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
-- Name: auditor_denom_sigs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denom_sigs (
    auditor_denom_serial bigint NOT NULL,
    auditor_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_uuid IS 'Identifies the auditor.';


--
-- Name: COLUMN auditor_denom_sigs.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.denominations_serial IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditor_denom_sigs_auditor_denom_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditor_denom_sigs_auditor_denom_serial_seq OWNED BY public.auditor_denom_sigs.auditor_denom_serial;


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
    recoup_loss_frac integer NOT NULL,
    CONSTRAINT auditor_denomination_pending_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
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
-- Name: auditors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditors (
    auditor_uuid bigint NOT NULL,
    auditor_pub bytea NOT NULL,
    auditor_name character varying NOT NULL,
    auditor_url character varying NOT NULL,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT auditors_auditor_pub_check CHECK ((length(auditor_pub) = 32))
);


--
-- Name: TABLE auditors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditors IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN auditors.auditor_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_pub IS 'Public key of the auditor.';


--
-- Name: COLUMN auditors.auditor_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_url IS 'The base URL of the auditor.';


--
-- Name: COLUMN auditors.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.is_active IS 'true if we are currently supporting the use of this auditor.';


--
-- Name: COLUMN auditors.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditors_auditor_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditors_auditor_uuid_seq OWNED BY public.auditors.auditor_uuid;


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
    first_name character varying(150) NOT NULL,
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
    master_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
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
    denominations_serial bigint NOT NULL,
    CONSTRAINT denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64)),
    CONSTRAINT denominations_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


--
-- Name: COLUMN denominations.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denominations_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.denominations_denominations_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.denominations_denominations_serial_seq OWNED BY public.denominations.denominations_serial;


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    exchange_timestamp bigint NOT NULL,
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
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
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
-- Name: exchange_sign_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_sign_keys (
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
-- Name: TABLE exchange_sign_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exchange_sign_keys IS 'Table with master public key signatures on exchange online signing keys.';


--
-- Name: COLUMN exchange_sign_keys.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.exchange_pub IS 'Public online signing key of the exchange.';


--
-- Name: COLUMN exchange_sign_keys.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.master_sig IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';


--
-- Name: COLUMN exchange_sign_keys.valid_from; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.valid_from IS 'Time when this online signing key will first be used to sign messages.';


--
-- Name: COLUMN exchange_sign_keys.expire_sign; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_sign IS 'Time when this online signing key will no longer be used to sign.';


--
-- Name: COLUMN exchange_sign_keys.expire_legal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_legal IS 'Time when this online signing key legally expires.';


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exchange_sign_keys_esk_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exchange_sign_keys_esk_serial_seq OWNED BY public.exchange_sign_keys.esk_serial;


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    denom_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


--
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.known_coins_known_coin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.known_coins_known_coin_id_seq OWNED BY public.known_coins.known_coin_id;


--
-- Name: merchant_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_accounts (
    account_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    h_wire bytea NOT NULL,
    salt bytea NOT NULL,
    payto_uri character varying NOT NULL,
    active boolean NOT NULL,
    CONSTRAINT merchant_accounts_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT merchant_accounts_salt_check CHECK ((length(salt) = 64))
);


--
-- Name: TABLE merchant_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_accounts IS 'bank accounts of the instances';


--
-- Name: COLUMN merchant_accounts.h_wire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.h_wire IS 'salted hash of payto_uri';


--
-- Name: COLUMN merchant_accounts.salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.salt IS 'salt used when hashing payto_uri into h_wire';


--
-- Name: COLUMN merchant_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.payto_uri IS 'payto URI of a merchant bank account';


--
-- Name: COLUMN merchant_accounts.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.active IS 'true if we actively use this bank account, false if it is just kept around for older contracts to refer to';


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_accounts_account_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_accounts_account_serial_seq OWNED BY public.merchant_accounts.account_serial;


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
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
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64))
);


--
-- Name: TABLE merchant_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_contract_terms IS 'Contracts are orders that have been claimed by a wallet';


--
-- Name: COLUMN merchant_contract_terms.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_contract_terms.order_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.order_id IS 'Not a foreign key into merchant_orders because paid contracts persist after expiration';


--
-- Name: COLUMN merchant_contract_terms.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.contract_terms IS 'These contract terms include the wallet nonce';


--
-- Name: COLUMN merchant_contract_terms.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.h_contract_terms IS 'Hash over contract_terms';


--
-- Name: COLUMN merchant_contract_terms.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_contract_terms.refund_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.refund_deadline IS 'By what times do refunds have to be approved (useful to reject refund requests)';


--
-- Name: COLUMN merchant_contract_terms.paid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.paid IS 'true implies the customer paid for this contract; order should be DELETEd from merchant_orders once paid is set to release merchant_order_locks; paid remains true even if the payment was later refunded';


--
-- Name: COLUMN merchant_contract_terms.wired; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.wired IS 'true implies the exchange wired us the full amount for all non-refunded payments under this contract';


--
-- Name: COLUMN merchant_contract_terms.fulfillment_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection; can be NULL if the contract has no fulfillment URL';


--
-- Name: COLUMN merchant_contract_terms.session_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.session_id IS 'last session_id from we confirmed the paying client to use, empty string for none';


--
-- Name: merchant_deposit_to_transfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposit_to_transfer (
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
-- Name: TABLE merchant_deposit_to_transfer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposit_to_transfer IS 'Mapping of deposits to (possibly unconfirmed) wire transfers; NOTE: not used yet';


--
-- Name: COLUMN merchant_deposit_to_transfer.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposit_to_transfer.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposits (
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
-- Name: TABLE merchant_deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposits IS 'Refunds approved by the merchant (backoffice) logic, excludes abort refunds';


--
-- Name: COLUMN merchant_deposits.deposit_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.deposit_timestamp IS 'Time when the exchange generated the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.wire_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.wire_fee_val IS 'We MAY want to see if we should try to get this via merchant_exchange_wire_fees (not sure, may be too complicated with the date range, etc.)';


--
-- Name: COLUMN merchant_deposits.signkey_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.signkey_serial IS 'Online signing key of the exchange on the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.exchange_sig IS 'Signature of the exchange over the deposit confirmation';


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_deposits_deposit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_deposits_deposit_serial_seq OWNED BY public.merchant_deposits.deposit_serial;


--
-- Name: merchant_exchange_signing_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_signing_keys (
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
-- Name: TABLE merchant_exchange_signing_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_signing_keys IS 'Here we store proofs of the exchange online signing keys being signed by the exchange master key';


--
-- Name: COLUMN merchant_exchange_signing_keys.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_signing_keys.master_pub IS 'Master public key of the exchange with these online signing keys';


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_exchange_signing_keys_signkey_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_exchange_signing_keys_signkey_serial_seq OWNED BY public.merchant_exchange_signing_keys.signkey_serial;


--
-- Name: merchant_exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_wire_fees (
    wirefee_serial bigint NOT NULL,
    master_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT merchant_exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64)),
    CONSTRAINT merchant_exchange_wire_fees_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT merchant_exchange_wire_fees_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE merchant_exchange_wire_fees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_wire_fees IS 'Here we store proofs of the wire fee structure of the various exchanges';


--
-- Name: COLUMN merchant_exchange_wire_fees.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_wire_fees.master_pub IS 'Master public key of the exchange with these wire fees';


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_exchange_wire_fees_wirefee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_exchange_wire_fees_wirefee_serial_seq OWNED BY public.merchant_exchange_wire_fees.wirefee_serial;


--
-- Name: merchant_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_instances (
    merchant_serial bigint NOT NULL,
    merchant_pub bytea NOT NULL,
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
    CONSTRAINT merchant_instances_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_instances IS 'all the instances supported by this backend';


--
-- Name: COLUMN merchant_instances.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_id IS 'identifier of the merchant as used in the base URL (required)';


--
-- Name: COLUMN merchant_instances.merchant_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_name IS 'legal name of the merchant as a simple string (required)';


--
-- Name: COLUMN merchant_instances.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.address IS 'physical address of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.jurisdiction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.jurisdiction IS 'jurisdiction of the merchant as a Location in JSON format (required)';


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_instances_merchant_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_instances_merchant_serial_seq OWNED BY public.merchant_instances.merchant_serial;


--
-- Name: merchant_inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory (
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
    next_restock bigint NOT NULL
);


--
-- Name: TABLE merchant_inventory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory IS 'products offered by the merchant (may be incomplete, frontend can override)';


--
-- Name: COLUMN merchant_inventory.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description IS 'Human-readable product description';


--
-- Name: COLUMN merchant_inventory.description_i18n; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description_i18n IS 'JSON map from IETF BCP 47 language tags to localized descriptions';


--
-- Name: COLUMN merchant_inventory.unit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.unit IS 'Unit of sale for the product (liters, kilograms, packages)';


--
-- Name: COLUMN merchant_inventory.image; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.image IS 'NOT NULL, but can be 0 bytes; must contain an ImageDataUrl';


--
-- Name: COLUMN merchant_inventory.taxes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.taxes IS 'JSON array containing taxes the merchant pays, must be JSON, but can be just "[]"';


--
-- Name: COLUMN merchant_inventory.price_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.price_val IS 'Current price of one unit of the product';


--
-- Name: COLUMN merchant_inventory.total_stock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_stock IS 'A value of -1 is used for unlimited (electronic good), may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_sold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_sold IS 'Number of products sold, must be below total_stock, non-negative, may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_lost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_lost IS 'Number of products that used to be in stock but were lost (spoiled, damaged), may never be lowered; total_stock >= total_sold + total_lost must always hold';


--
-- Name: COLUMN merchant_inventory.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.address IS 'JSON formatted Location of where the product is stocked';


--
-- Name: COLUMN merchant_inventory.next_restock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.next_restock IS 'GNUnet absolute time indicating when the next restock is expected. 0 for unknown.';


--
-- Name: merchant_inventory_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory_locks (
    product_serial bigint NOT NULL,
    lock_uuid bytea NOT NULL,
    total_locked bigint NOT NULL,
    expiration bigint NOT NULL,
    CONSTRAINT merchant_inventory_locks_lock_uuid_check CHECK ((length(lock_uuid) = 16))
);


--
-- Name: TABLE merchant_inventory_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory_locks IS 'locks on inventory helt by shopping carts; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_inventory_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: COLUMN merchant_inventory_locks.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.expiration IS 'when does this lock automatically expire (if no order is created)';


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_inventory_product_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_inventory_product_serial_seq OWNED BY public.merchant_inventory.product_serial;


--
-- Name: merchant_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_keys (
    merchant_priv bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    CONSTRAINT merchant_keys_merchant_priv_check CHECK ((length(merchant_priv) = 32))
);


--
-- Name: TABLE merchant_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_keys IS 'private keys of instances that have not been deleted';


--
-- Name: merchant_order_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_order_locks (
    product_serial bigint NOT NULL,
    total_locked bigint NOT NULL,
    order_serial bigint NOT NULL
);


--
-- Name: TABLE merchant_order_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_order_locks IS 'locks on orders awaiting claim and payment; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_order_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_order_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
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
-- Name: TABLE merchant_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_orders IS 'Orders we offered to a customer, but that have not yet been claimed';


--
-- Name: COLUMN merchant_orders.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_orders.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.claim_token IS 'Token optionally used to authorize the wallet to claim the order. All zeros (not NULL) if not used';


--
-- Name: COLUMN merchant_orders.h_post_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.h_post_data IS 'Hash of the POST request that created this order, for idempotency checks';


--
-- Name: COLUMN merchant_orders.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_orders.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.contract_terms IS 'Claiming changes the contract_terms, hence we have no hash of the terms in this table';


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_orders_order_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_orders_order_serial_seq OWNED BY public.merchant_orders.order_serial;


--
-- Name: merchant_refund_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refund_proofs (
    refund_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    signkey_serial bigint NOT NULL,
    CONSTRAINT merchant_refund_proofs_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_refund_proofs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_refund_proofs IS 'Refunds confirmed by the exchange (not all approved refunds are grabbed by the wallet)';


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refunds (
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
-- Name: COLUMN merchant_refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.rtransaction_id IS 'Needed for uniqueness in case a refund is increased for the same order';


--
-- Name: COLUMN merchant_refunds.refund_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.refund_timestamp IS 'Needed for grouping of refunds in the wallet UI; has no semantics in the protocol (only for UX), but should be from the time when the merchant internally approved the refund';


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_refunds_refund_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_refunds_refund_serial_seq OWNED BY public.merchant_refunds.refund_serial;


--
-- Name: merchant_tip_pickup_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickup_signatures (
    pickup_serial bigint NOT NULL,
    coin_offset integer NOT NULL,
    blind_sig bytea NOT NULL
);


--
-- Name: TABLE merchant_tip_pickup_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickup_signatures IS 'blind signatures we got from the exchange during the tip pickup';


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    pickup_serial bigint NOT NULL,
    tip_serial bigint NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: TABLE merchant_tip_pickups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickups IS 'tips that have been picked up';


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_tip_pickups_pickup_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_tip_pickups_pickup_serial_seq OWNED BY public.merchant_tip_pickups.pickup_serial;


--
-- Name: merchant_tip_reserve_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserve_keys (
    reserve_serial bigint NOT NULL,
    reserve_priv bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
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
-- Name: TABLE merchant_tip_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_reserves IS 'private keys of reserves that have not been deleted';


--
-- Name: COLUMN merchant_tip_reserves.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.expiration IS 'FIXME: EXCHANGE API needs to tell us when reserves close if we are to compute this';


--
-- Name: COLUMN merchant_tip_reserves.merchant_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.merchant_initial_balance_val IS 'Set to the initial balance the merchant told us when creating the reserve';


--
-- Name: COLUMN merchant_tip_reserves.exchange_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.exchange_initial_balance_val IS 'Set to the initial balance the exchange told us when we queried the reserve status';


--
-- Name: COLUMN merchant_tip_reserves.tips_committed_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_committed_val IS 'Amount of outstanding approved tips that have not been picked up';


--
-- Name: COLUMN merchant_tip_reserves.tips_picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_picked_up_val IS 'Total amount tips that have been picked up from this reserve';


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_tip_reserves_reserve_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_tip_reserves_reserve_serial_seq OWNED BY public.merchant_tip_reserves.reserve_serial;


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
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
-- Name: TABLE merchant_tips; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tips IS 'tips that have been authorized';


--
-- Name: COLUMN merchant_tips.reserve_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.reserve_serial IS 'Reserve from which this tip is funded';


--
-- Name: COLUMN merchant_tips.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.expiration IS 'by when does the client have to pick up the tip';


--
-- Name: COLUMN merchant_tips.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.amount_val IS 'total transaction cost for all coins including withdraw fees';


--
-- Name: COLUMN merchant_tips.picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.picked_up_val IS 'Tip amount left to be picked up';


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_tips_tip_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_tips_tip_serial_seq OWNED BY public.merchant_tips.tip_serial;


--
-- Name: merchant_transfer_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_signatures (
    credit_serial bigint NOT NULL,
    signkey_serial bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT merchant_transfer_signatures_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


--
-- Name: COLUMN merchant_transfer_signatures.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_signatures.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_transfer_to_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_to_coin (
    deposit_serial bigint NOT NULL,
    credit_serial bigint NOT NULL,
    offset_in_exchange_list bigint NOT NULL,
    exchange_deposit_value_val bigint NOT NULL,
    exchange_deposit_value_frac integer NOT NULL,
    exchange_deposit_fee_val bigint NOT NULL,
    exchange_deposit_fee_frac integer NOT NULL
);


--
-- Name: TABLE merchant_transfer_to_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_to_coin IS 'Mapping of (credit) transfers to (deposited) coins';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_value_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_value_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits minus refunds';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_fee_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits';


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
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
-- Name: TABLE merchant_transfers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfers IS 'table represents the information provided by the (trusted) merchant about incoming wire transfers';


--
-- Name: COLUMN merchant_transfers.credit_amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee';


--
-- Name: COLUMN merchant_transfers.verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.verified IS 'true once we got an acceptable response from the exchange for this transfer';


--
-- Name: COLUMN merchant_transfers.confirmed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.confirmed IS 'true once the merchant confirmed that this transfer was received';


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_transfers_credit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_transfers_credit_serial_seq OWNED BY public.merchant_transfers.credit_serial;


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL,
    failed boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE prewire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prewire IS 'pre-commit data for wire transfers we are about to execute';


--
-- Name: COLUMN prewire.finished; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.finished IS 'set to TRUE once bank confirmed receiving the wire transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


--
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


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
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    rrc_serial bigint NOT NULL,
    denominations_serial bigint NOT NULL,
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
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refresh_revealed_coins_rrc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refresh_revealed_coins_rrc_serial_seq OWNED BY public.refresh_revealed_coins.rrc_serial;


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    rtc_serial bigint NOT NULL,
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
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.refresh_transfer_keys_rtc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.refresh_transfer_keys_rtc_serial_seq OWNED BY public.refresh_transfer_keys.rtc_serial;


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
    reserve_uuid bigint NOT NULL,
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
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    receiver_account text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    reserve_uuid bigint NOT NULL,
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
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL,
    reserve_uuid bigint NOT NULL
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
    denom_sig bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    reserve_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
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
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserves_reserve_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserves_reserve_uuid_seq OWNED BY public.reserves.reserve_uuid;


--
-- Name: signkey_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signkey_revocations (
    signkey_revocations_serial_id bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT signkey_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE signkey_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.signkey_revocations IS 'remembering which online signing keys have been revoked';


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.signkey_revocations_signkey_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.signkey_revocations_signkey_revocations_serial_id_seq OWNED BY public.signkey_revocations.signkey_revocations_serial_id;


--
-- Name: wire_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_accounts (
    payto_uri character varying NOT NULL,
    master_sig bytea,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT wire_accounts_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_accounts IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN wire_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the exchange.';


--
-- Name: COLUMN wire_accounts.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';


--
-- Name: COLUMN wire_accounts.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.is_active IS 'true if we are currently supporting the use of this account.';


--
-- Name: COLUMN wire_accounts.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


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
    wire_fee_serial bigint NOT NULL,
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_fee IS 'list of the wire fees of this exchange, by date';


--
-- Name: COLUMN wire_fee.wire_fee_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_fee.wire_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wire_fee_wire_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wire_fee_wire_fee_serial_seq OWNED BY public.wire_fee.wire_fee_serial;


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
-- Name: auditor_denom_sigs auditor_denom_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs ALTER COLUMN auditor_denom_serial SET DEFAULT nextval('public.auditor_denom_sigs_auditor_denom_serial_seq'::regclass);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: auditors auditor_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors ALTER COLUMN auditor_uuid SET DEFAULT nextval('public.auditors_auditor_uuid_seq'::regclass);


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
-- Name: denominations denominations_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations ALTER COLUMN denominations_serial SET DEFAULT nextval('public.denominations_denominations_serial_seq'::regclass);


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
-- Name: exchange_sign_keys esk_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys ALTER COLUMN esk_serial SET DEFAULT nextval('public.exchange_sign_keys_esk_serial_seq'::regclass);


--
-- Name: known_coins known_coin_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins ALTER COLUMN known_coin_id SET DEFAULT nextval('public.known_coins_known_coin_id_seq'::regclass);


--
-- Name: merchant_accounts account_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts ALTER COLUMN account_serial SET DEFAULT nextval('public.merchant_accounts_account_serial_seq'::regclass);


--
-- Name: merchant_deposits deposit_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits ALTER COLUMN deposit_serial SET DEFAULT nextval('public.merchant_deposits_deposit_serial_seq'::regclass);


--
-- Name: merchant_exchange_signing_keys signkey_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys ALTER COLUMN signkey_serial SET DEFAULT nextval('public.merchant_exchange_signing_keys_signkey_serial_seq'::regclass);


--
-- Name: merchant_exchange_wire_fees wirefee_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees ALTER COLUMN wirefee_serial SET DEFAULT nextval('public.merchant_exchange_wire_fees_wirefee_serial_seq'::regclass);


--
-- Name: merchant_instances merchant_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances ALTER COLUMN merchant_serial SET DEFAULT nextval('public.merchant_instances_merchant_serial_seq'::regclass);


--
-- Name: merchant_inventory product_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory ALTER COLUMN product_serial SET DEFAULT nextval('public.merchant_inventory_product_serial_seq'::regclass);


--
-- Name: merchant_orders order_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders ALTER COLUMN order_serial SET DEFAULT nextval('public.merchant_orders_order_serial_seq'::regclass);


--
-- Name: merchant_refunds refund_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN refund_serial SET DEFAULT nextval('public.merchant_refunds_refund_serial_seq'::regclass);


--
-- Name: merchant_tip_pickups pickup_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups ALTER COLUMN pickup_serial SET DEFAULT nextval('public.merchant_tip_pickups_pickup_serial_seq'::regclass);


--
-- Name: merchant_tip_reserves reserve_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves ALTER COLUMN reserve_serial SET DEFAULT nextval('public.merchant_tip_reserves_reserve_serial_seq'::regclass);


--
-- Name: merchant_tips tip_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips ALTER COLUMN tip_serial SET DEFAULT nextval('public.merchant_tips_tip_serial_seq'::regclass);


--
-- Name: merchant_transfers credit_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers ALTER COLUMN credit_serial SET DEFAULT nextval('public.merchant_transfers_credit_serial_seq'::regclass);


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
-- Name: refresh_revealed_coins rrc_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins ALTER COLUMN rrc_serial SET DEFAULT nextval('public.refresh_revealed_coins_rrc_serial_seq'::regclass);


--
-- Name: refresh_transfer_keys rtc_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys ALTER COLUMN rtc_serial SET DEFAULT nextval('public.refresh_transfer_keys_rtc_serial_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


--
-- Name: reserves reserve_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves ALTER COLUMN reserve_uuid SET DEFAULT nextval('public.reserves_reserve_uuid_seq'::regclass);


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
-- Name: signkey_revocations signkey_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations ALTER COLUMN signkey_revocations_serial_id SET DEFAULT nextval('public.signkey_revocations_signkey_revocations_serial_id_seq'::regclass);


--
-- Name: wire_fee wire_fee_serial; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee ALTER COLUMN wire_fee_serial SET DEFAULT nextval('public.wire_fee_wire_fee_serial_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2021-01-08 18:30:07.405191+01	grothoff	{}	{}
exchange-0002	2021-01-08 18:30:07.517173+01	grothoff	{}	{}
merchant-0001	2021-01-08 18:30:07.702262+01	grothoff	{}	{}
auditor-0001	2021-01-08 18:30:07.838169+01	grothoff	{}	{}
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

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2021-01-08 18:30:15.318751+01	f	0ac96e34-cc48-4129-8b0e-84a9d6a73128	11	1
2	TESTKUDOS:10	7MSENY7GV926C4QPHAPXCRZZYVH8S1NZCBHM1ZKC8CRPKVZHJ9TG	2021-01-08 18:30:30.26499+01	f	2857a9d1-46ad-4f6a-a06a-7cef68ff81f6	2	11
3	TESTKUDOS:100	Joining bonus	2021-01-08 18:30:33.797682+01	f	c3999b1f-b76b-4b64-8e89-86c45d9f40a0	12	1
4	TESTKUDOS:18	HT0DSJVZYMTQ38BCX71FQ2VJNNMEEWHJ0ZM5YTYP9Q754NQENDN0	2021-01-08 18:30:34.4489+01	f	de2bb97b-3b94-476e-ab5f-6227a36e45df	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
c5d24280-baec-4a8d-9f70-3bf7804f944b	TESTKUDOS:10	t	t	f	7MSENY7GV926C4QPHAPXCRZZYVH8S1NZCBHM1ZKC8CRPKVZHJ9TG	2	11
5ba3b433-e9cc-4d35-86f6-c9e266e01136	TESTKUDOS:18	t	t	f	HT0DSJVZYMTQ38BCX71FQ2VJNNMEEWHJ0ZM5YTYP9Q754NQENDN0	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	116	\\x4404f5198e4b17e268bdf78ce01f82e82be59d66e73b7a18de5e371fe418ff3e9410143a35e8b0c562dee5deeb210db7e8c6a500fa2a0f9f5287beaeace2f601
2	1	13	\\x767294749d46031db9d6b0f2168c3ad43eecfc8ec6d4890af9a54304cbc3a915d0cc78eb2f8a8e5825b4a7b514ddba2360c0db9cd37f1ca8eeca0f9dbf3f790b
3	1	235	\\x1499700dbe5dbdad291013f755646e3bdee8d38bca2b080f8f058653d4241490ca4b861c51f3f5d0fdc7b5375b1fb76e2c7ebb862f279793e53a2f5da583ac06
4	1	172	\\x1dd2a532f75425dbd69a6741452410d2b9611c2869bf95e47e4d51174bd3e2c4399f77ac2982f1138cf3bdee58893dbee0caa5a4717f9c0a1d3db6fcbcb4870d
5	1	57	\\xaefc5f120e5f2f08c0d9c690cb3dfa45cb6865660cfaf4397a4bc4b32c89cbd799015bb99bb7be81adf39b61e335178159328fcbd008d85f4081486c64f7410e
7	1	86	\\x0a21d4a2b8d2bf5ba35e7c411250c5f64181bf2e5be283528aaa200e6584c1bf94443091faf81efe0c694b77cd848fe8d26fa252255cb9c6640fa001eb4d1802
6	1	144	\\xa523bba2352ad9a4ebf8f6048884dcef43ba5436714fcedee1daab9b70b43ac64fb6326f591ac9ace38297ef44f270b76222f16e68c4b2444009dbfa737f6407
8	1	304	\\x745eb6f5926ee66fe1fc684e54f364e04d4e63f6fac779cffabd6277f9ace54445d3f907d49e1c451737c00222e0bdcb374084baed829f754b2288c7f7ac4c09
9	1	147	\\xce7b40ec8b36aa0aeac7dcd8fccd25ae0111971afdb66b49394a50e8166e57e7010b8d53bc3e35334f36faeb17827b1c58b8c3c0b8643c3eb72a5ebb65d5a609
10	1	236	\\x8dd1f10f81690b53579f9f040210f51b6a394f3d2b7d6cb625e7b533d6a2bbd8cb7c14d89062feae9939f806e4a22e82f993ebbfa7fc1879b7237474d557bf0b
11	1	105	\\x8a7df61377e36b9434bcb7eec3c1eec15ea2c0ff66fa0af46c50fa9e540708cef94e2af2e80bae86884f16764add3d0e5d616259e2a0673852c2dd0c34e1450c
13	1	279	\\x7b3f9a32b7b3809c0b4407a57e16ef218d3123c7663bd1006fd7d3a14712b50c5735fece80cc8829512f1e562d640105223ad25db81d936729bf04b5ad8cce01
12	1	96	\\xc61280a61c1c74fd825316d9fe87f50b29d9ba7db20321a8cc91c36480bb77d00437df33ef017023a309384dd0a1627acc5fc0ad50c0b42afc8f710084133600
14	1	100	\\x8265e2bc8014ac36e717708f574503309a95e9e36757203f80e9b31933273619becd77dc9874f70f7bd28ec6c999ad2a389dd71c59359eb7ed6468a419df990a
15	1	331	\\xfae52bf4bb1630d137a5217d748a6008191e853caf8c55949c30f0c30270286d6b86175ea4644f8540e0490a1dfbd7e25bb7ac69704f2d7510f282e32ea38e06
16	1	286	\\xb8cc1b4a8889e4a6d98c1d6b2043229e0283642bf384144dbef7902d513cbe3eda620d9b7736962dbb9ca54179b83f13cb09b68ea310104cf9ad631ff6bddd05
17	1	368	\\x370a2a36c716f0874214da9abf059dcb1cd883434936b94d5cc61925035ba3285102429e70e8e34ab3f9e2304cd1dd4e7e0d1c4289b22b432e15b97190adb906
18	1	5	\\xf7e78ea79ae7a0cbd86eaeaa35bae8f47c3cb39904a6d253e1d191c36c9c4ef120026959816fc85bf09813856d7f89bac51461eb6f10b9b71566141dd690fe03
19	1	18	\\x702642345f785c5d93ab927abfc0935d13c9ddfd4c6bdad4e111cfe69347bea7814a185b639ffabe2748a2f81b2feffa8b483e8928d7a9b5c142fefe735e660b
20	1	74	\\x1e2d49c719ba7ebaf45a8cac8c804ddb9f8e572fcae2f32ac9f660a0ffcde5b150c372f7ab86dd1fe8b673a177fccd1b94e18c78bbaa95218087be0a2da45807
21	1	46	\\x00149f461bc166eaf124f9a6cf53a5d769aef51a836326c3ba17438417c7112543249e877ccd6788c87a851750f88a2949851628e933e536c619ea0eeff17800
22	1	117	\\xa9cd60979f869dafc8116007d887815fd45573766b3bd2059f11cd3f5c384483b772565ba341347ef18515277486044cf4ed69cb585ce2a8e51935c4de97d800
23	1	134	\\xef8b4b3ca27249da53c105b84274b84456635b812c05e5dc1b448147fe294532a13056af7f4ee08d53d02ed28ed930c2f1826852de98a120b8d2dc9649955e03
24	1	400	\\x786a3f569e67bc75ebcfa168513e1a8a6d5b73768095c5df0ea499025a8f7bc6f31d049d2b6ecf2fdc5966b21eac84987e69c3b028991f7fc555f546f3c8a807
25	1	315	\\x239f6de1e28de05930bed8a452abb6f433cc34463e111e88e053782677f9b570120775da87c95f8300af12c328f19e00c0ecfd1837eaa337bd4ecbb41a97ed0c
26	1	369	\\x04a83f62c5bda84ebb3e69b19400b6f0a82db6e9076a6593d946bd234d1c8bb51874d97967ee2fb291d819864d8ceb12021c0c70a9287453fe4c64828f9ca506
27	1	168	\\x07f1d54abdd7ea98a1b04bda0e08a49a4d1fe3c36243548e485b477d1728cdf636d996d3222d9d901bbb624dc8978ab44ecc0a2c6a6a3705f6dc37f51333fa0d
28	1	137	\\x3f1cc592415e71612d5191c3ea658b8c87eac73df14a784597b92f2412be0387e2947df691a843685ba6182ecad83e7fa468972f5b74e0f4bf2d420da519f00f
29	1	150	\\x0b4676a0d9c53feb49f7e5a50e3e039db8900492610ad7b27b13199ea63a452bb633360db5ec7dd96203cb51cac333dd4cd2c1bafedb6a2846f13761f3ad2309
30	1	106	\\xd14e808a09a811b518c65390c3d390bde6585d7165d7c2cebea3e5b1d1b5ba079ba1e9c3223cb6a375c5daf4ce55f36d4925c4e498f425b45ff293e80d193a09
31	1	170	\\x80c4e49dd577a3a43bc2179d94b433b645cef700d23a461d61d86fd7d3237f7416a05f5c29c2a724931ec54110f900c72afa4cfad9e7e77fe33cbeee8c66c709
32	1	310	\\xf665f87cb5f00f06601b814e3fb8d0ebcd7c53ae44793cf7fce22f8eeecb623bc540f4cbe9ddcee8555beb9d6da63c3d454d6499434e3eba4d59e4dc0d80ec0f
33	1	342	\\x31e8adb4169a66f3aa15e84d8f64e97b236887e0f8ddf50df0fd0ffbfbb8ce577762f6a8e41438e035055c8f10dc4f68bfd50c7d66faa7aa2ad4127a8876a400
34	1	283	\\x8491ec8388a8ef2c3c1b6e89d03de22b811d0bdfd640d414ce774df146de5c2b49e861385ec12dee2c27e3227940c70ca6cd8e1379c7f7d2dddda490ff38f90d
35	1	198	\\x6c0eaced6403a4710a744b7031c55a6570a0f57fcfc2da96c88779218520c6c3826bf9e3151a8d62aeaf9334bdfc60429bfb1ec4a85ce01ebe7bbb7079c35e0e
36	1	257	\\x3fb6887b030c59a176a8a9b52bb49c3530460ce9e381b781a413d7203bda680363ac1a0225b1ef70f4a9b7ee04685546abfb869cdf2555dc53cd8cf60d8af70c
37	1	26	\\xbb5bfed7a578f56b1e80a558e6afba46c0515c51a55b2de8f3837f5cefa509b6e8adea97edd5ca589d62b3029cf811f9fb644bc451dc9a449a37e06ef0ad1a06
38	1	44	\\x5b3fbe8f1ba99dd32294d934e255d3d7a722d3703e6c631a891885ddc94b6f01ec1c78091aec88c604a762296d81fdaaf708b7a81ffd150cdf395c9b7f25820f
39	1	327	\\xf86e9e4a06c2259c8e9eaa4c952d9862d92ab6d94293037da8a460863d62560d01acac4cf3cc5d3ee56edfa2722ef201f1a20be7552c2ccbf617d27931bd7402
40	1	156	\\xf042918c3d37189aac977e94d61c967e742697232db84c33088a7b377873604cae6ef9e56261c0f0f0a6db4c8cbae45c21664ad45b58316316401975fb458308
41	1	164	\\xc52a87f8c25071fe3c1a14fb3fd4d8be73a4297d935df248fbb9087d97896048d67848bb65982588ae2e6c4dd9fd015d1be84d2acb78327b1d4674c5fd68340f
42	1	123	\\xfe1ea609d04a00baaa3411d76b1de771c09808bf3b1c3e0f772f76e752af70c909f4c6cf17c6e0bfc8e7f8b9a0e45b319b44d9d7a8c6fb1076c2747bb6f61809
43	1	262	\\x1395594fbf89179a342136dc438572c04528154ed49dace2efe4c0a22e8670796681325d04acdd542c1de3d45654859242059b8a44e6b860e46cc1a8c28c2307
44	1	190	\\xbe7b80d8f5011f418725ae4ed9f7c9e3273adf455c1e612284e77118adc9f18e750fc3c2645eace8100c28be212cafbae56e14b83bf21671eb84f1d8b3bb4908
45	1	261	\\xdf5916b378d53954dd6fa80e8abe4e260e6b0d7e1721b84a35bd0551f3b370d17c80ce0e9f19dbc493fe03a23cc19d2de12fa2aa1dd8cde048f2ad8426def401
46	1	38	\\x504e94fe317f1b82a35264f9b3bb988aa0262518a560ed4f8dec027d46eebb85b628dcafa37e05eb550fc34ee8e7eced54860c44880df6c28d112eea696b320b
47	1	347	\\x004b7b16b9367733e20efd43f6ec2efbb214577821147c0e093df3db9fe0ab55675f8618e97b541057c923da8fc20b796068e79b74a7a2b0998dd7f68aab7e0e
48	1	37	\\x1eb2fbd465ecd12884b477883869cdff3860aaf83796ae14b537d18365c7496720a9ec172d637dc38c2c693a62289d086b599bc639e938b5f72fbd081923e906
49	1	419	\\x0c65acb45a10ba51a588ff37d2d429f643bbb18689b3465f9ae86a9066839d3c8d9da890749b0efa0767feec525b2b72861ea3794b5d0ae3f8c30876ce97ca04
51	1	389	\\xf25cfce8e696b0cf02cf1b932eb4b7a17ad88f9f4a6a95711fa2e918514778d72a3dc4f8f8c72068e952d042133123b0c5a81d73c53bf9abadafd96063091006
50	1	218	\\x54297b00f1c1bcdd6c63735bfe7521615cb093c96e74ff6635d01a50bf2292ed1459299dbea71193463ac8b17346adb27f225768dee5255f5cd081c07e460d0b
53	1	220	\\xd2f15b8dc4a550fe50c985e57aae7177ad6a6c7bf3db09beb667afab9310ecef3fc50ae60ab868e8ee73039270ecd29708a90d81a9c3e1ea52b7bb07cbd3ca03
52	1	390	\\x446862c63e1dd2b69f61d8aed87d20cb7197c177e2def25769c84f390ec719cbb2afddff24adf0cc7a80644754184589dea4deab25505f88644f6531a90d8f09
54	1	183	\\x07f3556320d935e3276e3451601b4eb28a194d5a257399e9d2996aff61eee4eeb99e0d70d6d8a011fde2be726e484e167e45a9ac41a54c0689a834d24ab6ed09
55	1	145	\\xef09de0958798475cd820547bcb6b107f95d4cff4cf1eaeb549083b8298d3ba5f073b64f6c29771b9388a4a13170703993347da9d8e69301e723e1c8ff710600
56	1	20	\\xa88e348f948de5955a16fce4d526522d247af73e987648a881e54811f0a019978ca2eccc78379929134d5d23b869ecae846db0d4a3ce782504e79939b929f407
57	1	311	\\x231d991bc2fb90209a8b408dd40993638685717ce896f998d0f6015b8dea87eb1658fa7252a1edace1e7959f51b389a2660aecea403f5b9db5f63a946060c707
58	1	189	\\x91247a1a80e7b43789f0b5334ac070da084e3182dc7946989ed958f4184034fc1bafa1ad634741512f818baae079a7bd38e41d32c3bc79e22b504097c9906502
59	1	67	\\xf2c5bcd1cf7e216660b296068bf0d786e5463333a636f612022704325a48c29162bb9b8017c1d68e2590b2b6f58e772b93d289f0a9a1d7186ea97cb5ee617309
60	1	82	\\x89f7093cc2a948aebf020ae9b4bd8a0f60bc3a949a9e0e4af6a3c96c428a8f9fd018376df90c0ea05133bb7349c8c6efc7ce23274b1bfd77166a8af9062fc20a
61	1	357	\\x17dbe13fd6e7baca9baaee32f4860681de4ec1829e79569fb7575ba94f2b305e25cd70bc899f32cce457bfa352607b9756520b9ddda5aebfd5bb4996bd5dcc01
62	1	303	\\x1c15e16357c38d5d9578a47e457b56da434687d656d8f80fedb40fa53574b36ac846d4e7289f102f979be1abe9df306e8e5f1082a27adf6e8b221f0effe73d0a
63	1	356	\\x6cc5fc48612f13f819f0979b50df8ae160d72d156145145b35ccc45f67ab1602517c65183a91f0eaabc66d390b1ad64ce51fe58d7579a4ab905b810f0d2d2606
64	1	139	\\x415692ef518482ec9fb8812aba24e3f3c697feae631fbb755e3caa1c0ee8d907251b3a7904e7ed336531c875c7b1e32085e780e9c444b1893f0f422b0039c503
65	1	205	\\x07d1e36b3ed970c84da92a8fc2d7776c1aec22ea61b7b46c9188dac1cabce81f9dd58345aab778e01064d29bd63c36840ad389a82e1a8935b8800429bbb42d0a
70	1	316	\\xf94b4b67c7f8d6f32146fa8f82f8b353dcd8ed45ce423ad101c5f26d46369dd7b7d4dcc3826ae4314a9e4a4c4ddb52a58845bf1655bfddf20d7bea97a5513008
74	1	393	\\xce7abc63a915adf2fa20eca044ea8e44a69905204b7ab9f6f57ca4281d33ee8fd5d9ef306a6973e4e2029d8b106ba4662f890ee9413f9764ce24a19291aef70b
84	1	227	\\xaa69a9ee750e600cf944b48dc9adb7cae34bde1221e4678c8fe269bcf7b18b1c26864261412e2a18b8d1cefd943c6ac501be98382b0ac3eb70aa065fe19a6f0c
91	1	277	\\x3570c9ca964d1395f37fa67f390698629292863c8da3fa88cc27eff8b3ead006888ee312713d18a7255c2f527e78ccba4b1d6790d6c7dcace0377208191d0c04
97	1	194	\\x54aca3b83ed425281875bb28ac7dc3d9bca32bef52461a94f54bbb6a5b4a455e032cae11aeb361aab0182573159d78a2787844323d599456defedaeabdd99a05
107	1	208	\\x229dd481948b3e9df5612f033c77d75c275228215ec96a82df3267806247607d8b47c3782d1bd14307f25c644bdc6efcc60edcefd55161abcb29b2226052a801
123	1	129	\\x44630cb42a0ddd166bd8ba6f89f288a4c9ae2cdff50fc40fecf066af186f07bc5fec09fc100915fff68cc8c684c66cdfd63224f202b538241e6c82f9d1ba9f05
129	1	230	\\xbcb631baeeaf146d080fd33f4f34d6af4ea7ac590318bfd952527131b5a932b046d3a5c32faac100156d6792ec5855159fad59c7a78c211bf2b9a2fe02af5507
134	1	151	\\x2b00599eabc7ffe0a508a4496831c41a08d53a70e5c196fbb06fa3926ec559cb012ca8ca49c7a6b3879e20457e83ae89c6b87eb0b4f8c5268cc9d5abc2b80207
141	1	424	\\x14c9b3c78b8ec66ada2b05912ee35c00ee4b54311af0a2fee13c209ca70873fb2d124d185f1690e7a5e82edb84e0bd9bdb3b9e240d0fb2fc6df710f6f8d3af03
197	1	320	\\xbad2e18fad5f3b7a0823b481b13c369127071743e36ef39e3ad57cc5562b831762031928915f2d2f4617bd98b56ebec84a9d9d27810acd3366f192730dec5e02
231	1	175	\\xf9f0d7763d99feb2aacd90ccc206c2dcaf886e84fb6cb5d88a25bf19b29033368262859c9bc56de483b90bc9ad51c8927fa8c64ed5ab77fb85cf53a1f50b8f02
259	1	197	\\xf47a12bf400262e61cb9dffba67873fd6d5ae0ab15eb1bfc52977dbf5ebcb8d8b4664fcdcd62b72ed22f9b30c188314ac8eaa4b0fd4934912a5607e974e49205
318	1	363	\\x11528f1fd5d36e1d6e4dbd2954d07d35125d639e25d178c3c8fcac42f2a0fbf27da8c3afcd20b54478329fab962736b6b94e99fc82d798a5a379bd824017d100
350	1	141	\\x48acc0e205c4a1db0eb52fd632839d8166f399d6af0821c2190654303ae61298ab5f993fecd3b46fd61b7f61bdf00c98f0e4b0d71403f03a989b78ac5437e80b
371	1	83	\\xc156a6d9927c074a8bdab750bdfb05ef44536a618e45900268d0f1158f37b2351a52da2cf89ada878520e527faa5c37fdcd8ffeb3575ad20542dd39bda61e60c
398	1	378	\\x463c1e9e0153e201356369e51f11e2b414e9c4df3c38344c407e5217456e842c3703c99c1a04fc272f8ec72bdcbd4bd47539732ff1200aed3c58e1546328510d
71	1	325	\\xbb3afacd799b9bc22fc235d24ee348c31702ac123214d1829d411033f8d740cbe2735965ac0812d4c2cdf1be332e7e60f41bee49f7fc378d4c82fb61a3881c02
76	1	214	\\x03e82dc29263da71281526613afc1dadde71fa3bb456cca143d50ebcf27d8130a2d70915594308ff88f1a88bcefbfcc1a739f7d2466c6c68b768f4e87c37fa0a
82	1	11	\\xfff12c6724b3c933db1b8c1c52724bb2946c3d64314942cb46859424325368209049eb8cd237d1288b0f60d0b74127f0083e38212edde9cecb63e236bbd79e06
89	1	59	\\xa7674615a8e8d9623a7fbaa0784a758fc9c9b48b5a6b60d0b0951ef40bd4aa35e2da0e49cadee8119d5c98de38422e1f438cdd4643cc0751a5dcc91222f5f20f
101	1	52	\\x9a12ea59272c1f97257c006d2617128e2d3217a60a28daf8c90c6ad8c77b36ae5aa26fbed7bc5391be9a3337cba81ed18f51144b027f0066220f90602d86b401
113	1	397	\\x39fd4e2be2a2c0bffca64beebf28ae35a17dce666a8efc72490ef091e5797c451255329c014ef4c6ecf76e74f04aabceb31bd363a790858d1605cfbe70113009
116	1	211	\\x6ed268bf52b8f7d864b4e05be244948511546e886f2c9c05731ec2c918d3444eb035d225f0e4a7a502dce16283c520c7da2f0c73e9c6c7f64471e4200c7a810c
124	1	398	\\x788371e5026c1371729fe858775c9ed86184728ff3ec6c5361e535e3446c635c3d10e198f362dac1f1639c275dd4638a6a6957cdea798dc60072c572d72fc30c
131	1	196	\\x99292171dc56efc19b4974e5100986cd2c53e7b2937881ec6515f199fbcaff11cd0fb01f70a862deda0118ac847495d828171dd67a6318d15fac5abf8ea5270c
137	1	384	\\xe7994eb3ba766637d85db5046a516bd2599d793b32e0ba648367fa93257e199f810e6599323bd1bd451edd1f05517304238a653e62280d8e316ff8ec8ab95501
172	1	266	\\xe5f90820929bea5a7c824a6bf1d207563f519440691c37d4a201f8edd4cd7a6fbc0f4e950da03e3ebf023dbb481f3bc1dc7df5fb2d058d224b384ce7df8c1606
202	1	10	\\x8b4ea1d8594540ded49f1a14751fc4e0312adbd5caf841b81408ee983e629b2d84ffe931af8859851f2b5c0b6feb62bda25f56d4519230bfae57aa6da4da9908
222	1	255	\\xf40ad8eb505d1541e0102ef44bf2fdf6e6769fc0a037dd7a0b70c4ef3d059a10050c9340e0e3b46d15259be3a7d2d0f7668cd4b1b1f3df0e296a5b64891ccc05
243	1	25	\\xea228cd8b93c88c0dc87a3de0e82a75a6082d8f2bd74fea2b834f1dbfbcc1a03088aa1be45a7dc5c8de8855664d941b50383669dce957a1bd0aad518b3d32e06
272	1	411	\\x7e2d89f1a50039bd5fec45e36641ec0eb54a29decb5d86d66a8a42e05cdfe7434d48f5188312381a16e7f23f6d23c8ddbe197b834fc75e9f6358dfcb2c4d5b09
72	1	243	\\x0326808cce230c1de8f9b6cb305f626ac9a88a93776c7da44d7e6abfd7445f0ed56ca9ca421f18bb39bde5f21bfec2ede424240a8b6187a9b00847816159e606
77	1	95	\\x9ad3c7a6c233c3b43087d2935fc24ae1a35c4e5babc3176a6883895537f697dcab4c33c6c682a30e4374d4af2e8abeac42110a6372a4646c9bb7894f59a3eb0c
85	1	298	\\x0fc85872eae1b482e756dd854e0ca10278b81f85cae1143875181919b57c7720fb4319373776b7ecfdc3368e355b7104822a02aad6326e551c9f833c4b8de901
96	1	49	\\x47fd50277383bc74fcbfba4b0925d28f1cc7e656882a5ffc68f71ba535e17c12bd4394a0a3d633d862dec8308a470af8eac800f44c1d6125cb50fda64a572906
105	1	131	\\xf72737f24a507fd0484fcf728e8b9e4cc5e209dec45286c1663570a97e36e46749487d30f1449ace2ff31cb6ccf9d3727c9ec9b45491c61437c846df7063580b
112	1	339	\\xdf044767e682e09f3d4e9b89b9c127197fe0309ac6ac3798d07cadd519f48785bf1082ca96d1a2feb1b0068673f727228f0265d023bec2f52dc1b8abcc90a507
115	1	65	\\xd6363b660924fdf6998c198f9629b87f660646eaf05e1f0ca9a1b22a21f7158bc7afd8671e412f7c805cf9c3c34649ce57fd9c7406b4003baed9bfbc9f3eda0c
121	1	127	\\x435f8b9adb24463c35b0997fdfdd105abf8c20193742a0ef7b6730b43ee219f18cc58a599fd3cfeb6e93ca7fae06241e18e63be85cef9ecdcd1d5eb36969f40e
130	1	121	\\xa3d055b684d416b929e61980cba632af4a84125831e93916266cc6331eaf3ae677ad4cbb3cc7535833381151bbc015b6d1bb79b92626b4d75f04b828037ed00b
136	1	302	\\x131de70d1a7a288d6227ff51e93b2fd3c1a6c7cff9c84e0d9aed8d067dd5a8aa1ed7846131dd03850dc2df02a8e03d6ef224c9d3bcaedcc675b42bcdbdcb3e05
168	1	55	\\x620d1dbd65889f02351593405cd654f15b50c56c8ac2b72fe0c9fc787ac47e58a2fa0d12a11e94d588f0928829ce55fe4656de06852bbb820bd19b0c14ca3108
193	1	19	\\xd9e5a6a99e6a32b05a3408b3400e7611e55cd89b92f6cf227cfd2e304a8d8dd486f41a03339cdc2ee958826325d20645575d65681f2ff45d61b0c37f7f31e906
211	1	249	\\x028d0ee3112f86a012e18323c199bbc4eb75d39c756fb86465585e329b286219795713acc7953d4eee2f100ffec9bffdfd8d9d016e74d3fbcaf00529f7ba4506
246	1	348	\\x5be20079e9f1594d235112e99957ba7ac53d219deeb55cac808999d8083ae3fdcbf8bb01a848088eeda697a21aa6e56a151b0e3571c691d68c62186787092a05
358	1	157	\\x1c04a44d37cd939cd75ed0c5cc841fc1b2adffad34fd317c966a75dbaefd4381e86d118ff8f951ec230677340363bda076c31ebb46cfb9a308c40a33cc74a10c
390	1	107	\\x1b3a1106f04d5d3ff82e58667f80734bc15822994335d7b563327eec4b9111623a1e318be5b88b5378411d331e29d2d1fd4e8c03657ea2a0920124e29806e105
418	1	273	\\xdffdcea2804bf9bbf37a6cc0a5fc793cc6a0452e81eab4b2264daca6c337696e06667390b3ee0ae984e639d42e72ed8e415c759d5dd17c95c3a4aac7a3898702
73	1	193	\\xc97c528771211671873088502829273227aedb7fd61969c3ea6eabe79ffea92159b94101f5abdd1478b45acd8dd2d967ee0e9179f02b473060752915960c7906
75	1	56	\\x3ca10cb2f4e878d602333d348bbef6f695bbbb102d3ecb4c6bd637c3a5fdddcd0d72a04a1cd8608549276de2e42cfa599423717ea0cc9acc7223c7878fe07707
81	1	6	\\xcfa1f29acebbdef4aa80d12b139357f015402f2400fc587da1f0c9967bbebb543ac402b9420d4696d55e0977d466913ad40f41eddd9c1e23fa99195e549b5402
90	1	344	\\xaf7d0ae9ce8c3271e8c1e67c3ec03cdac58b3f364f4ec2adbb1c5970060a27153ade96044f1e8f7f7d5480c7ba1f89eb2f3eef60c981af6a47a5ac677ce19c03
95	1	51	\\x8601b673e7acb160a2abb1c59c9693415ce9b0ff7c47523bd04ca4c5d2ffb12bff39ac42dee5bc577d6738fdb3109530a0b0cf2d78d78e599141b693c1ebfb01
102	1	291	\\xde9f2239c0d133e2bf3127bff32ab21e9f997733731485452f8e9e93b7a7f3d9aa43b2760a12db8e10e941f64f881f3785504d67c2ea34d844a0c190e455030c
110	1	380	\\x0b4ad50502e0a95f9c5a814ea1d133e147cc0ce753f855086c48c154038ef5ead68fa7f0fb90de441c76602c3a5fd8e0614167d32e51d8b39c7ec7709242f40a
119	1	367	\\x60d7b6a04eaf06a9b4add36c6a10f50394dc9f40a22c9325acb7da4f52151c9f22b128307564c186b3da1cab98d8528a3fc04d91efad04a07a81fc1df13c9f0b
133	1	354	\\x98464d6eecca03a93a6ddd4349733b020a6690fb7ec94616ef4d2bd176bc4dda697d4f13c2ce471d5d559f24e4bb4e74fbe83f70f37ba70aa21feee462e5c209
139	1	355	\\x80e946039b77f2053af6b19d7ca1d242e41e68acc4cbd44ca4d69b9c1aa4172c7cc81bdfca7948aa3eb464bc24ca82fbcd730c6db46d218721515203dd56e904
174	1	12	\\x2f5d8f317d30c6d2e1b39ae840857b8382ac1b7229b09470dbc1b3b83dec36d0853e78416957981593bdbd09430dce04cd17e761cfd944253855bfac1c77ec04
203	1	160	\\xf8d81974f1aa2e079c66d72431b892a8ef694e7d66f3e43c3b82090f2e24e7a9a14c7b18393bac74a73541b3df07955f105ad93ea0a18434a8b6d9b9c7461b07
229	1	81	\\xe9a4e4e6c8663027b7fadb8e5074c3302df672fbc8f6431b31075f72f642de43f890ff46b85163b96d92f68bb40af09fd89b5be988ee212e0f2078e5f60ad007
257	1	364	\\xf3085ada3503683c7abd09ecac78b364af6fb868ffb55d78decac7340cdd2d8927e66e8469b40f6ae8fae152de68391c270bff3a642e209038479c28af76b101
284	1	47	\\xf15f49945ba9d75c96a92f9e6ccac8cbe319b0a49c205353589577157615e9165440e4bace47b770511cd06a7bab21777c90a606ea0f630cc0f33e5590ef0f0d
325	1	215	\\xee6ffd9f4d74dd4ff1ece514e4796d390aa9c842030d662e8bac0b4dd85d50ffbd057596817a9bdd06e56f31df1abde6045e8409313d03de3d43052411728c0d
338	1	27	\\xb0fa8f955f82c08f9a4518662308e2439c0211e15e1d4707ac0090de327babc0d0cd59fe8f3385f6693d6a9153a0ec80c0f4bbbffcc4f3aed8bb223481aa7e0b
422	1	346	\\x7894d1f0de4d02a5a373a60ce0068683a7d77dc70737073b7613fe001dd21053e98d6436d501be9aac7c046b3eb66031e3b94a16ae9f9a7d6143c17d6baa7909
67	1	120	\\x0bc958f3f38c8daf2e4118805f8456aef73081a6abbe8b0d478eb2c732e2feb42d66d2e0432d1809d548f3a7a3e68622936671078729f4a612278a35ba18e603
79	1	102	\\x60404845fd2a21aa7cee671d8b69ad18b00255ba1eae659c0dfe1973a6eb4e3a550a43c32b40dcbdc8cad6a0384145c148b7ad786009ad25533a5354a18b1c0d
86	1	375	\\x6af94902d019181df240f7881349a91458fa502501d2a378c79ec27a476f062a1658383dc3e5e842bf9f8170d4a130ee1edf402603e3b91309b9404ddcf4520a
92	1	155	\\x152e1ebfbe8708e45ce2de2f876e8a5254b11bebfe955e99cd71bbead9bd42c644a0bc196df7cc9925249018a57e2049aff81becd7b4790206d4b7b412e1220b
103	1	272	\\xcf1ede146b8cdd362eafad2e8241ae6c74f34eaad7f37d02d84d6208b25eac702b7462a89b8c29b5fc9b6725974f8f0f2dd6d26a48d0e8d3f0b14cf5f9866407
108	1	203	\\x079432e3b72db7202705da84472ee477adeac69f6724f4a52728b5f87c3ecd2786ab07c5f00b8ecac2df0d687077b201b9af7fe8cb84d228195c17ffec22e00e
117	1	132	\\x2ea4c3d27e9d391014502b7c26750a36d112a0fc070c5445f76e99c548912d6568802933030595244e1610c0e11ec289db331f7cb704f0afdd98ebcc5790950b
127	1	265	\\xf47da7681f9e90a19e4bf6f871a7e5b78b5967f55e48f4cee7194f603025a8b4b175c288a8957a685cf73777be36986575a7245b9089d1bc5581c0eab4a8a707
135	1	280	\\x7bf51cb92dd8abb0aed735cab4fca8f50c03d1844381b600cf6459af6eadff9b72a9dd2e61c3e01dc5a8c4d788569ad4efe958e413053a127ca9368cd0ad7e0f
143	1	239	\\xb2315854cfc7dc1f7229f6e08a8098efe68a53816233432c9917136b36f273d8d662d143595f5801e34e24dc66670f8941fd8c5a434830c332d13cf2bd336a02
194	1	163	\\x9839fd085d072e9cdde26883c9a0a6c59bd4276cbb91bd7c67817e83a96b2bb0f2e2c9cee6ece4c69c6a7e7876c89a47939e6b158abdc6b1c7d758990d13e602
217	1	71	\\x2461316331a576f0eda5bcac07cd60603876fef1b94cf01ea5a2beaa52621649de3820a450065179f8e4615ef05a77ed410319144ee86a4738e699002e5e460c
236	1	78	\\x260bc321a69150675385d3ba66c2efdc87290ac1439ef15e21580798a855e969bb67b66230189bba8c22c179dd3b7fa38c08956dbb35f797c63383fd58eb8205
278	1	274	\\xef74637e0faa8e26da1905dd96d3353420d7aefe44e015c4b99437f86bd2cb0f69cde456030f7aa1ab5441071f5071aec2d0a4f40b74cc76bd63618b05e10707
327	1	35	\\x809ee71b6f065b4b7078ddfb9c4e09c1da92063461d08b90082e4a5e0c33779b83d715527ae1f6088e4ba00d54d7763b3b41f55e17cd6b0edb879b7106017f06
347	1	323	\\xf2093612125c6eef3e615d8c3e993f17dd9893d1506301cdf50f312c02110e1c8dbb31a323130dc8f97ec02576c99acbe6c0c528eeb16ae62659c5ee99263a09
367	1	140	\\xe7091eb32380a29a5b1cc7aa5a05c51f4b9075113a33dc8ad75a951e95968506f203d47417503362797cf1857c6dcd7ea26ad8b46c5c894d6401a72ca666b007
401	1	287	\\xe068b784e7a8e8e7019fc0136e5c92a9d6400eb8bea61103527ce41e1498ab73ecdb2af19f3578f402550eeb8f044193f7749bd09663e4ac6af1085800f5a80c
68	1	126	\\x3d67c4deee14dff79c3d970091c5e1a44cc38dbe9a13f79ed01eadb7b384bb695516f31879ebabebbe7e9d529889de2796f4f2b5ee8a6cb280c95534c3e5a300
80	1	77	\\x43f18aa687a77317b79e2f77192d0dca1b5e7ed5d69393da8427bb57ff6427d24cfe6b8d12cdfea99bac7f81aa78b6a135c3dcf5e7396ea6a5157ea55bb61906
88	1	158	\\x903e5ef16f4ece1af3bf3fb8091fc9c001ccb2d0fd1226b1555d8cb06a444aa1d01f44c3292ac076a742535dcdb0307b065531a840a7dcd31042754aad928305
99	1	296	\\xacd032fdd8dac85562a413eab7735fad7be25d66afd380d11a19178f5d744fdc15ffb974336c319eda55b72e5c5b79b157a9097594cccad8b93947337a225e0d
106	1	324	\\xfedb20ccfb9d493a31463b51dc7f4c7478cd0c4c7673a5e23182dafdcd30aba74e74ebdcaabbdc5e325627fe4fc644043c89746e652a5ed17ec6ea9ef15b0101
120	1	409	\\xa1fcceab6f44ed81360f37e2ed745e17ec8bf191c0944fbf4252d06dfe93b51122f86ff6e55dc3146c627f2a74bc87a00cfae985217bc8bed01a123f3c84770c
128	1	374	\\xb07dcd7aeb326d0eb01976786f1a096bc7420fe96720f650f4741d996ad224386a92a62e081e51bf0d96abee19027c174572a37a9dd98421a7ea583a0a0ec00c
140	1	247	\\x22aa73f22caecb3701ca1ae0062fc091fc60acf749e3e75a9e9f8d3022cdc9fb9ca0d2fdaacc43fb9804d12a63680bb16e99e2caf91426de9d53057d006da408
170	1	195	\\x277a247be290ec5aa9ae372cd2839f0151ba9b4762594e72675ecbc9c88267a0856b771d47988e5588ecb1de49c9a5982b5e9fda74c2e6eace55d65f79cb1901
185	1	313	\\xe426d020e48148354eb514c6956c78f4bc8874923dbd5a67bca0aa129e99d60646ff15056544201b0d92f3596484fcba62c1923004fbdcfe5a3011fbda35f20e
218	1	420	\\x16de73bd3f3c58bafc08b7183d1cc0bcab487e793fc65900b50a132c70d3a627ce4399a619298fcb9ea7a788d78d0ccd795967dcf79cf702edfe2db1c50fa40c
251	1	260	\\xc54f16cdafa7466295cff80a4922681295ccb56366a4f093341847bc3d35610b26231363f55b3ec2719e5ee6d4750e8490b8bb39377b8b796669ea7d23425c0e
275	1	61	\\x8847d4fabd7c922059da16522195333a50c2e03793fc5d4d837c587b7080343baee8b6a7bb326b18ee6c4dcef6fe5345a1a8ea3575f96649566a61018cc4c90d
403	1	351	\\x0a13e75f7d213cc183441cd5398312c3a49a60e4b7324bc7b021ee4d52f52d705a41a192df39506b8590ff32a15328063408bc3f0bd2002c7274036377bbf80a
69	1	224	\\x45b4e48911914c9bb424a0efdd0b966b6257f67876c63a4d2b26da9d6c2f282850a5ce9b1a66c40870b513ae9bdb8e583a5b2d333cb5559e32055e5cd1ec4d0f
83	1	295	\\xeab274391d56be57d80fb2ad166c917d7cf00b675c292f7415fedfe579ecdb2c88cf018b5476df7ebf8aecb99e3e9dda1c67eeb250ffd7a2fe2965704d031304
94	1	187	\\xa0c052dfaa5ef370bb8ecde3ecae0caaf6f7f2e4e7a4b9ed8c12f94811729063d8d36c7974dd569bca204fd43bd242867e86f4159703086d2455e34705d87809
100	1	314	\\x97760b0f3a7033ece57d8455eda2dda058a843efba1d9eee377141fd5dbbdb9193b1d4a707e7f09260b4c047414222a9425fb1a200393e96b4a8badc81b95a05
104	1	114	\\xb04c2c4c8e1551458580613f9d5dc413b852825d34333fc83599796730bdbb50d772212719814e24627048c72b0a3460e2cf094a5ae81f56031233ac3c6c9e01
111	1	412	\\x65c1a5adf5e51e47123ab5d48f0fe6bf632511463c87621c88ccac874a94949bf200ae5b68079ce8d888edd330ef841089d7dd331fa7bd1f9a994e274938a209
122	1	33	\\xdf00a6fcb7b78605a1f5bef2cc63f4dfa0108c4e3c33878170c12116655314f2e38399dd7ab0fe73af02d7f040725e788a149b5afa52844e8377f6e12072b908
126	1	340	\\xcd841953b49f3b93742f8f1bd717c4c857be94b74d83dcd30ec19d58e1d4dce120113aaef5ffe8b58bd2a62d624636790d111805a6ff9b59659daee6b7a67c02
138	1	294	\\x0cf02f9e96bc73f912fe406e364d0d44fb633b2e61e7e2b93883f85e696eed16af6e4b44622d870dacd4816189a45d7e1fe253cea559153007ebd58eacf39b07
169	1	361	\\x316f929a62c662d305cbf462f68f59bdac6166558f28a6f4ba23b9c213a9a1ca45f6b86f847362f6b3f37035d0df4dc2d4bcbcaf27fb81be6f528f76d933560e
191	1	84	\\xe471a990fc6ecead013712cfdf073aec7dc2307956be7cb1f6e236705489778396c7fa4cb806c6b8d7062aa626d27872e2fe7c9d8661432313db3cb7a988a00d
220	1	101	\\xd367d15b6fca18f0b932ec0bc088bff8ef4b78cb3d5017835f0e57b2623ad4186f3ace8d6f45c7e19bdba9136d73de4d881d017e5221c8b33b7d00248347aa0d
247	1	365	\\x971be05ece1ff72d4c073748afa1696dc89be52b77abdc79efaf961e4214064879883a648d661c03916fee64705fe4d8108d1da8c73c31f109710c819d732c0d
296	1	31	\\x44bdfc8263a47b397c5961f8e9e31065b1cf9e5cf4c25f401359ca68e452a0b1cd024a93495239e6e94e5e24a7a3cc4ca08f5c813f3f8f43515de734fbec3a0c
330	1	110	\\xfd7f87c99282f159a43e456104f7c1bb2b30ea4a8587cdfede9783c76316f3d486781dee24ebf20a6f7ce83c71072bfdcc59e40c9bb1337756ff754eb33e7700
345	1	333	\\xc331e7c99fe2d2313cf3de329a8be2920cc8acb6e7c6e25acc0de4326f70d890f2da0e5fdb2abba5599c1cd469082618e9f4dc71d2fd10227bb81c8019a7de00
376	1	93	\\x772684aef6a2d77b101d15228d5d684d2a361a41ef9e06c40c9229a9b8f79a533566035e5ddae1872e2ebb85199dab6846f31bc3d844e73dbc33347750d77609
144	1	136	\\x46fa108da9139c9700c01397a56a9f2f5a255737b915bc17944ec42b51b1b9b8477a98b747dc22be65c33f8a5aa7ba3ba3f8efbc61ba11c4b7550f6b616f330f
182	1	135	\\x7e36dae551f021881faf24e46393511d51abf45338402de12c1a345eefeba40418548e2e1bc52c29777703ab213366b71f7fa63f63678efa4534f0562618ad04
207	1	204	\\xe23b57a0c4ff48cb965230d3c73e9c5403ef5fbfc52b517ac9e2242e87076e3dcbcf48b2fa3191f3c74c82ce349215a911a947098854ac4c6d30beae41b9070f
240	1	234	\\x205ff865e35287c407b64b531fcaf8f261ecefae81ebd6f60d877427dee7aa79297591eb8b107276c143b7dd61c343ad24306aefae028ffcb5b9796ad5b33503
271	1	169	\\x240cf32df8ba2a00f11411d9961d1a62785f825631eed3248bb0001d7044521354c38a3b9142080471037b05bcb16c7a79d383853c8ced3b1d4a459d4aa5f807
300	1	328	\\x63aa66aa6b0212ad8b262228156aa479503808651b88e57b6da75dcefe5d963f5a2f7bdeb2f0737e758728ea8fd5d5e3199d9b1d69fa7b73743428e766058003
342	1	408	\\x99519378d1afc00d1b2d209d9447b0541831bde98a15700d9c10f786747940aa29c3246e43c6478a24863232d9c86e3e2f10aea0cf40476d9dee44023afba00a
364	1	387	\\x495521d1a0ede27e50944e65d42758f5689ac011ee456b5108e93e2696a6da251f5386eb6b5795f9b8e3fe33d36292a5d7657c957f50907b7749f622aaedcd0a
380	1	233	\\xfee452a0cc9c58e729fd9213567abb78bb7b591546096a9259d898ea5209ae67902455d3d9bff9c0e931daff95f33785684a6bd08697086854847cc89a184402
394	1	28	\\x9bd319c3c4ee715d66c38261a76894ebcb246e844a19ef1584603b43b1b344b69a7c57115aaeca77779aef4036be9637985ad07caa9c355088d83b5da78b6301
416	1	4	\\x43c24e547ea2cd5084e6e5cfdfed8284f92f743745f7ca15f4d50f8905a93dda5ad585228cc61150d88e9f33a146eb7de9385c75defc5b8ca9621af54fce8701
145	1	133	\\x488b11b836993c383a34071e7265cffa7f6da341a2f46f5024a06fbac861a8ec66a5dbca7ec1af5a927c26d52e58d8c405f5506cb9a0dd9654c66bb9be20fe04
192	1	388	\\x3b3c16b7407eddc0e8e65deb204869520d50e2db61218bb831968469a4c700604097b9cca3b596582c0321c7b8d49053aeff823b3ecd83949952c66bba0fd90b
227	1	119	\\xfe82924f2dfa5683a4680e70ac9875f4aee0d23a296b023644d679500db3b6e0db7938c431b6ddaf55885a36f3ac8b3b4cd94e83cbba65ef4353d722354cb80c
265	1	162	\\x6be7cbd26ee50a38dfb0ab199b517d37599d7eff649134c93d95b1c15be611ce16d8ece14266dd3afe0975824646f9e38dc2162bf63f62bd4d4f2d32f1280406
280	1	335	\\xabebaca9e25b31dd85a4179ca3247c62b5c03382d44939d30e52be792d9c653e9941d1a5d3bca567094e3dce2dd7df6d87525691e1063c8a9906835844366202
303	1	352	\\x305ae294c63b04fca27f4a36267c1570c976890b4fb5a4ed818697ec107e35704984ebb287f5d09fd5578bede8f302e9640954f32e59db741454c94b0cded300
331	1	377	\\xaec808a6be09040fad285c151ee58ca30dfad7b3b82a910a353c75ef2872e615d0f4dac5098dafb1a76daf982a52c9d03b925e435a07af9313a2552f966f260f
146	1	371	\\x5309a956957ae9d9e3e68cd0c34a06d180e0792c100b0128a9430a9cb1633aab52387867ec3e33e90607cbc8a58dbb6a0a34d9263737080264b0fee3daf9e600
173	1	22	\\x00c9d09760139fe5cd7706c147f1d8e9dbd19be9c8820904c909cec58c151880d0e53ece5730fefe5df93f3515c2f6cea4f94c796f1bb446ad6ccfdc068c0605
204	1	370	\\xd09e1d03c49bf325506424b5994e26d5fbf7a4be295e89848b741a6f5accaa661e57723dc5182d23c9e961922f7b39d05a4239c606128202e53b6d6186014a03
230	1	382	\\xbad0c3ea380ee20fea3fe4081b7e48d0688a3063acbc3c217cd9f9bf24b2c85db4de7e5c2114284323b4013bb6a224cf97e62a53b1e34dbccf2a0bbec92a4009
258	1	317	\\x5ff005f53a853eeabb29d7c59023a0d1ea70cafc35f1a089f68a4e4539af604678701766deb916b6bcfe407598ee5a9d7cd37645866b2e965c1ba2d07125620c
313	1	336	\\xc42bd99f1c0091225796a2915d1dc0910b264b8953133cd1be25fd05648727b3fefffe2796a4b1a9fe849613ad8571b9d329efa6adb0cea71676c18c3d15320f
340	1	2	\\x5d5b2d06393af1475f2609eb2d022de24842a1b8aca91a4c6a84ee30eb7f47447ec0f827714ec0544a260526b7fb96e7b85c8b6d701cb1055de3ed8986137800
384	1	213	\\x764e7413ae194866ae74343676ee0274caed97144e37038519e57c4ad4f640ec2024528a70401e13bc129d793d0adc6dc92d9fefbc64b51a23287feaa8593d0a
404	1	223	\\xc61bbf06383aa75a2e7e60dda740e42439b1f7083d72f3a3395b5c1aec594113c3ee4c4a96ea7f799dacac733dc526a11d5ac7e568b949bd72fdaf5513a4d50c
147	1	161	\\x580f710b4630e1b79df5fb21d33695821822cd2a7a4cd4e01d0ef2c9a20770fee39706ac81869b7578ce59d30ccb8b4758ff9950fd8b80b14594bf8e11d87106
184	1	246	\\x47b8f18c304a5dcd004ca5931c3b13561c76f97ac9b700ee16219313a62ffd8eafc3dc0f6ed99bea8f63c00baa7632b27d8176d6e737e2c64f68b50e5e0dfe08
219	1	166	\\x8a8232860847591f37d76168c73ad61cd870308d5a40eb652f74e47bd7234d3e273e25992ce26349ebb9e412c64eaa7435d5c71c0969cd897ab6d0b7fade1b07
245	1	248	\\x99407bad77d09dba84a86291b1a0220fa4b38d8c28a638e417ea59fd3343819e435c75aa36a172ca4e2bb99da5029b07a1ebe3a24a11f84ed48d1504b9b1c901
294	1	407	\\x27a8e1d30089cf08a61fcbbda135f5b5ac352f1b6123575b611ca6f5aed1b73bb2ebfcc086b483799113cc45c0cb53581640a174dde46faa5874776ba2cd7101
304	1	225	\\x24f8b85463b509abb2a0a27a24f2c6ab5d27ade41e24a49e6b567b34ca6e18268cf0719763e4df25e1092cea35da7769b50b5ccee235102808b2c35484248008
357	1	186	\\x5df8b619b316a29e1a764451869f0626d5553dbbf7d04bef568128788c6c9bc1c44884d798fa4364a339d0af5da9f64472b9a16a4a046e1937b7fc14bcbc6d07
413	1	177	\\xb56c1b207b77316aa7f4a9fe48c1d45b1eeb7438ac965d5b3835d65b0c25bd3817dc59f9058e331b60e18e2687579a09fd0c6e8a168319e6712ba400574be000
148	1	173	\\xfefe7ae92be4688345a5a93efb5acfa8e724d9d878296a871a95cf310ddb9d1676334abdba4178c14064f5871b29b86ef9ad331011d9c0819dcae6743f62e20d
195	1	289	\\xde3e79bd4a54dd4beb247fcafe7bb4c304d636135fb1cb4606e8a69b0a6d43802ba25e27c93bcf294844a3d529bb4d3d1ff5776c111bf42a32fa2bd2c5eb2d04
234	1	176	\\xdc1c009466c4deaac9719b06b90f7821cab36e79ac1da723aed63859c4315d3c10618affb7066ac8770994697bf0c7f373be327e87af813f3d2c49bbf27c1103
266	1	8	\\x9ed32a2074875b0ebeb7ad842041a324d76319923866b508bf9464f4b644562dac09cfc9a66694a354a6d84e40b6b200950aa638ee288f968a1f68c78f7ea607
270	1	29	\\xb6b1e51fcf6b4333765ae267185da2150bc5135fef2a0d84d41ea363e58cd7559455d8e12c40f91965cfd203703d89f8491f2cc314b5d856c944cc616a2da600
293	1	281	\\x7616014de91c62f841dc40b60db35faa526912a2f2e427c85ed4d83209e6586b6bad2b6995e49bfff84948f00ab39688bc1a8efd02ef0516ebe16acabf67c100
322	1	343	\\x5e4626ca392358fb91f31557d146d3443676431d7dddcd48ddf875e613407ebd8ab6b1e6899904500f25d70e4b498cc43c9da65db2a41784da1ae6923056460e
360	1	373	\\x916798ac6bc59e0ee3386f20e34015daf42f2e7e0922104ed0d09a557a83142fca9a8219bbc2957e67dae112d8bda0081251367234d7036a1ef6501f96ee6d0b
408	1	159	\\x0f872bc7a52c568d5f0662393ca216d6191c42815cd2a6d1ccd855e91dbfa60c11b234dd2acf87360dc1cbf08770f1ef1c715bb8f6ac3d02d76596272b27020e
149	1	330	\\x7c999034b9c8f66ff4b44d624681c9b69bf7b955362c422b7947820b45e46bb669b3d9241c27f3f5623fd1efb01398763b7178ab64d43fcfcbefb5166322e005
179	1	200	\\x2812eddafe78c2601706d763e8d6848d470bbeee996a7f8e906ead7940387ce863d517b531b107d22547a89294a3865a2714633645278c3b715b805e98df7a0b
216	1	275	\\x054c894fa866cfef14c39d63664880cc1d222fb0f1be607c1b18439eb446d13c98c982c36b440e5349d6dca3577afe3ea7894ed84ef0280dd2d666aefb59830c
253	1	178	\\x3c1dfb65c0b9ae79e0b6c7bb52909cbb54690396d5c28a85efff722e57e43b5fd26db783d20b66319729471e91343e3b52d08f15fe1cf1d07834221e41826107
289	1	319	\\x97b623a2a3c97e07367b2cbe1474405e6a3d1ce61b92c36dc2aa481c92f66c31bd3c0e15fc2d457fb01bcf9c0dcc08efcc55b48600406b478d79e3fe99f90f06
315	1	245	\\x2757ea61ee11c155260be46f91ecfcecc6e3516b483262f79c68a9f770fc35725af523676902f44d13d5af521a4573bfae4664e21cec123f3e9579553e70c10e
329	1	206	\\xec1559ec2de1763e9fbd74ec78184476473b76f6c246418ed0383fdaf95ac570f4a3b996ecf9e30db4d16b134b56b11df6f0a24ba7f36fb04e8692677c07cd0f
348	1	202	\\x98160808c955d32c1ac4cf616d5368920725f34c2f0911f3dd778d018666fb8f6447d492cf69345c2d0b0e9ed992591dc5da86ba577f0ba1468751f43874700f
382	1	392	\\xfe67b001ba86dcdd3816b2e06f47541ab2646d146b9c4ee37c95afcb077d5b400b850b4612a7d509786af0c89ceda2d2dcae97cf07538ef52374f949719c9a08
411	1	253	\\xfa86e35cbf4fc5c222c609f03cd3030f0bf8672e36c9f070078d6150950ac45d945b381f562eac6a456c3afb5662ff6b7ac03beaccd814464893160ecab6c503
150	1	64	\\x8f897e92e1cf53935ec2e9f106dcc910af3c10595e8fd7c8b1a21d7dce3ed58bb3f5094ac478a2e3a3dcf51fd4b47a3d88a7155fbd404ebe54fb87152c100607
188	1	349	\\x9a5e6fa360507831e973e9b79e580e0d8fc30dfd167197e16f2436ce74c01f3f3bbbf4f94873ff65c8fa80ef0941163b8de4d30eb7870f46760c27c712938107
228	1	17	\\x504db97164b8c62b1b81cf150d354b6d9f7b29b59952a35d69d51dc5e41671b98dac8af44d941774fce9e2e37980a57a6e419e375c86186d2ccec9de8cfe8202
260	1	353	\\xb1004785dd535d0ff0c266a9d69b6193f95d5baa8309cc568343b78ccec32acd401bf091394bcd1b8a25568cd23f4aa1b0b98c31b9fe0a209d27e90753e9790a
285	1	308	\\xa6c84747ca45d686911dbb79720e5c482e128bf24a3cfaf846be4af0d53366bc7ace244ab40d369c532d32772005627f3a6fb152ca72de0a94d938558e5ae403
309	1	383	\\xd5e99eefaad9bdd799a27ebb215b61b47bf2a6ff4d6eb7853ce98871776f7b345937d345ff40f8dacdc78423e341906d38a4162038aea79f89a9de387c86310d
323	1	124	\\xe0b519a93e56c441423e48b353179487e9a402938c59ae0e461e5f608a70eca3b8e81fe9e8efb627d47f14366fe4266055c66e22c1d5a297a2b073fe1853c705
369	1	85	\\x4c912300d2972f5569f891f1748bf848c65f8b99c24382b0cb24c32c598e792c71770b6b6ee740aa6e2df180f95e91a0aa220eba57b36093b2ae348ada363607
386	1	50	\\xaba6e9c0b7a8697a3fd222bfed163f0fdb655c7d29dec0c3c926f8bedbe57bdbfa2b84e16781cea73aff24b377fc89f194c082a42192fe368429b2b31497890d
405	1	16	\\x9b46b74337a87cf784afd7ad69a1ea05d977729f53dd6b8633f842962b9225918291d44fd64a65e71b0854d83330e62579d848158ac36326f5e671ffc4562305
151	1	73	\\x566f3ba1e3db924bb3c7a8536af801baf30a711fdddc96c287fb3461002980909f14889fdd6dfc0e8aef3529c9452e25b1458f3378ec7f0d8d9c4c5514c54904
177	1	414	\\xb845aa24473de6b0fb073f122e7f0682be8f8a2688aaeb7e9d66d37953b6ea4ab23efc8a0d4da28fadfe56d0ca78ae9a5306925a248689b65848f4b950cafd04
213	1	305	\\x8c41c9788b3f80409ca0e879f440314ee828d557744763bcffd193dccdad21e91baac087277dd5dbcce51a156819d9fa78dd0473122c84a219e9e8df33fc7e06
249	1	395	\\x11027f4d54eefe882463b4986f33d357d104a0f98f5b0746f59c5d0812be2df1fcfb4c081b102e9608f16631e43746096156859e7c691502c939ef1e66c6680b
288	1	60	\\x71ed3a82ca546e618ff6713de4f64525a81c107bf2f9363d06da2c9e8b52f662702ae657b9b9db1c2ba58a13e99057ee12c879e6023bcdab041ab37fbfa7e60a
336	1	237	\\x1d0a6351a2856f4d8657f57214623ece5b9d65ac2dc7e32311c5d7682fb47544227453e51f56a7e580b5a3dfe3abb455dafb4edb609c3a4ed983cebe7bdd0c0c
368	1	290	\\x58978428914b63f36a3f8a03b65c9e765ed9cc96157b83119e89c2d89a174b7b287d64805ce1fdc6af738192956d4c86fec49c6f21b3117d432bb829d64a4b06
396	1	299	\\x9d25041c6e0e08ec38938affd214b9b298793b7e2abbfd1a1e423530ea12a45120a79170fc6dda91031dab92c882b3d770f68a9e1619b01c09778f27a9e8010a
412	1	104	\\x4dffb6b58ac2fab8eafb0fc279f114000c470bd665db3bf9da561a7dc931513e6b5015bec88f5b95ac2970a4046d2776ce6491b6ce82e99e951ff1a5323b5c0c
152	1	165	\\x09e94a5eb6f1f1038b1f248b24425266281e1a742b9c15d530d89c81fa7e5c6469d730d948b23608597c48b0159827d4ce309c1e678943c06bd93a056370a906
187	1	421	\\x7dceb54b7de122b2f2054f290fa9352c004d4f7f77c456876e0b81e6cb43f5beaf5d63936017bfa329b16d3fba0a4f2d7516a0689bf7b12068babc0c4ea4de07
215	1	271	\\x3b091408fae9fceb4fab8766bf9c44d8560d4d6e37a40ccf0fcb4048b7ddb3a14fc0062fb6afd85c0143a0d7edc1d2f2d6a42e7a67e13ddf50b7fd6f1db18b06
248	1	401	\\xc078919edbd0169140cdab2400cb714f0b018a0d7de35285a2ead95014b13dc5a55ac5f2f3dee10d746d59a85430ac603da701375cfeef335c1e94c2e6510e0c
274	1	99	\\x8e3ab6ca4e0df52fd41323897286f75f76dde8a079591fe40e7f8595e9e470a1c2b0c3c04a6b0c1b3495c0d02f7e68651c355bd74d1308eeb10aaf7354341a00
286	1	153	\\xcc8695c3a3490c8e0271fca8d6f84601cc35aff39469327ccd780e1d73113b226433b8f7c48b1ea59e798f37b918737ad58fdd5b8679116524b30341b546c306
299	1	301	\\x867f9157ae6bef2036e7a4dfd58090be7834cf2e3de71cd9f1d9bed017b30e22521006765fc20dd282e6cf5b8ffa80f9d69f09f70e35d8c53946a17d59bbab00
311	1	63	\\xa9aa67dd7f7713872a3c38bf5054373e8c1625e21c9b9d6c096fe0f5ec67c10f50ba162132021744f12170112dfe1d54bdf96db85d59221c726834f73ff2f705
353	1	89	\\x4d78f34f06b8f77bbfd01fd83e36f889f5a8d3e33f34a7a2ad364a5c2008bd2df7617ef7f9a33a0ea593fcb9c15ecdc2636fdf60e455eb05f9d11707cde9ae09
365	1	292	\\xea0e7b97bc5ecf760bbce44a91f75e4da31301fe373adf00615b850327d5d17963bb9219f61429666c2162045b7f335df8ea708f2e0da69527d2986be863e703
388	1	130	\\xbb0874bd5843b1e5797d9aeec5ad09d7da271a2ec0753435bb40bfe125da0bbb16477c8154e4d8ed3460a437dbaa4b25990b910271c8221dd1b113b9783f8503
153	1	284	\\x9585bc97f7d2719ef332313069a1debe59b50f17fe375012e110ed251b99364fd36dcc2844cdebcb65ecfbca139e701bb53ede745980a4ec08e665406be93608
199	1	122	\\xd299083a7362758d474d4ec35be6dba501b4fe1303bc1262f30159526f666c1fad487f625ea8f3b3c281c120b232832fa5141a5284d1e6ced55fbed844492804
238	1	415	\\x4059fdc2f76314880fb1999b6a1aae79e01e218e42a2780389a8bfaec940c8d8091d82ca338ae6d50c94e0567b1589f58b191df3e6e2691a8fd972549b2f870c
264	1	329	\\x78f069b85b4e8bedbdde4d001c9399cc531bd95fc8b9245220a34dc1ef4864f854ae0449bec58e347f2fc20b8b016bf59078ca7282fadd61ee3916862ac01300
279	1	372	\\x56f37d965bbdc9fc3ef20f33fe1a5e7d0fe6f710a2a7d969b452f1f7b9d692e13afc53f86d62479ba964555e8fc4f718b4b17b04b065396819bb86cbfdb8b601
341	1	182	\\x619fd848f09b8b2fb5f99807db4019600855eacecd9b23e04af5a7215d9226e8cd475f26bb1b1917603d9433d84bbf233acfb47004508f3665baa08c7ac75b07
361	1	240	\\xfb2acfb92bfb6f8634b20105581cfcc67cb4202baaeebba5ecf4d5f112db56b82d4104090f363aa22d39f3ed4fe1f28578125ba67f045a0872e340828bd62604
377	1	112	\\xbb30cf7bf472277dbd51af60dcff433a3cb4bfe7d1e46ff74603c8699243168387f1e935bf597eb31e9d69568c674b08c1990d5a31cb485dbe49c91c32833b0c
391	1	259	\\x38a36acf79fa9584351c8df119a4085ffbeb49f76098f4b377efad767a27ed30941bc4114abff041f55261c871187f0c9019228811fd4be81155bf2bb2cb2000
154	1	360	\\xa51dfa5e78bc77715d0bd03775c28d8f5f5f6908fa4a9bad756f53e7d7a40ff9b1e242b8fd63aa78763b39612b2d3ab6eb2a4fd1d52dd5d997a1a9f4a9f1c40c
186	1	36	\\xf93b5b89e0373c7544935fb4561b1cba8c92577576789d5dde5de00754d5db21f952a3cdff28b35375b21bd5829219d1dd232d46e9ef1758b954786aaafcc806
221	1	174	\\xb533728f5170aff06ec063625c07870dc1a5c208d4b1e306b5ee9483da4e330b154eaef2a1b408797da4ae1f5d987416e5af92bdb6860658297a2ac91b31c30c
255	1	385	\\x54cd01adaf64879a7f76568ae5251825ed6089832a98880f2a35bf2d0950783d50890daaac3055a4f31b31969a1fd67bb28581f4a3595e4b74a53a317ccc570e
306	1	79	\\xcedcdba79e6ce2ffdf39abb80669cfaea7803c901d860a5b2b07c93d8919fc1cb73617186fde3781d51031436bbe8105c3dcc229dc3bcf62af9bf6220711790f
337	1	381	\\xb645e3df8ebf783b2189b56a8a16835f95658e6e39afda0c6e6e331ff79858e2d2ec949c2e6deafd317a16baab140c0ecbf3831371c0dee62d1e15f0299a430e
362	1	376	\\x084436e1e1e87f5e2ff7917b015d3a53468aadf340dfbfbf53cb991030a8f88d54144202586db736959389744bcdd05ea734d020f0a8c1c23def9ccbeecb1707
385	1	229	\\xcca672b2685fbe33f60e57c7a1d68f41582b870c83e29c5302bd40ab89bba8b7ec80a6d1dece9db55f795a251159ee1378dfce7f34cf4cf1625f566c712b190c
417	1	297	\\xb60d66b46826f3fdec3bccb81a054e78ad1cb3d0e7f547a9a75dc7032d9752c79997bb59d6ecb6fa03cb0483b42d8cd737512f826131cb5b8e9a51d64934f400
155	1	386	\\x7b6dd8b13069e7c2441883e75ee7ce3554bd793824f5795ec532c17a5d2cb90466a42f4b6f40dd170283628bc5a44ee907d156d6bd03069a6bf374939a996f08
176	1	241	\\xc9d64248b33c1bf24982cf3b5d4e6b8d26396dd02ad1411cad6e0b90a4ef2a726393309bda1f301112da6ff89f8836ff8e49ccbc240f5bba49818c68caa0d00a
212	1	75	\\xc868a560e0e69949642980539f07ddce82e55b35a0d92fe51f880606a41025118763debcfa97d5b2e04545bffe3e11566c40384a81b8cf9477ef00ca2546330b
252	1	109	\\xe7913543849cdc1d0f367892ec0f394686735c97624f85aeb2e97233812932bce14ce1dbd3b13dbca89f1e58d65bb1465d723bdf7e467c56724979b259949d0d
283	1	358	\\xe813ae99154712b1ae2c2bb9f803772ae56a40e5666075cc8370858160c1b400055af173a3e992300dc63663cd760aa6c17024c954749caf9c520eba7a42e106
307	1	30	\\x5aec87c936ceae9d0a5deba0cb0f4d4d4ff67f73799168304b06b01be5704e0d835faf59c7f011b63137fddb80316f13f0c3ff0da7b09d17e4619968201b410e
324	1	394	\\x58ee579e466d7d02fcd1b47a3a331796c153c6771d9b351443ed1e768b942eef48e91570ce81a4da411366fc3253dec4757f8d5fe549c0dabd7a021709faaf07
379	1	278	\\xa610e4540dfb01c13546041acf6d246f7daea32d3abf020ea01c34fbaa0a5b6c4f50f92aac40acaff148d0d2bd4215b1f3fbed0dacb4d47d81658f94c96cc008
421	1	231	\\x60cd8a024f8c5ef71225d59f23cb02877e0aecf99e16f52008aa2592de21eeb2dae87a0ea39bfba3f964498fa76accddcd7aaad88ccd66e9f8b511483703580b
156	1	345	\\x7cb8004a73247500b8daa065dabdf767f77fcc965cb08225cbec832d0fc664409039a429d8d9ccd8d79434b59c956f901a402c0082b2533edc2dff7e6b787306
175	1	210	\\x021e45d8acb8f2b2c654aa3bdae9e88d6d04c94d380734bb43606b18f01db0ddb75599edb67395c2b2e621783bae3f6c9c617b04daf2e52fafc25a42a0b0fd02
208	1	97	\\xdb6caec57ef79511c5aa9069cf36abb53e21966d14a65a8e95fbbf034128da9977166147278c4d8ee6724efcafbe62f70eae75bcfd96e25d2b7033109d56550f
244	1	341	\\xd0d49f57fcd85cb7db133eaa13a9ebeb437af26b9c412ba9f38f6551c0b3ff08072be2d19a8dac50baddf01a714ffa2c4c76b1cd771dad35861fe62cecbe030f
287	1	254	\\x44d50a0906d2570919bb53ed61e65c4f246dfbbae5ee99029d7cb2643891134654407304597052336f5fa4c67294ee8a327b57a061e7488d7dcb78838ae49b07
326	1	216	\\x2ee3ebfe1b1ff147b1e6d8e1ffb535a9a4801c086edfc5be7e9269c183c2820af7d52404392651823242ff3dcb90e31b2ed6d27488579a55432723f0a8f66601
343	1	285	\\xe250a4c616202a9112ed3878ab4d542519e1d2b8dbd5ba5ab0226baac29484ef565577dd97388e31525f870eb5a09f705e06abb2ae29468e285b133b35211c03
354	1	98	\\x935973dab6ce9d6bf6e70d11a3644814c89ca9ad8ef91a53ea362d72ca2a521f563453ab22d50d297e5f371419a8e12ddfd206af82611beec46683b2e7954e0c
375	1	15	\\x82d8f07dda281963b6de3aecce73c2881834e29ee7063d4b493b1671f7a15b322690d2c1728f47d38a27523473ede4a7dca688b6a7d23d5c21c18da1b85f5809
395	1	70	\\x73ef738f150373c8539b36c9207b3252ba4383ade348eb03345e9f2047450dcc84ada2733b2166c511ce2ba8dbb1015ff4f1926c1ffcd4cd2adb25cda291d701
420	1	293	\\x57623e56151fcbceb833e67bdd6c1750fcc0b192e856c3882b6b2327fafc55bfafcd842b6ab5c8c1bc46274880a29af2b32a47478b3583cbd17117702ab58c05
157	1	306	\\x5756996cfda3e78e33a6c6fde29e640d1f9f429e5aa2ef6a4a8d8026599359d4a92c02a575b66f9307718087c1abd735cf86dad62133d37ceddf39bca8ef8d01
181	1	423	\\x3494cb4094b57986591714ee5fb64698162f52c8a44b4b2daff81a2d6002a3fa9271aa25736f4a85be5367a5d0ac83a7a48418ed4a8e0704e58c4efff16aec02
209	1	417	\\xe19abfe9be6d6a65be89630aab5ded53eda76ab7492952b308cd61c2bbdbf725b3aad2763674e81de8ad97a90566717035bbf21b59dec95a91b98c86cb2a5d0a
232	1	288	\\xd0bdc909edb1575b9e310433cb11ca902dc7b8a0f952626797c8890ed222a83ab66b8b98d180b9914ee1623028d50a8146948810a40c560f78b3c7c0314f9f0a
282	1	41	\\x1b52a618797e837b46728a9ea4388593f1de38f1090b348e94ffd71511bbcc11afa2e193bc18be2b275ca373a3803d431d63898aa3e2728c5e825783b9cefa0a
305	1	209	\\x9c62a35f31d77be77d8ec9eeb41dcf6a5392e9980039269c5536e5880516ef64e789932fc736d3adce011b8d10082575bdc38a8189bf388bd9ad73e7ed30c501
320	1	103	\\x87d02acd9d4045dd545ab834a027953cea0c898c73ddd15e6815fa8f1247c3093ddf8658601aad8ca7cd0997e4ad26c8e53949f72fcdf16a247521034e91dc04
370	1	413	\\x78d17e3d17ce3a66fb4a1b25b58f64fa94a48bd120e44df34dacfc60eea756a450228f8dd40e1391ce211c0a4eb2d96ebb4b591f4820b47cf3860d42431f0107
387	1	406	\\x0ac44e56a0d9ad5d9b80523e8634e59af8a3b427a801b18838cfc1e920d473ff9fe7a8d39a3ac3350f4af3b5777e9093cd1c4a427aa4a3458c902ee02079190e
406	1	171	\\xf34bcffafc6d638017da55037adf2bc0c18737300e5b704a6d5382a586757eed64798a8ac0d65d4cd653ca2af2be51d975399b42f6c812d2f6fc27131a4f0f04
158	1	192	\\xe284c8728e87d5044ab03f01e748a5c351936005023a202fcbed35b043023f0b8cb9c1d2f04fe5df8d135b66e7c5ac02ab23cda739e4bb3cb8a2a631e46e7c08
189	1	250	\\x17d5a1bfe8e885b133258180142e68126158896e0ba6d4b18a1f3c9f6b2e1d21e274ec15a1f0f045f8f08671a60b51e5378062ef712f732f944f20c425cfe103
223	1	334	\\x136bd656a5bf4ec0359dbf15a3d98d3317d55f54f5ac631b56529abaf542ab8b4e82d784f090e139df0ecdef7c76ea40b255abdb81219ff5a8a3f13478d4820c
256	1	1	\\x9fef086def7a81c47f408197229805b66c3aaf46e663dae688536bf2bfa9d8894cf90c20e5e05109e47b8351dd542abd29f113c57360a7d6fa4c10581972500d
277	1	80	\\xaee2e17e71878d268067fc418d572009e1d9f34d30f94fc85de9cf88dcc5f8e9d5f4c73294dda1b25d0fe95793e8e1fc0881ac2b984083f2e44f2d393231d201
295	1	403	\\xa116ebcbefeaf0996f98bd05aec033df90619eae6212e15d4a67215877992ec5b6c941a149e2f6787415b399342cd9a11c526fa82723df60ea418a9d0b16fe0b
312	1	143	\\xcbd47f0efe642ec88ddc6c24f98871c3938220f716f73b18647906f9a43614564eb9eae180e685f9120943bdb1030947075054ea1d4599e95d07d57e2e0bdd0e
333	1	154	\\x9fbbdc126555283a44e8ef62b8fa2d7bad290db53904f88205dcfd68dfeb627ed52352d4d74d73f6b566b1bd19e33248478f7bbb232c81a21252f7a9bfd5ad05
381	1	232	\\x4add5484bb61583154466f1d4ccedf9c8ff83830454d0425932f072536dacc070ecd370328a708c333153e9de4204ca7daaa7d04c65f968a02fab4f66c92b00b
399	1	338	\\x8bfd99ace3a08c4fff0d922cd6602438d9a92083e40ca42edc5ba11f818088f1cb541e817e3dd03502231fe570aa5306ef7898128fbd8f2664f63cdaa08f3d06
423	1	300	\\xf40dbb07dd574ef3f6d9134f9aa70d153fcf5cbccfb8eb8db5806337fb263932adbe9ddafe89b36e45b5adc0ebbde23bfb2d3c2d533a9c7635915f743252c700
159	1	418	\\xe3b13b4add322c4c23d3ede779a8741f8c487bbb5649e2cc61ee01a8761fb90200483cce1a90678b2839e545b83d7eafc7c2e6059c579df4699e432a8db64008
200	1	62	\\x7c8e4d4ad5718c327bf298e0461565febe79dadedb7457f2af61dec6c853811b8e7e8e0744a5913189199cbc9f5c589e7e0ce692bb3af633ac254f08a6fe1f0a
237	1	21	\\xe9fb3f29eb2c0fb1b90c373a62aacab8196853639179767bd32f6b65de6075582b0c0a63661fd0054256c2db8e68ac54386212eb84c98ae2471d69d6031ff60c
267	1	185	\\x7f55c76dbe29f0c109b6f644af51f7dfe7562566c0ae59081e55af91b01ee03c2e950a08e3abafc6e03a6923c53b1b71d508e9a6713ccb47da895d23c9d84806
291	1	212	\\xf733dac8bccf25f4de53c7fbcb646b53b2a952970c1b731ed332e22feb46e39a11421373187436086410637d6b95120867dd107d30df93be5bb047bfc979f704
321	1	90	\\xa668868743f6a3cdd42d420cd386e726e23af31904aef4cf9861523db2ea923aa111dcd0457bc472c20016fb1e102f4a33a47cea832de67136631df40bc89308
332	1	191	\\x906bd668afd38cd2ce935d1694a7335a29532e0bbb749484a41b023b08584b1b14f2c0078648ab7d7e58ec02e5d23abbad2cb027046aeb9addeb2e1d5f9dcf04
346	1	251	\\xd96c9e1e24275dc2e758027a18d4492a34bde9de44db060bde59fd30ef4fe96efa34f95c8b0b8c33610a828221dfe058e0acd0c3a2b37609e993f02d91d66e09
393	1	268	\\x95c87cefb956fdf5bad8621e263fa3aeaa9b1c893e2eba2672ceddcc2e22eacffaffc48b9174534b0e59f7d0d73c19ff84597ef5a11ad210be91cec9ea66d60d
160	1	416	\\x04c05b14fc54f4015c35aa696ad572abefae9d6bb19ad20a09c13dd26d87ab31633c185164909c097bd01cc6ba71e274b0d85cd98bb614a6e74894a7ca68a406
198	1	318	\\xe4f4b671d1b03c249fceb20d58cf6d1a8ae181c3079bb8e86e82b60e76b940ca9df3fb309d6c6f3b6a84503e6b2038c68a5fe9f5fbd81610cb382535dba9fe00
250	1	422	\\x0743aaf72b3783c5b1f141744d6cae5b1f09b4f70358c9400895621b09a7650dc989c086bd371831da84dec0a452f61cd4589aec86b4bd566fd62b03f6a6b405
314	1	14	\\x473c0ba9e78ad1f1726604043e4bf3fd2963a577ffb4421aa29221b4ff36319b0a37b992d122e2b49a7987ecdaeeb9c8903bc1ca6be544f015b2fc07e9a3a703
334	1	88	\\x411fe9d6c7bfa3036696a52f4922bacaeea1d1f5ce1bf57ba1eda32a6ad49b030b7ea253c514d75d785a3f7bf6f9e8cf774ce73cd492acc29c3aae0cdb744f00
351	1	48	\\x4de38a44cd47bd45e07b52c2e950ba87247d3840d45b193a3866cfbd81b19ff8005128b6070f4998b125311bbbe0477382d87bbac9229bbf3225dbf7175d610a
373	1	43	\\x9a05033b709bfb59188544a7d71aff7a61209c0fda8687f3f24f6505b1aaa94d740e7dd352468c2247e7f004d83927b610e8f5b62b9b8539540059a1d6f9880a
161	1	45	\\x79857d7835bb1ee356f37d6910d5b35e3bcbf509dd350586e091d578c432957dfe9d75f98186444a7a57fc3c6bbab8f3b51d4a4176823ec8238bc93741e9350a
210	1	238	\\xa18f2e867d6d622f24afca60e635db00226643045ef0c4d860624bcc97eded5c927e5a0945e9599e4dccac46386674752d718f3dbd805fdf4a7fb5fdb2f7340e
242	1	69	\\xb63d1e965624d8111b54066ae631a114e1c5dd4dfbf9dc4fedb356a53dc59b69281f9fd8f0765135dc8057c762e6f6728921a302de0c5ee8be8942a06e337f0b
292	1	149	\\x0ad7dd1d93cc373a0b5b885c101f1e79a453532c8548a3f40128d8aeafc5ac6b2938e7eefd34c2fda542f30c7bfc7eab1efb9c241d0dc035a8f2aeeb6350b408
317	1	113	\\xf65ba4e2980d0442823ad722c504ed6fc1ae7bea751d5b0f1a47b7cc1879667e39cab7d748865f10df4c85034be6c68a2565770a677733de7a58ad9d78b69c0c
335	1	226	\\x44b2507144009068d9b4d4fc2270af25b97562672491de42e99bcd5437be304525a3ef51860162c5416aa0e77c1c1c4429fcc00e83c4a7404a844d944b03ab03
355	1	270	\\x9710002aed9bdfece58249f483613917c25057079d9dea7d683b3a5865677848432ab9b4f8ff594e34aa1623d1ff5541e575710008a17e2c55095c7a51b5c908
378	1	39	\\xa72e2decf39025c195eab758d5c93309feeaad9d70a3001d8e8adc2b4798a6835cc3dd9534b6e792c3f00bcbf5f84a84801e10a9f0f4db72e6218d74328b1405
414	1	91	\\x2383aed31054fff1cc1d3f5ce92e4d71788c2b894df00fa132b67687b775dbeb32481686432d4e283857857e8df78ca07435571be097405a98c9d194ae62470e
162	1	337	\\xbf0c755b879a7c0a91271a710f38cc29651a55cb243da6ed1c306ee8d4653dfab8ee9b212420243222f6dca32f9b46d0b1ab0790f0860bdc7e9b2575f9003303
196	1	53	\\x19fa7e20c6dd7437c8271215ec01efa0da27cc1b35d158b04d38fa60ad5c400017623bbf8155c85ccc3317236576b1ae5d1ec149c39cc8a0674eaeaf4dcc5d0c
225	1	138	\\x973492058b3274587b2156047bd491cc9f72b832e8046f837c03155b95eb5e49a41f31752e8079283596fb812bf5ff7ec21d10ca5bd4bc131c8ea5a8b93d7b0d
254	1	34	\\x87af3fe2f3e3cfd7b64e0b6ec525fe87183c37a170fb156d9336b3370eef63c3215a05babc609f73ac0ba52309590b41c10f2a24e2a57af415fefe1f93096905
308	1	312	\\x475d5b50665affb69afb6e05666b3a3e9c35cae0f0e1fd14b3d45eec584de2726c79bfb2049c5e5aa9d001f5c2fbea3adb82b3f2823d7502133eaacad1f6610c
359	1	94	\\xb130078e8ddc6d9bd2b699083f333e89825cfbccbc85b353b5808495e7393a4cee7a7e8e7421e161872c2e0cee15d662d1b2f6f105fdb040a677fc24f22a3e0c
163	1	9	\\x331c999d837406080702165b0d9d40637f0a442853595e625b8436db76ff136bf1400ca58e2cb4d80c7a9963d7ce54d3baea9019b19e45f678998f2ce3cb5a0e
206	1	152	\\x6cfaf362eb86a9e7857852667d8c53ca4e22a40322092c693099b3ce32639cc1abf1cb74b59f3309b76240e3306fe443ab5cf68a88c8b91eec600d45f32ff509
239	1	322	\\x3be63f30015077017c14a3f55805cf4943f699996bb71d7b8d5c79e2f465c508711e5bad2cbabe93dc30dc7494ae37a53669f4f148f0caafbee6a25bf514e605
261	1	68	\\xb8027a314abebfaafc4fbca87360c821e58d2cffa97cdfc4dd447d6b9bbc5db6a3ca4656df50f02ab1ac143ac90ca13a0128450b6f858454283af1d701892008
269	1	148	\\x2fb63d5734ae05aa699d99a375f953ebd2fbe11895bd299a9b90256dbfcc6b8e0c304e52f452f39afeb6936f9e3a14d5482ebc6f1e64878df428d74db610970c
301	1	252	\\xa846e62161e1fddb30db3b3a194ef55a78bb25411ee404b83124a7eb9f538718ba7046d76036694ec559f0231ed1841ac63e1d4f324aa56cac9b1fa2df8ef100
316	1	321	\\x5d50c0454bd28c2c8b7d305fd7e0c3c6ccbb8e2983e9eca69b1a36e3a59b1b81fb066d64d450fcecc758881ea58196b97855f5d089edbda78105ab5401740c0e
352	1	23	\\x19935f7e2ee503aaf2cf26f241a8f2cc65680605fb6f55e6eb11559f2af8baefcbfbed7d7520ca87ccc047e157f89f03e5ba55729e2913b926b657aa14d61c02
372	1	32	\\xbd512a7ffc72b8dd6502dcf4de62250d88b1271d0f51d78682c3270ecbe5db837aaa65d71b94e5c63e518a1db2abfb1fc87279912489587df3519d64c5731503
392	1	242	\\x55cd76e28c2461fa5b701bdbe1ad76fc4b50c32a647b236f0b0d3ef22696abd27c938ebc8c26f75784534302f435d952bc0f7a2c81cb510fb8aa60b8d3752002
410	1	184	\\x92a65986e954cead5bca73e71c6527612dba9bb46474c339bfe862a645d0f77d4c08d28db8f75e35d7fff20d9087bf0acc3615ef10653ab72c9595b4b03f5d01
164	1	217	\\x58605de446072823c294d1eda9545336f77483be35ff89c9daa15817c618259a505a0e955e5f0d41ae99a8f38c744d8b10917a4bee2af1e1552624fe6d06d803
178	1	399	\\xfc673fa9b92caa3b4ad04273536e43d3b2aa271ff24ee9273dcfa935fc8cc0f719b9c346dbb62f6373053e86b359cfbf8e9e164adb94fa249cdda2a3a43f1104
205	1	207	\\x94ad054144dce781ff3b59b73b600680640e93f2818a81c574324213df4d1064f6167137117e6e60a7f4dda6905039b9138ec2299bcd8ce7ce57f17488be1b05
235	1	115	\\x6329ab4f5eb8f5105b8fe1f1183b471dfcec7defad9ccc706e84a816cf641e5e565f5aacd08499250dd7541e964552ff13fec75af6852a3b58eaac26ac603900
281	1	269	\\x22af9903310e749e97644ea05225b29d043b1ec027987dc714c43a176b9d93bc4e9a116fdb634ea4655faa6e058c807e8ad753610bc4647cae248bad9ad00f03
298	1	350	\\x6b4c913dac6d3c5f7c2352bb06fcac7de35cfe70c1045eabc642b50964cb5292040abc83bfeb82bc862ff2e6af052c649c5e290b3d5a494438fcb5dd3f074a04
310	1	263	\\x791fa765adede39bce365f36e601da22e4bbee3aeea0c1cb3a211d065d631051758203871c68b5b536b36c7cc7d8d1ed1c85ca3be7f01b285eb91c3bb991a209
366	1	142	\\x29dcf64b3b4736b099a3e729e4da71dbfa4ec72f0772ab9bd3237cbaf1c949520366e8ae162228688055da66c709cbc89508565beff8de74590a8931d065110c
383	1	179	\\xab90e16b1f1fe8c135c838c35c8e099fd73ea295a257eae99925a8bca078e3daddd60e36a3bf39b95504821a2e46c97f72b8f626ffe11c7b3e19e6d334e5c40f
402	1	410	\\xbe6d19aa6bb0de9bfc3cf2045982e7278426f600d0e18a46bf00fcb6242b7c1f61071e6b69a90c40fec1e78fb5c82fdd1d676f8729f473b3b534e8ddcd825b07
424	1	309	\\x07ac86d46758f6a1fc1af0693b40a21253936c1786a31801a0806bf4ab0bbd3f3cb450be53991cbe8fed60bae9a71f68192b25379cb7637675145f4e134bc20b
165	1	118	\\x77a3c31c492fbd4c537ce3de222ef556c739d20c39d5dec02072e4e42f10483d9cee30afbe348068ed497897eff08f3ead611bff47eb322d3d31626562077e0b
190	1	201	\\xa50bc6b0827912844f4a70392096e3e77075c2a7f59f6a8e20c3a5fd144042a6c03fd0f459a45d3ee699949e40b10b67a7540a171b5a919562f2ef24c7cd5e0f
224	1	7	\\xf22cdcb07a2a92bd92a69b9d863d9e8ac39a6376960ecc008104ac24337a67d6fd7d58ea4c81f44f194e5c2d04f9f76f5a3438862ee812f4e3b02d6a36050e00
262	1	40	\\x1918cf761cb682d824cafd757bf86eae9de4b65def804e950402deeeb17b4b1d19ead2fda4a2e2654684572353027263a30e5a31b1ec3e832a89a8c0fbb1130c
276	1	359	\\xdc5e45171ee49ceaccdc7e33477bf2c0cc873a6791e7a409578d9cb065cb767e90b3e02d85000230d2f416ec33ded0e539f08de2a6d1c988d747228d8065990e
297	1	111	\\x16b9b5ddbdf83d11fb81092c250b6d30074a39440ce6bc384270b1a6e627dba7b07a923cffdb0e3dceeb1a089ec614bbb343e7e999f8460634ef86733adf3f0b
374	1	228	\\x5c74559886dc5c56ff25dc7cd676fa072c11a2ca3dd32682e3c2c38790ee2ff084e3e4035458b596dcc0ff2409b1cddcc0f6bff9f8abec2d44f6fa877cf2130c
397	1	379	\\x54dc42b52b822fe4fea72f175ddc52fd59072f4900094f8bc24564beb83862b2e99f355eadcb8afa8b6442fad78ceb81f9ac2d77d7fd0a0e2205f7b3441ebb0e
419	1	362	\\x23d064dbc299722abf152e9530436c23e6429be66eac2576348723d65b49670d8f66d0fbd94a5e99042a206a187ef739c80e297c6fbc9c10cf763419ca6b7d0c
166	1	180	\\x3742894cf65e3ee4d1df5aba7122aa17d111fc382abb85d12054d8214af6e940b553b220097b1a4ae738e7db47bd92cf3638fd4a6a31d0c6122eafc61b7c4700
183	1	66	\\xd022d518e07ddd159aa25c4c7670d492303ad818bf3e8f472cc292eaf823fe31d05d307fab304e56c4543e3b24a9a06808f88a55113fb18a2d75a6e5c80b500e
226	1	24	\\x56dd366d8ff844184591f059295d7614aae354a873fe412d28ca1c215f00a860e0c75c5dc9714cf5d954abb5b587f8901d9a6481cee7c8c37cd81c4ea1ce1f0d
263	1	146	\\x31d7b982384d8a61a838aa1453f44956be011fb488a1b3310ced4328dae06dd75bb7a915287e77dca9a96b194ae7136d20ef0a79b1b02252176be4957fc82c04
268	1	76	\\xa26c4ace29194a794175d5dd8ef6de6a0419ac112488d4dc0a74e2d759c0b16006fc4a65a429f273bfd4f048e8cc3a65ce24fe385dcbb1ff82bbd71cd3ac4f01
319	1	258	\\xc78bf63f48db77cec283abece7f9be92f4bbce9d15d63aa68744db7946c2b594c92a6f63509e4b9efbfd4e0823f652e5ca51bccc73c61b8747d25b032432de0d
328	1	181	\\x9ac62f740ed662bc2d737b582962db8cd4693e1d8f1804df8ce3cb973ede49c234ed6224a7406a1451e9508b4d8e8271fce0bd32d3ca2190a4498d0fac47ec06
344	1	58	\\xd5bab2c71541ab161eff2f7322fba77445242be82dc130919957044e580cbd7227782bdf8ae47d073a04abc63becd949c4e6be77691f84317dfe6ac5359a4009
356	1	326	\\x03cc405831dfe32e2cee01589d2fb4e370f19255550597c144ae9e795ca12c4c8b7296151689fefe460e06874c25f51af208dab0eff99dc9d71606948ba41703
400	1	405	\\xceba2bd9319880fcff0d4c8f4548ed4222b51aa3a8497e86c36912b89ffeb09f8d05d91c93921f30d67882dbef34ab81f7e2447958e893f3164fad862d1f6a09
415	1	188	\\x0b02067b5574dd9bc2d275f82aae5864e941162746cac368822555ac96f09c46e07b3af7e4b8ea620de98442aa511ab418f406ebe5c23269fe521872a6c9f802
167	1	332	\\xe6b4e42bcee1d6cc8451688d16fad1235907860cae1a1d7ea6305e76cfa5b7df37a8fcf8ce127cd0da0aae56b5e33fc0aa5f37025f29b390ec4dbb44a4e6e60f
180	1	108	\\xb3db5b0bb6f2b772f72360343e930be8634955938bd8f45e4143330f0dc05518c59202218b9089810c69c0d7bb230c077cfbb3c893c903ec10f8f538f9e75000
214	1	221	\\xf99db235b30ff89c6f5eb208a600e523f1568a127bd0ade739a1a0ed7de1e211f3de73e99787e31ec036c0324dcd5b1a2ce31dd97e83df81c9c77c2c0a6db305
241	1	276	\\xceec82d0d566677a7be4d6c733a2d7d3b1b36a968d2689f57ba60e6d94f00c425be72ed99fe5b8a8f0b0cc9b389c381d42d3a4d09af99105875efd4af0d02b00
290	1	92	\\xe4008ce19ee31a420191853f88dac8ac65ccefc7d3374fe937377f8aee653997354d507b95e82dfaac95c7ce0505816880291a6e96674f70a71e2d136a9dd002
302	1	391	\\x683f319f7ec0f94d706bdd3ab0d5fa54459032e493e62b7f3cb77fd7b9e58affc079896b2a7d60e01f0ed70dd0b3a475c60f3e1c302924e8af1e234516a46508
339	1	42	\\x8f051d0edb65c3a55e274257d7a2b33f000f729398563d0c0e58a44a48dc9a2a58644ff17a263f4ccd8138d21550b79aa181d5c4392426ecf9aea6cb3a10dc0e
349	1	167	\\x8755d1b79ae86a331e154eacadd8ca670f1a8df0f9b56d11535d37c1097ffb138e37e04eada75cd59e6f74d79ced41acccfbf2f615ce5d59de956e312e0e300f
363	1	3	\\x6a8c6aff76ef2045c63b8a47d48f5c561e48d59119acd03e336312096ce04f1ca54d87cca050e366dca9557950e35fdd08b2d86b280d0f40d142c074359eaf09
389	1	219	\\xe663c683d907fb5eaa2c75c64c7fe3f6d1b0afb8485599d1030e92c2062512b9e746fe2778fb842e5d497b8ab8b379799b05be7a4c5be66c01cd18d61aa94a09
407	1	366	\\x8e820d9158886859f2df1abd310fef3a97a62f47226e2c2a9cf1c977af247d692438f62bbe8fb3e08ced376628b66b760ad7902da648bb71557940e1531e8607
66	1	256	\\x881d99f498ff9b7f054ac7a9eb030b5d724afe87c64563c183ea3d2392f2391f1dbfa95ad650d2df551316fb493b1a2793ba0d10018a73787150e9e1b17d7407
78	1	244	\\x50c4aa53460e09bee51d3e37ad1bc18e439c3002ca0bff7d9f9e903ef4b4878ec32581ba058ffeef393dc864ea09fd5418aeeb8e7c0793da27fd4602be1a3f08
87	1	267	\\xe24a4e974b8feb5d01f149681dc5284aea4167466a9b714e53e6175cda01324b74b61d98f49693b7389c98267268d7ab83173f2c8fcc10a7279eab34bf621507
93	1	402	\\x1cc932b256f59964d0eb30ff99c36a00145d886054a3626e9a080df1a3f40b5093af6d742c64142c48f21587a309043f2fc4eedc5428a8f2b3a0f5307b6b0303
98	1	282	\\x53314b651476e3206525d077b330aa0f93d64b13c63128a1c56fcc024cfa33fe2ad00d5e72c2e536b7f51c70229d63f1d5a313eaa062decdb84f9b5b22664d0e
109	1	72	\\xc3959b75f4c096efd972b07b2cb2a690ea7a4bec263364cade2c5d831b4a9f1d7aa00c4cd7961f5d185aa93ac457fb4d5abbe6e8fd00556f4badb212a957ff09
114	1	222	\\x7a9ca577e9a0a80e86398fe1d76f9fad93f6654fa3fa56f8443d992c6133fefc2773f3a750f5302abf3c22202d7c3e2465d7ce3a25309dbb5a86f6e5d6692c01
118	1	199	\\xb8245aa5bcc5b41153ccc523d68843c1e3c72324e877508c0773b822bb929381d770c1347389bc958663be6ba19b9e6f89267b67fcd17dfef4e3579422aa440e
125	1	264	\\x7f1c30cdafdc9eea1d5fb3ef5bc09b494a64aace80a70d701f78808da8911314290d133bffdd92280655456938c92787c80af3cf5d0270a382807cc6ef2d3a0b
132	1	307	\\x252976b8143c314b09ae14a22c498cc63b9012f55a111c83c913d44895bd966e3bf98d86631eebc541a463984d810fbfd86c14edefb65321367d67d377ad5303
142	1	87	\\x1d933dc0e73d23de9fb18f83242d21443e11b862b8a7d02502d342459658767339253ed978d91ea18dc4f85c3f80812d4b0bd95d494622167992c106dba68a09
171	1	54	\\x269511ac5a7c56ffa5f33764b02380d846847bb56a3ddbcffea8ddfbc89536dc5e33db88cbcfa7ef40fb2e3e7166ad43fe800b90a30ab26f81abb15c19fa7008
201	1	396	\\x68af587b02a3c0f22e8c95a3716b8ae7bfd635599c410b388264027970c83e8997d2228a1a4246065d318888cc924f70d00360db73050fbe10472f0718d53606
233	1	404	\\x1eab4a3af559a82419fbb403e053b0199e4d687b631e87c338e01525b53b7ee42f97c602ab52a1e22ee6b3fc115e5cd06256b9ddd82143b56c6e96f31aa4f90b
273	1	125	\\xa30ba6ff6159cc2ccb439501cc4bf9a0db40ad90032928a413ff3741746fe226953fe0ff2f86d0d4885f4e3bde27ccac49c0b3c400a5727b5fe3a814af1f6a0c
409	1	128	\\x8a3834526fd9100c0f5537b05a8b72c73c4baa9d678c9c4fea39a6be5180f999ee7bdad289e08a6dca3c6100f59f5c055f61641a3139db659f6db2f096322501
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	1610127007000000	1617384607000000	1619803807000000	\\x21797ed983fcfb62180fed15432a856ee6f1d567ece6d14d1bc7810a37eea495	\\xe076168ce0cb972a2881af2452071ddf3d25cab55b0aab96a4f3c1d0c6e12e31e7576de5f48253e43a15d50e7e43e1b62dda1ab9e6f549689c9205415ea9ef0e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	http://localhost:8081/
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
-- Data for Name: auditors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x5b395db01fa92430ddc26368370f614529a046dcb554d160397599a4df3415dc	TESTKUDOS Auditor	http://localhost:8083/	t	1610127014000000
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
1	pbkdf2_sha256$216000$W40F0btRIqIo$yoa8dpYB+8fZEGeQEC2z47gsGP3VhrCaz9soo5kfU70=	\N	f	Bank				f	t	2021-01-08 18:30:08.396984+01
3	pbkdf2_sha256$216000$PftLGmTNth1m$E4JbKjndJiImgzzu3CjTrr3G7y4Zxf4H1+JTWeZMcKs=	\N	f	Tor				f	t	2021-01-08 18:30:08.575496+01
4	pbkdf2_sha256$216000$kwUwjzW0AxEX$PAvieydiXsZotDd5Liic8+nTchRtCDB4eYLUSDCYBTg=	\N	f	GNUnet				f	t	2021-01-08 18:30:08.658785+01
5	pbkdf2_sha256$216000$tfUAenBBD98a$WleXNeUgJF1aZ85OgVMPNWlcMuVcHi/CKx78bsc8Lcc=	\N	f	Taler				f	t	2021-01-08 18:30:08.742543+01
6	pbkdf2_sha256$216000$VyX6gBuAQEr3$hdna0ul8KQ00Y/Dz90kNP50JDv2Hy43qSX3/H19Lo/E=	\N	f	FSF				f	t	2021-01-08 18:30:08.825904+01
7	pbkdf2_sha256$216000$b6LTQ57isGTs$Lr6YZfygkOznHpAmGCvq85Hosxc1KpTlL2j54lo4l1Y=	\N	f	Tutorial				f	t	2021-01-08 18:30:08.909146+01
8	pbkdf2_sha256$216000$pajdtqvBfKpF$BVtbWrBVlbL9Lefq4Y0DK+ZOW7UGMjxoazvRDk2+nQc=	\N	f	Survey				f	t	2021-01-08 18:30:08.992272+01
9	pbkdf2_sha256$216000$8yLQWmAc0qO5$zooypTEfI1Dku7nSv0EMis4tp6ztXqZ8tG/cu3FqOPk=	\N	f	42				f	t	2021-01-08 18:30:09.444214+01
10	pbkdf2_sha256$216000$7DVG8P0jZlxT$FLJ40SB0upcoatKoYunyhY+asRA4P8eWf5eRlR7FMKU=	\N	f	43				f	t	2021-01-08 18:30:09.898101+01
2	pbkdf2_sha256$216000$65ybGceSFYRz$Bz8rKrC/cLmDdVVa1ciKA2sL0w6AcSNO9f9GX8jTHdE=	\N	f	Exchange				f	t	2021-01-08 18:30:08.488762+01
11	pbkdf2_sha256$216000$EUgNCfP4tslm$P2zGqE2V4PRovNioQyCprrDJwQo3Dsm4g6s2/CBROy8=	\N	f	testuser-tkR2w2k6				f	t	2021-01-08 18:30:15.218066+01
12	pbkdf2_sha256$216000$z95PUxijX9LC$FQFmnW1jWyqKdH7h6xY/lJq+OeHy/qbpFWjjB/Owegk=	\N	f	testuser-MxPr3V35				f	t	2021-01-08 18:30:33.705564+01
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

COPY public.denomination_revocations (denom_revocations_serial_id, master_sig, denominations_serial) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x02b0025d9ecce55e68cc911b7546913b370d3409519d804f496a888ea5c186c35a92bbdf05da6859a026a42b69d969bdf20236cb6a3d2051d7b50232479eb8ec	\\x00800003dfe8209dbcb17f5f8aa298232bcca2f3eded5c23d283c5c8209e8142f2be63e471dc0788e01deac6535fc00fe0c77f67f6c4e84b71067b96f75f50112d34155d82a1785ed3e9625b54c5522986b71d5449aec333384561bf06a27415892274ef01585ae15a5ee914c97bfc8cc1b4525f0d272469204a6e942fed31858654abc1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8ae368720623441c6a1178d7ca29b68bc00ada00b8375314989042b5aa2381c02efa7c27684aa237e6d051d8e46856c3e33cb286c17e2cb3bfe2f56aac365602	1640352007000000	1640956807000000	1704028807000000	1798636807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	1
\\x058835c79639813f0d09da85ccc078c25c34bb9d1c36e1c52a8e78490b2ddbac36558f89022d7a2bb7f9ef74b3e954408a7d9cf46e24840de598f0781d5c5f82	\\x00800003c94cf3f0c7b5ad6be1fbbb32c05e57efb9f9a8cfeb5344535e18efdb34d71d923de4e5f66d718d4d33b3e743ea1c1be494f352f796e03dce0e38034903a314529781d49e49f701d280796c58d7b61bd35224f709ead10b1cea6eb5c4c0d79353f88c2a1383684c80797fca22b00e300aa2fc72b54354956cc910130a2bf91363010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf43734b997a22ca21315823167d894623a5eb0fdfea35359d30ff8eab2724efb20108f507d0a3ef426ddccc5654959560fb9678fa3caa99c8106bcd9444f3c01	1633098007000000	1633702807000000	1696774807000000	1791382807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	2
\\x0b9410884b900fb67cc88c74388fee6c81f96947f1b912cb21fda71432d9b98281f2752e45dcd5a60a3d8f4c5598da03bb745c228a436acba51ccbbb5e3491dd	\\x00800003d5df535a3952b63a1f35ec5fd09177e43a28ad295fba65c134be5ee336f06076df52e1a8cf3a1a703f6e01911bce0b6c573169d30ff630778c16f4e758dc106326c5778ccb3a8ba9e16be1105040fd33f26415d9a43c92acf1eb1495e9d3dacf224a148de42a4f43a7723fc5e4258e13ad274c7d3b69922b070cd1af1ea127f7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x92d3ef1c5f41e9e5029189b30d6e9df40472b928345accbd69d8c7f5c0a207518a8b368457bba1e8ef123537102e00ecc2ae0589ad3585476de6315544166a0a	1635516007000000	1636120807000000	1699192807000000	1793800807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	3
\\x0b546455e1c0f201b9a589b48eb79bcbae694d562dac104ce0a75f9651ae1df17a006035a2a0ffe785e6ad7a4401e3744a77640d3a059f89eae00b6b64b18a30	\\x00800003c363ebece86f25c0cc906b7daf891f198230bd90f6163337c63057297e5c967d04c4b3287b27cbb7599e7a24221369f232e4798d65379a719860131f9907cf0df3b7115746630ee8fd8b68607e5a4eacc440795d86a505bbae9a078b38da2019c49785201ef4e84aeb700f6aedb9d6735fe9d2958096e8173d864bef3c73aa8d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x30e0b720dcd2394c8937cec0e62b16a90f23904be28e49adf4870433d05ec1d5e41c113f8b74c40f17b3762d5aba29e68ff5fc0e533cc35e48af1f9522f4390c	1640956507000000	1641561307000000	1704633307000000	1799241307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	4
\\x11d4589b1a3e2c240e237ca8c5a7e2531a83edb45e65d92c8f813131049f5a53474e8c1c8f71fd551438dd085cac4a13e4eda74061821138190ace2e92bbeb86	\\x00800003b1024285962fec29f630cb490175408d92739d6786ae916fe31142a266de39b363d3cbf940670bb4fab2e7abf9d4b9aea30784d85fb413ba1d5717492fbb48a5a0d05de2bf15e75f080dd23869ed52052980ec5343318a0d55aa70c75774df212dab13885b2781ff7058d6ee1125c0ab6d489dddd53944db747dc375837762d1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc38f8797122dfec03bed16534c882e2b6f05d12c224ed2f72398759898270a812da135ca2b459f06c45cbb42662bd87b6c69a87ceb9a0cca5d86d4bb2d156006	1612545007000000	1613149807000000	1676221807000000	1770829807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	5
\\x11483d402f1cf12cf269529c218e3eb0b239c5dce82185b2daaf3bfce3586af33ee948170c87f078559a568edb258bbaad31d77182555cd2b5b10da9da6cb2a1	\\x00800003b6554ce2565502514aa9f78deba54eb25efe2d1cf6a2d759b2c2f98a653e14ba93011f4ebbcce74d50308fa1177d6697559df569b42b6b0065f6a7bc0ebf6ecbcec10596c4f450613bfd711708358167df14aee37f8ac99de62ab2fefb96380142e0be49c2bcc3ed7700664dc836dc902fe78cf584edc2063e093cf03a489317010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x016359b53f7b217e48999115ae1868f55cf406eb4f0f8adf94650234f571d1a5f21ec84855cbcfa6f7df236bdf176f0b5410d4b733cd9f7392a96dbfb801ab04	1617985507000000	1618590307000000	1681662307000000	1776270307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	6
\\x1aa8510519d4e064816cfe0a8d49c6e2bb266c052f08112afe1b6fdaabd0957572cc67db9845320d11471d8b83d279079460cc218bc8d4071f4869486f53e005	\\x008000039f128d27bd0e6f5f4e59609e943b6955c3fd772000d7f74b24dc8a1471d1afce424d6cb8784a250c65186c20784a614b643497d68370c23c770749fd7023e1775df1fbce6e583b5abe36d42c39da8d94836725e9973323b7c6d197e9c12957382e656f74dda26053983f5089460f651dd44204130cf224aa4375aaa5a9de0cdb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x48d92bf787ef476e6d9346cb40cedfb431dbd19e2f2e10ed5bd14d17ed45434dd276aa976cef4b09b55616cd53b261d5891689ab68d65cd9455adc5fcb69f707	1626448507000000	1627053307000000	1690125307000000	1784733307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	7
\\x21a026e2b6af5126be639aa7b270dbe1ae951fccd7e1ae30cbe56ca45f9f25d000e6fd3b899c68d0a854853fc6abae279f83b767c5248f7b25938f3a049f73d9	\\x00800003bac53bad89064c603f8d35f798c2e4f95b8264e267eec862a7f17036e8ffe7dbd7e0af5dec882198783fc5153dabc5774922464fb3b39deefd9061287fac55a2b125f76b8b2271bb12d67f8e947f856d15ecfaa46bcea268fba8b83811c666c87558f8b96225a1c8f44c197643482b2e31ad0b9b98db41513384c002bd8a936b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4d4d2a729746d958f3671d3900ec69bea982aa5a17c7a8eb78f69b3480ddbdc6596b80f65b4d821e83e694a2af7b0f5e2bad68ec30a0ce73f30cfecb716e4105	1639747507000000	1640352307000000	1703424307000000	1798032307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	8
\\x26343fde570138d8be4423f906beaafafc3df10dc2249b7998516f2bbfb06b51a83cae56897527213dee7ef4b5363ca478094e98ca3412cd4516ea9914fcc643	\\x00800003dfc091edcb938a630629df7c2b284bd900d839951d6ce90f802046b50648609ca7d1e4749266e6d819b66992727181d4eb2142e6529997756554d9202cc0930397724e2edd95c1ed5b9e98776602c11c58c116024c4a8583354f0349019d249faeb2744e17e4ccbc3c186564f98d9e1e085e8dda22ae07c64ae99f50d1e1cfb3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9102da927d4d1e3b4f3ad14214c9a23a634b202742c62e652e2599a09f64ba5f101ef0a6f58cbaf9fbb625c2b09e950c17ab08b67d2a24241ca7ccb46bff9204	1611940507000000	1612545307000000	1675617307000000	1770225307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	9
\\x27a0971d266206f15170b26173c658f254c621383781ab26e4318702da97b4c24e4b8babda2a31a61f23519c7b2f9e7b3ae8e90ba03e41ccb2c3afd13f0d91ff	\\x00800003c34a69e604a5fce0a38898ec1133ef1b3deb97528716e1057ce38e0e67bf793754c4204fd0a42179cba46d7fb526c2e1f24854cc777b18685e61052a6d9c209d3a69ff920b62e1e7aa90b82dd556f475ab51709e731c825d9565b22f9cbb28b90357f9a4323dcd6b2f7e0182993ba185ca26ed921d0ba579626e0b8b0bd22e0b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3178201358b4d83c2d3c729a7e2448646f2b0ecb2e2a4da7d9521b49e33aea440a45615e527f59984a49e2facad86453dd6f08889208378cf3e92a8986cd5a00	1625239507000000	1625844307000000	1688916307000000	1783524307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x2728ececc5ad2a1e8d238e775309ce78e63a17340d45663b950dd6f99b2482824038276df6c8c5309640e5c5481411291f16dc6b51e6ce7d09e414aea958d241	\\x00800003dd265b8fae7ea50b3997961b9d3680f0c8865b9951af54c2055d55e7ad44a69d2fa49212a759ef4f5c94881964ebcb461120575bf94f10c6a3897c2b151293b09b89d9c50cf80e49362779971665ccd97d867bcc03198cb228b3294a23a8d8a9ec811d2ad77ba899290a57af05ddfa88cb1776145865f9b999dd3a999ecb2ad3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0346ab749c2e380119e3b92279543c7aa3af52af7864aaff5de2fb90c14cb8fb03a0386d0fdcb4b9b4a1b8ea88220432bdf54f0a234fa5943dba2fff74317404	1617985507000000	1618590307000000	1681662307000000	1776270307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	11
\\x2bf07a3518d12f44642e24f9a2d018b633713922a8c60843bd1db1388e19967a0e3ed4fc99a168e632fff3167fe8339acfff6abf6dbe1e50490e9147fdf3b40e	\\x00800003c3bc6535e22c0b56289dc05d3109308776879a12a3952959f649d431c82dee74edc85c0e950aef7ca884fd9eaca0131a7edd700669557521501c21ac312fe901ddb3f4330c7d63ab26e1f7bda106271de76d402aa4b6152018f787cb506f93ba535a82310a9a7ff6c35ce98e932b9d741a05130394c76d7eec315e79a0a10ce5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe3c316edf918615d4d325b5309e629a561fbdc4a5f6dc1eb3583600f2727ce19c47cb093d31c6e0c320a42c7cc03991f2f5a422f5b802b59e43710ff07e6720b	1622821507000000	1623426307000000	1686498307000000	1781106307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	12
\\x2b44dba7dd050cf342ab89ed391e2c2dbff1c5718bc38d96f5e30563dbce539a740408f3f3cdbfcc166b7120ff3cc45f68ee9e029d7c8dc16ce42e2843920138	\\x00800003a2e7d5a4681282cfcf06395b13272c4a67267f5c585d7ec79c976e2abd800ce5015e2941ef0cc6fcd48391b2941f6c24bd89ae56248bc78e3f3e7eb22b64a53bf6a8c05f42bdf1d13df411b0023461717b1cae1185a57a12bfdb87c6e2524aa0d994fefda65d9ed6cfb0c207c60cb3a265f86784e1bc5df3e49b1b543d38e29b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xeee82ec28a04944c5c47d03d70413d87ad07627942b59c8fce03cc25dd9ff1aa38d9f9070f99036c03ffeea8db804b2c9bda34fe6a9d221f9662971d9702c107	1610127007000000	1610731807000000	1673803807000000	1768411807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	13
\\x2edcf5808b410d231f540afdccd42f47a1184fdb3f4fa2a31e51b27e5b541e2f4eb1b1858cb24ca565127ccd9f5a4892e4df2dbed7ff3db23436f9832243dd7b	\\x00800003a95d9f104fc1daa6a90cc68be10b7961ec19674c70405d7f570dfcb5aaa471dd8462b2223dde6c052eca5b5da60910fc3273ccca2bc6a92a8a0915e8739689691079066d446a9814df8f67fcf2bccc2ce7c50f8719758a3d706fc7fd15e14fab5d158624c788c3e974e174d52a9c0cc1baee6185a2a248f2ead957ee8e1f43bf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa36d4f54f92af4e33fc89e38d692f5dfff3a4346ea5d572a0b0ee56c75930480f79990721720bb9c13fdd17aa26df6a29d30a2345ca506b16a9b62c4aae27802	1630680007000000	1631284807000000	1694356807000000	1788964807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	14
\\x32b41f59dcaf051e9f201eabe99175bcd073c0b2ab73c22d7d788377b8530307a1bb490032ca096dd93c810bed226e49b0d0c46262d1151e17be71175d03a834	\\x00800003ce5b938968a6b8be949e32aa2f58f17185eb3fe82a4c6df1bb2c67fe3ea90030c03b46b31b0db5f7de128346d0ecc11136626ed206171ce82734b6d1b8d645d858855476eedee04f3073eb8862ec0f9a04bb0b73f308ac702401eec4acf66c5535a691c8608b1a6060ab33b01c3aaeda6633f9acee816bf7a2f81f2c822e6391010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xac8e89c10f853f92bf9058754f16b2e3d90972f7438b5eaa38ef6681d13825a67d5c12393129bf389ed960d7d3ff25630a252391efb54a4a53a9c242befe8901	1636725007000000	1637329807000000	1700401807000000	1795009807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x339c2e27b4a3538388a31b492bbdb4aac1224367811d250b0bdcc2dc07c3c649fc1be4c6399b2f73c0e7beeb5687ee176ff900623aafae37cf1f0b67f194a570	\\x00800003d0d0e3d1a7fbff92ab981d6493b4fd8163b857da81b957b6c02943a2e9696c9976b859dc9e2c05f068eb96d25f602f5f766d308422d40be2f5c76f2bd420819ff49d7aadc3805408c8522aa4eabd02d6bde4a4a42ec1381d81fff0311ef621dc662e45b27aa28132f7ebe9bf1a9ea842c1cb596d42643947f5f120df8efb2679010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2e501c9628abb44577e2a0192f4bb84206b9f7daab23730cac09e0a12de0c10a2808f39d82c9e4299d56253e886ffc1cdfc18fce25cd613cc294a0a1cb4cd503	1639747507000000	1640352307000000	1703424307000000	1798032307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	16
\\x36d0f20424cd0ab873e1bc6e63a08b67949a9030e4c6c87069b05c069ceb662f7fe52f6461bbcadfdb57a42ee2803860d1a55e87af762372ea6bab933421f2b1	\\x00800003f1bc648e22590488a9b64f680e067e6e9e6be2000e112726744fb167ed1cfe7c45b241a577ebdfec5027444e4227466cdc7d12e7c5eb51910b0a68633df721cfccb815bfd1e2dc1ea73e3b3747644b2db9e540ab0f9a599ce8184662b22b96fbf6d1f6c5529730b841a6b1417222431cd62ceb7d804dab185cd394bf5c565c8d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2e1c6d14c53a45e25ec7962fc47e46461399e0fb545d0e83285e8b059a30ff7be21a38b8b5f5df4de0c6b472b4c1a9f4cf08fbdc246694724b5d6c7b6bfd1206	1630075507000000	1630680307000000	1693752307000000	1788360307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	17
\\x38d8436ceef99cd32ba899917091f3eb3ca95676be2ff68f279dd75fe45366b1f2e719dbf8d8528eb22d935e7efd14397c8d25edf3dca749f82dada8f3f19e87	\\x00800003b2c04b96fa9789f5be62f4ae1a6f724b2d7c2f02d09b885298d04d327108fbef5fc8ce9dc64e17bd972e288c51e223ce070a3cfa9b1d42193478c35f0f2500fef51c77290719309306dc48c116179a9c36be7dbbef03d795b59b98d999501890631002b76987cbb4cfe83f2753ca29857ace49c915463c3ad388085c580605eb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7f254a0fee9e40c920545cb067760e3b785cf5b24255c0474d6f1adbe8fdcba34fd664da1538ce1d338c91c89d607aa3aa2ba38bdb76449d689f7a63c7d1790d	1613754007000000	1614358807000000	1677430807000000	1772038807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	18
\\x396c4a5f1ff643a97c4740ea2d4f1d7a63e0e77a961119fdbacc1af2299cdd3db2de38eec2713884e5eebd27dfd2e39db2f60c65444c91d2fb8f49b822c2a818	\\x00800003b9ee812958fc6eb75044ecb96a7ae5e3b990e256e9ec827d8d045dcfc7308beaa13c255d605d8b7d7e11bac80c615429d6e393af12da5edc46bd74af9602e735cee26c9b49006168de27dc41a1dbb4dd7d8b9be659300473567f1eea42ff326da9ab1f7bcb69f2bd2ec09c7b1eeee3c71dea45396c0b9386ddc0c38398a7841f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe1c221db7d65d1f52a56198530934e9190cdefc1cfd769665dacf27169253e5a5550499de364e9fa157a1f34ebd3dff57412c032aacf9faab72a4ccccdde5406	1622821507000000	1623426307000000	1686498307000000	1781106307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	19
\\x40d494cce3e26511d7254ad62c8b9acc78209c6ba0ffeb1a8b5b46c54a3ea72247109587da268f041f22fd440642151212797ecd9970cf3978ea14cf03c66f30	\\x00800003d683ad4a2b43572a85c4b5bfda475b2bee05d9218f79456408be443481d565e46f48f750807b8d39c6aeec79f2d6fbd4fa6a18c0344f66ed3a6b005c903649ce3745b0e430ab82c2189405e3ed14495320b571efa4983a2043980b9f227afec0762bafadf27db95137f46623af0b74efdf7b41044216da61dd0522fe8055b459010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0b56319cbc237a8f25c6f83e6597730d7d52a2aaf03b161de1277415222b7c6937ace357e08f6b52dc7897017646e3a65bdf0f16e0e00115990ad0f0a630f10a	1616172007000000	1616776807000000	1679848807000000	1774456807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	20
\\x40bcf7418380a90bac9fd08dd2f6f25f2439c1cd15bf45cd7dbbb2e65cfdf7b9f43bfafac15382f3ff337ad325b22371b7534546849a5b4feb24a0480fc1c0c5	\\x00800003e8035c05f754c53ac2df62d2b15273be4ccbb7c233762b2d98225db2c9948583265f12e96602a2a27068bb455308d44495dd5be60d768ff60b0fc88bf7ea76fa5ad702a401db8afc47403e3d9cd0a0d313f2cbac9d302a4af5ac25f195d96f8a4cf12c1255fda1399cf3e5ace75077025e6400718d6d0f68acb5afb5d600c5cb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x777c3e3a71497f1c7ca7b28edd99c155f7f1987f578873c87eedf56a18f907a97ae9cc18ed3a8a22af8e68c88f8161d6dcfb3355b8f15ca72daeb6ef91179605	1626448507000000	1627053307000000	1690125307000000	1784733307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	21
\\x47a841cfb2cab030f96621d469fd56a768d88038fa02a014bd6538c0775b14083bd136ac425f3a94db1e03fa9af213092e652e183a5a44d9876c3e72ce31d7fb	\\x00800003b3f76e5d58baa88b26e5a9abd636f6cd5e4cb418b0a373b30bc9c48d5f746bb4b0bf3e491dec9f2974bf2f259fff45f94e5f8c958cc48cdb3f158cc2dd74d4d506158480a8af29d9dc587ab8929d7a30fe7cdb51fd1a1ad0c899e18ed3becc2eb85a2b5103f2f35d6ef71db356a1d0be0988cb6d3f5b9f77d412a728e0af1cb9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xad8c8535f7b65612a339f9e04ec4346ddf767a7361d203d61308cec6a2077f87dee1a4340a8e6bd1f27d92f96722d419a69c8d9864be5be6b232442fcc6a8805	1623426007000000	1624030807000000	1687102807000000	1781710807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x4de4590fa22f5e27b379c106f21954a5de00b09076686184c8e973afad9145734e1ee7184225101036ca065eff8060faca691934811be17c2d96d00649c4523e	\\x00800003af7a0041d5a5d9d8636470d48fc4323266aa53cd991dfeb5e9c91a3139aefc7e0044c4d53144c54397b74cac3757c5c6ed69fffef3106d81233089b430914d395da13b01e36e2bae7031dc1d1a3f9f77c7a506aa7f308b41394b998d9ca13a1f599d8559102c4382a99297be139bded0389e68768a7582faf8a0e89965f6f535010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3696bde88fc621b1f973eeda201c13be53decec439c6d86b78e4b749a44fa980bac13ef99b7bfd08c45cee192c0a5206ca1f7990d3a9b4875d694b87fe462409	1633702507000000	1634307307000000	1697379307000000	1791987307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	23
\\x4dbc033065a941822091a6563bb4330c185bc0c9f9c3cf57a2cfdcc64d8df51af2e12dd8c21693713f9b7120710ef528d70ad16df144a6fe3d563c2d76253e8b	\\x00800003c3e925cfcc56f956942b825b3b78418f31ed41dc40a992a19b313e4aacb9b6cf359cd12d13466e1e8d657a93adb5622ff1228cdc2568a0871ee82b9e9f7898f83fffe3c0d41e3f89493d6c6daa672f590701091dddc98fc4c8d5d9a644684c9448928c04ca4daf24af0415c4afee71589bb76293f11e12797c182ea3d7a12771010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x76781163b93fc8511a78cff81022b7382fd56ea5e15d4b0f792950d1c3d448e498aad66a63f198df2339cac825680d389dbd39f2890736310e147bf4a6877107	1625844007000000	1626448807000000	1689520807000000	1784128807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	24
\\x4fe405d72b6f51bbe74f307a93eada345fcd62ad345a03da13325c89191c73b0fefcbcc0d476c2a0c42b2d033a263bc4393e033cae945b0e37ec7c2c4515a0a0	\\x00800003d957e024be8fca49d213af6f32745d5b6e593324a41d3766826cdfc0822b99ef5790ca816abe3b6681bee883e15294c6cb1b2c60619566c593fc91a996890436224e608acdda885964d64a1d2d74d421546607bb4889019876d122e040b95d30cb673b71c68910ffe0c97ea353e5af7fc75eb0d0e5c996e1aa4bfa230870a13b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1b9f241c4546616c957d71c3b314cfa6475b869c5c5eb630a47f7fce216f5310bf9d43b3e5af031a6814352b0e589e9931f065a6d5d00d6c378f29a8e2c0af05	1640352007000000	1640956807000000	1704028807000000	1798636807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	25
\\x51506a0cff4d797542f49b71e839ac16d41ed749df69c8dcc93cfc617b8215b114a5d3e3f5274d47e0289ec6bafc2e7077a097b377b54f532b33c0eb0dcffd25	\\x00800003a4b9420ebde61ac99d0bdbc9b5fddd117e819a281e0547a53fd748d1071ce401a2cfe7392150f7b2a048f8422a7a6cde648dbbf2f8a9129c8621f643fd4f17900f23611d3f43e3c04b561fb67a9894bf9b4d3139b107807f72376f029c44643e88969cdcbce7eca3376dca0324b7860ec85bd2840a7abf8032c5bd37bf05d7f9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa3bac8a265b6a3c83a9283e12d8ff5ee48716d6cdb013c2a1af0fd3fd06afe5821e36c3f345266d228a0ba76b31de68d0c687cc04a8e1119dafa90ae20f55907	1614358507000000	1614963307000000	1678035307000000	1772643307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	26
\\x59c8fa32736258cb992ca2fd5aa6b8a81213cda35ba60a2d22dac8800f6c64d45a09b634a48188083858c98236a4640b11d689d74df7d2eaed8cdb3de7719dfc	\\x00800003e82675a6e33a1db76b9bab7c1ee9d5f4357af9a25997779b6e013f4d6918537c1d47a7bfe3b9035941875c2a7deedb79a1ab07e916c7c3bd4821b68fe029da9ff174baec165da3bd9ea94ae81dbd1b6be9b79640a90485ca6bbdebfc8f6e78eb6a74c0c29c2abfe8861747cbd6f033055e27d28d6b3aa64ffc1ae5f8ce42a7c5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8d1e5b4b6876853a6e212baa9e57380243af193d4f813eb78656545f06b3bf7bcb9869a55f2a8b7293f1c7f8ed067863689c3186edf2d6f43621ca6fe46a140e	1633098007000000	1633702807000000	1696774807000000	1791382807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	27
\\x5b70a20d5b28ddb6cb33b5847dcbfd59f9d3408ad88f488503a0e004e85f6998b91c1e94bf9492477a85ba448aa101f12cb1e6ac6dbc07c2c072dd6800d9ab07	\\x00800003c7f0490eee2e58abaa98eb5c78f934e224d439902ed1b0aa215b98b4ba75eaf0a3290e5432afa78365874be62e450c9a53647fea2267e48fa01c00580c9a1e3337707ba30c992b84a7a1bf456dfd113c8a53044a5a77c93e1efc72662018bf43311a1e016138ec86f55628f6a92750222e5c49000d9d40fc7dc27d2030042595010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xaa0fb9dee56bdfca101ba26bf01b6958df0b144aae46c1053734390f6d5bdf7246275d0f7397e2897179abcc622f94c27ccc19b6d717c394d7486b0e8a38b703	1638538507000000	1639143307000000	1702215307000000	1796823307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	28
\\x5c485d2707cf23ab87a72ea524806bd56178d2998cccf26acfe9a19cdeb5aced6e94ab68a8b11b517888ab80d953718f2f118ec39456556cfcf70ad8668ba840	\\x00800003c44aa806ac73fbb706637633008b9e54225bfc844984399c2f1613e06551b17264501a59016ecaaf465d46da632b3686d0496833fff94b19060ca51e6ce80015502563d7ba50f4424a22fb3ca6beeacda256304282357a2030df3070eb5c7d663f0cb8f03066b0e36a7906a8136be4b327f3d9bfbee3a70380c9d5f8efa93e41010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x077991eed9da825351f78c0520e42c3f1a3278cee81285d9eb3ebcc3616f226cfe5941f3309f021c4d2ad6effe0bd247bad29c71f6c48b81bf0cba699ad8130d	1626448507000000	1627053307000000	1690125307000000	1784733307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	29
\\x5d68c93051482532f616a682858fd08b1bd01329f19b265e375c7f237a6cb3a3d391189e1fc41b8e98689239a03f4b74b8b81a22457d4e5339d8e91850096461	\\x00800003e866a821daeb9d4ea1c716761836e1b69c9109b502a26a800ad85f0324b9f8fdc49c9b8732a131477df29f701b9c03dccdf545660e87be127fa50dfc6bc71d655a905f0c71dc2273a20c70ddd01ecfeca96c117e7d8af0e67047609498ed96654b2b4b83f1475bca9a9c9616201c07e35a2fa6cbc4ba462d51b550c153a131b5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9df970364a528f6344f38fc4595cc9d8a1bbd8ca55a9d728067e1201c601dc44ef4c8e9b4f4af02961af55c62b7c6c405992d3760082419493d26adc799c340d	1630075507000000	1630680307000000	1693752307000000	1788360307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	30
\\x5e18db27d1eed8b882a1a90e8ca2bf90adf0e16954dee7cf2875a5e0c07e09a698029129b35e66a31bba87928d6e227903135bb73eb4431069810bda90cd93a3	\\x00800003b05713153657962fe588808f13aa4d823b046a39a9b5d7bafc29a32537bc9c18a26498fa150fb6412934bde4b58a3ec2742444e9a810c495a37d0aff11e401c6cd0fc9325c904afe35e613ea2cb9f79115f3add4a33fd54aca3b1df71e055ee62634c7032ad32103f8f248a0cf3de09959a115670cbc0e22c6e2d27a2dc56d0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6f50790adf11c9ec13e5dce960bda4c14a8eafb977c0ac6156c15716129c0b3e63e53a39b931eeb405e14b538aea56952a9a3222d18f97b201b3cf1a8851d903	1629471007000000	1630075807000000	1693147807000000	1787755807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	31
\\x6530b99290dc316d001f3c009e76aab233ff8303eae1450ddc9b7d02ef04abc3cf26fdbbb2ad8028519975867f10e1329ead43f54c72b947b933705dc58bc96b	\\x00800003bfe9f19475d9134b0edb0ea36f11fa264379ea7f59da778d1164e99281b6226cc2e397f29b2551031fb6a4d4262e6da3d1dd91c0c164a357f67392926cf552b8572ead4d25761b4de425475185eae42c2009b73e251b03d3dbc1bc24b303e97f199b8de5bd54b64c5bc1ac0346ade0420b368815a91caac38669ff51db008141010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x54a7f5e98e3cfbd937ddc30f834d5eb7b7f7d028d43218e356c2c0e92d365b4ea8bdd0560f84d0076a2bd859ec928e2109e1226f49050d8e7948d6389c922301	1636120507000000	1636725307000000	1699797307000000	1794405307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	32
\\x65ecc6508cff20733f250209d86045f65f25a26111ce3367822aaab379751fd5dee16e0861ff3eeeec866cc6ef09e394bf9cc48eb664a86c1cc32462267f4531	\\x00800003936bd49cac95c0368f7d33b9626e297da94652fe71dce4e379a0327182bebbbecbffadc660e410b74613fafa6a4655abb39c136bb98b0d138fadcbb1699491a10356f2f4fade925ed8e06d740e6716456eeab3071047d9cbe086d0cae037cf4a11871e876390904d42099af32bfeab057bc347189d4b1035265c020bb65a04c9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0a4a18fd0122af1bfc7a5fb01ae102262d339f1eca46983dcb1a0fb7f43963a5bc6a203bb5bba7e6fc61e9198a728440d6fe2284fa358f80919db83555be7a03	1620403507000000	1621008307000000	1684080307000000	1778688307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	33
\\x66e04e2d2ae668784da3365d3d2221a5d67e802de865c376a5248ed6db856a88f27fc185d752cd12a74178c27897a8e563b7fc56cc718ec8f8d349c7ddc39feb	\\x00800003c5846db9461c9db2c83830066f6ccd338bdcde61e8e02151ad98f9465b7ff0de99b3d3a3f264fd42300edc1bb86adfde44c9715e633ce78667ec6efc4f3eb63be52e9d844145324c25e5bafeb520c4b3b898a8841ca5286c08d293f6bd70b171c629d5a304f02d24756681b94d340a001a29f1ebe317e925661a96ec102cd1fb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x22d0ebaff11965c63689763401c7c4f08c43f24c7c42f5331ff2b78db168a769335b4cac6f5daac222be905300141abce42163d060f849593ae56d92142f7304	1639143007000000	1639747807000000	1702819807000000	1797427807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x68ac9115ee60f9ac0eba697b0cca209392471e216e651fa08032167764fe4ab1be8fcd08de5a0deeaca9fcaeb3d117e0fdafaccfa4c5f2e4e59ecf5617cff47d	\\x00800003c7a4d7e4061812cbc0a48a31d1ed1a82c89bb5488e8d81ba1ec201a27ac4161e09181326aa9d5770d03a5150e83fecdc7387b67d1eb0ed691548f5d6383750dfa72503f00a97f9f39940743ce87173a04db04cfec008627e13623535e4b130cac51a2bdcae7dc09a929a480a7ec2914d911b093080a40a8e264100dca5235ee7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x46f4045ab5eb4b95501580cc2708020be6f84a49c067e94001f3023d8886c6faea41155946feb91a915fcb093df6faa9a0272aff4558f3cddf15ffdf51f6840d	1631889007000000	1632493807000000	1695565807000000	1790173807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	35
\\x6ba03b172710d2e30ecc6619468e7e4d81dc13ebc406f1fea09244bcbbc8e5c16f47366ec9c82adf6255daa5ea6084ee95216f08ce5a2ece7061087670190bc8	\\x00800003a9b0675cb7d2682b79d25b1833db601a62f78fd03de7a09af8d842e8532cd2afd6210a38e6c908e687998696b42f0c7d6af8989719e4cbc06e46750b13d12c2d2983a6177a8d3c27062db16056ef87f553ec3752059fcaf3c92b56f6ebaf0b07ce018ae8c13e86aaf650eb7d4ebf577e5b999eb3f041896ddec5bddad4ab0fe1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8c1eb43ef986c691bf3470b2a405c99393e76742b4ca2d0817f9a449c55fd9edea1dbce8c8d2e3eac9479640966581122ea901876d0c055c928f14ed5a438805	1624030507000000	1624635307000000	1687707307000000	1782315307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x6b5000077aa55e2b07746d291d274f9d97463a80cf113b81172db6ce9f0a4c9f5eaaee8bad2460348f6e0771d02e371d983931433c8e288d0d138e90cf4d3fca	\\x00800003a00ec50c2c916ef1fcfeb905ed3e673ff4f0d19f01ac439c0b743c2df19d04ee9ba4022904582788c91e8b53b3409db4481448fa2864c7e0ecb5f3454e7f03f91c941a2f99e0a9ccbc038467d44057bb74c9d708c23e0456fd2cd13542a28dda1a3f281793f94f40f53606e74ee27763f23ae586a7cf39dad245e33cc4ed9259010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6665e6f4595cac7a5861c6d391ce82d5b0b757a358994e458c67b9f80cb82b60714c314fe553953046bbe3b473b4c2d53caeb22b1d0d1755b7821a239d7cfa0c	1615567507000000	1616172307000000	1679244307000000	1773852307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	37
\\x6e04af8f0e688c9738ace24360adae9d2504152a62c8499c06ee64b1a9185d89bea6d588cb1d2ff6a107ffcc941e17f66cc369a76677499ad011c482ed3249f9	\\x00800003b04cdb41d8d2939b05ccd292921d064901a154bacad83242682262262eb79fb81e770eb49a83124b3d222fe6bb624072e038dc15876fc8e0ea857b403773def19c3f0013fa65a9269b0aa92b035089837f81bb5937c0a9831ca680870585176feca792593ed1ef242a74f51b0fdae94931c903420e9e25040c7793a23ff0c9c1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe3e0f8f5d44836802bc15f16ee8544f8d1773c6098a6e1e4f7d027c4b3bf50692c298bf0655f9c8018ebe8dba89431ef0eb9840dfec07a91452aab231645b404	1614963007000000	1615567807000000	1678639807000000	1773247807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	38
\\x74106dbd64d87786576bfe2137a586e82279d7ea0b5eacbff6ac8ac51ad9579331b98738c4ac14042f771b23f216f6de00c59b7eff22c3742cab42469af772ad	\\x00800003a7c5960bf205a77b8545aa8925b4b92f9abd66db2e5db86339ac11e52d7886b85ae6b10f0c9f1e0a9603ba2702b6f8c97205b037a094772b12e00dda2c2d247f4d911c952230560d3824bf3cd3f7899493654db1aaf29bb2f13f27e9fed1a0c084373f96650c17fdc3ebe9598aed8d673913570bca76074ba204b5a59d4a8e03010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0b5868fc06f1b6bd80c87114a2c460f9c3b965a0bdc3b181d442d09bbd0f9fd1cf685c3e7e6fe52143590cff304931bc3d96ac98e9f95e12d99b390a62db6805	1636725007000000	1637329807000000	1700401807000000	1795009807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	39
\\x76903d03e77fe025a326e97c444d6ff1535ac3bca3992208e1e4eda6ce01d536f6f6e13f99038f830a31fd7a5e82328ad5d9dfb08cffdf1d4d5cfa5d9c620ecd	\\x00800003a02f20d958645c7ca6035183a4d08b9dc43be1fb332e406b95f940ccde4751cf812684575ff36967f56e44a09af1fedc888dc64716b2d98a7aacbf4c6cff460e0f95dc43dc5ded919d4a56f61f6471e28c2dd228cf0ce4f52116e2be6bff9c6e01ce265ff7368174180591ae59a4847b9f039bff989308824770f76645ea2047010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xeb8c63ae06344ccb7879f5e5b7c6ff6dbfeae7846d4fead38184cad12202741ec292b7cb53d2de0b7dfa5c80cc0a0bad70e4b95115144216e162360fc0e96804	1637934007000000	1638538807000000	1701610807000000	1796218807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x76189f06339ee563135e34f83d1c86cec7dc814e71d47edf1a3f6432c96654dba6ea551434a05abeb9adcd1cb97008b7e3b0e5d83d18b0f4bd1637ab33d7c6bc	\\x00800003c736a1304e1bba9eed482b6c3354c273a1b847f60a7792f7cabe9cf5c0bb7d53b8cd6f1c866448c4e1048023e895c1a97153c1e336693c393655afa4d86f75ca427b9af323fc3f1e2de0b540397e339dc7305ad06acc0074baa01d9c7661fce634b4356b5e7f48da1fd4d2a2e1b685ff6ee600d5b5384e2422a0b1fbfd8f1b57010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd5b8837a82838b41dbeeef6b900fe720dd862851d17ae9ddda75d9ba43b9d2ba198f834e4ec82870f393eb3548b5dfbc98a1dbb26569fdb8bf167d2a2d397e03	1627657507000000	1628262307000000	1691334307000000	1785942307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x79ec4983380d0032e071c46d183bbf122c7c85bbebee1a8048575c00c9f5e5a73566bc961f01742a89dc6f9c609a2b4fbfc393673b58b5f84290241706dd6146	\\x00800003b7597169bf59e9da6f96443c512158cf88fab4dc2fe2c2a8b54aa6bcbff5ae3225a56dc426dde491ab0bf5a82f3b926da63677fb5102764fa27e7f9f1a1285f31f94e44ad00035a350c808a56594d74b27faffc9b227247370af02c209186945b6a58ce1e755bd68f07421174b4a6ed69f35e39cbbd831c9c65e7bf1daeab9bb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbc5ccb1c03d431a3de70d73294f104a3947c7c1acd58725e1b92e1b2f5943660a470b474b79961193466bb92c26f271d75f0310c224461e7dd7e647addafa807	1633702507000000	1634307307000000	1697379307000000	1791987307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	42
\\x7a6cd2d9bce03a78992164847d3000fe9c2aa721dae832dc6bf805824c3422c0dabc0407e627e6d47ab673498cfef2fce1f47fd07ef7ff25604d23953ec13d46	\\x00800003b5d2cad13dd6b643cb945e824f3611ca5a25b0a35cc71e91d29e3c4ba0bdb3e587540a3e873c9be6f964cf9b1ba8232fbbb46e1ba0d4fec2ad94939eab7ab8470505b16733bcf87ca98b683ce3e243c6ff9d40586fa89ab22f57468b1a06200e9f34fb22eddbfa1a2bd7b8a4c4100a3c47fba905801d0af5e6ff096638f2a37f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbcca2ab0fdb64e6de2971af16a67365c92e79f6b3d3c34020751729fee146d543d3996a9410bd22d80d20db9be254319d8871160b4a2a6485436af282fbd4004	1636725007000000	1637329807000000	1700401807000000	1795009807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	43
\\x7a7c032596bb12aebc3d639e33defbe32b746de890eba9c626be116e7ce615cae80e382abf4c60c5bb3bbec556db6953d943ed66887b70a318e34044f142db54	\\x00800003d243311d1d142b99b0755149bdfbc7bf3ea2085e53271598b00e7b1015ccf43dd2c322a4b6ecf0df61697d007d5b1fb3be8e638ad82c928abb277d28dbb6e1f0fdc54b0721ba3ce746669f20e9fdcb5e0a1cab18d42facd90feb25287ef5b6103406d6f6f915d97cbc9649376540f9b7b3cba1542eb99d1ea3bef35ccbb37b4f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xce070d5a70231d805ee3ec933ec02763dcb28efc020f7e49b79b56e2aa1d4f5b1ea289f75aa254dc237ac07231179ddae01798f393532460a4486e0f6abe5103	1614358507000000	1614963307000000	1678035307000000	1772643307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	44
\\x84709d721b798d60e81c5d4fad7ba2783ed70a59e5652c7efeb11d293732fc39e5ce90d93eced963f4793ee02ebf65f26928c08cd4d68fbe04bbeaca4ad26bd4	\\x00800003ab50aba39249fa97d6d95f559c8c2d503ea9cb6742c660ee9239eab424d0adcc1f7d0cf5c54e110037afce475a32022e10b1e9b011fa93755c5067c6ecd7844870b163bcaadc79890e68ab39b8e08f2d419b1734ffe5bb23b3c158042c40b06d1a0fb8f95dc42582e1514a638fc68910399e2017f6eb62540ecf57642ad6f257010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc02ff0d7b47dfa9200cebd9a40cc578a997b77be35dba488eab452c630a88bf9745d05c335cfadb033503505b389967a22fff22e2bffd004441951b6e3cc5f0d	1611336007000000	1611940807000000	1675012807000000	1769620807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	45
\\x8758f14d7aa830f6be7f7c5cb0d29b176725314e63b075fb287faaf412c40adc6738a97a5baf357f749b33059310807f4aea465e9daddb7ddd09da85b280867e	\\x00800003e7701edd366a9710375934fe34e04d67abc26c17a777bd15b9ba040f5b2958261ad108e86d9f829655808f19a55f3f0f3c5775aa19fb5a90e76943d3497fee85b21e8a02bffc271dbb1c2c4eecaa821ff7c38be7571525c5fd1935bff6cf4f93fef284c27f0eeb4d4261f10fb016c4e235c36c2091c3887fa8520a4dd6e0cec3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf0965d8b9d42dc363fd618680103a1740a8440b07c0a687a61461c7ee6dc1f3ac15bd278f1961dc9e15f87e30aa5b89edd7aca7f4b21bf0b5150a681c16e8b01	1613149507000000	1613754307000000	1676826307000000	1771434307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	46
\\x8a78fb607ef984eb32c638ab4703122e09b8b23ced9ccc02d31abd907014ba42cfd953e7856f46136632fc64fffde7ac7e0cdf02e10057818ae64d0190ee32d2	\\x00800003be2a62a958bfeb4a90cb807e144f2fead38cdb93da6c56e9d7b83c384ea1330ef67eb3fc6b06400636a7c42f71b0443ad73bb228a33a7d60858c5d2696359d78053ec01ba047ad76c5f20ab0a22a6efef22228aa3642fe9ce0f18dd5887446f41bdc5b94b9c66bd6a603619c178d47c6e5cea480d7d5be828d64c0b553b37185010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x75fb6d90f205568bd47c0e21327679f2c418a54fb4638c72f27518877262ae2703f7aa8c1e8318cdf00c98402378c44be4e7454e2228942b698c71c0bc017f09	1627657507000000	1628262307000000	1691334307000000	1785942307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	47
\\x8bd059e1cb1ac556b6d05cdcb58e8041ccf9fe49a0a6dc81543db5f39e7b474dae355e4bee11330f49d6f51f955bcc31a9ad6b208ff32bcab3856e3aba8d4aed	\\x00800003db9fe0d1bae3bae833e47cd1de222501666734f8f6a013297dbbb798caaf41de4f1b5950a995c633ad2e5ef3c63b65f98f9e9f7734b90910ffb5c17eea84d033f923a1edf0b84b1585d34a48bdc40c380c47fed7461eff519f87f1a63ef42f147321220d2fe0a92e433facae2f0f160fd12c997591f3d2c72de8a2f1ee1114e5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x094c919d5249f43d15fb3639c3a8556b7b2da84f2f6e5bf9cb407565409b300665e6783fad46c5f8dc27da6b51b749151d76e51e71aabf7a3c5452fb54364809	1634307007000000	1634911807000000	1697983807000000	1792591807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	48
\\x8f7c78bc6dd04ed6335d14af07dc620fbf932fe6333bc27437fe187255bb55622d0da6f6bee60e796dac8c17cac588152936bcedf9363e73f1d85aff0ec71c0c	\\x00800003d203675f8b0487906333bcfab847589142143b131fc6fbb724408bde45ecf145f09a23070480761eea80411f6550d7a9cd79064b39aa4af5d53944b03a9ff2bb86ba5f556ba4691e2a9d62dd37cee58a10ce0fbad1221707907180da149bf32177d33932fd9a1008d795358cc84f0eecfb2ea51f9375201e45cf1810de4a0cf3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa84f96ee075e4a762c357162a37bedcbb596573378787abaa31dae7622ec11f091e66f3889e1febbd41e2d779771e0f287ce82898cec6736db4be7d192942c0f	1618590007000000	1619194807000000	1682266807000000	1776874807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	49
\\x91ec2ca03e9643f053a73549756662a7a4e95bf3cc2e4d5813e2731093f1e7e7aa8b3c258500169a5b9471319cd2e763c7fa16abd9cdbf4dcb8c71f5b1f54527	\\x00800003ae08cd414e38d437312d44a77fc830ee9af749101b423b82daf11e60a93c3ae6edaa10be6d90cda2d7b8313d765a0a38dab09585e195f437ac497ccbf7127c02335b93f3dce2fa515a3e77196ca8584bbac4c8a23ba1e25a5a64829ba445c77dc4d3b15b79edf8386d3a5b274be7cc8ff88b77d12e6f1af2aa4ae23b201fecc7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x61bd80ea95cfce414bd888ad8a667996c7c8f2a541e356a825d9a640217ef3269bfa985ce0550823079782d6feabd5fb9d5e17cafc8d622e7382f3da657e610f	1637329507000000	1637934307000000	1701006307000000	1795614307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	50
\\x914c1c3c214474e02d9751cefbe7612a467883db3f63c6e185fee847470c43611039245e6d22bc8549dce2aa4a8586e0995b7ac7c08ea3e4282129e79a8cc3f0	\\x00800003c5503f2fe86773622466ee9e02e573593be534fce6afe1f3b1475b9156be5b4be2436ce641249b7cc3ee59366ef656618324907729a52f7932dacc6d5575fc226a7abc6d1c924ec1a2a939efd8160be31643556967b546fab5719c39ca3e66770975628191e51cbda3df59ec5fbb5499ad41848e8056bf6047ede9d803f1ff8d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfc56302a1ed9d78158159268c4ae93a97df1e44439528d5b10d49c24fa48f8dab1894c5d7e122121c0359477f2a9bb4e30eecc759a076921da5ed343c35b7a02	1619194507000000	1619799307000000	1682871307000000	1777479307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	51
\\x93c0fafe685428c47cec2cd91c459a077238b5a61ee736ced5725692f88452af34164f32dcd7a95020607025bd60b3f7f0f2ab9100968cc5decc08b11b81f247	\\x00800003c3ce77ce36e73761db5ea7625bf1106bf7a9d10df8e1b6b508fe7a8feddeca9f84e02f0f510b89fe91ee842ba0e4f4d19da6f145e9b15f7b0e1d5ac0ad4b3f12fddbfd4b8bf16c8749d109a7d10d992fb247e28d016c7c1f2bd520ce59cc9baa3ddc7ac907fc45a8d031f815f44346f0d474981a839b86da8ed57e1f93aa80bb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8c134b6149585d1ff33cdc42dd42db9cdfca022fca12d6a48993f5901e7d8966d8dfdea5f674a6293f76a319d7727bbe710d3cd1f9d4b17f98d0c1715176bc06	1619194507000000	1619799307000000	1682871307000000	1777479307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	52
\\x9d9cabf99f9e65c4a75076b2fa1b49030da410e070e4ca8ff178a07c5d570a55722700960c6f832fb9737e1e2dcbb8df3b25435c4f72aca33230fb3c787603b8	\\x00800003bdf67a44cce6041b39098afc5283211b664ece8068a8e1c35ff096f88fbec98b0c95e816eab8b437ea2923e35ddfe7621ff84df4cf50df3828426be5f66583fd9bd2e10d629b6551f036f53d1b02b5557982fa295e4d485c5a04acad39d16623131d1f153a801806cebf5cd2239a4ae6ca795ad2886edea371ab6fb6912bfa95010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa2482ea73d15ca4779f5233f84371a269c6f8c9cff4303757a526dfdc2d5a053b2d45b1d699f33491e12ef0433a07c316b144260b7290978350c916fb0d1af04	1625844007000000	1626448807000000	1689520807000000	1784128807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	53
\\x9ee8fa99e0dd2dc195ef97e333af3dc75faa30d5840c15eb17316eddae27769bf27d33bef62da513dd5cd3b84e219db41e731e78ef43395731997021cf65fac0	\\x00800003d0893496989b43ba9a1ea20030e8df077f725909f942f754398a49963564ea4faf0d81dd4dbc9c01632e1d722bd64f9421254b8dc16ebf43b66db8726e3587f616f1422a7d826d76d821898b9fe5e8390e24bf3e1c0db267052d4e0d70b51bd19f4d779cee241a9544b6ee059da902023aff77306e96913da09d7a8417a14005010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5716efa1942f543507c08a21110efb9cf088bccaeb964272df58de6220d5d6ae8712ab24429d257b088bb59c68c0ea028d0e846f178f2aac28f293620bd5a809	1622821507000000	1623426307000000	1686498307000000	1781106307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	54
\\x9ed04720937eb86c87a4ca51686e28ccdf059159bc68c08bbc639306b893f6aa9e6106367531f646f70b29e3dab64406e951e3b7c61af07fa2c76813fd8afd54	\\x00800003c41820bb63733fa40beee7f6b97a3ac422adc2b373e11ce0e7599fe51151a7025d682de6552ec8df12aeecf91b271b565e11d027deed3afa8b6da5437b12195c3f1262f3b6fd5f92f5515afa62387aaf511f8e02a09edfdc92aea587b8b764fe4f09f28c0fbca7c5c7eb5ec5671dd204f394bfe86635fb4abfd1a160486eb5ef010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc21dfef01496dc9f5ca83f5fdcff6e13ddea8c2980114009f8c8785d243c5608229544f48d7e648fa5af38f068db1063018fa7af0676633128b64f9c16f7fe07	1622821507000000	1623426307000000	1686498307000000	1781106307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	55
\\x9fc844e422d8542fba84d02c24f51dc6ec41030a3adb6434b8f4d08de8ef5248c318bb80b5dd507134b3d6b153b30c6861ba2b6e86611186ce3ed48ec9243f2f	\\x00800003cb3cea6ac48ddb2fe2d12de894af07e9d1ec139c694ccaf8d864dd4436afcee393e0e7c24fed0bd9c52d4d691cec2752e336ca24bef8ac6fb316daab94deef7e3cfffbb177d84c4adf11e573a1a6e18cbe928601cffb799635cac585754fce9742aef906ce37547bc8549a9dffbbcf35bd7239e28b2f4346e4f71194d513b3e5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb3174663512b940d03bfa094e9b943257595ec74b51ec4337edaeaef43bcd9e3129523ea2e3b570bc8538083c3e8835e65f488a284a48e1a4d2aa20f8acb0f0a	1617985507000000	1618590307000000	1681662307000000	1776270307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	56
\\x9f64bf93d525e4a2d92eddf4f0639c874907f832428a396b48becd0e8dada099542c54ccf573d09eb46295f00ede83178e554d3ab95abb6ca12ab7790dc28ad5	\\x00800003ca4e7d10482852baf1d4b23350ac0f065748de4823bb9991fef6e498b1a48b4c9ccb22d494dc5792e8cfbbeab659bf052751259912fe49ad869be04fd20e3520b15c766e47b1fbbf289a681ef70275cc4006d8fd28e9d0fb7916a83bf832bfbed56270d5af8d7b6c93f4c78fa171635a4aecadf8fc26696128f54e7355aac03f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd7c36a582886e83fc4f620db8f01615813637e6ee596386840b055c0dbfb2b442b930cedee654ea5a88f0442a2e8a7667dcda94117c2eb1aece71ce85d476d0a	1610731507000000	1611336307000000	1674408307000000	1769016307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	57
\\xa204c0818c750bcb8559b67cc82ccde7ca9d9e7668e795ff7206ecd19a9d51e30e0acfa93a45031884f0d81824c705e94835747352925b394232958cb284048c	\\x00800003980806a3a7cc23e4426e6f3bf8132623bbdea5a44dfed80f8fe2eeb72b421bdee1a8b76791bd6c86770886d35df37584dc0ec70db25186c27af3eff42c90c78033a94586aba898b478ba528dfc959e33b21d03fb7ae36779e547c550ca96451ff5701fb3caa732636e73efac42024c2ccd036e5b511dd0a3b8b9d3211eb56fbf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x84fa8826e1db64471711e6d16b1e561203b4fdf361438354e31bed1ccedb8ab6924507fcb920810ffc79a979ca7549290a4cdae0f2b3fbe35397cfa8deb8a40c	1633702507000000	1634307307000000	1697379307000000	1791987307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	58
\\xa69027059db0e300fb4d7a5cbb557e0763034ad8fdd2c807c3458e18587809c84b450cae852292531500156c1e394a0d0becd5c4bb2c1766a8e86e3aa0e9cbe1	\\x00800003ba812a35f9aa16a9bea04fc4993c98e0eafc782bda71367d10379f1cd6f0119adf33b19a81b11769452ddae25691178c6212406286fc5ae25dcb6352119c81049f6d46aeb354afe399c152d1090396ca69bcdb40190061ebf43d84ba753d9a302ba9b9d7a821d2a6bf5560bde30e9857be627a03d2cd47bfecd075cb4280680b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x33ebffc59dc8df2a97f0de42b002ebbf41585664c1b00fedc19cd1cf2af26b5af5da1420e3733537976c88b63ba711ff0a1628e21ae6ce53a9a8d6b8ff230607	1618590007000000	1619194807000000	1682266807000000	1776874807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	59
\\xa76c0c4ac060a1dddbc9ac368929a7c72801f18c9a2249d2c02a0c57b5b47d92e5ed5c01cdff368cbd284faeffb1903b54598c896a4c5a80f22ce6db24dbc0b2	\\x00800003aed3ccfef196f388be875adeeb3f2eae2b6dbaf911d08238c059d392e3dc6fa48344ec655cf9ef956e8092b1cf9b45d70dd4a5963ba034a60138b58bd6af345e223ff4758b9c2e8f24356a4694dec3f668d8cc1d57d93c753f09e91061b5401e910e8ab322b42fd9dfc32d763030c68f0a2c844ab41f43db226d98dd8ce48987010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x68d2b79cf49d4add0738578ef4318325970dccba04906e1c253a301995bcd945a1efd8066f58b2cc7335d823e229177fec647762441b3379f8b8e1e5c1b1390f	1628262007000000	1628866807000000	1691938807000000	1786546807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	60
\\xa954b0ed847f4571f5f501bc3eb5a6548451185106535a7b487ddf543cff0bcf6f8c4557adf2603a446692ebfccd60985e9685fe775fe76ffeb74cd1b8f0b2fb	\\x00800003cac21058bee0986db45723b9acb39167a1f8e47ff974972277d7b30cb1f3bf0b360b9d974b91b274f739936ca4db3f2c276f7692247be1d20aeef83ef7c9b158ffb079056adb6d7b8aab89a4cece772ed4520661655c85c5d6a86f9ed97d9157dbbbf556fdd858c35e4dd7f46245c947221b1aca38e2422e6e897fdf24f94521010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xcf41e902c391e2398d3d5a180ba3f29e10aa8bd2af92c0e4a4c329a9f097abc784a2b0744a0fdcee91a064643dfc5e27f346b175b6abef3ca416dba29a57d100	1627053007000000	1627657807000000	1690729807000000	1785337807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	61
\\xaa44eddb6ca1640100c543fc0d7a406a287f2e1830ab248898c857d550c0642eceb5429f04233d46367a7d3db4404061c764c5e769163745dcb313c3a348e612	\\x00800003d7f9efc8be44a764ccd7d19f9ac49e60bd6b4ffc06d506c45fb26c2461fa2b5bbe3f4c979db1dcb057a658eef34518b328074582f86b186b3f6fd72faae9e4ed886d2e0b69e2e2b3467be09e38962a9d6f5935fc5f1cc9cf55f8dd398c10fd8a2c6e924b2f03f9339f240020655461a8fae8a048ad52fa281433ae35ed531c4b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x877ddbf5acf7817967856ff59eb910563d7285c0d9546c4ba346ac02b41467e76a4cdba37731b01b4f6c2d932832c36e0475ad94501d85eeb52bea89fa89a60f	1623426007000000	1624030807000000	1687102807000000	1781710807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	62
\\xb004550d3818ab4784c4b93c0a843cc889a03b98114fd205cd04c1b03a0b6543b7dc875ba53b3d9bcb441f604da16c3557fd27a5a581e29dc369251a3dadbc02	\\x00800003f10846fef1414ab7d26c22575ad80f06c08fb4b7635a216e692de8e3267f15b1ee8499a123a3e3d8ece8a50b24b862fab89875a0568a1226cb172d3011e8a84c751be7b9bd05bbcd3b5bfc8c538101fd71f873da18a645c02fa57ee6da1c8a502fda35b971274454c839f8fb608a272568a41908cf6bec0312dd1bb8cbc58289010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5b82138fc49867bf2f7341c56367ebcc18a4f15739bf13f7b54eb1c120bd4829ef09ed1a5ac5d762126559f1090082f950080bc548b9cd06d2053dfddaaa3200	1631284507000000	1631889307000000	1694961307000000	1789569307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	63
\\xb2b406f1d0cfc405f752adf80a718d7c580bf171bbb064484482f1d1e2043ae3894ef2887337ba4186fa1501b6cc9695d39f40bbc25f32cff81248eb33102b54	\\x00800003ca94ca719a705c9af827b152d881493371e305c4b23897e5079cc85379b1ef55f66cd7dc504aedca467c6e27f5017af1295c41d62cd885ee95c050c45a8d85b077e77f57ebc43309c16ef2d4ad0d726d4690c19e36a5b741601acba96ab9548c7abbbc5150478f86acfb1ef0b2d37654e62de549f39442912623ff59dc109f83010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x92bd9f1294dabaa96c6779245e669e41157201a90c5e4d9e4337fe785cf1fd3ad478131af2a283128caf472745b493603746ce6f8dea7f0f208693e7c34d260f	1610731507000000	1611336307000000	1674408307000000	1769016307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	64
\\xb4ec5dd72e6003cb0c85712c91bf596490f797d776aa746d0fb4423b533ca5c8792c4f7d887491a4ddb4a8a27915d6b519fd7606d48d95711df03ca6573ad782	\\x00800003ab8b708cff27f0b04ca5181d6a9a877c5b44d9dc821e4f38356b976b15d93227672c2d7101634cfe2039db640beb7a0002afa63111b969dc91c3ede3052f5cda2143ba814701b228e53e820b17a3254249572e4ae812806510ed882f74f6232fec93071c72b06a585a7bd5862d186d4b8df833d24f9421441b484c2babb0930f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbc875efb3449147021d0de8e2b5b7fd5b7d33fbf75007a278259735f8a93f195dfba8a074e7565bdbdf769e8eabe5f9601f5bb07458a4959aeda889180aece06	1620403507000000	1621008307000000	1684080307000000	1778688307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	65
\\xba5851a4d32e66df37d405966ab07d6b734b43821351e80b4b623c12b44d3769b51a9b9803bd5ff04cf5f06dfcf6284e45ddf3bac7c704ac0bcddd1ed95e2ac9	\\x00800003972e97559b31d8feb1cec061d08de5f8e1c42e98f8b4088d8f84f1dbd0b692bad043f02c5bbac0dcdd3bc03868d43c4a0bee81ec46bc315901b00d217cdac072d376c5985b9b5a60724b369909c282314d2864685c52116d6956737ec3322ac10b390d2f787738b69148bdde3f77819be9fb538d4615d277cc5138ae590ee211010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4db04803cf2f9dad76e43266905f0eed8d389612b6e1f46598d4254827b77f760f659e01415b58a8d7ed5dfffa1019d0894d836a68d5f5b25cdb0b55c1f2810b	1624030507000000	1624635307000000	1687707307000000	1782315307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	66
\\xbf5ca0792a5dedf9ede29fee59ce0e640272f3cad2fc0c285b4a9f773aad77c51f22b2a1e64828123e31fd7fa332a2fd68b5c7b481664b89e359fc10c3c1fa95	\\x00800003d2b57e79e0e6ac6fae3a732a71eb1a8d6b17be3edc70f4b34a3561468372af8f71c95b4baaed4f3bc7126ce7f1e5f9e24ee6e3db96c0a00103af6973ca550f18646c241725db6b76265c0caeaa7e02ec830372f11da102a8b52685107802c0e9d8ae8873b7514586bb7260b1655c5ccf63b0d805ff2d0d3bd32df4f2629f9ccd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb6fe1637c519c1809141bbd945d896181af4ced3ba148f880d1908bbc6a292887b56b961d3254b09d3b6b188119acc81d5828ef77cf3ffbda1be6d6ec30df40a	1616172007000000	1616776807000000	1679848807000000	1774456807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	67
\\xbf6819669545b5abe78a5c1f0c9ec79013121128915a210bc25d339f88ca2b7500ee39e23e86d9e8d10a8713bb877aedd30c17347c252c63963fb0fc8024a1da	\\x00800003b539b38a05836e171d52be42a070f3a129aad704cb699e5e4e0937afc92a1443d281126856d85df164543016d063cca0d1176e4d9197fcac6484721328de4fe5dfe3e6a87ca3af235a2b635295f645bc8e69c331896c39d584bfb82bff8deb27ee1453ff031ca4c7a045b44922989ddc6b0f31f5cc2cdd1ccf9934a8a29731f7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0df0cbd5c33e51d8ef54868ebfb52abb1311c1d2209e7363fc348cdaf0ee9eaa989e60c4b27ba3e2a2434edc95e7e53e7444fa175dd05102a56d3f798026790f	1641561007000000	1642165807000000	1705237807000000	1799845807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\xc04834548646bd2ee70b6e1d8803ca4f5a904a4d338bcda7df9eb3603bf95bdcc6de8a94cca330ccb0c3284586f266fa8d8d44482c159e35765853b5a7ec71c8	\\x00800003b303b4a300068259ee1708cb4b373db32cdeb92669fbe16607b27550bc231d6304039dea63855b57681e20dc8e4e73e3ef80c536073b7d1e4a96ae6d3c9a1b4b8550ecd1b6cb61c96f9ff599087aaa31c4b8a5cf6f508ce11ed3dd14646b646105ddd46c9972501517d9292613c1b8e9342bd74a6beab4bfc7a63e15f8a23567010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xadc8d4c3e7ce42f0ac002be86fdc54b26a9b5c203fc104fb5e97527e49c83d33d25199efd85867a1533f4bb8d8b2206d5962559379d9dc2ae4f65a06a90e0800	1627657507000000	1628262307000000	1691334307000000	1785942307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	69
\\xc1789445978da1e1bb74cb8da5c033e9a33e774e591380b43f5ed39dd3f51ed46cf700b2f0b191a5217fd65d8d1adde444b23141d31bcc2199680173bc7e5b00	\\x00800003c0680074e38e9cf816900c849a56dcedc14ec8b1b685c26700a1b868d15c769a9af92367be6bb50a1d97a85cce6132bdffe60c7f2b389d194d0065a7872c3639880a61b5caa2134972244c6983aebfc1d88825e0c744692858c060b7360500c76a328a78c781273b663d5f4ce82dfd4c938ad05ba4b2e4155bc64b8b899396f9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x088871ba1c1c19277a4586aea64aa5004e172433f46e081b7b99fa54f9f7dcd80d1d5071f90ac2ab90960865ec4e07570c829a0b949f15bc80fd59ab0ee9e00c	1638538507000000	1639143307000000	1702215307000000	1796823307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	70
\\xc54cc9e64a21a94faa5946a4c50ec123f14c0cc8a3629d5c0a8d848fc8b380f921a116067235cf0818e5bb41ac032798fd33e95cdd68cae09908a9cb55cba83e	\\x00800003db1b0224e475c14e57f29179f90d1bd1a50a7f613667e540921a5b67f8962423cc6d21c08f73d94c8d0956e4d5a4024f6cc364cc996a91e36bf6c691aa431fde471300b1829061ba60a765889f9b2fb71a4ce243c49cd6f6fbddc9714206574deafb394deadee22bb8612066ed2d084219885f8b67813b757b36f210c6696a5d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0ddd540058fd91538f30efc724874b0a3f2a489a6de918eda40c691c8f2f7c8eec982e911c788d66a3eca4cb4c410acd62f6c2c3561eb5fe2fa5c991dcdbb009	1625844007000000	1626448807000000	1689520807000000	1784128807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	71
\\xc67c0239ae50807ee8ca512c103534e698c1a87e11a82d802b5de9830d69230ba9bddac9de09ae610cec1feb3b549d5bfb7f9b554c1ae1d2a9dac15253e54704	\\x0080000398cf9fadd641676f589807bebee1e08bde7e58d5848b1176b605ad3bae6e371bf26538b49e0f611d5df8dbbf82325ac3853920a216189cef36ab50b7bb1d7c07e07df511d822b4729c09fb2990a3136e8fa22d85f6c23582c30db95ce073d2efb96572ca12581850fe5dcf86b75e10624d9fb2f1dd1ca1a5f4024ca0c2b87a2d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xdc227d1ad0f93de0d506a201831863d05af561115c5692f05a6d49ee203468249651795403a65bccb32b6979683475c161786fa06c0dd758c12e2ede799e710b	1619799007000000	1620403807000000	1683475807000000	1778083807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	72
\\xc7b0c86fed3360403bb71625d8bd84963ada83ff84c17fde1477a7824e728fe6e74618caa4ab4aa688b2bc84650982c7ff64fa16205ad3d4eeacf591a93109df	\\x00800003f3e7137bb9a5d1c59a0b2d790eb988342398598d489c43727d1a30884918039b1d9844fdc0189b18554a67d4f8ed490af037759c4bde3d4ed96336a1711b83d3bb16091157100f5b83a8e5b2b36844dfdb2ad5d05ceb5d88483bdeaac169ec612aa541be22e78eee58c24b8df61a2f1e13076bed506c6671a5d6ca8a5238dd65010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9a66dcb1a9ba6185493d377920502ac319f5b723ab34c47adbdf978db6d1f287d12b53bc7cb928758bea4fec63cf9279a0af925c39523cd362f41257cfb01604	1610731507000000	1611336307000000	1674408307000000	1769016307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	73
\\xc86465715fa69f0dc50c447ac74a7e7f36f4490e3f18f62ba8f1320dc03dc727ca4e68ea04bce473a9a7787364f1184da0af323a19b59df68bb4b6233a1dce28	\\x008000039cd3e1c1946913eb514bd78b40add1152905d08e4a51fed1c5f641bcdbcea4178a267a7d39f33eb089bd3daef17484cc61786d578cc2b4482e8b8604078a4d274dcc4ae7ae1c00d25fa0935ee484a1b60afc574b04d76e70d1567cac379b34000908f192875a2649ea4814e953132f92eecec9f2530b0ab5e6899bdfbdc982a3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3110e4844e7beeb7801996feb880f14ea3245197e0ba1b376ca333b219f89e181a26de5b3056b0a609c4603de29ff78cd378eed2b2a80f6aab55ba6616f9a507	1613149507000000	1613754307000000	1676826307000000	1771434307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	74
\\xd540ac80f8e7ffb35901b9a11d816c82f746a05522d9efc2716740ce057d26d8544455eadc895e25aea3b331e37cb70c6fad4dbd5a4491adaff2771547db832a	\\x008000039e15870f9b4b7a2fb27eca8c562ccf3d9a777abfabaceaf94273ea5c397f896ffdf6da93ed48c648f1635fa918c470ce038a4a24fd7cfef3db10988a7c5ef5a7c9df8ea00c26f11a043e2639313726f8f5b338ae7b34c45f2d009be572e05940d99a3bfe29bf2608b072f8fe806c38e56a79089b968dd96eb30f458669e0bd7b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x43746cbc2b5658505c7e414eea0473715ae6bdd89236d91204d7d0afe3048658b57c105db2ff5cf29bb209da43d03fff44a61eeedf4af8e5fee9aa4736490d07	1625239507000000	1625844307000000	1688916307000000	1783524307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xd6904dfca8f1213103f4dd3388f2dec1875bec08e0f5a4b22853396b5e14e26e04b1baa34e451273b548530b1cd3886a783437e4b4d768b979022353d7cbbde2	\\x00800003e29a3690d31b5defb24557f35b063a4dac52732eaa8714ed72cd77e638f28cedf512f76bb21844a882553113bac41f6c26b1ab654eda0b65abaf399f1a230c875f8eea9b31547789e4a2d1cf3ea1a4ceb77356e83faad1b6dbddd643290aaf7d8502c183271d26b31b6e1ab982b719573ae887a584cd64a33045ebf967ba3f39010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa74dc6cae3ce402a4bc2dd460abe7e02eb6cfeb575c4c8367858383eaa7ca818b549d01b4bce4fce2b21f0fe8f5218b653122a1d094ff4c393aa9fc1a78cc40d	1626448507000000	1627053307000000	1690125307000000	1784733307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	76
\\xd6b085d9380f46c9481d1d96b378099253c996455d23ab6dcc33c7843bb5ab6bd0d5efdd097a335470e5345cb4db3c4950120526415979e0a5eb6af51b3b9f0d	\\x00800003fb36d884ffbcdf40565d1fcc64b25f646d2aa01a11dddcf3535cdfdaac1e9629fd1ca414174f354b6dcf433ef5a5edca7575454c100ff3b04dc6e76b8aa33f12451eae3ccc2a9981a3abb08e2f9c5fc246b73da5ce689f6deb6e53f896405f789693054355ef86455a48bff550aa665fd0b900a562fac6ced2a8d166417d8987010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2ed1fa9d7dad8f966cc65b7bc4a87e11e770ecec90b92135640d7a094b290d62c1163c1dd060a75f5bfaba5769c638a5c522b29e91294ceb36fb71834199f201	1617381007000000	1617985807000000	1681057807000000	1775665807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	77
\\xd8985f8149a33dc8ba477730cc46e11c2f6a401bc2c3e26cb36a718f6ed8df1fec5ce9af8a44b3dfcc6dd80fa6b80089d6e9e70ad568520bffd6ef877763bf70	\\x008000039b9180072f89b38d8336167433d8938624f5f443a9b0554e9ce9555c28b42b1cab80d8fd556cf7debdbaaa0a616848d823ba5bab39803d663f2333b7b6d4a6985ce4445a7b23c5da7c163344a55b91ce4bdb050d76e313ae02340fb4818fb3273196edfbff98c523f1c4ddc5b83667bdcaac923d01475b90a7bec98b75857357010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf0f1a37bd2a16ceccf9948e4f54ba4c5d4157b65ba21513a792160c2f2e5832b0b73db79b0590fc709611676ed585d333735caee663dcd858188a7ecd8275f03	1638538507000000	1639143307000000	1702215307000000	1796823307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	78
\\xd99c3170cf490d3e1e470bb017db274be1bb6bc6cfa38425b7330ddf3acdcfbfc59de2e154de9ce95e78a9341a700ce69469e8b6db6079e09784824d97c3623f	\\x008000039911b25b962b905a580f9159cc25375cf625dff7043da5e48476a3182c51ba285999cb537477930922fa200d104814a35a6a234ccdfe3379d34b04854876b7e7d85d4a070872d5aa4bd7497edc275d5b50a0fbae140a08603411935901c9d14852c68118876eca7ef62ebf036962557e3b411cda2256197d00600859a4b39091010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8e1f5b99eec836b4c4e73720a8a38f504af671b77592c3a7b9b73f8e70edff6f1ed60ad904fa7a38ade2d1f28c35b0dcd81aad4190430a82b331efc1b25e980c	1630680007000000	1631284807000000	1694356807000000	1788964807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xdbc00fa063f0c893ed9c0d5a0d156cdb79235dd933bc2121489b7add347b1d1369f25a60d471705c782800ce4cdd52f80338cf9483b63cf2662b29c12d8b415a	\\x00800003c1177a1d04b9b7a51a8ed062a3a01a2d12c8511a4995088371a2a68122a72792e3baf8a0639108f61877f03af2a4b0ab8c4cc1ee458e6051a7aaf5671f7341eb2d0f408fe9d90c5422deb3a95059635d575d3c04a42ec61ac57774ff5ccbacd8269d94ea7545d5d9ee02630785759bba8be9649c29be4c3afa9a564b4cf26571010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x117f607116a93ee2599a213f212e8d33ae7faf9058bb6b9d70101c1fdd16cf83d2fd92117697fc5b08cdb22470756286c99fb6b4dd7ac9f1e4000385e0cc9607	1627053007000000	1627657807000000	1690729807000000	1785337807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	80
\\xdbec6e8508f58bd5b39e74d87e91e9719558276b8978f2579528b50823792679c7f40c05584821e8f6d660396b46527a02445e287d5e2083c642e4fa349f4538	\\x00800003a0721fd22babb61794acbd91372b2efa77a2488ff0b40b8e7eeadc3812fa6338dff437adb91f60f3e6de904d21da044a02550a041431c7dd828910ff4e93e255f27e28ac082213210a6ec7dcbcdb22cbf578ee84fd6c4cc1e2d12d97c8e33ccd5041fb3d1640d4ecf23a7c04b790f2626c11be31f1dfc4bdbd5fd934487f371f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb4ac86ad071a4acb3ec1f1e88e80806a805e44d8653c5c59fce5bf5695936132725519d2b47c03b2ac403f40236f71eb46621bcc9f09a601b7434b7613cca805	1633098007000000	1633702807000000	1696774807000000	1791382807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	81
\\xdcb8ed4a328d5561ca80439827388e848ecac8bbe91408fc79ea35ad56c2ee2fec252eb35bc00a60c0faf52da21ef37acd9b1f9f8f919fbde1c21869c80a42c4	\\x00800003d66a69ab9915bbd3c60043841ab84ca06f0f2cbeda464f076a206e7090dd50fb0051a8612bb47d08ecd525608feb70e1376dcf1b499009230d800eaabe08e611bff0ecfb2399208151fac64c01d0c03b91bd14415571808f77b3c1a1b95ae3ea6a0d36bea1f0c3c88e47342b90ae7f662c4fb6a748fb9845a6f1f1f98f4a9395010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x38de1a6b8c78968aa1ca34c315de7eec010859adb3011d36538a5cd8e16036e55cb76f153e5941d3076900986fdd61e3328057f0336c5b406dad03db5b39b509	1616172007000000	1616776807000000	1679848807000000	1774456807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	82
\\xdea000e720c1974c104d49eb6e336f2b47e130437f64813bea53f58df02c87e349c3d474fdc6b20915834a5ea7be6523c969fb2bc818c7b3d51342c66d7c1b82	\\x00800003d9c4d9c7df579165dce530d62864c516cc351de269f06412ebb0d8644848a5b447cf1c52289228512f699fce1d6b5f5de7bac3342c7a7189153c452a41922ea5a9b13d28e121f28d3b6b4e84e58343ca3af939f647e21b74342ae4f97198d5d2a97613a228615d155e37550f94b76867d9045f76d3a212b31ec06831ef4b12e5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x505dea4a97657f1a707c873c4d3cfc4e3fc1944153d97d4be494f3d3156ba97d2f92aeb073c16306cf14f0d7507fd3a18633e4bd2b9823990fb3cce249324405	1636725007000000	1637329807000000	1700401807000000	1795009807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	83
\\xde00ccf0587736894744bd4650f9f026d79f04b026a25aaf6d09eddf993ce5f16d1efa48945fdb773cb8bab147bae75a0f4a013acec52783f745c5208591f855	\\x00800003ac36799edc225df0d0e3578be2b35f3c3f76b9efe7e61dc6a8872c2fa42351bd61d95e7b8509c040c523a3582d5aeecc7124d043bc291ddabdd407c6b805e71a7666a48d09886cf17f0614065c353e6f8d455afd5dab81946517cfc9a87754bb3a2e4ca513de95fe12e57bcec28fc13dd02b28a446ea8efe18c8577449a1e2b7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf088d0057c84cf125375010f12001f30c734aeeb60e4bb6b71c6bd61fe1e4999f3b90e1ce03ea2f1c5d70d98683a3db625b4a316a7c0eb4080f049dc1b54c308	1623426007000000	1624030807000000	1687102807000000	1781710807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	84
\\xe2405547389daa53cb6e53ccb9011afa3847077da85ef13605a3230331fe70fee95b1d25589b1700188bdcac2d3d57f969b35688abd86280ceeae3cd5ee053eb	\\x00800003bdb5c0ebc281cbd9894c752c909ca4480035246fdc0a2e92d4b0c491eda38ca595599c7548ff3bda738efe2c8f70635e0d3921db170962adf484f912b0d74c58c043f9293b7a0780d7f88bfb15b1089a8bd8e4c1760514e4e677c2197343873b6ad2437eb00f4740fccc0ef88cec120c7d21487dcd2e7ea1dca15b9838c834ed010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4be9e12408fc177b337f4cd7e69ea0acec0df86a62a836ad19b4b8f1fd58a0e8f5d513d8203cadbdea172ef272d1b3a70b43b0537a134a277d27ab66e303f503	1636120507000000	1636725307000000	1699797307000000	1794405307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	85
\\xe90445b4caa6866b8df93e91e09a1cff73af7936989550d25e13229a10ef5ed6713f30eeb123c695f8ce829af47f236fb8647702b99721891368e6e00190a253	\\x00800003beabe1beaba1c8588ac82d86351d3159587846d16017fbff255e25d22f7b42443dc35cfc4de9ad8e2f90d9198b891a6c2a0cf7ffe071746383cb4a9e16ba359b578d2c5adfd1d04acc23368e9e0330a1c76f8f62345b668e72a4a880f17d70971036a9d3f68270d5349a7e57aad4e66bf5365cde1f443ba1299c5d9fc17f0e93010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x20ca2d95b34b990b4ccf99102055af717589998ba307b9de4581313c98e3aa927b3c1e673ab0bcfac5a651e231d8c8cb868236cdd861134faea7a61f805c4d08	1611940507000000	1612545307000000	1675617307000000	1770225307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xec30805092456f78a774afdc60cf5fdf1abd7c0395abb9f4af6eb1228ea0b4d434df48dd76990b293636f2ebe0ba95d243889a80914b85a0fd8ebbd47c4c1615	\\x00800003bf7a400c1d075d2dc0c56d5cf180176db989d555a038d28dc5aa834ef572e79a7c7429de56c2cffd6fea86117e07859050272f3108c15e45a2fd47c30bfe5aa03055d0a4f123e5c465fe7357e88f37d9f86745d6b4d4a834fc9f9759b2024ae1c20c427d48ec62e0f29024542ccb75ac839f14751269d19bcaae5b37c6c39995010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfe10794daccb61295c4be655978df3c79e81d9f361f49f41386a234647569a5a660521a539c5990dc19cf0c3629126575803087ca38181beeb4ab43ee5a86f0b	1622217007000000	1622821807000000	1685893807000000	1780501807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	87
\\xf40051a35c912c79fead22f75d345e83dfd02f02c9e653d1452dd9c7fd92c231825197f1e2481533cb877a91bedfc06731079b9349fcc6cd5b514cd2e30ed591	\\x00800003c3ed70acaca2090b65a0b9a04f123a04f244229b15136b8d956d6254809e359ca5f16d4d8e4b7beb34880938d51be22cfeff89492a59e5769abebfbce5949808d7e6daecd4686461f7d221eeea65a947732711cd9cf11be63659b4357dc2e104c8245497d0124b0a7c6c1330d539f7ec44b0dd572f4d65a52b522cd6ff24c669010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd1bc121aaff425b0620c8109d4180d71ae10008581cc7befd61b938296d7be4b7ff3720bbd090e1f08960fb67bef523e50cf9cd965766b1b76af19e2d7bde403	1632493507000000	1633098307000000	1696170307000000	1790778307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	88
\\xf900435cae52285b975e9068a6f626826d02ed6f8fae67c42c0b3f9cac0b92c879a47b8e7628e30131dee2e1fcb3c7b7749e784f6a51cfc78ad90a73a7b0a559	\\x00800003ec423feed25d2066100c09fe65b9bd7c1a3e95c6959ad595eee68eb018b6d8ea0dc445a4c1e035ae7edb0f2a578134c2e3b8690f0f4dc523c91ffc5a1dff0e3df85dff3caf124ac2f197e77119151a43f9d8357b9ef2d733d4d4b9da88c6b9ce2bf4ad23d78b8cde855deb8fee53d9f1a1d1a137c4f4a65bc4df6df5d42151d9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x662d20575a094835c168e66b936e00768d5d97363156dbd09a6500d1eff428f86cc639fa40409901d72035d5617a12d6a3e90219628dab1c7aeaf5c138389301	1634307007000000	1634911807000000	1697983807000000	1792591807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	89
\\xfc10131a0b2eab21c8536846c0a1ebdeb4413e265e1aa4cf19bafed3e61b14c9715940cae80d9317a88aeaf8ed9db2d3a864308ce693de1add13add91077ca18	\\x00800003da8a341fef5b5290fec5a04a7ce19b2bb1b9ea61ee12f973ca5b2a5ef01572db1704adb0ab5dec8e6cf2639e7b8d0db86d820a661ffb75f2c96b62aec8ab5b177bff030ad2ad6a867ce191b54f72a35ab5ce2248d904db1ce13cd9a192346b7353c6ddb21eff6a508093f6c66938c0f1d3cf044d41dbba4ea8549272205fa9b7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd012db30619aadc7b120b04559cd35f0c4ed8ec0f0f2c31a4c6a955d4c694bbcf78af875552ed6e9704ed0ef8075481c93f25c6ecede73db6b87301cfd170403	1631284507000000	1631889307000000	1694961307000000	1789569307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	90
\\xfe8c7aaa4f2ee6978b2da6a233052c81d9476ac5179ea2cc758b79af3fae50519b53a3dd60897f4d50e5c6675f49f9c60e205cc052a9efd0b61ecc5740d0605c	\\x00800003e4d386252751a554420df1efc61c8b89270f45ddbe80816b3cba182e75672845b69f64652c03aab71205c741a66ef553626e648151b67ef4da1d4d0aaaeec5a5012bd6dc91b88c103235a7e3797cde62a13f00f29f06dd22f94cc031ea3789122a2d333e5bea2096ea42efd6796908f9f0c0e8f9616a4f73ffb595f78a949aeb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x663054daaa5552cd6b548fe4700c7e81e98122b70eb570096ce95c7d48dcf95e19898bb138d03a24b8a814b1d87ed47f8c92e013eb4544ff254eba88a8f22209	1640352007000000	1640956807000000	1704028807000000	1798636807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	91
\\xff8c24a4894df5fe34ff46bd1dc09520b8ecf297aaf8c63dc8ef7bc0fe764b8370816b678dc1580af9f856ab8bf49711750f4c965831c5d343bbbe9aa1e95677	\\x00800003bb41814bdf1d85ffe692d3184c24efea8bb1ad7251e2f4650e9838d66787be07649ffd231d0bd80f89f8739ebabe96ce10086b95396ad7a7aa57c35290b733bb9f71b560109b5726ba340b79b54e47d23f5c2eca303eb9d66d69353cce4660380205f9827f3e60853b5ba7354b2b338206af6bd86296bcc1f4d81a24f37097ad010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x70564321c313f4f085935e74a237fc2220fd6121c4c936e816336544f7a1ccc56b50a0cae70680ecc7db0f72bf7849610b05c209df01f0782359664bd8ab4b05	1628866507000000	1629471307000000	1692543307000000	1787151307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\x0111a6aef1cba128eba342f5dcc21b38c2f52079d8772366ed981c08a8c11d0d870602e79fd2ee8005eee497086929abc357ab0d48353c116998b6024c7d1d4c	\\x00800003c7e9c3e8cc2413de12c33a49af0347067323dd2d736419102b069c6413c7feea2a0dcb56e3d80c1634d4461b695593a0aaea80aef9297639c0a16e2f608a901014bab3e1f3f8696ac1ce0261990a4ec238ae8e7142f7595c62b1ed05b312fd4a986acce74c2451235942cc0139218a9a2c6eeb89c9b1e257b49159cf61e05817010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x65e9ebc24fc9658c4c6f2a2c5e82bdf5db19a8299c838b1b9dd282200f510dce85f794cd85ce91aebd5506978379228d62442e21644bb63d8b35e9a47a9fc908	1636725007000000	1637329807000000	1700401807000000	1795009807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	93
\\x08f96fd6abb06a129e3cc7b7274377af1afc27679bfbb443b37144141e8e8d8b7a9403092060779ac2c5401be6f5671cfca58c67ceb1e87760a97922d0e160ba	\\x00800003b178097b123ea5df1b15d3223be5ab4bddab80bc581915b622670550ff1ecde0d54b56fe562480dea37063c1bc6e89ada8a5857b02fc370c5ac9aec341e912778d88d5f10105c4de4ae3544252ed2588610b4ffa62855ac55d101f859bf348bbe19ea8e6008348c72966a4708d1e6fb647e4617e1702aed87b5f3d4944c38451010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7a8839e71ebd22f81cda53910f2270fe9753f24d2588df4ba09190a88aa91245b47e765af201d4e1b5be1389066a04136bc7c82d9abf8aaabe37fadec1549b0d	1634911507000000	1635516307000000	1698588307000000	1793196307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	94
\\x0ab91aeefcbdf90907f30d9eb47237c8318f289cfe4497795279ff6294b0cb1fbc894a820b31eb57819fd0891fa3af3db992fa85f70e3a1d4e29f211e1e61357	\\x00800003b4afb9ba032c8756076bcd4c34eaff5b5e2bffb5c34bdfdcbfe6df1a87ea3f998d57095a26ba04f5e894bb78f7007b4e4276fceaf0075e17b12e00659ecea3fa1d97d0aea97c8ac7758aad696d879aba13a028e5e7655502f566f63bc0037c2dfdc34472fabac54389e0e721104c4f47c7369e6550d3d1e05c2330a397c6d859010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x68f0e45667429080ea94a0775530237ced7dab70b4bdbc2f8bbfd32765e31082188a3e407dd854c1610c56174823309b2b46ec500a1323398a3fded997096303	1617381007000000	1617985807000000	1681057807000000	1775665807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	95
\\x0abdda7ef210404a4734c47e40f3eb726e4bd77b72ccef399ec1bd634c659d97cb8573fb5ab52889b2d38e87ed044a46369e08946533aa170f374551fda77700	\\x00800003c883649728768a30af594abff60bf4d40a72dc628cc61d89b4da3baaf051ca1d74522d92004f6b2de2a56877885976830a3beb9f2fd9d089b9d866801c9de6ac66d2a946fe29f2673ae4fdc89487665aebe8b6287cb40a9e3993968b3b5960f4d2719b1c70da191755b72a612c17bd329bd1f3d8c150a0f184f9b90c35d6be51010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x51163ced7ccd9b4af17b00e24eabfa5b1601a68e652ed54a4586f4c2c0f3f494403be1cb76ce5f6d58ec19c9850529e1cc9315855238b4a710d3912331991105	1611940507000000	1612545307000000	1675617307000000	1770225307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	96
\\x0a35db8690e99570de5c2cce5b66777c325144922df4b3846070d93368fc8dc9a35d6f62f800797cda1e358985f24f3fcc4bf489a18e5379aff2923df0bc1019	\\x00800003cdac68b0bc0cd2ac07d335ba048d42efbf46d5430565d68713dd129dc1209f22487aaf01e0113e6331aa3f5f8c31caa489168f1c5df0cb870ea7373559ba65f65100d1b75c2281b3f3299032b044accef04d910e3e0bdaa12cb3c7cfa2425664b6d4c511d2d43c8f9df258800821589e7157338d96433b142a037b00dc922073010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf998b507d8feca76e8c40f8088a4b6f1dd344a439b3b9fe68445569d8bdb85eb26c3b2c2def63e5bcd28082661d6e087cc885726c5b7abcd49c71cde24c01e09	1624635007000000	1625239807000000	1688311807000000	1782919807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	97
\\x0e9d3f0b28f8904d08d3e1230516cb866ce354fad7eb6401a026183224c8b927d35c201a465bd9f225190a0ac5446270a82b2d8f0dec8d7bb38cc2d27f84e2e0	\\x00800003a853ecb72de9daedd2fdffeaf8998d3b191228e63b55937c859e4c9a7f40dedea8c53b06105c66dbfe97c52e9ce95c90f87067e35151f89271a0cfb141ae0e7197d578309d13ddf655fe547abd868a53bbeebb35734156c7c8651483386e474c06985e59f7fdbe7f9713d57dde2e0c7960acff1cd131702813c5cbe793a58de3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x714f1a7d6edd978a212f56cf6816e9e4fc9e362262b87901545fd9b5234aa6bec7fe04b1ad6d86a211d417e0f445e636ef73942d9b83ddee16d7089355b0e605	1634911507000000	1635516307000000	1698588307000000	1793196307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	98
\\x11f98d19f50cc9288facffe24a464fb81e213094b0fcb30f5e74a30d891fb78c96e070f7d1f64943d5c9340b79c40b1445b6ae93e1c31e67ad99bd0db9ea52ec	\\x00800003a70e2decb0e09c9f9844ccba1ce43f95882ca707f33e317c5409322c10a4d4a339cb3bafeccb44346ecf98c2ce7f52ddf9c871b6084a31482cf225da51d8f25f3a32cad9ee8e2e9b3b9c853903eba06570d191fc1b1eaeedc6e99d79a5b9e2eaa3deefb0366ace962812a3eddb871b9a4f0800bb20052c03fc2dccfddbfa6501010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x361ed2a6369eee19925af98aa5310e8e381b32d1a99daa5c8520f74dce889bf949356f33219ef8ede36ea14b894bc4c7851911e59e0f76dd59ffa04a3e472c09	1627053007000000	1627657807000000	1690729807000000	1785337807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	99
\\x11a5d463f847e0a6f77adc187c428020ef571f6a134d67d9a9959ea5d0390cac378566dfba18c357bfd984d7fe35122dc8c9d02fdd527e3b7b7975c7fc6ec682	\\x00800003ba6ed9bb7f05313a82992c463083a57561bb4e2e2a6a0881781026cd5008f155af5c8acbc23e05aeae6eada7a920ae87679fa2e78c85760e1a3ab8880abf75f065041e1e0f953600b083da7802b272c139cf35e8669a54157efe16eac96db2604c3857cd27802a8afd89e7bda734644211dac83bd4a02513f224377994991485010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x05e2303a6ec2d641d8dc19307503df01c20beadba581177c977ed9dc2eece8037f6ead43031e3e67eef3cba9f6a1516e580fb912e6fba820aba8785784b3640c	1613149507000000	1613754307000000	1676826307000000	1771434307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	100
\\x141daed9ca90600d8de22b84b2cb0d7e1bad52aaff71e95f190a442dd621beace6b162b222a9c80fff4c332a91ffe5485d73a0b179123855b9ae514f9b0c109a	\\x00800003ad172f98ba799cb601d65ab69150df163d8cdbd9267ba06ae6e2e1b52425831af3004d5221a8882b5a0f6ba4974efbb8b1e733855ef807e100471903a155871f79be967d90090e7ce3f38049d2437094b15f2f557b8aa17124f7f6e092067d55f8ac6c64d8ac0981d2a8a69e40a8ed97ab66bc75ddb0754fa5bbe1291066d1ad010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb94a47e0f5efa77309a11d8636ff59bd1516132f52e8be59df4c57759e9500559f9b08525eb87d1fc7854277402ba8497bd3de9cacdd9cd3d67118906e69cb09	1630075507000000	1630680307000000	1693752307000000	1788360307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	101
\\x153d4c38fdb79fb155842f008971412a543a16292b63a8fc00471446243a4a2f29223c58e341d8d4eed6c96b2cedeb9a2431db5419f883a3505c10215253b9b0	\\x00800003c7be8f4f77053e76eef6bdab7e56d7ae51be211421d4f27d490fef3e9cb0e4fdcb52eaf6cb3b207a0dc6d760c74301127dea0a44a6e8134a41989fa0ae1800b7764c16aca9b23f35429b8d7cbc027285f80c2fae5f7cff12f8ffdcd6e5606e6d34582f5e622b9adf2963e80748d498ebfc7563874a7ecc10ccf40f5b38d90c0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6a7c7a85d23745c72d4e65b81de47ec346104cf3670ca682e8ac46333d87cff9fee654cab10a6a1d15f5488fa6a8b88c307a7cf9bad11d7dac4f3cdadc1b0b02	1617381007000000	1617985807000000	1681057807000000	1775665807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	102
\\x17d565aa662d79083b96dc95d8e5047fc0d3ed5f4d02ae8dd9f79dfba216c3ce3e5603c1d620a9bfba992e3d06e6fb29817b6c2b2b0f0546a142cf52295f9fb1	\\x00800003aa4a0ea82f381ab27c086476a5358e3b8107b02ad26d1f2966cc08431daf2f2d594b735d3d276d5c05d81d765478f15ca7964f465f8cf426f37a5a90e67ac9c89ad5df9e8184be1b9ffaab63cb1ceb9efb95c213b02348759446f95dce7815e47b548391364187d4d9bd0ced1b6c268346ab3628baaf8521cf7fe158ed607741010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x16c1bd8de7f4d088c074cb5696c29cd5726f6393464d2ef7e6e60f1b2a5c1b3fbd27cc7930c04f11e7e6483ce63b8c5793b2988958807ebb577b3fc485dbf108	1631284507000000	1631889307000000	1694961307000000	1789569307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	103
\\x1cadd05b00fc80eb8712341022385f526f5724a512c4e6c38f3643cde796b444ea2bca448011565b08041f638283c57ca8148bf97767282a50414ae524f397c8	\\x00800003bdc089f70dea4ed13f2bd16d6190121ce34f65370c4262b6eaab24444302fdb6ef1ea02e7947e7599d4450569473976a17c24eded7d382d44c683663a7ef50a4bfabd8491cee05a550471917db1ce16eb39de93603264d17444205bef962c7630b0180229b7c62a1a64f64480edc774f0c13386c477c4d7fd509f17dc9e74253010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x606422856fc83289219a18dca870d6d09f499fe09c5a42595ee9930734507b627217986aacead7cb09ffd0ed3823adb50802059484094ddc8761981f6d837f0f	1640956507000000	1641561307000000	1704633307000000	1799241307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	104
\\x1f99d2373e74b1fb2981b1ca1aafafddb6db9e74c07759a8c5c6172a00813689a09a3934acc17d6a81bb17d6db8f5f68d3e6f2d4bca8c3d695e67057b2fff60c	\\x00800003d8481a927f47e361f51d3a4f31e401fe69028ecdfe40df9e9ba3a9f13aa9b555c39eda0cee333c39cc970b8b0f0960087cccce29ecee30ff46243d0fbf040145fd1f2793e0b92ccc178b47e6d807abd90b5cf8e55e1dcb376ef86bf36c5e9be97fd1f261816a02a47b30fc9f5ee04b6349d1a6ef55ac70c67a8b2851eb0221e9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8862b0094b7c8fbd252509b138c54e65073b786407feec3570fcae642db52471830b7332ffb8179df122a9a5f5f81a4c46fc93940375abb89510deac50960e0a	1612545007000000	1613149807000000	1676221807000000	1770829807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	105
\\x23f15d2f0f0c1d3d5aa29604f53cfe9a38a1d8762c96b02d9a963c76638e2cee76718010e47d4cc0aab14a92a85699da38c35addb478df39840645d8ba996c8f	\\x00800003d8de462995e5b826dbf358ad7d2522e286efe4beec0a0f23b4370335a8cc13ae896708b04ba9712c785970fd7dbb73730ab4a9e4d43f3aa0f8cfe08379d2762a9582b273ca3fa8317a0d2076f83387bbeda2e42fd52e7c0c0d956c20a768fe99d1a6537c440620be1a63f8e63095c8ac54c958523eeb7b0bd3d66d4717834d89010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1fca8c440a5c8cc2dfda56a07ed7e806528848369446e60709efa7b11a03fd600d483d694e7da07cb59fe455ea0f6ac1075427aca88e115bb5534f598f16260d	1613754007000000	1614358807000000	1677430807000000	1772038807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	106
\\x256d78a5438779e2e5131e97ed33357f4f2bf22b4dec49cdcdda7602292d7b15a30685af0019e117b805b863e5b4d1e93ac83f5ec4d340010223e1e4014739be	\\x00800003dc52dd749321fbbbf9705dedda94d4edcc054351fff95a3e7aa955b56d2297e24ebea0686387200a1d4a8e141b0ece5a6501b16300808e777c866ec3f23bda4af7eff412da42ad3700dce94ca6677049e3cdfb1509540f7f031178cfcfc402d1bd8158364aa291c37c94cc5f57ca2ee21491bcf5ef252565c01517c9a141bb67010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2c7422781006d559dda2106e522cf0a39e74c68a857e2b61480b4b68586631336a972852fc891647cbf0f82b2bf2b20313bfd497e905a1dc2e283c454d299807	1637934007000000	1638538807000000	1701610807000000	1796218807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	107
\\x252d3dd3d28c665c00e8f636dd2232a3578b3a0155494ddb52640b5137ab7f764595a1155a22d43ce2d71369b503eb4f2877b3aa49abc0949cd3088fcca5cbcd	\\x00800003cb35db0a2bb692bb6fc6d8d91fec95aabc1d9ed154782c15e60414dc2212ec3b778064e62a721367682a2a8d8215a5ca77c1899e38973e68990ce5645cc62e857c3247769b72f34ee2451f78a1e2c1989500e37d9f8c4c63aa9d4cb6485e0561d5f308f456ba0b6dfbe104d24f3e304121fb3ed4f5f75368443ab841ad0f3b19010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xab2423766d0a17f76e2d3ee55e4c1de72ec046997bf42e8878865f088c349775eedad42ee1e9a24416debaa374dee7fe01e478557a28eed40157c306299b6d0d	1624635007000000	1625239807000000	1688311807000000	1782919807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	108
\\x26c105d9c9d1270f39696cbf3db71fae3dec1ee8405ec4c6ae32e90efd6624aad40030132242a1264c302701cb8e89a7ddadfee0e1389b8068808cfb6b07e57e	\\x00800003db765d47e5d32162476c12c6e812cda1534932dced4085ca6c4d2343007ad1b22253198c242326f54c4e705aec3b8222118a51d91302993b431cd8b74f6d760db07c449325d9f9f3bc4aaac7296ea1091a9fff6d8c59546114bce9ad7419ab1eca0d270c0e6ae8166a2e6d08466282a1d26c73cd7cd4d9dd264212159da7c915010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x09d2751fa63cd4129ee7c5f0052c44dd3cfb238b08207c714cd768a81697cb3c624e068431adf304e8e269bd1185f04db876d45a4b61b8c846ebc4f287b59508	1634307007000000	1634911807000000	1697983807000000	1792591807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	109
\\x287198ab817b3f1ea9ac295b00ac954d50b9a16d082b08e97e4c6e474eb8db10f0475e26d225e673a67b92741a76d7e382210f19d17ae868316c7e527084629e	\\x00800003c7c7a71b46248f27049233bf1e5fc236a5d945ab1c78a97aef0020cd197c2b46ccfbb2c9627fb77dc6c513f61252f099b0c8818f954cb2e420ef820293dd082ceab9f98bf93a4a73499a265d47ca0b173e0a84ddc3375f09c261b74ca8407681631e800271b164c76bad36f9479f8d4bd4812b180f471dabf75bd4aa91b191a3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x45b44e1fc81e67f1133e9099bcc3a890670665ffaec97c0ef9befb059582cdcc9b7e7557da2d22f2499ae0059d436da88b9bbdb3acdc96b0d93d32d67a18c804	1632493507000000	1633098307000000	1696170307000000	1790778307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	110
\\x2d4df7eda73687d2902a3cba947058279e538b9878e46374a09c5d68b5b2957772edd48d96f6e98a836fd0ee68855043cf9ebbd83900e3c7c3e97879b5e34078	\\x00800003b71aa4157ecb6edfd89df7ef3a6af69455100577751e68395c7522d45d6ae2a6044e39df6032b6fa4c440a6279242a2b3ab3277e34c9edc3feb430bbb8ed147ecb1c739729f37bb7a388b26ce46931a82815c2b885d7003be3e2597c80fb393a6bc25927408622bfee29b6f98dc04ee31e3046b725275be73b64ee37252108bb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x31156b3d7be0a9b024fe0452c7dee35c2fcc052b053606b774ba9ee9a8bccd679a59642ce7842845e718e2645d96f860686524e315a2bbaf5558187dea41d009	1628866507000000	1629471307000000	1692543307000000	1787151307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	111
\\x2dd56570fab8c202d4c760b20295c7b3f0cd4b9737e0db52bd56a6c3f6bb7eca925f54eee2ed14a296ae8f0e0f2a2ea1744c601a57cca16851a17270b4e0de3b	\\x00800003c77b55c97e3e89153fa912e514fb65f9a5f602860b484057ec68c93b0dc0da51f4c913f4c62ed4e7a5e45b0b47b5d66e2ef2667c5fe8f5b2d8549c85dc1e70e8333cc36a020e15411e6b2817b472994eae0d4270d71a1efb0ea70f5e1f59df600b3ce6180ecdd66cd729448c263749971700cb19fa8d0e7816d704fc8bb59abb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x67431390c6f858373f75e4208fe7a6a8f6ffab6f647d2dc8bd7eacdbc014d2b6ddabdadb2fb3118e0b67c145452c8e091c81be1d041f1b0b8305722d7b96ae05	1636725007000000	1637329807000000	1700401807000000	1795009807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	112
\\x3399b5653f47466cddc388878bc6469ee9d5d3901545732e74dc2fb2b907c1422d05d88ed3b6643242119e9698decccbe98b87208fe3cbac0059b705f6ab37ae	\\x00800003cf6f658e8ceac2ca300ed3a11e0f39f0710d9f952ef62f9ecbf2d2fd64991c7057cb93be53f29a17f22883af3543993899dc27e1e3697fb7c6cf55621d4f6a5e63138c2bc6fc2674e6373792ad104e4fa73dd6ee92e20c317335bd66cbd214ba3b2750004dc253d410fe3f5b9f0dc345875d10ab1f87944415fe78c37438c4cd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8bf8ed6e8b288042fb239e2444cf98da71fa203918cbe8c960175f2980e550c0c9541edbfb431c5e5c47483a55b52d3ad326b68c817e21b49733fb39c13d2e0d	1631284507000000	1631889307000000	1694961307000000	1789569307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	113
\\x35fd12c4375a03c61aa0eddb0dd27fec72760603ddc60cb77fdbb53e2b0941545d12cfbabfb321a60185e86502e33a4946f326c50fb4c029dfa9b1162f553bad	\\x00800003cc825ee22863f44cdb34ad61c6f887c5a8b260b737013ce0b552d4722724cfdb3ad4d1b373b75c7ec96c3bcd6f23d3ef3d6a8788a8d7c9f0eb936b9001d6132a0746a35f16b2234ee502e4dcf316d21ce592ace70081e5d46ffa388de36caeb12b6c24d075447ad57418689c53776627035d8d1d26f7c2945ea31c330a788bf3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x492fef3d0d8ab46cfb85fdb4e16b5f8c2e6a5e9cfbd0fa5969b5ee1f93af978a7e2abb706ed435ddfde29c8a12fe05e9996084410d7478144077227d9345460e	1619799007000000	1620403807000000	1683475807000000	1778083807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	114
\\x3779317d08ddbfcbe5114127b70dda0f903f5380773200b97c9b7fe1cb8bfb211cc59032d6840d321728f69f4368cacd28ca68cd8d72586addd19dcc91ac368e	\\x00800003e15ddbaf4b16640eabd1d9a3eff72519e42da0184c3e465797f31f030a342956bb871503925df8316ab3a15fe5effe554f9391753bc3798d92b41be029563a003d8f4aee9bba95e39e967689397da81930feb27417ab38f731f4b3fafddda6024aeb0c7a1580b172940874f99db6b35d2cd23ccf16f0208c541a998f981da53f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6ea7fb112f1529831dbf70432c57f28b06895077fc37560e69ae932935fb8a7a30b11a66f2e0f1ab5b325f28a8ed9c48dec4b8de9bbd1ffaa31d5fd3904d150a	1634307007000000	1634911807000000	1697983807000000	1792591807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	115
\\x3801d7a5962c3a9084ade79c514fef0c75d820e7a025db8bc1213e759a9c1d9fcca54c9b86bf12aeac0292d73ddad545afe9582a114dee79ab5b610980a04ba4	\\x00800003bfaeccf8c4f5c74b0e91d3e912a60d9934f8a872a3530a3a279e3ceb182077298db31359932d8f0d9296713f9f3c368fed8207d7ba0db1a99ad2f869dc43af7c29410714ea60c6cff8679a92f7484eb6a4bc9e37359e6606a988d64da3f9219547253f0eaee758c4da71d9a247ac7a9371ad3c183b840060274e2ab643118b49010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4866eab1bdf788d09c42e7c4aabf6f93833cb0713c9c59182f06fd2e64a2eb5f46233eb78003afa553b7f668c9c6df2f3cbd0539496960e0427a2785fa194d04	1610127007000000	1610731807000000	1673803807000000	1768411807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	116
\\x38b99fa93b699172af45d16cd92776db6f19f8b7e86edc11135f97b11f752edd9439a7fdd1b7abdf3f601d0a445f5f7e9a986be989c13bdf2f418ab4389e6cd1	\\x00800003b7c2b46817949e112b05ebf9279523a524edfff8305f3c23fc9fe5c2149964a0e33b4d920fcad150d2e9f5472600765c1df39df8ea719fb257d37204dcccb90c8d0b310f04ab3a27167fd0caff3d697ce66fcb5a1747bc0dfb34427b8c5ff600170a86f11497ca44747a06c15cf69ce6a6e05f1b7a3805261b29c48b06549991010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc8b2a68f05bdaf712b1f9180fb8dfa80fae138d05703751fbe2bbd2f67d1213b41a0c126167c0a27353a10d6ecb3c96726bfe490cdc221ef8095c9e337fcc102	1613149507000000	1613754307000000	1676826307000000	1771434307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	117
\\x3949584964af7162e1d4d1a4d3677091197d73afe5be169324f1810f6d0c8b563dab55a90300568e0a779873da435acae503976073fcae28eb05bf8055238531	\\x00800003b6074f6cb4bcad8d438deb391858b36ac4f00306546fc50892f0155fa4677b9ec0de64b6aeb6f286bb170aacc8f947ab37b418b33c38328929667db51250abeb64322688bea3638dcbcadd4afb4c9f254a2e3b0e760aba5b9120deb49ea2615c5c8c963fd2fb6ad7d3bc4c9f68f774e621c08d24534f67acc0355af20907cd03010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc404842b582c58fd797355efdf850a8bf19bf673f1aa63097922292d87522de4854accafcf694df80086f652f81000527cd931e946282b55b7afa580dd71c20e	1611940507000000	1612545307000000	1675617307000000	1770225307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	118
\\x41dd6e2d78692879c7e55f137903d3cbc630eda03612f5761379bcc03be91acacdc18e9f9d9d979e2197c7f126a6eef7da5d83f290673c74d27e1f3033b4d7ac	\\x00800003d21db64406e87a2e309dbaa1d7840e658f667042482b3f0615c87760dfe2241d063fb5a8f1866a6f1de2a9284849f62d6feb2a364d455fb5450c0892e1ddf1258c5d234d85588eab655699e89da7dca14e5d5d868fc580d47f6335a33334f399f366716b8178693be5de646de23567e641396b1ad227d16ddd72ade6b7e4fd2d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7542c5ab2cfd5ef6b95017153ccf4e3a5899391125f2be13d5f75eb5f3a878b14a405250bbff435d4dfdd6bb742305d2e7fbd48c324ee536cc0b4355d885f70e	1628262007000000	1628866807000000	1691938807000000	1786546807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	119
\\x42354a5682efe1c2d12c62ecde8ddfb4e3b88ff6da07d16a420435641f40fcdcd03fcbbca1dd95f57f68b8ed0e4e1b58828f89ae55c66946c16b4a74ae9e41f0	\\x00800003fa23845ad12ba1e10bae021007f66b11d0f6106386e6836dff94c05e3065a23aaed79add1c14a248490072c6159c2978c829ef66ba0eff1cb54c79e4a89fdd6db62b407ce6ded715bb893b462d42346a758ea8f6e2d3c9bfb4f8ebad80e91738133b428565fd6fef524dea28f11fec210337c41e979a94268b14e491c7a0863f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xcc7cc18d0e52458a43856e1d1c94cc3c3db2bf77e261fe972dc7a536d01870e1348ef7c85d2d191480d22c79802bb1b3b4ec59576726054b26e09d418ee5be08	1615567507000000	1616172307000000	1679244307000000	1773852307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	120
\\x443d0a3508174ac11e9a9d72bb7aec4e39c41ec0dd29432d9d3779239d07faf1ae0b8b19cee929ea010079ea364813918fbd5190a51cfd7cca51c0b67edbe7b5	\\x00800003f108d0c6c3e8ccd88ac925415d6fd22c18550b39c9230afca95aecac263cafd05349767c34ea167d4a3219b1b575af93d55c9123b1c102b782d910dcc1edd898a8be900a4f066c6554339d54d4f95c1df5b3e2b166319b7045fbbca9e8181865f18d2fb9703522ddad4a20776d603a0f1747217ecf1a80c682a34147babdf0ef010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2948338586a93bc7098a7f702cea80f20f22b56220a2bb3bf264f756dd932bc2b1cc2f6fdd3e28d3974664493f736d793b65774ca6158069964c152789fe8c06	1621612507000000	1622217307000000	1685289307000000	1779897307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	121
\\x45c976c733f8c3fb8db51e41dd46f03c8fc1d751ec515ecbfa5f30c251bf51b1cfcb79e89398e39c92e1d2e2239e0db724a4c7e49241e9fed3e5ee6309cc4e5b	\\x008000039dcd97a477a71680955f9bd442157d3b3ef0c18d97bd6a21ad64c8a4c1b0f012636f4e52dadb3da03f4d025d26814aee9ff4650feb14b03a445ae2c7e29dd8256620326572f40425659806caeef87499d08c1d2c4a6c849020aa9188ea8a00b34f1e521ee2d2799d0c3bbbf1b6923265599d629a031d2157c40191712f7f213d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xda247c88201f5ab197a7b514d042643cd4762ed9cd05d7359f4adae222ba881914984ef024359f68bea663616771748157deb9d641ac0242bddd7363e14c800d	1625239507000000	1625844307000000	1688916307000000	1783524307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	122
\\x4851ec9ca1e666cbc1e0eea59e35cec16e44884b793e84470878e33e0177c739b46813d738fe8901eaa10169ea00e71db80d49ab95dccb4750beba3cc14b9d54	\\x00800003b50dbddc00f312cedc0c60e048f9e374836c1d46415271eef6bab075a8abea96b521fab37044ef78cd1b979ad9392d254e091b60c91ae7e15e79cb17ffbbdce7df61ad0c07dcd665b8d217ba71d2edf8a929a2f8e74f983f619db6fcc3820fb987c47268d4720f6ba1751209709bb406b6c06c929990d3fbb55610277e5fba73010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7b5d0011b4e5d924207d986639c768470d7ff1411f29ad805d06980f1c5f666559e2dbec93998dc2fcc217b47217dd5d50e6d4c202a9b1b2ee3faba5be89180a	1614358507000000	1614963307000000	1678035307000000	1772643307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x4b3d136375ccb82e5a3f32217edc4ea3d847ecba2339442a33d0f6d05afb4cc2c07fd233b27ebcc5aa5e3daa619a9dff50b313c78353cebc524547cb08123c3f	\\x00800003aea99c87d8bd2a200cf9711a4360281973194c78387a0d3fc7565fa8e6f5b65abc96e3c9897a742a1d1fca1810f909270ab3ae3c269b76eea0706e2885efa9b85dc68ef9a50650ba072ff0960d54e4684184812f3a8c9a0d3db2ae406e89a178d5e174a957c912aa23576dace9c5da090e2c4bb7a93ed798febae26a8d125cfb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8e5ec141b65d160dee93b3a9ab86e05adc75c5835925f79fa4e356caae221f77769d06ac6e5e61663ac368799486e952113ef99518f86b75d53cf9b76dfae50f	1631889007000000	1632493807000000	1695565807000000	1790173807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	124
\\x4cb9f0b90bba41f7376952965db1b588319066c0e1775502bd94733870f7b49aa2d37c51691d302ef88e37a233f99d93f0cbb14ebde21bef36e3a33c3c9cac95	\\x00800003bb6b1c78b51383eb54b1a58da662a483685b9082e552a779ee5b0277a526780855817e727ddd13cec05e4ed06ec8ed9ac99b96b81b4bd559825e651070ffb3f13b933e25a0dc4ecdeb6938846f5dfc427327d9128bafbd948e267116a9f210c2c59e21949c0dd02a59116a8de4be2346c57276c482bc5ac6db1ba32ad0a80ebd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd6e123f6ffa654a471e5cbc42767a23b8f80297869d0f012db3a6344bcfb8b58ab2e5a389810ad14c97a5e3bf4c5f732706d8c5bcc06ec2b6304ebff0c3af600	1627053007000000	1627657807000000	1690729807000000	1785337807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	125
\\x5211200a64a9b41fa3ffbe6d6e981b18773b6ca25cb9aa44457232ee9ef85d7fdc4c37e222062377205b2c9a787962a8a27a3f318bff320942d10b5c9c2237f1	\\x00800003a91af6c9d8eb76575c38e70045123d96da08218f2d579f192122ecc679477ac03dccba4c52b15864797d35e392a0d3a8971f0ee4cc29d62d64ebd48490b5420c82a9e5ca37d12a1b8d301b4a8e6b5d2607525f4a5060af7ae8d4d2277a39a35ccff3ded565e672a92a17aee78d4ed3e33f061c4cf8dcd698b865e73f1c3488d5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9676a547cb4152d0dc8cc0429ede911d34e675f26b4b85389ef046fbd4cc4074d449692a298cb649b078c508e7d4ede5302cd429fde1324d675725d813ed3602	1616776507000000	1617381307000000	1680453307000000	1775061307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	126
\\x5215e60f0cdd874bdcded913c48689ef67f2ed001845d161c55eb7c6d17e187a37e1d34835a3dc18417c8b45288de8b27a123c85c43b98c45033a10f50a089fe	\\x00800003c5503cb00087f7bccb02949ba93deeae0f8770f78188fa6da218648540f66009b7c8020683a9ab56b4d4d225d21673e6ddb8264b46daae7b95b99cb914a1ce687a5c9c30904bdd9139da62236ea2fbf4135918ee4a0c5f5568245fab043baadb1162509dce1c0022e812982b1c4fadcbd8b9e54648ea931f6c0218fd2ad0b72f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe3fc5838cfc4f5d5b068ea58a4819ab886e5edb30c345d24007ac41ee67b206f8b3d165700e8f00aaac116b81c77c812a7227f1f203760e38109607fb591e406	1621008007000000	1621612807000000	1684684807000000	1779292807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	127
\\x5b89d989d258cd060320f464e3569ccef6a14c8879618df427bb6c6d5bcc40495bc2b989c5d2ce1d8e0bb7416360f4ee93b58ff5fe340fc31e551e66a96d613d	\\x00800003ebc0ec98ef6d633b60830a87153e305a42b73b150ff4139795bba324dc7187a0e8140bee4d3dda43dc16cdff096b3a9946e111a2fc925985b011bff53acafb5aa2a87dc50246de3eb0e77cddaa81dca58686441f6674d177927342fecbd82df01463b2e41473c899da2f60fd3eda04f3bbc4f9053776f7e4c22cebaad1de2cd9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4b966ca35771fcf770ea2902fe4d83f0d8f655715f09db5114d99b6bb9f70f5af66d5c51ee65efaf067e8649759f179ca4840e285ce66de8834d48a67411d90e	1640352007000000	1640956807000000	1704028807000000	1798636807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	128
\\x614555c1675c19071b0aeed8dc281b616fd66235ae1652439317e0706d0ff121abd8df65f801db76cdc592d32c149df1ee2a3cf3824b034b2b4667526b89f566	\\x00800003b31b44f79430abdfc8840a3052d0add440663e0b55e7fb00663c2d20e5b972f85b01461f8b81f324b95569e5e138157034186058812047e9683d10e5c8f1a563ac6e78c3a8e7c4c23b6e2e8deb3cb3564beb458f065edaabcb69bc300c1ea23ead9bc64d142736bb407a13881dca3922ff12d271204a804f3363ea957cc3fbc3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x970974bc76dbf13c9d9c7a2fad41a48539868a9d3584992139a5babac9206c2dacf45ead56ee7c1a7b1fcca25d264a459849778aa09ae4dcee0222fdb6ea3200	1620403507000000	1621008307000000	1684080307000000	1778688307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	129
\\x64f97d70f630a3a4e56dd1d62e0ab9cb9247c1e5464ece1de532a8b1ac31676d605a4a0fa630c0fe3055b9cc4cf8bfcfd79d56dce742344512fc83ade6369c76	\\x00800003ac402e0a81160b39914ffa16dc0f00cf8ffd69e7cc17d419a5240a71751df58f1d1d909e23ed7df3db0508fd9a72fa2f2936f1dede8d1c0846c1defc0d082a2efeeb58faacc720c4237e5be9344416f5bd0a79ffed7be467d0746b0aff0f3318eea12e85390f69853d5059c4e36111262f57e4c50380e378f209608731ef2087010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x37cd0f5d7da4406f636d6bd324554b2bc236c3e75ef213690ae3ef90ef91a8011c1b5fac902dc7ca831e076a8824f2abc36c8eeb967ef69256c7375b48687b07	1637934007000000	1638538807000000	1701610807000000	1796218807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	130
\\x65895b9786a8d03a945a71c433b4a2ff8f785d7295725d6cd785a24cc423dd98de82893679ca917d75df9bbbd3adc4cdce590fee3b38e7cc6640515d163b5fb9	\\x00800003ea6acb9d7984eec8d435670e409fbe62a218b5ec113fe07c2378151a49c96aeccef40ad94d47e59f08ab51484a0d19130ddb6144241aa6464adc915938031215cbd6118d8e5f0c99dd6d4d0917dc7c1a484b8f7b2ccc710ec764fc93461fa91df5bad1ad146a4b3b74240629a7e02531dcef74946d464565cc8156ca5d3ca2db010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x136f3c65fa233cf7434b83a185a422840166bc3d5b219e05d99564231bb3624a0ecfdbeac8db40337c58b16e373f13c3209ecff3a5c43d9c3f9b229bd0d79e00	1619194507000000	1619799307000000	1682871307000000	1777479307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	131
\\x6631378ca9b5bff8d2f7d0fba1c12372258c4d1c55bc8dcc0b34dce4bcb69792bfea6c7a024aa9125bfe8274900a583f184c1bb693d63b7574e3c45f0d48a66c	\\x00800003b4774a7b31e47fa517e5dd7eba1500089a1638362071186343875d42b3471089fcb8e2a888e10dc8c9a87bf45f7b7558b5362de669e768e9f97bf4d6bf74f51be5cac68d53ccf3be5f4726bbaf71add024c2e0b20678670a3d7583262e3b58120fc7fb891bf276166f82685d48d001946a16b09a11abf2fb89fc0372561b3883010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x14e3ffc51b3b8d898ef1915ffc73b9ea4e9b8b59a59011574d1883009a9044a5c84c5fa59cb6a83971c118f8a9253554ed8728dd5354a74395d4ff3f8ee46e04	1620403507000000	1621008307000000	1684080307000000	1778688307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	132
\\x67e9ea48a9bd9e5a3cc1982336755ac25f6e46954ef37d562d5880a066c9df5bd45c9db35d5a2aa41d8017610cdfff6b822e9698227bded2b9eb5751d5ef3214	\\x00800003deecff59d3bf50fc10807a1eac483d637739c7dad561d4661df6fe83d15ed84489763ca0866279a4ce48c301b2d32de9ca02ae5a280275e7a45770a22eec5210084ce255ffd3e8af60aadc12f459e1d5eee21a0c984696de930fb95d2bb3c36e7a748b7d6495b57949dede865541df1561cd9bdff1f2d7778e6ce4f55c3bb0bf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd179e5b0bee4c4efb198092dc6b61702459eb5b845ed95f6bc85da6cfeca0008e961914a525c5ff8ec17d55117630609f5d4e92a271dca76c40d1db52158910d	1610731507000000	1611336307000000	1674408307000000	1769016307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	133
\\x699522ff8ad6bbc2ffc7ed98eeb205b4135d57c93d4e367a750ab6a96f8d81405e1b242712add95860e146d9a2d31158e7f5dcdca1832bb35dc732ce2ff8156a	\\x00800003f16827f11d2775ae5c81602725e8616418c8ea4b4654aab356b9d47446e92df4a909250a8905b4e9e61f3cc4a74c86ccd1f8c5bc0f1931b22345a9473364110ad1c8c0858ed6bb9e218cdefaacff1f1e9343723f158275695678f42798c1a2e1f203eb5869272b9f58604fb1ec82c87516fe9e5d2f2607901506d5648d46201f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x342210982a24b97da4ca06ac3fd94fce31456476b5faba5de07fd68cc6f568725132834792050302b6202e46d93c0e6b71f4a4cd8facf374281c2495b4346401	1613754007000000	1614358807000000	1677430807000000	1772038807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	134
\\x6d258178b77f5b21c09a6f1828dc86d1ff3c5b4e146797cc72ac729ad2ae5b292c34589fcd4c595b35a50085704717f3b9c802ce426ee94891af04e385f0cb3b	\\x00800003bd839c9be9dcccf528c88e6dd005826713fef37f8fc32cdd5207783e6ae3233b944fa1963de66ccd9c57744f5781482501eeab07a24fff9e7554bdc3748f82e0274c15452890c518511350ffcea50f4098cb55978efa02a34193c37047979e4a724311a7776c07adbe282c6d5c908d346c795f04a1c0bb48349445729186defb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe9d3c34c6d6ce20c89a508054b2731a00d0cd8c3434d67e8855e0cded181c04c4cf81caa2a3e94ddb5e2d09bcd7e9566b5a83b71ec28af305adff9f1a059bc06	1624030507000000	1624635307000000	1687707307000000	1782315307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x6d0d777f8e886f9581735ecc140f67fe4820901736b0a89b8b0240ef7fc6b0b9c3c6f6cc10723b222ee628c50a0f0b5016b47452bc0abab11f74a95cda8071c1	\\x00800003970a426caa5af516087b1ebe885bc5b5b6c1b09b166b1a6ecf14a92bf265c5352c55eecec5494050f3608f9a3059caa3e541007d9fa0f5d1b9f8752d3632d71066c81af8a1629a862e06986c1741c2ebaf9a416a7f63d3c7f6e87cf29b026ec835d5675e52933b29c24996ab4c307354a9cea1b42a22c3e8e4c96c8bad10bb85010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbf72fe818ac85a7acbbd15d38a926ac4386742a74bcc12a8ac2fd8147e43eed8a0bc515c3d6a4688e8f50149adae9ee3e22eae57e0782ccbd2bd4d1d7463b709	1610127007000000	1610731807000000	1673803807000000	1768411807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	136
\\x6e41a0c551c4b9fc03b7d7c2ae33b23a82df4ef2284466d8d2caf2b3af656fa1a4dfee803f0210075fc2543e49c729cdce4d6d3276fe58affe26fc288d3a4d09	\\x00800003de231c151cc8bfad8b6b34d4459d78cbab044c4bf3f9177847c656822089a6687d1e45fd9644a8c77849c1a232d9a23aa24b357865d988e63316c0b8f94abf2564fedf783a36541d123521a82338e7c7307e8e0c6a5cc7abebf9f4c5f3db9e2235c90c794f10806645a4c51aa1b35062221fc21d5f6938e26a40411d9afd33c5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x47bdcc55fce419c4570ac16036ebf02c1ec1bdc42f299136085e854d3c50e0c36cbf7927440c3a4ffaf4452cd4f4d1990a5deaee6905c2dae50a6ef0f32c2801	1613754007000000	1614358807000000	1677430807000000	1772038807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	137
\\x738503302d926d6a3e58befa7b8fd2929bb200254a63d151ca66bd260c490dae7188a33c6cd7ae8bac975abe58099b7c2a7a392c269d3aac5f9d3981bd3805ba	\\x00800003c957d1ece77c8b9f3b0b49653185c0fb8a85470f3c6f86d3d9cba66742ec2b70f6794cf95120757fad2651e75b774272cdf289dae54fad1287a305f0e9319581e00accf6c0ab863b0fb8b1a132bb2b22d94b310924a54733f00e3650d2f7c6c8027aa5f8594654db505c267fe676834f21fa311ff45e544c1691826ba8334f35010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2a3e6dded9865d86b5ca30c02dfa1b7ecab062c6774c2cb799cc8d7a6cd906e7211a295e977c1d05d2eabce46732e3b50f90b9fc18cd6d26ef596cdf431fa10e	1629471007000000	1630075807000000	1693147807000000	1787755807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	138
\\x75ed2e140fcd89dcf5a074a96c36308002e13887577a8a6ee124099dc2d6d869b65dd0a2a967cce5a399c6af458dd6f69ebcdb0582e2ff2b10995db36d6baa92	\\x00800003b6ee840dd52654f9c3f2fcc7a579a4c3755bc4905d3f2069f80101264d3aac6936a58a9180c1442853e410792edd6e098be1d70095bbe8270078cc2d9a333ef8ab4d3dd01424a142c815784efd94651557fde998796763531200c1d19e6ff8b0e909ca2e92b57e5e1e64068e32009c116199b99b06e6687c6ce5a8c905826f59010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xff98f9a39f14737e946f0009aa2bcf048fcb959bf94fdc0b31419679e893a7a931979a5add9969fa4e05a065b7b4329e04247c2d2a581c2855b0e7dd355d7b06	1616172007000000	1616776807000000	1679848807000000	1774456807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	139
\\x7671f8aeab002ae6ee3dfcec98a2963613a1694ae0021cf6b2e86f70de4d33a02a4e2e1733bc037c06f18572729370782dcb82aa239ff89886ec28831479d795	\\x00800003cbba1f9a20f1801d1b8915bce7a3d8500bb279946427410fd6892fb97004a0469779b84d269ef2eeb9efe8e0470c0c7cada13fd815e35cf51e43d18b764dd6c27de2fc28b7f11cb3acd37f6404e319d1eed82250df8f40c00bd248712f78b911b306f730f18e03adf52bd86951a8363215204eada32c044af7d36170a1d14a13010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x76e5bb977de4fff73c76229a0c7f7079af76c94d4dd5ca302588aef05ece7e4266e50e4bcd3149f5fa70f271028937abd4e7d9d24b2c57b68a04fc4582b12206	1636120507000000	1636725307000000	1699797307000000	1794405307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	140
\\x78dd58704a74efd108fda40de4e4fa32fdeff7b8efc2f0f62be140de6b5a7e8ee3a6092009c179cda5378b95722c668beb86d446ace7d1f93c1d6b9ab7435622	\\x00800003c6d24a04b4c468cc2df453947a0bff22fade872bc3894158efbf06ee0ed1fcdd308a94e1d2740f3f9de3d281b55881990333b8385909df56db1b8fcf352f13ba60a425a704ae65698b5c57a1b403531d448ac2a41fac24927bb343d8ef07e96d9087fa42cc9d399d439b8aa28e7b67b98afddd78919cea7ed0e3bf878bd895f1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4a3d5f7b42221325f2cb1f461dcb185a20bc13811d71abe4dd70b681894f529df8a8bf65919fb9b39e5a09b8f1f4f7da1bbc6ec40a34a1f9aedf2aebeefe5a09	1634307007000000	1634911807000000	1697983807000000	1792591807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	141
\\x7941987a0761e64df8aef4fac41afef6cabf06f9fe651b597ad70948bfbc070e83436816504ba44a8a452d9770f734e2e90edfddd51328ad4aa9792a2df478a0	\\x00800003b5f28d2ba68f3ada017d98b86c5e94a0b13bbbd1c3f0bf14eb180f7d4d7e7c09c7e205141dcc34f812c9f057f3a73cad108e777b8c7f23b44006476fb0337f75aae5c4362c09f1bae4fda99b608528e2594436207056c4ac98a012a7a31eec78085a291b804fba323fa7da3be8f0cff3e3d8d71f013fb964e29240d5c184a8ab010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x48bc2f7c3da1fdf6bb04b9af82c5659900d3b00b7075ce52178653ddb72444b282631a6b5c61c6870a3b776ba71d2a218df383772ba0722e96bd2256db1a5e02	1636120507000000	1636725307000000	1699797307000000	1794405307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	142
\\x7d35f704ca5440fead82225d4392f542afe4611fff1b1a9be375f529a0df66ebe98af72bf2450faba2fd2661d415038a38a996cff988f56403a3352431e0687d	\\x00800003dcd460683f62efe46d9480648cde104ad547f7384e37b860346927af1e3ef94baddf498a204622638167b58633f4b5844ceba8690fa7772a03e03ff781f6532bb82ee57de1fd4c0f54ebb470e67e16a901bdfdfcb8560d0ed47c7f07184a1c1b4c7ba07311bcfdc0449283cd586bbd09422560d50dafbb93520f20b38dfae83b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xcf4e69d1428466981ac94d97f3169b98fcf771feefd62fb75b503473c12f9f7db648302cc2de85b0fc1b92c95c28ae7c00175209064d93b44fc196e58975c108	1630680007000000	1631284807000000	1694356807000000	1788964807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	143
\\x7ed16a3b623edeea7848c19de87253b155f041dbb43954b6d0b525d347ad593864582567fd17fdad8e1d289407f85123bd0cac84ff89493d6b524d3ce9fa79d3	\\x00800003e53f6d1fffeb459e75f689b60eeca16068de80561189399b83a7ef342ca8b1461be9b9c0133e6eff6f4211a023782061f186951035f2ddefec8f761416aa8be2be43b9514b5944680d9aa217ffa3e3e814e5544c67b4fa55f810653cef0f66d5c25e28d9a26dd652c5a14f4771f81af8c573951193df65ace868d163abc3809d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8fcb03379586531491c6327f6f8b01abde7aac27ece5dde43cd1d4b39c0faa464a189ed1e45ec6cf8f26d9b26fad822533c58e200bd175e68f44b51e3a03a20d	1611940507000000	1612545307000000	1675617307000000	1770225307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	144
\\x7ea5acdb7664b15635cc18095ad532fb169a42fb9fac126292d89602c97678f904e7db7afd76f0252bef41e51431ee00581bbfbe709ddb4df7611003b0ada2f4	\\x00800003ad186697b6d0ecb756dc3898dfa9ac49f968c923e78c805a163d79948f1806fdf0fdd673912d6b14ff1981c407534a04555aef4b0396038dc4055af7249392d9a47a840637736bdf621db9a0cef582e52cdf69ce236f8b897b86f040cd259e72deceabc9426ceaf50fa6baa7a34532f233b47c4066c06c4d81209f49164b6ced010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5451fd830991a8e31ec19cf43573341e4ba4038c5e1a1730e95ca511e1dc0ad8a0ac78dce56b5d6578df78dc4e7ca5a6cef4aa1f42266b3359573a6f51eb6f0f	1616172007000000	1616776807000000	1679848807000000	1774456807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	145
\\x7fe1df7cee2ca094e98afe581bba0b691533876984c2315e19e5ee8e8711bdbbafb499862f2edce7da2d7cc23517cdbab098db71f7144435e8bbaddae0a7c89a	\\x00800003b7c46375d63eb1cb760136d8fd37c220bf986c47ea26e961538aab4a38915b0764293e765b0c4f87b566945761b2862ef667e54ed78f6db1d3ff10531115334babacb929a5deb8fd4579803ab06acd513d78c001c960c06e0e6474cb53057d7a723596c0b7183268f0bc1bf9c6a139f2a78c596891d4ab3d8ceee08361c9ab2f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfa2ebdd3f13157b09dafa47e7b5f4e8b409abd6330a1184b152002d317d2d87f23d525bf2d51f74d66513f79c7ccf86ee7804866ddf9078820ee3884028ba207	1639747507000000	1640352307000000	1703424307000000	1798032307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	146
\\x80952e95df31044a80251ff0b8c60f80e3fe9c321caaf3378da7602d4b51b034108fc5df79ebe75a9c66bc1ae20ae9dc8ea0c5c29122e9786608b1b43dfc72b3	\\x00800003c28ffaf66972dcdf9c94709975211e1d9e2d4992d2f7beace2ac1e6f95f98e4781a4c15827450ee65616e80352d91a33227071dbf92544cc79e9d545f03558ec0fbdff297e204b7d13e032cf05070cd96f3f3ff365fbd01600974c342fc7af27422630aec09c343c11b32b19ae52893972d77a0b43db9dd0d12b4b6ce78e8fb1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6cdf8f2f451a00a4f07a8541c8dc8a5d842c0c1c2ef87e5bf5ae28de63672fa13f7203e7c1539745f6f05c0824d1fd3bf44fcc8b49bd25b680b14affc66da100	1612545007000000	1613149807000000	1676221807000000	1770829807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	147
\\x811de3fbd9ce660e60f24fc5a2c35236771978c1cdfb309306ff7e47bea03f716c9676d463744c12f325bffc6fa9622ae092a4eba763ae5c4b68274d19af1a01	\\x00800003b3d31aafdb8a934c558a24c3978afed212dd14585e9b5d85cce7695e567051bfef83719f5e018ed640ff86253d67f18f7eccc5682e54b519c208a3be792192a6b33b2c8ab85e4d8b4fff5a66e6e0fe633e0bd4a9740c3ea2be71c7e21ee50d1abe5d2727a29efc1f2f7befda2a4e1ad1251ba5f1866142377186c5dcf1304401010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x522b458b60ad613baa09c8098e133a81878679a8e84720ae25c4df61712c49dac2df5fe83e8ec6bb36da1e5d6c351a8195b208801f57388071b11e79ec53410c	1626448507000000	1627053307000000	1690125307000000	1784733307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	148
\\x81150bbb9a9c410c88e27e45341e2dfc47fdeb7f0f8bdba91d9fec7ef3b4d37a5e10d689367f72d37da23d5ccd378cbff247c029849013662575b5669a3cfd82	\\x00800003cdd3dc2ae99574ce74d40efa8e7ec07fe662c81ef888e6f4f776723d618a17dbc622fc79300c3e07b62829a296f69f996f515fa6c7ba2984b2e6c664d59b28b6afbeaef761264233e938a5789277dfac1dc90f26cb575968466c3e287f3113fc04095f1095cdde943033585ba08dc9665c050d2dd81584227522d98683d55e25010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0d526f0a03575f6cdada2486232fbbf51ac08a8e87d0b10c5e84f57d5197b640e473b228bdeab6535a230bf07ac8f06b121fa9eb1ef450216c41f64158d0940c	1628262007000000	1628866807000000	1691938807000000	1786546807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	149
\\x83ad00ec50bd7107ab926cfca0764e6337df7a908a6af9ac52ec7bff0ba1744c943f692273b43e1bd0ad90d1709e5fd71f8b9623b2dbf1ac4b17953dfb2dde15	\\x00800003abdc3de0db0463a69056d7ec55e315619c389a303ad259f4e1ddd1c977f8ba07db2e4d9014a007bc7edadb6498804804a581a3a093e5e408f7dbce9e8ed042550301628a1d556d4e27ae6567045d7c41a7b3dee5905e6e91f75be9283a0c0a4e6971ebdb1168184c2ad165ca61780fae8425500a41f371cb4a3e1a80da4b4811010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x72432f0cb41499f5aec9ddc18f992febcecc8951b8c785176c694a72fb9ab7071542ee74da073acaf2b0b3e6838fc8fad7516e381573bb1ed37a92fc3801a709	1613149507000000	1613754307000000	1676826307000000	1771434307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	150
\\x87b90851a6396fa3b5232413cb0aff7439fd145027e54344e39c8464edfa407f021156c8fb435bf38af5e7d0790dcc936f89351eeb22d17c03937365975e258e	\\x00800003c8394fe25bc4d102b83045910c844b67324606451c6dbfdc4e4febdf4480eb80e95b2f6c309da2ca2701c78f62ecc141a0280aa0ce644215af02ef0c6d8734194a1e3468f96b633c90b9616c14971a11c9be7c9a8079c528ce99bce203e8522cd4ca7753cb0ed3379bca42a7a4b90114e7fa29ad6a12e156793267766a291b89010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xdce724549efafcb257950bd2c62e69d34d82250dd990170a2a95ab7f0ecb23964372d10e169d8938279826ac474a87a17eb73c0fb15d8d2ccf9c9cdf67525903	1622217007000000	1622821807000000	1685893807000000	1780501807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x872dea121c6bd40935dab55c31931b1db90252812e052b7abd4c6dce3a9d719104704b11d99c09688dadff5b14067feb0d41b9cfa7968f88844c8bca4b54d36e	\\x00800003b0f517dc6c8c512b0899bfb1099f49f6cb882d9b469c9900a2d7948a6bb5c9b44495dcab0fcc6980322d5afa4c5ca84a72c0ba89a591532d1024833a4ba70dfe8fd60ee9ffd405f1df6ddc8f16ef9f44e8a3751135b306febd77e58e719430b2f48eba21969c47eb4c608cd94ddbaf729823fdaadd1c2f833c1c18580315580f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbadecfff096568386fa553e6caf1b27f8ccce297e13a943700a2c3b79a0198425a56dbebc42f7f1129c3bb708c8d68902253f5e8baf3e886bf4de907a921d90c	1624635007000000	1625239807000000	1688311807000000	1782919807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	152
\\x8b6555e68a6c724638c2ba1f5232d3197c7cb97d8dd2892acc5a86877f695adcae093c5b2620ef844b1fc394648c492a45c77263464cca6a055d9d648d77af33	\\x00800003a91b23e58b2af68f37eadc8ed104260ec5a2dd2757bf0af9cbadef482c183f2c1f2ef24d5af2fa72bf5894ec0c65e76dd859efbb787e522257858784270b4e40497b0b0c7faee55c5f4b63bfe6b7662d7ea7d3934d623928c684d460ae3ec9cdce9ba3773b888157707ec64b32b3d7eb64ac1ebf169c264177d6d33b78c7c47b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x24056899b38c9b1b14f48ac3b991c1c9e904d7415b7ebb8f3b128688c1c594588410728c1dbb02a084b6f9f7440fb4be8f8904f85067a1cf0af9dfafb4267902	1628262007000000	1628866807000000	1691938807000000	1786546807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	153
\\x8e615c4b9710464c86cd4c4d39cd634d90bbffdd865a7796edf1b0ae623f1511460f1b7a509d52d905b9ca296dc94866462ecf88206cba557d63e894ffd654e8	\\x00800003baa7938a6f7f33f2f929168752a3c06d3e9b8f8bd4d6e263978d78d2f45c0e5f4de749f93044ff9078789c96841c965bdeff1eaee0281634953347b1f9bc8af170265699a086e84b6dcbeec1b22a0fbfca01337a7e599df54f3d750215da5290e18b9bec3dc1522ed3dd4e0b733464cde0e1a692eceda13ed03500c915f58193010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x148d2455b84e0f5bbdf202b956d9fe6a4769415ee338cde601c7a4e66cada027eb322bc34cbab892f823ed2867f78914f6e4d46a2b37ccf580d608659c77410a	1632493507000000	1633098307000000	1696170307000000	1790778307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	154
\\x8f41d6e3b401a2c068492060ba88a8a151a623f46ad114d7308c849016c15bffd7465b46546d3ff9f9f05e83096ac974f269a95af4f7d6df2fa0b9a7209145d0	\\x00800003dab3711bb21fb3bf9f1ae43dee9ea0d71bea2eae08674c8bb916438f1626557b79d5b308f756e7b3fb1c00401101e90c19bca36d8b99b73ded32ea861a1cc97d44afd99686a77bb95a62ffbcfc9af22179335cb7891d97a2e421547ff163d3b35971757f4812071e7b24e2610462ec84f86442155ea6a4e8e98f8d2b8ac47847010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2291ea28a31a14e657abcefbf391103138aa86779a2f93abf87df0540236cca4857fad71a5fc21cd1d68007ab8f839f7eaefff5f6e5d8a8a180e74c1df775904	1618590007000000	1619194807000000	1682266807000000	1776874807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	155
\\x8f3163f59aa3de2cdbd8724f7b6e58f64e347fb5cc993fbd6d83b9bb481f5fa7b0abc0ca9235afee3ad6ce2ea19c739fbe071eb63473e36826a0eeaf7f36b8e1	\\x00800003baa0c217f0a945d4bd95782592e3dd7bd85b58e116c69860261bf13988e903c4a48a8e4bef18fae7b9e39422cc8ca29241f81342bd83e0e3bf503b5601569eaa928871a11be3236a26d92f70baffbd3f945ac2024d6f55200e26065311b6a8b0286edf4f3fcff9a52b83b540d32a13d63b95e06895998a3e59e186e4c25aa30b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf773715995d53719e8297427e74aa3f960cab1185ed28e33f5fb14a09896a0249b504f79431125da680b5a57be75b12067cfc2638082baff16c4f4d6e6ff120e	1614963007000000	1615567807000000	1678639807000000	1773247807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	156
\\x91f1cfb64c31cadf969359db1e71335a2153b9045e075b64fa5bc386623785296e01ca94982771b5dd98998a423017f650c421b696c1b569c2475d2f9255a8b5	\\x00800003c2e4dbbc9e15cdfb856a1688a642da431c36b765537e968c14635138ccb992c874e27cde6694816844f8f3aacbd88e77bccffabd0c2bedd3cc9422b497802f507cb49302d84b313566a72ed82ac5b85c21302978c5a83305fd875a8c5b41d15059a53072749aee1283af7ed814c98cca9100dbde430a53eda9ee6f664949b54f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1d9bd42e309bb4a6d929c97676954e17ab823b72a89a40c53b23bd652b9e2fbc016fc4d7bab6708889861905442bcc0fbe4895f7df7278346aceb610cda1a50e	1635516007000000	1636120807000000	1699192807000000	1793800807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x9145ff8d5cd2a74979d004c2e736ecd5dac11b31a3f3f00feeed91c14d1fbbdaff661a2a87c50451e5bc0243e2a4e264dc08f55c916922c212762129c99d14bb	\\x00800003b0d407c45bb4a4cb4d8cdf32cc6ccc50f24088d965d7da809f1b4bfcc7782fbef52932b29df494d3abdf5c5de563cd5ea687d2e065c72ba27416856498a86c22f39e393bb75135c7e42746c5c8f98dd8594fe0b6fdf9870dcc1d1b119123403034b7cc573e2deae1cff4a0f85ebcaadcc7a863d7cd3e78599f5e5558d4976675010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe9e7bfa7cdbc3f967d0415e852293316ee4046e4a27f5b87f105862275f572996ac1016e6554dd5e9c1fa4484df6971a403fd20f1835ac6da9672c6c9bbdcb0f	1618590007000000	1619194807000000	1682266807000000	1776874807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	158
\\x942d705e1e104f1bcda2e8e084723a3f510f386d5b56edbfcb9f50e425b18fee60e79965108c95dc507b96e2844dd4c9e9cb0bfcd4c46123704e797fc6b6360b	\\x00800003adfd3ce87e28b0a0d6bef3422af8fb8d8c50ae4a1dc546314efd1b2e762287a6ef954c97046afe16baa3e6206ddf69272c18d0c45c0fa984b43fb61d5d6c379669b58831367f558f6901130bbbde2e33208ba756b45de16953b69c1f82ce0421a76e39d1525e428f9bf44656cfe7ac133bb6b7a737de78b80d3428a80137ba97010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe5c88c44b42eb1c59079e8cc83cb7122adcad436f7d28913e4ae100525b5d1b0fde08b165b01d206134d7c1d1e9c3ea940480083a47ca7d63bf81ccbfe061305	1640352007000000	1640956807000000	1704028807000000	1798636807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	159
\\x9929b7203591ae0a18d9cb0a2573151b4509e26bcd420ebf3dd6c3986754557aa5fd1a45c3496c222830a93a44e7db040f58628865d38eb8940bfb99b58125a7	\\x00800003bb3abe9f3de43e859bb4abca0b9214c8a62da15336117f9a139203c966a02c2623b5860523af3076653a673450a0c1ecaaa2ff6d8b1c89b5f80a211d4341a31e2748344805bada03dc51e03c0ac67f331ba36c30d485dd43488028a2796f9a00bc070388ba2af7c66289f02379aad0f040832ba3391b1ad40e835ee266869723010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xccc6aebd3e464b513ec49f7c30311faa6517167b0542be6e62e30b1914b7c73d8118d344f1215b9e890d49e57e1d0d44a097c7c7a2c8dcdf4e9ba4c4c9b7df0f	1625239507000000	1625844307000000	1688916307000000	1783524307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	160
\\x99ed49f3a6bd562ad43a7ffc3437b9761d7531a9df811d08cafaf4f21c692b4bebcecf202e454fa3bd5cb8d6a2ec7a7f802ae7b863f731cce4737a47bb9e609b	\\x00800003d4428fb9e39115a27bff422cef7fdf42b3c23b1908893d073d96b4ce531502484d52c898e3497de5f2aab83952d3c27fceca86250d6c1fa30c9756ce0c4b25d0eccca872de22a55eb6dc75a4d8189c09adb7f840f0e8205f3f66caa3e72b182ed79a5f780afa8ba07f60cab815bc49852d90cc565765eb9a661d631c1d46cc1d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x152835c6df74eab1680adb3a36ee14a2e61c630c391aafeadce211793238345cd3b247f00fd0533cd5c1a7e3c285de368b2c05801053f2e69c9d83f8edbb4a00	1610127007000000	1610731807000000	1673803807000000	1768411807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	161
\\x9b19af54bef0acdf29db2f62ce539ce00f56f85cdb863f91cd87450e30832d1f89f6315840da6a0932f89f456a4d14551cf6c298e04f3b37791b2bfcc6be2ed9	\\x00800003faad8638f075a29547766b3a7a7419847376da6d67e47ff423b6a5bc9cb27c95356df250c503cbcbb4b67200584ef7d52f6a00acd0676e42bd5aa4f2dd65a7edeb0263878082558f293e6a47dfafd1b44ac72972aa67ca1da53a78af210b0b3808b2f0c9ea38466f961cb3ca43130dc3146d5f66cff2996302be84c5025c4a8d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe08e43e4570faba940dd8903acedd6930ee03418587b8f76dde0997c3109ec6afc04cb3342d8b4e44719bc76c10ae17ea667df97a0f6e8356c53a2190165c905	1640352007000000	1640956807000000	1704028807000000	1798636807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x9e193c2dbd06435f20d97408e72e44a0a93f9445b5820af28f2369b7405b37e430196d34e20906fe755b6dd2ee5d46263ef432a769226305b5adb287ca46eae6	\\x00800003be857d08614475f55820f430c6c439d43b8e92f856a2c619321c6f63486a8a2901b90bd9223df94363396827067bb491c0d4fe3424e5fa9eaed6466338fc19a45b83321b6c5053f8e01a42520dd0221424c3f0ef5dfc764b873d9b950646f5df6016c5114e2948d4eedac8f98379f94aad9766cc379f35349ac58211d8cd317f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2e7207f892a69a3dbb7f1e88bdc98bae3918eb2eff34c3feb13fbd284b08ff9ec16e1b19b597b6d4b1f87c7880429490bdb1cb242ca14b7ca0aa8e4c1047fd0a	1622821507000000	1623426307000000	1686498307000000	1781106307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	163
\\x9e25738830042efdca12589798bd59331816d2197c980c01e757cf8f70b0772aae37ab3ebf5a9e1aea5a5345516ec50539f7f869af56b6ae7ec231100dd6fb18	\\x00800003ec18cbfd7e22fbd039d8cfdf6bf4d817cc5439104c7683a408e42835c13c84c0048cd44ec6be98c645fc713e8d2b383ee15c2c50918156f5ddeb5034c25012f8ac99f64fcdaa291576f04eed6eb1825cf9a28357e06884da319ce63b260d3c9c83a80a285d7a8f9f042619fad4a4b18bb114e10d203e63efe6186a0ec00c1097010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x314e78fb6bf1ea193558f7ee054eff900472cc591205444a9f4537acda4c6d087a813ca26cfcca0ce4d786260174e95e27dfa61cad37d65f1038d457c6a7b00f	1614963007000000	1615567807000000	1678639807000000	1773247807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	164
\\x9f497892f0d60a7dff86db52c276cf7a6adda4b6a6f636ee13a196fac1537c7959208ba6d3aad01485f516c14d58109af8ac92a6e7d0286ed81033f398f11ab2	\\x00800003d8a39ca33d044330487858b3dc1540f89e5dd153ddb6ddfa023ae3a6fd40d97c41919c1119c8232a47edce16a15a1c7dc6a64fc00ae5fc0920fc4343a0c562904c0fa642367b16901959501b43163d4b566b563cc683e1b7ae1d96fe708c1b89f44f75af3e48593d06fde32eb4831e6e46d70fc8e39a61bc3ee574470c8ca151010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf3b455bc5a48a4743ab8f6df440ade107872bb7e7eae32772859a8d11848f387c535ca022ba0d07e22e846b4dbf20f2a33672cb585fbfc2fd8d163635299510e	1610127007000000	1610731807000000	1673803807000000	1768411807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	165
\\xa0fdb7ec15ccfd3c568e1a0311b758a1a4b3081126d5538e6d579a9954d73aab6b236e03d38cb972d460d1a8fbf22efa0e7b3f45c337c037ba14da113fa88d9b	\\x00800003d8d4c73be9294000f2f1a6f82baadcd50c88b05b0ed4fc0d825c93492eede8f8eaa9c9e2ddbee26513878b4d50f1b7018843376e3862b8f77748aee2142410c5afa1c1b560d420a51fe8b4235dd35e4036d5f87488a228f01cb11e105ceb3bca06bd74a65baed2da784208d5ad34951ad2eb1c434e64c61eea5aecf23961af55010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7ff55b3face996ec169f5b11a3c0ce9c60ed65c30ecf1baa43d4e27b03e560ca714a9cc9a5dea7353bdd37e82c8a84af808b68e62bb80415ce04a1ae7d2ae007	1625239507000000	1625844307000000	1688916307000000	1783524307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	166
\\xa17d0d784d27592158e2b564a3678824bf0b02fc611843e4f36e01295f102afe708aa0b3bea771ae2b52af3bf2a9f64edcbd4aa30493369e981890fe131e9357	\\x00800003e735221a10cd7d3861fd6c087b76cc52743444947fbcaaf19d01a0072011b32c3bad92761e26ece3a1793550d35f3b1d58e398ac00ef6e81ddf5243bbfca0fdb0bc1cd95dff63fdc317d3aeecdc4daef98a089fca174a1fe27bfe5125214bdc343b00e0847717f52a7f438df2c6964f3bfeb60d2d22483718d020a0a53c894b5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb4b65687e73da45214b03caee2a3606d2dda272180a374738e60625b7b9ecbc5ca0c0de6ac28718fa65cb116010d95128d59d2ca3dd27173f173b3e40ed11c0c	1634307007000000	1634911807000000	1697983807000000	1792591807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	167
\\xa3b9b0823e6beae5cf8228ed6b0cf365070df24be037ec4a1cc2694e0929bce9459bb97b20b1906fc2aa2088b959d58fd46f72827877585477ca1acf6feecedf	\\x00800003b870f7275d3b9f70dcb4492fb465efef8dc28c536f01c9c75568ba246984386defcaf3591dcc313eebd5b767a388cfd87eaa023e722944e3b59d93d1f5a72b0582505a4127550ec05892e96dd93ba1e57a1f0aa4d546c277751c3ce539434820a9412296dc0806635252c8b4ee64cbbf0dcbcf2436395a13d62b567a3572a3cf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc3717635d6e9cd63d52ffb3fa1599bc82e779e1acc03334cc9d6f6de5d2d3f815174ee63089e320aad5621ad1b19e180ba388052475b74d037d37a11ccc8f202	1613754007000000	1614358807000000	1677430807000000	1772038807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	168
\\xa339a5df62c4e47492e08c74938627b4b6e16e1f01b91696a5bc443949a2ded8d149d695e412ddd3283a5b76c52dcdbd0ac27bfab275e6175aef8c2c9d82f5ab	\\x00800003aef6bec78724d95caba2daca1b318f25a759dc2b5128561239957879d75e60a28d815e58869477dbbf04fe40cb7427c81792b9e3f7ccb3dff1acd8b2419270875a39d393386eadde6ba2f45a3e7496b1e2719b5cd5911a3227595e310bd339dcc3d1e911f716151305e2afefd705abfc206f4460558d2c8b60c7b2938a1f9031010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xeff4ebf2bce89770eac2829c9ad680e1d58e6ff951836166d9261ed2ecca543fcc5011068a40deac105072921b1af39852d3c29d4f596527ad07c9d8e8ca7f0f	1627053007000000	1627657807000000	1690729807000000	1785337807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	169
\\xa41de8906af5d81695f754587881765f1ff6d1d856e26cfe700642a8810dc7ce710ab88627ea125d1eb83f990e7519acaa97c21b025acd6d989c662f922d7ba0	\\x00800003e28f598bc5ea742b15b5ad90e70182deacd266e2668deed430e0c5e714b3be8fe2a324f1949fc2f2c70c0e6b44b82b5844fb148671c61c70e9481e8175fda37c3c5c89fec53d01a5029577841be60a1f333e5ad5e97cd7b714b790ae357253d970501cf05096e44c50c1275899bcc512e2d124003c50bb8ba9b5657d93e0cfd7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1b531c25ead2cef0f3e791775a418872206f4f3b7a05037a8cf56744c75aa01d3bda9a7c19fd3a48181957e90be66159d8a867adac4d4118868aba744d2dc20d	1613754007000000	1614358807000000	1677430807000000	1772038807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	170
\\xa51d516ba2baefe32bbe3e18d22219733da6a89f71ba12d02d10cc287e2a49800095bf10754e447c078c83ca16953e3fd2f3aa2ca1502afc0e817e8f8bbe745b	\\x00800003bc7760b4587994c847da842d842ba239bf118b0204ea2cad388515c5490303a679648d3dcdb8d48c593e10e1df6aa3f25ba16190028ae530e36ac37502c50fbc37eedfa4a8d256065e48534368f3def1bbda8260bb593ff762f33e36f250f7dc9b3ce43fbb806b6e1b01ba002036f0f95b271cb9a54e64218ba8d7ade6d11db7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5e22d95c10adfddf38ef837cb4539355a9795e449fe95b787fd08e0b30c94cd808ac20bd262e9af464bbb994add0b812e8643577ebc73e699408530713109b0d	1639747507000000	1640352307000000	1703424307000000	1798032307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	171
\\xa9c5c0e57aeb4fa771a66b94bda15f0a0e24ad0af056cfc66284ec2248bf08d65275f34f940c3459b2c3feb48425008d45b6e90e7688efbf3f70e814688feafa	\\x00800003dda1148c54cce074cf2864cc8b3637e3f8216b4561b60ff72395503e498cc98ecacfe735a79cd0d65b4f3a77b2e6f937192c9b417b7f68d240111d8dafb392f9a24da307d3920a4d3754052f29c3ef3acd6697b3420b20916121e64656f6a80fa11242580afda449724abc4b806f98dfa4418199bf31f1e0aae8cf3a4de73f21010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x686b96c00e00ac4bf2b08b78e705c303ae343007ff8758493e1e6d89e15ea265c252227db1266de13e7115d18082ba2cf9e1334727ed94d1ec71e94552f82b07	1611336007000000	1611940807000000	1675012807000000	1769620807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	172
\\xa9a937bcb77475b24d50b064103ca0fff54e1aa60286be9a3927bea97124f7882a9a3415a8603996eb64c0ca9b8e8756833609f5e0d13a72c5c493bf06a06968	\\x00800003dbebc5a9434296af80c0e1e7a9f83e784e1f4e91bec49c2622ef3cab272ad5b3c50afb639f8fd11929d82ec7ab0dc96eab530d883c6a4b563d25ecd18ed15240f3333faf22bdf087319e4dd7ddc9a8fdc3916fe1b3125249c70b406cf58721e5e1d5888ec37139d6ab2b750b31f50829c49a6463c00bae63852b90e45339f969010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb9cc22a69c10b1139ea7b27b32feefdc9a6ce6cc7eea468a757dd2f52b59d6d8fe48a0897be56305c0fd76490ba39f0c5b5831149ab8c87704e0cf4dd0d8cb09	1610127007000000	1610731807000000	1673803807000000	1768411807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	173
\\xab61d1c628877dc344a5262a96461acb9a99eb83ff8f346649a6e6e3b5307e4bce99b1e60659ab9a925b07d2492df5053b838235a5a38114c0ad1f3fccc0d73e	\\x00800003e062185ea4a5eb164f39ab6081674b7e590abe79d129b432094c05a8d9d542350edf606d4b00f1a30154181bfe4ea5c238b1717b36539ebdcf26f7d724209fb2513c9e130dad91678d30cb526dc9947698701ee142bd4217fc4dd0e92a441daaf669012494ffe0b32bb7e1ae4b8e8ff9a689489720572042082ccc04b5c4df6b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe5916d05f7509577bd33ae3d1869e38a42704df0309f308cd577e6fbc71ef80470b88d26df5a088c399e2653c27eb1e77ba6c86456f6a3bf038c6799363b280c	1624635007000000	1625239807000000	1688311807000000	1782919807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	174
\\xacb5e6a64d9c329354f199ed2bc419d7d96ec3d224b5a8842ee489571a8d91e9af891faa4a6126f87274b369ad72d6fa3c0ee6098dbd2545c3e234226e6cb7d3	\\x00800003cae5d49ca5b4cc199113b5df6ba5cddddd878f0f21b998ce5c392c7748bbe69e5adf4418147eb7310da644d9df08e12c8c823ff06e54cdd7fd680c2646bc212f9d94e8b860476220db2e98205c5dc7eb43aa04dbbe7b32872d5a621b73899a5043c56a179d55d6de4919a03311d98971459dc15e864119da246e03c1da76594b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xcaabc3fbc8ad87efc8e170e8953e88eedbd24719b7391f81dbf93c1abb2dd73e37660eb0711f37d3e66a3aae51ccbad4df706bc911b71da04d44bf286362f707	1625844007000000	1626448807000000	1689520807000000	1784128807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	175
\\xaeadef8eac72911dbf6b80f20c8bde930f71fab1ef8331f659f71a05bde2f826389e3439d42aefa8e06d648cb03d7185d8d2d64390dc5632eae1b37ef0c1149a	\\x00800003a9b674499dced86293b7f9c020cf6176b7d7865e23793e56137732e59b88e65af5b58120f6dcaedeabaa74ad4945666b71cf22fb60ec9161c70833fe35ede832fbfcc548764093d3048e6e6d3091054af77b5fd9fca2c2b988d4cd14e32bf1dc32149c71280ddfffb17ce136c60b6d2f6008b40dae92a9fe6d2ede4dc7296faf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb86505131653eef086a265dea71d85b0df1e4f2758f19ad3b097f1dce5d03a9bae9ff80aca19ce321a3a87609dc4f6b3742fbab07a259fc1a79fe8a45637d208	1629471007000000	1630075807000000	1693147807000000	1787755807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	176
\\xaf01ec331b1cda0dcd8be16cf2b51d50eecef97da495c9c66a0698772a9025fbb17d1591448b2b3dc07b8e220509adcb4a6aa1d7c2c099535aee08cd895f210c	\\x00800003d148507436ff8241673cfe328979cd134980ad580e5c46eda46eff9e3ab1a8558e728c19502ecc10c0c6f2ec15f828cb9c1529bf64757f7dfa238d83181aa1b07e944533be059bce073a15f3cf16eab75f06fc8c117e450b019234b3f03ac77043373ad2a24312f8a4c06ecf3a28e76c76b927802dc773198e889391a215379b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7ac4a31e3bf51fabe9f9dd4c485e44fe35264397dbb2a109843fb53180a2f0a63aafb54be5d5967bc4a1efd9af1c3e8c1c4c3d04ebff0197fd80c5cf7b39210f	1640956507000000	1641561307000000	1704633307000000	1799241307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	177
\\xaf259a9e084f8870e3dc4314124ac85ac805046d13f4883c9c3f4260c768f9ee462039ee3712ca6a3f4d25febf3910f145ec1a91df6e1ef177134f865b6dc546	\\x008000039d9be12aea49567ce6303d4fdb018462890c2dee2e65f043a75097dbb84dc45f253447765f7b4fc13a6e13e4e3524672a5660c25c17607fdb03a27dc023efa0963445957f143e009ad7a52ffe578dd3d5a817763c3504854f59e13218e87bceaf68d822e455211275431de83ab782f3657a4b88728256350fe15606ad75e52db010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x21e7fa368cae0d50c75d1ea68923d88c27553709b8a88a461be209c4782c5b3796363bd1628f7a62e17ffbc6e73e9b1a6e9a0a8a8ebecddee8afac541e15740a	1634911507000000	1635516307000000	1698588307000000	1793196307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xb4f5f2563d83b81f4bd39c57c0c6a3da6a6e78f4f4b693cac2b8820743730cfbf4531587ddc5c59f6edac33d6c4fe6aab6f284f30147d6a740d4a9982de58c94	\\x00800003cd601c68995bcb66b3689f6c9303b34f71be2b454535a1926570a6db604e18cbdb49344eac513a0cf4f7098d75d2a82ee703b5ea887aa1f00627004c873e13f7c5a9af24ed30f1ba64c8677024021ea1ad01496937dc41d4a473bc0ccad50c6b415aa4250e2a67a9d15db123934c49223e8471fe0f5e7a787ae8221ad52b59fd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xad574c34195e6a0e5c63dfaa4f4f4593801ed3c9e4848a28a067e89de2e0ced0845a2f793c2c0108f6adbadc9ffedd4809fae2500c3ffd01595a535bcbbed004	1637329507000000	1637934307000000	1701006307000000	1795614307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	179
\\xb5c1418b5a83ee469d18fa0c2164e692e3c3c618cd04571e3f2d7bc907c6684e3a92f7506f5794822c8efbb4e0dd55d046e69db4e86b76f9981285cedd7c027d	\\x00800003b83f6e7e121d7cd3b6301abaaed247ca18967a174ca7fde6f92aa209556b1c9a0c9a23d5e863009a68a3e8cc87516aeb3b632a76c23bebd3d3b5bb40ebd63ff4f83787f1aebc107be4f1691b67b6774868c2cdc51cfa836d85170e0890692f3376e31fa6d4868796e407aa5bcd004b7b9148a534e1dc210ffdb0f7290883dbc1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x416de12ab377135b0c4163b3719061b682259ffa009fbc0355a3b244ab7d27654d4e2c56b113cb1c2b562ed11d4cd19e02f859f24ec3177b9b1055c7de6ee904	1611940507000000	1612545307000000	1675617307000000	1770225307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	180
\\xb61dc3807b2c3dc382d6e0cf8cf1ebb5669ef30be50bfc83246a296c3b592b58275de2448e6077d12cb392021b679e948be9cefdeb0000e3300ecf995ba136c7	\\x00800003a5f65a4180d307650ea2e2fb730b9dbc80d22b48e1f6d6315ba1c699417526ddf774a545a28225d2cbcbf8598fee5a06d681ac796d6614b4f961c7e5c1e31c26d2b2d9718a1789700b3c8a7b21e8f5540ad333cbe0056919c7d08d16de6839d0323c2e190bace22928d1716490be975e7d345c9a987a2bed6527e3bb2e5325bb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb0aeeafb5e3b2f6c22367be5e455b33a88f2098ab81e997535c8f20648cada81f0aa5c41a18e375e48d9e178edc60570f465eba0ba3ddd9cf4a628b7623cb000	1631889007000000	1632493807000000	1695565807000000	1790173807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	181
\\xb6d10378d80b5599cb64ee9b2a8e10a9e33b24399715101cbae9ca805659fa610847e1c418ab54624a4a07eb09c048bc91261fb7d1ebce22619be52ade804f29	\\x00800003e556be73387f0ef36b1a60fc41f5ecae19a8c8dde007bef2253a99bcb5bad20b8951013bae016a743d27a352fb39f47551e4c4ea7d5e5eed0798a3b6e460ecf9850cea7cddee1967f56a88e0e6fef024fe90153e211770e49f2738f48bcd1db745b5da39a60c9851c7b6660b117fc776eb3767f4876ddc91eff728830036212f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x76b55ed4629b61b27ca6665f334090448e6f12abca47ea4033ef6296cad9bda124668f77bfb0e8458e23cfa0f7c529f5ff53b73861abef656df38a05b0564609	1633098007000000	1633702807000000	1696774807000000	1791382807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	182
\\xb8699a3bbd9997eb4a8818d14de590e25ee4706cec3a100d8fb24a36a97ff56c6c3e5a69e087cc92125f8abb3669f8b8d8794bf4e0377ec892c50ab1889804fc	\\x00800003c33f6104b4cda83fdd10b91f51dbedbda40b4a3522024d4bcd2cb3f9c19c021f28508f917615308549771a4d218622bd2cd12a4c04ce3bcc34e1cfab6c0f5b5cfe19f14e96b783f1cba11eec31bb7a74af9b8466bcf5ed263d0a61ed7138e2cd53ba4c665d9c4deb165073017a3d7f7e9446c492b3d34faeb25634f39c88d751010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2bb12970ab319dc8ec59ea0ac1790d4e018646b2fa5de39b1a0616a54b28fcd291612610d3f411211084015be84ec67365013c3c598bf5009a86565a408a010f	1615567507000000	1616172307000000	1679244307000000	1773852307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	183
\\xb945d001b1f65acdeae15e8762b7074094af1e406769ec429e6a4c1fec197102716cbe2898fc794cb6dc1f01534a60102babe67681fd6b749d4e870afee4aeb7	\\x00800003be7be40be72c27cb009c8af73be032a4ecd6e1a0924eb53532e915dcda4b1740ee56412d34871e7c32f454b2dba35dc56683dd93890c779c74431105e64d4fd7c4f806d97ac2fe6a3db2a9a977a97e7b73e6a0ea096d962d7e2f2af9bc047ec5e19b6374310d876a5e908dc4e356e18d222337d429f0cbc265f8f977f97c1a8b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x42e4c40c99c81f8ad273f59caaef2e1d49f7713d2c94e5c4e97eda2b5cb17f6fbbf5559894ecda5a3bc9260785fad74f7711df27ecac94095780dee168d0a90d	1640956507000000	1641561307000000	1704633307000000	1799241307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	184
\\xb995934539398f1a16e5d2d4b5fe9f388218b0c0ca15565c326b086a4db5020123e578d4048a99c77a5b5f0d0bcd8d4c2ff1a9ca660a4bf5b2dd6231cb1525bf	\\x00800003ae5dbd4c0d5c087082386d76436f6d908a9c6279b6b6f1cb1070d315253bd235969ec9bcb21f27dda88ba06f0a1760436060c440f829d78546aeeb27f2ba7879442d5ef31e950044f9a2d4c6b638217c54582f8972388b38b0a32dc933cc7e113c800bca0171ab856a0e725d8cff7c7ae4b3d295d2d52d2cd3e82b2aa8750649010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x783753307127b2824b60be911bd07d941e9c6fef6d48aa8d113276a899b8470319a231726540c7d3eb57d0bec4b12763c4a1cb38ac73ef98aa69b93f5f3b560b	1640352007000000	1640956807000000	1704028807000000	1798636807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	185
\\xbc19679a9ec620b7874f9150123904efdeb246e5034f8db4d1434a84d7505404153c1636a964a81740fe35c42e6e90be72b001a29a5f6cb0081de6cfbc3c4986	\\x00800003c083bdf2745a41b5ccb541380a20a341378b72d1c0669b6ee573494f092e2a5e5fe800a29294c36a7434398838e30cb8afcad7f0d57d26338ccf6c166345beea115d437df99f007f5059fd65576ce1b6682c43e07d2a683b01a8f700f6d1c0427975163e13ae3c672630e7f8776fa3dbf459f2e0ab9eb3214ddbd96f722b7a49010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0a81bcc6851602f6381e52f47d497a1183c378d89f5a3c343e3c4a277aa2e0850155eab4e6c9399e1af320bba0dba4ece9be1ff21d89aaa68849c0067c3f3a04	1635516007000000	1636120807000000	1699192807000000	1793800807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	186
\\xbc19ff320128b7fb3cb774e3f1210a4f5419697250f83ce90c1fca6a2bb9d2c16a1c5755a5d814398fb96df433a33eb6a0f2bfbbc7169dc6e71943fe01cbd911	\\x00800003d5623fe81a7ec33f5e5b218e7edc7ef88627073eee6ee1138c8f932b0091c7179be9c828347d0d1bca4c765fa3a487f13b20d0810d744442faca33c1a9c9fd169585115683226e22ee64dd14f9e9f0e0933b33f3ca1eedd9df147dd01de395397b626b85046ddbd367730ebac8242dc8016c7419f903fdd01c94bfc6f944ddfb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9ea7d70c77e3d77c157569edd7694dafd85329aa8f29e1ebe908a3f7c2e645bc49ec1e13c7b5dda7a82e6e93e9597889e85e31d70d54831ab2ea95c4503a4d0d	1618590007000000	1619194807000000	1682266807000000	1776874807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	187
\\xbd29743b84f748297cacc5f7b6f6180c4e9df63d72b3cc8abcee901670a765e15b1043a783f4fd19bd154f92b2fcd2a53959f05c441e8f3097d866d9d373724c	\\x00800003a193b17fa7f7f6d60a704326187df19a7691d747476852ca66dad70cc22b8ea855781d72fdd5f186363e145fb85881f00a34883571f311ce033fbc5b27f4f2b98fafecaaa176bb10dcfd1edc6644dbf65c52fab627c1a35c819280bdd524f56113d3bf41fc3f92c03d2a0f24afc5b014ebd50517d6078ceb1f5b5685f7c0bde7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0ae45b08620e9c2af0fd0020c40193a590e300306a6d9e6d67bd13647e1ea112ac637a04cbf08f191d4672f48b94cfce949f0983b2cd397c5b64db3379ba6700	1640956507000000	1641561307000000	1704633307000000	1799241307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	188
\\xca45328f1b59243969962a803c98a144d43ab553cfa3c4f217b1a26178798583ea4be10006d8018edb72797f45c582b393fefc39b47d8d2ae7849cb0fb881387	\\x00800003c42a0cb20efe9d23e3bd83ba0efd2ef38a950cb3f4ef93e6e88701452e64ea23fc44ce83cc311bc805f2710a3b3c3e1b08b3d45b732720dc01d154cfc66d0d1ed165663b964ccf4d4dda2615552931cdd731ceaa64f81101d628c219a0c07caa6fa5861b032a326ad7c00292e71b5045fda77b111caf7777a22247a203e765c7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0483a3a36d3a4bd752911f81e6f53a3627dec1d5638132a3ec08fcabf667c235fe2ca39f9c94994fbb27e65a63b313ec15be3666ae93566cb5b405abd165ac06	1616172007000000	1616776807000000	1679848807000000	1774456807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	189
\\xcc7d68f9d666ddb1e4e48283d6c903434719ffa9daf737eb59f67236a64759231f7123ee2c2b17218a8d46755ae88daf615b7ba0113feccadee847370fecb0e8	\\x00800003b6adb722e37dee9e91fc88f9938128f2e79bc4d32261f8973026c8895d59a223e6be4299ae730b10ade0f999498616e9f7d44dc27521368f9315893f53806d02c59979499c6b93a1f1b72e0853f7e9e9d376b494650cc5b1ce8eaa4f80c82fc92619615ac2b0bdad27b30a5db703198deab16e072d5ce0f5e293fea9f2976d47010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x36aa1c57dd478715b1425fc8f05b6c833b418d4567e64561ec777b1f9dd728d6e483c8233666a55954e0994818e72c1340a9eb314f1c7bd884b15f1ae258b602	1614963007000000	1615567807000000	1678639807000000	1773247807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	190
\\xcc4929557a0940debbc3e4ab2ca3108576f7f857871bae60c240c13ed1fe838d22dbc2dcd8e408ae972400a390884f06b57fdac0eece9320d76ebaa577888aba	\\x00800003e76ddaa9f9f1c2640ef467c4bfc22cd6e7225f278e6cd84f3a7bf18a2f4e038d2d4f762d576afcfafce6ac79ceaacb4808d5147c71aa68c26da2d670c7c36b856e817883a57f3e402cc6bb4d0336becd24094d316133f427699dcef06a4204f74125a811eaced4744c832bc150acecc0fb9f81920e17d5adb3ad43aa79d319a9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8154db2ad839096271467aa70f4ad4211f04538c5313d426a10f94d6871629253c7a8c15eaddee934396462968df0a4793f8bbb50f59c807281098e11e5cc00e	1632493507000000	1633098307000000	1696170307000000	1790778307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	191
\\xd0ad254056e006c0d43708ef5d88c4a722edc5682554e5042287f831970aa9788a6c70d25b774213b654ea7d7a5215a79e668d08b961d31b755e688c85ed0d44	\\x00800003a875be07a8a57c0f16105533768e5ba9ed3b2b55453e6c056004d1ac0e23e8d72fd124f45657f16fe8e96238c314bee5fcd710281d34f007b822580b9e37effe9960a8a042bfaa36b73e6622b48f5df7382ff9d2a03a2dc2c97ff8b03d529956493ef1ab70198aa6b36f87554dcf2518cdda862a42edc1f487cc42d4d52d5349010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x174997a432e2fc8301630e6513247ccfb055c609c499c28336a0ff0b60e5d2fc19810029898fc8531f04f15e3809372e6014f8306834f565ddb8a5827dfaf30b	1610731507000000	1611336307000000	1674408307000000	1769016307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	192
\\xd0597c92f3f6cf0fceda074f6fc42f385befedd6adfe130dc5885f1092b64f4d784a5131e1a2315c8cd4098ae54e83fb63f6ed2adeeef6f4c33ef7bbd743a669	\\x00800003a9edd4d4ca818bb8c5f333f75c2438187d3f8ee8df652b7caf09ad25da7e8a20dd2c03ea5ad1defb1a313abe66ec972bd65167c0d3ca0b2ab0dda38ddb6320d1df8dc90447ba6d44fef4987aa49ae4b89a41e5033db82945fafb5e690609c0ebc556a29f0f786bc129e039f165d494165a75f84f8a69105307b2c2c9d7c50cfd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc8de6131918c3493a85274a77e52afa70ab530e1f92b89ce4c09457b5989a0708875970a71e0c16bd7f3b318dc5222dfe85434a04762f63d7ccf820edb3b9a06	1617381007000000	1617985807000000	1681057807000000	1775665807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	193
\\xd13d65502d7f2fa4a0e4b48732ca54ecd636b6d4bc533f07368b314960593e10e00199f8c3aaa8058658ee1881c5ed371b7d55e8b3c5b9a37e4eef428e677e95	\\x00800003e191e56c0434542fcda0a8584e4b6239ad9b096842a15a1838be129cc5727500d3956785633940cffe639d47c7773228b557c2dfcafd6425728b5035e6590aecc9f17dcd60a10829fefa46029e60550f933d565c528dd5fc7146cae1466f2e92bb112a473563360994e6f720cf0c67218859feec1f68e180ecb6a22401e037cb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x628cd6847dfb38dd5adf21e1ca7a117a978d957bf33ddacc4658c10b623c22e0ade7416455dff469c0e0e548607d08b6cd612c6e0f478815122be190cfba5000	1619194507000000	1619799307000000	1682871307000000	1777479307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	194
\\xd5adbd582d26448859e943d2ca9d3849e854d22cb1b01180772f117f21f3804a44e2f35378fd9dc83e6d4abe9187c1dab02e7827668c1253467648bf1c3a15c2	\\x00800003b4b6161b5ba0fb53261cdde4cb5ea97e00749b606e676d81257c9f3f1ff46b65d66c8dc9db29b00765cb15dc30acd5074bcb30a0934633cb4e9499310ccd63745ed08d0e8b5303be129a60825caea645ee15679b1a398dd4aa5d11342ff06a01e65c84b6fc8f5386a890abd6d3cf82d61b1851b02fedc20dcb09c9b754356a69010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3180f084c7be1900c75dc0a3f5ea979d2e6c7a7d7b1546221a4c69a14a921057f4ddeea10fd7e3beb7b30b0acea13dddd236de1c7100b343c3c98d96c037c402	1622821507000000	1623426307000000	1686498307000000	1781106307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	195
\\xd6294278aea64620d02cdb19a821c29eff74aa6236984f93c82b2ad85dda8edf434377e71af35e0f0791bdb11e96c6795b7ef3088e40d2e8a86cf5c38b5eb813	\\x00800003c985f87c8015633c56f2c3c6afefa2f23a8042c12327cfa9e712514a81c19fe9e4d590338f5ac711917003b90099e635da04c1cfb707268693b2037470553a78fdbfe724e864699e2246e094c8f49675a8256b91e810c8b1efbeb86cedde1bd90b7b379db0464c8574e393343f36b39504024e595282097c3f6ed8ceefa9e6e1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe34d8bc88ecb9c0581aeea26330d3fced2bcf85a91f09b0c3d2824dba915f217bd8bb58943b11e73757bafbbe2e4e66865dc5013aad8b3037920a4a2fd9b1204	1621612507000000	1622217307000000	1685289307000000	1779897307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	196
\\xd73931de8c306d51dce1fc652217b59119cf4d4189b14261dd63546cc335fda209894e6ddd1c5f96385d4b80351f582a4ad4fc1391526630049fe63bc51e023c	\\x00800003b439bb7bf0dfe713782d16d646dc354c8892a54c15508565538e9c38f11f59b5bd3bea03e228341731a038f11ff87dfa3c285c0aacd17e74e2273da1eeca8ad2e82320ddb41d76f5e5ec239f948a385ad9df22fa5920aa270585345b2e511532dd9a64943c0b7cf74049227a9ad79359af8ff6171d01a3cc1f296a23c5057feb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0a19ac1964a78448d88d6e72cb3cbcd033c9edc045b22517c022d20d76914a6e34210695d6c55e0360f9984e28c449bb965b494603f93c79a361d06aa1e6730b	1641561007000000	1642165807000000	1705237807000000	1799845807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	197
\\xdd85d8680fd92c21ba7650c741b1da046de454dc9a5b0fc5f2ab7c0d08ab41f1d472498d25629d85cb2c40767ee504d0c9389f07f08eea87b8e47cb5a6a3520e	\\x00800003cc7ea8d89ecbe1770d9ea9fc7d2168a8f5bea33349ee80f0575d02f275c05f82c73b8b8ca9a866f9739b1bed32456974ad34bfeb42a2e9e0aa9a991120b91da0fe10d908a1103d492f5946ed7b7cae575ba19aa24b1047d545a3a7f3fc24080eaacc010e72a2098bbc5523a8c348cc732b1311195d3da87f62a0a76bd479917d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5b1c7dd1af243ef2ff1b17c1d1021660f871d9080b248bdd624fdf62b0539dc21ab1a693a08233ea3d0ee2a51a1aa52044041fddde760e4b0bc6dac637598204	1613754007000000	1614358807000000	1677430807000000	1772038807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	198
\\xded59d717723799b06ffa3cebaf263a673753d38d9e70b878d16d8b296ce93bc715c9e81287a46ad715f71bb08c84259e77340437a5b060edbc57b44f68a044e	\\x00800003c2a97baafa0b982df599cbde586e165c417662f2e99512e17af4f4ac6ce5f2ecd4a3e70f97b805505dd478a37c2dad9d2b9bd8e23887a46d9c0aac5e3b06aebb451def134706451ba1ed95c98dd80224bcb6fe7033f24a41a70c2d2f3d01c91600e5e030c086f14ba429460729e6edb3916b3174c7b16382b1c9a3c77f1eae89010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xceb6ed13794c8baf568e6f25fe513c849a04800ff51b7e3e199bdad52e5800435291eefdf9b6e484bc0167f88dddd9e47ffe607c4fa5279064221e450538660f	1621008007000000	1621612807000000	1684684807000000	1779292807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	199
\\xe0e5a01ad2e4c2890d878da83c75393e77e5f3d1fc2909ddfe0cd95e6c5be456849bd81ea6aa77647c548b60b40a3a4290a5e07ec1d0a3ff4385a1f6f870b3b1	\\x00800003ad0aca2ef3f63cf02a3a69e1cbe46bdf8e434ad10d0ccb4ab5900f5ac6adaff5c4b4625a0b8651a7655467353c3e5df7c780141072b1ef751d4631c4b747d04bf38bda03b152549ad3e8c347885fcd105b9e8f814f5c172c3706f8ec7eab889cbfbb5763e0f2eafaefada12686204a5ba68b88d09be9598c543313f2c85fb2ff010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe9317c147606d202aa1ee694291832d6dda3b1a73f6caeccee95b597300edadbc040db2f08807d44a83db00009f75173763e0f37a00342ec88fe8f8763ee720c	1623426007000000	1624030807000000	1687102807000000	1781710807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	200
\\xe1b1e1795e4223e8767cdeee8ddff08ec96391cc2d454015bc9084aa80f64eef7d8f6ec9542f766f29c08d8bbfccc4ebb203f3bcc707157fea43af255fc8d09c	\\x00800003e18f72ec1843b2036cd9380ef17a3e9e824943a316941f2de8e5f0c79ee9f343ec05f9cce451e747722ad5f73f542862399baacc9eb481661f69985352c723178e16a484699f67e9c4f831ce889bc003041f0cc44812c47d33b59713100c5ca879ab6035889642746a42df368d308f8203add98b33f3c9c06417c077d4dfdf93010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x112a89befa4adf12e56211e582bfa622582d84430052aa44b592c40cfd4467438c37b2fb28b6712ae9c9e2f7269f0e24834e4429a43da61b8a42059eb2897f03	1624635007000000	1625239807000000	1688311807000000	1782919807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xe18de88440dabc85f40fcfff57bb30d622a6db5dbf03fcf672982d23e4c32cb29ba5ee52023050e9a97fdf507716aa22d65b2101ef903022a573bd21b1ba3b52	\\x00800003a662879d2f05959b80d5d56b59bc37551c3d272a6b2578037bc0e66816d9615325094e1ffb4392041d211076c10a07ff16ed558f86ce3d8becd7d10c9f3dd6aca376689b95595ab2673b91b783666c13650a2543594232da6c09218c86cb55f15762c0ca3cc842bbbff4beae82cb5f1d612fbfb5ad55a93cccf2cecf6b5c8803010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x49f5f725e790746de7300c492eda6e26f436b6ad23578d81d00ed2852a94eb902496ea929adf196831dfb2619d3b53d018e20ad96256b73b417cfd422807140c	1633702507000000	1634307307000000	1697379307000000	1791987307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	202
\\xe389a63ad03599e63a18d2ea53d5d841800d431d2925b1aff03ff5b4f7178b3bdb008f7858a16955904a881824146ae3bfae53a72338ecf01821c04a298dbfcc	\\x00800003cb2bba969f61df73cdc86f665695131858497e219b96b0ffec4cd32c3659046d8e105ca86e15da824bb4510869599d03b836e4bc6040c655666d8bf7ebd6f096d0877578916c795e8ce6580fe3765fa7a5b650b6d05bdd57b14234d0df7ecef4cc2790e396ecaa592f7311668c6183b11d3fff734dd9c5c242c46bf4ed13dbb3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf674dcb970eda3981e9375e3b7a7fb286713163cb6636274bba3b11f39788e0364e86acfb9fe88b856b9ea33b2751d935bd6c9db2fe177f49828d1d77d73250d	1619799007000000	1620403807000000	1683475807000000	1778083807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	203
\\xe4d9d95bde4fdddb0edd0e04f0ff2f529113fd32350a5635c5cc6df9ccd2401cb2619a3f3584ce3a3d89b9fe3dfedb9afaac5b42f4fd1afa8ce11328386c22d0	\\x00800003e96edf344657d66fafd16d68fc81f90c01806c610d133b0b76c55c6bf20eb4f2ed98f0ef4904bc6b53f081f4da9357cc36b36f7b266f64e19d040084c1bdd4e63b085ac6e974e4f90a49e4743292594f299ab376fbacf8fae3841957aa048aa36233c48e1b4ee3d3cd2acf5c6164ae661cbb1528972d20bc8bfe34bfdf73e16d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc9d02aaeaa5c7f110133954ba707874db22268f1a992b04df1119d59cf5cae0fc9836a9a926619c05edadb84456149d3cfbe2df3fca61b4eb5bc4b672ffe7006	1625239507000000	1625844307000000	1688916307000000	1783524307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	204
\\xe50142d30eafc3f0fbd4d77ccb0f1ef5ab3a57e4a19bf13c2fe433c2b787e530286b3f8ebf2b9495662afaf4e4d93dd04f1d0cbad1f0670a3ddb5d2473bc8fc7	\\x00800003dd5fddac8273fe63ca0bbf4cc57ab44b17521b2ef51ea58c4135ab5efb581c51808fa22d3914fd19d55168564a271a3451ce4811c014c7a7f54896d6e4676eca8c2d4d283132c58f7dfca35e0fce473fd17f23b2cc073bce52aba5a48b3e2484f24f469221324f999b171bd24603cc7d058e631fb5b55e2768ecb4dfd8dd6ccb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7324b1bfdc514bf4f63449a02239fd8480877719b9fb4d71d2fed4ce26bf4a9d2f26eaca517ac4fda9216af670d01e665dedb20a87ab347bdd6e639a31e40e01	1616172007000000	1616776807000000	1679848807000000	1774456807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	205
\\xe555edc091abeaf243cfd664bd3c40347dd4e368eaeb765bc1e1d394a3f59faf5e77c0ad5b1849cb84256ff08c0cf68f32ced46493606cf109daac659bb4e72a	\\x00800003ce1d109542f0175133edc3892537ed2ced360b68926eaa72e472dcc01d4224a6ddf98bc47c5c6f605d392ea7a91b3762032e0b7a5a306a4dde7c5f15f3f8b8a8c817c34092777adc6e39def7d947f8c535ca13682af372fed1a33016c3ce1223a411e9d89ca1c9dba2dc0b3ae137b12362d16b73126c63715f5a1d7b90b24fad010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd48343d77e436be543ec375fff11ed3464bea0bf2644d34482f1aa84c9909c0fc20b9ef08ee197162ab54fbe3dcb934ae8e12146650cf3f4944ff39afb54d200	1631889007000000	1632493807000000	1695565807000000	1790173807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	206
\\xecb56033c0f206957418455fd0a598a1d621e18a9e2c913707c48a3c93cf7d6f98694648efb632fa6a7e85da90bfe43420c5ffb886d925816145a01d549e562a	\\x00800003e64e96b9f1f5a0b439841d8d3404c22246d751db0e21cf3dc3401585cf8193f2e3d7e9a35e8ad8f9b7b8defa84d7a58b7db18dea01bde4094e7fc50e5c09f46ad1066195aacd1845dfd28fc9fbfd1fcf3e0e0f309f2fbca8fa6ed4aa9ef3ba83401cd082011178e20535990537b0f69fa8b62ae1eef162b01b861827c1efe6bd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe0637e1d8a7802a8416991a424532741b67dce4ed148b3b6d4a6effbb9454870e5effcc7917da32a31e4836ac2a85f03106fbf25f97284190251e92efe745e07	1625844007000000	1626448807000000	1689520807000000	1784128807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	207
\\xef392a298ae1e2f81974e06325971c52da7f07c2357a6d897c1a8a99bbb3d495e2082c198ab9779d6c7b71e0837feef7af7235105058472d39b0eca8d010ec08	\\x008000039ecfdd5df8a092a526034baf1966630866ca005702266d1d39c463aff998ab1aa11eb6593fd1c828a1883ff6ec6cfe339d2d7b37b26cd842c7852ecbe913028a4d731e4d3b11c580035ff1cadf55cd1ba59727113baf8cb4358e7b55799e9c7bbbce29bc1d43777d2043b4a176789d8b89db198b73c9012f8b231486bb548457010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1be86d5dafc47720437a7059580744d1003f291597792464e67419096b989b5b01ec6e6482df6f4524c7fa033487115059af83c5bac7abbb9b0ae271cfab040b	1619799007000000	1620403807000000	1683475807000000	1778083807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	208
\\xef619099e8cfedf4f93c3082eb097f46b0d366baca8111f3965fa6c3ac42706c9f217b088d737ff3fac581b7522e7a7598df6b2a5b70e1e990c7f6933906755e	\\x00800003c42baa07ed9da6444f4c489fcb2920b7d27deddf01d5d4e33a446202099094a38e0c0f4f53c6543175d1bbf07fe0b4f1b4b686c36d57dc58637c0034e9b42b794dc716b45880b1cf2c387bdd48445d7623faa08acbdff5fc410f9a1df14323d03859b7b04e157e205998862e5e5f1ac277771fcc502880eb7e8b4609029daae1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd60687900858aeb89e11654a2d67f4881099fcb0e182972e01855a1cce5dd1236f3d272eea1df4874043b20e9ee0517af228d71fcdf8a676f53fa98978beda07	1629471007000000	1630075807000000	1693147807000000	1787755807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	209
\\xf6f9335581011938f91402f0fcfc6496d0ca3c85acf8e9d98d5401cd76a00d3cc5cda6227504736574023ef14067dd0296fea425f0cfc8177e3034a93c5a3a16	\\x00800003d005eef1a6ba70acc640a8ef6bb8422c62c79db29613cd274d15aea6edbc33f36358b5ad2595bfd98112aecf5409d73072171dc793d3ced4d1fc4c7d4bd7986e45db6c182f605e9d757886e78dfd2f991a5b3dde412db8b215d91d6debccccbdf4e7b639ecc3344b84104e5604356b6889f52d237854961278d2c64bb2101847010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3b5537ee40f4568ab39fbd29f6fff67ccc676f3c316f06e5704e9e64ed63df4fe191f9e67c2ff0b7c6f8c1292aabac015db37977db0e98850e5946e373b7fa00	1623426007000000	1624030807000000	1687102807000000	1781710807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	210
\\xf8215a9cac1997e789e4cd5e185b72109714795db3045fda5a3b57852bf3b73676fc9de6501d960826929fe160bc790ef7b1a49afdf402bfa52240285941ef90	\\x00800003b81fd095ea2982295be38213f11f36ea70a4f92337d927a4dcac3644349a01e90e28e61b5c13694e92c72e8de52c1e7f98102dd9db36b6a8fc014eda21de4e391908630e1507a14111a273e6a24931e21de9dfb6a6104a83d155486e08dd6f0ca9d3c0fd2a05e162f681385cec4a570fcb260434c90c5f28a884ca7799cd54b9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa9c03caa344bb8d6030d564acec8ee17dff170f53cf9e83806983d8f8cd064a320cf746a90aeb960233b25aebfefccc86071a9d78aab4a9c3250e299b50e250d	1621008007000000	1621612807000000	1684684807000000	1779292807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	211
\\xf89de86554b559c8c4897fff2609de56c98a8b5ca765575d2dec3a11671efd233bf36694b2e3280ca39ac3d3a816fbff90a2257551f3f0986addbfc7954b8456	\\x00800003c7117eaf20bb6c3b72036deaffcc142b960bda4ebe108c98b085b21c466b0c844a892722cc4d2a83eb8955773b1ae8748323d1abeae1ffbbf032469c5187a324b3dac12406696ee511d7b193a4d02409244f45deca1406a511e1c6e0174a4efc9c04bde2fb8cb9e42520baa42af3cfaacdae2be76449c0c45ee1c7b6265a88a9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0649c9269e02bdac578c3b4dd90908915b7ed95016f1d5af9ff2d1d59de2aca216343ba0ab049d00702d07d02c113f2a65a6543dc91df8b6428aae79214c1a09	1628866507000000	1629471307000000	1692543307000000	1787151307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	212
\\xfabddd50dbaf2b19de4714268799eb0d0d91aa8ec40b4d88e9fea2e5d11e14f6b58daa2cf61cf4d9ffc8021dab09bd67fe2ded191a4376bc68efc5acc7c96a7e	\\x00800003c779c2f08683cbaa666bac072ba37393c623dace597ca0a6d9d038dc675e7244f42755c5b560d882f14ba55c2337cef306a5d4578686036498df2cef88364078adc2fd14708bd7f19bf49d47371648611b0c241f8b9256b3317b4deea743fa693c3042d90e4bc832e97e00f34053e52e3bd5fd1d676a3219b8582d04c09a5c3f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9b5ee37987d7f4da7e352ee8ef1956baee144e6fe2bdbb22b924d15b5558a8f88db18bc4d898a6688cb0d085b84881c87625a82e856236e41f229e385f19570a	1637329507000000	1637934307000000	1701006307000000	1795614307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	213
\\x01fac62a28a0288a1472c4bb7543c9c70ab67053b090b4b5d323ba35d223350b37739790565ec89614d7994476cc69ce4e9e2e0089239457d17885134ded8e2a	\\x00800003b1b9aae1ec802ed6b6b281f39ced4bc60b584c7c2f6dbd0b7fa91f010b6bbe71da24eebed7b649e7c3009d0c2ed180d2608663343316445532c879809c4304c941061f0328ae4306ad0112474b768b8980d52eded3ee6046331f4f998b42c934aa974f9813fc27f5302efb598a794573de3c4a53a3385d5446e713d3211df811010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x290b6648a6daaec9af44cae6b6813437fa2ec242466f07045f536233e4064d36bba8ed3c73f6e0c8f869a7776313baa847d7fe9e498745a5254097d6ea1eda04	1617381007000000	1617985807000000	1681057807000000	1775665807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	214
\\x02962c54a41d4573925f10b9c25e51a4a880536c41297923e0a3afceb689d60d207edc5d312cd03de5bdf8a490d5a96d3990f9234dc9053d2ca21e8c25e83104	\\x00800003c5fc0934c67d5b10ea40e5e51a902d2339d554182ced3f8a0c85138912b937a52e539a376ea1877424d393b19f0a2836db19db545cc0ac21e5615f25d1127f51a95be3a5609c7ebcff1d549b637e119e7f117dd3a22dad954027f1f38705777a0d35c36ea1e21623003e4f4cd2e9f623f801245ea8abe6459872d2def25418fb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbc6b7f7f382db33f7f900fd5b4748068cef0c782f56f0056915f9ae5198bf8a62ce9d3a18de266b27b36e00a4949e4ea6aca99dbafa9316a55073c16e379dc00	1631889007000000	1632493807000000	1695565807000000	1790173807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	215
\\x06261079bb5c2312ce6c2a41d820ac5a592b8a2430d7536e3aa6391e2836587ac7736343d90d75f8728fe69ac8772fe19ba2d5836ae539a9f332650f406f1a80	\\x00800003ed9704edd5295277535449d47f2e9971ad16e5ad4e050caa3c3f191a13ff774afd40f058ff0750e95be478e0685b3a32814dc1f4cfc9caf066b4b6500bc081aec553f4674ea911e6afa0aa9bbdeef45fa12754e0b33b831d6f89fd31233938f269e23402924671fb47ddd0179903976e17158e4f0e2353f686f03f1e2e623cf7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x52a3495b4ef546df1c809e1ae92f56a4a73a49d087ae32a314efe72d1802d308aa93be03da38e7a55a669b9c9fe8d015b1592d11e5dd47f4949c17b15aceed0f	1631889007000000	1632493807000000	1695565807000000	1790173807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	216
\\x073e66e0e0fa564f3ae19f274867c39710a8e8d932a6e19e1f6ce3a0280aece1b5c5e7514028b5578e6883ea8b56b88569307ce0220051f22e8f2cca87d80bed	\\x00800003b71e26c77cd13a583bdd5b27d03ad8bd55da150a68cf63383a0878d4caa83f47252c4e693c44d6da49544b72c8cf0438d8c734275bca8c4a585e3eab9a676bcc578a5c8c9b1d99f876f25aca955f5a6aefbfd675ee821f53537581b39286f813ca4649bbbd89e60c513ed2d11404c821d95147b104c31f20fcbb3fee7f5219c1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd9b6705e7d67f313ad086d4c790fb0cf091adbf2ea930d7932b81c4160a9e158baa8e5dc82d1b8a6375acace067c2b784e59a8590a50641b02d78454f8626c0e	1611336007000000	1611940807000000	1675012807000000	1769620807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	217
\\x0ce27d34999e264adc2e3f2a72893a0d6c81f8d22f3cbfd14b0bfb72b4739b35612675308faeedf6da0b3f9b002dde0844dd3aee2209770239f30b9663372171	\\x00800003d6515a2fa06f04d5498688ad5b2a59732877fa658b85d26ef1687852db8018f0d5faad21593ae36b510a587fc7b77e4229aab360f1d9ea7b0ef603529029c9932b131a36ced66587ae9c0f2d74b1ce8bd43f8581934302bc09b582043da0d8ed730b16e44dbf995b99037efbe3d1f45a62e9380cb7f36c6b17ee3eebdd63a591010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa828e0d8993f4fce50badc98b2de4513b4b1eced4faf1e2fd8fc2fd91dca1db4fd4316ad3653a08bbe231551847fb1cbdce63cd19eef924a2603a2ae73eff206	1614963007000000	1615567807000000	1678639807000000	1773247807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	218
\\x0e72274f3292144bf7c3cf91deb6736a7b01b939ca20e3ba0ed53c2de7abc48f9d7a573e27fff0a9cb6d20db44a24abd3c62d668fed9d0465b88a8a9318b457c	\\x00800003b7d10cbb4ee1a0defa6198f6413757ea368e73f0c2b4ff0589df972416d393ad6ec03d8796a703336ccb28dbc0bdaf8bb21fe2de055226c1860a4c47722813b8ce550b2d754ccd1bea171b71e11e24605125182d46688d69796bfb38a593e5bbc90e093301c50fcec808100f46514563e14bd475cde8ca2abef31e5ea31f523d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0d72d156cff740735dcbc4d00732c6f44b010ec87124e93bbf8cfc89ad7b8e4ff0fb5a64b1f2b4565cfc7861c55d881a0634ed9d41154ebfc0d3737425bef403	1637934007000000	1638538807000000	1701610807000000	1796218807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	219
\\x0fda33d65d41dcc561eb2311aecf28e76fabd0ece561a33f63146a3059e5bfa78d71766f64460dcbc4f13809ce439b17dfc7d6ccfc3f3f25f6890d699f084202	\\x00800003bb7993c99e865dfcbca39b9b1451554487593fe6c7235b0f43a3df42585288e11074fb7a23c25490fa578c8b97bd6e3435e0ec68743b97abdfab2567806d4f9f02953451db1ec0d87690ce4be2f31e7614326d5991027fa60e025d78af682da2ec802ac18d87fd8d2667d167ae8bfbb635c21662c047f5a497cc0e8c45877019010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe067778c750807495a2cef9e8dcd36b4276755a5efe5a70bdfa9a6487e52c3ab4d1219ccd17b061879aa4ccc1071051cf6afe892ef46eef82593140859520e0e	1615567507000000	1616172307000000	1679244307000000	1773852307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	220
\\x14066e9425604513d3696afc41d281c26e6c8b8375567c9a81cedd4fb136bcd490e90b0e4578b412dbf04ab1c773ef0cee71d5b483913acad9e12b7b3a2f27d2	\\x00800003dfe434ba3e2437fc5c956affdc9643075778eecba4b85fb3dbba2fc2a4cf9983a5639e5bda4a9f5239f95f0b642ea8aed36e5d58d01cc580070572aa838f98620a72af25994cb8c72a0f3f4da75a2be07c5ce6f23bab5f8713dea7d38cea94206db8655b50d8c85ecbc2cafbc8446350eabca01ce9fcfd54d3181ac8038920a7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x614abe00ea19535d9beb92614affdf695a8da7f7001eb886210b0e175abddd1b17bef50bd743fc6776c46c8bb6e6bea5862785481b23687ed06d3f8d7e3a380f	1628262007000000	1628866807000000	1691938807000000	1786546807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	221
\\x15ea32ab6fd86952ec461d39321f21afa4a2b5525b1d1790ae5d4b89fc19e699ce4b5e733469b2105de56e9a981e74f3e9943d78ea7f42a4032c26a0f4f0e04a	\\x00800003db5787b4d64b4e1809c832e4cff9dbbf3c927849d359aff8d440356aa58ba8fcf09b8525cf5d987b5fcfedacf8d1df8960aa2ef6f1bd51148fb18e631fb89a3515925af774bcc111564b62e9f59aa93a5aa501d6df039c5510af194187c3c17913346ab5e660a06f8300fa1866d123e13bf3f3fb59115c4952902b93ad4a351f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xdcd242aab82bc91b3c99b23225d3a3834f1e6a771167a58cde2acf896efc44bae53aa315372f87b476ec94f4afdc0ebfb5b738fdc37d8d780924d008c5bd120d	1620403507000000	1621008307000000	1684080307000000	1778688307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	222
\\x1b82592736b17835a0797e9df76926a575f5db9287d8e08d4586b12f472575018ec6f3a29f81df7ff971913384226255ca7d6edebfce356ec44a3dffca2ab7fb	\\x00800003de2a3881518d7f7efde8b4e7de7d478bbc1e2652dd8e4e0359c66fb0f73bbf6ad6e0d98ad15b3089a3ddcf20ff5ee466be7d53e22dc22614c7bba1c0ce90b596dac2c9d4f40eaa57c5685bdf5a08e787190ce0854e6e1cfcd7a31c99c7ef774fa450fe5a1355e15b0faea88ff0a8e1d1aa83a495202fd3ce9bd695f9caff21e3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x833d51794709aacca679743fbde7e50a644d7416f0ee9a9c817e68aca0eb2b5e220af9bb24e1eee38fecc670af61b5925249b27b334ba26b04329d365e3b1504	1639747507000000	1640352307000000	1703424307000000	1798032307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	223
\\x2412110b082a05b1d4054e420e54b13096f43bc5fd2ccf8509eab6024daf6c4e5dc0b0293b571da90accce2811b6bd6b422cb877c4d370c9748bdd596a0601f3	\\x00800003d65460a9b1652e9b12e35ce219738c40fb5cc14dd92c24d26fb6cafceecca2ad069a769dbc5dce00bf89139f15641857d52ca52cf8ed34ff3ce1bd1658788b96f3ec23a42d82cff56e8a906e7b252c02fc6797600c6e81cc7eccc5b83a889bea42dc71c0dca2337766e043e2fe30b0d71232ba9ed485a8ef06c904cb1a60ad0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x589ef11847680ce0134767fc001655f4156c140a290839b31539929d5cbecee2b01d888ed9aedee1072699b8ba6cb11c9a734d9283231105df744c185d209502	1616776507000000	1617381307000000	1680453307000000	1775061307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\x26d2988891edd12a125d64bcc9a8cc22b20c2b8cc75e383e73799c439c7cd29eb4ae06429e2f80756338d2fd73905d2bfe1f2028877b33ab40f8026ea9c2bdc3	\\x00800003ce5f2ba2f5e52a9c5e5406420d5a0b959105a5cf50ca2094bcfb25457dc47b924ec3917d8a671a1cb2dc6046dacc962f3a8c00ba2ae39db4d888e55660a09f7eb61b324bebd36fc09f3e71b140e3d7f0615f9164d7aa0b9679474aaa7528a77a9b751e26c2ad7177d5b91fd0172eeb7094e067302ccc750611a158332f8c5413010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x55e7d11019335510eb668462cebcdf072d4ecbae14211a81bcd3116bcaf686cfba7fe7fd6a12a7af9b5c42ae6f5447e896a3cba9c8c71fe22dcebb7a275fb10c	1630075507000000	1630680307000000	1693752307000000	1788360307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	225
\\x2892747b4b63590885a8c68aef0ac503b4d39c3933b23efe88ba4eb7b842b7be4ccc08c7b1b778ac46c3808fba797cfab2c197577b7deda1503c39f9a6ef1ff6	\\x00800003cf58ee77c8cb27b4bc8387e5efea4e48ca434b70cb61a8dd586ca44a12b41871536ffc431e46c354e03a88a7c5dbb4f9f2ec98f76bcfda2bc36a9860e8cb8721bc642334df3705e6dd13d9b4b3e36c931dc7a106cd01b93c705d01200fb8975a66aa935680ab54ad21dab60d08dcfeca92d5ab105b173b354946934e616c7357010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfd1ed47a0e27fa4d8ec6da903ab84e2c8c82b741bc6b0d5f9be6bee853088dab3fc9e931277f352a603fcbbea0305aa4743d77c1d97d0c6a995085e2dbe3f003	1632493507000000	1633098307000000	1696170307000000	1790778307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	226
\\x291243c7c9a76477c802ce453e8836cfa214f3e20888a67f4d5954d1dd4f0367d87af46c7a4f5640e2f4266347a3765d0973098675bbabe5ab9982cb25b21ef7	\\x00800003c14654c881b0eb757ea52cb8b4aa086f97c66a721c9e0dc10903c21b38bedb1b70ef30fead3dbbcd97d7e963b5ec89d6f8e2c7fd4df4a303824b695e2b901e115e87ed5fd466a51cfbd47f42338c3545a3a851e205d1da7b5d6df08fd691f455d9926900ac909c3664ea519b0a21f9dfe90178fc4e65a8d655d1f2af8950cd47010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9be2fd87af822bbfd3d7673069a9e563814bd227c2ab05c5a430fc82ddf81301d0e8a0acf65e334a88d51d9d186b20a73b1c55220c46982ab895235345a37202	1617985507000000	1618590307000000	1681662307000000	1776270307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	227
\\x2a7af8f14db22b26cab31161b70991d77aa554128bcd83766a00cdeca41f95d4a5b3de9d314d2eb7cc26eb64f02de53cafb7e03102a7da285402b353c03d92d5	\\x00800003cc07a889d591b0be6969c448e2c7ae659de719afe3e821f011793fbc2aa1b7ac930c349616039d0e127d12cb7075694d71107b17ed209fb66cb20d1948262e8840e30fec4ac6d8ce8399ce8cdb219b0004eded91e8095c5667059a39b12453861f48fa69a64138b452a542f9d5da41907c59b66d5f873acc9d3800bb03b54de3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1defb08aa79bbe6fb233508ea8fa38c0d9309f40e65b78b8d3b8794cd3a7d6a131bc042df684b032b66df029fab3449e7d3f7c8d6460204ae76aabd67d5bdf02	1636725007000000	1637329807000000	1700401807000000	1795009807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x2bc21d9fcb602cb270985ec8f560ce68eb8fcf3388af0d0f04a2e4e01291c65c2f3ac90528c629b3aa771c29f904d1f264ae41693d75758b1e919634c06dc8d5	\\x00800003e8c5793d2ba2869e4468f1e9dace82b30fea82f3dde3787080421be14c4defbdd8250a8547df2c29c3a47689b0e94f6ae8e4b45b2cace85ceecb1e0da7895ffc08ec751d68c252a5bc1e55ccfafb66e6866aaf81533f849f20bb1d640cd94f48072e190c7719524bccdae6aabd7449b951b1c56539834a800ac3f000d07af9a9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x06608800e17f196d6837d2a3f845f9ddeb1e1aa21ba0b7239b757ef976cd73cb246491dc09970dc4e29cfd244ed77fc2b71193ddc9c1f6dfbc3956e9e6cb0f0a	1637329507000000	1637934307000000	1701006307000000	1795614307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	229
\\x2f6290c4e99a2c02b7acf20a197409da005368973562adb7e6490263fd3dd5b2c3ca136fed32b33fc60e6ce291e02d1e7a8d1b294df4be906861a023e7ec8f1f	\\x00800003d984f444b46825171c59d0af7d47ae0331b01e5298df53b5a6c14fdb8abe0ced6a2b5558d63dd737ef7fa51656271baf5382f7fc107857a9e54c5b90a775ce45bd3704f09fd526f1d81d92cd0ea50d026e2fc6f9b2ab2d1cc0eae82df0bbec7b358e01b21475d492292c5f5ee2b3dd059bbe6e8bb36735fb1f07c5252fadcf15010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xac721207a8583d1ea3e627dd69a9fab94844900af572bb33e2c77a77d8ddce7f5fff72d23e27b6d0ab5e4fe7ce4db50ae995ee47c6ade93247fb2ba4460cd805	1621612507000000	1622217307000000	1685289307000000	1779897307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	230
\\x34a6528552749c61d4b462b8db5931f6f33b92516b2d799784e198b91c3772e5e47e50e213e1d18f48a36eb16561d3b532e67d3734df7dd0c97afb06c996a940	\\x00800003bf8aad6fa42f6ec7f22802b70f8cff1d873e8ae3aacf7065bc122a9c4e2ef2b611e3fb9ff5dc3e368b9c5f4eb715ab9f5ffb199e47e30a2410abe2c91d99af581a2b4fea415a14d91a3dce8cc273383b236443becc83f12acdfbac7d70105b113f716ac11b6fbdd744549cf843ce077551173b8597fb15f4b74b48d89f49e4d7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbb8be2d33a2c84193af0f0d96b9e070998a85422c2c77087b892261d154e9e6913951ed2f53bc9de2c64a49bee7cf1d7a8fc843eb0c1fcad8ce3b7c318732207	1641561007000000	1642165807000000	1705237807000000	1799845807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	231
\\x3486fc731620eef697e05e8fbb039aacd83f57c2d7d44343709e86e87e918715c85c5974156311043362d1d60695e601eda173fb9f74490c86de75d6f5952f80	\\x00800003c067240079386ed57276365664784d7f335da8657cb6481504d58dc9d2161ae7cdfe55874d2ace69b3d57ecf2ade835a5d3acb91fba13fe5a9c5dfaca65105707b0afab648727f6cb62592283e352f316460f43b6d8f846cc7020db8793c90011094b79732523d03443ae7a109344bfddeb360e3f3dc281662a076ebbdc19ae1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbfc2d49b756922aa3ff4532a3894880a7421d0324f00d8be6506ef2b36907563a469fd31877b272999cff8fe3af5bfdd27aca8004e3664f10b8fb932837d0a00	1637329507000000	1637934307000000	1701006307000000	1795614307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	232
\\x371ad82111ca493052ba90c1f83aa4d9bb45e445855fc40dfd0fec59b9a6e97b452e5259a603f4726aefaca56a65fdbb179caa37c7a1f53b4b943dee11c2dc39	\\x00800003b625d0591f077e811d1dd86af4f2e26797260eb1fc1fa63cef337bb7d789feee7c4d4da0d5e795f1edf8f3e40462588facb677f1604f1fac936116b64346233f5ef023ce8e03060e7497f27b82c39133ed63e570f5d1e2fdc965171abc7fdb1565b1f6b40b48542e2e590241220a90386d4613dd8b4a7d612dd499396dfe7aef010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x496127c19d2bf63112ff865a0095f24f206a23e8d8ecf23560db164d40e382d6b4f913ce3afc2489f3121b6a15c600ee96906e4b3694f6d5ff390840e880d10b	1637329507000000	1637934307000000	1701006307000000	1795614307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x38b68302342e94680c0eaa16de3df4e32c61c2cfc5d345cce7a42d3c4b3cb11145c36b10da3cfcfb2b494ab251e3ef6955bdfe78714cc99261f1bd6a2e8e8a5f	\\x00800003f10b72b8f8c361fd23f850e1985172e186c549abe37cc5e6a341ac3943d10e3db278a5e7f129e705c7b814926f110fce9e092a3dfd0b2f7f079b4983fb120dc34e7cdd8d4160258d974111b27aa73c1e7b846b40c050a70b35d7d0d5f914bfaaecce82bbd6eea1f9ba941492842cd65dbd8196b59491a849ae0b2d15d34cd1af010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x68a4b0b4fb8d2825e0593a750bb40370f6776b746e8603b6532d2d9e921b29df49727533f6e7db75c1ee4ff559f83d9fb6b2235719216e3ff57c8bc0b121ba0f	1634911507000000	1635516307000000	1698588307000000	1793196307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	234
\\x3d62719716bcc241957f0051f59b0ca5d2f5bf15b8432fbc63156f22a1dcb06b1f0f9635d1847f55d256be77c3cd684e3799d565864578d86f850b820e4c7c7e	\\x00800003c2c045b518a0ef04d74bd1100b200361255d8038759c4101096aed0a864ff1f02f8f4ccaccd0f77768e9e5f8945710e711023d8bf460472ab7ceb4d2a2958ec0e5dc43b5c1c6d8f821115576967b4c7a40d864aee85cbdeb338a405f0fcb128da285617f25232219cf03eedfa2dc0afed04ae5c3f7a19a9e10e97a1ce1db6ecf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5db1b28a1de7dfafc1228c04b509c5337dd2de94c7b5b795143c8ace9a54b18694b999c35c04e94b8829b0004593963f2077ffb7bac52c1868ab770e1857cd00	1611336007000000	1611940807000000	1675012807000000	1769620807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	235
\\x40eec1747b8b701e0b2cd7c04d2c8b62fbc7144b36d09b0dc07ea1d408dcc7fbfcf97cf3fce44e5977331588fc90cc0950fddde113b6edc6ccf51023b6e219aa	\\x00800003a7378cb066fa1002e2ed063599370ad921697e10be58ffc37dc000cbc6d8b4f60287b628780233baa1d5e67d089f3ea85ad67d9b5e19d80d5e68b9431ce31821434c26de962b8b1dfe73c69305e4e131bf2335256eb82126ac6252dafa440b407ea2bc78dd40208c93ab3acdd035587cc27b91601096b5183476b9d08a565355010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xcd35d4df2ee4d45d371c3d8b7a3328603da37324cb8be392f56da12ea1f4275a3aa4e5d9b0cfae19297b35caef21e0f4a565da75b59b61fbf85f98e5d0eb4008	1611336007000000	1611940807000000	1675012807000000	1769620807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	236
\\x41daaf79d64007f8d62bb04dd8d44be0f569c3320eb62cf71f4e68a81718682affd0d46e55451c75872a3e40ff1c1efa57fd8aa7e74ce12efb2fb0ad0206d7eb	\\x00800003a9ec29a588d95c8913c702f7609297384c1d839ea4f270e6a72a2908705e285acfeade8e065f88bc34da7d2770efc4924e9a67f1c36757cc61679359f69d775c579262a70542766c3eee61cad31acc90040c911a7bca8810b6481acb2fdee626845c07fb5cc7c3c877a5f152a04dc1698d8d68355a44457cdc6fbe5adde71fe3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe84e5c994401151fece9cf0749aaad3bc01616729a53e5b7ed768a807a8fd55e840e288acbdcb8e7d029e24e8369eaa5b853b85859e0532fd25f9498753d440c	1633098007000000	1633702807000000	1696774807000000	1791382807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	237
\\x422a370b845a4bd73e107232117cb201f9f4b4ecbd0cc31d44ffa54652753a4868bdf24c375a1835f7364ff5ebbe620044693ecf38909cec0738c2ba0f22ca6c	\\x00800003a40b31712769458a5da7e79e6d308f4e37d96344215218185ec3f29fc49317a57385fb7f9330ba6a976951b456209236b00a469b9c5abc1f2544175ae157aa044fc898949125e685ef58cb78b75e95de69b94f81f63edb4af7acb5d7ccfb6f0eefa46fc621f88a666ace254c0b345c54d5c181a0eb9e5129b853eb2edf3102e9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x98d1ab3568ddb7c6b73e9a04e0deada0aa050a85866ad2453847e5d40d1d075f5007952f8275e36ad41f3c2d2bd51a09b0d40d51e3351263857d439ffe99560e	1624635007000000	1625239807000000	1688311807000000	1782919807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	238
\\x4a66c8994b7867d64adc30f226a6cf0f47940c43b583f420458d55f2e3b322905d3c3ef906d3f0d3153aaf4814b21970c114303eafbdafb9f3f0448f62c7ccf5	\\x00800003d39594fc50b2f2fd6c50999fa803b3e07277a16b75625d873b3b40f8146612d4fc6cadf0516a116b688f955adea8100b642ea4a9d26df6fdce914ee7d22116cdae1766d7bc01b1dec131a10637fb86ad5facd104495402c7c1b3eb8b6079db8b47d881c22613acbd09463b2df4897ee4ebac5d661a4a0c163f2c6ebc5ea4504f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd163e31b1f884a77a1f864c676ac2d0cce606fe8782e588ba1ceca9c9a2c328163289cf793af1ec0bc1cfe677d7a6d038fd252ad2684bf45a45dffd677207f02	1622217007000000	1622821807000000	1685893807000000	1780501807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	239
\\x4b52ac1e8184a28e7b93d72b6fab878456baa89933e68399b5516063e18434835629eadaead57b3155ed091ea01062c6de6afacb242e34c9312b57fb76d760d9	\\x00800003bb205131490df136719b482df36cb3815fa2a32855ccc09f1ba5b8660c5ce033c4022e01d9319724993f9790d1de5dae886a24840631e4545a60076d61188183d3d118983e7ce3bff40e0075cded01ecc01fbabbff967c3c537ab60f7f069012fe6f5c59fca932cd173952e17ab4f9a9088e9840ddd58ab0a7fdc9814358f51d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd1140610d1e9f48dcf32acd401c4825869f517556f9cf576edc609fa14ebfeb377631736b12d365be3d1d5a209bfd51d116f6f698fb00ce48973306bc1232903	1635516007000000	1636120807000000	1699192807000000	1793800807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	240
\\x4f0a3885eefe95666287ccb60181313dec4dc468df9ae3aed168bad862f6313a239e466237d3b52820dd5085fb42e910f6ccf0e7846fe5459647b470827f08f8	\\x00800003c5ee3e22082c194023dd77f8dfefeb64ffc9a5585f4e1e43cafa8985b04f9b1fbb6a79b2cf99108efec54ddf036c33913992cc6fe35e84d6951a841a1b66da9fabf36ee1cfc5a77ab3d58605ab4f31677ceff2ef6ea59fa7db68e6418da6ced6bedc50a8d4a821e6af902fe3c079aa94ed84d6f0bfc58875361e281982d11b99010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x37ec062bc0fca4978710aded0a4bb34945c786bc850363ff62a7d4d11962900e059fc87256998048f5884f994a39374dfa990a90089ccc83d3c77b456801ef07	1624030507000000	1624635307000000	1687707307000000	1782315307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	241
\\x530e76d2b9c12d0a7cceafaf1b4423b59c1d1eb2f07864a26dbe5c773285bd6d9eeb12f8005f8026991a2d3b34e2c0ea1075abb89bd03c81d47c6d90cae69387	\\x00800003b1875f19f357576ed4f96c649c70e2646f23b32b235a7c478881a819dfcb6eefb89db91b05e5f71a06a0b523f691a81f9ebbda280d0571cb817df22ce91744f4711dc8875f87ee1575caeb32b741412cc42e226c1ea1448041edba9872197d65bc447dd810525d8398d8064b6925507942ecfea74941d3c46252b612079f2287010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3c2a52f3e1bb359bad529ab4090139faf3f6ae9c8d78f6d87f13309b4ddc727e65fc386eb574b8c31df46f04ec5176fbbc70a58c9290e41ee97a200c4f815b0d	1637934007000000	1638538807000000	1701610807000000	1796218807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	242
\\x5462a2ee635f315b84b1596171a3b8bb1d128b2bf88faa6ae6097071a504659a03e7a853af982d997d5135e110a09c411f8af9a8ad7b0bdf1a622efdcbbf341f	\\x00800003b92094011e69124ddef3ff5973b0bd15bc38a2b9a394adce84f2ad640676873cadfb014aff4008a3b0540db90b3fde2d3790e23186e17ad84ef82865b6ff6892fb98e07909bc9986446b9f81a829acad73394d315f35fc1e11fca80be72eaa787ce8d527d856c2750dd1182d852ccb36872d14ee87096d522e6289ae1b915877010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7e91552faff87009e19ca84b3df78dddc3c468651cebcab6d70f7fa2eb295591830291bbb76b035c5dc94cd399cf032c41cfff8818266c8edd776f2398a21e09	1616776507000000	1617381307000000	1680453307000000	1775061307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x59fab0366a681301332df6859bb8a1e71f65ea2acafa20cfc767f9df92e259f577976dc02fd4738956b2591db03a1c16d16f4447c5dcefdf9ee20ef31c090811	\\x00800003e670cc194b083760c9036a53f42bf7f8678ba9b2ebd3e7628d2995367c1209c3dad22e9d8bff9647a5633e26a4c388ad60c0b8f7d471201ca48efb41003fc027b10cb1d99e5413aed08ebd3692f22c71dda3cee410e3fc9592e5e7d50a852b5f05812380025ec740b49ecfeb77c464f17ef4724d0e26613a55c4030347ecae85010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x45fab5dda831ed8d686f86344c2c1364b215470def262ed95412527f48f2c3ed1fdd70356f8c311e7a5dbaad4c65084d456d320b03e95d8c0de92186d7925c02	1617381007000000	1617985807000000	1681057807000000	1775665807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	244
\\x5bde9a3a8160d08fa5a5ea59c33a3ef0c89710770e312512d23fde2e4fb5ef21ced699c3fc5b3ea4b015d4fb6d40f31d0b096f8089b6075eaec1b96a3109bb6b	\\x008000039fc2ca722b3e890a98b6bf790c916aea7d9cab1b322edd7b2b178faef1cc69ffbd8da4a2b49421aa826550c64ade894f24c3ab1bff6e10c66ad0fcf910b71a654346906564ce3c1812b9f54bbfe304da456f2b8b761793eba01f5535917ff06cc5b7ba8657f8eba05cb751035b4ca01a91a49923aced61ee1497f4fcb904cf0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x413531dab6e32d8da5a62638daf6ea79073c756ae7b7a2b17fc1b06dc413616275cb7e02a69d8394baea92f9fda4a18901a194c13aa33365de819efc274acc0d	1631284507000000	1631889307000000	1694961307000000	1789569307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x5cf6ab424e133f974583c42e60e124095f82354b754d5fa16eb27b11a0c51d3745609b64137a8b9f17c5a5d83fa95c273019498bdb1a4e531af4bbea8e68f5e1	\\x00800003cf50a46eab5867f40104a26c771aa06e842520dddc7d489044123416b034ee3f1001b3cb6bca5de3b86edb4c01563226ff2eda1a2bdc822aa04524d1551ff573ee6d21e9fa8aa1e75aae6623651f6759a7e716f0e280040a88cb570770147e2e25eab4fb6eb94a0f9f58b8005a9273d9bf7c8f74744da02b4a022d6ebae3a995010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x72b9ad9d58246dc224ebc11594a7edd49ff8982511f0188e7faa37e36280668efa4bd9a29ab19ab8556e4dcbec122bfe9030da5ab35a672ca254b2dd28ea8b01	1624635007000000	1625239807000000	1688311807000000	1782919807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x5dda042f9cf49155729d19e6df7ffd018efeaf6aaa81c9afa0863358f1f89e4e03e9369347992c9e5a84b4606e2e8bb0010c2ef6e12a9a1abdef36150aae1564	\\x00800003d084e5c9979539d3ad091519b76a1bcc085e45d35421c303363c8f26e17d37d2f30acc1a79bce75a2b16df2f57914fd6ec737584a177fb2f4502a90eac92b92ed3e5155fa0679ccaa6d8dc4480550650f75dfb17de412f5f881c05c7150ee56e33aaa9ea496a1b1c6287744b4382a130c21f4c2ef7127a810b784c3f107bb377010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x576e4d508ec3d10810f61947ab21e0b7008af1d515cf22f24c5d7e0f820124a96ababaab932fd29468a5303bf990bdafa91c9bb658904be11588874094c2ae02	1621612507000000	1622217307000000	1685289307000000	1779897307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	247
\\x627e9e6e181faf182461eb762c4ed7ca38b77fad200e823cc73539a582e27e0a36bcd3b4a38383014806817abb4a754c943f939092256d041bde122539253777	\\x00800003deddef50921002d7697a9a907e67c0b86c9ad9afea44988b163f1ab59ad04cbf4d1b661ce700c54e1dec17ce7e64af90d8bafbc05d8a5d11fb8fe17701a5d149e02da982770d1292083693181b5f77f7be9cff26ff21e6af211f312b11ec8506f8d57aecc4d87b3b3ed1ed268aa89a24dc7e9ead7371ebfb112f600499a06a21010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x80c4b7a6ff4983ca297bfa01af43b66cfeae5b4b4de82d09f56493326ed1102f0d02e2830d5f65f86c42f2d2251178574085bae0c935216d6dfc066939d8c90c	1638538507000000	1639143307000000	1702215307000000	1796823307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	248
\\x679af27e012bf4189c165737c67accee90e2a8fb6b17a7ca3bed8d5b40a2b66e82b9a1951d1fbbcb3ae44d9b3e31e640be55d319c3e1186fa63f4a3982e64b89	\\x00800003bbb219dc585dc8100c5a841b256e6bd02b9297d86ff8be8c2c6ea19f838de52f0abb45e67a21bd16bf53f1bd1144ef9f05cd9790c32bf9e15a8ce313d76716be7f4e5f6d90049918a3335c77f21c34068a14e0d95436eee0d390daed235f709327c0a9bc88d5acda774892bac1121332e8fe4029eddda5af18a9e62252bcf12b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe2abf723f9d01b3fb10680e8d701fd3cafbce5318a5ffad76b6916e66d2b7ec7abdfd3ebcceda5a64d47672b94f712705082298daf95da29f5d1272013688907	1630680007000000	1631284807000000	1694356807000000	1788964807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	249
\\x68a62584500df90356913759058d97f8e82940b7edef6c6516acdf7df6e2f57f065f4d727ef9e8c3049ef8a40e4e88c3b48d223348fb47d3450555e190171434	\\x00800003b908df8c32cef15f9c2606741e78a645df1dbf5b7374cb1215fe4eff66b804ead6f857e70c3f2f7a5ef608b793d739ea8f88ab9b8ad761dc8225d565bf9a14915a60416bb1b406964e3e989d01303b724f5eca7908a6306f2ed11ced0f4cdd0d287340d653801fef85b1a8913cd5f74ffec91a5efaec2217fa3831155b3f4321010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x11f081cf225f29cca7dfae8d545f49c34fd8b61300a14c0739fa574ed83e7af8fe388a04e8764fb981a39ac405dba4d4e27dc2af2b15f17c90516e9af011b704	1626448507000000	1627053307000000	1690125307000000	1784733307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	250
\\x6daa4773871d8e4669d9e09740ed66f33fa45ec343ffd4653a0d1a367096b69a20c0d000e339afcb5959a7bf92936078acbbc97cce890fc44dfb37fb11ae2089	\\x00800003c8d22dab3e2e1f4517cad82ed79dde89a2665590367c5df6f122f6f976a637f0cb18aaff345f04df3e5e3d7ee47216ae8620bd30df0a1caa5842a9acdaec8b8a45246ca5fb8a20c0d60ab4743d02da7c7dbd3fe07c925c544531faf90dba7edbf877c31bf6c2248a407130ec1e116ef662633823cc32bd69ab060e02c2246d87010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe46bea64d767a709fbbff3d50443d028c34af6d5260509c836832e0ca1bb5fa71a25bf5dd436c60f1c7ce66a1533c431ef89e6cd80f327cc79f7ad7e99b81604	1633702507000000	1634307307000000	1697379307000000	1791987307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	251
\\x6daaf272abd30943e5ce536810e31d456b558b6a7369c990d8ac9d4ae6467a0b9580693e86262f8a1a335b6e2dacdef9ff7da1d600ee43ba6b7f3963ee4bf044	\\x00800003b8a77bffa20ef4cebe3fb24d6558551fd394b7868fb4d346d1b05c7fc4487882b667a3b043ef14ed5af0280b7d170f973c1222c1fe06b2d71e33994d15b0a2b2bc7faad9dc5feb052e796a6bf7681e89e0a8072399bc3990876b81425f0d19b0214aab22273fc6ae9bb5d0148623e637b5ed0e0d6f322bf248d2ac0c05c1c549010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9a73d98ef368885b5546932fdd4d5a98e86b2c5d9f021a020c7e303155818d4c9b896976f39d5c94f70e6375f4f45e3897206184b11cab76c833521f22e96c0a	1629471007000000	1630075807000000	1693147807000000	1787755807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	252
\\x6ee23e163c2275de16d4a8bca40448ab12398284d66c237cfcd8a8935422aed29c5469966c5cdbda097a613084b1041c3e9792a63a872d7d976c226260c4c5bf	\\x00800003b07ce58a242b49da926393c4b2c308474dc64faceeddc63fded83a3804d268b4b3fcc9bf8341c743380a787c5dd037557a353280153237ae9c31448d8672c4d55801fe4dddb0729d6233fcbd0f6f1cebf6eed67bcb399a4e195af042c65e9887bc16aeb4154a44bd370affac98c05b590a4167046cbdc67e1d9bdf246b587c63010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4d4cd19b0c22a17d32256837f131f79abab7d5fdb17c209ab5c5e75e84c7836b711778aa32aed7672936b0f8f15c93ad2ba8197c6ab28777bb5710b4c927fd07	1639747507000000	1640352307000000	1703424307000000	1798032307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	253
\\x6e5a882954f690c40b2fdaf02387e5aac6e9d73e58e57ebc9732a9a56de7bbf89fdfc9067605a35bf288765299ab78f808c20b691051eac4252aaa858c598366	\\x00800003d765499c67427d37872c424f6eee185db25fe3d29c29bbfdcf0a3dc44da04eaa8b422f4c076b581e96f641ed5019e29acd675c3d707272a038a428e31623ae4132058c3445e20961d39e98dd3a4afbe3a84b023846513c8d3225b2af95e3d66b1a8265c957d05d53894ee937aba98e463c5071bee7d80a51bff2900104add27f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4164cc86de4d1eba90c0d53d7cf101c999efa01cb685f43d0af1f3773c8d8131150a41fbf919b0dbe14c41a1d0f80c9b11bfc4a5e1d590ffc0213fb71db7520d	1628262007000000	1628866807000000	1691938807000000	1786546807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	254
\\x71322db6a9295a22198efd36fd57495ac0b8411cfeba1e6bb253c48fd580733be06cd4c0aa261369569adff517068020fb6dcecbf6b8819735a904eb3daeb418	\\x00800003c71bacf06651172c9a0c8c00bcf0aca5de2a3773f7b1c5654a8abb8ffa572302b3d6d2becd2c5a38fc97de82450e7ac711463ebba4d8336f1bed4840fa10255910ed33bcef59ead8a4d5ee18ae99ee52b5bbdd3b456a686a6eb0355d2e2584429be2ebf6b1cec9c844dd52cf2349881a2d7e4e047d703c06849a8488caf7adbb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7d63a07e596fa48066d79fa700320b3bb299100e409eba8ebb22dff9a5bc151b78a030c481b01d76f43cac8c7c64c86cc09dfcfeede12364f82893b394e3af02	1633098007000000	1633702807000000	1696774807000000	1791382807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	255
\\x725a2ecbbdefb78deb868c33acc3dab412da1120c9a5f8e1b00cbd49bfdc44954886c7d1cdd607956918b973ae973d2467e73028e0dc9b24e573a06b33256a5d	\\x00800003b59b8418a4862ff1a8bab82fd73d6c0fca33705d613e2366864741ae2850aa9ee75212e8e4442c94aa890b6b46f3733ed0348b0772da48db16f6c9f113710af6b4c1c4022026967839d29bb08d332e211710635378387f7f2be711061881e0fe31135b034a30d22575c57b4f5fcb49d069b50501b43abee9ba8a632c6a85625d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7122cfc3238bb08e9b4201518a90d01e2a02702cbc99721c571b6412690149d3273f87a5f804c605cd6ec8cfbdade3ac18a74ecafad6ae6b1fc9d8d8d962810b	1616776507000000	1617381307000000	1680453307000000	1775061307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	256
\\x73a293d19e7e6291d2560603d7a6872a4bde0ff1b999cdfe37d93bd4b6f4049cfd7ed8ed4a76288631be4cc54d494c53231847e0f6721226e0479f3a24815ac6	\\x00800003b580835e161e9587968ebfc298a01c3b4449be3a5956096365815b8ffe26513cb17eebb9ebfb224ea3bfbb1cec167f825f04b0a27530c27ed023998d4bdb0e391e117da02f9891416783f315424e01ec9ea5e95d80a762e3209da50fec6b29537a606b885ee1f70551f01f41dcace04fb6b99bee8ecf598de527d9d058d561ab010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xcf489a0093f4ef1d7888deef183f81135ea2043063c3f2620eacef7d47d87967a378c94f4e91ef4d3f6e7831227b145cca02bd72b207b4c04e92039353b4f404	1614358507000000	1614963307000000	1678035307000000	1772643307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	257
\\x7466b1a2aa39e309e2d199dd6d88574ac89e27599811c57236d33818ff2d64f7fbf854b8a40a453f6ba5d97e132359f589860dfa202aa57e8b5e867723661e55	\\x00800003cf154200f3ea93cec7a293fd2830563283cfc3c1889c54bc9f081e251371b1c27f4ec8b92bb1fb37edf4dae6322dd1f1422256d8f2d2532be63781830d94047629e2fd66160465aa575b8cafa511e3c88dad338117b28110eb55082fabcf458d18d8c901395947cdaa172f32809472e7399ae78dc8c185197c1966e0bb1f1a99010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x12b836e679a7c3fac1ba45fb3565619c990162a8add51cb3fcfdeb568c4715938505dbb5295bed3b06f8d3947bf4af55e94fb58a118da2e533da5e0e7bd6e80b	1631284507000000	1631889307000000	1694961307000000	1789569307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x751e823a64907eefffec2166636bc3138f7185b2c80421180f8df3924c232ff19ac1d622a91701deba0076ed026aceefe9bde5c893e1763b92fbd938d732dbd8	\\x00800003f43c7dd4493d72eccfe63cf084fa9af383a27a1be8b2cd9acb49734fe32860749f09f8b88b9392020a83bb53f81828069ce8703a087cfe7b10b09fc89a0daf9c7c7da248bba36b3ca44abbba3c8038a200f6735dd3b5aad7393bb9dfafed466b5681ffa808dca6406a19aa9e7a5cf9b331f1bd53482a3a20ef3307c166deb9ad010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4eca655ecf8a592075290565da105166b6b8b6949ecd00c63fb92c21d1b4f44b0414e74e1c4cb4622c033d2130a399670a2b41de0ff81857ac53a051a1beb10b	1638538507000000	1639143307000000	1702215307000000	1796823307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x751ed0556566c85dcc3367ab48058b3f62814dbd0a96139a73773165a442e396c464fc03ba3afdf82720a495ee4cc3e33d425253fa0af8254e04cd3589925e8c	\\x00800003a905f4b302b72f69973573bc2f2e633995f933a0df07e3ae983d38c4f74ff45c5e2bdf41e0ca55aa02ea98cc69712f96fa72bff6ec7ee02ff7555a741fc9d2e2761a9e24a3c7c8a53f932acc5d370840441226ad4652d09fd4eebe4c1fd745ca7562e81c620930eb70175fbfa7db5db862372c9c08ac0d7701b295750d646eef010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc7e053e2a788b6b5ea91d1aca22efbe8de357b8dd88a5e0225b717c690d934f4aaabf16fd9c0b470396d4e67f14733588a0e787545c0b692e680f11912ccd50b	1638538507000000	1639143307000000	1702215307000000	1796823307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	260
\\x76ba478f11f0b565c72956e0b0c8537b21921badfc547af0907b772643779b220c765336337f52155d957e09e14cac63ae8fd077192c1f366d40c97cc9bd2772	\\x00800003cee9110543bf9a72b89f21ed7f3d1d559aa4af40b4a867bdfd33a5915a0e96ab582036460aefa07201d365aed8f5a020d45f207f9d195042011fe9eab10baf6e2843a9f96f941f1a1e85aa7bac5587f5b88b31e9636477818435bae95ea311a5a0c829d1890edaa1a3fae27608aef85ad269c7e20ef7a83fff428f6ce32f60dd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0aa844370b3f0d9aac5c619ddf9aaad4cd7ae074fc53e2de280fa34b7f9215e1eff6e5bdb395b5a77a670f498ac5190ef8c3f09f4b6041fc0f8407d99b6d230b	1614963007000000	1615567807000000	1678639807000000	1773247807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	261
\\x78faa52abd42f4bacee0a9b79fa2708fe9f809175c98fcd8e760225fc807238f409b1d81b475d33d1725e39b2799ecff589d6e1270b60220b1c94aad1d4e8b25	\\x00800003ba17d137dde54dd5fd087af910fe6092639b4a31db0f5004e42a9ead67e70b7ca9ae5360f25eb0a7264f2f5984396ab0e3b258eda2c333053019de65e963be8d8d8c312d378c471a5da7d2cfe75c1c13148c3fdfe55521634eae06c20ab2b999794264d99804f6ba793e8a52c0660f5a34985dc5c5d424c099eb67292a08dfe5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf4d1de0a2715b21e08fb205d60fb04a8b2d1c705c44674a51d7e9a844caf336f6066b158930ba6593bc947bcb07227a37efe01fa870c3d0ae58a3c50bc5cbd09	1614963007000000	1615567807000000	1678639807000000	1773247807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x79fe3ce43d4dc483ff65bc709f0c5e4ac1dccf731df9b5b07f36b996064ee4bba477ed4d9c172e13e73fab50b1b39578c1f1b7dbbecb03bb04ba1b7182a46127	\\x00800003d8d43f40224fa1c36316835040e75fba0158aa41fc148c7325607275e57de83e24205665f1eb1127fe83e1e23945ba375cabbf9d7c20cad8d2269d40fedbb0c8490136088f9d6a861f23aa6446e2e7be17c1efc14ced7c67cb6f4fe31d0a25caa954d404f74cb8dfbd30efac7782e5f2e56ef11e56d22d295c67d8428f0f9ff3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x53cc8a6a3547703cc382bce27151c6df6a3ca4461fc037e7b2d6f60c0d096c0bef233f6d9f121be232ce464575ba1b2b193c586293022718ae12c350cac74108	1630680007000000	1631284807000000	1694356807000000	1788964807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	263
\\x7966ca3dc5a421f3a49efc793ff05dfc861c5a7359c4ea28aefb87be25d49126ede46bdb78544dcbf5264af714624f94fc8e9c2aa86ee8fcd16cda7f9616f2fd	\\x00800003ad56654d29f2c8cec2c2d5957f91985cd5a51aabef7517aef9947659c0fbc24fd6eb9e6b8daf75a3b101eb6848479122c2b682b7059c07f6c74f93aba60abe68e05a062072957aacf149bf1c22dcbcaad9341a07275615439fc598795e7aa84310edb465f2ff6666163aa39c781e81ac4c4879adbc1bec25fa65ca4a79d526dd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x45bfe29109790687864c25a26cfa08c77f52ac6dde6d24480008c553c99166b7f143b675162da361be778d70d82c110837f8d9517e61c4154798398f0c26080f	1621612507000000	1622217307000000	1685289307000000	1779897307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	264
\\x7a926f3cd2214e764b5358d755830687fe8b00351c847c36211b8a01ca9b65baf2c72dc2833e0a4564dc6cf8dda73ab36d213ff52506392e97e2e45a4f69bb12	\\x00800003c3bfc8ec33e58f5b0e6356018bea0f6ea860269adcff11dca665c530d35145486e0abb08441ca10eceec6463265cedb83aadff97581238baaa8031611989f465c880302660d226baf2d58cd1b69f82186493270d8efd92f04e8c89418afa361225ae23588ee71b626a853c0393cffb3b1e2ecbfc7239ca64c150cc2986d2eab9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8d73e2377327061e30b326f76e83d1c47fa46582e5b67eca4e60efc4b4fd19e5302f9ebdb2474ede9de1b265526e62c08d4fdc755e776e5e81c38fca1288220f	1621008007000000	1621612807000000	1684684807000000	1779292807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x7b3aa8602731eac07a3cbad68b048b6c4a6e01e832ee3559379802bcc5d33bcbfeeed1eb85b54070c5ba876bda498f47ebe752f5c85336ef25a74dfc507b3397	\\x00800003d97fc8840973d640c580ed440b9659833efe7673c3b285b65f7d60d32c0bc29e3d55b501475192688f15fa5a8e9ef0d6c66eec499f52ba26ad51fee1bbbaed5f831f5306dcd217f46d257270ae22cbdbadc9a99d35a4c952116931c2f8978eba5396d1fee024dbfb6cca655aacf3ba968cbcfd23b5ca8434736f017a0523e683010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6d747ddb6435341a66dbe78a7aa40b5bbba42f2a5cb0298f75e0ed1e10359f21dec6763a6022f3fff29ad5b25b7412d8ac96209e617a5aef54ddcf550849ef08	1622821507000000	1623426307000000	1686498307000000	1781106307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	266
\\x7ef22d55723ca9eff4f857adf86a44f787b8dff39ab150e1ac55394994fc421f1a535ca08ad1ce8ffc79b62339c1513fd636f4bb921f1484e2a995bed83f2af7	\\x00800003b41b62ed5e7231c457893e02a47e0f80df4e170aca732479d60e37275caea4d213b259b9de0a4eec5ac307c75172eb15bc4b2c737f44bc8d26407f6b51e7d766925c228bee5cbc3c13b0fe7b5831c45028b7375d9c1502deab5a0b2beccf351989481ca4d819d7d6d2bdf01b557745a82bdb936ea806fee05501e97b29518557010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xdec7d52eab12d396b3206ac842d49cbcbfa860162e4a5a9ea22d6caa71c0327e73c04fb78e036b8cd3f526171d6b3fba1b2231a08d241e33969bff67e9cfcb02	1617985507000000	1618590307000000	1681662307000000	1776270307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	267
\\x80266f2256f6113615858216daf2947baf621d48d07e1898473fd864251a323bbb852c7ab6e19a932f3725fe0363dab16a241c89de750a41242c0bd78d78d00b	\\x008000039314b0d1a0d46a5665312cf362ad2994c876bdd7b7550b5f0253bdea76aabddbabefafe6d23653825e169a8a309947070a01f590305d2740a87925f2dc3795e2d90eb88906e85334ab3470f911201afa554b43f941cb62e6249da6b44351deed636510820b14c4160782c04213f264ea4e2951b7813d6d4653507cf2edd6b39d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8397113e17c50ff17ae9abe70e68a866858d49255472de65a9e02c768192ba0b6ff6c77b9331bcc956ec52979a84af00163bdab72d2c61396da20dd4bb761400	1637934007000000	1638538807000000	1701610807000000	1796218807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	268
\\x87cac398977f12c785108fddef61fece293ec5baaf43c08d7a973d8814b4ce22cb5fd8daaca446815f4898fb87c78758db30eb2317b2bea2c44be32b6eeaccdf	\\x00800003b0c96a58735d3543548b951eac88480405877864123ad01577a0e533da0fa4fbba64c146fac4a35fefdb9b7ffb670c2eee8d28b47204148c79850d6a5c9554db8e562c591d12083c330c7215f714f15f8d8f6e8b7b6f35c05280cf776ff5ee0a15fe90a0a5b90c64b1277f11534faedee4cecaa5187fdd07ec492b727d5be7f1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xea878f29c66495f4447474b1649586e88fd32f5d0c515510fc9920f1574993158913f2321852bf799c8446976a65fe01da3c272aa4ee9e33c6a128e4f464490e	1627053007000000	1627657807000000	1690729807000000	1785337807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	269
\\x8972d99eb622ebb2b7dabc9481dda335f21fd4efb0b4c69874b8847853866c1bdcd73a2e17297f42f4f80b630613e877e141db46048fd54d3234fe8f1847df6f	\\x00800003ae0ade3278c86d6eb611a8e18004544a8590f247262c6aa9eb7a32e5b5e7fed8a471c01a58a6514185b0b62b3413322a2b1967a709d7181a655f82fd40721ced4ad95afdfa94c9666d38f58b38440816d2aab3261201165bc7ab446392c634fc8a28df7b984f780aec234b75471e766a922af4899dfbd4694ecebdaa8ea19e2f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x54451d13190af7ca4281292d949047a5175e3740d6c494d88728bea3d61a78207a5e275f2c9e26aa78b7329d1902c896eb6fcd4fe4a6215fa35c4cadcfb72303	1634911507000000	1635516307000000	1698588307000000	1793196307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	270
\\x89cabcab9a8a5c39aa9620a07deaa453c5afb9635a17687993d691e355efa5605e70a39ad0bee2b9b186aaa7d6bef6f075bb5f0e26c930a991a32170a6f98713	\\x00800003c4d9b445cb7372e7ee14befba59371c36ce32bdf534af24a83d41d409df746f251dca132d655fc77026d30f6065d1a15ef84fe82afafc061f6145b9332e8e3300ad52762c9de3949ede573228bee8789096e463b1bf6fcc6a2bac7eeee186602d5b47be6b382bfc8db0a370944e1e80482d86acb036400e1e95b2f1476a6c653010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0e25eccc66651887b695cb4c2163144b123c3aac9731a910841c6267c552f2b35250b274c772ac19e71a8fb5ef9a19f92e807ecc08deb3e709743f069f221502	1630075507000000	1630680307000000	1693752307000000	1788360307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	271
\\x8a5ea9cc0a79ba71411a51f539f51de34e7e3357e3655207ace902a874f0e8802652b6d97f26728aa4307cb0d22c9ae691c10589048fcd17b5a33597c15a1e42	\\x00800003ce8db007c0c709866e9e8dc3047bfcfdc1b42df80a253012b81fdd50404ed12b9f3f07369c2b30ea59e57babfe58ae61fc33d4b4a92bfe0931d3b85d4a5b02419b93ebb5be7739d570a7c669b15a79ef9aa7146281b7f7544f9a2fece2af1a6fb2e9dcd6da47fdd07f8a443ac6a0b0d0dd432b07c3e06c16758d249e42e27b0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x209ff04c7f46f2d7ea973a073e6937d3ba626086b8ef789de6fa7f9c0d6c9c319941852e4ba8d392d919db801314345e78546aa049c02b5a89f3eec04371e70e	1619194507000000	1619799307000000	1682871307000000	1777479307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	272
\\x8bc62d3fbe1865884d95d7dbbd97b023cfb5028da450e4f2efc116ead1527bf803c5e395b203ea1b84112592f39ee89ed13ad18827c38ed568680163c69c998c	\\x00800003a20f292c14161d0ea5f9a91e9ae0639c3d3ce852a8b14650813ec59b3788fe351bab5a77276b31ba11aa78fd98c5db6bac092504ea41bfaf4ba0f6972fe487bb9d397a781049fdcd2801d3a4ffc643cadcc345c591bdea4a6cf7de351ee11109d820d2b9707ae70136c89e0b5f8261ef4852e74b6ae6375e1eeb7831e365a1ff010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x52622bc2dc5f5696135dfa5bda1cd363941d79fb9df36e1f890edcb556dfd2f082792445a32fa0cc91edb337d2284f362621e2a65bf5c8a263ae0b334a3b2605	1640956507000000	1641561307000000	1704633307000000	1799241307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	273
\\x8cde1d5c6c394bb15bd632374a6b905839582d0ffe60e11b276b282f00a7389fe5ee8dbc11dfc468493fd32679338723cc93d6879c5b335163248c0d4de54802	\\x00800003c83228f54a33a1bfbbb017d1eee9bfde716ae1087782b0e5ed353a6ba919f433cdf8716a93bb817753b0f6624068825a845ec56c005fd48259e1a84f733d3b2115a405097308334bf73136373000bd50b392964a40a647ceb4f3abec0988e986be689002c04da4a45ba911c196f63f02d5577d5961745afa311a3262859a1241010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x285d1319c14629bf8984094531c26d2ff364ee06ef81afac9f91fe9da01acd0854148afbdbc354b1ead0a3cd142f978ec782a3c17ce91dae684c0220d5b4f60f	1627657507000000	1628262307000000	1691334307000000	1785942307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	274
\\x8cfe42bcad11b4f5afec26b4069113605439adee81032a0af23697640640aad53cad97267aeb4546c7e1ab717b1c28ec190b935ec28aa3d6560f0db995feeb0b	\\x00800003d5f66731a1807675af912fd1f57a324aadf472f65480f5c9ac78554875c9de8e6c314bc892532d2ada6b75bc0c91fbe4124d877c3dd0c0afa6f73fd7a516b1c8c32d9e14ecddf997294f26744b29c49835c18764df94a0181e94ba5cb8255790763c684aac1642de4ebe11d90371403531960675f31faff195ddae0d965d54ab010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa066f934ffc7d244b241a2f71462a306730758c10a4370740268d3aa8fcde52eecbd19574533c731fd5c3bb6e44a9ce00a5725298fcc6d10b67408c88a716a00	1625844007000000	1626448807000000	1689520807000000	1784128807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	275
\\x8dbe7083edb97a610480750bcce28ade1af3dff0dfe278219221faf8c5abd0c89be4bba0521ee9afe0b2508687b04ee073b3bea5ae3e0a2515e73e9ba80613cd	\\x00800003d0b689f9d01dda3b48b9eff6e1e1fea139358d015c177e2a03a5694f660a93b01c7c27a7e0f147f278f03d58e9362f667b1a2be6654513e86ae4a7aee178e885684c877693d192f0190a894091a85ef8c56edd6ff2e9d2a7f3426d16260d76eb90249a86e1470ba55998e80c970c543a3bb877e73b16e454187a524e800cede1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8a9f2913ff855fd58e31665fe00089b5c11ec3a69aa3285c384410708a2a057944540e5e56ebf8b0f7298c46ab12531312353a413a7fa8833650170a10af2108	1634911507000000	1635516307000000	1698588307000000	1793196307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	276
\\x91eee84a79674d4fdc5c26e0bfa3cd6caf5d2eadb1d05242c535b40378f6d55e2f4208c9db78898ab4489a57adaebb23c28bb81a11ef6331ac14093642872ca1	\\x00800003b3c6d7cd827a33eeeb1e7e556e61e5089bb6e1431f68b2a82c5f7fd82886b82e84de53b80373e76bb62df7098ea47e51f121ae8d386c82ac8a5383c862c35f08bef67c26852e1ded981e5a5028334da6314c6ff3489a1125bd2a1bf6732f8c8081533b6d47ce6fc9cf0fcb83e1fd728e62309e90078569d4e0b17ef690945bff010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe045a4b6516aadd99980374b865ec896d02ba9fe0ea15e65f347431d2af80fab27398550181f7f04402862f361b38ce278fe0b9aa8abd05c1605b3b4b8a10600	1618590007000000	1619194807000000	1682266807000000	1776874807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	277
\\x9646700692f44a431dec0ae69dd04601486745ce162361ba0f7be39719e43ff3e8cdc38d434a034c89ea33ba73cbb226d99de7b71cb42b32d663d563507edb1b	\\x00800003adda034e04a195544b21958c397ee20307665cf33f2a96d90f64dbfdbc2e19906529ac47bbb53813adcae72d34faee6dd017f1d5b6346657d6db40755f5caa281d5463a59abc3813895f40ffa8c4982335a10aaad275f5adb7de2b279c1b4e15a173d22608d6a3c153e8f14ece4b99cc2f0d3d559122c399bff7338fc9344249010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xce46a2f24b496bd714065646397b0162f5c24855e90c60afd3b755eafc79b4a1381873d5bc839ba8659c0f9f4d3315a1a20a74dbcac7b4cf1d13d4c09d30d00e	1637329507000000	1637934307000000	1701006307000000	1795614307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	278
\\x96c21f85f4977c862139499a17c9d6aef2a91fcd05f325b95aefc002f9042635a20f885497564cc3ab776f90103a5eccbf6f51142dbacbd0eb6d6de0345ab694	\\x00800003c2705920bb63c7817f31d683fe038783c6cc122dc4ff8fef215b5835addab658b3e757ae5b98149201ebe03c161d4a2bbc77cacd1a5ac1f09f9902cd1890f78c44104b9f29860ce03b00c916049ec6e46d8b0631692eb71ffe6f21f20a9547374e4e3dcfa3eb8389bb2293d34cbf4b5882268db40c9385f7fc3e4a20c9e86a81010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbeeb17ed019664089148a1fdebdcca276c8936d1bd538007519f2f37f0438d935321115f62b511931771ba62706c007ae86c09de6647bef2c456776801792c0f	1612545007000000	1613149807000000	1676221807000000	1770829807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	279
\\x99066c0b7bbbe30bd91bd1ef453cf12dc3d2bd5e49a2e7383fc1c38e9a80aeeb1253f46abf2a446d24924f165a6beabd4e0a257f0150f4ec447532bf1e440f66	\\x00800003ea40cf4fb2b4e2cac6c8bad6710fbcd55e0829054dfce1bbca77d389a11297efc5a821436f12401572124393c2d354e871bb45130bc6e5b6486516b34d48726dee63b4d0102d11a26cba95ce9038528321a368b26f69a05c315db5b30f9c24a14318a404a6618b8004cec6ecb349f8331919a40a34b793a6f05861e71564d0f5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbe416b296bc2b02e2876e857a9e2fae2824d9c52808bf3462e8515a0ee2548639f57aecdc8c43e44518588415b3c86353991296c22713f0ebe7f727ad339d604	1621612507000000	1622217307000000	1685289307000000	1779897307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	280
\\x9bc667b6297c3c88644c942e88f7223c9978f3cd9f1518dad2041a74e6e420c22ad7a78045baa81712c4a17579d9bbccc174da22ac0c88caf8b832cdc78b8d41	\\x00800003c3c10e7ba4e50483843691ab4e900e3d9f6cec6bb240cc35e5fa844a2cae09cabf4a02ab94356f3c7e887b7b03ead55d6d9328fbe72074587bb82effa9f120b6ef2212ebcbaf4b1ae7a7fece3b1dcc2268df64af7858cb235f176723f28cf520e89cab11b0f5159058d1d47da19d7c07c328d85dca5fc99a203818a2829e786b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x34c4ab7df1889409097b6088b81fe0d227a79b035acd11f168ccaffb225ce134355fbb69f81df3a1e5a706a3f056d6b0a05d949ef6787e4ebb092b2e5ab05508	1628866507000000	1629471307000000	1692543307000000	1787151307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	281
\\xa0daa3ae9fa216e155782adc9112606d464b271f0f2e73b8911bc5dff57c46404294d3faada3694bcef17d3095093b2546c8b255cd6d4ab8ddf2aab946d13aad	\\x00800003e172b21c2521d06fec2137e9382f2014361376715a13f12fe6befb28f4c1b49442a4303b969018985d86e2114741b07fefc47842902859fbe7e5e8f7c1e0bade5e3e0de30a1c8d3cd5c3d388f4dc3c8ef6ba90b321f8d3493b10214e08ee475c3dca3ca4a8bceeda222b977171e6087d57ee8ffaa2efb7df9124030a653649d3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb5c5f273fdf68d56d1cab7f74bbe146b32990fb68238d6c8705c95fa4a125b53873c613f1f03e2f295c766e8309fe4ecb2b5224c2e9155eab6c46f02b0d4ef08	1619194507000000	1619799307000000	1682871307000000	1777479307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	282
\\xa4e2c1f721a0f4616bbe965a84b63e4af876422cba4276f8e7fd3723af1bf88148054184a3218c335c1ab9869ce3de3b7380e17e1f3d141e40f81861920bcb74	\\x00800003ad3a917f5a275b44a9b80c99e7a37a4b81775d02dc0a042b6c5d8015f3076ceb5309a88688f4337c00789d4be6940919ac3ca15293f73fbf68a2d28f7e24aaafb0d190e149205b2cf07d9acf5912caa9e2195b63f9f0f840f8517bf4559dd3c7d3efcc97924fc47e93a3ac4cd85f9cce2b2e6dae38583a299eb7cff7c4e91f49010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xab64f124debfaf63af617f8a61bea42020abe1209a59316a7c93e994229d1b614ad0c01794ac0415b644643ce9a9429d6e2ea8e95ecc6d9f2334c4e098c8f005	1614358507000000	1614963307000000	1678035307000000	1772643307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	283
\\xa5ae8bbd84b3ace6b88184bc3a7c8f7a76646745d677bbe747bbd3299277e59d79f27bce38e5560c2ebdede34c13c60400d761ab97eb7c71082e6beed69c1b75	\\x00800003c712cc779e204545679759b57e8f38d36e789636b3aeb0400dc1fce6b08f9b7e64ad58211a546dc06eea63bbb9b59058b35369baae09466cc48b10cc35952051da11a04eee97d978ebe4119f33ebc76746d141879dceeca5c6954eeb83782b8c814c83c3014907b527e61c57ba5d68d9a67283f385f08d41ab12b6830045eb57010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe89d1daba1dc0a9930648a984f1b66ac8c2e376c3e852a718691c51e31dfe8f2afda2a7e7b8e1992f94e9637ef9ce51721b876d1f6f89f3e6f145e11b2597c03	1610731507000000	1611336307000000	1674408307000000	1769016307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	284
\\xa6aa865d2551694462d9ebf1fda929eee66dce4660a1d517e22874d6c576dd8cd672ee9993cbf5dafcafdaba51f663d867aaeed9965b0d5f6498bec2d7c1055f	\\x00800003c8f2558654612188185d326e563650bd4ef788ad5a4591cb2ae9bfdebee1e8bb820c94123867f6078abfe9f22d3d22be233aaac068fb6bfa0bed8d3d1663400d9d7730de9fcb4b9e9261c78a87ba6c1d7efc6bc099e06a702f27f0d9619db7fad1c89c539a1135592acc350a898f44f855bc3b2686311a75f92373f4ae1a6915010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7f30571211ba92c65dd765139e03307499eb7dc0de2f3cd19b367b8b320ad8b3be8c80e8dbf8444f8e862119cab99e8537e3b98e7903aab2ad0efb14eb091d08	1633702507000000	1634307307000000	1697379307000000	1791987307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	285
\\xa7da6d91e7f8009d272cdc88c484f4835cd490fd50cc9af596eb465a09aded5847c8370e9180109bc08436687140da6153c311cbb970801633d35a2284af545f	\\x00800003c73112650d611478bebb9203e31bb0ed69249451da19a3dec03185200d446f5f39bfcd8bcf2bb38df4fdab94df82bbe29c0545fc926ab4a1a8b8a2e281431b62244d53fa19daa6aa4981ae98ebea4f9d9cdc3b095f7ffe6294b0e1e29ef2404ad959443a44e11a8dd8f63fff2a10f7ad1522ae3bad1362a9c531dcda626684e9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe33864a8e74c877e1ea8f9b43347e4400e8194c1065a46a1f66d2c7b98f5af7bd474f81e028be409603459bf543e5cd14f5add9e29ec7e79f6916a5fa5c0e700	1612545007000000	1613149807000000	1676221807000000	1770829807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	286
\\xa962994536975f5420ad3894046269a3dff9b144925712593ca74d915e8f817e8dc9ad3aaaafaf7fd07232a3eec6125335c339424a1ad857b8bac67bad6192ce	\\x00800003d32a19222bd39c30e48d7e1593b99fb2b22be3c174d836fe7bc31ead323497bab81a73b0fdbfb2a1768038b5718b7adda437a29b8b42d5704d6de3d8ec1743cfff6dde1f54966414c07c2c43c967b36b3ba16c94859cb031396cdae19298ec6267f09a91c9308f67732f35e890377bef09f1121c62f9254cd5292b3a12776d43010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x18a69c899edbdf3062365c08de5ddcbfdb8bb73a60e79292a9aa44f101d76d248524735e1daca7469462d8b5d46e9ee685899c818c68dc2810d1547399f7d40c	1639143007000000	1639747807000000	1702819807000000	1797427807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	287
\\xabea14cc1346509ce2befbef3fedcd0baadced8751d37e0aea5ac7fb57d52a88961ddbc505362ce996be4b20f376ad9f443b479fd5d0b22bf56041611ef72ad0	\\x00800003c7c131240afeee26bdd762de4041b92ca7ebb79db2f8cf4aa7fea249e8d797aa960154cf61fdab3e4aef4e9cb57f6d254440514257eac2b51ccabe639db777e112662494cd1fbd7db63d83002bc1f99e718f4719c4f077c659d89512ada0fe48ef27ad05f57111f4c0d0dbd1a6b401edfb64ca35b5f380056216631bafd40e0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9d7d4548bd317a9c6d48a77a130416378959f9b8a84c1895a0786ac3674b286136849ae22a573ae3469a20a6980a9518e3fc0d0cedac2f0a9f9e264e87ac950c	1634307007000000	1634911807000000	1697983807000000	1792591807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	288
\\xab6663b8b502aa6fe7fb6bbd104ce64ca7f16d5ec88bb68ede9089393453085e0915a635eb5ed5d8683c65c1b7d28ca23a7075e87959b28dfe069b3925cbf723	\\x00800003f7af6b345503e3989728bc6012ad3db8d4802db7cc506fd8078451498d74983209e3118d18d51eda8ee91b95332c4ca7757cb0d05517707c2e5456687b78f4c3fe2651de3cd80be38cd39c151c4a6605f1bbbcea331216552f134179898c591e459c143f381e683ac19539130075540da2fc7e9f4e4bc6e96e56d137bb9970b3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x09a2dc366d18fdc25bfdbeb3c611746317097e1c45c979038d0be895e75a5319e75e97a959b2b9ab969314552f6ba7d8d2c2a7b9a6ded6f201f493db34f14e02	1625239507000000	1625844307000000	1688916307000000	1783524307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	289
\\xac5647f455993588124593ef9238b1406120496c79224145ab86412b16537e709140daba7a1338b703b38281d9446924fe420e204fa0287be8bb8d8f400cc847	\\x00800003cae6bdd99b2bdeb348ba6aaa267899a59739fcc49b279384e2865837b54fae52f716232fe2ade61a0d8de44c56725daa803ed1ca68ba3b9bcc6c542f3814a936cbbb421c95490ab8fc92645a7e02913d60e7f4b5739da2e9417023e65ce680d6e0169630c6585c551bb570e4fb0c6257849515efc24e6380adc4315b82161415010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2803f6ddb17653c8cb3e2333f47dfa35a4c33d94b51294cbe7361d702946bf1a1e229dcc56666124e78642218d4655d6d6000f229cd99e2521e1e6c9dfc66f0c	1636120507000000	1636725307000000	1699797307000000	1794405307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xb0f65d6021ef9faa0560d5b7747c08e035aa5de5c2ae5bcb0140dc298696c415a688471c33935c19b100fdcd4502a1a9d0d48faf2c51b704a784a6359aa6730d	\\x00800003c18b04c9926423b1b98c00cbf8f4af85dfc89f9e4de22e30a31047995fd01c10210ba619b2c0ade15528163418bde48770314003289ec18958ada61fdbadd6963d415b161b8c1788c4c3ab2585a0f186555691b06cd7940b093dfeb96f79dc95a0503bca7b4e641d38444ca61665dd26f46bebd08eb4ad7882d5414ae4ef1153010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6650ced2bc1428eaef60531ab427755d1e3fba78409dd99dff4509ab7c923a56ea29ef456b462c7a24770deee4b07bf7a53044a337c2abc01ff129251a22f60c	1619194507000000	1619799307000000	1682871307000000	1777479307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	291
\\xb1465aa4aa19581381be46a75ca74f25399421d2a5fd72a6a18168af163c5986e9194faf9d1325a215c88addc97a179fde591bf2179dc06d284c6c6a8b4fc7d8	\\x008000039b0b7fe549cba7bc0e41ce5894f8148ad72faa9d0876237b12273e8b2fe83ccaafdad53bc326e6ba82270a8bc4d5b00295d0d66dc405fe8f2d5a0f5e9ac193bc8011ed58b78f00888b72ace24e03d4265305f676889c3cb4db9d205847a337693142d32d0eae03955ce8a15f03f0c4b49a39da8f3b2b2f045a0245b451376cef010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb8e35a76ebf6a0ae6319c08df6e1b1c67d14cdf33feb54e4dffe5bc2d7b361c48c3da5e44d61502910eb0bdc874e6fe51f325901b35055f0487b94b75274480e	1635516007000000	1636120807000000	1699192807000000	1793800807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	292
\\xb2da35ef0deddeb95559d9be1fe1e9b2fd28a29bd9160ecfe3acf82678c3fa9b70a4c41a699a7f8e1cc9aae654bbd63eedc54f3020bd2bd3865c385e151f1ee8	\\x00800003f90d9b518caddc3e4ee89d6191895dd47f27849aa57c8376ddd40ec5a353828692ef9dc036d23ebd035ab7dc8c1c28935357aeccebbda2d157ef243495a8837213cc57b52048111875182b4a8f3261635896c348462131a95cf7e2c575dde91e0b06b3b8762cd4a1e789328b5f399d817b251c6fa60abfb5031bc637d75d304f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3584328424a745dc56a019d659abc743bf4175dcc8ae7e447bcc62ec17ed260e95a19888f8db87baa4db3863981b6f06d5d8724d2914ef39fee675990b0c0904	1641561007000000	1642165807000000	1705237807000000	1799845807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xb8deb47db48ece5bf3097b228a6ca5089bd187dd8d72dde10b419b4fd5c7a367f710b1b629d83187e5d21cb6ff09acbb7e54884a96253d4f23009cd41b920477	\\x00800003e0ff2edbd76af7a6e805b290fc9dc6c888b5a32c909b6442eeb43be54476eaa3b7014ad2233a4ba14353ca74ad0de847070dd8e3487ee573320a62d2159bfd0a35184a2bf0d59c916b5178976403a71b040b8cbdb6407de226695b435018e293d9d491cefcac3935cdbe42a0d337cabb1295bc801aeb6ffbb3930af152518ce1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa585ff33595cdf813fc43624e825681373781d57163c0ec95e3d8a3cdebc7b91d899cec01f1e22580eaebee139bdd5c67f81e08a10b2a27e63b68d43bf25cc09	1621612507000000	1622217307000000	1685289307000000	1779897307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xb9360cf61a0dea1fffc614a9af9aaf8bb0080fa55c98d17a0bc8be479d5e11c2c15137be1121d847cab402d10e3d3277e73f5c0e57f82f21989cc2cdfd7f813a	\\x00800003f21e908855a479e28efad902583df02903622da6cf419cb88d4316e5bd12827c466d8a514fed9ced628626d99e9fe8f7d589bf6936fa1aa3e431dc87ce4fab78d4c678369ab3d148579405e8a32321312fc09a0b919826fb06caa720c250029511316f584587f46d4d26afb631205a1942094dc5c88b31ddcc7ec076eca7ba6d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd9c1ae4c50276551e6ce05c64f4e56d77e08ed31cb40d50995d82a5364cf132a9464f9da07da2e6b3be60c503a11e7bd28c3e99e1b23626fcdc904225bdc860f	1617381007000000	1617985807000000	1681057807000000	1775665807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	295
\\xbfa65897bfac2f32d87476045e9f842d6c5b1aa5d12821dbcf718329f51d9df2b5746b5f00a3b886739b95bdbdf562b4ea8c9bd765ae8ec47a9c3a418c6315ec	\\x00800003cf7a3983d740008b4ff6dac0282ea526d3ce098e93d0da8022a2984c5be17119d7686defdd40d3fe0b73e19d023fc0e695edc58ddab59320f09d7c68a6b5f1fd126e9cd1990eebfcc9cf8791805c726a2c2cc85d2685ea2a1ba5e76fe544f8cb6f2a70111750d20fc333a2bb45a4e141229be7ff6c9df1786289abf48e6461b7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe81423044faad9082f0d403448235508b7341359161042b33d457b2a0e2b53329a41de996b3c230901bc14f112c30019b4c9a62203762baafb6b50ccbf0eb109	1618590007000000	1619194807000000	1682266807000000	1776874807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	296
\\xc012bd7db538ac6b5a86f1ba9e7082c6cbd8d2a33017bb1919b8c2a3bd2c7f600e779d1588d4cbaeff0aff4c3311815ad8b3257e611925db17d572fa9276fbad	\\x00800003bafc0cdacb17c0967a828215161fd08c94abed539075367bdc9dad391887d614bea38700e6f139bc2b3130be769971bc98b08979b277b9c79bb2dfa4ddb7685d570582bdc36e64594752258939189c7831feb765ad5ac2f396c16408202fc4c55d03ac4294c1c461dca9a237272ce4843ad5b7d826240704b8301ee1dab95d47010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x603b609229aa915e6b356e66bc9ae94843c250c928f66837aca5d2761b9e82fe81a124ea4cf3ffa1e028da37d8fa6e7b0dc0abca7e353ff43e822f0d94deb402	1640956507000000	1641561307000000	1704633307000000	1799241307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	297
\\xc672bddfa9a261ebae013a168049eeb53afb5438232aacde0f05734bae5141892baac4093733b4664586773df1a70675e6052b53a08a8430ed9fe6c9e4253056	\\x00800003bc7ccade1a665c0a7be646d51eef4f22cb379c31bbd986ad7c60f8bc5423849d5f39a7e954b1dbd43f9ae90f86c3231f8975b5af6260ab6342ca4c1d62956b5bf459e1933a51abf2edca6c573812e090f09775f1e704a3784ea0d4165763657b84f2d82d8244a9804552b3cea7cfa429a7f3d01586d8bcbefb13a76694590d0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0ed67ff8af1122f6e78779a4267c82b6765c478fb3eb8db86cae699fafd664102eff093965edb966838c46b5974be2fdd72fe66cab07cde256f701fe5a9cc103	1617985507000000	1618590307000000	1681662307000000	1776270307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	298
\\xc8cad57e7d09f060e83b8e2de55c52d1c2e89c8f8a9228242a3eca54cd04d2e0c1f8c73e006c398ca5f8bc6697c5444ce2c6030c9b4b3b62fc8ac8372db3bbd0	\\x00800003c7b7aea9b89c45f599f55ff78d76a8ca18d685c427bbc635f5cce22179cad18a712eae4efa79a8055d799a7b5e1b92d30b709deb274d85f4706c86aafed82304f1ff5481755bbeb39856ff1435f9a98bef5cc4335b10ebf5a7a6a8006db7711f74226ed597c4f4a84cdfb3983e6f95cc68034d4133f0646156b4f1f2795fdfb1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe8fc2f23d643a7be66d6298d31ee5ee3aec4d967c55b30f91aa62f4db2b022959161d848341051f53dff0fd5375cf18b1a9b035f60cf2dc4e6678750fb0fdf0b	1638538507000000	1639143307000000	1702215307000000	1796823307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	299
\\xcb324203af8a2114f578fced46133e62b401ceb1e047828a1cb256996e754f54c995068cb0bb07c7ce6e9b7bc6b3c0b051e0d61ae725e0d606ef76a2fa450fe5	\\x00800003bc080d3c1f37b8803d3005ed0d82d89a93fa697f9b147f8eafe5a6ec6646da8f2840423b281bcc40f0ead9787ce5b1c59282d459f6ac0080c9ebf2dc00ed2ebc26657675cf0938f605066c61727b837ee5727da2782a3b6593307c5b88d70aee4f3f9f06df74108fc133ddc26f695f547991c42ea3d5f4d4ab0d363e7bfefe3b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf2af3d1443913fb6fe47656c3af1169b1ad3c20a78cd59c7a952e6c3182de5476475caa0dd378fe90c7fa7c578f407faa4190c0686b702c271f459309f39c109	1641561007000000	1642165807000000	1705237807000000	1799845807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	300
\\xce3a2c258a807bdadd10bdc6c16ff8763ef6b736b3a22f3ac9a0e0e39720d5fa027875bfb6bc2247fcda0a9084cac9dcb224349ce3a5077d5d39bd96afe5de87	\\x00800003bfab94c6fc48fb2df0212a2f26c7a7ba26c9e607a1d570094ac9c0bbe2d8baaf2624fcf14e1dd471df0f1780eb19245ef8ee79379ab3b3364a9fdf69e79102dc7469d7af102128e263cc27144dfeebafbb3a9f79e425955f3d18df75c412edce85161565c8ad21982f2c701cc727656d1a94d93eaf0a730f17a7dcc2dea42375010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x262be26ea8d4adaf13924ce7ba093fdfc4e76a84346a727ac963c8aaff31e32e8572178d23f036d9296d53f9a95c49b8bfae6fd24086e33c9b427a9926fbac02	1629471007000000	1630075807000000	1693147807000000	1787755807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xcef2ff69a75edd43e734a3df11b8c0ee6dfa4f269a011abf43712368383fcdaadff1b96d25922975dae3d7a32bbc75ad23a27295ac303274bbe6632f3d71a048	\\x00800003dad66df0e52e89051027ea82538e02e206c7f6710ae58d5f094693b881fde2fe8746e6804e867bdfcb6efe09d38db722045d07b1579c9c275f18905d5f5e18666c5b2d911023e657d59a802732532b10431527d38410271931945b1800ab2b202356c3b7a07149bf33a2561ab28397b6c6b0bb5facac838f2e0fc770896b69ed010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x64b10d138972869035681155636b9ed838fee82bece74877b8b4f85d98c654fc951a984b4718ee19ccdcf8825187611447df5ba9db5039ffb3498c8814b8af0f	1622217007000000	1622821807000000	1685893807000000	1780501807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	302
\\xd1ae616fbce3d2900c972ce33acbe3a7fbf174fa5a9160a51b8e55729d094f2a8294e154cd249fd369603d09596b259f87086a84bd86d5b57b6971c33b90d354	\\x00800003bda429cfd7f85b2f7ca95c1ee0ad29701733651ce006f2ad5381c9d4d070aab67ba522fc54b73615e23092f32a13c77f8e68a64510bd82997fedd2d4cc3da61cd0c823db2235f37ae64c2939f726ee0bff4c14d5d8c32306f4de5f602fa50776ca44fe84224bf198fc5d2473c31d5be59a98784a2fefcdc4745d7714175d0e69010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe989553fb4ebbb9ad1dff798d4de3fb6bb21e95e689ed12ed73512e61e8279a0afee75689449669207bf4e0f9c28fb390786dc9d6547daa7851a0c2b81f43d02	1616776507000000	1617381307000000	1680453307000000	1775061307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	303
\\xd53e40950d224cb50f6ec62a6dabb5229ce00a8da4d7c72428ba921a077572571bb6f3273183aa7b5fc74b609e52cb46b2a33bd06698b86bdce255b4fe7f3d98	\\x00800003c5170c5ee7051b647b1a20369a5b3c4f00292cf734c75c831fa011f2abf134118be803d7a9e95b20b12587a63947d5f63bf2e005aa6af422c078bcb6fbb4ab69e36d6451eeb5b2778c06f12a42250e4c80b03fd36123644e7f589c9646b49dbb24c358532c2f43842a02c832210645c5cca8861813872a60f28e756b32ad56fb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9cd7a51659f7d69b4e420c7590fa3af36db4af9d78a4681e59b47026db77acea44c180c185eb30313aa52b8c27bf0280209a386f866f76d68474e3693e17e30e	1612545007000000	1613149807000000	1676221807000000	1770829807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	304
\\xd7bece4c2bcdbbf6f1e3f3f4ef69d5cfa5e771764973b9f6bd80280612fda52b6ef8e440c499f8ebe9a5ba03cf518c19e1a883a7b2ab49690e7657cf7e641c8e	\\x00800003cc86a9436be4d426135b6ae153c47a4265e9025d9fee2fd3841bc33016635ab18b23d998ee6044d0db1b327f4a1e95b6abcdd64448179be65b1b0ed34df0d3789b56af698f2d7f67fdbaeaecb79a1f259f565040a4fbbeca278781ad3e07fcb1003742ee1e06ac7e5a24b167abd31171384e3a5f4619d4a9cee8a9e8c13bd77d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf7b78aa4cea43393da1b4196cff1b9b17352151e6fa16722bd2613c7bfbd28556912ac9b79353928a996d3d8cf55ae06712033b2be7d760a29d0016bea228e08	1623426007000000	1624030807000000	1687102807000000	1781710807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xd7061e38b524a8f463cb868f49245de848a9fa48941f6458506fa54f4a61002f210043fae0d1bd59e21eb02f8ff02a17e2605619b993377fa6dc5297a6212df6	\\x00800003daff83e1a6057ef2328e0356d031d81752649a7caf0f350b426e5e4cb83eb97d6735fd12d333de765faa30f7abbf313a36a856acbe4852ecee4f06ce9d8a80a769e40809532353cac49ac4b266c1ebda9dd7bec2333f977fb780a85f526ae11e0806d7c7fd294c6746844fa6b847083af217bf532b18fbb30b226244d8b1b941010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3c5ab83178843533567805244a82c7213833e82366d3b3a823dd393cc1f1ae81f81aa34d2ec3a1ec1bebc98d139fbb24f44da103c0202d168a21b10b930f310f	1610731507000000	1611336307000000	1674408307000000	1769016307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	306
\\xdcbeabad73470e830953ac0431ac9e177eaa43b42fcdcebbe26ee94aa3bec59fc20ed4eccf746abf89c5977f5377a7c4cff95d44934846020531fc581c025133	\\x00800003c1cb48961468462e7fce6fe4b4d964ee16579676ec731734afe7e01499419a36290060d3d7d083b6c9b59df3b92cde3e9cb536a4f8ea6326f1983a4e7ebc30e2a686a8118f68e52b7ba977a15cedc768bc9917b4f476f009e3f61cd2eb2a0a14d03d5f15f5b4e78479a1f1a49a934988be7ff03c9dd3654204d71f9be992719d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x511223a2bff1fe9f4de12abd29029af637ee6328703d18a519c4bde94a196ef77508066b1a09ff5c6c74f146d39e92429a7c62f714d1950840648a809558a500	1621612507000000	1622217307000000	1685289307000000	1779897307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xdd2ab2010f6c73057440c63e4518f6b37363f8f831d3cc3ff36838973033a1e660b096c0d55fe08089cb6c0523c20aca990e787fa6923f5550d86e273fd99faa	\\x00800003d9ede9e2c5003e8a2f8383b4c84d173b362e84038ee0678cff7cace7880880b4638fae06574e04bde4a943313966f92e470e1f33b97809f461cf56b5bec0731210d1c2adb6b593a11a307c98caee1b42a3fa2601d27a41e8954a83692ce0d9447a1397f382f696d7d578dad03a21a024f1f5eb4da0ed615afd1d0928864a20fd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x235ff1cc0cef55c495cf71d59bc32d60e2949e459256ab2a73827836a860c934de7f74b2d56c80c6fda9bac4dca961099f03ac98a425b22fbe8d80556c2c850c	1627657507000000	1628262307000000	1691334307000000	1785942307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	308
\\xdd5208a7c08b685277c519f3407e3c2d9fbb371bf976f01bc83ca9c7bde2cf061a1810f42624285c79cfbcbff455dce3cb54e6bc17506a40d59816b19b786e86	\\x00800003db7f81efca324617cc429fd94646956109c05ee7c23338a4c779a8826e46d7cea369fe01ee6477011becfd7ed5cce63a589f75127794a437a328548f915ce10a02ac5fb839d40a7959125ce70100a5f6dbf027f7a344d0626519ac25a5d9e445e17e05d611a218cc6ba797aefa92229b2f9a175be64380325655db110c310d0b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8e73f1f8c9586f09316bdcf34e845d695b3e44ec99d59b363a5f787d4830044c870c16b81d65d3fc4fcf7050a494bc9302e2b376d2205571af80b6b384863a00	1641561007000000	1642165807000000	1705237807000000	1799845807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	309
\\xe1e617307788d87246cd79486c9f8e3e91b3b2606cf6f7dda92498522c33b33b2308d783914cc6ad67462f45a32d4cb163cdb265e3ca9976f3401d1e1149fc38	\\x00800003e88a8b450ebdf05260eca2e890a4b94bab5305cd03ced3f21e132fc9406610ca592e559f7d14dc60d1d25dbcf78b48aa79f2a7680fe4002909e3cbcd5705c5da58aa7c4abaa2b12081651444f5d3358e1514e42c826ae6ba9b489c846dc24360f37e4ebc9a8fdb59b2c8d9073abc1562a1d153ffe6b1b60ffbfdb393b29b70a9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xff23705ea771d1adcc8f52c9e3d822ef8348dd825ff1bc24a9b781b737d199052613724cbd8af6e12f4333215077b7af97c35b14ae346d9be486cd3c06b4a302	1613754007000000	1614358807000000	1677430807000000	1772038807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	310
\\xe29ee3a79d2c8e5e48fd115184bfe6332341c76bfe7e609e87c05e3cebd3b8b6544f5770d7c2c40e11d9c5fd12b764e56012174cb718d5f6dbfae0e26d006beb	\\x00800003da26e13956fd35009c3c0ce787379ac89893c5b3dcfcb2a0c4602630bd4e635af263cbfb93f3c4e3081a43f9ef813161da9c7ec6cb684331e30d4f36120a81add409bce433864798b2406b4a0f4e9c9095b48972bd359d8f50a4106ff251e17edde737f1f1669973c1c8aab9dc1cda5673876230635e67efd6c535ce199e753d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4753a2a8943512ec728c2f3280a6bc371d28160fba045d0c40255faa8d71c318df2a080c201cf9cc8f87fbb9235cc4e0fda1899d13108e29e36acfc10b416100	1615567507000000	1616172307000000	1679244307000000	1773852307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	311
\\xe2ea336c385b3ba1fc3222c19d3db086479ef020d5d2b347c60bcba30ceb8b7063384a2662a7c1f3baa35a7d9bbae23b744bb3323db65131f7fec14008aeb286	\\x00800003c227ef6c8f6b70a68d241cad1e3ff5d7a563631ab2f59023bb1058c57291794124ea062a3501c9dba07e4d58d00cbaef6ee6b1dd9591f3060dd4da8c770390f589c5e63add4abe019a70e3f0bbb624b759876e541382ec7304d0be88c6af1a647788937b1ed1bf2279b36da89cb634ddbf28e39080d0cfc536d63a45d812ee01010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1924c4df10c8f42a4540f237f7ca06d1179185496adeb55a2bde2043b6c8e37a3ef84bca4cb4ef3eaed8aa779b16e0e1ebe0fc2c63da0b8c024ed5c591d53900	1630680007000000	1631284807000000	1694356807000000	1788964807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	312
\\xe3e24522ae1ec78d7fbc5fe0425a8cc463ccdb7e70ca15f253148db466ad129f9a8b6ee6a6c74bcd9bfdff92a438cfc6313ebc05c5031c0372175d3b69beff93	\\x00800003bc196e6e31917fc0d690e86c6b0ce507f33fee04f5fa8cbe5c608a3ea8202923f522a65250820c3b480fb62daf83c4cb4aa6382bc71405728fe82415e4c181c690cdd24bceaba72fea10b93f02815838b122fab41f11da09f73c1fb691d7c57f58a8665228bc624810e5e9677ac54b02b38d37fe1ff3c98a5073ed1172d48673010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x72337904b60adb9530547ac6352aa86d46060cb0a78d52094a9f872b70ce255c6a9750a4284c01df276d71106768bde3cafff678f2c1442243291672ddfbc90a	1625844007000000	1626448807000000	1689520807000000	1784128807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	313
\\xe3d2f13a5a3ba941a8129e4692192bbe763d4f43c770a2382ac61835ca8c214c757f85619a6edf1e1c8402a01ece66897dd04ccbb6cdc93b5d5a107d94ec3801	\\x00800003bdd0f5bc75987f2fc09e736bc6639be05f7bee163b68f4e847c51c95988c9458f7c6fe40e37e29ff74958016b75d99e15238dd7b0b1029bc2be039c6fe8d8a39d25a4d30c044e67a90337ee9c516317af717e4fb40a99aca7b6999e007043c674e8d0d2a865e1317625cc46e3ad0a37df1556dc16efbf05850e5f8e7a92dd741010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5e877f2987ce853ef1de91cfdf9de8178850a53ab147b925d4099a2b9615375da9a44ca768f95fa256b375301d6ee3c391cf88732c064dc8d58f36354291fa0b	1619194507000000	1619799307000000	1682871307000000	1777479307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	314
\\xe95ae8b87b2a5da0e4c4da04ae5a347cf1ea30bc7c842fda654771f3d9fe4bd33017ad365d0e63170c10a0ba5faadad92610da72757dc51aaab30af6dfb0ea7b	\\x00800003f26a910fd7d3de7ac9056a913230cc51a6d71170926418b73cc4eab18620703f6848555f18f5f63ec9048b11e3176a52ad8f4a5ab642ee440a64eb91e1690a66b36e57bb9349141d254dca1fb826d244e19348ae5df86a7c3f85f07e50f834e6d62a42744ba5733373c54195c927fd69765fea3a193f79bf86cac0e7fcec2af5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x728b2d6b1030f944edb55c02b1acfc5e45f6f429e4790102895f4e767872d6e345e9fd1bcdf2bf2aa02c6d132a1ad0f647f95b7d0faf0e40da7feb4ef296c705	1613149507000000	1613754307000000	1676826307000000	1771434307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	315
\\xee26de07dee479c14cd5ad29c96bb71a9ca7e7489a1a7aa460c24f553fc59e3459a68d0a26c2ef72413e0543e48d4a1c81ed21fac9eecabf1e4d5484d67fdbb4	\\x00800003c930f4f6f6c687a18e376ed49e80f8dbb114128e0b0c8507b50396e78683b51e425c15a83358192bba521d7b15328b879f4d0f5041a6edbaadd73eb21efd142ecf13118e99ffc31d4716616ca1d8aceed8a2e44ac1799a186ab09333a7cfc14a56d5537e46822de6b95b570b1936705b45b17b16586e4f08452405bc0da0b679010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x00492dcdfad3aa274dd22a6a4758e7b916ec9ef1b0df45a071661e51061f4ad5f9fe4f07d1eb7a8f2e6b9ae0224883b5e38d3d6c10b8b6521dca7cccb70b660a	1616776507000000	1617381307000000	1680453307000000	1775061307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	316
\\xef4ef9822f6373ed1ba740351661eebb54fa476a964a0058d49a38b7d15ba3f33f7b4c38fd3daf68adaa8f43254f7fccaa949cbc25101028c78031873e2ef78e	\\x00800003bfa734d0fd0acbfb6fd6a1a039d5d168276000722517d115a5f096c069f1e2a35d1b587a032c030bf86d761e3dfa662179c24aa274db83c4151a02335229bd26af60913ff77320dbba7b4819000d6c31545fb12ab24d8d740f1004ec4276ebb0a1bd85f788337107289eee8ca2dcec0ffc3bc82e4c3301ff164c496cbec4ce7f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x549b2a894c6bc818530c07aab584f02821c55eb151ff838d7bead7c8a530d273fa0ef06bf3e4957a1b5658234342d5fe9a8050024d68a5dbd41e51fa81034503	1641561007000000	1642165807000000	1705237807000000	1799845807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xefee9b4806eeba8750ce362207d8c45642762499a99436fd39a75c7f4cdaf06a6bd6bdd4128b6d0073b48b7e3fdc4b2eab82c14fb0508b0ee290187c8f7fcfc6	\\x00800003e6848db0de255d729044ec8949a3b2c9a97e257de69cd41c123f3758bccd2373fc68bcbdc59833e3b890678d23e8dff827a4c8ad705d2392ddb6f50bbf64b940faf946842bf9df8da858ed8cb96d4527469be0f56d9a040502dac23c9fb97439ff748fe90cc4b8f17337ff71446a7a06bbf4e8791c895114892f1ae41c141ce1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1b7f42bbbc673e7868d5b6a719e885ae212a4c9cd6758c051a118fd3566890b4ce626188e50dece0425904d1875d2248f1f5765344a9d93af40f3344e37a8300	1624030507000000	1624635307000000	1687707307000000	1782315307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	318
\\xf25a2a76d4b9760325fddfba2290fee4a0b910484dead9bf8e2e9da819cad09170b33a245a74f7da17f60afcc388c41835fabea8437c9b0e340e6838d3d742bf	\\x00800003b231d50020e70ed65d1c8d45bf01ed293e2989835f3883496ab8ae4579646516a6022a2edeb20c035c06779989262fb26f66b74ed894b4ecb672832e4e2f55afcc659ef7851c8289bb616fb2b884a1a2e1ee096dfd27c76fdafdaef65ee1be9ba0ac89404e4f75d8c2d784b9482672746288f8f481609d55b55249b783a0db4d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa982080b334795f2b84eed5a1966bfd006b9dd50ff2c22eec78240bcfce7a46bde57a6a4b4edca025e3d15c15ebf1221939a4c9fd873fe52a4738b04b39e8a01	1628866507000000	1629471307000000	1692543307000000	1787151307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	319
\\xf32ac7ce7495ab70562aa0367cb086b3651fcd23867372147b7509b96ef77b8b594d735dfd6e7caffd6a518fcab5cc53d583df57aa374068447af337fcae6d80	\\x00800003c4a1d3fef4ddcf6dacbdcfc3c5e297177e99ba3e9e25cb094df29ea71a8d5ab8e1da31384f535c165fac7f53b4015433217ec74c92b685c78114eac2b0ff78a3fc17cc7e612a50db9451eaf65b94ce57a8f7807465d6ab858c9542ea4c1c85319dd3430ec2fdea6e910458b0528cfa45f9bd82175d6eb87bcbd0eb4b8f937625010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc56594886667a11d072bc8d74d471f85e46a56aba9e04724af404ca8745a0c4c2014c98612889104df2f078af160495f40828627549ec09d293f81e56d7c9403	1622821507000000	1623426307000000	1686498307000000	1781106307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	320
\\xf54e376dd6a6a112c834bda7d725a21a74e4b0970c7b47b3f8fd273c69dc1c13db8e6dd1617097983dad9b9b826b7cdab02f2c9f3ebcd4bd2dfb44b0f6dd3805	\\x00800003bd53102b0dbabce20bf6e70460d6a1de556320ebd87fab137a49b1744ba42724d14dcd38c7e6b9c2f0877089f5195ca31a50ac5c59f7916801e4d6ef710f284c0e08fb515987e794dbd7da72ecdb28d1c8e56d4cb4d5c6df8f34b57594885e2b57722b3638346dd599c4f3dbfce228bf62f3973e3b94fc77a241582149a42fc5010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x08b7db864a48a9a76d78a2e6dde675eadf6912d7d3137b34093da9ebb52c6c9d5e4cf6129364fa4014f4289301efa0416b8dad2ba2275fdb06567b7b82124d0b	1631284507000000	1631889307000000	1694961307000000	1789569307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	321
\\xf71e49df27932706553f5ec10d642d3a5998d0ad04f177ee4c26b1e3b6a621fd2c217bd3d5f5b2bb3dd750eed7b44162e7d6029d62a23a6ffc433073caeb859d	\\x00800003aa8d842c557dae827351605a340187a6f57dd4aa60c35b1b1f1862fb04081e76a0911ce5e6fef662f324f48d62c56b379ed512f55d24aab3e2265be0f27fa14a3765cc6663f0a8da6a3ac965e2910ddef75f4cc4c3442a65ded9c551fb83b82e014bcf5ad1f29b45f50345f904dbdc8fcf82746e96108ca4c0f1f06d9db6b245010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8090fe509e3eda9a3a52ad0fe315306d5fdeb180e13b597e7f9dc4d7d3a8374330ddf20d352774e778238a17760d30588de2d7207e4443fac749b1d9b9bddc02	1626448507000000	1627053307000000	1690125307000000	1784733307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	322
\\xf856719fba50321c620f4221e900fa06649d1c4ab106f968fe8cf3cac3bb83a13d5707cf8d45805d8a3d88a9ce33ac520f94064ea044e4f4686fb47a89fc1bc4	\\x00800003adcb37a73b55e27e2cee71f9b7698a20589b02b1ce9072b02146705913a27105b867fcc67779c8159a17dc245ea9d259da05f6edd80b51addf8722935e9b334a536a4f6a8ce805e815633664c44dab7638387f801ba7fc38595dc22190dfa7f8c8dec9a39dc94d440b456ca6eeac8dedd29e84c1e780a294e9c5b5721706afe9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8b29d85d08fe602c189e2500560bd5cc76e91b5dfdf7a860fae3e56e0c84e217d099a26290635eecbe53a785df8f69b8660e70325a3b44ee3eaa1e9f3dc2230b	1633702507000000	1634307307000000	1697379307000000	1791987307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	323
\\xf9768e3ab162ae1b66805d15f226e898d3f3ef82f6a817abee4e4fd8da0385e2844959aeb2a58a683e8b76a9ac6234ef37c8a47edd08f14c627bb137354aca0f	\\x00800003a91fb655a5bbd79c0ad73b819fd7efb1786cd305490fac14b63a4dc07eb2307e27d115d3cdeb36f5906baea533e71aabc87c6360f71af4e6e3a688869de224f7bfe2475639c33e46d2c7a9cf59dbb1cbb5b442f761896f61a23b300a518c73c57ac9cbdd75b987faa1146170dc3ee568dc012c55650c309d233becae68196769010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x15c400d29d963421746a53d37a1ca3639321addeee84ef675c1ebc428d31a96b110e0ecb7a90fd83fab5e5f7e956d6cd084d1a922b49a83d90d95669edec2409	1619799007000000	1620403807000000	1683475807000000	1778083807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	324
\\xfb0a97ae1190e2a03ffdd83a17b2423238009c3aecccd880ba771a123b9dbae2470b688aafe63fd884a8ab40fae5dd9b3afcd2669aaee85f5956e60447e3270d	\\x00800003c08818af575d06554a4ac7191c3f4442a30d2669b627910085171099dba8807269056249f84a3df6aae96c7409f6a8f37d3f0589e848cd95b49813559ed0e6f2b7167bba4abe30b7fa45530f4da9d4dfd1f40e68aba3b49008abea7975a2884c326726294976d5e6c8d1bfeade8fa77bfd631c263cee59bbd9a3f940708ebc87010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0ad513ab7082a299684062ca84517a12165f5687c5b5e4f7c8071cdb8f3364d2850e6f7801f415267f35d93ec338dda64f86840f490a142a8328b915f99f400c	1616776507000000	1617381307000000	1680453307000000	1775061307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	325
\\xfcfe104eb78ad7a2c439bed24fc2d79dc5d96e8ce025d9fd6b45f79d8f51c16d4a06166772d334859392ce70638a05e8bbafa45f44447c395a6651d1baeee18d	\\x00800003d7acae468fd0badbe746b11ad3dce31f409ed8cf9dc66bc7c009754f6715f8e13027928b07452784a60a41ffa26948b4ed3fff76dda47f884bee7009d9dae23bc314b6a1a340638f7e015e0cec27799fb909ea9b7f59ba81fa34c56424f01440a3844cda81ab0002fc37a83e2c72eab29deacc480b202e53ecf5a45378d30173010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x42430b52cfd136a0d2ee4733f7f0adf849eec349b9df42e611c040e66b5798dc3122127c1767b07d73ad1f83f31b749f4d5b703d5a3ec1134570d8483c05fc00	1634911507000000	1635516307000000	1698588307000000	1793196307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	326
\\x01dfeccf6c07765d83f342fc2254cd71fb028312022992ef676cff70833b131ff21f75de55dc1e11c38f4391a900dbe277e236b89a9aaf14c5d1368bd6fa1f95	\\x00800003cf347362b5edb7ffc26a62ea67a8e6a40afb60bd9a9b52c50685ac49baaed6bfa1fd8b65086b92dfb91b7e21b8d1876b09c71278c9d0fd055fb5debcac9224aa3d44b6ef2c63fb610a1e713621e14505ce62521b294bece17204e3637d1e35ea8a3dc98bec4d3776fc77a4281b9809d4f4f1e790cc7152578f0d3152d31cdfe9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9441c8700012d359b7dc433bceca301d1b6e604f4012a2175d94cb3503219f0e344a0ef64a770eb01b6f229085afa7207bd05c246e8e37e231e03b2c4172a10d	1614358507000000	1614963307000000	1678035307000000	1772643307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	327
\\x024fadf62e9221025a8b140613f7a6a257f0c2c0251c12d95f7fc96d02b5221407aa40a6df3f8255b63d2c0e8abae953660951745c9faf1f97aa9c1dc914450f	\\x00800003a71750f3d183a67698efb266cbd753842bb3a60aede4975e9091c7979e3fda12ca061fee447156b3c319b30a64d25892660dc92ebe9a68c7911ccee018707a6e622fa1ff490b5e18c0fe1f02f6c9e35944724c40e0fa8c0fbe0b4b8bde8d5c3c4d6f7b46cc15ed4fea5270b04b5c7f47af9a3888899df0482a96f3d9596cd745010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x061d3c080378bae1461e83214d7ff226779d66040d60a7a66ce784d8fe63e0a45ff41fafdacb07d855923b0860d520342d442bbf2e884c79c3c1e34c383c9e0b	1629471007000000	1630075807000000	1693147807000000	1787755807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	328
\\x03174df39d0af05a8bd93cdcc80fa14ea79f83af887fbbdae06354962494a36b142db7adcca9fd2c21b4952d7965981fbb37f74324697e18b6573ec4f5fddb93	\\x00800003f2059c1d2e98f29067c1a665d425bf9e2c17b986819c5d1921c86935564454a531d4d9eae07b39818fbc162a2dd2b5e874a0d50035f811d4e5fc81cf77120b21cb9b984e721d09905d840425e6a43efe79c8e801e0df280a32d331cf48502f69c4c6ad197c7d4eb0d3062d62256e829da0118a7762ec9ae6ba2b21a4decfc803010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf59f982a367eb84219bdf548cdbd9c23695344e809b52e6d77b113e492e800335d88f070c32f76a1039418314c6d1462328454e17ea7b61c024f944e31aab606	1639747507000000	1640352307000000	1703424307000000	1798032307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	329
\\x03bf4d3d126eb89c6e85987c3037f9976cf1ad1be9dd3bd464e653a50b13119380408f812ddefffdae93a3f335dfe9aec5d4ac86c5f5eeb06f99e500ce4a438b	\\x00800003bd5533a9d864c173ec273c2c79e928a54b91c3788b8147164ac4062557d2f039ad6f121ab4c75058d9fc40d49a1ace687dd0c11618313f1e1ece3e0802466deb7e5c92800e78ccdea75e18f90f9186c1320348f9883edf84e56386db02d55de63cfbc9796820f5538daa2b1de20b8d00a4a3f4e5f4befe67b8564aa8e85c55f3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf8c82bbe5ed71c77477123b2bfb2e4c57a3346187458e0e55e27f030183a19b885bd3e8476fef4525a8a0f0bd5a432ee051c58130d61b2ade6644de59c847a01	1610127007000000	1610731807000000	1673803807000000	1768411807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x0573adad663ec9a5c6487bf20af592e53ffed69ed1af4894cf5be50bf5ee04953e7ad701ecdd2a83a300f4e54466f87dba3715e4ec4c9b1d858d8361c98b3884	\\x00800003c4ea3be1e5d0afa2eec8d38913a657ba48cc51d15159b2a3352b1a531b610301b536aa4b63c772a8621a585c9ec1792acc73ae9c9e0f5a7b0cd3fa46d5b96424830ccf062a1f9d8ab1bc46390d8eae7d12b97d20ba6467322e2befde2e408efe7254b71188774bc527f85e23a0d073fd39d081b711cfcb5a294fff209543f41b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf3bb6ea833b809723d4cd65ec54b109f6143353ae729dd1a6013aee21cfe57f9f0be2c38c9fe4be6853228fdf43c155aeff3d8c6313c80805c1ada2180eb240b	1612545007000000	1613149807000000	1676221807000000	1770829807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	331
\\x05837685942a9780438cf5b49e34ce3398d01d4abc10cf8b942c16e155e26cc84f4bbad8c67d8d06571421e7b8c99b082cfa3b00dd1d21ef8447fa26450e209c	\\x00800003b470cf81e972587b16a3f930c1dc5655ea94ecd0cb47163007c23894dbba1a395e2e421b6135a6cd3177759c41f0bbf82400ea3e94d8d2dc0495e48b931afa2152e3a31026e6e59c228178afc12447b9fc5e9b148b431f086b2cd5e58dee52a26551cee9552a47cd7e3db131325aacf5aeb3587d0527ded4ca668636b0ec379f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x475ccd490180a3e1f5a93a1c112b82649e2754089ef94478ead201a1485320479cbe9b2fec713c16714214a0fc74d3c1a7ad5362a65167ab09651032b36aeb04	1611940507000000	1612545307000000	1675617307000000	1770225307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x11236cf3ffd3a789270dd0a0f46dcddfc036cf36fa145993463ec5867c913a21bbffcef239357c5912cede2d235dff1a04b8e7bcc2781d75ce47e4c0ace2b717	\\x008000039e8c5d809a3231c096b45be4d36732e8bcad2819804d72d0cf3921793ef729c993796de77020f134294c7fe2fc7cbe14df5c928a40838bfe7a1a29d8b713f2954c75367e494e5d0485604979ed905b64b29679f3f0a3709dcd8e066cdd99da2e27baf676467a07353c29bf5204b5d3db6551c72108f55db85dd4e7788cbc7337010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x020090eb4f51e1b4b62657598b742cb1d7007f5fc174807ed635e580d622f9f38ec6138d1708bd276c676d066482043e74d287f568fa60fc1b223aa57c39e40c	1633702507000000	1634307307000000	1697379307000000	1791987307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	333
\\x114fd37153d99c09142a955f97f9ecca27a105dc8bc15219e840606f61f5d2ecf06c9938303a33b6edc7b24a1d7a2bb5f875f612060032c7badad41b55fd7cfd	\\x00800003c9534a51fd20df5419ad1c3edec982692e622d884b75d23f657c339ec260d9a769ddfc093f48a6d1196cc344de8e4911cb78ddc7938a949bd08081d5632e801765deec4b4fbecd7d19eb796ed5910049a7288b9818a45287b9e648b3b153854e886435625fad0ef43f2d08752ec02feabf371f2de753b12258b122414b539641010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2246bd7855b66c9e6e028f710e223961d005128ce57c78afb482bc87a358bc1bfd16b90d99aa7d8da84e5a5e1cf669f4e03fb42464b5b14d0ef8ab5a4ba03100	1629471007000000	1630075807000000	1693147807000000	1787755807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	334
\\x14b3a16c4ecdfaeeedfe3652b11b8060a25382cd1d92bbfc0babfbe3c8fdc4babe190b7fd8f81b7c1cbdc733349d7811764699903149ccd6ca1d4118a8b9e39b	\\x00800003e9721562fe33eb64d924d2a6fe3ee0eda2217473d8cef3339aeef45af6b0151c8d7eef1e959c378b243b6fa649a03f6ef46f1bf46987bea01a5a5589b22880031c2fe4e981a9555bd8622747ed7a6e3e062ad332343e0d4a9e89682637f3e1f22749575b810795a8d9cb8acb7592a003eda229413a5af7ee53b02efa4d7eb819010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9a66c36528c6606895def5dab015e67b28b674575d1e8b9d7c425eb387de8f8ee4db31ec7af63b64a70d3736a661ec6e01c04db3fbc2ba3d4883abd576001f0f	1627657507000000	1628262307000000	1691334307000000	1785942307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	335
\\x19739f1c70eb8aa6379273732b7d3508c1eace6563780d1bc59d13cf69edb50a38233801ae329692b54fddbce59b713412a012aa9065ea3d20471ccbdcc7b234	\\x00800003e5a1c915dab31e7e4a364493e3da0346c5cb7c4600a72c26591c827513e11c41c92523a949904822bbd510db486cf8f8fbf2709c0077cd27283827ace843a825e12af10eebae1a16e4b3fe4cf65119f967d26cdb9cae9ef581c11b6f5da7b67f14d68a774380af48c7b5bd5300031f395e2d8c77f8cd1f0ac43f18b4da512555010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x426ac670db38aadc5796dfc5968c4c2111a3bc82f1482f0f8aa481d7783548508081fe374ef8890ea5e3d39bbc244c7b0a81a4ebf3231c74f2aa0ee5578e560d	1630680007000000	1631284807000000	1694356807000000	1788964807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	336
\\x1ab77026fec661f533ed775d1e0c46eacd9bf2304f926b52f75f61834702f872a70783af8d7d0e6aee12008562c2406ef06c227cef5b88bfd9cda593bb89f4b7	\\x008000039c0e7637c33ef6fa0fdf76409efe13c8ee7e260edd420fb991c2bb82330954745c2ca05bc4a55e9a4caa3634b8be4ae7f159ad7c6ebc412ae0e8267a4220cbf6a6b66f1017c00fb8089e73bd56fd623c1c9a2d9c27c79eb41bfd076b6358c43879d8c14b787db33ee9f3b3f6b95c3d1531f17a598e4d95bd08b6a49d637f5479010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1376263d96bdc89cdc52e1376f939bec6cf1389353936e057c8c97455773209c3e0c97d42bf1672909a955375a9f94f3f65e220d45a8c8631a911faaf7ca8306	1611336007000000	1611940807000000	1675012807000000	1769620807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	337
\\x23830ef915970c9a1bf32ffdd1fa21b58c809ca719abd469a330af5c027f7a689053526d7a7c5164f9f92c63a2290ea50b93e4239f04e2d6d8de28004ce7b93a	\\x00800003a23f5e6ebdad1e82df976f8c733bfc0baf683d4b879bfce1c875cd98959f91da3a86db98ca8eae85c9efd478e7072747ae4b7df52ee8285061ceffc860086465da637622b72ac9369cd200c52026f287c3afd766d7b2fb482bdfd25f669052169746747cab7d6ae92e5cbb231e992baf4c348181ffa08454f3c27565f6351159010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xbce986ee3eca511fb97945d27c5e8268b00163696a58f8c9b482623778cce65b32faffe35f5e23b060f2960bff8a5407810b92aab95ef575c4ea25fd6d21240d	1639143007000000	1639747807000000	1702819807000000	1797427807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	338
\\x25ffe8c3d688ea406d88025ca502fc30e7ac8dd7f9646142a3d40157d90c9f44ae68792aeb412887a3ac6289b5d02d0fe698b13c91dfff74308a05a5490e0909	\\x00800003f48203cd7122be9c55690c9c702e3d8aac2e5cb36283783406939d82a85a6a3afe7a586e0e570dc83a65b8e7290816ddbbc3f04b7d9991851d154187dc757c3fcdb9cbd07cb26f30e49f73cbf71d2c2f2f150d66d20e292ad4644f1a79344783361782ba0a93a4a6be3101efa14f1ca13c4b0b1952db51bb26f011a7f6876c0d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2b3fdea7570342bb575387ca3da92442c789464125ad7190d20be8eabb36e29fe18c612e898c19f34e3c6d11599132af3bec993ec95d3a533e4a8c7516e09a07	1620403507000000	1621008307000000	1684080307000000	1778688307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	339
\\x26e3104676d7ec25fbd998258e24e96cb2f2f84423e4b4bdd2957b2ef33c7215458212458528ad5af32c312aef602ba31585c1d7f888a9f7e58594a064dcb039	\\x00800003d0773a57ed8e936673786771fc23cc646507dedf899faf16af6cd7a96c6534ff9305ffba83ce28b85aea11a02b9c94de61be556248044bc8809eb9acb61531ec4e96b903ca5d8f27ef2e17982be74a2c932b440ad86dc64d2ab89054798cc5bed2d336399dd1fb0b56789e761827f9da53ba9c255dde49e031474885f447e1d7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfc05be582fc038675d6315ef23895781e8d88918c046d81e0cc1f5e4e26718c446b84c2e8b20d5b78447ff1a8f83610acfaee09622fcbc1d12cb9d20d25b9506	1621008007000000	1621612807000000	1684684807000000	1779292807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	340
\\x2617651773e195e57119c39a9305416a019fec8b47b4caeb465a5df93bf6d617bee8a4dac72e2b9c731eb92d2e0e17c6af7b059f0d078ea59f99a9d4d2fbd3b9	\\x00800003f599c5a16ed9aea85dce475272b46f7dbc1a4d81a20ebde617383bd28cea8dfff94842c278ea1e726c066da6b0141b055ec9848a55ac446f538f141dc11d5b557ca0ca2344c840eb5e18eb3a01d6eea9df24c29778a2df470e7c4ad8a1745ac1c4722b9bf1d64d92d0873893bfb9dd378259d13b3125c3bcac570d5ce6e9772b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2298caf5f5dbbe9555c2f79152c3fc4c7e56f7bee6c07fa928f0b620fe700660737de6e9e00ce17032303667d96007f93dfa00f52011baa4576a5905e03d840c	1634307007000000	1634911807000000	1697983807000000	1792591807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	341
\\x298bdf33b54f6f99016f251c7793417d37bc15da1656576b8358906a04002963361edfcd0cbdf9a11645c70bf55b34f375cc561593e40c5966181438d6afd6da	\\x00800003e2056de0970113da461626822c3f9b46fff13a5954126aba429597426c93a4e694b4130d4a4ecb5aabe220b55b61dba8087ae34eb62c55f3136f684dc965709808423bf4d9e2d1d1cb836cb4c9f988f95f03e6ae6d88077cf2e7047ecb562468ae54e8a1ed84848eb34a055151d7ba4dd23421f4c14aee95b67fa13660245515010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe0ca9536c31be78703642905354633375408d9e82c57ee56a1bd3ee426e8aa9e3d6128841ba0ca71093d66f7fba05417dbdc1b5c4dc0f6ae05158aec96a4b10b	1614358507000000	1614963307000000	1678035307000000	1772643307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x2df3e700c84cfcc3da327fbfe2005d2b6178c792f0ce5c52ef367a86ae484f70b882e9925789db5063193aad648dcce8064eda9d8b53926eef4e3d477d1e9f7a	\\x00800003be8f7a6b18fc90e5a76aee037c16def209c170807ce25c64f474d7a82a1d51622388617b63357e3abd2b5888eb33efe9b910ae056434c2fff370eea7e9e543f91e9effdcd6ea956e951a57e9001e227bbe3001384552ad39c41729531779540cb01bb573e4bcd4aaedf8c9193661455d5f8d7e57760abf26e821753f2dd4e143010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd2d85e10e14904f7c194bba8a5591f9fcc3b22e61385349c789b75895f55439750caac5d50e7e9a7cbb114248a24490d699c25436488398e1a558f7254240b09	1631889007000000	1632493807000000	1695565807000000	1790173807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	343
\\x2ffb79a30e0b3877ba0604deff33e11513fe7fb185b9a824a96676abe4ab590cfb242b8c0f4b7c8e79f9ca0ed86d25bb178e6aff12637d8a1485d103a15ef319	\\x00800003d0316d81402d9c3ff9c834106ac63f9fdd17ea3021c2f4e44cdbdb0226e558f7b9cb2ad3189ac097419f49d158e432910dd4d41ec46a4017a02815594ecf0a271af9f24bda1a99834f644910125171ea88ea0acf78c9f574dd1969262c8a851109d0c257c12b9508ea551ae546d717b7740bba2a00fef96707e9db181a818291010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf9ca2ef727fe795d455852be9f33a49cf7d4c93373d4ad0a3807237164b8af4d1df35e101aa3d03c9ec755ece4dc966cc0002ef476e8a1d701f95ed4e1d0f004	1617985507000000	1618590307000000	1681662307000000	1776270307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	344
\\x2fd3b8b65377b2b389e536f5d464f90070a0c3cc6c320dc17144ff8fb9ff1be5096a98851437d15f9f9be8065ff3cb78b0f90ba24aaa316c8ee109c1efa6ba18	\\x00800003b4e16c246129fbe9ffe72433632c7b566fa581236197fc763789ebc4aff1b815e5c50cde7fb8e8a81105ba34969abee10a2fb4cfc39ac39481eaadc0c43cfd6903ce8dc38e766b108c05ba8e8aee56eb48edef0b432e5e7647732bb26337992377a7dd390480d86f9dcdc6771344089ebff9c83b357ecdc9a21648ee028d0f6d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x48e79ae1f07c83ca47091b692e355006feb7d979c90f55baf729995dd0b296de9e78a5e801bc7173d897408b03d1a6f98bd0d8cc463692737170f6d2d4627b04	1610731507000000	1611336307000000	1674408307000000	1769016307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	345
\\x30b75759813f2f5605c24fcaa5a0aa72441c063fb6cbb02fc9a6d1274647f638a88a5c1848a243481a6e2a4e0bf254939218cdfa44e0a1965e994010861678d1	\\x00800003df654014ba9fe604b29125522d262b56a1a343c6ff1c897cba032cb7e722f4b45095b19ec07d22913e93f00f5cc07bb0f1d01067da2d167f004fdc5b372e9aad9b8f3dc5da870a7802e9da567e69443c27f6efbc21585b0c8edfb880972e24e45c5f243067302f58f98d96cdf66a1488c4967b3edf977f02fae5918fd3c21d65010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xc3063f41735ed27475cf6c491ea16811647c17999bfd818c0787978582dc30bda8e1186d432e8dbfbfd2be4ababad14aefa176af066b10556f2c8ccf5b679807	1641561007000000	1642165807000000	1705237807000000	1799845807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	346
\\x35bb598aca55e3d0c4fdb7d2ccdcab78308c8b9765b0cab919f0e02b6195d188fd5b75851d717674b5a7877ff6a436c97ab701249b273f1e349e4fd0babcb07f	\\x00800003c94031899023cfa87c6e26e7552e4113c5e67754778ef8edef31c313bee1a783b8f173cd37d824446b2234011455a4fc0882f432c84de0c938feea16c8693b80883fafaa5dcc485d30e486f2532d2d24716e858c13a61b74fe4a8eba6b557efe0e7b955241084164a17e8644708ae2f493599427d87911a4f43c3e7b1e447327010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1688975f0f18dd6ec529643504efa75a5892bdf0eb7d177c1d9efbf48104615a3f1163e54930a3527ac15a3b11f5ef664f718469e2c72d56761fe35fa6c11a0e	1615567507000000	1616172307000000	1679244307000000	1773852307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	347
\\x367f31e954c45d35f9f802cd3f619e674556a40e8465c41d9995a471e1a05cd2008f5f2b91e0ac2983b9f5bdd63aa88ea677480aad1403a3637a5c9df5a62754	\\x00800003c93b043e61220417b3eac51d38c23e38b2e610613e7ccc11fd66856c36ce5e3eebeb4b7abc52302d84b1b281fbe5476541dae2934d3e655def3085079f5911c44b0422bc0f733b84839c5360fb23a711446d6c2197863dbf93695b2673decdd30425cd632ae68da9c4cf57e6be68dc4fd824e7eee81e627ab5530c4cf24ae177010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3e3767f4464938ded45253c5d3e3dd36412d2385a040a94c8236fcda2187a80e6c864df7146a816ceb91db8f1078b0bdc9ac0e8bf028df83657a04e8855b3b05	1636120507000000	1636725307000000	1699797307000000	1794405307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	348
\\x36efb0fe2ebd0d23798fa0c9899140021a3c9bb5f4922d3cca065873598b4b65b5539913afae6de30322992bd149c01cfd3019fca66613369e53f03746e9413e	\\x00800003d4af4c3156eabef66f5e281d5c773a497ed7f162516598df7d63a684ee8bb9d7c31cfa19ca5a610b5b633a34d03bd436c66404bc4ee6d4966bfa02972cbbf91ed716e70049e0eb6f121f5931d6a7d266f44af0f05b4339d540096dea2108054a3d93c05931971debfa28bed27d725fd90bd7a84615e6ac789033fba2b250f3ed010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5826f81c18870bc01eb9a55493a5558ddd136a626904e017747d7af02235ddfaa7dcfc52321dc96197a691da0d034ffdf088b9469e208c07a24b26167ba47a07	1626448507000000	1627053307000000	1690125307000000	1784733307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	349
\\x38cf1c2dbe61ba58500a7bb08ed3a56d0ea12dbe79969b481965748017d62eb0f7817e864aeef2138879e9ea3ef672a6fbee8193f869639bf13b7af09293d02a	\\x00800003a9a7dfaedcc7d0e93db58821fd47631dd84dc4f4e763ad7f26de247e07d34728b555f3cf4832030ec065db959ea745864d6457e4f466c918040e5050c2f7888ece4494cc571b1e03624fa2a9e14684d71415ac444c74a48822434f3f5bcb29b3ac54b9db63f74796ca324cab54bff84c98aa5bc38085c501f98d8a5ce5b34be1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf08decd235822670a69f31f1d81cfbb686436a19152e27c71dcaa939cf6d5f3be9aba202c896cc5ad2b10621c00cd2ec061a6870244def09f6f13a2d08cb6c02	1628866507000000	1629471307000000	1692543307000000	1787151307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	350
\\x3ab74e5743adeb1047bb52d6f84045aad0f4156a83a9869b42e32bbe2c8a2b48b00f17f7acb4ec4afc1a022843ef2d5478163d5f8fda218b9f4513ef73d5cdae	\\x008000039b552a4ec91ea7c004f7440cbcc3245812c6cef082e2d549e35cea0baaa803f26e7649ef47b8ee189ffa74d42c66b43309be438d60d78e36bf953b01df09c9fbd9c7264da07121e9c6c3da5a420ef7d22169bfe58f96cf6e525efbbac687a521b553c9f7e7cab357f24ba72509298028758807284513f7a523f380c683e4d847010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x25dae96a92b51aa607626cbabe7d2c7cfeda097d28790c542352e58155b32750a82790decc4c564e2edf26097239c78415b459dd54978a6f822abfdd95c4720a	1639143007000000	1639747807000000	1702819807000000	1797427807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	351
\\x3d7f3a7a5358f5d25fd969503722c6d236f8dfe449732755dfacb25766241b35c18b98d786ac62eee3ce8400ab4eec99d8b01c10d5841c277e760134e12c08ff	\\x00800003ca133f7bafa2b39b88bd4d78680f86534e7041fe22f2d622ea01921793e3415ecb25dbb548d5ff3d5ecad2cc831df8675fe4b5e629e9811a8b65d4bbf03b1a1624af98b46bfc93a0dd99ecabc2d636783be72346da44e1510b65e195be086141fcde16a3739db63b10796ee86849f14b0d098c5b4e65248d9f89de42d08c2c25010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf124f1a6c4828011454795fa56085361c68cdb75082bd96ffb9d975e7edbbd857a8aa940a5d6d516af3b6b254339a9489381f89f69879cc6b414dc74f4b20f09	1630075507000000	1630680307000000	1693752307000000	1788360307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	352
\\x421f9a9f63e099bf9e85c6bd9a7c39a1882e844bec358eb8067166eb43a70caae8f409663011ed89562c064cc3737f74695231bdb85b1746b0facb137db8d275	\\x00800003cfd8660cf0a1842c4daa4021bd8a2b47b455dced02c474b7226d3548e8fdf39bc9881612990c2f807558a2a3a2e85849e799ead3ca9d90c41ed0a06f4428f13019e1b6f38393b5833721655317f47a01c10d4b114f306518ca4741d0c994afb92f8c3dcd81c1566c21eff1b0ed28b5b5398c5c7ec3ddf1a00cd12158373e9c91010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7c0847db0b7e690b1fa121d98c237a822ecd25ecffc1b9196977478444754e33f955d76802b3f39de4257bef3340fdc66ecb1ae61ee26b97e7e484de14f0c90a	1637934007000000	1638538807000000	1701610807000000	1796218807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x444f9cd0f41ce166418ab307257f0f4cd77c10fccf1f47e46bf84d4decde81598da13e8ff775264e76deb4c7f9fc404505e38ef397774fa2173f428b593f40cd	\\x00800003bfa73c22a260d0c711a5867d5b8cd5267d6f870496b8add1d3b28d71d20762823f3eea0c3cb7f1f692c41144a71cfa51a79ab43b5aa767a29c5b7064824c4677479659115c206c826f3c2cce1702c03d7b1465cfda1b211569d288d63cb6487d170de6c7d184e2db02dc908e3fdbd741064743c5e362f6051991f7db1ae8657f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xaac79e0447101611d2de895468cc4433d6bc31925c947ab369239a77c9bd84372e120e747e96c3a034ff747d0213bf2db0f482e0389669738b818be9201e3307	1621008007000000	1621612807000000	1684684807000000	1779292807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	354
\\x45934258dfeb082687c3aebf9e6eb00e0e3a2e678005c5b15bd7a292667deeba9cc796d16cce6e14fe382ca51e2276482027c2e79ce7ead81dfa48dfb3885185	\\x00800003b77defe669eae1d11f25232cc3c9c6834a1fd99b3ab38effed4890481d93a5459ada516facb6bb14335b0b07184b7e3ba5d116080f85454885c184757a3bd626ce6e80d1d314eb8681bf132206a420c46379731e1db6b431c55736feeeed539aa7606f1bd7ebefecb24bd1431ffa4702c011bea47d3fd87abb8d48ef39f4ac67010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x73e5718cde0eff641fd90261cd276c1af4a9c38c9baee2563e1ccfcc3772164be2f58790ee7a847f31c5d261d416f94e17002b2da7543c49eb0721631145a407	1622217007000000	1622821807000000	1685893807000000	1780501807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	355
\\x512b28aaa06864d8ba061a24a2d1e197613cf36a8a2ff94d49fc7a697ddaf4451c49956cbae37cdb4c5432616363c5bd51c207314682f51a8aae1d5b7548c90c	\\x00800003db28a15cbe73ebbbf6c8abd215a53aea1b43b48156c2eca5c2f8c49b789687fedb723d8e03abf25dcad35158d474a5e50d415da5ac24de11316503350a76149e63929dce1bd24da27f7046a0ca8b2ac7c2b48ee2b638b66db5980a88c6b391551e0590cc5ba0aee086eea0719efabbae41f811be9fa022d6c39db690ac6b4d53010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x81d3b7e76e15196f0b0ee1c30d65288f0c71d3b5ad1ea50f569893a96a4f79c55543f7aeffabd13657229f39760d63a3a05434fb86b50ed6eef2fc7f71118b09	1616172007000000	1616776807000000	1679848807000000	1774456807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	356
\\x543fa7f684bc7784384688ece292ceb570f25e28619e8c0a9685752a2b4e7e0517f074f1efda08d0703548177db5bb3ac55a5116661ec1cd67dcee0f5f419dfb	\\x00800003d3c9c34fb586917e38fd0b0cd44781953b8e9004dcbcb91784ded32ccbff6a426afea4e89b6389d3133e3234bfbe59cd5c25bc6bce6209c0afe1ce51f85dca84b0d5b81556dba1d1d613281f2831db0190896adfc4f39574aba16d91cd62ce98c81ce78cd010037aa15858d136df50dadb1d105a9a66d0830ed5ae78e3b07b0f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf0d8ada26cc92af751c05daf07d7655d81fde65a463258955ff1a959a684db1855b97a80aa5d47a1049f4a8e0c10f9948dad2da7496ab1b7ff92c08a8785b90a	1616776507000000	1617381307000000	1680453307000000	1775061307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	357
\\x5edb1ccd2e57a803191dc00df875d1219d99f0234ecd273b1b53fe6c16d4a1697d097e7457f36b2267c0bf81d2b607b6a3bd84aa3fd433fddafbd24bd0aa3a4f	\\x00800003bebdd5bb6ca478fca7c82cc81e29794c1c6c493c9b842be44e22e3bffee5355e3e90a3966422a75751a44df6a095eb462d375e2d41cbe67c674209b755cdb2f9d6933390cb5cf38df7c29375a9a89228541db77e12ae8a897c35d55f2f4211dcd78294300517adbb6698e2e8039e2aed64cf273ece783762d4c023b113c5b1bf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb78a1804ddc7e5544954b1d607facb525e2b7b5fc4600f4b5428ec544f6134a8901275a7b4bca537215acb516f9088e625e6853db381839b352f3da233b7b409	1627657507000000	1628262307000000	1691334307000000	1785942307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	358
\\x5e2fa96c37794e4febcee04be367eb398e1f68f4afad51f5aadf047435384e9a02781b26c20060d98214aabdb4d3c49857734a683239c96bf10007418f2a74f3	\\x00800003ce40b187a89f1396b53740cc414bf12d44aea0880e51bbd0c1df6f57c2830dc83a8acdd1182f493f0e0bc93dc693fb85168eb2dbdc2dcd844c1cae33f1bf542c08a4e42429f6d16f60ac8d9b65d4952c4b2afde0ebed60f4d9eb0d0755dafeba2da42bc997e60ef8d901346f0f75ce85cf55b167cd642552c12c3c14bc7c42bf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb62a46b7d80a6e30552bb179de7bf5da927486111256f1c109091f862b02980674b6afc0a87ae36faf20124f7324d7002e6b85c0c3d1b650c26239266ea40506	1627053007000000	1627657807000000	1690729807000000	1785337807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	359
\\x628b134dcb714c866383cab3df1668318f8e260c88f830935c7bf115128563bb5a23ac295e07463c3ed966db0fe9dab734d61f16a178c8f8446ee58e76cdb294	\\x00800003a4ed30d14e1e6c32d810a675de985d0e358206916ce144efeae9ce29414ba6c8b30b69c82bf2c90ad2b221c77c2d27ce76b2535d99b0af7ba51df78c14f0e64c7d3e82c0538e0dc1d2349a59a94e781232ac2042816641cbfec9166e75845c5b17a6850aed34ef9109b5f606d8418760856845758ef758504f77c4214781df29010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x07122b677b2d4751f9b7dbff8b38ae0ec2d6da6aaa7b77432f2eefbd5c523b19cb242c6056c855f98b03d0fd8649d4da7abc61d2bf69ecaba906de1a9c182604	1611336007000000	1611940807000000	1675012807000000	1769620807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x63573ee9762d96269a9b28d880cb8dfc3ba5854a0d95f1d6d2d5d64d50863e536e57bbd4cf5551e183b6c25c8585c9f5a3cb08c602f6050293dd7abc5391bcd3	\\x00800003f0a2a386f629bafbf5e27771d34d167616c534afc2b90d394edb955645294bf69965290a3f5548fa4ccdb15ccb1d393e31c7b7c951760eb138db9abce34cea3dddb8d38d6b8866e9663d11ac3703d4ec804aec04c14fc3f660e3460517c9102ff582741861574685e6627e936fe3623e6ccb2abe84721ab6b349f7e9d9d39d51010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x36f2a177f5e18b99b9abf629e63e81f8cc5879dd8ec360c92a3a56a21a355a6336df13ff4e4380bd7a1e3477622c70e57c66c8fd9b67b24906c5a548744a4406	1622217007000000	1622821807000000	1685893807000000	1780501807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	361
\\x66339d9fa8ba2c2b17eade2d9d7994c00bcf59cda10234264efcacfce496dd5b7f1ac20714ef7d6966a34bc6c9736f1a3c8d4022b41761eb1052b9bdb5c6b143	\\x00800003cb6ce17ff9b5fcd06c10e505b870e15b640d489ec7cb6cebcd479dcff71fa105615c35f4dfdab30f646116b0b0ee6d633a928b8c0dd3e59c1df435b71bf79ef208ba3118c9f8a4ec30b6f2c30e36db1e706d1087bcfa77ee36139c3fc08e86fb786e7dffacf46a9c728d68040898b6665f06a5917f87d259515176137ebe081f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf6ad4d18e3807608449544ae2f8bb0dccc71fadf3cccf26d7637de9e4afba34b58e385ddebf72cdcf42b9e52e7ddb84d42081f8f51571ac3c9b81c115064ac00	1640956507000000	1641561307000000	1704633307000000	1799241307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	362
\\x673fbcdec6773e131c190e1f448456743da6e2c9d332b4235e64f8ac42ebc73ccaecb811e81acce55f6e3effbfe60bef330abddc8b09086a51f06926617a1fc8	\\x00800003ef44d419b82c13f3a8c2497df41a03c68257b79204562fc62ca99489089ca1f491bec1ab00e7d4472ec2f36f66bed0bc9f0605c6e6bc5e632d01bf5ae158a061baff85d11ff7df02bf071ee29d344c7d44c65aa57d4afae17a6794a7da60c5bd23d281f3fbba177dd3d514dd5fa6d0ec27007eb25bf75e98029b3df60a039cbb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6dd51cd648c5d1c288f6d771f45b24713a2be4a1bcb8740bddbcd355ef0be64df71c4464b44070cbe200798775e4f215d244376e7ad1bf3c12ab31e38676dd09	1631284507000000	1631889307000000	1694961307000000	1789569307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x6a9bdde7b9eb8e9d526575ea4b3e898c6ae5774ec643dce9e4134403c131479b6c0ca09d757ce2c119e3a6781df2fe848ff09b094abc773cc8c886a61582bdb3	\\x00800003b60fb8da351029fc8cb395ad4899c9be642700cc48fef707426059c90cec45acd940b7038e8972a59c1abbe45b3aa229679da6d07b98a96c9481cb8f2b009b4b8c3374489096a2aa7cae9060995303696cab4185fa68553d77165413bac61d430e0e858cb637388778f1151a673236eb71634e4143c74644718bf4cfd6b606ff010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa23419c6a16d793d587d0eba735052094cf0d3073333055beeaf9b77830a75a7d955ac4c3ba86ae74e78ee4f6cda97eff9a22e60f0313419fcb231c6af004d02	1640352007000000	1640956807000000	1704028807000000	1798636807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	364
\\x6bb3b345cf0f44ae6e70d6b9598fe1410d63986d6cce39ac9070e468bf23f6252bcd84a9c4daef38168f550e3aadbb00007533a048990ee49c82f9d67ce2b989	\\x00800003ea94e118bf82b4f2f03b46236d444710c7b5e0f5c05cfd78d251dc772ec5c720f2dd18de715de6d62cccad5eaeefb3059bcc61a86499f9f9d03c6d16bf41b4b39da0ab9cec1d62fc1252482fb29b095bc65e9f1caf88738b9bfdaab18fa6da2f701c19efbc521b15db26f2b071cb7586ae0f49cb36b210cbd6a363ce605d880f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x0252aaf0f418cf9371af9b7a19d6d2b0008cea0104f9c3d7594628becc359e83cee1b64020342859839d94aa85232c0379e35e8a0004e7ed51e191c12034850f	1639143007000000	1639747807000000	1702819807000000	1797427807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x6df30a09172501a34d3147a38f5541f7a0ea9252d57baaadf2f01077be5023e84495342c796750643b9f67c1d78a5fc0d8f6911fa997d68f27f1dc1beed4af32	\\x008000039e8f376666ac68c42270f8a45270df1b220e2cfd4dcfecb5cd6b6c9af165f98a442aabab1256237a6bcee71503f9e836626f5790f6faa4bfbb4b3029fc0ba3aed90552d0782bdde75454fdc28edc6e98c07ec20338b2d0ee5fcced86496d4fd06e07b6284d2a6993c0946a7756bffd97f4ca351380986c4acb848570516ad14b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x723ee0e3e18d4518d591dfffa108f545d184ec5d7d26de6f2552841c809a2a1bc773f4d30747e6844628abec15e508af036e81e8c3c4358319a5018c925ec002	1639747507000000	1640352307000000	1703424307000000	1798032307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	366
\\x6f179c7b4153d81e3e37e0d3f3e7d489bd2cc480ba10fbdcf5cbd8af96cd87794e18ae37689f2d2771bb03cce141d9de49096fb0941c20e50f77507603c85767	\\x00800003aff2f7c7dda0ead75a1bda0d8c098aa37b42e062914e2bd2f4ffa3e7fe9a64815871ef3608493c3144ab164ae981c711b0e410234fe722a6451a334c0d4b49fa744aa1a9b88b58237cb3cf13c60405ed70d2a310816bbc9d78e3127ea4618e01fee90b18e6bd24246eebe0e2ea548ce2f946370a32c6656924a2f3eaae04a6eb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x473bf182ad09493839b57f352e0f468410ba360faf5b05b31ea4e0acc16ab8fffe93c78ae842eaac587a32edbdde8b0410f56439571007bc7890cd58a4c59705	1620403507000000	1621008307000000	1684080307000000	1778688307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	367
\\x705ff24361fd453ceb2414fafc48e9bc303b2f7dd6e6fa0f2c1db1ec0c012b102e342240c6b62c6e8e468ffe15f30beff8c627eadacac652359076e0e6051db3	\\x00800003a848513af2575ffd5c11dfe6deba4c16a45df5320ddf0af406d3793767366a018fd187f50c37c52467827fdccae011f3c819fca7a0ba103cf7fee053bff93e47a66ca7b149fef67a9c1a390a8bd4016590d58c3eba9919842de6becd0012d24ab457814509e04b0371f58168e45a9ff47670b1e92b883985dc248b21d4717629010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5193aeb3f4448e4a9da27b60bbd98d105c2f2dd5d6bb8e708a7734646072f2865b24169999fd9e5eecdcb78a98bfc0b6c53182850fa08b1d5164739b1fdf1d0b	1613149507000000	1613754307000000	1676826307000000	1771434307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x71d34ccf572ac53ad26d840638b82654239cf6f1bf55129acf1c1a99b2641e976dfa49922f117925757bf75f2f21927689fe8d0e22936923f716a4436c06ad75	\\x00800003b95a632d51995a49ca2d09160c6984abb428375252ef82072a7f56d037f737dd101ea5b2a4178995f74a388d103467eab80f992ae8dabde8a5adcf2342689409d11b86ba6b773a3f8f84f5ba44e6a6d8d3f0ddf23a94491265e6f24aa211d437b803dca5931dc9e72716299628a74b195052314adbc7d659e6f9666e052a88db010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8de25f1aa4821ef815c846fdc23e881632c47ebd4265c9f9e8e5327e5912f6b17aec1304167fd0c4f5d11fc41946b1abc1ad4d0bb067b354962984199490c30a	1614358507000000	1614963307000000	1678035307000000	1772643307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	369
\\x715788f106d08b9f2af2182192d87a36ca244f02492bfcf473dfe8ea274b2e694b26991b81efea6c4e19758b607316b047e9f9d1fc330e8317cf1b9d5f42c9d3	\\x00800003bc8693bc3a9d5b40ac27680cfc2fbd9f6fc6970dd9cb88f473d851ebaab4daaf42f63a82130bc251c90aef5c508ba45338f61881d43881c3f96ca49801181f1a86d1ebfb6675a6ccf55ef75eeb3d2318e40995931825a570ff57407e8e6ae0bb70ee440e1498010fe5ca8a47efa1b2d9ddc31414224310ac1c03dfed7c09671b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1b565fbd363c5688097cfe9947f77f3e0195a2940cf737a17c09ddc09f91c6676107a2d8a1237809cb6800751157a75857a642b729666cd39de9c2e2c072a206	1623426007000000	1624030807000000	1687102807000000	1781710807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	370
\\x737785ed027fd5c9d6a59137576f81431dece3f51cb29405ddca4e3e7f704ba273a06cee0e68f78238d566134a9e1f9edde4161bd2ebb198d08fb1978901a00a	\\x00800003cfb472071c04dda3e3bb70f4ae2a1a56b9a9360c02fbf9e6c41c08c97971faa789cac5b26e0cf5e5f890833addef66cb24ffd899d2d06e3504ad22d865db1f1f6f8f1dc8be6b5eeb125507320e1d2f1af2159cc927ec8bd8cac487b34e2fda9db05cc75d52d45fd7c4c383d1acdcfb070a04b7131d27cdcd8d7952fd0d7cf7a3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5b4665b6855d6e6d2ea154bc4df2d8b04eef27459a8caa255160edc77a56c4258c55f29a3317e792606028090781ff900230aaf4d707dd498bcdc32be714390b	1610127007000000	1610731807000000	1673803807000000	1768411807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	371
\\x746b4c7ac6328646c98d15f9bd8cb1d1290d96271032c3d7a5e134cc2e160071fc5ec54afeace71dd2fcb5d6a2a3fa27536eade090a8e455dc304b96d16d7333	\\x00800003aa052e0ce62d6c917fdd7fc9eedfad804f99ebfd0bec6b24155e8ede9ad28ab8dac474673f9de386d24765068c14ee39b7b907da325c61516a13e8c355201ae746caac261e023a3f13a885ad73856f69ab158be1cd443b99d7c9cbfff093982369a5a492e1b8d7d2985fdc4a9e891ab5348eaf0c16c1c6173c1771d64b2c70df010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x1c95ae64810fc4159a19647c3364513d0cdf8c70159dcb3d1d43a8e0486e27b69f9868ed62c96529df47bd62a95177a8916af932b7ff0f08fbcf8e6e65404f0a	1627657507000000	1628262307000000	1691334307000000	1785942307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	372
\\x763bd2c7abbf7115e6bb4088d2b191f3791bc3ce98f1a80f9eaad2f1986f4069e25381a1ab5498c7f1192a05b6cf0c8416cc24a0b3bfdf145a0ca32853bdb7db	\\x00800003db12689e880ad44601bf121ba3853e7859e4baf91f2c54bbf8e52172511336bbfab27d90543312bd8ad884b45427da2d2f91091b6e7dfd43eceedd07490abb4331e99936ef6092a35216d723d8dcbf13fb02ea5cca5ccdd9e01055e7f0fe5a5d6dd7bd21638be6af78f347908467761e605871f838d32fa11101dd8851b11343010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3252dab1c5b9ae9a26cb9abb31c25180bce07eca75a432ec38959950eb832b1b2cf55273d79a1626a4db5aa4c960cbaa5488d1c28237f8c98baec5b700b7fe07	1635516007000000	1636120807000000	1699192807000000	1793800807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	373
\\x793732daa04630b4a805000170e35d00e49eb4729966714f3010caca249e4fa881d0bc02c7e7e7ba9ee8175438e9d17de9705a24f9ad1302e4783a5decabdc83	\\x00800003b10a88cdae0ce54dd2442118d02b4ee6e9c05fdfd01c0edc441760901d2fc7ba3c232c80d226b0e657129195d210d8b21db012c60b2146f42f10c12d534e2c886a404f74e57c73ca5c100f41f7a8849593fe933b7a9d9ad07e027695e1786138969cd98b66e0738d95118c87e16e8d3db028b720389b4ce2fed71dfe0cc49adb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2cb32ecca3429ce33453648a79e3c391bcb7409f34cd7677ad179c0b8202aff83107927162490c21751d1708fa1f30bde42e31302742072ebb192c8e8934db06	1621008007000000	1621612807000000	1684684807000000	1779292807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	374
\\x7f8770689a53ab8677c99b26bc0f33011097c1e9287c58b442c802a88e7eab8b5cbe62166aa8de40624afa6b7241918603abc8f10ec3d7b898f97da8a96b543c	\\x00800003d70c1a9c101483eff896cd9df7475666ad319abe8be6aa7f0b4d6baa68bb372b296dece95e7b4ac2f8b82a6bc80bd6c6325fe793f3184332f6a8a29495824fa0716db1a08d9a1e06eb8a8a16ee9bc3631eab41684ceaa3442518f09bdc3e1bd51e74f66ae51b4dea246078d2320060cd4b2e33a2acb48036f50d95e6e53bbbcf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5368694fa4b615e9a49349c514cc3c933127481c852c3dfa9115f62f1a8f90a96e769432bb76d0bec833a949bd2bcd6e0781b11ffa7b74a671f58bb98238670c	1617985507000000	1618590307000000	1681662307000000	1776270307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	375
\\x82b72f51b53b9cb51df5c7166c1785e96de07a58bec746e351494cd744f767dec4338c3d9e27c7b6a7a60679d2d0eed1de51040d3422b7eac9435bfffd10496c	\\x00800003a967c8e4fb43512358eb4a5a8552a63946c10e9c5c8b8c6747364af9aba5c4bb67578d40090f64106a55eace1e244d01ecac506115b59ad0494f0663ea912625e95bf97e536a146d2fab2f6a29b39bdc294d8941d3db1beb013287cce5f6f28ecba49b722b3c92099224a9b77595388b89f61fd4b48a2122cf06f98b87ebc6c9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe3fb6f6686909dcff1ad21e448c95a47acdcd64b6ba44a2d65fe76b252704af88fa4abee32e29db3069f3a1499db6b142195bc8d1445bd30401c56ffa5816109	1635516007000000	1636120807000000	1699192807000000	1793800807000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	376
\\x865ff59287f022a9dc5c9ea34c06e7dc402197c3adb8bfc08242fa9d549b5e917f20a32e82592fb24192bff3334d87cf9dc13ee3210b5f34a863dd93e9c81434	\\x00800003a91e8c91e07e972f331fe8f00c25c741d71e2f82ba95b7c70fdf29bc13898ad44e5575b4050efef39e008eb6e1bda650c2c0acb4e98f6f90eee1cf2bd4aa23b1a87d09e6cab62406cc8d0b592c47d98f77117f80a4d9d6637f3bd60560b0bfd295906cb2ddf869f6af004b3be6c3098b5b1f5e9ab5393ac0b767bb08e3e0c055010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x5a2618f022f3941a71eef43535e12c81530ba3bd042da739165e09ef8f97c0096e4785d171f7cfd64023a2f67befc01e652782e2c7ada11b5f5dd1a599a0ee06	1632493507000000	1633098307000000	1696170307000000	1790778307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	377
\\x8a47e9ff63dcf636bcc76857e4c2622ae42e09fa4863f1d46e1127164b9f5521c05e9c0e3d820ddb1f61b7323dd6d62dbf4a4092d241e56cf64d56aca27f3010	\\x00800003bb08de4ac7117d3ddb22597e90b799102bfc452d6f5fab725ecb1380de3d852cd607a03647f4530b924daeb41ef2112a915b66e4772b25fe304e2fa410e721b97080939bbc5b0d950b61387dba5ec7f77fbcc8255f87cc90115a64f317077ae717e286acf27a62f3b8ad7237025ab6e5d5329d10b92c1994f60b5fbf51e80d7d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x92405cc340c947b365d0e480696e66ca40c1bf64f28c574f64abd994ba6ce94478969950152ab0d68a9e729506f28da67ace21ecdfdf3eeacc4e928a93a7a800	1639143007000000	1639747807000000	1702819807000000	1797427807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	378
\\x8ee7a2f8ff2ba4cf5c39ad395ce71bd9946c85e37c5581faa9620f1971f19ca016de45bc3e511c92c5859c013329850bde1a578ab526087fba22efb3039ac607	\\x00800003c137a35251e1360617f4b6a1a8fb09028c74155318a6f27170a2c6a261de2006da736ab2b7426d80eef483e8a468f498eccfc143601136745abcc70189e65bdc7b65cf7359e6f6ab818e752969c4acef010dd3a00ca30afddf1bcf87dcb5f05f0ea62bb60e0b717c2fa6b6f704b477b0f8187c7d178e9e33bb957b471945cc81010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa216e65fa7aacd1570a9e8da303a3f5e6e553d5e3aa78c7979ef6e4322ca8eaacb8c0017b036700c679df78dc37f671cd0c6d1286420406eaca5dd884598060c	1638538507000000	1639143307000000	1702215307000000	1796823307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x8fbbda94a230665669c48e7cd62e1b441d07ca8f5ef64611c9a7bb6646b79ddecb1f3f5a919845476ed12892dfc769a2c80640cfd4a0957a63461a376012aa65	\\x00800003bfc2f6d067c6eb590a9d166ea3cce86bde6c89243d5b3c405c8f4d34610898270399cbce38fb9bbc7a6274b06751e06a0ae1fb99860b1e51d3eeb11a3c2627b715cb6b50a51a87108387a6539d874a14883fcb374880787d1306e1c456268464d9f06b27ebc3ab40e49c81d3de818b8f105d426013e0c4d17b0568646fe214c7010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd1c2444fb7e4433134314d8148d7edc75e1632355f9da3351a36492096cedbf848f13d326bb28459a0129ccd9c328ec651446d6320306a8e5ab8e72494b9fe0c	1619799007000000	1620403807000000	1683475807000000	1778083807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	380
\\x933f74cc224225185d14dc36f8d0d7ad1e8dc97b518746a794ddfcab373556d5bab9af1ffb801135bba04da852bd28875032490e30d9cfb4edd6cf5f3fa7f709	\\x00800003c2e0cf96b2b81798cc4e5e8cdd269ad1b28373cfdd4b1dcd1464c8f9d109ad2c81b63efdfc47c26f6352e067a22ab323da997de17fd66b9f78a3656cc88115cc96ff1989f970db3873d867adc3d50afce85ad1c0a1c9eac4ab9a766fcfcf7c3e1bf1eeebe5b81c19350a4a1e99cfe2ad7b2b073c3ff049b933204ce006b68bd1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfc89e5d70cc389ca48230837fc5217b110146dd516555f7189b996093fae7d73370cdfcfb0808a472a6d1aefef7683aeae588b7c2026763158f4b0dd62958f08	1632493507000000	1633098307000000	1696170307000000	1790778307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	381
\\x968fc4e141572a84e3a9845d3309157569cabdb85ae6afa0f3d3b0480abf6722aac0f6071c7f59555b869932c0d79189406c004ef69200d2af35ef85fb4f2d7c	\\x00800003c6a864f152e3a36f70a42f3f8cf49f7fc6a8bad4208ad2486123a4b0f38e185547439e9f4c6cf442c363632bc67edb416e977886fc256a0882ab9a63c5437c171ce83653d60c887e8e7cbf7138fedc2253047df87bae02acb1a8f10706f741f39f83a09bbac8284798021118f67ffc81071f3545d492746e67380381bea585ab010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x7d1001389c5734eddeae6ae42f48964d6c2d546c553f8263dc31318cedcddb5aeb4e647af3a49f81efc4097ea990934c13bbaccd8fb8f3593ad7eb6521aad408	1633098007000000	1633702807000000	1696774807000000	1791382807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	382
\\x98e718d0f3bdd2758b2b1f540076c93e8af1f67821a3b432f900e0f12cdd67a8be376541f872ab2aad46707acd67aabd90aeeb7d8b9b5d0f16f5b4764ebee0fd	\\x00800003eab24c4755ddd9daecea8ce4e4586da1cfdb00223be6ff0fdfcbcd673ce70aab885d0e09af8433058ba59dca3dada2927bccd33ddbafdb9f98f2592b01a7f312aecd08b143d5bb3e250f9691da2b8d8eca9abd7a8b3ab898c06b82d87271fca68e893866ca9851c71b7fd52f7082d797166a2454c494a35ce28279503503c4b9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8fba0bc4f62b67fb395987b27697dd75063c11ed58127d33094c5cdc695cb897f8450b8495f668752cc61b65eea6523fd9d6566a15289079b4180aab7be70802	1630680007000000	1631284807000000	1694356807000000	1788964807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	383
\\x9ee3ea9e1e20bcb382bca7af9c53b8670fe035402d2537213d8985915d3d85715bfa4ed0dc9af3b5a90f9c94f899845764053e7c7a61ab647d4c62cd162ef7c1	\\x00800003b5b7fa0bf5b6c23dc49a62209e9387a7965b498328ced60cf39c63c5babc9978d7cd79698dd27e6c0bd13e77da6d04768cb050369ab5ff665704432e1f400a35fceca0a7c8f932b28adc4536371f55b75725fdbb783afad9cd38e9c34306096ba749435663dfa1737d92cc7914e3be37c25387d0287315022989e1121ec6796d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xab2d5f2ef209497be308984841a784fd5d23bbcfbec1a2b576c76b9ea23c5a7be38e6994495fb43dade36864b3176a07646fbd61aad74d4b1b88114a3b897303	1622217007000000	1622821807000000	1685893807000000	1780501807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	384
\\x9f83caed18b8ada3c707cb2eb4f7e7b32a40627fecd96a5792624d103665df0855e2d3117e6736379e8f1d86a9e94b81c2ff6dd57445ded92246038f26df70e7	\\x008000039b5cdaf6a832c763fe521354df803db5955211821517d89da1553c074921922fade885cb1f820ad9539d4682870ed912cdac30d4b200b424d5a9a3091755d827ffd4b85207ac4083aeea5d57fc2e651f1984d2effe4c47dc7b87ae9b2b43b8032b03ebd0606f72ee429979872a7c4ea586718571b4b2556c1d338fe4402c2d65010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x37e4eec25b6154d57058cf1f576cfac8491a20c171e2ea66d0029b37fb7e1965f395594cec6fc4aba0e3477c80e073f50a687ac60df1cdc1bffdfaf19b33fd0d	1637934007000000	1638538807000000	1701610807000000	1796218807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	385
\\xa2877d2b6129a849334224e4cb4bf5786c6c8474fad8e884bbceb4cb9102c9b8b7b54652ba273a6a02cbec9c017b350b29220a7c60f89f0d088a0992f02dd848	\\x00800003d04c85b7e3235068ab8c2372e22afcad58c15249102b2e592bce035a7e3683e94ab310520ae0ba5ce0298c982f26e2b1440ab1959825eaf9bfba981f622b4a8998c0f9117e092f9fc59b6f049e04480a5dde9ab2044bd374d10d1e4a31b5c8265e551def82069f328d0a1e47066db7aa37a83abc66cacc08d530a8d7779be309010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x308984b26050310210d00e8a9144c705cad23d3113782c039707be012d73378e14b36664f7abaf76e4febbc6453e88b18c2aed4c2ef24d8ba0d5ba66166cea07	1611336007000000	1611940807000000	1675012807000000	1769620807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	386
\\xa2334b651130c28e0f0eca7fa78e5f8d424206444d7edc2e5d0b741b7801afd11d7aab48c779d990a167948e23ae2e71bf1948f29dcbb7a19d16e7b677ecd0bb	\\x00800003d37041e2179f75ce565f2ed9fa4312501cf09882224c85b090e85de56906a78beddb08a842e1094381c7ff29270adb97b1a975ed9b840921c6fae25dc79a5974976ec52abccf8ad1586cf00464e1bb2747439694e824ee02daf1a919d2f7c0db41e0a6d6c246646027b370129c9c7ed4d4dda39ba0407b0b3b6e7643feb64425010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x41f0dfa705434315a90d18136d15d8e7f68696e4a6d70fcc7706ed476696e5e4a5e4cac185d7e2d197789bcd40d340d2f1dd42b69514cc285ea12b1a0bdacb04	1635516007000000	1636120807000000	1699192807000000	1793800807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	387
\\xa40ff98711c07e73777e88e0002b758cfa1546ce4873cc9e2b787dd3181d85865a059e5f02f4185ab737ac9e0956e1a0780acf3d69cdf962ea1a29e57f1740a8	\\x00800003bed4ac90042506e75a7542848474c0b092e4daa89f80d527c689e6813c3e286c897bcaa199e45e7663dc2fb567ed91c3384108b8b781ac59f50b931f9bfa5c73f487530119b9f0d7cae985553b1f7262839cf5d4c7d24ac3aab22a8749cd95e943322fb88f1376b8612f9a4d44386fa0b1efa8563fa45ef1f29baa13c30216b3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x87b6ef6a8cb9c91ae5a5eeac71cea86192c8845636eae5c30d8c40512b7a38d008fa1888c95829c7fae90aec690d705ed9373f17dd0fec92575cfe6c0e4e990c	1624635007000000	1625239807000000	1688311807000000	1782919807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	388
\\xa5dba91fbe6a5d7fa42a8ca506e1b0380a7fa0528cc08a0705d4afca2bdb1339d23741b925aeb3237a5401d5eb41bc6fdfd02cc134147ef20d84eca030d6b2bc	\\x00800003d2238506bae076859a4bc4e41b1841842cc2cb2600a05ca6771fdbecb27229c808335c9cd6f84a029cc7e01fb368a75ffac01a99ccf744a915dcf211c49aa35f24d799b81b46068336d61377efe63a07b41ce7dc383af5e8bdc389667e8227ffdeef017b5440d53eb85e8f25e2ff465459038d53dfb5112921661ea34de5772b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x64d0032e7e633efe8bb38f7eab380fe9dca14b8df8a1df855508b444228391031e162a049d2449e7f21b9b8d3d987d9417d3bf8da88becc555ff0dd01b43a40a	1614963007000000	1615567807000000	1678639807000000	1773247807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	389
\\xa9abad345f5697f5c580586d9891232a692981b7a8eb4d8e526dd0bbdb7c85f81a4f12d41e16332d6df3b1bd5476b6fd2a106902701a6b4118812996a62f8287	\\x00800003d2563961933db3d3c1f4237fa6fa12c429c32b525fd418c76b39313d1b6445c2d40ec3953a0f97d47941a673ad63638c2935e1a5bdffc94e1c3e8a28f2104ff000e2168e441eeb2f63ac484c3fb422d6b89e6ab41f065867dfc9db9086450df0b91ed3906f21ff9c072092eb874ab1321962e489f64c339ccd6dadc798f8d81d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb04584b214399c2b236f86fc3b47670bbc9970ed0cb4c606079b19a66378dfedbdd8dda66c52c167332bbdc90134b53497b00fc7c4f5b9849daf3412940f8d03	1615567507000000	1616172307000000	1679244307000000	1773852307000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	390
\\xaa0ffd576f68bf0bd19385e8492a03215041c582fe6c352e64ea003d413066338a14073111e417ee013fb473ce191ce1bedd91ac321c6133d2f978529001d852	\\x00800003f1b1950507a93c4121fcf6fd20b82ad997296aed7c230e1e510dfd38c906a571aa5de9c5ad4dfb6e1dbd5f310f9d7ee243f72e5eaf3e5062f137a8232770f0391575bc23e2919a9426f92c427c983b5462fdf9e283ab75095cc820ea4793e87ca3e36201dcc84ea73055048361f5be1bc7b532f89294f6bbc5202a795ec4aa05010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6e82ce01a746cfc5baf47ecc075e65751f16f22a9d2a0860fa597e8b43e82633fbc5322aba7fdcb522782538746e7caea607a3976f486bdef0786d8f6e1fc70f	1630075507000000	1630680307000000	1693752307000000	1788360307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	391
\\xacf3bc0ec1cffb231a16259f20e2072b2efe4b84ef280c134734a3e5fe41ed688666b25b862e97f64649171c3793a83134ec8101ab69b66e66af02b49e886704	\\x00800003b0f4fb1a4d1cfe4cb2a7b9fb6ac1195cbb46dd452564991f20c5f9c2d1e33c700c3acb18e35efb2d4852ea5378a52133ff7f9a5a451ce7451754c4834c828344a5f11d5a94d4a33638513f218c2018617346d6c33c4239dbd85adf7d8648a08505f9221e589c3f174b91dbc9f0523a3fcc16459beb64727b512e18cb8de2ab5d010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6fc62c19f5b9fe855d7e37e7c21498ebf01a696521a3b196acbf4d669e01e659e9c44b1a801c5caf335d756741d8404ed0e83717e790cdd859c24f1177beb00b	1636725007000000	1637329807000000	1700401807000000	1795009807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	392
\\xacc3b0464837679f1b2081b86b971a19577c901fa3a88c5f19699cd54659c5fc1817de8ad52ff943c18fa21fb1876eb8057b4419017c35734c6788972b396a0a	\\x00800003e6f41f5d1302bd93916f73973c43b83dda6d78472db479a0783e5b84bf0d90c3e0c5e8c9a9f6a14f3def8ca2ddc7e14a1c3caf1125785d1c9d7cf8637e87fcffc0cd95173e816957d458a312c3fa420d8c3c31cae1383636c89a45e6422b0f7221a5cc0bb63decfe170d3603103b9ba7fb3c1d5946e7a9f86c43d1f87ffaeb53010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x961aa59630127df52e6faf87b43ac4f9ddcc3a91cb92307d83e06921da5fde3ab7a20002a30d801453390004ece8d22ad5bfbd3b146797d46f79de753a449605	1617381007000000	1617985807000000	1681057807000000	1775665807000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xadcbf21e3f040c78bcdc4533de78a404b25099fb4fc6642e3039328f532f24dd8d585d22424b521201a3d588f82ae5a5791e0c24887bcbbe9132afb414b685aa	\\x00800003b921805849963e77d49e2824456f1ec22162c0f3b762f9be9b2cb982b253d11f564a50a523a67b5882ab3e9fb30276f56d211a5e06dee28a337ae85e6a401748a00a5ca81ff6abba89b14e976e77edd0d2c5eb51df53dbd1aa78e2785eec3a048491b60b6d60443b1f6b16da2738d7a24c60d5cd7913441f629c6e52d2da6a47010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xfb7d9b85f359c41c6f708c5c3559daea2ccab5fad90e790c1ad171ae18f96c213404071c44f8a8190f3cd38c9c1a468f6654705223bf51433d2d3fc85853b209	1631889007000000	1632493807000000	1695565807000000	1790173807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xb07fb6188e2e0184ba907a8e54cca0e2beedfc2e54a43a7065097a582394901bd146a3fda70c09e34a2e4aeef680598a52bf8b264428b9662afacbef084d3aed	\\x008000039af85c0266f753719916c43753d2f3fa60064de02de76a8b32696e0bbc75b1d31ee4c4195a8505fcf142e0484985c2dcfafe6fa7fb8a361a1d4f5250d03c372972083dc09ed43c2cc3268aae2e5c84cb66240346298dc24ef63fd47edd49999a2f5b98acb6d2fb7b759265fc01541615f378309bd5999b38c17601e7711bb781010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xe67c1a60b59f808719abd6bc2c0b156d467431b348cee3e5d41ff9692c827b48b66c940b18b12b2761a1b117b22b73f7bdac9a11397351502cb861d0c4b37303	1634911507000000	1635516307000000	1698588307000000	1793196307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	395
\\xb0abb452da79064d5fe2376fbf2855cf8a64f2302c0abe0255c0bbb12a9a49c11cfc37b636c32483d904021dcae9c7500c65bfea5d646e6196a66e97d0b4332d	\\x00800003b66894e6f81bdb2be7c12b911f65e2cda868356c403a814d37dbabaca76816fef2a3371e71257539ab31af6a6cfffa34ce8c408b8c7779421e65fab037741d158432cdb4fb13949a687870fcbe0ef4509adb7dc20540f28b7eaebb64389a3dcf41c3e088417ef67b87d9f1097903a3105b25743a27913064c690bec05131ac49010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x124f68bc23ae2b8f36da838f92728e97a7071fb0f034f688e0d419ddf76dac989d0d44614ef742e46076cf0e9fc30f5760553fa6bb2461f61e8d365468bd1c09	1624030507000000	1624635307000000	1687707307000000	1782315307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	396
\\xb11bcd47c801bde8aa4a09b6bf23f3f51a23b49de27c495c382e8be79649850bcf32af979407b5cc92e5e422e7ec1b8c395f7ee53cac939f3fc7cca8c5c2f546	\\x00800003bd241949881deeb61ed0350f0c793f162f7f738d41368697d5658239491307efe5db6a71cdf1e60c9db964daf40047b0f4687529a59e49fdbcdf7817b9cbc1bdfd9b663b80a6aef5c17a66653b5dc85a9eecf4412cbc7651d365f266e54e8adca4c944e0bd52cc619498d0a1e7bd1e07d30dfcf72be4c11cadda0a667fff0879010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xdee4641599e9f47bc7a13c871ddd2b719806614370230ffb152da7113e0386c33c222223852c7de8905f744d469e15aa00acf94fcfab3e1c3bec6b1b176d320f	1619799007000000	1620403807000000	1683475807000000	1778083807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xb15ba9f72a04faf0c2504cbcda07c406641ccb230268cfd1fd4658b0f23f5551800221459680f4ba591b09dca92647f37d10f249f141b8f2439db24fe6973a4e	\\x00800003c77724f1990ff122a1207d06877bfbbb204f2ec2cbe6c586272981158cf5d46498a3632b170ea22bad88a927adf38163c1b2a21608c8cbc93c4187532eb31116521fc8ce2698f16f528a1721fd5074a7eda7137b1ceaf34a5b3b6f755f7e582c886fad61bd618636e4019f91d39ca4a6f18ed13d1b2b66ba0fa0f6a5e99af55f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x60f88d02ee14206aa286ed757c88d310d5c08c4430846ad3e61ee6d2f6e059911b22f2f551e335c1c7a7be7b1efeb806659a750046113c09c53fb9e6e56b1706	1621008007000000	1621612807000000	1684684807000000	1779292807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	398
\\xb4afc603293866fda6d193676a1fe6c400b51191422d0beaf32d5b3026f8133f5a9f375cab4dc25cf54223674c005fb1678dbddca551c484cb0d74f82e442e16	\\x00800003e4a98aa5a50a2b6dcf9d749a73f3e76830deea18f2fb13bc01950efd2f622cf2b1f54f9ccab6cf7eb0733cb6172d6834d829e698463ddb74f3baada1d2a35843da7e3292b0aebb6bac1cf005d21652c3d89d46379b2a419dd227a755092ae333152bfa73695341c0b2c6489b6583d186cf7c659eefb99c5c5ddc1fba96741065010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x98397229904cf2e79c10da3dee42e279affb065827caafe70d0c8e46901b35e2abb2a2663b36eb80cfb1a9bae645a0ca9e8581fbd5ae7b2fca82554387fb100f	1624030507000000	1624635307000000	1687707307000000	1782315307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	399
\\xb593e71c2ccb03c9e6a18fdfde190c5a69d7cf1df76a137804f79a797bf9098434fb8802895b13a246d9656ed9189f21a2aa53ab663a5ad6531c4fe8351afa73	\\x00800003d466aa2d485ac86ae81bf253d7351edee12e1008fe19e7be9653e236083bb3dd283cef880fff02f5b7896c4650316b236a43e432f49691a1786b488457e0820c98e9d193133fbbfb64d954584dd8e04b3a8c98ab0870f3f2334e4ffd6476b0cb5451a3c4331759c8eac26208ce9b4e9f6d2e704615cb4549267be62271cc7df1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xeb71dee5a3e6574018d9ff544410d3c03ef3ede33cf34d22d8e432d8bc055e2b948fff1f6efb93b9f51fa0a9dba78874db0d89a9bb0aa6e5606225465380970d	1613149507000000	1613754307000000	1676826307000000	1771434307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	400
\\xb6ab29aa48b516679fb3ff634497b2b5aa334c3f48216e07992b8f8bec5b644bbe772b7c093072d0ed50cec4a58df7fc47bcc31cf3403f4e09226ef8eb649ad4	\\x00800003bed1d2f32b0119a928420f2ad062b064c2d3579bf07fce9dd185f8bbf6c7bf832f3418583426c391b90266b36ea3c15648c5b5bbd184ef8e23d5c3153042210c2d9f18c3be5e3e7b7d88899de0eb5a5dce1f797305e2c4d5e1946e15606a9d35e4bf7149c4dc969026003a6549c5b57ae5a23a15c6d5e4c8dc57fd00cb7d14eb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xceef9bd1725cbc3955f9f3cff5924ea5392263b4867e88c06dda1c9b31a9bf0cfb06dec40abdb69fe7689349f069d04bca8e6026b029a9b6b08c731c134b500c	1636120507000000	1636725307000000	1699797307000000	1794405307000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	401
\\xb7afe1e62cc32ffb0689ad0e08a6b551f6973b6ff41a12711a6d9b72f9dbb543508872ddcdd0d37eec36eeabec2dafc2d662260834c8c7718db6e12148047bba	\\x00800003ad582ea40ae7b6d4da33912931933eb97a43ce8160e36d6b36fa0411d2fed9acfa76a6a5eb4d4eea8a3c9ebdabbbfbe8a5da4d41e95c7b2fed44e1eaa64347b00da90b854dba1abdc2fa08465066489f1dc0859598aeac37b8fa0242cb0c894e2a2b12512c8743e5c6a62864ed145e0fd36f95c70f14222282c4c6787fc9616b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x01576875ed6abf91ebc58bdb0efc09f99226beb953b430f65f65028f35ed02559dad8c745b2a8a7b3f95aa0153edc3bf4796fb0b48d1ef13b515ba576838d305	1618590007000000	1619194807000000	1682266807000000	1776874807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	402
\\xbcafc018632e4267e4c591927e545527089974219bf011a0576ae16a5dbfa70cb94df20410cc63360a0a9e0f10da9ff3b7c9ccbc6a57685f25f7eaca74b79acb	\\x00800003a0e5615456404f98fe9d8ddf8649e5cabbdbc35dc2720a987b29bdaf85725073351afbd6dbc82b73d449aba20a38e8001f1128ea898ba0321dd4b016e1e834c3f20c58811dfb41c7df2a49ec760dabca00ff81d927061333115cc51db7ae35f111b16ef607962ae5817943762fe7ed36c6f5e107029ee39d62b5bf17ce0e1edb010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd7a07c1a0d139e2f6e30e8bb0fb31ea8600d5ce38b5e1ac496061a2a614cd6d630fc1dbbbd5ab2210b690dd9355a531164af3310b6fea450379846a5c93ead05	1628866507000000	1629471307000000	1692543307000000	1787151307000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	403
\\xc2177e2e0a4855f8fe03de5fd413285cc63a07be92eb0d047a438d15f7e206312a34cd4196395d2e2b85817ea030f18b6367dc37f992ffa4e09412be92b2371b	\\x00800003dc257972383d7095dceb8954b960e968c5217e355eab9d79a8430c7497ceaff64c8ab5d72044f53b79ffe3234d148fbb1412a9f9c19921da1a48726febc4f2bd003e26c078f46d3c48509592ab34200f763c432bc40b4980acff3603fda2748b3daf045b27eaf1eb08b63f86e95d0268de482eea3fdfe047fc178458fda8977f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xd98935b93697eee83c5a62dec8f834522048eb96f5f14ce3de4120302a2d537ddbcf02443e4e404c8a8e6438a5c2dbfddf0d0ad6cb10db47464213bee263520c	1632493507000000	1633098307000000	1696170307000000	1790778307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	404
\\xc62f1e5c94265d17081ec0f6f6b645dc83055dfbdac4e165620fd525ad4dc5a406606b4ddf7ad6c3979c04393b19a50695ae77d6a940d541c83abcdad6c7a9cd	\\x00800003f44b444689e8264ca84617aa855b973787c1d066511f1f923ec9cf2e18702b6e45af7ca5e06ba41c27dd46b0b747cabd9fbb5d84fbf1c8d23f56e0645323257ae3c503d842b6a4afdda154fb88973aa7113a6f44fd4506cc27a3af2933baee2872bfcb277b64445491eae7eb43d0614ccc05a21ae5a10f8e97712fd242928e71010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x67b41cbf6e1ff931e25e42a13b1ecd108d2670445ce6a78be9341a02edf16d5e56aea25f39042713facb21ab81367cd8680bda7d21b3e5f1f72b9b429922a40c	1639143007000000	1639747807000000	1702819807000000	1797427807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	405
\\xc7ab1bc7e03a1955ad23d52d7967e96c190c41400d2e2871196c92dc1b82833f509b08ad0eac4f2049956d3f521dc82fa1a81deb9f560c8da1d8202aa5756ff0	\\x00800003b64643cb8f3ba8b546e59dd56d6c1920a41afeb50eed5f32e62a2fd19d906b155a8f3c2e05c9be2e23f1ad9ed82e008a53e4bfa195eb8b78f18d038ea7b55d17cb24d2eeb1cc41b2eef479883aca0ad881c21afa5ff199440a4ae7b1a5ffebc18eae458e1e93f6e189c6c736b3f40fd134ab5bb654afd536204c3d3c8866b8f9010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x295f43e4b3fe101f2ee7909a8fc419197641a598941ee154fc88466b1b5ff9a7b4b9db28608453e4a6eca34dabea62d53669efcf3933c6a5410ba22638804a03	1637329507000000	1637934307000000	1701006307000000	1795614307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xcf37bff881aa266def4750b9551e84e74646402fca034c18c5b5ed43ff7431a35cacc439fc96e03c3c777924dda2dd8e5df21cb2da4d63dcfb78ecbee62c87bb	\\x00800003d1d907dcecc412d0ab4b68025e050532209ed0f31d5412ef3da4587bb9d9ede34a4e8ef70b63563c68e43338ddca5fd26f3c9fd4bcafb28a42cf82d6f1df49b7d89ac11faebfc835af102b6b9c3955e50b07ae315a1c5f46b0483dd4ba0f90c51932cd4a919469fa9e94fb4037d64bf28444dc58ea981e9baabf752cf5ea9671010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x11ea842fb09a612adf2ebd6c6be91bd56a0ada012d59526ccedb5e1b0554e9a788d2991307f6005767a6ae839ecc42c723de00a2ce46370dbbd01540d0deb504	1628866507000000	1629471307000000	1692543307000000	1787151307000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	407
\\xd697320c6f5c00733ca0442e29a2aa28e5dc4481151d6663a8b4d80043f05740706f38c39c109e4002175cdb516ff361d09068828539c0ef8d1493e5ee62b0cc	\\x00800003b6ead35001abcffe865dac91387faeb118aafd3b445fc2035b4df03dddd8660f1e563a3fe5a1e0db227d176f90df1362308e5c848a9e98893fecfd6826dded8504b6161b1655dacd4ce06d516708209d07961e772590280bfb94b2f1001d1287d31d2c202c53f9f3c8e62219a216a2f676b1251d9a163ed77829ca6d2e011307010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf0234290a5f45116aa56e50c1363172eee7bd93a554cd9beb3f4f2c1c53e56358ef97d5db6ce829b95369a64a890684a5c650705da5f332a4261675d25d4d00a	1633098007000000	1633702807000000	1696774807000000	1791382807000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	408
\\xd8b7bc04d843b1f34a8749db184474c29787f012ba64a763e6914c3ec6dab68f1653dc13bcb3c817f81ff3a646a64136c28111061993aeed0f0ce959a8f8e97b	\\x008000039da02250c42ae8aa6d47bb580bef349840ed1fcdb165a573d726f970f28129a567c20e1fc7d9b103a2cb7e2952db7fba071066d45b3ee81838f44d2ce88140e7f272016964ff3e10385cbc26033ff50beb1e0cb7e2fb4911bbc3b547e4e24189abb7ebda80dbd284497e928dc296c265af446537c51ced03d9180fd1f20a2cb1010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf81972dc8fa1f87b05c571ad2f499eabc7165731d5173da1e8b6f5cf4d21ee715e89488733d06636d510a42817ed5df1db4e39e12e362b2f99ad01489433c60d	1619799007000000	1620403807000000	1683475807000000	1778083807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	409
\\xd937d68abebaeb44263741f02c0dfccbd9844f4474c9f7c5bb77554035dabca5131db67f7f2092365da4f0feb271ad2c9ea865aa2b1c05ca4b9744c5b6705399	\\x00800003a9ad0dff3ad01cc248ddeb78bbac6c7efc60bb82dbf92be62b89563dd72027a49267f0c31f40c6d3f450499c5499d0174a27e62bb4d31485a7aeed172f7d7204bef29e8513f018f73be07591195013f7584497ba95bd2795d6b2939e86c06c8f1c72d6837e5c9835f9a76354878ee82d3486b6835c8946ee9cfe4148384f9657010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa2eb366fff08c7350ec670cc79c0e5f442fc18c87ba5ac45aad068b37690e7e9954c2f8f16e0a66bcb069320df7370d0723966b520f36e479a156f11c17d4a00	1639143007000000	1639747807000000	1702819807000000	1797427807000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	410
\\xde7b61b452aa639eb77b9d011c68d7c95594b979b3ec62e80e1cdcc68bc3642de67831a917089260b71c711d34e7d8a341f72a51f07cf34a10f707310ae3ad21	\\x00800003b3cbeae2367ef41eb99e39ea2db77f051c7b0b80fc17641a5955652ca5a8354a510d7f36c852d39958defd32bee8014c572d8d059a455b68964c4d485bbac9df395cc0aef288c90356722b6c95f083562f972a6a2b778bbfe93ab27bd7b2f746ca4493bb8bc092f1248d7e1723be4d52bc4a1469169fb96c4d7f9ee6a755e4f3010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x46a34046d9739b66bb13c0fa7b2c8a6868890367a4cb78f6177c29126b8481e2993f5076926da52c0b74d2859e2a3514d93864bc6823f52667729b202a24a304	1627053007000000	1627657807000000	1690729807000000	1785337807000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	411
\\xdf038fee207cd843a2edf06b3b824192f42694ca166c4ccc1b6d4fa5539ce394f1148d16e672980040f366c7ab5db710dad365b58366d7af783e0be9d60eab80	\\x0080000395e21216a0c4bd8a6bdcff2c1ff75c0ce454b853b36786bac341b41e2827a4d946663ce0c107b8228f9057d7a6d93d42de52f4a7637f41f0bf23d3b77a96851f40321cfe6a3cfd8822801b401cc7dfcbb52fd987701e0e1d1e2dd36ffd00c639e576c8d252ac136d9aee6702e7d3d87db5eceaa5cdc78763292a121eb1b2aadf010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x814f9d26db8e71ea2df4ac5399bc5366e26bc27d55cd7c570581eaa31f4069a1920b272d7068f15e6a2337a006db09cd643f2e024c41375a094019994b05430a	1620403507000000	1621008307000000	1684080307000000	1778688307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	412
\\xdff32e247598860815fef820f23a97c37ebfb30a3deda89ddc11849b50f9a3ae0eb329e0e0cd21acad8b70abd6180085d859b641cfd7583081fd7c9877bfb7d7	\\x00800003e6d8eb69763e427327968e773d82de955af91e7e95b46df8ecc6e199e39694a5fe3a2c2bd6a326c8f6171141af4d562d28c7eff54a5369f9b0e9280f2bcaf69a10c67cb1c41a62365c052daf577a20e2abcf1301c842990363c9c4e9f104c0c86d7f448802170b3a4be2b0788aace2bd0638418ebe0ec19f62393e0e8047c8db010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x8faf67493f37f8c975b4923be5d746a2e8ca8f94250bae6317f72a747c6ff32e26cdca6a9d058553043cab656bbfeead81be6a1c282ca68805bb3f6411af9b03	1636120507000000	1636725307000000	1699797307000000	1794405307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	413
\\xe493edb426759e2415b4745ec71c1b34ad5af32b164990ccfeb6fde47375db53fe88294c1124da6b675f06a29e44a6b9171ac7facf85f2dbd9d5d1cd942f63a2	\\x00800003bbac9e5ada228e1476c865e9c359a6e429228bf81243cbe4f258272d205e838f14b2f7563c7ef1411d25fe5538d6c0af635f84dfc4568ee0653c1f3310a1c40b6f2862055c47b1856dbae9496203572cd03773ca8067a800f1a497c30daf4f01ba1017f41bc7e9b29ef2af442e8654826adc7ee784335aa6b1e6160e17c13709010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xb20f7149964e00f40ae6fb14b86ca671231203f4d7b6f822dc4d8995ec1f0e376b659c47c8c56c20f96fd5fc18cb99528212fbfd75fc2ece5f05788ca8265a08	1623426007000000	1624030807000000	1687102807000000	1781710807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	414
\\xe65f02398423e0fa047b1a9a2b3f0627bd56c5022a70a119adaed921e4f314e045318290a050e107754a464994457295fcd589b6058667c75c3b731fc793c977	\\x00800003fa68a03199691f5864b449827b427211229eed2f0a2454f9eba418341c83262489be4b1707b4b0279ebdcb684c42666e3b5a6c0b062e3b527b19bc07ce7cb6276abc7d2e503151abc163fe537771fde661c5c24f3e41f7340e34d7e6be72cc73a0e58cf4b3b147210390f364e26c899d3a2d90a5d24325ceeb4cf8ba9f9b4bab010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x79ea6f8454b6744643cdd20c9ae85bfa29aa13c8a82472ac37ded3c08e85b7f9231dea608ee5705671917abd73ce49aabfde577a35aeee9323d21d6d38939c04	1628262007000000	1628866807000000	1691938807000000	1786546807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	415
\\xe63ff73819a0eb117027bf6cd170cf828347b40df9ba8594a69fc8623ae2ca54b092a31ee304d558fea5605c0b51dca5cb95b2a2eb9ebf51f50f2326fbcc5e63	\\x00800003b87551e4c395aea7e78762aab8fa04bfe94968457b9b85d48829ea7472c294f76f991d4823732f8ec477f640d97be0410df668b530631c659ce17c57c84c7ac13fdb666216e4d75b097f62cf99e44eaa009cf27b9cdcd47328b3d80a390ed9704d96a30b36dfc5fd3ef6b50d260cae249422b6707b90c1a8f6ceb4e73bffd9df010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x9941daf99ba05c008342e4dd7e73072e4eaaf692cea7083345aa711fb5c0dcc4e0eb8e2a9963a64e7476a070f319db5a21a936172ec56790a88a941f11c8710f	1611940507000000	1612545307000000	1675617307000000	1770225307000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	416
\\xef5b5817e88c5a7974d2ea73bc5ba9e5a00074e2a3cc439c2cb1edab264b295e1a3a77fd20b5f2f21006fa0193efbdbdcb371998eacabaac6efa347023256242	\\x00800003b587320dc5286e1a71c33df1220a1566382d13ce81ed018fd5ecf4705818fc3d0b3399e10155e932d909ebc350af288bf39a097a26da916946f4520111e4889d7c53199921ba0947f27beb2a24b1cd988bde908afaa1a46c512a8100db1e5660232ef8f02c1ad2d044abd16d68857de695a5adb6e60dc05086ce04c170c20a6b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x6f37814cc2b250ed14385eaaf60607df055ea36be1ae82e4d55e99c411ba16ec27f2db78b865a59cb32b0ef28db63874254c25f5cf06cf901449065d802c9e01	1625844007000000	1626448807000000	1689520807000000	1784128807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	417
\\xf03f0f5499c86feb857bfe90475d319923826d2144285fe2b10afa044f93fe66b3d30326b269a643bdde15576fe92297f4b5f1238948e924d0054ec8afdde4b6	\\x00800003c0e67db2721106d9fba30ecf50219f0cf26a7ef67c9a31a55d7a3e2bfa32a308d7eba274367d99a2e9b6c6b0cd6c937e9f6293bb6b009a0cbee3d4a348ac8502e159d74267ec529f73b2c5311c5d8a3a01831d7dd8222c4e2dee6366b4eee54d4f089c786b2d8967d72246a77619713afca1ea7d62197b884d82eab3dbdcbb8f010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xa3cf5e09ec4944b0c03e80c924b5f9212e3231e4fcdafadc951620deb3199834c814ed394cf7ea0f2cfe0d5f3debd34aa6d89a6683568a2a3dffccc8daae9c00	1612545007000000	1613149807000000	1676221807000000	1770829807000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	418
\\xf3774a76bf570db833fa3bde9b9d75863b93cad9eacf90b44c9a18864041ea5382d799749bc41cf46f80a223d0738fbeedff42578f0a28f672977718331f9dd1	\\x00800003a2b89693f54172057fed5b3d280125917d366594917edad59db5be587493f1c925de018e12d4895e57f77a2473b4dc7dee505afee970f41d8bab9135ed0f65ba23e47afe4c9000e202943086cfe45c3e384ee4fd33067acdfa4eb7f5d4efebc2a70cc8ad3f4f72e445b292b18f98d30840210e49bd40aea74de8365a2558f037010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x3d64998a2fb3ca9f880bd63cd5d5143d730bd47c96f3516d2eb7bd313bbf1e7827d7514a7d326543e58ba334b19debd20ddc389478021d910ae8d639e0204e0f	1615567507000000	1616172307000000	1679244307000000	1773852307000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	419
\\xf5d3eec2756d7ce58da31dc8d3c50d824a5b283464456d93eb6205290afa79c8ba13fd634fc5ff988a57eec13d400adde9f323e3aa4bb2b04e0fb93f6aa4247b	\\x00800003a3eb44995caf63898a33f76862eb488cbe82000d2709ed870e34786c19b36df0d9eab09d5cca99e9ee6de5e6b7dc602641e43d2302fd595e9784aafd756dee1fe6a68f4c5675dd7d317717f03d8790c41b7ff11d9017c036de79c834a76d6e8ac4d5e9c049bc325115858f55e6c8132f7a54a8e67434daff4f35bc4d3042d4af010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x15732b8aa50e23bee8cdaf4c3076f26647f076d63b9c7b769a0f17a17d38a9df68227a464c21cbe412530291fe1c8a16fffeb97dd10951961295d836b9914b02	1630075507000000	1630680307000000	1693752307000000	1788360307000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	420
\\xf86b656e141dc6d31cc527f5b2852bea8903faab1a2b305d12f5d1ba50a2e96e5801895d9ea1fa8ab19f93b5b57e9d7361de945a1db39474e59f25ade2546b52	\\x00800003c8a7aa29193e2bbe2f56fa988c09e8b35a06c5b35e8c5232c22717625152351bfe0592176bd90e937ad86835ad6d57d266cf25a7c1559e731f9f2f569db0d0d7c99ffff251638ebd757023162370d406ce9e91557af9c83eda7ed48e6e837cf07f0de7cebd54b4dc678d0dd9495b8d405b8c55f2e1579860b306a99d8befdd55010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf1a25983ed9989f0dd0f448ef8e82db13ee798d633a6edb4e3fe977a22e9a8a1f108d24c2fc1e56568a62f704a88d70e868de50b6a7802e380a3db4ba855cf02	1628262007000000	1628866807000000	1691938807000000	1786546807000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	421
\\xfce3eceda752f8c9ece27abc027c80516dcb396d8d5c0c689622706fa065683db91db75f5532b50a69b0c58f81ccdaf1fa1530ef33b02d3d7c8951052a45aed8	\\x00800003c8db9381686fd7306c9359b2d74acbfb678de77aae0934366a6a0e6086f64b54d3632aa90db1c09618116222a3d8d49122b7c25016bc10df1e80f0ea07a8e1bd71b79a647fc0c43390992aa19d0b454f4fed9bab96119205d05447f8af694bb040c868ac9c756e6eb6a6ead1696c25c04b6cac8e584174daf0a937b995320517010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x990d93fc73e752dfefca6b1a0f4547b5c0b977c1dddf2720cb4de7aeefbd0e88011e549b89bd67ed953ffc490f94efbedded33f69d8b5f5d82ef3da8d3ca5900	1625239507000000	1625844307000000	1688916307000000	1783524307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	422
\\xfdafb6a1d57c2e6d5645abdd85b3f795f370a4beb57793133aa1442a7fde4ce04c4831291433c8f5a8e56f261579a2295e6394f949440eb22234af7692e37c42	\\x008000039af005c2ed2a2aa8e0503d791afaf1f1d4d8c6513fed930a4132ec5179fe41a3d63f9d25c809e59164aff30e0ff82078d98f755ffc4d95519a854c391a50383887ca249f51bb19b4cfd114f6cb1e6245f53efd2ea4e41de1f1b0aaa7bb0e266fbc797447ffde6a1abf7d280c17886308ff920e7d83b04ed6f6fbe890f2f5d9cd010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x68ee878f48ed05a0f3e9618197879b476b072844b80750a047d9fb567fd7dce8c2f36f62040bc1a80f64d3fa54d88e193d75fb5aa30e5056b069eb197b413606	1624030507000000	1624635307000000	1687707307000000	1782315307000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	423
\\xfd5b25cb9633d1f1ace61e07f3a1e7a505d48aa747d4a56d6e295fda2543266ab2d575a8aef631f48b3984d70c51d212269d2b07372775aef95a41be8af0a6e6	\\x00800003d043a68f31423d54e34436fb4fe6c0394de7e769c4c0f5224f86dc3264c29ebe735061b74b96be47bc4200a7eabc614b79e7aea8ed7851a2830d41bfbce640fcde2ce7fe72902c08bfe83dd3b0ad05fcd67e876c74f6e853a5e57ead24840b533c5b3f995be892efee549407660e7c4d7f4356f5d66679e44f4dd6e51bfd540b010001	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x4151ab9d6a82434c400daca4126616b91daa3224d82286742ca80097400c3eb944e8398c8acf0053734314147771564ffb052bc9585bcf8259a5529279d00907	1622217007000000	1622821807000000	1685893807000000	1780501807000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	1	\\x33e94fe4dc86b3ed919fa19b2e6d06be8ed3a6c7a2d83e068b8a7155976c6989b282358f48de6667a327f5828a8715bc6db1b866c91c530fda7d105597c8f863	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	1610127032000000	1610127932000000	3	98000000	\\x4a86ec7b50e0486df056fd7c5b6d43cc3fb4d3be1bdb173f227fae91a0b68843	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\x86c25713a8d650aaabfc02a9a35923dd2f12fbaa3da35f9d132f09c9a55acf9fdb2f13a8fe0cb9ef83873aa1fdc78cdc987a17651788959aab91052848736c03	\\x21797ed983fcfb62180fed15432a856ee6f1d567ece6d14d1bc7810a37eea495	\\x297ec3e40100000060deff6b2f7f000007cfaf754f560000f90d005c2f7f00007a0d005c2f7f0000600d005c2f7f0000640d005c2f7f0000600b005c2f7f0000
\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	2	\\x6272f032079cf53aa5e0d4425e1dd812b88ffe70cf189d37d91aa306301d1f43c183fb4aeaf264eebd72d674577b6034af897cfc3e251267f3051a24209bd576	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	1610127040000000	1610127939000000	6	99000000	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\xe347bd4d0a1682d5d28a4745b9441f69f46142b93f2aa2e14e72890383eba95b81f55c86a39764780b0e29c26ca904e448e5def826717920f9d2df17bda33809	\\x21797ed983fcfb62180fed15432a856ee6f1d567ece6d14d1bc7810a37eea495	\\x297ec3e401000000608e7fc92f7f000007cfaf754f560000f90d00b02f7f00007a0d00b02f7f0000600d00b02f7f0000640d00b02f7f0000600b00b02f7f0000
\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	3	\\x6f311d077eea8eea5e1396ad6e30463b4729ab760f29c4a7e6cda2a2f98fd0bd5f5c18130b60d831a9694a6f5daac68aec2a9d0f5ae665eae025ac599a9d521b	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	1610127041000000	1610127941000000	2	99000000	\\x30b3d7274aad06ab9cee4126764ff792f2c07ff2d7cd561a9a9193dbdcf6311c	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\xb66e11f036ca5a7e731b80edc53a8c7273184605a3d5d80f30da81524cc6c2fc2676acc2475aa8ebc7900e8dbbb2d0c10073a2dd913c190ed44dea0123fbe103	\\x21797ed983fcfb62180fed15432a856ee6f1d567ece6d14d1bc7810a37eea495	\\x297ec3e40100000060deff6b2f7f000007cfaf754f560000590f025c2f7f0000da0e025c2f7f0000c00e025c2f7f0000c40e025c2f7f0000600d005c2f7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x4a86ec7b50e0486df056fd7c5b6d43cc3fb4d3be1bdb173f227fae91a0b68843	4	0	1610127032000000	1610127032000000	1610127932000000	1610127932000000	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\x33e94fe4dc86b3ed919fa19b2e6d06be8ed3a6c7a2d83e068b8a7155976c6989b282358f48de6667a327f5828a8715bc6db1b866c91c530fda7d105597c8f863	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	\\xcee46869ed9d2f2e56e228dc38965f52238426efef4bee9645c765a0bec6a93d9c130d92f0fe57bfe6071e247c3219fca29266c7f96a470bc727a63f7b03ef01	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"XM1BXBHY6SP5ZYXV4WQDZY6D0CG99TDR69TBJ6MJ7G4316MP4WCWBD7P635HE5WGJFDMQZG3WSRB71VDA789BTVQVFGQR38R7AWQXY8"}	f	f
2	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	7	0	1610127039000000	1610127040000000	1610127939000000	1610127939000000	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\x6272f032079cf53aa5e0d4425e1dd812b88ffe70cf189d37d91aa306301d1f43c183fb4aeaf264eebd72d674577b6034af897cfc3e251267f3051a24209bd576	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	\\xfff83580fd10c60d5379ce827f7f04b82a29e07ff2e69d4c615c737d61c4df54142012008b773d1de87f9f94c21d6a1033980339b20937aef48e9c9220180b0c	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"XM1BXBHY6SP5ZYXV4WQDZY6D0CG99TDR69TBJ6MJ7G4316MP4WCWBD7P635HE5WGJFDMQZG3WSRB71VDA789BTVQVFGQR38R7AWQXY8"}	f	f
3	\\x30b3d7274aad06ab9cee4126764ff792f2c07ff2d7cd561a9a9193dbdcf6311c	3	0	1610127041000000	1610127041000000	1610127941000000	1610127941000000	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\x6f311d077eea8eea5e1396ad6e30463b4729ab760f29c4a7e6cda2a2f98fd0bd5f5c18130b60d831a9694a6f5daac68aec2a9d0f5ae665eae025ac599a9d521b	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	\\x924e199eb6f5d90a51a799f81761d6243aa64a6421c4361c5c18c9c3c6b271076364cc31c40b43a2e7d24e53e0640593359c9ae063771475db0c2e7de02d3a00	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"XM1BXBHY6SP5ZYXV4WQDZY6D0CG99TDR69TBJ6MJ7G4316MP4WCWBD7P635HE5WGJFDMQZG3WSRB71VDA789BTVQVFGQR38R7AWQXY8"}	f	f
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
1	contenttypes	0001_initial	2021-01-08 18:30:08.118669+01
2	auth	0001_initial	2021-01-08 18:30:08.160084+01
3	app	0001_initial	2021-01-08 18:30:08.208854+01
4	contenttypes	0002_remove_content_type_name	2021-01-08 18:30:08.230348+01
5	auth	0002_alter_permission_name_max_length	2021-01-08 18:30:08.238714+01
6	auth	0003_alter_user_email_max_length	2021-01-08 18:30:08.24496+01
7	auth	0004_alter_user_username_opts	2021-01-08 18:30:08.250233+01
8	auth	0005_alter_user_last_login_null	2021-01-08 18:30:08.256104+01
9	auth	0006_require_contenttypes_0002	2021-01-08 18:30:08.257651+01
10	auth	0007_alter_validators_add_error_messages	2021-01-08 18:30:08.263775+01
11	auth	0008_alter_user_username_max_length	2021-01-08 18:30:08.27847+01
12	auth	0009_alter_user_last_name_max_length	2021-01-08 18:30:08.28761+01
13	auth	0010_alter_group_name_max_length	2021-01-08 18:30:08.29995+01
14	auth	0011_update_proxy_permissions	2021-01-08 18:30:08.309696+01
15	auth	0012_alter_user_first_name_max_length	2021-01-08 18:30:08.316123+01
16	sessions	0001_initial	2021-01-08 18:30:08.321187+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x21797ed983fcfb62180fed15432a856ee6f1d567ece6d14d1bc7810a37eea495	\\xe076168ce0cb972a2881af2452071ddf3d25cab55b0aab96a4f3c1d0c6e12e31e7576de5f48253e43a15d50e7e43e1b62dda1ab9e6f549689c9205415ea9ef0e	1610127007000000	1617384607000000	1619803807000000
2	\\x03d62327525c58c8038cb0d30059891d1881e109596a328cb7f4f5385116acc2	\\x033a9308ebe8ac839c4f369acdabd9bc0e6d5bf05298285effef3363765b3988142ec6173d276bb458bf2abf601355d31e1e99d34bff4c47f3d0f8a8952e2606	1617384307000000	1624641907000000	1627061107000000
3	\\x2c9442f7937b062b9d577cd87848c51ad564fec921fa33e562f9631cd42b0a58	\\x736b0eec4eec90e27f61bca53fb00414aea3a70a765101b85dffc7051d381c2813236cde810c002319c8e628bd8b76476a7a2480f49d1d87a686c3f05a8e5600	1624641607000000	1631899207000000	1634318407000000
4	\\x52485f5ba101908c600c05adb0eb734bf75d7ff4433b8ee96e5e84c755ec5a3b	\\x4e5abbe1646ac19eaedfe625d5b8958e4b708599eb8d0408e776e4b7d9d1516dc77b4cd0c51b9ea9f95a882193bae6cf5a927a2183b8151d322dd9548f89e106	1639156207000000	1646413807000000	1648833007000000
5	\\xf3db37406eae1f0599029e423dbd3ba365d3a1c7e6dbdc26477a2b9c2caca0c6	\\x3f1284aff7078f66373c2fff902511c405410c2994c8272d6f813e77d42bf587cebc7f9c5fc015e4b26d48c1a25b09d9afbf6c0bb237e7214a8d21e744f2e30c	1631898907000000	1639156507000000	1641575707000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x4a86ec7b50e0486df056fd7c5b6d43cc3fb4d3be1bdb173f227fae91a0b68843	\\xcb3cc31b6328d1821446c486a9553b3bf9d9a293d02980ad356f565410a87256414b38bceb26e3dfcbc3ddd277446a596de6052aeae6742cab782faea33cbb78fac9d1821d52dc324670c2cc2b47039f9cc2422c94aa16c4a62725056296a1773b87c1de76bfb1368841a9788307377d43981c21605bce69c93e733e2fe2ae8a	165
2	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	\\x615a34735672e47ed45c4e89d2c33330c13070463f32e7d44d40944b1f536f493225c5ca7f239633f42078adb0f2dae0438cb5b3efcebedaa80953d9d54fde9213fdccd4906d51ca24fe0038b87c67d60c90e465a64c4e348c1dbe644a8e87f66d4293fb36e0c303b441edfc3e2ed3416917b9e880e1b9a8f542af72f32c1124	116
3	\\x30b3d7274aad06ab9cee4126764ff792f2c07ff2d7cd561a9a9193dbdcf6311c	\\x7776ab61fd49434aa259c636db783d18832a74f30b199a24f31c3bd36d858ab8e4a0ebb7ca1020ff3e6da8c7f7f73e5d6c617c1824c44122481c50172c7d5f22374e04d87d5172abb6654dd21248bfd3e810f9ad0bfee50afb2a3786628d72468287b34367cb27c8bde9145a50e669a18b40266a5128895605274df410d962ae	330
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x20a2cd876bec48699ffc3fb453bdb2710ba6390432cde33a5bb5d4d35db49f28804e7ff9ed5d0371adaf87b7fe2c1dfb5e9a1e244728c9cd1990f2824395f095	\\xed02beae3e366c5ffbbb272edff8cd032094e9b83274b91a923c08309a962719c5b4f630cb17179093db4bfe03e670b3876d51d095eb77dbe17c0d183ab97ef9	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.008-0286826D94S88	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303132373933323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303132373933323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223432484356315642584834364b375a57375954353746444a45343554434538343642365936454a56505141443651444d4b574d38304b4b5a5a37504e543056484e50515246445a593547455a50514d5433524a3445413639534d435331574d323845415a313538222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30323836383236443934533838222c2274696d657374616d70223a7b22745f6d73223a313631303132373033323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133303633323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254453551514433573451365046523757354650364837425848444b343848585a4b563846464e595337425459445959544d4d5a30227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22464d4d5147473959453743575259304d56544752485134584a4b4e4d43414438415a504e4a524e344344384148364331515a3547222c226e6f6e6365223a2250474d4e3532593244524a3358565135454d384a384e5242343530414156484334515042414e5959374a47563933445933585647227d	\\x33e94fe4dc86b3ed919fa19b2e6d06be8ed3a6c7a2d83e068b8a7155976c6989b282358f48de6667a327f5828a8715bc6db1b866c91c530fda7d105597c8f863	1610127032000000	1610130632000000	1610127932000000	t	f	taler://fulfillment-success/thx	
2	1	2021.008-03WAN8KWFDAN2	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303132373933393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303132373933393030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223432484356315642584834364b375a57375954353746444a45343554434538343642365936454a56505141443651444d4b574d38304b4b5a5a37504e543056484e50515246445a593547455a50514d5433524a3445413639534d435331574d323845415a313538222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303357414e384b574644414e32222c2274696d657374616d70223a7b22745f6d73223a313631303132373033393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133303633393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254453551514433573451365046523757354650364837425848444b343848585a4b563846464e595337425459445959544d4d5a30227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22464d4d5147473959453743575259304d56544752485134584a4b4e4d43414438415a504e4a524e344344384148364331515a3547222c226e6f6e6365223a2243523550443637324e4243394135434a42345346473052584331544159585142445330515452424d4a4543544a4e593845444d47227d	\\x6272f032079cf53aa5e0d4425e1dd812b88ffe70cf189d37d91aa306301d1f43c183fb4aeaf264eebd72d674577b6034af897cfc3e251267f3051a24209bd576	1610127039000000	1610130639000000	1610127939000000	t	f	taler://fulfillment-success/thx	
3	1	2021.008-03EDHK38DSP6C	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303132373934313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303132373934313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223432484356315642584834364b375a57375954353746444a45343554434538343642365936454a56505141443651444d4b574d38304b4b5a5a37504e543056484e50515246445a593547455a50514d5433524a3445413639534d435331574d323845415a313538222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30334544484b33384453503643222c2274696d657374616d70223a7b22745f6d73223a313631303132373034313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133303634313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254453551514433573451365046523757354650364837425848444b343848585a4b563846464e595337425459445959544d4d5a30227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22464d4d5147473959453743575259304d56544752485134584a4b4e4d43414438415a504e4a524e344344384148364331515a3547222c226e6f6e6365223a22314e50564a48333138305750374b5342364753435248415854503944514254433858534d31485946384334473952585131353830227d	\\x6f311d077eea8eea5e1396ad6e30463b4729ab760f29c4a7e6cda2a2f98fd0bd5f5c18130b60d831a9694a6f5daac68aec2a9d0f5ae665eae025ac599a9d521b	1610127041000000	1610130641000000	1610127941000000	t	f	taler://fulfillment-success/thx	
\.


--
-- Data for Name: merchant_deposit_to_transfer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposit_to_transfer (deposit_serial, coin_contribution_value_val, coin_contribution_value_frac, credit_serial, execution_time, signkey_serial, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (deposit_serial, order_serial, deposit_timestamp, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_serial, exchange_sig, account_serial) FROM stdin;
1	1	1610127032000000	\\x4a86ec7b50e0486df056fd7c5b6d43cc3fb4d3be1bdb173f227fae91a0b68843	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\x86c25713a8d650aaabfc02a9a35923dd2f12fbaa3da35f9d132f09c9a55acf9fdb2f13a8fe0cb9ef83873aa1fdc78cdc987a17651788959aab91052848736c03	1
2	2	1610127040000000	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xe347bd4d0a1682d5d28a4745b9441f69f46142b93f2aa2e14e72890383eba95b81f55c86a39764780b0e29c26ca904e448e5def826717920f9d2df17bda33809	1
3	3	1610127041000000	\\x30b3d7274aad06ab9cee4126764ff792f2c07ff2d7cd561a9a9193dbdcf6311c	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\xb66e11f036ca5a7e731b80edc53a8c7273184605a3d5d80f30da81524cc6c2fc2676acc2475aa8ebc7900e8dbbb2d0c10073a2dd913c190ed44dea0123fbe103	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x21797ed983fcfb62180fed15432a856ee6f1d567ece6d14d1bc7810a37eea495	1610127007000000	1617384607000000	1619803807000000	\\xe076168ce0cb972a2881af2452071ddf3d25cab55b0aab96a4f3c1d0c6e12e31e7576de5f48253e43a15d50e7e43e1b62dda1ab9e6f549689c9205415ea9ef0e
2	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x03d62327525c58c8038cb0d30059891d1881e109596a328cb7f4f5385116acc2	1617384307000000	1624641907000000	1627061107000000	\\x033a9308ebe8ac839c4f369acdabd9bc0e6d5bf05298285effef3363765b3988142ec6173d276bb458bf2abf601355d31e1e99d34bff4c47f3d0f8a8952e2606
3	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x2c9442f7937b062b9d577cd87848c51ad564fec921fa33e562f9631cd42b0a58	1624641607000000	1631899207000000	1634318407000000	\\x736b0eec4eec90e27f61bca53fb00414aea3a70a765101b85dffc7051d381c2813236cde810c002319c8e628bd8b76476a7a2480f49d1d87a686c3f05a8e5600
4	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\x52485f5ba101908c600c05adb0eb734bf75d7ff4433b8ee96e5e84c755ec5a3b	1639156207000000	1646413807000000	1648833007000000	\\x4e5abbe1646ac19eaedfe625d5b8958e4b708599eb8d0408e776e4b7d9d1516dc77b4cd0c51b9ea9f95a882193bae6cf5a927a2183b8151d322dd9548f89e106
5	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf3db37406eae1f0599029e423dbd3ba365d3a1c7e6dbdc26477a2b9c2caca0c6	1631898907000000	1639156507000000	1641575707000000	\\x3f1284aff7078f66373c2fff902511c405410c2994c8272d6f813e77d42bf587cebc7f9c5fc015e4b26d48c1a25b09d9afbf6c0bb237e7214a8d21e744f2e30c
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xd38b7bb47c25cd67e0fc2bec689d7d8b664447bf9ed0f7d7d93af5e6fbdaa53e	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x7673269a24f57e3dcf09c917c2cdad26a7cbaaea3b6c229fec460e313a90c7db49006862a33246ec7ce172a9578874321e8309aeb4f7a2a0a70ff427ccc74c0e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
\.


--
-- Data for Name: merchant_inventory; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory (product_serial, merchant_serial, product_id, description, description_i18n, unit, image, taxes, price_val, price_frac, total_stock, total_sold, total_lost, address, next_restock) FROM stdin;
\.


--
-- Data for Name: merchant_inventory_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory_locks (product_serial, lock_uuid, total_locked, expiration) FROM stdin;
\.


--
-- Data for Name: merchant_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_keys (merchant_priv, merchant_serial) FROM stdin;
\\xf84be382b6a6e8c689bbf6f0df47e47cfe2275735fc58aa2b1c94c8d60fa1f61	1
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_serial, merchant_serial, order_id, claim_token, h_post_data, pay_deadline, creation_time, contract_terms) FROM stdin;
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
1	\\x0a14525a295bf9718c358043349e55e4beffbf3485d09afca19886ddf42a9a1a2780c98eedbc92b6bb367c680375959510844b79f49d664ad79775f0027fe60a	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1610127040000000	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	test refund	6	0
\.


--
-- Data for Name: merchant_tip_pickup_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickup_signatures (pickup_serial, coin_offset, blind_sig) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (pickup_serial, tip_serial, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_serial, reserve_pub, merchant_serial, creation_time, expiration, merchant_initial_balance_val, merchant_initial_balance_frac, exchange_initial_balance_val, exchange_initial_balance_frac, tips_committed_val, tips_committed_frac, tips_picked_up_val, tips_picked_up_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (tip_serial, reserve_serial, tip_id, justification, next_url, expiration, amount_val, amount_frac, picked_up_val, picked_up_frac, was_picked_up) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, execution_time, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_to_coin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_to_coin (deposit_serial, credit_serial, offset_in_exchange_list, exchange_deposit_value_val, exchange_deposit_value_frac, exchange_deposit_fee_val, exchange_deposit_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (credit_serial, exchange_url, wtid, credit_amount_val, credit_amount_frac, account_serial, verified, confirmed) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf, failed) FROM stdin;
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
1	\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	\\x4a86ec7b50e0486df056fd7c5b6d43cc3fb4d3be1bdb173f227fae91a0b68843	\\x15df784b538147520a9c9041c4d7bf97ae3e010d9604221a70265107166cfabe4a64bfc7e942e16334400dac652d1dc877dd0f69cc64601e844ca5494ac00400	4	0	2
2	\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	\\x6da0e10eeb6bf6e539ea6f7ca809dfab38eda52418c9bcc64b9afa9d05cce4e144322e01f320907c608f487b22725663f7c6633d2f2e93e0940cf0a90afe6002	3	0	1
3	\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	\\x1c300ce7a5e2d8e737bb158828e3fd4d669a4352d937a5c4e432f4db59af645ebee33b50edd68c505ed727d3d6212e033c60ea7d007ec70953b7c65ad7348406	5	98000000	1
4	\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	\\x30b3d7274aad06ab9cee4126764ff792f2c07ff2d7cd561a9a9193dbdcf6311c	\\xdb9c3dbe9699fd133dfaf549b4f994af1887fd6940335faa757c0609c921258fb7b1abd615cabdb3630b4a7aaf0dc27d7bdaefa0e862bb501c03e7839c587607	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial) FROM stdin;
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	0	\\xc802a7236ae4e5031a315d03f55a6ede157e115b0eddba2a165c5412bc47262430ef3d89396f14752db8ce26006fcd7ccf922a7c894fcc7cc744ebad46bc6801	\\xb53128aafbff02b3bcd3a98df325088833d3bf00867090dac4a626d1e72dea4333b960cfeba7049b23e358a59157bdfc40a61f491cb9a5fae5c3206c99bb91c433732b341919eb05444a3c836748c6ddb27564d0dbf0b3294a0282223b6cd51208d5a1f89a1a2ab6a3bd2ea75b20e497630e31f25e3470c9dce448e83d81ddc8	\\x4399789f155b0bde78233f24fb0dc1641d77a6adf240e7b178e1e8b2147ea7829ab524a069378a111094b768cefc7aeefdacd5f33119f3b5ce888b34e50130f9	\\xa824d5732ee3f2535a72ed488bd787763ccfcd6606ac30f65be6b2b20f61f0200becbd3d239dfb3ffdee4baa431c5a9d9ab983399e1d68bb6757670f2834c05455e48e383d3bafb0abf6ebb1815a1349f2cc2d9f7d0fcca94f373e46d00d7097cebd2852f3fb939316ae471745978dd309f418878da2efc1e6afd45b9bb4e8a5	1	371
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	1	\\x132854d392f49d2721c81d4953ee3f000c984a09efaf3c73bbf14d53140451d916a485ecd02ea7c110e64928f370fa69afcdb5c3e7db094a5d95fb6abe451f06	\\xa4a484ddd7595b367afea95e6e0feb8d97cb619ca938db8876df51d342c14153c84967147957d2d4166d0c3fc61b9a190e5c2a2d77f54451fd3cccce141423871bbb5c10e73480ca3f3814243d0bd92671b6d7c94d4d28208974155c7034d2f7db63f681c1719a88161834e1ab1c57d08b8f564dc9ccbea84deac5f019f2f1fd	\\x1a8b03f3272b486a463a1fc8e10ecda5d1dd5aa2a75b6d830e4828e60a93627e6289a3bba63007798eb35c7beebcf4e55df20b1777daf01158f876191771dfe3	\\x123362c23a2b33d1698de22d997e1a658fa144beb8406226be924d32ffac30db73811435bc1a6c9fab61ba881ed88f07c503a700415c7e0c8c70b2140bb1b2375487cf8fe3b2929d6b7796b82e285f8324833182c32f7cbe4a81eaa869c787d2893c00930e67fbf2d800dc754944b1e8f73493c6704116715a8965b03996053b	2	173
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	2	\\x7835a041a961805ff6de3d9861f5be3079aaa7c2e65d3629f739791cebc5ba94b00209a3717b35ed08941431b5e23873d889166f0d15f75ffdac369f24821e0f	\\x53afb78e58d7c3f4c6ddf66f494595caef471f4f0f92f3ccebfd4520e868d5eb15b39d772b92cd252ae418c4bf39aec3f17bd26d17f2b5fa78b97787a9456954f8962a9060515ff7f39340ee56f4e0594e9f445746fa0901477f5968c0c37b411df058afb010aa174f91bda9cb83d21a781d607106be7368e061007efc79d537	\\xf035a7ce9a8fe0fd4cf6b344de650309ceac10ca9f662e8ed1e7c28abeaa0a0ca73746ac8f1da260ae69867e0671698bd79794baaad016d2a9c555448ef9b395	\\x8d81b9edc89228b075f77d4f23b2880f710596ab1e8ef6e55a195578a394fcd22ef882c7cee6b15fe0fce6386ee36c6e5adcfa0b34a8d25ed4ec7709dc60c7e20ebd112ead29e97a5eab0dcb3b57fc368a32c5dd41531c822c62e0a322fe82c3f8ca84c7fc45454ac2b8f0f8b21f929a47f64920490472fa06d75c3783bdca18	3	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	3	\\xf2db8641c027beb3e8e27d40c122430f81126673eb09638338f5dc2b91fc2b5cb219da0d1241f9caf1b015336958dcf8ce3443bf4c2d9f43f3110bc1d6ce7207	\\x0392a81c1b3df87bfa96f7fa525dcd224cf75d696b42284553d67362ac541732680fa0c633285f12de469bea40637c9cd844a84a567295011807f7354225a6cb06d7e2b0c856e9082cfa89b84435bbad85519b082a8a79fe0f122e48fc3051fef5337c3872d31b1fbeb4e9fe10cc9affec3ed50be356662c69fd0475d8e26814	\\xe104f6c3a8077c72754b223177b44a29ed8c7177174ba74081243a1d27f69eb8d0221c81afcafc6052891db49966a20e69611538dd2d3791b63d5ef4d4fea570	\\x77e24e3cd07fc7f1c48a55710e3589f67cdb98480b7313611474c9f25c4a1e1314e87de5e7b82121d79980b0e0d95cb8a35e95eea85bbee9de17cfa63c00fdd8e3831f3240d764f7cf31b5c7767cb178f3634244031dac51b98fa195143d375d46a4f8419159dea55c55465815ddf74a7b305ce45d7c8e7d3aa79bba36d74c13	4	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	4	\\x8f07429cb76b4b84b0d62d6965aab12ea8fd9bddeb2396638c3f6cb30fbfac61b5648bfff7443e6ead4d815b4b448c6f64ed544c2eeff372e2bfd6b11811ac0b	\\x88e94b0405f84bd831736dd15053138fc5fd1e77e543e63dfa3daf3410b6de087cc836ca55ff4cbbd2f7a3fe0e9250a1ff1252ae6cd79110b07afdc7942b483a79d646674e6523b24532e0fb55b95ff1d1c0c54c274aa5484902a07b67541d3f153ac6cc235deeb0206f9ce39b6537a14f609d3b1e5b689acb70949be485a699	\\xedf3042fcbd686ab8f6b1231cd9449970cb011331631c4bd147637f0484a2bf04bccaf66de79243043b8f119a8ed411a953564a521f69adedfb4a509eacf040d	\\x879b31c3302ec2fec33489a78eb0b8fcd5671d8d71e7006ca59a4b5e8b7f216dbd4bb15ca95512b19d2e8bb05b13398d3afa88004e984333507ecde89ea13d8413eed131139ce4ba1fd2eac3f022ae4c492f3e3f90d7a14a55bf1d118c83636bc1af907c657cfb2e3e29164cc0927df1686a176bbc46a7e8129a60885b43eeb6	5	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	5	\\xc3996cb66ff447d98e7eeb4a995ce5e3d63c25f9d4b4fc1dc79d9ef4a70f09d58bd4542bda9c8003a40cab54f9c9e0266b2b4ada170390fad23a34ceba564209	\\x0249f225a83bc849f09e77717be3f1643ad88b3a5cd13777eb8612d4bedf40904fcf347fac32c7f89ca5309f4ed61ad94f184aee7a78f2cd3a0a26df4236a31198c08fe9b02823daa8a92c406d9bbc21efdd8ec8e3cf00e18edf0070c15205938219c3d6d689b18b749acee13f98e579120285d9b09b0d5eecfd75d82fa95e9c	\\x02ec5df65005155494057d3c7ca5e7b57a449e10a15d4d16c2906b21f67afa1664bcfbe6115c87e59bf86cad5562af5a3f0a16be146a9990b4759b90036f6baf	\\x064eccf2aee8dc4e3aeb67fde8a42336205c5c430f9581e719c791a5635d211ff9e4ef2272419b3b5c89b4f9ae811dbbd7ce2cd1075b2cf82bd90479eea182da5f629ec58477f6f7bf61946a182c9fff2493580ce5cb698b7c9733a9b008a14fd606fc3b6dc0a0d81b74717a839c0998667c45d30efca2e22775336988e0ead6	6	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	6	\\xf3fb4b75415da9c50a87e2b40980f5eb6a3e07f062bd855c7d248ca879cab74e7fa25da6fb652d8b55217f488d9762791908da5492ce09cc1ada0de9064f1605	\\x7352ab7a42dcac682e556ddea33705565567742499eb25e1e94b8c500a0de8845ff5d62297effba750dcf3d97320a29d442e12d3a4778ffde16535c1b0a6ac764a4209378aeafc16d518204549b356067375fd2ffa5f18e6012f22b97dfccccc5a3d9812a00f56329b2df4b3c1dcad022f7fed834b8ac0ec9375f5e5c3243b81	\\x0ac643ea9a5ca5c453f75b71ca7f35418b97c27f9822c074dfcbed6e6e4b3fe45499c7b6aae09e575dcf2a4681a4fe39a6c9070f346b2e6cb5f6b1ae3d0435cd	\\x5e0f52a540b673149f429b84fae3f08df8c0975ba5e1d5ca6eba438b3a11a8151802ad5390755ca3ee696f4e0d1ad4ce7fc58d120c236670241f5264418e35baf1cfa257264487580646e17a24f512e195e5bd76a9e713aeb1f26ad484dc11e59a543b1394df9c3e14264a2132ec43b265a597bb72050fea05c8015ddb87e349	7	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	7	\\x4680c69e2701d9a630f12c7a64f02fba52ee0d8a1102290b27b80821cfdf5f83c1e3528cf005f49528976e216123ec7735ffceabd2018e84bcf7df3a6a053b0e	\\x773f9a0070fcad39ba1226489d15a0b0d01940f7e0c2d3bdf5059225beb848c2fd2879fbe8ba3af3312cf779d555a8352d0938342e8452cbf0cd48a37162c55e33d3007512170983e5f662c9d636bb212c87b90c034230a5b1a4803752b5ee5150f6e0aed8155fb1fb0a19761ca86b578096c5e99771c254e6ac3594ccb2092f	\\x9e855b8ed1765a2f42a575024a16e91569dab9888c7a0401ca3e8ec3b2c634903ceea6843b05e315f4af4e8b6c3f9eccdb7e117fa46c8e71d66987bdf3ef5322	\\x8142461680d0b092a1fbcba320d81f439bb767ed15ac585dcacf73bb65929387658fad8af1b6eea2f80b50414180c4e0903d822ad1d501edbe15a94b19afd2836711132453ce983bcadc06c6f615255c03a14075c116941a71b28e0b6092398639d3b5152693f056c27f7a95d812b14373b0c00f2658e771f99c98c4a6391930	8	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	8	\\xb39ffdaa66f23dba44eb37f66d7eb1022e228845bdc0417f5ef61b114f7ad26dcd9e614e8527bb5ae80931c9b84b2f0fbfc051b84fcaf828c107949712d82a04	\\x06b55cdcfc6d889c19bfe5b687fa9708b92f004d6d600987784c5874a9538d0dc50f9f00e25d1d0c7b90752ade347334d1b08cbff09666b5d4910185de0602a745c3409692d415c121d0bd36643811796c1bae3397d16075321f3b6815445a579fa23d44be77e6640f7b35196c7871b79d2889297bf2713dab929fb88eb6ec64	\\xa8af67776797db650d7b6bceba8b57b02b18aa2984fba1324f7b8c4b6863f23408c55117e8baee6f4722c8fb4113c9080c540bc92207479c88bc8bbd76fa1734	\\x0c184b4dc928d3891cdd31724e50ec86b54cc9ebacff5253c726cfaf2c65a9e9df5c3d6c30d0108a237e2a0c781f9a3283a535ab3d4429cda3f24bd634f2f6b24d3d3fbca084825ba21654479cbaffaa35ea74e262b67192540308d96fd898dffd3a71f90372dcd1296cea269e8390fafd7048953f832488d4273e496edcd6db	9	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	9	\\x260db1fcf718fd7ff363e2d5f4e11142cb84c764bd199367c1c9eec2e77fb3e434504124929b67736e8ee14bd40484dad7068375dd808981b78a348196215302	\\x436238161c513dac47dc12a90cb9b7d78b90c213b5b3182a930c2fadaecb24a2e465723862d54f385e3a4b8cc2aab1e9395cf4dc98b0c9903e0dfef093637bde9ca1dfee759bbe28ed7761259f738badc053f98cf908ecbf6d38c462c1417e607eae01a0f02b8ce626730a9b71f17d40c38540a1ff41e33eac2ace170151761f	\\xec9d51ca5cba31de880135fda9b0509291f137b849512470069a66332e263b33a47a64f516b2d2f66bd028cbb867655e1226c2fd1eb2434751d14d792ccb16be	\\x7de9a718fc9494fde453405546e25640b193547c4596b573522dc9429ce4828d56861b5d516378d16f293e59535e87985d83b75f7319d6c50153b2bdc9895802466e69fee864066c6cf31d37b1dfa09150128f6f371ed6f198794c8f2ff745cc73091b7bbf70e66a4b514c2228e217c8397dbdfba892c72fbb09811e8ae2b5bf	10	13
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	10	\\xb4b65a6a250c7304adcfb05962e2161478603c798a1cc5161c63fb955c8ddc7e8e02e950959cb3ab0677e6cf72ceacc1c5b1425190fc31eb9da987a484f46205	\\xa82f72ce080c6c4445204fca4f252db00bd132e94c2559e35b5f0d3c8337a9a24773b7343bdf8c4f70d90957734fd580551dff18e4ee54b042bcfe264a37cfd63064d9d29d51d62784d8814eb3647123f9f3405819002f3be40bddd4f40ca98609ae534c8b3f823a9916e7db39e7d8d69c82a859f5b375e52c46460c5ca0aafa	\\xb4e1bff8e6928bfc8853878b413655c84db7f42f55a5bb06d9579bd2fa45742447b5f82359092274ad6106d9155e6957d2bbd9acd2db4379b729f52819170366	\\x8d1e79eb1d98fae763680d740c08d837d05d84a62bc3f949e188974d362c254653f69f1aa87e0ba6391264c3a11c760bfe589747bfc0f322b1e0053a09fc7a822694b5757493d4a382a9c5ecee13bb7cdb4e879c043c765b0007d7f35a24bc9ff41bf012a09577d0ff9bbd0e48378eac3a4a8369ced974db8190da73e2ac8b3f	11	161
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	11	\\x19639b5f9147e190f3d9b075bef2fe6a077e17e32f76be300cd21d5c604ee31fb0df57951f78ef69be62dab3dbc500ac3357ea3a41d28a2bb1b3f3a6b5f3a20c	\\x9a0dc06434688613eb59f6681b332c952be70c14e815526039fba1ba0627492c140a2a33367efbf4c943e704be445c5344145ecb7e8ec46868ce6f056af59240d584b04aaceb2e14d8dc104a228c09d0f4c2d7986037cfc86882cee186858f9dcecd546047e3c6e5e46263fd18625b2078c036f8702f87ba70d11e7729951762	\\xeae7d13a132e5f95ae100f4571089c4a4428b709afc6939b65729567ef455de51cd87a5023d581fbdd1d8bbe6625a9ed4b35715ce63db427c20800370fa2c121	\\x52f0f1d904e621b30038d25e6518da4c543778c39c51702e6e9dd0ca513f4c98bb46974bc98a3b259a429835d7eacc9c3f8ef2b33c23a8a704ec4417597b526560325f76a854800b3bd030f474f436762a3e43e6da40c7e68b0516ab18fd9c67764224f7e9fa62337e048b11f5688e90100fc4cb4dd18c202c66bd7af2293f6e	12	161
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	0	\\xb2f3966518307105cdc535f7a0b0dddb271ba798a9c3f931a046b9df198bead6d198e5b71430d4b47a0b7b37223933c4ff197d169792ad89eaffde7df905c503	\\xaa0a8bcf3080780cc03009b6cdd186deb577c1eeed7d681a3e211007c156d1ed0c404b323da9f0612a664ad766467e2ebf65c3a49b975b72194202437c54a20db5038a46cdaa0e1443bc2807c42b4cbb9aa276f7c0074699aab8356668bac8b4ca45b49edf3dfa9257699753a7c42b2106958818b52e59f0261621d40ec470eb	\\x2c1e36526fac2d511e4c5414835aa17455f0a61e07e66e0e06e10cfa0b9742a956d693d9ae989c34fdf46052a8f720af07fcb3cce1c49becd3d2546d0b70a710	\\xa90d16425fa3039312358cfe6aa90594374f4fb8d66823cee56f1782248c865f5252039ee1d8ddc2bb3e3f64ccc03bf9b97453e1a4a7bc56ad707bced737cfa9e5137f29c951cf2890fd6a9f71d400acaf7fbd01a1a54356f7530c234a5221725b3566cc3560b08ccdd4a526da60193b213d3d3f9af16be35e14b86edff51f6c	13	371
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	1	\\x5adb6bc23380fcd46a98e85b20fcded3215c71d0f6eb6cb45af31163b040a023f721cfb06a4bfbc78b0555e87023579879b25bbe1478eca1afa1afce7d87fa02	\\x328eb2801000f543ec76e0122b8be1a7f1f2c141dbc2ac2da18a9602e1385f595e56106f5baf20cd99aeef188059fa8670ee1295e1fb716ec101e535388dd0347979e364bdce0b0760895374f322004b03b721f034756cf9fe2b6d9615e438dd9063835d2da123511a6a452ec708ca4268f1a170510f57aebd54c200ceb414dc	\\x5d146ae769fe616f57145645f97858e95cbc6a3c9dbf14bab495777c45364dbaf4d7bad745a0ff14280526d35a5655a94cb8a4b5568a2e15fe493a319b4a7d29	\\x397e7ff83342f2ac7197386345733bc41059d90a5ea1d24baa274f4501174448f3f7bcc94b99f435ef43dc4f144d2b8de1051341937abbf28a1ae0b725e1da8052da39318b8f175b9e6993b98108e85202a64f2da530a00f8735f92ec8f865b86b3cba507e073621aaf7a423b4dc9c4baa537725d5bde7d85e18e5bebd85e0dc	14	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	2	\\xdc4e160f115d5c6163290b490323bcad6d2764c593844e3530e1c23667773d874707297283b1ccbfa85fe6ab7d28d0d241a4aded8ff7deca8dd1e79321b2ca00	\\x1dfe98b6da4c2519286897f1a10b774f33d5b4c47bc383ef96b6eb117cda91e195611956cc47d3a24d7a337f5def8f670447758eda400c4b694fb35da9cf5e4dc09ff77587f1604095ee26b0767f2a86cef9b0cb1b2c21373008e024f769d0532ffa882733899d0c65dba6f9030148cad3158e38096cc6af79dc59d272179c27	\\x977c9efb7eeb16e795ff84eea990d07bf4312aa28a1c3aed705630516105e89dccc8f5c2d7316da0849e03541b525cf0d7ca042c72d99899afda438907b4dfee	\\x0573e4eb1dcfe7ed5da9e93b86d352afb6b7f040ee1c726d522ec77357a31ae88b5fba03624ae38d71f9b5e250494d4bb80dd7c2eadc95b95c6c43eafbfc88120e27baaf092681271e973f1c32ae37eeca5f5bde669ba2eebd962f92a1cdd8c46e552c1e913cb3c4059b51a2524a606aecf5ac788cb18e5ac24993765fd689ba	15	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	3	\\x9d366b3065462a3ae4b81f1ee87da6f4d5e5baa4d6a394622efa27636f5ae498d6c2bec678058d71e42eb9d4d5522d3904d40be02490318e9b67e4666d7bdb0f	\\x743b824b9f59e045aa7e9b4c855d3cbfaf7b4a43a3c024eb609662c24fd5589662dccb98bfdbbf19f6e8901c2da4208dd6da1005667ca2113aa7145b635d1cadee0cc1b4cdc9eca05d01299fd63426ef92fdee5ae5bd054ff537782be96e43d480031fbca0fa878ab42fad8526856b62616d7da12983f23f0fe0121dbcf61ab4	\\x164dabc6d85b264cf4c2bacc0340c92b1eea88f895d6a8138460147a4a5757ac442bb331d20fcbb558166ed996ff6c29100d7b30c6c440b6eafd4455a25e0419	\\x96e9b211b6c489f1fa5cd94d80f7dcaef98a278ef1d3aa3e96a22039466c92c1250595ef783c496a9dd8eecae26ac0129f922f818f2e2f98354ab7bfc41d47782fedc9650492c1e9f201c8e2776f4448a5c6456b671039609491d0d93929fa213b6a934b7b8b04e1f37b986c9b73a5a2dcce9c168442964c8a2380549ba280fd	16	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	4	\\x2fd1bcdd712a74e10d52667a0da3388794df04d5a6f887987aedf2ea3acaaa22e6e38bca6312f994a5432b93df90d736974efea81d1aa438bf1ac8ad0fbd930e	\\x8edf56d7c0ce4153150e4a186d30e4e018b7e9cb3e14f6c7ad128b38a50efed414ff93a6b94f254a80c128ccc9c6c405205cb3efc138f7aecd3dc1f7d5ae57e61eb4be5ab94a5954259f5dc1668c3333dfc2740bfb4678a7070a5a9fad7590d9406d99a952271c48ccc48f12e0392e114812ecd0945e77138d178d737675b1f0	\\xc07f84e8a32d2eea22333529714894252a896ad28917d3088c3c9f7deb59e8d8d031c550766d9c1d0aea68b4f84ce7b3acdbb315627c78b9701e0366bca358c9	\\x67fb4304aa6cc0cf9da0f999eaf099d1e14b14e519071618020d15d849757929f9fda296b1635cf23392396220ddd7990dfe4e113ba97a78de7d100b1be3248bf994db04e8daab5305b80312b3c08650211c5c611e0fac191f86aa9976fd231010c94ffe8dc34fc38a03a5202a1751c2dbbcf414682ab45a938159b433a68848	17	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	5	\\x16535b1842cbd6dccfb422142df3b91cbb9577ed093c8ae98063f2e42193c644ad314a860168484ea151d43d475036a27be760cd35da57acfab69f1a81d4010f	\\x7e2040587197ded5aad0ecf431010a0c1000132eb1abea8b7ebd33ff6a9d0c594d5413be7f4e3b02ac0061276465f473c9288bd24ca7bc70760e0977dc321e0107cd7fc086e028a873ad191e8df655c1b3bc1725091a7bba40b5c22f49a6fad3b8ac449a6a75e627f30262a73c003ba04b08d2aeab1cc9a172c72e98a5b38f72	\\x75a16667381f7e85894aa2a203156145b8c7cf07c4034657587dd946a3fa4e9cd27436a29059896dc87c7ad02a685841d03b767eac6f6c4480c548dbf0bd064e	\\x7739a9cac68bd3dac66e25f5f3b30282c0775272254fbb74261e2b90a61429d97e054372dd4de6528806e98e5ee31e9524282bfdbbacdb47eb790c9ebfbf1eea6aafd6cb05e88942d7b8a516c4b83627bedb81b818a61f9413fa3ab412079b5ccd3b69bfe88078763a3e623ef51a282e2b162f675104b0c82b8ee51b11dff84c	18	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	6	\\x20014b667f88002696c5dbf799a769a5a89bd89424ca4f99d8d8f8eef2c72be2cce2ec06f6a4eb911b53dd184f8a01058cbcfc2866a31a63d3563fa23d4d0503	\\x5ff69e9f666bf0f446a87a9b546e2aef469998a30a3bbbd4cd46e7fff16671ce898e1df3f12b2b17fafa1c6ed57f7a2cf50f70b1bea023266201761f943654fe4d1d7f5f70270543ee9c7a83df46a320632e6bc422614603042b94f93098c49449c72044627edeebe4c4861f4f9228b37fcd114d600bfa6a91e1037394f1d508	\\x9481b6fe8cae5ef6fc1bef2109cd9f2e5243f75643f33f5101447a6e7155cb6048e2e45bdab23a4d495426e09e4f2eb8de3578d4fe9fa53666409a4e91b88b6a	\\x78704c5662f8ce16daa6f43ea9a7e70a4bcdd8be4480a6f44374072868c6ef25677803639f106e5da3e470ba82c370f7e743d89ccd1d3ca8a42f3806a58195d5a65bc114a7b2fd9e251fb37a14f4c30859ea3278b3232b8a57fca3d80264c0892ecade85e68f045bc88da7fc211bc1ce333ffdc6b30bd3c9ce12bf52c4b6ced7	19	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	7	\\x05f759127f2464af8d7b4563005d27e9bbb560c76cbf7c22ea161391f613cacf3ce6960ebbe25526503e2aa8f4a20c58d9783f2e055d1b2ebbc46938d117b806	\\x5d5a6008cd9f989eb26c556316e92b5cd77007b3c10b363309e24c1d8a3ab49f515a1d24776c66c2e5e3e46d91b26ca4d543654e50e4df656cbefd5f8cefcc04d5df088f3d15210d0b934a9f7b59497711a2b309fc298615a1b8d98926bc3b344e0a0c1587510d3713978bfed6db2dcd16174c78c92e31ad24675ecaaf3b291d	\\x8827e706e5c8365b2bd9a9312293d0fa118503dd42ff3a8058e3f793947d5b1a4e0de745775b124bc237c9ff5dc1b03ba3a4675db5d56d69af35de34d6d97477	\\x3a690972f869b0a71f168210df182d3e7cde73392d9ba60e714d0334d84e64b9b5ad188bccfdd8f526df17d441ff7f0830cbc4966425ebbe73d6f0828f81b3a1f1a0480c61439d67110529ac66f9b2c4cff7ba8b8a9de242e748ac7033b64c39c6e64370c8cb30c9591bf8d4a023a0cb7a747078362322523949858215b246	20	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	8	\\xaf812077d915aed4cac08de4e35848b50afaef6221cf0c9f54368217e9a048463f1de0def7714e1fe3568a1113eb7a107c1077299ed7ae3f7570d915912f2800	\\x6a0447fb6b8f5f85b3da27db80d48f6af8a139562aa137ad11c8efb2c7dc7317ed0a99474de1373511b72ab286b27e06f2b75f0f31b9f264fe1d7459545755e88bc1604c9b0a1ab70f6af52cb5809d6b7e82248d28973867a8c98e2074b531c675a8aac3d3e69bc391f1c8ad51c58817156ea5b5dc32f457541fe165a91e50d4	\\xafce7b8c7cfb53d8ef2f7cd1f6b85e9bcb1d86c39ef209e009b62ba7e724e31cd38a96f788d5153efa1fa2dcc89283de47c85d030b74f8f611a0929511662b67	\\x459c80ca2fe915aa5c53474b6431578472b771c22d055b5840d0d444bb7ab24c064f20326e81809972bf095ed4246b16df7cbc62c9f38977b00c1b93ca2cc39ca9424312c9d20476c17875dbefb2999796ee487ec1cf256e17cd34fe2b7c03b9b10ac28a1a8ecd5fe1244e0d75d2a23893be738ed9a6cfc8b1d1b98c8ae31e53	21	13
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	9	\\xcb5784529886afe2ac02bf356fbb852c12a48703ff4e7cd551428b674004a43e070645c01b6c820132470b1fa9a78840b8ddb19c0374e5f72626f0c4bffdb103	\\x5fad50a1b680cd1fb63d5f673115ff9d7765db22b5efd2535d1779f8cc20042a16c66fec24a7179bf2f6ba0dcb942594f7ad12c728b03a252b4016423ef902fa575129f9c32401cab94b2c148e71f14c75752da32bc706b6b2007f57b2913dfc5039645487a6fa39735ca71c8565b32643a59075546be54497f7f3924f39e487	\\x2bf89d2a34106d891160c0153417c2f7ec2a319aab88be1e51508bf0ea10715bdc2839833487c087566cd70b9be308d96a668dae9c83a272487b8b0aef2e7b7e	\\xcdbc682ff6aa824071c39f17a17d28cd407e019561c169d6c9a0a461cd9495b281f2ed703d36b1c552180ad7d74a88ae11d2cd8da3fe9fc9681796e7daa14f535d1163b222013a6223e53fc1de89672f2ec6c34a5bdbb0b1c7c4e70c15ab00c5d3c3b738c8600cf6f24ddf7ba08e8e3e7c5dbf7e1d06bea3e0d4f4cee5bd5e8a	22	161
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	10	\\xff29937dbac2c6bfdb29c4c5c0253006d00f03bc2b9a64437391b44774bda4bbdbf67f4d36c65ea84a90c7775ce4f4e573b74c1d165e797a53456f1d0daaab04	\\x8ead25846c957be0fb9c847b812d46a2b5350c97cce41801719100edb9732684ee89a96e4c0836bbb1fd6db0b32f33563eaa1734600009c9c31456e5fd722cba55311ade9eb01f733c2350b01413000bc19d53844235cea639bf7f3fbd96617efdb39c5720c7d173d0a674de105d2320358990e3a38f0d10f3a15d3fa5946271	\\x4992bf329cfb84e5e224892df9c27e38bd9781a2e46095b3a82287efa81a1cfbcd6dbd755c69854882538d97bde1ada5708fd96b61b4129ec803a58728b7d93c	\\xcb47bbb6d276f9873cc2f2f22cf3fda95a607f703b33e99f07a6c3795d0752ba12e87cc8f5cd0b735049d04316e1c9f55bd29e86d4d548acc9063e78c6963977a5e4f44fad232338beb79a1f1998eb8cc8b2c60d419db9b721adef4abca7b8ee9918ab210f941b8c27df8bab997483033034fb6bce1e3417f10f34b202846df1	23	161
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	11	\\x2f6109a602e84429fa13bd2cb94cf27a7c4f45230a61900a2dbf4225b3182a94302a6939b5968b88c8f92bc7c4096571b528b7d3db06a098c757558b8d09cc0f	\\xaab618934a860ba5c1cd91192cb502f3ebf363c79735053842f08df388977977c68d2143fbd16a2794fd3a94bec319a6f7a85da8599557d847263d8b67c9da2540e6cfac80249f8fbe76c63bff57d12d2fc880906babad0d568fd648bb58c98d00eacd30ce1685f3c412a4682295b430394f2b2323a68e5be975a1564f62c2a4	\\x885d46ef5d425f655463981d4e79431fa50d55a9e497abb3d356ad8f85a7a88fdb128239c61b4c7d70e2e36ba63a734fe084c8772c2e67db2f7abc5789f001b5	\\xca6e1489032c693ed9de8f8461c75b225f4e4a89b975cd99d0604b2c09a8aeb3c438fd430af60a085c292501d280fa030f439fa1bca6aa9f748b2bebaaee185c9ccd22abc749d76ce0ca9b2c289bb66b5892f20ad349c12fec48113b0df9b0e438c4ea038f37ea99a8171cc152ba87cbab808d66620b153453c961e300584dcf	24	161
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	0	\\x59faf47e346fe3a53be0aa6a03e7990f1880d948b5a6bbf37abe01aba0f56c23ed6d88fae66f6e43c2fdb8d878f7f952a72964d4b8533238c617600e155bd407	\\x212e48522c9d07e040a737db187a11c4ca9f2d043660f1c2b076f78af9f99f138384ba175174baee0768c40f1f382a450bef44f516bbbb8cc7c5ab193dfe48db12bfc8c5b2a8cb7e26be224d9bb818371457354ac69e4a710128175cfbba81c8112313dbaffbd78103289c99c16e2295039f7ce0d137ace3ae58885f23c5c3f6	\\x470eb42e84e76d4a496f1c889e1ca4b02aa8e0bcc44e8b9ae460e611191a15121b3ae4d1e6d29127cd3bfe3a75b868147f2ea0f820b2dd8dadaaf693ef76a73b	\\x3adfd1f3085089386d94467d9a7c3ace93ff17d67b7ff90db1b42c6943d7ac3ca3331ac3eae07e6e87f3ba666c9a8035fa9b82baf33b3a66e6c4760240d5b63ffa8a20603b93248b171e1b28c463ec87a7f8b3d41c80d7ea70098d4f30a6c5093c9882d36900f080ca69fdc8a2dab985ac053d8f32e2dc6dcd8adb0f3dae988c	25	330
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	1	\\xd5df6bd97e15dac749634205558b243b5cfb2a05c839b2fbf354c6dbade779e37dc5e7b03e93b8cb7a5151e1a6c4e7d198e8aec2933adf8c64965104ee7abd0a	\\x3dbf6a43cf19b6eee2aa8c15236579889e4536dcc400d3c6d4ba4deb75d5aed7842505fe114d2493c040e6ee609bda3d79d9400a0c745ccdad322cd4b14f9c8b1fdcf41b1d80f9f351ce977d7d3e3966d1e09be9198650f46fe0719694c0dd9f54ef2b8bc805021bbc34f76d3c7aabc26bf937094f6597bf8147501185cfe077	\\x9ee08465413dc8e28d31d6c3f04138a14a1751631992673df373ae6170a3bb937c55615e21b9a9d984e2ab8a4e5bf6e5a3a8c3c060546b6cbe5ccc2080ba9698	\\x4c112ab9df0d8d5416ead4c454e8cd97cd88b2d56811dbbaa31a7cc0b486636d979b0fe3f01468726e567ee83e628668a89b3b85d3599a981861cc197ee2a44e4660acd50b96eebd2840b212283f7f2ca7f8a13d97cec4aa5e645598c7bf58e06a602d7803bc81dd9443fb1d75abb6cb3d4550d9ad716391cc0f2db878c533f1	26	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	2	\\xfedd2400304762eea51ace8a107f50472350c8f88c41e721992197417af4102c5548ee1ffd6f9a35a0fb2de8012040a7a348667bc84f67e8deb7c3f9c1891c00	\\x62c8e9c510fbb71e5e932ee4f7a542814a7cb5d6b17b1ab4efbce6f9c13824c01687b9365c088a30e4ee87bdb92db177bc7dbfc44b5f3134ff4040dd0930e435983712c88000f6867ed2f9cc450f0c074a78acbbdf227e10df0557422969d44d119fbc7021e9e1d127b65f2075d0720fe35698058375677649162b69216c985e	\\xfbf8f2abd1ac8812ded3ca44c62f1686f42faac80f7c800e1c72fda3acdaf46ec644023870ed7a89053527076b14593159ba715116b75c7f3ebcbcc121bca476	\\x7d530d8aa9367a3a8cd7e56711dad51dbe4c775ff562a21016612837a1810e1b2b45eaad57b5007485be98bb4b992a10997f45a992ef4b5e051fba44dfdeef5b201a8eb8b5144b84f471113d5a4e2898a1769e45fe03195eeab17ff314235ed8b30300c3062a65658d3a82744813b10f3a0cc965ca37025fa1442127f8d31acc	27	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	3	\\xb3c7156ccedaf30306548298316745ddeb83f02d1b7997d9080160604e781de420360e5b781070f43dfed8e8eabecaea7acc4f66085f073170658e7e90d7b009	\\x5c4b6dfe3a41e508e67878e648a522517b56f0551bb2b56f38e3e22edf743905b1795d2c8f964f2ec780d1d21139016caca74776436e3d4ab09fe43c80ecd1866d1a32e8be03da96a10ee488e2e0d54222112c474234de4c83eeee78ad09646842a7317d84d0dbf9f450bffbca03a44706f7358d5763d78f39f63c5782d03311	\\x4214fc09d26f10f26a4d771e25340c2371716ffca7645eb298f33b7caf8bb03c1a6971ed31cce731eddb435cd188e14060a2d09b2e44ba491fbb23e624a2bc28	\\x523fed1b7be7ab2f311f6bc0580f8618eb5c08d537bf871f649f889b0eef62fe5e2d88cff57f86cfe326bf8ee1520d535ecf3178653bd5dc075f29420e92cb6564c71bfb950c614804406a780ee1c8ebb97a0bff75d0c6a9ea1a6dca27d8e6e09f3324c09edee2dac48f31904a77ff21ac583e7e9a7cf5ea1296d64d4ef5a0d6	28	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	4	\\xc25da79a711e0b52dc80565901fda40b2b228cb8ba14c502d29620d5389f5a95d6a32fa47d036fdd41146710b98f4dcf679f332e6972c6ddae2af622494a9700	\\x37285c6d698ac4531f6de7b29eb45a2b7d398d70fd6fb96961e3eb240c907f741a6b54c0120f0ab76e06bc797c5c116918c0e5fed24d40e1af89d4830afcb66715c88371d9e7624a55bfd734eff09a62a3061c5d85cd1de8cc17b0534ea02c22cac7732f8d48afc1a0bbbe5484b106fb6f4e0462454a40723b482f2719d038bd	\\x1f66963ad8fbdc7bde7b24263bdaa32cd2ab1c590b789940bd6c67f79e4d2a43f58fd5298094de72d63358bd9d7ff525cb3521be38d7427a50ad7504f84efa21	\\x4185084a474ed4b67dc1614c8948eed8e5735771cf11474337860f509007eb97fd4340fbee3ee12cc7cfc7b69f13614187f3c0e25dc974fbf3aa2d2f893c58f6c7e9a548f1e5c4ae8fafe3260646f2ebd0cb656ab864fa2780dd944dcc8d902b23ddafef40cf0bf40cc27c987a47ab8d34161b3ea803e015d2808d7629ab2718	29	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	5	\\xe8390e9b4e037811c76a4742f32f7a0092ee1090105014cb0c5d93d63ac5fc89e25c3d87fc3f27ea4da537c257ea4996cde4b9dcc62b7e28d95e6d661ff5290f	\\x15f6c6283405663dc45a428f2bdd6be1c61d35cbfe95b92ea1db603893e2b94966524e5114626a05e12df43e804c1137d3b16360ff4147fa8bc5a38356101b205e5ca43cadfd7ece62659e31595c342d4b2a7a0bc8972b1fdcc4479ea1f8e83f2c7dc8531fa80e56434d8be9c3d9f953f28bbcb94e22a712cf9a38609d8ca76b	\\x548c78fe2329446f411f0ccd39c54d4e2278c14d786c3581d9603b8ff38bae5815830f43964579fc38d9d4c5e8200e93b2c12e18b8501b148b2949136d06279c	\\x2e536ae9fd3a1c9a1653924581aac29f9bc30adfa7aff0a1ade561b8904bbd66aa404b0b42929ded014cfcaccf52376119aacbed0f1fb0035f827f6169b2e32bdce1567f5b9d47a49310d9330b55b17dcf79796860c90efeafcd798f526342b54243ca532d02e4494c3f441f33a80e1eb33712a310e1c6dd53883f7c72903ca2	30	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	6	\\xa2701cbd14cdd49614eb513191b802fb17edf9f32f0f14e9db240fda7028bfa63d615d5820cd2c7ed90701ff79cc43e48d163c357b28a757e58c4f9c6be3cd07	\\x1f7994688f5d5797196de5ab26ca64e4894534ce92ead1644abc24e504ddf8018f4a169c3d4cd15c06f303d391159765b744a7cba0d5444b19ca6b6c9385b580616d1eb250c7aa6a62a7f7f62ea5be8a76a722a276c8dbf67ce19d92d9aae72baa83ebc86f59e1119a64ecf4393c0b33ff7faef4bcb21f49f64e541532ef3add	\\x497c99530abd9b93335705c3b05b5dcdef609c70f46c429e7e9b9005301db03c2e5d6c5530285428ca7454fa4548d501d884fdf3ea44995535dbb2dbb1cc566c	\\x2d1acd0e6032ab958bc0bfad39ade4e0ad6155d42b68edc00ce0f4b7d1560694a379e820f796d6a80b8b663add60326b832bceeac6f90ac65efeb43ce84a1e10ffcd4c83b810f9dd04917f9ba03c89a8dd2a8a97facd2801185fc3854003d3fdb4d042950122be6c9e747d753fb03682b64030c89e39e554fea41247bde9e044	31	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	7	\\x1f07e739254753a15648cd7beb0690ca4291d59de7544d953944068b848cbc229d8120d9281c84348d8122cae11d456eb00e83f98272b1bfb9fc605a63c3750d	\\x7d81b35fcb79831543442ab6fe287c9e6282e7760ded087399d33a3e6c922c1753785d105015177b0e61f42e5eb1317c39ad4d726e863d30c4a250d71b6b5f76bdd8a8bad6770dafd41f66d66f91e9f87f678720033b3d5063106d1c56e20e210051b45dd4ae4dcf2b9de51459798f269dfd5564e6672744abe6ce3c544a0be1	\\x50802022dac99d2f9f9f69eee456acb34e7abd032c40cddba8a157b97a6d51a81d3e02fbea49ff00800b694a586b5c46c9a61afa9b5a840a34147590c5796fda	\\x7ef9d81b1bad1601556c6331393e138c24d68b9ec669954bcd40c1cd694fdd26ff59ff1bc1cdc4af8a66d6bb4bb140028e198d314408cd6365738a8d5b52f2002f9e26a95dca5b42991f67488b01e4346c99c9e8c725d04b7a0d3b4e4d549ec44d61681a80bb88b4e146f5263b586e0ad358da2b19d7999557658f066a6b971a	32	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	8	\\x79cb0f5bfa7f681c0e238f236994c0522ae6fa5cd80a1542ca81f70b614ec3aacc753b445950997e0c1cd9299b704285e1418aee7eee729fd0220ad1c2eb8801	\\x14064b32b27679c2ade7fe6cdeb5534939de7d68be9fdbf5437770953f4df46c8bb82399a7981aad14599fc83d111cde6e4bb7cf9730c6e21fc9f9cbe34590b3266efb5823f1d3d95011abc2bdff5bfbac68df37176f803ac42f6afc90d8ddb9f148aa78d8f7b296b19f71bf181e4c5427cb1be13d7ba281d4a08d56a8904f32	\\xc0b476055a34dc55203ababe4badfdf0056c97b58d8e0923e259cce55d3f740763adfeb62b90bd68b8cfa0f4585480bd4849cb16895da5a461c2c511a7f82434	\\x76e95a3459965c482f66ceefeb94e20f8b7dbad3a446d50a8b730844b2f7e322b7892fae29ccd696bde87625096981f8bd40570869a60e6ee9672adfe786301073ac0705c06000de78ee840fee34f60b4791dc5072c3311509d0899c541b12c04345547c2bbe9d4964191053b74612dc06be110d4973f8b7b52b37d18bbe00d2	33	13
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	9	\\x2ea543edf6ef7ca824b82053529fa627e722a1f7fdc99f216249c6e54fb9496858879b67bafdc0f993a351995493a566f314cc62089b7ced06f74595a9a2e308	\\x292bf5333105b080824c6ab40c6a8ce1937075a317a94d41ef976d34d650a093a06741392ca0777162d10dded1c4a847067dba3a636e971a4f450e0f6e7be5f2cf2d987912b6df0985a361a1596746dd46e9ec926e79e8da81ff76c11a61861c7d66a0d63ff8105dbd48138fe83d6270e4f9f9829efee7d93477f7c7ee24ccfa	\\x43b3cef4bba123450375abbf94a85104c8622521f13889e5503161051f05b685cd2745b4931b0b5e9b687055ab647ccf9e70b102fc99671932316f7d8a661699	\\x2711a1bdee010bcc282756c44dcd2127ab3ff2ddfe6629ddee7bd065ea401dc3e51d7ec0a76ffe5b706087b87aac282cc67025ad664b288799fb3265c27d77b39ecba52c8ca8135d28b344367627f61e05b7b9cc5f8022f8f2d066869df3022bca0b0e141f0ffc2c166d6234c024359f2bb831e2f5de39a6f858fb4b409fcdcf	34	161
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	10	\\x28d4aabcf1cd2b742ee97c6e646e8f46399d519376c37696e71cb37f866e2ae5144d37a9d8183d28ee42deb5112a2b3bd0fc443cbee852b3eca699f80fcbed0c	\\x2857d63cdf661774999dd17bc837317663a48665dc7d812b058af169251a52a1067edaa9a490b906680ead33df7f85e47e62e1e4d6866d4a3bb1cb935c1e05d59104403240500fbfdac45db2755938385f9eed471907e1877b60fe340ad89f54791506c0f5d5d95020ab794756bdcb905e8e1895ea41ec08f34ae0dcfbe8f47e	\\x4b537f4bf0961fcd4ad66a35bc23d924de9118308633dccdf0a544600004f898765fc49ec3816c22dbd5db2b0638e43f0006a07446e18efd125867e6472fb8a6	\\xb4bd53e5d45a956178dabda922684893f444cad098a201328b40024de84a426899b2419a3301773588ddaf12b98613b7f55686437afc43ffa71ce34c991a0c6d941847d1768096cbd825e7f82d400ee51a57bfb39b45d68e5badf717c8ce9aa734201e2dc5054aea1cf54d1a31d9825a8e1d80960c0c3ae87bde344079e43c85	35	161
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	11	\\x700bfda69fbb7c9b106977d674ab46ed1a1f6851e1919136f9adc276b92127ab60ed912298db21d1a16afcfbe540e3e51b25c57c7feae51e572f13afd4bad005	\\x7e139bdf9fb41d2d90afd994f96db68ede10f55da6641ad9e16dae5e176a05070e59e8612a65ea48bd1d4d4d7c0376ec749608b2d5599bce5fe6a2f03a362f7c576b78208e7ec9a915087bfc123ba7bf282c8dfe67ecbc989d3561a3bde2dda9c2e2e3b494734bfc725d7c62841e2ca63c444d209ec72680b89c25d45c7f170c	\\xeccd5110342777b1b5a618cf008e036179e7b3b23c52ef23804e41fa89a05a40193f075e2c338ae2bc6545020115be47ce142003484914c4052f9d5ec1b6b93d	\\x3d5e4a8730bf47dbd673aa874face9ac636d84c4483290c2fe502f527897db8d434a75aba4c455e378f854cf439efc6c2f620f149bef60306d3e50ab2e34b0bfcba06d62b667a15d04df06dd935a045dd8045bae87e351d67e43e503d24c62e9ef8b9774f414afff601915a3e406d709aa165a2c8ed2073b72ad04f769a6f7c8	36	161
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	0	\\x3d3ccf956e127c081b9bc19177eb6acd5c8c235f9868b65ef756d0fc9d432fc0ae34fb847213279e47be497f04d7c243321b37715d73daed2bc1b2e3c8b7760d	\\x93fb6c1f672120dc91ccd8d0bae674da1b524b1ecdfbcef54e811163a9550e14940593e994dd43e4b50477384ee594714f0dbfb4e13562628184797fb11e727a6aa135de837e72d106753a566d56142d47b68079747ce466b78441d2a05ea7ebd3a3e35efc584d7408e8b3bc899c29143ac2f110f32a00f8fdef2987fff084be	\\x8f29c4f7db373e1166d7673ed362dbc250edc59cafe26d37e7fac0c040b6e1b71f6007bb843fd0965a7525a8e6d3457f58014ac1505a69f435538bc2215bf8f4	\\x352223bf0e57292b1b26b3f44e929623266f452c8e362a91c8dc1f451f2309714d50d586de60f922d09c5b92680bbecd93f97c9514ac6bfb3a45854b8a0fc586a3ab166cb8115ad207127aa7f0d242b880b8fcca7086e601034e7abe24603ad1999c8bc0053f1cbb09e2da8d4de855db2f40b20d12d826070d7569b16ce4fe30	37	173
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	1	\\xec0c35014a3afe4269dd22a60485ca5ad86fa1108560598f335b1daddf25e3d5944e7379ed19fd23b95f9a7f60c62ece2376886868401b84b49cb016e6382d02	\\x8e60c2c6598d3eee57fbcbeb029eee4f1c59b819e489a215f9b509d547ff800f8ab2f8a74acf1bd54ada891b59410f73aba47bf2bb8b1aa52652d9115ace6588cb8d4ae2e160f1c5fb7d29cd9abf213317d13a904e58f32c75734bc50ab28225a71de4086d22926319f375a621a25d4234903215444d580e6d9b06a3e40dd7e6	\\x2449baf510c3c611fbd4e0680715a7bff23f8651d3ad1739b089a10cfb4507ae933c628e23c8ff5cbd213dbca2a603b5e0e6e61f24ae370286ecb38d352af9dd	\\x18d751ca8dd5c82bc2161729ae50f12120146fcbd9e727e75b3f631e35a3a208b10593c022e20a099f644ec979a7566e94bb8ca79a9797ef96058b5e5412638fac218e33c502d0c49c6c78c4baf2052b0a8df371ae054efe33cf4957cd427cbc71c3cb1c6eca4df3d95a6dbd972440f7a7d7d723dfdbbf4b733b93cc9ca09b64	38	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	2	\\x464b17459b3d563f9ebbd1dfe3d2c1c0b6d797a3b5c153bf059542a3956a66f8e5ebe27b22f87108bfd3c20e97503d7885f81afaf44ac2656939eb0c06794f07	\\x461f42139de23f7c0e2dcbe8591cf0aa0dab36967a78edd2b544496332b9c53483bce662b6c481472c57fabad713fdfc8d8d6f0a52c526ce05977109a4f9c6330861ef2be7770e48a29f47104f91d2647a4a739c9485a08f0f556602fcb7009d8fb878764658745b6bf8ee00183932564d61e547fc4c5cfd239f61fa95d94757	\\x4f599b8974eb974cf94e43d97e81d0cea585627c838d0eae338d698c554bf3928ec8832f155e3c7a84c4c6677682c1a1bd4ca45adfb6ac66605f7586ea488988	\\x2abd3b5cb8d5987382b401c7c8a0851657304534e99bc68b526482b24505cb21af4dd58ab1fc0d9efa25dee5619d87fb130fd82a5498c75281e5830f37a954abca175487be3838bad9012091936b8695b509c59f4020ad44c2f0fae0beb83d8490857506f93a4867edf198693e6b4628082cc62345aca8a0cfba45bd62d66040	39	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	3	\\xbdec6e17d56a91cf62a8120b0e89955c1de5a90890b402b00dc4ce5bb15f80b7d1c8a6bb270bacab5cbf10a25a15f7f77834d55137dd49609ac75951be2a5000	\\x020803e576e3181fb269685fba28c97e6551144c21f1bb13bf721403bf388f1273250aac6872bbe49f8ebb0d85b8076ca32c9173f1d8f5ba79448379571c3155b7947ca221bff2bd205ee660346e2ce9cac3995430cd2f6508f6dfe18384fd99512c2b2c56f102fb4b7fee6cfc3905c499d1e5e9f7a650c6676b46c1c76a0548	\\xdc61a81bf67bdf2e23ecf70d00ec6a1212b980660b9ddbd5291d9a724b277805dc3745427a26a2c724ddb830360787b60def4db829509408f97853a8db85843c	\\x975ebf237c60f6dcade1c45dc7cc9e7b83bdd1bacac10be349e170be654cb99df79075ec9471e6089f870961bad36e4eeaa1a8b59aea473fb2ff3598b0261433e73acfc4218eb8637c4da80213cd4fc337237d526fe27b510f0141753195411f41a3b40aba830c5d2d29666d235f277737a752778691aca00e4d2326332cab30	40	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	4	\\x9d86893274855cadd70d4f350236863489d6f559dff114dede8de400fc4484bcd2dfd1319e69a30b7023f292b51ac7a713be7191a0efba429ca1ce11f6c44406	\\x66d3f37918d9fd8e63ea129c69792ca09d8719727c014f2581070ab53c0a0fe3aae556a931b6d0bf97b31c0179aa109d95a4b1a1e80e08a09f95123e980c26f2b62de3d30c5f2dd51bb46340507c6d47f8737fc1a6e427e91c0e73df94622ffaff2b9666a6e472869123f9973ce1081728e524dc863a447c354a0dd85ed07263	\\x199cbaba14a74bcdb2c23b55d561081eceacb9ca4637cb23c2770ba4724bc80e5432c9e49a1d707bc4772b4d7e5a1c4ddd060fa8045418aad3a1bb3b34cd3fd7	\\x952fe196d6f9964ff1cfc322bb0a30698e8145bcd7955139e295509cbc9844beae5861dfb07f72f4cbf2c10457a4a9aef0abe11c40b0a4db21783349c3104a6892e6b1412924204045ed6b6b6a9f8582822c286e382eba3eae290c7e6d2f549a2969e2251d2e1bb96acef26bb6484ebdd0d454bd0695f8a866443a8c6989cd5f	41	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	5	\\x42595fa3b32db7175ef69609acf0348390289ec85dac68b2846449d3b474cec1b5793f98b545e4cb73e0923b450eb3c8b074cd6fa8b5646b20cf5d852c073c0d	\\x8f075778f81e137388f7233f4226d6eb2f2a2bb89ba7b18ec93653de3211cd32428442f6375168041627ab8ec84b03fc39ee664f9c3c66a06ad62ca1ca74ece92b0cc0cd0b19d80a143b6cb3f79c6c80951d9a07978cf7ca1b6cb453301bd5e9fab6d3157d34ed04b80302e19c22a948f605e5d944ef9bc9516f669bd0228804	\\xe917c70bf3f98a1c88295ead4269c8180aef83846fe7a13f2e0b8742161fa5c3ff157db3ff1abeef3e5ab6c315466390635d2076d5b7e07e38baa6e8458441ae	\\x28b36eccc4000033babd24054013e647244fed55750df0c5e40cf8db18bc633384d3ed750a9da3349e5ec8e72ba105b7516035e67840b9daf9801d465eb41ee19c0c9e2734c591dfe6031a8329c8d0cb69a1b7758e11f272859f44097fe45fdb3078516b422522675be165c2de5a26a53176c6f78440445057a2b914c671ff36	42	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	6	\\x9eb5699d8ec553a128bb58b9e53eab16b051eecc4639bc4cc1c7d9c7cc66dde244d700f353622f1ed9eb22e969b89595bb1b69e28838f4d3d9d22ff4188a160d	\\x18fbde6d4bb6787684c629eb2d1ad7c1f0f8aad80d4c1bdc8769c99193a2e235dbbf7cd2c91c2dc5c9ba71c2f7fc67c20d9a31a76f32144165801ef99d8dc8fed87e57ac16722e02aa84b33d796e3b902be94f1c7a111bd66c3da0e5da706b3a54b73d8975cba9618d8ab6cff1f6746c8f6bb81658bb2f99b1751f5736950e58	\\x2a64c179ab3b7d44dac291a2f621995d12a87a19bd1c0680bae47acb55e2ba041eb8621497ee4ef570802d9bcc96876c740a2b12d88e84e3db8c17e6f4ea432f	\\x71468da934bf9fd6f7eb7b01e5b95036a764fc4c45b5aa996d099c402c0e02595f7514293404ff7b644463579a78dc50511e7461b6daa7ef8576c023a00909ddf7db310284458ab6b17f8a1f096ee9f3366a09e7f70f73a5a21c6d92fd14b882aaedd60be25957d78f0dd26687a911affd3a306ae8833ecec72c03ac9b22204d	43	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	7	\\xf95e7fb53c5ecf54bc7a8f1b7bc2e7fbb2a1a11e4758dc1611aeb52bae93852135df361da6348431376caab00154d36af2b9100eb156e0de204168bd4b9c1a0e	\\x05c2a5a242949a80f37ebf0fb66ca810b149021519a30067e605f2febf64f58f3b33f06e2f7c6c606054ab0e2e34e6f351eda032599f816f541b6e2f33849ea36244cc340fd42f126f2072150e0673c02cb7fdb4a58c1a25edfd944367b986b165e3655af8e68e1c2c8033cb7d28b80a01736f5b366977a358a22131b011e27b	\\xaa2a0f7cf8b91b921af47a1a2173f333a9b6912d66a47e1b6d7988f45f540f81883f1b66615746411b4cd453ac4a64ab88e1c502d4beb3f584068a2e148d19f5	\\x050fe54920843161872ca165ffff2072e5a5e4b1dfea5d5b025e259ffbfe6e067aa9a7ccaa456782e47dc27e8607d7a4d9cdb07eb1eb7dc8cb9a70e972bf5a2aeeda574a5265aa8fe694eebedf48de1702af52fb3cda4537fd622c8fbf3bdb5f13fd5af05a438cfae9e865850a4c38843610523184e0e7a7d0417f67210bc4ed	44	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	8	\\x9b84a33b4275e2e4e4109c05c7847291629e2c32e390680e58fedb1c3f3c0fba6460db0d616f0ad4d6aa608f576bac83925534c420ec8d4ec78e7e591595aa01	\\x01ff4696d1d544f4f57d0ba8a6427a074c628177fbdac0572494798deae248e1b5d7f7e0c99962ec2fa2661720792c1b39a1d9a678f63f4362d6d7d621117f91671bb4f8f6876a26bc9c9e724a5c79435c0192ceabacd27fea82eb42a14373e9af6a330760c40a3712b8de0fbf94ce6e994305986cad6891ba153a6e1a6c96df	\\x1cbb92af8da357f590aae61aa1c2e098f98954106a4a535913a09ce7657d6176bb11e399ad8854e89907f84f21f9158643686f065dd186cca5a7f52d0398bbde	\\x9f238d2be4f2a98dcbbad7a3278057efadbb8963160fc640ae0924b3b2405c0510e407f3273cc4baceec553bfd8cc976afa12200471f259496eaaea48a98adf0b993140ea800c3456cd473ff69dce2e958badac16e204d52aad8363624803d0b0e42c318f5bd75dfe77018725bb66b4858beef19d51a86046da06d84f208aaec	45	13
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	9	\\x33c7ad5db08d2898cd7115baf9f29990247dda83cf238b0d46a5a22031b101fccf677e4784c33fe14908bce774df57d89c2ee69c5b2a341fc7e34a7bc85cb20d	\\x72170cd97bc8532c8836ffc8971ce421a6323fd7c802368b3b59cb8707e63e759ac6b363036ad085ffab65388a76ed08a1821bfa60fca17b3a064025e7bfa1e9283a61cb1a18ae79ad5789ba16e9520b6e8b8ba4241fd08e3cbf19c5afe264f3a73a8ce173b1158f7d557866deb878f1c2ef8ab8b54355ac70f8ab31e329c802	\\xc77df8876a0b7d49c2f15a97e130cf53b12ca9530fd7c26aa98a8bce95cd294fd1afa3724f5a89cb2fd758c48e24c3604dd11b338f1ce654b163bacf6acc8067	\\x652e857a472f306528c696fe4e03637986ae678728efad70b84891d288508b6a82c29d84c9e430eeee9c0ece5ecf9b998a3fb23339cf005411488787ff5a76eca08e1da07fa21c6065138be2d1b6332ade58d4e083ef0f647ce8ffadd2ea63d051e877767ce316559be8c13e8dd969c9720cab64934860a1a7084f585cbfbb2b	46	161
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	10	\\xb26f23bded9911dbd05e35a1aa7ef1039f8f44fb6f7ab4a3a449033075633077c67e720c3640e223d1d4ea55f3369814d251790cd4f5db7763d3c90d59670204	\\xbecbf4b3d4b9c35bd2b35ab1323024f6152e881c89a621d66a6c5d797f1751d51f74cd57e663a66bb74b1697f4c34a07a862e277a750733088e5c01e0f05feaab66f1c322662db801cb24aad46771d57fae6c4ee95f50617f8ca00659f59459a725dd13109f2029b52c624b5a98fd93498a17b764d551d1f0f595259d68d1444	\\xeb445b482f6ea83c6bee1ce1dc6e8bba48df7c44362f4bf19344b9f524f9dbe3eb7482d3e7598bbacc4457b1d18f54a5387fc3bdb410b3448ed87ff29977c8df	\\x0da4645c86c6cff3a21896e6252a6f9531cfc3a7be5951e727edd037f632580cd779a66c2335d72f84482ff4617c2259b905be935dfe84581922df4e764b755e54e8c897af9e8e0ab94868fad7680c75671ddb0b96739cc4707152d3c0e13dada5096895a84d789f979e85c68bff12181a8329a86a8b70f1b9bb22f1d566c8dc	47	161
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	11	\\x4c7f859708dcdd26c18b65bc9edc2ea88226335135e6a67a57fd2e376696dd6de8e02ffced4822526ef58d7888d275912252b35b1bb4430b9f170777cee1e402	\\xc015e5318f435da716c216968e67c852e13900c57b72df5588b748c890cec83d561001382f3adadfbb12aa058251d61cb34be6cb6bbd7cafc8320e2637251727ee1cb87633c6636b620dfa200949fc9dd94f2e5d0b073c083ec60767ca9c7dd780ec285673291c06bd9a3bf053b3d3e5668b3571900da61bd7d3c4e76fc9f6ba	\\x457d4b5fddfb9ecb90dbe6da7bac3413db2d7605148fb423d76d567bde2b7f7f4f83121b731d2b349cdbbe7a17b9efbb76f2dc13703e0cc971ae18ba4b662352	\\xbf44c66da8c0f7b2af7001e11970abb1de57c4556d4459d985da553ef071c255c6bfa9debc97be3667a2fe56fe09005e96234e1c0b3412b2f630d59526e1e0303789cc0f26b0e96f8f77ffa76989579382c3f665f30a7f81b3c2ec185238cb8cc527fafffedd82f0caba474ca0b8d0d8f3fb346beece10f894e96b9d1e785352	48	161
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\x19a679f78623921c98c671691e329e6ea9be1e44284dde7df7d604775c0799bbf9cb0b1b8907f5adce79ba65415812471c491a161c03c509019a5a5a24d8cbac	\\x4825e562503bcaadccab34a5161de02ef686feb7ee7d376ca1f5c1d90fdcf246	\\xc2ad4a8dfe64ec4929ccc8d15b79de72de9d6a6f200bf707b48d46b1d5def135e4e0826bdeba7bf1736cf5c6456ca32697951cd460de8b8a0e756830fa80e163	1
\\xea86c41b183a01e950eb980a898d4cf4cc92e4884a17cfd193b030249d910b22643eb47dd37660621092f53cec595369dacd1f99caeccd5155f3482979559f2f	\\x33a72985d9f1e8711bf9e9743496043adc621ce97b3c624c8d45c73861b9a831	\\x84ca2eb93f7d93716547ebdfc7bf748dd533b4700514c9a01ea1ce0d5cc2ec4bc2759c255736e24a92ad3cf762b01410a2daa3ef46ac3df0eb27a4c74fd765f5	2
\\x0427de8ecdf53239621e4f89ddecb272ce08aca0c4f53aa96da716e0faa97c51d1cd3f47da77c3dc8901cf257a2db004c598b5b325e44e9612bfdf511d9c12e1	\\xd45c4af5413e72fe61ea241991a3f28f08ae41f6ea991a8eba19d18b0848f55b	\\x27fa0c94705817619b7ca4e67e67052da9df11dd66b9ba45e582251f5aabe63ed9e08f66ee29e065cbd705c08b8cb96ae78b83b2dbfc621ccb79debf58ba3f9c	3
\\xe2e0224ccd5dab0dfbbd47263914d70dd70b52310e8d2049d0c76579de857ca8c4ae0495003e9a214cf3513454808dd1863a16551fb447110917a58bb1e7ebc4	\\x403e9b593954342fb62eb799f44288faa33c3b2f10c89b371642afcac364e210	\\xfc8253c480982235f0daf7736ccac16e3d16d3d1858fd164236d503c85166e618c3d0ad84845ae56733c0e23996a1d92664eabd1ba647af2477f134a624f11c5	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xdcaba1d9fd78169f715e5e636c47e3e4fffc859494f025ab6703c49a281267d4	\\x7d2978413e71d9cc7814dea188dc9d94eb4629a857ed5962a46350a89981bfcb	\\xb2a5bcaa8ee74ecf3cc863b59f041ab608a5779b1cdc0e748d2040edb101478d1db5a093d8689a922493af51c0780d49d54f77b1d8afd9abe3e0f8311b887005	\\x6272f032079cf53aa5e0d4425e1dd812b88ffe70cf189d37d91aa306301d1f43c183fb4aeaf264eebd72d674577b6034af897cfc3e251267f3051a24209bd576	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x3d32eaf8f0da446612f68aadd663fff6e28c86bf62e340fe6c433169eff19275	payto://x-taler-bank/localhost/testuser-tkR2w2k6	0	1000000	1612546230000000	1830879032000000	1
\\x8e80dccb7ff53571a16ce9c2fb8b72ad68e7723207e85f6bd64dce5256eeab6a	payto://x-taler-bank/localhost/testuser-MxPr3V35	0	1000000	1612546234000000	1830879039000000	2
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close (close_uuid, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac, reserve_uuid) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in (reserve_in_serial_id, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date, reserve_uuid) FROM stdin;
1	2	10	0	payto://x-taler-bank/localhost/testuser-tkR2w2k6	exchange-account-1	1610127030000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-MxPr3V35	exchange-account-1	1610127034000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x9d4508aebcac204e3b7d7c6ab8621ce5a1d0a64677a9412925251f9724f5c650940f80b13977a796a1a305c9047a508017fb2ad59108d7d333156ed0fd8b0b17	\\x887f21d6085dc03c75d0af606a4be7e8b07a8fe26ff33f9eb72d5a39c1b47a246bc55b374bc1e334cd413ef0d74e3ed4896adec531652cf7b6c797d47081a45828c3b87ae9509e7b4686a5052d26c893675cefaef355b15b6f905034167906105c44975159910c4f17ccdc4bcdf88029392f586bdd7556e4ed9812cd770aa6a7	\\x6d9444cf30e3f0d87f731aa0f3a9caa67187b39e92f37c4f0d8fc816497d72a0dc43cad2210fa2d10223afafe8b31bbec64d35bde368ead08f938a77d47cc408	1610127031000000	8	5000000	1	165
2	\\x2b0fdd44e0ebb85d7036dab26ec4afe7c5cca1fc001da52ba76fa491e2765bee6c3133ec987d1ca6223937f5ab79ea7e4809f5a609efa24826b0a0f84c341d3c	\\x504823f84ebf33c80f865970d4871383bf3596949fabdce4784b326278f47f5218cd759d55405897064df61b1e0e697efccda362aec68ad875def1ba448dfbe7b408ae1d3732e1115dcb26c9d96fd92f2f89099c438fda191b8abb8f77c2422560ce512bee45c9191704a6ea7f34ced0aca21257f2b44dcb593c32376bf340ba	\\xf0424e0e914d5432bd6db2ec64728e1e5cd4eb0138c7b031b2de01f74ea6ecee9b4addad7c15e8261793cf30e6aa1cad2c2790d3db44d97c1ada2333eb384204	1610127031000000	1	2000000	1	173
3	\\xc38b6289e3b70d1f68cc601d0f083bb76bd36f4d23fcd3fa8c8a74ad45de68dd9096dc1e940b0eee3d0cb903ba40520d3e5ecdbdbe69b5802c43cde0919734c1	\\x335ae17af68cf00292561c8581058e472bba79ee6cb616c7974a39fbd3b7a746809a39722c8ff6d3771685d364665d73ec6b96d8b92cd1548c654d166daaf653867fa606c893ae20584868b22276d16969b733e364524ef1b4ef945ff82b86e5463637c8ee83a0484bdca6ac37a9e2bb6b48759ba7a70d6ee6ea1850f027152b	\\xbae19211f758b57c01bd21fb9b5269a9daa6e900ffdbd54fd74bd6fe62ae07d74e6b1eccb8bd63e5ed2ebe27acb5c3defdb2d5a0e88437a258c1da0972f68803	1610127031000000	0	11000000	1	13
4	\\xb8665f8934f3e6a72df42bc13c630e22136f6e2d928a9782ba8ce0ff4586b654a76ec34196c3ba2eaf1c35fcd90652c6a947278bad8e56bcfaf213b07cb05343	\\x88370b4fab4481b20ddef4a12e953a38e0f54793ab9497c9e49bec1974f4392e3df05be6bb2a243d489ba84e965b93261255fda3b407645ab23ac0da585966b99d0b7e5e33bc2114e5d9468b0d0eb336d5e288bcd1100deff108a7e1af35ecb32ff78bf01ff33b59ff14e0c95b98e9df62da7251c2e935932080602964fed3cc	\\xdb24e49ceda217cf9cf14f67fa77a6b654399c0da021f46cc539431fcbdbd2b2b1261f04923487ed22960534a79c851c15017c0e7dac4d4d54d3870bf4f3970d	1610127031000000	0	11000000	1	13
5	\\x657a7ab861debc33cfae5c416919731bae4324a80e48d039bbdbaa6d623c37fe5788edb1e209ab933233d7e58f39f7cf523e258d0a5349645d2b32060da5d048	\\x803d7d6815dcce747ef48c9212055b49fb321ed1cacf24f49fb37e4b99318113f811c887d628d80e57e2cfe046b36f50431c19064872c14959331ecd861d3f9db521861430367729d7a48769e33f3b001a07c21c810e8975cf589c9648179d4f9e3ce7cc6fcc4ae60f4f41f153e0d2536feb1bf8ea9ccfa81bcef27b0a5a413f	\\x3f7f42d1a8162fc5a2cea4b8de1c370750f59d2e052c69fab2df3fa62cb56837f21a147a134d7142d0a253588fe187585007a67ea383a35b6f07411809b47b08	1610127031000000	0	11000000	1	13
6	\\x804d5039c639efafad70150e8787904973dd1f1d2475bcc6107d600ba88d1808828900d052e45b423a773b5a225cca3b961965274510aa220082712c3c126131	\\x76fb702ba3be4697e32f713655c0cd587a036f7cb92baaee05f349d6f8eec4eafd6dd3b90bcdf57fa4e5296972bb863515859dd988a5ea4e3ebb473e7171d2fa528f5028b60a8f7a8640c893b9c2a26968f1aaf2f46d0b294b4930879f04e6cda491d5d62e96ab229243f2c4fc672b924045de3d13e9a9a28fd840a4773ad11d	\\x20015c5d6c3ea13b5562698a685c2ad4799a9236be0fd182cd9fac39f0d401d1519cb041dc3444bb51bab3108c3620e67ff0c0e152a2ae62cc09bb1b5bb78f00	1610127031000000	0	11000000	1	13
7	\\x7097b934ccbc91d44336c8c81b458e829eff7e205c2813a8a093f09a01a36cc75359f6f4856f7621d1ccdccb7754c490ff564e61c701cc851618cfff38d08189	\\x84315b12f34bb35caad0521b7b2ad00ca1dee0664d45b2c865d4e132db10639ac85a4a431a0ea8c30cd2ca7838fe81cad415c70cc36add14704762f8f504b28770e7574f41540e03d51e6b39a139c9bfe11874e051a5dd6d42241fc98a28e29d0fbe4cc03e2abbd705d0182b67bfce588d5b1f4f002f116c6c6418af143d0c6c	\\x3f2a6602f502d89fd32559a747ea9885b338013333b0a5d6909e52fe0ba269da7ed1fd016ce70ba58a12035dc5f782321e18e1b99c31321e75d7de19bc5ba606	1610127031000000	0	11000000	1	13
8	\\x4143e6fdacfbf19df66f85f1e16f6398c255f73468beba8e7c88f0f5256dda4ad3f4c818b79373f5e2ed162e7a2220c94b3b873405e0e4f152260cce7bb47f42	\\x1501d4e64e7cda553f546f3fb5f5f2366fefa719b38bb0db92b584cb1d79da5403582904aae05d6fc043d09655d0771222139657e4dec0b69e967892163589fe241685d78c7787390048edc865be1f196a5ed4d06298a7cbdcc973449cc0fa8a83a83909278b3ebeb22e2cffd2537000634b4ac6755d5cc0ae8821ce8f1ba64e	\\xaafa5cf6f8481fe2d044ceb440c69e226b7b9d5c70ddc7b6611ca2c7cb8b406db0cb376f0bb2b573445ad5e587f0c590e7b766c22b98df94757eac4e30ed7902	1610127031000000	0	11000000	1	13
9	\\x1db8c6e5d2209911f44941e582176e4dfbb12669ff10f59a570699b7693da38cdf6e5b8c8d2d8ce344c78dc4aede32bca2828f098e6a07ee2c0d52d761649441	\\x01b77f0700b7a171b2ef90ae52861b610446e90862bc1cacc566620b26aaf31c12ebb6570c19a298bdae12b61e9b6c46c5dcec15890f669ae5ed14ce2112696eca069d8cbca218a1a78b15ed698b5c515fb32fa48cde60118dbab38a8d9de03524df22483eda013522970d1bb6722329815b401ee4ff7e05eb75986f26e9f634	\\xf32dee7d8dea6eb009527fd1af7d4f51c5f4b9c9bc41e0ac87bb821d42268aad0d93b580b3f0d16d5b3a89466c915aca81126e2fbabca729ba2d067a6e28c00c	1610127031000000	0	11000000	1	13
10	\\xc02a805042b49116ce6750be3090b291a60a56639904ac7de42c6d29b7204070495c0080845d8d195215684afcb94e024094d94188a4abf5a66d85b2f79c6c7a	\\x45aa10c68aa868d46c9e5126a0009c4cb3dd7c2798deea04c5ef63d11e541d10d54e4ea6ae39be36af46c465053fac03a0f234c29807bdc8a7d7c06f722c116b3d383e5c601b2469d924500139aab8735a2b5c90de5cef932d7075d4d2fd15ae25b5e88510f1f831d0571c54f2d30bc9107897044fd2ab006ca003bce552f44e	\\x729549661b42bd6a50583b8809865fc328653f08963eb756b7fdd2b629752989d2755f1d82690320577a8d5f943934472d29ba4792d3b19dad55380c5e4e8407	1610127032000000	0	11000000	1	13
11	\\xbc523055cefedf84ac4836fed222e2970fc688a28fc7b1a1b73e6269cc845125bb72cae851ce7606d748ea3e152d73ec4f05d36c8bbedb13a32f2d7962064c20	\\xb24a8c1749410284c0b89e0443bdced5aac69c2222c484c9a6a821689d79bf21f76cee3b06da13ae8a8643b0f6d1e0ee9b206b2821d6b449d1b667271eb7468967797a62e254988ae38f957e08ed5e6411a47449902cee359838b32bb559659a36f0f26740f009904c407550f85baa8d12125fc70578aa600ca251ada78620be	\\x8c84b5a0745d8d9329cd0570287abef1dea1a3c42e5e6f3169b1c4abaf094db254bf703c462a1aa171e2af0f338d91e4e6c837058996ddd6d810919521a9960f	1610127032000000	0	2000000	1	161
12	\\xc5acb5b2c6ed0889349221db623bc74c15d52be613ec22c6186e084e75aa361d4a2e1abdcad3063056c2cfdb060a660df3e5a513ebf2e4d095042d9cef886a86	\\x06915a6dcfca247a3fd68ef4aec8bac0d102c2e05718d6495a13fe73c11ef955ae144c4b1fe773c59f5311e68485f1a4699ea3c6e0f9f0a2f0a722f664c328c2077f66579fca0ee40c1acdea290cc14577f7c61c1db986a11df2307faed9897fdb3a9bd63657643d295a6f2f9806fabc5fa6818414b40a2c65f80b143a45d6bc	\\x240c86534e648b042da074bd190e29a633829c58b102342f0426d24af37841fb9bd4bc2fe2c68c2c0ee5b8c361d280c06e9abcfc76ba048a2f272a27a9251f02	1610127032000000	0	2000000	1	161
13	\\x16ea90beb2834827b6fbee204869985b7f860fe322dc5124cf746813b657ebf73c147b64b8e4c230590dc3445ddf73981bef44972ad6a35042682431ffe747f3	\\x6d9b21bfe80062f5de835aa4cab8a3c75bbff3df878cc072ee42a28b74b2daec7063fc35ad0d097c784e4d0cb71bb96917e88a3982fcc2f43ae0488d74b4893ec9d0aa0e6fa34a4889b7aba2174129c09e581b73aa1e524c301fe2c0cfb8fde49704a3c10f05ae4dab5d9ae867e7ffb2d6571442c5c57dd20996b5cde78355f8	\\x807f0ee0ee632d2958bcede93dfe00fd96a33ca0ecb4f395055cf5790dc23e0ab425f3bfc24ec0d287190f00e93a9a7cc373c351a81a47e6bddc8fed38027e08	1610127039000000	10	1000000	2	116
14	\\xb29a1fd911c3e2bda643da5cd45ceeb6a00699ace72dd835a922a927546fc3a538e8807b5b27d6f19f09f395382562337429b1ea3e34e0404fe104a2b9fce95c	\\xa6df4f51032323b16eb0757eccdb20d0dcd8b96543025c25be8197045abc14d7b9c54a4a545c8de3f973459b6a37266ea44ba3cecce956f60c9d6645ab595c4936b74b05614642ac157089905fd07354b0a01b40eea86330d859c3d74035e3cddc8159342a74f64fdb4c1d953480112b6e506afe877cacc48798d836276847ab	\\xc358c0a327fe9058324efa576821d1be2d55c883015444b1002851682af19ce4bc31a00ceed725ca93489b79fc5f7adde20543e08c4de27b9f34a52ec537fc07	1610127039000000	5	1000000	2	330
15	\\xb3a691312ea437eff8fc21255bdc61625d0c6247e3d9c2af8015d3890bdebd7f106f3c28b2e92f98f7e552fa58477887f9df589e84e8f1929f58372ec9b8336c	\\xca35d2f450adc834e91d5013d94342c1ccd4200d15631856faae51c89cbe0c36bf83fd896984d668e5a96262ad627ea168104b5b2907326f3e68c4811a57a5e32b5b43901794d881f35413c6deb7972eb31021f3d2f32b712dd1f5d206412638760139d18feb37aa39b1af568b2f121876f5698de6e22636e40877f05d2266c8	\\xae4b45a415e49c6514ed24587fbf1c5b7af0c99356b49cfe58d7728c825981c049a578cd8ebc59d0a3e0c8aa4bf01bd3c1cf291c70d2f35ad33da53e6b0d430e	1610127039000000	2	3000000	2	371
16	\\xc551b477f91f57ba45031c94db429f91298640611a512c48ec3e07bb6a95f02af4537e407dd21e0647914d828f5da256589e0d066be85e7a96e05f24d448b780	\\x2a8650883da87493eb9c39fcc8173d1e504f667916942cccdf0934aaa8e71e85a21ced0ecfa656b2f0b898899a9c088208f6a24cfbe76dac8b704949a4d3b03144376dfa3037116b6a6d98465c3850833c9bf5be61756193541b9014ab7621cd936a108fb84917bc943d5015c55ceff4cf0947387d31a5acd9baeacd6c907e4a	\\x470a55479941852caf00a686a37c97c2b309e900d0e6bfe5faf3fca13592dd1556dad4cc45ee957e3a4e6acbe70b8de024a2f9e97e7ff0638cff9cefeba28606	1610127039000000	0	11000000	2	13
17	\\x00f75404444e10a3dc2c426569f671841bfda4197a2e26fd57c6a8d74928127347a4f52a757ad967ba02342785f2ba11feafa15cb14869d079c09b9eac47b6e5	\\x54ee720a52187049bde0913db134060aad3f0bdc11620da600e2ceaf710b7613606ecea40a729ee12686ee4ce4357c3394220d93a72cd969fb28e54960f55bcd2cc2849b9c7e880da06a56f1ee216498e44afa158e007c987a19ad2c4378cb3d6e8a70b16dec9286e711fccef843132b308f77a15696f420877c7d50f11e5436	\\x0d26df5edcfaf76f95cf5ee87553118ebdf07cd4ab17c4fe6518c55817a9fc7e71b2e85db3b1a1a6187fbdf8dc781f1f6f331aed1384a6d51e774edcd62fc602	1610127039000000	0	11000000	2	13
18	\\x6eedf107e1d093cb7f54e7374ba47f5a44edd3cc19e6ee4df03d232ec1bf7712e1ac4602745ef38b14cf8b47e60122a6c0a70a390fca2ff1c7f40a7935291ffc	\\x157e35acb648a77726124908f54a020b901a3f773438015c928d664da5a7781b31c5012046fe402683ad39b438276221ec7be249822c769fc3eabc4ec8c207945cd142de1bbf3a78c87dfa2716de6aaf35e4f6e6346e0e29e1636cfeef1c22ba174d7f7b7d3a7233ed5cb40e54a7c1a795cc562b83b509ef24060fe7313824e5	\\x6925fc26d8180e8eba41e2d6f62749038f51af63949049f8cf67f394036decd8454c916890c286861a448ca73f2971386ecba16d43932502a2dc824a83a04d00	1610127039000000	0	11000000	2	13
19	\\x1e90713d5afd5fa51e2a9520f641d1ba97e8302c9d8b558026d1b8d501f645d582a730a516e5edec4c87f25d4596fef515ae6f4b873523824d865414dc664c5d	\\x9009ca384229b0112b0eb28a025ce159705e5078d5f77d6600b354c697a4610bad84d1c0c00e75304619a030bbdb3a6deb03b454efc35713d197cd9294c4b7f5ffeada3bc39f6b5081a3688dbfebe818cc122b880cfed729e9d7425fb2dcdf84cd2a03022a25698d387427a932975e0b442fdc986122f632890675daab8e4319	\\xade8c96602ba7c4b193255903d15a13f23f132b531cca9f07122444dba50497d6499774f4e77765f766003f9b3ef3b1a3654652271a20de78b9b2ebdd4ec400b	1610127039000000	0	11000000	2	13
20	\\x5183b582a3b86404c52ae8a1f90e5f836b4c7973a87b4ea03a9d8f3b084f1770cbe46ae220a9355722d04a8712da864d6d68498ec15ce268ba92da4379f5d96a	\\x4dde7118dd13498641bedc26475fe2ed49ef003532e3e6d8ab3ff9e99ace16af387e104ce764b9c17fa61db1297fdf642505cd4e1f93f5571121d27a2a2113eedfdf023c9889dbbb5ee38293fa8a8f901e5296a16cc8a270f57a0cfb0800526fd763a6ab3fa572f639daf663be069a2671d85d980dceb09412a2f6345394e1f6	\\xb86404208b6ec798243107c26126b1075213c512fc36c010c8b1ecb0ea1a6cff8882260646c10a1061d4f40096c9bef5340ac5648253ef65d843ddaa8e992704	1610127039000000	0	11000000	2	13
21	\\xc73d35f93fd9709b65d5e65dbdcd02d9d9fe89b291bf9ba5388c48950f2bbf6672ec15b6ea47d16101c224633953264a24953555e5efe9197f8ad06617220a5f	\\x996d3a9fb08772b377b0dbb6ab44733a7293fd9c217ce47513a6dc3c0717265a707da8c072ce34b4586b3492cfb195585295b326d2668cf66fb6226c07339e563dc70c0cf31ef0c1d126c6c7fa44fdf5fec26ccdb717c08e73be0336a728056c9fe5516270ac7677f88833a547c97b6ede3bfb05f508059b1777d598e855a342	\\x99eaf68a45e993ebc0d0d9ad553719ee215f277ea4226b6f17958adf6e151a97e520e6eb0739540cc15843bc2102a6e34526627916bb1ca1c2c2089c3311870b	1610127039000000	0	11000000	2	13
22	\\xb6afb0a220cab7161e8140b55338dae9f5f9fbdfdffa304343915ff86dc6303a687dea0704b386f56da2ff964d599ffc1b7e109087565e02d7e91e48e1066be3	\\x44ba73451115112b00eeae30762e27e41fba1ae07ba110833db7cb0118dee27898b45747a092a87289ac22cb1381cb3784968a6107f5f34a93c81b93f909850ffa6b7b918286b792b7486ed70ff0905fc0c9e6334817de83594e3821c52c0b6f5510fb31adfeda476cf57d5b5e466e35590b0584a1bb92ce8d6ba2745b75095d	\\x31d70d46a0d6b79eca390a5439edae09e33b4083b4f85559ee2b99f667e88c14e40b895c27b38c140de7ccf9aca86573d093bfb73fe83ca80a39faa65dcea908	1610127039000000	0	11000000	2	13
23	\\xa35b363bf25360c63169fe1a7b0dfa70f689b021f267289090ed012dc0398db436df821c35bc87f66e7c0ff86a9acca544bbdfa1be648ed563c735d29df96ba2	\\x8e08d74fd1e0a9a2c8ce9c286cc94a586afb44903fb12e545a7bf8abdaec529975bd36c198810ac1eeb4970d81d5524c925fad8e01cf02283563e88aabd8edd34559f58af79493d1fc75f8a5fa79beebb49bef71ed25990bf049622491d06f61ca8e000dd2295b2fc5ec43eef456b5484a7df4fefb7494272507ccf91d7ea5cc	\\x0d11c583182efcd39f433e9af507b9f3330adc2a425817f24544f423655983c52dd017ea43d8a8d2b0137f8074f09bb3733b66715f2977455d05e9226c042d0b	1610127039000000	0	11000000	2	13
24	\\x4d50141eef049f75b71ef2efc46e3a4cab46050f0d1b5979865fcb1ae61062232a6104280769e76c0ee6c2909e51a0f3c88afc7c54430547409f3eb65bfeb1a2	\\x381de5ef49447abde9413ae83cc5ebbad01638c5a9576a4b05536167f67fac466d974037504dd0e7674c73bd9dacc46ae9a397444b87741816bec221a11632001eae4efc8a28df57f0848c8ef3d548a9cf4dbbc80418d5fb4676795f56294ae8044dd6cf26bf4b0f9fe18300054f4526791ec47aa0b6ff4e956b0fc128d6a950	\\x38d8bed252a3e1930665bcd037f7512d351b6e14244bb3025201861f976b93637651d08e81c2b8bb7fdb7c0a01ac5a6aa3f7d03fa97fa6d4432f41dbec3b3f08	1610127039000000	0	2000000	2	161
25	\\x64be55b3bf14ff4748dd64e9357e43ae3c9506dee0f6b3932934db77a5265218beb5889cff8af2ce2fc2ab715b3c76080d882f689954d5ea9989801edfcfc64d	\\xb0c46d791801e7160c264d2cb6df3d816de16bfa4e347fc6b9860f418e83a1083f76f02eef761801da4012b65abcf91f4c6ac79c31d00a04f949242713500e06da49a768ddadb7cdc79fd164691f7740245a3edc8330c01a0abc2e42ec47ded684bd972e33ad9ce891db1879404d6c74eda5174d794bdbfe5cb9d1bc46f5a37b	\\xeee5691e9d543cee334caed6a648da8bd16ef6dc2790d8c553ccf12c4591ae12fa368913f2f411f5255ad1ee24da733118c581f9d0b1991b019d00684d675a07	1610127039000000	0	2000000	2	161
26	\\xd9fc834e5621bc6ddbfadbecb0e5c8933edfadf87080ebec5c375a592359546ca7488666b6c4e5100d6fdd2fc6dc0a969d8bef7c27721dde16fc82102e192360	\\x6d9f187cc10b467b6cc50cacb8aa1f7ba5751ad1720ff0cd31a1b3f15c39c2c8efe2cc645e298a0a846cca9706d5ad096948994cb20480051f9267941a90d0d7b0ecf83b84505a7da75f5c04a824c3c25ad8a6b8276dc5fc200819ab2f262d2f15586f76606e9a6ba54012f54328a752d93d346a111099f55c3adf9f3b111a56	\\x72f52dd5310aa6e052654705f056c105c495f5be88ca31a15a89d4ee2c29cdabad0de4e683792cf857416149d76cbd5ae3778f0bd8bee4c31e984b6a502d7a0c	1610127039000000	0	2000000	2	161
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.signkey_revocations (signkey_revocations_serial_id, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\xfedc396949cd127c483d408763267923474825a97170474511beafec03a079f2962c4768007d835f16b641160ecf0137cb07a64f12142c4b22a9f1734d75f800	t	1610127014000000
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

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig, wire_fee_serial) FROM stdin;
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x7673269a24f57e3dcf09c917c2cdad26a7cbaaea3b6c229fec460e313a90c7db49006862a33246ec7ce172a9578874321e8309aeb4f7a2a0a70ff427ccc74c0e	1
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
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 424, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditors_auditor_uuid_seq', 1, true);


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
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denominations_denominations_serial_seq', 424, true);


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

SELECT pg_catalog.setval('public.django_migrations_id_seq', 16, true);


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exchange_sign_keys_esk_serial_seq', 5, true);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 3, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 3, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 5, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 1, true);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_instances_merchant_serial_seq', 1, true);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 3, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, true);


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_pickups_pickup_serial_seq', 1, false);


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_reserves_reserve_serial_seq', 1, false);


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tips_tip_serial_seq', 1, false);


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_transfers_credit_serial_seq', 1, false);


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
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 48, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 4, true);


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
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 2, true);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_fee_wire_fee_serial_seq', 1, true);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_denom_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_denom_serial_key UNIQUE (auditor_denom_serial);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_uuid);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: auditors auditors_auditor_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_auditor_uuid_key UNIQUE (auditor_uuid);


--
-- Name: auditors auditors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_pkey PRIMARY KEY (auditor_pub);


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
-- Name: denominations denominations_denominations_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_denominations_serial_key UNIQUE (denominations_serial);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: denomination_revocations denominations_serial_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denominations_serial_pk PRIMARY KEY (denominations_serial);


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
-- Name: exchange_sign_keys exchange_sign_keys_esk_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_esk_serial_key UNIQUE (esk_serial);


--
-- Name: exchange_sign_keys exchange_sign_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_pkey PRIMARY KEY (exchange_pub);


--
-- Name: known_coins known_coins_known_coin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_known_coin_id_key UNIQUE (known_coin_id);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_key UNIQUE (merchant_serial);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_payto_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_payto_uri_key UNIQUE (merchant_serial, payto_uri);


--
-- Name: merchant_accounts merchant_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_pkey PRIMARY KEY (account_serial);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_h_contract_terms_key UNIQUE (merchant_serial, h_contract_terms);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_credit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_credit_serial_key UNIQUE (deposit_serial, credit_serial);


--
-- Name: merchant_deposits merchant_deposits_order_serial_coin_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_coin_pub_key UNIQUE (order_serial, coin_pub);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (deposit_serial);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_key_exchange_pub_start_date_maste_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_key_exchange_pub_start_date_maste_key UNIQUE (exchange_pub, start_date, master_pub);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_keys_pkey PRIMARY KEY (signkey_serial);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_master_pub_h_wire_method_start__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_master_pub_h_wire_method_start__key UNIQUE (master_pub, h_wire_method, start_date);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_pkey PRIMARY KEY (wirefee_serial);


--
-- Name: merchant_instances merchant_instances_merchant_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_id_key UNIQUE (merchant_id);


--
-- Name: merchant_instances merchant_instances_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_pub_key UNIQUE (merchant_pub);


--
-- Name: merchant_instances merchant_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_product_id_key UNIQUE (merchant_serial, product_id);


--
-- Name: merchant_inventory merchant_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_pkey PRIMARY KEY (product_serial);


--
-- Name: merchant_keys merchant_keys_merchant_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_priv_key UNIQUE (merchant_priv);


--
-- Name: merchant_keys merchant_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_refund_proofs merchant_refund_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_refunds merchant_refunds_order_serial_coin_pub_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_coin_pub_rtransaction_id_key UNIQUE (order_serial, coin_pub, rtransaction_id);


--
-- Name: merchant_refunds merchant_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pkey PRIMARY KEY (pickup_serial, coin_offset);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pickup_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pickup_id_key UNIQUE (pickup_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_serial);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_priv_key UNIQUE (reserve_priv);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_key UNIQUE (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_reserve_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_reserve_pub_key UNIQUE (reserve_pub);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_serial);


--
-- Name: merchant_tips merchant_tips_tip_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_tip_id_key UNIQUE (tip_id);


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_key UNIQUE (deposit_serial);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_key UNIQUE (wtid, exchange_url);


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
-- Name: refresh_revealed_coins refresh_revealed_coins_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rtc_serial_key UNIQUE (rtc_serial);


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
-- Name: reserves reserves_reserve_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_reserve_uuid_key UNIQUE (reserve_uuid);


--
-- Name: signkey_revocations signkey_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (exchange_pub);


--
-- Name: signkey_revocations signkey_revocations_signkey_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_signkey_revocations_serial_id_key UNIQUE (signkey_revocations_serial_id);


--
-- Name: wire_accounts wire_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_accounts
    ADD CONSTRAINT wire_accounts_pkey PRIMARY KEY (payto_uri);


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
-- Name: wire_fee wire_fee_wire_fee_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_wire_fee_serial_key UNIQUE (wire_fee_serial);


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
-- Name: merchant_contract_terms_by_merchant_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_expiration ON public.merchant_contract_terms USING btree (merchant_serial, pay_deadline);


--
-- Name: merchant_contract_terms_by_merchant_and_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_payment ON public.merchant_contract_terms USING btree (merchant_serial, paid);


--
-- Name: merchant_contract_terms_by_merchant_session_and_fulfillment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_session_and_fulfillment ON public.merchant_contract_terms USING btree (merchant_serial, fulfillment_url, session_id);


--
-- Name: merchant_inventory_locks_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_expiration ON public.merchant_inventory_locks USING btree (expiration);


--
-- Name: merchant_inventory_locks_by_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_uuid ON public.merchant_inventory_locks USING btree (lock_uuid);


--
-- Name: merchant_orders_by_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_creation_time ON public.merchant_orders USING btree (creation_time);


--
-- Name: merchant_orders_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_expiration ON public.merchant_orders USING btree (pay_deadline);


--
-- Name: merchant_orders_locks_by_order_and_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_locks_by_order_and_product ON public.merchant_order_locks USING btree (order_serial, product_serial);


--
-- Name: merchant_refunds_by_coin_and_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_refunds_by_coin_and_order ON public.merchant_refunds USING btree (coin_pub, order_serial);


--
-- Name: merchant_tip_reserves_by_exchange_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_exchange_balance ON public.merchant_tip_reserves USING btree (exchange_initial_balance_val, exchange_initial_balance_frac);


--
-- Name: merchant_tip_reserves_by_merchant_serial_and_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_merchant_serial_and_creation_time ON public.merchant_tip_reserves USING btree (merchant_serial, creation_time);


--
-- Name: merchant_tip_reserves_by_reserve_pub_and_merchant_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_reserve_pub_and_merchant_serial ON public.merchant_tip_reserves USING btree (reserve_pub, merchant_serial, creation_time);


--
-- Name: merchant_tips_by_pickup_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tips_by_pickup_and_expiration ON public.merchant_tips USING btree (was_picked_up, expiration);


--
-- Name: merchant_transfers_by_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_credit ON public.merchant_transfer_to_coin USING btree (credit_serial);


--
-- Name: prepare_get_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_get_index ON public.prewire USING btree (failed, finished);


--
-- Name: INDEX prepare_get_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prepare_get_index IS 'for wire_prepare_data_get';


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: INDEX prepare_iteration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prepare_iteration_index IS 'for gc_prewire';


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_uuid_fkey FOREIGN KEY (auditor_uuid) REFERENCES public.auditors(auditor_uuid) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


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
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
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
-- Name: merchant_accounts merchant_accounts_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_inventory_locks merchant_inventory_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory_locks
    ADD CONSTRAINT merchant_inventory_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_keys merchant_keys_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_orders(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_refund_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_refund_serial_fkey FOREIGN KEY (refund_serial) REFERENCES public.merchant_refunds(refund_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_refunds merchant_refunds_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pickup_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pickup_serial_fkey FOREIGN KEY (pickup_serial) REFERENCES public.merchant_tip_pickups(pickup_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_serial_fkey FOREIGN KEY (tip_serial) REFERENCES public.merchant_tips(tip_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserves merchant_tip_reserves_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_tips merchant_tips_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfers merchant_transfers_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


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
-- Name: refresh_revealed_coins refresh_revealed_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


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
-- Name: reserves_close reserves_close_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: signkey_revocations signkey_revocations_exchange_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_exchange_pub_fkey FOREIGN KEY (exchange_pub) REFERENCES public.exchange_sign_keys(exchange_pub) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

