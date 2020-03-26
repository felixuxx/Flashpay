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
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


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
    request_uid character varying(128) NOT NULL,
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
    confirmation_done boolean NOT NULL,
    aborted boolean NOT NULL,
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
-- Name: TABLE auditor_balance_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_balance_summary IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';


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
-- Name: TABLE auditor_denomination_pending; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denomination_pending IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';


--
-- Name: COLUMN auditor_denomination_pending.num_issued; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.num_issued IS 'counts the number of coins issued (withdraw, refresh) of this denomination';


--
-- Name: COLUMN auditor_denomination_pending.denom_risk_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.denom_risk_val IS 'amount that could theoretically be lost in the future due to recoup operations';


--
-- Name: COLUMN auditor_denomination_pending.recoup_loss_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.recoup_loss_val IS 'amount actually lost due to recoup operations past revocation';


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
-- Name: TABLE auditor_denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denominations IS 'denomination keys the auditor is aware of';


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
-- Name: TABLE auditor_exchange_signkeys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchange_signkeys IS 'list of the online signing keys of exchanges we are auditing';


--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: TABLE auditor_exchanges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchanges IS 'list of the exchanges we are auditing';


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
-- Name: TABLE auditor_historic_denomination_revenue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_denomination_revenue IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';


--
-- Name: COLUMN auditor_historic_denomination_revenue.revenue_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_historic_denomination_revenue.revenue_balance_val IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


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
-- Name: TABLE auditor_historic_reserve_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_reserve_summary IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_predicted_result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_predicted_result IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance.  This is the final amount that the exchange should have in its bank account right now.';


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea NOT NULL,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_aggregation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_aggregation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea NOT NULL,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_coin IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea NOT NULL,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_deposit_confirmation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_deposit_confirmation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea NOT NULL,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_reserve IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


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
-- Name: TABLE auditor_reserve_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserve_balance IS 'sum of the balances of all customer reserves (by exchange master public key)';


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
-- Name: TABLE auditor_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserves IS 'all of the customer reserves and their respective balances that the auditor is aware of';


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
-- Name: TABLE auditor_wire_fee_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_wire_fee_balance IS 'sum of the balances of all wire fees (by exchange master public key)';


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
-- Name: TABLE denomination_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denomination_revocations IS 'remembering which denomination keys have been revoked';


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
-- Name: TABLE denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the coins the exchange knows about.';


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
-- Name: TABLE deposit_confirmations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposit_confirmations IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


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
-- Name: TABLE deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.tiny; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.tiny IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


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
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


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
-- Name: TABLE prewire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prewire IS 'pre-commit data for wire transfers we are about to execute';


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
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed';


--
-- Name: COLUMN recoup.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_pub IS 'Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


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
-- Name: COLUMN recoup_refresh.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.coin_pub IS 'Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


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
-- Name: TABLE refresh_commitments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_commitments IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';


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
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


--
-- Name: COLUMN refresh_revealed_coins.rc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rc IS 'refresh commitment identifying the melt operation';


--
-- Name: COLUMN refresh_revealed_coins.freshcoin_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.freshcoin_index IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';


--
-- Name: COLUMN refresh_revealed_coins.coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.coin_ev IS 'envelope of the new coin to be signed';


--
-- Name: COLUMN refresh_revealed_coins.h_coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.h_coin_ev IS 'hash of the envelope of the new coin to be signed (for lookups)';


--
-- Name: COLUMN refresh_revealed_coins.ev_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.ev_sig IS 'exchange signature over the envelope';


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
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rc IS 'refresh commitment identifying the melt operation';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


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
-- Name: TABLE refunds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.rtransaction_id IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


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
-- Name: TABLE reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';


--
-- Name: COLUMN reserves.expiration_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.expiration_date IS 'Used to trigger closing of reserves that have not been drained after some time';


--
-- Name: COLUMN reserves.gc_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.gc_date IS 'Used to forget all information about a reserve during garbage collection';


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
-- Name: TABLE reserves_close; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_close IS 'wire transfers executed by the reserve to close reserves';


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
-- Name: TABLE reserves_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


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
-- Name: TABLE reserves_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_out IS 'Withdraw operations performed on reserves.';


--
-- Name: COLUMN reserves_out.h_blind_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.h_blind_ev IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';


--
-- Name: COLUMN reserves_out.denom_pub_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.denom_pub_hash IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


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
    master_pub bytea NOT NULL,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint,
    wire_out_off bigint
);


--
-- Name: TABLE wire_auditor_account_progress; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_auditor_account_progress IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea NOT NULL,
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
-- Name: TABLE wire_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_fee IS 'list of the wire fees of this exchange, by date';


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
-- Name: TABLE wire_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_out IS 'wire transfers the exchange has executed';


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
exchange-0001	2020-03-26 18:31:36.816456+01	grothoff	{}	{}
auditor-0001	2020-03-26 18:31:43.889593+01	grothoff	{}	{}
merchant-0001	2020-03-26 18:31:47.155872+01	grothoff	{}	{}
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
f	11	+TESTKUDOS:92	11
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2020-03-26 18:31:50.685184+01	f	19246c16-f71d-4857-8172-8143e0536c6a	11	1
2	TESTKUDOS:8	6VZ1SBAHZ3BF6Z775FH1KAZQNCSDWF7JW1TZZ901NTY7YED33510	2020-03-26 18:31:50.78515+01	f	a9ed8845-c888-4c37-a44d-805ff57b6cc7	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
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
\\xf2df58ac0a7f9bc1662482d628116339ee319b7499c6cd5dadd3123d48446b9baed0907639f1cb62b19e2343d5789ac477ba55ec892a640e17c9b8322cc10657	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc75a0a63e29c8ec2d2e13bc182ae982d342d728a54df92a27d70a861049980cc59f947ad7ef1fec6b065b1859cbb67f4661af1f593fc19b928e7c3980cf9a9a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x87cd6908495dc978d1bde1131fa9ea316bb850f9b8e2eae6355c01808072798699b98889927ebe0089bfae4c2fc073fef5fb789dfc45ab2de30c9f27b2e903f3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eee30eba2c7c557b6ed3575f1dda90b4b63903f301826cc649d47cb107966e3ef16677c6a1b27db53e55ea2dfbc714dcb37db550fb62b99990b86af58399d87	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86ed10e3ae3c24d9df37bd544245bd1aaa9be003cd205b95a1fd6cf6e7a78dab21525a6e2c45d61719b26f6717af5d7e9510841ec7bf090ba0bf8a87fc857e7d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x187ace28753db4bed77b9e2cbe23d99162789b9d79584e0852dd1cc2c0d8f155aaad16bea0a4e26b1b23b3a38268de34847044581049a29af50c916cf92eb3e5	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x87febf9a731ded53d74093ac364b900f850ca2438370857e01b2df24ed4cb0a6e684ea97790a748a2916a9a1952ec2ff1703157df93dc6797f388c79155f4e68	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf36ab0295fcdfeabee9cd8c7ea7b6a54763fda86b1f0b225b67e88488c8dfce236fff9c9ffd6651ad5d29d6582e382aee5abc44cf5fd293bd8023aacda79226c	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd62b35c278ed74753eab3cee76c6231466c0fe892ad02817a810328ddde62e9965d0b7fcf2d9dd4062fa3b15d912e6e2f4000e29fec91913dbdaae88b2adea8e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x87f7876be9c570c01a3e25e76e6682f3c1d50dd7cd5e9721b11f5478d434edc56c4dabac2419747fbbb055b419239bd51b1c540dff8d7c1c0906a56e4a11bd49	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5cdc334fe7ec331c361ee5f45ae8249e4c7eab3974d29273409ed87ae914c5ffee8a56f43d642d5786c0a64c00b147b6cecda5cbb19edf34fbb41c6b8802ee44	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcef5fb056890cf87f3e1cc2da9044ceded0602c6314fdcf86f8d156ba613f7418b277f5beffca1f6a2dc5fd57d6ab230ad3cc19aaf3b3f2f57c541e325ed8f0d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd7fa1272efd3958079d3ae6546a2bb82f4c82f0f729a49a332d92a4d78a3d5d21ddb38b64c9f5642b0d9f78f9dbd29a5b51b6fbe65e403a4c95de67a3474f0a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x529868535b2394bb7e537ea08a6f2d97a538689688e2ca5bfe3bd5822d67156b0600a102ca85eaf59c7f5df15fa90fe4b383b4467b6b6b76b65e7b8fc13a1e90	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x088d167a2b82660119482a2e77c07419c51bf72582ba628bea7d1d512d3e6805a1f3acbfd35e45f4f21ff60b072dd9871a32b9e493a80920fe4d3ceaa8d98d9a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe700de469a2f4f955848434b4f434e416e16873c6c3e9ece3d6ac2832889527c3427c8378391ac4f86d7a77cbcbf8eaf07096d0e4490ebada9f4ac2d1e0515d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2764142008b40544871f2fd1397b97259627a07a7c1820408c17a3895db8e6e8d93026fbf9e7fb519f9951ec3c91d0c9de01b6dd027c94007bbe2d307fe9f36	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc83270c8274fabd92f2c2555235a0ff5cf1b41e1d33519f369b2f788b7bd9fbd8e9f58d02beaa58c3fe2e74de62b1a4163747ed2c74682175076859d47871cd1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xea542eafb04ad3934853d2de89d3e0369132d4077596013d64f9e623b0f89e457609218cb2c26964ee589331ee545ab4bb204f3ddea9a1c4cc31d8fde6380c0a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d0c41c82de042acfbfb5cf7d4b1c37bb04ca2832f9c9eb7ff183c87b1932c33d6353b07dd833b863738990307a25b7bab979bca8879b802eedb8957f278c8bf	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e5c217b80bd02f64ec6d0b980bf18a5b3b6e01e604c9cafedc916877ee94443df0217370caeaa66ce93717261e8015f4e60fae96b6d89e9fc777886471fb633	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa01bd9a4ef2ff228b53f24174be7424fb929e1e72be4a6291f00f21fff00ef9820f6f945e6068abef98f4ebcb277199b6e4dd49f45f970acd1b4ad1701762535	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x34a18063d681b8babe8c0f96977d6a1c6cf16b9e08b2d55393765fcdcb4f083e360a641693eee1c0e3d8729eccac8dcb61ffaa9cafc46688a74fcd7d4cd4d025	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70bcd636cf5eaf5316f05008632d76c163f3da636b81da832e06796f292ce281c0ae171afebf82efde6ae44d8f7633f71eadfab5a4632d7a437b34404acd031f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5bd2651d594c957fb8a2424ed6c3a01c3a6c54f9ed7c9a7451498b463fecc5cba2435aff83eeeb9050aef14db452bef9cb48e73953c3ef07c1bb6b56db4d14ed	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86a92243a87aae4d3abbbd80db46ec12df7496153b0173a1f107beb7ac14f2e87a9a48a905c78566874a8874feb6e5b2721ac8b43d66a0c3624b7ce0854617ce	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2691baf34df1abd0f4654085cb75977ffad954339b443e0582ef03cb8095570f3c90507eb5ea1a6eeafaf8ebcbf40869cc62ccb84ed8bf818fa4c3e9292dc793	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90e25247f8d6b317eb1f6aa9c2d90346c7723c571581527d03509f6dedf70b5ac2d63354a0ba6e3263b67cba732f32b83cc074c6b7eaba37a8bb1098e778e689	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b6e315117429ec8849cf9371eeafb3c8d78691f2b5f59b4027a70f423bb10e268156926214ec015580b9ee5c1373fca1b6fa0d18ed5d54ebd17dd460d6bf73c	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd237a00eba5ea3484211ecb77d7aa667b14f8a1f220a3bf558c7e6f2437b64838b1e986fc61fff07a5462d6a1e86a01412e2d26b7e2f08eb503cf9b130734a6d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e3414576cc574d95e533aee15b9be5f5029a3f138461fafc80079aab3d2afddec40a9e27c3ec57b9628ee16744d00df757217eab83d08e0e5ec6d3b1c3813e3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xac3dbe970e1006bdb6d5be61f3c5f300255d786c2e0b0f544fd5b30dc228c13f6499191c6d5daf357c7f52bdb16f3db6b789231798b3f1f5f15a436f90200925	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x60fe4e1bbac5b0e89adb7d1763e6871a249092857e4676b39c056beed603f20cbde15fa2ffbde22a513394c5c16ec6f06f90a3f526632c56b99282d4e95c3bcd	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd79a8a4e6986cab23f056abc5adfb91d60a4eae699bb5a624495df249ab9c2a2b705cf588eea31eb0991905e62014b36e458e417f7e28b8ed91142034fa2326	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfe0b4193901172557f52130f2fba1a894f16042c1ae1c25c86c545021dfe5a0dc02bc16ca6bf6fe11a842d8a4bbe2cacb17dc6f91719da466a60f291a9738c3f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3534b35710c1f0e1155cfca1f4809ee695582a7d44475908821dc8d388f0fe8a1460b8594b08579b1092345544b431872239351fdc33bcf122a6f2965bbb771	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x88c67882ef1c0804c6d91a9f8bfd33653a80ea715e707bc40893e387ef8f7693da0919fa25a528507a1ada02744786381945d734d73e8563b68deaec47f0fe31	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7104356f5e39aa088b782a3d704f4579652735045d3d0cc552540f2f0214ae835904ed4bdb575d0fa92f680ee7fdd3b38f196bb8b56a1ee53b1a9535badb21c3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa2939d2bf7a9c6bbf70a7432fe9aba62993d9965c7569220b0a64e500fd9c1286fa1805c49215825db6743465c3ef422415b817a6c6d9eea6a717d23d2eb5501	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x11c63330e9a9413bdef2333fba0fa8f6dd75164c84063a4ac9c07e275939747afa0ea6d679d96084cbeebc83c9ca19c4d85a598f7a7593500f4a3b1bbd05ac49	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe38b7536c79971b945244dd582aa72842d82b6b4081ff60dca5a0d6b40a9907fbfdc830ee77460f623f3760642c544d741c0bf581470b216c27d138be4138b92	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2c71bd5e41fa30260e4dfd2eb812a093cbb723130006af235cd69488647fae0039a53f57e652b84c5ecee064f4caa4a31430d75f7ad0af3a809f0df78e3551d2	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3829e1f0fe0491f9afe5f5923214b4e208abc7af53521b41849099533676080ba304d82d34569a1afe539d71147915636b96641652e9816190d72f37fd2c3a5b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf625d8596ff229914993052d9b89bd73714c0d81119c7ab4db1ea0b7c33804956bf1b671e0cffca75aa7f95319ed5a7b4951aa8e6b7ce0d14b8b61a2903f9dbd	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x614a72a93101121ba4c9aec4be23a63f606d075c3c642cec241c156f271a3cc4459f875e5ab81e74adff4ea2ea700ffe172e1ecece45e9e420dcf7c67c3a64ac	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0fe8e53780bd91a7566ca220e395df6db059927162f7ef59f50a81d4234386f25657e2d9ffbd6690013bfa5cfec915d501d77395ccbfd13c85d22aebdb3fcf18	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb6e974a0c8a1c5e2464d96eeb28a4ddd08e2921ff208cfe20542ca065227f19552153923357d6da75b86fef527e4e9cfee33bdde559a3a26164c41abacd585f4	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x552591d2e3a286738745d2f9cfe796489137a883cf24ce6b5903adc18aaddeb1b11feda2501788f8ae2ce66ecd230c429525eb237c5d67fdf4b9d0b6cbbb23d3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa823a5d3d8517bbcbe43015a57818064b3bc243d7773fb409ba6f5974aa2fcdbcf1c65247289f9bb1f37df07674f83304c2f76f0d1646da3524efc3c48661822	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2085c092a797fcf981b7ed01ea2e30ac4120c90e628d8ebc95d08dfae56b69383d9d8fb75d3a463b114837e79f0d5dbdd0a1d0858e6a9555721a20728e9c367f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3ace093e9510ace1369ff85ee8208234cca6067994a7f65e330d38e00e0891052217162b5be08836354eb06de155824f87278dccfa2440798bbbc27e1ba00e52	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5daa0fe6a1fba573a34a1ead6643c3af5079d8f9c8092f1f3b169c2711275c7789b18c5542dbd68066448809ec5af72884d695d6bcf31a9e975e7644f9cef5a7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb770e043f1b31bae0033aabc340e891e6d7a8648c1584bc434226e679997c9fae9c272d498e273912209305fa9d2129062ca5d45bf4b91cc5b2de40826fc1bd3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa332cd0c2529ed5348e1bf0a32b43b6c78eb4c12cf050db3e448d4f3c884f4daa7e5a514c35ab92b54de335fbeb8489e0da4162e86b00c3ae7554f8a196f95f1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7e82f8deec5fdcd8598ca15f04cc80005e3a87c17b79291891c3fccccedc2b137888fd6776b4b737181abe9a6257c7c4053c5f6f5bead7db31af565bbc6372d8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x95f9c7de16e65bcee8f927797523df9f510a7c0ccf9ce893f85b4c7b7ef6b16afbd36648fb5b72e4429bf04297bb4312af733440d2bfe9647edd6d8af43e1d4b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfb0e7a6e9c2db8de9bd30182d42e7b8c21eabc3d49b24462f80d321d1309d0bb93d151af2482890e9e2a964a80c51567fed7afebef67cdda14bcee383f139029	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3e11fb2280fbc071112c2e3b3e81cf2789735c2a618fcd0faa945c6bddf5859be9eb658e4ab7ce4c1068b1e022812c589390dda014bf38ce6b54dfcb1432061	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdb7346b611dac484893d7e4ac877ba61ea85741c66a0294bd473959dbfc5a4a45ba8b4c9cdfddb7f5813ab4234d8a1eb8e695fc9e6378fcdd772212e6da5326c	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x701019d0a1a39659d5ddfc572f7e58b9b187b74503d4dd1835670b64daee39fb0233f33e835ca5a10dc1c74c65ed0aba45e20eb9313068b771ba863da9482282	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb62373a63a659f618ea3ccfca83b632e944f72abee7322414ce063c865223818f45752ff2ff49a641ee33205af1e414cbd5ccb8764e0b1bc8f3dcac350bdfc28	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x76280a3f16b611423c6265988b458119e2da85cdee9c3e2aad44a1684029d0a4df56cd9515fc9b5e0e6dcc7bf3cad305af91c8ff46f89bc04d5eb00c2fc0677e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x73b3756f5b51e3bef99b47c17aacffbdd2421dd656e29edaaeb02f46b1c5c8466bad9660ad0a10d573184ac0238c41671e7ed033fd525ea3f71d68fefb0e2dbf	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfae7546c524fb69ef0a2e62b78a0f59fd452a1076f13e38f7097728abcd53e48c36d8184f0910deb0d56c4c916093ed55e12fc1c86e0007f20afb8ef26f5c349	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6ddb5b6438d445dea34aed4dcfaf151043c54f929159c6dbf17c72cb6bb145456bc39a44ba87c653229ef8f296e1c8cf6583586da467e03037d401e4598e06be	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb4c907febadc7cc7c6403f0f259c8013ef7980454fb486ffabe0759c4dc3d589b5659bfa76e126ecaa1e247342018813505c70c0bf77a86ec11bea848406049b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3ef58d93b1ce275b9090e8a0652905a9bbcd5604fcdc68cb07c20c04f11e2c615b80c1891d3ab7e0974a1f556e329af8398d4b1a5f7735ecf23d7087890e3bb0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53e4f5be8e86f7c0c24c5c2160d406dc71af17fb586c24b693a65cd6f0cd991fc6903811dcf5d6e7f37bd770ed283360a696cf74d5cd0e85a3738d356db5ec12	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f030c49bac6181d3c0f27e1861b43697410632ae3bc04e785baafb2677c33e7437239c22af87ffcdcc9c8f7c3a241bfe1e4b0a895a2ddf5af96e055181582c1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0adc59377119677c1efefed5031f9dad514c31138f0f39f22a899fb3648522f5f55f75c007add7a70e4a33f2e96d53579f29819ec13a31f2648417468ac134e4	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x38e21bf89d97b78aa66d40f44b6dba481002beb77c4014e2ff3ccb2e8d47cfd55d566ce87442b68da0082a7475b928a10a6463e6856f050dd6f027ce9d5b7efa	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x97a95623d55b0b483928bda7b1446f2381eb2beef612ebc75e4f44521ae984fc108f68623ee0ad6f0bbe311badcecb0f7faf4fcee7c471b8337fb71fdb4d8acd	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x11f917852f96a859ed4b5856c26573e50ea7d965d8f6a7a20a6611617ed12a9bbe4692e38e65c1e4ec12268fe8adfce4b34860d0f868cd6d10f7fe6506fd4a92	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55751d6cf26078b12fab86bb02e0e354d8a724491bd910697075c08fdff339d959fc486850c6a5c15b96b8bba8ab769b68e494faf48680b21036866c92132ca7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x203803437644faa2538bab4b786e4f90aff670940f237a16e42aafd8c5d54164146c7f1487869ac45fe6936cac00c47573f45c76f42b7fccce535adcb3956ce0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3afe4da2f1c1c316d458d318cfe00cfde83e0ead137e6a554b3a624525831d50aac7c4708d8edc3b7f7a6192d05c91adbe2454bbede410615e0d5276cb3feb27	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe591cf2781bd9a86cbdc3e154eba94cd9e392013cb97e2b8a54aedac8287b8fd0645c2c3a6fa9011d157de8967afa8ac180ccbee57d84d768eff1de7098d532f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x354c42181885e67942806f24b7ce66d1bc25039f94bfb0c4315d381d7117abb9f86d53a0a270fb5163056e85c63af6dce19aef5df12e3f96e26239d99d0095e0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ded35724e4eb1bb5554aea0d888e206b8f1a520024bcc4cd19b3ababba68456e6b069793820d2b3119ac819b26d7d10e0c96979558e253ff6b149f63cc031dc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c3dfa97e8b0c5a25bfe9bfa983fb19dff0d31eb9014e4f982a8d04c441411f469da4a06e0b6de93dd2070954577d91564569518ab2f2189b0cb2d6f8d5fd4a7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x360b3fb43191203a71741300794dced1377e6b544611cd9b9ab8514953940b3b075b6d426952787e9a8968ca2b73b60b198bdeb95dd695c3bb248eeb591b8707	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe128881e20f253d373c70f46fac7c789568478a361c670891ab8215e248551bdffff09c859d68770c5e0f7b4c45fc54ed3ab598bdefe6a65664c91c08554be0c	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5d7500f3d036eb1618d59003915276262ba65b82b249dbae6577385a4972747f2312876c47248d19b5b7d92096b9b17652be692f143dc58bb413a7f3736cc1d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61bd1cfbeca07b7ee004ff93edf9606b31abb1711cc8626c072dfb096c0e65b1c92b2230c4298417eac214a98b8f1e548b00c3843b78fb2484046ef07238f40d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0ec65685f8aa133ddde32ee85ed57a6ca03bb475b598df644a802f4c3a52e0a1e1f58a0c7f3f038e29024d07f74e19f7775bffa8fa75598fe7ef72bd0daa816	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x869944d4a31b1a0fa8a37d02278a686c25d795b56dfea068abdc68cd049a70ba0355d3de39458e345e409ee57793e4ce18e2f867ce6e351a4f9dc734c668f4e5	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe8782ac221dc7139f96351fac32016205d15637f46b74e5b3c99f78fca7c2a21d8bfd01f44bc4b622c23c2d7744dfe0ff15dade6fb7b30c9a4373b7c6d97d93	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3060d28913fd17bf20add9503375ada366c2e4389db32bd1f2277d2ca6ad8a21feeaa936e4acc4920308926bb89bbd95872d746a3e7a6b55254e288c8a4ab30e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xac22509f6d60e2d4fb4b683a4a4c4a035edcd3138988e8c0432db2354433061818653c939af05100077f9cc1f57bd54ef0d4c90d97f0178e5a547a8712ac1043	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30e24d068568bafa14e0089516fc2d5101012bc8ddb341db7929826a878d493ed326a8faf02751ddc49bf43510bf786bf01f9cc0cbe1c515942e81af3f9327ac	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabfceb1aedf9323bcf39327ec773f1541b02c243b78d03bdf18770498cba6ebc6e48b671ea8486c581966d292dad280aee263195c8ce3e376db1dd58c684ee94	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb88db1952bcb5fd99405ea53ff0c05023a0e17a996972fac7eabfd4473eef7a7c0b4986f741588ed8903351f1b6b11e3dab501b495835a4bae3483bfbda8a880	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8fb74f47de0e6db867902e2b93e4212aa39bf8edcdd9c5782b995f17302f29f30473e8941f9e717ffa1234ddc6cd3fd72e7e150821e3135c126574537efcdfea	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6297ac0e963b16a987b5a3b4f0ed76b574d9bd180ba0e668308af0bfa25090db44566e845d8512d2df6416ab8ef2b35b2c2deabb2bec7eb6b0944d6704672089	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfaa4e072e3631a565f78b0aa673695069d92edde015ffc824e87e556c00c2b30b33e4a6b089b884ce8501d07e8920d30fe4aea8170fec9d9ecf1c546ed60dc61	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x511ec092e2bef19b68207e6608fb3e9d0df846ce0d0cdee1b6ea5e4ede6da74dd48b98545c0e89b5d9eafee0dc105232a17420333a4a68962d16eebe5eea7890	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44bf99d883962788c662d795a83ad7b0af9847159b5742f215a7400e392e211f7b7bc9046ae5c2e0b197a400098d0635f73b6cee175f7f7f79942590c07bd57d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58aafa834820ceed340c93b9def7f0567243a9785898d27352be8aff50c015009cb4c8dc87bc7ddbf0266aa2301c1ecace4e35b2606ef29432b34d06a4784910	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bb72a24e2b821db660417c3dde50a94e5e7538c10a9102264b9dbba629dbae8db4acd6c47e5b0fbce7b8be56f506a2b793dd6e14385ebd7cd2070ce137c10a8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa40ec28d84c3143fc7f9476d46f8cfe27646c6ab74d12cab5aa4a6f745fe5b7c94596bac4ee1a3948421231620bbdd47bf406b1bb0bab70c0911f921f86ff5b4	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c67bd3b5ccf79cf725ae7e26125995846f4300ec41fa68e1a94e851dc31e5e3d3097ff6ec92e03ba3d0e69d49741c0eccbed5ca6eebe7a6032cc329774cc7ac	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbb827f21f1505c35080e2f5561a82c06ed0ef55e73c4ea72094c800564130a0325dfafdb4c904145a7daacfc886c55a35bf3bd3985405b05498a2460b6571cdb	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2f9b6bc37204b9cd93c0bae02d5a68d145daefe004bacae9fcccf95cd30f0ec473f80795f8b644be090aeb849d09a16d4ac00d54c6e6abd8ccf03aee8b22c2b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2abeebb7d2ab7c8f092a45566aa3fde6e9670ec9349fb3d1ea3388ab3b4a6f29193b06d87f0e8f58885cd0a2b9c6f0d8dad18d8aac009e8cddb3a6856532b33	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb535b5afc4568b0fc5e9d1bc92c7624a12c322378296b761fd981b6439bb4ac4070ef9bf2e37de40ef6e13cc8b2466a39af261fafaedbb8edd8f85f1f33b3a28	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x842d9bded428dfcff98161b83c2cea6dd2ffbe9758d68617c1348e181880547a16c19c6392e874ea9cb83f73999614c485fd64538d6620b8197988b74937e531	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1403d296d261f7118f81ff7ee86d086443e1333bf2bd41af0451a1dc127e9963af96f4f7ab72f8c9a362a190a31fa2a80d94437dfb731b76d3ef3acb8e097007	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc13b221ecc60c923bf0b7b65f0fde020c1e3795efccf85ed2ca1c2a9435be88623ce5e87447c51ff3c518ff95537aa2844c4b608ebf5b03858992e2ccf0faf7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f642ba98ba01cdfb88d39533081628a61c65e8c6929f05f9ffc5a054e696e1d114a422693da4d838f0cb27d8db43d1b7613d9b0229c2e2139d14d210a42ea0e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x809162bdf6e77356502abd5badf4b5902a00f08e8d9cb82cc7895af3b634bac6e1af700a5576701955f020aa5e318bf352db64ce2e55c86b8a4fe73dee224495	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2202ca8707fd213e53ffac76c7b960b12a664c34a6ed26e7a8e3668aa7ecfbd159e17a485aee2ba31139d6c41fc209eab0480261a33737acd1b5b1c890e2c623	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44ee356d60600d19d1af15e3d2f7f7daf8f58c1e4d0d6ab760d22f3f136a3dd6911e0c83c53f7a5021e0b582dc333de846849e86f31aec3dea49a0834c60f340	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4be3e10fec1fcc004809b6581a9134dd598fc8b14c64d4b0cadb4a49df53cf9ac24efe9ffd05a837c57c0c26ea6aa7c1dd2b88fa1a0c95cb1eb5f4151f0cef2e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf95d253b467d91e924973f4ffb0e62cb13a4242202f74d5fc1b6ad74f020514ea8a8064ea102ea80dca225848e8aa7dce3835e606801775b23b3f0abf168123a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x931f2e4f9d319c7f8109b35e28c6ed60e4f7b1b1da7e6782dd4815a2d594c7612cf88861ea23b4709f657b5b373cb6736818dd44d0f1be1083d6b66d4d1f00cc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbde016d9ec1cca1f3afb627309671f545ca5fb06b7802a3b7d6cf0685991fb38a15a1902cd6935c0c73baf7def535c8e55289a942b99523b54029bc4c7c56f62	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9f9695d97379ed15f8db5d2599139af886076fae0765160297380d827555be680d5f77408c0a92200738d8bb2b8c905e31c71951c56d19b1d980990c4d3df62a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x572c2e153444c1dc7a52a625f9b781fc8acc49354ba9f1ed28f317783e7eab5d4844c898989a3f909c33c714a64396239ae42999c5e6742460db758f5a9bbdbe	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x83c0c8d6455ae3ed768b9fe30d43c1701544b446c258d649e0993133d70fd0a6a7ae4a20c59fd78320ce33e9a294491359968f5f8198e094021b3ef205323822	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a174592dc80c11be0a1fa25b196f815794131ff5aa5ea5eae8735c3245ae292cb09a5fcde6ad64125380074fb82b8e563110b6d42004a33fd0b35f949c99ee9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59e07ec8a2a8c48b18da1ff60ba3b0ac1f5b97f516f6690a351a9d2446887038f541a7d4a432e6ed333be5e750bdf1de7e4f19bea51ef460c0bba31a7605d6ee	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47d7e6bf6dce1ee06d28fea52cf1229bc6fbf08f89f618b6ebe7d419cd4b1e17c9d1db5a82455026a068281b6fb4acd0767818a6faca4432b00f4bab76690f2f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd7bf37ed39e0372cc1a78ec14cdba1ef60a8cb908434b7e9f9d4d330f0747613b2738d3040d662b357509281fc9e6fdcaa4d5bcecf24877e79857366239ce1f9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5480ce3821d7073e0b9129bf090558acfd69a295290216cbdc3a9310484c4321f5fc786d081d5c5c916e729899ae6a6a16d6e969f641a151cb6504534604e911	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c6850f59b8e12ee35f6989585a9402bb0be4063d99d4fc6812771eb1a0d192d4b473f41bf36f36d1e769aed243a55f1282bf24b6a94f45a5868699b05eb68a1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcafde91ae007571b4532e494648f22f5d3aea5d6e965d333f556992606a23c73f47a2afa936cf64cda6ac3ed0f0574f49700c2879d48843fac714e1dddef76a1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb22619ab4b891013af6d4e230f3c31789a645a839841cd4a156c2f3ecead6c8ab434039b7907d82f90157ae711d844cf93420cfedb0b2ad4f20ebaf185b80fc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c1d1685f0633536bbf7e8fae7170a2ba01b920ebf8072ffaa07792e8717fe6f957458a0f90e9b7cfa74635051c59b51c0ab0ef649be8146a8f6bf9fa675ea79	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8293f2046ac0d84bbaf7a581e37a99562ff09f4e1b97f7a68b26be14e5711bc2e89bdc4fde26f43deae3cda40ec17c75607f6ed6aab1276a60f75a866c2c133d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef8da5a8b7c269e56f032ae83c4c1f12ceb25c8dbeb60a0b043838a47ab1a77a7d8fc4f2e36d26e541264e099826fa716c2e4600a6d46f702485f1dcbb847939	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf8a5067bb88cb1af9c09f0ee472ce52e1ec6418bfed8696e7f368cb4940e42c689fa6fb582f1216720794d5dfe78fe9a79830d6e6960ccea16d415160f369a90	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2454961799cef5b34cf630068d4f8c1d6204214af07d72a8237ef647593a8d649540d531c2f02248de008cce76409e05a100c729034dd330914468268a77392d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x320372cd907bfe5e64120d67a39fb1d9b401c2d882023f4ebdf8f5f0a6b39020ec9bbf1b752bc2366a088f7744c16b0d54bcbd08c6877bbbfddef4a7cf7b79b5	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x985260b86adfb640aec62593b36e9ca32fa681f727d57ab8929b563832707f509948b64ca53f03ab6236ab49c8eaa4ee0c31170e092d16d650bd104f0bd0fb7d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb330743331a0e8a60cd017730a19872a30984c8f21aaf140128e0492bfc7f506e6591b1337e0af63e28a36e66c09dc78be5a00da414f8057694c6b1af8dd1d8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb050c41bff5e33867673131faad19143cdd0ea393decb7ef4e015be2bc8dc75d229a9cd5be9b7a8253abef6457a3cdd387dc56a9896b69d4c94290d622035d07	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a9258fa3cd28822e1d04d45bcbac1a3d20d86ad7129c2c8075133c6a05c1fe132e2606e780cc2ece2177ae34fc280f322166eccae969c5a8791f9064cb30453	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6314e8570c42874bc3d6629ab222352bb261dad0b129e9285eda73444d6c66cf15f464178e0a6a17dbdb4246acdf0607950065451187a5103ed5c1e38d3f4a22	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x726fcdf9ecc424db06b70595264975bb2719e70f1a278e5240b0f47faa3988e70069bc091a33613d831cb5c69284fe16a264b400a828fc2ae9b5cc8cdc42afd6	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b6c0aeedb5c6e1f81accb778d480ac5afec94b1d05fd60c81c2c4bc46fe7ab54fc35c083655be761318ba1960a69b66b75c02e2433a129ef6b49317ae4473db	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x893c42d4d601711eb02a62feea283a4b50f769ff3b3a4d722fc405d505843fbb6b6e55add8e17d5f238446560f5456b63e9ef1b8bc82c44949b58dc7f302afd0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa59dea0941367a9d376cf85c5989e772f5bbcd147dac39480209955b8ec44f76f5a6d6dfd5d58196892667b6607c0297c9749e38ec72933e851f31326363a543	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5b9ed1c63b4a8a5a1ffc3269c4eae33eddf55edc8d8993cab1b017163f2e98202acc05aa629acfbcdbf6fc56c32828e88a5a4cf65476482062b8457ced15ceb8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x291bade101937d007169a0821f58facd3f21ee36bdedd187fd10680b253428908110c47f6344d476821aa6613ea203df450317502cf55d1c220738cbc9baca23	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5fd7968526f97aa534f17761149afb99ae3e5356bbc1f44d00a5a51596ab6f8b0a4c35ca1c5df4f1f55b1bf1611fd1ef18706952828d4f2b39ed5fad82f7d84a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf86c561d149023e701c5e584275f4b077a342bdf306d21fcb3b64af61f6f92e2e8d1d7c4aaa6bc7b9b6e4d83f30c4f85109d9f2d09277c963d654fc29830a13b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x138b542f71c4d116e793e52dd2e74ceb55724ae0de0544c602eb70941badd841925872f66143305689119dc635cb671181748fd8bfe69a1feef79806c63aaf63	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc6482e1cf49395e71e798cfbdb6df0b4b7f4b1dd1d7fb651b1be3ede10b833ede1685ef0068eac1e715b21cb70248dc35b9e2a8c981d49b44e7be1645962258e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x83bef53a26941638cd49467d07d2942cf8f1c167c74e95fa873c53b80a3b7e0f092d46466e5b13c4156f00da58f0de2c3373c215b8ce4d357c982a44e80b30c9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99e0a696ed44e8ebae3c13d3faca394eef975d120c690e66203a5e7307cf1a87f41b75269cc3d0fd214f82aa579a9b99ccf3a14d991aec9acd0fb9c211849e3e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8265771a0b90cbbe5f6d8520b9e8de05bfe2ae1b52950678b3feb44d3bca08452ac800a4eafe7cdaf895cc7ec7250a3b33b3736338140ae6e3af4bd2bf23d6b6	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ba2bd1fb1bb0a7cbf7a530590ee673d2e7240ad000bbb4761d6476768895656a59e3fb9001e44df400eee7e7cb8278552fcc04968eab748fba2526013b06eb7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbb9f5e5df64023bceba2f0ef68529c12b91ccc616ff58502d926372cc5cb652f875ae3965ff7b4300a31e453898a99470bc6da86c268a8a7e9ff886d5e99b051	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf22271e521e3f20e3f7851a949be48484ddbf6dd38085e561fc49f4eaf4d5338edfd428e07504a1b46503a9cd30d222a2bce6929d49d418dc1087d8c450d2980	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d3eb98fc5ad0f154136cbae181aff930b23f9ef2cec2788b46c61d172a6a7990e3cfb01a88030a6c169d41b99ab099f1ac46d707073b4fd4f06a6432093edd8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x338ffee963f3b1f92079473115273daca79f95c5c0de4f19799dd75d399b10d1a27271aae488e3057374c7f128787c8744cae25be88b35f91aec4ce89259385e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3cad8fd778221b43e061389ef450175acb050868dafda29f52155eeabaa6ffc56be70d8af4f730f8cf0455f0f78d795547acfaaa0a55ef94ff6861828d000fd0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2db3b0a1a67ad6566970206b06e0bff202bfabd28be8deac27a640bff91516d7336be86c4685041a9f8425d4fd58e42c30c7da220b50607e8385be86ef3dc1a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08d03c25a8fc2673f925d846a7038c7b633dd4d91afc545be3c060897eea5a83baabdc8cfafcb67b15e8917a65febe50e91086ef3ccc2d92a7864548321e6b3e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd508fb15f9f7d586f040f8f1fe4e7af955783ed37a1286d2a9cc5bf718c21629c88b96379ed471d04c2a5596b24d6126dc15ab6a91491b01c2d2b249dd247016	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x73893c71a90b934df0d47736bf7c57fbe1d8f0c2c34c32a551cde9e6b0a641a13ebd69a6c2e5bc0036ba0285c661e0f7a06fac5a5d4f111f1d287da4a6bf93cb	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd1dc6143f762268c26a84f37a3631ea3b3b26797675b9060d6b54f719588a0f0be2c1c75051eea9d815a5acddcad2454075ccba1edd52c10835e08b878a86ac9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1895df0021ae70b33ff9f047c7f8b33ce1398937d789cb7649cf73b7dd5f69c38feeb8c48a75c77d18c69f2beb4419758c3aeb2be631f08423c9988dde2838fa	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8b586d2107d11a4298348f31f080b297644208955402ea17ec5b69aef986ea8f7ed55c720cf1aac43cdc2f51b8e7bc98b455ef9430910d89dc82d8fd0deb921a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ddf7507ce24586c977ecc558dd65743f8847b35390f3d9c6d75046f5e67152275807e014f7a2659260cf415f89573e76b7d2711cb690f5ef4591b468c2793da	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08c108861d20730b4078bb357dc9b801a4b6db0589b90b26885f6032cea71766ff7aa7bce983d09b9405be8acd6ec44cc2e494f0b80a16dce1b36252ef7f5e3b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbffd35106d37f68c3ae397574594352459ff4c87b2ddf6be6da5e5c92a54f62fc9c2a2e6608ded9d54d6e03cccd73c1e70db05763b0a96b46c12fef6352e19c9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x049cbcf36b05dce6e956df586cda35715161f75d6638645890066f152084a3f86eaa7188ab0bc1ddea6e5f0274a907a4ef7e3385dc7fca10e4271a766cfecb2d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbc338774f756024cead9235906c9a33007f1cf99813ed9c4794bc72856992fa0e30cc362dea6c85a7da321bbfd0a4441ddca022d8a96dfb88f53caaf61c7efbc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x685ba2409c223ee21aed57b9d7d482a7adc9218b527ba5b5043273ff3f9ec6bb590782ea3254cdfba53cb9fcaa23907f06432bcdbcb98fe3decdb7179e7b462e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa2c27338a0df1444d157b2acf6c0a6c3c6c67d48338c55d0cb44ffcfd7e37874caeae0d7313b2b71c251943acee867cb5303bf409567abe77678afcdcf116c70	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x653c4eec5926dc535a4b9971140d9b46580a22b3b51e36b2ceb4b35de357af7a0810617904777ef3a0e803337327bf7e2ee68a9b181eb759d871ec90d8aa1908	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd945420d62ce2d2b551acbca144ee72804c58b6baca20163ff870252df72c4575065b6abb0d910bbf502bbd137818f29b4c196814dba161141d7d3e834bab8e1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x158900494e8f7509c4b1a4e32ecfe09ad8c81b6e720971a4e8377e848649a796da6cae350661def3f2e2c9a8b0885e4fd31fb135869c6a1713ead9728a29bfbc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x37436d5a9022443f94fb64947c61441398794ba67734614257688ed04c79e52ecea61a4e0ac92521a62a13549a3287577c6ce6883e804091f68e53dbde27dfe8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x26b349283302b6b8bed809419f02e23151b9380184b90e8d4f055a145ebc7fef7f484b939e83e5fffba78502833fed5a17cbbc07835ea92931fa14dd4166ff19	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f29f10dda7e4ad7731dab46809ea12b244f3e5e056def3179a8f7bc56da41216158a5e05eb74dce65aff22c0352b58d211ac543752f5ef49a80b3fa46c69051	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x149880c5f39f7a93115044a02231a31922ba76049b107a633675441b145caa750efb7ee7c29bf647a2faf0da6bfdf1d5e536d9958c49ecf92a39ac99c9c8f9c6	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4b0dd11da230c2468e01b066d95b0aac9c753e4b43cb506d1995aa337d2bbe21cacab882b4d1adf38e96e13650fc9783fed332b586d8b0636cdacd6954b44b31	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1e7a5ef7de1b7152b376d988f6142f79258bbd4f64688fb8279bd803ef4e280e0171bea8bfd01dba6e2c8452d79dc8a812ed8f7ebfd632a5539a38b31821eccb	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbcd792f973807105967b5d6aafce1c6d4e91a2080551717af997ea59053a1fb8bbfb224eb02db5ddae466d1b23adb5caa66815929cbdb857150a247526bc99f4	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x50369fac14f7042059ea2e4af4797a2bc24461cf30dee64520890322a39e792ce1d047d5d26c8d447073664b62e433f28cb337caef5522c360a93f2ce542cb09	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf3d591805867d51063fd75c31b53263f96e2efaa0e1d1866f79c96f0f36c037a43ed193bb77bd09d80af38b2a7e4aab51f98fc11a2e05828325dd4423b87b844	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x36272e05199f0413462ea8614e1d07d94bfc42f5a0de11a669abe0b19c28dac849af0105f60b06dfde1bf38d83f1752f459bb09883fba5570076fd82d8ff75b0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6a090cb109c500d96390a8240d3beea0d349de2db4b81f7953cee6200bb5b7d3fcf66d78d405ca4aa1b1862346e4f5933240defd1e9cf5655bb616d0da99fc0a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x251c0bf2130dc11720afc0310556f8648c2cf154ac5e21c048e5b47bdaba5965cdde240a4cef8c66298a1a06af4ea59702918d0ce91e83e2529cd495cb325a66	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8808e5373d76bc632f204dc5451b75e8324bfa680ccc5601bd351d237af643111806c01fa2ea928937ecac393ba5103056a39464fd8c6b2802768ebae43b1828	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x61c7395562d25b8dc75ac39a132c0e94343987e8fea70e19368189601f4325f2d3670d5d4a72a55488b12d79d271893c991fd2b2f5c3900eb34d4c0fda07947f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xea3645e4170d015349f1ec6149257477cc77964bb9284c388faa8c561c8b14a0c999a2d966e257e06b1113c200b51bb2375a18d9d229e6cedab60e53e2dcb4ef	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x83b2a1f8bae1f9f0cf5e1c159079e9039a665db83a0ba0962868981b64aacbfa7d1cc0cf72ed926d6a6725bae5a26434f71bd3363b867f1063f85e7107f3a927	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8bec43b081da919a989c0f2b635d5773437668643f399537b87040b8b3e19154062e92cac710543efd0f5c1a973a667b9b824c701d348ccec851531de7c0fe8b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd7e6a123fde320d4546b3afca9538c108fae726ccacd096ee391633331777f5783e9d0c6cf93175c3971c78f6a80bf63c57efb9c94ae0f96779e3ed6cbed1048	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x01cc1922ab6015406ade7887d15c9b746232a8b63ae3d6cda6b2b5c303135e50f4a228fdba5537203c4fc370f014b194ee7e7ce124f119ba2e1e9fed4c7dada9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7ff43623c829b9cac909ab28f15e201c602e6d352678ca2b24c901e76129e166949bf16787ee6e666e0561eaae178752de0de5794daa01ede845f3695fac9e71	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x886ecb008fea45479960a0a8c8bed502646ce6860350b2f957216ee3ced0d6a7ff497a56e50016dec0c3fe78467788ead65b003366822ed32e17070f3c330d2b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc05c359057a4a42dd15e713ae79f4c54d1698f87aadd4dc94a3768ffc7cac7b2a677f911b39b9c3d31a7e72b416eba8c9bbd24d45b54e4c801dda67f32846b70	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x22edf12a0bdd8ede3e93325eec10bde61aee7d8a39a2c519bbb2d0b22f22bba2fb6ad2cb9549495475ee8ebd9916912a702291ef6e541d1ecea435cd16dbfc07	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xccac75f07656280f629387476b5018c6f4cc586578864e6a0a045a3319752e2d0167d95536a3bee10c56800517fa90ee014005a10dfa760d7d8f44a81f6b5f34	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x55c4c472924653fb3dc97157d90889d9c263da6b58525129a26d89b34d4430b5513a59c8b454741402466bf7839276e73173df581c0df8c51f91165e54341b6d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x736e3274135ac1dd65906ff1a1c2bc0c514ca49c32c849fdc5cee96d0ade27149c9fa03557de1e03cf3e43591a330994e0a890c21edb4372b75dda77fdb09c64	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9bfcc2715c84436e3e79648596f1b62b076363df60e2b4779ccf6384f814e52613958da1df3f8cbf9f328b872040ab4f6347b4c5035b2a5272ca3ef96adce12	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42f6ee7e3a3e891b14ac521e8220252143ed9a45f985d6287fdc97113229f7965a8eed9bd0d5be7e798093e91925418fa8f48718ef5a37e62da0d453c0b20af3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7711bee2ac49b453bbb38f6b8918cad43284c1c48fd1671afdb8ed9df4772493e5e559292c68f2ea833f96ed438f18ef13fc29645677d6e9f8d4fbbe54d8b7b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x60f7ba80e78226f73980c4c412e57a3a7fcd366eabb815fa399ab24450b89d20667d06141d00860d197d89db355cc5dc06f107c85475052f06856dee09e941d7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4aecb8510d2f0f26b716655bf9b8ea34e284d2980ca842c3eebed71eedb55b44be8e4c72eea2312c5d15fe93058578c2e38a4e471cae3d70a18a6b10374d985	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x263658fa1cf50f652ce5fe744fe146323288548bbbdca406437fcddda6a66bf90cfba8637d899d328a2b325e5afec85226726356f5936b5a833a6b70e3a0ecd2	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x155186189309612b0b60d931a872b4b9d209c333db9a0d7f43aa85ed2dc9bb18025e250a261e8b2c415ac70f7b111a73f5899942ed9e785c9d9ebe5e2d2f0197	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x172904ca3e8933b1c5cf8128f1703b29062e85b548921cb528c69f96a85222c1abdfc898c610630f625af3f665049d6b6f0be50315f3ad9e51a093eb626caa5b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcbf861165a682c60e77eba511f9999aeea13e403e2d4cd9c482b7c4954abe0171a48af38410e00727b15c357eaf76aaf13559add99352580d913697b4bd376df	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8afc2c12f9c77153b3a46f2d81644a9a72c1eca90560aa91f0ce6008ffeb4f824cac0fc06d7a7ff7715fee04aafef4dec09aa99d289ce4938964b0aa155234d6	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf03c698760386baf0444bff7f7763252c490440ed26c3529b3e6adcdb41c8e91987e8cbd9d173fff4742e1e13ce8e6627677308b2ee5da2ea8f611cebc2c8eb3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4003b8efbe7bccac7258202360acc440697f189f4ac0dc7856ec670a2684f21c321f46cd699e36c2bda1bcb7176cca07e9207355ce122c003ddf28cb77da2f0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ce6bf0d87e415b802f3594354c4fd8ef0c7e7c694dd0d36c2e8900cbbcd19ed8a026f6c462ec9d43d5a4d49c70cd718b80f3874d7479ccd6fd3b7134bd8eaef	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9698ab5abacf38d3ca9c6ad3e5ddcab96565073c55673906423b0ee78cf4867088fd412535fc595dadd13a49c54eeab9e1c9dd5047d89ad82a9664e8a744781c	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x92ebf98b7ed883bb27e2b5e0af2644db1aa72930b051d257a50db4077f829b3e2d5fc6e9bc9789993d2b1786bd1583eb3338812b74094438786e6757e78bf318	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcab2647bfca1f02baf8d4c92e491b0d4b3daaaa0652e3f296b8b12b2a98fb36672d7465bee6b7aa8ef5a7315a726c039cba4af844cbeaa7a92b40bca57ec9a0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcee3af02a9ee44dad4e9f0df21c4f4856d7ace3414eac973e8791a4449d7376e2860f419883da74a0371414dff5a69b39f7e43527b440814cabc76542f534ca8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xee0869a0d6a06d653bd4100f77981765855cffa436787db6270eec48704dee1b50cc1eab05fbcaca1e5f0bc751db9ddabc3e530a505626b1e47d7d973933d022	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x282dd5d93ea48372779e153ca1ee16f30e48dd6fb60eb4cd34275d82b056578dd5fed0f71bb6c03f34d675eb901568dad3dcbd91a6d9742cdfc50049ca108fa0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6571114814053c5d9a7e5971e57461014fb1491de18c916e97167dc693ddeab9ad7f0fb79106e2bb7621ef86b090ecac57472c0a6fd90d70a9f0f323004c6ce5	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x47f17b96fbb146258b135d0e178fa0a74543ed24e8fe00d9d93cedb703697613578c88d1d0032572af5b128b9da2c7610b742b802ff6a5b905d1227ec71d5c2a	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd95cc00513a2ab2b175957a5e60ed59de87a292363558b86bdab89765c3f78d2024c57e376bcc66c8365b39c9b3aa26d51992cc59036ce6422a9b103d5725a0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5bf0a0a8671e402b25e54787a84a9b0502a9a89469ce92192359b1e6421402160749532dd16d4e5540eee3e0912dbbb06fce5a899e2ef183ea67e911bb91ace	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3a33d7b9d124590f48aef1b8d3c382d7d619d4f66ff78cee527a66d76bbb3e5eea86ca51a85391b2caaa1ec9c95166fc546974adb9756c0e73928f9e0872b01	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d7c5b1152f24aa94eecf5c3a07782b0cc623faa9f58c1dff33b9e1888f6d67e1265a4f0f9780ee5134f5ab3c5f6a55d3bc8d20c8992d6339e850de025bca5f4	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x08ebfe873fee63f2988ceb89613f10f25ef55ecd9e56a8be97d8ecb915f3f357cd6ca70c85ea6d4798fb59c1144bfae48ac8d6a50db064a6cd40ba42de961552	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1924479d2976d5a585ece0522b497f7edace04f84a2bfd32db88f909595fbf25cde8555688db58996b009ab7baadd2d3903c49f6e1da6e85fe06733a85e2d877	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8765b6344560cf8b165468b4b45e42412fe86dbdcf3842751090da11d545ef976da4824f782527c2e299b9913c3bae2d17ce7a0a807ba24be19217ea0003d97	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f914196f0d50a590ba0e42199cb428b38a4c6b220d2270b37906d546b25cf0a74b56ac2d7eeb4638c3685c13936be36722ab9755541db69a5f0301228c191f1	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585243896000000	1585848696000000	1648315896000000	1679851896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe02ee89cb6dba4d1f0f153f248582a08314f118127333f50bc57e5a004aedd90b2a9adbe08aabd7e7a87dd7c04326d0736a0e16bfe0c268794b6e88c1e3d012d	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7cb9e437d1b66ffce0aaad5f8c06a60c4652271951750c464b097a7e6f05d5f1babde643105453e174db2ad3db39ae4214006d2da7fc23bee5f7dadfab75e19b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x34e216434dc76c8c9e0a5d806e04fbaa8a3aca8acc63fc3ce7e84731e7e6a3214395f176fbefc832b80c3454254a1194407f99d585282dfc42ef2b2d0ab81efe	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1587661896000000	1588266696000000	1650733896000000	1682269896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x87216455dd84fb31964625f002f0302bf1eea855f5aa85adf57922c2c690d920a29694759742a467203fd0cbf49321cc538b197afec26854c06a2e69baec6b90	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588266396000000	1588871196000000	1651338396000000	1682874396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8936a841801be0e425f195f42710573a445d2612e21adaef993512bbd54f22eab547323cdfa0e2b5fbea49df67a8b227014bac295df03d03e44ec3568e156d57	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1588870896000000	1589475696000000	1651942896000000	1683478896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa50b6eb889298915ce6525e887e14f470d22596d940ef13fbb812c321d366093d388748786ced1c690319c546d83745f00d882aa82dfe62ecce1c92ebe342962	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1589475396000000	1590080196000000	1652547396000000	1684083396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x97feb49d47e560c9aec89d155aaa1dae49e5ae93ac19021abbf9297f8f4d64b6af172d0ee3b5de6049b4917688f187f6aae20493c03fa232b983508b48a800f0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590079896000000	1590684696000000	1653151896000000	1684687896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2bb9fff26599ca42055bd08841fbbe890450f4b3825b2a326a669d3ed1ff8e99390770ae413733830302f80f80b8f5395736f875b01bb38df791adbe06c81467	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1590684396000000	1591289196000000	1653756396000000	1685292396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x44955ada20c33e154f696b2400d968c9e38fefa51191fc0b73cb40cf6edad469302ed533afeefadad229b003073168250fb0721731287535339599041c6274dd	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591288896000000	1591893696000000	1654360896000000	1685896896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8b8151eeb02830be2fe18a9d62edabbd1563739b08c54616ae8dd0fd3346bd80fb4bdd6b97572c587a6fdab819c676f44ab93d5ef42c4f4df472492ba28caa47	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1591893396000000	1592498196000000	1654965396000000	1686501396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb82583ce550a08e7df9ce5b3f9424dd6cb3d3608cf263c22013ecbe74f69dd6fe7b5d03842c539aef772bd52b60a12c81a291a045bd5781141e75c53282f59ff	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1592497896000000	1593102696000000	1655569896000000	1687105896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc3cc73ddd42bd49dec285c14e5683206abb97a5d5bcd3163dec86d014755e6e37d1e664d81eaef54910e0d88b8b0a13e7cc998c9f6eb25ea4d34f0ed15a10b71	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593102396000000	1593707196000000	1656174396000000	1687710396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf54d63c58a7873296d380e9c139395117850e49f947762ebb1f6d119b1f7abfd29f45280dd816d2d33928bfd3f603b0043efc03f318a2da3734b53dd1c6dcf9b	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1593706896000000	1594311696000000	1656778896000000	1688314896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6edbebd4e1a18cc1f123014ead39c4d08545bcda7d91d30576c5ca521438ebefd2c5e0091a80c67957548641e8abef5cb69577d1b4b79c8979ef8e1c306f21ca	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594311396000000	1594916196000000	1657383396000000	1688919396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0c8146dd63e02dc98780acf6a66d500756340c8aa9450cd509097a534ec5d951bf9b2b3062f2612f171db79c134022bd0fbedcb637b3fc5084fd3d9e6bd9c5ec	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1594915896000000	1595520696000000	1657987896000000	1689523896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x08736b9b430252de8260b124ad9e27b2e7b1c6d8323eb2e2eae5b2be3e3004a9263da4069027d83af272295484371d420ddfd1d30ec67d463e04757def673fc9	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1595520396000000	1596125196000000	1658592396000000	1690128396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6ab853c5d6a882a576a83b1a39e002b553f67c837db670f698ddec9c1732cbd7afc8c195006627b951bddb1e53815c560a1202f409bcfe35edc6e08f68321cff	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596124896000000	1596729696000000	1659196896000000	1690732896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1d7bd8c86e18208c81cc89de82ed3b82d580816122ee7ff757addb127a9fef4f83dcbc13f36de4bfda7e8339ca414a1981a4f7ab86b431b52c66305cde505623	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1596729396000000	1597334196000000	1659801396000000	1691337396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x43f46708e6b050349275d4cdf246bd1eb94b8fed63aa4ac53aa93d1b8513b9c06a3456fb4b8cb46e6eb9ce65b4989d91f2f15920fd7f798c54d4caf4c89e34db	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597333896000000	1597938696000000	1660405896000000	1691941896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x264e8abaf84716b3749c58180a446ea32c4c32bda3b712ef49817c1b9cd5d942a5a4f3760ab08f469fe3bd14b5ce8918e154959c095c44326cb9f033fa7c4805	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1597938396000000	1598543196000000	1661010396000000	1692546396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x116ac0bbad84cf1d5f1bd012b3fec6cc4675bcdf9fe1354add018dcb3dd187e828cb6039b786efe8f52905e781379cb49ffc89eca13603ca71f999e38a8e74bc	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1598542896000000	1599147696000000	1661614896000000	1693150896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x343b78f28150e9797697fd7a16cb76c4ec5d8bdee91cca125f51448f455cefd50fc225e102fd42bab4ee4e66a94275109aa1f7b7662077aa3938cca24ecc86bf	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599147396000000	1599752196000000	1662219396000000	1693755396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1a3dbe75f642013194485882f1b7c46ff0243128a383616d8ccba13ec8b966e8559c541ed37923f2e1108712f5f6f068800a2ccb4b03503317127406eded1cdf	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1599751896000000	1600356696000000	1662823896000000	1694359896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9459a3ad66d5554851eff4a8d021598fe612264311036ceac098774aec4316b4c484faca4e9eb61c12742aa28b01a5cb414701722d49a43b2c7baa422b6c7df8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600356396000000	1600961196000000	1663428396000000	1694964396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbf21458855f575fda11d8974f786cb26a8a7f7b985de3b94192fdb9bcd02d47b46a106fbd9e6b404433bbda47d6689a1d75aeb149dfb2e237273eb5cf0a439c0	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1600960896000000	1601565696000000	1664032896000000	1695568896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5a2e61375941ba59795783919e91e50c9749760c2df06721130ef705822a0c58f10adef4a314eedf27438a0a3c316f36ee2c28048e55c453fd4ba4f1f32dbfc8	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1601565396000000	1602170196000000	1664637396000000	1696173396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9148d4adaea5718087bb6c00e5e693f66610e2360f59b08e2b0000ceea38d8dbd12064b965ad8c6d5199b439d6d44d9f2ee8911d2923e6cb12dc15919588eaa7	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602169896000000	1602774696000000	1665241896000000	1696777896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9362a859b931d74edb4bd4770211944aae6355d553d2519d4e56936f2c83d7600923a467c54801324cf0b84c50a76c25b188e40364a16b1cdf0e8b4b5646b01f	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1602774396000000	1603379196000000	1665846396000000	1697382396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1c9478e8a46eb53951ff22a64126d28fc886b1417379568e58eec36cdc76c3bc43d951fb72a298a8d9399c9daada47f933c61b5bc17dc1a81cea2d9813c88811	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603378896000000	1603983696000000	1666450896000000	1697986896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xca853bf006167655b8a9ee83ddd91c16a2304c7ffd9d5fcee97d60bd96e238d2a87f1ae01a6ec961ff39d07c768a73f3bb41e67c531e69b69937e6b99c871d83	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1603983396000000	1604588196000000	1667055396000000	1698591396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5251dde7cb7641362f6ccae0f76384d34cd34d9ccfbf12f4185bee6864d006a46b6b23e86ab945589bdbf699373d6d9908562dc8ab4592ce0d5bd20bb425b3a3	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	1604587896000000	1605192696000000	1667659896000000	1699195896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-03-26 18:31:47.535464+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-03-26 18:31:47.609047+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-03-26 18:31:47.672122+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-03-26 18:31:47.735955+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-03-26 18:31:47.801497+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-03-26 18:31:47.864901+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-03-26 18:31:47.929843+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-03-26 18:31:47.994339+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-03-26 18:31:48.413285+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-03-26 18:31:48.836385+01
11	pbkdf2_sha256$180000$FGDdap19t1ub$ECWJXqJh/yV+o+1XJKeOPyJMbBidu9UP4rbSc7wgqDE=	\N	f	testuser-A4bLVg2t				f	t	2020-03-26 18:31:50.599445+01
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
1	\\x320372cd907bfe5e64120d67a39fb1d9b401c2d882023f4ebdf8f5f0a6b39020ec9bbf1b752bc2366a088f7744c16b0d54bcbd08c6877bbbfddef4a7cf7b79b5	\\x641a1454d52626228552f234efebd9e016d0ebe9afb49bba10d218ebde0ef4e9c31ca59d61c965c18ed0e4e5d8f2fa95f64b3266851f676ea0f7b8c80f966803
2	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\xe299c9b69002d16385df4a9c0ae657c5bf06c6502b19f3cbd663614a9b0a3a4d51e73deb6a70838e6d84a4bcca34fc089a018e4495b4ca8474290dac5a8a1703
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x3ef58d93b1ce275b9090e8a0652905a9bbcd5604fcdc68cb07c20c04f11e2c615b80c1891d3ab7e0974a1f556e329af8398d4b1a5f7735ecf23d7087890e3bb0	\\x00800003b4af7e765fd78a41ffed8754a43a54ac0ad14b6199388a904a2336e6553f5e57d54476051478aee73f2e69bc32a19160d03b4285885fd330d388a0a3c40b282993560587aaeaf7f96260874ebef73fbe6fc6cc2138df3a3e9c0d4499b53c0a92bf9b21f6377f3665ae1070a8b4bb9957f5834803cf132c980a7be2f1e17f7cab010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x5a5ec4299a8423db34d54b20e6f5087a4e21644711fca0f92d25a11d3742ba0fdec15942b3c03d776cd37956b8ed959ae6b95a141426508615bda15a4db4af0f	1585243896000000	1585848696000000	1648315896000000	1679851896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f030c49bac6181d3c0f27e1861b43697410632ae3bc04e785baafb2677c33e7437239c22af87ffcdcc9c8f7c3a241bfe1e4b0a895a2ddf5af96e055181582c1	\\x00800003d8e7bd311865f6c1d87ebd31956be2ccfdfc15ec6e589bf586f8ed213633a6de8bab527b7e2e16c3c046bacb6e6e3019eee0d03be2cdfc097379922eea633ae7dfcc4602c89ac27ce46f46a596b87b9198ede54c641b43a4241aa4810fd42cbb498f39a59f9a0e9d3283dc4840a82a177c2491f12ffd253077cc3070b919928b010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x1a7ce0ee527bfc5e6afab9df9a0883ba07b7702112a8a12992ecf89317acdb8299516c934fa9afeb662c3eb37658e2b6bd8c7349c055339b8a03fd0e73b7760c	1586452896000000	1587057696000000	1649524896000000	1681060896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0adc59377119677c1efefed5031f9dad514c31138f0f39f22a899fb3648522f5f55f75c007add7a70e4a33f2e96d53579f29819ec13a31f2648417468ac134e4	\\x00800003b52247e54e1fede6e9811f4bbf8a930d9597123537fe1159fc1a703e707dd8aefa9212f939bbe6ac5f3d703d7ad7ebeb5d6184850d180ee12589c2fde0487aec7db215e474d2f03d664f24a7c70fc028e9abdc82c6f12e833afbc634b93ea113b8d79df1a41dda64d758b96f2fff100c0067813e624ba6eeaab24b9b3d783643010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x769fdefc1e85473caf95ce96195f80fda1dd6607c464119867d60421a3c5282306e58c8f81086135915ea38fa05512b1493fbca5d9707f172cdf34c8d02ae006	1587057396000000	1587662196000000	1650129396000000	1681665396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53e4f5be8e86f7c0c24c5c2160d406dc71af17fb586c24b693a65cd6f0cd991fc6903811dcf5d6e7f37bd770ed283360a696cf74d5cd0e85a3738d356db5ec12	\\x00800003e670b2f8fd7fbcfa917d9589a6c45ef587c586f57b27785cd357fe873c9694463344d8bb2daa0e335cca3c2bd125647540d77bef53dc6feef1812e47fdf45f186655299cfd52b17aa14eb03ef56434091f64417f8ac25fa240f252bd68aa0349199d84cdab7581b01a7137b635c2693838b9829bcd1612735b679a381d2290b1010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x49ddf029ce305510e2c6408e277b71ca4d0e21e9f4354e736c265d3829be425df62d495f8c223261d006b34119c8446beebf4885f686be7d2d6c96dad7544906	1585848396000000	1586453196000000	1648920396000000	1680456396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x38e21bf89d97b78aa66d40f44b6dba481002beb77c4014e2ff3ccb2e8d47cfd55d566ce87442b68da0082a7475b928a10a6463e6856f050dd6f027ce9d5b7efa	\\x00800003a409091e3136ea75c7ebe378af19452644a787425c54e588244904b55c298bac7fe0a6808f99f38674b5460a6921736d80a3c5375ebe38c0890a5a494170e32c7cbe8c5e494d1e1bd63ec73ad300e2c20354bd32e72b88107781fdcc7cf67632f69ad8291644dfe63a7c363243f7b206073c22e0e022be4026f8749cbf5c5a93010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x3d1ee58c104258ce3126157c177d5883580de75d75ef4c7bdad342cdb1fb99bab1f63dbdb472e254173a6ba5c3ef37d7465d9c7c361781ba74c3b7d3cbd12300	1587661896000000	1588266696000000	1650733896000000	1682269896000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2df58ac0a7f9bc1662482d628116339ee319b7499c6cd5dadd3123d48446b9baed0907639f1cb62b19e2343d5789ac477ba55ec892a640e17c9b8322cc10657	\\x00800003bb6605f5b88dbee126dab63c6da3d1e5d009dac6b4244255fab2981eb840f612d92d629ed053fbc2f96e404aab4d3236dfdb8f1c591caa71027cf7fd2d789fc5440b50b25485763a313f2b55e9cb863eed8415b2f33407dfed6541e7ac523ea160c8c300f923670ea376a6bf21705811e812331a016c69929268fe48e4af5b4f010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x2e4f25b96ccfbf9dbbfa90bd113ca17b27854e1a0a1bfabcfd70f15660ea55a1e84466884914245e7bcdb26418a560a61e326fd233b96485b90355f561a7de0b	1585243896000000	1585848696000000	1648315896000000	1679851896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x87cd6908495dc978d1bde1131fa9ea316bb850f9b8e2eae6355c01808072798699b98889927ebe0089bfae4c2fc073fef5fb789dfc45ab2de30c9f27b2e903f3	\\x00800003df927529ec585c68c93f55269aca9b01c0849aebfe4646326144b080dcf31d9450998c01169d68f5012adf262e9b3f24ac1866d0a79f868f51b7deb7dd48f65c1f04dc456bade5af8bccaaf670cd878d7a6a08939988b2ec03a7bb6a56ecb59ada4f4835b3aadeb70eb500fd661a97e8820662eb333fb049f8b91e4cccc121d9010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x5988caf3d7a327b4d702e17c5a27835586fee0edc0fff72ccfcb2de2cb82c4a6862f3d570440d40c94e68256f396c0257ce18dc9efadca59f63875b0ab874e05	1586452896000000	1587057696000000	1649524896000000	1681060896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eee30eba2c7c557b6ed3575f1dda90b4b63903f301826cc649d47cb107966e3ef16677c6a1b27db53e55ea2dfbc714dcb37db550fb62b99990b86af58399d87	\\x00800003c6ff11a12938190ca6ca99f4e2753a9a2822e36b8ad248f40bfbe327144f32074eba1bff19f527c4153bd64d2f8e3de5c01d65b91a8506d35a4760fb41f722bca58f727190c9fa30320082efebf83a74cbb33f03c73a9842aef62efca484948dd5155adf67187e6948012bc2d792f38c573ebcb254e5ba566dbf326e6590583b010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x82b8e658fa09e308fe9d84d68c3c28539dbb14b21df7408e1c4c04eae8bf26a04a6a329e7a58e1a143bfb0400be7f95f9b38f96dda76947f9662410ffd032c0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc75a0a63e29c8ec2d2e13bc182ae982d342d728a54df92a27d70a861049980cc59f947ad7ef1fec6b065b1859cbb67f4661af1f593fc19b928e7c3980cf9a9a	\\x00800003d71d2e08ec9c8b04713ec30fbb1cc7d5276fea735d87a9cbecf50f97947564cfbae1f9278aaa3f167337742fda220cfc28934ba79b3222a7ab69b9707a822769c29204d343e3b68350e45f33f2b47b3dae38e168ea69b9f5ea5f51ddbd0bc1a2e83401a4357f1d3fb9ca953555e5fcad212c03e91a17bc0e9cf62acf10a29e53010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xbb104a4af6b8fca712934f52f72b0fda1b3600b3ae49735fcaca34800f6876924aa63fa86ecaebd42c3d21d44ca8c806edab89ee066a866dd332a4f10f634c08	1585848396000000	1586453196000000	1648920396000000	1680456396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86ed10e3ae3c24d9df37bd544245bd1aaa9be003cd205b95a1fd6cf6e7a78dab21525a6e2c45d61719b26f6717af5d7e9510841ec7bf090ba0bf8a87fc857e7d	\\x008000039fd25c3614f44b22554844729263ed069531b18e75c2df98388b65d336fdc45f25c7b6b3c002e8787552564603381bb3050f173d20f361764420211188f0d2b4344a8b9d8031b2ec1687f0cdb87d9a08d6b7feb074338b185effb55bb9436ab264ce7c8ab811ec5d66c550256a5bb449abc260b4eca08f8ed7c3dca43dc0e893010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xcbd9b082a6ddc66f8bc2d0cd7a9a8aea3775dd6ae9c8ab90d7ba957099af27fffd68391684d7f4cbaa4075d8d54323890fb58d1bdcaef4eb88aae65cedd2340b	1587661896000000	1588266696000000	1650733896000000	1682269896000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x320372cd907bfe5e64120d67a39fb1d9b401c2d882023f4ebdf8f5f0a6b39020ec9bbf1b752bc2366a088f7744c16b0d54bcbd08c6877bbbfddef4a7cf7b79b5	\\x00800003c29dae25ede7ae198ca3f941ae5cad0bd8648513ce6840b8573bdf671fe58af4a2ae343e856940d59adf7b0d2a88e79470fb8b522ea4a936d3b96e441592b6e08f2ed613162ff41cf06a2cda03e1968efaeac421a7f53a7a1ae7abf3957662643c132f74d504b3581f6ee9209c03c76e48fcd7d0b96252fb082ba0daa5338abf010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x67da0a88ffc9d34e39c8dba91c83dcd823ed95d80a82c61397d5be04a31951a1b5981b6cf37e113223a90906907b01c42b3c9d9b8f77cb20b4a2c06f6c17530c	1585243896000000	1585848696000000	1648315896000000	1679851896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdb330743331a0e8a60cd017730a19872a30984c8f21aaf140128e0492bfc7f506e6591b1337e0af63e28a36e66c09dc78be5a00da414f8057694c6b1af8dd1d8	\\x00800003ce37726e9aa3b7ed039591e58d2a5f3d020d16e5c4d81fa6868c5199fb9ff9ad6a2be311b12938bcbf0b7433fc6702b37e23e7d30573e71e2434370ff5a07b671210df97c8b30998b0efa7efdf5028b5e12968f1793c98514273bbf3d7712c4b6c1d423b9b3cb1676123c1d9caef7a9a767562fea3b8f6c15f55bb449a90fe7d010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x37cc945a790c57c9f5bee52c5acc850ea591303cc75f3a011818806fc0b85e1c96664de5efb7ececf85205db0b14959f703295202a94515c5217ff54d098780c	1586452896000000	1587057696000000	1649524896000000	1681060896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb050c41bff5e33867673131faad19143cdd0ea393decb7ef4e015be2bc8dc75d229a9cd5be9b7a8253abef6457a3cdd387dc56a9896b69d4c94290d622035d07	\\x00800003dd9250e2e527ee0ed9e78b3c3e5ed0da393f4848d5c33899fc640cc15b501155fa45029d2f805b7e64aca5a6d37053a7939578ddc07955a5fe34c3df0c814d54736b133a00d2c7b1ade93dba1ee14a2ad89b9e7878e47304395eab2c7e475493accdf40e79d4d4d8d593ac6d71a9d469dfb7d8de58e5953306306529d406585d010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xfc3fddf8904051af0b3c4383231032e2eacba0205a73326b1d0218c65cb1bfda771d6bfe02bfc88e182e71b3424057df3ca05e7cfbc36cdb9e8afe2456313803	1587057396000000	1587662196000000	1650129396000000	1681665396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x985260b86adfb640aec62593b36e9ca32fa681f727d57ab8929b563832707f509948b64ca53f03ab6236ab49c8eaa4ee0c31170e092d16d650bd104f0bd0fb7d	\\x00800003e5dd9c63c2c5c0d3f2b5e21333814b12605fe2c325ba4a1abb968492f4e17b47ad8f470288bcef18e9bfe82be3b285770c731c8740c9b252b41a0adac3800ae5f5987f7bd462e58acc1b7963c5dfef5bca7cba4abeec31241e1f0ce16ffa4e2a8486ca4794f5a47247a481f633e7690c0bf0236d3706bf9a2e69f6249abea101010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x2b38c83bc5d4017f69024523f10ed88a3ced789c86b3051fe6a6f2f8a645632a083c743f354df3840893f62a2a9acdb12a9871dd879e709b65b2be6f8c02a101	1585848396000000	1586453196000000	1648920396000000	1680456396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a9258fa3cd28822e1d04d45bcbac1a3d20d86ad7129c2c8075133c6a05c1fe132e2606e780cc2ece2177ae34fc280f322166eccae969c5a8791f9064cb30453	\\x00800003c43f27ac76664ed3f7a750c36d073fc73fa4cb80e487c2e7b6dc4162644a1371553b2c251535d01173babfefcdee714f6a06c4bf684f4230dd41bf007905cf7da8c74472b06ee6d69d75fc0ddaa2115897ec9cb6caa58fffc1cfc51611187bfc70a2d55f3ad9e68efc8a344b5149274a4480ff65a957f7922f6d790cb0193cfd010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xa4969976019b4a0714d50be60c9a7291006323d9f613ac509a673f8f60d41aa92339cb6f235deaa6b59e57b56a8daf7f1082c53d3727c14cb75e45ac9ff49508	1587661896000000	1588266696000000	1650733896000000	1682269896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa40ec28d84c3143fc7f9476d46f8cfe27646c6ab74d12cab5aa4a6f745fe5b7c94596bac4ee1a3948421231620bbdd47bf406b1bb0bab70c0911f921f86ff5b4	\\x00800003b4cb93a1d88b6a07a449d6d4374c0d1efcc896107e61b7bd0783e51f67051ee458e483a5ddb695ff091e3e49a5d31c8034deb0d30c404cdaafb5ed66bf1e2d3d127ac227c8eed193ace7f55be37882b1a5eb4a025fbb58effd6a2d6c7f7b7497754ba0a465a332b4f19b306cbec1cf1272cd8cc5f9c1c7bd5a2b284f75a00fa3010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x95e92f50d11dc4d04c8af02fb37253f9f57fddcd43410c855d205a3e79e85f09abf45fa611239c8d23cedf172662f9faf3a74460884c53ae54021c874d0ece04	1585243896000000	1585848696000000	1648315896000000	1679851896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbb827f21f1505c35080e2f5561a82c06ed0ef55e73c4ea72094c800564130a0325dfafdb4c904145a7daacfc886c55a35bf3bd3985405b05498a2460b6571cdb	\\x00800003a66c2929894fc55cc019403766f5682a9fb4d29c8b836f8cca6859784a391b989a19d5dbd8b8edc0a3f99bb8410e282dde580001bced82124c71bfc79eb4f3ba70a3515aedfcfcf78a847cabac9bd1d7d167c9bdc28ab7c233bd4d312692a293c702aa2a27d9522ea0c83b129bc44c1be3878d111edab3e15b4c73cd927e53e7010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x747dcb3e8d099d76a00f5a5d589344a1a5f4bc31f2fade242d0cc8d7fef6bfcc0a251062aabc159cf4f6163ee89759d9825711882af558242afe7f6b2ca54206	1586452896000000	1587057696000000	1649524896000000	1681060896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2f9b6bc37204b9cd93c0bae02d5a68d145daefe004bacae9fcccf95cd30f0ec473f80795f8b644be090aeb849d09a16d4ac00d54c6e6abd8ccf03aee8b22c2b	\\x00800003c7afd79a3c22e514958697de0d844f4f84baeca2eba9f4ab6648a512a96e6acc185d97cc929997ac812000c6dc04e03ca5efda8ffb98154341a523f98e8cd6354725822172785484142f96156130745c6487800f738683b0696f625861205efdf5be8d25638bb3289db817077ce9ec998f8235cd2ee3019c5c9f6e1bccb441a3010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xc0becc95345b6b2946260d0e28062b703a3294f33d2c27e3a0f4a5c26e24d8b83171b2944fcfe075ef2a0b3ccd25f7f62e1289fc480def7213db3cf4f8b9d700	1587057396000000	1587662196000000	1650129396000000	1681665396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c67bd3b5ccf79cf725ae7e26125995846f4300ec41fa68e1a94e851dc31e5e3d3097ff6ec92e03ba3d0e69d49741c0eccbed5ca6eebe7a6032cc329774cc7ac	\\x00800003b60518d8d0433b5ef12a5042430086e694da53b0f35e27d18153f1f525a2cfcb6398e1ccabb71825bd2b41c1ea3456f281a6864b57eaa804e51302e4453e7eafb3a708cc1015536d823cc2d704bff4f3bd6a059240e483d3d24567bb9570d731c0f69bc75131ff67d6b571467a95e581db80fda643febce0984c734271b6aa81010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x3fb03648908bbf135a69130121db34a4c7b739817ebb9228974050cdeed971621b8433b223dccb7b7cd3aa19808cc63390726fb1aa7ec0c2c1d193f10ea06d0f	1585848396000000	1586453196000000	1648920396000000	1680456396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2abeebb7d2ab7c8f092a45566aa3fde6e9670ec9349fb3d1ea3388ab3b4a6f29193b06d87f0e8f58885cd0a2b9c6f0d8dad18d8aac009e8cddb3a6856532b33	\\x00800003963df7426af5543527a3f99fa50d3f3a801b2a03e5628ec6cfcd1ee21636718a402e4b01447456734c1b8537b7f0b012262901cb99c3fc4488d36330fdb186c9a787f29981e9ae463bb653bff6c0e4276d0860bef48bb18baa41260f740f788455ff09ba2ce5545994dfb6410920d03524e6c67e3b477871aa386d6452809f17010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x47a1e30dfc383a00da519a1ff0fdc9785e5c6dcbd21b63b142cbab50c0e79477e2adfc419ecea4445b98160017e59099876e10b7c7dfa113ca79837883a4b30a	1587661896000000	1588266696000000	1650733896000000	1682269896000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08c108861d20730b4078bb357dc9b801a4b6db0589b90b26885f6032cea71766ff7aa7bce983d09b9405be8acd6ec44cc2e494f0b80a16dce1b36252ef7f5e3b	\\x00800003a7f5ec1921dc15dcc55a16d4ad7a45ca0916a67aa6913c861f5ab17bb1927f3111e29b5810901bd2cb6133b34ca2ba6134a3b7e781078e9cc12910bd2a0595d0bd023c8924e2257d6a244b8edeaed45e4c3554dfdd246dc4989a62f235cc390f29bb9ea4ece609b420158b112617940bbf1749f32b70f115bcca016f43478c8f010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xef409881d2ad39ff7ad611622d6d3ed79e7ab7c1a0b05d8d99555fd981afd30eef84a01832f99e9d0f444e59647f4e8abbf637ecac43ea8e40ce531ffa889c06	1585243896000000	1585848696000000	1648315896000000	1679851896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x049cbcf36b05dce6e956df586cda35715161f75d6638645890066f152084a3f86eaa7188ab0bc1ddea6e5f0274a907a4ef7e3385dc7fca10e4271a766cfecb2d	\\x00800003c8ed3bff88fc99a0c03a4a8e60c9f507fdb8f4eeada11354f8a0f95ba466160df332d4c7c2e4e58e931cf4724ece8e49f1337708a0d4bd5b275214f2cda9a38822bb39321d61b5b901e416be1da16261539b8c995765cf6429137fae2ffe611812a6f29446d000a26f400c93269dd90f20d42f58193df6a362dd8d70c9492c37010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xf5db7faf958eb1c77b45127695dbda7ff40739401f9effe595341f03a0e34d32d244eb615127073071325e5ba9301b65473616559ee7916e97bb86011a73ea00	1586452896000000	1587057696000000	1649524896000000	1681060896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbc338774f756024cead9235906c9a33007f1cf99813ed9c4794bc72856992fa0e30cc362dea6c85a7da321bbfd0a4441ddca022d8a96dfb88f53caaf61c7efbc	\\x00800003ad94f12f63057c0587658e0d41413d556a1b0aa852211555088a32799c2f576d35c226d5c0a28049ae725ce761a1466680a6217c6ad788cb63571cc748077c61e939a47e1c96249114656018bf3375e385d4d2a5130d56a2719bc9075abf78aedc17beb111c921fba365d4c8dca1332067a0b62da7499a6ee3b7a01d974e6bad010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xc205742cdcf327c1eb0c156d2defd3697d2bed5e616c4563e3bb22c6c1631748f939c27030df02ff7ba13b60e39acd7eb16c1b0bbecbf806b901b7fdaf706600	1587057396000000	1587662196000000	1650129396000000	1681665396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbffd35106d37f68c3ae397574594352459ff4c87b2ddf6be6da5e5c92a54f62fc9c2a2e6608ded9d54d6e03cccd73c1e70db05763b0a96b46c12fef6352e19c9	\\x00800003a5c4de2edd55ebb74364934f7cf3e4898a8c705ae5dec84c4263f01174f76d1852d6b838424b0506ea10524a94a5a5371516adbed83f2128e2f4dc95c4e5a66d6aebbd3a27dc4c40cb072a42fdfb97dca3b2b4860f78f7df054641a2823ab11625048e5abd3c7284045652cdd07b301fd38fc2673cd6a1e69901fa151ab5bb8f010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x6ef74f9b009e8432847cb9d7bb9eb19b2927bcb90b4191bdb208580946a11733b1ed983776bbcba8f5da7968b987f2670d6640521da5cfb1ecef11a775732506	1585848396000000	1586453196000000	1648920396000000	1680456396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x685ba2409c223ee21aed57b9d7d482a7adc9218b527ba5b5043273ff3f9ec6bb590782ea3254cdfba53cb9fcaa23907f06432bcdbcb98fe3decdb7179e7b462e	\\x00800003d5c99e494bff1710845068d70d0ac40a53b2ba3bf948ea5007f62be5bce6e5bef45baf90f95e5c5feeab7f2f6d250a1fd9112ff38ebbc85f502777b0f367743aa05d16496a10f0dccb2e7773e2f7901d6ab94e67e67b381288832dc5d54cb6d8f79abbe34c1e61e13c969f7c8e0f70e0c81f7529165407fb8ecc38982d60539b010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x9646aaa8a0c125f74b16a697e5bc9b963be48c29547d0e83c38b4ebc99f71a46bf9a00b0a7e64fc5defb77fa2654e98d2f684fb20bfe2bb3ff84ed4fed2ef90f	1587661896000000	1588266696000000	1650733896000000	1682269896000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x00800003c3dd82e020533aa82a71b147293604922aa14a7c020dcf0c6ae1b927f495555d3e22fec03fcc9e752e76dcfdac4ae8437d3941a488f0f31c805e23760227bead527f858410f079dea9f51473b3d1497c2bcdb34f84e77662739945b11b6746aa5a0f75586b976a3c08e0f7e48a0564c280dcef70a0ec93d846e33bb87c0bfedb010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xad419ad9960fcae8a61eee9351aa52b30a045d8ca3504b48e94547022d874270cabc44ba6cea3ec5d4d71a7c9b8b5a59495ae360ff275a33b084a91a42ee0707	1585243896000000	1585848696000000	1648315896000000	1679851896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe02ee89cb6dba4d1f0f153f248582a08314f118127333f50bc57e5a004aedd90b2a9adbe08aabd7e7a87dd7c04326d0736a0e16bfe0c268794b6e88c1e3d012d	\\x00800003b8eb9ee84feb7a35f3c47ce59d1d723d8c4584415b62ff5caf152cf98e5ad71e1abdd9a6c9fddd222e4a05867a4509823fb5e1fbfc204bacf3c79affd9f5f34c11a820fabd40a7f0bb8de8ef525a141384c14589550419a618c6916329e334a8bed6a81e8c408fbfdb3f136756eff2e79a091b8a51be97f9803393339733f99f010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x9d524b99d53a2a85c31183d1889702e43465c59e85692c09aa7c8fe1207cee55d8e638802341ebb0835178a96b1535f85534174a9934ba11ab02f14396ac4609	1586452896000000	1587057696000000	1649524896000000	1681060896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7cb9e437d1b66ffce0aaad5f8c06a60c4652271951750c464b097a7e6f05d5f1babde643105453e174db2ad3db39ae4214006d2da7fc23bee5f7dadfab75e19b	\\x00800003f22c26ccdc3e8a2b7ca9a21fbb9d9ec7beb02fe3ddd8ac70d87a081f7383926da320c3d0f6f23d5eeb9f16a4d998a724fecc98546db0c55b201ef588da509fcf638bccf5d463745b98a9abb804d259b95081e4e29e38a3f248b3a9eb65ab7b1646f247ec00170e9c4a428bcd32475ca4aa8ccbaa132c6368433c489838ebfd4d010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x82d80e2d49332356935ab042826fb8657008f38ffdefcc6ce7dde12080798fd39797081bce20d7d4b1d4eb0347361de01120dbc20497bc425225aa2b863ca001	1587057396000000	1587662196000000	1650129396000000	1681665396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\x00800003df57ab7dffbc2f8a6eec858c5be65f1bef7387ee2e373726090aa09a6aa1bc96f685f8aba5b3038c9561ce894b5f34de8f1c4bc6a77f4bd1c1abceaff33a1acd93ef92f05fe269eb0cd139b678156d7a4cdf566e0190d360747412739c430a239fe694bc0d29113a8fa39bb9ba42eeaa3732a7de6050c4c339d4cf3fd25660e1010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x742a3da2947c5c5d419f030db4179f7f1cc01a067e863f24132cb4ec652b13a3205d5b65a54ad8e77076dd309412253f7a6734a8aa61073fb73ec6eed349be0d	1585848396000000	1586453196000000	1648920396000000	1680456396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x34e216434dc76c8c9e0a5d806e04fbaa8a3aca8acc63fc3ce7e84731e7e6a3214395f176fbefc832b80c3454254a1194407f99d585282dfc42ef2b2d0ab81efe	\\x008000039ea23b284ffd85ef3608bca84ce229c285bbd5b65950d4e137a70e0ea88c713b85be700b4eb48f02302132e39d85db5c2c8047c6781ecc15159230555b93c0813422cca235bbb77c379b32d0c5ccfe7ba5c8ad375316a7cfc5d5dc70018ca56385a5529c19abd7a18aab6f974783dd5e31ae472f8cfad2ae12de1fea2bb50b75010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xb952587d2c6de05bc597606af7b13f0805fc54867ef29fc8e5eea2acbbbe24dcadd642ae47e5f06c7d6d0de77fee636e7b709577b80d3a731ad266dca46fa400	1587661896000000	1588266696000000	1650733896000000	1682269896000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x00800003b754be5bd2e3a679b1a4a19d1f4628baa4d506472f1112a06f4ec9b3a43dc80d3704a7ba3cdda862d2acb4f3aed3867ca312897ba580785f1e9afc75b59b16d781a10339c8a63085879a454c932e4e528ef0260e798c16d91b702a51aa6e51f9f18ec6f4175fc0d683279890269780549a41b84f0d0e336d077ffb497e7abfa9010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x05cb1f726f75250102e8d709308be1f17865d3798d794e7026dafdc72ae852151311944457f4d8e2a73a7c06d28154270b7568c175983086ad4acb5b7bad680f	1585243896000000	1585848696000000	1648315896000000	1679851896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x55c4c472924653fb3dc97157d90889d9c263da6b58525129a26d89b34d4430b5513a59c8b454741402466bf7839276e73173df581c0df8c51f91165e54341b6d	\\x00800003dde4579a8c012bac7555c42035b20c0bdd2180d195e339520d20aa18394f40a0a83f7bc21779f59414507c456e44dac244e38e7a00c26bf0cf5a410bc0bc03ad986590be7d4c71cae1169f68f22d6f61c571355e321eb384e97d6b0c9aed40e105f1138f5a18afad75b36de388cbe5dc55a35d2af932b0da766923609d3c31e9010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xce447ffe0e9c0ae7014a834775a6cb94cc2b1d433577ab3f05bcb2692f6ed8ff1492006939fab00ef81a755622b130caa5810029b5ef4dffc5c317e8b132fc0d	1586452896000000	1587057696000000	1649524896000000	1681060896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x736e3274135ac1dd65906ff1a1c2bc0c514ca49c32c849fdc5cee96d0ade27149c9fa03557de1e03cf3e43591a330994e0a890c21edb4372b75dda77fdb09c64	\\x00800003c04bf6c3d7f12c55825208b72ac505cf2775a9c52d11e97e162609c13e0282a490a4a8a3f1367649df9f7a1f428f0fe4129f71e44cd88dc87ec70c057f2c3d7cdaa2ab893624c63e095e38d6b1d15cfe6d5b919bf3458788862b92a61078af964e026e653b97ef31b8a46007eb15d8473cc7ed659d26c515f1e967e6fb9f4661010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xe0d5e894c0ebafaff15bd83b300f5b81e2b9315a455aa48103acbcffe4e3d6822c9ca538d76b481bf7670d5ca5d0c95f5ccbcfcf8eafd616f9f72544ab8fbc0a	1587057396000000	1587662196000000	1650129396000000	1681665396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x00800003b986b0ff5c62e9dfc6da10b411c856d1d9e19ab6838d3287e0755ce3ab6bc9b8e6935871e75727421d42e3613f73f7e6402ce304d2b659bc4d293412ffc1dae9bcc9262b400101e42a3f919b7cf3de22cd3a548c65edafd4d90df3a40d2160b700917073268cc2c7cf83e43c9fc558304415aa855b8d34d3fe05084f5320d26d010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x0fc3861af813ba39dcefb151d81f4b6e939933925bda553398360d1b7689bbc6d80c921a6a54f19b6e173f87fb4794bc295f42f856ff8b5268d99d800d3dc301	1585848396000000	1586453196000000	1648920396000000	1680456396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9bfcc2715c84436e3e79648596f1b62b076363df60e2b4779ccf6384f814e52613958da1df3f8cbf9f328b872040ab4f6347b4c5035b2a5272ca3ef96adce12	\\x00800003c387c35f9904e550df644cabb5d78dacceffb8435e809afe37d74947852b99aee9a7262d482faa5310206abd9e6f8465516844bd7f8846b7f12d073f724e902e2abadba12864e43f700794bdde898ef875a53a396d5112991cba9a0acac13b665bbe7fc62067ced1337415c4c1c36f77559b6264ca1600d7193e55dc8d6a2a55010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xa2d57c7f9fff58f5327926b21612132e589f8b6965c07d39754de69f0d4ae09697ba05986ed51e9c53eb93a7dbed2a073a358a5cbeb30772d1cee460987bc90e	1587661896000000	1588266696000000	1650733896000000	1682269896000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd79a8a4e6986cab23f056abc5adfb91d60a4eae699bb5a624495df249ab9c2a2b705cf588eea31eb0991905e62014b36e458e417f7e28b8ed91142034fa2326	\\x00800003e7fbfe563608690f3b79b39bb7cb80a93dbc2e8bd531415d5dedebe553d1c2ccc1efd3cc3aa562d3bc608f43f239f6c1a3f921dbf8581cd9f19a7e6284a631f0884ed343b2923f47480298cde6efe5a4abc1c697c74e530fd305ba1c16d43416e0eca856ff1576c1ea18ee4611526a223f9df61ecdefd1b424ac6338219318c9010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xf34b5d10529078da0cadfbcb1fa69de7d9fdd9fc374972aeb56991dca0d356a49b4149c7b875fd0e4bb73d1f971ed171a1cda3fde82bb3c0a1b1c443addc1306	1585243896000000	1585848696000000	1648315896000000	1679851896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3534b35710c1f0e1155cfca1f4809ee695582a7d44475908821dc8d388f0fe8a1460b8594b08579b1092345544b431872239351fdc33bcf122a6f2965bbb771	\\x00800003e75fc5e96256bf665feb2ea19f09f949ad07673bd3ef10c5921cb0174d995fbe7f7ec1023814cd92d04f95ef5e900024801fc9bbe4f0811c93733d4f14117f3e14c97a68a22cb3981e698aab961738bc46fc62bfb6257bc99f400e34c2c986ce64f2aa7d56e9d36741467d8337489d6108bb0baf9119ad902c01ac3131c6ecf7010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x8add1fbc89f9ba8778cdbcf0052858bf10b7e4b058b427aad047dc54588bff41c0318617991a637671aac2a935fe5b458e52c7a8dca32d748d2979eebaa57709	1586452896000000	1587057696000000	1649524896000000	1681060896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x88c67882ef1c0804c6d91a9f8bfd33653a80ea715e707bc40893e387ef8f7693da0919fa25a528507a1ada02744786381945d734d73e8563b68deaec47f0fe31	\\x00800003e224f2900ada51898b3090352d510b4b60ec8da5021807458183354a7092d473a311baaf70f9d71d2d1a8325be9586b44547d55c42a4b7f8bac654b402a971cc25eb003b292870e7339e7fe69e768fcc863bcafc4895804f3a470ec628cafa0c89474a563a267bf15cc1794a0b323d8549d2ee6384611ac2c36f5002302ae6f7010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xbd2570b54aeea24acc95bc51af0f4ce4fbee597a2ad01c2177780638f3377ee9aaa57cf9e987c1e01fe5a0d621bc70c42c44b55d06da4a7218a840dad7157b0d	1587057396000000	1587662196000000	1650129396000000	1681665396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfe0b4193901172557f52130f2fba1a894f16042c1ae1c25c86c545021dfe5a0dc02bc16ca6bf6fe11a842d8a4bbe2cacb17dc6f91719da466a60f291a9738c3f	\\x00800003b1d43c5d2c1ee97ebafbbb1a61e447d168960104131a8310b7489cdc7264e31848e5bbbf96a28f906d4e979c66628bfc16b3572556470ab60f68ac3b8005f940acb1d1aa89324b19f0ab5160b5d5f137659354dd30e316676fee3cf74bb9b23797ef9f553d83031fe19e824ef130816da1d6e129a8d217d86a6d3886f08e38d5010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xbaaa1beb3bf9976af2219cacf5c2d7a042f07545327d3364a1d4de93e8d5dadebe195ced0cd4a50396c480082d9417592c9f57c030bc7f0bc5eff5957320f908	1585848396000000	1586453196000000	1648920396000000	1680456396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7104356f5e39aa088b782a3d704f4579652735045d3d0cc552540f2f0214ae835904ed4bdb575d0fa92f680ee7fdd3b38f196bb8b56a1ee53b1a9535badb21c3	\\x00800003bf491b48acd88175b9bba030d17c7b3337742ba0200ed28e8ddc017fd61409361b67f6307903369bee37a611497d87192e0d873478971b1f40734fb6388ff18ab9aa9cc91b9e88eec3b8312ccfa07406522ef7c3716a77e43adb7b78c27b53d575feceb38d66298d865d315970f11978e47e5a282f9cb124b48f462c7d499f8f010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x6677d45fde11817b18ad8a4c82b74c21e10687dfe7e46626007585d1f6c9e2484582ed96d36c190431242fc9256ddef56c85da08f62769558f0815e96cb74603	1587661896000000	1588266696000000	1650733896000000	1682269896000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x12ccaa56f83df0f4a21ff9cd0834dd7476f6ca6cd0ff4674c0ff167101046fae724494b4047adb5e45fc5054caa68e9d227c483a2a2b36e5b8da684db7b9b8ea	\\x01000003ba0a780ff9c45bfb37f763633a18fc0e662f677893e5994ee396c0e9509174c6b23396d0a321a1f55c9c51dd026d092d676841d822803b007172297d1281d6823a840169b0e6498d38e4c2fe3be8e98b0b1edf34e755212ecc62e7f8e654520dfbe10b910aa2a724b565e2a7a4120bf1bbe45618b0a51d5a1d8d0605323629fedc0c8e68325f39cc5a2044fe2794d79223e812788a9954f1131eb3b5a754db6b3dc1dec0ca3b5173c1ad57185a8e5334e125ca157f21f4ea6a1163917584b8e0a2d6f7856e7d047bb3428364b15ee19e816714eb7670bbce7652cf2998e459ced01b297b39868a5ae4904cb25253e693e1cba99064969c9037ba2b3c59ef6dd1010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x14ca7a2d9a7b2d120f609170cc14d1ad2b5811b336e7aecb4e11e387c027e6b9388ba10cf9c5efa1899b60d1a58acbbed3193f0d48cc3036255b2d6f770ea60a	1585243896000000	1585848696000000	1648315896000000	1679851896000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x97a95623d55b0b483928bda7b1446f2381eb2beef612ebc75e4f44521ae984fc108f68623ee0ad6f0bbe311badcecb0f7faf4fcee7c471b8337fb71fdb4d8acd	\\x00800003ddf45d597c1297f04e99c30a8d45d0668538c547d24f0f00346edf8445cd7cf377a50c2667e18a4c979becf5174ad4216f4e1b8b94490982d98217407786114296fe85e70fd4eadae29075cf70711347b02b0bc08126762a7b2ed95361dc37fb2ddc517ae205d32d8405017295d99bff785c10cb17f6f5d12f8576941d302919010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x5374661f222e48d5fd3d6bccfbfe3d439f2acd37441f973c5c5dc1f560a3aca304d0548aadf85b7a71d3bce5debe766fdec22b791670b6466059a570435c8a02	1588266396000000	1588871196000000	1651338396000000	1682874396000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x187ace28753db4bed77b9e2cbe23d99162789b9d79584e0852dd1cc2c0d8f155aaad16bea0a4e26b1b23b3a38268de34847044581049a29af50c916cf92eb3e5	\\x00800003c365de105f7d0f6d02b18960959624c42ff8bbb996583d80096141a2c07a652e2594a107a8f249f86c4a28a96266f07578debf95fd2de694bbbd3dcc43af26f01502720c9a6103a5580c57b3462687f10ba7d4a370f3552bd7a2346ea6e89974e29148f611ac306388de5d7e0d08861132e1ae1279699aae0b7c788118f0a033010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x0fde51ca18d9acf4f53f0d1cc5428bfeb01d8583a1f5e0e83294ddfa3d015198c2fbc7626c5151ba6095894c17634587799f499afbc1f0293414eb838990de07	1588266396000000	1588871196000000	1651338396000000	1682874396000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6314e8570c42874bc3d6629ab222352bb261dad0b129e9285eda73444d6c66cf15f464178e0a6a17dbdb4246acdf0607950065451187a5103ed5c1e38d3f4a22	\\x00800003b0754d7621609341205079e8fabf68547086d551efed045cfd64803a277bd4f54e245b06742d62b76f148ad2133001561da2ce4fae098fd80a8350d114b158c4eeb706eaf3711e8307d56d4fedb5e1de83c17d34253d77317711b6038a57aa71c302b306ba6d1214c4436e295df75d6eb9c346e647833756f72a2527ec3d33e7010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x1a874da104fffe0a42e8b3197b32f373b44a79974137693317a95bcf6e678c467c2f11ed54e245d7577c2af648c7ac60d472dba57fd48955dc967793c0218608	1588266396000000	1588871196000000	1651338396000000	1682874396000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb535b5afc4568b0fc5e9d1bc92c7624a12c322378296b761fd981b6439bb4ac4070ef9bf2e37de40ef6e13cc8b2466a39af261fafaedbb8edd8f85f1f33b3a28	\\x00800003bdac039e0697e0f15b24256e73cee0d6a2b8d9340db2391f6ace69e34ed32085e8a98bee32c918192f1e9d1c246ef2b24c1be20603a0e09df08c00921a17829507f3078b671b0f9d6b9e6b534122de19d9734d294a6387266f89fa5a7ea6f1afb52213c0af3b382fe2ab88b2c0135ce5641bf3f57bcce79f56f5ebf1d460459d010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x6d537ee3a5607e412d5d7b68671b42b3320cbdacd0287f734b671f97001c6bb5d46f5c54043f4274a4434c14959c5c4e63b94b3b64908b74a314e49586f5ba01	1588266396000000	1588871196000000	1651338396000000	1682874396000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa2c27338a0df1444d157b2acf6c0a6c3c6c67d48338c55d0cb44ffcfd7e37874caeae0d7313b2b71c251943acee867cb5303bf409567abe77678afcdcf116c70	\\x00800003b4c716b55812092eb091485d7dcc0320c7c7060ca35d2f1a8fc800f735e38da06685ac367d71f70bd5156ac82f32e3fe8daf4d8f015088d68837a405c141d86e81d9551f2db3faa98e09706609ceb13193823e0e23ff1278289fd34023bb0f23640eb2c95846304ae5e6fa4aafcfbe57ba60490c6c5a2874a5f79119b5854839010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xb24fef53a30b37dfef10ba7d346c72c9a988cb9dcfa134220dcfbd03cf99966269caf540d67eeb6cc88dc6244e2514f1b0079f5b57c75815dafe5bb7a5c0110e	1588266396000000	1588871196000000	1651338396000000	1682874396000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x87216455dd84fb31964625f002f0302bf1eea855f5aa85adf57922c2c690d920a29694759742a467203fd0cbf49321cc538b197afec26854c06a2e69baec6b90	\\x00800003ef88283d9c0294d9a3efe1e815073d1363036fd4fa4612473f77bb74c471f4b3ae97c4de20b84784a4acc3fdfbe02cbcae60089e37f5a307ec2a6428b8a48a2e0c6386337e21caea5c1ba65299bc90a27d3d238910db6a400764e867a52c44822ab768d289fa9f23dacdca26374711c6f85ad8462a174651fdb910292b0f6507010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x707a41c4d9df7372469301736c7078c364251309f0708614d7a06ef1fee8923c760ada58b97365ce70dcfbcbae49a75e32d57efd4027c0b0e973a8b071d7030b	1588266396000000	1588871196000000	1651338396000000	1682874396000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x42f6ee7e3a3e891b14ac521e8220252143ed9a45f985d6287fdc97113229f7965a8eed9bd0d5be7e798093e91925418fa8f48718ef5a37e62da0d453c0b20af3	\\x00800003ceb6b737e73a60f09f67b20ebfd479db78583120169fe9b81eb6d8fafbe4079a013327e71770be6699f942de41ee2ec26742fa73f2dbc63d171f93b866b509e5dcd9ebf19b549f4731d9cdaf037b3cb27c8424130ad51cd7ba9f6766a1c582cce1274f7a5be07cc2032da18d0e051df49e733ee3c0dd3b42fb8dd78460cadc3f010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x641a079dbc4f261d6cc79309c8fa78784b82fd5223fde5b10b1407bc5ae6638be0d2265d6f56f967c06bbf1813c9c6418818137ae0c85d0d69f124d5e2a81b00	1588266396000000	1588871196000000	1651338396000000	1682874396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2939d2bf7a9c6bbf70a7432fe9aba62993d9965c7569220b0a64e500fd9c1286fa1805c49215825db6743465c3ef422415b817a6c6d9eea6a717d23d2eb5501	\\x00800003af558aa1ef7e55934cb51eb495753b342851af4d76a9007523c327a4f6019370868d6fa341b5acb57f7ed96fba408d7cd1b8fc3f956c0785f591f9d406732b6333aea835515b34e0836164450ee3e08b1f357e5fe39bc2e2de1b6aa2ca655a8f2270f1a09abc037aad4311fc7d3b89a02dc49014463eb1034f904d34ed209169010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x111dd025f18b1f7d87dcad8c16e72b1d21a10487116210bb81062e993a9aa955dc23612ab5c1b9c32cacc22dc94027a7fb17726a96f6603e7dfd3e3f321a4c03	1588266396000000	1588871196000000	1651338396000000	1682874396000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x01000003b4fcd331adfa129f76f4bf59d70ecb4fcef5f200d767b5a64f97b67a429209409b2763f1c57f59ce38f8b75d89a76f0211c5324e1eb0604b3537b01dee49187f88b035ffa72cd7d46ce83d1a5d7249cd50c9428427bbeff6402da3e6757e52bc898aa7a0531d4bf16f2148be25f8e9d8fce736ff2dc7899244322719b0dbd18b6ec401e0f59091b3e0b51936f4e2bf459e441dbab1e8ec0fe97f828f6ac91d3e84109aa253bcd8aa1e2795452aab4e743638d1848327d8b2cdf3a3917cbd9ce484e300d048722bc22d5973b2fac19b096581d11663ee2412beaa7ec304d453b793b9723af195f85a659be49f5c1c7d9fa84843531e0fc990a85c6967e9054b97010001	\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\x8dac7d4baef2be55a73d8ce933f13b1dcf7c4f8947f7fdbab76230c637e6046dde2e361c448db38e4607cdcc405fbcb46f24530be1e0c5c526d51c15b79b1108	1585848396000000	1586453196000000	1648920396000000	1680456396000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x271b75a72b089dad3db1dd3061ef91aa447e91a832fa8400c972e22b8d326897	1	0	1585243915000000	1585244815000000	1585244815000000	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\xcae6dd9545d844f84d157e21513bbf937963ce604a5903d3daa0be8e090b3def9dd1089f12e01b9613ddfd9702de0a9595cbc07567efae338107f15d8a81a681	\\xedb4d1897265f7c08d49dbaab690a1a3f79d1d5b305c7c1eb16a8fbc2114577857c83b2a99d4c1f505d9171de14173915e287a691be15ef245b410412def7280	\\x315b4bd58338ec8bc1845ae55e5b582faf4b00e20b0d20bb2b23b55427ae06f97924638a915697dd9839e842329abf44a00aab8258d7c9d5200e6e890333260d	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"ZNB9M17C4K9Q55KS14MMKMDJW23Y2E7JD2796XMZSAJHP3W9FKPDHP96KFPW6YSRKT0YFW1SJP8B1GQ5CJ755YVN6K5YQFDRFJJXMJR"}	f	f
2	\\x06844561efd1878daa7c9c1f60fc101be753dbd94d363a884cbb052300eb8c65	0	2000000	1585243923000000	1585244823000000	1585244823000000	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\xe84f36573e2d4462691aaae114bfc85ce605878e33d0049136d73cd90162924e7863228b1a034e41f0d13da6bff2aed943a1899e43caa476c4faff5a2a70a733	\\xedb4d1897265f7c08d49dbaab690a1a3f79d1d5b305c7c1eb16a8fbc2114577857c83b2a99d4c1f505d9171de14173915e287a691be15ef245b410412def7280	\\xdfcc6a512d1c0b2a0b91df0b9587b883086846ca2388007fad1c26d54ccc3b61a67a6428bf2cd15a8ff4b43440ff06abf00272fb5b8cea8db05772b60c1fbf0f	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"ZNB9M17C4K9Q55KS14MMKMDJW23Y2E7JD2796XMZSAJHP3W9FKPDHP96KFPW6YSRKT0YFW1SJP8B1GQ5CJ755YVN6K5YQFDRFJJXMJR"}	f	f
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
1	contenttypes	0001_initial	2020-03-26 18:31:47.307401+01
2	auth	0001_initial	2020-03-26 18:31:47.336763+01
3	app	0001_initial	2020-03-26 18:31:47.384931+01
4	contenttypes	0002_remove_content_type_name	2020-03-26 18:31:47.408573+01
5	auth	0002_alter_permission_name_max_length	2020-03-26 18:31:47.41173+01
6	auth	0003_alter_user_email_max_length	2020-03-26 18:31:47.417368+01
7	auth	0004_alter_user_username_opts	2020-03-26 18:31:47.423904+01
8	auth	0005_alter_user_last_login_null	2020-03-26 18:31:47.429995+01
9	auth	0006_require_contenttypes_0002	2020-03-26 18:31:47.431375+01
10	auth	0007_alter_validators_add_error_messages	2020-03-26 18:31:47.436701+01
11	auth	0008_alter_user_username_max_length	2020-03-26 18:31:47.443877+01
12	auth	0009_alter_user_last_name_max_length	2020-03-26 18:31:47.453253+01
13	auth	0010_alter_group_name_max_length	2020-03-26 18:31:47.46023+01
14	auth	0011_update_proxy_permissions	2020-03-26 18:31:47.46731+01
15	sessions	0001_initial	2020-03-26 18:31:47.471763+01
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
\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xd58f5c480e9e8b4f0808f9ac1ea963b910f5d6e5afd74d1fe6a0409b2d342e939e821bd4cfa16ced0ae3baf8f9a5790a333bdcf4782fb4a42f0a719deec9ff07
\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x46da80fb9e53c1091298fb9374a8af5a0fea886372dedefd6f230f02eb4f68317d99042990772405a77e80b7b7b2ea480e380e0268723b0dc34cc68dc43fc508
\\xad6203b2a3efcf5795022fac5a44bbd7d9e3e5c83c8bcc7e15e414ef0f3b3b0d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x88b812f89f652456445f0e57f0152938976d4eb24a3c418d50404a57c4066e5b57f52c3105375b19fde0aaba31bd6893884fe9664f6bf7868245d3813deabc07
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x54b828629a7e0f224f7ccbf1c3dd2d6be94f71534665a7a064cb9a6a83e1c2e2	\\x320372cd907bfe5e64120d67a39fb1d9b401c2d882023f4ebdf8f5f0a6b39020ec9bbf1b752bc2366a088f7744c16b0d54bcbd08c6877bbbfddef4a7cf7b79b5	\\x9196d4c9b6753fa5ec23d6878f40d39ffbf54f0425ce798ae917026e97ff220bece47d8940cf5882733ce2b28dffb2a9d30e7852ef7cda3f8db48044a94d05aa8d1fada72a27df21d6c1f9531b74fa84d36577808f4bf07ee0f5db2981d3b2656cb097385aa92b8284796322a61f1bafb7c61822d6e760ffbe5b6ae86fd21781
\\x271b75a72b089dad3db1dd3061ef91aa447e91a832fa8400c972e22b8d326897	\\x08c108861d20730b4078bb357dc9b801a4b6db0589b90b26885f6032cea71766ff7aa7bce983d09b9405be8acd6ec44cc2e494f0b80a16dce1b36252ef7f5e3b	\\x12ba9ca738339c4f9a0257fe865177127a06178de3bed0a0fe67c265cc79afb603f298d203ae4afb74c1b979b92204b88ebfbe233b1744a036a81a6da1431fdf1a6cee901ad1bc11e2be3f2568fe347e545e21728020142581c9b9c59baf39502e48ad1374e29ddeec77716bb7afcba2ca200de1ff6fc061c3e0cc0adbd044b3
\\x229f55dc19c3cbbce9bb31401ad974eb0065ea55c91ffcd4206753bc5c640a99	\\x3ef58d93b1ce275b9090e8a0652905a9bbcd5604fcdc68cb07c20c04f11e2c615b80c1891d3ab7e0974a1f556e329af8398d4b1a5f7735ecf23d7087890e3bb0	\\x0a45834a20957cc82537a531ae4a4c9b65c701364b1716be626ff28912136fd396d974a8327d550e94c82f99d9e4bae128b8cdd00ac90b91877b548b53d71f52a8118c231cb5399e684594f61c797f5ef5d839cb1848cce4466c573ef97ac01a93c220c47e0f76be4f612aee1170756f6a45140920eecb5e352ede9e74ebee6e
\\x5ecf9d369b3459273b5b4aea0be965549d98dd343c903c0a60f1e1f4ca27194f	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x4b69b8089bf4f036ed75bca5b07afa22de576914c07abd78777cc6ac6c60da94ee659745646fddb77f8887ad39c8ff061c98f254ee821d0113d289cfbdaafcbcac0f4c017c5994de8d277ffc4691b338de92147d1cae0468e3245755fff7125d75127d445557e095efd15b40fb02f03c0282b9f28b7211fc0e7f96300764acf7
\\x27c98c8699adac4b59a594c731aaf89b98637e0dc3f8b460ad217b21c762a231	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x35ab039838142244fc9d54fe31e16470f4c79240da3e84686386a1d76b60d594e0acdb395c27e40384938441f101669802766e9981e6dadfe86c9f63a7e1e6f33e50767910d5a1e5395616ecb991164c97080152b13245512913da6826d44b1fca4f4f0045b3bfddc1dff36a86f6d2a62037630806d8bff16539551b76e0c179
\\x09b502eeea2d099ec7ea225784ec3a7837d682c0580caa8222789ebe42c90704	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\xa6b5a53bc3bff7501d897201f7db579b16e449e8d8ac5a36af7eee9ed94e64c236839b3c38091cd04f32b732e9155fcbbf524f1e74f244a2d1b721ab6d563cc14374c1b993ccc5b3cec46e27e910e78b914f522214f559a20c3272fd61be655232eb8a2b19f48706fa949516be1c5a94f3e354f0d481c13fca0c3871e24029d4
\\xc54d8ba6dd70a3751701a89507a46c44affd07db4030a4b3783b05a4b1187637	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\xa706b366539a36f0bf724c2ad212ef5814e3bc1640e52ec04b2b890ebc2ae2216d981bbff20e0f79a08381fed6848842de80790ebba3b01a4e6eb3c00caa1dffd4e59d4fad20c2ee985edb05f08d7450fa8923042c0917ab8288f7c1c94f5d21e30cb747a5f48246173c1b12c48f21028db8a93663aee3d3a81adea45baa1db2
\\x8328d4d90365905f6d49edc6eb0856f3d2827dade0b379edebbcbcdeeed7d8b6	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x79ac45e15597a7c0aaa2103253c64ab135147639629375e3ceb9dbf346acddd2d4507aa11217f3cd1e534f6194e841a7acce0c20d674b351cd19941d14063c91507a04123fb795fccd3542716391b82859848c913f506520a2fbdb0176251ab69aaa877438296ae6007fd28d4da14d17ea248222bca28c16251dae450c092582
\\x171729281a204a7de758285a4a64a3374c2d115a587816904311522bc67d41ea	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\xaa0d22035864e5848b34ad1905e1c516c13c658bec064df303deea7468b5f4796b5e6a7576c3058d96c751054b1e38a1543bc7cdff39e8a6e71984cef71dd8e1ba17c16a1bd6856cf2e8e05ebd8eb6cbaea5eb903762e67f342b7c37f117a48fd4c7cd026d7445948ae425b2d7e55180e658c5e8c7a5d7a5bc3801496ef6784e
\\xfb6a3c82043f1d8d7b73c5cc1eeb7244af7cb8a3588c063908e201eeb94e27c0	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x0ea19c050b3f3fe75e2b11eccf712dcf2af4c3746405a81cfe541cc0bf910853c6343d22420741ecb1091074f8ee88d04cbcd9c7526aa7258724de0fb8b94f2d1656d7a0e628f1f242f932a808dae224287221025062faf11674b94e974a4a8834e1f1851f8583d4ac2c3b98b25664f601f3cfe46a13e312b42bd450eec61f4f
\\x4a5c76aff573694177098c87c460ff870b9d86934b89251cabfd136c9cb7c672	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\xac70e91f07a7ec22ca87d7105bd47a88def402a42e4d90a58c0b337052b375db461d25b6d4b5c20cbbba5e4ff1981b63c3b0339747012869ce1345a92451aaed0eff61b102470eda12a8cd59730872f89306a340ee33c59bfd93325f8f019e72263f301b84ca9b287564dccffbec4abf294e45b2f0278d4d5c2213ab7a1a2d76
\\x06844561efd1878daa7c9c1f60fc101be753dbd94d363a884cbb052300eb8c65	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x30612137b18dfbe263a83a2b9d9ce8f95fe46d6be622cee65f00efe9a3fe83f19245141c4606755276262f6b4352ce2990fbb645d43a111a8a0c7961c9a289d7c26c1bda8e202b222cdfc986bee6e295eaec9b1c1fa545026b9c265802007cb251cb12950b6747ee7f77ee76e8c8625e465d7100eef008603f3cd3aed357694938859790bb487026bb6dbdaf2bc594d2816ffd53b41725fb81213538c8eb133e2ac437b86a2487876b8d1fcba34ff0a687f593629be65a46845db79a311cc61f414c54ca8ba4c45b66d769c00a11598ab2e220f94065c06781e64ffef6c67f2d363de6fd99042bc82ab3693b864f19ca6cc0af848da119bb4d824034c99163bd
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.086-00M18PQ12G5AT	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234343831353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234343831353030307d2c226f726465725f6964223a22323032302e3038362d30304d31385051313247354154222c2274696d657374616d70223a7b22745f6d73223a313538353234333931353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333303331353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4e483037434e33585a374e46353832355950354d483556545a435937534538374a3557525a474e574741455933535637433647227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22585054443332424a435156573133413956454e42443435314d465653543741563631453752374e48444137565238384d41585735464a3156354143583947464e3051434845374631383553533251483846394d4851524159593932563834323135515151353030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2258355350385850374241524331434d545a424747313556374b3853345050324a4533525730355048305338333643474439423147222c226e6f6e6365223a224a4d3032523242443458343256353838545056375235384e3836393741435841564a53314a334530534445435033413142454430227d	\\xcae6dd9545d844f84d157e21513bbf937963ce604a5903d3daa0be8e090b3def9dd1089f12e01b9613ddfd9702de0a9595cbc07567efae338107f15d8a81a681	1585243915000000	1	t
2020.086-01CCDZ6K59HZW	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234343832333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234343832333030307d2c226f726465725f6964223a22323032302e3038362d30314343445a364b3539485a57222c2274696d657374616d70223a7b22745f6d73223a313538353234333932333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333303332333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4e483037434e33585a374e46353832355950354d483556545a435937534538374a3557525a474e574741455933535637433647227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22585054443332424a435156573133413956454e42443435314d465653543741563631453752374e48444137565238384d41585735464a3156354143583947464e3051434845374631383553533251483846394d4851524159593932563834323135515151353030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2258355350385850374241524331434d545a424747313556374b3853345050324a4533525730355048305338333643474439423147222c226e6f6e6365223a2236585839344e4a36354b3751534541485936393631424759524b574730523053345056514b41395758505a5643573130395a4630227d	\\xe84f36573e2d4462691aaae114bfc85ce605878e33d0049136d73cd90162924e7863228b1a034e41f0d13da6bff2aed943a1899e43caa476c4faff5a2a70a733	1585243923000000	2	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xcae6dd9545d844f84d157e21513bbf937963ce604a5903d3daa0be8e090b3def9dd1089f12e01b9613ddfd9702de0a9595cbc07567efae338107f15d8a81a681	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\x271b75a72b089dad3db1dd3061ef91aa447e91a832fa8400c972e22b8d326897	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x15c88722d144f3813cf8a6fbdb0daefd3a1ace5872d1b576a1fd0045b1b24814	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225033595058535131424b4638485a504d484a4a374a3545433234364d53543634594650345957574e39445a37544730364a324859483047464135453337565a423739594159514b4456354857565035435a5747505844535944424246464541594d324d514a3252222c22707562223a223251343845385048384b5352324637524d565858503344455a4d58314e4b4a524542385641584e315a4d30344243444a39304130227d
\\xe84f36573e2d4462691aaae114bfc85ce605878e33d0049136d73cd90162924e7863228b1a034e41f0d13da6bff2aed943a1899e43caa476c4faff5a2a70a733	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\x06844561efd1878daa7c9c1f60fc101be753dbd94d363a884cbb052300eb8c65	http://localhost:8081/	0	2000000	0	1000000	0	1000000	0	1000000	\\x15c88722d144f3813cf8a6fbdb0daefd3a1ace5872d1b576a1fd0045b1b24814	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225930585242464344564341343138344146483437464d5a3733583633594d3638333041423139534d48304e4a5a524b444b51584b5943594d4751535051534b42453056594e395a4152524830324e48463559393836585045434d5031534843584a4e5739413047222c22707562223a223251343845385048384b5352324637524d565858503344455a4d58314e4b4a524542385641584e315a4d30344243444a39304130227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.086-00M18PQ12G5AT	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234343831353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234343831353030307d2c226f726465725f6964223a22323032302e3038362d30304d31385051313247354154222c2274696d657374616d70223a7b22745f6d73223a313538353234333931353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333303331353030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4e483037434e33585a374e46353832355950354d483556545a435937534538374a3557525a474e574741455933535637433647227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22585054443332424a435156573133413956454e42443435314d465653543741563631453752374e48444137565238384d41585735464a3156354143583947464e3051434845374631383553533251483846394d4851524159593932563834323135515151353030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2258355350385850374241524331434d545a424747313556374b3853345050324a4533525730355048305338333643474439423147227d	1585243915000000
2020.086-01CCDZ6K59HZW	\\xe9736476c75ab0c0b29afae10097679a324b585270f1c016d1065033320d4ac3	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234343832333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234343832333030307d2c226f726465725f6964223a22323032302e3038362d30314343445a364b3539485a57222c2274696d657374616d70223a7b22745f6d73223a313538353234333932333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333303332333030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4e483037434e33585a374e46353832355950354d483556545a435937534538374a3557525a474e574741455933535637433647227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a22585054443332424a435156573133413956454e42443435314d465653543741563631453752374e48444137565238384d41585735464a3156354143583947464e3051434845374631383553533251483846394d4851524159593932563834323135515151353030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2258355350385850374241524331434d545a424747313556374b3853345050324a4533525730355048305338333643474439423147227d	1585243923000000
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
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x54b828629a7e0f224f7ccbf1c3dd2d6be94f71534665a7a064cb9a6a83e1c2e2	\\x1f2daf73a06d8ac1d4d6aeb6142780e51da78bda7d42b4556a8e45fa9ad0d7cbf810883b1da7b628e3a7475f22c3895239c3058584e4c2e8f03cf9fb3d643403	\\x81b014a1dd1692d42b871f7e453d55568c05768e37a93410472b6531790df2fd	2	0	1585243914000000	\\xabe2737393fe52873eecc8b0796e9183661b0b948be4e1295ef6bbd40856030a48818f07fc9b1622059e984bb4d033787c5256429988b41efd52afc83f2b1237
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x5ecf9d369b3459273b5b4aea0be965549d98dd343c903c0a60f1e1f4ca27194f	\\x9be36aec0c3def92c56a2cf0f78d4683754463a1396f54649a0606fc2d3ec38f6f2834b2d448d588b7aa63c1aa4bf58db87cacd1b8a076f90d034e75e28cc101	\\xbb2905ddbd5f37e53f8761930e9809d7246790b0d7ee5e47e9d15475e9e1cbdf	0	10000000	1585848721000000	\\x20f1cd5f1be3f08e56ba6c4a9e29238f16e1784a2a51c2dfad0a6ff83bd0a886453eda49472335676675fac1e7a486600b937cad2cb0fc2d023856749b02c6ed
2	\\x27c98c8699adac4b59a594c731aaf89b98637e0dc3f8b460ad217b21c762a231	\\xc048a5fe11129605f89a46530f52732b4efced62f6917b044a296a133a1b638dc973faa2756fd72c5ef604b8a62a414f4fdb23acb7ec3711c54f2f4dcd19460f	\\xcb549e3fc541533e8d082b7ff1a8e1983b31034d08954b5bbb3ce0140066f456	0	10000000	1585848721000000	\\xf6679af7992c4be93af37a08600f706670b9b3272b1af6f0c5b2d4c8544c34b33fee3b6173e6a65a6e4b2947cdd614b395765bf70b5d7da6f40ea4a4a15a763a
3	\\x09b502eeea2d099ec7ea225784ec3a7837d682c0580caa8222789ebe42c90704	\\xe53a21be64f33890178e814ba4997799f5750a255df89ee7f8f7908224121cac7b18aed5301a227e479114c2fc168e56d87a9c0d5fb82c4c9bc40627dabdf409	\\xa379d5beeeda047f7c26906d48eb71b88c3e35f06e4d12266faec1967a12bd3c	0	10000000	1585848721000000	\\x33224ddd9d0106dba1a8d76ba15c7b3c577099fca05d9892c65f27b74693d3ec9ca7c3a1e27e3871038bdb8d3bd88d63cc76e76aec03465f19a3de6c2220bf20
4	\\xc54d8ba6dd70a3751701a89507a46c44affd07db4030a4b3783b05a4b1187637	\\x66dbc7c789f96503809cd0d66b60198320afb8a90fce052d8857c78c8eec02c73cd7eaea2d9bec7b2372babbaefbf615887c6abd3817a11b0cca866c95427907	\\xc3f6d39fbbdb01d8634fe7517f8e1e842b00b3c39ee991a5700f7799d429d168	0	10000000	1585848721000000	\\x27964c2687269d857450acd165f22a5e2e454192efdf3e016f8e4b69e3731e2b5d394071ae78255e8b5ac67fe8280ca358f54bcc01fc8164d30d2b45aa3a4490
5	\\x8328d4d90365905f6d49edc6eb0856f3d2827dade0b379edebbcbcdeeed7d8b6	\\x1625b85bbe80fd39a1242b914bc9780a8ced037be7e87bba897087f498050dd78fd1a981f9a600eb6ed1fbacaf2199f1c4c750e616f3330340a072039e34d706	\\xa6fee9f34acd91feb9fdcab85c6347a706124309c75e2141a36271f13b9dfc1c	0	10000000	1585848721000000	\\xbdfcb6ed6c0c9b24d12dc72779d4e8b0ebceaa3e6b56596cddc3fbafaf2a1650f33b2d3382349a9303282874fc65645134084311655dc29e0fac0996bb1c1997
6	\\x171729281a204a7de758285a4a64a3374c2d115a587816904311522bc67d41ea	\\x032298f89b554463e8ecf902d6620c6ddfa4b5e73271b34a9277458ff5d518651fa90c44b08ab483ae2166e11fbede3fb1b04dc50c7a7f906c30a39d6075d20d	\\x93b48f72968e3b353866745323f83815077a93ea67f10bc628c76a41391ca6a5	0	10000000	1585848721000000	\\xb6c6d0de0ea738c8bda3ea87e7674ed3f9497dc2efdc9d4a770b0e8b8b59402507dd952e1d35e6c79022bf809f0c974d17292eb554f5d5a1712aa08c63c0be75
7	\\xfb6a3c82043f1d8d7b73c5cc1eeb7244af7cb8a3588c063908e201eeb94e27c0	\\xbfcb6355cfdf5be5060b29d341bc2a15f9f752a0eb0fade1e41a783b2b64b03fbfdf4731ef30a8e85715a3cd7eaa71ba8a6aae0b6f8ca661a32e20cc34576b08	\\x26d2b7ad48011d3a568e29fd7d6b3bdfad52ffb1bb48ae21f2ebb644b15b1dce	0	10000000	1585848721000000	\\x469b829b4faded5dff57733ac4a15fe9cdde3b11ffae91645bed29249e5152e8d9d3618dd2d03a375c91aeacf31a894e1b5fe62b7778b9ee546c3aeeda056bb1
8	\\x4a5c76aff573694177098c87c460ff870b9d86934b89251cabfd136c9cb7c672	\\x2422815a0ead6dd43d9d5cc27c6dc59a49e02311daa027e3cf92336fad6c585ef9f3d48dc8a49ba26a19092d99c97b32eecb368685b76d718c07922553b05a0b	\\x9e6de3898dbe9a7fc421b1bc18fa26adc648a1c6d02586b1f1f48e5ed4cc895f	0	10000000	1585848721000000	\\xf227f2d85fe46fb59bf22220591e6c2e2f443ce97b2eb1b4a5982f92bd1fca642ed027c34015dac9f5940a573e0079c2bd95d90933edda53a898761588e069fd
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	\\x229f55dc19c3cbbce9bb31401ad974eb0065ea55c91ffcd4206753bc5c640a99	\\x2047fdae357065018e283bb29d95dfc214c20fb2600a3f8646bf458eee83f5ffe963f97bc1838ea76fdae8f152020996a6c2aa477b83dd0abad0abf84f59d208	5	0	1
2	\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	\\x229f55dc19c3cbbce9bb31401ad974eb0065ea55c91ffcd4206753bc5c640a99	\\xb98a3d190f82ab8375dec019bed4c4c9c778fc8d6932ddf7b5cfd5b3fbeb5504ad1a6bb7acb9d0ab1493879fa9dbf97e0b939e920105177c838e1c7c6317a404	0	80000000	2
3	\\x0313708216513ca3e006e040fe5859d26ced6fdd688ecc4763edaa860f75d61cebf7d873546cfaf57c91c72046165323a0fa2982e5780e4f11834cf20c4dc99d	\\x06844561efd1878daa7c9c1f60fc101be753dbd94d363a884cbb052300eb8c65	\\x3e5a29855408ba0dc3e641a8d33525d2087e5cf66d7eabdba47a83fed348c3f429498ec088f7443ddea70c7111e866dc8bc06446288e1c0f18ddaccb252a7104	0	7000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	0	\\x3297df5e39be62cb81ff8ae8352e82df62fc98b6c99a757a66dad4b3b6472a0dad2e71f7eabc1190d3251dab11fca09e52090ff4eeb5eb54720596efe75c0701	\\x0c67bd3b5ccf79cf725ae7e26125995846f4300ec41fa68e1a94e851dc31e5e3d3097ff6ec92e03ba3d0e69d49741c0eccbed5ca6eebe7a6032cc329774cc7ac	\\x04ea08ad6ad7a1e2dc7de79fbeba7f367fcd094a3c68f2b512664569d28c9d6a2f88e252effb674926e1b9a0fa911634eefed440bc54473c79fd7adf842a83b77a4cff070b0073a3127b6c5d185656296e6a2675098afaeac233ae01c608bc6d6ee98546132d6da1005a64d15995a67f4b382daf3202e2ada2c23c62a2cdbae3	\\x774b90460cdc32072186e2bc94aa3b4d8e208203471580fbcae31297a0eb57d4445edf7c94f3baecf56916b8544e97ce300676299d42641c049e8afaf6c05526	\\x92b54b156d6cc462136bb55d8ce033b19af2aa3074eee771477cadcafe1a3f3cab3801eeeb1e317927bbc97fb23e140c87732b8df280b63a814f900b8f20ba0f4677b3598814a4fc6afb6b25158f55e6fbdd3d88d59aaf5e6709576494ac8677f627b96a97dbc65839ae9bb632b5a3eba56643a42cdf8773749e125455c34848
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	1	\\x87310c8bae8c4ac79f87ccfa9676d74b0ddf87f131784081fa7145cd617548faa3d1372fb1cef4e474e81c30c1ea8d67828b51a07b53ee0308c81e5b4b430b01	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x9cd29d5bf6f2418aa1573215686e5cf9ab4179ffe11f2b2a5abd90f7bd2fbb64866d69555bb0007ad67395bb86605e4372440c335f0398d18470b1dd33a1d23e54e63a0a4a9415955a106de675e7515efb33abb5a638264d4ebab73b90a7ff5b945c545c253a3c833aff315d5c1e438c4d704cb66ce004c535168f40311470ca	\\xb6c6d0de0ea738c8bda3ea87e7674ed3f9497dc2efdc9d4a770b0e8b8b59402507dd952e1d35e6c79022bf809f0c974d17292eb554f5d5a1712aa08c63c0be75	\\x6a624343b256c74d9042a91a731a4f67729a7226083f3a911970bcf1cf4ed566a300db74cf2a32ca95a938fa9e75384802ca7c11d994dfa5a07f3a5c8915e4752f623a429eedf2a15e3f67de7dd6ac300f177653d80b3908750d0715a5dd62311c9ade0c6b86c36299ae91482d0437ad314f83312f6974dcc79628714cd8ddde
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	2	\\x3cbf5d63b7978bf31fea99743765fc245a2901636e2b0d80a4b71b43b02016d143295b4d74e9d827bb8df097d1034ea9cdcb72405ced7b9b3ba6111c71f8280b	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x7baeb20075afc7d7889d5d316c61496aa0d0f51155eeddf02e529c31ed4795cc5b0afa9ebe08cd4be085a71c68fc7f7653af79fb638b74bc3da9cc788ea7b48f4cefb00542f430d23d0dcf5f61792d6a1d9c1d5740a8ead7b55cbdd6334660f2216b42c33ca002bde0ed2a57c6befcc79e9aee05a66bb88237a41bc3dcd35123	\\x33224ddd9d0106dba1a8d76ba15c7b3c577099fca05d9892c65f27b74693d3ec9ca7c3a1e27e3871038bdb8d3bd88d63cc76e76aec03465f19a3de6c2220bf20	\\x2313b431f9a06a9e063ef57bc09404079484f5c3a3328616e3747f70c75872be811de359520892b13520b473f30705f197ee61eea1c664c287f311287cc074798d898c5d48cddb56f0e5dc6a57fb98ac6cf9b765001210a548c979887ca0803b86f3eb10fda33782690bb073d38020c2aa49e95f97b1053042a94ec01054f7c2
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	3	\\xa72fefc6f98aeff25dae64458dbc479bb763be1ad04782e62667abfdc6e54845b297b95d16e8d90931ab082a7d43e753657678d448738988735aa45d87120601	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x6c35f56a102ceaebb5109e85a3f17836ca0127395f8204de4b53d07a9360ab4023729a8885aec4758fd6b8e739cff749dd33f65f5a39d0ef715f0f51f7c6eecfe3ec0effd2b6313fe0b6e0cb2332daf6026c3a27109bc583e20611b3a7d223d7685289cd52807364db84e9387bccfe66114276133ee3befab4dfd74ccdb01c65	\\x27964c2687269d857450acd165f22a5e2e454192efdf3e016f8e4b69e3731e2b5d394071ae78255e8b5ac67fe8280ca358f54bcc01fc8164d30d2b45aa3a4490	\\x1187c84e35a7dbd626384a98a55db6b8b9486b5c3af3f7fb6b8983ba690f3fa17dd9bf3780a82cc96ba84f9e62a4f5a11a5aad9f5be620348f60733ef4e0fc84924d726205152173171238b46c994c47f02b944436b918aa327867e5d1cc6e8bdfa613558bcc08a3e6f845bf275d5cdd536866eb52198a948d6ea529a7630af4
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	4	\\x6882b50b48d994fab5145f440685cfae435759019d4f8bfac45777442a11f03eba0b0318c1ab79a57d30a5e3f33f5d134e97fbe6a548f8407578dd4aa449ca08	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x971d9b6d15ec5499c24442e839c153af24800390ec72efc980ce305cabefc0ef1ba15bc6358830cc055e24c58da5f193112764c0f7601940349aad41534c9e48bccb5efc2f066df6a0bff3dbcf850858304f4ed0fa1458a815c1e2c1ded47e363833bf29ebc244f6b4365d0b85e21843e7f67c6ee049058d643fbad4bb463447	\\x20f1cd5f1be3f08e56ba6c4a9e29238f16e1784a2a51c2dfad0a6ff83bd0a886453eda49472335676675fac1e7a486600b937cad2cb0fc2d023856749b02c6ed	\\x4df034258a21f748cc1c1f5aa98d666d2b4b2d054d07b478c0a9ec4114cfd567ea93837a1928781b133c1f130530ce423d62547a1dec6feb8a9c26789f7ce9338de7b96917b3c226efcfa63ec9b2e0836f6298b34e6a89b5bd93c0c0417356a688f258f43b05d3eff0207e82a48e7da3e57bda238a4a2acd16d57e9b37784d58
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	5	\\xeded8db742bc9f804458e333733bee8f950d3b61c55f21ada59f79778bc8719909121cc80c95287cbefd50b0a0bef72a56ef982782efefbe5fe965c917c8e10e	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x7cdeb2befb9b36971f4c7fbe93b91b1b0548bcd982a91edebf64d602b6ac60981c17a6123cd75e21a2676cc6a29f4d2e3e7dc061ca69aeab0d4dd0e9b2b9576402007edf8e012ea818dc5068bf1148b3915921fa9543f4ad162ab87f41adf8d0513fc112ea27d1b8892c87f6db913d6f5910745a163edd2d38804537ebaf8de1	\\xbdfcb6ed6c0c9b24d12dc72779d4e8b0ebceaa3e6b56596cddc3fbafaf2a1650f33b2d3382349a9303282874fc65645134084311655dc29e0fac0996bb1c1997	\\x7d82595bc8db05e45b00f7f34069c5fa185a5c5d14a0694ab312ac8fefecbbc19d2f341127a1fe674e9f8dbf76b8acd1f7cce9b3442cfafc028af79634464a95b49bb7fc62b60fd8896dd246bae3ca0cb208c7cf1fd3243d5d877b72e131c8c2ef3525e30fae2fc91eec290b6e15f1c2e07523a51839bde786de140759382a6c
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	6	\\x3c823c5d15fd66fa6d294450997d14df064e072c4458d63abedb3ded8bdf650f98c78ba27236f6f59616407359ad5d1feef97ee1f2aa2fc18c2b6ac22b79b30a	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x106fb3d367693c0d578e8e74a03944c8445774dd65e094e06211c931b47289f1a5696054e3e74f50e1c6a3fedd22a0cd757a4c304e76a01090891aa3876430fdcac1f9d7e4b4f5d834c87bb64ad81a19d6b83182c1927722f03b008d128fa4d6abc8963d9cbaf1c63e83443419f6b8a6ee757fa4f872e56cfae26ac487e2819e	\\xf227f2d85fe46fb59bf22220591e6c2e2f443ce97b2eb1b4a5982f92bd1fca642ed027c34015dac9f5940a573e0079c2bd95d90933edda53a898761588e069fd	\\x2dfe09f87e3ef7264e515f31c1e9f8e6a6b8ca682590ff3c08870690ac93507c1d3eab72ec56f3b745d3fb5fc1f32bfa1825be1d6c43f758a4157599e599861f06ada91e14ddaa54f8f4e2c6c89f734c3a1fa580b7460c975777fe1c0d6c5da6aeb1d236fabec186b3d536b9c45adc1a47ab0a29c3653bcd2edfa5cea645e1f1
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	7	\\x4efc064169ff813e1f0c17f3700707000c16b1efebc036a5d27dfdd6aa943d796135d4e4e598bb9e5c7e4ecd65e487d89e992711899ebd63813e561da3b3b20a	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x9fc9521678232780c65735a2da2879284e38fa63fbcb1823d1988aee50742987bf576c6346b5ed7ec27d1a3f786e36e11641d093aa9fff5a33078c1d54a465eef2ebbd75fb52fbd98e06d22096a368a595e090a07c8d297da44ffb45eb09e103c421a8dc4d7ece32a6e977ddd53143d3e78010ee8fc6d4c9161186d927313c17	\\x469b829b4faded5dff57733ac4a15fe9cdde3b11ffae91645bed29249e5152e8d9d3618dd2d03a375c91aeacf31a894e1b5fe62b7778b9ee546c3aeeda056bb1	\\x31de663ab7efee5b02fe49fc3e3a61c5be917face10cdeb32850100e96fae6f7a50fe819c3df43772747ad534166f459c6d759e3dedbd57208c120382afcc04dda8d50380ef12dc1c9405ef46da222ec14d65121d26648f80afce57f238f75dd63148df8a32bc39f8ed41220892a54611585a47c9ccb632a48ccef0aa8977023
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	8	\\x4470e5a3836fa0d3f1894e27a473045492fd4e887d06c3933f8f7531780e37119d477515ac1b7f8d1329c48ae40b076d771e3ad595ca7cc1ea05fe53da05b800	\\xad340342b9359fd392ca9ec46f7a852a9eea9b77ea6ab047f9c28c339e125d5ddcb5649a6f5cf55bf731f086ff0b759a82ecb37266e6e5e06ff60fde5c914319	\\x537680b1ade219e7641675bbfb4b83d81dd771666340bf77910e97f73c2e981ccbe2e52782dae9a974d0780de5e29573ed9f054ebca16db1ddb9391457a59c005d6f5c86211ecfa810eaa3e827320f35e35f9ec09f8bb838fd80b9624286971a206cd0bce88405cee8d762010f18969d291549ca70e0e63aa0825b89d16e2a7a	\\xf6679af7992c4be93af37a08600f706670b9b3272b1af6f0c5b2d4c8544c34b33fee3b6173e6a65a6e4b2947cdd614b395765bf70b5d7da6f40ea4a4a15a763a	\\x2cb49797327852ec60ab691c5dc5fdcd03b24dbbaa959d3ee2f63ec5a8eb0643d3f28a341b8bd8f68f3fbbb8629bcc25e81c240854dcbfe2503abcad815263cb2a7be0d298db4be630108156a451e8092cb15893181109e66eebdd60d7d2c0d7a24e0d8a717fde3d918eb6912745d49972fe19be218b595dee266b41495b882c
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	9	\\x4d14bffb6c0f304540cfe9178feddb6b3ed374a2243e7e2bcaf9b69b27ad90377a2edc1ceda69dec825219a9d867847cfd092747a01c890618f83f25ae398609	\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\x6af1d16eef8fae345e10511b00db9ce78255ad9864997edd7dd47e3a4633cf8f5347b4e0dbf90820af970f31775bda4c5ed522daa0e53fb0b4a2ca2a059eef3c620091f0cc0fbad13aa815aa9210d5aa85743863917af9cca1f257f9d9884966cf45760073f2886dc0770c8e438f57b38c9058017a291df999f25ac05c49bbee	\\x6a5aea813c0d83dc3237212adf9559c178503ccff42896c0c5d4aae00a3575bfa0bc8fa037ec3cf94eaf8e7153945e0b2c0c4d7e55eb740013ef2d6ec7e5033b	\\x29d95368cc81e4c47888607a031f879234fbaf341eba817230331d40a62b721cb4d6785c3aca7e582a913363fadfecef77a1ab56e54297b4ca32499967fa45d608a90e3a2e05e0f59d88da52bee18ff11c30760694ffc83e70335953773ca8114ba2975d110200ae354204e4ca55d1685f197e3771f59bfa9de13334496dc466
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	10	\\xbf177ef57482c4518ff2229cf9a31cda4fd29f1aaf89adf0079137eb98b0cc3636d9fb0e6cc7b81cce1c02c120fdf4ca9eaa21b1c9a7b0fea52e9e3f31c43f0f	\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\x45bea20908f5a0855a9bcec25646faaf74a7c6f8aac2877371de0edc299dabbd9e1c9b0343aa5ed0be9faad5fc56e854f6659565d955f4695ac299ca83d5d28d56704150cf50662f5c4c6ff7a2b49796a9dfbb13cd890f64c91d7eb5ee63960c29116a480f456667ec43bbe3c266a67f55da567034c411863b3d28edecee02f9	\\x5a213554f81d43edff109e344eeba17c8aa814db4275f6c23ca090d86c7206ff74b52b57671d12305cb26eb44ff09580e26877c4578a7000d7a07a7f608f73e7	\\x935e1d34d876716aa6c172cb5a2ee3192b2bff63963f1982eb9688c4194d04fbe94bc8fd116ae6f9fdb91690c6be4d4d3b7e1d537c504d706b5942640af05bcdddc22cc70f3167892de1af0f1193becc04634ad2b8b461d5ac924ffac77ec5701e16f579a42290d886c9c0625d4f681aa71fb9566cb837894f78dd2289c218cf
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	11	\\xd65c8d38fbdd0f6aa02fcbd0b2983a48ad98e1ffd00a14aaf3801217141641d03c56280e5a782cedcc390df8da4322e9b58fc893abb5b9d1d2dc804e58f0ff0f	\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\x6e2af277b2473d53611fe69dfb73f4779b31fd0efd7050cbdd0f162835ec34264db6d704b4c91940558382e2ae904606bd817bf989b57b76b4643f0a577fd50103e7b0bbaf7e86fd03b39a8cbde8e9592deea96f11fd72a2b8aa3fcca3414ddfb83cacae1b2f300f95eacba7b59eb65b889a059a8a70b7fbadf5d94c7a2bd834	\\x19d0045c4c883d66048686893528d8b9309a587bd9e5497a0b67bb787e1d9e14adf547c46d8a80b9edebd7d5ad0333c6e18303e6337cd2d11148f8cbc0970b04	\\x5d30dc91d6e3cdde15a376aa4c47357b760ddbcd6fe614f5677a62d6069d6a4fd12c708d7f74e08e54aa4f866b299ceb39f3307d3ecbe544acc29e4b3d1f517e8a9a182eeb83479d4b9c5c65ed5abba5835ace2f2fbc2c55c34bb3b45c9d87998a839470cd62b20202efc161e9cd9bdd12b0035197938158c0d2cfd113f06db8
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	0	\\x268752c2748f1da86b84a112daebdbdff7c6910ddb62c07135a3c32030133a7ffdd7cb43c5c781fe4bbb60d4d365c21900fea5a08c04193a6fa10fa68fd6cb00	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\xad2d3c70c2a1e1123e8a5bc7491863e7e4a7087f45b0498214e3a905bcc6c0b7238eeaa35dd2e12b2e322fd7791db738ba2e158fa517758143c33fbcc0dfd68146e12c1e5fb7cb6dec57a3ef5a7bc6c70b381e2ae64856f1af4b383a3f044ae31e627ec3cafd0105d1e3deea655e4167f9f9c714a23a51798cc6d56cca035afd502f803dd53d19523144b7eacbc126efefc6bf64886dc0c7054ee9c190792cef32216eb27b9e6b4c9d8b00eb62beec75bc5bd18248cf0ce6d89250c4134811d7d66aba4c44772539c9692553cab93b5912c6b5affb8bc891b512060bf3b22501be3e5e7f5f8ed8afe92d4dd9a3172418d59542825d1b3a6fec6f1e95a6f334c4	\\x727925478f3b9ffd34ece85b3e6deee838795b863dc2aa1d96e521407818977e2a585b5f356c6542f1fd2af7e48f5cc894cff56b07a1b5c409230ba801ef31f8	\\x53ed0fe415f5f86404a986fa862556deef9959b1eb52bc5622953d045a9b71046532136f2684953bcb79b3bbee8ccf4f34bf99473057f716a5290c6efb250dcc22853cf4d200e3b1e78c314a0fc4f659af4b3ffb13af55e973ff1a817cc65567b316ca33ca82c4b1156b24b9b437cd0ff948f5b2c3c8ece72d6daa84aa2b621a7011a16d40704ca729ddb4b2eeb3a925c3655c9955969cb965c9b0969547e432c40a6b4beb564a31d335430f58cd778bc005a4d6a279fb1697e6938dbc3519d3bc230e0d9ced13a3bd8eb03e37e80c5fab37d892320fe97002131fdb478006ccf39f517d954620f25e7ba09eb3f64b3a3862ad9841c7d7d115355ad98d486a51
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	1	\\xcb1f7db8cf0c389ac35a5a2441180a410985ca3bff7698af61d22c499ad2dbcb5428cb3750791ea099e02ba876d30520425f155c48e299433d4e8441451eff01	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x793166c8c30352e6963ae6de157447309f564a2a1b38e01f13f5871fbdf9e29875d5dc60af22e3ce8a28b7ef55f360c091bb260598a99cb085a77f9740107b1c5846e261a4e268e95779085ff526dc5f4e689cb18d9d93dd28a4175a800e5c197635babbe883651709c64e1e5556db79e05da384619f3ecd3eee221d17ba0672aa98a8a6defd6569588a9d5b772e866d2ed625c90398afb0d3cbf412984d1a09897e1c07e555548482e5b33925b51f91580e5084064416ab479f6bbfab8bfd27143be42632b6a6a38b67a47149504cb119b9746eb91f2222d75349ed0e039a5deabd96ebbe4b667b26ef4a99981d7364bc5873518a62ebfa7b2a8eb3b1becfba	\\xc814a781fedd9113a6bda219167b825a6823050c812e2dd1d3fe0b5b370a403570252e73a0c8ce69d84ae15324723851c82d3680eb8cfc1475e5179762dba9f1	\\x24ec90278991db07a061d6c562a24b93803e3d820a61cc60019710d0380bc55611af3449b3eaadb011e4e445f8c4338f666581d211cdd6aa4035bc992332b9039141f71b7b03255d39a48fadf9afa27e3e9d3b1c5d8bbb5787c351e6ec2a86d2fafae7269dc149ba386c870ad2a1d00318361e520f1a71fab2e249d92a7a3e0defca8c5f9b92d1ac31cdc784fe823835b307a27cfe1f352d825c8d6a824f8dea1835d6679beef7e724fa6aed8817f51d3f4577fe2b6db9c947d5fc58d6743c1e86e13fd28c6769f1bc36c07083f4c5abf7cc741938ff833672c1089ef6e9422e0cf5afda5557cb55f169dd1ccd31ecfa7343c3623203f31b460550691ed61bc4
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	2	\\x8c4ad752dd6675e79ba1be7ea3148b13c914f2282aa6eca68e6bd122100566f4c6bc8d06c179aca69de37cc0710ba3fb72fd15c9a661363dde08b0be1f1f290f	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x6404262677646a4bc7ef33ded01417dfeddab5d70cff2858e05d81795100ae7f3d412472de68ae701b9274e62956c7320516caa99d9fb3cca61d0e83bb5ee04da78beed374733c1d04e7538327463c8e9886f54c47f0f4af3b65f8a76d1b67b7bb9b0356e3e209d768331c145135949fa833a548e3a2b39186d1fa5ac781d5873c5344994f973018c409d14522ce358cad27b5545880ef0edbfc794dc4e85ae6b2ee19695ad2b769cccf25200657e79391e7f643544f61be0ef424572f142dd28eb82a27a93a7d9405a5d5cc67ecbc6adcaff6efc42bdd16fc45ceb9e383966e75f2d6a9a22ad00e68220a65ac3e768431b908ba9d5656a59bd7161f95a393d6	\\xb7abe0e0ff998e2d07d2dd864aaa572477de143251845a2fbcef82c72f15a5b098f3ad48d74cbba9c7de9636372a8453a3f5a7d2fa330b574db211921d0f8f89	\\x01b353fa8b2b545d8fbdae105a560d40f93fda488f38efc3d7b6b383de0b0e2453e07a055ad9eef6aa195c1a0445934e4a3d0faddde60aa0dcfc73cda3a5c5c0f9b08b351a51be49c0c060512277084fbd7a76013341edd8f61b7b7909aca82e052da272833732ddd9f314016229ea0bb6edc18be1a4ea4545556a7efbb58875b178f2c165606cbba4788a3eb94121c08577c883a62bb4dd049d86e5c1b2fd862407eb552c812264f2d1ad7e269587655180ea111d8393b86df852b3653b370bc68cb612675c58473b976a6a69f301237de8b91515b0e1ee0244aa013c9e842315760403425e7f5083f3ce0e94e638b4800a67fa5caa05ca7e6d1eaca9919230
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	3	\\x2d379f7286107005a70d636212fa2beaf2d463182ca77815909a3d29f80d8f64371b66ea70663b919dec93c053a5ea55792202f0be205f3e4b07e8c16c7e3d0b	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x5b2155d447f072c6d1806f26a75c8b7da6f03d05acf0f32733846e7b88fbcdc55f58164f5e54ebe67cf25c09c844175dfabd724777a77032457fc8fa930f01f6d7f474bb118f6a4cec19bf8f8c26e7a1345e68e49c214582e13fbd89c8a148a887eabf5ff9acaa7d4687eaf1aea97c75a215dbe05e25caa0da82dab756dcacb96e82792ff475d77973abab3590158947546e8d2e26eea46b5d4e6afb164c108a5e5541849a584465ecc8973bbf5343d6ac52ef0ad93782b7a5cde06c3f92f2aa13a7ce8c52194ca181dfd4b8d89aaf590fe3fe6a8a180b6040f956cf6ae3edd14d74fe03e76320b936917f82441eef593a1765b3c8a6bd47287fb57eabe1fc96	\\x63e875e8b76373891a612d1747164ec3019ec7c39fb688d49afdba42b804ca4ae11dff6e430c11f08ca53bb623f7d5957526241208f74c1202188d98763be80d	\\xb183a9d67642f633a9cfa06eacc9759437c32a97af61b0e4fc392dfac7cc30eba594189a1a6977c896f5b4dc0730f6a9bf1c6ad2d8f2989ab6663d8260dcaf8439eeaa4a14f6301d68202cc1121fd1befbd45cc983960432621289e09afd2bb6837909879cd3e5918c046a03a3b67390e151be853472498d21b620e798bbedfba55a53b8120f4ff2fcf906e8442a14de42fcd2b3352812a35bd4b1a12a9ce31d8945d6fea991f7693ad90f17359a03293dce47b040ce923650b32105aee39c7936b6b1387e474e9d3383573b2635a9bb06b277fce7987d37e5567442983e387104464d94bacde2288e86c528705a4bb1846c94890317d1f135280bec4fcb0a40
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	4	\\x22fa7ca30ad040e9dcdd313f2e8c1326cdc4dad42ebd74c12f3166040dfa9e33dd590c0face43f7df3da956c015f351f07f8939a8cfe7eb3adb041b1938f7700	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\xb3e38e30fd8a6ca023fdfd09343e249f607d0015b094fe9b3cfedb195cdd7c2aecbee2f5c52f7213f75b12e3555380c87bf86ac4d24429c7b90185152c42beda125c735605da169db691fe2b5db034883de97a4ce330cfd3fd6768f870d33cdf55febf2393c4b976fbb4b1a54a948521e992f51de5ee5dbf31eff8ea24e7769a8ed12b56da03930db5b2ded6dd733aa4602bac22eb37bf2442aae8d7d292fc8aac20e627ce67fac5a7d2267aa22d0178bbdd403790f34e8b6291867e5075750b35f5873024dda771e0602599a41a360289328b1fd34c1c8136bc8133eb3ffd3d5e15b61f14e953a34f204eb49538ff6cfd06d0e617d2f44fc9e1a94a5eae012e	\\x8110c63870e2e0bdd761ebe073cd9398819ab7dcb239e349b45eb46a1656144ccab7c5055de1c8095f6dfb200aab8f2dcba725a5f8ad72adf7941fb5d0156e93	\\x9a2d2c6086b93ee58adf0b268ca17b3a3d45d743091ac771e02ff7382cc8dc5644529ad84491eaa77fdfb3780b8d2915a5d171b752baa9cb5122eed8aeff8b1cbe2b3acb4a191443a197fd566e5c9b689074c546def62d1d90cdcd95b39ace7bbb1abf63a14f6fad2547fb2d2e68d7c539459df3e46e879816d6b7001e9bb1c01e22ec285368714242cdc5efb804d47a4acefa345009cf2c275e7aa3144efea24d1f408d7000eb876ce971dd301343b7367691c2c82517e11a45ab672c294913048b2ba07482ed3175ba852a7052f485dcfbf267006a8980c5fd3bc2b428ef03dca7368cbcdd96dc89dca330e1675972fad911d312a03a7cfd40eb80482f816e
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	5	\\xb2125f1c4bbf35354a7738ec2ec00e75810f49d4df97721a0e676e46e127aa9f70cf04404ec5417a2414a6b0ce33e97aaaf7ecfb3daa24ceec7db1210872d008	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x768e2712db3a5af8cb788f69228d5fe91af32154f36a649ec9a8f0c3ca2631e157b1f7759c405b5c4b7136220dc301c042c3d0359eb13354659adddbaa160880d17b47747feaad8a888f83210b9887d455fafce2e510356fd39c0c95661d1fc4351d4a7112ef881ab670bfea06443f510a0957072acba3a4fa863cfe25dacdb9aef10dc04dd978a629c91b5b628ab8704b7735f5af542fcdcf90f8ee7cf2cb83f0f06559cf45c6925c809b1f9494816f47e55417395e9b30ebe7f2de03faee11729fd429f5e62051b86315f9c7e13e691db90f9537ac1926d2eefebafb70674288dae6c26b60a58308ae7b9872eddba9231a4bde1d01048d365d21ad56f0cca9	\\xb36970302b4e87508099e34b0fedc486bb969af3ecdef7014330adb2cf1dea1bc6dc139c0d553774db3be831d11b89aa2de0bb7d4522886cd02b8df79dd6cb45	\\x604a366f83dfcec0e6c31a30fa37b44680aed75212b7fc44b1a99df24b56b10c416531ab1560a942be0927baeabad2823353b19f12efdffbe36ac3c8e3fe7a37e2ee413608297c18d194ddb3ec6a537fe27365f6ef5b12b5ad019ff68bef6ae73c0a03c9dd031f203d4f1e48ca0d43c3838dc30575a16fb72c29ea3390778935490f7b82860b359afbdb9571e47afeeaaa9948e3c6bab0c74723d305d8a7ebd492d748e2c379e46abde86cc9a39cd66865e2d0f5b0a10627c886952184d758d40b975f5cc5b2ca01d09f1ce09f47181b50e8e7de3d2458d4a6f2379e2b877999df94de8765590786ea32818d72ee5942227873821e2dbf01bcaf598fb2e96972
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	6	\\x29b142d04cf662a5e3fae11791c581b31de6da64e808e67184a686292af3ac3a2158d303e95ecf6b1ff13049e2f86bee4138e2c94eb8f2ef6514c98785953f0a	\\xceb610b46c4f5318a3571f536eeac0e1f668f3245e3b4cd902185962cf4e7f1c395e1c7e1e42c775975f758efbaf85f7bec83a6302feb8140f877fda91180d77	\\x698454c29d3c83763f0d4b2ee11e4c63de9968daca7bfaa05d5730cc44cf888f8cc03eba8eff552c3edc2a165364e3e2ca0fad901d3f3f3044dddae28f6c82cfcd9565100a0cc728cb66de7e3232ea11f2a8559e3f8a7bad857f413dd6e872376f36db2565aa879d3f1d6e439a2f5db78b754ee5f38e3e6b8dff2d59891612c76b902a30c78730fbbc3119c2d156b5b4b3e3bf116fdf9f93c89c060c092c8719f8a8eb9358cc01a1876933e4997f525891d14eab597271148675c6d6babdf65eb1a790848a16f99c849525cd50e1ea8ff4ffbf87a0f309fdde7a3b0e51fbb80968f8b118db6708b74bcc9a1baf4f4fd85e1ff6d38529fdc910a9084f0c5d248e	\\xaba9daf3b1e17760b874d78ca400860e49bdc3462ede46d873f32d93a3eab7ccc66ab816a556c4442f32afc1483f58e89505bc1b2e8987d59540cdc411552cfc	\\x21f89d2c1c6f8781dda4b89d4a09eeaa12eafd8197d40840e288bc7aaa52695fdb1933e123abbca42601d064106047ddeb9a9bfa3f3459c6cdcb43f487148b94e6fe3abd8ebc3b2e74fefb38122a563158b650cda09080bf3f35ba029ef1a127600f0cb70f9b8ce5c459bfa55c4e7ad779d2db98a899fe6a51296ef52eca05cb16d66974433bb9b2816765fc3ce1f4a14dc6fc0e4133274110b6147f62df06903df93cc38bea4bf33f78539ac34ff6a207719d5640114a1f436ddd2c409cfd08e538c831a226a1bf666c8b8a3c4d716cc57e8db59761bab7c0f648add8eba3b8be1044f0aff15950eec5a2356c38141c0563922bffda508b05f6bdb36389b440
\\x0313708216513ca3e006e040fe5859d26ced6fdd688ecc4763edaa860f75d61cebf7d873546cfaf57c91c72046165323a0fa2982e5780e4f11834cf20c4dc99d	0	\\x99808e9128772b5de9f6de61104ddaf5fccde371d9eef42771895df466ed1b33382da35e298819987d09c0f9496251766965b62a25ee0541dc6e70535e25f407	\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\x8856e35c34fd5fa847c23854c0cabb2251963ac89e30678cd41246c860194d146c715640a77073970f03cc1c017234ca6f0e46a86cca4e63a74b4a285a193eb888d6841f3444c721e485e8731e9662b37a4a74fc5d7bb03b7648de1aaa2cd9ee3df86ba2fd5f1af3fd80176f789bdaebb0b09a258c241dc6dacb28ef2572bf47	\\x4136c7dc6575a67ed2bc370e479f393f35b7849e7c3f3cb9204d041ab3975ba737c3ee4d389290e347d3dd06f2cd8501e636f46c0252e5d2e2606870cf7d33f8	\\x53e66dfd07fc88f853f63b0b14132f4ca7f47a189569d8905271ed6a47eaf2bb984ffc193cba481469f7cf1bc2d31a2f03ddca978992bc6c370c689003089436f11f7357d294b6a88a29a92f8d0160c9bb42366490c99e955dd05116becd012e57b2359ba5cb97933a1bb4b23d701b6df6f52b701973bd70500baabc1ab211e2
\\x0313708216513ca3e006e040fe5859d26ced6fdd688ecc4763edaa860f75d61cebf7d873546cfaf57c91c72046165323a0fa2982e5780e4f11834cf20c4dc99d	1	\\x695e8c02a5efdb31122f2a44ff8862ff0990153234654aad33cdb1b3142bc57c39b0583e4ac0baa81cc677252529a4ab344d622bd6a98c66b05193b85cbd5b0b	\\x80225c7b93b09fb3466e5886d17e390e5d87558e3b6b804b89bd4f3f8a408a231e8c0b8fb1ffa49cca5b3e3c917148533d50cc19f96f2d7e9441f814c33467dc	\\x1d102d92be0bde41344c2c9d09d66c28d4859ac069ad87f98f2003894872f9239bf7bb968ef6125b4334f3f1022d8c557a050060ec1f80e10436e3dceebb6fcb1a0b9ca14e443e61cfa39a1448c9ca4c5b2d0999832890158266f9bea00ba59eaf4d992285dfa6ab6a2cd21c899caad1d5e73f284f7869b75cdb74982ec5cf79	\\x3adc073d0c41a6a6521f40ffcea7dfe315a42a5f2dbb6e5781301f38a6c799b72a2b08c6cde94df924dd975760481f2321621b3637e4a5dd959f0e44a356b448	\\xb4b8c58301bbf57762bcdc17e7af04a75a46d9cd3f44e82e73effbff17af217d9c0e6a98b7d832829ef75e55c45ff2d474e76d47347d6ee94ad2a131057f5815f0d2e869bfeac3d2a593f0489d746c6ec180bc288a474d1522f2ef61fe74be306408ea58de2fe1482599229cbdae70ed848df076da40e50c70ba97d60daae668
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xdae7be97cafb18c47f5e43da99d7ad3580006a008e4cfe6af886ba5881539e50d3c007bafd71cfdca6d4f066aa588f48bf19a70bcff970b9236d89552517af80	\\xd503ebefe1f774e2f53b4e82de45aa1db7cb7e4ba9ae6737419827de429f435f	\\x0d55ce7aca149535a07dedfc019ed5cd0a47d74c2a4c43395ef066f800f045657de87fed8b1aa68f74f7cb14527fb44b2a84e6f9d6b9d7fd0ec9f8f58bdd8b46
\\x35a590a6a6fe1559aaf9fec32599ff0efa554315cd0b1e4f8933df1b209a47edcd2d30555597a2c596f7fa8f9439e7981123948b10c87cc2ea65af254dc7fd05	\\xacc8a7cc19d47b541b70edaf8a4345f6ad7950cd9c1c3f1d146beee4bc568040	\\x2259bad789aa224c46363ed406eade879b67c6b03e8f2f9afe2558d8b061b11f99aec664805388420ed94786407f69aea36a4e7714372fb45cc6f28975a042c0
\\x0313708216513ca3e006e040fe5859d26ced6fdd688ecc4763edaa860f75d61cebf7d873546cfaf57c91c72046165323a0fa2982e5780e4f11834cf20c4dc99d	\\xe46513e99afe40665548605a54282be405711d05951f3dd44664797b3dfd7c76	\\x22b28020722e5f1d653d726c3016f8eef448ecbf47c097d808efb07a693b36ebe7904ee9b84df49488a8d2772c3eaea4d1cd20c9251c583f75d7334fa8f438ad
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
\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	payto://x-taler-bank/localhost/testuser-A4bLVg2t	0	0	1587663114000000	1805995915000000
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
1	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	2	8	0	payto://x-taler-bank/localhost/testuser-A4bLVg2t	exchange-account-1	1585243910000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xca6f9dede950d4595c24f0065097258c351f38f621e243985a06a09029db4f1a2f1a38d98c2eaecafd2b9279b053e1af83cc79f35b67e251d2213421e90e2833	\\x3ef58d93b1ce275b9090e8a0652905a9bbcd5604fcdc68cb07c20c04f11e2c615b80c1891d3ab7e0974a1f556e329af8398d4b1a5f7735ecf23d7087890e3bb0	\\x179ade64d21af4c3249b498e641a3030a40f6a8d43d2812805064b9932425421ce19a7a3e263201773d1bb6c3dabcb6b5d9cbfb0175d5417c1fbd831ee288e61c60d8f49983187ee9cea3c9a4a7ae458cc652d7b6ce48e48d8b8a35d8348dd7db5b31a4d36d5c63edf60ae3e0bf7cea8a7c484b0243852903c169d89c832057f	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x789ca3b4cdfcb672c983ecf00d5e89a80ede06beaec2f6061dd7b2104ae210bf85982eddfbca4b5117fb2c4df6aa7278c6a1d0c27051709823106a421cb96b0c	1585243911000000	5	1000000
2	\\xc7ba3f90c3e06bdca2b0f45d1bbc59e703d9b930c83efad90799e529a5b539c4cf7caf55bfab577558e2525e6e68feab1b36fd8803c031d5a39b9afa7ac896fc	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x0a580bda8921a7b8de3defed85ecd83cc0d7fdbebad7488ceaabe4a881986333b878b63279dacef80c20c972c6e2958ad085eb3f5274be1c6f652f7bcc8166ca2f1787dbf5e521916ff855fae1133caa1527b5b3322e183ce01847db3c0d6d2cadbde02423ef856992db6d53e7a964e018a5792467e89a63535cf6f98416f11f	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x0d37dcaae052c20716240173a72f8b9c991b8cac9ad3122cba8305c785faff20c6d5e68f354fb30b773f6cf77b2cdac3a873ad8ff00d3245c6677d2646f4ef01	1585243911000000	0	2000000
3	\\xc30bc7922ce0ec13237ccad9517652d1af84c00ff6482718442a1061d48314110b40e339dfbc42b6739903c896a5796f15d020a0f513b2984a0ad8b7eb43225c	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x6b34f0631637a8755cd487e81325bcb96196d2067fdadb66f6b05e90163c63c6654e1ea48edf36ed229207595d6f7665bae1780b12b4e56c069e6487a4e165702cded0d930ef400054216fa94220cccdd93d1f843f9bb35cc8114c0b85160ed75c07ed13d80f5a03b3cb6ac3497975ba80756c9aea9234c445f3c22735673574	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xa118d0683751e2bda5b10b47f5194f59863be15716c321957cd942c40304d14aa8290f410d7a4f11bc47687e788413059a916e8187cc5636a89e63d39551aa0a	1585243911000000	0	11000000
4	\\x72360577b6e4cb3fcc73dc1dd36840ddd0cf9861c3c18423610b84a749f4a864d311f5743abcdf1fdb3169163e46821f01eb750bf797102e9bcbf00228833abc	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\xaf9fd2ac977a0c97fac59516e0f7d80827068acf73286836c2004ea0d948d0f4e8672c73e97c3144ffcea467c47c0905128be99fb283202ad31ec3a222390a98115e496ab0ccaa287c15bf849f263afc2e27ac86fe41302cc0251302f12c877285927065ccb67f17e3b8d117dfcd3c5504a65800e2363aa5528f6a8aba298a72	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x5535c40ac9519d435825cb7931f08b221d0ffb07e85820e905d76cbb66006348b8c5e08b75b25c11612ff0df6926845f7bf7b78e1a2e4e719d19b69346ae8305	1585243911000000	0	11000000
5	\\xabe2737393fe52873eecc8b0796e9183661b0b948be4e1295ef6bbd40856030a48818f07fc9b1622059e984bb4d033787c5256429988b41efd52afc83f2b1237	\\x320372cd907bfe5e64120d67a39fb1d9b401c2d882023f4ebdf8f5f0a6b39020ec9bbf1b752bc2366a088f7744c16b0d54bcbd08c6877bbbfddef4a7cf7b79b5	\\x37d07b6621874ede9e74d688e0f89870a3d49d2aef6c60e2e4952e6df4129816dbbefcb3d1c483cd7baf8e7d63c359850db93b11fc14e822a117d4d8944b96fa70eb9e1995dead4ffee6b26358e289a29dc938dbe7b50e9230c7911564b5516fadcb38b2ec0970bc91fe10a7c3f454c3447d56bba15488ea672e97f994aaea2c	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x040def8bef3e0e3159ab5f4fee2c7fb4aee63dc8ecafebba3084449f99653b038ab0ccafd127c847955bfb4ab02ecf15e030df8e511249e02fb1bbc46315130b	1585243911000000	2	3000000
6	\\x387671a7b54ecb09a393853c18b9f3128890887a1627da31cf316972c37c3a856f1723e1730b6c02a0e862879b79e1078432476ae1374e4844cf70a5d41827f9	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x62088785c35e58aae9a9096a1a0681f32ee3b430fa3acc712de360aa04fd5f12002ca04b0c7f564614bd2da9b17653b8afd790e5ddb8b4a820fad90dbdc0bab9885902dbab7f12b47624a1cdb745d79fd4832750762f67ecec5d505525d5014a854505494a8b44014cf685d7056dfa4007e5e0b1174dd5f2eacd8c9d63088899	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xb7747bcbf6de46d1bdaf9281f6d181657d2e3f7efc4f8dfc536a72171c5ac52a4f4226b014b2a31fc19b793d94ea8408ed18e5710a7ffcccf4bac23373861402	1585243911000000	0	2000000
7	\\x9336efd0595768038f55797ef0d6c90589554eed3bc4d72a90e4a48cb313e6462fbb0f298fe56fe76285fb0419c1c625f1a8d2d462b122d76a16f617e45ecd5f	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x5ca42eb597c5745c25a816ee8eddcb38e73014407090aa052b50f48c4b7bcde7a8d62f1fc9421ce3ce3c88cfcdfb66fda652864036dd7bfbcc95c0b0a64d4f2d64e6350f9a85f5084ccd6c5c9c42f08f49fa2cbba71a086b10768a0c79c21761e547921515a6e8563af279b14b50a6ea43be5bf542f26d399c940e14a9c891e5	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x5e0ac659c1bbeb0d56e490af726046fb29b0117aee1f2276b2127710e8d076ef49f051533c2a2529d34f6ae1500049ffb335adeacb26d2b7ba09943873744d0e	1585243911000000	0	11000000
8	\\x505b716d74185cfeed6631f1ad96ebd9801fcbe96aae366577e001ffb964080feb2236ce897a895ecf52700278e050bbef87263debce7b880873b9a5186c7b93	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\xaf2903f620995c9370432494fd0c87b7539eb36e61835f8e623989cd82de43d0f1a12baf094ecbbaf8407273d08a60e81e10b4447e04cf53d2dddde39cd7a68c2f9c8ecc1c3fcd0637ab500a5dde5f60d423af9b3d63a2fbb1cd8b15f9c08bf72b4cf50ff57cd3456903d596911c7c8126784d6930a643e47a9ed5761b13f87f	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x6ee5c1b534521de0eda3322fb4bfb71d26ced13577a436d4c7cba6d91aa1d43e41ba6cd7c456396f2332afb5b773b7f53c5b2458359c1f8743a8eccfa9c74108	1585243911000000	0	11000000
9	\\x0bbf4e48a7585153afa235680278b6d987546177f67af0422bf780eee548289b26e4b76f33b69f23f9c498d79cf7ba753adc1ce76366d6a012475f307436dcdb	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x3087aa0c47aaee0e915fb0e64b9fe944ed503d156d657896fc11689d2fbcaa84b6834fbb012a5e18db9b99427994d52b04627ad8e121fa761d12772e3e39a2ffb6dc32c84b4418514bfbfb730a38f80ba5ab5c046df9c3a0af5a5361f03eea0c2e16589492d37f6d142db8906f14d7d6806e0c6564a7617bb0eddb3fdd1dac61	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x00a66b7fd1eafb4dfa1987851ceb101ee0acfcc2df7076f2c370669a2337a33c1d794c34d2f74908eab4614251e3e0e4f6747a43aff92801c0f3bdd595bf6b0f	1585243911000000	0	11000000
10	\\xc0b2d129369577825e0b09091cba4e1a447d4d54e7813cd44af75b961229038d625cd2ae68c700903655057f4b2ba4e4470c16ff869b93f7a1c57e07be3c592f	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x0d40c7cdaddf98894b5e0c422c38d37e3c4c8b3da07e266980786586e3efd4c5ddbb17610a3c70264ba8f97273195743b8ef014d3479ac8b1275025afa765c4e47ae8ccd5765c1c6d08b052de4bf1775edfb6918a5e0d90f0bedd5d721e1ca1ed26fa6a79cd8d7eb5059e905fc2102f3cba221f77f35803af0d680077d1606ca	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x5b198e8ddb8d9f6d2cd840108560ba6e676084624db574cfc78e59ec9d9a10f289d3e4aabf66e5df93cd6adca64a0c9a134d8309063d0b3c0bca6fb913e89106	1585243911000000	0	2000000
11	\\xe1b8d815d17e0de423e8c64ec74b1f9e73878159f8fe45877a14620a6e5bbca836248c13a3f229c5ac95d6ef967fe9b1e56e732f1e0593a5ca9481bbefa03f18	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x9b00c419795fafc9df5da321c62d7a1ee769ea82bcbc851296bf6a8da093cad186142e853967405b82f6d51fe185811e9a3a7925bf100cb803bd3fd68643bfd6948d47134762c30f34ffb74382f2cc888946302683f57670e461120af99e0b36e1c9da657d1df8b1f7751cdb7c5adb09e2660c276a159a7bdc328788bcba2486	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x827d86c540682cdce23a22ba3cedcc3d69c43932ea424ec0414a0829127f8bfb6d3d8975fc5222be19d4843d095f7a72a4e78e1824410c3b2e2367193e13530c	1585243911000000	0	11000000
12	\\x4ac6622d142fb025e5084105db3d3b7d617dc1c18971ed39221c649c8a295d911e7e8e599e972e8b314363162bc50d868b35aae898f5c39f6640620571002fbe	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x2b8b727ae4090295e17cc61e98837c3f3ccb54a636084ba3a3c12cd12cd07561704a7da0e61d7e80c7ef52ea3f548c0685baec8da19776417191922a902281e8144b6a4ad941c571f3eeb52dfcce66ac02ce73f5ae384afe3cf5b0874e14a694130561f08a8304db065da7fccea53952f91a80f0c61196c8a259a9986b212d6d	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x95b14137f445e2bab50e5041887f08d69225650a6ae0ef62b6296e7deaaaffffb8e9c34a9da9f58e9878056a708aaf63fd913b8304cc83800400881c4e91fa0d	1585243911000000	0	11000000
13	\\xd8d16cd0df6fb5a036ac902a55403688a655631fde3a499b0796f5585a1fc77a5b2d667785ee62293b98199c25775544933b8331168a5baa551661e14b36999a	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x6c9547be19318e8b8f4f474fe906961d4ad76cff769aa6e43fb73b9257c1caf0b74de283e1f8c65432eb4d69781a65d2deca1cde15f4dabf57e5ea8b3e3e79f549d09fe33717095ca490836ce3c890fc29789ced6df0b172e7830b96451fea4c79e4bcbd3ec9c701f75076539ec5d1cf5dd6a05317080619770dba32f465a184	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xd4da768135a35406deb4ff25748e43e6d58e6f0364fbac455bda65d98f76814e9b11ee4d28470f9b3b168f016a8be4e5bf989fbaf45246d703813ac910e0da07	1585243911000000	0	11000000
14	\\x68bcd63ce65bad0ddf65bf4281936ef1da8b54b7361fc36d886cf3e571d0d14965cdff3fbd14e21ff536e10c6ca61ed3774a9c02e5fa995ec4b42a5ee2741334	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x05714162a6b89d317b0decf5815afc6b54bb61af2fde9265fb95db370e8af4755f383e7a9c7b001f28735236a48e02c7fe1b8ecd37f8688bbbe8e5d5da18a4b83475fe078a6bfdae0375a5826390a2dd2fd9a02a5adb20824a10f35e384f7b1207274c0680857f5fa83b41fdfaab1ede592af0fc4ced79a83424bde7a7d6d234	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x7b2ad127251a5766fc6fb446e6dd294045094ca6ce7116b81207df2dd77c6d7cafbf45207283222c9146f40503ab4a744d8d714b4a45d0912ebf4a95d2a2be03	1585243911000000	0	2000000
15	\\xc93330b77e9c692a24583a2a7adb422e7ff8e6227bdb19c63d233d4dea7e1eb16a277ab236fea8371314ae5e01784b43b72181ee3f3aa6e363d31b12ec371c00	\\x08c108861d20730b4078bb357dc9b801a4b6db0589b90b26885f6032cea71766ff7aa7bce983d09b9405be8acd6ec44cc2e494f0b80a16dce1b36252ef7f5e3b	\\x08e411a76c2d2b5072fc458b4000aca1969d6cd495ad60a3d4df251de96151d65ca9a7d1d996b711b5f62a0544d5c4e50364b015d83a7f497b33affc18f5c965b9db59f12f8bfc3b653f522434f749087a1895dbe38d24a3c75f3f555d7b30090585f9f81a9353dbd7c0679e17afdae69308e9ce9dd1d9c877b60bcd2334769c	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x63367a4bc95ded4ff3f6d81bbfeada50706434046b0ff89443c2d40227125d759423fbacb66c55f5db18e59a3299728351c99f444373513fc6faacf5557e6308	1585243915000000	1	2000000
16	\\xb95da8874848b81271adef6dfbd9a34b9382dc3c1bde75c1681de915344ddb627bc1ef1524b2671aab4170afe7d578139fc9cf349f00755de86d4f9e2645ce48	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x99b52643435e777aaed6fca2d0214afd6a1330709785f30ccd0e57d712837583a8c150037303d9c0892dd13ca94d6048ac5d6d243e1545578634e784d17a6c4b84adcc16bd2df98846c5a0ba55d82972988f04d4cb260b5363397f5d834382bfbddb461c3c94d02e7a47726ba0ea61d9d1c0583a16aa0a5d355fd620b141b0b6	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x30205435915fe67fa9df2b928b27dfe117dae1f93d5b978a37eb0149fb498c2d15cfdad5b581109ab7981c69fb4955fdab1f980398dd926d634ae8d3b7e0860e	1585243915000000	0	11000000
17	\\x85c0d60f51f851022a7774413114e87149abb85cf1d10d49ca786906955fd006dd12dbc0a305b7f867781324c4723ec1aa61ee7a9f58c74cea73097430dbd3b6	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x475faf45412a8c0e8f5544e79b05bf27323988e1e7258a75e839ebf7af0866f123038486fbdeaa724b7b1c66c13d619dcd5656d5080e83677adc82744da9d0397843e541914a791f315b603f1613b2179cbb8cff0515be5fe83cc1c2746d30b104a607d3f62c343fc73c7f473b72b8942fdc4eb296ea87e05313d2f28a67a6c0	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xcf751c62a80fc11ac3de1971834e732daa630e900157c935258701f40d579359a3f32995407edca8c046286a2a6d5540749fc27c87f8a5b6b611e786d1b91501	1585243915000000	0	11000000
18	\\xc29a7a076acaa06ed7dd1a0ce397d806748399ca13df0a76ab33954255a9492247a8b66f57eae64801fa9ccfd82fa73cd08e2c87a1bd6da749df8028a1f84deb	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x33033b1fd8d8b39bb742f0fc05ebbc372bb250ba11a316c6c21107128ce2595bef93dac5b80cc2b1df4872818acb999bd6548faa4dc8dea8a2748229e98364e25d7bd98987167bc366ecf426dc6fe29b488d56a668b8c0c4a871420aa6f94bcb01930a9d129c500f28c047ba1a778da31cee0ba3708a31da7f2ef14edcf24ccc	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x29c3ce2d8f97237a2336028f88ad70d17dbb685a659dd90731b0934533d038df76405835733d6b1fc80a0f90b5e0660d216181009fdc008b660cad5f12d18603	1585243915000000	0	11000000
19	\\xb4496afc12473a85a090601edd2b24e6ff62202b69368999991c8bd8ac31501c94c961ad29a8f27bb332df3e5aa9ed95a7e15eaeaa4fb3e49238c014050d7171	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x38ba9c63cd474440d78d50d63cfdb56e2ae302d2bdcaf5b1810e25bcea12995f5d89d9094c54aca638078d8c07cdf7c8816223aeb9647b655f375e623abf17baecde0308ee9a59a953fdfddb2bee8dc20449503be9811b4dd91404f478aeee7494680125c56b5919fd0a70eb11d7f5432dd46fc3540b3a82a55b564a03dbecfd	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x3639830c1870aea0cde66e404b1b70f1c7eb3ffa229e20364f8c9317c4aca4aa6dacc63525a082f90a959aa37d4e560b1b0056d0a052ed41da06e1fa665ec20b	1585243915000000	0	2000000
20	\\x2cc751742f1afc16ff5637897001db4728626d5d61590359c9bc2344fc0b2bb395e1fd3f49001207678ee8e95ccd340bc1004b4aae92ca4bb1ca1f1900f4e773	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x91a0c81280195a44ff11b5d51b343f9bd4ab7503ad7c6921b4905884921cb3f6611f9a1cc0f71a4eda6854adaeb9b36a2c802bbd603c9cee0aa513e84890c8f2cfe15229b122dac4b5e85a892f04d0e70058c818bc290a8272ac0601ea8aac1443e5711c0af552427f14f684ffb39a96458f7baa9e443e41c6d1b6a90bfbe597	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xf36575347c011009cf6c95a896d71ff29c8629113860b57fa739b948cc949e96d51b280e2ecc2475e1cfcd77968b1fe891f82413974327a5f3018e71e1520b0a	1585243915000000	0	2000000
21	\\x89349226aa59486579d8e8b5259ad7559ebc8f3c1b0d10f7bae3514c99ebac0e2a3f788940c8d3f5902d29c8e5b3452e9c49fadef29fdf6fd02669f8728428e0	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x547e36bdd8676402b43741ba6170c47d58a1a7d0eee5e5b9e0609e28a6803476c242bc2c0bc362c585cf16c7364a4d739420e82074c6a5dcbddecc2c669cc87d345785f2985c6469c1213973d5b1dbd1e10cabe62325f003ec43a07ba6e740d449f26364af18bba2e9254ae04aea4cd5d43d614b4d588f71728384c11240f4a7	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xde88c33de5318380ad75a6510c8f122046334756d109ac16c49011b3a71e2b3235570ad44be664e831304573ad17cf46c3abe81a8baac20e4893e155e37e5808	1585243915000000	0	11000000
22	\\xd14d4c88238ee4a8e1944aa16efef126613be939d0000761b5c015b915002c3c5f0e8e589d61f6daf2c921e8d22b8b055786bab90dfb481da7a937315c246420	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x40faadffa0bbf1bb691058f02ad927d47a35a3e6802d96a182b9ba2a3f9c68603f6dcdec3d02b2b29737971fa6dbbdb0ccc15bf4ad90e1fff1017cd58604a1876ae58d35d60b0c712941dacf72f00721099d0eea23d72641fcae7f80a3c0e18076f0dc917dee1e1800cf33120c5fb7e04b3339bf824877a5fd7e431ca5d8cb84	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x9423f8621e65fe0f38c0a208bb19f9216c66606375385a401b9a8892cc343fcdb80b7d76747b345f4d82b2b44b2a2da7dd5e68263b3a8b7559db96dd6bd33e01	1585243915000000	0	2000000
26	\\xdcfa3fc4f4a9f82ce7a64389c1e99d83ccda8c1829682d7ac6b24ed8ded2c83baa0f7377d5fcad4408361159ecdbf57a3879403f966ed0f40004d12d09da52e5	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x1e957a636a73fb64584f29af403edc331a5dd09bf107ce885715e1438346f46967d53dc38408a3ac1b44eb7d37750a845b0e69df6b507920189d28336c2162c4e6fb9d7b7200b641e6d661c1f29003db0bdd828143b062684860370174ea86dcc77ce327e01a1cfced145cd58ce40dcfc223a3e79b388bfe0d01d7916156c505	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x3cf2e7eb75ec8e8d5df217e704e70acc13f32cf88e4f0e31dd48315417269300fb620fc8643fe3ee53dacbc726ffdfbc899ec0fca41b43fbbba69c51f356be03	1585243915000000	0	2000000
23	\\xffac3743cc28c8181b93841f132ad355ab0ccafa601aa7caa920b69c7f9cb7e34a6419e0313f4bd90fd27395aec9f934aab0cbd33b606d7f008301fce21d3ba6	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x9f0dddf18196582b2a12af21e7d51e6358b080898fc9b34cbd391af722ccd7d11a3f137cb8a1b814da12f9bda715271184c2830e359e9f8331f1f768b922eeb2fe88f002f39bd6bb95a8522265bfac5b034048f2bd6e495d39bd98042bd9f9e969ad38604de4acc91c142fb4f6924043eed36144f6abbd7c41a4a9307c475259	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x5a7a34e78fcc03cb8e8c1890c1be86a23e12078f629097afdefe2a59067ea904104a05ad6fc9cad483435d89dbb48823e16509ef1d5c6532c88f947a774ee606	1585243915000000	0	11000000
27	\\x3447d49ac0635d7a9245825e36c8d5509c8debd504550de6242d41157a9670afe573b435b7434df05d90d6a63aec5a1dbc1add6eaed4ab572d93fb3984626ed2	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x4246f1db97c013c5270a8b6dfb10bbefdcdbfc81f07a7eeb11d202261583a5e17ac800816e4e377d0bcc0ae1ab64f7588859e1ffb7e6a6936ea1716dbcddaa353a42c2f2ab408dad85a71450e6f08152e27f497745c8aedaca819aab71e050ef84fe27d6b0ce723cbde8b480067b04fa437d4b61133701f1cc120a0c044ec834	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x017c2baeeea0b1a1a3bcb4bb9116a0f6e2bc3699ba01221515f6c3aa71aeaa33c84db010bbe39b6db3014b04c4397eb95cf5bb8ec66c0e935c5f04cea373bc0f	1585243915000000	0	11000000
24	\\xf1e4f8d69567dd0acb80e070514d833d752f948dfaa0a77e3fefe0f59a1489269c394e0d285c9117480c174a72af528b321aa666b3e8dba2640a0845be3ab7ef	\\x9d3056c19bf08e215fd630009d993c711c43798e25963e88677709aeb77b52681aa67cb2b2f7d398c50b54d0349f260e06e4e61dc13afce8934a0e7a500e578e	\\x7f5c541284d9a5b870e602c4199e60b354bfd48fb5bc84007d6f6e2b995700064674cc45ff461c35a20ff88f906870ee1ba5868ebbfb8cbdb830758a64bff60cff34362916d262173d75ecd70697997e65d649e309e7473e26e73ecf83192c7394545b3761d7240c04629f179a01478cb20a0e448e7d089099f88a34e7c726e4	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x6c5c99eef5b2a95d675db56c59c0c40d0c73d78ffd1d8c20cb4df1c340602d7a2b41efd47e3e1e33a9e2458d5d4b233eff306dbd7860d8d0b6ec0ecd4c6fc208	1585243915000000	0	2000000
25	\\xcc19b903b9496ebbe3746f477ebe9165187d415f65b680e76cd6517e24f23bbc32713d5bacd90d115edcfdf9353515a5765bf15f0a86511b2a5e30fe35f429f7	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x0acd8f88f88786aff8a3aa4a513cc1b84514586411fab729885b80ca9edcdd5af283a179c68e70329e4b7a93857e11c2c9575f00272d081b7de183e6a6183822cabbbb82caa8d2b25b0dd50d16923f72b2b12afc18cbe81f683fc9bb2a5b507c9d2ca63cb6deda5b83084edc99a7ae5ed8352b7cb26452db274f99196233e55d	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\xccf465636e72cb461e154716305a56943ae12d6a94f65c5180798cd95285d107c610a633f5015c65436e1db31c4f1770dc6a27cab9793980be54d353604f510d	1585243915000000	0	11000000
28	\\x8d884e9c43c7be212ba2f10be68d208a51105763a8358922d3cd21a9dc26a495ed3cd90671c94eef2e3f4565e5ff3ae28c85cdcaef54ee955530f68cd79a84a4	\\xb0bea61a43e6362955c6a0ecbe714b5c1dad8f9d135ca0bd197024504bb2081a67591892ea149b60a92d458db7bd374df86565a7e6cc868b83444d34f76558c5	\\x352ae801d0da043ad66383f9f9f83e4eb136c1df14ae41b6cd4ef5b5a4209d8ed610d767375eee98de067d4ef81b1e7164dc23cfddbd19b9aed9f75932c9768dad80db8498ac2f32ded66be979ff6c93826d8199ebb42fbe96c63b54c96ad748efaf0c23a5c3d105bbcf6dfafd358529142e2e6bafb0c518968d3d9a70704f88	\\x36fe1cad51f8d6f37ce72be219abf7ab32de3cf2e075ffa401aebc7f39a31942	\\x3b9dc8d9d4252fef6ccf3ce2c47c628f18f2409c590775fb15cd8cadc514c412f3eea153f726f44eb39f27e98dc27cfe1195536d1ba9dea5dd329e8949141c00	1585243915000000	0	11000000
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

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 2, true);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 2, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 3, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 28, true);


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
-- Name: app_banktransaction app_banktransaction_request_uid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_request_uid_key UNIQUE (request_uid);


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
-- Name: auditor_progress_aggregation auditor_progress_aggregation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT auditor_progress_aggregation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_coin auditor_progress_coin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT auditor_progress_coin_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_deposit_confirmation auditor_progress_deposit_confirmation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT auditor_progress_deposit_confirmation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_reserve auditor_progress_reserve_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT auditor_progress_reserve_pkey PRIMARY KEY (master_pub);


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
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, freshcoin_index);


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
-- Name: wire_auditor_account_progress wire_auditor_account_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT wire_auditor_account_progress_pkey PRIMARY KEY (master_pub, account_name);


--
-- Name: wire_auditor_progress wire_auditor_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT wire_auditor_progress_pkey PRIMARY KEY (master_pub);


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
-- Name: INDEX aggregation_tracking_wtid_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.aggregation_tracking_wtid_index IS 'for lookup_transactions';


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
-- Name: app_banktransaction_request_uid_b7d06af5_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_request_uid_b7d06af5_like ON public.app_banktransaction USING btree (request_uid varchar_pattern_ops);


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
-- Name: INDEX deposits_coin_pub_merchant_contract_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_coin_pub_merchant_contract_index IS 'for deposits_get_ready';


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching_index ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: INDEX deposits_iterate_matching_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_iterate_matching_index IS 'for deposits_iterate_matching';


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
-- Name: INDEX prepare_iteration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prepare_iteration_index IS 'for wire_prepare_data_get and gc_prewire';


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
-- Name: INDEX refresh_transfer_keys_coin_tpub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.refresh_transfer_keys_coin_tpub IS 'for get_link (unsure if this helps or hurts for performance as there should be very few transfer public keys per rc, but at least in theory this helps the ORDER BY clause)';


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
-- Name: INDEX reserves_expiration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_expiration_index IS 'used in get_expired_reserves';


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: INDEX reserves_gc_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_gc_index IS 'for reserve garbage collection';


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
-- Name: INDEX reserves_out_reserve_pub_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_out_reserve_pub_index IS 'for get_reserves_out';


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

