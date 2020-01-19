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
auditor-0001	2019-12-31 00:00:11.598736+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:18.81552+01	f	11	1
2	TESTKUDOS:10	KYAZNKCVX51JC01JHCXW835Q7GS4D3EGD55T1VHAC4Q323VB8750	2019-12-31 00:00:18.906962+01	f	2	11
3	TESTKUDOS:100	Joining bonus	2019-12-31 00:00:21.888327+01	f	12	1
4	TESTKUDOS:18	B8NF4E22FXF9DK445WYCG1VA075FVMFGQ319M7FNVCTQP99BP7NG	2019-12-31 00:00:21.976274+01	f	2	12
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
\\x4b7038f16af77137982b2b32cb71049ff96b5dd48b099dbfc3c288e78325028957efb6720c89b8b27ee0425194dbed0f58c5806ec280385714bac790ca51a472	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x07feef6154103988731bf694856a9ebf9643123187b9e68d0c2797b02ed04b3dd2e71b3793a5cb89b55a9e7efe382b299473977517f6b5128b49739934313c3b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x95eac193f21eae6befc7a83c9c24b525e52afec9badfc791d44db6ef7ca1d44ba12a6d8002e16c799dfdb93353932b1c9164b0f0033ae73f151e1f1c338cd492	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xeea9a3303269c5c736dfed0d73211e0addc1aa75195f16a51997eeef9023d3ee4f270788ec7e5a6535d5e93fa2469d8afe86a89c101efa4d4c8a1e6080b01bc1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0817432ed4c056a37c747e7db98f95018478c2a45725e8622550d910f1836576aa8d8a07b6baa0cebf3fcb1e1d9714084c73d263c1b162db6fb2b440fd34aedc	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xcb4ee0af52177fa78b473e7b4b9cc705b5a7c94e8ae5b046fe899c37424ee2015956fc91d756237e99bfc78e50586f0f85750eb1f0a649116fe99800fed46e87	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc6d357fe8dbb25b5b044646369e6b347f4c1815748e2eca78d6c1a78b7885bad071f2631c0dc11fc0b98044d1ce5768c5ce0dc2f6183e99fe40d57ad49eacedc	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x64ce22659373c1fdad8118b05b6a473ac69a2729e997cfdccb31109141165ce33462d89c53b0cb53c33ceac300e2f8adf26c3dbd9029294a1d4fd8f510518973	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x352a0d63cbe3bcc8fe0e913ccae6af753aecb954690a2752b75c6bd31ddef1dfd178d8fbc544eb5e98d62dc48ad96d7acd94cfab22ec390ac7e1f4a92a342c78	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x2d0461226d73bbf1221b8e75607bb26ed27bfed0bdea6bf710607295e0c3f6951c6efba9bea73c0b40cdc4717b2e22459764594d982ab57804a638b8f4534d75	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd056df5ebd8d608bdc2a1dbe64df7d0e31cbbbeac2217f4a030e1bbf25d15939092681d2027d5bb91e9c0aeba8448658ef18fc698044995bea5e48b15965bce9	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe42ff9efa0c46f82233d2ccf978e9b556c5e60c237d3b841e7904445c915c392f1cbfae100cc1df9c8381648465c5cb9610d4aca6c8e16026a36f9a4df3dd43f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x83ce739d72ad803c9a824f4caee7163e1edb80a06e657b03a95d02b8fe53dda7559e399fa72f30e5c3fdbf609635f5a4d8f551e66e2deb2d12773cda2ffc1760	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x49d81784f6588d2a75c9bf8cb10fa5924e03b53bceda279869f51b30aea57664b40f8945ff7c5611ebf52910ccb25a23ab82e46eacbb3b8d15594b0638e085c7	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf72699ab20526da0af166996252917f069a79a8d0e7a6868c7d77218179b3cc9581e450b3b892433f69c17c58bf876861d6f512cce8363ff13a3789cf30a1a49	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x470fb0ad50d8a3b75701a739b5d864fcdd361785f1e4a76ecbe91a568edabee576bed84b6c737ecec7806004953195fbfb7335905eeac5c7db2d4311f36dfe8c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x58b82e13e9b770fb287289d02c7200f9c939809ca016a4eec6744ca102c355174788ce05b5789ef6cbbeed5d40291919c530f9dd1b15c36985cdc32651db3539	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf99fb6b4f03d2e48a86e9b311d187a76face1c0e7608a8b59e86fa035a83bcf24fd8194e71369316f70a5ac3d8eb49bf90c5014cc73b304e8a6c8d053865f2f6	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x30da752fe3b21f6f5a244943b6c2d3b6614ca2fe0bac529353539fb2303d507e9cf0301ee3f759ed1d648374147d6965d4f362c3e003a2bcb949ec4a16bb41b0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb490d4e6af6e0c2a1e6bd61ecdfc43f0ac2fe84efa498b6a764a9b270f976582dee277347c35410da553b0e7e997cf69200110174226de79de2698a08256be1c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x967619f31f53c642eab1255960d41acd87c92d43e3cc05932fc4d3fbe27bcd1c9ce26122235c737072f44476cd442fa367f50546b586fda7abdc475b41806ad5	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xaa07b8c187fe38df5eecea580ea22907aa3e770ba1f1ac4f2ec20631245ac1212d00f2b9f763f0ce0b3dff4228e259d197de000497e87baad4d33d19149d170d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xcfc732df90166bdaa1a25f8cae6b212cbfcecfca9f151e202fb6cc495b2be8ebb8aac368c2e66dc1f3ff443778a25ba06ff75eddb1a80eeab60b68b266b39abc	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xefeaf984d570e942e70cc1cdcb8e9bdcfab55266ad90a225377d7efc0d83050e04a9c30795efa2f74e34df8c13a07cd285495dc6da1abd58209c93fbbc9325bd	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5c60a56b2e0f56ceddcb3485dab8353709ce44c8ec56cfc4ecb2fe9c231b5544e4aa8484344d65c4a0b48aa26d815c888e84acda6710fd63adbe9a96753be19f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc0c68d21bbdbc521259edb71f4f2a1bb70bf5e14a40e18cb9f6b0f66d9886d2813357615db6ac98cf9e22290cadd72f8f3239d91d447dad5def1afc2d5c8d5bd	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xff082db7816b81c956b55d4476effe208ddde0875ea7edd20bb53085963e254e2727a235ebdaa1537265b43586a209fa4aa1fabe7957af223ce6ec5b933ca67e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x70fe355bec3fa10fe93ae0f4ae85ae3a49b33402ab34da9049ecdb62cc8077f34cf9b6a2e6e55bec20ef8afe5cc650da49ac9374c7fc8693864375cebdc7f095	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd80a79f63739c24198cff21c318de6ce4ca286a3b174a94e71854b879106742337a5fc7b9276968cf7a6fcf6702c683f44731b91b3f53b0fc14d05b768d8dc88	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x77a6873bd8499bdec57930ca910fd2ed3470590100c933c71aeda9ee69b1d42512c948cd6786fe202dbb8037b0e03530d82a7a1bafae0eeb746cbbf389f79c0a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x809541f7a20fc2847d32c3a5d9938387f7c96516bd6aeebb6d0f351c796a82a65a1fecf94df04291ae70f7e4a8c7fc0dbe5f26df7763be9b2032ddf2595bd9a1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x3fc2c581346b9c8fe62edcd8c8a1bd0175c3fc2693436ce8c05ef0d8236432846eb8ecadb60addc481c4bed945eb53647b7a8ed98da2b2c3a1351c58fae36908	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x886bdefc8d9d04b41fcb49fde4981aa122125a9c428182d15411acc29941609e833546b311e374a24af03f31af45650882f5732e3756ac1de6c928d296001fb9	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfc9165705c124932a55a38f2b0063779773676f104bca21c31594e6b109b52e3cba1876a064d6007225f241a4fc27dcdd20ff7be405d39778cccd7dff08dc62d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x39eab18fb8d96d3ab6228480414e4862ce9fb2638020d046819f9043fe0eb799432a8d99b11aeae6852efcaef4bf301d7afc79fc3b86f8753a9d0510bcf24b80	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd42c83707cb8349b91e9036f98c98f72a172281afe8491e6d982c21025de85c17734a592bce80f059481a98db6eb253ba18f0311752a5013c675523a8da6f297	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfdbe9555dd53b79d52122256f9c58041dd1c15bf4b8bfc7ae7f81763f096107e0f027fa9acab50607e3ce5d52a94663a3be5c98fe1402c89e1027bc572c2a7b3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x50841f6ff5d75e64bea7b30024d78093fa5d97ec7d336e2086a8be26c6e81c251b835ea0f85a125073c4d49416766068b7be6a073aba06ec5e12f1d1cdba3aee	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x364cb5ba7720b95f9b653eecc4556434808f74e1f95435b73502848be9832658dbb99e1c9c59b7afeded560f97a1ac32c5708467cca1faa78d6d8d12eb087539	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x6b2663c9acf18fc7bcf74c5395098c4e1c884e4eca2bcd099b221d89d28522690732d8915e705274b69199f1b28da5126daebcb55b1e3f3c96c20021a100bfc7	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x638a9858caacfce76a8a0e689f4b68c2978d207d3f38bf711a74c66cc7c260f4b34c4833e0b913d4b8b5ff7c8c340a7f61073ac0fd6d27d9a571c949c874a307	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x8d8bd9b869800a03e7267cbc6f74110b5ae61465db50a680bc7b774d9c1c99f50edbc421235fad59182ce9b02e566541d2c4a42f13f786a469329ef24736bc13	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x9ee3624ef94d43515b257f13efc373c3e22403600903b2a281fbcfbd9c5e435b44ec0b02a2de385b263a20c2174aaa2bcd8bee2941afc4e497435f539a30400c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe2244282794218a42f9fbcef835b5b9c1479f439b56da25528e493f44028638c1bcad49823f491eb379864b000efd5e84733b37cfcfc09add44d657180288c7b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xca99e541ac0c8d8467480df0001a2dfa9190d872731771afcc963c03240ee36fb7adec18e2e0c5ef454bb1db65631f8d59e57025f2c018440155d958f5165f8c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xef05b9b5c32839b6ac9a80d8fb7430cda741cbf2dc55461cdd81d6cf986bbe0f0ac97f347717b9699baa6fbfb4368743598f2071bfed80bd13be068b4f686856	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0285e502c08c226e5aea17c461467d4c8d118c7cf0c550fbbd226a6ed9f91a8ddf3de40f8907cb2100672a72706c34a011fbd5f3b1763c2911ed285cc4dece70	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x110eeaddaee1d53bd2ee0140b97f477563ea5e9f1c8d835dc33f58936ebeba98332fdad5a824a27bee134284e33462c343b86a57fed6f27fe2ff9bda9b1760ab	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x42f6044b7fba3db18b1fe671fcbdcbbaa6799106c0375101a3a9964bc1d7251ea49759beefec44aeeec4a5c49003d40fca358ad7a8493d61967fcdde7a459be8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd79e8fca918e53240c50f33aeff4159bf88af8e1ab7a652a3e93a683a8e12b050968e07fd47fc17747ef7b73b5376673479ac4bf34d96b5d9893b98cbab0003a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x77bd4063afaf338e6d95bfdf8fbea4e609ef3a58fbfe778b5bce117b71692ed46fad883aad3ba40328a69b1365c538fc42876a0e45c6811bc57dad8b4424c53b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe23cde1eba207a355b3b9a4b5614a4b67bba1b51e06734451bdabaf995fb450331027ae513db1004b5ad2ccfb901e4537b65b4e22edc7c63abf6e18a2ad94dea	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4c78958fe84d8b16301984e4216735cfe3c7bfcc3ca4af691d2b6488d12acca0b0c273bb98fa868ceb6b92e1a7c10cb9085421b80d8f536f491c90c2415edfb4	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xdcafee4a5d203f981d664e5509ec29c92fa94b0ab934573a4c27f79fed05e700c6b67974a38f0a8169e7e05944fb7f0a2606d2b8ff4bb5c281642ba9b4007719	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x9df0c9d477482d88e8d3fffe9850fc53460d33ee9ea5f7359fe164a3e6d2af5232da1bfc4d227911ef899c49f7ba64297d0192bb072fe2ecd0790543905ec025	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe5928f04fc6623f2a5546f2b8554aed20f75eff493983a392ed584e5a0e753cd163eb16c256f28321e117c09ba15f805ab000f883742eea2aa0c4e36e5fbb643	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x065e910e667e23d18720993bfd905c1279e0a852c59087c47376fea04b3a428e0b6e4456256e0619e7e48e4b9e5e44180428114200445dded9f535bb0290baf1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x2020ba9002885b68267a0ad5e854a57d2f5f04716434b936f97edabfdd03808a061c6698e4d7a7da12d27b421936fb192a1a3d1680321c644c199fc2a47545ac	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x639172dd4b19b4946883da29474285cfe434b84652f1837a92fc0757f66706216949e37a65cda920ba47cf0db1825f2f9abb7e805f2e7c0f4bdb747dc054e697	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x1cb34684679c8b4b1e6156306f6e495c02b9abc1704dc71a739f756a4330dfcf538115476f565fc0c0e7da1773a2a986edcb4ca51d9ff562dd088d6ccca9bd59	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x7c4f6ccda6106410dec257773c29803b8f79f13b4521e3e2be7bebeb31072e0efc91d92b32eeada159e640fdc2f6a5ff4e9de4d865520f93d53b12e7bd5e75df	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xba12a85a72247fc4cfbc4c6c7331463bccd9c62313c5222ab915856cadac04484274f7e33d0719daeb0aa7f7b638fba1483d258be78d68f8579651448e790bf3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x04b6ebbb4ef6724f23182b64ed2bccbc910d17471f298b1dc7726678bc60cc4fd3059ec4f48a0bef7ffa5dab47f282ad1ccc8e5df8346e61ae7ae116526359c4	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4698b54cbc451b8014a293f53de79e19fa489268f68e791d459828a73dfd2881a5089f1614be4acc840829fe3651ab5ce17c399f6d362e5cb97679c836ee4fa9	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf8c85a5a0dea7ec4d5b811cfe281f0c1161decb9e256c9feabeaf193f5d98a055fb1c6ed13e7d1c147a79fe4cddfe4206df831adf18bf0f5b2cd70727bdb229d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe96c542440469a0c93afd29d224374614885dd3fb3333f75f8058a2a15ee0dc4308aa7a11d0a554334ac6ca7261d6f83ffc3751ae710110688f17cc3280c247c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x32c060fd8356705fd99d02173fda7bc7c5d9b0fe782afd71ad84f75acdce927d244a84c1e49d08681e3724de24d455c2519935e4bb4c502aeee7754a6a0eaf50	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xaed7a8aaa5e26d23c6404536692f48fc74218ddfac9ac0e15b5c90e1a06ee4c6ddba61a22a13cc3a582c5b4b3a32bd5ecfb6bf1006972d17844cac280107aedc	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xce5bf868d4404d1f6658e8496afef375023a749346ba59e0c2642a4e1e232d0ef186fdf6220acba359b19762b72558979dd8827c3cce5ec35b88ded84517ee87	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0fe8bab6517e435ce7e814383c1b844cc8777dd8ed4c90ce0b50d066e2284d7e83cf921f4a45a5857af01d456d20523238e76e4ab4b794d4b7987ba52ead935c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x77cb8efcee325fd302e6b0138d16da2962df2898f5612d6a7c8520c81407bae6f226be5b9adcb9e7dfc0a5943596f9e6a323721faedc64f3aacc9bd2b26e3526	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4c5b2b02152e9fdd52f6ce623623a3ea78ac98df6313735cc5f31c3199b23a9b41c7eec0eb40e3d165e4ced49330157b370b2334d9a531081e3b74724fe2a2b0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x954619645284c91ed00d660dbf75653e939a693a98b6941d801fa804af918e53d6e403db109e5c96740f3a8fff2b38a72a103086985a42b3ac761dbf9625afdb	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5127a0c7cdef9dc6cea133735e1d5f9bc233cdcb6c94daee8b9f7e626daaef7350731d6bc9ad8e27988fb6d55951b5e4168c95ca13eb685cf324c7b4fed64cac	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xbd6a512e4d41c7a0fb3e0f5c660956d12d442a01ef41ed064815eb95f790cb0490bdb9a0849c71bcfdf9842c4e85cd13f24363ba6ac25adc4d9b245b7d389f56	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x1d694aca169b95d0661c1c6771b3b1e1f5680743b7cdc3bb5fed39e4069dd54e15d28140c2707127ff9b1a23710536134d75a902f19d187bcf650b95fc7bcb4e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x41ad48c5c4212bd985b6bdb3e9e5ef090b112277406423692036bb2b5203769f260264ec12bf73d45640114df124d6c73b3ab050b2d38e4e236930ba243d1567	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x99ecf9576a1ad70691c5113907c7e97d36172387de8c4dd6e627b0be839a536d5df7ba5e5934bab2121e86c0583c11a57882aab281a66075ca52f50206cbfc36	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0594cf6d875133eb624635767849f1d7d98166b89e668779050c3401708e00bfb8a77baa4564ce6f9c2f8740b398bac751284258c1380d11671dc4de5059cebf	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfa3b44baa3a4a4a9341fbb4e52e15f8dd113362168e4f87854c1d19cc4e638aaa3c894c8b8fa24860ae9a00d504f54f32c4480b68fac0c3b69c395b9946b4c88	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfbb2391d672094896aca9a0bfce8eae421f92d68b750ebf6c4d8a1d02145f78c876744647fa5db2e25b48642dd177eff2e0cd525c31dd8a5dfd4f7267782e60a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5dca06243dbddc6138e2c2de6498f1a0aea0c09822975ea63bb3e97c188e6500930678ffd2afece25a31fa6e8313f1ac33b2d7a8f81899e4e318485883f28255	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe2b8702b9de07b84021795bb4956bcb76c77c74a8a72cb1ba0e3b90db69bc08fea4601420682bf7f431f2327e5722ad1db42074ca2bb0783af15a1e29d66620f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x3ec03d72b9e4866194501e8acb22e2c5446ff34ea08c09b830176f91fb3d641db5b044d3965583250a1804e5b5936bc4647224b22417fc37522a947bb2c67fe2	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xaf205f3f9eed6c8fc299e5d3b069d311785c910d69470457f29ab83c45c81f53390c2824024de8483f42900a7d57c1698035059e4e07f0e67bbbf17c8beb78f2	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0032c4c4ef5f62e6c8b6d305c97fdbf3eccb06f04020aa769889abd601e8ecd766cf36107392ba03b6dce7a5b074c04312ecd267308e9c4023d84ff2407176a2	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x26be7fff5a953cd0204d0bbbe706a2fd50e5b58e731e1c010dcfd1dce4690e6fadf6a868f49c38748a68bfb17f968baa9cd9f939449e108abd7887d75fb9eb51	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe1918985390d4119edac1c84487e95d50754e951abdef03d2fe49f33f3eb5b86e8032a5cbdbe0ee3108d5aaf560187c1a5c52aa0d12f275cbd28c5724ded0adc	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5a28a0aaf8d851be044eb55dc66b781faf72b260347fbe2515fbb1db852e72d53f0e05d673ed70cf2e0b91f06e3b890aac1af9e9b1629684aa5c75adbceebf28	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xa063fcc9da096d2bd3cef70000627e5386b1690254be4e2b3989ca2940d562d58afa2fc49ecc2d17ab63594254cad067d61793fb40c216fe616d4f62849bca71	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x1f437e27786aa0e0c6ce46464442a185544d3cb8a862044bcad3a509042f71e24c29ef3a77cfa2980134929a249ea84559e748dcfb504d0031b0bd62dd5ecbd6	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x618e4157cdd6870804f1a6e61e456c5670b535678d952e9e65e2f525433e61d6f6a2fffd3d20395a68ddcba3e862193ee9a7f3541a74aed232543b19ec43dc9d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xbacb2db46a54eed95ebbd03ce535b8d004a7542191978baff935eb7a74fbe3b63fa9354b30b3e9c5908e47f9fa339d2e30870cda6d226c77d889e24552d69953	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xcc58258b78418316367e73cac9eb00fd968b83e1820f140f6337ff5909237b737de6d137b803e798a4fc74fe556a11be5c58050b44f68b3c363527a84c5def71	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xad9bf71ac652fd2de82196816454f5330c3a56149674798987f042f81a878e30b98d3110e3f80f26191218a2b6e9d971849ca785085e5f2fde1771b3e2c1e5e2	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xab27c22afbef6510e7fd2a49de1ee46aabf16eb8e29218b35fd80c02de12ae7e2e7b1fad39e603602b4c47e2a5c8295897212d44dee321f6a37c997ccf531d34	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x133dbd4c995b932e04097f380f5c46706e55523a9e05a3affceefb56e9ff0aed7876d5e5fa8b89e358b5ba0f2a59f95aeb7266cd080c477aea7071e546b8e05d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf057896db423d16a0e18c9b0d676b3d48faaed5f6f954584287f0428b853fb3b9851e870eccb21cc58818ec8ba86c1a81f0d75975f55791ce5ee647a3cc9d3cd	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xdc996b9ea6154d1bc4f9f3c1da53209f6744ec9406838549ac14b827c63443aa642cf91e794f6c14345a8669e247016b3b547c5516f75dcd04662ada9623e570	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5de21c71a635a9a9660d595afc1d9de3aed810e04b177cdd139188f3b6e06658c5507dfe2f3382ce9b44a96ed583a2543ea6cac4994bd2e471f8bbd9e2f460bc	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x192f06d6d6f9860d59e2748a782110fffe4fdf61395942c82102b6c8a68ecb304926eb98eb1bb018705e0db2a175beb9c5c2d363da1691c720b9b0f2c08a55cf	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xbc88dc8675825cb688dd888e5b382e0e828cdcd993f40c3a63e5504d8b1284fe4fd2d9a43393c81f81543102db0044529fde7f5d0c5a3d71c7ffa4acf67c9a88	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0c798c2ffcea527aadd0b62d0851fdd10410dce01347927bdb6bd63310449ffef7825da19f8555b243d5253b986a73c14731b11a81a8d36a319a86aba69965fd	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x26fc4ca650b73f4704b9bee01fac44cc21620e16edaef53e87ffc8c72921c9ff1bad262d573e76d6b63b0b4c02a25150ffb5e4604214d6e6aad2279f7e910607	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x9bad468e70aa48dd573809b3bce9c46a6f0cf0163dfb2022603794093565a8078b63af1d531c96fa09611ea04c24eaeb5ab22a5e734dedce407734e4d8000a08	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc509b89fc3f1f64ad39a925b580dbce0060c87ad579c83d649f6f74e9bbceaa6aadc9e2817ad9e66d7f14e1ffe328c33c6593c0a0071f7f174816df459431f29	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x3a5bf49a23f6d68f451824dd121a90b76cbf88d95a9b2c856be6c8ba780d2cf2d96c39233658a51d73796ee53567ffddff4b601d795db90c0f3fb1630b49735d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf98703c6279a47a41473f0c6385e42a5ea92db9472bb6da97b1a04fd3e8b37316638fc35b81244b4de85804837c4260cf26040c1705f2ace4f702f74ea816810	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xed608c06a780ba9ba732516daeb5d734b76fa2116931a3b6c62c4df8d3d94bc4fadfcd4f55c75bbf2d07577da92a3be6a3c0e4836a6945eae79b986c841a81a4	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xedb79372f8e5f38d72cb2e1d3382d39941c86ec0ce6086393b96b0c46dc706e5137a277564b1b28fb3616784caa114ee8ea7c8040b63f1036b188a4489b6c4ba	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x15a49211d4f08ede48035edb878d9c4c582a3e0aa96feef8c8cc90832d1b670f3d906844cc4481d51f810a802e2c68662e8ef9be00f6bb6a6bbc5c3e8df1d55d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfda4b08e2af8c78209eb5344d7a044c892757bda21438db920ed49803470a42187c05bb5f365eb830fa7f38801a6855307bbb7d14f3f2d5959450124d43cd711	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe33a97513c43a5bf2b66d6a0e4aaa079bb6ee7cd4203cf946e00129f3bf21408a14a7236c87098b119addcf7cc9a9c9b27d46796a78cd014b99e8594efad1960	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x90232d2c40d6eed26516e0b0b9b9ce696c85f51c2bdff75646ed32289d9ac2c708738ec8beda963257a18826456e5637a895c14acfa5a8b3f15b703315c5c7e0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x2d97d880088a0b0e9802506ec7002d24ae006c23be8c1f2a480312c9e6d7b5decc0431f9150514561e9d7a0a0cc384caac133352b5fde9389d856702e61f54d6	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xba56990c66114d2be9bdb313d398afec43fc0917bfd38614ffa9da6309d96c5364e9c1a244a2b7bb88dc0caadb883697627d5dd1258e7a1e7275d89560b9902a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4b1e67e13ef47bbfc5d1042e319da85052976fb552a5767edb3f78a0ff43789466efe9ddc432efd2e6ece510124f2c14021d4729ea221360b711255626de621e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x214eed027f1a6bc93487214adb7301c65169febad2860895c5414dd597abc0b34c2f5a2c62433abbd25a4e2eb45291a0263f2953a2180fb3a539b34b40f788da	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x938231fb32078d1113e71bae3d4212daf8f447c59b5e1d5cd8ee5115a1a596dd027ecac0f9e8295890bc67b9533b1b7e34a1f3ee2c08146abf09fa5f9dff30ee	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5011a49805797d4da015e8a57e6c2672fbdbe8a44e8500c58090dc342aa037893e64b0045d713f7619fec1b8f735a27e16047f4f2f1458ccd6475cacabd2c969	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x8f82df0de77da09967ec4000bb978756c06c87014e57243c75c489661bf165e75d826de4b2136a01f912080f7a2407363e359746218dbda8cd330cbf2b9e153c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x140d63cc769a3d1d46110fb07a0811a40aad66c94295d0ce3d66077db5faa3b8b709d04942508a00f10d44d40ea26307b40495d655d9e7c951a182030e4c6dab	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x618a2d72b93bc5166c1adecb300fa559ecc86e7360bf8ffbc676e0ebb37d4a6d044ea65025c31b0a4d83cbdc2e56ed717bc20d021e8a179d85fd2c6a3c3bc47d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x27ee6f73448a5bcc6949aac9ac2fd3c3995c93f42f9339304f3afec807b00a267c4e2e2d7a1a481e48c963805bcbf744a4b00406e0d0581c0adbdf24ef4dbc47	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb212496be0dccef30915396b0ce564b2476a7e3c36647781a23afbe0bc3eed1702e8f3ca623783b30377fb66ecfc530ebdecb6685445205129398674d32495a8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x9e34fead50f0d5179458fae2a4060b64fe54159d0dae17951f1bcc71fba420ba1cadf2c72aed7c48cee2356cefb693bf7550c0aafc1c8114fbf46c76e6fbd647	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x04f62c5eb83bc7a1756f938dd0f0c7a7a042f2c941ee3a055086b531e736a8c1365f6ef0e0994b4000ff2104d3caedeaaa67414839bc9f0ecb0f225504b8c18c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x1296125e47bdc424c5b064a83808a85901f6be01a1fd844e233dc66906e68fd4996a044ab314abb7d328a5152757230719cac43cd3935235bbe3adf6c05a7391	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc0206c0dfc2cc53f54ddd7651aebe2d00f6a15e2298ddafa35bc12a1aaea25d4256e4d3d13edca9cbc3e7e5cbb86d037feaf9295f9717f6c92b142719a08ce33	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x484097fc6c2f0b1e4e47be7b47fe5c6cb94f57d3b7966085c5fab568f3f2c4a4f88f6b14a24b0c06696dae881c893c18e68b32aafc31037fe325f4a26df9a436	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xcc8364e13d466ef7921e557ca72155a955682e7728bd9ce465904f37179ed3b5c55bb13a92fac37f9620fa56814fdf10fcc0a074bbe1901d02d512dbfbb94f2e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf775ad3565bd50444ebc49544d930bf5b209254440b076b739efa46a2d6b7e298a14a791c7e56417e56a958f38fd114ad7022d129853a16c23e937be97f3b726	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xa3e728aaf177360a81dac474f1e86aa3b90c0a2c430c433f42e33f9503f0575c2ff9d6cca5dc61c4740d03f1bc5bfe8d2f0f5f4cf2aae2968f0211ae83ffcd58	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x47d6de896f9538f1c02f1d33326118dcd6e7645ab9f7a1e0acb56a80e1c742f3e4a9cb17ef79419f454dd317593ce5521abcf8d9089ff85a6e3e818c4e98db9a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb3a9043ce1bebb6e5dd4711932ad3184818c68c46d37df0c3acf8251ce121420466ccf1be230239fd431ca450c8cb58f6f288a94374cf65183714b487aeee0c8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4cf3fe632d2212cdc6424b52d0d16c755671d897484ebf857219620687942df09c66614b4c3050432f5e0993d47979eb3820a16498181e5bac39a49f1742e58b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x34b07002cf734ebd8ccd77b3c4aceb710180c6d85ebd42c4ca95114c80a9a768adab20b7be9d659a36c45052b513230dd8cf9bedc8cf283110a92bf998abddbe	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd4aca9fd543385dd3bfc800c8364e4d8b191e4df2270b2d3245a103d7f1624fc8eb31dee9f5f67336afe643674b501cd34e3c99fe196195b2d19eb3de6e6ac37	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x893392b943158a08eb79f28a0829f3d1f9af5bff4999258f6593ca6b955f8f447030f429fa073323896e0adde6600b658289d903339574ac52468a734a7a3531	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x07177daed4adebd6361b911bc7fa152ff96101958d5c86f3b7072a14d06fbb1e74f064a5e18a46aca250dee7dfee009483ba2861cfaeaf70f90497fc3241c85d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x43dfd83715e173626aeb638f1ba7464f1db3d0972fc9bf37fafce42c1e98c46cae284930f2b8c8ff27aa35d0d1b27449e1308ce1b5960cba06b6fa568ee7256e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5479d57b1b399ad800170622156c6b90610e53c5dfba1bd1e348a51cb20b260290f69f3cd46938a41c3999dbae1c7faa8873bdab1f6952c4e4cc89ada1abdedf	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x36dac591453b74c738fa213924adf32d441c4d6e72ad1eb9b0fe99203cfae612c09e77936d9f9729feaeb5cec924feb7d1f2d2277a64e71f91b2e63943f07f6b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x831e323913b052753ce35035ebbf44200a34f89f7323744bb8e07edbf91ecd516315f1ffca5bfdca42b308471218b009d5645d3e72b51881f999a5073ec3d980	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x09d0273c8a326b2bd2d6698587cb1a7152349d08d1504ad60786b0184fbd1d3607b4ed8d97f0a2a8cf6f26dbf22ccb905becb4005b7e9e013bad4dc2783d9793	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x3ca86d96c81786c9ab68ad4dcf333c8d1896e9dc61f06151198569b2445889630638c98d83df75b0b2d56876365f793ce04ef79100d385f770f5f5d636d5641a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x807c5e13d515bd73144c8e1748caa6dd1687d18ce89cf3ae45198854c0e6d28849ae5d94d49124be300be43c9ce7b3b583e8b530c22835122bcafa572d0e76f5	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe7c1015ed18712dbe1f4806d7510886f3c8e540da78fb67021dc4542725bd6934767df1b8e3a45c4be455b72e2faf3268933b71fe7b500f4309d2a23618ffeea	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc3ad0c7781e78da57efb87cc9e40eb523d6df4aea6e9d31a40dc0b2b14e0c2e8ebf120c6c2c73f47e35e64fdc3e57bc52ecd0a8a064f6e311734626008e18f0f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x43bc07234da0e4a00d77b768934aee6d45dff183ab840889052c7c9b12cdbb621a99fb53697e50984d15c4994faee94588ae55982dffe4e473d19774338953c2	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb0d8de634b807039221341453940485b637221955f2245bfe8519c1327ccf928a0f3f286287890680a349ad52b9d536225bd46bd6a520176217cdfb2645d85c0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfaa8fe6dac7a5aff5f5271a76bcca72fdd20fe4ef8f2777ed5aae58f2fd981d2ab093de623d13e24a20485abc96d2d2a769fabbfd219c88d5d998f36270093d3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0f9847c3ea94bb67d23fdf6a1e253731ee5d5ce6eef9a1185625ad9003b99f1aaa5a10d01c54879eb4f4128bcc33160ff31204dc1c4dfc0fb34ff7cc22249afd	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x7cb8fae7d1b59c202ca23bfbdf3e44331a79c7d88284d5566ed5384444be6fa2a8690cad1df4ee25efb8aa6b76cc6be33ab33765bbb62920c930a1a8af096412	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf8dce992af77cfc0d4fccece091e44697a5e6680ba95e0f3b783647930cf5a22cbc41c0da68a011dda004516b905b0fd703515fc57ea074faafea90f105e87e9	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf248e0730c0dc155cdf7dec996481832ef50e2fc980bb78f832aa1603a55e0322ebc88ff0426638970cf43db0b0082b6c61c60f60881b4e65c87a90de009ed08	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x9415613defa955812c35d3f40aef43a93a457aa615dd521b0ca6f0f7ff22255fbe13d405143e0d47a047a6a37388827c3f8f467943e6212aa011509587ca8f38	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x025889612ccf8c1c7d500136649d6131de7c5e47d7918f8eec7fec2587ffeeff713a0b8d094a887194c7bf072e731472ae553d596f85f61b3449b2c2b55937ec	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc8d106dded43a05b9e0f87354a594292d6a54fb887fbca5b30fb209b0d4a0b45c43aa97e70eb8efcba937e1225fc3d62d0dbf0937881d9838dfcf9de7a2c422b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x21817de52de3427032e8d4b60482c67979caab190a0c5276848bd269d3f4cc6af6e4888d89a61e57df1e4b42cb4971835693f1f95536322e306814fb949831d8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x64ae2543dbcd5d79875a00cf799ece55d83a310796d847e306bfbb8b67f11770dca23c1240397b25f5ff6f124ba52989d139245bc867e3f593aca1457ff3e373	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc4e17b923eed8b391ba3f72dd7c43bd4f2df9fd93d2c7c491a0e79dd3f69593ae97d8c07643c42f76a3fd078e6170c01a78e9b14deb9d120f29fa5b10d44fee9	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x732ce991589e420d7ad2e8aa36ebaeb5b5a12be1857f384e9acb6a065e6a12659f68af149f5a708b0711c9a5bf4a90bb879f486a6ac5df33ff5a89dd7890e5b5	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4ab1b6203129c75d5fd2103d4bc3a8de8a7ec378911b8f17098636dd9698ee9ce5ce8fcdec10a477b3686f06e31ea8dcd25d770feab62e1b93471fa9ef5b5e16	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xbc15b6e0dff4f5f389f41ac6ec210888963e19c7a45f93654f710f0db2ae70c9c79bcbe63c627888a5f025c66ad586a044d0288b08af5770733bbb2cc6817683	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc7c81552056d3c3df38d7d9655b32ec930080a5fbcd8a72833d0cdb41ebed8fb8d8337660d8db6fabd1d9fae828702e356787b86de7aa222432556d07acdaa15	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe115ee088f9e92c7deea74ae40650d14e81940393b583dafa4a5e002b174abd2c18200d3fd156d9a88c583e6213301a61d06a468faa66972e96da8c05e134cac	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x84db2f172344db592e551b9dcc799e3d5973a3e81e35ee09890a0f3a6d81ff6cae382a9ae44dddd9bc2d2c7f8ca5399d7e11afd0bb711d0d4d1d8d611cf7704d	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x16de84a4dd7c223ebdb4be6ead22643e1a5d21d998c15e5433700b1ae2d89261ebae2a16b4d6f238da3b849af823b4e084cea29288be81884d61d426fc6fe18a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb4ca9acd6a351cad8d1441cda2dacb05af22ed80ed5c63346edc9090a0b54c5af6060d0beca1020cb08cc1efc617e689f19c69a78c11199a7aef8fbfc8d3965b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x53ab5c6de398041ab64fb1ad29f5930d7600a041aca91270b2e96db3205ee8d0064bc957d828d469c5d15d17e4b78b4e9c75f9fce093efe0a4adc67dc73bc79a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5e851c0b26260b199f830c11f24b10b9baf38444c72b9b2a10d145d7ad1565d8cda30cb1dccdb2340f1b078393bbbc17b45585bf3e65b1f2e6edd2138f6ba740	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x1c59b5e050a18a209c9ff5d4164e906b27ccc91aa01a1f1d4959792e4228121fcac302149246f72e49569850ba74faca37b61025927e0ab11023b0300ab8951f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x293a68dee9e8b2b1fd3ac3c20af08b4b740d8001773b1fcbba09f9870c7641daf930824400abae862d764740865cea5c2d96ee0d23f3e1a42ca7079a36d5d4bb	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x7c82c6d183a0c774542aaa7c4d7cc9401b2d2226a65dc715de54bb28e5d572c4740d9b0203dd2101a4706bc24c77e35d1f4f42dea4d18e73c2c90e6709fa5ad4	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd2bc288d44aea2c23643577b3733799e812a5dadcc55169a68c75c7b3df25d6ba0188896ac09f74346f33c8de60b7ddaba95974de6b26092cf9727464aa55d4e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x7703cd18beed3f7925904ccbcd10a66d21cb57422affc47a86e8feafaf72245ef4e2883ac4449c6072d8c4182a66b6e123d03a7257ffe91b908485a6c0703424	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x972b4183e4ccc23e5bb4bdcc1337fd3cfe029ae05ca416b1adb8dce87cede9d6728fc9f5e8a50182d81b37618de3da679b57eaf7a52e8db5a4623ef7f94a1124	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x862939030286331ad8dc0600d429c18645c30e81982f81f7593621d564dbcff97712b54e92775e6389349b7b4350776df5d652666e0123ce56e64ff6d121fd08	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x2399b9e5f8e9eb4ebf11a1a893b3273435c7c305ada6c6014c74c4abf0496e2fcd93297a1e22ea550163d10ccfc703627f87feff2a361f718e8efde100f6d044	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xda3c94b151e0041cdd37ad20a273a5c34a26ed93267b24431cd26eb7dc1e389a2a9e7f09bfe00ed70b96799bc45f7149e4e18a61fde908f3c1e6454c5e43f8f3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x061d893e0b0ebe9fc106e58d319597d92b3d152389cdbb6e31861f7ddd9631da61e4f61d36a16434fa0bfcd37a6f91796cdede4f9e7404b73b2191ee7d2132c5	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x41f1979351f41b2d8155e2ca925d20bd38c993d59c6f7b501b71e2412a606108ab1a087812b81f1bae543c37901d1641546eb22002b00af7436147c8d7f338f9	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfbeaddb6a71686a514a87e15fef9fba984abaf439b01f86225cabac67fde70454316bab7488ab9eb8962eb6f13bf5f48fad96a96578583e592156f887fa34630	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x36adc1138bd9fc3ccc34014cdcddf035463af27c87702f4e255360546f067f2f634745936a7006dc53cc9d835073632a10717c9921b6347cdae604ef36cb1a13	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc01e6b25e9183c478a837b408185982d16d8c7ddf858f3d1f2194dfc86ddc59c941d54de68ba4bd9b2d01589e09291c58ee92650fd64c2175253132aebb7cd5b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xbf1c292a2d9813ce2b5e0741ae3f8262d5c154474eb64f46db867e904962cc659697ed2acf0fb257c0ce1538dac5e65a4f2587adb0e13e9bbfc989925ca96b46	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x1a5a1a058483b42cca994be4ff25f76de8bf8afe03331ec42b8153559af037a923bbd7e3353fee7f479ff421e3372d2d61cf5619e437d6e7015b044d54cb7fd8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x77f695bd5642513ba0ce46fd3755621a535553a70aefd3c7802533dcbd73ff99b065ee755719edd60044d9b6721ace49aa2f1a85082b3659bc8d60a79364bc75	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x032068a402831334d7fd28f94b1006f391f01ddec21ad8261a52a5edebd0bf86c0c9bd6bde3ff3daaf14d73bc04f903eb1d7e01433b5e64e2a537e52223c187e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xf297ece6de4ed7fedf39e7c7a23f245bc8266285f0426e92383eded08cbf28b7baaf2091e31fd50c823f0f5ec4a5d6ed118320026fedc9c830e3a9cd591fa023	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x529ed2eff089e2aa7511510cf418817ae4e1c95365c700353467ba3e09f6e8dcaf89ea9ab9e241787fad1d34ec6993c3dfaa11e2a9fece68aea4a54ecf58ca79	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xff3280619fded5dbf482030e4ed1b2e6ed7b02e3c33db1cdef2df3b09071cb1ae740e1e9c494658beaca85c46d78c585dd57e6c28ecda41514ca35d887e83eb3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xa17924be0cd7d95ffbcb514d25d14f23a05a7a1196d07968e51467d72d98ceed4dc46ed95bfe150811b051e9af2aa7fabf99d461b811255a51ca78adec65e626	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x81136fce9b3ce755fac2e67ef24bb185ffc83005fe2035f7ed43f920d17890b1ac65119d99c5a195c757dfb9a279d339185da798ecdf021a96b780ec6917ace3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x6eedd99a286b172a7a76031e12d3da50c5e81f38bf6d14059eff82fc1ed1a1c5991925f373c0ca643638eff376115d05426eea7603019a240696b60ffb2a5c1f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4a7872aa17fa982a44f5eb9b40da85a5d848336a9e204cea8f6864082275bd50d4f579716aa4b6dd11752e5ce364ca13b8ea1e76a0f868683e090928ab4e8023	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc452a927181f644e3a85d74899c29a5bdeb46b3fe1ac4c4984bb7b73c4fa8810bd8b7facefad19c706222b87e22836fc81fa8da16b78a211cab792c18b000a67	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xaa35d8f91cd2980f6bb6d626c81b1e5b088c810b23b2e6df9a25c4757f42271937e852c3bf1c34a5fc6c9bfdae2df9e8e1c85a78812fbccaac02e58e95b4036c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x800d0137c34f58834ce41307a1f8c2809545e1b8a92d6d58d6e3bb2801f92a7ca6e124cd7b6d39f6809812fac9b79a949465d7731a35a7a34013734d01c9ccdb	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x2219c0ef3b0bcd5ee513a265d917a6c09165ee00d758eaa7b340e6b2fb4641e64c3c64f3118ade7077d40530c70412b43624e0b88074f605670a26188b68f556	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xf8ddc165d2e630fec77cdfb9e94a324343019248d8201f3c91aa9a284184824edb4f55b9dc20d942efeca1f263970778b6b956b4673b14cffcc0200ec6ca0399	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x16f92a6932910c66e739487ca706bf10827c01cdc4f8b829a177c1759e1b2f18d36da93c56944e9091ae60deb81ea1e78d94549eb9681e988480583ab8b89be3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xb676a69491a49552c43cd01a89ccc03fae023459fe82a0d5a95f0f9e2de0921ac486db9ec1d688d96a47b77597d69c759ee5f516579b17f4f4d01b4814234bb1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xc6603f2070dd2f5c02d3513404e69626fbfa54c0826d7aa5626cff3492898581aa537c3200bee516f5e7def4fa7d208408c1691778bf34833b6a099bb4279e26	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xc8822921fcc8e8843cb49e389ca25f7b79db26a3fedea0a4782988d3cee901bd9a4aca58a3e933dee4565744da1bed9f0d2f9469d1e8a93d0b6405dae7bd4046	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x60306b792bbcb382b791070ad0c8f81802241ea24f5a29f0046389a0d38faecbcca7879ad185fc81363466c3f12259edab1723e8ed5643bb0a55d7430f9b85dd	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x26d79e7048167cb953756236a0d7fdca0f71ddedc1e0b56a136983c8b41d15406d1838a884b9a947a1dd57233e77bddb1e9d573bc0d6b1756e15a1e377dd50b0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x32e6e54a63b2d6242b5c0cdb1b94ed274103889d97a5ba44a203c2d96cff22a8e40e8adbd6c04b7f5ce50c3fa8b0d6e73a68c038a75080fd6b09c80fa3845ceb	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xa353466282a28eed53630c8eada1f068de2f76b73b385b7421c08583daa06b7906636a3ab3de02f1d7c7b1036e0d2ff7a9700152c1bcf2612e169608f4af70d6	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x8084eb5eabdec5b49650ad80def642c01ff6fbbcad4f3a947d1b0734deea25b89da20a4d1ef0282e73915775958f73882420214c115422e20d2c53618579afd7	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x941c0116d62d4116b6ea33ac34334f5fe28bdd5ab7d98eec7bd4fca5c356f58a83b38baa685d8ed474c9836a5d918a41db91f36f29d65e6a768321368fcc3594	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x5019b59f3930b5b9314bb7add452ce37b8053b4698bcc21812c5d317e46f62de73054d5c2d6483f5975d61c94da8fdaae454798311ba173fc98c6a5aed80cc85	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x5c3c31618285762c1f64e4d4bd6e71ede180c74715d4294569e2729713deb3c554c578793f5af2b44cf91de51c34150c0e05a35a81525c4d761e261c16df1235	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xda172aeeed68bbb93e1aed8c471f0e16a74f295dc853cd83f6e5d6830c7426f8f108c9b4cde45b1ba689941032e1908eae3c661c8f65237aadaecbee586b6988	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x56812297d0238c90374b2067c8e9efd37041c7016da3e08aab636d88e6d10be318888ee8b7ceacea8741a9a765fdbc24560f8ee444309d1dac0e4a5e41ce8c04	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xe2ca8edd7aa2c1a709fc590c96ef65d9b869c02d14c560fb06c29a3afb756fd36d1921971b18bb895955ca56d0e8c026833c603f0f9b9d03892add5cefe10c0b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x29fb59c1888ff5f45ad65930efb3c7b9dce6b0eed6cbb9cd55cdfee7df39bf201ded1585c164e9465c2c7788489bbb3d54364084b4eaa99a629b0d68d27bde9c	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xf02a15a8e3a8c6472c3720014440eac6bcd0de12b9225326bec26263cbd8b9884d21867d02c06120ed1ceaf5bc48ca6a3660408695534282b1fd4e9320203ed8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xfbd3bc16362f3fbc83d331f8035c5786fd916fd3976c35a7e3e9e52d05c6a9bbb3dff559e39a1c4188432b9a198861e0d69f40aee18ce04039762dcdbb6948f0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x7fba710d18fb4d25525fe5f6c909496eaf65ea9dbd808fe9a83d508c8c9facd3e0cdabce912f8fd1c181407c9eab5fdca1756754c7afd08a1dee860c648b6335	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xe68142e562c3a75b23dac7976b3bf05642b3dbc01f2f1d725cc5a9d69696e5b308c6615ce51d186e7bbb1fb342b457629053cd735ed63e5bbb4449e4f20214f1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xb55ec017c18d76d279f3a6d2155eb87c87ec391bb709084a072c72f1930160b7809eda20a7c24c2fd36fd0d54024ef19d410d54136526d09bfe016a9d7a6461b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x35a3f7838f65c9696c76f25387063ab13559f0acddb04cf57ae60f61ecc93750932199fcc775194a5c9c3e534dbfc9a4f17e26892b29027683e841e22acb923b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x73e7e2bb9b6d95fa2a38e1cb74e8a92ab2b4aa45f769a9bd79221b7a20683664ed59877e303dc735edddff7b377de746aaafac2a2a2674e839a044d3abf2c424	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x90472c792c80705938efd7382dedce7bdf843941309da1b0674494eaeda9bcab6a515587a80f9cd1274d4896d6930cdb683f871467691705888bee179aa59d28	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x7e7eec87aca5fa530f2755caf5cca70cc6f28a8287e9726ff68e8ee9273df1869daf06aa58c7389eb951cb12a36cacb0bd8f0564fb72178ef9c2216b77b90ef8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x4d09b6632e54c1b8be556ba8468d361b054ec426a0b1e60b02c5dbd4c0efb160d0117e425481e273dd7fde574f7250f84bdba5ec5baf0176e854254a5baf02c6	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x43546dea9ceeec2c0f30a04827eb5ab573b65763173b2023b5368a83be172f24883d15eaf98cd173cba84a85c43789b77723fd8d5b37f7eed99c342647c290e0	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xf6458d5770eb6704c122bd6f6055e19d7dc383400e7af28b864524c6de4cdb6fe695b8d82369c06348d4d7697b058c5003ec8c2053930374dc1cd71b63edef32	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x4faae39cf9b294c8f5238418a10a1776c05521e1ca4837e85c91d18c1033575f7b65c1cb3249c59eb428e541cc6f154b12ecfbc1a200bbc81769d21f2e0ec926	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xd377fb3ea50ff7e09fc539b7d13a880ce002e5a5f21fbb001e8ccf932742e677f84db381c060d65ea316f697d50f547d77addac120eea25c8a20cad85e42c9b7	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x5fb4dbef9ee049bdfec4e812c952f0c5164a1e92e0d9d58b45c4a4cf011944c0e06f69cd2a635cfc1730706c3c989798db7c8d208bfa77eabc1b5990f67ae7b1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x96a93b3cec43c2eb2ffdf3257176a331f030053c8d9c9639bfe90675ae25f4f532eec67efa731e606c0acce2e653e3d312a02cd89c48b33e4c3ddc2b858a5fc3	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xa6b9a531b80a8b64d3c0e819ac8206f3160cc10e185a640eea570c4f8d43297113faf6cdb66821f236a5d0682f94462af81eaf9f99216ba8e0b047243cc93579	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1580769304000000	1581374104000000	1643841304000000	1675377304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x94112d9ddb52bc409e7b77ee32bfcb91568a7b9e822f38862ac47eb23c7b5ed3592f38804b858fbc63730844048215a16e59390f3c65d869fd672b22a7e4e36e	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581373804000000	1581978604000000	1644445804000000	1675981804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xf828b2c270affb3b471cb099678ae50f5bb9073a69eaa550852bf496890aa30a879832d2716c61f99ce940d538393f9e57f575587802c8a1788c4dba10008387	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1581978304000000	1582583104000000	1645050304000000	1676586304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x8b68b12adefdbf469ff1f32502938de46e55ddac0e92a25426d87651cfc0ed69754869a0167d9edfba3cfbeb2400bc202ddac9baea7bdc35c45f4c438d1ea034	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1582582804000000	1583187604000000	1645654804000000	1677190804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x34bc85a06ca3bce0746fb08431abe19bb570e60e60a5b2e8ba8aa086497e7aa7ea6a5155877718e73f47bc121b5a26106e6bfd817925d7b3852f5949f5556009	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583187304000000	1583792104000000	1646259304000000	1677795304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x051d5e4c7d6431dcdd9ae9e1ee299146227a178f53b5864662fb838d31a039849c7aafe917ba007d9114d50944403cbd8cddd4276189cc73367c3b2b9890c06a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1583791804000000	1584396604000000	1646863804000000	1678399804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x291317638bebe25e392ca39ad32df6292c6c2d7c5518d001229ea76e167b91548a23fa0de1c3b5105a347e9240197b3b76d4282ac2fdd5a66c84448411da4b5a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1584396304000000	1585001104000000	1647468304000000	1679004304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xa614e7dc7fd1393127ecf2699fe7534710d491bf8fd302a4431e4056dfe430163661174c8dc7c3442e89eb0bad4ab0d396a3a011fb71cfbe9ff68e7550d8dcaa	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585000804000000	1585605604000000	1648072804000000	1679608804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x6fb8ac0c060b5f5ada4ea6e0ca42dfc7bb535a194e95bfd5f989a232c5bcb0000988154040f6d26db10ed8a4b94971dd53f5f9d0326e3c36cdb5755c7981f612	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1585605304000000	1586210104000000	1648677304000000	1680213304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x7a1eec1db686cec1772ce18985567c6c4990773e886ca062acd228a574536775c9f03a75173614b8d21f0d2cb527a91ccfdf609e479e998e7867e9169557a606	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586209804000000	1586814604000000	1649281804000000	1680817804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x9182eb3b51802895386af49853ba452324ae9836686cd6d0c55490f3c35e1383f85101c34a5226476f93993a63c3d5b65a26804c7fd5d99b1ecf88129206b885	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1586814304000000	1587419104000000	1649886304000000	1681422304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xbccedcb2181ef936d8e76329a003ce1e64106801b753636479333472fcb8d9f6d777308ca46a54fdb5cd96e77a7e279cb77dbe55ad8554a61040ee6ada1dff1a	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1587418804000000	1588023604000000	1650490804000000	1682026804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xe3389ac1430916e57412835ec50337f5f29fd21856d1ef8776d837f49e3d93f8698312f4fbdd57ebcb49459b748269efdaf8b3cfd0d527d013053cd7d57eb9ee	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588023304000000	1588628104000000	1651095304000000	1682631304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x29679140d022063c8845a2247f780f65221906cf4886023bb599e2925dd5a94cc27c005a9137354b01b83c672bc32c7094743da0b12da85571bdbc0105061109	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1588627804000000	1589232604000000	1651699804000000	1683235804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x49067312a9e43c4ec1e9722d39c1bcda0f36d2e4173f6f65f3317db2e71e4f633ac918782921d279a12fb162631c7d4399dc8eb73cbc58c66d66547e3179d359	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589232304000000	1589837104000000	1652304304000000	1683840304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x8a90e3214469671a2c7318c5409fa2662a0dec8e44e45999e901419747cdbb12e01950297e59cd030c952cb8262607659d37332318b2d52ee1c5e92153b4d9ff	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1589836804000000	1590441604000000	1652908804000000	1684444804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xa8ef5b6124569d271ab2dea950f3bde443580649f0c329e9fd9023671c41ca35a6dea46c02445d2511b9ed304d033d3fff380fd6faab8c02254f2f80eb5997f5	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1590441304000000	1591046104000000	1653513304000000	1685049304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xe0b08333e73a0a46c4eae25d4f5433cfe5a74d578c45e3de6041db8635ac8eeb3a05acdde986f0c92eeb81139957c8eaa7427c4a293d12f59d20b862e98ec97b	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591045804000000	1591650604000000	1654117804000000	1685653804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xb2a7cdcfa1346e0c3177f6235e4e1d67a358408889fb54a07981be497dffbcc02e0cf17bf079935f2cd70001500b4cf0cc2da3b57f443c25fcc372dfe0a52b7f	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1591650304000000	1592255104000000	1654722304000000	1686258304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x1bdc06df0c8c625be7251f6525b06601f0d857499c8c3f91f09c197178a4b037ee713bd23213ad82cabf01213d530e92d45fb898a79e78081ae8e958bc54e666	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592254804000000	1592859604000000	1655326804000000	1686862804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xa83ba732856c1704ec93adfe8d36f95eee7eff9fc14e4bc113ebac238a3b9a28a88d12b1ea89e4b0013d193301df156692dcc15d7491c44f0965ecc957f04064	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1592859304000000	1593464104000000	1655931304000000	1687467304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x1c26a85625dc3e865b77a937a190d2eaea29494992dfc38ca56dcffe5a5af4bd82e232a24b9bdb1cca450db1ce9aedb01e2cf2a27403b140dbabb35f44bd77a8	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1593463804000000	1594068604000000	1656535804000000	1688071804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x663c8bd7e3c3de2276c5e09676a61d7e51030be1a116dabde86e44ee9646bc97ae0eca37bf4785ecc5e5fe5f5080be9f424fb1e3087cbfafc03b390b2a3b7dd1	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594068304000000	1594673104000000	1657140304000000	1688676304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xa98f3f3d4f9d151e0702c9c30680438e28e22511366fbc88b65243f47cdba1404f89cedfa6efc17fc57713b63fa9202ca9b670b0280e8716958de203f3e6fa70	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1594672804000000	1595277604000000	1657744804000000	1689280804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x49bcab2fa5437bbfbe8f79faee871ff995a61cf7d11a2155da0f9c32778b14771d59852f797a0d4210bceaa23b80db29640f9e4a5b444384f965b91cc796b0be	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595277304000000	1595882104000000	1658349304000000	1689885304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xee0b0ba19eabf5f38aa026dc7b1cd141342e9b8f734a97868ec593f643d7b5ca49978290589fcbdc2b916ccbf18bbf713e93e2b4445fdfd7f92a3dcec1565122	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1595881804000000	1596486604000000	1658953804000000	1690489804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x96c8db868bc59c53bfc0503a6057e130ae691aa2ddd7d901793251316c561b1a60b9d54a837ce2f63bc85d82c2c8ff5a9945df57688ecb91a17ea76731609d38	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1596486304000000	1597091104000000	1659558304000000	1691094304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x638c70c52649e55a3c20382dc26a43178152f747ef072f0d166a369475bbf1fae4810543f6e12ef4dbcf0fdb51dec557fd5fbff1a9fc214b8d22966222e9cefb	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1597090804000000	1597695604000000	1660162804000000	1691698804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1577746804000000	1580166004000000	1640818804000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\xf419d5da1a58c2ae409ea0432d4a3f85407bfc9d88ec61bde5adbadfa230ab49cad59aae8de4a1926573d12319e93587fc17441a4e724695d69e164e459de20a
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2019-12-31 00:00:15.77709+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2019-12-31 00:00:15.852923+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2019-12-31 00:00:15.918281+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2019-12-31 00:00:15.984178+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2019-12-31 00:00:16.04886+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2019-12-31 00:00:16.117052+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2019-12-31 00:00:16.179556+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2019-12-31 00:00:16.243572+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2019-12-31 00:00:16.656398+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2019-12-31 00:00:17.077538+01
11	pbkdf2_sha256$180000$B094kGRJpM3h$sXDHU1ahZVRUEVc+ACsw3bFTA1WhByca8s+pDpFMj1c=	\N	f	testuser-5kbwcN4P				f	t	2019-12-31 00:00:18.73179+01
12	pbkdf2_sha256$180000$HzsFsxZeFcs2$6jd0yjnpcc0GB2YWF3yiFZc4VsmBlhY7IG6sP1wO6tA=	\N	f	testuser-EZBaXuIu				f	t	2019-12-31 00:00:21.813751+01
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
\\x0fe8bab6517e435ce7e814383c1b844cc8777dd8ed4c90ce0b50d066e2284d7e83cf921f4a45a5857af01d456d20523238e76e4ab4b794d4b7987ba52ead935c	\\x00800003c92b6ff727bf8c37eb7dc1a8239ec0634593a8e2dda913d9bf60085ae841ef777c9ff048871d395139c6a7170d1113874d28115aee543aeb6e0763438b8cc193579069c09eb7dd2d0499815e30aff6be66066e71eae4f25728aee5da92ba6684d0005e472198112baeb8c625b0211414cb7f2dbaf170b6e1a986b8aaa19c5981010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf1b14f26bc7ad40bb702d1435a4a3f4c00813ba7f259dae980ef265a3f05a9678b38454881f0ce1c97683ba313eb85bdbadbc4f903f10ab96a25ddc90100f60c	1579560304000000	1580165104000000	1642632304000000	1674168304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xce5bf868d4404d1f6658e8496afef375023a749346ba59e0c2642a4e1e232d0ef186fdf6220acba359b19762b72558979dd8827c3cce5ec35b88ded84517ee87	\\x00800003da54cb76aed7bc0c96ccd9ed4d04d05356912f6aa1243741c9207fbb1a1634156eb030edc28d1889432e7ba981e91a41daadba2fa9310c8ded10200a2b59b090057bc1f604aa7713b6abf2edaf6495e702dfcc4aeb8f26630c6b1d0c4b6abe6df02f24487de5830601935027b0d5175bd75aa8e491f8f846829de8c94ceb292d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xda5bd7262588a205f69715f3bb82a3aa23b03ca2247c017a0879f09143489ee930f511ab16e09af67f1d383100a45dc999041846c6d845204594ce5cb2db5b01	1578955804000000	1579560604000000	1642027804000000	1673563804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x77cb8efcee325fd302e6b0138d16da2962df2898f5612d6a7c8520c81407bae6f226be5b9adcb9e7dfc0a5943596f9e6a323721faedc64f3aacc9bd2b26e3526	\\x00800003c18332cb2dfdb41de89e201512097c18bf199ae5d52fa26607df36cd5ba99a93be9880998e40f098f01681cade3502765bf98e0a7d49c007bb4d0dc4c559c00ea879c96a644e7332104fea201ee3e85e2ed1e8a34dd13e062f659295f15d63018e0604de984340f9d446c8f2c3ebc96140a9f3afb317737c13b3465c505d1fcb010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x34b408bebe332048db1f3757ee81ff9cf0c817bff1115e3b33ba3da5f273d0d395b1b8e4be3fd07df1e16d8be4e75bf48ccffe32786588b6ba65cf4ebd261900	1580164804000000	1580769604000000	1643236804000000	1674772804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xaed7a8aaa5e26d23c6404536692f48fc74218ddfac9ac0e15b5c90e1a06ee4c6ddba61a22a13cc3a582c5b4b3a32bd5ecfb6bf1006972d17844cac280107aedc	\\x00800003f4bc7e82f34753d0cdeeaad50ae09917fc75df6a1214fef02b7fa98de321dd0029b9728bec15c3dddffe2391850c1191d030bec524e12f1b3a8d00f469473b607aa3b5b018fde1faa244ba475353051612b0a3fa0adcb22d58c41167b1e324bfb77aca7528395eec971c2622a0db4df847ec75bae622ce3be663f23fd23c0fc5010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xbab1da7a842de7575356e909fd9075bf91d03812029736e73269dc6dc01bdbfa4f2071f1ede4969645c373e31e4bfdd212ae816d9c09ec98be1827e325bdaa07	1578351304000000	1578956104000000	1641423304000000	1672959304000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x32c060fd8356705fd99d02173fda7bc7c5d9b0fe782afd71ad84f75acdce927d244a84c1e49d08681e3724de24d455c2519935e4bb4c502aeee7754a6a0eaf50	\\x00800003bc94d93b8dcecf88ee4d0f7f29c8911123d5137d1c6fe5821e0a3ebd0e18540790f89f09279baa95653497911738c55e813c762a14baa3b3732b1a45a63bdd70027392242c53cfa75e7cafe58cc99496276642aed78d6604a30f4b7438953b13319087be2a629c3ea94caa75a706abe30483e5719c5b37875624fcd14f4fb3b7010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xc9ba45bd9da75294810701a00c0ee244a3b5b8b5565be3a09f379b5f2c25f5070c8883669ac4dcecab34907c7913d5f501e0fac3c9559418d429b3a4aaa77e0f	1577746804000000	1578351604000000	1640818804000000	1672354804000000	5	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x2219c0ef3b0bcd5ee513a265d917a6c09165ee00d758eaa7b340e6b2fb4641e64c3c64f3118ade7077d40530c70412b43624e0b88074f605670a26188b68f556	\\x00800003e58b3fa74102f95b5d51762ff49977393dc97d949327e7b67d54b0594cd55dc6e45e76b5ea2824c6edaf018f1a7b595fb61b3838bb09372be1a8b5f99cec5c017875a06f8071781d3d8de053fc37718d621ebdbeb444df94456e709153e66688f935dab89314e67a46b9152493a5354bdf3a70fa498747b12d9022279a3f742d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x5fec2632d51238deff5558c441c21b3f7d215b4b4fa550d3cbb14cd8fb191031a3916b167b02de8b60e9e61ada0778d1452e0825df2b0b4ea68f3aab7849020a	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x800d0137c34f58834ce41307a1f8c2809545e1b8a92d6d58d6e3bb2801f92a7ca6e124cd7b6d39f6809812fac9b79a949465d7731a35a7a34013734d01c9ccdb	\\x00800003bd359d9fdb3b3ed21e210f26dbd5062f0577faeb6d5fb647f276d719d8388cd31062a487c63fa312e13502d9c3a5e4205accf760bac35fd02530e09d4175e48c9e6c2186da759944fafeebdceb78da8b5f2e306297ded2abbb03f1aeacd65c0318af115610ff7fbb17d4a57adfded12e98665c43522b2f5a88bff3ebb38af04d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x8649ec0078cb73928a7ffd044982a69529df73a0a494c0a627152babb808a5bbf9eb2f5ca707607244fbbf4fb98c7b5d378406915bf852aaf12d7085895b9907	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xf8ddc165d2e630fec77cdfb9e94a324343019248d8201f3c91aa9a284184824edb4f55b9dc20d942efeca1f263970778b6b956b4673b14cffcc0200ec6ca0399	\\x00800003a3718c116ea4d58c609a7bac087ad73b052c5c556a6d90ed57a6de4f6360fa0c69d51e83aadf7cbff2d3148ce1236678bf970fef6e5c910535ebf3aee5ad8b30b4991c705b0763f5fa8d5ce86440d8b8e9fcacb2f2770c378da6f4f223f75bfd2aa56e3444b7fefbe66c4be2ba94c317c8d86c06df0eeda155ae8c3aa3c9ce83010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x11c6a4b7391dcf85a19cae964d55d83eaaff55779c8d6fa40562bd9a3883bd050a55d9217fc6d96be541ed99d4a09f25a3487d3ef4a131ebbed8a487499bb107	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xaa35d8f91cd2980f6bb6d626c81b1e5b088c810b23b2e6df9a25c4757f42271937e852c3bf1c34a5fc6c9bfdae2df9e8e1c85a78812fbccaac02e58e95b4036c	\\x00800003c065d4c5126c6f9040e7ee30cc9bd5537acc02280f8815de4dae6f2c48bca834d245ce55aef1c7e0d831f5b1b21b436dbe5f72d6691f200c09b8fe2bb39298cc8a050ed9da8fb590d672f9edb31a99f88dcf6de0290d18d25f26bc15231014c183948e8ed82fa8162b184c4048db5b94e2cb9814f56a70ec7c6d17c0d65c9383010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xd08a4e84620a1562ae6010e2661225027519cb4b6523cb82a9fd1fa8c10c196e45529d60ae549d2dab49f35627e93b34b656f695c55f50cffb5b0b25cc43e00e	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x00800003a9c5b99c5693f89596f22c0e151080c8025184b93ae72bde5902481aebe8119f502655ee18fb04fe97c55526a284f607a74d3501ea6e11b1b85e310d139d8c470b7b83b981bb8ee982798238b4b4d8ec1bd941c17d56a0b4922884d872fff843ad697efacce31e68c2318a8149fe67fe32de00e4e7dcdb6851c240a271a39da1010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x20f4aca691732e0608edf02c516129ff02c52e7d5fe1a3eb57cfdc869129cc39677826acd9b22a9fab596b09f789d592dee41c52174dd103c626a4c1004a3b01	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	10000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x0c798c2ffcea527aadd0b62d0851fdd10410dce01347927bdb6bd63310449ffef7825da19f8555b243d5253b986a73c14731b11a81a8d36a319a86aba69965fd	\\x0080000395c82fd2b8f51d3ca20cbb6d7b31028e0a392050dbfd27887e8e8ae595c307f67385481b1ab6455c77abac4b2c3eeb31699b21f3706efb9a2936128bc4759647bf6f0f89f9d3f833d53da95040d9bd4dd79b74bb15930505c8a6fca277e93027c1aad759d7085fcfa6b51556f121aba1a72582d5caa9f5246be5f1eef982019f010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xae82290e93542e033ced1f568953b556b7d57d0825fc03b6ae6ed0c6b680117f9e7a536396bf50d73ca2bb261ffa8c363a479c03c5aa30233d37d2c72910a20f	1579560304000000	1580165104000000	1642632304000000	1674168304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xbc88dc8675825cb688dd888e5b382e0e828cdcd993f40c3a63e5504d8b1284fe4fd2d9a43393c81f81543102db0044529fde7f5d0c5a3d71c7ffa4acf67c9a88	\\x00800003d362810b3e78893e1e7b8fd040086273e1e28b0471cf6f8b48b0631604d4477f2e7fb7375c69e4a0e2b1ae42537dd7dd7df8dba4c6564db5334fae21a6bce428bcef215194df802f8bec60f515139638d402a6056604ca9cb3b844292d89a5a061e18174505e6da1a99884af830cac290cfacd04b93aa9c105b570471c633dd7010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x8d67a7c7eacea8126b0022647ac8979405b71e688ed4390fbf809ddb4c5753970031d0a81f268c52c9c04c8063d7560f29825260462b79c3a66f95aa05c0590d	1578955804000000	1579560604000000	1642027804000000	1673563804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x26fc4ca650b73f4704b9bee01fac44cc21620e16edaef53e87ffc8c72921c9ff1bad262d573e76d6b63b0b4c02a25150ffb5e4604214d6e6aad2279f7e910607	\\x00800003f523d41e1b2648914202a96687aae4d43d371d9ec5240474451e69932642ff8ca8826865f0767c506871ec95bd2a5088b1037dfe8fe883e3e9e9043c1acc22db454057d83305549e935b311c1e03512d2e9982d47635c87c8d337686eda409a6a95cd2aa6217d4a81216f8313a151e9c743408f381e5f6d5e1b5f74958c99d6d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xe7851b96ead7711d79241a879c8367b56f705a6c3099f17fc1f946ec60437985d6c933b1bd834746a4f2a461e48e645830c438457d9e6bddf0a54d3bfad34302	1580164804000000	1580769604000000	1643236804000000	1674772804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x192f06d6d6f9860d59e2748a782110fffe4fdf61395942c82102b6c8a68ecb304926eb98eb1bb018705e0db2a175beb9c5c2d363da1691c720b9b0f2c08a55cf	\\x00800003ee43d501bed10ecca5f4ffe622836fcd7e7b3b88944cee71268bd044d683838394fa91a40874578e4243053d529682886f87fd70db634a5ca585e37cf0148a448061def3ad399da4b21e6185182bcf7f299097be35dac62816b6174cef5e2e3eed504b12beed749077c9ac63424a702835539f9e82c2538e2cc5ee893d050095010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x0c59ab87e2f271f6459674dd26894e93f4d848f1f5a7177b328a062ae4002af88aaa6cdc4573c57a20d0b3d58947e6edcea8e3a30221621f7a136d35fa1ca402	1578351304000000	1578956104000000	1641423304000000	1672959304000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5de21c71a635a9a9660d595afc1d9de3aed810e04b177cdd139188f3b6e06658c5507dfe2f3382ce9b44a96ed583a2543ea6cac4994bd2e471f8bbd9e2f460bc	\\x00800003f262b1dc2a70602a43e81e442b8f1d4587558bb4f37ff2ed2d42ab238ab0bb053b8424226dd9f2450ddc89651321f3156a8712f69283a03d3e91e8f5682c485e99873dcde9bee127d45f0c8d4dd5465637502920acf983d5b9707bf8b6bb3890bd9ea518df3273efb8989c567412318d5185075852b9ffeb4f284e704fe65681010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xd62349d61ca1d987e0c696b419d7ce3b0b8b558d3ba2ba6246f83b18e826e00a016c6f94c87f51e3cf9bef3a5afe887983e39c7c77cc97eb6ad3677709f73407	1577746804000000	1578351604000000	1640818804000000	1672354804000000	4	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xeea9a3303269c5c736dfed0d73211e0addc1aa75195f16a51997eeef9023d3ee4f270788ec7e5a6535d5e93fa2469d8afe86a89c101efa4d4c8a1e6080b01bc1	\\x00800003c8d508d96f3ce2a62fa17eeda704cf7d9b57163614e136e7a1ccf50f1c1dd1cb86428a8e420118cbea639e373b37d6d7f26e4dae688a1b36d6601bdc8fe4dd085053a2fd768e308cb8ae7086ad719ef599fd2535e442057aa4e3c1362b780feb51cc3a5a66adbe87df346b9b62ad6b37c404ac94130d3b95bd198476ba75e9c3010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x1e1c9be82a61a0a2a8ce322b7ba972288be4854b783f8036c2105c6fff2a21dcbb070561dceb025200cbf9e29c8cdd86cd78d7730751136d53d022f084b46300	1579560304000000	1580165104000000	1642632304000000	1674168304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x95eac193f21eae6befc7a83c9c24b525e52afec9badfc791d44db6ef7ca1d44ba12a6d8002e16c799dfdb93353932b1c9164b0f0033ae73f151e1f1c338cd492	\\x00800003bf09768196fae3aa26817e91174d8e661b8442850a0022dd4528cab93e1caf098f9bbc1543bc163ada85747196abbca540965f41e5275a0c07851999bed6ba87dac35c04c459abf1e635d8a6a93c00f4711ce003f26cb442b2f2e31f6ab822742dd1610a4d0956b3abab5e98f1819651556dcfaee33e73ab4b2fea190f30d66b010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xccfcf039c32d3dbdce0ee7f5f4073cc927b26db7d2e76437a2a6c9a9b755f82ed382c2b3b504d26d8060540023e8552bf07f1697cc58383cdc61414be4d6820c	1578955804000000	1579560604000000	1642027804000000	1673563804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x0817432ed4c056a37c747e7db98f95018478c2a45725e8622550d910f1836576aa8d8a07b6baa0cebf3fcb1e1d9714084c73d263c1b162db6fb2b440fd34aedc	\\x00800003abb4ca0a2f4e3adfe7d3dd11c03e29c90be3ecc4f71ecd1a7264e054af8175d36707a558e7c81dc824facf96486304d7f9bd45c0b3cc9ea8ff0be01ed0fc3654cd5ede83849f6c17c75e7f85262853dfd3ba7b3611e861052d29f155a5a3d24ed12a6c49d671c03f61e924a6598ec10e2c1fe43f5e1ad7c65c8c769fe450939d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xb0cc1acfa482431c041ba81dd1cc92c9041f7482beedfff62658a9117e5c96ceafc966de359ae52c03ee52a24b426252e06b21a151119166b3e95e077349f20c	1580164804000000	1580769604000000	1643236804000000	1674772804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x07feef6154103988731bf694856a9ebf9643123187b9e68d0c2797b02ed04b3dd2e71b3793a5cb89b55a9e7efe382b299473977517f6b5128b49739934313c3b	\\x00800003c6d34c4997eab5af4c8d0879cea37c5504d19f07822a0d0c32eb30d771421d7406711ebe3566c9e6ea352ac8deba2f5332b4336ceb923d2bfa7130aa0a214f48252cd4a1b6f35bdc5202f30088ce8db8851f567cc85760199f57edaef1cb53924e4e5d18b8ae4272a5d44306120f55c8581bddeb517e7bb3cdf2dbbdabbe0b2d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x497e3cbcdc108228d44fd0ffe0118cf24f696192918ca45e1016ba6a1a9c84f1cba0f85049fde22128be29612eae390262ff6007be37b440476325861757fc0b	1578351304000000	1578956104000000	1641423304000000	1672959304000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x4b7038f16af77137982b2b32cb71049ff96b5dd48b099dbfc3c288e78325028957efb6720c89b8b27ee0425194dbed0f58c5806ec280385714bac790ca51a472	\\x00800003c082e555cad70fa8d7e96ae5f54f53dba79ea579a20e3e77e3793d4cdc90663ffb232cf0e23f2e2649ec19ef622df32933efdc5791eb499a8df675c4e7a85b7348dc46b9c75141367e87e962ccbf833914e1e7c7a576831d9cac6d3cd5e72a79bdebd725aab7831656466dca2ea5c0ef41c196aa15252405268efdea01e7ebbb010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x43d4caddf431f899739731502b2de35c8d2350ac013bbd47f1963a2dc8e6c0692e642524fec47d2d55fc6fa362fd91c7d8442a14fc258ee07939f471af11620d	1577746804000000	1578351604000000	1640818804000000	1672354804000000	10	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfdbe9555dd53b79d52122256f9c58041dd1c15bf4b8bfc7ae7f81763f096107e0f027fa9acab50607e3ce5d52a94663a3be5c98fe1402c89e1027bc572c2a7b3	\\x00800003bed18768eafef2aceff09d199f3d257d3f5a450518d6842655a1c22db10bc655c3eb196a53257ee8a16a8e0dd85807a35d80d5c561239cb0fbf05000d6bcd948e49df2fb7b9fbefe509beadcc1ad264c626b4abec6be23049acdcb646f43f0a9dc490dac3272446f27b6d0e06a224b1a0a292bb7a577b0b055df781f49ee8b1b010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf172707331cb75b013bddc3f4fead714cb04cb4914542f4f3a340bf609c9f2b7224e4db368eb23a5c79fab510970364fbb8fa5f43726989baa009a3315549308	1579560304000000	1580165104000000	1642632304000000	1674168304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xd42c83707cb8349b91e9036f98c98f72a172281afe8491e6d982c21025de85c17734a592bce80f059481a98db6eb253ba18f0311752a5013c675523a8da6f297	\\x00800003d8123047050e5794ac4d96d16003ee17e975ad09f625d21038958d1c12d04733a7ce84bc7dd5a38953cc0d2b9c7cf50e8be74c9491ac6b98eeef088c450a2d85dc70028d0f850cbe43fc4654153c6b0822336e9e2c2ea1a603c91d09978f1a98ef7599330c13077c5ad9175eade03e19b0bcfa53eb738a6ee51ead8fb4df3f25010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x754bd64e090ef15e7b5b4480a7da97ff188ebebb3347ad118a56edb4e67f0a99974215eb57104289c8023575d7979bc9f86ecf8695e87a826946d46eb6f4520f	1578955804000000	1579560604000000	1642027804000000	1673563804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x50841f6ff5d75e64bea7b30024d78093fa5d97ec7d336e2086a8be26c6e81c251b835ea0f85a125073c4d49416766068b7be6a073aba06ec5e12f1d1cdba3aee	\\x00800003b5eb859d7d0a78105a7db5223ef6143e276eebbddffff18fddd5b653ee767a8d02f7b077350c7cc204f8340d14accb1a92aca12e2850d032c36bd0904d04e7905bf0e764cdeb6acf3f0474435e9fb44703f7066717f5d62534c5e086accc6ba794825c88c8266ab8100d6a5de6bf127a38952801b1daf367a7a8b47b0e98238d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xd486eb665b91824d03a8ee4149404c49494ad5e0da2d7666ad75e9571fc53cbde98b7b2db4d3b3af46a6ef604f35eb78504ad78d1a2989a8dd93df280d22fd0f	1580164804000000	1580769604000000	1643236804000000	1674772804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x39eab18fb8d96d3ab6228480414e4862ce9fb2638020d046819f9043fe0eb799432a8d99b11aeae6852efcaef4bf301d7afc79fc3b86f8753a9d0510bcf24b80	\\x00800003b4788e88497a27349c8a7752af5f2a02e96bd63eaf4f12bf921e71451769fdfd629cc44735fc4f3967bd6c7d84d9678d0cdbddf9383ac791cdd2df7df1769bc3f63efda294fe92f7994dbbf0995333f197e6130c51dd583d6cdc4246338fd262bc6114837494938bc0a1e3ef3d6ad1fd1bdbf1445239d883d3d3666ce1b02a8d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x5a8a813addc28125908ede744d14323019514d8eb4d513f7d626bac0488275ac0245fb2a05f845a8acb8ee97f9f27805e6f6f2c4876445f6e87ebed05899a309	1578351304000000	1578956104000000	1641423304000000	1672959304000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xfc9165705c124932a55a38f2b0063779773676f104bca21c31594e6b109b52e3cba1876a064d6007225f241a4fc27dcdd20ff7be405d39778cccd7dff08dc62d	\\x00800003e79c41c0a514f29e48626edc6b06816710e05f0c632752fcc49f780de0eeeb3c89084ba33a6719ea5ff13b90bcc141a1578d1956999afdcd60e446183041d671210ac2a932fa95c6de8601cb0d9dd58ebfd6e59a3f4eba5cd5731bc02d5c84a9476c23d08ec91df3459165a56915e8584adb84f915d214258044615af25f7aaf010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x0bd74b46dc803429505af6ca3695e1f604f026272bca3cd63947242d516908eafe7f1b6ec67950f5704d7259501521cdaae37ec83dd01262c63969f3a0a7520b	1577746804000000	1578351604000000	1640818804000000	1672354804000000	8	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x16de84a4dd7c223ebdb4be6ead22643e1a5d21d998c15e5433700b1ae2d89261ebae2a16b4d6f238da3b849af823b4e084cea29288be81884d61d426fc6fe18a	\\x00800003fd87a60d02372d7c57df89ce679492fcf0ed4a937b975b526233ae18b9e22b38ed53f565d489814a7947072a402ab9869291f2608ed87f48d24e6224549e198f0a0f62bdb933a74954c4df33f15dd78dd705990fa22b8a41e231d467720878bf6edf156e68acd3d9162507fe6008d3393fe8ac592c6da3849f60919437a6431f010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x11dff747e1898ae27cc78fc5727a041bc5cb5e4ab5d2ee6d6072bea7e130cb304ec87a5d874fe4a7a40fda6647ead0624b95fa80fcbaa68bc91923ddb6820e0b	1579560304000000	1580165104000000	1642632304000000	1674168304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x84db2f172344db592e551b9dcc799e3d5973a3e81e35ee09890a0f3a6d81ff6cae382a9ae44dddd9bc2d2c7f8ca5399d7e11afd0bb711d0d4d1d8d611cf7704d	\\x00800003d0a916992f67ac8c773a22b5cab75572c9c8edf041ad7083be5afd0f274a446a81f41e88a204b0a14ad68edf8afb07c0375e4f808763d26e98560bf33b9d3352bebf1ebf26e7df82613067be489300c2063d47f28e9e5c598329852b4b9f3c2b6808c01b346fe90a0d0d1698baf15a9f578a2d68641ecd54bc680f91bd2d5bf9010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x3af96e7674d7580ba9679fc77e0cab647421896ebf6991a7bbc10547d55bfd25990836dc0ca3ed16570492c1650e6609299aa726db7e502b3c2f5fcace27230f	1578955804000000	1579560604000000	1642027804000000	1673563804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb4ca9acd6a351cad8d1441cda2dacb05af22ed80ed5c63346edc9090a0b54c5af6060d0beca1020cb08cc1efc617e689f19c69a78c11199a7aef8fbfc8d3965b	\\x00800003e822dbbbd89a65342ee5235feffeaf17ce7a81c0db974933d85ae6259661a7abf85d2b00a9472d110a8c88f723e1eedc9fccdc8c60d8f684ee7e588f687d10fead6043163aac571e096bc10a8634b735d24e17e2408b31c2bf4b638d63f2ab630d019b30cbee6117252f3d704a56afd1a5e0e5cc7db1cf56383cc24726ac113f010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x61abf071b118d87d1a86b829f401659e8bcfe063fd808cb9ccd67096ab57652bdb657a45653d3f5ae9749253f464c02fbfd7d05895fa5e76f3e5492249d9930a	1580164804000000	1580769604000000	1643236804000000	1674772804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xe115ee088f9e92c7deea74ae40650d14e81940393b583dafa4a5e002b174abd2c18200d3fd156d9a88c583e6213301a61d06a468faa66972e96da8c05e134cac	\\x00800003cf91f011e395e5f0c8a8a872f01ebe050253e084b744e7235f281165367348023842baf167107404f9aae291925865548b359e39b6c987698ccc569abf85d09926c0df402bbcec4baeb8a73e412f70d09e2cc2b2cb470a7431108c9775cc5670578daa9f5a3fd64a6ff046e8a76188282a30902cd34f22b01e6bcb7830c89b37010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xbac6dee511e90a3495b81f17a1c16b8fe1a052cadac0043d3bc7747831627db66efd7848cbbfaed5d3f80386c10bea88192f03b49c3ffd7c883bb02acb765c0e	1578351304000000	1578956104000000	1641423304000000	1672959304000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xc7c81552056d3c3df38d7d9655b32ec930080a5fbcd8a72833d0cdb41ebed8fb8d8337660d8db6fabd1d9fae828702e356787b86de7aa222432556d07acdaa15	\\x00800003ad1b46dcb9d0ce383df76e3d9890673a0d8a66db3bf0a45380a0a50ff207521fb7bb215607d01025e92fc7943d1b449b7ea6e13c10e6ea4e99ef9cb59afbeb09aba576d821886d6827c2d6130e2a5ce264cfd324a1768db2f4db23aa4334d4ee0ed555344597e0080234827ba110e545735f9a76dee88c3e476f483eec25df6b010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xb3167ba438c97a6585df076ae0564fadfc4c7f9766adc5ba34dd81fc1056fbebb4ea7caca1fa97be080632ebec33efe7c8d12fd4e47ac33929719331466d7c02	1577746804000000	1578351604000000	1640818804000000	1672354804000000	1	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x5fb4dbef9ee049bdfec4e812c952f0c5164a1e92e0d9d58b45c4a4cf011944c0e06f69cd2a635cfc1730706c3c989798db7c8d208bfa77eabc1b5990f67ae7b1	\\x00800003a1e7a930086f7866ab939a661e9c19a17fb5e2a9641945fedf8f86c42680f2341186345b118381db8a6f7e00c19d0ee907ec9124888342997c3ae136984bce87ae3c2fd8d8bf53819685acf1ead68360860df174144b1b686d00c9f40943986f9e11f3069039f3c437ee1b74f228a75adfa3c92174446e76af2c4e70715e800d010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x0030dd90ab23b53cbd32dd04c701169ef43d2910173b3c17945abfc433a7f305379375f4c52d9676accae3fba0481a8352ae49aba367b2438fe11c7ff7cd9501	1579560304000000	1580165104000000	1642632304000000	1674168304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\xd377fb3ea50ff7e09fc539b7d13a880ce002e5a5f21fbb001e8ccf932742e677f84db381c060d65ea316f697d50f547d77addac120eea25c8a20cad85e42c9b7	\\x00800003ea486e303a26e5079096cae3116d70820f0e9fc48bca7f19a4021b92c6708a27754802d8e4262adac71a5b686e2b1d276ba231cc8172b5b7f6fc70a2399b6944bf9bbbeacc52c7c25352009f9111f9871dd5713cea01fd2705398489d32ec851d9cecf2f1a945daa0dbf3f2858e14b1312e08100e0027a8b9db42e6e14095c0b010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x87b8c3ae9b577a72112ead95ceed4d001c9b41e9c0fd68c1ab0b0a57379b5a4d5f0ca2d55fd710668988d9b56071d37794208da6f3ba519fa67c317edbb49a05	1578955804000000	1579560604000000	1642027804000000	1673563804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x96a93b3cec43c2eb2ffdf3257176a331f030053c8d9c9639bfe90675ae25f4f532eec67efa731e606c0acce2e653e3d312a02cd89c48b33e4c3ddc2b858a5fc3	\\x00800003d3544792030ab282212528cb2b64d5a810e2877ed3aea6d65f0ea54c2cbf4e2344754d526c01574713a4a7ddb2d75ba1de9f338ccd172e01a1ace8c25db4d9b531d46fe287dc538784f9560ba03b4146327f16513f0b76a420d2ecb0d16fdd02839d79960eef2b540d6fa6b235bc5c4e2b009b3a6f77c7e91bab443a885c69e1010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xe589fbf1440faf4d63442bb566ba2b5bb8258fa3722c1270a7358d9e4ae799c8c2f2c9057765049403228b1c68a6a2e38609f5d1dd188f3c109e74c0f5f8f504	1580164804000000	1580769604000000	1643236804000000	1674772804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x4faae39cf9b294c8f5238418a10a1776c05521e1ca4837e85c91d18c1033575f7b65c1cb3249c59eb428e541cc6f154b12ecfbc1a200bbc81769d21f2e0ec926	\\x00800003bda093f1519b98eeb1e16ed1266380601b3c9ebfa84f41120aadf44f51b2c74664c90a1e4da33789e94aa12eb25cc033b05e5277f8469df94363db7b3f98be4d5f2fdf003561dcb55a3fbd48f8790183c2b28138038567d9ed9f3ddd7740a2d8fe72ed692e98614cddc0b7089466cb15304c9e52de62269a86ee6ea92ba548eb010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xd76ea38c35241eac67928dbfb294b97b19f0c695feb5875ecfb3b2044406ca95172e70c3fc6625351ea50515d88212c1bdfa97e623d8d1e45bf5278ae72d8505	1578351304000000	1578956104000000	1641423304000000	1672959304000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x00800003e88bf969be3ca22bd2efcf0c4aba4bce3b8f7cd74243a880d490495460fd27815f5ceca720f672ea424491624df6098ac6b79ccd57c419848ac667dcc8f9e92bec6891aa63a86c7171bd652e17fdaae3bdeda338a7346d93c517441c54b374dcee210a918871b52478e1314253ad2ce13c7d2cf9bdb605c11cbeb9671c07a21f010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xce6a9a2ea7bf5d1ceebb5541c728914d6bf9c533f0c0ccdee1925d1d0e6b804abdbaad388a49a3c67044ea678015aa9e435d6fa2cee321f260599ab8c8a52e00	1577746804000000	1578351604000000	1640818804000000	1672354804000000	0	1000000	0	1000000	0	3000000	0	5000000	0	7000000
\\x4cf3fe632d2212cdc6424b52d0d16c755671d897484ebf857219620687942df09c66614b4c3050432f5e0993d47979eb3820a16498181e5bac39a49f1742e58b	\\x00800003a17aa69a1e802b5e1e82c50822f3ba6a503196abfcb27dde1c1a6c083f13c093b5480ca0c5e9c1677bb5d0438e416910e0c311debcb5b43691d794bac1454843eb770dd524e9dd29bb21d0e3c4c529edba59a761dbc10f03b398e49f8f192a4a25ad2b813db794b0b1b79263471460a04fc2cbe6a21fa91fa9816a81f0ae9c1b010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x4abc410fa7b63ed41800e4153f11088a7240fc8da0482e972c9466111ea01f48310a6b82264433c03179682891f0aa2e63e3dddef6f2709ee4dbfaf09f7cf30d	1579560304000000	1580165104000000	1642632304000000	1674168304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xb3a9043ce1bebb6e5dd4711932ad3184818c68c46d37df0c3acf8251ce121420466ccf1be230239fd431ca450c8cb58f6f288a94374cf65183714b487aeee0c8	\\x00800003c9acdcbc44aa4648ae6c5544ca703787c1003f55864e4e7115f8eb4f68f6ec721a356e52bd696002e1519270ba162eb8249a0c1a8fa2c1d4dba8a49373cab068cbc132c5d6265f8f5c26ad497c8869a92c4c14de8f73f4cd871a64c67171e0abb9465b3723befd23adef18b1e56b0bc45519830078bf1eca8d2a7a181acb0221010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x476fbc4c8b98ad3218ce1a845b0b64ac0711bc92a5f5631c84b3cd6a4da2aeb01efa536b175946babb4a6988efcbbaa9d16ff935eb783041dc18f4a05af62303	1578955804000000	1579560604000000	1642027804000000	1673563804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x34b07002cf734ebd8ccd77b3c4aceb710180c6d85ebd42c4ca95114c80a9a768adab20b7be9d659a36c45052b513230dd8cf9bedc8cf283110a92bf998abddbe	\\x00800003ce7365c0d32db0e324f82b770f4884025e9350a8d186b44c1f3f174671e8356484a443d0f019e34a129b190aeaf6776246725064fb8edd516655220f2ff7c2c02d9e9deca2fcc93fa0cb01327573dbbe833daf851b9e020e1c84ec4e6839f600aae5f5b648dd2cd3ef7dfb12a5ac4fea15e50927d42a1d69cd5646e9c4a3a60b010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x5d2a150179e125c364b5e4ec35f145a7603d058d4d529f5bcaec30a9baed0606558683934dd3d67d871c2ebe5a58b2bba8e2911e12a210d052850362802d5d05	1580164804000000	1580769604000000	1643236804000000	1674772804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\x47d6de896f9538f1c02f1d33326118dcd6e7645ab9f7a1e0acb56a80e1c742f3e4a9cb17ef79419f454dd317593ce5521abcf8d9089ff85a6e3e818c4e98db9a	\\x008000039ac1f0405462fa24ccf5ee9ba9271a92f55dd1aa8ebe6d690631f54787cf470542a43dee6e4b4f9a974646d5eeec6ebadcf06c90155e00364e561fbafabbbdf5132d13d45ab5c1c24ca0a6db7196cb3641f25ff0e515aecdf90adfc6e7695654143b781c9f322b1bd68060c1fa6561aa8857705dd809117bff113d015a609507010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\x89e5e82db19a3ebe3cd23d4a06b740a7b73a00eb38df9f929b4be1f389810e2de641993b87b7c5aed9ddb7de90207bd7bf2141a0afed0d6b1e3dda4454383f0d	1578351304000000	1578956104000000	1641423304000000	1672959304000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\\xa3e728aaf177360a81dac474f1e86aa3b90c0a2c430c433f42e33f9503f0575c2ff9d6cca5dc61c4740d03f1bc5bfe8d2f0f5f4cf2aae2968f0211ae83ffcd58	\\x008000039d30a22bd94164e4cfd446f5e99a410745138c31634513f8786eaa6211c98dfc421afb9387c33b4dc527ae3e2c6ac69c1275f3fe82e09aa9684cbaf7e0f44f9477aa0ae9beab022f3f3f1c11080faf9438eff7a4f9019a6d57de99a857ee394b0d802eba1083e24f0f1e74e085aa55f7918019032256416ba7e92cfccd81ede5010001	\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf9c51c34adf5cb7fe68b5be1e9d3e95492e943d945828f586ea8f80129e995787bed63e0c9ed1aeca7529462c7f449dc9d5f2f36bf2070deb7e05850f7680a0c	1577746804000000	1578351604000000	1640818804000000	1672354804000000	2	0	0	1000000	0	3000000	0	5000000	0	7000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	1	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\x3376a984bc0ec5cd04d943d775722d90a49f33268cd840fa7270005a02d30312	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xec909eb8ee85acdc1c92e6f15afe6ca8536c23f8bb9f5b950200e1c416cfbf8644159181a86d2e7b32bb10469de06c68ad28e2a940e6beeebcf3efd504a78c05	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957f11217f0000e90eed7664550000c90d00ec207f00004a0d00ec207f0000300d00ec207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	2	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	2	37000000	\\xcd43f7b7553d2e28f8b1d9b7b6772c23f26a9fdbb0af976ed2524ed97aa5cb2e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x0eeb53e92f878ffc68d4f86f5829cbc95318ea2797d98895170deb9c3fe4c5163e1c2756d3345d3acd2f440c98f2fd5dda3e5960c8afb0b60d73b5b40c3c810e	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957f11217f0000e90eed7664550000c96501ec207f00004a6501ec207f0000306501ec207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	3	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\x725213269b3f640e52e8341345e44b364a25fc01b1f97690115ea1e106a2516d	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xf34dbef8d5da2da47515fe5c037fcdccd383f4c927f3ff87e8989074457094d3bb8177faed8d0813f827242557e1f643e45a9f4ef6981f0a7a64589687071e0f	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0c5ffae207f0000e90eed7664550000c90d0098207f00004a0d0098207f0000300d0098207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	4	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\xaa4bd5fd2dd2bf41ef9475068a09ced3b4fd48b2f2aa8e8c4ac5dbb6b3971d56	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x55fcdc997cea459ee5c5d993060c43431da07b7b09c6ea6db5aea98aa47af8ec3b5eb1bd6ecf072b11b168154d30a75cf2abca34c311ccdf0069ec6ddb9a890c	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0c5ffce207f0000e90eed7664550000c90d00b8207f00004a0d00b8207f0000300d00b8207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	5	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\xdd210c0852438aa105f31991bd942047a4a3f790ff1e0949c8461ee958f71804	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x6dbf9eb7d0a4de8cd9e5ff7c0587ec24a275c824a67d00c7690519f9c7dfc7e28c0de86a37bdbd52e4d0b034be68985c8e3d4a935d7f7757867bc20b535ebe03	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57ff3207f0000e90eed7664550000c90d00e4207f00004a0d00e4207f0000300d00e4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	6	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\x3fd5b118c20863603c4bbb6e397aa282b40f5078c73658dab268ff651d195328	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xff1bc4075a3fca014a93641a31a4a1f74dcf3cffac7e7c492ea0d5528cda6625e41f90fd475f8795f98672a4a92d2928a28f21900be4ce4665e43c302371fd0a	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e085ff10217f0000e90eed7664550000c90d00e8207f00004a0d00e8207f0000300d00e8207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	7	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	97000000	\\xba61a131b373ce4ccb74989682c1d54c056f6e8cc9435b0a5bf197fabf15b310	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x9a6f5affbc9ca0680680be742a12de76073b95b56acf155a3778caca6c9947e60f45ac797b828f300ddccf369dca6eb53cbc9eac61988b8a32e7f0e73918b401	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0b57fae207f0000e90eed7664550000c90d009c207f00004a0d009c207f0000300d009c207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	8	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\xfa85baeb623c9754b7edb0165b78dd143a6cac1078610b9e19fdec2e5e90e28a	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xe4f7f9b74efcf9d814e0b74b373d813332326060e716455ee9c3aac08bec9548dcaa0568752734909b9d07d25edb238a461a35c6e877f3ecdb31bf0205dd8201	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957ff1207f0000e90eed7664550000c90d00d4207f00004a0d00d4207f0000300d00d4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	9	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\x51853a1d1388b81b43b95b462b818c42ea5c935e2cbfa56c61b8e82abf3a1046	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x1fc7636159b82da3d9204e4ed7ad17993dd17b0e18e424e64dcf82343d2983a41fd2de76dd24a5e2b9db269e56985c87a8fbf8f527013d50cf7f4f3154451b04	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57faf207f0000e90eed766455000039a500a4207f0000baa400a4207f0000a0a400a4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	10	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746820000000	1577747720000000	0	7000000	\\xf16519d55580147680a47784cf8ed0311f9e1486fc7d4be715fb2153143a3ecf	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7c2ef4d4369f1dba61cdcd8e6636373ec0cc25a9241d30581c0462016916d5871eeccf29c34be54291cd421dbb3c9821cc6022cb63506629dd1b39f5ed30b203	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0c5fff2207f0000e90eed7664550000c90d00d8207f00004a0d00d8207f0000300d00d8207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	11	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\x4f017b4502f3fc5e4ae50891b82e32be47a303b3bc2abf26ac68a0b3427b754f	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x926ed4767c52ba176fdc451924dd9dce1a1133fe43fb3e0009ba5735d520ea32c8019a8b95515cc3663808d19792e6b0bece52487fa4f16a63ff5e9689a0930d	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957ff1207f0000e90eed7664550000294601d4207f0000aa4501d4207f0000904501d4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	12	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\x0c6fcacd80265d8f41787a16038fad4f47fc813e54b6eb7d0d0ecf18a8737efe	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x833a10e8c0f7ad326db0e4a936882ab018ab2850e879bb46e7b5280bff221a076c8ebc1ed050052111d61ff638a576d1689fa6fb0a2c6952fa1e13e4b5ff680d	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57faf207f0000e90eed7664550000c90d00a4207f00004a0d00a4207f0000300d00a4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	13	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	1	97000000	\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x641300544b2f165a4520fa0ef309fe2bd95f483c0e2762c353912b849a9e7b7cd6846738ff1f18e98a3dc9b44487f8d720940d7390868b62ce9e8eb685548a0d	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957f11217f0000e90eed7664550000f9ee01ec207f00007aee01ec207f000060ee01ec207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	14	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\xa895e862e248a6ed34fd97cf4d39e10efe034f93a753a2a3da305d1baff0787f	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xc15687f97351490ec1cf70644fafd9e6fe1cd8ba1d0dcb05329af2653ca22634bfec9a1efc2f09b2c53f771e9f40786b3a01bb90b557fa5b7dca44c335b1fe01	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0b57fae207f0000e90eed76645500002946019c207f0000aa45019c207f00009045019c207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	15	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\xea4de448a295ed7a4769343155c7154f2d8722231afa2b645100566bac77c869	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xb2cf9ae8808fc6904bdcce23f7610657248120033c1d3bf028884c82ed924166a1f67282b2252706838b349bfae0b31a2e0692764ebf3643ec9fac540fd5500b	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0c5ffae207f0000e90eed766455000029460198207f0000aa450198207f000090450198207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	16	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\x191ff0bdb47189fb5c64678d4df5b11d21a27ec3458fbe5524ed34d80ccee0db	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x04593cc0db8455ae371c807cdb05cfd3e79e0b9475788c2e3d39468f4bdfe45cd87bdbb3f49c21076aff4746644a76db364cf0ed26fb4a96d4d6c375c968a403	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57ff3207f0000e90eed7664550000294601e4207f0000aa4501e4207f0000904501e4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	17	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\x8378674310b12c3516b5c45130b19fa69a72a654a25445b7472c6e692125870e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x1e1de2c3c41cd3c2e0ef78b23ab941b70303672500f6e561667bfe55be4f97757db7adbb158b8bfc123886d35a0ce09558ec530dd98b6c5346585ea212eda509	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0b57ff2207f0000e90eed7664550000c90d00dc207f00004a0d00dc207f0000300d00dc207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	18	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\xbcfe55cbd95c24a22e42c4fd5e33d98edc81d9ab2ce2b9ea85c30aa35a29770a	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x0142c45dceb8ecd47669ebe0d6ddd6e84023ef31d985aa0ef025c6549f705e9a78fe9e3ca28178d59519767e7f1afd2369fdb25d51372ad2a1506248832c2b06	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0e5ffaf207f0000e90eed7664550000c90d00a0207f00004a0d00a0207f0000300d00a0207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	19	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\xa81d83dcd5d8aa4bfca3e06bb9a09174093b579f10cf80d092ed2bc029d8f53b	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x15cb0430dfda97b24c237c0900319bb1d2dedd6e6838b7beda87f23569bcb85448462c7e0feff2e8bdb1c69ea6582ec9dacc9147d3ef9bc59106eb76f1c47306	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0b57fce207f0000e90eed7664550000c90d00bc207f00004a0d00bc207f0000300d00bc207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	20	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\xe2a0a7ae5eec25810c50377ad371d290e5503e29c0c7d0fb45771b3c1e465f9b	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xeea9f7a4e618db571611757a75e4a4817891945a6d31f39a1a5f4a8c03f173f864f1c2a3a340e0ca9eafca7bb3da3e42c47639718f73365777c712f4da57300d	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957fad207f0000e90eed7664550000c90d0094207f00004a0d0094207f0000300d0094207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	21	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\x3063307755df623a9188bffbb9e68b3d026b3cfac7acd87bdfa2027d17a08061	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x9ade9499725e3f9c91e2251735bd60bfbe908939a8cbfeb0194380faec128d648fe9dd14f5cb657cc3a0e8773353c82070181a8e2378c74bc31b4d828c086f06	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57fcf207f0000e90eed7664550000c90d00c4207f00004a0d00c4207f0000300d00c4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	22	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\xf4ed2e21728ce0ff2e1ec25b1fcc67fb2d87cde5e178761f6237dd18ea7379d0	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xdb18fbfb0f852edc87261803e71861e307a446b0309af4a3e8829383744d0fe8bf81c9302ef65d08ecfd19a92b9cbc6d02ad026c0c728d72b7454b86367f4e07	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0a5ffad207f0000e90eed7664550000c90d0090207f00004a0d0090207f0000300d0090207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	23	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	4	9000000	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x95688e112bc426cd343fc4bb8259d2b1ab661644112ef53f4851701c83df124ff2fc742f1e03771123911a45e2edd33622359bd57ba757a84e7686396799d003	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0a5d918217f0000e90eed7664550000c90d0004217f00004a0d0004217f0000300d0004217f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	24	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746823000000	1577747723000000	0	7000000	\\x4cccd36f630a8c9692093439a2d8a724dda990d9f6318952ec6c59da87b1d7c7	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x8b6a4c09e82f817ce422c2f2242ea32a7b4ad98ba15908abde66bcb934ee79ed3a3f5ccc7a6d6078cd5ecb6fbee975f2179043620b6e7aacc00c190ba4e64400	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0c5ff12217f0000e90eed7664550000c90d0000217f00004a0d0000217f0000300d0000217f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	25	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	1	97000000	\\x4b4add0703c75b5511274fda57d9ad33d6f3f3e649502a2498256225e08fe3c6	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xc9901d4f433865c60040347de4c72ab2cf96bfd3ca32d47ebc3ef028d4ef918c53b3dba34798eb5006d076a4d1d1a90ce8e008f982feb6209ca57f0dc326a008	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0a5d918217f0000e90eed7664550000d9450104217f00005a450104217f000040450104217f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	26	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x0f378f1b6409f437e7c94ad7ad50a0ceaaa3635199cf5d5adfe8f104a0002e2d	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xc80aafe498d1a96e0caa40b81d88002852f960275dfaf749b44285145e5cb384f1ed9f6d136142d848558eb27769e3e076ec83f9625170c6843316a44fa4060d	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0c5ff12217f0000e90eed7664550000d9450100217f00005a450100217f000040450100217f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	27	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x7f29bff8719ebee9376a79dc37ff15292f6daa81eb4e4a9c077864cb75744556	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x5053a766a5540f5700b412d867f2b914d904c42758bb4ce9559690b4d9f3d496a0bbf7fbf41904492845782b32a273c0a6b681b3f2f386d30ae65a5d13271704	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0e5ffaf207f0000e90eed7664550000d94501a0207f00005a4501a0207f0000404501a0207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	28	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x3e7a3bd721f21f354b1d4c27bc74cb5c0c532d900cca5c88bcc1f4d7dde3dfe8	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x16a76606b55e46d187d95bc5b893669094955e15b9692183b230b05475e7d1ca131b0433b78982066c321dd2e988c46306f05e8d7c1b848d22ed55975ac4da0d	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0a5ffad207f0000e90eed7664550000d9450190207f00005a450190207f000040450190207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	29	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x343138c7b28d247d5f3039bd14ccbc38f22d0d103f67a9b9fcbbab61e21987ae	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x974f2327dcf8e34f5d6abd69da8df6c976cacbc4cb7779b8bb3e8da0c538ac24d9ebc1a2374c9ded6ddfc75402f68192ee03c89500e3ae75aeb1a1f58784080e	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957fad207f0000e90eed7664550000d9450194207f00005a450194207f000040450194207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	30	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x540e9bd868098e28a4a50a0da18681ec6e161139c11345e92fc0d0adadd9b831	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xce7bb5853b94eba48450df43d533724c62e20c46ed0f93c7351c3ae7105c3390ac6c15eaf0a1da9fe1fc83a6401c3492286249a037f9be91307f98f303bfce06	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0b57fae207f0000e90eed766455000029cd019c207f0000aacc019c207f000090cc019c207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	31	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x2a0ac23526f6d75d3a3556f127befb1516d8d70d2f8ac7a65ef8300fff6536c3	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xa816267c9490e99837e2068cbeaedb61b6723a594282b340a13004b04f753ae0bbb46c9ef3544ec6d397422e9a8eb599ffe697ef854f3af89480c15c952adc02	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0a5ff11217f0000e90eed7664550000c90d00f8207f00004a0d00f8207f0000300d00f8207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	32	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x40201f7484bc26a2974859916a1e3ea3cc17fe69abc422b69de77a9eacb3f4a8	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4817d749e4d98a8ce30f75a65b434bb5e8fa5ef88dd1d5b9bdd97a88e62e28f9d3dba891c1b8924986252c63b8a987ba1cbf764cd09226c57534a5f2fa5e2601	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57faf207f0000e90eed766455000019dd01a4207f00009adc01a4207f000080dc01a4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	33	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x8f1c80000da00365e45176b86ae537754fb6e3660b0ddfbb1cbe569b4a17ce1a	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x6b199cdff80e9d159d66693bbe22ac2be6d05246834f7a16e6eba5fdd91f9db3b2472c86a11f98ef0778c546a3a5fef20847d11d658a619e675e8633ffb6e007	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0957ff1207f0000e90eed766455000029cd01d4207f0000aacc01d4207f000090cc01d4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	34	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x4dd658b97ec353b6f78d1838d2d434d25203f1ecb0cf70aefbb8210ba0ebe6e0	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4c3681a8a02c06962bb05a3ed8f5911311646ac0bb73423c0945dfa3d94f82b3683bd04a72d26e47aced0129143934192c566192bc8c59e6c5183d458c09f80c	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0e5ffcf207f0000e90eed7664550000c90d00c0207f00004a0d00c0207f0000300d00c0207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	35	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x5625134abd8636d6e818d4687ce35c498295c2306d28fe6f688cf271d896a84f	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xb613a3bcdaf263946aa00825664609b08a659294e8cb992ca33ec7aa5c3f03a7b7ef042c4588ebc1555d013b6fb2b2124a98a0e06dce7235f04b4a9eca79640e	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e085ffac207f0000e90eed7664550000c90d0088207f00004a0d0088207f0000300d0088207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	36	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\xa1c536051cf36b0ae7ed864ae79d7c6c6493972b216e6a9c3769fc7f205d94d3	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfa1f4002071b0eac83043780b679471e68015a1426d711dc9c7c973d197d64542b0ba63ac8cd0bd8dffae01a7987c3c555b4c392d7f81b0b01b13c1ae0695c0c	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0e5fff3207f0000e90eed7664550000c90d00e0207f00004a0d00e0207f0000300d00e0207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	37	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	2000000	\\xb4cf2d1d29863f34202488951e81593d8c0c0df520478d9146ff849c3c800721	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4dc1946848bd0c673a7dbc9a93c90f688173c2c1f7d07bd1e7174ee9b6a86cd45bce8524c70d6e7804609d4cd84fe6de9d1bba922fd78a890f342d9628e80708	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0b57f12217f0000e90eed7664550000c90d00f4207f00004a0d00f4207f0000300d00f4207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	38	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x85288b1fe630639f1c9be3fb2ff981aa0f4f552f1073f94e1e33a2e8abc413c7	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xb0803c1253915b60507c22897080679d0516c34ebc394c9eb657981cbc11e7d19f386585571267d7c62045dbef19663ec548c0670d8a317d2dba2613ab47a10c	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0e5ff8f207f0000e90eed7664550000c90d0080207f00004a0d0080207f0000300d0080207f0000
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	39	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	1577746826000000	1577747726000000	0	7000000	\\x408bd8ef75c3a44e273b54b79fee6e318c8401b6d10b50afdc3f43c78cb7d1a0	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x0e794297bd531bcd69deff7b537f0e0641fe7cbd4d0fe831999216977b42795dddd4bcebefd146984de7300d29924630d469478ac87da0d17361536f555a9803	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x1685f91a217f000000000000000000002ef6ed1a01000000e0d57f13217f0000e90eed7664550000c90d00fc207f00004a0d00fc207f0000300d00fc207f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x3376a984bc0ec5cd04d943d775722d90a49f33268cd840fa7270005a02d30312	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x092ed19427835a870df242ab641df6eca3eaa2346b72542a52ab7c82415670478400c0ec29f94652f65f2b4fedaadffb4e411c4670107b8aa197084f860e4307	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
2	\\x3fd5b118c20863603c4bbb6e397aa282b40f5078c73658dab268ff651d195328	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x1210d476cc18b21ab404b1328b38f48d4675f6b2163ba501e620821b864c270ff990a1e8bf8135cf272cbce203c5b7d004ab6aff9604f94a287226dff2aafa0d	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
3	\\x725213269b3f640e52e8341345e44b364a25fc01b1f97690115ea1e106a2516d	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x0b156cd7fa77e9c7b07df921daccfeb034d803814794e92b720376fe7678e23dd9b9fb31553fc1dc75c4b6a2ae7da73dd8973dfd4f982a7054bbf02227b98206	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
4	\\xfa85baeb623c9754b7edb0165b78dd143a6cac1078610b9e19fdec2e5e90e28a	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x609f89750ab6c070cf5c3b7b07d5980a5dc94cd45676ea7a4e2518e6c7855f4ab3dd49a66d1130d9120dbf8cadc4252b05109316133f941f94c9126464e6b200	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
5	\\x51853a1d1388b81b43b95b462b818c42ea5c935e2cbfa56c61b8e82abf3a1046	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xa2f348479c61b41a9a82c8fbd6eddabccd1533425c2e8684a0052d946fb1716af030c242d59abeade008acd76ab86919e091a8205c1cc87153c16bb87ea8e90d	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
6	\\xcd43f7b7553d2e28f8b1d9b7b6772c23f26a9fdbb0af976ed2524ed97aa5cb2e	2	40000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x6a1981e6ad157d1239a29a70006425a137350674d8cc0740156fd19fb5225a56bcac4467d6f350e0886cdba5bfb9b7819468af42c205149c68ff2ced0bde2b01	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
7	\\xaa4bd5fd2dd2bf41ef9475068a09ced3b4fd48b2f2aa8e8c4ac5dbb6b3971d56	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x88a048bd26d9360ba29bf23dfbe941f7daecde9bc1393ea520af24dc1582e19813d01da881ea72e690a3871b03ed0ca7e6a501f79533e86a2573215d03ea6c02	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
8	\\xf16519d55580147680a47784cf8ed0311f9e1486fc7d4be715fb2153143a3ecf	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xf2d4fff8d523fa6c7d957638279a21cc8a6060b241c7a55542f6be58e417c2f4f59dae0ea8ca8dd657280c71dd5ef00736adc63ff7b7a005b2d1a5aba6948f0f	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
9	\\xdd210c0852438aa105f31991bd942047a4a3f790ff1e0949c8461ee958f71804	0	10000000	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x8d6f7949a7f35248d59c2b8034e6a4170d164645db8b6d919d8ea4edb2ebf5ef69bf69194e8bc00b43e7561aaf91a5dd18db1dcfa49eab417b506c99dd96c507	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
10	\\xba61a131b373ce4ccb74989682c1d54c056f6e8cc9435b0a5bf197fabf15b310	1	0	1577746820000000	1577747720000000	1577747720000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x7904c10536f50c424654dc9c65718cb366cab1c9ef6a6cb80f3c3afa9359ce1bf4d22dbcf624cf49afe03157756b11234f60c8b3505b09ad1a56053508bbda00	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
11	\\x4f017b4502f3fc5e4ae50891b82e32be47a303b3bc2abf26ac68a0b3427b754f	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x3010061223c6bb67a3255650414ce8653d34497f5bc3366009a464db629319ea1aa2c9b4bb7a8d62f96adae3ebda9832001f46fabef8a57564ca732cc919ba0a	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
12	\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	2	0	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x53cfd133a15d51614c6cb19156c1cada82527749ad2cf5917c1c05d96732b3ce7e5769c39cb9326d54af301d5977503290d9f959316cdc292fb8a02b9a678407	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
13	\\xa81d83dcd5d8aa4bfca3e06bb9a09174093b579f10cf80d092ed2bc029d8f53b	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xb5685c5d00098a2dc9d6ec8a1cd0e7f48cc72ccea22f5f3c9ce23a68c41de0a6b6c58dc213708f784a1a99720e1845a35350a026f90d8c23afd91990bfb1bf01	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
14	\\x3063307755df623a9188bffbb9e68b3d026b3cfac7acd87bdfa2027d17a08061	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xcdf60d4b310f09618f486e0c370a494611c6ab8d22c2688476a9e949c5d55cc5e1cadc024b331c57888047fdf821f7ad2b06730ca2bbaede8b1b0656644d5809	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
15	\\x191ff0bdb47189fb5c64678d4df5b11d21a27ec3458fbe5524ed34d80ccee0db	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x25ae7dd182b73bf4e098271c2f195ea150d04a9da67e9887de46cbc722bd8e5095271263747e3bace999c88eb9c8ba9542fe98d589ecc30c9611f44a59b67e03	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
16	\\x4cccd36f630a8c9692093439a2d8a724dda990d9f6318952ec6c59da87b1d7c7	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xf73d34b3ebf0906b69eb0f44bad3055460ff677c3232219faed54e4fabf6074583bf9c0036e383695ae0a4ae24c118f5f1149b5c4d088cb0fa9c91f77ba92909	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
17	\\x8378674310b12c3516b5c45130b19fa69a72a654a25445b7472c6e692125870e	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x6ecf1832ac69c6f852722e882ed6da8bd28b3b3daaf0fc1e4a3c2c42a3c3b29c3561bf78222a0e620efc841a2bd91d07224c15b5035ae7ebf155bbc2c77af608	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
26	\\x408bd8ef75c3a44e273b54b79fee6e318c8401b6d10b50afdc3f43c78cb7d1a0	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x0ca745095f4604b273e5499cb69ecad28803e0d39ba70d4f6a27fa60df0b5edcab0ad832abefbda8efcde0b50578a183303886114217608ea4ebf69615dea700	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
18	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	4	12000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x0f46bb0dc42b99af9cb2d332bb86ea20b5d33753a681f6e6241e7841c91385bcd5399f64d9f4e0d85c315cce273fdd50fcba539b6d003b72a369306546511408	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
19	\\xe2a0a7ae5eec25810c50377ad371d290e5503e29c0c7d0fb45771b3c1e465f9b	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xc45626a844882f8bc192cdfc1d77690792839cad65c09b3ee971a58485f183c9fb88f98f6455646adf8911306456a8ca217518a667ba3518b311294623aaa707	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
20	\\xbcfe55cbd95c24a22e42c4fd5e33d98edc81d9ab2ce2b9ea85c30aa35a29770a	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x495db64690aaf44baeaaacef571e634a1110f92cf769921801bfa852c2c819493ab6cf3acb4da825871cc5682e1eb63e6b255cfb90cee0f24bc05ee7ec585d03	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
21	\\xa895e862e248a6ed34fd97cf4d39e10efe034f93a753a2a3da305d1baff0787f	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x3ca78eb5cd15a221cc73023c65a0fe9295e75bd83248ae43025c8e52f25a6ffbb6acac237ac86f73dcc0bf14594ee18b8b3570f906a3e94025615f93a149610c	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
22	\\xf4ed2e21728ce0ff2e1ec25b1fcc67fb2d87cde5e178761f6237dd18ea7379d0	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x6ea45069f248c2bccc1602cceb3bc7c83391398e495776e97b564677b3045f8b9bfb766bf6da3e45fa9db814c42f7815113f30164fe8163eaf68c56cd589fd08	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
23	\\xea4de448a295ed7a4769343155c7154f2d8722231afa2b645100566bac77c869	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xac78b09469d44faf5fd307dbfa3790d84abe97ad5f6ab6ffa3359a9c0c3751979cc8791f4ca3ce61c1b94c6d85ce61583f83b48553e6c7660069d9062cfe9c0f	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
24	\\x0c6fcacd80265d8f41787a16038fad4f47fc813e54b6eb7d0d0ecf18a8737efe	0	10000000	1577746823000000	1577747723000000	1577747723000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xfa86f4f31fe92cd1b63748d5863bfa3d35157f01d7830152f408ccf5b348d39eea637962eda0a2b5db4037a1ba0717dde69e6b5fc406646e0e1af91df5fec605	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
28	\\x343138c7b28d247d5f3039bd14ccbc38f22d0d103f67a9b9fcbbab61e21987ae	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xaf193e25576e56ca6bfa8785c552b621df55fd931f01da84f1028fdf404011de3cb05b371d9bbff93aa3fbdb4e917a0f4bc54dc9e9f80f8dced3619d773f9d0a	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
29	\\x2a0ac23526f6d75d3a3556f127befb1516d8d70d2f8ac7a65ef8300fff6536c3	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x279b3c9a9bd52e6f28e8b6fb10ee3d2dcaca701780c07cc3651dcd70e4fee2f185ac4f93aea2566b0a6add447a2c5ec407d2566d6220a4e152e67753ceddee0b	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
32	\\x5625134abd8636d6e818d4687ce35c498295c2306d28fe6f688cf271d896a84f	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x5809be04cc3fad1cc40796b3639f49df15c6f8544c858687a92bb221d8ac5194a2f9423fa6cb32064fc27820967e09888960fbe38a85f448b7e5788be203e702	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
33	\\x7f29bff8719ebee9376a79dc37ff15292f6daa81eb4e4a9c077864cb75744556	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xd95f6ca0bc7258ccad3035c7bf95ba0cae5c63e73c4831d8fac895f1a140e83183f98c6597b27c8d27e2ea73c07e12b0b40f88f344a576df9fe0c51268beae0b	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
34	\\x4dd658b97ec353b6f78d1838d2d434d25203f1ecb0cf70aefbb8210ba0ebe6e0	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xaed26f6b8bf6e2fee6f2ce62b259ecebf3e3e68557f72acfa014533276c7dd11dfca32030f1e0360dbc31eb9f87655ed8735abe518f8f9374e18a7ac4f9be10c	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
25	\\x4b4add0703c75b5511274fda57d9ad33d6f3f3e649502a2498256225e08fe3c6	2	0	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xfff71b596e167520955dd2974e785ab51258f147d8839f9efb90f7521e65528ff67e0f78dba82003433559a6025f26f737123613e1e0a49fc53e17058689bc01	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
27	\\x0f378f1b6409f437e7c94ad7ad50a0ceaaa3635199cf5d5adfe8f104a0002e2d	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x114c3c82f187cea8ff5ef7f1b6508a92f8488d9e28eb078b7cf5b3444e281f467ade34848562e2469bad7641568611d62f186ecaa4b8a160673a4f4fbcd3f200	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
30	\\x40201f7484bc26a2974859916a1e3ea3cc17fe69abc422b69de77a9eacb3f4a8	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x9c8b507dec31a6c540641092ef2afad6a7c88c0d16f917a179bf10c1efcf42a66c0ff027ea5f921c9598d53650503a01b12a60f823f07a58873dea1b6ab41602	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
31	\\x3e7a3bd721f21f354b1d4c27bc74cb5c0c532d900cca5c88bcc1f4d7dde3dfe8	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x6662210a0779c69d3ddbbc0370122246d1bb39a4dc1130bc8bfbd8079f7a170a0fb15338e69090aaa0a8393c89e052bf5e1a9bda6c6c67bacfdd3e17c6726c04	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
35	\\x8f1c80000da00365e45176b86ae537754fb6e3660b0ddfbb1cbe569b4a17ce1a	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x2254b154cc9075189e96f0a5639d55d19f0ba959c1bcde6fa86192f199b10c0615bf430ea7cd0fcc4ab5e881e30b078c4606efa88a9651d90a2b80f7695ffc02	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
36	\\x540e9bd868098e28a4a50a0da18681ec6e161139c11345e92fc0d0adadd9b831	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x25553f14fcc4d8d67386627ad4191f99bddbb0d98ab3c79964458fe4c918fa459030caf5bd0a57be076f30288e8f4da9261a3be59266aadfe9a8688381d67201	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
37	\\xa1c536051cf36b0ae7ed864ae79d7c6c6493972b216e6a9c3769fc7f205d94d3	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\xe1f0ada530677cbe4159f2d4cce7f86a6242b64f60ddb974146bbf940503641cd306fe8a3d270eb6fec67c1903dbd400a394be0af1a6d00f96851dd5a9747b0d	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
38	\\x85288b1fe630639f1c9be3fb2ff981aa0f4f552f1073f94e1e33a2e8abc413c7	0	10000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x82dfb6ccf52577c35071a10d21bedf32c45939c7f145a945b436ca38e9c9bcc225edcd386afdee9bff83065662d3a61648ad565fccfd0f6de206cf5982155b00	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
39	\\xb4cf2d1d29863f34202488951e81593d8c0c0df520478d9146ff849c3c800721	0	5000000	1577746826000000	1577747726000000	1577747726000000	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x850e0e0f93de5ed005b7dc02a11ff3aa827791a40c2d537e781730edc51903079ffc0ccb10f4655f0cfd651cca519f48847e065f97ea247f2162477a3e3174a4	\\x64976c145bfffebb05e3231f75c2b6209081907b00fd5e26fd7c2fe6e586a2f005765c10dade837c34562977d9bc26423b6db9cf54f9119f3f56997bf0715804	{"url":"payto://x-taler-bank/localhost/42","salt":"Z86CMVR4F1FWT61JPW2FQFS4JZS3VJGQ26923SFRD6AEX1H76VANDN5NQVG229HT0VD8GEN3PAY9QYT3E6ZJT6BB327Z5WAP7CVQXK8"}	f	f
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
1	contenttypes	0001_initial	2019-12-31 00:00:15.557418+01
2	auth	0001_initial	2019-12-31 00:00:15.58421+01
3	app	0001_initial	2019-12-31 00:00:15.631249+01
4	contenttypes	0002_remove_content_type_name	2019-12-31 00:00:15.651072+01
5	auth	0002_alter_permission_name_max_length	2019-12-31 00:00:15.654081+01
6	auth	0003_alter_user_email_max_length	2019-12-31 00:00:15.659779+01
7	auth	0004_alter_user_username_opts	2019-12-31 00:00:15.665669+01
8	auth	0005_alter_user_last_login_null	2019-12-31 00:00:15.671751+01
9	auth	0006_require_contenttypes_0002	2019-12-31 00:00:15.673059+01
10	auth	0007_alter_validators_add_error_messages	2019-12-31 00:00:15.678854+01
11	auth	0008_alter_user_username_max_length	2019-12-31 00:00:15.686533+01
12	auth	0009_alter_user_last_name_max_length	2019-12-31 00:00:15.695909+01
13	auth	0010_alter_group_name_max_length	2019-12-31 00:00:15.702415+01
14	auth	0011_update_proxy_permissions	2019-12-31 00:00:15.709682+01
15	sessions	0001_initial	2019-12-31 00:00:15.714407+01
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
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	10000000	0	20000000	1546297200000000	1577833200000000	\\x52d91126f6a2166eeb1af9678a1989fc9a56da5962ef57d2d9bd26e72f7efb4516b5c04550fb5c43c97da91ed92d6469f2d5c8f67765c89f44fbd21cc551180f
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	10000000	0	20000000	1577833200000000	1609455600000000	\\x0f6534fe5f700c2959069d0bbb4cd3b9e8fd873a32df346df2be188ece0ac9067abf518aed2df97a096477441c85b570832e7c2e286d88bef8c2078719c6430f
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	10000000	0	20000000	1609455600000000	1640991600000000	\\x80ede0348ac57ab05f18b31b92c45f72e48e6033ef0a5a437fc691348ab49ac491208e881bd61e977030b77d7c95fba21479a15131e95d41c7aabd9ac69f1f01
\\x76bc0de1d05e334e27438a7ac6f4b5b8f7ffeae408219ef61fe655d739739c28	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	10000000	0	20000000	1640991600000000	1672527600000000	\\xe12aa497b0c248ea3da0f42e3a904662afa42823e78a9caf72891422b0cb8de9e936b548969788ad85ef18cdc8f8b7547c448bdb724a7a88b00cfc3d7122a007
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x3376a984bc0ec5cd04d943d775722d90a49f33268cd840fa7270005a02d30312	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x521d5139e841cb83adb717a9e1e570bb8052e6e9d815d47287ec05e0f6942d3410986a514834351d8c89549a92be677f706013d700ee73e3798b2547523b90da44f39122f7175d13b77b221f784ccbef85d46767ec20405cdbe2b2bf8c691601b3258874d27844dc073185f18187fad42dc30464f8d985b976f1509a45c327a0
\\x3fd5b118c20863603c4bbb6e397aa282b40f5078c73658dab268ff651d195328	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x72ff7aceda9d7e8517e0f2298631a998bf2a381dad0dd063bc5ad7feb15cb4b807881363b6167a91d36f68fe047123f44fcebdd8e5875b17ccef6eb92f6a998200f99a381a8f61c601b9f84f63cb67e76525c3c8c9869a624b0a9b96fde4630b1834347cf750ee842723e77ab8fe2a7a05346e3232bdafa031becd4236787573
\\xfa85baeb623c9754b7edb0165b78dd143a6cac1078610b9e19fdec2e5e90e28a	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x46a3c9d2fa475415f47d5b9b3054a2026a9f2dc053874e6e5e168485bc4cab612fa5da45a9afdea36fd43876a5cad79ec2b6f51ea7e1859a4c97a447dcd08686e0dc9d330c5d8739136f049240c8a12d6e6c6a820159be8a365b606ba38d34d4d231b4f3db446d590fda404e4cbe6b058faa2d99bc10583e1624b46010f7477a
\\xaa4bd5fd2dd2bf41ef9475068a09ced3b4fd48b2f2aa8e8c4ac5dbb6b3971d56	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x14bc489bc751856de5d5bba3c0d4e6ce1acc4b872b590ef517b75cec0400f69f025fe3f2ea12feb99d54b1cc3de4f406baf9393a25a7e5ab21623608cedfc872a3c7ee7adcbd1c40efd67eff9d81a3d39e8ac76e301ab5693373bf63c17ffea6fcba8b4d245b5041083a4c72c917413202201653ed6fd0178f24e609aa41be6a
\\x725213269b3f640e52e8341345e44b364a25fc01b1f97690115ea1e106a2516d	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x7e730bfd70aa4b2cd4625dfd7676ac158aadba5108c2a7b281c087bba9f93952d348d138e3c41d7f91461b668f3d8a9dd123fc5f70e038eb5b97675592fced3ca04838e917d6a664d26d6165778d89f3148d24be7ba2630352a78e5a145fc2b4650dbd1e56cded1a5ef993ae6447b0e3eacb5b01dc760890662a47733f651e6f
\\xcd43f7b7553d2e28f8b1d9b7b6772c23f26a9fdbb0af976ed2524ed97aa5cb2e	\\xfc9165705c124932a55a38f2b0063779773676f104bca21c31594e6b109b52e3cba1876a064d6007225f241a4fc27dcdd20ff7be405d39778cccd7dff08dc62d	\\xae41bcde1771e3994bed4e18d7f20064de04070caa3c8655336641be91cea10ea21d64bd86fa28b1e163e2fa31b57ef3fb4241d6790453aeda91048ccd2c3a38036e620471e0827d284b5a0be514ee3ad291575dfdd901c1fbdfe76d4c6577d3ad4672e403c7c01056d611dc336e17df5af05f54f9ac61ff155d479512b73756
\\x51853a1d1388b81b43b95b462b818c42ea5c935e2cbfa56c61b8e82abf3a1046	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x1408c57d14297043c572a43eb6236dab931cae0ca5afd1e5ce79e50ab13b976a0967cc7fe7d252f0d3a7eece5111931d782f47f6bb3a77c1104747a7df2155119a4ce46735515e0dae4df82566901ca9bdc3024ecc51ffda29a85d85338be6cad8e8171976a20999ec19270ae6ae3f1b8ab8bdbee549af02e9e9f724dcf2a365
\\xf16519d55580147680a47784cf8ed0311f9e1486fc7d4be715fb2153143a3ecf	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x7663c743d64d610c8398b50fc2367819cb0f3b9ec46b2a8857f538977ffa3909dcd5bdf9d02ce81bfd5598f9a199693f620f6ec3986c3ae7320db4dd40ef1625e7b9e026530cbe72f56583da7720d927c560e88272577c956fb8bde86dec264c20e21bf583b3f432c1041a78206d0feb37a4fad0e9f322c1cc8cfeb4c833d2bc
\\xdd210c0852438aa105f31991bd942047a4a3f790ff1e0949c8461ee958f71804	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x549d1dd00a265914d3b8d0d35ff30546212f7f3b8c8a926e01d3c6229cff48dc0188d597cc087dadc791e9fab08a31b9851487922ad3cbb44d7d7caafaf93e445525aa523ee1761ae3f2f0e3b255227c1293a231ae0cb22bbb59e75b80216521f96b54dd0b4997a1a0d0d0a06356b56458df9a95e5286c506488dc1f3edfd0fa
\\xba61a131b373ce4ccb74989682c1d54c056f6e8cc9435b0a5bf197fabf15b310	\\xc7c81552056d3c3df38d7d9655b32ec930080a5fbcd8a72833d0cdb41ebed8fb8d8337660d8db6fabd1d9fae828702e356787b86de7aa222432556d07acdaa15	\\x6d0787c231e9707897b493c3056c1b1336b15ca134943755a0a5fd7dcdaa1759707d3d07b83ca9ce2358869b1cd558f4ae4d1495485aef6a948448b0cfd3299f0e4096406dd3e6d91986f1da5b5e40af9a208d95136407606f594c05b1581dda3226782608b469826e5c468c82b4fff6d97dc311f9bb85b2782ae6643fca338f
\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	\\xa3e728aaf177360a81dac474f1e86aa3b90c0a2c430c433f42e33f9503f0575c2ff9d6cca5dc61c4740d03f1bc5bfe8d2f0f5f4cf2aae2968f0211ae83ffcd58	\\x65313a0db0657acb9ac149d1c2e714eea40717595756bdb31187171ef57dc4aabb930ab487857c0ad122ce1e0db3a28975feb8234329587c9147ee0bf8d60f5afeabd15686343bd7e1979b4efbf9791a0c703ff3ed028c05e74c005ad635c8c343b6279ca0764727d402ea51b768e5838e5accba6b3bfdcfb77b5b006005a683
\\x4f017b4502f3fc5e4ae50891b82e32be47a303b3bc2abf26ac68a0b3427b754f	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\xa95b086bc6386af22ccee6870066ed9d8468bc8c6a69c301f17c2f605d20b8e3deab8efabbc4db763b1f2365cdd89275a630e71e15bd6ddf09f12481bc87dfd3ee812949f3312707c4027f40db0def4fab7c5bd442f03803318c2e50251be5cdf0ec00e1322f72fba8dd31570d6c3d824ec8b694b8b73ba720410f2b4331bc76
\\xa81d83dcd5d8aa4bfca3e06bb9a09174093b579f10cf80d092ed2bc029d8f53b	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x1a57ac5c94c15db6d8095a672babd340e52d0811e319f91e9b1400ae49ecb342e660cbfdb90124ff086f53edfd6103afd7d0a3ca52a3cfbd901cfb5c456523ce4db8bac554fd8e0ec177ab994cb4e7ee22fc84a00ccf70d536b244110d41de54126206be9ffab01e4dd81559b7c095d5461941181b8955c3f4a35dac49770f30
\\x8378674310b12c3516b5c45130b19fa69a72a654a25445b7472c6e692125870e	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x877125836963d852d2d0e160235c058864ad51e549e2390477d01893dfad013ab51cae49e98f467d52adb54cf21655889e45316f03da3547e5d046d617b06822a05e5720e4719f245c1711d974ab6a3e3674b564c04c2fcb6505ea54222409477438f746778ed4d418864e253f11e05f6986996dc8c2e885a4824bbc1e0c28c2
\\x191ff0bdb47189fb5c64678d4df5b11d21a27ec3458fbe5524ed34d80ccee0db	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x2fc16fdad48a86c6ccc51394aae6e8aec800df7b71b3ba1e9e2fcc78acc7ef86c33f4404ebac557156bae17a330bff8287004ea8b979f74aa4dc7c9cddf33b6880f3b3d603e29455aa5d35c9a8e8bfb1625003413332b0a27a7d24802c8a1ba21f34bbb6aa5ccaea6433099559b77a6ecb80efc12e09e0eec07e5fb0921c7f8a
\\x4cccd36f630a8c9692093439a2d8a724dda990d9f6318952ec6c59da87b1d7c7	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x6105374379ef94adefa65526fe70f03dfbe985594b22713793355426cea9445acd318af72b80122ae267b6ff20b8cefbdfbefe49a46a4a92702a9c325a901301a9978f7d7fc21ada388dad62c2590a84237b8c1317644aaa8308ed70621c90f0cac90fb8fe3852e97f885bd5418ce58023d0e2e18c627c0755dfc397b7f88f80
\\xe2a0a7ae5eec25810c50377ad371d290e5503e29c0c7d0fb45771b3c1e465f9b	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x77dbe2c25ff3bd16f0470c4b2a3dbee1b44f9f7929388a11415c6ca710c9a241481804bdc557160f5a023ea7d923411c19113cfb54f275f76fd47a8a85e47495c2f47096513f89e74d0565f972d77986a0abcb691a8f508f163c3e7884640957e76bb8d2946ccccef5f94caf5952939c52c2cd76a2b3ffc9b94c046700260394
\\xbcfe55cbd95c24a22e42c4fd5e33d98edc81d9ab2ce2b9ea85c30aa35a29770a	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x0ccaaba9048bec59335ece15bd10e07398e2b327e9c69298e913129d1a18ea18ad8aafebf2f8230003256e28e4090bba82448d6abc24afbf7ed3bc9f6bb575af3cbea39a5ed9d95deb30010f785b315105414659d4fecb728f09170b45d8673753de6ef279b355c2c9c7569e7b513d0f7df5de6063078814eec001620512ea78
\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	\\x32c060fd8356705fd99d02173fda7bc7c5d9b0fe782afd71ad84f75acdce927d244a84c1e49d08681e3724de24d455c2519935e4bb4c502aeee7754a6a0eaf50	\\x40cd2f04196e6820fad46c9842a9abc7804bb5723bdcfba351f0bbb49dd9c5c6b8a4f5d6c84d9ab186c77611652e0203af4492026806b7e78c05a2e32921cb08eff1d6137b6dc84f27ca7e86501dfde8263bf70eb7520d6bb9420c1ff2710f915f560f3bb113ac72f24e0e2b8ddcae63752fea42b8d532728d1d44c16fd05ce3
\\xf4ed2e21728ce0ff2e1ec25b1fcc67fb2d87cde5e178761f6237dd18ea7379d0	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x9968e0281c562e439285a179e4e18f1ac9210ee1dcbd891fffb7aa60d624fc5500137db6de441d7d09232a4139ff96df051420d87f1410280408f09b83a4f33e525fa8f9b1498f33af4aa9d6b953abe6026eb5ee8338c12621d586e6fa6b6373756d1e863864e45556b8ff5a75a20e9979ada5ff630d4f6895597b347057e069
\\xea4de448a295ed7a4769343155c7154f2d8722231afa2b645100566bac77c869	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x03a356f13d0418cc45032f2e0164a58b6bfb62afad66f88d7eb3a0169025411e4acf5d5131ea2c8d8877e85af603eb155e72b4659630f9b2b55fd098117a9d394d34dc6ac2d39a53cdf94f7fbabbcd7c0f6d5e9c55157dd18a4c37e7514019d3c3d9685c677586772ea934c45bf8ef6c3da168872b325189595e948f985d71a4
\\x3063307755df623a9188bffbb9e68b3d026b3cfac7acd87bdfa2027d17a08061	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x401756a9b679a1a83c1bd28b8b4bc0f6a0eaa425219d906a1d47fba8fb0ac181c6ab1f2bb7c9c1e6cd10d0a9f2373c1736be0ad328712f1323ab523dd524948fd3fe118c0ce575b3d21cde6f4a7e4e176a20764ec72d02e008f7ef431502104e36673425e846a658f1c8acfe154e006c6f1db70c126baba445f584a41047bfc5
\\x0c6fcacd80265d8f41787a16038fad4f47fc813e54b6eb7d0d0ecf18a8737efe	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x9a6452222e224bc5f767bce4f3d37e6cda1e36c72ea3b3b8acc63617d8baf6f41bcb015df671642af2e5ab935b9f03afc11af7e03c825002414c5079b58f174d324c6c057e42e6c35cdb7198f8e3f7fb4523481d023e251b91d5685eb946710243f56ff54dcd448970121fb6673d5edf47d5bfbf0f0349d07b98c7c6aae6aede
\\xa895e862e248a6ed34fd97cf4d39e10efe034f93a753a2a3da305d1baff0787f	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x383654f7fb2463784ceba7fc9a5b157b135cf1d608d64fce8364a57fd38d559c5c56c6df76c0a2986d143a23f4b6f08287f5f49675237865a3139a55cb76d4afbf29758cbee71f5a68785bbd0d245496e7eb3a6902aedeeb2ed7bc4a53a323d55b4e04fe819614391c3727a48aa29ae84945a0236f9a6ba15bf4ecfab876be4b
\\x0f378f1b6409f437e7c94ad7ad50a0ceaaa3635199cf5d5adfe8f104a0002e2d	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x5a71596611626efce6904ce48c7dfa1afd06deada50037d95fd7ff8511f3e9da3dd7e8a2c9b946992a6c4a29a180423388f6ef21dbf875d8178ae75fee0383308cb38da30a70490fe21cdc6a1e3e6668fe0c7eb8445002e73df0f2a72bbd4ced840a3eda3439d616bdbc183e55e64e34150d5905dd206c9dfe3fa7fe55ac523e
\\x4b4add0703c75b5511274fda57d9ad33d6f3f3e649502a2498256225e08fe3c6	\\xa3e728aaf177360a81dac474f1e86aa3b90c0a2c430c433f42e33f9503f0575c2ff9d6cca5dc61c4740d03f1bc5bfe8d2f0f5f4cf2aae2968f0211ae83ffcd58	\\x1507ee7845745069fdbeb27189b830a0d2d1e3702793c97b588f5b9ab1927b25c03eace00a6dead50741363d52fd14d150823873408b2c2d89e27184357d3f9f2a6e6c1f2aff970b548a02765b4ca70a4d1ec2156c990e007e9dc49290c72856f8f182c65de21558c43fb1ca69e416f8044514bd1dea5e857c4fc894023b1bc5
\\x3e7a3bd721f21f354b1d4c27bc74cb5c0c532d900cca5c88bcc1f4d7dde3dfe8	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x87b0b1020655ef82004baf98f4cf885bd459bf3fb989d5f00a1dd02bcecda2d17ad9cf6e985665598b693b285e2ed661570092e7785f6f942e7f8c92adcd7c919bfe5845a13fa649f1c92632c63e919b9c015e4b8f80c02ba621e39e9e6c07408b7ae80b3e5ee78b9d5598778b0bbc466e0ae172cb1ddae1f662f92a42b57fd6
\\x40201f7484bc26a2974859916a1e3ea3cc17fe69abc422b69de77a9eacb3f4a8	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x80ef04150cb40a8856dc554e189dffa34fef778bca6533b95ba231b931e970d58135dd6b1d925e90ed281aa61fd9ce9c257fabd7da77bbeeed499a52dc87ae8a68c284720f310a1fd9cb39b18ca74786dd0200364215f23c213e793586ca1ac13d04ffef61b360511e9c7395a909f86a6839a36c5297a48bdfcdf5807c9269d6
\\x2a0ac23526f6d75d3a3556f127befb1516d8d70d2f8ac7a65ef8300fff6536c3	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x11cb6d75980dadf9cfbe718b4367a67580136497835cb985a4852e8ebea856f30248d14834145d03639af602b62aa35c2fb549d01ee2a371d6b6d7135acc4af3011d21e457cb3d5484dfed939f7ddb246e668c5db94d768e8ab274bd140d9d1185a4031a27bb42e0f75ff3ea67fc902d24c1c0ff9b33d6c974567d089cf89b18
\\x5625134abd8636d6e818d4687ce35c498295c2306d28fe6f688cf271d896a84f	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x44f9b302f3098e6d75131eb5938a109a92149d4a2213bf2820972554ac2e8d9d1166d60596b0944f1154cf77b6c409f5bec5acaf732405a1a60ebe130bbf3bf44e1df9d766cf0384d4441eb51fe5da4a8382dc0beced59f5dadc34149fe73269c2ec9057fab69047722c5e67613578cb01c9b70c6ebd1adf1af03d4e9eb0a176
\\x7f29bff8719ebee9376a79dc37ff15292f6daa81eb4e4a9c077864cb75744556	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x7027ecd28dfb74330d975e9b90f66ca942519cd370f83ff7ef8a818b8edc9382fbda9d7879b513658644dd749025343e5041af3c5e2ea6f7a78335db652c04aaa2497a910ae4866a5faf23b0a09a3e07bf45c2e1db67c2be6f0be122d7cb61c72c547302e7ef37d90ffb2af2c8764dd73770204cdb5ca2c15eae8a980aa3b59c
\\x343138c7b28d247d5f3039bd14ccbc38f22d0d103f67a9b9fcbbab61e21987ae	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x26fdd89ac6f6cd39c198e62adb00e88f4b1b91436876922652be1ea0f5f225e3b5485e865b2483f3277609aaae335dfffefa068adb68db1797560753db02cd5c610c3793b2a765f643abd19ce48889dd36e8e132c17612a89bfd4e6261cca15540ab0a20b10b46dcfa1594e964ba3c090b245a92865c94ec83100eac1d0f5bad
\\x4dd658b97ec353b6f78d1838d2d434d25203f1ecb0cf70aefbb8210ba0ebe6e0	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x846d63b2f85379fc10a064f761972ce85cfe81d6f341e0df6015117d114a4aa2da996f2424282cd4dd7b8730974fd719545d65021acc7ae925f95ccec80cb7afa6c5ea232862174d39833475aab205b3e3254c2609aebffdfbf02e37a44e43096c628472bfee4abfe70e7d754a82be23743072dad86df7f106de2c3deb6f7799
\\x408bd8ef75c3a44e273b54b79fee6e318c8401b6d10b50afdc3f43c78cb7d1a0	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x8aa55f3a595bae32e180c2caee11a4d1f41291a3681728fe6e854866e9bcae3c6404c38e917cbffd6657e90802958e0d1668da58ca3223229a77111d40adec70ffc46c41f232ceb25a08869f3dfd2594408c406e0c2c6837c1597fd9a6afc5ef3a5b5cd7b92d864f8e371d93671a029befbfb9e371cf43cfdebfd2790ab5e314
\\x540e9bd868098e28a4a50a0da18681ec6e161139c11345e92fc0d0adadd9b831	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x3ac08c78ebd635a40be4d2106915864f7595e79069175a6eb89597a49c21782275ac188f9690c419939cb3f6c5b8a98cd0e604724749b9132e49faec498ad3a486ade454ea002143e4b6e8c6d51025262e7330162e078a31c11b7609cff1b9bae23c00108935cd39537abb074f985614d35116b49cb70530472311d934f514a0
\\x8f1c80000da00365e45176b86ae537754fb6e3660b0ddfbb1cbe569b4a17ce1a	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x4f8ca5ca944eb10307817e28f0e1606b4c144e0e6fbb36adc6967627d7c4f7214fd26c5321211b1c0645a2545d94e13afbc84124c84e27eaf995e722f91ff37f126c97c0dbddbc8fcda0f0b356f5002f327985017849451a19acdb6997f0136d9a105feeed481405431d9b7771a3516b4d6b52c85333c15c95df2f4f786fbb9a
\\xa1c536051cf36b0ae7ed864ae79d7c6c6493972b216e6a9c3769fc7f205d94d3	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x95566e70e6d19053fe445ece04ef8a282b1caeb870f7c4bac8637cdd3080984653a5289681ad1849e87fb855db62ce48183612350498e5417d4ce5e1d807ef29e6348e03aa3d4470b6fd176184ac803320a3e6ea2f894d2507c25bebaaa0ecb3c615079da0d215e21188499d8660468bac0d52e689c13750f414753feb92e10a
\\x85288b1fe630639f1c9be3fb2ff981aa0f4f552f1073f94e1e33a2e8abc413c7	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x1dc8c1a3aca2772aea8217e4678d419993beddcfbb68641d0713eaf338e8aaf24898d36b72c2dd2870306aa15dd12e1d2edae95880586f4b70c409cf302782213d8d83fb98e6fcb22b2e8c9ba39ddd32cb1921922ddd70c19471048a0b8911e498b450332490dbfc82a7778db5a62d72700b6bc1024c145c448987f5ede71ccd
\\xb4cf2d1d29863f34202488951e81593d8c0c0df520478d9146ff849c3c800721	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x7b6911f3b09526309cf41b76bb24a1838b09d3e7857c8fb9057f39e57605bc2d50cac41633d648aaa41c743b992ae4daa00d0f3abe4040a8230f191139ac36300e2dd08abe27bba77d1debb43c4e9eb314713d14ec6a8eb6883cb46f2105b06813f64021a833b663876e2256da83a2198f5883eea0fdce90e30eb41b6e3a570d
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.365-0242V6TZRPBCT	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732303030307d2c226f726465725f6964223a22323031392e3336352d303234325636545a5250424354222c2274696d657374616d70223a7b22745f6d73223a313537373734363832303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232303030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245545930565245474252534d57395433483958434458354e5133565a5a545134313047535858475a575341584545424b4b474d30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22474d37305733574b56534644303144515647314132375a4b4e413137463444343147504e365a4b523257524556483853304333535a5a3043534338463853415a314b5950413736414136464d483133593053465346544834465747503448565437525251393930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22444548325136385754594e5258345750503158464d36543159304e52325258475057463558434b465833444e38305651484e3030222c226e6f6e6365223a22474637413335443658353046434637594551395a4157544e303631374833394d4b4e32524d534d455831435433374e45514b5a30227d	\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	1577746820000000	1	t
2019.365-01C33E8KNPCDR	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c226f726465725f6964223a22323031392e3336352d303143333345384b4e50434452222c2274696d657374616d70223a7b22745f6d73223a313537373734363832333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245545930565245474252534d57395433483958434458354e5133565a5a545134313047535858475a575341584545424b4b474d30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22474d37305733574b56534644303144515647314132375a4b4e413137463444343147504e365a4b523257524556483853304333535a5a3043534338463853415a314b5950413736414136464d483133593053465346544834465747503448565437525251393930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22444548325136385754594e5258345750503158464d36543159304e52325258475057463558434b465833444e38305651484e3030222c226e6f6e6365223a22583038315659414a52464656525958464b5438334442394b4b4648534b5647425047465830334e31355346444144424131414647227d	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	1577746823000000	2	t
2019.365-R13E42KC4DRGA	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c226f726465725f6964223a22323031392e3336352d5231334534324b433444524741222c2274696d657374616d70223a7b22745f6d73223a313537373734363832363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232363030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245545930565245474252534d57395433483958434458354e5133565a5a545134313047535858475a575341584545424b4b474d30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22474d37305733574b56534644303144515647314132375a4b4e413137463444343147504e365a4b523257524556483853304333535a5a3043534338463853415a314b5950413736414136464d483133593053465346544834465747503448565437525251393930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22444548325136385754594e5258345750503158464d36543159304e52325258475057463558434b465833444e38305651484e3030222c226e6f6e6365223a224143354a593530524b4a373637523130303056474b53315333534836485346304a3144313751323532333534475a45524a375a47227d	\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	1577746826000000	3	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x3376a984bc0ec5cd04d943d775722d90a49f33268cd840fa7270005a02d30312	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22584a383958453745475050445237344a5756524e4e5a4b434e31395052385a525145464e513538323033475738355046515933343835434847364d3654424b563641584830484d58573150364842393857414d4d31534e59585459463756594e304a4b52523138222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x3fd5b118c20863603c4bbb6e397aa282b40f5078c73658dab268ff651d195328	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a57445738315454375a3530324a4d4b4347443333393531595836575946375a4e485a37524a39454d33414e3533365443524a59383757475a4e334e5a31574e5a36333735393539354d4d4a48384d46343638305153364538534a59384631473444525a543247222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x51853a1d1388b81b43b95b462b818c42ea5c935e2cbfa56c61b8e82abf3a1046	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22335a335036524153513050543750393039533744464238514b3459583259524533334a3239534a44535931333846393947454a315a4d50594556454a393946325137444a44374a504b314538464137565a33544a4530395841333751594b534841483248503130222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x725213269b3f640e52e8341345e44b364a25fc01b1f97690115ea1e106a2516d	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22594436565859364e563850543858384e5a534530365a5944534b395237583639345a535a5a315a384b323837384842474a4b3956513042515a4250525432304b5a304b4a3839415157375634375332544b5837464436305a313958363850345047573348573352222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xaa4bd5fd2dd2bf41ef9475068a09ced3b4fd48b2f2aa8e8c4ac5dbb6b3971d56	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224151594453364257583932535853453556363947433332333843455430595656313733454d56444e4e544d524e3933545a33503350514e48514e514359315342323652504735414436324b4e53574e425338544336344543565730364b563344564544384a3330222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xdd210c0852438aa105f31991bd942047a4a3f790ff1e0949c8461ee958f71804	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2244505a53584459474d4b4638535046355a58593042315a43344a4837424a31344d53594731485639304d435a4b48595a525a483852334638443856565646414a574b38423044355944324335533348583941394e545a5651415933375147474241444642573052222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xf16519d55580147680a47784cf8ed0311f9e1486fc7d4be715fb2153143a3ecf	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2246475146394e31504b5745564d524544535037364344485137563043523944393447454b30503057304848303254385054503348585636463537314d515341324a37364d34374456374a4332334b333034423550364d3336353745485045464e584d5242343052222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xfa85baeb623c9754b7edb0165b78dd143a6cac1078610b9e19fdec2e5e90e28a	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22574b565a4b4454455a4b5758473537305058354b454643313643533334523330575742344151513952454e4331325a434a4e3444534147354431544a454434474b454547464d4a59564348524d4847543651334547585a4b584b444b3346523230514552343038222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xba61a131b373ce4ccb74989682c1d54c056f6e8cc9435b0a5bf197fabf15b310	http://localhost:8081/	1	0	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224b39514e4e5a58574b4a473647314d30515354324d3450594552334b5135444e4442374841504851463335434d563453385a4b305948444346355852353353473151454359444d5853395142414635574b54503633363442483853454657373737344342383038222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xfd3bdde57aa440eb9b9f938303e79ccf5cc1bcc89e6048510804b86bb9e5934bd7a23bfae07eba48597595d611d3994116e202ce510a24bba7e384fa51b8661c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xcd43f7b7553d2e28f8b1d9b7b6772c23f26a9fdbb0af976ed2524ed97aa5cb2e	http://localhost:8081/	2	40000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2231564e4e375439464759375a5254364d5a31514e4741454253353948485448374a5a43524835385131514e5352465a34524d4233573731374156394b38513954534d514d383334525942594e565048594235474348425847505236513744444d31475938323347222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4f017b4502f3fc5e4ae50891b82e32be47a303b3bc2abf26ac68a0b3427b754f	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a39514438584b574141583145565957384d434a395143585352443132435a593846584b573030395139424b424e393058385343473043544845414e3251363343525730484d43514a424b4231465045413934375a3937484439485a59514d5048364739363338222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	http://localhost:8081/	2	0	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2243473947304e3242355742354d4839305a383746363246593546434e594a315731524b503547544b4a344e5239364d59464459444431333737335a4859363739483859574b443234475a57444538344d314e535331314d424342373958334e50474e41384d3338222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x0c6fcacd80265d8f41787a16038fad4f47fc813e54b6eb7d0d0ecf18a8737efe	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2247435831315436305959504b34564447574a4d4b4432314150304341504132475831575650485137504d4d30515a53323338335053334e573356383530313931323742315a5848524d4e56443254345a4d5658474d4233394142583157345a3450515a50473338222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x191ff0bdb47189fb5c64678d4df5b11d21a27ec3458fbe5524ed34d80ccee0db	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223048434b534736564748415457445257473159445031454654464b535732574d454e57385242485837353338594a595a5748454447595956504654395238383744425a4d45484b343939564450444a435933504a445954414a5641444447564e53354d41383052222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x3063307755df623a9188bffbb9e68b3d026b3cfac7acd87bdfa2027d17a08061	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224b4246393936424a42525a5353344632344d424b4246423051595a39313239534e33355a58433053384530464e56304a484e4a385a544558324b545750534257524547454758534b4146343230573052334137323659363739463148504b433248473436593147222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4cccd36f630a8c9692093439a2d8a724dda990d9f6318952ec6c59da87b1d7c7	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2248444e345232463835593051535331325242533238424e333539584d4e5043424d35434748415959435459424a4437454637504b4d4654575348583654523352534e4643505658595835545a343557473844483050564b544e4b3030523638424d4b4b34383030222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x8378674310b12c3516b5c45130b19fa69a72a654a25445b7472c6e692125870e	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223352455935475934334b395735523746463253334e4541315057314736535335303356454152423646465a3542464a464a585451564458445143415251325a5732385738444d5454314b473941503743414336584b3256434144333547514e3232425054413238222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xa81d83dcd5d8aa4bfca3e06bb9a09174093b579f10cf80d092ed2bc029d8f53b	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22325135473843365a56414256344b3133464734473043435650373944585142454430574246465054475a5333415444575131413447484843465237595a5751385150525744374e36423051434b5050434a35335837565756525038474454565059373237363147222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xa895e862e248a6ed34fd97cf4d39e10efe034f93a753a2a3da305d1baff0787f	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22523542384659424b413534475847454645314a345a42595357565a3153503554334d36575031394a4b42533641463532345254425a563454335659325932444a524d5a5145374d5a383157365045473151453842414e5a54424459574d4836333650525a573038222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xbcfe55cbd95c24a22e42c4fd5e33d98edc81d9ab2ce2b9ea85c30aa35a29770a	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2230353143385145455133504438584b3958464744445145505831303237565348563632544d335147345133353937564742544437485a4d59374a48383259364e4a4d4351435a4b5a3342594a365446585039454e324453415441474e30524a3847435032503147222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xe2a0a7ae5eec25810c50377ad371d290e5503e29c0c7d0fb45771b3c1e465f9b	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2258544d5a463937363333444e45354748454e5837425335344735573933353254444d525a373647544258353852305a4845465736395745324d45484d315236414b5451574d59584b56385a34354833503735525259575350415856574534514d5639424b303338222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xea4de448a295ed7a4769343155c7154f2d8722231afa2b645100566bac77c869	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22504237534e543430485a3339304a59575352485a4552383641574a38323830333747454b51573138483136383556434a38354b4133584b4a47415332413952364745354b39365a54573253484d4247364a39563458465350384650395a42324d315a414e303252222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xf4ed2e21728ce0ff2e1ec25b1fcc67fb2d87cde5e178761f6237dd18ea7379d0	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225643434651595246474d51445331533633303159453633315743335438484e473632444639385a384741395236583244315a4d425a3045393630514643513838584b59484b4139424b4a593654304e443039503052574d444541564d414a573636535a4d573152222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	http://localhost:8081/	4	12000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a4e4d385734394252474b435444315a524a58523450454a50364e5043354a343234514641465438413552315330595a3239375a355a334d3557463036585248344538484d4846325851394b4338484e4b464151513954514e3137374431485343594358303052222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4b4add0703c75b5511274fda57d9ad33d6f3f3e649502a2498256225e08fe3c6	http://localhost:8081/	2	0	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2253363831544b543337314a57433032303648595939485341504237534446594b53385344385a4e5737565232484e37464a363635374359564d44335348545447305638374439364854364d475354373031335752355a4e5034324541415a524452434b41303230222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x0f378f1b6409f437e7c94ad7ad50a0ceaaa3635199cf5d5adfe8f104a0002e2d	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22533035415a53345254364d50573335413832573156323030353139464a52313742515846454a444d3841324838514a57504532463356435a444d3950324750523931415258434b51443748593058514347465750344d42475254323336354e3439594a30433338222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x2a0ac23526f6d75d3a3556f127befb1516d8d70d2f8ac7a65ef8300fff6536c3	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224e304232435a344d4a334d5347445a3230543642584250564336563734454a53384131423647353136303242304b564e37424742514433434b56534e384b50365445424d34424d54485454534b5a5a364a5a5152414b53545a324138314741574a4d4e44523047222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x343138c7b28d247d5f3039bd14ccbc38f22d0d103f67a9b9fcbbab61e21987ae	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a58374a363959575a33484d59514241514e4d584e334650533556434e4a5934534456514b45355637543654314839524e474a444b5459314d38564d5337464444514657454e303259543053355647335332414731525845455051423338464e47593230473347222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x3e7a3bd721f21f354b1d4c27bc74cb5c0c532d900cca5c88bcc1f4d7dde3dfe8	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232544b5043314e4e425333443331595342463256483456364a3241394151474e51354d4a3330584a36325235385846375437353136365234364556524b30473644475331564d513948333236363151474254365152365734484d4845544e4351424232444d3338222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x40201f7484bc26a2974859916a1e3ea3cc17fe69abc422b69de77a9eacb3f4a8	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2239304258454a4634563635385352524645504b355047544250514d464d5151524851385842454458563558384853484535335758375058384a37305648344a3947524a4a525258524e3633564d37355a4553364431344836524e544b3939464a5a394632433038222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x408bd8ef75c3a44e273b54b79fee6e318c8401b6d10b50afdc3f43c78cb7d1a0	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223153574d3535585841434457545445595a58584e365a52453053305a575a3558394d3759474343534a3842394559543246354558564e35575846515832484d5239514b4b303339394a393333314e333938593543475a443054355350324d5646414e4439473052222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x4dd658b97ec353b6f78d1838d2d434d25203f1ecb0cf70aefbb8210ba0ebe6e0	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223947563833413530354733394341584742385a444858434832433850385450305144534d34463039385146543750414647415350474559473939534434564a374e4b50473241384d373454314a423250433639425333325357563248474641354847345a473330222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x540e9bd868098e28a4a50a0da18681ec6e161139c11345e92fc0d0adadd9b831	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2253535856423139564a4b4e5439313247565831584143564a3948484534333236584d37533748534e3347584545343257364538415256304e5842524133504d5a5737593837394a30334754393441333239364733465944594a3452375a36374b30455a57573147222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x5625134abd8636d6e818d4687ce35c498295c2306d28fe6f688cf271d896a84f	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2250523954374636545939485338544e3031304a50434847395032353642344d4d583335534a423533375633544d51315a30454b56465652343548325248545931414e45473245564650415331344a4d524d334736564b4b4a36515234504a4d5953395750383347222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7f29bff8719ebee9376a79dc37ff15292f6daa81eb4e4a9c077864cb75744556	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224131395445534e354147374e4530354d3242433646574e53324b4347394831374232584d5354414e4a5438423950464b544a424131455a515a4654314a313239353132514741534a4d39535731394e504736535a355757365443354543504a5832434b48453130222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x85288b1fe630639f1c9be3fb2ff981aa0f4f552f1073f94e1e33a2e8abc413c7	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225032303352344a4b4a354450304d335734413451313033374b4d3248444754455147574d53374e504159433153463048575a385359453335474e4248345359515252473442505a4633354b335848413852314b4756324848464d50564d39474b4e443354323330222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x8f1c80000da00365e45176b86ae537754fb6e3660b0ddfbb1cbe569b4a17ce1a	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224443435353515a5231544548423742364434585657384e4335464b44304d4a36474437514d35513658454a5a5650385a4b50535634485343475447485a3637463058574341484e334d515a46343232375434455042324b314b534b4e5831484b5a595645303152222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xa1c536051cf36b0ae7ed864ae79d7c6c6493972b216e6a9c3769fc7f205d94d3	http://localhost:8081/	0	10000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a38464d303047373343374153305234365930424359413733534d303250474d3456424833513457464a424b5436425843484132503258363742344354325952565a584530364b53475a3157414e444d5245394446593056314330563246305457314d4e523330222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\\xee3663ad77b1b25d509216fa434f7d294694f9622941623e87759b608fad5f45ee1e21b4de20eee23a709d1e814e28c7a4a12839ce147bcf8c5c2cf98bc7203e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xb4cf2d1d29863f34202488951e81593d8c0c0df520478d9146ff849c3c800721	http://localhost:8081/	0	5000000	0	3000000	0	7000000	0	10000000	\\xc8df2daa4c573867ad7a2de049c915b6d643189d256ea4cd57421e101d366d08	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223951305338543238514d363645454b58514a4439374a38464432305137475031595a3837514d4637325837454b444e38444b4135514b4d35344b334754564b5230484739544b3652395a4b4458373856514139325a4e57414834374b3842435035334d30453230222c22707562223a225333464a56414a434157573646424254355147344b4a384e5056423436363458344e5141394b41513838463130373950444d3430227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.365-0242V6TZRPBCT	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732303030307d2c226f726465725f6964223a22323031392e3336352d303234325636545a5250424354222c2274696d657374616d70223a7b22745f6d73223a313537373734363832303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232303030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245545930565245474252534d57395433483958434458354e5133565a5a545134313047535858475a575341584545424b4b474d30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22474d37305733574b56534644303144515647314132375a4b4e413137463444343147504e365a4b523257524556483853304333535a5a3043534338463853415a314b5950413736414136464d483133593053465346544834465747503448565437525251393930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22444548325136385754594e5258345750503158464d36543159304e52325258475057463558434b465833444e38305651484e3030227d	1577746820000000
2019.365-01C33E8KNPCDR	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732333030307d2c226f726465725f6964223a22323031392e3336352d303143333345384b4e50434452222c2274696d657374616d70223a7b22745f6d73223a313537373734363832333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245545930565245474252534d57395433483958434458354e5133565a5a545134313047535858475a575341584545424b4b474d30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22474d37305733574b56534644303144515647314132375a4b4e413137463444343147504e365a4b523257524556483853304333535a5a3043534338463853415a314b5950413736414136464d483133593053465346544834465747503448565437525251393930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22444548325136385754594e5258345750503158464d36543159304e52325258475057463558434b465833444e38305651484e3030227d	1577746823000000
2019.365-R13E42KC4DRGA	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537373734373732363030307d2c226f726465725f6964223a22323031392e3336352d5231334534324b433444524741222c2274696d657374616d70223a7b22745f6d73223a313537373734363832363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537373833333232363030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245545930565245474252534d57395433483958434458354e5133565a5a545134313047535858475a575341584545424b4b474d30227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22474d37305733574b56534644303144515647314132375a4b4e413137463444343147504e365a4b523257524556483853304333535a5a3043534338463853415a314b5950413736414136464d483133593053465346544834465747503448565437525251393930222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22444548325136385754594e5258345750503158464d36543159304e52325258475057463558434b465833444e38305651484e3030227d	1577746826000000
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
1	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x0c6fcacd80265d8f41787a16038fad4f47fc813e54b6eb7d0d0ecf18a8737efe	test refund	0	10000000	0	7000000
2	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x191ff0bdb47189fb5c64678d4df5b11d21a27ec3458fbe5524ed34d80ccee0db	test refund	0	10000000	0	7000000
3	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x3063307755df623a9188bffbb9e68b3d026b3cfac7acd87bdfa2027d17a08061	test refund	0	10000000	0	7000000
4	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x4cccd36f630a8c9692093439a2d8a724dda990d9f6318952ec6c59da87b1d7c7	test refund	0	10000000	0	7000000
5	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x4f017b4502f3fc5e4ae50891b82e32be47a303b3bc2abf26ac68a0b3427b754f	test refund	0	10000000	0	7000000
6	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\x8378674310b12c3516b5c45130b19fa69a72a654a25445b7472c6e692125870e	test refund	0	10000000	0	7000000
7	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xa81d83dcd5d8aa4bfca3e06bb9a09174093b579f10cf80d092ed2bc029d8f53b	test refund	0	10000000	0	7000000
8	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xa895e862e248a6ed34fd97cf4d39e10efe034f93a753a2a3da305d1baff0787f	test refund	0	10000000	0	7000000
9	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xbcfe55cbd95c24a22e42c4fd5e33d98edc81d9ab2ce2b9ea85c30aa35a29770a	test refund	0	10000000	0	7000000
10	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	test refund	2	0	0	7000000
11	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xe2a0a7ae5eec25810c50377ad371d290e5503e29c0c7d0fb45771b3c1e465f9b	test refund	0	10000000	0	7000000
12	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xea4de448a295ed7a4769343155c7154f2d8722231afa2b645100566bac77c869	test refund	0	10000000	0	7000000
13	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	test refund	2	90000000	0	7000000
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
1	\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	\\xcd43f7b7553d2e28f8b1d9b7b6772c23f26a9fdbb0af976ed2524ed97aa5cb2e	\\x5389ebe4d7b19ea93661b91ecdca36c0d7724d8f14eb4061249fe37770acfe7bab96dd23542e99c27978c6fafc3ba1e15eff4038215d9221ff6ace1c8efe840e	5	60000000	0
3	\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	\\x1b945c0836e9260ffcb48e8743503c1a19a0591014596c915eefd3a8ba883f19d5e64be7d5c4c79c07b0467bd2e0329892610cadb9d73f54357d67028332ff05	0	88000000	1
4	\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	\\xcd1a84b690ad20f633b0f5225323c8fd0d5e8f186afba692f9cb957934d29085a9a8894755a9b9a410c3a1ece37b22c84f874844390cbcc7d21ba3299eac880e	2	83000000	0
5	\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	\\xc2b46ff97608bcd98a5db1004a68d4f3f4e382a0f5ae52cde58517b855dece331b0a700f423835c248a28a0744b504a91b4ccff36498b67cb17d6312ab05bf04	1	93000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	0	\\x216ed2a36705aead83896dc9ca9048d1d6d211eb5e85845845d1c8bcda591dace6ba7e5cd21b3c11dead32dc1f8ad11876987bf69f6798dd21a0a8e00987dc0e	\\x32c060fd8356705fd99d02173fda7bc7c5d9b0fe782afd71ad84f75acdce927d244a84c1e49d08681e3724de24d455c2519935e4bb4c502aeee7754a6a0eaf50	\\x9530347fb8c2802b44d9ccbdb260b475b371de0705f8e08672ab203b5f3024ded6d479ba86910088b8effe2dbf469b5ee364dff7470234cbf97714670b56c2615e46e91dc5b4665f7279626a22ef9759063d2c0ea1760a72dbf59a91d6f2569e853199f5ad72abf24ae24111d68d72ed7033f4d4325f34c24b6c778beecfdece	\\x327b9b50f2088ef67b8d003004e681b67337ea6e8fd682c8bf6e3d11dd469a24abdcbb6bb30ff0161f7e7f3001e4d910784819db687bf8e84f15ec2e91f92369	\\x3e56981fbac00963a8527de836a4498ceed0e94bb44fbd7c754a59f7bfd90d936716f0c54c99feb3b5a24571f85d2385f6ccd59e63fd7c4b80664313701969f877010dd13adfff3a842921ceb80e77ee00aa84e712edd4cb22e9eba5ab7e1f4e4b18a884a501bbc681520a2b5e5d3db839de9df57505b26492c35c2674ca0364
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	1	\\xad31ebce1dddf3b48410a4cfc400f0f09c5e5ede2e8e1b4e4b91276f8f3379267027a63ab59e6fdd017b94b9b87fd65ac339acc802cacfbe8b85909f392dec0e	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\xa21c8faf5635abcaeb5dd9a9a61968c01dec617ef8f0f162684989c609566962a4f2164f2478747c06148a59182e16214d1748e4985dd11165692b939c75da6bf8cbae05aeccfa621525eaa16abaff84774b3d903c19134311dbd8e1e15b540d0140898352091ac45a4a9a8abdf5f47faa23f337fe21e0da77d523a08b630c1b	\\x86f7d7442ee19c4f198c9f6c5e82eb6bc14b1061a9df59995bc5b8dde48a370ae31ad8060fcd9c58900be6fa587a989e240994eece71aae42506a89ca3533bf7	\\x8a6fe03be6ebce0c82ee3d491ab2d5101f5cd8b1db28ab63c4743528f3c1fd0fa05a2988d210f6d1e50e99e47c3b9b38371c66fed0be097c3a9e9a40067f58383fad4830845ccba009323903d6eda3b7ea5e12cac4f1aae5591d8b51477c2e9151db498dc22c98055b92a0d0060e469e3b403b9e4f8cdd2b407231acbe73eff2
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	2	\\x24b5a24b2f19dae2c348bd08e00bad38fe5dbf09f1d9ae68c28660044971956ab96c81977e16fb4cbabd16ab6972e763e5f2d2c0aaed53e579e3f2de3c601a09	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x55f3c913a52e466f26b34b01fb871f8e9eb827160d64612ac3881ccd5dd4ac13ebde7e12e3ce88ac695c8c9b80d7a986a15e835b07f3c8d77b1c7fce5d4efa84e060c1a3398c716622735a4ec780dd8269f1d3ee5326283a3709c7f612c1cfe205e3a91cadc613f374f130f45c50b50e23e20fb8efcdba0ca758670700692aaa	\\x05e72b5151035205997f542902854ecf05d17a3b1561b16ca0314dff6c82c2ed5c1b4559f1c2e2dad644ba8b4f26ad61091d582d0dfedbe590b060d2335cd43b	\\x06de7be02ebb53a52d8ac97e374274365ce24f866edcaefee09b32007fd7de2e7be774f76ef7744ad39e8be4ab3989608ee6fde8f09a0f8da1dea794792fe5efb927eeb211fdcee1833f045b28b86a308e4e06c3694c6e5aef69376466c47e1513d2182720d4146f09ec60a9ad7ae639069a0cb1cc24e6ebe7481f1a446b6ed4
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	3	\\xf6a80ef2893fc253b3dfbd91a7fc8d106a106d4316bd21ab04c190c6b551c9a94213f30d689f6a564ef0215bd4ad87e652a9ac3af2ad1beed574485d42965a05	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x1615bc94b8d4e701ad02e06e8b4cb276f8707a538ce802e7938bf5e0c76ec068c1548ce1e006f699e649e91586b8cffe159fc1393dfbba0e73fc9d07bb06535ddb316570f6ad6107c04081d16490c63cc625babb2cadd1efe0ca4ecf6e11854ccd29ab1247ab705a89615eb16d07d23884a0a65ead2ac9abd05e50dccf26500a	\\x31acc86a92a4a5bf95ad9868d72a200e2db1deee7f5d76d395d157a122c206328cf271eb99ecae88e5374fe9c5d4c6ae273f4a2929aa7d3b3656e84d007152d0	\\x9390b04dd18e27122b55511421f4d945967ac0df6e318efdf6708e9597e57c6f8a88e95ed49f7e55aadac0bc4e0a81e524744255ebfd55569ee40bbfbc52017fef22c8a48ffbafd1437ab905f13752722aaa2568b990bfac2e34ddc65cfd9e3609c81792d37cca57ba63522d2afb5fcde9be44288a8daffaff6f811ba8646e27
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	4	\\x94221974e216a9e8fe526324ed2e42244829d004ca2aaa1be33bbd85930b7c20e4525ef2392caa48561a20189169d912ceafd8221913ef79ea0dfe88b046e708	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x0bcc818fd66ce17594bc49839b2c3e5f674578c9fa8c4c382aea7a704a94c170ac2d0209ec93f50bb290c3f9e39b71b34ac7e67dfb2b4c11a928eb374c950d1a14b8165b7d1de1f3a583e13cbd9f9c00422efe95d36747795773d927b687d00e35d5bc8f9fc4fffa764d2bc410e5a5e8d5273836872510fa2035bf687970f8b2	\\x596dbea9de5fd1dcba114dc48ea5923f8572e5fcd65feb1c48703692edbc39877bd836c9f31425daf58584416d4ffb9852d5e4e34abcbe6ce0b66ba98692e4e5	\\x013adb3a710d198fac74317556cb67d9d54f8f7a494e90da30bb86b6cf1a9fa4a3028371192805866ae2c94fc2d9f26f2434abf568a368153e5d832012fa85f89f1065eaa6344caa9194a2feccaa91ab634cb6cf66ba5d24c6360c12bb21fc226b2ac73588fcf12134e4ccefb56801dc6c922b82230ef67ee2fdbaec14282f05
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	5	\\x209584034795ba6ee34d138f02605cf25097c614730b6c4931c1379fc0d22413e09cc8615170258d2358e0ae1d49c5242613b9a182b375b9c480042ff069120e	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xaa35c4713d36edd8e2d4a3ca8e0bbb9a3e6d72d206d86c914ea9db9d5ab39dfebe2319d4c770f6c3ecb8e57266504d5fea94016560dfd08cde1e9bb57bb5cc0cd1823c4ffcb65fdd78c6e93b7e4dc3fcd6186f2f1b7faadbc490882001cefeaada34db264ceddc22b5b146b32c35a5bc3db374a5af40eeeaf124afb7e7ac01ba	\\x44365f37babf386fe8e82b94142628c783e6a4d44875c978d437caa05a3c485a2a55190cef3bc3e02b8c32e8d42b67d79408db52dc84d544731c4495c628bcd7	\\x2dc470c07a2d57d719ee8619244bf0d615b7b8d7529de6a6e4d8e82d666997d961d1c5b9042e01153222c78b845527f8e0a35a2bb2d012192654b3325fbe9ab66f91cbc3eb3ba50a6811e2f7699966e149b37df393b00d14cf3769a9760c922eee8fed00de5f296e9417b7c1bec448779dcb3fd80383ff9e799a63efb457af6d
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	6	\\x3159f96858b6b34f52e4555a8242ba25115b821679d6a8e3987d86997670f871d6644304bc749febc3281de7b54a95dc0c03a1073e4104efc7a15b3f29f8f109	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x797a46a4fe93e47ee944beada8f173c2ed58d80e2cac952cdc12ca83e6ac50447086696211724bdab3377cf4104da58718975793635b966a8a15b0661932aabc04734e4e59033e7b560845c057826ad678d161f5c6e7e94c68660fba5624aefebe2b36b6ea14aee63bedf2732b37893cac919cebb33671e0922efe4009b047cb	\\x8b7da642569ac0b015a27d559135fac87a659734f672bf1fe235bb6f907ca974f87926869f7e0a9cd134ca30083ee2b3d9921db0fa008cf84d98648d5d8686a2	\\x94db19250793308f91a827c0763e8a92e631ef8c2b01f58dcf5bb2315fd18f2574dd322c6685c38b7b51034b4796b7ddd5668848148514b6096bb2a8aaea97ed7ceb14535c2792d3207350f655e308e53d6d76528ab4f2c0705b9c4d366ffb6cb52f50ecb8f0d1b9545e3739e6f00b8f0860a194e82bb24897de58c818a55581
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	7	\\x90f4d1a50347c7fc626ff10314ba7f7e5f271b2259f0c46a813beaca5f13d55879376690b6594015f3779f638d61cdcfa0074ac96512749f68f8a5483b9a370f	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x2627860bcd8aa1876fb58974911bd00e2a772bd59e58648a6e6f59dfc63c250352de57f5365d0964f54a45fa3df05797c3ab8399d5c6840e3115023fb539bf3981a622c9bfc746cfad09ba04df0595ec19d725aa5ebdb630ad3866ff219ffb864041cc825053cce35c1956ef6d007d4f6c88152bddb92f27d232b7d30c6ee599	\\xefd62a95e9dd9a87bbb91ec0e31c16d99dcb8727ce48b376a40fab55de770afa101646e3d92047a9fe7a178bd3fc054f21fa7fc9095280f169b8883db469b37b	\\x04eb8e5107e9dfb4fb3bfce72cb661f7e8f829b4ae29795c97d687cee1a0e78a2e477d20219c1435b3e88d10a0c156201347cc94a449727f1dba61fa2b18ee56a9f70834ae59f8ef548215da2148c996a52df97cee2abb2775eb3af543cd89907eaae62ec8a613630f64e2feb58d1e88380fd9055ea1a5544ef767a6c2e30db7
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	8	\\xfa15eae777dd0835071c078ec8bb4d54e92804a5ed6d093c59f20e9fea2dfa9ed63211e67f1881f929b95db20501a9a4a4617d308e1d4b0a75785fd2dbd6dd0c	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x80f5258126ddd0110222e64ad573e391874e0f48547fb2070d04de442469335894def4b16d7119d1f5024966a59602c78ccee027077f74847a9c682759b3b3829d071bd3070f7978dec01adba16729ae94e7c91ca9534825bbe8393cd940753ed63d1f42c725736fcfbfcfc6bf52f56d2d05cb7dab205b3e08ee86a401874ea8	\\xd12d4c83c8b2b4f55d4237ee8a5f9cefacbced6c310cc4bfd7eec96b461ea267e1a2f5e64e5ae19f9278a27934a46948b2a8fe7e83ef225c913ff7477b22c7b6	\\x266dfe088383c3bc9c516b9c7397bbf63b9011d389d2c31ea0382a3b86b4c3bd2d3a404ff93cc7a92a4e4647b35b047db7c53aa84d4728149e57c8bbb5596c981de37feb8e8867f92c8c3323a7d38674939791b36fe147273b696c129893d22e1d9fa0cb378c50deb9ce16cc5ed5d93c050f6f84f1bd57b1f7e9b315e0a59fe5
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	9	\\x2d34c1bc0e9ce14972ce042901ef87e986982cf1b0f43ae530049efd8cc8f3168f489ec5259eb8a0b9dbe8a72a1f35fd3d397dcb2043794a2852690a8bd75a08	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xe2fca2ba5bd3f3831512cfd9d92652b8f41f65ec29d0752988fe89838738be5ae4831b6e08f401fed75461bd7aa1a3d0761d2593915eb4b3105064d5738448f7192ff334982877ed41a020105fbbcc1d8f0e23ed473290a374dff26248d71d8f2f9bea37053e98f1d59d659c5e3ef488380e2e2a320a5dbd6a86d6f05db24a64	\\x93a97135f4ede902b239c0e3d1908e8fd347ac258a2f145fa3f97bf85582cda14ff7481d24ddae555f10aa5cec81ca09fca6a74abed75225420a130abc34a976	\\x27f7075663aeccf0f5b41a4637204aa80bef679d1263dbea0743f2fdce544695f251518bea7045a053d0df7dbd39ba5df234b1d06b9c5ccf37a6c2fb7353a78bede1fe6d6f3a43727f06873190a9e514ba4e6ce149d401d22aa0eb045edd7b9c6dbfd21ef6d362d07f574fb122a47df365d7f07af5eb9270916202521a4bb033
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	0	\\x331f590085e80205cbf3bdd4c5f2a430b8d98e0825cdfb9c8b4aa493a1be88c936547fe8bbc77c51470ba3cae190d0216f6694f921ca4bc559e6ff624b6d8607	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x265ad565a9c6d96e8fb9c314e3ea8f04e967ccb385d1de2d5d34d2bf95be580633bfbe11c2807b62892a59afaddbd25e59a4f2dc93a265e6d4e99264fafcb6fcd103d898be7248933e740c98a7e03f9ced6af2495375c768b465a8d8b494a64c1fb23a09b2578c3f9ec5c494866a7e92c8922cff72ed49d9687ebd07ab7fb6c6	\\x4140d5f10a7435194e79b9a1221a506a8dad485e4812faf874fba8e6eaa2bed3ef957386dc263a51d263e9381875583eb329bd78c94c3be237bc0124cc708b56	\\x3748bc1a943b54d17e2a08374a0283518d378271ba86830aa21e32d3ba64c0f32690335c56b174f0427a15c1ee1c59b7e71caa49e3c7e3a6416512b1a58c8d990c796c5d8770653b621adc08cee3af0e9e71faf5292a38ce8d8323a529d168d91fc2c23bfeb62690bb6477bc283afd9608bdbcef27557585be753ce4859a38d5
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	1	\\xee8c50261afb5ae9c77658410a1906f615cda9db4a8126a476d991dd208abad8c215bcb39dd097c1237ef3381894a788a417082f62268401a013c043ae0eef06	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x81fbfc1b464e82aaabd23829a9eb9159c8e469c778dbe7f200baebd9c069028f60f821b64b3edd18a0c55d2d10cb7eaefd7b1461defc2c9760782ece327de8cffabfdf0eddacc6fad1f9333cfc21c5ec5adec5e8ff8ea34de85f356581ce4d1f9e71312205d6714b11e6b8336c5ea55ef62ae7ad909b1117f35cd2615f2476a1	\\xd08461428d7fefadefadbf55839a0951c83d0b67d94bc7eb52fde678477a9f8346352884764caaec02495a09929878ed7dfe9814b6dee14964850b48817193cb	\\x660eb1842e363091a3a6d0e18947adef7ffde57e5cca51c4b6c73aff8d904c3284490b5ccaa21138a96e1730ba7b2e91f96c28c509f7d2b3e1ad537b04361d4abf356d0eae065636d7a4e3ee99bb4d50d196c53136b31888733068896f6ac9d870a60bc680b4dc7b5c44010a5d14ef81ade03ad9bbd27fc64fc35484450a8e56
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	2	\\x23e2d64250c39b7d15ec43a630b24ecdd87e7451a536780de080b55136ee941637f3fc2dc3f14d209874ed8f2f718a1c253acc06b6023c4ca75aa4aaa583e908	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\xa0418067746cf01e31fd2f94b1ef4f022a2c77185ae705c19a92d6a55101129eec91d7c5017ce32dafb705b276a278bcfe9eb9b86b2064a098747b8c76162881bc9aea3a9a1ee947d61c4b27c6f8cf3d0c0fbce08f5c43b20143e09c849a211d3aa208c90d28ca3680faa09a2b16225b4a1196104241323dcccb5739c4cfa4d2	\\xc3f7969121ba2d40bb342b3f01645808794e7954de7e97eb0044ab217acd9394f212eb09823f46b208bc26133e22741733241078403251d8aa68374d6b7a0944	\\x8a8d95f2e890579bb42778cea8a361f9c29e6775567f3199f05c9dfe3435320cc199182a3fbd561dd310fd1eee11a447176f3829f0d02397a2decdffdf0e6c10388b54a6a26fcab4cb208ae23f6e7bb118563200ab6bdb3c01db40e0abd0623065749fe5a2e059aa1a4641fe4288f8ee4dd85e702ce9618e9d82f136ed76d454
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	3	\\x18e7a1a6fef9fe2700788c4bfedd2061c8c0b143c2f129547a79c5a89e744959ad614fc808f0b07318ac41d86becd1901df5baf26049f54f77be884f243abf04	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x3e4a68566b88176f2e70bdeec31ae372baf3993fdead719118cdc0b44286813fd51dfa79ae8d35c85e50aa50ddda45cd3b85bbf7a85d7abdf8ef11d762b95fa9e9847e7a22b75e9e3a5c8f7076b0c4831a315958e3fc6fba23704ba1b04abbaf25f9f10429860e2ad33232fa3f7bfcc085e91e027dedc0a5f3583bc1658354b4	\\x0b6cabead3d4e375486b7c2ed4f34b2f7829d60fb1383c073f818d17acbc9dd9a90472ac61276e1e287fe1c136ee6e689d9ef6f344078fc67cb72827cc5a68dd	\\x1af5b12893ff982b59b304659f456dec137ef9f5d833a931ac05c427b698e308ed0295f5b5f0a833101ac36818196e4bd7adc3111b57e25324f9377b9de3b2ec68cde2d383d29d405d8d7d1cb0fb7456b9d6dfecbcdd492a7de7566901f4814d6f13dbde39b801f9506d48f926ba143992dce6cb3c31fcc9a94e014e5a79af3b
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	4	\\x276da60c4fa81a396e6d66d6c68316bbeb41d763332de22351b1fc2742b32a18ec23756f0d983876543e41e29111df1532c58089bfeab6278c1ae9264ac6130a	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x26f849175d2808b04860af658ddb8982b2b29c342660ae9b0361cc653b35cb9eadbc3e2551d25d274d11687ebce24a3b89f50e59a17b9ebfc555cb8a2b11e21e5ef0f39341f41a226d7fc72f140f714e77088c7133b018c0be82718c6a618d8617aaa08bec34d5ca71b63f851242b27388731603f3daef38a49f639b8c633514	\\xe024dff00053d7b1c9534c85e55a403fc80646bf4d0d0b511aab412d0fdb4b654478aa6a3700e97054ffd6fdf478abe7e6cc535f7f81591daf553447a430b390	\\x7d38173ea573e2a34f2706c44021f1e4d7498d49b71ee9c6e5a3fda87f8c1ec36c2a274ce7b07a917b83e287041450487d4b51de4c55d527f300ff4def4b274263010ad4a841ae1718da3bd8645f2b22845b8336003586ebbd77786d835b2c29deaca22b5c483be7928a4c4a952568e2bdec2fe542ee2a9d1fda43f73b9b42af
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	5	\\x300250d088f07ff7a34a46b23c682ab9c1e8d8909b7a40b8d80cccc560557c78aa652b0be6e3f4bc3d578d5ee0a7dae36a05549d906a4d035dcddaf9e897ab06	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x2fa7b1a8da40bb662f259a18db105f02814e100ffdcfd6c24c88f78baf9b2c98ac214d923e43eb5a2a18002b3ede79cd310bf91a00e932e460d79678ed7287c5c1997b4234b95cedd6da2c2862854d06352eebad29b0add675e57fc8ddc13a9d2d69a29d5904a41e91742a80784a5d367c9162d2ae6c28eb01631326819f5e40	\\xaabd72262add2e64f930b88cdc6eef690d5a8661ac8b8055edc01eff33affc86c37f41f2ffc20462b74d72a9a40c25766c4e924f5c5ecc6ca8bd5432d60e23b0	\\x408a6ad04a837d565425b278eb84052075eda1b387e67f6b1aa3e53930372021bcb14acfefdf40226e0f2e41e3e4a51da0fb7b52b043008a5c0a512cfa355c23abf0b3bec62124a538de5f1e13d05c0aaeb766f6298c82ed82d629db0a4cf9a854b49c30267b5a4c6df86af993f76936e19850f6dc6c2f92e4866dfa70bdf220
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	6	\\xc5381baaf4e015949a8e683842203f0cc1dd461d08eadb99d764c9b63a0f0fc7c7c4fd175489801f1ab34f2eaa343338286dba6bd409a1b69e6868be28591301	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x24ee8383616e44a8fddb0c1c8366f8ec72740ad0c32b34f897d555ee5de94d2661fae0713077cdc0d8562f68530d26a3c58d81965be84dc998fb3e802d82605b2009bfc5b75d7eca1e1d62d646609bdc7e3c63e60f01eb470daeb16b54d9faf93d4895c42b464419d66287d325280ddf2d167a13b35180b05c8ac12b89e741a5	\\x2594fb602b6aefb1addd8e2d5dc6bb9358ba8d8251deb05523d3d043abe11f27c899c555649eb54c4d82cdf3e5608297dbd13a223dcb0c3f69fc7b546669ad96	\\x3888499a2494b43a89ffcafc30d963f0a1ac646e724fdda1f358f3d1a67490d71eab5f6182562937100533a2ac8ff85708c9f99f6bf3649f0a56364da855fce4a4feb2b45dbdad42bea1cf3244b07dc5ae23cf8d64f6b1df4420552c98eaf5638563055c8a6be285b306d40ddd0f319400831758b23dba8034e654edf7d726c5
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	7	\\xc9e074ebdb28a005045490377dc504753c914cc5ce1a6adba92711bd0b0f8eaccf50d04947676cc7a79455bacd0e9dc2d59e9971f9b6c1d8a9b0d9c23e47bb0d	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x6e151a966a106d580402d395812820a4f4b5c416e9226aaf8a1b0d37af13bdce1f6b7e7cc0bc4565c541a098473b96a03d5ca4da96e39489f3a65a38b747c5ae3b6c824ebaf969fd4cd7443cc13e4dde7580ff78e86be5fc08852ac3ee72d74e9e4c79268922a409c440c62b838a9a2bf72dbc5c42605d2791d4c42be4d08db7	\\x0655e36a748389f5c802fca050618563e4cd6eed4e0d92e9395d12769a27414b14d971315467f93d160e0c8ef013f6e2e821e04938913d8c798e94670dc9b8a9	\\xe3bfdad80f86d36c0d201bf09f645a6131dc3a8a762dc1d7ae138a89f91541ec30930a3eaf33cee69c9fffd821b071c7f6aa6ef380eb35a0680cd261ad95f4bfe1defc6f0981a1f629f73181cc3eb1fa2b2393f142e813870558b4bc41d4e68a610d32708789275818f651d7f98ff92959a87afc87a1216da4905943d45e0db1
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	8	\\xff27530f480504e445211352f5323da91eb594486b84c42e8e1aa72f87c3178d3fa2ec2d3529d9244afc62cbf5d807132845eb5edf7b6b3d5d1e2696deac9602	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x6e223eec8a57616e200b3510749e6f12b002517b6f6c06228f4713602c4a3490419bad09a37f00bb13e02fcc12055539cfd91b8d6db2e23d4b6303f511551251b6d4f8a243f85af828d7ddd073b448625c419ef16830fd2d80c50d837b276e3cc9b246d28a0205a3387bc94cb26a94f866b953d32d18340231b0974d9f27679a	\\x595f3caf622fda8dcb2e25edcc109bff0fb6d95f6ca478c34b9663fc5ebc6e9ec0f721a10bac0a96c306c99798c5eba78ad078476a5a817fc7ec852c5f99a322	\\xb2301d1a9ac2fc8b7eebf1b1649fd10100706f8395142c86a1a6f9365315fd30691d19a8a08c75a89ae7e5a70744e7e01bfbe6487e3a1b6e863426033002564ab19d3f431a03f675805afd2153e7b38b8d5ba631930c5243992ae99da3c2cb5459782d943ecaaf903110a4f1cc18b560d4db4ad74189a65d6a09d5b119b13eed
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	9	\\x5fabadfebf5ec01c51b04096137d871ece7f88125dcb97e5f58ce7da59b6ac9dec37afa50883f93682e63c18277b6f655c1ba0bc257e26ca4f237786f304a008	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x546b9d4db7f8c7081e876de0a134649ad39fa6310680708ec2fc9166ca3c7412f49ea6024e66996fa60419a3610462368639ac04d85ddb9fdb867d5455277a85e923231ed92e6430c8eb7052add2336fbe5f1749a5cbecb54474a28254669b5a11c0e55cb1a07192114c69d5be966746bacecc1ced556c383039356afee63f15	\\xd6b9c4ba7cb4a2dc19c6525403161190d30307dca08fbf936140657f1572f4389049473c7cb86f742035d39c2ebae37387aec667878a1525480a789216f2b378	\\x29d4ca70b1ca7d8706a62535ccee56f081dc62a666bea7b0fb0102790b9c9ef496a3f1a31130e2833641b00cf07dfc86af24efaabe8993af54beb2e78f659b1eee57fc4d9761763a2ff1c3cbd7a593905eca452d0f0b51d104d9bdadf7a68202d928f953712f0166b09f848228015567da8b085fceaaa8ba453afb3638526d30
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	0	\\x00c5f1190d65218c011ae1891d89f875c26174ced09204d1a29c7b917f5d61f20a7dce427de85f1eae76f100b0f883d1cdf36f9dbabcdc570cc50e3306865703	\\xa3e728aaf177360a81dac474f1e86aa3b90c0a2c430c433f42e33f9503f0575c2ff9d6cca5dc61c4740d03f1bc5bfe8d2f0f5f4cf2aae2968f0211ae83ffcd58	\\x547925bc05e8f1259e134ae01959e07ae85286cda8057cc8ddf05d6dd35322811d832d717e817aee1b5030af922b0b4be6bb51c8131067da079a595214b9e017fa2b0026760791502a0280be9d721a9533c798dff7121cb508d670f25004f5a0cb4854a9a9cdec06e972faba0f5850749e0e59bfc218e1db8e45ce97ba505b0c	\\xb943f77e3e7f8ea77debd95bf00306f850a54c086e948b71540fed4b731148d57f4f895e3e78e1dd49a9dffb7ba7ab7bc40d4e5d7b249af60649b7f949697f18	\\x033ce59024ce29a04b14e1cb57be43a0eebe29a9566cca4455cebc618c777ac9f958e54821d1b20371085baba5f8559629f96b128ba955e597482802479686ab2f704b7ff7a5643d55c63455e971997c6efc7818415188f534c605da594a3fb92b5efbb83438e97dec8a5042e2c25e4934c5100b240137967294f80d3907b198
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	1	\\x7102592bc8f0f9f8506f1b6378bc3a74387bee874cb93f6ec096cee58104d31e60a8d8c223ef2137eeac39551a93cc082de56f19146e2edf1e1fed7abc68fa09	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x40b2a5f292d46ed3777b03e525658dd4cf9fa4207ba550f6f6c335c6e98fac620afb2602c447d75ef47d3c19731cc0b08a970c6c9881ec48f93e88adf6866a78f14b55f5f41d5ef80c764e3b9afee1c020be9e5bb09921bf6aef6f983ff24f788db216bc3ec5eac749bdc2843b66d74bfe5a5b0cd7ffe3eb2892daa440b03612	\\x61772fe4215661c3632ec72e6c24d8cc39ca1d2664e797ee3bcf54e44549c5ba5ecc54c0c2e63d951d920e3b384ea8f78e543aab1b4ddb2254c30f58013d22cb	\\x62b1764960cd7561be46e1775c8b48619c950aab647534a890df4af550b489c4c96a055067b86d85f22db3adb14a702b96e262f890abc32ce8b08f33fdeb2c3e97759302da0ef5bbd53325a0fe938d4a92dcbb78dbc314ac14713bbdd9618d072aa6fd506e411d89314cddf804cba54cbbec78bc4da3176e8bfaf32f33d30196
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	2	\\x7dd3ada4eaa4a59fea4b293de382e6e1f00926e0117a45ea8d11a3adedcc8ee950f621cd218e7b4af7adcec1bdcfb64a662de95e0abd40b87afb7f9a46d50402	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x133f8534162ac5ede9d5e0beab5632b3034bcdeeb87db0b40795351470c95257faa8215482e519ddd9052df55eddd0373c29364e5a76d5a9cb8561d01403094aefcff72771f31238592c4ba4d3b4077b43e330ef75b34ef9968bf67bb8e3d6a31ac4b1fa021738aa9adb82a0a0191e0a44ad8ae27f9fddfd7b6e02babad78b7d	\\xdd7fdeff46b4a55939fe13ce820b8cf95f0c191e3139bddc0884820095a8d016bcc37dd9106b8e41d6b0cb5e20129179649a55e5f5c89c8b7b12d6e2b8b1afee	\\x5832771da4beef84100b6978496ac5e3fe3cbd9032ffb6a8703331cc6b1571fd24e91f190e2dbdeac36c40b6e71405dfe3a47760707b3b9d663d341a92f542de904dbaa311f0f2418d92b692e618511ae9acfbe52d6f875ca682814e3306e8e7b8e0089d8c127e55808624f9f76ef9f7e85f8d2950833c513b66741fab090095
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	3	\\xf5163f626a02e53e530d50b943ce6589ea2c1aa6560d01c89b0e3a984e8c04ac4e836cbdc0fc921bc9ec242a16b1faed92bcf6417628cdb1c7d4111e2f280505	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x27b8349db0059e9a1d3ea979d70a702ed7efb0201c14b525ad4bb8ffe0e1a14f8a959c51bb50cdbe4d6cc2c1ced818407ba00ea0cde96c0de48c4ca0e3f6fef24b3cb3bcf95675b4c9e1eacf7bde12e605cc89dfdffc0b271d7d19d9aed3895e8fabc21d64800610e195fd66e8a9620ad343df766e8db75978de70c5ba15b01e	\\x904d7dfdccc1cf89f34ebcc8491e360f140707291b15dedb990af444436c01b99897a4932f6a451cbd32b2d0095cc62a2538149a081eca728748f4e7385203e7	\\x0a35aa15bf2bce736179fcb38540ce76cf36758c864d3c93028ab9622f7ddec053aa15d7e441957c8c637a40f40d8933a117b514fa00104827fd40df90fb39c41de2adbdc7777e8416fabc5c21dcb23ecaeea03d0adb6587b68c862ba97a8bd5cf5c5434a2a5825cfd0a6694a22850d04ed520d305c5d12d9388ebbad788d11e
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	4	\\x9c17dbfae569c99ecf5ff4f262290b1678394e14d539a8a04d1495ac78cc616e4006bd395b987606c99ffcef40007e5bd00edbe734c57fa65e4a6ebfb922d303	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x4884e7d78769de2aeb6c9520a94bfe3d922d76bf2bffcd22e9ba2a75a2ebdee2f17f62816b616320a1fd0a9f7521eec6863f7729a17078ccda6c0874e9275dcfedfa786be48aa0febedbe5605117ebb7d8b9759010190733bb0c75d7fe9c701992a9515a94bec6ae496282928be7f39b99ef34047e0d2f059278184e9614eef0	\\x689305f22cfc508814e1843664c0b53c5e795f3b4d85e00fdc307daef14344363c61254a992799c7e2a2eda5eb09b06ee2b610b5bc445504d63f3744ee7f59d4	\\x9f2a05212b946bf7ccfbc75d27ff5d891a2b9999cf8d51b64fcb34a49830cb5681a4e795281cc6d0f3d2b623139aa32a4814505f92aeb2e1e039a10d4a25a6b3bb8eb108501134fa7f59cba8c1006e9fff2908f21526efd11e79f12abb24fe91cdf047ae9021ba38f258a853a3347cf9ebebc8a8439cf9b4fb2bdb87459af528
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	5	\\x692b094b285e1abe351e6c6b3cb5e2ce82b1b90ca5ef3fc384057fe51a5a678c7e56b3ebd2bf8e020dfd0c9e7722a5b6860ac8335adea505a5bf0b8b6356020e	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x17018ca1034c5266ca77f481c92c45866489e9d7ee60ce77ecc97972b4c2924ae65b3ec3b75537012a3ff5f737f03a280839066cefedc0eb2ebfa7558ead91dbc98c5489ec8f538fd0129adff99c4d85b1c7a318c1bbf7660c0c18cfffa2ce132f8f2801ffa0f3cf1c229b7321ec2da68dac13aadffe4a69fc14e21bcb87dcaf	\\xb5d26394af379886dd3f218b422d2f61efac7e70e0322a9bcf6ed76becb2b8328c5b91594d5312c09a6f4a34484cc61ea2f28851a5d98b3dd6381339dd76600f	\\x0a77da8ba9091b840c66f5bba96ac740b46fdc23627a64f19f115e8f5562b317fd5f6a36bfda6782bd746f300b642462051fc67059423d0613283b04ad957ebdd89e59b16b8b754e15c0640e184e6f69d8e328a2ec45b9b834b5b9c0ef2ed8508c7f5e11a5e21051954c7af98ac1added51eca06f20aeb8e337d2f612327ac47
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	6	\\x1e1af56b0512f269ac4b914dbb5676517297e76e71e1329e0a3637e4189dddeeb81490d9dddab78fc2fa5d1e98600a8f403f07c5c56a0db56620ce7c34cd9100	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x35132ba5f0af2156047de585ec571ce73bae4d45413469f9b6e474881ecc7259a5cfea7acd42d44322498d3026fd8f339cee14a042ccf27f2c4a0bba8277506366929c2d4f5175120da59878c03bc8cc9ddc38ef8f76842dd9683cf0edd292ece878db23724ef55c4a12dd2ee81193c349fca88a1b24eae178c5d1c9d0dce35f	\\x2c862f37e6fd14a3f746434512a2a57c046bb2a93ea5144923825e9c2a890937ca6513d0cfc1ff0de4f2b1ad3b10ed29e0ab971fbbce0fa9d1df66ee53f4997d	\\x5d50cdd15d3d0337c5a010d3394d5c5eb0028b9fc796d1c784d588341e01f667f37b165664e7460c51a552ed94e66ef497d6d3982f8506a1933a504859be0e1e658fc6019b47bcae48da1827ed74b411eec725ae1f000b2ae4573d843af15150da0fbebdf3c282ceae2686da9b04c493d9d89ef0d810b7b3c8c50518885501af
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	7	\\x615bde7c28a08bee4c56ec9af95cf279d0bbcef7451a1b81dde1be826fe658614a9d7d72353e984add006bfdcca82819ce81da3f882a31314e6b07dbe553db0e	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x9be6c0034ee852b6010e58116c43bf6fc4e17ad937a306b000467c206cb3d767b0225e5bf4e9434a9a2815a2a531110e3f4295f41d3f22668f989c2d8fa248546562e5d2c01fe36a4d4b42152b8ac50ded0cbd579fdd88026ac21065859760af665a151abc50fc29674c425211c46af896b7995239aaf2dbca62df68676ba314	\\xe6bbab448d474bb486b91d5a82c7b0c6c7090d5c735367802bd068d0b8a7097fca933552fbb9cdb80241495a71cf9dc52829565f9b155730834614b16e7771e4	\\x6fa9718d753efd5e35fe74c46bde181cb7204e4f38d13b0cefca0af6ab05d3c976bd98d5b2ae6740c72abbcbfc1ed43c65c6fa4affb7b5ad3038dcb7b9ebac8ddcde8f1f226969236615355d6e7a96d2e6c446c8792b0bc9da4fde858c6bb7ba9faaf31e7a4be6f81b99235edffab1ca9773a2a4d8b84cf80eb7953b29a0d511
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	0	\\xd09f142735deeaddf836e0dbb00965c8c63f0c82b2bd1b7a5875e6093a6633a842e519f43ffcf0e8de1d286b9f80a75b36f7173ed3a0e1625944b2ae8f888402	\\xc7c81552056d3c3df38d7d9655b32ec930080a5fbcd8a72833d0cdb41ebed8fb8d8337660d8db6fabd1d9fae828702e356787b86de7aa222432556d07acdaa15	\\x6446a01ebaa97d0991f9f4381b507c75d6fdfaac8c015f8129d4238744d77bdb73ac1041090c29cb99ecc3eecfffa7dbba6fab7030b1888aea7025d6ffcfcd333c5fde2518647175e28ffb3e7ffdf8a0e1e37172afdfc67ed09de35cad7c628463ef816baff677d4c61b899f72e7f48ce09a650f32c90a20f65f690ba03bd139	\\x059580da8cf3a3c7530c242c7daf16c0ce7e21507d71f2ded3814502028ce00105e710cdc518bf484acb41829aaf47d8aa3dc445bbc726aacaddf2450c499898	\\x518741b306f4b0592881aab838ac6e10ed7013f241a76b641316796afa90abfad93ef8236d52c7762003bc9766386edc5d181b963640066648cdb744436584f6e9925284b94e2f1bc703c7e812e7b41f7bd426c5760982ebdbb445efdc818d11942be895ddc8115c37ff749936a2a761eb83c0ccb7ee9219c2330b50cd117b52
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	1	\\x84a073646a9d31ff87f68210d443af8b310b0e65c23015038f21dd994d96cdb0b3877ae1e5054ca441829a407e3d1612d1f1442c4f4d1853ddfe2ce7d47c5805	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x5bfe6d6c7a93b5fb6c303edcc0a573c8dce254b79909464ecbe1cef44abd9467f11341f0c0f07242224ca9edbd3afa7e58ddfb117664fdd48eead10d40b3047c458e36bbb51b66a77bc9c552c8eb8a6c3da8e9dd5093d9460409ddd4ad5f5cac9c02e47e04675d06a2a79244ffbf3fe381862c8e3bbc4f962dd19757e944b59c	\\x2a62cdc71e47d7b148d4a8aa985ebb04c920dffb56132179f2a0ba9e15715ba4f1d1596cca0f70d04107a3313abfb1e3ab7fa0d002aa3b7025e197bd1c64300e	\\x85dea1ba6db35a211d68139ef0b43d7fd4552f1eaef0f45a10c23deeadb1e4a65dedbe3b2d3ed18921fa804b4065cac6d6fd04481e44c678432ccd940e0190685fcc1460b184adc45e98bbfd7785a6ad2eb85f01082934565ed6eac195b34ede6fb2e4f034a84d6c98f632516781a10ce690a4160c791520aafd53966fca270f
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	2	\\x423e01ca11856dbe8d3eb6ab115f2e600a3d2072b1e6c8380c956444ae8b972450a8ec21a43968824fa47d99475a32218f5972a8d9fb1962aeda0176eab3f20f	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x26d7f8184154d70823322e13298d18b23dc5d80e1819e73225a29bd8d0d7c249a1ce72494bd0d644ebd5ba1cc3e692055199bd5865498d52cd7f04b91195e9613b85da8cf1b4e3417f7c54fa114da6dc1884ab6dc13c22e213c43a830e72e6a1d5631a9c612192a67d351e4470d31080377c77c7e77685a2b04bacdd92f520b8	\\xfeb01b70ee08200cb01ab0d94e70f47f9f55e958e51ba0fdc0c015551330fb0c8661d56e459035aedaaba57c34ed4613174fce328cddb9094a2c41883101888c	\\x9c521616ab9a715a55cc1245ddc669012ad8341fe0fe73c634b24d0d4638dd4d47bfc98e8e88a3d233ab0b68f15818f807879de3de6a76b74c2ad06d503fdfcf4a45c6ccb703e7b1678660bab2f4f2b39e7206661eb0cc1d0726f680064d9a351d9b9dce48c93e26dccd37b4c4a0f957a8a115e05416ee0928ff46dc83929f5f
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	3	\\xabac3b908902424b188072b2d8001e1b11500dd4fd52057d91c8e86ecd9cafa1608048f8af7285ad8c4979f3a276a86ea358a684868f02a16e39ce3568cfe405	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x49fc36922b05db9ecd9c0d998aeac7cb35b51fffcab49f91dcd63957e0efad364b96dc123a433130c1bbfe37ad83ec115558a5640d4b78f4852934409c3ee3918752e0d23559c40f288b3fbee4ee94da18d8d3b1fc3140fb6c666b8a00730209de458c7c9d794f55573e410d40ac596b4e165b9c18d301c18a092a0528c9f265	\\x965b1939b61684d86cd7c153d8c7ff6026a3f813df80dbd102199277517a4c616d0f11795af2a9c91d8b59cc4f6eab6e4a5f4a687419d731cbacc9b6c77e34f6	\\x1f79282d7bd8638a45631ba9313d71849129097210c1d6e3b2a2846ef65e91d2f3055195b601d0b9d4d64200298694ab80f9065ce81fa43eaf417aaeb69a3b94708df8e6930da6d252440a1df8f9b2b0ebbcff39330622eae17c4411bc89c4cef7cd69ae5214aaf56549d866819fe5824d52e983c91f24c687b47eb2e8e73fef
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	4	\\xba037b3123acb25e6121145fe545748e90dd9352a4867c603ad4e7ff83bd8df84bf655bd326042fc8ca59d8b92b6bad46a06a7147fe2dd37f733799e1c1f5800	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x8af9502c8448d3228201db862ea46c5238688c146c1bc0e240682c2fb6cb7dd7e2d66b32c68a6231433fafff6c0ee2cd069907b0c17c4b40867e7f995350bfc97930219e9693b5bee2e7d2f05e07bd562e3d4a98680e96ca564599cafb55f6f8b94235ff1a1e595fd58adcb71fb138ce43042c850c4ebf34f35f9e847ea2cc4d	\\x5758a8dcd0951a7e60911c5f8fdd2fe88b377941d2adc91c0abee10f45e025d71193d6155af3beb5d46d064f58b8be7be7484ce055dfbb51eb746d7c1657bbdf	\\x2b2ac75e1deb507008a68c99e18795d1ffdec104d2956cfecefbabf2b6312fb0d622c4f2105b2856eed6e7f5ea48c1ecab28173ea743c29623d89d9d59f473cfbe94c2fb899aa569356fb2c8254ad15b6478f8e4df2f7b2435140a50f138500b27b9ba1c5a99ee518ac96e2c2b0ec1ff2fba80786b33642a37611c5cd5cc8711
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	5	\\xb41b1dc7c6d8cf159c67580b8bcb932d8745c12f1f5d6926fb009d6af20f66dda52a1a019cb75fc2de4ad643300d03883ac3ebfbf109f11c4d32dcfa198cf401	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x8c70f841b39166096a4d865d27dee66f71280547653160b884d4d00a8ceaa22f5c5396ff7cf45c6a850e47ef9c29bce1d5a2858d14119f37d9fec0f06db87d5f70158c2de2d4dda9cc2925db287355c677df2bc42af313def01b0e6e6f55c431a3c7fd33f76d64f48401d0deb6a88ed35c5795d7273145ef8f46f39dfb99743c	\\x704fc11c4e249f538edc9e9db45dfaaab705a39f886d86a09753ffe9d33fab38d710c3db86a0bcdecdda7b67dec7d0aae8b8cb001d600be5d3bc50b31299f772	\\x566d20bcee9b25d95328117bae227458d9a426ef2b2b9e7da53d15ddb8ba5d97b2a7044a25f935befa5dd6927c4374a77a4674e38ed015731cd07a458fbda31fd7bfb32eaee24be458cce341bea3966e30188a4af01c3009af89a04864eca3191e1d4f83eb8714d9b92432581a35581a56b1e7e589ac5aabb020396286605951
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	6	\\x4c25a887d11990e40edade45f9b7be696e04505044ed90bf73094cf55e3f76c62936d57ff3a67545a3735977a4549cb3e78ee13ed5d1e6be95f20036f2c0d209	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x5bacaf75470cebb963fb571d6740dac3cea33d92d78a681a8d4b299da2bb6eb37477b58a347fca84246279c3052f7a75de59b327dcd37ef7ecb110236aba44d2fd7ba54cce1237d7924a0f432b135a765819f479bfe26de4113883e424f2d70b5bca8391d76341c0d24360c993960d0c0ffe425f0c016c99f955c2257c5045bd	\\x2ccac3f2b130e6079674480cc52f9c6a9de3c71cdd77b93e402c67100dc1a1f912c52ac0b71dc1763ef6a73da6766875eab4d4eb50ab76eb228a8ba2463b2dc8	\\xa9807d0250ad009dafd72ad62134b8e7727b435f5734a00de853b9c602ea3cc4401a75152ec734a8c5aa78cf0768b56d02114ebd1e1daeeea6745feee60c0ed3374aa1ff08d18a5ea6f37257ea0da633dc0b5b258d4a1f7306e2c8e73275c8e5b8b0c1f7437e918b75083b7061e749952a5c83f300c54d7e881a925da7d4a073
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	7	\\xbe6df2fc6c00c4ad8db550c8338bde70a9f62e20784e6048f4150cff6b120d944b5f52434e479b9226e59e2dd31d6e9260cf89f1771eaa3358f063bc9450e30d	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x15369a855ad35509ad693e6b169fcbef048233b05930d23bdc8f01f8f02eba3c3905beccfa4617dfcbfd971a46bb0ce4db2333ec39a76ba5675fdff6dc6f26ae25b17ad944e951a83729d66736a08c1ba50782961bc60a6aab4baef9d18d77bf7b4420f13c1387cd9a6f3b7bc14e0fdbc163bb515fe6b2ee6e9d56d978bfca6a	\\xb007e1c7e97558ddc8a9589731b25412156764442bde6da5dc93f508f9433bcc27265953c68614ba66ac9c04cb87b27325d88ebd154c046b0cc3ce622aeca4ab	\\x887b89d0479b991cb2992e490ddec3b14244aab5bdf732cb663b32b3c7cd71366c7489b20483ce35c3b68f1d77bd970418096db542402da0d85eef2300e140b179e3153c17d1197a4a417f21496c9021d3be6566a1084f7d4a1632c3fc300d8eb9a001ece821d00b79c5f5134dc986e25f9901b79c3fa5b0e4497c068a58c505
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	8	\\x447a0aebe4726d9c2bb8a8fd47d382612ac76f4338fbb76482f9b37e454a58890015b15f232435472b8c6d4e44bef695a1b6ca042f6775e2af6aaa63d6eb150e	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x10316a3de0ec7b3c94589cf9485e6f5b3c0cdb8a58b85d5f2e356f6c17cb3e9ea079e9961a4c1d9608a7427543ba3514f1d51922a36441cc6d279100be8834024e9c81b0c164ff14806c076f8f137477506c64805f9a3e7bc119340992122b037432b98beb71ae44cbbcc69b993b0b2863e372dbe029a2fd4768955f7fed5785	\\xa86c30ac15875b89d28edc7c191bb7c4805d4c0ecb9ee1abfe213c33136c8be6d79bf8aad0f61bbaa661bf87b5e4e8fea43d944c5d8afa39a956be1af152e5ff	\\x0b36f282983bcbf8ca926722217a7af971e2c4169a919c43eef1756960a098d6f0098156d61ba7f5ae15007498185d91fa76bbfdc8fce7afecc30f88457202cc4e2eec0a6a36d09e79db1133540b96eec97381f4e648a2143be34f7f01c53718e224522f23e68b012ec74fb98472ff250865dc22da8cdc371145f3f0897d9cc7
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	9	\\xae12a01c76119ce76700110e22a28f4994d3dc119ae7ce9ab6984234d5ec95d6ab15a4107a989338952d6949af4985865fa26b0d5ca7157f7e763fbf666bbf0f	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x7ef424e8ed49cd95a9177b23f221bf6310ec70d829c7c792b468e46cc15364490fdcd7e617ba23c92f5880d56601e439bf3a46d49d698af785d84920f9d84b4a14fe42a3b18666c8e9f7e98b793ce3d7c052b21e0deefb02c1079199dc30add630ad0fb8f5c74fd0bc438b626d3a4c0375a74e7e6eefe53593c5dd68160d0763	\\x4f02349bad2c0bf95b20343d60025bdf8d8e97b4540d0b248c668b515375b0171a709bc51f82e066d950ab600d0534db15d480b4d8f0dfea555b9cd51ad48a5f	\\x4d6f5d382284c1a842fc3a524588b81aa68fdec6806afe7bd32752cde9b817f078e7fcc3de3b8186e639371ff9e2a08439d18603fd2b1899f8bc87b56761f8a3f34f41e1beac09ff4e007ebb0dbb51556636e7be1acfcc9d84052c0c8b32d990e1b5dbdf152dd22e70ea539c8b51904997f04e8d69013e13241a522a5f1fd72b
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	10	\\x369e159b5f29200b397f678f91d9ed7714d02cd3754988abe8d0b30780599f48b9c0a8f112b76abf78a5acf6dd2a43a268ec4c6a90f4a729674a3c1c79fef707	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x160773fd2913185142ff78bc11acb955ab2fd1aec4ed126fc8a385881b71796bbf32cc9ecd566a264ca49f0c9ef5c3b6fd4561b25594c4c088c5dc0b66c71ab633203d637d9940ec39e150c18a814ca767dfd73679d83d843cfa80cfd054ce69adbad0e9a9816f5eb0be8a4e97437fbd2e05eb23e7bb3d9c70c1d589eccd31c8	\\x265c16b09e8c9f111b2d7304d90ae2cf5eee0edf90f2096faaba38af3a761b02716089b0d59315ef3ff8efba21830868da3dfc46b9404b6f48d4323195e425cc	\\x9747fbfc945beee30f72c9ec070b2ca9798ff19974467705cf8eda18ded56b20a56f5b20594134526659c0006a25f718a9644117464834bf62b70c8582a0d9003e600dff02fca979b50ae13cad965a652e2d3fb8b6b86e0f91bd55a6344f38d1ce9812778abf122823bb7052761508e12ef2c6ccb0f34301e6b2dc507cffe686
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	11	\\xcc2d4b5d53cb61b44ee667de5e8f7eda45b21b1e04de440df8965a2cad2e6231d337c94aa93335e5337797f368df60b19c3b367e0a5f9bfa2be0e35c9114d10c	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xb2aeb211851d89b2914df0fc03230a388dc545d403e8e7b09bc76609d62d3d77d5963612514559863338cae6bed8a04b1bf1d55250d839c7f535c437f21629f5891e258eb4ec3ba156c08ac9c6a84f5f49c576685d07458826491ce07e9a98ae2b3d9cb510fd68b265d6337f45f76f4687fe34bb0d0dd7aeb9f8413372a0f9c8	\\xd9887b09b0ce2007fcd5ee0adbc19bf84bd26956dcbf1d4b8b0a18692cb9cf24f72109b8ed49c761d873a79304f5c70b55286438b63f3cc971ab265d4805e6da	\\x5ce9ec914182f78c7f3e7acb47eba5777d802e2a3ea1a12083f92094524f6d109e74c08e892f548be0a18b2d4a914a1357ddef05c0838f6e68e9474159d54e59c2955a9c2f9d2f3ea848f16313c2ce792807cefe0c49a3ddfa29f0856c208b40734398d7ba50549eeb92613a37f9b95296488e829ebff41a9607746a5d987b5e
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	12	\\x814d082d9f1cfdd4b382bb0a9c24efd8994f3aca55c0f359334096f57ced47d59876419f0f840254569c607935ea849dbfcde741b40e04c490ddfdc760522001	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x5f98f0c3969f7ea1a99fdee2d17f898a93b44146c6a069552015e6f372e230f3dc68fb6b90aeb9113c407c544ee90b6f078543d59ac064424d0838fdc825199d918051c9bc9c4a18d3bf6f5c99e0fc0ebf1fee23da01ec8bb478f306a911e7937abbec8992e1755a0d27986bcaa8a9355ede825e7a65f4a9a2d21244c33ee422	\\xe694fe22b4b2770db917cba66c2624cafbe4cede2f40eaaf0842319697d6fbadbbd704964443e5224feae4fa61e6b3a23dd7fb3fbf95914bc85e44490f7c516e	\\x96214d66d7186e5e244294186882166e61598d3c465a195b8c9d0db8ff89cb3d2726c15c347b1e7752e6574125a5551f21abb600cd573896933061cc285aaffbf265f3410957e1b1696ec1665637df3080ac048e9639936e570e3816f83156cdc459a015bd7a1f3c6098f44646658af6c3ee25e3664719444956f583b1bd7d18
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xd45e40afc89e605ae427c98c2b8bc427442687e450d55cbe541230a934659d1d1609c60fcbcdb275c307a1fb2eef7e5c90a34edc71572bf231a768e38c90daee	\\x43f8caea6da2407604a3d02ee5bb2856ed4c5fdcbc70d376740d0fb8f2285c7c	\\x4a1a4753d6dd121ad4710da681398ead0e1488ca6f276ff5bb5cd6c4f9531bfcb1732d8a11c9b1b9bb41944d8413f987ba64b065f4b7881f0887842069df8e82
\\x8ebacc3aba4678baf6116108bf0a658430d39d68a9fbeeba49bc9f7dabb929fa130c0bef4e7eb43e53731fa08f72b9b07773b67ce1e614cc8b1bdf8ce386493b	\\x5d33a3f8ace59078892fbd8a6e67c02af67ab1986f0856062fe26627c4aedd4c	\\x6573ed2b5c5725f2fcc44f00f7ec3bcdbbdfff71e6b187f0a482297d6c7133ff35f845502b1eb290122855ecb5cc6c784751aa81ca1e0e5ea7f9187bf14eab1a
\\x7879e16a2e80bed957ad7719715c4444ad0dd557cad53326af74d98d4ec41a2645e1880d61c25d813d0732c6534aaf580fedf6ccbef493b4b4d489d0ffbe561b	\\xa777e79ba18e182b6321ecdb64d0e64dbca3b29a9224a644454b004102ee8f14	\\x93fb3b1c70483a1ff091bd9baa9bcf6541e2af8c202cfdbb11bfbb10b5675303980d3a91d31b329b3cca111b61fc193c3ed6e7b63f2a0a1538d5ef8340abb9e8
\\x157289134a5f765ff232c3c5fd258177c36bb74d7caa6bba653ca67421a37508ec1c9f6c5b710462b478fdd6ac18dc7922bd60ca707ff5d3f61c073518f6bb5a	\\x174250322f4b25ca4798ecc1abb5c0ec672ed4cf0fbe44dd3e396b95d14c0515	\\x63a7bc4debb586e14c9b809582bb01e0d7f7ae592fccac727d5df7b840f4ce409913d95ced4fd3196aa0a1753cb321784aef33021fbf0b0d9162db93676840c0
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x0c6fcacd80265d8f41787a16038fad4f47fc813e54b6eb7d0d0ecf18a8737efe	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xdf1d2a4454ab0e144231cc18d3beb2b871ee9e376c70366a99e524e25ae668a7bb467424f291908d86c0a7708a154f18007435bcf8f9aa88c6a2a47a4413fe0b	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	1	0	10000000
2	\\x191ff0bdb47189fb5c64678d4df5b11d21a27ec3458fbe5524ed34d80ccee0db	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x068d06ee1f63773f378f12eee41a7915317d07339e1b11cccc30c29c904beec49e9df09f79e6376bef786183d3b1fd23ae7716129d2716baec5fd945ba7f3b04	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	2	0	10000000
3	\\x3063307755df623a9188bffbb9e68b3d026b3cfac7acd87bdfa2027d17a08061	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xcc7aa79e2e9eeaf9ffc0215d3e3172452a9cb5ce33083bb1eaeeeb9624fc3b65a0278a2d74e81031c000d919964a874d45ea2b7904190c9366992ddcad1d1105	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	3	0	10000000
4	\\x4cccd36f630a8c9692093439a2d8a724dda990d9f6318952ec6c59da87b1d7c7	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x0cc36d51638502e5e94bb159e25ca7b82cd7340dbd9e842c349fd93e2e25a8f9111634c49dfd6e272c7763df22f13d528ab183a6c48e5e04fd7c5a70dd526606	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	4	0	10000000
5	\\x4f017b4502f3fc5e4ae50891b82e32be47a303b3bc2abf26ac68a0b3427b754f	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xe40cd6434bb6615a531e78ea1aba5c87fe5ef0bae42b91c4dc0a8378f2cddac1dc3fc7269f33da4081fa0a69376996a5fa2011bfb6ce7d988689f9b8d9ba7805	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	5	0	10000000
6	\\x8378674310b12c3516b5c45130b19fa69a72a654a25445b7472c6e692125870e	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x8a1216fa5c5b38444bf6746ad1bedb590f883259c4eb373759a13d0ebc9dc77ea0157a4e11f7da935dd1c23144301681c54220aaf7bd5788a31fe3d0c0dc5f0a	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	6	0	10000000
7	\\xa81d83dcd5d8aa4bfca3e06bb9a09174093b579f10cf80d092ed2bc029d8f53b	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x6319344c723be994ad154d048d99913e59f82f945efeb56725bfe50a3ef4fa9c863d65dc6d83d9f7cc53fa8585929c5c06960f2e1fd5360749f454317e8dc10a	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	7	0	10000000
8	\\xa895e862e248a6ed34fd97cf4d39e10efe034f93a753a2a3da305d1baff0787f	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x3968d6587aa1f5087490ac69df07841f4a27af14edf7e90afb1eb9ce7d181745c6648ac94a49d691ce12bb03385e7007e0d86ff7974619e2a240b82155049800	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	8	0	10000000
9	\\xbcfe55cbd95c24a22e42c4fd5e33d98edc81d9ab2ce2b9ea85c30aa35a29770a	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\x87e13f005ecbe4e4026305027a4b43f24ec6a3a24794da8b1c856dfa99b324fd54dc730a31f193b66ed985bd4e44d72052b6fa5422d18aea0ab6e03d2bde3001	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	9	0	10000000
10	\\xdb8dcd19230b426a9e045c2082cd7936f03f22dae0f699a0ef55d7092aeb9893	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xacffc9de31699692be0dbd331ffcc4216851c3dd4940b9cd2589a0c4326975e1e50c56898c599830e1ed8e2ced6b2d7a14bbeff21334c1dea40d46d79345900d	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	10	2	0
11	\\xe2a0a7ae5eec25810c50377ad371d290e5503e29c0c7d0fb45771b3c1e465f9b	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xe736714cc2016d603916de117005067df1e8dcced5fc4bcdea8473d404df68d84d1f4392bc9a4b29b65e1e3290e102d49dedaf21ec22fac24e8f67fec2aafe02	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	11	0	10000000
12	\\xea4de448a295ed7a4769343155c7154f2d8722231afa2b645100566bac77c869	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xd402127ca9a83c24a0b2319e0c5abfacfa24fa6d7ef4457573f44802be1952bf0eb6df55ce16291733eb8a81ed2c41bac66f1ad50cb088bab6e96b3d1943b901	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	12	0	10000000
13	\\xed10ed590665408bf491bf21cb31f03e704d636b9997e2d6e40ccb910b2c2f5c	\\x6ba22b991cd7ab8e9396b07afa1b41f02b8163b0b71e5eb26fe8db5403778d40	\\xc488533326cbb60025fadf593258e77bed54a8e0ab6a2df0a3bea821885516df35d0175108f2bc2f1d8b80b402a3354588bbd5c4e690e65c6de0f92d48067904	\\xd9614e1ffbf6e7019f6540308ac54d7dc74573868dd0abb3175e9f73d06de4ee26de5274951373cb0e27087048761555f417fb783d9955c72628d811ee084cd2	13	2	90000000
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	payto://x-taler-bank/localhost/testuser-5kbwcN4P	0	0	1580166018000000	1798498820000000
\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	payto://x-taler-bank/localhost/testuser-EZBaXuIu	0	1000000	1580166021000000	1798498823000000
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
1	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	2	10	0	payto://x-taler-bank/localhost/testuser-5kbwcN4P	account-1	1577746818000000
2	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	4	18	0	payto://x-taler-bank/localhost/testuser-EZBaXuIu	account-1	1577746821000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x51ea501403223111985f193462f2b9a40c92ea3ee81f6c89ce5851b9a8af0e154410dcf88154009436b5fa0f77bca0fd5bb3358ed10ec84c22598ba2de51c6ef	\\xfc9165705c124932a55a38f2b0063779773676f104bca21c31594e6b109b52e3cba1876a064d6007225f241a4fc27dcdd20ff7be405d39778cccd7dff08dc62d	\\xc58d0b1f06c3c154b297892a013b952cb1bee477b43e1edea75fd12572276fa890c8c3cbdf64eeb3ca9947ca31f9e97146b8ef131b80f110c0eb71e43bc4a359becbcfd301a7993898f3a0ea423ed3a1963af8682fc653e311726aa062e05e2bd8a07ee8507eca43bf98956164cf79f9ae42359ae9dd355b3d9c86f467fe2947	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\xaf8c091c10a0036c0f0bfad0ed0911faf2c93f286feaa233e5e42189b5016e6bfa3b932d70507ee530f0dfdd3120c484f9c5c722f671b9e7af3aa1277f603d00	1577746819000000	8	1000000
2	\\x1b9b7dcef17e57854d3347fc799523f86918fb6c2113dbaa875a30de906129289a7d779217b64831b151ac659a3006e0835af0f25f662db214b7e7ed374a57b8	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x8cdb87a169a54a729dca4f462e9f9b4d312b1538c105a7e138e166949f087af601b5c7fb662a32782bd042833a3bdfa7500ef523822a0edc77380cc256bae01c67a6f3b145fc1d414281884adc461c14ff6f22cd26166f6add756c993abd122b1f0cfe185374fff17fa90c35b982228b6effbbfafd2e47778d36f41f09188440	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x553b9be5177c9cc7d1038095ff356b70b88213b6f9eb2f076f5b7cc814223f04c7499877e057fa13d7e4bca9089d15e0df7f9c2bac1bfeba85cae58d9a96c409	1577746819000000	0	11000000
3	\\xd267be3b068598ec0e85bcc2637861ac3771a91a2b5a9712bad68bb52faefbf81fac946442e23bae3297f0b40e52dbb2f4485aac38688d66cbeff4153317b9e3	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x5b906bf8d9cb331ff947dd0facd58125dee990a8a784e6d27d91c6458ea57ddaadaef48bbaae9d573d26188c67c8115e5d580772802d4a518ff5d10ef5632142c86584b72e7cde83d0a54f74f973bcd3671073b1c67c2530fe3a5d1ad766d17da138ad16385a654af45e0f59034b9434534d4e780e6c96072670e2cdf66836cc	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x6f96706d5efe647498b3c90b0504eee10376fb00088c6d1ccda34ab7a8c2149dc47d961bb3ce8d1c0d3eeb7ceb2366d2c82f39cc2aa0ba09fc6eaae19e570805	1577746819000000	0	11000000
4	\\xb163e22735c94b87774fff5543752a3fe72f6636e3067b94f991de7c1bc739a600654c00914d91ee517f4ec6e1d4483273ab4b457cdea261024e2d22c030de58	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xbfc9ad1b42207f7c645b9999ac1ef84eab017c96ab459e1cea8492a1db098704e68ca913c4b3cbbe400195d786db62dbc10a3c883b0052e703851166dd7c76507d1ff16192e5cb1a360653c123611f5a530683dcf964e2a25f86587126ecc8d5dc161947bc755539ae86906acd05f755533bd25077915559c2b7bf83e8c3edc4	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x81b0e383d5766caa27a9d48887ff47e547c1d629f24b59b205daf56f8b39aa13986f01d1671d891b3b71052f1f0ae5df8647ee53ebefdca1097288cce6d4870e	1577746819000000	0	2000000
5	\\x34b41a0da3b83316932f1f948b26f77d3c36bffb527e1c58654c0c90cdaabc83ce1c381a4b938d3aad2df1bdbdfd3eda4b03687bfc79ed248067d6ef8968a99a	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x1e479d3e30c147a45c43e258fdb80a966bba5be7033c1e10dbb796561ce8ffcc761a6e7c1e8be4a63f64974a5b9f9f0d26d78d109cc811187012df583f52798f19219bd2d392837caed9b3b8ffaa8aa08c90ab627edb34fc03a4001804514900cf73551078224dd4c3d06b13d59048344f849164c12b0d240b19ae02d99cbb3c	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x8c0a4b45e213552607499153b555c384e42fa442d21b2ae78835f954f24cb6c016df94373e811847554b87b82dedd2738fd8ed0f51ece37b003a53d7ad8c5d0b	1577746819000000	0	2000000
6	\\x412851e93637fec5993352de225ee2d465aa810c9761bd4d14095aed3cc81fadae3bcd6e9f9e42cdf6bf7d28a176e312729898dbb8579bfe8cd47260ac15bb6b	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x8813e6e96491e1376fc513f1d8e7903b45a4b9c227c0c8e561b0b1a467978e3303e96bddc7b10c5168e73a2335fd082d015ca4b7a87086a1ae6fc1c953347516881b366810ecd1def0d4d4e96a65ec892e6aa33465bdb18d418b32300d37a4f72e995ede65f3714ecb63992c61ec4e90db7ecccc76ef415d9eafdab308243ae3	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\xf1037dbd42a36da75b9168e6e3a3d486a46324a82f7129257c47288365f99a545b5e8c6fea127fc2a5135ae06aaf592346867f2f345aa622da4539bc627d7c09	1577746819000000	0	11000000
7	\\xe4e9cc621d5bcf82691dcd217490f12e683734609c2ff5e694aa295c1396c0b639dfb624cecc19bc826a1c692ba5932ae0dac1806c9f43beef5b78a95233b207	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xd1b6beb87bb8fbaae1034beb50eb2e09a20716e85253a3a5514d3950deaaf0389acb652e875bd6115e7d372236bbde3844cbc1f25198ceba5aa170988740000f19f81b119f5a13a32d9ad191a78da81e8280ab791008e486fad37236a5d04d73d63e042e4852e2af257a73f5b4f9d94b211b01215e66a2259ee6e675f1db119f	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x3a16779f5b768b8458d44d517dc75ff7ac6114895502e42b3de7eab8177e265673ec5707fbc71f14b8ac12d1e5aaf27234a90f46cf0d6bcf4afba504f9fbf60b	1577746819000000	0	2000000
8	\\x42648c37d2949ecf0a329760e4ed16356b1ff164c4b2cbb1813777e17e306e0b25f644c345223fed5d27334d7d0743b50072cd898fa2dc3ea781b3e8b04044bc	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x9c171b45cc33cb2a5926b9007f54a669b4374d626a5780722ddf2465f35b5c0c1d45c2c813cabcc89c4ed7079cf9dfc2b2e3d9ba4129a9e5e175e62c2c7b54a026dd6ece5f53308ee9319a5c0fb41fd7a4f9eb0874a26031954e211c371fd81f6a86f994896a8ee5511659bd0ac50740f0514a8fa76d0655a5108da4a71150e1	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x63378e4426b033ba2e21e172eb6cd43f93ff047be483772ca642b673954a53394f411e5a7237d9938b97ae62820c34df5726f6ab8e296bac6d0f010f0fab3504	1577746819000000	0	11000000
9	\\x2175a40ab50319e3c9e191cefae40199765045618bebf8021e23aa637461cb96d5b4d9c74f3eff1b9200b96fa7d84fe86163e9c0a42ab2c119cc3fa9fe16b525	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x346c2280453bbee1766a6c7ab8f31b3e9a53cc1c826031d9e7103bf4dccf8cf3563e1561d93034678f91fd59acc4351542890c72066fc299f1b514877e100df5cb6cd238b6431f440a98d96a4d76ba65ca9b73e529d2f0d0302d40d6a6a9c6006ae40c669346030b616678a89cf7d74318cf5b6ee3ac6c96d8387aa6e3efd06e	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\xa85ce59543932d582b9b517660945104e4023e766d6898d40bb767c524e372c3721a4eb2614cd281b072a424e2d3159d35360da8d768dc8913389050279f7f01	1577746819000000	0	11000000
10	\\xf6de249ba2b075fe084ee79be00250abd19018f9c1ce58d6a91474f884cbbc627bd6dd3d85a0f25a49d4bae2a821c79122c557c10c9cf299dfbc9b1c4426ac10	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xe225d166cdc3410cc15b1b1c40b7474100584c62e431a01fd4dd893132aa663e29301e90e669bfc503614087521b98e6564866fa62296a2b4c91792a5aca60e8ab58c9ce53d345304929ddfca2d31e9ad0c44068c5da8fbe9d7297ae06e51a9b26a475f637568d873c6217db49897787efbbb98be7a8319f7f31fbaec6c9f162	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x6b5f214d08dcbbb3bd61504439ebe0b13a17b6f04d334f275a460a946233f5c0446c9bfad133381d8f936e1915954bee2320b5156101b82ffbb571e82475b40a	1577746819000000	0	2000000
11	\\x87e034ce46b71e8ecd207e3b40826c37382dea769daa8ed353bd42d4175f9577a95757df425d663e754fda2f49f80eb6d8be0e521b84082fd03cbe4461814e30	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x08b8fc18ceadca7dcb1ae403bb47aeb9074182f011f248ea46f204fd7fd6529d4434257838de44492e72265d678546146279300d80a43e9fd851e935c8944155b3649d4551bbd1abe895743c51e5bef80403ae2189e04ba48be85b41fab6cb0e7d7a75e46e0afd5b205a5008678832bcb8065ddc7bab0866c98dd7ddd0008eb4	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x9a3e9b3e793f4893737bb63fb9ab5ab64b2d9d0cd99b5630d269e9e94d14706009fdbec53e1b53f4bff80b2cae7bb035bc9956d7b5985ecbdd904e34bf313809	1577746819000000	0	2000000
12	\\x41cc3d5aa903e9557a1033d79b9c622690fcdf345cac631722ea72aedd8c246f644db7b355a3da0428fa4b75b69e2570e1a7492b9d5e0147379754564afe5746	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x59d9348e9d86ee1d9483c1a4ec64c569b70e617fbe5b31683281e44800a852f1fa950da3c97a2ae4692cb917fa2fe0e34780151af99ce8058adea5bb4d3074b03ecc7956a9fed09942b24703583c168712a562533d519a17820c48caec8a23c9bfae0a0ca835c5763b30f58d34018cc90bd61dc9a4f3da207c0199ac41b56a9a	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\xd8b6aa4e5a94b99014874f2b9034eaf1e7ceb3b46bd08305686121a1f1bcadc8ded214c4b0c37275291e98b625ab6488177bedc5ec9ece2e0341c5ea0a4f2d03	1577746819000000	0	11000000
13	\\x76824d6fca1e62074fd4f54d162b30061f1f5308c9f11221242a2bf29388712049881c111ff8c64a18808ff32c7da3ee35936cf5ddd3908d6ee6c9b30f34afa2	\\xc7c81552056d3c3df38d7d9655b32ec930080a5fbcd8a72833d0cdb41ebed8fb8d8337660d8db6fabd1d9fae828702e356787b86de7aa222432556d07acdaa15	\\x68f717db19063a2affa2912ed947142a28cbb3e195c283d6169e07e6f8cc225e94b069b12207aed34caa84115df255dd881dd64f3dc9a3ceab79a4b9e9e0652d62dc7c334815951d0e156890322fd27e389d6b4a3f5c7584fd3539f9bbaa4ceadd36d8fff38d2c870c5c34fee3333e6baa3301b11d0460784b618b4349f68271	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\x2fafd2463a68f9c52ada3914a4db7169681cdba5ca59b95b490dd5f6e916eceb1038f64c74888c009b20b6da52de92f0b80f52d67ceae913ac441ff7e606d003	1577746819000000	1	1000000
14	\\x740304aaa2d7621875587a0aaa491a2e99243cf23182dbbcdbbd2864d9d336c7e52902c8e22fad48959dc905b18327c2cde4e84be80f6b0c66450ea78486d947	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x0820038470cda671184357edaa3e812645173dcb1872a3d48481f9cface4c8288554de102ad8366ba8c8693a370c0301b102ac469c81ce2c5cc1156e17619f0800697ab5caf4708e5631a040293c089de6649b7b431f5d51485c4664f4136ce9c5c3b517294366695f5bf1d76648bd1b0fcd6ce74c416a203170d3d107ea6426	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\xe5449664ec0731e7bc9db7533c597dca042ca8870dc3c52e67b58ae0e329d8a8af32760c4aaa9d4b749cb0f0e78050c33a2af16151c5bf8642ccb9ead45f8b0d	1577746819000000	0	11000000
15	\\xdc106e45d97bcc939207c45e7b3f38c4c05cd0d8c12ea4b2c5866eebd24b101ed1a2c06fcea0caf9c0606d86cfc84ff3e368fa7402089e592d6815b973c11620	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x91cff51fba32c077176441503852e0ee711884a8de8ba80db057581321eb528eacbfc0a44d9fc98655149742db8168b29a2d06f61651b9d6633d4b82e04e2a3c64ea01e5fc90cfc606e606f8da2e1bc9f91c55bcf669e0f3c19c1e31d77ff05dfc39de8d9c541d354836df526bfe40dd0603b42db24e9495d0587dcca98cd914	\\x9f95facd9be9432600328b3bc40cb73c32468dd0694ba0ee2a612e310f6b41ca	\\xec335185b6d7a1fab692975315558b4994d22a60c23303284eca1e5050bfdbad0f201e14b95b792568403af611ddf9c73f8cfe11f712736add494b85f1a85a07	1577746820000000	0	11000000
16	\\xf2840d343ba11e1f22c5816ea531f2def3a021e97c26e8e76b5e67fe43ad56bebe65d7c74b62b5e5bf00dd19455d7d605ac53ef249ee547dad5a4d98e193a98a	\\x4b7038f16af77137982b2b32cb71049ff96b5dd48b099dbfc3c288e78325028957efb6720c89b8b27ee0425194dbed0f58c5806ec280385714bac790ca51a472	\\x839b82c3fa440858b209ec0fca2e0b44e9ee2db2553bf4a740bacfc8b86b4ad0ee2bc875ab573772d91b484fe36aed60b4e2294a20345ea51f7f79b448299fc4aa50424906a1ea6e7c41c536aac518601ad34bad182d0712fd144cf41f10e22882dd80eee258aa30b45f49e8d3c1491c59f2e3ace3bdea6f9d535d484096f2b3	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x2968e95d57d2c9b9bd301d201d02f3651b69cb10eda7d870b01cfc05fccd321658585b4711146afdcd81df0d9a846c451629cc5c54f4b78ea4414f589e7a1509	1577746823000000	10	1000000
17	\\x5c2e925d67359acf4bc0fde300db55451e40b2c8d83b03ad19a677217747c3a9bb759e70460e94294d0436d991f2715c73c72853cbbcf9b5a9f4a6e991f50cd8	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x8dd91bc418ae4f2bca034e589b59a0fec36ed75f39ae62585e74f84899843479e81de76b319a72f9ad65a83e5fb62818c395124e408749a762ca0de9dd447201e811525dc9d7bc2567de56bf3eb073d76fbff109a5c8b588d976fb58ecc78f110e45cceef38f2b097d36f2fbfb0707bb5b8e2c1e7a2e96cb65f116e9cb973d5e	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x9ff3e0e219ca6590050e9bd5be1fd6ba78d8bc1d8670a2517a00e91c28a9352f212b2437a4c5c76bdca65e0994556fed68f33ba82af329dca35ed78b30bb5d09	1577746823000000	0	2000000
18	\\x59b88e4971298a72e9c96f79f7b8f69c8dd28de89e0346626276cd4255b826cf6783333836a63680df6973f4e36ea27f9524cc0b03df697eab0b409c5c0eaea3	\\x32c060fd8356705fd99d02173fda7bc7c5d9b0fe782afd71ad84f75acdce927d244a84c1e49d08681e3724de24d455c2519935e4bb4c502aeee7754a6a0eaf50	\\x8680143cc37e52765088cacda82d3db7be9e7a3599cf2b28fbf451418910ad2892679500978964e8829083f23ac1f6668ee5cf8c9bf441638ed856c3c882709927b2e92390b829e1358e40e5439d796d8030cbdf1cbc4f217cae4e64d8b25339aafc0bc8dc80550cd474e40505e3cbf2dcb05453e6fd57cb599325c545f52982	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x1a5e96f86877b4688dffbed1754fe298eee72c9a9d35ce646ea12b95cf6d469cdc2471fcf06159a80194149128cc02b1a3a89348da7758b2e22238814dd4ad06	1577746823000000	5	1000000
19	\\x111ef6320a49e70e47d52530c0062a5f758a054cc68b2aefae1ec808a393a5a03a9415f3ed182d02edda5a9d45692ac1dd3aa5fd6491e1ea9d07b1559e20ab1c	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x65b99320872bf63935ea1e6af6e5bd38893fe20cd67beabc6a49819cb65899bf8475d5c0cf79dea2a1e59d5e180a39ccc14e80e9f85a399171bf46bd1200ccb910980f5aaeb9485c0b0e2007342b534f27600b4d87e646ae6437bfbd8b58505ec30b57b7925b3b59ee9ec4dfbb7618acad2c4262024a6a86b05cfe30b3242565	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\xa556d27b9dfb8842358ae0498b07b499a918d57dce11356a5bf98a0834c2e31ae75680a03b892fce1bd97d54501b007f57268b4fcc93e487ab44e2aeeb6cc607	1577746823000000	0	11000000
20	\\xbd74ec43eebbe29433ccc1f33ce283e68933c736efeb27d13883e06312d8d0ff99ef3ce39a58abded8813f5808045a544d7a27a00d45fc15746e3a7b7091e349	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x683f96ff12fb012557a8a33b676687d09b4c7d020cfcb4a80b332ef8af0627c67d4c779d6446d3e5f5db9d327b0f52dcaf0f8d08f443158711f5f01bdbbd9087df8e186a426847ecb2e93ebf9ea83298fb3c2112f8f619f9972f521980c2194a7bbe9eb5d11f231918ee2a9c8dca3a610d715d975b098520b44183306430ed82	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x6cec17d874b00485338cbde09701d45ebb8db3472425446fef95568abce0965a3aeb27542cda75f8d73bc9d1237f16d7fa57b2fea15f444262341843551ed902	1577746823000000	0	11000000
21	\\x8792e4b645eacbaec444ddffd36c3a0b05c8b7185000025c4616618145f280a184271c6d86b994fddce76e0239447f40842fad446d5d7e863f5733d45fe0cb33	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x8a025052a1071850d741fa135cf9d0c1dec4589f7880483c4c9156e944a356b1dbd9c97c70ded09aea7c882c6fc302f03de7b639592c637a5a135110793b937c25509342eb0bd83f03d48ff4569ddfbdc91c20b4a687ef7e11edf2d871bf6f9f2eb1fb0d89da6a982fed34166651bbdc510319ec64d0de4b4efe12319921b143	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x0698b9c332470f01c988d6527895999bd3c1d6166bc4c5889daa66aafaeb7efae3fdde36aba4f92d9665f92c3fc378d4069169f7297eeefe43d0b8a51bbb6f03	1577746823000000	0	11000000
22	\\x2694a04cbaf646d79fced8c60745be27c13d30b6d9a6f82d079bd9c37328e3055f2ea4bed7ab0dfeade1afb052632008e76d38073d4b0d0e78ce578f5b55e889	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x2c51886876381bad0d3861bd1a8d9d30fc41ed3c1911ffb37328fdb48ddbb4f7ddb0fed06caa080c494a6ad01cf80accc06519abc8f131c51a911d11491e176fed0169f22fd36b788f573c853ad22af094b0ede07e1684945b62f7a6ff91313b2d782ab7e7dbeba30aff48396706dc231d528aadd5ace43927cd95baf15535a2	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x3118e0a1a51915f86a5d2fab128b816bbc48b131a6cb6e0c86c12c2e8e4f53f8f4bcbce5c9c9f4c0d26316bba94c07d9be5dcfcb01f7e0a7174629f979b4c20d	1577746823000000	0	11000000
23	\\x477ec60e52e4f8f0296b7369d708c797d146445f7be4b5957b8fc15877ed861cc613b816707f74e7caeda243e53edc6a34998112fe18430c0410811475288298	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\xe3547076e5ebf86bd03eed9338adfb2a87dd73b5ed995fd71bd02d489d86d8d5c1611728962fbcf099e58104904e92c531d49ff9eec9342b83b3fcdc70ad4d6e7cc62d9f74e56bc8ffc19af66c10a4c7c87f05add13c91d38c034a417f04679c67372ac4aae4713ed92f9dc6e4c5686b437490ff752c28867a19868ca33a3938	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x7c1942cbbe810e592319cd93badca15451eb0afcd70666378d65d9c1263b36256ea334c0757a1e72b146260108b7aca66ff008b70d58eaf9ec291ca2fdc3b50b	1577746823000000	0	2000000
24	\\x39b7104828af556e82686fb1f201bddcadc6f2a4eca37352671513712f750cd126b515dc59c6dadc86d1f6f46a2969e91ac70bc5ad9521d171043a4799712192	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x705107e10d5a1fe97ad5971de0da57973d5eac6d38f11463833748d9d5aeb6981d812fb202b7bce23c5a013128d9ebd73499cdb4ff1e3156a658a432a5c2baaac7d4ef8c8da81ed196297305c907134b49f08fc0ddd9eeb969f116bff1982f5a9e7e887b4067b41f5b5212b835aa8c0323d4c5eaf1a27b6a93a5e93e1fa3ee6c	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x47f2eb6e2ed0b2ed81001ba77f4552b336b96c03b3bad690cac93321b642fd7447f10bf8b1a8dbb4bbbed370cfdd0d706ca2b6bb1b26db17728cd9514e6e510a	1577746823000000	0	11000000
25	\\x64f49c7130f52df77d64c9868d6f1e0a2c79d7b987bced1136a42b269ef833369ee55ba5f9b90517d7ebea37759924b28b4bee6ef8381842893e514f45f4a7a3	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x2494bed9576d2005df537ac250a33457100d753455bb4801f26aabd3578814bbfb80dc522142e733491f64085bde81fc06fc9bb93b320a5094252cd2020a5074c0d1f238fca312cf69648938d81db9f14d03b1f23253f32d9dde58ebb1d16ed46677a1357abf2a4c38ae4bbe09d48f33329b5183c1ed8ab70dac76b26649800e	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x047b716b16889983eb7064dcec30e4e16770462fa395a64d900059b02c50d497deb2c74473f7675c4850a7a084cc14d46ccc506f6fb2107d927eff32d7f99f07	1577746823000000	0	2000000
26	\\x6c4d6c2207d0a40f030077f9ab6cc4052af7f5adc1c55e5ed5f7dddea6e91d52f4169d904c4e1acdb0c335fbd5e728e6c306fd3a83e1edb644f9b202ad78087e	\\x33c0db5f2defffcc86fde4a754e2b1ee1fe5691e0748581e5572d74b1dee0302f85089ff6d609a9778bb49b9b40f8c7cc5116331824448d564b259ad1961aba5	\\x7c4c7b6ff4505673c9f54ce1be0fb5afad73c937a037a97d61349ad2a6ce0fe217cb1eb49fe2e65af4cc9100b17d5244eb93ce7fca8aee61247ab06537778ff9fbe554d7e62e2e51dc28ff2805005f162b18a27867696f28dd7cc723f2c1666141372bd40e6da88ec5a62869ce16f17325217b0ede9f87b928c9db1a63710d1c	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x5ed403ba8498895b1075397c67308f3b66bfd96c0d8a608a034b2b313a4cf7c9d3cd47d8260cdb547972c5729083dace765797ddf524b4fe2bed3d4a83b53209	1577746823000000	0	2000000
27	\\x7fd129c5502863d3ce33f8eb25c576db629d689e20e4be91a292b41949a78a11762b54950fba1c095efc918985016c6b3d9172b144a1dbd1e98d883b21fa272a	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x5376905e76953807db0f6b56cf6437e5462bf7ccc8b5cb40e6b2a70ce607b9aa86caa122ad2219a4dd48b8ed716a20ac4d967f98ccd937d40404a998f7c41cd30a6864ac76f544f09c2208cf23f7212a7dbc79e15b01a1fae74b433b267dc29be535289b42985f819e78e087d9edb003686e6c21093f461feab7727f8ad0662b	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x541d6c90cd791267a6470a6c0e025f9229efd2fd8d3a1b9bc7466353dfaaa7f926458732b7d4cba8b8c5282cba0491c9ca781cc9806e715aa651af536644d903	1577746823000000	0	11000000
28	\\x31255cffc74abd5e823492ddf3dd362db973b2bb4aa2624c61f5668a6696d8e4efad8442a58963edf3abc00cf23b72191f5cd4e72d8258988e32fef6bb31004d	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x147e242a83c0bb1a64ce6bb44a8bdb432c087421394aba4102181fdaf6b1d75c60672567599cd8dd5ca3119be5e2c2b80cb0c82f7453201890266359c0c12feb46d37e03943cdbe75076d5aaf17ca49b37ee979c89b83986f23a8bc0683e330d66a72bf28556e2189eaf5a81e74eacdbceea488aeb364ae2c8dabd2fe3e4ae18	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x43834fb4e8f98fae56aaedd0b0611d27ec13935d990119c438485b6702713b3cd06b180774b2fbabd83045d64f257e6064ca8c7ada2210c190a7145ec9c95805	1577746823000000	0	11000000
29	\\x0335a1665e5c89c024019da8192b946ffdf68c7c062edc188134f090f1503b44c3a8dd3af31e703dc861a395f5276fbd056135a84fd414b58911d5d70c1a3484	\\xa3e728aaf177360a81dac474f1e86aa3b90c0a2c430c433f42e33f9503f0575c2ff9d6cca5dc61c4740d03f1bc5bfe8d2f0f5f4cf2aae2968f0211ae83ffcd58	\\x6c6f1ee3976de91b548c1c37f3fcc153cfd0d601fcc084c35b4d8d52a736262e8486c1232de3525bf0afe20b346e0494dd7be1643499d42831fd606449e612a1b7b6385651381e4976b56cf0664d677b2ceba77c1e17c63f7ba754b7e53257962e7bc065e5703c5bdd7175859c315bc294aa413bff6c29a3f763f00fb34a8d60	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x399f7f4016f928a0c3360092e58a66f0246f756fa1061cf10c3032c66aa574b5a560199752f7f86d3a7898815d7fd909233bf94cccdd293b6c0f0fdd60a23702	1577746823000000	2	1000000
30	\\x7cc79244fd9dc17a78eb2f50a7bfd7de7b2b6258c0d9636e50960f6c6d5182006acf58cf163498f4146ec2b2869cf5f268227ae601499612932023682ddf1131	\\x9d3a933d93d580f4c57e0e0d1bfdc3cf74dbce56fe91b427a7c6fbf6cdf384a65f313afd26731287a3319f5f8b98894d769775e0922d0d3e712185512fdbc4fe	\\x4dca8d0bd2d80aa9d9952315c03569b2c53758ad47236c1556ab295ea61a90183c6a9a950df5413258b6a55237fa24a63b68b494ec9608e9fca3830b11efba704f3b7190446aa7234f991cc8c257a5b74c972eb023b17965b30aaa6efd0d92ffab4cec65023edea912855063c638d182e18fe4a138fd8a5a5382a4eeb2430030	\\x5a2af238427f5e96cc842f3cc8076a01cafdd1f0b8c29a1df5db357b252bb1eb	\\x211c97d8ff484b981813a088c2b9906c5e24313160665a189862900a33b2753089a84f31a0ad104552b9d170ad9a0dde61259980a3dcf059bfd204f087ff0b0b	1577746823000000	0	11000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 39, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 39, true);


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

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 13, true);


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

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 13, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 30, true);


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

