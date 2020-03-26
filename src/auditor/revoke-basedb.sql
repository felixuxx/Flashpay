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
exchange-0001	2020-03-26 19:26:49.92415+01	grothoff	{}	{}
auditor-0001	2020-03-26 19:26:58.388906+01	grothoff	{}	{}
merchant-0001	2020-03-26 19:27:01.737972+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-03-26 19:27:05.284133+01	f	245cba88-c96b-44f9-965f-636e193f978a	11	1
2	TESTKUDOS:8	AVFJ2WDPP5DB6E37XP0R8MDA1C42W1Q94HNQZASW3061WR7C78V0	2020-03-26 19:27:05.384338+01	f	d44d7057-e248-4204-bb8e-4d9b0f434ac2	2	11
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
\\xb378eecaa2af3d60482c35dad80df06074d106d106c4a99c0bf17ff78a1c4932f6c61c244ccfc9bce512b86d2e1029b1d79d5f6fa165e29f200906e8a25a1e7b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0075376d6ad4bce8456a069e7bde945b7f9dd36d73480a147b55c2b06d18274dd666d2fcc28d94fcf6e8c401c26d462e2985a6714a59967886979c77f8ff6418	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05a962dc843c0ff39ee8e5fc3762a8c73db6be6e8777ea3eb8b5cb4e3423f7eae716dd7826800bc9778e004eeff63d38e3e3496475c5574a6978660bff8d677e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a947bbcb38b820a51840d9cc4f0ffae9a605d045f0661f391cb241120e2bf147dd7954aec09deb4e8b70ca0725a6fe0c6bfd486b8470773e0970d0293eb5b30	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b5d76d5af2cb092c8ff4b46d0d8e1d470bfdf010a456e290b5daf27633401624716c8cad6e767da252c78cf798c9e5bd5b71d34cf9d34788ec2efc8d38db026	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa901213e3003e1b9010fe14ecec385d940c1062eb55665cabd1b7ecb4bb221b5dc4a504edc0a98341564c526e65f765c0c0339a9c4cacc14047f921974c0bc3a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd29aaeecf5fbf380c2e8fdacd14b7a23933face6bd10f28dcc749b777a399a7860a598f17359fe51a33aff7c4c832ce87e88c2c589933b029929782c2bccfbab	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc56922dcda6e711bac6a7c8f3bd1539b2b5a7bfe9332832401e604ac2dd73a44da2209ab79bfa3113f3b37fbf7f5a01523e894f4fe18c1570544b4c83491eb2e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3755790ee6224cfff6c5db1d30eb3104b44998e1c3af8fbde9e24e8a11fb6ea6b48defbcf9d1503f8f7f58562ea5839e7133a054a6ac27794edb1a82aa9549e1	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a0033891df149843997e3a479c447991380cdc13b804333f3089f25d0025eb810b3488384acf97a43f0b56f234a799febb0933bf2fd4e8b89e4cb8927558cce	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71d2de23e29bafed8c56373de5e7b25855b9160a2539b3535d7a9643548f8040dfb496895221925236b764817108a9a4ebca9690de96b7b141b5bdd9e0b9c070	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2b3041ac316e2fa5656ed3035d55de12c428409518854086a1f9167d660e76ffe76a1762d7561011380582dadbca08304b398b0e7a8001c1d9b6d283690b7a1	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7cce87953b40814584186cf6d8a027decdeaf0abc91e3a79d5881b9706924e689e652005414c1ae373ab06482106a09ea6ae0a490a0ed665fc0f78cd38241292	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9558be38da8ff07c79fdc8a2d49e50ccc1ce8d2326e58fca362b8f28c46e140ddd0aa94d6db59a384f28ba935825949d565f0be8967fd2d052167d3efcf23df	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x26e839b7a0dbf7a50786189671b5f91235fe012177dded0a65073b946cd2012e0887c8d659191c8eb3ecd7ec4a9881bd1af4d0ce834c20bceba82ba222429d75	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93521fafe0753b9ac944df2b5088764539c41564d4c8659b5b64b05d1673526fb51035aa5cf4fcf3a70797435e205ad15b8b801d4822579c209828f91c34950c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x611216fe1f0d351925360b2e5f504e6ff857d7d90ab0731d7e121223eafac584c35e1f587980dbb950a83ef93f46e85da0b35973607a3bb417c4e9ba105643d8	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1cd5380661be05eee2aa2b9a7885eacb8c70fbadcb3a0f9f5f5190dfd699f8f3067fc8c9453b7037fe6de9bc84b76d3018e4e9bc8e535b36b736aeb6e5e15ca7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6a0f2c0e038bc72508e4024ebdf3b4ac6666a9494748149210a13e17cabd8b5c1386ea458ecd3a0af132791a7e4ef4919c86b2fed5791d03e12924c1089a5eb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa405466aa03b97274d8f093b0477c616a58532684a25de6153fd19affe58caa58d00768dc2c8b6ce514a80c4ed77e6d0385d9648039d39639d6631dec2766f4c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x064a5c17b5a90e46f58604436d34a2660cf06f383e4e3a449d10e98d726b231c399688bd1b216798091f0d1e2ce1325d84995eb04dc71ce5b1ea75c9f77847e4	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48ed78d94d51217716a001c9364ba73d6f418f1783455ae18815fe288b7f25494ad56b2cfebbee2005e57a6ecd2352ca0c8101628ef8072a5946b2cc0c93051e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x63dac59cab8c7778c124ce13ec041a319a198c583c42604bce00bfd294f8b65d8cd382dab81f1e19c0500da84c41847a8a3d2f6362662d748d83054e29ce83eb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x151533270a1b5cc2bc2257bf80b55700a8229aaee5153a7cbbfae69a60221a6dc9a0b6580fa57389a3e542d5e16070a7b1b1106b4b534d0a7007f500619f51b4	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ea4274729ad9eafc072e4ad474ef802fdaa1584341adfef43043e369187fd63796d6787a4025464ea07e428b2316c60b4116da2068e2af9a6749e63586b1809	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b4b20b04b041348520fe2c5c9a449d3ef883ebecaeb5a60f03971a911f51cf1e281c328785b0fb1ee28c521ea195969c259ff54532e2ab83c3feea5f8a5c4d2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2e06593f7acfc46946e23929994d69ed4316a2ea9eae0acbba7584224358d444fc2c8dc74a0174253362d976b647eea3353c678c0188901731cd35c037a5172	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5325201602106788cec43e0b1ca568904591b32a528a563ef959a5e97fab8a51618667ba28e18821976bb697a3adb1d814e33bdabd37db0c21640e63bbea9d4c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe27dc2dc8aca4fc4c55ed955fedde2c35f1f1835eaa8b5e8142fac5287516038c24deae42e9ab8602905c6919ac8fb9727822bdb2962c9506ce4ab37864f9ca1	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1264a2f5b5c378ee5837971f9e5a9a4338a47eaf72961bacb241e907cb891ae4766aab8369bab91b84b39b31c239a484a2febcce7b551d1da5c1f2e1b9980f15	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x454b79a65edad8b2091105870ac85fe522e9230e03a1f5b9049e5d03a2577146287ffa632df54ce33d361b920102af8203f2f2123133c6aa6809975e11226d2c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9dc566a04f9a3a41870aaed2a04663f4fe8fd5d7b494a41d73d5045fcf180bf97facb61e98fcc6eaf9b688af96fc4abf4a58b6b3d8b42b4ca311b8d8c02650b0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1e69176cc4061fb32a1385394e4ccee48d1549914129ccc18ed538f3a5c7c9fa2673b953c681cf3cb35b55740256937c3eaaa440cba6d7c8dd498acf50d9ef3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x770c748e581e8ed7edea219a09ecb0018a2015d5a8017f746511950f5da1c4ad1ded37a5f054bb1b0b8902cbd3767f9b0cf4e0a8e5a8f29bf555eb89dfe78fad	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x478fe9f5af3431c4d3eb0041181970ebfc4ef63e15f712f3f0882bf6ad45c14698ac62d1c58b687b3811de87e2a3f6bad2a04382e70b98e225680285fad80678	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd24ed264c3aed6dc5e0b038789f8b96c7a39e5afad1a6d1152e7522dce16cb07057c685ebb3ec13c4d813e7526934a0bedae3a3f69ff5ed67b17ce19c3900d07	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x423cb1aa741ab0a5237c1a1e96d8564a5cd1a4e1cc092690215c66d33c2ac3bc55d265997f49cb54405ba72c621465571b26dc781c6fc224ebdd418042540ffe	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd628b203825e5c1d6f06fc772be687e4b1236e8525660bebc08612c7d985f1f55c2d01e32f26a994ee775a5d425c1c02d8c75ecc00fc90ede6f83fea0a5e090d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xea07a69a2e207613ee0342ac42375a512a5de80c2de1fe45b8e02fc088afc54e57800714896492d7592f1760ce39a52b2e993f188ae22af2b581338541df9e6d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0e17ff4a5cbef557de82ff930b13011bd3f3ec7c9ae048146acacaccfabef30fd1dfe9c431391293ba9c6f2ef4fcc605d0c2f2b6037fe50d064e16ef46725fa	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaa603aecf389058bad8639cb59cc294c2e07810582bc742d9464b9b1ce1db3c34c6acd1d6ddc15b392e59ea35c1950134adc777d0d7f1f374783d4d671c250c9	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xea6820ab6c18df81c1e83382b22e376a1f0e32ca3cf44b698f2d045e0211d61b91ad2eb23223038fae7ead0ad8151569f7d4ab19d457342fb1092ddb8acb0448	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9031081bcbc575982c7ef830a3c295e8bf53ae135da5a0a36dd0a8798b9e80730f0dfafae43181eecdcd7f4b5f2e8d92461e9285d3344ede49e6b8f0abbdf990	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc9c8855f6bf389672a04ffa463cb17a978cd60de6fff056c4babe6e4714405789a117e83f7d16ac0994f12399a18821f02518ffc24b69dc54e1b449d727244af	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x34f12718d044564fb64907fd6da488af13745f71fa519a2241f2ad66173e328c25ab029acb0614d9f455517f2a5ea151b503ac40d765d8739e32611f938357fa	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd0b0025e5f0fe1b3b63b82dd8d3622f9bf597ca75ee456db436fb9b70feab75b2addf53d418da957197cb831cb9f24815f9260b13c58a21598b17164e99a6db9	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa201d1f554ed771eacff448c58b847a075cf2e26067dbfe4341ed0d7cac664ed923f67736459c56e2e35ea662eb9cf6b3cd72ef9de03b423513c1553a004eda6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8418bf8f77a622bf35ada66becc880478e3d21636e7bc67eb16583f06e384f6d36c54a5b3308723fbaf976bbbee491b89864db5849e0143c3f2ec32b8a4e7904	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf203968c6583ca909214cdfcedee187f3eeb9439ec533326304146787f4b7de96c14eef9d0e76741901125b166be7476143886790e6affdf8d3ce03090da6ba8	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec3dcd118571b36d0d66a591fc847e3e631b48714c8aba050eba1320212c084b99aed3ca443a8bc0962fa0022da729eb122a26a4fd49b398d57c948346390d3c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb2533b2ef6147c934a80bb385287ddd0a56db64abcb50e017c9cf292727ef48b9fd71e2ca5a655b1260c8d07bb89612c76faaba2a882c9fc32f06f813c688704	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5c42d74048f0f95be8cbdd401f5c52404c1c841218797be83c623b592355b3dc5c8345e16c1057e02052555bf341fb79236a27a189f90b9f6fd01b0e5480ae2c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfa4c794cd00de8256058a2f2fe0db828dce524248d2948659c9dd954baa2664d82a291a2ec9d29a0402822a6039723ae60b35d40ad23098ff35f1501eee05d2e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc2c67403edabb6712ffd28584485f924ed8bfa9bbe8fc92e79c0fe06e29a0ea908894601bc67f483414ceab1c0e2014ad072fa9d50d039a4f15996b0cf7bd322	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1265c56f0ff9d983edf4116e74381bf08002d13b16450395bedf89b768c41509cbb84cea3c37383ede857bd2e7822db7201b0bb8009937fbee558087cc5606c0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x48e61492b0edb65f7f30404ed9bbd1df09e6d6b02946663480b56b99dd6501f0d8c3cf1f4836a67d8040af93029ad73ce05015235c07c26b3347a24c813f8994	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe41e7a792cce6eb2fadc32efbfa1668b09e6835b4dd36573fddf1169b738adb48abb9f265bfa4442f58690d8b88cdcf553ee57356f1bde96c98aaadd0004b45b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x932ff95ddb379cb1b5b4d30c2306072cb558a845ff69e396de62d8ccb9deeda2ed96a7c1e624f9aab477289533cf07b4642a3bdc06f5410cc3aab2f8b8aa00fe	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa892380640102dbfdb06bf698d3985c890ef7879b885a999a5021a5c2631217592861d5cf27705f7035ec16e1b284dc5d1add6a5e5ea4192358ccf6951b9fbf6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc4b2f765266e0c216ca5a0ee39d9f3268d4bf529c808b890a4a3355a1f7a9e962df89c835dd3ccddfb20879281aad895833d9292fd7b4394a3c8d0f0b1552d69	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xae96c3dda1bc040dd9f30f16d9118e16237a56decc1badf5e918805f3959dbcdcc206190ce9a81aa06be999899c187f86a112a76c5331eb8635537a0d1597a37	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe9652c2e421600735f4b580ff9d71ea40ebbe54606411e484decec3b61abf37d7a921d9320a69f1806652b4c7e9c0f5d7e5c4154015f7ca2fbee3214f8d0f875	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x177a0deae7b9263287cd88fea9dff0667fefadced9558b7374215c0abd40b7f50bc2fb6c488f198b0efe8dfbf96ccc3273ccdae095e7909f4764717531cf1e04	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe9da8f472d16740cea65dab706ef151172a45ce8c48b92196b712277d12c9ad43089503c7bc2e2c98daa64d20969fc082f924c6b19eaec3e8e4aed1f9df273ff	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x83bb4ce6e18f7da1119c219e29fa91ab9d22de9a1612154b7e1c5841f88264310025d0928586feb554229f902a105e3bb6636f20e6c42f7e41529a78594d5e00	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf2435f6d2b47158c77f3c7057fdc9bb41c30b2937f84c5c6b6cdd3ddfae22bf88b1e5f86dae495349f2bea4a43914e82dac390c23553d5d1b256d01136aece17	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb2b398d560e595d6d879842cd209cc84c924a57538ffe918aa6f3107492495740d2dadd63f34109c3a19caa665eabb781359cac5c496e56a36bfc6926d3a45a8	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22104ae3f0d6f6e6579cb6c7e00f4ce253150e2fecb6610d64f5a0643b628c38f6bf26565b91221a9d53b2af71be535bbde0ab3ef0266302668b4683708dc28c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76697f4126c154b222b4c8e3f87e1c4aebd70a13aa1b73817e97bac1a03af9f8f6eb6008e0fb5fd0a9c8d147f96e3a6d48abe0f322969a8435081ddfbc8c56d7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83a1afd9a1b99a4d7824bb878db71db8b8718daab4429c879f55edda6c7050ed8efd60ef95b84af213dbdbbbe283bb84fb32817a8bd2476de1d563a7ae3940f7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb08a0f5ed1b5859b7fdf907c5cfa6439e79f21ef48dfbf5c93b7e7ba10262c0652e5b4ea64dca448eda615d06b851d85773a6a4d94e2fa210c7dc9e6730f222f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabfb9c9fcaec888f4c41cc0caa0697e857c7438ffd5b44ad31c6a03706e9f507e47b84042a40b40bbfce9ac3086337f1f93a3dd6c73b81b5dbe6b8008d0b195d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7b3a005ecef0e48d0c0c27e41ca25f45bfbb4fb379544bc7294645a82afd617380b61409830ebfca9f4b88937ea01cfbac87ebd7dd4c00923d53a899782d5a0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x736e42a1f4bb9a49045220bf4024995bcd982acfc61e23f515ac426f922fa9b29d757095b891a0e25b8e225c227046d744a00bb26172d14e0f1a1fb0d00f9daf	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3765433d6e727f0b51d6b2e10c9bc10a8e6beca70e57904bd130ca6d72c72015f6e31ee9e66706fe978576b4e0e6d2f956f775cfada9d1a419cdfad6aec15d9	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77f3cda2f035ae31416334c127cc558f2fe9ac11a828693d2dd58369cc372bc9529bb59abaeaa9330f681aff4e954af7f71f4af57c61a2a1d0edccf64808d072	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x68b9a7b30a6319213df3410e1ba3f51707435d5cbf0a6edcc56c8954a5756d61f1e600be8a4f39fe6424e184995c1dda8515fe26ba5e448a8b833e827bf7a831	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1df3e99efd724a6c0dc0a2823ac9166edbcf1bd7a6cb0413866babc471686c59097c77538a86207890150aedd4185f4510e6818e4c750746101540e32b715b05	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f05d950f1890fccb8485c90bb3dd12593a54a28214db64eb38cb8717b68adc26156f8487ae3559c289047fd628688ac6f5631282c4e5c388842291bb46f3824	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2260b2f3dccab0bcb338cc2882486ec3d820dd90bce313c98fa1a585373c12258ec5e6b03cbb1a3ad3a9f05e37e93f84f101b917a0dcacc56b0556e35fd4370	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9940f65d34ead9955365a9a662346df1df231f59b35d11647f1dc539978c123984f76b40d72c82c8959eaa4a4c43718d1a9dde9cd1b355f4516373c1d71ca80d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaafbd0f00ba4171f53f308074294c05c4a89d70c82bfb22e3bf301d5a612d70492a75d0d7f06a2bce5375d826bcebc537faae1c904f51e84c8fe02de79b9f1ea	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f7e3c4dfad9eab80fdaadf26b544e5dd077a53bec8d16299774b0414b2968f699fd109f5890c286774d40adcc2c0058282dd91c1044e95a14fb0952a68f92cf	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x657bd65e4f96a0f101b424398e3027c407b429c748304835b2785e8a102cc0dc7eb0b64a4b4cd334114ce8b8d15ca7a54144fd93438b842da690e2e16fc00a0f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabf5ac2d1d162a67e34eb3c18495ef0f10cf1fe91ac95034ae74573a4917a8e3fac9df84bf7627fedbf6635a3ee9b63c2dac558272f4f33692ba7553f2460b23	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb18c75b760c19d74eaf60640c27cdca32e617e79fa375af367253fd5d82de0ffcb2cac275e10fa34414c7e487c022e1cc8cc0a4ff1b6aea6699044db55a2d6e8	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8f4067b6df97c0f776882147e3050ee7fe6515d36bb3543f64d86a421ffc829e6223d7574140a69dbcaf1d9c2adfac04c20eaee5f9fda7647e3ade21fc89d58	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59cdf5b4960217fb40fb89197ff524d7d07d85ea9e8a86ff2df1de83168834b6718e40d0311781d494418d60d4da3c2c74993e658f4810fe29c921c79e70abea	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0cd102d8a79598cadba8953351ca90d4e0fc6dfd400c28a8dc5a13a40d22baa877ebaa8b1f5783d37f7ce24a4da699a11299ce7d0243177969c7478e9ab0e9c3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55132d223a1cc81ed6d1520e1479781932eae0786a8d966204533d8ac2acf6bda3bfc29f4e2c638e58e1403dff7a755e90cc82fc87ea19b7230c7fe8d29f07f2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd712b1d48df298318617323fcadd4932df3972f52d8a0f715e185ab1b35138265e752ea28a2391aa65717e0cf99f18167c397266b3daa7142675dc12920f26a0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x64b9bb4270e35f24aa1ff42fa24e37f091d6897743ef2a33b45de3a901cfa1358fe1c8b0b5c8976a77e2cbd70b3fcf1656658ceec5498c64c2f3e441232d6bf6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xea0a144ba2b13f631d017472caf6126fa74a406b15ef655d21a0afb990d73af47295af21864089594cddb95b929c3e7d573e1fca7b46cdaf0d5a947638b4e21e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98a8e152432ccca7f72f9e1ce4161822df6b989dae89f1fb84f81ea01b97d8badd8d9cda5fbde90fa28f048eee5f72525e793edbd1172867f1d3b45d2d12b5eb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc56873a3aaa4f1c03b07956ba80407614f95cef4a964080dbff67850fde6e45b51ef838e1fd118d6a2220fc6fa7d66581a33663cb77417b240b3ec5e5dd379bd	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9600561209bfd7c43d2342a93f5f2a33b249d1edec0d8494e93731fef49c9111bb03a10ceb809566187fd3664ce6ee38eacb489e8537a74759c99d137082e57f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x546e71f08f7965f19aed709f2e1d446d175caa3665353a26587032dc1a20d09d7fba8244bfe5257c9701b0a5325f658945b4e45a3f8a396b40c8710fdd5141de	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa59076edbc3104a91b98a27be3f166e733b3f412041c0594b27927f28a3e9ce8ccf495d341627a0372dcca6ab90d22743d7a9c5b47ce4c1240c49f0a870390fb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb58657fba4f2bd0434188927b298e64b3d6a850c8cee9d6361dbcf1551a4fee9476036aca0b125dae93b76b4f18c4a1714e122c994d0d894bb5399ee88c99fb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x133ec98fa5d8efee9e3db8305dbf2710c92fead62b0e5498cd3b6327a08bcda6829d723b7030edfaefd254544ee98919cb79ae488d288f0b44e2398b47543cf1	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x596dd70417dea3f96b72decf73ebbee411295403914758bcc5d562d1232ad6aa8b14857b58e1cf9ae9b1535ffe4fbdeb4e9b6d67f0739173b64d9bfab00c1f0c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5557667cab72b0e107bcf82f6afca038342e4dc9a1c9ad16e03dc7f8b087ef861fdfaf39c755ca5f63323740dd13edbbb844a72769442659736031ab8dc9f825	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x117efb8a2696ee71b862baf5718e5e897aa7b454c0b71731a8c51e174d6f47f0fb5f2b3e863b62242ab49a94f4a8c3b6adcc4c33e1f4f8eba0d0f2ab121a136d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ba1aedd039e8a27c23c673551ec9036efeed66998fb3371591db8ffd4a3782ef69b6a62969744c9c2052c40cb4600a8a1adc5bf731d0a4f76bb882fb7f20882	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf67f29265d2ff217d3b10a405f10948095527a1130bd9940b449ef76bb911c4fccb4b2e3d16d7e032f91a5eb71ab1d4a67df4430f69707ac71b5d39b30659f3b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4e8ce661c04af3c5b33513911ecbfa3d939740d19c73e1a988633398cb0ed4cdf038c42bfa3ee51b1161ac21004c42eabe557d045ee33453c9c9bfeebeaaf4ff	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x86902375dc166eb59ad208aa55a5f6b1fd98e00820ae55c82dff32b9cb24691432b12e6fe3132e2175d8de54a95ac4057aa709eb31772a40bdb66aabb1b2d66f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc98410a63b5283e3fd3746f4f1d40429e185eb675a490aea0355d459d8148cdf07414dd52086902b048bb38c41d9f2e062d66c8a5215cb78c1638bfae90e2eb4	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa11b8c9834c5f253ac0d6e7887de20cbb41f0085b2f7e35b50ff8795c062865534f17b131199845cfb025335933aec53a25c93956bc52362bcdaa51d33a88d99	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x50740bd39f5bccab5f3d5d5d0450a3af3d5100e061a2fa8101a843704511e51d9f3049b060e68a5fca43e954a553d64ac575418cfe28380793db72e7a85d5459	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8f913b6171b665b34523910b161f296d7ad1f04a20291a81c295c2929b4cf8c08ffdbef97042e263d93b82ee12002caaab69d2692c15fed75a271075182a242	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x143ca07a3017510fed894746142d6072e1d36266c75ebde7f9ced543ab224acb252e02ebd9900eddee6f804f9991c44eb6740605ede5aa81c7d19239301dc03a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2e0a60b017910b147f18237c9e69a9a88f541d22426c3260589c010cdb9213a264353c43d507d17a0f7574672ce0d4d3404172c3864702a9be351bbd46542803	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x68cd82c929fec87a096fbfc4f6da596342ed86a6f8e90862f8e459a14d26849f811f28e9898c566c90748360190632a00539bb9b1dbc12dced2726034c60870f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x20d3f42ca922c4f58ed26eec2f86c77495d9b48d4f0c04f5f1ec99d1f4fb98839cec4b6edced97bc8fa7f12276e6b9736df2b41fe94d27e314fc2587acf393d7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5985c9aa64ca1f29c6faf3bc713c948138f2e595572337241e16c4b324ce9e10e02742c1250e5ae1e4bcbe6bc00b765e40afeb698d3fa61350bb3e8841de11a5	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b33d18ffbbe7ee1aa0ef7644d28c80e1e2359a47ccf8b158c6bd04bfc8dd29ce52f7426bb3a788d6e37d52a840425f4dd7bc5c865745078577202c64f52fc9e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf1adc9150816414eb4f52128618355d9d5bd91ca8912d63f8e7a64ca34b1d7da69d32601866906589eea7d188782eaf246d333dc6e2bd19bf69a9a7b7483fa78	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0fa5cfdb816c6138bc62a113cef662541dd8c523b05b31c54d5f81367d0a31377688115e683d966ad0210b0f48a8105dcb0bf5fd46ff219be378e551db102923	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x703b416c294aac9b4090aa92c3a1f109334704fc40cbde0a34554e5bc9f4211eabd39733a6cf4cb0f262ae18df506cb9dcba4ecb4b4e0cc1a8ca561b3583e313	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3d873e455e18af938d24cf662c6bf37a9af858ebe4bf47a11c96dbff473465c7ed15177b14b7838aac4903c6855adedbc8a66815f0544c86f371a89ee41c0ac	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb099cc5eef6d7321f18012f657a17df19416c8a618dea525df502a1ee6fae657a50256c78e6075e9377d3a0e02ab38fde36ed232b2af9ac77ca6930e81de17e0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x61855979e9803991bb836485fd0888797888dd56e9e8f07ecbba3ce0669373256f44c6815c66c9bd71975571790a8dbb2be8a79b614c1a07c417f48ac0cb5bb9	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ca5c33be6ea670eda1354da45efdc57b6c8399f6b1e610654d57237e9b294fa7c15f036ea43ce335307848dc0603b9b5c706f597649013d212bdb0313bea037	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc583157b04cac89a2bfe8a2320f9e01ce123d8604aa4f133bd9cca72a725947707c383ffd6662b88bb5d1267e4aab6b4cacf41a29fce49dec4f34d97a8ddcef0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08e39ccae406332695a9cfc04d20d3f733d1eda5ffb1d1771477aa6e2bce440ea646f5f3829a43129ac991a0323c6dc6a2717fa72683c338cd330824ee9bc0e1	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4333acaa5662f939afd4a38290ac2a39bde7ebd680fee28a047815e6c94c9c54291587af56c9be0e8bf0b96edd09cfa3cc57425e88b333649755ee53b4403c6a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x774aeed719dcbb168d5257834a6419777a8e339a6979d9a93dde3385d76a97c2a5a0478e8ad0ac57164e27c9b5c8bc7eae65f9e6bb9fcd3022dcc03d53f5c885	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x05e02d74bbbf5f3b4192e9fb55c67f37a439da3ff07d6e849fa6d7b7d70a103338a7b61699e253a3a556388a7ec81fe48addb0ca7fba9230e79edae128c0e12e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85fa8e533d7f8ccb17c8f7992ff8ac2d993eb781003655bbf38455c5ccee44768244f6d87020ab1ef14041d89610f318a7f2cf6a912d97ef97cd29c742d1acb1	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc85238fd83db5be800a69bcf2d6d4bddc01df075760a83ac9face592fd257ce738d91159bcd66825ce1d661e99d4bc5e2858ec01771c9c2d911d9afff9ff721b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xca0a05f0d9d31709f15a0c19f114dde9103e16907cf42d72232d7d528f4d86f8ce3d05d502ba062889b3807f7326df6ec5c75823bb10bdaaa49765ca59dadd7d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe0726684567b8f6e972ae98a1c743d83344292e41f48d2696272bbe7d7cf28e4fe4ca576cefee21dcf4d05dc1927dbed383bd6383af4f6919c6185cb86c29fc2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e3fff3c1f92845ba0dcf1651b7ec20c0da933572c2ce961c0b7944ee4ee3fa13562d8fe5d799f8eb8e528cb431033634fe73318ccec18db2246ad6bafa0c762	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf47266abe3cb33716f3b864e07b033f66af6c7be58a6364c28d6c507b7ff70acf649b9a7396cffbdf77bb5bd7af9196c5299191dedd5c9a6ff04073be2ddb945	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85ac0b83d4e7d7d59d97c69057d729e8eff4493677e7ca61c55593b87f647fd7fda8d5b2712848a1d4df31ff2f27f60815078aa5f2e59e9db57ea625cbb65bd0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1f9600cf0bdf811771933679fd1dde21429a0c73f961960af88cd8d1d53a5ffdfaaf5f31cc5f7b28846298ef0a84de0f3abf8e9389814bcb913e21c630ee3cc5	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6fb5795135c3e9dda4c1f9726330f5c2133c1f10d75784c9acf91e2f5c480a50bcb7c3af863a2ce41df9aa20ec99eb6f9ca328ba3ce70718d4bbde98467f9077	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c85da610e0f8ff8ecf6aa169d4a5546125f86d16cf6540852ed508585e62f80521248f909a5d10202e4721be516f6443f0343b4cd77062193f0ecff1fa688c2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x362cfb8a2e90e503a2c6737a72410fea45baf4811c9326fb67b11210c79646b209c45c30b0d36c8858e10bb0ba574fecbe6cca19539b23abc5e2e5c32ad721f6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe5c9a96e3c86cbecd1dbb3115134af53d6eabae04febb9b16bbed023f88d6595b31c96d76614ea1d9fa6cd41d33b69e01a81c8e72189eaceeefea14fcc85ae9b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e387402e2c0ed7310ba9fc821fc8bfeb97c7cdc1c745f5bfb9b101c8aefff575aaceaddde7a4a73d913da0fd3cb3b713355d1e1d9b5591f0cee4960ee49f082	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x506bcf4cd7e2d1d680bbefae1f3081a1fbe16d06e053cade3eaddeeeee4aca1cd2da1937e23ac1f02d4198ae01e0fc5262da41b38b30d5c1425e52c48f3d8670	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ec5d99117b5d08d9877621063cb351bbf1a75981c0848e9ee3bfb5d2f33d2d657cf5dbf3829e504137e00dc7f10c5d47adb48262c1bcecb09af9e6e836a21e2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x866eed1ec1a323f1bfdcce39d5713711c6c875025dd58d4104aba4274ce9091a55b2c3e25076bd2ccf911a8cc25227c9d4070087d187701554167d7c37192da2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3af6b7ba5e61e2bb741deb79693b575f4929b12acaeb6842134067c0640ec26da7ae11f88e37fcbd3bded0347147b7d1689f4deba2f9e60507fa9568b24c1d7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd93143bed0c88b7620b4eaa41df90750dc6bd54e7401820e063bedf7061c89dbda2336011360f70888a4934f2c7c3fa03ded0e959eadc46ab90faa62e0faf562	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x30d2aed6b932d5ecbbfd6af28463c1ecfe7c178d93c78c3a77fbb50ba939c3623fe83d61d8a980b7ef992f976d4700cca5b8a9dbfe69d097639bbdd1dc3e0bcd	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3668654fb8f1a3f4f03716ef07f5c99c3ef78f881e2cf2eed90bc0b30375d7590b405dac4afe600f79f3e4ae46c99316aeb1bcc35b6690159bd2105e6c2c0c6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ad08082cfe946f44c267270fc18ae6ed8415e069a6b5a4d2f74e0aa916f3c444488d3576c1d2cf9b32b8cd2448ef0bf15b5c38bc09266c689a3142c87b2565e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd2db79a4569f54a04a721054dddaee82002e56fae734096a1fbd7d0d5c45d42f0a48b0073caef24e484bae22e987e488bfdf6216175c11a0a6700b6ea484b1f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x06967749c6890b49eeea509129a0a5da20afcf1d521bfb132bec60505a35d0e3ef9f37db07be5fec157ed39c0358ef8611e76517b3af3ad5bd9a4b6c7186713c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa30eade17313fb80b1a774cd5879408f565ba6681952314812dcb9401df2f7704d9e6318c1dd11d19cb766df6fd6c8d7a5737f84c4bd4013fa5166ad3d15f01e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x684f3ed9abd9e696f61267a93b9e3f990e29980838ae3a17fca5db3c1d8c81a1dfb3e35b16412824526161110d047c57e066b317715d2b1ca73a21d8cbcd2fa7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6e5ec95f36ae8c7402634ac623b8f58ff26f998c35abbfaea1342dee90f34fe84e05df9219690e911cc50ce16a8aa11eb7f15cceb6f22dbb17c15783e0c5be5c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x165dbaf0c1bdd9d42be3722c488e5079a24091fd7dad07a5beade4c9603cb0682dc3708da84b3b095ca6863ec51f16804b2b297b8dbf31041ce56155ddb2b2cc	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x74deb3f1abe0d0f7faedfb22fd0fa7c7496742a1aa2ccfd64086373df84639f8c6f87a976cda46f35df449c8bce076355d62870b7bf17f2f6907d900b59e1dee	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdbd34e536724be18061fb45c8f2e479ee586d5ae2ad2145096f4d25fbcbf97168d5a94d5740351a76f107eb40db7337999b7bc0114ad2d00c8b0eb5d61f1a723	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed4ea51f74204cb8177ea6b80ff8801222f54153397cbc190f39d3c72a264a451fb4043bbce6ca5691f8407c5c17fbf9c96ba8f729bf139a0f0277e6fa89860a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x816f803af6a7e11f0aa487de940ae8a0a30e402721dae1e10d34213e1b0cf99d694d2840b2d2b832f77e1d2feca9df281847905e5301cfa180bd1461309fe4cc	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa5e1ffe58f26df4a9dd211988634517c07d854be23f66e5e77986e65fac688abd0333036b05baa09a72f13b57b4b872e19c7258b3355357e389833f71ea071f0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3f0cb2a60e00b839aa07b37fa79e6ff7a287c13fd0b958a5328c3719a1bc26b5edea0238c48bd8cee41bc04b2816e26ced58bf0014e1d59212a82d58a1fdda97	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x92ab7592772b2b881f7e70ae12e5ee8398b76bc0ef94e4c737b7dfcf9854f4f18cf2115345c0d24a30bcd717c27be8d5b140dc015da8862894b241761e253922	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd1061fe76cbaae0d04ab65e940c76e6bc9b82f09010caf40556b9672aa71a021dc89670edf00f86c32729d330fb09092a0a75f039db49601364b9a5b2379510b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd136ffb55575c4ff5be64442bb108b83cec060c9bab8a5432e9762f0e32121bf3696990a13291206f08deb193356fda4cde77ebca556adf77099ba42ad4b03d3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfac60747f6f5230990e394d61524d5e5c2d7fde9d64cb67971383afded993d28b8ccc24859da6595521f2131f8b29f7249a132b21bd783ddc17df6743baa690f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf1c014942d7a667381cc079933a31eee8c9ecba69f1d05957757ff2735a71c20ec47253af465621395e5c5c08b0677345119eaa1d49309afbec7fbb27c85185	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9de8cce48ed3e96948d3b3afaa80ce3b88300019c9bc6f2448a82a9902ab58fb624caad443502b31a5b346881d74d3a52548fafdebe59134015a4af878d25f1e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5829756a33e2512e0c52cde712e9c737c4bd5efec68356606c9fca2163cb40262163ea08a65ac6a76a145397423299aa076a8f1f8e9957b8963409f85fdfb230	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe282452214a9d34232b6c24f6eccf2a97893d2ad9741e9e0b4c874a5c5fc2544446e0b43c0bda9211bbdce61a4762bcf9db641b46ec67ed8f71f3b0ff398d5a9	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x88337537317cc8b51018fb4c4548bbedcbbf28c0c2eec201d8352f9110d08e80d3e1449a0008f62e5f44a27efdaf5ffa99c34abfb0279e2cb7fb8e9e9c091ed3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3a5a7bbe7f8eec2371c769e6143d6ee1d449ca7cafaf1851bb96f4c9d2084d3231e74ae18fda9616a031199cb712737f01af2880510224d1e4119c26edadf105	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2fd6f2fa3d765fa976d488bc81e267be30795510570e980048c76145fbfdf4bf79b6858d1745000c0cd72149a80720225d9483bdd81e2e5e4434e7eec5ba7b0e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6e873350425cf51f7564bc5fbef921e7c9bf830c9d35f00d3f762b55aa504608e1dfc017499a3ac8abaa201cf072e6e3c9d3bada76e4e9378844aa1bceb461cf	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7c9fbc4197c48b8a6bee1360043ca58353cb3e40890fd78a6f04ab69cce9c00a88d572841d49943c2d7fc525c7f9fa3a413ff3d8a26a73e6dd226d0bc3b3b4d0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9068b60510081087c9d4acc4a906fdd20dfe5ea8ea54e817433fad3ee25ea35e086ca5a7983097b0243f41583020699d491123a721bc45daa490b176f7c62b2a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x17e4a9d8daa2ca64826813cde9733f5949d9a30c88260c7d5933c6ea811a27b9f5c4732774466ff8d1f9b0b5d9ec439827e2f795119baf9164b7c7d139fd5ea7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8fd23473f33b66e7336bce01e3b938f95b31f63f874edb521d5c9ff57969d5d78596f84b5a0447bfeccfd07f6b98710cdcb9306c62ee34ff53be01d0c7e678e4	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x69a2095992f3cddfd5f273c5c8fa9cacb924c58e1b5132c79c8001eb47e3e04fc812189675eafbe68b76579bb21fd056c4974502cedb1a7216c1ee7c42fe1f76	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3cf8a9a58ac03112f46a64c298a8150dad26d383fb12702ed4e225a8525da5b6ae26e4439d2b09a3635654c8599916d35142ceaeb5b9ef7094c8e918dd2acce6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf8d36ed24a9593576c0fbe1fca1c45e91bbd440adf76f1e7589793d5cdc1f797084cf42f28d1b949b63ea04f107edbc98ae27a35bb3e635181f6ff7b74946b34	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1cef4b14c92d23143dc22bc8bff1c7637ae220ad5af5ec7b8fc5b289b592dc536381653840495238ad17efd80e3d067806ec02c93ee7d353fefeb90386312dd0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6f15242144bfcddaaa200d7e799d514c320cadd2f149143656ef18425774ab340f174dfd87dafc87e4d15fc78dacb1afebe374b21a10208da099a650bae5eed6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4cb3097f1c37488a5f59c8e175f6989c8a2f5d8dae61a92105c1e46c19da6d64d0d952aad31cdfa0f5e24c90ffca6bfa9402466d6718f6e46adb408f734058a3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x440183e206d698c7a2730d1e5f71b32707963b9d6f117764657f3a615727f29ff7f69b2ea777fa55cda06b11777ffb77c6c73aa20968f9ffaa2f0c82d8128635	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8d14780f3f5baf8bb404d9d55185b8d151d1c3c5fa4236f6e5f2d0a6ad41a024eea070561434393d5d75e466795b99304a6455a81f3f220ce70486306b9b6f2a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4b4d8458b842b658affb89f20635a3cf34036637fac52e83774af8c363c5c99986e74ecdc301dfd17cd87bd5893fcb3a8fd83a27867b7f5f269df497d5cdc821	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdf88cefbbb63463e09ce6355c7295f42bd686c851d63965ba8d1a41bb30bbf8bb2471a4e72fa61262b5870221fd78d3771c10e13da1c7745e2a2871e15cec100	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x776aed60373a03618957c5a94ee0ffe060aac91f810030e1b21334fd489aba75d3ac5a29f3f64e8d9b6a767c095be327fa8dce9af14687196edd62348e59a620	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3defc51b1c9b98abb0983b2210d8af346725a940769536fe9d279b372486cf803b031f378cfd45aba481f283b6d30b5f73297d5dc1793ca877168db2b9645b6a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x017334ba5b590f808e52213a51501905e57e6c4dc50bb4c34d07e039d8a29de77ace1725d4c2403ccb86256d48759f5df7de1127b6f0ffd369252370f7eeb511	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x681520926447893b8d3557ecc1ebdba90eb23336ab721e93b954a42bf12a5f6cef5b67dc3d5a345d2ef96a1ed838a13d0512686f6ceba52ddd7c064a3b5a14f0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x25dc433ebaa4d91f9a7180e25f7d119c831ad9c1dbb1b8bdc05d03d3084ed4122ff6aada834a9c5dd3b5b1cec41946a1088e29278aa382819fad83ab188d82d8	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf630ded5f31fe2d4fc0b4209710fa38388c7e4d285d43592db68cd78623d1ae4be3f5e159bf7e01fb6baddb92981b96779c72ce4bac828b68e8a46f4853785a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4cb9299a278deb0617c68dffc002d8f5c7ea71b3601f456f8aa09b50835380e4a91ae1814b6ff460e490a077338039ec2adc15d93992c0668c05206375510f2c	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x276a6185aae025ddbd40ddca7cdcb5e11d9aba1465db83997cbb198ee3aa65976d11bb4d40f8b5eddb305117b4f88b090a5d66918761aee9e87a10024d490edb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb3be6818a39d860eac2ec503286ee89697f668dd4fceaac27ef9f372affe273e03a76a961f96c3cf03d8acede33afec84a8c899a557bada8b16dc5616295885d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf80f1f2994576496bc3d150c08404c7dadee844f5b220c0eb780f5d369f0d2481e2852c7dddb112f29c64832a5559e42d6c5c171ad96a5733a98da12a2200b44	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x98e9f02ee744cc60bb24bdf368c4b1a01e70b6d327c38380cd6a306d5451b79802d7b11a2859ffa86bc9e86f80ce67a8fb8aae6adcd0274739822cf2167b961a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x993df19db1d9858d347a101b12278024a0034c70b2ab7a2b40bc87ee5c15e933ce1d952bae328b5a428c8bf39924481466c9ddb42fcccc8592324c8760961366	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xda270368811829cb9103c1bb50c9d144bf3b263a2ef7902558d4d806de58be3df7598b6efc7287a0ebf7e340eacb69992d32e5316ef63b144df2b866796cd934	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x47c01b601fcf1fb694b873ffcbbf6f29a967a62a4d8bb117224dea0059d89a75336a58a71a14a0c8e08474116ede3af09278f75027f5017ec8678de2b3a9fd79	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa457bc1d426fd999113e12ebd82b6acad05856052cf84127b956680b59059c63408d45d054a4fc141bbe75194eb377247180ec7ca46d9c85b9f3380ed5642fe9	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ee49acb2433bce380f39d5d35079c17ad446c51a4515a91ff51fb8c15946eb4999a0bc6c08c44633ec509dd43f9b10eb7cd0435475e9bd0674593b1ae8882cb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a4572e2e1307d787c2df87ae424f11c29a04a6bd56d170b92ad51f7d93c0b1558749b5c8503e6afcd7f26fc0bb76ac8691b96af396e549897f55f9f84f75668	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x165970869cbac37765df1a5b6668996ff985a1dce898d2e6e3001c99dd4ef50c625178de459f8978eedb762159d74910ce1d406d51568f8c36b698645b99adb7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c2e6b6de36b5556a9dd88073a174a22f8c45d82dadf45e12a77080fe78271f59704bff1a27f81c9e4e534036d312d799b12b00f7417fe3e4b5b42fc394d9246	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d093bbbbf8d09bdcdece049e41693c3313fe3d7e1c3fab2cbe7468117eb61bf170a805be83c55b5b00a5c39e454dc685916e899ca6d119c115178ac7fbbeda7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x937c18af83d1e5b4ae777dfeed5569f6425de3a3cd1934ab2b07e2ee9daac5728187fa5489e207d93cc315f70657392f6dc7b81908e1ac37a94d5fc550a877bf	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22a6087b38521a417e96a8649be7ca5086fadad0d399a6128a3eed9f2ef076016a9ea677c9aeec7b6587372a787707dd934b505b7f9b50c13e6a9c004751d3ec	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5793eb71e2e610b279666cdc1ee3fdfbb9d4765573aba7d2d02edd2c9b973818e1a38e3ee42e3062cae853c36fe660f9e1378e3c003c142f7ff3d31304489bf4	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x721093e6f159bc5d74dedc00e1a964d2fe6c98085b7c7afabe821346249072332aa642b7d33841ca47dcfeb1c292f1892026b6cf4fd150319eab171f97e944a4	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x158276bfcc7388cd491511f8f8fdbabc4ef8c5e011341d8f3ffe90e8f37a3ead99551ab339ca8c650a783510c95cad58897e5e99e2f7ebca59fcb85a00908e50	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f8f6e2464a0ab5b3dad30b55a8a0593decdf5359ef995d07ff4f1b6fd3551ea359f93ecdc95b83e1a31273bab6adde46fdf585495c6e9e06a4cc593287f8c9f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c0ac65cf450c8c0ea758a0ff1637d435641bcf74c114a12c11524d4f0ad0da3faf3e0f4a886edb51706372e6e072e69177163313e32d3691f14a4c26c6f4641	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2252c33242e3d31c7d4a176255ead7a2f8573762f4b6d6e07d8784d9879a2655d4acab02ec6d6192861b09318c4fa7de31f00bf15cd460842d550237c3218118	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x54df5ed833117a0da8ce07e7192f07c67dd9578ac400dab173c89520f82b004752f1a6527e55a0661e089755482670844b9eef747a40bc712938e786a2437885	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xff6212eda23c185b56b845937dde409a7fb307679c44f72510e81fd91959cc13987838f9dd0cc76641935bb67622d41256de15f241ae9c4ce86e38d70da572ea	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x88cf6a75f50811a39837a8e04d11b08325f7d8ec24d47942088ce54d66794196574c40ccaa2df8aca347e49f06523d9720583a8ce6f73d4f8ef8ab5fc57d3d3b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3fbf102070aa2a1ed19a0a779d2a23f4f094712bd5822a5d38ebb5cd341dd3931c30e3f4ea01d99092c833ba23e8c79b651aca0dd1b8c41d5f7670533cb78ca7	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3c00b46ea754f23cd3b5d41377fe7142d4146e13594e70d67a541b14a5a1f55e3a4619113c1593cd82bd32dfa74f7e2e27bbc4be449181d31b606c67c8ff591	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc322cd92118aabd445aec705cfc7e90a52fa11c86163eaa97e22ccda4839717679d0b3348b778dfc4a98f5274a1adb343d4cec43df97243a89b812abf4a4940e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c3c6d57a0664d5da30c8394375fd8ae8d06e27455e41afc4198cbf509abfdfc86ee823d070715e58fbded3acf3830c5e323a01b28fb629e3e728ceb77e2f13b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbdeb7ac98af9c80c621707ba229659bbc0c9849a35efe1a32ab0b88943b736280c3f92fcef449337260c5e71f6c5bee5098c2a53a71b62c5d4ebe659db962ba8	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0b1afac5368d72b7251a133e13e4c3f271e0570361837d614ebcc0110045056eb78c5569ec668cc07a99d641e9dee321be1b621c03ed276f4870d79b227629a	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe0571c189ffa9598bd2b10daca0b41915b79d2af0d182686b4489578fa21be8fff2682722dd4843d3db53627a7ad82923e893a341c8f1d3a81606a42c0fbf03	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa0d996a0157b9c4008fd1daf1d8fbd0749d520f31b913357f2bbbe1100ec7d2307226a46573037a9c03cd36f85d5ff9aa9cd52d1a95b3637205befdebcaf93ba	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xed9964b3619fdd935bfc8df972bb2506f28f19cb821c1262bd62b3ff4338710b07e629bc0fda9b6e35233d770831386fc7b3ccc41316f4ae63164c7843e78c06	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f4b88691c86a171acb6c468816bcd93d0ad44e027412758b6980d0225407db0fb4f2475c5266ba59be99d262248708c8ab1aabf5857c09d1c076ce6f84598a3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0e15259d45b92cb3220d56402b7cecdde2e0c7b35ac8c8fb35bac63491ed0087c7d878333802f9f46f17e663cc5e6a75571527114651b854ca920dc09d9d456d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf449fc3fb518f2f296fee1686d745967d03c457efc5c843ec7d18603aa0975b7295b28afc80c03a27359abacd0b8707d9fc2017c4c4ab91a128481b82bcd4d42	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3bacefcce0349291c705d69b39cba778aa0701d0bb2747d3010479c031f6f407e3be7bffe675b6076e7cb84ddd42da866073233515581cc8beb594980927f883	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1587665210000000	1588270010000000	1650737210000000	1682273210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfd2ad49aab62ebae12f33fe6de7ccf47884d467965b906937194b5fc4bff011da194010a26d10aa3fe51d376fa91f6b24e4a874b9641b755ec78ff6330f913b2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb3e1d98bb8bad7430a19bb95c9a1f5b1d6b34fe2f5193ea95f069cfd78944aee3e2c0fca478cbd5583010d630d1273adfb563f615eab1187bac00bac7d26deb3	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1588874210000000	1589479010000000	1651946210000000	1683482210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8e58bc9aa845a8dcb4c93507273ab06f388df9d187a25e6982e2f15a5dd2778c6ea2616a95c4fc8fd01dc76bc667441e9f3db3c58ffe569a9f9634214c379f22	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1589478710000000	1590083510000000	1652550710000000	1684086710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3c635b2a8a0891f12f3279c0d9e6549c677d1b4616e5233a54fdc9bce4a6224a90f01058553f7744093a19478bd71590f74ba95211aa91ce0806e58175a0756e	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590083210000000	1590688010000000	1653155210000000	1684691210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc4765bcd9146d2e30f25dad9b3586eccfde80776971bf4126de8abd2c0f48192809a30a41349904bce93bd8a25d2966549b451b732fe049c77e4da8d82e4b600	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1590687710000000	1591292510000000	1653759710000000	1685295710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbe125ef28ac75b00c11aa8118ca94a84929c6a4216bd6c8ff349b607c83e543b770b0ee24b580141a50ec997a2b73860f43658e1eeaf273b42e7fa2771dab223	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591292210000000	1591897010000000	1654364210000000	1685900210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa477048519c7f8e54e792da8e2616e4c744c71e897f479c73b13409e7f9130f7d9e3f58c7798cca753a1ca799951c5f713f6d389dd0973c2eacf758a0ed7690d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1591896710000000	1592501510000000	1654968710000000	1686504710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf65f27fdd6ec270b95757c171a4961b3234b6ddc7f42cdd259741ec405383b12500b5645fc1f74311478277624b3ba16362dadb6bafbd629f7c89c2db86d6b10	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1592501210000000	1593106010000000	1655573210000000	1687109210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x381a76a33cbee8583d1e275d77ff8b4a233cc47f0d87ce76e4ab34fb13cd61b64f0c589be2c9f24cf1988fce64cadf29ebd1d4755445f7d6bee70a0ac2ee3d2d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593105710000000	1593710510000000	1656177710000000	1687713710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xab99a6befa6052eadfb7f61f9d4b3b701c2624cc3f384df41f1a31d51385f991137819b981721c0209a2fece0bb555e805f6ea2681d3d153e0aaaf66f461a092	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1593710210000000	1594315010000000	1656782210000000	1688318210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x352c018bbc511a492262cf5e101aff1d079b4ee563303e06a4f77581976509fad09f88a568c7a75eb521020b30bf1ad39ad07624dca02595bee20049073e6fb6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594314710000000	1594919510000000	1657386710000000	1688922710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfff1c04f3e24640dbc9b8041f758eaf9f7ce0dcdf3259974e7fc85e2fa8a6905b55a495e567c70289aae9cd9043f30a03ea06608fd34afadb0aa08ec26f4edee	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1594919210000000	1595524010000000	1657991210000000	1689527210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x104974b598dda349ecced03038b53eb9528dee10014385d4d33b02b9a2c953682a05a32a120fb7ce97a5e97af9df3f9102db5cd835e63d8c2a656d1046039a82	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1595523710000000	1596128510000000	1658595710000000	1690131710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa010b38180f0b7a0c061f7c5bb68d1da3d520d80eff59180f622ffda9bc51f9d2de29a3d75b91932cb1bbd32cd333f4ee8d82255810c91e0ae11400ae84e0378	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596128210000000	1596733010000000	1659200210000000	1690736210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xee0eb3d3eb3906db27a82f41ddc494383f6b613ca5b56e4396b83d04e7c565237f71ce98b3c5581a39f9e47eeb731dc74828e70930528b0d0a09fb1f71869c30	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1596732710000000	1597337510000000	1659804710000000	1691340710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb72e604db5657b8d528f16d2b4a7fccc12b0b97cc43dd749e9f5d1cb78f7a65776af046ee2646592353ac41b6517a0ec64b37ea7cb3456d763854a1b16eadd2d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597337210000000	1597942010000000	1660409210000000	1691945210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x568c9a5170ffd7ce7ef2eb2f2c294cfd54df443730b6d7d100297e980e7958a13aece3da0a50809810964d26aa0a1c805ec71598888120f22e22b90cd8f962ee	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1597941710000000	1598546510000000	1661013710000000	1692549710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x456a9de9e94e34ed44892ecffdd98a2c13cf14ea322745456c8e3ddcbc42591474514933a8017d01018834096b3e1f09dd22b24f0c6fd554cea781ce2c849f8d	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1598546210000000	1599151010000000	1661618210000000	1693154210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc236898146d3077793082f98e9a6f88c1897482bc4be742a09cad99b85f28f87eb17da75230273a31ab8be3719568c9a1e4c4aa3e78309873127e1db3adb00e0	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599150710000000	1599755510000000	1662222710000000	1693758710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x81c218ca0a206bd839b2ade8018b88f7c1983900f1a26bf4c89807b10def2e4a53c0245034a6c34e7335d853ec1a4344baf9324711ee52ba9d5925314891defb	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1599755210000000	1600360010000000	1662827210000000	1694363210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x44e130ec640e8492c999d1bb9522ff27606a2ca8f5264a22415c661d0f00ac70989193722ea7fb332e495ca48a36446ad22be424406ee78f60b9d20b089283e2	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600359710000000	1600964510000000	1663431710000000	1694967710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x214da53a649cf2b3ff4255ebb59fb7e7b0412a419b21df0989d0d6af0ef540aac8338e691b31d550ca59c2c8d4d60f12434c034b982d38fe77ead94665e9178f	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1600964210000000	1601569010000000	1664036210000000	1695572210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3341ff9efe2047bb74b842827056a58d87d46e3e4cbd3fefe1086a1ac55c9fa63795536626654ee22cbd62181fa9fecc1055a91473d1a419705e03cae7174fde	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1601568710000000	1602173510000000	1664640710000000	1696176710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbc17dc5cabe2dc94e9e7f4ebc48cd3b405debd95214d558c866f9b25e4a20bf01877a1e173d9a71a59e8d19424de6ea41cfe992adfde1995c6bc9850eb707d39	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602173210000000	1602778010000000	1665245210000000	1696781210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7294a2c2aed5224625bf2261ae05ef0945c5c2e39e68382ce7f282d8906681545a74b4967ea0608143adb52f5e51bdbc928ca81aa42a20a25f4c7890152d4f3b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1602777710000000	1603382510000000	1665849710000000	1697385710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe6e9928e69600ff897cfc930a9025ed83ae7c222f210748982f78e530ab2ae21d620b5ef5baaf150e92981a95bce2b95d21936828a77a6b4bc0f693ad26294b6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603382210000000	1603987010000000	1666454210000000	1697990210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfa402d97d8baf09dbf27b6f466e24a272e55a0b525d2201fa61cd2f45c6bda0eac110c05ac97ef914e12a2a5ad5be6181474035982bb7e646c93318443f7524b	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1603986710000000	1604591510000000	1667058710000000	1698594710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x995df75df0a3cda873baea40ad4b18aed83d13f2685d6e94f125681c613430baa1565ec480ffa3a812c08569e93fb9b733fd84beac6ae7abe53819621052c0c6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1604591210000000	1605196010000000	1667663210000000	1699199210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf83190c4582e1152cd1d1cc323b2b0bce4603dac971c160babf3389cf5e585796e4c3973db82924be749ba9655471d73653774df3963cc86535f423fd628ce48	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585851710000000	1586456510000000	1648923710000000	1680459710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1585247210000000	1587666410000000	1648319210000000	\\x946e8b5af562e6bdae3f9e9f1996162e81eb835d52f6b1455194d1c8a4afde69	\\x099f81f628dcb585af0d033f33aa03c6070e0d929b3aae82bf8d0496ae1134c9302bda7ba2325470039e1845b7a72b1adccdbe0a0703f89ebeeb2b5876dee503
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	http://localhost:8081/
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
1	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Bank				f	t	2020-03-26 19:27:02.111305+01
2	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Exchange				f	t	2020-03-26 19:27:02.185388+01
3	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tor				f	t	2020-03-26 19:27:02.253714+01
4	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	GNUnet				f	t	2020-03-26 19:27:02.319708+01
5	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Taler				f	t	2020-03-26 19:27:02.385619+01
6	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	FSF				f	t	2020-03-26 19:27:02.452093+01
7	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Tutorial				f	t	2020-03-26 19:27:02.517685+01
8	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	Survey				f	t	2020-03-26 19:27:02.583952+01
9	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	42				f	t	2020-03-26 19:27:03.007416+01
10	pbkdf2_sha256$180000$RBYjEO0WzE1z$x2Avt35TkOL2pMHvts3B1U1NIJalXZf95WnJhGFOAUs=	\N	f	43				f	t	2020-03-26 19:27:03.433778+01
11	pbkdf2_sha256$180000$8p8hsOkotA0i$JXXYtj800s5rl0nyU9HCVuMB6ergdsZIVhaN5Qnx2LI=	\N	f	testuser-JjVD1AYx				f	t	2020-03-26 19:27:05.200825+01
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
1	\\xe0726684567b8f6e972ae98a1c743d83344292e41f48d2696272bbe7d7cf28e4fe4ca576cefee21dcf4d05dc1927dbed383bd6383af4f6919c6185cb86c29fc2	\\x22960d2314f1582a329648f60b9cf4260a030e824b1250bc5579971282746a0aa8d148b988945bedf94a4f3ffb566926e399f7073d2355e578d7e71472140d0f
2	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x21fcac8b4ab4a51300d5a1315655d0ef8cce440fbf4518bc4ef759e4da6fe8f3bd725739ac7d77455dc3b006f66cfdda86567063b187708b588489408c5eda03
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xb08a0f5ed1b5859b7fdf907c5cfa6439e79f21ef48dfbf5c93b7e7ba10262c0652e5b4ea64dca448eda615d06b851d85773a6a4d94e2fa210c7dc9e6730f222f	\\x00800003f634a8b280d60e393fc134a026a9e75c73da984ee8b37d6f97126316c21a35030145c82a573dc4c2c8a1aaaeb4190a9ead8c3b5e7324f1f2aa4a4128460c41c63aecfba3a2345ae4fa0ad575077937b99c2fc3db16f3ff57ba26b5509bce6861f7223e18de56e76069a0fef1af8035997118cea476eaad9b8617fb1454af3a21010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x6dec5a22a2f272fcb4578979501441eab3fb2f8e56a714f961006a6f202d84818b99a712220c5f0c0c3f903bf6d33061b30629e71671d0e919bde07fc6c38306	1587665210000000	1588270010000000	1650737210000000	1682273210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22104ae3f0d6f6e6579cb6c7e00f4ce253150e2fecb6610d64f5a0643b628c38f6bf26565b91221a9d53b2af71be535bbde0ab3ef0266302668b4683708dc28c	\\x00800003d55ade68ee8e9736f077580c578526fda98ceeb09b45fda0ea51caac39833bdb2a18b515ae5e651b2cae56f6d52036119b31fd0dee64cc9fdf41187628016eb46db60fee0297c81effe636f910e3c6475afb86990374be80a89ddc305974c7c72b8055b9cdc965b2efc0a2c8fab26d70aea32585fdb75670084011f1128d630f010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x09610beb2ef510eba77251f7f64a731d27911b45a2b34a81e1d82e9d9f0da9c2a4ce305b4ca3b9cb9e96e5b88e64d6aa136bcc45eb9a41b1db595cc86b4b5f02	1585851710000000	1586456510000000	1648923710000000	1680459710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83a1afd9a1b99a4d7824bb878db71db8b8718daab4429c879f55edda6c7050ed8efd60ef95b84af213dbdbbbe283bb84fb32817a8bd2476de1d563a7ae3940f7	\\x00800003b28058f5eaa720fb59f2af6159888da4879499ee69315b44294a0f286991a9939757cb48209c78f920ebfe3087af83b6123e44249a16e8e82917f63097ea43306937e8ad94c577541d8e5da649bf5176418f130fef96baf66e093d367b80f04cf5d78c08dfc9c17789bb3515281466daed6f7af3093ae1fefba33c3aed5f7151010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xab3fe5dfd1db939ee85243c93249912b8648aacb0ed0908f962387e57b833574f501d6698cc6cdc5f449ac54b598c2dfc25becd2be85bfecb1c1ca33b12d2b0e	1587060710000000	1587665510000000	1650132710000000	1681668710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2b398d560e595d6d879842cd209cc84c924a57538ffe918aa6f3107492495740d2dadd63f34109c3a19caa665eabb781359cac5c496e56a36bfc6926d3a45a8	\\x00800003ccf8f6e955ec8dbd5e1fafdbd4c2a5c63d6357c58171c5ce23cec69db797dc7d5d1e634d5cea7484cc2be8ef4615db3f9d0d8ff2769f3f06ded82447c3f4eea765131b0af9d9acae660876f2ab540ad8c1fcebb713f75da2ea03ce49c0c74667771ec592a90d263aa67b3771ec78312614b9998b597c84c7f155d94dc17ba6fb010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xae5361bdb70271fe0370497ebfb224e8a7eccc9a8e6fa6624bd7d31bd1e41f68388b461a04af37d5029372b60b75dbb12a3048acad0e683aad76e725e982790c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76697f4126c154b222b4c8e3f87e1c4aebd70a13aa1b73817e97bac1a03af9f8f6eb6008e0fb5fd0a9c8d147f96e3a6d48abe0f322969a8435081ddfbc8c56d7	\\x00800003c005baafd68b9a18061a96d08a1f93c22924052134f0a5494208fb1d411886db3e0ecb074ae90bfffc03cf2b2232dd97116220e176379a5a72e8f80e57083e336a15611a673cbeafc0bd938a765a46b41524f29b5c7e736a7dbc2ff01ed34dc3764435fe9ab7a64f839d3346e6930f36081444990c8c44805dadfdb19b79478f010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x9c201cd873b697ee78b1cb5d617dbac0cd8f5b670b74c0e7975648ad0c6c8ff5527024165220e9158fc88021192913ab4a699c6b7ec3436c57ea31a67c4f480e	1586456210000000	1587061010000000	1649528210000000	1681064210000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5b5d76d5af2cb092c8ff4b46d0d8e1d470bfdf010a456e290b5daf27633401624716c8cad6e767da252c78cf798c9e5bd5b71d34cf9d34788ec2efc8d38db026	\\x00800003ad0b99c6fff794279491456c65ef1115fb9d8dfea6b45f82b4971926815cab2264de5dc5a200289c2ad0212f6d7b595833284a423add333c599f8d92ce818a6eedd2df2557883249446258d516af67f711aced066bd0a9afbc5899ac54b0ea901936b9b05243ec73e6cd4e1275563395f3706565590adc115d28ad0ec84ebff7010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x05bc742ac859e4d65f78b4d2757d79a3e3e1f60fd03b3cac8dd5833f28bc96e950d39a264a322ae3c5a86a9755f9bf7a0b809e1a228a6f8d37e5bea745f54e0a	1587665210000000	1588270010000000	1650737210000000	1682273210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0075376d6ad4bce8456a069e7bde945b7f9dd36d73480a147b55c2b06d18274dd666d2fcc28d94fcf6e8c401c26d462e2985a6714a59967886979c77f8ff6418	\\x00800003a9e811c8ec80e58b61eb62f02d23473c1a778a7faeb417a8140fb988d39a04dd5c1bdc031a0013e68d9fe7fb734da2e51f25c950e069c16d8f743c314b7035bfd12cd1dbc0243749fa6ca6ffed65674d1124277e54f48dfddb22ce3556352192eeaa41336b225f6416cfdf30e9a234d74d509bfa6604fb37626691e733325bc3010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x911d59d6e060e1acd0b857a95b089939b99411bb8a73918cd52515ff8f6e511ab12b52b51d68fec5ccf96106695644c97d7bd131808e0ad2e3c33d2375c2e205	1585851710000000	1586456510000000	1648923710000000	1680459710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a947bbcb38b820a51840d9cc4f0ffae9a605d045f0661f391cb241120e2bf147dd7954aec09deb4e8b70ca0725a6fe0c6bfd486b8470773e0970d0293eb5b30	\\x00800003aceef5e810ff509df46bb7578317fe5bf1a03e15954addc71e0e89b8043882b7ffa46e4dcf8d841527e90bd55e3b53175d6f849a8c211b49bcbf839e3315a820d56d8bf914c091dafa986b03d45974825feb252f8b18cf00119964b535cfcd03983a8a106995455ea0f3747f04673b600b6a00a7417f21538a240bc589f5d053010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x9556a823266bd931524199b26db0e0fa5113646f71b8870e12692bcad8f041d869abba16fd585fdd24d935aef5e2395444367f5f1a0c6658da67227b505d5901	1587060710000000	1587665510000000	1650132710000000	1681668710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb378eecaa2af3d60482c35dad80df06074d106d106c4a99c0bf17ff78a1c4932f6c61c244ccfc9bce512b86d2e1029b1d79d5f6fa165e29f200906e8a25a1e7b	\\x00800003dde42ff25bd4087a637db2c939985b8c32e96ab4a2e56c23d1e0b9d882c7e15def40d30d84363ffe2bbdfbd91dfb174305e772e6aed1dae9955c2580033219d64cbbf69a209c6fe7a71923fa1b349a9fe0b484c76a790da03d8ede39900a120bd4f3a60a755c16ec216f7f0d4e5cead106c197ae01c2a93379c55fe8911b2347010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xa79b383231e346ab1ba67f613471eda9b8e5732f346b8a43dc2ab1fff6f1abdd85aac75cd96eed57fb39e7d22433d3e906979ba92ecfd2673558e0e854916402	1585247210000000	1585852010000000	1648319210000000	1679855210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05a962dc843c0ff39ee8e5fc3762a8c73db6be6e8777ea3eb8b5cb4e3423f7eae716dd7826800bc9778e004eeff63d38e3e3496475c5574a6978660bff8d677e	\\x00800003ea5907be696e6a24713e2a8960145d74e8e787ec45cdf9e425a2fb2723125176c6540d36a64663f8a8a49239043d6a8e4f0cb1d7bcc240661eaeb961f9c2c4d292b724702e0c1da78d602b89e962d9cf4a9f7bc0124957d22fc29a900fcd6679bc9d752191a65b9f81a3393c662dae0f3a5cde312bbbdac6b5aff830decdc883010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x2a507230a1e3189c341c27e63cb2605aa835b69559e3e7ef2ff75c57531b1cfe8e65477022f6fc76d37749d4a6a031970575df387ad909dc5ffd5d2ab58e6d01	1586456210000000	1587061010000000	1649528210000000	1681064210000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f9600cf0bdf811771933679fd1dde21429a0c73f961960af88cd8d1d53a5ffdfaaf5f31cc5f7b28846298ef0a84de0f3abf8e9389814bcb913e21c630ee3cc5	\\x00800003cd35fbfe22e73bcb6dae7d7cb25fc6afe7628b1a3a1c2508ceb19b90cc8a6eb7c60ceece972bddb680500a030c29e4578b2bcc3e7000c992ec02811bda634d311d840a72b4735ba94534464b162b94092c192d535391678854c3245594d39ec21ffd5ca9ac2afc864a834b86e5f494004064817fc172c459ae6548eb3c1ce26b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x40730d9738e4d8a4db917f9aae1e47e8df9b1e3d86208e228f9228b7e2a6b4dcbc0c7c42ea245d36e9d353635f54ae340a8f18886b483de3453d17d92b76db02	1587665210000000	1588270010000000	1650737210000000	1682273210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e3fff3c1f92845ba0dcf1651b7ec20c0da933572c2ce961c0b7944ee4ee3fa13562d8fe5d799f8eb8e528cb431033634fe73318ccec18db2246ad6bafa0c762	\\x00800003d92a694f24b843c35b266d64e8255b7d42ba05b344cf172d1e5801009cc1307a6c11454e985e3d107de7c10e44fd5129ff91b6cf6183f09bea1098de73eafdc4640b4bd8f1ba96b01fa4ccc417446e9c05d13b046e6be8fe3b8e1a8f5a5e99ed97fd3aa54e169360b504cc34e670c248b3a2ed6c9ba3e9c30bdff95cf08f0a29010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xc70623f832c4c919187efce808a53ffb5911f70caee101391e572b17499e0d015767186d6683265df2b80b999c99d9e674a1edd472c0082d830d81061368fc02	1585851710000000	1586456510000000	1648923710000000	1680459710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85ac0b83d4e7d7d59d97c69057d729e8eff4493677e7ca61c55593b87f647fd7fda8d5b2712848a1d4df31ff2f27f60815078aa5f2e59e9db57ea625cbb65bd0	\\x00800003ce500a6d6a3c11ee23d22c03268a0a13606922c59678dea760e235a48c590681fe7794c4d1e63777a1bef2fe7fdb78eeaaaa2396f704df79e6dc21fd3ae140465d7879a2288acbd6f337b964455cea44ae3aaf5955331a742996e772d0b77917cc22b13282729d3f90781587d31da76bf86cf9c8431e1f11ebbe69ebbedd1edd010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xb65706df00d2a8c2ed70f527d5fb29b18d74ec8daf13e32bcfd22404626ea03c6a8df0787d114abcbd95f21925a25137a30081fe2f02d2cf4e0cadfae97ec809	1587060710000000	1587665510000000	1650132710000000	1681668710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe0726684567b8f6e972ae98a1c743d83344292e41f48d2696272bbe7d7cf28e4fe4ca576cefee21dcf4d05dc1927dbed383bd6383af4f6919c6185cb86c29fc2	\\x00800003b0551bf050ee616e0a65669e3aa367e66d0bd6fc8d0c188d31a5179bc6f3ef6a584cedefb23babef8688b0b07a4333203d440375ad0f02199a93b17cb42ca6c52def85dcf6b6a796ef98eb84a051fa05be4ff0646cc21f9cc8619576f3599afda20313b3adff21dfeaf689712d3764f83172c8b5b0291b18ffda239af0a9a163010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x6a38bc0801b022a2701425f901af2f7dcf9d880d155b8ef55f92f9d15e7d02c7558ebbd539e71ad69332f823643fd9d8275edaa3ef147b4cdfe570e861879c0f	1585247210000000	1585852010000000	1648319210000000	1679855210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf47266abe3cb33716f3b864e07b033f66af6c7be58a6364c28d6c507b7ff70acf649b9a7396cffbdf77bb5bd7af9196c5299191dedd5c9a6ff04073be2ddb945	\\x00800003c9c044e7e249e21c0f484f4d08b192186bd0d2f9d0e4ef9ca8c5d61f324c053a095a27700d204435cdeddced1dd0f8644669b46d8e9b79e2af304f42351a0eb094b0f93f6ef102cd0807806d4d3d8f7cb2b69ec866a3f133199b2acd51aa6c219bab92a8a3a37d833499ff9a7eba5d8ba28928702410b9d6620c59a4611ed187010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x74ab80aba48699935bd3fa517ec2c42cbc65a4a0d364d4331919852717e48fefbf4c4b4eb6ced68a57b718274c5e7c172db5899bcc97ab6052a9899011c3b508	1586456210000000	1587061010000000	1649528210000000	1681064210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ba1aedd039e8a27c23c673551ec9036efeed66998fb3371591db8ffd4a3782ef69b6a62969744c9c2052c40cb4600a8a1adc5bf731d0a4f76bb882fb7f20882	\\x00800003b98754c02d0e499276a63d9173c48466d7a97f253b8c129dcbeb6b3b6f41362bcbf90448da2722a6fe8655016d434030d6cc7e67617bbff116ddbd4e4e412ab56333aed2f0e014a160c9eec0009f84ba6c09d606e25bf74413fa825e62c37878df606c306c0b41ddecdf854550cb5d5fb236768bb60f16f97f16aaf4b50cdf7d010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x24d467b321192e02030a75cd59439083bcf671e0fd687770d930f4089e1c0f7ba5fd049f7f210064aa96b4bc43b0307e36052a1f56e0fd61f06a5d9531ebf80b	1587665210000000	1588270010000000	1650737210000000	1682273210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x596dd70417dea3f96b72decf73ebbee411295403914758bcc5d562d1232ad6aa8b14857b58e1cf9ae9b1535ffe4fbdeb4e9b6d67f0739173b64d9bfab00c1f0c	\\x00800003b0e1c04b9976d6eba81ea37b67007c594a9d7a843f4437e81e26e671e66234e9e7c044d3aafb293cdaeb4a62fa3c9286c4bacac8a5925a1fae8aa84cf911deb8de017893b2317210d7f8b9f13ee8441d922413e54f429dfb3f3c778fd27e6e497a3707bd763349aaab51df7ecfd7ad26d30456d5715958a0f3535e4d38d4a30b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xe314ee9e945c658a1c06fdf23f42d2ca888890044d9567b4dbfe8071c03165a55025279518e85a9edc312e19ec705fbd0cfe20036fde957bd9d3339b90ca1403	1585851710000000	1586456510000000	1648923710000000	1680459710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x117efb8a2696ee71b862baf5718e5e897aa7b454c0b71731a8c51e174d6f47f0fb5f2b3e863b62242ab49a94f4a8c3b6adcc4c33e1f4f8eba0d0f2ab121a136d	\\x00800003aa84ecfda79a2e2ee06163dc14c700f1ef089493f905b39c95b555acc265c68738b0a956f241e41b786fcf8e5a4e44a2a95bad2458ba257454e45274421cc58c88ce300d0619f05b845b6c9f8f3d691159469e5e0f44a21978582d2bc53e800b7b216ab4fea54fa8b3ec2a46c01a635725a763c4eac46dffc02a597699cf8ac5010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x2f5631d9c0da79467142728da1d62d7f70f80463670baf7ae6db47316933f2d0e70dc308c906c453eefe46a07a1b81aab2ef5b2a7a06c3340f350a16a639a003	1587060710000000	1587665510000000	1650132710000000	1681668710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x133ec98fa5d8efee9e3db8305dbf2710c92fead62b0e5498cd3b6327a08bcda6829d723b7030edfaefd254544ee98919cb79ae488d288f0b44e2398b47543cf1	\\x00800003d12b2e46adcb4b64c396b334010401f805bc1f5448d23a854aedbac29ee346cc069eecd774a7d66467f85133533e7ae7d284c091bc499d012867e7b9826991e1d9dd5c9faad98011e342f5192ec64775c1dc93b2b2b5b40b7cdaa450085574b5e682687c9b77866211b8aee01b4ee5bf5f287ada53c9ece7e32e5b1dd34afe15010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x553880a4746a6d8373cfa9ba68be5f9efc0025535abe290eb6741f6df2033f227e6c98858d625ea96b99a859019bd78721ede3066600a3d185bf0a576e85c806	1585247210000000	1585852010000000	1648319210000000	1679855210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5557667cab72b0e107bcf82f6afca038342e4dc9a1c9ad16e03dc7f8b087ef861fdfaf39c755ca5f63323740dd13edbbb844a72769442659736031ab8dc9f825	\\x00800003edd5526b05915fc86cea4943435410a19f281c1d89a54df84792032e495147511eaf43a84f86a95570f922653a238f97b042d757f0cdc9e969cfc0a075099308880a6dde598eb3a8ed09e8ecf64edcffc0fbf3f0641ed1429a45624e77ceff7aa1d30ec6efd671a55059bcaff6f44a168ed13fd35a74d251975bd4dbb66547a3010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xf36a4245dee05faf5d753ea994002f71f4edceb7a926c600a9eada90b3f2cb132046400340dbde9b4109800a2d52b3d317dacff34fcd1236edad29117ae8aa05	1586456210000000	1587061010000000	1649528210000000	1681064210000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe282452214a9d34232b6c24f6eccf2a97893d2ad9741e9e0b4c874a5c5fc2544446e0b43c0bda9211bbdce61a4762bcf9db641b46ec67ed8f71f3b0ff398d5a9	\\x00800003cb8272ab137e8957e6b27a69532b8e418d4bae8ff05d5ff728a426577b606d63afc82c2062498dff4957aafde398a7834e5f0e2368598ce52efa69fc9f5dd6d35390b476d803880f4908dd953f98d22949c41694d8c2d3e37e2c229f2246b50ce62b50fe32088f5885fef1028a5aef7dfb307f86625b6eb2dbd145d32bbb9947010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x7c5d50c01a587fa52d1e9ba4eab515b8c1ee794f48e7064d0aa40bddcb9aca9e2c7d05ca25dd2c43bf7873777bebe476e7bfeb01bb1628a8013a996449af1b00	1587665210000000	1588270010000000	1650737210000000	1682273210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf1c014942d7a667381cc079933a31eee8c9ecba69f1d05957757ff2735a71c20ec47253af465621395e5c5c08b0677345119eaa1d49309afbec7fbb27c85185	\\x00800003b1bf3b11f7ccc2ff27f974eac3d706d7acfb5449ab83b8d8e9041c6ceef4e255bb779d1221160f4f5cac7e386f8e76acf607dc6bc25171800ed692fd6ab86e4ca021ee55ce71d982970293ff74d5bda9c57914e77bee22bf2f29bcc0655467dd6c28faaf4b10986a20318fd46807b81250713eb65ed39c8d5e8ab3581efbe2cb010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x8b7616206d7866b7c8055bdee7adb397b1f536e4346d4c786221af738a727891ec1916096ffd6559fee2dfb7e96a5e1d97d682255a19ecad12ba0c29334bc709	1585851710000000	1586456510000000	1648923710000000	1680459710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5829756a33e2512e0c52cde712e9c737c4bd5efec68356606c9fca2163cb40262163ea08a65ac6a76a145397423299aa076a8f1f8e9957b8963409f85fdfb230	\\x00800003990f6be03aa254d61bd3a440c5b36314cd6a094b146a52be5db6cc09c3be4c96377c37b3c63e16d2a680ff720969af10986d4ba1744b3006354202d10918c8268788457bc447b9bd82ee1e296acc0799167ace2b11138abfbec7bd492fb55bc9b768d64bb0b70fb63b19f287c29ba2c48b5ea25ce20fcb38948c17a6463265f1010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x761e40863d9488915d4589a676bcedd05cafb75b904e38f23d5004f3fdd3f672d803aa11b84533817cfeb70650a536a1f8ed747991d8e1cb1274a022b57f2e0b	1587060710000000	1587665510000000	1650132710000000	1681668710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfac60747f6f5230990e394d61524d5e5c2d7fde9d64cb67971383afded993d28b8ccc24859da6595521f2131f8b29f7249a132b21bd783ddc17df6743baa690f	\\x00800003cef2c01704641dc599c84d724e2a23281e41c0b3e169d762e75cbd349c57b21648fee483f3d4f3a835c844b1abe496d92c8b812ffeada1bd501efd5937e6c1e2fb062565d0941fd91d57aab14bafb9b3e472dcafa3008db23a90a6bc371e8314adc1e48ebfd9be4eb090381421bb596b2f9a590feae44abdc7e9d822ed71e791010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x741daa2061da8db0a94be2a9997ab33b9c9b0f0f3de363972987609df8b6a8be20d9303fe9d6cd8c2a77cba01acbcceb66233c386cfd767da624e757dfc9e701	1585247210000000	1585852010000000	1648319210000000	1679855210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9de8cce48ed3e96948d3b3afaa80ce3b88300019c9bc6f2448a82a9902ab58fb624caad443502b31a5b346881d74d3a52548fafdebe59134015a4af878d25f1e	\\x00800003b94088d823d110517028c323cf8eb01011e1242c875323bfca0e1894e19053b015bc801b61366bd90a52d60a36c0387a07cc5cc66e2bcad30756a89e6f416a5a628ade9e3d395e045eafbba08f546028e93e40605bcc08fc0973923b2d81641d9acba5cdf22271a8e0fea3d55a60fd007f4bed17623d85a81aae53e3f06ff4bf010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x9a5d96fb19223c52e8943644d114e0941cf67ddb44f9a467271e7ee81021a842b75c4cb3c449ca82fa87b2495760e7b55adaa2fb285bd0632a5a620c9c3a2102	1586456210000000	1587061010000000	1649528210000000	1681064210000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3bacefcce0349291c705d69b39cba778aa0701d0bb2747d3010479c031f6f407e3be7bffe675b6076e7cb84ddd42da866073233515581cc8beb594980927f883	\\x008000039efdb7a58afbbbdfc3af3aa76fd48254eff1f8597ed1b147ce649f423de47858b6b5f07f6e59d1137bc5a0131e9514468c3237ec10f9b67f481c7136a067f95c52c24620c888c2cf6b9d08a0b7ccdf0d9f70e646cfc2ff46d7724d28135600036ed9bb37e78a924f6db1cb6d0779fd56a352f8faf756502b484c1a2b1f27c1af010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xff2eb53c691bf844fc736777e5a81c4d9eee0d9d9c4d9bf6e1549c86365a42847fda7dbc0b810bc69d3b1b1d3b89945603e39a9d80a003852bfc23be2b2e2205	1587665210000000	1588270010000000	1650737210000000	1682273210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\x00800003cd5947b0a750cf42de888eeb4dddf5546075f3ad6e010b1802cfc7141018616b01417cd60c4bac659de6ad3e93227de6377109f4a62c8c6c2cf3cc158c6a6fa8664154f84221732e11a0b44ead391f4a062356f824713f0e57024bd9e93f602f3d7d96a25232dcfc993ffa4820264b49b21746ab6b9ce8d38bdeeb69d540a961010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x68ad49dae3dc521076bb9130713d88974ecab0ce7ca5e5eaa38c6c171396d2c03d28ae1d369ae0de7baf6b30ef622fc72078b99067d9638deeed131cf7e6bf03	1585851710000000	1586456510000000	1648923710000000	1680459710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf449fc3fb518f2f296fee1686d745967d03c457efc5c843ec7d18603aa0975b7295b28afc80c03a27359abacd0b8707d9fc2017c4c4ab91a128481b82bcd4d42	\\x00800003c65e7547192fde53f1d3d862a15fe8290497f5cfc6a6bf695346c6a0959fbcf01df3afc8eedd2df6555a65e60f0e34e94cfbbda6c58ccc5928f9f35b230c38fee2ccf9dcd0977182197511ab21d7502703a9432fd3ae9089c583d0d503b2a6a071074980f69a922f6a52d38dd24374c98ce95861e753c49fa87de7a0c88dcca9010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xbcbb51a027659295deae26797987edaedb378a3d50f01299065d28d1172a1b781f13733d467458da47dc115d0c789e11e51f156c2167487a30cbfadfa97a530c	1587060710000000	1587665510000000	1650132710000000	1681668710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x00800003ceb8ec579cd089e157fe5155f3d0ffb70db073940f8a163c1a51441a44cff4eecfed0ed60c886107592cbdaafab3ae817182766a6402dd7d6f95aafa3b65b8cbc2fe81ad57d6d2924fbe3c6581f70250ef4ecdab91f43b588e14ef9091a8bd72a61d95e76606b3840beb7794fb92462ef1cae154a2cae67b30525f7bb0a61231010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x7ebdcc5dc79759b6638910ea1e4e979fdf95f360b23b42d7619685eea3025c05144c30c126c6cf064584d844b55ce7ff7fb77b9f55f731277bd44e1d0c751005	1585247210000000	1585852010000000	1648319210000000	1679855210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0e15259d45b92cb3220d56402b7cecdde2e0c7b35ac8c8fb35bac63491ed0087c7d878333802f9f46f17e663cc5e6a75571527114651b854ca920dc09d9d456d	\\x00800003c1e2c9c05b49085c35ac878ec97e53ea09cbfbe8c06c1e069bd477389dffc4ff73f6ba8c3ddd279a161b598d8d599c7e93778d45f89405aa457d77fd912e4ec2793783bd28117fc3c89d9dad1520dd46d58a5ab3ccf73b1bd6cad83cdb08e5992071e356555465f4fccd29a0465f150e18562ab78da1a7e26d288870f12032d5010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xe7fbd1cb37ce89fac2be18b79fcdd893e9706151ee21ce310b95b519c87aa28d0dcf0f996db8004b18f839e0042e4b40d89ff4817ba3e5b7af1cea7465a9010c	1586456210000000	1587061010000000	1649528210000000	1681064210000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xda270368811829cb9103c1bb50c9d144bf3b263a2ef7902558d4d806de58be3df7598b6efc7287a0ebf7e340eacb69992d32e5316ef63b144df2b866796cd934	\\x00800003a3e5d2201f8f6720e6206acf80cc2ce407adba174d79c4f72d30ec6c83e8d0f0ca7d29c489974824d6fc7aae5d3b203de67c6f5d0db2dc8f8719f09d30f9ded0c0698455dc4baedc6a6627648f5ca4943d1e0e22a3c49dd170c625dc2a6a06e1e9d6d187792a3748e9f73fb7c795bd9a6b59505a0e254e7305546209cc6f0fe9010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x7435cefb6723aa32554ff1fee5f99d41855d59c3c1b180a3b4e5ce7f21a3e31b4a10e71183dcca45404f94b2b8de7ff9373a963a45f3e4c85ad7835a58664005	1587665210000000	1588270010000000	1650737210000000	1682273210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x00800003cd57265e6acbc3fe78eac67ae683406c3ee72b118db97420012fb8ce9faa64dc62e4489a14b72b365f0bd697ba4a375e33029851ac7840207be92b0689736e62b913588a0a95aa72a382236704f885bc32cd8ac01e913640226f4e932155b2083ed05eb0899350ac59120c5e1e3d287c8f63eef98159d4c11b61d3ee84a03c43010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x04eb4aeda3bea01ce30e104dcc9e09a73f1289d382f55ce81d68f86178352bb2fc42ed1b6c500241e923288cccb9bf87d830cdfc984d0103580027dde20e4902	1585851710000000	1586456510000000	1648923710000000	1680459710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x993df19db1d9858d347a101b12278024a0034c70b2ab7a2b40bc87ee5c15e933ce1d952bae328b5a428c8bf39924481466c9ddb42fcccc8592324c8760961366	\\x00800003d9316d8066f9e582fea86b1e1a6d846184987ad96f73f88e66e30853b35c86dfa86953d3264749dec61577d52171e1abd66213ae7eb2999953943060a4530adf930e44bdfa052dc6d890d4315693870f11c4091de89005aba66647f90ddc615dc78f72c1374567950912f85c04a00716e2833e576d403ef8a20e2972e7a2758f010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xb9921d59e4272ae767a979d9e3ab18270fa73f689b2c8d7ba6176344f0cbbb13f4d8d664e7b04ac03f7da44a3849f481a8db0a664f1b366682fcf90ca8c7be02	1587060710000000	1587665510000000	1650132710000000	1681668710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x00800003b986211387b410e1acf0938086595550c7cd4f84115ac0c87fef183d63963a9eb50d58ff0100e33466a39f26da9cb5f9088d829c1e8243c1964b49e66e39320d06ae95b388148e13dce4693fb3309c68b374b521a868f41da9b0235388c592964602202f776f807da998d5caf858b36fe46e983c1b063c28ab7fbbedec3c697b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x78bcf7e85711ced525576e5c1d52bf16893c4fdf13d5fd4d188c6de4d8222b0d8afe13719f19d5342a2705ad20a8d2180039d82f2de834de769cca8c08e6ae07	1585247210000000	1585852010000000	1648319210000000	1679855210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x98e9f02ee744cc60bb24bdf368c4b1a01e70b6d327c38380cd6a306d5451b79802d7b11a2859ffa86bc9e86f80ce67a8fb8aae6adcd0274739822cf2167b961a	\\x00800003c1f82acfb562d6bad63f16a1bdc8e302dfbbc1f9cf9136f0b5ebd0204abd1e47917635712b2eeb9ce861a50490474e4345ef60042047a1376717510059037edaa8c0df53da16ece15d91b7dacb694521ed903af2ac0af387992da3d326feefe574ec7813ebd7688d77a9170cf70a55e9f63588e1ed57d220102933e780a6f8d1010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x08c5c5d8ec00c2b76214661d2846b6ce2bab719e6fb90822afdd285da69db41a1edec34ca02f05750ee93e275161bb5a9922b1ccb686448ede583729ad4c290b	1586456210000000	1587061010000000	1649528210000000	1681064210000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd628b203825e5c1d6f06fc772be687e4b1236e8525660bebc08612c7d985f1f55c2d01e32f26a994ee775a5d425c1c02d8c75ecc00fc90ede6f83fea0a5e090d	\\x00800003b1ac68a79a3326822f02c389681aeade7733d91ab3a79427c16039783f6f6ca0de0bdcc63c5bbff73f8da7f532a569f5d2a563eed5a826b0485472e71659dff71e2dffe3ea2bffacca6ced7363f77b40a3e6f22c0bd3c6b3e9a27cea48f9aad0a4582f2b0a56182e771d87f08c30f83646fcb3394ebe7a40de8cb1167d4235f5010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x5a703fcd8e76dba0e481a9aaf68d43bdca9b7b9e277d654bcc88fa1b8e8864ea41ef5bc87762dc7127e95e88ec682accde1383d09938c5b261256d2d0204020d	1587665210000000	1588270010000000	1650737210000000	1682273210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x478fe9f5af3431c4d3eb0041181970ebfc4ef63e15f712f3f0882bf6ad45c14698ac62d1c58b687b3811de87e2a3f6bad2a04382e70b98e225680285fad80678	\\x00800003b7aee48ab5d2db9ca0c90bdd4e6248b88117b984a09d3d1fd369373ae92229daf97270d0898958e32507471ab8e0930b63d4cb30585e5dff7f5c11060991ec3bf00c0b6a492be39595674ef0cd1c139c9ad9e04598a97e01ae51d40869c9011b75b7c5cff426c314eb1deb36b2d306e7ab0f03c157b45171ed814523d66ed8d9010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xc981df81e9dbc3700b84e6051a1f6936c7619ea8ec93f01b215754ebeddaa57bc1bac97b902c06ba6a7dd4c91a78ac37bad69e0540214de3649472fdbefae301	1585851710000000	1586456510000000	1648923710000000	1680459710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x423cb1aa741ab0a5237c1a1e96d8564a5cd1a4e1cc092690215c66d33c2ac3bc55d265997f49cb54405ba72c621465571b26dc781c6fc224ebdd418042540ffe	\\x00800003cf2c3266dda5e26deeed6f12cbd216497461ef98d732286109cc866bbc281bacbea593f534e77700c6caed6084311fd243f058c53d622b69d7ac525f2eea33ad8796dc6ac6eec5af846df48c413665614c4e92c3cb4f6f3f03dcef1de33e3700ff2d8ae413366d3c92d26d46267c0027d0dec324da79805d85710790afdc1a8b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x8b37dccb31a6b8a8a860856db7c2695f122f6170750f6e34e11d0eab20eb0bb23ec00c63107078f8015dc29094bf65e58680672fdd43176dde36561acab8e303	1587060710000000	1587665510000000	1650132710000000	1681668710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x770c748e581e8ed7edea219a09ecb0018a2015d5a8017f746511950f5da1c4ad1ded37a5f054bb1b0b8902cbd3767f9b0cf4e0a8e5a8f29bf555eb89dfe78fad	\\x00800003c25aced68214c1987b142f6407c6a40b01c3cac34606abcc69f71e13c5e3064b85a6b0a4ebeab7350e785887cbe9b1bc89746f16488352003fb00b202c71d1dbef46651c18b0c25e080a2a17c9c05f00c76c07bdf01399026a51f9d5e4337e9e4585d7dff0b2ec3ed02db6458c297dc892e3542037180b15993904eefaf64013010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x53048fbf584f2c38ec2fce2d2271bf392eb59fd00579ccf248c0bdfdc1014b60393ca1e5abf0612209b8ef7d787ae009398091b162c4a0a7f4eaf33cacecae09	1585247210000000	1585852010000000	1648319210000000	1679855210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd24ed264c3aed6dc5e0b038789f8b96c7a39e5afad1a6d1152e7522dce16cb07057c685ebb3ec13c4d813e7526934a0bedae3a3f69ff5ed67b17ce19c3900d07	\\x00800003b7063021c33fe1a2350cd57dd0460a9b87ac5f1e1de626400f6c07b7b930180a8183753725882ba4b484a3995ce50f69bfcaa55decbec1dee1474478ed1b09590672eabb0ec284c40adf1821da15855b79226ab705b915f1a1c7700b8534fb5d8bca6183ff89a975bd772dadb4f4facd3206f048ed71cbe61732557e5f09ca6d010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x9927a1597b6a4ebd9f1a220dcdef44af6121de38591ba5589a9fe360557967d20e0018190feffd4cb403b22bd736415e6de8f3c86b9ad208f6f086374b62fb0b	1586456210000000	1587061010000000	1649528210000000	1681064210000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf83190c4582e1152cd1d1cc323b2b0bce4603dac971c160babf3389cf5e585796e4c3973db82924be749ba9655471d73653774df3963cc86535f423fd628ce48	\\x0100000398c7409ceac2a45d8107fbc805d73def578387ccc929c08f6ef999c1d31656b8aa88bb7ce82709cb61fc71aa1866d4c208e875e0da6edd6677fc3ee1f4dbf1096ece98873937a4a06c1446653db2aea6bd51c3a288b619420305035c785b9d78120fdf2900bdb51d388c130f66871250ae7fc84e0848f44e4edae8c61811cc9b35f5b8c280bad4103f47febb3476df92ec7feaa3133b3f128e7afe0095b37f7e149c44d2f92e107e544dab6e5926bd3943522d537f0f7ffd201869240e9cf8c6fa11ab840f0ba0f6c918ae451bae71b590ad8c540046e31346f9b0680782c1d5f7a5841c853d39a89da685d31dbe6437e5c1a15b699799297c64d999ed3b3f1b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xcc08ef004e961fa31c20bae17bc8dd22840cbb448a944006abb024f6bdcaa788cce8a5821f3d11f329b3940480504d6464863e4ff5219ca168cb60ea9b17360c	1585247210000000	1585852010000000	1648319210000000	1679855210000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xabfb9c9fcaec888f4c41cc0caa0697e857c7438ffd5b44ad31c6a03706e9f507e47b84042a40b40bbfce9ac3086337f1f93a3dd6c73b81b5dbe6b8008d0b195d	\\x00800003c3e1272d04100a4da90c1c1fa880a9ce307147aea9c3446fc8d8af0c79c8bc5c3d18245f1d0de8341b7604e55f037c699023b1617f4a680b5af11c7667bd179ebc624ada5e9a566f4def432059e4b6987a003f9e0d1642d78f881d35f70e88596c8fc9a04b3fbd58db223c3cf67bf5b918d49c42b8f278d5b9fdf4c22e9b0e8b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x92b719ff98607bf673e7fd296fb90715bbed78a29c460596bfd6ad18b654e1c1c6710b0e9b2cccf306d33a9d23ba0b69e6c5aa50f172d8a0b4855903f8411603	1588269710000000	1588874510000000	1651341710000000	1682877710000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa901213e3003e1b9010fe14ecec385d940c1062eb55665cabd1b7ecb4bb221b5dc4a504edc0a98341564c526e65f765c0c0339a9c4cacc14047f921974c0bc3a	\\x00800003c2fc18727b002faaf51a748d609df4f2decef150315870e32ac863700490a84ad74da172a383e7cac437c2d7c01952fcc8e20acaafc0a95f7bbd39d3ecc16f9176fe346c41124efa51ca753226bd8f63439fcb019f191bd06b28c88144325070d8c30c0647ba0649bb6353da90f52e7456b2d15a91dd83fc08623928e91d644f010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x078d5089fda1a6ba991a9c8258c1502fbaa08a61171598fd716f7733eac65c063bcd1de3f86078518e41803bfe873aa14371418562511455979425568713a804	1588269710000000	1588874510000000	1651341710000000	1682877710000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6fb5795135c3e9dda4c1f9726330f5c2133c1f10d75784c9acf91e2f5c480a50bcb7c3af863a2ce41df9aa20ec99eb6f9ca328ba3ce70718d4bbde98467f9077	\\x00800003ce0c661bdd3ecfce5c3c0a4b600dce4cfbae366e89a36980c73737a3c885b9c18e0bee6aab678ceefb5c7d1fe23625735c1528624e06eb7855e27e633f0b968ad0d28c883ffc38db707d9800abda97d68ae9269bf765f40f7155ae91a7d12d5aed6ba9884c6d2b5a99c4e3fac277e21462f227fc04f2be4a049e16d8aefa43eb010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x20088dda14c294c0d56d5afbd26981e3bc5b22cfc9a1f008f025030fe4811254bd72ed03207d392d88db631da56c4a718ebee6f898b042e75ba6dddfecbe5a0d	1588269710000000	1588874510000000	1651341710000000	1682877710000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf67f29265d2ff217d3b10a405f10948095527a1130bd9940b449ef76bb911c4fccb4b2e3d16d7e032f91a5eb71ab1d4a67df4430f69707ac71b5d39b30659f3b	\\x00800003e006a9ea892bd6352b09367421a6434bb14481eef0b9815dbcaf34939bfbf1ab545b0795fd39b1fed1a56d52581e7ee5d0143c9855f0dae8a25046369998320fbba3e6a51cc772110aca3e9871421242b3b1ac5416f5adb1989cf65508a52f0a282bf3017210f8695540531d4ac25c91c4095b3759da44661f34f602d373fa85010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x649d8a73c8d858bb8c82f1d03748c165ae5e6f2c91ec389fefbd1c7fe9f6366c118cd980435d44b818f7051b8fdb8d0e861a77f90cae5c43d9de0f753c8ba70c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x88337537317cc8b51018fb4c4548bbedcbbf28c0c2eec201d8352f9110d08e80d3e1449a0008f62e5f44a27efdaf5ffa99c34abfb0279e2cb7fb8e9e9c091ed3	\\x00800003a9fb3a0f9cd59f01975206a2466546bb1151c79e3fd721f46589966b81277b685ddd768f58c505b1a40de62e87073e623748ccde14fe11933c25c1d1d9d9989c501fec933b04921ef94e72e2f27b403b3935d4905a7df21d1943e372195315e62379ed7c040f4d1110eca8095ccc5dbdcf2bcf533ac49db010ca6bea0dbe664f010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x81f04ba3211ad8c24e7e82241511b8ada9087df9cf201620092db4eeb91a52b3bc499e1e9892802972eb3dc82b6b1ee72e445f56e131a7f14d6ae5514e318904	1588269710000000	1588874510000000	1651341710000000	1682877710000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfd2ad49aab62ebae12f33fe6de7ccf47884d467965b906937194b5fc4bff011da194010a26d10aa3fe51d376fa91f6b24e4a874b9641b755ec78ff6330f913b2	\\x00800003a13560cc33a4d3c46ed4936079d4a857a36313d950aa782e0b2e7caf438d76300c0a8f827bc691451755ccd1a12d1520af895de882128c92b21cd270c5d60815bac69ef00944c7389412b801b5ac04553cf4bf77c15463c3ee72f4a69b4df0c32f0af8a34e9d2acd478f60787be2769ec73b08e6ff4248fac33decc33727e75d010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x1938eecca25bf04c6edc549362d35d30f4b435d2b3179bb2faa786e70f0c2e23da53c4528ede3e781975823f597309e52f647189c81fb4458671d394a3cbbc02	1588269710000000	1588874510000000	1651341710000000	1682877710000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x47c01b601fcf1fb694b873ffcbbf6f29a967a62a4d8bb117224dea0059d89a75336a58a71a14a0c8e08474116ede3af09278f75027f5017ec8678de2b3a9fd79	\\x00800003bf5abf26d345a5a8d9c4bbe7566c68c34c8e94f38078dc5c1e044071954d2aaa75d0c91346c324af56b6965e4c6a36068820f98ef77185043b95a05bbd4f0a4912a0bfd9cd939fc990ecd85d3ad2ead9d5dcce378ed35c08ebdfbc6206887ba2d84fde2b64506a66fd84ea04f8fad937565f2985f2df0dd2213ea4db6240cdad010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\x76672d0041d15cc3a3b29152a0136bb51bac0e056d1bf27398dc9ec8160134281c3e0b38e6ef6ff0d5cd781ad758519a7941b131a221eb7179d8c01c5d73910c	1588269710000000	1588874510000000	1651341710000000	1682877710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xea07a69a2e207613ee0342ac42375a512a5de80c2de1fe45b8e02fc088afc54e57800714896492d7592f1760ce39a52b2e993f188ae22af2b581338541df9e6d	\\x00800003d584493d65b12ffb09660cdf99fe7a0e73cd2bdc171f3842ee4553b1adabd4fc6cc66898994cbe304f1556bfd146b10c0d99c5f760d0914617e50e5ff2bd3f87afef5be664878951b684de9c04c402845dce1686826657ac3f265a83f5a83ac164d9a565bd76b3e7d7ace886df11e36b43cc261e66cf72273a8569bd1dcaa323010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xcc6fcc2c5aafdb1143b18c713156d7804d6fca3da80a5eeea5819ddd1e0f528a0cf3bee9e6465d1a6e935f8cb83c42c422b30029360188c2cb47d8dacce94c05	1588269710000000	1588874510000000	1651341710000000	1682877710000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x01000003f03df875cb648ec841dc9a2f1b022dbbcdda85a0a751e4af31f417d93ab82940a39cd6a012173fd2d23660794f4c6abfa808a096ac80693b1e37ddd90e01ceff63814c30b181cc571366f996044b43e8e8353b1aa05e9fb104d54a4cc808b1fa007a052531ae857cb0cf835ffbc6eb8995c7d6cc761dee167f113c315bfa15c54fc5c70a1afc157e9b424863b27aeb1f3f2418f5d8e4704bb950cf697e45af263e03330804c618a4cf74c2b8a291a5c1f5038b829a8f8dd0e0574c15ec31a04f423d7b47496429b1fa76512f90fd1dc1c305a49e8384b3459b2d9ff8b7dc2e156e606c102cb0e73d21c70cd97e602f07ba29d6e884f2ee8579f25525a6b0215b010001	\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xe7655b0a2a0fe1c405b2dc7172852c07c33964ccae520ed175a6a6901090a3d9d9d1d079c57a8789ae1b2e9b49c6f86f8c3fcbab1395d004fba86b8354012202	1585851710000000	1586456510000000	1648923710000000	1680459710000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	1	\\x33dd12045a32c69793ec8aff33d4ed3a18e96490ef0e6a95c4216eece585e79c4589523cd3de5c5435b8891935944c19f544c1901152fcdd224bb6daa90793e3	\\xb5a83c13d972e767ee6746d0537d32cffadc8a0af078212c858c4e74d835e965707f782edb666ae541402ec83b136213951e730ec01021fd0d5679583f67e8d8	1585247238000000	1585248138000000	0	1000000	\\x24209fe74c418f2babfdad3860e58645ea750c60e1d1ad1ed22c110ab2eb83a0	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x0417c7c22bfd7a0af863e0969e493b14e08a9cd6123990867bed9c82baa325518ad5f0400b22d1018754440ca079c758498edd2b806303aa206bc4a208e61e0c	\\x946e8b5af562e6bdae3f9e9f1996162e81eb835d52f6b1455194d1c8a4afde69	\\x6de6e4b001000000e0a5ff512e7f0000e38dd6d74c560000c90d00382e7f00004a0d00382e7f0000300d00382e7f0000340d00382e7f0000709900382e7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x07fa6375f8679153a23927ce068b019acc3d50fd696e74caf09f2fd776c21cb8	1	0	1585247230000000	1585248130000000	1585248130000000	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x8390d204c43d8418bdf4a2e5466fb50084a86829ab5b445cd38c199bfdf433a6b2dcb78d977ba238be29fed3640acf62954837308581bfc86bac0c48c0d08997	\\xb5a83c13d972e767ee6746d0537d32cffadc8a0af078212c858c4e74d835e965707f782edb666ae541402ec83b136213951e730ec01021fd0d5679583f67e8d8	\\x8a54ca1e621e70637f08def917a9e7bac14892799508641b2f9d4b82418f05e7c5eea6d732b6782c24b11be23e746161027aef3fc4ee41cf9d69aa775b88710b	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"35XFPHEBXDG1F1XRNGC4299K14CHFQKKBPX2WTSD748Z2ARQR0ZWKM6TWMY3Z2HN1K1AB4HBMBBX21NHY6Z120RZNSASXDX163XZA2G"}	f	f
2	\\x24209fe74c418f2babfdad3860e58645ea750c60e1d1ad1ed22c110ab2eb83a0	0	2000000	1585247238000000	1585248138000000	1585248138000000	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x33dd12045a32c69793ec8aff33d4ed3a18e96490ef0e6a95c4216eece585e79c4589523cd3de5c5435b8891935944c19f544c1901152fcdd224bb6daa90793e3	\\xb5a83c13d972e767ee6746d0537d32cffadc8a0af078212c858c4e74d835e965707f782edb666ae541402ec83b136213951e730ec01021fd0d5679583f67e8d8	\\xf4976cd0bb732303872537f5f82dcb90da48297da2475af6d279607bc7b77a7a973344b14795c1e7f0dc7992e43edd1975f71bdedefc348a032f815c07a6d10f	{"payto_uri":"payto://x-taler-bank/localhost/42","salt":"35XFPHEBXDG1F1XRNGC4299K14CHFQKKBPX2WTSD748Z2ARQR0ZWKM6TWMY3Z2HN1K1AB4HBMBBX21NHY6Z120RZNSASXDX163XZA2G"}	f	f
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
1	contenttypes	0001_initial	2020-03-26 19:27:01.883355+01
2	auth	0001_initial	2020-03-26 19:27:01.911343+01
3	app	0001_initial	2020-03-26 19:27:01.957748+01
4	contenttypes	0002_remove_content_type_name	2020-03-26 19:27:01.98024+01
5	auth	0002_alter_permission_name_max_length	2020-03-26 19:27:01.9839+01
6	auth	0003_alter_user_email_max_length	2020-03-26 19:27:01.989985+01
7	auth	0004_alter_user_username_opts	2020-03-26 19:27:01.996036+01
8	auth	0005_alter_user_last_login_null	2020-03-26 19:27:02.003583+01
9	auth	0006_require_contenttypes_0002	2020-03-26 19:27:02.004971+01
10	auth	0007_alter_validators_add_error_messages	2020-03-26 19:27:02.010342+01
11	auth	0008_alter_user_username_max_length	2020-03-26 19:27:02.018993+01
12	auth	0009_alter_user_last_name_max_length	2020-03-26 19:27:02.02738+01
13	auth	0010_alter_group_name_max_length	2020-03-26 19:27:02.033904+01
14	auth	0011_update_proxy_permissions	2020-03-26 19:27:02.041875+01
15	sessions	0001_initial	2020-03-26 19:27:02.046428+01
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
\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x464682af73ec741329585433751b206eb2520bb65470ef018faa1c485030057220b883b6b968b8fbff256cfeecf2f995830ba20dc6a356cdc0207314d5e2af0e
\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x472c8ea2c7e1e8cc0bc5c55063f4cbe3d67b2e94355c4fd702b14b64d2986090292f67493a9921a63aa67057c5d169aa2e7f96b4c5d729879675e6d07595dd08
\\xac008e081df3aa3a18c395c1a8c33888afa3f863481231bf79fb8031dd2a4f5c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xc5ced6e9f6914133e532678d4136ddd79180a7465a0fe8f11b9d47f74916b71c5edd6f5064da771d819386714d6bb8cbc252a14554cae356630008a81b7ac70d
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x2750ad23f959b4616f9bb9913b2c05789ac60905a9ecccd2a499f99ec9d40d0a	\\xe0726684567b8f6e972ae98a1c743d83344292e41f48d2696272bbe7d7cf28e4fe4ca576cefee21dcf4d05dc1927dbed383bd6383af4f6919c6185cb86c29fc2	\\x974ee8270e59824583948825272df1816ad14b0304ec9b37546fc91f8946d27416549486ca279f35b054390663c0475b1f29b9bffdec6bb2450029b742d7694ea034f18f439b17ae7aae6f8acd8f3939d9a4c3fdfb7bbc448993d8b4d082df47d340c5e62faae002d728696cbda03eb4362aff1d4292f6f9d34d6ab6f6685ad9
\\x07fa6375f8679153a23927ce068b019acc3d50fd696e74caf09f2fd776c21cb8	\\xfac60747f6f5230990e394d61524d5e5c2d7fde9d64cb67971383afded993d28b8ccc24859da6595521f2131f8b29f7249a132b21bd783ddc17df6743baa690f	\\x83c04be2454671a89ace301cbb411f274541dfd4f7507b8087902a9b291ed676aec6f727f4d6f1a3e0d476cbbc2168e506d35a832c3e0ccbca28ce88b25c32756368ab972d2fbe5e05f665941beed0282f0ddf81cb41324ea5550294cc3f182c61578a09aa341ed5413fcea49821ce673841694ef953374b07dbabfaa444cfc9
\\x39ecdf0cece28769866927fdcbc0229e73e0e6458efd948eb07278b8ac0d738c	\\xb2b398d560e595d6d879842cd209cc84c924a57538ffe918aa6f3107492495740d2dadd63f34109c3a19caa665eabb781359cac5c496e56a36bfc6926d3a45a8	\\x613eea075a730f76e14eeb41e1baa6eec22ff929880ca8f587f66f402f627d4d1bcfa3936042c55be7cfec44313d25c5a16632314a6d235b416de39be3ba132789106d61a1adaedc8c54a100fc9ac6aeadd2032a4e654029cc67e8a3db891f69915aff2e8519484ad76bd56b2c5be8f4837d6bde18cc5f4b09fd0a679b91cacb
\\x5dda7191fa7b5e84562493ff81198c38d00b847b9c16c26d8b92b906781e7560	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x80074868b3e549225c6c87faa8737dc832aab8407f5d1fb65904eeb4045ae170b002443a63dbd769848f172d8b9e17d469d922fa4cffc6381f1f3dac00266df603d42a70eec700b69b9ede18a95bde9c7938e585a4a48d9c721fd947ae66686487b029cba41e527bdf8ebdc86c5dbfdad788f49b4dc2f58a6403995101e487ee
\\x06a8b55926e31e43b7514c608cc267fe498bbb6ee62655ef792c71966af1fa97	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x9e2827f7ccd5b3444a171d2279740abedb5ee623092e02cd602c7454855475b92de52cfa3dfbe9f060ab8f29f645af7b4cc230575212ad52e9bbe3da8affe17bbc42699e97d81b2fa334c35977dd17716fcf2bf3aee3c1c24a2ac727f26d64554e171f7fac975e08c81ee61d7671ad3e8852fac6171757d1d7c7d39e2554420f
\\x4c647b1aa4a9b73b44a797b104bedcb9dfb4d46ba36b9e7b3f2125b3ba761c4b	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x98337fbf9c56519ec1de2aea2ea0162e13691aaf954b8ac8a32067d7f1a45a5866e99ccb03932bbf1c445100ca70363b4cf28b76e3bc6443666c677ed02a74251d32beaf3a978fef137aa00d655079e32df3bb495d02998bbe41d0e552178bb36f15d10f25f6e609c25ba69a06da8a05e65ebf01ab4f22b7b18373248506956b
\\x6582a1874903dfdb722dbfda9c54cf0715fc63801ed583deb18e180bc8332a22	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x3e9426a6e6f7190342e4c2145619544881470c114cd752cc6648ff3f96d4970ab6c809695dbfe879c60cb03014b8d3714f3a95e8f6c8627271f5ef5e1af9eed4db7257ca7367491b7e99d0342cb57274a4be51f873b1892cf5a1ec548e59e2e8e0919fa4c47b15fc5f973630971e5f7acb3519c372432562b97384f5daec9245
\\x310b12c172bc4c7af4a0afd129a91fc88f59c07a7a9b78d528971be425169509	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x851da010c78e988cd85fb4ec0e7df7ff360af246eb7e11f2843490c535375aab07f615c7ce1f98e1f636083f44d8e4dd208936f7355b2f074a06ae2e2aa8d74a53e8330999df6667c65a2dbb452b58956928a47be6bbcdb2df9d4fbc802080a54c2cb7bf0a73cadc6c51bb7473bc15b190635c64527c05c0910a2515ed31cf72
\\x66e756ee0c152112a5a31e2127d3a13df65fdcc6a5d3de9abe803ed293508f05	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x0b100148c18896ae2e7ca3b18f2e7b83497217c4a05d2a64b69e233264dc6f2b817871aa1dfd074d3b48e29fa20f782a45a66922a0d805e7f91b9431b19dcc1bf1a11fbe6165def68d54eb80f5bcb7b37beb38641168ef15d8812b9682dc7d1b3279e499632139d96b7996bb8d88b00b902199b7126d7a492517d673b57a1cb2
\\x4a4693f51d818eb32db0972f19710b2450e3514033fa33e6588c90e265b56095	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x563182fed54bc151b33f935ade827faf970a393f756f674ac85e31ad6e02b599f9c2ec8498c7b0e9441acb8c68da3688b56c2ce7e26b4aeaa5421356c6149aed33a9832e8f5903f2a140ca499d171d156c04879318ba1f900bc0eae9afc6ac0094d68ad782ddbe49a712c5a59a6a9125217b82c53ee99b4a0a37739872098a4a
\\xeefcdce7677b4b91ba60c28abc7f2f827d8868e09abfb439567e255cff085137	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x9a239c847a3235355ee0ecd526d486f213f3df2a4dcffc8e3e0d691ad59007995d01e6f4723eb9334588a14b993ab4f039bf85efcaa58a251e9b7e64525f0a0a8084215ae18b014405b73ecce7e6e840ca5ae0de3ea46bfad2b81f2e38ec5a5961e2fa3cbb7c61fb67146cf82528e1a9b987be9f83bb7e2927a557d70a00835e
\\x24209fe74c418f2babfdad3860e58645ea750c60e1d1ad1ed22c110ab2eb83a0	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x1aa15032c925171a476ee694c75fcbee781cf98fe40034ca13f8369a7e8d0c9a0c1afca19353db50f3c8e6a8ad2fdabfe69c9786182df0a064ca5217c5e0d91882cf7d45109f1fa0435eed069ba3ed872c986fed3c7c6130d2e918733d76e262aedb0ddd4ff03d035dddfd9b65f7de41e1259c0ae5bbf3599841844ff3f0f94b0330e01da7ebf001755604aed05b7372c197bb2812d34e377b104a0026cf7afc36aa09736c8344d7d232f88eda43bd2f540b9844d5334a2834f2c4ab61bc25d43377391b596a47efd666c56c58c524eda63618db277abdfa776230bca74abef035e1996fbdbe5bdbcb7f6a2584141ac43fc59965a05b793c8ccfc22e7faf4c26
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2020.086-0104C3T13YHRE	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234383133303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234383133303030307d2c226f726465725f6964223a22323032302e3038362d30313034433354313359485245222c2274696d657374616d70223a7b22745f6d73223a313538353234373233303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333333633303030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4730385732305859454e334d3636334a51305448475352483251543759333339303933334656535a4530333351394139584530227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2250504d335234595345424b5046564b3738563835365a394a535a5844533247415931573232423435484837373950314e58354a51305a5652355644504354513538353032584a3156324448313735385945433743303431315a4d364e4359415237584b59485030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22394d595234594e563935583744355147585a5141394d3739593750543242594e4536353159505854415a313757523931384b5847222c226e6f6e6365223a22573041334b33595850324d415150535131305752543031515a4d523831524a44413244445346583150473345373830504e594530227d	\\x8390d204c43d8418bdf4a2e5466fb50084a86829ab5b445cd38c199bfdf433a6b2dcb78d977ba238be29fed3640acf62954837308581bfc86bac0c48c0d08997	1585247230000000	1	t
2020.086-01WE89FA7FS14	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234383133383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234383133383030307d2c226f726465725f6964223a22323032302e3038362d30315745383946413746533134222c2274696d657374616d70223a7b22745f6d73223a313538353234373233383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333333633383030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4730385732305859454e334d3636334a51305448475352483251543759333339303933334656535a4530333351394139584530227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2250504d335234595345424b5046564b3738563835365a394a535a5844533247415931573232423435484837373950314e58354a51305a5652355644504354513538353032584a3156324448313735385945433743303431315a4d364e4359415237584b59485030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22394d595234594e563935583744355147585a5141394d3739593750543242594e4536353159505854415a313757523931384b5847222c226e6f6e6365223a223156324d4652374850505759313948573859585341594e3150534b54443252594556443048504551503030525347584134343647227d	\\x33dd12045a32c69793ec8aff33d4ed3a18e96490ef0e6a95c4216eece585e79c4589523cd3de5c5435b8891935944c19f544c1901152fcdd224bb6daa90793e3	1585247238000000	2	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x8390d204c43d8418bdf4a2e5466fb50084a86829ab5b445cd38c199bfdf433a6b2dcb78d977ba238be29fed3640acf62954837308581bfc86bac0c48c0d08997	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x07fa6375f8679153a23927ce068b019acc3d50fd696e74caf09f2fd776c21cb8	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x946e8b5af562e6bdae3f9e9f1996162e81eb835d52f6b1455194d1c8a4afde69	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2259413239344743533532314d4b46394e5831364b353630503942515341514842524356474e4d424443413748444b4d473850415744304d3835383936445330373433544a4d50425a564443454a41583654504a30424738595a44524b5a4d575354585a51383152222c22707562223a224a4851385050514e43424b425642485a4b5446484b354750355430595130545841425642324841484a4b38574839354656534d47227d
\\x33dd12045a32c69793ec8aff33d4ed3a18e96490ef0e6a95c4216eece585e79c4589523cd3de5c5435b8891935944c19f544c1901152fcdd224bb6daa90793e3	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x24209fe74c418f2babfdad3860e58645ea750c60e1d1ad1ed22c110ab2eb83a0	http://localhost:8081/	0	2000000	0	1000000	0	1000000	0	1000000	\\x946e8b5af562e6bdae3f9e9f1996162e81eb835d52f6b1455194d1c8a4afde69	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2230474257464748425a4e58304e59333357324239574a3956324b47384e3736503238575331314b565850453835454e33344e38524e4e46473830354a354d383147584134383335304637334e474a4345564d4e52305252334e3847365148353231334b31573330222c22707562223a224a4851385050514e43424b425642485a4b5446484b354750355430595130545841425642324841484a4b38574839354656534d47227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2020.086-0104C3T13YHRE	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234383133303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234383133303030307d2c226f726465725f6964223a22323032302e3038362d30313034433354313359485245222c2274696d657374616d70223a7b22745f6d73223a313538353234373233303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333333633303030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4730385732305859454e334d3636334a51305448475352483251543759333339303933334656535a4530333351394139584530227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2250504d335234595345424b5046564b3738563835365a394a535a5844533247415931573232423435484837373950314e58354a51305a5652355644504354513538353032584a3156324448313735385945433743303431315a4d364e4359415237584b59485030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22394d595234594e563935583744355147585a5141394d3739593750543242594e4536353159505854415a313757523931384b5847227d	1585247230000000
2020.086-01WE89FA7FS14	\\x4d3d827abb497a7696f0efeea4d0e9f1eda12fd5718a1f5bba57c27e612144fb	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a22222c22726566756e645f646561646c696e65223a7b22745f6d73223a313538353234383133383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313538353234383133383030307d2c226f726465725f6964223a22323032302e3038362d30315745383946413746533134222c2274696d657374616d70223a7b22745f6d73223a313538353234373233383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313538353333333633383030307d2c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e4730385732305859454e334d3636334a51305448475352483251543759333339303933334656535a4530333351394139584530227d5d2c2261756469746f7273223a5b5d2c22685f77697265223a2250504d335234595345424b5046564b3738563835365a394a535a5844533247415931573232423435484837373950314e58354a51305a5652355644504354513538353032584a3156324448313735385945433743303431315a4d364e4359415237584b59485030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22394d595234594e563935583744355147585a5141394d3739593750543242594e4536353159505854415a313757523931384b5847227d	1585247238000000
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
1	\\x2750ad23f959b4616f9bb9913b2c05789ac60905a9ecccd2a499f99ec9d40d0a	\\x458250decaaee758800ede6a5f0dffa49e8a2ee946bbcfa37156d6a9ab5032f25fc83874092e1868fa17f8c747547f1afc956cb57a9f39989f14fec6bd6ec007	\\xdb7023ef2d57c4f4500a37295021194aea177622a15f4d8c11fd0136b269265a	2	0	1585247229000000	\\xe4c580166cc482aeed98e877c5c4b6d288c458c78ffdea5eff38729a2412bf787c7a462e5705103920288717ef27a3dbabd1c1c07ad7ea425e25ed7763dcc1f0
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x5dda7191fa7b5e84562493ff81198c38d00b847b9c16c26d8b92b906781e7560	\\xfd217b015e0ccf9054b607a5ed62f1eeccbf65ed85277424418d9992671c38272eaed29d337a8e3542df1b650cb07abe436156d0790a1fcf0f902aaff6e32a0d	\\xa6257f6882d3cc5c3c9b882d692f7e5736a732bb3396bbb3975bba0b18e6321e	0	10000000	1585852036000000	\\xc88c70b05f6f8cff8c173bcf1b223478c51c4497ba93c2472fe4dc76d00689cb4951a8ceca4d00944d8bde9cf2aac94db5e129c6e5be44a1a7ff8a864b3bd0d9
2	\\x06a8b55926e31e43b7514c608cc267fe498bbb6ee62655ef792c71966af1fa97	\\x8061b43e162908e52a6ad932109c20125708e1aac8c147a95d9fba80fd81f1c5e4d903f83656f6ca9ec3dfaa4bc1533adb3c5f972c19acace87028551b822502	\\xf6d96f6a32d51fc9eac7282ab677bf1639f62d8d78e1fa9d159d6507b492ca27	0	10000000	1585852036000000	\\x33b42711b523febdb144fd930a49b050ed9108da4f653c9d7ff79c6fa3a77942449f6abdaa9ec0f43f8b2ee892082dec6e8fd86d244be5cc7504ae7b625420e3
3	\\x4c647b1aa4a9b73b44a797b104bedcb9dfb4d46ba36b9e7b3f2125b3ba761c4b	\\x093df9c0402076959641e4063e3aed2278bf4d52eb6da260b72a1c7a38db4d9b8064d8bd76a8c03f262e5d805f77adc54dac03b776287b616d27fb42f7bae70f	\\xe7c812758c46b02b551f8ec6c3b936db1c28a6ff9e2004668d530f9708aaae33	0	10000000	1585852036000000	\\xf98f4b7afe27fdd8a572159413cfff527f6249d8731feb2f81811572cd3719f4daf4e671fee2bf180d1a15a203a6c5fe4c8d6f3a9e00d2f074e44efe3b4c44b8
4	\\x6582a1874903dfdb722dbfda9c54cf0715fc63801ed583deb18e180bc8332a22	\\x790190f22f2d60f54114ee168b6e9f58d2466763299c04012796678e98c1723bc99baec9c542c0d10a459b38a7e9fed7d17c470106a62098f77305955ea1ba08	\\xd0a6359ef0fb86433c3d34a89594107fac6aeb9d4b3cfed5dcb8a07087561ce7	0	10000000	1585852036000000	\\x9e88a7e41f31c1048782955bde254a663e55c6764ea9b9354918221c2c6053ec2b6832fb72a80435c0b2055d754dde03ee7dac4e3251037150180d02f363364f
5	\\x310b12c172bc4c7af4a0afd129a91fc88f59c07a7a9b78d528971be425169509	\\xb11b6cf502182e7661c368187179872574d68836bbd7f4ddaf72ff14c04862030197cd760a129022fa70743f4adbfc0fd71c0fb36d5d9d1a299d27f7582e5706	\\xea2a6013507080345e8e68b0a5da32560da61e31f65da3c61ed0ec2da203d75c	0	10000000	1585852036000000	\\xe2d21bfbb014870b62172458af49b6b8e6a36af38c79afbfd9fad9d66420b3d8af2e98c5b6c1a16fd49aca7b74bbfdb4ccce32d879d79f2a579afec89b627317
6	\\x66e756ee0c152112a5a31e2127d3a13df65fdcc6a5d3de9abe803ed293508f05	\\xfb67164fb92f9c194e9d11adad127973532b74e6b6d44e917cd445cd05931a3da0a0e64cee92272d1501af215f355cd015f96c6f2ab8a5a7cae63dd8b54ce90a	\\x795951840313147957428fbc8f2eee4bea77042c2546331a46c9c6d0e79ef242	0	10000000	1585852036000000	\\x5def2ae83577b46954abe9fccec8930c9d9f0d825bc545b224f990545f9b6fb1c38d559677ea9252ca3daeeac5963dc79fc860a240b7b3a7b9af8ed47a679b14
7	\\x4a4693f51d818eb32db0972f19710b2450e3514033fa33e6588c90e265b56095	\\x170c35d8d4e6fc0f470701f2d08f4f038c47af1a5a590294783d714606cbc58b2f517f6bc33b68567548d04079f0a0b0c58707ac132e0df116a9079a77871d07	\\xea00a088f3efc2497b7d93976134696330398f4b4a4bff48df050e9a0161dcc9	0	10000000	1585852036000000	\\xb697df52aad42496994e2737f2980617856867883392fa8dcf71eea3a69896ae3385d84bf5e32226ae51553fbb5cffdbf57cfa6764d6d6918ec978c9f4971a82
8	\\xeefcdce7677b4b91ba60c28abc7f2f827d8868e09abfb439567e255cff085137	\\xcbeb077660ab284a9ec0bae485c65c1c8c8244689648611612934063e740e1f0e3f01e7a309e5befea045fbb81e20c90b2353dc503020eecc2f378c5565ebe0c	\\x6d4a775680ef7de6a176cfc0d6e3ab00c5401f4a4e2bd53ef982a35cc97b1cdc	0	10000000	1585852036000000	\\xe5ca930828a38b367f72ec9e268125eda82664be5fecfa3841df1ca0e9a9ec6e6c719153eb6a44aeb2675e4f3d013d11e51edbd492bacbc8bf8656bd626d108a
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	\\x39ecdf0cece28769866927fdcbc0229e73e0e6458efd948eb07278b8ac0d738c	\\x62a900a609109f343f68b39c5e0508b8cdde3da11fe8d0e21145ab5575abc8a0629f7328baa62c206296686b0b6a63370657135bbba8fa88be3b24353cd01f0f	5	0	0
2	\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	\\x39ecdf0cece28769866927fdcbc0229e73e0e6458efd948eb07278b8ac0d738c	\\x7cab0997915f3c39464afcde89e7e35df1a450bbad44128b78f7da52f3328a73f3b0890a2f330ad76ca6e5d30caabd71e3e4e7ece21f5576964da4594dec8904	0	80000000	0
3	\\xfcc21691669f322732ca1b3229921c06ad7de9ac8bbeb67cf83424a2380ad26f70552b222c21be55287447acba12746af988ed5bbddff7331589c2a3376879ec	\\x24209fe74c418f2babfdad3860e58645ea750c60e1d1ad1ed22c110ab2eb83a0	\\xc24c117ead15d951c26b1748c302d574ee01b05be54ce134d33994a200cd2fb4b1b2e03e85dd1786a36874dd9f0a51645ad5d8cf24eca34ad13df75418f4bc0b	0	7000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	0	\\x12b4debb810bd37ece7834604c3ba148cf831542903204b1247ee57a9d9e45428d388c4846926bbe840c548f2b3b3508af5bda66d78445663d930dc55b32ee09	\\x596dd70417dea3f96b72decf73ebbee411295403914758bcc5d562d1232ad6aa8b14857b58e1cf9ae9b1535ffe4fbdeb4e9b6d67f0739173b64d9bfab00c1f0c	\\x01707fabae5b3f80339b9e28271b6d3ee4e63741de61b4b274cf742032fc9a6f38c352b798fda4a8c490a5a8886a9367abf5f20282060e2590d0a8ceb127e5cf6bc353c08e1b20ec0f6803c10d0aea3fd5e20f2bf02bf0b783c6df3a1d464bbe973efeb98442a99dab83bdab0b8add7e78cc42ac4422628a67fe3e0bbad83d6a	\\x9ed687c6aeaf69d91788dd87a1d2adb4c68c0849a5baf0e4e1397ebd16a4b1ecec28da59196593f5f25db205a1562117027639ff772a3dc0efef4f531936a83e	\\x80a780980d0f24d0b9735b55cc2c83238c97866ad50ab9ee3490cdda8b024b6dc7b02fcf9cc34ecd59dc5f671af4d5325224e4a9bf14a6591a7a276cb5aa6a9f19a948c354df538ed5cdf7809758934b3ff5b96153cd7b317d6f17c32d1aec40aa11699cdb44ca6c3fa2dad9b9624fd1d161452c4acc4f0c37a8f1864c58302a
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	1	\\x52b38f12698482134ba9474f05c7067fa0b7d0e88eb8b8ff940f639997e248275aacc8f14cfaf377d8d66dea69caf3741eb0946a6cd10de7f7ae657278a73e00	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\xc83267d087846d48caf06d8a713e7cc66bf62c580630bc455149216cddcee9cfecb4fcb53b930794e99762bbaab9d82a5b6c0e5f15046907f949be7725891b66757c2421f9af5c32df310049bb6454aafc31802710df4432a10c954a6726c3980ba0faff437233670f7253ef6f37235e566630d24697014798525db15434bad6	\\xe5ca930828a38b367f72ec9e268125eda82664be5fecfa3841df1ca0e9a9ec6e6c719153eb6a44aeb2675e4f3d013d11e51edbd492bacbc8bf8656bd626d108a	\\x794ac3266e873423e8295af80eeb3f36c6d6df8f4e57ce5495875ef52b2ead63fdbe8e1810fddeff996118bb3f9d58ab8698c50cc4675b2763b44794a474f9a00e8cdece7f586627b1c905a04dc61e4165ce3268deb0dcdedb4d9b0e80414fa3ddac03f691161cdf7445c4beaf72394cfdd96789a519a6a998f7ce79dd381763
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	2	\\xe5d363effc8515ebac851b8595b5f6524c6bd72d929eae91618c6afba69e12b26e8543c10ec55f1e8f7b80c259a171b10d98b7f9f2ba4d1221eff2cd9c28a50e	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\xa4ebd6b85fa5150c4f43edb97a706a389f6832f2da4ffe55d3bb52690aa669340f3772165a752a000a7bd010f5df257d849846407bb952a67c5d26a5fe8630c90d6accda7e99acaa513a7a1d7c75a9f519e9f14ee19afd98c98806eb48171df68d97862c7689f760b566eb0517d99bed4297657f796bf9472137f0c52b58ec54	\\xc88c70b05f6f8cff8c173bcf1b223478c51c4497ba93c2472fe4dc76d00689cb4951a8ceca4d00944d8bde9cf2aac94db5e129c6e5be44a1a7ff8a864b3bd0d9	\\x66102cd4f231135457f477d78f2a4237b8c2a1f1dbefa15185bd89fc7eedc878217512d2c927400fa405a84a5d3f5327b8f2f083a505ed15ed5cb50ac7b5a998f45a309e0439f0ea5da2899b22ae45b5078295cfadf9c41bd801282b72d74490e31828e5d82bba5a8ef7d37eba3bc46b47cd42c0d5cff9215792ed689756cac1
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	3	\\x95bd7c78e505e0f035256c88a0cb82b57b2b0f5b1a910f5c89ee538eb25b24ab0814781321c29494fec061c6b069919a245ba868ddc900baf720de49875ac507	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\xc5c2680371529b827e0c36f3f7999be4ad4b722ca0c64bf008bbab9fdfbc8dda025aa6ffb64f40fea79d628e197c147f02a93d489061b765ad03df46a89729b41376bd9bbb1481b94edf2186dfb4d6a46d4e931833e659ae73c5a42b6aa38e3c1b150ec54fd4d382eb33faecdc105f596e15f9564e369300181a157b50738118	\\x9e88a7e41f31c1048782955bde254a663e55c6764ea9b9354918221c2c6053ec2b6832fb72a80435c0b2055d754dde03ee7dac4e3251037150180d02f363364f	\\x0ea5f18220402f4c3b1f1ac361a210490b0b8c9093f24b7192a6c53d6cda08482f39a58f6984d3d8f9926effa1c077f1556943d10d4aeb32c92b8ab6eab009cdd2cc0bfd473b6c1e421337abc15faf531ac8ff82ce5b341830289c750ab67b3b1a2b9fad44c980b248a22920070c5ce2b0595cca031286a4d86d75192cf8b8da
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	4	\\xc92ad8dccfd74b064cf8e0c878b07a64c9d569a59b14d020e44bf452686456cce2d278749387c79b8fd8d475bf7521c2f3026a54c3df116fae5873b70cb26601	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x6e5cac4b0e48806e94acab58742a2f32a297648c1a3a52bca43f78a155657e24814a1da3f9d8b77722c5bf5225a9bd8c9b035d8d2094b67b5f726640447c6652b19a6f0aa0616a068a5b0255980a099749867a0db1bc649807ea461209231db08f7fd5797f8adb9f29f23a072202be8370acb9f859d865622805654d1fc4a5ae	\\x33b42711b523febdb144fd930a49b050ed9108da4f653c9d7ff79c6fa3a77942449f6abdaa9ec0f43f8b2ee892082dec6e8fd86d244be5cc7504ae7b625420e3	\\x59acac73f58980d9730dbcb7401e57a1ca22a10a46adc2c4b59cb7a4dc3e7bbd0e9761315a23df78ed3ec7ac1709e7d4330c785fcfa10df3ba0b374881eab0a6f7bb85cfeb7fdc5060472a931ffbe6646cb6c48e5c77e5bd0a950051e4914af78111247dc419be12a62aac4384433b8ed0f04d5877e3ddb29cb068c37adc0ed4
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	5	\\xbb38496d1d1a79d3aacdbbf888ef6dc053531eff1bbd01bfbf1c3589578de6cc2d0e0da06032ee6967b969f975499acb111f62ea52df767dbc7f6069d65dd001	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x8245e8ebed90310ab7728d08e80bef8bb1937739b46aaa3212ac8147dc354edeac4c29f3022f74a4427cc692f5ad08eaf22052e969ad76c0f40eb2509aa01b25485522faac96766c774afbd4cfc9c579bc23939bab896f2ff35c0a42b3ef36f420b2866bcaa0aa8a7c395ad7bc36eec9c2ee68c41c9cb47c102a2c0c51f0bff8	\\xf98f4b7afe27fdd8a572159413cfff527f6249d8731feb2f81811572cd3719f4daf4e671fee2bf180d1a15a203a6c5fe4c8d6f3a9e00d2f074e44efe3b4c44b8	\\x583c50c1d8e486a47b3feac3c2a4977c263a6a4d5b515099c20e4747e819ea23faf0488a3a19efeb06cf0544e237a0c61b0ac2d4fde3f9df204a255b16171a2166b68b059fb43030ededfe7ae635bcfd5e77feee6d53bfb6e829da96bb9e750a15c14f3eba8c03b7f51809b1ccd80f249bf1aee2565e83063a0dc8430e1985fb
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	6	\\xacf163dd694450addc765dfee90db4b3278923f396e9e659b52c0d28ea5b714b90782932a671581551b71392df2a9006135f392052e1bd4516dccc59ccfa1105	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x7ee1c4e887a71495ea8536079562dda9c0c6b408d6b66a602b1aedabe967ffd538a5e8b35d023aadaec3ee01c9b717314beaddc171b4ea719792f9f12bf5ca61a1006a1d28deefc550c45a2d4ef7215654c0edd7ca299ba2e43a0c0f92d669c7e578f69252d2c0177a4febfa31ca210d67a4d3919c90e3827ce4a36c8fa4bad9	\\xb697df52aad42496994e2737f2980617856867883392fa8dcf71eea3a69896ae3385d84bf5e32226ae51553fbb5cffdbf57cfa6764d6d6918ec978c9f4971a82	\\x14fb3bb757d2929f96c399b859ad0feed63f9506d5ce34fd8965916e5541a60577bae519b15292287355368d3ddb5d071764509881ada194365e2443d6bed62d6d4383749d83451343362fe7c81019fde94051e2d772e0d9160e4a1529b039a9faa5a107a0d9434ccb3d176666a1df0dfda60d208cf1ac518363dfbc09418fc7
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	7	\\xcb38875258c9294ee196d9f5bdcb51a737fd2de505a46f8bcfecb181569f96a9c08bb39b1ee6f0233dc26a461ec017e1eb741a0a9d538a502bc0c4a3e2383108	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\xca95ab52a78d3a587584a3d9e04cbd4c89d2ea8ba4ed55147cdcb44770750cc62e832ef8446869652ab1ed38841ac0bc0c226accd2790af562a00905534b76c9040a5cc93cf971e2f3954429aa4a1d726885c0990c98e20a3e63aba7aa0a4925397614f59ad63d9b531a12858e39b2940c6469b4ba7f5b34d4ac77f2e1edf4	\\xe2d21bfbb014870b62172458af49b6b8e6a36af38c79afbfd9fad9d66420b3d8af2e98c5b6c1a16fd49aca7b74bbfdb4ccce32d879d79f2a579afec89b627317	\\xa1261c9ca930dfe1201760be1ca6cdf2cfccfc5199c3248771a123a3dc1b29e9df520b037ffbd8496840faba4f170b636a068d89639d3595ddd3ea1724fbea8c65de7b24a05936dcc871d22608afeae08bfa20b0745ec6e3939ae1e76e852faa9f1b2872fa4e49777ec2d5c108f15884f9de7fbd50cecc0a9ffcbf35e59f27ff
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	8	\\x97f293befcafecd875f4c154785c02cc097a0b703cb61aa99408d4495091c5862be75327197dccdd56c48067e444c19da0a9a19c1377d632be95920f8ee19901	\\x7f1749df7f2033f92e5a5a3ff9117934b7ac5d5757da9424b0d46d4286359678d67fca8b3792ad086bf23bae26833ed5ca3715373ab56ada7aa69db79df5c3fe	\\x7830fdaddbf1548106a2e99e8910352cc4f1fac6737bfa10b8b4b60281f99cdc4294fba9140e85f3d11754a111023a109583e9a6c08a1d3721595084c59352f0b4a9d91cfebc1a81f5565daf28f15d11f8961157683d5c7585531a096152ccaa60087b52ede2f4498c23d0930062927f82822d32479107e7b3ee8e40b26964c7	\\x5def2ae83577b46954abe9fccec8930c9d9f0d825bc545b224f990545f9b6fb1c38d559677ea9252ca3daeeac5963dc79fc860a240b7b3a7b9af8ed47a679b14	\\x4a462c82e05a6151a1d986f8d38edbb72af73a049c4c2c76c44850e7182e8e37ae3756dad822d78e07394f34d030b2e493ddf0b5df2736ccb3a0197be412299823372f13db485c047a756add7b8df946d75d9d7323a4b7a02eb15e60705f9bbade4b4372143b44ed5ec072d9520112df00c84079fe40f2013dbef62e31d01fec
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	9	\\x28c07b28799f691cf5aa7121d9f8bdce5df35b00dfb678a1ad96f7da7a495b9f993dcf953d2cc8a458169f743254d671eb875c5cfe9f1af9f9a93ad487407008	\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\x8771d525e4929d7be8e026073dc4b9bb1b1bb1e05bdcfb072ae2c7e0d919f4ee37348042e12a1b050e95506bbbc08c67ee3f4af245acac8611e4785208ef07c2b288c11f30c5f5f17171d1e21cd081b62ebf329754058432af7b8f9981968193ddd295aa9eba357ca06cf3a33d52debe63abb8ffa39c4dd4820ce05d07a0961d	\\xab7cf97af456270d04840d41e1420a3d79ac47efb841554badbb32094dbe8f2c059826449360f79195a8f6cdfb1b0c76b1dcc4a3b0284302861f4591d871332a	\\xc9e95d0d1d54ee4acc6b46403c02b165e3be7331006ae440b2d2dfd7ef3a3d0dfb3bfeb1b9f55fd7d3fb1a89441bf445fc9826770f1ad9eda2e9b1e3cfa2e2e8a61372c5fe42cb4938bb60f63eb519edd1ac793326640292fa5373b19d20b3db8ff702665244a54c8c23e8a6ca07320515f8729863c9927d7a3774c17c63cf77
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	10	\\x5ad43c0ccde2c664e79cfbf76553df07f2e52462f6f83c7fdb24c3f0926916a6b67e5b0f4183d7d15e8e05d670090500302c0b1c912f11c3e8fa83c38677fb05	\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\x579db5e78f4e053806b6d8ca301acf0ff90a049a7c57402dd501e63946276c93ab41b38ca042e0ae4646c241899d991e800416bf80665c00587ab09e900761f784a18b157ed41bb4638ff92880dd9e2a6cd041add28f4ca0451ce5f4718505035766c6948d2af25d000dc7db2fa90291b7e2c63fc10d79f5d531cb928794b010	\\x5723f688454576fab541a9216c6ce1292954b3da870bd8f1f1547c622bdb7913ec1d6580a4fc0a6f929ecddc744f82f367aea9976682ebe0342ddf9eb22106de	\\x8640e9a747b7db3b62b7955e690624552aaa41a7c89f3e937d7ea6c649f3cffe37f83a74e6aeb277017c9e06c0eda2904e1e280043e96c2d9c8b504a50f44b2df7dba382956cc08b897b245fb31db371387f1610bd3c80b422e2508a3b234252d3de37b5a597e089102af07dc9392a5d3bb04c3d31e9f2efc29317e95997cc5a
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	11	\\x965f589b30e912fbd1f6f2887cec7f6a37701a7bfcf84d9ba70350d126efa35b1b721dcfc353f5777125a0b28e256b9645a153ba7b2c542054ba5fc345baec0c	\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\x2a67d2eda9b1b84392d22bc220e1c1be939d8ab64176bd88813e63e1f3cb9f2f7c9049628a985fbf89920241c52adcf2d6c94e1f0a77b138145b0acca646f979b9437f305ceca4044e09d30f22f677a62be9fdbac0791f68482b59a6ffab0326595a3ce6676b905d8eb23ad0caa78d67ef60d57eaf2f8a158fa78d2008d07ad5	\\x361c3090eb3b4ed5d74b8c7c939fc95b5b7c35e3630a1058e1a58a99c4e3120d29ffbb1d426bd83958aef562b457579e0578406a64621fa596487fd44e3e9eed	\\x4ef120adad7e3212425a4f13fbceb610af2bf9ff373192c25e2d6ebd7402b1f9349d675c8691bac38d2391e0e4e8f42b9f001619fd86590084d52a822f197359384b62f18b34506588f9e1ebeaf0c7debc8d950655fc5fc0e4b0ed06125eae63a37e9caba20c2216fa9a3de8ba9235780950741d69b2cec5a27229c14f6e2022
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	0	\\x53a6f7525578adba5deb77351745a19c77953ee2495bfe1d1f34298ef3436e7f873be770f6b668d757b499e2153e248768e8a663cfd74395f49b608f423a9c0d	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x1f1807b89a9acd9dcfe852bae1ff6db0cfa5b0ec6c80c04896a5e018300fc6d469fe4ddce79f0b77159606b048f46fae222d64f742a28768fa6bef7242cb850fb4c3e7f81095e9ef11111f75e0fa864c520f2a22af5326aa9d079b8913ebd22518968e61257e1df2dfb6d8a6d9570ce5d97bfa8bfff2d9612905bf77b52bc9a84626b01f5f27160b3dedb2dc5dd3cefd2afb3a3b2897c20f15c4c13bae0b40c55a56c3b3e361253019db2f5c5c82491c59ef875eb62802d5a68202be6c0865e7b5317f624932f687fc9d7dc99f103ef7906d87cf114dad387e5def4cd12180f4f8159b857fdd8c27cb4c8c53ffd77a3983eca367f65b736027e1fd72c73fadd7	\\xab2c69696fb2382100cd3dc3f67a3fcbb65eb45df22cf50bab30f6cd3777f431aaa174ea9b0337c447dd67b23f5fe8f3216dd8636e5268efa47a7361444c88ea	\\x3ab00ba7a3c4c84eeece5d7a14beb177a0589f830e9b2293256aedddf775a10bc1422931727c5940a2acfe8a596661d352d56a291c7636ea011e5119fd05789ba8595b2b608dbc8d53cb427bfa85a0eedac49c39db84d791da4d72012b5a0d19cbc6198b247a73adbf2a544783600395f9e0f25faf78b415280afe655e6285a3f82ae6472bc3c994b27e1561072500bf65fc9aa8b4ea90f66fc5990fe535b427aade933936b2e8dbfa38d6e0261f3f5198cd0afd22f4118b0a4cf77ab2577a6fd34c19430c7a147a801f60fd38b833d2ee9f071b5c6e4f7276d77f45daf0a1a66eca3927e693640965b1a79eb4f7731ae8fd3e5d36e8c631fc600bf317ff468c
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	1	\\x371335ef38d97b73042c2dc656d34e5d0d416154838a503d66a2daf1791c82b130889809ec3b0cbc40417690d07fd8b41ff754139ba9c9e8c84d172258b33004	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\xd3f5a10d829522cd19fc83f462b2999312122acb59fac2da00110645827be939ada4eb4a51af509f6b7e0cdeac01eefbeb24aca7aafd7ed6237c97994c04b82d0cc8991a531998e0fff8cd1310f9481842616c0be35702568585261f17c75014c4077e439a8c19a6fd256c43d27fb226e065e2cde55846136b8e13946b89666b876364adba49d4a22947d438c40cef662be3dd2f24b6cdf0f5b119c6ef8cabc450f95266eedfff3c83f6af96e6382622db5a660da3029f5b98c6830348f1a0664ac741fc711316e2d2d87a79427f8254320242e07e89161d81f2d4b5bd9e32e5dd23b6a8cb2ecab25a55b630f5bbc7004fad9be8d421cb54167014cbec8ec316	\\x8406d4566067f679aa9ef346855a8577b2690dd0342dffe8911b6419890b9936541d56dcdbdf308fc712db037e579d4244e3d04daed505c8f99d600d334e37e6	\\x268445af33e672f8fa4b1ecc72548f23a815882a5a93b2be7f9a118eab5ae5164145a3ae9b5fab216a8be4af408f12f051b7a8b2de2140e905cca384ef12a9d945952a195b3366805e26a7dea78ba561addde400841c74cafe3448db4511725f11670564c5053e8e85a10d7f852fa005a9d4f191f374956fac7d1c594dbf3c0f003937bcb7e6e4555c110a81d6e29c527a4b839b8a32a685a9badd0d6b40c62f2caa23386fe35c25f25e1c2e4993ccde80bfac90e6071fd0a7f303174f333e9e3604090f3754910efabda9ed786d186ecfb934993dd77c64f4d72b1750e09ca6439e1f520df6402813ec5b866aa83d46eb0356093136cb3f57753bf0b9289f62
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	2	\\x362a9a20844e454a0fc9062289bc478c3beff6538c000ed3adaa4127b7e878deec7ca9c77c1ade56a3deb5eaa97be1f3b9858612c1a2551f25a87e6a28459e0c	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x19f30be726726f1638c9b89529e453dcc6ee3107355789939b0beddb4456d6267700a6e819e8f490ef73e4807a921798e8d4a6942283a568edeb09d7853fb5f0c9c9bbbb4835df31d36a454da9824dcea80ab33c017150511e52073ced14ec49c8f7789102f2af8676ed443df189fb6f5b8e73a6d8efa7da9ec72fd84b9411b689e03fa647ee90cfdba377b81ed4e778cd46a13eff27a4b3509986174b80b5ef04abf5ead4d5220504dd7afc1a1c9120b472c1077f082a260fed9b5f67a0d7bee086defd30d745ee3934bd3fd3235723ca5e9520af0e65bc7d4a4dbca8e2680c625807afa6990b235d423f321ec64a05de77a5b9abd0b20e6eb485f403705792	\\xc3c0b807d039a1d4e344642d2a975e840b933487ea9b50d6494b5d74cca65e9c2d14f203ac2cd50282aed3b06e5b372cf7a7463d2267cfffc2e2b1e90c7118a6	\\xdb633de0bf4fc1e3f2778aff868919f269857d0c2f9feff4ba342a8c1004e5e9a0f29a5817c7755f3118fc394177ee0d7cf52a5c9bdf561f38c69a77ff62f23a3a4adf8035d05d41b72860aefd10ab14889f87ebc0a710d7eb60306a60d3ac31091b77c57b8a3b0ed9d8cba24f52660c90c151dc58ebe94025b0cb717d1565a52a88a6525babac36d608335192f747d87f6348eedd8676824f599d4a46bf70e92173294f5eea4ddc48591eb89deeaf38c629ab5aac77a725de28ee9829f227610b4cc3f0ca06fc61ff5737a4567ad556bf0745f2922a1c54dd823f2eb2d5b2fbd09b8e1e738440418ebcb0f1eb51a33e9f9d28833c53a0baad128ff2abc8fcc8
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	3	\\x4119ced37056b0de05ff5bdbcff621bd9a5acf9329a6aae9613bc84f8680767191c935cfbb568cb95f9c79e939b21a8cc509cf760462b96a0fad0ca5b7edbc04	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x57e6b0c6bb6896570069f7090ffebf89d62a34096464481d00a1e59b98ca420458134471c93445fbc774bb71b59fd39dbe0c5d8deebf5689b6789bc377a2facc6fe24aa767d07c2d3e918f7d8c24dd41b79e5eeb876a7e81f3634cc7c38e4e3522a9911e1486f703325ec9a8da51cac3d10341312f05efe97785d76d147e3e071c0a7f587dc607980d62687598b322f7f1cd6ea39d32d91e70e48404789755143b3d7e7529dfe6622fadf5419022b48d53742875fc812c1d5261fc02e8ea69b7567d8445b8a932cd0d24ade68dd91bc957912213981f8e8e2cec3c28b5114ce8de2949f0e8273eb9dbd2010f79a728088a784affc29c50abefdad816955381c6	\\x953fc67b1b484fee9538b57932b9f14837262235ef202751de5987669df27c31ae6bfa9f7ab79f8a35074a975b2986f9d2649077af075e435a29cdbe7ad90f97	\\x436b9e94484b36eaf6b733f1f4f2947941da0b319271300586ec02a6c35550a820e2c9daba0b3649f74aa1ef080708f3238f0fb2ca15f4a762a12f61296886fe14d6e2e1a72cf3615822d5e4500cf9859baf0ebf1f0027bdbe2d893d9baed2cd28a3ac84a252348b7e52ee0a6f132cbbffe9bf0de4013773ad553cea139bf116c0fa0cc7610741120b6f18f288b23985e9faffd829fdbe739aa06bd6976639a5e085a22446eee7d98343ff9402c8dd72c52b10db1ef7a5c86b6b73afe71082edaed4d8575c4f50f1d8ed1f99551f5912cb3dd05ed91b2610dcaf65172fa091ea7b49039ee12e2a8c2ed62c2c097935a1c90e15d041e8d230bf39073b188abb65
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	4	\\x55ad17639332de18700a2b670e5dad0589f29404103cb5163cbc105528cfb82799d67b2ad941d80962eaa7856e3695edf6cab28fc9cd7b9300c778f6a961df04	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x91da6326fa9c5efe992f8c7d807177fe464b7edc247f3ae78ee3629f61755af4e370535ad2b60dd66eedcf76e262f59f27cac267d64c4b7978674eaedec95ae637f9cd918e8c2237abd4ee29d3e0a4d5442f488599aa56489ceb4519f7232a91b49bd7c6f35d9c328d677ef45c194da3a34d2faffe61e07f3ef14d076c8c088c9d5777fb4698efd7d70e28ee1fd19c22f4aa078622aa4632182b3f556bcaab63ca740809e8f0c1205ed21897b870a49f1485ded8238d1b969d96385c0d48a243383107f829d4d40dd76a780e0ddcecb226e6a6660725cf822a1dde0c16f2ce07b58785820c3be10383b3ee014c80b81c63690f4ceba3b249c7214acc581d066c	\\xc6417a65789b64630e1f9298b67698608d1be14019df4f06be73c342c96e2f91c6129b64f9887bfce3fca30f1d8b7c1c19ce302f5458b9fccb0b39753779f782	\\x3a2bb7356333a9903e1f1cd46936eabe6f25a11fbf56e2e153f8a1c41a18944c78ea5202cf9351651e82647ade3c926d5bee177124a34fc00b38323c2fc7a043b62528355810f5814f6b990ee4f16cf33965047e577fe9db77fd20d199ea0989da6f9cfcc5436219e71f5c4a6d8f60fa01b32159e24c3b49c71d6bf07f223e51e9e3a0035cfffff0a5928fbdc4179810893b17cf654a5b82b8edcc466588402a197a2959dfa40fd69f03cc6a3c0892d8bb75cce3aa05b0a906d04ec6be657439e750373f9f1080e174dc9b215df1945b19398ea8ca077a57e7bc10fc6286d214799b7a83e843a36346d340a0c47caf48cc61c35f88ad854912fced88eaaadbb7
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	5	\\xea792ede870a12621f594314e274f07150e6788559929de7de7d8169e75cf69f7204e6cbd8054e221b11eb2666ac63e6a3584a81feef99c28be70d570775250f	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\x83ab4f307610060a1c81c4b74cc69a4073017cd0b599f89cee9218900be96a971f43b095d2a05c03975573ad52498767bca75f15c7b58a6e49d2fc9489d40c0ed2dffc51d0751a1b4f0ff2ae7675308963bf6570dfc3ff14e6a5a8bc1f5de113bb228bdc10d7d31bd78d32824fa82cc43b55aa89927595fd8d69bc4f0ba0d93627ec139be1d9e85b08ec426c9023e34d63e675c3848d19b86bc2593ae5c7819e7e727854b9f2b434a601a78b3c2e88161f526a9c1ab41d38dc31869a72b7d088f0723eba93d652567510962d0b4d14d63b2a59f1d148bf5ec3212d96c6c50d7d7c78487504b58c69ea3f9d5cb0ecc32a3a66184176624120446c7e87cd1d0b94	\\x2ee3482d4ce1c97a5621dff114c2e52746a13e5c72a85a5e48d2ffecc33c86ec6b0ce9788a579e12ff825007d2f56acf5e6e5aa5ce0e2ec8ff31d1d0f532eb33	\\x58d9e0f411b619d277f8b71196c9be30ea9da4166302b9d8869e4199122e9464852dde58bbc3021afb0caa86a359d05888ea4eb54b83f3a6ac83f9cb5e39144e1c83f768ac768314f6b7d5e836a0f214c019c0286674681c9faf5d2886c5ec6c533835f704b76115a9f7213fb838573cb24083f8b0447e5c7b45faf0d35ea4183eee899187e9c9ff8edc2d59a6736950a0e40581fe8c4ea22328f610229b431d17a8317c10f4125f5cf36c7dd4edb7e440e59a584d077db1a2faae5bc1a384ea22d7a585a424e54712799be149f703ac5cf5ae115337a8808a04d3902b25fbe7da5bb404beeb3da63d21e75191f88fa1cfe64c81b7cde7697836877082ba3e95
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	6	\\xa02bfeaa2d5a66c44e6f233365f760f53018cc1d96499a235a90e9c1437781dfcd6768cdfb502797ce4006666781933d687af7ff85d7226e7d8db6da73199a0b	\\xb09b6217d72bdb8f393332f676b9c85c2e246a6685c6f4ee8e96384b23ca29e89e587f782d24625001c7cd6cea13e85fdcc9591452f43c6d717d24297dd2dec6	\\xd1014baba95c600cf77ac40559b28b03bbd579283989af84c6b3adeb7bef11887b19bab7c5eb174ffddce3fc0ab486c307d6ee6ed82d5954cf74ac1419cbe454d65a92302fdcfabab8937f021aab344ac6644d61fa099dd1a807a09600c8e3da34eb95add3135492f6345a50f4c298491add7b9fe0464ba7c439619423e619bd1dbfbbcf391b69db3cc4881e42b2cc3975e925dfbb33a118fe1ae46ffef5fe034e6adbaddad4b8ebc12235f1909275208afab5bcabe2c8af65622b3f74053c53b6aa67f2b6ea0a6b5eec1c70ddc6278d873338eecc44318160dfed19bba0df973db28b18f4ae55c0234b553d67b74231c6e289a1b8c92d242838e7e41512f90e	\\x3e8065c139bf41a32fd187274c4af1bd718cb0c016f35d527a4716ddc2b3c3e88cea7924653c09dd6c62205e5e582cf96069e14bc6d2004dfda9d03d750a3547	\\xef6f6482550a54bcac032e78e3ff441bc10bd903d139f9db8c134c9267056c8b8a1ca54d6c5c42129ce2718789628503ecb0f3b7397f979601c445b72c6c040a39fa4aceccec75faac68ef74ef9788cc28c525507db6b51b36db066e183b28616fa31447e61f6c0be44b6ab44ad551496a7ee6c0b9c3768b2982abaf4a88200739dc1964c9b05dc007ca4cb698ab2ecd0d18d5237eece654e9081612fbd5c85056226f6fa036d3d2446e04f4dca68324be91d92476cbed46a73386972841e0ba2519e2ae27d93120b11f2a8e72c41cf250f12efe03c914034f92cdd2df0a0974b809ec3cd166c8baafe527c811cc72b1db912a3e436abe61aa387646b817eefa
\\xfcc21691669f322732ca1b3229921c06ad7de9ac8bbeb67cf83424a2380ad26f70552b222c21be55287447acba12746af988ed5bbddff7331589c2a3376879ec	0	\\x6e35b295208cceeb9c6c199b1f1ae52fda3e4ccab3543b5bf8b506fcc8756b1bc0073e437ea2851f66e63894512ec5916eab0a158c0932dbb20a45678681720d	\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\x6536da6ceb5cec792ae76b6acb5710a99ecaf1190c097bdd5a1e1af087c2442e7e9e962c572150a055bc2cb781d20fb1bf6f1e9ca216a1bf2ccca468bd39ee5c6416ca22101e47e4176e3409b714cc356663c19ae637780d676b6b308f1fe463719d803c85236d465e3994c16dbe680fcdbbb6a7755f7761db0f32ea1edfc66a	\\x4107b1e138fb50ea7bdaac15afeee44167327b376467af5522796a454868a29ce6db869eb2cbeddaa3077f8d15d6caa58fe436a7f481813d734073863714c232	\\x51bf9d87d5bdda5de0751041ae9a2ddc14988105bd394e4180f0a86b52d4f8df1ac7e1f6225d9fb20c2445396ad6f0152ec5c5251e35e20714ff13e2c0df5ecaef3060c2da1adcb0c8255692a9e8190f69195b83a702fbeeec934521b3402bf7bbdd8c8b0ac30ce97301195ce6ae970aeceb686783a3ae8f1b33f43fbcfad956
\\xfcc21691669f322732ca1b3229921c06ad7de9ac8bbeb67cf83424a2380ad26f70552b222c21be55287447acba12746af988ed5bbddff7331589c2a3376879ec	1	\\x3bc4b3e1be4d49b66bf2094752ccc521082565f02dd53c7469d452d22cd9dd934417cd35fa12efe3e75ad826862bef6a8da065d551d6a06258bfba8c39bef502	\\xf3b15f353353c828067a48d0cb5cc98b82fd0fe9f0403e675cbd25a702f0601c7254a5c1f12aa67841d9b347bed3720680b3fe8f48b3a3219ec5df26a55f41c6	\\xb2a698d8cf72b3d4b36ffe39fc03540e28a7ecaf645b59d69d4e16a7908c971eb408cb1789fce47071bb3ec8bd94df9b71ef97c79477a733df1e51bcb71f0aa2558622e8aa3ef3df62f530e30b1e308f6bffe691aeac1ba43b63bb46d8b4aea9aa1567184c9ed7fa25c95bef29379978577a73aa3ce6aac40402de46cb8f585f	\\x13e40e2ba06c26a3ead37ec342533624f82ac4a6ac517a415c77d40a788dedf478ac1f3179c08e5f45107f2cf34b0a39169f203671d774065bdb51f21341fcd5	\\xba1ca7ba386e938215ab43af0a60b8ff2ea78d5d4e63c182441d99d370f200cf66388dc237258a8e6f2ce3b5384787d24e3609c84a83fa6af431edb673d6df2138179c5cd66e32f4246438b02998d1e1c63c108159e07eeaecc9e11871178bd72525ae901b66d5cdac22791bf8ab9403957733ae335a4b4db1865ed9dcad37a5
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x31cced9afea62ba3578d70d72b0fb97669a4e3337ae4e20df97c4754dd7e9c279fa14b0eebe7041289b281d3d7604e7c53b6e7eba614d8a29cab3a559707b785	\\xd918c54605c7e14648b928b526ed8038148c15af15e293a1c5ba6d687ee91056	\\x9a86bcdbb3d50a280f8de9623bd82135a36799d7de417d8a7021f5cbb9e2ce71b2c8c52445efa89e81e1c8c7b440601719b6508e9db637d902a873fd4ab2bf1a
\\x9299f109ba5bbfb69085914e2112d4857a48d4a1f87bac2dc3f161e1e160566f3b1908b1102c1f58619f812c7cccd8efe7cf76056a55ddcb9bb598f1f49cea3f	\\x14df49a28a7c6c38f3e7d5d6185105b7382b2a8f996bf0038d1442ce331f834c	\\x972486fadf7f64314b0b46238bb42920083c2b669c311ac887ff2e596b6096ff50b70e22dfc1b04412eb3422f03b81fe16816c1ee53c1585d355d5d4e9bb81d7
\\xfcc21691669f322732ca1b3229921c06ad7de9ac8bbeb67cf83424a2380ad26f70552b222c21be55287447acba12746af988ed5bbddff7331589c2a3376879ec	\\x83f68c7d166403c62d94e094e08cbb0a9aacc0862d230ccf972846a5b99a6a18	\\xf64291cb3a36b748230f9eb097439b0138e4854bd33d56da070b2321ed20bc8eb73263a72f5f5e269b9c6e8271e6e74a26cffc5e5c3dea208cf8367b796b39dd
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
\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	payto://x-taler-bank/localhost/testuser-JjVD1AYx	0	0	1587666429000000	1805999230000000
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
1	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	2	8	0	payto://x-taler-bank/localhost/testuser-JjVD1AYx	exchange-account-1	1585247225000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xe2a5976be0ff4d8fcbc4158806046c4d13e5451be8a85b16e0f733a349f12f021dbdd7fdab0d3c97cd80e2a0962321f44ff82d5cacf8bf7a2ef3d0e57839fef7	\\xb2b398d560e595d6d879842cd209cc84c924a57538ffe918aa6f3107492495740d2dadd63f34109c3a19caa665eabb781359cac5c496e56a36bfc6926d3a45a8	\\x88d94c7ef6b9fdbe123821244ccc8cc7d5bf4f4f3f88341a7d0bdd5bab04fb0f2e06e2fbebca41eb8d6d926f0da55fab4bbe32cb9bd39e05ba305106dd31002547e62637030349da5ab8f468de6e232856f946f79db511649d469c08b8f014e7c4503a9fcd74247c15e85ab5189b537060900e20f641c6390e32b9443d15f8cf	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xc6dcafdc44aa3c23118876a2f1a1cb240fa57a3510c2c650f48764f680f2273b342a73683b80bd6011b4d15688cda9866a17747109a20268092d1e853ce52d0d	1585247226000000	5	1000000
2	\\x729dbcc6b62e8c06af71732625ab60fc87ff2b8c8f67eec84c2fc091ff96acab9d6e46d9daec54cdbdcfed0c971487d232c070707ba45dc842318f4d82f759d2	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x5503753f883cb430a8f127898411600b0446a87d3f9b0f590d69530bb648e214130d2a02228fd0e380cfa4c7787948d54cbb64070ece94ff077065309e3f164168481ff29375ac141765db17149e12b269f8b9b8a3f6b527b87c8bc8537ae0d36ad7b7c085365d3c69a59f5fd0afddbedfc0beb226fe008534e108d391cf0f16	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x2d6cf195d1f05247afb9849c499b6dec127d5a97fc1d91f1992309046d6cf4419230af94de47b49555f909d6cc65f23214cdb537512a8fabb5b6944e1c503f02	1585247226000000	0	11000000
3	\\x2f445f26fdeed3207cff9fc26c0da8cb334ae9cffa6c504e6113e01ca870450f9427e43e7fef653f161562c68b49cc032425247db5ec0beab3c48f5ea2afed4a	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x5dfaa41d01999757ba3c2989dcd95d32e90a55573f12ffb1b7482edb149cc71a068cdd8ac8f124c932be077ccc1a1d5884a8a3696c32d0771205b4088c6b7f7aa972b6e03352587acb341e9d5cfa7a6a8dde24a0d19b8f4f3a256d623a7403c105c4f8726d65b5428f141ee49566100f5ada7d3853a3d8ab91ce1ae586106f1d	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xf8f3cf5095af2246a7465ea7f9b42f1cca5168dc5b071a5f72d9e0b7218101fde22ef841fba2021ead35833da8232dbb755a53e5e83c9547bbbc831d3589dd07	1585247226000000	0	11000000
4	\\xb461405da8de1da0bbed12352af73b58860dd9222b0ee43d6bd410e10c830c140df671286b8818abc1664cc260de8957b40dc5085f44f3f65facce7c949f44fd	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x83dbe0e184f2445941d57c8ead85ab4d22f86db1cee9c15c9958772b9ac870b32064e82ca7db7a8cfcb18f95d0656fffe8b2d2ec185cef483fd830868c11f1f52563b32f3cd50ff7a9401a41d13b5850ef79fee7f8031a45c692c0a843c1c4ed1dbd41cc0bb12efd29fa5755569fe359fcf25d8f134a9c5192d81114ab421bbe	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xa75434524d67b0316a1c51ebcd99cfaaabb91a37b3848ac47b063d6653afa13fe1aed35f15b17ec0a7c29b56144588440d234ec7e4650f93f3db57960fba4400	1585247226000000	0	2000000
5	\\xe4c580166cc482aeed98e877c5c4b6d288c458c78ffdea5eff38729a2412bf787c7a462e5705103920288717ef27a3dbabd1c1c07ad7ea425e25ed7763dcc1f0	\\xe0726684567b8f6e972ae98a1c743d83344292e41f48d2696272bbe7d7cf28e4fe4ca576cefee21dcf4d05dc1927dbed383bd6383af4f6919c6185cb86c29fc2	\\x84869b61fd17f94c8a23e40424b1247e94a4cf5208962106a63db062be1ce1f54dd86e1f1a7dff56a03ad1a769abb4ca34844dd9593208d053cbe656fe64e5e790c9db67012988cafe65a3fcaa0a844720b9b13b26e0e977cb18cb3753bae29f43b5e2185116a40644dbc83b8408c32a1fc67e4f18ca2037fac27909c370ba6d	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x4d675f9bd9890c61184e3676c30d16de23bf4c6c7e72b101608e22903b1a6768de0b2286f3af8e8ff31532fbed5959394e7bb88cba6cca884390818d13826604	1585247226000000	2	3000000
6	\\xfbe66b1b4843b2790ccff3d22d3454aa433919d967a231523f0178503914c79ebed229e74519c0a201d03384c181b8e30aeaee8be86b7fd109febb06f6c8dcbf	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x3321faadd56c35f36d7398a8f77ee4a2969a499e3c90a41e1c91d6512f2c89156ea535c7bda92fa6c43edbce360d9d26bed704f0a4a363e6390f06c36d55b47c13d0f9f45d10d87ee2006068ca2d7ba8ca87cc003c1c95fc0d2947240e0d6d0ed041501842dd54eab84a7fa232dda60bdbaff7c31e1ed01ed8210d99e8d8b402	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xb91d7e405e3c4d8a87c57d6e7abc2b01906cb1bbe72ffd7b30beb3e3c34ba9a76adeaaf18cf15be12a47745ac9d9bf91b2c0cab180e857af7f3c0a4419a2f208	1585247226000000	0	11000000
7	\\xb8406db7a5f0ef73155b7c696136e3867c0088b166d904cbb511f431be02ef0d7f9d5965928954582a15ddc734953341e2286df1a004a3f08b57bbbd1b9cafef	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x1ecc94b5f450b885c41f612509ca1babcab67e46d291e94d22ad28d24dfe258b896c25311cc9d51fc40e83c87c7071f539a27a8a6c3e02f61945c199a6d21e0c431c232802d23ba10bdf3516097da8a236471748115dd4ba468642ff750746b06890c1a3050276a53568b31b919659c268751b73a2ecec37489b451c34530cd4	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xefa63a164c772c419d203f6aa9137e571e922666d43634906a782c14423c039fbffe10251eb683a78c299d43c8571b9a6829978bfab1386125bbb688eed8d609	1585247226000000	0	11000000
8	\\x80f9cd293cccb47979a32a7a48ca65db99e7931c98b48183fca8c116a907c703677270a1b2dc52f3ce32a4145e02a40041beaebfddc97c5e14d0c525d1cdba20	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x7f003d48d5382176d0d1721e464ae92715b294bd21b4512f69730c5e1bdda025e3c96c5fd49791fc9351283545c1e3cc07947972f8ab27bea324a6521b684b101b1ac35791f26d0af2526e3b06e5d90d401f78af82ad3f03f00b342c52361d331543e4b40be61fca3d205e443eeb4c57d8648f56c85d3ba8f6fe21e343a750ce	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x690318e2a4dad9ae83ec0a684c5d4ffb3b1dde44d3b261ebac5c24377947a66be425d6d1467e3b4fcd25c2f566b383cf2c88e905953f56dfa1795cf03c89b803	1585247226000000	0	2000000
9	\\x9ee5fcdd21814ca508e77fb1f12878fd8fde8de0dbf98c09c4eafbdb16d1a891a5cdf4fc6bb27b35f332cab91777340b925ba6cb09814f8151b5b877cb472050	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x9a71e4484e30c9b649e6ba6c64a4450f758e34226d369ca0837ca459776fb2f142b572b1e64d846bb4845c362d8ca07268fed5b31edbf65f413fb2fb1caa8abc83d92d0da49fdafff32042ef867989bb78957e59faac66291837a8c3fa230fbc992f404a1a31924f6f99e7a8d76949db7dbba57ac103df3c1d767c33623c4270	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xaf53eb48f261b549c9de5270cae9795bd7a8592391759de3b521bb79acadb53ea78a25d14674f863bb21c05d96ea43e25a6ec5e18faa544650896f0f8534360a	1585247226000000	0	2000000
10	\\x60632d0439e49678b7f284dfab08a4a3e657f521465d440bb103dd6012da2514ef38b48f972765d56c27460428450c6618d5cbeef6a71adfb1b2abf64fc4bf68	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x5a35b65a05ef66471acb62788150dc92f0d3bdb5af550eedd18f364e88bb30f53d95a1a740348d3c2a92d5df395655a87920724068fd877dfed267c172cc2d065769b83e220bb743f450ab6c609c32171e49333dfa13a696c393d0ea0c3a955262410f5e096963a606d7e7012b7c5bc1d5408f71fce7978df5a5723d7f69d3a1	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xe0d59b95446aef3ad0ee8128d7f6f59e20639def53ecca82072f799f2f93246d2bb5e8f9197ccddbe5c3cdba9299bd2346d558dc60c9102cc5986ec58eb82b06	1585247226000000	0	11000000
11	\\xca41556b29565f0be8a1614df891946e35d4e20c1e613d983c2401102d56e89615780ce613a025470c2b03ca188314d510109a52adbd99c3fbc8aefca447dc8b	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\xa8b27505ef3eb313171476cf80897adc89921bcb3e97eb758b3b0b928909eca42249182e8595faa046dd8f545a021a8c3b25b0d3022e3a5e77a928000ad3402147a562ee6b78744976cf2db1a64fe03f308987db1f85ec1197a049bbc506d979c9666951d57cc9daa0893b0241de5a977e35f736dee165b619ba0aeb090edc59	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x86b3e87a469ffbe0504a6289882427bf04f70446e8be4195572d48a9d5fe2225b939bab7a562b47bc3ad91892cc095231d107213760a17e8c27a405c1547a10c	1585247226000000	0	11000000
12	\\x4b53c212fc6d01d19b6eea549ef51d69255630cbe2828ee728ac02457cb885f03dff8d89c6bd63e51f7fe0172b644b967a24061dd25ccb83a6d18626a31e37c3	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\xa30d8e019e066ee05a44e8b7327c9fcf7d6e503e4815f5bc885b99656dd1acd1985b43d8ded53cf587196cf06a8e27890bb51d883c79c7da39795ba68cc3abcae887f682c38ab3d8988269e4a72550fbf1c92af8eb2376aa55359f899345bebff26c3ce9a7ea5f57ed122eae9f4c43c293b3eefb2d732379a7247b902aa87113	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x574c05f5afae8c1191d0a8a577f430590c01f7f4b99f47ebfccb8f0f65504a5ef8a8dbbfac9227d696f3b886f97741625707ddcdc6aae474e688552041bafe0d	1585247226000000	0	2000000
13	\\xde66e8165426c0a5506e3cda95fa32a5e5ad78fe18c8af2a6309416a86d69da1132131edca99b2684c0a0793246143d7b1bdadb8f6ee09e2201134fa0d0994ff	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x936ac8eb60f0dbba8c146170c1c46da9b6dcf604c7759be8de925b990425c6e2f129516ed0234a13d5782db59b49b1a2a56185a5674a749c0b89f4869e2997678a86d7effb16a4b8348aa1470d0dfa559beb5b3e240f331415449911a1d63a85247b4bade791b3093d36a993d2785ad17ed099da4e22867ac9f8491448acdeff	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x00a69d0a669a3561d1a2718eab1af264b955e59eb0b0f977e956d2af4074fb018530ce72aba04ebfcaa9b16caa48f3845078c464156165c5ea7975ee0f096807	1585247226000000	0	11000000
14	\\xf2cf47750bf61cd70088a8c23f5a2449aa915d839e23d20cd845166b2183e7788b25df00d0da40fee13af660a10e5e85b0bc878d807e1c5f13046e0ed151537d	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x6b1f1eba71b3e8fa153b47f0d5acb90903ec86e69adf63d40a78ecb75ec1025029295d7d354eaba636ab7f06f28250026ce8ace07b3ea294fbfab77339fc6cf7dbaf86cfbb8ac2d1c88655012dbc5211b84eb4af42d8fe5bb5b841568586cd749df3b20ede2d2b6cdd6d9ce9d0f207d4bd79843ea18f8de57f98ced3898d43e1	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x8bbb9c97d8e2ae2298bca00cee1e52e86260d46f4205991d33315829a702634fa07c518934ece2e8598481c573cbf6e7c3918302ea877efddf3d4596d6eedd03	1585247226000000	0	11000000
15	\\x0e53156fba4e75d71bb1dd03ec212bb660cff0c2d5bc3683d6677a4fda7ff6c9644bd039ae479cd315c2a9445cdfcedac1aa2e323ae501fd0d2c04781c37cc62	\\xfac60747f6f5230990e394d61524d5e5c2d7fde9d64cb67971383afded993d28b8ccc24859da6595521f2131f8b29f7249a132b21bd783ddc17df6743baa690f	\\x1b4a73f61abd43fe3032e7bd7f2ae75b7d4b7aaf1d52a7ffa41cad1fcfaba3df9ad4f53f682164ff189a5cae3f5476d800d48769a444608b0f88960fdef16c3538c55281221fb882edc57f474e4deff47300e2a920124e54a8076258edd1c372e5944a9fe9f5df7875595efb55c6efd8d3cf3df45fc81e4a1f5dfca7f72a1200	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xf732e916f16f2b6362f54323dd483ef92745dd1d65933427ba12a223628595d3896831f95c69ac8afbfc7e211f60878983cb1df60cf1ffa8aee4c01d716f840c	1585247229000000	1	2000000
16	\\x8462d40f51d83a81b975f8944404ac198173e851992a346e07ad09c859093a2a19ca7bb8c78d9c1b063a5ce248932ba32bc6a3ed07329f3c9609a4be9858bf8f	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x3d0bef9880eabf5d8e4db31ddc896f5cac12daf48f1cdd5a4a8dbfca48ca645c11148b32e15a441d6e17c7669ea10f51bf596d10b741ebd898d64bf7b498f9cce4fe7203f371ae03e5b2cfd261ef336a00817aecd243ec61ac5849a35536246eab312708d61cc8abbbd50b1cc9a6bae4ad5f40d564b607ddf9ef426c65264613	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x44bbadffed4ee4587f92605e72d67103f92345399352d406f7d38811461b6ae3eca9ffd1d201d875dfc1b3bed85a5ae857dbbcf8fc551c3e86edd11c2157a80e	1585247230000000	0	11000000
17	\\x4b35931e6ead2975c9099cfc47fe715087be04a7c3730a131cf16dcd6e8b5fbd1b58e660afa7d1022cba95f9a2e1bacf6187115329db523d6b9aa404345853bc	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x705c95c755ac42c1280f8ef6bfe442362d3aaa9f373fe5090338cbb39531f6c0ff83d3724a0e098ad1b6af8831ad26473c8990d2bff5a18c6133692f8dc9ac0ffa0a80b2906d022a3b35de9aab72e18032f2279e9d8f82cdd993f0a07f9e6d15ce9c8e54fe22ba64d992c7c9314854c4a8162814e0bcfbc53c92b3738c2b0fcf	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xb7c5f441cecda52fd4c0626d811518acd09904e87633a9935fa160e4ec43d553e472c6ab87dedf6c159416c312355d90801c8c4924e1a9add31cb89722164609	1585247230000000	0	11000000
18	\\x05f3a74fe2fe247762d754fcdd5bcb83d563ecfe3b6afcf5bb7c84ff818896fa3080d0311117990e576e31d54d3656c121018fe343bd32faf81b6ad6a21e332f	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x9a46f96041f4a79916724a0761def85dd23f21dc710642e665793d7055d3f1764fdcd177a287aa609886016d3b42578d0cd9acde50f46473d6f772e2949ccf00db546f37a53697f8cf3e63024d742f752508927af9ff6950fc3e6ee7032c3d49a79f858ec12d01bee7f78ba5b5e6e5ca31a10920d634544e0b5dac4b61490d5d	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xebc8717aabfabd10282204f9ef88b55edfc5949ae3e18b98e14a7d3e07abe0e82c3501628c6673b6655c75d9f8c2c4662a3e3624dc8bc4e7bd11f726e2c0c408	1585247230000000	0	11000000
19	\\x66ae656c02e2fffdec39453e05cbc4422de0bae93fc22f845a681e9c0a80c5b27b11b16813ef6a63a184884b0eb911ef09f7b92fa043d48a320c7dea5c2bac7f	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x6edf87b1913134c93ffd14a9734c2e4b69bf841b7ba133606d26edddd69b3561ea733d3de73bc3a3780f0feef8817d5e5b0d4a7b13bcfd185deb5594a1a3c9d5b3d9929d8d566c1c9769de373a035c033ac02c98974c55229493225dcb880d54fdc56e95a8ff1c945a28ca7c63952cf138626c05549c0ce7664883818d00bf11	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x96bd755d90921484fe6689a86486e106d45fc78dc6ab6a73f9ca9f584d3825d6cc245658e10f5875954f6ecfb0c700362605a5d2804db0b72851a98397cf510d	1585247230000000	0	2000000
20	\\x8a31eeabe64ae80d2c0c99c68e7200f5089608071ff04cfa32fc40c0143ccbec2d190a2aedf72ad5926177665e55f3ef66a3e19a9401afba76ef539e7451870f	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x08c3e0f40be0aaabcb31d5f8045ee908192792e0980c12945bbe5dfdcd1e779386b9fdfbddae72bf84021918967496c69e9d0f9630a3b4975b2dbbed4e6a4a4df8ce88f1c538131b519a1b4cd795c01b8e204440a3590b9ce757409b349442ca72f12f4e4f0e080be5628eb75aea9d6174726b88e393535d1a4ca314f82fb284	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x0884c026f4df818dc7723823ee1542f6bdc81738478e7491842630473d5c67fcc2c1660cf0be1f45fce434c81c38b6dd9d3c1db74d5c241c29d04c658a18390a	1585247230000000	0	11000000
25	\\xf2a6c8490d5759e9cd44d8e474ee8aac282a95326b8af1b3e6cd097f65e055633f8a95f456add1ae539a161142b551001ea7d643630e561169a0b0c2f2054917	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x65d094cd42bf265e17f74ec061b5f58f07b460c9942f9049346e620d98c1109b4b1ac4b4db065539c8159f198824c271c41be310b14f2f0ad4276cc5d18f8aae19a8eed68eacd558dc82f270232dae708d259ae0250c5166950fe88b6c63bf6d296883d449d9daf3cc30d1e32861da0b3ac9703118e2b0e9411141646b3843a7	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xd87631d6086f3e5d71e211aacf324a7ec853b15b77c4b17e88c6d5920949c86a9b60e74ff1953c16c8430017925e2868c0c1ce7f51b0cbe1c8ced9d27824530d	1585247230000000	0	11000000
21	\\x8faff62e01a2e73d5510bc93d1dce5bcc032e616c0650201650ca170dc815ec175e6223c85b232553c08a00bdf5d0db1ceaff775c91f2d9afac0ba97e9b63081	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\xc1cbe09f93ec79424d690499b928d23c2653cf52f5fcd624d40627382fd35756c985f91e4d971da86ede32db8b0ed286f55fb02794d723866e61e9cee99a6765c7e42ae8f926d8d73a7f95441219450df3386fa0ea5949f8a83ed298f33c7cf3cdd16a7eefababc065429ee72db1cd79d065671dc3af70a21d97fbb8a211a975	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xeaea23d476645ffe095d8d6f5969d9b88e74a95a18ffbec57c5207fddb6c52f0805f0aade8995b788e11b215489792af2c8409798a4d17e2979ee078cd750609	1585247230000000	0	2000000
22	\\x58a82e4e4716bde678b3532cc06632b50d47afc1637391e2b6e95b3fea751077a746967495c3ea32994316e4bbe2bf8bf2e1637a882938802e5429b43e4f0c84	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x7681e9b708d5e987a6dc6b23f081273b2f5645d2b3a6bae978f11e2cbb93e31061d23b1865fc8dee54d5205480929ed5dfae1c166e00575dbaa53eeed8b8b53405bf89a8fe2ac5bb1fbf2bc11c340492e307797d7d0b1edd8a10d44b1c1b72b20a784b03fdccb6eeb8b1038f8c68a5524230d57677e01402510c8d1a2bc4803e	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x221c138f646f4ca50f54b87b942db487c126e49fe35e67af9457864d26d4bd013928efaae98a9d18bd064cefc5bdf82dcfbcc949ca041e35fa20e83953950809	1585247230000000	0	2000000
23	\\x9aaa401c7cbe71171a1cf1a75fbcad721f2071a2495622c3a2be00fe19addf942c29260bb2e427310938e85cbe0bc76adbb19bbfb27e40fb69c4156010c7802a	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x24dedb75ebc6b9529c652c41b88dd408f6a5078845d464a27ae4473a1d3f6aa93c719303ba1ef5fdde5a83941ca804179491e0cc22007af400c61c9175e0776b9879c6cc422a464c752c6eb06766553ca3c241bb4bb68810d7c9e4f723deacb2daaa3741a3c5b25ccce0d92e92dabdb659ceb9c4c1c8c4eefaab8b500cd0a1ca	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xf2c6e943016d8b743bab51992d1418edc8c340f45afc66464cd4d18dd7fe208235f35f5f3515cd7bed5e097b5e75eb9f8ac8d5eca59ae9432275d62dbe5e1806	1585247230000000	0	2000000
24	\\x6ecd5993d2ebb9c51f62e3fb88db2092e39c63fbdbbe87adc8b9f3c874a2c89b1b20b87ba0ab1e8c25c57e272cbf584ab94bd666b45c299fda51b6e46d7425a0	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x2900c01b645d85e0e49a1649cd416b5367bd3401f64d3b5230b05aa047e0dc6ba9c555056e51cffec724b2c38bdf0ed14519f098d987fd4b629ac27d1173c46203285913837c82422373b37707f7d866ed454ea90609ffff635efe7f0d79fbc916c8058dd3b108f07f3353e6fd8ceecb38fd7d12278b9e001e22630c888b625b	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xa134ac4ed1d1b5f83410753def597fcc22933c4e437c1de44136990fc4a42bfad1b4bf427c73a58024ccbd0500180628da898c73e737d56377e63bb781ecb208	1585247230000000	0	11000000
26	\\x16c88a50e2920c8a330585b2e490e22929c6d7ce9abb2d519c6381efc9e939248fdca90b509ec25c2a0de4b13046e1692e9bde9304a03825c0bbf31db4043b50	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x9a027e2d37b4eaf80f54372d5097332208e4c9daa42f7615855e545c01c3424e703150911901cfd8e7c82748c324e3f7000f3ec6168bbaa64f40b8cec7db1be6ff581c47506581add4828a9ccf031d52816dd7912872d221eff1ba197ecc7ba2e5e442384326e3075382623775a9be991e3ad14aa023c12e51aede29d14dba30	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\xb1ab12d70329f3942c13b29a4419fbf0b2d3c7321f11068faceb35a7e9bd9470c4decfd72e4a5384c02eab97b567c71fe926b9e8a058317e9eaef0bc0e27830f	1585247230000000	0	11000000
27	\\x4a773b09239e4eb500fc1f7901824a15d989f9d0fabf717bacd3a8a81c7ae9858fea32244fbd882f0f55d8763262a34508b0a9e1ce50b96c3e04212568a724c8	\\x747f5c89194b7266b995701b18f8f5f9b31a1f18997b72aa306b12fe8c1be3db30507cf68c32408ad8ed9accdf31dfb56ac917b362dd21e4727b7e499540110f	\\x216c2135704cf4f5e1275784111b36a56bfdc9a5370a0197a8b610db27c170074e30f37079cfd0a64ffd919236c1bd8e98c4ad1939e51e43adc0e180cfcc08d0ae2ac0565d5350662ab50700ea87b17a08ee280896b7d98cdb3abfd459297b3da7ea536cd75d420e516b7f25a85e9380bdff17750bbdf2857c6fab1c9029902c	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x8ff08d79c31ee50fecab4b49730ed7c04d8f5fcadf1fd3279e128c88a0e8d0044d2927e090f4a674a6bb4224461bdee8b6fae97c484c37e8a832bda5cdce0b0b	1585247230000000	0	2000000
28	\\x77f76187f4587134ab7e00b26347225863ef176a0d9885c4206e01611cca519ea0c5fc5ac6cdcbaef3823b9cca6bab32487bd9c5e0ccaaa00614917c9355c168	\\x515baaf90e9c05724c56f5304095310345032d27286e6136a972ac6017b9f67fa608a11a806b632cc1f7d367ea63e1df40cd2d0c0756de82f829bc67f8b82ec5	\\x711ef153eafca8a60f7a7033d50f96ab6f614d8ebde72ef96742d5d351cc75f409a9c8a25f8151e39fcfc7de7299e3f0a725b58705f4822ffbe9ebca7d0ace87722e91848ea5fb94f637c65d145b803781b23d1a22dc2742aec014364dc54ed6ce4aab2eb13da550b4b08e62d09297af96ae27f4098a2fe276b3e90e7b791502	\\x56df2171b6b15ab33867ed818451aa0b082e06e9246b7fab3c180c1e60ec3a36	\\x91cdc2831948debbebfb4f1cdc9f68eedf602e0a7972891a92db3f486a4517422d8b8f53301415a572bdcb80b28d1b4ba9e7050d5070fc82bc7503dea2c8f506	1585247230000000	0	11000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, true);


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

