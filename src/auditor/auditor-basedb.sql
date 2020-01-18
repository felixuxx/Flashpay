--
-- PostgreSQL database dump
--

-- Dumped from database version 12.1
-- Dumped by pg_dump version 12.1

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
auditor-0001	2020-01-17 13:19:11.001803+01	dold	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-01-17 13:19:21.416971+01	f	11	1
2	TESTKUDOS:10	XFE0GA99ES9RM5TBJAGRCPVD9RFNVNAMK7S6SZK4RKSXAJX86590	2020-01-17 13:19:21.54015+01	f	2	11
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
\\xe85bbd1a29c89c157ecbe99814a3b79252dcf506447743cadd9974358bd036a9fb3b7b640886310b0e8dff523e2c96af62afeb54c1f43eead3bee99e7fb7a708	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ff43dccab8a6d0aad431b6c1e8fb58980e1178b201e2fcc92e3f3779b38b7386a2242b0fde53355cf409185ea87eb356bad19a906934224667abd583afca542	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb9a25d8a53bc26362b5bd77d5b8a2dee4a557f3d39e5499d66eadb014334562e1cce59e49f4edef1900a2c54c66bf3958fa82d6115c84580246379d8721bdb1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaddbbb6022a648ef2205b272c81f5f0bf096cfd5db483ef45a466e91b89127618c690dc0e106bd3acb5830c8f50e5669bf9fd17affd72672caad5f2ed48a9796	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66bc40622c02a650f9960f4ef5e35cdfc37700fe15ad2df970af9bbe0c027a070b1c6434e019cffcc3f06f2ab7c03c22a0a928fb2f61f6a1904c0493501e45cc	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06437d9bc7bf5f12e7d98aff2e2fc92c640cba5baac272bb68ab7981b4b105ef83f7b897dcaf04dd7b050928012ca5507305713808d6ca05be2a396b34f40b6e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x64cc56eeba501d3cdb13c6b2a56b15df4923b286ccc7712cb1749e496578e3cd71058e24f9c2efac700518b3c77f86f378f3730ef60279f737f47139459a74ab	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd47b908c6d4d29c0a7c3d0e1813cd67ed91fd393f2a3b6e197687eedc79acd2921d0a9e0dec4bd6e103a808976986e5d3c90cf3852a999ce815c359c1ff11170	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c2e2e22569ec663ef9cbb2a100bb4bdb5e2f1c2214c8a4d0df947f7629d3eaf9762bd9015d7f3d18e78e9b8c073aa20f4043bdad068420c0d2f3b68f81571fc	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb458c12d68d7744c4bc7c8abcdec7c4af317a169063a7c18c00b2099caaf5db764536f4b085c174c1784bdd37890bc51105d26ea251ed6481e6e2b01616cb09	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x16f2f906dfccd2971627978a05ebaf72e2982d6765409abc9db50c45d066db4c8b0fa20c2c1cfb746dfb949400b63205e97176497b97d0416031a06b8aef56da	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad71083aab030de78a99a694ec4b818e7240adf2a235219eb8dfef02fd99856c37d3bc7d5bf8e40992527be328548acbabc12913f9e92ea1fcfeca4948b8b242	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17e07c77c8c50677be77c4207a8d98f5e65769517ae72b149baeda29d0b40809c9c04b122db18d834e0e6baf8e11b2d32aa6ed5201da8e84dd596da9ef9123c8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0522500da8a520e18544e1cb1c59c49b37a58037372d80f3855499b52a40fb990c3555ed56c104e076d42b294ddf20b01746111c4de58eef5ad7434f4e7a0815	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78bf89be5081e92d63a63b243b2a6439ae78c04c997837e13a594409323fe3da70250457794322b64ba28867074ec5995f414ad3d84068ea8f27605b4fe75dc3	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb617ffaf551a0ddb5bc135d846448e88a97fa8d9cd2a07f7e8bfe651ea26a04f4dcc85d6cdd120b54fe5fc936f1db3c5b503a5b9f22e3b6e4935805bab9f1042	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fbfa4b6c204622f9b95ae7e277dc00a435e41ea68a4b854be54ed8c528aeb28064ecb5b3c57d9e2f0385ae0d5b3f65c3899bece1d666b8bf2e55be90d14edda	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30a103295b9a672e69ccba961598956089a03458a2311855edf888a549462460010c25756c14982181cfd361f1d19f55d58c38449b59aac4fc9d4a3ff3c71fc2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ec5c9f90587756ebab10aabbbf45e3df5258e534a1fcaa4369b7baa2a4a3e9d38ca059cc893ede577179c30a86d80c75eec5a2bcaef2713657eb4e6387f9a73	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6723b09089eb41def23781c952cc1e8806c295139fb53db8557f8a6851ac8a29d01e4ad68559d712c73ba767b1ea434b3243f14494881360f044256dc32d4a5f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59c1a3e24ea5d46846eb84de1cb0cac1514a5f4e3e1e993f36521e3ee6ac4d299ef7f9291a24f5f470153f2d003108d3663ba0c1f4ef6fd5cfe27f26e1d0a2f0	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5879c522660d4262462641c3eaf7bcda027e1f469c0d36d2a2a80cf53f271cc72e0a2b900d4efa5fdc3fc98570dcef433579e5ff65d8b4d0d548bf35811afda	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb703d19258d04b19c6d0c71024fbcec622b2f9d922cb40b4da4010799b8dfcba1be7a5151c6969b8c69ad0d9735b3dbc759983174be86667aeff560d8aec67ba	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76a630d0d947dddc5229037d69176aa28636da1d12cba166b4d903daebe92a4d838630892bce51c42eaa4c4656a9c9c981cd554dc69ffdc970e8dc4a52b34f43	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x116f53ff64adcdc8de105a773f2d4d0e5ff07454f6d83410ff976d98dc8b0d61974a6c9382098dfc3f57c2ab1cb4ca9b0c797a3c06e5ef689fa031813f99840c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ca7c239f1086a9b35676c6a7476a28dd4306d2aca54fbe4fd3ee67f840022793e68cff37fec07a150afae35277d2706f1b35bd5bfd6ad578ab24e4db3c17179	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x711f4049c76221ca2840b3fedc0d59f58728f467281953c37c8325a20d612b25f5c0c59f0ca93abfae3ecaf114f3c2c643e61b0985544a7a455a7a96ce2c572f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7a9ba45b1a0b4c51c430d56af6a26d8d8c2ff7e24c0a6399faea48ac91af75b51a1ab795479ba03658a14f4e1330a8074c107c72930e1d0be49fac3cdcf5dd1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c519f1c705660c3ebb7e8f1c781642949f696cfce6fd91d4a2740b70d0610103d3cf67441be3b01e0bee983294ea14f922211410c5b598bbdf549d965205942	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c635cb252c6c4df4a69811a6125a59e539392607328373b8d70339eb592d254e489278e847421b479f8927ec8ce91c6bb5f7ac7afa88af439d22a0e37ca2bbb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17d47e3e5c02d251673642b5a6ff98401146ebb79767a0de3284632f8359326a070c62d8b7639ba8234ceacadc55a9400e962b1ce0caa4e9f223e4683ef9b8da	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba5c5e629fa2bac2dd393d665426ac09cdeab8fef84d3c858a347b271aeee40cc0f3e8570e8ec83e814032fdafb60b663de1c7655ba17ba3dacd86bbcf5a63ad	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x806c35fb29cb534f135cf57a47f1e8e9a4fc627b1493442d2d8d3a32d9cd8eec2438bbaa9a58aeeda5200acfaed02f07890e85f05eaa8f3608dd8d37d6ced3e9	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1b1cd52b53fd93409562be0eed9bfaaa8933bfc50303e85560ea0df784f471055259bc956118d71df276dd93a4a5185391c010fd75f5fcd9c7035c0c781ce9f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xebdc64eb1fda2dd74539890ae74d9153882399047a1ac2dfbbc32dc9ebbbf1bf8ca8607f06ca1117ed2e0f4766d0f7b9cdc0e37625b5b43fe7da5417363b248b	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcbd74869e8498e95c1e846d39bd3e870143ffcfedfc96556d1f401354407c8d58e0d3789b3c400cb8c298375eddcafa58dbeab3659398ea66c10470c391ba978	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbe5ef50b6716c57e24342c36dc247bf6cdf5317b65bf85dbfe1a107f9434e319de923972272389e7affd3812230a8cce101db2c2f883ed8fffff3dd32a48445c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa9a59de75c88577762431bb5dcdce749d2861ee734cffcc354a166932c68c369a37dba5cfb22bbcf1316c981a8ef2fb00460703e815a2d87d9af7d421eedd076	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc41a3548b18985ede30c97555554fd8b3a88184507ade30de87b717e71dff13ac876a3730aede17b5c6557c87ba02e5d0e0e2a8922d590626d431ad3bd98984e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7a4280abc37cf03a951af8a28755266bba1491bc67bf8d13ab62c1a512ac43765f49834f8aecb3959b651957438555ea60cb0d8ad4b4b7a46313196c78352707	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x42855c4743df33040b2fa1585316e50a6e02fcca060f2db31f8e0d674012ff48a014d7d464c63f3674d4f6b93bcfa196ac659f0ef528a65f7dce671479230459	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2914771762064d9088abc2d8e81d9fddae15ec89e71854c846b19be91f60f7dd31d20b88e2c0a48dc9c609c833863e2dd9df9124ef84ecff3d63a33cfa539289	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc26754583e5ff5fd5de0366540345c8899268b39ce875caef3a7709d915ccce122137475b192f532e9eabaea19cdb0ff1d76b470bed853a625a8cdec03be6dbd	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbf20482a249d4f36c145a14bc7cb4574993362f48790d312661f35e643c2ac0bb8434fcdfc19b8e3f233eeda4393cc09c90fb185d8e8d23fe8cb9b7629cd4626	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd31a56cb8b1f6e3d8201b731f4c3d4ed53f56a818d489be7feaa6389809694de601917e9251018224d8b08e1dd8aa5fe6408c455de4a50f5a7e5e77a7447a68e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x121fe3d9e4a440cd93b460cf85726be77c3ee4c4e2d00689b9d4fd0ce9d020850fcb4090cea261caff8b2de9df03b8fc04f27fa0b632c64f248ede69fcbf2101	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe528da21c822f95a0170ec9312cd0f0a07d46960a6fa3885cd4817d37b376b5f311fda78e66a54d88b7a7318eb0216aa9e4d3d4e2401dbf7dfc2c3ddb86b9a29	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd90211e6a1ba3fb611cc8a46dabb0f83e6b77b0a9b8555b9df8da418202afdb39bac3ef5ad48ede549801ffab06215ea6f0b82cb740a97970cc4ceb701ba2bf9	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x88ab97f35537d70420af3786fe62d35434a1842d8178275169e19a8553773ad9768d85d4c36ebc2780f015f96935477740678d62f5b8a46065662f655d99c831	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xee9e3768ff5fc121e7f1a49458e1abefb54c32dd070aa895a7baa189b9a409d4bcf1bcb38ac69b050a6527a2f4267b56caa025c59a0cf1a5d39d6bcc1ddb020d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0cb8cd68ef3c0ac0f59dd577ec0fc4ef14fe69b7ee21d5c8a248da14b3f6b86d322d155620b76c6a14ffc5c2a5b3065d7e10203228b38bb560cd54df9753bfe1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6616039a1ca97319b2cf57c109507c3987eca79b53fd83898c7748feed3d3e338512c52a08767b35c83e496684e89d5a67a2281e9bc15cbe9ac2a421ba0f8254	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcdc47d8def4935625e525cd0b5ad5f9d11a24d9fc2560f161a80126dbc324553762b19818f9b19053b82b3ebeb4329bff52260dffdf68f434fb9fd03503f00fe	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7ca9454c59b3dfacb85a6a5c298986ab8e5a22419742c693a970b50c6e34f6b80b1d83be58889de0441c18ae36d42a8b96f1861066768236db83f08845c45227	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8dce34f39e584d6df487b40471fc239e089b527022864213acdd2b84b441c6eb2109126d62a878e7bf7fd9c325ae70585798bb2de2fc794ea059c545f628698a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4678dba0a8c14348812ff3b2167f48129d24e698a360531f0db5c8bf1f48fa11e76af4c96d6d18ebfce28bc7632b057e3969744e3eede8563f69634e1c5d4da1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x24aaf7c63e4a0a37db7826b8f2e88ad81f7fe2d60fd2f8680e9b310d0ba1f6f52624afc9940439a49ab5b63df5d7de5d70eeeb76e2e272c2fa789cbbc84c1a5f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc629ead20d86edf658e74c78049a110b057ce50d3026202df1c7264e4bb6920b6eccec289833c448387b6c9a675c01dd75d8a919b83dddcaedf0dd4e5146bef3	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x173b019d51e0a63db8c1d63b121fc3331557b1e32f832d30907d70e602880e75ff94720401a2a4e2d23f26741975c839022236d62103ff89fdf545641f3ffa43	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd8bca70dab224a25d318423c2c2696f319476f4b06e690490b95a1386b54436795e6d5161f6be45023f8f2c1449ef28a12b355c1fa4a80b90b2b0125f1b26fc3	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x04af7fa23ea838d93a6240ad832cd5a6d15c42e05528f15cf1d3f3d522bc77783d0dd3e77f8f26ddb843811055165cc5bfa89ed351ac351d88c49cb9a17b66c5	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7248f66c93b70f6b58b3c5ecec83601963c3a19d0ef3ea6c5ef54bad0803e400b328186c56ff3a5ed85e345a6961f0b642e8d8cd569517b00a6fa9dd6fe01e23	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x35791659188830603b037eb44a0c55b637d8cd381e32171aaa1124a54d6bbc569591e2383c16717cb413612aceca5bbc28b280298f8be48f155c8cdc67ea782d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8db55456bdd6b37139c629cf10b763001f6a508de8f37d118bcbbe55b6920bd53f2e1be99d0222187a4bb370bcf7641caa10aa118768ecaf454472781d3cfc36	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x55dd0de1c6db82c1f3ed8312a5c14dcc37e05b29083b53c720ddcdd12655c9e35c81b868d0d2b048d5eab0b4a889c8e50a428cd29788e73b380dc4858056bcc6	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x54c8ccf42396248eedd2211e83657e359861c8faac3c01a8a5f963201772eaad5942c8cadd9db0c8cd8008c615aacf416544fb361de89fdaeea7d8180ce0318e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf1468346cf1b673f0bbe22b2331aad8efff46f10a6c8012ac2afda2eaa40d525b66ae72cd4ea8eef3fd76233e8dcda14235095fcddeb317d29d63ad0eb619788	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7962d743136c8abec9ff9024fb629513bd5789fa69230ab8d743fb6c4b35c99601a975099dfefb2c3385bf803573cf3a537c62bdd530ffda046e6cfd471ab47	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x20170b616b395f3f219a6d53fbff675f0ea22f73fd5c03143cc0cd2ea0f7ef0b0af0b93c59fc6b15ea2887c2705dda28fe3135bb1b36f1949db20defb0374aae	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8f69e59bf452b03ad72b06a683b9e837d39bb04586d0a0699e23c125c036721fbd5e0d5629f9ff60ddff4c62f43d0449007cb15ba0aba68b0d024019457a2fc	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff0627b13deaf549fa7e30e42044ba222268853db6ca301c0858f45acad224d1845dfce6de4f4507276d1d2160946e89d0339ae4cc3a79d3dd0ecacb21c15981	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb5d2a0b8a598f194d6c70575598803d3e24c0f0aa5662a2584145439edf10d1e5db893240167c6b0fbb5bd5de609bd99d22af52667577357c4262ba693149e2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6acfe612f191598285b46f5be550dd85acb133f305d31c76a6639f63b8e824c99ca2d46b57c27fa7bba1c21451f447e7de0565baa7700360cc2b75297484141a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9931aeaf448ec211b2fde89d88107c09ad960f60b09d9bace6bc796d161cc480a12fa9817cc5da3accd83c119319893b4f282e2639e75c0d69182e003febcbbb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xed26f4ef86747234477755be0f7fd01d07678fea13965d065c02275cbb1eb1d3c2d45041c589adfc58f5d79b5afccdee6d17b8645c69b41f4b4883007f6b4754	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc12798b880d7aeb83a0de04c330bb805b12946a8cc665dfba554068d1f98092d1a9395fdfa0cf713f5b80edb2ebea097094009906963c1a787f62adb4a51bf8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb45ab61b8cb90a1ec5be87bf0b94274f445995c47e6fbfe824d3fb9812072bded0db3bd1ce04bd4f3fddbdb3eed0b7887117410e22058b55fcacd0e706066e40	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53a78e8773a182e41068fbc2fec1f82ac27f99cf87a1c96aed67793b71a07fab7a2b861649e90ccfdaae6dbdc33ed215a66295444e1f31df2fedcb8da099e342	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbef70f33ce617627ee2e54fffc1bad5aa73f6b62fd1c2523d5d27ed72641ff2ce21b852a41d17e73148f92b83d05e0198befbfe2ceb51001a7096ee7cfa2e493	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15083927fcd7d1075ff11f8de976f6f052907cf7ce1a97c19bbd6f15b7a1e454566fe0029836736698b3b25b0f5815ee41c6c9ba2412e81b9aab040a1a618920	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9350fe55fe7eb0fe72b45a26b2ea8a81dcffe4548be4a17eb71482852555672735a5a6e534b4f440105efa078dd7a47460ac2d14dbe4d537942325de6815e595	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7430e350d61696bd64a10276a7ba9b4fe085ae5b757bbb8c83b5e877937f07ce145f1be2ca870331258afd97a99cc1ce91a9b791c4a144583d8628b70bf0c888	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x092c1efb43297d40c980c8835133f782987a95a8a92fcc00ebbc4ce952175b100fa3013e0e660f73348ebb780b590ba43dccb6917076bb4bc878f976619ba5c7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab5e7f273af18fc7ca916169d77b5bc93a5acae2b05a09f544d6aa0fd88801065e0885fbdd42236ae27ecdd7e7baebed96aa101c6f7c6e9b23b472a02377cadb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5140f7cb88e15c5f9faf138042702a1e3ddc48b392994daad7d01d9932d641313378f44f6a8ccbc73cbd1129de325f3f5175ad799c563f9b5a074671af9f469c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x445df770979de2b8cc54d5c15b10f0a5794107eb595059e18c63b016b63c782fcab6ceffa85d89c8f2f376b463c667bb84f31fa6dd503f4caeddd73741d2503f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x68ff51852b8a3d10b667faa67d9224da949f196666acc7fbbe8c3a13fb91827463e5226ccf676848a217c330660c5dc372cc3060677ccf68ff4fa4d0c2d697dc	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x28564d31b350deb5ee3380b27ae55c535ac27aeaa22bc27fcd36862d7b2a8cbc8fd3aa01fc05d8bb9c5aeda26d6c0e9d9c2b03b47f16d4e21f35f2547ce49e9d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe41ed2d7569c39167cb9f1fa0bc20ca6356c261e998a049925b75a041f7860036308ee3ffc4ceed03e595fa23905ddbf0a07672f2a847e87fb1fc26a817736f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3bb21bb9c7b95cbb3815a5df2ab57fca2fffc37f0d54786415fd8901ec93b0c4db409f1061b85d00ef57fd6a2194678fa57eba0d085c466f7b6ad0512d9b6811	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4197872bf698e6a3e1183e483043b9f658d2692856827010a17cdc12c7e792c952f534afcdd1058ed276674f42f49aaaf2d9cb77826517d37e20c83e45d9c11f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf0f39f1dbdc07d6e25bdef14122d57a4032472404915b8a685295ac7d14f75ec757a6299fbbf4d93189e5bcf6410ce7952440db1644a14cc55dc2c6a53f1b5f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb8e03097fb0bc80a392bbdefb75e51a81480af6f814deaf019158d4765be08ed75f9eab3d088b0a628ca94d90a48bbe02a38ca341e53eeccbd242c0d514dc8a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa85994470cd98f2a2f997f71c3631efd774fbde4caf970baac64407cb8727bb861cfa9ec5e2099c4039310339ce400690d773b1aa4dcc93f310e8bb5964e87aa	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21a9b44d25ae708ba2ef585fdfcd5a8a41dcc5fd5ea0541c1ac9d80a0b7eaf71dcfc8b11f2cd005ef2625816a2f05cef04e5f61a92f9f27c831d5299ce3dc025	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x590dd605f57f1cd12109fed61574be879a0dbe23a237da5364d0cd0ef4678d62d8d5d292dd3b435ceca89f5b2a4822dc5ecba300820e8b66bc7028781905bfb6	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x49d89c75642c701c46ed0e230d0872b72fa894a8ae1c44784f8d98e9844c1f5450d1a61f147d4a75660416ff5838261cb0ee4c5b12d2e906012a3d64af226400	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x313d76cd259465fc92bd99662f10ca8d275293165614ca3cfc0a7e7a0dfe7df096fb479274fb57613162b5db3608a8d7d3febaf8be1ce8403e01843e9f065551	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8a617cab802c5a35ce0229ac2f4f899fedfd5d4176b54010d7a83c8e3739451613a52ed214584afbcec5cebe9a2f2c3b69201642e23fce6d9ce995587aac36a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa290da8ad69402a720bd54a8464112e5b3b0d9862c11a44a9fbfa415b6d86023a0565aa5d213d86df2dc751e3ac37d97e3023089fbbabbb5759bed6e38ebaa1e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3e78548edd9872f9a0e3a1e05d0dd1ecce90351238d9983d770a7714bb8adda83458fa3a641f6bb020619afe3eb3fe838de654a9911b4640e1759a2d94ccdd93	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x387c0ffe2f32356dbc7131d1ccc734553592783f10f169fe535b39446dbcd6238d7a686421e3708f962f298f294c814dc4fe1fc168a02bd1f9f9ef3d30c87d14	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc62ca3bff60fe73178150478cb1ec7f017209895225a0185b4d3ff5da4c21d44e27b358868074b3feecbcda1f3d892b7428b45ed465af77ea1042ca56137b32c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe92fc6a1cb732eae503494148507291bab1e3c81703ab4a0b42b4d1c57aec4df11e632048cf21946c5f41195e323384bc441052294d1f533662e386e2c4f7f5	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdddc2a4317c56748c25b860e36e257d67931c25a5b98bb43492bbfda233ba71aad56c8c4fd7312017b101472842602e74691309ffd91fd3397874a5f797f7426	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x57d9b013b4f71358877d072a7066b31e55ae0ecce30f745f30d56ce53239b6239cf0aec9d010b1fa5d55228c8d1f46be01e98d2078d033a12d068844baf86a88	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x262c99ef0ca962859541cf489c3a6ee69b5197b73be72c3b1ef7f07ee29d8d697f05f3a3a7e32cd313348f309f92e04ad9dd25d6f726ac91b70dafb3a4c1c52d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x26518f3fb60f45d689360edebcdc15d7471049e9755cd52da3e9604fb7ceed412ff293ead28d4c85bd8f92dcf1814afa55ae4717fb58f0ab33fb1d30279738eb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb8fafa468fcfd050edbb896d168fe98ec390973508d96c9045a2ffe37c4573d6830129fb37344a09f36769d0af8451c006eaf6183d7b8d1e09c784daefbef238	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2deb7e2cc56cc0bcd6f8c7f7ad12bb11557e4886d6fc64163506388d4c2353f1806b23651fc7f4cd506ae7f19c4e56d72fa8a29792a5358e0a42afef34670c3e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xadaba28af8711606dfe5547c625c70e4490d71aebb428121a34a0ee5c78045b6a2af7f458452a826ac656b05df3844989191663119e833da8dfd27ca1ffb163a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7bd9c910666b3d193a91972c2a5dc6369d10e63e01cd244010cca1b899d72500a5d99ff1004cfd0b4a215013ade0f48b61e936e553e395cdb9a6158e7f724f34	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28c9e1d32c7f25fbdebb731decdb798ed715cd98e003aeed9cf28d8aed433446fb46374d6d2c7732b57d0c42a8745bdbbe0220363769eb51834f3e0a29762556	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f077ac0df4284a55511e6dd7c52152ecccb4e838f7abbdefaab27d74a749c4cff48f05daca404e29c226f4f8255a0f7dfd83dbecb4275ff35f042ddd1e1f66e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x069c288a60cdc4e45e05e415d49f4d645a9bf3b273e78ca0c03b3b9f279521866def87afa750efe97fe59dfb33254c5f59e980df70f60785c8aa40d6699f7f34	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbcf13492e4b172f82aa7f8fa9c0c3247132acc0e2c3b35d34768f329dbd086f5841a7623961d042210e76ed0dc73371e9ccf0cd54419c87e30430d4c8a84088d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x20e69697c15c800bfb579bad48fdf9fe5fc4779cf6f412ea5b71657dec2235562b753c4fc7e5a99a98155e89b17f3e748c619ebf6e5c0e32b234ddfa0726f729	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9cd14375d33b297cc9cd0edde41fddf7469afc9d31373310521f82fd528ad8d7217d1b493e5552066c192cde17bde5be6c274f9c6b3ba14c92c438605b12a1e1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd1a5a5d9939bd6bfb88f27824a84cb6c3be53e6330d163a464dd12e8ea1808ed5362f60effe5498664eab6ddd31d9c40d04499113c644caf9396c8ebb6180657	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2294ac6baf08cb8a1bba82f185ef5753a1bddff64cf2d513faad92fe6f17763b830feebdfb365fd4d67d78905d8f7501665f76409ceac073bfcfe3cda764108c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x39994fa418507e8e29baa7ca160b9efc0acc121b31d9541af171e646a46417f24df29c0bbea756c09cb181427522ed7ef994ef9aef3645e813398a0a41182231	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcf19e8c64f03ea6ffd4240b4712d000b96b48d27223229766d0d1f08b674b929e2f9a4fff1122c9af9772db758c67af3596b19a84d7b39ac3bb993baae637c0d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5af1703c26be8e333a40140420fa5c3a492faa43bf4433e1266fda7bf5a8ffb983052785fbac2380d0ca2d9df5058fc52054d61fec5854e7082c19ae66f1586e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x86dc58c9b194d57318578fcc3f6d65ab77e1b4162763fd1a81eae8f753771435f993027e9184d24db99e70e46baeedc909c7941d655a761bfd2879471c701f17	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6a9fd772b0c8ac85fd49e1fae45922f1c59bc0ea92679ab50182ffd3e9933a680ffa336937a98e5d6cccf990464eeec6986f0cac517f211b608544ede8acedf	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb173cbe6531058a79a269ee7242f8762cad05c06b634bc876197bca96cb3831fa8dba187f13d00a9f587b36e23cbcc8e5006b0bbb70629850bbad8e19f90d448	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb07248d97e5821d1a8254b9cabab37baa9848fe3970df4d3abcf554a6c009f4b58a201de104b92f9d74d5debeaefd12c57fe274602d0bdf56a84678ce19c7ab1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9d15f4155ae75157143bfd1550ca5158b330a08c09f29d9512a75ea6b1ae4650e3944d4924678f7f0a6d153d18977923ef3729136b84a29d2af8ffaa11db9251	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fbca0029ee615df4dc7be0d566eea6a61c32b4a8055c5a72dc2b652a53dfaca2890da9259b321d99216101e90ab92cff9e5f2527f490b4ba45192dd7b7ea9e8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc45225e50d3c320cc0dcaf8aa2fc6e1182bbb6a585ba7efbad12ab0ade6d58f77716e63d7c3f182529738c72f4910c3c43a90f0026d95e8808489d24283b52e7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x996bc2a24bbda1a3830d24dec7b88b7ebba72a0ba4f53f927f1edec75911c29707bfe4cb1ee3b3a3770c4f15c477a5e1be163277b98fd5f41490078dcaed9bee	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc4c2d812b724eaf6b8afce9d9af293554099e17fd502ebf438da02bdf728d533884d489cfd5336b3cecf46e4724d4dfa3edf442bbf3024fa3a0ab0f7aa6907fd	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed2214657088da594b799437eaf4ecd0566f2f85df16144997cf65a0d8da187d6631e03541de5cf892cbb6626598fe729ad2d6da4ce2667912f7ae371cac6788	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae502a72e8ca3c4369fc745c499e3e5c41c5a81d266891ebe817706e0945d63937fe037905ca77251bb932d842c0019422f68eb0c242a4f61931998af92c034c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa51a74c621299c19c907ac77430a2a14d5c55e941311c516cbe9849bed5f4d32bd1355bd381babb808f1c06e0a11017743b2c510597e6bbabb989ae750e57bdf	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e414a6d314d31eaa74d67264143a4d7633262e2c359d12f2b233587bbef02a9bc2be9892b5136274c6ebb13eb82c8206009ecc8dfe3fd1415b6f56230e3a57d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f3b11f0a6ac1c424e5bebb9f8384a8961cfd156f1ace63be4de389832160c181f3d8ea4b9d62fc11fe5af3ac12cb23d1ad3e0ca86986ad1b5afccabfaddaf44	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd528ce97e58255ef78db52e9890ca853297b3739acd70f6a29e3194673125c9353b4ade4522f693419ba889cee30dda7fa189a393992e0ff8e2afb4ceba65f1c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4d7b8495662facfe794ebae7a0b8880162271225f2cfffa1635a01a9fdc468b142db4b7d57e9741953d54aea2a9f8f39a53ab429e80c19a6ec7368edce470b8d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4f6cb3406e04354ebe24164bffb769ae198966e608826463f92369376bf16dd112cab9bb2bb0813a5e26d065cdfd870a4d8dccef609204fe77c45b573341561c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbdec8bb2137c57e7db6c563d71eabf86dd1f7bcb374946118a4b04993b38b80635b2e5021ce0dfa399c093a10ced9d5d8a8796eceaac779117bb6e60eae10845	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf917a8976e84faa93474f591eab7c817e3d0bd65416ae24125c5400198a60485fe7f6516ee214d477ba60b2cf6187e2b7e271a60bf589944380abf744356f8cf	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a71ed16a267f15bef517673934d90ebf8119b6abcbd877476121bd11a2720f5812c93aa0f00ae88d2e9dd0d2f306c749253ba71df939f7216e6d47eb7526326	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ea15d9549249162e8d56078fa4e52b210248322aae9d8e0e5f3efbc655efbff9633f0cfc55e59f206e4d0754746dfaae32a92b7647f6e349392497a14f6e3f6	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd06b00f554dce2c15ea2974748f237cf97fef99710f7858170284607e2ba20dcc6bf1330692861510266e8084bd591f69999c7751ae5f74d5ced19025e4d6655	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e2218bc2d5a4183ec026113f4578da4f2006e78cab1c411cb67572cdbf670af48604c8763d0150132bdd25937fc41efda1dc8d312f832f066930985dc81a208	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c1b72d76a056f16868052464b9fb5642a8c8dcc50c83e847cc95377626fa935b6b933ccd1744ab8a7c5cbdf6050c2392ba33d7bd94148c8edf70394bf3bb62b	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a4baefb4bb5a94731f52bbca48e9b294c0b7b9653d4f633604636771263943e8efb439e1a78ddc8c9f063cd13a490ae579c27b8a34bb87fb9cad37374f996c2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8982a23afc31fdf35d3ad3a036267f0b782ff696fb959794e76d660750d007bf74bfe5847144d7f7accf212224ef2e5c3bc3bc721fe8cb2d1955d706f5eed759	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x765be9dbc2e0c70eedde11c0b9cd4cf16b1fee80a1eb905af716cfea78f32569b388148bbb746a16eed7d1e7df91161b829129f680a54dc07aff19a030bb77c2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x378c2b1e44641732939d4957db26635c0ae4accc432e6c9b095362a8f8acf7bb5afad01a0fa7164c79db8378bf0eafa9475dbb7c27771054b0a68903d569b589	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x535ea35aad44943462afb836b7eda8655bf88aa8cc6c2debd759b9eec2fe21b4b6e3a6f65ed7b5e091cf0d81129bb04733d1fcee274881ae895384dc4947080d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x50ee2a5516b6821e474a8bb7327431f76e5c920013bbd6d5b3962031697a1ab13581d7e0c0f74c30aa20d1ebe0bfe619f09802b5a0e05cdc4974894dd9508ccf	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3a667abbee696e2ff5ca2da1a5de9fa4e4d9966d169dbe94d57e3ddc45f13a4a7fd9fc184c3b126ea014044b0903c08a733d0b4cc4e8733c019bec568af011f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x56bc5507cade463ccf17964f66b689368a37ad21e2af56bae150219c9b23e14282b89611c8338f4ef9a3d1f3762823027298832fa2e4cb034f8d147732488b13	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2e99d34143e3c2c1b2335ce35d13ee3377e7bc07ef728896ccf781d297571d5cd3ed4ac0b327c885fbc382077396bd8b82136391f7f7fd4d83d3b786b8e2e373	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x88cd6b987e7509f4a0059845e0d8c530d0a736bc5b534dd2161ed67369b9a3ce0760604ae3217ab0fa4e7b992ae43ca78cbdcdcee16f4fa5aad6cd5ca21865e7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7fb22ed11bae80b771286204e526a59f621c5af627892b77f7f47148c1cea87f2a16a11cb5dcdcff3c26e664a9d40dbdf6e26265b66bb493c3b396de752017f8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c163ea646fdda7ef992efebfd6b287f93e5cc5097f1bd0673ddcc28d26f80d1c42dd2d6d55ec05364425a1c23bb8003c7f45baf7cd0314862802ba131feaf99	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe12b808d66d6fee274df65a0731f66387017511058f2a7f7bbb754e2d13ecba42f3e9d27c7e77f75d6cb795a782dbb04d9135fcaa7b180ae1a499a7463b13e84	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x73c2ddbfb0fe65cb71b65854b64df277b40231760e77e6840dea763e06777701360936e944ba0ff68c7aacebc5ec6f9f9a74a91bd6e8e344b587cb71e29e738f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaca570b4039e3fe8fea206f1eee32725518ab80acf360728f71248939766f0db06f20a737a70da603a1cf5ef43c9d98863c5c792083a3f969ac9b5513b5f6106	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcfb70d4b2eb5d623585e35a512aee9da2a4a91e635496e9ae8d4f0d658b265d72ca12b091937174b2f2630f8d1d10d44c88b67142a45b47721c9d17202a0951d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21132f3b4a26a00835584baa6120dcb82c9b409d51edd3c4f799bf7fb704e8ecf1cc6184de2a83e3c880211f88ea81079a4780ef1b00db7d096f739db3732a79	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6bf075b6e4b179e1a914ae256b661b59894f355f6d3e98582392a5f8b2275d4c865f37ff3d282f1c403b5d98129e4bcae6a26f65159db8e0d0c0bab0488d677	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58712f5d1e40314d71f4fa8b31b7cccbda2b522d62f5decafd9dfae7e5a00a959d56bd1d1fdcf316cbd1890aed45dd81d5c43e39d5cc1f19d41c820957ba0ff6	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xff319d72bd75025b58e81d46d7120aaedfb9ad5745067fac57fedc69cb9bfa6d6ae075b70a3dacb09afee57cc4ac99002b5b4213f87d97981d0e59119c785635	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeafb36d2731a53f5d4987ccc20a25d46099955e4a073c1790f951cb7c6e744d4233b661c4ab8c70d614ef1d10bb1631d03ba23d3a209aa3e75b5f54f4641892d	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e54113a7d7d0fbf815c5c9fc315248730f988d546b024bb56dfad56c5f2863c12660bfade2a1dbe9c112287239664ac9dc22eab93bcada285ac4d072ddec9c1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa5f55221a7af2d278676f9c03f66f9cdc6d528977479cb21c75f54df2791c5ba0dc6451a0a5d1399942545cfa96f1db8d1cae526e5a730c964b6259ba43fb0c9	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xda2da311b05d09789490d08b09bbd943a64f001a384c03ec92a3e32488d55a0a30a47f2f548be4914708e5e53f7b0d46344a8284243670999e71f6c9f963a9f9	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x959d3e13f82935d831152e60259860eed643409351e5b1aba4bf3d8db60d7fd85a2b62c62cfc10969fd7bff2ea57a35c0e009657eb3f1583e87090ac804fa427	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6932e7e0b5b8e034e3b29fc4a8ec38678b2c2327b73f612fe453a7cde09cb66eaa95ed97e860dc98674b8e3f9dd70ccd4d66abb859afb4d0061ca0ac66a4e621	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe4b34e46d05ccbf928b09cff17aad1786d8379cbfc92b781a3af9e4a66f5408dcc2ba2bca9a3b2b6d8e14b04f568b00a97b3bebbb5ddfa04431faee1ccb14224	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27a7dbe9d21a5b3db08f8bc1b96c9d41d8c37589696371adf328cb666676d4182b9ea6d1b111d456496c988ade25e35fa9cd6b2598511ab495b1fe1d988f8e6e	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1b8b5c3f6a9bba13bea6f3cfca54c97597351a5bd4a1363ab20b2927f8cb97836620dc2e99a7fa0dc8da6875ac8141189b5c2c0ac6e647f5f13a4ea03250bbc1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x645d32c6f7ffa83b9d0e1570577647d5288a373604d610ffb7be6c274a2e60383d3c3a34c6e8df9f6f6b4f00db705a5414114b419d8a368e01f8ff2c72309b53	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb32b6ef09f29566de3269e83c01f4a8efd5929647edc058b70044a69d4717b34032e13376a2a35089924552bb32f2ac920d72fc67d8f08a957470871673f8a75	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x46ed28e2a0b80a79b35af02b6b661ad8d43918a9cc726e3d052d998b0e42e6a94331a69c80cac9b45d0b7ca4c0830e556f01e93ddf60b25e3d5d47447bfc7b93	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3ee00beb6dd569fa0fb423405c8377d5898840df27b8b47dd317a8bf3dfb876125971bfad76f436e68c34010907b2727e4d33c96ddb49db93264305f921e6ad1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfa824c76814919d36a6958862b0c2b4afa5824cc48a1fa4537db3e376030a39a40b8cd9c321851a2ac8679b6703ea9d2480249cedea5311963d26ea58a080840	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c454b54fa31e36f3065243a9754fff7cb474fa92aa0e56e46a673ce8c7a7c8e691c9f47891c99b7de018e667265fe63c4fcf9d7eda028c3776e711b61f19f21	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6ab7db634be96eea192b8b4838084403c25c9169a13b73e21bf3601ba1d879a32f944e4e2139e1839e67153dd22cadb0c2609fbd1796b0e1f27c54eea96b8ffa	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0d7fb3d2a5df9f517198c650b15c5c422cd154f14e1dc326a8742f5feaaad8faa6bd54fd33aec25c980c6b55a36440fd888dec9e028698390f8c65db2678defe	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcc7eebf8ce70356c769a4807275a9fee34e438a10aa3801cd53616f153cc511d4701375226aae6881d7f5f90cbdb8548a262f27f1852acf133aa6f7c70414566	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x06a175d16063a2889b31d65d4941a0cc3048d0e6c689397ffcbd2802ca7a61269c2fc068ea4dc66b8a2c3013d911118099de3e1e5454aeb659c38ff861aabddd	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9c503cf0b14db09f60544ed766347fe6a570683eaab5ff4166a64453c45f97874217588fbe3d1ffd9eb2cdec6f2a03efc268ce4901eae4205294806b82653b02	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2d241c0fdb6a30594f7f6ad4753cd57b1e3dc2fa6b1c8efdee4456991657baf195833aa8e7b8a19d103c73502d2f9be6590d34f045a9dfacb74ad5be31c113af	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x978c2a7c6c033ea1d99a29b2fe046a7aa0f5e7812405ea8d3f3092dfaa4f47add5c57cd94bc067f6ae2a7b4c4a9ad9ee8cda140c8604c6c98c046b0371a6e7c8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc1f95e9ce2eec6698c6e929138d2687ab1932dae62aef70a6f35fae69950766715babae160413ed0f812d28099c1ab1d81f252e97b3ef2fa0a721945c0fdfca5	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x162f03c67ee454666c731f6a20b506ba16e378eeeed5a7889355334fd3dcb415a3690570d7c9c1e9dc779458fb5e90097852609bbfaedcd0dbb06d006289aae7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8dd5838c627d3900c0268e5c3f79713ccec0802f197a406fb756904ab4c9a7ac6c85d70129154ca473df3176baaa2dd12f1e515dea8b70ef0d081515461a24e0	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9ea30fc4dbd358503260f6fdaac6d7a090a6a433f6fe9dea8b964237fd7a4d3f8b35b36b8fa9feca1d7e6225be919c685f2225d1a056e7cf7d6eff88230a7cf3	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3322ae18c8494abd0a222da36fb7efab435dcc05f984e28cef12d9a3fff635ecf811663e7b1a142306b9fdb75235fe00d11026b33c868ce818638b464242dc9c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x57defad12775d35f864cbd1eebcffc0bedf5c62b4b444c34402b7a152f8de83a7249fb3ab38cb6aaf69cd846a0f32d4e45661e369f397965fb9bc34f67a23c55	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f9d0abc7d7ae2e037b3992891985a647d91b52d31f5059ba2ae44cabe494129050b16f2773a1ce594744968652138d6ab99ca3bd09b470dbb13b9e1b15e11a8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa35c3d88a5887c2d5b3f6a9d9e790a9c79257e9cd124c9807c955855ac9ba992696a5c983e8f3456419bd3628e3ee63acbcfed3c8edf0ac6a7e56bf602233081	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x91198e87cb3bf23c632e49d67326e64950b1cbb3bdc07d80e3ed63af38fe1eb1de2873034e25a99b863351eb080126867128ac63e8989185edfbda925ed80c05	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b278b652646eefe454fea13817b5780560c064ee74f6319b6422fcec4339bfdd5d29ea18205bc76f771fcf2bc70a1659183617e4f09db97b3245ec2949c39b2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x110aed29c50be40128daf6d45c64c8c7a427a1201b8218ee88679265ebe7ecc47bdbc857a3146d21153f50908fbb1989576b5866032658698520b5ee88ccde13	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c7358946f75caa96af1c3078368cd839c12f562880754e0709808fcf760b666c02463be88533f72294074d72ceabccf64ebfa67e053dcbc94e5a71aabbd6568	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa68e6613da4e4528b170a988bd745930293620e23909b4c00345e13d011bf9ec415560ea141c3cefdb2688cd0d4f41702151361495916a827399caebd11933f1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x050cd6269ad000ac42ef272d4bbb250d7b9d495e286cac5473394974897c0357f6764302de127a09eb26fb98f878e069387dd75fa0f9ba2226a0dffc06cb578f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x086a5635192fe09a80272e6a8530100fff66151ddff895883087f090790cacdc8d256163b0e103b942688feca39063a73be519f62610108b200eedf9f5899bb0	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x555442f20e65ef8100cb10c0fcff33e4fc8e2567d9a1517c615b84b80c187e0b828843dfd483f2117d95c734d4e35b79e36ddbde82a6a39d829c0d98439ca2fd	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc03a86765cb74a5e76f2b7f17913904f4e4565d2e2c88866730c90f24dce8ea6948c3876365eb3f6e73c54eb57b320b97c304d4115200f620bca895ac5689d83	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d3eccd077bd8a4f4a68bf62bec81a39474d82cbf782afe601845d4507b46821ef0067fdf4526f3c5adb251809cee4976a6a36ccf57fe2cf88139d5bd6214b78	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe270a9ddc8cc0985f919e8652b11c5bea1d2c70536e1e060437af023d6347478bfc81132f933f799b369fa1233cf7044f18e487b962aa501ca6b9969e1dd1bfb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdee99497ed3c7b663584ad427b824c60788099d2beaad6ad045f5b2968e60aa80d3e719dedbb5c7d3a715cf5c5099156b130861caf109b7f8807037a61000dff	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8853eb555a65a1f9bc1e702b26224c1b6b97ac17a5412c1dd1f03d9bef2ea63d81cc3d0d210222797908266b7e5102deb087f71ac8ce89a18d5e10d75baba37	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcf0a02954d53acf86c6f6c86d4fbc5f3722b94165cd919a9b6ce17191b2081679a1c3df40a2a39b7531893f42ca75a93b4193b596f05a7ca4a2fa52d79f744b	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x51bb976d20a09ee153fb8a3fa483567e154483123fa7893aba372a3b612f1b2b1d4d3c554cf9dd48c64406a88e156ad0cba0a96446d61d3c1837a5d6aa7c260b	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ca8dada9edd0c3a0ff50242f556ddac6346f93dc19fecad95374ada063f0cd6785c38432ac4a62d3a3acb05817c655ded1b2630161fe3700aaac6bea373c8c2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1a322ed98f880bc12b2b04f29c1fefa35851ef9d2135e6ebbeaaf1e5128a39ae5217a2a15bc463513b8b2a7aca8d8e7004dba02c42707693e7c03938029fa95	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x785eaba4be82a69040d6563b144fe7c0a43983321a9394251a6a1431a514d8738c5ed23ef74106cbc20ab14f8943829c52c3e269ee2fa93e8718d5f11ba6af47	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x748ad3ff1c3ea7aa6c83ce5f88f2175d3c03b919f434b62446d7f6eba27d0043ba87f292cc81fc42747861322e0a85676b9595dacc5d310f6c4c0700c2c6aafd	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c7702acf15581c2de2c933d6c48e3c721bfb851bf2d0298d4f8927c17a03f35be0c7123b6b2b1ccbc961a00c67437c0ac7557b6bd41f6ed5bbd3ff74457bb29	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc772824cf22164bb46be84fb13beb1a98450a169ae9b84e893f486ea124c9a405337060966f4721babb3eff9f453d95605ec23630633804f1183f02e01bced8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bc86f2ce05aed6e3d0799b4223b60de0803d5938887c28b15028d507eaa220f3604053bf284575fe6940035e8081c325181783ca5dc7c583a3bda097e6f91f9	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe479f262b6dac27fe08e1c65af768d7cc69bbcee16322cf4321317982d2fada475faa1c94d571cac79f8f3739be359a17cb9dc1898fbb31950aa186607b74ed8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x81b2a2577c8de30fc7c1e1c27d3d67cf40ad963caf31f74b62d7ba2d3ef165eb9b889946df933e8ada826dc29d5b9bd36046f90bcd6ff80cc9bf866c317bd3e2	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b6fcc2006a3bf804deb840d083ed09cceda22433fe442cc0350f0fc539374e84abbdfbad2088c6e1f784b8892eb642f27d82ce3ea1b01651006f4a1afbaaccb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e78df3fe8e4fbb8995899173950c6bc1a94c6c80ff3d78027e085132bd2249b8c836947088eeb701d3801687a3f6f1381f54deb6d8bd0a9f431d6526a2a5981	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xca8c1220536f355e6638cffda11749008be3b088c0603ada4ea28a82d63b9cb8e0ca3e6471b74f4257fd6a53a1e92f8a64950c0a349f387cd59789ca37e6ba72	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x35e67b7aa07bce99680e5922903556e29a300adbbecdc73188b7ef3a5162ef4a9b577378c1107460f253690ee2a7cea1140d645e14ab97d5644d6e54934a04cb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb022da413895ee9d513be5714edcb34743546203410d2bef30b32cfbd74c3a897a6dc9db9377fdf20648eb08f3cf6a0e2e023f580b6b4a790f877155eb0b621c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1dc3b1df54e059123840d96a98b1dc5d1fdd78915c13499b3daa8480529d67da7f4ecdbe93cfc42600b13ff4455d89b07ca9a7d49b4d484cdb0296a45edbd4c7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d0d491d328f811e04ce4932fe660a6e1aad7e9cada48431b0ea6ef68298f0b04c9a99dee605922d7f0bef403f542dd136df614543ca7fe1a93bacb134f5a9e6	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c665c42ff858a6f4d746caa504cfe58e10a626ae29dbfcfb398f653f85e7b40253f51fbb8fbcea8db07c7a0b00df26cc2af19ece727d404491d5944db6d8897	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0798fe8cf2c9c15bce1349428c5f0583d5a83537f9dc6d02e355762907174a28408ea2565ecce0f4aae3f9afb4937f27a3d6bffc33969a0982e758e914fd3fb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1579868341000000	1642335541000000	1673871541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1fa7dd4f8d5dfd34a1516cbd82f645fd5da0a2689d5833fa68a3de857015bb1068ba3c6c0e89460463188779374678dc5bdfa8334ad934b19c0ba39dea7ded39	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579868041000000	1580472841000000	1642940041000000	1674476041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa130ba3c5d0298b8a041476aebb47e444df56519f5a93b0e719c3c85318fd87d1f26859a879bad66c8015c720e1fdd8493fc86834ff0a20fbf60ea50ee692917	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1580472541000000	1581077341000000	1643544541000000	1675080541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc6beb91683ab02cc269d7c1f089f2c990164279221ea560af7f8e154fa6ccd8acebc05a042cc812f83a807fcf31f5f09a26c6156a24f5426a08ddd93622fbd96	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581077041000000	1581681841000000	1644149041000000	1675685041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe006b7bd70c5998e4542e713ee685898957d3122ffb60e2411bed0cbdaef0cf76639e2a06d31e592fd7de082a02c645efe682d01b6ecac22002e95eb3274c213	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1581681541000000	1582286341000000	1644753541000000	1676289541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5f404c219f859a5aec7bb02fa6261fafacf6dcbf251dae8c20edb4dd1c98e00cb3c37762fa2035074fe9f5e58bdb22597b3d5e7cd71b4340a8b568e70d102388	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582286041000000	1582890841000000	1645358041000000	1676894041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa2ab009a08423ea087181fe42349f0808dc12029ef047772d9b1bbbf2eba564d5d3aab15ce06f41680237689b215820b179b1b3c1663f3403cd15ee631ec58b6	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1582890541000000	1583495341000000	1645962541000000	1677498541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3548ef5457d813750712a6fd8c4d33a0907bfde1b365291f19904861afe485b74066e22c3b2a82f0313e61c1343da0a5378b00f55d776ed3fd60e6a897d432f8	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1583495041000000	1584099841000000	1646567041000000	1678103041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa4dfcf9dde0a4770b058efca53a5ea69d2baf5b36a89cf24083be3d18efa8c082355c41ea5e1c90fb68766d679380c908c6fd08ae0eb7fb29a194f167e460472	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584099541000000	1584704341000000	1647171541000000	1678707541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x137edd6657c191bc03cff6c4b12de910aa1c39a1059a5f3e416d45add1023e29470c405edb39f70417be2023b50300842139fc847aa47e9050df75fc490ccdd1	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1584704041000000	1585308841000000	1647776041000000	1679312041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xacc263ee1aca28794e543b54ff079545367fcae37e05bfe97447837ec0945ea25953dc8f19116bbddf0e39db6f5b31da3412b4337ce859dd758e3dd3a0b868d9	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585308541000000	1585913341000000	1648380541000000	1679916541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0a0ba1a7841cc27a93159c2a37659a32aca05039482ae25f57d7f945085519759b6883b9328456e4e2af1714d361823b99c370a27246da52fd8f4b49f49ef103	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1585913041000000	1586517841000000	1648985041000000	1680521041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xce578f8d0a5012fc8ce67ad8396692f8beef5fc3c3f189fc28f8480df467be454997a6590b8cfd6558da5bfc1228a04f775989aea4b3d87e77d7a22227d7437f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1586517541000000	1587122341000000	1649589541000000	1681125541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66c1eb8aaf02d5e6686d77bbac9cdb24ab873220a557e6c9f7ba145754ed2681219adbbcd14659fd56bca034294bd099c74362dbb5b6ccfa5b85f59fe22e51ee	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587122041000000	1587726841000000	1650194041000000	1681730041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe5b5bd419e593146319c7a851e90a31d3d427dae3d80bbae9e5513acf240fe4a4bbc9f33bf539b0eb14b798046e4ee1009294fbbc4efc6fcf7bf46a0b836c7a7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1587726541000000	1588331341000000	1650798541000000	1682334541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x85cfb6ec685cab17ee75d1ea4c48f802ee3ca892f5ad10d359968073fa36204757797b2f29976b42ac7a15e103d43bb6eb2b831cc29f7e641133394e44818f2f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588331041000000	1588935841000000	1651403041000000	1682939041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeb28e91064d6d0074192cb4addeb232fc1be71e36e2b881bd4c26233fef6539e09812627b5c8e465bdd172744b4552fa14c57453a8dcedd4b29463936f98d5fb	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1588935541000000	1589540341000000	1652007541000000	1683543541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0e83d0f0ba11355f854a68186f0345da01393216059e633d370fb83a66867ac1aaab8f17c7d32d199609918fa199b800e23c97c13ee2f8a8ad99e610395a0924	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1589540041000000	1590144841000000	1652612041000000	1684148041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x38b1f8a40002a3f5a2763fc20d741e8446d6e50e9ffe0baccefbe172a110da30eabdb234399bc28cf6408e3dc9ff53f68f264cf028a18ebdcec47c742cddb96a	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590144541000000	1590749341000000	1653216541000000	1684752541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc181c811e068aa46831dda027516747274018f95899878096d89833e7693321d71786dcd4b103a4566026bf85957e423745e0fe9ec727704c626e718ef5f986c	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1590749041000000	1591353841000000	1653821041000000	1685357041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7b3aa6a365b124405621ad872bc8e76f0a5de901f95a9cbf7bbe295df05ceb85f53016867aec246df79eb6931b3716adf94f3db2c92757b76c1c0d7ad0e80815	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591353541000000	1591958341000000	1654425541000000	1685961541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7b5adce550b25b2c235725b9ad373ea345b4134c29e1eacf662127f0f5851df6482d20d85f524dba2503610dabd005a33792d82d0c404a089b99df9f127bb888	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1591958041000000	1592562841000000	1655030041000000	1686566041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa922a57688d9daf3beea4e1da66f0db61b95d8805c6ff3ccda94a17fb0ae1de2da5309123c26548477ce9bb368d3894a41c04c6b8015b380b9c62a145c16544b	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1592562541000000	1593167341000000	1655634541000000	1687170541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5f1f383b78c6c6283b56925c63ffa5bc402e0b668633b57c6e099a24c2b33ec456438c6e16825340035436e7ef9480d994c22677672e162ad8d9ebc40e4eae2f	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593167041000000	1593771841000000	1656239041000000	1687775041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x23092da52fc6c40c5746613689d0a93c46e914af5eed12afd3f9d3295ed7d10bdb57b0e297085e0c201553dde7e7414541441ff26707d28796a1b3bd9f262d99	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1593771541000000	1594376341000000	1656843541000000	1688379541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa82ef81f4213ac728ba7894b6f05557935fea004f846c32696e317f4dc06421146002e0af1dfb51794d336d83ef0da3fdeb7b220199185b263e0068ad118d122	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594376041000000	1594980841000000	1657448041000000	1688984041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0650ce1458190a68869f2914e4ff1540901dc9a82a1a7c9e189a778fe9df3394f4eeea8c5f9b06b5718f9e64c3821c4ea2a4941d8912deed5f2c9f5267888292	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1594980541000000	1595585341000000	1658052541000000	1689588541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0a31ca72188b7c26e492f255181528e940b20f124c07eb7dc5e7c597f3e745d8924f55305eac3f45c474497b9a2d51360420a8be3cd37f5e5194411540dd9c08	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1595585041000000	1596189841000000	1658657041000000	1690193041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd47143fc4bf24178465adedcfd5309c1dc006c006f01d9ea9f3bf649f81570853c570cca8b6cf96d99c71a073bdfbf283b275bb0fc30c5815f41a5f47a501b82	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596189541000000	1596794341000000	1659261541000000	1690797541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x02bb56b55ff3086fdf648d251e923ac231a46f321248db24be78721f46e2eb946de74cc7520b866bdc140b3fe65f2e49d05b2c58b5dda3cdb5ff32da5bb4d7b7	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1596794041000000	1597398841000000	1659866041000000	1691402041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x79d0d2985b6b70284796c7a12293e38056fe4df108a76341e3c56f06609a548bdd80713cfad3e3401eb96929ad67cada5fcfc8ab30bb5608fa77ed3d342a7b52	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1597398541000000	1598003341000000	1660470541000000	1692006541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x419dce7e76af8c6a04b45948e874879f053db6c36e0e6d0c77972b9e0fd37dbafdaeffcdffe3387b95bf3a20414a6abf14b73106c950062d42160092eff827ac	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598003041000000	1598607841000000	1661075041000000	1692611041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x29393364e18e2189863cba6b627e07394b00c566e5952b1d17aef21a4d6f26226043cb5b578acd526f6afff80f54dab65d9e632fbb18261a2a750fa146d996ce	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1598607541000000	1599212341000000	1661679541000000	1693215541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1579263541000000	1581682741000000	1642335541000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x4bbfb86700174727c23622e200ce0f003ee43ef17d877dd5ac6196699f7a5209183d5508cdcab99a360c8287c4345e3cb12b7a1c96a4aabab336a4526099da0c
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-01-17 13:19:15.998765+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-01-17 13:19:16.153097+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-01-17 13:19:16.287558+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-01-17 13:19:16.409486+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-01-17 13:19:16.526332+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-01-17 13:19:16.643164+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-01-17 13:19:16.759978+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-01-17 13:19:16.876813+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-01-17 13:19:17.441007+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-01-17 13:19:17.995878+01
11	pbkdf2_sha256$180000$GnsOKhrusR3T$izFU7u6Nxpx3hId+HE8bSZ6O8GRHvtHiIUJtfSyj4GI=	\N	f	testuser-a7XHQdqA				f	t	2020-01-17 13:19:21.293578+01
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
\\x0c7358946f75caa96af1c3078368cd839c12f562880754e0709808fcf760b666c02463be88533f72294074d72ceabccf64ebfa67e053dcbc94e5a71aabbd6568	\\x00800003cfa45ae2f5da9234a47aa8a4967a63a8fe9c4a27595e03b3cdab3c9c36c86e09c05999b1e3d1d5c9a6a8b523e49fe8d3e861311abb1a6ee3c4e4e3478b705c1c6b098bdeb4d984e5335082355e65054346e26f652a392a8caf063d53afdde187908464f6e6248671b0b520c74aa95649a139149a87d9f582b466d6cd2f239983010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x3300a666eaa57c2e025aaa283c099eb6de2196816c99e331892922a86b7f8ba9aecc78ec4c0c8be27277a1047bd1abca82e9944c3afdb551401f0e4efc32fe04	1581077041000000	1581681841000000	1644149041000000	1675685041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa68e6613da4e4528b170a988bd745930293620e23909b4c00345e13d011bf9ec415560ea141c3cefdb2688cd0d4f41702151361495916a827399caebd11933f1	\\x00800003ae9ef37e09a7091524f4d8be63f98bad7399c845744ca7a8342013afc15652bd132f1baf08e7f212dbf7cb466d9f4b8620ad64c14c616c53d4300eea7f789895d02c348d8581482508d1baf33aa14aca83068c32be6e2cf268b52e0a78cfec7fc5477b3488e747abae6e22b58fa573dbfc0d7475ff684d164a9753685d324dfb010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x1932fe7ca4f292d65dc22e23a36ed86e12404102eb0b87f7dea8ed00a00e703a23e553791afbc64afb83b804402cac944213ae190731be054a17fb7f2bf2380b	1581681541000000	1582286341000000	1644753541000000	1676289541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x00800003b527327fa2ffd9042c07bea609b1d2750eed5f8b6be1dea53b1d348e9b3e2ef91e4419cae3381439b87ebbe25fa50434a7c87b478d6a194c60503137b74005c1415cf79f608229c22779944ebcecad509f4f1e96437bfe654a9e668860c732725c899e1918d9748a92f6a2252b5404e1f345785478a9ba186f1cb86a6dda9edf010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xec87ccbbf87f01baf91a26c3cd4d5bd1fdd50224bb90cd0254b7e801c1d78b19ed27c467bab0e792cb995c8bd3bda46a5acfc469b0aadb866483ae7d5c71d707	1579263541000000	1579868341000000	1642335541000000	1673871541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x110aed29c50be40128daf6d45c64c8c7a427a1201b8218ee88679265ebe7ecc47bdbc857a3146d21153f50908fbb1989576b5866032658698520b5ee88ccde13	\\x00800003ce106e2bc2dafd21c6db6938c8d1807862adca6e96e9334ae783ae7148ae7f0301db4a0ed673df16c273d764e361fdd5f8f47fa591e905168a4bbf84daae89d489c139cedbd2868724154200412c7e59c8eca98fd4ae9207b189dac080ca9415d4998b62d9549c62ef2fd39a2bf1a41f9480776e66dd2d3523b1865df4dd852d010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x8ddda4e57ad52d93bc746d4106cd6e76c0f23a5c7b80f2bd20231c99f52621f33f998e56cad8c24f73833b9f58ae235e147dfe3cbc2600409b513c8cbec1f504	1580472541000000	1581077341000000	1643544541000000	1675080541000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b278b652646eefe454fea13817b5780560c064ee74f6319b6422fcec4339bfdd5d29ea18205bc76f771fcf2bc70a1659183617e4f09db97b3245ec2949c39b2	\\x008000039414bfeee8dd9509d137943b52e4c49687518fc3350def4880d35c7a612fc63a126e34c7434faad6a7c95cb6032128322a838bc75978510fd4016e928761e3e54a2722fef938f947598b0d5c65ff355dd7876d69e7da786b3924b473f33f67369084a56113eab4f385819af77576499c907317165f7b7b087c03b2202fd8e6e5010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x4478c28b429561dc88b00fdb948156c43b4009d9c313967523123d773262ebe923e1f4f523720b21660fac1b3f7a617fc7428ecc671495416ae5a221c66af70f	1579868041000000	1580472841000000	1642940041000000	1674476041000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaddbbb6022a648ef2205b272c81f5f0bf096cfd5db483ef45a466e91b89127618c690dc0e106bd3acb5830c8f50e5669bf9fd17affd72672caad5f2ed48a9796	\\x00800003d967b80458ab5ceb9366b33f347ee16c3be8e3e6c3bcb4179c5ba9835ee8ae205a59b2fc5ccb979d83212508b9a21eec57792a57db38f0a337af4a7de83c128473cf8fdb130d32003621d8ebdbc6ee0bb8d426c3de1c93e7b8af6ec4b6c5989e7b894d6540d048f05a69899535f402ba2fc29a030008f38915aaa93cc1564839010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x70e7abaee43c964c0222f3ca37434e6cb94c24debe723260f3afc35461ade4024b0603c6b16e6aed1b365e81acc4116a89a8318fb99a78ebbb7912b118ac9a03	1581077041000000	1581681841000000	1644149041000000	1675685041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66bc40622c02a650f9960f4ef5e35cdfc37700fe15ad2df970af9bbe0c027a070b1c6434e019cffcc3f06f2ab7c03c22a0a928fb2f61f6a1904c0493501e45cc	\\x00800003b25c3896b908ccc1cd9426d101361cf2b432764279db25af9d5c6379d47b61b3b2301d29af78dbb71768af62a9e3a08debdb61c0e0b82bbb232e215cc2fd1ab1ad4113aae53c4507976081d58200db2b4a1adcc00934505733a278dcc21f3453d71f3736195ccc3c3162245e847a8b239ee5d433e13ea4c47ea7011011e1d37f010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x62f1f68e08f69f8776ae1d28fc6c959c9d885ef742f92dc4e03451fbdb4004cfac948967886023aaf5988fe9c0d7cd1b3c9e5371cb16072693f463f52b624704	1581681541000000	1582286341000000	1644753541000000	1676289541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe85bbd1a29c89c157ecbe99814a3b79252dcf506447743cadd9974358bd036a9fb3b7b640886310b0e8dff523e2c96af62afeb54c1f43eead3bee99e7fb7a708	\\x00800003de7f91b161d7ba6f42c9d3d0146a21f6371dfc393c370a63ad822dfff94649aa49cdee9710e4f778f06bbad63514d270cbb21e13c1cb0689355c56bb3d9c13d3a8dcd96a16aa5219316824342d73d85f336451071cb57515a812224034992ff5c029d1332cadb6d8f3a63c79e650566ab601618fe2f758896df85b9c7fd1e2dd010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x9a38520e2c60243161f3aa6a7bac4705d3c849a24164c3278e7f103a06ab9636689ad62afcb058bb8419a05117199a3281f27b20f93d8c1e9982013c93001309	1579263541000000	1579868341000000	1642335541000000	1673871541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb9a25d8a53bc26362b5bd77d5b8a2dee4a557f3d39e5499d66eadb014334562e1cce59e49f4edef1900a2c54c66bf3958fa82d6115c84580246379d8721bdb1	\\x00800003aedf024df0f5acbfc6c13385579ff4e6497955b280f59a20018b1a4369f3a3dbafa87016fa6682dbd44a4922a19128dc2a8372f59f35c69dbe5339f8697a0e9192c827940c21d4736fe3179e13bb969c018d2efc9ec8ec7181429d1fa91c7fd465114bdaae5187f78e873ea3fba76e8b2a5c0671aa5c8e025d1c5a78dffaa783010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xf552a88d0a65fc8881a5325fb3bac7225c285892a2fd04de89234c5fcf8a467aca14ea7249afd1db684bc0927b1045b0611722627dc0b35de8e2cae3bb150100	1580472541000000	1581077341000000	1643544541000000	1675080541000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ff43dccab8a6d0aad431b6c1e8fb58980e1178b201e2fcc92e3f3779b38b7386a2242b0fde53355cf409185ea87eb356bad19a906934224667abd583afca542	\\x00800003cae77426049875782796ed07a70a5ba53f8360b9151eb6468697ba5a2e7b5d8bcbf046ca2d4eb3f881a93bd74d1ab0b811e1fe9763674fd8c465d2e9abc78c62fb07cacc97e1284ea7a2fb934a8ba4535584db5c4e0c4e4a98739b5d2f9616326cf6b8d1fd122422a974ae2fe8da90a6778b83edaf4851cea21705d282514855010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xa56a01757d225962b00a0a366c355ac6c6be8aa805a2c5c27a6fdc1d315646381abb3b0130dea616001709052843c9c3ce0e0b112346e2bf10f65ec1e25b2a04	1579868041000000	1580472841000000	1642940041000000	1674476041000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc62ca3bff60fe73178150478cb1ec7f017209895225a0185b4d3ff5da4c21d44e27b358868074b3feecbcda1f3d892b7428b45ed465af77ea1042ca56137b32c	\\x008000039f0a98ec12781e00461114390394861c1350f17c18b661d1c32c8cbcef337f523d3f4e2fb5f098ccf7318c6f863a307b83bfd71d5eb02368959f27a212ee03ae16b57d5266357b4266ebcc46535d86cfaa5b68828beb828ca5cf5265ef894b67939cff37f77abe4181dab5453211d43a3ab816c622ca25f6bd708343bf36b615010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x5b3fca9467dd95b1d36b66766b1836776c3d3de5c0d69ee052e4312d53921db49e2b0540d55a07926e8c835440721baa16da9e922f9aee8e43dcb9030aaded07	1581077041000000	1581681841000000	1644149041000000	1675685041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe92fc6a1cb732eae503494148507291bab1e3c81703ab4a0b42b4d1c57aec4df11e632048cf21946c5f41195e323384bc441052294d1f533662e386e2c4f7f5	\\x00800003cbb8ee5dec81d327f8e27f4e915a5c6946c70b4e66520d54ac06157229aea2633b8334d6c77c6f3b413314a14459af3aa6c5264c4d27df383c3b3c988a7d2a20501a9fcccb443b0ef3ffa0e3443e787dd1014c49f5376139d38544b5730fecfee3b746c84219b83b842593344bcf95cd94e05c14d2cff7c73cdb03934284bdcd010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x182e8b29d96536a70de3146de0c537964e5f950b818a2751354e2beae302b4ae070af47e0f1e1497b9501d0d185d2656f108ab6fd8413a59c58e112e330b0901	1581681541000000	1582286341000000	1644753541000000	1676289541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa290da8ad69402a720bd54a8464112e5b3b0d9862c11a44a9fbfa415b6d86023a0565aa5d213d86df2dc751e3ac37d97e3023089fbbabbb5759bed6e38ebaa1e	\\x00800003bd405c9dab2784bddae5bae63b689600e919eea47e98c298e83dbac6f656276453cdf57716276e348c52a2bcaff7ba8196b07dfc0b4fe4c2416a39a48232d4d92254bafc4e86da48d799593c58ad7bf83f8ef00e6be9ebe7c5fff292727daee3e827169d706af519832e98229a3c297ddc486f31f44e8c10763088a0d6966983010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xa2615e4227bfcdcc3bb1fe9ddacccda961ef5705e35c6f35349432714678caf9922d44d26ce5a5b26235ec5fd77ff8195a5039c2035f5f97d37c1cb6bb15f504	1579263541000000	1579868341000000	1642335541000000	1673871541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x387c0ffe2f32356dbc7131d1ccc734553592783f10f169fe535b39446dbcd6238d7a686421e3708f962f298f294c814dc4fe1fc168a02bd1f9f9ef3d30c87d14	\\x00800003c1a051eb5ff781ca3ea2a079997deaf958ccb24b93a39eb511360efe0594a43f9ae0b6be09e11db5cd44f634a515b69af16c8107984fda99ad90832553c8e518e3c3fb239ebdc28652dc6a2c089ddd6d0c43e3480e2b35029b02e53330ef2ce9ee4bcd56c66069b3a2a15100659301af5d18d74264839333f61f5284d28c8cfd010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x815536b76b070c9963eee2968925d7c7cc32bd8beb68b78b0bd7d2aa58bc3d6cfdf33708b22649e0de8adea4df0799daca382c302ed7fadccecddd672410340f	1580472541000000	1581077341000000	1643544541000000	1675080541000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3e78548edd9872f9a0e3a1e05d0dd1ecce90351238d9983d770a7714bb8adda83458fa3a641f6bb020619afe3eb3fe838de654a9911b4640e1759a2d94ccdd93	\\x00800003b0e68815b0a1aba301b3341a5a4e536e9bc2b112b4f6270c4b6a1fd04cbc1b704105e2c23261d24ff2f5e44b2099ef52e7797f2236b3c104d3b6a981f939cba1777cf238dbcdd7d552d8cc04c2f2f89cf477e4522f7b4cefcf484e05642b2e6e10ce7c2c19268e585b9c4b53031f58a534006ee33413a6fc42b8a3ebcd027737010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xeb5c2278392663cad1c06956cd796dbc493a8807ac148701111a4b23ec2db9a687433b449287e3cad1f27e5a47955f70ce2fdc1ea3a52b0378a08a27fd70a907	1579868041000000	1580472841000000	1642940041000000	1674476041000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbe5ef50b6716c57e24342c36dc247bf6cdf5317b65bf85dbfe1a107f9434e319de923972272389e7affd3812230a8cce101db2c2f883ed8fffff3dd32a48445c	\\x00800003c873aa2abdfacea17be9c4aaaf0f655b11e59af2060939e92c9777a5f7fe3e018cd05108978b2fda19589800df23c3342fa8a3ec5eecc38d0e7ab5d31f75f33cb0e9e8f18160aaea640aa8fbf5ca17464d8ac0948f49613b14d9414c4363cfb875fceb685582d4189b01827c0ea8821b0334382b91ddb0b987a0d090a2d55623010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xb087e77d6a86a4c7618159027442184e52f8fc914e7919bf91f709fb7afd26e56ad114ed55974cf3d1ba954236c63b0aca7667f9d98107b50cb51e5bc3890b0f	1581077041000000	1581681841000000	1644149041000000	1675685041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa9a59de75c88577762431bb5dcdce749d2861ee734cffcc354a166932c68c369a37dba5cfb22bbcf1316c981a8ef2fb00460703e815a2d87d9af7d421eedd076	\\x00800003c0552f18b5969ea093cb9bee288b0126a20b34ade7982351e98d2be7d6c65f20254f9d257f1d3ce93de45e5e3580170c20959d9055a61ab19b738fe0d2d59344bd0a53a5ecf943f8a19e5214bcc0dcd39cfd60b7b37176ae84f5ee322f4ba5da5de9beabcf6f531b359b38f5088ee010ca173aa4e9739889d56f2106e7b68c63010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xc770e61261e36efda52428c7b738823233b9e22d41e1a2dfc5499d275adbcd05573d74c882ee1344ff8e3453f38ac3ec4d41119e2c3a5af36feb50c503446804	1581681541000000	1582286341000000	1644753541000000	1676289541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd1b1cd52b53fd93409562be0eed9bfaaa8933bfc50303e85560ea0df784f471055259bc956118d71df276dd93a4a5185391c010fd75f5fcd9c7035c0c781ce9f	\\x00800003c3a66d8b1bb37535aa216b29d39a0a6d964022c2f84d5b35507bc61fddf1fb60802bb0ff966e122d536653c872a434c3ede992514f7df60f15a2f6afc71e7298a99478f2cdaac14bf0b8f18c28bd062942744ec6cca1f44fea080a5819f3b10737f327a96a8f3a55aeb5b89a4b9395f400ae59689e58c7548de219cdd0a61a07010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xc3a9111d03b8426d7994ab6288bde7c74ee7dca18425f91aba0c7ec7ee2614f17982a008b77033f7f86d3e460786fd0fb3c8907da67ca6d0e26f352fb6b0dd05	1579263541000000	1579868341000000	1642335541000000	1673871541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcbd74869e8498e95c1e846d39bd3e870143ffcfedfc96556d1f401354407c8d58e0d3789b3c400cb8c298375eddcafa58dbeab3659398ea66c10470c391ba978	\\x00800003c850ce42a6b8220f2c363e81ceb07603cc073ae0aa0cf12b692905937ea658bb157697e2ee4df62d076f2b8bad0df66389741885f24efb1aa900293e8cbe5a5a479c648a70c90d30db217989c4bdf2ed8c4e98870f86791fa004dd0406a6599faed39cb8350a7f1ed31eb474a15d762d53c7863173978fbb884e9f5a0f212565010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xb5b015afe1d82f9475cf766600e84501e4af10ed3287817d12dcb3aece4d44ecdbe82ef147342d919ae0a91b975efa373b81a7e64564a4009e2562b15e04d60c	1580472541000000	1581077341000000	1643544541000000	1675080541000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xebdc64eb1fda2dd74539890ae74d9153882399047a1ac2dfbbc32dc9ebbbf1bf8ca8607f06ca1117ed2e0f4766d0f7b9cdc0e37625b5b43fe7da5417363b248b	\\x008000039f79be3b66037b29cc29101cabe9b404222e2c4c590e4430f690226341115182d0dc8f79fff1be3c25c12c5e2958abc49e91c148bc7f7694d088641bb412c4427b67037a304881a0ba0ee25deb239f1f7aafbd105680c16367d008bbe6ef85c612b33dff365fbbf046fa9d5b5ee944bc269f8682c64451cefc20a23044664e4d010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xecb43970c5764a0b902b19819ebf2d9cfdfeeb9011949791ef593232e914427980000380cdac72eac1874660f9160d214483da403e22162ecd97c95f97b4230a	1579868041000000	1580472841000000	1642940041000000	1674476041000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf8f69e59bf452b03ad72b06a683b9e837d39bb04586d0a0699e23c125c036721fbd5e0d5629f9ff60ddff4c62f43d0449007cb15ba0aba68b0d024019457a2fc	\\x00800003df37f6948d09723a0133fbeca0a6fd61c1fbab7ea4d1767ffcec17437f6c01f634db85979757cf63a1b5466947136679bf561e6ae53f1275fc8271ab81d5da544ae161fd18bc6352d7485a1b4e09c1ac34d86f58549c89eb708db0cdae33a4b268f91f8eb88a2c86dd77a5f9a354aec78e0f83d1b5445215fb7bc943fd949b55010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x3bd817e1b6048eeffac9caea38a709e9ff44daf117f8362e0dffb7a572b3cb4f3f1f7dffd992d1e5878c15822805717b49050a75ece1748702cb195dbca0f006	1581077041000000	1581681841000000	1644149041000000	1675685041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xff0627b13deaf549fa7e30e42044ba222268853db6ca301c0858f45acad224d1845dfce6de4f4507276d1d2160946e89d0339ae4cc3a79d3dd0ecacb21c15981	\\x00800003b7edf7e936d8f69202af315194c14629c53e39902b261b5bdd1e948332e5ff707ac05c537a8900e537a58463f9ebbf94634008f99ad0485363d4c8c8cf54efa13e01b8b9a9c977e2218c6a34f398058b81f407667e741dd509591d4a9e4ec41c35a6133e4cef66f1fd7f7cccc1998d204467dca14f238c58ae53e3d67d8d0a59010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x16a734dee34f35908d66a14d47fd4d012b61ae285fe64997906fd9a765065a32abf92e6dcbc2b3aa24dcd639293a802c938884d39010edd94871d5eef434d904	1581681541000000	1582286341000000	1644753541000000	1676289541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf1468346cf1b673f0bbe22b2331aad8efff46f10a6c8012ac2afda2eaa40d525b66ae72cd4ea8eef3fd76233e8dcda14235095fcddeb317d29d63ad0eb619788	\\x0080000393d8329c00a436f8c5d98cdc876c6063c6d9bfa71145a8c40fe749e7111baacaff96b8c4ae018698da719fae49b9e94bdb208be2a54cf4b97b992227109a81cb83617f018997451bb085a7e82aec439e69cea2b78afd1c9c553ccf3dd08864b6bf2d9ee7f9273719b81c11d4668e937bb5ee4003f70c3d8618f04ed43d52132d010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x1071ce27bb48c48ea5cac32676c84326c05820feb3761ea233fdf4dbade4b18f0677128b3e4eb9f9cb0bef452e72ccb943f41dde92e2cc9a7db1ea8125425b08	1579263541000000	1579868341000000	1642335541000000	1673871541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x20170b616b395f3f219a6d53fbff675f0ea22f73fd5c03143cc0cd2ea0f7ef0b0af0b93c59fc6b15ea2887c2705dda28fe3135bb1b36f1949db20defb0374aae	\\x008000039cdd483d59f20e05f5743da4da1af60168c21a02d038f081e9b257836ec36ac1b8d21808e399c3d0e769f6e6a1c51b21b8c028ac65c89c5aa53c2a9fd445b1917722d26af9d372742fd044784b2f3aeb9844761ed4d25a095882d93026723fdb4b4a6cfc1f3042747461e67aff886f5f49b30a0c5ab4c5589dbfd3c63904a639010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x8d470489885e44a48d55d392c22bfec6ebeaeb5e07f1ae47df24a7dc31b58aed5165fe073a3d3b19869ad90dd9bc1ca945d4b275749f1928cbc7a56a7e88a80d	1580472541000000	1581077341000000	1643544541000000	1675080541000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7962d743136c8abec9ff9024fb629513bd5789fa69230ab8d743fb6c4b35c99601a975099dfefb2c3385bf803573cf3a537c62bdd530ffda046e6cfd471ab47	\\x008000039f7810b6fa3eeeb76ecec58b79998bcdb4ee5dcbd6d46f9d5a8bdb4a680865a11d17f312d0d8c97e384af87fd5961c2c5c69c58852b1852e165fd5f8d9778cf4af26549535ed8008ce6e9e5ce4ac8d967eace6642b570a2c7d9aa808b7772b853b84e763983653a990f3195ea1bd80ec55809f6d98686fb96606a75551e06bb3010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x67bf25530b0de46680e077d572f6239ef9354cfaa04f3e23256096fcde6488334ef781adcfbff94c69d441c812dbfce12a0ad83e3cca8609df19e02a576e1309	1579868041000000	1580472841000000	1642940041000000	1674476041000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc6beb91683ab02cc269d7c1f089f2c990164279221ea560af7f8e154fa6ccd8acebc05a042cc812f83a807fcf31f5f09a26c6156a24f5426a08ddd93622fbd96	\\x00800003b0f86af1069313eaab41446420a0e0a9ed59006b14fc65c20859dff7849d2f22edc55aeaf77150faebb7f59a2fefec422fb92ffdb8b782dfcf7e15c02a0170595561d368cc725a995ddea67b4af2916599c089e77dfecee91006cfb3120dceb5cf230ffc6035f89a82dedfa24d036e1e59c6633d7e277a109d3f19b913486429010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x83c2a0a5bf4644b2899d4c624428354ec5a633d0821646ce2b7594fdec82c02825a5ed6ae36c0db6592bda0dc5864a2fbefe13c479b546ee75d104d69d28850c	1581077041000000	1581681841000000	1644149041000000	1675685041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe006b7bd70c5998e4542e713ee685898957d3122ffb60e2411bed0cbdaef0cf76639e2a06d31e592fd7de082a02c645efe682d01b6ecac22002e95eb3274c213	\\x0080000397c45d03897cc3d613cc8407a6a5d4b00ce1c1396331e1d914f600c451a06266320daa0cea270e8a07dbbd6a5a373e785e0082c50a9d496a6fbf3e371aeb51c257a863f2dba43894a56779fc25a569b526994c7c4729b592d4724039431f3f38436b77a725c504278c0c387270e4901eab7a6a136d76f22ae601595dba1b59ed010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xd72f748aa7b7d032d14ccd9ae03d750b59e0eb2dc2f9b74104bbfa9c03b174ccc7a1b3db67bc948b9c154be42edbd2972aa3c6d5626e937bded5d2ab8e39d408	1581681541000000	1582286341000000	1644753541000000	1676289541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x00800003bc5240c4816e7f441a006021d8db28f868ff000c133fe1fb14b02e7c0431a971643253a821e2f806325ed782104cefbe56230320168cd68d069ca576b191713bb94156dc1cb636b639a99615240d8b8e667763e3abc2fd5cd7531d4696ae0d4dda8e065e9004b6602545dc8a8e3786c4bf54380aa6378996af30ea2ae00ec5c9010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xecfb184fea1189bdda45b6ca140325528fd3749d08e5fa055d7ca59da3243ceaa09d5e22439b4e495d4603919bd3a6a685c06598bf73a0eaecde9a3ae29d7d04	1579263541000000	1579868341000000	1642335541000000	1673871541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa130ba3c5d0298b8a041476aebb47e444df56519f5a93b0e719c3c85318fd87d1f26859a879bad66c8015c720e1fdd8493fc86834ff0a20fbf60ea50ee692917	\\x00800003cf436ee5d701cdb9a0cf8b10fa2adaf5e89b94a205b2ca688f382e942a9a758eda64dddc02f39fd28b68086dbc6759e7abcc58d0b1579bd186a4c095514730c204b8e8afd30e7323f2db10f8650457b9279e2221addfa1f7133daa4176342c79e9d58b1a3ac07ab22bce38c76802c33c146c26a0747d6078a38c54b77e2d996d010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x2df567fdbcd929c82c2854f52f6fb7cc0cdff942d276be91be8c4ab91f94ec8019a7ca29ca2db4d1ccfabbb975e51f7bd80841b9f0eca951513807bac4afd800	1580472541000000	1581077341000000	1643544541000000	1675080541000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1fa7dd4f8d5dfd34a1516cbd82f645fd5da0a2689d5833fa68a3de857015bb1068ba3c6c0e89460463188779374678dc5bdfa8334ad934b19c0ba39dea7ded39	\\x00800003b92f89acf69d81dde16ad7a0be2b7757fc311e61b55cf3d71aece253b55736fde72a6e369025dfc87cd1db215b5c73aa1a83b2d66ad5fc6050998f80a981f5e09457887d8bfd11389e7f1b45e7e5da307ce2c646400495f8722cbcb6688c7b785043371da0b9800a96cee5ec8124f52dbecbeef5eff97962a3358aaabee453b1010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xc9444f0545ae5a5c3066eada050f02c9886e296bc54c37f4e2b19c4da0bb076e85464b0f5cb58d439c4448fb124eb12d0d3f2833cdecc70505fddbefc33d200f	1579868041000000	1580472841000000	1642940041000000	1674476041000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5e54113a7d7d0fbf815c5c9fc315248730f988d546b024bb56dfad56c5f2863c12660bfade2a1dbe9c112287239664ac9dc22eab93bcada285ac4d072ddec9c1	\\x00800003b63ac4287b7420c979850f31b62f62a8c81727a8dd70887ed714c22ee60453271583f7f49e7bbbdec390b8778021910c19395fefc688220c91da1919bdcf2fbc6000b9363461c393b636e2b7107b411a9e21441fe2b501cb58ee5b90c03351daeb51654452d6dd7b5ae2bc6ac6ec76a961af1743fb2c31cc6c4f390e2fb70601010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x499a8aad83511d3177a9c687be9647bfb22bd3abf392d8bb97234013c4f84f33964096ba1b81458bdbcd2da38589de674a538efa350228b6bd544f9b08eeaf04	1581077041000000	1581681841000000	1644149041000000	1675685041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa5f55221a7af2d278676f9c03f66f9cdc6d528977479cb21c75f54df2791c5ba0dc6451a0a5d1399942545cfa96f1db8d1cae526e5a730c964b6259ba43fb0c9	\\x00800003c0ccdd91720642794906dff3785baec0a8d483ddb89e702fded4d60c4a8c34e4993f1a0359e4b23829391ca2acfb56aa3e0646ab3f15e4b034c212fdaebde74b2a285261fa185c04f9e7ddb1be1af6d1989a5a4cf8a954b37a3d9119cc70019546298aff0fbd6ea0498501a6ce35ee4f7e3088ca458e15e4154c6dc3a239d893010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xc9540a01beba4dee098ba132f9fecc1b08d22b79ab44454b5a5e21fc241ab62253bcb14923e6e0c97e3d6ab4cb2be1e85d9589a75812e83cfcf103d9796bfa03	1581681541000000	1582286341000000	1644753541000000	1676289541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x58712f5d1e40314d71f4fa8b31b7cccbda2b522d62f5decafd9dfae7e5a00a959d56bd1d1fdcf316cbd1890aed45dd81d5c43e39d5cc1f19d41c820957ba0ff6	\\x00800003d4e83f016fc922adce5850b6945404a21477794475bf027df3e374548fe6a8ec6127f2709b139efe85e3f26df83cad8462e2e8aef2184cdea460d44b9dc1c418a27eab7cc59c8e25f3b5a71232968d5c2d9812279c0cd8da2c4eabbf27767380d46e3504efffbe4916661a2365819c4913cb2ef93d2c8fdf57a3b8d5a14ee009010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x09549fd68de3854e3d3bcd650a91cb395dec8a8c05e5a357f709e7cdad3fa950a3633e1607c82ee615bfd00b8cfd56b61be3652394dfec2b06c476c5470d0c01	1579263541000000	1579868341000000	1642335541000000	1673871541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeafb36d2731a53f5d4987ccc20a25d46099955e4a073c1790f951cb7c6e744d4233b661c4ab8c70d614ef1d10bb1631d03ba23d3a209aa3e75b5f54f4641892d	\\x00800003cc9e36030434e82a818c94f39d07135170e3f83f20a55f7bc779b264046a061b0413fe4928de004bac9f2c4a2423e758088d330881edc6c77a749929ee4270361fb939fac8b9df9a86d04fd78ec3630d7c85d15a81c29797dd23847dc48a76686ed04a2af5ed013c05dcfa94573071d8ba0a695e3367f2b0df6c8abf65007989010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x7010cffef7e8be6e4a7e852b3e78304b41ae4b82ee3e757d16ea8b984f98fbe5c542b704f1a40cb87c04634692c9ec354614a4214364590360dc7c247d011807	1580472541000000	1581077341000000	1643544541000000	1675080541000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xff319d72bd75025b58e81d46d7120aaedfb9ad5745067fac57fedc69cb9bfa6d6ae075b70a3dacb09afee57cc4ac99002b5b4213f87d97981d0e59119c785635	\\x00800003b067eac9c7d84d6e9446925c214f887999baafd0a5d0bcb95241e0b2f30c10211afc51b7e3574dbbef1bac6059c92d2044357f294fb395b6e0e4bf9830c0c3cec32cd37fd89bf90345006e81547821afdac2439b88506fa093fecda5c676c64e97db3d24562e91efe8bc38d788c2effd2716ba77640ff67cfbc574a6c1b2f875010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x125ffaeb71c4a2f0df917cc388cebd8b5d77e38c5cb10376e13bd53ed5c84d9cc09cdfb64b21bae0548f35cdc3dbdbf93ce904e73c0b063e574f0ac76c3c7e0c	1579868041000000	1580472841000000	1642940041000000	1674476041000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e414a6d314d31eaa74d67264143a4d7633262e2c359d12f2b233587bbef02a9bc2be9892b5136274c6ebb13eb82c8206009ecc8dfe3fd1415b6f56230e3a57d	\\x00800003ec53db9dfe31dc74078f75e64ab4a488c7feab87720b3d34951f6f07cc87f067778f48a368ebe606051f599b194da162175f56121e3d355b27236601a98d15f15b133b98713527b08845788b61eeeaf0194c921bf2e4136b494b7678daa17eecdcc7661417746c1f238e8b5a6cc2def0684c7fd78b5b6b4b54ee43cdb9316f07010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xf3917f1a3753e27b8982f181be6bb73ed16441423bbeff87435e91c5c4c29af04623ee0063bf834699e401bb14874b7bc7e52b1e22cb2e12380ff74ec30f4604	1581077041000000	1581681841000000	1644149041000000	1675685041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f3b11f0a6ac1c424e5bebb9f8384a8961cfd156f1ace63be4de389832160c181f3d8ea4b9d62fc11fe5af3ac12cb23d1ad3e0ca86986ad1b5afccabfaddaf44	\\x00800003d065b7dc3a79a088535c0000209fce1a7d33656c37b62ae16b8a39bf7497d197262510ba0770cdeb7a9e73ce0c22d7cd4be88e9c50863dcb2b43ba51c1c9c122343b3f385bbb0cee79690dcc6238ba87fde22754811f327a338e81d8100667ff3a7e39badca9dbbcc10f7f778f0c360baeddee06992853b6c5155705f6fe0f63010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x0ad4bbfa35f972c3cac0a81cab4717a5a9c2e84eca5364f6bf2e7455284306aedf037493a40f5a339e74d9c409edf56026da62af3c724b48e9b846cfb8a97701	1581681541000000	1582286341000000	1644753541000000	1676289541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed2214657088da594b799437eaf4ecd0566f2f85df16144997cf65a0d8da187d6631e03541de5cf892cbb6626598fe729ad2d6da4ce2667912f7ae371cac6788	\\x00800003d3cc34f2245308046bc0cbde6fbcd0b0fc8d71592ab74da8be8fba7f8d1d187adb2be26135c1c153705641f4fca966916ded343103c3238cbb930525b9563b510e85e6fc45ef17d10ceb72cd40a4e3732ef999563f9407e17a91f46d20b2cb072d4695797a2e665555dee48c737d1f82d2173077dd52cb6d28130a28d4af6ba5010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\x96e62e3af09b66dbe41aeb452ab5c15900433be71c69beab4bafc930f5d7a2b0ac13dfaefff1a17a74f6edbb390a03b37f3b7b867a05ad56d9710fc82fc5690f	1579263541000000	1579868341000000	1642335541000000	1673871541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa51a74c621299c19c907ac77430a2a14d5c55e941311c516cbe9849bed5f4d32bd1355bd381babb808f1c06e0a11017743b2c510597e6bbabb989ae750e57bdf	\\x00800003e69ec34342f6ae56d00c6e7a5acc39a3f1cf31e57e0f61a6c8211264ad84828bf7df6f47d834a0dadf4f8ff15451e18e2f6852c0e739a60b0a7b0d8481b8603c308e1190a61af3a8eec3e4803b18f677aeb310d44d944b49e89ca2ca6f6c796bbc5d6472b141c734b503bc0570bf231ec4a8b87f2c6aad63a58254135e982aad010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xbe57ebb60e3a1d1a8c0da957db21885f3e938007aeca1c3bea05658a41ca27581be8c7453990bfc385f2db2425ccb1346d819d76b9b80450afb0f0f5b3aed100	1580472541000000	1581077341000000	1643544541000000	1675080541000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae502a72e8ca3c4369fc745c499e3e5c41c5a81d266891ebe817706e0945d63937fe037905ca77251bb932d842c0019422f68eb0c242a4f61931998af92c034c	\\x00800003e4de4a2cafd9031f04e81aa6991967d2c65f72c4e68b9e266ce8d7460c29c5bfb899866f08c7b9f9a7db9b70ffadef75ceaee6970396040f78b237c01a671fd0b2addece16b8de05022d3d38f3127f3cede4b8a05aecc144cbf5ba9c92027e454e789f1e8a12d5d75176bb3ce4123cb39cf3c77dd1493d990e446444a0babf37010001	\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xbe7343cd504681f251ad2201d8109bb4a91e50419322f0e11743d3c556ec1f0ba69a917676e5061d958676bf9ac016d2525106d9b303fe013047730772bd370b	1579868041000000	1580472841000000	1642940041000000	1674476041000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	1	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\xc8cbd85f3063714686b1514193a3f0cf4918b4e63b72bce1c4931bdc4939314d	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x3193a79600b77faa64671f7d99cda5fd4a06fa18d4d153e11ffde31757218d0634f515645c416a2098f4066cbea394e039b6e837fb8e881bd89725877d0ca60b	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f00004083fe48497f00009762225d497f00004300fe48497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	2	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\x30743e5a7ea6cad925adbc93287fab1ae74b033cde5973e9b35848545f17ab3b	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\xf400810e2cb6415304cc6fb1262ef496735d298dfff42abd92c67e80892bd5451ecfd00f49bd86f7510cabfff07b38e67af1b180140d94f9f77069e42def790a	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f000040737e48497f00009762225d497f000043007e48497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	3	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\x3b77f75dad20bd325884ec6ed232afcc1c6720347a5051745a10ad3f10a18770	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x57f5c95289e0a16d7996b7ce3763a661fbe20e65e4fccf95c474389408b6ae969c051f61aed2463cc23817db4b2e5b6928eb0a091b34cc84a8f8585c64ac0909	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f00004023ff4d497f00009762225d497f00004300ff4d497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	4	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\x01c2245f1db04d78f74e0fa01a4d6470e22742d1ec8bce96373736f567502fd1	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x8a9a171c0ad50441ee1eeb5db0ee64d7dd22fd5ff192a3e8f152e7797cce20fd31e410f656cd1c4716a65eeffcd4c622a122a97cb1f954eb4a974d92bcb5a803	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f000040137f4d497f00009762225d497f000043007f4d497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	5	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\x32f701d5f46774130103bfd5805bcc692aaf1353ef2ee93221752f3fd29dbce4	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x673265e0a8327a69960860b8983b40c7a24d7b342d31c88b5a9830e8e8a4bc373ec3d776fb96de986d7746548e45472494c79f1c043dc1c574c37ead3926e808	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f000040537f4f497f00009762225d497f000043007f4f497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	6	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\xa814dee2d9ef114a49e0ab908146ffd1c09658f1f16ad9d21bf46ed5d71266d1	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x6fa773584ac240b506c6fd788a2c7b26b476d43b74d6d52ab119cd99106bed6261ac79910e09f5d32c6fc2d5a7a3d6f1fd4a03c933d44ae2aecb7c684c766a09	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f00004043ff4e497f00009762225d497f00004300ff4e497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	7	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\x9715948f261d04933582a23df40621d88a9f28ea9122489ab48a03b34de1b0c9	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x7a8c95d428103e2b3e4c43c7ad1ad9db1dd79c295c5a4f7155f7e421aa89553900147124eb2734b4c0a16f5f3cbb00c5b9fedac49e4aaf7ff557a41e36f9850e	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f000040a3ff51497f00009762225d497f00004300ff51497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	8	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	0	9000000	\\x89c3cf1dbb44465b55c53386f1925f6ab35e4f44aca0f3233db317188bc5a4a7	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x896c984c6c1b3aa74ce4d120a5901d733924261354d0252d8209c31e2b3e2250120e75ff3122e7927fa6cdf71f2886c1d4682e3a577494b8bc3e290abf829a00	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f00004023ff4d497f00009762225d497f00004300ff4d497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	9	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	1579263562000000	1579264462000000	3	18000000	\\x35c0607d6af459ad2620cd9deadbcf791ee212808d4bf3542df0ccc5fa59d906	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x83a663c9efb347bc4333042f86627cca223f9e498fb91492c96929e98d1445b53f10ce9766b9fc1307f90e286d67e7b24a331bc10514e2c3a019ddafad38d608	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x73cc375d497f000040a3ff51497f00009762225d497f00004300ff51497f00006f61225d497f00004c435f4d455353414745532f676e756e65742e6d6f000000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\xc8cbd85f3063714686b1514193a3f0cf4918b4e63b72bce1c4931bdc4939314d	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\x5b40474e2393e8fdc21d8ad599470d9c4d867793d613a1ce9d2387ae39515e512036a10b00594d04b9e74b091585dd19643a1821e5df5d965ac6c987d958fd03	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
2	\\x9715948f261d04933582a23df40621d88a9f28ea9122489ab48a03b34de1b0c9	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\x2529eb464cb7f89643ca56ac2c1773103bc314ce12cc8f43d9e0771aca4c190424a4432181561517015a4da8a77a5fe1b0debc928370b340270d310f61c01508	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
3	\\x3b77f75dad20bd325884ec6ed232afcc1c6720347a5051745a10ad3f10a18770	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\x7c2bc27d078c56dfd0714afe1ad1b674f9f7e2fd5ef183e13d45bfb4804068f4c25a10508a853ab96e23b46fde76d2db5a15fae7ed91d7a6bba934d93f4c0004	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
4	\\x89c3cf1dbb44465b55c53386f1925f6ab35e4f44aca0f3233db317188bc5a4a7	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\xf7e6b64f4cddffd0b8fd0d901e14336c73033619cd1d18d1da0735361b48cd98fe79e60f0b4adf274f08aef345914d66d9a290d3707f22787f2f0cc1d11c5e09	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
5	\\xa814dee2d9ef114a49e0ab908146ffd1c09658f1f16ad9d21bf46ed5d71266d1	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\x22e959162094677ecda2fbe0d15af5e7f975d8df40dca3f6e209a1f4420c08025d17ff0d3304ff1ce15a7a61c068a9146d27edea74f2d78b2ac06488b8d89909	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
6	\\x01c2245f1db04d78f74e0fa01a4d6470e22742d1ec8bce96373736f567502fd1	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\xe892521d4aedb082823da9eb9eab4f54becdf0c6f6270162773f18161eb37ea0550c865bffb521e0a5a1e60a22f35cbda5ce04a9a8cb8916511cd7799c9abf04	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
7	\\x30743e5a7ea6cad925adbc93287fab1ae74b033cde5973e9b35848545f17ab3b	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\x8d324f0dcc024c1667b7908eba0bfdcb6dc0470284f05249edbc01f0f02c64de2808bac5911e598765780ebf6d5ffe6273ba8ac50909bd2e2f079865f67b030e	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
8	\\x32f701d5f46774130103bfd5805bcc692aaf1353ef2ee93221752f3fd29dbce4	0	10000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\x951af75f6cae08a1395c4e6840a39855d1ed33eaa7232a0ba7555ff6c8d13fb7ed4afba1f820bda2a3e940bdd66e7049bf2f063d8fe74e72a67463cf4929cf05	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
9	\\x35c0607d6af459ad2620cd9deadbcf791ee212808d4bf3542df0ccc5fa59d906	3	20000000	1579263562000000	1579264462000000	1579264462000000	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x1c7f8a118538aea0a8a1753f1f1a1b7e76178e586e05cb586ddba3d65558571c243bae514bdaf8095cbb63e49f8cc0fec24995fbfa35fd037c4fbaae1f84c3d8	\\xe71914ec7d2d3e171057e5fdf372417ccdcd2c7678ccef8366bfb0b2d9be59112287dad2b048618b27c1fa7156b418c80e2979ae060d14946086aba71aaa2500	{"url":"payto://x-taler-bank/localhost/42","salt":"DK0P9H4A8SB07TW8C9ZJG24MT0XYG690023VHHH1YB87F6XV9971102P4KFHGA8G6E0WQZH2SNZ4G2DN8DZ8N1A3QV2SQ5W27JN2J4G"}	f	f
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
1	contenttypes	0001_initial	2020-01-17 13:19:15.496017+01
2	auth	0001_initial	2020-01-17 13:19:15.564819+01
3	app	0001_initial	2020-01-17 13:19:15.732048+01
4	contenttypes	0002_remove_content_type_name	2020-01-17 13:19:15.778535+01
5	auth	0002_alter_permission_name_max_length	2020-01-17 13:19:15.783809+01
6	auth	0003_alter_user_email_max_length	2020-01-17 13:19:15.795015+01
7	auth	0004_alter_user_username_opts	2020-01-17 13:19:15.804823+01
8	auth	0005_alter_user_last_login_null	2020-01-17 13:19:15.814398+01
9	auth	0006_require_contenttypes_0002	2020-01-17 13:19:15.816546+01
10	auth	0007_alter_validators_add_error_messages	2020-01-17 13:19:15.824325+01
11	auth	0008_alter_user_username_max_length	2020-01-17 13:19:15.845283+01
12	auth	0009_alter_user_last_name_max_length	2020-01-17 13:19:15.855723+01
13	auth	0010_alter_group_name_max_length	2020-01-17 13:19:15.864479+01
14	auth	0011_update_proxy_permissions	2020-01-17 13:19:15.873901+01
15	sessions	0001_initial	2020-01-17 13:19:15.891358+01
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
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x9e09eb05e59719de7012db770bd62be7fc5b8a048e34ff1804173cff398a57361e07f7ab96cbf5899d887319255a3499155bd294edf159fd62a24984c3ee6c0b
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x6d221d34c199bb9249bf1b1835e7801d05b5b9eb865135d984110174c976c706ccf53da6172ea73fb2ff14bbb5352c00487f8455f164b5a54e5a4584e18e9b03
\\x128eb0cf990fab885dc96525df88beb5358db52a551cde372c5da8dd006bd3e7	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x4d6ed667948854ea6323d2186218e7399610f7fe55a84731be52ed753aa5ea3afdd1694f5d3f219bdda2c650940f808c40a6714d920f015fadb87a0d45c2450e
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x9715948f261d04933582a23df40621d88a9f28ea9122489ab48a03b34de1b0c9	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x734ccde1c2061f822461cc07bd52944139ea66fb4a2f49d693e138afbc620bdf869078feeb914c1dc3aa7370c7b542cbc73c5d82474854d8bd1d842a7c83fbe8778ebe6754218764160faec920de2b9c660f1eb420adb48ed8a93c0bf9a0c9a37f9bea56e1cf61e12f672ebedce83f22c8ac575cbab5bbb008479d18fd55e77a
\\x01c2245f1db04d78f74e0fa01a4d6470e22742d1ec8bce96373736f567502fd1	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x823d68f63edd7a4d92e1d06187232f469d89e89e2dd5ee74862b0f1a821206e5a21ba6b964d9b14acd979b8bc049eb46516aca68c40c31300b27284105e01a10b00aef7b752d393b65299fd8fc0ac3f3b160fb736d7e57246132920787e572928a44bb6df04d69a2354822493771f0cd1da808dd06a3035decc509caa9770f41
\\xc8cbd85f3063714686b1514193a3f0cf4918b4e63b72bce1c4931bdc4939314d	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x24c050518456468bc7cad39bbf95b1a5a1f8cb1283c28a9f952183174a94bb67986bd22bfc0fc768ec5b479264beb546a37544accf33bb1a7df40da74e23c6f57de204da1ae0823d520e2cd52e0dfe10a1ca41e9cd6ec88745515d2c0b94fde8761f3988234796a8cbd4a5e74e2bb6011397a5688ccb988404d9674866dca5e8
\\x89c3cf1dbb44465b55c53386f1925f6ab35e4f44aca0f3233db317188bc5a4a7	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x69257ac8421a1f1ec849c8fe215c3cc2c8367ce062382b9cf5cb05d7249d1e590d3ccc6f9eae811fbb65ad5aa672dd92ef47463b151a4e31c976aad2a0d6d76f31e8c70640c055b0d43e23539e23f4370670c119a115153b42791e1739307991b5168ebdacd3ced60c11b12fd8c585b071f98eea17b8a2103889fa9313768a96
\\x3b77f75dad20bd325884ec6ed232afcc1c6720347a5051745a10ad3f10a18770	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x3bf6bb0933bef3488ff6d76802841ffbc4f2f4d695b9d0a67bd21fd46207dc3c8a83d3c71d4ccb7cfb074e846cd482787c1e154239e8078caa41e59d400ddc66341b46fa60bf18cdc9bbcf6c7ebfb46a5c41e9675cd2d4e915bd73f3dd2ccc9134cfe1ff547d17e5706103bb4c0bc3e2ffa4a57f845dde8f34a402856e550667
\\xa814dee2d9ef114a49e0ab908146ffd1c09658f1f16ad9d21bf46ed5d71266d1	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x751b21b7c127a8586bc98ea270e4f6e68bd87f173997e273a0dddefc3e78c7cfdd06ee246d061fd065aaa752f2a87e378fe09f1f40048ac1d8c6d58b28bb8b13270064a952a3b8fff5a432977a7a2d23b2e2c173578e191ef256c9a7ec15c0ce6bc4f9c3106a80cd680a68f9912a87b5bbaea063adb88c087b87dd22514c4f63
\\x32f701d5f46774130103bfd5805bcc692aaf1353ef2ee93221752f3fd29dbce4	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x9e150cdb04e9f429b8da0c365ff65ffeb106a2e6a33c428a51ae5efbb492566b043d0eb3ffb8929ddf2a4cce0c4d5a8239e84121dc77c7bee0679170f5af3bca32ea0eff8751278ae7921aae246a3f0f4fa17f86f3d502fbfe045e6a0a022dba85fbe8b68e5de9cec79362e717f790d0c9d544465c8006cdae3f4d74b0410713
\\x30743e5a7ea6cad925adbc93287fab1ae74b033cde5973e9b35848545f17ab3b	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x32752586f141fea0fadbe6532490b1c13788a7019e054637099b1d49bdc774cc476063534ca23fd9e243492c4b44a7d5a82e930b314e6cede00da4d0c6e85e7ae84eccf34785b0aba2fe008061a80ad378f6aec2e0c317fa944e4142a7261dde8cce031f2076c6ca35a487abc3c67ec15994f4cfa9cec37ae7d9b07306985bc0
\\x35c0607d6af459ad2620cd9deadbcf791ee212808d4bf3542df0ccc5fa59d906	\\xd1b1cd52b53fd93409562be0eed9bfaaa8933bfc50303e85560ea0df784f471055259bc956118d71df276dd93a4a5185391c010fd75f5fcd9c7035c0c781ce9f	\\x6a2948fb97a5eb2b145f475562c708dc849e91844f3b8bf510e5b6148ae6c8fcc08c510cc1a98bd48198cea3820ea4c347f199ccc89d93d85111dd02879a93df38a8b724830eec89178d5688c3d1eb8176eb4a3e7493c3945228e2dddf00149f43d504922386325fc980aee4b2a98c5b4edbcfe8c1b3f215bfc9d4e759c4338b
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.017-02CFBMKASHX6J	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393236343436323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393236343436323030307d2c226f726465725f6964223a22323032302e3031372d30324346424d4b41534858364a222c2274696d657374616d70223a7b22745f6d73223a313537393236333536323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393334393936323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2232413742314b575331594e5247514539434d4a585a323559504d545256443941414d45445744534342504d445430334254464b47227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2233485a524d3443353732514131413531454d5a48593647564653563146334a52445232575050334456454858434e41524157453238455845413535584e593039424a58503753345a484b304658474a394a51585a4d444658304459345a454e4533593243375030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224834574737324636515251455130483834423853395345535943303651364b394236383633314858364656474b42383939355747222c226e6f6e6365223a2238393358594a38524b514a35545139545236385a593657385a505446525135423842564837434d4b444248444554435856595347227d	\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	1579263562000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\xc8cbd85f3063714686b1514193a3f0cf4918b4e63b72bce1c4931bdc4939314d	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22363639544635473050585a544d533337335859534b4b44355a4e353044594752544b384e3752385a5a514848454e5331484d33333958384e43484534325448304b335430435635594d454145304544505830565a51334d383346433945394337464d3641433252222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x01c2245f1db04d78f74e0fa01a4d6470e22742d1ec8bce96373736f567502fd1	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224841443145373041544d3234335647595844455631564b34545a454a355a415a593639413754374841424b514a5a36453433594b33533047595342435437323732544b3558565a57544b3332353839324e3559423359414d58443539454b434a514a5454473052222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x30743e5a7ea6cad925adbc93287fab1ae74b033cde5973e9b35848545f17ab3b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2259473038323348435053304e363136434459524a4342514d4a53534e544143445a5a54324e46434a52535a3831323942544e3248584b5947315834565631515141343641515a5a474643574543595148503630313833434d5a37565130544634355151514a3247222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x32f701d5f46774130103bfd5805bcc692aaf1353ef2ee93221752f3fd29dbce4	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224357533642523538363958364b3547384332573947455430525948345459534d354d5257483254544b305245485435345147564b584759514556585344514d52444e564d434e3445384e334a393536374b57453038464531524e5443365a4e4437344b45473230222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x3b77f75dad20bd325884ec6ed232afcc1c6720347a5051745a10ad3f10a18770	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22415a54574a4d4d395732475054594350505a3733455258364337585934334b35574b59435a35453445475739383235504e5442395231385a43365144344848575238573146505442355344504a4137423138344850443643474a4d4647503257434a50304a3238222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x89c3cf1dbb44465b55c53386f1925f6ab35e4f44aca0f3233db317188bc5a4a7	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2248355039474b334333435841454b373454344741423430584543574a3839474b414b38324142433231373148574153593439383134334b4e5a57524a3553574a46594b435658525a35323343334e3338355258354558344d5132593357413841515931394d3030222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x9715948f261d04933582a23df40621d88a9f28ea9122489ab48a03b34de1b0c9	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2246413639424e313832305a3250464a4338463354543650535643455846373139424844345957414e595a4a3233414d39414d574730353348344b4e4a4544354d5232475059515357514330434245465956423239574a4e46465a544e4639305936565752413347222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\xa814dee2d9ef114a49e0ab908146ffd1c09658f1f16ad9d21bf46ed5d71266d1	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2244594b513650324152393042413150365a4e57384d42335634545437444e3156454b424441414e48333736534a343342584e4836334233534a3437304b58454b35485157354e44374d464246335a41413046344b374e324157415143505a3338394856364d3238222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\\x009090afe6cf7749f6d167d4a86b05344eabfe5b328b8f2b08c26f9999fe61f7b752ebed0e5a6240bbb15a4b4170a00e11cf15063a18bf3f447c6c2b294dbd1a	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x35c0607d6af459ad2620cd9deadbcf791ee212808d4bf3542df0ccc5fa59d906	http://localhost:8081/	3	20000000	0	2000000	0	4000000	0	1000000	\\xc46f143d919760000f1a8c6044cbf84ed2ba1310b02635725fe0ead25271fbab	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2247454b36374a4646504433565247534b3047515243524b57533848335a374a39485957483934503944344d594b33384d3850544b593436454a584b424b5a304b305a574757413344435a4b56344a484b3346304741353732524547314b5144464e4d5744433230222c22707562223a2252485148384643484a5847303033525448484734394a5a52395639424d34524750304b3341574a5a57334e44344d4b485a454e47227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.017-02CFBMKASHX6J	\\x89390389e6be2eeb822822d194e5d9f3006b9a69599061863d33f709ad094979	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c22726566756e645f646561646c696e65223a7b22745f6d73223a313537393236343436323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313537393236343436323030307d2c226f726465725f6964223a22323032302e3031372d30324346424d4b41534858364a222c2274696d657374616d70223a7b22745f6d73223a313537393236333536323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313537393334393936323030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2232413742314b575331594e5247514539434d4a585a323559504d545256443941414d45445744534342504d445430334254464b47227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2233485a524d3443353732514131413531454d5a48593647564653563146334a52445232575050334456454858434e41524157453238455845413535584e593039424a58503753345a484b304658474a394a51585a4d444658304459345a454e4533593243375030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224834574737324636515251455130483834423853395345535943303651364b394236383633314858364656474b42383939355747227d	1579263562000000
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
1	\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	\\x35c0607d6af459ad2620cd9deadbcf791ee212808d4bf3542df0ccc5fa59d906	\\xefecad167b93b1f4606b460ddb58cca3c6ed8dc96e3420b8421fa1b6e1497501aa65c51e344da4cdd4d2150e442eb0db27291c3d304ff2a8005a7cfe2c723903	4	80000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	0	\\xf4bcfbb204625e6bc567252792af936ebd9ec42d2cfcf5d3c22697796ead2d54523b473fe51ca6e043c353248f7c5e6e43319fbb87e42e2db676edfeed767e0b	\\xa290da8ad69402a720bd54a8464112e5b3b0d9862c11a44a9fbfa415b6d86023a0565aa5d213d86df2dc751e3ac37d97e3023089fbbabbb5759bed6e38ebaa1e	\\x3d0410a330ead965e83aeee957ff35680a433f71dcc2afc5099d1ca7eb81c5964e35ccd3a1ea9e4b4f1ec2c3d28a918a34e7cbb9f577934c99c569a552f44a676f43f0df6373a8a2575ac943122554ad63ca7b996df4bbfea4b851f16184be51bfb53c44d67963401ff67babf13f8319877586fbe26a9a426f42285bb2240e9d	\\xb4f4708e982824b86407a9fcbf1840c48aac0d98c0e78e1fb72023a6ee9bddd29c9f39965f2034f7f2e046ed113161d54b2ddcc263be504dfd7828b3895f4ae4	\\x1c6f5733810423bd8f3b185c18e873d48c36682101ce7935b8008e776b9734eedb73c775cb848474c9637fa9cd595e4476eb3c122f198cf5e55be1b747b27aadd9ac16d1c1edd161346ce952f4c4769ed8ed8474f39111c6dda621cfec6236484e02960c0ca6f54123596b4577a7b2a4a46e0980b5599cb8bec50dbd2d69df72
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	1	\\x2d9097afb70fe8b9215057998ac6eb011f78098aa2bb6771fd8f1da8f3dbeb38d598a747943b38db40cf9190034da71691e9b39392fce41429ba382387b08d03	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\xa32dbf7600a0211f3b0eb2c663498b569154dcab7a490c7c3651a225badb8cb70ab1ad032bf76deebf249257f92de46707b2b8554b1048dc6cef3b630dc22c3c40d0af814fe4e89bc5d1cba412586ee4ee1785308c56f97b1e345f11bb614f31fe5e36f43f1b1d4145499859f6c9da5d87224a176bb33e92a4ddd0bd1b9bbb8e	\\x21593bece19bd8c072a197f5345bf7a8d941b20c08ed2189b2f47422543ed4cadf83d3a58267cb91156be3e7787cb157d45e234f6ccb8fecbc70f6ff32a89103	\\x6020509fd46362beadfd73c4e35c6316eb9463b51c545215e9651e5135d2d26e27fab1f2045c32f531c5e3ac6a2529ea9c1a26a2f1540ed355f243fa943b5a3b93e676ace2ff3baa073af5f031f83d5658ffa64b6d7ba74532e22dac09a57acf43b2d7aac11b8b46333e3aae5cce7aa3e9c349b4cca1d345da390c44f0399017
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	2	\\x1d9d94ddb43159616153c50e9d57e4054ed7689e62f9341be3b5957179f7e5a66469caf129ef32ff84608dfb3cd17c4bb4c7062da3deb6cea2df56315c87f20b	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x6f8b56549f95010722d3ad03fb934fba9489fda88597dfebdcea57ebd24640d6a4f9d4b21c81fd3496c3a3284e7e86c8058752476929d58d03698fa33c9f7b87bb60648fcadd4ac6303152e118dc12e650bfd729cf1ed4371017d164d9355ecf8c622b1aa286d1d9002796293a13e7e8a6ee479cfb341b1041119ee93ab716e2	\\xbe641b98d94cd39aeb14791d5827a7a5bd42b6d35a18fc303128ce898a4981e4ad546ba23e8a8cd948516ba8585e5a6cdb3f6e381ea13c288580bd6d6cdde98e	\\x14baec311ca6b8e21d6c2ca89c6f0c624c278bccfac2e46ec2687d65d78e37f8d404e3cd700d1b4d5b59c40583478ac55be607e010046be7dc60208e0c24c548ce7785de70e7feccda7f5d727f199fe78b061f844b375e8157bf6d2023bd44e6f0e7ee1e9672624c57074b7c559df08bd49405bb1dc036888607c8de5d5516c3
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	3	\\x53d2264f7defcec32e9bed35a1cd308201edba5672abd38caad0f477202e77728dea97b0e955309fce276255ea8fa6ee7d1d224168aa72b821f0c92541c3bf07	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x1f974439a6c3a30e2c6ee2cb1d26d443d66c0601107179e6be9a29475f6ba009e2393695a4a8b6fba214c45cac8bd7dc706a2cd54b34bcf97f2953e18962746944e9c4bfde0815f4aa3b4da6d99874e9ccd9fd96bc55471ea11bfa380c7722481d66f46f83853cda67e080bd8c6fa7d70b81111bfab141b186ce0f809ebc1e88	\\x3eddd407b9e2170efa412c7846a82068fc0a340b44a07cd7fcb61bb044c9d92b7ecdd2f43b6c90790e3c79b2d9c8bbb6b66fdcb9a1a2f48bb789b36e416bfa39	\\x80e2efb1219422da32046a7f6bfeea16bee40f2ad094eb7e4028ada983e8c444035d4e7477bb9b5fd4fb4b8f311255afdba206300c144a749ed19250bd80b202ac2be38b6fe5372958a5ef717280a961ad1a2ec5c50eb642d9cf4762b7d290e2886aeb3755cef762656734e2dc4cf8761f2966c699134f97e90110be55dcc177
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	4	\\x770265808af8032669028a38a2827b3c1cc0a018f3dc592aeaa24b4583d2ee998c31eb83b9c30d2409d2438fe7cd6afd87509ace612674954ed5b9c2980c6005	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x831d7086262b18c4570c9f0503d3e336e5aec9b60934800524679991b151417f9a2482177df4a43136eb2be1a3b03ce6c238cc533aa2750a86f50c4caea3462384c7c68819f95cc3c79a1a3de8edf8bb9eedfe355c2412d7d882d69f69042d3f5d44cd88a1e631f49a77989386f127d73d1898c7daa275d8dfff1a8c0223f9ec	\\xf4b681a81a7dae3b48c3310f31499c59b729945bec436ce3f6e2c9bc2260ab7be09c9a4b227012e1726bed35cb75d45a9268431d1a9f619d10f5ee101d6d7c51	\\x5b41934f16577b4511a3ca4a93033813601ee37bcf5aa518153652614ee5ec39e15571e6dfb9b1a3b1c0dac8687cd475f64bf54afec71ef77d5d87807e11c45bff14f42d6ae0191f8d9be0a26377e33ba0f98c6ebd9f7b4ffc915317e3ea81b1832206f8b0214ff24e1803f5a56a747f2c345f759e38c4804536a56c5427931b
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	5	\\xcc2f3963d7b1d7f9b9b458325c626bde9c89bf11b752c10bc7e91d4eaf4fc84d808e6b63e4ef4df3b85a7bd2a1f0686688527a0163797bcdd8a3807c8073e50d	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x490f4833466a5ffdc2714b4ac71ce4875ca999bcc20f2ab115dda33a15f21c6902622734d6f852b9c3bcde127c4c65e67ddbec4e9bf5a91217e3a82b2f6fe356569ab97c404b734ef4b6e4b3531b68250a2ce74e1c6076b427aaab30f7617e1365c98f78e2949bf6f6fd6145a63a1989ab9cff615144961e7f88c3fcb66511e4	\\x5ad83358abc1b1119d7bb159430eb1a2eab439e5fff609cc0158e2c2773ec790e8025a4368dcf2c3551743b28535868085f4c3d971fb4c6d919742584d939e8d	\\x9a5a0250c7e34de95905638b4ac9d86951d3d30ccb6e7cf4b272a8cfa7e93792c6e714266b9dfe94acedc0240e9a206f7fad066d9bb874233005f7dae12f2983b051607c1f10d82233cc930508df08d06ef2b6650ba528f06089aa0ad8a107c847863bc0fc398c12eabfa34aca0f0c850273ddbcacb5b64bcf4a9fbd73c54681
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	6	\\xb513588e2d670c28ebeeb04048c998921f08c9b13b6bbb5c241dd40e87845220ecfd655f70ae0052c75adb085bee29e84b6cd04f7bf0f744e4e090729651450c	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x6cb816f24468ee823a88df6fef64f545fc72820e2a62a9b946f162c944843fc679962c9e80c17190c1f699d958e16814f373c17e93ae9e377981b20d3f34d6748435dd195547f05c4cab4ebdf17e7ef7663ee2c7a0ccd92344444bcb552aa6bc8e245f02dee1f8a176389866202d37d17b687750445d290d7ff9ddf73c0f1d6d	\\xf3a9f4ca4660c33836b528dbf6a629a1b52b982aee927b262dea685531d0661471fef781a420f1b21f4198ee2aa44805ed4b850b63fdbcf56fbd36164d585262	\\x3b3b86e7a2a395b4ba95a16ac4e5d234918547bfeae0b9cb4e06d3de0f7de3d33994450e85d5fa85a03a7d5520f88f7c6bf93b4820f569b04d332309dabe458974c63e28def829b936761a25a5b6021c835cfd806c26c7642d0a7d400b178fc28029476cee2848d742f2685143f13f1be91d6d09a1e7ae6ecf657e8945ec1bb2
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	7	\\x836dd5edf93f2018e07a04fd10366e6d2afaec5d720ea85a80392236da213a09b14e882c63defda77f9710a871570c90c2e5f3c57069f912ce030b0b9f80b40c	\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x53953f91d66e29f7e29a6bfeb6ee90cc1be108f1204d7c0941625dce3cd248ebb20b51b19a3a485bcbdb0c6e4babf53a588c6032974d8e5b21ef40d4f646d414b08d8b7d6b55bc547864455c6dd9a929ee00760a119c49c8e52e9bb5532dada92ef48476477dde695a0bd5cb980d0fa1b2fd06cb8e945cce9013075d1fd618b1	\\x6ad966f492a49ba9d89167306249ec25b30d977e9aded93b07ef202a1b1bc892cd97dca16de5d1f057553792c02acf15aea45034f1cd78c2a27e37be907ba0ef	\\x86f1bef8356ce6a1e1dbe8ba1f8b744b9ba1c0e070722f8668e2dd130787b9f2dbb8b74d7b0e17d4ae037bf742a53cf8557d83861997b7efc689a3895782eb074996819723f511c68c298a3d00a3cf001aa343950d5f90eba3d2a1a8b43f692dee9ecdaab9500e062052fb08d7119d6b83e5bb6f79cc65a9b76381cd15aec1c9
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	8	\\xfc0e93e18ea8565c661fef4930b1417a0ffa9a7bfacb127f2765a819632970c910dcb08801607d3613c842a3329616ca20b61afade592aac1336d12552465300	\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x8b186fb5139e83ddeb7228b3cb80ca619a1be3eab3464a568b980f73255a5305988c9c7b5198b6df46a06205e36f941a3b2fa067fc3008289dd00be9035ecfd3746a6ebae94cf45f336a94609b3e5b16a81e204860635851198dd2ec33b967512de8030a16ca45710cc314ce08508ee33724f9d0dc0e4692c324a9b82b7551a8	\\xdf445d707dc3c5af01f47419f8efde705a961bdc96167167dcec86798ea2ac4e65be062ecd618cc7c0d49e65e48cc1b7e01c3f72f8a212ce12efa278b10f08cd	\\x6a97a8d86f76611537b5faea951c2df2c2bd3cd8d931a79ecc8612027400d4738d7325fe72dae79825385043dc538045d5366688171127422a3865bb3436e26c1b3e852b697cb7bae9895dd5b762843763f8e6d5055835dbb67dd9d9ccd287ce669d13ddc32e2d67f7cc9bd38b540f28f71e9589ddf45ab99da8a5836ebd3154
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	9	\\xb46a098b3affe9620cf72b7f5d83a10af990735fb8be999d232927143bf469e72ee891df5ae15dca0a2d39e1837bd4eaddd92d179b01cca7056ca4627d629e0d	\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x1956a2efea68aad88af6e69530cf5ecff141d01169bb23e9cff67ec0a7396d8bd5294f8039f793e2b4ac079d6ac2a498979eeaf2081efd474612e208c926becb84783131e5624a8a167877a4187ea195f98ca710c9680a3f91c71873c2ccf27ceae904499f83750e48438160bb3fd7a9ff6b3b0c2213e8706cf3cdf0df89d571	\\xdbd36186d9ff963d2b678fc08439495583fe10597785a803bed937a344c47062912fb15fbf7e16a84eccf9f932ae5db6ae6700598dcb27fd30c1d807383e4cfb	\\x80760ec2c18b11bd7fb81a745afb08992a752e23de4b5f4cfaaf5a576633857af38d5b460513a3e100e62fe314467b38865f6c19b7ed055b92fe88f6a6848112d474419b49be495869f46991647a4365c634e5e6821e1844cb80c9bc3942458c4430d6ef50d2edf419776b662130e374701c25d29438d0e13b42eef97f4bea8b
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	10	\\x2970dd3c9f916d84a7c1d0962cf4a834cfa8fb9ce1b26c2cb9d0c3c9570839dea6964021d8ab2332cd769b2ff9d56ae98ca1c901b4ff90d8a634f9d79cea0f0a	\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x36b4d009c39c22884e76cf61497439c1768d2f4bde99ad26d3b3ac31da2382aa352fd5883cdc0fde7985115625a115b869e858ed68faffd6dac01978193d32a764edf5152af8dc6a29b9101c8a1f252018d34be0a52b7d87c906184cf6a34156edc81c1fc2806f727be9133de9fbb2685e49662253c0307ef79a672410a91033	\\x9a26bf5bfb607171d805cc9160210591dbfcc370afc4781b4417ff98e5eced8568547d27220c5f8f23475e03ba0ffc8480d47da85d24ec21412609b469d98d52	\\x07dab81db5fd96cf2be67fd9ae0db1d734ca8d743a90642c2bdfa5808ed27e42cbf1553de7c7e4a261b691c119cd88e72e2e8899bd123f273edf1b7d11b58ea9be22d81fc0993f009c9179c9f3a7db8d0c6c872569716de17f2c6b4488f059907e6ac19b5d6046d0afbde6db26df03d13dbf8bd45df4cc0895da15d87a0f6dbc
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xbdb58b17b8172e8b1aa8524f2580a6dc7b416664dc3f87b6a7ae6e26833cca8418540a1a4f6e73cb4ecdc5fdab7823bd1b09263c87c70a9861316c3384d4f506	\\xc39ae8b3aa89a16e4a49ae0ca275f8a2edc3cd1251fcbe60fdac0a1379f83d7b	\\x9af5443fd6370e2f846f078abe8ffe43459c8659702430dcfd864c0d6b52c76dc590b2595d96b6a5ed89d3a5b7e67c4eb3692c901d1aeb9a6e24435abbb1d0d6
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
\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	payto://x-taler-bank/localhost/testuser-a7XHQdqA	0	1000000	1581682761000000	1800015562000000
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
1	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	2	10	0	payto://x-taler-bank/localhost/testuser-a7XHQdqA	account-1	1579263561000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xb0203af1ce57de53edab718d5d85a193664af98944f5e140943d857be65daa2baf5e0d50bcb390f9d2fc90e39ce03740739706cafd3b131567b0d577bf56b33a	\\xd1b1cd52b53fd93409562be0eed9bfaaa8933bfc50303e85560ea0df784f471055259bc956118d71df276dd93a4a5185391c010fd75f5fcd9c7035c0c781ce9f	\\x2536d34082262421882b58b581deba92ffb10725918536306170bd0bd6112eab8925e0b0666e414721edf974f029a73966569d0777805574c758d8908a08fa4dee8857b6fd3c00ae12fc92589a2a73d602eea4db7c9c73bb445894c424ad5e5b15eb70837b1395386bf6ec4de573768338d32c3bbfaeaa3abe773aa15d92304a	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\xfd674a38e4c90ba4d217f9abb9fd6c9ef0b8b1b1c0c38706708c89e09bb567e51e6c02ce373ed8fb3a6a8c7cb4be2f649397871c7e6a76a76ff4bd8bbf2d540e	1579263562000000	8	5000000
2	\\x7936616d57fac164157cf0d60f647d4fc23fc9701b64d36c705d5ef84b80e05c1cb46194d147ea9930e17abb7d8760701141bc1469f9310a078549cb4f59ea96	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x350edad65bc768c73e3a8c2138da10bb686931480e0c4bb2bbeeb7330c136e28dd6cb4e462b9e9da50b800ebfd7f45252a2c9d0a1e1ced935630e22a9a625f27e63394758339f06d8b96b8c349bbe1d662471721c6c2045e38d47d85fd46ef2b6f58508c351caa62769211597c66b3325e82323d29109f4263cda9e162a12270	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x417bdc61483e6a7105c6732a11f8119e30b9aecbe006de5e7566a04ead2e914cec5d6beafd78f587a8250bb732824ea622db229ac256c0739b45d7843528cf03	1579263562000000	0	11000000
3	\\x82f0d1faaf2f54f18c0a2ab856cf71e850dd7d1e41e2cdc430bde3590da66156a457a6aed71de73688ad41a5908a672b7359b72ffd71968329da3afdfae316c0	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x3137011c81fc139a5ee1629474bb80bf484b9374e6d6a7178d765484a3505ece64427f37a1f7f3a0bab575c5ef807e9ce8420a3d12279f8ce49d22e656d5e08ff47c9f8bf0da83cdff458c8df879cc726f22bc138433dc32ea5e82888082bbabb7268af72bf361373033280b45e6e0247847a71ce15d19fa85bcd3e0f2f5e51a	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x94af3811a5b406bbf0c9157622538121fbb4038d22377776d8542dcf72c8f457845e59262500cb59eb5640c55c129a13d6a09c37d0bf9d9b56d581f64deb890d	1579263562000000	0	11000000
4	\\x48dcde785d28571e70d1c4e93e546553ab4e461973f1ee0d21764227bc0efc2a83a8d0209658f598a9fa98676fcabb3b1b8f6bf32d5bb0f8a1c5d5e5f564a347	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x4d61d7898b799bad729e6856172c21b4b64db4a0dae4372c5bc5cf5a9980464b71edbb53d602a1b1594a2e3a60698e89a7e496162c996c1c4c294929685ee7b88dbb61804bfc55391921fa8b9ae9d9e59dc23b193953c0fc294a0e3a8cc7a5777228fba6fb9e35894581b07bb9cfb7664d172b40aa6f844bfd0176586d3c492e	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x49a11796f655b875e01cf3c73e5b206e944d08b6dad447224a6ac8522e68d29cfd638de8c76d343a422fccba66dbfc690d2401538ff3e7f8f09ff7f822be5306	1579263562000000	0	11000000
5	\\x641ca8057c7535dcbbc7a375eae4443478eee1ad08d7522fc4724bac3058425c42b5d170b0830dfdc744865daa2f7caaab326432621dd1eff9c163324e006385	\\x58712f5d1e40314d71f4fa8b31b7cccbda2b522d62f5decafd9dfae7e5a00a959d56bd1d1fdcf316cbd1890aed45dd81d5c43e39d5cc1f19d41c820957ba0ff6	\\xaaf9ae3fe1d97c35be2552fb1e93e4602dfac89c630de78559f2ab85f55acd02a9c865c0be578e305282f18ba59276240a094997bad9536a2c4869265f1e4146f96375ecdbe94872ca14d84eb488bd9b3b8571c1e822f226392940c1b31d6397721d90c0030aac2f009b9ded53165fee79d7f9d9def98ecacf50c9036f5c732c	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\xeb4fc474cd470628a92e20fc682d4df82df4780233b07cb27e19006165bd3dbb9d20a0810106f38231d2e81aa1290b167d2812c9e888d07a00d81b47c8678f03	1579263562000000	1	2000000
6	\\xe0cb7496a7f6f140949589d8a72cd5e293afadf6ef226d366e4dbb1ca9552a4e256d53970ed792b647472248dcb02162d25a8f7bd9a333137074b67aa6bf86dd	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\xa9e450bcdbffa0f0d269ff6725d3f726617253c4ad67c9973007bf1f2eb0eac4cecb28577a8c593010dc6b29428b1747f575bbbd8ca7f7e94a4d43db67139a4d9e8fc6ee526577c7d22a8a249bc4171c5b3d343bfb1a52022d415087adff32c7f2cf3b4dff6993934ec89ae45bb6b63681c930421cdee590f94a75c9d9ddedd4	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x83dbac95b9191151758ec5bd3eafb6b0a3bb3d1c065e032f3401b9bdfb05be69b60e0c05a31efad74f2074f305fc39fc5bd17ce05b87a21f8e8395688d27d807	1579263562000000	0	11000000
7	\\x89c9a8f578efe1065278f101ed0802ef23cfaea5f44efab5325c9188a6084c8b18bd21cc8cb97cc841cafeb9a4659430f80a01f8528d86ea05081e6706bfe749	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x37e7d07686ba9ddae175f045df9584f1229c1edbfc493f88e57a25f8fa9690e3226c13892e25aac3e8512582b8fa150e9db49a5a7ec1b3e6655074957a6c94abfc8bd8ef6c3bb1f7160ac9fbe164067d94b5b513ba5f8eeb8e872c2fcbea7e38ef1d7436d549c6f1445f3384a545dc3f18c0e805b79edd89054c9bbbb74cfcd6	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x826c1c7f917a3cc1bfc9a65fdd16efac556774f87f36487253c096c6017b9750429398ba54530b53f0903e0799845a68426236262d2ab3eb1757e51184eec80c	1579263562000000	0	11000000
8	\\xcea22f7e3fd1438b8b3cf37f5953b8457621705bba0d6e9b3d47d6df841631feb82e79e7142ea115158dc7491eef648c76b42b3985bfaa1286c580ef3fe3cad8	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\xa418908b3c83a10a851f831627b31bbb1bf58c7e6ee2e53a20549f6df674af80a1f5b9228f111f5535763048b93b43cbe47fd5b28759349f340e6f3df1d105738f2e8eb73a378e32f2ba44c5a1791772572091cb623e61fdab560118a3983e8bbfa2ce64ea8c1d132191db43f3a69e240c022909a0e17ac5f4de8c383df78c93	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\xbbb97dbabb5bc79b0f3687c7ff730a23cf3b66113b5066c7d2ce3a003427f7b2e1b74735f9fdaa1a4622c58bfc32bc66a3b604b7e8ff729c703093884d981607	1579263562000000	0	11000000
9	\\x619a3f59475a6f1c9bba407e0c796c2868f38c1bd13e5866f295b28b54ae327f29d453f2e66cc4d9c932ac0a0b1da9808a0a8751896137fe5b71b71daa7c2d17	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x7140c8bebe591477341332a659caf3cac6dfbaf16d46a18a804d4773d1ef9b580c5652bd52219e168375910366db56fac78aa75317dfe28ce43e7bed8bf385a81d7729e3a1d20dfd59c99b5e55e603cdffe484bf41f3a93b88fd770552462b4dae529afcb2538fe342083d51e1c07995543081610df87b0df9832086e400c406	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x384531d4abda9602ab042f216f21c80737b3b9c8bb9235b25b92fe2767901bb274de5bafe907c72185ad0e882f6b06f042202e2a3082fee5c76692acc74e280e	1579263562000000	0	11000000
10	\\xa0442b23c3c37877c7cf2b2a8dce1778fcdf1ad843c727ceb7707883d3a9b842dccc034f3e972617b61ca9295f0263050c7573e484758f2c2b1b1d403e7d9b78	\\x685c9d6d5410f39eb12c326bf28c7767ecbe1ede96782a8510f1354b3e4e2c9f05bb6de0632a142684bf7a56a9bdbe75fd75238ecdf7dd69641531d047e7626c	\\x7aa8904868a588cef8d85ced7540a2b1f63f76bcf5b038585a3cd35975148b558d9565036ac157c85c9585c1359058bcdbf7b7e1fb3f3671b84f1169495062d3b04075d9d518a7b9a7b7bd76f02825a03fc2561ce296c0609c5244aa7121db1adb308999c9959404d883aee64753a3c582a785531e0eafc9030e903b91363b9f	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\xd44d117b1274470e95ef5bde983997546f9c9221d9f20ca1e1b907d3fa17f4859daab0f9d58fda316c8bfd76860529bd0842b3640971f318c3c5acd59caed803	1579263562000000	0	11000000
11	\\x9dc071cb39af72ebbcbb8646391e7fe359dbaadb011c2de75acf3acff39ba010d753321b203ac6c094b040d0c9e7588e8b288f7c381faae8a917960e4938ab95	\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x49206914d129a988b7cb7e9c7dc638a460fb5d49939960cfe3a3726442eea268d9da08797ff462c6d7ec1a62ed6a744c4778a2c3cbf2b0eb690d8650412fd2883dc094e8cc11fb46ad72ac82936154c4363f85d059e5ea99febb4de4d31348bce4f0f99def8e5b1531a58d07fe157fb120e7720a3abc035d8aea685dec1c13a7	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x8baf6d15fa3a8f14310823ef92275cbe0608fcaf6fc29c836a6e6e566a49e47a2aac0de74e3ad2cca290d74ad45dbfecaac0a2064d59449814bc9a4ea65e3f0c	1579263562000000	0	2000000
12	\\xc9c317ebc2e83588bf2bd9dd6122695ac2a754c554366f6a9f25323dccd3af5e19246d61f2d5ade95307297f5bd7378eea5ef8cf73186e9e3b398c23b512abd2	\\x33a463eef4ccc3c4873ee6e30d50cf131f3e7eb7bce2172361ec83a60e9bf5c57bb7e7464b1722c5974aeaf97e0567b6ffded2196b6aa56b52940f444a1f107a	\\x72c14326ccbb2495afb53a850421040a4a78b7609bb40aacba6f236a8f28a8f5b3b871072ff5bd935c5a1e0cdb9389bfd2f90b3e02ecff88f5af84c4eb48e5fc5a8c2b9040cb609f6be4eb44df4adbe175af8363b83b3bd8a60be930b470f135ef0a11dca3564a76a4a714ae513d79afb616fd77113b588bedf039b92d5bbd6f	\\xebdc08292976538a174b92a1865b6d4e1f5dd55499f26cfe64c4f3d54ba83152	\\x888d3d0bf9fd346430e3e475484e0c2add7451dd434f655cb2b7fb70e1eb2a0478e1eb308f9dfb421213e6b516845b1ab986f6eb4b749ae94ce24ec1ab3d1b08	1579263562000000	0	2000000
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
-- Name: merchant_deposits merchant_deposits_h_contract_terms_merchant_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_merchant_pub_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


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

