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
    auditor_pub bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_pub IS 'Public key of the auditor.';


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
exchange-0001	2021-01-08 16:06:46.970194+01	grothoff	{}	{}
exchange-0002	2021-01-08 16:06:47.0744+01	grothoff	{}	{}
merchant-0001	2021-01-08 16:06:47.261095+01	grothoff	{}	{}
auditor-0001	2021-01-08 16:06:47.40116+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-08 16:06:55.366274+01	f	5cfcb867-964f-44bf-91ca-3379ad752f72	11	1
2	TESTKUDOS:10	X3QEDBB62NM88AHMH9TV4EYT8VSNKZVTWRWFXGJKCDY610HY5FJG	2021-01-08 16:07:10.441168+01	f	4698a179-4e70-4c3f-a217-6c83be5e527b	2	11
3	TESTKUDOS:100	Joining bonus	2021-01-08 16:07:13.467791+01	f	d6474d58-50e4-4ade-8cda-0e0881377ca1	12	1
4	TESTKUDOS:18	7BFXV6GY6G9RE56KGEZXXK5BHJA0A36D2C4EZ4A1B6QD8WG734H0	2021-01-08 16:07:14.184285+01	f	b0f5fc80-2bd0-4719-97ad-e6c4c2677df8	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
21025628-9559-43c9-a07f-f7162e2bb220	TESTKUDOS:10	t	t	f	X3QEDBB62NM88AHMH9TV4EYT8VSNKZVTWRWFXGJKCDY610HY5FJG	2	11
5fb3c967-ec86-4bb8-bde3-a56f079a0e34	TESTKUDOS:18	t	t	f	7BFXV6GY6G9RE56KGEZXXK5BHJA0A36D2C4EZ4A1B6QD8WG734H0	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_pub, denominations_serial, auditor_sig) FROM stdin;
1	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	271	\\x4fd6b0758910b824f484d1ca67c72d54d5fc3a3f06eef4a02c55ef0386c346907a63838b1ae6733e5e6d4d39dac04270cb85c9701e71c3a40b5935c438700408
2	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	187	\\x6287a4cdd55ed6ff48edbc64cce6701715a1da3392920709bb91446a443cbea7cf0e9b0e98959077a5ec84983d19eebfc978daa41d43cea136d8715ec4c00b02
3	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	52	\\x047acadf5a7ddd254eea6034ff58d294f60702350489aea7cb6e0d68a65770d27f81aeafa602c65c9d136690a6210feb91bd0c83d12c5c3126fa1a9c90886b04
4	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	403	\\x06667507c95046066e5daf8fb0e309b01adb37337243250e66392a4d6da82d7e3106fa673ecc53c33a49daed6e57ff7bd5f3b885901c7c712c2cb5b0478c830b
5	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	15	\\x764fee1b9d9eaf762fe8dcd648c9e838e04815648e6b48309fc9e6f36fc60e53a0e219304f09193bece7cd6f60ef063754ec366ce7cdf606d42726e3e11f1909
7	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	305	\\x49830d59f27ac5568d07c0fba384dd7011ddf22631a1a16b1ff7795ae2ca71c4e1da2170d0ee7b1e90c34c56a85615da4d11525bd981fee762785f148fea6305
6	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	26	\\xdf7ecfb27f4c6a436a66728a5ca2de28b9705b15ab1496268d081f307a7e9cb3d9a5f8c324661b5c9259252366e1b154907cb68164a18f433f961d542ada2a0d
8	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	314	\\x2353d5f1d131fd0fc8e8c318fa1b24c2ba8fcb92416df1a1744f584cf6780ee3ddabf1d09cc9c81f01d38322b5b7b6a98101374f0dd6a6a9c10b6cc6f2b18605
9	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	130	\\x5df0c17a9643df4389cce8189ea6bcb917532924a2620494dc24a0b1254d2e3989c7b567d700d594b47a0fa64156c497e4a928446fe2958cb93ed04f5badf202
10	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	341	\\x2b9d2d9b8c2c4d0ef86deb4d72fd27ec1a5482d59400266779283e36ec4a9a3eccd59edba6477fc71dafaf3da97cc55a210f2e10a3478257ba21b4d9a8113b00
11	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	231	\\xd15f98fde4a5d274692555f7d0a36271983cb264a1a11d959e2097da759a88f3e37ef02366f9b447f5c3bfc7a0bb51a0cc2e8bdbb01a7fff288c69ce1bb2440d
12	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	51	\\xd4e79e22238f22ea8136438c752475656b4de2b3e514d1da6e17dc4f9d1422ff924505ff590c4efa0eceee9e74f45a7af8efbc1cafe2c7f1c80f3f15fb38c308
13	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	212	\\x92f8eec99c334db0cc50ff0781f4ff1d7790f6584bb335298b37021e08b5bd27eac9475565582b85a4bd1bde9008c703ac8184aa20eb3a0e46a0051c322af105
14	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	54	\\x170025748e29de9ca2b3c37233a8f24eac0800e92d95b19ce4083832da5dc70c3876ee1299d1d29351d75fed488f6258c5bb6c5c4b0a7073ae3702daa1bac406
15	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	260	\\xe0a448e775cfd1d60d48179cba07ea19ca4fe16483904803f739734bf11daafab8cf62fb03e34404ae3ca806ab25fb06ca0531e5dccbd23b147098f675eae802
16	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	146	\\x91534c944e22bef565b2259d92379702ea0b5f46f4129184ebc11e532f982d670381079a3e8866fc46b4fb003f99de139adb06f580e37b05f3daeef6d1438a02
17	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	279	\\xb85d33a7a2895ddf3e07115c5652c0793fc9cc7e617b04de67cb7fb1421940a3e8e15c127dace111c544d12001eefdfbe6d9107f14750b35679cadb744d3020a
18	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	72	\\x073c2288dbe1ba158f3786ae3c3dc9c0f9549d7c81a9f4559bb182ab6f5646cbf9bc64b2ebd4fd129e557e851dde650cfe8fde9f0446dc8b6684b77a46d3f801
19	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	60	\\x030f62fd1e8c540d4635fe3193acac4fd24d7e5926668a6ebce2a21f42399e36990cb34121e982534e40c2732b54aa7b02d93ca9dc20d60b0c391ed6e6c3e206
20	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	140	\\x8ae409e7f99bc521b987d1fb444d1bbef0628a8b6f94119233aff176dfdae8768f7adba9c07c113df04f2736ce425e3bac49ccc7b35b966998507d9ccb275f09
21	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	298	\\xb1ca2171a915fd63056031916c651ea4fd4069b1794003c9eb586c066b411d0a5b6fd3cbdb076d1d2d7cf4952959990b11b6a106cba37c2a1dc6b3d23c5f670d
22	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	391	\\x60f227fdad467c517e4a0d004ca76f85fd8024bcfccdfa02b05acc8ba726d22a212af2d82f8a9b1c0e75ed431d1aa2d5116e4ac2dc31333461d466e9e6ef400b
23	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	165	\\x7581419537e24966e97997fd5db5ca84a7ebf0b89daa6db035d1332da4c873aacd39b4b9b37774e7f815e798d7a751f09af048d6ebac7d0056c1978ae335110f
24	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	338	\\xa968b5d1d0ff509e235e01cf4eda287259637ac2e00c115ef020b77850c9134cf3b5e3166f60a141b2b7415caccd5f54dc1da1e446549a4211fc615d5705420b
25	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	221	\\xa9ede110e919c90ea8733246332eb32f67c52ee691670f64802b8c93d346f62fcdfea23eb86de473c83dc4d4de31efb9370e33267bb7ae2b97b3be8e5f126c07
26	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	134	\\x711b77159c254c5574e4183616e5f6885473de26558ae56918c03369ea016e571e46152f4e1d0ba153ae039079f6a639a6e86af8a0f391ea69b38b771a1f1f06
27	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	384	\\x2209e635d898ae11066f74ad4cc41134d844617e3fbae0e8014e3101904d015caa97d7a18c2046833a54bdc0a4224848d484be5c2a1fdff0abebfcd0bdfbbe04
28	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	137	\\x5bbcde1f98db015630fa52af2063c211515ec64bb5ab8d4c143a8d7a11c3550dad251337805903b73c51f95b605ee47af2e319cf5b789be2495b55f44afed703
29	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	205	\\x3165f8d4262d23ff30d78610ba6accab2be71894a4d55fd47600239f0930fdeb9b9234aeef2e230643fd8a695724a1f938aa4bd533901735259e644b2d0f3604
30	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	4	\\x5914293439cd53635f3beb3f8af7afad2e76cb1155d920da7a921e8b17e48185fd028d11e08dbcd598ed3e4ce275f4d494a064cbfa6dba52fa4800de4929dd08
31	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	380	\\xc3fff816ec3082bfe0157102d2351e07fa3e5568b13b45a5d686a8be4dea5f594eecb07c9b7acf587092bb7ae1407d75f21fc2a95d12c398d20fc8d17b7d6d0d
32	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	143	\\x8942f60d2e203554d3a0bffe22b9cf95f5ec097f9203714824f82b3ceb7750e9fa67421be72d5ca3b866c385826c4728c5cfae6bd960d5a75d0c75d85d87a702
33	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	222	\\x98148bde0c94d0467c5692673034c4280779d7394a8e88319807234a8c67dc1b6a266061fa507cb4abe978cbc139108d4681b26e1c31391ae492b5045068d203
34	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	311	\\xe309c44b46e809478ed20f4ce6d3f433d416c5c73980147edeafee394b4a7edc54a8b5a568da591fae4670cb4fc3de89a7641e8f6ebbfa24b00294d9c8384b0e
35	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	196	\\x4b383cac03827361eabcbd64380cb54dcb09fc22a6c09f747175806adb7d0cf7dc499297c2e44a6c4e71441341dbe857f40bee78043e5484176cd071722a5a0a
36	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	56	\\x2988906d57175f81f1df19d5ae60f5e13cb04d73fc047486c333410af2a8090b152c05708785e688e0a2aae2b70e5a3b8d8fb624a8e4ee4bd9a88bcc3f81ad05
37	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	398	\\x0ec7cb33d76f49501c6635d11772329ccb0acb37ed9630ea6578ebdd89880f2c3e69d36b61f604e6778a499b49111d43efbc8fd39d9c5d11984d0e8b9672a80b
38	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	101	\\xa3fd433a062b78d6f79f8c217ef50a97bb0ea730e5f1b939ab1b0bfa876f31ead828ee76bdef5aa77ddf797c635bcb3ca6c60de478457a3c230649036af8a20e
39	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	22	\\x01b0ce05a7987041f6c6a03b6e87e73b0874c3cf2b33a91a443a74559116a481eaebf2da43ade5054cc0015616619e1314c0380ec305680adb0eb97ae3aabf0c
40	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	297	\\x7effc6632b7c151dbd4388b2122f28dd7c122484a1432aeff8efddd85ab5ba1750519435f4b2f67668700c62c42b5989e0635578aa46fec65abdf3028173610f
41	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	133	\\x2f35f284ab91549e0860873dda9f8d6d1ba44c93946921804d8928c6c88cde18bf2d4e7792dbc7b76957525c53625065e9081d3367cb9cfdac66ea5df4815e01
42	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	123	\\xdfd5040dfa642fd9a8e0b47c7ad8c640254e1e11f73d0a8ccfe0d2fbea1cae3f1dd9f5056bbf98c7f0b9a62f3744061f5c853267b72b9617597f7f86b06ff50e
43	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	47	\\x10d3d8f7ae887e25e965fe1b6853d98dc5669bf738c3480a1c26393ddb79621f7706ad11c2c3c55ac20dc371348f32b1d126dca170ff167fffca595160be550d
44	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	299	\\xadf642a1c9c57cf897a9084157c141ecb8963078f97aa840ab11d3533d38cf8649accc3fbb34cdd2825b6bbfad90141ad5b9ff554db2455589770eb84cd9230b
45	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	178	\\x2d5329ecc659e887f0a60e8aaa12ae98e126c1b83744dba27a729f4d0fac56e190c875cbde9394aceae43333ea9fbb5e28952b949b96203482623ccec1ba8e02
46	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	280	\\x9ca33b734dd387094cd036fb33f7b30b0f4f1a034f455e203762e31402e365d97a21db00ac4e37307e138aa071345f0ac294ee9eee5ef891cf89c3461e494a06
47	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	198	\\xf27fbf96a6485e3c14ae5e3d5c431b3b44e980201beceadae7090f8d129744f4757b000c84d6f446fa40304a67fce9f2288fa6dabd2b2750e7adbac622d3d10f
48	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	263	\\xa56feca6a01da6a1999175bf80680d421749e1a2d15864d43a3185d81da6bfbd976c20d0b52cc3ec3c7cf0d519f414b2a541c5f019a10b304ba346888a537003
49	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	34	\\x31123ee7b5faf4be1004076a1a95cbe81b9753403279418dff841d85ca53b89127955f220e7a4e5e93f049188da77e9f4deccb4cd5ee3248aef90f447781e401
50	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	209	\\x6a7944c31c5a8fc3dc3b71291149fcad35e18536ed83c526c0666c9c68b790fc21282d2beba77616024b2140f97bcb3801b3533c3ccb224d7212c996cf36c30d
51	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	83	\\x62f95f8d99e5116e2c91d4ba5089f8cb25a4a2e1a756b981b3e2fb77fca4143eb7d3fa9b5b15d530facbd25328b3cca016759440d857644c327affea4c72460f
52	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	65	\\x9211569ffe52a74b816a238439ec7de6f0a419a42538c0d6342932f60f6a6fa3d3bb0fad9cdb7901a81d17c637a7f09ae8b6f3b4722ef4a72f50b187814d7b00
53	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	226	\\x60ae7bdf47d4f757e6df90eda8c03a008b2473e8bc3b0ea491a9b7c07ca09eb8a6e635b63ff70b97d9a874c478f9f46843ff0e815d5a32be9301d9a28be8fd07
59	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	88	\\x3ce4a24bf0da31b0f140b7797d49b3d50109f87d8e5f3d1281bca9ae6bfdebe3444f6c3f89e6ce4518d57a8d3cda400ce28cbec691e2e03e71aaa53f5d46aa08
65	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	358	\\xf62b82acf2b821d69de0da00988f9f042c33a3efaaef726a3b6036646f3a946dd1d2df6d357b17619a96b988e27319404a76d0e30ec6f1ce1450da563c856e0e
71	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	236	\\xbd745d8dae0eee33c628dd99c1994f5cf82222e659944bbfbd855d7e399d340628d39d4d01987f4b376911e7ba5a01353d937015a243572e54a7094318436904
77	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	254	\\x11d54129b9d1080030cf9bced4421c83725da02845a62f31dfc1c1eeb72820a196e3c6e18627fbab63903c16c520cd7efb98bc0fc1d0538e5eca0c98bd0ad005
84	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	30	\\xdfb09c61c50268b415900493ba759c53256590165973ba77bcf4f3a38a5e673cc377e38ea4a4f3eb04e7e08f93cf1258bf7915bce701dbc06789199429fcc10a
90	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	73	\\x9401dc3a12febe904d547fd9399e6c16d354346e2aba139ef7194a24640bf9483dd0fed4da99370cafcb1b9c0878cb24b6758cda13ef3aa7dc2fc16cacceff05
93	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	277	\\xd53e6ae2717059b39c2ef09813f6802f4cf293e6778a94d8c1f3d05a5a84bcdfc04c2992a6453cec8ab83a0c129a5671e7e12904fe1ff4022b5b8a0ca9ecb405
103	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	124	\\xfad6e7596734b847aca02f3e67745aedff5382140d6091d643c5514eaf62756a18f3ce9d680185bb3cddd04228526348268b49692d576d05f7e394836c0bc200
107	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	207	\\x5fa2692358e2888a6f75de0a975d3582535e63a0bb9c30f0fcb8ea503494c7d19098852c056d21adc8eb0fd0e508d0cabd68f9f772a05f9782557e2c3f19d00d
117	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	416	\\x2efa22dcae21e3d55405d41ad999a37f7e4ae4d94bc45af412022e1accd85ca14a2d453055c77768c74e49c88b03ca218c7432d12e8d8c5c4a4343aff1a49001
122	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	80	\\x66440f93ef66895153bfb767d8c524f4df18f7a406ecb6d68fdf1b7f7c1971d8a07c2240c6b151c83c0e901e495b17624e024446befcaad572d49b71b7cb9009
125	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	268	\\x02ea792581b589e5fc925be2345bfcb19f3e5b312c325031cffd688fb65a9a63276f00bc77d60703f2b75addc4de9a96fd631d027630760d86d05e51ab57fa0c
129	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	423	\\xa701af171a4ec0ceb7e4fb79fd062a9ddd874d5e727b42d5f09fc7790c295718db722b6b1350c5cfeab381b625d8268a837f2fe26620489634e208774b5bb80e
138	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	210	\\xdedaa0daea00af72c299c483aaf02a53f97cacd1b8be0cc054e383f1160597abc96a98c288c0c0698349162bd81b2fd70cbf5f36946f1ebda42f5196cc5ef50c
170	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	166	\\xaf8089e5f64c2ec270cf4241cbc52b9385a1c144eb9ff6caf48b9c5ee83366deaa2dc873486b2230cf8bffedf5dfc38e0bafb3aad7eb7dcc7d89fcd97587b50b
190	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	185	\\xbce899c14962221463e2fd8e1b05c4faa886b6158d4964c6ccff265f8c884388ed84ad5f34cdc1b3518498f408ce49177100862fef51aecd3158c68887b75105
207	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	174	\\xf2d89b27d405812447e209aabcf7aaf37b32bf872f50ae385ed95ccdbaf7a6a108710d54587463ac4956b7b962c3060f9587715f9eda1bebcef8f4de61c3e10f
224	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	20	\\x7cbef7a30f25478a3ef68dbd89a1d281244de1c5097e60c6604621b1d9ff80a6b50b5ae0bd7e59de29f87ef8a3dd0e87b75ad501b0041ef08be1df8bebde6400
274	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	141	\\x9d39abfc3c2f710ca995a45094c7bb6ea91734deaeccf23730a601249c16caf086fdb559d8266f1d0d219b5d513b6a4c22700621fd823c807cc9c85ff5d46807
295	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	145	\\x3db8b051e081a2794c101662894479401177e41c715d240359358141681082230598ee37edcf4f9261fb85512c3ebd7b3bf0595f0104a57814ca5b272fbd9409
310	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	392	\\x8b7e085b325f493542468b5ca4852af337a51552aa5c5f7f5b8c280b30ee6e0f59d626e3cd9c338ce549306930b56d495d3485a8fcb9b41ec34f037f489e7203
341	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	240	\\xe893e4edfd9ce90bdc95043d79d827a1602263d10ef43ed25f620afdd361becbe2d282e9b12fde3d1617d29aa7858a121d1ef97031fbe5e487c0a654e6db5504
58	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	369	\\x15da9594de424f5a9fa169c411bfeacea20840dc90714cad9ff8b9d4b743b91d8e43ec833c96cb5e697363f22fdff571eaa649f36dbaf9d50dca388cdbed5b0a
60	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	28	\\x993de82fd47ca5cdb1d56ba99ae8090aa3a0c09f4c0557ff23df0724404df81f791cb79e74e1948ebbd5a62fa6789af8a7175e69bb3d032dcb648c9451e3340c
66	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	99	\\x844fbf11ab7ef183987208a6d71a9641386cdd362f86c36990bb2c57c49c9a8fde1a0d91277826e09e4bbfedb6556ff3f844eb9df5d4215a4d4b1f9172ac3600
72	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	192	\\x39aec01668c401f8f33f134515215edcc94c86260d5318d4e34128ba68ec3e505aac7b767319f295926031846889609dc9b4129c1969a6c7f4ed799da3b0100f
78	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	362	\\xb33619edd9e6c30fe98a458e4c61367f62a7fa3950d6e7e1e58b71ca290dd296f6942298bcefb9ed1bfd01c733ba7d4ea8de1b1b900ead1ed1568fb683b42108
83	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	218	\\x9104e0caef7f237d7dd060c72bcbd21233594affef25d69e08335969e6800e01eb655b0e1458bcaf5ce0f66d4a244de57aa84c4d72b792b39c828ecf9952fd0b
86	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	347	\\xbffc817b08b196f9d8d9a1142c33a7c6816f0ac90bb8a838f639d7bcdfce11e17b10f04ee149efdb72003df09b2c96f8da2ac26ee0034473061f0fb6da96e407
96	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	357	\\x5f331148db750c7e6f580d698fdbd8ff7943c16320744029b722eeda84c990fc93335bc05507817215a256713c2db7a2fcb69f3a1f98fe2b6b9812762513e007
101	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	359	\\xa80ad145f5b5399b4347390258ee3994bed630f41aa031f7e358d2b35bf4974aebab7439b1fdec0aa54317f2a022ca727e2686d6ec7b0e925be883064f110c0e
106	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	188	\\x6940cfbc9c701a7082d96cbfd1b6c93815293e8cf95dc169053c071b1b573ba4e34a8adbac0586e920e497d4badeb57095f4cc0849989bd1e6deebac8532a503
114	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	84	\\xbb2db86beda7e40cea1ab2175d395a586a0ceac8f3e1f3b867e92e0fc06efbfb86601fe1b40db3ee8642b0b1c8b70852ab786d3a24a3e893d02e171f49a71205
121	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	104	\\x9a2466f6254182aa3cbcd2e2a37094e0041ee711e6094b27f8e22e53f06b1af5d7c258ef148e3de39166ae6d19db2c390a98f695dbf977aed3ea038ded1f480e
127	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	67	\\xa7d18a1f7fc5665d808af287932b2862876e8a03507162a34b4f9cc37cd6ee6449948969cfa58b29ef33f72aad074a07740352b0ae996ee103690ced18d3830d
132	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	25	\\xccd416be7287ea1099de90bfbba5184f070ef59db4faf027debcc5881058768bad63f368e1fa92fcd1d6a34883783f4ed8875d2c222d05a96b65f8f3d327c90b
136	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	334	\\x545bb37f4999ed34b544cbd9dd9ab6b8bc77d40da706c791f9d8e4442c9e20710609c834813d1981313e406eaebfb10594d3a1435dba217b7c2b1cbc00135503
142	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	127	\\xfaaa693a7f8815395b9992d5d3a1a0dd67a260fa02b615b927ef5f6f2ab12e3f8361cc411cb1148ec10742f7712b1e58142a2e859fd44ce9f6f99cbbc6eb650c
171	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	58	\\x3f50ea32501911958b8a3095995d6a8a41b354f450599903790c83147f1ba7e48893b23efd483cbb0166d25e42513afe7ce7230d8006f0bd5a05c5afce402a08
200	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	110	\\xf774206b687deff085d1877fc6a722e4638ff8565974b0f8e9ce94984b54babdf0db90cad6ddcabd2b11c185af4c0785bc6a56752c5ba92d2e675fbcadb10c00
226	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	216	\\x0d17eda7e5f72611afdb412c5b8cc22888bc71bf13fcc6a229bc7d3ac8bf73aea425dc4e60915603f7011b8304cdd2b4a7581b22efd42f6bae8c36f92b9ba80a
284	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	164	\\xd26635f2afae70afafb36148202091eb31c6b542a612b39c153ef6443b00c38566623bb2b3341a172ee24ce79ab21c81218d92d924e81cfb8374adfc1da7c40d
313	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	227	\\xbdaa6665a4f938027300d667d72c0b55ffd701c49c78579cc28701e7ca296f7efcab66aae410b968159230b708db5635a0cf6cf1bb8c704eea31a6767cd21303
344	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	407	\\x0f49cae394ac13fb802e959531636b433a8df23189c3626cfb13a6ec2e3a916a2a1fc481ad770d1dc9b8aca7525aaf5c888b8e8894844e5d794ec6c2e5b78d01
375	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	232	\\x642d9124e9f2ef69b480de2a6d321d6d19cf1ee85ab93bad4bb41106fe8a312de835e816ee09a8dba0483b592b442c49f337d4d52fbb7691724f4a4a70a1dc0c
54	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	91	\\x0ee4ca850b30bf5ce9a0c0d106cc15b8899294e42ed53933e0028c417a2cbaae5275ba2e954f51e2dedba16ee65d4d56752a48df3470f16e83e6c5735a2f190b
62	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	233	\\xc9a942f9a05a52af7d4a75e1dda6e21f01b99b13d913c490f2b36c00b895f9c5a647eccc29bd93f9540b8b86c351c62d52de41feeb1966747d78649b437f6f06
67	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	342	\\x3ac189b72e00da457522f5aa0aa46dc8b561d29593ad08ace65cf312e4d485897ac6a477ec60e89159228bdff5b8d90b8ee93b03cd60fd90dbb663f567f1850c
74	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	368	\\xa13c54b52e6c5fec6d807ab87ebd406d54eed40873ba61b1aadfb132ba8ef315978c23511733be96fd3c28921db39693deafba197182bd9ff58875db0b6f340f
82	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	183	\\xc63016c0ab14c862f5485f59424f298e82cbc0d2382e839223b4fae1b41c79c28c144931a49f1203722af1dc9e09e2230b130a07a6b4971129463b3f3e87b40b
89	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	278	\\x7819cdad10bd1112403792919ce9d3b5560fa44a97b3608dd5d216cb3e55012bfa516440b5c25e393c450a2d5093eab45afdadec57ed6ce622a1c9b7902d2908
95	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	167	\\xee162e19ad75ca6f82470718368cde1196eaf4e5c4a3ab9b125108a6ffa0f155ee2e8c55c5ba6c90db2d2bdd37434c70c8a712956ce441a10cd85183ba917c06
102	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	9	\\x59db0e3a632e1817dd74f9c7cbeb0f91a0a78eb3d93fa4e338c6b1276554a5532216d0853c2c6cf124d1b1f379269cfe1bf165a3e30e79b23d0bb827efcc1809
110	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	175	\\x75f99da48f934cedf6375b9fb5475ab60b9eaa814be4aa4d74326872c3b2709945c878fbac8dc10bc63c33d60d346518401d803c9deb11920c7a9c9c97abf908
113	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	3	\\x50d0f1dcc2ad330c7d36b0aca60e1785ad3272824d5cdf73527bc95045723c967639ee0cf47f0628c81e706ac7c542d5eedde31ab19e660159175a7ae3d5ad09
118	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	107	\\x5da2f47f1352da0e8add43952abeb60335115812acfeb4ed8623dccc1293c2be821c3a54a0a15ed532e193066eec1d1858f8134044aa197a5a00a28feade2509
126	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	316	\\xe3f3b928dda836329574acb2f9a2701a176602b1f888c66d0114583cadd04fa95c3accd26460a7f0cbcc9cf9124fdc2b2bf3c448528a216458eadfcae816890b
131	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	66	\\x1e4b9fb12446bb16dd4d8d0ec9d1abb68c8b58ada18192147614c7d2bec540f00cac2b4783b13ac0cdb140f9f0d7b28df2fa22d196a6611ea325f5fec6b03c07
134	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	373	\\xd14caa40c1b812376cfdb23ab7af3f0c8e55115f1fffc140af2781ba54750beb1156e2c062890214b7c724ea006559eb331466714e32a24818d8c61d0017a605
140	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	331	\\x7efd89e6c518ea9fcae815523078460fe59b0426d283e3a46e32d1b2472491039a2139e6aece01248aff768eabf6fe4a4972770593967c3a14b9cb770c7c660b
172	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	6	\\x5e5722146296de64dd75c3605fe8bda6e5ca2aabe6631e9923dc57751a1e222097ac29bdfd7495c67a4cb5486a57b568b91aed439e5a91004476e43b739d0b0c
198	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	288	\\x336ad3012d65d5d178c00e7e5a346852fd61c1a54305d0c930550dd67eb146a0e0aaba08cc0353d5c075d232ea46f9ebc18bd9f5ed2f70b020d2780d0f2af005
237	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	150	\\xd7843234e67d8869730a1a86b155072be7a1a13de3de69cd81d5bf9cceca492bfccf6fc97380d6c7b84526d85fef218d45707fd31dada136de6c8e69fef39c0d
272	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	64	\\x146c9aefa603f09df4f0b73761be79da78555d23aa61fda8e15e483d6bc5580bfaebf606f9f6b8eda11d8dfa8c2d02ec1daff9369ffe4bb2794acb0b1c0cdd0e
316	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	53	\\x01e347a90cc604079f860eeb1ae275d3582d42f6df941791ec78758099f445fb907a232b5dd9dfdafe0868c448ac13c659318992cb0f3ea907975db264f7ae04
345	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	39	\\x37a1e75073332cde67e3fb8f1af98277543376293190902862808c7ac0dc579c2fa887a175cb63356a8288595d18614a8e876eb1be2156f7d57e1357a049230c
378	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	390	\\x870b9bc7f67e5cd89d26bc28130b7d383849f1e1df1671ba53f46aa99696c05753db6549aa9f8f37b699ddb24ea2207d6722318900281e3f6acf0066f45c2f0b
418	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	324	\\x8c5e1d97edbf1ce7708e7a3c1b0c4da98a6235bd0420fb67315e39612a9eece633e4b5a7827677c878c088fe71a723425140746ce5b39fbd4b54b2055d10a705
57	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	376	\\x74fbf0b6fa7325f8b41dbfe08c4b59eb4f82cb19ac6e364acac24cd25075d7f0cfa6013037810af2eb85596ed375583770745c94823ff9ba2662340fb6a77d0b
63	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	85	\\x32b954db66c29a8096bcdfd7101b9e5ae432fc7bfc3828e503ffbfc7cf8ff4e3f3b3a86a174b0421a576ab2cebeb8098b2e6e8364c5bb461f438312e2f3bb900
70	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	418	\\x8926b6d17075312abeaff9323f1fedcabdd78fad308a31418bafcfccc8d8804476e79a017dcd59f407f26822ac8279e9d699df7e0d7efb216eaf4def5b77630b
73	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	24	\\x98dbbdd1bcb8b25a2f3ac3c9d0beda331ea2ee6428c75d4cafc27c34d7c70c6a909d7b52209ba3d6d815a04a2ca693ef9d18cb749985d744949e89fc3697b00c
79	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	249	\\xf60c620acd520e852364c2b67373cce91d04b9a3a0acc085ee3699b5b020d35857cc4bb7424d79884f9ea75c08d47ba2675f774a9c404878083aa77d2908c80e
88	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	11	\\x9c969ed21f4540973d928b3e38b8fd422a1ab54e5aab1cef712f41d8f4d9b927a5ab3a16e4a5bf75d55645a32dc5096e48ca3f4f08156618963c4f310db09b0b
94	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	255	\\xb6b8461cbeb9dc08dddc4b0db35fb5eea73c00d603b2cc90097ca2412af76c034e5ae8f92b682c8d895e6e55c10a2d0fec897b818e7e0c3dd823c12f8508c20d
99	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	306	\\xd8f39e68d6cc587e16b984e27cf5864405495d14b8912278e8665beb7a02253b9c85cb7b61e4cb6c89a24e8b691111fd0dc7a110f039771df1caf97e1b5d6c04
105	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	356	\\x380261dd9094cfe949e043b0ee4faa18684c5781d40c9fdb07c79f08925e59a80bdc5220b67371d1a194c768bf3714812abd976fb9ac3ea39e9a9699f91a5901
111	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	46	\\x14fb65b147844acf5b5e6971de44360cb6987805b9ec888a0b13141fe9432f97b251fec2204b06725d38cc1c048aca125bf94696320ce79ce6cad3807158ce00
116	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	276	\\xdf6db897d3a22b088bbecab8a95bf94f7df28ae4f15c410f155023e821258aae79bcc75037b0d086a7cb299ecf100c56378b3d4bb680cf6d424769bc20fe5506
120	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	302	\\xbcc6aba8a3f4ce08a5d192ea4c3c7ebed8d03d92d39bb49224bb7b24836bb3c3f4955d9dd6046669192fe3edaea7b5ea6e20bb48c50fa6e2881cf6c261488402
123	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	147	\\x25b6a2222169f723f00d562e00e351a04bc7d84cf6570eef242bd716a8ab62d1f2a3bcc4d07f7dcff3e64d254bcb8a54abd21660e1ff3d3ad15023023808ab09
135	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	409	\\x3448a3a710b40e7bf229cf9c2022310ec2928bd24889e221ddf6cbe575731dbcfda1930ed93d70b4af6a13f3607b7d9b644288ab32e036d9ea2f567944bacd0e
141	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	138	\\xf1640a045b10ffa10218bb4603394c296f44b51a58fb1cc98b252c79613b3b9b6fe6f0e706ba4eca560a898b5813b36e3d2bf1613ed3d140761439f0fd1b160e
173	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	397	\\x600637a7be96f016e31951a04bc63a92e842949923597337aa4cae6beb19c9dde8de13df64653bae8878089d0f63e76628c8ec9bbab996e6d3fe2b2ac4e60b01
199	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	310	\\xf14d113bd6c142c388183ee54010788f17a980cfa94c4d3966c4fab4ac4efcf4e2a89dd336677f1bf333ca60470e2aebaa61c9c85c476eaab24e5b694e452e01
218	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	274	\\x66f9b9b087a4587c2560ad1b7bff5a2228d420eb71052660b1adf8cfc88857390cf8a66d4ef1c1c1209bc7e4d9f553d5f157f58955b5695c9351ee24ca9bb00e
247	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	2	\\xe0e202f0253fb64d76be03580146a9cb1910fe3bae550bb0e88cb473ae2f24f1713ca3ff9391966f44de0d33467e32590189a58c8b9e063a9b75a8d556a9e101
323	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	23	\\x407a39672104598776e6274bc581a2ac21db15eca7f43263ea08672d6ae876c41c8a5f8e65b3a7ea20053dcb688b139aeeeb1742ab1f011f8163336ecbc32b02
370	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	50	\\x23edc89bc31cfcf37d3050083405690389eebbf484e86265501a669a20686e3628c380ed418254b24c0d1b4806cd5cbb11bb51e9914f6fb6f3a30a680f9a410a
400	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	257	\\xa6e2b5a4804a90f6b84d60993a15505e7eebc4a618737b05742e4c68b444af5879c54c19fa1d814c64ec8b46e2e05973c8225c75a7224622e52b795e3f26dd04
55	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	125	\\x58e9186efc1f4a2646398885b85a706de0dce7619293ac676ad817a068290fa65b0aa09c8a97151d050e6d909cc327e96296ee623e77160b93f110b693745b07
64	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	13	\\x8ffd0a54e09c7885601264cb153f2a6a3edad3b4086354b577d6b2a0b9f0a635c4979e3574a0f386ccd7601aa6b5118bd0a96cf823a1d311a6b5932f8bd5d906
69	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	71	\\x1b0cfbaddc01c1d37e185b769327b0519f0b9433452977d133fd9138cf8ce06c0c7b1961e5af11b019f7bff8c19dff8823c3e0b6e041267b598e7a145391d906
76	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	18	\\x0d829889d56cd24d347922801e28792b50f429b1cbad3d152da8ad4f40bf18154192238ae30a038f31b7f51879fee49a34a52f46df51d34f0a81b2d42c669a02
80	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	421	\\x575f8f2f022175df20b9292cff15c6b766d057a1953d84d5b700a109ee26d19db60a8149f6e606bc0ccd02a32dd5c512f95d9ae183c492ced5dc389f6ac9850e
85	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	131	\\x61abe6b3fcd6e57bc3c41693b8994c1884607d3897363dae3d4ee51a08a2040b44d7b77d9e438039f8ca2813c0a9f6936bb72897eafc80b23f7d0ce8b72b8108
91	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	402	\\xe35088b23baa922cd70685e94a5ee3570d28d9b26480e1a5ccc0ecfc9c7328874ecff4347cf47964f8798dd88bc731c9c5fc08a33ea88d36591a06bc66f1f607
97	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	266	\\xcdde55c3e528dca97f49791e563c6713ce862e07eb4258c0a294a7a442fa659b58785835f18129ed997a59714d2967d21b4bd0aeaa49b43a9041cd3058499a09
100	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	43	\\x85bc7a06f9efd839b51df6e8f20f6e164b1033454d52e8e1f633f8d4295714697611e4ce0184437ae95fc5b780bf18527a7e8ec3af37534ff6c6ef37c8265d04
108	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	76	\\x19e3febeb797ba14e37b658da4b6e0e80a89f81c696a00cd259cef7f8ffc5ae182a499d807e76fd9b838a581699d233b55e9958426617fc81835920ae4928908
112	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	267	\\xb831c60d04d6d0107b36abb3fd810f72873bb3fb1f5b208aeccec92cf945ceed6784f659b6cfb618db186ef4d02da10b7b4b14c3d749bea9b22a36ff5038870d
119	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	413	\\x6a4f0043397affa73cddd0dd9d8c345f30ef012e7c77ea8ba568e0ca286839bf14163126aafeb07b25d6a0c83d765cee64e2bc77ef74d37f0e39b95169e4d604
128	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	155	\\x4f3dbcb87a20659168c4ef0fe29faae57ad97dd29bbe2fbb7d0ff81782fd17f5d821adc871a45e652a201f4b87b9ee64358de4c3c3d6263ef036b763724c720c
133	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	186	\\x1d831dd18ffe451a519f6d9830fbed7f30a5c6448331f37c5ebffde10b640fdc89eb517bff784a4f2bac59f68b7dca2f0233aecc76748263de7a3d0d4a465804
139	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	189	\\xbe42ea65b7ef0a255d320a16edf6e58d9b8c65b8db6b25dfc1536fcfd69fe6a0723752c02bfa88d405ffad2ebca29e11b9721e7c62367a59448c98443a14fd06
180	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	281	\\x245982813de53365baef6cc4634748aa2aa368af0f451d81cc91dc9a4ef01df396cc4d8abe2ebdd682111341848a5036615ca7aa3bdf62f087a121c6aabb100a
213	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	195	\\xb2478d690bb75c56a3b5fd14f42dadce5feb5e03324af814ac13c1592f27bdf9472d430da1ab38465b6bd7e68021e1fc9831166447771bebd414965c6e9c8806
235	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	120	\\xe71dec470be58c569b54cc0ef168c94c884cf6badabd72b2a68cd89bac1f65c0551251ad5424f2721ca91132efed78021ff69a0f128381bb7c4c602b895e8c0d
334	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	424	\\x97c34725ef4093fe79ff54ee019722ce4eda7ebd5d8fec5d95dc72690bff2c5bb3adf6c870d6659b83719ee0676dda6f5be730f14dc00811667d16af3d900003
355	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	261	\\xcd5d8d4a9952136b216397b7bf5a18ed13b7db8055f4ebfbf24bce891315c1ff2fc577988d9cb99e23172e6db5b52586c2094d939cbb7ec8c864254279b01800
388	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	405	\\x1233d368a9a709182b296e38a1a389edae6df8ef5c8ef00eb74436fe151b7677625fa633b38969efd51cfcfada097da30082e1830f320fac6f5d9ffaefc81000
144	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	417	\\xed1dbe1ab609c2cffd6ae542a315f411b296de5f69bc36f3b61d297832cdd172e543aa34baad4b67e9d81739d579860f58dc7b880a120eecc7afec2b24311106
188	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	394	\\x5068159fd716c9f56db205cb346a42acf73cd295c1d9f5e64ca11a85732eba933ed4da4f6bcd340becbe9c8f80015cbccc69a517632c9ea2cd078dc17e422704
221	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	420	\\xe59ad4ba845e5d6054c6f6667266b94be540bc1350bc3ee978ea74d4b30470fd06aff05a5eaf20c7b021d160afbb87a30933476a9c3f73e187d3dcda27b60f05
257	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	290	\\x5717f4f02c904c071d1c59d8d2192e476f6dd60bbc2b243f99f7bc0ca1b09cc004f4ce2b7a08758d562dbc0b18ef76054f4b8242757e5edfe64873e499170a0b
264	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	361	\\x24a92071151660d762b02a9ef8c8f1d71df4f9b4fe1c006044a2243e9fabacab20abe089511c661f2ddfbcdb58c12f116fa7365af1098939c5ebd0f5e42d9b0c
320	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	322	\\x45ed8c8065f41215300acf6c7a2ffb657e94814fa3206fa059c7a3818f0e730d2e136fb6e7931c3235156be51ce74129b0b29e3c2f91b5c61d4094112cee830c
348	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	45	\\x64b56fc2c604b137c75a82271713f96b92066284c771262aeeeaa980d9495dc34b21b4ccb47206dd0aeac785f948155c352706735fbae5a6079675924dea850c
382	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	158	\\xf39b9c8c22332ab4ba8aef18eaa3672c46066f14a36aa89f3619fde9235c98199b4ea51955e118a5ea9ccd44cf4f3cafe14f0900f02f5b2c1774e8e5982ac30a
407	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	382	\\xd7928a9b228db3303cf9911103fd9884c7305d9e810e9c647dd49d867aa3d288881e00354a22dc455ee1ad22d61cf6533c1569ad0afe82d5658e3c975c4d5d0b
145	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	8	\\xbd40474ff5be306b3d1da236a877935725c18454ebfe6e2174abad2722fb2f4f5bcc3c6ab2d4e1647da6dd42835ddeb0b29bd922a0cf61f314ed4ca9e585780b
201	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	14	\\xd03b6482c4dab7b02374c6caba9c49a6b7dcf9b1a9d37889b2e1df528c5cd8e63ffc73b982aee15c07a04629b7b50db1079ee526863fe133e93a61a1e3c10801
239	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	95	\\xad60fecf6a859acb2b96043995adf92111398278e48c603418626fbce57053ce31626c8b5d9a0854eab95761df0c89b391a4ca038c8fa7a1e0dfa1906332a50b
278	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	371	\\x9f4f178cf5d9245da06c83bbf3145fe12b4a285c8c47e404298a08520ef7537f9066ed815fc91e85f85efd9ea0b3525af477350747e1d85478eafc6a466e9002
335	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	363	\\x291ea03a602b290764ff34d05c735728411487a4bc8f1785ecc98c37d3dbc023a41fd473264b605fb70d190ab6dd45077f8b2403ef86703f5025964eab1b0809
347	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	400	\\x7b1e935d20cc907fa69ec49f76dad3d7ccedf70b6ec006b135f1198dad8866ca5bb39c42d3ccd0e952e95aafa586cddcd5f940d77e6900981590cb128bc2eb0c
392	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	96	\\xbbabd578bab443d2033a4e7d92bb4c08d393a0c9ee9c665f34669dc4d64372561a0d1841674f92d63ac05a06b98dfd2e086ecbbbe41d78df28a886c7cfbe3704
419	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	93	\\xaeb6cdade9c5097b8e3bc78541be61fbfdb355dd42e36916d7c55ead0cc11986801f2aef99b6000c049054e2fbde8b20ab0bda0c55762524fef8c6877e9be008
146	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	307	\\x9f5a0901c314e399c2215a29409185ad6a1c3f79c3716e370727bf8a15c25b6e8093d5db3c542ccf50fd07d48b2f95c637b72f30dbde48bc4dff7b5bf28fe909
189	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	119	\\x1852effef9d6b71088b0445cfe4a9e64b625c32b035cbfcac6139bb16bd6069a2f683121eb71291b58a9ecb71badd0199c03f570d89ce4effa98fe149f8f600d
225	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	339	\\xa7c2274d02a753ae8afef49d478475b1808bdfc27350ba58b104fe2c8501227908f85e2766cbcc8fd4d0b2b0f8a908f37590d9869016f5402a8a05d13e35940a
253	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	142	\\xcda4125227e48997ad39a319cac50852ac8becbf490e1f10c809d933c2ba26d449a9630244441791293eaf69b129bd0e1898c672f1fd355773eff38898b9dc00
288	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	184	\\xe6d5e750a898342c2aa2067e6146de5547ff1556a381d227b43e49c4f845f9cc10bc1ba623e6d5772ef66723361b2cafe81688a5f1bd0f65888188547d89b90d
303	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	337	\\x4ea491bcc6f8265d6c303576a89f0f2443db2e495d649c1e4fe7500ec1dd9d42342d7ea8f773d56ee13ce859d99dc20482c5039e2594e58e1824b97421209b09
324	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	78	\\xe926567815113f894d2171c15e61a94e01ab5296d58f0d61d836750e20dcc4b4538353da21673246c3f834985c610e3f3410828120fbe045a1c76f1eca052d0a
365	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	289	\\xc9daa6141c01883dfbce30aacfb806c19ffffe6e95de5f8fba98f2795badf254a72d6ebec33dee621bd2f524dddab7590a8de1f1cfcb905b7a4bad4dd0aa760b
398	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	270	\\x9b4b82bd70964aed94326f2ef40ee36c407632aec14dd7e4b47c82209406951ae1a2f458b31b7261fa85623be7620f1b9d80f9225cb227b8ded791e09fb0640c
147	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	329	\\xd7653e4f4c3c884afb2b97647c87f00ad776c5f0d84e09dc3e109473260277190c8d500be2dbe8c59a0a4a0629711a4985489940791bd3278e08584b2a4af502
185	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	94	\\xfdce217ec7a259069e908286e584274b9e210aa6879912c4b5166fd49d4bd411f961f4337df3f1038844252f8c4e296430ef616a60c4a9cdeff8fbc437c99c06
214	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	17	\\xa13ee794578628e79830d9b35176ab90143ac76684a55c8866ec90e130b6f61acfeb70c9e754c4f53d4a57b1ee03431338e2a98c4c155ba1b3053a7a8cfb530d
251	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	59	\\xcdc5b4f3174ea29526693d2bd55a6330077fe6f117893aae7b7e22a45fd89827aec5ae86df690d1013a75a4daa758ad6c738cb2207bb13f4be60f40e105c670c
297	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	29	\\x909ec6671e9d5ee29894cc2af113be47353912b0648b41e2a15f870fc59516783327deda40a0dc5cc698ad905da4da59598ce142804d4346b1033f3ae349e30e
328	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	244	\\xe7307c632211db88a4ee2a1a873588996594cd342b5c5da31425bd174a9609f5f9fd5b124632c4c866b5b528fe37b0f46a3977bde8d4e910931e86c35962a507
364	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	44	\\xfdac0b4a357f58be8275e1133ab963f819a0579c20dbe970a0919c8db06c98f9e6d730044a9b4c207e00db19f790101b42805d8f9b51ec5994ca2350fa683c0b
393	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	81	\\x08c943e32b2daea837b21de4b74d0473630bf7821fdfd896c5e1c7b5a5f00d564ad4bb153c7bc7314474f34165c500f3d10cab3a305631bd7bdb80b7327d7a0b
148	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	79	\\x7cf2f3979f94d3bd74a4c16728b3f2cac68931e60f421585f5c27d3684371c6ef2686d5a8b37456cbc33db657cc76fde8392e5dadf45c235ff40b29c1e44b40f
202	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	203	\\xf876027b0466f03bc701d6d05e86c1a843c1c5c6a6d014249fc375a978b84050279b8119e1913ec272e95a5e2f5f935401c31f7111c07e00573517fa44c67e04
252	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	10	\\xb1be96a5aea3ad26860aaac68f4a91b05da7e72bd99db830f1f9702cf9c7fc363e00fdd1f5b67554580602dae70a50e54f5519989551ece9d3ab3c9549225701
300	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	374	\\x68876097a277eb6699c5a3e22972ba0860b27f06ef64aab335b59eff949c64f038499df542a5b3ad4df18386e8f3de447d75933ce8eda52249e3378f91143b06
322	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	272	\\x7a99d2c318a983b3e8e70de9519262ab2537e1cb79df15abc779d57067905f9ce39c1ea951d0d7df814e343089608d9f64b4076aed85a72c49c2e4ad2324dd0e
374	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	21	\\x6fbbe62a2514f375f69a804b53df1cd32827d8b3e735539a56844c6d6dad1d63e503e13395ec37b0a8a4aa82eb752f3c5429af4950a49f3d9b6c044ea4d28304
409	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	326	\\x13ae6266758b84175652cbc4aeef95dd56b909bc66c658592b25ba27c83ec0532dd1f07d3feedb210c2b73bd24f1497f6895f79c77f96a1013c05a9fd65bc70b
149	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	325	\\x572b24e8ecbc222ce22c47a4a0432ba0d1ec4dc06134bdbecd44cace8c32108dd99507d02cca57fcea28fe92f2090361a7ea9a089edd81b6eb6b70f67ff24908
184	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	213	\\x96e0d167674a66055fb330f0e35c7f7d37cf95ad4be392902a3298525e75793c190823abacdda1b7e5d953508ebc7066f035413b9747f238847fc42e09572003
227	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	160	\\xbdcfd774a960ab6efe5613bfacacb726c95480627c302a4e2eaad82554c232ac2964c4b8f8860201b9bbf8d08fc3da6e24ed6f8362c30ae650ffa7c1736e350a
260	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	190	\\x7a4cacc3feae341ba0b396f9d855e505d2aea9def8765710b239ac30146ee4b4fe0a87ba882812599f913a9dd68b659ada3bbf6011c4b383040c0c834e417704
263	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	294	\\x145f55087139b2f7742a1a8589319353fad2f2f5018881b6c32e3c3a4ae50b0fe91ec1c04ae1a069a330503c37542cb5ceb4b4e1482c989713bcfddef69c5501
273	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	68	\\x2ab45a3735eba603e32663ef0d0dca9aa453c9873f25ae98da5146cd9625bf8dcdb887de7a7258615da10555018acb871a044ebe6ca64f35e46b8a83d734b80c
292	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	292	\\x60445bf2a1b0a77175ade4d2dcb734c9377ad5ac90a895843937dd806d6e6c4401b0bb6ab137f8077bcd4f3e69aaf5e21eb2607b5e505b1456edf912303fb30c
312	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	40	\\x14f63469100e069865741a5b1beab07221ec1016a838e3353023ab788acf5c16727ac9cf47ea755cb847b67295ac0182e748ca59e70c935a56b606cf2e692804
353	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	387	\\x68310d8a0b658e48cc759aa9782d2a6582d8349a9e4e24bfe1ae7f31b49a6774dbb1000a29916b379d29439e9809e101f153635bac521cbfa1c493a1d9adc307
379	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	152	\\xc6d255a14d6ed5c387fe17f017ec227206fbe036edf9243833364eb92a871983fbca873a8b25982e21cebada33343c2eba7de19dda463c8502a70d305d416e07
406	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	415	\\xc3d72d99fa0bf09e5e1a47a4c2d6df8c496d9bb4ad4d0a0596dffec83bedbb3b726d5ef43462d9b90743798b23c72eb2e19be6f830342faa632359fbe5000208
150	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	238	\\x5e7813b90b27d67eec2e24500d0cdbfdd888c00e8e6c5b94f31288de6da4bfc3fd251bea5ae733b66aff4b886904fad9b3ad5534ec256bf9edd05200a667350e
177	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	300	\\x0804c794de093d23aa2198878d54aececaada75ec9225d85a9c5e0d91bb9f264b7e1b656f87dd4207829e0bb3555e57480ea0916215cf60b88f3309804a7830a
210	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	235	\\x74595bb1c62dbcfade1a92f958ba0cea3b0ae1ab72e93aff554f3a4b40a0a9bba59483fa0f2a24976251d61057767c74a19abbde6bd0d35ad6e99fa3eecef206
245	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	354	\\xf23fdab9682a8a7df1aa37b52c1d0a9827a1f45989ecf033885c95f9ae8c43cdc7ad2a7818635f1025ea43133fdc6de47ed838713d2419e230aa23b1bbab470a
282	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	182	\\xb47ccff4bfc65bd95c63a13527b144d0e9aae5ab335bf05c98b616b5beef288e3aeacc216fd13e0386fed9b12f7ef293a16a14da8f8cda17d4fb242ba3d74d09
308	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	323	\\xab2b686f029f1d0a9c99c7f3d9f001ca5fb53392238b37ef888fd811ebc3fd80a9c2382e97cea2b24c1160ee82f83553acda748e8ecea72212d7ad323429770b
339	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	293	\\xad1d39bc3eeb062c5903ca82e678aa44b16eec06ad9bf32b80eb47937dac0cea20b34885fe8a270282e42c894e8c78c7f36ffde0cefc94e67b2290a7aa98db03
363	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	243	\\x46bd8aa5d31bacc7938e0626f76edc00f2f4c94124fefb51904191707991a79cc404372e2f0efccd3e2ed835c334cdfd120cf3f28f7d79445c0b1d46bfda8005
391	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	89	\\x94a8584e73a44c23973c72e1504f310a802a3b5f69a562b1a7dfdfc913704f3f66f1dab1b2e92a1bb5bad791755a262480b8d63d96cedb3b8efce457d1706305
413	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	246	\\x208e0db188127f558d87afc56804ae8561ba05eb83d3dc1d104d6cad6aa03fd0489bf3e35f596c135cb3f5fedfba9a9c5834f9d6633c8c2922af4294301f2a05
151	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	308	\\x02f9affd5c3711342f693f4e69d7947033dce910a9989bb439635d9b47d4ec7d9f5835292b973f5cfd0619509270993c652a002953ef707fed0ae74636e4830c
196	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	116	\\x5d80287cc726612cb61adfcb88bef35d4e4a26ff9073b8ae716737a93a3dfab405e26787783a8bc1d37114b98c79f1ccee875e945afe8413fec2f780e0211a06
228	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	97	\\x0a4f61eb14418d0d9a21e4ee6047d0cf794f725d40ed587d6d08f3f2cad63f33bb2c56adc0523f72f76dbeebd40ce662555a26df2f33ea601206902780200500
270	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	42	\\x42ff97ebe3ed10a5b11b294af7a9cd0f3bae0f8eaa889bf7a963fbd1c773eeb8be744679402bdd88a686163094dbea0289ccafe2dffd12c6095164b0b1350e09
285	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	19	\\x08c5aa1fcf2fcf5b4b8833cd1953f2c9a92747f890649d230829d7dd3b297220bdb80899b3d71430d08ae70e1f9486d30e0134f4130660e0a81159d67ffe1409
327	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	258	\\xba04ba9b9b713b2ffa8b4404bff1e08ace66165ca82b090569ab09061ac3eef212f412ff9419df8ce55114d0822ff0783318eb387f1edd143ccbe7f3999dd20c
356	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	201	\\x1e603eed1b45a7321e2f965a33279d27eca60287369a734366fde988f25837d669f1f0b1034690b0f9c03e2101affa232f83cabbbc0bfbdaeb0515837503ff0e
389	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	360	\\xccd35c8e74c64039ace87a9738f0ac4c7b1ab709cc276f6b555a7b10cd49f574ec4913e6402d915b3a6dece4de11833a95693fa66ed89ece5f73c2b8d00ffd0d
152	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	100	\\x98fb8a0797b1b46cc6a4e638e674c23da7182213e6abadd2d228205473dab89f597ef76dc9e0fc23313000f2bdb01420392b2ceb047cda56e5883b1898481b02
197	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	169	\\x900a65e1b5e1fc1661c9fd7b9bcd26ef9e2e3cb3c36325dd969a5b8b524d860b905e51040ece114067e5c2c6e78075c8fdb38b99aa41d959fac3db7eaba86103
236	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	256	\\xce48d1c7fe264f2b163009b4f12f3a2324093a9f6baf708103157f1f450c8cd13299571b7c393a712ab249866b43f8c51f88fb86c09286cdce3d8fcffefab80c
276	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	375	\\x5bad394b30e7415ca062e990ddbb76fe129e3b3fcda9bcef328a928a0590489ec9736c7a9356ee056fec1409dba2dceb6ab81b53d2bd60cc9ad6a259fad7820a
296	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	215	\\x4041e86754e8b957eda5ca6288dcc1646c0993fc0df28574ab03d7fac06a9b7c39336528bf22edb2e1a767f11d29fd6ee445687bd0a0653c31804ec706a55405
325	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	57	\\x80f350c2d2dc5cb92c95982364ca99a939fcce9a624042a611e4bc17fa53085e55b372011c71f7678e6561fea248f61e66d032f96dd006822e004e5e55eeee0b
368	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	340	\\x4febbc8fe305851f1ad2ddd02cb206aba4bef5009e0fdf6bf37853a0885e5fb501a79ceafad6d142448ce09ff15112cbe08c84d75e0add4e290dc86cba2fae00
401	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	148	\\xf327898d0b92f85ed7fc8146a7e1d20f77eb8cb9258156af7bf12d62c979331a58e3419510a20a711ed68b66e84d97fab65ad84a515a86172a3d5007420c4609
153	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	312	\\x1d4092aecb4e8ddffe567ff3cefe55f8802d05042245e0effe93e745957cf34d061ca4fc0f63191cf7277a6287251fa0c5f5d232851adef6d7c3c56e5cb17804
186	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	242	\\x7b81c67a07dee382ed4c07bba98a0f5d465e6377453e400d27008edc12de522fec5d65f5b0f4f1c44b1099481ff4fde38207f45ce92b1f90efcf5df740dd9103
212	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	253	\\x798cae6b5f9e674b1e32482b39a1fc781a0b066ff2c82eeafde8e975807c5430a4cf49557a3d2d59f512a8161b06857b20532e5ade5d4fbaba8867cb37aef10d
249	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	5	\\x825df1f9d6ba87191e4324240107e0453463875c73e9bc335de5fd86551c81de7334051d6e698effd5741e4140ef1d2a071f1cf2b49ddb5a0923abc63bef6708
277	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	62	\\x31daf8c5742fa124f3e5e6bf0455c4571b2b11ab85133702789d369e1ba39c79dc9b0a2589912aa1a9f9991f7a697366a5cc3231aa1e7ca0edb547289d8e1f09
311	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	262	\\x4e9dcfe0cf5531d16930d9d2b58c2b70b08f15389d9a680d990bd413df749c41a5a958006d7dec09b4960ac1bff8d30007b370fb4b93471fc56a445fed8e1608
350	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	128	\\x11a4d67679682d9629d38f406a8296a284f84eca54a367af7d2f62912acb68b7ac9641c786f41dd7c145709ed17ab8fb69066c4366bbec2a8d2312ae2ce94804
383	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	378	\\x95483bd2bf5d805cad0842b513047ac02a670ea80f829a7f08eeb358c7fc32009a89935f5cbc49f740b406fc8d26d67257a72489e16cb45adc6d86bf3bfdbf0c
404	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	170	\\x12eab628dade57683509f8b825e00d2362abc90c21fc356fbe8c74127c569b414c4084564da00640a1002b9791c5e719aeebed5c8e34100ebd259d6da5c28106
154	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	321	\\x04c559300baaa4cb581999affe451cc56609fb2a40c28fe4b24d32121f4ef1f9046d880a35a1c1874aaa665b6165c6af4fd055cee44235f91684de00ebedf90e
181	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	370	\\x7cc4b690c690c12ad5e44f8c18c2e8a711fdf2535215210b443bcfa195fccf4760b8ecb8f2d18f25e4ad88e02d78cd2374d7a98802158653edab45fad687240f
215	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	126	\\xdf0e8d9dde41bc1c2e75df49642f41e24dd953e036205ac297f5e3160bdfbed9592636564159a6141ad9d65304a529ef3e3b77809309b8454b98539d0d9cea0a
242	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	149	\\x7e7157bba96d2d02444b0e543f8f3e4fabf31626fa233bf0de1d54f2768d6b631bb1d72d04ed213ed6d248f85519680970229e859465876be86d6ad90efaad08
266	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	283	\\xa9bb85478af09912f7d2996fdd6aef4bd9015723c7be05ebeb4f8f29b1caa604e2fe4623bdf244f229da5c7e433cc697f8cb82650c275159ff3f63264d996c0b
281	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	247	\\x846aa27fcbbabdd53bd65f27754560b5b9cd38cfb75ebd480d799e60c925b8566cdb29c828e42fcd538e382f1b4b98b0e4efe16db19c2d2d766a19286c294400
321	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	414	\\x9de5796e41e402243d19cc24857440fdb679a5b02ed9627cebc2a116aa4ea9ebf0f0b083f8cc3e4af7b1916e69413829e7441c6e30f61c020b321043b2cb110e
362	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	252	\\xb5420a270bb135ca6a93c8978323830827c644d20208fa89c6dd15770fe31b2d2d5bf039ad5110817b0550a36446c72a6788c81f7633a890f3be771d9bc32705
405	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	179	\\x8d300ad313c73ef1f1b594c234a0ddee79f6ad1570d5d2f700455f9f0f585a845075bba4c2ae1d89d32aaed4685db744d138c4dadd86b603e76a6d7d3b129d04
422	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	41	\\xc50b547e11c830382ac8fb29dd835cfe5db8a7b2c9a9838dfec819caa09818191762f61a20315f3c494d741b2a107508f173a16c278284c0d886231796152809
155	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	388	\\xcf6c4cc995cc6751388ce2e2f0c6328223d6795137941cc0a3316358bce6f44eb6ead069444bf00a279c83f5ac2575c3c3e7852c0d91ecf66562da98ffbbdf07
182	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	422	\\x698c53114d087d4e2cc79f45fe5b74a0e5921eee20c7e0d01e632fb2f86ca9e6bf880b7a7d27e9a90c3976ec3a8201312894ffa5810de744656b476e2cbb6205
223	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	406	\\xfabfefb610c55222d1761af0455d3097a9e80e53864dfbef8720447da08744def06e3b8445251b16c25f196491f6036d5363263b1b1c38960335dcc554a53207
248	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	228	\\x4e0221ce7c8d44f40c843851e897ccd92e571217b6dbb1f8c9b55f996f67c88540c0e75f84f56f2fc1bcc97fd7691f2c3f49e12afac3df7323568e123d4f190a
305	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	153	\\xd828275e44d3f857ccfd741c9e904fe27ee409bf347d29b568b46654e4f5c2d0fcaeb527bbdda42f1f70719ebdffec3021c9f513877403b62f45542b60e33905
336	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	144	\\xbb3e63661bbc8d8041a9036d27a51a2e58fe456c54f8f0e0009441c1a09ec32756ba2cb65be37b9954819bcf541599c2f355a8345fef920040e9c4bb15e0b30b
357	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	162	\\xe9b0d5b652df388493d06fe359cfe8e759775b8ff07e94a0e0e1f62dc5d7144a89decbc0a8bc27a9e674126fc5f74e29772b553e2addd923959e8a2525a8b201
397	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	69	\\xc6d574d60ecc07eebb535ef20a7a88655d4bcc0e3d7809355980eb11a19d11fa05064eeb2fbe3d3817efa801fede8874ca7996136e19614548bec8b4fe3e1505
420	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	129	\\xac1d0b09c961154220ef71a98cc82252d91e63c325c83e5c8b4a796fdc28029acc17be4a64037541c853e5197423b7e073839fc0b177f4bb00da287c9ccb7607
156	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	230	\\xe1ea15f82259cebf7b441cee5661d84a62ae33df08fa1b42cf9eeb272151cadaae61c8e70d7c39ccca654d9e59b4308a6c7f2d0e2c845ce2f287ee7846b7ab08
179	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	372	\\x16e40cfdc2aa60d2d6cb4db314176fab8d06c473761853853b87fb025158f539e501837c09c5acc7fd42a7675b13d189f76110093582369d7c9b6436ec16d102
217	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	365	\\x0d7f00cd2eeeb5e3c40f9c95b6880c32563f43863d8234bf396a23956b64e9922ece583286bdb64f92248ee6bfff25cc0d2b58417b0b912c4b74df33921f7702
259	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	275	\\x3d5cf5e4dcabc374a2ae1836b41c54b92e0837b65b3070fd5d38c5e11a3e5ca79bad4b661ac00f4395b2ecfc6682dacb174485bdc04543d69b3c14a98ec23907
267	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	377	\\x241eda77ccedc62bef5a5b2bba990c3cb5f7ab105aeb235e898a2723b1a48d896daeb138c07eb3029c1efaf6cc98a97be164ea22bdd3e1be950557f269d2c906
279	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	330	\\x6971e82d831578904995c90e8089997c12e412057a1159c79ae2c144000fb307c68229e4ef407d5c798b02b4e62eddfacc7fbb5987a4f22763af64486b243e0a
319	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	303	\\x7b65a70b6dbae7c5073d99bb2a45062d35b3cb253d07e08f58012f5b46f97a65b7c83ba82b5f4df83cbafd39f775c613f43377908d85f486bd5f5a8f6378350f
343	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	404	\\x8f7b37d4e432d3a26e6606aa4bed7bd563fcd4b895e6be28a4ebf99c1497838b1cfbe2fc8939bf1d290c58b24efc4d10498b6a1d8e8d95754bc40c27fcd00f0b
372	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	399	\\x627492ab89d3f35aee681e6f5601bdf2922e3ad6a6cffe7ccc56aab1f93838db7b634eb53c30c10d4a84d494bf44444a786da3027bc2da9ace45d503086ffc0c
394	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	248	\\xeeae0bdd292d296cbcd4a182e1066af644a902f9d4a26960d567a1101709bb188ff9780f69028a05825a06c03eda84d37a083efbac4ee860507590a9f3d05006
157	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	202	\\x5566e8c61ba71ec22c9b9198377dc21d7a1ed557c40764bdf09efe6422bcb6ac7353f46816cd3b86767e424c6e1ac973ec84ab6f21f42ab04ab5d82c8e30ad0e
191	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	171	\\xff73b999fdf0ad610abcd1d7bb04e237e75a5da49f83c7d9dbe84593ae23e50d6fedf3ea31cdeb7add07f8971ba7bbbf4824cb2c1a54211d1c8c628a41196602
216	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	204	\\x6208da6a5aee6ea5ee38c5fe6367101a7baf27f00c23c7d8900502c2ef1b095a2af7eb0f5b14959d9ed37efe88cdf3dd0b35ef65775754f296bf77e8bde17b08
241	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	156	\\xa451b838edf23c4ac8b806896c466a38654c36d6eb188ed1a3cf27cbcaaa5118d7983537efe56172396a5aa41550215b6f6f94bd8cb1238a3005b5e7219f8e00
265	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	219	\\xa08183198be7fd194810a0d909b7c3071d262c0c698170f068d62e5d58dc9e133f3699f8e83eebe3a1dab54117e7d7fdcee9fdf461d6b8bd925351a80af8370a
294	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	35	\\xd5814105a28853598acac450ff0a9c29a85f3bb92d07dc53b86d76033554a346c5ce0ceb5c45c8170530d5a6ad6100398084d9836cf358fcd3ace1d62705d80d
331	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	7	\\x2254fbf3c4057750c9d4b45fcc19758d426d0bbe070a58896a725ba74ed9827599978177fb060c8bf6f216e7b1fdf87ba85b72266a01258067958bbf58b4570e
359	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	355	\\x3d537d28d06a6b0b64bb34d4dcc11f536450308e7843b514ab6de0dfed53b81d6f59af965cd26cebf6bae6e2e87c7dd69e6fb0a77a8d0e370d7291a442085908
390	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	348	\\x8c861290fbbd100282e27dfe5d0b377bc53aac91fb59c6edf3e3c33a0b5278c02b4cb292f469d065d81929972b48aba0a6dd078ba00dbe14037a210af8f4cb04
158	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	241	\\x8f4c09bc84c5bd00fd9b531ac95e5394484145edbc00a5fa3ef9415793c2996db94177d780d54f82fc836fe4f157528e4ac974386d5407ec91fc5e5baf300209
183	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	223	\\x71dcb333d8ca78ae57ee5a1591ad2926914cf377177c236d3f262fd11f1bbcee271c66f5d903e290ccdd5c450bf1cc6bd79b534235254631ea38ff14d0cddc09
220	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	103	\\xc4d6a16135288111aed23a5ea16209a45888b2579ecc55c585c5ce0d0bfe62419c0fe9a4a3e9d2f990edb3d0e87b706a759c19cd4533e234579439faf46f1f09
255	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	386	\\xbb914ac2184c0033df709b0137def07579531740e48e3dc240b0a37eea030eb7d7a6c10e257aa366d8f7a33568604122c9aa794610c075d93e545bb17f2cf10d
268	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	176	\\xcce8dcaf1477f2c63fd46b19f31d65ae2158853ec69155a551a77bbefddfd4604b28e8e5ad9ef0433afef20cdacc7e86fb8474c0449a238ddfc273237291dc05
287	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	90	\\x9d1a5536e2b1b86206b0cbfd9e66f44bea83dcdc15eed1f2b839762f8b43b45a665cc2d9136be5df5da35ecc4b7b5ff2c2f1e140c27279f1cafb39092a02ec0a
306	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	345	\\x7e11ff416d0bcbbea6975c771fe19b2ff47124aea41a63ec1d91169358e9e8e69e9eb067a9d03e1d1e3a30bc05f73715c5f3d54f6ff19b62feb2db9566106701
317	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	200	\\x270a362acde2aafa46d551e6682a10e7208a40ff2856121cbe19a801f0b9c383e07012574fdb57b4aaa771bba27410289c5195a4df89600f0d6744ed9c5d0003
351	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	379	\\x27a7e6e6b00b4087fe1aae95bc56db1858e3e4bdb250ddbe79637603be225df1a3d414b52342db2f1cbc5407a986060aab01dec5574009ae0a8b5ebfc3f3c20d
384	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	366	\\xae17bae28c7da16f613c0266d8c6d8911aed4bcf2644fbe457559f15f809a2e7ffae93089b53566a68c256d92931b70a14d7bf27689a25bc5af28b56d1bd790b
416	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	412	\\xac1c3eba16f9aef6dd58c07e376bfd34700621c7b6857ec53d14fa966813e33e341a73952fed4c3dca62185dcabe6dd53b99bba0b22737f2da9d2de82d634a02
159	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	265	\\x7a5b4c2c540d49857c1f0c83e687428a320db7d83138c1c8085fb3e231377a29ed505abfa4e1053903cda65b70734160d3a897a0ebda241727279e12b34a9c0a
205	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	251	\\xb0d6f42519e9837513104323cdbc76cc31e88cea40d141ae2fbfd736578dbaa063b2859b7d64a34322b496a893c998cc96b1102085686c216ade052003323b0f
243	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	109	\\xabc3668e532239bbbe5cece1add1b1f1e170a36337750e7f2b0f5f60c568dde03d333fb40f29f23aeabb2fe5c659ca26ff0160cc4bb4ce5ab6a9cf97fe554906
293	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	206	\\x38a037dd579bf9ebd5a7a859c407bee5373388fa1dbb5f67672b81714e6a071092c6cf7b496d17c9bf5c3afab681e71759d9a31982cf807977dd780dffbc1409
337	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	55	\\xc73f7a2f2f01b1e4a7aed07a84dfc572b4317a5650337ed93953526da988122925d28cf45539bf9473084adb39d2ae1209837e58a145b0cfdb99237bb0aa4700
371	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	208	\\xe35cce5a47d6c228b1207d43237fdc3997bce952f8943e178ea4df801075423c75ead5954ead3ce073b23bff6c9837bd9bf77a2e332984fd42313d61ef6e170b
403	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	111	\\xa04119052b441a086e2236b7289159efdc280aecd580911ac5afb6a49374326b6dfc9c04b07656983aca3ee33c11e9d4da739a43c46148d67b109279bbb74804
423	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	287	\\x7edb9fde0a77685bafcc01397a30a01631b536decdd29a840c267770dca6f60b4f1d56d91c60186f3b9f18a9ee8fd37bf870a78a93fe32f507043c6036a40504
160	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	117	\\xf1dfab8261bf300716bb7da57ae9ae42190666e49b555e72fe9c6e49d20e878a49ee3e9c286f92fc05c6b73867653287195ca512d964bed979f083befe218101
203	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	161	\\xac91a239916a3a313856925997e9fca7a5f0b6013ae890d9330c8dab4c2c35ef9d7581079bb84729409e62b03762a1d80f62c6cf1c767e543d293e75ff30f60d
238	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	33	\\x668c851b5a620aa24277b88afe86b59df33c415dfd66a5f8f89317d47ad2f795df64505482d3ae555f359002cd8f4e4036ff53dba9dcdcd70ddef822eb9a7c03
302	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	419	\\x6e8b256a8e408f6d120f5d7838534505f6e087fa8a6a6c112900b3d715d472ae1da071d88a6c83c09e965cec5886c43624f991e127ecfed04ef5583b2228bb0e
333	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	217	\\x80fc20ceb42fa7f71d310328ee3e4ae6de6af8e264f58b3cadbbc233db33c8b0ac2396386241574dd72dabdb889295f690c3128159e461bd24a4d29abad48e03
349	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	286	\\x3316766998aab9cef0f73d558942ebbdcd08bf40683eeae5e624e700546766e8fecbfb1140ac61222165d4bf77ef2c8b6e0f5d77778eeb17da38aee3d98ed409
377	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	385	\\x12f258700a34196cd117de6c32c759874e467293ad5ff087896fa57b85cab3195723f7291a074d92b6d906dd88488891531151fcae29ffe6ab5037251d19c605
402	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	114	\\xf84bf49ef638042c2520cca7bcc83a9d82a0d4722f272c0c244e208496088af5544b1912542335b6095239dad7327498c082e534a5fe7601bcb32eddeb7f7406
421	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	315	\\x4055ae055edf8949aacd20b527d8b2ed4385cae29044cc14859175359190835e699b6505f28d8c26da23ce6542add76718a0701018662a86f219c2294a073f00
161	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	383	\\x655df99edab90eb002ce5100cc13afc5097ed0e4727184ca95fd18157aa5668e386492cb91953c65c617ee95e14b396188da4fdd6054e0ec74ba6e928b496e0a
176	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	135	\\x7eb06cbc8056b88ceec783a01d9ed08ea60ef5864538f6cb80855beb3d84d0964b41665e666d8c91733b10dbf86ac5e3a0541ec1713d42cb1460e1647c032f06
209	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	327	\\xd297ccfe3302231fbd9a754cc61b2761410678db75bb76bdeab5cb49e5b7487d5daf589cc58bb359600fc63db5d8a715fb63d38513ecad32496184d7c35b4200
231	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	320	\\x29aa96eb0baf466f3f791c58916f34bee3d61be2e33c97863915e958757bef3c1ff8b695be3467100544deb8a53122e9e4483b3d7069bbdcaa62311512b59a0a
289	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	224	\\x10acbd0d04a9a167116ff869163063d352516bcc91e2ced7b111b11a1321130456e31723324ad8609a4a5a059fbe786b79ac360b5a37d07b79d9e630e9e1fb09
304	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	193	\\x7a0e7642609a96d30bb188f798a6459aa239f331be394080a32da21c58b290e292cc5246a95301ea2738a22941d605f26e8d1abc665cc0f259d20f5ef98db40f
318	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	82	\\xf1fe913b053568a5ff773010b76607de647b1eb89bd18056c2e45a36a4a093f5ae1883de3ab820d353b4a8585562c5d390576e1fe971e3c4db73d5665c0af102
361	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	108	\\x7a19437785ca6f7e44d714683ae8ec938d2361175e540b816567bf6f3597c75adcede7106f8508b251c39b9ddcf9b310b8d8a2c3231224767d9f3fb37c1a1505
385	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	27	\\xa921cdc8c2c6a9c72510ccf48ff1534250b81711e64068f7518cbcee4efb091e76024378b0844661b5232ae5031dd52e6d91a6b5c8481f809411c638a3e0e504
417	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	121	\\x1238f319cfb403a69932ba82bc7af52efcf51a7531c1e87f15f08efdf6a7fe962c4ecf407c3be3a110df595d9fdf15f11157c5026f6dfafad73c9f09c0922801
162	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	139	\\xefa82d538266138e01fcda9badeea7545491b25d29a4b1864b63cf7bd2088e0b5b6583ef8be983f670c7d48e33f0f9b037cbf69d4c8db747e3567b424bb4f90a
187	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	395	\\x84db6419ec3ed961d1d06b34d5c8c0d0bda15fda80b23f3dec97ef5b06d676c8d9bf57c69803232b7318b4f359446976f4db8c4e328e21e1a1daba64077c0d05
219	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	319	\\xbe798fee173b0e6914ba466efb5375f5158236023c3f65cb45a5482532611a70f7ed01549bbd221679c61a03020b998e8622554eb5352cb06d641d7a46684605
250	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	32	\\xb30b5aa6369c63dfe8f789d7019f69ab09ef8aa6f187e15c7e97de1629181a7745de2c3dfb9dc03f2a6615c66a0e8ae9f99750679fd81429fb1856b7df2b280a
271	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	234	\\xa08f65ffc8001b8ff8c6ebe3ea48dd6f9df2d88430a221c24adfcdff7d9f8ecb84e34c143ec1442933e9043f6a534e802770289be12f22fe14d7437f6df4eb0a
283	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	122	\\xa7f63de0fcc781ddc428b68fd2b5e88a192bdfe11089c186dba0d318ed656be68c5952ee9500b9f70e4858982a0493f602bc36516de649b6792e8d4dbaf8560f
299	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	177	\\xeb01390beda0298362172e4af18542a765927469dc4adc929b58a7a6a2cc9c5cc127647b825b4a54054f52d7315189278e69178fdef933c4b4f99aa12c4b2006
332	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	115	\\xc8ceda25ff9629e0ad2ff6772b0ef68cc4f326652b163766601550eb4b16b9ac9cca8c20abfaa1820eaf63674957ada73dfedfff92087ca861ca8c76942a9307
373	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	151	\\x50798391e0831a0cb6de9d7833124114c919f5c5b8e10e78c5a89f366f8994ee94dfe2e9d31a6becde3795f0ec71cc7c097390565aa8c628c61ce0df50a22107
411	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	250	\\x98f1dfaf12fa801d677cd72a793e9b3b6f952620888c67a8a25a10c592a651983ee3c897817c6eb1758c55a32d8592bc3ffdf31ecd6467641f116e09c4d26302
424	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	344	\\xa721a074bbbb024b84850a711c462a4eb9ae18b3eefd048654f24ffbf258cd08acce1c01496d9f86e0091a9ad8a88ed002a8f8c0d1610c21fb3fb036abc0d100
163	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	98	\\x21336047c4e96f37ed879720c2b8b25b177999d85cec7f680d70beb1fc8c7b22787a9047a37bbc4eb8bc925ecbd417a66f2576cc0524ff85ae24465cdd31d500
178	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	343	\\x0e3fc05e904facbd14d4720e072f4525a81bd497114000c7fcf1447b4c49f508ed34c418ff521108e1b75c2f6c758e6bdb965264dd2cae48489de5897c529b09
208	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	199	\\x858092c779e83e7ed950245280b2c7770b890693c5191e41f2ae8534b34be04a7689da5edcf1d226d50572e2a7baa77af680e18928e879f5f7fd3065b1b23103
234	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	173	\\x9dee2dfb7efbefcd4b561864592dc01afac8046c01d93ae239bd3e35d5c8c380d4cb22d06e98a013b4b782a8142fad8e4faeb6f707d1792291e8028b7950710c
314	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	180	\\x86c170c3478cf966f2255b566dfb17b9910a4f28acdfc88e361f0e12500b410e24edd7377942a16cc75fa60ce404fdbdbd339d0232ac126b94b96940b33c480e
358	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	349	\\xfbda61329a1301c35eb3954abd31393b3650b7de5756364923f1834ed2cf030927f22206e0482e3fd1a622bc0c8142e500a9c7a7b7858806cf05178ced4ffc0f
380	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	396	\\x91db15de6314ebace23586021ff4d9885fe6741291a84d941556b075776b5da1267bcc1d5ca9ae0df33022a894d2549fe8c199bc7ec31927fc8dae7ca458d90c
410	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	296	\\xb21e5fac063b40ed1504bfc11161f2ee158836a53f88a3905fa2546be5e26b0f9a0852b029c1e06661063f356bd6eefecc43a5da9e68a45645f709ec447bb90e
164	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	264	\\xaf55f364482760c06f1f298d6eacbf9d6a607b7e00b794289fefdd5caf14b736ea0c3be1e5bfd97e9108b4e60e7289f28de29432f9a07dd486dd479db0cec80c
193	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	301	\\xef468562b99810dde1dec5f7f70c09406b3d9b1d7d0a8652b4f97827a38633c755dff55b6361247544e476dcc7497300d0e0404c7f4bb14fafa2295004938b06
232	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	159	\\xb88812b5cb9c6c7204f430ecf7d4a043222f3d93bff3baf8671174956ddabb3f41d2ab753a3500b427d5003c02e8be3cb4e4d6d97f41d0d466b568811dc48906
258	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	105	\\x713d98b6f1d10fa2c83ec90c4262303fe772e387c0257e5f78edc9aa66a57400dcb90e83c1ac84ee91713b2e2a77a7ad3e5ce1f74113e5aa3d66f59ffa53bf02
286	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	168	\\x7b67c312d45c902ee5b73155a36a2bc4e38cf57c77f9fe4a4549509170bd88d880e315f90ba287c0f5fe495d3d354500dd86e76e566cc36d1fd9862265b8880a
309	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	211	\\x416c8aa7621fd7f80b39d9cf20e153c925690b14f01a5950f34fe39b7a5e47a7d72ce3595f08dfb021166c336eb84612a279f13ed08734a036f66711f6c85c00
342	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	106	\\xcdb011fef00344afce7f5f44596b2204597d27cecf328fc321358e046440b4fd2fb70944e941091d28fc624ce5f2326ef9cbde7dd158f2591dece40a53b0ed0e
366	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	411	\\x189591806d0f8c33bf59800053927ea9a7652612f551043b1ef627f0e60b0a8c896e9dc3bd87a2c3bc4d42d851adc68b0d7ed3e65c8e2d66586cdb3214f8730b
395	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	269	\\x08b049c995c045e2534dc6dda4a195c4389acc966eed9c1c92048fe2d1a17679bb5476601784b5c42f032d8a9793c41e8a0275383a2645a0923383e49d22e30f
165	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	335	\\x6302270f3b045cb5df868f24baaa92433d44b0beeb2004d4a01c786dcb50c5caed2f4f5cb3747e487be705c7ccddba40c3ac881e31cd79e03a16458f281a4908
175	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	225	\\x87c15fc3b386afb3a0d6d4e2d9aea18c623cfdfaf7f9eed19f78a1744f6e99b4894f97b69986900a3fbe79bbdbbf82ef671768adc1df9af9d319144d9195e206
211	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	194	\\xd2c394cef6f81e84d87be2ab56989803b397c5cdbdd95df80bbcef67f60c8962c3eaab44f9d6a800a2ba4317d1f3faebd2e572f46c2f1a0686b5111356cb1c02
233	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	367	\\xefc144de4c8a47096559e84303aea69631f9a3431589c820f2cac81a5c9543bcdf37c521944d2f9aa82c9d41d3135aa9843a5478715c34611290607454c24308
307	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	92	\\x2094c7188fcc1185cf7dabffc7a70ae4312fa3e0054d980f6d56b61d13162e48864bb004b725781559bcb7d1336ef22ef22a1d5ef840feadee18bf40eb885a06
340	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	181	\\x3288b18bc21a76383b221154829e1c514b23f92ca506f83a91321b52b6f87ad95095363ea277b0e21282a93f43a93f9327ae0bb9246cb829f359e750a05a9a0e
354	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	364	\\xe2adcb03aed8948e8a6f78ef8fd61e922c0b75c24a5b9e22110e72e5fd16533ace7ecbfc3328eacc3fad48ad3abdc4eade50b08666e84783e56207cf7e1c560d
387	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	401	\\x47d7d86ad43f01093c6a14dfaf65db562d33f2dacc4edd0ad75fc86df56f20f0b3d3ada828896f92146031c940906127c62c49bb1b54f675fb511f254cf86109
166	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	31	\\x4584fe7d075290e06de623bd0be86b196b211b92855d0b1d807542b33fa0f0cb2ec80b4a8db5c6570bb1277fec3d6b73e648f6a2fdbeaadb1bb04474df4c5b0c
192	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	332	\\x019221c7d5907053c6382fe19437edfd0aa86580153b6b1c7448a43022a2950c66d634c93009fa34a5eaa8058cfa5fd03625482512b128bd1ccc5f6939ec2e04
240	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	1	\\xba515603b84f4be0f3c8963f148ec6191e098222023417e32e964dd1f0591edec45cd8414f8bb4fdce8f59ff5046db9c8d07a449ea50ff2f0184fdcf40695506
261	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	273	\\x821e511103ddec924ce30f82224cc4404e9a5883ccdbff6b19363a3c1d4847330e6e7b0455f872951dc0ea542974d9b2f30da8d9546edda1c8c335a495d48700
291	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	245	\\xc15f4ae7da6ed7c816dc323e92a53628d6c89cf399a0004629e236b2e450b84c8aaf941ac19307ee86cca7b78f02190a0d5e21e5d60e504fda485d7c1810ef09
329	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	237	\\xb3c14b0493f3e2ab40d762168294262f56fc2afbf8ce46946fae5ea32e39fd7ba7b77d947125dd4b9269736d6e3e70f7fe235fc7f5bfc247dfa3b2809f25760a
352	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	16	\\x92df3ea18d7d5b9afdd063a6f221a4ff100388076700a75196e94bb27205e042fcba06b65f2259bfb937f510db02a9a7e9f6a4e10b587fdfde08e0d336cb5607
381	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	336	\\xbc281144c32a70a5faaea03186e219004b5b8c6c75d947e8bcf5875d3d6b1c08c2e131ff72443329a57ea91725c902a0379c5583e87c072b6bab3cb5967e880f
412	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	328	\\xb118c731fbb23318c9247b34a63ead82838e889726b8c00607c8ec362302018cb2ef6c74282be10f0a5d4d0f2604675106fc51107ce23377b2d5dbd1a3ee8208
167	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	291	\\xf0149349a991ee3b95ea04c77a08ddcf0101098ba72966dace8d7d0c2c8f2a7e36980f825fa5a06d458ed959f2cc5fc18e5c22284b44922c652a8659c574310f
194	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	74	\\x380a2932ecedb0c8b71a244e1685cb7c84a7f717e5538414e937e1958a82934aa9a73d84056eb827bec686f6e4b19d1e0668a9a95da6a16ff64b9b036a95580c
222	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	86	\\x53be50ab8c025085ae6ebcc6b669a030f82d60dba97dd13090087fdfcfc1c7092eb5b374d55e5d1aaae2c9853345bc527c4ef38b1fa1940aa21afd68632f450b
246	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	132	\\xdc70e9a38fe953b74c3f4b599f76c353aae8cce8efcda7b6b43b04ea1fab449e4331ef8ca0a6401d622b21c9390083fc73f7ac02b5fd69a0fc89db1b7c11450e
280	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	381	\\x710f55c872c6a47274a4e2479cbf310c8ed660933589d6a551a8be5b879bf7edd448c11f28f1fd1e0c7eda8d0c95c1e1b8ebb62e7765ad261d9b2fa7b2117002
298	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	282	\\x88461f68e517f51fb1b0bf1f4db451d326d252f3ad086cc9da52459268af5c7f139744b98fe81ee113d01f95125c1a0c2f671f6e938c7ed060519a13669b390f
330	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	295	\\x405cbfe1b1a95b4fb48f1ff842ba1db16aa8691cf56622e7387a8b8bab0332149697ee2a444275196d4aa86643ee6387d0368c6ddf8fbd903bf344d81c67970e
360	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	136	\\x53434bdb052652937de78ebf67ac419be7f9bf83018311cf240b8e331f236ea79bd6c86f3637370a4cd370377adfbbf7817f763a588c5f6a9b92f6cdf1a0930c
386	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	70	\\x285cc6e75b248e70dff430eac528275855988fa4f5625d4f7825681e45a06ba31b805a63bf1794e2d612e34df3136c5512525ad18fa912e84d3ff7ea339a6e02
168	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	346	\\x1b4240f0975ec4d13ab19691f570baec30d0541e19c14b749996034129396d3af42994ff03bdb7c4b499096f2e28acb456afc2213e0ef66fa24ba515e28a280b
206	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	163	\\xb87abcd7023ca9959e1d53988f2f32bcf9060164f44c3ba8caba99f8a4b107e3594e565e86af86ed126e9f1e4cba9c1d0dda242f6d41163ada506b579b5f0b00
244	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	318	\\xd3e4fbb9a6ef9e6c4ea0ae3d8a4ef602114fec8289c72252ae6be233834d42ec569a610b3fe07483273fe58e8dd8147b6cb43fbb9e9bab64c43851b53dff8a0c
275	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	37	\\xa6c1033c116f881fc595e61ca4ec7ca3e6401570db52a269d2d25a192d4ee998fe17efdc7fc24b5dee1a519a67b5a625dd957abcee5dd7a7b20bde90962fbc03
290	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	38	\\x4f533a7908176a5f0633c46c265c36d5ec65dbb262c1194d00c6cda6612c30231226dbf149732f9cb2ede78ab8ef7d4462f0025f43cdb00a9c93ae380095f606
301	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	113	\\x834221d886f1045bdef4df747bc7b1d66b899b6a4b512c7d126390f760d07d918f612b05ce87a9f864242f5bfb1816bf3131970fa6037fe8a8d76ac8b18e8e02
315	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	154	\\x0a148ddc0ffd925b8a3244eefccbbc38359e4426be811610376069fafbb82bb14a453ed64f69e32fe84e88aafadadda7d997e57c529a20fa65e47dce6d25b20d
346	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	48	\\xe68b2c3dae1fce773384cfec2366f018fde05042c32cc405c1da140ecf8a59d44dbd7daef0ba3375ea4a80c8cf62a672a1f7c0509f5c7dd4d35941962326240a
376	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	285	\\xd3e285bc858a5ada7dc1dfdf5f7953c9b7f2055883db5fb3f60d0e673b3f1ee64b2aab25d16dd042191ccf27051b6143917bfeaf31d49db8c6170e536f16190e
399	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	408	\\xd16323b70f0d0a83aa740ce229e7e6ea736a4d7fd2cd40ae40355505d9c4305c4767787cd539a2b486ef66a96362c67e1299702a7fb5d5b6cd12596e5c0e3c01
415	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	313	\\x8719618f9634cfef45b3f21645d64d6c8c3fbc8665f780756eaf52e5d6ba6825d580d0fab2ad7a554899e179bee90bd58ace91e87b8570fa3045b885f950c309
169	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	12	\\xc46d631639eea07080f0138dcff6fee8991ad126bb4f9c5981cb9f1f959ca8da7c381000ab4a3f5337d6c362835087803481f97c1cf6705248b69347ef841c05
195	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	239	\\x00eb6d34ad6e1be9a64aad3d7f0c5cb42f3c1a55a692ac1285f57a616ca2076996bd75e0ecf3d6b941981e82457c91b384682f82bc2dbbad6ec22efb241e2902
230	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	410	\\xa409b0fe30bdb61ad2888a490ce62d879693617152764808ba8cfb106a0c618e462fe8edf38a056a6c395d7e6aebbb8d721761e656b2f6b5944c07e8a779730e
256	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	87	\\xffb87ce540cc0c7f5970c21b809f833d5fa6745cc8eccb4602f32684bc576be7f522efc1a000aea3d5b7507a7aa4e03077d665bacaa48170dbcf7c54c9949d07
269	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	389	\\xdf1513a537acb62ae5a823a74beb2de730c85834c46b377c82a9e85deece6d2429daa82c2958c56d221e6badc84f1c7e5be9b629ddbb1babd295df1253737809
326	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	61	\\x734a5246e477309a07b17ee581cd86f3ec7c3ef7d2c3509b710d3213646a637f72f36ccc70e48f62cb1d2be879ec33011b465ee105f7fbc00ab8119672ce390e
369	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	214	\\xf4eb56cbdd23ef4d89087b271719093274b4acbc1f7cceacc083b511e0860dcfc84001d27a156ece97399f9aba6cf0a2ec9c465e09aa11ea884ff019d579530b
396	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	63	\\x55bbf198e899f10acf668463ede65af996501796fd358800e64c12ca9d7ec10d24901ef3ef05ec2f2438653363e0c3a8f40701263630c5aa5eba2fb32c34e608
414	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	157	\\xdb063cc9b556122fd9fd5ca9cdce719c0e78481c175be08120cae8435e288630c62ed83202919fdd649b29cc233a1b93cad137472bb4e5cbd1949ea30e1d0700
56	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	77	\\x1e3cfe1b3117d75f109551a857bc6c14b178ee9196c356bd1ab05fb144702561fbaf416fd66f8c99ad04c7509abd43189f74700eb12b98cd0bb4390194f4e90a
61	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	229	\\x556adf06c18b52fe59ea9ccf3366b6761be77c3d6cb83cc0ddda5cbf30fcc04ae9fc9b0094f6532f3d43526d9be4b5d580f3fc342094d8a67bfefaffc2d14102
68	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	49	\\x47a6a8cf97d97f23403da0f4274da819c4cd76d2d7d1c528c0c06e74a76529a3f519df08a5b0587868c9879f4d6a69d3a6cfb5e91bd208f363db34fcffe35b02
75	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	393	\\xe7a22138f60f746ee0b618cff9154eda8097cbe04d3c4a3b9f252d75207724aded80ece23ec39f195ec9a801ba442afd8d08524978e714e61a7fda347253d10f
81	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	304	\\xc6ce2ad476a1fd46d797e2ec333b54256532590c6dcd8ba8bf3edf7a380536072c961428e18390282ad016d2102f6ad0ab6470c02d679999e4e380f8dad17206
87	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	220	\\xb6123490bfd87a44d6a7457aa03307bd097275d9113d22a74edb0b7b3f23a3b1151cd5bb37d88d7afa2283f149b811df9497c14f22b6ca7f4b1953d14f995d04
92	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	353	\\xeaae4c075aaea8006926c5ebde472f0edd93073839a3bef3e35bc7d97072a019f0204a3135b12e3f2b8972bc3a8030a9a0f6acb4d947d220380c788646209503
98	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	259	\\x7dbe8afd481adab8f5d4510aaac87853b3ccf67cb2e134ac368efa23f26da8c0dd26a8652a97179f36823ee468a46a5414e9a01230caf4658762ce1507c61a0e
104	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	351	\\x773db6b8ed8cc022482cf8ec881d0b90463824517672e05a8dc536e594f1dc59b271d0610f2f808f8abf8d22c4a69802c85586e12d0c40effb0832f548c8690a
109	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	102	\\x93756c634e56d1716611f9e0cf3c103ca668c1e4128fb78ecae1fd98b8a07d59c02a2ea0ed542bfbd56f0fff7461f5e350328ea5e845cc078a25c4dfa0944006
115	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	350	\\xe1d712d1dff25804e1065a08ad59392eeae5788d23ebe723b80913a48e170733d9ccfa1d1e57e3e727246de3d3ca1958a12fd5b92bca9f3076d4664534c0c009
124	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	112	\\x8a26b8fdd866af7bffb6d6d47ab1baee34f0b7c2997a808a24e0e279fada414df9c8a84a6cec938b13da6583795a7df3a30496f2a08471afa93a79bb7c88b305
130	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	284	\\x3509af1d429e5b5e49b93bb853866e1ebd5aea01e0c1f3ce6ea524aafa0c4b6ef8dc3132ecbd67145d565d438c287089e62299b2a08ca5850765666d51cf4506
137	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	317	\\xf763727d4a8612de4101a04f17b01e209d36f4e434825f518381680319037d5d446099363a16674e325f5023d215d8f5681c9f12614112a25b914e9d624b0800
143	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	118	\\xc466c9b494871f1a2d3608af888975549acd40787e35b0bfa52cd0d07adaefedf0f6986f1e270061b60fb2e75aac858571d834aae6d4c7f5255f9f8ba60d140d
174	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	333	\\x7503d997fd650f718c3fdd1dd31e93249d15569e0b4d52d36ec452ed182e127f60054e5687025b86ebe871db3f51e84d8e793c576fff1c249e622b6c0de59506
204	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	197	\\x1c55dc2d00b040a95ccd534dd1ed7cf68e57fca926829ad9108e7e2ed5656e6227c11ac4fef651a339e1bea23d60fbb7a955f7fc558a7d77dc93a5458a7a300f
229	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	309	\\xa4752d5d9ec80e2746f5ecc36d6c891c67a1385cc7a4419165d2d2c5e2905bf67ab1324e8cc330f1d5b589bdd34674617ead6cf605301469f8ca71be2f768d07
254	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	172	\\xd6845ed9c1babfb3f984b71a92f458c8f7e3fa3468dc0fc6b7666cc2afdb45a7dac7e5b25fcc0979104eb08bc22774ac316ae836b20dec3a501c7fec90d1be09
262	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	36	\\xc1bd47d3889bbca4d9f44a27d17bf875a04fcd13b6f971d047abb5a9d4b029a44c56f1c46ddee44f7de6db552cede91e879aff68e244eb35749149058537990a
338	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	75	\\x0f16f23337dd00cf45b4a1bad1a4dd98fc2901e87549ae096518557e01cbfde4b67a5fe7c73a65919dc696ce16fc41cfdaddbf8ea4d7c17be7aa55c595b04802
367	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	352	\\x1d8701b3f8a9a04803473e7062af11e8349e0a2104fee25494eb0f4ee1dfaedb490738c0932b1ae17a8ce6c7f73607662f0305af4290d994ebdc35cb687bb500
408	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	191	\\x9156c64999532df1e711c0f9f41f5e392e0a754b60958e814a844c6a94e44634cfe5a61aa61c28f3e8547db185976c83d84d054b0c78fb5c223bb76b7e7baf05
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
\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	1610118407000000	1617376007000000	1619795207000000	\\x139fe12db5496ff0e808fbaf159289eb5bfdfc731c77ba3d19c0ec2b68a047f6	\\xbb8a8dc3f7e63d5f464d13ba25071efe02e39133e851768a5facf4cbb82c57c4db2bb2ab236bc4d0ed74ac0bfdd5d4ef4456457c25e09710a9e4623f4a779201
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	http://localhost:8081/
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
1	\\x85685580f516ba32cde8ed346ef3b43df424804864f2adbe1d7ed8798b3e5f00	TESTKUDOS Auditor	http://localhost:8083/	t	1610118414000000
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
1	pbkdf2_sha256$216000$daCZab73zDEw$aK1j8380S4rFI7E62eudePSMX+/hi+SJZry13igV48s=	\N	f	Bank				f	t	2021-01-08 16:06:47.965825+01
3	pbkdf2_sha256$216000$6EtXKXUPDF3J$JM3seQOygkQgUJFef1irDvCAu5AG9A2NvfuabvLKVYU=	\N	f	Tor				f	t	2021-01-08 16:06:48.148062+01
4	pbkdf2_sha256$216000$5fxARrNIUnx1$AQiryCC/bNivGEMlAFCtJJ2aG+VNWaLmInRGC6mzw8Q=	\N	f	GNUnet				f	t	2021-01-08 16:06:48.233146+01
5	pbkdf2_sha256$216000$pA3dvLKotxwc$tCIZx00aKFVmhhrX66Yp6/ouMFyktfSQRuo+7RdB1rw=	\N	f	Taler				f	t	2021-01-08 16:06:48.318415+01
6	pbkdf2_sha256$216000$XsQzYgUg21x6$my7kdVwKDy5dS1W/v2unyVs9DsW8ReB0iePCxncyO+c=	\N	f	FSF				f	t	2021-01-08 16:06:48.403472+01
7	pbkdf2_sha256$216000$4wxkn1io4EGl$TNv9cdkVfb/LY0kOwHU2/R6+uLyR2A4VAIGyhgo3BeQ=	\N	f	Tutorial				f	t	2021-01-08 16:06:48.487444+01
8	pbkdf2_sha256$216000$sZl47pONOamp$Av+mm70d4kLGOX7HJSCKDcSrBReFHbniZPVBqxZ6K28=	\N	f	Survey				f	t	2021-01-08 16:06:48.569839+01
9	pbkdf2_sha256$216000$DaXH44B7xWAK$Mei4PcflyRqMEtX5iJLfQz3xRf8LZ5GMN9uQSDvlt/c=	\N	f	42				f	t	2021-01-08 16:06:49.019846+01
10	pbkdf2_sha256$216000$bpo5E4aZE0jV$EzsklYHSmcHLcs4bmtaXOUZ9CWDl8VHCMOc/GiIPf1M=	\N	f	43				f	t	2021-01-08 16:06:49.47857+01
2	pbkdf2_sha256$216000$xpUz4sroxbR2$M3dstxJEqSdB4KWXi7efmwtiDedp018EnuM6nDAfGjk=	\N	f	Exchange				f	t	2021-01-08 16:06:48.062656+01
11	pbkdf2_sha256$216000$mlvkjLv7w3TD$JjW3CnWuxRgtLG2ns4fszmzvCe7azlJnaYCHNbBw4ic=	\N	f	testuser-onLU3ara				f	t	2021-01-08 16:06:55.262492+01
12	pbkdf2_sha256$216000$A0BHKoVoAJkQ$UdGgNb8MMyBIgdKdgy5ZXi+xSszbCd5iK9FXklPtYQo=	\N	f	testuser-SKC1r0sF				f	t	2021-01-08 16:07:13.378034+01
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
\\x02043a535b489231b816dcfb7102cfec770fe55888fcdc3c8b05ced5da8b4735a493c537db9cea88cca3c414c11a2163fc9805ee164dd8a12f7cc2177264e4eb	\\x00800003c685d68c92ddd9623afc40c793205f42395a2f8762dd562e44c03c695a8120fc18cdd9a063435fe1a95b46558356625b0cb683a635d187530123eff2e5b182002bd9ce5ec00666f4b580f1bbf1382bf0d5bc8bb193db12772dc0479305aa25600c43d2bdcbf4226aec0f8b3284cbfb056dbb74cdcff43e9f6db32af32a9ab4cd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x67bcadb51086aa7f6777bf92d82549d28cb3fba6fc65a6f90d81ac10c3a587d7e19a89ac5ee4514fe52ba7b65140658e01e24cefb98201e1fb9de632228ad40c	1625230907000000	1625835707000000	1688907707000000	1783515707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	1
\\x0a6ce6a89f0e9edbcd36cc38d9cecce34389f1d4126eaec3deef5a6d9a8912690e0991d00b02bf61737112df7f250522282a2404c60ba8802ea30b5b06c92cd5	\\x00800003ecbc77893d122ab67eeaef1b90998177a0bf64921b511f5662ae5ec5b8c4efd42d012ec4a540623d226ccfad2b2f65c9edb8c215ddac2bce693b59f80ca5a8ad00b1e7b6dc4e582714ba3a01b320ede4f581ad1a394cdee597c2a0b11ab142dfb09286e56d6c700dfcece66d1f366faafd4d4d6b855c8f1217de21b1ec0199cb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8c9db969cc9367db5ce864ec66b768f428fee9777adc2b9c4645532c12385c109e1e29a95fd919712b426a0ade48f87ef5d35bb96521250f1059de539a245d0d	1639738907000000	1640343707000000	1703415707000000	1798023707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	2
\\x0bfcce2a682a562cf2f5ff2f8bbbb75baf36e29ad4d8a441fcdaab043f06be8e21319f2ff9cb44422a36fe393f22b613d27c3f16c568a97e81ef2702c0ddb42a	\\x00800003aec09396721b783da61fba0ab6e271e712de4c2236ef799b5d2a95a4b3b123367fb76474a496d571dc4e5e40b7ae366213f273e3c6672265057375825d1d19cbf46ae982ec121f4d404783f890bc7967129544f23e5c463ab9609372533c549c1bb99ab2390e820ebc61f2aa1f9830fe1adde62f5fe6b74f3ffd112adddcd19d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1934ff98757acbd60276de86a0c55c2669e75c2b96fdd9902f94fa7ccdeb03d4d49dcd284712d41cbff6dc5fe063b5e21326c444af73c4c31502410d3ea74a0a	1620394907000000	1620999707000000	1684071707000000	1778679707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	3
\\x0fe81a28d50e42e3b920b01c7e828519c95382cbda8af9b18434a0e77ecf749d83404a9c508da1d4a6875da03a3b20813396e02d0743f12600d339b99643ca5b	\\x00800003fdb2e404a61b01901c10c015e6731469e4e31b608811609f5b2dcb794cad4a81a53f194fcc69f34096b531c66d5d525c25c0cda8999e2d06fd907808667dcf4a2743b92cb6bfcfd172856ff4a18218436049c2c7fbb583838c9205ab6ee30ace57bad2fd96f9b3b7a11a9aa7ec4fd37416aaf00b937e28c55c1de148aa5a82e1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x81d599ac5f1694cae38b8a502cffaef8a021a60e3317dba3ef3b8e6572c064b01151c8d45cf68cffdb5089eae6428c90284223dbb63425c198efcf49e1444e07	1613745407000000	1614350207000000	1677422207000000	1772030207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	4
\\x105c54575193a8faa173787ddde7c402ccbef1517e51a2a93e247bc32a92a1fd67f904c9c40526b4d926576e5cf7b60c42c218cb6193e655ff3d59fdb8006e98	\\x00800003ce24a1fcb0ccd876bb2ad6e75b42ee69b1fbbd17df0681f842b6f11036348583a03c32d2a51d5929803ed12b654e0cfa6307798df9382c11bd027f29b4d5525a6451863f14d4daaa5af16994c0f58c786512fd3c6b25d80d713dca323c832826879981a588b777387f7c9b8e08ad70f5a225d2d809231c02042fb8d51102fc5f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xdd340fe3cb88235ff7853b167877bede5556b98b60750dbae1c70162fa75b417feb92f77f7b500862b4931bb2f1ef460131807f05fca5aa19880ece13c024704	1637320907000000	1637925707000000	1700997707000000	1795605707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	5
\\x1048d6f43b05d40db9084ca811dc7c90edc26081aee0bae1921fc04470e89d75d1154b196cebdd769c6615c840fb65bdd1b63bddeeb7e61645e40e3c7def79f8	\\x00800003bfd4e01e99424ca12be8b8906e81a82d6cc8a257a7dfe65341031f2fe00320e7337373dcbd0356d4fb73b60fbfab9ed86b6a40ec3e21e367926313f4e02f32285af022653f5bbf37a2068d7507022319767225e1ce6fc8cac1da192e4f9b7cf1537d0507f3c4eea2401a0ae407ee929b82167213e7b7e340636e3fa09d8253a7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0e87a85a80e336c658c17fcc58802dcea2eff31b9117decba27c1a136f117c71dbfa03e91df3a778d9d4c6e8cd1b4f3221ebbb6705fa79b9d80913fe8e529c03	1622812907000000	1623417707000000	1686489707000000	1781097707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	6
\\x1074a863a67d61ba4f80dd47569fbc8e45866b03cb5d07be39eedfd75c31b5a0a94bc8170b1baee3934cada974f96626a707b528857a73eb3475581996ae39ba	\\x00800003bb360209dc6b8914ff9a2acc8ccd1b2dc5408acc324ad5c52ce68df2c3b51975e508583dd6f6f3013e0252faa365018bfc5d4040ae1f5374c4672bcee9443e8417a4494ece31888b539b6ea3cf6ca6f2ed411e16673228dfe966a1313101408665f48271db021c1abbd02395dead2f8bc83dba3c48a68a00f23d5985e7cfa6dd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2a261f86e255314be1144ee329999be2168d26875424ee4359b68aada9c946de018c7e7609a42e6a590e681de6371ea77d246191cd8c59da14137f786745f40f	1631880407000000	1632485207000000	1695557207000000	1790165207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	7
\\x10a056d6cadfe270ee3e80b31e84141083bd5b706754cf1cca5a29b1a2355d08286619ce5def5270a7aa0c266faff3d8fe547588a09e504272f1c5412420ae5f	\\x00800003a03971e0e8f4b626a7b19d6be8630211a0629297453d68e002f3591b1fd832794f75c4ebadd7926d00a94c5a1cfc60d1d574b50efcd925432c331987a6093ad995ff9fa8e5d977b3f8b89239baff44926c88ee54f9fa7219a0ec42a514463ee85aaa16b0bbc7de2a855fe9bcc0508ae736a6fe7c544456124a3d63c79df9dc67010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9029dc0ac9802989655d1ceaadd84f0cc69e68e5446a8c3d6c095bdf50b0c883668a983007154f9b2207f8bf4a8406021534a15e3902e139cc579ad201dbd908	1610118407000000	1610723207000000	1673795207000000	1768403207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	8
\\x1644b74e1ad5e5330f5ca35c772b46c7964e4b1bd47789e2e2bba62f07f9888505a071558c0b1b102cec2888454d63c13d6993a13a38f033b1debd8a4a5704bf	\\x00800003aead11729c7bf9fba846acf7e6f3c613202f9305ac7108147aadea1ada24e0c4ba8ac4002a17dabc417b656b6d58d3aeccc6e1e1f702a6457b667e1903c43ca1851dea3ccd22038c2292a0c8d9dbd5d3396b66e8557891f73dabbb773ae94e9d38d6fc24c8469f2b8f5410fe10414a683ae125d7cc9fd93f622f9005dc0be865010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x20722b13ad42bb0ddcaa09843c9acde10e8bfbab42beacc8c5aad5417e789a36c86400662d8751e05fae0962e1c50d777d7f6b2287ba6be8b337cf75738b8b0f	1619185907000000	1619790707000000	1682862707000000	1777470707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	9
\\x1744299dccce4cf067b6ce8d1db48b5181f3e168728f58ac981e2449f3c0f7a3eb8e365cab069152df18929375c650a8e90a6be43a3cee7653a93374fb629bf7	\\x00800003a15c2fe92f9f374de709c785160aeeda3cb0b14e32917538909de02a027bd643f64472df307ec13984d15c66909fe4706e89b11fd65ef60d70619b94062e3f6c5751c0939edde73ebe673ee794224f55279cd31b05ac0dd179ab6dca77b5cf723e6458d8c48bf250ceb509d609d74b60502c7922eb4ab28063350d2b11785881010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x44dd86701f5f7a345286d5a00ab5de0b18bbdb3e7563e8ab3cf7e1ab599b7392b21d3926b12934c6cfa2f51b04c99301379b3fe7f679e90a501b03ab769a7f06	1627044407000000	1627649207000000	1690721207000000	1785329207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x18c4226d5a285a5fe7449238676c99b574c76acf7a221a093aa116b559a22fc50d9a6d9f24c92e3fabb3ac38842d166a7e72822e4d27ee9319ada0666b793dc9	\\x00800003e018424fad3a3a5932b37ef2fa2568adfc70145ee2b3f6e26de5163476360913ada10d92df05d6a7d95ab6155c694dc5a4f535ac30bce95d78f39e3c3f20cb240c999b37ab6b8d5105a6d34af84b9cd759cab1b7a54e31c5ad4c92ca2d8840ba798d0d8b5fad5f6ef2ac02c30322b73a3f6885da2b0a792329f7ee1e81ed839f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9d054f79d0e8a754f154e0aedd0c9f7b37fd1dda77af12c00f6a31b79d114c536a9f2a4fa529c3b5807a54bf31fe263ee087a0dcafccae7c6d48cc0031cf2e0f	1617976907000000	1618581707000000	1681653707000000	1776261707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	11
\\x1dc4599a450008cb5260eb879993d042a451085c5eb32b53d77c203021f4a35943cbff90ae3e1c6f611ce0c513d31d95f1be420de9490200ba378a6713e09cd6	\\x00800003b6dda40827eadc55bd39039a63ca183ffb5f535bb4c98bd956abb818723ba411de8e39ca65b4b80b4f9750465359cb124cc5f05e6ceb3d08824f00daec32a4d61c61abb3105a6b45fb6200dd78904bd47ef8bdbf67938d0f76f2b08868fac5b091620a1e19a7a306869419915c31a6bf6074c45408378b3edb8e632ed39ff9bd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4da583fb8b9ffd83f24f0362c9646c3c7e729a16433d1e9a8957cee12ee60850c1a56156f83d3c748ae7a57269842d5f7dce31034c751095bff87784548ebd04	1611931907000000	1612536707000000	1675608707000000	1770216707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	12
\\x206c87b662b7114c8c32609219b3150235720fdc6fba6e0a15457f0396fb9e597ab868c0ef466b9a83411351f02007141d8f92f2fe6699fb08b0434f0993c40c	\\x00800003aaee6fe134a461a2a0c590dddf9b3210d614439cdbed5aaf570bff4a9788b1c3210a1d711c15a098efcc07bc7e6b68754e108f8ff1c478e99932c3d4694da69aa63897f734abede6cf71651a865aa116953dde6ccb283a5c112b51f5fc730a7362a03aad4a8713e1eaff21ba3a59404d2eb226ae21877b482710e788d358e92f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x226a233f90274cf0fc6b3c0f34d8ebbd22d5eec53c95bd0f5af0d23b343972754835dda13589c3fe679020cc3aa7085b0c6642fc816166926ecf80b1c767460e	1616163407000000	1616768207000000	1679840207000000	1774448207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	13
\\x22d0522a32312f7a3c98181b06e2d6b126f8882a063800cae4dbe47eaa6cd3fbc54a4591c3d0b9f5183a11bb82e666ac07d1ce2f510e43e3ca6cfb8cac0f2e4b	\\x00800003add347288a8e06455339901a5e9b8a6f8712a12754ba17e7765c84a2ee5318488b3d707e001bbdc34e0cc33d041e8349831cee4a0c0db3625d8ad7d5379fa4d6f7893a2ecedfc39f73d8770804a1cc2436687e47ade20691123a21a9d07c292abfc2cece1e0c9c88ee4c816d11eb707eb49279abf5e86a71591612731c81e40f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcae7f6302a99f6bee6e5395069d7b491e8662206777a9ccc2c1eb84501c926f805fac6296ac9005db23e0791fd930741126c6e7c73343278392a15545844d80f	1623417407000000	1624022207000000	1687094207000000	1781702207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	14
\\x22bc4804ac1c9cb7f9ae7690cab8a38df7089248f57ee605a66ed3689d1a61bb9af63cf0143b80bc9a5828884368903e99cb6d5feac1afbea5486e8406907bb6	\\x00800003da61a91076fb448939cb75b0b57501fe1dbce0d80b10478bbb5ab1ae2e5da3482a28c84cb1e2454e836e4a44249301baf761738c357fc180a1ec6cb30303473c8cf8d7f4a6b211f24274fe4676c58ea7b4c1fe88dd7892cdce7f66768d1c46c0b80b5e3062a51d663d96776849e11028de058d36b87540bc51fc69866ac3902b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x366e125aa947266ed52210e096ecf7925063285dac5c560deba73a6d370edb27684c711563a683393b142b8ddb4224c8c069fb1dea883f976ff00ba5357fea0c	1612536407000000	1613141207000000	1676213207000000	1770821207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	15
\\x23f8d26648ecbce7bd85a014bcf99634f470f8db7b99f1f0b4e792e51bb66dd05f75c6188c4182293ade902e28d4535256247333f635606a7a4a22e4c1a4900f	\\x00800003b55c73096e84ee98ff97086d25665b3f6581c6b8f19e60af791ba944158f94b78d06770c8a4543e10206e968236980ec35143dd93c63ed8bab2bccf5a3705d6ba155be70b56a807a262585fb8f14444b1c499086878616ffe227a4558ca39b0f94cc6bfe3a5fb49a6e280b3833d87f1a3eb7ad3dbf57a3bf97dd0230416bb407010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4013ca5df9c2f1ec79acff21a415db5ad1d99a11409572995dba8542b3c514e77b984794f0e0b482dd8443a1d3d4215acb450711c135eb93312109d6fb4d240a	1635507407000000	1636112207000000	1699184207000000	1793792207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	16
\\x2334bfbc1f1c7cf07fa46520b6504effe1c3d91cf03743f31975eb83ad9f9b25e9fb8da60128cf56ce7af25636d1c6747d341e0419f3126767f3fdd008a096c5	\\x00800003d37dd1bd1bf534c30cf1db6efd635a2b08729e4c59664e37894b78b07aca46ae5c378685f7da2bbe2f41d8eef5bd38cdeb95c08045c1fd17aedb70a4de2c03a1381edb471997bb01b3374a54b3005e09ca1d450a2a601cc86c0f8049d27b404beb69e2b0bc967dc3f01681cfe3ec5db613eae52a4eebd67c38779971e2462a5d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe6d95e09a34c9c806b1aac6a8660fe60eba1d0fb456ad356b3b2d84abcc9f969b03e0689b3e5adcc09b430b1bf115a6a8c3b301c2feb759ef50195e09bc30e03	1631880407000000	1632485207000000	1695557207000000	1790165207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	17
\\x23e407013418388ba2b7df3c28056c92154a83b6b5033dcca0ac7f4a4375b17fdb2cb13cb77dc38831fc3487a7dcc8ad7e0de1e68a1e2a997db24444b4907a30	\\x0080000394b3867d278b1b4d03251600903359c4b2428048b443ae47a24565fa20077127e7808edbac6e7293f63ac82b39bcabdd4d725220f57209bf66f1c84af051ddede2a80a3a36bd142b1179b7ad5929649d281b023cc2e06cf1ed219ebf29c555720401a0df5256a79bd6566d4a5a4d7964c48c37bf9412f83e4cb21a5b8572776f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x37e87e7030b93ad1965a0faec34906536a0b987b5be155d5c8f453a943207055bb54919cafd56a472b5983cd5589e4884dfc8170a70a541a130223e1b0ce740d	1617372407000000	1617977207000000	1681049207000000	1775657207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	18
\\x242cc542db8dceb590053b7ac5bd309a1e5e3b0f414de9e206f023ad830f799bfe6b0265ce895f9c5d266f242c54aea19e7b97b3bc0ed4c41bc90f977e4bee94	\\x00800003a008b6f7df31b9f76e1ad409b929d937953c29e2fdc92691374c8f819d741ceaebbbdb49195d91912c9f8fb3e5aa368ab6b1c8c93af5e285ce384045fc5150cfcc1171d74ce636e6b63b1fa574fb6830919aaab5e397425549b1b12fa7ab4f5be5c55b9e02117e9b53ccbc3872dff899d47eca68b03b70f45a66abcedf4e86d7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe91f185790235b69bf2eac10de9b481220747d30efa8d7d5470cdcc6a558af633fbe9268087aa5d0bc49c9f1ed9a99d7bc78b357d7fe470a308cf083560ab105	1628253407000000	1628858207000000	1691930207000000	1786538207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	19
\\x2a581693de0cbb48fe2d6b5dede82183d07e74ab44e676204ae088eed7d6bc93e14202438b9f5da57cafa3c72aec61b74c5f555aa4fb9eb725bca6f788caadf1	\\x008000039c45b291070a8c03cd0d009613db8eec9c924b0bb9f6839358ab5e33d691e719b8ae5636f1151f8fde98f45ae544be509d4942f5900ff26ecc051f49f353e71e9ce7b77b9bb453d5382c4700b0a52d661933cffc94eb0b8270ef6e4821ade215b0a1497bbad2e4d7b9817743eb72f8e0a96ad154b9ca14de6f2ac45b1793d835010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8b6dbac939f04bd1e39cfc3d7d96162367b45f729c6670731a115cb9fe4a381a94828841f8c298854eb5280b7afa52589bc63283b7553844d5ed3dc0cd7f9f09	1637320907000000	1637925707000000	1700997707000000	1795605707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	20
\\x2b847cfa647a52e8eaad71e4491aba96e076dc71b8e20606cb2e4a2bacec4b6a7defa4da43a3c697c2a0cc4d2efcd79f24c64220f38b8026149b4040f70a67ae	\\x00800003e7be46d5bb3673ae473237be3862adee3c9cda90763ca33164eb1ea3cad9d694106d94679d1170b5ecc563a11e906071e7225061a42b29c823ea321367c692d6d3862ae2c07a53b0f75e6a57051b95b3dc812b96873773058bb4a438b9ab6bcf6330b185b11d8148918da68b1ab50efc734ebda602bf4a180f3438008f133be1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcda1d30bdca96e90cacc932aaa1d75def3bb8b48bf61959308d17687ef830e2ac856fa7afc804b049a61c7f681fe66a158bd0809cb05f2d17ab76bd8579f970c	1637925407000000	1638530207000000	1701602207000000	1796210207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	21
\\x30d00af1fa6c9a1e99eaebe66dd9fd5f9df7db03055c9b57352f773a6e399f588b8efd51e80199f341bc53f1fba677932da5bf64b4d2b9b5cb51fe670bd3a1de	\\x00800003b2802e56fec9b32e0b5c05d870838d9538c813f8298b97230fb770de6698223845a5ddff70c6f02363e790479a474e1ad279493d530fe399d69155545030fe11ccb21992460893ce47c9d1a1923262c509b43c4d9a8c1121ac701fa1045c9d4810ee245fd8f9dca3fdcb37530a8d6e57afffb1bdcffcf14506d0bc76d854a6e1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfff6b154d9924739a0e5f7e1c3d8ee44318f236dfac6376619fa6b10240773600140602f9fdeb467dc5d1da97613bd117b2d5ffe6fe27bb3d302e3107153d30e	1614954407000000	1615559207000000	1678631207000000	1773239207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x32986ad209672ba332caecebb7e7fc2987bcebc7356e8c70aa924064bd83619954c60c77b136f5bba73e8be8f2cca86f35539c4980298d719f8d646de91c46b1	\\x008000039eefd0b2f7776b1fdd539416557d3cf68c9969949aec509927756cae8d86197f160c9db641b6b333afb0b358a5f5e4157a09534d3492124bda9e1cd8fed5377d27b6b7c11331e7ca25e6605ac75ddda7ec6ed20ec07ebed3bbea622bcec26384ef56856ffcccf81ec8cef532da6de9475a26104eb68dce130b5509f9c7b756a5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x79832dbfeb9545a7ae991bf530fd3ffadda886026d22d58a81771977e6ea54da7468ebaaec28224a9bead80db99c511d08fee7ef18cdc0d93f66b8fe37b66304	1633089407000000	1633694207000000	1696766207000000	1791374207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	23
\\x36c4d9ed2f9a1b6c2935ec039aba2fd9ec3892edb94901e3a2fd34d42b63a20a89ee67584f5e9c9862e00b9da740c0583929aa1b7d0e4073deaef5ee0120cf8c	\\x00800003db7985388e567487f18a5fa0f8c588e058667a79249278ccd0343d0bc40f50b145634f671372ec2c53833665ef351814e702be5684c2acc1980828cb1243b52ccdb41e00ad9043666be272a1825ef578f4d9872a2adf53f5d1d43591b924a916a1563d740e22f4f761781a75860d992eeb27454d68fce88ccf4a89a983d743df010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8e8c68c0e535162c83942979741e3a0e0987156de5bf20c4870b26bc7ed885f42d2448eda8783dd6d2b397c00bb1188395e4d1aed79b997fe44b5232e977900b	1617372407000000	1617977207000000	1681049207000000	1775657207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	24
\\x36143f082f70ebc219ccc876245aaace8c55886301a792a8605a11bf6899c32d6f0d0308ee18ffddfb894177ab191d0da7c778cb38b0f950b9a18c15a10d4916	\\x00800003fcb55a7d588fe80a20bef27334f3dffc0a4bd99f0390383c438f73744fb347271d99c1487b270138f060b9c32cea6ca64cadec2e1105055e18c7658b45ee94872f3be2e181c34ce15d8a3a8f11d00209ae9562823b2b6c7a4785994259dba21684716dfac0e1169673fdd661e43753d26e0de37a23ae306b04b888d7c8761dd3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc67e0c886248dba33aa06b79e8f5bf5269da82cf39a8db1b2f5ba75a644fdb61a9935438c2be2a5d440afe182022358e20d1567252c987dbe212c7a08da7be0c	1621603907000000	1622208707000000	1685280707000000	1779888707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	25
\\x379869340a4ce2ab26a20be94a9a4de5684d32cbcb3213bb9a09d31225264aa33e8ff630aad9145fb0699cc5c69286a70e63c34f2de4f5f267124bc3910cfe76	\\x00800003b82e98e436dbbc27f4adec870455eea28a0c3c6e3028006d1045f3945f3db08a31e99f402a9a2367bece9e83bbdcd48d3172127532e1f701d66d4455874417214651a0ad97eb4124f351fb6e6880734a4dc447014b90227e81e5a893a873c8fa37a17778e239070d9a54b73d102d3d7165aae12aed616390f433006f1e719d2d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8d0e7a0e54516636cbe28d8cc1342890e5ea21027a90da9ed42c4a1003ef33a02f37c5d8e1f5424f21547215f234e09bf0ba1617b186f18e1429960a23c7fc01	1611327407000000	1611932207000000	1675004207000000	1769612207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	26
\\x3e8c43513e5b27e367f468f9960ffbc325fa7e786003779b285cb19e17b9691e64931e93ad9e3ce1939151dc5dc921ceee7197b252966d6edf48b61dd5e03737	\\x008000039e9968d6b7f9cfd538e5b05307671a3bfdcce7f08fc4ab03d8277cd51573fa5df2c6fa9826e00c1be41395d276e44370fd5075eb712ab30dc63d37262b9d8bd97c4f1190732e5925f80dced2aae0d62f11b8dec01bc56cd4b685586b1c9124c4efb7ff0f331e25e45cc5a64e483524ba5145451f2be75a937d258d3af58e050d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x09113c5608c32d867e2cc862ca2c457a30f98b74a42cc2ced48d15f3fdb438f767d3fb5067694f29edd688e5d22f917e3caa5c666ce5b12b0a27b5e773531f0e	1640343407000000	1640948207000000	1704020207000000	1798628207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	27
\\x40bc952fd29761e89df8aa1486451556b6cc1cc6ebe48c460e5e6b5a8c9db5c5d25df956fec0d6d0ccdb70906570214e5abfc3e67f8747c404fd0de3cbdb08fc	\\x00800003e8e312e87e69e84acda6fbd61081e436b5630689cc7e27c7919e66e09827bbf761d344531cf89163eff23d18e19144fc6d22c5c40a10d885580f396b556b77c51fef6ac44df2b8b5fd7a9e53e38d1edca5fda446688edc4aa6a61e391c29816cd375c9cbbc6c495e69496320116d0e201a837a4ebed04d66cd26c23c8030e837010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4a924e2d6e73fcad4c37475851924e661f4f43fc35ee83443052eb75633f286903d3677e6d5f346f4a114ca8ed585321d68632dcf5dbd3c86756999240f1c90f	1616767907000000	1617372707000000	1680444707000000	1775052707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	28
\\x41cc2c8347f5742521370a8c13c2e0328f67a570e157bb07bfe67b29ceb6ca96fffa4c808651ae8592998b3358ec1ebefe11d3b34c899a44ab807738c3f99243	\\x008000039f004c7a435e4071071528c854fbfe3ca2d7f02658221a7232626170b478f2b054dbbf8480af5d56a0cd10aba6496ca4583adfb92ae038b6d93210bbc40e89ce0ef7be2998cef2453beb9b203432d217dd60fdeea742b71f49c1b06d57347b72cd1795213c2ae6f6731bbcda487eca90333d463d0317dddadd4396724acefaef010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x97eb2758cd217ca92326c49a29bc8934fdba56169d008412e4215030f480519c3fed65c3d18f4f36eaa4b75b40cea496cbe56dc757db13756273b784e8d66704	1628857907000000	1629462707000000	1692534707000000	1787142707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	29
\\x4674cbb345dda6b768e2aeb63a770aee5b3b2c9a9611eb75910bdc6f752401b4e72fc3ae5e36b424bafc77b2dca3d15c33affcf8b872fc9e872e62d34fef597b	\\x00800003ac7ad2cb03ecc6316c337f20b38b315f2c50a4c60ca2c1845c62ed246da384bdd1da22da45c9a7f320d211ed8142090c9b168cbae14eee1a6ad4f95988aff7a49480aea2aeded5926df7d5d6598fdf118032eccb5e971a8d884963c860ace04f3e42c8a4b9fd36e2333187cf369e924d818ace41a6936bb2f8a513cbebb0b533010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xff2eeca16c02310ab463512827ce4a19ec98b16e1c57321bdf14f7799874ecd73e2ab0d1306f6d29ffdef39e18d764935813a4e48f61758c03c310d180bb3e06	1617976907000000	1618581707000000	1681653707000000	1776261707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	30
\\x4734d66f1eaacb8c3811970455e94f4f4e2b7b39597f339c5bd20128cf3f05f49f6815668da9ba6401dfe305de1c6b42b9a1a94166a51d48ea40be05c8cce81e	\\x00800003f41f80d9eb2b1a012e73710e0d31a265465d5c6b9401f82fb1dc5b8a727fbc71f394d493428eb1a6d38045c48ba43fefd3e8656521e7724bf20a6d228495d07e5dbfc4642bd0318dd0d816a542861b1154fe45c709b360a77be069b1c34fe20e40c11cdc4a6c4ce2af0a12766909e7a2f7176f93febc609657a7eb4eacf76195010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5431b52189088c0ce2750b0c7cb211ffefd0110e811d4741a67172197437806e406c195469bedf4dd98a68133e8b1839f27a9a020c2ced14d299e26f95878602	1611931907000000	1612536707000000	1675608707000000	1770216707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	31
\\x48c413f8b78eccb59e41e5a46e31bfccebf47126af43dd546492c3cd1b6b5e964e72c1d0b866a786e2bfd315f9e8c1ab71c392f139cb1f862b52e7195f80b80d	\\x00800003cd05ad1f4655e5676b0aca709f86f2984270678b26f7920bc8c6b0c04d0e539cc9b0afe991c94ce92f018c35bffec00c2a74b800475fe8b1d047a197ac499074e727d794349dbf730c393ebd8d67bec2aab934cd7e7f2bd621f15a3b6e59b5a94d16f412afd332993c07dfe20f999d3139bd5e166e9d6608f12f152977b119f7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3795992c948fb9732f7aa716791e2889e7da082adae3c5068f2c899ab2843ee8a32f08fe81c004e48ed955771ea8360ac54ee4a43ac34f74304d2812565dd30e	1637320907000000	1637925707000000	1700997707000000	1795605707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	32
\\x48dc3537258ba2ea9340d25b7d637a9fb106a10c9ac1f44e4154d84d8bec5b87c06ca38f0b34e5fbee8556368210c73eb0934b3ecadd6b8479b92866ae20aeba	\\x00800003cfc8b0e594067eefd90efa2480e034649a3b8b668d4ac1639da599f72069d745f4f73fecce9f6790a84071fabea024c7bcaaee5d85164b252d9e00f4dc30af7f3161dd2eaff7ef5236605fab91be6dd9a7d9a990d837a8be8bea7a6c08e2dcf43362840d29c20dffa12ae5174aab00c0e16b6c43e6b37f5b1df55a4307259d49010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7be5d43f240b5551ef239ae7ca62470631fe25f76a641fe32f5cfdd8a50f3cdee84cc5f53a0b500b2bce5fd0485106a162ff28e1afe5438f666a57a8fa78030c	1625835407000000	1626440207000000	1689512207000000	1784120207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	33
\\x4d1409bf7843396f3697bb2afec2c117ba72a0866062e1c8dc35e4b9d36aba07a71f50d3850516884cb56772bb6a9b24b371684e25aac316e0e0be06731acac9	\\x00800003c65307f213185b74dc80894b200ac4da7036075704ec0038017c077e12cea2fad2c525b3697a39b0be59e485635b3b5d2eb8eedc9f7cd7abe41170c9302edcf6ab91d3b0908c226dbfe09a51e286903077e940d985465c456c28d2a1cde05bd0d3431382325535de40d3d46ca9e320d58c3d60d617ff75558863def4e0ad8609010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3463d66dd97e82268fd41f9f1fffb92aa7eb5c4865a4f243a383beb9ac787c653db493d3f7cb8b8d4a4de72ed7925bf2d1023ad28bf76875cbc7173a36815d0a	1615558907000000	1616163707000000	1679235707000000	1773843707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x4da8618b0fd970f3db888990c98914c5f6362c5256ab4485574f69e568532b0540a6721981e461189c017bd7222164bb66af2dbf7d7441e68dace62fe009da48	\\x00800003c6013819f88f248db46f5473908864b3b5201acde021eabf06a95c02166d3d5a5083b2f061b9ff74931cd5c6e855b49524c82c2c2e08461333c7bcd8dfec6aca8141f9f73e7474a7651034e324c4725bde90a2005ec120fc3004a5337449ec73536ea9befce4e4e3565a90fd18ed2688c5b45083626b605d08424eaf7d52f597010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb936c45e05d26c0ffe3055ceb4cc2c4f2e94a188abcdac0e082217db3c75465fc749c59f05ee9b7ae6179c58d020715876bc1913316d21596231c9d6cfc15102	1628857907000000	1629462707000000	1692534707000000	1787142707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	35
\\x511c4bac5ac4273e423c67c90276521637f5656082d074bb40c5a19ef7e990a7e4ef68e2e34228465f654a0c05f5b6120928bdbd50cc164fc041348776be4928	\\x00800003c7195ae921a1536ff15c5a7fb1fd0f1b78f7ab419e73073d8559029650c6fd2427d4bd55610535c13463cec34521630caa8137889394a39ce564633fc867500c9c1625e64cd892e660ec8d8a7ebf1eb5713ae00f7a4107bb9911aea970bb7ab492a2917c8aaff02bf98a60081c9393cf291b2200f02d0668c68d8d5ecfbc3355010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9731ed601d7e581d10256e77a10d4201bf29e01a2c8ac0d780d18e7d6c30b30af6c9bd52ca5b8f3a7dfcae27509c0652f9ecf9731830d8d494ab6e629ba91309	1626439907000000	1627044707000000	1690116707000000	1784724707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	36
\\x5574746abebe7994de0c065cc1b0b32bf8006f7d1f196dbb44ecee07792a7e691a00e994e75189cd4c63e4db21560eec4f54fa9ec3f50250e6aefc2e73730144	\\x00800003c126c8ef95d661de5cbbded939588e2c5748505ab8f23602dc6da69d28e3ff8867d238bb97e3aac9f33af8b90d02e06d44c39e26fad1a766859efa2eb2d5153fe35f7d9c3dee1ac1c2ffd778c776f09b4c4f7c963970e5a4d5f5afcdff71399aa805bef4defcd7e0fbd1d8cc28e7eb38ca6af8a163fd5aab6b6c7c5637c7287d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x58e32f75b67b55c79996d5fd1126bc7f604166c056c3d2f5e41c09e222dee33c88203ac90d6025e84cfdd08cf6d64593c53de4dc89bc7406144ec711d905ce01	1627648907000000	1628253707000000	1691325707000000	1785933707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	37
\\x56ac95a9de2e8b99e91cfd0b769b37c377143f59acc93392207ae1fd367b32d4fbcc04ada67e2100bab5a52370aff5b12ffcdab695c7af93ebec7aab176d45da	\\x00800003f4ac9190cf6acc065ad5e776b999209ac91fd59812640a34e6f2019c505797d6efea27f5d52bb859b8ec5803d40b9a826930e614c0eeca064fcfe8b0462de10c2b00c8cb161297a8b9af8f0aa156e72afd2b13bbd11a05128eb7266027568cb4738943b231bd833b1a538d10841a447cc5b03680b74dce57b545b944ec836213010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x70f5110e2cc9cd65c5e569a3be9ee19258730d4acd31911df0a76dc5324e9447ec45111bdcb8a6ec968adcaf96abf51ffd3196e5f7a560cc2fd07bc5f48dac0f	1628857907000000	1629462707000000	1692534707000000	1787142707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	38
\\x58d09192e57b15e608f2d47e08ef441145aac272f1314287f86935f821a8ea24638a4dfbdb7493c02b56503989f7ced14ec9394a00d0437c4f0b9396f811d097	\\x00800003b19a825f516a27a654c1afad3a89276f82f27e52f78c64292234d47702f7dc60b3b7b4e4befe4f43fb90c0130f062d11e208cfbcca6c8a3add6ec3c2d499415701d79e891a8d8f67faa480225e7526094f5f47049a93493955bc4d84b6fff2f596766e9bc907fdff51975497082c7f6e1d98490d6e7dd1350f2cd21ccbb4f69f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x08cbd8e3d242723a2aabf1a1decf5f8bb910f648d2a21462d07d96325e6ce10cff8577e8e3ec9bf162f14656dbd9e26268ef481049677bb38987d78f0e5c8f0f	1635507407000000	1636112207000000	1699184207000000	1793792207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	39
\\x58f8e3ea43a97d85bda5f7c0eb5efb7b58961a90608aabe594e8ffb40ce22a343d935b1e82f0df64deef0e013d579afc831212f2ace0fd45029ffb0b04db8581	\\x008000039aa9d5443357b8e6a3b066a008e1e7187511496decc75926df7b39e88f708b071ad1a4edb42a5d7e44fe69493b1fe49fd6129d60a0a01fe9a9d9f67cb2b8b612fca40c2bb9a06ad38fcfd6c27eb405524c94ab5a7c1c1cab72b98ecc9f243d2c26f9afd253e73fa914df940457c27acf24f4b75a2da15662cb62a30795235b5f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x56d2f33f59c53fd5c4f6b3e9b76288a3bcd00b113b2784189938b5267810ca71b6fc57d324ed63e71a5ef805b2847e6f99b1f4ecad13ce03692d9c28a7e8ec05	1630671407000000	1631276207000000	1694348207000000	1788956207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	40
\\x5a149c27b96803998bcf7e855ac762ad1f46daef8d994be766aa2bb53070d18e1e728c7eba3b15f892d0ddbf17214c4724d8c4580bb9fdd0c1fc03aae4366338	\\x00800003bb4f7530c5985b4a6f46592372ca883fa8015027675be30c26e6b3ca46a11bea1bd0263e87addfdaf2fd8f7afdb087967e97d8d9862b823edd30927c0702acbaa175aa6bff2a5b14f54443602337c284d902e7dc08f38fd7ce42519cac6efaafbebeed3a80e8426f00068a3b4ea8206bf4efb53026c932294996ccaebfeb9329010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0bcd66f23603c570e910fa86232f5265b1f9732bbae3a0842b96c144dc08f1cc41b2a35448c6771f60459c6c5b9de64db4f78fbc61e015ab9eebb2788416ad00	1640343407000000	1640948207000000	1704020207000000	1798628207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x6070456329455b1aafe03f7a100349654e66c725f7e37776da73781c822a42df1dc269c65881bc0ed98a2a5607cfa5315c7cb2ffbae972d9d920e18595cd8b18	\\x00800003b456a09167ca876217e4a937a04fdfe6e7160dcc23ddd8792db89bdfcce90c10c64f245d6bcc6e680b83a1221fa8c66531fd6d130d097276184c111305eb206e1ede6ca5b3a9b7d4da522b7b79dcab5b7031add52fa9d41c0de712f7eb275e169c9d924b763bbcfd9415f463299f4527a8823f462784ff20ce885b53c9ed4749010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3c67f1b047908113a50c9967d18aaf873007417632e6547bb48db470de23a19ca376078859224915a056d5a42b9cee13e16e2ef969f6ced05dbc9993d692ff01	1627044407000000	1627649207000000	1690721207000000	1785329207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	42
\\x648c4728612f58e18a8515108b0be0f7251b52fcff88db9aab8a90c470d4b334cf8af5a4993c5c0ce411953b69771be31124f4ef03518fb2f3547ca6ec16d13f	\\x00800003ce1a442b8bf15e85917333e83192f53046a4e8f4379b6fd96e98ede6335a2bd1a5d30a77bd6752438b931af76fc70b629424d159f0110c0a2c35a499fc89cfabbb860a7c3932dd18b88665f72d0cad618f1e3f99f0e58b311f12031aa31d7bce2b0bceefece283b1b2d475ef846e308a7a0c372452f793717121318abc6428fd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9b4306889433a0f989792f81d41587aa4f56883699da137af0abe45df3813cb50195dee5c659d149e2590842e9733bd8bae97b10f1f37e01f360ccd3c0a9ed04	1619790407000000	1620395207000000	1683467207000000	1778075207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	43
\\x68f8d0605e8c3fa29219f6b96328e16141843a4ed23966190574692f2bef8f733b08ddc8672b245b553eff595694981b48c22e6cc7a0b4bf77c1c459a844c091	\\x00800003bdccba6c2fdb177c398b16803b7ab5749c50785c1d1ca6a729e61c903781323c124ae1c25da2acfd19bd58c2e622a10c9ba7a51d7cfdfeef8c9a4caa9d99611ad981a341bfb922ee630dff1444c1cd9cb263ecad51f1f8ce77557b097aa6a461ecb24bcb77e18aec74da9e55dc83a8ad01d553990923505989a6da123241b331010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3931cf0f0cccb011fb9b00b003a4ee5268535221a3d363c160584568a032eb2b77684a325468715eff4df189948a9bb0d4ed590838cc1424cd8c90ca7896430f	1636716407000000	1637321207000000	1700393207000000	1795001207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	44
\\x68e42eeb0191ed426d242643872d8b8703aa00a13353bb93a50f49a60e139425a20e2e2c8d6a3e991a5571906b1dc4d08d7dfde87b1b765a53d37e13b0294bb9	\\x00800003ac81db7599a9e4fae28b080649976dd2ca05b4dd553805064e39de7ba6f627a4dc987b6c8eea9994f3360c40a53d812a405bc62cbd55c9cb77564c27d7711319ee1d65f509eb67a1a729e18453a360cba9bba94dddd09c1155ae95a2075a33dc59a8fdd1cd448b374dbb3f35f9f313a8298c50a7f95a1c759bf7f4e758662405010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5cae1e3f2d991348cb8e369e9bf0e184a7de4470dda86b52bb9c61cbfaf84cdeb9aaa545e2eb03400449e4279e3e6eeecdece72680e0d62a8884e5a852d8de0d	1636111907000000	1636716707000000	1699788707000000	1794396707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	45
\\x6bc0dcf9aebb397813819b7892458366c6747f9d78b559ec2e2b57d58ab50a7bc39d246c7f000fae90f13c864180637704414d638f24923bb0d6812ee27d85db	\\x00800003ef66ede7579fb8ee6a9315617ec7c71b1ca247ea17d57cebbdfa3f6ad8cb88c6e56b16edf07d7f1dc5414586b12c83a9cac8649a240892f599d8fdef55350540c124c5b74816869b3e61b38c133e334664825c8d5f55c27907209a4ba2761e8a7238ab88a1885ce92bf511a63c46071edc843ec61b2bdd571cdb4c640cad7e67010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbe73c9d922c1f4ab3936c481f86d01fc900a42b40c8a113312abb315a6088096e117eb4ebf163085398d9232800451bfebedd6120270090c8bb8472a86d6940b	1620394907000000	1620999707000000	1684071707000000	1778679707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	46
\\x6fd8fb1fe8299d0b6d8a056f02ce7cbbb3cdaf0f65dd2b5440d4830e2f0c043f53611385e9046bc184d52affaef3d2285ea0001a86c9355300e6780bd186fd0f	\\x00800003f19e252aadfc5bc0fca5e396c03c0899f322ef27380a4c4db08a696dd4d8b79d606179c9a16bcea2aa8e7ccaf60be0bb02cb4e7454cf36fda02d31abfb150ee56cc5960197c4ed4f8fd4be5b1a2c13a0f5393a52431685b64ffaea91929649c62cb06feb5df2a0eb90c43d4140206ff769ff4cd9e82e1e266e55e52b1aba237f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd1643022b0ad9a9352d9a41ead01b12453741b12d2764894160365b1e9dca8f69e31b0e16a647add13826091968c31c52a334ef93c0be80a64b6c088195a9d06	1614954407000000	1615559207000000	1678631207000000	1773239207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	47
\\x7170f9922de3fd74cffd0fcace5b8e96f69525c3f15594377c31ce094959872523538335e4ba4f4c8a0cea94b828977c9faecd9b87be3728d55cb9b1538527a6	\\x00800003a47871a880521a533958e058ab96c10fbd288f639574cd38209246d6bf5677d655ebef8c34e5544798297ae79fc39a1145eb3ccb561a5f828ca1590da190066d7694433de51ff93f1866ec11e15c58e6a73df2371fe7b9de25ce75d48162fbdeb26e10c2d1d1d2dc1d01159f265450edcfbc6ba1a822595d00f21d02c72392bf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc7c47bc7b43991032df2455e41dbc5d1ff8acddbb98721fd052a044982f95077afb36f187df2219efb3bee353dc114ecb481f5e3e06be4692abc0f1d1a5ac705	1635507407000000	1636112207000000	1699184207000000	1793792207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x72c026861ade811cb56e674f2d90483d699d52c3683c11fed6f9bddf21835bea8aa0492ebc9a89b56380bd5ca3692226078a0019b8af956ce1235f5b1716b8fb	\\x00800003c28ccebaf7dbc2351d6227ec6f441391b817a6f3d169531ce334c6f802c121dad19073fe9e028c3a8d5b970a1a20ba3bc7a773ef2b3be062344db09d5588b95fef84739828cf8e9d2678a6200c8b526dcb561ee78d6982eabc2f99b75b2fd25231dd9c2bc377b61162623313143679f8e6a92cb28135d470dcd979bc185676d9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x87b3031a9fa6284acaad98bf020fd91238d8999156cac827feee234fb5c3ad3f9f742fe014fe67776b00e0760a84f25866195a0689bd506bbc0269b0536d8303	1616767907000000	1617372707000000	1680444707000000	1775052707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	49
\\x731ca7fd5e4f83f4fb38373e9d25d24b8647a8631e1064c79975f71b8c6f7b896d530df157bdf7c6d768978f1b25459549d146ecabe4f597e8262ea96e3fe372	\\x00800003acf49d1c7df69cc68c3e7db4f575b69ea8ed61ee631ff04506705ef581c3510d26c7d3052ae8349f26c9e674f8359c5d4cd336cc018fa84f61f3dd29972797af89173337f19840c8b64cc7d8433a8b23674ab5f2e820c5be54c415ba37e6f8765464f4eec2c740312a773f15f949f4e918bf91aa551176e52dac69807c3ef98b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3e78a36869e8e2a9a72f9ec37e02850c7aa301c506ca22ef5624bc660ecb7c7363e02ee617c3ac7fb03e0754ec1d91b9d664cd4649812ddc8f26d56ffc101803	1637320907000000	1637925707000000	1700997707000000	1795605707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	50
\\x75f08b934c2ce05057183017a01e4c79dc4e69576c76c4fa77eeee3eb3bf67dc48543db3df43d68dd21079812656ed9ce9d345200cb33194f5588a0aacfad2e5	\\x00800003d8adf4b1976dca697c751888c525930c3ea1f27f2d8280f7c110454e82555dde9d8c55fd385e1c17d0ad2bb873370693ef3e955cb0f9769dc2b4efe74ff532cf4555240f5cb956a6931ce7b66ad7e4bcced6c3a625553775fd6d76fa943781910920eb9819e9f653ad3e26d930fc3ca37ed45e52453bae41c85b837fa17237c7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9529a699fdc9aae59dd1f2cd3ffb9a82787569123a9284147e7681f19ac481fda3947264b1ba858cafff47c004865fe721da1682915c6bb575a4f7c552225801	1612536407000000	1613141207000000	1676213207000000	1770821207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	51
\\x77f0caf71aaf8d4e6ed3abc11decd984590301e0ff9fc7c8f911e984c7b9e5e3c45680b76fc64214395c6c854e82fea3e816e52f54b253b9a621c27f1ec25c0f	\\x008000039b8ad9390ce1246db21c50bfb2ec5d16f7eb09c03cf05250e1cfbd29aa36618b9b32187ae312dd6de3f4696bd0a1e824e0a705819c0ee888c39962bfe9337558b03dc90c67d5d9e07bb3ac7d123e8b25bf5132314ae9550b1ae0c89261b87614aef8fd5aa85c92217da5eb68db17210e997a428109cf22132288519c5e8a0c79010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5bc171953579079c45af5dd29e85a24df270ebb2adfd28aa5cd4d254a084c4031903a62ee3ad81aed249b7b9f757af1df381c7fe0dbd5520daee15dfa6b0d006	1610722907000000	1611327707000000	1674399707000000	1769007707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	52
\\x790cc158253f3313199e06727366aa02cc0255565ebb99750d7f37630803d04a44771012336d36297de4a7a0a0bfbd2a732d25739fe2d1a3349bef7cde595787	\\x00800003bf715b65e051d935bfd4f9bea92deabd0cdb7461408b0345b2b8ed9d6d9511834ced61f0a54439a869be89d7f4ecb0d199209ad3c04855ecef4fc5780a783007ee56306f8b61cae7bebe0cc91b00dc942f9f2588499817bf2ffb67effa14372f26786ed0fbbd5ef67455dafe866878f70eb99645577f5a7ba2ff7b1cf8ec044d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4a019899e00404843a25aba8e03f53e346521f79734e5d8a1e1e62ffc3d4bdca2ba8f2a84c23bf224e7e78435754e36880179ef788b80edcd388bb55075fda03	1631880407000000	1632485207000000	1695557207000000	1790165207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	53
\\x7aace6b5ea353ae54c8e526f2e1f43f8f68e37a08ace7b71871b017441f5b750f2258c9a364054ffd4a6ca2b4a7e022a1e015308aa79370455d09cf4752a2fc1	\\x00800003c0b6f741ad374e3ed17ca15eb98bc63ad186903c9217cb54a6121ffb7a07b4ce7fb906ad6bb26538e753ed94af44e89237d78da838330671f369aba36bb3f9d5ad47649aa94bb58147d49b6b95be5ec61cf21d652dd7eb6dd3391f16c63b9e7a6221d3ac8f15ba4bcc8dc310f0435e0fea9cb43fcb8ff96fb7836b0b89c84207010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9c25bb801ad34fca2e5ece405f0c742fab71c5c8cf817edcf167cbe5aa5f6481c6e465518eb6a981f88ef479d3ffa117fde5d3232ae32766980e7fe1ca0a5a06	1612536407000000	1613141207000000	1676213207000000	1770821207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	54
\\x7e8c107b5b6f6f5bb2ffada081094e77a99606af0eda71dab574f8a2bd61cfd27eb29d43b84f3d69b6aed0026b403af611db39574f243b32d410f91546ddc592	\\x00800003b1cead0dcfe0c49950e844b299122d289c54046d313123c82601ec8479585d39ef9be0e11000376922db8840cfa4061a47c91614c38425c7bea31549b0da6b636104e44106283aea4d63b5966510f79a28a396f92966085b0ee881470964293dea29616f05439626cc0716c4329fe442508ba49d920d812aa256de648ff775f9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7715a1603ecd27ca14a70fc7c284123120c91c008afeb2e5f726355de0f6ba604ed93989b808ba6b37c54a69a65087d1fbd8df73d5df8f0f6d6da3e7a25d5303	1633089407000000	1633694207000000	1696766207000000	1791374207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	55
\\x80a00122e6cbb5cd267221ab6f08aa2ae88755ce30a1395a1998b0693442e2d7d03ab64baefeafa413e2ba9cab6629a97b16cbd586a102ae53767e19c6125486	\\x00800003c69c275e8b5377441a3e7f2305b49052eb31eaf3cb7dd26dce917dbac604dff1df5556ef012bf20db18de386783fa150d052597701aea0e517ee07fde714484002709d630fef28c9caa14b2bb623b9c0b1b041edb6dcdfbd3ea0b3955ff928b87011c1acb81dd2e33381a33f87d88cbfdd67612d2407c874dfdbf8eff70ef975010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x986424d6c06530c72f999f9429ceab5ffd94bcbaf49cfd086c16341addb9c00da87af7d56997fe0ef09ba9157fbe19c8487a69ee962c380c992649ab66987809	1614349907000000	1614954707000000	1678026707000000	1772634707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	56
\\x81d0d3104b71970c34c689e7edc945414171803056c74def40b54ca69776e0496a0658e46a350ca0f50d1e693e3fcc0af89b9993da5e994f4c0d293496e95fd0	\\x00800003d79859c585b5d8d9d440555300a5e0debdf228b6c99659f97e5a044ee800ab7779cf2077d9da5cbaec1023bf033ee3e8d0a5419fd96ef30c2e7ec925c8529206687b23e2e6a51acd2ea0d2a453b8e5b75ba7b705d5d2a85273d1f989509134a393d45d660ddfec20e26f1ac27abdbb18da4c68e2201d2900aa2f4d8c4fd067d1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x09469947abd5751b9177d93f21503e63152e0cc01c4c7d84962889dd5c119a229ed14c71bba07094f2723d9a7059a1813bc814a553b6cddd92373b3b6229390e	1630671407000000	1631276207000000	1694348207000000	1788956207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	57
\\x82d442797a7075d578902c1f546208c3f1b04bd9ee5c0a255a02a42f339162af7461d89ea3799335c8ffafbb82a26affa8106ee56648998f632191a6b6bfb8a3	\\x00800003ad77eeb7b59641ad93d8204f00a42b53597394f32c811d8788b7f8f1a46f32c7242297ac1ab72a2ce7dad08d5ffc1e932e0d504bb2d8f0355f7c7c788611cc2d33927a3e6d96eb96d60308252093cedefb0aee156ef9c7c4f231b053b95c649b73b4d035cab3c6cfae2edf68b99d6cb816cfccc36e74fa3e20f5ab1c60dfa889010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5b67ce681dee7cef6e4722c4a00392cb8f49d519af445f874b36f4d8d58a4de15c940f5c5ec5caf160084bd41fdbf5380c53f4767905831ba47fc476e8efa00d	1622812907000000	1623417707000000	1686489707000000	1781097707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	58
\\x8340bb3d254be676321716a724d2b53b7693f373fc2448baba884457bf5452463fc3ceb2f37a6b54ece480ed5058704010bcdf14dca855e14c5da947ed2e37fb	\\x00800003b240c3683f7b2eecfc8bc16a5bf8614191681a61be33ebc2fe50606b93f89e6a07692206bd6d8e7044f63a396ae7cd765ddcb3800df1ac5265b2a47611739c1ba8a0f06840916ae128d8e58457f89c951fe9f4067ea5da630ddb56cbc84a4cf6700c2d4a5e940d75294aabd5f0b5faba491f5e5bc8c0d6f4e69ddb19bd7820c7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x080164f3613c9d256e7b3e3522518ae41a9ea2ffd556e51c45027eaed5a6229c09e974d28f97c4273b174b707d34bfd9110f19be580462742ae4611dca26450a	1634902907000000	1635507707000000	1698579707000000	1793187707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	59
\\x87c04ca6445002c10c2942bb5b2e9e9ab4793852aa9d275d0c1fc68b1688a5921f3774ded503633ea45606921b0021a8462f9cd0a38a0c61274eca3d1d4ff9b6	\\x00800003e461c9a55e5e045f053e5d2d056e678f741c5db78a03893034592e175a156c4f5b3229da2f18f2ab274efad461e32dc505d1c7b8f92b69c124ee3d9b201ef2893dc1067192da503e27dc54d99e3a0548945dd5e0a056d0eba00417fd51ba9b9e42eef8f960fde19a20fc888b8fb294e200bd24e576cb220280073ac365e68c1f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd1a311b8947dc1eda02ecc2d837e7840dbcc653a4ac2c3d34273c40d4cec25c507ef3bd23b1bc0aaba420bfea2720ef506bc48830f943f307435ea7d08031c00	1613140907000000	1613745707000000	1676817707000000	1771425707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	60
\\x88a092885711ae3e4baa942515ece0da204676741a68c73da4d40499f5135f6366bcdae196c5cdf4df4cf2935a3f369d00a31d410cf6d4ea98557f61c61868fb	\\x008000039f4af742b8fff70d3be0ff2368a71f133a87fc209aca96b6a186b6269cc4826e49aeb44c4be90a24f6fbfc29c7d45e345f03881468e2b0cae793c80b452f3fa76063a87ce095e481a5f030615a5e5b08110f0e5a14f648b3398ef1157b9f063b32133168dc8bb843e2c3e79bfe2ecd7fcfd6093fdb2705107d1419f0f12f4dd3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcf70548a9b2a65a0d292e56fff0a804ab4a22a1dce41ba5fa9ff956fb8f82a065c52430e2d06d41073e964bca5dc35cc898afcd586fb29a059e1149750a23a0d	1631880407000000	1632485207000000	1695557207000000	1790165207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	61
\\x89e8fec076d5b14cdabf66ff6862ffa81737ca709540c252bc2c99aeb8e5d3b2a8096daf15d86b11e8ca99ccb141584188a63da1c66b6cf019f39fc5140519f4	\\x00800003dcbec999679ecd0a64b1d29f06f5f5efc7fc44251a5ad799e7b9ea0d16b1c25ac23c5eb26837f34d34f0d937e158793d1c5829e5af05559d8690f5116c70d7176a898fb16ee05daf08877f081db8e6fb5a72d5fb17c41e236e2fdcb48d6d35329bbcf5288ba237d0248a7ae8d6309d5a39eb406bd0a090ffbd78c05fbd8864ad010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6b7e282063205c63a2e1c07c7835c838df59dc38c47be54b7f5e0045b82f3799c8cb432d0d212f72382ee408cb47f04ee4e6ae979da3dd250c00436555343809	1627648907000000	1628253707000000	1691325707000000	1785933707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	62
\\x8cfc0c6d8d9f7edb50c376b67cf594c924d746b9f09632a4117ebbb5532eb382ed4f2c8bd640fb69e0f503ac5cd5197c68bb8c0259e1f5293914fbb0ead55f72	\\x00800003d549cd33e118e3f770994d69683d9bd4628636dabfe6eb46594b3fa328517c4945ccb02d52c41ec99fb0bba4f7f1fa18f43a06fdaf3cae5f98580eb4b77a68b0ed01d3080dc387cf47bf15ca6bce0ebdc66a2ab8da201e6f45434a91f68d145031c624a157f75f5fef32d9c17397708c667222fd61bbd00aace966f0187d6f57010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6c3c0c8451e7cdcc80d867ca162dcc1e748dc255b36d1d805e36d0e28bedad412a3402efa8bb03c612721aed9b10443104ce2d3085bddd9682cbc146e0127300	1640947907000000	1641552707000000	1704624707000000	1799232707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	63
\\x8fd0694f14d29d53beb292bfb0c06525f089c1fad90fefeea2bc5976fa79b4832d3ff74d4c5dd139794044e1d652cea397e5efc9527c031286c4da58a9f37bd7	\\x00800003d82625dbc338c4fb94d9bb65cf6f97334d079613d3395c667f4e48a1e9a9f3d5d84df0447f5e2679f2153ca426df3f4b613c067906bf1a858be018c5d29d5f0050dc43ebfe466b5f53bf3803d1a5b3552436ed1f6e96295ba886fa37edb1f7ee669902875de1bdc4dce1e63d76e3586a96ce2c7db53adcc12b6f831d73793d8b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x00e525f1ce231bd11d4b4612b2b0d674dc09ae1924878f8b0add8bad465c8a65b1dc63815575ae421613b066ea6e7b125b9677d21b742bc017748ee6e4c36902	1627044407000000	1627649207000000	1690721207000000	1785329207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	64
\\x9160ee88cdf84fcce61a0ecfe1d54731f0c42e928aa8a9cb6b647eae92409283428d4a3ee8c91cd58dc5c4146873efdea3a8fc2829e1831899bfee59f7a25e76	\\x00800003e3397436c1fa1f2fe5a5db8f5dbcf5a7cbec1dac1cbd0d7aeade4cc3818602aa67bc1f9fc8038503e05e3c7f33c1a2224d30e1838415ba93d209745bbe58bc9d2700d6f952a36f2f92e33e8c9a1261b9498ca3525650694ffd4f6f4954f18a76f93c28155117c7b2bf7301d6620ded2701e0b1f79f3e2605e250874f2cb667f9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x29da9e20e60fa66887d42bcceeac6e0eaf02def0f1ae28e7263f639f50fcb5aa2baca95cb772cc6fecfc45c6bcc37f03b04142edebea45fe605b887499862b0a	1615558907000000	1616163707000000	1679235707000000	1773843707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	65
\\x9748f07da32d0d7b745e92b09f8545dcbd57a58df9390da7757f149f3f673dc7570438a096bc9b1e7a27d38ccc00afe8e7a48b02c7616778f4ce3d0683b37891	\\x00800003dd74968bd22de892c4757355862b62bce62bb3caf1823e0f4209b6b6c52c82add79bf946f62a5b8a7a08fa656a4b6cbcb48e72e03be5785518461956f00e79943e031e4b016e47f094a8bec1ece4c08c77b712e0133da0bd36aca6048d1a3c7dfaaecc5a378e7ca5b1804f45a0b0feb63644fa7d64b384fae503f7693311ec63010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7b860c581e05a0fa6e8b9eb61931af264e4943736166e54bd34ed9b74a94c4d9df26168c5be6f8f8134ccc3b2ffdd2f61e065cbba6ed9120aef4f15f2cd8df08	1621603907000000	1622208707000000	1685280707000000	1779888707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	66
\\x9b4cdfa13daf241cfe165efe7c33e1af8e0f93bb96c2f94bc65aa565c672ce421b0c0bcfa2c97a532ba4eef2a5a46387b5c133e144cd66cbedf620f3fa52e1ce	\\x00800003d0d9e31f8a43ea9549613dc4ae64347b679d61a3b5e0503dfa1c6427729b457ff9c8d79460a3096adcb6372a8982ff55e82b475ff8580a2290f3d5b088d61f13d4cccef6aeeeac4c3736f8d853e3895611c47258b23f37809e8128b0fdc97992d084ab2dda06e820dba3edcaaa855549f95471a2a9465439f237a0e2e19c334d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcc08127a693f3a4db2de7317ef5b0759316f3eae4c9c4cbc222c28a86d36e262ab0dfa89fe75402c2d6091bd6f50b2545a00f319db75325b2005e94a09361108	1620999407000000	1621604207000000	1684676207000000	1779284207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	67
\\x9fe0dbb2f9b58a88f88adbcc46c9271dbb1dea767e2a48d3e85fec9d3f571bce501048241b135306d59f0bd410d962615a5facd5ceaa830ace6310f30ccb433e	\\x0080000399303ec176fe0681a262e31772d3c4ce4fab1dcff1ab7a26545e5e3cdde01c1a150c15f499a49cefc9138df996eecc0ac678efdeb49062a02accd49e3985009e4c1a301912b696d86a3eb3130592ee574ba1a0dddb9cd1f133a5e4c6345b34ada3b397d11c63d45c71d1867163944e879392acfb2fde7f15f69e4e26d61ffbf9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x25cb19f2abf480191c984f037fd6c99e50b074eaa6f2eff7b0412371de252f0d0eac9b0ac9ba130c007c0484de8783d942042d9b62c412bb626d75459c79b001	1627044407000000	1627649207000000	1690721207000000	1785329207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\xa2848386e3020ba9a5c14b531e2cbd894cde33784106216d87531f75e69d7c21322aa901e5fd999f4e7a8a6c5b2c1e04daba5de1d39efed5474cf0783b3195df	\\x00800003990e616633959e374ef3ca590bca9c6625b353d9c5c9281f510b68c5933273f9263a72b809a9675e0167d66013f47da1de8684e5385d512f314d408a32540b4f8b9e31a6cf09a6956ae86ed2d64a83c4c51d4602629eb0d84e2d281e7468473f51d00ff42c837e902d16d2b28857aa02d26d5cfebf986a99cd287f7a0a42438d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe55f5a364c54daa1ad3dd4702565a7235ce67a7c8c70aeb0cb8684a53fecc535b5a371e2339ddf37090f95d20da2d8b177be74105e5d5127989751efad874306	1639738907000000	1640343707000000	1703415707000000	1798023707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	69
\\xa410a9d3c08a141a7f8f74ba95c38be3e72d296d2786c7f885a08399a3c74d1e70b38868b4b3b07d244a72a1b0905c8ac2fa6491a9846d1cfed32add773d8936	\\x00800003c1408788d33a8eac4d201de488863de90b49d3d3063431e94b7ceea4d799de4f15dfbb63e372143b85951906e479f0ab7bce56700121fec9d5ee72f9ada76185bd5539258e3d1563f525fb8ea43db8df06da6f319b3bc52565b49a9d0d5cf14075b8c97fc0105eec07ba5deebc4573353ea9068d23f85f94491692b945d69603010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x73eea453e9bb9dca02da4f8223c75c16d2dd7520b835f9edef342fb74a07d2b63cd6554fdf90a1a91383860a3cac7709e074f87a55d1e4a0693c07246a18c107	1639738907000000	1640343707000000	1703415707000000	1798023707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	70
\\xa508c77c11474d218c24b7b8fc85899b04991d25f3f7d0a1e903de803be59d2d11ffaa5ca6adfd8b011ffa751fb6e6ec9a62a14c602b42d05acccf6398479fde	\\x00800003e7b73dc0f160f9f68eb31e8fcabd2d4415a5c35eb978bc8184db978261a0f0e200cebc17685f2ef4dd8481b8826cc8da2c26ba48cb097bb4204a06955487924c66c9b37d87e1148afedadc094b4032119dfb45744f91e16dbabfa5369193a4933cd9da50776dcae628b91f4dfe1b36873471a4c412e15e0433a37a5216d37933010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe12b629b470b64e1e40f539c576d82a754c19ce93bf1a27b9ef44a4478e7748111a135393ea417c63829f5131837b9b8fe83ec1c22591d846279f1f4fbe6ff0d	1616767907000000	1617372707000000	1680444707000000	1775052707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	71
\\xa514946fd0f996d7b13adb393f6aac1bbf63f55b271b953d7482a4bbc6675921681f7bb2236f9d38c5f63437debf3b447b9bb57c9d76fbc12fcbe352e74a1921	\\x00800003afc91601305a1fbf2e3714ae7005ba35db138dff7943a439f6f81acb0a70c4f9faebd196c50b792a386dce8dd20fba0d91923f82a863634a07ee7f40fcd8a0059ca08ed6a37f274d23ff9c7f1c72fcc03565fe98c9ca7da6f52346e4316182cbc4524ea2e894e9c318310ca5ae5e06692c28c94fc065cf07d80bd86599be2de9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x020a5d42310f1c77e260d7bd06363820c72d645e3ee765da14398cc0860b658b63c5772c58060287189e6b28c744fc8711e16ca09f26e7688542a52ce3349601	1613140907000000	1613745707000000	1676817707000000	1771425707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	72
\\xa9f413d694bb4ef30d362c4112724cde24d740941566effc67168a939d64397d6b265f7f055b4a218a4bb26a345e7e7f236bafc1dfe0e188b83f7dc17867ac0b	\\x00800003aaa3357e7263d8bdcd83fb530e5b8fadd48dfeabcfddf502c82972db880ead00459774c233b71e0a9eb97201410a50f9c807e3e69fdbaf9fb69425765c3929320acbeb7c8aeefaf6e745257f121787448d7de8bf9ace4544a5459049983a0765fecedea6a3d55d010eaf581211720c71bf81d740beb9e355f189a1ecb282ce2d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x46404d48803cfdddb440aa95b8c26fb4bd55f460f566be0505c45bbbd2a1630c7097a15c92d6876dc3c7d4acb9d2bcdb76ca58e5e4a52ebde562639a06950e09	1618581407000000	1619186207000000	1682258207000000	1776866207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	73
\\xa9f85b42681ef6b7a9ea469148b08b74c5ebd867daa0db743f3487baa5b45a69adeea4d378ddc2221939cba4ea90cdc9e0acd20498e8db6e3a94d77e158aaf83	\\x00800003d3d406b248cc9638e98a8b54ba2e1f0bff1782e6dc9d6e159712fb84c69b7e3e30e1a253d17dc0544ebd8483bb8b9b4e47e677785b4346b87286b85be5a0094b7d4a73729122fb5d90ec8a74d480ee1fe0bf9c237fb0b4a303eb092cc2b4b2914117ab23995790e503305b5043bb07d769195bf7cdef4bcb810820d041554dc7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x379a146258fe108aaeb4f0b6216fc2214ad99ce0eb446201d438d56471ae751d7536a9be1b8a92381422ba293a3bfea42d87e7e1653a0355d7c6bf270225730e	1625835407000000	1626440207000000	1689512207000000	1784120207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	74
\\xab4044128d6e7464530f70535de7b9aa76e32d67ebadc968cfa6ef0ce8a3964ff3b8bfc8519d07c23278d65229d42068588b14e776363e0794b3c7a6afe41ee0	\\x00800003b748fd04aa58c26f09958da137346d7537625af59d62aaa4a87f5eabf07b0f86af3658b9e5279e66e364d1248f0255349a8077ac2ad2e615b3fa6b619c3359ed1ef83662a149fa8674b52224b32e77a767e0ed9f5260c92a8c41b82ba2d19b7070a16742cb4f9e602d5db54f3775e7a794d876229411f5bb724696f7935c9373010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7ccf77b43236fb5e483f7c767f0da2b7a76910983c547d68312976809fa8aacaa8e064a157df73d0c8a557f86b4a1e08aab34746c8fe7de5b1942b9472b28508	1633693907000000	1634298707000000	1697370707000000	1791978707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	75
\\xb07489bc98370c044d26e0aa3363cf39bfe28da7abbad8b6979106b0719071c01a01218408201005201814d820be75d2f8d9bea537f258db3c39151e4eaf8b5a	\\x00800003a69f3f4fa80b64f612cd8ee24b45aa4a06baeb84954b980cbe82714fa35c839af19b225d868af5d4a5c3c6ce5b6d143c81a5e4e3c56116901cc78f5fab944cda175d3105bec78fc9dff81672c46e26863ecbc553902cf743cddc90083edf606353e36f50f45f1658239b5fd1e5666a196451d1e901eb62f22262e3055b9bd0f3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x25d89ab18b183763a26b8a9405d799e2351383bad6670a3fc90f7bf567334d4d2f4cb905df5794625010393639199221844f11ca024ca6413c4234ec9ff96505	1619790407000000	1620395207000000	1683467207000000	1778075207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	76
\\xb2105e2d249e3a17ebb43338b88cc7fe5f1544b05775fbd6a7bdd173d1906050fc9a3cf327e6ee533f73fbf18d4967386a6bc013b3ac0672bda7340b8981e419	\\x00800003e092392a1604fd0670301c8fe2aa0540f66123ba45d51398112418ce00e2097b7488d334ddf5cab818276c03fb9641c6199b6f069021ffb0d56b0feb03e246ad8a856591bc495fb4c6cca5be22fac2069f0c65482c11db0dbf3b55eec7aa2642257779a759b5bd5e4b6bd9ca296a3cc7efb83212dc0a0bb5e3528a77fc2e2c43010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa61bc5e405224bf08c06c26c9d761122858d0eb13bef884cf58cc3b38efc976d856c06b9983ca0df32982cf024f696053c185d2a7157b988c4b3bc37affcdb0b	1616163407000000	1616768207000000	1679840207000000	1774448207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	77
\\xb974fd1cfd7021121c80fb2cf422fa6d9405bfc265954a7b2d5c6aebd23e8ea3c10e7c26d1feeff4f8c9193b8816d5ab0c827c4abd7c427f8893bd1f5246d66e	\\x00800003a415ac29b03db51f41353021834830232e9da1a19e9906bca329816e80a7e401dbf7128d390eb7ddaaa0b7f1d3d99d2574688efd26c062b75c6d11d9841a3f070e50898ed5b369465f8b6a67c8838f88a10b0e8663643bb280d395236fd0b695583d7f4724791fdf4b783e5ea6a8bd4587fa2881bbd49cdb75390166d1e815c5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe702c1bba9c1bb19b1b963305fe32ece550fa87bed379f5b54086239a307f3021254e1b3d6457ffd13dc631445dd6fbe0740cad504f2c78dd55465b8cd914709	1631880407000000	1632485207000000	1695557207000000	1790165207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	78
\\xb9ecf99184440f2b4eaa870c352426080607ddecd6f13b12c0b36721b56c4978aa1b46a6c21229b4a0b3020b402bcd477999d00018b906905f5eebd5032bcc6f	\\x00800003bde6977933f11c30be05895bb04a613638166d0d19593de1d023707492da92621f80630eaa594308b653e4d51352647d79cf54b2c45096751fef1238b35c6526746b5ee366a698a9c11abd8b94824fe325294809abdb6c21331547576323f277d8df7c866fee1efc687b20da064cb6358139530e4621af9904758a389d19bfab010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x429d0019fdc2d9f32d2599a9e903231192f460e4f8e5bd569127fb41f5b3cc726a9071840aca3e60b98f2b550e8105a690f431ffc180d1d73dbd5ce991976407	1610118407000000	1610723207000000	1673795207000000	1768403207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xc2d03918b1b00356862aaa20d287d54e9d1caef5a97aa55b65a6e97837171fcad87226169fa9890544d8ac0d737d6000ac2730724fb9594ee8347cd709029b49	\\x00800003cf53380339a48c5afaba1b1f0f188fb87b24960ccbd248a5edb09aac9dd389202ca1d731c865ee7bc975cd8ae15e8039209f1aacb95b154340a7f74685ceca732410499a839ee92edca95c9edcf69ac60fd290b5367ad9a68d5765a49dc1625e62aa00d851e2a06de92488adef91d4c7bce16f9798cc2217b9a8e7faeb2ce601010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4d255dd93d05dbd71ae4e7c80a66981e5070b3898fca507d624dc96c8ea4147312d5944d5682c26c41cdd616b57c579a969d343e2543da3f86887bd36a208307	1620999407000000	1621604207000000	1684676207000000	1779284207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	80
\\xc62ccc8a4a8ecc5499872e0080ff8fadf1998a8410e4186834e1730b53780565afc201f3b0d51c0b84bf1543f09b3439e38d33c57e72c5b526e08ef961944642	\\x00800003ebb5f1d51caa2d21dcbe313b711ddc9ae64eda161b05d2dc2b509722cfd636e232dbc8f34fcdb88545c710d4cf18a42d4df0209034e57b4ed1693f64bb25e3171e92ee0c3aa5e831e6797bfacd057941d1e42143a2dbb84715b764bd83b1f3b3cc1a74208f847c2e2223e423b7f1e6e5da5f19edb40b526cebd2dcb3a81386cf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5062e8cbcb2a4c25636638ebef40cd9e4a702123ec405e2929b5e978b5ec2d24f462ab4c3f37c95dd6d09448ee07414862acdeca34c46bff61fd6370e585590a	1640343407000000	1640948207000000	1704020207000000	1798628207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	81
\\xcde0d6269a61506bd9cb51e50a08afcb990e07208076e68dd2d77c36e6240ef9f9df07a0b44061a09e05a6c259b9f83a74c591446fbb183369c10a56dde989e6	\\x00800003b301697b6e47317a987813a6fbf898141a611ca476c1606c7cf71a6f8e97413623c68aef95fca0a008d66d953e163238d000199f9bf7075c29e0582d80ad8fbbaeebfbba90e4dd3330d8e73a939a35c6ab24e55a3f1b555178f1237dafa917b0e3ab7dcd09df7397bab34fb8d5fd4286339144a0f1329dd14f8252f6564a869d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb5c89d7a7f4f4c3eeb01715cb5a96514fe9584b6405ecdead22f6ca36c95a058da7da8be26257d7a6149bcd3bdc9d80e960a831dc4b9315f91f23d6c2b3b2e0a	1633089407000000	1633694207000000	1696766207000000	1791374207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	82
\\xcfa48cf63e3ab64b550cb985bd042ee2b304763b59b17e42b08d865f180af929e416ee8b9fa8af9556c677c39e4279ffa748eaa805784c98a948a5d3db350e75	\\x00800003d180f83996ce9793a8ca9622150fa0493e5c29471c2c83d0dbf1097b852b85bdc71061c448b8db1aa17fc63e57c17ae9826ae58bc93e0e372e90a1841de7c834800aa60d832de86426650fb7d1a234d9746ce0e4749a7d8820e070a19d42a85ea05e70044f347e803cf5780faa52c1f890e4a13f969874c2514abf0826c25a53010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6c3a5bb60c5a51db39e0321764e6753dc96d5ede7fb637905c467dae572f053138e0742d1b8d3e61b5bb1b3f64523fe354721e353fed1a47a5076f5fa456f401	1615558907000000	1616163707000000	1679235707000000	1773843707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	83
\\xd0e4ee71ee8412de81c73c3df37513fd2710756e1d1d2989008143a689bd1011482f7c66a080f4f70c386e09e75116a1ea0531210b44bb56ef65a952a05f3bf9	\\x00800003d797cea4ea7b93dd98606c4de41296bb238479ed59ee9b6b483c9743d5f23117a1f208e85d7df8ead0fa6949498a6d0a217c20701caf6b4ee05a48fae2be058a9b8f6eabd20684517e165ac522df45e6fbc9622a3f41de384aace0a72746b78b574e2799f60ee0336b6110d1157dc424e5217ba3160d40f3bddf798381f8a981010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x87fadbaaed5619b5c6cb1fcdc4c0611ad2e12b5a2d70b3b953ca2c8175357159852bed7961f559bb287809f7222fcbc2e86f008de6db3f6d717076f6fe287906	1620394907000000	1620999707000000	1684071707000000	1778679707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	84
\\xd3084a109fe04d6a9dd0e21036319cb6ca3a457b79dd0bd1f68340b7fb4f1dd57416fe183698a9ccf1b4e72d6aa36e77d05ecc805e426801ff78a245a0007438	\\x00800003b3235fba4f47bd4a91e7c94230bc056cf271d7405fbf04bdd052e70c1a654de5237e33ca80ccb9b7a76add3a91008e94763811ea944165046f56a0943ac512ba54e3faf2beace82f14acaa2648dc00ab2a0c666f518f563ab674e06b26ebac71f0dde83221582ce1f01124e7d699490fa6449f9b34c09cd5f198b5d41858876d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5266bcb5042776351c8025ccc8cb7ed519a760c49eb5aa5a1fb2f1cfa17f31a763dec17158c035e2d44dd4a1a07cf4d47bb0bf451ca169334b7216226a8ca30d	1616767907000000	1617372707000000	1680444707000000	1775052707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	85
\\xd3f8bcfc6a63ee4c341db2f1bdbee8f3a5a6e9453a23277788096dae15b4e2928f9e31040bf92b45fa28b138d842180da99d2fc983e558a656c7ee128cd576a9	\\x00800003d84d668643b23b952aedf1eb3b4a098c07ebad1580a7ce91217b57157577707201ce05f442a5da0df5e90e348ce27df62c675c398a85e60de69f51a918b87fc18a4d649cd00bc3925df9c3e886a89232f63364c560647949834645583dc8b0d9fd034509468304d839b9d07c0fe27396df51a47f6e9d2e30cf161b5a400a57bd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3722f23557ceedcf9a1c33b0a5d86d575980d28e7a6cac9cf216f61149c4fdbfd0a9f3ad2030dc0048e9f3001313c9306fde19f08c2042ed80d8e26955549e0a	1631275907000000	1631880707000000	1694952707000000	1789560707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xd65c235d7f2e1effc5d16f59c47851c3ae861f789aad26ff93aa1742dc733c9a1099399fe832e1e33af64b0b5d4a8ac1256d93155b8bd301b880fa55e1c72b2a	\\x00800003c220a2f848971651abc6b8037b85fd9aa74e566df6a0d59338254905e1a7c799f01e7d630e5bda172ada7fccc7aeee43f56d7488d8f3ac3b1a3c9a98fc5b84801ae94c7b731813d469f255aa6abd6b94a9d94a59ea15d97cab66d97da4e36c5fd098b38ac100cff3264fab3e4b85706c1135dc1bb183b042cb2ad4898339f411010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9ee321987ff1ea51b21744df3c284651877f94053f48e87159eb01a30eeb6b54ea75284a031f801517a7f90111deba739cdca4b805dacb0bb1883b2b8562f906	1640947907000000	1641552707000000	1704624707000000	1799232707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	87
\\xd9f88d8402cc13b7457404818a61a3d64d699f44f8af575c829101d076d3ed3fc03f875b780fe795b39758d2f42c5af2550246a9ecb6eb375e00387600e7d02f	\\x00800003cb3aaf518554ec1a64b6017875f55340ea06153022d050c60f67e17f6322d63679f1740006aff886b4f8bac7664cf845312875f456ee2633b0310373fe6986762c92286af6aca3c9a26df5022f1d3aeef21928b36d22ffe89244a5171375c0189b5c525eda58e4724b3223364efcf792fbdf582ef620ec9f226c450b795fa4ef010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x503ff8bca83aabdfe67b54321b51502028393405090d0b45aa5cfc1fda3ccc81b649fba3aa535117aa15b049469ff5130b79cdd9234090cc6938375623ba3c0d	1616163407000000	1616768207000000	1679840207000000	1774448207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	88
\\xdb64c6612e68bbf18d6110bf2897a9a17bc188b6a54744fd4e3814e533daae777cce46c4bc1af529e3c1c71fe01b8bef30fb0707569260a4b6bc312629386ee9	\\x00800003b942f71a9dba077afec0d0ce0b8f527362e01063c0d8075703e649781895e8886d14aa0320ba7106f1bff9c5574b4cc6f5cca72a442fee2600084d45a7ac7002c687cd95a5856815d24a21c01e0694d552fb4bdfda7d9ef101e3220d9e7f50233da1451836d439e0e054b1432c4139778ce6ada55b437ee687625221a18567f5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1d2a822c40e30e588968afd3d96b5bf35e97621f08547cb12a3ac2ab5473ff6c479b434a2a4a3f50d3af00d743c4472da2615f18be8a5c6d656eb75a8d77b700	1639738907000000	1640343707000000	1703415707000000	1798023707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	89
\\xddcc6971bc3cbd88f07553a1431a7683370f6a40e84d9d2e9d0265cf367b3c1fd16402d018cf77abb1af820342754a48554d8ce3ee3299f934003963412efa71	\\x00800003be49f44a5207a52586bb490fc188419935385687df631458ea0a2e618984804a9aaf51306b8d2d1f3bf1d52ce1bf4ba74da8d24f7247b9a3eec0fe2f68b630f49fb7b4e3c579d21f830e432ce8c031247c7481c7d0b187f09d81fd9d0560fb1b65df20b1e0e1c83ee2503fb6ffd383b8a6326e13014f229b7250d913b6ef032b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x952337041a10f8f8c41bf37f9f7b02acce17606c3e07f8a4c3b448a840c6a2c35397d5109b8c7b65c655451669a550fb19d61677ab7be3250960d390feab240e	1628253407000000	1628858207000000	1691930207000000	1786538207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xde7caa0fa2912be7e740ea947aabb3d1d5e348b155594c2ee3baf0bdcb1c01d9f29c0a378b539fdc4230dbd392fb99882fa6164398c28e6bdf6258b45366e565	\\x00800003c961e6f636c4555e9ed206a6b1024779c89c4791fa564f2a8df5ec0adf531e52a326d95c8301e0ea7a6979a819ed18ee69c71322eb31cf7ec3653ebaf86a6069e3f1aa496c1f8b6e0102536ec71af4121bb340029c0a58350ca0ff5b5bdecc6b2e284dd2d32936f60ff71c589882ea14f19e592db1c001562e96016c80bf5c29010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x18330f883be3687fabd3d569ec1fee159513745fbadc734c60fc841e9b11b044ef8b20ae93814c126d2c8327864297338a791f1f4e3840640a42d4ea487a8a08	1615558907000000	1616163707000000	1679235707000000	1773843707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	91
\\xe1348eaa0340457fc9664cde053f64fbaa6af60bbe07ae1ba7816ec89926be43ed645a2d9d2c7ee87399d68cfee5b85624b9cf0034af2a926b9bc89bb22b9e86	\\x00800003bf2a80fe28e12e825d49e68f3bd3f9afad6c7723acda9382649f74e2b6e94e332d97e3af9475b17b6601c92bdd4c1e4157981823612197c0a7e5218148ce26b57ec24bd656da5006795d93a46b97704d6c117f945360382a96e2be4f16859b57701a36532296bfe9ec04612aaed2a8205802a1670d96aa0cac97578d909e3045010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x719a6fe59a38fee23f371c54e35c3fe3744745f2b2b37b896ded813429cd5139971f568d5bb328cbcce29145a99de855a658ebceb531a99407568ce62d28e407	1630066907000000	1630671707000000	1693743707000000	1788351707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xe34801c5395f18866a2f694f22613eeb3646881425377f75ebf2058828a9d5538d31d7bcb7bcd4e09a19e758268c6828707710a790587c8f760773771e71713a	\\x00800003cf741df258cdb57830f6ff199af42e0057ac4ae3bc4e14b41a941b5796e7114d179467e287719001bec562b4dfc3b3295938d38ed2bafcee762863ad146114e1e75ecad792c416a6e2dd6415b7a7b6ca13a0f269215b347391863a6b68297cac83e3f5aa8e21a09b5863a1691e7174e729245944e3fda7d72a616468014dade9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5483b5520af4874177ab46718215609d828ae3ea293561370fc05d931489e3db27f5f8b9380ea92faa48d2303564f8993b0dc09cca4cbce6b2063d50bc140703	1638529907000000	1639134707000000	1702206707000000	1796814707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	93
\\xe654901d370fbce6b75896795783f2e1baac51ad06733ffd3a29b14aa2b2fb85bd6a8f9df8c6c5f84fe5cf02c21ee8e22ab41f1d3023e8dd6a1ba47125cc062e	\\x00800003ded7664812060609350d5de67a047756d1d54ba53bdff4ef5bb831770c80afcb46d07a6b9f861e63207aa8e1ef8225d80d6f6d28a649b30f527765caa101b4660d1d27aa56829d221bf6a64e0004a587d1c5ce98076d592b5979ef27223d19649acc2b463741b9ad668920b6cabb5f7f86f26688cf1e1a437e5d7de6a10df99f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x487e91a93c7cb66cd0592574960a3eb022fc60984b40a6814a1ef3970a460e80e8551860ad9ec921817ad832f5a87fd7ffeef4aa7ff04d9c8482142beda70b0f	1625835407000000	1626440207000000	1689512207000000	1784120207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	94
\\xe6dc95fbbbceab4dae372cf37418348e56d03c3b9e2092280ec3555197791ba8f4ef36ebf55278990847e6668321ff690b31ef143f1e52166edbf4e0b4b8a5a4	\\x00800003a44a32dda049ac4585a41718763997d4613f3213050d132823fd9d7316336ca5d6a32e27a7309b11249a0d8668fded918368edcafb3c8479116df4fab39c825e08f8be3c3524c567a097be40814e895707cf92c38aa092025953ba79cbdc844bee5288b81ae4b77f8530742d5941f4f57f40503dcef823f8b0d41eb70845e237010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa772307489890755560b8039e9b7d2bf7be7a449195693ba523f4b1ed8b990ffb13b08c7e495c98d565e6efd8ef457194634ae27e84f2b0052b7404ceddd8201	1625835407000000	1626440207000000	1689512207000000	1784120207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xeb20a81302ff2fce6c48379beafa5ba6597ebfdfaab810893e8e9d9eb2b3e5e05313d17a4440556ddefe121be29fe31fa61e52efdfff8d2ded8a038ef95f9f92	\\x00800003e6c948e3aedaff4e88a178beffd30b9eb963c170bfcae648f1595697cacc4cf230d069dd94b1cd5a8a52043265b66262378fadc9da7863ec4dfd9ff63b5fad574585c9f17be12bf58c1afda7d2691ab1208e8aef38f5dee3dcdb1b2d78417158f2b03968caeebfaad6909320e08cced95ca2143f191e202d300e479c2576a3ab010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8d5b9b4c4d927629fa12585f970ed6b209d3771f34db572a7eefb9641bbd572dd157aa1b93b20958de0a1837e810c8e5be6d044f78558132a9e2e15849994d07	1637925407000000	1638530207000000	1701602207000000	1796210207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	96
\\xf050c2cd2d5bf0ad0bc062de555c602e2c31d93c3cc74333a99bfe98f9abd5b1d4c06124e5a871a559eee2c5feac3ba3d05e09b0a738abd37a3a01574bdc1f5a	\\x00800003bb6639802d0b0dea3bfd8b125cdbc601c251f0262846c2807e74c78f3cc9b529793db08cb925d57298a960fdf80245fe58fecee5ba0107c7693333b2ff1d73b75b6b7e8a495f23d41a0ad31bd5d3b34be361eb207d930bc96c17e32ff8e371dbb97948dc15cd67fe14186a942c3e84ee188dc7f92f044e93fb39886c576787c9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x548a9a15aef42e56dbf54960955f1ffa56a94c51cf18a4058c24ae7592cb13329f7ba4829b540dfcaf770a6929db69d0c7fa9112b5b2db5dd1fb6bb415c1a704	1631275907000000	1631880707000000	1694952707000000	1789560707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	97
\\xf6d87a891a4ac664af4c8f0f33a8732b57158496fe004ec22794ad8d63e650f6040cab4f47166ed21a75b312b1499e144bba1602f745828ac8cf5319443c8227	\\x00800003d33a721fecbd082c975309ecb368f6a0cfd29a530a82f1576c1d4c5af634aa62742f1cb830b095862ca16a6faadd6f2207db611a061a06592f4aa514307916ebc39a66c7e58ca57a3da4555039d487aea6c120ec1133152fb23db473ec11569f94fb10b559fc4d0e50525c3292a3d4a7b2e1db66f70b54b29bc7f61d5c63f8e1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1b4ba9cd7aedea6747de5d811cb7dce5e250d36d248edfd94022aa665d6dff2102986a6e10597811c06b1fe8b3d9c375228065d3ab4f48412fe83e668a54dc05	1611931907000000	1612536707000000	1675608707000000	1770216707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	98
\\xf684871534376c10f3ea502a421753f0dbd6458f5a94f0b5832fc233c20849b06fb45f48ca77c4513d3e22495705ad3ae95e5f6abb256955cf82909de4afd392	\\x00800003d4f31159761de93d7bb1d866747dc05b45f3a7ccc3fa1b9ecd166b55e91a66e97cefd2ca36e9107f53812ad20104e1b2bb498bd0c10cf4928e5ad03006a8be36007236b7894ff1dfaa6121baf9a05fce8b94d88e1e20d435bda747dcff011820810f549ee36bb587bee861a65d3ae15729ecda4bc34218ab99861b0ef2e47765010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc247841202e7ac591f7c04bb378458c4fb2049fb7cdaf8ae1ae3ba6cade90a69c281a9d900000052043ccdb34974d800d50fad8f989682bafa7c4dd01585e104	1616767907000000	1617372707000000	1680444707000000	1775052707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	99
\\xfcb806d2fdd6cdd5effe8843e00552e01ded6ce8703a879162f19c99d80714227ebd22431ea4be7ff7cb2b421f6e70172aa7cad1765951bdb7e6f52aed49c5bd	\\x00800003b8ec32c889b5b75c3b417d829e1d29d0501e8018e4c73f7124a679644fb504b605ff233115ca04bd08c9c7981954eba24aa5f33d9279e2f024a66022c44e109e790e99717c4610fd6ea53d87cb8d5429ec6cef36822cb019fe83b8ec17602ba72124afe452c49929bfe669b8efd113ff8bbf35c2c9f11e3e44a41b840616c68d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6e6c7351491496bbcb2c507f2481bf74b95b6f52a4e42d99b9611629006e59115cef42bb9f74c6665c2d11eea395fc003599b9b3931fd7272eb046c13d2d550f	1610722907000000	1611327707000000	1674399707000000	1769007707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	100
\\x01256b14190904946da82166a37e0be1f4b8fd535d0b267362c2be544e763e75359b82162c557ef218dd8ed7fec1ee54bac123f1c6d6cc22db1a04dcabf07a6f	\\x00800003b147a91d6afe184c1e86b37ebfbc20459474de56ea76e524e2a0fe0ef4c057812fe7d9c74825c57950b0777663a0ba114fd15b25050ffeb1ea2af8fd3c5e3fa2899a40a35a37216c442cd636a7d325c770721eecc57d4c91fe988a6af9b6ee48e5cd43422b8b1a8847c4875b0ad285662af42d07ba92cc9d4ab95560d9dacad5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfbfb6ea7c1bde10c9dd18403d4eefb7ed00062c8156470cf5011a2649a11704953130822d925a3935411e4d61bc94ef5870fae980ab44f96a71b373847ad1f0c	1614349907000000	1614954707000000	1678026707000000	1772634707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	101
\\x027109e9b55370ad49da351ef5ba7c006686946a090c0c699dab511d8061d726a40d04d5af057d740b444d16583628f989a6ec8d2458a4dedb8bb670cd1220fd	\\x00800003eb3105e4dfb83eaf74757ab86d5a53072eb3b87c253339643d41a5456bf9c964c0f2891245b1500dccbe179defff5005e26a04c665dba95900229515bad02720ded30b989ebdd4bcfc7aea09513b2197aa3e49a9726eafb9379cf5a978343ad0f6b5616eb0b41e1533d7e9aa8a68f20f8da42dc055fed6ca75369bb4262134a3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xea76567e2becf10e1957e1ca0eaf812b0e3d22f608d4bc32e6f89027a7b65d7c70fad4d8d06522dc0f71da372e59aeab46d76130d73d865a20a4218d9ddecb00	1619790407000000	1620395207000000	1683467207000000	1778075207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	102
\\x077d5ef30f0ac5d20bb41fa44c231044bb9cd3d0e2cac3ac70831bde8e3254839a675f6297dfd156c8587c433368f55df6625a321c92fdbdf8386ad58448ef44	\\x00800003fc081bccd125e6b5e21de309aae690e55a75760e51d909d684086a5448fea04890851cc9f8f5a7053e0f928583f5620357895f6fab77130e2d720cc1d744e818fba982ff96ca0baccd52b472711162b2c169a95fd2543c06facf40242ba0c67134808ec199a7dcbc2de8aec6fba89abd486a1161371f3eceae685b151130036d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xda1fa7b63fd715906af030c5d9142057c3ac7397af1a10ba9bbc9bbc6bbad71de41e15543109c7bbfed7aac511336dfe535b1d045b445115397144ebd608970c	1629462407000000	1630067207000000	1693139207000000	1787747207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	103
\\x09f151ce734f65bc28167491535783acd3675336fbd59497f5ddbf110517951b39ac4a2fc5b86cf8058f6f992c319bfd6fa335b3599eaf1fbf91bce94cb64cce	\\x00800003c3e8f5397c14a32e30d9ad2b7de3eef9e83db28132baaa849cb7c6aa923fb945ed49071b9e1b4d1bedf922f413fcfe5d29aca11158669cbc9fea276e64d52f5aa347aa75299cff02681a429bf4ea68d6de683a472b14a0a7a42b06f88805c8304158d8d034d0b904e0299630f397dd1383218378a88240e3e0a23e4a796fb3a9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb335c4efd6e8e05bb31587a319d46ec0b16828f371901c0e32ab010da09fa067dcbdd1ac062ca076ffc5d87a054abd55db1ac02849b5d90bfca71a086206cd07	1620999407000000	1621604207000000	1684676207000000	1779284207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	104
\\x09a176bb08e368d36a46c6ba3f56d05004ac97f0b90ec2373f1364111bf954a489ca252415351f0af7faa8e9632d9fa027e189fac3abd6f9a0e52e6a7e1cce04	\\x00800003cc33dd35252a447097b81e342273177b8a61bac3dd2ef412d9967cacec417ff3b9e3b13b327c59b1be6f09e8238756ffd91c356515dbab810a1d7a6bd083cae09d62e5430b9c8669cc46815b5ce70cd2646e2015ce25eba3072c84ec75897c551940ad88b0b57894d7ea196f7ac05cb8aae50f72beed872024604f0558613447010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf8f7d40b476536d28fbda1ce8bcd22f11bd5f305c4f0ddbbe5e18fe83e251587bfb85e587757b95b2d8f2790e75a007a0ef9b7bd1d86fafa198b5e0b945c2a0c	1640947907000000	1641552707000000	1704624707000000	1799232707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	105
\\x0d1d54619938ae2b95ce0b96bd0e8d1826a352a8a52fd8f3f04236e084f03a9edf1b94f2c630f69c3e4927097b4d2ce16f9e00223b356732f8c5123636210880	\\x00800003af14570048ceab5893fc816bc4e3a1ed90b6912a4f7de406db31e0cede0dc71128090797c9fd3f5d4f4d6f827f18c0bcf33d08b1d9b63f0325cce29eb978b3e6bf4745eb343aad09d48405e01a477e9f5776b9091056126443f138de9bf47e74361a02dd01d54f1da80fe523265850ef0e1e89cbf744ee6b9f1b898a99733a71010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8a0ca0698b402be972541c11e02c334d7478c4f3b9a50fd58da2bc982bedfcb94d73ae3b436694b42dffd7adb4df7241a99a6861d5ba9d4aec201b5eb32d380f	1634902907000000	1635507707000000	1698579707000000	1793187707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	106
\\x0fd522185dfd2845dd9ed4382af7615bf2ae9fe62cd521727b9bf5e017772fc3e122dc54b626553d61b987d4f989dd44ed3bfe972a8c36b22e9becfb4d76b376	\\x00800003b85aeedd4b955a02a6784be0b79069e990aec784af75df4eb9ece19fdf76f008e20342a7ac180aa57c03e5cec39177b7939830d7fda8e3cef7b74ed7f0e85e477e5245dc13a46c01e50f8ab77bf64e1fe350846325dd79706ba4c548b001a58b3f41a8007b0c83bf1576696fb0d49e6538728183c44cf4899bdf06891046d1c1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfabbf2846d306bc4e2b48a89670c99f6eb06a7ee5478ccb0bdef1dc7fd6172dceb8395669bb332566a29353337ed7fdb6a119f2b003a504b61fa625eff9a7108	1620999407000000	1621604207000000	1684676207000000	1779284207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	107
\\x13810412f351cee502e7b1f625ee15746860c0e711165197331568b1abd4e4334561bfc4c76a458447d411aa80059386445a1b74d66fec6b829335255adfd4e8	\\x00800003a0e1026be07c6aa3434490e6aff9fae433d70604dc7f7f5bd34d84399fa499a1f2c4bb96c831570bb00f8bde9acf713babb71a48b4bbe094018e2d52676dda414ba66b14097a9aa4db2a7de4ac5129770a81ff3f55e9b16cb79184dd2a2ca3faf448308ec767b89dc6a432c7f58bb7dcf3f44104b571b1bc91fdaf92442c7041010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0dc1b07d31632413e1a3a2dd3d99ae268f837fa631102c2467ba14eb8464b51df4379de1e1bda9eeb6ed4de3727220242bb6803d14b35fcfcf8727a139ebb303	1637320907000000	1637925707000000	1700997707000000	1795605707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	108
\\x16fd1279aaa6ff6aff2d4a2ed12f6d1bdf95c9c27ce59dd62007de453f7a900ede584c3d2973b2d9743f0a8397c47f2976331093dcb0eaddd0306b5cfbd0750e	\\x00800003acd8cd8ab4bf3c332bed6f9c6af2641592649679da93da8fa1f55c7b5b784b07033bf9503dadfdbda7c2a5c4449d4083459ba2c5ceb6e71877828b3d25fa0c4975ed81775f70ce8d4e63940377ca04790c05f5d57bd7f5480e67fc9459cead45fd04ecc7e6ff16eeb36138577871ce92deb68b499773417e8aa744f8b33d1cf5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb224cc3e99d3a7f928df8437e0e04aacf61a8ebc49690ecaa6a62f5231b76424541e50f598f14626f9c81c50524493023f083500b4917f7f91bc472c788b4302	1631275907000000	1631880707000000	1694952707000000	1789560707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	109
\\x21f5a343e2407197ca8367ab2c0078399adb6891c0a77e06005e0a83914a57225e554ffbf881d03dadbd24a3920ade88ae899d4d879b2a9f52ea25a94589a6cc	\\x00800003b46c702c720731e6094841272289c5eff56460b4d2b713aa0bacc7df64919f56d1fcf15f110be2bf82637cdb6ea7e11ae03e3bc68a702977aac7477cdefc0bf8f1b37b06994be54bfb36ed05ba2a710152e925800691411034a0a53b008523d602120a3354b4c8120db3099969bbd9e8568551858c6b55c236ab0bfe291ea139010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x55ddea9e2086e19b5a6afb0e6382d12a28e1e4fe227a2359150b68af2aebe89d3fd5421e9b8ded8bcc43037097149d78f05814eaea58e14d717014210ef3e70a	1624021907000000	1624626707000000	1687698707000000	1782306707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	110
\\x24c1e83f6cda474bdb1ffdca58973fc7d4c2444235dba37403b94133ab0ca55d29e8c46b072af2f96df9ab22eb96cf98852d2d8aeb0426256795754829ae71ff	\\x00800003a63a9e8e7ebda1f93f22e3317b53418c256956525a18333d38ce7a829416d31ee92f764dc9ac3121fc962322f1e5b077980ab2daa30e222653aebd204d640707a6fb5bf7565559ccad4ac4b90a2ecdf12fe27c91b572fc03b8b951f6ca47a119d2ffbf78e0d464bd752c400de9cf59cf46b56f6c654a84c500f8bf25977f0cc5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1a758d1be8ec77baf32fe6ac03514eba35f533477927625eb8709aacfaaef87c8aa9b9e9d68bcc1a4081bd6458314d4bddc53ce869b576d993b29c61089aab0f	1641552407000000	1642157207000000	1705229207000000	1799837207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	111
\\x24119eaf356de69443d25dfc6219ae7f08e16c420b6547f3c7527b0ce91059befd8e77db864ab0e0be560658d3150afbc70eeca187e8f80fb89a337a8ae07ca4	\\x00800003cf2aa0c1d20a377de9c51446ad54c6aa4090944b3a02b95f9f61d64e4168ba25d6a60bd4d8d368e2ed0e9c0a7336408d68e2147d62bb147a30586a6ebff62e7be59c8f446b6bd01cfd8d75974511756b8c9c2d9bc5067b716a5f17b53e865d6e7ac64c7093e054db32dcc88126f62588e93abbe52ea5054d461766e97e93518d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0c5a3c4eb3e0e4e532fe90f51d42d492490bf7165f4c61c606532c48a88db1c9d82edb2165de49edea95a9422dcc028df03978ee1e910b3c3c7e84363fe0ab00	1620999407000000	1621604207000000	1684676207000000	1779284207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	112
\\x26ddf3c6028164815f5122d88245850e756f5119c97f7be9d09b77755d6d7848f5a9514071b6970675ee8b69cde6d9bd95440cec631bf7388ce080c1312564da	\\x00800003a5edf5f14c709c8d2312bd6aad517724575995f8c5c6c0f22801324bb7277d0d755eca526fd951aca94627c6d5ebcc43c5260625a3da8dfa1725c8a480c1ddd45979979a77f2c5262aabddd964a29d699dd6d8f703d0edf8ea8612c522734d7381ad254f1804062e64cff4d7f60e4aa0660817ab1e48fc4a76d1a0eba16dcb93010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x592331180f280a4c5d9bf3b00af08e8f4ff52e4c881ad64762a98550dba707dd8de3ef3459883adacfd2335b3458b1e39859dc6af23e82f6574852e7a17a660f	1630066907000000	1630671707000000	1693743707000000	1788351707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	113
\\x2b75e0e346bde5e379c85e8d29ab1c3a8d890f25fd1afc4f39793fd31a5d524ecb91a482adbaf6429be94597dd405d01ea1b55ec9cf39b1172b7afabaf0af95d	\\x00800003a78beec6ff190206b43caa1e6a582d0b8d5d5413151373e83508182383f4a223d79b3495ae5ce02bac359e938e309e196c45e288ee494b72351512c43a603e18881a820331e1a5a3ec43db05bbb00698f4bac34466e3753eb84f53ffd076890fb883bdc00cff44c4cbf2c7f1c65652d2f4ca6a5a9260fb6c0de796a9314e9531010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9e5d5a0cea4caff3adfae7b460a218c7f7c3a4c9935c2a19246b051547eb8f0f2e4ff01f0dc3166a06d6c4f1bc2a8fe84be0e6385682d184ff5cd412292aba03	1641552407000000	1642157207000000	1705229207000000	1799837207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	114
\\x2f09038bdf5dfb587db22a2d4b28afa0a4cd5a0608d3da8e992ab90794d547b55a94e1b8225b0d2bcecd8304f4de19cd3fb0af49bb3f6eb6370b86f5e84b75a8	\\x00800003e2e3fe56a72c86ae2a8a8764854eee7d20443ea67f669f3d235de3891cc45b055c44c434b5ff063de3f38506f3c591a3036f0aa8eede895b4f9f177d50839dee28ca7d5fd294c823a6a3b4f5592f9dd514ba80a6dffbf80f7631f03a03b135ba92f50a7a7e031b4594d1012389e2c5f3e2e23d39bcc0bf9fde099090c9000ad5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6369418843b35905faa5657fc395a1f68b2cd0edc6f6b7538784a5343f3ffe2a0cb527dcc55b58e6c09db9144f4862b2034483b828f09a49e39b789ede2a0f07	1631880407000000	1632485207000000	1695557207000000	1790165207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	115
\\x2f01dfc28cb807514f477d5ad151afa71926f0e4993c1f67a96311632127cd584f0b216f9090f81a8de9f830f0706f5590596c9479b658a8730f413ea405e03c	\\x00800003d4c8c13bb4d3e744a01f658adfeb7c5428bf6358df7d624d6e48ccc26837909878859b35f67939257b81a24852b55648e3352dd6b7057cc8a16b1dbfc2e8e9bfda740e2f080ae3cc3213b05ce1dc80eab9eacff3d7299ae57d5903ad80078fcf6175a877d490192f41cb8f26f06c0a9e15777756263d33558100570581e2e41f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8f6adc4b953e299b157c6cd44bcc543c075f86d724e57af8ebb773e8cec17fdc6269496543875e32694cb7ff4ecd4b840c60104c588baee2b01924b7188d3607	1625835407000000	1626440207000000	1689512207000000	1784120207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	116
\\x30d9cfec0ae8f5d67d78a61d31c382fd23d545137cac0e8ba4b33788332ad077b02df96ee1ed5017998d57b5e292ec124a13f54cddb72a96927744bf419be955	\\x00800003af495b5613845ed053e8d0df714084d745711d705f5e2b580400cef72230fa5ac9004e3fb99cf55262c47a6d51f26d7d01167bc176876e01bf7c8482326141aef48414fa54b84cd01f57ca05235141b020e5d7e542b440b37a5cbecb00f2dddc0f37c5f1656a2507fb8cdff4cf9a19e67e39fa816b957db505fcb204ac48ab37010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb595673e61d58985e232e0d24f7b1a439e6ac7d77e1e15fcac8e63145e10b0655de620291647d7d7866ab2120c6c55354f2acf79ec2d7a4b2e36532b3fdfe104	1611327407000000	1611932207000000	1675004207000000	1769612207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	117
\\x30e505482258e9e029567fd5d8c3d4802c5ff9fa59e541670fac875f968f4ff07eda1890bae91aad1da2f03a85ffb6570092abad2a7901d38ee09614abf189c6	\\x00800003c221b730d2874c6653336f40f961dc24d849c42006a8440c6f2ae29a1f898efbd30ce0f8177e9e0717b9bc047bc71da7db009e2b767a074e53a18cb88491189cfb5f70b3602397346762b099cc8b83dba396da0a780d22a2a32c79cc96909cbac70d24b0e01ee14ae8975cb8ffa6fba5c3977f4dd67d6e6e18b3ab53d24ce611010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6a62b6283aebecb26621efaa6e48378ac5d6e8c12bed667ebc4dacbaebbd87aebf434c1ed60e932093c2f0b23d131a36fe076bf9dcc160b5e4ffd45950625f0a	1622208407000000	1622813207000000	1685885207000000	1780493207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	118
\\x3361955f3db256841aa9f5ab99a61cc9f2221166f5f9dc557b6abc93ec2a0878d60ea0c4d45fca9d409ddf6dc9a42f4b8f791fa280779da6fc8084215ae51d6f	\\x00800003d096a5ab541a1441767c8719566a8193478a4c1048f5918e43494f989dd035bfa88a0d3b5c44d0050ee264edb28a40330c167d6071b654718f1e2e9e114b60ee5fad5b3f0822aeb80b222852e10d2a97b127ecdf85fa5ea848b11449c67da5d9f0142b7981785b68348c089a6733fbbc6e4819bee15d23b2b87b9b07acfa5cb9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc804d05d5c4ebccc2f647f54206b76081d4b39935a919b51730958a3795183c103c108c5b7547c68e44767d1da75013b859d62bc4a82326649962de502836005	1625230907000000	1625835707000000	1688907707000000	1783515707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	119
\\x45b9e37f27482b91fd42ed4692f0c74e1d0fe4e18e8b95ff4074466718c8b7203b44781bb76de96e4f0c8d6ac556a5aa9a4f624b77019d78866611d327960e9e	\\x00800003ea11b3b1c138eb19dce5245cd66f8e34a5125cf5cc8965fb9eb6048b45520c041b31ab330216be38efaeefec3ef9aa92f53873997bf33afffc0b05667c487d1087db48984d5e51ec5a6d496c7611253a45a84f1fab3f9a1fcc0e109b342c7a367e7994eee051299876aed738378bfde265058ceb8546591f1c038ac3729e3b8d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x253db59569c7d5af38e6187ba129f066de1d3aa6f26e348359dfef39f3fedf1468be14f7e171cf3b09f7349c997d442646db8de884987e5165e4f8470c814905	1638529907000000	1639134707000000	1702206707000000	1796814707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	120
\\x460df884cd23055a7c9af046fccdecf694e34b7782364e1f21eab3ddee08c530543c2771d22d0380b8c7ccf104db8d0f1cba9f3a9538563f88378e0f81177290	\\x00800003d69d34f0b3fcc463531535b0a8504471b56a4ecc1368d0ecac358f6c811114f369bac5f0911de75bfe56f3892ddaa05c4c549f85bbb27f6c72d030317541f195b79f85f260f6983629bbb88832d9ee19d8ef29d6910e5122998c21680317da0ace691baebc9f2ea765e8849479aaa5a49a5a3f79ae4d8b19ccb7fd67ac8f36a3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7d0254322719d935837d5035deab2d384e03a9c04fa897addd83364aa1299e01a179cb794322e6803b87f2ce2db68c5b674910ae36d2db18e52d62d8ad54d20d	1640343407000000	1640948207000000	1704020207000000	1798628207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	121
\\x4aa10dc02e0fe22e7486af84ba0c2dc59c6559485d30e493783f69d2f672c1ae2944524cf970be56c70965991c186639c172d0bc96a6862137d59ec36bc8f59a	\\x00800003cc8e228c21b31e00bcab47048b161a1286285e728e81a3cd81e6659b0faf15511bb460a11855b997d91df18b1ab2b48f275bf8f301a0fe7a4a2ed532ef5b2c8312e93d406c91afd09f4b95b4349e4dc01ff52fb9bbf6ed17e04faea16bcddcacbf9c6578b3a83d9381f3ba6f21e7d2bb5219895f03aad0869321422d57976d39010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbadb92ffce182776a7ec8717c581ab4a7113beef77d11077e19ac242f74fd1f6ec456b34d68e6d7b82a08c935555ffe0023eb93ed82a3db7f961e084f973d103	1628253407000000	1628858207000000	1691930207000000	1786538207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	122
\\x4b51ed74b2c82515721d8d23561c61daf5c0f1c21feb984c78928b7b56e7c4da83eb9e7c7179257119bbc64aad66fbdc6265c1ea05e1049be779522b691edc32	\\x00800003cea1f64491864fa61fd2b11408f203e440387037a3e972582836d21e295aff7dd16ed7f83c630fd1a69638b14b878226d7910c18183f74c8370b7b619f737fb56b60e09dd59ee6b05ce8f1c51cbd98965f73b29e5a03069a5c2bde53824f29548700232cc37e14aed3633eadb8b8330aaf5883a1b183b66a45b1e0a63585c00d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x71e67f8f8812de3d826396a14ef5292ba1015b013a6859ebfe065cdf972d96084c3c08f80f5af933d4f15de021920b817ba824f42465de997e1ab6c938352b0e	1614954407000000	1615559207000000	1678631207000000	1773239207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	123
\\x4b694ca9f5e4b9a046941deb86af7284b09d9b16619d6a329e3caa531555a0be42caaba7e9ac4a4c5de798c94756ed3f415f85c11cb198d1c6e8e3808aecc7a2	\\x00800003b635205d77120de0ddf0f36c3281f0a59b74992a2950210c1e07de2b361a1294fc5887816c0912cb1f6cf31f0862d47d826d032a4b0d05423967f4f737a07700f3937e19d40654e0c03d05d80fc7a689023fa1034aa3de1c3cd88b414e3ee0ca3828a9a7a27c84f95b63416490daeee21247045c89a0db446b873571cd664d5b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa8c2a62e616234a454b3b73ce8cfbe8e7c9ec188159d09ba670d10ada7976aca01b0d24832482449226ffe8fb18c787e28502996d9796e03872f19aed4fc1d08	1619185907000000	1619790707000000	1682862707000000	1777470707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	124
\\x4f25ae30b00be92370d9bb96d7175dd77274402c7b440be7ec2d94055a9b3510cd57ed31cba3d2a4d036493d6cdd3266a18d3b3b1da1c614d3bf5729aee9e2ea	\\x00800003a42594b8a0fafba4a3d36c4296f72f9020e2b1bfcf7eaaa46886003ca77004121dc4e4dc73c612101e2c5366aafc1e7bbfe94d2345b7498e54cb4f3630bab98be87b40c54369ad8756490970adc6cec1ed5f0b3499f95b46ce59556233cc01cd2fb86d9bb68de42e53232787523b713da431ef1793f3f0bba7f65fec774ff50b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x81a1e6f8a1925e1890d97f6338e9fd8dbe707859ec17c65b57c9fbfd2157891e8469f2b61cc1d83b23e93f16c3926956a6b4878aa981a4184beb7ee6d6fd8e07	1616163407000000	1616768207000000	1679840207000000	1774448207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	125
\\x4fa96e3d5de457bcec7cfc2fd3280aaa3c03a028de60932f2d177b5ce0c3e390da4874b675f0bac444c799c496f228e76c372e1320802d247b36b3e7e57f90f4	\\x00800003d682556b41b5183fdf098b11c0ef5b23b82c7ec76d898c0a577acf29b227e363b064c6679253eec26211fad04519d23b1358c6c3955372c1519e2fcfc62f3c650ec14a55238c76190c21641e03d0255fa8aceec4af7c048cf28eeeec2ec63e01e138eddc3ecfe56b917da4d3ce282fb100904a8d54c7b9eb62b649b0ae301585010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc4b9a72d3ec0888a358fc8ea97e200b60574ba8c432d12c6802687fb3e7b0ac09992aed4e50bd8eb360abfd3b75d858bdf2e24ce3465b66b70c2d1943ba65b0a	1624021907000000	1624626707000000	1687698707000000	1782306707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	126
\\x50f501ed10a3107ec00ba96cb8020ea79fb507f7b41e741c74237baa9d150c09338cbbb5991132272f3bf81b4d769e7d4655d848ebb5dc4fd27afbfd206a735c	\\x0080000394e3f838ff8553b4675101977b73efa215a9263afbb4b4a493793af46eba572439effc8e4f00e15e289233f92199f7b12e46deb840933cc0005976212e25e121d88a68dff3217f97b5fceb88d7fe8c6bccb4cb33920e58f9d4380ac87bcb53035a7935fe086ed04a8137f9b33e44d11b33aba09ba61295ff6361fe67ce71307d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x648a7a5a8ed5f7592404dd167680610a28fbcf861cba0728636bd379f1385cfab6877b051ba99de0ab804fff978e6de8d528a4dab101af382a4b49ebd36c1001	1622812907000000	1623417707000000	1686489707000000	1781097707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	127
\\x52f5db0fe54353cea5c0a0bdd3a286c405845c672795dd9a10c37f0eab83bea87894c37911845828c71412d250bace174dc1209ba5a55ea7fea02f4df92dda11	\\x00800003d14e452127ed2bd2b1e9202654f63d26b60fe2eb91060b3275cb13c72e5a48d062957c86fcc51f123d24911ba944465d65a8a86ac1b4581c4a059b4ae3b5301feb95246ab55a7a6dc2d239c1f9f0380b7b71b8afa2af2020a5b7fa56ad8eeeca3150f890eaaab964ff0c7b0dd55bb7371d1c5c87ec957bd7c7a72515c17e9423010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbfc958a8651f9a08c826b32c7fe08fee7c341745a2346f3d19eb4916c628b13f4b95089f307c07abb4b058746f4a1068f5f49c463f15ac00d3b43f3c0d4e060a	1636111907000000	1636716707000000	1699788707000000	1794396707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	128
\\x565949e5df97d12866e65999b786bc714ebb6a1ca6c50af2d9fa064e2b9babbd1f204c7ef1ed5a524cc52a38ecc728b79cf34db257a1cfd21304a313563e4e7a	\\x00800003a2d76dfef4a1b9c38b263c62759a29e6f021bdb87385928e3d753c943edceab58bf6c7ee58599e3dbc72a258fde1c7f458294ff63a0f5d01ff60928a223bd816612fbe611bd16be9d8095f782d638f85d175a996dce0669439ccd11561a27472b69717bfd0246138c782e2556b27c230874aaf6762714f7f1abebe52e910a809010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x150358384840a20a35022ed4cd41dc35482c963a7d59a5a8430be0317b2be1401e2a2f9f6ac66d351c5ffb60949d17c7713f53b452d21d5ad16305d19313ad0b	1640343407000000	1640948207000000	1704020207000000	1798628207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	129
\\x589de18d3c376b95ca21c1d7d2895e85467f112a15c2a400631b27c8672f461ea37409f77dc08371d3f92429ca7ec3ff2e13f5bb5849c0e4227eca3f3e2784b4	\\x00800003b7cf4e91f3f84adbdf7d44bc85e135c04f2922558d83cd93829e07eb4b4cef4a367c49e4a426de0ec9f6995d77da5ee1c2d7fcf2fe702713722801389f68d94519249d2af06a39b4c0e9f4f8c2efcbe90840856c97ab51c4104adbdd0b31ee90ee206fdfcb766902d0d245e8cd9aff22adc129878b026624d695cea0ff629579010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xda496a078d31617c38736e7e5a4189402301089efaa4c2b5bf5cc89af946711e4a22e40c43159aded7e1510f3f46125cf993377256e1b75dd90384bb9bdaba06	1612536407000000	1613141207000000	1676213207000000	1770821207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	130
\\x59653bad20ff5160b700835f726124f3f742e8d1f3ef826da71f6582cf152793312292dcabaf14405a6067d1f21b9f6f92051e1881f7b2a3da9e6f64f2c7141e	\\x00800003c9b410e409c826063db3d42cd3577040ddbad2515a68f68b46de494a1ab31193e266748f8b373bd4800d5e8478d282ee2a960625e47d0f537654c74e100147ae0b604de49ed4aae0e11f10f6e8cd70cb8de3b5b176a80fa4a516aba4fe5d94c3baae732c39260de78d0b483668e077a0de45be25e4382809cfd85e6c93139bfb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x25f36aa596a9b55c913cd83aa7d3b6545221d7570454a887c27d50d2ecec2496c6e2aaadf7b74d55607989f66d0c85ebf0fc5bdbdf2c9607f7004771acf53304	1617976907000000	1618581707000000	1681653707000000	1776261707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	131
\\x5bed41774134913d151b6d8da4aaa82c0a8b063ec504f81adb08a61d2bf4e77d958d4525a0c57c2cf7a585da1ed710f0332a1e69746a42c9e16709d4cdb9703f	\\x00800003b3465f8cc3c5dca32d932fb77c1c98b090f733e6be278a8d93f93b8e2433d0d105a6c58d3ed5aa9a2eb88a692dc7821be4e0297cbcf4aaadf554b79777105487c4a2f1cc46d151a2fae39db4218ec5642de8cb5a258c6e5547898269b08edb33a84782808975280370fba0c285f34a31d0b186e28a82a60afa1856c6134b870b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb888d09636d4b83ace0d23b4cad8cbbcae9c8f876238614167a43e7b4a940d80d5b327d78a539ec2bab81c5022b2553bb1d2631af8bbe9f94cec0eb83a6ae40f	1638529907000000	1639134707000000	1702206707000000	1796814707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	132
\\x5dcdd83f0c01869015968af0361a1521663789c8ea09692576785744b2930196dbb76dc570932c7e71cc2b09e9be7cebbf43541f3262207f63e2a55d27e6ce1c	\\x00800003cce2a38980ae62752ed040478b8fb6fb1326206cc1d43f0f8a8c1ccfef3c5c3eabeb968f470b476530fe53532925feb97d9e151c7d7cebd167ceeff7164d6e62a1f15c8e388a0dc04f48c31577114b805f35413b0ac796bdd1ed9bfd2a22d41e7d6aefe4db58f4ec41c4555e46ae27d2c4d1d21d5bbd14f0809dee7dc102d14f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x595aa460e5c129b6b9da9c94bd22d4156ff06f4559025ed6758d19f1e4d55902a255be2652beb1c1a9769e97c3d2252b206a6f68169a75f0485125e9fa851108	1614954407000000	1615559207000000	1678631207000000	1773239207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	133
\\x5fd137b67ef4d1b22e7d1f742d8de5a8c6e62a77f9b5b6efe2b1d92f276efc9fe4549620519b55d358a75144ef508e73fb26216526193bcbccf0d1c13d44af73	\\x00800003c53731c7cee870d322d31cb9707225cbb758d2c8055949d76747867031f95ec0f1b3787cfc1584775af1ad4669512867149dc05d9504a55db9ce47a8da81fe38bb08b77b3b3a4dc8d88fd4926b2c4703260b738debbbee566ac020696a47488b9ca23014005e77c337e8e0fe46c3b2ca57290060fe62d7279c0d3a68e1b0417b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcd17797f3bd9fe0a35a0f7fe23b7e8aa90517f4292710cae8c74b81337f575010a361131658b8789bca3e1e56eb2b31b3172a15f6b48be0a3d8f673d26dbc109	1613745407000000	1614350207000000	1677422207000000	1772030207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	134
\\x633932379f1e55f90d39b189c2a713ba4582b9b63748a087fe3c41e40f35106a69c630327c24abe34d48e0b002e63757cb251a09a161a58ccfa34b5a15970164	\\x00800003ca96c7af837e659b8ae3e1b5a2159452fcd651c10d397ee4b3ec27c93811d88b9ba5a3b2048d5008dedb45a6d45dacc70c905c3788582e688240b7df4aeecedfb3a7f06c8484d2bac98b9ea8d537bb4680c8eb4ac584a938733619e43522ac9d4000f3aec8ba6f191dd34763273f0fbf9eb22df222935406ffefaa0d92b86823010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd0c80ca56c1c5a5d14c09ad204589d6d776736f2b105a07ae192b0a8c24d1217d3e7e0afe77f7fec1ff533320f71c8b2cef0aa2a3eea763a41b14b0940682702	1625230907000000	1625835707000000	1688907707000000	1783515707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x66898c569dff2a9e5c1f76de2c2394cea6a232cbd6e798c93fb912e206c1d6531be4170206cc988c31bfb438f7730ea4458d0a918e53355378cb21edfac66ac6	\\x00800003c27c3c66c4221cef7363ba65f3249c1c12a3294d14186dfe648efd8cc726f9471c55dde48878b1f2148bf80596babd40cfeb0cb369089da3f9f0a9640955ca18f9d57c49d967f5af9f007f7603a014170bcc2e082dbf79ded1abb78402bb27537e42fed068393e8c60addad52ab889af4923a27b242938f392968e1f768f5b63010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xce114bd9463fc22c7701cd531b69d06d284c1ec44f8f47b15e582f963d39599fd33d441ef8622c1b47890bf9c3a6d89d44e3d51b7789756717a2695783d8c90f	1636716407000000	1637321207000000	1700393207000000	1795001207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	136
\\x6ecd9de01fbcdfd911b2f982358dab6b428d248666e072ad99522db558d15449c269579deda3fda5ddb9c6e61ddcbaf740a570b8dfce30e2a8f39c524522f3a2	\\x00800003b8de8cfa2c845a2409b5f578c5d944dd5638eddfc703aa21d0643271bff1b84066a1c25e8b270052734a1ded72053e28e336df035f5d467bea318618ee36b8881d7bb856612db1a5953da81daaeb512b81b24daf0f285aa7931a28b4e154fdcd6f976727a2a480825e9ffe1c6091fcc809b02f1799dea0bc884b0f7f0665ab61010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1395c381b6fc41079da9757311d7f437938e884129d0807ee50bdc2e1153fb6ba242387b523f2d1363d8d1dba09bbdf588b8485d71dbf825b1feb8068758fa04	1613745407000000	1614350207000000	1677422207000000	1772030207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	137
\\x70914b4a5e6373e8997b13623fd414acc9a5a3a76c6eda23c5225ddaafd2d6cf92b1e2a6b709b7697e3a1ee5fc166354d24a78c997a58f02ba91272754e3ed50	\\x008000039cfce3df67ad1c0b0d1cf6da0bd2cb2070a34d6109234d8851cb25080d6f9b7b44d8c8554e605d991885220033ba7db5656881baaf9026ff402f3afa7108c3c67cf05264306db6b7c348d0d0b9801ac2ad18321d5c4f42128c5b22ce82822a552884c502a9543d0a643b87acaf79f36edd074e0df78c2258d6eef94c40073c13010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xdf77eafc2d0401705692fa2bdf3564c77ebe1437ee20e4b9ca755e86defc6b6efe9b79c8e8d648136c287cc05380d6a64d04049406c0e01bdd0963c37096da09	1622208407000000	1622813207000000	1685885207000000	1780493207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	138
\\x759d33cbb22730174a70f0e3c287fe9704b544d70b7a39bc5974b7a7f3e182e9b20305e13421740e98b57de9a33ba18748baaa746297c66a1e2f1e9a6689ad33	\\x00800003c8f58ca23795a73cc499c8e35455853a2b9ca805e555e553c3a4ef1d4d60c4d729c43fd7464f2d42a9131eb4ea455ae4727e27c6417d11676b819c3d0fb9b911819e8465d29f72e0b8ef49c7ea0a73e470358abc3a94684cb298d0057422e987f428a35aaf2ee353d506e56b7719bb661334a02c53efd0220ff7210cbd170ae7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x08b996f1fe3c290fa86ff79d7a7a706a9e77db26ddf3d5dbe044dd88c0519e75825ef08c38b1178c7ffa8ed824cd6aebffe225a3ed6782f882134a11208a0201	1611931907000000	1612536707000000	1675608707000000	1770216707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	139
\\x7615177fe9f3d9ebb80e34061cea572c21588dad74cc4565f7f2f4dc66936f8150b6fa45f1ea3c709e9e5237ef06e3bfae223a8e9795ca9f8a2db15bf1a86118	\\x00800003f29fe0da2ea6edd080692eb2dade5c13ad76235c90f14bc3310953e118da9a31610e374ae28e9816ce69d48e777fcea1ae8d0c25ce290dc59ee221c42b1735e4d7b512bde6318a983993011531bb53452454c1f16b94b52077655b60e056cbf90c37d955e84947da89337c38e78550a1f8796264bd58df812e375a8489924bd7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x77fd46b06e6c7103ea74c8bc938b6b85c143cac5f078c2f7094d974252166283903db28766fe730d3c4689c1f62bed302cc1a9e4513de23b593a46110bb54d07	1613140907000000	1613745707000000	1676817707000000	1771425707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	140
\\x773dbc4f41182f366e502628390267f4769d532ac308c9647c8f0189f11e1dcff97ef99c87248f65389510ebe14f6cdfb6b792cb6160fe02ce81451e22e37ef8	\\x00800003bed73c1bbcec8209a8bb6f8b9747f5b64b86e973e24110ef7420e5bf5e649406bff4bc3eb9f09879a57174e8d48799b661289f20d7888382f92eada557e93a4a6fe4006ac56f67bfe2912f58c458206b309394fee5bd2b51f8e269c3938892506c6ca13b578c32d5843f9c04edececb7c4db78973948a4679613005538f58ecd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb97a14a7a9732ea90be2aeacf34b3a5bdde1b23b315976655d4128716034496edeca5438806da777fd4b4d13b343f1219a125c76b0139c79507da76f4505d502	1627648907000000	1628253707000000	1691325707000000	1785933707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	141
\\x77f17c689ffaa4cde31c273cfab87302ef7e137bb9d5063f76762cc2cb03f2b6994f2e19fcf01011293480fb7b2213ab335724a2bab0a947ef916076cca9c954	\\x00800003d10c6710ca608edc1cc2fb82e0c4f2a09dd85ea9f31cf7bd8ef8abe0e72d37871a8b549e3aeeea3fba1ec19d2f30fb536b17a5e98c32d77e3344ca1fa4384bf08624a35400a3fe1b3b1346fe4812a6e613d69cf45741e26abd9fd7374784810f5f2bee0ce9c572b265aef83e7cab90ece01ea85b4d556421493910d1f01ff161010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3892fb7d5a4c27d14c2b2b420ddec7b3f4048da6cf3458089c5fa63106a47b6f1a0895ab54bbc9209e232567a8a3c64945bba16e203f4a37066bde431110920f	1637320907000000	1637925707000000	1700997707000000	1795605707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	142
\\x79c5d79476521f8bb7aaab8bc68a3fc626c4bf6f3d2e38ac3ddde335c9e7b606c3aac80fdf4611e652f844a84948f942a8a6a1d1de0bb3aaeab483cf86ca7026	\\x008000039658935f1e65fcb69431bfd2f5e8bddcef921d0d819d66a996935df9c29af80ef5694109b332ccac919f523e0587d8ff7e95600705c5cb1d3afa292f1acec798d88ca47a781035e04c30b6935e89d3fbc22ca6d6e927be4973f75fee3224b58c5a8b18e4ad429587eac542732087f2b0e490392c8b1fb97deb2dca33ffa232b1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3be407642e159f3031809733d5061e3e4bfcd30e0791f82a37ac665bdb89b6c51dcc12e20b98802740b03de839fda5476b02f085cb52ed05ef55fc881b527e07	1614349907000000	1614954707000000	1678026707000000	1772634707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x79c5a8ac991943c99d2262e677355bf2e5072ed2cd0bfa776fe9437a4952459196ed42b5039b8507aac19189e61688972e80a39e6ae96a27d24e0b4172f4b760	\\x0080000397feba7732e70c798fea3cdbbc7753700a792c4ee3b631f879f2447b22f102187d39fad9f7d7d907020f9e0381e01470084c5116ddec3b973481107233fa87f2aba49c963e0aaf461c5d65c93a344396d4d03bc7fcfde6ea49c9d695d8b13689c4a17b986be78d2ce6f565d4a3a5c0940f9978ca92d22d68adb93ba5adb00d63010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe233b957bc361f1db937a6eff9cc0953c21b0aeb5b6527ed7f49ddf839c40a281a8c08703070dc00cb9c01ec0012b97be2c0d2443e7972f0df67bf5d3d066a00	1633693907000000	1634298707000000	1697370707000000	1791978707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	144
\\x7a5508ad988a249cb54a4691e1f75759d0826daba022228ccef79b8003d17a5ad1e5d6987233c8e6fecf05e025a479c514a26933360df5708ddaae7a0d06d268	\\x00800003f35f138955eddc08b1b353bcebe7fb5d10efb7a9d5729358b8a7e32fad4b82c30e048201c46fe161d3e8b5149a83bbad57a4898a7b4da5746faa41d820d9a9b2265955241902dd09905329b1b735566a286eb6853a7ccc9098e6bdc080f812868112b48c3a657c990e834c33a22a73be5d61b97549e7099c5cafbc436d3f5005010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf7fbb2c36bf89a85634b0b51fd2bc33d0c7ad1e6b9c5a3531928217305aea98c30a9507bb37393ffffcc6a09823404892829f198d860b26e3a89e282bcc2740a	1628857907000000	1629462707000000	1692534707000000	1787142707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x7c158ff6c45384aeb02df70f109f0bb75c9519e84871954dc108edd9a1171c979dbbf5cff7632da753eda0d0f5c2f06e0ea1d8a6bd232d85c3af5c5c7d73393a	\\x00800003ad9d5a307a758bcda511f2fe50eda0fd8a60a92f3146527aacc2b5268321bd0668aa76b893618ba356523652f7cac0960a8c12374e601bd295b4221d84574d4c44808d0694527888af4e9f1f5fbc6bdf3cb2f13627b089ca639072e21895d9b46ed5de76d8de8b11b00a8a389595907ac71b1d8e246d5b3a31c46617ae4d27cd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x46febc7f6cdb5e8e3b98d5580e16009a30cb67721d433d6851e6e97c48353509112db8babfe73e132455ee41919c15613ec0e1e1b5e71ed9359c999196081405	1613140907000000	1613745707000000	1676817707000000	1771425707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	146
\\x8355ef23b3a74606a4f8562c08e7cd9e1b6add1eea346f980af2b3039ed864dcc77812643bf31f64edb0891223642b603ac2dadd91d111831e0e8fe4f78f7f8a	\\x00800003aa0d321d6581eecbcf357f17f77d20ddcf07583023b073405535906ed458c2b9f356a2b5a00840eaba84a4aa8cf23bfc0c020d81a7ac8c1bf19b41c9c296ab9a34220aec08c5093bccf08b9926872d7a566da8b5ad7eb4e9e75dbd2cb5fe02c900e79483bc7311e511809b2229c099e09ac9700c04130a4410c2e00eca39009b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x056029cb56eb969b4a8fae66350040cd7474fcdbfa6e010c6eb2e4d229825cdf45270ddc3b671c54dcb0d16308ed539dcf16773f807ad2495fa55e1785d57e0b	1621603907000000	1622208707000000	1685280707000000	1779888707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	147
\\x841505f6e955905927ac5ff2515d1b8004a614711c337d95fc26c04aec98fe50ed2c87e4d04d009fa4daf22b8e16082628b555a922027fd943fe8934832e7fe6	\\x00800003acdd982ab52860fdde313e71a1f472069a41219fea53ad0b732c6b4147d5d60191e27ca18c4e89a869e80e37bfc2e7475e351a923e58f6bfb394f368ddb98a21ca91afc1ce01af873827a1b83361a4d404d8e48deaa175ceecf7e8711715a104c52ad991c8a64a7de3175067b39d08c0c196c2a98dc3e8a85090f6dba4a67aa5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6e17d41cd3d238f27ad2f8aca8b954bda7523b811b2ded01258670e8a99753fa379855b2ca4a54df54d96673779b7a2167024c32329a9e8da4b4d1e5244fce0c	1640947907000000	1641552707000000	1704624707000000	1799232707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	148
\\x85adbbba87adfbc81c6a6e7fb16f1848d39ebe4fac05db7402bf134a6bc5fc619f6b1ea4c816c7aaaeb28e82acf60f58161f9958711c94a3ff82fef3bafd23e7	\\x00800003cd59dcdb96e4677a0952325d18f6030e6dba4bd301e7b8daf9a0494100dd07b46984ccee0f1022704fc0d0cca0dcb9305c124dbe29ffd562fe878d8428b69227768256b80332f9ff7b7caa9b19eea58f35c6cd621e4f1d15b249fcb92e69b4b153fa2abeca14b0d9989b9ddf9021976bb6753af9ce3c98e3e9869de34a5c7c1f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe2674ec9048a05bbd1e46cca361635fa23de2b7cb4338b05f140ec2a98ea4a09f0e0357bcefda07559e56f51ff3993b71f89f9dd52c67a53a7a8b270ebaddc06	1634902907000000	1635507707000000	1698579707000000	1793187707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	149
\\x8b3924946da381e52e8d9d45f5ab29b0864cbff0dbf7f344eea89c87ed27795efe30f9307a7827dc7c2da0903e15511f09783f1a0c86ea20dcaabfa2d893cbe6	\\x00800003a21574fdea91c6d64ec72020dfcaaefe5775e1ec2ae07ec37e28ac9710084051b895bbed47fe4e1a3c4b9b58b207403940a33405ad646212c2a06ed063dd1e9e7554ab307a60128bccb0082e40b13d3a95bc21006d246f990afdba024e092bc03ea18aec6697a141e7428a1f568973dfe14c18f73b493a192f9861de60406d47010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xde9fdfe359ae4088023b587537256c33475db06ea268d61a2409c2a08ec8f6150c6092958d7b5a7ab7a6cf7958f4280cbf546a22624a2991c2188990fccb9b0b	1632484907000000	1633089707000000	1696161707000000	1790769707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x8b5d19af19a491330711bb3e0ef7b925ba2a1c7460c820bf8dda7b999394531731933e93e5ea2d4ef13b3926befe970c4f4d3cd3fafd1a71d5f44a41ce2c68db	\\x00800003c0c56ae3d9ead32497ef7f2f71c7f686581d8c284c5d62093c61a0d2c771d7c751b8833ed413a6cb688b24df9e63fac1554152c2f2b526670e7c1903d98bfe065f53d8e43d4297f813fca9f8133bcfb2baa427ba3dac5b208be8dded2e69339f40d71d86b69db6bf5ea7875844373f862d93cde9fd66d61a803c1b170420196f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x67e817b8bda21b7fd4cf675ede61f18c75565814227cbadb265a12d4cac6d71bc2bde972663fd11bf369bac6b83f2c4b37c76d0db01aa8564debe3672ccbc708	1636716407000000	1637321207000000	1700393207000000	1795001207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x8b0568fcbde5e344fe6126e4464bfc927ded4dd558491feaf0f84f701962a066b7c3f3efb3b0ef0613ef2e2b2126bdc130354d6738cafe57037258db3a147133	\\x00800003bb4e2cebe39f53894064729507d779985d90340db44934e4010c0a49cce402b3633166dbc5df580732224ea43070f42dfea13c9d3f738c0347dbf40601e6bf7cb7ec1ad3d11aaf4d37e259f1b6d9354fc8c3944c375dea3e135558839156df3e4ecd9ea6e1cb4524fb1064094649cfde1469527934286a96efcfe5e240c30835010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4217f2c62a191a0f6f0d0e359b47987121feeda6360cbde3e3ffdb909a317581d07de24f48684eb1f3222b06b7514c8d6f72acbf4e459db8be5fa79138fe0a00	1635507407000000	1636112207000000	1699184207000000	1793792207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x8c9590e401bb89550d379fe14b482c219a6080eb90f28fb58db42a64256ded13615b7b800c8ed423e32495c8d37ba226aa0abc0c3858a695234f84c505341d52	\\x00800003b6549022ba0c7d5293856896442adeb0789b0aaae7f5c7346812637abafbc4a1d6b2559a6f60abf1ec0603823c7f03b0ef864ba363ab11268efda6326b36b930b18733348e6143577a8e1bd34be4e9c4f981f1c1931df78daa5a4d89d4434a32c6a6e1147612bf68776f59ef096a2f9607a952f2c9077ca6ab25c8f319af2927010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5ba7f342b72a5615158db3b1f444417a04212d14de33040861089d5f2aa116272aadeb01855550cae546598f69d99adb0153039c7063809a673a6fbdc50bb30d	1630066907000000	1630671707000000	1693743707000000	1788351707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	153
\\x9115c0bb4d95a19281450e23071d63f9071baab548da8b504a06e4967399c4ee2434eff7f1569b741002f284d4c19c09bf11ae8b6813353674bef2a398757a0f	\\x00800003e74a43910bd7dcf0a4a607457a2893f6735e760f22aed6e3a55ac8c18f17cda00c55cf534ce14645afc4ceca6cf3c84024b5500a4285bf047d09d1e25be9f0f69b417e2b651b8046b18655f7b41dfdd9c682f9d984dd0dc80385af344bb1db68233d35c5de270d91b161178543b09114ec1dadec83fb9aca19a3367ef1bd384f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcd2bf4ae5b54b3067110c4c67826491658a183de3fbd1e61446de395d475c0d42e97a7366dad45d77f4e06de44963571e563c9924952bdf8429bda05bbab7b03	1633089407000000	1633694207000000	1696766207000000	1791374207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	154
\\x92810cb8404feaddcae830c75fc8f2fd90c36ede6107e876ee47b59fdd67fc4b3680013f270390f2509aa03231213cb8f0d1faf36e21e9a29299533cdaf67d68	\\x00800003b85b2c62e8ff478d8f0e4188d45a391c3b0ad31ede2ef767764480db62be5c36578f72a836434997b07225c0b4faf9a16e05022cd1e15648c387ee22cf66214d717a06732f587cb49f51e444d29c29994da49ee4e47a8fc2380757fae24ab5b64ed578a2098c024daa47f1ada81d4f32bf24c52384977e4ee101b74ed53d1df9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x412bb8a895b32b33b1634b8e91217f66c33e4cb587e0ae0ad7c9e66855e6f9789c0010d1f47e42f26eab85ca2c975ab05b4916f284e95f1e16fb7b5ad9395d06	1620999407000000	1621604207000000	1684676207000000	1779284207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	155
\\x9425d7725bff268bb1760a2af644bbabeb0714fc17b977c0628e95a197fb804982f5a849d2c0c4312484a62e58e3fce0f2bbfb520bac7c95855f80ab30c5950b	\\x00800003c359d2dd777fd2a981d5abf299d063a250c0c5c3e552f890a702af0c1366a50dd2b39fd152577983e11eb299c363d4cacfd30167d58c118b2a89451733ace99b36a465e385792befc748e530425605fb575676f0a393916e204de2bb7da64aba5b2502b99486191ad9163b5f8dec94d38d38537688b9a53dc764c994e767e733010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x93af9c38eb429ed3e34135550c0e1d531a09b16fca71be2af916faac1c90accf604ef5c709ba7c6b6734a0d3a930811281552c1d628069c52359319c15d7200b	1639134407000000	1639739207000000	1702811207000000	1797419207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	156
\\x98b925cd97efeef768a84e48f4f85175be6ee32029407480c4652f6917ef0ea0794c928ff873487e3beed199f412ad148fb6b723b39a66cb8585bda5e21f7a9a	\\x00800003b4ed05e0bc07ee8919f7621291fe5989fb1127d3b0a733e90a9e19c9b2abfa9b5a2bcc35f3da54fe13604704b66b841cb58f939690b0686fac881fda5fd34fc7591146da072c138ff3a22101ada312e82d5905060b0fbe9b32e7811d1171d0935c6984d1518e3c2f7fceb126935024ef479fe650fe217ae9a8e7f2881bedd727010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xff112744d177abb249266f19d3c268064c59059b6f05e13872f2bce3b1499ffc4c7a83650fd7e33332b36170f186fd2b673765032b9d6985c38667a57d4bc70c	1640947907000000	1641552707000000	1704624707000000	1799232707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x9821e93ce01682901c407b94489ba0e1f381f526c915e55e3fd786339d6bade7592737b1bb63e859533d75f4ad08042fb4517ca23d400bf0573a1408bbcf5765	\\x00800003b4fa783514cb181d19bfa536297eaffdff9130aa4308844a64a53df9031340ee6c4022176947dabad33139a461acc72581ef5abfc4c03b968032476e13698fe50d36dd51693aefbee5d7a519a9f1ef6d310fe3310d2fd9ae0fb3a7f6a4bde9a8fb4600b983678980247eb32f75be48692685e1ca4ba509c2a40c8038303e6b0b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe51921ba7da87cf107f4bced613ce6fc461cc854584ad6b9a20720ee1bd6bf89828129800b8b0dd6225d1251e6d57016411166d09235c67262548c6372d38d0b	1638529907000000	1639134707000000	1702206707000000	1796814707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	158
\\x99f95283c2dfb464aef54993102a8151479a35a474a1cec4d09af209c14a192ce632f0fb43cc2a8cdf81ff7e6d155084b311af12755da43dbadcf7b4a4626aab	\\x00800003c12c8b565cea48525e2d2b1b175160212e0b6817fa93b4e29f37d485d85187deac5034f0a1fa827c86d45a2c08856b8dc6a2d1f24b4a008131afb870cc7d815b45bf43fad5ae3acb7565844736a6cea1f9e1ccf53393a9de646f2853a71a58fcc6a9c96ba43dc7fb088bfd510674f3fb7d21e4b0522248a336c0a380972cce45010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6aa27113ad48bb9d7a06224aa614a9b06058f95800c528e6766f9953165abbbea02efc7399cece4794a74d20c71af7b6967db7f4280c7f9b9a752d4ef5403a0f	1624626407000000	1625231207000000	1688303207000000	1782911207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	159
\\x9c914945fd8131fb0210005a0d60d20ec7b042c332aea4543f9a6a40d96021ab28f9d0fd271df7349a350b34ae9aadb90685ab55049f43ae9fa231149b41ee8e	\\x00800003cf44c4cd7a7dc5edfe2b5eed239e0b88f866c82097e39ccb18145fa4640ea811db55e2dc81c688f62297a0a77705f22e4f2af93314f7f2e00a79de470665f3c9bde8a4ca28a8af3e0d21f468c4481af5ca641d2f5cc50728f972663bf0c484d1352994d715a7d8f2ca0c889c72ccd416670668b7e51d83237624a7a2190a3617010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4cbead20dcf3cc11ab7827b760257f2bc5378fd2a41cd64c5ea9b1dd42610a9db286064c819ffdb01107bfb6a774dfeed884efddcd1f77d7f7c6ce64f1ff8c0f	1625230907000000	1625835707000000	1688907707000000	1783515707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	160
\\xa02911ee6cd879624b7cc2bc643e068e463fd8e74e15975d211f94d36a946cd3f290adf843aad5870987e674ca2dca786225b83fb97dfc39d2b852eaee9fa3ec	\\x00800003b247939ba53d55c7816188b44b9ba8faf36dcc5fcb1ba0847fd4b380407b67bfca76d0d7a6a2f2fd22a453b15bd3f88dab4e9aad25f2190b19bb7a58c8ebf3817805420115bc305b230ecfcc70714723147c779bf64c34026543fac44ea9aa08b34bb8ab7d7ace2293e268fe19cf726fe05c42ac35c161aa254599fb8044f105010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xae68ac31432fb78dda0f0af50902ae871219e9f7faf2e8023a9206fabd8dd541c2f2260c6ecd75181428c9d317209af2dec519513dd7a7c0e234be0703347400	1623417407000000	1624022207000000	1687094207000000	1781702207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	161
\\xa41dac98f60113ea1ad6d97a33db8258e3741715eab1ea6cf97b748f3780c3df93d972e0e934e6af7dc63579c3d000897c653bacd60511ce978bb00555bd8535	\\x008000039a210754653edcc711ad20f667b1b854e7fb0ed0719aea4b182861b2a800890a3cf096b7deed2fce050bf7e7117d998108f8876aab9e3022432dc4af8e1077cc3ba439ec0bef6ea36fe2d0dd32b3e251e44334dbd0a5129e1df26c1fce22baeab92d9fa2ca1d015502cde33d95ef066169f18852524557fadce161046b1e5fb5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7a18bb6083eb241bedff87ee2c7f1c0270a1cf4b6d8f11d88d55c69904be23ca2b1448d5d1166cbb5bc5f71daa2034cf7ef84b43a59bad41d8925e579d813007	1636111907000000	1636716707000000	1699788707000000	1794396707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\xa46d806aab1eea209a85dcc8681e5670dae092b730be7179622b98ce781f4a70245d77f28c31e362463b25c2481ded326d982e596c4c0ff33f675644c9355bcc	\\x008000039bab0dcd8ff0bdddc84e94d5bf025c415fc0ef7cadbd2450a77e94571793dc3ac331e1ec9ed60905ccf998370a91a9187954213c3add6537480997b88209d97e7b7e6572c39ea4ae1cfb8bf750ce508e9cc5878674bfdbe54d7221c8e8d0baee42a920b7d36745bbd3ffbf96a91267168fb17ce1dc1158f4b1ed5df92713b8d1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2485053ed888d4ae8fbb1c291f7ff091b17986e9d170eeb3e30f941400fbe7278d7384014a4a65a789c318fa95c1080a3b33b6abb62f537371c3554607393306	1623417407000000	1624022207000000	1687094207000000	1781702207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	163
\\xa8c5523b3e8de6b96cfe88a28214ec2bad5e8442572690dd806587b177ff053fca534fd1b59a99cbc198026dff9c913558ab494b817e0070acf4b9d79858999c	\\x00800003b047a3dc0944c031c4f6b263646bc9b359f4713f3fa738667a44cf8476879cba92941e6d2ccc280f981a3a88ee201b3929886b8bbd7ddb11bdfe82681a4a53d7e528c20f639778acde0cc2a82d205f40318ec1be0eda9037912c6326a70f0f98e6bf52ca20898699d26630f3574a7550a70c1076d7de3cce02be340b4dd63a4d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9f9b58a360985aa7715726da848f4917bb2da574f590fa63394df29d7d58842a4bd3bcfe9ae16b2d96db8e60f229c82ad3f3bddf3b789510c36efb4042b7d40b	1628253407000000	1628858207000000	1691930207000000	1786538207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	164
\\xaaf9d4a6234b2aa809d3d941cd9a389a6dbc8062474b70e6e75a53d1947185ebc194ef27c1f382307971ea31d645b05a2138c9586ba8cadb094f646a4b5fb3ea	\\x00800003b5a81847518d7df3e75351a17d7449e07a8d494bf0226b8c421643ba04e3a6f9d66dbfb2b3fe1b4bcbbcefcb35d6ebb819ed7ee7bd9ce5f9c7dfc32446c2a3bb6537beed23282a18a1c3706725e38cef00fc2c6e76d0430749a3e5efee6e5c950de603d7031f780252829cdc784cdd79f710a0ecd5537d8058e34d7996965bd1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3894e58d271b7eec1a7263f0292f87294d043ddeca9bacf80ef707eff855e48c3403a0d64d5d27f1caeabe24654a107a786d6a09b4bb23c7e506b2daa18b0c01	1613745407000000	1614350207000000	1677422207000000	1772030207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	165
\\xaca9848a11c2529a5782ddcde74e0512dbec2c3a7c81943d88e4e3e4bd7f1fb2b08d3d83d216ff0c64ac3f5dc6cde3195c5b812490fc1e2a9c7f3d73ca1fbc85	\\x00800003d9fbffadf9b67a5d7a89c9642e9624a10593d553ba34620882be9e911b03bc0baa3c167bd4d363ca19b4358ce8e3c28b3bf7b173a12845910e3455f10e20692e1d14ae809225f111b4662f8c4bb0a646b56d45b06301eff3d7492d44bb66843432c20464e42a0cdc10deb995e4794bfb4eb7442fbf7cb9e264cde422e675b4e5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x726160c44298aef10891b19f8f6bfe55c41622fafb4cd3794a2859a07f899c394e30fb1650fa2fca9dd6c021646f8907d71374d053b9b75bd60168a9dafe2d04	1622812907000000	1623417707000000	1686489707000000	1781097707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	166
\\xac15e3e050d3364314207095dab20ff7708664040bf603ee333c0094ab94891c65cc762e8218c9aebdb23922ad880adafff6d80c49a0dd8d20c29453e3a42f7b	\\x00800003cb3a0a144f1b33ffd39fa705e85d48810440aed132406f89f90ebaba236ae9e9c354ac1d7fde28b8b02c2a5d6679b7a50f4bbc82f9b3cc8aa092293b18ee2c1fad587b2976f4b45bb39f60066011ea11433eba86ecefec7c863b48f0a34c5bf4f902c2dba26ea33665a040f599810f4fec3fb51a6a9149af318b92c659e02cb9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x027923f4c90b479898130b0d5dcc8546024d675f17c2ca7ccbe9893dc3ba3bc9972145ea7e267567b38e836328da3341109361b48839f497a0978b275e5f5102	1618581407000000	1619186207000000	1682258207000000	1776866207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	167
\\xadf9606021022f1cd57895fc4866a131df85d15beaddab04e6b1496146d731f64d0cd842b34952a37bb4bd0bdc04917209777363383bdc8dd395270fca15a173	\\x00800003b8ff3084190fd82797c7e2b1ff660d379552049f4dcda721ccca5dd3a105d61a5d456982264a3485f2363d9093323cb144d989e5719467f202958e209d9496f06ff75e482ea77d5cc1a31d09a32a0687600e6a16481664d8f0622388e6f87ecdd8e0fa66e350cbdc51da7097318202aef9fd6563d3d6eb06b10b58d1a0136d8b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x068ffbdb562295eb5a5dcd48fef0c652ce4d19d2594219cde63ef28e1546ce194d2b488552ece81f06c74239134ccb715249d1051bcb6144e9f41e5d7236ab07	1628253407000000	1628858207000000	1691930207000000	1786538207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	168
\\xad2d706a675d2dce6188291029db44db6cc811e446bd8ea584ed3d81d72d8cf9b21dbd9895165e14880b19159c6c6956bb51061f415cf1908d3307cddc52250d	\\x0080000398fe60d76922e6e93223243d85d02c9f9b686aab98ecca54291a58adfa225ceaf5b30568f011c7d594d0085b05ae018a07e1b06fa5791aec9806e87bc28a38d49f0f90051faa64a91c6c101c7590dce271efd8dd9ab76fb28798579d7b2e8fc9ac17a0c15a77cf72ce7878857ccb14986dcbb4543359633167c149fa09146bbd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x63716d96788139a1dce0d9d35c9624ec7ed9f1e2ef3180f44879e5f128aa6d187e8d7e1e8c5d15d53a31330249734b87c09ecd785f2ed21a443fe71a783ab00a	1624626407000000	1625231207000000	1688303207000000	1782911207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	169
\\xae41a649aa632c3a444bad7e664452326e0ad9022f61a206316ff9f48fc5111a0c1d4bdcb82bf7b6c64ef5a593f9d383da481135af1e083d0c2c467d90552f8f	\\x00800003991e5a11c171af647748dbe7b2da9e6f7bb3a837dd1a5127c7d31b80c0017923828bdd51ba891423d6969d1fec9c63ddfe4bf6f0c4651a44726671500f2ac5f9019128edc4fc24730efe78bbbc5f3f51db878a0f1f4c8d758e31552149c9d8379800f2be9c03a31b2d644a6462ba37e80dba385636824da285ebbee4497a7bd5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5ed6c4eae6ee56e3e2bcff31368f37822390efc9af5336f3e58f362371a9c10350184b123a355f12394e419226afc7846e2e67c5f0d0e123ae5edb160b759002	1638529907000000	1639134707000000	1702206707000000	1796814707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	170
\\xb0f523b4739f27ccc69f3f64e5310cec2857e7f02d7186638a659916e973a6b78ab54f60147a95d33005704e4447be4c50249adcb51c81f11da71a26ce064a14	\\x00800003d031137cef551d63e9d2517ddf5dddd1b675223ba6350215b48431f5174aece1608c50f3a812b3ce617399a9efe06c47e4a88cf274e98bb38f6b63a2612c63de55530846b1da74fdb20e2641ffd2470a004f1002e78f3bbc11fd494b65b56d78e175bc116459ec0d8d22dc3f2c6a38084e84ac4e57d423d9b1ca58d1e2e3b057010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa5b8a65fb7ddd449f212b5e1bbe342158520c4625b825046bb8f7b425c7e1455dc7a23b3d1e9e9d9c56702cf7f3d72261ff33c24c06020d6819b6e04834f5e02	1625230907000000	1625835707000000	1688907707000000	1783515707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	171
\\xb1a9cf4ccf913189e65e25c010bf8309dacce626eb49ff2642317a25a5df3cb09aeaf2a0095e2f911dfabc744f11f71a456394871a780763ce08adba2243606b	\\x00800003c113a8f18f216e665a9398cf9958df3722119edd8d7b00d6f9df2665d00d8ce8d2b121dc109b919ea8a0970a2e6e37ac7f04a82960f3c929095260d0b369249768c53e08929d6c37a520f278488650612a92a4bc6ea237ea40aa6b2743b4150ee9a8adaca09a9e6c0f7d4955cf7f7c843c736349f44a56b667a2b2625ba54eb9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x692b279941e11a0a69dc732dbb51761561f2a788b8ef12a639bfeb21f0d1da5a4914aafbcdf4bb5d5300c089f2eec6754e2bc409d6d2ada6ae3f852566ff920d	1641552407000000	1642157207000000	1705229207000000	1799837207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	172
\\xb1b59283637cdf5955e3c2a6f58c497e144520083654d5ff0b515d4c805564940d8005bb994ba55ac10c18f7f27fd7f7ce2b85b67a20a015181bc805454f85ea	\\x00800003c8264c35ed96dfc7b6d1514e0200db76393cc2e68d1152c8ad3e93057b4e13ed51b731f67142b14ff8fcb4b29a7a74cc02600f081888cbae26dcb1523e7431f3754529132b08c6ea75c974cbff8449d7a2900d059b42e8e7cc1e5b5e03206f5f8aa78becbc8b5b2daf082a58ee55a99a6aafa2f77df96b7c8e773efc832de67b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2bb67973e218bb14281ce39992eca595ee3304605b1041cf766922bd0ac30f0c19397086183b307cd47303d9fa4bb23d0bd2027374f1d076e4f86430a7984d0d	1634298407000000	1634903207000000	1697975207000000	1792583207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	173
\\xb2c9265a8ea3a11ddd65f7ddf86122f27d9bc294afd9468e10f89556ae1f2c3468289c98a3ec72db9aaeffb57cfa680749c502ae7f7406342dc7f05576bdbd31	\\x00800003e4370a040e82cd89fbdbc06a2294dd8b311de2e156b9700cf2a52bb3a226c1af4cd1005cb3cde7840e59ee8d5dfcf6baf75194c6db401e22e4f433dad3b87551c38a887f35c3538dbf486e8d1cf63d5e0e4f7536173412bc4f77a3a671b538e384cf071631e5d60c5b8d17f83fef70caae2bf6e845db797ffe806ffd155e9b7b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xff7a649f9f5f75398fd0ba376b60152863d7fcf3737c21c5f532046c11db8c735cf842961eb50a83588428175b5b0959fa26c88d4717b7f2d3ca440c0e27e409	1632484907000000	1633089707000000	1696161707000000	1790769707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	174
\\xb765c4cd042cd26d4f4a5dba6fc987ed37dfe6e0a6387cc6913c3f56d98e51fc06ae506b15321966764fc622e1f5a4929e75607b812eb576de25c11606b98410	\\x008000039570530113691f9735dfd0635e96af7848a6aebebb6513550c9b9dcd531df2cc4ffb9a72f3e4f5177357ac9d89f1440b61dc092494ebae9706976b0aa19aa6d9ab90e1b3f55fc39641b97bc1f1ecff46535c0cfd224a74c93e5971ff35fa3525664afe935b1fe642db85f87f7c0db8152ff61fc26014fff65a5325500be2b69f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x66cf70bb53ed9d3482de1b4df7a33b2e77438b8a761a6d692466fd7cb3068d87ea2eb1d32834580014d58cc84903fe0629b0cef283f0fe3dab861c5425520d03	1619790407000000	1620395207000000	1683467207000000	1778075207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	175
\\xb8d12f90c9c8a5123ac6baa06a05c8d3be4162b61452c28b134f0bdafd307522da53bb13d4ee1a0e889049e91024acfe547b54363d79cc7c5449d8c0da3bfd8a	\\x00800003ab5a1f563619636de62f72735af6c9f852393581aaf5a2e4da9410f39e021efa2c2e337ec94f867318629cd42ee808b92a3408a96875693e70b89ec4d22381d344e49e55b3934afdba6a27cf48b2b4137839eba9c691aa325fc66b50e6089d0d0ee4f1f2f37d391656fae91b1b7de812512fea2415a3f46470eb87c130644153010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4a754ae832fc724e6306e9f3147b5f8cd5c6476a08143415043fbbd7bbb763d5c2042371f3a4f1fefc1f1ee01991c3b27f76bf585fb532c4b05fff0395c71408	1627044407000000	1627649207000000	1690721207000000	1785329207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	176
\\xb97902b9010f4dc39f5f626bd784e7473e623a5d93d936881dd73f72627c4e3a5171f744b07ff0a02cd80339d80e93df8aea4aeae8afa1c20d53b96b1d11b079	\\x00800003c7a54f940b9e04675eed0355596153ed04288fdd7208282e9526899d864786bc67190ca80dd9e6e69e0711a3631d7df4a52b125e3352dd95541ae449fcc8c8ce01bb1de00b5a1d929695a9fd54e1b11081449827b94ec7546dea65522756fc2643b5eb738f8100e5151c12b96adb098caf2bbebd6067854cab80f17d5325c05b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf41b3fb9f64d5c285ee7bbc1e4976c7e265d877a68adb6273f9060485f7d842a265381cfac721db27db4d84de9830526ebfa5c740d78b53017f5bf6cf73f2808	1629462407000000	1630067207000000	1693139207000000	1787747207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	177
\\xc1f989a32cb7a467637f062c6c0665931d202d1c012602c966f31e30fc69f07a29e3ea75ee1c132484ad25d6658b687cabb0c70a59803449188f6a4ff8165c8a	\\x00800003dc44aa4e41d0d4cd96b3d5437a0f613bc7e83f29cbf3d07707d5644da1c65ef074892dbb496fda01f12215e4d97c57c954ee45dcf37c18a2dfb9a6a85c538920b4298731f25ab6d6c329818f58031ac4352aeacc518504e4fd6020f2a012630c9a6315148d1db7c0838f252ccbe3730281236b5174d6c4ee6e991eacdfdd4795010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb5cb8ce22352099975ebeb6e8509c509c5eb9e61c3e93e16ba1ffa183145450a2f12c7a1ca4187143a5343ce84e6ed2e1fffb481ffa9bf8003dbe596f2cfb907	1614954407000000	1615559207000000	1678631207000000	1773239207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xc2ad51f9f6b38d604eb7587de1920be0865915ea343d28dd3181e29dae137555041f9dcf9608c1ac691d92e9c320a20e2143f3363bec6a9f97dc8c0a9627bbaa	\\x00800003b4d78d9c1a2f5a61e82be6aa18a06ff0b617ee6a915a8ecc0f7361c32eb3ed9a1340f4e1c399db0bd03fc0f37623cb95bde4dc3b0b3e7edc121eda762832a7311d26dda38aee3566dcb5daface9a44e477b83df364019e73eb92e5ece18bf733d1b3c72e6641370cc67415b28d77723f2908bc10982ec46e3f955e59926153e5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbaa7ff9f2a7dcc2d1c40c3abbdbe834bfc9981666de9f08baa8cdb5bf02a343b3e51aaf3884b1b805df2dc997c81ac69fae87ff66ce33a1a13d4f7c00ba29b02	1640343407000000	1640948207000000	1704020207000000	1798628207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	179
\\xc6a14f77f489761fe0b7e5af3781dc234b92482bc8feb68f9d6f73eae4f505aa6e459b731bc3db93d1659aedcc855ca65c24a0d652f3e8227c450bf40ac54b34	\\x00800003c60efc936dafd773e9f2c27070f28542d86297c74708acc219b4f3b3e1be6c3d439ef19fe5c68f77799ad9cc66e71b2446a937b61bf93357f3c26b4ffe82e6ea0e256c4ec7bab801c702f300176ac16b096130a1adcc3db5677fa61b0b832912b7b988e12447e05263a0fc2a67ea5e74fe1f20845640221fd4da4250d07e856d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb0fe2e951f3eb7feff1d6d0173bcd1e959c14f2e185c095fc30260324a89860b9a582ece0ebde8a9d8e51c3d3c5d8b6508940c1840e49f88019aa1023cf58508	1632484907000000	1633089707000000	1696161707000000	1790769707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	180
\\xc7e9e29fe0d5a52c7ef70c390e2564e5b3d69e4a53c7c71fc609a96e00bb76fb22897edf78b8d6dca38821d310bf10b5d1944fa67909cd9a8f691ca087c92492	\\x00800003d25909d4a1bb902a7d43fdd2f2e8b1ab24e9393269904f07c2c11d57f5e5a7e58854f4e07a7b54216c587d75a58335b34621257cc0c7155a6d1c2c351bd05a8550823f96a40daea6ae6d0d04798e8162d20394367a04769f9e596241f3dd10712514c6276b39ad2841bdc770253426bed2b65cf450f24b8a303b8da8725bfeb7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd97b1cd38b999d6516418f50dfbebab65afc4d37d01ac93b46da0afbb0e93217cfcbc2b9ed13be28f7fca141b1a2c1a846dab84a7a67ac867dc43a997af7bc07	1633693907000000	1634298707000000	1697370707000000	1791978707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	181
\\xc805559f4af2adb14f96cebc1158ae80b91989e4a26f408bf81d7c542e29102c571a6c34e693bd20653e36d3c641061b4debe6a3f35f34f3bbe2f2c5a6a6a61a	\\x00800003b2d8f86d6796d640f7aef866deb3269882be65e3e169ad68c703036db1606c2a31ad11202dd912f1827875e1a622ed4c4bd8c994e56898088559108353292a6c00de7b87e04cb820dfd6567603697bc152d3606e2391490748871903e17cd554ba2d77f5a2a3317f6fd6bbdb5163a018879cb57560fe12359acb2fa5e144f0a1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb8a9ca8d9f13cad45056beb60f19ce28e42ad8a94b4bed399926f3f234a2889e8768a74223631e3fd1a832bda056fde419ab340d8ee0b492ce1c5830dad7b807	1627648907000000	1628253707000000	1691325707000000	1785933707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	182
\\xd0b5b85003b90138792362ce33fc6fbf2dd52982f9480ed385bc6aab948300501903d98b652d517e079759bd660d54c1aeb31fc861926d8afcd4dbb199233dd1	\\x00800003a46ae6d0b9359f467a2c0d9d9c8c0ae52b76e36a29fc33c1461724647153d21477c9907276f1ec27677d0eecca9e829252dea37649e990466a4041d52c94d5c3440d1b00b7eac3ed0d37d2962ff13a7dbe988ac2c98eed1f11fd629729fb460e99845bc0e1d32df49ec7612835c220056d77ccd41990d4db9b0c562d545c5af3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5a2a255dbb8812a5bc85c14c9aa94953eb172e23d37e589b8e88b2b9b35eca74ac04b8aa6c312fb25fe79690128deb33b4ff7851f34b99959bde01ea26220705	1617976907000000	1618581707000000	1681653707000000	1776261707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	183
\\xd06165e19e57e072e2156a5906eefe0c0f8646670979449f0c6b8e9da5d0173dd984a831fc49d0135831413742d28b4fdc0c4dd61e5edb533a01fccbf50c509d	\\x00800003c3d5f0aa9ca7f975a61357e934c6064f61edc57dbdb3a82ee902849ac19e7afdaa236dc53239ee6bd5e75257c277171e4b79a14de047bd0ddff2e3bfbd95b6f9f7e6cdf444ade63c3cbcbb091cef9da0a0735b113dfa5a683187943766669e8e70e34d1e2860ffb00628356b563c5f3bc28cf5fb706ad28d9fe4f48b89e3cf2f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7c22e05ea8570acf2105e8df6e36624c4ea791892eecbdff4309699c0e974530d2e9083c910aeb5e42c1eda3f55bf403cd019d410435e908f634f6e8d714b102	1628253407000000	1628858207000000	1691930207000000	1786538207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	184
\\xd5d17319cc394f4f33dad070ac14611f738f4e327e58b065bfa8f8024f14deddd37f72edf3f3a5f005d4646067f5b184b3ae2f56141c981c8d4d4bdd2d20363e	\\x00800003bdafb4e82e413e4a5958c9e7b131fe26da4c9bd1cd3f64b2deb1c162000e548584d0c2523e83b5204e00710564a546ba08e13104ed161eedd07bcd3f580a8fac3ce7dcee5685579777bee2d352dc038c08511df7acb4575ffd134439ee153fde16e9b6e08fa698b174388e585824dc3886d1a57f7d9dc782a0d54f4ff2988293010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7babfb6ccb09b67ff448e7dc654e2429b6327ffd07766867625ba614972767f0f3ca4bd080733c8c692796e62a2caa5aca1f6e55b667cd669596b78169bc3303	1624021907000000	1624626707000000	1687698707000000	1782306707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	185
\\xd6dda4fbe6bdd0a16f2394ef654998ac78bfa343da842f762b55de087daff5e0e6c53642a8d8fa767838bab6990ed3b07652af56688b5378c3696f4b82977ad7	\\x00800003d83904e15c6473595dbfa563c962d5590e0dffdb08bb09da529658a890c047bcb8f3afc36fc105bfc0de11c8239d82770425fb729cb885cfc3e5fe5561fefdf06c7aedf8667b3218e1b585fb7fc29cbec6711c21d416e01165c907d0844b42fe3d82f3471dc58d21dc994bb3aa61c697b8495f056e61bc1c8bcc02f87e4d4e89010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd566e7478fb6a046462eb86bad632b020521e7f9504fc9f418b9f61f2bc558958d0a684848a413c2e48b667f4823bdb804ab84941e8c9e96372e6d2437f6360c	1621603907000000	1622208707000000	1685280707000000	1779888707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	186
\\xd85d456dba1a712e30164c02348908a7883a7b7c42810a382e6f11dcfb41eac0e94b2eba1c358b8615bfb76b6e48704c80bf17b34ad3e23a3e1b369d7d5ed3c2	\\x00800003a9bb5af2fdd1b38916b16e19ec485bba11b1499e058da877660efaf5be31c753a3f0d42f723511897ab6814ca8c0347a3700f3b0a7da2f791e1a9a2a159afac50f6c021d861d9844f2f569e752c01f49e00856476742d97d3312339db645ad944ccc83f4ab943a1e74e7e6da2951a0d7ff956afef8ac9b31b8700de5d54e6d71010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb55140491583f3bb753102f252053dd7d65b45c61cc3a6795739c84d58d9f23cdd84593546673aece188567bf8a9ad6db149574ba62226588c904ab377329c0c	1610118407000000	1610723207000000	1673795207000000	1768403207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	187
\\xd915e456242c032e09d46640ece73af14410d2450b2e0e2b6fac592c8678621228bc43d952e17536c06128b47fd67bc093137abda60b27c96303d81cbc60ff60	\\x00800003cab21414b5443ee69d6ddcccad26a459f670a6afae3fe6acea036338a6255d80ade27c020432024024c0fe237d0e69f2df79854616c9f35c7c27bb3bb535bc0df39420fcd6bd2e6a6bcc8cc424bee52dcd86e4ac7cf813ea8d149e9bec35d9691db80a972d650d79b78466e0bc53181817d2ef9b2bfe0f6e8ac90bfaa65d15f9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8cf0fc1b856f57b73ab81a497f840856121569a6c6fccbc857d79842c3fb71fc68fa3a2ee3f2f44b54a712978f41954474bbfdb77637a21df312bc89627f4802	1619790407000000	1620395207000000	1683467207000000	1778075207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	188
\\xda7d6b4b45ffc6ead8c1522652a866b078f6f1eee58e2fa9d61da7f44c35449fe2df9acdca3fd03d237f2b946fa594a0ab0fe941551e97db771b06061b80f09a	\\x00800003c29d14649d7b0c2a47a3404a91986cd0eed5a53be8b54538f5401c948683997cd8b6c5a631ac45ef377efb975c2d98d476344a08a37ac2b7eedcc897c5bfd421736efbb4945efea207b9787fce8c501f1b5942810b6f99715f0f2f90849329c507602288ae5ff2335d8a77c68fddfe92e7ed2cac46a97e097065e7c05f441c85010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x849f75defe652ac993b61a3e75a68c36efbab804143315b2bbc16b5d56fc17773f2122525ed5dbb4b195d9a6898044c57eae2947095f8a3478cdf5853882b409	1622208407000000	1622813207000000	1685885207000000	1780493207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	189
\\xda11140fa69e52b0a51b75b996a7397a8bfc2125ded210938fd386c5157b97a15d8108ff5eccef538d624a0d1a2a62ca6ef8f51934c1c76b4112ce0f6d394be6	\\x00800003ced73c158e04f41de9d9aec7f097f37ce461641566cd23443cca717ea40ef04e392a98df272ec0e8cd128c1d4000cdae009eff635e35de0676b067bb1a07a0ed62b2304f8fd4750758cfb5ad2cd28acdf48171462309f3ebea2f3d03977ecce54db4bcc9aab36af8123bb5204522ca0cfb8dba2849511a8d783b72f30656598d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xadd0c0fb1b392fce15ac82b968ca79eacbc03bcebf118f561fc6f2cf6abfef9532dd69593f94d5460bc511cfde7c57ddc3f5a9d3f8043bc6f3583b324742cc0c	1637320907000000	1637925707000000	1700997707000000	1795605707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	190
\\xdd6564a222fcf1164c48fbe9847f7c4aa3d852214ab340887fc29ffbeb1fccca840478f6155bd1fb64b1aa7bddd8c43d744b363d29c8f7f6eeb308dd47ce4150	\\x00800003c5e6d4c6b1827ae5d9261fe318f27baebd4b6f533a2b6aa3a0056867c4be73ad88530a9028bcbb7fc01c9b5c46c07b9606126348bd860c4a542c5645f3712c619114584aa94c2051678e56fd393ecbefa58354783f99ea5ad3293b576cebe01192fe960429f934dc9957a576d15fa741676f556f603b50ecefd243478b0f74f7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x85f33de2aef2e0fb93ef6910c562e925c4ab3b414cc419b1a77c4e75e6f60dff2729eaee8d2b6fdbadf54ee8b2c269fe632b92f0698c916b620ffcf58fd88b0c	1641552407000000	1642157207000000	1705229207000000	1799837207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	191
\\xdd1db4fe987a9c0697c1f334e6348bc967b531706fc9de247ab143cc3d6ddefd623249e02e773aef016c0c1f2dcf1f62bf0ba550dc354744cc9c765264034685	\\x00800003b5d011747ff68386ae0add2bdfd2e26768d7159ce8ae83193a71429ff5c82cdcf21da54a3418928ba5e68197b2cb4bee44a98263bff0c51e4e2d24b2067c5e05b21890ad77c8b263d60b603410a4ae4cbf5f162278d0d0c4a135714fc37aee6976e1cee9c7e769f1a82c4f505f14c0becf22a32a2759e0c3d3da5d3eff35ff6b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9e5e6babf72eea3e29d1d661eff954d3785afd7bb44597f4c26d57bfc752ad4cb886290094015e3e76c48d5ca2f7bdb42534c7a0d004fd87c2defda2a4ffdd01	1617372407000000	1617977207000000	1681049207000000	1775657207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xde99519b2e3dc610193f161e31dbbe8eef328ca4fe66c3d085ae37badc14acc2d1f2eed03f29f0f0598f7f5417d126e11a0a388d98b7c4b7a301005ac4e45611	\\x00800003d8bb74ab86c6e06d9247fd2dbaed7b23d916b20283d19046e82d6a0f35a5b6563b409f861ff0775ff5c1856085fa3ec55698d37f7bfc7268126f7c219f09b9d5f7e4d3ae3b5066228b895ca33d0406f2bd02d3c6ddcbf20eeb133c6366c2232428dc433463a038985ce6d6d7bb4f0875be036c0eff7f93bb2e151ab0b45d36ad010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x48b995fd2d8552ff69d112f9c2ee91702f9fca71144cc5cf6314922c791939ae30e03cfc917b1b2b22c304430c613630836cf258290e971f5aa53542d3058d0e	1630066907000000	1630671707000000	1693743707000000	1788351707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	193
\\xe075b5ac8ebf2d7ffedefe898a2709c4f2c2644c6bbbc78dff8036d260ce2af51f8905e1631937bd09d13055d7df0c18d31082073c21858c0abac3c93b1423a5	\\x00800003c05775e6391d922d1e8cda7199b8d8a714c23df0e228d0ce079ef99171dc7fb5eeb8e70d54a2be6dc13d3fcba673fc2b5d52f7cc1cb810fc7a43bda8b6fe029cd1644c2aa8491f7c8ce4286db06e33c550af6e5f8e656867a52ac58adc4045fa600ea75aaf632d91418220a50bb804c83117720903190f0ab470e31524cace43010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbecf403abefbf75e0f6687d7c4ec0d2dae7f3d44afe14b2e490ce974441ab202f78c077496a8c096e47da1c641c0eafb86f8ab90137561795ac8ca7e14dbce0b	1625835407000000	1626440207000000	1689512207000000	1784120207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	194
\\xe1f1953a0621eac521d3cccaa80399723653a7b2711cd36c25f9d6160769a3d8987d673f25a4bce3d635066761b5454369f2ff2c03e40c44d0aa5555b3280d7a	\\x00800003de26e0febd7799adfc9bf4239b2ef1ad37e8d2082c1a616e0edb973117c45b2be09aaa397fb8def1dd450ec945562ba1f104d4b045b87c83b367d3d7ac2d46db4a1e50f1598f3c7ba8093a1bce228669f4aee173b7ca961fcf5af4c1675e7e5b28d88f6323eed8addfa614a3343b7b9e1aedca5b9bbd2069de047f732ba0b01b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3cd4cb73aa027b25902cb1d6dbe8de80ad88269cdd1389ac8a1a0be7579be8064243b04ccdc426805c1e63b95bb506c1a1d5977e96a72aa58a6d7c5426d2590b	1624626407000000	1625231207000000	1688303207000000	1782911207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	195
\\xe68165ebd80c5700547f5cc9968dea0e95b7ad1da22306ceac747e949681a26d8264bb820b69d58efeca92c692ca26af8b9f546388180fac4ca11e6cf21df05f	\\x0080000391ff123ec891405f1671564f0d97d20d491d8118bc37e7153fb45ddd92d2b092627027a7edd93a8ef029670abeae4373bf95d4aa6b97fb880f25fa0526d0e0ce953ad52b974151c9423c7a896763158d7fdb30c2699f5de1c178aebb54231ea456f12890061ec61029316c19c882341ef4e3935bd0a68eb5b9e5a1c3dfa5e45b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x74ede0fb40d7f406546a126b7969f131a572ecd4ec53280507c4ba57a5dcbdf9bd664ac968944fdb6673c979b2a0b68f0935a32d501a18c6b57b7f77a8e4cc08	1614349907000000	1614954707000000	1678026707000000	1772634707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	196
\\xe61122cc7e21fd1c0362b0fb256319fcef313eb4898ed9fdfccee1c72be4b4d04e3680e1334494206a6e49bd33a4242c2a9f8b2dde18529163b6303c468c26c3	\\x00800003a96730bd6c773f3e32c5f0c4349fdb1090a7e80bacb6267cfaeef055725658f1a83aa588ed22fe6ae3f85fabd5cec8fc13de140e4dbc62cbda155f150e78848db17e4f44f6da0a6cb46d6575ed94708b9cddd876bb0f5c18516119c2324127879d737eecb69a6dab4cbcad8718c5d46001ae7bb8bc866a624cb099e176529607010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6f98ec92732949cdd5fec98247c8f4c4af331b91fbb1e5e96ebb936d89f5113261e4d13f71981d7de1e902e978ec0229cb4aa99d13f0213cf539fe4dd7a2dc05	1626439907000000	1627044707000000	1690116707000000	1784724707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	197
\\xe699887e66b7660e91c3254f158be05333fe9490e9807dbe838aadd41b339d58745c5f5d24d7c50dc52c546a66f3ce1388cea9cabb315142034cc913a353c993	\\x00800003ba0d81e86217f70dd1ed975d2f68096a36ecc3e328b516160155ed6deedf5932a1e3a6964bc0b64d2e4a5fc98ea5b0447c033b2d4b86ecb7e8e29037ba5b3258b626a4335c6bb019c9a4ec90134ac15e7f0176b2b59f3f381b5b9b7a0dedeb17cc27c8fa7ccd0cbb7e9b11f7616c8ac70a308fb83dbe6071237d621a23fcef7b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x20a3337fb67282a210c444ce97b2418cf0c1265d2a4ebdc1a2f67629c8c61d6a61be3e650042d577f532c948aa9720f43015f6038ea0b0d991cc17e2b463d50f	1615558907000000	1616163707000000	1679235707000000	1773843707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	198
\\xe97150110036c02b5a831001fe5b2b425b121fb46e43cdc3d36ffe437bfc1200d41d0a8b9e0bb82f4a0485b9a879aa9549e4d61aa12daff36a9d6f20b5b02bf8	\\x00800003adad99a4b19b66c69e731770df9e713e59428f504c7e90579f88232da927148b9408e1d94a26a993fc27f8489532e2f6fa836e42ed65a3446a1cea554442253bf340078b9ccd78e65df9906e828c20cd9d1dc479ede7851c0eb96c08ffd4d0e7b553f64faeddab22e1fe6c8472caa905aad5cc3f9ccb8f37e8d219c40fa12725010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf7dddf0583e8ccb1879e0ae802e5a007d144ee9169e868e26ac92e3306de8faf1238a9cbd0c16d49379f47bdeec81d18224c02a45544fe1fed859c2c88d4650b	1625230907000000	1625835707000000	1688907707000000	1783515707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	199
\\xf1cd553df0ceb6cfae20a03cd6370d1a0c555aa79d59a93692b16da953f3d525eec16b47715a34d0ccb600b2139dbaf7f039d3bf7bb1cf8a20da1e316d4ede45	\\x00800003d9eab21d851ca82f7150d3198aaf44fefeb90d56ba99c4293480220b7aa050601b734ae2dd33fd1e230589ec691cc2d8e9aceee6cee6e8c60a376344c5ab3893954033c4c32df4861608d0023d10003413b10aec52233b25f1410ccf49edb01e20e8b61fdd1c34a2ac56b5c9f844007c210995719a531dbdcc42dce720d48985010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4e7cb2b86d8bb7a4f450f5db2cad50d681cc57b2e87759515e02031597a7c01f4d7f569137cfd50beb5a4881c575b8b41a8182f0b185086bf0e84c7d84dfb005	1631880407000000	1632485207000000	1695557207000000	1790165207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	200
\\xf1e572a543da5787c34fc09413da57edcdf880268dd4b38458b9350786addded18ed3b18c28a715ac118f68464a9deceaf844d6cf4dda1dec8763ac5ff15949c	\\x00800003ca19450a93410489d26c790b086d231370253cbcbf05e72074110028b840312a4c7f52461fe3c6e783f68b49001c6c735b26823073ee370bf33e02098449b0d8dffe6597683188221169fc72443bdc2111be9af0e8004944f0ed6e3c32a4ff9b333e4aa0ccb8115edbf10d09c6c6c27d6fb51cf6067449bba49fbb63901e931b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbac9b95e76611abbd66be4dcec15faad188534f3a3618907080f3a39d3bdb67b83911c6875f044ce9ee6e72d43493144a0e09b5c5dc7d50989fe774193c50e00	1636111907000000	1636716707000000	1699788707000000	1794396707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xf8cd9313281200a5cd6f9d4ed8c286e3e849c3fc5f8440f87ced493de8f730ee54e15be105f5b4ed6f58d34cd4bcc54154b1382d84425d295868aba315dad954	\\x00800003afda95a7d909a43becb2f3a5998749d8420d5687b796adda9d0cef24302b325e948cf12e18fd9de1f9e6485c229341501ab497321c627bb37dc359a64038f0fe6ed2309e27092b233c40e6cfc34c9fbdfd3f1def533e7d82522eee9744f12916a589e8ea80e2433063ccf1be254c422c0be5af4db4f81353670e3fe36fbd7cb3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8c5e8cc7abe5ea96c8ee457cf95e4500ff4ae316c81492e0c66655203b91bfc8c7762f172d7cae846e718c9fc5ed71f552cbcfb1a39c169c81b4ee259d826f0f	1611327407000000	1611932207000000	1675004207000000	1769612207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	202
\\xf98585f4acef98e54d067c5f133f87ed5851b5ecaab6e78f0ebd4711c1f053857d7e0cb66578189e35de3d5ffb34ab0f119557d39e24faa90599b24500b6f3a9	\\x00800003b900a58e5d7a7280ae7ad5711bbf291da6ceb9496b56e24b8efedcbd27bb1839a304b131dbd186aea3b06acb568ff423463553cd2eec575a562381ce05220d142cbbbcde48f8d7ea15cbee2dac606eb73a6eaec7432d66616925c0cc38db4503ed29863b0d7bee60e6ecb196f9d2918ebcc98256c907bdfe60de62afb4193dd5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xec9268e6ac9906cd21a4dbee96320e92a94062af48f8e49338410fe4b27fe170562e1167da90f55a95b8a068321e6f7a8143e4a4e409dec2e26ef25e3c11140a	1624626407000000	1625231207000000	1688303207000000	1782911207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	203
\\xfa251afb1f807281a8dd371d17384adddef77004f72736befeaf35d78e79a7b6df9b299c095a18205af6c22c4a336ad2e224c234b85ce69d73d3451f08664216	\\x00800003c7e9bfe1a0f6da17598651c7769188d4c1483dc8382197f609ee6aec98b2bdb1593c499cbbd4e18c645e2726f839ff041d9f36d4d930c56b1100cdf9d0aa3d3bb331a954d1f486232022320cfb85a4b48675fa4d6a12798eb8f54d1f4f74943db665ceb25f0467bb02eee8f0ff05e9958602809847f3f1af60f1dc46fe739355010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x08b33df7624fddc1914e8da8945fb26c8ee8e6b74f3480dcc8359a5b565b105505d668881f8ba134e2b022f08118a3705bfbda1fa8113c30dceea6ccb849210f	1629462407000000	1630067207000000	1693139207000000	1787747207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	204
\\x0252eb5775a54b43d194a7cf58c6a20045fcd13a766c6e84ac0ee0fe947b987cb3debd03528783e48377f2f0b1e87f7656047c6ab1076ea9bb0cb5f043a32102	\\x00800003d0c5082cc91a5fd4cde4b2e2b0d1c9671461fe7cc2f61c4490f85eed9f1e2de518ed09a10893476d4e76acbdfff71eaea3cf14125db9b2364038ef54072dd15079b86030a6a70e16d61237518b4744782ae9ab2d8abff68ba7c8fb4d06247e1b38d0f64a02d7df4eb69ad792c2ef57f520b8989a46ae6cfb94210043ef8c8e2f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x961429721f01ad4b093dbc56f562449635d42ad18af1bdf564710633352989751cf0a2fb1adeb3855608c02d01f6f9c90fdb8c00a5107674b449f0c930c5d401	1613745407000000	1614350207000000	1677422207000000	1772030207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	205
\\x085a59c0f6842b9e864bfae70a564d7e4418c9d311cf55845247f156cfc48a8f96d2a0bfdb99934f8eb2638b669bf17e765b017e883b007524edbb760e3b55d2	\\x00800003cc6c563daf70f508c24ddd6d6c2ba0f0211347e4df9598d790c25ab87e1515a3a0d90fbda2ac540463be47be70c9621998f58ddb3163d8d245f3a4f5aa723cd9623f05ff2d1ffdb33cd18b5bb619d0fad06789cf97152e9ad53df0ecb4c0243d1e41971556d4d9f633bdd11a62fea1d9ff0d5d668726ab3653bbeaa058601edd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5a2a2ff30602c79217af448379cb07f35ae4fdf98554ad1834b1a1463246941df86c8b3fcac54a659f64287e47c2dc271b67360ba6271bfde8f5ae4f24a04b07	1628857907000000	1629462707000000	1692534707000000	1787142707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	206
\\x0b5270a8abb2e16f0172ded2e642dea2517ebcbcfb1b455522ac35434e4d95734a0e08d6126837ca472eba20a4ae0528ee5889373ad4f12fa419ecb3d4e8805c	\\x00800003a9794fc7e80dec3ec4bd29f5708d6182e045c9f501046f15f1b68094b50f1ebf15abff7f8b17531fa88cefbbdad7c799d8640b6ad9c1ff4c5839f3348bbf6e061e7ff2b66cc061676aafd618f0578449bb136cea80e034ac94fbb9218d31a78a65dab234960e494be3c2c0d4ab746e5f4d383929cc8b04364a2813aff3d4b385010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2f314657359b7cf3a4da10476a464ea9c54d1e7f66dc7c62d060288993460af409c1f8af5c15c161d584554a371d12524b1abe7273507f930d804af872a0ed0e	1619790407000000	1620395207000000	1683467207000000	1778075207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	207
\\x0e32d2dcc464515a0480b853044473fbbb3bb39c0f2ba63e6d1441179253ca41b79afc879c9c3287e206dbb50e1b97ed2a711a4ad9a08f69f77c0642e638781a	\\x00800003f37db2367c7302d43e0119537b118865cd091d3b0a4115712e8a75a3e9f3796cbaafa850287fcdeeb6986e75ab7197696a376a0f5049f23d764013e1187a24c5a6da3ae8c4060dcea73c8b277c972f2666f4209e90136c4a94ee842a829ba4cc691c1e550508b4dc252eccb16f84a3f6a36e8ce0e3de0b6234ad88e153d3f237010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8168fb7b72d63e15c487687c40e98ee4d5fe4ab61924f5cbfddaa2a66536b64e7beaa73b2a6a15f34f5011e03dec33890dc05c36d0a44645aed9c4d932cac000	1636716407000000	1637321207000000	1700393207000000	1795001207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	208
\\x0e42788760f5067d1b23a2355dee2b7858c7e0fa85dfe27989ff94fe88de07bf973d21994e33bff181beb3324a99b725ede92c7cf253661ee44305a360e53d15	\\x00800003b787562657dc5c12be3993998edc05d833ede81ffbc329a48b05a6338cf22973eb7217998b6e6f1c3707b88f87049f80d2f39ba21be81767563840eaa8f7401f54fb719897928754ede6b4ba1a558ceed6155cf66279e895751c01a9e5709ec9aacebbaafbc0720f3f8aad26e5e92716af1883ebabb32dcf4890ac64e96ebb23010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc527c18bff5408c39559bf9a611c186901d43f4085f12051ccda5fa1387e5b4dd2a5be09b9145a9565979eab30c9dae8fa9f73dfbc1c5cfd91c701a2cca8c50a	1615558907000000	1616163707000000	1679235707000000	1773843707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	209
\\x0fbae49383cc3fd5c8e68ef485ee5a0cf81ee198a93fac8d07cb74729fa1679c13ae55c51637c9bff68f9975385c4872539a9650a8e665293a7a625f80435d12	\\x00800003e2823a79e711236e9f427b867903b24a51ef3f66b980cfc8401fbe80e05772c5e3bc72b288fc995e3bc596776e4b3c8c0230aa40427f920e56c489b27df0dd1f953066de23f2cb730d9efe9ab0ef78a07ea5c4ddc83573f56a9f704efbb0f83fb41cd888dae5cae8b6f348b697a2d2f068d6fec7c149a684be5b0a7f3478aff3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x61c78fa0ddccdf2fc090fad6617745d78bc82666bbe02fa3c05cb5a42af30aac47944a4ad9101f80f53bf4e3a97e995a3cbe0eea146acf2396ceb8bb22108902	1622208407000000	1622813207000000	1685885207000000	1780493207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	210
\\x105ae234cd61bd1b73f878e87fbf88ec2bcdbdd3f64065349a4aa1605d9662b554865373d619355ea2576ab861cef10168425f95969380f8e829bae574ad2248	\\x00800003bb13f03622f61559e568eb65574c0ca44e52ae714e485dc207e702382c91076c442908a44aecfe28989385f0b2b9cc2963be911c8b733d11ba15ecb8c9aa880df8e8bb5240ff9d7f17f7583ce13ad183fcb8a26f63553f88c3cb597f4b8f5e35e3123bbd79efc9ffbfffffba4db7e1572ac404a08c1e0e0a641ff3d9998c92f3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3aac921749bb6d7579beaa58aa40e2c4cbb59b0127ed6cea1e045560a65dd4d4647423e874c6c9ade4c43fc213865af53780419ac82c0252e792ddc3c6093108	1630066907000000	1630671707000000	1693743707000000	1788351707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	211
\\x13b27954a6784f45b49e9ddaf07a8a3c4e38efda0d9ba0ae53af2c0a9a7777561a507a48396a498074adbbc97674e5642e189a4f5f0f911e9c62784f8140d4fd	\\x00800003cc5078e6d3994275fe80499d4a09b2bb5a67283f2594fcfa362890abf8a2b036b7f6e46e231c95a73c2a4a69c9c4c14933fb58a4f638c6c0d1422fe134a3e01ee2338137af66549c2b48bd59b15c92f6cc9150837b9fa7485346dbe1d5c6d5cbc4ef7f897a0a97bc7e337a3d350583ab33ba5e99f5696fdf65b51ef68f9b8893010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x65bf02697d605031b666bf6555d3e08246e056ef3fc6bde82c393bf8b0291aa83ffb71cbe248da60f27784ab7b4ada7565d15db98cee4813fd3a416537dfa40f	1612536407000000	1613141207000000	1676213207000000	1770821207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	212
\\x13ce72c65d4768c4bd4b940a587a6e5f80e712eb3183f194f9b2b5f7913a413f6c4bdec57b894abaf280cff7718f50dad939bd8c0087147c71cb19967afae554	\\x00800003cab713795583cc638158868a87ff785cb6c413db9701ae343486dfdf8e4425743af83f16096ea33cd05ea1c1d8b96863e5b583ed4b242733cc20c4500e9be23f386543c25cb86a6e950615c56d53064c4e0b11669f435aac6a27ea3eae9a4a15dcebf2359acce8abaccab0fa20bf23419843a0824765cebddd56e905147380ad010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x21bd914ffaa07c697c7af052d723a152a9f457adb0d3b4868570ba4c122cd094a0cfa509f89da2ad718daed9b28e650ea666633b25a5efa0387b17d6a1e4190b	1624021907000000	1624626707000000	1687698707000000	1782306707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	213
\\x15a2bb24397043d5b1348312c775093b1161fdd2ac6f89e12c0cb201b531658572810bf1e22d0723f338c1620d3ad6ae99d18fc707ae9d0db273f2f22c7f31d5	\\x00800003d97736e86925db9ca46253da1c157ecd6d99576a271bfe144d3fcf944a5f5986096dde1dc915fdaf9d10b03601c39da72661e23e9050c686414633c2732d4e447ef0e13b95b9a486b758201c213221520785ddd7eb4c99f7b6ddb15f2d0289d86515d4f957b47f9f2d63ebbcd3e46c5e63ae07093356b4a481e27907de91ca15010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6031f7505e8d811f77126e929e730b889e7df7781cf481c828ca88fae529c8441334e8ea0c3f93c9a859a405fa83016030f3286c30312669a6857249e9b59509	1636716407000000	1637321207000000	1700393207000000	1795001207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	214
\\x161ee3bd599e70daca7be6a17882f3e5e7a544cef76e33de09d7dc7e10d3adf574721bc04ec7f5700ef23483f30ed979038ff46cc0c7e3ae92b7e6e8ddd8f5b3	\\x00800003c4cdde2b871f07cec06acdd8816201390846583b41f89893d968d535919cdc40e49fcd869ae5cdd38c971f6315039183321494d7048b1d302d6f90944fa5d2784703dbf8c61db14bcbc4f352eed78d6a8771855877cc2803452e92a71dbb5f659aedea4c97809292f0cffa818f6fdfa702afea551b9efb13fef5f42fea9703ff010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x79dce375dc8dd6ca35f6f2f4f46b1c19dd3ce3e3f358f1e71b391cfc2dc3261c9f9a6e6848ff14419aa776496a1e6625b090727018c7efaded09742f7ebc0408	1628857907000000	1629462707000000	1692534707000000	1787142707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	215
\\x16425f6ffee5442548af8079dc76f5bba270c40016c9719e8fef9ebdb0e65db769e72faa10e592635b0674fca9b4df31bf340f96faa3c5db4cf5be25403ea7d9	\\x00800003c9d376c061b22f2e13ec97f474b28ee406bb7d169c608b73a81d3eb024f92524be968155ab1598af0e84b5240d8ab56f4b3262291fd7007084d6ec62c2bed5f9d20653b04dd1c324cb9946d8795d6c3a08c55342e0b03eaa89765c85d01adec366e58e7b9fd5782b71e406e7fe06474d9dabe93c5512d518332667539eda1a3f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbc4d37983cd2428b814b7deaf488d32dd4383495a3a032bb4e14c9a3a0255d4eb06ca40ad503b39717569e576f34855c717cdbe1bcc4cd686720a10236130009	1632484907000000	1633089707000000	1696161707000000	1790769707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	216
\\x164a2028d524ea858f4bcb47fa454bfb3ccb2d8feefdb9a4099d2d9ed88e67a3069d58b88e0bc6761d77437f1343077f72a7e3d2f2c52aa5b59c57ed379ccf89	\\x00800003be24070067a87045181508a3c1dd9a98cf64c30c8736840b9c4557ff2cf13c7100f73afb809703b2573515c857d1d7a914bd2aa8ca201a80abb3850029e1eb6598ba85c171426d021032c509bf7d45460a46f9078ba4c2f0c68a54ad0e2e237dc6bb39ba35838523fab81ccbee1d308e7e6338e591f8d55ce434d6f78c6f3eef010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6c80ac22b7705210644f9cbcfcc3a263d7bfc250fdb466dd0c663035adc5c9b1b62e1d19fa64c8b192384c1bdd76cc72b567c97ac6585511e0c7c869e5fd9d07	1633089407000000	1633694207000000	1696766207000000	1791374207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	217
\\x173a95bc26cfcb58039065b9fbcba773e44e76b1ff7d59e5f1e3042833dc6915b7ce1d8395140f300eede27567df0b863a9bb16f92438654ea70dbbb1083b4e5	\\x00800003a879e30ac03d8ebdba7bc5a8df7828b6175215d13be05cc7ddde01a1f4817ed7a76faa660e303a948dfbb1273c5a0e48380a167ca8d3b4e2f40a0fa03e5f44c85551fe50eabf8d71581bc07426b01eb3a460aae4856a3f93db4f566de522433d55fb90f0aa76cff4549685f70b3aee6e72e13eaa60db3db147f68d38e91538d1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x21f32f420e21d422b6009d3fbe57f69c9664a25b7f2b39aea616b87e314965a1b85c28177b0f7ab1d605887f32afd5ccc7b5e43efa295d0a7caf1e0445aa6a04	1617976907000000	1618581707000000	1681653707000000	1776261707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	218
\\x1a16d73941588c4baa49c51e45c73750688930b8b9e60bb4c0a8d8a0dcd1de2375c109be3687ffba764abc3a2fc355df7f348dca186c5b0b6fa22716222a64ca	\\x00800003a1f0bae22295b81e4c6c30a57b75bece680930134fbe2d0386cabc51d64a039776d7c74745867631d88fcfe582ed3ea6b3d87f655ada09a2e58440b642b47cfa1e89cee2ea01df0a80185c3eda2398e4031a9f55f170a4a98a600359419d4448de85f01c30947b3adf21943a81ea77efeaf116293d4a015c871e2a75656c6aa9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3bb89800c20d76ce564d6b54cd076304278bba4d376457a1668e5c0ad2d729186b78782f8558464eeddfc289e6bb1a5ff095905f6d8d9974a5bde87a426bc80d	1626439907000000	1627044707000000	1690116707000000	1784724707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	219
\\x1af238044a342a2c4807faee1c39257bbaa441f052fe04cc1e780588536da03311d97151d746dfef52752e315a861207f23768dfdb57ffffb0777e749569bc36	\\x00800003b35a97034d994d75b0c42688dfbb658fc71e9b0fe1aa9b3712decf9c8f504cce377fcacb345855ded96f32867fc25668b7cdce5689299f1801d225b2371f9e02b7b45bf89e71735b95f9d4607fa467981900a6e727bfe128499b1efadd1de2b5e98a68834af7c03e5607fe20f95b529667b2ad4f3bb0aedb365faea479ef97f5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x45613cff76b2df81c1cbd0336e191a421bed2450181354dc1a3e7f9303b2003bd75b4fc2b08120d4db389f7cf8979bca6f29d2605311bbb3799200c43fb7e803	1618581407000000	1619186207000000	1682258207000000	1776866207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	220
\\x1d06030689c85537abd734df5a81010294e841920a121100e1d72d50798ece144fec86a468386f724a66568b1b32c443c63cfcd5cbbd5bdf77927bf7e03d9255	\\x00800003b9c8e106c0ad3c36404dbb721f0939a4557e7639091964d7312c86a67c0be8f29e83f471f5a19b5a9299a91f1c6ac0cb52813de249b27ff9da8728271246448d5357b0874786da3a3cf9085166dd2f8ea119bc8f0d26cb323bc4f4a9a02c20eece2e616116c155682fa0de2a18f9238452fd028c58db0bbc6a50ed741b385969010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbff9bc09af775382c28b2c33e87b82a9d54bf60142b8ca57c56c78f227ee19c72dcd280e1e0e3f90a8a8db46758832c67784677b7254723fc410ba17aeb7ed0c	1613745407000000	1614350207000000	1677422207000000	1772030207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	221
\\x1de251529702011aa33abf566125aae30ba6d933840f83e1d15eed6f2389464430e3e8370b21702eaa8d17e26c17f9d9ababb605f9674aed2b1cc46dddc9911b	\\x00800003c66b24ad206f718ce4822fab9050032219436086cbf69cffbbad3746fce7cb870f685cb74d9b34a75f664fe0b747ea1104796cf4612a22f4435a6eaf4949e01b445e99c7ecbb325739c2be6327dcae6834c69f3574f4d9b59efac2d6a6a6488f9f50ef5682d593dcc965a05e45ab04b12cc6ff00eea5b48112c38c9ad087b6bd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd8155baa6216e82850925e47cf19a564e179cf70fc025f7f8d01a00da10feb1b1d03c4562798cc85a5101216f8252f2fb3c90163e3ec8bec675354eedc86b309	1614349907000000	1614954707000000	1678026707000000	1772634707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	222
\\x1d6a8cd94fc1d9bbc9ae8acdf37774adda78584093fa9e3559d1b47572093f8e05796e3aebe2d8ba8b236d3fbd99a2a841e5b56e64f55c345d580300723e6dfd	\\x00800003ce6878e54f74cc3e483acb601d1a33bce25f6f90808685f3a4b6769cf5bfb3aa2c7985a5e8f880ef6dd0b17d4933f9a508729866afe019280e9f8c9a880cff7add13f979d767b6ca3eba63ae46de8df00c85b2812c93fcdc1fde2f08219d7673c9ceafb84d76a9e7bd0ac179c0d1ee2226fc61dcc6eb1ae4ca9c5df724f03767010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb184855c7912b55016107575786bed1ef6bb0cafe992bf7a998dcb780f7823b227cf07d4ad96f89d90c54a3dfdeb51e91444438fafd0dedae441035e7226600d	1624626407000000	1625231207000000	1688303207000000	1782911207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	223
\\x29028d35a5b57f646fd6799e0cbee1b0bbd18b3334e4244da3b1b84482ee91744bd0f126bb5dcaeb2eaa947c71ff1686de57e07ddddf5f7c8d28120e91a44786	\\x00800003a821ad7ac2c7bbebb58e3e91d072627103be480753511854389b9983a654f5658d8dc1b966d49a6e20ba0c951ad355a2d3eea88a7a18f417f6fe256e65027dd1bf647d3f4026957279b54bce4b1d30447062f053d0a84ccc4b684cceb0b7972914e66b8d56ba1e589ba755234ac651e27de47ebc44e1c40fc86e3177ad05c583010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd2302e412264a59c7a7b6eb1097f21fbdc563632e3dd1f55c9331c584b44d09177efac6d8b8454d7e9362a383da0b8123b6e658683e51b4828b30390c4d97d03	1628253407000000	1628858207000000	1691930207000000	1786538207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	224
\\x2cceac66f48ba1a5d227a1d22e6294d9bf15b1b0818cca740a3fecc9d0bc562190b0fd1d8247b532d6690078ba5118e325909493a24ad2f7d06b770b559f872a	\\x00800003a1339fd80c03e3211aec9bf33aeef310149c1925abbb928700c77aaa941f53ff7d10425e8fef0893dfcdf7a24a0651b0fde8d2bf4b572aa3e84274b0eebe8429ff45661bfc2ecc0d6cb06139d73aa41f71406360065319acf0bf88c9c4e84dde762910f1722882078fa66e781193848855182efdd96cafa76a1a5f616f6b3785010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfd80cdcf8c3befd11e47ff0ea6d2df70a94e20b804b64177314a744aeac15e2688b7344ee95f39ae3baee2972a0910daa951181bddef5ab0526e6f1f2a61c60f	1623417407000000	1624022207000000	1687094207000000	1781702207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	225
\\x2da6260af0f5ddc361886c13a7095d6e3d991aae541c14cb9adc0e63c04c7b3220bf3e08323105ac2c7582869f345707e157da6e05fe5ec7b1aafac23c545996	\\x00800003bee0b708ca918471fa491aed9ccb00e4e3a2fff39ce84722a2c58ce5c31f0b6c5f7b596b578a3125e585cb2b7737ebaae49832b1934890339a9ada702063f15fe9ba428f1bf2414cfe81879f5db2ffa4089c6f74e30965abeebfedb460abce5bbab5a8d9765bd06fb0573c92320b143f3b2563501b1081dd2fbcd99e7f911c29010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8a8b3af96f6343f517a06e8c7c1350b7947cdcfbfd559eacaa90983dc03e0c9ac67e72327b17e321cd6a00073ba52609d79b9caf226b8dd370147082abd16a0a	1615558907000000	1616163707000000	1679235707000000	1773843707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	226
\\x2fdaf197579286f5c5cf65107ef84465f68a03c7690f2bd62ec9d6a5a88817cb4ce50a55b4b5cd58badc95c1da309ec555523624d4c1a0c81a387a7cb9f0049d	\\x00800003c5ec2dd7589b7a166f2502a773292f8a82e4fa5938c239bf2b23666f7e26762745679f8e0954efe39dd97b3805c1671828e9bba2a21379b1b6db0a94898c489aa5c3f2a7cd357fa780f8e4af54056ffee723e3dc8b10c87c48bb559a39a1b76b776775aa94c14d4d865f24976e88be1b56b52ab67623a8bac5d49bcf27f20513010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0b3cffa2144b1e0373e0bb3ef7eb81eede4e1bcda6ce1f02da86433ff79dd9230a72ea3a6228409d3407ccd23b13a9dec9f0a3a6d1901af1ab75de9007855903	1630671407000000	1631276207000000	1694348207000000	1788956207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	227
\\x30a64de2bcf5ff22d0414eb5246d5e26eebb0b2dfd973b5391e579c949a4fa1f1e37c90ee4deac083362af9d05290d4e81674886518c4d83c46ac5a462559a66	\\x00800003d1d8c1b9fc1bc80a317b3eb95f8c0429d974789d82c667638d4e03539aa0602caab5e597555cc999b2ab05e4d0de8dfde5a7f241f746483cecd4dda431fc238accc53fdb8a2b912eafdf60478adff3a3263732e2134f1fd9856ff3cdc3af4837dc54683486a5ffd63100e12cdc04ef5bbfbef8398cb429ab1e3915f61b2b5f65010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb4ee2c385b3ee306dde595b11dbbe7279fcd372ecb76eebafa8da9fb886bcf5e8a68d8952b576d58c50be26b778ddc8de5b6e90466f83abf55e90b95ae078908	1639134407000000	1639739207000000	1702811207000000	1797419207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	228
\\x34120f89961e59e5ee0a46687a5f0b17b60583b10490142fb0baf08279d2bff32aebf0baab8e3d9d35e417fb73ae2aec7472a0b345d69d9438845eeb4fb9c251	\\x00800003a57ffe5c8cf6a78133a822c284c991b90446d8b18ca566c30eb746a02f0cde180a11856ed130f8d1e54247b572bde291086749a28488bec1aef60783a8a8338f9c76023cd429971556fef1e9e6581ed34ec427c0d207f95c74c23589e6e3e76b275b0ee0cf76274dcd7436a164ea10d34770fb0ff79b1aa7f0f126a75e163cf9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x311a167909ae6576c8b7c80c5718552e44b9742a41b272a5dd27d1aa4a93915c281102d8610037a65d9b2c2530766e72889ca941f0e38d5f5a5b55543b9bf00f	1616163407000000	1616768207000000	1679840207000000	1774448207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	229
\\x341ad6080c6bc289b75acc11dcd4b94f5eafbb26df66022ba1ddef37dd1138349380723675fa8cce2d99f6ad8ebaed8bd9e545173efffc02bcb11d0e88eb4c9d	\\x00800003ce6987a17e7c554e56aeda155745c9b0dbf9458cd76edf4e3c5eeac3d1e980ec0e80023f1c06aad6bae73c1fc0065e49810112c3f8e63db2a6f99c8030046baeb3261915baaeb5931a3917afb2db03d2dd31755bf3cff489224ac3c9edcd27a8dc1fed30d8d5bee388170d481db7358c750acb24cd399309253f4c0885a527b1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb7035264796a232cc1f27cd14f05c9eccf50f86bff64939bc695812bbbc5f3b7c10e760f8cf988eb96cf26399576b7be990f7677c65e1ada2e14421ffb47520d	1611327407000000	1611932207000000	1675004207000000	1769612207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	230
\\x351631f10407ea197ad3828697c59842d07f8e9001efd64bb6c55eaa6fc6e3ffb41948c82e14d5720d4aefb78bdc732c3fffb95d7633c68ead67d25126f8c9ad	\\x00800003baea6a95a33baa1b0e29c9a1398eb7d5a4c85d425a524728b49f4c4ea6ed9814d75e82ddf8c726a4aec00526be2a9e29ab53a7f5e46306752767ab48e3554d5530469d5b2ae33a33b6d13a87d751e0e5d76ddeb9cc678dfea66ea49b72a3cbfdb90bbb36630eefa69f397bd89471cfb415f1b4551559449ec298ffb9101654f3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x71bceb48fbd65c48649ab53b02724ef6e94af5d0d5f0cba214eb7cddad49c83b18081d897832eb9d0c9521062941cda6c47b7a18afc60527fc6cc4be45478909	1612536407000000	1613141207000000	1676213207000000	1770821207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	231
\\x35eaafe30bd19ac40ead0b51d50c2ff489506197285859e37dc5f9198a4909b61152492e027af49e0bd2f5c351b6025fef9c2d931a79ac5222c2cbbac8428409	\\x00800003ca467dc414c618ce35dca7268fbfef7957a934babad9cd1f7c581f7bf342020713d0ceecd82792b00643ea2dc32414c6349b9802e1f72942f5daa48dd21bc61d74c1e56451779eba4626573586fd1e31dc9a89cf9f178ac08810230d86b33410c781666b2e8ef09ba36ed6e8c7f6aec2fd9fd5b43dcb67540de1fb92d81e2ad1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcda0949e2783c437ce13bc746186276e286f1e56b8d7054fa62feecc3c7573cd78cd362452b0f046f370887984941d74a9e0e629497d168ed4fc9de6f2e6c800	1634902907000000	1635507707000000	1698579707000000	1793187707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	232
\\x3542cb7ed2413eecd2d582c277c684384cd0885c6cb2685fd5293e2a3b63ed8cd5db52dada3e2eb7cca12eade8f647ca5cf46f620f6beb131f3f8b05f5199824	\\x00800003b47eb844252f730c908c53570665812bff12173f89523a588b889facadd8034b55cc284998d1604f0ec3bb7f8a4f5d78aa0607a5458c694662ee77a384f7cb6e0a3ce90bdc091ef8f9ada7993c5f442f6a4823ed2d1499704b137a9de43a585de64b9886bad6ac5adec3166b49d08b4ec170fb24715a425d5c205452eeaf4ac3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3e8178740bb33c44779589f2640510ec40afafe4b859df08203882c60369b478f6af4033b24ba53e31bebf5de6618ed056fb0d9244735ab4d7c72e2fa3591902	1616163407000000	1616768207000000	1679840207000000	1774448207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	233
\\x364625eeb9b0bbc8354b0e6efb2831b29022db35b50bca7e1a7a5fc226ba6ba6fa13d0e91b1efa373a5b852031b6b4cce06025f58596826dc61608e6a8657815	\\x00800003f238f8403c51e55420a5b7b7a086fdc6f913f8181a2ebb3c39d3387ce868bf441d61fd221abe16bec2feb59df58854e4501fba4bfd35385926ea02dccb2d6d299e7e24ef67f56aa44ea1b836da900f5e651afed6f6ff5ff6cc60f3011db0b3126aeb53d19f8029fa921b1e994e9c48b400c111fdf9d6671dd4c2a337398c73a9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa0ba4c279d20d0201c49f6f885bf9e99263c1a1f73ce9b7e920960a5349bb74040f5e353292a276c41c459ec64322ddade2755433d0220561b56f9c4176d900c	1627044407000000	1627649207000000	1690721207000000	1785329207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	234
\\x36eab07b233f106df58683bee4cf24975eaa55351db7eb6968f5b2f69bc650dc9a450e682164f1d41a788ceef5d00660692fbaa784839a8edc2987404f359e82	\\x00800003cb403aceb0fe9e1d199958fb750c2d2116d03480271d70595d2a90a7a6dc262ffdd1f53cc84aba3f99061a8931924f08c658f3bb38ee6c1ebced89f4389db15d8b895c5b4d2f8db270f18f7b4e272baaaf2c9ab60150088451ffce79da0f84ae546a99d5aa1422dec17c451e231a2a8e8087df9ffcf0e45adf331d5b3f83bdab010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xff4b2796ef7b9a76cc5c28f2fc429c4f625bae87b868640430c946f9d972f4d8ff0e6bbd702c4c025cd205b875c30ae3ed5b416d6aca6d635d636fde867be20e	1624626407000000	1625231207000000	1688303207000000	1782911207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	235
\\x3752aab9ebe10104a623870ee19c03e53779923c22af675687378df9d529be236e93eefdc7e2937b98732401651777e3c6e01a5687b76ac15473fa2edb0dfdca	\\x00800003b553547fb6d48f354f8d9f6f4d602099006b6f99df8ed7998522e2ad7181541c72cc2b84e6de3b79704cf6f8637c8bd7ede64eab3b74ce0c4f4ce1654b6637136f015209fa45f33b97dec7a6ec2f71a9cd942d526a4bad0aa302b385a719be07b5660c2f9ca2fe6fc8d2d7d1b43c5322332f72a53b6b13ccbdd429cf1fcfa725010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xed7f918cb8f370817a7925517d9cd182cbc260e98326064c4330c6a999e109a322e7623c2fcdf597a0b4d90f8c28957d4c2630feb994dc606f5122bc26ee760b	1617372407000000	1617977207000000	1681049207000000	1775657207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	236
\\x39d60a537e79a21a0e83dc407fa9d27c918bf9bc28ea22616c2ded3833c48f33b4be93113f749e704336d8803d03b586d960a924c8102086e4cb959423c9b4d5	\\x00800003c668d2c117cc30e9ae0f19bcdb51749766c7f051bab22e3b234256e94ab50c7c08fcecd113827dccc4d07d0d010b369befb6874d423f485253d2ce1e080feef68063340e8f33e82f653029002e6d7798e98d6941df08fb77986d1695086e5ebe9d748c44d487a9950c7a637f04fdd2d291a3f63516dfc17f5023e1a6cf547f25010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x80430acd621b7889dca8d0286ec89b0a89693902fac0a5915691021448f0bc17e9405a3062f7f150c0bb2f6bb74eea4934f96ce8857e830c45267db00812430d	1633089407000000	1633694207000000	1696766207000000	1791374207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	237
\\x3c162055868fb0e7167e437ba7235e48898032e763d3d406267ff672e49048dcdc93abd26fcd0bac469598e433398251bc00e82afe7ced7fcd57a1fea6698fa4	\\x00800003bf4143caebaeeb15a03bcf08bce952e0f8ed435d78450bc0c19e244c0586e1bfce52d0dfdf544533687c9249c0841a47fdfc5cfdb8ebc86e4901383874b7293671daa36c77be4c9477a592a74b13c67ea2d50a2b1972496d548cc136484eb3d669501810bed07648e0f7cff32c866e466ba92caad48526ddcc83b13990c40601010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x834c917c4eb5b49ab40a48afd8d3a815fb28450792a18909a3465327cc3ac6f11fd1b8db4042697d02bf892a0d8422d676f6223f5a459169e7d4d512af8abc09	1610722907000000	1611327707000000	1674399707000000	1769007707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	238
\\x3ececdb1915bf0adc4313189ad21950b8b747796ad4535866792a4ef8878756ab617efa2f42428a998681cad4e0785efbce0133a8bdcf5868d333549c0de6373	\\x00800003e1385f4ab8acde3c98733ecfd1812f19b7e0776d94017e31eee58e153441c1f8cbbd26860ab0b23615d7918c26142c6cae3f7f7c0fbc323f1a7f5f7d220c7dec5672bf2bb6df482008ba2372bf0e086c3baca7466347ed5334b4f495a9fdd379cc6b8d66e879b05b87a12982e2385546ab8cd076a5470fd20d67a16b150204eb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4dc8d22344a0ca612145b1188ae3999d2e95d7795c01bdeaa36154ffed2e695909122760dcef92fda10be5f861e6901c04bd33083e87217e08ed359ab8e47507	1622812907000000	1623417707000000	1686489707000000	1781097707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	239
\\x429a6912b409f45ea3f0eac4c4b81f45084067507b7b065c0adc7f90bbcc4cc43b4c1fa29aa2d37a2b7102f81fd8bd4fc0475d1274d327f18528805a2e896254	\\x00800003b88789b8347a82979efd9321ade2a5a4f07b74a4ec91dc860695ad1172d342f64bfe3599bc59f8f1c7e3ed7b1eb190a2227e94c9dbd2ba853fa325df39ca6e0ec2afde5a7c129608abc5685a52933b919bb9dfb7960eeae594ed67c4e562ad0fb225ce77ec82777f59da3f538d1cdcbded1175068524636cd808d92e9281d25b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2d58cce26347ab75c1dfaa8eee62e710f164df435b1b695b9137a171268192f5e1cb209fa38023cc39386ea8f3eed4bb71b5add057f95915aae17a8b18018c08	1634298407000000	1634903207000000	1697975207000000	1792583207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	240
\\x49ae56423757a8ecbb2b676c0cd8bb6b20c8f407af85e1eb00b15d7ecbc691287e47701133b151f6c77cf9ee921d7c2ba02bb09cc69b740cb8c8f59a78c8c4fe	\\x00800003bf2049ade962ef375d86efe4c640b79575040b973d705708ac0f23d7e99ec4705d875e1924201cbb95f3a2c6ec19f94b5f87c0c1d8615e3a22918fb59baf7b33857b8acc631a667d80b88392e8f09ef4031de0dd16091a5a7e9491b44578a9d94f5387a3b78ebddced14b4e6e8ca245ed54d9a9cc55e7a8b96c4df8fee7d50e7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x77de8e1e34272a652fd00d65ee461617fef794dd7d44d0215ffcbe525656a0f5869741b8d2ba65ff32cc76a6ecd99ce02fa561be459c2790ff6f26392e63e002	1611327407000000	1611932207000000	1675004207000000	1769612207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	241
\\x4f86a5be0acc23cecafaa7b47725a5319acbcbbf656eef3056a670cde40ee0eb3753ce4039f47f6cffa6e8ee2878d1943d03e666229a9caded482e25618c9dd3	\\x00800003c167a517210e178387254992743d6efca86d8e451d7320e43fb689928a7b5c64ee24bd79d8aee476494c863ad68492f5b25646a0351b91582864e6aade590b46553306305a6a0ef4e17f92ddb56bd1fc6f1a78c322e48cf75f61f0ad32c203ad1a6cbc3cc4ce9397d7c79d2f4bac88a8e6c1d6ba0199625d337eb07b880fc74f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf88cbd580976bf0bec6dd1872e1d777d5f2d7c1c35c357b7c60f2a7dcf1e8236aa6a2bae907e50f01abafeb0611f5b82c35fcc1cd41f73f1cde4593c31259304	1625230907000000	1625835707000000	1688907707000000	1783515707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	242
\\x50764fd7a4887c468d152d4381c7908bad8ea71e10a043c95dc11b47e7915711aa23d3a4226292f53ec4dfd7ed98f5b391d229b7c26e513d912c4a245e4ec14d	\\x00800003b793a8c47138dc9ce1a011415fbbca065707b2a5cea56054c328951314e4bb91c6fe52cbd1bfde0eb5d458f4e90d494a2848728a454b865a1220cdbdafcb9fee380874838a8dd6e5cc22dfaa7fedf953e1fb4ed21e7bc2486e915fdf72b655697fa5c2330b877416083fa0fa58daed356864a4a52d8ec623b716c7ea35c0a791010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd91e07b25069f3dfebe198b3fa2069e9053d53094420032eeb27d27ce526e36ef5854746779e9e0c1689a5f5c135cd7556160b28aa41eb70eea973c0c2733500	1634298407000000	1634903207000000	1697975207000000	1792583207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x50524a7ad287e84566b9a7f9aa93631fc870724249cd63c9cde047b01888520f565c29dff864166d8e41fc2fe3bfc323c7d802e8eb423a9e6e004aafdea88610	\\x00800003a295814fd688a4672ccb05ce3cda8a5792d69afd475898a479ab6596e89cad8336fd293b42eab8198d1783fadc952d166e111b010c79747a6fbd58e42791a8805ce1e41042a968318de4240b3a8166b7f02ccdd8374dbaea3f588b2ce7326377890007161ace447f942cdd953a02ea03e3a5f0854254307f30c2eb06854b9a8d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x21e87a488cdbf78fa21b75d11ccb6675787f6d3e56b30d33701e43aca4c3ea2867219bd8b00ceb65b71ba073f1fd9aefcca03217dd407555a73e91832d01150b	1631275907000000	1631880707000000	1694952707000000	1789560707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	244
\\x5216acafea12fffd106d4ee3e716080981a624d2b20c28ab1b9e4c1a9e65f406977291d245ab453b23bbcdd66b0c25f90f0a7b0c88ca5d473a54105348f95300	\\x00800003c5ee4c0863010af32e26884219c9bab1da64af1da955fa2d2b475e57226e1b4e173b4a26714143cb2edc5b5648f8976424182e7fb495f7c949f9522bfbbb405f2ce23d7ee962a6b3bd05aaecd9fa3ef011c792761ece2291377fb82e010973f8ee92193880ff99c484ee0f4a09153e8422e52b64cc99feeb42741c1942e879b1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcd50a30478a194d209c488d1ddd93df92af156719320a7797851c9551aa8ec8a2ae15b719c1c1583c6d25de4c3d5f7a2fa6aee068616cc90c44642909e20cb08	1628857907000000	1629462707000000	1692534707000000	1787142707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	245
\\x530ebc15dfb3fdc552e2613fd9846287e85bd4c465ca4d5d05f4567ae937e5a7a1517efcfc54e2147b29486d0022d7a443765e7214d5fc2941fc6ec6548c5441	\\x00800003e50be6e213b68677c7be8c513621a3027940b96d381feede04da9f246f308b895df6eee5f4010813234af405f73ef46ae8c23030e4c6baafa937ad55d7bacd0c17d2cb05bb7e10326b534968604017b605f72666911944d2d20bb2b590461925c7dd3159912985e3397e7ad5b133a6ad8c4a8a762380b3119d1f1503f44bcf1d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x62f5c6a7c07bca1130f3e9e59ede7c7ea8065e773ac6dccf9a0f094de16c194ae76e6893ce5b99dd7b4533a94d9835d052b8bebc0a54ff1a6dfaf04a02d50404	1639738907000000	1640343707000000	1703415707000000	1798023707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	246
\\x572236c7582b65e7382d5e2684005e69e4af0eddce659a3591785a7a6aadcace0973aba1334057b4eb6a4947304cebf38dc788f7cc8ad39a0bef1dd569758e92	\\x00800003be433df79e9f222f06d1d920e6c24f3986ca254ca60efb278022918c9cefdfa52b1f60890a0c52d9e2b82387c115be6288eae9f2b8e5a30259384492c4ad68a4bed984b157ee966e6e14986a523bfb4b2e308f6a99a074c9f61fbf11ce03a9f62e38481b986b52cf98d127a4d44bc0ebec23763d7edd5ff4260f04aabd070319010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x997e211ad033b418834aa4375c2a7c2a413f299c4ef7be6ba179daea4fdd6165ff35f15aa00df116242b32886bf6df01e25a84f8669a42688c70ce2bab57590e	1627648907000000	1628253707000000	1691325707000000	1785933707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	247
\\x58b61087821fdb0004a448159055e43e61b15cd3541a44b7b663bc9c500e5b47b79b03e14378257bde97babdc97993e75a8420261bd7d1d7551c5584dd012eb8	\\x00800003b08bf70b7dacbcdd5289a9725a792987cc6788cb2818eb39aef7a654395e3e25e3f118f9928dd3d5276c16b1ee451b6a1a875aec285d1aea5aecdf63289fc1f4035efff143347121d884060c8af1ab8183f483d9ef3cc0c4bac2cdfe441efbda0cceba441de7b9f2703b9236547ef7020eddccbae64ae8bf861241597af29bab010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd52fc8e87e775b92a55a4854978412058031b1f070ab708356515f2f273f677c58a02d9001a80f362519ca66b64a3df8f5e1758e411bd016aef403e2acc36308	1637925407000000	1638530207000000	1701602207000000	1796210207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	248
\\x5a22b9ad5e2fca76f516f9f4b75b4ab066ffd1adfaf918cb26137b6b00dd4c00da0224792aefc797f0252697711ae6599c1af40d3dc522643bd545c45c1bcf4c	\\x00800003a98a5ae789560ca30bd784d9d97a87ca7434c1a670cd8c39dd99b9f27e06e6b37a0807f30ef87f2f21e217989dd9250fa99069995d8d3ee14c77cfd5ebe47ee61b4a5774a5e09d31e8b085eb8ed3e9f59c6519f030e3a6b887ec75e75e908d3691e2c0af52d3d51b7e97514c599a263e2f74aa2e56737fb6403306401517a297010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x876b02cc1ebcb7aa99515935352da94b183f8c10a556fd7c006b4fa506b43965203a6eb39a39d9ffdabe96633ab2683a15cd80ed199487ab2163132005a6390a	1617976907000000	1618581707000000	1681653707000000	1776261707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	249
\\x5ba6bbd8eadc4da5af876cbc85e0a7d4885b941b706e5f7de2b1b88abe3bc577a8808f748a59ea0ae6c998dd94d3b105b2694abb720225fd8c0b99f3bcda57bf	\\x00800003bf54743d40f240aea2627eb0715ed8483b13ea68a7eea9b215a4b67475959e3576828a770f439e885154b9a47a486f5cab6a31dc1393ad0fde505fba263e2140af6476cba54b320b1cc456078e111cce0a31a0cdfacea907c536e7d676942ff6d508319ff73650dfc40e9ef6fd2feaf931d206650fd143dc6078e792968e5757010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfe3a1c226403ab242261aa17ab10964fd247c9eee050fa1e9b92c6eb56a079dc13598797208eafafdce656ce73dbce519675cbd8e2040e5aae6643772a7d8608	1640947907000000	1641552707000000	1704624707000000	1799232707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	250
\\x5c2ea579c3ea2828c36bca8991cb69dc67737f93d8e19faaa2b6384fd37f1b15278d6d164ff5e9c1ee8a296f453460e06360d582aa4bf949f0f3ad74fdb4cf67	\\x00800003bdcad4df840e969e0d947b6d96a918c7cca4d1ba86d3ba7b78f2a72b463c0700bf3d2f62fdef6c178130b2a0e4c3e2d15d476be4f75359080a95289bad8c5f64273984dc1070e591d8e429a9629ca8c67d5ed8a13681c4a8c9271868dc1a3718f0a104924c77d25b96c93283190cba60ae02308a7ba7459f8fcf40dbfac34569010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x57333d6c594d461f37c367866a5891d54e2b3a426d2affa714041a41567b5d5a8f5b95927644f00fc60461a69db8dbd217fb77297a40227524499987e3912600	1626439907000000	1627044707000000	1690116707000000	1784724707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	251
\\x5df6c928ad1ffe16389d8b5796a170b48e2d1ff15e55a682393533621425c6f07ce0a4b239037489586e330b62ab584d701cae8e877815fb96f43e4ed9ffa4a1	\\x00800003a55713b724eaab45459ff54d13f18fb157a5c8653183726b0078d45165ee23bbaf91203efcb2d569f99051352a42ecd027e40564af8d00cefe21781b53444c2be45cff4cf198bc8a9a42308672eb2c3e6b4a839b52f50be2b14e8b8d1326511feca33b0c4088e91879fd42118f0ff0706203e65d14a5cb1e466ceb6a3a7c86a5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb8478d5862085354bd50baff71f4747b974c9552f0665bb821e7794484ee903174439d98d6309978b63dcd4725066dde47817991b4959089767337760fbbcb0b	1636111907000000	1636716707000000	1699788707000000	1794396707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	252
\\x600ef66f25e675e1941afeeb1ed931b1cecd42569a2fdbd0dc15e841082800995344b316db1d2cab4a84ce999f08d236a71955c7997010fe7339e877a3b586b6	\\x00800003db5d4652fba1812e0a1805ace7942d7e839d25557e1bc1b391b1ddef39599ac20ccd68b1af365a4503371d4c22107538e6064a86e2ba55d016b1389d64005f06819e048e0ac21446d963a2fe3529a8bc6a3f80fb9838e70691d721fbf73d8509c73ccd4a133871e96e3c63fda6520a4afd1087b4aadd520dd6076fe994bf1d75010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x961a90100229c630f351ffae01a286066a7bc6a8df5f52d6ef9e2cb3c101b97f62f144c0bb3d71af3bd9032847fc0e039f4cd6805487a1be5e9638557596b106	1631275907000000	1631880707000000	1694952707000000	1789560707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	253
\\x606ecf552453e7ae58de8387bccfabdedc333ca124e4ea413bba8a2cc267cff0529e7fc28fcb833d9ab33abb7917b0287a5d8d74eee1809e5cf1ef4e431a3da3	\\x00800003e6139ba08d4526a23b4ffb5be7d4d6e0ccfd33bf08ac0877783fbc155ca47094ef9a139c395a7a33452353f3d1e1551c277878619e6c27459d2c3d1d493ec16af35ae21fee4c92f08a1ee352481fc6542b2242f268eb16d0aef7122e2bed063ae31556f952e5e1a5b8b8fe3f1db03181bc3f4b7568885885c9f459c2a501cee7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf0eb79011185bc028b5a7fef521fabe7f6d2d831d2cb49e9e975648e286a0d416b4b544b40d6dbd9d184f860998afe166e697198c751dc637271e90aa6346006	1617372407000000	1617977207000000	1681049207000000	1775657207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	254
\\x63de6de51df3612be5e7551a849042ed219450b224b44cd9e130bac73a606082eb9b9a7693f7af1033cb3d6057e16b27e5ef6542adfd1feb58683464b6de91c1	\\x00800003c5ed6d4531067eef25ed6b1c663e0162f3a2f761e0c42557a1096d15ae5925406d7858c7a9676827a2f7fe680f052157c87382c52a018f3c467b63d02cfb02140b6d69c547d86f0d4ed06a47749e5faa60ef9ca60dc8460e85496482f7ba4ec5d4b84f64a6ab8a809889ae964be4bceac644fd64eae1f4d88a93da186a29c097010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xeb27dbf61c938ac9af1672aa4c1063af8ae4e27d45a946c63672a7a97837f9688dd3cbc41d4d2de68812cf0be10a4ba9cc18a4de3a07cd1dbd8da1f346c5a701	1618581407000000	1619186207000000	1682258207000000	1776866207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	255
\\x64960749a284aafb7a9842495e2839993c4a720d17ae00dcc8e1d32ca4b478ae91194a0dd734b2a9502b6941cb57ebeece9052d8d0c58c3061df3fe0bbda2f8e	\\x00800003b4402845fb2c13563bfca7755ed80ec96aaf111b55ca92e74c187aa552919e25cd8f55748851e98c96bfccd855aadaf49e0a2eabb709f6f5b7e2e61b8a8a61037bdfcdbac8334ce5138f018482282ab055c6b45e43db1e017b8720480d145431e64836a23ef8d709e644db225100e3468857e9b29d2793be6777d9090af57f07010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x34e33d21a155ed5b5e5e3f0313e7cf71f3301d42b30c3e919b9afb16f6312a900fe07cc011bd7b9a317e9ec9e43cdefc4ecfeb5cc71db357ea750d0d1158880f	1629462407000000	1630067207000000	1693139207000000	1787747207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	256
\\x670ed64e4095e679cd6086fd634cf7db34ab25a0d3024b55e9196b4fe84a79f461d3254d0efae501af90c5d61c0b0583fd86a1ea38485249be23729cb7848f17	\\x00800003b03b2e5f9b9c5f65f8501c885b63505ca1cd0af3b5dadf9a28632e52b97c4513c7fcf1b0bf64385b49a23954971072bc974cc0bd4545a3263e9ee10105a882038d42e96022a98f530610e4e7508532d754468fc554f2aa52710d985f7d8abd7b040f7963bd3e2aba5e52d6a717e6f771d30ac6819aec77d5dffa2ee94765a15f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4f016c5b81e26c1a5651297683a2c317a46820350029ccec4b6ad465dc4e31ad4caf2ecd127043c188089331d306cfd0d0b8ceee9c21c46093300c84e4df6007	1640947907000000	1641552707000000	1704624707000000	1799232707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	257
\\x6caed403271d14b354e107d766311fa02409642d213ad5066baf8f160ffe25253d1b9cdfff548542584209021b15be00c6f6a4e5f597ad448289ce64147e47f5	\\x00800003d0941dc80245cb1872a63e555957578095b0e912fc48827d7fad205dea17f3a31e463955148e1b07c31a617b2fbf38bbfc58bf2e92f204bf228845ff94ee7750f1585675fa307335cf070f28a14e13a1b5b086037cb8a1941591bd19ffa7ef99cf17cfa7084db2d2130c2b5b0c913cf65ede693a3853e6bd9887db1afb418491010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x991c4ebbb31e65c50613e1af9bafd360dcf5f3b427ec38be77a42d2c55b3850065e57e5e62aaaefb3745eca5590ba2e06b342d2e50b865e13973610df093fd0f	1631275907000000	1631880707000000	1694952707000000	1789560707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x708e5378e846561307116e51de4ba837574bc74763d8b8b92f463ebe075a16be57188a93c8ca50ebafdea884b8077d61788c635f454e398112f2a9fc87215d6c	\\x00800003d96164a7356f36b061f7e55a1c67bdd78f835121be441c03d78dcbf7d665b5d1fd5e334cbfdd7e28aebac963bd2da70a70591e6d2d0cd99198f1de65650e8b644dbeedc9862c3314bad263086f4d43bd55e3629e5d7128ca7e8c34979225e449d60e55b1b15f14818549e267e374f10b48572fa32176a0c5119909f0b92f7221010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf7ed14ba9a4bcce7fd8e5f773084c4d701022595d5b6dcc8434fecb576adb60e781009dd32c3a92e5fe606aa8712e3b5c69248252c3368e960ed591576dc390d	1619185907000000	1619790707000000	1682862707000000	1777470707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x7602bb68fc9c0e4fd00b1fae50f6529d5a771269a423832d7adacb6ff5c10adf7e1278590d3a8a169e911d0cd6de06942d43283ba25660b7739a74874d986326	\\x00800003ea1118a62d8813fbd5ca066b4320ad9dbebe0648dabfaa0d269a6b3a3168c44371c3b80104e16ed5113e87dedb30ae419075974ff30d3e4d1ab3ab3b50dcd4422fcf62ba23bd38a5ffa20371cc86bce18a746ed8b50610332c8024e2d272911dfda4e2287edbf1108f777333b4ed00ac6e6984e8e8e3d3ea0be538c949ab0703010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe276cea1ebac1ea57bddedfc804a874640eb1bc9c4fa9b9d981fad7706393f60ec4000c9bca2b1e248c3cbc3e6bfded471eddef02c5f9c03e0abfae87aebde07	1613140907000000	1613745707000000	1676817707000000	1771425707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x76ae827b8ae0a36d35ad388ffc742cc26d891a81ac27f84b48dc66f8b1d893a3eab45865ff292b00d90ce89bea2bf75cd26e1d5fd0f77a8ed2430f5f1db06247	\\x00800003e5b01b12594e9705b26b7323e25f9d12a7b53eb0084f59c2e347c27ffa83ba7b84663f3828b53bbbd1fbcd48aa905f31168aaebcc881afe647987e89faafed594fd8751b9f1af8d334476d08643dd937f64cbcd31cb9189297aaf9c0019ba0f733d06e72fcb05cfe3dc046ea7f141837368887f643b3d7cbd1573a2ff585e495010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf4e3877902744541074884aef8cab635d1a329da610303064ee89858bac5d8f76bb9d948f11bb67a9e80a411bbc5f6fbd5463877d43288b5a14b041037480c08	1636111907000000	1636716707000000	1699788707000000	1794396707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	261
\\x7afaf6112fcb61c25e77cbf97c18d22aad89aee06d5bc8180bcb20ea1716ddef5928fcd9000c47188d6518e66f0234dd129483986ad502f4e861ea68b1787bdc	\\x00800003d4219d4358a8423d348d5f5833a880059cffc1258eaec7808f8582ae7a2b0109877f7dcc38a9618292cb7f5136e409a2bd6c5cb5dd3e6bbabf9fbfef597986621c7ab0f548ccb0cff567971824d603fcdd3637111eed2ca1e0cbd141ff5ae871a37a9c94cf8f4f162830163df3188e51fa0c63409de8ee9f4ad2c5eac075abd3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4126dfeddab67a460df75144bfd249d04890698906abe8d73c632db4da5ace4b118a21c3a163229b452c42381f8b96b5dcf20560a5decb05eed35957ecbcc80f	1630671407000000	1631276207000000	1694348207000000	1788956207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	262
\\x7f020dae8c8c771d3d06f432ba1a56fcd2ded5eba6afb0c3e5ca02e5bc4707d7d21300eff2774998b976d260eb195d94d4408c5e215d84fc99678bf597213736	\\x00800003c6d56a02eabe47534e298d43f086a4fd58c888a934094df7d8d8a16b8aa92a1942d18d6a2bdbbc84076991173bbfccc85d72c1d0808b80472abd0ddc5b26b092046d2120982ebbfaef97e796f38171ca29f4e047c2f96bb834b3bedaadfa199ce93327e13ca9a4223d8fb75cfea6c3dc5677d45cce98ecc35487f5bda3aa5ddb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x55f071def97000fa2c926e16e737d4d7d9f2087591db42cdb621f14368c2a99e40947cd91e93f6a1de121522aa6b66c9ddf2ce07cfb688c434731df74bce890e	1614954407000000	1615559207000000	1678631207000000	1773239207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	263
\\x8066c9f083163f74a97e39ee29e1157817256fa93876341b398abada915779d7fbd703f1acb349bee243916d38e3422ce87eaf55d4764aafd141202dc2d45bde	\\x00800003a8bd56d0bc970c191b37c758c4a963e9dca2972e32b3333ee84237e960ba8584e7af199b0bb6d341cce1572ff2df99338687ecd28b4a9378e6f8323c3533b2283ca4a02939a02680e0f29c369018fe890716b84c89ed9866e30721ea574fda49e6e22ebd15f9465084feac2894158dcf228505c0fb9ab954eaa096c16e34ec3f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5b11f66c7615a7eee925114a29ab9bef47f47869717aac9d27d8ae6505e70a76ae06216eee9f68df498ee780576163bd410091030788168383fa56d86cd77907	1611931907000000	1612536707000000	1675608707000000	1770216707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	264
\\x86e6659f33b9f59e76474f50ff76450d13f161a379db47878803aedb649ca1e6e4e029acab5f0a73f5b3be1e9a8e42e79ef51e227e751509115688383ecc4fd1	\\x00800003a23e72d694605d0763f722cb3d291ad7ec35f3603cf56d93a98a3fbfbafeecbc6af9bd56a1a8fa19ef3c913e709f87956a96731b0ea46de3d2db91bedb3e872d5523057f2efbad6ae8a698e105be7c4bea3b5b41c7d3f38d0f160f699c0fbc2a1d46c8a54116f642cdffeab804bc9e23ed3bad653c0cfd325739fe3a23355a43010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xce7d507413fd0fb3fe7448108facc5180c4dc64a1072e3d8c33d7a879c905d1baf1430b5f6805a56a62178351fa77fd27b11a47282a647dde675ca4764c2790d	1610722907000000	1611327707000000	1674399707000000	1769007707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	265
\\x89463ba3c150da47b720f337368aa799e050d57280e2b3dfe1bbd25c416f8d4b3d5ff508f92f6e439074b0c886382524126a4741a0d01875de6de9444391cb37	\\x00800003dfab1c5ba00085ce533c82a6c8eb3170594839fb1c881f80bf2a0e31ac9f7eb0261acf2af1784d0ad8f1e8ffcc0b322b645f30a19093a9cb8911fb0eb7100e68e04657066e02bbf0bba98ab5815edda9407cba4ae373a299b7dc4ac3dc88b5d79a754d21b360ae853a749d8f4b69b6f0a423d955e26faf68faf996e5d3acab13010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5fe32cee37adfabc9a63a6e8e4fc7353d8333d4d6660d4cd495a1e32cf32881aef7c69df74bc982440733206c764f6d1e9d99527b5ae911d1babf660c0e9c901	1619185907000000	1619790707000000	1682862707000000	1777470707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	266
\\x90526332ebfcb94adb1078b5a5396d900d9e24fae0068b0e22119ad4b2aeadcc7cfca002fa521ba17fc242eaeb45367a17b6a4f450e52069f094c62018c0d8f5	\\x00800003c3528b058494ad8fc95b3eb69309bd38adb4aa1e94edf18fbb046cb9830c9f469ae6ea91d134fd5fb6c6e1d00a5e2232481b0386f71cf03b510c0aca4412955d62d8f4af95f283711e25109af9fcb524cc0a4562d1c8cd04e84758dafa1fd8fe5e6b9ffd8f6c52ff9e0ad6bec5fcb46ff08f0fcf08923a28fdfcd26ec5c24f35010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x70923f22845f68eb14545001adeb4ad6e0038d8d4713915d7b70a4a2289d0424a9e64d60ce220f46fb7a9883e6ec5affaa05bd8bfb0ea2ccc5d643b65b8fd700	1620394907000000	1620999707000000	1684071707000000	1778679707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	267
\\x9a9a7e1f18d7fd6bd82fb3dac2f3fb2466b6dd5bdeee6df4a2ab293279c2bba9570cff7574cdbdd1169bc9d9e58ceb5b642567c5455ee934970838c74dff99d0	\\x00800003a36ed1ea8e6128535099c53a9d29ee0c3f41ccab898f4d3c167f4367fc1548695243178bd452f181b648b7d4f22ae0fe955d404001b6ac91c3e697eae3b8cf05edf692acf49100b419091dd86c52eb4aa2c0691b62a906b01c9539f08f3f753d55889e210317434b0cf5cb21d2cbb35e8a87bf9e5acebe89706475bf239ca1ad010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbd93d668ee48226a6ee35784944a34cfab7c5d9f2d7d1021ffa1b61b289a7609013ea68c9526359ceef747ddbc98209a6d64ac9f00b31d926feff72c95afd303	1621603907000000	1622208707000000	1685280707000000	1779888707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x9bcabab2167ba67c52652bfe03887873a471a0d0d8ae6e055cb494a72edfc45a2c1da046ad0c752cef9402740f1d3b4d91369fe9d7d7b730310e84acc2360c4b	\\x00800003c1dfcc0e18fd63b4aab5ad8abeea624a6d05e0c5c3a043dae9b8ff7960420c12ee80a2271cfe75d6b3194cebb368d71ed1e5df7d1fa29af307109a1ab37377e48026154829eee76a76363f0635b5bd17c4164a486da28f224d21c09ed9f6b4d38d8a5fd6345dab8b9320f3332781ce92b76a6b960a83d55b27d520a9d02ba91b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xdef49b0d93adf44b99175938ae02e977fd8588b87ae6a4bff6a6d55a00b7c5fddd51353e318790ba633856997d7dffc58de459784888d675a78b6e9518a5c104	1640343407000000	1640948207000000	1704020207000000	1798628207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	269
\\x9c1aa5769c0c11bd71a00576bb84e9695061a0fac4903fa076e1bfb60151b43589c86ab4f83f0e2b40fbf59fdb2cea42501acc12a0ecee4a09c869695939e011	\\x00800003dbeb7382b907ad3a4117937977666c24f536ccce31d58a5e1cce16cb7a9da267093db3834c94a8f7250e674ed1e664e9fd6facc3640d720a76fbecec70a647c8ec4ce081f492927be46fafa9f8893e8a80908191c1403dd4b5bc9f5cba3705258ddfbfdbbe5b3fffb4aa68d293ff8eb7d85cad2fe8ff359038e0b8f789a082a3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xaae19480ee60324d4bba9fe53491433dcc1c010cc76fbe12dfe02ccf23626a3c49a123d77d9de56c63c0b68f26e8c311467bf1d1d0b64f4e2bee2961d8aa7203	1640343407000000	1640948207000000	1704020207000000	1798628207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	270
\\x9ebec68cecbc13b895e5cd285c4b7c311ce33eb34f6b727104c58b08908ae383db9c19af7be695ff473c3f95861b1efd3b47432ef0d200300027817a1404f056	\\x008000039c59d25b7b916b4a8321672f901b58fb231f8e0980e2bd9619ddd07273526ee73b2e9ce4a2da7b14733cb427e6f0d01861dad3728faced7303b18d9efdf22a8577351120d87b86b5dd2992a01efc37b3ce57bde3f7d6f4ab860677869e732b9a036b9873bf27c722d7c6df2a2e3b4f66db334576165e26b9429125a56b61bd01010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1dffc66b0ff48242050fe99126ac10d4dab85dc9ea5808a199a5a8906a2c95ad4da3b39113de8f07a6a244f8d688f2ab4b22174cf8088cb18a36e7903710020f	1610118407000000	1610723207000000	1673795207000000	1768403207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	271
\\xa1ee02aa528e4869aa0b35c9a64601b3be91c542b8f665f326c265229688ade22ac01db90c699a3aa2dbf0b3af421b63050ae1dd327bacec9cd674fa30425ab7	\\x00800003dad6b3f5f930e48b64dfb74470d739e8f70402dbc32cf3e130c4bd7af505b78c20d314c8908254240d6c4cb0b499ad507c969d0cfee063b339b5eaa37fa4d8bbc538227ac859842eb71018fcee3bfb2f3d4323b22c5c401aee0384cd4bcef8f4ed6f5e23e105f0be3c48407f1138279e3da05011a6b9c22e6ffb8a9a355b4d1b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2904a5fe935059b2fe066ec9c9788ac7984325673b400632577544c458bd5c3667c764f1a518a672db00a62eeaba99fc6e2ac188248954aa2d120ad141cadb01	1630671407000000	1631276207000000	1694348207000000	1788956207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	272
\\xa2de0eb2e322c7df7d4eaa2ee8160f5487dc7f6b99e77f8a2f721e6c78b70da18fccb51584cb9be086f32fe8a989d599192d61fe1fd28bc99a207e00b835eafe	\\x00800003cbde8c0040c52dcfeba6ecd2eccd67c3b14fa26084ba594f79dceac0ab17e14250d7a72cdc7a27a4e745fa354580dd273ce6fb9d7f4d84dcc192b3fb9714300c0895a296d6976833ccab795c96c1f68e299b92624abc3f903480fb7dddf2d15fc4923d6bed1658582da21cafe8afae400b8190ebee40ee344a3ca75f08de5cd3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x206412552fc51f090ed02212558521c0a59b5c5849a18ccf8ceef717aca2b1f3e625cdc47fd381dcae8e44280f5cb2d9658c6c1e65525320109865c018751c0a	1639738907000000	1640343707000000	1703415707000000	1798023707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	273
\\xa362bac99870807e5b6a04201861aa8155d2897d1a7912d1ac29fc337febdadef6288a52f988cbd79b651b57d341c5afde553778b833f4ae46a543d93fbbc139	\\x00800003ac57a1f9149990f79898c068b2b0be7726ea908565d89051fc4d32d7e3f45a3453ab0df27336f9d3fc37f128fc12c665f3db1d32d558a20715d802f1fe24956a50b4ac2586ea95b3685511502ac36a1383b2c045ecf4b02bd150cb2dbcf53c69b82a6b6edad4c3906d92ce178f60df2094ccab03c91897fe7444187c3924e82f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf5272c0119efb2aa358412e4163f7b2324c70bd4d7ba4370e30b49c65d4758bf5434775a5727748f44ff9f2e5676101c029ec00e3cced5bb275be08dd9c67209	1633089407000000	1633694207000000	1696766207000000	1791374207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	274
\\xa38a8defeb9e073ce58eee2992a5f7bd28de5e45e1317d5fdad4c64afe27707df4e77065d242ae30367d0a6960665b8c2e20c1a6f3801ebea9166ae8d4ce2a19	\\x00800003ce8cf73df4cdad0f636c40dfbd09556c5069b8cf162fe9dc79a9fcbbe939434a549ff72b95a8e0a6e62125dcb285058ccc6436a4025c93594ef77a201231571aa624b5eb864876257a8add20b589560acada84ba5cc45fe1ae3533433c9c737dec54dd0567ccd82423228e0fa2365cbf2fb7ca84122646f97e088a20851a5681010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc508e0fcea90f547e970266c4bd572b04e1722685d6ba0df47c69c76ae68297cfe7ca5d65b326859486e2ff96ab4afd6b2e11579fc3c9bf5034bbfddb99b8608	1637925407000000	1638530207000000	1701602207000000	1796210207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	275
\\xa44e8346291dd59a82df377d4f413935b4dc170405fc54ef87be2d06b1ea3b95ac449ded8b7d744caf903b25c117ff48c1164de8ac680327a3d7f5b38b08c9d4	\\x00800003b12e76b999d904b1586ff77a2ae69fd4284394775147616b8559b7ad9cc6f687efe6903eb4d2a1acd938784e9eda60b8001656a7753ddad6028e0c86daef52821127083be7c748b3dee675ad03f799637aa3bbb99cb57d444f18dfab7ddcd96c5fe709f8dadc35bd060558a1f076a6028b7e1cef8f02f887c95341935f8d0e73010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe08c3e7c02436db48a7be31a32f9d12e9f493d81954f39c9ac05fb559653f0acf31f3596008d5e576f1f5690696368ed51011141591f108f4b254fb04dbc1d06	1620394907000000	1620999707000000	1684071707000000	1778679707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	276
\\xa6ee327b060e5379753c55cca66ee32268e0ae78083c6686e45fd3314556a5698fb7b8965eeea63b587f1f6ff9e84cefd8dda7cda3a83049855458d7c79b3b85	\\x00800003f0e937df5e0611b9ca1078f96df28c50badbb43ef548e306e1199db62148d49bde447c8d0a8c28caa301bc26d634d5dafd33a4fdecb51f029ebf6067c0862a34677bf0ca52c162271329c43221a3cbc060c0468d9b43968054011ddb6e738966e337405eb2c734dadcc6e1b039e8c71de64877a1b5356d7487cb9c747fd9341f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa8952205d82eac599ec416f079204f07914cfd863799de120e906e3b4d978ec4a79bc585fde235905c8305b17690306cb232af8413b6fc946ca21e6bcaa9c709	1619185907000000	1619790707000000	1682862707000000	1777470707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	277
\\xb84ef994c8659521c5ea33776f3e7a946ae1d8762b5d8c3c3455e7cee9584c71f3b31a8b43bed93b06b6ea2b7fcddd247d4f81064ce41c98bda0e00ee77badd3	\\x00800003ed852a01c42d646acad03d6f8871d06b471e266f62aea760424b70198c3c4e9769a437208a3fcbce301d9778679f9a7adfbfa563b9e71630d225cb3fe012b6a8cd573fd140f4686015b4ee9d12edf2f2beb1fb9af2b47a42d738eb118d2a05b48d5d1e766cbc1ee07ae841bd335e7d0b7b3036edfd3e928f84ead96a3fd9e20d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x336725fb6398bf2576a3411923081e9ea3781c8790c7e1b55d7624ba4c3e4aa0f6f6e6fecc36aa79e7b0acde04d1d826853b2b8f5660cc093333e1b766c9010e	1618581407000000	1619186207000000	1682258207000000	1776866207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	278
\\xbb565fd27e5323b747b0efec90135185c13bbd173a9d88e623ae90b9305d734594dbfdc5c0698902ea8e7a6880169ca9e0fa4d2b7b6f43798106709c266d580e	\\x00800003d3b2651f591ab29feea984e341f3640bbd65ee484acf9bd0088a1f5d488029512dc28552ec696debbfc7d5e32c49b6e091fd8e45b1b84027677f52dbb4f06caef6a1add8a83175f0532f145240ccc17bde572da6929a0d3dc30da1deaacbf6517b43c6d4933bfe81eb192e8a8846cc6b7f864c4b4dcbeb3c467988facb4014cf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd2b799f0da4156332006b48bcd5831065e52acac2cf808f4246db8b13e2ce8b7840bfe68ca9482059d355ecb19cbe8c90e94a14b8180ffcd3c27d3ee9eb8ba05	1613140907000000	1613745707000000	1676817707000000	1771425707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	279
\\xbcba3e56cb877202d032424bc829541eb8d8db4f1fe17dd58aa1d549096ea2ef0d1b46ce48c6d3ebbf0547694ca522a4d84929bbb760832b1e0f9c8c74da2e21	\\x00800003b60cdf4282fd4594aa60a2bed79b8dd63c78bd3ba0791237628560a158dfc4a353a67c5ea118295a48ba7bb4bced66c4187b41674021d85393229ba6874cf35b44de11681c1d2088f0153be2e0ac65c5a811e3312182ab5ce8dafcedaaeaf98065e48f20aec0f8ae00ddb1276ca1964dfef2c842a7ba289bbd84876666b6de69010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2a7fcef081ab6bf103244639b5f30b269bf7263732602db9d9acde09986eb37617f22ea97292ecf7fce29bbffc27405052e39113447bdf144b60e36fe9b13d05	1615558907000000	1616163707000000	1679235707000000	1773843707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	280
\\xbe6a50dd752a00891e0595b62625103d940174667e3a04fcbf1011a4a22de2b2391e7442bfbbfcfe3d2e6f33f8b21670de73e66f1891b741b5db2e3878d5c161	\\x00800003b8da4caea193864399b6835d8d172ca5457ea207153380f9456fd004862de92859d074bd2672c6101e492c7be5206a1411e595c8e0f2d9adce72845bc223d30127a180c128b37448cba1be15935833df3a51c60fefd0b5ce54c360e6059ecd8ee1fc67eb40d5e5153ab207d11b8000dd989fe6b8d01118b0736db9dedd36a545010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0c59f7bc86c4dad5fd49c4f38ee2b7efc55def66c4ee49f997c910f616f234a2abbfcc5f1bd2c21ea9ec4ce44d6556a1285598a393164621f47d9b0794ea2c0c	1622812907000000	1623417707000000	1686489707000000	1781097707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	281
\\xbeaa9c78aeb881a5ee04ea4b840b6363f49e4e2e17d59443eff8a8918c526c1ba661fb387b96d98d9e18eed98ac46f8576d127dfdb9402d5e40221971925d161	\\x00800003ea24bf9208147803b5e953b2c1e5a695e68a8521e0743d28f7e7fe64b26b564831d6239e3804e0dba1d022a23d0a7039ac814c09b83793eafb89778e2383ba46b4f874e43fc3b9f8129352279096c1e52f1cf96f1122bba1c1cced1d772094999275fbbafbb449c5e11c3534f9bd057240c2cdedc8bb926448081fdfc7cd288d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc199fb8074ad3272a621ce570d2f53c4d20ecb2a67b10e1464d2c9f4cbcc121854a356eaeae485d7ebf2d65e36c85fc79f310a87d078e0871ca10bedd437180b	1629462407000000	1630067207000000	1693139207000000	1787747207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	282
\\xc27aa0848a49dbb305a4e87a8057324f2dcc6c33f12eaccfbe44749b796566a783f292252072119a0bb78ebc654fa4a24f0d9ece5d1d8773fd58879223ae37e2	\\x00800003cfcebd17f23562a907cc4054f27b6ed16a93a63661f4998f8177ad85a73dbf1f1a2eff301fec24c7a651fb309d2773a25a7a6b02488e2bfacc99e57b94f8c70a361d6384163e1cdb39ffa4f7d77d30f843111d99c1e8ddb48672d265a0aa55285ce09a648e1b5622e26614dd5e0edaa3621d2c38d58a9a242a635d4b732ab54d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x81b51d1a8a196553bd2573215fede3df5e91db6ac6ac1bbf2749570ab4ab084b82d3110d9b280b4944706e7357d82af707a716e0a32d76528bfc7a20a28b7b04	1626439907000000	1627044707000000	1690116707000000	1784724707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	283
\\xc5063f6f5f8457158478944fa60c1c5564748e883c980a9488f02eca01517f7a12ca2e67807447db68d342c7557f2ead6b37877aa7eae8538e4e4fcda8ac81ef	\\x00800003b4f2024ef17c67d87d6cf3669d1111d9cc6233643d2a8fd23561b80b6f3e43eda89a0eef73cb2ecfe93e7fe0115c00c23ef0ec3998fc2b6913d106827e79ad626d9baf83cd58a16a4458ef50b6c61e9a3de820d2bbb0fec84dda3ca1f60a0df1449b04515f5d9b3c14b639b54e64d240c522b089094fa2da5931840ad1e6d353010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x209dc6aec1416e57560bc5122c426cff6fb01b2d3aecd116b7953ed985e0611481a39a2e1f870e724e1284c66b782f7d602db010186b1faeb55289332665c90b	1621603907000000	1622208707000000	1685280707000000	1779888707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	284
\\xc9f6f5e1e389462992ba4eedd4358a0e835ecc398e524b94cb3031162e27929bfe139c4b3c4b51a6663f0a29371a21eb55e8534f90d6ab5c81507119640e401c	\\x00800003b7f573c16f6d330f394e7dcf13615153e6b5db832ce2f27a3077732427bf27e16296bc6ad4e308cb40fe6c5102fc872cdae9b51403b8b5177ec30b032169a13b03396e7803c563d90d943187fe9f91dbd846b058805319f7b5ef25ce63ed4bc789fe6ac7435019debbf18272e1bfcc4a0b87c6f3d620ea4b7f0f52b83cf97869010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcbfe418e6050e1310792994d3f23dec2c4f0a4f45ae55c3aaaeb2abc4442ddeafacd5f1441ecba62b4b0416c6b1542f8db3b355ca3a223217f4d001998e3a604	1635507407000000	1636112207000000	1699184207000000	1793792207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	285
\\xc906548297d053cfebfdda49e117018d5a7a3454d2bfe7a2f51764b2cdaff6603bd9ce8ffd6cf69c7823cd81a4a5216c96a9ad632df8219d5143678aa213d7ab	\\x00800003ed4dd328054d6152d5eb056ed97975c0046e8b7c60436fcc75d60805e082126c2e88c09f18ba32e87c18697f2eb3ed8b1ac121f4860756f847950a3136f09b4c25d37df25488dc0eb03285990fbb5c2babfdb6b4ad9f43d8aff8ff3542e6c6194b6490343764289005a978ad037ee15cd746133c74ad46b628393465f01e8625010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb7790712884eed25256f23fa80167d290488a7ebd3c3047e4da90b115a07cbfc5b5633d79e82a42c0fb9535e572fddcc2e2ed5476d6941cd0d4fe89b7c100f01	1635507407000000	1636112207000000	1699184207000000	1793792207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	286
\\xcb7248b6d2dfcb89b7af6484d545cc947bef90edf628fb1cac5cc2bbbce9138dd2067351d054e260f993c8ed4b615761e758d3b57e40924900eea28997afe4c1	\\x00800003ac5b4f8e8600ff98e2cbc3e4068e3949bc9de7eb36437e79d0e66eebe02b7f941b1d3e638aab39578c9ffc313c3c145206ea8bb5b4313c8ea5f573ac367175fa3b35024d99d735e15baa9e4768b7749d02302ae3e416c84700052c40d73ad641d2a9b3cf754144c4eb879bec5d106f21ff5e98d5b858645785d9c7621a7877f3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6649dc8855f1a3f0f5cd93f5638bb7eacd119321c1b148ccf5b154c7b9873b51eb470721eec72702b0f5d02de439117f0905bdfa549c1fccdfb6322286041e02	1641552407000000	1642157207000000	1705229207000000	1799837207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	287
\\xcc2e6939fb8641da6ac97ccbec093d2c1b40220ba0e553dc0863d0af27713490de0e5aedf0c190ca76b3d55b2edd430d0a269332b3388f60585d16da146f7b9e	\\x00800003c935d91b28da1e1b7ed4b4b49119bbd2f86f7649f89b74d6f79fbbec9f8f3dabde95817291994022412dbd4a66e5d8d76ebdccb3241eae5da3f54f44cb48f03adff2457e6f957fac00d991a0d41f0b13e20cc6d37200c0da0360ac1d7eadc6ff102f1f5c2d65677c7f8d7b88027cc8969c43068dab8f77bda355a4d44af3fcd3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x09cdccf787b048a5059b717193e31c73b86ab022b89aea9a1b0544f2f3561eb1f9c66a7b4450dad4ddb37d8735752a595fbaee56c49046356c83ff1d688f2f0e	1624626407000000	1625231207000000	1688303207000000	1782911207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	288
\\xcc120a8dc0949170c3897526f987bf27a3a95773737cb32d3e988a3d475b03060a82d16844087dda510030d2b633c5f66b275c3ecda03cf562affb8d69b71853	\\x00800003b1c6ba516d344658c82542b284b03dfd95006a156af8ead2cdd4d5fd7247d6f1fdc37c4c4440d7817b9384c52503342e66a144d701f816e7dca8bf5b631d54137b288fcd06a974e9024b071a290881a489f998a70a5583e5b8aedfc6016141b34e3a9ae56a7ed0f2a0be691224f2e5bb6099864aaa1e8b12bb3aedb547f698ab010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf2ae08a74c6d82fea3a9f16434c4be42126b69eeb1b53cccdddcb455f988b5411a9d5fde4cf960305add0a83dcbc42325109f73f47296b78a15b76d29c90430a	1636716407000000	1637321207000000	1700393207000000	1795001207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	289
\\xcd9e2bb3f0001282f82cc23f8054acbe9d3fbbb130c91cbfa32a84bb4b99f999f5834b1c8f98f15e3f54c915c2685cfc47918177fbef71bcb0f7281f9cd33294	\\x00800003b8a45da8cd3b5a3f5e2924615e68c61272406702d5691b2729d92bac6804e2c82fcbd766010be2208cdfe2e2332f3529299121bdfcd7d5fbba0e673d5b9ac8d111fcb7415df4b34fb7d1da8f2d29343c8988fa9fef3d6622c52d814c0e086916cddbcc400d895d69dd01dcc2334f8b1c861e19407cdaf51638cb3306323d956b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb45eccac3b80357403cd68f367f8faa1891c54bbafce0b47cef5144176cff690c59f69d26f0972d6ee96d6cc91a703a4eeae962d973552b552e4255bf0443b01	1639134407000000	1639739207000000	1702811207000000	1797419207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xd112830181a3ef6c44152a37fd95e13746855aa90a97e9ce83006b0f983fa7e614ff0a8c43844a76278df9d58aac337121a76d261d9d183dcd4e54070b3ece77	\\x00800003e2a407830dccadcd42d34a19873195602b2cc66565a0cd844a029bbdd6da877a26dcf31aeab28d242df72471cfb4e5f4f42648e323451322d5384c4d3b4b36d0bed1b82d9386ed4344e73971b78c264892374ec335512fe6aaa24f8ec8235a688c654bc1468bd792272f357340e9e2800631d56ae33869a23cc677dd18873345010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa89cac20b471c41725483b5f3889ac38448fd493325cf5edca0d504285e29b3e9a1868177595b91733c67250747409a7dd62bb1aaa4183dd921a1fba8ec83401	1611931907000000	1612536707000000	1675608707000000	1770216707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	291
\\xd4067e814b3891d073412d0defe74368140d08d41fd6c50bcde07ad1c269997483885053780bdac46b03edaeff8def8250d68212d5d379f88b04fedee327c2ad	\\x00800003a9a29e87a57f3a3043206fc700b8cdee666e3661500142b743aa89d64b8a5ec2c944154b410638112a810d1b45cff27cb229253bc32333048805d67266b04155a496c91355d6419c6e7f9d8a30bddd452e083f46f3bef761516db76e06c2191937e6abe88a6d952ea18022dbbc6ddb121a8af498d459c16434a629fff606b745010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5577d5bab45cf69e6a7b00e7299cf9261c8faa819d4e53f7a6c693e92264fdc5fd3f6645f9c06bf001b5a2f85325da4ab6eb92c41f2b2cc09ff6260df748a20f	1628857907000000	1629462707000000	1692534707000000	1787142707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	292
\\xdd1e21250d3d97c188b8933a0509064573e02c10fa27e32e2473b599e0b4986ea4344b74bd63ea443afcf6659c99b8224334affc2a5a4f9c8cf5869f893c6c90	\\x00800003c4ba4355d0622d77337d0db599c412f9fc9466e8b61fa2b0f3f1bb5b56c7e4115a2197db33f8d36dfd2ad522658ccf07efd411be4059d725b075992fa0502852143d09f234168b97ddd8a40ad25df7bbdb80dd5b1f0899be6f74173c5fc9f1ba427b4f51904326b29c5ac7ba025073889e628f2bfd99e9497a39a08b6210d7ad010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfd2ebd3ec84783ed33e0bec2e763ab28133cb86b4518579b1e2dba0016357636e2fa680c46fb997b7ebf424173cc7613d2bae79bdab65a35f0b3db31cb65fc08	1633693907000000	1634298707000000	1697370707000000	1791978707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xddd69a96205bf9f09b698f227d7915416c037f0bcf6aa3c699a97d6e3d5b6d81f6dc1bfff35bb4823081f8015eb7e6c7a26e5e6302dd73a2605b415df4c0add1	\\x00800003da084494fee8abe8b7925a1f9ad0b2895d0663f665f25f53001dee6f0b9aafed8feea727bebe8487dafe96fedad964ca0bcfb851308d13c5555ae5976026934b478535b5d34451a8393e0a72479ec02c6d26bf92169daf76a3131636260e487f0dd138e92bcec14b7a5f56f38c4a450915633bf0dba25ff7d6cf44c3f891c007010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x257e4d527ecc5381ef7953d2f9ab8c5d49b248bf0cc6bff3c6eede20aa41529c1d2f67fe73675052208b06ec5a2ddea14c2d227aaba98fd0a5661d13d07eaf0b	1626439907000000	1627044707000000	1690116707000000	1784724707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	294
\\xe0ba8d37cd5a705fe9d260d8168dc10bdc22b142297ecde11aea32ad44d32787fc642141fb6008870e03203496c193ad4239d3c00cd247a0e5ac2f20d7757a56	\\x00800003cbc86b10ae8f365f64ad0d8c84a6ba70b96170da230d99c5d94b9fbc5f41439220c25357c87327bb50667bd8988735b440f18bca5e222a53c2e6db1b2dba913a564b81c1ab049147073b9f29fcda26317225acf053921651679fface7204c205b4c435d0956b6110751f9da392be28ff7c4d698727ce770a8296a2047861e319010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3f57ad326457242c316f16bb7e4200301b12f651bd6ff329abad586c607228e14236410a0bb76a14271ec1d40cb9cca5fb65cff3ffed25593420f0b18eae2c09	1633089407000000	1633694207000000	1696766207000000	1791374207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xe166e40ef861d5a7c6e5ca9d7147755f578701ada0c2489bad530befb01ac3564b53bcbc2f99a1983ae12f19ad49a26be8863f292c99999451c5d96a999cf34e	\\x00800003d8e1c7dd9ad34514ee1a33b0b4ab050815c537d544dd3c454b7b36a35f759bb537a68bb65ddf23486f77b4ac5f9b1bc6c519d7dbc4638e1063b656396fa0b3cc858e5279385138f61aad0218eb8fab98f2ccf36ffe42bbec2ccf0167235152c10b050b968f272f893be6b51aebdee124be57c431ce1f582b031196218efbcb57010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x91b1439dab43633a51531bd44032d128e32eb5b33b5cad4a68442847299eadc8cf455f7ec7f8a2f4adf9dc7d0da11f5a32b95b59545bc1d7e399cea45a0b7c04	1639738907000000	1640343707000000	1703415707000000	1798023707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	296
\\xe19ef9b278091f11f365b7f4d033f03726fd1217550e770e92e6ddcc3ac8fa9a2757cb2d286fecd735e2f95c4e400689d6344b89eebfb325e23702230dbc29c2	\\x00800003b0f5b503b7aa7e43dae152c3b96b87ec26d0bede17b3f06e10f3567ad9e367da0b674cbf28af96d174123c7bf0021b25bac01bf54f4bff88714c977b8cc98dfeb270e6ef7a5a82241540e99fc9457690f63c06959c375b924708ff58409967211d37ac0db6dc7e4f9b89378f7c9b54025b26e4a12fd3dcf919d415eb49b2c7a1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbbeaf10c9ea176ed0cd5eaae2ab763874e49b1d8f145820d667109e5a217063cb0f99ad3c42f0a72e1f7e9894ac1451a96caca7762e759302bee4c8dc43cd306	1614954407000000	1615559207000000	1678631207000000	1773239207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	297
\\xe50eb980641b5bc09adc302eafafdbb2fcb0b5c5a2683ccc4b46564e1ce265c999138ad92e0474281cf00b30eb61459ce33bfc10d941e7dff54cbdeda1bfd8c0	\\x00800003bb4783b5837fa61751a87eaa2f33003849be2f1c45038abf0beb012c29835235d4b6b502196f8c75c738496782bd3e3ba09d583ab89ae9ce361220b825099f8777c9380803396f323e8106aca518b2b21d5e2cc88bbc869026261e1fc0fc1865c31744a4a664b09fc3b05d34f2e5f743f63fdf41bac0ec5ffe38854cc123ec5d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x46282eccad49c374443c9f1fd0cc8f451ac98f17d86c4943a181574930edc47fb8a127b3018d7297771e36f927cc880a8e148f984632290e0f2e9e5e273d9a01	1613140907000000	1613745707000000	1676817707000000	1771425707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	298
\\xe872d36d8326e343388ed9c7cd60b032ac59fe4b021cfe1d008d53add262ec0ad34d26c83c02206984ea38a504ef01b050777671d00072511f97c240bbabcc9a	\\x00800003ca7e2f22ddcc86ed62791981f98a991f4c47b8fde0a5e8c364a44cf9195bea85f8394a9fce7ca326b0c3fb756571f96a8b11e2cb1b16c4c09096274a8397ef1c94704b99bd189944f4adc8cf4f3fd03fa9d60fd00ac37e8922f6f764915c112b7c30d15fcb9f8477e936980614b2b4c2d83e78adb77c9098fc2247a9fcc1da61010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb52ec76887ed3f6be8d989df0d2f8fba5dbbc5da893e5e9f824533b49a6dcd5aba99e6972769393d8c90c7da16f980e9b52b1ee733b59f7e106a67276f8fd001	1614954407000000	1615559207000000	1678631207000000	1773239207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	299
\\xe856b8aa73b9886ad7ae91efcb5fb4a9fa33e435232be83086c8a0543f946e2f8003ea083b835795c27a82a6a232de47090c6a36be31f8efb4b6bbf1fe4a7402	\\x00800003af0da4e12ad84ba5d5fca10933e5473222931bc324c7e77902d8afe280904967b5dcd674dabc1173a0b48da0915483ebe84c85da790e66544d4f7b7c6ca5db415e7db20a2b2605bae55bc040e8b1d93ee9a042e42697ffe53b8ee0eea628ec10887540f6b9034ffa4f60bc02ed8f18c900539b7bcd9b0020b24796e671de7947010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x65dda1f5adfa0793b26efe25ebe4976677e0801ef6ea6d20a50f3cfff8098baa25f8ee137d683f339c4e3e7f5c50590dee1cf5124b3059d8e38c119e55de500d	1624021907000000	1624626707000000	1687698707000000	1782306707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	300
\\xe9d6085a930220ac4af97d8785693d054f7ef445f2d6b7124d436e2cf805fe91d671005f44e14b856cca897c883b38c80c47c9cdee8d8c4accd7a4fc1fcd98f4	\\x00800003b698be3c4738342c78cc10dcc92d275c4b177a0f3bfa5e789ac549f163e34918f269e7b030d76b4a02286051a6b70d808dffa876e73e1fd3cc1b9b761e0ff7226f908021f7201ff38a721484b2182c81cacf0124253a4f609d3d4645b5375f0230caf1bf55828333d5dc192de65456584355d96ef7c0bb7bc13c891e8bc17def010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x645edd8869fb3877ea7d9ef5b57c6eda3a0bdda6ee27eafdc57fdbad055b023eadb3218d4ae1a880e8b18c77ad894d492ce39e2d2c8aefaf75bbe7393aa6010e	1623417407000000	1624022207000000	1687094207000000	1781702207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xe96aca96b179ad08464cfa167d9b4bfb688b96a37c0e9308445c041ab0f69d40d28dcc93e9f23237fb695b2b51d00442664fa13bffa5d6d251d2a52889b880ae	\\x00800003ac2e68f0a9a6f64f7dfaa9368ee035565210d8a3307e2a629c6c69040b90017e989d252866ae392a4cf8abc454802c45195c6da253410fc675a2e77dc45f3a138059b10e5d931bf940f7629a294df0e1982b261a9d92f82f14c0b97e2decef4d2d0e63528467b908cd518873abbdcb846af5fefafd3999234f980a39f33670ff010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x807156b4e7da32914ba8d9e7e0b974f865837c175255db573767aab953d6278ca8fe2b3ff15ec8d424ed650a85d490e8b8207679c79f2bbe20f5bdc5e3b70b0a	1620999407000000	1621604207000000	1684676207000000	1779284207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xea5e2d08a9e96d565ccd01fb7e994762973990c1d212df1b188153bc1e9eebae1b3af85f64a0a128316043915040dc3a85f84d47bf4fbc907af7b3408e7fe1ce	\\x00800003bdd1ada0da3419ce14de3ffa0b61eb52e604c8ec9cf85ed569f18abab691b7e1a10f1c1226f0a35621e36a69c0dd3d9a62f6f3f75f7ac147197628049eb94f364ffd2ba72096c372eee152fcde793f6018bf7f8d1bed59e488f40b7952466f0704c60a050f9cabdca5eab2cc8234489243b03fe9a0b5946e94afb2835b108aa7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7dd0b2d88e580570a15ab7a5ada4d22758b4b4095e52bf4be76eef7732dabdce5670bde2f5f59a099730068374cf89b27716dc9364588471c25b8e7df758d608	1630671407000000	1631276207000000	1694348207000000	1788956207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	303
\\xee7e0bba8dcbcc1469a7c47fff64ca59785e53f70e96b68b3b2f942a4d741e11720ea4fe6fb8e2c5755a26becb6000e60f60f9bfa8ebc460bc6d738b379c2bec	\\x00800003e0fc295f38ef94bb877b0694e845310298afdfdf046f7c8e255117df0b2b0f9ea99ea6c9ded30016de7d70335ebcf7c4689fa59802ca452c13f49120e575b903e6da14613eeedf58db1ce72892f791b6c86e4f469966fa7c1c204c28222bc3c6b5a885f504f766a351e1b4633935d57526cbc3c38c8de479ea2ba824746a00a7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6910ea60608e3d00146f23dfe9cfd9548f60618cd1b15e97ee4a6d67a192c6ced0ff4f16cb4753faeae5eda8e523405edf7398847b121e5d68767465403ffe08	1617976907000000	1618581707000000	1681653707000000	1776261707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xf0ba24151157818ee410fee37391c93841fd2647591f724e68c06fa52121c0308320f91ced0eb41efe86418875f4462656f00243368ac21c761918b02f9c18a4	\\x00800003c9a054610324783bf23c9066c6f656a751a70bd84679e250057c8c8beba66cd4524ef71d327ee2eb681664662fde7bbf0b94d75d5d39a2ed92a6ca2e99294f254d48d3972ced1ba2268e0897a8e48642e2ff84dfcd707b853a69bd10262eff57a8facc489896de9e4524c9f57cfa2184452ccf584c1e23a02b6c2628686e3df7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x65e8a1359a10402e9a302716b613fa1d068ecdfea972b116fcd8cdc19f0539477b62f1bedc906773716ca89342735b26762a5f5bd8b568d86c7dad58518cc302	1611931907000000	1612536707000000	1675608707000000	1770216707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xf2069d77e542992a254db68e18334974fb840faa7a7df791a76c43e14e0c01f9127b652964d25769f58c7812e460bb9578c5f2c4f5877ba845b2632361d6ae52	\\x00800003f1af96b11181a028d007bfdfcb67a7e9bf0bacf06248dd893f05f7ae00e91e9cb3cde5578eefe999ceff945e0c3a5c2dec9775b4cb3369656acad917497c0d1865e80f7730ed3452c63574301235c4cc14b70f6520114db7535170e6dbcbeea300f4181c859fe863e74bbdad69dee49cd0b51946fad485475c0fa817d0336ab9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x65b06063ebfff1845197a7067f4e7a0dfa8c00803c794bc28feb0ebc186e26701c59c1e1063cf8162a51558c0211cb39a4bb4ce52e021d5fed258aecbd68ff07	1619185907000000	1619790707000000	1682862707000000	1777470707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	306
\\xf3fa646c78fcda403f96664df7f5e268781b3421f44dee9935b8205ca956fc0a88cf380a05a87a258274734a3b5231888e0ad54b58d48a0db9617f3e60ea017f	\\x00800003dd8dd03fffbf83b084db3438c03ebb22925e067270cecfcfaaa946ca1f9397fd9c5fd01e990ed452265d1bdaaf1c5cf82e2481f9fd6dded29d988cbd57d5e8eced22cfe64b74aa8be97d79a17f7de8ef19d0b42136f8ea1c045037c8409c9628828d7875dc4ead300036b7486e61358951e49fdecc5019543c48927a309a6201010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd5d0accc37ea1b4971b744589c1beea6ccd4bcf01dd4da28017a4b40f5ba65c31a9a40203443c531c96697cd61af0d0e889441b8fa226b63810c362c7886b709	1610118407000000	1610723207000000	1673795207000000	1768403207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	307
\\xf78e5e216951368dd1929e882354ddf99a337662342a65fa3b957a8e3add1190445bf88c5b770286d9063e0d9c295014771f9c2ee12d9208d564cbe3c61763fd	\\x00800003c8f3b784f51b082d86fddbb6fdc3ebd25e03a4af178a2c50fbe0dc61f24c28f80baae4fcbede707aa4884025791218d8c2f034c436905f56dd0fe7179a0ea29e9ff3f2e1556b578c820f909ad9dc11b0cd97efd168ede1b6eed75a994d4447b9ea2e97f953914a34ef98867e56bb7c527f4e29d71d5c8115c8bfdd7541279821010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe84d23cda9b908f1695bdb0fbfc131c28874eebbe6b3113c7ba849bd04558655b1eddd4ccfd8a919774a3ee90a94f7baa7300c6615281df6e061cf44370d2702	1610118407000000	1610723207000000	1673795207000000	1768403207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	308
\\xf786aa3824fc3037920ab8c19f200789ab5d14ba833ba523ae6bdc6c5db4158ef57d7518f756222124f54b550fc67d662eb0064eeb30b9ba9797f51909b1d84d	\\x00800003b82a517d94d15e8799ed5cd43ea35c055de222e9790c2d8cf1632974086184815eafc1d21b9ff9e8ad3662de7f72ba89552dc594ef39fec6afb2104af2638e4174451745702cf1beb55defba9352d8fb473a5ec35d6b315ef5a1104b241a94bdf35a2bb40d99f54468ba520cd2a71af0a1b15725533026e54c67b88b53e593cf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x31d3b699cafdbdc2fc80db8dd48aca44bfdae1c7b559378f8cea82833839d2cebba459e84a198195653c860b1aa7babffbe740bba31da10e56a78550c3d04d05	1633693907000000	1634298707000000	1697370707000000	1791978707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	309
\\xf99abe23ab1af4c66f39c43c5a920dc5b82639c7679d11373e5baac8d555fd98bee166c9093c5d631a5d9c14add8b907067ef04489ca0f4abbdbbe2d42197269	\\x00800003b289162e7815d23fb3494f2af3476d20883a3ae6830a4e312cb185736f6efa2ad79b48d6e64290afe6579865eafe64eb8256ba5f1f9eda65b537323644aedc5ca0ed396c003a2916c34086f2168329bde879dd596bb0e61426881ccd4848ff1dc9cd4aec4078e032202f9a7f935c692c1fe535368a8f0f5fa5926b4f57411d8d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd4dc56a84a61bf45fb9b49ca9ed0738c0005319f6f464d36ea52192f476068368dc8e19037b25066fe40a45deea28aaa0c58f4aeb26ce9217bafe8fe2ad0580d	1626439907000000	1627044707000000	1690116707000000	1784724707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	310
\\xfaf2d9d6de67a5f91e255320573d89a147000ec1307e8d25c73783ba51e99f68549c45f539c58a97c8c70d58765a9e37474559a26875d7ad820252b4aae6b9bf	\\x00800003ceaa5a76634f3bc1e108c7b62bf2cec2f2b07001458db1ba23c5ab7869953b67ef98d772ea9f7701f3d2288656e9d607f8a05b063b30a45b27ba5747d169e9a1664d6958957e30a33d030aa9e6d71621cfed0420adbaedde20f5412373debf8ccccaacf5e603bb7377ee675dd7e321364c0a53bf6d8280b404b0934a323720d5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8e1cd634262a8bf4588247f3e5edc2d461b90b88c48e344d6bfe2b38af02403047fd4de37bcc50872661758439b5a9d106561a1cb429009471fc178450713801	1614349907000000	1614954707000000	1678026707000000	1772634707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	311
\\xfdd2c82fc64493abbd8bb0fa9d39a1dc5ea13541b8e0fa9493ea0de7a29828ea504e87f61747826a067dee6f60bc7f4264aeb7e23a79b114118e1bf8b070a22b	\\x00800003bde07d1ec97f5ce8fa82f3e3dbf48d010a22b51123d9fce2af190ff1e17152f9076c597f38122a2290a3c785f86948c1a8d4a6e3410b22b84273355e892624be0101cfc68d1d6c6ade8c7dd7822700482945d8ed500f4befb516936716f773b7ff20e600f0257e047316e78bd7c2d13e8118b94f86b30dcef717ab493b9881cf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7e5770a615e1843e4c8092be0cfc680cd9f9b39547d732bad811864a062eded29bd585e9beda33ab83a94ac68316667a9e37de9747a7d7dc056c46ea36a63e0c	1610722907000000	1611327707000000	1674399707000000	1769007707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	312
\\xfdaab650cbd05917178b16913b0ccd4fd0a9fc914fd4b2dd2f6b030278bd63354f0d6b0aecd328887ac32fb1e9d0ead31263c41b70d3c8afcb26f610dd035c43	\\x00800003d6cf637aa52635956c82de7dd1e04f74e901b29d1b2039e6f99f6daf2e55a68289192d29c5e1b42f234107a230268773e895a855c1cf03d931d7a59b8528ee872cc701322a1b72b37ffdb0caf8ece13f3ad459e9a50ac27b065d7be42a960b0e54799fb4571cb5ebd161f0b77c5d1cc62f971aced7affe7f1b352d0355fd7cb3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xce42d6ebc6533d7671dc4a1bb1fb03eb74e4af7bac4cb55c4ddc703db2b2787d0df41bf0ab36e4d2507a682127c899a75408a0493756e843b5cc1ed478a6ba0e	1640947907000000	1641552707000000	1704624707000000	1799232707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	313
\\xfdd6248a453c1f6ac8595fd68d9ef9f8496c7e3b6f4eb1469b4fcf513c508e155ed8ab24335662cf17ab66f603881d37589326515019c1aae05fe0b8f8d26fbe	\\x008000039a5cbc42ca853ceaec92c93e7fb975029b3f035ae10891ea20286fd5fd76390be15bec313c83983fcf63d3844f803e22c8306c930d96ba0f7edd20ea84a140170cabf5af3f75c81e80c2daebae48e57745d0ab1edce182c0040acaee528f033d56fac38c5fd87d6f2d1979e4de84161bc1484bc674461d8a75afd12c95b9482f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf881d908ccab8ad75c4de9cca73e8f73e90877b7c94517ead5506e42f7379bfcdc58b68e9f25e616c305546bbc4a45bdbebd9e6f3761bda83f4836b73a771f04	1612536407000000	1613141207000000	1676213207000000	1770821207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	314
\\xffd2f8466602c8765982ea65581ed5e5541775c2439dc8e7d5301d5218ba8b5cd4e26b313088f185a93398fa672e5f5af9bcf29e262ba71400214f99f0d15dbd	\\x00800003cd2ca105fd177c85ce579d6fc1bb0b3bb2b40032e0c44a38e6853efd4156282695f600373a59dda84e68955aaddaef17687a96238f50f15bf3a9f6fd0539e6b4ca81f47c3f34f51cc68fc5b2dcdcce94f9bb9e94b4b6399bb981cf0ba246204440dff0c98c7846ef920f69649848018ef41c37797b8301dc0b85142390476d73010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xff63dd38a703dbce523096c1adaa10dc266d8fd3fdec5cfa5bd2a32d7b0c1fc9d55aeb030859569578cb7c0ed5590f1394523a306808afe67845b6971daef206	1641552407000000	1642157207000000	1705229207000000	1799837207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	315
\\x02933eb3fcb9b1e94c10b3fbb43146a20c1d92c594c48e5cbc424d17df37923790eb5c63c40d83735072a3cd964329eb28479aa7e40d8f518a69e32a6e81083e	\\x00800003d0b8df5e6f34f00aa338eb067bc9855e9f4b839eea7090dfba5480b644681caf70bbf89b753ba590b1399ca15f47d8d46be5dde1fad24e9196bce14ef686f2ef2abcfc59f02bd8c21322dd88296cfb51193f1e4453b1283f6fb388fc651f61012c766e4711eda88729323115f07b7dd382e274348b89067acfd6a14bbbeeafad010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x73dad9fc7180c42b76dbf1ac0e59f6cb3e4499a02ba37b4519d059545430a2f3aad98b721540410577b17e5bc675e6479f0d995ca0010b8e0e644e900056f20b	1620999407000000	1621604207000000	1684676207000000	1779284207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	316
\\x078faa2d1db17c300bfbcb3b0db0f32afe3fce6bd3c45aa13e2d87f65f277f3686eba47dc8f8a857749fa2caa6c4f5f9d65f6ebccee7e974daf67bb170d20c6f	\\x00800003d6cfd6c92150ee0f3804670653ad92dbb3922d2e896ec0f9a1f7bcdf65070d49ca8479530865a5b0dc58ec15ac622557f92b62496ceb36fa7c7ba76fc4d236c9b3d65c35d3868f3437b11172b53c348d3a877bccd73c2d42593732cca9d70ee0641fafa30350fa00d0545bfe21e7dfde268d696f8dac700cf7a12deabf8ac043010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xba8f82dbeaa8d38feeaf3944f81bf09cf207143ceb033b3ef5a25ec29942ea2b9dd6176c898f1bd1a8535f784c0806108e9faad95fe3d8f76570e1e3f9b1800e	1622208407000000	1622813207000000	1685885207000000	1780493207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	317
\\x0aaf0b5e140ccaeebeab91861b67136dcfc1ed5281624ec4efab4ab6417a6c8163e01250e70484349f09ddec0b49a4c16efd0b8884e9d08d5585028156c5227f	\\x00800003c3efc57cc6f107404aad1db226606bbef1be0ea41fd250c9ddc0bfc5a2f78d3be62ece0ea23e1ce1122d015f2a79b3542c2712723084d09904ec427d53eaba19d5be3752606c29ed28ac085b78d8ba7298597572a0c8b3408f00872aad802d9e6af13ad5dd6a3d753701006a761fa53dd7baca487f9e5dfcff55647d4dade5bb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xec89ac3782ecbbdc0602973819a75d856ad0dd3cafaf36acdd5963ba48ed51638f5975e1f32b839df85652f3d5721aa56fa00ca35089e01cffb5ac6cc54c7a05	1624021907000000	1624626707000000	1687698707000000	1782306707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	318
\\x0fdbf0b0e6d7f21792814340be2c3fb2fd6cb2337b0d47faf45755e9f44194cb0a8fff2a74aaeda64339e3ad67f215083cdcc55f7ca5f710c24e22e3bb36c290	\\x00800003bf3585843a90967fadefee6de9c07a15387ac99d143bfdfe4e9abfbfab74876bbed4d492fe54e1b2df2db56a214bfa2193b5de550df2a7768da7a1448f4fd7455457b96f7159eff2c7b11d6e2c8d3e8da9eea91d8815fcb78285bf3e771b8d03b28fcb1cd1be9d83d7cbe8bbd9a2e3b3c99641ccc483d489fde0aa1f17ab7b0b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd26e8307b3722a2152032fdf0322bd0696aca918f229f74a5b08c84f9c3e2df1d2b85a5974b093b58e5c7c149908b6d54b0ef5c06d294c0ff946d54bb6402f06	1630066907000000	1630671707000000	1693743707000000	1788351707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	319
\\x11a75294711a55cac35f13fe1d1494fd59e5066d17f96e82a979d58a812c204dbb67dc0c4a8aeec7b6e25b2729c0f747c6d81fa7ef933633caf7db7637a47e4c	\\x00800003c7993ab8841f0e8ba9926ae31a14a01776b499b694c30a4fabdcc261863d0c97d441f6f32007f8fda5c55ccb64660d3e71164bb464f1e568e9c581f9ccf59e932f936a36761a7ac9d75c9fbf909f47c3a7dd455a6eba145538cca0904ab5822abd836ae34387462f0daff6c0f351df9fa05a8b563b2974cfba241ef39e769367010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf590d4ffe8252c05206b8aeae2a838ffe7e83211f62a5398d9c3e3f3587e9142983784c0d085572b956d713f93317a4ac2a330d9d0727ed8b7d5982871886205	1633693907000000	1634298707000000	1697370707000000	1791978707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	320
\\x14272d4d4dc7800e6fc8ab7716d14bd370a2891227fc50156aa9aa053a4adf8beafeb68cc4050782cf55ee3290a426b4d07060d9e05383569de0e9819ce1b78d	\\x00800003c221594f290203de410d70bed80126f77bdb67b43f26a874eb41f17b50c4ab40e38d7406067932a402ea421347f0ac7a5589173787a42548ed1eb91b8a91da6fffa393eebb8bb5ca60d9f1e4c1d6ea4a42fdd5abf9624b54a6ca815d14ef6d81ca54b0fb4f566fdb50e71555e2d0e69980d76d2ae216f44e28ba7daac77ebb49010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x83b81b477b348348b676ad9b69c9601bf8946c90a757d3483b363a24e21e2082091029f779cd39dbbdcc8c77b7d6ead29190d6adda5c2bd4bdd9d0c13490b20c	1610722907000000	1611327707000000	1674399707000000	1769007707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	321
\\x150f68c7ff382c16d8ce5a17d44e9bedc509c15d5ee01a76a2aa36a910b8ae61b9da676467f5cb727fe202f006fedd9a27bd7b2ae3645cd1c87462f829f40199	\\x00800003ae0a246af0152c7ade9c966974ca5294c29a25865faf5a61e86c04eedea1fb36a9a5b3c82d512b757a683c69c1896fdec565ff6a0215f6a4aee8cde90856e478193be770604f9ea4b276c6d4867bda0485ddf8cc48dec0e4e7491ac5d9ec08d9cee93a50181c39cab942e1bd48ebdd91128956ec8db7e68e6c0755b8a812eb0d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xaad20a84ba26acf9bc7b0408ae9c8669b1914595a84fd029052a438726512dbf8b87ede27d648193434dc474c9510da4467d6d10c2044d6c3c002df4faed310c	1631880407000000	1632485207000000	1695557207000000	1790165207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	322
\\x17e3d22b4fba4d43270b58ce0d20775391791bff129b11a3b2bcabacb664e071faaebe0d62e1948345765158355ce6ccca23f37f23589283f669788aa41f7a7f	\\x00800003c157b31df40423d4db7fbd51df3c8a68313d6096e781164ca57d88743ecbc3f7140b3fcefa05b10f802719eae22f8d3bbe54e0162a5b3963b3e771e25447445676ad6559ad7a2b13bdffcfefa2dea0ad747c073e987010aca99388876fe9defb888d96a50e3b4647fd951586d7afd8698798d7dfdab94c40c95e716fda596249010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc1af0cdeda58d6147b9c0a05e04edf4c0575c0e55de9ba05e11567dec07d17e7f34fb9d2a10e7bcc40b043f70974d50fc95a98fab54deb2ff4ff552be7b8c607	1630671407000000	1631276207000000	1694348207000000	1788956207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	323
\\x1843c1a0de5d06ecda83bd1c41c2a93fd601d8e8273ed86f1548bed80366a35209303886ee5c548ec0610a7fb5d088fa51bd905ba78129f152ef464001ec89ef	\\x00800003c9ac86ad3676d955e8dac7d6f985d67e941646489e32d4c3c38a2062fa7f9891c4b51c893f4ddeacb5b3ae9e04aa95057c96152b90dd4e0ca78215ba76d276bc2fa7ddcc79a9d43051047aab9134af83c3fb5c46a971b7188ad986735daaf227ebd3857f91e92f04aa7691ccdf719066c417de487dfdcf3af5e8c05e65966347010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x50944333c1e0173ecd25e788911a8e329668050fa3d7854776033599f33645caa25161a97476c9bc01faddb8528927a665b7590a28686d4bf3cace8eaf1be408	1637925407000000	1638530207000000	1701602207000000	1796210207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	324
\\x19d73ffe8614c5fe88aa072c3c2b5c98b47c2b9d848c2a2d6eed364cdcb0433481e38e3429205c2bd9bd0c4ecb7bf9e1e729c260a436c4be85bb64b7725311eb	\\x00800003bc8690dd6ecebdd15c4700207a29334536fa1ea43219114da77ab51c0abedb2e2a875bc0f63131923769a6a232607e54a234ea1cd85b907ce1c6937d6758cec5504bc18ec7fa064e44de58327330d8a2f68645cfa0b17d05d55299407a5051b80abecaeca21b5a4974cf6c66c258c34bc2da6d84a7fed9af24dd24fb7cd2e001010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xdf2f78917c6c6fc1c76fbd4f8a8a985465c2d95b757f1fddfd243becfaf85cadc0c7386c20fa62c7f46e57fe850bab318ee89e9c7139a954fb1ce0ace30f6a0e	1610118407000000	1610723207000000	1673795207000000	1768403207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	325
\\x1a934080c7f7745fc25a03e2a32f0d6416b839e055d5bd664f31dc4212aa89bade21366901b0b0b1d6070d6c67fc3e70d31a28168e700b09eb6de99c106cd8d1	\\x0080000395c93eb8f577ebf711a282888e0c13bbb15eaaa7ded65622091f86451174f253415ae4e6f9eca4632a38794af227596db7d18f04485baad057817437b78919a72feb9ba4e7250b2f3c753390b8ab08f9f1eb9c8311ff5baed91584f6315ca97ed44ac6389c766b6c472c82d3b948beb1a4f55c7e408753ee5b7bd8cf18420e3f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x521f79aa145bd35f780af655bef9b0ae8472a0b71a586fd10af47736f0225a805ee28289b3458d53b790d94c996b42dc525f6d8633b817802e7cd068b1d8d100	1641552407000000	1642157207000000	1705229207000000	1799837207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	326
\\x22f33cbff70569322409ec42d1a324e0904114242878f4fc686863b7ab1269af9bc66e79e084e5108bc319c784757fed7ac92e3d40008a747675e556db33e99c	\\x00800003c5696d7f62b150905ece534c9a3b94b550ab4713cf300518b31e78bb1817aaf44ed079f97576d1146bb22d97f958e3398598ade7b347c1fd231bd05e5cdcd6f738f809779649f51b435605be99848fdac585a225a62b95f06ab7f94290807cefb486e63060156447c80eb953380e6b3b181a76bb3b7a4754f21bd61fa567932b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xebf444d841ccc156a450f897d405a5b0164bfb6544a74b5130c84b9e5dcb2b26b09ba30cac0b8d709a4992244c87ee847ff3a424ba23a26a01868a51e7919e04	1631275907000000	1631880707000000	1694952707000000	1789560707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	327
\\x247b0e1d6037acff83d9c5c748d0b701d54a8e3cf65868b2cc0b68ddd16c21cf50c3e8fd8a06bd1067d139fde2a7bf277448d12907d43dfe84f14d20b2e8aebb	\\x00800003b280adaa7fadf1d39cf08c84d8425854d4c12fb3ea878581b079e374ae1be4c010c406d4e4938047cc31953f7ba99dd995183cff3b01ba9e3d072f557a90db3ecddb33caa106b74ce24684fee251e65886fcbe7fc306b9736b8aee147590766065aee0a681b67bd3018ae60bacf80ebc0acc2c19577f41f2f0bb9aad6b876ecd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xcb9d45811bcba61ff9acb34b919d9604de78120c620f967579323d5f0e6fa3d87a60bfdb20ec1bbe69918028eeabbc540d5c84bfefc618720420676a11628e01	1639134407000000	1639739207000000	1702811207000000	1797419207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	328
\\x25ff9699499ee213e1360e6d128e97c8499a20664905c464ce69d85ce332ac126055c3630fae42d68b1e52a19fcd6cb243e9c835aabbbb6bad730ce3be2ebdf6	\\x00800003daf99e4a59cb9206b8dc4881867688ae7509d7f15f15a0210f1606013fb9b41d7def826b7ddb920f293f5f3878a3881e1ce4ff9e8a9ae31766e0b49f5e60761549465d8947dcff603461a7241f9945b72b717364b3ad8b68688ab4d873db3b198d2e3468b95ee6d4f6b11cdf917f4d4400481c1a3749b7eab26984f92ab13f89010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8bd1aa8cbee154861dfdb1a7d792807134d8cf11f0755255384809f518e0a714de58cde268dd06888e62816986d72ca945678bc46d4197a12b9677fec835c708	1610722907000000	1611327707000000	1674399707000000	1769007707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	329
\\x2613fd0b9b4c91fc90ddc4d0b0559920f7148828444a2f306833093233da0512eee4532f214a60809bbc0de5a3d556f809bed6a50f0a399686e4fd425a0efff8	\\x00800003b5c56d0f498852cf7e1d36667935b2d1a52b3352c8d722d107cd5a12747d26ff36f4df24e9116174d927c2631644370a31bc1f923da7b9c359eb0a3fb3c0cd91dd2cb0d95d621a615e06c1c419998842b260c34d7795fbbd0524b7235a6ab652d772345549c481ae6b813477f211a54620e3da57e07e40f0f67d7021f6f86bc3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x58775e8d19e58fb2d96cb99d4239807dddb6728b59cdd037a75d6a7e4a75a75d3e2947d23138b3b458ea326830713386c56d2b0734d8e4a9b457402946a0cb03	1627648907000000	1628253707000000	1691325707000000	1785933707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x2c830c46ff2db426b5b19e15979ff3962ea500d970676e1fb265d08ed3da057901550d5f839ddc712724d6f57b5031a5b8598a28e78d8d819acef43f13c65aca	\\x00800003b06fcd97e63bf0deaec6e9ea484ad975c9a19d21bfef75e7eae1410c440b0a5ec9438eefc91463e15d4757b50f343bcee85937cbc10ea1a4120920491e414568a798b4d5d66b9a320c17349a0659ef664f9982a5d94afd63d347034db5f3e9b8b2cda0939e983d527ca0ee20ed97d171b8c805e6357d6fa094d2d139b69b6381010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7fae5e2833acffe6d32b5a8756f63223822f110523743a03e1de39e982691df9caa0b707604646541a8444ed936a36556d3aaf488865e2148150db2af49bf60f	1622208407000000	1622813207000000	1685885207000000	1780493207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	331
\\x2f737480514413237850275906cb5411295db2a8606c8aa61825c272fa2137414e9b7e29928cb9b25f3fc4cea1f9821d6a074a8b7abbd2d1191d18fe9d0960c0	\\x00800003c71a8ece35de8d8ab63d1df7f8b1ead3e03cf986f70a7c70ed1a277671b1a4948f37d328176dd9a338ee630c7f4a5aa707f7e51384f87e9f67f4dc2d615a091f8034e6e40294926c28c7571525ec38104b0f29ddf6a24b3f7ebb6991011554a2a15c6165179ad220c35110a9dba4acfe4df41e9f0383bfc30542b0908c0845cd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x85690ba3a3f0f1dd5f3b7d216fd61b5570dc2db2732ee15d540e32f7a8698acb935096e2e69cf20c34dcabc9f7aebaf9697154fcba3676798d7f7e9627945a08	1623417407000000	1624022207000000	1687094207000000	1781702207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	332
\\x30eb1e85542484f157fdc62f32a55dcd9eb53c885b0ad57cae276525e16027f7e5aa0c3ddc4a6c6c3cf9e6de3cef37fd3d6590ba7bf0b8aa3ee453e81499ffae	\\x00800003bba14b7ada05259dbfc8c100d596cfb91f8972327ce37317c4193423ff85e915537027fe3c8554cb2ac0c736f9b50c447f0b82cdd391428fa1ddf73ca481b94e1aeec5e2f3fdf4dfedcf766f254a007cb8629dcecd8716ec95240ec47729c165ee86f6952d13ba71c079a17bf6a50360893fd1f087ef3ec0439615142e409237010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa9e9f69cfeb4875fcee9ca1ba436f0fe5f561277918082fb2b0ef6b5b26feaa96b234423fdb58379f42dcc3381cfaccf22accb36dd6fca68de2ec0043103630d	1622812907000000	1623417707000000	1686489707000000	1781097707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	333
\\x3433d1ac43f5b01ffe699c0e94348bb9b55c59f5e87ed0ca47ada9d2e312a2c4d0e02d382ca466af2e2b6e934be607da288bbd3e8a3c1ea3ba66d504a992b568	\\x00800003ba7c91c69d7842cb4c9d308c53d2d1f8842e247935f0aee66b47cfc1a5e9c6b4276fcb441140c308c560a9bb6f246695f41c2fd157a425bd8962be6e1ea17ab54c2d95335d4e44c5a86717ffbc6b1ecc48b4d772fbdc4db7bb24781044bba0a04df619203c0645ea5886da7a6394d25f31a63f6db5c4fa7577b8316602b7d0e9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x921e1f9cd72f4558de5f1a7003e940609f3911b4a9a403281ada8978a7893bc719069935145039604502919c56bb5e1701c7df7582170620f462d16c50953102	1622208407000000	1622813207000000	1685885207000000	1780493207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	334
\\x351f00348658a249ac9b14a4c4fa4971d4fa5568dcd9202f1c5a93003783d79bd5b3de05bcb3dd48c26f0ce2362d662b88ceafda145433570bba5c66d27c17b7	\\x00800003de0b0b5f9f9cb65a9f15d89d878ff9e146c5aa98cf079d7691add9436efbfb7c4470115a25d49e99c2884b072bc5147361e032863bc07d44ba7abdc1c7158e336e521fb24a9c4270cb2af9f011702c24965461b9cffea303ef52c2548093643c0af615642c9489c1dc160c29236854d17ebb75ca6b2abcf74000eade695a9f65010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x316473d29d5f0755862287109fe80ec8dfd5eca6ce506d695c8a6b83bad35429d61a472790edf8675df79b5146a5541ced9ae11fddeebf3e3eb936671c43510f	1611327407000000	1611932207000000	1675004207000000	1769612207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	335
\\x39d3718b04558a451f7f8d75f06838805e7b43559bff4a4c8a3be4db714416831da9bb1b1a9407839a4a16d8b6e6bd8618255dcf78a75fc055fa8f1deecefd41	\\x00800003af9594a73efae7fcda5379f0dfc22b6e8f522c3964660876000b38efff3fe2c0d96375cd7801b5bdd649dd9d6856b8a80a0bea3cdeda2a5d3bfae43a377c722f3fdb1bd3713caf4ab834d40b8d49369e42746f9fdc52ef53357c7e1ea4c8b7b2d3a21200b3209c67362d7fe834e5e3279fd567458a40dd3fe678f6b002a8bded010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x292099356baa02634d6b37543f2bef365ded511b891997efbb170254170660372d92861db581f8ce3aad8f5a0d18bb29abe179c5ed0156154986512163006409	1635507407000000	1636112207000000	1699184207000000	1793792207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	336
\\x3fabced67ab68fc81e4e8d3da9fd633b30687c5dd5379792609538c796b5aa0403d792a9b78cb3473d66cd9950a76a23125670f14b194a8250109b9fc65c32f1	\\x00800003ee5cd7ced746a8baed266e099410510fac3329d1eb3b23a5f24b4dee5b4172fa4b4c00b7a1d110f4f4bc0381f4127787f6c5e92c018ebb9f07d894a73983eb1163f1a2d57d7688f80ea9cf939ca3fd432111b267fea735e68c3e17358fa249c8afbcad2c9246d163b1a19044e144c34130b143227b3b2faf7045b52d614abddb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x0d671db1d4fd5191bf3ecd4bfb2c60e7529f1759ea8c3fcade611b959ddfec98b1b7e516fc961b80bb75e733344f2598600dcf254984e644a070f744e015d608	1630066907000000	1630671707000000	1693743707000000	1788351707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	337
\\x423791c9fd7cb7cb86c0e2180d07ca466dd5a5779eee12ac61590f6acaa3eac095e43b964173ec43dfebed5835ac26e20dffeeb2ed290aa8ce79fbba1a2a6538	\\x00800003b2ea7f3a5320de86e7f86d9315b5472ca7cb4253d149146b160c4b22e0bc035727f180711647516c4237dcf0d41c9aab2c3089d8f66c814851992522c18d0f976c0750ff82e79891304c493b8c667601be5572e35adf81992170c00ed22903e33cbbcc10593862022241bbebdf7b8f9955fdbeb0541cf09f05a0d33ba582de69010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x59f9cb8e54410164da4937e17b0b6c8372f6653d8fd51d4ae3d64a1e2999fa973a7d6dda1e362e845fc86adab509cbcb4399eab14084a6ef61c0173a0cf65f0b	1613745407000000	1614350207000000	1677422207000000	1772030207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	338
\\x48c75ae63d5744c6c0afa8813624ea6ef81546c5c84a0d9550109be79271e4a289b6f2ec8db7d4e61b6020f137db469ebd22b8a956cf7d1bce7aaa8371e9c9c5	\\x00800003b754bb354ed21c14fc72b56608713eb1021342ba716bd7b49612e5e843a923a940875642644017c5726c0352515e6652fd3eb2ca98d8d6c876e1feb035eb898adb5376e8f185eb0cc7c34d9812da75310220355a416457bafcf7b7227698426960a4b1f0d1db075328cc03528a5b0573cc4454c9bd921f6cd12790b5f632dfa7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbb707c453b6f4e67a42ed376326c1c566ebb292e869f8e2d4a98f3cc328e43717a2f9b24d13c12a0518dde3fec3a50a035cc4d9174763ee69b59c09931b8a802	1629462407000000	1630067207000000	1693139207000000	1787747207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	339
\\x4b2b7b74865e20d68b684a1a9cf0c2a8ea68c73cf3cd2b86fd96332e21be575c9f7c94cc7ab00e4d709475ef1521a0731ab5f9c345fc37b2f5de5f35bd0689bc	\\x00800003ef7e086d15633cb7fee4586bc8003d2f4207e95fe226937682f81d8d3884c2a8c3fe94ad86605d729bf47c0c927d94d2db7509453d5dbd0e6363c65670af8b92fc887394eec869affef36e8f70041e83ecead646942048ccd7a5a6eeca15688a8f9179ebd5ec4517c6286ddb9e82c3449e263120c85db742a2509fb19423ddcf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x025afde4194ba88fc764009915f34c81882780d8a1839fcbe5f40611a0ca0697fd13159994ae6c515081132da825defb823842c4b36c08049ecd7cfef0aa7007	1636716407000000	1637321207000000	1700393207000000	1795001207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	340
\\x54435b81112201cd7f8fb849ce28d2da7ca17711c48540660c4a83f0d68987937ff55600bf9882c6babc176c35362e1a9eb6d2273facd478eb63ed42325ee053	\\x00800003c6ef16c52b86ad145d119def4ba77e4cac5cef90501488e2bf386e64f813b92a6786927104d82632ffcca4a105828929562488495b494adfa4c0102e9660294d4f0637139e7e00122a207cd303f65c3876d33876364331661b4bcb23b781ac2aee5470590bb3f4a4253f602462e2b5fb85ce7a2c44f58e0bae9baa6ec013fa81010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1ab07a316eb2d10d5fcb998a19f1fdca83119dfa1b492c97e0834499423cf16323521ef76eb0a8156f6ab61f927d7b7d4178607f3d5f58c5d969025b6e3d5d03	1612536407000000	1613141207000000	1676213207000000	1770821207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	341
\\x55ef793a1e8eaa131e94ad6a98fa40bdfd9fc96f10701b15411fe381b46885f59f5c65d2347989a0bd0448314cc004931669f264876a716c6547bbe6fa65b594	\\x00800003c5e8c2f255f0624b378a724ae5a68a53bfb54c92c96b16e2b3f39413f1f0b56909e1f568d2b5d96837a82798549c5c16555d0b2a68095abf79ef4c3424dac148a57a54c764ddf89901a9376869ef2c75c1dd2e95c6aa230797f046d91e63c8e941837d588ac6f15581d2522dbb915c2cf5bcb0bc68239757f70c735634fd1ed9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x460a24f7308a110117dbc02ade349d5561c96afd5299375d8ae82ab6ad5f76f043be5122ee623eba6947b935cc6257112be52c94f6dfd2117147a7c82e72790a	1616767907000000	1617372707000000	1680444707000000	1775052707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x56bfeabf99d87ec9f45bc1504295d0e0aaf86bcc221b4da75a30f10ad82af723036efac37604c1ccc3c82a21aa30ea3e4db63fa7aed19f47a4623a591a8d32f7	\\x00800003b616c7e28f351d29f12b13ab87070ec0fffcaa32af7f972e729917d18aaf9392c3fd2073c9d8eaf9f185c3acd50be5e062d7ce258f359a2c46699d0889ef8654a29f6ecd62a506ec032fb18bca9bb441396492b1f611dbe137ea404f144398beeffde315f95148198c03d74f2b43bb07de4e9f9cf3f2e0d0b59ab7952393e08d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf3cc942313c8e1ade36631cec6909c200411e7da25609b693b2b4c3c6dbb04a868f79fbc81f63aefa43c3c7123daa2d40771dbb91fd9bb38805d1c5598cac700	1623417407000000	1624022207000000	1687094207000000	1781702207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	343
\\x596bc491599891fc7ef9f1023f48ed77193997ab89f8583132f288aba775e9a25a2110aafc6fa0ebdfff97a2a5c0f2381760fdae36ce3ed2dd5f3d3c4349a2ac	\\x00800003b917acb0fc1239390c69438bb347f72eb70e923a5188712db8a11d9fcba47655071995870974641945fa4b1eb79062abe91d45578df6f28f21685127ed7fd9076479321496077ad14e8cf68034749c010474d6b1d5f5a81d34a33c488e01894da6b56b675b4d86d2d6f9610717f39b7f19edc9b2e37ac26412b32e98bd485da5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5e4209f30f956270e0b5954259cbfecc62a626c9d0c2d967ea403a074dffe3c13ded82ae5d39a772f79526ecb6a34b345247d364fcd68ba7832cb93885049a03	1641552407000000	1642157207000000	1705229207000000	1799837207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	344
\\x59db9656fe76f43522ee5aa61cc1fedb9c9d7426eefcecffa4c5d66c06040fd03d352bd1332b40b6f8dc85a8d9bbc291c5083ff9702be579946a0469f782ec7d	\\x00800003b7a5bef898e8d23850c52d6175246a5ad627f773d57ff34bd8d2cdfae19cd7ea8a09394a4b05f550e1caa28da15330493071248fa182a8ba149b04e48effdacf6609986f8533f7fc43739709efed7d8d04485e7bf13b8f4ff1aee2c034aa9fc2b8032b9373e0f29e9c47ea2c35084acff278cd7c2275800671075d43554d1d67010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5fab5461b9208d3f5e56e8251fd00b801e5140ffb5dacb1f5260d42a7ba3bf2fdd80bd8f5d2fd17fb4e326d5b9f130fa7c79a6f3952e40034f28024ea97e2409	1630066907000000	1630671707000000	1693743707000000	1788351707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	345
\\x5b5f6f5d86e521123de287b21f6869dc078ce168cb2c7aad65a9009af767085fcfff2b7cb90df1b728f7dec751ec032734c9cb991994d848339158de8df1d039	\\x00800003dc832c86ae39cd2bb18bc225c9882cfc340a524595497c5f67116e3340966ae4d8a7fe024669f5aac1c3990d6f053f3d508246b0b8b1dd6d24cf551c1416e047c9a4d243cb5d854f93cab923b13ccbe26c1ffb652358425d860b85b26983e45f1c4eded31ab2f822b2711eac356de724b0931485f68732230f9edd64e38507b1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe2f32c26928204ca239b64affdf521aae5532a2305f7bdf083f5193cc6d537e7d26fa4f8ed54c165310d53856ab7ea79c2f0feddc6f60ce186bd1d47eb4e4507	1611931907000000	1612536707000000	1675608707000000	1770216707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	346
\\x5cb332b565ab911e0970033a10ddffff936f68d3cb609a1a7b69ff9e7a75e4091eade7e8c968db5025389a73e2c8a2fd13640e571bbe07d50457d60832aaedd9	\\x00800003989cf810927193e97d0023ba06ed81fbc8ba315aff3bdb51507679fc9b9297768dd0c62a40e7d0e85db5d05b5aa8c90a0dd92907036bce349824f35e6b2b21c1aeafdc47ee50cb59ae362669cca535ecd3911e42a6cd23bf40525af15fbbe8ea863a33c90bb068a1f4c1a260c357c3f7450d85295e75c4186a58204ca9a6bba7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb8e999af2639ad7389ce0cad7b21243956ca8973f79d4f687fede8cfbe869d215aa44e34b6b3ba2af21ba2280b11b81cb8685c38e0925471ffb258295e89e903	1618581407000000	1619186207000000	1682258207000000	1776866207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	347
\\x5ee3c248ce936a4458210006c173d672af2d12075ea4bad9fde7a53d28e286841044df058b3652bb9f3f2e8d6893e8e74e08bb42ba8dfd867d091b549f0b2267	\\x00800003ad068812a1575fe0b863f712cd329b400a83d088c1a2a9505f4290d7e32d120f72b65513005acdf07f846750676fb746a152100aee427054304b33ff00779df0fb1b334be1ec508e201a239b1886adb1525593500c1362b1453d37f1462ba1f803c2eb9c8f0114db9495622e48b70499aaee45f559e49d7961ebd84ec9961de3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xeb103233093a55a7e3eb9e4757479a0ce4b1f526e413175db417521b33a188c5b8158834e53f411a2546fb62b8c94524db6e68b1e62d10b110b5751ed2ed0402	1639738907000000	1640343707000000	1703415707000000	1798023707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	348
\\x5e23c0ab53ec13a05c751f74cc9e54c8452a6f7bddc443e1a8bffcad1e4631fb39e5941050d24267fde19e29cb904e0f3a1dc26bf99a2a8db8efa89219bf06bc	\\x00800003e4f111cc18bb5347da774895415589a5ae12c1b50edd2d9951f230c434cf0cadaf46a5f0bb773850f6c4babe2ac824b1dc6f386ec8c5d814e6c60f2114b629da7b105284b1277892e286652554d98ba534760c7be6286b150ef9cb66446e24be92e540f01100eef0fac0d946d8b536098cb18732eb8efcb71531639ec214cde5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe241fcf4757381be62c18cd3691966ae5190396d2158386c8e02f079e5fb8602a9f9ead989af85a8965672b35cf43487f2a5e212500aec4301d968023aa3c609	1634298407000000	1634903207000000	1697975207000000	1792583207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	349
\\x630f2df68401940e29ea7237fab8bfb002a1a8109e74ced468b6223970d73d5878bfdf7733b41b6cdfd69b99df0d036b6b3a33eb928a1781ea9409b8d8c2c39c	\\x00800003a2fc4e4d22e9001e7dd0f0a65f6a79cf663734e3fe01c10d3a651c8c31c501c9b7cdab0b0f03963d4e4d0b29c64aa1f754107934a0a987c5ef5b685733c3abab0e34aa3b53d8bbe20aca7dacc68d85a381b24772f6544d5c2c491c97f81e0033e5930478d68bc0e7a1cbf3dadef206f7b8aab99558a7209b85fa0956934c0d19010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2f46e6685a83d00580c3cb9f5bbc8af6ea32577bb5d5b2275dc20d8f540a508b8919ba8bf3a2bce7bf3630569302a3d1a7bdbdebb5b1b92e188dc63f2d86f903	1620394907000000	1620999707000000	1684071707000000	1778679707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	350
\\x65637389a3d32d797397777660a2217c71e71cb36b728405089715215cbaa293a24a3564a2f1bbceadf6c654397820ddcd795196462ca01a64fd97b1ddb6c9a7	\\x00800003aa3cae8e0194199a7c75eba1e46e5cf56fb1c8c788244cd9c5eb24318a4bcf5179c72935f997dd94443c0ac3e642a4b8e296bb65e3af8eb3035fc5e7a65d74d4bb517392e4e45bd11d7108d0640ae51b297d66a344e065878a00c891d138f2e2029e31915c2ce98487a053aa0309b0db8e04a91f089bc08bd64154c3c04bbd5d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd53d4effb61a3accee31abf3024c3dc83eecd5a0bb74c0927caf9ea606057e7d189a523469363830c2e07c08696b622f381fd0e2dffdd3836d694cfb9ba43706	1619790407000000	1620395207000000	1683467207000000	1778075207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	351
\\x67e7a0ba98ccd3fdb24c8ec031c341adff626b0064e09e9a22e8f2d853214f33b194866d3eb89839d3583628e3460ef736e22d6238b6cb79e028f4255e37fe0e	\\x00800003a4faf5bf971303a50299c8110aab973f13ad5a6c233303980868444f4059f21402dea995a8e5b898900f614becb867c97f0a1ef7c868bd1bd9be39cf468e5574fa5c40a23170019c4fb15e283b21a0d607e33697141b7dcc74258dcb26b29ff96a0867d979ea9c144a845532647ba81bb725d30cc794a279d5a5cd1a04e1f5ab010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7051e824b28a6ebf59a96e6f865a6b1260fb954b250da2f5b46dbdb1d5db4dc637854d5550f15616dd4a8006eab6fed0ee3c46da60a61c7c76fbc4064714f809	1636716407000000	1637321207000000	1700393207000000	1795001207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	352
\\x6d3343c847bf41238070f1a9855e203baabdb44a144b3207664ef63eedc53f57cb09454c4d4561a7f6d565cd7f4488aba7cac0e26085269df0f9e369c1346c5a	\\x00800003cee5355bca97b4cfede45cf7149e034027353b54977e21a3b39be37657e349770700b9f0724329a65b81b67480fc8676b8492d77bbbe9121bb4636458241fb71e87cb7e889f3313c82525d3b5c5748b64dd0a16f0ccf68d1207cdd7f9593fdf8ef5840f86f96c00d96617d752352137e67edc56aad2bafa63f4f409677361271010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1ff4ba563c2174b3ed064dee564948a4238c6a53bb806ec50a6d17afc3236ba05fe335be946dd8811cef02897c339b714a4706657697657f05b236d91c89860f	1619185907000000	1619790707000000	1682862707000000	1777470707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	353
\\x7093771c1ae596eeccf57319332488d5afc67b90f9e441ff6cae48fed1962d5d40adbc69579d68ec7da9fd3aab206f3aa1076936591129fcb1466bd44706ca5c	\\x00800003ec259ce7057180753cde5a18ba0f20cbb6ba81cfe1da0c48b563a24901cd4aaaf71e0f26afcbdb177ea5690a8610651584729d4eccb4380002c73b7cb20b5ef273ad9fdc6d3ee096c10878bf650a847f61a8cf13a4e20531e392cd6cd1660615e31e672572574b04e7231d01e65e1b6180f3ab8eee60f5ea0cdab4292ca9dd8d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3ebd3adade93362d8a0b0a21de5a74409bf6e7e06a2ee1dc5051e64c33ad9cc8653ab1d3cdad249e4fa52c711dece9725c9536cd3ceca89c4a3f6a9b35ba390d	1634298407000000	1634903207000000	1697975207000000	1792583207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	354
\\x72c371747beb38d39ce5bb12fc44fe2de5fc908210cba62e818d8e879f1f55b49ba94b3f1e457422f52d696a61ffc6068619469863f897c72ab4cb5ce147033b	\\x00800003c177ddb2c7cd3f20ca6916325103b29feac774f360cd81dfc70df136ca487a82556111528bc23666c5e085ddfe498a54fd9fd71d8aef06c498f77e313512fb7f05bb55c97fe759b610db758c20c1a0de9da69be819e54a59ae561bee61a9659437cd025841f9e94efadc83ba34b89778bd29ed1acbfd3c924e9a69ff997b3379010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x864eb863a6ae60189c3627b2ba83322130d252e268fcffac90e412e6df5c65ebea2d6fa14fbdb3590db4ea2584b1b7ab69eb310c76344e0095bc09c738db8a03	1636111907000000	1636716707000000	1699788707000000	1794396707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	355
\\x7b7b8a18e209e94334332a7ad8ee51dfe7df6fcfef308cb54523204fbc91fb4d31f098e9530745143a6e27485ec7ed2d60365a75ecf4bfd52d5c306d14951244	\\x00800003a65c29ccd463fa66c634cea5d8d03086604effccd2b967c210f68e2e00b5b5af9b5a271b83deb39dfd31453c39ba6bbd7fa5b6e2ca356050db46a8ead980f2f19153d6657d76e0dd35a3ebc1973ea9bcd9aa2d5616bd7423a481a604e45cfb2e590f4ee1b5bf380708b67a76e8a8cccba417cac796c1fc1e8dc54911fde59a5d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x34c609e3a9a2bc45fcf0accf14b2a61eb06fd6c9db38e9ea7d5e23090c035739932fe430a809691aa37b1ed029d6c7fea1d39a736603c3bea9adedbb1dc2a60a	1619790407000000	1620395207000000	1683467207000000	1778075207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	356
\\x7f3fe48775522faa769d5787cf0de7f7650d5fe0f0fc9b6fd93c602742b36dfbca3e3b2fa859a97e6ef50b1730434ba0d8b3f94c16ede5cb0ee4bd06150da209	\\x00800003af9e899b346a4e2c37c5abaddfe63b7c6b2a76e5f1ccd2a14976770c390c047d598c285b72d76acced8d50ff6b78542fdeeeef838ade1c7d217a7a79595456b80d34699ada25d3f8a4cad0496f8053a971cb12c08bef74fe02293f3c0ef52ae4417b128afaac8dc37fa31fdfc2cbb0820211581028a8861448f225ca736f219d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xdc23568479c600bf9c37db7ade7ae174d3507edcc70f62046849daa1b7d2d5f2bceb661c18eda8efa2416abe4702f410d8e337af432598d0065449957d778403	1618581407000000	1619186207000000	1682258207000000	1776866207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	357
\\x837725b1c4c244354757ebfadb033f53c2584999e7344ee446b3b09b5af4e35c6230a1428d4706b9c910f2c89530b3b2f770fbba194b11aadccc4ce1bb5a4f89	\\x00800003e5449107605a4db774fd877bf24f0c05d2905523fe70008b83649533165c6f4025d2dcd1ead1fb526d1d5d1190b5f42849c2fc02843335b49d0c530acd0c5314aa511fef7290587866535f45eb0ca8a4bc1e53a618b6f14d09a63ce2ef4e51eab75b52d9b528f380fb7e0bf70dc4ed0562a75dd6272b16778537ec018c6cb461010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbce0fd3b97c955b29065ca36603729ad00a572ff9c0cf8a231b13c94451c1d09069403d234fd5028432f209537af3132cadab27c0abc7547e653972459d4c506	1616767907000000	1617372707000000	1680444707000000	1775052707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	358
\\x831f620f639071d870c209f946951e186a44c87f79e02c16addf1a2f1cb706f6bcf7de263a0d159ae6e41d707b375b1957bbe3b7c51a8d73485e330e5fa455c2	\\x00800003b80a1bb8e7318382f27ab9baa10ac51e4772c2825c4dc9fe0ac00b249447ce9fb3ab1a2b7ccee1908ad4155031e08226487e7da4ab8820d2d8eb87b81112d3dc6596e6fa4bac714eeb66d7dabf7f3a9148ac658f8eaafe9653312d0aaebaaa5dfa6f95b4436188caf822370ef9c10c91e9a1f3eb2ec3397e81201f5a0885fcc5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd11196b5cfb6845c0ad3a348be20769b35f19281c82845cf536d5473c22e152086e492e40637dedabd74d49e52c471ce71934de6f43532ae719e4841a3e83306	1619185907000000	1619790707000000	1682862707000000	1777470707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	359
\\x835789a8acc09bfbaea40acbad18baf4007810be0570029e6b09f1dc4cdea76ede4f4a721b9cc035600941e37e4d8b80c520e8db49d97d1b7dd20ba25d63bee0	\\x00800003da49d0c66dc0b0a06c5e8d263739866896dd5e77bee67ad093c83cc7359725d74d0663c7bac132adcbcc71d77712061d1d3fffc9958291abdca6d5bf4e6a6b48591293d34fc259d3f351ac61f8ba73d915137459c6ecc75819f388f69e05221328e499ef490ee533fbdceb0e79b09a414b7b318d48352cac0672375613e50a3d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x55d5cf6fc854b0a0931c4a871a51849bd258e5427cfe7f0c1df7de850dbd17e371b868446368ab10ae7ca930745527f7f2dca3924fc7c922f788b09424f25d08	1638529907000000	1639134707000000	1702206707000000	1796814707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	360
\\x86af2c9cd3fb08543bc32909acdff6430d8ff74d9f6c3890ecfbc5e6103bb861a351ece3b5f07d92e2247454483b61d2c2c96a51934c3a34b226b85dc8571506	\\x00800003a30617315006d3ebea8519798760a35131080a550feeb1f7a44a0e5924fbb250702ee7f37b096a83b12385df95457a1e441b779a5b1316330930f0940d30f8b6d17511090a3c7de124a321f9c74a445d1ae0a4ebbd3cf528df225b70109fefb7099e090bbd69b6e73e47dbde1ed9c4777ab120dfbf821999fbd85781878d5837010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x86f9212dc6d1b57990f5c642025e510dc70ce7f984efe18ab07d1c095cedf552271b725db1fd0a244e60c491f2d04832b3d008e7e6ad422453a233831642650e	1626439907000000	1627044707000000	1690116707000000	1784724707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	361
\\x876703f91905e225b2e6ba047e45d06d9d5197cefcf0e399cdba20615db5e3db75decd96c808bb313e162be1eb228716023d4c31ea17f72420163b7ec848114f	\\x00800003ae2029a33ef27950f42f43a053a3d738171444d1b043ee5ca383399c5dd0f2d91947058fac533c159c95de3ec479c6f1e454f501d1747b2fb64735d5e4887d99930cdaa54a0377dcbd5ce1de9245c461d11d0766d3daeb739de7f350baebd377a1a7e2986abb4a68402f2800c7753462738ad7f6ce147e5cf0d751cc4557931b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb5fd2847850c2c08b6a2f702423bbc824fe72e1b7b009bedeaf5d2cbab54f2a488eec43fd734a2557635e10fa97ebba924aa6bc80d16ce903a5614b079741b0c	1617372407000000	1617977207000000	1681049207000000	1775657207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	362
\\x8897eb891aa3b68c6ee49811cb73e0d81b503c0d5c81f4708a08544914c43d3d9f06c16a9ed7fb6059b04e5175971df3c1582b63dd1f51b10ce607566194cdf7	\\x00800003b6a8e4d23d1d0eb5be07360bf3570e165649d9c61d5db4b61a1ff95b841a5ec039f3004ea8b6b3a1c679fca01aa991691485f99fa1a14275bfc7ab6cbbd3ccccd1310a90beb54b119a3a1df3fd60a8b006fdc930decf537fdb7a2bed160a2d300cad41ad1c5e2ee19c362c1c439b0e0f5811ace648f7241e0eff117927d9e033010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc689b511aeb13faba0204cd296aef79f316b44e7a7a5f6468de9ba72d42eddf14e97827eddbae2b574d53d99c40bdf18c4b44f3968b4c375945c9a798bd97908	1632484907000000	1633089707000000	1696161707000000	1790769707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x8a1f8771b2aa5e08f53e922fae779f6517547c3e75010737438ed7435b897dacc45eb43e6d9ae197bbbb214011a77d42e9e286d7adfd4ffb3e26500d8ea64726	\\x00800003b16cb6e920e8286e104a2e25d6affcaccd27d8a8f866fd25e8c406b7b4231e4e0d6b8ed82974e5bfb136db9d34362cc85b4daa75d6d2c92dfc8caf575c5c5d217dd6bc6abef84596a6b07c02d933d98f704f3408b471e2f6787e5f4399d4b4bd63c7b0f80e0b3769b8f6f217692969f88e444e8c6ba1f84131fab10e478d6df9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6e98fe41485a391a2ce7eccc7f9d5d4957e573f3c7ccc6c7e2a3f5c5b08d1da3d59e3d0cb1b4087a7b18329ebf9a645e1d70c764bbf43c4e3e42fd85aed82f0e	1633693907000000	1634298707000000	1697370707000000	1791978707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	364
\\x8ac307d4393a31245adf0bcc2a417589f801a4d1e3d016ba9dfceb61a3e395f17aa2d5f25ebaaf49b207ff9fd9226a1450886d6f47ee363357a981d7a7a26b81	\\x00800003b1293c2e8a399f69e5efa0664119f53af057c53f05435280c0f48dbfbd77d91be7a3372f9d376c0e6ba2f4df179ef735c556b3710674c8b06509ba18ddd04415d1005984089c9478fee931536158f834222b601f188b2b25a9453ce295923c2c1e8a2b1499bfca0696840e1e0e8f52c73811e43b9e42262509233f13c6cb6213010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x18fff26611be13b77986918a870ed43c9dba01170a76f50fdaa1e47f8ccc4177d39650542e96d7b6fd1106aaca17918047ccc142e9108318b907db549d1b020f	1632484907000000	1633089707000000	1696161707000000	1790769707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	365
\\x8caf161736c58e3205de729190282d891ea4645b45554380a35a664d519c54e16618fb128026270c2b9e1d3868e8beea7c31b489d220d2305b0567af4f805072	\\x00800003ce883f2b1602321e77aee471bc35c117b87a4003fc7a0bf57eace0c9d4f1835ad7893f037dbf88067a386eac4298f3df0bebc53afcc470fde37674d28c8f8131e8c58a617a11e167caa28240c04543aa79f580d626931a4b6d4160789ae978a9d0750603c361b6fc775051f9cf3dd5c25c17cd7a4a3ca3ebba05136cb690bc5f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x607ea3ceefd985d38a9aa846557018e167187aad7cfafad3facfad6e4bcbad79b488dd4b22683671eaaba532239426c4994957c104353d100704831f4d6c2708	1634902907000000	1635507707000000	1698579707000000	1793187707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	366
\\x8fc706860b394466192182e2ad4e2c07aeb9e4c4984ae12cfe5700a58ea4a7aa7a0a4935ca3bb49c8860ba73e4967db9a9ecd1452611772ad8e26d7585f0ae6f	\\x00800003cb66180da889937824c412767af5d3f363d3ab07a9d0b4b3611473fbf0ba9669f4536541d8f9f87a1f5867a56e518605f798ff2508dcb92a0e5e376be5e1655317ef898907285b2d8fdc04baf3cc9f77b2bf8d94ed36237f76d329d57b67a681790d21db0877f0afed77f272339c7ca2d2213231bd13d1e23548fdb2935f0761010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x241cd1e0dce5686cc1104e2d144590520e1f7fc4e7b096e4726bde03a4424346c5c04e261ae526100cf440b906cc0f26777df5ef185112c0e9ce2238554b8400	1633693907000000	1634298707000000	1697370707000000	1791978707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	367
\\x8f6fad169853b139e962d5ad0660dddf54b19b141d7a86975cab7dc6b68d71b23982a65eff333a67ec269cbcece029e23417085b0204fa285c3c6473a88d2189	\\x00800003ad3bd8ef798af3e48d19da941809b3c391636cafa45ab6fc911d4b0487a82c220fed444951544862f95ac605ff289ce226fa5370193a6f9de3abd35f3865b14b2c7c0c612852197afd233cf4a52d037d2f222d9ce6f2a6be0f7daf61192db70d858acf9988df2a2e8f1b11c50a194d1022a4a759e184db3b514f992cc53ad1c1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7df2410c0a3e277cb0eddaf3285229615f6378f433650120f867cda004cbc1eed505956e9c3813916db5fc41b136b6c2a6610ae039b0b8692d4dd41e20c34c0e	1617372407000000	1617977207000000	1681049207000000	1775657207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x903766671e66dec0c4b16c5eac5ffb7cd2ad4baeb10a396255a45b5f00389c65bab02c171d8d77dfe7b3bb3a739f926f4b45811e03705b6dbc4f5ee39bc30569	\\x00800003d706b39bd97bde0f53995b1146553f882294f299681d3c6140648c30bed789e287d8372c760e62b2efc5b9e0c7531de58b136c412d3cfb90359cb234ca3f162ac9321b628a71863a67945745038a96cd23586d184ae8957d5f82ac83ebd0c8d081e1b9a93c7c702491f89815a29f94919f8d44929e94236519e8204cf6ef17bb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2ca6c2363453a503ce5a62bae157a2b9eeb32dcbbde6bbfd1484fc5473216d4e3aeeaf981ae441072cd1e0f5e3a17a36e1ef715f2987bbb1e3f85369256bd50a	1616163407000000	1616768207000000	1679840207000000	1774448207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	369
\\x9287c9cb78e410d0cb75e5a7aafdf02bda9f4d5855de4017f5cf5b29e12a5356691b6e28c8b724cc292b0d39440a0731795c6d9d386ce1b61ae0c3647607b16a	\\x00800003ac16821233fbed7e842674ad4489b733c695f4e9cc5b97e15dd23e204e8324d7dc66b4402f51a149779ff497ac05bbcb940f7bb96c35bdbe4d25d03d6ef05daf05737e98e919f16bab1fe454f716c736a6c6a2fc9507004a7c1cbab0bacf12d0c7cbed0b839fa09ca3e2ca1d028d4c8e6b2fe1d9441f9a2f40e4aa714fa501dd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc74a27c711d60543ed75752f14f2cb1fde33b22f87cd7c8ba64edec77495488311fbfc81e26f43bbbfef20eef6c18372bd98f81e74a10ee7e597e03f4a8b160e	1623417407000000	1624022207000000	1687094207000000	1781702207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	370
\\x930ff453973a21593e1e7f367da437eb49666dca8819e8bd262278016fdcbaaa1dbec763a67d4c97be430abef063297488716863e5034f0093349e705929d576	\\x008000039eb499d84fdd11188a78ef07b23f7968b988aede0bc72e8dddee2e50769a0d449d783af1166b85ea6765d313bf27ebb5c7dc303d4fbab6be660c25846bddd8f2177294bd713529fcab8a88e6c997cbb5b537d28dc8d03ec0fbc93fcca2aaa618d3148907fd3bd153c5fe59c309f5b1b7196106e3f81cc4b88dd6a6f9a6d32a13010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe0421f69aadd3e094dcc651fd13e2e6ce96a073f4ee53ea604899a0efca465de9338b56c7edb18cb3101c516622dd3441888063efe1787ea1e67b633ddd8c402	1627648907000000	1628253707000000	1691325707000000	1785933707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	371
\\x9cd3e8f2e62d17eb8089ab73fa7d38801252e3c3f8bd4ca8eaaaee319dac034bc1f498502889f73ddd4ae662753b6bad7ddd8cd2c06c8844c171cd87676c3730	\\x00800003d8d28b2f9a38dddc8a587c756d66f4063c177402b979259d58e5f3801f7a4f6b1e7acec4a0cc93612c09b2663baf19683d5457511056c9b467987ee86672a697ee1605c34b1e37ffa7506d8e5ec4301dd89adc425c46fd91b49dc64fcf30913d57f1354e15399732d8d428c28f55ab0fec174fa19a5a01616a6128462c7dc2af010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8689819e1c268b35c9a5368dc8188c6d8c34d0f87a050a6eb829db55280397a3239dfba20e38635f2cb8cdaadeaa425700e56de74f7a84a66020fb3cbee1d80e	1625835407000000	1626440207000000	1689512207000000	1784120207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	372
\\xa02f4189088a7bb3ab50e001337e826c3b67f562d51feb053b45acc2bcfd023ed478079fb707d5821232ce06eb5ef21a5109e9e9d129e474637fbc15734f70e8	\\x00800003b10d96c3e1aec2bd4e0d80e46bf08a7b6ff8a16612dacb9a868a5b9ebcb60f16ca72de3307d05d0211e4188fbd0312b2b1155f2c254a31195d5317aac2e5be60985b276faf4f17f41249715884f2918101956a891a1cc1259c6aedca03113b03cf7cb26cb33441668b639be97fa115b763ca3bdb190d1272cdc657fcc01bfc49010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x37e53dc2c8a3f73abcea029b2e57674d5f699ac3a802b26038dc08806e83c47269ee6083c219ce28be53c7349884ab3297afbd4f05314c87a5b749d1964fc30a	1622208407000000	1622813207000000	1685885207000000	1780493207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	373
\\xa36f0d1598c208b6cd275ce83d2ca253542a4d24e308b2fb005358f5cb30c305d3a30ec39a168be90a7e66aa3996b7e96bc201b26ef19b8262f01594877443b7	\\x00800003bce4864c3d7633053394d6370d42bb3e92c5de77ba11a1fda397c524ceb6f18c87eef1edeb5dab10ec124e9b98e89dbc88ec19070c450cb2229b93bee9869a58227ac09f2561dd31b5f01b0bf7b5b5cd8fcfe2a5a23674f9dc8d9f0014c9d28af399d4f6cdb6ea1cd341828bf7caf6be6683e05bb31b26a25ffd54f21913b811010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x824b7bab2c4fb05eb2116f34f184cd1669d17e82756b7af02c848a79dac14ab81c20cd0bc349f889c9311f5edda0194bae568db693194e37a11579eb43edaf0f	1629462407000000	1630067207000000	1693139207000000	1787747207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	374
\\xa4b7a8c5c5a0cf9bb2ea58806fd5e1313db2b20ec9ead79fcef70d570f6a8a6a501ac71000db546ed799a17015b485357096499f8070d9267f0ecbfb2d08481d	\\x00800003e2fb0626ec398bbbde8a9fffefc6645a87170552490894c67b9ed8716e5aba2ce2bfca5ca2fde8fb355a2c50e4c9ac5caa060ae9f511940e44d2699af0fb8c7d60f112f45830c5391c2ef2dc3e13995bbe30457bb7f6b03c7962e57059c0e963384258a5e88187e76dc112e427bb23aef78ca8e7ce89d771547388162fee760f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x26117dd2f6ef7ab1810f6ecef88f3a0dbe66c70e9e3f8642ceace71dc7c1e6ac58fcf9db39739e54d938165f41229fd5bab856b48ab618b418bd65cb92eaf903	1627648907000000	1628253707000000	1691325707000000	1785933707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	375
\\xa5eb4de228bde54a89faa92979d173f4cc47995b4eb1f2b1e376f6e9fc844fc85b57a6855fabfbc78b0a4bf8081dc9f28b2e10472e65d59d3b9f93d718ef8d24	\\x00800003c7e1e884470f89dd267fe253b02d5b5bb3aa2a017ca347e94390be7ba4f4a122349bacac7e961b6591ad3c234738b9ed880683bb62fa3d50c23f000d013ecc79c47cce24cfe58945173d61bcf3dc9cf86b405b57f9053ea1e0bade8385867db3b2f498c8a69c21817f5d277ec646f99b651b53f88bd9919bf21a466d31c22027010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd9c42281a612c23550b689a8db3ddd88e4eeccf3935cd7cffc8533b03845f24b07ae8edca98dac89a4bbc10397ea87c54416949294b1d2c5073f808436725901	1616163407000000	1616768207000000	1679840207000000	1774448207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	376
\\xa56f7da498236bf23f0e06cd777f385d3186a41729bf6fde85153537118806cbdc14a1efaf348249259219107ada0ff7a2d9db5e079a3fcff77fd1530844c264	\\x00800003a8ed4986b710a97913a655e87786ba8ea53c51ac275fd8730898a4457a5ef63ab5379700cc45f2a15269bac32f2300c55044ee161f8ffcb7e8ec951acbc5943f7dddcffee62741d0c16b3795863f4eae84f16c7ce4c5b6e08e13b91674c2a8d31570e13f89c2e7962f2b32fbb8c99a22dc8a7a3303f20165b6c70eb5bafd9a07010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xbd5f8d0ad32ec392fc35a6d7228458837dc4c5f4cd21cd6b7537a094edc0e7717ebc9f092f49b5f30ad84b261486217b2fc782f09777bfb7df165d1a7da9ef06	1627044407000000	1627649207000000	1690721207000000	1785329207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	377
\\xaa1b88b362403b58a7d9273c85e705d0d46ce2b1740ad9cb629443509270ff8d0951bdd5b9fbaa2ad98c01ead2b5da286e3e38c3060b8a0c8c36730fcbf23703	\\x00800003b4b196125e2900274ad00db4c8c3d0f5f4435e9af3cecbebde741bf567e3e5cf7ccf13845c6bfe3213cb2616b23a5f430f85bf0551aa4339b6e2c225422b98519d073fbb9498686951db932133b1826a42e12672c120a18beec026924c5472c8c8f694ab756490d23e2ede55b3c8814fb136072acef9aad095b3f30b6fc8366d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4847392d848e49df09d25cf236626e99ea22591dfb27dba0ec29f6573d00450575f9b3d72d3c754a1dedf3d7af6f9168ad062522dbfd679ec8df3b9e8feb890f	1637925407000000	1638530207000000	1701602207000000	1796210207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	378
\\xabbb2b707764ba7175d7e14af164b9cb9165b361eb4fe1f6204e6489bf1e387b60469f013892b33eeff5fd9845bdf0cdc16f2df0b04f16a003c9886be64d15a3	\\x0080000396ac83d3089fb6049df011fcaf08268d88eaf6f13f8e1c80f5f3224f3f62faeec04c58acc8e1df7f4ddba38626bad80fb90f5a7df69dcff91bfdc55921ceaf3e8693b37bcfa504b8c45384c5409f89ecb79073e90ac3fc7778f50be9da8d8d4b8001c2cdaaf2cd088db34a5a26639cd49030d635a98c5cc73f3e1707b7a695bf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd9d2f1c8ee3aad5338704b8b7b4e95b5f3463d192af31bc140a7f292991bc4eb20b108fdd9285389e811de98a77158829a057076c2a10cf86983d9449b23930a	1634902907000000	1635507707000000	1698579707000000	1793187707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	379
\\xac8f93696b67a8325c4c255e90a2e803e7803af45debe519598a31d6a0b3bf4adc950f166c6f4c1ce43c3a2b7f017544706f2aa523f2f95c0cd07ff0f93ced03	\\x00800003c3cdb86512aed83f07c047e246748c3c5f273f8719e8b5f1e3bccf30897ad571b65beb44d636a823219886b7e4d5b22554d97ca9013df03ee5200e932ff202462dcb9aa19c7411501f28dc19c6202994def4d75609b788277d3d9598531d466f5ee2756ebceaa31d3a4c1bd349d32e7bbe7f97c644a21551c519c19c06143cbb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x55f228f8676580a42b052bd412f20589a79604b41944f8f023a8ad55d43c3c93b270416b1df0995c041ffb98ea240bf51d329454aab76912de1e92fe14f9c401	1614349907000000	1614954707000000	1678026707000000	1772634707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	380
\\xae03955a07b2111b05ecb6eab5a1f4d1b8e9038dc50f1de32e8367fc95023a184d70e8bb8cf12f996b4462441369017f02d32887aa08e78105e46ebc1fa9ba91	\\x00800003b124d99be5a1354a1f4037d3ee38ac40cd1f51402a2f1718aac839a054b90266e6b9c4364291dbd118481f53fa8e33dbf02b870ee82a4336ffa5ef1df16f99d302b1c5ed8bbbfda9a23a8c576d97b071364eea43e7a5d33e7677e5319246a580b3823933bc40939880da70eb6938706f1f45a50f88085cbcad0727bcc4ed4245010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf7b4d7049b2cad33ee532eb4b2b6e02060d58a0f4c29c1e29bc5c3be30289fe164b3774fb185a9a590b68d428b8990323bc872f7d01c17cb3d868b84dfc56808	1628253407000000	1628858207000000	1691930207000000	1786538207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	381
\\xae53835c02a9b4b8eac7f5fabd4eb3f784d3108eab6ad74b51e18c0d76ea40a700a052a55e936760560f20de3e928a92288b1fe982c01ee84734677ebbd20c1a	\\x00800003ad26b2a142794fb06e2002e50ac3c7786fe3fede92266b40e46408859ca564ce576fa8f8a095302ebf20ce1b4cbd03b723a7a7efad41118e71e4f34a6cd171e11f0d329641f90e23b1666ce9ff5359e8a59326a934f6a4f1823e578c27c1ee2aba2a043418bd87c5a438af7c5fec6bca03637deb315273e6d923f9a7a421a421010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x3a23cac9e5cb3335059c3de0605d393542c4b27aac93fc397f7b018dfe33f946a233cee71a7083c259f8ec03fddfdb20c5fd8531611092c5dc2b79ef01771d01	1638529907000000	1639134707000000	1702206707000000	1796814707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	382
\\xaf0bdcb4aabf14509ccbf28fc6a30aedfa98a88859e09c930c8a1476f993cdb3c91f38ff2593f90d81f1222b60fd898eebb4f1534e2d1cfd4fc354d627ff6942	\\x00800003bfc3063478e33b3932d66f48fd7f75bfc015a3419b7843dc6373fd95fe63115bcc631605510c00ae9155c3e686fd1d2710fc175e4d1e5fbe408b0f5ad6fd3ee536cdecb8563d74960391a3ba882545fc2571ff1b73a053f3bb4228dbdb847b3959427ccc142fcdb3ec44eae125f5e914470ba1714ec80ddcf6109505381a2e6b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x261db875d08d9379cf5f7dbae8937db6699af29a52d4c0c94f0e67ca328b97586c060d013d6eb84c89fac571e9cffad3adef35780ad54a0e256f104d29bc2f0d	1611327407000000	1611932207000000	1675004207000000	1769612207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	383
\\xb063045ce1aa1b14e872157f5b3e5feb338a0c3798c0374ef0f0cdc4c55cdfb2e35a1a6cb64dc980adff6324c01144c20b67250cb7c30a63590046573e56863a	\\x00800003c3351282aeabcd57b3d14d0f18cf1e928a01d1ee212abea4cf54da83394d7e9e98de992ed6d03757c32d92f0ab6283aa4c56a9cac8e77bf2598a8e7c1428c04c374a7c5b9b1d520cf9b95089635268c7e852f26957213f7d6dd2f230eb57c7b557d18ba27a998f788a9ce2cb973ce905fef711bd3aedabfed71ddd708471ec4f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x1f6a96f41a468a4ab331e2179d98ab196f7b21b8a990bd33c0a94b4505298d15c931de9cd1474cbce618cc64f6305560e5ab2993b4fa3c0e53819e87d5a19604	1613745407000000	1614350207000000	1677422207000000	1772030207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\xb177dfd798fa40945344b3222b0111ce8cc2a9d3590c11e4e5cf6d824933581a958a8426bc8831f054ae3172af1bbed8b7c3e21a847aae2fecc1eab367a54578	\\x008000039f1a2a5aa9af064ad02edc3093f21f632124968ed650e517ee4ec8773c5e994eebea43cd237664c57e1b01ee996855275b3b21e2ff650aa3dcec79500de1bcb4ccabf9a8d4bac9202341740b40d00b22ae08b74fc47d5cec98a3e4ceda8b646d2bf29aca26df62fab2a97f48b7473dac7609a488746374f6102a810f8124ed0b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x04a1dc50d5ecab1ac9ee287fad40e54d67a60117f4e52b38a4a9d7be669bf0316fda9d88d95e7fc74b935b32e54c42667c285068e6e8dd3f249fbf67789aee0e	1639134407000000	1639739207000000	1702811207000000	1797419207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	385
\\xb5bb26722caa0e02ab86fb9bfe9da682ca7598597fac2c4d291765ade7f3a9287c00db99e74418fb3c8f70da7870400a1cf4806137fe8f0634e17ca3473d66a2	\\x00800003ae550a7c17980cf7f72af64e61aa6cd0d66381e2915c05fc5e2f28a899bc2b3fc5779d6d59681a63d737b2cfa7629384d1f19d93e90067ca21aeb0bd0cb82537d67fb401ac48dc6ab9eb43362a3367e28dd202febdc102c88392cb6ee8544aec3d55110cd42df77f7715a1c28c672514a2f72f1dca49f11797dbcd954c2b253f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x48ba5ef821b7ab391cb0a34f73ca6b9cfad541aaf1cd2dac9ff837b78f4169ff702a563cd2d06fa45976c2cfc3ea857d903fffcf799bf59bf8a1e22ce9e9ef07	1637320907000000	1637925707000000	1700997707000000	1795605707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	386
\\xb7d3b8d0ee9312282c083490eaf98210b5e2966e3cd0554a6e2bf49e98e14dac34cd451cf474cd306294712441695e61e30909ed2559d21f33f783f523932b1d	\\x00800003a947037b2fccddb9526a25d005cb4ceba29a928f7dfb2e585780e9b54484d7a787ace86e2b009faf6ed970e44215a814515221c311b24033c51bfe1bcc0103eff17328c662c61504b230763a32cd7c0f28d9edea25849341647e23e1e7b6b3ea8cede07bed175d6d0d0957255d89c94f848bf8e32807b5ab9c1da777ae3712e9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x22d20891aef75d7e08ec2e04fcd250d642d44577b3111fa267931ef54a96b5fb245f87f06113ab72057aed0a285cabe2bd9cd19bcc84adeb634fce25610f9300	1635507407000000	1636112207000000	1699184207000000	1793792207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	387
\\xb767a62f6904cfad03a272903c4d768da222b4c74252579e48359afbcd3cc077219357be3d5b30f4d52ad3e5d152708e044232d67bf8f5cbfe2bad7b3b8854ba	\\x00800003e8485f45967f0a7b64753e453b8628d904fc222c7adb1a6c82ac73a076540167033a5713ccecbee8a9b75a4ad610ab63c331be3e7f52c703022c14e48b2a511309c89d5477c8fe8bbb6618fd048cd419a355c84d2515fc0ff4bc4e816b429c14388c459f76a82a9f1992061665017b2a79a5d299e6471806204132ade82d170f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb404152abd05e0c0eabd560d69174fcf810a94bc66d8a4fc61ccd7fb7c4420f676b1f230f7bb3fb94d9ac28d2664ee308cf8c2de5347104672394e87b9b8430e	1610722907000000	1611327707000000	1674399707000000	1769007707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	388
\\xb95fd862ae84ec051f2e3417b56b327cb4a88f9513532fc68b8252add439ab6ab46ac0b05e42eb81e8772d454314d2b68b42eba5c0eff6d720fddd2d1d060859	\\x00800003b69593d4ae1d68ad8afa881e15c648ff615d5984f25603a884892b33a0c475e5bb3d4cf04733ce8eb77327e05e3c191f86e65919556d0ac012f4179bc5cb7cc6d563891595c8adf04826c9cbb8765162338ac2c4f6bc7b06c52f2cd7e4022b231e2e3e7c006bb77e45881779e7336ec371db79287d2ed5ba8e433c9fac948ca1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x91f57008c056915a8cea1c93a00d85e7287c7d7cb3c0ae54b3ae4b60ce4a652365e2d053ea82a7799b8dc33afcd15f9e9403401d592c54f0fe9b0c012d5c6906	1627044407000000	1627649207000000	1690721207000000	1785329207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	389
\\xba07d5f8dcc04f511e1689f1b186475354979ed38edc850a54b6cddf64990f79f52a532214bdec219de3121d6adebc363b9f399d2444909b12e87a7b8ec6eadd	\\x00800003e18be9c6ab7ed4b5ccad6807dbf613f717f53de514a4acf279883d8227dbc4a6c1155276c34c534811001fd1dbd7b6bc5c6f206a71f792b757bb5c8a909b03acfd8af79b3bf3e3c8083605d30f21b86fa1e89a21223b8358954caea03941f9b8efcaf7e964fe6bdb1de4ed3929163aa414c4fa4b09332ac53dee75041729b7b5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xfa0e3f64d8a5e5a721b8eedd1537528b152a4315e1a8058dedc925dff651dbf27454215fb09e58a0bbff465ed2540c374cf625f186a826869370a9b70cbeb906	1637925407000000	1638530207000000	1701602207000000	1796210207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	390
\\xbc1f864575eec2bbbdd7651f39ce55ffeed288c60a6c9ed02501d9f6819b29aa11076b2ccb1fe085155bd355df52a3387494ecf120017dfce4b6f2e483c4dccc	\\x008000039aaafdfbd8b5bcbde4e9ff8a05ba53eb77828ca237fb864d2aa1db1a19fef901fc500d31bdf2ddff101382c79207148e0fda1b4f3d5c5092d3f3ee46c32bdb8c790f096718929c09f3cf735a0f15dc3e923c2ef4d4d7e2712e1f93eb7e296e64f049e487b1aa76df181ec29b4f6f22c3b46ef4127e2e21df91f2e7671fca7803010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd096b190d36c16f12e8eef454ea5d88003b0e57048d2de1f56145dbab2944d8ffb48d0167d7d6ee6836295198c945423a215ba7ff5619547fe857bab987b7408	1613140907000000	1613745707000000	1676817707000000	1771425707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	391
\\xbe03a5880282f569a8aa402dfff77a244d8230c1d05473daaaa4b785b51b18065bd5c7c0f7f27caaeb2f2d3f87c9128727b84b203b6efc327d0a7d0dd9c4c4e6	\\x00800003c3f87297c455919a91cf907b6f25801cff7a5902ef2ee2ce9f4b7dbf7b90ec0c3c0bffbec4bd67fd77ac246e79d6c9e20c26769c251b23329cb23f0b8b373ef117627c17282e463ef4cd0528a18ee12826e644f332aa92ecb4935cc6b30078b5a795bd516c32fe98ab6c54e7983b22b2b570fd4c1e47fa460c6522b426947341010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x105910c5ecb3ecb48bfefcb9ce8fd00abf7d54a08d087407630150802045cef3b28ede3f0f16dd8e377d40f86283ea674183334ea6778acf312cb6af75d7a108	1630671407000000	1631276207000000	1694348207000000	1788956207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	392
\\xbe5b18b3beb4a2e1feda8bb382ca851b9033e4ae873d2159a8f947dcf5b4d7a15a74a9323ec6004bd24110d79b48c26ff5f63f1d6cc5ff9a44b63d900bf3b864	\\x00800003b96356054e2240bbcd729cd6bce4085672910250504b7ac6188e47b8e0d85d81c0081bb93d7dc4dc7483719fa18552331a03597ad75b592d5429f3f859dde326b29a59937edb8dbd5a50759a739fa6cb2fedf28785671fd23d4063eadb08ffb77fc654b7c676c33d5bc245da22ca86de495b01396d8f9a0bc8667cc0b4f8a9bb010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xee13ad2e750758bb41dd9d047ff7b8d283fb78f2df3e164e1b781f5c4b974e5e161ae4bfe0fa457cf65eb1b66585efa57cb26bf2487c9af65cfe5d7a50844b0c	1617372407000000	1617977207000000	1681049207000000	1775657207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	393
\\xbf53d6a0e997d7fffd094ad0db4ff3339395412cf489692cd937fcefe5ff94aea3fb730453a6f6659bdd18787c32a0394069e9c4c1d4569f296d4e10a2ec9873	\\x00800003d930b01e02213a2e53c7c0faece6715a6e65e021ad0d7326103c24fb3c713f52bb057633905bd75fd999e96e487bc145d85111795de3d274c59031f8af32e09980eb5bd5a5be814b50328c82f49bf78a67919cc2b282743f05fff347b6b63b94688f9ef3979b5bef3fb7e993ed81eece3b52c8507a8204ae88ec47d4a5892497010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8328cabe6606ec35120a7de08f7c9ae8c3330be6ff928eb32c5081e1ba5aac96209306e28400c0e05040577703cd4b0f637087e4832a2b12dd89b22f5fa3de0a	1625835407000000	1626440207000000	1689512207000000	1784120207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xc2d756a2b2151affad7242c8eea9a538f127a36e93aeb3ec998360aa16a317f4b115a676279a4b44fb634c5d689d1fd341256020897115ec8572d41c22d0c9bc	\\x00800003b47c44c113be1d689b9b217e95c65fd2b4e9f3250d5e8e525bcc6de5c6d9e8a468ccb8383a5d32a13e1793a83c14a2394ea1250126e94d1a762555b3ba5b9315b839ff01d0acf024f517422159c0211c7bed23213200a9ac3f7854dec4b3eac1f18280985823967e558a9b9e62f2a8d07d459dd83f66aa5ede63265e02bb83fd010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xe50c72babca845a7a75e4555653663973361af6b454ffd2a9e4cde472d4df730af044f0d1933bbd3cd92a4c2c78ae1cd1d00ed8f14e6ecf37102e05b5119ba01	1625230907000000	1625835707000000	1688907707000000	1783515707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	395
\\xc45fc8684652ee69281c7e006f9c846dd521659445e955a9bfd6af2931e15637bc99e5c7499e1821737700368e194f791dd678b57ec9631868331d33c233670f	\\x00800003beff77fd96fe07851f7668ccb948156100281be602c8f2ac4f579bc84149f444b6216a79dd9bd5ba2a1497e6e538b424fca4a2f9c6390e0b0f13b3c084dd6b83d8f2578841566050932edbfa71c0b6920e59fc3b7aecb77950dd14a570bf35056f5649a43680989d092bd6e2e9bb93e985e9965a0e586cbf473179df6f75c963010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9f227b08333bf7257f2527f5121876b2eac41bef1f374c3bb2bf85eb4f8d065e3b8b683b4097a0e18929f2ab5913f4924c788c5be9848751923069852866ea09	1634298407000000	1634903207000000	1697975207000000	1792583207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	396
\\xc8d3b5ea23fe56122a41e12ed0b11c16af1672890d83f21510e5cbce5c6c4000ed7488f81ae6148398c088af35c09e445a0ebd2b910644b09707cb8edf371e59	\\x008000039fde093860c264e04e03c6f5956888e316dc5b123a66e6320ea117844273b4b3427c3b7cf50c3e48372d62eb1ee5c536713bbf4c0c2a1f172e92241deb1ed3f61946fc077032ed92b6f5d0aa587adb0eb28515a3cf828670e3e0564bd22fb30de2693f8956af73654452df62b1ff76fb9ffbe6df450de3fd79bb65aec50e1927010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb15b71923228f529e770db5705c8781f12f0dfbb10a07ef93da153f8563def2cf9bd7ee13631f9002e35f6064d1ef11615784b8be34d2ef64000a0ec25575a02	1622812907000000	1623417707000000	1686489707000000	1781097707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xcb53139d1564d1d3b047949c978c36141e9563498167311aa002c92d57df264fbf945da5ae45efd487d2e83334bf590961828345779202c1faea5cfb50dd3fe4	\\x00800003c12085cbb2156b93a1f8a953760085442026f871ee97ab7df257c86cc560103eab4c95f59a9c6f1d8d885cb460db89a7db53ca9745274ed90fa178b2f76492942838eb9dfa6f9c5eb97f116d335c2767314b3df736bc3a7a4dcc327cb767ecadfdf382a79323d39f294194442836be4ca89dc7e6c101e5b366cee7d6136930c1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x4decea5aa5f1e224ee7003c8e11cf517d49486168b6035e74c24619344a62f58ab3cf8d4b1520e01125684621771435c7e8d216228e857de0424b5f3cc0a9101	1614349907000000	1614954707000000	1678026707000000	1772634707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	398
\\xcd1bf924b708e0b78a96cfb24e62212588b838b6e4a13dca63558132366fe179d690fb4208e345709d1b0834f6a45e6b1ba546eea1b15d93628780ef05e87333	\\x00800003b753b384c2bc5d06e3f7c92f3218b3ddc2b1d388b39f986947483bf5c4e75aa25a0de624fa26ccbed41c1f7d8038d702bb1aae42d6448ac27401b5e18b7ff605a2dca327a81465e5d773a6ea979a06131670a32f747c9d55b9ac1d2552d9ac958142a2b33b1ff2ed0b97b281c29867a74acb1cf2bd7a51155edbf04f406f78f1010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x7bcccd617a8c3f030c17285f44ea8f241f0e820fa36fe3a9543d566208739bc40c813947fd8c4cfe579690befd15fe91731e2d21eb873c0d1271c8dcd8946308	1634298407000000	1634903207000000	1697975207000000	1792583207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	399
\\xcec7571b453ca8e50315152747a3d2ca709fe775f185f34403d04251f19e2606604d6799f1b9f8edfcd6aff265d83cb892a55ea037126eee804a39b7dce76b1f	\\x00800003e8a5b2ebdcf9435e7ee0e88f0cfd5560260587a08cedcee41514a6482468c63630f6af3a45438f67740d428538730743e4a2fcfc52d4ea75c910df73e819d2ede2b32b03d4bac1597b02503e28ffa3f0d48917f49bbc8eea5636b6cb1c9f4005ea6083af69fc6c43ce9e099e481af423997d8647b7896cc7ce4c5daa93132b77010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x8146d04ff7975af158c69ff65c38014c13c55a6ab48cb5c8bef3b08ef15c996df2826b460c437269fae8032a5ce42a205ac535269d4e5ece11310008c4439c0e	1636111907000000	1636716707000000	1699788707000000	1794396707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	400
\\xd4bfadae91f6cf8018eda925ab83513ba3e410f70cab18b8380ef6bc063c32321b488bdb3f87f7e882cd7c24f048438a269103792060859c3032532777e0763d	\\x00800003ea7e54f46172c9090a1e480ccfd7812cd452eb22aefa7a64b2ff60550c4a64b3d80c388d40edf0e15f193232045e38ed486d5c92dec4ab73c5c75d28f11125cb5efa31eaccdddfdab7cde315bae4b4d99a50b632aa805136a6e0bcd43204b086cae8b28c2ba6f567b7ef7f208d06989be9d84bdcb4301b927ab24d908e3244cf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd32ca88a08219554b33f373fa5ef465bbf8155a99667b7616ccf29564469242678b7cb2a5f2f2ee7b40fb5dd91f60390596ebc714bc7908064da6dac43f7e40c	1639134407000000	1639739207000000	1702811207000000	1797419207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	401
\\xd5ff4fdaaca0746e61f1c0125efbbc19d98d7e3064b3ef393c4d834624163645d47dac2e2effbb4b318a6bde0ccc2c261d783c0b068e983e02b77fed5ed895d5	\\x00800003b00990e68f87229c1caed0a875dde21c02322a3a3ad151900e86cca11bbf1e08e35dbdceec1c3abe3181df481e8df0d5cc9e8e7a8f95bac8996e599dd542a951ef184a15dddac14f70fc7f466cf53a30c9119b46a7994b1b24e3f9231dcfa7b0c7262e6726df194b91d74a94ba7ee4348fe064558b51e8621e394a8262175565010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x79746fed3aed2ab02145dc976217c976ffd63d1724c4e8357db6dedeb5c28950464fd240ef8dc25477936031b98706c0f00776228baee107250f554372060a02	1618581407000000	1619186207000000	1682258207000000	1776866207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	402
\\xd5d3dfe69ddd6ac83165491e8174422bc0791436de2f2eff63e4cfb00c0eee8885cfc0bfc0e4477a01be7db6db7f7a037776ec345b9fc2c6c68de15cda9ef718	\\x00800003ed0a639efddfd0f0276da3f8642260e19ff4f1b491ae83136a5fde63d7062055d52b1a379b36485c1069cfd119022b6000f4a34d5505507705469676b0ecd0173d6eb7a67db73b3632555ab5f23dd1d6b869a7dde9bb21ac4d6d20569335211035a7beb0d9824b66545153f067b2f3736290f28b6c8ecb5b01ec2224391da2f7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb70c0946aed56cebf0602fd5ad44053115afa19b87f069736efd5cafad664311611a88c63e9ed092c1d5788747e6eb55413000b640eec1bbd2ea4f01feb6ac0d	1611327407000000	1611932207000000	1675004207000000	1769612207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xd77b90fe72e2dc059968fc2ed771bcca3b00dfc0edbd9cc0036e8f576b24c7b71bf85cacbbb266a72bd928e7724ca22e855a9ea1e2132e59634f453e0024bf20	\\x00800003b796385c6993a8b7e02b0098ba1b48941e97d3dbd57ac729eee9c70c79dcb45ee92a7c347f33c1f2780300a160891013318254821f18cd1570cc408d7d017722c9b538fcf15c2f366a6d6c5c5f1ee5ce34ad774df3db4b3c1a16b2be36343ebf3df09b51ada9939d3b8e17b55b8fda248b04ae54d79357b533dc11d49529660b010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd16d5feb84cda4cac243241434ea40eedab84f0982ebc98dda9e75980c5d55ab1731ccdf00d3abd9b084f9506ce9d8b18b2323d91b56cd7ab826bcbf07a2e206	1634298407000000	1634903207000000	1697975207000000	1792583207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	404
\\xd7cfb3fe1f9b061844304071818c5edea05dbdca38786ec1c142f0432469bfe916762c0eb3b33cdc9e895830b2f82b580a7ceb59e8e511d0b0ab94dbfb3096a7	\\x00800003e2dc2834bac371db0fedfe6cc696078f81d8d17c3b9765020e2a11fb282732ee5a14f3ecf4743698be17a50ce03e25f66401ab730c9232b4e5674d0453bb14c340aca8b6aca61ab12ce6297470dc4f2940755584a17ebe7b1f21cb1812486133e00aea4026aee4e60321461504e7910cc6bde727aa74018586c0e583690f2335010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf7317a994fc8e47f3555f6061e1f8975dca63c9e3b24ecd97272979dd2301daab1233e026e35df8c3ae18d187f31df1c370c2299465c3b0bdae5debdc3941308	1639134407000000	1639739207000000	1702811207000000	1797419207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	405
\\xda9b7e521a7b3ad4a028e87736b00737fbf84de198a2af65e5e78f8bfbb77aea360c2cf000cdd7eeb983b082e4f19816524c89ec494db8bfeab07e0e57eb7e0a	\\x00800003cdfbc82e6846c271b9fbbd8645909ae47abe699e618bd9a5b741d756c1683d70ec7219a87ad2c71cdc75acddd2271dcc5aecfd79bfb78f97a9bc0a8e9e0c56c6f18e14d3cdd246de04881af9b134c4018ff25522b892a5ebfd7bc293996a3d4c00d9e9c397fe69a53c0b7bb6c7b1d3171eb104f00668fa8421925f1dcdf4939d010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6dab6a34492470c2c398a1b867a09787d90d2fd31737bf4d259758351aec20f19846518028eec701a3d40eadf2e7ace3b6c31f16e50ce9a875a7f2590e768302	1624021907000000	1624626707000000	1687698707000000	1782306707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	406
\\xda031bbf8145aa5f80eae5c322bdbfce1b7ec6abe329ed54d692333b594a3e4ba230bf681bdbdec9ffa7e2b86652009724718ed9691b0a8f8e40e6a56279a8a1	\\x00800003bd172c572d3c77995fa06562ae68103950f07cfc5808e28427e8ae8aa919c780abf4c4f1f88c07a794bda606a44dc0a1a571cc7618cf68b60fd0d6288962d3f77dca8d9a1aa1dbbbe65f7f952647b59a2bc8e6480cdd4b34bd9391b56496aa6b83272808fe80b20f5893eb7d5747ad652b235569f5ca83cb1b105af3d495bb47010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x25a58f55084a92a6822e95d0f2b910ece95cb34d9b71e7959aa1d92d3700cc4428ba06cbafa4ae5cdc4e6e304ab6e21a0fc4b1128d8dc0df9b062cb8ffb0960e	1634902907000000	1635507707000000	1698579707000000	1793187707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	407
\\xdb9f201b58b4ad7bc406b188e654b820ed25121a3398e267ff035f9e9199c9fe696a35a8d5c7ef4b27c1d15a74ed1bbb948c650be84bb525f59809e04549cc1d	\\x00800003c7ce91967b1e2355a62bdc44b25be505b638da982afd7d47cc87d68be4244e11a229371db9f8d4aa5ef172a44a3500e3671f93e41824dd72f5b7e6b9d1e80a663644b1ad1bd125c730646c20010627a1ba3048e8e3c77f4ebb828a23007238509cc20b06f07df8897fed598886b39a196efdef2d2ee37c335264ca759ebd61e5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x2c8f191d6c99c1d6222e295f4e2c4faeb935e8de3b2fa1b6c3c588a3d3e30fc018e11da824ac5b2024c955e3052934b34effe68eaca45d7caaa393ad16bfe10a	1637925407000000	1638530207000000	1701602207000000	1796210207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	408
\\xde6b0137805dedff2bac824e037048571a4cd72c8a469a00d54297e4627102fa9eb08e7bdd296d4807a3f98d5813a4b811360d2ce2593c4567af6050b57333fa	\\x00800003d4b6684de752298bf8f47f822b8751974913d0fe8145f0bd3dbdef5b47448dcc60b96913407c4694d194523617b8b4e380f7645362209b3519ec9ad94ae4f8eb327483d14a1abb22dae92cf94a700a3ccff2a898e5cdfb97609b27542146ca7a1902dd9f7a0d141d7d4c324e306f7d1c16d4e5f5080a04cb780c170afef4fcc3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd5b0c1e574c7578d7809ba27844ad01d752b80150d4cbbddfb23214a2062fcdd621a76d2c55e3f48ed58689c6cc6f89071263d70d3ab7c07f01833ea2aae1b0c	1621603907000000	1622208707000000	1685280707000000	1779888707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	409
\\xde733862ce7bbde4976e91d4241df2189809cc7ca004a9019ef70f258dadfb3119d4e8a6130b3c6c271565c5189bf2f9e5bd9fbb6d35a23fb5f0bffc889839dd	\\x00800003c07ae1d92b03480fdf7d5f111b0ab884fe335717272b30aed991bbcc9c1ef874a22bad1dc3c30a276e4ab655f84b369ff2b1875aad1a139cfb5878dd87aa68c96d0882d426e76e6243a2097e13f647a04fbabfcfde77f5ccabcec9636a6516c9445241a4a8552d85723ad4b38e96b2a8d9402252b96be12319225a7a88d69249010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb4b2e2f3e9241a45b6f4c44efd8f59fb3e92fcd7ef298f10c074500a2a6c54f5819cf32c4416ecc2e90490eeffeffa01cadc9a235e7a770f2c429e4576157409	1624626407000000	1625231207000000	1688303207000000	1782911207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	410
\\xdfb77ae178a302464f305a59860e7a7beb74845a3ee05c1219fbedd2c6d51bcf53138909eaf0a23e1aee19b84fcc9ec5a38751413194c28333e73772a3295f14	\\x00800003d95895aa93b0dd259bdbeb5654c43483c314f7ba7d7f4af64ec3536f48c31afbab6717ae6d10accd2b982336948567a3fe827add93b27cd5a69994214ff7397517d4df6707f4d5e627ac059ac4b9ded97af58258bd076f61d7bb31e5edeb824d3f8ee545ee32a84356fa5c50cf29409e1901cdadb9ba5109752b524edc996eb9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6f33c00964fba2e76139e2f328d586507cc17924937fd444bf679db7dc0798d5536e60c8cb31652df44746a84f8e47c1386ff00bbcd853e3c3a82ce8332e1401	1634902907000000	1635507707000000	1698579707000000	1793187707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	411
\\xe0038dec9a639c4da06118c3e7d435344ec6f20a4dc97e2377bf4274f7d8176f8c968c0c71c1eeb0097a3a3f2de592f33f82755b29ae46ff7050e397a83d6ade	\\x00800003e154a48a2a14243a9bb95c39e80714679504735b69c0284cdb962b9c036c0edf34a5341577f537473936317841b52640e22dba525fe7d47c3c74e675934f115ec308bec11809d05727aaab118a8ec9b34e2c8e518820ab29d38de6a5f45795e2504a3153552582c5edeea9439340f71d4f138af6325a7dfcf6c25d0bf1f367cf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xa76f32e7fdd3b9f1428730b7de78902312b25e3aa77b3d2dfa833547f1736ed36a11f13b713ddb86e216d6d0185a844c62638f1d847904962dc00801f4eec408	1638529907000000	1639134707000000	1702206707000000	1796814707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xe43f2ec178d27362ae06fa88e6917d162d06f1fe8456261fa453d98eb1a86d8ed6079eb6ccd73ba8b6c71fc3bb61ff815f918d8f2cf381f8a78f29311b56b9c7	\\x00800003a351a1ff47de5c5409f59d2d13cb1520a1a9fb626d4011a6c46aaad32499e9c1bd7a224d5e8a69fd8cee97fbe1c99985e0afb50ba4d9090f53af6ef8a3ba72145578eef222d841292916a6bf23241b5e0ac9827ba9c1c34e63e5d4eaec1cd2881f14d098c226145ad02bd355199980e29a732923629607e7804797e9d2a29dff010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x795f380315885b05c1e8e3cf9e35bb4192e46760afce320165d40b6efc6c0525e220b0c3da7c90763c43f544a9bf8c5a7bca1a5835f061dc85afe3e03e667904	1620394907000000	1620999707000000	1684071707000000	1778679707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	413
\\xe4cf6d3489a874a5355c7591e6c475579d13eeaede21aeebd091393ad327685938de1782da3ecf4014eea808ab30855f5c54a4c0b8cc3c144efed4ae76f0490c	\\x00800003af3e7ae6e548f5a952acf915b26a2860419756c78b8793f19e1437ac12e714309e6f906454eb4922bb0cde5a7567558414aeb4946e3d52c5c9219476e91a27274a997d13afa6b11169bd0c25abb2a39273bdbc0e53997da9df5d25f71da4b55cf5ab1f04e1c222dd723ea9951226d958c8462edbcf4e9c69463473a5d6193ec5010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x5255524fbe1612bc1629827ed24ca4140d18db00f0b6b640b88b981a66256091994bef2b7455eaecd0d0cf1a92836a0eec2018f6a020df848b81495640c5f903	1632484907000000	1633089707000000	1696161707000000	1790769707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	414
\\xe64fb7cfb8343b7fe1dbca7e45da9e98b4f5b025acefa90efae0fa3262671a046d8f8a57680527fbf76bd95bee7dc7f93baf623784176657ec460d896c9a017d	\\x00800003ddf301767fe71c23af815fd038eb7dfd8724ce11468ac7fd02036a23378002aa306afba47ce2bec994bdc8f7c54f2d7f0aea2801e00c1a16e6aaaf71e4fad26b39e271464fae533be224e293372d2857ec0a4e4dc97b929425b1b10f53a92ad89306783e3da44da0b86cd2110ecc835775b45155962c9d8b8b50023faa2788d9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9be088a732d4a669d882af1aba850a049eb7486b4c7ba520eaff96ea000dbed0a9815f3692e9ee9e87523d5519c62b34f1cbc5fcc21a46eda23cc1d738a82207	1639134407000000	1639739207000000	1702811207000000	1797419207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xe72b6487c5d8cf0e23f2452f9cb1bade34b6767f28825645e3fa16552fd610e3a3a47052e4744726b0656e712d7c180e531c6f38fb92fa5cb1c91db136f1ff66	\\x00800003b4bd9dea800e71f8e8af284eab5ce30ef589741b597a72a5a978c2ee3e555e15f627c3840e9d42a721394d2daafb0ac91646e902028677ded5152bf00af914891d4dfbce8800b21de39ced4d42e88d3ad662a704474c958e4d97f9ab6d120ebfd8075905654acd01c33642b845e6502f7f8e59ffd60b6005762733338085aaed010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x39618b9e2e23cf139cd1943b9a98302a5e86a53014a7f98d0a019f4b7de6d5f52cbe316c3accbf2889cbacbfc457e713511b73366dc6532dfd2d2e2ab5676f07	1620394907000000	1620999707000000	1684071707000000	1778679707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	416
\\xece37dac1781d75656d6d752cd45d66d6d49d18724615cae190c0e5aad0b888dbd54b8c32a34c24d8137578f682d1cece0bd9bb84e2c1059ebfa1f5773c1653c	\\x008000039d9bbd75c735cc378f8f9a231f33585d451394d965f1ccb4434b7df97159ceb04d42690325f05fb2d8646645a94e49d00dfd94b45e6f5c1343f347ec5d9cd84e351e88de30fd5b3fc899016befedb9482a89786b3d14c08005ef2dc792a9bfc9d97d5c204652475ec0b0beff43ae20b74d437a251ca19d407e34d68fc6a5cca3010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xc3b7cfd84734fde0d1c20a9afdf7babcd46e35f09605dfa86475a087fedd1947d7a2b2be77889b3fad8456bc584a8a3663c30aef5c4a2e766526c21f6e78c507	1610118407000000	1610723207000000	1673795207000000	1768403207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	417
\\xefdb20a12eea9d41b7fa47824e0973eec042d55af8ac88742001a829e827ba279418a519d5640f759eb2640e46eb32e30adb75f9106dd24a2f884a6957dd3c0e	\\x00800003c9228d58be42e3fcd972728feaf58c1dd66f404bbb361924e7f1964d610634df63ffc603b2575198c2d462e5191bef8634c30a9b0eb8fd6c579c15f75665ae72c96b1f9184664d1318675c1fa44b2a31d18c556b326ec49677c6fdeadd465fb9c016c450975f314a6e91d79316aea5a3c00bda7e67d7c991acd4531f01c35a1f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x6a931c6aa8b1d29bfe4dae2da97ea13602ced946a545cc341b77c5c2765eed6eed6c3e5ac0efaac7baca86bd9136c8a463d983f64ea2ea772f3c4a772667420f	1616767907000000	1617372707000000	1680444707000000	1775052707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	418
\\xf127a5e7c3a7dfef0a322d46be24a2f5f2a5e6b7af7e64addeecb0be4ac202505c0096a03d70681f3f1317ed818f634c863ba9eaf9df1e4ac55291ef78dac31a	\\x00800003bf1ada2342e4c1fd6d6046330ed289e5e750a1c46418dc85ac7e3b4bb98d3ae3b97adad33fe537708c17cb686e2cb806ac1b856cb19d9dee550b83c2a366e750b9b5a94ad755f766d3b585ec562f1956a79a037ab78af0c5a7da2d54229e69bd27f4accabbc60aabd4cba92762bec0b41993ab33d28a68274bf075be001edd07010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x70c3d24bec9402ee1a8df0af7b0321d70a2f76278b4e6488c92518d0fbdaf24a8a7fce954241303242277d1274d7008c5f49ced8c52024e666e2b1c9be4a3f02	1629462407000000	1630067207000000	1693139207000000	1787747207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	419
\\xf1ef5ad3753606595297c1e14fcb96982f704bcebb183a145384c29c5a09c32e48c6a175df592075105d08ea44923318394772cbc71ea7f7eba6eb934ee059b9	\\x00800003c073e944b86b2ca1cc64bb5073a413a25a46e251ea704d690630233ca7b82c86e81551cadaf70fed57cfaa0aff1f6dc7ed055fa53e7079c9e75257a3b365105bf233ed28b0ef1e6377c76703e45013e1aac059bfc96a09d1c14a73411ddc228e593b2b1c1a9a135361079b431193870da8d6e2b285a00addd9b79e802dde74f7010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x62934501257b8df7942153ba8267f5e11ca2f557a3af928a07fbcb955d3d7079ca497e306e6820277c40fe77ab6c4f59e4824aedfc9f0dc5f08118da4f0ef908	1631275907000000	1631880707000000	1694952707000000	1789560707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	420
\\xf2876195014c266b8211bf5d75733bb8df09d6d36ed0e153ebeb508787a09b8ff57866a73a0a98d7d81d2ce8b5ed0ff32fca2ffd2b84188e6628e4efd6c97e9f	\\x00800003bf71b5bff933e74b52ecca45a147588948e048b8b1badf887b0b6d316f364210d21348278d4fb78a9d3f3d75d298bc29940a71eb8f402dffb8ce6c4afa02d5d9aa28b0318086854695861c7bc2661c051eb2bfe314039a42be72f2fc5731f7458a97390460d9c98bc27f55a03693cd84492d81314577bf7823980950f8008e1f010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xd9a6c33f066391ac78c194b1e6b683bd6708c2f678b69aad2047f19b8fbd874fa67375a0e8aa95272d26fdf53b7ec46c3494aa4c7e503c10b9c439346242f101	1617976907000000	1618581707000000	1681653707000000	1776261707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	421
\\xfc7328f293e8f6aab5c406f0cf9dd8e0a320fb3e7ba3bc6bb8931d28f204f558898201c892ec4c06d857a2bcf2c04180e57872748619de70b5fa0f01a8d487cc	\\x00800003d1569633ae40aecb44b167a79fb6388f14f0d17384f3a14b8598f5df52bf27829cc0d8fbeaf656e0994ed703d46a026ebf5718ead929f0df3ee8694f36836a905ee88e840a4825369ae6edc99e02fa91998ca76320d6c45e353f798e1f189b375b80805695054b0db96048d5443f60aa2e429ddee0c2d97d101000438f0d2caf010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x21fbf84d00e38064877b9c88cf74db355b3bbd63fd45a6a0a9e4084f0fcfaec25351ed5fa9776194d3a27b136ad6547ced9911d06c42d771ee1b2b1dccb6420c	1624021907000000	1624626707000000	1687698707000000	1782306707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	422
\\xfd839677338edcba59f25415f857dc1f2521169cbbb4304c5160b6398e9dfec08945f8084bd1fb1dad0efa9e538691d2dc832fa8627ea92b0023fd4d36219cca	\\x00800003bd8976eec133ec0bb891aae153f93b5231f4a1a38bede04a05b8dc24e335c4a9877da41f1a2d45b0d7817c53758e273d1b24cbce295eea16f5bf0cef44bcfee4ae68eab0f39b539f48c13601c694e71fbe7b774eb5fe2f76d3b75ec99586131f306eb4e16b78a5f68d8b7df122e5f303244e4240a10637a121e11f56db0aaaf9010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x573341676b6604e90487641ff04568f015be3fdb6b5179e553906b216f2feec871503d4e01f4b0f6b04a39a6e96a19a8a536c8b8fef23d5758003dc6629ae607	1621603907000000	1622208707000000	1685280707000000	1779888707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xfe3f3b174cc074244dfd9b6c325ded277c5295dabcddca9155e24293fd8dd8052c84eb78e3c3cf5b802269c4b8511c0120ed9331d7744c5b3465d90932ff3a3d	\\x008000039a73e3e26115474b3353615da6c27ea1b54a0a1c2e89b31a97a67590bbd11e0fa2da6541ded50a816501b5d4c43ca6b74531d69a1483f10d8c34bf0f23d21236fb7bc66e8ad7a33b8d140d459eded4db344703fce69acf04e141270f20010f2e89b6ee4f356a8d5f31b766005d5ec1fc318074bfb7d10cff5161ee2e22310715010001	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x03f31cdbd26dcd44fd90598fe224c5f20b68715decc8aae7d0c24c97a746b76c601473f4b18202719dc44a34055b2335173d7df6d47549621bb0654ba0c25f04	1632484907000000	1633089707000000	1696161707000000	1790769707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	1	\\x853fc774862c3074eaf94b0b1a45de30aef62b2ef930ab66224164b8678a6c1b918c28356884ef29c9b8239fee46d623285c6ec31c5f05927b56b61436c97be6	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	1610118432000000	1610119331000000	3	98000000	\\x66b52b934a1e51fece0eee5af5ece6afa3e4c10da0dac5805178ae6539511794	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\xb0461991f03ee4d475803883d344570b14ad35ea6bea459067a0203c4c592f94f4f68e52c6294876d5b1ae1d7ae41bff1ad32f4202018017d228450a3d989502	\\x139fe12db5496ff0e808fbaf159289eb5bfdfc731c77ba3d19c0ec2b68a047f6	\\x29fe0fb50100000060ce7f4f887f0000077f482560550000f90d0020887f00007a0d0020887f0000600d0020887f0000640d0020887f0000600b0020887f0000
\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	2	\\x1508c71a4fff137679afdbd261431352c1188fc837ab1855c718331b98838e8aab43e618faf1f66cae4eaa87e8b670ddde3da1ac8a5d883337fe56c4a7bedae2	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	1610118439000000	1610119339000000	6	99000000	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\xd16507f35743a7a50f4673c8685bc56b18e46929054e1573115f5a88662c933b61f31fbf5dbe0ad6489e2e0252b6789a2b712b66c5a90c77b84f2c730ea75901	\\x139fe12db5496ff0e808fbaf159289eb5bfdfc731c77ba3d19c0ec2b68a047f6	\\x29fe0fb501000000609eff89887f0000077f482560550000f90d0058887f00007a0d0058887f0000600d0058887f0000640d0058887f0000600b0058887f0000
\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	3	\\xb47d49961a5b5d5f27aa9dc923eb51344b40c010b816f1b3ece2f9bc0f9700e82f5377337804689e29334a3bddee2d0d5bb7a955230302906c742b25db5bbe8a	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	1610118441000000	1610119341000000	2	99000000	\\x015636cfee56ff529dd1057c7ebb31d0a717fe51eda993daf5d12173fa529a56	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\x0a13e93a4ab61b50c794c66f3516a1d174dfa23dce11d800732dd2d9b7636e948e7a7f9e51a86677be5041edccb352bac45c3e9df6ae9482ac7be27b212d0d05	\\x139fe12db5496ff0e808fbaf159289eb5bfdfc731c77ba3d19c0ec2b68a047f6	\\x29fe0fb50100000060ae7faa887f0000077f482560550000f90d0078887f00007a0d0078887f0000600d0078887f0000640d0078887f0000600b0078887f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x66b52b934a1e51fece0eee5af5ece6afa3e4c10da0dac5805178ae6539511794	4	0	1610118431000000	1610118432000000	1610119331000000	1610119331000000	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\x853fc774862c3074eaf94b0b1a45de30aef62b2ef930ab66224164b8678a6c1b918c28356884ef29c9b8239fee46d623285c6ec31c5f05927b56b61436c97be6	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	\\xdac29ed482874fa63e1bfaa50e9f7b0215ed31e985cc0e991f4d22175098b813111734a9d3b2cf8c4d779827db9593e79fa50224f0e46f4d1b37425e5dea0709	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"87T7EBM5MX25VZMEB6HWT7W63EDXQKDCX4H6V1PXVC331E2R7FSEWANHPQZXMCYQRCMT6YC1GT5CT8MVQHMDEA7SYJVW57T00NTN010"}	f	f
2	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	7	0	1610118439000000	1610118439000000	1610119339000000	1610119339000000	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\x1508c71a4fff137679afdbd261431352c1188fc837ab1855c718331b98838e8aab43e618faf1f66cae4eaa87e8b670ddde3da1ac8a5d883337fe56c4a7bedae2	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	\\x7be7890a8a65ec3aa9835fd4642cd96de96f1ee1f569ca9c75e3494e57d5fcf678e648940f734c710359f69fc202c370e3b5a328168e5f429ba9f2f3483cd701	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"87T7EBM5MX25VZMEB6HWT7W63EDXQKDCX4H6V1PXVC331E2R7FSEWANHPQZXMCYQRCMT6YC1GT5CT8MVQHMDEA7SYJVW57T00NTN010"}	f	f
3	\\x015636cfee56ff529dd1057c7ebb31d0a717fe51eda993daf5d12173fa529a56	3	0	1610118441000000	1610118441000000	1610119341000000	1610119341000000	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\xb47d49961a5b5d5f27aa9dc923eb51344b40c010b816f1b3ece2f9bc0f9700e82f5377337804689e29334a3bddee2d0d5bb7a955230302906c742b25db5bbe8a	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	\\xacab585fdf2c39408a50aaf0a58adaba7ff9142f0c7b7f9098926b0bd6c021ec659587ae6521d75567a3d476c204c406f4ddbcfe175c78d7569175dd989d3104	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"87T7EBM5MX25VZMEB6HWT7W63EDXQKDCX4H6V1PXVC331E2R7FSEWANHPQZXMCYQRCMT6YC1GT5CT8MVQHMDEA7SYJVW57T00NTN010"}	f	f
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
1	contenttypes	0001_initial	2021-01-08 16:06:47.698421+01
2	auth	0001_initial	2021-01-08 16:06:47.740997+01
3	app	0001_initial	2021-01-08 16:06:47.784483+01
4	contenttypes	0002_remove_content_type_name	2021-01-08 16:06:47.807335+01
5	auth	0002_alter_permission_name_max_length	2021-01-08 16:06:47.816716+01
6	auth	0003_alter_user_email_max_length	2021-01-08 16:06:47.822323+01
7	auth	0004_alter_user_username_opts	2021-01-08 16:06:47.82953+01
8	auth	0005_alter_user_last_login_null	2021-01-08 16:06:47.836175+01
9	auth	0006_require_contenttypes_0002	2021-01-08 16:06:47.837782+01
10	auth	0007_alter_validators_add_error_messages	2021-01-08 16:06:47.843761+01
11	auth	0008_alter_user_username_max_length	2021-01-08 16:06:47.855844+01
12	auth	0009_alter_user_last_name_max_length	2021-01-08 16:06:47.863487+01
13	auth	0010_alter_group_name_max_length	2021-01-08 16:06:47.876032+01
14	auth	0011_update_proxy_permissions	2021-01-08 16:06:47.883849+01
15	auth	0012_alter_user_first_name_max_length	2021-01-08 16:06:47.891312+01
16	sessions	0001_initial	2021-01-08 16:06:47.895879+01
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
1	\\x139fe12db5496ff0e808fbaf159289eb5bfdfc731c77ba3d19c0ec2b68a047f6	\\xbb8a8dc3f7e63d5f464d13ba25071efe02e39133e851768a5facf4cbb82c57c4db2bb2ab236bc4d0ed74ac0bfdd5d4ef4456457c25e09710a9e4623f4a779201	1610118407000000	1617376007000000	1619795207000000
2	\\xb776013ea7a22727f8553e686ef74adb6cd0bfc938126da5048c9d74e5673d54	\\x3d13d32b354ca1a72fc931f222c14bad96b54866f67c97cc75653c4aa365d138feaa4184250b8df6712fa230d3da6ffc01415a50fea5b2473d80f1a126703e06	1639147607000000	1646405207000000	1648824407000000
3	\\x19d29c551cfa77553b30047977b1a5d27df5e8c05e2d8765e3e8cb8447dc4f90	\\x993f66906fddf0eb2557947015c1d365f6c9f6abb22f80229591279a4c8e6ce7610a5ab831ce8e8d0092b3fbafba60544796bf6f98cc871bbf981c21eb654705	1631890307000000	1639147907000000	1641567107000000
4	\\x997c3183222106256a8dea80b8c14f339346515d7f886b8264cb1a77a7fa4252	\\x952de73d2426a5c2804620726672c6e03580fc6475e04278c27d05baac8d5411c8e6f5744a32d14f0a6c1c6964f2a42ad0a78a61a67adc6a9e525ce8f2708308	1617375707000000	1624633307000000	1627052507000000
5	\\x9e500a9a1e3e37fbb0dc5796382e2dac773ebfad59d8cefe5bb25b9dbf9263d8	\\x0c715ed8ffb237a80566f7e816f4b15a9fabfc0da4361704a994469163bac29bff8af1b924d4ede70a2280b2f50b31c25a017dadfffee0e55e2e7c16d65d0208	1624633007000000	1631890607000000	1634309807000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x66b52b934a1e51fece0eee5af5ece6afa3e4c10da0dac5805178ae6539511794	\\x60764e179bfdd88bd4cc03b68ca50dbc57f4fc072714c71722156225690930b8b00cb83c0267920f396841e838d7db13177ef0beaf03bb757631d21b8883fba6164381bd0e7e239b75ea0b5fa9b85c8282c47f56f03e1e5f7f89071a7d349a1e16a9c09597106f8c253ddb3205a9c07c5c6bf2af08018a3c6d39afe7ccd78a31	308
2	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	\\x8729d8f990ac01f6095adae53a84fd1785dd0af61a6a39fb2d1fb9bab758ee0be41945a2a13c8fb8138cfa4cd61c3bee7ae6e5439a201e01397b0fd568006d9a93610a7145b46426ec23347d8fa6f2420846de8cf096e39a45535665a52399f3702aaa79bb8aade899c5e1cedef60c65173cd0a94bf6f1275b87265f9afb8db3	417
3	\\x015636cfee56ff529dd1057c7ebb31d0a717fe51eda993daf5d12173fa529a56	\\x1f98d9d26a02e488fd17673bf4c7d289c65bd2324efb1cbdcddbd1d9a8d007d80d69a546682803e5ef1f527b9d03e055e679e49243ce4714954aa6b8e93480b305bda347e2d5fa13100e7442f45d4eabfc2f9a1e93566093d91fb3b07a905aeb9d0e44c6165d54f9965629d70d7de1cfac1fe3b57c349d16277618225fade4dd	79
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xd7b28a388144122f8daea626d118d68155f2fa3bfb7bfc500829934f8a080c765576bacaab8d5ede472593ff1677c34ffaad85a7db8d7ad670bf2efe86db3898	\\x41f4772e85a7445dfe8e59a3cd1f861b9bdbcdace9226d86dddb0630b8583bf2ee2ab1b5ffda33d7c329a37981868acd229bbc68d728f9f4b7c29f4005755004	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.008-0042KCDKGEADG	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303131393333313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303131393333313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22545953384d453431384739325a3344454d524b44323636504735415a355948565a44585a524d30383536394d5a3247383148563541584e5453414e525451505938574a53375a5250455a314d5a594e4447504b585133425454535242594251594756444b483630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303034324b43444b4745414447222c2274696d657374616d70223a7b22745f6d73223a313631303131383433313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303132323033313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254474d4b4e584136584637353357585a444b334d59313032544d374a524836475956314159434e42474a46355231393253535647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2259414a3050324556315358385030414a504d38333254414d544536385a5058363842385159563430364d563958583136445a4d47222c226e6f6e6365223a22394e50423644423748535739374e41384e4338574738424b4a464b535231474a43303944443056393559445141424d5434375647227d	\\x853fc774862c3074eaf94b0b1a45de30aef62b2ef930ab66224164b8678a6c1b918c28356884ef29c9b8239fee46d623285c6ec31c5f05927b56b61436c97be6	1610118431000000	1610122031000000	1610119331000000	t	f	taler://fulfillment-success/thx	
2	1	2021.008-03GC1778E1G4W	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303131393333393030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303131393333393030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22545953384d453431384739325a3344454d524b44323636504735415a355948565a44585a524d30383536394d5a3247383148563541584e5453414e525451505938574a53375a5250455a314d5a594e4447504b585133425454535242594251594756444b483630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30334743313737384531473457222c2274696d657374616d70223a7b22745f6d73223a313631303131383433393030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303132323033393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254474d4b4e584136584637353357585a444b334d59313032544d374a524836475956314159434e42474a46355231393253535647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2259414a3050324556315358385030414a504d38333254414d544536385a5058363842385159563430364d563958583136445a4d47222c226e6f6e6365223a2239434d394159435a47434158455134594756463944334853355330575148365a414d50323656424d3246524a3943384156323047227d	\\x1508c71a4fff137679afdbd261431352c1188fc837ab1855c718331b98838e8aab43e618faf1f66cae4eaa87e8b670ddde3da1ac8a5d883337fe56c4a7bedae2	1610118439000000	1610122039000000	1610119339000000	t	f	taler://fulfillment-success/thx	
3	1	2021.008-03M1H4EVEA6CG	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303131393334313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303131393334313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22545953384d453431384739325a3344454d524b44323636504735415a355948565a44585a524d30383536394d5a3247383148563541584e5453414e525451505938574a53375a5250455a314d5a594e4447504b585133425454535242594251594756444b483630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30334d31483445564541364347222c2274696d657374616d70223a7b22745f6d73223a313631303131383434313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303132323034313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254474d4b4e584136584637353357585a444b334d59313032544d374a524836475956314159434e42474a46355231393253535647227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2259414a3050324556315358385030414a504d38333254414d544536385a5058363842385159563430364d563958583136445a4d47222c226e6f6e6365223a224d344a42333153344b5743365134574257534d545344564e464b3535565a414b4a565239444a35363033574b504a4b425a395447227d	\\xb47d49961a5b5d5f27aa9dc923eb51344b40c010b816f1b3ece2f9bc0f9700e82f5377337804689e29334a3bddee2d0d5bb7a955230302906c742b25db5bbe8a	1610118441000000	1610122041000000	1610119341000000	t	f	taler://fulfillment-success/thx	
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
1	1	1610118432000000	\\x66b52b934a1e51fece0eee5af5ece6afa3e4c10da0dac5805178ae6539511794	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\xb0461991f03ee4d475803883d344570b14ad35ea6bea459067a0203c4c592f94f4f68e52c6294876d5b1ae1d7ae41bff1ad32f4202018017d228450a3d989502	1
2	2	1610118439000000	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xd16507f35743a7a50f4673c8685bc56b18e46929054e1573115f5a88662c933b61f31fbf5dbe0ad6489e2e0252b6789a2b712b66c5a90c77b84f2c730ea75901	1
3	3	1610118441000000	\\x015636cfee56ff529dd1057c7ebb31d0a717fe51eda993daf5d12173fa529a56	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\x0a13e93a4ab61b50c794c66f3516a1d174dfa23dce11d800732dd2d9b7636e948e7a7f9e51a86677be5041edccb352bac45c3e9df6ae9482ac7be27b212d0d05	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x139fe12db5496ff0e808fbaf159289eb5bfdfc731c77ba3d19c0ec2b68a047f6	1610118407000000	1617376007000000	1619795207000000	\\xbb8a8dc3f7e63d5f464d13ba25071efe02e39133e851768a5facf4cbb82c57c4db2bb2ab236bc4d0ed74ac0bfdd5d4ef4456457c25e09710a9e4623f4a779201
2	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xb776013ea7a22727f8553e686ef74adb6cd0bfc938126da5048c9d74e5673d54	1639147607000000	1646405207000000	1648824407000000	\\x3d13d32b354ca1a72fc931f222c14bad96b54866f67c97cc75653c4aa365d138feaa4184250b8df6712fa230d3da6ffc01415a50fea5b2473d80f1a126703e06
3	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x997c3183222106256a8dea80b8c14f339346515d7f886b8264cb1a77a7fa4252	1617375707000000	1624633307000000	1627052507000000	\\x952de73d2426a5c2804620726672c6e03580fc6475e04278c27d05baac8d5411c8e6f5744a32d14f0a6c1c6964f2a42ad0a78a61a67adc6a9e525ce8f2708308
4	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x19d29c551cfa77553b30047977b1a5d27df5e8c05e2d8765e3e8cb8447dc4f90	1631890307000000	1639147907000000	1641567107000000	\\x993f66906fddf0eb2557947015c1d365f6c9f6abb22f80229591279a4c8e6ce7610a5ab831ce8e8d0092b3fbafba60544796bf6f98cc871bbf981c21eb654705
5	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\x9e500a9a1e3e37fbb0dc5796382e2dac773ebfad59d8cefe5bb25b9dbf9263d8	1624633007000000	1631890607000000	1634309807000000	\\x0c715ed8ffb237a80566f7e816f4b15a9fabfc0da4361704a994469163bac29bff8af1b924d4ede70a2280b2f50b31c25a017dadfffee0e55e2e7c16d65d0208
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xd4293af546ebce51f3bf6cc74f0402d50f2c44d0f6c2af32ab849e5c0522ce77	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xd8e8df6d88b84d2dfda274d6f76d178b7d68d7c3b11de80d34726562fd4f1a4d99cd07a25b0fe62da467aaac7e5c816c225389d7d0412d9a3b3f7da3173f6b09
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x55c2ea89a7a3da04c9729d92d5f5d35d8de0fc8cabe0af3780a525d998520859	1
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
1	\\x9fed6bed294cbcc9402b31b08562f72f40adab80ed7ab141f615fbb6afb68b6de9f2d3bfa3fcfccce253ba91c18011c3f4093462e67af2e6e47417685f73c00d	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1610118439000000	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	test refund	6	0
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
1	\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	\\x66b52b934a1e51fece0eee5af5ece6afa3e4c10da0dac5805178ae6539511794	\\xec342257f00ba79316ad80ae09aa0372c71167108e696fcdd4ac939a7364028d19768fa32f5f04aa20ab6e969a561be4789c749e1c5e898a0eefc8a06867390d	4	0	1
2	\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	\\x1389f568b797e538116e60ca037d54d45690b21e65435efda81f89ba5d293ff73f51dafd28089bdf7aae0a4dc67379dc9bd3fe509c507cc83bb7cbcfcbea7c09	3	0	1
3	\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	\\xcac46401e75cd1e48d0e799f6a5ce2f2b92ac8af9c37a963443b0d3122d29983282f5413806c9a3a28ef5d2d5d82751209405e4b2ab54d5b8ed90046bec8a106	5	98000000	1
4	\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	\\x015636cfee56ff529dd1057c7ebb31d0a717fe51eda993daf5d12173fa529a56	\\x451ea5f70b3159517c0d82b721fdaa5f39f82890ad9b90cf208cfb69e2f96fe4906005176a1968195c17a289b6985aab51a4d87fcda2c73bcac9e97c9e7db803	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial) FROM stdin;
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	0	\\x3765ce0cb24b5ef994149262eb21ca3c8eee919be9359a97d923bcb94a697d433b79eaeebcef5ab50b81e889cc90b4fbb5eadd1204284730c10f7156691d6902	\\x054b0c5e16cf2e6b23cab064ca3994e6d40b28802238728001f8ceca9a8e33d22d70eb13e87fe7151a05a24f8e2b262b11cc6d5f9aabb095f2d97165cc8bd3ad0ae20b83c5823c45d49e1373658810289f92119c5b0805efc592139b3f753dc1ceb9855918195e28de4156ff1ceac9f352561ec0cf3ce224a609538665fcf250	\\x5fb40681889467854c783be3a9a47552c84566b9310b8077b4265c0814078d2f928921092b74d16a5be0f97eb1676de43d848ba41ff7e0a0a18afba1da429cb4	\\xa3d8375de9d08d4da2721fb590ffee574bb69c382b671ad682ed29dd1ed65ef7894f51e303ef60dddeac0e3e3352ed0b4273fbfd2a4fd3682fc1d702e40cefd4c37e55389f3e294f551e124165309b6d6e10c84c83dce9aa17e6ae594727336107067ab49fd6b630b61e4f2569097c37040825d1bc00f86f4b7bbd327ee5bc64	1	307
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	1	\\xedfbb083c9becf0405100f2297e9ca213d426edd6364bfa27f100b2e3ec16d624584937326571f53deaec670d963b2d8f1d63a706e46d892b318da87f4b31503	\\x1de008d1258cd0f5e66cffadd1ef15b54b3d4c81ee74e44a99bbec282a184e7a01bd9837466ddf79c864550e2b7162170ea65f2a74604b23f86d4dd25b4438ae4132596d256534ff960da56254ca6f97d31be1c94263cac5ce751c3a53c92b66dc8d0b5128aa7cbf62e52250467781b555cb3e192fb7eb0356cc9ed0638fa60e	\\x8ec0c1bbf4ccb02c6aab40cf3a2e234833e5103e665bae9c869626635638d561edcc315b8ff310d92e7e9fa81d790a1ed635f6de588c91ef16a1e80ef35de1d5	\\x7b207b4c225de5d37b62554cc4d7057f61da1438fc76b197d4e3d40fb3a76735d2b96dea84c32c57010f174b5f3f71201d458696f76f35b331224910dafe1f4ee2aaa05d117eedba134a0232fdc3b3e9c876b566d0f077faa8d01b8ed834aa7a591e9d1b751968f226d318e226d9c76fe829e318c1d860158c994c57468e03cf	2	187
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	2	\\xab2247c564f42470cd70d19914a6f71b707248d7a4d9e1acd2a8b4fba8d9081e59b7c32b84b46c0326920d7e1a07fbd29dcee2a522df698db1b02f311dd4fc01	\\x1445e53dda741c9ae4e0fbde723ce9e802183c18795ea6589986aeac17cdbd0ceff37ff1e7bb8fa6f59eb4ab577b5781575bd9f80a88d7e3fcac90d52e0eacd0ecb5744e24c65e17abe2547a6bc03496188a2ca4ef726dc7d6845d49de2cb3be9b07d26bfda5db7ec19552da3ecbb0223c2091d23b979e85ae18710f0b0c5e04	\\x34f46a96bb479ff28c84e5e6e6dde993a9c83305f45f31b183997f6dcdc96978b0347ed3213885022d40923f4e4fc737616a69727e799da143304e4bc46ab6b7	\\x9c01f1d85aefc7c13214173545803736c9b86d81e3bbaedc4c1384bf6699b61ad12252e7d070e7df6a5aa976d54e6b53bcb89f2cb79d3abf3082bec07c6ba6a6bbfaa827ddf03bdc37b56a13a9ab49fe006d54a6a7b3bb3f91abe2c0e4918aeccc90b98ea8aa14fa7368edf2ebe16a9d762d9be2627559f45172e34ff571ad5e	3	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	3	\\x448cbb63e8f8a86de038930120beb75a1609753da92b1607fba59b9f2f294b2813b2cc1409ec1a2b697b100c57f9ff5e5b8687dfb85bb7a75eb7e24cd6d1740d	\\x169ccbb18b1ec53abc97004e7769f63bb80371163fda0100fc27de1ee97073b1349d85392a734b36832e6f3cdaeade6847c47d087971c77b94ef4b489ee5e9a23cbdcb7e70daace640a4fb84e143cce498aea669cf43f8f07e7fe6f5229558f05fd3410c0d4909d3a5727ea0920754a43f34596200d57150524a83186bf4b027	\\x22aa268469a128257fbe3163c49ec8b52a4633e78816efff8dd288a333cd995122773c049b40f9c95ce72d528e35189d86524bebbbf1ebb3436e31cbe5df929c	\\x09acef636ce5da2c117218c90500cfa4af939410d4b7ab0a28091d0dea6e11b31e4d7d9f1dc29bc1e9fdb038f37573913d5bcf9f837f95b8f63a189f1548e3ff4894712e380945596cc2cf55c536c642c20645a1aafaec1b5057a445621f154ca7f4a6126dcf7798560b71eb0896d25c5ed63665ff62e9b0ba437a68cc37809d	4	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	4	\\xd931ca42f6c9cfde590b8c5cd5e2b0867f7af8c3959a00dbb7b9abb78a5ce69bc8b1b3317abc94381ec4c41bc1cce57db8c7f62a8997ab68a1ab4394559baa0c	\\x5dc8877eaca1d643a20afba74e20e067e9d22a87e8a9909577873aa217bedb4bcd4670b49bb08c320c6793d8c7c0fd84014ddf1a09f3487740f3ed205c5cd3928339e6dcda55f2e603cf6a241048ff2a48f0a42bc786558e732c71bf071425f0d90f006c3f9a3b155a3f7d2ca059ba74bef4bf8c826d248d9ab13cdb0962c34a	\\x68f5d0a7674fc2750c2f47ce7d1b810310be3d50c4a44663e7fb52373268cdcf4602967a10553543703e7113ba48292fee9471fe47897fc0d66f1e78ec860085	\\x751630e2c38e752f1fb61198f2318255f2da4a2ea4ff4a5e79c393849b03b0dd6a02eff152fa40183316c7bc33b06e845ea0c5911496dffceb013e289c1ae91a4f355b05317feb5fe6118a1ab8035e5de473fb9d29cb5fefbca489af0a9c469084f45c26a04e74934d6efc92c6e1afe160791014a302f2d912d184cd49823a19	5	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	5	\\x2123a2d1706bd39e00efb232d1555c08856b53cafeb3b4f86dfbd52d6b43e9993794b359110fcf8a3814c57cb49147c4687606aff0ae6d2e25eea2de1328010d	\\x9be9d814394c54c1a0478a2eab3b270778fa56e91d7900964395b8aca63b769125cdf31110de49c27f24a8dbdbb3f0bacfca787836231a188cffb181d85175785d74bf618ac446625b15bbffdfcb75655cb84565804693a21dd1e5487bcca4ac2187e5df827cd9aecbb1d6c168327a0052248f77a2c6550310c190435eed046a	\\xaf5ffd725900c0d6cfd83ff1dd17a62a60b98cfca505a65144f811324c459a7b67e2688c0f5c3a0ec98f0d8fdbec058be6ca8ed059fe54b3ddc4f6b96c6a0411	\\x41416e44a01076e9d9af59939a067ed41e459a5683505a0afcc3e7f42250711183bb350e1e9f238bf3888c7c9664d0e747b3c9b3bdc8d65c13cc95c492170f35da77ed63d17b0af81974fb776beb192babe646c7a0997b8f5ad5a1ff02df2833d034127a06220aa69521794ebb2f92689fee2cf58ac72aadfffec150434d6701	6	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	6	\\x0d6fc072f9f8586d02a45929cef5de9bdcd472ad2c83e64e36ff2492edf6c46686f47a6c713d8bdc96a2bfcb09f23bd9940f4d226426c17211ed1812cf118c01	\\x524262133fe037947048b4ffd679db330f804a72b64e15948a2de5dbd72ef44f4c6d159ec64d7f8b7c6f48ed4f7f3a485280a79482dde01d3469afd107da0a5eec0b472104a3270fa9962bc393d102fe98a354f5aaec469b86975513e80a33108102dda2004311f04c25a6c2995611027ecbf4a0962507898ad61e250564d051	\\xb372d7aa545112f445017f1f60dfc260654115fe34bae88eb30577f81ca65209bc03e43263176be964c6be63e811176f319eacc09fc068b8e6c1cff1bf5d72c1	\\x96fd76c9abc57901703c19836b6b62babe26c86db2a3ffd63b70fba7fb9883d5af4d8605b575df6ae59b93692644a622102f38cd5a445251455cdd72e6a24faa3ee519d057b9655aad39eb7d32b017a031b4e132f8c46763f2f0b7df1a26aeaa0270aa7d8512265f855678fc87403fcec852e9d02597bb105e566965f970bbb6	7	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	7	\\x3945283e2f29989bd3a798062f1f5ef06e39c45a13d169c7e73c9250ee4b482afd23698b9bea6902a6fe1edefa44f54ee49f3ff60fba6f42836dd6369e53ea0d	\\x070710b167cdfb724da92ae09e97c9770f6e463d16febe328a2e83d9bba5a6621e2d31860bc415d3a82b59236cd4358f523cc8f34aa9798a77e96b494a5c27441e5529c4d165eca0453dc92fa0ab37ecf9c1013a2a42fc0a1b69854133a9c82a39a52e038712a4c4e57674b77ad3f9ba1f0ddd6bc2ff273fa7203f6af35f56af	\\x58c01127051da5ef28b78a91ee7d181d063a35acecff652e62bef09a9fd9a087065cac155d8d3187cf198f1a9e5813543f9f8e213639308865ab4956dc7fcf2e	\\x1d86d41d923b9fc92315c72a5580cb11508e5f7fda9846ddd320a37b79edfc2fd01d71688332313adc51bd8af83dec7235c4f133ff148a3d060b3a6664ec80503ebea6f54bf7f85eedf8729b6a3af6d7cb5c0c72d12116baba7264dfecc371d595f4c1d45c841fc9108cf43e9beb31850880aa0ddbc97fccd1af736d1119b48c	8	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	8	\\x9792a625f1d92aa36f5806158c63d053e5655c8842066a03be2c275a387adcf2d2ecfe46c2c31a879bb89cacc87bbfaceb4b303a8cc7393e21748c757ed4c604	\\x7b8b729f45c8fd125f1c50573f64f151d9d71f480cd1e0422adab75e7f95eafaa51cdae717c565778c92408c53ea11ba9816fbc7db06f16abfc320aab94088c0a142379cdf2d52445b54c38acaf7d59e2870fae89d2ad3c4ab9b1ff0f02717efa7e017139399dd6208f279d7a1e1f31b643c2b28df972f19806f6ab0dcc70191	\\x4c44fbbd0baa12a85b48a6d20801f9f17c6152e672d63186349e1865a47959005d75ee76ff54e9c7f61e50ac9937f301e9ff85ecda5ab117aa84d6a214d21650	\\x71dcae35e0bad4c5a97fbb614541059f5630ccd73ed63f89986184fd39881848f7003474e5030ff7d9f18b87f0937a84b0479ed259ffe49835e8e2444013a88e39c22e3ebaad151eeed8d350cc403ed00b265f6463ceb855c1416eb75760180ae2b70c91f577d0453bed039ce1f0adebe62dc0fd774a773d97c2a67c1d051e2b	9	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	9	\\x536526181102829421045d92e0f4df46be18e98192d7968ce618b0bf8027c7b866936d37a4a2be7ac2f4d5a59be133c56ffa8290c46538e629e224faea47e600	\\x6d577cad4cbf59bb54f62ad5226f3786b087b68e9a42897a81a8826ca53861dd229c44e897d6b2c34ab58e1dbeda9c77a3bf98b10c6d429641cf0dc7b819692901acceb724acafd7029eb2d0bf1ae168ab2c112b9cf9fbacd7099e78450b93c405244aa88d9d6aed7242a5a532fe47e5192f4129ef08fe5cca6abda973afd5f2	\\xe15947c18cc081662451c99fb70af03544e8f2a5b43e45ef6a1f7667e6ce9734194d41758ed0c201b1222bbab0bf3bc293a9c4af8ab7ac2db040bfd77114f72d	\\x5ace7d13983635087d8edb476f0c127916ae26cddd929b875243ca3e60c5007faab017bdacedebbe4495e3a99de3ac7220d2ccee6c399a1c1f31163591c15ff8010fef4dfd1e37e5db2ae0c456572f0261ea421f7d2be159985e38359002e93696498e9d1f5b72186b04d18ae79558d72e8d1f7a77fa59d75627961ec9f3fe11	10	271
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	10	\\xf85e7d91bbb7ebe8076b5f1f4009955c9d0c034b82843162797e157a2a4a8890c415f7817cedbec8099a2888ab7e90af0e7c0075d131318061da49cb9bdad604	\\x2e438ac604557375f47029374bb8c478b4a85a38f960b50bc548366a6f853897cd14d695cc2e85637913cead8ee705e284e47a1e2c40e39f53876fe05e0a2cd78834334e1be2edd3e2749fab54fbeb6f5d940fd99647720efb6a8b53cbbf85e9a280e00044723a719162c6f31ca4e52565b6ae58e178b83f78f4cc57ca849e11	\\x638a0f9dc21fc16e72c370dd8d07ab9b73eeae8c1f733ad7f6d1006e9a04ac7bc9ce1d0fd2d2415d5cac3be94b23d513749749dc93d2d106fc6a1d18db5f6395	\\x2b31bb6a612759e8bdc2223fe4b3dbcf34164c00fe52e6e366d29519d091b156243e2baa71861e0e492685538bc5321fb25379a3a413e8df37ec28060a5d16eb210c812772350ebd794569ae8c8a103e85f7d8fa2322e6cbc542741d353104575f2aab0dae3507a6925923807de9cce75cbe3afcecf90450392819de6226780c	11	8
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	11	\\x305f1c6ecdaef0a90883baf1424a0c3fdc9a796015008fddfa05f4a73a551b8c5e9308e3f4dc893f27b22fc16083240b3b34e368b5b03b406e1cd2baf39e3b0b	\\x1ce6ea55f56d772432495ea59475d54f31c2ce6a6cf98f0a201d58bf9a6340541e4e4dfe5e5430f0e1576a4f180f8367b99b6b4b5e83f031b6ace0703ed3c2b4b66e0d7e52d06a178a7df0fca1827035b267c753cd740040085aa0e367771f02e99ede1bd8c231b9e0c508270062376fb518330d472cd5a9d1e687ed5df1717a	\\xf124cb82482598b37ffb38dccfd9f08793a44ac1c99435091eaed97b623775e58e691dd3556753ce19f9c9982edbbb88f29aad4c66387df8ea8baf01b2bb1762	\\x9d2d73c77a349887491ebc891876fff4259f6b26b0710c07918842228c4e859a7dfb381488c71fa263710c9eb6804fc61adaf732dcc359024a2137d07357ab8bf85c2fe207610238faf0ddea163c7428247558389df5c434c4cc99f79fdf226bc93431be401e5553627ac1cc6657d4caa4d3c5734cfa8989d734485ec0559c33	12	8
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	0	\\x3fb46964d0f9272dd1714dd4e61904d71739ecf0f815ac719c858b093c5822cc27e1f39bec2205ed8c3393609ccbb76f122d290c378ed3117ecd066b591cef04	\\xb14f45f4ba88a5c1996cc219071f3349b089489c72765ca0889db676d7067e9c8f89fa418e8b0a5c2884ad6b6e0fd0d399a6339e2550e2cfed84170e5b0b3239809b1b191a1c1790aad8e494d109c0b915eb9cd63cd94612dd78459523f0d635f00cf603cee9021a88151ea3646a2fe356302a498ce3351df36eeb5c7c7946bb	\\xcdc650ff9b774c02f9fb984d73acf3c0ad8d753f0ebeec62457fdc7760d089b0dda085f6853f6d08d6f5eb24bca37477160345fbde0f0b1ddbfab98adfaafb8c	\\x765e3a9b3621a0c1d6e49533306d5d485678d9d128d42a8e3911eeac77b453d1aa6c8606cfdcb0379393fc87f3f248b9b8c7aba4078204b6dcc97f9410b550ce58af1967b4d917b385f5e61c9d91af6216fc6a0c1d07323c0804ef7076b3009ce3da22d7e9762fe825a1cf9e1db261b5d214c7311844b387d9ef23474e2a1bc5	13	307
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	1	\\x4e3d9983e4b4a12dd7545ccf7f47cf01d4dea63392a29a1b08b3a810338984e8df5d61007f332f0a6daafc0b824141babf445773c236792014e31d0c9e6b800f	\\x18bbbed2031e20ce0b7ab3e2a59299876360b057ab0f9a1d7e1c4186c443d9c2006fc8b016c0305ea70076a719e10f0aa593bd80f62b3579e484551d3c7a9ae2fe374fadf0278ce85e4888629918e8d5951f9819c7a42eddb55e9a0947443e5ad2cf41c650116bc93f2db99b60e353408de28f9ff1445cc4b38a97a4e3b93bf3	\\x97f687b8255870b4007bb9b64efdf4ac568137c8217d7f16ef72a92741494f600759c499d86bff06b7533962dd8a391c7c2506f2d2458884418bb48264d61786	\\x67ab26453234aa49da7ec500c8da98f0cf838baa087e6746ba09319ac4692ecbfb1d50a12236124b9b2443dc6b2e14909e31abb127839e1137b31dc074d5774dfdf7e4024e9caa22e8eb49a8df7a16897c0ce43eeeb316c355dbe24522ae7aac0ee63fe055e6b74c841abd956c717ed579a27514ccf3d09c45f4a6eed18e364a	14	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	2	\\x5c65fb28cf6fbe413a46b67cd64bfc08c490a802439d30aaba028075d0548720ab4b58490021f439880bc7c3ac11575b54fcd233674ea07463817ac3671a2308	\\x3e9e9e60f3c88c0bdcbf6ef2c50c86e32e94a93448c3d5795e96a8f43e5b37b761cf73c7c4266309d55abb34d69302bbbd6ba235c6078aadd4329b3e3a0060494aa7af5775d4975b5b748bd16d7ce6e888b2241d645684ebc836330c2ebba5c2eb0e188b83f65133d2f35d282e54c7e61b8c406c915f7753f3272ae779eef74b	\\x548d6a5e12963e206ae818c44e343b9619bedd315546171f2d63bb39f860ad513696db78638324c4f6b38ccbe09705cebebe532c2316dc99b55cf64577f3e2f7	\\x2555f6700a17da9045d0482642aa9dcf9c7e35865e2310860eb39aeacbc3efc60215d369001b344a4ba1b672b8ba5d9c346839f4b758f92d881f6acca7364472da12b9f56a4859f87670ff0a375ea2d1597cb406dfd9c0c7a9443b8f4d2959032bfa53b59a37898ca5da2375057a35eb34ed85ce69429146d46a48e5624f3dde	15	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	3	\\xe082db1ba8915183eb0ef165b1b8a9c821a6bccbd191873228526e9d90b642eb9b89f354127d26abb78242dae54ad58e0085a1389867b3620e154bd729d6d101	\\x3c5a1f04ab5d9bbb1bea837e9521fea17806253c92765495e9f4a4e96e0ac9b5a4e999dde7ef42775fb9631a49eccf05fb6e330d8d7414cbae31f14642c8b7bf614fbe40f1153cd89c22e5974a89e7e96a4b067135468934473cee25c76a026a826e31a8856938c4d065517e6aeb13c15bf4109266cc49c6285bd38f4ed658d7	\\xf12f90547fb6e2b3dc3bb15ddbd226c57bd6160f1cdc859f235763823817e679e0d270ca332ba3e8923ec19aab429b8d2b7b29674cb5941d6d563b73ab218bd9	\\x6821796c21b0bc7183cea65255b4af369aff86a8e3c917f5a8053aa3d329dc8c146a81282ec92d2bc22f42ca3cceec37a6d23b17f32fe25a952d9b129cc3ed87556ec809678de455894a418be2b535bd383b8dffc699bfc90ce682158ed857c7be029c8ba1f6929b1314ce75137f735c6b47769347c2ca510d4a047bf6ca4416	16	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	4	\\x74816224e05e51f1ee5e22666b1f6db2aff00fd0dcdb3d1be9f22287ba970805cee698f36d4d8f57be9308df7fceb2f17a101ca27fc22abc741bc759dbf28307	\\x54b5fcf05edbc46e8bbb6b77fb222255e6b889af3bf7473fbd977c023e3183f284477492124610c1bd92215c0c3433c5d7a2683e64e795c8c46e7b40659bfcef7e8a241c2e436ab5325705d7e992f9ec2abeee25e7370016a1c96605f0adfb1074509cab9efeb84b3118922b3afb1296086f7007a3a1d104f127a5db40942e62	\\xd0d05aac22fa65fe87be4958647c711781501b14748ecf7be5f12be24466dcd7c264983d50373d7ce19f738aa2b6817fdf08c06684f80d06be09d7349e1bec24	\\x4c01e834bfba3e84c8d9add46871302842b0675066dd280c017932497a5feba382f117d36b28685b71907b70d8335b4bdffbcddb568dc12c5c409fc8aa30a74ba8e0b6535dbf3fa1169a639c8756759b3b7a3898939b1f04b06ee76ae48dc00fc5ab8af376cf10b1c218e8a6ea1e31b2a85dd3f0a4358a4f627a9ab491f71853	17	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	5	\\x680719cc88aa152d686e368faceeade704e13da8080b21c135523eb1fa6d740e25565697ba65bf1cc9acd890520311e10dd0f724db406b7176bc92ed64458702	\\x89359c5b709dc88fb1f1fa412cf7e61121069e8b14d173c2cf581f5227dff424ce96a4ffa93d397db5fb174abde48a63bed2c305f78eeefb10fe0b9ff59a05829986447665f571fbc78d41ef402953a6060c36bee7b2e48a95b59f6b769188f4233139e03a50eb734186366fa3e6d77bf129232f8c9ef9828e78203e2ce5ccfc	\\x2bdb3f9c9351be8c2f080aa2a13567345d6185761bb400eb2ff12b48867ac8c3cb95a80fa7de958781b9a66932184c194d95b1ad53a992e3e2e6447a57301b1d	\\x62ef721bc30340bd339ee0fa3b3e7273fb8031491dfac35b0feac9b71a787ec126c7dc0a75622d04bd9355ec588c3dd7070b38b5384413f4257059369bb6c92d7be43ef6ace41e13a203429cffaa5f3d701b0c6b86c1acfc6bb2b5058286ee922deb502b413520aa944265bcea13debaf334fce607644926746d261f7c75e811	18	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	6	\\x1f43100f273c792c511e827ee8a6488df7e7066585c1aba454d3ca14574be978dbae2d3948907e2491f3cb4a1df163be0f475587191518fbaef2a48732002a07	\\x7686c3c7c70bc3b7ab392faddc626df41866f40d09e8090f4d08ec1a321b4dfe926727235c570b6c342eab9a88a031b32c3f47c8bfd01f8ceb9df6a29a50d97ffdca168bfd7c7d3b58c407b8e0990aabc0dc5b57ad3cda7c78fef7eec69b863b718cc9b1747a922b1897a6b4912f604cdee78eeae9eb1b57db3a828707988a93	\\x98d3e750b62b8d6a4a6deb72865d0abef8e82efb10c6cea00c2bb91db1b2040e8dcfcdedf08526fd005c69110faad74facd5075a688451302edb784ae5f47462	\\x0107b51f43bf2e214fa399fc68f1e13d36e631c3c35d0d6fbca5ef3e6477d1ab52871cd41a0e1aad6584a70d14b301e636523b1c0e76d6fcfd238f81d498e2222fcfb257a6f1433f2274964ba6ac3d71d361cce6b270f310fd4ed75cebdf9105aa4a673ea14c2a825441003810ff09870a90534445a6b511abb29ba71ab22cac	19	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	7	\\x21c1f3d9fb33b01742adbba1b2564aac66bd0ede6775da137773d8154ff2de56a078359b9bb3052d46ee52567b077b52b4b4719eb50b16252492d06487f4c102	\\x50d57a1d36e08303566a615f59ad33581d41fe70fe26997b12a2f5169e007c38c9ebb62d251ff2aeb324235a2088b45df4f9ecdeebd5406c9cc4c7ce665dd62dcfaff9a930d44b281c372daa3227705bfa990f126b1aa8ccd41a8a293e81504700ef8c0093112c2562bde71648df7bfe055da5f23d8c9fb90b26814b78b3d4d1	\\x0141da351ebcd67227644efecb8c98097b54ddc7464bb080a57ab2c32620630aadf08fa6244fffcd416e1fb350ee89e305bb19362fabf6be6109b6224219367a	\\x1bb2b62d79d655c8d2f542315ff1273e4d10fd5d19292072cf4cba76654f53f136e4c2837fb58c2077cb5fc0c96e87bcfc16e374eb59a28ad3f4fa9176def0eb7dca00e6c5b27bdfae49dae68654f7938b7ff52a769b4c231ac9d265742a83f8901c38e5da84f037ef920c11a189b1080ddd0f4b3fb4a681ecdfcec3fbe16034	20	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	8	\\x350b2a9de359709b6761b6c4f843a497be25696e3bd94f0e4e449002916dea2349518d4028cea13faca83f109f679369328f97a79263722ba02f03a68889b502	\\x84046b9f84a9f56ce3beb6bb1ce381b6ef34e873e6f1ad4188177e7df97696ee9d1cd8f51c9f88714910462e6f82e8ddb2385beefc5b2e635632b13553579384959b43bfe2093ac664337af5e41cdc5146f24653ed9052e5fe0bd38db439bec0881bcc1cfdf83f0efa843549b191ba2b634f2a01b281e5c76f5a1d155ade07d3	\\x5b07bb4e897db398dcd6f18b317f833109034858b25c622ec53411613cb0a9395c9c00390fe43ba7079455f5a920c1c7b977ece3728a31efaae0f8d0cdea5b7f	\\x2572b8fcc93b88545f1787276d75a6d42552dd5e6b8c496a59b3369fc63f180cf8314e8ccc77abf972553da5cf76ca5b21f8dab0f9e776ec2f5134c4cbaf1fa91b4bda3638e08af652c98564716a62bce12d2c345163bd843824c3172487a8b9356a413381515deeda02f767e80224a486688daaa0de21a2b42387e918e66bdf	21	271
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	9	\\x01c637257c428b7cf911a0e73b47cd711158fcbb9ab04fba7e1d61a221d572c15c72013428fc8250eecc3e9289f041b176f0942f2152734066e40e00a030380c	\\x78b4e6c79bfb7cf56ae970bdc6fcd786cb6757af95690d326cc5e1e19513496c94d1e4027f87e32823db2a7808e71a6bfbd31713e2c4a352d07b5442d1d20b61968b713fa1b34d2fe968acd9d0a0801882ac99e0b32441dae0cf671cdd350f04a4a7e8f30c3b9d6dd8f30b2faf69be5c19b313390856120e24bad62c0fe84c71	\\x6e7a6853a8f2ddd48b59580e7127752594346f60b364dd236a112ace1b1fefb2cb7e525f97d9eb5b867d9a5d37dd739325bd32b8de774c4c187de1885df4f2d7	\\x18b34ac0c476933c83b97cf117948f494868cdb85a903bb141b62a991dd06563fa2b5aa0c032ab0d92d4b3e759b1d48d8cb53710b6116acfa9db800b6162ad560bb3967ee568707d7b4b3f926bfd94c34560f8b445c140b6fbee596cc9c1f562f2086ffcde373a2068e5b2148eb051c4b77732b7985a2055c26852e953b1254a	22	8
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	10	\\x716a568dcb9faa4946e045476b885df6f4a3c1b78e22980b0ab6259fe3ff86cb2da58fb7fe5adbefc86c6dcdee5133022295f391e58b8b4665a1b154110d0d0d	\\x7aad996dbfa95c4294220bd42274f063ab8267ee47d8b1aa781faffe247ae8104f7bd116eba27d86232521eca2e47ea62bd92c6a8481d8ef6841b8ce49839ed4aab8bae6af05afadc7a3711cae327cb605feb74cd8c05cb38bd4d05f1e79debe3806ba519f71ec6ad79178023a24321ec724036a9cb4c139785deeb831ef4431	\\x38914921f9f2f2096539c69ca68d2ffc581023cc793524303f2243413c60c3dadd7a302e8878a573348a956ce994e2709f90dd7b090cfc31f6ee2213e1c9f436	\\x08c6bcc2b9c5be3e4f66dcd8b288ff16d71b2a3cbb4bb1337ee6309d5b086da9313b93f4412f4897a2759a0f0d1610f2ce2c7eeae0a1c419f592cd09427fbc9c57ab019d798695cbeec22260aac19e308f355337911ef6fb96bd0f6278d67d81fcabb3ea0046b2b0baae0a4435e0c9f4d4415eec01ecfeb3d5cbb1617aedf734	23	8
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	11	\\xecbe57ab10f5827931c1475b3757f145c1ee93b2f51aeab4f12e50cec4dd45a8ad5442a7f7ae88cffe325c312c06fe2a4f33671eaa5679d0ec662e5cb0b3f80e	\\x08e8325a91183a7cb199cff62b9c5bb2a3b5b1a03c2a5dfee80fd47f2a312f6cd4a84f639709db7de104182aaf874213f52c3fc6e8af524a68f2dfe8efd5ee23f608b2a0ceaacd0746f2cdd8159bae475f00d5ad66d6e190e07f1b273588a36bfd7350a4609aae6e73026a8c38d9261ce8e6dc76ebc9d4bbc2ad295b448382dc	\\x7004500271168e5050bfab61e3da049fc21ab89c563ffe4368fe6e89bddc1438bcd481e60adccd5bcb6c9d335a6269d565838515b917aedddc15acecd2c4ac75	\\x3556d0b24883f2c5d41010877719bc674b983308f07795a7c700e881940490af4dedd410303c99e58d64900bf47ef452938687ed7be0941b957dd52c92c4ecd9e74c1a410535da185b319c7177f1af73ae5bb19e8f4623c9d6fd15a79be6283f414480c1f619156e0cc3e4c65c54c6e183724f386eb08fc24ab38f1fb6fe75d9	24	8
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	0	\\x8f17c56567d8f762db8717425442a2334738b740dd2a18b53ce065532a2e3c064f8cc3387c11dace611e7b2433e9d7a98c513f52c87ca1a5878368424230e70e	\\x058238b4ec8a6838a4e7c44b44aa9c831f2fa0dc039ae581164a1cd055249989a954f1d2f1ee28847b046983314f868d6f0e362516f52e9ed2eb238c4cdcab305e1aaea32d2f8e16eccdc75d55bf37f4b31cf3082d2863600a565402da3179b66feb44bd56d04e3826762ffe29fc7bd251ddeda418dd22bac963219da7e4eea1	\\x77a4d178807e06e3f6468d07d47f8f7eb6d0709b4d3fd300b0e6bcad198ff0db5001be64e3b27292a9c17e5f1ce49393d17425236e4932ff58feb10b4bd74be6	\\x75356b6a87bf5bbc200014222b79a5ecb30d9ebf45da65935de7531cd261a80d817fb7d61594bfed3c85409e30ceb25e1b8afd49c8f285840685487f600248375b0fe61ad14bf4a445430e47fa7fc0b61468df102082542572535048fba4256b57be8ee3224ab95bc6e4033802c8ce1f774f48df7d2a99fc5f02d06667eaa019	25	79
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	1	\\x64afedc0f16815cc44f86c703cadf158bf69f36dbbb7c5b4f219d17cac9701dbdf58da1166835748ee043e490ade87cbed3ed967bb285b2d0c755c3017fb0d03	\\x40344bbc5d3fcca6573c35cfd3781c5e13dec209357c1106dddea1050067326814745215436ae4d185d5d462b9086af88502b32e5341636381302d3af8715d992f773017a51bc8d50b461613c82548327a7a15e901be82dfa79f3fa80b2165fcbdffb098bcaa0cabe8ca769fadef552428d18b2dfde0d84d440c452aab222a19	\\xc5fbbff7260de4b40145375e0c5dc80425462a6dc319039e274ac692141162c50f52422bbd3548e5ee60c68d740abdcd57418faa4bc52cdf05319a610e47cf34	\\x2cde8c29688b39aa0b0fd0bb9c9677a77a0170fbb17278ad555e6be09fd38399fb5ae9aad95b78e2b7238696dfe76ef06d848369a0accb61e62e7f4490bb5e0d89a8d11098b1eb822edbc0c7e0daee447837a08af18a59ee60a824a3eb4c52638ff849999487865185c22eb33d04281467115d40e0fd78159864efdc3a2ca7ea	26	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	2	\\x7362ecf487ffbca92d65c39a2a9daefd76810496b20db1ee42d091ba923f0d252a82c411e2e190ab7d21659a3d85e0efdaec5e9de894e9193932850f7924b004	\\x8dd2abd5e0709577450c78dcd393f64a7bb5227356ce9f20c58ca26a21f44bb5065b2fde8b8a55a4e96201251af95c90ce38b4c9d400f131f753fa8897ab683e7a361fca9af21fed543beccc99518112b93d63bb4d4f15b4b3a5094137f31e5786a5b5ed6108d7441adc27dfbd34bc8000d853010bae7edcf10e7e61414adf70	\\x2231bd5e915aacaf5f15ec4585371b8252711c39b73cfd723c1428c8d77c77afaa44cf3f8a53b7ac0c7834c7b82de6539c852f24472975e0b05a6d1cb7dd8da4	\\x125a831ecd5b53347704c1e29ad28ef7a234c8a82c1c60b4241c22ca5168907c8c6337278378a5e4254388cdc480141eb1ac40c623c2a4924b7af9d42b521aff63b340aac29a9b49b9dd1c8b67d1afe30eab8f345e26f4e51af1065cf5db4e0c5b3b21afbdd7c0bbc40d36ced93213f4fe5f30818a640a705433c626bea68bf9	27	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	3	\\x42484c0be92dd980532de03e370c74e384f9d8f7dcbe1f38a4a7c3b16b666b02273a83344673b4e9849446ec643b3de055c268e264ecc9c7e574e01211ed3f02	\\x42aeeee166e12182fe38620c27fc1156cc4de3d51661ac7e11fe5114f858b359ef9823f75e7da153750c329219f4b04486cdcbeb0e7fade029e290887621a045e0887e88588c794c44ea83cc533ee0eb51cf30758bc09648e8e6c68c3ee54cc1007bec732e51aa8a8291870165a1ace2ad97c3e0fc22c6584bfd9757cafdac4b	\\xfeb63dc23c9ada379dc290f1a6ff5f4c3d946abf3bde5bbf3db3dc1abeb0af551a7d2747094de63f65c20a768053abf8702f4cc011d72326708c2890cd03b84a	\\x961df9644869603f89522d0043b6d4cc6d09554d428898bbe31a9ea0b05e2c06e8599cbd2c2fb1e2ac2922ab8b6d88d4071055e7b54ddb070b289a4695c819dd8b62fe9d46cfd824977b7cf31fe55a053657d30e3ac87e45dc15c62821721cbed29888d4772816c0fc4f0d8dfdd9e2b35ae2a0ba3d4d3438a424961a71830355	28	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	4	\\x2d7beee620f7ff06567405977e9149af237220870f9f2756c8dc67a9cb08065bbb4eb977935dc5cfb482c8373ed59ed27ad4f5966fe2eb99124fc6ba19999705	\\x37dd06d566530d56d13e932dd9ec555235f4f220b0f3ac34f7223eeb651c1de9f9164d808b20786ed08fc1008d013b9809c2b05a6968b74a57f31799b935a2d8bbe28e8208e7883190fc514caf344d0094df6282dc09f28cb3327579b1cf816e3bfc73f6f775a393bb19948a9fcd0b333e2fc35db3691f4ff545ed70b334ef4b	\\x3505702a45905c437ca48c502f2a57f2e95c424395b18027ce918665bb95ac7a5eb166c2e9601896dc9ab22b2e7fec833be0411dcc67ccd7aa857d65ad77844a	\\x18dec8b85a7cce5ed4c6231f24053fe6f3f56ee61e05fa49f4c5bb286781bfbe8681dc338b3f22c5b25983eb9f112e94a71305b69c121abe4baa342848e9b437f5a9f572fd3e2ffd4f21b8c3d67eb038c061c3dff5ee34ae7c16bca7fe485b15ea62fd7510bf8d26178dde43ec4e11eae2e15bac4242df46d12dbc6ff526be5f	29	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	5	\\x3772b38c07bcd47bb23834c139fceb1a31253f1daed53cc77739dce6c15fc809d120f07fb685bccbab4af64ececde19ac02ee21455ac6f3064bd6891333c020c	\\x278300cc2e2aba7db64de121a259b469c184892bf7ed99176497179976af7e3f456a9702d328a0a790bab8c1bd82a192e5fd3f2e1c9788be8b17eca15cbb2444bb8da477fbb98516187d4c8d8008a7860e5e46fc965528e78d63587bc5bcf4aa483d5b2c8d2b415fb828d7879613c3e8fb5fadfdbe9cd1e076950729f0e4cda0	\\xe0663f4d22a83171ac3da1d6c31356e2969031de6814987c0a482693727bd01069dd9e78d644201cfb166ed9b7cbba3651ef85abb8bc35522a978dd78dcf83bd	\\x4b91605a97f798c5c8cc342e97026e8177398f698c34817cfe1180021fe697b08870766dd99b4b5f30fe2c4a722212a750eb44ab05bd96f875b865a019b08e7c5cbbd132d7d6dd20a884e9d89039860135124a33cacb4c79b87ccec3c1af56472197a4c1957603555dcb46ee1608ad712d1dfadb5d405d47e08c20f95b28bd25	30	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	6	\\xc4a6d886794d5b7e7c88e049a522cc995b6a379396e5571277b00c56b6661ae6b0696baf9b0a8d0ff00234d02b057481d506c0729e2e2dcb4ed2d80162fc0d03	\\x902124455b9b068a7bbe2fc7ade784115d799ffa19ea13da74fe0dd3942e53a667499c22fe82c142f7249e4da3d93ab1e4313788d08d428e4f2ad09656737a94be02be467eb88ee988ed159b732ff03115a893c0d6a493544aca2d4d265aa038b8f4d8551f9b8471a20e0119a430fed8e0c4498c055f15d7c57929eb8b574017	\\xdf694e2e5b4c425e6505ef9128b1698bf05be236b2775bf895c2a531702977049b779b9cdef334df657d4ff6169f9f4fef95993585b7f1c2ea7b119b629c4bd4	\\x59e83ff0417eff23db1cb2205c5f08a8c7c6adfc17eabf55cf82aaf3993c315f4c8e2d18486dc72ef063a55f9a1d522a5d1d4b9277b1013aeace64ab39af8c6379fc5e849ecb47476866907cf409518a77fb42795931d00b5d816fb2471f81de3b3f2dfdabf103e63f8c14d92f9d65638fc3dbfcc6defae1191ebbfaeefe6e2a	31	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	7	\\x28863e70ac3a67c6216e950006bed13dfdfb98137a27d55f06d787ba4287434597436666046fa5811fc1709dde38ee7d5d4113fbc614b837d257352ee8951507	\\x3a897bbba78d4d0e82c3378b7b779cb27f71d149b6d5415d030ad07527852ae47fe24dbe41ae321ac5d20a1a1ae23a8b4949b92576e7e7771e546cfd7942871f7fce591896b911c79315acb64cae420c33b6ecbf421c76f9744bcd4d5b730829da678a1600273d92e2ddbf00767052ff9305efbe720738ee047046dbaad32176	\\x65f69a6cd00aa69c8b01f0ce82f5e41d9a77c51307bc03a2a24cc76c80b03ac07c8f83371167a79ebcbf67c6e1c6e38aa87609cda6811d7b429797042f4f8c10	\\x028ef96d5195a79db3e54637de4a03e4c9480f43889cb000f21d1eb061210ec48b4a0f10699276fecf9941cffc767c7dbb8c50f9e38150be6a2403adbc733be478037293151dc9dcd9829f6dc1ed861916f73bf3792a7cac68d0c2e1f9965e794f4635f2bf2d869c9e1d7b4c806ee41ddf7afa39b2dab1bc16ec872cf3b849e3	32	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	8	\\xa87f1ba7686cf6ddefc529376ba985d27cbbebfccdee14caa6ae94cddac166f7fbba58a9b751a6fa7700aa4071d78f717090dd2e9a3be7dcbd569db70f5b4a05	\\x16abb659f0b7bde43aaef9d384952f6f20ce4841a956605bc4c887190c5d6bf72ac2ed240cdbafe8be98562f005ff2f502fb5ad0ac2ca0a625b70cb7ddd54b8dc4cd4fab4816e1a3e6718a090d1abda75a2b7241234a38247d896b706a3472e77319ddaa0af64f1fd15601abf90f3e5dd46e5dc12ae1d9acfa5dc0ffc6f4d8e4	\\xa7c18169f2c88eae73fed24dc2908b24e35c3b269f26d59bb074df2ad5e706cef6a87f1bd68badbdfa92750ab6b96c30f9cbc46bc57a49a7ef8d8b7eb747c0e9	\\x79819b151b4d22a8911aa58dbd6ce918c1f741d6553ecf6dd0c2d391bd36edf33e296b99a13d34b74747c24be8890a8f0d395775ff72039f242bde9bcf267bc56f4dafa70e621b60a8f32308ffa5de0de5293bd70c391d5f3281a7f8aac49555efe8b751d789b9b1553a813cd83967a735f6b604b420f2787ad0b3b9e74de02e	33	271
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	9	\\x185b1df785ea4b1056449e3b8c3ba2a43b919c842dddc8e5bb405b16bbd96d08a956c1df82ca5fd030121b4f5db5c02c267ac2e5fec49abdc91fed37c743e803	\\x1e9ba494f00af30b174f5b9ca02b6ba703d935942ab2921aec1e602969d57d8c24a7dde18eebddbc95bfeb3ac1977b585efca3707aa5aeb2a1f55951fe2785a39e92c599aaa0aa1aa7eb8fa73d39e8be01bf3548651021f9276902f5a53ef1833d52c4be7aa5c1389199d2b4bdbf9baac4e350e129301556e572b73bf3dd8361	\\x22ceb2e1cd1e753e9ec1569636b3f8c86d18b9647a6169dd37cad1009080905e60e4f35a6c53d968dc313b188f7811e0784ece2a3db1aaded8f1e9c69ad84211	\\x1806efb74538d5903f94dba669b636952687bbb1a45961811a94d1817d92e0bdb1a7a48a81772f8837e88761c2a0dce9efd13f0999001a732dd04ae003d5146ca43a77860679f75c7f5a9177b1b430c5bd883706d33e3be6e8e403ed2114562d2cd19588fcccdea9903f2fbfa05412d51167fa8ccadd8e164ce2e8e945897420	34	8
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	10	\\xab63a2d8d635b8d8cb72969ef85e9fcd1b82513ba1321f81c8ca6faa2b458f777f599bc40b26a6b1d2d388fd7e3d428285674513654bb8fac0fd1362f287c500	\\x9a10fad23f9184f41055f7d7470b668499951916a7d023d67b0457dea05fdb910889dab8ee1e741e712311a03bfd6c908329593cb770e7caae7cb01f365ddc38d41bd57c37ac27f5ec9d33da76508629eea41e76ba2469f66c3d71fde1de3fbf34bf96fe1081d9513918c720b337ecc4aeacd4a590176ed04cd51ec45edee668	\\x616e789f7a486befc5a2b1b96a4bf5b25c94a96e9c1697e6a36401ba310bb683aa172484c72dd865ae55735834e77aa5640ec16b04da43f0c1475533a91659bf	\\x04fbc0bcf131fc8673c3420168152c0ded06e7c39b71a4fdbf0ead023caa4db66fb0a4c5acd604cd101e6fcdf838f3954176ce688ed8e727b3094172c816b2ab9094ebd3e04eb965ea91bd3eabccda75b77027f6baee50c92dc4016e6273d5b2ec485ceab9aa73559acbbe3b8ca9d86fa071af795a776226b853a61b1124b66b	35	8
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	11	\\x16f12110a301cd763ba595b04c40f9e47d69bb89b75f0fbe97cbdf8ea7339deae0d64ed9b4cb4773be847134a9765e80753335a9b7b9845f193990cbc12e390a	\\x250af904a9be2db95cd62f7882597af5d9e59e76aa5ad214ad936e7298a9127e06c9f856ac883934d7ca721ea674846844534a5938d118e4215026169cacd458e86ffc90867ce0316cbe04471e7dd0679b500b061d6777a0ee000b3638b3dc6a292f229e094c8b4cf55adb8da3ebdd1c5c1a7e61c75c2e22383d5e54e1da60b5	\\xb2d06377bec176af9baebf60fa9c9dbdf7e4b744db6e8b510d1b3b6c8c269f3c23c6ff40356b27cd65a3e9b831763f78aa9097c824a8d606dd940282f277e603	\\x4e4f4896c1db5f99527d365805f4aed768bd86079b81706277d02596f3b5c0231c8d9cecdb62adf26ed35e7066c8afca318d96326a868a38be2933de11c331e469f4d393f7ad2580860b572c9f128cbfaad4ba7d26781d2f64db7c21471c4f1bae0e2ecb7420851bff5a3ab930e632f46d1357d64918d6d3b1d64e12e6961d49	36	8
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	0	\\x3c4b55d99604b8066059781d25c1f6a3d1db4ccf14f9d21e6b37a10334649b231df5f63b7542f5f8fa73eff04d32855be236ad9c600bcd9b3576d9c53d277207	\\x38854ffa46d9b04aee91e6cca83e95e4974b1308d05f89bab0b4ce8f9157b0dda4b76eaabe25d9c23b0053a7ccfd708ad614805e4dcd00a61b78c5baac92418ac7427dbaaa01977ab67adda643d26ca73a92f4dc98d7169b6f4a5268f7d407597f8f68034104227b88b33e905da7366c12e4fab1780fd377cc7d9eb67ad08f4e	\\xbf19429e858bcdab1923ba094ee7b6499240ca91d93c78f959782f2bc4da865d5115e101e4e86bb67df268dda02bd7bc79c2d178d44b0e6bce7e1cf609a724cd	\\xa27974c6d5b452a9892b6144fcf228887923c4deaac3613f15a6ab387756e238f52bf666af674934cd605bc47296ea3a4ba6a6f7c4527f178503ae5a3d8aebad0f2be1e7e1ee6af8213f28e192f73b33f618b541502a014176de804ac4caa014721c96fdd7e083f911b9f4308c5736193692c98690759815a63e20fedac2d948	37	187
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	1	\\xa5585cce86119730f474c5cd7d342b6d44ddd06bd53245a035ac389e06cb82404c50dfeeb54a6ff2a7db8a461dcbbb107cc77eb43ca8667ac59f6a9f7f144a0c	\\x64e75f973ab1c4378baee40ec53a5c925cbbadf9908812fa6b2f892ef431502315f066f3b2d59806e3fb4545129e076d68b5bfa44f39f09b80e25ad9aa48cdb2236d06643573321ed2da57c8f80029d96406f3d7fd67b3eff08dfafeed1e6753d98965f6e45f2e760036a83bd4d8faefbfe83da3539514e917bce1a3fc0adc3c	\\x3dfcb64fa7be62873d7add06b4e9bce97c1c90284bc3f9ae9c8b38a78a45c1de7c4510650b2ce685c3b89f74cb4910f497db28dd080ed6fc0a28691a71de82a5	\\x8722d8c3fe93b5c1c18eb62250094455fc69bbbc8f49d0f23a5414e8d64119b5daeb822a093cc5d95094ce88ea4015c28b0a7c9185887ba7c08fdd273f9aded6817268faa0c70ad60ed69792d2986947b3d0892f2cd3cc73f4d17d34ca4133ea58f75efe9d4e883b13c6a769050df6e310d531a2be76ef8522ea5cc247309386	38	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	2	\\x452f6aff258263b604103d3f05688a85c6452848bc1e41aa26feb77a37f48596320e2beda798235a7bdea9d24269a663cba137422450dc99f456d715e43b020c	\\x6baa057903bf68927c74327528cb191aac0e21e5fbfc2daa7bcc903f25236f8e9dee8af85107a31c22094b7d1b5a5b412d1e70de1ffa7f86e2f08d00ebe0cea2fe5f52d9c9418c4fd3e3b06eef4d97a8a2cca7ead688547472439fd003b59172a7057381f761e5ec720e70beaea09a28cefbf2861dc4c8571f87c863c280cd6c	\\x80240a16b1b191f02dd6441f509e074af2b4b0b9c6d5fe25db4446a3b2e115e487814a2c4c8274b71e3fe23f50020e61d529cbaab38d2aaaad6c34958c860ac5	\\x5993a537f35a48db61ad87e1459c5106c3724d92eee1da524e9c3060f6f3e70edc44174c151aa45a20a2d41150c6ae1c94248988d0e6ee384876c390a161d075224b0ce77e76dd20923130e52a60c9a4f312d49cbd284a8234981b8a610b4582191d43f47fafa47c2d31fe801a88fd3e05e211a25d76e0319305b31a923bfc13	39	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	3	\\xcb867a061b4513edbe313b8cb4972f405bfb7e5366f599ad4c66cf701c2c75cad24f2dbc2da6b8220cbb1287b5b6f79d2e1c60a869c8dce88f985550b5906b0f	\\x14e44958f7d32d34020b6d63318c8225a4adfff705e4936d4b6aca3b6d5b998ded9894b89ad0e037d300db7124a216ccbee8bf33b8b849d5d358950336677ffb23621c44f67b232755e9b6f2cb6815ff6e99ba368f9a32de989a1ba88950fa45f1ff70bd922aa630a9328eb30c68bf745e5e6178cdcc04e2cc7434d50c8da5cf	\\xbea583936c27ebd0a5d9113f425b014e274eecdd3036d3a39cdab80b558c4e4a705147550f2f6cb2275dd1d38f007f8a9cd1b5b51eb51e34087e62195e413d1a	\\x1ee811dd0a1c86b300ebd545b800d6d2a53d928fbc8782ce5bcb816de937eb1a111a3d721e2b6281f92ae7a07c1ee11d509daa44ead13c838a0d5a75c10c7e18baa66a536704a79ec4d368ae4f1cb2de59d94fefb614655ea8c9fc140fd4c8c3d9d49023ac6ae6c81474866b78ef4b002412fceeac2dccfaf0ca3aa4ea06b73e	40	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	4	\\x77f822b7087ea79046b812f758f9345f30ed7bf4c78169883e254a5ea41d4204171b8109bbe164e1d977006cf6100a5608e9e42e73ec8ae4d67e924a10d41606	\\x2f101ee691857ef411bb920efd934645b99401a95fc1fb5276d86138c1456686a2b6f14e0aeedc38de6afcc5aeb4f7a290bb6f58d8454d728225e9dbcb8095e422be24e4db3fe660d1e948f19b333b97acdd5f88919b9e5008fd4c9174c4d09af68f0523a0aa9f4cfd68dced6a093e8d56fa25d4aee7bf5de721b9ad7101c679	\\x2655237ac1b0338b3ef98d6936caa21784c0e9a5cea9f538acb0d08c015a068023e15012035a20612eb8110bd2c4a06299f6d38dbe62e814f9d5c9dfbd3f70bd	\\x03c793c0923c41ab2ef3040df83e60199c5e4f95a1f8b682b0d87853ef439d7a1ed2a6b77bb361b9d7eb9ca2fe2d50acbae71f6af59e37cc2d47266d32e8c418ca1bc3c6ea3068c04e95dda6fa9ba0cc8fbf9e068a9bfb68cd9b3050a2051378fcbc0665f20999cb6b47b603f8fe859336e1f3132636326acc0c9feed66cb872	41	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	5	\\x2046e3b96eff2d78f5c21fb8fc9310d0e6fc667e95dee71b415eb385f63572be1045da8d7bfad65a568a8feb52a2a700a877dded90bf198477ceb7d3b085ef07	\\x6431b30cf7ede16b5e51c1e6377675e7b129d00e99927eaed3203beff28c6666cf67c2c16c71bdfb3d663b8ca5dfe552ec956de0d02f03a7f34796c19470d5576d7d2ffccc33cc2a860367a12296ee8e84c68347035dc0ffaf298ca7d20331f074b013902f24945f455a3068af5acce9ae36b8e6ab6be5c5b5f2c4dfaceda5fb	\\xc81ee3a4c06ddc4fad67bb5c2455b04e393784907538a435a21d2221ec514695cd961fef40740d6a532a86d1a0d9b0423d8cb5f118b1c4c3a93a94e52c943fe0	\\x4c72e9aa6fef8a832af2ed6b7d09902f76ce3f06bc5795ae2962879dfea64c2e38ab4d7702c107ef2ed523dabe846d366c6408aa572f793277715411d6967985eff333ed9e866003ed7678d450b215ecf5191d8f64814390f27a2cd5cc1416dfe3a0992f230b084e3f8feeef8e045d3019c91d3f7619f766c024568af277e474	42	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	6	\\x8f67bee99c2dbda9a1f3f04bb172d8fd248c8d7f2831af08a207471539eeee7f4ea53a8df136eb94b8ba60497b04df85963104f37ffe6fde15e70410e559dc01	\\x279fd3ea93d00309e169e21197ed288d523f70fccdbe4752fdbecffc4d12add16d66be3416f0fa92d1bc9a25c8d9226081fc02a05ff326c4a5c3ac4a3fd0f598f48ae6a8c136e51a45aeb30b9f35351036f7402edb495890b9925020e006c93a147e91c99d5b5427e9529e90ca7b7265d5bc8d0145b58b06675ed5b17b8f153b	\\x6d3aa37c0569affe589aea6f3bd97f9b6e86d776ec8cb31be6e64634f9fa835897366b0535e1f327ea0877bd3dbe15f0834be03a564a87a85ec5206e4efe7dfd	\\x1707672af81cc15c1f393c66c9ee573973788d5989c2eb707aab5444824ee99a12197823e7d4ccb63436f6b94a739f0fe119809c1d6cae85d844efdf43fbe3ee2524e44abf9d5d814e8fb6dc4b7ed5ae734e9ef107f643e7383bcd186eec8415fa8b649dc74d9c9a6d6143f0492ba63425a09abfb23448036f52e8adb3c6b1af	43	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	7	\\x21b4976cb43f2ead0218b5ca597f9ea7e6a333324f31c9ce3ffa0c9d65cf3b71b803587fbe32d3e78cdfb2ea8adcec02e106fc69044a084025d573fab8743108	\\x7780e11b75ef2e3b31b08c025afd762f048945faf5c00f91c903db7ebbdb27b99acbae55ab457b84590f96d9d35c6b5ff4d0b7f8346ec6b0ecc6fb0c8a0e8a5b5b5016db098a6805b361b2634c217a8b91fec0f64497929fe3b800b80b28c8f3c5500e0c3737290b6480f55ed26bce1040820334616226e2a25fce4c7ffb634a	\\x22bbcf9497ba5c61ab11ab30bda96947fb27082497f861373bac956754be9e02384a4254b53b2d36cea6ebacc6e718c480c230fed7e626332226df0877dea0fb	\\x4f9e8b8bf74493f2c8411dba111cb23ab46bc542c57d99d8526e7c0ad57608a1725a39d50383306a7fc7b28c593c0c694db3f908ffc9835bcfa3cc099c86fbfa9e50dc47e68c13ac11a4156716a8829890ab24931375e7ea039ab2e421f217dff96e61836d424bc52cdd0f7dac920d64472d081f2ec2acb71596b5cfc6b92752	44	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	8	\\x73e383586c8aec39837f0e15971c28db4c3a287a7498cf338c78ce585c6939f2b3183a24f5cffd907ec169dddf5421086e8fcd4bb3ec5083042480c3f03d8c0e	\\x9616b4812884d065a6ee55654870718813d887d2dd6a400b4dd3853267ea57ad91e58508a19c9cf4c468c1acd88c6bddfb8b2a30d3f5399ae549483f4c83fa64e4df84ed1abd0e95c7277ea6268fdd93b7869d9cf763e94c52635c3aa3cdfa2a1193d6feb5d339b86f8f32119ef519de6561b66f5add10e808f0b7a669ded929	\\xb2fca659b63acae08100741a9a65c22d3975a5b37615a063e821549e8fa06df549b226a47ac22be8355e5fcc897e3d8548a0a8bced685b252117ac58bd9ad619	\\x4f779b884d42a8bcaf4d69e9a0dd0961bda77c1e9a42d0c8fe27fe625b3b9415881aa86a6ff4229ff27ef0d312fabc7539c48b614720000fa791450d77f8e483bfd4a0b20c229c48d6a102732e6904efa68e93c78b8635da852a9263dc2da924b7665ad418923a9fcbc8ab8b8a0b5fe082740a27f145d1d8265f70637bde52d7	45	271
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	9	\\x068cf54da887c128f1b2aadde56ef9319b3e9dfb08994b6bac04330b86f8258491f0c20c6280292bb8e8fc4b743c791fc54da2e16bf03d5d84e2eb33c9c87908	\\x4a585dc26b5b0d58a864bdff6b4852798dae16080a31f47ff9be07a714b84de043752d15fed12ef1468e921da101627c8893e31c43d87961c03e680489ef99ea233626b6f05aff39b76cc0b06f65333c4bc198287ead2b39a7797c46863db67cf93998fcc77d20e1b26c1124310550e356c7aa6922ee5ffacffcc0ee3cb42985	\\x780859f2595535ae9cf420247cc1985d84715fad15d9543d4e4fc37a780d8b66ed631c32ac039e851763cf120e59ec5fefb998762d3df1f1a838f3fe91f9cb03	\\x6a3d296fc1c903b0d16689b143900b47d522588de12c858ce2b0e3d940c3d1b0ee4de98638e557ee252b3b1a6b733e4421ac7c1c2c8ea37948895c33b950fd34b6402ada633fd369dcfbd077958e2e4aaac659abac2454e37fbee8e59df50c53af5681f37de02e4ab3cb89e43702bc627e2da5f137b95a252be8e615bf204b9e	46	8
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	10	\\x57d744428e15f2181e889b82284f619ba72a14601b515bc4a48e69d4821241bef48ff30235ef7223795460928abe7f288683b84da8f432ea8278aecd40f3dd0e	\\x8890cc7becc7e80949e3b837d9972c2ff175f8ccea7d58992abf884c56e4ad11050d7fd2480a5d998db6e8a1202e1c094c9b99700d17cfffdeb07845279710ed527c8d95452c7473078122587d0d9223bb168a6ab278de24846169e0a36f2bfc76cd678db3c56f15a7905b3afabd3c560f5f339e49193cae6c9926acb46dafdd	\\x2d5fa4e0f5a52aab3c52bf181e0445b339cb4b500aa763360df4eb1accbc3c541dfbc52b63953d87745462b291cb7289215b89bbc032f37c3571fe4592969a6f	\\x80a90cf2896a393e8fad43e014988265b0535d711755658939f0d454aa621cd8ad81bc399339e89cd250287afb676c6297416ba839faf843837895cc9325213f7a382bac24ab3c27b33a28f786e92415f04a375a552a1eb8ae40439c964ffd4821f2a0b814b3b9e78cee970a9755cf402e1c3eede6674697b90173fc7bf8872b	47	8
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	11	\\xf016e156983694996d338d00ca71d6b9abef238fe8f34c7025d1803389d138ec552f26120a9a244b1ff814b0a05d13566059e10eb6f8b036d64f5b32a1a4b603	\\x588dfff9b4f8379d1311ddbff40d24f476d9557aa56bf4c3481549f572fc831f9f9714c22fc7bfb7a9d279b238069e58051bf2c155c6b717f82ec527e4696da082db9e1c8631bf0c15d1a217e99cb97ba6042823b3e438ff7569e446cab2759bd38096547ac9fcb341380692f26262b4c33bc4f21df9ef1d8dc69989039501da	\\x5102ff5073d0f11a52597ae4ab55817cabfe1da3f62429bf19327d37141df5e19e14d2c5ce5d04d200efa88e2a19154477ee0d16036a6c84e374a78d7461afa9	\\x5252a13e4e9a401f7e3942e8ff389236c0d1e22a43433c82f3e64a400fbc97c419fac4f59dac832a91f2e567548e229d292380e202df8410b9153987da5e098a7eef6103f57d67455b5ce531d629661a06b354e67113e4b948b5427be1401ee71762797ab2cc73877eea0fab77e3ec905b46f518f63c1c13ee810e318d20de26	48	8
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\x745796519859d1cfbc6f2826956abd05c0cd939e85ee8e55f88feef308078935dba19bbec4e695e4052040801d8f06bbaaf0a7386088cb28f79bbe692ac02360	\\x28b62fb642c5c3fde0ff2e309df5662ab494713b4810062c0a638d3985062d0e	\\x6d397455f3a12d65a2b115d44337ff2a8ab0ab09cb909c0a73f99a1f587d3f5760918cb53de6a7ce2d17075c2a1b53d3e0ab58b99b159662395d9cecd66ffa73	1
\\xa360992f8b16b1e7ebc5a2d0fd3f617f91fec9ab7950de8f44b8515cdc4340eceed7253d0c88960e6622dd2443ae477edd9c65b9ea59116490c3561cf43d52e3	\\x3c97aef2ccce815a4c086e5d5f0a42eb42d1b2e92ce6edc04cad1d415f007102	\\x96f5d793d005963ead6cb6997816c8c80323cb8716ffb408d82b97dd56c706947d27610661ec2e9fe9f9299b9fdc8acad324eba53268909452c06e52f3735597	2
\\x6c04d0402bc08209fb0e29ebe0d739a60d63316e2a78554cc35967e0b2492579c05e6add5b90c4d582022c86998f30e6000abf25aa074caa5ba1a8fcba6f3a3e	\\x1c8bd14b809d1039c9f785312d85f2e4fb7f30b472d7c5772b00fb0d698bbf1d	\\xdafa2e6403e76f5475b4323b272b6e75bb650862617ef92555d985e068cc995fa29d8d04b1c41ba00e9a99ed7ba621a40b2884be5ab1689a040c819ecf44785e	3
\\xa1678c28afe694c3bdc1d36f12b21e34b2ce044d5bcee4adbf9d4cf3b56620959867e5b573fd9de65e0f26d9819682da2952e3d214ad7fc70318b9c5ceee2d59	\\x3bc45e7089a6920e27b9eeefed7dd11ac130593ae90254e1bdba72785635464b	\\x986789c46303ed7174af6684ba5826ff6797b63569d72bc23e59e965a70999abca7c329749406ad8f9b849811c579aafe88fb52df7d941621e9a25c0ef30bb78	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x79dd58a7b5c40595ca8689fd33acc1433f632070f9fd0cd1f29a530e6fe9d1b7	\\xf2a40b09db0e7a8b0152b510316954d38c8fdba642d17f6c8035369ef4266fe9	\\xcf704aa542b714b3fa874cab2b604b6f0a2a41154e47e9f94093d140f1d6ba5e3f053be317eeb52640456bb948ec972c002ecf8a50747a3e4935e904f0bab90a	\\x1508c71a4fff137679afdbd261431352c1188fc837ab1855c718331b98838e8aab43e618faf1f66cae4eaa87e8b670ddde3da1ac8a5d883337fe56c4a7bedae2	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\xe8eee6ad661568842a348a75b23bda46f359ff7ae638fec253637c60823e2be5	payto://x-taler-bank/localhost/testuser-onLU3ara	0	1000000	1612537630000000	1830870431000000	1
\\x3adfdd9a1e34138714d383bfdeccab8c94050ccd1308ef914159aed472071922	payto://x-taler-bank/localhost/testuser-SKC1r0sF	0	1000000	1612537634000000	1830870439000000	2
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
1	2	10	0	payto://x-taler-bank/localhost/testuser-onLU3ara	exchange-account-1	1610118430000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-SKC1r0sF	exchange-account-1	1610118434000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\xcff0c91ebf2c57812659677945cfb4fa181630835c56a533b8f81839b583ba86b2488f9f494d519ee5467121f0d687a86443d3ee2b60bdd06b3f68cd2aacf961	\\x80d6db58a1aeb699ba364a5b1b3076cdab2f09c615c748e821a40b6d6851d7c041f9846463467e9d67c168dd03891d17f282ff7b9d5889ba60f67fb8cb43940ff91d63fa0279c7d9ea5dd1bfe39d467de692d175ade23b49af6dad18112bbd1e2798d2dd51492d0a3ae0d108ae75c18073e154bea2bcdf5f8ed77d7b55200e23	\\xee0252ce2208f856618c811a606f26689735ae5525bdfd70268232e6a95524575cf2ecbe5580e0096dbd99f7c4bd3a01093ab6fa21dc6f39dcc428e3b29f6502	1610118431000000	8	5000000	1	308
2	\\x61dee5c6991ba9253bde3680d3669bc1068ea8c2a0f7c607afb2a2ce992396d059ebacbaa3784db1fab894a10dd9df055a1e65ef820425882047f4efce3a0edc	\\x432a4c1bd20ff38454d6691e795608d9b0c7f9a81f92b2ef6b5468f2bab6134c8f1838c43cad0064ccaa84fa1f54e6561cf29ce24a40412c94420dd0963ce65924c5023c052a9fb2cce9b66828da99e4882b63d551b4bae9e5f101f5f9398dcf3fe90f3b5dc9ef8fbd7408e54fb28ac048232ed7a3c9866f37541a618ef6399c	\\x9322d457feeefaaa1198882f1695a732608bdf8d664f525cb8aedc479b88d469ae0ddfc85bef1c73b5838daa33d1e4449e6d10533c4e9ed35cb3c0b833212700	1610118431000000	1	2000000	1	187
3	\\xab25a5a8d39a6531fd7f9ef6cb4ab5be3a6dc3711d8532df12b54b2532cc24ae348fc4d3ca207c607f2a02498582f422d6ead8fdcaf102bde15679f8eb2eea94	\\x6346a7bff5636232107e82346c1dd2df35dbf876dfcd8da5dee43a317d2cc2bbc7fbb36366c9bc67eb2f408a8d09656e03b4e12c9a01bc45f26b7f7b8fe8f273d7f6057582bbd755e2fa6519716ab6e5794c2565456357a84b0da749f06ea75002ec2e69e15a4c0f77a41dee234e595249368ad74c0009a50a8138ae8ad82658	\\xc433017fdbd25a4433ee2bb5e1f14c2b6b32ef1d6373417e8aef92b213048c0ab6c8d8deaf9ccc21e3817902278fc23ac25bf275452a984558196c2dd35e3501	1610118431000000	0	11000000	1	271
4	\\xbf1dfd0fddbe4088bf718e7e168ca731ee363cefe15bd2f0defd3ef0f3d70d5ef91835ba7d7d25a150191ba2ef83248173be92c5eb79210019b767611ef35b93	\\x598cdc55e4c209fda66ea2641e24f35cac1d06b35326a080cdc5bc86f10655b7faece10071ec76413f9eec35cbaba03d68654b77da731075c7f231235a872cd2db2146a5b83522e83f4d23e971eb882c2ead46a0f59a8944817e008fa3feb76253dff6cf1b6f8a891af18a2be051490c05ea340c7e998adefb3ce1c9774de302	\\xc9fdc28415e2b9727799ddca353fca13feb693a85481f855e694a0f71d4c8328e506a2d9e2647444d48c18ff1edb85b44809ab6bc978d43bad9bc29fa4afc20c	1610118431000000	0	11000000	1	271
5	\\x3be8248b16cada168d9f8ca66da60a3fcc97c385b3fb8fa0cb8607468f20579dd4e54d81ba1fb8b2fb7464de8a2f6eb892422c47803a2a9c55851af5641ff12d	\\x1bdde8b5491033aca95c9e40531fb4868186c5f5f7d8c865df64c8f1b7a90607d75ab5169cf5b64e1d01d07178c416fa81f96d82131886834ce72f0a0e14398ebbb49531595ca5ba9651766bef6360f799d042780466681fd9afbb0504a7aa57fdd643231215efdb92e02a6a50027002060f53ac4f5b27643825e55f4662b049	\\x61b6b8f3d5062a93423f958789f6691aad0de88fa817ff27044b87464a0ac04732fed535936627cdf1aa1536e4500d5ef4f322c6462f02fd31508fda14b88209	1610118431000000	0	11000000	1	271
6	\\xdd95f6585a5907876d2bc7e29e26fd5faa10fed51566cb94cff6ed73bd14e536a6229a80483d56559ba7b59f03a7bc0ebe1e18e7504181b9bb52c1fa86ba34d2	\\x01ef5153aefc987d2ab3895fc225aef637ad898bffa56778115323bb853311e62835ac4bff3933a339a39a117be78377bf9ba0dccdec7d98cc83c2fe37b44d6142850421ed18b5501ba587b9a110150f95cf3a6fda8fe1dc06b0bb8df699c03c1865a52824234dc68e7337b8400d36cd666835d2a7d681dbb16a8f89fdf6522c	\\x78907c32454c369e37913672a8811f0fcd25396289160ab455541afe91e388f31f43e5e2c1ff54181af8643bac1d01757b68a97f613719d60b3242cf391e160e	1610118431000000	0	11000000	1	271
7	\\x315feed6bc5e63c2e74384eca949dc48d58fcf2275fd9a1cb5edafbf593aa96f2216ecb92db1fe35011dc5ba6db1cd91c07dc04985566daef71d7937448c54d9	\\x2477f09a383a56597d35215f23afcf174b82461a1911058ad43efc17f3efff93f69f30e34dbc121fd1b18f86ff8481c65155e200d13888417425b34e7ad2e1187d1d4a408263bd0418142dbcb72dfb0db613992d90bb6d277e3437e89da1300f9ef41831cd8475cdfbda8d9a40ffa3c0dac0c4259e50847329c7049246263350	\\x0fc5d1555efac6a5c76d9f221632fb8bb54c243db1532b68964d810871f04346b61fded35519af9e1353d4206f8a54443691fd63481df7a6fa6503586ee5f306	1610118431000000	0	11000000	1	271
8	\\xa896869096632dd699c6ba07979c37abf23850383e8ffff981560882f58269fd6931dccb8a7b413994a54630cdfb113f0b8a1984b06ad2437a57f45d481cdf84	\\x56886c3567020b6d4350f483673ad72814f80250d8e8ea9f3d928f957c1a4203d59ba926d49d39c45a4a20d8576cc3d9bad4b9ed384213391b54c8be65d8e39fa68440387b7e3ab388b40bdf25072d8f9ee55dfe03d8c0f5f57ef57e693723a4ec855efa9d35c76f587594228f6e9d6e2158707f2c2792aee076fbe158b72117	\\x852923551f7c86728b8f70ee8cc78fc2fcdac21bdfa388bdfef789e325a95e37d92d5f3ef96f5d2cce90fbecb744251955ee20ca18b4a5b4c4bd6d93a1a69309	1610118431000000	0	11000000	1	271
9	\\xb46ecaea7e950f13c665e1a1e847b83e59a131cbe4eb863bd958a7e923b7be85058e07cf2360167be2c65258434fe95e2c5f5249fe48e7cc4b34304205c4de74	\\x1a14d48f141b8ae1b2018bb189a4a7d6790c2d0e1c442c62817a64168235327254445b059cc660961e18528162cb2ab424431030346d784aea33454e59e21a8247a63066dabd339990bba936aabea341822c43c9ab3c8ab2dfda0fd6df2635984ef64d5aa97fc09d19310b22767dae2b18bed909afbbdd2002d575b8cd7fffdd	\\x14ae0e46af8361ea06a45c6fe234d7b743f0ef5763d9d67411a906952cb6c73732af020c9325f09728a9eb70d3ddb0b141694107f9da4ab83d8008bcad95320f	1610118431000000	0	11000000	1	271
10	\\xbeb9b1fc579922655e8188077a0efc0a762fd1dff7d8736591e7103ae7b63d8108870bd8b5f67dc8e812e417f99c40b38b105347da3c2824768b144c6a785e13	\\x4cde49d88e38571c54b9a2e88a8e10a649ecc1ac3c8aec0414ef20992d94af8785db42321529dbe3946876146e374200e59c7c3ecb5cc41b65127d08aa1360a6c203d6c94e8f55c8f45976f8d7757b85b2fd88f25957c3a2c95ea82f8ea4b7ad21f4e623d9949f3ee7a18879b2cb46e964e0b6343cb91365d140ba5d92033e4f	\\x08189f4647a46925180a3273206299400c882ab0c5046897733a24526531d80f1f45c28e01aa581d0ee77551cd19699a27cbf311be0c2970a12981d76331ff09	1610118431000000	0	11000000	1	271
11	\\xdcc7341efdb9c1c50fd65810b1668ddd334166ffa5de1beedf00ee135223ce860511a4b936df529a03d8691cd05b866334f4f41f680962091b5f38d2763a9e41	\\x3417b4164795bb1d035c1a5ffad2c55803d6061d7c14b2c3e2d33a79caace42c51f1908d35ab63ded16740bfb315670a4ba6ba3991d0ae6500d7774b3955841f38d35548e608062cc4487752ab94536b3c2326a73be750e970d7d841bdac0790fbfaeeb99caccff44ea3df256e815ed4cd4121601cb5b5d468ce4820b606f3ea	\\xf55b11d9aa0ead039d7dff01814d37fb6ceb780b26cfdb922b9796e3184aa7fdfed85bd56195482173bdb43477fd4ed0a5ab6d5f27ccee1a15b57496b8e43a06	1610118431000000	0	2000000	1	8
12	\\x51fd4e4d4a12a65a84f8aa91d34ae3d8c9b95245c4f1a3c2cd8922a2cf74daf4dfc5cb50e3e8ff30a56e018fd93af2b3ba8af639ff958eb41301faafeb17c23f	\\x122ba4ef90e1015795921e3ae06aee0b1c8c8b78d527030946f9477838eb1e0ad2a36af3bd60068008903a6429354ccdc442db50ae139a8e9cde8e00eeb994229be64c4bad8f97cf1b26c0c9a07fc946f1c7b0cae70d10ff80b7ee3216e21a5f4d7642da3bbf504bbf352e439654ccf1dba08fcc37f6964e00509b86d0e0b614	\\x4b48fbbed2547870043048f7d577f10ab477b427821baf957b481fd3654d9273e69aa6b35302ec185d49e08dbed44aa46d94cddb8cfb9c1d5b7c9b59c846c505	1610118431000000	0	2000000	1	8
13	\\xf953bca8f3f3d1ffe68bd4b8675d1b5e82d3d2b6326d7ad9aa79e02444720117bfb449d294d5e7905c52a63f2f16ccc89fe83dda81f782c6a8d36a04a754b047	\\x450c11b555cac70042c4954c995444f145a4081b0c732b1efcc98d02eef9bbb1ca4eab3f5dc68356ae15a72cec91c3d6a0bf5d6a5c6430a0a0c75b70f76eaa69eece7bd8c59a318b232c3e257e8bc6369be91205796e0d428569fa31c3864d752456514b92599f52670f4a053b5e6b6b2b74637f4019fb4a11353cda2ccb80a1	\\x51f062da1a8bc854af091535f7622ff31bb20e0a5de8d3a82fab6cb4d3711165ff6b60e8e9b88756dccb53b56f0533fddb9ca72a399b28ee6fdfacdb76ea730e	1610118438000000	10	1000000	2	417
14	\\x3d3af71dac0bba9abdc78673ff9a730e9293965614f593b35510dbd92306863bc048a2afa052e2bd736884eab7ffa99a34f774aa6e88f7f74f11677d7bb9d8f2	\\x8345c2e1afdcbfddba5a5cb441429970b18de6dbaf6e26cefe21e4f1bcb004852a21b24da58ef319ecc186c3e9a46f49b7ba9d4d1281cddf1bd92623542cf815c0a4d9fa5d01f5b5554f9b2e91b4b112b084287e8a913b67181777994463a6ddbf85a534460150142cd1bed3b00c65f3ff3c32cc261f783656f675ba8a51979e	\\x08b8ffab0d1844ad695b4be7e46759e37c2c69bec485aebd8f4dfb2d559fa5fb1d00e599b69defd2c0d86668dea4cf273c63c447610c9dbfcdbbecb8a2635201	1610118438000000	5	1000000	2	79
15	\\xb42ace4d5308e1c391742db880cb83d283749f906abf83201d5439a5c4643c042dfb40be9f163e9eec98da978b13aa491f55228266f0689d68574c78cc6258d6	\\x5a73d31d1c878177119a3c63fcbf5a8a71522cd326ab7d95a9297f6fd47f84851d59586bf2b525e2589a598519597bb541135f4799a930a445426bab97054cecefb4df345a34c83f217d20d3dfc4e3201ed72c9967fcbfd1244a67018f02f34bb62cccf35e88a10913c2e785041062cba08dbcaac2ffc6501428cf5094af9f1d	\\x78e787b31e508a91579a89ed60306e71c4f87aa7ef20556a455ba6b993f31df4b213e2fae5b53dcb964f9bdc4658104527841f8def6cf2cfa1239f8bb86c1e0c	1610118438000000	2	3000000	2	307
16	\\xc757cee21a1db1e45a1995b65a8a7622c22fb3769d1dfd171dc6721fcabf808beff9a75272bbc5d5d4d00d678efd190ad5a56e18cfca9473e8c8312ee259b035	\\x0954625da54ea5c7cac9ca7ecb9c61e26724f6a5c240ce4b2ea5a31c5e85160b470d008e69c7111f1845b69a55d3b49dd2e9227466e78abb83db8e7487e4f542e750c3b4e7f283ccbc5fac4a56e1f4e6556aacfdcbce2b4261254bbcaa55fae5026baecd43a148d1185d8711954dc80b8f74c860a5df06ddb5f7f72b19dee326	\\x8dd8daa3f498724dd6a5203b8e04f676a277cfb9fb57a982c2bf4b68da73d7ca28ec361f3c646d445dc57f16419decf46c80d18493acca573f4d977da46c5d0f	1610118438000000	0	11000000	2	271
17	\\xf3bc0052f152d67d5c095c9d5e9853cd54959177f0f5d45f5ace9bac09eb20b275017e3237e32f0257cd4a163dba328b2d40cce3a95453c28a0d25ae2118ad5c	\\x6df65744d35216588da2a30300e9405c9f16006c41c46abff39a39ec633dfb8b955d15121830bf6e83d680677945e3edeff274feb0848561b7fc6bd3fa3436d5d1a357377b84ebfd5deaba1f33a32cc1a6c984dec32a62f0efd9c2f3e8bc39f10a2792c040bd90748378317bd3dca001d2cff45d19f141410e3b33391bcde90e	\\xbdb424544439052420dcec41ff301390fc5d636157167fc821003acba4f16b23d9e495b3fa55420b5a65aef63d286ebed69a9a2e6167cd63c42d3034a448d503	1610118439000000	0	11000000	2	271
18	\\x893c2ace1ef383225477e5225b70791e5b4aec71dbe1c71e1fa6fd7c4013c85ba0cb7ea218189323b81d6d17a507a0d1c145308f834828b035851970f43219d1	\\x8c43caac693975b9e4a3aa30fb84b8d6368d5d184a392aaab40a555a2087003b621dcc18fb28f95067f3fe07e4c5fb2f913fefb73a8935e75089eeeb78843ae6e47387292c2e87cd3fbf91fc44f6efb186335cf80f16942236fb3d053acc21440b71fbbe1b48a768c0387938c7b729b3278d03734e460ffba1189c98455e6f5c	\\xc1015c515f6d634024b4101e2d81902098ce819e9274137c9364208b79edb8894b1ad6fa1def398fe1aa5289dca8d1b2904bb7c7dd63ba0a3a84d74e2687040e	1610118439000000	0	11000000	2	271
19	\\x59f65745b2c61dfa83e3ee4ae50e48c540345f195948d57a418903a8edc849150437ef35782a085002482bdde1b8086a09495d3a410b07965419670562901c46	\\x8fd4405fab649c8476b568d2f5f52677e45ff056365980efa78a7d2b0556eb28814d68f4e7d7b427666177b715f2cea857b2643674bb9da000c1ad6986e2a73ad8f11909bafe62fbb9925f479c8d8803ef8e353b62c885aedcb52bb6385815397ade140ee57c6257110f32807144be5c5e86dbe9e71515ae4e462d84cb0a5c87	\\xa2cce236326dfe8669b4364f92321a41382c05f98cb2054c88da36c18c397dc758e49ba2b0e7ffe1d522edeba25315a82df3943a1d6d160f50818cad81573f06	1610118439000000	0	11000000	2	271
20	\\x1ca33d03c66ccab41bfd40f0b1a7061d93746754c426f6916ff8debd279928d5470786f8d23b08202b154b01465529924924ee478e6c330541a8f64cf34936a0	\\x8e5caf829a5e1fd31805455ca1614b0cb81daae2fcaa637497c5efb3e0269032a7ca1b550292b2ca4bf84b915032356ee4cab2ac79025def3685a91ad32dfcc9dc59b23268aa061e93675ab8052b9ce99326ae57c1e8cbc7668591f2557a93e1a2a3603b65dab63a0b7cf45c009d9c4065fc3313adf1a8a6cddc534c2d3d6215	\\x83b435a6aedd17c735d8a80395c88aa2167d02899f5bd4c670c3257a42d2d8ef2c0cede897876ee592629af8aa4b3ef6f9295816e458a0cadca23fc760a3a106	1610118439000000	0	11000000	2	271
21	\\xb26ae2172e6a70de0e529ceec2c0690f5a7dd4606958fcbc0a09150e532d1061d82cdcf6e3837437542fd86afb63b4a6739aa244882c26154982df12b94a8e5c	\\x61c9f783e3065b81b005fa39c747b30771de9da39c0564757e194501cb12cbe51fbac9a3d736634a8e5afe87b3e8dd2a8f24db05c6d66b3bbf6a687b25111cc00147d643e73f2eb57b4045093d138c27840b1d42101a3bc7e3b060df032e7806123f7fd24294251135daa1e63086026916012a2728646854404da879ebe6bc89	\\x2d3a0f49098f8aed92e07baef93c3bcfb66221a544d0615dd4a10ac90b71ae9a71375661ac8ec0ff8f41e1f30f3f27427d8d8f65e087af6b1a32321636636605	1610118439000000	0	11000000	2	271
22	\\x8c96b2699af13c41470dc360bc3656b0e018332760b1d60044ef72648beafcdae15b1e6f9fcea0d18a59c0d47334d0fb001dc7b7692baf51b2cfa59682720b18	\\x8ac266ee3a82a77fa59ce309d27795a8cb0db99fae7b189dd6bb66e5cf0e4db8dc3c084138fff35a2406edc602f2f3d12143d7dbd116149934776267d11e44d94ce6b08a0dab259f6c0b976005200f66852ea1436c6631cc01c5ba8bc2969d609bf3d1c957f5e789cbd283556facd476c39dec9f812ce20623107cd579b153b3	\\x86abc80d7369b6899f7b026fd29875e3288895cdcf9612bf619eb055de22d00e6997adceba04b8ab7869b2757500543be3b036d3d9c18aac388f71a696321807	1610118439000000	0	11000000	2	271
23	\\x398de86efb611c21426b83a26fe3a5bd8bee74d16b3f98caead6200bc67418eaca1a7936e7b7ffb545a4f7726a4683e09a5e30f5ddc9b287612dd15002f92839	\\x4ec94a5223ec33b6175a1366b6f93b5a307453cc717e2e6848556e5dcbadfb67bfe2851f295c1b4c5640ae42e3712c3e92703d9114f20bfdcfce118b8526b7b4d00334bc8c203daff6bd08c98ff2c4cd0a7c0028506188afaa6bc3dddb1b22707f38619522a9ea54101c9a97e5796bcfffaaf496e61f3e560109def819e6dc50	\\xec5df3bd6f331980cc19815bba48cd8b4ee4c6dc80e5a7d7332003b55f296dd74cdcfd495b85938ce3eae25cf95e068806f67ac6400b7913858fdf6dea5ec305	1610118439000000	0	11000000	2	271
24	\\x792acfd5fb556d7071a02a60aa36e5690a3bf8625eafa1fdc9cb06887d60d60408d78c44ac1c1330c1337e8288c2403a239617ca68ec0ba08d31cd01385fb55b	\\x21b2581513de9bb7ab1e2321b32a4400dec93578544a9559f37d9199414c3bc81f1ad5b84a45fd16a7c204412e1bf649b22a0e23b93c2cde8605d5dc80aa3feb09837f614dd6cfa272c37a5c66621881fe1f1f9fff9b300096a49119d42f33211575b4e39dda56ad4bc70a70ba94852efc96bdcd06ceb87f2656a5b0abdf87b1	\\x63af37ca157d182a3820f9f69f0c7c684fdeeed830fc37c5a5a8c5b9ec54de37250666b0f08304854ce6fec3fc001b66555d785db8562119a3dd36ea1ea6cc0a	1610118439000000	0	2000000	2	8
26	\\x56410c3ab1851c676b5aa470fae27fce4e4eb80adaa60c2dee2b5635cef27439d386c97a8ac3011207bf11b4160009344c0753e9230eee28b25113a7fb1dc3a3	\\x77f332efaf403a62ca22b7d99c11602dc009a04fd707b7a9fdf27ddb9aef530b3f09aac1ce5a07772fb5e6a40525225769dc7d1dbaf5fa2ef49a3d83ad06b883b2b63b5338d03e3522d2fe2f0f17ceab2590fe3308ce607f4302318e033eadabdfa3ae86a45e28ab4bc442e2e69c3505459bc6ed55a3620c49c99e3e0a514ee0	\\xcd03a4b01dd58e1e7188c50bcf0aa8894f9bd0acc47a9a10790de944beb93882db60dce9cac12d294c15e58be72ae8a59023b7132f7008b4ae952737140a6002	1610118439000000	0	2000000	2	8
25	\\xb4bc5193301b8796facea4c82c42ff32126e0505198c817486e8872a8aa11f048db920680cbea9b29555e06e6705096ac7c41c8dd4a86d3519ba60ad4e0c97c8	\\x728f9e839b5a036b6a3b7378e30c081a22caebf00abebd0c8f38e2433879e20ec2570b941e080d55045d4c9aa7cf15e8c6e05329ce81a84392aa1c1d404f700215509255117a31fb311c36afa8ff357db84db88b44aa87a5949a690506cedd0587c8995527a8e88ec87cceedd4ec2912936beab9d8d1da0a8dc272b59e12ac91	\\x71e38d573dce91b405df2d7a4f56fee1cb922a3738581d374649edd34375e22ad3ad18ce6f93a19efb9e7b99313c2d3e42f0436086d0aad8c9cc0630d621af06	1610118439000000	0	2000000	2	8
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
payto://x-taler-bank/localhost/Exchange	\\xfc188e039d5670c54d8fabe5ccf004b6b1cd40178fdd79640f05dd22d86b1171cec8befa3cdbaec6836fec825aa7fb4edb5f7a9961205c3b3c8885fdcbc5bc03	t	1610118414000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xd8e8df6d88b84d2dfda274d6f76d178b7d68d7c3b11de80d34726562fd4f1a4d99cd07a25b0fe62da467aaac7e5c816c225389d7d0412d9a3b3f7da3173f6b09	1
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
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_pub);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_pub_fkey FOREIGN KEY (auditor_pub) REFERENCES public.auditors(auditor_pub) ON DELETE CASCADE;


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

