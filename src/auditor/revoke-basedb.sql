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
exchange-0001	2021-01-08 19:09:49.180223+01	grothoff	{}	{}
exchange-0002	2021-01-08 19:09:49.289175+01	grothoff	{}	{}
merchant-0001	2021-01-08 19:09:49.481179+01	grothoff	{}	{}
auditor-0001	2021-01-08 19:09:49.622227+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-08 19:09:57.059523+01	f	9cd90f9c-6896-4a58-a502-807b5d5feb91	11	1
2	TESTKUDOS:8	1Q019TPPRKA399R5H108T6BPXPGKMRZA0CHGWD8N83QKS7HQKRNG	2021-01-08 19:10:13.019367+01	f	b917f026-73f2-49fe-8dd3-1774a764ad16	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
458d56bc-c7b4-4938-8360-b73f241d9841	TESTKUDOS:8	t	t	f	1Q019TPPRKA399R5H108T6BPXPGKMRZA0CHGWD8N83QKS7HQKRNG	2	11
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
1	1	92	\\xf9f48bd6ffc1461982ad131d8602c737ce4b189042f2a1bd28119cbc79d7f8e6488f2ec1407f271b43760089e2deb3854ff1acd6bc1e79ad8f5a5ad3ea45c602
2	1	63	\\x0b1e61228c4aa23b84b1cf9db856417e1bba106937e57e7ebbacf4b228f04f2e2629eccfc7b5bbe594d2a6fd8df1fb1c441f28d2148aa300779a1791dbc8ec05
3	1	84	\\x3f1e81b8eef7ad47cbf5d502bc46c7bc338c53e355fb7a3ef80f9018a72389f8289f427b28b3a82a43d4cc6b6edad4c74ee3231c4d5f535cacb391208d4b1b00
4	1	150	\\x67e0c36ecd2724136b268c52a10f2d2206ed5cf823f791070850a08b1cfa84ecb8f532353a768d043804ae806e29796583f923afd1019d91d8a3304697d4a908
5	1	179	\\x9d1fab9dd21d053ab7e091e2b92288f31ea65aebffbd684c7cd6fa93812aaf284d75b56bba7206f7e6c926212161b94dfdf2abf7fb09de62131719a0fdbc5500
6	1	306	\\xf0d09cddf671023f6f04a178925cef5c0af46ec08bf1a7899fae5c0e0db6bf47d260dde2363d4ec3a8b216f8057eab34adbb8b38873d0d087f617d1880a97c0d
7	1	167	\\xb52148e618ef986ed107778bd0300550e8121a0aab7ee32ca3dee2adc31d58cfd429cd210803870787f2df289f443c1b998fe082c42c42637c8aa56285dd2202
8	1	178	\\x2f4d4dcff02a1465361629ac11fa2b8638b00e353a924d443894fb301839f941cdfbee14da4d0ece60efe6c428eedaac8d81c3186e4b1c3c1daf2b59f5e38808
9	1	119	\\xc874e1dff409744d6c25bbe2aa374ddd6d3a905ca1f7a5fedf69b620eb62a3fe89ac979d6071c2bd7bd905f38b32c27ae68c1581efd0098d1cf22455d3166d06
10	1	98	\\x858b97cfe45eae60c24bb980104532c0bde457808e51def4c72711d49e5ddbfb7e8be6380f5a9721a70353536e998b7f3abb697ae973bd27660e90474516730e
11	1	29	\\x06fe30d4469d39ebf8cbcdd89f3cd5594ec56420eb5bb49f1f34a9690804f5841d1754348c7f44c59cd3a22ae64da540006b5fd9102d1740fa13bcdf2331df0f
12	1	34	\\x1e810ab0f239e5c31d0d473fc46afeeb9437d421b2150254bfbb0f8f7fb850f032ee34f3714d5d6ba6fd548ef91219dc804657ed884e7cfdb655c8abf2472008
13	1	141	\\xb2b08159182eb164995e37f971bfc724dc87d8679a329fd3be5736ce6bc219e7c46a725e89ba592598137d6f67ebf84ef185718329b0984dfe972ff22250e70b
14	1	278	\\xb90ab5f45ab0d6ef4c1fda6907f6ff34a98ff8774e88db7248ced82f4a072dc7e1cb029696dcb17ced182a1c602cc9ba89289020f9b311dec449de0612feff00
15	1	404	\\x316a186576cd30cd6b9d1cde50c343b4299aa7d3e752570e6136887a87f0d70c29e573855dde9302b76e0ca9cc8d3329e37152bf6e385cadb8b6fdcbddb2e60d
16	1	412	\\xce863723c7ef7788e4fd75b80b01175e38071a5387bc13b1a7e1cf054f2a78ffb91e7113e6ad9d2da21084c1108f702cad0b6814e9459d41428359a8b201d30b
17	1	202	\\xba743c947d4255163a5e30abeaaabc7c3d1a1978641915bb208061e9d7daa642bc835b0c13ecda6799128c62a7d60e6f25a82b6b8bb7e7b26da799ca04d1bc0a
18	1	204	\\xe219980c562975210ddf44753d3389395ab1033a816763c6604184edf46770daeee86d86c6615b5b5ba91a32469b8195d0d7e5d3ed627d6287541b68c4068a0d
19	1	285	\\x856df07b3b672431b41ab1fc1f5af4fb735a0d7e42bc40d7bc222392b791965c779ad0a6e5633ce27378f1ad180aaafe8223c6a105773f1c14040eccba1eb20b
20	1	22	\\x8cb8467913926dd51e853bd0444c2b9675a3160e94b32d88042deaf92fd350dd2026419488cfc0514449c4c9453f5b32f8a18ee0797e4b45676cde8697068104
21	1	235	\\x068669dfd16029d569973922c3800ccdc241c014e29b66f7ba238791f6fdc701eb7a9d2df230983c967b0788648020703651a9f25cf322a7cbbc19cb1f713e0c
22	1	297	\\x16de467eb62a79b4297b697916194e97912d85f6df41f27309dfd5633daec3e6f8083c39412f59d1de64b48d5fa393f676e10b1233a11eeca77a8e776a14dc0a
23	1	419	\\x664adc2b86076cae6a0a9373b39e7feb0e7e37f2154311e073a857ee6588f073225fb8e0fcb47ce38d7f86db5218b9bc96669869229ba23e972757146aa72809
24	1	206	\\xce5ac8e83433ac6e2e063ced53544fe6dc9479cb9256544d33c80618ba13ea57a8f5d71c13fb50cbd0468ad58b750069d8a9d1f88fdd5aff5aaeb712bd626c0e
25	1	82	\\xe9e3314b1df3f8d2d56f4980f3b585871caeee02bd956c3823ab3c4febcdcf4747d66da1aceccf5edbce6eb1ae39a336a0f1594de22de1df852fb0188f58840f
26	1	69	\\xee91be24d7146a55c2ff1154998ff277dd2825aad28a23a3a5181bed7223b17cfd8e29eec1f61df40d461e2636c5999bf12cf5c0808a8912121aca95b7641308
27	1	390	\\x8b32e46dd31dee4a702be2221226825b77eafd896b8c06d0495924d71bf7054bb04b3d61059c84c76ba6fe903bc0dd6fc0e6ed53fd40fccbed6e7f8a8635ed04
28	1	348	\\xf8860b795582e7d708e8fce6f38592a38d07874326c97b92d366f690c7754de4c5c300d3fdda8741aa4ebb017b1e308b25c43eaf5ce92a02d2bfaed7c3a3fa02
29	1	269	\\xdd63a9fa171d4fe8a11a0badec74eae38c809872cf38d6882e3188e82708bff08d9464bf64a69a2d512b741476a9c0424d7ff58c5f042142cc51493cbc32e007
30	1	382	\\xa979892806d240f3d63f5c570a3bae575695b54c9a1b9dba8200954f9a02ebcb713f16be285ebf87933af43c1941e42c0e10e94c569cbf845f46650fc5efab09
31	1	146	\\x5fd39b27771a77a0bbc0851a9ad34131b42162e27617e80a3ccd6076290fffe9660c3c5fbef88e39f325250d90e2d0e039fd5938df1aca766382d1701b8ff20e
32	1	377	\\x27b28f3b2ec4b5456d1d6e0634b2140fee752621f0aef1a5482be45a112f336c685f645c9b5f116e7201fa8d874992798873e9fa7bfe355a959ddb7cbe1d6009
33	1	385	\\x2c8c7b1778c707a2be00f707507648d76e27b8e89178c63904c7cd45e1ea5d9782911d3ddbc65cea391c2c141945f72d151fc82c19195071f817982be631470d
34	1	408	\\x2bd30ead68cb7e491cff007b4dede9e49ab4e5d4329d7c2aaf770efccc1849b05e3eb71dcc2bec858a99af4d10846ea8eeb03d8d830a3e2fcc824122d6c95409
35	1	282	\\xbd08267689bd1cdc1e71775268eb6aeb90a99077a030800ce623edd903f4e42b7dfa25c9b8588c26b6994b3004dda69cb5e4f29bbca50988609c89f6d7a6a003
36	1	113	\\x17e1a4be83deb3278e22c7875863b3818dde2a6eb1a4d40480b038d66eaf5a2ba5f75f960f486916ae756d5ceb3b1ca4b652f07e939ddf1c004d47c4095f010e
37	1	296	\\xd08bc4d6f86b7eda0e6893f01d673b2cca272e6cf4a83551bd6342b72dd81a7ff6f6f15bd8a648a70a1a0e270d06107e802e1fbc8dbc03320f6e548ca136ba06
38	1	210	\\x8655e9f9044458b183361f8f2cf2b9251a3250ddb74fe5085f21a5fd7b8c07512a805e97cbcf9f2055f74d4598f8b6c4712f9948b8e05d818fecdae787802f04
39	1	147	\\xf985d30f436ab33f86cb2a4103dc9c047bb7f4fc31414cbbec05b9cb68c485db21719d0936ea6e81ee9e0216a0bc54b5a51c03590b542b5cab392522ba3c0107
40	1	200	\\xc6a73b44db316c6c8f534fdfa24dbc76a59f405cc1ea66d3e78827a9e154a288ed9581f5b352882f5bdcc5c380ceca40ddd2737429e7c286eeaede5ef9e5f501
41	1	420	\\xbb8a3deebb60f769f5243c1ce332af97c3f83a675f35a878043e8d9ab5cfeb0a08c33a31cf50ede013e714fa8d081e9ae50f0a7fb0dcd19b76ca1c73b9569304
42	1	247	\\x09f0e0e565d8c7dd39bc8dcfe92336554455e8a35db651eeab70a75e241724e00bde2be2d64f34b17146c66c0c17568ae14d406442b8b2867a73acd684032706
43	1	289	\\x3ed8c38150e8ef0686e0a67c9ba0894fe5a66429ac5216764ec91174d5d0d978f8543798cad53f02006e6817840ce65021a17e8553444e6c43347f5e18d3d408
44	1	274	\\x7ffe0d1ecf5684d0ef24cfd256a3ca91ddb29e434e7484d1fd237093d3f36f127a87f077d08f417196042d0e5578ff2a581f8f3691b2a2e8f590261979825a0c
45	1	374	\\x2874f1c9cc7998ab7d10761af30996f6290a0be6a6c43eae456b0951d9ee806eaed9af6bcdb262446f608621960721347474dfa1102ac8e05f7e09247203c700
46	1	355	\\xf1a821a64dc38238827b3b4fd7c5e3b959ac93166dbcbd168b98cfe908e8eff2e88db26f2424ddd2890d219d7012ddef0e0b709bf46b862288d20ec3f3e12609
49	1	342	\\xe6077622207d613e54ba38c6179bb55581db1e26c3c1f8f787bd59726fad6f3368cfbf0d222d2a7e2781ad315589dd2d5887e00e362ec106180e7f1b1e1e440a
47	1	158	\\x391b73091457aabec38c6a62d320157a98cfc4940f08c7dae527f22cbf8606f87bc3302ab28e1e4f6d2b26c49fd49d7579832437cc0700a3ea36dca3f282c907
48	1	61	\\x0513f3e72d0f6f2c9ab2ce061639e13f8a4c6d939b24208444cad317ec30046fbbc063e09291ed7e889e3400780bcb32b2034de966947dc31a65d53a50a67801
50	1	14	\\x4afad932d70ce7b357c415783a69e7593969fddf01418a9da9c236a20022660c13b4595e398a52bbf98b2e05a0ae49ff3691f8eeee89a05e0217f7972739670a
51	1	8	\\x6d6d1004c05b5eb73c36879caef1edb006a69ea9bd686e69dd5163854ee527345ab0885461cf5e7db3b6e6d89d916dc663c0046e0836ac6500348565689ec809
52	1	305	\\x0a7f23245a7ccb6f030aa9167d6c5d8990b90e4cc39420989ec40916d3b9e3f77a2967bc9d38867351a36405a39bb5f4eae9aeefe0be5f82671d821aa0dda405
53	1	6	\\x529b689e70332669011416bd5557e7faba74fa44ea946f3a80aa9b72e2a2bc3a474c9681d977fce1e98919c85177029c7fb3a4df56fc12f0f3473aed000fd303
54	1	112	\\xaedd82caff44d79e6db6662550bfd094c9f0ad90710fa7f6a4c9494162d6d89e59f6392872b2d9d2c8b459e830cf001856754437e05b2f56ac21871c60d9f00d
55	1	389	\\xc2b11c01951c08d4689c5a9f06fedced2c78e4ab0320aed450876e21cb116b563d3b847ca9bef5ac316052a26dd6f9320f05bc09dbbd000ff37033ec61932408
56	1	203	\\x5906bb96a3a7a397a768835045e2f06771b22ced9f3b7afeeac76f4cd9de0f6191ce29793c4d4d9324c3ce5e6328b658787a9648f73dfb14f9b9590eb3c45a0a
57	1	30	\\x0145911da566cf807940ef559a305caa0d46ea248e05a3a4b0504f86cd021410b754899f027294b6b20bd96ef02d07651d02cc95472ea2804e69363935437200
58	1	49	\\x3a205220d5f7b020416cc9e090190403199971c3308145a00f9623bf73f8a0f11b5e6522e517297048de5a0731b4c9b0710cff171ffc4834755b70e935b5a604
59	1	25	\\xcacd0f46dc494e4349ac462f98d38749f7a4cd6403b7cb082801adc5b75d7360ffce2e79b6fc013d18bd4f2bc59a14c0ad2d3e5692544159a2392e07e3d0690b
61	1	100	\\x526af3d9a097d53d07e03fc93bf174791c07c9fcdd3e0881eabf18d9de43db59a5608c56f291af59d80742204435f9e1b215be04643dac46dfd341cfbc28520e
60	1	20	\\xfb708a09be1eb274d8d46c7ab6183e2ce482a5374a203262dc481afae5e4d8cecf17960a9dc0b0a767293adb3282a531e3014ca1e5a5ece26e1026abe4545d07
62	1	168	\\x069805e5e895ac0616161c8f54f5f5b01a37b917c396245477fdfe9a54764291f62bf19a01e628a86c2d827018a2eb39716a280f226fc2bd6f6d35f9431a4100
63	1	89	\\x0f382daf61c72357bfb79071b40b36ed88c1d689ab4815c4c02b7ad54b3cfea5c97e0dcf803a72373287e9fa8de769d453cf12f4892ccadb23b221b34c17c70e
64	1	185	\\x90a6621209a3f67c6d5967f0b844fe44c4ee5ca7b72c7b4ec1150c07082daf0722ab1c19f86d5f26c651d46f16aac2d7b9c148f524c94589b22678122edac00d
65	1	328	\\x2b36a820653933b05317b2c53d63f7e7c7870c05bc7dc8cbd2fa67257117dfa81ed3ee8a7170a92e58e85f61cd92c7fe4d617aa3816a16b264ba8cbffdbf080a
66	1	72	\\xc6771a3208c0ee09fa7bc33bcd0e6b8c0ce0266d3c1dd7b519291fa0f26ae577c8db869b125c8d493c839ea4b3eca9ec09da26d99feaf145a80325b4690f5e0d
73	1	307	\\xc79ca2bfc014de55f3689c76610ee9cfc71f14cf448006dd4506acb1b0eb1747569f259f12a05933942e5553371de9227233e1786c4c2aeb2d93127589cb7a0c
80	1	21	\\x5de6379d13b1bcd0269abe03806cc3e92bd1b74f89308f95ab9ca41176e811667e1e651f50cc6d396dbeae34e622b87e8f56a31d20f8e8638a624fe5c9f34f06
88	1	319	\\x0db878fb3a6483f9efcc1c65918a49f0a92b133ecb72c22301b4c02cd31dd3d1c1f62b4af69d250ac7635d26ac6a25e242e0342af71b324901b4a083c8eabc02
95	1	131	\\x0c7ff523c89fed882433ce11e78e46615175e3bbcd54c69f42f7166815503b82c89b6d47806d3366f946d9923f62ac3c100635877e4b2042f7356e5de9410803
103	1	176	\\x982f2236e4d599fcc588831ee6fd96151c2e8ec9a90c0150cf850a1ce4815b1253767c443d154df9fbb43ad30fe5a9144615e8cfbd1c632b66524b98cfd21101
113	1	410	\\x473b32ab0840f0031d967b02a94eb1489245fb95b1bb55f82e4a3247f786bc8bf0e4df8662351ad802278f1870f50e49e5a951295d7f16136afaca5fc6b9e60b
119	1	7	\\xc7717443ae764852173a5f3e8b0b42c26c04a8feef74f9dca574cd3d42104a631a6f8f973031b844d6265e63f4dea825318bc6d239ea2494fda672ee16b0f701
131	1	175	\\xd6a04c7f9360d0f0115757d9c6bc58d10c112ec0cd8f30fd7299a54f99c78823e371e401c37298bc222d6e83ccff31eee02ac965ee475dcfb67e298451946708
139	1	32	\\x93a6ad8a189fcf5918e4a4494177e69b22effb560d13b3b9251db045ab7de50ea0ad2965ca8017f3d120125a261fc8b39e81f1c9dbe0682f683724c795c2aa01
143	1	354	\\x078acfe973bcb578f8ac23f0df8fed619927134651763bcfd939ab20df22c46ad6d866da5f2988d51635571d3f3f9f0919809107f3d98a0002f4246eb56f9303
177	1	154	\\x36d4be03157af54a947ec2cd53f26ef2fa2dddbde77bb90f12b5bec88f6019cd93435aec81158476fe7b412fe0e5bbb216bcce28314476c7d79082687e222c0c
204	1	365	\\x8b70789874c771289463720de11bf8870535f3bcdb23884945bce47463be9b3f733645693006b44d7d81b1cfccf225278bd4fac0d9bd94ea50d002f3171ebb0d
236	1	359	\\x816c7dd3ddfb801b4012cdd92a6082f6dea092a028cae2f9c2a5b2b86f3816798c01f3ee13d2b993e841dbf281a677adbada2e22fdd9ac494d9fa78085d7670a
270	1	376	\\xb8fc92ded25bfb758cb9719ecbfe147205844030a5bd8647f095ef2587f43cbfad512415bfef812fc6c405e5d2d49771c824d86862d21548b78da2bb5d3ac20c
384	1	351	\\xad52b6a2de645c2df3333586620609c10bca1519dc4c3bc5f3ea8038128414c7dbccad8e7b18b932d21f276cd6dd5f0f415c740e56ce87590e7d628fa2b51b02
67	1	211	\\x1a1a54a5fdb81820b720283e9ebf330197e62779376fa23399fb3a1eb00094e0597508625e74f7d7b7d37c1585929bc03570ce9db689b53fae078aa25bf6af0b
72	1	86	\\x00d5d86209db25cfa6be02e4179942c047ec747b9154bdb8e8b37df26773568be55752fdb4fc6c9f5cc1a7521802888f327bd511859e51584e0b1499466d020b
79	1	221	\\x867614edeed077225046147be37ae0b7a1d36d9be9fe35f0f121519d87e62fe69cb01f745fa526ff91efd138dcc137974aaba64cc05a458e96b9a844bdbc2b02
82	1	386	\\xab46d31c70c913ffbcd625cd508c1b7a18799572304ff43e264966e3fd37b37f8792fbec2cbaf4ad86517e483c01a78f0c63a1a641fce0a2a8259a8946dc4107
91	1	128	\\x1824969b685887b62e71d6f65e7d7af2dae48b2881e115178e40f0990bac991ca5d3ae1cf9a25f14b9e9b95d12125eef56299d0d76623c8605d8b6ced1433d04
96	1	263	\\x5caac2697b10c43af59ff11ede2a3c606fa54541415581f5bb7deed04cba4a7e2073f308a33c606f991cf9ea5e3ef06776e98694acd32fa92cd2b160d83d8d06
101	1	148	\\x4063c975b1df2f6d00aa7176a26a992525e7bc58858c61d5e4bc8e57bfb90556dae9f15ae7e2d010aeb031213b33b699b84029c92ca90ed21563fc799787cf09
108	1	277	\\xc8d2edb256785a2e28699dbb23500158c3e291d491659e1093762d5e2bcef556ea264f5c9cd5d77d824292c72f589d683cc522949cfe3cf4213c89936f3be309
109	1	327	\\x9a214046f430e7bbd017243ba7fa5a64cda08f680694709e02b625054a48c2a4a4fd124cd302b9e688d315375b1f44b54ea360b2308a49ca9295dad47a0a3e04
117	1	417	\\xbd2ba55671305a8908d8d0cee5c304069238c1531a9eef414c8f7750c4a8e1218faf7fea7cd579b6555e2a798bf3db81c3ee7eb94528cbc818e9330340e0f400
121	1	23	\\x2b1814e6d37379a1c7cc15ebf3403b64e0277917b76ec60cb6c7700f7f1ef37ddbc41721e413547ad298895d821b7099a2f588a1e35a86e301a65f6504343708
127	1	35	\\xfeffb9abefc3dc54043fa1355ed16b93336a2a10fd29eb23a6a06c9bfd314c18b92eb756614d7aae776fe600807f7fb0ff659d7de63edd8f2c1515d0d129770e
134	1	372	\\x272ffd712175a4061d9cab35204870e18847701519432095fc9d90ea2ee03a25bdbed4fbb9b2813df8dddbeebbdf318b6f4e103744e5c9f7309a7a0391fc2107
142	1	79	\\x57c1e40dffa5bcced3e72f750316f9ca82df49ba1d1d4b01da72362bdaae2b706b1f01fc17ed584ead162d0a8e53451c5211728d2489eed4a28bc5c45bf17d0b
174	1	380	\\x52554934d9d26c41c4061e1422ec58c31e99886560aca47604fc728ab7b7a62c46f716e5c62ad1a75671b14a28130c0b51fed0a03946f4e02efaccb4394d8405
189	1	395	\\x7946885a8451fd7f802e1123829d33fa777948a31626f401c8a2b10e8cdf15a5ee04228e32c65072070faa9060ecf5e95540d53733d8983e1ceb5007fb7ae903
216	1	229	\\x0d4bd7892739ec8932b278b964473c3fd4bbe8b9ca395cc49220ac986ea53f9757c05c8d899a4d695dbfcbd00bd037a4ead8a496da6e33bddc605d8a50ae3e01
239	1	125	\\x9781623d3d6ed6911a24dea93ee00e5a4ca46b729782601eee09b805e8c93a190a418df6df7e9da11cd756b7503c63aaeb3d38980bdd3e8ed59c36a4a34e2a00
277	1	252	\\x303592d7f96ddeaa60fd8e5c1382bfc6ca22436de555913e9d49c508b35810c2bacb54fb750459b473d8a1b1eed931e0c448175218b9b7b2346927e3d850f200
358	1	133	\\x7b34f45e83911668e38a9c2c0e26fa4249731ed27ed092eca08aca6fb4ff2c4c635c7aff3c95f603971d7a6ca3c08c940aae7a51f53e0251034cd101800e4002
386	1	3	\\x020dcff79c9943a9738363584223b01e7548ff54d65e64d7707f7ed3dbdf89997079cdd7e2472f20d7645ba99b7b915383dedb15ba129e0f809eeb285f57cc09
399	1	212	\\xcfac66f97637112b2807b2b6df3ffd1c98827831d9781386497312a7a36dabaec1fd9c1a7d16f9e40b7dd6b4ce803111192f58b825c93c858209afd432949203
68	1	191	\\x0cd05ab0a87bc643bfc6c1d0e7d3d5e5e6614654e8367ddf7a4c767c85d43f067ea7387f413a4c81463d183b6125b7ee0b2d28678b2c6452244fe704d51ef503
74	1	27	\\x64963fe3d007d4d2f922ded5812bc823fb7837b042300cc0848f4275304ecffcf577d3642c7174f2116c2e282928845806b8699bd3dd254e6746880a9e593a0e
81	1	290	\\x849eaeb71522ddbba688810777af0c50ff9112a9a1e0be7c7f2e2ceadce5450b611a9e08a7b50028e9ff377892dc18732b33e3071c4fbdebaecb8e5b014ba40c
87	1	333	\\x71771880beb9b12527db68e48d237f0e8e9bf5bbaa792e546a49f66759e0471d418697daf191d2ee1083586e160ac94d99b6dbc42c8c6a0d3e29de75ce1d380a
94	1	97	\\x501b10ff32446a0c40ba31a02c2176470cacdb5a795d2cac3c470856512b0f1ad256334830f29ed9b5b775cd481a61d744b25567bce30064159165f202b94b0b
97	1	232	\\x1f6573ea170408e2f94c3fd8e04c9926821de7ac4e77f8d6d239ddb05ac73490e74e8b96dd9349385f7809cadf9ed5ac1c754d44baf4b4470002dae6e242b206
104	1	353	\\x996ad19e6057c5e10dfa529288e1fe2f675b4a1ec86ce65b308448b1585fabbf3c29e070676357f29c26f30660223db0747c0aace8d73301cb796b3bbe5fa704
114	1	151	\\xb53a1335a2b28205437f31758dd760d34af1e0b82e27b0d919da258627a308843c646d907989afe507baa139aa9441ca5284acad6aa5813fe1df0f7c93e42e0f
120	1	95	\\xe330cda41dddee98425f8734cd449159bb07bb9696db8667fe6b8a16d98b9d076054f5835c2ad6be6012f0e779569d2e2fac7b37860c9775de0f4fc23c42bd0e
126	1	284	\\xe65b460b29326a70ddd9818cd8c4df29544a61f28a75b80a920d2b00eef8b2b1fc59683ee9a7397b3d27be110f8fc31eefd8eea140255ba88910bc06a7b62608
133	1	248	\\x72837ccd704fc780f85a83820050dbd69ee2e1ae53a8afb9b2aceef9efe5a0c8636d0885999ce6809325b5aae225b38a9cfeb120666087224efcf8ab9eb73c0e
140	1	205	\\x172680826e5f03bdb44029185ddfd02593411ef4f4ccbf20ec21b5b7f7f58fec0960756c8ec3550ccb3a94431d392176fbd9ef8e0e86b9127a7aa5d44ca9c806
145	1	162	\\xad71c8de1e18ce8da4b5818688dcf34b0b15d21fff851acc7ec6066de7af7d4740d7d9424674e81415ef8a26b9f2f05ed35d869dca5297bff36f7839081f5b05
180	1	255	\\x598bfe120f5d1ada9abd2204fcc74bd6592e7d3dcd4b3c04e75b45128d7b4f934c605c31fc4b783e34ced8c56abda9f6b21f0b2c696f68a1281e7479a7b0ce07
210	1	157	\\xe741ad2835ad8471c507952f97529173849e5e6ed571fa7e6b971d5c5863771d746c976576b11cb48347dc38075bc1449fe08eedf856885440735731d1ca1b01
233	1	406	\\x741ab93d1ed620918a15a07e3db1d139192aee47110b1882f2e362ac65025e925a56e042c55572ef930531bbad44f83b5e6b1be038a7576c4a642aaf667cde07
374	1	76	\\xa760370b768b753e326615bd9916f67e521735264c4d4c0b54f89f087d4e5d320cd0baa5c796121ed23342ecb0f4ccc9dbf6b7202da72611831c8f8f1866c504
409	1	96	\\x03e8b042fc98730bed4d4fcba4cec1fa795bb9577320a5edcb2aee47cde41150d2e65660165a69513a8f46b9de17c68ebef51ae03914fa891f668593d56e2701
70	1	373	\\xa6fadf7dc6884cec1329fecc97d613c89aa7c870333dc3df2e374720387ab6f6891c16af5886c808c3c03ce39e58abf3704163f7cfe07d44ddac04b6727be50b
75	1	218	\\x5cca5a9f58c70be77b934b6bfe016a4822e0e443e14024005376940abc872c6d51b185b8bb689106d245bcbdc8dc2ba92076c50ccb7fdf85a17757bc1de5e10e
86	1	336	\\xe485acaed104706a5d57c219684dee8b35509da0b30e9219b1bca394f2b7a8e72d049f4bfc13c1adf59a2763b76d60032b1a15ee57e982ebfe185e6c938ff70f
92	1	139	\\xc0c6c08e105c4c2eee664913868ae67c5ea28bd6ba5889b54421342407bbcb792b80893b7b01c45a4ddf9efff4e040c8b5a459e492d53fd3e31119e628f3b808
100	1	197	\\x00c8b32660d20f66de503fc5e6099c19dcb8ec8ad906c4a61ac3af8eeea3b6387894561440a8028a992ab48b12a7145818e76089c3bbc97e84b568577eebc000
106	1	1	\\x8aa6807a61fcbd1a0493ded0a05653817cc6322023c57e2d6ae81d9ca1f534647fc8145288da24b3919142acc296be853f6e73aea19d56f687b8a15a1dd78301
110	1	266	\\x44e0c3c6a135ef8d875927eabd06393338374f927ae1a031b710a2745698c9596d38a6211ecaaf670220287630bff4e0072f8c6ffdd85df04d69e0dae1faa507
123	1	356	\\x745bbc83ecc524b8ec2e1536e2c84ea33dd5c96aa8c51e79298bc73a8ee93b03bee38a4270605c4a000546fa301013d4ee8646e52036278d8fa2d0caa2954804
129	1	189	\\xd75c0239e773e86e652692ffa6f75378bf31b05e89e3020e84cb80173b1b884c00549b0715e61e644f29c9cf956199f5b19e5f8ad5f448921c4f5171b13eff00
137	1	295	\\x91ebafb246e668cb0e8cb6db3b27a37246f82b40bdbf88a1a046b4c6554c779027f88970b662d83797d43ecef64ccfd094ec5c99b08ba324a072330d6a43960c
141	1	246	\\x66be671a4f087f168de046c05805c7fc14329a6411680a224dface8f4a46e5ef3a6f6573a0937be7a20141629c28e82f9c7671570ecd11d8c8dec61ebf006d0f
173	1	44	\\x1515d3f0e86004f59346bef4dd0d9915fe9d5a32a2d318e59a79c69485a3877e17796fb3dae9a448071eb6b7bc225800e0ac4d435d7199acd993fdcc47615908
205	1	17	\\x7e1e54108b499179aade6683e47a790979f7537d147aba9687b4bae0bfa7536c206387c6aa87baac6a8b65160e598e3e2122fbf3fff734ef8fcc5ce399594d0d
225	1	298	\\xa3e57349337d67fb0ad1cb9791f4aef71f35250a8572ffd3194c3c517fe06e4db9e97b9859fc08cd25efaebaed6b63271af891e1f685d4056b6bf07a06bae30e
249	1	259	\\xb12c704d9cfa7cdb3266bfa1c6802c0b7d883a6a10d941aecad0da45b82130f39d1ce32fbf8c21c399f6a9bff0f8e83693ac7c8bd5911ef742342f4afd33c101
300	1	228	\\xe4f9476eaacc8ff5d4eb8dfa0f4460f596a2703f5d50d700e04f6ad725025c5c06d5f2328a7b327df0909072529e05b00178cde2f8502332daddbf22ed8a7c06
324	1	329	\\x22f7f3b768849c3b5bc2caf08ae975f4b235659388048da490e3ac71d3eb3cfa4e7aca849ba68949b78e565175beb15eab30a99ef5af4104782da20f5b7ec108
360	1	262	\\x6f0bae55991296c402a9aa2231639d129880d4360c1a1510e45cb4caf186932ca357a74ad05eb37e3a4c676b6816de307293aaebd656bd8c7ffc578d55c11306
71	1	209	\\x51a9eb5716d180b380bfdc9ab4946235f062bc208399db9e58d13f4c97a2da4254c00028235122a0de3d80d12a623bfe501e714320c8acfbfc41745e2c35450c
78	1	361	\\xda725d6ec201eb6629a68435fd9c024f2c3e0b6e189d0c18f9aa6fb37d8c3a654c19b67a07d107a44f48e21dd45cdaaefac2c7445e38af244cbff4f4a8ea5005
83	1	70	\\xf908bef9d6ed4081464cad3f1d671b8c3a5d902d77cb4e244afdafd60f0cc2801474e14976e3170157db83b51d1a842f8596b06b6d177faff2d363f25809210f
89	1	57	\\x2af754ab4937239b309a5a5b474ac8b70aa85c6b06d199dc636e0e65d8055f8987252570516e3d739b362db862670cade7030687808f8308bda134fb6e9e8404
98	1	130	\\x9fdc04f0cbb387cc4cf32dd4af9665c8c8f8717d885c5631ec9b1be2eabac37623dba8e3a5a45abaa33ab1c54982d99fc0e7fd589c5ec85f120b3d643143d50a
105	1	249	\\xce1b97e0d2f95b92afd2b4fe5d9f9158bce5c52a91b1ac89835e4aaafcceddeec8c03863eafb02dd97439ae0efb8d200c11ed3d0ecacd2c9d0972b050ddfd10d
111	1	339	\\x4deae218aa53e49fab05c50506002c99cac2ac312b7f85107dc0008eef0020cc7260c45e2736b271ba8252f3f6d8c4a5cd0cac1d4dd0405b0cfc6e393562bc0a
116	1	75	\\x9ebb5a238ea210c13fa0211a316e9958567b571c6f15032c905e701f1f0eeb057fdfe98e7253f7047f383a674ac1a47cdb1853f4caf7db477b61a43dca859d00
124	1	117	\\xf6c285c8dc739da89f8bf83ed33f19ffb2ab9a1abca050feb495ffae598ede151fd3ca94f9945cfbb9971ec9951118812a08dd5b7a758ccf98d55861a16c3f08
128	1	36	\\xe6d2cf32f0351f946e0faa5c3c01cd082df285e37b93913e57b534c8e905e4ffb8e8d29406b197e156cd02008b21cd1ec3ff8d98a78220f75f688cd97915e405
136	1	190	\\x7238e4730c2514f1a8bf46b09ca7fb195d0a7ff21da4e058ed0302adb561d3b69bc7d29fbc27a75fb3815e2bb175105490de17814c65389548b5751951ca230e
147	1	367	\\x3976a915bdb36c41218659c588abc4d03f6790310c656ff43a9c9ead0677dea81d7564173adc9cb5fccca32ee801d0bf9422abb5db25d5a72569a85588f91706
167	1	114	\\x6eb48b0b25d9eb73d83a88c102045b3af6d2c50e982c5c2784d78908c14fc17ccb401796d09d170e05cabe4ac410c1bb5146b26b2a97ea2e7cd609610950d30b
175	1	192	\\x4551a2b514bf51594dde9a3b4f109f5f06e4aee5ebb3b932b248f10159b6efcd86c269e5b25424274fa9b2b4dacbafdeb28c411ab9976272afad58595703350a
179	1	101	\\xd535a1ffaecbe7c74b5245aadc0c017460bac4639aa39d8e84c7be93c2abe4d3bc9fd84416bfd98734cd8b4fe1a59096ae4f5d4d3ab0bc4d67dedaf86daa5e02
199	1	65	\\x06d7c046c38a99e68804d2f357334c6f300054c9059c617000723090f5ee499037b1f2e5e43c37462a4e67fba47fdb9a78985460d94142c0eadb666b536d150a
206	1	181	\\x9b718259e023b3275ccb66bf410d5ef18b85c2febe50d0e1d5ca3c54df3dcedf53287996707d766c5c70660c05b384cc6066cd99d617609084ec29ca027d6903
218	1	39	\\xc7f767d1b62cdb6da8e89406b702383597797c2c44796ad415dfb23e7d7eeeb9a4d3d9ced18d7fa98a1ffd4ebbba38a7b1129a22ca9c22a376e5506c49d1f90f
240	1	244	\\xc37f9ef0485f6998ef3c2eab179b92ef5a1ff5f83db3dbd3b5cbc31ff2a733f794ea4f8cc5e0d3fb65dbc2c4b50ab8603579dd18f129d2565ff1a06adfe7760e
246	1	308	\\xead333e0180e144da1e18d0487631d7c9194875eb2264ed267f0edc3cb8744f6f682c9a7065a80d40f21e56ebba3531fa61694b0d46ff9f42c2daf9fb92d8703
274	1	194	\\xdee3456214a2e448aa71f7014fd9ca2decce3af1423e435d7ffa77840bef9cff68d3666f2d8bbf3c5e67e13514745a9fe8fcc1c0ded57e3579afddc4a8be1e00
291	1	180	\\xfcac8ef59e74eb60d44f54204709c66251c2dd94cc780f41df24522a566aaf957c0de35cf5484268d77dafe937d6216f59b99d5de1c2813e7805e00d9b09ca0d
311	1	407	\\x99b8cd552bed34f115ea0e664609535b7d83c38ab34eac10db0eac84d95fc75eefc8bbdf563acf87e26b7528c16b0a5fad68a6680e320d3c6caa3e5ff882aa0b
317	1	201	\\x70e51097c96f2ea7c932d35322927b3f5762c9fab78ccda908b742093a57fe9ca6d0f61e5d62852a628f4e1351d007225a5481ecadcc9009886ddb07487bdd0e
341	1	216	\\x46e71df3174ff17fdc30c0c784bfe3543cfbb1b1fb1c2e8f8b3ff5f4643da5e1eea7fea3cb5403b7f0b596c04c26965176525325c036aa87da4c5ce354f39b05
343	1	26	\\x5b11a8d189ecc0ec8c204cbf7d090d55391c284094316287ae3a484f524cc77d3a3ac59215c49778f640358637e13cf5767cae38751c811ff6b9ee4d064de400
359	1	196	\\x2c6b353742c6e8e44599b4f7c6ab51670f42bce596eb7ee6f78d2fac72b5dcb1ff50e50f96965c2474b8a56c09ce3687295128cb25af3ee5d41bdb30e158a503
387	1	225	\\x1238bc75eb9d8814087497a80468df9e52bf129f7e5c6de751979cbbb6efebf2f9e2f3c90e4626ed9f847a5227c48f479d6145b7aea3d7afad63787924a2b20e
404	1	326	\\xb7800d62c2ef1b5adc8313c30fb21ef87ae0addb63679cab8487eca0ef9dc9b693effae0b87fee0ba820ecd12798da91106aff4042358ead4e51d3fb4a6e8a05
421	1	134	\\x29f562ed7c32570f673bf020aca27af04223911e890aee85f5f09d75b50d3e8b0a352d695c6865b624780517a0c9dd4511e908e1faa0d936b6599d43a4f28e05
77	1	11	\\x93029c0e225cc7ad5dbc253cb2e6d55b239502a453be2cd3172c2c1ef1779beaa135bfab33241e8cbc8b21d08e4aa705b471c7688285ee5b912168d48b583f08
85	1	346	\\x51b4936fc36cd65085984362ec3af73a93768d5c271c98d2e471921b168f25d4142e25f218ca6743f765b2ebd5c02cf53d12c1bc6da9141d5e3e6d7cba8a6e09
90	1	260	\\xcb31a707ab01fca10c59b7d1d91c456453ee8568a5df2148da0be20cc7cd606eb28a4d9b3df8ac0a14f8c5424e0a69633085593a4a58ba6dd860a22136aea404
99	1	51	\\xf271abaa2890f5300171701c84708491797807d48641192bcac55e0a7b6662c06d0745901cdd2880ef42521de6b9d7fa7a3938b3e0eb38e958f43b8729715701
107	1	107	\\x68d66d9079fd257ef7eeb8c8554b77d31d878785a4fbb8b09350092d5b07eca55b3406a9de7b443800f8fba2f0f64739fad52ee08875f9dc901149a178af9601
115	1	52	\\x8635520dd3c88fca8a7ac501d0e202fa2cf7dceec5668f75709b7e3a44ab336b6ac9961a69f56223b078c0861fa820d1a21033e43ab98de153da9e51c32b3c06
122	1	41	\\x0e3c5984fc324ecb970e6051bdf5ed7fa51da812fbf6775c5eb46879ccbbad86c3eb74abae6eec643e156c58c6f546724da7798e4756e413adfeb3d6e1e47a04
130	1	81	\\x3e51cfc6fbece2f9ce4b9484c001110dd4e300ba95c421d874d76dee2dce8233640832cb663e42c74872a63d48c75b1a8827e0553f4e9d615bc4515ab31b4406
135	1	142	\\xbfd3f82f8997e08f716e6c9bd167822c97fb7fd7f90d0cb542f627c8735107bd8848b363fd20d156606724a40512ed7f03acd8e4f5fb60162a78a9e6dc88d20a
146	1	240	\\x2244152ca71a4714502762af58e1c8330440b3baab3b2126cbeee5f9382f17e947712b18ab578d6a84f4fb39c5aa3744ac89fd4d1d255b7fa979ac0e92bb3407
168	1	393	\\xe99342c27a3449b256b8e82702dc5420522e75d8e54e0b98dc6df03aa09556946287cfdd82f48cc6715e5e80d9b14996dc0877e3b0268ab10fd321412f03d801
178	1	330	\\xf2ff580c75dea8fc4bce3a54c1ff5ba69b4043c815eb464cd442a836ec324869189928233d582fc0b6d72f8b8538b50b55b7c5f2a7197806b8d59f015d031f02
188	1	43	\\x77ac40849a304873e6d21d1fdd9c7170e09915521405c6b27bb929fb353c7474b19f0ed33b26e2db72f3b6def3322f3db31cae4a17e05aa49fa0c09a061bf501
211	1	87	\\xfa03d71b41d9b0774edede95c2a713cc4892598feb10d3a99390951e9a6dd865d4d2d1e9b0558e1e7fbf2f7eb307b07e57e42bdff2a61019b8d5b0dffb1aba0e
219	1	323	\\xfac066fb1db3235100ac444dc56e506b9a92bcd47efddf6436b7cc45f49f7d129358488fe030986e11f6b33df200ef2ceab3e2b555f5fbbec33fbf60ea28d409
228	1	256	\\xd8329da06ffb72336d0d0bb9199cbc5e48138dd732c9a551bd9c4ca1f66f0983d8db90c7180a101caabbe78e4113954ad7abb3866c2f40dd2f83a8d5779c7707
242	1	159	\\x0ee7961e48ad0e4abdff34c2771bc3a347ffb4158cbad60751a0155ba88a4e6e2090144a6307045729e816fc0bca8fa1c88713c25cb6080dd56d8a2ef975c201
265	1	350	\\xa2d2b58de76503089ebf8d7d487a1c0640d4f4a54a39eb1b3870e2fc0bd1521fdbac809b03b0c7c24b64edf8b46bc513abe52cfc97db7ed33d18febc49227108
289	1	394	\\x02dc8385a7ddf025cff84cb09c40aae4d5d71c99904904f00c7460cc945a40cc3adbabd0bbc3de61cf8d1e0df871bea2bcac5a79d7645e78ea2581456072880d
316	1	403	\\x0e491bfff463e43c584044e17b64c7d2653d06e946a2935c0abf3b0070c9b0553f6091a82369409c7c0773fb51a3ab989e907a0742bbd9ac21a3dfdb899e740b
330	1	28	\\x68c2021560517ab7b1ea94f6df5281a6bd5aaa22c11384ad18449cc06c2b96038ead524a10b39dc8e8eeb7d2dc56ab0c4ef85a7fc6475a3ff4a56c1b08fd3405
349	1	120	\\x54b1cf4d104059e8ad3006b6c25da3ce4eac8cd84e984ee1ddc6fecd922a153e7154b69bb55ca5abd5d1db437becd3b2ccb973b5adf0bf0b45c6c16975ee8602
352	1	50	\\xcbf3f12682ce5fab4021bd9cf314f6f746977b6ec6c8dcdda90ead2f487923bf3b3e1c05e1655f69cb228787cea8dc08ec5ada078f7d393e1e26ba58607a3d01
402	1	309	\\x8aeef63e83824a78e047b5dce877c909afe80aa12d2965171680c6529346bb6fbf09308994d4ea3889e28e1c7c8c6cac4b1524037cd741da4b58c1e9088c5f0a
417	1	375	\\x6bc72e937a31291b71fde8b740fbb6d4cd99dc074fb9afc193d6441496066e7fc1f060d9fd7fdfdea13c0510b33908ce837192bcb46a19393807e954391baa02
148	1	343	\\x443e758a38de5e52f2e5d6d6434da27cb2a62e74950c819d06f4c52557f5c680ffee51c6a5a61c46e8c5ce888edf8d153d2d6007d6d59ca6dd52b8d65cc5fd04
169	1	265	\\xf2201c8e1aafe85ef2365e3f347d146e4ffa227f94e7908f592541207cddcbadf92e3b8a8050d64aa5d9d0e4be383c64b4ad22598a925178cc305da1abd9050e
181	1	324	\\xc25acc5825070cbd0707de44d7e5058427bc4d755dc932144454305b534a2f52d0b94d2a60e056040714ae6662faec736b08fa38ceba9e190870b5c2f93fd708
191	1	170	\\xaf5d0766a19613a6608e8f584c151e64113f21923152853c2362ee40f93be393cce152718390e83d8a1b2d313c4359528ed7a1631730d23f36b4d105936f750f
213	1	116	\\x4dae8ae417d91f36bb6dc887606935e4c1c7954d29a7001a8f3b1c1e2f6d70292317b29a161fc93f8fe23c221dc7b706897d66ed565b5e2e42ae883076b49d0f
229	1	334	\\x4adde450646bb48ec9961331bcac00e8bf6606fe8a8770b82c4341385f53ac71867706bf14b5309a86ab207c888cb906de04645831a866991b1f55b966f07606
241	1	121	\\xbadb8b0e29e156a986e72a12e68b4b3c2d50314f0ed6d154af31dbb65df2c3ac602f4f865985a5d9ab7f157bf44201b0aeccb117831a1052ad251e98c6d6d10e
260	1	288	\\x03c3b05768d27569dacd819b32ced4efe181c6ffd66d9744ea6732b1122ebd50d85db0a29716a751c5725b5558341e4244a0f9e0208ccc3a75edef62df63f405
275	1	219	\\xdf76adc6e580dcaf6cf6e6b34576c190a7ae05be4cde70e58856d4af777dd283012b8c910a8aecb5278d7cdc7348a0a7d184a61ea0acb19d823c7d4192d35409
292	1	140	\\x5edb6b95ed7c60208df6ef0f46426437f8e6e168e5bc7950a4c00a4d3c50813e672bef828da8036ac52c77a5ff64c92165877d1f26c4d2853a98429edc5df70f
295	1	379	\\xdad03249f60d5b093a0f82be4a7fa6b3a7d5dd941b868f6be9161e4aabd306dd5a4bd9154a81d25819393c824999327cccafc39479f823a611ea4e55bc2ba501
312	1	318	\\xed309f4100c6815ab4b43ea4526b18053aba7b5c4cf18d378b13b820e3ccc4e7254a03967ad13234ea447ad2dcbcbfad859fb6303c6ee6a03d5b74b7de868106
332	1	303	\\x3d559552e2ec73c3f42de6d2ce0e0ab9992c21757c3631be15790dd169cb1473e49050661e1a0321167dc48fb07f964bef87451141bebc6491f1ae8daf4dc90b
389	1	275	\\x45aa70e5960e13fd64d524a1a4b0f4ed18b9663254d61dba9cf40606d55f1da018db6a42a7c40f519fc68728290da0c1f6dad0f30e2c68ffd18e7857215efc06
403	1	357	\\x5d0668fd4e81e58c619fb7eadadcebd770fe3eb317a5d1716a0d2fa08f9dc55ff790c346bee767892f5c665cdf6110f1cf2b37ce098a7c9401e9925ee7c37805
419	1	337	\\x930fda6f00c03b9ee1db34c650ec86550b51a330f2337f0346fefcf01806524244adba383424a284e6ff98c2498c8e587aeb5a29c0dbb9d8ca3a0053895b2b04
420	1	261	\\x12a94e04d2009c0ee2369ff00aa6292ab5a3f81a7c73992bf905c60bd926887232d4178c5090cd8adc756d624dccad826cc44a383ff949f20a1ded05da04710c
149	1	223	\\x3bfc4f1c6de2b5e3ee26dfb4c6a9fde4afc53cf2c031afcb86f3109c2e373674608c3c10b6c60f24bb76325fcb4f25f3e9c0670c1c223554eec235476068c403
170	1	340	\\x520d52c464aa932ff3b1757efac5ce349cec90ab20b6de1bb8d5b19ef88d83c9b5bf3d325c4094b4541b3cb8705709f471b7cde93df63b0ea41548f2d1da400d
192	1	272	\\xe4fe57fb7de2bd790d24aadebb618239f14c20cf4cd2a6de534710f80c0fb3d8b2f900e75df8f8aa3615b0377487f50b907ad5c1ec2582c2f10af2f945df5903
194	1	268	\\x7e14a17ab059a4cf7b78d842ea22f7332da10dd1f130b2b12c126ef51d94d5ec1ec7d579c26de68e9cea6e7534b65c33583200d17bb4d14489a3ef460a7f2d06
227	1	186	\\x1d1403272c88756afbf9c783ac34026f1af76e536a191f5e1dea82ce2e3cd189a23d5c23d041ce770278a38450ee64771807f9fddb5706fb61bdd5c3ed082402
254	1	381	\\x7936ab05fe59bb3929637244f215a0212969de7c4e64fdcf581f38630e79d3e11f85007716d83d4d7db1e629a23b2d857823cb6df09dc47b82afb8ca4bbec705
258	1	173	\\x213e265b681d1137304c359cd709e811653dc5036635f444daae1d9a045e72bd990eab3a7f696d440652e2c5c2ca8a7c2f04502ba3fee719644ee48c04c9fa02
272	1	71	\\xc79166f91c548d0960eeb132f8d49aa8b5e82d46ea64b4ef7f8282b36098f77e3201bb0a31119efb7afb653526a1b62c6cbcfc8bd012479bf4d78aa472a8b103
278	1	123	\\x9722560934aefbf057553f56805cbdcc8f8b27aae4becbfff3a1a5d31068307965da0ae6a7fc9b36b6de835a7b43407d375aafd327880d2d75f8654c89e77003
290	1	91	\\x8ade898cd2da1c13823974473bcde25eb47990b5e0f2288d48364ffb6152a5b000c6798c0f8c04704b3cfa09897896d379ea37a362c93ab454261b3791aed408
298	1	411	\\x3197df16896d61aa3a3d38761b7a6a1a585250a46e23f66e2d68523d52560e8f7c10fba7707b013a31637b869d62f2b91b6c692cad43c7c2043af088a8f4610b
322	1	152	\\x27818ae93d799ff0265158522536e7881f955fff4f353b9402a129cebb11d6487f21fe9b0f1abbeec7e4222bec565d8ea9fa7582d7dc3eb38d1850cacf3fb90e
337	1	172	\\x818d6adf1a066d8b7edf0541ea36f34b6726661ca85b650e2879d5ecde7eb13c2a8dedf008452b406825d9a463fc96bc15b24e5922badd50c15a8d1bfd25a401
354	1	129	\\xa3c59123ff76912cc54f82031e8a9bb24c70dc7831163a983e8b20eafbef89a922b6d0f8d5449477112eed2c9941eaa28cfe37e3f1bd9747ff072c36c725be0a
365	1	397	\\x532606cfd9ab997bb6097f9c61cd9b2167fe12b84efbfc04a2a7af0a287baf0c878b94132f8e3ab642ea20bae010e6e6c49e950f81ef7ae8a4d16f6ba33cee04
379	1	5	\\x19af80301fbea81e75b266cff95d3af37a2f0d10cb8a464e0c357c12208353bc1982b188e924649b3c4e8da1ea0fb909ad05e16548ec2c1e617f3170d0822209
392	1	311	\\xe2c3d45f6032415ea25fe17a8173eedf0b76c39c02fe974ea34aaa904247c7fbd1d5b8de0fb8cfc5f0236153aa6d3565cb5c908fa3188a8a297334e43596bb0e
400	1	62	\\x810ffef6ae6f87ff3e1f16ba376070a5bbc6fe63543f9a949b0d2fcb7f1ed9304d8c8b8160d5b71cdeb1f5a55d5ea4f93bd755c1bc05529a67b90e035dd97205
412	1	369	\\xd726e3bdc7e2b61078208884cbf8ec1fb5bf951e01e8f2d1a723986ca20eeca7d4f998033384ca568bc6c086c6db3b9db1133b3190fede1b513d837c8eb55b02
414	1	149	\\xbee91002650133016ef9fef2e4106388f7f364823bd77a839151e7633cc13f58239c4addf51cd9292fec96f0df100363d9de76517bfde10bade10f944d9b8a04
151	1	135	\\xd3f126d1f7888853c53f0f1672735c2efe55039ddd4e86660ab1f3fc9d6df3b6431aac2ea72f5236cdc9e0683ad1ae5a5f147eeac0c6e1f6629773de88350a0a
171	1	238	\\x3488e4200760c8d52d80aee8c662145523ab04d2003bfdac7528f8ce877ec58579136a74b49eca00de6745ad5e8474e0c359a3d519cb2ac42bb6c0edddff5602
190	1	267	\\x8d34616a8c69d6f8211a1fc8d7ff0240a136f77ec17858dab057aa78e51b575a6e356e5c84e0e75724f7416fb75897479d201306c13f7845d1d4100b4d2aa30f
200	1	220	\\x68abe1b90d829544d6826cc84a1aeb0771da9841231c33037677e9784c4869a3570bd96406d7ebca7625eaacaa3e68312daec22ed5e164aa70f23994f8367d01
217	1	224	\\xdcb612f64bd930d27e0009068e9be8f5e3d5576c3f2baf669053b9f958c491f0cb55b225cd5e8c54b25004e14774ff64005906415e79e017c46e2c24cf49700c
224	1	143	\\x0533589ed319ebf8f8446ef92c5a1fd1f859ef0194059a8cb1c6f213dc98e929a041c000d8ed28a42b7305a73c5a4210292cff134efe28ec53949fc1df155502
244	1	257	\\x3cc8934716d5f0e24c0124e83429254c1b085d8d20be8414add719eb9a1d92deff973bf4ce5ae3b67ffd846470f21d5f74444cbf56c0fa140742862a8ef0d50b
252	1	136	\\x812c481df0680e78a1333c3f3db32fe9da4a8bcb82c9bc38ef5eeb43670facb99f357606a52db2711d368a5f01b492aa0de382ad31459075ee82c2f35f45d801
271	1	392	\\x8698059956fd7da10108abb977c392a8da407c516ac177099d4656d69e63708f1701333e93ca8ebb3950ae7fa995a4839b091ae977eddc487e42ebafa2d43409
281	1	111	\\x4c464bf36e6c737895d625c93d4c91dd242f48eb550faedfe4669e7e09de433c63f8683cad123527863b52c663cf15cf154d57acef357a42bef492fc6f2a4606
302	1	362	\\xc94bee8896e125e2965deeb55237435aaefd415a1177fe72f1404e72d586de8bc806705f2037859a4d6b0ba35e29609c2a746340414f494be3ec2330a0796505
319	1	40	\\x8c9e3a6617390dee07cc425a0d52bcdd18ad105c8f14aeaf305996cf9ee9af6523eb17eca7afda167c3732f43ea13852b095a08efa88216ddc2a38230eb1000c
326	1	254	\\x32f5788ea1a7db9bd43c272968c0b99824d69b5ff87569bf5dceda778cd8748a18bff23b968b2ed29f017bf79341dc02aa05c0d25504cb1b4e98aff681554f02
334	1	12	\\xa31b36fbbdd0e5c717b35d14bc9cac5c71c76b40704d2244bc064affe98c15e7d4f8624a82666afc7c278dd811015773830249270c34ffbb8b329e8edd0d6f03
355	1	183	\\xba7228651d35e585a4d23cc735b289a7ae2b344d54cc0aa5f4b874b74aa9f3e3de16cab2a491efcff0f11b19340c04302407bb916fc5097d9df3942072061802
357	1	315	\\x2dce682f7f42bbbb199918d6f93a841da17c1d9cfe78ff893221fdbabf473d6b8f67d0bcd188be50ebca108cbbbfb9fc5549a598898a0b771ec5b71366abef09
376	1	80	\\x8da9128705280189182f932fda1cdfa6e42a96ef2e902e09b4397503e0f237ce293b99d5385415d708936b3e51e495a2553bc1b321de658b377dcbe199c4e00d
390	1	115	\\xdf66b85de4a8620112c8fa8babb597e294c225346c6d862b0e911b7cfdc1c99aab39ca8f37897937118f4e2f4b8676c4930174604120de0a911dd0c70f1cad06
397	1	230	\\xcf8c3d8d0d0c80faf8c0ac980e86e5af85d11bce65ade6d403d8f2e1df1a1846d0f0249191591bbbeb381ad92c55dc4db4a33268c4086daf2c6d86b57ecc500d
416	1	226	\\x8b5ac95c276c85abebbf3e8f1de72bbc658abcf47c946df67f14d56843bbf37961d27c400e6136b7f293c0de8af4f1781e18765bf7ba2ec9ada41bba78fe3500
150	1	250	\\x2643286240bc512f3c5a1a757aa38a8236204a7f1ae46058b43f9c6407d07dd233f4e8edbdbbe76945a176072a5d64ac5bf9f396e8a5dd2c49fabc0697742908
172	1	335	\\x34bd16811458a5533d139d26c7a7a378f1b5d2ac7e2521d6f57d967e9ad613115ef19420a882ff5ee57f693a3ee9f4db7b1f0f02b85f305b9f5a0f04d9579903
193	1	188	\\x6635e6c7eae8bf02a3811fb91006a4d859e37750e4228331aaa1063944c27491acf189dfaf0f1e26c3ee48381aa9af0c09adefbaeade06cad0754332122d1a0b
203	1	264	\\xe3dcf8bcea7e7692c628eb2dbedf40602bd93bac4d40795550014598b3e2cea1e9a4788e9f7bb1386d847d263b9f3deb6b1dc1fd4a3ca46c14d63039192ff008
235	1	398	\\x95e5c02bf56ed907daeec94945011e294b6a2be41fb72296bc6838e9c07d3221a8ee838e46d7672dad183618bd6f0e279a3bc9e422f19dbce2a765ab61c18101
238	1	345	\\x47d50791d8f7ef41ab13107800e774b25ae5a5ce8d4fb77eb7ddc0009dd171c102e666cc187ccf7fe807e8bb953c29b074fed388ffef58d0aebe028236ce570d
267	1	414	\\x109d1325b58b978ad6f74f80babdb36daa8d7c865b752c26d2a5d16d39925f28a1eeb2c81f02e6e20258a6cb9690e45bd50078becb0de4a6a15bf521674a2d0c
268	1	9	\\x04938f0f930b392235e3faf49eca34b43fb94f37346fbc8ba105c824f69f50de923e79e843aeabb5ef856c4d29e1d65db0d4a0e2d140c0911fc9e40b8330d000
282	1	165	\\x01c65cf3687faf8d2c4855b4fac7d126b6fe16eceefd122c0b7c9420e1bd292de6b4ba012e5f8c9b10bff4555e19c9a01491392a79f85b08b42fff0610f60701
286	1	316	\\xefc9a44b470f9eec81305b64c448d4e0dcec48d5d65a5a430be6a53c71fc0a28efef854b5be343954e73d62962fd7485d8569cb00fda3692d047d25122a42d0d
307	1	93	\\x76cefea99a28e614dd5c4b420fc2f491a1617c719c26fb37b5bb8a2dcb9c36284e4b54fd82b3a09700d57a6a2a1e781ee62694b26753cd773aad6a5540d70b0d
325	1	378	\\xbf9a41393125d237a764ed38d5e0492ffed1eaefc3f1fef7a954d26a271f38f47efe3c4dffc301cbd0b87432c367b6a7706ba3401a1fcd0b15b63dff066ea008
338	1	118	\\x6e9ca5942fb431d059091b3c345dc0124230eabada70667ff2405f2c5f9e9ecd84023fb3030aa55f4a05905dc030702a02e7ccea378d9461d99dd0bbbe186a0b
356	1	105	\\xfda8c4169ce84e350249ced8dcf09bd251296519c917f1bb54e9e45e23df600d107e93c55fe2c70f80b79eee7e387baca1764740c3398436561b1ca960d5880f
363	1	19	\\x9402e5c41a0f1d90d191856bd93f3b9d4d1152a7869c548267f6fe0719eead4569981f3ed3a7b006009b7b3b1c166db7524f4c964edaaeda5b7b0b16bdfcd60b
375	1	199	\\x108f9690df60751a7214ff3b4eb1ce78cf00e73c00ff840f331b10d4c65b77f72e968ee2c7a3d409655b137a55b8ca599c2bd24bbf87883193eada84b7246909
381	1	317	\\x8dff8bdb2a786980bbd95350f29edecaf7e01556243bde102477d0ae596f3c1d2bbeab2736a4d13116281d4d3bc5d2ab1454640edb33c00d9f87adfdd7f4d904
396	1	366	\\x2e867fa16baa9a882cabb554e3400f200a51b255a7a19f958def9912936f08f60d0198daf02b0ebef35cdeb333248087cb345e3a655e9c325bceb522bf84ab00
407	1	242	\\x317c88eab4dc34a040518d0b321177c9a330cd290bef134be6fd9c23228783049d67cb8958eb1139a279bed9d014b15beddc534f395a91d3053d6c3bb39e6309
423	1	245	\\xc5334193faae62f2b07e89bad416a09d5bb77a4bde3c8296132078981400c6911a6285ad4218042251135ff917a3f389190d883ff74ef2b0ca2e21c5ece70401
152	1	124	\\x4c7ac4f47a5b086c513daf8dbbb3fa6cc8dacfa6eec0423ac7b115a7001fb78ffc6203e3c6d7eb93129e0169ac2ee5dc4c1fb7a192ac075c5b5da57b0596d80a
209	1	208	\\x16bfe99e315106642b7a83e984c92154f946ac3f46ebea576bf9593873286fe6d1eb007eb85493e2d3e44b282d69b7cdc76956870729e2b322049a5b674c7c00
232	1	83	\\x5997f8e2f7476a177abb1ce2c9e1554a7e1e9ba83171543e8062a9f1df82cc3ad2665043b689952338a857f8e5fd0f01d7feb2982e6b03a8383e221fbcc54407
273	1	56	\\x0778546fcc1fb36efede51e57a446d0df12e48bf93584bc3e5d96a2b7d3185161f488febd0e05cb122a04198725e077766e1368ec74b5d4101b4ddca9b060f03
299	1	312	\\x6e08cf29a450326342aacd6872e0e94462b133ee1844bac89a4440ad0bf8b0c0a9ea311d12c4ff78f369352c619f309eebf2a56a654ea3fbb181f0eb106b4f09
320	1	193	\\x925056b2bc548d8ea1ba6bd8cef429ee049d2e4c53c2d1044a03b725011bbd3573bae10425ea9002f00de2777065368a06008fecd7e13abd34f6ac7c424c1a02
340	1	276	\\x27ebd43de675f52941e735e3858cc5165afa115ff0a8b4824c42107a034ebeb90e89ff8d03cf8f37441ffb1dc83dc6344e4d90ac1d9761176c9c18978db12303
362	1	421	\\x9727c535bda045ac83171978dd2eb98ac8661fc87de3fa610d8393263654985047b2e01411316791075f037deaa1a96f10cd8ed3b954dc7963946d1d7534c10e
154	1	370	\\xc67aff5cfbbcb7dff955e5d0f53208e2819f70bb5f40c01d7ab29434f7174b407d4b6988af7581b6d2e60fb131a4290c7b298d352ee680228b756bd3f6c4ce09
183	1	38	\\x24749e7b5ae4fd88c31121bb49f7d309612f9b881635ec78278c25eea7e8f28327a3435f4ea2c2c807dc6d3482425d4d8e10824a9970e9803ad8e81b4276a403
221	1	103	\\x642cf0e1e30f76b7c93f591a4361058dc36dfda617266ad69de0d11af80128b061b42bfdd098f0975d835a33fad6cb8f95832c190f5fe580ce0c3f2093f4580f
262	1	371	\\x98ae651c7bf6445021581184289b24e52c64b079db9b5a36344a12e0536892e376e05d644c05eac66ff8ae5eef7c70bb24526c57800371b63501a0307d5c990e
283	1	73	\\xec77401c0ca54ab6fe6f1e1265a91e633d6567c47f57b25d26adc5d6003a74032c6aea6881e1dfca3f87be4384ee0ec8c636f10fc2c1358586cc25aab9a75908
310	1	90	\\xadb5d6b54651d4e655bf378e8c9cef2b71bfb4b161cf33132a82ec35351e733bc3917599b4ff425a922ff0a0c599c188988b9f8f46366abf0cdc31fdf40a640b
348	1	423	\\x42371cb241c7f1fee607a73dbd4947efe03c3a54465a982ac9daa6beab99dff335e85a7b148f96e6bc6c5246346526c0c41621a271400ae660248f2577a34b01
370	1	215	\\x887854bc11821b806a4e07f73eb1cd3cce72bdf2a6a0f1942d4a6a605eefdd61ffdb41ecf6b36fe082952013c4083f24c82b959fa0493c47410e7642fb47f600
382	1	58	\\xafe42965a87c490423abc65085a374753bccfc6ad9fb80a8b593ac7b5837cf3093bd2773783b5150d7f1aedf7459b85ad2c7aa9f5c24ee2ab5a5f82b8fd65406
398	1	332	\\xaf175fff7ec900cd00f8ef19f363005c5b0e360e7642c46212025a3bd4370814af2f1f947819c312ca98f596918ba563e216d3fa5e1e924079163a72751b930b
153	1	301	\\xb6a927f16a7820108b8e3e726f37912038435bd421f6276cb69436b77136483a9ab81c198478a10ceda3ebdd92709dac4b672cd8fe99c68afae323893e88770f
184	1	271	\\x44a464802cd0a71765181ceac084e8298a1a50fbdd93cf69906597bb35b7b65ac8cd0ab6e27b622534a59deafebb00d2ed57b380999d17ff43c2a40ffeab0303
223	1	287	\\xf074294b9e2876b1b0f23b805f5599b065c248a4c2ad54055eb49a01cbad223fe3bc9d14dc41bd56085f788ba3d0ed78b28b5482d5cf7102d785521e9c574c08
243	1	160	\\x4ce0cbf4add1e9d61603c280a1009849697f38f25e3151d58b449f0435b0391a896d45bd4e02fbca91d675391e28721f4fc5895265e4b11ad647e5ca78c79c05
284	1	198	\\x6ddb1bce2450ec85091a251ae2bbe18bb73d12c660b8d804c104a0fd6776f2d15186879fb1cf05ecac03927baa95f3a306cc4c08deb8ce7caa8bc2101bb3a207
308	1	349	\\xa60e2eae02ba0b47629cba2464a5fccbda21c3ff1e7d0ad3e2844cf709fae25849eec953b0619a4f93e82c7d7f367ec44bc6ff0ae76faff678d86ad70b4aff0b
331	1	227	\\x2795a23ce20c302abb27db0625e7098bf85b42abaf4f5a2dd3ddcbe26efc04fe589a3e69ccebe8cad90b715432e55f3993404a974208c459c38c67e0e821f80c
383	1	418	\\x440a30a2321f3cbca68163d8410fcd938fc3b82b20f632cbc80acb691e2e8a91cf8d19d2762ce3ba3b076ac725ab389b85460679329ec20a7b7e5a458337c20f
405	1	145	\\x85c032e9a679e460bdc3f4894fd59df337ee313ea586b11861e31bd502df2bc87dc83e228969aace77f9d754a318139d184f7d271b5c4887f6ac053a2522780a
155	1	144	\\x98d246f8e5547bb1f73dd8069aee0cd6a5d3b2d9a454686e516d4044344f5c1e2b01d67c5651170662a656672c58f04082e9d0fbadb62cc57ae95fdeef872d00
202	1	195	\\xb433dd9166698370e025bdc450f1c40c439f383636be4c57c957755da93eca828042a7e631da37f100d12138d239dabb13bca8b68ac89d6ae0d6b0b124c6e904
231	1	413	\\xc444fd51579d153a8321435f06362ae3e447a28646d7238b15b6fa62a5a46fcbb8bde4914cd7719c436c4a9db66e613208fa818f7c64c2e75a61daa5174e1908
287	1	338	\\xa7f3f38b43f7c17b4ca203684f65a99280db8c5d301d17cc97f19b6d181a6cd846e199be9f8d6f733fb534f9588fbc1f6583a9a78cc9fafb2298b96122224a0a
314	1	322	\\x477320ee5e734cadfd4e47183d8b24cba55bbb2322404c9bd30c99d5c6805033e16e99d0b241653549ebe9b7c49e9e0343e81a2949e4dce09b9399ce13fd440f
353	1	137	\\xc5304d5f4ec0c0196c7c10cd734ada845f272b8dc0f428495c5b5dad50fcddd659a14e405d15fbddb20e99a92bb4fba619e2c034ed525a5604a793adc7618a05
373	1	77	\\xea293c8d931f8cbc533dcc42ed3c949f776e6843791d0f6c026f09646864e85ebb11cbba55f2f546eb5f1483491641de72e58ac269a63215bb3a57a6818b7b03
388	1	104	\\x0260a931add1f79835bd5436618f8948bf7853f061ff5b55e809b9f7894adcf5c5ccbc4e8d7c108595eb025a9a7f3633e4f7cfaa5fba5a8d9d3ce4af50cfe60c
408	1	67	\\xe5a84e4752c190bc9dc9c4ff488d10a0fd8d14745d366f11cfa106c261dee3ed044b68be7122da2c4a9998a2389893e4d452355ae2ff79077303a6f55941430c
156	1	402	\\x5aec65c21615452a620eba454b4135007c8cfdc1a2e436a82b882213b6b84441753b1ed7b1d52d183214e7546917f6cb517f5f631cc041a10b271f1d9aa7fd08
186	1	388	\\x71fa6982b351342febbdb1022cd0d16cda9337784bb9af56df3959f348789918a625f8b6830173662c5c27244617061ffb8b114f4605980a03b8057223d4c908
214	1	363	\\xddcb4057d9903a66adcff56c6b26a45e739593b0859132794d5c51ffcaacb9825dc768ce2fc79f53c945a482d5b31e740ab186f78d3c6a1f3989daa504cb110d
247	1	171	\\xad05b27797e779d1ae4c8cdd623ddb26a4f344c82362e51db0b78a948e8b15777650806dd7649e1905c4b2479c604b0d26f35b894a7d7095c737e9a2c3539905
288	1	313	\\xb3471f2b561fec51ff4e60036038c6e879a276dd46cc3d3a11115a47c5db4d90488f5ba4b3ea4c0ebaef7ecdf7a695cd2c161e15be238f2246d37937c8e02402
321	1	243	\\xf6badad6830e90b10f36e09f69211d228fa8372c1fe782814a3b5ff785753bc8390de8b7ace28b01173069cc52f6c56fac7f5f271556c3328b02ef235e9e1009
342	1	325	\\x20a5fc9d523dcff1bda0db6065d431d782987ad39fc7d93d79b74353685f93b1be0f72419d0749698835ce4c7263df5a849602903c4416bdcaf751a23a69c908
361	1	241	\\x12ede176f0051f5d278cdd252e1ffc45236900b71328e269c9b472ee2dd660c4b1ff43d667e64036aa10074128292fc47f3012aabf3650cd9504672f6bfd5904
380	1	184	\\xbd279d4abe310eb3bea475c4ba76e901386b55257ec464bce8f7af0e22e10d48c39179f9f29e06102173682466fb8abb18f2a6b78a962bd711eea13eef7c660a
422	1	293	\\x0e5ef175a2f37688bc67d84f94bb3d8dfa0e4957466fccd5761a735daaefda00379425ded7b53705e3191c8b369a3db8467ffc48e2609cb185bab275678d0c06
424	1	132	\\x897b7feeb24f79ac5734d14d7f0f4ee96263050ab28af717bb388e6c49cb55b61a8f2bff15763578cc83fcf963c30ae47b191bce6df5365a137beeca68f72103
157	1	187	\\x5faa8cbd7a9285fa372aa307c6ac7c137c587cf56d67ce2bc6c0226ff8e3eccc7912c721f0afcb534e95ee55d320275f6ed6d7d936d686e26a6cb735dee5e005
195	1	292	\\x5d7fae779dd2c065f3da0fe7517e10453991c74a114f6b934391abf2d980b52dc0fb31f5b63500d6ada4389603475ba4233ab569f8c830a120a7b28fe8e5bb0c
237	1	10	\\x56bc6b017fa8b866ff9c5f0954590b20e6a5745259d40ec28645a4a75722c8c149d9a0fb4aa893c9956485a6360096bd8584b8537881ba5b744ea98ecdf75107
259	1	258	\\x9a50214967fac27e1916902ad26c5b1f02e39a967aaefd7ca78b2e759a2e46acfbe3b1996ccc662294c0bd832ad60ac445390ac0ebc637bf47847cefd56e0708
263	1	156	\\x409df6c294d70093eb13f5984b02a9bf8f02bddb05bc1dcd4e24431954ef95d4825e295703e3e2f1d6a0935d11423defaa0b04c9c232021047cb8c573a4b810a
279	1	177	\\xd252785b5cca9574c1ee4e6572f2d706987c63ffb57e2322fd05f59eefce2771ee1d2f11f043bfbbf7c3bd3f5fc39fe333365aee6b6de95bf9ebfc648db47702
296	1	286	\\xc168c383a18a7a6201a15a0d7c27f6e68514c814732ba363e8443e452c60315bb05b17563a41211a866db4217d8a1af6fca965c4f3f59efdbc587ba07b65fe01
318	1	163	\\xb126b6f459d49f13ec9fc59d505a089c8092579f39abc16a60c3c65bd8f5331ad6bdc5c7648aa7ce48ddbc247a93c64f6a09943b1a9c7725502839ca0c71f00d
347	1	391	\\x767a8539ab69e5272839011329558154ee4e6287bdd405ed17389d7574efab927664f14585b66c203be5c051f3286e7514d511fefbf842a0501e2c47cf8e4f01
371	1	283	\\xc31cda876db6bbd8cb3b39a49591018ddbdb5aa6d1991a2d563b37c11fc63e9042b67ffa5cda08b282daa3fea7fbcc01a08ba1301d7a2ee336e195f5e985fe04
158	1	273	\\x813cddb0369bd847d4eb685900f39d7285ee7627824c193efc012308ff1c77bf52171cdc5d0c01283fad61a3106fe7d737fa0efebba762fd601277328cbdb803
207	1	416	\\xadd82a4b9c52c209effaf71743cf21e7b606830e052d3196c84f9d39579899fcf702667fdca7415b9982fa0eb01c3b1daaea5c3e38908643a32e94f82b96ef00
248	1	331	\\xe87ac757e82578578f246014dd3558399fa1005c15ea27e89e497099d290dd8f173df67d3615541e96fbe576cb0438bc6534e203de58afbd183dec742c36d206
261	1	294	\\xd2eba640481bc06822711519e6dddbe953d4a651c7b7d1ca9e07c2db9e7fe8940d5898387b915b37af001d2d3b65ae94137761c226b963cbf2599f665eb34e0b
264	1	60	\\x16f1417c3a76e67572ded615b56cd921622e72525a1c625410c7d3da955e2722662e34adad8f383bcec4db26d5f00a8d5f39fc21bc9e929c6cbf9b58a8370b00
306	1	320	\\x795c6ad00674098c7124ca02e179f20f5a927ef0f65920127aeed52b5b65933999a76c4997907c9b922f4e595da4e7ba018501b02589ae19d9ef4feda1c32909
333	1	302	\\x2d59987f2f84fdac438135ffaeae68b02eac5865fb6432fe14ce229c2249bc4beb3821d444a499665b9c5c74c973008620ad3c30eccc50156bae7762bc9e9106
367	1	47	\\xdfdc22575eab780d77537893a3f2aee57a9733570e9495d36f9aaf3cc1483c4936b2a412214c47da06099648d2e70a1a0b40b8d789539f9d22690b39b83fd000
391	1	42	\\x7f14afe1d085e25d4690954992b63c82dfa71a09634e254b19f0ca6aefa31659514d98fa207eb07c459a1688402e6f75b38a9d0e45efaa66ea98256dacc7d303
159	1	234	\\x078f733b55377ceefcdc12ac72ce918b8d21806d1e69c20e2dd5208c6f6fc2e9c398f341bb22a405fa7e2020f71e1910ca446d35ed3ed6dbb5986e3efcf8150e
182	1	18	\\x19931c298d227c3b9ae592b62583b44bb0a562232913d32de0a14b761fa10ecb163b65662b4cfe2e1eaeba0878854929f538460b41635bdfdf264ba09cdb6903
212	1	222	\\x822e09234c55d773aab7df6de6c98f23679e56c764bf4be369907f9cdd50f368019e5bbc6e08dc24be7f40f14966460ccffcb119185c8be9707bc2d2018a0a08
251	1	55	\\xb519f473bbb2019ac795b2766e898aab682164f03998534d1722fa509508912bc74017bd29ffed9ec0d90dd6a83fe09e0e82f56809b6f090dd61ebee879e9007
293	1	422	\\x26e708814acfd04561ad30dab20eeb1192895addde4a7d67499fe6414f894c3fcc1eb921b8e594bcc615a8375bf8af30ecf184b26b0d4a7c493bbd75df30ec01
315	1	13	\\x8ef3438b9fa882b683d58eb9293eb9d07dcb3b000e8f7891449e1fb2a7c00d9198b884e130d5d45a8f909936798392a669aae88fb6b9687b57a8088e06cdde0c
336	1	48	\\x02fd3e107162f67366d191490f81c70716ebd973df2ff77d67073ff04e961b1af95d6fdd03843f6c2a1cbc6f28b32326765b3e0428286b04604a4178dbbb0304
385	1	31	\\xe126474f68cc8265f43b232328dc31cd0fa1ef544f37b6511d20e572e7fe32f743740d9ee544bc35afec287a093a0a0f6718611b8651dac7ab403fd64f4aa400
160	1	106	\\x7a0be5c7618922469d16c26210fe88d0f4e31810552bbbd55c31ccb710322651357bf27d20445530f6e1a91e781515966f2d3435614f6f5bd67b49be1649f20d
187	1	33	\\xf389c9aa1857ca1d136a94166b849c3e2e173e913ec25c2b398cda8e4dbe92011b0e0d37034bf183d23ea6010aa2610ba9991310bd5d90d8c63fdcb5ffca110c
226	1	110	\\x41103dd78bea6b0180b48016151a941309a1b95b63f2a390b4328d4b03c1ef61aa6f31de440d0738631fbf39dbeb3902f2f5d7b86492b480c430116825c4b70b
255	1	46	\\xb3b87cd6669c993a452a8e2cdd4c1ea4fa22f14425ab1394f9c0e1d33756760be378e47ecbeb1622573913c0bd5e019ae000038c75412b60eb326369a47fa501
297	1	161	\\x4c558cf05a19ec6c2f9fb11b3761fd366e32452c6f4d5b15859e635727649db126e97db20b3a2de9fbf94a22aa9a56f2b963a592cce71f505180bfbd2146c901
323	1	182	\\xaf268768b8294dd4b3bd9f9e3339302f891af19de70570d782c1ceefede41106243fa15e7b37c926b20676b060f6abfeb9f782c06e65ca8c9bc6e34d2518a604
339	1	59	\\xa5665fc25c497bbf28053438504025fb89826a8edf86dc8212f420d85aeb85831b3b511625eee4dc215d385ef0344d0448192ea71e100dac8293cd96ab0bb709
351	1	126	\\xa1d7312d63b68e9685b73ec3f9750f42555cb56d4dda14c2c0fd277658f205acc5981475d172242677e108b7e9a1b8954c0627d52480868a8dbbc1ac3e87210a
372	1	304	\\xeb0812281bf58251d037469174171ae84334886531ce302bde522dce2542a87d0ba750fc60a4b4a7a733c91bcf30d6ba84425acf3f6142c404f4aa12c2fa3107
415	1	399	\\xa3994932b6025b141d44bf51f3b132f3ef3f622309df5da83455b4ea170227cd58710f069bf6d8932f30394e7d385cb5762b8bf030e4b1914ab6dda452be5909
161	1	360	\\x3ae8a63f9258e5fe81d6cb2ba80ef7ab543a83f17e08a4ff018855d2155de74a1c567ca29df5e6a4c9cfc0e37ba79d0041f7d7358a4bdb8ae8ea6295699f7608
198	1	213	\\x0eb6331deca171838bd3f2135ece86f7589028f08189af02df955ad468830d3ea27abbd6fd676b591399ee6366b56d1d053259764897431ab74b7fc2c288f404
230	1	352	\\x139f0d88280bcbe5702db3fdfd14e247f4ccad9ec2c2cb8054486af3b07f7ef0260603c9e8a6a62a8ee36e571bf0b69a14dc3f5f9bf80104a8ff18895dda380c
285	1	401	\\x31a7d38d0b2bccb74cafba43e951fe37921ce014760645819d787bc5c8e8392248c1dae3757a0601b7069228b1994d0ed2af7886a8d8a4de1212e7b83c46f304
309	1	109	\\x24e14bfbe6b3ecff900445bac34c155740f0853ada202471e127649fc677fea814f38d2c0202c6f6eaca8500cbca03a05924ea9669488432a29695bbd791790e
327	1	368	\\xc7c1659523bb1d2323c1f02a6f706e06591321c2010e3c7172ad710c5ee9f7b40afa354ff7d32da25a1806da037e2e6c82e3ae74cf0bd034afdfc6cf6f59630d
350	1	279	\\x6abbb975fd8464ffd76d8aff6a794ce273a15ebdc2db8c53157557664b35f1d05365297ad9e0ed15ad56a5159751daac85fcae4a11c0e362a485e32795e36205
369	1	314	\\x6a249df95fd56c6c48d32af6c457e88895b7050a9f87c28f38f108e7cc7decb327e4617579deb110f81e72c597543b7f487ecd70e91555b9e0e1fc1f44a82100
410	1	78	\\xa161b427461bb38884f7121012b75ce28c17b6fb4599d1455fec570071d17c5a41b37581fb50213e1c31d65923de7498565d7b95d02ea04c7b03df748c0f7a00
162	1	155	\\x2cf97059a4e411a9044fa7a98185d28cdc38db15453a1008e8b57dde7bed31eac94343fa6f4fd5bb444fddd1467f7cb972283f3c7c48750106bb1fff80865408
185	1	270	\\x5d339c0c7b7953253fa8f860aaff4f5f98accd272254fe14e1d542258a1b4756c43fe7f4ef78ededf5f64f3b407dd8e781e6b267782f16b1f192053d64ef5b0a
220	1	364	\\x90a64e9c9bad8c9225713d44c0f16c8e05a2e2885f4cd4d0ff0d16ab93da12c68fa85df986894f5b6a61c6482a9d55ffcd001e99475d4863de3311239394090c
257	1	341	\\xb80a361a62b3b7699e9ad2f579b175c1ef24ce79588233a1c5ff931cd2c403cbf0745d608e055d52d8f809fca5d6db8fb6b9e1fd6506f810a843884f8127e80f
303	1	383	\\x1bc98f6c638a55095cca2ee9e4653579071fb9d694858130c224cae6b193c8ceb8cb0b287be3a9a88fa6e3c2beccd638b140e350270a900c764a31e2f4bcb203
328	1	310	\\x225bff07fb4613b39676b2b2c56e4c13e4d03521e3345de8dc51b2870b81e13cfd9f16eeac18f1c95fc82c5cee4ad6c66970a4718d5d027b97e0ccfade2ae700
378	1	347	\\xe41c608ee3c41ef82f64f47803bb54ae1f25552356ecc7868a98df64fde1262282ed7a899257a6d5e937cdbd9900533cb919632afc336a9942ba57b55eafaa0f
395	1	122	\\xe1329442934d005153b83fd55718a6ac12367c49de25d27a08a0fe4f1251ffed80142efc34d8441cd3213426f47b2553f3b4880daedc57871a9cbfffe0991702
406	1	253	\\xc6490453a516c517095faac0af612e5040ea40d53e10c0e8ad52bc7c4c585065f17173a2d582f0f518284900b0d63df23f5a386518e795de60df3bfdc6a8ea01
163	1	396	\\x6598caaae933130668e80c8f562d8ccd0473b42705d14a3a12ea35c15f95c8a25a4e56f9b64bcb38e1879a7799b9d792ff933448364e06f82cfce15142ab9c0d
196	1	88	\\xef743ee449fa581e5c8f333be1a6153908690be1166055d4fc477fe2fbd00a556cf42cb3e2d57d0e2d41d2ea9f9f84fcadc0633a3e80440428746c86dcbfb101
256	1	214	\\x0f73960d0caa526923240d3433a388ea16df74cb6baa15e0ea3db7c06856cbc8fdc7b8d1827dc3658e3ccb5cb1a3afb818be1ef1b61d28f64e2017a15f67660f
269	1	300	\\xc383335d6e84b4901578d99786cc7d9439f5950e4194387b67defdc9bd7d4edab55fdf71f18273745e523ad4900a00673a42eb491d1d14fc8c49054a4e659c09
301	1	64	\\xd93aa3d44cd55a4a216488e783a0e0801539d1416e1c61c7fcd2bde4b6b9801b7a4d253177c4e10ac7eed8d52666a5d1ab99799e76ad4556dfafa439a888b707
335	1	344	\\xeda5fa15e75be619d96a91047052080cff88563c5aa8214a12c1a7e11d1a3938563946d6d26f8c08e3b030c2399ba4d4d2df7c4fa19a955efef537c34248350b
364	1	54	\\xc2213b8cc651ae43ab12d95fae01c830a766217c3ae3259e3e07eb6a6e744facb91a5ed690e75f74aae13abdd2caddafb52f064863f3fd0a1223e6dc78d00409
411	1	281	\\x1eb0983066e6535f1a48689e75889ab0f0468be672217afc8bbd2ab99ddd9448966c9b64280b43f171c01ab83c3873641a8f1bb616be8bf0171ffa4b94602f0a
164	1	405	\\xb3c8bd7c7fba9383af63da289df87790145593f8cba6457fcce0f11fe9483bfc408430c60fe2bf5ffbc2d4653a3ed82ece010f754fd215df85880390803ef80f
208	1	280	\\x7a1e282ee3ad95879998762e4264ecfba2c8881b6fcdcd673bc38a0472aa1fe9942fff8703f467447a04239d9b1cc64670e3019cc8eb1392b96fec8c21098d01
234	1	207	\\x36cc8581bb6fb8c285f74147a82a8cd3d5f8e6b2fdb26c9ffc3d9e64de258a15f0808099bb9db6652fed700c8a611c1192d815cd950ed8eae3abb1aac8b7fc09
305	1	99	\\xdd8ad2a798d3d6b692328d9f0cf2465c35eb4a3054238b249966ea36343883d769154b2eaf05506d531973b3fe30bb46e712d1fb47074aec504df01779d6c006
346	1	66	\\xd471148621176e79498653207f839d062526f3e2ff828423f58074caff45bd6ac7f184c68d01c83fd619c9292e0f6b4d37b5870a0e39fa9308166212274e9000
394	1	236	\\x8a3d9e020bc7be278f81958536ba1ec3554564f473e70800fdb3385107a7287ce86ff00a325604c7e9ffa4ffa07e1e56f815a96ed54de936f21a55aa031c7105
418	1	108	\\xbb39ab01a07aa2d416d805ba195eb241e98928c6c111dd1025cc8da2cc2fa2315e7338a0e24a85748659520260c108bcce7e1d1eee35b4d7ae0b5ef8fc348d06
165	1	68	\\x874e996c8fc62995fb20a20c5a0b64270cd5c6ef2a7d759d9334712be35221bbdec24326b1f0e9ca4e0b93ecd4c4d9a1d837845c9e4307b2783d4573a499a10a
201	1	387	\\x3375493be3212b4e4dd903fa0b3a762dc60cf07439a9e87bdeeae8ec979d257ba883d273159faae581b3748eb9eaf84f18314190b43130dfbcac9404a761050a
253	1	4	\\x097c71625748477e924a889e101e730536f5cd0afc1e26c387f361333e30c1a2e9ff492f24d309d5a2ec1278e885a945ef7aa11a01ed734a3da02342fbf1940f
266	1	291	\\x733f82110c0a905a5a555671067bec2ca9aa529dbe33bf1f4a9cdb89f39758b623ce1b3d7244c1159a5e19805c8f724baacae7e0e7a9f318435a414bc49c7301
294	1	299	\\x4dbdc32f36e6d7f053d7fdaefe016124823c0bd99edaa9fcd5f4cbfa9636c60f922003d463942d4ecf1daf2bf747330ce94719202bddf7a84157d04e54da3001
329	1	251	\\xcd2dd45320367d7ebaab5a1ab39dadb50b82b39b5a076edb1f9e30e0a9d704b0e2ea8d895ea44f19b483bd6390cdcfdfedf15d9a12e80a1f49eceb6a2abff00d
368	1	233	\\x236de51421cb7225a6856ffedd352a2692a6c3ffb0ea5b5eb6efe8112ab7463910900798e76073c729f7c7d4ebba8eede7a67222d0931dfc073c822123632406
401	1	424	\\x1249f81702c3c70350c277b2b47ef512c275b2fa74bfc85878fc2ea5d0855e6b5c7e29824294bc7961ed53e83e97915b03286b9475b1e2f54fc402c649f1c408
166	1	85	\\x1b31773eecb0e5bd773247b6faf5ad8bab9853d87b6fa00020b530b81b956e5a74d1def4243451b740d1e72e884078f931f0d98f73f191bcd81a02743ee8ae00
176	1	321	\\x78ad69cccbd59a617595128b5a088756d614116b3d1f2fd40d2c2c92eb22735757b88000e18300786009867f4ff781568a27f980b845079cb9912267a87e3202
215	1	164	\\x437c8be1a650f24c78aa4299147094af55dbd30ecff2af68bfd3ea112339c7d1cf3194864ea5b9260e4842c8106598b50c45f6385086bc57cea4d13171963e0d
245	1	174	\\x6e0496750abd6622e066c28fe807ccd17658fe3c6053b471ead2e173a410997bd1e03c90fd4236c7a6094eb9fbaf993aad4df37c862ff8e20e4c30936fcce004
276	1	94	\\x8261a5945fb7d893aa09c039881c6dc2dc7402d2de8d418f81f6568dedb413ae9e7dd19ac09dca55070b730d8add8c30093ddb4e0e96e29161deb2227daad102
313	1	239	\\x27f7bbc864a71121412016659d0db39203eb36480140a7f0e9b3ec89e92ec9bd0e09fbd986b319f32ed0a0d8b3b620d756f523148f42f083815eef4c9fa4a002
345	1	400	\\xd7f077c94d52141415546f54ecb631c441b29139a24866da3aed4e98df53621c1bdab888d0fe827e1a49ea104dd1b6850ed1e4b8a9325a0a952e0ec4e64ceb06
377	1	53	\\xa4558a19d9d03980597383a1923ce19324b514d06a6080109864312fb2d3a1d69a28f90cb1294a7850da7d286c900c18b782cbf3c74a0142a89cb073eb6d0c0b
413	1	166	\\xceac83a9bf13c0a31cc6872ac629e2a4bf6ea608d70397435525d760f815120c048521bddded2d584e4c0d7cabd85cd90278a7e3b886a097f7ad72444d381c0c
69	1	24	\\x93fa62659d867c102a297a5e75973a811fc6c80d5aff8482262a29798a10f46dea10a37ac5d1a93aaafeb1e181883dd965e07cdee163f7c47f1b246f5e999900
76	1	15	\\x152369b87240746a82059028543681988f75b65fb5cc8d9ba7f7c042ab3bc8cc29ccf126595dfc66f1ca0fc6270090980daf0e3526999773f9825ad6a4c7340a
84	1	358	\\xc2a1bf47e168d57d62b3d394867ea0f4fa7b5de7e6d330d8f217712a9e005543aaad227ed118019f30700916a0aca93265725f54488d9a50ac53ebd5f1676f04
93	1	153	\\xbf235cb328b7161c2810927aa2ee63265a7359e17c934af7e07442c3ac1a2c30caf184a31994bf4e2846a82685e1cce9ee20d79ede0c775c6f31562f118ae309
102	1	127	\\xb38231777c91b027571a0e2467a4b076bef66724a100e8207a1acf942a0ae40c355a5b92e879a4c491d3e6671d1e266b0e0c3bee5a503df1895f75a3c2f3f00a
112	1	237	\\x9bd3e043b6c3e3d7261e4a8c294d251197eb864cc8831737236887263d1ad5a78aa5efebc92508793b4d46a70c09059b8456d7213d4e25f17965fbee6536cf00
118	1	37	\\x8819b06b898169ab8ff6bf4dbd8027f7497978ddfdd98482b88e095e29ba228f1c9e74c5c9a99cb31631d411b4626ee6bfdfcf42f35de3996d46bd2be32ad202
125	1	45	\\xf0234a17325a8c5de982f4b646e4ec424ec9f05500ce700411d9172dd1e8f50068d4fb6f9c78a709d422d499914ab12f3edbd5c9129a1f4a0844a83be5103204
132	1	74	\\x3831ea63ca86e7409e49bd1d75bfd17977455ec08a055a7fc11504211906b1cef183d8d32e2d022e8fd006754fd93bdd2f26d78f759d049efde5a98a8ac9640a
138	1	384	\\xcd46c21840d846d601ece90a382ad83d4d19f65a3d993366665d630e3b51a2830716b8ffd47c6157f5ad8e2a0127fe0bdc1b32b238aba992da3ce37138834608
144	1	102	\\x09d626fa49054c7eff4eddfd0268474f6b13da0a9f8503c7cecd47d81db0e523b73bdc114b0c531d3f01501023db537a2584dfaf8df3a18fd191b5d8de88f606
197	1	409	\\x7bb95fe6f3f28d24c47963adaa2d184f3d7713dd92a1703829f082a434be21012b3ae72c2fe5b6ed3fac1d097e4fcf2f3a048293b56a18e7bca48d0dcb824103
222	1	169	\\x256aa873b3b8f0fa60e18272764810ab7aad1585091989cf99a51de2cbb8355e1daaddabd5f894f1cee6fb94c12583a987c9be61369fc0342f146f7d9640e806
250	1	16	\\xa6b60b705656c3abd15d39ce9c8cb99d598e7bf4d69db1bc1656401566d77d99fc1a092769b1995d41392f67e39edf5945caac9ca456c64f93288aa9d6ef8305
280	1	217	\\xb761adfd62356be63e4a5461c8f77e9d5d6d36c4e6cb1afe46b9fec81e6cde8be7a67c4f81568c79ac2f3c37e4eba078d9ce46c11fe2a16f1fad58f1d995e50d
304	1	138	\\xb694da3e1f26200662d204ea08ea3a3ff1fbb8f2170bf8e8db6302fe5f472bea0ca91889c45b771e521741d0277e5bec66f5fde9db5cc083fab3363b809d3705
344	1	2	\\xfe8c1ab1aec574259ef6def0eb4e385326c01d5afbad57906c4cb4055203922fee36b66aba626d868518865006ab2f43474b1301e27536fbfa290c3894e8b90b
366	1	415	\\x2d5bfe98c706134266ac2930e6a65f44b780caf7ff402e82ec9867c03f048d4cc058d93a03f8178b80b8a886da9bcfdad4922a8787d1dc09f27ff603fabcc10c
393	1	231	\\x2f857e79610c02a0da0272f7c2d3695b49d5d204555dca07a79e2202f9b003f48be88d58cc2be1dde844bbeacd107a97c65c459e947f5be931b97531882f5b04
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
\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	1610129389000000	1617386989000000	1619806189000000	\\x1bd6b571cca07ff85b6f944cd464d148f1b26a5489254260e0a6bbe9af82f3e9	\\xe16f722f3994b5c598b325bc3adc00da2f095f9784a34a124c2f914c3e997611c3b7c7bb19b7e5193d82b389a458df9b5bbdfee2286b2717eb023187a9656004
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	http://localhost:8081/
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
1	\\x2a5bd76ae3593023c0537a344e115ab8e6f125dbda145df6cf53dc428ab6886d	TESTKUDOS Auditor	http://localhost:8083/	t	1610129395000000
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
1	pbkdf2_sha256$216000$A3FfsG62qcUd$apPtb/kVE4YkFvUVr+hmHs2sWEXfXQTjyfvgha0hT1o=	\N	f	Bank				f	t	2021-01-08 19:09:50.164873+01
3	pbkdf2_sha256$216000$p8ocqvEK0SDr$OC4oQGs3a/yuzn7ZxnKfD7I+y5tR3BlwoYetDDhVG80=	\N	f	Tor				f	t	2021-01-08 19:09:50.351416+01
4	pbkdf2_sha256$216000$HVKU5K7hMaFc$HX/PMQDYx+6U+4uJMPrgGL8f/4nm/04BSmzCV8+7uQ0=	\N	f	GNUnet				f	t	2021-01-08 19:09:50.436016+01
5	pbkdf2_sha256$216000$xAPLYoSH7w1e$YvY769y0sRtY6YrNEYPpctXPzDNGV4+UmC0HXepi+RI=	\N	f	Taler				f	t	2021-01-08 19:09:50.525685+01
6	pbkdf2_sha256$216000$TtVzSTqKQOKd$3J9zEhW3UvfNkALEI6cy1xrgT+nG65Y0mgty5dyRdSY=	\N	f	FSF				f	t	2021-01-08 19:09:50.616195+01
7	pbkdf2_sha256$216000$XqlCkS7lCWhr$GDE3AMa+HktNYgl2tyAL8ZeSm/VAIUFz/yXiCeqbOJ0=	\N	f	Tutorial				f	t	2021-01-08 19:09:50.703132+01
8	pbkdf2_sha256$216000$C0iQMG5MmCut$KagtsC/0LjDDoxBW7OhZGFCCnZ8mEUvJ8RvLInxgsfs=	\N	f	Survey				f	t	2021-01-08 19:09:50.786994+01
9	pbkdf2_sha256$216000$Cp8QfLf1VWyu$+9OD5GsBo/Ut/IJya3NGOyyIJuDCI8ZRUwR7qW3WtPs=	\N	f	42				f	t	2021-01-08 19:09:51.243658+01
10	pbkdf2_sha256$216000$KXvvPD0i6Co4$RY6NsuifkJmEOYokFqcHXRTicrE9H2p2zM/3urpRm0M=	\N	f	43				f	t	2021-01-08 19:09:51.714159+01
2	pbkdf2_sha256$216000$gDBRrFLoJtLP$pMj3Z4ObX/OnmK87hE2kweChcudSw3mucbblDPSuBB8=	\N	f	Exchange				f	t	2021-01-08 19:09:50.262043+01
11	pbkdf2_sha256$216000$j3Zo61t2KAbP$zceJzHPL6SHs2XnMiht0Fe3OMeupOG099NlfTdpM97A=	\N	f	testuser-DyuTYxrN				f	t	2021-01-08 19:09:56.957872+01
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
1	\\x767aa6519aa4d76d6cc9d532fc7c1980b4e5b32a1a4727386bb9ba01a9206814e544c24f419b37ca407031dbaa3d198daecb52c2135fb4801345101565f24e06	124
2	\\x64a08498b51d2e709dd09e2315a5245196273382e87db568a04f22ba8dd7456caa8f3870195480f9222083f9f3532703c0213d4dfb42f3c184dc4bed4aaa650f	84
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x010c1dfc23598d1ec22a5473e4324f0a15ca265f740ce0224e62d62bde540b0ac9b04b96ff51a13e52affdc70407893502ea71a2e9ad64fd59d086b2fef6cc34	\\x00800003ae6db2b7aed959ce3373718f42134609677bfe6f4e9126dd405d1c5928e2ed63eadf35b4a38aa7c6bc86db9a850213ae4c3134c859b92490bfb804fe0b01db6edb6b0d5b2b30a155174cd58f28bb9fddfc108e44aee22d8d117c7c90b45d6855f498f137997661c1c02dd36e554dac0c60c111680b4ce0abb59aead8e2ba0e17010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x95854b6e2b88f4b6e8c44007c751b59d57445eaefc9f0591a137f3e4bfaa1a0b2d21c3cd7c37b6505df9202ece0cde6d8fb4e161d99b769d6ff13c9670214c0e	1619801389000000	1620406189000000	1683478189000000	1778086189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	1
\\x057ceee3838d7028801a20d87d218bd4615c981df8e69dc00ae00cd83cea31cc230868df17e6c35f26a45c1fb526b8cf1d07a07822dc0baf68b1c13228c614a2	\\x00800003cac77478ab0596e435af1fc1c3a1a14b8d725ab7f73cc6998350c14a39cdd571c212f4e0ae9532ca83d4e257305f98f727c21ce2468e873dcdb18d6b2101754f50dfc6aa26040996d5cff85e02fd34a39a28b4f6ab10ee6cc6831200bf45d391a6e16180777b1c10d5e200186ff95ea7bb3f9ba49bfe0279306ffdac8cace7f9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x32d62bb22a0d74aa549af95ac75b926d8b48e702448427f19d882e97fd35332f4f0bd8c0161485689a134d91510ea6deaaaa01c64323641b01da54c5d6b61209	1634309389000000	1634914189000000	1697986189000000	1792594189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	2
\\x057cca91b41b7e1de08345061f7b7be174831e9b9515ec5ef88c151c5fbc2950393e07eb54b78570df7da0593ec03842abad3a39ecc283bb9d055b255c793b49	\\x00800003d15c0866bca2a778a485c76cbb2ed84678c55dffd97941764372627fe5df3783d71411091f2c7daad9e736569f4b30ae8acfa6bbfd3f01671896d99bfc947dfba90eef1b9cff0f160dd1b6159154c89c3c1af778b301427ddfd0c0cd2c165382b44db608448375f104b8a6968adab99b5ad103950a232210e0a6b956731d3ce3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8a10583549940fa76c0491d6b5da2f7959684d6352aeb03396878dcce9cb87dd07f4eb69b7e92c60f1bca87a819daca4853639bbe67d4538efcce41591c4d30e	1637936389000000	1638541189000000	1701613189000000	1796221189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	3
\\x062cf5cd340c512c4e8e1be85f9b4902e5e888f64bd0f8c39bf497803df8ec18b744a0419ad61ac1d05a96b67d895b7427dd4b3a13054a084b8249469184b7ad	\\x00800003dda446fbe163e17cba04acbb071282ac802bf30ac5be7f87fd37a8f39234f0af7f3024c120587b7b8a1bcdd478aa90582d353ca1a372dd90383d6f7b3a4767b619d47468d9859285ae7a1b110609c719c52a9dabe2d1fdec790c23e78c8db507b2772ae03311f53e39d1632e2ab150d61d840a1b59a02f3dafe91de5a746dfbd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe20b4b3b257e097de0139f2ee41b96c5c8f1fb8bb5fae76cd456b6e3073fb1c7c8847c148cb39f2d5836e4b81afd05f8d60eff0ad329151ac4a84d48d6509d0a	1627055389000000	1627660189000000	1690732189000000	1785340189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	4
\\x08140c97ac2ba0c311a7ca0833fd742a8ed3b5c022e27b4bc664b5af8e02087a78da85483e7854d902acb96d76cf85e4fddaef9f541b5b242edf6c74ce75742b	\\x00800003a5cb2d37027b8c2ec490a9d31b08542022ff15463bdccf08990860b5fab613b147d9e894a75690a01c81b78b6201fb983ebd17e427545a3a13c4f35f8872e7a64a11c1412494b78b873aed73e97caec6efa0f82963b1fcb7f9f4a36eed46ea30218dcda45f79a96b42435ea481bb2d173e49e651d09cbc9274a907ce12198f1d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe804efb0701b48cfa1aee4ee07be1e3ca6e2d4ccd01768456543c7bc561f0ec738067d3129148432854634695c0507e108119b1951320c91a54490ed5029540b	1637331889000000	1637936689000000	1701008689000000	1795616689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	5
\\x0e84cf39bf3839b17f4e91d74cdc812daf66f3659bb25b28a98eb21d20e5e0475b37582fa203e1181a370703ce9faed16d04090bdd96d138be2fba01052b7a07	\\x00800003b80ba7bf81b0632d6133c97c5275824f9310b0386edeb782b9666e2a89fc7651ffa4c28c84290757eccd96392fc7a3a3c853068d6afdd670989ad6db2fa043aa7bd5efedc91d28742ce7913d6a847604ffa1758720e24226028638a70c11e4eab99cb84b06ab2fe9bb6eab13cf21c7035c4fa93709970ba836b919fa373337d9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xaa19f940f66da83076d28076c57db7ac6b827b391bb8d167320ce4eab1fdcdf3c182d544b980f823f287872a046275612b7da35dea31f0248b9ce7f4e72adf0a	1615569889000000	1616174689000000	1679246689000000	1773854689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	6
\\x0e6cf62e64d4edcda8c2414c7229f557196cdffa561efa09cacef2abcc11797f4ddd2b260d4d4c3e8662d1b81cf8e06fee90542a4b37ddf93caaa0d2ba828a45	\\x00800003dfa5f0c7fd1ec0b5a35c6f3f53c739ec975993233e497f25d68c7140ec30545b847a28641f4015ec01e80127189aab47b3960b59c7bbe2016f4c920c070b176782d1db82151bdea7bee2725c3949850260ee4d35a8aafd42dff148b44e2bc0d99f43e995cd6f943627b4c2846e91b8d35d16003a6acd3cbbe3bc8a86fa70c5f3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5e506ae3db1ff069f10bdfc9e62a52e88353beaed5e7464f6d373dda2f59c1c7e887080a1afd715ebefa33ef427f8b6ff4ee526e910b23cce8e0e7f764c6a00e	1621010389000000	1621615189000000	1684687189000000	1779295189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	7
\\x11a0d1e739262a95b896811da150b480d24bca1bdba55982ea26650a60d78ab038999c2770f66ee23dae1e60f6d84ad9f7f1c1c9ef3c3b3b7a503409a92acda0	\\x00800003c9d1d7cd358227b1610c89597f392dbc3f46dbf28df805d1356c04caff45641f94455a264d10118a4b658789886b7348170d3a9da6b91fd87a551655e899e6e52b12f4430606367e13915fcd57efb6327855153c7b5aec8f48590828231847050da717cfa91616e6eaf774cedacddb1c37e7f318ee3dc920b196e665764cd96b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb729d11991207624d548d30e052ff7a75bbd010a8d5350d716cb26e13fb21dd42fb10eb4f1f81a2d2f2662e1b067e9191a7e3e23aa642c9d69d11495e6b0eb0e	1615569889000000	1616174689000000	1679246689000000	1773854689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	8
\\x12744bff195cb250227e7735d88b4dca20d301672ce0caa4246f80ccaebf86980861913e7e3273cc2427a1ca06c701508c5a1b1e7048ca0c374394e802c6a6b8	\\x00800003c55424a270eb8455b64a8b364a0a5fe6d27e68d5e8839b0f86eed8704111b1e810c5b9eb410627bb143d5e1ed472255b5520664b4d06c13deff1e68206f6ac22fd1eb9cc0ec7ec16be4b690e39149eff995088d0cb7ecc71f9f56059f1969a0cf4481661179b982ef22d1badc039cc26fc7b52148d83e0f180fb2809c2e2a9ef010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5dde91669af3253e57d2b5564e106eea97fd3344d738cd91f2388395046c73e92e41c191b4dc88a5d98dbe2d39e4e88ba00191a9dfc71a335075972e339faf0b	1627659889000000	1628264689000000	1691336689000000	1785944689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	9
\\x189c01f3f940faaeccd745dae5d2c67053b62a9c497ea9a00221b3e067f742fe327236666fcb65e950c2ddaa4d9180a1254d08bd18f7630f53cccebde492a753	\\x00800003fbe725f00ae37ac7e2d8c15d2e13f5c6ac72a716eee6fdb01ee91b5c3f45cf929ad4c06f9a48c653efdee23a78ce000e449e3298fd2221617d02639ed899c8b450d48485205872ed80401ba5441092f2ab39bcf95424cfe2808470f7e92e7a41b9929dbf1fa44adec5c8f2b77a000dfea9434fd8a595ab238bbc039d4eb5380f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9b6b11d8ab587ea8484c07b2051de4637bc93dfb767b51f4b78d52873183e8dbde7686b7a1473246a6b5acd96fa302e3610e638139a30aa61cb44e97c7168908	1627659889000000	1628264689000000	1691336689000000	1785944689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	10
\\x1b60f091807339e60c6c8e0733878f984e51264f80c3644cc030c221934385739567143bb3c2ea3459b1e3bde1636d08bcea513a05c99f653aad62490ee835ff	\\x00800003c11a77fbc26b57b95f8fb1425c6268536462722de6d10acd7bbdfbfced1b31b03dc18a23e31780b4760e016106fdb4d4e3b3d87e7a94b5eb270d3184f9e19d1c1b2a5b5bed945e347ba3fce8907b289b580ebeefe2205b9fdcf15a7127dbd2bf6d70cf7b54ed95660cbb178f8da0b0396bc3f49ee0924f1b8ab806b9b25d28e5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x05e209424950b11e2a78a3fcd523150352005df0c3b373dad90f89211765c774c2bb44277918ae44fd39ea16cb782ec343b6ef07633370d6bc835f4ad226f20e	1616778889000000	1617383689000000	1680455689000000	1775063689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	11
\\x1b94d7717daddfdbf5b0a389c9a050a9fe96dcd3947cfccd04fb2d7ecd79236b32c4038fef8f7ec2cd14e5ef47c0ef723c69c91f1a977ff3487d0c60ca4a7e6c	\\x008000039e9ff97063af4c24391739a311778ca419e849c2fcd29189eb1fa68c87f97e34297112abd1bb300966f99ad57954d888fd9e73faea7a406607d635afe7b7b0266ae5c9c76a1f6a32ce3f1d2b3a80b9328bdbbfa7d0d873cc4418cea45ed31bd1581b7bfa8c834ccbe872637a15caad7c99d4b8390f953c7b2fc9790d566dad1b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xaefe08a30f440f744c0fc9bf4884a8ac9f219306eba7c90acc442b2f9168449ca8246c3adbd5fa14b45156c6be28f583df61285d918f77688578bdc354c01407	1633704889000000	1634309689000000	1697381689000000	1791989689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	12
\\x1d1caf9c29adb819574a997084e183e83e87c0bdfafd739631d806d93e91c98ee8d637037e6d490ce86d77473febb00d17b9fcc5569cb269d6fafc082c30bd22	\\x00800003d1c387cd123a915527535d89e9e504703f4eb7501f80e296025ac4bf842fd7945191ccd2c24e4d284082c25c2edeb3c7420f73ec74b79a7eb5817ef5421668c211a44452539c4d09ae6b38c45ed8d89b3c638554873815fd19ff2b2dc9857c8c13cd6103036ff587e8ebb293a22d74335918267185e587f240db682a2174ee23010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2b15e594d20a288f32d578a16f23f961da682192b1716ed61d9c03ab7f476bc79ae01a96f7621966129273fec90ac6b2b2fc9f8bea27e261b8cc62183e2a1a0f	1631891389000000	1632496189000000	1695568189000000	1790176189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	13
\\x20d43b306a57b0ae40f7e3f290b57475a186d2ad21056f214fb05e5f995e89879ef084f95c0b47d9f51c3897363513b416a6f96eee2cb37b40da0b5bead76e59	\\x00800003c9109cb02042485f7495167a82912c535d784108b5645dd037c3a63cf4a0704c536ad3fc6ff3db3a30d12d9478dbaa9e41ef2326324287ec29fb57b62e490cb63de934fe769c4feea9c966958874c338664313fd42a1cd196654dbc3f29d93da48bc21c06b96c617a9414db266c90bfc862100cadb5a1813249d4d9aea29e357010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd00b1f0b265ceb820e528bc861aec71e3ffff77488c3b0e02c1e51daf766cafbe3b9acfa58173c35e0a6b8fb9531a5c95a64d198ea015c99b6e1a7dcc8dc2a0c	1616174389000000	1616779189000000	1679851189000000	1774459189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	14
\\x214c829b7d7719dd159b1cb61b66edcf2d5029c7247132c61aea0a45453a0e7d6a603839868948fd7cb221f694638cd8fd2dcaad181c99fd895dfefcb1ec7471	\\x00800003bedf4e8ac121a9fee577e7d7bbde17eba40213d26b4eb4a5c7a72974b578cc3f9e751c089553d84c071a898a8ed0508a4c961c680e0858c17f4681cb57e7cc115cbf29306159506b7bdbee683de6e59576c74318f7f6644b52b102f1df7a754f7424205380c5695dce594abbc4166f058af2ac620a65b2a75b5f5223ab6f1787010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x115e6a949cda0a79587141e455db885fa7247429d161b340c2f23669308de90603add0c6c587ca97c5792a36f63c53861f6bc21ce4ff6f830d26703f3fc9c30f	1617383389000000	1617988189000000	1681060189000000	1775668189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x243cbddb6c0bb17a779cc124ab17429ce334a880a82884bd5ab5094d639586da4001fe51fd18eebd0c0865f43286c2d5b4b1dbf5c5acdf242e0b959dd2192c7a	\\x00800003ce810bf010f5ce6218624f235d63424bff675eb30eccafda0d413c2bc4b74d1b45ff2c07e451715f7a947130ab2c620762447a2df8a8c860eb903d8cec1977c6a8ec07c83b83362e88db58490a1e0d9a105a6b0ec155dbb1720765c9bba14c958e151c39cb16286456071cb7d4afb1c4a6e13f17d6b7681d79af905d55e016fd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x95f9c6bff8b708174366010eeae120c7c879b640b9f32b89a15d7fa615c402eae0c636d8f6ad56cfa4597f2a177a5a5cd26022868321f09b0115533b20a09202	1639145389000000	1639750189000000	1702822189000000	1797430189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	16
\\x26181facd1295bd6b269abd074720838cd75c82c8c08c23eca9eae3c76fe9cddd9a2b730094f2d574009dee912e633189d21ac0b774f778e8be5d719c8b769b9	\\x00800003a0e299759d274e02aaf88df8ef29e43c925e3ad1a4d2f4db35478ac972476a639ada41ab8e48cdf03d87e3466a60633a9bee8e8bf4b9f7081043679fabd73b0fb6818294110841520f0773d0332a8ba19de4947c25e1a4dc7e750223bd80816034ea7e6c0d4a9908ef0210ae774f0dd10b785b27dae71dc557200b850e14d1c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5e3fe2ee5e4563ff76e031ebe3942f134bcb355f28204ffa44f84a66ecb40561ed19f44b59d631ebc580b78b2f9c25f9980e8869810659b46058495f5942de07	1623428389000000	1624033189000000	1687105189000000	1781713189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	17
\\x2988e9fead8328ca858cd7b046c5c1acefd42b81de70beefc58b82a5e3ddcb603f9b385084a55af555c9a1fba11cce6c411e0851f440407f2a3d5f5e9387f6bb	\\x00800003dbe65454ecbd2c18a103f3f59cc1b599f320f344c64b6549e35313f3d355159025805aea0c097d53f4d0a84344a3140b5348bf71ad0a5911f1330b0091f5b2173b750db83a3002e7766d75699b59c06fedacacf0eae215e1709ad627e660211c1dfbd8faa83c0c45d107911ea0b76db27c08c5b567bc7b085c6d993e1eed6dd7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7ceae10470b33c8556346778a4542280410c0edd93f30c5ed094a6601ccbc7b7596aa04c745a8c01d7a57ab781389945f5125905593ce872c1e378d5e27bcd01	1624637389000000	1625242189000000	1688314189000000	1782922189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x2ba8e0a417264236cd20c636490990cf3015d025862e8af7189ebb72e85a299033deeda725ac2a3e0ee7ef5895e417164a9ba048c2dd2856526f051564135f1f	\\x00800003a91b0ca708b220eb52941913591f1b4e4593f1242335a5645d1d1f4f3081d61182147569aa3df3b121c044b63344a3638daea52034a6f39366d6c1568bbdd703af25f72a4654ab2508f089084aa0fee6df092e348356097adac504cde9bb92ebad9535843565bdd0a9ecf86ce37cccba1ab59e94cf556ae888d4678d6b388b6d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4f96d077eb63732af6ec29f24113890a360a210d7c8ad7a5a8ad035034603e797f708f5a49fc4f07adece277cd42481766ff146640f8082b1da4f19e9fc79706	1635518389000000	1636123189000000	1699195189000000	1793803189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	19
\\x2e68ad0e135b54ab2a4545d04e637e0cea230ba32e8020c676fec1903960cf766323fcaba106004507bf776ecdd3e52715552e35f60bc5f6c5605772f5fe58cf	\\x00800003c83dcb8143a03acc765c4de259832275d2e45f802e71ce7bb6b87868cd129b38b3b5ed68f82d793c917e7a9c2ade552a66214f9d65a0fcd8ee8c6c95df47e4d313150098f6b3f86f85a62be429e0940c4367b106a9f54507b9e9b771e0557c54775806f92828f7870ccb2abd1b01ef554991144870686ef629ac620cc5cfe815010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9c8196124ce3a4c9fedac801a2ab34e46cfbc72f4707a7f134630d22db16c80b67bbb6fa07f4cdfa0d163bfaa8486cc731e4db08927bcfeb908884c2307ed409	1616174389000000	1616779189000000	1679851189000000	1774459189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	20
\\x2f34e5c98a44f2d8f7963fdaba1cf00e313fc758e1a4e091b850c7c2929a4497af5dbde7563cc3322c0b8a15fc4919d4443aa80d31cc594b00ed95877696d5f1	\\x00800003ddfc0a5398f65b2418d7f991dd549ca333cef6c3a078d32823155cb5cdd365db8c6b7ee7948e9088fd3555f81ceed4b1d7b6511960d7c3e14ad4a9c3039e20712b5e21420a926ed9b71242ace1ba53fc5e6dba088e5f4266d592f8c4973544994ca110d7e99ec576bafc7ad1d1430f5f0be01cab2f35f877aa5fb4abd15f45b3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x77b220a17aa346a7dd909eff721aa07cbff494c0a3ab9e8e11bc2ab9c56527ea649a2a78c92d3c96622e8ed04373556ce97db086210094510587eecfdf769e06	1617987889000000	1618592689000000	1681664689000000	1776272689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	21
\\x31b4ed65d486e0df2b166d8a858b7e548251c113a61eb0d84b484631a3800d579f35545e3d4f45af683d421296f44f7d0c812d47119211f17b86c1eca604d7f3	\\x00800003c9e2cf2d43bb05a8821a06a3f0b0637afb884b9acb258aafa7a2ef089ab0cd28cc0ebe3717b6efd0f80965defdf999288c1e8ebb73988da33a32ad2bbc43a462ac03d3488d3b7a8f7099834e1445b2cfee25cf180b1cb87359b90d796bebdf5967ee08750390a314591d88b598a5dfcb292bd58905d6c21f85c15ba634f7c32f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa870c8b1c7721590b29a6878f3cbd0eab4964d8eca7a65b44af481543701589ebd9a60aef8696e6e6e21f41f517b408adfae6acdc6c0b9589cb38168115ab808	1613151889000000	1613756689000000	1676828689000000	1771436689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x3298327c1ce281c6246a8435f0f9eb40bf654a2c39e2862a13cedda7e44a3e4c47add81b71daf02c32031e7da4f0dd660bd8afaa405fe3d488a0449ca4609cb6	\\x00800003ccf3a48f9365f0eac2e460561b142faeff806451e75dd26c121e60ffd6e69f22620649022295c1b42496e3acb5028d9de23f51d4f4f5a9a739826dd3b68517b8fa5dc13db93f8fb379f2c380efd10de7040cfa9107416366566c584eac769e6721b645fcb489b9dc0936cdbfa8d5dc72bea4cc8d2bf604748c9f98a23f33c22b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6f9da8c4b4d199dbaafef53e9fdb69bd185fc21d55ec61bd128ebca25c7e3b02e5df21f6dcc88d18789b5c59d75188f091b001008aba888ae1a3dda5e697f404	1621010389000000	1621615189000000	1684687189000000	1779295189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	23
\\x320c1f962c3c6062d208a628ac11e64053585313db399e3c4730ab11543c9b0351187a5d05f744b8355b5cf751753bbc671f284d903456f458456e6be564be71	\\x00800003e90fde2977a778a5700867cb031cae46ba308fb3a04ee0a9149ec920c49386b92dab06ea6d2bcd83b40083417ad7291646e97454d5c508f0d7e4358b04a8c28b045e4d5d780026383848e8d0dce2381ad90f992f03e6a8403b81ea959d647a726801a4d7118458f5708dd46cd0e09fb9e769eaddb645c67d0c4d88127aa5a4c3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3ebb2295a5b67f6b227ab70bc9649b183a7964ecba2cae44d87ae6d440654b517d013a1b09d999e921dcfdee97b07140e98509f395a1a58232a95443bdb55b01	1616778889000000	1617383689000000	1680455689000000	1775063689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	24
\\x3630fa3c6d864b00056007fea2b7e7564adf0cc67bc6f0ee098b447049e0b85c0f1926fec4cfb2fd45f0f430e197d60eac162bc4abc4af7af0267aeb06872a7c	\\x00800003c8f94e8911b712fb84f8eaa7670773af353cfb7b0a14902f53f0b93858227d2d5403e72fb214cf34b8797f3421a9d0bae3af5586683e41721c688587e0a55e0d6d8a6b96a12fd5a651a80a297f670d5eddca6a22366d0e08b61d628973e536dea222666b433b53b6aac1ba6448a40e198c3c005737183ddbeb383933cb45d897010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xac7e578649831f25563c3891abf5f5dc4b43ee7580c7985ece2d0a83b6cf372f8d93d3a2a26550ef824301b83c6fa254bf50de9648550ca8ac728ab99559240b	1616174389000000	1616779189000000	1679851189000000	1774459189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	25
\\x360086b67c8edd32dc8d8ecff95ae43a09363e0f9e9230d21616c6c4a3077f12e2c5ce4ed8a74e66915f28d58d7e8ec600733c89add214f69ef2842fe8d5f379	\\x00800003c08b1712256356f358fed101291d89219414003ffab5b060e8e1452e510520b74a443cb9c48845a091d4924dee3c9e7be55f8c387b2df8ad22e2251c195f7e0aa8534ccb7752b0ffa3039a8002fde4da8e9bf24d65ef77d82ad9e8bf634180f0775482f5f0e8a2daccf78669970af25b46ec96053c9d76fc413eff73eb865f75010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd51dbe2e89894d2093f702f7a4b95c741767b62dcdadd596513b960112dfbda17ef9ef2b01265043032513daff33946044c05606048ab0a869851f69fac31100	1633704889000000	1634309689000000	1697381689000000	1791989689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	26
\\x37c0740731bcbf99ab5b1f6f4069990e4c5a7e6aa50a42c73b725603dbbd7b332b346cd886e42ea3d8fdc6573f12cc94343de6d1dd2b8a87ede7f53a29097dc3	\\x00800003b4695e0665c5285d178400e6de2a10341317f9e0ab1fc99bc956d5e5fdb9e7facdda929e41e949278208b58509a478778cda9ce8c8af668757b6a3d1d02754077310813c2da8b73a5d6496a09e0538609ecfe7107a8bda1d943b644da4a24522011770282358256eaa4eb281788cafca9d48376930c2b5dcdca4aa6595ed1e41010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x56c09a6791168e8556ff48cccdf52dc820b90f4dfd8d04fc8827c5fbb643e6bbe79b75d2c71964ee80272971dd9566e2ce400bfea766308e16314df5e6c8910b	1617383389000000	1617988189000000	1681060189000000	1775668189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	27
\\x3bc4276f83d1b63f5d392a39ec5d356e65650a1b54d4602f92ee1b0747a92118953c99b116d64959c3f6929139eaea4a42cdb97519746ec268634e2505c6ff7b	\\x00800003cbc46ecb3636ce63bdcfb215c8f41f0b75bd2ed810f9e7e647c89088a1479bf5293b39bd5a7a8db292ad5ca775482418fc7a52f6dcc4fedee56ff9f1ef0d9dc711635992cb3c003b646a4d888993c856783cc066abffbedee61917dbf90953915a6988ee8884d4023a89541c41abc53089ffd3d7b4f2ddb38ff14f4441d4d499010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5b0acb13db3f256142d6ccd497ef99fa6723e1a794fd9acd90b88b004b67f9997bacf5bc0604b70e58abb203906284dc75104900b1334ea0acdc35d88919750c	1633100389000000	1633705189000000	1696777189000000	1791385189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	28
\\x3b14711a40b36094e76bd6c8e6352991f783bde655984dcf748fafebc0d57cad1edc631dda74e0faf6d414ed5599163cf660da72c41c1cfd1c128be7baa881d9	\\x00800003a124dea6add06d81c0e52047b9f09f24cabde14dcfc6adba9d4f1bc48005864baee0e63abd8af0560cbfb207cd7c8576bfe2cf084cd41233fbcd32cf0cc0780c556d3dcddcf3d2f56de8f4d6e8158fdd75e3019f16d521d0aeb81ddf4a49809924b3d24b1c11ffc7f1453d9e00a08244b5523c7a5ee6d47686071b79fc9b3e67010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3f708a883e1153f39d9fcc1080c369ab418e4c092c6aa2a819a29b5510da1769ad009fb32009dae31d809a0b06944c1ec7c40f076e570078aa432d56c87ad600	1612547389000000	1613152189000000	1676224189000000	1770832189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	29
\\x4228186ac7ca592a86467df5208ee898631957d7b05024b37f160b5e13b691e606f374997253765779497221e4d023809317351d1dd7a076d4672461894abd90	\\x00800003c67cb116ad9a725ff16083ced7832a8ffb4693544e19ba0e0cbda9c943793ad5739884d84fca586e0ae4ae736b2b1b7edc366d8bb4ce4c6522951fa466d1615dfb0a21320fcb67b8d891202db15bd8fd3bb1190d9b02bcd476b55fa6fa0e9f514f58234b0f88f0790fb5d4b544c0e77eafe96268448bd21e661bf593bc9d61f5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xfb375b2d97591e1286bcc7a5ed2741b0e18013932ef724ef005d337a66ec8c36744b3c93df36557684bfa7a3eddbaa390c0a4ab2c003543f32e1e7a950b7fb08	1616174389000000	1616779189000000	1679851189000000	1774459189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	30
\\x46f44a47cf04e01c1ceee1a4eecbc48866dfbac05876d89baac68b15c058d836348f0dec8dedc99c25c97205d6dbadf5a995808fe303ae4b6855b1b7af5efbc5	\\x00800003be3cd580268295e34dbcdc80e02f8db973ed9c979f68e8b1b861c092596217c572c65fa81a94fa8dd2cf51f006259376c90097ba4dda6dec2ef104270b1a4e9004e2cbed7032e1b987a9894cbb926347b0605060294e43767b003df797819e1ab9691c3646091c4f86658e526d461cbfba0eadd67a42cf30b5561bb63d56afe3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3fee122d48e67e5dd1aaeeb4d3d9eaa23fd604114ed4d1f086f69719fb1641bd17033f65167c39040a065664c0579d3513b29cc6b502016a74e4dce2e5f8510c	1637936389000000	1638541189000000	1701613189000000	1796221189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	31
\\x4800e6b2a41ec53ca5b9144aad23d79c9ce21573104531e70f0e60440815ea050d7a308767cf2623863ee23fa69798cc934c1fea2bcee7bf023af687deccbc07	\\x00800003a45950fd7694508cf2f2989c4a38c3a7b3c12b239b57825b64caf21bbf811ac0cd33426096d6c4e688b86c3237ac158fd829056864214d2db8d3cb42150321e3a26cd3f8bf597e7ccb33cb3c290d4df098f7e26e5fb0897081749de94d34ff8aa44a393e3612b87601e17b8032fe16ac734ef22164d1765c131682b9f1a6c0d5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x89e293c22907eb88019131103da6cbe406a979eaf48c3b73fa1601522c83e52fa2bad2d08a90decc20534323fcc04826d767a00d1df3b8798fc1e2f5aed77703	1622219389000000	1622824189000000	1685896189000000	1780504189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	32
\\x4938deb1cf7a24dfc9c69b825457bb208167d13eed243e1158a90d7735b32d31fe03675c708ab4e78da2bea728c88470da8edd45a602822666cdf7e06d316432	\\x00800003a02ed602a1ee9da8a719c81c5d6dc5daf0548e47f7a49f6df2052dc167bf0c209b302b97622229be26b6fb1114c91950c255ca004f2c8b8b2877434fac10280ec35bf8ad803386f102ef125d5e8a2868bdb6df02ee85e56cfb55c3bbf99f8830659bf84432199b9efb99953bb09dbdc9014062ec601222d798332ff28fe2eb05010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x02965e950b92f47095a12703dab4ccda9cf2bb3be2937fbbd508bc8e5d4e0a0943b218ed50b380f3316d9e7843f57739763774614329b56c2ee7c736b16fc200	1624637389000000	1625242189000000	1688314189000000	1782922189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	33
\\x4a5870acafac4c844d0e3bb402cc41473e8063484e4588e2462a18f266c91b760856b39600b270c94b5fe1a997fa82f9f43a57aaaa8ea9b43a3220bacc902363	\\x00800003d823d7f0680c1c70946d02b65c672bd84bd7b39e93666cc0deae7843ccfcf2a9e86d0c3280cb56973736dc4a3e7181759c70a4b5a1ab7188a94159cd636848d1eabab344888aef30df4e89b4cafd016d7eee14f9a6423870403acf2ac3f33f7ab59d621c57191516966efc22b445aecbb2b2b4701d906c686420d080b89e3a3b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe547119a8321d8d7e4f4e66f7736c6177495c162c47f85d5209ea6edaa9e85130a9cdf09657dec0802d83e5fe50784c73061bddc50204d9742bd2be7c3da000f	1612547389000000	1613152189000000	1676224189000000	1770832189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	34
\\x54fcaf1aab8316ecdb9fc755acc6718296bdae8c69b53ff96df4bb3e36205d391d97ac632f3e3225256b5d82ea764b95bc9fd63bfb0f08a7e74ce444cc160671	\\x00800003c17b5cdb2d6aa6327701804fb5431261a082a0dd8a4d35828f0e4204bb5755f694e6f3f04e3f65c41888c05bb4d276eff956a9d13f8cb1af018a3f23a3aacdd86f2ed695f576fb5fd3a5f507fc2fadb3106e469684cde7155d231a5c49be4db23d64d559712183099d81a895d139526063233b4175530693b0022286ced5ea7f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x49030e019a06a82d6206267c226cf9c0906dba2f92465d8abb17205da31bb0b92880f54d728892c7abaeb3bc7616c12a68096c4a51b659471b222bf331b3f50b	1621614889000000	1622219689000000	1685291689000000	1779899689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	35
\\x58dce90f9f9e9fb2c2a1bba890a7ed5462ee0f55e4dcf754711190dfd58aa5e707d4fe19b7d18bf00766fc1ef89ff5fc15fe9751db65aa9342cb210769a5c5ed	\\x00800003bf5427833e92127ca7dbb3b126a37f45f8c4fe8c98f2fcc227b4b99cdb5bf8d4d03c5538705464159048a88b52c125b4ecb5752aa3efbeabf98c12368c219923a234ec170c833ecf5c73a062a3c0b74f3355574ee32021acfce07eebc24845ca836efee889b9e3da3dd259f76a8c79eac236502238b3c33965cc17ff6b6136bf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf8d99407d6884ae899f3e67a95bf64610d4bbfa3a9de5b14300f6a2ad4bdff1cab91b38cc90e77b93fa31c1f8ddc917e55fc43f7f628b52dab7fcc79b752ed01	1621614889000000	1622219689000000	1685291689000000	1779899689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x5928bf12f8cbd03aa1f0977ad7e02eca66515a94b46fdfa4e7bd095327b634999d843fd7f83831c90262032340a69292658bce1177163d4a8fd7a613dedb2a86	\\x00800003bb5385f7cce4c28cad1dad7008e902c805f7f652325ac302b2058290571ee75a90cb406da524def7a3202285f1fc0d86b542826bf8f0b2e6cd64332beab71ea13aa9d1119347bd4dab39709e60a17fe1854a3d556f4a0cefa6b6adece2a3b9684806832040d824bddc55cc0bc8d481ae57caddfe62e183d35369b2c0d3a4628d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x886f2332979a4bd6db3cfe7137b8534eba123c0e3cb38f1916901c9ea25e439f67157f0b1fdd63aaf3706357a7079b012cb4bb811192990b1dacc828bc2a1806	1620405889000000	1621010689000000	1684082689000000	1778690689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	37
\\x5ffc7983fd87e8a1930c42247750f3a71151b0011f8ad11d1562b1c810cdaab8c22d9777845210770272967443299565fb13ba5b0aedd758e0a065b49fd2bec1	\\x00800003cd526d68b0b647a1285f24069b64648ecbf8c669e2c618cdbe9167506d5da2cf5ed9f005c15da3bc27e92aac4d79610be42bb81cf4ede2e476a86f73595c8b5a15c4eab5e524a5ae81286f29bc0ff5a8689709ce59fdb6b59a76978eeb76d3a0f12ba81b1fd502ca040b213cf8c360a24014a5e1b9efe20970be01939e9cfa09010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x77cbfaab88061d8c1c41f6b28554402340d3b8964ad76edccb4f83253d1cccb8acd4576944ef88f72116a9ed1456679445484846dd3e900452735e4290245b01	1626450889000000	1627055689000000	1690127689000000	1784735689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	38
\\x60705e274fd16896f342267ba8153daf3c7b6ea19f86775bfab8f47624e9b5d5264fc15e19073465bd609982498759c33120cae36b843edc352dd6ecea944ba8	\\x00800003a84b594859e566bcce08686321801084cbd4177e75a4205ae4e601ec623a98c866b2594fea59b524f3dc3f7a24c7d294c6ab1706c9ec1834496709aa13221ad754f3a7afbb7fa90550664efa9e6e9d8ed42035d90a77dffadac321c32d2a99ea167c94d8251536fe8380e492ac5395304dba6f14e09c35a1676db3a15e6a3053010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xef8ec218e31776607cca671c682140d5f02cb6f666f38aba19d490e8fa5e1986b939b8a392996947145b0885602746ac1e875b83c7c8f1701452f78e1e346901	1630077889000000	1630682689000000	1693754689000000	1788362689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	39
\\x6278e1033dd56061b3e36463fc76ba6cbe98b3efb11e8fe69d3d049c118932ca28bcea8b930948d44af94221eb9e3562aef9a9fc3e1bca523a8ca854ec644750	\\x00800003e11a7a604c4591c695d2d65c95cdbdd4f1e85a12b0a3e4aee7cd1836c6ff302f5d322469df8076951f525350522dc0b7fe68c07f3f5b18a9d4b5ede841e9d5a642208c31bb58a2dc95683c665a45ba248b1e8043f4e144901160a5d02796323c4f360d37ee1654ad2c9af395af12177baf7cf6ed86af167eeb868847b9bf35f1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x439c77d700e57ce790fb79a9cfaec4ef919c74216b5522562e74c01a4af10cf4bcaf5258019b8aa753382c1b6a1270a588202550066a74b5c4751f910d726d0a	1632495889000000	1633100689000000	1696172689000000	1790780689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x667482fe503c702288e6c864eabfb81a6b65e7f953e6e1680989bbe92e9226aa17f461980e3d9935488cc534cb8a4b794968e7a896cc07ad8438041c592bdc17	\\x008000039d58d3aea9c2e5060b43e23757f9a682224ed90f8c06f34de872b5546e5764d4e3f3e622e78969625bff026f14fe4bf7dd1dee850469de8830c51d8240c8283421a2d41cb6bd84587f99e6933e7cb70571ce602e397331021f2f65e93e33d65ec2b106ba3a3e51fab7dc507463a9ba1a1f6a708b28505c074f605efb23558d09010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x989376e854a2372c50d70e3c98bd43d6d68306eb02ff223ad71f66d0a06ebb25b32c1fadc70e41812953df69fea46eae78e10ea4cb3448efb590a5126f608404	1621010389000000	1621615189000000	1684687189000000	1779295189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x66e060d4e49b9a79f1033f3468f5b18ded588e3f3abdf9fff0239e9a9a216d92ed3d31867b70a4bc2f13d28216de1395977c39a61ddc9857a07628fe3e65198f	\\x00800003cb07172e913451097ff843af3c7e2408b88b406c352c5074292cd22a6e6b3ea75761224d483c16aff3db9046980fe8515a62e312991656abc4d479b73c86049a5f635e0b6377a130d2cf7b5e932a92dd6902ddb3c4cfbb9ade536ce46d77d7b844ff12d24c87e91cfc324ebbf35cc4ad2fff0f52bf2babc6dcdb9392c103b4eb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x40f130735dfe01340b8182cc777bfdeca34f89f44387b42ebd4bde51e8ac78ad4c72a7da5b8f309ff82294ceb73ea12ea519730d64189d758d5726590f2a170b	1638540889000000	1639145689000000	1702217689000000	1796825689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x6980ba891f52dd415e45a3b41517126bbe090ecd65567041f4551886ca1873a19a20ba98ecb1f02cd816665248673b8014e9408bec3535018402d7f44ef00c5a	\\x00800003c474baa3f630c8c215940adadee411eab262b2d96df2deb5af1028092b9f1a640cd679bf1dcae3223e6c0a19cc06951a29a63bfd0d585db2aa71dc6cbb06d860cbd792ce5e1196c764deaca65800b33fa5934ae8a02d437ff4d8d48599fcf61f46244e317337799c4877b84ae32fa0063e92d23b799e1ddf8ed61f858d7c7b67010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6bfd2783e5bea462d76625de4585ffa10a38c09e0f4b2c7cd89032ac77a8c0f512ad2800b51b4e1ee13b1f2dd2fd9404e9e6a0b687e508574ea2842acdf5720e	1623428389000000	1624033189000000	1687105189000000	1781713189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	43
\\x6d68fbe85872269fa867e67a914630977eb1fe21fdedf48ecdcdc7692ef49e6b9c22438e905ebe759df1ae8259a08b1d10ce2b1273fb1a04ae4c64d2fe282f28	\\x00800003984296e0a22d8af51d86a50ab1fa264396380f72f90ec7cbb70829c794b47413d0a2f11dec6b4640ee79824629155b5d81c463e02e3063c117177c909ee9a53e0cbc489d75687ab3e2e4b934e815b74c4d886a57c8dd8271edab498ce29e50e51231262ab02d59baecdd13ead4eb03e52edd8a058bf43c0a43b38d9d0d1b1f19010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5ea98958c8140f4af4d10f8a5f9e1e1e1745f3c3c06f168400706669c69d0d0a906e6c6856211fec623b7682a3802670456ad46bc1718d0b9b371376b83e2707	1622823889000000	1623428689000000	1686500689000000	1781108689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	44
\\x6f60b65ea7416b2e9d5ba3b518ca9b692b74e8f225138a9df5053b7b7dd2cae772a794fc4352e13108adc7d35c01f8a8c7f01ba98802912f2b581b365cbb32ca	\\x00800003b35c49dd6909b2be315f5508605b5acf9ba0df796aae42ac5065655a6e8095022eabb31bc7b5d72ed47223a5f0fffdd8dcfa492eee79c3f1a5e147a74f9d1e53038dbaaaaffd0e7924fc57bea044c5c0c9f5a21814b0a1fdea6dcacad66a6b07f50c0d1efd55b45df2b4ba5f8ebacb7d69d894682b75dd52368a052fcc11bf33010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7c21bc8e68e553a3e55ed3db95cd61087c829d36542c3cec18a075cbd690e6a27f8debc97266c9456aec13b4babe1340ec469853fba2407f3d7b5b5dd8db0f00	1621010389000000	1621615189000000	1684687189000000	1779295189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	45
\\x70307b5642372e54e45638fee74f33696c98cac23a39f40e082087c57b49d9f9832fa865e5c882bf806b6a7510babe28a21374961d21bb7a7ddcdbf2eb3f90a7	\\x00800003c1af828ffe73ab84d84d54cefde42f38b19fb223a93b00c3094457c4b173ba42cda94a7ab050c8afb037590f7211297d2f9d739fa481f90d80ed3b64bab3f671f112840c0643b21bc3864876f3c2d3b7d283367c1caed4610e3e70e0d5f6625cafe51432356ba06d9912844fb3deb8fe03fef20792c3de189fe01e5d6703220d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb216ecb98d65aeccdcf5055d2a05535d8dda6fd0e3d7c46601ea1b8aaee54aa0f6af47eba9d7362883f16ad54ddfd630f974855e9e57be2c37f8666cd207760b	1637331889000000	1637936689000000	1701008689000000	1795616689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	46
\\x70bcf78958b0dc4314a229e98c6ad8aa2bfac4c875087504e3d3ce62baa3ee55b7bf0d00da62cf31659f89d2425a369d03fdb0cc105eec2d82a050e8640542c6	\\x00800003cbe2362a281c64378ad44f6fc16518884e1f960a5bc99f54e94566c6f02b5f1c16a5c414730dd1ba619f6d60e6a247abe46c14e7633f0fd31e4ae707f0aef8e4a33cfcf87bff4df51ca89e91d0c789f9c5604698c44fb89f5420e7b7b86a97354f5e5ec924b0725f240ead367d8a7cff60f825eac4532f3f00a4919088abe4ed010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3fa4c4c0447b95e1c3cc7a7d82a13a2e3e174c8e4872ac30a4502e1826dfe5bd9127b94938bf1a36a9aa2d59b9aab40b8350e2e99774ab2fb6cede6c53cf6500	1635518389000000	1636123189000000	1699195189000000	1793803189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	47
\\x7620f69e14afa4807edab0956322214da0eb279f85435393ed364e3b0cf94f98004d4c02ba6a1e37198d4c44a2b7a9164cc13f170e9b1680dbdecd568eaea5b2	\\x00800003aedafab0e6e05b3ae481ebc6adf362096fe7ea706377c86d6ad52985b9f0b7f7f91178e0be1825234c1aacfbb4d497c204552a992c14f192c49299bee0f3d04f467adc40a58f7b6fe6069c5cc520b5359c749ca9bcfe5c166b50a5bdb927f6fa9aeaec2d4dfeb8d2025861da35da7c0af56e946586f2e8c2431bbb34f195132b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6f4b20684864725601663567e056893d14714dd41f516c1c0be63ad25c8e4e86cb8d796ed777afd42fe4aad5ed2544747cc4b46daf8fe5e66522e835ae891809	1633704889000000	1634309689000000	1697381689000000	1791989689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	48
\\x7850f2c45985de38d5022bd1811d13af88cc9ec8a887a792b2f974be9cc04da63dcfa8388dedd692a388f47f9d6ebb1c7257596c4fe527752e08b043f22e5422	\\x00800003bccd06136e798fafea5e0085a59b2d373cb93f0c50fa6b168b9dff230b4887233d2a5b1959b3f83b6089aaf34f8f29ba28aa87642d681d5a3102952625a6048d782fe2bb74b2107b7beba2d199d776d2f922c46ce5b55e982c24affe28ada1d456dfe012992f33908a08721f9a8a14ea82962a3b00d2b5aa6bc73caef1abe4f9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf64ee6a33ad28806ef231fecc5044d16c2d1c687d9e48b0621dc69b732979c5abb9417c65270decc49e8956613cff3a5f6ea4a6e7dad4a1ff42b49197772450c	1616174389000000	1616779189000000	1679851189000000	1774459189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	49
\\x818c12ef6fea379a9cee3d9ae4326108699b265f0be0b7133cf3efac08a6a2bc411b3e7438397dd7354475bd3b305d4a9ecd0886f6e78022a769ed5ab6c537be	\\x00800003cfddc2a31316575b46dad521d0ba27f8b5f32e433abdaa3e582338dccd4193dba20e5ac3fbdf76621ba8dff7bf04ce3f2710f9e8ae01dda8f54757650c36b67f50cdb8d7b1d97d6d7a637d5dbba185ebd793933c0359341609ba32c8d7382e8cfec6bfa7b14b33c9efd2caafabe883d6322784fcfb59d1b0a2da3457cec7fd5d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc33e86c5241330aa3d2d96f605f3a0961d058e65ce3dae66dc604ed031db54c0c70a69fd7c81a6d998662a3413f6eb3be546b7d6a29f4ee6c0efabe483c6790a	1634309389000000	1634914189000000	1697986189000000	1792594189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	50
\\x82d0d7c6742418429fe2f98f0aff1b7e5ec33e15a48e570112e3ee05a5e09786d0842b9a54859fb05d0fc5bd833f00fed2a4d32d3a3d121d2fb21a3477131699	\\x00800003bcb0db70217e3b88550b529ee3118dfb79a8b972309fe3fb57bafc5e65a714cea7ecb13a8792ce17b48e9ab422ff706af9d760bc6c3e3264029d1da8f23602e4371540f929bc97001d034d9d677aa38bfba85a186221c847f814b4f339b86a14e5e5de5f507ac31d8d425d9297710f2a7aa77fe457bcf305f8c9ac9d25ea12bb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc07daa36b5020a2e21cfc04a82d755f73be42b030060c6b215ca698bfa370bfd727ca160dfb0b6a30fbbbd0d7e9534d46884fbd91ba02d600a317ad89a11070c	1619196889000000	1619801689000000	1682873689000000	1777481689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	51
\\x8400fe97c4e47897162f86bfb37afda6d67b053537e6f95e3139aa11990ac638e20a41b6cec2c8b8ec3de63e3005b21149c57576c6d30cd05010e6a56684d901	\\x00800003ddbdc754ba30ecfffcfc6dd30a72a3bbce8413ef4f14dffb8c6fee9f086fd86dcafc78a94ec6905068b6b2d830b67cdec1116b1b3a7ba06848ec4f58af51bd2523f8381007f1ee4d7735115456b9833dfe8b66feb7872f2c4fd3861d88de587fed8448f382cb36afe8b0f4a30cca6f5aaeb42a0486314365bebd765258abba5b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x50d7097ae0b878307244f0fb081290ec0c3a90c7d8e0fb37a844ad3e5b30ee73823769bb37062696fa79932cbb536521fea97c06f05df5f05800be69c494630c	1620405889000000	1621010689000000	1684082689000000	1778690689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	52
\\x84a07be55c4012cca696ccdead3ea6a975f7568555286707faac8a193f966a737002789990fdbff1bbeaa5a622bf00545441497b2820879d97d28b07e50cedb8	\\x00800003abf6e57af0e612183196475bb51843d95a61288ba0a61481fb1a79489c2ec5869f5aeddfee80b6389c5470a19fb0367d7fd1548866c222bca522ce4c44fa25addce3e89e96b009f15499bfe47b3515df90603b1893b26f9176375893082e5b41a24b5acce953a9f23185af36df33b03bfe797b21ad0bbf26a2165e5df6bd74d3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa242f48b95a093f19604828567022fb7ba1f5a582ce77dcb9b0a8835eae301b4a78103d889d38b0ab70d6d3be1d8afbc4d81e55a290ebb89b891af68832b1508	1637331889000000	1637936689000000	1701008689000000	1795616689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	53
\\x86fcba3831c8eca1616294c693e27f2dccb8ccabafd08dccdaba819eb39d502da54a13000e2fc8873ef2226d2cfdaa081e34483812f38015c742fe8a635961dd	\\x00800003a08333fd3e5f96cda9b5af4d1a8c6fdc07a7c34d13fe1c3a98bcae65b03602526afbe4d219f56f437541bf6a8c1a689b3a39c9fbdf681dc351038bd8cc693e4876ea0905a2442cbdca5bf738e1bf7dfabbb7dd7827062cd5870085e7edfb3dcf911bf8807b6335e7db8e1c3461e1aa98e1858c17d22560d5c1168bed0d9c6995010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5746eda5e486658a20271b3f23331de79fc7f7e40f3c008d4a51e75ba69b7d44456f79d7b97344fadd87b1e6015d0c6dff562aa12f6b0a69ce2f816a3ba2010a	1635518389000000	1636123189000000	1699195189000000	1793803189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	54
\\x879c75dbc8182a70107d3a5eb67c2b01fa3b1386bb556bb54979f424e94cf973a6efb928bdb610519bb124fa5fce088e0f2142f0f42c2ce381d916eca2891797	\\x00800003c2f57675e4b5226169ba8cdfcdffa0cdfceab5a12655a36ee2f74d0222133cb1789dc75bca573704ff34db0ba9a506d29b9f2ba54ddd32c0b5922eb0537f1c625849e9102872af892c2281cf55a618e4e1723f94fc256a4e3a2aade239a0cd7eba7807b9cc32a7299d4b631ba93d480929725f91e41012be505e0198e4953229010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe8a06d3675a5f8826fa1372dfcafec8538e4720c9ef17d3f15a76984d97fc89b627c4f67154af6fa0ef468d7cc6b486f07e38411819f860935076f180aacbb08	1636122889000000	1636727689000000	1699799689000000	1794407689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	55
\\x88e06a75f81dd988c6d065794b20dc39189284566ac953854ddd5602b35b942e3975defb31493a3eff5f80ee4d8cf63de87203d19cad83b18187af0a5d285037	\\x00800003c97128fbb8eef8cc8de180b5df9f26bc343a52be291f52c1f110b411fca370afe48d278f10302b3a5c6d4a7f6a6e6e187b1abf7be46f32a2788d400b3944d4d8a12c2653b748121687056fe6afca636a5e46997cc43cf9ec485fd1f247f3f1157b6f7d6cbea60006b7c7b237003211ebb9516e0870cf0d3b3a6201927ce8b719010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf44ef332470a191294db6aa047f2438ebe0624198b14fb424a503258d1fb1e3aab48d68d2f678bebb89db8b938aab0d0b92b4b4077788f1f224b8459de1fe30c	1628264389000000	1628869189000000	1691941189000000	1786549189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	56
\\x89d0d152b52440527ebc5a79d53aecc4e9d960441449df62861f3b06b9ec3854a3a2c41115f69ff7cc075ad4ce53a8655658782239e6371cf45b5e89611ed0f9	\\x00800003d20f771cf2cf329afb72816b71cdbcc9a7c27925a7d685a0252a4ecee354bf5309d81e4c7aab820c9132d3a8c312cb42563d133f1b63fc1cd17856a223d8f6bfb405527cb3fa78e3c2b2d50e05a263dc0fb4a81904f50435a836f508dfc756cb346b9eb39d2956f47a004279d3e7b0a336a5c4d452a85dc24886702fb532443f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb384cb9e72546afeabd573ba26cb990457c09af013385d4835b7aef46e0a336f7794bf4d22cd08a0adaf7d6c025e292c64100897dbe7b50f88ecbb6429b7b609	1618592389000000	1619197189000000	1682269189000000	1776877189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	57
\\x8a68327c81438367100af920d374f4cc4a1afc97d0aa5041263ea9a7b80469912942406c1acff1d5c39dbca3c9ec8eaa6a0d9d73f85991a2bc608d0dd8215708	\\x00800003b4310d2fb0f5d505965d7bd089f632f678042d8fc25b16840b7d696021eee988ecf6225b4fe548efb3b2b07beb0351d35da05d84b2367033c2bc26c50c366cbec950dac8385ad9c52fb251c2955daed7ae26d08571c14585eaf42000f4b49e555007adcdd5fdc8e89fceeea1df02e39d22784b8418b01e8b4fffee3cfd511ded010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9c23cf5ed6db1128b1e1cd2f9d28be2dd22196a8589abe7ecd9930c1d636bab7151b503abb08db7292f8ea4486e84484aa76a1cbd8dbbdf97c76eefaab6d390c	1637331889000000	1637936689000000	1701008689000000	1795616689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	58
\\x8ea0d1636a612985f50e800b006a57b8f8b1ad046d790cac0a84f28324f952e3db920d88322113ce97587590b723658aec18c21c2e8a04038ca383f6ad1e94f9	\\x00800003c3cbc39c9410cf08ef6f8a8e11261806604279b1f6a465af601fbc10ff6c2e17d7df69013ab7e9b1ab5891eed5bc43ea5fc0260721a18b4716fabddb35ba2cbb77f5c032c1b09fbe7f041bd419f299fd7200d8622dfde680c6baeea4857859b24a9e6c20c0bea6130687828aa0698a914790d2c03623dee9e0e78ec3ba54ab25010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8bc38f846f3d96652ba753b437b6338357208920fca78a65b37b4beb4cf5d3649de7a9018c1bf1fcd2425ef0e3efc002ae91f246306e12b3e334f2a9de8cb407	1633704889000000	1634309689000000	1697381689000000	1791989689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	59
\\x90d47b02284540549c2b639da319fd747b2f780dd786fa68186b137e85b5cade001ae1103b29d94aec1b12e2ac9ce9076546f12f9abf9ab684ffddab6f4bf4cd	\\x00800003fb89ed06d55a77c9ebddbc1a4d839888f11f6b86fb443995ac786888fae05d57d528e4ccbceb65639f8373c1e01f39dbd553f4561aac8730d7e63718280ecd348028587eb3fd1ae07b33ec6b827ea29abd12e630eb136ce6b4a1a227e9abc65743d674e433c2959d0300d59ce770e60c442a229ffb2d9e7d05f7044f07abc5b3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8d8b5dad7485091807bb5916d62bf0d5ad1fb51aa5df8133a521c8ad956bb47012990ffb95e2ff65da466d832655db74aa662638b4e4feeaa08bb446b139c101	1627055389000000	1627660189000000	1690732189000000	1785340189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	60
\\x915487f8c1ef08b173d1b86d67d770e8f1ebcb919b62e0d0e4aa6f23cb67e330edc397bb56a1b6085c2fbabbb6f2b35472017ae2b1649dd0468d11bf3b003c52	\\x00800003b7d2eb0d0832b07e9099c0102ce2782428e61059467089e1a796af98d5f6a86e7a6b81894b4efd0e6e3ffc4bb488d7566e7ba11fad38795c6154ccae56120e1bef3b44be8041580caf40a278ec86f33609a45f45d2620b41788ba68912aeb79ce89a344d59b8ee461fbb5cd33209d954b445430faab27add8ec3a121de263347010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x20081cdc2517551d4bc0196afcaed8b4dbc67235908304bf2f51365f8ef83e0dcfa76a459363876c24b88ff6e1aa6e13fe2d3268b3ae25552f87f5daf86c0b0d	1614965389000000	1615570189000000	1678642189000000	1773250189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	61
\\x92f847fae5d15c6774e35abac0c7c676abc2c9b4ea20c28eac88d706c403114c6deb81eb4e158e773c4eb739b9bd548bff57d63af71e22e8547fe06a4ce18c52	\\x00800003d33f859c9d4e867cb2abb86d619a5848df1305d785706f62cbaddc89de3458723f08c9c7bb6e367f81996938e007d4f38b2b947796214a988f35a5e3704ea495226add3b1122d025e162377a57e28d0cbf0ccceaad24d588f9542ae6a25f8dc7e8717719afe8dfc8ad73847214c187f78b585c3f22e5eb01bb54eab611674131010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7b59fabd74c1466affc26eeb1d6226825bb4fcf82604c7bcec9ccbb6f0b83eb0d92b8bc452730d70734eda717c02d5686e6a815279e2b796d5c8d604a2ed3300	1639749889000000	1640354689000000	1703426689000000	1798034689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	62
\\x984000dd4e1da58b313c2b629390b8da7d0c0e0b25b567a5a2da296b8e71292a196e47e665a7f3425fd94a1f93b5b7aefba134ba137a01388bb57d6d05094beb	\\x00800003b82568c11ac38b8ca7a7cc5110d56e0b7b5f6e53c369dfa523081365d7170b9434e53802b1836159fb5e79dbafc0d855ac7256cbdf364a11272ac0d68589ddd8fbe1e4f5d4cc453df9edb9481fd93ebafc5a1ef7c8ec7fe1cdf0d7a8e6ee2a105571f758c56c3f791bd1793561d670331e4ff8a422a20b632010843fdbf5b015010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xadf7758b3ef46c46d7674750da4a6df1b6777aa15c3d21e2b6e5b12d99fec67ea5b79e411e9170511d94186bcfd5f75d344ec68a9286447de663f8e8efc41002	1610733889000000	1611338689000000	1674410689000000	1769018689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	63
\\x9e2c07fb62b9ef3aef8ddc8ee7356f8ca7d2d72422fa7f7963c684dee24776d83bf6572c0d14f2c537ed2991102b866bbf66542c7618ffbba8610f5e28259180	\\x00800003b2327637232e5e0d4fa912952ebba12af9810860c53c4fe97e26e02efb9e5eea0cc5be3db9e9afef4e71f3802d9abf77c69cda5234b26c4e0c9ceaca95de2e84cd3e7fbd09c302ee0e69d9f172a5b02a434d5ce4400c7f610335ec776ab0de81791fc4027bad37cd611735cea6b9e33ceb21b069ff7b419039c35dc70ead79c7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6d38f8297c373e0ef1e508fef626b1181267e5266bbd963f138e0058b24b9bdc69f765ba02bc1c620e238e76de11953a213eaeb10eb0cafb24609ed3ff22e10c	1630682389000000	1631287189000000	1694359189000000	1788967189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	64
\\xa0389e0f23d0f98daeaed424c3798e08ccd59847a1c12965fb15c96cac85e459347f49795b9ef0f9bfb6d1d78dee98c4da8510ff0aae3ded3dceba73b9e27629	\\x00800003d27df2e6e3d615a2584a41bc6fd213fd01787778e27da355601b6689f2e2eacca501b6dd054b079b84a15e2a1693648571ad181fc0c211d85d8b96d28b97570bccbc13792e29936f868689caaa92230fb4eae4fa6cf1c5138aec1dbb015e95e9b6f27d71b20988406d29333a5959e2969123215af942409a02640aac040320d5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4cc5deaeb8689917e0932507fb4c6c22e706b249c29c7f98ee60eb5827ced333fe4ee9f31e14ff982a829df3b313b9853e0b6516cd2f1ad9c82fb37d0ef4720a	1625241889000000	1625846689000000	1688918689000000	1783526689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	65
\\xa2003e434e4cc37861e1389e55c8b587d4fe02b87b57f536f57563bef1f558dfe6b1e6b7fe57e4a38c2ca2ed5f9edbcf3d555a09da3fbd6e4c3354916b19a99a	\\x00800003c076d72b464d07661a94059d7b3287a7e8efccf62fcba44e621e79c2449bdcade36998ddd5e1a17db73ed73aceed33bcc4bacbf9b8199f1639ff6146a49438ebcb1819cd76a09caf7309ee74ccf1841b884ad27bafd1891afbbae868b7647d39074a63df31b009f3c59d1fb573fb237c23976e7d7a826bab2f178c971e8e3e79010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe080609555c01948ed0fc31e343d5552e9d85a603013303f6326268de30cd85fbb14976114af138f02880e058ccef58e6ba74cfae6b1657482e98eb693afc906	1634309389000000	1634914189000000	1697986189000000	1792594189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	66
\\xa32ceae831661d438ed1797d29cc7f2d6a58743d206177ef27c4cbf48296bc0d9b13eb2076d078e9af66f2158aac176964037af84cf7729020d1a055597f1f73	\\x00800003e13dbeb05bfec024ad6949b1d40c60dfbf31820d7aae40379add67afa82d465ec8017afd74cdac39733441f1fcdd585cb1d997d3c67eb2786397f28b9b29b4fdb017550b25735f106ec11dbe001a5cb96110ceacfe1189141b2319e979da578dc7ab7fdc6a47947ed8cf40a2a31f7e65e3f9810954aa023477896f28055bd41f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x398fa55b027b4ceb6fe3c6c6c34423e6682eeba59853032dd92f85b909870f6630385ef4dab6e19ad54fe5331db363ac42049d82954afe35f655ff3881026a05	1640354389000000	1640959189000000	1704031189000000	1798639189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	67
\\xa45073f802b9bec7442ab94d85b22b790c7647a9f4c4a24b20fbfa67691c94bcd9ad045d75f2562eb871c465700bd41da8fe009404027bce100290eaf5bb6257	\\x00800003d4edfa927fc2a1e21d0e4a4babb6158787a62e32290193cef0859ccc52eed82004e205b212b05f0c68a7c8ddb5e6eab8906c68ee348e1b162c6d07eb995f8bf2728130d49fd7fb3de06725ca973b0b1dd906fcc7a998e18fd60ddbd72cc19941096944bced07affde7b957d8f1501376484ae286b25ce675987e66d2f77c2401010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4cfba83f4bcc1298b54be559673b87d783d1b72662f1d5f66e850b316ec6fc9829f8b4543427826b6f6998b6584611bc0dd601396c72e093ba79faa87b63f40d	1611942889000000	1612547689000000	1675619689000000	1770227689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	68
\\xa4709f0e3099ef40c51406ad49548818fed3b15c0db2e21411e60d1c63b8b346238e49f6b38e761ff578e64b44cf9df5652bd1eb3f7190920510f01f8d0e558c	\\x00800003bd81029da15831e61807f4176c2d46372c61cf978cdc9ff10008ed492c3676ffe0e7e5daa0fc67b29a24f55e593c7d2b6222e41f38b59a40006e77bf3630da0a813857f784edda609b87d3ebe13db072ee9d632384b3ee970f08f81dfedefc0b2eb475ddb771d86869d551f58653b7477b3762f0741b9f3f1ad0bc4f420ca835010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x35a4e3f2cede570f862b9342e33fb439990d0108f8bf228414ceb334b084d5b6bc82a06c9251625114d01a30c576b58f565b2c7cbb98baa7dace0044cd83a60c	1613151889000000	1613756689000000	1676828689000000	1771436689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	69
\\xa624a39235560af7967f622f5eed9bf80f1b49305f7d785ca38ac2b4bc07f56146c6d488a9f140a7b34cdd14059049712e176e64f79e2c17e59bc90d4e086e17	\\x00800003a6f3ab431037a30c356a35a6ba8408ed2bfe464c131ec60558afaf340bfac65a6920dc0988012ac0d9768fb491129fa861e74d458fb8bee5ad0d5d329fe2ba08e714762e6c9331534063012845908f578e5792eedcc79c241740ac07c9d1870aa61d45366d65b7774cf7830e30c860a368af076c950ee92b85b7645aba8edc0f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x071045588251055cb93e5b129b65478d0d20e2f092aa6df19b197953d9bb21e0495578c54f1e1dd2d5d5bbeaadabd7794903746b35b522b0379b559f6fe90608	1617987889000000	1618592689000000	1681664689000000	1776272689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	70
\\xa834b881fa9a31e6d17cb54032e98be0fe60b81a26d6048e27e8dbaf53d8fe57116352ee93fe0987b6ed3068270e3eee9c1d2838bc9ed831289de5ea67b29808	\\x00800003e893889530a55d4b69132e728fadf9ededdf97c3d6209474e8eaf82953659ec09f7186be00f53119e178edb2c1f0c8f809cbb504d4f605fb55c85c8df00156d3cdc6dbf9fc3a7c2878de3477edefa038de27b45b116ad74e3ae17251cd17f538dc78ee5d0ea81b5b6a7b1a6c8e01516fc4422af5f05d87910a44c511bd7ee64b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x338f1f0afd4fcdfd9ed11f1f66dc0d9a284703f12c5010881ece994c6caa0be44350597c8450df41c08bbf4a9c26b7c11244b94d5b7bfcc6278a491ead406900	1627659889000000	1628264689000000	1691336689000000	1785944689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	71
\\xab2ce904398d5193404e22aff027fb7c349766b5b8f54f023c587cb5ccf152e8cf2a800649497142f228fa771e756b0a0401d61c3efe564c2491b0cbcc822553	\\x00800003a5cc74a2712d15a268d1d250c9236e499a292932de6ffb06951c69af772a236fc15a0f27b3651fdc3b3c0b0b172cad940c1cc254c29578feae035df3c3d548d8db94c96848936ef923c4b9e5a436af4daef0daa3f2e549db75413de77bd915484cf16751a5ecfab14069d981c5f5cfcf138eaa1e9245b2d96a7ba09cb8453cdf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9bae0f5fcdce3ef6ed627e31e81b1c13e9a7f727e34bef3c6e0f733c9fa8789fd041148122ca6b9d5eb669151e48f9f4b57abd925cde078d11fc4308af0d1005	1616778889000000	1617383689000000	1680455689000000	1775063689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	72
\\xadc4d1d6507d86c8349bd2a6637a878237b5fbd6580a10092f555053e98b8d63c2313e8018a6b1e409b183452f43e80e7390cdb00ce2df580a60d45065d7f9bc	\\x00800003d4537eac357321f0c9a53dd62b5cdd0aafa43474100f2e0ee0b3421b036a6060da5d7bec9515b1d9aa5044ad2b38a0f2c5b986ab51c7f4f55e01cbdb2e143b5b73c2daf54f9ff7377b011d04cabd3a220058f010dfd79401e437cd8dae516fe4ca213e1f18c0deecc32ce7dfff951eb3b02579f5ce63c1afa1cbb868e2decbcf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xaa654b54e645109d78bf2872a5b1dc4b7dc045ba7ebc84fad85b0afe40c1f54dc87e69a6e5057ee658ef86b8a9f059afa6821788e509b605472f4e9f85d2200f	1628868889000000	1629473689000000	1692545689000000	1787153689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	73
\\xaf44ba17e46bcb98aadbc4cbd5a5f812d2a4d84df79d17576e443920cd31c91398f55a8bb639ac775b8983453163eddbedbe5f86bf1f42b3212a4cef01a63b20	\\x00800003a76185c2e8d3b01b7cb5dcef7ab1008552d04e96ab064693f653d2de251db14ca4b8a12fb4152ca15b57dd1fd2283cf8b4d82ec3df132209e2108a5196bc989bf2319f6f61d7bcb84655f334d632b10388b0a1e222c155eb5842eb16a127a98d02ee697ef50db2ddb560c1ff88b8aa5cd2394b962857a7b6a7b9513d6d2e367f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7a3bf5fc4e968bf16c7100368f877d8dcf8a3740511a3596fda68f2bc3d82a218b12f92444e1a652af500abf0732bbb51b3ac14755c34c5e411e7fd17d7bef0a	1621614889000000	1622219689000000	1685291689000000	1779899689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	74
\\xb9f496794e0776584fe8446f97a2a658e0a73a26bd33f1b5261fbae8366de1ef8cd25b26303ed4a0f2c3ea0bd96875e504a8e1438b32175045ef0884e1081415	\\x00800003bb63aa7f759b221bda93ea441c1b46f6ad7d3469dec55b760ef37fe7d31c3f17189f427402a7fe59f7900319d73ccd7727e6d0388d1b94944ff8954d6cbc26c93fc6895c0176c69b1d16880a77a6f3568b27d8cef53d25180930f87fcdde0070b159622d08bd84c5740baf69f5e8f0fcccd762e12a3ce4787f4130f7780501cf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x773e2b5798da7b422abe5924999271c1ca9e50f5968a4b0b2a99453064e3a170aa8da0ed9dc99c4409c70081267d60adff53ddf06e2368bbf9e08173e7acd50f	1620405889000000	1621010689000000	1684082689000000	1778690689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xbd086e31c52e46b67f39e19a3be07d57106f97274fedd53e52bcf6b79145d9f6b90b9342e6034d2b1eef2d54b30041b6b632aba0901d057406658fafceeb5813	\\x00800003bcd7bf28d07a314c6540f7f012661b7558db5d94f26535afc29e3dcc9f24514920695bac48cf74a156e1dc49a6171c20559ad884bf639193c55927f26fce4e72db7aa40e5521b5c9ce11f47a1ae466a13b311868f9c2b49b9fb230fbb17ba36899957146633b883dc9047c560d0a8278bfb6923d208cf8e3ce620c4545a88a0f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc736b3e709234f4f325d28724ea64e687720c7b51b8d05f5a57e41622a59ea67ed03a1d664a723ef07e72df008d3979ae214de91c9842873ccaa2dd9ac73400b	1636727389000000	1637332189000000	1700404189000000	1795012189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	76
\\xbfa035a77095fb44ebdc3239bdcf54e11a59958fa5310942525821bd34b7034cb4cf0659b38f17ab4253265efccacda42853c3debcf8e1413d49ac3f67e1e9b3	\\x00800003b16f969c8c3dab2367540f570bd45bb9428b6515962527c6e8d6f70824a8be28761d6b907656baa694258f3a9b82a46255621be7fc1037f1faca440aaaffe5dadcf20e872863bff30248c4cafcd8243a070d1c391f50eff7ca7d904c8dca84838356e52b7f6fabc086199a589cf5dc92a2e241ae14263e8eb55b706545339ced010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdf37878b86165fca5b406f00b75b0c0b6a86a64756a704c929fbb61a15d0862eef0796299f0e31a743a45b0de4a8451c15a364b909ab2a7f2e6c7767ce29e601	1636727389000000	1637332189000000	1700404189000000	1795012189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	77
\\xc050bc901589068023fcb9687a389f692e74a784080a6db4a0ffe02229c8e09b5d8d0514bc393653c3add592b7e61f295e6b094a499f3af43642ff6aae921f68	\\x00800003b18cf49ae28ffca1f362c7ae3f2e399bffbb5d8cca0172e07b8bb0fba3161d8274be3b1fb6ba6b406e6c2f4bb776d8c145816b0e9c04ea4726cc243755fb14e95363343205c80d9e9d5d9358ffa1361fa35e950f9256e383559f4b8d1b37dbf00259851c005e41c0ba77e7ccdfac6be86b650f037c561b98397c888f8ff34a69010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x02d39d85f4923fa17d474038813b7ac74e4ddaef393e3bbfecf506866aed6150bad2d1faad385603e13d883228f865df35186c42ec5ba483493f2da4c9bc8106	1640354389000000	1640959189000000	1704031189000000	1798639189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	78
\\xc508c7be9de827d1a25a839d187db568ce84a924122b2b7262a2b78bd2c461346ed2a610d1965715884a1bc68c0aeed0fb51b3c6ad258ec15d70814f7799aa62	\\x00800003a12528f6ac539ab1cbc8698b27e57c80807d188a56c6ea98286652f9d12a55100b7d69dea177f55bc1e4e54fada917b29e69d3a425e40687ceb805d078995b965602b95815803eff8988b7d6da2b0b4286bfb5caa37bab46ff36eca18b2e7bbba730b35a1d7a5ae18fa6a92d21f266eeed8a3c1d7501aec79f9ccd24c2f3eb1b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2c141a5f43ded90e41fc266fecf3ffeab433e26055c41935d7a6ece8725cb7c621a66c531201db0764b776bc85e745ed0e61366b98b7ebd8e655b8c07821f50a	1622219389000000	1622824189000000	1685896189000000	1780504189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xc660ce2b4fec7af0f83b3710704747fb10704cf331864521405cd1a52b25988125e9b2566a571a7d2562d6292b7009b72a6a5857f1c95e70d577d89f8cf080a0	\\x00800003fb4c45d06ead7da6ace4bba4bef8e6a3f9ff56ec08689890b892cabacf834846f3310e0dfd0b9d280fe796e4c293a6d396a3e4468e1224a26a401acc1714bcd5a37013eadb3efd4906c64b6a5e17dc926246a5a6b1257644fbc5941b545a349ae37f89c4c4d762f8ea60cf6b757ff325300e3f80e1a1ffee09cba07f18044fb5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb9224ea3cda24000ce5ba07ab3a97a593e2e7260acc79742ccb6a601014e858a1ec334672699bbbef1656e7b26345f0a8c3d180d94ec3487f0bf4eca37ff7501	1637331889000000	1637936689000000	1701008689000000	1795616689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	80
\\xc6c8071a2c1e0d86af20e0f172ab96fbcf32ebd454734df22d4638fb5f32f81f60d817c8b98651f141881c3e14103e5d47361f07c89f2c79c10c13c29d570a8a	\\x00800003cbfc24a2a99c81e73a6905dc20321b7eb51587289d93e9b343b8567d1d8b3f562426ae34504baa846878e9e0758ba82c4b305e1e7b28147af14c2618790c794cb74819f091fe030917b698e2070b23f7aff84852d7f04e9ac51cd4246e1f801f589bbc43ca2285f04215d7d491864cd9a3e3e4e34153dbe97b3bc2edf2f56f3d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x96ede71e4438cd544cf49a9be39898d306d0eb6f90e8a27d8690d9633a099cf29024d9b2c1cd50fc396d54031c734528f640afd93a5d862dc04eed805216cd01	1621010389000000	1621615189000000	1684687189000000	1779295189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	81
\\xc8acf16fab984b5d9471dae91a9acb5cd77640c00014a4b35f27395acd57382976a05e6533a0573296839155329863e248d46a170d428af1972de29bbbf97571	\\x00800003c1e15a4000f6f2af2e8299756dc7c688c7dffd7a70497419c36f58b94c4c3755a5765d1c503207572ac60c15c97d3587e496fee4e97592a59c5f314b801c736645bc6bc7011e3af97e91cd2d6887c36548d1f8c69b8fc620c5e428464e2cf8c6e108ceb88c371f50aee0bc446b73f3afe5da81c0ce5388f53d8661b8d42067f7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7a000adcd2b0446b85db6075d87de8cc35aacf739b35ec693f015ca9082d9748bba7039abfc078e095d242713191a6c8816a0d1c953c2b7b87dcd8ec670e6f03	1613756389000000	1614361189000000	1677433189000000	1772041189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	82
\\xc8bc6628413b86d0d4d5f9ef58320fc594519bcfbe7bed5c33e38c1c5c43556f9621f7f2cccef5e3114e9aeaaa59a6cbb745c62ad12aae8e0eb8f04c9a8b812c	\\x008000039bd827602ed2b203c84ab0364d52cfe6f51252dd4e4dcc8a81a7eb59cc4f3a52ec58558c8f7619c36bee0109c89b9a1fdef3142243e4038e76b97941fbcd76ac8179e1dae91e9f7b7f2d33a5c115db7e57823a2a6dcb3e05e78b05a9f08b4fb9190aea81aaab5402f5109c117a38134a9738cd0c7a3afa951329f716a2e8959b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa6c5b05687db1c039aa605d07379face757ad04514e7e4e287086be2287e529a082bc62ce2b3c8a4873b000e473b2b56b2a97412e2f828e4b871f6394e80ed01	1627055389000000	1627660189000000	1690732189000000	1785340189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	83
\\xc8f0b8316e230b493bb5d21e16a08dee0658d30a61bad7d1f1b13c3ca0154ba430a83ab558776c1148f0919df0c33d7c10a59d7c5e6c4b20d96a1ddd6d6bd1b0	\\x008000039d12adf82ce5599824a35d1d8f12b4c4897c789c243f9ae0e32418f921084c91591237876657a17353c90879f9a246eb657ec58219a5c01f792bc4714a997a35d5b7396de0f9c01635e3c09c3bb4379dcdaa2d4de1dc5cf8e6738dee5769714950273707efb56d5da59d13da44a8ed13059c07a095d17d487c1861fb7aedb4b5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6b88c9adcadb17d9f970086366b874be15e8eb257f84ce4f886dd1afde54070f5b1972410e91b88584353db00dab7ac13d429984092a3820ffb0e8910d55a308	1610733889000000	1611338689000000	1674410689000000	1769018689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	84
\\xc8a4c3c00f740c447d214a4527c12cbb8202d4d1e946aee1c5b17f524551c48264e9b02dca89d78913d48d9cf83811872de7986f80af2d89d49df1efe91ec0a0	\\x00800003d9066743ca95bb16edf83c20176dcd2082e734c6f6d27effce99833a707fa9e1f3a9ddbc1890a67c7e53b20d5b3cd2a38414a2a69a75be163e3b9addde7861361c14e1a0133e732800df01f58370d43673609fd78fa9942b6ff48464bde2d0b8eee78e50204c3c8ae841dc32fe6c7b1aadc99e1641fd70393d0ac5bd8393ce91010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x92abf7d02f07a693c404038517af33eb6780b0193a139061ebca6561b818071b2da01d5ff1e6bd8ff926cedf035afc552e75e6c53e1f92d6237d79a64938960c	1611942889000000	1612547689000000	1675619689000000	1770227689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	85
\\xcd5851f6ef07503d396b4e218273f149edc8a868c3fd4a3ca75214c009777422824bc05878304404ddcba7a2b3e4e0c3d52b075728e878639c77d6b99edc97e0	\\x00800003dc18f06f50b77fd3b45bbccfe0e4ae38802c0e1953b9582d422b46a388ac3647a3f0181e1ffd8f6dfa23decc07f4fa610f87c05afc4f4b2b60f10e8068c9d6c4219fea4f226f9c7762d0bc0cc10330ec7e0403d9cffd33a0d825a5da4d3fe5b8efa1667b1a696cb38aca5fa4fb162baa165fb18088de20f4eddad4515409ba11010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3bd628e84fc3f7837d103ab63fa109f9d348c9dc8e25dd17747322b31e2672e26e59d98eea7bf4b713e73f22cca326577a50499b5db8a144b95b2eaf6ad87005	1617383389000000	1617988189000000	1681060189000000	1775668189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	86
\\xd21c5a12a0ea950b721d46dac7c99c58e0539fd95c750c93a86fedbd2258dd2cf5e0ceaa0733f465acaf5bc09ea5ab32cc8f0e425f8a4eb9c88d2e13f47223b3	\\x00800003a49d32268fade0f82a029abb49cf1c4f20f06cf9c8f3d00b833a9d6ed9ba0d4b9480ddc4c2992eb2e5510b0588b960ffa7f34a857b382eb0cd8a4488b59d19321dfcc8190f806c1b72588d2727298cf1a05770c4b57eb785d337511640b61d0b10aee23be30abfd5ad7ee7698df214685ec82f3b16f5bd95e14ef7c42161f827010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xccfb2001180ea3c5ec26d9783b3ed49185767512b465cb05e25fdbca07467deb0f97d47652601cd68123f2d0758be97cfc7609ffc2ba6af3bef735e7b0289703	1625846389000000	1626451189000000	1689523189000000	1784131189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	87
\\xd2285cc8704a83ba427b2d69d3f9d1e1fb64d2a462636130e63cfb02b650e3142509520404783ad26658c776009e5593922c35695601c922885aaa57fdd88fc3	\\x008000039fe8c55011b830c005f299ccfa22e2e96ac52e6acf1a217d627cc1232421d218e75e4bb6c99227b8e9e8766a1ae1f236cf05c8f3191e7353e97b7484b925764874a540ece1a9299555632792d69ed71f02587f05125883645fd3ef7a55f2c730f429c6d7f3cbb41b82072a80c2be97a735ec340c309bfb008ed2c10dd3ade101010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdba372627839d0938484b6aa9b20d69e9da0c70ce21e6b254376ad1003639be74722535ed451832d0e8e88818400d3d454d8844908553619cc21c348e1e04902	1623428389000000	1624033189000000	1687105189000000	1781713189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xd370c083e0ff4bb05fc658f6238e4faf707cb9bc4ca4c7f0fb36526375bc94ded4f68e2ceb29937c6f32650fd1daa0be21d793ea215ac0e767c2434609261e65	\\x00800003dc9edf9b96e4f2bf493caf9be3f1cffadf7c8d83a412fecebf9f1d5258fedbacad51b593a1b41f18079556dc0b3baa54693e666b7e39d10af75254a40ae4aea04c7984153c69363db35c6fb78a6830aad941101461a0ccb939df7d76796ef998610314a6689a33436f2c3b07bd14bd76bdbac14cdb0b90a57687c5659be267b1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdc546e3cd4dc104656aff38969f735849a0378c8b3d295685773f3bc7ffb81a6160e5c378dd23473e994c0b28546e5f5e4a8989aefb56de5a9fcbe12bfcac80a	1616778889000000	1617383689000000	1680455689000000	1775063689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	89
\\xd5585e50c2a6f8862d26d563e64062d770d445d0443a3e84d9a663a088fdeccba5285714eac02ddf480bcccc7bee861afda89d1eb6715c9851dcc79463e946df	\\x00800003edba85fd2806b3a6788c140ababb589977f52ac36e71df686dfdb2a6039600e2afd4619d14eba7b27f170a27df26deceb6dcfec9ec47406ea6243a642015e152f212f66a2f69044592669755196477eb997695501b637c6f57e6a002d8dfe41c4e07d938d97beec46760ac1ba794e04a3fc20a7808e88cd19add66739d88c4bf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x202a0929523850683e2c2293d931e2870a32b3c83252853e70047d3dc9b8a53216fd7b247afe377687656b92a6aa109cfdf8e00a5e71c3cc6815b267b827b20b	1631286889000000	1631891689000000	1694963689000000	1789571689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	90
\\xd7f0c6bf8d31602e9a04f24d88614f6ff87d25d6805864927afd584f2d704104c5bc31734dc88979091a06340e5134433965660b23c8553463784ac3730b7354	\\x00800003d9704fe1c107aa84c941228b4d574ac2666ec5630f0d4cd80a48329fe5fb5856b02fcf5f71c1a492defd90411380087860790d682c8f249d975e343b87cc8250b44bdeff6d628b53b785e5f04d1487b4fce93751082e67fa63cb4a1a0dabb95e264d6669fd754ad324ef674a0a6e4c68030bef06b1cfcfae63c0465fbcc74d9f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x19e6142f702e453f016a2e35044cd4c1445891b6544670f59b2127eae79f9b39e79e31b659577b09ac6d802ca7d82e1b42ad925cd6cb3dcf742408ae26ea7e08	1629473389000000	1630078189000000	1693150189000000	1787758189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	91
\\xde7ca190f0b299083d6e405d0cbff528f67300f666c86194640d72f1e92acaf95f7f767c02bbdc67c717410bb28be797d43e33938056f9a3a2564d4c6d6673a1	\\x00800003b39946b344aad4c23bb865e9a9b1a95a6d4c8a0c71f5c8e80515b26dc2e6030f2fa458784f53ecaffb8fff8eccd2770ced57e118e107dd46e952e1a8486cb6569ba8e0d7bc937a7196a3de2cb253ce77a985d192caf0682610b97be8c68a31b3be8c75a96031f83331f369565efae14a7c387ee2a6f208344e906b2b47f15543010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x88b11c0e96d0a99183b76b97dbee112f526f69dec533a3998fd97b32f818c2579f5fd6183298c2a10534c956517cc01b4756d235478f0588afac1f4c2ab4f80f	1610129389000000	1610734189000000	1673806189000000	1768414189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	92
\\xe044e1f7e804c808800f9c23395f0eb894f8048a6d917770f0692bee0dd770ea9568a7a0e4b159c0809091e3661b7a05d65ac807ad524f1c195c73d34d26d687	\\x00800003a2faec3c6ba3a806e08534f405cf9e6ef963234fc183bae817dce3d28de24082989aa01dba7ca7835c5947c0f40ed4afb9abb88900335c941b3462d416a77fa5d6c435c3783a69a1c5a87b51baa2e0d0202eeffbb0a957b92455acab1389365bd8349e635c362fe37512c87f2ab3e63e74eb4c8b31c10e8bfc09c0face0a43eb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa2ca67d2cf343d4fa5b2030f10f3ed647dbc2551a4f03ca391517fb2f4627b0c406e8be1be251ebbf53319258891e3afdaca6bbf794da90bc2ec131e5158240f	1631286889000000	1631891689000000	1694963689000000	1789571689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	93
\\xe19c2d25ffc7c1a1722af8ea98b990d20f3d0d92c725bda9482b8329b5271fff8e67448c667bade7114436ff2cca669805d7fdcdae6e701925eaf4f1f2d59ed9	\\x00800003c0da51a8dec112f6c5e836d35e73124ebd4278707e27365743b4b5c35ba4d322305a9b1855af32459c30e023ddacfe9d9715218b48579c781a49153225a3234892641e0bfab54254adebe2c38e6a28e1f3f36abdad9a9fb84fe48df5119784051abb7da7e3f41ab2b2d5667aed9c3e9be2c1f8722636e9664f44c9423425346b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0fe4c1fdf376651457e597d17684bf1c4c0e504c8508b37b9f9ad1c236e7fe64fb20a94a3efcd1787b7d24c753a719d272770ca7243cdb93c4deb4fac757a603	1628264389000000	1628869189000000	1691941189000000	1786549189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	94
\\xe250d088c944e00264c2ceda83ff8f09877aa69342c8ee7997464729a21c32692a3dcce3e2f958200831c233adffe84dd0ea8f744ad6ec7e3d66ab8da96619ff	\\x00800003c967c376753ab78a2c7a3fa87abd6cbbbded7767837d1635023d9f426a413d47a67215682bcc9f79cf0c960e4d761433afca9fd26b905d673531633b21a7498fb74e7a3b0a732366caa14f07b381ce297bf0b9060c9e859fc57dcc7a5738d48e1a3f36f5ded28c57be95831c929e3906b1ba41422b14b558147c63a00025ea3b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x201cb5102fc0cdecc54e7289f7dfc610ecec3fe335ed638b2992aefafbf6d615691a4794652f7244b871276dd79d7001cb2967f8f0a849b7cac928bedb92f303	1621010389000000	1621615189000000	1684687189000000	1779295189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xe47c1d83501e6025bff071ecae6e427c4b956e06993aacf5c2bb44a02176d1cca83f691ae278fa3d0720f0657255838d9cf386d6c6fad7bd1330ba92df6df263	\\x00800003c7813755d8c8561ad6a455636eb621ba8ea2a52edfdc05a51c061cf370932751e1af2861d9bbdfd8c9cdb25ae50d137656ce4b74552d44cf414a929e6060e52bbbbdc9d36768c56d4e262aa4b75ef49eee7dba4b40da36cb00c07dfbe16ac7059c49fea16a915d433187be61c37fbcc8d487c5fc7495b5c099f59bd7d5a8d1c5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb90cea61be562ae09b83fda361e226eb56b70d9cd27471b98650cd7bcffb5147780bb90652f47c851b9fa63c8232e6e21b2909ca49fa55194cd390dc65b9970d	1640354389000000	1640959189000000	1704031189000000	1798639189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	96
\\xe46015ec1764a4249b90deff184b6a8c0138adc1a8e519371fbce5e0cd33cdfe899700d774e797c44981e3a352fb13ee074259bed2c7056814ab672b52bf85e2	\\x008000039b74bd49a6d8301bdbd718361a617ea1065fc7f4aa006744ae1f24e9073b23dbdbb84d38e7b1a525eb6e97fb36a7e7332efa914fb7e5fd978e1411d8fd5f04f7f9e7c9bd5e8726cb7e4871046912b9412229b7cd2fc8d0775bb71100d0108222c39b115867724de235f2899d72f39cf8037eab3de3cf4a8572d1d95840b3b3d5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0fd28f1cd85cb47b7536ab86d944a48209dab6216cd4399b3e461509323a977ae24caffd98378cf01f1101c102bcad63c8e923154ec5acf48218aa31d11f7c02	1618592389000000	1619197189000000	1682269189000000	1776877189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	97
\\xe6acfeae1b6e52be28a407536c151a400c45b79a507d028a26c1c9bb5183c452bd3fe7738645181f0bd98446ee9fb752c22fc1c43286ad7fdbacf2b4131e30dd	\\x00800003b95981165f929dbdc1d4a61ecf0bff5977b19da3cf68cb21125793f0d8144b0c18e3f00d1110169470a6058a0f09440350416af9654c2dde7db5e8d5cb2f51fa82fbab49dc67059dbe5b92017af1421ebefb8a398f696a6926879673eb3c56ba006c0e6b717399f1b5c7ca4f5b8bf62ce5e60d6e239215f33c5c020bb3cda94b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbb6a6685c21ad3bd0f420721e67a7afe3cf0c4c5a9c109c3e1fcca95110f456b8789bfacc908946e37e52400840d52cc03ddecc7884ce0c17429601642a59b09	1612547389000000	1613152189000000	1676224189000000	1770832189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	98
\\xe8c0dc60247af15ec35f478d2ec82c40a9aa907d01c079ba6a9a8e79bec66fbe45784471f5e6f3b82ec5342c08870926d07b9eab2d4c18f10e2e8091ccc08f47	\\x00800003e4be8dcb09a27901d0e790523f649a292c4c2c88a7819fef06f4b208a18e6413c239897fb8ff35c4841a7119788ec69e32d642d13b1b9bc4aed051f49a60e91654e5387de1a2b0a8ea9dc762cbf9cfda752fc0a8d20a29e306817dbab32501eaee4fe41c1507acef2c15d89301f99aa1ce772f5c1b469d1291312a2da5ed1851010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa381992357d7a3461723cecad8b9bcff7d3e163f5bddc937ef4f441c4fbadcb4d5b87187dd44b2c5aa49a58ff8f25a02f5a8c3b630bf724130b360fca5533500	1631286889000000	1631891689000000	1694963689000000	1789571689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	99
\\xedf079ea497d1c8b75ba14d6d7a73100d8e4af6553029d24e0d4079f57cfbbd6e0c79752d659ea74e183def59efa01ae569031f209b5b8940d642c24004388e6	\\x00800003e982099a15784e046b21dc96cfa903699408fe330905766de681d7b8fe47e814e892e3bf03af5ebb641c9da9cf5097c5cd99c0f6f1b85c3f4fb796fbc892ca14e9104ba55879210bc022b5746ab3e1fe9511ea97f9f08481a18680b5e7efdf9b5d16c34969f8cce7241e22f7f1a052ff725eebf67c7054b7ea02f3747d88909b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd17046a2959d347230324daa95187c663c331e6a53bb30806e477bdefa31b5ca871da34a9d0b7a422988f9a3a8acc13d2c0b3be8a87e7dfa83b5f36ad79b3d05	1616174389000000	1616779189000000	1679851189000000	1774459189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	100
\\xee3c3251b3268e02420922ea37058d6afd5ff05da8a8096c2f497433cb271daffe57879cb010d85345e2e451a098f695b8ea00e95e0e0fc909aa1cb07b605849	\\x00800003e99b2eff2f911624c6f57f0a9846d482a65d680744fa4bcad2af8fb8d0654c18d56f59952cb7fa6e35e30e8ec28ee14d4f861eeef2453431e5287e4b950942826c4436ad4fa9bece6ffc53c683ecb4bf5246e0c4a83faf12df9f22ba447f76da37fa157f9b86bb846c8c26e19c2d49444dbcdec90509f249dfc59e13214b3e25010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x922753d4b3ce2f027878e9bf5d7e87a8408348d9a0effb4e6735d6d582bcbd5bb2c6030bfbc322c688bddbd796d5dea4418943aefd279e430b32c8d40d66f205	1624032889000000	1624637689000000	1687709689000000	1782317689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	101
\\xef8c1c72ebfb9770f240455a5eb3b3025af4b8f9e8225c63d9e262870b767a84cd0527b2388135f5d5b05fb3a5067dce01df83a4ed2fa2ec0e1ace42778e7a29	\\x00800003c3267c6339bb03f0b5ea7ca1d105d746514ac59e6baeefd8c7d5db2782f3bf734ce01437fad43cac28926fdb6ce24c2e405844cff77fa7f8b57204144149781975e72be7cf8b51b3ecfcdc916dd2182d4b1ee10ee95b92e2cded2781f115e9af1346ca520a80ca2c50fe48fac279a7f300f436c89781f756c0e13bd67df13f53010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x438753bda2ac4eded79d7019282c40563677fc1de0880027fd72723555ea398407b1cfe50e75ee0c18eceed60a10e6f3507bfcd5e36a474331cd4b8b6b4d000e	1622823889000000	1623428689000000	1686500689000000	1781108689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	102
\\xf0b8693eb3186137f0ceb6323ab05b7129a7a86327d1c9b0fa2e6a50682a6a320eab20dd5d12679b3bcba6e0f26765a7bf0fb2e1555f1311b1b5aca906db692f	\\x00800003d6fc7c5890797fb0974b22f8d5a43b5a31d99d0ec9a83c0510a08d410895a1cbf27caa5f4e49ffcb644c561781ff4634eff628b442d6412375d76baf3c61b031cafb94289e51726bb35ffa537ac40cf9d4c77cde791b45f23fb1c85b2ff01ac1a3eaae9506f49fc4e8728a50e3962fc385d7cc538f01ece48d44adce45a96b39010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdf3dfab730376f112c7da349a2a3358df76e265dbdc3714fb9e15a07be4e9f775bd493931433cd53e59b987aeb9b83d0c0798b56f796b0d6788af80f3cf16d03	1628868889000000	1629473689000000	1692545689000000	1787153689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	103
\\xf5d0ad790959f9f88636e37f4b592f9d74a92bb249d96a8f72fcb6e895a61426cc47b87571e566b8dd7a3fa988f66ee6febb9d4b7e11f21f1415cb2bb9f2a88e	\\x00800003b327cee4a183512f94a010c8a825c396ef35213e52b80dbf40967b91fa44d1f300ede132acf7c766e9fea6f247aa7bff2d1cff022b9eec1c90cd0d0d3617013c997b5065932a7cf16603961db2b8aec3cd1e8aca08b38f77620d7552077ea8d1a24edc399473de0e5980017e91ea36d0cfd4e87757dabd5567a74cd92a295993010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x81d639c148eb89cccf171f86758fd145379ff6d6116a139598c10112e63e54f57bb91d03af314735ef8fecd1129c608aad5bfbc99916e14552c08d825a3a0409	1638540889000000	1639145689000000	1702217689000000	1796825689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	104
\\xf6cca7eb278b2489f5a13ba7d4a08e85acb2a712c722f8c246eb09ba5b42bfe0ca3e78a8a940a34c1c97f2280023aa746302f953d27ba8e2398df774ba0f2ba8	\\x00800003ecde696de187f3061d2628262c1443c4df1ae94e50cd318682302b9a2c76cf3fd0659d85fbf0df8945a881d3d27d4db9c1e4b7f63ef487861f59631024e184795477beae0eea48a7d101f8817179106d82f9faccfbc171282cdbc89d9e5a151a35919eb775b9867ea4e92f2d9e0fc797b6e43f05305d54b0b799cc164bbf5d5f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb88210f6df2456c31029e679e2d54b3858d4cde59420efcf9f287b37a97f856e8a1a2736e5477a30390e828e6a16d8fb750c4794a99002bbe5ff04c78d3f7c0e	1634913889000000	1635518689000000	1698590689000000	1793198689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	105
\\xf7148d482c717b8766a26fd88ed8fe4c1b59ef41170e743de631c2c9cb8e68810606ec42c60a8f1a2e7220e0cbbaee381a239cb5a423d7d09fe1371b17dfda51	\\x00800003bd6a4471afb23abd5939579d3f2843b165b1b7f21ccbc69042db505d22b39ebd436a5599c961144749b1d6e33d3e43b78ae1c04ab3c87efead6fc22244eee69ad491332dbd4678b6e54f5363f7c3f9c14793b15aab9adb3b4856cc5defa9887f711dab62d710d3b1268a68cf7d77bbefadc77cbd6f024261562b84c0442e4207010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd26430c124007c9161c2eeeb1b446707f532a1e3119e191d7479a2da5c3ac7fb81cc73d2abd6466ccebed5cdb24232bbed620dc4703f830ee4dc688291ff5f0a	1610733889000000	1611338689000000	1674410689000000	1769018689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	106
\\xf9f8c1ab85007af8ac6825a94baf4e5df3600f712f3b950a2c342dfd4d6e9c4481df561ccaf9a611e8cdbf6dde2304f3dd604d3f2df76991d2471ce8875c93ce	\\x00800003a07e7cbf1e29046b7d6ad24ed33f1cf1c68bcea65ccb3ebc48c8aa7f19ad5e11ea3cd0ac4fe6641dac437a0de621ad772c787e36dd8ead02a1410d6fccbfb10b4e47b5b27bbb2779f2c1d18d090127e61222846be481891283443fb97d1f326d9c78af648b0e88d7f3f35fa2aca7d62500a677295df1b7524a3aa78c9467055d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7a32533c774647618cd459b1f6a5b35e82f9f86d066a7a10d5c84ce061b9e9761d540d1522e098f76115825571660c54cd94fb1bf076973d431772c88f63be0f	1619801389000000	1620406189000000	1683478189000000	1778086189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	107
\\xfcb0cbddb9a5779e2f9322318c3b01f174878fbdb1daf97bb18f3698235a84d2a57e79a1d4d82af4ae065b0136676e8af53790dbd83fb46d992b157a0e2d7a88	\\x00800003b4576113ddff4d44cb9268fac6030f352d68d728bf3235672e1f9683d19c99d7c60019398f77b0eea4065a08cd94fdebed83e37548e5a0e39ff152ab4239fb780f0e71d475780ccf61e6027a48cc35bf8b44e89d377b9c04817d343560805fd724a6f95db80fccd79a9d5e53d322d1cdf80a396b816f080b5260d4ffd496e7ff010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbb6d8709c7598a7d157396ed21ea05385557985daaa9bf26b3fdac3206404caa8e9af3c0cce2faa033f7bbddbf86b948ffb32a29ac660839a2f3d1c40130fb02	1640958889000000	1641563689000000	1704635689000000	1799243689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	108
\\xfccc919ebafe4fed568817f6f4646943fdaab32f83ca63d2253a20989a2116dce46d3cdffd75f26fc178ec77608740f5ef5f6c7d45617f162e3872d9760ce748	\\x00800003aa2eb2256e4e1514a0ce043a458a08d8abbaa1f2fbb257577db441581f3b64c81907004a20a3cb495ddd16739e8c4b06a913db8ca4dc0e66b27b7c88b40db145fb8f822ec5678c190304c61627c3771c88df36b4121ab7febffb1a5602f2ddd3297181d5f2a1910ffaf4117603fbb877b126ba75a137b625842d60f3f14bd4c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe23cc0f733acf7cb3167b2dea1bb2311734e9a896457f2e03a258b53b613f219545653d47c8ba29b3acb04b7fe423e9abd66123d30f0d4b506cee4df68686809	1631286889000000	1631891689000000	1694963689000000	1789571689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	109
\\xff707e89f4abb923150cad9177daa5936e700d69f48f17c754431f54e8be342538090312e3b95c66a1af2b727f6733bb27d0bdfcd0ddb488a708a292cb094967	\\x00800003b1c57ddaf1ff1683c8f860461d13593bee82337f9d4c614f842a5db38d9dd015df76e4c386c3fdddd1f6f1f8a80074001822b323c65162821cc6dc2b33c379d1e1222d9b53a9aad6a2da94c7d720ac0fdfdba0da27eead4677f8ecf3fc191bed88230d960fccca4310d58561d9e5ba3064465bb729afdac34e234c43f8b14c25010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xecb23047607cb7db7ec9e2f6da55533a9b2222e3439a6f785e30f8cdea795242bb40e5bad313960811e82a806206b6843ab387dc7c7189672114f1df39ed610c	1627055389000000	1627660189000000	1690732189000000	1785340189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	110
\\x01197e292fba297e079960a524a48ae0d23eecb5bde755feca7faaf7c68d1311552bddc190626aa5c6608e6c1e5d8b9d9b0ff20d4c3ac3b1cb0e3d64759f4f31	\\x00800003be7f226e2e4ee40967fb64103577110511d4fcb2f0548f159be4228fa7791721afc14bd53ed761ac3cc7dcfc820078d74d31423695cf1e271c2a993a9b987c84a97642a8d44f15879c631a8cda06a573594dfce8b9b6dda4cb46c368ca04774eaf72aa8b26244d05f9df3a321e5764cf74899080acc0d270d022ee84361a1faf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x55f04081f958ccaad66e29dd798d973b0aae42339d437d4a88f0423e28cdf1995c54fda6aca375e86d3a518a0b68e21fa2cc239d05516b3d15e1e90cee36d506	1628868889000000	1629473689000000	1692545689000000	1787153689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	111
\\x07b1c5d3192d2e9b869126ac9de5cc71776996fc45ad618a315f19865f891ab635678a3498581877169c80c2ce28066f60deb06f1697993336e07a04a2bb717b	\\x00800003941b95a58363cd6649739fcd711680ada6e1bdaea72926970239adab9a827af832f439a9c2a1e90366d04ced166de600acb3afafdddb80842d3fa3db9c8e54dde6f7abc6e7275894d1aa5290185031dd486847f4cca8f229d1e9c9d233501c1bc4183ab620ff508a68516cfbc4568dd9a7da2f7edc6d0c49189ed1b79ef81efd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7cb1f2c877842cda308dece03317111f9fe132d736a72685386b75fd7227ede102a67631789eac9604dc484bf719b4f7f3313dfb58b2e3a963d73a21ef2b9d0d	1615569889000000	1616174689000000	1679246689000000	1773854689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	112
\\x0815f0c6021815f7a73151aef059b6e98369d92646defae07fda5abdd751152df10fb74aff1c8a29cba596de41708b778ba8a220ec389f867dd4874b705f490f	\\x00800003d07abdd70938d39b7677a02d4002e2af27397db9c473a96715487b311a7aa1efeeb961e8c8d56a4b9f7b314b0614fa28712f65324c633798cf0a9ca11fe0ae21e21fb90708fa06a7b7e41dabb4dab4cf66198f60a4b35a15e60ca28323c257ed8bc597464ec1068b48d018ba25be0b4d274fe2cb16f5e1b0e6bcb95b47dbfb07010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe3740be1454595eff1dcecca90899469e6d7f1f01153e4dd626c9747bc8b0cc59cb96ada7a33929a7244ca2cf5801e911575a81d6d95b67b48d179d83eae8205	1614360889000000	1614965689000000	1678037689000000	1772645689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	113
\\x08b1b10b1121e09c1d1a5cbdcc1803a499ccda41ee36c4f9516a223d60ad83abc25f782241cb0df023fd6741141034455729d70b84a52161421addf24caa3d85	\\x00800003bd595e5e76f0b618f8afaee240e45d7e545686209427eaac575d2508b251c0440a42d553667991ed583cc992d71c285ea8c9519b7b8874250a61868e32b0659dabc7a438902f76765f237be5d5b6599bec6e57355873cce07914424ab1c8fb3fee8380816674cf2189a4b302e1262d8fe74025ca98b0f4cf68357b0f32484171010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x996f2d8004068d670ea8f6a656bb18adca0ccb131c5c734803de101f117cfcb1f0390855543f8be37f878ae60c00c287f43389adbefc02c9e94c5375df15e50a	1611942889000000	1612547689000000	1675619689000000	1770227689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	114
\\x09b1389f731e778c06f9d3b699e956d68d9d760fca771b5fc60a15261712949bb2156ffece8cc2bb63155a6df5d94c43dbe86e1d75df29d83479b822476cae06	\\x00800003c646210e11d2efce7850cbdae2fb0ee21e5c2a59e32623d8da1019b5e001180f281a686cd3574e93216aa3933a3c70fd4e97b50ea524bf9a863a534b433b853b1a8697e8d12d2d4cb787a02d786f83f7edd399f38eed1f0671094b4704f504d8ef339b835b68e95fcf9295ca7e75b324c54c614491c5836ccc5eadb20f90755b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa6b510c1afb84827c797f1c130800047f22036d6e479025f502c371d47e149db6597e66cebaa5366d12344c745739b8ddcbd43cfc26305a48298b2b10f332b08	1638540889000000	1639145689000000	1702217689000000	1796825689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	115
\\x0d6104b84e59a7d4740a0497b5f02eb9f6995ab94c1bac8711b5e8354766ff11e8ce834d182bbbd5bd26b64698696a07f745772df3f0fe553013d14517510f23	\\x00800003b7f40bdd5974956cee380e81b66359e62f941be67d2a43ad137ad122a4dced0f1f5dc0af0e4e17d7eaac443f543417ad8add0542d65dacfe8f8ae42a9f5ddded117bcb40bb5ba4c02c4fc2cf3ff09a894d9969bf36da7610b37fd2564207bf9cce4cf3e5957468adc6b5c3ea5576275f8b93eeddace420cf9f8b9f4e5eca7961010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x13f15ec98aa6661a108fe247675ea120445696a8ad4b67e85b726558d350e5988de7981de71b2e63a348bc8ca997e0d2bf31d5ef6d2c0126f16c615a6bf0be0c	1626450889000000	1627055689000000	1690127689000000	1784735689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	116
\\x10897e01f03b9e2d89cad226540193762ce8affb3fa5b84b92524f6f52b7ee5e79b1768deae2dfe2785ea8a17a8cc92df0eeb6f471ca2e47436967246781137c	\\x00800003ccab516d74d4b3915d8713f1b5bc4aa482ad1df3412e76b1e543577a4af55dd0e9d1ce7858f46a662538727e1a070f3fc7519cc4783c343c4583f889d5107f7f72793ea5dbe67a8924171e264bd164efdf9e4aeb12c8d20a4778200a9dfc48c76209a13e7c8756f598c36068c45a98c0cb89198edc7d2cfb7b5c73d22f1958c5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xef3ca89913e6c8c0bbebe67733ce802c6eaf4f9d474cf8896892b51f4dff8193bb765f5a670aa6b99b3c87b13ce17525acb8611a99527db7c65ca28981b79a0b	1621010389000000	1621615189000000	1684687189000000	1779295189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	117
\\x16d5a18e9c99c97443317cf60eb8a376253db0b10e9f63ee113b0cc0319330850f8bb269b9b09f50ffd9ddc3510cd9a6adc4debafd162508c90dfe1ef552a508	\\x00800003e6751670cfff3cd7d507b5a105e64750d09b331a37fe3831015463d2cb2ca323f006148eec6f146bb62e81d08d80902f8f39efd8a54da62e4e09e28ba6855ed7bf67702a4be3bc363e1ccc510d6a1ac3b6b33b855454dbc2166360cf4d63793bf72ee0fe17abf03ef231b261e9fc9b35317231eab71eeb4fee9e075cc36623eb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd1f2c71f9b09754fbc7010dd7e3aa75dc79c8ea93a113455796d1eaaf1af9513daa115fbc21385bd569429cf3d7da73804beb2a1f27f638eee8c429d3358e105	1633704889000000	1634309689000000	1697381689000000	1791989689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	118
\\x1abde1d550eb3be0dd5716adf13476277ec822937022321199ccc8bb5a1e06bc9c087e4884b9e3f89d8319f17db47496a9b4f039a2097bdc4d2b2b52bdc0a0cb	\\x00800003d925ec71a9b16112ff6722d51e5a94fb790cbe4fafd33cd12ee9b3b44e6ba5f2fc57dec3828ef5ddce35b2d4b0264481ab564009cdb1fc543d8f9fa5c3dad5fba8f697f39ef4bd7d4f08c3a796837394fbd6e34ef71957bb2b49837e36cd0677fc16ffac2b4314e77ecf84ad4176faefd6f25a471dd701a7adb29428b144dae7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x130156b8a3c08cc385c95010852a66e2f24912bfc7eb3441ec99a6c4064c7c9480f25d4ddac91b5a4ddb7999e9459d53990c301997a1300432f24d6c5c170c09	1611338389000000	1611943189000000	1675015189000000	1769623189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	119
\\x1a814075dbdb51f6f929e4815758ee2fc80d98fecbee4795c66b13eb3171df80f7f2d758bc210c23b39d044bf5f172cbd4d71aa7510ef05ee13eaa5f19028843	\\x008000039caef35837f005dff9eb1967af5bd496660935b0ee6f1692beea7602ca022e19d42d30e179b8027c1e252f654da6bc61f631cf0b7118fbfb2a421306cba37ab19e42ad8fbe2cfe13b5eed5d582c1720b77070922d93272dc6600efad41682ef821a09a923b25d59e3fa1223d919e2434c36236ee9768010929ed2ae669dac39d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb1841b08be48a5e280116cff2ee2e1caeeced182caf920430beca1a1fa17205b9415b6c5138805fe456711184f6f6165e31780e0427c431ce9cad2b96a7b720b	1634309389000000	1634914189000000	1697986189000000	1792594189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	120
\\x1b8dc783340a396d004176b4f53beeb1c970aa9157dcffd4164f716969da404aa197f9e570f17bb2c725d71c324ca4e70540475b9826900d1866582e6bf55a10	\\x00800003e4cda26d0222c0802185add5dfaf429c5ac2aa95d1f25de6517b4a4e0ae65d82c34800cf7ed729d8cc8675b4cb1e6c227c041425ebb886b7b7b9da1c6f209d3d00a55d2558029448889fecb8f8207fc3463a1bc438fd48d11c39a3f390c51f0d4d89f501c97d2f16a52fe50da667b26dc868854c091fd64cc7af848de27225e5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x55126c708456f3e69aad21a66558c7f5ac227efc2b82128ec4a0159ec65cc18cc71b6bc32a522c0b95f62dbe1e5e699893e134e8b7f506a02c0c70e6ecffb000	1636122889000000	1636727689000000	1699799689000000	1794407689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	121
\\x1d2d0314ae892b19dac1bd026e88ff3772c9b8b0cad159f2265625bccc5f5a65bbe3b941ccf7dc30b5766d717b60f511019499913ce11dbadb88dc2d46ce4221	\\x00800003d299834d4121bda4a43b0760037cf4d3250ba9e880406b269105c17abbe30f5089bc38016710206a5c9338abd947553bbc2ff8ec2d29cdf2b96751ffc4763cce20a894fe2031f2681efa3811ada16b165c08ed0626d99dd598cc0ad07139bcc4f1760c88e2d401aafb2de7849cf856c696286d103509969efa13412f45d8a357010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe4b083d14a8b6c120e295b4396198d6fc59e12689706715a7c9dbc1887d77253afba16be6f8ebea37a9b0126a287c117eb0a3ca11d4fe6ec8f7b8fb2a623c80b	1639145389000000	1639750189000000	1702822189000000	1797430189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	122
\\x25f183487b4e2b8c1bb9a549a0c62420737194fa501151666c6e24b28d884718f08896008c1ad2e0546946a0b8fcd24b9b0e12c22f830bbf740eaf3f0328bfc9	\\x00800003ba6888da0d9896465a1ff03ed2c61221a167a90d294a54afd50349c87d37ed196dede4f39861f9e808253ac717c42e3e9e673da45a32b779e263205c127fb265bd2f50334c00b19ec67e4fb50331f7802862b103353e9c5c6906fe90c73bed18e2fb26a30cb224a98cefa32ac46abb7277d5e7b5d09cb8b69da775a2ffb76737010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x093a8044057d235eb83cac15061285db524cb3f4227815065aeab4a8bbf61fa26c0f47071bfa8ebf018cdf8315ea6b2e3d7b391e30d5e1eeb4e6bc5b9d954d04	1628264389000000	1628869189000000	1691941189000000	1786549189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x275ddde967152a66b7dc563316fc8eae1106ba06f99db11568387fbac6aef41fed14248c02fd25b6376be334291be108c93b950c246259af4a950d062475a631	\\x00800003baeb936cf77843e584d19f08280ba5ed7f87dcd2ced11eb56fa63312e9d227c82280a3463f627e81fd39ad957ae98d818a81314ff7d8504344c9016cc5fba4a3d4b61da00b16bd585e8be0ab319e145c6691c20d864e2f68cb31a06ce3909c0431d6408d9401409c7ed8f6603a7ae7dc52dd24b89612016df1839d723844c1d5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd632023a2539b91fe2745e59c1627bb96a2968fd20de5b9c5f8d0fbdd5f9ae38e7a46852b949929e10014dd5a49e9cac4dcdfc0d7ec190d758fa915f6c79170e	1610129389000000	1610734189000000	1673806189000000	1768414189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	124
\\x28218917294731f091fa675f5623165090a372fd99a71246d26b9a73364fd3cf6dc8adbf4ab6f990adc5dad21e7d3a8205ee172bf220e069ffc319398355c0ba	\\x00800003d5cda615d3998af1ad89145315087b88794f3393e4f10c258298d75783d8092f0af03e77fe752cd98a69d2fb49939ca1d1dd3600d355a5501722c216b6c583669453d401919f66333e2ed1cd1e3d56bc331a9ec9ba459cf70f3ddb202de90d20457426c360f71ca7c6bce651e85da6c3e171a8b9976da9f7871e552e6758ca51010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf9d9ad08b9f2c80244a1e818c964747f5f360d1aa28e748eca5f0f5f8af858e2ab2c6a547b5dc0f8cc299056a3a97f4ebcabb0c0a4b6f15a93990880e50dd903	1637936389000000	1638541189000000	1701613189000000	1796221189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	125
\\x2cf959157aafc5cc36841f6e076b2cbb3021f1e63c34db87e0d78b72061ee3db1ed2e34c597a4dc6d1f9f50bd6d63014ba78d012f6fc3aa4da11f14c07e96dd7	\\x00800003d06edb73fbc51a3293fb5457b264dc78e25f15d50bba097b386fdf8c522c2c1c5df6f47b460c42fd41730f7459a80022c9318f4c7decdd89fbd5c7839e2abeb9cee3a00350801a6212c54d4f7bdf12dd1c7189f1b24a4d8311f4d10244168508f5c9075c2a65d1055c0b8b590bec9def0cecf98f345832792b63e254670e234b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc54727ead0ea94a0e2c86b9e7700e8c824401326a4ae13d93b1aa2c3a3dd3f4bdfd3000353c63e37de796c725a475ae0f161d32142cefc2fafc7d39977bc6b0d	1634913889000000	1635518689000000	1698590689000000	1793198689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	126
\\x2e65bce6cb12a71dffe40bdc83e3bf1d940e9807560925ea5da46f6f9b44ad8c8ca678eabb1e795f4d312689a8a4b7f7f7716924aab5f2708c857371e259effa	\\x00800003b32c6f048d0845b8facb4ca2a902b51d92621cdb8ad4ddbb4c24300735a514ac77f496346406159dcdfa6c1733438f26dbb4d469d60592bda5729121e68707b6a497c29da6f189bb61d8c8be2750d7d45e756912cb467ad19b89066169bb92c4f9abeefb25d776838f15285c3d4203a6d22c107429e691fc2be09a416ccd6f27010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4662b33ece51ad4f1c476bead2a9324e20369ba5e9387b03ae4d393d793fb9f59553d0e8e159ef5f0df6ec2c60c6c3590354f15debf75124efb2b3b1b79f240a	1619196889000000	1619801689000000	1682873689000000	1777481689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	127
\\x3199c4f4df872a88f8dc372799490de25babbf108fa0f17d7e76e8b91d8d2a20c7bd13e6118ab1ee4a5ad914416a9183a244f4c0315140330188b279df9bfb29	\\x00800003a31dd9826814449778e39d7ac0c27f5a8068e473194fc0e4dc4dd3e9216814f3f1043df69197cd5eb3a17ec13985f73915ebe512619a9bb93f303321a988449ff1155dec5ae09bc1e8b9f3751e01f9ecdd270b5fe757449c6969b577289fe1a6f958800a961a0cb426d4850e35b0f87c5c8955d899580f31730977b5399e3809010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x34d139ef18660c7550d23777f3e29087ccb87430bd5c4afaf6a8e5eeb9876f2ed467885b3ea0e572b3b151fe21da3189e6130ee556fca0738f9c21efbbdf1708	1618592389000000	1619197189000000	1682269189000000	1776877189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	128
\\x335dcefbc6a6cbc09bb7ca9c080ecc4ae5e60f04842eb1a2a9d1feaab3b3ab98eb3980b46595b6f98e0ebfada00ef2c20985e0e51ad1d8692bc3eb894737c5b5	\\x00800003cc8216fd5973046d77ff7ab0a396d6cd37a05b6c8a13513e29155eae7d72ecc38123f441ba73fecc64a040c4b224dfe6a5af6d5f0d149bdf7f7653f39e1a9b9aa029c1fa60ce22114e1fe51bc9d62ed9afbfd32bc4f1b021959dc3d5dffa8304ef0b1ee3a9d438a9171dfc659fc7ae4e46eb992bf8c3b8046a5b244a1df577e9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x22a2221c6a2bd63e8950054a0da36bacbc88222d9dc3143e278218530d6417934b3cddafed632e4f114da7c5a5b574e3171eea48b450e8490ff00a921dde8b09	1634913889000000	1635518689000000	1698590689000000	1793198689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	129
\\x356d6674959d277834d3b27d972bbc81cabc742e3a91bee2ca64492b15ef8bafdef80fdd3e663ee3fbdb18df44b53efc2d28f59e033994f4494b87809e72742b	\\x00800003be57e5c8fc913f819cadcd8f34ec9ad7538ea928db5a9a9267126677b52c2a8626e113ebc7eb5e406cfb7e9ccba39e4d81dfee1ffda58d6872f1e8f248cfb30798668566a09259925a98b613a9eebaaca1f522636c52cf45d8a2188e75cc50214713027f8bb27526b04d47bda1b1d373100483607e51debf0183a6ecddb883c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x333173ad73c85cdea4de2f801f132214056656b8c98105208dc8366da0116780094c5e24ceffd261889cfbb4f31425d6bfce549775bb68cc0bc7463a9ec3af0f	1619196889000000	1619801689000000	1682873689000000	1777481689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	130
\\x364da6d9539df33c2b8748a7acb4c7099214e7b91530051702b5aca03101df26901a2837cd5bc5e5a37202e802c7280b5056b8789ea9b96669758bfe5048eb60	\\x00800003bf161d2c4ea6d60e8db55b360170b576262b5458cae72a725494e445eaddafb9133db0ff3dbdee33f7d2b3fdb0aee7687a9057977d06a3753ed73364676a77f52ed9a7d99ccdcce81fb246bdcc410a5831b8eb1290a114914638b2009aba180b8d6c43202287c77cadcf9e55cf2a1d8f8b1f90b4c95d1ec6868a367cbc3e0381010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4b2269e78a0890c32377b55c0f9b7628f797f889cf864115d4a44db11bc3fcc75ce992848205d0fd3626b548054d8d33bc15981905c200cad200007898641f03	1618592389000000	1619197189000000	1682269189000000	1776877189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	131
\\x3b3d4f9a71d157e6dd6396faebe03d984131e3e343b23fc715e2c60c955b9a32acb4d7510be3a0f2adb50826e6d5f57f4d6e4b510f6d241e20beadff4630b2fe	\\x00800003cbb121e3fddb47fed21c0b0b34cbdbd36cf186289e9cce9731c6e2b50937e63a4cb7f86fb6a5e543cf7884d36d34d3e415c9319ef6a142ba2855efb8ee2f0eb24c46ecbb8b48536f000964ddb7933d6de1517ae696e4c680bc8faa1c80cb204d6a1bcd11f42f76d8c95c069043c524ab883511f0170d5b9a241b1ec1be743e93010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe4899343e1031114988d7aeaca07f227933f585d2e59b04a98189dad5671c1b44bed69a9c44f4ca17e7c563cdb32099f5fd9c5e37d1b6ed4c142055d38ae210a	1641563389000000	1642168189000000	1705240189000000	1799848189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	132
\\x44b97ff92f7036b954eca2de6805fa6bf3fbe711b145793176ca6ad3e570aeaf86d96f56b6378f4ee92236b6cdebda38a3dd0840ecf38305150cb07dc0baec9e	\\x00800003da219787fff553962672951943d2681f67c38c5ccb29f67202c7e557624911406a17eec1499f3ac32922cb375e0adaceeb80c54150f06a4649c299ea127eae0263a2393226b7ea7e9ced7675144b53593db8333e9327f63b17daf3397591019ed88c2a89f1c24f662cd05dd68667db596c40b1b00582875a838872e89c24e41d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xba143014f2f4b94eb1124bd79f18f40ef6b0fd6ce98afca168663dde6f97a61115e8da435521dd450e3b36bf7f1ca99e0ce4855163033eee5ef78d03baf4bc01	1634913889000000	1635518689000000	1698590689000000	1793198689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	133
\\x45e5d592cee55f2d1a81d8b204243564087b60d3b4575a8e301f953bc5ae90c6ce436378e0e414ade5a3fa0bd6b95fc972672fcc6a3d30fafd7da68e877153fd	\\x00800003f4573a47e93e4ea193d1b0aac8a0dd67578724744987ef20b4f97309cfe699e20f3a5f882d0e933c2a500573c8d2609ea2cf1434404e987eed02703c02e60db5e18c01d83a0baf0e1548c9bb2df6831f01f3a4898eb5988cb78dfe76236afb2bd984ad9e6a0382f9fdb2f16d4c09fef497c3fb74849958b8ac6e261cbb68c117010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa84208ca32dfae407b8592dbf154395f8f4fb62f03fc10a69360ff1b3ef7e57bd0e78209877c49292bcfecc59437b5b6fe35ef8ae5b42c148a6363956aac0e0e	1641563389000000	1642168189000000	1705240189000000	1799848189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	134
\\x4a25fdf1845f25e25494798c78ad20a044a5dad23ea62901d8168e5bd19479bc2619b65a627a0083e970b1da35552c586c0698ab01ba740971347ffd69d891a8	\\x00800003aaa84672bb2d0afdfa8479c3c43d201af17e14bed471dca4645e6860254e3988c852070d68870b85e5d95d2c64a12c2be01b4f7eb0ff0282e51b8703eb08e73a638ea6bdc2b3c64d7e82cda42ce9e603e3cddf1a30ca330514196e6813b503c72d51bf945a196e049bc42e012b61a954bb57a9f08dbab91886ef1bbdb16e09a3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc20c961b203d1d96a1569545692e6fbcd41667f3ca3891651817fff4afb0a7976339cdfe79db7984484380caacf1f776e4865df5613408ded0c7c5f130976005	1610129389000000	1610734189000000	1673806189000000	1768414189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x4b0115251d38ae88571809480c4eb3dc5a1b510786ddc83d21ed8a886ffb0b5e2894578aa37c6e1eb43e701c7aa19eebe4282d24d0e4022fe299cbb0df1ed4bb	\\x00800003bf90931e06162b7a56710684085852f7e0685a8b0e4483acd51818026afb39e8b307562ae0ba24860ca35a5f6be468add6664310a052b538833e372daf740624c03adb4ed43df7b6f1d367babea83afe3e84fd9009634c56f1a2abc13a7519d1e9c6a7312d91b6a6c9cb8d26dcc9fb94feb710f96587a5210b77ccfc4daa118f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xac6a0fae41f37fd31459d05fb5d96c26c66aa613cbb73e7f42ff4f4c4911f5c0d376f221f6ab10ca15dbe454fbe09958b5e38599d0709a5a6a6cc82725043f00	1640958889000000	1641563689000000	1704635689000000	1799243689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	136
\\x4c758e06e453878e0aa2f1de01f0efdc49478aa6f015950ac80c6b60c8314ac90ba1234b1e4c03e817f05d3b209518f60467932eccc6a2d4a4decdda864da50d	\\x00800003b233039ed8d73fe272e81b4084e9c7c7a742bcfa2262c68e1fe1e486ffc5137f301b92b161ea653b5662923f2c85b38cf62b6c32d16930d7bbf697d611cdccd18959b7db72a4a15ba5ed772d375a6fd0216e0a48eadd5ae49860549a6720d8d9a981e83093e649a0b84e3105b67b5683410bf805f710e254f498a07cbd9ef717010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x90c768a8ed6d3681922fccd5a68afa7be10aeb49bde37aa054cf87fee982847fd2edc94a5d703016f745128e6407a0cfeb01226de34987c3a7c64884d4458b09	1634913889000000	1635518689000000	1698590689000000	1793198689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	137
\\x4e09f6145802406a115b70a2bc149559cc97d3be59f020b4dd8c6252ce1305f06e624842bac730f33b5fb465edf24f502f5216ad6f8fd3c9d32a5a5790874071	\\x00800003bd0475e257617835f2fd49cc4fa67720ebb9a950518a694e8d7b4b3d3b619cd24871b4e353c8bd83f2fce78bd7fdbd0d32cf95551bc0fafcc33bbb5b9b3a27c59de75ca81b7d66f8a1b543f4dcb7843843f5fd9ae94b1ed2ea87489dacd9ab5884cc268be07b4e4556b8ae32cf4ba24eedc183850dc3f194c9ceaea83a6cb799010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcebd63e8c9c1923ebcca5262c414800409cc12fd9ef45a1e1ee9cd9d212a0c57865d6743414f9cdedf6aa5d8ff47fcab68889b13032e8e929885993a9e45630c	1631286889000000	1631891689000000	1694963689000000	1789571689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	138
\\x50d1d89c7fb9b998b52557041f7e0d438946daec62081ff7c4f23077a647cad622c0f8804e7d4c46a69683b4759d52493ccb23dc7bab401c3dc684c6d211cf96	\\x00800003c2c32f1bd62500b26cc6a703073e3c13732cd3247a5860adfb230de01a0794ef53ae9e5baa71e93dfb7fd86304ec1935052f35b03a0dd1797af70c57d5f87c0e6a69b69c1d591356ea7e7eba6c252bee87607add898f5102541f035198d171386ef8181e03e38b02ace169372925ff201e2822d9d145d698dec5652f56710a9d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4053fe1c062262485314d05a1219ce741e3a9cb5429b36c253e3ad7a21a47e609827944db12ea4cdf9f6a3034be49e78122ce3f45c16dab23f6392f1c3831402	1618592389000000	1619197189000000	1682269189000000	1776877189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	139
\\x52652de2c75377e5cdd0d4bb66ee78010146d9ce8a82b3353ea2084404adb158c699c22888070d5b15cfd7b6da4d01784db52e98679273897dfeb46d4e70969f	\\x00800003f31d25a10e3f982df933a4c2f7d3ae36587c89cc83de0794a9fd16aa5436645193f1a72e0c347985931f16ef379df8079dd7e0c616aad5c1ff5c3e86d1eb009665209be4ca7fdfd349687c7a90f91a4553d45732e11220b720c8609059c319426a1558e78088ad9150512558a1e3af51095a405e83b21548d4ffbfcb1c2c8401010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x384758d57b86d3c9dbcba1c5e3375e0dfd714934815dc506c9a4fadfccf2d6f11916c9232f013dcd252a95073fbe43805bfb30596b64459da5c494404294c700	1630682389000000	1631287189000000	1694359189000000	1788967189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	140
\\x5279a409e0e2419c19ddbfec68d4460c178b5534b6927e8dd7aee70c5e5f5ff56fe8eecad9fdae7151feb9f4a7d6d06665b22f616ee2a2984b9c35d65c7fa972	\\x00800003d79f5b5bd9f351b759e1f078ea7112b039d7784e563a665a78ce334865c63696df6bdc58af566ad24d0f616694f45a09e63684fb28aa1472b8c7157d8909c78fe1fff259eee3ea677b78071b2050592d6ac1c2c96aaa46995d7406b100cffa191cd145d21bbc60af6a8d339c9eb69001b14a0bf16aa93ecc2bcec5bd0ebaf8db010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xef69c4309d77e68665486cd52907d245ec1cb0657403a99aa1300e0359d174f031db5f9a816be09204d49b3082202b9e3ed3ce6ed86115ad6fed5612050fc508	1612547389000000	1613152189000000	1676224189000000	1770832189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	141
\\x52dd4e7d664a3835cb5daf74b708e8c313e923215fe4cf9a778f9a6327753ec93889fe7aa92f4f77cb4298b1e6178666670e8c57d6f7cf26afa002f4e2796e4f	\\x00800003bf03fa0f51dc747d3b16a60923589b1a51202f8177e477f149700b78a590f55d705133703e10f6143aa11f6b0b390d4a356a405e6c76488f8c333430c1c6ff1041676177a435d4a2ee458117f241ce24e5198e309979359f71bcf6ea17ebd2cba363abbb4c4832787f47d3740d59967103818d52d82b778fc9bf8e1527756473010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6e66f856e94072139d13685a29e70dcd9d811487a10b821c835e157bbcd59f57e1b6726d857bff0c7c05f784fea4ddb6d39a7892a580450df8d854448635b30a	1622219389000000	1622824189000000	1685896189000000	1780504189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	142
\\x53d9d31d2e5469e8302ea78c5e155be9534883a8906b72ee470c28e7f8c86737fd3cb624e09ef63ba404652e521386fb6b1b7b4f1956ce2aa50c5d5a35113f3d	\\x00800003b6ad56e08370ecb6cc98154dcf036d4421235415a9747a4d3bd63da700129a71dfd41e6db228b2f543ebef2af787ba050683e67f359fee560f1fc32c929d738a3acd04cb2788d0312caf843e56f16fe6913b53302b145845ee4f7facc8f27ad59db11431ebaa2f134cf06c809a9f7ffb3d2fcde9195f66b97ead9118daf05b6b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8561ad0aedde5ecb04a516732a60abecbc24a80efde4511332ded9b456e7a1ba5c0c805789108a32dbb0a45a3e5fbeeea6d5505ce77a452889c70917685c3209	1629473389000000	1630078189000000	1693150189000000	1787758189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	143
\\x543191aee39208e279938b537930530737482f39eaf10b981a31bddfbfe93ed03ec7ad2c83dd3e4b746bc7f8e2b2790e2379e006d47545484db777a9a7373a24	\\x00800003be8e3dad22e7b9e7ddf3b36254a1974d30b981a938783b5753715f626e056a70c0b02ce2353eaa945dbbe6aa080ef7500436155dd9e3b9c9d0dff31836a964421ede5d8801c7b064e0d85b08af6877c306b26b4b11cbad7f170dcceb788948cbf0077e1fe24a9f283da6d826ea7f7217b02c68d09dc4d664e00a53ca542b6e91010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4d18b4061ea07b46fb117901ed278bbd1aba5de1cea37fb4dfb1c76256e53450663582f9031a4a09636413893aed12ff068dda45696c1fb1948799104fd01407	1610733889000000	1611338689000000	1674410689000000	1769018689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	144
\\x55e14f7a659084cf18fbc07a632631032ab5dd47c15e680d73caaa7821a9ea93755b0a4ece11605baa6f3f003224289b94bb058bc572a1916832e6ccf1aadc6e	\\x00800003964e7a4c2e80a7e590deb51f3357930baeb41b9e6343491c06abac4198436ee09cd8969290fa41b1e511a08a0d4ac0e104326c77f883b36e9259df0646d78e1d746c26a35f5522782ed159095b4e5c0333849a36fe0fccfe2ccd813fa597acba4190f2f5d95cf47826d4c250ec99b9006e75e1e364a640cccb73338bdfaf4541010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x907513ccd4a6dc229a057bba3e33a5afd95f6e289322fa546fca3814c3a28f4c28ae62a0d5ad807190376f9571d67a2ad6cb08b31fd07c3e2d706dfcde586e03	1639749889000000	1640354689000000	1703426689000000	1798034689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	145
\\x573d4c0c69d01e3dad7995f04fb7fb8354e9effe63e8ced5fe160ab9d377dcf64ac88c18d8d2cf89bd783ddc29b4f0b16f95ab37780987aa001ad7642fcd6866	\\x00800003ae2080bf0f2a02ffec11e5059bb6ccbae0272bf9bff0bb6817a9b4b9ed4cf5470479de00af9b2271a3c480fe4aa95364ed2214b4e82e8b564ea44b59871c27b01ed1f321c688f88f2671b3ad7c7d7196037fcdbad3fe7c4da3d0305bcc49ac2377bab58cf7413a1a1d2ec139fd26c139582d8e491406941124352946ed66c877010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xac67d53750bbb9766c4d54b2fc1123a9fba9ca6af3cfdd2ff12225d57e1af900d2942e0dac6a4469cc7b9e5a4e28ca47d1ced4562845474586d4fe17ed53640b	1614360889000000	1614965689000000	1678037689000000	1772645689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	146
\\x5a5120d8074cadf5f3f84f31eb658d7c05f474097b7d004b557546ad6ae88f7e5ee92dcb77992eb70c25db5d596c02caa615395f7c4a1b95861482fec416b5c6	\\x00800003d18e6c2709cf068912334300ddd65b455188f2c9b9c12146381c8a4151dc8477e138c117012e34dad9c837346225997b9ed48b4cb0e2bbe4ab419bbd3e06ef1f7c6cb57c38e238a374564b81b12a2b36e35a92d7cafa2a995cb4cd0af1621f9d576ae8314aaa1984531694a936e4a2d7769f966bef526942e15bf50e8d9c3279010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0263952df4269ac3b1ffaa973bb7c693096d13f68f54ec20730a1cbc2c243ab72390df553613d388d019bd77ec9cba21fb468c32e3e08c393ad926cec9e39c05	1614360889000000	1614965689000000	1678037689000000	1772645689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x5bed760b1f4531fa75c30573888dce195f501666146239fd0145437acf87652b5f8a493710eaab1e136ac2a5978bd36dc0c5ebb291be1881866ab97b933f915a	\\x00800003b44a3bc82e4fdf0d020208faa5e69fb758f57d714bd0d9fa3b5600abaf12dd7a797f49dd173d03300bb5d716d826bec3492ca8c912ee0860d1de43e28b42fc0ee000b5616a097f7adefab7688ef30d225efdb8ee21c0332628aa354a444fef971da7e5dd9319b5863f5b8a0a32163b05fe6f2c8c95dd33ee51d965c0fa26cd09010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x12b0c2911368ce270c51df74324a083d7eb887093260a23ba5d3a03ff549007e3c94849658173404683f3743bfa1683abee8cdc0a78f0b001738511b566fa107	1619801389000000	1620406189000000	1683478189000000	1778086189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	148
\\x5ca509a40c394d7f4157a0c8f4656d59307ebfa5b1d9425acf04b73cc6f59972ac352c9b328f294cfcd15eb7b551faeb947d8599f98d6acbb457afc87fd57fa7	\\x00800003a2d97c571f634289c726f1af356fda7f3d0ef9e11ee309e87503c2020d41f516da97f1e49402f3db5e9c3a88a489f4e870a1aaf04846af80832173aa534a39647ca35efb6d6d52e9c25f95ec86bd1f48c9b6813b059f885a4d07d25febee03644731516a10f3754a7391555c9fbb6e22353517e57122b68999e0c375663b3de9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5e868fcd5a6e415e3ac1af47c3e714c1c6badeef99f8e513c3c0eb8c902e4812de61620a407c18a04c8bc5b3bf70fb0ac54f4a987e1436d5a4d396bb165b0705	1640354389000000	1640959189000000	1704031189000000	1798639189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x60498d5384f69b96f52dd9eb512e30b14337a33d959f6958c8dc3aa293501162b4af871c5b9232ca5354c1b784c830aa3b699db64332ebf02123f9b8299628f6	\\x00800003b0bd037a0e64b725bafc39c3cda26f65e33a3f9d5f3c96b5a64348c6d4ced267ba33fc2954e5b5b13e3933793df43f6ecf79061b795ae4b55e8e6ef530e27cd13a0aaae3ae2c25784e2126967b5fc136e9b2adde6b997c2b04389bfb2e2b492c35e4a01661fde9bcb49544d53a13f3684365d66787e36fcce8c9c06ea52ded13010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x496148acb00104e7ac9cb3b6779f077ad87d6b11dbb38bbc9000c56fc8ef29ec8bfec6ea5532dc9907d4acaa84fdc126af44a1172104502f4f44e6ff94de4405	1611338389000000	1611943189000000	1675015189000000	1769623189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x623933d0b56358bbb3eb517766cfa5e6e14293b6031fe87c3dfc861232663f7d9176e821fc92fb14248f48214e8a940be94d0de8eda7b6b13d529836f1d5afa1	\\x00800003c555655f55b2e715dfb0b08f1af648ec0724ae773f1a2de0d8f406d9bceb1556161b0125f76b2c4a1092fc877dfbb1cfc3e15115b007509ac5ec4b4d58172b93caa66c0024a433320c20a4ee7da93f3d042ecda5bf989ea87b0be19733e747da518a4160a381587ba1c2956b08985d38caafd226041798ced9e6314ee7ccc4d3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbc6f73d3bec6fed6cd9b9fcf053041345ce6ab1e8c74e613b11cc5dcc4179f10ca965cd19e10a7c526eaa3df752828ca45d1104cf90c53ceb7849c363069a802	1619801389000000	1620406189000000	1683478189000000	1778086189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x636901afc5384991402d88b45d61748d201cb83f3fff163d2946a3fab3630902a693a048aee9ed2610dc0c33cb67f5e3de1d68ee1dafe7b64cbc3166296220c2	\\x00800003bc9452b250f0c4fa49c8a51b0eaa1ac103a58149783f83dbec015b1e625decdd13fac5651fd55244ee186199b6e0428e8218a375707d8738fd8a4f2412cf52c088f25c14be1e5a83a736796a8e67ea7046bdda72fab50b8e9728798e50b25ff588d499c18d4cc9a8593a8429818859398fdedfced8d6782bfe519f7c6b5ef1ef010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1aa2989a32ad33ede54fc2c0f4b62c5cb67d9a8400cd04d546846b2a6dd8b5236f6e30bbd6accadd825d1603674f2bac8dc2628f7d4c20a1010f53522171a00a	1632495889000000	1633100689000000	1696172689000000	1790780689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x6375ed7e61e111eaf6247553edff6b57e30ee10894537a90cb6bbca773a124589ef8f8031a9fb557a2125f7b6e0876b464d713774bed1a75f0d4756892aa34f1	\\x00800003a2e8daa41f5431a9f062514f06669cf84a0896f53cddef9e112f0f292906be9bb34f4e4c5cdcefae498b5f4cb9315740dc6d0abca23510ecc569d916256dbea5a6c40631d859c47392fc8c8129d11e870045fd8e93008720ad4d0a224b0d8a00023b097609c1eff0382f77f262af39c88659360076002bd85ab74c35d23d46d1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x49cacde696c5fc8dbe088a90923b44c2727803da383ca91a05c4a8ef1831fe7f2496f30bf6b8f1e0487ee05884e369456d875a3d1ba6c6db6d40d360cbe05401	1618592389000000	1619197189000000	1682269189000000	1776877189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	153
\\x658d64e59a3fbbc6ee7cccdbb91f7ed710e4dec44dbd12906ff70d2a3afad0ae2b4c66da8730a86f4b856b396346273ed37de42dbbe322e07a483a0ef5616a52	\\x008000039cdd4eee6bf75d8f5050f5d8105441ec8bf3c68224962816998b21ad497cea93f60866a667ab8d0a6b441de99bb91c368cda9a28c78a7d3d8a3065bd2b08cd884572c07429ff879c38baae2b395b360a77d2112e22682428d92c43ae18b3e15829fb9344cacbd3f505481efad45ab694984bddd831adfac07ec6d46b8a9ed6d7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x67822e4525b4d0c8552e8895d7efcb178312f7bb4abbfc097f30c580927e6754a9dd6444926befa143c38dba3b696f17c51f9c07bcaeadb1033dd3eed099ff01	1622823889000000	1623428689000000	1686500689000000	1781108689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	154
\\x65b533a030cfb6a60dd3bd982a9e028eaa0fcf6a75f77b346733ab2ec35bc0fc397f22382cafda10fa426ebdf1a7913e16ef36c2fd9c20689352dd62eada6e78	\\x00800003cf5aea196b41c3124b867385dbe2facc4914067139e2d8ad48ba09e9aa76c9523f97c3184b26a05be27da5dd2b1632b1bc669493e3dc50e8a86ad4efe562957d5d9ae09ae2b86ee21199d5d832704b499024ac9e4d533038ab7fa56d4078d90db02bf6e176ec0e7b4917c00b3de2077aba76c8a449d999efb50d1f608a4e8967010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9b6b5550b58bddb8b1c94778a0cfb075eb63bb60123db280c4667f9602633f5f8c5938dfd6b42a6f65fc9f776b20487e1b3f452c168269ff508efafdd1358600	1611338389000000	1611943189000000	1675015189000000	1769623189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	155
\\x659db9fba0a58caaff63cd0cb84a657c2221bb58956e8dc4f8af9f1f0a79ec26b07a5ec6cc1e1b67680bfa39994837de5db52315c75cc64274ae7cf562b15275	\\x00800003be3805ec0a90ed0b7f351474ec7e7b0e3d59a84ddfc3fc615bf80650b9bb815bc543e2efb09fffe5faf7f7a117c9f271b404942b8413d31d49b4335fb8b91d235921e7900654f5224010bf68cb7d49a2fdb8274a66729d7fafeba409c4fa917a74119a3b41a989c9fee9db6c1de0a3cb1fa13544f0bb7d1587e0414c9ee18181010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x07a5b559c5b411b8a478191007a9938c2089b6988453b00589a91c80450218e7db3e2a16e48aceedb5c7fc494727736975423f77b787e328b6ab76764748f707	1627055389000000	1627660189000000	1690732189000000	1785340189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	156
\\x6e7563274949d468ca1ab8e8ac6f4414b6aa9ec109b620968d1e1aff9e7ba43e13f694b4e78d4a486f40f516d61bbb02574d9bfbbf1db1e430cce1cb44425d79	\\x00800003d9cf5e8221bbf0fd3ac1829fe9705e863fc9f715b681071252146fcfc0fa36721f61290bf9db8d739ba0e9b796a6eadd595585920a81d0fbb7dc8a61f14b21cdf37b275d2283247abc973ca99f758861ee9de395bcdf1d7952e5c767543cb47787264e3ed7593a2749aeeea431a4ea8015b41531b56759d6c18bdfc6f5e54d57010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x698d57e9a0e272e2afa29035b84cbbcbacfa0e7fd77656520fbb351060eede1616329c18f3e5c7daf039cba64a1a66ce29ad0990739aa8ee0bb161f97a42b202	1625846389000000	1626451189000000	1689523189000000	1784131189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x707107620cc7f79ddcc49ce98f03aac04b97a1921215c00d8e5d49f15e45c41b13ed90be198c15d460437d41b4c673cc4de150b3ea4317b25207217d77e3e104	\\x00800003bf09b07ffa249d1280a840cf10c18455394d9fc83ae25237303def6dcc08a66ff994e2335ead7d413f58c025ff60e6c5f6ca594fb6865574e5b18308b3f7aaafefc98aff254eb1b0604952f0054d453bb6fc61f18d8ebb7e2fb89815e488fba12c9c5686f4fc5bd91b5a9f7881dfe0b9397f55be082a5063e689f18c2cb97a9b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x54184989c57af872823e567c6ca2b863ec3ccd09220a402384d3da5e303f4d805b6705f0949f06f903a816d4cab6965d1b53874f3b403fcbd52460c828ad2102	1614965389000000	1615570189000000	1678642189000000	1773250189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	158
\\x799547cbe7df49d9f8db8ae5849a905d2747ec3428d404a07dc4bbdcc07c8ce713729466152273452ce526182fcf74c68f2d545dbd548855ee89e82395ca6b8a	\\x00800003c264b13606fd3e640decac662373af1d78efb7a011b5050b96cf445bee6392365df25bc7f3aedae983d9ec46225c548e639bca97e9c211a09b22b97308aae1226639d641d1e98c810895a2d9f099c1d5d2a5734050db690baf7396e5a7edadbcc97e7947ce8e665f0b25c7b1e83930a3b51010c7b99301335aab95e2f2fc6de7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcb61263af997f8fd813c9239268de1ce7196e6ed2917d448eb5d5d964251e85636e9c61c0a7a4d58a044c6bc62568d8853f3109b2841c33488f87ef0dd8e1805	1638540889000000	1639145689000000	1702217689000000	1796825689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	159
\\x79413c4f3af37ad9edc9ad1faaca2a15cbac1299c9f71310d8f7b1e7f71251193e860943916b9fe9143d06700b2746e8b4dbe64dc145758463d0d8821d964aed	\\x00800003c99deb4e81964f125629be211f8e23da20c3e4ac7cb6b217a69bc2b59b5d2c52d4dece1fad77b295f7b8873a56b5b0b134341edc0cc1c4c063aad13bad4d02ef3fe6bb63c0edf381d16b96e2ec5bd734dba1fc981736636a37c148ab74bef3e22b0f87f18aa4737b104ef24515f64cf438b987b0c5679def67e6672fbc923695010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5c64a5c55f40531e5f562d2b92938e59aaa26518101e2cda85ccb34eaa788cb99f88f4e63a4fd4eff996643674e29a924dcf67174c00f45f7b691e50211a7d0b	1638540889000000	1639145689000000	1702217689000000	1796825689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	160
\\x7ac127c298412901d50c5a307321439352a8ccb8e9c6c6cbced37451202ff615e2fea2f6cde1dff8eb1d6327777fdb06c1f9d4d302883bf0b2261dc3b2127abb	\\x00800003c4aec53943fed3e3dcade94c1cbae4ff7baa44bcf2577d9eba4f5e3591c4e8e5fc03c48d432c8afc15ada600d097636ca24cf9e2bf09fbdd58cc6c2de273fecf7c9db4efe092bd602dd963060284a0d0b666301f8f6d9edc94f804a25312ebc35e2ed4e2ecbf0ef868816539ddda2e98331fc77f5e605e4a1bbab89ec4489c59010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa98b1ad9e87ac9a5dc793c0e98b1b064fac0defa1c9dc6f5f0ff51828382ffa35f62f88dea377e1cffd5131637d0e5f9a3f4e1209a3c1064ede31217d0e50a02	1630077889000000	1630682689000000	1693754689000000	1788362689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	161
\\x7c3d38a985b58843a31d49df6967a642560860961fa8a404659394e12f32c0a78aaa90386b780588fae2647b7e4fd09b90e7f2364c92ec6ac44e9506de15ab45	\\x00800003c9ff6481de83b74bfc9cb173ee68a0bdfe387db829d4b33f31a149456d1fea6fab317ed8aeb83c11b8f6fb19097f410dd6dbb7c7fab47612c6b67118d1f4a647404666edaa957684ac4da512de174d5b07ef6c89e30de0f2062ca3fd4f99618a0645b662317b502e8ac7fb2334e4597a929941a6b34cae9b52e4f72f018e9217010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6db5259e2de6f0ade6428fd9010828d61cbc2080c53e92349fe37773a8d3a062ce79e20df91fd2e97173afb177e1a712b54b58aa99f0b1319cbe5ecaf5660406	1622823889000000	1623428689000000	1686500689000000	1781108689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	162
\\x7dd907fcf5833149937bf3125bfb62d9262f4ed0b97ea12b4c190320508a8400c85228e642d106f2ad7546c38b940c51dfe1dde1f76127725526fbf6e2e42dbe	\\x00800003a5816f0ed39233d15a12ee6e649152746f0e00bbf470dff0170e7adbaae546b7181b95a74e820e13df1fa2a9514f9f21ab1353837587f5153fd368cae9d4c57db0c9d9de4c20eed1a31fbecbb23b75dbe3a73197db02db8bcf79cdd5482c06eff71d2b27a75d4f3c0556043e1642a4002589403d40eacb2aa5d4aeda46b0e0d7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x85c13ba005d793da3355fb42a548039c06170abb3fc2c79a92b486e9a7e5c7c94e52a5c7c9664b7d51799cf8f7b5f138c063c5245de93e3475bf7ece1f61a007	1631891389000000	1632496189000000	1695568189000000	1790176189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	163
\\x7d4d0e477336f9b0632d45a2e87b0c9707a194b9690a442c480197a32456df2ada19bf23af8b8ce7efd479abd6b536dcb420244e08ea473c72e93c983634da6e	\\x00800003af8e96dd87e1c3b3194c5905a16173fdb3690d57782ecb6d2d7b17e18561cd02edb62eddbb93096b680ece505785d4121ca5c5e00185e1860ff2d14405629b33a64fdae1b898fb13405c3683300b1ca6d6cef4c46d7df0e4c8dc8be6b0a68e12c91869af3fbc52c2c12dd88b442afef8ada3f0096e7caac6356f608c098e4987010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa98b66fd82ccdd60d4bcaa3f3fcb0a07be8b7da539f5087f5fe7d4cabe6f90acc00bee755645eb360ba49e6eac397a1c6f56f435553e78f12137ad22affcbe0a	1624032889000000	1624637689000000	1687709689000000	1782317689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	164
\\x84b5dea55b780026a9687daa342d635ddaa9f6fa98e3245eaa4c81214bba3f9972cc2fa7d165757347464a206570b3ceaa29c372b6412209cc0f7d28a4f403c3	\\x00800003aa27c36fe033ef01ab708ae90243e8557ba6cb15e5426d06ad91a2329fa36d7e60382332f62d98866aab07cc302b82b3444aba8c9a3b4cf8e5ad2c762b78684d9bc423d464c4fe7c97144c7b661e79c1f36aa0221b138f0a7e4ac7edcf6681b77f2845aa4cb00b73aa56046d6f7f8cc1dcfbbbc007a6c7eb54912f992860c1eb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6eb5de1714dd9381f6dff9e44b8e8fa3bd2c32f4fd27c79085527929b459dd71ad94890e8d49d41faa33bcafe63c390e452e686db4576948f1553ba38475850b	1628868889000000	1629473689000000	1692545689000000	1787153689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	165
\\x856513371c37fd5561e16428a9a5643f18c591a3dc145f4be1eff2a84e6ae01a09172ec1bca4ce3daf2b524db54b8c9f6bbaed150f86f98a69320230dd03a78e	\\x00800003d46bd5275d0746c08a138e1275d5cce8807e31647d627ab84fdd2addf971c473d496592d16f9cdede00bc72c22f29aee74fe72571feadb90f414a4618455ce15b0222c1edf8e7918a22b74d313aa421e57f938c8103399cba62616ef45d16fcc7e16ac283e39a5b9b09c4c48ba72219043fdd79ee1f86f4bd8ace1d0745f0411010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1877661efe86bdd796750414231ac26dd8569f5bae738a0315830a327bc302cb1fbab0f05a30292c79fce641ba997418cd9f91367a7f82d2de001b7ccc5fa80e	1640354389000000	1640959189000000	1704031189000000	1798639189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	166
\\x892958fb13f35210a137a49e09379cfaa626be33c9834afde2e83429ce94fd43abb1ecc13034e700c5200cf5bfbdda22f8f89de1c67ea1a8228c2d90387b2b34	\\x00800003a43a0f1c12b87ab33288a61a80ad59b11e36cd09bf794f93c468e0956a1dcc37f6b8e05f066df5da55942006bc879ef7d74a8b169ff138bec382e55ffaaa5817f29034bc77c52b423960125efd9d86611ed52a6a0a892bda72d652f8acccab191c296a822a21bbe4065043b4df777d32894038ef24850097e30867b0df4ab04b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2d94e164523c40ca3e55bf8d1f5cfc90246f45d29e084db58ca43212f6ff493f2cd8d9b4e0616655b0076728fe1d89f2e4c32b685e03326a7cc6292c30b3b309	1611942889000000	1612547689000000	1675619689000000	1770227689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	167
\\x8b652bc8efe87f6a10891ebcb8d35398fd8cd736c6b3a2c3e0a47ef837480fbd2828679d9b309d80f3373e32f2eafc85e33907d3f78b49612ab3c77cf4744f3e	\\x00800003957891b14b931ee396a67e9cf7570a423d06cb2b6e8795f57457ea5ed26a7de62e1f3ff091d5eff648a1fa1a9f88ef5f3847a2ef94d3b5c4a9bc335018065ffefe8c6f279dbb9d32c17d7b578fcdaea1b1c413e8e9e701b4b91e3847596c6e86905efe28bccd1bb58696fac53bba616d96be770721de2c59e4cabb63cf38e437010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd60dc38bfb36b213d7a1e1169cf226163c2c1237eaca2d54c9ff85fa942ae5faacc4ca1cca8fb9055026c4efdf4b7e63e24deb570b1970c94cd2e68ec6f3f40f	1616174389000000	1616779189000000	1679851189000000	1774459189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	168
\\x8c11aa100604aff1141ac868ff394f370a6dbe27c3ab4e4b1eb7ea73dcb49aa8ec48d060281216d7ff0c6f1ab52e6f896d4eaa6b008aca96d629c73651ebba60	\\x00800003ac3165cb1f29d35bba4d2f195dda3a88908dbc0906eb11f235dc276849db489b00e7d33d2effa140bae4a83aeac63c8bfd0efff735a45af8bf45e52d0b184e0503d6905a6e4b8b49b9b738ac7b223c076d6ff792d3c6595e1459662b664075bec58e5fe3d5565dfa6b744b8fe9ed4b4a9832915a3e196887be282bf7b8e00dbd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd99f2476e38826f9d68ee325c7d5cfe7d1e8ae379ca103522607acdc4d6f9c1d01aa9fadec29d165f5bc4c66debab76d44914787b9ed20a37fe57161c13b5d0f	1625241889000000	1625846689000000	1688918689000000	1783526689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	169
\\x8e05615ef9a306f4e6d1add8b7dc1b53cc08beb169610051f2e10d798b54fae9de17dd282857b817d8152b98de1c6c6696c49c9b99ab004845e24ed6ae1fb981	\\x00800003af9cf80165f67f7b44d9f0b9bca42ce7c26e7fbee06cb1907df007492793d6cbaee84656018d7ac04197c70acef640486d3f6f7b27d6a3b95bd38c98e875f6ad86dec563fdb55cee1599cc409178c2136767494df7a931deec50490eb7eb4bb1108137597149b8d158793f42fae4b4a014fc4adc151a19c43fe3e7c8a82419c5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe5679e604f4af4d3c043af059fdcc8e8e1a59dd742a249e53d0115272e850300c1c4ebff2ef0fb6c9ff97a701621c2f4f6568ed518ecfb920fed380209ba6c01	1624032889000000	1624637689000000	1687709689000000	1782317689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	170
\\x8f514da2f6e00d0b78f1ac35c4db2a8264931c021b876df277a801cb9b4057910d32b9298505a2eb83fe7d89dac437e9dae5ac367078ff5cee31b12e3d0ac264	\\x00800003c907ff76a37d6c48d50b3cc9423a8745350a432adc7319198149f5dd472bd134546368f3a232bfd8b5f996ba0f3d66ff26501b0d5d588fb2ecef4ab00775bf2da717176d6a1fbcd029f4623bbf438ccacd3637c32e90f285ed440137f453f8e8543b8d569fd69f346ed90f81f778aa7ae3f27d3760f86046b7e693761db26c59010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x91446eabac6eba98def88e65ac7ffe341205348357e61d29e9b4bfee1eb8d9d1bb976e14aa08f96058da3ed3ec503909f84b4d440df42e0c300aa151d40a0804	1636122889000000	1636727689000000	1699799689000000	1794407689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	171
\\x9245016230abce30d69534e7752f108bf3487a42500d7e6469caadb47bbf46883623385612ed71111bc56ba81bad540754a7951530d7e516d0cda7847fb32b5b	\\x00800003cbb786ee06d30226411bbd5a380d27ef29565be316677067ee0893d496c51c2461e933dd46d7c369b0c213fc3ad78dd2862276616c4f715f2142e4a5666535e171eaceec2052ace913052467febec54fa4970d3ebdc3927b7b5d66658219d1772bb7189d20cdaccb612d5d8289a38d6bae58b203d57f5d88ad5a62736b566d27010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9230852b9fdb923913ad7ac75cc0cd82e4294c1d1c020bcaae8f42bf69689f354a3ecd99688e43e55ac191b8ab84264970f4a72bda1179dc0eeb463b7ccf6104	1633704889000000	1634309689000000	1697381689000000	1791989689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	172
\\x95c14bfb9e8aec43c716db0035aa1d53cd06006795b84e3957e07729ef83b37dcc27a42cdf005892efcea286f82e4012e9be53ff3f55c603723b03fd95647756	\\x00800003b0e6aad9010a881b802b4eff235c1ebf24bf46999490cca0f548138a310a1a7ca17d0c912d2a124d79d2e25d3a1e238e6e51f1e868cc57dc25ff1002f85df2eb6e1f177e7f750afe1c042c79d24d25d3a137f8ecc4aa04ff47dd8cdede619738082fb5cb62051be458c1463ffef4378378c55d69085938a8457e837289e85cd9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x62a864093a186ccbc978f6d54bd13e245f9701d230723f6aa2debf2f50c5252a4eb7b220429f36cf4fdf0a52ab4f2818cc784fc5bc4b0154d0f64896c14fc00c	1640958889000000	1641563689000000	1704635689000000	1799243689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	173
\\x968dc4d86ad1ea0a357e847f14fd93edebf44fe03de7fd9b751ca85118c5fa6cad0c175e29b022e888c242478f1de77e253be71310d58c1b18033c214fe0e2e4	\\x00800003d48c0e6626c90505d3e7d227290c8b0e6df0b0b86d78caea9cf756474dba6bf4157ebc8237e43ad65a12950ad21d161d95bf4eef9f9f98a18c77ba3a54b93f1d1031006cdb43ba729eb3ee268a3ba53d28fb7f8b420f0484a4a9cc461d3ea674b633a132d29eab50d91aaf6dc080707c3a34c50f11b60c4a02973aebcbfc8691010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x60c0e94ab4d857e993c0ea08f95d2bc89666c1c6a9d344b81f87c4cba20b57979443c0fe316e3590def84df7280230fd93c75e2716e935ff6bd699280f57c909	1635518389000000	1636123189000000	1699195189000000	1793803189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	174
\\x9b094902f10375ad4e67db3fab2226f2870d3d798e8b684d0f0d9b4cd49fba96debd315394dcd0b74cdc4f99530e7eba29baacc945b8e260bc8c7d4f5c6bce94	\\x00800003b4c4aa1d5815d1e8d9a07ea682ad46945329c723b638041139b075ecddcafb7e03e61f1da59890d9859354c9be5e21b52a4ba85bc57250c911f14dbb48fa03e93121c9c2ed0bf386401672a3a3a27e081db3c5540c309b5c1d93164185560853bfa53937ed898f01f25d1d23bb02191c937c87d0292a29c22a764eed80e3832b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x554bfb8e2aaa22ba1c4179d0fc2e98ada5144684569857ace3eba794fce9aa74823ddfe3ba2da6f490b99c3c35959ca1c65410cc07536a6da7c0c2448b64580a	1621010389000000	1621615189000000	1684687189000000	1779295189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	175
\\x9b214534247007da6286f77dec06bb1d2e40811f51cf5627771a50f0a2660f360600d0a2fbd17fca7549908507ffb598012afe45ff958c22596303d400304071	\\x00800003b035bd9419a8c206690bcb6d31cad201f7fb8b31973fcde52ed5dd0c9a515c5944ccd2e04b5b224e99cf28ec35c110bc6de6bb22825ce5e28dc12d4ec18c7c4caa0d56b99f785838f61d14d9b72a041d7080f4a1987043adde8b22ba5de08fb7d3f768ce18be0a0e032e754e54227d006d112945058e375ef45e92744e032ef1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbbd3c35f106606185fca050f1bce40aef0fd365ee8f5b76da89039cb60cfc7b9449380a37ffda81c3ce779a8f3fcf1a829543c4a2fb3fbf1179afc1089bf3e08	1619801389000000	1620406189000000	1683478189000000	1778086189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	176
\\x9e1de30630b09823d10c95ee999f7d80e854ba0fdf05a5ece71aa53c07542177a26838163ce504e8c8a2305332ab11f4b4931f504c6433f67037e874c65ea21d	\\x00800003ad4569f9bbf5e0e346c093cd3fc5c37a6641ba233523de8a25295c0a4d58444193f240e09941a6b6645e290a8df8082ee0b63925d0a22db783652d50213ab7689492697902a992d456ce6396b636eb214ed61741294a97c9354b1c645500590c528bd6e69c5e717a5c607c6d396553c1671af9f5b4541fa8cb617b7e6f02fb9d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xfa07476ad8f3b1470f59d2b6e207f222852c17aedcbbfb79e6d5b0fb489d2c9c4dfa4995edca2cc5ad88996e6411fb898c51815e5b181ef6d562272e9a8acd01	1628264389000000	1628869189000000	1691941189000000	1786549189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	177
\\xa0911534bb2699a50c4bd22564d562d56a36f6c3252cc5c484e3bf3449cec36a111375bddb4f70d5747d917b8eae12a8538843762f99a26276a9004a97a95e87	\\x00800003ee5c1a05d7c5b732281dc4082ad7d510d1854b1973c15e753b816c9c1cf72a8361ad39331cc858afed81347521840545e274bf4b49bf130caef5df310c3f3b173c0e6c188e7c090243657ce89257209e28728c33e78183fd352d0ee41a14dec9b1454a520d65b5cf46df41a2d28c91a3ca5a11b0a7eaa070e3d37b4138d7a5fd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x990c23ba3c59496abb8ba3be930199fce023a7ae605daa86ab1d0d7c477c89baa84072fb3b19b33f97d0887f76b274dd62d108398a8091c3e99ae41e4f837600	1612547389000000	1613152189000000	1676224189000000	1770832189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xa0959158a0d08c59e6101ec177036ae18753fa38ab731df0c92977cd4cdb9b16ec13e6bccffb01891c566d631175b754be08c1ca0e562425e033d2657aac3e2d	\\x00800003cbd44acde6c832d917fee3d555d5a2d9f7ee6e20fb0adfb30da666a3dc6112a2075e0bbc6be339a514e39c93dbf185b2820fabb1a7023e360b4de71c3ec26cc63be3093ce00a2c34deca118d7ecbde5078a2e9ca1f1a7d97ae151067ffbe920000eef7cf4a57961505a4bc54e059a03d66ba798b0db2fd88932f1adb11e16015010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2c5cc3bc719104a76733cbd271151e5deb5cac7f9dccbe5506511ed655d092a92a3ddb3a7541dc3e4c090eea15a8859de00b6ef5e1ac9de7dec1d7f15f0e9600	1611338389000000	1611943189000000	1675015189000000	1769623189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	179
\\xa3cd0bec3a7523b6be69b24d78536cc54841da2215e94f92959f3ca117b9e38093cf7c43546fc7f824fc4112c316951bb64362704e61b1935f567c8fa7a094ab	\\x00800003bdc2e723a3ecff683426427c7f4394eb173cfb8a4960632dd47a97bd07413455297d774516bfbc2b2dc41591673e9a115f957e2d6b68d97827fa367c0ccf2358de711e3a9f87a2acd02530189eb2063ef11f9aa43c180535e65fadfefe28d0a34f401a13409af39cd5836bef8ef2d83192db46ce759aad17a24a2ce1faee425b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8c829f9f49ac676eafaa36efcdfad2bfa26f9b076fce10ec32d20375cdb782ea6c6d9ef7f6b817006050ba9f4d9a74ed1b1a8d017e85dfc23d04df95c0746e0c	1629473389000000	1630078189000000	1693150189000000	1787758189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	180
\\xa53da78a49d9951a4dd2100a6c099a543e05576fa6c0c0ed7781573f498d19efb225906c7ed4e7ea651060c5fb0d17275dd8aa8aebb0ee15acbf3393198b2165	\\x00800003c8234a98b8e79d438efb5bb4f1426d227a00138279b058275cc8c571efa8d5d046076a29d6001e3040328b8ccaffebd24ce6e38ea344d4f284504689a2a9ae81e54fc975a377cc44322a5380e1e99d94979615e4bab8492e7f4fff19cdaf1493667e58179cc5aeabc730d969deed159ea43ca767e669da7e6894be81c930c1b7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x491bd75ee7b4f8626fafe522e59e33007077d045a25331ba7c69b2ee6ec5a4e4425ba1ee1bfba566808f057206e5df2b68098e7248c68cfed4bfefba7bc89805	1624637389000000	1625242189000000	1688314189000000	1782922189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	181
\\xa5913cce73de71d7c8e265a1481a4421e80a614f56cc09cb232297a6fbd4537a746327a57cf8f50194b63f79eb62b5bdced4571b473e692d1b573569ddc15a3e	\\x00800003ab74adc3ac0c39b4e7a7c9df35a8d2aaaf948996658866689591262ceae75856ea803f7a09729bb7922eaaa2934c1873d5d9b81dcb5e2d7d2da81a959084f113deb7cb6f003360d595052d9c1c736f556f3ff23d05eb7cba4c172a35f722e896572f725b9652564c05df082810e8b40f54fb1faa7f9363cfa613be7b5260e411010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9e69bbe614d0b53a145336bf42835b71fd1477f6603f4b2d0bdc6f20118687c790f65f09c293519550f26ffebc0b703f5bdc8be0ecac4d6c3b1536b08e833b07	1632495889000000	1633100689000000	1696172689000000	1790780689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	182
\\xa77595e4f4ee82c80c3443518dfe0d878cd45644317f36ef003e28f8829007ebf5d97510f6243ef7799d3db6c7ac9285ce9631cb58917e51c766b0f552adbbe4	\\x00800003c09b5ff07a54c981186c8af305c7d8b40f178bfbab636b4360bff73c6a817348f5ab9186d2e40b4c0916dde2ecf7bd5da4597db5e14568db6f3a69933a37816e2e90f8ce7c644648d1a3aaa6271c4f87af8c56c77bdb5161afbd76f6f4c8207b578fb2b22f1a451950c9f7a87288388b2bbd7c2811776ac815a99c00237f438b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x907e94a1fffbeee22936d5582b117ea83bab716bf91bdf0fa56adf6540ce418ba04ffbb55cd7f529ef814268c49138b971b9c3fcc1108a65cb0340a144921a01	1634913889000000	1635518689000000	1698590689000000	1793198689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	183
\\xaa395c74c9c879524af0cc397486df8cb0e4573de86259820aaabacaaf1022fb7ed34795d0fe6f99c5eb926547e428c31493f31a1dea30898fde5e44c0e596f2	\\x00800003b591764f71cc20478d516cdc86f1d818f6800f685cf3f86d7472f7842e8438fc68739ae85e39ecb54621c51b265d884fc70bc77b571275c927b9345401353d68a71a3c6b3d02bb764241b2255ae8bbccfd2b34d2143a45a07558c7a96098b84c9a62f17e93d7fd9c4ed262b960c705c8304396747737e60089492a8f236148f1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xeb4be60cba246add9e0851834ed02898d7e79cc44cfc99e388cf74de84013e694562fb8ba0bc2dfe044bd38eafee5be699c6c832da7d54f3002a30bb10356403	1637331889000000	1637936689000000	1701008689000000	1795616689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	184
\\xaf258ecc0fbeeafb9c032050fea174453b03ca3a7d7153d9579bb81b13f4b02bcb05be0f3e2e8421af2022342b16a8c94cb577fe213e48c3a74ed893a30821dd	\\x00800003e6f7cf1310cd3c1634562f405922dfdcf5f785ea6052c7c8fece039187fc609a05465f78510997423514e1f5eb7bb91630b041ee8ab01cea3411e4dfae1ebfdc87afeb5a89ba0f781261909cccbc44cc30d5b887b8f9a4e62077b96225c12c8bfb3d92980d80be5129cdc42db4eefb449b29cf1dabbdb47238db9ed1b70213cb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2a6402e421d3ce54639e6fe3e8d8439ff5e82c7437c77a6a6ff5932616b90ef01a7407c1242ceea35c154705bf93909e37805df3c93fd61caa43cbf2dcff8801	1616174389000000	1616779189000000	1679851189000000	1774459189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	185
\\xb0d94c95eb0446928bfe0a9e7ce7aac93a2357952e7c600c2183466aa67abbd705cc33fc231cfd9134dfd35f263094af1ec0c18b4c337ab42c6d13a002305423	\\x00800003aa81598d10204c83c921e8d2a1e9a8845a4bc7153e3400620bb3f740f03c742f7c6f4043d45e67253e53327a3de192725b27db89fe14c74cc23cfc48d02498adb64a29ee1a2f796aae092c952326abf045125fd37120052d5d9d9d21f4c0e6c9c641f5f3044f378362c8d96296e6058b66586c464a4d01179290dc00a7f93219010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x464b9c6f9f1c98309615e64f746df624d9b41a7569317974fe11caeb9c40b562589d9a78ee93a994ea8371a9d853e3fcd136172658ef65496439bcfb920d3403	1625846389000000	1626451189000000	1689523189000000	1784131189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	186
\\xb1090e1225ca75dde4c31fdf9a4cf94afa22cfee6eb0f80a986a36e9177cbb1a884ba51449752cd34e869b01a34256a6f8fc0ec34a04cfb3144a8260362e79d4	\\x00800003e37a917b36d4b6b179b707a98531aa525eff2aa16a5969547f17b0cfb13448dddfee4fd47b2727ad350b25ace5a93b760046cbf6b1e408b40fd965425c3f6c2df23fb85736d662d97d406c9659378d64c1915e66320d943579fdd3b8a5b9b31c46b0d5af7b7c3ed06acbbb19f31161f7b72c33995d78c24cd2d63a78546f7cdd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x56311faf53a0c30973849c22e6b16af17e378f8679fa135b50a9581eb45fed3a66fa1ebe847d32f0ffa3c4b1e409758a8ec2466e92fc502f052f88a804db330a	1610733889000000	1611338689000000	1674410689000000	1769018689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	187
\\xb159427278bf8738ac7afd3ddd01b338f6139a91c1ba478bd0ccb2fc9ff9ddd28b315d849571c212fdccfe411365f645253029fa59e0463fa71e09a029051aec	\\x00800003aafe5f3cb55ebb3d9712f9cd1ad36725e0b7f90c0a7f8f9f2ef49757b0ec3175652073f2aa9689b52094d8ff1f1b57f3c785aa0c8adda5a2452b7b7d68f8d91a5ef08731e6cc792c2c99262c602eb2eae07979aa1f9ff20315281e6deaccffaa086e8966baf8bff1388b8076b3d7fd535d27d7838aebeef14d73360f3060eb1f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7c174430ee59ae0c7229014d4aad3093ce715b5ddbd6c174e92c5ea5b0a5b9bb16d44ac70bbeb58744adad4c2257df10d351eaedba097d1424dfa6c3e6113c0b	1626450889000000	1627055689000000	1690127689000000	1784735689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	188
\\xb2d940e1605bf75b66ec7e2054cb9a9cf0f513b0ab5d242e7a93ca24c8fc15e78e9912f40cfd6b53411e1f823bc6a39007c69cb55f8a1413d4995b504f20208b	\\x00800003b434fbbbc4f0ec649a16df1d15a6fc9ec5f0fdd6be978f859c58708d690733fb0c5346f7bbc17e7e5ca9208b6ad8b20afdd97ca6210a2f7b5b4f15fb628c8495b7dc4291a20a69bd87d9e11b9ecaa8cf1c9210c7571ca9cf7c57a831054a72ec9755e2f57db285b2f1dc10d5d5d00b5812815e34342f62d02fabf95d59af0f3d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x44dfe59f8f2cf127eff4f5d965801f746f8e45540725a5f7d9a71b235bfd8090fd69104db46345a6befd5b0108db724e32a5131e13d4b1e344e78d833c64bf01	1621614889000000	1622219689000000	1685291689000000	1779899689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	189
\\xb4d5ac7158ca51811e569598623da25c2013d0a6226ae808572719df736ec5f039f0723a0c095fde38c25dca590d42f0b28d68749fbd021e072155a1f3a24a7b	\\x00800003aa7acad88fe4de77062f3dd2ba0ecbdab2a9ec8b14539a4592850d566f10e8c2f563e89eae4f810eed1ce29b408604588dd30b31f461f9cf32bafe5002065a35d0699e64377fa020de4f3e0737178b66e275b522e41b57039323011f15f67bb287186f6d08cf06709adbb80d2a1aa0a1298d6998ce8cfbcba365d7b158fcb7c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xceaee08343d5c7affce4baef68ae8920d4e8c67bc3fe9da1ecbbd6996094426a334576ffbfa4e213bef0b63b3cd15517c1e8842b6978b2419398bef4a05b5a09	1622219389000000	1622824189000000	1685896189000000	1780504189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	190
\\xb44507fb7ed4d19b33fc7a5da5f90acb52295b986ddaf59128955fce005e0e0d7885248636c4e2f59cfbadc6ace6641806cbb58c105bd80d0fe942a8d1e29d30	\\x00800003f096f1ded6ddcb00a18f0fc196e1aab5356b11efa9fdb6d19d3ac06d5f8db3d6f87889263ac89edd132a4f62ab17677815121d27e9cadddbe8fd817cc61f6fafd8c57a2e3ab9128b82f2c33afd547bf24739dd121fd1553f9529db996da704c9bd63696b5cc155211c676751b1904463e4a16e6063c2b93a7217a6f6d80c21d9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd74b2325d9b69c56b02a4f5922b1868c875400c5fe070423f3750418879415d4d0781f88b066422cd4ab5fd93bb0854aeae9a8b5713b81c12ab4bf3032781f01	1616778889000000	1617383689000000	1680455689000000	1775063689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	191
\\xb86dca54984b6b0cf06e850146e5b6c9b9cdaee815829ec9a9ab2ecc67f3e79331234bb9561215a53c77cc18052e1469ad6522a631c39c1289283175e0d702af	\\x00800003d3acaa198a07c0073cde4a1786f0bf71ad9d5d615f9f22a7c856fb28859b5328850fbcdf0b565cd3164abfb2926341892b2e2407cbb46513d1320249944df8cd2d55fbeb9612ef720743eb91fd164a33f1a1400214b6c438b8290bf016cf0d358e8419c5cb64d0df39bbcb63d119264b371c8f91d4fe7d363c668cd388a06f47010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x123f68059563af9ba3751788cc57fdb70275aabec8d1f5fc5c58ec9d5ccea83e53bc47e89be9b2ee8025aacb2c67e91a67e1f2879ad3f8f59855645b6e5c8d0d	1623428389000000	1624033189000000	1687105189000000	1781713189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xb98134ab974de08d027a9f187bc5d5f73d143f3a7faec68c1eec92f39276f181a49a363318cd6ef4845cdb4e5ece207f45504ff5e3da3c5d6b33977c89472951	\\x00800003d220ac2e08ee2be3a38eb422055fa70b0f658c48a0812e5b2e05a9a1f526b5a8889729e162c4c78e28e3c145284edd511fbd61fb1fb399ed94c3b58bf5383118f20f14f1bfbc25e9bdf6a57e72970f4a7304fdd39e106557a63787f0477f48d6c08f8c58ebba44ceb69ac5bc0926d4ec290438f239bb4a6c64d059286b03a39b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2c2780620786c16ef23d74f40dffee3d5f239d5b376e2baa0944bb8a60322d34550110bb442a53296ba6d8115e1a925ef34e33f780befa6c855de02187ce580d	1632495889000000	1633100689000000	1696172689000000	1790780689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	193
\\xbb953ae77d2c615f744a9288d55796f8feb2aa5c12e65b26b72b3bb25e93ae1049c35f4478dc55e50aba54d48e07a75637d1caa1ed9911e7bafe6aae1a0ecca4	\\x00800003ae968a7028576d7e3d80debe73ebf70250ffb218086872672a898161441b4cbd0946feb1f4aba5e0ae214584e83135d72379a8a6f66a4701a0abde6e7378d6e3d49e59c33353bbbdedecf4f47f176bb91b8e7c2e3ba3c83f8a55c8223889c30d52cb0d21f7eacfe3ccbc13db1ea21468ac9ca0c1582eee4a762553e5e98233c7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4f4b1c89cb2a323f026ec4f546662c0f5db5062a77eafa57be69657b5617a4d7fecc072d5947e4e5476b32bd2b44eb8ef3f3182084ca9895317c3a33ebf28f06	1628264389000000	1628869189000000	1691941189000000	1786549189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	194
\\xbc99b0df2d9a67fa71275e23d3090a68002e3d57c558b3bdeb828459169ef4eb085cfc4c418e2bfb290a32370fc746049255b645ca789fd0d026b5e033f7b265	\\x00800003c6282b34108b6a36c181f0c8e5e0bb313406ae2ecded09ff01db2ebef5804b3ff33f919a6705331123b2b2099a00efcdd80f2bd7d15f984f42a01fc9487b9f2346019bdba8e99c15096e8bf3b4d552daccc84f70d2532705b40736ceef8163ffd55ddf809908c6e080f0f9596342227c14d992a1105da017bd44077fcc4dc205010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8f6c6f65cc39c5f1677be2b9179b21f0dc529e806b6db923a10aabda0be3f5fbe17bd6c68187647d554874f30ff9eaf727ccd64d699fa6824b4e6100d515ea08	1624637389000000	1625242189000000	1688314189000000	1782922189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	195
\\xc461f4031008019098c3c8bb7728a26f810d0df3c55e92daa37dca74ac8ed20fab12a3c8f32183397972cefeb7c89cd203cad74f456082a02d8cdf3189d78172	\\x00800003e93983b8c098d25f7d0271bc00d90a7f88bc444700196e46372a483d26a076fd1a31e907c59b3d9f820a03a829dd302e3549810d8ee64de1f5a3384b0a8c4b6bbdd7b02ce9de91b55b4dca6277ce137608ed20f1e8ef8d9eefc5c8cb9b2a0e762edb476b8b5d89ca71581c65afe58975a66a7c9cc6ed9b0fdd3ef5a0a273dce5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3f71902e148a58472e4eff6fdbd1eb942615cab7b6210328127ce432893a199fa4d496c1c030103c228a86508c8e0365052b46bf288635b8d4f06b102b8e5500	1635518389000000	1636123189000000	1699195189000000	1793803189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	196
\\xc6893e09ae4204e32ffef771701302ec97ecd9f20204725153019f24b61d126b7bc7e0925d2bb4c4b328855a39d4a27f1e32091fb1237d3985399fdafb823ba8	\\x00800003d5f6d205c5420fb9c8e6797a3087a11008b8fd40a3c3f612765345959b4a3ded777cbd4ce557e26135ae33b3e6d1b21950b02d25d89b029847bb3a457d9026bb8ca0c38fd498db5abb13801dcac14d8f929a9a7b5547bc1d6f227866a1f8a92cae940c37d72bb85d52fed60af9c7d0c10424aa722c1ba6c17e8f00ce9261fe1b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xde95379d346e4e6bfa5273a84dff49d13dd2fa107d6b0faaaf125296ee023634b0099cdabbc81889fcc4b3cb8bd9c384c9de09c2bc5bbfcf87f3a406678afd09	1619196889000000	1619801689000000	1682873689000000	1777481689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	197
\\xc7a1a3070d99fa0ca6df59ad722e41f66bda6a9165b7ff4968108ddc5233b079bebfdc09c024df3d86b3c4f48959b355e91bbb2e140792ff805c3f236712f87d	\\x00800003baa7f00490c35f6a75218ab9f1c1f524453f8d71623e4f0579c5f4433b682b9f0a89ff8fff727e3e3ded2ad9269c0e2ce71c41f3dc4f5172d9601795604112cf9064354de2ffc6f2dcec51c79ca4449d9771dda3bb51ab8e1231367965a230f5bfb2f2afb2dc6216fbb3472e5a732240a7f5373c55bc6e84caa44628828b4daf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xda9d7c22c9fb54af138eef855ae9547bf134d67f4f7f0b5b8e9dbb6aa2c02a327a5b0346bbfa856c512d60e7fbea12ad062f7ac83b572e870cd6776e8106ce0a	1629473389000000	1630078189000000	1693150189000000	1787758189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	198
\\xc801593cf16df74197180a951d2596ecaf1e69408b86bedf12758434726c5d0ec427de6f6bf919eda9786ce0170a94bed976e0825a015c525dce2a1f818fb00b	\\x00800003aac87b87b3ada9368162848765fc1c76f5497abaadc87501f9da072bc2ba085d385ddfb7a7b1e62704471cf487275b044cd3fd4b80547337ee0b0c7dc30f76f5574dad769409baece4f1eec22bf11e7225d1b6d088728a7774696149c9573dc7dd627c0f66aedf2dc3f819c646b27ecef901b20f3f7d92244b39a5ccf1232b31010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x86e52b82d3e098800b58fc16a3d14c878dd26cc03b5518c75ce19c3f72d9388424df2d22e9d408f15be4701f5d4224fc29eddb45cda398d13ccbead43fc7210c	1636727389000000	1637332189000000	1700404189000000	1795012189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	199
\\xcb21c49252b6e3de37482dfb728030eed8959fcdfc92db56638798d02e2e278230ecfe4dcf8730bca7ef3ef621104740a44313c0b69bf80de6c434ec9525f64d	\\x00800003cb629ea8726b215e879a27332bfd32e0c99380ebf4b77fad2e96dd8c4fcfef9fc0f530446ef72656579897402661dd6cf978b5705f7d358c982e4172c9c64620b071706d2dc2fd6adffc507bb521a1c3e9037ccac69b0e56b2154739f8a3e53e7f802871512cacecc0cef619e91314c61a1418bcf0fca014c268c5716a9a0145010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2606833911c72ed1f4ecd472cd038196338fa9b5f302a6dc9d5de61503a99ce5b65732a264b9ced9351b0caacaf4df6f984524db94b0d771115c73f054fdf809	1614965389000000	1615570189000000	1678642189000000	1773250189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	200
\\xcca55e70c6c0ebec6f048f4eb4e649f44e463977110d0e8e8ceb1391065320346ddd55757ed1543a0adfda724ce65bc00cc2683e8a61be3328a9d7eb0bdf31ae	\\x00800003cd0880fe31f644915536d4e5d60d15fb764860b032abf76e9a1b518925a02ee9391ee2b9d57605e3907a5b4f5e893791b670ab41d25285a85591c71a7e95915f6904e293ab8044d6b113318199d522e6fe1e93376250008b7e8ba8387625134ceb64638960929d75b864f0e0fa2ab359e04c83132856cafa30b16a746ea506ef010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xaf51b360ec543ca7acddb425990782c8682078c351497118fcc42e538acd63ca9c6da5f6f3d7c14f93d73eb216ed6801142e5219fd726113ef0c741e5a045004	1631891389000000	1632496189000000	1695568189000000	1790176189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	201
\\xcf018ab7627d719cd708b16b95ea8264791ea9a52375c8dd7dfd8d523df97b1bb9377634cba5738a8c8bd41b8e5af3b41c223c9f0bb5dd04f063806e38a38e09	\\x00800003d49e9a75dd6ecbc86556e4cd87ef87e501bf17659446de4748fd4e1b19a696ac566421fb437d8b3af412776d3246a5e60e5b7d23a8a512dbff0018b9880d41f8ba9d0585e196dbb1739b75097c42b128f0a52322a2be139a8aca41b32b6a622e3b07a7f8f9f51ae79570f1b53575deaefb634659cf35ab524d767189b8ae8897010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x51b05e54094447bfdaa23503b5292b3310bd1a023e9577e362cf73b6d3bb4467909a0be7039b70a422a7733d208f11a96d1129a19f449a0e85ce812abbe7e10d	1613756389000000	1614361189000000	1677433189000000	1772041189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	202
\\xd1452158ace08e2409afa8b8116ee780c49fb49aacc6ab71b1449d35fb86bcec624b76768e89bf19c76734bf0b8e855c1c4df5ee43cafcb302b033d4ad26eb24	\\x00800003bd176c2811a1b0a5628e8de5d4580b00b3b9b4eb61e3830e1709651ee93ec98a8c4eb9f39945f2c61a686b95f051886920a9d474bf78f061a69d8cc6a6b9053eb4472d541d81640b1dfe0870d63f3acb06db1dd7e58679dca7d8878ca871228ef411943623a0b62684b09e35c592a95f691e2e874dd5907515a5489a0b05dacf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x26ace7f8745cac7f3793d4e35657dc3aa10ffbb758dbea59993f8ce246bf0b88805a8b6ed7984d949f350d29ea1685042fdce08f403951ca8de531e1c4003f08	1615569889000000	1616174689000000	1679246689000000	1773854689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	203
\\xd339bf783a9389f5d013a07f60bbf6e34cbf896ee2ff2f53fedcc48ec4d7b5186aa5360ec4fcfbfa1d26c1b395309e0788d47f5b111000e588d112f9de3965d4	\\x00800003f025e3ae157331ce084dd24cc6fe617b61c9c509a5284d4171b9e9f95cbcf3415b3914e3a17af9785c376b7ab2b4e6fbfbf1846300b785d0c9b979b3d60335bd60333b022dc51de9f290cf0191d1393e6fd505b46e8e25c178131e5a6953d74eed47cdf72f8473cadd4a4c85e0cc3c03b653107d7460c016442ca72aae6d5fd1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0c20803cf1a9c7e8cec02b1cc38ba0066a3f9744afec002f585b6c51d547d3ccf905ac9512208d871e083996d11714410089727df80299f3c7543e36d0317c04	1612547389000000	1613152189000000	1676224189000000	1770832189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	204
\\xd53134908710f88e10a77b577b5c03886b16e4c8f61e91d27a9da606b102959a38db8fb4f1beb1c53104b02e3e353a3c8412db8fa379fef4fd626fc364bd1335	\\x00800003fa816bd5777006c2642ef9c11c187bf5f8629649b26db0f10cb449546af805b69473bc9d263a26f5e02b710299b85a582f155a550a14c7774b4ef0ec9a2afaa65f662e3750815e31ced610f7cd27b958d13a86e4bb1d3beef9d6d605ab988185b80ad0f51472585da2bb981334574cb0aba6b89ee51121ae4731d91c400f2813010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0642d491c24a341ab1267ea2b12a345071d01d3411f3fdda3e35a447c09c310018d5611be366e185387ec386259dbb5ff86535dc73039cf3f5082dbf91d4e30f	1622219389000000	1622824189000000	1685896189000000	1780504189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	205
\\xd7e5d00ecccdcacb8d32a5f487d6086c85683597daeb98abc8ae72b443b65f1298bf9c21da1f72cfd7ab7df223950f583b8ef40f13e411aef1718ede268853ab	\\x00800003bd6e9ecdb93e45b004894d6359477cc139582e96be7dd6e6f9e249f5e135619f8f7f0d9e6a22bf8ad1c4581a10ee3e08ecfb407145288fede5d294e97a9fbb649695a91d30f22f89cc2042078c5fcbf47ac2c9dbf02d4e231a61f27ee4aa7ed920e86730724fcbf460f2c2db72795edf9b887bc06f36f7a827e1848c4e341523010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x71429ceb94f9106fc6004ce950c6404bd29bf8b4ec9f94673024093ce1e949200a11c6dceae63025e8ada53ed21a6c8acdc21684518c68be2fa87e90743e6000	1613756389000000	1614361189000000	1677433189000000	1772041189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	206
\\xd8f5d09412f4eaae2f3adc4b15da1f65b2ab5b723e81d1ef352ca3ada9a6d474e306ba0e9548715e362b53447b339a7f469db5c08af95f9c74eb8c1ca238dee1	\\x00800003c6896094d85fa32ca32f0591dfe8b6759a6e810c757391b262742c0e11961dd6b79873b071bf24cc4ad57b014ac007ebbd5317cda1b407d832ce43d7609c5a008b67b5f15b20894312d3634d04585d370cae3abb7fb568e5f2916bd39cb30ddd6da93826f36575a47f9852067d8d0eb90efe87106e2396cab473bb3175ec094d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xef08c6fa85a42813279220ac3b7978925ccb465fc303952f0e0710a68087d1c7e221b5743dec87fad068a86b3d847c89e50c721128ba5ecc047eb79385ff580f	1626450889000000	1627055689000000	1690127689000000	1784735689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	207
\\xdb5530189b0f04ee927e0f3e67774e0aca5a4baf38a31ab25241629535fd04dd77b55b2cf801905d7443aa226c88c90856e7b2082ecf695bc576b745f7913793	\\x00800003c869b25c181374bf0cd1fc955c7efe16dc089f5030665221b9763b513e4e834fe8264a8398e111835794d3e8aacada7ee47237f67ea1301bce6132ea8386293f731a6545d1d6951dc7baceaf5fbb836a41a54aa901502425563af6e31fb1b08e7b51d2b3d14bf170ffb9ebc7b6386e0283adcdb70b07175c605e56ba6a670423010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xfe3cf89637617139d820ccdb41e0065be56e68615d4d170c51d4ea4c790ed2625dd4b95ecf5c35cab803e11b841e065402e6d712f28ce78abf10b83a436e2f02	1624637389000000	1625242189000000	1688314189000000	1782922189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	208
\\xdff151fe02d485584efe54479dfa838e4096f7914be802f04d10357b86a2f0a457544324d8a4d7d6815d61120014c31422b4f7df931357e8cd13661729f7fd00	\\x00800003ceef29673f3e2fc9d05708502d92b3d48d77ce18bcda3bb565f7f2c2f5d90c00a8a48bb10a305bc10d3a2fae4da90af1395f33b0f8090c65416e4b4bb4cd57c90901a4f43f5ab618841f76f3c1e666200d9278c1262d0506d391fc90e935a9f611fdf45ece52190b9541c9434c0b2475b2097bfcef58e46c118e912b00de1437010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x991837d044ce3385b76f2e932d3693cc13bc37972038920e913c8286197b75ef3fe0180dc076b26aad7df030d1920c4301a1c792ec4c960ccba72ff34f209f08	1617383389000000	1617988189000000	1681060189000000	1775668189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	209
\\xdf11744726d058f9641c668b8f8f0c2fcfc8879a3af924e22eaa67ceb98dd5d99c554054ff88c93fcaa8b14431a4acb7abad5756dae629d2c774983f3ee4d272	\\x00800003ccfad59a04aa529267b931da98536f693dbe39998e91d8618e84073deb06c26ba08c451814a5f1ecc69dffb690b9d89df1f57eb700f2cccfea8a0dc1f339f9f4c4841e82ab7b062b09a5ea50363ffd689930a98c176b39013d9e4d84d896fcbcd2972d574cffa78874f93dd8bd416a648d4a80b2128ffc37ec5580e30bd35faf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa7f637b5ddf1b1c5d687a088572d5ff1ceda5eaabb541e210b09254e511bb7b0f6f126fbb6164736755884394cf02503d92ad01e2f4c436e66e10e886c63470d	1614965389000000	1615570189000000	1678642189000000	1773250189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	210
\\xe071a053d2a15f5ee5b23dc9940fd85e1bc907648b3455d4ad1eec8815d605daa2bdb860c554a1d70f333a0cd834ad4440880706fd4217c9d24f696d35402b62	\\x00800003b69364a48b88c270a9115e5be8869c100fa393b22c9964b0f4a221106bfee7ab4bae8a18712c106849df33882e41cc268689819d560438ccd263395414d0515c6f6c4e747933e73ba5964a7ae397d92478a8a3b7530092d52abb0ba9cedf4f8b3fec14a8fa714e42f3de2682bd8c0ebb1c11c181af3ae7c2708fcefd333f21e7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xba10274c0acee6e7c21c163218289f2ad4f2e169193f15cd0ec0cd23fafdfcf7d4c13b07054c9f405105c31beaf7ea3ea2ec98d3bff7a352e15b2817d9f1f201	1616778889000000	1617383689000000	1680455689000000	1775063689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	211
\\xe2915add9479b8021108ce388767744f7f0477e9fcd9b4abaaf78817d8904c089a26d3ba4774e5ab0282fbca96e98bd1d936178ac3479c12681c31231d17c83b	\\x00800003ff03b0fd6947c9c7f81c58c24a8610832e704c4a5be455d663bbe2184b14a2e872119fd111fece0d6f0f5d2d409dcae52d08a18254e46ec23d2eb2f80bcea0f46f2b149cbea19cb581574177aa33af4e420d81bc020785946bc2a86041a909af1a8e3f5c453859a0ff8b0a393f04003b4c1ab3dd31bdcfd3a92480614231dd35010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xea2d69c55016a45d8112bb92e1671a8b25df2f57adb02ac1606d3b7a6535ef570c23b0642a858801241eb265e1e35bbb622602ea82a6146741e4b20467a8ce05	1639145389000000	1639750189000000	1702822189000000	1797430189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	212
\\xe7d123b01563950ab14f7bed787543e840776c6125cc3f215e9812b05de005c564bb38f5a245cafe5297d15aa049c1de5cde116be0b965cfb4e6c5ae555cef60	\\x0080000393f6cb9f70c42477944558fc952ace2b3dec549c3d64df45b1516ee15c923f2bd7d170a94685d7b505bdc0039f38295dabc952420ca3581a78d2abdbb9bc6eb640f8d105dd49f9ebe86d8c64c3f9fa2427378229b1b25cca14a7d3eb9e5bdcf55988081e89168140e5e0bdcc09d100fc1a305ce21bfec7cf194111a7750ab339010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb51d5a2ac8b4a9b66b6b403754410b82fb7c0cf8276ff99ee8bd5ad2f78634d245680bbdc4153426dd47bb4d71277f9a1e082d032b875b1a8e0fbd390c80a708	1624637389000000	1625242189000000	1688314189000000	1782922189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	213
\\xebb5cfbc3ffd35260c416aaaa5d3fc674f40ff1cf05275d1e9f17ee49a3fe98e95500447b842760f818e624be8c6cf19100d39393dc4ef5535bc138ab2afd7b6	\\x00800003c9fa03eaca783e118df1eb0c4b014ae7b7151a2062bdd1c8581a24fe6263bc50ae28580e733879a281d1621f06c7cf00e201a394f41aefcec6f503b1e89d0c1097a6f75f65e53236c9d7988e94b020ef06d5223a6fafffa0f48e687576af35995c729fd313086dfd81abf20a13352174d5cd68e9a794c9bc983f928c983b7675010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1237fdbff0cee67f8653aaa82c2c3267b0d578ac523c0d13fcfc464518271a67730b895a47c89f6d246d4e032defe3b4e742fb1cda83845fca0fd50ba4f7db08	1625846389000000	1626451189000000	1689523189000000	1784131189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	214
\\xf1a1dc447a101323cdb6006bf8b1f9fe62f01d84023dee919b0f754f1c9afd90f5a551b4b7e9d67ab75cfca67c89753d963422c8b06f9e8543dbba58a70d96ab	\\x00800003ca12012ad7536edc3689f93566dc9c2aac8d5a17a7bb4ca1b91992ba0e6b1f6829fb9d3c26b79c19d6d5497dd7e86fc62f7cf6f348c9623d0d9885418ceaf97caf71171660a1b7f170bd45b7afd7d944bc6cecf5b5d31ed2674db43e31df555c87c524cb3a30d751293b2e51e14f1852e1e5bd16987c1bea50723def5a53a0fd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd9bd88d26ac274667ecfce4eb8b8198b0263619eb8119956a87b0167d5652b2177a268ff9d134ff821ba73afe0de20f00bdb40441d1f3a212548e827809c5e04	1636727389000000	1637332189000000	1700404189000000	1795012189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	215
\\xf15da57b06a5a3fb34a3647598e1adb0cfa97f6f5e3b0f5dd6b6fd9592a56b26d2efb7aa0baa19a93e31e9f55d363429f0e5bb46b6d0ddd58402040a3adc1f18	\\x00800003b894eeac9263f4ecf77ce4b015724277cb627eb70004de1552e2785f2bfd7e977debc2ad59e19d0d463d10a9fbf56957d8a857331735c0262efd7d9de9c910fd7166a470dee9b7ccb9329e20dbe13b995a76862f84e2e65aecab8004838bc063f6293309a451973c6062593c7a306398027522b3404a65e1f27d2806439db0c7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4d1ee4222d1fbaea90da1be94732c05c0a0e8e30e8750045947b388c21640dc19a041c987d7a40f9bebce2d4afa7f78e7fa281e38a21ecca40fd4e15bc3b2c04	1633704889000000	1634309689000000	1697381689000000	1791989689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	216
\\xf2adb251d9b029a3a2aeccbee06dd5dfc898d6b39fcd4981d5e44d9dc56a4d39dff8ac4f6d2d3a8899cc53971901c0d53e93452c934aba68f9cb71f8bc2aba0a	\\x00800003b92121a17803d9577463b2b6e16140b5793c25abcdd613fc2ffa79c56e78b9359a807fc01d4b855025e0834bc37a1f784fb60ef77cc2b65c658af4cb33196c2b27ac6e5fea9c3eb76ad73cf555ecc74f829cfe30ae5c6315f0bab0a43e5fbfa59613dab6f86938bea2139e32003db7a7e0ba1ee9930caab77798d94ebc93267d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2f6afb01c05e50ffb66fbaf3f41b57588d8bb026078564a2895900e2f82d317836a73f7e0f70dd56da54bb7215b5d019e60a6d3232b8246e4ea063af5fd0880b	1628868889000000	1629473689000000	1692545689000000	1787153689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	217
\\xf39100a23db30482bf36149c7358a8520d3d50e1f2ab112e89516fff2fef3542bdbbdbd87189cf7195f87167a10efd009387af829b9d0fa8c6790ceb4e9a9e4c	\\x00800003cc07cf38ccd37d21e52ef4bd6d02eda3cf14b3876d30707255405c35499ada780991129262226f06e632dd0655f1c6c61a0d23ea1e2e61ebc96a5f995e654c922c01288f53dffd6af3ae0546ee3159f0ec20b1c698fde23a8e6cbb1300bdf56b2776cdf6de103226309909e94c06052236155a68f2aab4cdccd946a78bb289e9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x177c9c012ee8cc923834d4f63d0d8856d16417ddee4b060de4109668ed29087e1bd86eb626d9e7c19f13d2ee6397b1b942278fd3cb6cbadb399d33c304dc7e0a	1617383389000000	1617988189000000	1681060189000000	1775668189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	218
\\xf3f5283833d6e07c7e4f43aeebbe61d46bb405bce62213a06a562f60e687dfa9c85deb86b47cb230a38256f7a397cc066bc7d2146f5f6d0c46c8d17221a87c52	\\x00800003d2aa4c6ef796cdad296c0779d2346b4c69b90fdd497860961340c4ec7f20f42c0065647a55ebcfacfb0a48f65c9ca53e9213aaab1cd9bd36252bc70a0179eadc8bddf180426a37cf484e87a4699f4c1268c3574d3cb03f602ec7f5d8e793107a39bc2ac79e9a6d4b2121ee278ddc9dea23f0762161099f4f38490966d41ea387010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd768655da22c9befd29ea3d58510532915fdeab561a8ec906111ad79ceb37d3fe4aa583c1fddbc12ebc72e185e042be2d8c9ec466bb9fcff3696ba2e86c0ac04	1628264389000000	1628869189000000	1691941189000000	1786549189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	219
\\xf7911aaed52e76a9e8e7af3e951342cb1d4e25161038159873d347ff280a646da8a617afe43d5f0b0ebe2ccc1905417c78969dc4db106ac2c048285fb71c8c33	\\x00800003bc1aedbc40d1d683011697f6aacd605045b61d118c70983af857581ab4868f35fb02516788e685f4e5018700a1aa0e9096c3913ec1026d330c548fdb9cf261fc6e139e7cc13a245a7720d8f83275a729da005e8cc00c3a4e76fe7ebe26c04838c5d008963170de319ef46aedb5b627f66a72c61c06c29e07882c32ab299ed777010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbaf88acdec14e6fef8dbb80220f0ead3ff0dc030b3194831b606ddb1a7a12a35cd15a52cefe018a6553f377f9d40289179b7ca9784e2f707250a1ba091bc5e09	1626450889000000	1627055689000000	1690127689000000	1784735689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	220
\\xf719b38d9da57d70236ba91ca97799ed402ee108512ca46027c5ea6504749d373c76094e189346a2426f3f81f475753700d8bb39064c8eb5a3f97996df8109cf	\\x00800003dc023352fcbd298ebc946ca213676ffaeaddc3daf9943613ad5388301892a09c13fa3df97d35fbea573dc07683dff51ad80a1cc106aa90fd850954274f3b6e9672ebb262b2d1ad7487d39ac15441592b29dee3944034c733df220d06867c9a4fbaf7e6021f60963b3a8827514eebc1bb019e43a8d649bcf2a5d55b8b895ec001010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf14f535807460ca91374ec50c02c80a24a52b3418317ca2b7d9c6ec85e814eed9f2eef3652824ab9d3ed3c3da48aaa6b5ce71a3a6608d069dc1c5f95fa78e503	1617383389000000	1617988189000000	1681060189000000	1775668189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	221
\\xfbed74b80902f37476aa83f42f8b4076e2b4650bbb3a441802711e31cff41892b758c74899bf16b41b57257e4b83a65b6d7558b0ea7a1ff4f61433fb75f8a3cd	\\x00800003d1799ce26dde113d85d4b6a02a42eb93028a1cf2927a33915aab044a9655024d7bebd281412147e837f052355d41444b3eb9351b020ce77dc10a4e238443e248bc741d10127d0a5a1eadeee168091df0c41dff7ecf6eb5be1a2d98351c5645939a6eaec3dcd63d637896ce9a1a729eaddce469dbd7a23fe7339de2ad04cd212b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc3a64c6380d8b26cbf551e1bd5b6e93aa4942b4fdbea54a42f4dac70db078d65557da876850b54c0639306af9d24876b51f048bccd39aee7776a1f1baabfda02	1625241889000000	1625846689000000	1688918689000000	1783526689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	222
\\xfedd8e56816424481ddcccd06e2497b34b753efffe8fba15309e6137632c2ebce4bcf68197a5de6f1ed9aee2c8b151d71804aed1a827c085ced631f98f991c5c	\\x00800003c860467d1a22835f5c21d95557289a9510c62f9166db43d10b6ffdba17c99e259c2b5b3d1fe3550721f5bcb3b372cd3459602bcf0273d58f66f8c78b90c2e658c90658eb8e534bcb5faaf491914041d173411258a61d4ef404c464954e8bcc4cfc3628a565cf9f5eef9bd2aee1b9fbdcf2945f587a475febb469f9d99287fe1f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbccdc87a15cbd832745afd3152dffb33f95deaa5850e0a5c3f394d7a0901fbb20ba30888454e06a3d5293115ea7d48402b21aeea1fbc191f0a865f9b2801100a	1610129389000000	1610734189000000	1673806189000000	1768414189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	223
\\x01bed7dd05072b1228e7866637bf10e4c8ad93ef19df54eff592201aeb14fe88e99b486e77685a5b420417dbccc744534908f9ddca9c65989d557ef9a7357bc0	\\x00800003a65a5431611e4d3504d23fef3fd880a45da1815936d6c8a306da0fb2be655c8823b9f03e2194c3bd16f0cbab1f34b1440fc6b9e526d311daa4506c80e2daab7c370836933b2e2e8848ca2da4bdf7a55a1aa05d19c6cba6cbf0a7e55b78def62226ced717e7be98a34082d8a7aabd9ee14a7a24b9fa163aa0cfe40f0db75c8241010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x42638f4bb4edabd9a0cca70efa742654e0f114f9181cb20b1a6d65e3ab19a552b14292087244edd7e982227b05f8e25f6787681a56a5258c192cbb9e4fef5802	1625241889000000	1625846689000000	1688918689000000	1783526689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\x02f2f14560d5b4f21714087b88ee307c31220cd88d129b5b36321e173cb034de240325846da1ffe7649949797caed0f1df7f1d515b783a9b3c231f083ad42ea2	\\x008000039c6dd9a44c62c857c09d7831334172711d7a01ece7438b6b1ada53ff7fc615ab9013d233e13a6e9918606c8fbe3e5f314a823459e4302291c1374af813db45e47f8332f3cedf161bd9dcc46fc2840b3c2fd2c524244f16fea3fbe901bf195f1cd6e44993d0db7463d082014f2eb4f2786e34e728c51e15f5f4f515f2d9cad6bd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x232ce99cadbbf998937814366ead205dda8a04ce5fde08a1392d8ebbf7e580a823fda4b384a7acffbb3c8c7310e6439ca5a989e9d19e502db07a128691ea6000	1637936389000000	1638541189000000	1701613189000000	1796221189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	225
\\x047eee3d5dcd7cd703cb824984dcadfedda3b772f86db2b298ab166a00fd320544959596c9aa5a06fc785d594ee03a73dafbd323553a428852ac70839a69930b	\\x00800003d648d14e161b3a72d945a4969f716c0f06c63864455551d74ec071fabdd38c246da02d5ca9b21ee5757aed30eadfb160c0bc40f5514e3e7a91b409ebff1cf5aa07802d25af6e861aee10309c373d9d3cf9f0f3d7b7ff8c3b44783dcba75e451143ef98901fb52c7c0c9c78d89c63e875bb42cd8afe741207c38a7e97457e79ff010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8660e8d2462ce6a5014eae24d863f7b69c827c083cb3d77839a0dfdf62a9470d61984eb6d74c450595011f3cf4880b6826463f617d5193e31c7ce35101a13c0d	1640958889000000	1641563689000000	1704635689000000	1799243689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	226
\\x058e94abdeba0d5c4f9418996d6cf51ac256e17ae686eaf436737149a5ffe7fff9edeea50f9b8983908fc28e433fd5c581fccd4e60ccf5399f8356d5e07f8f0d	\\x00800003abfb6aa6c7c2f8ebcf607e9ac106a0c7e185cfd5ff907f6768b30bd2fec283ef9ef26d80a4732c5a7c9ccae5716da32dafd16dac528d7436b4a62f77ce56fdb8084d4bdfa6f83ecf415f09c03c3dfaf9c894ef4e6163221fc9228ed6a0d030a643db7b075492525de790020d96469c747e4f0c0547879af4d4161f004b6e02b3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x26cb50490ae5e545772f92eb96906b34abea3d6dfa8e18c782c1780fd79c321e9fff2536f453ca6c5ce8bfdcab5d4702b72b9f30f074580736927e191e574b0c	1633100389000000	1633705189000000	1696777189000000	1791385189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	227
\\x077abf7f58dbc7cd8231cc9cfa691806f959dcfbe86ca02f05080fec2980d991e49b8cb770329e931fd244d8c5b5245aba19ed814f85c434e957cc17e2090324	\\x00800003cbc20e6c2ace8416f53094af3a758b20ca5cbfc4d0d3a1d1204ade7ad01682f9c28c92cf656cbc590d19344b90fc458a6ef93c2e38d38b4c8410850997e866929d578c49363b8270f0df9d58d7d5e1644c3bbc9df112caab52803356097d5e5bea6980c23ad4bd42bc692d6e3efd9cc3a10972b9432356b5920d3c2220899cb7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2173e1aeecd032aced67f31ab458e74f958a98af419d4bb4633be2fc141c6e6c7dbf4609dbe663d1a82cdcef6dd211b43c404600d8df47455a7ed78bf295520c	1630682389000000	1631287189000000	1694359189000000	1788967189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x097605a81e299e1d372344262904ed2a2e8924948a6e911dc2673e62338a60e802c8f84e1b4535ad894d4c49348679c641c1ae4df6e8f4b62335851440225145	\\x00800003c011828703655b128a07d0e0453853cdb70d405c3d30e7774e2011677088432797b41d327f58cb9ac50e41fbf046a84873fa7fa5104f75952829c08bd8d5c9cb24f28b655c51efdbcb6f65cd02298e11565202d6c68caddb49de8b22de18f52c3036a14e6976ac7f6d9ef0770acdb8406a4f05a8028539afff9bdeeaca935037010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf8e2b702ef4f50324969dda03835998076877452618d22fb619b262221050d6a8642f80be1f142ed3add840aebeb97dce7bd04d48e6f571bf25a374b0c0e8106	1630077889000000	1630682689000000	1693754689000000	1788362689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	229
\\x107ad98136e933d36d204df25597519f3b676a5c56354d674819404ffe90988f863c8439192f30cec34105befdbebd1a20f44fe58b6c7d7d479fd990df8c5a6d	\\x00800003c1db0c4c22ecdebd0962f39fb8e935c948c1038c23755d8de3a5cc0af0667bcad854c7bf54328aa87618be380f2ba9849deaa699b18aba36ca27436b2df0445eba20706ef79a03327c852bad86acf9e31a80f1b7c50658ec294138fb91e458fe9c2f493a67bfdd9433e64ff6a82275eb3fbeba607951ff86289e497ff44b840f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x144da434bcd8d15234f4453b9cd6d5820a7066b3b6e70b4bb3de10669da7dd4bf7a349ad8a246603245a8f85dd93749bb3a13d11c25f58eb31d77bf4a53cde0b	1639145389000000	1639750189000000	1702822189000000	1797430189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x15aa8d6237b9a3f07d6f5fddc46e82a01461c72ac1a810018421e254f6d0fa83a6d5a8aa4ae33840459eb980928ea879c2d15d99ed5e10bae18378484c4f2591	\\x00800003ce4bf815aab7a2bb1721ab2e8c10e8b2df6399c04c2bff0e8398e330a29f4079c1f17eeba1b0310b7e93076bd3d1578142a4d9a5f48b2540e6ee3cbd8db0ce08a8c2c7e7bc0ca68f0e428508ea3057a1a514ff9658a40db1268b55e3e742c3268b1f4d092c94081a51757b384be192bf44a81707bb490ec86fb00b452ab8a4e5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3994aadf99fbeac5817383361e1f273c52fc261cb945001a4e51b861660bb96597d923b4a7daf572fdf88d361f6648c78a711a418cd276e8ad04428ed24e2b0c	1639145389000000	1639750189000000	1702822189000000	1797430189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	231
\\x184aee9b39a13423a0c9776721d4b1da2fbcce4f7911d8a9a8d27259c8ff463c23bb5502fe677e4ce6c592fd1183c72d323a50bc336231ec0eeb4d268a37978d	\\x00800003f2c58b35540905231a59c9f948ad14120c94d021e1ceea4ca552e43c928ba4933b26377dd9955cc4600ea76985b76646950082e1bf3587e417d1168f0f089643bde1365638658588bd1cae5fb7f32116b5e8007ddca136b35e043bc1db77447d593620970a1986b71947c99f9fb0d879fd2eef58f362347a48ed7a6c5bd52a05010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2c218f1b0a20a595f0d9d199ac40b82b00ca5b2badfc12517510f75275d41a987c309d5fee50637a654cbf1ad19e6a4ef69d6709ac330ce33ab745af721cbe0f	1619196889000000	1619801689000000	1682873689000000	1777481689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	232
\\x1b1a5bb89ae188d24ae3595f52dfdc78f8e4d65f83ab73220cf13b1c8464cb0171a030db7f5a96913863d6ecb3db97781361df08d6c1ec176f3c211c304f9431	\\x00800003e5157ceeaec2a9434661fe52ef17c33098bc71765bd25fac89b02dbcf0bd8a89d39ee2e15cda0916a6ff09180ee71f187991873be6702eb13ff37df4d6da66e97963509cb4da3665d4edbf3dbd5efa6ae7bfc3a1bd831055a60e08a71f5e73be69ead817fa1260c008b6f03ccf6977d441a0599745343773116688c46b6d137f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1a76ff893bc0202421c31ee357078e7c104c9215782dc0cca9eda19c85902264391f259b5684fc06b4a9409e99142b69d1ec1315f433ccb9f43554ab96ca6d0c	1636122889000000	1636727689000000	1699799689000000	1794407689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x1d72a3912a9840f1ee3ddc95ef373f091dee7fac9b9b471ba29437b2b095e5a24b7ac19a5a36b505e9a908b2905e178f707a13866b8aaeadbb82bb88a82ca990	\\x00800003c88aca24cd21b63d2f658e504b099b429ec8de403cf0a3027bde6fc8c99ac8b6bfaab8e17d0493fe8ebf100111781a2f9adf4d95a6cd5fbdee0635ef1914e990e3180af14c3e56a78088687c66f26e3f11c56b1af60e7a646d0e55f0e679b5523719ed109462b2bfaacbf95a40a3b1c209efa0b08a207ab1caa3e9b20393ad09010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x137120fbe795e29e279a5d59683ceeeb3fe554bed90a6591fe1ff83e4b247c22791d0aa1bcc28e3a27d292946e9a1588a1af8e4c9beea99c08879932ee88920a	1610733889000000	1611338689000000	1674410689000000	1769018689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	234
\\x1efa29dcf8b67e49b232afc9581cab8cb8a4e2e4a47eb048d01f3fd44da5a6d6d97d78b7514376cd22c779479977ed7a553b77776196b4d4d20f3f0334bb5147	\\x00800003d48e4a12999901b61b32d71674928cbbb9041135d3069bd294d9e50e4b76f6d5b1dfb6555353dfc3960e89a7fb6c686725a267bd1ddaf0160ec0b2e86d56f361196ba03de70d1f9dc667ef6d804ac194b2354ae2b9cd149e3cadc238ea795a7671368eccef06f9a319aa77e6f4bbeb5cae0880ce4aef526a8b93803be8936a95010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xde40502c61295086728377f5f8b3b889cd5b8257e1eecb8285f45a5bae64a8f391bdb192c3e2b8b24ba9bad6af76f9ea16bae7b2444aad43fd0d60bc99482b02	1613151889000000	1613756689000000	1676828689000000	1771436689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	235
\\x293aa5a2c5aa15d306697fd3a966b70f46df9a23e246605e3507e93a56183d45e1e4b17642c8284a9f2299e8e7fca7b2dc65aca2b7537b200aaa03bacd379858	\\x00800003c766248ee25441ddf7111cdd7bc9e297e0ddd8b2a2465ca275196d3f08f3c83dd48ad7b07bcf09647f2dcce6274411b26e3762712caeb75cc292c1c7b5459209b82e28d9c57f7b2ebb43475e433ac2fc5ca294915db35ee4dc021e564469b246fe0bf0658d21904f1015c47f0aca65e151a7832cf200af284516df656292fcd9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1eef0b4a04d008f0b2fa0feb7eca4e75fdb9d6354543c27b32182db3708b8bcbaef005a140bf0836634f8f29ed89afd2cbb2c300a9299217a7fbc9c4ebf4da0e	1638540889000000	1639145689000000	1702217689000000	1796825689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	236
\\x290a94b5abd9b16c129941801cbf9ea54261963c0c332df12f8b332a89f170f77acd3d7af5a0232eeb54ebd6cb4e201f54ab586da977c1b572c1eae0e62fc35c	\\x00800003ef956ac87a5258797f7f0e478cf47a89a927e5115f75a610bb75e6554db3505a9f2d13f5d88b4a0e5c092ab36dfdac919450d3db2c4de35d62f2a423a12bdfc805ead4b5daee59b9dc6e8522425c8801615debe8b08447d3b61e46eec39fcdcf35bcb795814d00e4c085b4425f3d162b86ddc79490a9b733ffb6063e778ca3a3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2b3cbd8a26010a903dcc949a3ef7d3c1379278016a6d0a05fe8e13e83a69762bd3dc174b36142ba5a0b4a750efc5384f2cb986a5596dfe3fcfc3539ef497fc02	1619801389000000	1620406189000000	1683478189000000	1778086189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	237
\\x2a46fd844c3ec78e82877dffa1bc73b5bee2bb1d735f603d042eafed3b50d3e4f18fcc9e63a9edc16b48e13f5fe9d9d9957f63e598cee449abdcb4d1ac6e8640	\\x00800003a84fbdcf6152b670307709ea4f2f46645112ed9fb1817abc5b7f65e4a44dc346ecf178e58fc3c14a234cf81013af97f9c2642bbadda7d50f499eab0c965b07390cc4ae8d24b83abdcf920383c0eda2c8e0332453a24a08061b8692abbb7585575252a629132ed104b3feb26f8fce226bcef0d748ffd3a64070fc5384d3f557b1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xfbc1867bda10094765fb84bdbbcf7e5091631579ab2004f12502c986d4ca6ecafe38982b5d7bc75a949c6c65a029893110e5cd9850feb5a9b8c801ffa2c66e01	1611942889000000	1612547689000000	1675619689000000	1770227689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	238
\\x2b72c64e78aac769c11d2a41f1e59232608781e0c5fbf9b557fbe098035df3346c5ed13059ed09ec9e4cd8001773aea8968c4110d724b757576533c1751a99b8	\\x00800003c84c4aa910df17439e2e1c3363a1183b6c11e082da286f948c04fc9076a2b087c992d4064af59db4a84022346aa841a945f3c93d31bf3389b8322e155cb608fda52ab517af8cd74654a358a686a45a90eff8d0d1634387e78d80f9cb6e41b80ab06e2a2894424f26742c5cb6b2e39728812fd46aa6c455209d275e49eeb69add010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8df50fd97b5a061d1cf3e3874d69bcd3255104754c72c7148af369dfad4bcd970733ead5d2cedb613e81ef1a664902c75c951def2284c90d6bf9b70a4f76fb0b	1631891389000000	1632496189000000	1695568189000000	1790176189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	239
\\x30825d0da933a57ad6d36a8ffc8a1c6a3a687a7ccd2cb11c10cb33736c5e840202b0dcb498ae93c150f83e0e8021d8f03c7d04b899f6162cfa36d8e6a1fe8d31	\\x00800003cb8f4c83c6d3563646ceacf021f7f3985a19748b64306302828c12b3a4ff93cb88eb43f81dd179f256ee5675837951a084043ecd7b0519fba0643592f9c893d15be8f99f5153fb6a297f3ba47b524c6211db7fd5d62719b3f34a757890dba4529a7d6fc78a644a59348724429e979c5197a21b77bd2c926efa804b5623b76ea7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1a886ae8962c97a471a8aee5644185338a3b009bd46cc96e20c7d2c64e7708572c1c9bfbd95b902a81dc7ea08b7579684bed5a77f230f4294eae84c70ae6f10f	1622219389000000	1622824189000000	1685896189000000	1780504189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	240
\\x30cecc0a3e46300362b98eb9a4902b55bd62921f39f6c8730bc1520225c72ab5696e6ec64ccb50cc062096753181eb75236dceb16b69e38a079d3885ce6217d5	\\x00800003d387ad70a6184be1deddd670cd3f8abf1950ddf8bb73f17e42dd90ddf876161022093ec0064133fee80af32504d938dff3da66c7e1cc25280656b8a9ab2e13943f165b06285019cc193451b9d994ec76acf6d320f2165d4ae3a6d669d028d51382c4a07bd998d3696797857cfbf04a1fbaa3726ad9d0f3ef89543360e7ff36e9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6ade9188256c0df6ce198b968c28eb68adbb2a7c5b6e0828138b969303798ff2cd34fa646c0832808ebaa603aac4cce607a7993c1a5e643ca7c6e96b17899606	1635518389000000	1636123189000000	1699195189000000	1793803189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	241
\\x3182b8a68d54a93d00ee7db4f61cab51e18f13acea5aa991ff8fac89bee4a5789078e942f11b21cc2fc5e970b2357961523e31051e5545867f956f4dd61f1adb	\\x00800003c44bdac4d901fef23a67c34bd4396b2252965a45b1c20f4742301355db118ae1f01166852d6d060617ff26dfb22c3f383ec1b8fa40fc32232c488503539f8d727cf84a058b716ef7e37dc4085f9aac7ea6776750ba76ce850d9c956f1522c373c68db626c2e0c609e411d691f27acfb38c015782ff972dc00e5973b279842e1d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb063d16922acf4817872d6bcfa07f4daa715a9697496c6e1c51b03d2b1622fa9fa10a36ebb5fc801447f24bf0b1b53da34a50a1f3b8e4e1697bc6a9eb53ae70e	1639749889000000	1640354689000000	1703426689000000	1798034689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	242
\\x33361c7682155d887a863ecb51c06dc2e625ce3ab7cfdfd2bb985d8eef968d5a8fe8000cd662b930f6d926420ef592b2c2c7d6540d19bf1aaf7d485c2d062765	\\x00800003dd86ecd99def694215d6dccf0ef82f90af5d09bfb2ca79eab7ae3fbf668a688ed92d3b8e5d63371b479c99fdf9a1515149a5d078052fa35152c30a5a9d80ef5e6ba7896217a136d49508cac875146b89f0f85e733c28c684e00129ecbeec6d11966422c7f70ac82bd695c39ea04de9f18f79060a50d64e452e24976446e39587010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe25757b496ee14072889178bfd8dff5e1f725c1c20e068f44f6f14d277a8dc2f8192325b1d599798c9434e76e15b2a0816e434b3333487c81a5b2c8bf48b900c	1632495889000000	1633100689000000	1696172689000000	1790780689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x35162307623a65b52a788d2a6b3029b855441e5494c83986230a2d9b8a7df57af7a6073167368dec09d01a856fa6a969dd058ea9c5601e8ef16ed9c2226133b5	\\x00800003c575f820a4309de70ec12d1027dce9da174f4326e63088e7036f149179cd4fdf326d56a67d4feaafb56103bd28293aa00fc8a1deb0bcdb581a69511d59f607bc7c5072517106384dcaf619459b2be5a828ca15bd6be1a8a2b7dcaf30780fcd73bb33c326b6f7c023a03b665b2aeedf69e91d67a7cb3bee68463fa05fc1e47b87010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3f3b2c766f120936bedd55b5c30d89efc96f176e7bf3528b7eabbd0024fba46ae8f3f87bcabc510d687a34cbf936cc505f793f62fbbea82c1ba4755811a0c30f	1636122889000000	1636727689000000	1699799689000000	1794407689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	244
\\x352ed6c68f383b0342dc17cb68170ab6dc4e9ae2c84fa6bf7667177c9d76f0db1181e5d4f7cd243f45fa35f6328ba2d565caccf1a45211fe2917759f298d0fab	\\x00800003d2c961d2a968dcedf90b41f9f7ff1e8acbf7bf8b45a778b7ee9f850be2e84c577237a49bbedd35bc29b2151224544eee1759ab3806781230c821c8f65e210930f3f09ff69f03a5fe7fb156991798a3e4d8077ac34e848f4ac2721f0a37a2b9c0a73c42c1af0cf4675661b9d49b4936c7285cfbd03fa74c286fbc6f180ba59d43010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x062e486d965aad2c073d577edabbf21cf53e321c50f94b670121a494f2061aa1ad81d6ee04f2531755a2220e26649da6cf51e8bc0ec5e8eda50b67826cbbe409	1641563389000000	1642168189000000	1705240189000000	1799848189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	245
\\x394224ad0cfdf34cdc67cb663dde1bb9eea5ae6cd6543fe54fd94f78f00cdf96e1c8b47a3658227259c5cf8bdceaca96515eddb60811d2d7d69c989dc5a3ac6c	\\x00800003cd1efa545bf8cc1b119f467682cdae2be582616fb18adec53c51cf0141fcb8ed10acbcb86eeb603f1d2c689e137b1bcd1b21c2735131758c54885fc7848cc170925078bde0ba4c582753b5693de814ad835d0dba9fbc2fbd9da76473165d7abb23f1672dadcdf7f3245922b5bc0ac6ca5cea45f24b66505765c1d59fae0a2b39010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6e707e99994a78711d9414197aa3d77ca7eb62ac4a1ea456b35da4ce0dacc3223899fa0ad78087fc8ed152d9bc87a5f461022cf9b303527b957ede8a0337e501	1622823889000000	1623428689000000	1686500689000000	1781108689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x3972375b33bfcffdc8cb6b666864670ba60e5550feec8ee812f6c463d42be36234369811e5ba18e60b92fcc2779957a56c985f92e128f1c7f00ecca7df2b8a72	\\x00800003a299ff2dbf9d04f103e262cf781c87ae621e97c39ceec120c01780929dcb7bf7d6a1f35549792996683e3a6fb826a00c4f44a592e60c92c4baf0b6eaa69b98d796ef1dd353516b1ff3d9dd168c1e8ddfad9ac186bbddb6fc3ac821d6a06ef45f4bf6ba87f3b847ab0d0329c38817c29d9ba654f804305516866c0542f885f6c7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xebe2fe484617ace0726feb6cab64df1050fce9aaec071bff1c1a4b727b7102cb9e4d7a7add103851ec6dcca329991fc52e7ae83ae6e615d9c277584b01e95605	1614965389000000	1615570189000000	1678642189000000	1773250189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	247
\\x3b1ad692896011c1f2d9598c7ea1ff8bd384b4127e617770a0dfc8bba67e1e1208cdbb9163163d985cad921005519e16a0f7de0fcfcde79223a671d9b164dd37	\\x00800003a9c30cf5193586329e7c07009399a87c244ad605fc5872432beaa605088a84e9ac4deef64be65720b9d66c3e6308f78deb47fc9106a39e56c3b43976ca470cf1e8ee72f6f390e4710b0aeb82eca1a462113d8e797ee94bf9d26ebb3bce9f3b8524e1d9427025b305858c511c699620100f2d1fe4f5d0cd92662be0cabb3114a1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdec5f9d7c35222c5e34a0ebcf816c8a76f8e17b949acdf1192a57b14569118f7b463d414af8c8a7805131c005baeff883f86514f933a77b53942f565dfde3603	1621614889000000	1622219689000000	1685291689000000	1779899689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	248
\\x41bec7b373c80d6557064f1fff0f63534e323d1d30c94a40450d9b1b78e4b2ff62b7b47f8d9efcf7de0adc5bc61b2ce07a40155bdd0205dbc8348cc22a0f6809	\\x00800003d198260f267995a9705487928014566c1794a988ebaf061fb013134e1e6a7013f7e962551cca7f4bd4eab2f8b6ba159f7cc21feaadc028c18adbfeed1540a29dc0db23b60aad073d7d16183aee5c4d5e92e7802f6bbef2e8456bc491059764f0f8b6b152a7bde2cbc431989c930470582f0e0109127f1fae99d914701d594823010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9c461a59381416df41d206f870cc435a12ef091b70468679249215b17c28d3ab35b55ba31372991a65cc0225fd33967eb0dfd27cbfbd9f74073584f6bca5eb09	1619196889000000	1619801689000000	1682873689000000	1777481689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	249
\\x4efe89612ad37691353d36c6614e72cff439a2aa8c0b407392cbfbc203f9ef4c213e5c4d71207af1eca2681649762978491def629cbc0f6faeefd04a907eb589	\\x00800003a097ee5f86a9a17016e5e62cb405b7fb991b3be2e0a10278fdde5b7c61b14a518787c4009364fd336a2e6bc196f4a1d1fdf38eaf77e63d19a31853aa6efde38b81f20bb2a93aced9ff5b56c208d7402ce8bd096b7fa5b766799a4f2cba2472ca169622e330bf08c9aed785b5e1d942e41f4b430b9a32fa8fdfac4ffb9c5eac8f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9ca107aca41d7cac1d94fc01c36aeb6a9956d32068c309a3746b672b1f28f83333ee7444ec407f56d614d2156b5aa99e10313c469ee6d989412e8430e7fa8c02	1610129389000000	1610734189000000	1673806189000000	1768414189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	250
\\x53f62afd796ead13e86d588a2ba714c907d98e15812d3dfefdfd17c158d181184b8918e48099d77a00e60609b82f6353e714d3ecb9b847eb40f80d334b2c865a	\\x00800003c537fb26d648f82409c2b12d4d5e6ed85307bee4431e725a755b4275c02c1f74f3f368ed9b5b1d9d1a9fcfa9680e2c823afedec29d7fc892836e90fd451b41bdbe9c526cf12ca5b1bbf267f646d28e0cd5955b8e30f62a60971d872e98358bd48569bb22de49ac964f53448b3c4d7ded87f3aa8b9fd02cd01f139896e8ae2549010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb879bf2b21c8c3c4629f2ad0b083cbf3cfd0bbdb1084fc1b02016061169d64751af688655114af0ef2bc8e7bc6b22613f8473e98210264c34102cf4655ba8705	1633100389000000	1633705189000000	1696777189000000	1791385189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	251
\\x5b3ea5bc191f85dbbbb3ba7b0de8e894d4f8c8e3efbf3ae2ea4559fb0d0293fc7da67591bd9f019603e770a03004a710a39c87d1befa4151041e30b24f897b6a	\\x00800003b0220d2d2899d36d406881491fd10214f48f40c6cc8facd669e99c58e4a3e24af95663a6aaae012d479b2a904cf610e4ec3b61f7d5f2a73a44427a57ac03d7c140945d8f1696670dfc52fd30eabaf49f7c4f641a6b3f31ce5c3429d2e1d3b4a07d7a8715a7d65434d99c54e08f0e0b9a70456bf02899c04bbc65f32ea5e41bc3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x90080ea68c64806e48444fef8f79f418dd7b2a4e7966113cae2f2322a92015b76cbb30c7c7df2604931a1480ac352efc60765f573528bae8dc5c1459bb1fb804	1628264389000000	1628869189000000	1691941189000000	1786549189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	252
\\x607278380036806cbff4bc85121a301ecd12eee4cdadd2e45e2ea36da0d37a1d631b2288fac34e62318403a3c6a8c13f4db5be43c3ce2566af76394b39054266	\\x00800003b1b0645db4d701a2520efbdc4cc22d25ed4790cc1fe96837f611f659b381d2fc317e5521243e69a3a05d5ecca1c025d99240c349d3b27e8fa051546cfcb36532038ab9d68881947fe830ea92b1c0d94e41d63cb81a0f998df6ec8de36abc9f38567306bed33f6700f31db45c0031a4fc9bd3cc982471d0438326b993172e367f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x49f83f2c756764428ef3fbc5a9522f916fcb162a6680d8ca29d69ac4c43ca5cbc9b2a62337f34caa51fcdb1c387d4f110407eb111a301136749bcbc0a494d604	1639749889000000	1640354689000000	1703426689000000	1798034689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	253
\\x60aefef7f299f221ae7a8a57f63b709d21c2ef3a5c911ffa6f1365c19c4846086222a56f3f2a03c41ee6979c5b0491e5463061b79d8ee6083de00aaac7530ee7	\\x00800003edbf2a3e7b98523f4149d87b5e8fbaea90df3b1065d88145f07324e5a61a858abc79586ec8d8b5cf62e00634b759c262489567c3802e6a6893e8097f73edd5d5e3e86b70793d5dbeaca42ca423b124df3434ab6fa955533d9aa5e564191d299238ea34c3d061d588d83bec3f5b99865104c36e7c8c74e7327c1b7980745af9db010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc1a2ff408d388dc02b8e097bac287adf8abebf0b3496427740d3ed2227b6fc5136d9627bbecbde5a9dbc92fda176e28fd43182be0a1cea03a4788a2cca4cfd08	1632495889000000	1633100689000000	1696172689000000	1790780689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	254
\\x64661b66b4d5d0dbd91a626fdfe78026b630b9df84f680c065a205c6d7b37fb2cf6d170a8be81906f4357cfe064cf9a7b8fb18e82e67a175aa4b9d5d9053e9db	\\x00800003bd97b8707a21d1e059fa84ce93462f53e5f467d6ccca7b75faa5d7e10f5d270a9394bddae8693b01c1e755a36c095c17d14d2631d3d3fb5dd33561e5c4687f68e192a267120af6f082c3ae5a680c1e6de5a47f1cd0a6281322cfa9d969bd2cd7e46af3c7f54891786e35035ba101e11748a087896b244090ba18d3df81511da1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd1f1ebf23e76b7af469d758041f99a6c6cc817e96c04cb2c46389b54337dbc4e6a182c6d8b629b70fb066269de0bbbdea12f03be029f345440153e7583771709	1623428389000000	1624033189000000	1687105189000000	1781713189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	255
\\x6962757b008b84da305ad8fe54e8d077e8c2c57a8dc0533f7fdef0b796854889846d2a0a06261f2845026a33fda2116d44f8bb10b02f823a0ab3c868f850e286	\\x00800003dfeb209f602c82f2fed351ba0b5dda78e981b706c2a2a6a2c53308c32da8c0a60a67225516acc3cc95a7006bfae82a1a621c013c2ff056d3d0af004b24065aeb2d88ca655cf984cc7251fb989a65f0e6954529556f908396d58fccc93bba224130c72cda5cd949bcc3078738ba73bc4b094c1525c20fb0c8b7702241d39f0bc7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb5c14479788e0be6ab0eec8d1045b8101383cc68a3d9aa52b7a991336850809960c4ce5579041edac3778cde90f08de379ef48a33436fd2ba4920b8e28bce205	1636122889000000	1636727689000000	1699799689000000	1794407689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	256
\\x6af27e64eccfb72afae0265fb1c6b6469dece78536a5dd00b5a08db18d57c3dcee928642aa89be1c1187851625d567f69932fe90a6d9a3425ba1f5026d4e052d	\\x00800003dec8b9d303c34731049dc6d8f34e6878cb06518008e3b2ed7c64ad1cd324e6a1eb9eacc0d6402b739addae2b381729ca17fcca77baed3fd6e12c4bc6482308fb526c979df2d24fbdd5cae5596f0af9df93af6d87097c6fe6560cd1f2aa52d8a0e04ad9c9783661b6211ffc52d080effa9fb3b1d7ae148989cbfe5d7c33ea4787010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdcb42baee0d465d1bb9cd5ad3380bfeebd6ae8cddbedee30a8f0efad1c6795bb597ecf2e4913680e0900a161718ee7658c029be04034cbe6439cfef4d7b2b30f	1638540889000000	1639145689000000	1702217689000000	1796825689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	257
\\x6d9e40d272c719747de77b1a7489830eae65589f8410c20c431057a54bc2fd63119395181d808e458d39222059d2a6cbb4bf4e4c6be986764bdc9baa4e036410	\\x00800003cc4f47665a990cfea93a589a035b36b24eeb46c1d7748cf07409813a4e928a88358414be261c03b47c9464a5d454f7537b21099c108ea05e851fe9585833fb80d900648cc82261663c9b869287e5412626f5626a3b8877a86fc4b9c30aa59cc9a22721db2dd5ef5dbf6ec0a61537ce8a4a5ec6de9ae39d26f5c34af7f4cdeab3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7ba67be49ee90c480ce81353cd4ced2a66143fe96107e7893a238c187857bfe01e5a1125c15954f110f203bb9ef972377b26db46045fd49de4c1f9c6d417720b	1641563389000000	1642168189000000	1705240189000000	1799848189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	258
\\x736a749731bcb16a8a1d10f2268a4055cbf0f40abfb61baccecc5c7a9226548368fdb59b97f65232cd7b1d429520fa6ce36992520032cb166d6a499505bfd742	\\x00800003ce3c9ddf595208e18d063fb1c0e80b2c7fde52fdfdbc794ead397784d06992aee5f1c8f4c2e09e4a27d86605349726456211864dc39115b8d1abb6c744caad26cddd08c72c392226a97b61205cefee4337b94df98065445c6ffa0d02fddea3fbceb18f77eeb43827866f79bf40f2a493b7b195a6e059f2c6927080bbba775863010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa28773ae11f53f8939bdfa04b489fb5e21713a5e2d85ba9abe70f31d640ce11a823df52b80b0941306deaf5eda1231d61a38d8e98d66cdbd5cfdf96130b3a50e	1640958889000000	1641563689000000	1704635689000000	1799243689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x73e68a347319f5fb1855f97e7f664313e498b972e61b9c2892f13560b3fc12ddd85160c133529cd1ba2ec2e0bedaa50a43ba33010d24d3a73b7089a182cddf3e	\\x00800003be34a2d98ef01ba3e728e2a9361f9b5c5f6a33da36eff19844bbb6a48a107023f29f1eaf116da1847860f36705b1eb9d3180def5db32953897a917e9dc1e1e119343f629846f06fbca285945c66158c188199a556290ec42e3e49f71fae37178ed453f8336a7a4c6c147d21628ab456bd5285162b142bbdfb6aabb78708ca3f5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1c8246e0487cde71ebdc91fe0c7e74a917b19898145cc08d72eefa974c02592fa716ccb7c912043008bcbd55addbd8ee9db40c094557d30558e3dbc22bdf5f0c	1618592389000000	1619197189000000	1682269189000000	1776877189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x78ce8a3f39db41d470c5ffea0307cf7df7f51263b7dbfc98cebf22341c2722c33ec62bdef53f3cc96aeabf8fe5c9cc5a1ad7f5cb25a398d30c392bb65a09afbb	\\x00800003c4bf2b9255053f4847442d22dbfb80500f34ee2026293be67c008aab062d39e02f127567bc5a65f38e50a65afde15e1fd163c557e85936c1af19c22d710ff3bd9eb54ee7097d0c945f8f599cefdd810d11ba87b62dd4f3d06af8f7ca5ca8967869135b85fb476e7e9bc5184285837bd03bb07e03d997587f4efd8144f0b55cd5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd94f51c14fb8210e4271368831623df343fc5ad0bf0c91b9ea6c0a3f5308d854d58b0c5cfa5ae40617055757f69e29929b3b3bf95c0bd06b225e6b24e436cf0e	1640958889000000	1641563689000000	1704635689000000	1799243689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	261
\\x7cf673e9f5e37c2455de29c4042f563f5e8ab4bf4c6a3606c61ab494fe72794d7d74370075533536b1535db420fa7c69ff23edd27030af871ae1958b83ac8d93	\\x00800003a3be9c45596078a9f6355c60e7c035556f999d3599fc7a3360909be43eaf332f4d5c78cf8283afcfdcc3b57be5c77b836ae7b252f4edd0d303576658baeb8d2c8aa2f47c5c4a1d3441e978d8d50f84774c26b4676c3a33b33dfa8f352656211a9e1ed786a7f407e0beba618449a85680ab43ae42b31e0d30d61a18bfec27d14d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x170bae7ecf47acd130fcd771a42609a6e74243aab1766ef37d9aad0306905898eeba98e7aa93b2280aef467662f7bccd292fb2a60164e4716f54381428237406	1635518389000000	1636123189000000	1699195189000000	1793803189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x7c0ee451eb5d19c42e99740e673cb01f932d68977a1da03c97514d3b740f7096a80fdf496532010bbcb1432e998635377de9f06b6032b754fe0bee978154aa12	\\x00800003e8b07f98432743c7b04c4182de2a919fffb024a17d03f8cfe80432afc64f20c7a17fd4bf271ec546bbc6ef2ae823cedb9eb2b3eac93f48e4d42113d3265cd86eed8871c93cdaefe532cbb32dc6e3242145da4629d8333149c66738d4272114900e90bab87083e8100240d3c946a62d73c2dfb08ac2cb479d7fc79fb9365b170d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x81cc80dc4ff45905751330a38b1ebf8abbeec6a2bf626763a0fbeffd20d9d581210acc01b414dfc717f55a296eeebd13f9367da3a67e642160804ed07bc4b100	1619196889000000	1619801689000000	1682873689000000	1777481689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	263
\\x7c529a54424f29291861defd8c3785703fe815d55c2e8ee6111dc18f5d59f68c7904c98cb853a24bcc39feb23c44eccca1b963ce2f8ee143f0fc50bcb2f333c6	\\x00800003cbd060b856203f3dde431cf446a07990472f105b72fbf93098c0252bff41c75753d03c9fc180b33b89032786ad16ced5a79e5ccb1d2d8948e60bff5b3a671081161b3aab1ee6a58280076fde3ef1539fd0f88d2f1d719cbdc279312c6deae12282a84e54fc45b1db3e91e17425cc52a05b13bd4e8a36f15088b3707001e6dfc5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcc5302247ea2022511e70bfb23197cecd1c9f5515eccfa83fedb4199a92fadfe2b223c34303785ec67b1ee152806e869a4d18269759cc4f9d6e13820b60d1601	1623428389000000	1624033189000000	1687105189000000	1781713189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	264
\\x83121a00eed1482d2940a4a2c7b7913173c4aaceaa7ed8c9b229ce984ec5531d5dd71f4d36d9719b327e6e0d7e2bbda931112f9ed3dee4f381c64d7b6deb078a	\\x00800003a2b0c65a6b66dad1217ff1aee4e087c43863d1fa205947e638957d7ae75b0514b94e5811b8f265056e358d546b6a490b0c9cf7604ec764c225181c3469a3c45e0813d1b04304dbbd0b0179abadf4f1f71a96e2cd22a7da68af95cdaed92fc43527ac449e32fb51107f42e5c8b059d76a789911897e576773ee38c956aa31c5bb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7c66070ddd15267599cfd0f66ce9d22a8b321626e4b05116a0056e730890fcf2b3023670a275fbd2b014b517899a211e693e007c287d438ab1668418ea9d2b06	1611942889000000	1612547689000000	1675619689000000	1770227689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x84266751d4f35873024cf6ae01ae36b319a3487b3885ac0720810e803a98f1c2763fd579ef430c8d2a833ad09e932fd3a9c1bc359b090d2de549a095fec95fac	\\x00800003b8ed023982a63baeb3c2d45f04c6720f9b990ae46397e7f3f1e3d837685c9cef6ed483ecdb7c5a156cc49202ea349dbb29d1b7c3952b8d29f3b79155b3b053e06b2cfce9ecd3259e3cef53ea0df66b19cb0d7a84ba65c2821245b5f5c7d195b1802034fc87c087e4a0f6f07085ef0a2c03d915bc175a7daf1916cdaebd567be7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x33c49dfc8e74aa4d1b3a776a108f1f216b1d7e1404cef77fa6af8d67d31655fb673b2157f602293a25620fb46b53cbf7cb2290c25741d9c33278f7b7c88d0506	1620405889000000	1621010689000000	1684082689000000	1778690689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	266
\\x84a2f4966db576a513f14415b0a682240bd12028056630f87e6c0e8fe72bbbbb78209f04002081b354d215962d90fff0eeb62dddbc653cbfcca79f236720fe9b	\\x00800003e4cffa313741e973a03aebf90e82ea414183d8cecb817b2b463460945ee40207eec7aafd5111e52b4ccb40d244d580bf524127732103be6cfd8939e86a6b2ebd5153485d1706e28d0abb314c8817abace06ba19e8226b984aed6b33d1daf9e76057dc45fd3911eb3268f3b3ee093ede72296828df7b8ea382b83e61e88b037e1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe256a2174070f8bfd0243c1d61fee89a8022f9a5c6ca06db9b6539f60aa28bcf61140126ba31bc2c52c6ff3c0b048d139edfdf408eba56dbc9e73e5af9530106	1624032889000000	1624637689000000	1687709689000000	1782317689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	267
\\x854a813305edeccd0629e326c0db3d0651138ca8ba5632ac1ae202deb66ca9970b785a9a888efa07f921d820a58d544d2a7077b4e2ce7893d5289cf65f30c297	\\x00800003ae1d72454765a04a4a0d3da4fe7bc1eb24958e9903a7876dea1dbf1e0cce17eecb292f4b2716eee59ab2166e1e57d06f747965ed5b83150e6b93dda01796f0d846bfa87d74734058c9d1592bbdb59a4f6523e92bf3dcf13a162b7d2760ed6e543a4ceb1210d0b88a361e0882d0a82d3b1950db62e4a80bcfca7a2a75242a9995010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa5d47c396c9a9afa21bb94054773c183c74fa5092549e6cfc699e823d330003d02f9f6cefa4937e3d6076e2d807f54bc61d937c53621ae0c94ee73d14b62680b	1623428389000000	1624033189000000	1687105189000000	1781713189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	268
\\x8632ffd5dacc0a9454ea9a54e3a6c3ae3221bd45cafe1b59a982f62523682af3553a9f23668c31cbf345cc7bb4ca9db8c5e21fbb248280e592e3fce18c5a4276	\\x00800003b1c5ce015ca0c371ecca2370cf22beb6107b89828166ecec0f2e042437926c8e64ebb5d389eb95439cfd5c0944cc9095947a89576b954186347eb85c2151c41d60f6c46ed9593ac8065aaa34669ca32dd8a936989f4e28a8a9a6cba9feeaf6ab0d3c0ec960298f37c8dcd02adbb2460c440a8ae1e427c205cc42daec427772c3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0a0d590c0aa0b29356505003131fb34f19c3861e20a4da5ed0650bfb93778c13aa9714687d1600a4c4f7768e080a212da40d72a338cbd49ee453772249a8930e	1613756389000000	1614361189000000	1677433189000000	1772041189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	269
\\x89cea3d5ac187e6530166899fa6a7dd12411efddc3f14ffb4f906d77ca565015305de583dc68dce227323cec9d1edc4ec02eeae7975b6d4d56da29303921fd52	\\x00800003982aa92e2f26faec850273aae417d48bc45365b4333fc2d7b3ca6df2de954682763c94e417a7377faee59f91863e94120baa0977d3354382a47a0d626c214d9b5bfa5e21e1486b00c41eb3c58abf8dfcb2ac56c7b058f6b8bb01f861b74ba8ad1f1a445e0b50054278962fd6f683728c7fb1cc235ce327b2cd09a9caedff8f47010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x25dc18a496e98c4b2c3b0dfe7fe434c885927f81ac907571dd0f6df62ec38b230190eb300eed345959b8d931299ba91422c208d7a29f0abdde35ebaa5012380a	1624032889000000	1624637689000000	1687709689000000	1782317689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	270
\\x8ecada189c4b1f207bdc9e1ae5fd805b8e4a3e8ff6d0628b62e080ce2cb3dcef5afafaa12ef7576b21a54cb4a82cc6366966d7bc7977e8ebc5c4f38e5c8c4370	\\x00800003bb30d78d15e803d39fd7293182a4a69f7a5d5e60ba29c4c2e2b3e9284decfc1f627401072ab7188c33a1324a34e71efb7cf4c297b13ed01bc2c61651a960573a8faa7096d0ef85bdbf0aec153733811adf2f20006a3c4913e2d533caf82cdc2c0e9d0d86b2b2a684114f8558db22ef7cb4e05dcd7697721b88011636f0b4861b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7380afeb14015e4e0217cddd8b6bf2fbbd02c740104faa3bcd908611228ee4b72a569f2569abf285a01f3f44684ea1e0814b49b28efc7f5d097c15e8fd096700	1624637389000000	1625242189000000	1688314189000000	1782922189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	271
\\x8f4a0b68d2c43cfef8501eee09db248e52430449ae5b38554c8a01426ca38cef65d4dd9aee1ac239e28b1ae81a91251c56afe17124b58e8d7c4412572e151772	\\x00800003e992039fdd457ec7543b8d7a1d70ec8c551411e8d725afa052b79ca5cacc41e0d3e710727d9220c7675f3174086790f7ae76ba01648f164f212780883f00c32ad842517b1278204366c1e7c8d70564db4f9a54fc7e10e9e6e269e284db12ba0b2e244332cfd4cdba3e30419f7004d3dd668a35e0a8f2eac7f7b312e4049071df010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x88c95bb6c1d4706ecf7b5962dba8544f6410d285727f22f19691b1c37ae4d2d337593f35d15c9256f572a178cd3fbafc4df0111c0b5bd57ced97526bafa80105	1627055389000000	1627660189000000	1690732189000000	1785340189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	272
\\x90fe468f3d13ede939126366f6e3ffcbd7e8f510ed61d6a5258a0caadfe0b8d56b1649ff8de277daf2cdf906979033bacbbbedc0ac8900e4bdbd5032c2069958	\\x00800003b67923f07588a2fa01574280fd45c7d0c6a44855f6ba513f649aeaee535b6130d9c26cfdf9c303f60d5b1a21f97d9b7ab312e74b379a15cbd6a3e66edba67be7dd6a784052eef5e8451b05be22c07168862464aec2ede22489ff2c0a6c5ab8cb0727aec1706eb2ddc28ecfc9c147e9e429ec93b61e9413c5053cf2f088cba201010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcf882a05156226a615f1f9be86458a237c055269daf24c2eb435c24893ead62ef31ecf34d62a6b0610706202bb541626073543064f7a7b7554b3f90f01556901	1610733889000000	1611338689000000	1674410689000000	1769018689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	273
\\x936a1ee5e6054253a5fd247207ca171ae2541a00dad5f309583c66a1385939c25b3ef8b1d4770d9c837f55a13f9267d63f4c267b0d20e0fcbdd91499f6537fdd	\\x00800003d84a63fda9761b2ae2a7e5dd8d17b3883e6c9fd0ac09da20d28f885df5a7a8a9ecf9abf7218d89a73f0c5debdf676c46100b2e757457685c37a9fee8cabcd70d40df5eb6c3739f2b7013e1f7cbc31350256056a967ec49bf051188a08cfce47a0b1438e18c04a6a9101dd6acfb072960b81eceaecade4f0f191ae02780daab3f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x63060706952ea188ad9d5ae950b60346182d0b448c0b7ff3ebf570f14bf6d2f09f0f3f3faa886ffdd8e64a4c6628d611b23227dee551ccf5fc6bf8241bde9001	1615569889000000	1616174689000000	1679246689000000	1773854689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	274
\\x946646944bdd07bbbfc6851d97ddee0d97c1f90fa7146978789e57b2f46a19a7c1c1c60551a0ae2acc7dacac1f4076efbff2d52333d721f6f4e318abd3dce0e0	\\x00800003c2db21e7a29a5593baefd39d3c75a823da00e69e1d0257827855d4c5830ad191a6e1d88aa402bcccd897514f8aabdd57b71ca6be841f00917d908ea539b13b0c24bb852b300e85bdec1d4993b9b1faf1cdf662c55205c4cf6c5a628b45e75e0053afe6be8e2d7852aa08b376372b77ff3a57e1d75f7069e3f1b0722beadc5109010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x25a320451dabbd2c46dd9e6ab36a8608d96f8e30a1b5ed1377cc3e618840537609e9267819ba889ea5ba621084ee89ddb1edfb117a6c5221dc1f419884470401	1638540889000000	1639145689000000	1702217689000000	1796825689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	275
\\x961662a7f8be282e807ccd7cf280dac3b7c115d05a1629f04ea5c50e8987f8ccc2808954f1f84343468e1e0c18dc1433cd371357326a7bf8acd3da03900466d3	\\x00800003aa17a7f3e8818dfd0641402c8a8420cc91b3352353fe1b981c189b2a659821036cdc8be78f6a19a0c49431bce0fcba520988bf5bc96c5ed34dd50481627c99b56978bb9e7fdd6d3f780227af5f8b415f75b26368ca62338e21d5370147251cf1d6d203bb383198b55c0aa37bafb046f989b4d7fa2e5d7fd248babd3ad936d14b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc899fe9dc988b134fb6204159cbb7b53ca3a6967cbb2103f965c3dd85d3e02b401f9fde4501e9e4c4b19d09e1e31b4ff3e8271674ec2f60214ad3c1b0df0f20a	1633704889000000	1634309689000000	1697381689000000	1791989689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	276
\\x9726407a036fc97d1b3647590c5412a17acb0afb15984efe6ba41aa2722e84a0877821d7dc68a0f34b4861c5107569ba050397ed22317aaa8e9ddee9767f7ffb	\\x00800003bc0fd5d2c2cdcab57ef3cd1bbb4c482d9601aa07d170311828afabc9f4ecbc6fea132520a2d5f833b25eca9d17382452fc9f4bea7cc432dd569cf54ac08539b9b8d85c35fa058ce8e152ed3c9320b610c0becff73bf98dd93476074754574faf1a8b56c40bda7379f4eb56a69802cc7384545e6970b18e7c678ea15fb0271035010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe8c85e2fee01918cd18484aea3138dc60e416259008eeb197894586ce8133852267ed36b4f02b9256ceaea0e82f49c0f4a4ffa3839a9a667ef753667d7cf900e	1619801389000000	1620406189000000	1683478189000000	1778086189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	277
\\x99e638e20b6931528e4dddf873ca87bc6c3e9fbd5b370f27d3d8b6691b611424cd0180cfc6b92a21064b170fa875ba10ba82806eb730e3ccfbbbd650f93a6602	\\x00800003d32c9e742a009c3d955d1965e6cc91785d07c3871b8a8b1f290e41a3fe94320ca1d07ddfba299e7790bb114aa9b986ae87e89b33735221ccaa9ffa5ebbd27f6a43e06ae6832e3d7f903921ec1da3b4c6a7d5700d298c7682a1d668a44baf8f07699530125ce6fab76b940a8979de6cc434db6e9e6a30fab9059db1a71c61e9b9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x744f6f951125684c0b977f081e53ea4668923049e0e78b9709ad0a9c8861e9f1e85d5f93300cd99677b82528af779e3433c483ec00fee95c49e988f6639d1506	1613151889000000	1613756689000000	1676828689000000	1771436689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	278
\\x9c529ae0d7170a3357b6876a432b2b292993e2140113f4f09cfef91399ce70133cd50da1e89a4997ab1b064462344e836d75d30c188b6fa0d5063df5e502cb1c	\\x00800003c130487c26af09590e9efaa313d891077058de88dac9c97c0cfc2bbc19082756215de18fb360a16f00747e6d3df0b43174ec39123b79676fc57d48becd22da18f424977bc57854da8340fe2dbfaf610fb78d4abd1e37b79d54490be6e3cfdbf5ff9f601dc9d7e2ddf16e98b6f622ae5269453ddd0bee79ed9c3ca09bba89ce81010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1ffdccce5acaa1a211b7d534f03ac8fd6f7c8687e5a325ab3a45cbf15b5280d69acf787199adfd84373b51a3b53b3499396100281aefdf398d0eb37be978df00	1634913889000000	1635518689000000	1698590689000000	1793198689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	279
\\x9e02edc3d6adb6e9b67718b2925e9e420da42195de58e9b5276b3f4a43639266b80dc8826000d029e4d1d6f5de8bb20fc514eeacac268fe6ec3437bce1423e39	\\x00800003b3fb539acfb8e531a0a75ead56e21e05a2ef8643a9c447acb78fc568b8889af6b012648cb0fd91dfd5065c59bf19e28664781807ccfe25492f6bbded219e07f2bd72c4150bd9e4379055f97d93cfb987378e6c15218da5d5659dbc023b806b46db574a27fa46a66c12593d05ce0fb642a9942743bddf4bed9837c8610de844b3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe5bbb9f199d9946c5886f746bb20f71cd34babe1740e5f207b9168df18a2b98d3f11c5efe82446a4a8a13ac6981f6c77ef6cb7d2686ad3b93d1802e6594d8e0f	1624032889000000	1624637689000000	1687709689000000	1782317689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	280
\\xa01a087ad3a4ecf247ee3e78ea274d1c3a6cce8fb2168239efae06d260f1374df42efffe62d2e5a54c3e7a93ece00982b17730d1fc26f1cc22a98ab03ad5db1e	\\x008000039ebed4546269ef65f38da8fc7130272da7f1d53d09b1fc7f566d37c6018fa708c0972fd09c371f4171c2a39fd9eaad68e9f73204e31e9fe5205c5751541e856476d91f6179bb25701cde1ed152858328fd87ac806b3b4ebd438987df95b408d21c75116087dde1cf5d8fd6c83eb43dfee145a40ce4c6585bb3835ce4b536d709010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x732f5e764a17289f17a044892d20bcb3598587f65322b8337e085a66402609053bf1f7bf8d20210c05a733a3ec7f8024ee70f98f903e8c100df77c0ad35a6e00	1640354389000000	1640959189000000	1704031189000000	1798639189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	281
\\xa1faee2a06179e8c1222cf535afaa859a4e494bd94966019dfa701f331e6d42c1a1f3371da2a16f737daf13d92e5be8c2e6575960f4d521190e1e8ef7b3f58c6	\\x00800003cc9a15c98f7fd514d3525a85614b11b23384a76fbd3e86bd55b7394d4ff6a7ac85025136b2282aeb5b071c884bd88ca99b353691028e5cc766f3402f9bcb580602961cd07af4dc59b6f43798f7133325c514230bf061ecf4673c8255725e2d102d5230daf5a84da5b420fa65d026693361cc4f5ffd9271117d3444542f5f44bd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2b0038d450c347f4fe447262077633940f5034ac5217aa97eb95b780312eea633019023f57d0e374719af81cd8f45b31981bb37b3b1edc596e8ae7580eef6403	1614360889000000	1614965689000000	1678037689000000	1772645689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	282
\\xa6de55299710a7640e9da6bd4c76a620d16ba7e72b9586662714b75c6ac57216a0c249062388757d38b10183680713219b71030fd628fbe7f1d9e33b636cb3c3	\\x00800003c30b37cdd43aafc3e85326aa1c6c32c9d5b51d12ff57ac4fffe116fabda009c74d78172cf4e960a87c1fcb66296840d10548bff30a980ff1e6d35e381a5fa4e4e892e7a34a5fb853bf1f6be3bfb05c94c009b461f72ef6875f5e038b0c17b83ee0d6ad3cfe82df12f16bc1d5ac635d0da6c92e62b4c8ef1469c2a945eb3aeb95010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa3b8afc02d8b8a587790a9639cc03e3947045fc1d831894874ba3eb49514c845b4fe5f30ae48952e31b74f4dcb95fa138f3c7bff2c0c778371aa9f05e44d4300	1636727389000000	1637332189000000	1700404189000000	1795012189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	283
\\xa79a2b7da2b5cbce2534a49969d206492e1350da00dbfd448b5758ead66afa9fecdac5824c162a1b047ff5e476a9ac56655673e280d41572f22f09397f32eb2b	\\x00800003dd51c85bc4527f92c34e6bf9af76c33fde88142a474ca3c15465134a75bca5a7c0204451b2ff5be87736f1dc259de4175be68a956b2d31de4f6aae9544fdd0ecec65eb2cc1b87b34f3bc4eaeed9c19fd0f7f5cab25902f4b3dd9afea91ad17f0cc5432d62dd6979d78e94fe80cb92fae97dc7bf2e7aebf50ed1a2d43568f26a7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd8917524387b5fbfecfd674c50272ae1fd58989c3cd80e182a9046618f0f875d355de038cd540beae25ba415af19910bd6f7a4984aca1ba96babf540c2c3dd0b	1621614889000000	1622219689000000	1685291689000000	1779899689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	284
\\xa856948615f2ead7b59ec592e81808909ced476b2e7c95855480618b6fc29b2470c004d787e7270092d7287e6b5267ed87b026b9fd06a4d86741b0bc7746bf87	\\x00800003c95bbba9ff4af048f569e1c735cd545ac4355be45e5577776cea77cf89521c86dddf5749f323d20446650b5c16ee4b271c1be05d423fe43a8c741d54ac9ef757485f5e4f427cf05bbdeb5d974a0bf1205b940f30c669eb8bd129fe03856459a67b954843da734b0a8ef80be303b376ec2edb49daea42f83a136a5fb253c99e93010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9fd0c68aefcddb241afc82e67a3a61d0b1d8942b421b2cdf04d61301f49c4b4b06bf9c205591524d689bad3295eefcb52a5d12f3fbd79ccd90b2eeda3b1cc30a	1613151889000000	1613756689000000	1676828689000000	1771436689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	285
\\xa9768d057b728bfcfc916f08d020b2f9befbf3718299b1a5017d6314bdcddbc38a904ecd6bafc9a252afd22fba766bf768ba0257fd1dbbf70ecdb844bd3afe01	\\x00800003e0cce947be01f8a95e4f81189be83bbf427de6dee9492711239d2c6a80ff7a2351b8097a1673362831d41eca2af39a42110d824d7aca4928d6a09f4fbcb30b7e853afb8354fe7e208bd8f328fb06ac1110b3981f09903896dd10765cb4d1bbe74cba28c6399b2607fb58f10326f52d0338276dea021d0d8c9fd16519c06b37c7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbe71f385d3937751d730754bc4f54a681b93e14e54e110776f5db6068da01609ca3f23e0ba4fa027cc3fdebd0d586f9fa34cb016e85f0e78d67cea4fa0ba8700	1630682389000000	1631287189000000	1694359189000000	1788967189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	286
\\xaebaaebfeaf11e95dc17b4b1efa6849fe66ec438e78e2dfd8f7943f46eea8e003257c8a525b060b983d8dbb2fb7e6cdd4e13d49e0be89a821b9794e70c6326c0	\\x00800003a4893096b50a5740f9376374691a7c7e28a5a13138941051e43529f9dfc41b5e3c96408e8c9c8b1e90c314be65c1df9810a67a8f915995184b55920cee210185936dbc3389ac77b07c5bc99f1d9e8ba25c1b8a09f8b0405ed3562c204f1c5b4982254b6079038332a1d8aa927b0b25d2ffb016db72718bab5d122a6d832bfc15010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4dcc9a191f42399e11217376925cfa2a42b1221fee1482b4ffa899c7ee4def6bc312a18d40cadb9d5e757d315eaea22f929bcd2c8e3e933f5bbbac5ce8154f0e	1627055389000000	1627660189000000	1690732189000000	1785340189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	287
\\xb05ac4d572a8b2d6da093ead51d1baa9ab809ebd7e82f21535df11798f061e71ae3ea9b135dc425c9093feab0e5dc1993316ff3f93d2f0daba26024f56029d98	\\x00800003d399adbbd2881c6c7b1e26857dac8fd9693282c82207f35771212baaeddea8ecfc559b473cb40d35ea25c5acbe83ff8113df4860ff6f718d7e60f87ee70b828c2d47f860a649041a2a01705ccddba5ec6f7f36f693d57e62bca146900f0423c7c91f40fcbbe34cad3185045c3a26fe99dad00938f326b4e847c9628820858591010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0617464c2f90b6f8961f51dd30b69a7a98ec052ea588470072e292e8af1fba475bbda1144b0aa71565b814e673368a569441123839e9553df134ad0240409e06	1641563389000000	1642168189000000	1705240189000000	1799848189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	288
\\xb046b8a3e848944eeb688882a5bd3eb8c32867904367e940eac485d70110f22bd964b614eea7cf6415c08f1b34b18111c5f397710e79e70b92b2294a84d8cd1a	\\x00800003c94deef73678976b542f2e7ce52b1a1012a4a7acbf78a52bdfe0616dddb6ecad042f7fd4c34085542ab37a910e1adf4379c7206e3dd81509385b65d3b7e068ace6d4913f979fbe6e87efc6d419cce15504e271444d40c923592a94aa712fe259f2b88cf47ce48e411285933aa1980d4ce796b9d9caa1167beba6e942bf12e94f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1404c84f95fece10f463481f05b543e97c07141270e6fbbba304f9eea9ca2cea77aec0de361ee943b3a047f963f216c048d98d1a1e7c38492299621f93dd2208	1614360889000000	1614965689000000	1678037689000000	1772645689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	289
\\xb35e17d4c9056cfb7bde776c043bc48612bae35261d7716151006e18ceb39c946f79fd2026d772ea6d1c267d2f900842808ac890500d18078ef976471abbc92b	\\x00800003dea4636ed283ae358c0da6fc28cf658e0465229a7cf5b0eb6af100ddec547482862e9c110d29c3ae6c218af220bc1be1ac2b94ca2c889196f42199d62671fa0cccf44dd7ea8e059a404a438ee3cfc524400ce0ae1370c5fd51d570c3ceff9958d410a2807cc876f2b8fa3a0d8440ebfd8e427ce7f16f49833fe05ed01a93e225010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xea1a009a27252199ef1b2cd1ec8428f60907d6a9cd6ec5a64d1353a8166abf9523cdacba96010d5096fb894b57c70ed7dee8b8e93d9f59f33955639ef432aa09	1617987889000000	1618592689000000	1681664689000000	1776272689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	290
\\xba4e6cff6a8b0187acabbe1f5764b77948a888f92f4cb0b9195d602686c4f8bb84ec10f51a2e9b6b0b7f7610b7b6ffec5f7b956cb392af44be4b65b906e75e82	\\x00800003b40ac33267d9e430a6f16495bdc28d35ded932b38364c0fcc2d73e2dac119a05d1dc2f9e8b14105e4fe466136ca4cd0e167a713e80124d39c9dc759a9fa0fa7c562c694e4cfa7535cf7a4ee314b82c24882a72973596bd41b655a97f6bd7c55d18a9f6febecb93fc3b149ff37661e90af13824b773c1beb71722aa601dedf7d9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5bd2f03d2c8e8f0caf102135a842c9ca213c5c47374e395c8c2929c9da10a9357650ab4f55ccfdd6826ac7cd91c0f1151d8f80c4bea4ed972061e9854fefaf0a	1627659889000000	1628264689000000	1691336689000000	1785944689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	291
\\xbd26eabf24e253fc581ac1ef068b4071b17a9ad1dc76d9df602aa0fa38ac0daed99b407ea04fa94126f823ff5e16f1929543ec635c1f03b0d43a5f129f9a8926	\\x00800003a1203c0d4577242635ac04ea101c461f2de53eb4d07ff092432b7c83668fa929402545dafd8eb49b00d85d5cf457ff36cc0f477254bb3e8d4ded596054930dbfbbc132ee0b34d832222e09a3551da76915570e4b457cae421aa0b829f32937db18b44a3f1a014e2cc664a62a273163b57e5d72502740505b308911d4003b65c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc035c288769228571b7172e7f9b12c57b0125913f85cb49b2563fd2640addfb8909651d35cca29c52d4828591e318680d63ab10cbe6806a9d9a3b150bf593904	1625846389000000	1626451189000000	1689523189000000	1784131189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	292
\\xbf7e3976c8ccd573a096991c9ff1f1f29c17c7f8fb63964c4ba8e9faeb51c044d902ec4d1ae672b16c07e86be313f6b4e5f4ae0047c142e3615369acdd574602	\\x00800003c4e08ec32a8bedc0b9d68cc14d4cc5534d58a45368545d63ef43f5388b8dfbf593113598184876ab3f01238bd1bcaedf84140b6fa42b52412f8bb92dbe8d4a97afbb13f4793ab0159a48872393bd15fa29dcde9d7494a2b6f2ea9b220026988afc6b5153f12a0525ceafcece72d1dae13bdb73d99c5e0797543cef6fd68354ad010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1f5d5e6a707e1ab623a629025dc2b433902594145ea9a2a69d294b4c6946f6717b571f3b98b985567933d83be3350004370c9d5cca8740ff8316376906b1790d	1641563389000000	1642168189000000	1705240189000000	1799848189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xc3a2b1cb0dd1f8e981c0081c3a61800ad4121af14ced3410f139e9b3dd7271fb7b1ce694fc69a381d058f81b80048c6e46d370c5752cfa3ac1688d3f4d4ca2af	\\x00800003a7d942cbd58e6ca0680189173c37711acf39d2178f715864b3195b9f76ce31ef103443832fb38d4d73f72775b8d5a2cac5d46507ddf4e2c516f2e225bb40b06a89e87978a996a22ec574d094dfbe6cf12b4d4a7662ca064f96bee173789c2504bc7e4265e09670c58ee38c1d6a4e0dd43c57b8a0db976bb16144efbd2d5eb8c9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe6f0ba5efce9316ba2b97582e1c4d96de90dfd5f0c3f7b09e760347743a30adfb3b2d5259f450dad4d7c8d3694f0698af4c1f1f90f7a0caab8dce15e0a2eac0c	1641563389000000	1642168189000000	1705240189000000	1799848189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	294
\\xc4b608f29dd7f7891883cc8a65306d2b231117dd7123f80332851edd641af46796fac2b539f9ee7239c607972acd8369ad8e3d64cf2ffc0a8c954792c5cda370	\\x008000039fb9640dd00dc7ed21941b87278a7945f60ea5c3410fd6fe4b7e159319a681a00693341889121123bfa93a3498c6267baf5641c5de94c727ac222f59d02877819d05831bba1f7aeb8a7042bc052bea8d75f96777705fc62a47dff86525e25d62c9b99a4014b6ef86a75d25b87fbf0a5d6e6d04c42c7370624619456aea3570cb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x616f2ea1f1ee95b2783948a6343fe8fa1c72fe1d1129b8e156f5471bc60f6723dc7b175e529c2a8a083d48d88c74c00fae64c67b03a096d397c830c0a9a32a04	1621614889000000	1622219689000000	1685291689000000	1779899689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xc9dedef325cd4ba7a9864e1ea1ec62e7e263885baee05a0660d319365946dd1487ed14e8e6c40304c65c772ae5e428b97d142eb411dc84a142920fe4e12752f9	\\x00800003ba6d4f2cb8a24c64323d646b77932e569a935d99f5c071eaa145469154f682a4784d3b326cfe6d9718447db1cb76f32702db30cb72b94694706aac339f10bce90c7bf91e814195cc7dc7bcb6df80dfb1fca5e820a49a7bc9aee1f035c141de8e53e826a6f577bfa892fb0b5fde2633a1dca6d2a81c4e1caa42d0ad281b5a606f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3a68687fc5d15379e5bc2743ff71a3478e9455be22a548e813d10ba28f943b56fef4948b1b46d4ad6260123757f7bfcd5ae35a6d5b29cb82c74281278bf8a602	1614360889000000	1614965689000000	1678037689000000	1772645689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	296
\\xcb6ebea6d4a05728be51b03f36496836b1fce3f641a477aa532a5a3d42c05e750196592812506bbf1ea86a8ee8b857233f336c472d7eb71321650c8464a54dc4	\\x008000039a3858ae868290a986e4cb108975848ee70ebc9fffc7f55142db6506e4ef5b9180dcbd5d4c32660e3015d885d3929636c79261233ed03cffd68afff11b1875e72971f4020b611b115e4f89fd5f4c284bc9d33d7f6528f9a91ceb69574c50713aefd9bf666f0c3bf9e5790f3e995c221505ef352dfddc9b3f4fc94d746b8dd25f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x950cf75ea1ea0532be885a08a4c7921f367cacbe6ff997a2b1a9c16864aa7f52ac553022dd6fd199078629d2679d526aea669ef2671843d1e980cb95afd54708	1613151889000000	1613756689000000	1676828689000000	1771436689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	297
\\xcd8a33088a4924ee8611c04511338709139c49cb274c119c089287393f3c2dbb921c3d8c1a6de0264e33dabc4f419932e6715263d9f47558d21ae022fdd8196a	\\x0080000398d0a120ffc78d7d76b6c35e4e86270dd3fc504a616b5508d5d35bae67d8cf810d9fedeca96548a79eaab9485429da56b995b9620f02418c0ef2354094c6ad3d9380553ced17c5cda272e5355dfc276351502f81759c6855d8ac1b7e7aab3465ba70fd5c0065f75f6713ada203d99b3886ea88b323a564def784f106196bffed010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x467f90e2ccaf3e59641a419b87433918b88a4be180bf6762637af95f5ea310ea3f3b4e339d364874c7e3fbac49cf3f7554b2b411b9874645294879527f66b903	1630077889000000	1630682689000000	1693754689000000	1788362689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	298
\\xd23a2330b55924df242a748eea39740a89463926c26f52bcd77f411d3e70dc666387929c8c9a9c455fe97ba130d65203781127d291f975fb626a742f31c15942	\\x00800003cf018b76a3479dcdb334ece1a2be99ac47ea5409fa15bd406c25f24222afe8605deb91f0a8217b2c7ff76f0a328c15c903cce20807701878ba7314dfdd5856edd68217b2ecd5f0b6584622c7c600aa63127557fa99b767f9481dc184c092900345b92442882655c6fb7163b501a4c57307092dd4ba8d3bbed4f196fae6126653010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2e03f2cfd7ebfe3b0b84cc2854ef3b321867e917b27155080567766bb89ea8772b4a7d3cfd2f1f51432de2c25894579cef5dba339d62b806dcfbb1bb50221204	1630077889000000	1630682689000000	1693754689000000	1788362689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	299
\\xd266ab5801e6b2cb3e2dc76f1ccfe354b3ae50868c205fd3e89659dde6d5411c81df7ac511f4895080ee0c632b5c8bdff8f85e1f84fb266dad92fe9782b21f1a	\\x00800003bd09bd08a08c83e675fa3d39241a8f6192b5f04a553e354595d9e750a7bfa1501dad352bff6856d5bdfb853e9f538484aaf178415847c69a358c592c58f10c73f39037b95fffa2850c47688f5925a4a017fda8ee85662333df69b6ded2d86aab4bda1d5cd4437b3cacca7ffb09c9c964dbcebfce80492fc6d2aae03d13c7af53010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x12af4cc40b2ed051105042fcb4302fabcc67b6df0068c1cb39b645ec20a275c9df92237dfd3cef2653db925fdd1c76999cd65f7726070f1ad29a17a9638f010c	1627659889000000	1628264689000000	1691336689000000	1785944689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	300
\\xd482c743fb1916dd2b3f7f28a96546eb44b85f000ada646dc99ea2ebefeba2b2ffb31a1957cf07d5c09cb8ada52b63285f66c8abe5ddb1fa10d6a7b94441f57f	\\x00800003ecf5bfe89f2fdb4d3fd7d948b0abe5b4bebd1b4f10e34fa004bf7faaae1e0d494bbd304faec24059e4c304409e912a5262c289e0ac7705c0b8a460b4c8aa8221e8375efbf42aa89ca3ff4ff41dd30853f214b67edf853a02b372c3c7a890381395b7b6198de2980f8e549ba15ce785460f4b7378461c70a4d65c9ba58ecd84db010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xba3917bb759d9c27c9e918d5b5d252cfbb6b509a7f339d0bb04faa887d9b7060ae89633b7f66d0439ed7e03ae5fc390e00fc25765afc265a310ba100d2d03f06	1610129389000000	1610734189000000	1673806189000000	1768414189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xd422b440bf3ee6684a5f4be10452d40e67a67cb0e7f21a5067dedbf1e90371f6e2f37ca1f5dc07b9eb3ce7089c6843442af1e7aaedf51d893eef4fe51a791ace	\\x00800003c0213b82e28b5abf410305bb5d06b9181b715dd64aa2b4a02e7b526151fe4583d25796e3b2a96c9b1ec179bb11d84d6fee3151dfeb5247aa5a5e5c7e06a0da178257dc355987dc5ec7c6ad1b9efc46ccf557b1303a02fc675a1c27dd624c6374aa2ab3dc0380fe0dcbb0c4ba68ae14ebf51a67b1bd2ceb8323f7ce5efdd17729010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x45cbb3339808fced5d6208254916a185637d4a0d58827016c094b080aa9ddc5201e923affc431a8f9247befca54b09645988c78dc63f4df18d7002f726a57f0b	1633100389000000	1633705189000000	1696777189000000	1791385189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	302
\\xd55eca867d70af25588b0b4969051f722731cf4b0ef4833cf7655609256cbc8c698d0ec57ef836004ca6d2475383217a3cbf32e129682d0158f51967c4fdc21e	\\x00800003af9893127ef9486f9c6fc42cddd027f2be53b6b858836ebf01c20b4e4c9b227fce2e01886645aa716f5d4c0c9bf5ee782cc631357a620adf877dbeee29b7256af7939eab5e5fe9e37f6fec412453a9952fda10d1f25d988be994ed654465c9d6bc9ca6c7251c66ec732ac3b29aa7dba8a7c0d693338cbdb9eba5357817ce1b51010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0dbfda77610e2ea36b784a3a0897e0f725a09aba86ef38c5dc0a08979a4ad02f101fd1a8d332608e3d54d9cee7709e67a783ba3124755a04c362bd241f3a1c06	1633100389000000	1633705189000000	1696777189000000	1791385189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	303
\\xd55282eed556abca24202e6de63857ae87af73a34f608822cc2ed03d6ae91ec95c1497919720fcbf3201cc18d3102d3fca6ea9f29e352cb3856bb6ac7aa261f0	\\x00800003ae6ad530ed3daa20594ff8a6a1cb8c192c700e76e36f493cb613049ba0e60330dabdd356a90e5348335332314682eb5be58bb4db876037636f27f87361f64901624aa1aad30439ee20aa9eab84e2a01899a3b89dbb8faf7eea0213b490502c2521b5466513df7b69669f96b785d75af0384f02096702791d101c554f4c3c080d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x408f1a357d484ff3b96a970ff2644921982de4ed9a380562cf9c92d61da699854b19debe4f7105ed49d428a8b85d00fec6942969a9139b6c1546bf72b0b0ec02	1636727389000000	1637332189000000	1700404189000000	1795012189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xd836c178a61155c1e88ac7a818e5b10c119d6d2e07932452451ad3ffec80fd3448edb9a65eb07e5be0ed7db329c499382034057a3ee1fe35ca68abfae351a12e	\\x00800003da753ba329e6b89df78bf224e67c5b1fbd02e7a9565d34f19ba368fd43f5b4bf8af24b77caaafc54fdb6e288f7b5435d422cfe4f7e4122fa98b0abf9ba356afbc50b841e478e42e4d125c5fe685af598660cfcc07688e45a54e03e40057ecdceee0f3330c46a18116fa39c51d33642133f816c405fc09e3f829efac0e15089bd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xba01ca7d7196b7d0d9a534b815c6f6e63b88c18f1eba65a3e7f9383ccfcec03fa8a562c42958d1db0e6fea8e776646df8f7933847942e5c7fef55b9dde344204	1615569889000000	1616174689000000	1679246689000000	1773854689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	305
\\xdb5e46525b46c75b67cab4f1754bd0fca2f144df251c63470f84675f96593688a94e06f8cb75e0f8a6408df42a0d1ec9d49c07b06694cd1d607ffc78c3914cd3	\\x00800003b9faa62316edf2085e327166b4529d06073979ac5b98320eea04bc332f6f2308f6d865a5ad195b05b1ad0a06233248f0306e8fa4cb08339072ba2a0f9fa47871b3df7f48d57d896fb8912c259ea16bc34bbb03e2ad44acf7f23cdfe707e9e13dc594f30f64c50f6eeefc498d27ef9565c5c6ca770c268cf78fd3b872e76254cd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9726ad4865e99a89953544c8cb468627784ad7d35fa92c6f1a98ced8bb3c6f4a55d98f7ab676db4ad540ce54e34a90cc91e73d7938c99b246f8f508d3573000b	1612547389000000	1613152189000000	1676224189000000	1770832189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	306
\\xe29625d568f565993cb81d70e4ea4f16c2aca17ba9b0499faa72db39899bfd5034109f30ccf0b3f5dec125072a0fd37c20bd4507183053b9d8823efa60f3ee40	\\x00800003bad9b4b7b5bf133483bc5dad552aaa24b03f629e194510c2df3307b3be63a566ee33852b7ee3b85d1737d63dccb6027cf97c42b64c4edb1d9da8d59e6e34e27ec490595ce1c700c61f55ba41054cde373eb22cc6691d1ad322728892a530b07c7b4db4d037072968b62bfbd14fd62051bff789b1992a1d32369709dd64ae2e25010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc2bc2082864f3c97bce325a184a44ad6116881d389426d28c07a1b57ded1918a0fe9f06e6194f305409f9656b6523fa6c7de2ce61519d5ced5dac63e4affab0b	1617383389000000	1617988189000000	1681060189000000	1775668189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xe28a6257fb91ad544e9219b32012bf4a2524c387e6c874311f55bffe21eaad3f8138823abee9dd75c15a8b87fc52299cecc864eb64ee568e9f03ec931490d1bd	\\x00800003dc0e92901e4a1b0ba80c8f516a9608214dea606bb91bcae55d6213f44d28ba4eb2d78adb0aee8231a41a05053edcd3eb40cb23809fc20f1ebae925703498f6e9a6dd352627d8e22a90775cef4b06b80db20f00d305fd02652a1d07f07674b8d2465275c0962a4ee559d4f3486ba96faa65a7a9786a24794230904e1338278e75010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe91b6978034199b1164caca9bae4150a5bc6b36c901a013da8b293cbd8dbe53ce84335f533f09162ccbd7e5f143df27000eb740f70882853a3945ffa87f3e907	1640958889000000	1641563689000000	1704635689000000	1799243689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	308
\\xe76efa88bab12b8438ac4a834a5c739967e5a6ebb9693242377ce799085a1ba225ec3d91e38e85c141b3eccf6d63b348801504fbeb554c36fe78f4cf86bd9b4a	\\x008000039c74a633586f747d3b8992b6cbb25967d4b3fbf13e2dab75236fb75ac387a059d4a8494f95434a08276fe923ef563a9963ab17f62d4a3921e8df6163fba7da1f69be0f81dd64101b308827e5b1876d3783eaf4d87bf98b342ec8643ac9951cf73cba4edfe3f70542965208aebd55e7f25f28f26027c93e6e0c4ba2ce9402886d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x07bfb51a4c17626453f6b4b5fcfc06bd578c1464a2eee8e645f12134496e971630c69f7a70480c45118b3de457413f42af6778fe2d533a4b08f166516514a90f	1639749889000000	1640354689000000	1703426689000000	1798034689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	309
\\xeabaa8b74ffbed0d55496fa202aa0025f3078c56e0a5d9a18a1e480063a5e27a63f0a4acb4b282c69d2d4752d85dda4029dfb1283d0b069814c1a3106ef3dc3c	\\x00800003bcb733d294da73365bf73c8399ea765d420288deb9cda0985540dca773acaa3957be232d55ea12a7b321f251f0143f7ca3478dd2b6856e4709443311bac21d8315ee3516b243283926d92d31d35fd910f8a12fbd8b7c65ef879514c8ddebd81a41336099e2f950935cfce1e8ff5211574a6afb7a8e6fb266a357148c53fda601010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x27df2a52a38c914fa6a7b286e23c14312aa1b6c4fc273ecb5a468a778ab6094180df0a4dcb64597c25fe4bf83b5b5218bbc7165a3c912cb607cef6ef73d64805	1632495889000000	1633100689000000	1696172689000000	1790780689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	310
\\xec627c3112db79ace3ec88e5980833a614b1161477c5f043337fd07cdcb2420139de7be9203e08ad439959bad687fb2c88733b7a794f65236acd5e8e2a6bee43	\\x00800003b20686eb292aab6aa3537bad58e32cf6c8b0586e8c231a97d2bc4032b1b3175a2996d851236f128593e008dbfdc23c62f438eab02996cddb45550e73802040dd5577c612feb314665a5e631107d56431a0733be0ec5fccb2072ca04b7af26532d4a7ebe05d5f3c474caaf510841ea1815ef03dc07eec1987d8040ac55c2ea9f3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf9823bb2e02f9b106a13b0cf141daec41a5190db1cafbdc973e27e8b39658afdb7c84a396da644e9e6e76b42c4511ddbed99804e0529144c9ec4e7685d0af604	1639145389000000	1639750189000000	1702822189000000	1797430189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	311
\\xef02e7abcfdb2ce04a90d03c53a4165c4e350eed134bfadf9c4417784f00e7f0311c62df23c0689f611e2f823513b8224d2425f6b5c795376dfa8434fe989580	\\x00800003dc6bbec237ffa4f4e166c315b2845138d1c7cee87060915c52ca6776cc6a883914d3a46aa62aaef695617389cc8fdbde87985953161503fd9e795d66793fa48b60e59e9c82b1cce80ddfd07e2f8d25742b2d130b9b5712447ff2c76e250898e025ad647d071e68bf13ccac664a5cd6f6e9c99aebd850ca8a09779f9a2586cde9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xca4ce40c8366ce67a145a3339b164f5294dbc724936d0d7cd4e55e69780cb64edac2bd83be86c550101de704cece85249bcce17c40ff79653f890e2c0797740f	1630682389000000	1631287189000000	1694359189000000	1788967189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	312
\\xfafa34f91a6066be8124768bdb3bba5215d977dc27141e369129924a43d6ced53865d70ce73cb3025607c09fd331d212215a159a8a863601ca27e27e09484718	\\x00800003c19580fab5043268fd24667a64cda39f74e862769c1c5aa94faca83c979941490749a5e0de24cccb0543c550f53e18defe0c0cb7cc63220f94b1210585255c2a2aaf68d4cfe516aeb7e814318af1f5e900ea588f1d8803b8499e451c2981c90b3095cb6b311b0b5e2570663b6afc0afea22a495773bef9d7a8c2286b26681bab010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd1c263d596322911081c636513c4aef49ee01c3b76c59ccba2812361c608c0ed2ae63545b1854885e931af11f16979cf9aec9475d0d0a5a73c9f9eacf19f8d0c	1629473389000000	1630078189000000	1693150189000000	1787758189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	313
\\xfa66c357fc8842e713389b15548c7f9de004ea0cf387816964d2b425b2f49847007f142303bdca609c058b9607d4d70ff078acb0677719825cdf0848d90be0f6	\\x00800003bceaf4573cad0c4f03a98460ab45ca4eaff7b946a98a97255c6ed962e0fe72879239949ea50ad6504ed5e65798e098a229af567a065196312b2d98201425ef981c50eb9869451016004e5cdc5e9e443bf5a7b25573cfb92226944eeded02f74193582a1c06483f6fd53e7e53e495721fcba0916bbb2db91a8e54b65cdc55345d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa8f214a82dc38ffd14ea69506312382ad68e199cc099895158ccbd7d82e25f156ae8e8a405fb68c49cbb41b693badc4af02182fb87f6d786c6a815a4bf50680f	1636727389000000	1637332189000000	1700404189000000	1795012189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	314
\\x0113387306261fc90a9466c610aa3fca60d7d0596216841206d08345d9343b0e96ca8f079548eae162bf46a09d6bbecdd4eee122640447476c6975bae375ee7c	\\x00800003a27a3797fb407a9f72ef4c3cd9f79fe3c9d74b4008f6773770464fabac72e23d2edef0689f05cb507b8904e8568ae7937e7d822f8a5bed6bcee5ee0c2935b0e7608e1a4371e093ef330e498b68ace242f3169e9d77814f90951838667c4ebfc480e5404a41ce19f8854a658631941e0b1e9c564ef31d425a3870de3feabdbdb1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0aba7494fd2fe9a2a26cdc9b8c0b6228c50d24638f746cdf8cb82aecbefd03d83f4fe2de49d8db503be0fd63eb495eb2bd72b5c1650e34ad6fa52ae705278603	1634913889000000	1635518689000000	1698590689000000	1793198689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	315
\\x04cf214a152647ccdb47d4b68f059ae08374d28bc8deff93ff9157ce40cecb8b81babd8b4a4cb33a35ea2a17ec32a4de15f8325975e6ea008edb3af5e1eaf4ff	\\x00800003c37b11a3d2f8b7f40a70ad9e9a47fb6ef15cb2efba9bd23afc659450a59795b00fb7100ab11f2c1f7bcac34700f44648827f4ac318892d4fef0147baf21080c538ed200dce1089ce5e8daa8a19f65abca2ad94095c7e2b0a41abd8e820da9e0b6f63d80f63b76bbac7e64e7e4a8b771574c217fa5a4d395f9d09b495c6c9f0bf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x092f9d37343801d159f664e20614214a9b4e25578d55fe94e9bf1f042be17aa2ab0957a8bcafe188b754cb38eab8d06787d406d3b952a100f2a1f79d7f29740e	1629473389000000	1630078189000000	1693150189000000	1787758189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	316
\\x0bd39d7d681fec10a6f6065aee810e276a2674f2821a360157be7bc7215f3e2fe0922937637e702e3845ccfe8cfc2998aa760a9f83378481b2a05d00891469f3	\\x00800003aaef3e35f2df0b157ba0e5735faa7114d0b7e4b240c13b26738ae2da5e131908f826a85c1f2eb06b3b35daf144bc0ebe6e783a6fbe7f8ad998974e79e0ac0962219fd93b41c2a84de95ed7507015ef40819e85f4faa6a7c150a73acaeaef7b49a491e6b614c468573db6e8bffd9114329aebd7d6aaad8fb01821c54dca5d6f95010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6dfe722583453765011248cbc11e3f0ce358d034f3ff6596fc1d660402c49842d15b4b946f037222d0d7d27bd2fea9a30c3c3d16065d1153f2cc86352e4b5a0c	1637331889000000	1637936689000000	1701008689000000	1795616689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	317
\\x116bee30e6650a8e60eb54025b68d7090d19972fbf1524ea21561b1494ac8d2839bd8fa4e18cb41b8ae1707efa9176ea47c5286fe99612517aaec0655c3728a6	\\x00800003fba4a1e03690ed9cc044e5ae214920c8170b0f7ba1cc4304181733fb7cf43ee35c6de0efa1b5cc6a48d6029a42c7ef5da49a84ca3c83290c0912c665ba45a13686f3775297cdc4993af6a7f7b922b6091280331f31cfba7670d90fd97a8ab0460b38e19ceded99cec0760e0bf31fb2806cf044a1d45adc8dd4969d736a4646c7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb1100b78ca5be73c1a88ad201ea252fb7bf5cb7581795ee596f055958219d71427062563b51492f79537b2ba407f3060a1df03f9719b148c8475c25347a5a107	1631891389000000	1632496189000000	1695568189000000	1790176189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	318
\\x127f7df7bbb9eed9dbe715d7f1a049c12bb6e2a6e8a2e7455148caee36449bb4c3fe6b6ef4966562405122ac8560cee7b95dbbe515384d232d905ae8b72039a8	\\x00800003e057383fdcaa1ac7ff82c91ae607f66db79aa25abd191d6bad0f5546f2686dd45cdbba132cbcda50d9f512536b0948b34268a7d2797cb27d22b0e1ce5d3ea28e42f2097ec5697a8e690a2fe38dc3a2570a27393dd123860aeda519790e3f629b6ae362298941160f7ea5d3bbe5dea7620f0a04a0c16fc90e048c9248a1686cc5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x63142db8aa2b74058c0f8bbe3e631c75c1cf65877db81eddfb9c76cb9736cb4878882c21fc768a51604046ce8387fabdfa75f4c82698da35f06c309e7400130f	1617987889000000	1618592689000000	1681664689000000	1776272689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	319
\\x12734337f568afa1b82ef2cf678196dfb81daf16b6abf83b677a15b77172811c90fb7eb1d46df94c6af0c505125b1bcc47706a4c4573a869f46b1c9ce2e00005	\\x00800003cbf3afa965047130ff4f068b2a5c3cb10d57f248b499dcc818bcb95df966548b995a7d9bf2411e61267eaf085ce0591be2afa0e973e41325d29ff7720b00bfdc14be2220615ff23fc5aaba6f344ba868bd7b67ea3002adfea67c7808f11d8b7f13a697c761759562655df3e3e4dbd422946e20e424856ab087ff45f61b548399010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2064e4d4f3170197140dff12d7c4f69dc554048b613d7de1194e4a03111d8931fdcdddab35614c40bc3a594c312292c1370aec766beed944793ba4dc98397304	1631286889000000	1631891689000000	1694963689000000	1789571689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	320
\\x1427bc0665e6ca1c842a3bc58765de66b104be852a77a484524da6ffdb070f4ef0cfb884b626a74398b394e9e227cca17d2abecb9463e1680723cf789a1c0235	\\x00800003af0641a4eb351d9c935b89c38ae42c8402f2e7f4b203f8f4d10639bae9eb712d6ea98d06b30c28cac0a237e1448a20d8b99fc3b67ed170548affeeb67d2257ec8f437b42b5be2a5a94e7cedf4a70ce3ea5f7879aaaf447ed1a0373fc70b317fdc5ea884fc0f318684d6dbb6d3cb137cbfac99116c913d13cba315f30dfc5322d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb3b1e8eaec9f354984fe658280c43e36ac06974908518949775b7279addde4e4913193374b2e79cf5632ecbd6410f38bf37778a8ef1ff87f5d0743e68271d307	1624032889000000	1624637689000000	1687709689000000	1782317689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	321
\\x1433323c56a54ed1b5e6ac382cca596ce017e5693b7e28ec5f95d8551ecb7b2d296bb4bcbce2bedda4c0cd34c616e04711018ae3baebd6e4d9a9daf235639b19	\\x00800003c87460d5a8c24301531349a7ebc09c32f83444b2b5de0d19142b4d1af512a8e2f0045f624c959b9f445080e58a9ec8c759d917b9898003baaff25eaea4586f68248c1880b3839532b646dde142762d02b56a7fb69e00b19efd6029861a80c8823fa46250578559ec271d37d317795df57e0d28f1a6c8e2053604fe6be6b3580f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x80fd7889ade962818a7947dceec667b8d544e8622383aab5ba3b74fd383b012353a48269cbc21152e84504985dcccc468ec6f7486219fbe5c78ffddf4e680800	1631891389000000	1632496189000000	1695568189000000	1790176189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	322
\\x160bd325c55838e990d03084ac477a385adf7c3cf6d6c68a154281ef845b75fbad675ed26d655d17374af31b5c03f0dc17d79e853d37f32037d01f6dd6720187	\\x00800003a6e18188b60fc29565c3c9c72e2bce3c4d94593dff13c532962f6136fed348eaa9f2355a33712b31af2d19ef10537774cf5a53a9429759ec8c86ab4615912484467c42b55bb28b2df5058eb6ac5d751e15ec453f0d0cb1b0dbf737de23d12b2bac2fc1e306b6cb71eb9aa4f3beeef44f545696b677d9f7c5fd0a22ba6f251b01010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xbeb4147b71252331512c47b25649c0ec1686a738ca38576f15a7427f8d2ffc0de28bbf50e7274aaf3f365815cb387bbb2c8ddbe2d0f1a4f195c615a898062c06	1625846389000000	1626451189000000	1689523189000000	1784131189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	323
\\x1f5b5d3c0396489b308c4ec4f00bb4a23e7ec662aa933aadc0cb40491b46c6281b29650a978712ec7f62b7d348c47cfdb4fc056569790a25f649f727bf1455e6	\\x00800003d8812b0d9a5e48db87718c66a8498cbd0a44dcbebf3876de85b94b2be5a274bae330134d0d0bb69cce00a024e421d0c0deff416fd72fc9f63bf0e824a8dc5f77afa8c0e150dbeb76c12d1e1c8ca9ad868b1627db2c89a2274c72b7f24138828b154a8f5e00fea726b023ff3c735fe52df414ec3bb2c5a3e37b34da1f969731e5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa538c255428b6f4dabb0b3ede7e8045cae6524d72f2223386d00f7b49161dd1d57684c5363f0898c8167e488a768e3c291f834693f5206dbecbd54c37b66fc0d	1624032889000000	1624637689000000	1687709689000000	1782317689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	324
\\x1fe7c2881283f566e07770db4c97049063766182db9327852e13e0a8b85eb6ff84f4ea67ca449f0c4d710547d64dd89ed77604ef259608ed197635b7b40a7914	\\x00800003bb3db3498577987527239ec696f41d28eb6b4c6afda716bffde3ac990be9776128a5c92591bcaffc6313377893c13726aba6f487763d9f8e54eb1546341eee82bc9ad519857a2f2ba43c5bd88a6b7c506beedb878e023b6bcd4a6ae1a1342dfb82c037bd52d86f8ee7d1415bec865aea4f9eaed7402ce6e5ddacca2c9da41265010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x10953a804649b5a5e32037adb30d0fcd449cce4bcf32ca8327088d8b3af98b44b9915e9617cd5f78a7c6a6cda39f50617464a2637f6794700ec52c2139ae9e08	1634309389000000	1634914189000000	1697986189000000	1792594189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	325
\\x252b526ae997365c4d8dd7491fef3983b852d66d5f0e4954e036c0cf5dbd39757c31b281c5479a05382c17f254caacef4e9b841bb1eb28312983cfe08cd965db	\\x00800003d787c0e412d150b8c9143b9e059e2ff284491cca15f791a53c7f6b83e788a7918894a42a31d91ccda7060e8f3cb6c36fd00f4b895a99a7ba0ca2f5736d1556e203a24dbe5e322d1de2a2d1360c03db23a9feea42f8fe01dda87dccdcdcbefcd322f6bf6c886bda31effdd2df6f1d235c77d9f9caac1c6dedba9dc6d36216f7bd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2e99da5af43b49ac362f86531e7be32942bbb14dfb92bf4716068a3aa3457a8b00fd5e8be0708f28d20c5112abe54a795093b86348b722cd47e262e2a9acf905	1639749889000000	1640354689000000	1703426689000000	1798034689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	326
\\x296baaa9256465159d807bdff8d20df11dad961e0caafb253eba9348b139d3e76aa4fd9415924a32acd4c18aaaea05c3977295c244ce5804736ac2626656acee	\\x00800003c2915b17623a4abc9ec2c61a7b6af2e516458df897845690b7572cd556fc7bf743853adb323297ce250cf2eadddc3d4580d15f790482fc082dbab2109e8eef11855f88cb3da8ede5623af03088037af5cf7e857040b58e743e7ee660f99be1cea084976c080dc2f1be6f6679a91f8768f9023b831fa16d98982fd31a01f58e4f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x49ea80036ddea8471ac44ce1f3e9b06c2bf61fc78fd0876926353ee10fecca903989fb26eac7f13c84393a82b817909c4a22f66661d12a7d1d6ed84be65c5208	1620405889000000	1621010689000000	1684082689000000	1778690689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	327
\\x2b4735456111434888cd7b48f95d80b976eea6c6cb2c03b5fafead803e196b2ebfbb4f92d565694bd58c80237e445294effdfda1dc45bcdf2731196971f00d42	\\x00800003b3a1cfa24c32fb6aab086a4e0d7ba2a55ad94ebc5588fd49c30a6f262fe46704f1786cef50d395109e12a12b10b6545aec04a5584a7afcca5457208414e4ffed4d52dab14ddb166c7ae0bb1e321c3557121e0084e812d0826b29ef7bb0ec693eb2da81d306e90139fc393f07f6e62713a407537a8bd07eb35f94050a9f89872b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x661684d4ee0094f95cde1cc2e942efc98d7093d947819e9bbf64952a1f0f6daa55b9664460e8cd786d2c630045713c88011642114dc8d269a629f8c89647a901	1616778889000000	1617383689000000	1680455689000000	1775063689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	328
\\x2c3f90f2ff98302e024138fad1dae1c39ab448861ca44e90bf8f3c513f8eb07714799062c3276a4c1c33648fcfe5630dc0a041625eaa740c8becaac8d411dbfe	\\x00800003aba054b57d7ac31bd866e1df2d7bdde6e9d6cd7effc8c4a67fe6d21b3db9466e47e4dd0f8d9abe2e8b5f9e3b0ed5782df946ff7d700a4d4b9c06fc175576b4cbec96e6abff28e1dea378a778b2cdaf8a671bc9b20220231808a0c290ee51ad0af7c4d0453881aaf017fa4dda838180672fa553366ab1d23266af536421673a8f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x8db4558f412b5ba114f96a56d5db60dda9eb54235754afd276760213905f2c15a6be736ecdecbd7efef04cbc7e91ee4c54099f88dd28d35638768563ee1b2d09	1632495889000000	1633100689000000	1696172689000000	1790780689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	329
\\x2dfb15ae1984fb57b1d67d0041219f6c8e73e57fccbb4b68a5bc737c2da05163bb34619e5159be1cc2e4cb318a4a364f60c4697244d2a7899c39b8988ef2e59d	\\x00800003d3b9a8774d5e10801a94e98d7580a13eb9d3580e4ab006f8294c4560738abc687e790bb10ca01e1da9789e34a0a32717b3563466fc52e899e65943be13423476b613bc056cb7ac12e9140a7a53c0571d07476b1bc6ee59d0a39abca0a75377b58b92208372475c376f5bc95a5c5124a299e50f3f13ead79ea6a20fb77d70d7a5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb4896fd5af313bfdc309ad0b2d452a784a269a6ffd9294f7e71c8dde98b32cc6ea3642c0f0443f2952b0c7c424f277f42c52abfdc1eb5cff8f3db9f529099b0c	1623428389000000	1624033189000000	1687105189000000	1781713189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x2f8b2f33cb175e1c6348483c77b7a193b216df61cbb2b7a1c9997554ba22455b33eb115f631868f289124c2c6dc9c6a665ecd2c33917850c0cd5a56d608e1c0b	\\x00800003971750a5061b38228d51d9ac257da949fc24a83d0b3900c2a25548c6dc29147efc6a3f8fdfc3f7519a9ebf62d9a24aa6b447e0e45bbee928ada250c785a68c7a83fe48fa1e38b17c2d64740fb8e0715bb687ad8e3912b14ed635496e27492442f0b6fef9fddeae8e88cf13d8ab59395c9350ee8f07d6300696fd9e00a0bbd5cd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5700c2dc37f3a4868ca983808abeab2fa9f92dcac30d04eb02904927e1ee5827e9b564d5f963a92db0c382714dedde13c96a76cc82779d733244f8265348740e	1628868889000000	1629473689000000	1692545689000000	1787153689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	331
\\x34fbd95f0ae13012d30bee942bc6295da00b57ca14ed39bb6475e0c86f6a291940cc6324a05e7fe4d7acddf8a02643ecd4d00cc4e6de809b24ba6b50e2c157e3	\\x00800003cffb8f206b5b961af4e97892ae6e44c486643140da3eb2f5a295ce1c7a57a0c4f0e0bfee625f4812536d09ab6a4c53604ea5afca5ed1f9cf86f43ea28d20b2f28324f56c2475374db7e26e40ebbda6156cb2d10cc50d756c6ff1c694094c44c8a18479239946aecaeb7739235040e11d2c028f174abc78885149c122edfb8b5f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcc769374ff56e601c7fa839801ee2c977ba17fd707528cc49ac7e4e62583960170ec2ba3b04a733875057fdbe22671ab6bb52787f556b1e91386d3dcca1fc308	1639145389000000	1639750189000000	1702822189000000	1797430189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	332
\\x3d0b98100df7b8841f3a76db33777b23ad0f7dbe8070683bbd66609e5e65f8d3881e801b618f413ddf1cd81b5a9aa54a5ae35ac247db0e315135bb0a88def134	\\x00800003dcf9839c70f5c06be0b0094e8c4a91818e47e2d8dd182e228e4560ffc847e535a4858be698e12d5dddb6d9eb5357464289defbcbb05012f8bee2cb0b976a8705dc9e1323bd92a86381b555d88ce2c9cb655bae00768b2616d7142c56c89735dffd2791e9f730d47aef7d0b495a2cca5f989d77b35d967899af8032b0db304bb3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x37ea4373d0ade35bf1a89df9330fd448ab73203be2150433772f65d717202cb15aa5824b5497eca1528abe7a61e97297b3612ba2b770c627dbd4f6132f560f05	1618592389000000	1619197189000000	1682269189000000	1776877189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	333
\\x3fa7a1e9e851b882ac657ce8d2df0613f4e890155bd910cc3482d0e61381b693f1470dbbcb422e57cbfb8b0beab41f2e907fc2df6251945ab8346eea0d698890	\\x00800003e9db75bd8876d6551b15444b490f44773222b24c3509565dcb0bc51b91aec679d7c03aec3004e8d0166d898b945f385736efdc288811025896f022dcf5d3ce033d3bfb745674350141128488d2f4357bc36a93fd8bc15bf2ba35e47678deb12e6f9f9d3c8f3dd5f3f3b8bdb441ae37e275d6d8e9ef453fda4635a5455601e4b5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6191bf3e504d52a76179f18b7d4c1ca5d458db8083b680c9fcd618b10bebded1ae30af69e190a3f6f86c976bb1c540538ed1bc059c8e725923f2454c7e25770c	1627055389000000	1627660189000000	1690732189000000	1785340189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x41dfde21fbdb5c954f8326d8c82b7a286c50b3c5a8b19e6f205e11ca0ec5c94cb0c57bbb2537b7ec1c694ee1fefab618ef0550b091e46a2f97eee7bc13c9715d	\\x00800003bbe40055a5ec71bf75b7c594ad2a38726c6651dce7daee27bbb460205cd785bcd1f10efb3c94194cd24ab4e95843b0c0ddb2cc0c7aa8414110024c917a31ae77c0f3dd7a02625b4904abfa11f35c0bace167825e40c3eeeeb810eb04a693db945ea9c48dad3f550b49a25edcf21ae223f322868a8871e8009c90668cd733c155010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x69d468fa07409076a666928e1abb1a579a7c04f1d69483814fee4ebca8c3c5efc43e41a0562cf1c5ccfed322fe9da1cd77263419690ace59d4a109216e8baa01	1611338389000000	1611943189000000	1675015189000000	1769623189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	335
\\x43eb4999613ff8230c1fd0b72e879a61f86fca2ce01c5332f5dc3b9d3dce547530627a7a7db98f263093b2979ca4874c069940455dd85b44c424d8f85ce0e605	\\x00800003e029d0ef12f99f2f5ebf1997b29b61af87db36e223346067add144257acac27f32bc530e79769b6857326ad05de7c9067a9f115e4f84e8883c73d49e54187e404fd33b11a05ed866d92246a8929eacab29949d78ef6477a1dceaeb243677e7b636b711372e9eee9f64e91a1dccc6dab1441d9a5add41c92621401baab1a8c751010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6c760f8e1f93d3d61b87ca3a122ecd277661d5ab920973b7f99b1fb4431755c80e56a81039b724eeb0a9a779fee28af1975090676feca22b68055a8218651a09	1617987889000000	1618592689000000	1681664689000000	1776272689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	336
\\x44b75a4c408d88c3bbb58e95e708b10dde1733bdfe32d72ce3a36aac40179c7c3da4ec9c51c319a2d5ed5a26f3d680cfc8127da3a080da65d6ce5cd8ad7968b0	\\x008000039fc512693e8ca7ed5fbd36f4cf068f7cb73bd3db60146ba299e266fb94832eb2ca67c8a48d417bfafecf714f19b1d8b33af3dfb140be31ba4443f6c0e6938717bc499db1a3bac859a1ce1e6e4061f007f3666d6f2fcd47c21f4f019ede07db8f5278d9076f95a7ce7a4f62deb5e61806d46d11ec95342b1842752e2372303bf5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0de68cddf05f759f4983d0bd28bde8e42860f5423f38090e77a31fba55cc20dc8a9ba91768508e39151458a3a404e937c8b4057a64b334f8f86059e81939340b	1641563389000000	1642168189000000	1705240189000000	1799848189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	337
\\x49f36c3fcabfe5bcfd3f9cfd17c3c076c6ad4659aef1ed691104a502b459a1e9cdee7470f1a31b9a5d17d472dae70361d85cb3beb3e2ed96569b12b3a5f9cc23	\\x00800003c9a8e854f94e2dde71e94ed868b13d4d8c772017332cc0e6e164b2984e04b2c7706f3aa857ef4b673241c419878fa66c37a88d239d01b27e442d36b43fc666c74d6f06cf1adcf4a9544f01b9444077bacbc2901d742331705de7f3d79994890c28d626a423fb30696c0401e74875ef845b470609483f04dca9fad621003d938b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x611180d3bd78cd61e8ed9778916967765ac47dab97cb364e5b6b75c53c97a1c5dd713bb0682396f4f65be306bd17d66f74c8a39d9dad121cce3a22f9506a6707	1629473389000000	1630078189000000	1693150189000000	1787758189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	338
\\x4f8f4a996f6f03153f4b4d29930c232378bfd9d1dde9bc66d8fb50745851012d192158f765264447975d6c907cb511739663c05b239ea8b1f1744aa398eb0ec5	\\x00800003c84f24fcc1b581c3af99b363a472b437734cab5a5454ff5e5e805b079c8140e94f6bb344d75d42ffe2c927a65a2b3059a87b2f0f6e2176ce0c7f53750db3a33a617ed88c724d7885fcf80339a44834c905da02cb328e7b3cd9e37abee4768d531fbded60738d163b9647ae1d04617ef69ee54244cbb90c648d4cbb515abc6acb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x20c23263d89ff3ce22eb000236f79eaddabdf022f2ed30e7ef9285880574fbdc83fd1402ae9d45447dfef1a929dff1fbb24adf91e27ec18df8399f2ae7d53600	1620405889000000	1621010689000000	1684082689000000	1778690689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	339
\\x523fb56069b0024da55ddb064286052d8bc2b31f82d66a60e09e1851fff77aadb128bdf44cf8001bc8aff3432454d589b74bfba22428a3b06c262e3709c5f54a	\\x00800003a9fa63ecac790be554e3efb49590bde69f202cf30380e348d2fcfe1683e1b1910e0fbdbc0568e087b4f5b14d8235917cd41d17389c7610635cba43e8490deba7ad1685ee2acf091140614e62463ea2f8b3368c22fa376ab09e5b1401f67c33b8f65873b79903ee9d658219bd7708130dadc6131831b0aa353b761337ff0588a7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x36aa189a6c69340d9f9dd59f2a5509ff505096c976bccf12cdd828b16ac1ed61331243346e2dadc03a56c0e4dce7b774ab48d04c5dfa09e71fd3e51327673c0b	1611942889000000	1612547689000000	1675619689000000	1770227689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	340
\\x547b19121f9c71f5f4e7dfa80901bb9619451b2af57a6a72ed36bc06509ffdc4c3a1aab3307f27957acc48ad3b927650ba25ae07e399959e5bc43cfe1db4e6ea	\\x00800003da3f939c7e4f3ce0b99db80eafc424158538012efcdf4f408c99b603b615fa88194da5da39aa1706e417aba5433ea8ac142a59a81450dbf1b6e786b6b3e8332cbd69042d93f4d6bc796dd89ad118cab15687f02d7ed1e11bce8610f5cf0216cc8fb5266ea4c4cda43df38158a1f28a93640b9d71badd1a9b2cf7b1d370a537df010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x483154b4f9a7a30a4c591728e81e120ec76635c69d5f52828ce70b33a1263a2dbec65413e31d6153762309615d3551db486fa470329b4e6a5a9da4f0c8a26a0a	1637936389000000	1638541189000000	1701613189000000	1796221189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	341
\\x563f5ee9db0425f6b6bf3f6a9f9867fd39a24bb2a76f51728fa4584c3dee402777cd959b8155539790418a44f25ce6daa39a549f50a5e1b4563318ecb29be3ee	\\x008000039faa922807604451d89e9f1ca7b83576efdd09b5b1163986c47fe5f11e7f904703f7b283528122166933e73fe8be5d683b059829687105410ae998d7be6fb0899a50cc444c5a10cdc12157eea2b51ea4ce45cd9d7ef304103a97b88fbacc8cd8d61f8e4e5e6e55cacfdb94c6011fe75f9fd081b1e0f210a45c5eb9fa22a990df010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2ed3128d2090dc36af7f4dd3c17eb49a7fe51830d8380bb6fa81669a4b2a6a011ee7928f410b29abf45683c460a719ed01d6c49e1e648da02a8b641264324d04	1615569889000000	1616174689000000	1679246689000000	1773854689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	342
\\x5b8f4c9b39ef42146b06b278f36dbd88b69099205a7f8482384210f41845086ab1fb928006b64061564d9297c23230c9a75ea7d0a20cbbae120030128f94b782	\\x00800003cb802e20f4b1cd1aaded4c81ef4a6dc2f0c079d2ae5adaaad52ae116a6386ff1dcb09b6811ac5fb13f6eeeb71a5674fe38f0790074434ff3c20eb828df392dea76d19e91f6c46c8654169cd390ab923f29e52fc92102d5d0eae91cc223b9d711412b56e68d55d8300678c84bb698e6276b919771b9ac688f7e50cd3285b8f535010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x66bdb2b5de5dfe8966aff927b17dd25f65dc2149c9834dab21b9604f0c10529fc10e6152a9139ef370710c490af5674fd1dc6c46aadd672e0d72be901201f400	1610129389000000	1610734189000000	1673806189000000	1768414189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	343
\\x627f73f916011d245634d2dda30ee5f947a1eaeb24867d1dd8c1ac4616abb780ed16cc8b4ddb91290444c0cdc787544de50b12a5a4ad1c6437ff1015587c96a9	\\x00800003c1e8e2b11f31f56f5e962bf13e8db1d0638dc0abc9fc05e3e18e4295de0626839f701e9d65f2023f77b58291814bed783499eb23ab1e595a9db3a6c689d828751f7be6d832658a3908d138edf2aa52de83c2deb9c388c7083e0f6657af649c9f2b9218f57a56be4249140658fc09376d33b9c51242a881a597537645249737e5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xefff91c1c5b4fd4319641eb30b007f7662cb3faf1deaa249c8fe6380f0946875d7a37168066ff42fbc0044aec807a9ae388938ce2e52c4082a0de4d3d51c3d09	1633100389000000	1633705189000000	1696777189000000	1791385189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	344
\\x629f02b3e9634d4d42d474c55b0e9235efa128b7138dc18b8ad0601233c76e6b971e670e339ec2d2377a4cbe175f370195b10c86eb48b5fffb2708d23e4b0924	\\x00800003ca02f64982493afd0f1e0bcdba04e7b452ea0709287760672ec614ca684c2d71d863932522a0a7672582da7edc172ff96552bd7d74b3b63b846018b697325dfe5519035dd90784cf2a2d137861e0a9887204edf11c7fca4f9378376edb632726c173fe452b76049bbe4739ef6068f4780570077f12885b62a2bc15ad39c420e3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xef665190751bbe71f0d164d623bcf94cd5ddad8c44446f5ddd12909d0a47c54778ce45d0982f202019e1f60dbaa673b497a758b23aeefcab8ae9d4764792be07	1630077889000000	1630682689000000	1693754689000000	1788362689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	345
\\x64df476c9074792d7607422113e50aae54971e337809b2d3cb65b45e4c662eff839818f32b68073085a7d5cdfa7215c5cb4becd618f58d3e8f9a59330f7cee15	\\x00800003cc9d3c8d760779d5ba234a0ec919120a4f57447be46989fcff8026c78034b1d45012403c5b551ea2272bc2bd7bd0723ccbce681214bd03fc88e68cc0a1193057a73d897cbddaf1d8e470dada0130ef45667c9ce2d9dd6206288363bda8b8f75f8f3d7aa3d38e6449c38a5cf173c86372bf4ef2c5fd835500b7639a9b3ab12a21010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7d19cb240a56b0f723ad3de164db639abe05a519df4391b5e43535aad923f3299f83da0f981fc268cb85d553d869bcb81f2dac9bb19cd055a0ad99e7c6fa2b02	1617987889000000	1618592689000000	1681664689000000	1776272689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	346
\\x66bf2fc30deb6dcc835be5f464f1000ea3781c5a614f16cb6f9dc6a75b7b8bc23238ba69029d63005dbc1df99504e7e3530cf3ee8927a33a39e072d0d198120f	\\x00800003c90614d7dc3a0811c8cbbaeb9bd58672eed3585a090833315c5b475796bf335d79e3e2fdd0129a608f390be37bbf58e0668512cd323f7201c5c5abe2db51f7cde58c98aac70bd3de0cf50858ae97969ff7148bbbb78d2fa9d8f9651014312e36e5f1ad7c2573cf0b3a9e8ee6d7bbabfa39d5c30798592997399c917a29f0317f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe174e1fac25cf82460b0dfe23d89c8ebd79468bdc46c61cf78339fb0f839898298fb0aa8d238feb5dcea9fc781ccdac7a0577ab512854e51d587d1e0c5615f09	1637331889000000	1637936689000000	1701008689000000	1795616689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	347
\\x676372c202d3e56b17b50b0a4c5c288d720f22135ed22c35a5c34a8c93df806bdd7c0cfdf92cb544a1d92daf7c3e3bf84b474915395ad2b2d9f8ce576d33e1d3	\\x00800003b8a75dd420aa82b32756c5f361ab90577bb301ddc1665931b2d6aee5435afb29ec029bd1f07656e25061af7a83228102c907e14b23a90bb74521702441da7910e8078876997d33a702f2bcad8e30ddfc2a91b8dd57cb6fff0f1a2d42ecc5291d86a0ce4ccaabfabc63a1b7957a4a88695a9bfe31a5c83dcfdfe330ca77d180e1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x920b49136bccc7231d3ba360f3ee72f7f6c28d0b7003e4e715229b15abc73a28a31c4d75807290d62f875e45cbf522dd216c4a5c025a0f5765658e3826bf120e	1613756389000000	1614361189000000	1677433189000000	1772041189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	348
\\x6ac3496fe93969d119a54abc5a0b6c27881ab558ec41d35d24cc68c77470d9f6af17ac202c0f397b77b1b881290e36e721adfb9e576c605bb015297949e31c98	\\x00800003c5fb0e78244901a806cd7dd8721a4f3927c717d6e0e4418fa338b198923df4e9cd1ecb13636d456b31f5ddb680f88adb440e46593cddf52c03e91514365f4a186fba97b109e1fba5a8a5ea8adec3f9d8fcd70084ff280f1436f49d42121b82cdf0eaad233ecc3e19763e1490f2a27f4abf8732e6a9a0995a7299376d6dbcc6c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x45788455a06c87d4c83ea0887c7a3cc13e2ac5d1f7efb263574e16e8c842bb11167294295875ddc2427dcd5c1bd6dd93a1d5993e811bf1a0d6fc61abb56c6802	1631286889000000	1631891689000000	1694963689000000	1789571689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	349
\\x6d67f13d72fadc981fb7e023085cbf51850d858e20a69bcd33c9e591350d563e1a961353205ef6a0ec4d1c769ffb42f558645f4a21d03cfcffb916260377115a	\\x00800003d2fdd5041040216d4e157f55548a3d719cb9de807f441b4a8aa4bb30c82c18886e6f84f009b7d4c8ec6852b77cd69cfccf63d0f65698fa188fd761dab5f715f87abc849370ecff1f272baa4b43b90db96813e99f2892620541e94483325f442f2b995b5af6df949c9bf95df25a1036e65931d0e92c5064ad64d01e7afa04ef21010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf8b2b4a69951336e3d8eab28823839ebc7b609b716a47ef9392005a7c62c3fd6fd5572ae6d3f82922cf900049c21d04e8f74054142fef335e442dd7399f1da0f	1627659889000000	1628264689000000	1691336689000000	1785944689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	350
\\x71c7111c5d546cc5b3d1001b977c066e5f10b0b07a5aed9452f0b15a3cdb3c7ba520a4b98e7b77d7c1e2fd4b3a1a8e566fb7fc58a99e0e28960a4250644c4ee9	\\x00800003c21a63118ae8311cdb0b65870f8077b915aa24f18978cd7a76955c4b255c62974d945a18960677a4f79e1ec9c9c7dc0eb587e0095fd7135954e22a4e61f8b5d984fc43fe6c178732c42b772c57199f7a178883ad48a97cc05ccf44311680d58e28c86eb24629cf38323f6bad409220b8e8e9623e10c6172fb44f1306cc92cdbb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x510eddd8be22c2e0b5e7cd64d1c62f4708a189e6aa3ee34fdc418aa1db4bed5274d64a17b3988eb2f9463faf87bf17f72d2558005fc6b852ed8d135c4a46bd0e	1637936389000000	1638541189000000	1701613189000000	1796221189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	351
\\x73534b995c576b7bfe980a7f6593020cfd0b66eb87d74a05e91782f4dd2c42658ef80739e4f3ffdd54f2520ee42de80ab33100f471a3cba5b6c115069ab8840b	\\x00800003b6af50c357381c1147f6c920dc745375c9d8e11a939ac50df2ad6ba84daad9b33e8b27ba4dcf697f372ecadf1dc32852d7516c5e27e0836ac196b2471b6827d6722fd6324f508d0277b680c06c3818c395f0cdf1f67b32279ca0d3c7fe818f943edb0db4ae02acbfe6ccbacee9084779b29f1200a1e0f6557a081d642bd0c699010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9b381d35e52a8ea5774a8f4f9c990f89d1da36643e106eebe47b34bd3db5a4858d9d0ca64fd11c92c6ffc958358559b399f1f918fe4c8ce4c45a654468bf1701	1625241889000000	1625846689000000	1688918689000000	1783526689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	352
\\x76835dfe4780324580a2ae3ce2b03ff6dd35e8b69bb2c6700a7d6970c75ff44ea4fe5c8d805ae60e664ac751bb10dbc14848e4d9a7fee7ce4215015b864795f5	\\x00800003dae42ec54610c416bb9ca0a99e9dc95613d993ff6d314d559c063365fd160d58b7f040c6fe06585378801bfae34c22c43276d4d02b6c539042178a88cb2cfee7960b2867c0d22ad9fd054ab6b6c8f0d5db2e206d1a3733574df9b36fd34f8f094a258daa0ccc2452b992d8d1507cb1c31267b96efc83d964fac386e36e91c2e7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x72ea28acfa0c9a29cc21a9cccdca074bc6d771d36acd514296a74e3aa4f0f2e9f84a1724b917304ad2e965299c78539e1ac5437adcffa5849f32e0cf818a0306	1619196889000000	1619801689000000	1682873689000000	1777481689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	353
\\x7803a6fb504deaa40eca8874ecaab465b8204a0b4d494c50931b1a8a0dd46b471157911c1d8fee87ec516ee9b796e789d96b3cad10cbea3f54628b114c6a7547	\\x00800003ae0342020259aadbc79982220f915d4c03a2918660ca3b126455f6da0d1b4bb6315f61b9c1b60c21702ed866812dad4175802700db9782fef761ccd649afd26486d27f4f6969d5243ed2e4c3b92ad865f1d83d743ac8b200db10013e67d699b0b116ea1aab36f1ec7c591d6bc569c232cb839a0ef2f1c5159242968cf41fe8b9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3b90452737148de1b0dcc68b1518cb4ad799c5fd6c4d00f777cdb857b0e2b4b1a22123631f26cb22d0cd6f9db6b68a9941752cedf721ed2fcb147b68da66f106	1622823889000000	1623428689000000	1686500689000000	1781108689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	354
\\x7923425726ab9891a0ba9781653b36c08d31e4314c89d1ae292f448379a3484d1de68b9b6966bb5e98425e625b2bb3712cb455b39a20cb939bf5105620317a24	\\x00800003c28e409fabcf7633056ccd452f867454a1f4b1764c61cdd82e9791b0396831d86ff03474805c1eacd3e67e141bbeee065aa5e57310e8f33d79c863a456dc04237819c9f114475947377bcd79364a3fbb9f12b08a65a89b609a3ec5ddacc432222cfdb2dfde26ed97e2d969dfda3ed44040f95e828d80ba287973b12c2d0bb209010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x17a9387b9eb39d0dfdd0de68c23db4f12d5402066f88202ad6511c71761a8a1a9342d419a76a3449e1c01526a1c4d054adeef2d13aa73d8de4801eec579c3509	1615569889000000	1616174689000000	1679246689000000	1773854689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	355
\\x7ab7c8ac1d03770c11365794f096dacff70fa2a638445af7c4e7159cb9faa2fefe8e2b28649210a5d4dbf889dd72c61d4866fe1ee36ffc9d96c26b5a10eccedf	\\x00800003b9fe8da95da6404d18d78169a32c4515ad2b72b44152d08795c935369f3c6c21fe41199c1a002972ac8aad069d0726170283cd973d22852924e8e0a2e63cab9a395f21f68d9afbb6ed80f409c480f91ba3a0b9ff9c55d27578eab8637ff09e7625fb98bd550e787272c3e0aa547d4948533924945f5dc6966bec99cc53db4047010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x68c0a12687eb79d0ce8231949e92734fde61fada7aea173b4dfbdb84dad62dedf2cd41702e9e3cf70f4b77957e02172eb8d79001fc59858a50aad668bb64a005	1620405889000000	1621010689000000	1684082689000000	1778690689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	356
\\x7a73578c333b88d5f57d104df6a26676f7cdd8fc308997f6836ed82b3bc7438b95f419c5e67000d511c035bf746d57524f0c7f58beeae98e96f1bf3055dec62d	\\x00800003d5f332fc347c20d27ab6a7a44c0b050ca0fea0763d764d92b2ff95c2292846fbae6b96f484fda3b820248b203f3973b7780c459e4d979305808e96192db3fd833d0f293bb87f714c092aff4afe3471fdbca46111c68915e3d5e0645979c051bfa07c77a6986d4f55b19a439cd980d84a724dc9b4bac5fdcaec57fa094c56bc23010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x428dba65699b5f8009ab094e8324df5037c95bd72ab51e801bed33db0b86d7f5681a52ac7ef8caebcf92d44da87718d5a0f9bd0f929c1b21078f9323809aad00	1639749889000000	1640354689000000	1703426689000000	1798034689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	357
\\x7a6327afd2ff51f18f1e37524cbeb9118eef50fcb97bc93850aed4bead68aa790533e85363c0a958e3effccb5a37d7c15788e846c64fc7a2938ba72cf46cc745	\\x00800003cd2661ab678532b45f38aa2921eedfcf5929f43a38ebee5b35d088003d09b2ab43671db855f13aaab9c9ae9f378306a5f03c418590164bcaf81e592e8d2c86dc7f37fc941354f9e222537efee7c1876541b6c185ffde7ffe4f73da4c9f261aff5ff7f1d098ed1b1b99c4738ba3e3545d8d64910e465d4b17c756d646cea0584b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x591426318bc11c2215b9c13bd07a5916b2bfbf60f219bc51833592f8ef2185d1006139c1840c7ab6dac0de016bd2c67ed495e839216f0d94dc84144b33e53405	1617987889000000	1618592689000000	1681664689000000	1776272689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	358
\\x7b5beb124c5b0d0aafb2d72dc763acbd1f1accc37afb2b0050fce15ec7b463819cbca66ecaeea4433df68bbda95a66a6b2c5be42633f5a97ea16633c461c1986	\\x00800003deb38059bce6cffba4050bc968d2d4b64f155614531a6ccf76c2b3458d82904c66d8f997bdc6864c875cb109f4c7339d12fd1dee20c17c2a250867b9a97e2f205c817af239d2afdf35897299fd61183eb1e62572566e6eee7ba5895b4b18f379372c429102aea5a9294201fab057a63bb88b7961c197d7dd576c2511992e9465010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x83be1d6160799ec23b38ab4f074645dffc66d80caf2bdeff6c4b88a2a553e86c32fba283bc3d03b5722db875df5fc08839e8710ebe50e5ce2c7bfdfa532d2e06	1630682389000000	1631287189000000	1694359189000000	1788967189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	359
\\x826f42ae52e3a84f08b54bacb99d3ad732f57bb0258dd9b3811f1854934e4a1449fb2e367e1de57ee99d40e8638661e68ecf7d32de730360b91a60242cb3dceb	\\x00800003a7f175f98937f06798c32ec9815244bb3bfc20c696a7740d074a7178fa01809bdd4bf70ae72c60f767eae0a1d900a18091ce271cefce50e04c5eb52de2709d64ad7af077e39a7e56ba7495b8a0e054bcaefbc9035c84eaee43d72b32242894a0ff56a63c895605e0d7ca21393e7c891adef54c62ddc6e21abb30ce750523e615010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x7980b4dbf67762d0bb849c2b3a5f81cc69c6a91ee21e67a21c54855dcb1d22f7072bea87fc1685c666b26c880a332348526c4a5025895fb4b7a4e886aa974a07	1611338389000000	1611943189000000	1675015189000000	1769623189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x857b01d97d84dabef7fa053cb4b058cbd42c47b38f9694597be9d1643ba46eb524c76a67494445d1a5c1fc1391ff08984f504a4bd4044dd60edf39a0c24e8c5d	\\x00800003eca59c4087a6e5db1e34f48b9e4795ce60a471ea16e0569b1301c0ae6a161687a3b129e978fd3e4a92c1a1910ee89f3e2c62ca48235858d6ad1c5bcc7ad23c2d4f999fd3a9e70b60641b5940d7732a65dfb99ab083975ba189d400d655f180f409d75e9946f586f27cafa0c94ad9194e7a6016f8ad77625f2adaa782df95e7ab010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xeb5cd50b5d822e910195e21b975f2a8cc2e11307e390c7c7eba8b25dea31af5b4303ddcb6621fa400365ff16d03fae2f89a655df958b5317ece0618bbe11a30b	1617383389000000	1617988189000000	1681060189000000	1775668189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	361
\\x8bf3a65bdd1d425a93ecc16a264b38d44115e48a585b5be2ea2274cbb7a6a67b931b4c4700234ebb41030e42953dee4e4cdfb6eec86e676021891c824dc0c1e9	\\x008000039d2b34dda143dd04bdf5f1d84fc8fd3a98cf5405a2b22535be9b06faab0391b4d297853c396da5b9f92a849f963f81756a005aa53c7e26c0c4a641a4d6f9a636b5c00372ab7b324f9d35be327a4a574186b9ee634e887e2f6e67483f330296baa4fac5da9d607b9613e6fc34988feb5b2190bd166c65c3d816574af1713f505d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdf43179b8d578eee137aa14b1acec0e047dcfe8b07597d1c45b417b8fedc98b6645ad296387504f4079eb73cefd06f2aae988e435e534d8baf95208718a65701	1631286889000000	1631891689000000	1694963689000000	1789571689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	362
\\x905ba92635a8dca04b8865f7c379a0820298867ebf24af07cb874e7477b9e232133d9f2bb8fc3572448bfc662e21e6d455cc6d881e59f91743a3e95a30d83c5b	\\x00800003a2c36dc37e3e98d50f6f6943d19a55f4dddd0777546b77995aa590e02963e70a986ccbc82d20ef1a143e2fe61cb23b4b20e64330efe156d7fe188b0fca0094bb103920cf0d8940637aa0091722849320cf1e33906bd123e1b9805244966adc90559650f00f627f8391bd573c5dd8165025ff89e7f570d19bf79162ac334fb4bf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf00fd5d5ee886fef9910d667a8ab239611f6dfdacacef9685200c2e1b0cdad65151310846a266359a6a205546ac1992ae7dcd7566b73549ded18017738cd8308	1626450889000000	1627055689000000	1690127689000000	1784735689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x90d7a7b2a1a8d0539051cba2b01fb8b103f64665bd111377679d309d81e25c77abb9d8178ad2c381f75714faec37b694b07fb9abfe75cca3a70298d2dd434705	\\x00800003b3b1d04bfded60d2261578824f068c947b442e0cb7ddccc441e8e6aca74edb8a4f6e27b347af9b5b241f75c44f95e8af3a655ade6d50cf64ba4d483c3b7346d977c66ed3561e77db3291e8567de68db1c48045d206074c402834e0f9396f818e6b89acf4ad0ed18e512d6926c58553657c067d5d996229be61cd816d72ae5765010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9ab80c9dc7d028b4b81c7dd3750d5d9d873085bb5ac4fa299a7e7e285da5728efd4af8de7de0243b99010f22a2bc7a7d0681fa932197ebce04d4b95670b8da0f	1625241889000000	1625846689000000	1688918689000000	1783526689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	364
\\x921f27579a6c5edf715897665a4cd55676b0ceeab3f7cfb6bd21e690e0d1e58f2151e0ef440511bd63f781d648d2d425f59283711ebcb722720de7081994a493	\\x00800003bbaa1d5a7b1171a0290c4c1308da6d6c61634a772df24635b0cd5f5e4bec38a056c6724f94e8cf7e0b1ad69faa56fa4c892ffa92d21787104b05e1f283c509efa663d9eed29eef397d621c271a504dce0cc9e9f2e50e2072a631ba2ba3934c4f090c09d36b04fb05f1f5c98895931d0d638e6d6ce29638f532f35e5a2332d839010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x154f9650368eede327aeecdf72eb2c1695491f98e7289866306a6bbf978a4ae43272374131e5f597b0aae0e765c4ca218be6910b3ea3108ad609101c706d8f04	1625846389000000	1626451189000000	1689523189000000	1784131189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x95bf0cf5222890908684c59266c382880f4a91d66bf92d1143bc52071d86228e3b9b3d9fabe0c44c05073495374c79e417a08ff2da3935816509c59c13bdd8f8	\\x00800003a96c387214384dd4c4e6864ea107c82b7d666557b4a7cbdf0dc76235860a43c6db8bacb88ed987ff93be1ba6b662d1d246f0975af3ec9e621140e01131e4e65deebdf64309326c6d1d46c71321c4a70a48469200a1a2095aeecf06524c0c76d6eb1ce4ea1ffe55e616c782362d19d183ff1cd2228fbccd0117a3765ce86a2375010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf08262c86f2d1a693e429560e72819b70fff33beed05527f85c288fd604208c97891e0f2eae4c9cc30f8624f2e148f874fac8eca7e49b8a7ec31403381649008	1639145389000000	1639750189000000	1702822189000000	1797430189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	366
\\x95e34cfaaead906a024e6f1b309d00f144cede914facaec08ae0419b08f1f1081636ccf10dd22ae812035b7b150b78a3f9b366e94b16c94bb420b50853ae0abe	\\x00800003aa5707ac51e53352dee014441aa8a293cd4bc1a94fbbc62fac63e07a05eb8d71edb4b11c3584988d9721eb1765c76ed416bb095a789a12e57d5656dc75187bd27a10051f18446ecad345f18378f40d36403e3e43276269d58c88f373a89f2066879722b0cad6faa387c471295c09b147759d54ee6f82f8380741caaea9936259010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf74bb2d286ec52ef530d390581473cd8a7fb239f83754c3bc2b6cba4c88e69192c7f1b65efd73933d033c3399a31624764d78bba3b07f47278fd397b6e278a05	1622219389000000	1622824189000000	1685896189000000	1780504189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	367
\\x97e78b65e96e2562a024edc12231dc67cb4bb840e6c74a4ffc47dd04f1538042b738ef8bf329f4fd004cf30f0d7ff904bdc28bb70a35f615a4936bccb2c0f6fc	\\x00800003d07c3de67aefe02f83510d791df5565987a5205638c32c692e2a879b7faf70abb231d715706d9e52550c472b24741d7aa917cd784ecc2c8ab49444bdf131d609f409ad97a31fe9801b766982c66160d13ae7d9d8fd927ba5f38af05319fd35d0f88ea84096ef501fbfbeda9ec648d6f4ece47f4e4a1158d7d043bc0d9161367f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x46be3f3280587a1731e06823d9d32f60e81ffa9154005bdac30ffd2a98e0737e88bb0448ad1586eed1b8e0b846229f74fd93df59e8f4cc48734f5bd601c9a40a	1633100389000000	1633705189000000	1696777189000000	1791385189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x97e7d32845a2e0e12d1c4a5593d64538781fd8dfd4f7ac36948a4e1940db04543a1ec5d473ada636ed6084712d3ed226a167e7cb818137ad2cb5b127fc0fdc9b	\\x00800003c9fa0490fe3e7743d348cc1ad0fbd21f78d167f5aa99dcaffcbbab6560b336f9e7ec8fd2445088ad4ef7d36ba9f3f8eb5e0711a60605ff8c4ba2f9c6ece955cb71984bc2ac7b9a88308fc6b58cf852346ec92c8715ae64dbc27b50a3e0089b1a12d3bf9fb704a1a09ca550ff73209d9cec45d5376333bd65ad80b3d34a8a1bfb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa504ef088d7de4cb411a34cb4211548ccf5e46c06467a912ef4a7fcaacdf9ec011504721f8db90f4790fd1c8545817e9cffa02d10cbfb3aeaa8187c7aa413c03	1640354389000000	1640959189000000	1704031189000000	1798639189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	369
\\x994f635c6a261e1f0cf5a863275ff2e4cc369bb3d9945eccd657c2d2df3bc7b14bc07ea3d7d8a0ced22d50b9bfa926481d4a2df56ccaf3fe256e7d0dfcecaa40	\\x008000039b3ad8fff6b0e6c28233c9188c347ede03aba8f203bda30dccf7c1f41c7b9b28576f4139db0c78c3f29a5c78f3aa4f804b89584549a88e3203b834d0872ef72aab02a49933ddf1b40416ff4acd38f5737d3f3526eeeaa0a1278ff17e860404e6fa480aabb2191f7e4d8318316fcf30e9b96ae968aa65c4ee2ae596cc324cccdd010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xa626b5dd1c98bb9a55eb37d7b25f769db3cbf4ff640b1817e6beb77bae2d4b1493ff39d2d3e87c1b8819c4b7f03f37f6babb34af608e488dc5901fac20fe6004	1610733889000000	1611338689000000	1674410689000000	1769018689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	370
\\x9cafb3f671b9cacaf97ffeb6dd7e73737ae71676d74016fdd8b6341e6a1aea8e3d8ee7cd4bec6dd21d640c38c71899b7e754a139ca77b7a8175e0b805e383a61	\\x0080000396ddb62c2f0212fd17be69ad1a333711fe3ab6f601ead029df20da6c8e301b951517be78a73599e41db636b12247b1d179ca411860bcaa21eebf956e9a80d68b5927813e94d9fc1482754fe62e0a52150047c8f33451fd088c7c35980956e17239aa638876c0f9b124d3b4ccb09778a496dbdd722b6d2cde173ed62b1614cb69010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x111e530921be32a72bb124d5f497e013a3019d041530176aad45132dbcd98f03e529d10e18bc489a8a4d26cd7f217337d1f650b44c510f3bfe6277973f9d2502	1637936389000000	1638541189000000	1701613189000000	1796221189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	371
\\xa30b88578fb6727a2acfac87f2cbb7263651ac6b7050673ee473c7c7bd472b5374bc11e536eccdb5faadbc5939b183bf4b170a27bee151805648689b8d4b26e7	\\x00800003c396dffcd9a051eff3b0354ed88afe01907cc848d488d41b88aae8f67a0fa231c3875d06d13a18a28709e70da994ea77c468bea91914b751208901537536540605de02ebb737a78a8629e63369e259bfc585ad90b7e86ed317612cdc873b51c8a39c83497b1914a592ca983531f2b22acfadbb91c7b334c2cf55806675229f6b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4fa674fd6fb518f889588969c3acf2a9ab702c96ffd08e1d20b9ee4bc640979e18cf467fea2905b2d5e4f5c000103c9425df2f8354e32baed226873b06026506	1621614889000000	1622219689000000	1685291689000000	1779899689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	372
\\xa78380a330665cd4e50bd1e35da6c76ea2f923d4d44c1bdece30ead814d3236ba5bd50fa9bccd03c1b7331077368055b94e1faad3506fd5a3683f8daa047df71	\\x00800003b543fdeb2da93c7b19747b35af2f5ec0368217e4a51507228480b232aaf26c1b6cb7f151fa04384590fb9b5b5277955caf7c1b75552349477a870f5e6f66daaa36e7a5ad7e1f30ba2a0356211d0c1badd6440919014daa7a5d138e86100c877d24ada8e7b4ed81de255d17469892a06b5738ec2af83d69f905a30efbda522857010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x62d6d6471505d3eba319865237c7413c4ee8015b4f71e0ead2b474e0d8a0457a1437b8fb8776b3dd49ae90c7b35af5e0f079839e014f783138de18e9bd3c460c	1616778889000000	1617383689000000	1680455689000000	1775063689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	373
\\xa82b6d363e721fd6be54540b71f9c715366a06f091dc1f9c3bb574be17254cf92ffe95d80d81640394350228d726a49e17bc95264304db062f0de527dfd3ad58	\\x00800003c1cb00848b1ee0aa087d17abfa6302a513e49fcf3c5efd0ee62f71cc7b91c0c29aa2e7c647f1a4ed4529a4690e64d5a6f910fa9b0a38801092ee09d0cf7fe4e1e316ba0b16addec32b699ba6383aa6b3b2adb1cc5674c2ecd8ea84c1a50835154733bdb858ef1aae722d42667087a50bf1ce8a14d9ac62d4bc311ef453eba4d5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcfdb1f623ed351a8bfc05f8dcbdee05c56fdf1ca95a2211dbb7ac6d61024891ac119d9c5be9786c04a73a02f4c8cc00fb9562497bc071a7f7938d91d63b64708	1614965389000000	1615570189000000	1678642189000000	1773250189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	374
\\xa9934f67561889d763c2acb1311c460734b305c0b4535be279728a5ef832d5dd00a70368f095ab4d7176442fe27c75aa505b688bb1c9a5cd8fc3e1007a592ebf	\\x00800003cdda5e06aa28a30eace97275dee8a93402f37ff872e3b18c9834ce81edfa65dfd0377f9c00a07b7292b62fc70f798f5bbe06c7004db1545bbddf4fca2673129000464e3aa5d7e0d60910be6cd916fa98052d60e97c6bf4f87616e2d3455cdf3fc34e19c2a7d2b785721b5adb8c720ff205e6098dad27bab640d62dc89b8e6cb9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb895c62fcf5c8433559a805765902a265fae068607eb17958d54df1c75377068058e375ade4edd3825fa726d71439c88fae61f2728f31489e18d808f64853201	1640958889000000	1641563689000000	1704635689000000	1799243689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	375
\\xae770468301c8d85bb5e4642e63e83328bf5391a3e79646f1af5273ca99ad3ac603c9939890c3ae1c0cc0b4554fc5e6dfe731085d237ab5a0478633657f2ad25	\\x00800003e4db583d32a198eb603b915d252ab82e7964ab487f179b474bfcfd607acef8f068997f023443c13ffb335f1e55ad7987c8a16292721245aaef0137f83de7d98f0b722aef00b06fea9ba18e574b735bbc1f4dd44d9e008913bcf524e8dc067c5c583c0b7293b886457ca8d7d41271cd19406294b65a95163fdcf525449bd195cf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x14c3506a498281b35a73f246bc82152eb2ae6c428416e66f50838575210dc1b2ad760fb67eaaf8a586d32813ab9ac3a05e519b478ed737da12a3bce1e3813b06	1628264389000000	1628869189000000	1691941189000000	1786549189000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	376
\\xb6a3ad3d16ad216d31017329d8ba88cfc9e41db8f7bc3c6e7297d2ab2fb9d928e7674612799d2f8fcd100b3da2b6476ec69e9ea6a86febdfbbeaee4e619e6725	\\x00800003d1657b44aa9f1b349b65863be5afd26a7e421e1fbd34f0ca1e270ff320bc4d5a4042f6bce2495b8bf1ab1af516eb1da41195f8e53e67f89f47084521e9589eba287664d7fd76fec15624b6fcd68910e11eca7175ad744be8216556d58a0daa7ba170e61407fe5f260f4f41271564fbcdf1b17b4080da8f71dbd2d4254d1583bb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb0019b7b94aece164a17ee9167e9c0878f7058c88a9445056c7738b29ab5e58483ba91f23cf9aa98bace1377c5fcd1a582800e2f5471ab42dc2911368f398608	1614360889000000	1614965689000000	1678037689000000	1772645689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	377
\\xb667a651d425507fcd66d90462d6db8bf98dc5e0edf370e214db2c0b60b78bfdd176e0ead2e9e7573d9e79df39cce66c7ad717894a2cde2e0a2911b22c875323	\\x00800003b8273a0c434bd550510f95b246be041242f396188295ee8219c65075ffb100e52f8f0c202d63382482760dadff4e197455b3bf3ae4fce677ecca3ed6a970c0054b940d5d4ca65f7766bb84636c95baa8026fb52e33bd2ad5cdae2881ea83cab97ec69d3065261012a6617f820fdc15c264fb69d5818a0c0701048a1279a9eb57010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcfedb3fed953ea2952b52ada54e6e1ba721f7755e674b9a3459493292ecf99d79a54c60dfbcd652b55bfad746d4ae76ee1e2b2fcef4201d5cba301a82fcc9102	1633100389000000	1633705189000000	1696777189000000	1791385189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	378
\\xb913f3c0579759cda292f184457f5de16eec243df3f605291acfd7ab6914401477ba5f36a3fd76d88f38312eed27ccbf859368778a8417470ca29219f3b77ecc	\\x00800003b6f6140a5f095c6a389bdcb946ace96b47c145102b786edbd64cd56c515212714dc6d6bd8081566bea8c4b87cc78166c1e3eb519f3c2b86ce3da1a7fa3339ab7d1306456851855353d00e06a6387836c5915e35f1ca0c2111a4cfbeab7a29a81462fdbbc1d0e4f9a1a292d64791034ab8dad239961e0e8c2edd2d21e4a258c19010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd0a18e89c9fcc16e64cd2f77854dd50a04bba1fc7c43ee9e5e98cdd95ea979a3638f6b47f79ff0cb1c54d16f0ef3b1ebdf6891f3a41c0b3758b3a7faa1ed940a	1630077889000000	1630682689000000	1693754689000000	1788362689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\xb95fcd79100cd3a01b4c24f69aa9ab70df352495ef12f3f90428b747b0690bd46f98df582fa666cec341a7798ecf3587ffdb838ca7c0de73435fdb508860f1de	\\x00800003f21f0dc8baf4eee31130f63bbd4a40453867634d4bd838cb77bba73c5420436a55d7b85cfb4b8fe0da170d66b06d00832b7c444dac2ad74e25116fc3a28c97de49023619f8c45e1afd1d65ec1bc3f413b904404dad47bbefd0a505404a5f593ac2a83c0f66e5607ce6ba7719b766ec0b7c3361898fbca3528636197fa4bc66d5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf601b9d5340e44d2d0f2f97c070371e54d3a15f1054ab1e4181023276ac02833fdebf35fbc6a21c583cd072df93881ebb56e11b4b6d97c5d1c8ada82adc52402	1622823889000000	1623428689000000	1686500689000000	1781108689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	380
\\xb99770b4dc2e2742efebaa4faaeb4d14678b2b49ee772fea77d4fbbcc756182072a3b554225c75817ee060cf0be1410c56d35b6044e67f09ca1317a522900089	\\x00800003bcc99871415def2e86784d3337ca184d338ebee46435c8f14958bb0c2f0a66b71a96ff707109cb3dd54f2cf3aab922767926de4254e0fd5392f0bb5bfccd36d2055b8f3d69393bb85d0e51c3c0ed22121db7844c392559efc3ffaf7ea630dbbf234cf4d34cdc191148773d48a7794db69ba58ee10bdc9b93734fdbc791f5db15010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc44d6f73121ffc663423030dd3b8ab1243911250ec5be241fc45462a441f19599c2d94e09c1c713119fd30a9ef7dc6867045fd75a48a04abf21869778e046d0f	1630077889000000	1630682689000000	1693754689000000	1788362689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	381
\\xba0bbc1be4edbf72f2b4dfa52e3b81e3b611531ebb7f1770ba9f5fe3fb26084e61c168af4f3b6447cc09c1df238aed006570e5581d483d388dcae3b9a48c44ff	\\x00800003b73df830701ea082dd218dcd76bcbf881b2adce5b1477fe4eff4886abdd7b283aa1620e1b536516d1a220e6bbb8e4096dc54bea764e24fa401732cdeb05d7ba68d441cec8b7bf641c3620c0ff7cda7145e89bfd34bb2907995338ce959cca543314129585b530c8d4e40f425b2e9145ee76868308207141ff7e1a0431c4acc4f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcfc650edb2dd3fa972c4a0350ea205277c28bfdfc421e215b23441c59d062f2bfffc16d1881493b095c4e2ee285fe3fcca4a9fedf108c97de4ea0d5d00d9330a	1613756389000000	1614361189000000	1677433189000000	1772041189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	382
\\xbc3b44bd619b72406bee1bbd72aeed474b55e281b25677bfaea4e514d833eeb0ed6562e42825420e8cc9e232e97a523b51d05db2985d445ea732ba05b6297394	\\x00800003b57de1428ecbe9855953bd8d221b56500d44a1616aab64c2dfb7f64eaf11b81e204b7401d08ab35d6dcc84db38f779a5390b79cdf1b8e6f8c48c98ed81b16ae7f2cb241c1d4e896e202a09bcb81eca117bffef2aef0b2692a788bfd44704ce972d99f794b63c78e0409a16472f08a6f2ea9cab29b5c08a448340eef13306ae17010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x971d8a904da63f8ba0f7eb2692a9794b87cec18aa5f0f3b8618ae8de00fb366870b6062639643b8bfa1f7f9c4ed2f10d17e8d5e807dbdeab34fc03dd1501460f	1630682389000000	1631287189000000	1694359189000000	1788967189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	383
\\xbd571dca59159c5cf9b1782771585b86409d15de6e6384634f87fc83a250ceb75ade1228ac79734162cbf0e651d78e030c6b78889d4b76657a3272b448c80c3b	\\x00800003e8ffc9a32173f7fc93e5666b48c2f5092009a53bee06902474d5917d0374473b35eafdcd86cddda58810a900484ee90a865b40f28d6021be28bc019332ba59dc7dca857b90b0d089b33836c3c33a23d16025f65ba663a4d1b0a53534e76ca2affcf255eddde8621c50ee3d0365bde348d51dc5775ad885070972d3bbea0e247b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd1d40e9a25a6e0ded87d06331e2b3ace3ab634f174a05071b35dbfd34b91f158346a7918b062b4409343be9033db19a89e1a18bd3c1854d164af8367301cf00e	1622219389000000	1622824189000000	1685896189000000	1780504189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\xbe272d72d4747094182fb85a1fc268a3e2a9afe1d73fb696b6c7565e7a8b493a9d88ceeed4d0d79a8ff20b5c2a8418660cd960c4d11d3f2080f44cbf8c3c78e7	\\x00800003b5059433df551ca9a04ced32119014a5d5ef0a6b670183aa464f6e18b853bdc2f7169d74f3c4bd78ba9a7b747b8121c3dcf23710a31881d723515f5fc67f2d019d93a2cbc18c538ff729f03e4448200cb426eed1e2e39b45d37011a056b13bd41ab31a621f72670416afb104f5179bcd0dfc580a7d8c01cbd90c0ee4e452eadf010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x32e83aa7cd2d39e378e696e13aeadd4bfded414f86585e247a22a5ed7f824afb40ec435876f48ba801383041ed61a6505a7ea441f17bd6be0b79ba220766310f	1613756389000000	1614361189000000	1677433189000000	1772041189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	385
\\xbeb73d43f1f3c50f81e9b8a825f540469c4e2f0ea20dee962c8454d1d29d295d3ea46489c4cb6a819a4ce20b3fa1d26c7cac66b4d8fba6adaf2fce41287d8a9f	\\x00800003c96c5b95aa72dce56f4f116ccfb0c34dbbeb7498bfed6bead12668186e9faef16941869addb1b8723ab212ad8cac5cac5524721b31e073f19cf4c3c3545941139be96e60a943c45dc4b96b6f7c17c599242c81a8939efe41efcea7f3a6e1c9b4f1d645a5fef11380fbfe26d394b42992784166148bc9fdfd352dc067b3f1abdb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe72082f88585b44bb2c599e7e99b4a8f5041c258253cb98af596dc950a3341891ce8d021fcf040688d471c6e2bf04142bb73f9ff39677ba0d996a621433ea20b	1617987889000000	1618592689000000	1681664689000000	1776272689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	386
\\xc05b2dc090b834f270c82e1f1dccc62f1d81ac92bcb0974b6acfc09c5f7cf4bf4e3d73d644adbedfdaa07a290e2bc76189d2432947360a03b3f24f08c3fff3ac	\\x00800003c4b5483b30e207bb9ab9ac50d1a51ad2738295fbd8fca8701d12d9096df020a0db7e93f2a20ded44fce05a0d19e544688ab50846a72de6026a26b93c8bff6f5d30e2b544296dd65212112259f5a1b99cb01de6119bb573b87f071a48c0e3b33d6c65a532bdb03e92936cf30f320899a48731da9dd57e4e449cb7b1d40d81b067010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xd7377ce17b144ed6698918065de4a650421893d2700de4385f5231ff726723e3818979e1daabdcaaa6d6ac420e5ad354b7b2619ff90eb6e47cc1319a4835920a	1625846389000000	1626451189000000	1689523189000000	1784131189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	387
\\xc03343ec16bb16d1a7a20fafe79c0e1346c58dd24a887149027a59a414118f66d100bca5868bec4f9c338c62ac96906a511c32152dbb01460b8e8528bac54334	\\x00800003d74e07331ba7dd67343f5e53e0aa680f388b3281cab7bc54a7d19d4c979121842cd28b0f690e1a3f81513e9cdcef25fac162fb3ce0ebbcde0bd6a5dc57265a23f8d57914d910ebb34fc535b77e13b91941580e7e616e97665cec298d723b7bb7f1b63884877ee97c4bddd4190fa9a8da114e05ac407ed23df1af7467bd5b200f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x79a7bcb8b2e2187ec23e4b3b885bbadbcb0baf8e1da38a69576a86047e8e6deae9a34edb63cae8295eb2e65d9cfe5d37e7a0826d4d05b9ec8a3ab2cb039e1908	1624637389000000	1625242189000000	1688314189000000	1782922189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	388
\\xc1b70c361b3cecc79da4a97a2b0671cae96da60501d9c370816beaa1a533f488859e624ebe1792a8c0c37c385449ba2cbca512aa281820ac603711278781521f	\\x00800003bc2e7e44c416a5d9a318a0e836323009627265884d7cbea1b7e4c60706ad74f4ea7e37adafd2571e6f67c80c14d88c84490d5e93555c90768a90f9ff5af9c95b344d90a491c95d4b583875629f471dcbb5fee37688778396e140ae36aea80da3bb81e52654b3b37d11fba9f6ed2058e2e1fafefa3208a99be70203a4a660c71b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xcea690858439522dd066199af6957caadaa68a2d6582e7362ca5bb13062a8091577e79147a80914409b8718bc3359b292425c3281f92b5f20ce81e9e0b968604	1614965389000000	1615570189000000	1678642189000000	1773250189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	389
\\xc1e719e1ddf8a0aec225a83ddf1e0988b40328ebb9875da70881599f6b9afa88c17f0a0719eec74d11d16dcfe0c69401b29fce746cdaa3e220ffa606c79ac519	\\x00800003c60f21e5ad7a4a210d8c35d212502ef6d30ebb085ebc59d67579b40903afdc691bef026f390a500a74320726aefcc59d37f78ba452e2809e45583054f0b7e6c755abdeac38ff4a3191c813c38f437183f8acfc1fb43788c2925f7b3f304dbafaca5f927461c226cbcadf09b0b1d75b8ed16f383ccf960b115fa5938c26cee60d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x99d2c5280bb5002465c4f04475a486d76239c6147444994c438275604d8eceb659c3a9ff6837cbf394ae6846552113d525871c94ef446b4205e9dfd69261190a	1613756389000000	1614361189000000	1677433189000000	1772041189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	390
\\xc207deb5f01f19802cafd742ff357d5f9887921bcf90d0d91dbfa6841ae6a23b017e202259bb66ed472d76974cbbf98dbaf150dd99d9fae26b85d9de61999f6a	\\x00800003bbc03f3ddb15ac4bbd7d96d5340dbeb086ebc50b6f51508791eb6ffdc536b8679532dfc31aba5dc8efd687ccdb754aa8eb1df896970625ae971344788fff588550dbcfb3a731c209163a1ee74a9193fe6080bc6eeebffc75fb5eed09d6ac0c5e55e1b957283135da5771318a671a0528234396797132793bfde5616e243a8d55010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf2ba5ee8071607fd296d34b30b29c6d15ed4525da9fb6fb72eb3562e760159e96ca7e59fbe18be94061fc238dddc0bde842fa6493371b154baacfa8ce1de9209	1634309389000000	1634914189000000	1697986189000000	1792594189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	391
\\xc4033bace2f5da0a18ac0037e9ae1f6cf4cd0044616c2075babeae3ea33ce2cf5d0e24678791fa85ad6f0eb0f44b9051f2a13f4e47da4a8725a432bba9ad1828	\\x00800003b00be0b65b056f1045437022ddb83fe0ce00459e20338c75e0209e3e10db59f657fca0ed8083c1481e56c741fd4569eddfa5492e5685f64bd5bdf047a2e568cc91381442a8dc577dbd75f1999659bb6f16c00dcdf4a7197e5ceda7361c9952b39089e7ca92a8cb64f38ec6161c1f673eaa8fd826e11652b610b42cadf99ac995010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xaac7f6c10f353fcec6c6b2df037f570e22d398058010fc6c891409c3f7c1803aa1c1016f7e355cb67dbca75c3b5a89e6025b974258f71dc769cd5ce950c6c804	1627659889000000	1628264689000000	1691336689000000	1785944689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	392
\\xc98fbee0eb32bc609a130f19ad676b3be1d0439e85fb6d292d7333821f83e709b059c165086c8580d303345aedcea4a0f8145ff4d8bb03b979bf9a5a221394eb	\\x00800003afa15e7b3e6cfbd210aedce3fab8d23b65dc446ba4ef28081dcc1dd955dd6121ba7d5e4c755551329455a22044afc0ea7b6affe3e44950f5e3aee0c6d05f49f3434d1ad209c1ba09d429f5dc59d103ed013494e1b051ada70f1b539932bccc01279cd8e0d86db9675282d3837af8794d9f62def682e98da7128f177ff3baebff010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xca5124d6954c5173fc8f06b7d09fb47b545dff70aee531fc859f970ce037fe5338155a9c6449b67847f2e3d4af7517ed3829a66eb09d12545774c2ef08a0a209	1611338389000000	1611943189000000	1675015189000000	1769623189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xca434a8a58039beae183ff1e40a1c5442773702605d4b7763be7d30379fb18a8a0f3449a08b97e1ecfa71ee92ed4e8d5aa8cab0c50fe28cc63471e29276dee99	\\x00800003ec09684c46f7f0417365dc032a003ff8562cca08c498780ab4e43d3d31a9ecf0d7ddd00e2ff8cf7a319a9b7163a03556017afe88c283aae8ed781c88c940bc60f66942db274bb31ed4df197bb296c25e5c95ce832bf2e996a7cbb54ffd82eb64f064a2cd0d83647d68e6d933c8b4616cd801b956bc783c0e8c52f7d8200143e3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6c67b552ae1cde8d1895ed607933849cf80cb99cc7803b12f7c06bdc9aad7eff2cd040110d525a70f8acf86808b183b43c49304ce770c865512c5e0ce0a8c70b	1628868889000000	1629473689000000	1692545689000000	1787153689000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xca8b6cc397898f3267a1c18d3f88998d2cb02cae83949da4191adeb04640d0cc5789daf99f2a24efcfbf8362b4e04fd9da6d9177fc14a3022e241f6782bb4c72	\\x00800003bf4d9eb2907674b54b60ab7077352fbc0bc7b2012c4fcf8e800d0a0ec26272bb91a6dcecffe69ed9e3c886fa5d534996997ac93a95658ab2b11599abad158e7b3ed02145ed66541b6ed83eac9600aedac63f5c88f499f40f02cdba576bf477be70c5cea5d19f7d3402fe0d79e403d34a9eb0c85498e3a3005cb994c5b576ca9b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x154ff494a4f49445069a63aabc1f016fb977ba4b21d3eb15b487d97a8bbdd3a17e42e2444b61c8fc116aaf4f8e8e23526b7f32dfff5bda0488a2832ba52d7e00	1625241889000000	1625846689000000	1688918689000000	1783526689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	395
\\xcf1b18832c88386c9b7f743481325ac9d6a7933708dc39c8fa8493f7f1d1c9cb3b7666b436e5ec437cfed24eb2f31bfb0e0db77dfc60723c1c1f4bde66c98268	\\x00800003bbd07af7401695ef8b92445e30597a7023e733f891f4b2421f7bfb82e408107b9b191538b82b61c856b1a5f8d387affc3b1434102310147e3b68ad9294a7bae198217f2fe8ec76121e7b1e59221969e0aa0c1bd814d4ef6ae53741c1860095acaaa645ea46d76b12224bbe9757271697d06d46b66a18ada6f72e0896df2ef0f3010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3af7017a2b3efb15f32c57617e3b6d223b8bf233ff0f499d468b4bd341a8895269ac8080ae88b090fa50ba77da6b5a4b889e1b21dfb42a2c267957b02b9ea701	1611338389000000	1611943189000000	1675015189000000	1769623189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	396
\\xd0efe674afca627016e66ce9cf1fe0c9e8df1d4e80851cea40536b7dc3aa47c3aff045a3e1031e64d7af24bf11af7a2b8a8b323c97e2c8ca51ab7c2e2f871a05	\\x00800003c762b42f7d943aec0c1e37e860eb116f671f4d46945588a06d0e8eb1a44671e905096f5d9cf635f56c0484a7c84357de087045b0cf17c5ed87f79f287f8753cc4f4f702c75df6d881e3c0801379206c768b121e8fc39f0fd0484a3ecb2abc8cfb7a9292ce7e61c068c40b4154ad8b5d1eeabd8517b2f2d506cbd42bebf2adb19010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xfda6c23a51ffff3154f5cfadc486f3fbf711d803e09be97dff783879c442619ae25e1f54c94d336d44d48c6b5a5813e6344c775f4e8896ed8c6bc3e3899ff303	1636122889000000	1636727689000000	1699799689000000	1794407689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	397
\\xd1aba82a820ea667831b02e3802c72433edcbe3f37fe5418f3f396a9d6d82457c44d8f050f9b9b9f1fe6daa040c94a1b4d2c953eafb913fe6ed5b43f70444efb	\\x00800003c48d0bef1d0dd08704216c82e2bc3559a67cb61058734207f45f32f82f8125cd6e0860c16c3012cd00d79d42b32c14846db9ea85575699613fc56cb629dc392415efe81395b1f5ec90c844e3c7a1665e34f41ad088b1fd32f417b992a52b4a8e6d89b9bc3126000a3f495bc4a6b1d6cb708b2031867f739bbca38fb93fc4ce99010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x0124740b216a540d7ffaea3e16b8c9f39b5a07683a2de6294aba987c1ac1d9ff3523611c080149a4ad1c74bf356c1fe7d00f3d4a95597b6bfa6f428f85554c0f	1625241889000000	1625846689000000	1688918689000000	1783526689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	398
\\xd2cb98f47d192510b5d4db58955d6dbb94d27efc9236e1d1fa57625fa4012554f13d6de6d4d49c3b24d3801c990a9eea59acc243ca6c526b5de40aeb8d9b91ea	\\x00800003d9f2c306e45880bb12f6d93785bd5c45bd57b29c7410ba32b2a051101f297503780edfbbb95ffdafa8e70f2d6a2b5ebddafd528fb8821864e2cc0559b2f788e7bc3f775068374a5476a8f9f64bedc0c2f3a0734bf693e6d4ec748de59156a7531ae60c7b9260f94bf81c7b634972bce3d4c1ae17eb33aa3ab35de31c21c8de93010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6131429ba56fa566e47b33e1c26a79dd8a400584004c999c6bba0431d8ec90fda7cfd33ac9b9c563e83afcfd25b35e2a703824ba1df65472f95826f4abd27801	1640354389000000	1640959189000000	1704031189000000	1798639189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	399
\\xd62b959c9691b6e2f9346f937b5b55463847ce1f2b1e59f574de607f0c5bdcc2c368d009a07ac5c3b15be29a7b8d9d5a0af1ea114405f31bd87c98b90e53e800	\\x00800003c0f8d7131b9fa2aaa9e6fb30b14ca10c4de08135e34a4467caacb4e27f5f734bb966c79bbb6fcd4caf919d85b526856dad67572c26bd492528be5749b801cf8c643b5aedddf5e7b89157a86c7de1140f4cb9a6127d58a164b06d35b02f772780a4a4700c2a027542cd94f8b1e95b4ac5fcb4e26c90080dcfb8d8d1f7ff49f4f5010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x675203cb67454a67e30980eef0b111584c9f2d662e6fc128b5562c4f8666e68f082c77763b81913a6db2b785b226977f5563e64ea8297d9b1403ecb635da8b0a	1634309389000000	1634914189000000	1697986189000000	1792594189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	400
\\xd657308e3f78e07c736ab15358016bb414211c6695ca69fdd57b2a83e2a1a61997d62e6c9684be7bf59005d16e3a1cd67bf75796dc64bc515fc27bd4e885f32e	\\x00800003ce59a9369d56ff22101d9e9760524a8cde94fc3e8c498b42f712ec8e23ca37a794e09d9367d512b19cbb3c8ff2308594fc9ea2400a5ba1160a364dc7ab99277751c7701a98bc2facd4bfd8b21b2845b0f747c67fd4968114ba76df76567e5e99dbec12eb769dcba54118e579f1a390c1772d9f96c885d1794b3032113fda830d010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x03c01eb5c4d892884b92ade6ae89d53d5e68d30dbb32bd7217ffe15d772d3ca4a4df4baec4a9dd892900a64e668008c6cb9b764ee3d54068834feaf97bedc202	1628868889000000	1629473689000000	1692545689000000	1787153689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	401
\\xd8c3e7cf05690360d6b906d7d59bb12370951de4089115b698a4d29903a13c656bdc2a1bbcf0dfba1a266fd5937f0305f0fab11ff623be8f2cf4f910eb94b7c7	\\x00800003c74511037c46c1079bc6647197806171b392b50331aa7d6e4a4e0a0ffc1ada0b628f6566ec836e882df9357f99afc65f0e2d82cbb96e438be0abf8926e2f038f8ba5bcf7592a32c9906fe2a21303647431c4dd47b61f14cc64d648d5dd5844a6c006c00dd1fb5654e41b6ae35ed705748a62e8b9528b0b60f72867f65bb39c51010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xb5fe8ff42243306cde071ab9aa9dbf40d9013822415e60157928c84069e3e74bcc1766cd4e0f3de6006d8048307e16acb6ae524226aa6748c6ea7c752bd3c10e	1610129389000000	1610734189000000	1673806189000000	1768414189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	402
\\xda77c6f6e98a3f6e5874f2c21fefbfd022dd72834c663dbbb71558c120729aa9dd5a83f4c3c411d655ee074cf74e4e61fab54e3c7e0cb7184c5e2f205373654e	\\x00800003a6bc91ca846a88a947cd817fd69a7a926be3de53375c7fb56073ba364e4b853f5241cbd62586ad19454741fda0bea2f15c0b1c94e926c10d92c97d809de1357343f08966178bf276309e1ebf3f21396f6abf9900009aa7f253320ad6a6eee53986238c4e306ae140940126d3d812bb52806d39e13a4ec05dd668a8ab26345123010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x65f61ace9ec14329dffefd30f55a1936fcab6706ecdf4e0cb6ca97ce884ccc55d70584f790b7e64aa354a1b150327f44588612fab53fc830c2faa9ecb9d1e203	1631891389000000	1632496189000000	1695568189000000	1790176189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xda2f0be6fabeca056fa4f6072606f0529c1f4b169bb85e509314c79e236a31de979373069a6dac7809043828c165578da0618df300adb9f44e6517d40d6b1341	\\x00800003f0ee4ca2a0d804760e45614cab555cf373e8972609ade8c6ed1c2d533a85ccab096b306b228b15ddcd59f9521d4440c38a24cd50edc56d49698ce1c0c756e118fb709a67d34e6cc49e59442ffa9955756f7854b13450b519de05f9a1a165d68f4c03bafff3abe1d963d0d5d05c0db3f5285653d441ca80199c0c83b12987fbeb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xe34a67379936504248c787a37bd3039407b7bc08ee062df05c0f2ad3215b2c28396a1233ec9474363d1e53bed06998c51bc1276b7a1f614b677346927bf98a05	1613151889000000	1613756689000000	1676828689000000	1771436689000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	404
\\xdbb3f8128488f7bb7a50485856e261c3aebf1dca7bf7a271f3082e31f829ee2c89992349662ea3fb22cd5053a4ae39d1ab996e4da0b1b23f97eabe25e285f316	\\x00800003de164f40ee201a4bd6048bdd2d4b75f80af32b1c5d5d1627b3faf2eeb55893824623201095a3a690c5d8d3cedd4ca0c62280463383b9a24948d023f4f0d12bc7a2cfa82cbaa0303ab561615cf4220bff753056ca043d84cf1bcb6506b2b993ba33a054ab461565bd9b1fa32209a96825255cf3e21f60286879f5806f4f8b1d93010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x40ce62d860364f34260b42c2182494a662ddacc4d087a4b09b8b07048796845bff0b9b7aa4eb66730daf8d0cdb886c116a388890d9696306ff45ee53b68dff0b	1611942889000000	1612547689000000	1675619689000000	1770227689000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	405
\\xdcc70d2df0a5967687528cdad602f4a93f0e06f7bb4cc53e80698c505624f27b4099f47bf6048fc55e366b44739103a117d6ad822dd304a8493d3f11d20909a9	\\x00800003b78e887ea760cfe0e5df42209073e34038efeca2fb14f7921637179b1f9ac76a30cd70b3bdea1eb0d19cbfcbce25874849e75652ba237634bf83f8f0fed7a0d28864431a2a82f48c04d5ed69db8191c87d22efd97046d58aa5f60a8f9483b09a65b98826a540fab066c19cdaa12d17e921530151a0cef65d99a8e4cfc7651c9b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x10285600560dc38146b08d84a323a5acda6a54f16832775aa43fc7ca0effc600942aeff6536b46a8fb9da7174091ce8eee1a20413955827b67d31a8bda77940a	1636122889000000	1636727689000000	1699799689000000	1794407689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xde9f95e94f8d935727a94bf529ef4daa7a376b0a297eb22a65f0c45c12cdb4105a91c2a7e879c781eb57e8ea83eb108a4a1f3c31f66a66031a2fb34ef3239d17	\\x00800003a78bdc2096c6c0d06816bf07527b52ac990c48fdd678266875c2d2edbfeef3a96184f3363138bd80a8d3959107047cdd8bb0b4e0f34f64c9dc1422ea90515fe14a1b89ad77e6cefc10ddb164c43ec458f38ae8bf1cf29a6703fb5e42be2f60a878a07c54d121994c0dd18127d3d5a2ca16e0e842e5b160b565c2338f6b4d15c1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1654692a6b386a4d161c2bdefcc57f21f7f8ff9f574cf598a80ba7f31e172b1554deffb4d777938fae3194f451d494414553d2e1dde0aa7965e2301bca89290a	1631891389000000	1632496189000000	1695568189000000	1790176189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	407
\\xdefb447747df34c6cd72f2598e7efdc77a3b794063c67c84946796f3b039e7d181d66fbaca2238b019aa37cb62a302d7205ccb56a4a0e5388bdf1c35734d7381	\\x00800003bf5978b5930625646ea1b360879dea6c8e69a92e193fce40d056dd8f7eba630a1189394e2ac914a1ffabf20b0b1e4a0bfa0dccb5fb064aae494e8e21203ad5f3baa8e754fb26bd69ec6e59ae81951a632aae12314a21d433b6d9714ccb373188ffea73ccc50867c001fa9b47279158362babfb48136e34df886ec4463ae2f487010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6e53256ef7b4665ea78837cfd4eec4310446a402ddcf2639b9cba835b7e35c240f860660a65506ef13937d8b95bdbddfcbb2893d81ba01e0a18e7833dffe0e0b	1614360889000000	1614965689000000	1678037689000000	1772645689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	408
\\xe0afebf6533b6d7c7407ef0cccc52cd1788659167d744f358b6951ea2c5539d394f9be5078da3ab9f806f33b04ee4e63cac6f57739ce6554937a64145877fdaf	\\x00800003dca8b4e41ebc092b755812ba37a4d3c4a3087bff3eda5b6c2d636de6618c7caf52a39679eb5ecfc25edb20da8c124ed475316a712d3692f20466f88a35a9ebf12f1b1cc8bd5e1c5fd8af0ff1e20d1ef31815c8cd8d69481905adee793df930ca5aea815342cf3e6ab0f99c253eeea398d88d6accd1e11759b5f2f9902858a1eb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdcf12db78600ddd8d0d983f4d90b2d8ae95ccdd398a5980a89fe748888bf0a7559ee19f73cca50640f01048a91590cd1f7e8831e094a8c6bbdbb554366b91602	1622823889000000	1623428689000000	1686500689000000	1781108689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	409
\\xe1cb3593179a4ab6f7425f6735456cdb3a6c431740c2609e5dde28ad12475bd0416d00af9cc773eb3c1441d14660909519556e60a31b18578b15b7e236e2c5e1	\\x00800003a56c0dcf566cad0944e454a487f002f65799b365f36fd1f786861b2d9f2140498652d7ff70411cea8916027f2930de82544c167f0b1d4846b5ea9f650cc01326d4002f4a3c309c329a4832c7a79f9b9b649e114bb45d3b565aaa69eef4f84d8607c69c4b805ee170ca70f64f676d10da6b3c710561be4077cc2ef46504ba6a85010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x40ac144630097c9df396a9977593dce6012c464f4c5276dcde6a347bf87b0128a7452747dfc27c9b4507eb73cb34587ef322f924b033a076b65b99eda0764504	1619801389000000	1620406189000000	1683478189000000	1778086189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	410
\\xe2ab1fd34092c1c7a3bafaa8069c4c23541f93fcc04b1e43db93231d9ede25bf683973cdac17384853fe3085f55cc767c4308e2db3ef648c269c7258f2b2dd12	\\x00800003a15cc357ba73c4b0bab91fd62166dca363d0755d021036b83b3214ef0924fb3495c787d5a9aecef051f9fe6297067331bd39be871902dd73a052227521dd70d745f634ecd7828f5b91a9da6b702c9844d0eb1575a303f05074e75c65ba21467ba6e441b1a603521cdaf4504116d59dc0f42e647ee85b3f4512db48731eff2111010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xea64de79e104057bcd992ec5b94ca0e51be01cd3bf8ccf078a582378f60ef3d3aad4c02a1e41794dae0354cb51475cf8a0f7db1d59991a8dbfd8e1f485ef6604	1630682389000000	1631287189000000	1694359189000000	1788967189000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	411
\\xe37772c17f56069efae11a779901d8f01938fd41992a6da5121549f6fa94aa960c6ea06a095cf95e9239edcc9e5c3c0a69447b658575465dc4977c4ad51e8a4e	\\x00800003c054609fc30f000a72d4fb1cc506175b0f2b1ca5aa28bc26df7fc0dada21d5f46f9aaef47f9f0976283b5b2d583bef4740239ac15e356dc6cba3c63892f0175756ff4fb0d61254c8c7750fb6dd0b3a6808c53c80d30aa1eff65d56471a72ca59fb7e0a496eae129cef592ec8815b2ae2001d87888d41a6f8ec8e5cd2c656e52b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x6fdd3f9e92e2050073e6176a34b424dca44b53552efa3b00f038866f47e4d928d695c4b370c0ce111f307ddcc733389dca344c513e8fdc32a4786e1d49166d00	1612547389000000	1613152189000000	1676224189000000	1770832189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xee63811815353a8c396ccc17e2f6966a5e92146607fea5b505fa9e304e7ee66b26a2a2512a56dd3db2cab4645f4fc953f1e6684e900b414137dbffb2b2fab693	\\x00800003bb18c2c6ed6b0b7471377dc053be8540f051f5ce47608b139c505694336645f89f3257b9b8640035bb1ddc1f40ee8295ad9950f5c13c156cc6800ba7be5078a8675794014af0ed71e81810cb13aa992a257b994a567a4d535c742f98cd72b9488d3e068788335885763b404464ee3dfa48b37669e9e0f2301cf926fc4911ff47010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x9fdf4397549f12f3a04d3978020e27d118e5aa24f2e42fa06dc8b23c235cb860a40f4ea7e46c4909d136ec0dbfdce6b3f1757c65704653f6590faf0021234202	1626450889000000	1627055689000000	1690127689000000	1784735689000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	413
\\xefd771c5730b08e9ff4b8a8c1f21ad08567b93af3eb370bd20dd07d660addfbd82e66e49984f4ae46c88efe5c598e93d71f10bc6ed5ff9326e847399e0a39a45	\\x00800003c30b8772f2ea5e91177608a92ff68af58fa013967f524337178cbd4a71271b77f2aef55945e45a1d6c33c134e76ebb502036cc2ab0517af30d95d1fe16465358763b1c6db0c28fefa1d94f3f1995aa3c08565b587bf3d3a9c948c2f5e8fbdff3b43c23e1b6a8175c25956a0d8eeab06cf00bd9655c2215b79c019d6f8f8ae341010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xc5b28607771cc92040ed9e6e47a0a185bdc9abfeeec66a9fdfcc2b8416eaefc53ad6997f38aea719a6d708b4c76bd62f3bfda9a977b2b4d924bfdef8d0271007	1627659889000000	1628264689000000	1691336689000000	1785944689000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	414
\\xf16fc8473a92e2fd5f1179d411bd9b22328eec2b10b3a3c05789b9b580f179d8ae8e2fb7affb20a1791427a7c0525478535bf13aa83eea31049d160679e56e1b	\\x00800003a8eba4a036c315a03d848b12361908535ea9ca9b541e02fb876e132b68347f3bc93a91c2e0bcde62d25a06fd7bf31d838399109bca0736b5eb3f305d175d0876ffd10b169cc8bd5df8fb284ae18d688026d051d98220e427fd6723e8d29694db0444f88fb4ced94c4a66c2871a069702d787ee5c87504c49f662006c2c22c20f010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x4083ad1755b12e521417e752da765ae42f948e765882c2e47cdd1ad3f92a993e178044d4b9077a0d380f8823ed68d843ae9e0f3bb42dddd0dc8866ada5bc8e04	1636727389000000	1637332189000000	1700404189000000	1795012189000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xf197980648b98397d186598ae82fadb400f12389dc486561850cb4b9763882139fda37392142e416550a5dd89eebeba7853b48d1c0714cd5081c66c7a63fd888	\\x00800003abedefbcf3a8f977dc73a541631e0d20738f01705a03b87f1b366b7403efea64b3de839dba37f072fca5d7bbbcb8b48d6ba79586d0494a8db54027c8ca7b7a72eaca70d0c836b802c81ab6ee6bef538f0e1c02f6e9afe3df997030a8caf7b1ce06d928b8296fba4bd0d8c9fdd8af5e78c421279e78e2ee199e6e2807926c83a1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xdb8d8058ccfb893cef129dffd2d92fef1b034dd326d048ca71ab7e47a82fd315997bb73941851cfb72e570133686f421593f96f1750859196936430ca1c59e09	1626450889000000	1627055689000000	1690127689000000	1784735689000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	416
\\xf35bc541652ae5aac4e3bc902827b04c55668d0e15a92cc0bc9a5f3d169fcfecdead190c715b76fcbd69e8841575a95cd44488ea27a5af2fac3556f40ffd7205	\\x00800003cab87fe586cd5cd3d342320312f1796963e31aa03be3c825aed42a001584e70e2a07e94b1448593eacb164fa1155f87d8c8108c64af9d55a71fefb7776aa388e873f19e22874439b0390109eef0d61aeb3c20a96fadee16a3433f3dd13b48bc02147e16afad4077c695683f4cebbb39e9030c20f5d8c90e6161b72af32e37ab1010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1a671fd4f228fd70f6212f320b841f0944f82c389cbc6eda65841591ef75355c89184ca83fe6a9ae6339972d7b4dd5ff9f44b909c68bc5663fd3653a00f3f307	1620405889000000	1621010689000000	1684082689000000	1778690689000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	417
\\xf41ffd2204ff1a81dc88eb56f40ce62fb527e2cbece43e1712d44e4881a498dcd4a8f11ba37825ba6fc0273af9673f340fcc5b53bbb6a17c92ce48ac4b014efc	\\x00800003bec45b7099b1185ab8ea67dd628508afa621ea36d2901b244721a4f596bfb59496aae76d36e78ecf76c2fde7c1b7d4bfdad427a3143b47b4404d677885c2791843cda8c5436417d13ba909351e539b9f3f413e0d71a01530e4585a2a6a87b2d33492dd8193767a58ec4cba0014e9acddba4aefbef80c093a6a0d3ed22cfae4b7010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x5d4db176cee853f87fa7447f584f81189853569f0c5a96e9ca75e94d6b51eb29fe8482dc94653f728e1ae027d8c68394b7449d43bbbe060c20c3e4e0c4aa1e05	1637936389000000	1638541189000000	1701613189000000	1796221189000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	418
\\xf523224618b044ee1284315e12a68a129cbde8bc2833f872f45275d5506de9eea5eab6fc47218e477ee77a7daa952c0e77e33fb19e10f7b324dabc07818f22be	\\x00800003e50d7929740d7a39109abae032a1aa2be042b5eb8323b225abe9a4e9cee87e168ab89271ff05e0788b50efa0fea3c877ba3d122a95a1321a5910bcd0bcdf9bd3e96e55a6eca73ac6f67e6e013e5ddd8700f05db273091a3f513cb925d086e3a640763e57988f9458eda2bbfcb2d8fff1bdef6e3a12907e1bf015e5910327224b010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1b3ca7f3218f28dc6d55b5343ea1fc5185eb6d5b20674c374e110a27764b9bc5975b37cad9ae525cb756fb418e2082b1c1e6b00be796db0bc1d2c3f1cce71c0f	1613151889000000	1613756689000000	1676828689000000	1771436689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	419
\\xf68b3f01ed357f1131a78d8f81bf80b170f28e3d1519f54fcd8f041e4221e5198be36bd15a6c205e5df137e2104d81a28fae55b2acf1af4cb6c3f928d8f89245	\\x00800003cdee17466cb391753d0aef29048bd0f65349ca87431167a3371abfb3ec9cfa401c67d59b54da8634f60173b620a29440ab06bb4868fe209c0f7411046d9f9fe8bc9714c0b564c5bbee4a7faeb5e850deba4dc1cacc4b8c64e4916fb39d81976a2841fb6d202def5d4d9dccde3ad32f1cdc89007c2058b811bfb1bbf16476cf97010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x22d3bf107097cfcf65e8d93f78f2d90565965105f09b1f95a7d431a0d1e7e610b68a7f8fffa23667d3083e6569cea475d3cb04f2050ba6068bc62e361ce16701	1614965389000000	1615570189000000	1678642189000000	1773250189000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	420
\\xf653ad1f43ee6d6fd48704653623f4a771c1add5e51c86ef6d07ac023a6c5c7ddde267ce3fc2cfab4a802b5de0377267ea28c5d822129bb9a3846b0d3684f64a	\\x00800003c14949507dc0eef3692d09b5689fd40a6ce5ab6d5fc3b98ec9184db4d74d279e4704a14fafb66bf0162f53b0cd8917b9fc44825af2662573fc778190af4f355cf44b4d0934e07663443008b6c6afe45368bd224671fdfbe75321b5e82219cf749254b12aeea32a3da8e3cec5d1b38908ea3edd2ec45d580feda96357d8e97bef010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3f82154e19894c658bf56304e4a0f744104b76fd12fa305296fbe62d1b9457544ccf5798c46dcb569a9a750bb7c0bbe2345a5d9b1ba8a11faf835e50590ed207	1635518389000000	1636123189000000	1699195189000000	1793803189000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	421
\\xf90b497a14b6dfe4f84006139ef058c0dff5a096a1ceca21afb03f4b332ab2f00eae792e6d75fb8765bad19d3d8079bbad08fbf248f845ed897fe809974c90a7	\\x00800003c98fa0fb5dac8a4bc55af509716e85deb0ab34cd103a35cab74d9193d05fb4ebee8a44b1fe293fdff71d9f1af257378bae24d6f535aec7284cebc3695693206eceb6a1deb6e4ef713eb75812251c134beea5401df5509c829716cf98b66f316026cb59b04c1300aeb1518d108475c8b54d6123f452bb7060eeacc3243318acbb010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x74bdc249f47b44097bb54720f191a3558fd18fcd70117ba4c8dba8bcb16e76df201b45d7af133defb99d681d4915c3abc9f5db1e8ee014eda591ca0cbce1970a	1629473389000000	1630078189000000	1693150189000000	1787758189000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	422
\\xf9333c21a6fc2065e47561a2cdc9d8c89b79db294e235f54f45e084de9fa39161b2a6aa939f262240080f1ed6fd47ea54c57d75b4afe1f7e3fbb16070ad4919b	\\x00800003a3f03aebfb276c0d093bb25fa69061b341e327f59bb172f529734a0db7c7dedb53c7adf5c21a609c1180f28856292459ab4d006d56b3f07fa1f6c7c4fd1e38c81cc0b38a0df4dd71f44508e96010bc60ff1d152223c639e88841770bda4ad2c3bd287aa9db28dd69cbe1fbb0b55d6fece69771b1602a73ef5c23b169a92ea9a9010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x3ce18b02405b90924f083d1868c218e91fda345ed33de77175f033f02367294954bca8fd5423718abc92b7747c42617cbaaf7811c524035586b08c5f25ea5e0b	1634309389000000	1634914189000000	1697986189000000	1792594189000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	423
\\xfa8767e4253654830d8fe2280d0f9ba441cbdbf82b805f3f01219124600b7db78854e900a75d240dbff1de4600102fa6d4cf963f6ba9560aa935c5b38fdb7a93	\\x0080000396fb2485a5332940b5806a667506a845f283f51a04af03cbe18b322944a77c67ba0ac73268a942613ff004a9cc6262ecf1667568f984704ffbaffd8a8feb75509951fe253ef45fda2f597d59bea16009260c16401d92af0d05ab8c65683caa9fe388e1f4f67b78e131d213b9ca9769dbbe34d2245b56e68450165848cc3a4615010001	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x874a2d607355da0c1e53060f11b144ebcf5c348e48ce6cdf54e40c04ffff8f0c9d28d4632127d3e7fb272f04a468d8fa1e7b2ce1e5396081b2a0fb27d8a9560c	1639749889000000	1640354689000000	1703426689000000	1798034689000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	1	\\xe38de3ee4ab10d7dfc857628e4b808783ec5d74a68a1f53852cf468428f137280e64a33e012d16dae6b34c08d2261223edd1a68a50650624f790f8c7d7c972ef	\\x1d207b51fd99604577e3eca15eae946394d81b99e68748b77fac61f289cfbf96f1c2bacc5e8631c3cc53c157520ba2da5bfde30b31dd1ca8cb93fcf7d7e07612	1610129423000000	1610130322000000	0	98000000	\\x37a1804cda72899b2729260ce80cea08a3aa449557a49fa8dc3fc5cd8be67cd6	\\xf6e3f700855a8e2ffafb651c6b76b5a74c01b1ff721bac45f21ca116c8b2c916	\\xeb5e5cd27f6be4d6b009b9c55b8964f4009d68ab1504aaa40ca5c449bf248de0f7afff6cbb9097d471f3fe93141b9cf9887fcb429644e16bc362807d6353aa01	\\x1bd6b571cca07ff85b6f944cd464d148f1b26a5489254260e0a6bbe9af82f3e9	\\x297e071f0100000060ce7f179c7f000007cf3e01de550000f90d00009c7f00007a0d00009c7f0000600d00009c7f0000640d00009c7f0000600b00009c7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x37a1804cda72899b2729260ce80cea08a3aa449557a49fa8dc3fc5cd8be67cd6	1	0	1610129422000000	1610129423000000	1610130322000000	1610130322000000	\\xf6e3f700855a8e2ffafb651c6b76b5a74c01b1ff721bac45f21ca116c8b2c916	\\xe38de3ee4ab10d7dfc857628e4b808783ec5d74a68a1f53852cf468428f137280e64a33e012d16dae6b34c08d2261223edd1a68a50650624f790f8c7d7c972ef	\\x1d207b51fd99604577e3eca15eae946394d81b99e68748b77fac61f289cfbf96f1c2bacc5e8631c3cc53c157520ba2da5bfde30b31dd1ca8cb93fcf7d7e07612	\\xf1cb19b08dc840443cd95bcb99c465b3c404f5b88c8f5be1a91b55bf80b64fa036e6aeb8df936522c243acb2d93dacd9766f75aeab1f2145b0e0d3c684c96f09	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"ZT0VC2EMZ0GZWFN8T5BAH1QHAGB2641PTX7NRK6ZKFV3W77Y3CFVQFHDD1GJZE7MV1H2Z2AB5722V9MV7VCRZ99NRGE8ERMDPXWZHB8"}	f	f
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
1	contenttypes	0001_initial	2021-01-08 19:09:49.891857+01
2	auth	0001_initial	2021-01-08 19:09:49.931746+01
3	app	0001_initial	2021-01-08 19:09:49.976176+01
4	contenttypes	0002_remove_content_type_name	2021-01-08 19:09:49.999229+01
5	auth	0002_alter_permission_name_max_length	2021-01-08 19:09:50.007449+01
6	auth	0003_alter_user_email_max_length	2021-01-08 19:09:50.012972+01
7	auth	0004_alter_user_username_opts	2021-01-08 19:09:50.0188+01
8	auth	0005_alter_user_last_login_null	2021-01-08 19:09:50.025673+01
9	auth	0006_require_contenttypes_0002	2021-01-08 19:09:50.0274+01
10	auth	0007_alter_validators_add_error_messages	2021-01-08 19:09:50.033271+01
11	auth	0008_alter_user_username_max_length	2021-01-08 19:09:50.046054+01
12	auth	0009_alter_user_last_name_max_length	2021-01-08 19:09:50.055993+01
13	auth	0010_alter_group_name_max_length	2021-01-08 19:09:50.067636+01
14	auth	0011_update_proxy_permissions	2021-01-08 19:09:50.077461+01
15	auth	0012_alter_user_first_name_max_length	2021-01-08 19:09:50.08489+01
16	sessions	0001_initial	2021-01-08 19:09:50.089725+01
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
1	\\x2696eef6ca7915a48cfe4d9f127fa575e352dd8822bd9d1f1fe17f1bf6b176b0	\\x0a3843bae20e6ea0f983bd4d75a5b0796ebda847b90de96e3d4dc89a5c87cee4d708014d7167c8922dc42198e10a20d65774f1ab774d633e627db5cfb337690d	1631901289000000	1639158889000000	1641578089000000
2	\\x098552659574fbc2ed0ce7f58f886bc7d0e2923f654ec0936949b695fea4ffaf	\\x7e1ef5281f7bed3271a7ab6d3ade8d73b0c2e62cf8bd174608b28ed16a121f6520a1e2d986b613acb3b141518d38f7ef99bf5ac131ef22226cd21487871f9e0b	1624643989000000	1631901589000000	1634320789000000
3	\\x2af4e090ab7a8a6213a6432c6c64d2322df2709edbc3ed1c14a29710002d6b12	\\xef3c92cebe65a19b148991ae108c760e025462c0c359babe591502afd1c86c53eda830013608bf890e6f078c4b977df9a8f909d068c450b235286292cb70e10a	1639158589000000	1646416189000000	1648835389000000
4	\\x184db54d48e8237f64cfcdfa01423a00a39bb7ed7492ebee20bb62117a94d26a	\\x2a4a92d4aff275db1a848558842b778270e3fe12e7e32fe5f994b5c32ff48beeef4d6e0e23ed6c7e9cda5e1cee2da701d9b3251a62bfb4d1a3d662c87d8bd409	1617386689000000	1624644289000000	1627063489000000
5	\\x1bd6b571cca07ff85b6f944cd464d148f1b26a5489254260e0a6bbe9af82f3e9	\\xe16f722f3994b5c598b325bc3adc00da2f095f9784a34a124c2f914c3e997611c3b7c7bb19b7e5193d82b389a458df9b5bbdfee2286b2717eb023187a9656004	1610129389000000	1617386989000000	1619806189000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x18dd9459fc12836df0bd68977628ddb0f77bc5b98c7dae0226f61e37a9c2f365	\\x7ce70ac2b4a60cab63f56db4964d9701ce349a7ca250924096b10487657cdd4c560219a8b0749d3a1ef50c2eac852f061f81698b9ef5b60957efb9ee98188266617a53b8baee0a20928c6ab90fc91cfcaa30a636f7dee0707b27b9b515e14023bbd966a4f76b9f29bfdfc0a4439abc885e9d27d7b57c92f54a68f637b6644ffd	124
2	\\x37a1804cda72899b2729260ce80cea08a3aa449557a49fa8dc3fc5cd8be67cd6	\\xa5ec9892d6043f88695df7c8b7693a0175975583bfc5e7735d05165f8e173e3727e8f7a6455e4edb14a28fd229cd3f12df58e592f3aaac4137648fbe96b554e4cb2818b441b6d6273e64fb9b85c4fa4bb5eab47e8b4a81e4eb9fac8d141d4584d9a70b4c37eeb7643d3512da7a0022d0533732a7827a5325c4c3183ee5486eac	343
3	\\xf850a82b1499f4829733bafd9485bc2bf2fa96ba2fb119b7bb608434790b8499	\\xd80321d706b89259b9823b203bc57dd3441034ca40a815523191e87703de390ea413371db04d91bcf46364a61471eb3413ee093e47ad6b7ccb7d7cac3ead5cd642e135f60b668dd71acf2f269730e78211cd112d82ffb80bd36ae62d4bdea76ad548a6dfc2e279d10fe47b1de5488fdc46189a9ba6b230ce2a94764478bffb99	301
4	\\xa75cc8f19b06a3d93b7a9caf2f6974ba0c5fa0aa114ecd099b5b06c0ff163d83	\\x6db08dba2d01673156faa9be20306c68ad945242c9d1aefd82ad53ebd253b9d80deacb74084e6c6a66cdd8021e0e03fb61c7cca494e2e1d64d78b55e7948d3ad1f615a0f1c64c4eddb53733fdef26987115bc742b7a98de207661977d92d28a0cbfddf6c79453a07070e97e39837898677f079fa2362333df196a5c8b4ab0dd3	84
5	\\x2ae77dee16af5fc7565533dddd6b2668115412273226c1d60ef5774ba9dec856	\\x9c385c5f2f63b08a5722f5bc5bfb2a673263306d83515cfb0f4b45aa5b87f34323184004a25a5ca9639e7a600a292918aed1359aee96ce3f507e1de457bc8bd6b962da70a64221bf555aca0bdfa0cd2ed2642754b993e3bd7b22fb13b5fe628af165691b93121a3da729e48b2ccec09ee21a61d75b194c47755df3af2e605999	84
6	\\x3fde23fff91659aa12821a52ea7462e6912e14d5a03d0258d142787158812dcc	\\x783e7516bbace789ef342bfdf15366a70ebfef65e61f94aa241ef03d4e425f3f05c7d9b9c0c1ebbe50c02a5fe0e34e5d2e2d5f2b152e9e9d91492dcb1d4a6d8e303b54fd72b2e975ef850379466b712fffa7904286050d5ad736c6c30224bb7d250a82690507bb56958c0b9f277c32d2419178c0b6c1da47fc4b06e1fa8fe014	84
7	\\xd00f24ba3d4173b36b4dcdc78e72ce403f5e22c82c7b317e493053420b056589	\\x4f663cb29b13564ca0ee36ef472cc89468340bc0bb93d3340844aca8f5c42baef6abf141eef0e875e76126864a4a2fb48117d77fb31d3d4b983f22e20cedf1885f03b1b54a8a8b0e3018e4f1c0fcd8416c8b119c330728770a3cbc86a86cba8ff3a05e25602f8e2b2f8376927ffc6beef6e29700496e5e0b625593499997c198	84
8	\\xec6adbb9c2440208e8433ccfd58416a653ccf6d544a271dd88c042de5ddffebb	\\x2cc1b2cdf24a66c4436822a5d2c61af25e7e11e01648185177f1f6ac62d0cf92810aca30694b9097860e3e7a2cc52315b4b1870cbc25fe1d2c7e704a0ef8591c4f9644ffa43f410278b8ac03bcdd1d954ee92602996efe95e0bdcc6a56c3c1ad316359f03f9bba49e7cb31bf9b7c76f871ce694863f5085063a5a79630c6ee6a	84
9	\\xa37d3d89af7a82c68df46d85020adbbdd35d44d88f1d60f09d3f0e1a45710ae0	\\x1d3210c9bfcd56a1b580c5cb5fce076cb92bc5c31d73094f660dc1034517b2f0dc7df58ddb4a40949e362b32d37b86a2ccca7812f90c6cc7d0dc0e998809a3c87c51ca56b1050e08547699e273b29ef4e356bff49c85986b8240f9995d7ea241607c53e0b002804cb3bffe8b77d5c662ccda2bbb24eb64bd5ffbf837debecc02	84
10	\\x83872a0326dec5d5ad5ce7af736f913a4fb718b3481961e658223f674e669cfd	\\x8dca87e6cecd5542706c1667bcc2b31510d83aeccdc88b88bf236087e7b7453dbc53151d7e4e6ee72f39067a5dc3fb59c82bc11dd730f27989942149d84b5fb656ac4c5b106497ae2b996a0ca2f460785c5ef26a1c790f56917a08378d4aae365fbdbb6ca20c63c6d2f8ccdfdd8b1d81d1164228c8b9fba325f102a91fbc8b83	84
11	\\xd84c23a3d90bc0d18300fb71ab623d41aeae22c62351ba4c67cbe29938728cf8	\\x5154aa84475a3d8d282600ec9d35024960fc451ecb7584c1a4e3800218ba8bf506c43ff1cf68d8f41980e9c55d2fa4266ca570c9d794d8835fd8647271e40791d7909ff99cb41b88f990f04fb8e106b37e7aea7bd5147b81190a33a81b174e639c3184e827782683f5eeeed2962500e468f545859d654d2c5e62f899e8b52a18	84
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x1d207b51fd99604577e3eca15eae946394d81b99e68748b77fac61f289cfbf96f1c2bacc5e8631c3cc53c157520ba2da5bfde30b31dd1ca8cb93fcf7d7e07612	\\xfe81b609d4f821fe3ea8d156a886f15416231036d74f5c4cdf9bf63e1cfe1b1fbbbe2d68612fb8f4d8622f894b29c42da69b3ed98fa535c41c87628db779f8ad	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.008-0203SFRN7TFDY	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133303332323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133303332323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22334d4737504d46584b35473441585a33584a474e58424d4d43454144473657535754334d4844565a4e48475a353245465159424633474e54534846384343453353483957324e544a314548444d505a585743354b335138574e333553375a3751545a4737433447222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303230335346524e3754464459222c2274696d657374616d70223a7b22745f6d73223a313631303132393432323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133333032323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245394a5356514e5957313459524b4b4a3452574237315344464d31424533524332575234354a4d54373133514333345638585647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225956485a45303435424137325a595156434d453650584e4e4d5836303343465a453844545248464a334a4748444a354a53344230222c226e6f6e6365223a225836505358583152543452573144524731384354394e32434d59533135503956464844314b535a4d52384444443745544b515130227d	\\xe38de3ee4ab10d7dfc857628e4b808783ec5d74a68a1f53852cf468428f137280e64a33e012d16dae6b34c08d2261223edd1a68a50650624f790f8c7d7c972ef	1610129422000000	1610133022000000	1610130322000000	t	f	taler://fulfillment-success/thank+you	
2	1	2021.008-0143ZW8VMJFZG	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133303333383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133303333383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22334d4737504d46584b35473441585a33584a474e58424d4d43454144473657535754334d4844565a4e48475a353245465159424633474e54534846384343453353483957324e544a314548444d505a585743354b335138574e333553375a3751545a4737433447222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303134335a5738564d4a465a47222c2274696d657374616d70223a7b22745f6d73223a313631303132393433383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133333033383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245394a5356514e5957313459524b4b4a3452574237315344464d31424533524332575234354a4d54373133514333345638585647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225956485a45303435424137325a595156434d453650584e4e4d5836303343465a453844545248464a334a4748444a354a53344230222c226e6f6e6365223a224e304159324e5058444b42365a464b54515a33394a585a464d4a4a533557595054364e42444e305a5a474d4e43484a3733433430227d	\\x5420f9de82e71221759eabaaf6bac8fca5e97f272c47cba2f57017d84f9a686c6f280339b8f627b4ead95d8a98ce2d70877b863d5b2f3254f148786433a3e094	1610129438000000	1610133038000000	1610130338000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1610129423000000	\\x37a1804cda72899b2729260ce80cea08a3aa449557a49fa8dc3fc5cd8be67cd6	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	5	\\xeb5e5cd27f6be4d6b009b9c55b8964f4009d68ab1504aaa40ca5c449bf248de0f7afff6cbb9097d471f3fe93141b9cf9887fcb429644e16bc362807d6353aa01	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2696eef6ca7915a48cfe4d9f127fa575e352dd8822bd9d1f1fe17f1bf6b176b0	1631901289000000	1639158889000000	1641578089000000	\\x0a3843bae20e6ea0f983bd4d75a5b0796ebda847b90de96e3d4dc89a5c87cee4d708014d7167c8922dc42198e10a20d65774f1ab774d633e627db5cfb337690d
2	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x098552659574fbc2ed0ce7f58f886bc7d0e2923f654ec0936949b695fea4ffaf	1624643989000000	1631901589000000	1634320789000000	\\x7e1ef5281f7bed3271a7ab6d3ade8d73b0c2e62cf8bd174608b28ed16a121f6520a1e2d986b613acb3b141518d38f7ef99bf5ac131ef22226cd21487871f9e0b
3	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x2af4e090ab7a8a6213a6432c6c64d2322df2709edbc3ed1c14a29710002d6b12	1639158589000000	1646416189000000	1648835389000000	\\xef3c92cebe65a19b148991ae108c760e025462c0c359babe591502afd1c86c53eda830013608bf890e6f078c4b977df9a8f909d068c450b235286292cb70e10a
4	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x184db54d48e8237f64cfcdfa01423a00a39bb7ed7492ebee20bb62117a94d26a	1617386689000000	1624644289000000	1627063489000000	\\x2a4a92d4aff275db1a848558842b778270e3fe12e7e32fe5f994b5c32ff48beeef4d6e0e23ed6c7e9cda5e1cee2da701d9b3251a62bfb4d1a3d662c87d8bd409
5	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\x1bd6b571cca07ff85b6f944cd464d148f1b26a5489254260e0a6bbe9af82f3e9	1610129389000000	1617386989000000	1619806189000000	\\xe16f722f3994b5c598b325bc3adc00da2f095f9784a34a124c2f914c3e997611c3b7c7bb19b7e5193d82b389a458df9b5bbdfee2286b2717eb023187a9656004
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x72659ddebee049ec4e722638b3872d7d02b70f0c173042ca9a3847760c9b4777	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x69eef06ec776a9fdb74728faeee627e37670635d2d94d7c6c9d3c2ee342ab28d6071723b192f99034e7779cd066f1b08f7bd83602864b47ff55895197d390d00
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xf6e3f700855a8e2ffafb651c6b76b5a74c01b1ff721bac45f21ca116c8b2c916	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xffaa41dba6c85d1dd8da424b3810e32eefb0170955c55a07731b5e12a214598a	1
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
2	1	2021.008-0143ZW8VMJFZG	\\x47d89ddd8dfbcdfb24d9683d6eba8357	\\xc1322a8c0cba7fcfdeabad388bc8061b7f948a91819e12d2230a359f8ccf281794e4e2e886c6720d04967e3c49f9b325ca2ece4cc2f6cecaeb8328cebeeaa637	1610133038000000	1610129438000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133303333383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133303333383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22334d4737504d46584b35473441585a33584a474e58424d4d43454144473657535754334d4844565a4e48475a353245465159424633474e54534846384343453353483957324e544a314548444d505a585743354b335138574e333553375a3751545a4737433447222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303134335a5738564d4a465a47222c2274696d657374616d70223a7b22745f6d73223a313631303132393433383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133333033383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245394a5356514e5957313459524b4b4a3452574237315344464d31424533524332575234354a4d54373133514333345638585647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225956485a45303435424137325a595156434d453650584e4e4d5836303343465a453844545248464a334a4748444a354a53344230227d
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
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
1	\\x18dd9459fc12836df0bd68977628ddb0f77bc5b98c7dae0226f61e37a9c2f365	\\x25dc32399a761894afa7121a93545f0a3ef7a5f939e131d82f4a35d1ad3f09811f8881c680d0b1b0c7abd239ab68c5f9e9256becf54e1e2c15eae242c5a35608	\\x9a8a1b27a815ed4fc6a84ba03189f24062e96f7b0e6359dc7e2e419cf170d017	2	0	1610129420000000	\\xffed31beaa7fae0c96b4dc3637960a5e761eccda663ba54c4ece23b81e68a50d9dd1c0d42c1f0f15683f7811b28ed31fd3b761be35616e8ff63d62802d88f139
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\xa75cc8f19b06a3d93b7a9caf2f6974ba0c5fa0aa114ecd099b5b06c0ff163d83	\\xe7bf6f9fb408382934d330c4a146fad039390893f29b006a9bc808e5405bd69d3cc9ee7e679c382d57c1c4c229720101b7f992c92fbd3c5ea5b13e9d83d9040d	\\xeae36b59a4dadcaf821bdc36bf262aadfb4adfaf24ed2ba6e8e45ded834ae975	0	10000000	1610734234000000	\\xee30637250e57c36c9434c6487851a7c5890af58d10d2791592c9bd3e3ed060ed6d3ace0c9fd5e902bb06c40fceccf1e519448b24690ed127e2856547a5cde38
2	\\x2ae77dee16af5fc7565533dddd6b2668115412273226c1d60ef5774ba9dec856	\\x0155d2bfeb5a7436c089c8d1f62b9f11d2a6d814026ea2ec193a61b5f57d24615094f6de7ff7c8c6eaf694c47857f8b98a16bdb1febe8dad132c62487f01ec05	\\x39b372a32eb0a5d6f1e67d136436cc76893e1849597a83e0f5c73726f3fba368	0	10000000	1610734234000000	\\xd9c28b513d6f180de5d88f5fab182f40e4505634d4485452c1c9143a40bb9b5cab1d374d1dbe30ad04943b7e8c7932e9fd7082e3917d4a1d3bb623c68f90f832
3	\\x3fde23fff91659aa12821a52ea7462e6912e14d5a03d0258d142787158812dcc	\\x4e00f5b20ff12711bb6ef638656c1d8c7113672c7c5993498fae6bf34d8fb2504c1fa1d388cc9702c23a87bc1ebf78cae018948bc40538ceebc130adec974c02	\\x5aa17fbeb85764a910e67ac4071eab91c93d58504efe84f374a0a6ebef5afae1	0	10000000	1610734234000000	\\xd9d945618ba54ce9259314dcbc7662e5208621945b125271ac7c528d46999dee7a57cd374705cbbf603992731d904a40e3dc53d86fec612b2e4ce271850a6aa0
4	\\xd00f24ba3d4173b36b4dcdc78e72ce403f5e22c82c7b317e493053420b056589	\\xaefbb88753bb358dce50af19a6b6702978d2b7f2b87cf5124cb0e1490d32e63121e3ec7bac14dcc2292f37821f5003e0dd930c18051241b896d18dcb1349010d	\\x2e5dbefc7ccab1998d1d72c57405c81a6aee21aa47f34002faa5fa1de52c62f1	0	10000000	1610734234000000	\\x50e6d7b17bbe7cdbbd8ad2eea2f23045dd9fbae4926f697585f8359be2e2eabdcbdbbb19b61a2926733789abb113ecb21ebfeab4d41f6366b86756a0bc2642ea
5	\\xec6adbb9c2440208e8433ccfd58416a653ccf6d544a271dd88c042de5ddffebb	\\x2b3ede82ba2b8bdb477e20c3ca8f595f81b00192de03d8c56bb3c9da018a9ac057e59e28008c95925eda16b9499cf26334e77b07ee465002eb42b6ce724f8304	\\xf9faa85c8c733910c5c5a62e6298369662db5a54e37254c64e12567ed40a3289	0	10000000	1610734234000000	\\xf474d5748926dafb02300b16dfbf131e3b5e30233749cad083fc84b69da2461a63f90250d626ed233dfa1d87ffd0c68bebfc46531407d8811b8fd24ec117b176
6	\\xa37d3d89af7a82c68df46d85020adbbdd35d44d88f1d60f09d3f0e1a45710ae0	\\x34476b8145b13a4683af2172777f3cb6e98946b65abec134c51c0fc1f4ed1b92e28b1bcddff763fef7dd06ef63f2043374dc6dead1fda031520b656189e81a0a	\\xfbd164b9222de9cd784eb629780301eee401ade96b79ffbbd72696a2c99eb622	0	10000000	1610734234000000	\\xbe3e3bb07297a395192d2b75d6087a595b59ca22f1a3444441aef2c0314cd764233a215d57f0c4bd2dda0d746788a393f43f077aaae395a79faf863aa68d59b6
7	\\x83872a0326dec5d5ad5ce7af736f913a4fb718b3481961e658223f674e669cfd	\\x199f08a075bd1d2c4ffe602184f95ebcf0dd292e8c347aec6c067c8c52b3935f3c9b0a9803a0765a18fae6415be692dcb04660e53d7464ef8d1c2b96429a6c00	\\x068394bac144e099b88745c73094bbc646be98b0dfca9a34e64e4a38fb9758a4	0	10000000	1610734234000000	\\x8a4da64bbaa892f58d107646987caf8340e5a7e8b68fc9aa92944a2e94c52eac59994d5e3041f212aacda32613b7ab63e784149d490f9ef26066ca30173946b0
8	\\xd84c23a3d90bc0d18300fb71ab623d41aeae22c62351ba4c67cbe29938728cf8	\\x890e04b188628fd47b1f21b067303d9362610ad001074fd6ce6b9e08132ca921a5024814a66ac75e893217da0b124cfb196ac7762cadb4e37aaa886eaeb26c0a	\\xb2ee7768ec69bb8b346e421f4d77d7daf11995d3acac69bbf0c68593d581b092	0	10000000	1610734234000000	\\xed4f1edde83c47bd988f124d140a1b2365d3cd22277da32aedc331ef1f44f31c3c98425bf4dbd5c2d0dd74ec87311356f799797873e479c0cbadb2dae6c0299d
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	\\xf850a82b1499f4829733bafd9485bc2bf2fa96ba2fb119b7bb608434790b8499	\\x8d6b50f5faa2fc8eb33dcfa104502ebf65f5dfcb02d759ab7413bdec53c19f5dbcf9c0bcb0389a3f1991d614f1e78dd76d06105e7b8b26475ad354744c82ed09	5	0	2
2	\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	\\xf850a82b1499f4829733bafd9485bc2bf2fa96ba2fb119b7bb608434790b8499	\\x6a21704b40cc9b474b139b5359840c6a2ebf1d96ed8c25e655ccfead4cb154e5c8d9896b31b49cbf8da95df68f9d034b4c9f813ce78f8ebc0a361975a3472609	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial) FROM stdin;
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	0	\\xee09f43a698cc2465b88e3be373e8576c94b4185dc55cf42dd7b8af0d240dbdf94d429b542abf307c87fbce9ef3c922a648f852a7c4fbcb210a4f7fdbd54ba0f	\\x7b75c050c795ae62b722f77f62538ac26fc73b974fdc16638b971af8512d108f503240e510e4095155e6654731611c4db79418ae02e01755810032dafb536d93280cc95c59d7ac96c66d028630b988db31a2a7e0f6bc0d71088e473ef59566e5ff601a38ff99d5c5902bd46a9e6ff850d0cea9cd89acd80541f2931558c1633a	\\x34b1499a51a1779e6c1c6ff1e6ce57a8a4af831accff31e526fe67e64ef5c1acbef824cff496f47c920eb824a5096c7753367dcdaa9b4c6bb7cab36926a6bc74	\\x8e0c67c7dea9cbde01ee2518a7daed0a15c60c0a9fa14ff20f212b47dd0b8e19316496a3a95b6e4cb8b1190451262a89c7c8631d7b99dde96d9bb72cb79cf74045add93d7885f9b91edd5a7e2f69de25fc6fa2af2f5b10ba34ed49e9dbd5fe521d97e074599531f9719c7df0d82f4a0a5b030f0774a169aeb8d2ee4c86c33ebb	1	273
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	1	\\xe7a1870d799401dffeeb196054bd7a6ef57b61b1d1073aa9978ccf21878edaf6b79402db80bf59018cd5fcec6647475449c26ec02bda9074202acee4c8cae20f	\\x13f4bf29fd6cb2cdf29e8496442cd8979067dab6d440392936aef19f2ccdbdfa74fe2f17cb26c357bad407d48548015c1717304abe25cbf276d961c337373e760c5dcadf0faa699a3483a907090af7b84656483bc883df8e67f66c47be74fdded91ab7c2190b94c0484dd9a0e5a252966c8408f1c8e7816a1f1cd91d2fc2b892	\\xee30637250e57c36c9434c6487851a7c5890af58d10d2791592c9bd3e3ed060ed6d3ace0c9fd5e902bb06c40fceccf1e519448b24690ed127e2856547a5cde38	\\x7a24d0af3687ac0c2a15651717f8ad9bfba259a41cc01b94fd07ba7c09b039c4d82026e9f2747873d1d1686ac762c6d0ee50de1ddb2964ba3253126aca9c80be8f1dcb4ae267a9ebb32457dc1c84a396f451eb5d27ee82569536eaba2d19de9376aae81045c87eb2725b99b6f8947e1d1452f1ad54416478e5c293926df11e44	2	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	2	\\xa1fa47a0e26f8287c54848544cfb90df6031f8023790375003c931aae8003bf8d8ea210769effb9121d16dd05912c8c8101ca65a8376d66f31d949a766445f0f	\\x825fa5a9f0001a60f6a6c0d396679ba36abb65ea538fd592a73d8be9b9a67da7a83242999b88e9d4994c2fe930bc6524b1de1eb92db8ffb0493cd26b228e41fc9e3560052f6483c6e508c7fd65fe02c21650d7d749e62dffa62b0fa28684f5a9bf6b578619c2b296f06b93c1532f1ac23b7cbd0f35537bbd2dd710c2027f54fd	\\xd9c28b513d6f180de5d88f5fab182f40e4505634d4485452c1c9143a40bb9b5cab1d374d1dbe30ad04943b7e8c7932e9fd7082e3917d4a1d3bb623c68f90f832	\\x0fc3713adf6ff42440a67433b98d968489f12ccac061044dc8dcb13d4214d140205820beab86a41bf6ee349897a6ebf5e584637a6409647de298fd19e2e76f5b55a15120f853d4e7f230254241ec37a6fd76c3894ebd03c466d2dc0f6155599786ef57a01e46c9b15baad43decf9b5a507bcc44ba61f665afe0e444c0be627cc	3	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	3	\\xb788d0bf24a79094d44d607e0453db52f1d67b1741db07c2cb1fc765998957acb060594f0db04a103a02f836935741a42826d5b2414bc5f6d7ca019e6a01310f	\\x898140f6ece11b3f0c829753d14ccfff1bac7798201e46621861d4145117cc13d6e447529df7af199e947a17474ff8eac9adadbb47c08211ef781a2d1ef346bb33209d9eea3586c9c34c3d99b535ae8893471922c79cee14780417fc3f9081e48f8d80e080a8fd431109d78e640ff506e70a2bd2d4e11715900143ab794f6388	\\x50e6d7b17bbe7cdbbd8ad2eea2f23045dd9fbae4926f697585f8359be2e2eabdcbdbbb19b61a2926733789abb113ecb21ebfeab4d41f6366b86756a0bc2642ea	\\x3b5e3df07dc3861ac28f5cc51e4651395505c935d08e980a7e34291660099917d1cd89a363010ebdd1e7f5dfcc37f1fd550f9c6b04112ff355f6fe531fa67ed16c35cf6b3e085227442f2371f9f638ca71724fa736d986fe0726e4dba6d59173ee9018ade0ab93156ad9b8bfe17d0b7848b71b48310a2842b77b64cd7783a46a	4	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	4	\\x2617bc90359472aac993cb434695c0b1f8b567ad5ef1e53dff8004a13ed4dfbe60059084a4bd948285ea7c250d4f17202e30c51bc771d2d7b59a78f59123c100	\\x697da8c5baf7485583047b5424be862c4fb01bed507af6721b93a2e4bc4dce12ec44ed0eab760bb9b739dc8106af1da7d0a8368bf4912fae029727565b2c0a13de9478cc5ab23c383f9e131f6872ea5aa7330dd643498df41a7eb1e1221aff6936bbc26f4249b76972ef591213ab5aad2b13c343662febee131f6642fc3a36ba	\\x8a4da64bbaa892f58d107646987caf8340e5a7e8b68fc9aa92944a2e94c52eac59994d5e3041f212aacda32613b7ab63e784149d490f9ef26066ca30173946b0	\\x7036ab457b77497ba20b3a60268e6798f848f4c6a120c73b884d565e56ff5be63515ffa4bdc0575cef78701878b202493a0332fed5415abd8e90febc7c4922a028ab9e424a7768a1d597513b86a8e374cccd58d59971e223d0fbac1fc6add9a8cc07172fd851dc15f0b723dd53d25ffb09823da86e395c4dd6cfd6ae80109b74	5	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	5	\\xcdea003bedfa6ae5105c08e853bb3ca864b86a24b069fc2703b9605a1b41065e38f19a9c230776055752ef6cc46fbea6bf7d5c5dd63ce43db8e4a29bfadfc50c	\\x40153d65e80cb55a4c603e632c9614f045262bd98ae4b42470e09c8334929be91fbc4424df10b87c473160ee3bcac82dc5acd1c20167f5a6c04b9303955dcc14d53e0dab5436f03f7e3099d78046b3bd1c41fad1d400b4df2af75d3aa8a56ca5cced607fdf8628c5f7b4c5e4933bcb9602bc667bbfc896bfb94c2d4f4a099140	\\xbe3e3bb07297a395192d2b75d6087a595b59ca22f1a3444441aef2c0314cd764233a215d57f0c4bd2dda0d746788a393f43f077aaae395a79faf863aa68d59b6	\\x6d66fa77c5efdb677c2d3dbc05efa662334746ca914d2d0162233f88c52cad18135cde1f4a74d43f13f571096828098ef3353ef79623b08f68a1f0f11f13d6bbb73dafa6b5f6588173dccff51db596bbfecfe47f06d9ade83188626e411321bf4c51cb45d8c7d0da54a25f848c8078b7f6a210e37dd22b348aa4101872530663	6	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	6	\\xa0b0930cde90bf97f3890da183041c5e64af0cf14517537bad4552a96104c69585d822875aab765334ce322c3338421b9b84b209673f014cf33f6077c448da0f	\\x7242f5ea42401cb49e92ba115f8cce590391037a0ff7510464e1acbb122e9be04a03d73982f46a93b966aca1aae117a8f526287de562723fa561be24e627812060e66157d2c1f5f9738e4764a8ec9860e24ee9c223e4170158589159878112c351c0a72303534029fa37d97e4ee72ef735d0533ef911fc46933dd993bd663dd1	\\xd9d945618ba54ce9259314dcbc7662e5208621945b125271ac7c528d46999dee7a57cd374705cbbf603992731d904a40e3dc53d86fec612b2e4ce271850a6aa0	\\x3ddf653e4db973ac12809513ec283da6c5ae0cdd5b83a29a1ee1bfac9a1ff766543d4f58990fad12a9bfca60fab1298f3893c80815a95520c0a6594a83156ce0d497192ce985f616f73fe49d299adaeed90cb521c24bb15b85630bf985a13c7ae1b90409b8b6ac2f6db386a1c01295df1bdb6ed9eeb3905f618c68c9c480d54d	7	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	7	\\x3aa8fcc0cf93e9b5bfa8557f7c5e4b04d53b62666cb3362b1b0816904aab3cca2a79ec2d815eec1d9f534148d178dae8a80fbafe7b59c4d06b6462a7099eb404	\\x9804c2805da0d17ec6bd38ad756c9551dba59ef45cb55b226051e1a0436d3d022ce2bac6810b2944d82fb9ed0710fb5062b6632c072f4a0d963a8adf27d4124378d554596cbe02824005245fd69586f4ad8c97249bca241e6068c5c3e084ab11b3157f3470a34807d6b96f96b31b606d5ab46ef995187998f6ce4c9457cf97a9	\\xf474d5748926dafb02300b16dfbf131e3b5e30233749cad083fc84b69da2461a63f90250d626ed233dfa1d87ffd0c68bebfc46531407d8811b8fd24ec117b176	\\x43be940bec40601985adcf8abe73634f9faff07bad84829de27e60c69d45d7b01106752d70d54f98478b0db78cbb11e6b81beeda1d54d216987441f1e11c45f52ca0e55fc7a9d3391450d178638d7235f4bdd034fd0fa8949b87ff1d97549a183b4058a703a185418a6d831129f62d6c0f070e927429c4209831594353e29ceb	8	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	8	\\x4f9bddc0c469696928a71632fdaa543bea1af0c232e3e28bc377ecddabe151b8116d813c3994c0f61f60e2940faaa9bd8345a020490cbe0b0c6a8ccf8e9c0401	\\x83baece77d42e5581a146f8852c32d9d796075897d1376e070fe8557f1665fd8635a49caffdaccdfb2389402d2aa19f1bfb19bd371a385b91e94f467f41e42b039aea840e93213ccc3e52100c377c0570d78f7b8368f34e2489ba934629b4556ed9ce6cff9e0af6d3a578677967eb704761baa8eacdae8929e67a9eba02d549b	\\xed4f1edde83c47bd988f124d140a1b2365d3cd22277da32aedc331ef1f44f31c3c98425bf4dbd5c2d0dd74ec87311356f799797873e479c0cbadb2dae6c0299d	\\x1f7a1371397d3443f57eee4691e36d2560282d8df255124280265baef2fe3376010c0d3f1bf206b1115bee40a97d2f5ce78c8ec69d3ae9735cb013a66ff3cb501ecae6b8d022d30def1e5931423bb751bd33410469cfe83d6492f6bb4a6517930ecdf733477e9da193ccaf64c14ec4a18e352567e7f3ceefa8f209bbdec8f6d2	9	84
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	9	\\x96aff1c8f5433764ccc6f9e12b77108d206ef7c704c26da0d262f2c00369f3b9957eca808cf5a646c3e29f7fa62452ba8bda67a8c5ae30da4b96508774d5d50e	\\x5933b5068e5a9544968bae206fb231ea1a67ecb4881c0eda92353902038fea7ff935cd9cdd09d14462ddcf8a60b38dd1a601ace5ff3d2f3ae66641added6cade9aef425e67bd7dca985e34982b3c14f0e0d4a4961287a17be0848619b310260ea6a9aefd41e7bc54b170c22d92a675f30000955c1916b5351a67dd4ec49f3a2f	\\xbbc0e182b5cd8fcd592b46e818563e89c96e2de9198ca0d62fb7de4553229e370a4ac16cbb89887e7524371e22f8f008710f4ad7681cb2cde1c5ebd559988fda	\\x92a182c85e37cbf4493bf7fbcf986df66e6a05c48a299f1c1502704f63e5497bab1103204a83850aae8a6b4c61662dd48f5585f89c762b76f2c0a98a1e308ad815860d0fd34c98df63d0006594a9cdbc0e1af0634b5433882617a485c4200fddab9083e0bf406ba117731f29cb27a6c7956a9bf1e9b8574ae1891eed13308b99	10	234
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	10	\\xbc4fbc196c7024e63893b0e9e4cef53518cb53e4fef3b19f36825c72948c9a4acb6ba38d98417869f36cb2ef60b92245b44180ce45b0c38a9d76707be313020b	\\x915ab3e7244752d8fe49e5a12f70c6eba2c2c7b878a7b1c9f862b8a9ae9bca5ba0c412761cf995b6316db826b2529d12cfd577cc4a432bcae1a732f442c3eac8ccd87c39caecf14d43a0277f652c3b8d12ffd6400bcb4833f24924ff84d6dccd37c928b55f34e6dae9df4b3812b2250274b95cd438432fa74b338a8e6473b93b	\\xf37a410c57ca2677c68c9180ba4706ea0ead72239de42494790f3be1a6334d1552a4fd97ae74a652607d5168f003891b4245e685e4c8140d34b501448a314132	\\x1bf616cc16afae8f32ff1bd34afa36b16b57a7b9e3748d4f1b70ead7174933d630c97ed85af4cea8c8cd9ccfd05723dfeaa0f6689bc851a51167c4776f52bbddb56a8aeee430aedeb1b1420a76e8d5d49b1f02d61fa5c89fd9ed0e9af131bc334b6bd311f1a6ab8acbe47904f5f30dea4b195b7daeecff2506179517da70311c	11	234
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	11	\\xe26d4adde86839d58c897eec3432d962ba447ff9229b736d990f85075f211479ae63d64520a7fc8e3b17684eeec4757115dd811c0f99d847c2bc858fc04ed30a	\\x0d8da5040bc670c517cf7c0b0054d20e0ed2faa9f956d7ed4ab2ce235c638686d20fb02fa5d41299eb64e4ca1694e63fb7bcdecf48ef5af2115045c2d0038cbfe3679b2dca3c238c7f4d6a1c76ba4573fe3458ddf3d0e4110f9b359ab6e80ed22851eb3cd49e8f4b7a2cc104f3bdcf142fe4db529e32c803e7e9823ec13de572	\\xee708b56c71de4f0b185ea47b12a81a44d4072449451afc55064d0772105f266715b46f07b4f6885339b10390a7992359452183f15388d23aa3bebbd5e838919	\\x0de8d38b6442fa542534640ba2e4ddd38836d236abcfa428152306ecc40942a9b9c2628072cf78bec524527fcd7bd7d88ed2c3c136413ae48c10f0b4edbee86fecb81c6c7f675571afca3a386cd7fa78ef5becfe95794f328ccd5a66eb54c46b65742e976aca0eedcac3e82bae3a2d77ebf68d774f062e644f79d57756935973	12	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	0	\\xca98edbe7098f6fff95f84f38f0a46f2a57a24e7e12bab24330c5e4c4e18a82b8408cdbf064cefc981167ece711e77fbd6724e816ce55c21bb583465e586850c	\\x97c7eb9e8d87121dc34c051e4c15fbe6b981668a34335e8059f70076227bf45f1b92e1f102cc054a827ae5ae6fb5fd291fbc406497790e967a17d374d3891e74e4ad5493990af85edc5fb5a7a614babc44a53ae8df7b9ba19222a079b9403488b1def18264d08ec81192a98e35b82b6b96bf3468b7e4de83f890d08ce7bbe049	\\x60c4a6206bd983acd942151e69e03b758ab4db4e5bb998e35bbcf7004ec123e6dd6bd383188d4431652d7dcbd96b2dc36bb4df381d14cf1fbec45699f9e8fd88	\\x71adf38d6573fcfc8fc16d0b220d0a23b8c05806961d8740412c065adcca154d84349ef83fef4ec35bafe26f964d96f4ce2733870c5cffdd371ffbbdffb99ffa13f1003ef24ccdcbb0e41cf41abcdb9c6e7447c8a8252e8c86d8cd8c8b5db5d0f1dd36d428cf7b47a07d34a412a775bac229e6ec28d378c3aba91740628897e8	13	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	1	\\x4be3c52a628d185f659ed424c2747ce566aeeb58803b4f163ccfe40df7fdd2914e54de605d88b8d0f19e83fc8810f9b89a3f3f7680704546e5256c111585b100	\\x4e9a09c36ddb0eb46ff905359df250a54e6495f20d1cd642f137d79ab82bbb01bc5f248850e36877c6b5437d43db806e4eaeb0eb4c6d94f9c541abac3d5f05a468f8fb0c42af0a3337a8775d2dd3cad9bc6b6d6d2dd7bdf0afd5a3b9cb93ae857cda2ab1a6b0a27dfad1be01d9aace09ecedde49cb1ca9c415a66c2f2f6aabfb	\\x1d97b14cb342b40f14409315bc998f04befc6ab68ba2b9498916a0ddc1c4b70feb4546206fb8f265e7b228fce68a67d25fc3fafbdd8219140ac59e886fa20825	\\x25b30133872eb9d01cf5ac0d42b6e7450e952b447f329704727c97343e2d421ea27faba05c3641b35ba357fa5fce127e3f9927fd18b16592811db26090f0e772acfa35b8be971cbca7ffa69d2b51d9afa6de884781bcd8c9f1f8a8e9d687a425feaa9da021dddbfa4a88f05bbf3dd7c05504ad3c30227ef0f06c555fa0754451	14	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	2	\\x2f3300a5416e9928c90fffef8fe57126c1ed425d43a4b587626f09194841fe9938f699bab99e7e9b5cc091b216eb701d8b27f74384d59a4b60ee8170aa6acf0c	\\x545dc0229105350e371231bbacaf748a290c27c76c43726a58f3e3cdf1ce558495370babf0f8797803a4856dd0546a3e036ae415253db6bc62050ed7f0708e2a75e278c6dcc88741ee73fec011b5bf488562fd9093bf544fd80374bb7f123e480def325b3ca7f772ca8815c23fa180745da391577d9129fa82e83b8d2aa834fc	\\x7641b7d6443ac5cb41e62a7efb9bac7e67bece36de690db17105b680eb4db9f04d98abc45467512fadabe4f565664ed8695d0fe36822cd7269d5cfc1325ec5af	\\xa2853fb6ffa400bc5517a316aaf83bced3ac9f26416a39406fac4e9996debdbf8e8593c135ad202188654989b8cfa01755142b227e36559fc0301c6281301d0bcf9fcf5dd507f0c65120c8f15a79caf074c1a97a82fadc7f95b699e9c48826481d85c3cf2481fb885f1d955ce813ca73d3da2ac06647ac29762c3d5b0e9e001f	15	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	3	\\x79cd0650742e57e8044d0a379ec6edad574cdef2ce62a04811a7808d1eaa521419cf5e5ca5fd61bf602798c1e1a213ef639ea8b72ff9d24bc86adfd62ca5330b	\\x0b51ce55cbdedfb37bf839695c85126946384941d2c325e6ef310bf6192345f2102114e4362040cce079707d7662ea58eed68914d4f379382e9bc013e12520fed952fa4b33abcdd2bf14f99b3c57bf07007e4621394fedf2c05242537e5570e15c42396f790f90f07efc60c21de2d88738811e9d8f5b2a5059e547c84f15295c	\\x5035b030ab101e4f41854c408d4c36f0de7b74b13f3c0cc8d593f839e5c97bbc7f7318ea9d54124dd0b3af50efd29cc631d52a874310957522ffec693d8baa9b	\\x6aa41396688293ef0dc3a61613dff3de99d127a4578e78001909ba22096257995538cf424ea72969442c9e47999f8b94b69801397ba9d43e305356e6a04f41414d8d003a9ce1e0c020c4a3ef533f27144a8d174709586b56af068c5b8c5f31060e47b7249f566783ebc00584e330883a9dfcc57fa44283be24f036539776c97c	16	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	4	\\xc07fdbb189569373624802fcd26a7952a547fff7a5931f0e009cf1a8868577f861d48e77a7dfc28ab257bfe9c28d1c93f3ba2cc379157c6d0e328dd622526808	\\xb5401a231337ef31bc5810d6c0db919ba4283cd59a11dfcdba91357e3b6a1c84e29b762557dc7971e3d90307f9d9be9286f9e9cc016d398a8b350b099153ee92df2c44548ada6cf2ef40cbf24f64663faf3ebb26127e6534224c956deeddb0cf137bca30048af27c8ffca748f86d4e31d3e0ba278fda6478d9809ac94a21a98b	\\x465c2133f9b63532757f7fc47b1e08c5939e6c9c3d6ac721ee79037191a03de7de10ddc84f6baf8b02a1c9c1a312d714987cd7cb0e6401197ffc64b73c8e7b44	\\x0637a10aaee8cd50a23c8db050ed401ee65bd2bf93e736da9a14bc4a895a823c22da7cc56a3c410f26d34ae2dead1848660de2bf73c5ccf939927f4579be48cc6a8af082f0a162564574d552e0802b3bdada0dc4f12c31f3ebbc548d559f0a583f4bc9f54bd5e5058593af9d482894da20b485561a5a5a3712ec7426aa929a04	17	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	5	\\x57800972424a4b0ad33ed0df0dd6c7885a89a9cd991e88c4ea3940091d5c7add29f62b2797ce2a9c08cb14b6d09c278188f0a46bddb6497862ec791e22813001	\\xae6c6da6e9466d2d4f00ecf5ddacaad6c46cc864f79d34801b4944fb2555b27562731beb466b2de9a4814864fd82cbc32f04d973cd42827ec11cb954b6834261d23c89bacb12e46236f0c24549459292b38d8ad469b196ca139196c9b559a47f32e4d9a0053326da2493c1a0bf81b3c60e9c6fb9bdee2f67ac09af682ee46f50	\\x47fdfbc7e42eee8fe578e072a84ed0bce83153808b463c2e239a4b1e24e4fca1c1feabfdc26e386991330520d7050d60de20b5ff76c66ef5f1908da6425c25b5	\\xbac037e2cdf3e81567b31e8d4229e8390f95fe22113c36e4c123c58275a886d54bde85ea275b0c41f687a25e1c78652328b3884c7fcc1b01a087462e960597c59eafe502d7122609629544d3608a41eaf09d90501cd81a26f4efeb8cebe3a49879ba794367fdc0180c0e961a4a26d06335938f6e250e3a6eeccf517192f5e4cc	18	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	6	\\xb3a751f3b35490ca662b8113770a42b9ba077eee533d35df01a7183a50ad176eeda473dd63af3519b4a92fe3e2e4d6b23cf1c9231768fca40627482d93561d06	\\xb85affa2977dbdf3ef48ad1c2513ae43bbb020a5a11ae4c02fd06727481b2a7e4082430e6e9fa6bd1d471cbc4f4ec3c3bd35d161817806a1d4c492d8e209ae3b0c9a8a9fc23f18fd3b65af4c48afcf45ff0a11ecdc3b07deba6708bf4d211947056b05d7f974f0d5c039fe99fb7eeb1f09451078de407828828de1575b3c58f6	\\x62fad0a6591c7f6a3b19b5a6100211337eada97ebfc9da7d31575de6ab0fc83e00fb5d896dd3a6bb5bba3b8138e1d96b51798f81e445552a2cd1152b370fd2e4	\\x9e5c25558c0c0ffd121c020bf1ed6341ec0fdd940098f742dda0061426efbf917683eed255b0acc8106a1b274cd0d286cfb34d833b7c08d7efbde553468a5902c36a6006098d1492f0f3adfbc122864b11bb97fb7b3041a68cd5e593be632873fdde86f2f547568095d42ff9679364200315970e0009c1088818df0c22aa2de5	19	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	7	\\x10953ce69ff2c6beb631e2f4deb688fa0082a3e758cb1761126537be2ff8264bed579ea8d32eb2f2105bb0037e57a86579a1a29c9663e7b0466366895154cc09	\\x9b8b7329a31eeb7f814901fd4ed6234b8ea1055be3b44a0a0e5a90e0da093c353436a59a20ee3bff40584cc402081a77d4ac71f2c7ff0adfb365508968ff4615d01502013c5cd8d1710464c6eccc25869947d9ae29e82a65bb83b743a47afff9c774463fcf437feab600d089cfed03e82e27b23ee522be8170385a16e89ceec1	\\x385f038ee67a85ce7f03242a8efe2a04bae3f2d8918e2e0ba759e663380a318c8363e76744680d4d9856ab870e87f874ed4f75513d3b54c956bb112adb4c8a6a	\\xbcfbf3d1662aea74bb29cf907ee3ba04f3067537b3b089e3060aee285acc03532070667c28ea69bc7af2c9cb364f61717868f2e58e14a36349960924e4af43a49a8b149d82157ea38262f15919aaaf10e5bd8e5264570c843ec75d78937ca326803e609ab502061257c4fa5a0c1367272548da893f6f044536374a5badd23d98	20	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	8	\\x1c5823d731b3ab0e4f240911dc480f45c0004c9af1b70051cec3f314cc04b765ae5190ebff7c7dd9caafddf1ac4ccf25e4271bf2ea02018d3428daf5b6b31f0c	\\x3a8f81ab00f9aaf73d40ac25744aa4195d1ff4996362bbf1365410af89e4f411f467bbc79f27166e57f7e5643f8fb579f81b12651a8d8e4a0259a3a8673c25e6aac7e97aa493d6504feb4ace8eedc0b02d370bc83924fa4ace8cb8aa029ba981933248e1c31915d2d5b4f855b50eb50dfd87b379099db6fe2f450ca7295a76cb	\\x9f833a09a38d269f2b78b92608421a239860e34d469c1b93a30e5528911450249d1c77a3496c8c6e890478f940823b4974ea60fd78547dca847b63a428d4d8a4	\\x5601ec425916c942113d4057ac97fb5914be25e45634f2feec643762d00a67c762f3613d48937b2a678eb0d2f687784ea6457e488eb43ff185068fca263e31238999e32ace8260462dc6e84e3a2f2ae124d758de382ef2da12ef4e40e3113ed7dc5686766e672d793473f60a7f565d7ba2f0085bcfc5d92e5306871900e4dba7	21	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	9	\\x7c798ccd2aa74d557a575735b9cd6455d46e99a0c7e0eaf0bf803d343fbb92a148c28e328889c738fe713e1621183d9fef4ff40baf490eb88a710572f1a2ee0f	\\x3b4102e237e38a126555a643bf1fbb78972ffe5ce4376a36a79bbfe432726d56fb3e2d604e65d3a5a68ba09bcbaace3984c599f6bce15386655b0962211c610d0dfa5ceb6be46fa6f23d5c8b3b6430560627b8e6e3724f195364922bd573bb22107436dae65aa008c15e94cba785ea07da2534b78ee470bad6abcf2247850cf5	\\x4fd26e1578cb6098a7ce4417592bfead446110f6518d62568f7e7a3a5f4a0d5c8c338cb5863ca18bbf9eae0503294b89fa87d822e8c451028e0713b60c1a4c2f	\\x27f53b77d28cfdfaadab22b5df1fd785dd285dff26ab95f7e9d3c8cc5428188b43258781a515636b66874d756d290a8ac041682931dde61068cd281a58749adfa49aee59a6d17acee84b490b727dfc31d1a3ced0eb2c6937b7b794da9646b7b5970564e4a8f01f067a36ecc8d7129da8a4042a6d6a928622fc8a11a9bf9dcdbc	22	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	10	\\xe227b0bdf8cc54c9206c5ae09c10d3013cd191f69e38e4de6daae801cb025320097d294e2649dd95a936bdcca4d18343d769d794ec4829ff7e746e42c867e408	\\x2c54e876c97ff58b96165758231e4d7b6de7f3c54ebbea3a1acc4782cdeffa7d8e9dec2ac6e12d20b071cba111ca5dee1836968d8c5fb10e5e6df1077a9597dd1e5e03dd7b9b22a3380fccabf427544a27444b8d9f60081751abe9dbac97ee5adc150b3043b20df77c81ff56f72cc3ded324a0801f07600d94b4fc47e5e86ea8	\\x49ea078244a6bdc61b009a2e64aefe0af4cdf568b7844f12a56e6df97f8543757a2ac7a09be3d23da2a59c5c99961c21bd1783b3bc223841fbe7c0fdae54fa79	\\xac1a2acbcd623c51c4bc54a8eed556c55323f6ada2dc58f684821e03f406d25849599056d699e19b33ef7ddeaf333561d526460d3eac9c77cbd1aafbe5786395450d83627225388e24bd85d6dc5c5ea3697b6072fd457c0e6d5ca494fdf909714fa8610d9f1b7067c6c9431dd9299f519ac67049557ed1a4394cb7d6372b5e67	23	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	11	\\x55e0451f34c5ab6b2c4935deeafdf4df9fa32c1868a446a470a7565cf93831fe957009caf5a11b28f5e93594cd40cdbbee3eddb92e056359e3d2e018c1120905	\\x64cd9fd5dd0c1c8353a3e92b2eee4fa9edf17c527e7113689c0dc9f9fdbb1d1c22b97a4436d6c08c49db57664e8d032266989407763f0e02a098ae4882610589796f27b6e16a9ffcc454762e1456807ac9e2b09d4fc1221454dc148d226b529073f7fc6449179959d3734cb467631eda155f8a4ae869ccc4bc86f356a773e853	\\x3a7c6320caa54f05a57a3f76abdde8ffcab5a0881cc3692e66f6b97d7c5c523f5ed6546894a5952df0c045c5650be2a97369fbcf5024a73149fc5583c0cc2e5c	\\x29b386c2b1d024696598ba81f733adc1b62881732c4bb11c3b4b26630b2c8d6f5eee8ec08ec6c058da66d56b3e9fee80a70875ef4ed9ad925004753bd89e7cc8afaf169272a981f9703126b227f29db9a1ef47a2b1b84d27afd0873b0de1903ea0a6c392993efad45a8a744d76823594e343932bb92236ecac2ece3ef0a09e78	24	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	12	\\x3a69370e32d87b19ce86a43f5da70b469eb141fff3c7dacf0ee9a073070027c2dd299b7e69301774f3909b457f0f16d5bf491c847263c0655afe4b5fe7b9a00c	\\x6c4f6486577c934d70318b999309bd6a2905bf8ed709bbc5d8129d84986c1018c955b69627f62413972d5532601adb0ba08a1d7ea24f1bedd9a79b144f983c8cf707c953e6f30dcfb35363547a30c319791aa19a880f395a9e7d6500cf331e6167486c0a61e308fe73184e623aca8ac4919f6e611d828059c50dc7eb25c6c262	\\x6ecedd45319f1f7ef0bb10a08eeaecca98500b2e3f0c05a4fa0490ab9b8dadcd5fcd197f51b69748a7a8d1252d8c032551b47042d1b24ce1569583a4f9c3c12f	\\x6a00e638d33064eaa8c2e168d1f825a32fa749e39a3cca8c6f503def8abfd915f42bf259337ed6d5c0aa848f7e74d799285f4f32179995fce884c2481e32d200e109de3aac7663063eaf2dd3f478594a790031cb55cbc5dc6379f8e0d7c196a9bd99bc35bc10c947817c59cd789d8ae783ac67ade305eb450f51dfbcf5c6f1cf	25	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	13	\\x0169ab98de4eddbf5208374d7080e18b2a85f67b77d7bca05913e6af9a724cb6b8111e2f8c98924635f5c2d237c8baa72106a50015cdfeac8d68030e57454f09	\\x988bd578572fd91e6990adf1a2818334deb489e107dd9d48c4d17b8ab447e8758ae173167de1094a6ffaf4cb7b5da02e96afe24ee2f319d19647e4c4ceae4ecf4a2c2fff1b8a8050a56bbd2b74df6cb08bf65d5c6843b11a9e734b4a90554557bf0eb77525e3dc509919f73e918797cc644fa5991c401bd4ce42dafa2ffcc3fb	\\xcd107e003d0e828dbe47994dc2c73baa2581549842ddd3cc3d77214cd9611b733cf973b27cdeebe91cbde42cc5f9ffeb03ea3a0498c7837e3d1a8f126d5e7a54	\\x83abb05f17f53abcb26166a139d7418a1daad44004224cf507c16785419c503314116936562a26e814923c09404835ef671408e4b55b14abfdc98c8e53b97bb997693d0d127d363f407a8cadeab89e5a5696ad37a9fdd7423fe3a07a93ae7f50ec190342f95bb349bf1ad43d272d36513b6edd2f2f7250b7e5db77771ef62d2c	26	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	14	\\xbdf70b7eff9f86363531eb14fbb04e6483a1faee1c7ea0f670b38e23e1fdaec974d0bf44d5933dc27650551bebfdd316bc39b2dd96b47c3e6930101806cdad0d	\\x6ecedf20626962d3ce116a769f42fa5f970949b1aec8f932646e1df39fc6c88237ced74a25f6fb5ab99d6581f8d6a09487224efab37e4af6ffba7a65a5e4e69739bf6267a0833b0b3a19afc4b5926ed505f7246b96f3561ca17346aec5c6378737db6496889349701cd572c8c4c4cd5fa7df88ac55ded17cd9d69a75d0182387	\\x1c69110c75c46ea98c8e5674fd9ecfff258ac95b7eb29d7e9d9bf702cd55f70c23d7821b76e5156669dc0833a7fbd0d60a1e32bc529bc10b984845b18f1e8913	\\xac4a8c38e5fa3a9bfc254435cb5a7b2a64b08ce49f096d1cf85e15d266689f61977a2a2167457b30807262186fe5d9190a2f7a3bd614108bdd5c7a20c2e30adcdf5fb13d390c0408d7db869f92dd639fa01e704f3d9618007655f354d680cfd31e0da9e401d2bff404f15557300d858e014b94af5862a7e6315edd42d44b5c02	27	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	15	\\x96e1ee34845379135a1036e0ae5028f73caa851d4af6478a103aa445d473ea63f5c63471920e37007cf04032481fecada9f103cd8a00ec5c5d6a17787af62a0f	\\x0ed9671942d189266462b2926ed713af09ba8443a0066accede93651e028241adac6ad0f778c6a09ddb5929c8d9794afac3e74997de5eb2ce9ae11653d1e677caae814d7a39f95a481a67306d998961c64a87c43f82fd4cdba05bc7a3b318c381907a0cd8142c51b02e46ec3239de3c2735b929d4e77b9c115bbfdb959f76deb	\\x9fef286cfe36c3c71228179d41e8e05a29efc5f0338f01ed3ba5992dbf477841a6b1803e5e1ed782234d1081431ba792fca5be72f6b6b72ae555e444562b09c1	\\x7c8c78b494a37b4521498dfe3b7b6f04908406470a61f3ddb0c852df8d388dffb426cd202433380e492277e59b69ceb193b1f0e9f3c3bbbe046a54e6ca41f4c4db243795914f5f5f30fe0b8235f8603143353dc52c5842b73783f459b6a800e274b87abf6c0e3f9896d3342a7a72a4123aa2875e985228971c3d5065b501e316	28	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	16	\\x8d46179b269108f1cfa78daf84afe233e59c8f4df496350514b6864e912e423777e95303aac62d21e027fa66b49b0d66f0271d777916e1da7092379084d9ac0c	\\x551fba24217e378c11b36632cae6101b5fd504d6eec9418d883fa1d95557447463228925be96ca3c8d757c0900379570172626b2597c1de552b6d2a9199c7848a7b8b763d81e06925437507424a61c69f6dead37468c2c65d9d3d52ef18c5800c4554b303371072e6dbc1002327e1557aac32bf07ce0e6bfa8984c91aac077d4	\\xc28307d6ab2b424a31bcd29afe766badabb2d10cf7c96f1e546233dcff154eaa0f26b641a7aa2b334efe9d80299786ca255002c51510c16f42b0e29fd1661418	\\xa4be91bdadf7f1a4e73dda20a7d45edb15c0abd89f4bfb8318302b036e30875e4f5e2f2672c2807b0421d1275069c00f71099ba3be00d38b94f050cadc6faa8c489e4f9b58a77ef420d4c739f87eccb35b865b7a63f7b613fcc449cbdb6fc93f014ad94c5bf734afb465beadfd0205c11f52f4cc4fc8489eee05d2354bf61ee8	29	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	17	\\xe93bbde2202bd0a8b43fcaed669be06069115dc923771a068b66e42e4c532815494b2d18c2859fd57d63f1b8cc3174f2c8315a665aeb46d1ceede4e08a83240a	\\x7099dde30bf56c8584c3eb944589a9bf8c728c053508efe0ec69c8f7978e0de459dfea8c4506c55dfbf868caa4e5c9e27da07158ca32b3483a73fb1d1c740f9e94a27fc8d1ca6e15b9dc0ece71cc26e6d65f9dd04f5181070b31dd738c3ec756e7ba9abceea6880a3e973e5728e93c504536a22abf9b0b77b64ac4a7f142c533	\\x09cb2c74c81c9476fdf16f0bbe5f6d4bdb2215b8b921cba9a9757d10d8de46fe39616dd6c8204cae21cb26961c95686facdd24230ad3ff0038a325711be80f36	\\xbee1e68fbe2aa9c1e9cf14451952089a83dc155b7c561b56cf172466b52c952a56d1deb256822035cb426d6b6c7531cd0e540bbde86ba7d2207acf1a9ac81e885638ee45af0130b8c56ba624d9a330f561d70fc4a7877602946024f521074e0efb93f6ab4ff4990cebeb9828ff5ac371d0194724cb824103eaea8ef773a10441	30	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	18	\\xab0e13299e8ad9fbeaf39de69209054633c420d2e039d087c2045f35b373c570621d43a3f365122c2b983c00754641986a62d16393d85da54b699aa01cb3c909	\\x2b5ff1e1a205d1ed5dc597c73c979008eddfd1b2842d48565fa2686cc5c1446b9609ca35d74093c4790879de840cb5e500cc96aa6c623a0dd77b7cea1dd1c79ff7b69ca2f7f038e5da6a8a0b95d9870d41649cda8a2944b588cb9cb427c5ff430d8156217b1a114e26fdabd78a6a6222fb0ce14d3364208b5eb08e8b664933c7	\\x4eb7de7372572b77b31941ed4986bf97c91d6666e9b4f69f8f5de7f89c1e3bb50a300d746284ab7d1def32e74b65136ac120e997b962781ba1a0c0cb688e0d77	\\x2fc58e5d88b7e4b73fb2dcb2184cb0c2072eb035693a69f313307da00ae4f8dcb17d65716884040cdd81c9b721760070f0f386989fd86986898eb27e64b99472966748d486250a593e99300ada87be17f559264c14df730520ec4d95db2469535282160fee7716ba31ed100932f64a36ba821126ff40818e4c38cf1e1c7365e1	31	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	19	\\x5f8a60fe4e6c886558c1648b40ec3329c88f16a7a3e240fc9c7ac761ff6e8d88011c8fb35131b2e473588a7ad5a80f87dc771ac444b501c7cf5c65ae44239103	\\x058bb47a63e25b8e23eb9ea774770f0734de2e184eed7e549ad93ef0524601417ebf98bd71e2130275a0154f6d50aa3d3f30b03b6538119027e281433e913e7d1822fd84eb11ff6b1c6a6e891221f3cbe80f77edc72a967080af2c9691260e56db98c90bc644560db562ee02cdaa93f46d8a254e6e27244b85ffcffcd81d81e4	\\xc2cfebcb3219444f181a6b4ec46ce00f2a582ef81403449bb37f1cebc2594e56e480e744c078abb658e320248f35e42d596a14cca37d892bd31747defadb83bf	\\x776beec22dcc9674bbc3620d85046a4f682af091eab137f0b534d10d9621d24f4379121ebc12fe0aa6c197679d2cfc20c989fc28a239a5dfb172fb6952a724929b6de0bd62390d58a6b62b964faa87fa639f5f9801bebf005f1af62fbd8df00ee9da1d06576eca6698f17bc55c06cd51697d5939e07c7f031a1f27bf467f808e	32	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	20	\\x54b62716f590b26e256dbd0a813ee796cf6a3290d71e2f670e702a0e07e0acb4497e5904c7c7359a3b6228e725120525b177b3aa489442e33022b723f8576d04	\\x25e54e28796a2bf1b8cd240c58b00269da079ca21ac3c5e7de3ea06aed4e42fa9d08658f8a13f0705790216532e9d1f3afdedd0d1f038cebdeb06afffd37086f2c8d2dc36d9e96ca3012d669324f31293a4f9df09a6ed986e190319315f4f90f612dd6d2b62f02999b7db2b46275ee78a9af45574fb1e7893d47b21e70d0999d	\\x78de76fd513d21788212948f770660c9abf507ef9443f16ec95479925de3e511fd703468cc935f8fcb0d6bc954718d9e6a2bc3887e9092f48cbf85b4520a80bd	\\x0bb6b83bf77c7c6f21dc3937b5c4619b6d121126953a9efa6740a606d0f93c1ef3f4c0e342fbae34b4dc4fe52fe70af1762e1fda197204006d3deb56d1dcf8db5ec49bf7be5a2eb398f0762cf0b831678bcc8f476f1de644c490c5751dab58fdcb6679a815cdaab17edf16b3c3827a010914e89c24c8e9f7b03117caf34b1c1c	33	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	21	\\xb69fa6d897ef850c86a12a9d6aa07f6df18bc4c89d0c6a19af0ca91c9e031ff4092117c849a5009d79285aa29e29c1fe37c6d879a4ce3984bf4305ab9b36660b	\\x994e48651a40f5fd52683c636645906b0ac0184de6d0c01bd33efa3863f7fe57fec2906655b59f229cabed7247b0251ef6bbb53f833a0a0b7576fb6c6887bd639bb6258d28044f621229612236b529d58c581377d946aa706563a72709ca7c28b4b8b0efe8ad147afa9a607be68f6e5494be73b812b76fb5ca83793862ea4987	\\x7a3ea251eed7d81d65928f3db691da3de1239138f365e657a1685e8a31a4c5ec308caa836fbbfec4efa750ff57dc0bcf493986509590e61704c21077a9a2e1ba	\\x2d784596645ffada5eae7e1ed3ff09bd5ae7a17dfb9e0bcd67ea351e37937a4876d5d8d4369cdd250a0af20a3b760f16a35777295d503b3a5889bc794c747027d9b729a2fa1f1d58bc681749dc827211212f488b55775442f53400b53e4101118699f068689aafb97a0811265302d1445d184cca8ae17d23911283af66b54648	34	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	22	\\xcf736a5c448629fa9d1c45a56d41aecc42376b92e9055443469eda2463f2646f6b5369087185951ec8b0ebe6af62edefb1a357b99e67ce6999bc78ce4147ac03	\\xa9ea2b0a0d59e4fa85a43bdbd850bb3cac744b00040ba20437a72dcb0b169cb74f7dc682c324a7008183a5a22c6c2c46b3276643b010554aebbe993b79cdeca82a8e2ee636361518d05381de7eba34f9528185d9e867c4dde49bd8de1bbfd977f067e0d19149f808d1c73075576c08402331225424e47a17ce8fe3d391aff165	\\x38a78779e5fd495a930a1be81b53701a4b91cd93cf433ce057157ca5ccf2561122bea8f8b6c086bbc8d9c006cc06154a70a32395874a9754b01ce84cbd31f623	\\x0f974fbc4af180433888bb6010edbf33008577d3d2f7d5b10d404e0f653ee48c9fe56bd713e5686d92476f0b4e0a582776f76d03f3192335b7b5f22d5fe934632c62709e99fa8536d84d38e150bac03b034ba7c0685234d32388adb1f085e97e911ba8b56a0f12da3687d38e5b57d1ad05216a27574a84c778e124def0c6278e	35	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	23	\\x8e981f084af9e3427224707d22895f4d6be4c6940eee6903886c4517b14c94776fc121c0f50b7d605b4b26c6b4604c6a0a60485b26c32d4f967859999257d801	\\xbeb2fe106e81d29e5589276c7a900f3cb2aea988a36d3513bc50095883ae466aaf10bfcf34a80f60511e5178d9a83cbe1d4446ec061bdbc49c3d44bec87667ac360c56186b39fb35190f7243dddede5378c76f0c7fc312f764ef01e101c1ebfa0d63f43b117d4e4f01edc4f7ac9c1b0902b3765ea7e5764b2e21650a79f298ab	\\x812fcaa3c100365d685f83b69b5894e750dfbde27d2eb710118e7fc38a9df356de6b6e0b4527e3af05c49230dc872440e105919e244290c6c7e7116512b5ccc5	\\x35a073c481b0474abdac7c3e08cbf50ac94d8ff38fd00e0464e08f3ce88826d72791c67f227fa8867c7f6c9be6dfa966e2848a50fe3dc265456ee37d90cdac3a4d7db1b84493207551f4ad655e1579698ece425ae49657e2b01478c74ee9b4363131ee178e398381c360a88230c09fa3647cbd4fc665c21475ce902a873f3527	36	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	24	\\xc6f34384db3f1d9132843ef5bbea7ee699e533e733014c403970951b56a4e5717abf15c119525ad701f7342d09314e27af355bed14cc5fbf4be5e1bd7cbd1709	\\x71b0cf7332ac29628294dc6a4fb4ecd7dcb3d3adde4578da6fdf060881e0526ddeda9841c94fa8fa7fef670e7e1e10c703658cc878c96d7b5ad435d4c92600819ca4183246f1530c4e6b9f16c8e6d6ae0b50ac0616ec2f21d61713ff5793dfe621adec5aea06f2c89e6d5cc6342c2538a18cf096444cd0c1dbda61c820f4a073	\\x62542f03ca4691e9be6009defa070fdd9acac7ca862d10a5012919635969f16742c23ea804e42f30e6b9d63761bac4a3a4727329385c8b03cc5eb625ba5d8f65	\\x85777addb1a932f38d2dc8c2ad800304d154cd5c368e60a2b805164ee57a47d309f265f185510a936f8c77e78e0af88c6ea990a4ef0be3ff336e8e118083cdfa640baeed6cfc8e9c485eed6e735152913e668b686c7d6dcc7fa9c80d43aa877264108a21a2b49961b244751392a3f3601b0810e3f79bc38669a45b752971d1b1	37	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	25	\\x24d52a0d8de716a702b745dfd3f07f1d7bc395a414287c6a5853d1da1f19ee4c9504d3e1c8b26c3674b53f24523c7d914ad01946bd212f5e16c1369341989301	\\x9ca7277834ef844deec15091ff04a5a46a60f5d2fcbe150250025cfc57900bad24c2d27e14ef6e0398fc2245eb939bd9ba57e4de6b9067a6c3729f5473baa2f1b934afb8b141af65f3062619f74fb6d31ffa7fa840968e1be4e336707812aa9ed255338134b06593f2916d71527c126c9b1d69d2efafe62dab5ef8a2c08c523a	\\x02b6d79a4577f49e7f37e708c8bf10777d0834eb73a6a1ffd46d244c6d0726c5fd002657ff52348498eee5a87285677b9524042252d9a26f271969d4aa265d91	\\x7188dcfbb8e7c3962693d82ad9aa9c2d14c11a1e0073773bede7ee62dcd4c141b0b27aa794635d28c5e0e55bd59aa2de358f351063713eaec35d2bb98c721b1479f80921f49e52af476ef5a99ccc749e20b6b00cf2d5a7b11e9527d7e550fdd00867c919afe3f2ebd91614570bbc0c8948c2acecbadda729d301c1289182d645	38	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	26	\\x79007d068aeababecc4620d693a8fa9cce64ed28a924054b64b64c59914c6e7e62f92c18d9af6605c6599fe5dfccc9f4de30d0ef33be7f47a1162d3418aadb01	\\x830a1f7ad1779f5c3ca3d59409367744277ebadc9cf525728e31302c4b05873db27e14547d1d7547f1cf5898936f098cc5e104fb82299c392780e14c67b5127f2deb2dfad477407c87abed1b5d81da6bad03766131c601a6ad6e33ce21bf2d26a84984b4bbb809a13548f0d6ae6d7febdb033bf1257b643c56df883e5ce17155	\\xc5e41b7355033e344b3f7c22e93c82246939805647aebe5853af9635db422805dee78fa5eea72e81127107649f8d497374db931e023b905f52592b9204901292	\\x0477d11cc641205a3dbd91676fd09420f5682133059f02cd3d40d520c5ab07b23eaba9efecf1f9e0aab08c029ffd43c796de1d43726d991b819e1467cff06254bf557a6237a3737cccb3e68311205b826a3bcc42f892f0d9bb9fed36c88ac133c18f95a6ba76c00136729960bfcfded71fed122360fd07a2b6b29e1b1e9e5d9e	39	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	27	\\x18d6789dea5d1048191c6f2510f7cac8219a5f5d71c1f3bfe8194c03d0a398348c361d5bf5eaca61b7414f66104f7d59b3f9d2ba32ce0493eae6d579b42e4709	\\x95c897e2f55505d83d2bc36a953591089bcbd8ad3f6c7a6ee806388c9f7193dea8f174b1c28ca51fa8940e34b4bc7c972a360a1a9262123c3e45e2ddf35a5b8561e8c5700a014dd6dffff307f5051ddaf389a92cbd1cbe01591d72586ef122904e492ff22eb5581678a00a444ccaa42552833ca992b8ab46ef77635cc3cf3f6a	\\x524584a05e55f3412c88d48779e8b046e7565b28bdc81ab2081f0518c2c7f605bc9b8d526e23d43a4e5b28b04d626c699f19c46b28e75c23a2708948d7d4483f	\\x811f53c42fc0c1e9effd804c7d4e2c8833506590c90409deaec1afd6ae217556528eee8bc7fdf51515c2d51b768eac606feec9829af9a337b0e3ceb868415977b61815950140dba2ab00a3e7f00ad9aa825ee2e142a2de9e13ce9fbd5659b23f238983e1a31984d4f4032e49b23598c27b31402a3663ee0f23a8883cc1f148bf	40	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	28	\\x6dd8d04687447c6ad8b847b55e544407e11956f1edc2468868f6263973d09e9a3b6c6f5d30b94301c619f6513c722d4e3374ba304d0d09c475b0a402143ad604	\\xa0e740ca9db491341fc63099730d104cccd742837d30cf9673453ddebf5f2292ba0effbcbdff27adc2fad79117c1bd4918b46c4798d9f8871171ddf915a80e38f8c1017ea419a61011bc643edd5c5651220bf35734abf8b3beca4fbe3b49dba0ac458a59b7c9c3d39e6e67f5da03c4777b88c4098d07aec7484c9a7837ec239d	\\xebf2ac784155f3d218ba735bc7dd35aed368a48bae2759c95b4416318cbf7ccdb066ef192c02883f93760caad2c67a6d6a184396b37325eb8e219c15974c63db	\\x1b04c55cca72d0eab3af6b722b189f37947d231fe564fd4b134a3e1f79acf192c649fe89d4849aa21fdb991b7ebe1786bb19c43f081d85ee9a563a32e0b7806cdd94c5ef02e64f2ae2ae2bed88cc90d409dacee402fe9b47bd649480dc2cef4d6d2835271b6f389b6f2f5698154df8fc91dce4e6113dc0c5879bae45bab07584	41	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	29	\\x1bc73e9de7869b3b489a5aeca97ff39a5edbe200df3893508a590b00e58769b0e40dff3a3da1dffceedb9be8da6dad46c8431044fe5b32b86a7b01af0d181408	\\xc873bde3e5853acc88024857046fd40000ef05489184f958167c66017a46b003f1764625a6780da8ce936244b182b763c379c94ec0445adee3e5ea535af3e3fcd3f9cc852b582b1bb74c087f4e7c183c88f8e8c15effafb7b3b1a4f534b10d5e5fb7057a411043805ad38e31c9abc5bfd058c2cb5a739fc81ad748223812c494	\\xfa998fe54a5371258f6b4de9ce15e8258e331102b2ca79c5658359e9d4e54c50bb74ad279aa3bff5c5e5225c80f693873dee7d027fae94c449250fcf38dc8e42	\\x80e15003f7c2030cbad153d21c9100e3ec4986df4f41650bb91b74d52f4bfc9ebf9a41c50ded421e278591a25e9c727af93a8b4978958695f458dc8b8b51df2d4e6418647d90000c8bf574125929011d37e8da2123b8364780937a086118dbd106c3c9bf8fd7169763a7a86185677f7d0973c3822a28531260cb9de8e0d9ddb8	42	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	30	\\x51075224235c0e4aa5fb05a3b02d51db3ee4126d9eb07ab9a2f9fa105b8e3d53e008c1452943d83ff9c7eb24eb4831642991691eaf915ce4207127739147a804	\\xb528f091403385c92ef0148ac9b1faf4b3b2ec412792e53f2bdda13ca8f4419023c36b51babf24be92d0bf0bf7a5451fe8a38ce5d865807829552506fc237215a4947a0110e63c19399e2bff39d10897171a999542a17ca0ee610bb118065bc78e0331d6d099fffaf238c699636deaabffc595095db552658cf3ddba7131a290	\\x8a96cc9baa27f0f98c5da11434394bb8c1062ff7d71a2ff801fc73806130cf2a484a91f032d2a20399771f18656fa1f3e610922914e4527cee43a3e823579295	\\x2f9f5d55ce6dee63d13c39294ccbf50ea36794532a4f6d758fbcdced8b8a52fd9fcb400ce6c30a8d14ee9e26747e93bb3ebb223b76f076b51913214c13d38d7f627a4043c04b81e689e075ed46f7dbfb4639072724231a6e14c5efd548066fb359c4f1fa46e6dc8bbedec466e39b94e8ccafd279e22e44a4dce824df82168f5e	43	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	31	\\x89e18f0e0bcdaac60ca023fb36ee0799a1ce85cab69500eb058487f628b2244c85664fd7245e7750b3f48cf14d66f51fba25f62d6732ce50e2d06102ad597600	\\x403ffde475a81256d9e51e1368025f090f55c070dd0ca7c06f0e77692467f2b056e502c4004c5422438af9c7dc49936aaa467b8a9ad8ab0d66d0b962d4af7fd8afddf052a512615248d01572496934f1cab8c5ed41fa770a9828b61129b255ddcd86e345d44b6569a5311f862a03ae281db9b91fafdef12f944fb796bf1f7f1c	\\xbe07b160ae621ad8d30cf8d56a807f887f2d6e0f88e984ceacfe5211cd75f629c37f93056e847da5ea5d72e701bc560623de36f2ad6ec3550652e2a0341e1046	\\x9211ecf015747b5ee873f032889c905686c832c15e9fee73f6613439259fbe0fd7028905e11ba09f1071999d2cef63a77ecfff7e2b9048e3825454d681020dc5c30760674cdab32dbf87a5bbc1ed1486417c3fb3ef5b49a94eebf1c9b89d4e31587881e66df9d16b14d8e79d68c8a1488b7fdaec19f4d318f19fac0160c1b29b	44	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	32	\\x621457d8e0cd583a2e3cba425143ae4633ab74672307d94dff73f4b04253e3d5592f67283d086e7e0077988a4217a7ca66db28234b9527bdf9eb7cb4401f6a0f	\\x322acd85b20d2b30ddc204995ab7a5df7dcf7564175be40040d18279c661217681cb324d55e86d716742cab0e30f95716e4611a0d07cfc9f8db2299800427a331883247a54787612801e4318b5b2f6cc3fe3db21647e18e1338fd19127f79f36fff684b4c34f784eb3751081e82935a3c23fd1b2cfd467cb7becf2ff15d77c57	\\x2f999a5c294005de9022b9d3653ec551b6116948fd85f92b52f9bcb5b4aa1555b953b306f7cd4a3b43bc6ac3e6ee00f95852dfcbc9f225490bb09f9532ca176b	\\x556e921b9aeceb52d24b9e8280f0b25fd93ee7bf24a8afac588e6ba3a94d1255c4cd20ecd094a459b6eddaca19150780dcb186cc88fc0daf174e3c96ab4357fd841f2fe90f1ad033d62b49ae7ce54ec2f7d0175b9b74b07e28d0aab48a7c99bb3873404332b2d11d9f3c6e86121181ab3cb07f221b0664528f46fac0bcb343d8	45	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	33	\\x40b3e964d2b3936bce2ea375208c209176ef1a2711ab643bd61874697625f6df508697ca380e845d4e724310020a676643aa9ac254cee2e5feef6597014e4f08	\\x30e4818bb97efe9f73679586648852c8a39bf24fd7136633db29b4226b2157328eebf89e99b5512a40c1ee1398413e8c80e26f7150a8a358e91536816b93deaf918f558e19d5a555fdce072d9b92731ac086131efbf89594e94d1b0d9c59612fcbd68742c40f276ae90bcb2c8feb73d5904544a7cb0a799e0fa3a9909144458e	\\xad94910d7e0b656d43bc808a9aa3e233b76d527910cae2fb1d4e65f006ca43928daaef1d17533e70b29b55191ef5aad17ef2eb0294f04b29492e3fcf1bdf5572	\\x83497ec265fc507eb6a1ab4788292024fb05d59a512e97cb72dffcbfd60dccfb1189c374aaccb55495c95e43a67a98ba9c9b132b63d46f9de1ff047724198ef778f309962a0e7138a873f1b4307859f744a9b7441423b14377c07dae6c60fa9a443d908cdf390c0762b66094fae3db07452cf649265f95b2c5265ffcbde6d0c1	46	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	34	\\x64d7e23c023b9af3098a1e16f80b2e63997fb47a74b119a7bd8a8b8abac67b305f1f39720b13ca6c74e8622c1453850da4c7984b62933f56ae15d15c1604c001	\\x4ca94cd4abf4be43abb998a843069861a0872d2994914dd1708bee7dc6e22c4d15a4c78689561f3c1d70cce152108383912b9047ba964ceb777ff15843c4cc6a78e9cef9eb7b696ea84b68d3b12caac1f27cd590a608686d1b0ab03c05ac25cf335e2bf5a3055fe9e851cc28380c15786fcc431904c2eab39762d05a921d4928	\\xffe606a8ebcfaa1288b9e83c16a8f09594ceb9c2603bdc2b873bc70c00faceabed992d909ef31e38745a80b68f422cbf2b77d889351f91631f51f9248095dbb9	\\x6d4a1751413743ffd348f81f0df5803efca3c41e9e3f13b76aeb1a9bd65168b0fec68d16860910cc256ae80bd89707049b0f976a8a80f76dfdb6951545007b89df8e7901cabbdaf85f79e10cec709254c90801a69964f6115a55d3c86dde773a81cf3d123e5c7655a4d4c5b35f8313356d86d6a10933739920fda886f9d5f60d	47	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	35	\\xa6e6311d1362157dd84fda3a258440695719a1a3e2bfac81cdef3f3b534a44e7fe9e46bf0d47e2337f0f8b6a5067c302f08b84542b4db1abb78343bc4c60de0b	\\x8bfaa2d193c6e3b6841d8236b7906561f070ec6452bbfc9b2a7d230a7b6336ce4e38e04d648aea2c820db74dd24f885ea02700c2cb3bad1e71744405d82ea9dbd0928896f2895aaf3f8ee9cd626d8f455a35e37927bd53bb34dc7f93b0fcb6c8ecfe1e2ae9c1765b8c192843a808d6631af34eee784be6b79eb934a4aa7f90b3	\\x75c514de1853b6bf807110f8318c845b31c88760c53deb4f056c181d5d1a1edb4cad05940f8c22b8b227d65b1453456388b3b8700227652fa13659f232d8d71f	\\x09a46b5dfd511ab15c3ac3329a3f7d7eac06dc7a1ff69ed06a5b07d9d9d78f7a9d9346a229c2ca2d2b6a6e6296aedc84ed915c73fe5821b3b32ed2150a931ad1a77f02da28d64739b5cdf5f8ba85624aaa2aac308336bf65fbcc50be1042c010b4e69bda28602493333cfbf76eae59f84e3f093f3dbb8e0ed9e957e999c36fae	48	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	36	\\xe025a807e664255ba242d52e91f7c9406b909033f46e6d52dc3c444882430b39efc71cea6866a0fb81446c3af5fa37822466cf86908e15e4256ab3cf0087de05	\\x83bd4e2ac477278118c04d2b2bf1df981aa5968d34ac73d2d429cfefb5da8d640e3ff1191b8c32ddc2da0a4d1071b5b6ca256bcb8cdd8a0823af0fda6f465fe2fdfc18eca5aceea96fc29b871b03727acc32bba02f62bf349233041f747b22a31a9c4ed18461f538df04928b5c458ff76348433f942a22f802d6485d83d1079b	\\x70cc9ec4dde14c71f330cf7956a42b0e40e99c8c5ded54bca2e92b23a0864b1c1c6966cb53e7b424dd294a2a31ea370f731d0c0d4777955e12632e8e600d0c2a	\\x2ab4b8fbb4c24454b6034f4d9bf12ad1049ea8567a6143e23ce126c5693f30737d3ead605cefc2631a926fa654d374819da53d12d78b4cb2cadcfbd25700361c9b17255893b9132179580c5190166d00ae709bf41236e21722008f0af515c2fac51f55341d5817a806f40f298839507fad22ddf457254feac2d2a4fdffadb686	49	234
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	37	\\x9e5c1ec624bdbab8cd405023eab59320ed9a03a799d4a28aadad9955c94b31bb18b1747da35cef5595928164ce0755be8598b9bde502c794534cc68e93e80f07	\\x2165bc67d37e61f37bb7a91e27d319866aab85bbabcd6448a32fef8471868db1c510a9b9122902dd769372e3fad020da31a0270f4bc2ee28a6b7371c9978aee4e17bd9d23790f57a412901d405a9448ea7ae1f1bd2ae6bdfb1a73501625ad05f8d805a445b0436ab5e9a143db9e56de90a5d75ff5cf95fcabb3934a6143a8fc0	\\x7a401be8655b9b2c1ba0b94d8e7ebbf40fe1331a901df51de00b5e64510a2794f290b0c54d56d5cd7b9798f1f9165fa9234ce972ea787c0847ca0d208f1debd2	\\x3731b639a915d2271b96d52e8bd1ac2cbe45b1e8a8422d518d446fab9a50bd6a09b401c00bc874d1c1113b7207808645c0abbb3d609eda162e1b649b3f3c86198e1e8fab7a4346731fecbc86d265470a033d9fda0ae6cbd4256bec1a69c887e1557d8e877887b464d8ac46e17effafbd18966299ac6890084c4352ef2e2f2d04	50	234
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\x719ef38b8c46acd3a1be7b0c583e972f9d5355913ffede64a14f4e49f3662280dbf8db6175ea3154d1379808cb5af9ffe8dbf3b946a035bae7d332f7f30afa0c	\\x8b96a6e73525e38baa46f9da428abed6c742521544a18144a1fe94f1edddb932	\\xfa0921cd75a92e7ad66852712886084b2461f3df362973edb0828a01359d2592c1e68021087beb70355a11562f5dc182f18f37006d53dfcc98ef5f5f55b7c702	1
\\x58ddb14b467d58392ea438f13cd784527f6f97d84555d52b5ce1786f7397991c7e4548f6fac135f91721e9a2e39b0063b2beaf4a96fefc0dee64c4fff372cbcb	\\x243b0aa355f50d33efcee0c8e4a7b33a4336a4785ba42d3e11287cd45da51c42	\\x813e3d733358adf068e57369fb033e985f49207dac2da0724a0f02cab11067c383277964bbf4315a6226298955596bc2a7423e8372603b92052fb968b980909c	2
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x0dc014ead6c4d434a70588408d1976eda13a63ea03230e351540ef3c9e379e2b	payto://x-taler-bank/localhost/testuser-DyuTYxrN	0	0	1612548620000000	1830881422000000	1
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
1	2	8	0	payto://x-taler-bank/localhost/testuser-DyuTYxrN	exchange-account-1	1610129413000000	1
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x75a3019e3fc5c61f3a0a51dc4396a42aca1a4c594c250e0c3b6230047feaa4de30c10ca49d1aab4111e2ef19f4a23881a2bfab4bae6cfe93e27c2aca3448aca0	\\x62977e864f7d14c45afc4c72e11477bd453dc9b8bafb4c48b3e5c0bec35fa7f2881b6c0d25f8f687d1c440373729b0b3d62d1c03f0071628b5dd2ebaa7e0e503eb6cb50a030ac5a9a41c912efee03a3f46671ca59e591ed1abf0a36b5a51466fbecadc48cd02f718ad25516c32049f642f0d0705f80c1569758183f35c5a0953	\\x6d3ed996da537bcbe1e6be1fd546d434e84a92afecd7ad1a0f84cf026b664197a219922d2ccd5092ae0c58e8b5b485041df3dd181467f9faff8cdbd87fdf5b03	1610129415000000	5	1000000	1	301
2	\\xffed31beaa7fae0c96b4dc3637960a5e761eccda663ba54c4ece23b81e68a50d9dd1c0d42c1f0f15683f7811b28ed31fd3b761be35616e8ff63d62802d88f139	\\x2b0060add8a7adbac0cb64a656a3d87d7d536b194972d2ea89113c408fb1189cc3016454faa66aed12555fdcb7b28845c7a3384a09ec442424c91b98e21f10d1a707e81454b52e800ec200ac1c7e8b75cb90d3dbd997f0722cbf3baab59e3e77684f6777d290e715e1f60fec5041ae561132bfd63aba8f24b38acbb140ef181d	\\x76dca55541371d23a2b216fae508ba980e50295a3e49472368a840a94c4ec80c0d90d0945529756bbf65fc33ffbc1a07b0b504b754ac296d4cc80ca0f4f55f0e	1610129415000000	2	3000000	1	124
3	\\xf29b678e91670ec0875396fccb79cf8c998110c7155750ff20aa25dc05040d074acdaa245fb059033c192dcd2d1e827cda6a87b47238f15b9da0e2d99d3426cd	\\x23022c84184befdbd5cf636335ce9fae97187b7c70b77441b4c6bd327e5054faf96213adf7961f970344cebaaf1baa0b0e4d3aa49d5ce6ca78ee2a8714fa2afb2ba798a495f6840b4643d02573687c91109a5174efeca516a12359f2a7c1c94b6ed3915f1376cd8e586da45a1aeb76dc49bf51dcfed5f9b99dfa7b1494b5e6d4	\\x70b7dc2ef362eb05bdb41d9fb5bf56ce80f6f68b463af91dd1cd446fad6c1028d69a40c8b17024ccbd43601fc1d0601b43139e2d018ea1252e1b7cee99fa5700	1610129415000000	0	11000000	1	135
4	\\xe03d913d2fbff99baa8343a78af43482b0ab23fd83a08c8f177c9af8fa221ffde9727a5163accfb02b3eaec541c2f4ed4d1d41996db60387e36f16fceb550e7f	\\x416813dc1da08470e9af68737f45dd5f93e1fa86d07546253e4ad885f301082644b0646268351bec544cdee26af5a379ba26c5b5699332015154e01c67703595dc0d5d5052f05e0dc2cd38d4c36716a1a298d20ddcfbd079868a32b80f4b61e6c7fc1c18f62a79010c5e1ceb536000a7e9a94f8b49aa95b4f026f2511e3b6acc	\\x0e8931f360acd8825e78bcaccb874496685d49e9f8d35cb18f37b2cd3c418337122f76533fb34c118d9a449bbcdffc58a83a0794fb2b37ae8c91b5ee3230f105	1610129415000000	0	11000000	1	135
5	\\xb50c28b2f8fa2a8e3275281c78bbf976f140e6d4f4a8ed2faa6ab193337b6545e1d275e57073a646ec967b0dc4f58776f85a55f62fcdf9fa47f1b1a2d53006b8	\\x5ce094c016cdec2d4561a6c618e36d96d15295593a5fd001c8b866b5e898c6db13194dc7d89aa2b3ba9625ac5350a2b839ba447d8f2566c9c069345915f09f49d30c52b6eea11b6b7758360ebd90ce1520b2a12f0f5ca4a416ca48dbb272afad75ce13226b8247d036011c44fb33ed7b4b57d5ac0f17a4a7859a7b7fff130847	\\x7ac98e8f41d017c68b10b383726a743d674970e8d8788e1d805a466433773d958d007bdaa8b0ced17c68e6d3d5a195c7f35339451a7ff581a4920c272d4c160d	1610129415000000	0	11000000	1	135
6	\\x2ca58b3a43a83f745bef08d3e47554703f7db0212e54d89d6611a39df50e95ea72588c8ed0e1748d3f86b7a47b43fe9072a85685517156b58834f54c22478f9b	\\x361f6c0fa6701081d2f5f8b899e411f9b79ff77627640769fb9d257876f40089f92b4d8450f3c0fcb8e067e4814dcf7a3015e71ae3390ffc1514047767b7008b0ab1a60a780f53dffefcd2d16eec101d680cd4c37f340228a178411c4929b367bae3e160ece5a2743df418fdd2d3c3ca9387d0b5b1fb04197a7da3814dc990ea	\\xc60ad1ac9b1bc0911ee0480baf26de1939d2df53bfbda46b85e373e856e5e6c586b3b5174dd10d62e8219a7cfaf20b14b2e11bf9b416e171c6418ca6056a6d02	1610129415000000	0	11000000	1	135
7	\\xd0d60f56fb0f01fefa82913f2432dfa6ecbbf647d964e44383756a7f4aa597d626df3bdd9007de6201d858a4c0c160e6bd5167410c5210424056ba9ac3af311b	\\x5700101b201471252b9c7b0799c47dd70004a086f877b8071e259fe4c033e76f55a795a51c08c83991bb2e15f78977b1da137c2e93c1849e8d37ce4c36aaefacfe71a1f8b13d16e3f57f29f0042255c65794a25bfe1916221a7b33945e04048717d68934eedd83f918256d7156249dc40b7cba51825a8ef32451a886694d3fde	\\x7c4544cf5f38407fad3841f87a4ad7119fabe0da720b0c4fa85f9191a7d4134abb98dbbbb68e821abc57e9679aa4985323c98c85d78323b9fa4db8d0a695ec0e	1610129415000000	0	11000000	1	135
8	\\x199edbd4e254763d85a3e879f9e6f6d61da34a366fa92cdfd8fa54c0b160df50e5b425b8167500aa61e00cde5a10f76f5d85fa580f7b9f275827bd795f1dd238	\\x54bf5518b91fa17302ddf6f11d250909b9d55ba6e69d9d4c50cdde7b82e7ece4c079bbc0e7830a6d9113ee8d6fe63006d1089ff8a2ea4f57a8d59fd888d0dad45ccac38e20ee490b2dd07a5a7fb4dc42e0eb1d909b8b37db237e4a5c02362182ed29038212fbdf12053749219e038252e8d01a7d4b7b81d9e5b14ce02aca7e3c	\\xee3169e04a995469e4fd5241df2f39deadea5f553fe4b520bf50a58d4a9826879764b75b981256d6ad7fe54fa1c2af119db453e414a0c93d78831a0b6061c301	1610129415000000	0	11000000	1	135
9	\\xdbe0075d0c5f30594196a5d82dcd49fb2a894b2a928a1bc3516334929fe1b7c29b8a2ec7526d244f02aa360963e6316a4a0821b51bb48efd725e9145ba2db460	\\x84632d4a193f7fb1d02945e8bed47beb41a236cb4efa870a8cfb3915a9b71b5514301533ab860bd616ed5e651b07c340139f702d72a8dde8e17e067744a2c3e8302efdf7409f07e729024bfc34f4e27e8c49d837a52cfc831910da80648ca67a43f625c1422f8478208398798632d6c093541689e028a614c93da413c86ee84e	\\x36288a07e4c0b8b6c4e399dab7273db9d266683f33c40450de7d57f39448d01a7b3feb22af5cad8dbd84080c0dacf707ab675c76d0c3e32e0634a0970314500c	1610129415000000	0	11000000	1	135
10	\\x4e9ca13fa2737509e6d4cb9df431739270eaa9eff3d2cd8272caa0c64c7257b41da4ed29af1de17c241017e285fc41c872c6acae0f151b18d1bd38ee0535e6ab	\\x4d3475d8194234dcd5ebe6f0ab6c2721fc479449693ae9eee5a31cfd845bb75a2f632c6ea6ef55a84733f558851ff25f37d3fe89d6a544f43b4cf0244c6186bdd417822758c3a5f7bc2da225735e262dee9c2927965c8458930dd363bc6e38ec3edbb673b21ad9d69a8353b2a90909f703cbeafdf104a650b79cdd4c25df5e8f	\\xea2a832d7ed6800cd240a89e764639d0e45f8edd38a5fa0ce9be66f1afe57506e1ffc07e586ffae619b94667767b0671649d9727a2ea9e8c92c4752144ee0d08	1610129415000000	0	11000000	1	135
11	\\xae21db6cad7be7223b31d6101b9928b74b9c07b6e9c1c52d52b9f2ddb3f42a4e9680cc2334623fd0dc60dfefaba43db6764968854995b4d912a9c7c10e178c95	\\x79bfab2b4ad26893a905f4556a31e034241af69d917550dd8be59dc752388782ce4ec10f12b4fe632f689827d6a55573f9f450de846be7b2e678eb1d62d06e105fdc2cfbe615391059e5a2869a78624cc174367f7c7a686f4cbfc96b4fe778b0e0edf1bba5da09a27d118c86294cc90cb11ba0fb247d66e917e1d0c263e2ec25	\\x964b53ec4313e2314875c13f8bd1d3263f20489df1a36a6f8189b68169efbd89f7dc385c6d8d1b5c523635b38031d544cb1246e9367806070473e0ae689b1800	1610129415000000	0	2000000	1	92
12	\\x3ee5426e4a86f1c850ef50884bf39d109f949cebd0ee276f50dafd04416f0387471d51fee93f4e6b3713fa6c036229b19626df31ead07f92d3cddfca3a310063	\\x7a677f6e7d913c98bbef5a8168e12960b1f00a2c9e9b312db896bef7ffae26601880f5797c348177d712d46693b07002e311afafe43b5d92b0e37f6cf5cdc3eac0cff7130564c358acc0b93ba676a300d0f3f3eb446c2e7b8333af9ca08db74f274e5d56233c894881813d65c0b700d856e35497d27ac5ed6e00c2fa19a7af57	\\x25ba054d61a5b6b6f05b363c204cea79c5b9ce47fddfc5fac327b09870f5ec8ae8be5e7a2931c458efaa9c67be9fe578314da0b13994639c4f5c4c2cc208fa0c	1610129415000000	0	2000000	1	92
13	\\x47d53c4259bc560c82855f42828e03e7d71a281143793e51fc0614f75a23ffc83e1ab4c8333a596c4c72915daed77a185bf0aea743079cdfccdbe22fa15476af	\\x0e6e2732041da2e2923f1d24d6a8098ace132bc216046357a9ec85a6f3776448e2c56d074e53a8a3a716fa0b8b5ed52db23c4b2c1a61e12c53990152652c4ca616f13a5c27ef2f174ef731a7d3f1c2893dd489e2f40299070faa0d53789011bac2bdce40b1b66b0d314df8388d93050adfa17a3a4c0eff08d77cc1329ef0feb6	\\xd05ece2f0367e771d441e937cc836c934283321473a4a388cf4e6d675128a5d6d141a60063fd093d2e209e9b4b87bbd85699e22d2a19a76c9f1545a8dd91ad09	1610129415000000	0	2000000	1	92
14	\\x4401381d1f252a8773d3c70fc4416e793e183b6cee5b47650d3ae6a8e0bbbc3d6a3fb382de58c68603e9d516184461c5342a2289068b18305cad2839d92dd2fb	\\x63fe25a53ca3d9ac06ecdaadf98840aee906caa61b7478b46b5542653c16907c113436faccda4d3da05c8c23baf1eb9c33c39d04c5472245b535f9ac5d95b38c948b6addc59edefc18ea14236e336f30101fb16fb44d5240d5d9ba59e531c4e638b8aefbbf7f2c95a50dabab4cd4299d9a8574a8d8ef09bd1774079852bd0738	\\xdb42731310ad11ed2ae44c51739e78cb2d0cd40232621889b9e1e1dac7fdb145ef6806e1baef96b090eab622100c450dce891e39f9fa057e61c827638062d20b	1610129415000000	0	2000000	1	92
15	\\x1faf934e86991c1d9cc5fb494eced72397dada5b7506cf5dd797361a4ad6e26644185a6b6782d30afa88647dba90b38cd1b03f8097f87264b6b8df15d8fe5bbb	\\x4cb10f185b57d3e5763f561bbf034d0eb391483acdaea7ae3e53841307a0b88b84cf3b62ccbf1bb1773f7b10ee4dc109545d7b7c2b0a5b168d4953c0140390514f17523b5a064eaa16d889668956930f569cf529a917ad12ba48ac32dbd43cde250933dec6df9defcf1183613e03951fa6ed3b6c852856d98bb0858f6f283391	\\xa4f79341236b5a1bd5effa66536614795c57634ca19a1a13595aff735bb08dd15b7296acec171fb0a1d18ac0b1426b6f56bf7f2187a7fe1336e29e0306020202	1610129421000000	1	2000000	1	343
16	\\xa2d3cd86e2ef2889522d1deacd30f4a551769f49370907a8c6862363111b68415dd818c8a4673681087c3824ba1dc62e8418d60e74ae112c238db6b50b9ffe02	\\x2a5fc6f602d138896ddfaf9c3fa415f37d8cb9412c19d27c80efefbbd1e02dc051f9ab0d5c2d64c897b731dd757aac44e2a2d7e87847cbff5023dbdb39777a808542f7a0a08924a5080234f0066b6b9c754bfd5ddf5dc80415f60a6ec9f96e20ff8888c1abf6b9a4d48c26117cfb640734d207ba236eb7187c3436f7a8037072	\\x87091b90b017b86027b2116db99f90d5a391f185ea1d602bcb208eb4c4e2d3e889fd2b4df6eb7fff7a003c765a4683541851629fb574143b301e7b695d3db705	1610129421000000	0	11000000	1	135
17	\\x87c6a28095a25644df4db28d97131cb0247a7955710b15002ab9eef6d7bf6a7e9cd60cf4d6983dabd5d1173022b99f9330e1d57068eaa43df3d23a61ee44ef0c	\\x99fe0ca9df760da01024ef1a72cc8de6a91169cee8f13cdbc67531d3b3379ae7930ccf1a5debb8e5d8398b3f91fb606399925604856ca9e836ac653f7fcac8a3b30ed661691183c39b2a6a17fe95c2fc3e11e14f80ede8358d42b62089bb07bdc37f691ec573be7d5bea2b049003ae4be27ad5b39f17dd3731430062196e5fdf	\\xb503be607eda89e04298fcf9038dbc423fab3dbab9a1b1b3517bea330cf0041afc1f941484a9981076dd0b849d5f44b58e40101d6dd589a8f7f4e66c34df9507	1610129421000000	0	11000000	1	135
18	\\xd29fbd12a98a75c7c817b8688abb9aed73e45540a81301204e64436ada7d98eef49adac6c273382b7affbc9756e9f0c8fde4d6379a8be4b6308a63bbb020529a	\\x18127e2856d80d47169f9737ab2169d573c9555a446cfff615d9c71abcefde4368bbfa83723bbe2e680ed415096111da53e934ddd486102d3d0fbc86aa037fb372c2c90e03513c5d6cf3afbd02192a6c1b6b37c0fca759dcaa9b6b6cb07cb50e5a1f3dfa1f90e42a3b984b5058b2d76778097aa3883258b5d0fd5c01497883e9	\\x3d40516ab50407f6cea32527fb49d2ecb0351e7e857358cf1ea9f950aaa9c75ccd1552e146351a50f095e571fcb62ec704e11d72e2ff7cdcf0feb47708de5b00	1610129421000000	0	11000000	1	135
19	\\xfdcc0043f714c9d810125cde46799125d40dfd74affb61077db190b47e0459cbaba6cf6546c70cb70ed7fbcf0e4c85e90a5969e78b868075782357a62da9ae4a	\\x31409f88a93dedd7af116409c5a862bc847d13da3d9ae3f86c459aded8e1663f40760933b068b508207de61e55b72fe0d48bc120e9ef0067ab148b2ff9f71a3ae446c9af2b1ad8587a2eb09ec85bc3c7e6b1c4ae49da6dc568b902eb3626ca1d3d1c6c04063db65d2357d32cde3d32d1b359b493cfc6d703c9a39faa16782885	\\x0ac03064b7f9acd6601b631099cb3650f39335d2aefbcaa2b9c25921b0bb87316303cb9a2b6b5e43117e770935adeb004eb0ef4301fe6f18f45f05052ba2bb04	1610129421000000	0	11000000	1	135
20	\\xf1284ba90d68c8d5b1dddf78789923bc857a24a3ac9e6176f0050609a9f252580539fe200227d3bd4a0585d71ec4a971dd2a4026372b20316fd6bec93f026b5d	\\xa8ff90105e7da26a452ef7e6aa1006e65c7839898be0b63bdcbba8c149b8e8e386027dc6b902bb4a499e826f251e759e79471e03e2c980ff82d78be8975d2b0be7d2bba97d1eef7d05359cb2f367ab4f1e7c688c71dfdb8e5640c8e20279d9597802706ff67ad1699c9aa3214c55611c30c069e27301b1e4c12ef0e72dcc8c5d	\\x8468d6a18d2f6e1cfa17307b12b8c67eb9936929164440877532c4a66dc65d704690bc61a4b2f9c1a970c8d71ccbee95a44f8196876e0f6adf8c5235e643f309	1610129421000000	0	11000000	1	135
21	\\x024b5510cf8ce76ff03859f8c16dd6d6ea565f16961cf6b4134e064d848046763c78b106f5390ffc1ff0d210beeadf6326e02e547e220fab7e3af315518d4b76	\\x7efaef35b85effd0905a016ba4ae1c4e2bcae47a472acd6adc763b1a3fa84bed4ef0667ff5792cc9c09ffe64932748a508de04d21fc5614495405d158f6a73c63b1cd3b48cd06ae7f5a849399b1be1ebd57b52d0781a6b31630f5026458e9c769da2c563719bc37f4cc22c4d82c27c7c558e779432c7180afeec27ea07407733	\\x71fa7bf15677197dffd226000d42c7c3753b6b646d5f07f51516349f456cc7ca97b64b9fbc125d9c35986a7de3cc86d57b93befa4766d736a88cb104a52f950b	1610129422000000	0	11000000	1	135
22	\\x57d298529a1a907da5d06d8b93a0f4b08dd47e824edb9d6468b61bb3a1ce60d51b37cb7de41f9ed9649dc358b66b3993656f8c691983243755a8748a0fe25555	\\x0488d4e5d1e64fad9083d4588802d77c913969a5e42dd6ee58c9fcf01b129d314445c173b67cd4c92e9df5e622b2a7a04ad087c9939e3bdc1878d273eed9f2701e5c02e3402db3e14e85e64fb14f1b92c4b7d1be26ffe69aa968eec3030dade22ddbbde79c370334837943e8e7b536903d9e7234751612add3b79597d35bd4e2	\\x0fc1f0055107f19d69abddcc8c87d086e12936fbd132353e8d7ba1515ed38071bc13db43f3a7ddf2651bd62f355cc9617dc3cb313e05e27a11ec8b47c0e59e02	1610129422000000	0	11000000	1	135
23	\\x3eec0baaffe2e3998da2ac8f8eca46f747b35353c4cae14d2a80fbe2579baeb68a4ac0f61f86cf3d902b1ff9a0bca25817937bc5e44b32d6a56d55f106a71886	\\x225beb4f608dd592c1d76f77b713d863dd31e942287ad56c5725f3a78abd26eda0234d37cac973399a6e3c51b7bbb597c37a2145d33cc98c177c8ad68bfb860676a71dc87936f86c3a602c13104f6897187be6949aa6aeb8d98e77d6221725f8c2ed7900cb8d263ce399e1fc6742b78bdf07e8449c6cf29a76814d02e25186d8	\\xd4cb688342d73a61b69b7ef5cd08ded7888042668b915e1767ae18a091ea03f2a04d7f747a3f05514dd32c0271fa14d05bfd68fa37a66d2f96a96eb0cde57204	1610129422000000	0	11000000	1	135
24	\\xf26b7d7787d84d97f2ede66e3261c511f13fc725c19d48fe4f61300070fa1e42671cf64974f72719481da5fd58fffd470e5d1fc60fd312e019ce99ff78254961	\\x59816c53b0c4f4b2346ec9a7c5241ce484be82fd2c36cfde0d1ff3eeac84c650b4764644c15adc53123c51b2e91f541c684c7049050a1b2e672d5b1acefc65ebb1a1d092a4f141efed617eece1d431f4c0c2547a45f287f71b9a4a7e9ee802043d1e3da612aa190964699d03adec65074044a9c9b500580e92775b0cd05d4a91	\\x556d556d17a0d988b6e4828577ce24f8323903219f424f552d9b61c46bc60f6bf53edff37f16fea341f5284a818f2f482325d97555f03baa37fe661530b57e0e	1610129422000000	0	2000000	1	92
25	\\xd74dc1c551e03c9d3fe82e7238020406cccfda9a8719489db65750e4da19c349a01a38a6492dd4e25a0ece5095964d7de2a1e2a6ff7daa48d5865648b4b47aa2	\\x1556dfe97b913e984cfafb828ecbb7adac2345348eca15c1cecc1758212bffee9c29c68cb2a7786d181ce1573eeed87119d00e739ff3ebef7cbdd85cd6bb9e1290880c9eb01126f17dc8e4b693f2f64f953968ca83b4743439c3aea15aba5a16ba3690aa2b90af9d28bbdae301f9f37c0c17f5df9cd74935272410d77f5f1d6c	\\x920c2aeccd757aa1c5ede3fd19a5fcf349789338b4b03c13d41eb6bfebc0c9d40833f7182409e0eecd4b957c5724a519e883443dc7f6426fcbf94bb123c06c0a	1610129422000000	0	2000000	1	92
26	\\xf0c656a0f4614b5c879d4c9275778577b5972ff45b68ff2638abdf29ca8459e653fe0baf1db74c529c6493d22c7c0b79f7ce9226fc1e08d1712b097dbb55652b	\\x8011bca841fe313702fd16545b3188b5a1453fb97ce2be126f0363f63be7ca8343b55f54d92370e3f275f662fbf7134de4b8b7c1d15da8e2fe93e26153d8db473f460c160081dffb72fc1c97d0dcc32f3c3f1a7b43242122c6546f085a8407a10d2da4a002307e32f2b49475093cb8c5488238b6f72991571089bfee25d48376	\\x0355c843a253c41b692750585e9a62340b1d2366eca2d3d4da067edcb752d9c88c399d1bd9e3c737cfa2850bf88d31127f88ed95f1129345963b014c7671bd00	1610129422000000	0	2000000	1	92
27	\\xf020e5377050f27db092c82af7058e16adfe608b7f12f6ec84f9fffcf937494196e309b8f31073a2d4f6cb975e7a2a0b9c1db53d3e311d2afde339a1c6178890	\\x39140c01d0e265bcee7760a91f7687be9ba6c6447149a3f8ec56d5c15ee31a05ffd9d437e22ebe6f3e7d9cb5b654acc791e6887b517b6a8835165f3c0db3f616d9925e1504e5bd77ff91c3aba290fcff7a7464f51f3e50fe48028f6cf4e4d1ef00d4f2c9ba49096583faf4e0155e844019701ce3ff5b98d794188fec68b033ed	\\x4686b2922b6551b6294fa6cfb889ce1e6c4909b78ff3adc3812e4ce37e321637f36a335ecf1aae18a17605923005980a2125a7cdad17a93bcc3c96a1dbbbf905	1610129422000000	0	2000000	1	92
28	\\x93675238d53726585e003021e249586dd4e92f47c1996f2bf777247776ee9bc15090a355a574c92999469bdf38309ae6cc6a46046bebe9b0b17a40570e77151d	\\x29212150426ef0050a99da4ec5fca0ca0a154a320f28d52c75521866133da54c166b1e93c6bbf5536d7f73063fbe81227bb40f1493ca28be45215083e6a6cf483542d9a868cdd8f235cda02524163fcc0ef0bae208da2c34d02559a7c36dfdf2ec2fe7cdc5d438f755a4008431aa347585b2b4870c72499cbf244b7ae6465154	\\xc6a10fd132f0a3b427cc512a509d5a860d785d655f6f2cc01d7d2a8703f1734e9058406f31f896d8e9017b821ce376d4b295a013aa029fb68de4fc4f15a6500c	1610129422000000	0	2000000	1	92
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
payto://x-taler-bank/localhost/Exchange	\\x0ac3dfa6405dbd9f1e22e33b10770e1dc89d100cabb15adfef1be4ceceddc5e769919f4ad97d5754f113f77bd856bd2efd751275d3140999b59502639c6fb80e	t	1610129395000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x69eef06ec776a9fdb74728faeee627e37670635d2d94d7c6c9d3c2ee342ab28d6071723b192f99034e7779cd066f1b08f7bd83602864b47ff55895197d390d00	1
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
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 1269, true);


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
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denominations_denominations_serial_seq', 424, true);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 11, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 1, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


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

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 2, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, false);


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

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 2, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 50, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 2, true);


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
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 1, true);


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

