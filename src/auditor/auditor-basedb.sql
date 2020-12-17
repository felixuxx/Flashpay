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
    auditor_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
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
-- Name: COLUMN auditor_denom_sigs.denom_pub_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.denom_pub_hash IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


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

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


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
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
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
-- Name: signkey_revocations signkey_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations ALTER COLUMN signkey_revocations_serial_id SET DEFAULT nextval('public.signkey_revocations_signkey_revocations_serial_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2020-12-17 12:24:49.259788+01	grothoff	{}	{}
exchange-0002	2020-12-17 12:24:49.368236+01	grothoff	{}	{}
auditor-0001	2020-12-17 12:24:49.467824+01	grothoff	{}	{}
merchant-0001	2020-12-17 12:24:49.604897+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-17 12:24:59.850134+01	f	a940c914-804d-4aac-b128-cf35c7243b8e	11	1
2	TESTKUDOS:10	RRT61TPYM7VQA1CM1WDFGCXJD0CTDVX3ZFENS087W4H4C2VTCP90	2020-12-17 12:25:01.720984+01	f	08008c9e-c6cf-4bc4-a702-c080d70ac870	2	11
3	TESTKUDOS:100	Joining bonus	2020-12-17 12:25:07.722769+01	f	28e112fc-c4fd-4de5-b7d0-a368f81d755c	12	1
4	TESTKUDOS:18	NY8JQX8XXVKBV6BWQ4RY82FV0EHSE72K6E3PFBDQ6BVJW2141600	2020-12-17 12:25:08.483936+01	f	44738520-927c-49ee-86fb-4c99f72c400d	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
101469e3-74b9-4a4f-b7e4-32813f7c6dff	TESTKUDOS:10	t	t	f	RRT61TPYM7VQA1CM1WDFGCXJD0CTDVX3ZFENS087W4H4C2VTCP90	2	11
be90ee09-6c85-45bc-81cc-911f6b448c69	TESTKUDOS:18	t	t	f	NY8JQX8XXVKBV6BWQ4RY82FV0EHSE72K6E3PFBDQ6BVJW2141600	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_pub, denom_pub_hash, auditor_sig) FROM stdin;
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8dd87293e8eace6275e94a099101730076057205db2e10ec6cb93f71dfd46096454a90d7685ec1c0205fdef75049c38d0f922c0fbec26b32efe38fb24c43e51e	\\x6895a4517fdbea1cf664393f0fd737242f24aa5da8e2a2ab1d39c53badabcde1edf1a83441ac3ab51516f5981ff2aa91772374bd6cb19cb0bf5c2021709fbf09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8f337d25d1742798559c9354454dd63de0d1a2a1bfb00a443bc858df8e574dc83352915cc013142890cccc1424db340782a9553de65b5ad921532ac00e8e09e7	\\xeba0b688714b2c2e4e4224b0b461c70b6fd60c3e3bcfafa7d4bb00d7a3c1d3a6c320125f5569d6b71e052e5d76fdffab3a89a46b6066212e7d906a78de983905
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x306dab646003543b65eba2616873ec3aa9c2bb111a1374eb3ee4cb44ee9450b8d2d1ec421741a971ff6ddcde566b90f04087773505bc05c53e182466a585b82a	\\xb1cafb2d3afe13780b76f5a0a7926d0ac3630c59119f2b7869f03ccc0f88dd78217e63e5a64b475dec549bff9199afb7de6445869814d22f422631c2297c0a07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\xa14c5acd341e9a7df7772c63c3099a3626b40d1510879fec12a082075d24d1ba5bc3acb74629131f6bcaa0ba6a0b1aabb32ecb3fbb4c7faed97fbc3f30aa7204
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x12da20e3d09cbcb21cafc61fbe48352365d33ea8e2824027c1a975923405a799d9ecab3ac4ceee62d18dfa6271f87bc79f9abd68b26615a4e33b7659b7bbf2f5	\\x933beacae726895599ab25daeeeb05386393ec0daaa97d2a09e7255de6faf3b85f23d5daef9108b95677c4dac8e1404de463e9f1dea994076c06ce1a95811c01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7a13dd59cb0db7f8badf1031ac56d037328e08b2fa3fe2c84a576b2da724655ebf83dda9426123320e2e02ecf349399531f5822dbb6e910fff332001ddcaee7a	\\x0c86ba45ff90b7ebb7ddacd1503fc220b395342d7ccf10d4a6d93a49edc178e56a1efb8c4d2499b5994e45249ab2b54ead85fe018f305ebcaf71c360c6ef740c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x55695195b8f915699c36878da604ad2ec1eb4504d56677406d3463b32dd32f7848c810c159a0f90b3e4fce685afcf8f5e2586dea3ab7b47ee88f4835d772a335	\\x064af632059d59566f80b8d3a636d57fec70355eecf2a20b7ecb8a3d8e8141ccdfc447ee07303ac42b53ffc8eb043f8350548efc25b56cd2a05fff1624c4040d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3d08260c07c3b9303b5fb847db1ed224ce3655d15c6784bbbb4d97f84704940b29aeeefff2ba525032775d83aea3f17452bd2ff5d9541a7d46afb1e0a0620070	\\x562b8ee41184d105b0813740bc427f02e03b5d53ade84474ce4d1a65335dd48db930df6587df9247d6e6ddcb1dcd348ef116c8fa79b45d9672aaeef022bcd90f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3a4995a368c92be5be6b77554770e2c07ae1c10c01c53fce603ebbd7e730ccfc9aaabb08516b6b03e1a2c20847f8c58f496fc9ee9e5ffd538979e69fdfc3efa9	\\x0e754f3b628efd524a23bff4377d109d2c7ce02d6ed9e90350331f84b149cf5a02dd9192561368e31b8f47074f8072ff0d3ac3aa283888f0a88df519b6d73504
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd8c25c0452b5a52440d037128b9a616bcd7e330ec261718c711ac439d34c117f24e47ac27eea790811e54ca793de169411d65d48de65847e5902da03e0a5bd89	\\xbeea270e44e24238a2b44b97a4e640163aa4ce3dc74229d9254f69b9f0614da61d9721bc77fb97f2bc919d76e29de1618e91618f637a529ac1d635cf5ad8ba08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd62e61dd80912c9b21aa7dba6d288ef52ddcb2f85f73f6e5757ee863dd224b394a999a71fe7325a04f205f2eb77ae646a1510a992e0c17e5dac5778c2b3fe13a	\\xb5e4d00a3b9b29833236846d0fdf1669d19f636bdacc18fd73f5e8f02d2e351daee1598bac1f919f1b5620afa2dd944dcda243802b4339cb7a246c2f02061801
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf87ea9d9a84861875a29ed07ea0ecf687c9fb50cfb4eba61c482b77c790a0adc74e1c3c047d16e5c10e533abc56979fa51988cae39abb246bb06c7f3900c1749	\\x02f310823d6a17a370da4adca843c8d8a7a2601d1179a8755b83dd990c14b96bcd4ab58bcaff2f59e7a526557b4b77629632f4c2b242cae311c77dcb2b379c00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x01a98a1b44820eef2ec96b908f626e32a0fc52d40d384a43a0f83d93507e443b11a2b0c444271999e041cf36789a753260bccf8c607a77d478729c8cfb1e801f	\\x7eb64a7070e9faa4f2e9b0ca2d603702e856b025156ae542efcd22537a5583f57bab804f59d38ef9583c97aea402879827d736cf1d53007f8ce176e548f1ba06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x294d4f6026ab4b5ac39a192b2e04743556bfaa2aefc8cbe20dfa7bba0e7b878814cb3009ee5ede3524cb4cfc1d8f7e52ff8d794483137d95e2251f2ef56cee11	\\xe3b1d4ed4a779efe9c949b588c2c3b2ab16a05ca31dd2ab5050f3ed85e5cf21e95c76ae296555657e0b86a05fdfd951d6ac9e990e32bd40026169993b6bae402
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x70ddd37ebb7cd71fc30b1c8d9770ff87407cdfdb61b8a76bbd91870415aaad6084f9ff2cb12ef8c262d36816768221f9545baa87fb3c38a8e8f89ee05cb531ff	\\xfd7db4ef1b138fccfd2f48a6d8c7966b82b775348ea386e6f076b7ad32118fa4ce6ed5f2680676d5919b6408950f1627dd4b5e3f89e440c41deb3041d0765f01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe5a706ec8a069e15a0c1c062e67c0b45ceebc9fbecc66e9c87c93e50cd72ee3c9f2610d142835b16c9d117b9d07fff158cbf498e0444cafa497cbb08a9642877	\\x2318f8a1d4834f8e2f95a53d460166c4f2316e3b72f1bf95b7c90b399785c0690a8b1edfefa2111a584cd68596ef511f2cfea29ef1ce72b1f2a25423dc9a2705
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x281ed1e02d31491014e7d4f7d8817f21c56f4f8a5c71f9ca6c57615adb5acbbf01caabe85b6fb88a2c284845fb2e4bfc41b416a496287ac6ac6080fbfe849e77	\\xf92b6824c18ea34a183186912d66e532a3663ab202e6662662dcabc6983c96b42e1bb2542c22756090973b14e10a271536c5d40679edfa8346a0d08328175b03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8fa19eaeb42f2fb86f0b17746a7b4bf20b82091a75c177fa124f132c5d80fa90422f824fd073e9abe1eaa88b92aa4b4ee40bed9d1cf67b2a6696f87c586c2748	\\xffdd2052b29270e8e7ed66b655cd05be86fe44e0c1a03c4f143d39c2390e9c402c4d4ecc05136aba20188a3201c489bff488c0f23ca95ed1cd66f2ca637a0604
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf5e0176566d08f9b701541d0b5ceff308548b388ace64f6065211eccb1d25caf4666d86a3eb7a2b1b06c04e5f8af18f6fe1063247d74504a717de3f70720d808	\\xf7ff1ce0ddd1e47a29e60db01ee4e4a5346039e43f5d7b4edfc373cd88f7af182b6a97f8e04e068a79641e015e0d35c35cbb71ce1a4f1b864dbad749dd2b210f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb5737c3d1b7e74a92e3d8b280f6b73f30dceffb242474b12f4ff7ace301fdce5471ce4fe08f9a564e694409cd34f993be5626299ff727475a02f2ddacb773403	\\x9b7e23aff4cbf7bc29016dc1e24256dd6e9511babd8dd4555b1739d4e75c12c70960c9b636c240841e683a8f37ad4832ed85cddac3abc7321bb7a74ff837420a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf79134b678ce3dadc556d4a670fa7a51be3241ef35cabfed96a6fd858af36b921b5e62c807148ef85c81e24ad7bb0463bfaa59dbdc54033e9ab46dc0ec0f1a70	\\x259c68b5072dbd329f48d6d412e48cb14b2b398a356a9fc7477500b28ac1130286538d660a5a7c5bd22b1fddf3c0a6034a4d69bc3b99ae0ea0e514a56cdf5c03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd429ddf539346c70f6459548df5d2d69036171b5e0a9cfae11091b29eaee8dcbcd89b1c534eb57b283960f85d298cd704716e4c4b866324c2e536a19f046e84d	\\x84ed2ecbf4bf9f9cc67835e76754465430f4486ccbacde48d5851f49ea3ae6aaaae1cb1dae769bf3b2d810a0b3b704c6bd9825ade4fe643c1ff0f9b6b9753a0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfd8214abe8c08c4b8c701ecd12adaee417fbc7a1c6a240cc94a1649ee2f1c12cd00ad63ebaa73a9d1dc81b799c1d50583814b302688b12fddaa6f3beae637ef8	\\x0f5edeae5e10515009abb16356ce2808d583c85ec478122038a7ed04bea41f216d6003e093159cf2ea58f6b9d1b1166058538ce69c0298961827c3481de91b0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe88eb2bb869b87eb81dcbbf99d1e42ee7727215148ef1fcc859ca43f2f42b3551fc25faf2179a98b8801fbc4fa7171367a6df060d868535d02fc7a51265c9a54	\\x8346b22035dbee3f4c0f593b439fc9b0dd55ad465cde67757096eba1c41844b0cab45d5d22d21361bc59e4c875f363f71248e8a9b8b1bf45973957c922abb305
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe34dc9700705d84bf85c8077a1b72ca852db648d5b5bf649f0823bece663d47093db6bb8c173695290f59eae64fd7bdaac3921973a4ea42b5643a548a03c4bb5	\\xe130f588ff05cf18cd97f8dbd130fb571e8a201253ad48c345abe83e5bcbbc79673a7442bf2cdd83b68d0c2543a32740bfa305b36dad7a9705c7dbd9700fab08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x020839f05b28d18929c53099902f9704836a3d3ff09a4caee62b1478cd4af868d5f517b3dde4d55343fe31b57a6780853abc2b03345a0e97b3c0f5cc28d1ca0c	\\xbb02443c6d5f3ae011213cc1f834e040fc64a0b775444b1f737fec1a97b3f7f95277a45ffb895c0fcba9289f6e0c46a029e31eb306dcda398005b3022ebe6c08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x830664e3de56976c3f8538a645635bc9b664c57d8bef573be7525f229f95ccd933d54437a728ef27c355b8c6b319cc916264dab55fc697bbd03cbce7034423cb	\\x9c35ebc4639060f3ce6ae5fcf754ccdc360138db7a5f6b61be6f980dbbebe989248e8b67219cb42bf1dddabbbe96a1af106dd0adb3879659c60bf058f2819a01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x320e6d908094d7acbf538c26983490f1fdb442c6ed75ee99e40de1c0b0986b085f68563c34039aa9d5f1dd2905e1fa1ecb897b3ce7ec587bc713d4273f9458a5	\\xfb5b0b42479a9b6f2058b0127c1ecb4e78957638432fe172e1b4edfd2a1253b9742b3649d3fb4bfb440b2df13c98152d377b9a8ed9bf04b469e0319c396b7a0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd38679763feffd035365eed23222de8c8536c7239a94f797c35eb01cb12e8fd00305a1c20ab0716ee80b8ed46c0ca2ab96c2ed1e3375a9e0f22ba1400e213054	\\xc0c85cefacbcf3b9b7eb3f9250ae51dbfe291dca9a4a0ef506df7f24869bd32a4d3fb4f4decc9352da0c4ace2697b406a9499a5b754a8c428ac8a6e18f2fe500
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x092306d2573553fb98c4e8fe1723a8e81065f8ef46b175a2f71eb632c8c0f1cbe29c9ce65e58539ec9b32c36f12287ebb1e2fc5230184faf08ae9c7201f2b742	\\xd23d65266825ae3f372e082ca199f504e9dac6a32a8af704b5dcab9deacb541a6d655ca9bebc5a47b7ceb5ac1b99fb7d9e74523222e68eb84bec3d2e85514a01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x83accabb4cea70f771f83c3db7fef99e2e093a404aa2902d700342b15c621c4a3dfc7f65a7f849be2df5d859aa4f7ecb40239a1466f2ced515d8b7215b59e4bc	\\xf20cbc873070bbd8187940dc437d82b65cbb3a5438807d581d0ff01ccd704894a7b2d760966f28b7e8ba3eb27a2b3dd61f1bf73639e92156d5cd05351b0f4805
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x78cb5efab5d22453175c2ce0c3682c1754df57168dadf4ad522b401e9d551b308689c139c21b75a2ba37040f9bfede97bc9ea7b001690d366c305f827e7b60f5	\\x68a2c0640d16d3a71eb3f1e179ba3af6fb4fd7b2708b5d60b4e0e3277fc0d05c1c98cbe19871443d52ffb2f4ea46d39bc4f80424e1c849e083dc43711678b80d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x86374e8ab9ef317bda31093e5132e96cef6a63611bef2b69d51c381071ed0fd18121c9223f46949bdb789cc38811f8c500625083b363558e8e3df2ba7613087d	\\xf40b733657a9f2a942493e5ff1bf8c3ef50c47ac85f050770465c36a31d6d8bf9bc8287d0c0a7e8f3fb2effb07602de0d5f1508f0750b7888cc479fc090d7709
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x162f9b3a08c27c7b7f4e4e5cd70a082e1798e9e2bfa82802c02de9aa854e03b54d51fdedc1e3250d32eaeea1b560b52565f2808ea659c9d082906215d85d1ee1	\\xf8bfc070085f98fa5e2940bc4cccc039e5f238495de8972c9e90e5e9b5b7d347c08f810206786e3a79b5d730f5f0544b2f6eb10e68d7d6d560e2c3d188c4cb09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5cc9581173b08f83b2d1349cb4f4915184937585fc39c981878a3baed7c93add0ed380e2a079fd07343633fd36c5dbbf92d7f3c65f489d27aa475fadb446a1e3	\\x5c8c0ef84ad9d29c89e41cd44d39108f0e52bfb5b3b5db924fb39fc52ed1e37dca99cdae48bd952ad3d0ba25ffb9dd90c97fca4a16cd4100dbabaa263cdc1e09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0a33a9d80e001ca119611ae305a18b58149378fa9f28f64ed216b40835b04823cfb0f54e8e8e918ab2babdc7eedc2c9015c8c7ed1e922cb5b54b069e2c337787	\\xdb4cec83f2d8d3ececb23bdae711b3382c905ae4729a4dd243b71c8db40d057c33bc9298348473c03f0aad053460a68e4b4fe1feed0d6bd7968b08de04e54a00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa1bf45b28a795c0518dde8e6321dcc60852f2b888210e6f9d82e927b7c76de67ee7d81a1011322a2189f86084e894522fbf26bd93e48753cd65d86ea585f7650	\\xeae48f1f4cf83caba6b224eef317e77f50ddb446fa3e4028ecfa497b39b91a8f4ba1aeb79f48f945a8a1800b4520d53ed2646d6886fbe245d20079009743910e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x53572c461b85ef83d826e4694791d81951765a39a84b1dcad729c52b71482d24b219ebc91419871791c459da5b786c980178b91b57a607e2baf84424ef5d2a67	\\x5af4c327009360f40e794a6574739f9cff4f651468994d9f67f778d3ffc9701f52cd2f52b8a30a8b580e6aa4c4d20f37056e8d77810825b6d34e3dd3d558b30b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcd0cca1c89b5ef7239154c33de47f223671642bc490e16db2cd445fc5e9452c6a6769127ec68b7bc8a3e51c742a5cbe84d85f43a31441756a301c578665960a5	\\x3b28b4e0591a4354d8fd56ab43d6ff9c2e3e7a2b4093fd5c7c4095c79697ff2e06f7ae4f8a34d5e2b6ff6bb58a649fc193c73e8a16ea52a2dfa8f9cdae3dcb01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc0a3134294b074e8cf652a49eb15458731c513e7977c9f07a33b22f08ccab9b9872df7be1341106d59f26242b19e56de01011f849979568542cbf2346cb972ee	\\x2890262ba35c8d21d42f422188a8de4a51f63ddf035eb77e4ab172051fbee3f0c903696fda1b9fdc8fa5a041fb11ce8d11429960ea82367d82db9ded157e1e01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa8e78226391ffafeb4a8a4c61a5dd51543ecbe564fbd2d46226749acc82c8b1fbfc7423a4063bbf86a589e7950846a89d763222a3aaa5c4621d01e2fb67de12e	\\xfb242d8668ceeb89173cf97c4bb0d18ed4aa1ff95e5bd1e24031b975025ad1ea9eb311182489c5f7ebcc6275d6238aa3cc5dad390a849a72b45c3a9f6a7efc01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf7880ba50d13432a695f9f6160707b94df260a161baeca8c6f7c1127f33bf857fc453990ec14bac168f51786018a00f691f40f4eb7a9bebfe82a75462cf96f3a	\\x7c9b2fc61e43ad12392885bf7679e87df3d709ac1b44dfaaf3b148b0755d5c22595704f16ad2bfee224c0c368f754c1557cdbb3bfb2d61a69afe11127a47e305
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x28749285c1935987f17ff0a3fab6261a09a37154ee4e1d0c10c5913ac4f2332f736aa0ff243f23bce9256cab74d64cb5cad61c1434c52437b73a6abdc792734a	\\x5c7ed72cbb16a35a59ad91f49c9e7f4e6464fc3fdc318333aed0f6304e898b4aa66b287c55a1a7aee54abc6b2bbe8be72bc31a59f3762dad6f7d56ba9ef2d400
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x28ddeaaa767f4ee5ecafa7f7e9130c9877fe5192171d0383e1e9b305832cf8842e5a0bd968d200610274518657faca70b6fb6b38941038bab509818c7c896c11	\\x3245850bb3ed4e33deaacc26f4d24b19e5a241203716443a9a7cf3c0262e9534dad7306da07c071518b7085691d807d014688bb589c866134c1b4e07d9263c09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6011ee56121267a0cd2334a8e973718013b00a0ac14123e600632bbd8fdc73ed4827406a062e5c7b384174f99e1ce39ff74ec9473dd5591d0e92cf007585c431	\\xcd5f6b7e20138a263b48136e6412328eaf491fc6148518c9e0ae7376d5ab588da59cfef60292332b075915e8dcdad94d1dfa5ee193c378343fd1d7ba263a4508
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfafb0e1896d6867593d4f8bf78c0093d2597c7463d8091783afe5bd4470d21e6b111322666dcddb922d2b01d8e5cf84329c9f646d72b5aa1e209eb97a074f0c7	\\xfb4791d4a9b0a180ee8bb057edd79104778c8a68815a7460843f527e7ea4009b75360f52362864f06e6bfa6444d725e53a01e058193b98dddd7eaca9bc9b9c09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd72b735f65c2c59537bb9a05a49d16eb1338516c1794ce87fc466ac2bcc0a5112b5ade7b267f675861cddd4dcfaa4f6aaaf5407e6e57536a3dfccc19ddf3b887	\\x12b183fad935c48711f17c0f9d7321c8743be8c232badc944737e9a78a5eb675864b84b80e25bad28667d8ef2945d5601c6f676cd9e4258ca5631f37e2658e0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x15e0ad982e2d73b161c99e019be3b62cff84b2afe8b197b6f2cdfaae97e991575c3d3f2bc65589b3275465c33fbae428b92fdfaa0996143b50b60641023865db	\\x6bec62c42a2558c422334f6ea255d3c86d959d8831e012dc7d37065d67f78b1f2ae71d7da067aefc4a6db0d5746fc96f405a969f6c6076efd6b774d690535c06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x963db68e2b66899beead0bf4684c9eb901fe67531e31ef98b7b71f2a1060ee82d55c89c88fd2cb1ac7aa3e5e80668983008d9d65771b308b0b5cb2457b20ade5	\\xb4ce00f4c6f56b3a9f2eba281575eadd60fe9a7154f8b5be50156b5f955da992ce7f0a88374a4a819503262b55e63e247c6489cf3eb67cb17f4ddf9d998f3601
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3a8be77efee027ed6b5715ee6818562d9c64b7c3858fe80b60f55d88ef239025915bc7dd461a3617366dcd0c2e9ea43903286512f3e838d8f70b0c741ef34056	\\x00434292f9ba1659a0abdd10695f9032fe7bce2de298db26c01f0e0e4f2f105e0a91c12fc9adc2c58f566c56d3e8d6fd49d2eba871e90c8e9d760c8fe727b500
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xba8a12f98f6edb218b49f1577fe9a410e24471fbdda9008334f4de831ace8128c6baad6416eef600759ed07e8bb9f3153aadc4952d69318d156b8b846df29c2c	\\x7454c962d3049a45ccc7e28f5a343845cf6875442ad84bd6056b8d6d267d9a5c26493d9a60c227a85efc4a1466001bd0988533dd0ebed6b741f216a817671f03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0f37be1eb1830c084039d13aa017e81805bb5875106c1c98603ef5b314968969cf4489c8a6a00f51686a4cd1831ec3113619221d3ac7c3be49b4a1638e7f34b7	\\xb764c2272732a033035d451776505c6aca8b66f2770ee1950b4971327682f6915b510808f7dc968260bdeeb22802dfe4ffe53df841230195b7348162b705fe05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xacb471ea890e35814b607e3b47684b9f8b06b45b09f1535dcc45bf4709c61cbccb81dc040ec4caab0fd26d73b1ffbbc58ae2b21fee8dc94546ad9947beb8400a	\\x455b1a4f7b131ac1cab65497336af39b6dd24bb659ec8c692b68c2114042661d429dd4da88602eb4a215e0504925396652d3d28c3be17d7a8fe5a824ceee7201
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3686ad9701574194e4142ada8c0a24bd975f5d5a307eae244e716a101b425c15398ec1a2e0ed4b6d3a79af0d9a2cbc9d7ac4ef6db328a863f30b0510708b911f	\\xab68221b3af37703ad4b313688639703bae792a6b34d1d2a30bf4b715a4af3fe922ab5b99e4296aaddd4dd8b03fab8aca3321387241432787c6788ccd82bd003
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa7761202e74774e119ec830c302789042d9413622b8a2d1e1a3bfadb943fa8f9141787e21df23d2eeadc49a7e0f66df5e58ed2d28ee526cc9b61c23874cf762d	\\xf263912249bfb1670201a0623f2c330c0fc1d6621501f44ea6f372d1fea5f864018b1e4a0be56547c2471c3565d4f9f9314b6ba44e5cb725ab3b831c12a97d03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbfeca0518c2d0c91c7f26870b7e5c27536420e4f8d1dfb29a186253f493219d6a6510bb470f458f0aedcd40480e485ef0f7bef7f2b100f09dd7e33bf54dda41e	\\xcd9918d9ced3d8897ae99e4e2659a3b1e57639736136df7851ecb1494a9950e1d3c5cec09aba23de183f147f903e4dca63afc7ec1b8419a4670c110235af4e0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe567e2a7920c75b3bd387b88e5a6bf6d8c04b085fa2164a5fb4acc92d9dfbd6817b09b42f5f0bdd374f9c2c1a5ab1da4475f855680c1f5f652cbb59609951609	\\xacc457c64cb0e8f2ef53e163f69c2f5bed129980facf257267e6f324e823797fadd02a6a76a0500fc1e803cc3a15a4f5f9cd7eb7a8bb987218d6150f3dc90a05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x48f29fe534bdaa9ff662820d2fe2fa9b417c5d214dbfdcb94b3807b1177a7ea639529174290d9d6d71dcf3e1722b4841676cfb9bb9d58ae6a816a24bbe2ff180	\\x55f3f52f2ba6aecf51a30bf0912cb5278132bbc3bd661f5dcda9000b6a46e7249e3fdc7315e7709d669079ae541462e92e97b42df17fa29532bf096e8684620d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x03efd666321e621d522d5a9456ee8a08d5c10e61d857e390329a7b5d2ac203f383228f335d21e6842e081d6c6c6f516f586a8e319296d165cb09aeb54100ab3b	\\x58eaaf68c19c3586aa4a6efc06bb0de3ba39226d5b35cfd4f45e74d39784b408c9b8db561e9752b32d9491bfa326b626ab2907f6d9292586004ad56e0a45a100
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xba53ad68079797374ac906274e5e78ba316151c24ed5c09e48cbbd6030f07c00f1220a63c8d926943044fb4d8c7578d14fa48cf50dcbc42124a98e71bf60c693	\\x76fd055dc3df5927ab637b88b7866cc982343f20a88f7408e593c05398fa31f38cbe19fff099db175a42de99d2a3f2096e23dfd223d7a4d242f15b7a33f6b709
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x14e4d0de211b03aa9195ae7f2d1d1d35644e908ada3a2147d38c08fd470b74b8a1cfa3a167684414303782d58ae1d6f8cd0f0598512e898415d077d3b4c4dc51	\\x8460b47b8bece291ab064cf3a78517e9ddb9dc5f6546c0c603e8547195247faf28b48c360d86abb3f4967facc1ee08caa10e94cdd0b42062da51e2eab351c80d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb2e675a4a755da30104b357ac71c863dd36d64298013d1d6500d70a43105048924163bbaf1ff8866e0922a44bf9e6e9b565b99d7887afcd3345eb1663ca783ff	\\x16fb4db652d02f7def07b763c8cdef2688f0dc326e26a1f96f882f53b7ebbb6bb7038277a98626ec26a38413c24b926213d6a2505f9738b972f610327409860c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x275229887ff1ba997965eb3469bb46a05c7cc111b992f988495c5d3ad985321fcf7bc4367aea295a448284c6ea2a39e7b572245898e4cc2ffd29047a6a84fc41	\\x947a5af4d4fd3fc3354d6428e555dc10c7ce76c40997dcfbdd8d5a42ad8fb8f9568cc9648fb0ea9e59a4960318bb9eb213cba7244e6379a9bfccbc8c8ef23304
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc905689ccd3ed8d5cdbaf57b40acb60dcd0dba66d898559bc9cf83255b8b1f79df94f08bd68c3dd16e33be4f1f4afdcfc72a37ec1b7d8dc1fe60f285eae1d062	\\x92f667ed069d18b4d68d92155c5b243b78f7924edb080740cd9dff7a5578e3f0e2d8883963db70ed16bff91f12e44238facc38785176ee18500660f669214a0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xeafd1d71b7c852653b06df46cadb505c4b111a7956439f317c5bc4cb125b7e81e44a546336f8283fcb96237c5013bf204763378553a98b94a4e2255375e81eb4	\\xfc5b0ca2b1ff2d169de68f762a446cf11703e97ee59df5e9a4fa0889167095497d27571be8bb7db09d8d42d744766f07bcbacfca17f74780bfd3c04e4db03401
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb551ccfb3fba26c773a1db7f707e99b88112289407fdb0c7646c6dfd4ea195c52fb97590576ca30bab6cdd83fe63c378ea7af83aed9c1c60630539e0c04bd95a	\\x64d5c14edc0b43a976644b548e3957c8448951bfcc83a4af009eaae6fb99b18c2a47dc635ee2325c4df346ec837de03dbdee81f258bd6bb7efdc01df58191e0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1904739fa21838d24b809ea216211a90db9291677e037fd51cb0814e0532b5a3d64d796de6f4132877132f732bf7ddbe703e822333a7dff64b3f8117e8e6af3b	\\xde5189b331ea3aac1eb95eddb68f0d89dec7d00bdb0600ca4365c2f0f95501afb0b4e00e39393ec7f0d4941cb966f2028eaa0d8bd81d9712b3f25de2e42f9604
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8176e9c0564aaf8fb11b1245c3cdd1c6c3cda4e44b96cb1d91e815dcee5abec29647d0121950cd1438ac2ab4e7c483b519cbcf87c72af622f17872fe79a06cae	\\xadcf19a2b599157af5c444dba93ef77df4a416b032a9627c05ef1db7a4d30a2f54bcfe8b258397633da89510227c33310d6232f906aa20cf9427963b14868804
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xdeff814c153dae3a9dfd3530e0014825a6c57d3e5ead7f337f7f24e57b3bd02834760f1fa468bd50a5a2072a749376f843aa990a7215f23520f787d6512bbafb	\\xc55138251ea9d6c488e9364c00af9d0adfe20c249927133617466909a486829b143d69180d390cbcf2796b4ca2dbf63bf093b7e053de40fe5a3801cca6466104
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb7864b4ea1c087eae351699d5e6b31ce169483a146f4eb039f12622f97e026086e05f71ebecc11780f7790a308d1baa3da0536221e8fcb550eb71ab0f5f37769	\\x21ecd2e8f54fb7d2b6209e8a5b711747340788b571d299beee65353504feead2ff752f85626a699f1fe131a7bd0b90f814dd5a86991e258cc0cb439e543b1501
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x80df7d0565fda7d5cacef25286f5674f50ea777b81e5a5477875e8ed1dbc974c1cdce226456824d8cef886140d29602f37aa787e0c0ba932d57566159546ca01	\\x98dfa222c40c34852aeeca160809efe290321008e17ab26e40124bd73506442b1ac441f2cb9b452885bbd0ff456e06a914bcf4a678cebacdac684924e8f14b00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4f1f08b18d4b9f7656ef7b5f21f85ce3c41985dde4242bbd586bd561ba65bd559581c13afd88706feb86133495a7e4c8e28cbf06c5f5bc735d277d39efacc35b	\\x9f2cb930ff764f5ff233224bae3827d072cd4898633bd5e8017681b9c150bc750f9fb6f105f8cbfb421885dfaa4d28069131b68ed24f48b278f0c18de4c63201
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x55f9d8cdb345604aa33ef812c805bbcd892fdc1aed3ad09697f34ad19e6c45f474f46e103a33308a426e566cd11c16109052cbb52682b532d3d928875005ebac	\\x025f512b0a75c390bfb4897a3f43b31d76eb45e3b1003d16464ccca84269d87b69780572df84effe9c92ce069a940add63524a6e0d5aa90b83455de1119f1403
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbfd79c9b2ab2eb6c276c42a116fc2a2ce9caa36f4444f85ad23b6907b70953d34bc8798f5da77af97ecf3de778a8fdf17237f8be9f2597e119e7edfd2b3381bc	\\x4073a4c2fe54a96149cbfd25ff707b735b2f8a705e18465b387f7cd2449bd8051e60b8480cc6998ebf613e064c26a2237d5d8cb2280a3c92d72e726bfcf66709
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x61fd87dc691dbe0f4cfe40c262b2d83da7f5f21a7d04a3a0a2dfe270d1606e296664dc3567ed1c933a8e58248fcbd514308431a6f9953ebef26d28ad99749a0e	\\xe607d0ba081f736f79cc5e5c7cb4aa38ac9009ef48619c0a417fb5c86c4c79dfc53d97d53a841f2a7790c02fe2d6158661fce7647a2eebd46dbcce43e680ab02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc7da95fd04eaaed0c98a1df6eed527755a98095aa2111a8b4e848b3fe2912ba3ae08b0b7ae6e6de328635d75a3657f4a85e027b5a34fa953e87964e60eebc49b	\\x11480e4138a6720b6f142ea445f95762564cc143a022e0511eecb4f7dcf3f4b892335dfc44791acfa509cb13de90bba2f01511e6d3a81f3a3bccc978f096be0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x85a48b3fa44d8ff6890c019cc2d8ebebce5d4fc43273dee5842eae7345e7df099ef127cd5555d51048b534d54f04ebf13c8e37faa74600d6ad496607ac52de4a	\\x227750225f8bf3f5ca6b02b459b5dc77fff6899da7feb5cc48d6e670f0c143a2b73722104fab8ddb99fdf89c1d1431a930609ece576b6906c2b1d2f53e4f470c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x138efeed6ab5116ba0cbae3488b7ee979d6acfceae9ae3cb3f7da4a45566b9936a05b1c80f73d409a8f541ca9d795dcb91412f7fdc89c7abe7d362a8d2c27754	\\x01b8e8c6ee2c4a2faef02022b7be89b59174228d2b05be17a57ef332b2f2740c657d36c628287002ef1c97d0bab1607c9a6de9179b03634db7bd55f82bc97709
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x72555ca16566d63134f89bc7206f68973fb839596691105ac41bca6e7f1d66946b6bb1be05c049bba73396a9badb01c9293c647136e2c3eabcfb301f968b3d72	\\x58a564e04d1940de96b3d2f42d57f50e03cdd00e52063b350e06a084acfd433e5da351412e628095b6900b39b78b06cb4236acf5ad3f290a136e8aa9f8caae0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8b36700d3833309b5981efb8d9970c9369ded72ad1f5fba61b042913ff9658e0969d890861b58132de1c32ea3e0459ad577b8a8a21a82c59aca0c785befa52f7	\\xffd22ca89cdd49483e0a1eafe2279bd68b682f2348331e81c28a9361ae5109b84a993a542df4029a03ebb7c95913984ee99729262b85f09b436d940bf3949401
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x25d8ca0aab36465727ca5000d053b5eab4a36c4a8562659af53334385bb8831df7363d71767bb658cba00c654d610385b684f784168d7be1002f6942cd2b487b	\\x097df97188c4b60deaaa7f580800e48fcb65dc558477d030c751f2e84aba9a909a0340af6452388d0ed18ba51a47becf2311e9a8f87e44f47cee82e44464760c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0ff889df4e102dc6f27659f4425211ce7ef50a907646e3eed2aeb30611e2de8aac853f7d3bb9b6ec4d63492e0f3e140cc4b7cc1e0c7f6198428909fa26964af4	\\xba8ba96a0a8397a9ccea6cf93ef10e4bfffc00b4eca4cc94f5c8286090a83ba147b0a5112806db39217722c7702884562a2d55683cc075fe58c83d5d088b2b0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x61d65e23c2e7adc2b8f44a4c0573a3f8f653c71380ac2412c9b5e6050506eaea2748ca4a273d883312f4547c0f3a9978baca8e3c8cc46c1f6913575505b324e5	\\x8a23aaa0e7216515e7458f1318d93d0022d7856029d6b3521229e71624510b9e710ed5b8414db5c4fa18584d3d40c63460f544ba493d73910b7c59b55cfa060a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2e695fa0a4cd63f736815f1aeb8f9c367a7011e23dcb7c340a39082e8bd71110280696623c9d3eb38a13a2b20b089bdb646d225f0c63ff7afb9cb920c8a79aee	\\xc621b17d4d12fd96006d786978a36d05a171ff762c3d5995d573b6bf598cea4eb578d049eb52e335bb840cb36eb3cf5a834475d4b606a0f0203a05173523a906
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4edcdc7fd093249f7be12f127808151cb14ecf5db488235135076189d230a2eb27ca3d83f4af16ef4f24aa18df25e0910072e904245c2ef26f3fb3a8d0b8a051	\\x0ca972ad5c3e1cddca460479cbb2b2ea0b059211f2074eee40d2c012c35381f63c001e431084427b904b0bcd073e0584376d2d2769fbc3a231e80c37647bde02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x20c5d8a5b20e2d2b7b44bd23c3fe740c8f8f91177eb04e10018dd4ab440465c30d9d58df423aaac425c5fd2b0182a2fc1758e2722cb16dd03949b1027776a20a	\\xfc142426a92d1e19944a662d1dbadc3f45a66b571b666572eec270bf9665d722769cb9f4c4b718e12f7c9babe07a0dc6f8f470323d74afdf761238073f536308
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb7f6b15e095aacaf54bbd7b5db9562e2fbe0decad605dc5df1c65431be3942adeaa3210e5934b5cdd34bfbf5a2ba3d773aa24a0edb70b5e62b9fdce8a5c37166	\\xb3cc70df0c164a617b6f10c837bb3daa125355b5e7980720591ba2afcdcf1fce142c3923be31ef7a588b1dc4795c99333f26fb4a6a9571c7b0172abf712bf50b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5538058a9604e94b2f32e0af7a0c1cbef6483bfaf82e739a5594721ec694ffc361dd26c1af0f3e70db54cfc7738d1a3029fdf92e403e74af38aea6b81fdcf90d	\\xf29c27a04c295afa4f52e3d58d0fe5bc43461e7c746a65b91ba7ac1fba0a9bfa282269529bfed478cc9292717e455caff32ba8a9e02faddafb3b09669fd7530a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xceaa6376598dd52a83d16733b55dbeab8ef0e66d12e7d5b9fc7c9b5274b514f897f7e81190b1fd87c0b51ece54830a8590e1ba270098791983dcc30f66c457ff	\\xf758b8c532dd9d81291b96525ff5ba968b2b06e8a9ded470864803dcc0c2ff592e79df4db6cdc9a929bda0ff7a8d4e869981fe0ea6e6844478d8bd5d85625e09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x736024538e180b54ea554ff182b5a26224b351211e86dfa019e5acd2b0cfd3f37739ab092e11e292e2accfeddf148120cf06aa595dd0a054bc3bc7d0cc9e58ce	\\xc9efe1c9cc6fd6032550675cd05689850a2a5c92352b1cc1f312ba505ea6e90766c1a433487d69e51e1182d5b48e455a20e4fa433911e7b0a66d6e555b64a003
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6ab8daa2125d18b1ec1c147b89f3284dc36572b7e7adc90f37aa64ffe94b253b26f0767bcbc903a5359db69937fbd4563a75f50cb64b34b2dc2c7fc1f7892f5a	\\x6f20dda3a63fb3362eee17382a9f1933e444da976f997993d1f37b65d31fed6a61b6405597105859851b700391073763c00db88f178f9e8f553df77b6f9e7f09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x929ced0450d67e4b79ac6734ca62f5618d099fb3cb327c9f841c73e40e599d277e677f7a02f8a94cc4195e2859b03c097b2c885697b0cf5045629fe8edd6b543	\\x5b082590ba8c2474bb1fc3957a8180d6c38cea6354a1b48d6503bb938a53a94784910007aad26309cf8e848f70b15c14310d45a627150863715f976c17288e06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6370c636629288842b92a798a96194e2e568955f630c0c9bdb6a1034383994cdec4e78b81deeb6da7d894528ec87a8eee01339b8822559e7bceb9465ff1d1b94	\\xaaf01dac535678169d932d5d5d32a3a0266630465b7f2c5b86249df75ec15d506fc34a6ab50e25252033586a6afdeef0aa3121269a94f94fa133a7abe5687809
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x55229be21d08504e60c844173916333ee751caa095e1c59bd5f167daeaa9138bec7547eb56e7aa0f2278e0da0e9afc8f30dcc1c4df2242a7d615d92e3c2ecfcd	\\x2c5044fda761f4bc795b23330bf14f34ce143e88705ee8cf485097988d2b1db54f2f238b78ca0ea2648a4f30ed3577a2aee146645d8c016117c098388a0b3101
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xdf90d2b24614b0013571b7f1217efef7c9da64a9b03a9cc57e66b225d72c49244f635470f53d0f1fc1eca997829588a129d6488c62a6cc575386a0bece7e9cbc	\\x4fef14ce8a9fe860fd36c26e5b5987267611a960ceaced6095b9ff92adf624eaa041e4350608ba1c08c495ff4607a419b1aa28f7b9a0bcbde8a58eae8f3b3900
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0401f861e6f2b67dca4fc15c5da791cff19781df3d3b347828a85fd60198f84c8780a8d178c37282f991bd121f941900b9af7e3460f293bb124f58915dd8b2cf	\\xf1d91954687c329aa101d7bc7714b484bf492e1c3601db0e116830ed0bb57240f598ec6d8cd442046966953301dc42478a7a579c8605673954c264f5347e5606
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0246b8f715f01e20e548ba93a69b39e949029354c9f17b93b05ba35fc3b799fe3127d45e1907ce4d280ca2be7524296742ce730265c9bef1b394affb89b46706	\\x2ecb69278b1fc8e5b2b09cde9945c04da4654826ae76bf243964c92d10ec2ceeaa44883644ba41971ad3d15950bb13d284ba15396e03f3f1e72426abaa47e909
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf19b1a7aa29f36432bef472cbb7f635c4147b3c3dd49dfd88ebc5c03a9f361ff88867f7f6fa1e4a72ad1e4adfbaf5d8380b2a2f514fecb79b9482bdb443f47c0	\\x1c60bc246990b893ca496a4312a976b34a4ea9d4be76babf846b0c99d35a3ee025698bf6846e4d704efe34cc1b310f59c712901168266e771aa7ab4c6a92ff08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9951f7dbc4c032bb3a348844840eda9411a391800d1998f3dd5c81355f737ebfe28c81ff3deec3adef5b8a14857041f37cc18156e773aa6ebf937c9f3666ebf4	\\x70a75cc0f31bb36a194832e6e554590c919930ccbb1b3d0bf4856e56a094224a1afa8eb000410b69551b367601ae7698ed9da52f09f96453f729a7dd9e015104
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x08cff8c4b9f60d2572d893abd76194dee57759fecee464e9331b72dba3357d15839573133ed09f5b4e53bc46cdb3f59728abd3663780fe826eeff3777f2af936	\\x9b0b9a5220901aec7455728fb5bf2d588689c8362d935b6c2cb38ecd4079f0143c92fbd061175be63a0b3c2738d61e82f093c18f97ae9c4611eec249d0ff0b07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x507abfb69a675cb20ee6d421f0ad46e92198e3695a12c40c499f718613b43f92f1914e4bfdd1d4ea9b2f1884fe44fef835eeca2f07cf29d47f803c26148bbea6	\\x3fb70b2bd912c7d5aa915e990323861ca6b220fa987bb2e31f9396c6057aa5d13955ebe2c337366d91c4dce30cbac9e47e5f19dd43ab8d2513a82926623b5c01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x23a0e06e9bfedc0c5994490d25149ff694cecdcf96e80e04c5475795826e5586fa99a904fdc577c620aae0daa341ff0f1d68a64bfc4e74c6383d1e07457a1448	\\xdd8e94e8ded04fe12f874f164354251484238784deb12a181c9f7131930d60d9672518d4a9199c997a7a5aa1834b4987abd36a7a3d583c0e64486bc22ecb710d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x415544fd619bf6d0732329b2d9f81fce2a2359d2e5ec513adaf1700b0316e0ef510d427d67bdf6a3c2d7d4b6f1f06a9452d8ce81a6b6e4c5725469d9f658f553	\\x03b99a7be01b74fd7d03b2b1574c305f3096da9e983ed37e2a63d4fa28f431ccfb18ceb8c8e7260f552d90955f96490126917b74f9426e8d1f2d77854263980b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x67b0861bc2ffb36039094397f55b43f193d2d73902fc4245af66a34d8d12f5f3a49211fffe78347976b5a0e4384d0f447d5205cd3f15452683885464724e948e	\\xe9f2e3813d27cc6172fc5b23344bdfe655c003b5a69a99097139d0b216ef3355214b370a0f5d71f1608de57bfc27c68e7f8611ce79aff36ec112a5c2d9c6420b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf8773623f8ab5b7c900e59ce1b87b1748a0e8fdc318259b510cf67ccdfc1e097332d72d677e43a94f70fd25d0e2aa8ab02087c0365f245a453273e866c3e4aee	\\xf890f891b04ecf8333f30ad2e9a7254bba690a13cf3dc8f46b8131821247d3211d78caa7fd64f8a9a210f9dc9ad2d5f0e6dc1e2122d1ac0da66f4c3d45f8970d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x05f2029ad1814297837680e4b68e37c01fd6aa1b1e101ba0ae0069122ec1863af40e5eaa0fa144f1b376ce59577f8ba2efc4bd3e5cf8807f378b71c37c302837	\\x897141b00771a61524e3f9b089f9a3281bdbd6261f139ba246930b93bcc056d3ba1636f0b5380a89a151a826d44e650cc98113882dfa3fa4fa43394778ca3e01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf670aa584356d26c3fb9f75adaa967ae0dd29da90198d5945ead80311519f7e11f6b5a03f19c8ccc751c87cfd7e79dd5a72f86500d35531e1dce9417f3d80bd9	\\x9a8159de7f893b2733c56c271e1339336ff49f05e7ffb6ee92099540aaf4c4f1092d8883be4f3fc7fa56169ce6fe039277d6133020bf4b8c899c65282dfe270b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9ddce34a891db500aa9b8dc52eee6bd02ca3b66c8a562fcc4ca5685e1a9caa250b66a17b59e468f562e02f6b2ceacf1a7d9fdcf7447e72e32cb88a55738163d8	\\xd246dd7dd6c31e2a535faf9cf434224d2aa67415d864d1ff37ac17b91c43af33d60dbbf067ecbb84ea09096b1759e56d93f17051b866ffc8b550a409039d1604
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc331c36a8bb2bb75df1d25029cab542ab827a38745ce211bb0a7f522a1518a744b02809f30150c008c60f483e645e176c01d1a804ab6c79d5b171abad6d2471e	\\x7787589a9bc0d419c891eaebfe42315cbe8a94dac049b91df984903b5c327defa7b576aac5cdb3004fa5ca1f761b565f6d01cd21158ed4858d1c22d22f4ad809
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x691d730589f8cd4ba9b6c060aadb8c86204c1927f01a9de42ae67241b6c584388801f60ca32a13a4799624fb96b8b18e3d7ea2e627e1e18f085e69932834e750	\\xa91ba356e4b981b3946f4e9359f1e749f50abe954316fab6432503c67df25b852ea78bfa1754986c329a5d8bae5c151625f6193d43ce917d166d49d5a7f55d0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x068269274aa340aafb540a9c3c3b440a857a3801a57b8ae8f65d166a096258a2da8dbf02c439b7848b1d376fac6eb47f947f44eb700d4cafd1a73e816def4d91	\\x1e3e4f2e5b85bddfddc23213ed30774fed4b4a423a0293b68042077bb7c1bbde16c8798d22b734127632fb6d23f729bfc3ae48540b5da04e4fe484ac8d45910f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x647b8efb9748c2cfcc094bc09c5d5aaca2d05311e77d8b94c2cf492d154ab05ca6d70f09732c6d91d9b020e3c5c228e0e16728145fdc8372a62562633782bb03	\\x1d64cdb7097b4227105cacf8434395448ddc46e264fb93146c23addee211ba4ac07a41612ccd7a16a2e4e1ea39234417213bfe565cf8b4ee3e8e2f18fa3f6a0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcc59e766b6c26350458828e0c80e816b3d57338a8cd45c5c6d76ced48e12219360f9a41d485a76b0763de1592d01ecc52c67726da945d543df58f50ad92c3746	\\x4fec6469e1a2340a316cf60492f3eb4698691745e3bc376a87ecfbf1be2c804377f22c8437a1c5cf5288a62a1f22e65bfee386e51fdbb35f8f77077d31f65e02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1f1f9a24b881f0c56c866251f96d0502fc052bcdc95dfd89feb3068299dd92123578e06ceb2e0ef0909a145bf8bb4ebbed4e2e6feedf7b73b15362cf3bfae462	\\x5107159548b31e972415e3bcb2a9bc7da63d7b43c2cd09a7482e57b289eb29767c901d6dbab5e17450f29ad2fddceb250852fdf3979c2b5b70b558db93b4060c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7ef25aeb990277ca733cc120fbcbc6c8bbc0670c24a7159ad33acdfae328b8517c5ca0b1bc92b1b99e05bf29b519b81149fac984fdd7eb195847a7a667533794	\\x788d9a51a16d699264a1d128a3a7d572d030320fd9579ee773890212ba678ab342a5fe1585a40a6244e01f730f9d0a212c2bf99cc04a61b753b2b701d8d67000
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf3b43daed009d92e3d5943f4b7c2c5d14e98b2fa17ae08a9baa39084a12bf616682bf607a2cd7c5aa0d4d55048ad4b710e8403ae36f0f72a3a6a44d02e39286b	\\x13c19030f992fdb1b3337eeef1a7063e07765d7726e6511b65ee1cb8d7a68aad590ea8b0943c47608c5f5a06012ac4f2fbcb43c87fa6e740306866327dd56009
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4a32b888887b6581c12e21473bdad9bfffb71da6ad714241468145f7d5e51294fbbc7c29e794d7741d7d9c8f1978af1e4b4fc13cb1715b686d57163b8a761ed4	\\x334870432e29b8da080a9d68fc23e20c03f1a84261937b400bd2b9cef28c067c1e0df029078b507a07cc074dbdd9fb16ba96ef2470347cc1232ce52ed749c902
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4566d165a55a4ac4b2038baa6b7d18745558f01f2a95a0aaa4dafad6792c8b4541a5de44412f427287e19e13abea99101c2c02c05d796cb4f3b0beb4ef70e159	\\xc9042a1629f7b428cf30df22f8d581d8d1667e6e6d5a28fd455b4a4a9fca613660ac177ce85120dffe23aff6a7ee674609ec45cdded8a4bdc7ada94bebb20a0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf70c73a360b0a7e5dd7bb5dff5594096680a63aa9e49e83895a93f1ca56fd6d905d3d3fc8fa7acebdf975807576177f792c1b53cd1e19d5b61c1eb72d6b25404	\\xd42333095d3b14b3d816a120fac4ae9009a1047118d3608be8e4e15d66e7be6db986fb907b7c550f5ab1b2603f851c0fd010b204cf49b216cde13b99d98cc606
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xef7a8fea879faae6389c9ab0087263ca98abee137379aa920c264ce2b9d9bf01d1059857b6700e05cf23b1bc785898ac378aa592c054e55e42d596c6ad1ed271	\\x8c9d788c7bf297d04d9a1ab6362234efa909a22e7b48f6d2bee3dbd51b73d92066d03b33416c2e7d240365d2e8ec3f90b33879614e89866f5759f731ab736905
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3d8df1f26f7c91d6d14bdfbbd3ee03eb2955bc40806b298e85cad31236675c8b483524ee1d42fb0b942b5807385846d6bf62b7c979b54e97a1ef6df6d1a442ae	\\xab67cd9a80bd524d59a6ad14ac62ae929e47828b25b2b6a32659cc74a2b06ac6deb8a230c08fcb9fb933e4e0d79274412980a7447b8db9c6d21b16c456e1310f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1b1a424ebe7e55d044a5743d6827ed698a9eab01f934374273711805d94a7d41a2a1ae944a4548ac4c27a0344490a4192cd05c5f88ce6726bdfd5c5fc15a9b62	\\x18595b6274b36970e87195c4a45a0193fa82b1f3f147569b3a12c2941b51e4e4a07274d5494ba982063cd22caed87c7f1d7771591bd4f1b83491ddc2845d2b07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe3d1367936362443bea59f482c9d05274132308d7f8d45052dcd764024202421c95fc285227d53ac4837c273a57f2ee8167a9e9c3f98ce96bfd08f2d81ca9cff	\\x1a18788ca625ad5459eec563354486d17ae8e84292972f26c5889b530e89942e0a16172943697b970b1652df759c25f17a9e568d3c03b3151e6e75f1d83f0b0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xebefda6ea1f853d414122552b5d8930c88d397e054faa009cc4022611839a971c2db83563bdca74d49d621321ff4fcb96e532aa3fb2d9be4e69d1b40d1a8a9b7	\\x5c00ccfda9578e37256a31e5cd946d33cea34411e3e41d884c09224424fc3b69701f1fe3801373b4cac75eef2467b4eda8ee5fe955e1f2f5743cfedef3abd504
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x35aa5f7194da6712689ec6497a1814fbe4736eebc17f5f1747f1616e74dae7a7fa9beb6bccf7c34d4526d4bc3db3b317b3ded94a62a127c359d175321ba78b0f	\\xeab6ed29f695d8a01210ba90d40c59f09cd367853be2cc3a991c70c1fb40ac84c57e94e2505f531a9a8b95b9febc59a1ce7f5bdf5ea030a10ac0d551b6b28401
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4c12b20043e86f2e19bf6acb047420b1fc38d6b4e273b8517717614ed0b220dc6ed17d4e56be92cd2e7d965406f720cd846f73982db30cb6f3d94b29bfccbfc0	\\x5d9c862dd7b7d2b83529ae5d74929300b8fd578603c999e54f7a017fc5a76d80c1331145289a956dd7ebac87a5859e2b630a48c7edafbca6de1bbf8c4562ac0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x141605fa18af242618518c8826f16ec1eadcc0eac9d907cffc71079ac28325e20c5a76951bfa71abcb7cadc61f0cdf4826a30b5e86579fedc2cbbd9e99ae307c	\\x720d9f4d2a0bd271b07da110d9b7b8e60a1ecff278179b2582dc074be8d2b7daf740453f28e35d4f13c985fee8f9e16145f9e899f7c36e4b11dab4c5d0c78c06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe2620513dc45766f3b7e6658a8fc9cad984fd1fb912b352ef224edced3d231cdad7a231373f431af91f280e591a814e9f20e35a3796ae25a536fb1708085171c	\\x23a278e2e867f0d7f5c26b1bf0218e05a845e8030579eec5cce20a9be6adc0b55c39bdb9d2f4856092fea663cd98f344237f7616fe4394bef283ca779cbae708
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x055245baa3a3dfb6bf0f73e55927b2802947bcdcccacfe5f7813fa2a507d50820eac68c8ae8b234a1708e3b2238ba24f720fee3132c261c6c375ea44576267f9	\\x2226e2a1a0e0d11e0e4f032e0366a094cbf8d0b1debae6d0505582180ed2f59857d336092959bdfa4ac1e2087198ebea33c5f5ee1e30814608fff3889f18a108
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2e011951eb136c3e59c639694287ca7dc159b5c125fa015ca9f610cea02830890cc8e6cfd7b46197bde64ebe406684baeebd3b15ac17548f214854696774b934	\\xcc90e57c1c9c81ea11195d1eaa55d592860355fcd87ff8b02fcfcabdb387920227a0965f30978a680f1a1dade77916cba5bec599f80da541e561159610a33600
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc0568122a386ac813982640670d78f4f050c66739f67dc68c4091558238502f3276d691d9b72bad2b5a961fd5f9d50c95aa75b923939223bb33bb73010910dc8	\\x51dfca62fa1eb5f2b452ae1e2553e486f609d0769e83376f9fd9dd0f11a102bdbdc7cce887647b09238375cc418afe74cf9722225fd30cfa3b1f41b3e62b7a08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8d9eb5630343cb79c8a6d1e597bd5a460c38597cc6f25af36760bb88a0528341c1b0ab9be0029df9d836a66485ab907800a970231b59b896ee2675d5fe6b7c6c	\\x64eb7c98d3f2a7896177a51277e7381da66f0fe4db3036693e0f40ae23de5f59a11f91c6688742c03fdfa652bdee691cba2375854baa62b53f9a9bef142dd00d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa094662cc51665334d705a3548030d0770af6b0a21e720947e621273db207f64bb2d788fea339c3a14f222679a8957d3f0da36a96cdfb3929cc21573bf977fdd	\\x21fd4db1159c2b66eeeec5eb8838c6bcb731a35a23199e4eb83b2b2eb06c1a1ade8687980ab8182666618b8960108c0a8e26bee0678c3b4c0bf9a6d0b7fb460d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3014fb627672c8b4a2649d3077b477b2b88d250336a81d69823b6f37ad20c9dececabe59423b59a498ad5c2170388760219b970c229c2b783066352ee4cdc3af	\\xc4c4d573f9fa239a0ae935c6a8805b25a69d82a7c84fdd7c0501bb2bdca27e0936a827e05e16a969b72d45f809a98676eabc373f0b64176d1ef4be785aa78a0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6504a7dd7756faf6754df08c5a8c00ae1608d202d5f2a5fda48bcd7f45dcd661a9973e1ea4901450619b058c891de607eb50f3c24b3479c3692d1e9522da581f	\\x0a0422ffed9bc059ebd235552c6b48623d6377efaad90b24a3d16e263a19a6f9ab1d379222435b814629caa7c61604ef5bba671dd38c5789cac9e001ee6f6a06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8ba9c29d217945f583e9c906a96353f047f500d5b503da74e3ad0e8abdb487795888675263efad35da441e2a4539592abcf73028c71eb73c14c06fc94206e1be	\\xadfa89b594e88a6701eb9e3c2119df91c421f96597aa8bbb2807a5a2ea3cf3187f18ec9aa3d3fd3393015316b059d36567ee1cc3c3e63bd1fbe4790d91ff740a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3f722fac23bb13f969b712012526a6eeb36f0ef8854ec19c55b5bbd0845a37f9df9f7b2de02d914f781465c694c0903ee46ecac2ffdb36b0fd681daffe26b5a9	\\x28a15d3b0dcb787e643961f064cc6edf4b6b6b0dc589c8e1f1e1c05831ac6268915fc26e3634b25b1db5f0ed34cd8df78ab841fd4d96d1d48e9ac14c1764400b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x35e8581484e35928e91b5c01dd0bcfea87535c9acf9ce66b34be8854f37e5edb6a6b15e541ff71d4551c6cbf69b8d42de9145d16c66605ea12c003f04f60a8e3	\\x77ca735eb5ec925673f2f797d68d2e7cb1727d37d834cf5f55dd9501787f4f38274ed23e0229fb4b73ed425d7a305d7619266558958be66b6308524f5937a702
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x83f015a76a88b5bb794fcca87306cf558d2fdd042135ecc885b6e528b9acc2f0a7e58518ff097a9ec5e7c846ff068889e8556f716ff08884e4ebcadf5c1e727d	\\xeaa9e57b4e0357c17b2352782af3d850e796a3a2afa79ab903b39b1012426328b34f3501ea3c23e70b9692bb0865c9e6d45916d78ec995d22c04c16423779302
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1f4fce1b97633d6ed0b7d739f62283ee49eab1acfa1b7f411bcd7d91573a34bc18cf2a2179cb063df30a088fa8700475b9e5ebf593e9e43a89ad1be2272812a4	\\x7939f9bff2284b133ee7956846cac620aee6f5eb606a36e85230b61d883b519a3d5b7f859023ddeedb72ae045336b4552f1da997a00a4ea13446b06f3dbd220e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x292e3f2a66223663f09851c25bbfe8c4f692da827b21baa64daeb37b77472e03d630d7ac2709e15b96ca788e96d8ba0aa1c92e9fd4ca77f345a31b1adb19c78d	\\x3314e5fce05d625a29ffb675f8aaa57908a4820e02331c6cf00b10f28e4342e96f667086802fe9944796bdd898a402a1e7feddc281e2dfe6de00ccacef500b05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc582224bcc58d52b411a568721e9ed63f68284f045a66b6a0271f94f758d3c065376fe1fbd00eb5326d807749466147276776b564dff4fb379c6255e4b3cca50	\\x4f26d4eb1f5fa0cedbad5d0690eee1464da91990b381a4c32e8546955c5e277f37caa7b863d2e07326a13a8950685300bfa6b8e51c90a8f79ee55768e163f20a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x837524c067d269a71989247da9511770af3d597545a940465828d33509a829fa7f93c7fe985dcc934c7a7c2336e7bf3bebb63b687d457b300d6f380b344a3149	\\x6ad2c4374ba2800297906e4d85d263c8c041e5199f9fd939fc2346acfcbda92477ef148bb3fdbbcc2cf6b75e2bb8b029c55f3a6995851242e011e741bea14403
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x17dc4c1defc635fa35d65fdc17f2594ebec0370cc23e671ba6bdb24408a58aa47859ffced730879145d4f057ee9ef3d7df2473aa7a6cf5282214504d6ecef1c2	\\x1795c9e0c1c57e6f20a9f969e362063105d06d5117c8839220f73ae22b05d77f1dff86a40401312e7a7fd2c89216dd8e8b2552e039c16dc50b89107f2e1f4501
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x50068b304d530ab111e5577aa6cf7c7d5cdea28567e13eac62d36402cab1391df0c8fe89250ae7801dcabc0c9ac9f28cd63c30df76a506434c88750a4c09bbb9	\\x67446b800f39ff63a37e3c0fd3b5cf0e9b60565de2b9bdb42ed7c0d8bb96530b4a01ef1492b0fc614150466680b3e90eb5b22500f32b1fe8b89b15be482bb00a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6975ba574c6b1f2a18314e2938d45a6340eddb5742754f8a9dbcd867efc1a97ea2d7cc1ae8be0e59c4c0992a938ae2dd867e3bd937060d82149c089efda8c343	\\xe7135e3aacf5e619acc34bf04b96854313fae86b26ed71e8cdb6e39564cd8264d50291e36987b13673c1b4d5d33f7ee82a29ba1528e25587e763fa0883754508
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x314fde3a7f4f1fe0af9421c20de1d8956338febe68737e6a6f8b745db6aaccf470883d4841492e92779c3053c05cf6ba38db0fbb874c50c07040ca8c3803be69	\\x7bd8b0d5dcdcb82db0947654bb911051afcc808d72151ba8bf7c434cbb6036b7353b4ded7d710c3eb00130b1b1be7ba441d1869a248b4569a6514e4543fb8305
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1421ce34e584f5c2dea672bc8435443086ed8da87ad95e1bc77b359a15469922d94432b840ff4ef109c73b62b386c51c1c19f2d003ef5a04e5a10f55f8fe0810	\\xdec334c910f5965e190fef8b812ec1b9f103d14c78ce79d4a6dad25b81a2a89441bc43600b9b88fffa7379b0ee270d6e61dc758718822e2fb1d4133b34e18503
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x84ec3ab54448135df4150a81074c02a6dd207f31188b0cfdf54cc2c25fb3b37b3e7c49bec83289c52a7ef36e668acfedab2076e44b737d2196fdd3c6834da689	\\x52cc6a63a031b040f515a54c38b83745f209f370e0fec7785bbd68191a130f5d76cf352ec8bbbf1c4d0612b79048148a6bc0a7a63dd35357724ab99d391d490c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2649a49652fc05da1e1f51af62d91e4b4c40c6fb0b0c9a74e75be8b58bab297a92e07b4039d517d1df6363cdfaab82e3ab495c97b422c1deda287d184ac01c18	\\xaf0a3a245881c82cd895a0221cb06f92e72de9d5e0a411e557b8011bfb1069815b509c6551500fd15cf94096b2e779b7919a058dbce675bc27f83b999c773701
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3d9612486bd8aaaec84c99190e19676cd147cf29c88e592dea6b27a7923607f479b5cfe5569aa349e8bfebf61c46b8613f9304c4c64b6906ebcae145dac4067a	\\xc3eac1610a7edc29501c14584546bff1ce859ffa127a4c9771c48e3a494e7df782dc707675a91cf8364c0f45eb349eefbbe55c59cadf292cbc19255210db4807
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb6ca21bf84ddde8e225a9b6b31ee1468e7d55b5dd5ed3e8bd46f6a0b3ef42c97112723d5e4c52bd856fb7d20c2ebc6564083473d51ab785de65acb8cca2a0a57	\\xa5a37824c5efa4573a09a08b149f107c46e4ff52524d17b6b5302701221956619de17272c4d00713d444d45605894b2ca532c1701c3fe7b13110649ef9f82207
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe5908563d736c05b2e0b324079bc6443b4ee0977cb3588b20bbed3b03efcad26080bd64c35cb03ac6396ce4057ec5ecc843953f0c7b04689f3661c6161f17fa9	\\x0d0163a045609f5d1cd08167024b003e2f5ac5b917ae731f44b2e4e37654a25b1fc86defcfc2b4c9932246ef2bfc3de542c011535788787dfd80d1d17603ca02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x71eefacd46a7d936e45d1e60235e6085dad624228d3d5b113394a1e609ba785fd869e2e11570673dcc5f0707c1651752daf22fa365e8966f7ccabedc0305318f	\\xc5a00d1fe2afc41378535e85fd3f9d05bcb640ff221803f13ce21e73e3c1bfac8722ed5a87ffe16b8a006b7a6724b141f257327a280b3f5efda4d6e3dda35903
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xea34142a8c8e411f47565eaaa3684fae7c9f7b4efcbbe95cb975610fdbd15a248cfb6312cd3d31ffc776d6357cd0fa967113677a74bbc3a31be98e9a099588e1	\\x5bb6fd991a0c4970a0f2e19604d5a31a411209d996595a019e1bb4eaa9d59137c658b832afbac12c314f6f7678bb4a3d6a1448f23f55ddf92bac45c60111d509
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xdbb85430f93f58cbd9132cb0f28fe88d9648276b2e11087ccbc93363814b3abc69d1fd10789e8cb26a8304a86fa383fb8dae40e45048c5c0a84db40a69a9cc1c	\\xbd73b4e5d0158e29d31049425b359f285b667a7f7a412c59d9e3e142bf9041a2f9edc77f3dfaa75499d4ab45702e1429df547bf7fd122e4fb83558bf82ce1905
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfbcd1d2a6e5bb4613821595750e4aff01917b83df82e391c36fbb2ff4e0720e71c59f064eb51deef54abce44d96d2e90e42ccd9d9d03bd62463d2b0bd7ddd3f2	\\x9d6bed55c36d251076add91beb01bc18e87619284e58c164ade24cdc43aed357a5b007860c3fe82a8a820dceac1468d258ba5e9c87d6fd333655e8a5478c8405
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2dbfb519ba16030c5642d9970734e89cdcce360be6cf99066ff5fd2955148edaad6ef72ec6fa1dd5ac8d7ce50f2e86bc9f8c3eb138786dafbaa6f08130925088	\\x61b028c4b3547bc53ff29e4b930bfd7a5c79ee5649e007b471cfab320aad5fd9efc507978a6563a0f69699b36c0c0a89f76bfe316878f43cca458ff3515b1e0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb0c3a96404cce6ce6902260c6ba4a80e6b61fdcda3aae1e4f64d6beb7e7b8c15fd18d28ee35ed3969fdf051a92f6df8e8673b237605c2b54211ab07fdd59748b	\\x1ad56656cec423e9d47ab2dfdfc574403e3829219f56985e6cde375bf41f0203270f6bd043cd1388633a9d99dda767afa00062ffd471df8da217c8aaa2651f0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8a2aefefdd10a8e4ae694602318cc0ea72a200b6df9f8989c1b645401a08adae78c0bd4638bcc13ef2679355ce57981c7b425fb6e447145b46975f09044ce132	\\x8a428afb51127135a47f68a47c98d1c1800e531ab13f1aebf8aa4ed3772c2fdea5553c8801da0ee2132618bfdf562470471cd5e966af76169c91736337ebc908
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7bcba76a76d7962b0a5600992b955783c924d16f469a5589af8889db213b51eecd0c693b0d76de7de30bbe2c09135e16e8ba603e7fa9eb02002608eda8c59e15	\\xa869c2d187f8edd6079a3e68faf9c9e0c7c57371ba96ef3a2a6f2ef5702324ef1985e9cc02723a993393e8e685ac19f106dfb167d370c574edf74bd94bfbec05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf3764b68b91def6a70d72cf48a5ef3c6949f53b9fec9174e303f7de0d482024b7bf147c1ffc66fb05185cdd248d4f0f536d17195c9fb7618078d3a87d7cfc431	\\x09be800eb0d34013d352ad551e10434accf66a982609fb9c8fe835a614a760544a2a1e17caea6119798ca6e717ce7de6a016c30c7506272e0c589ce54ae7c104
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x67835523e41a7f22364755ba0aeb09bec50669d9b72760c203dae9032766ab5958f2df62238e8647ef2d9e3334d83cf5cd260fabf44df3183d7df01f871e8ffa	\\x90e1ec05db36e7667d912109f22b53b4f8c63dfc718c6c22ab938844eeb0b90d1cd6a2539e126e0e1bc4104ac3c523c27dc0e4af159b928d77564cfc69ffa50e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd1c10956d1a3f07f0a477e1e0ee7e48e9c992741a416535ff2d47cf49fb0983e079df9deee39bb96902f5dbda67caa7b1d997bc50a62def0379aca4ec18b81a5	\\x5130709b4eb0d74a3376903fee4d073e6cb00af234aed031a373b49bc7c82f83f553930d824804c1aa485e6a6a927853aa8f88d8bfdeee85e0687004efd73803
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x64bd48fb2eb4e95dbcddd34e5ba2ec7582bcf929b9b484f84192a64601dd4c81180d57409891cc96cdfabda37e29b88529f708ab0914556be79c05727f8741bb	\\x078a3554772ec60eeac21b641b563c89e2d859fbad3df1166dbb81a1b52db9be5596acb0927783c09ea97fb344499d25dacb4af9264a10871a8852dabf244603
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6f4102425d2402ad3e496b54aecf0bacbfe4f13e853eb2e4dfdee2807785a13593c64d098ee80b7d31377a8ebb7499f4b749fc7fa13c7a4c67c6427f386706c8	\\x0e156b84101aacfb6d38c15f58a368b33ec3f270342d735f6cf6995dea0753a067b2f83e169ee3b3e49c1f1811565ba6e12e59c769eb42ccf0916da9dd367c05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb37b0efcc6a0f551f551252b83cd6ddb7d84b9e4d31d332ac6a182e70bec2859d07ba983f54466ab3cb6ebcad62b55d952b2ab23ecd95093cb0e2694222fe790	\\x348a17a0f01365b6a4928f8ad1b20a0e515ed9d2c09e60954a26f9f3839979b75b6e2ba2ed5e2459684b87bf5bdad6e8cef16a675a4bf0f3c61436d8b2968207
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2a526010b01bceba38289bc35b9c0cdf0eb586bd1c730b5014a48fdac8ebe2f9f55ffbc9b19dce9a4ac242fa9c9833b27817ea88f67d6c5bc66b055622b1737d	\\xd52ea9973af49ad101d39348d75a0f4904aa349fb0262b98260e26603266e92ba022c641758c7db21ef7bbd135a28b354971608e0522a54bcca813fc62e6ec0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa5fa3f86fc1b80745ab3d7234b80f7094875e4ddb1c8d76c543cc9fa32446e51dd8e1c6357a5d91073fbc76331ee377b72fbf063ed80a3a6cc7c2739e0e0d222	\\x9be706e516cb3b1e87afb9fe94073c13a3b8b087d2fa35f72e12f13fa56c7f9cb58b9b47be787b43a3bc1e69e1165440b253a83b6d6ed82485dc5ec20e585607
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x412a7c1bf544372fb80c8e9188c0cd1c80387c0019b9a66ae8f146d7fd13c5eb35374376401b336c9d266351c4b68f50badd763915fa827b13664fe857e34806	\\xf80828e9ad8e35616b075a7f1032be164b2e97c346b6ebce18235d2475d68d712de66d3ba96272fcbf21049e282d1e620dece93fa765df467409d0ba5374f30a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x922a1c0d0c6ccc46ab2dbb9a0247310e1fef57567fa7179fd38f0ee9f50e0c067e3ef3cedeeff49f8df59205c609d622f6ec1e86800861977c0089c8380afd46	\\x1a149d0a1992b9a9888786a6c428251511905094431ad5a56a330b6946300a30d8aaa98994252b5cc93184e41c9738e5f1561e3a1bc326cbce76e5ab2a23f10e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x41f1b455f0c00d59f8567c28d234044b7fb12b2ba5a26afd7986bc314beee738842389bec8bb507cd484d33a8baf91b8b00b6b1de15261086b99719052650210	\\x37b08dfc876ed2a207eccfdce4fb29048b40f70816fda281f52311a87cd8f1bb9df7bb4040fa9fe9673c512fdcedffe9b8481aab2982fea072de1715c996f709
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4751ff657e7db68c4636ed2c0890f696dc133054333e14827b28b028e457153e1193fd4a26baff1810d92e5ab0b58a5bcdb2f355e1e57e181c53c1bda80867db	\\x450b52c8c45680d31ebaec38484234d950e7daab28f249e70eff8fe21409e6e11df915cd43dc709501f8744679137f401ebcea053b4662c9085930544b4a4507
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfcb12e30dc1c183d970e54f333e5560f765118466163a931d45c135cda804d2f4dad03b89aed3a4c4c2678a8b299d781f24eedaa9c06436c87e983cde35d4513	\\x0b9fbb1acd199a710678263b011fad46311b10b7ec3874d498d9838e97e4f4f6adf83c0c8ae65be46c758719527863ac794a0ac019b1463ab2a5ae826c56dd0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9adee060cf538520c46394dcad073bcd5c5e926b56698ef56dc81dffa8bd0cfd5c607784d6a72de04fb1346ca91cdd00d280faf86413a4b79790cb88041e8f8d	\\xe535cb72e5589fc929ff8a9d4d9c2d6ffbf769c1afe551a46a8e4901fbbc32952f9b76e0926978ae965d2c05c402918a4c986d3809fdb049e6f9815cf5f69a07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8d22091a5ff6f6218f74b2fd5f5e42e1ba3b7d686be5168d9abc345ffa7dbd76d08d31340e2b85b6bbb0f944e4990ef644c955f96d09785a1984fdd8aba49550	\\xcb211681b825560d066127e2d5d8a3d6fd2d4218101d915750fce0f47473abca2c1a4bd9d0cf62bb5f53009ddf3709f2a6c54c6dd934f8146a9f9ef8446d1c00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbc097cc06563131f5491f22dcec00d78efb2017ffc340070cd2b29420d6b56f27cd81b31e78fb2602aa3ff312d0abbf9edf84ca5dc1df0c516bd1ce2d23b4357	\\x3f49c9e9094c94c7d6cae2590dbd38ee52140e9dcd68933b7bca10950a091e2436604250a74dcdb8c4960a20d6c9071cb454ff9d1ff2da801edacd73f7232905
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbcff0c46a3bdd50e7dd8b860ca4e25a668411c0a12f850c2ae2f74c118a0f591ea24f3279ca5edcf0121d5895aadf8d723904894fb578bf9789d0ac91eb4792d	\\x45088fa1e1a49711ac9b3b874c5e40ed6b867d21a2d45c14236c0005ad1dbf3100a1ec3b1bae610726198037cc7c8943cddc60da539743e60079b8a315927f08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x61fd9eb96f56f41fa1d0195c2b065a46e801ef87b0f09c3eeee3c7d9c11ba18f21ff3404efd364c0274537a003e2f1b7f5f28694505f9dca61544345f3c325a1	\\xab745dfe6b9c18a064a830a0c0051d767382151c9c2c99fc44aeaec95997acf1e1f18d88d391ccc1c7f8e5431fd0fa04b6a32c517ed06cb960a2fb71ca65e201
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7470248addc7120d5ed17c34a5452876e61e04f4e4bcf318c9df292215ce93184cac02ad38f982e5c1a1e8880a599c903fd9cb83c2fa15a1c9ca0dded465ecf3	\\x2fba0197c1214e9658165e61f84ebe886de2db289dd9e5a1985afe5c063c5f7307d7148c0d915da037e9796c45a3feb88f27a3f10f45dc7f500e431384898f0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5fd3b40c1f9b12a7c06a1e3ad3afff9a2e0457622bb1a76ada68e03ad4f59ba4ab0f4ac23c97fd774d22f98d16ddebf343d9a5af80f175563a2437a72f6a897e	\\xc1a75097c9e8793a189345117ad1f696b9a104c1fe2c066bb44cfaa211a9baff33521502da2c4187751a2dab79362690337b39e6c156f60739985d32964ea30e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xec0ee2424bc7fe188a40d30676d01649cdea2bdee3f75d7a8ddbeaa6b6254e04ab337c685ed30777b843477de261f87af4995769781e20bfe0b9cd0b759f0017	\\x0e0f4d5f1fe79c6dda33d3aaaf95a9b7a5c362266bd756b6bf8306c16255748533b9186ecd0418d88d8c233cee75dcce2d3f6259cd97d95c16d0761cb52cd307
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3e08ede3e8121306bd4be4a49ef413e53b0a7233bffc7795d4b21a0e38d200db7131de4fd0f67feb93fe55eba3536f48face8685bc3d74af80654b306afb07ca	\\xd646e72b050a73da77c80f0a2825ed1cd4060c3535d551e12e901d2289e7f5f92473f413a8ca4d9ae7f6d6f64a82b956189d012bacaf49115de47d9460d8340a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9856e102bdb2a7f2ce040f018f54a16d54bc18998d50768dc41b52eb5a89bdbe3d9796abd7acd2662277c845db2afcc71315dbd752ba099a50dab64766b8480a	\\x52b18a2490292296f994dfa674cd7530f94e81aee4ea947e72cb1a9028a85790a32c3d76bb26242af4f251dca05dc8ee08cb2090ee8fc9ca408fd625d2da4d00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1077765c6afcabb507aa2424c3ec2f33f4905e452704e18fe0451febfd832acb72c95c5759b76f2401e2d941296f474855886e066ef97378cfc23bd4709162b0	\\x239bd887a72d8a77594a6b3036e8c347df719e2aa13cdc5bd531f703895d363624dc7091655cf4e1333ecab8faeda8638d51268434f9fadc4f3feba1a95fb10b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\xec72be37f7744b332d05d4e6e090032f7f5bd58b9ecafdc004faa9a17fe347ab4c297f247628a9ba1cc47d2903beaea3d84117640653a94095db5f07777c1107
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0fe47e353703b0804f214a85d968dccb1535f4023e525d90ea062a250f14e5b1b1a2b09bce84255bab7889cb0f466e6ff1425b8aaa89537d71a20091a4339f4f	\\xdcdae5363c1116ba704062ce8175b182c564541530df529fd51ad8190b91ebc549857c3cae6477327bab97411c17f3f5b6fe6560334b418cc709d39449cccb0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0f15ec6e3b6ac9180ab67c807aac06e5be67bf9add61e490504d36a79c165e5586c78fa6c360cc0ad1ba0c0b193f76e5c2059a85aba55c0a938f0993b21c5371	\\xade5a11c0ea5e2b4636db8ac3fcf4d4dc3843fe939fee9ad78243e3fa14087bfedf8613a0b055bf480a7d6a03850d80c25e35787f13936872c313347e1fcd008
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfb1de484d0fab1b93bdab4f3ab17a8367b87b4d29c0a1b494f267b8b267ee2199048d147f6b2c6cc502171029479537c904fd5e3b6ba3f7b3641b3ffa4ec5804	\\x3b504235456c3cf50dc5c2524b5c7dca5a38c5eab898117c3ef503b13a564391e930c15df0c222bb990bcc4d536f5cf639bcc96dbcd26a4c1c8a1e019331f904
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfd136ecb9dc655062ac1bc0394d8b943130ff5c73ddd7a9bf7862fc4f79174fe9834de6ced535bef2d2dc56391150368741aee5988b4a28b90798221fa83aa8f	\\xec2e3a34fed0ffb97825f54d169ba827e3a24315ed7c4dfbd5f85e40809fc391bcd940a34b0ed946fe5a3711f719d8ff20d7910b98d5c946857cbad545d8ed01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x15a6c3a27ced735ad465528a3765f0c726c55001e3d3bda590a1bbfa4fea422a69776272e29ba5c53fb9be8787a15966f09611f020f707e41f8ef20bfa28cebd	\\xba68f168963092b8eb8350d3ca4ff28d9571d404abc5e1d5342607106ff5f872ab606e226e47a5f9702ec5b45d53ac22fd5575dce0e4d7f398c6e924b0b82b02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x30e9fc9c0dcd047783e4ef981eeef9a817ba73707cfed5d492131f60bcad05cb1034b16d8bacd71ac66d55b138add8743d08f8a2937eb19993ff442f3fbbe4e6	\\x54ce720bf097947e8b503b17e65ac41eebacd8237695e6f4ef13101deee2c831390947c29851041d504c1865b4d4c648d79bdd8a18136f3b1d9fa3519f898c08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8beea228c4e0ee0b8acfa0d8661906abfd2bb4b905a4c6b2c337869a9b7960fc5617225a4aa0e10f94380824e49d256c6fc3cd2a39de5913ed69285147df3105	\\x34d2627f66e8e7dd2496c322fca6cbb2593a457dcea272e1fb94b43b8a6d71bc9f48f9134b4c593bdd17e024a6059b1b62d80a4bd307640b49f7f0690d6ab508
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xedea5e395726f3fc6ec329d96efc45d52ecbb01ab0d4f480c57832b707f6ff4f16f7760afb890884f61bebf04e04420d45c473a535294097f0fc228c4d65ff1e	\\xff5630b58260a77a2a8ff27160e547621c70c76b197000600ca137a490868389ccbaf36c5656665b42b775afc87d712d5f92ffd176047963fb1e5f6737cb4b0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa404de1056071832f505c36292216558221f2780967df3fb21d5350e6acab283b1dbf41b846089d91c5217508a4ab30f182459702afdaaecfb97900cf0c58935	\\xbabedd1eefeea9f8d89d95df155de322118ad1f5d9a32b81d60f74a561fee5592843a4197efc17439e179328bd93765255e01b9fa40a80840adb5daa2230fb04
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xaad91a04b72a743953e2e27f43c2c0a18a6cdda7427438221b2c4ea3a2f123db450df715789c857069185f604d61356b774d2fc0b02f9d276ee0b0b21afcd998	\\x3b923a9a95e1f2bd15b2db6682bb8771a8d5177a0c0b0d4da401e296438fc624274f4edc39b2a470bb6346672655c9bba01f8b800f7ce889886274ea3712c505
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x69b14fd9ee32dc7facccd480d8ebeb5b0471e72f2119ec4f4d31e189ad4907d6403eb83c3a5bb67b62b4a51158aaab16d2512eba38926907a9c9a6d24f25214a	\\xc5f46baa91f226081b461c27fd496cae92b7f156b8b7fa9cc3d95d98238791c9caf371fe117e8026b21ab272f423a64293a5a8ee616b4b5e3877e4a8025e690a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf4cbed6ec7c98421b317a55f00750697274196fdefea2d5ce9ecd2b281a0223a391344e91fdca422d968cee6888c1a097c14abf7b96946872532c5d6518d9900	\\xd307e24b0714d5210500528775336976a95d3474d2527c241ff9d4efffe9524cbbd3c5e309b592636bd98434c2f25b3e9ca9379ca2037593c33f027c679bd103
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x014ed192bd0fee98c1b8dabf369e06ef58381d542cee7772e5f655beed6a3b8fd79b1d33ef902d575475190446af14ab8d1f2eb90e8a2cd393951ffa85398e63	\\x00d9530417fbaf64cac11e70df86a275ae682808882d43d3a135ca5570b30328f81173f9c9f356a80a0ec6cc984b493f4e6390a065e708c86a26b27fe2421e0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x60b19f47ac96124b4261c198c0d08ab878a2175b5617320c8f66818d83e7fd3ff2e61e30bfb01d9e78c16996ac797914020916fc9fbc46ac2edfb386427e8b9c	\\x6ccc14df8fd7c875423518c0960317599c73eb57bd3331e07aeb560aa4ab20189b4ff813021f046ebf81dc5c0711d61bfb97f93e5edb29c588660776d6306a08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc07d6832f28af34815906f9de39f209206fbbf03b1d33aead2e16cf97ab29c75593e9b2f39b9ae58eab625bbce75a2ba929da473dbb59638eb5a68b3dfbbf2b0	\\x7191eede01714ac182b654017e16b025e57d7afad0e988ce8fee139346e038cf384776b4b3ae7580e156999192e892bffb1c8213c1d300d13fe499998bec9b0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x70bd2ae10e9e87d29eee420c2de276578df6b013113fada7a59f9e20dca9f4ec67ac006d518841d37b98c0e364155756d683d4771cda34d748fff70485975d5b	\\x1d7c39fbb8b73128967995ed2be885bd777fe1d2018bfa8c3b243ee1fb1f3ec5cff9508cbf3910d8bb7e6e0bda7c3c4a8b0a7d08fafb050f874b5c04c27ae704
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x97d9481fff5cf26e18281fc2d990682958c8496eaf468267e9e3bb7e70144cc8a12b5103b79b85e9454bc5735c9f14811150851912e907985701ead093392ce5	\\xde0fc47390b22c5a699982d4a30a8c9d67051a8792db94ea0000597d37676bd8b07f7679a53fdd0d672fc615bfc05f03aa7fe3ea5162af0e952027a6d6bef70f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2fdcf8ef3790f1bf38e3140850698c0755f8b2238ade880b705c39153feaac016c8101e00f9af73a68bb51273f42bae661d26ccd8a97649d13464e9c6ea2596f	\\x98ee82c4db5a9513c397e62637fbb95e5bb1a250064e9e4bcf1aa9bb2ff5e1f197a8208ba2b331bf45f64b41dd7038d363ccde92837b35af45740294c80ffc0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x942504a8ae7a8f9a5c57cb4ebb83b1a25d816df33116f4c53b83b8feba20ec586004122caf19d576899917108cc639864cc4902fe98f5c08c8e978cfcada0d1e	\\x51db6e12e9ef9d0c90990021f06555e938fe3d9e69d3ca02ce12139d3d07d8fd1a828d590c1d67f7be2b1e7aa603d5a6a43cfe4ccaa5c0a53d9d91440b763e00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xff940722355169ea675239a1ab21821946d78914ff981be7339da8a6606911e9b721e12642afc9970e0dc23cb4d944d6cec0bc71c31fd2fd3b68822245caaddd	\\x7a993f84778d4f3ab995ecf4dc4d671070373782fab7c83560c605bb144616baaf742bcf938587cf8715c05cd0cffab9239e3932bc65d564c3a0cdbebc96260b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa95f9b7ddc565eeb11a3d3af37d8f7e4582c6da4ae8c32148059b9df15e10f03efa9fe73e6973dca1833e975d739d29f4024a00e4f473bc2129475a25e6d0840	\\x9cde7a7820a11b7acf3aed34fd7b7707cdf6b11bf215c96df30a8893679a031fc4b4467e86f6bed07bef4b8d8b5e49511fe16340aea37b02fa1b74c6cbd0a903
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1b35b1712d91f46bd2f2dadbd28d46cb904ee1ba08c7e5ae2383d0c8521a18b18beaf144d5f1d2095ebdaec74b33f18efa1896167dc4c95d7160031de5c69c2b	\\x7f7c4b3f03f4edc8261b4b6946560f3d47caf3b8ce717883991198bd4ed9820f821601c9f936beb588eaa91d3bb94c4cdb56892a74ff3a28e622b6542f89230e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9aa9354f44c53e4d3dc2c0ec6e9a0ec96290457a0185424a3ceadc34335302d9130334a29f9b412b667a40c1621fec200734c6a88d01c833910796fc906cb3e6	\\x417529e1ff78a5e0f56d0e181d21a9faa1f74a8effc8f2835191561b2b6cab82d434022d1e6745ddd90018c1b5e20cf1c4545ebe169a12449301c7c04984350d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9d18907fbcc474a9d15d0791f0b222dca25f9c77de85639b31adeb5396f4e1e038f1733ef0c3a60db273fa346b479ea2b7b65fd2972d7f64bb35c2358fc2a9a2	\\x51802a236062fee42dbb15c40340372c6d7fbb423fb43ee3877c0756e3450df31e86062fffb233dd1f9cb7a3478c69b522c14f531a774500535e2d32e2f99502
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9bd943dc08496d09485a59548b7866449f0cc11a50cafd07c81fcb19176342b2327579be8949efe885381dfc9e238c86339288cdf07265aab3edda9da4940716	\\x938748a48c25f3206485ebb0cedd3d275cef30804142fcfcbdf36283f2c91d81fa6920946ae584ed12b344220836844ea63d5946464448797131e06b1eb97f09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x22122ba7ed447f1d900b13cc0de967b44602b79c7ee80a8971855b13d0bdf2b922436bc9959792f114845916aef6a69196d0037bec5e6cadb268038b59fa83e5	\\x13fb461654a57a9b3334e3e9f2faa037faf312dce641004feb45a7de8f214faf5c1795091661c5be4f7d40d5c8cb82bc527350dd1635aa65cbb5d9a399509d0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x31573b4f2fa91fa88d63c8820348f6bc8a43d5fdc1668e0506f451b94c0fd6bd1ac01a917b0ea033d1d01fdef6fd25224b736202e039fbf9689848869bf17b9e	\\xb5e4d1ae408e5513c5a1a8bd9ad42a1bdbe87bd72f502e1f2260e9aa6c206196f2f799eae29e91974f890656f674c44bb2b62ae035dfc470586abe8ea8843400
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x91fc378ab80b0d864d2f8d1f5ecc3497b44cf65233888a022b3b9ce803db7e71505a31ef0cc06d64b5fb16cf8617209b384aecac90dfdc4d73cd9927f671e961	\\x22d8712fc856945f09649c12ed5c7273eecb8b961b433fd33143ff00eb5e41bf53272e049fe57090b95959a8bb23e4cd6435ce9dd6107611554d2b56330cf30a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe19fb987b4f3d53ef7e825c92c39ce1d110bdccd828cdfd0397079c7491517cdb6b0435b4b367c767c77229dfba2fe1eaa09f8001edfecaef3598eaee977fce9	\\xa0534b824b9b4415173955d4f518e8585b5e757529ef8e26d9ed5d8c6adef491d4a3bdf3795d2131dd8786d7ccac23574cb336c444dfb3c715fe7ce7874a3b0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcf3a20a036961a9116d49454cf7412eebc290b1031ecb9df960a8b491ea51ec97d6ef4a3f2d07aceb174f80e81cb31247e70350137546c39ef9b02c80a465669	\\x61f756d54e6930e361be49c80f630988b8749e97aa755a0093c68ae6b4c00b9f5d2e5865200c7f16143d1e448aa5a837eaf58ed879f5a204ce43bb5d0d19490a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfb9c1481dda403b57963fcb701c7c5a62ee2b42299cff73afefe21c7f9ce8e018a949e9f9d6b79daa562ea272153865cbfdd53b3f73665502f5695a3d4e13327	\\xafc6777a27d7761cb1f2370c370b211eef4244054556bce8e6f9e4041a7ccc950cb2153b77c55ff6fd2e09e6c9bf68dafd01f4e839645c53d223bb43a8f36704
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x636676a506490fb7ae5af3bfe31a17470a22aca62e984f6f88bf55b01935d839266fdabcb5c086e35240b78f22dcfc98535fa1d74b8228e4858b5ee548066c55	\\x02441b279abe90471d755a7aca34e0dc365351b62fe052cd5c6a3ec0dbef00f8019606f90877356db0c621cce27ce23888faf63e09754655f91f04bfca8ed80a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x70984e95dc16909111af2fde2e4873890dd77b1ff485ba0144c64f84bb924e59f955b599efd3eb38281e41a03c8b8e25b4301bbee059f9d8f282b38c0625a473	\\x29afcd2a476ae36447c02df992b63ac5d1f3956e0dc08846831287ced72e8cee96f315e5037987642f9f67cab095aba067f577be9925bc803c3fcb4fd13eea0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3d01677ad2f3c537712b03ec5d8c008144729dcb76214d049d67e51459a3eebade7503e67484d1447be665c6566b51a9a73d441e69014c74a25d82847be0950d	\\x1023f63b0dd182a06fca2c68f4b1544ca7e9b4c52244d01e3f585b2a55320fb8f49e99947df8a99450f3a4bc50d536e5859563357b2eb6960884c71c84fa0005
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x115ba456098910b86513c78ee5fd4ed3ee9f794638d2562bd9bc667c6516c796a66ccb74449ca014228464320cebbbff463fb17efaed3006874ba801f5c5b07f	\\x249a44684d8dd654577c2aabdae79a95c960350e30cf8ac17daff6eb698070d194f8e0a81db55091cc7ecccd2367c033db3239b1402dc30ffc532cbe112ad60d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x493079c2e2ca2a590ff23ce43c227436dbbd5011a56a46656188fd524efef0a7d7e3e65e541d9b30945cff09eb3e5656ca51465e36ca766200318e60407189dc	\\x892956fbb9629f4184688b5f374c64c9535d39dc60f3661380e741a20336c4b02a8522d7b2368ed3f6e1cf6fcc008511cc01bbe574f77998ecc81be0c5130504
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfaee1f71c923b24349243eead6ca4ee9824dddb0e21e5b3b440cde08ec598bf07a92889fc886c9490408b1cc38915609cdcf401d089a588dc0b85478ea53f69a	\\x1243b14844fa8220ec91f96019025c141e78c151735a055adbac7255485089b0250fc25d8bf802e9445a0426ce9d37d00a11f22e5b2ecd89706d2bd67f18ac01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x054d937d78b7fab83b71f1778464ed6233436144d78274a2c2973b3bcb7d3247ba8aae555fac55b0e89edfe26bd0be68e80f37b6aa9f1187d335bb3c70ade98f	\\xecef5512bb6bd76fa3eaab71c9c277ca0f726b981be394ecbb9d3fcc1feed2a54079582498e3c8c0e9116dce076e19dd626ec72acc0a417736151fd282e6410e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xdcc90f0744ad4889cb8e03929d0dc0d3ba431d6d64540b3b217f25c68a5621c714166fd6c3b930f05c3a1797c9fdf3f949fe3450fbe251c2c3fed6da07b682cc	\\x0ab5b40199cdb671fc248e00eba53e3f0b20cc37afbc894ecd7c5b11397aae0ee8487ee83f69463a03beeee6beb42050e2d686c50efc3cb5c5c6bc6e3d084106
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x757fe56fc5a000e05e1bab5ab3cbbafc0a7f9f5d7eddee55498b3721848e9ba0178e031facf42d4fa1c5728ebae6d38d9df05c643888982d827e1135c59300db	\\x13f58ebad9edb8476daec78dfb13ada86d52972d31ec8c064f909060cb225bfc05b901372230873c6ddbb25827055940dbb09f36d71a805bdf62dc21c4824203
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4c39b0b882c6fd96f9cf652aec01fdab934fd5726b36b5de4af3f8f3a8dba253d2f96d74f48f9c96e1956d58df8157aadc0e9600531c172d03a4532e51e2f01d	\\xce10a4decbe66694fc2430e5b1e068b1d543017032c9e8e4b930e1756efa8c6d7bfa9e98929337a1bdbb530a279238e20ac6ba0241e6f1f16b1548f333376604
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x231eeb4a3a2416ce33a2c0ebaff6a0c0b59d5841a8e5da47ecf594f8008c9725a5d6c2870415c31ef608001633d86a072e863ad3aa21365fd84ee3926d977a54	\\xe5579288651a93ad163fb411fcf883fca435f4547490746ce0816a836d120c11cd28cf61285b6a38270490b20a4cb2e13ad54c39ee273288a60663e654673109
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc30dd993189c124922cac74647cadbf877bb6f4b64d00df55525fa14c66892ca02b079fa65173ced84d4969e6b8172525f0f4a5932e444af17b2c3058c18488c	\\xf605ec182266ed5aa1101364e002e182e25a4ceb5b4e79ae1d7868167c5477c6119408b7aec7d1740348e2559100323d41b84607c4d46c38c71c7e31a7410508
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa80611d6dd164ddffe7cfd3cfe2a9f7563160afdc114d4dd51ba8f0ad18b6d8335e254e177e9f1a1be5faaa9678d8abcec606094787e9dccfb19f8b0fddd2326	\\x58d74fe67308dc447d69a666c03396346f3c9e196b2a5f6b3f9bf39e7c9ddc918646891b5c0246f3dff457489ddabfbd320966816448fe10533ac385b8476702
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x14cbdc313556b284b6ecfef26a908f23dc8af66b716643a29d66acd7f74ac83351d9b8d02e705b0946c149f4ce315504f5329f5b71b9de67639468b48a1fe1c7	\\x1ce407cb4c120c9ca36a6b94537e372148a746dc02c22eace2e283c4098d72c53ba9084bb2a52f1e7f1630221450f3317102601b67fcee143cc1e27c05988506
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7d83b679eabb205ffabc2eef5c267d634ab50c01a51eb75e2192d3bbc1aaa9b0b36a7d79fb52e637fad9cec4e292ccdc3e6d3d1c1d5ba50f2456c9b326152d0f	\\x70f4f9b24df4e0bc80e0c3efd7ef21db1a7eb3fea381daec904ef1e897ecc946cad4b08c18cec9c906faa29bd99bb5d6334be95eaa2219ecc9055e8ae0f1e704
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x83a883f698a90592d04dd7171feedf1502ebac059941f8edc76bb7ae1d270b7ed803d146359ee86e1baa6bd367be63838840e735c847c91eed61263b65d8341a	\\xf9abe71bb7ea5a74a0771da7c4209fe8597dfb609ecbae42770921b8f97aee2a6d9edabe2f8c2f91fd7687bfc0b5e332106f658dfbd2af9289e18b41d2b13e0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x335709989d3769130dd906266b23d4977c01d1714a18337e29ddd38a9526ec00e2eae8e4b553ea0b9edc866bb199b4d1d725589eabfd01deeef945af5be0c7be	\\xd1feb65af9af13336b02611333026355e6806e445f08d9d92705e518ff72abb39f31be1f5a5d70b747450dac3a5f7ba94b033061639e5f345e60a5109b469803
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5a18fa2e015d86912555d3de84669c0e1f1e37dc6fcb6078ff37cc08c70f7f836cd703c8398f97d1d8f310f07a6da5b3e3ac7b0e6af7998c59c3c49b7259b0cc	\\x77b9a6b945607602288eac6fca17a812cb39138d89b204ff0bc05e08fc3cc1617ea48cfb89f15cacbeabaff5788f5f8536d1b4171e2543faadcdea58a4e3430b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x42617517be08266b02336cfcf5d45bbba9714babd6a1023fbbfd94b8de7ad4e778ec23045cab3e802af235ff7708f16e2ec15769762e7864e97a07cdeceb33a9	\\x4853360d4ec5225ed3f7420258b101b64ed2fc78dcb7cbbab37cd48fb42c13a5c61dadbfae6575050e715613786838dc95433d4cfc48c8e0c9984e26e72f4502
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x67a5cafd4bfe0d9c96db7b0a36382e39e85c38549da68002bee037fa1575ed3ab1cd045ede7b964d11d307885439951858b9f718edf6e98410e10941deac08b1	\\x722c9649b07dedafcad30f510f9e18a1e6a383b349b13ce56a316fd801ee5fd60d949a681ea25426750c0e5bfcf4081e973e4e90a2fd5e70d911e6951b1a4103
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x953f1c9a32dca73e798987ac7c3d9083d7b6b90bf20eb70b7b260610f07f5f3ae9a945d1df365ecbd91b1c93101d7eb06d5724864ac8400d794de2d86f94d18f	\\x3fb952749038a7d45b839484add9b2e8011b73828ee7c5b7e179a675cf9463affdbd64d2b4156be49ca36f507a09522af82aeaa2692888a1c541aa2c0be64c0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xfb1e20395894a660f64470e7dd3c3d10a08857c88cab1238efc799fbe0ad8df7494a0a56a09978f1c23da624bdbc1e344beb892c6be2f090d71c4008e00de4f1	\\x941a81af92cad95d8c29fdd621a3d9b3d66877e7776100eee50da3c511f29fd11d62c6f79eeef7aaca25d386a1cd4068214a23e74f0c732e8b55f5843215590d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x02bec7929e143edd96a750b69f439c211e79d3866a36dee88ad78ff3960c80dc3d2998dbb891f598323bd2f0acc9c50e2fca33abdf8ba4d472f94f0e8cfb4978	\\x4fdfcafc5ce68a61b8d6a1f158e844dba0f25805394c77f8b47a4834a84a50b2832d9bd16912b2f522bf3b87bf810a3985a811643b11edb8a58708204df11505
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5db90105846eb74f74819f9f1002cdf8ae7170420dc37e26f944109ac95f1a78f6dc9cce8ec7df3fe164a9262ffed2447404a0bfa165782d39e38acda4714407	\\x9fe2be6363066b1e27d215fd50e3ce248d0557847a52fc51379433ada9f9dba258683dd2e5780584f142aa3306e0d0f7bf1586c337ceb6ebacdf8a23de891c0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x70c4b20a8dc90496c55cddabb55945e249ecf3a4fde1703f413a1e492538299da5183308e35c1cd006f8ce3cfb418b56935458b3fbbfb00a0fbfcd548fa1984b	\\x4a15fd2847ca4ebe20c8de563bcf0f4e25148bcc8208627e01c6d6f76d9b1110cf300eb5132d5894e38e205fdcec8682c09c1c4c2353d7b775e949798143700e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x43afe6b7f25a6d4b1884acee07dd2febeff6b9dc858a80af10df66d54a8cb9459f88b4f0252f3129e1820204a5a2344d2e9c82a7011a373564dff387613fd9fb	\\x81e0c6fc25999728b834e4ddd29ebff24d0dbe81184bf60542e858e20f8cbfcc26eae0577614559d04b4cf0f9bb540f9fd628fec380600a78081f695adf31e0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x99895433646a0cb0b655a823eeedb74b6efdc20f6a6c3ed6a3114445a35cddd9a105a51d12c54af5d456028cc034709f7d61161e9c69d78ba56fcc90046458fd	\\x321b4adfff90d72c05af5d3c20b1fcd18bbb2b6e8ac1a0b85fd8c5544ede0c2302ca01bc6dce32f73788a0dd250bbdffa08d56dadff4bea4f075376ff88ea60d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x52f1aa2a52f530611fff9be9f65dc9639ce99791bf6dd90b373d469790b732d970573e8ffa70263db8ca8542224534e35a9c6b248eabda6fc229ef67a9558133	\\xac3d6038864ce744989fb0081e1a2907ee3628c582917b958cc0f8329e918bc8f526990fc7bd96cd873d734833a01810d30beb92334067a8c6bb8ce378c3c301
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xdcfd63125829a210abc252ea99f75ccb1bcb1dd450d0977114e23eb06b0a1b095e69bd7d403c077779920ca39de58db7cb5f7624dd44ef950de8c581109cd52a	\\x9618ce529a7677779fad316d83a13c5e8796049e5a40eae1901ca7400eac36e093080ebe73f6d1a7127e1acbb8b6ed626e8f3231ce967b0d0cc8697db2aab704
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5228900f25941bc8aec60e011078672a910d44c77544b83bd7fba9731f57b07135ae172bbd6eda3b29ed4e47329e7976da469992518c1c4667657eb99634d23f	\\x66bb86faa596725ad7b078bc79ef67d4312927c5db09f74c8ef12e3bac945181c69b89e6eb818913d877b27998e1653c9af735890b4557c90c0fa4859bbfd00f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5dbd25082107817b75b449bd83e36a379e4d0701c68a14c23efc93470d9576dcf6ee18f6cd4c1c3a53147aeaa8adc2aba197adb7a7dc9e8ee11a8a21f1f29d73	\\x52ca4c5e9978ebcc86128448a16b1e0b9865ab594f525a90df7af78e7ee1ec0ea0d65daaa1aff14a298c10f2896a4d5bd099fffee958872e894aa6d79ee79700
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2010280b843e37e1e786f4b199ce79848ed14c823378424b3b1c0df8f2b684d8ccf313750a5e480eb81bf286138030907f7590cdd3b31872d15ebdc5d0089ff0	\\xc365541f777c521e1fb2484a64120cc3aca035cec8ab6057d419656dcb66bb315217796e380ef2028c9dbfdc827ad5a0058732205b52afa0183dfe9a7a22a007
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd8370a30fb99f3b3123d2216c70c2351e8d101f1d742009d1a83510dfaea2ca71814ecccf7442bee55601a922e4c56d504d646c2b4fb5e3f69cd9de1926c0b49	\\xcfa1962fd8abc589c090236e97875e9bf181a84b120bfc427528746fb06e3c58e87bf58c97add8a559ed98a04a1c6b9c3462b2570ab6deb742eb2b63b9dfdc08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x80a38087bfa533d47905c8f3f3cc421adaf473713ab041cb04b0cd9395db826d1772380ab79a00a5f50da82ff15b3d72041156e45f2e528cded563d503a425ed	\\x172b7696302c8df601997dc9afba07045855697e2b3c85146fed1ccab9869e5ea28138f5b7217851d087bac2dcd1fc6b0f33e454868cb61a554a0b31d9f2ef0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x644248ad54d15f7f7713036d7a29bf14ec96a678f473021f273e78d9435da4c597dd74a157bf255d612816623c978f726f2a0090393cebd6f1e2cd0eb525b453	\\xc3199496ce5d1a0a50368c804a75e8695df389ece30dc589be2d51584226819df012f76ed9b19504348cea6bf89eb426de46db4da3d8445cf21b9b444f477109
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1597542dd7c682ab296e5b29cdf47792ddfa2ce225182f4d036f2405a94a05953f5d6897da0e40d264a979935e0e5fa787efc629199237278356fdf520bed423	\\xc0cc42f6c5546fdfdb881377dbac45654212d549e95b2ecd16065fcfde39ba097565b57274bb8d5dd0b48d69014f7238a019695052a90efd4d9ef63283b0d50e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x82305662a553455fea8abbef99d8b637cf44bf759162d20681cfc8cac2f6b9ef5ee5c72d2a06ad620b1fda270a8b35a93c6e4edd4cc5c4449364def69221bc03	\\x3c5f151b44e545fd7b268afde2a945d7c354eb4688951dc80a9cb818705958ed10beb1bda688fcefe2271b5caf7f7523984cbcfecb9509a2d09c09d4e3e44a09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x08ae0da77f474995a37f3c2a045d9cbed0aeeaa508aa7e28dc55f495e9f07da28f93105541106052d453f0b8b23f2f8f988450140a16b875ffccd494a2fbb264	\\xe20dc85bd18c02f5e85ae8f37c12cf8897cc0269b9212094b109198f7c1cb7bf69854044c4b9e3f0fe4c43d8a95c9c66555dd47a763a888c759ab21b60a8ba07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe83971c83033cd73703bc6f54e154932abb52a185f38322c01d557425f11d4ee77acce580c2614d2bc9204bc2f11d1ad03913e00f6719a6e6f70b2ace7b0ab4c	\\x0f7d1ec6b7be9f348b7a93894e65a3268c71bc2ffd654732d8d9e9dbdb7e5dadf5a7b5b95466942078f3e57945904a57aeec0d79b249359be189fe1a2b46e708
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcd9908c73cc5da9da1247b853ce7fa3f636303ec4f0d51b6ca617f90cc03a1eb3e7f18fe30ccb303245ff49811b4ee91192733480998bcf71269e1c4d3bc213a	\\x04a2b56bdd7a1d250cefd3c363f5948c97b6e6566d9eca76178e9c234012c4ea8e1f75e9033c7df1488146dbc8b500f9ec6cb89efd22ff979c724639d6b90703
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf0dc36367305361a31b267a850d95d374eae84117e74a69cb8c5ad0ddb0497ee314e533fdf97305ebda0eb3b5f14c9ba97d9287563451fe22f3247ea30ee47d3	\\xa22f71e2f7611fd78346a54537d54a8c7138bab7cde4ec48c00f780a5771f1f806831fb0e16a2c7463a869e026165af9c9feafd38594156e89e362cbddb8c800
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x710de21d6a0f1b65bbf31c7029cb5d86f0fd5a02c21455da61466be5b31e3fbbd0d777fec4d483dcf413771651e368e0860afc7687a670ec60c555462569699d	\\xb585770e3ea8f5f32b7147948d9bd4b9df608632610be66394aebbcc0aa087c34bcc4b7cc1582e88d8dba69c925ff64f97a286659c27b46b67147f309325100d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x65f451341c049aa6bd38bf581bde523502d4ff2c8517b45f89b188b549203a4fafc92002413a6441d53110c0e3a69151d709afb5b7f0a636eb40d743d89e1059	\\x332f5c94c8026369ccffc5dc27e02e0d19c1f105ff66eea65aa871f4bae1c6c9bd0ae75b5e8b6fe887c8be4c0f88e5dda75a2d66a4f744d3a41507629466b100
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb85ed48822f4ad355bb04da7925d9d73473423604fe24dea664e713a1fa0959d4b2b82487c5ba2a03d3e043e4f3babfa34c29e94d9b0be377560e5f918717453	\\x5bd2de22e5595956c1b97c1d0c49aca08113a15689b5c15b3c7570e94142c232ac65e1fa809c1f5d3ed9e5bcea9c3589fffc7d31ace128592bc2229897ca0402
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5b4e2dfbf28c5c63d96f15d0b173324c670a6d46226cdd7ae7896d34e5a438aa4047ef9110236ec0bda1fc7718c0a73cb770ab323d10f458de55528d1e2faaee	\\xbb05df39078c3240ea9d94ba12648bb328e3fff36e6ac2500170d0feaa9d72797eeac96b86725f94495a24d48e17d7bec874ac3f70d2af6c946b978743fc9603
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2f8f9066181da08b4b336f471177f4afbfcbfdb880595d21293533d61da7de2f6ae163feb8bf8ce8309f9ff59224046da774a9db5a68531261c61ac5d8dd02e9	\\x6fb01f82ada6c0fbb4ae6ee01ea1f49f8c7a8a9be5465f2370e6652cea1548f12a8528c5767bd5e8a938af303277e77ef86235e651862c61e2e66813b00b6f08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x34b3906daf9c05b2be6b43aab9d04b7050eec8b925de40541ac91f5333f3190f956265aae4bf639044caa1d6859b485d3437d3f73013606d69e92384437d6604	\\xf3557fee7345d6ec5ed3b50cb8d2e444f397b538381b0765e750f835cfd9286f2e77c033dd5337eadc9cd614922016a406c08faeada3d0a62de329c960a4990a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0a628140e5243c036eac2d1d60d9c16c5ee8dc6dffb31da3f8bf899979d55fe59c028726354052cb74ea8109944e51eb6268e09a7dca9068ba063b5f247d7b36	\\xe285857fc094b91dcb3abecf6c0f0441c6b532ef8e9e0e8e4b58057668353d8f347642587b9436ea052b77b703acea558adabbaf35446a9cede6d12790b06d05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5b7589ec2c367e807e47a4033f04191de73c86956fb3f87c69846547ad6d14a8fd45503c0afb79a65b267e81a065eac8e1b6b398c0eb6fd6be246025d822a161	\\xe34ea88e255423e74f002b20fa0de909aeec0a61a53be7113bab65e880307b44cd5542d3185bd848acd17ef3ac59f1545683006da28dd9bcddfca5406cbe0506
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x99bcb76b6e8409cdc26cea7aef6998f0785061129d4388d6b0b70a9346a3d9d492d6bf5c2869d631274cab809d9178aa54e7144f7baaef4ef5c4be541ba6b094	\\x353228b922802eeed83f0db2dcfcc8284c80ac1b592781c01d230949cfacbd25a2df7b9e81108b84a16219b4278f3065f8bf023ff69657d8f7530a1839f47c09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xeca972004e55e79ac45b18503cdde787ff98b7cc0deef06e07a912dcc6411619c8fc2d8567707f592f2c37a66bdd2aed1f9d8d5efedbf4cc46cba56826d91c76	\\xc2c72832291b438d2effa0ab498b1e1e5afedda4d40626a7d4092637df5e8468603dd9edcbc8b992a16c6e68bdce54e963e9d304c16b28be146647c3e2609b08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa427b89feb0f0078bc7ecd74a6952033cea853d298867dd3d187582bab1b9850ad583fa643c85c4b42e59362b0ff8a10f8944a9fece41dd674795a07e50c4152	\\xcc89a52f46facd4983e8dc2df3fd045b9e6ee5f1f165f93cb0f182d756050a1a5f3e368b3e5a69702b27a8bf7c76416db412d1b0d02dff6706f491685498dd09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcac600a4d3d71a91282b7c16cb2e05f8474e6444cf42b49acf12099a82feea651ad3aebe1dbd73ab95865f496f6a9295193234e274eb6ca18ffad6f61e74e75b	\\xe8f2d849c1512c89d592e9169c3661471c413238538f86c89a2fdff0cd23ffffe246b8affc85f67afb67a82d3407094cd74f188b6698aa8f27e33d87b61ff00c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf0d72bc0f033c034fee61c4023539702a883ac2c4527c0cf632e0aa162131d90cb81d139c0db6f2e79f8ee7391cc90794c61da70a25a699717bba1a49cbd5969	\\x9f6bf024c46fef9c7efbe8ca91643053b950b2e393dd3adbd0f5eb140bc2b6812589bf2f026922172eecb99fa6c4d04eb1994802259fd622f7a22a9d2dd30f0a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbfbbfa75500b06da668b8d325ec2b4c31ba8b0d3ef2c2cfc0f09b2dacd4d2b677ca927711dfe54fec5586f0f4c850f7d5e5e3a18fc17ad73ecf83bbf5f59a41e	\\x1bbcf68410c2e7a9fa87e6580060f6c37fba2681dd2fad42ab8c691b6c045ceabaaab77c09ff0d037ee0f80a1b18326048820657ac84e1d54ffa454ea16e8307
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x244cd1eda9412aacc008767b84a710e4ea9c4ec3c97011cf732b44ca041c180d29c56dbc5a4640a36cd5387aff5b6582bffdfcbab5881a120e37940bf69e9a7a	\\x62d750b9e88771f669ad70f2ee72f4d5e5c0e93fd6823770f6083dcb9cb5c897d865984fc007090f4086e266bf26c32acd630766eb6b27ed5834086a9e57f801
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd28c93a36dfd2a11dc8a7e15eae55976d697109a50390c523b6e183c26ecf9edcb9e189c00ae6acd737f6305d3b580f7235cddf5adc67782afaaee28e775afee	\\x64c830abae5f280b1400fd1ba0fa44bc1251daf2de7113f628ab5f0f016e9a50719f599f42adb93b7a30f9e1ff48798ac395fd486a84f072db40a1dc5791ae03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x31df9ec13c6f316f26d908e647579bea2413439db1d04c8983a6574ba79122ea4f03e9ac46d0d107e905bf73ca4bcd46d2cb1923c704bbc87eb91559e938e612	\\xf938845d89fd78004a4e0bc3ae48e44bc9dacda9bef80f54e4e2e1b725cadb92f72d7234ac2c60e287f7a610604d63fd439b427cbd9c540b45b0394b9bc72609
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x663f6f0ffcab8bc1953c8a62de5ce52b13f7df878fadf498d6b8cdda3c97ec6e1e25e85220ecdce1ef199da851e84e663158cc092de52bccfa541e66382c4ca8	\\x7a62ce0e7f0d298c9b0731b76660c4d6f95c4405a4aa2745d6727ac9cf4f58521dfc7676234f21b54ca2bf750bbcdf51600a2475fc2df39e316e8bad76e3f60f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x64e664c9ccba58a7fa5d1ad9389926e3c5d6b8243aa4c7b4b056cd8d1adcf078bd53f151343cfac6cfd91be715f32b04c4c868e631f26f4dccafb8a9e8ce6ce8	\\x6665e971c67bab57986f9966427c280673bb52f597965408cccada946ae8fb8a76a50ba71a2a802fd8a5c72378ee05186e744cad23fc76c16c128044f672d00d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x642d19aaa52a50b545e74c188d4bbb4c470dc9e36b923e4bc6ee1b91c0ed7f2a74610a4db2152dfed2f0761b12aea6000505e85878ebe85fa95af226a9bc7102	\\x4dee2b49cfd826f6e11939eeceaf4075b30b06659c3326bb079e1f284a6c8a4647cc4728262d81bbba2b8362ba738e5c359bb0c8614f6cc7d5d3df3c02a09601
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4a8fd290dc9d67fb5d440f3c21e1a3476d0aee33c07cd1fdf567658dcf7e90de1d9081eb26efdaaf4d72825a1f80dede0dbce19f405bd85350d454623b4c29c4	\\x920121355d1a17b2afe3069986ff88c62864500eb8f7a33d39f95a9d2611a22d2d634bdda40e7b998b57138b420f8aa59f697342fa388659f8612c9b39ce2a02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x499609f97908335bb790ac1fb46ea8d9905353c68c895a4ec48afc4e778e61821a80364fc1e5e03a55bee4ad9bcc81e1a04e7f18c492a6b990d75f9023df9d69	\\x12df6b645c1d5787e610a25bee1dd4227b6d66e7dd30fb485d4c951e105a22a94d2b928e0a8ff1900739fb9078e39e536716058ca252edcb6e24a16ffa93e60e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x372aecac2ada0c3257bdc3995cec5f0a7a9d8f2a8a5fbd20b47c2af8b3872db24d62bde4899831c704083a2170ac0a5a81831eafeef490ef2e5f95c2d1d7b9ca	\\x4c06b813e78bc98c63428bf280c9769975bb425d7938472dff0e6d69e03b091aaeb86bdf8ea789b3986f8a9ba629ca20b180670dea2662de8fd809eb97914009
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x30dd0a11758cb98b37b398cc880a3e0c687ed960f88efdaf21d403e116409ce530949b7c849098d8b6a400e88d642ac0a6f461af2bb2206d26f4cac90d8dea3d	\\x9e00c7ef550f9177c9fbf299efdcfacf76f3282714dca913fee360303bfb803e5644f57521be7b7bc1e8537b0bdb042b264b19c38f9b880eb130a727ea2e410b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8f9f0e03102b6d13f7a7e593281884a9b36e7462d3e645b934ecef011f0a1559b635a4e3abd5a79ed59f1a919de585f4e74a33f72eec5e96c4d3d8ac0aee8234	\\x2dfb9e6e94505d0d566ec2fdcc055ed3eda10c462faf19b9d352c3a11dae3c4f9fc0744bbd111c8ffb8df5d8fcc4dbbf81f86a01f80ac854ead2cbce4ffcbd06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x337751eada1424987f9dd88cce7e25e8aa5643788840aaa5c786396aeb44adf64d1052bfdcbfaf0484f806dadb2712aac00b60f23aed74a7fd84934e59951b81	\\x39d3528cea9e0742e2a0d9729401c5c47fca9efe1030264351762dfd61e04dac8709ba42060630596709629e45caa733062d8afce19287b1a20b0122ab753e09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0690b296d9f0bbfc6abc9942032e8e2ee63d626c9ad6f0b56a75ce639e411b3667a9cddca63d409e84e52bcd195a384087c1c38abbe489dddadc673362ccdf68	\\x2bc7876a49f8ce1b2bb2ac475ad875d157c127500b8e521af2b970f73059642a7be70a3d92e24cb08934bfe695ffec3023beb05d85c6f7d576c42ef3fb1cc104
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4a281b11da8503b1bd560e5938cabe1bbf869c2784ae074b96cb346bd08dc46ed77ae3cd07ba2a18c41d1e13ab177e879825e4377e95b8ecd45458928be41ddf	\\xbb83508d81f3bea0ea24c76d8ccb806f54b5613fe696f1d953f7ade6448a16d1204fe8c0059a41b603e2c0b3bb461de73dfd82663c30c75eed60eb3df241c105
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x859ac21ea79bc64f5977ae25915a1fcf0a90ba7a51473148d6f360b6c0326a6b88feff70874ff73e5f2ff36a9bbe844d61529683b86df8a8b9313b0632838180	\\xe16e46c94b6941df7468f69713b8f8415bd5c8d626c94e1e8861886fd7bdfb0e27e5165fea340723ea03c75c06fa7c9d12c5f0dcbe29665571d22c55ad426607
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5f291f3d163b16155c55c768af1470f3c3db6ae162f1b6a88f8c7efb56ac5680594d7437c21e4034325a1dd42080ee3083ec8193fc322e217c22d89d979f24ae	\\xdf089a9b01d5c1e8fdf000dd182643ed1c6ecdb9306fa327c7c5c819e8e0d963390cfe0d8ffa972a0ef931125e0103879c799f9ad5dae37bdbb667bee85e7504
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x57d66a6018c298f2b82958268b700191352ad646aac899b9907272f641d32229089b6ff39c748e5af6ffe58e2e081cfd96ffe6059df13416b78a4f99a45e05c0	\\xdf9535ec90b876191e16d8cb4f862746ec1ca1f4e0ca6eccff18dc1dc1bd3cfd84d1504aedbf38ab8fb4b6dc1a84d803b5dd60a5206e59422fb20851e88c830b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8e7e093bc69483bd3cbddbdd401e42662288e1535e2e762c02ccaa2aaa3344dd135126a1d7f0efc708c2ff62552817db26acf8cd0f89cd178ae5926f6ea1c0e4	\\xfb099297e0e260b8b088ced6d2e86d9caccb19d702a0bdf55db043ae96dc6cb8fc89a0bedbeaea1ae0c734734256d90f9dfc6d68318c6870eff3db440ab31c0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9eb34debc73d18401d4749384e9c633e23df10710c04ae66b980a1ed82a5a69c26727cb895ea7430e0b4a437550106f8401648977f5e5185f1850b755d2b7f84	\\x219b6a9ba64d6fe12b3b1a0f3e0192485dd88f8517c60d1ba426a6f16bcfa91fdefd549b77ae614576ad525dca56bdd87e26eca3178a3f88e1c27acb11c18401
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbf321b0b9ab4ecefd20e4a984394a91495b101a0ac37b77675aec74e8730b450501a142c08d8b44bee18d6fca82a92157555a0b6c2eeb71c59e9cde1ef1a86ca	\\xfd00bff3def629ace8cfdf08eb1a491428c329ee0cdaab8ae1229085526570c0ae80f387361fe0f6775152711d113583069b78e97867983d7a5ef5e821b45409
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6b4100a67b282df9c611f521f2ecc1dc802dca2fcd1ad2fb9dd4b487b6d55ffebf1c7fed32e33cb4957cc8347b8d7f987ace50489219c53b1675a26821cf3199	\\x6f0994d4c9483eb8c0d6cd6bc74894ff2c392ea30d469602468242b95f9297c717c07736d3b8e301202df94eb90b8f9734dbfd071ed51adf115e14e5b98aa00b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa2535c14c0895d441f221f5c98b74e8938b62550eac9974eea05be02cbd00749945261528534e8d2ff86e9eba511f1dcaf8732371099f572277e998874842762	\\xc38af5c05ea0f7f981521812e9c89354b0e11885223cc95eb8449cd2edc70cbc584e3e9537d78e3dffe2a551dc6e539ac1970adba04c117dee38e1f0c4705d06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb7c42e96b37fca9abd905a5089d4c1d3a9c3e8bd9584ecf41531302a333839db91d2bcb3e36d2707716a979b709aa80b7f556763b642d811fa593bcd687ea222	\\x0a21402707a2d492e233688cd13e7aca44bf497810a4718719408de7523a34c2fb7cc5de42d6a85b1b999d0ffa96aacde6b191173dc73b75c47a011ed7b07c0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbcbae42a9d01482002871dd03c6f59fba6bb114f0d9c3627d102bdfb4eab4f040c84d62edee6f8db1d5ac0012b7aa855f39e266e68000eaa30fd4ce01ccaa8f1	\\x42fc6669b01c7af130703171edbdb817b2f96a9fb25526176141f17fe22cf984590a401e8a089d2367d297df72321d39b1a5a928f9a9000ff7397d9b3d663f0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x894fbaed79760402db88e3d271282f8826e5b12bdabe2929bcd45bee0c89f76d8a7f69fe4e836b6a6c75944450be5167f9dc4e32b62ac40cf0a29a53422e795b	\\x31c386daf92e849b00a580ca19b90bd4f90dd6e224dd39efc3792ffcff340ede708ea6fb92636fab05705636abb6aa748996d3ba9635c5fd0787b788b20a4d0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8e1a03cf50a9ddde401a8ccb070361d461227a1d6aca4f34ece691f8ed5b5a49be2c45a120444471636664a1d598bf2284d06879b019eec687788e34332f270a	\\xa19d0ea2a34234a0a168fa94b1d488223e68e55ebb3fa7cd371b477695cb55b0f2c6bc85e16aca41bdc2d7a7f2cd23a7d4e4ebe8d717dbe435812c29afd6ef03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9a2ed0da3160e257f454e4887563b0d4495fcbe603cc9cdf06cdb80eca4ceb888662e89376759beb66d9f1d69d8f24401c18c5358b11b1297ecbc784eaf8f5d6	\\xf7f7f58afcb6eac3df4441f02971d5390f15821e68ad95e9e6bd5f118705d668aa3c4b6e01fd2a1da4b121694f2579cfc4a30fa30d9a679a691203c049b1b802
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1e10b6f918b7999557ee963f722baa31b183ebf35351a5b37e9710abe47f10cbb3645c3feef37c0cdeb2cd9e924a7b2f13b2a5efe560dd6e435cc0478231e209	\\x292edeac86214423701343dd4f4235ffdcc23ea7f3e27c0b2eb8460db5318ca7c7bfb61790ae68669e55940936cba2fc8b87c2b731e871919827aa067976a605
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x03f83e89e1209c25da730db29519c2c65e0b0f08ecd43dd05cde135be1c2be9192510f7ff80dc1aac793b35135da85328d2b803705ec1c9b4621942aef8ed835	\\x5a9f24e7a65d4d4599d759e1940b700b09d57d0c69ab238331d13eb29e8f695d271292fd2b22913f152fabb470d9af12cf915d93232abe510670c86537cb5c0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb777135e69a10cb40acac6845aaaffaac5c51ec5735e90c5f0bf64e09ec20b925cdf533ac78f25dbf37de00d9e80a75c7406fbc241e416990895ae4f69ad010c	\\xda29e878b8bf307463f6a399c5f38fb08da733164507ec5a9a1a183d48b8b09e09c387acfcf23b6886fc5fc91166e0a9c5e40cc0245df7e05f21ddddd7d3370d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xdf445e913b2f28a051a27c615e2c60563e1bd209a3767365997165b999c70bd5b40585f6b952e9e328bc782c0669243d91e3cb8c3ac22179d1ae8dcc902c5463	\\xc584dfd3beb215006b19cd0a0a57821ab0eb8072a426b6f7efd0f3cc640557b55f64d8bb70f8b820d53afacb232c0b801a90b0baf26f76dbe27f1afaa863200b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9570c99a87c622515eecb6db91865fa6f95c77e34bfd5c5ed0078865986c1e652523b10ff82241dee8543763f96b33f9cbd9d7f792e9642723979c7a0bc2a214	\\x9aa4836db9bc293eada14e3e4be3d353d981827ecadb827add05011182f5bcc4438eb49dac263eac3fdbbdca24d49cd92f78bf9a026eeb5a613e0ad401c5e30a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2da765f13911b652802e9b2e14ec68492b1c4fecf6429d3ed503383e9feff493c12a10f8934ec6363c380d607eaaf6082c66df7f091cc751ee1570dc8a84a759	\\xf39e33030b929252a551ec3484b4d12db1686f328963b0fd2d8fa5ac4fa4b961c411db7081bc8282a49b997a754fede3e3f3f838d4411c61af338bb6a5805202
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x56ffa6c75b172b652ead6af0a129515924e1eb7af96828827dd2ea796589ce5ad2288199ad7f060f2f5c671c2dcb1f656ef816c9a064b2da901cbea2f211a64c	\\xee876c254a6ecd21eae30d1c8309b7b95b048afb9a8c69ffd1921cbd16a37e04e2ff4df3b25fc296bf44b162cd277e94adde6fc9833df7ba9c6ed39631acd809
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x24a6bade78943f8298c11784051c4475be98e8c5e8cbcd882a04392a83e475d3b45f411886316cc71d3b045f75fda8c2a338fe54d22eb19c823bf68a86ef747b	\\x401c821fe8b2a04f39f425f1038f71e49b0391029af49dd58826d40c972275e87d056e3a046cc69122a750ddab74ceca092dba55f5400c9a26648e0063d6a005
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x16778a7e7e0385fe9aa87e6045211908eb5528dd81ad487d55702ba7191b04874a918c1dd545cfa1925419367be00886e15f3542f93a45c64335cfdbbcf35439	\\x87932f6fa99136c11017acdafbd89514f3b6f545595bdafe95cfdf26abf893c1a97e969ffbe1a68ad7ca9a3c70236ced40b8d3c27598a67d4e507eca205b8702
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x89a5163123e142c8274ad22aa0a54f04612773625005ed54a982637d04ddd7790fc5c9687d5ae34344c8c2a69efb4d6c2424a45b20f0046343f895c43c5d7042	\\xab94f08908c2de2263c425defb1103b4e8f222b2275d566b36517409639f95c0d4c201f9aaa26899a5a16b98b19deadd0fa662b5ae6b0e3e168a2229ec218b0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7eb68aa3a27236da516bb7ac69fb6c804f6fa4d36b5e7d6a2beafa6f938369c50ff67178015b58ff2b31cd79c35b715387272ab75e88730269a5d50c730d4048	\\x67a0a55d6fc2c85068643948d9c9529192697428633bc5ae0850dba57061e7dd62d697556594fdb51fb54dbe595ce80fbf4ce5be125685ab1f469e236ad19006
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe57b45529b57fc30a067d2e201ed09c3db38f588fe71c4d11b2d74d95653286db6033104cf0ea56a5544670e2a57bd6d6741e8db1e920889a68c78811c657a81	\\x44517f86c0db6245404f9b859270c044e30adb2003fb876065e558e926aef5e6aa9dab364b79344c8c00bc7164e178c6312a6cef43c5d5e5e20a0c14128e8407
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1ff10819538965ebbd006f5541cb2a19e40cf41d6f7135645492927351339963ad75ec0fa62505317417b10d0b5c8dc093102ae2ef2213b4ea45148fb025208c	\\x94d8038b7c8ffd916ab869bc576125d42d862af4409c40db9d5ef12b0d356e4f86bab41a6b6c031c2088bd85c63d36bff92714278a4db2b610e698e3dd53710d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xaf74992802aa635f29b8cbbf22495f1bffcba58e7eb508b4e211a43c54dd888bf468fc31bbb933b73b1fedd2c435d7986981564fff31e3b59b73dbe98d88a83d	\\xe16ae23178e35386e94cceda90e89059f07cf3769edbe6a1c988b4ec6bcbe9a2223b6e9dbd30b585a5a159cd6a341c662e901f3d19ed6fefdca66203a8fe8f08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe458db96d8160c115f5fc8a51465f653d54ceaf7d71c8ecff7a1787b4174bb7cf80bdcc78f589ac978d0acd7c8f90a571a54f7b08c3262d334747d510a18d691	\\xd7855d9f502916aea93e23df750b42529ba10225c189a7b064642ef02a7c53945618a611004a690bf7bc4bb3eddb500eabeb9d461dbbe86312029a1d3c12b301
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc4946f95146da8bb2df435f755a02dd0c27315e0cee9504326eeccc63139070f1f2e5e36060536cabc27a2a6df23e37031d021559a247d958c2059dd54d8c2c6	\\x740c2ae5886d9a2cba99942224bd6b67b8aac1d5aa5e1cc162898576f07a0a5df9af91bea460cdc977124eb2cc67d0acb77d7ad5d0123c3896c7357bfa6e960c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4f258e217e3c214a844abfddf2a862e22615b5a1770612ad34fd88c14ec128326bc49abffac0d14d246cce363ec3df2b0ad3b9a66d347e8ad1b7a55d9aa91bc5	\\x49abba3a96d8681cf754bcb77d36f96aa2aad701a9993f8e498ab7e8f4bd9e132cdf9383de4401cd92633b735b7ef73688ae54c184c285ca7d1979477929290a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9f100cf317f85d4c468df9df7d742c01f5719a208468308c74413c04bde2f17ba0cdd386c624ccae2a5c873ab132c9a8864a403a2011f40c9811a1cc38c52195	\\x822117477137c7c81208fb1ed35ee15f0a4842dddd5552ca231f742cb673b3e629af5dc1890b548a95d4146fd72ee0587b8b8f78c08ef228a6f7cc2616d22b0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x49bab45030f3b33253c7691b2527efc9308dd53fd0b5b62db49d9cef2da1ccd5ba87b73beb6abeb54c159045651beccbe9019df542eadc191e314a7f6426c5df	\\x323954f496e902f5a5652ee8249cb830d2cce82d2a4fa83fbce29dfa47f7ec9ce778c6d9dd0380f5df88a9044a15029aba61a28775b9eaa806575e4cc7d9cc04
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6a6a35a89f12e3df1c0ef1695e73f226d50efd78375e7d707f2ec4c32936ae28e9414b38950b4deb1a78fabb714332b31dcf9daeb940a674008965d8a257d554	\\x774ad1ae9d35137dda5aecaacc145f1e8104dc7ad8262f59e9856f6772ea3b9669d07c48fbb941063ab1896ec507833531120d9cf7e762eb3fc127fcf38efb05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xeddf4477fa1f929f70e9969233d92f08babe07d36fe4ffe484da548db9efc059fe6bcd6b687d1eaedc3a16a01d7a78e2f0a92fde4c081c9957dcb1d7ee12e37a	\\xaf38c9ac66ede256a51ea279fe62a0989a56fa2c3a6ba445d977638b1706af1fab74a66d1f871e769ad51611af6cad3f49ce46454415d2ba1593e45e33dcc906
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4395dfa085e84a5ab61c58d76117016d95be05df550248c9ac7c5d0fef712f5596612ea15a375bce68ebd599ef6bb0ce3a865b21c0fd72e119cee1b95ddf161f	\\x41c3dabcf83caf346ed85ad1a05eb0792bc25689e028d1e1e28a5c87c6c94248d976298c2f224f419bac56ec380950e50244bbe80f4b93f333583648e468a90e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x257de1ebd5c056d6deb4f2cba96a85712a586192373511ae9562e9f445f58736c9d260243d5cf80b352fe522c987bb11a7ec704bdaf42a620f9f829a08a7d238	\\x20a65f6112f5c1317cbd7f9b7a29ad860d92c097050305ac23255e1b13672d0015146a99e7e62643d79856ffc4c689eb33fb3bc97466b28bf928583be3e7810b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x48a4e6ca933a046a968f551f8302a21c23d4bbcf9c98c5d4a890fd5dfa741b4e2b75e4c1fefced781d5ac46209f39465eb4f657983dd79c470140aef05e6e7ca	\\x19f47e1b6f027445f1336fff54c480d86497c43dc260ee0ade1c63b5503299ba9ed900b3016798a6d046e9843d00ee721f67f14deb77171e494a4e86997dae02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf5a3bcdf6913a884492d885e1563b063fc187e67fc489c235b25838dcb0faf21f3ecb07b07ab799049644f1576da2999a2dc8eb9f1b52a3b50dad8d57ba334ad	\\x43a3258cec1e7b611ed263643f6e5915a8d8cf2471c03b69f3ccacec95a676389f13982a6f1a57797f735811599177f88175a8959f191ad0c459767ecb310907
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x154f88772b8c5f4bca74efa22f1c6718fd26583e61e4512627f3e278da8eafaad720a49464c596673c014cf5625195598b6221eec5891cefa43a5e5f1950fede	\\x03be84d23cdd341ec6db4d14f22d2cf7128bfebe066c4d6c7832449338559f524278f0959a9b7f2558c4af792bf9754a92e86c8a7c67b977c005a12180a6240f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5318174f188fbee4e205ca4968bc7271537b04595007bce1dbd52700ffba01da2b3474cd1818a50ec05c4ac7eecae436368f50d1ae8d343332e64d2f9baa0ccd	\\x8fb58fcef68637f34454ac46db47cfce8ee3d27cddff632a1f2d6e64bb13b88f4b1ebca70ceb2b4c838d6aee8278131aa868b94fe657c8de0845b2c69ba3ea03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc658bf966408dab5f76cf2a8129d04c7d667ef2cbf287ca4dd042ddf27519ff7338bf33157da1de54fc4bb1e2e0e0a34605cd2b1a8ac752e5ec56eb9ba8acff6	\\x945154cbad0e71e108e2ac83e46a7400a74adab9324cc2b9368a05ff70ded9f0423b745bdd042dc7554616d5477ad300c5398876b4158409bbeb6e872c9ff508
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8d173c8a8900d67da6c0ae8f727fda45a557f39d81f5680a89f975ed1b944bba78bcaf2df17029d1294e70e7b5f2ac5c62127197eaa837412ee223c245a63bf1	\\x4b9a9eb47840bbb3b9af09ce0ffcf32c5d013ec7c891bb917a56fd9216e743cdb0eced62207a6b9a966ebb8a73508e3e1c81db69160757c2347036cc0980390c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf917839b47bfcc8887908c36b0ee62cc38c1e257aaf8edc44c29c0f1045ba8b756c2bbe644f2237a60441ed17ba023f7971272deadfc18d4cf6fb7e862a10ec4	\\x66e1abb75bc9ae03e22a0dd5cf2b4b6fe2150308690021226e27c945fce036b631a7e9231c9c08ea80d6e774acef764feeddfa0b0240e1c58a3a9624631e5c0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa53419859ea42599780e17c9731e846d9cda34100cb70b443e355d66ef065cc584eef4d80e8053d10061f2b1cde4c1b5980b7d4446519d37595012407ed371a0	\\xf28a1e9f849ed81092f129b43c508c3c7e6bca37b3c7a8c7965e8911788a1ea6a2a9c29d6ac2a7fd5526b2068ab1eb51006fd5bbedaf48481eb2a306f6c10006
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x540cee979335b9fcfd3435c13f8891635c71056b257e516ff2d93195f1a74d77f079d9d4a8fbf1c1a6d456eced071eaf3bf4f5f126227ec0503153dd2d47ebdd	\\x875a3aa9942f9a57ea12f031352b97b93147375369be35112a796c606c08d46c16f7cc76a7a6783cc2795a23b6fad3c8eefdde668f2524ee154b604ebd692605
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf57ef558c1d408ed513e52aaefbc17bfb18b70ca1d89ce535ee5c5313074bc37491515537a10c92d14c3b5d5c8969425558d550e12d46d95e0f2a45df393a2fc	\\x0f93fb3caa884141e6543fbc916a57fb921f73e7db85e5104d128637c960854c0de70296d7e6a1a87e3b2a49ebc9b092cc9d7db03e61c831fb74d9de8207a707
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x32e42f06a8594f8f7607525587a31f1aec454fd3bd681352ea7a0e298cfb806c414c61f814433c087b6bcf360c6be3917528f4181984c9ad738973d98c7bbc47	\\x05b2b87048d0dd9397579384c654ca16ff7e16001466c808baafc83d37a68962737d8bf54208709657d91aba605d1341a513624c7ac5729b6d1e8e162d68350c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x32d430a569ec8e99742b305679b2fe5f68c94035dc73d5daecf0a0ef6c92df2676fcdcda5415fcacaea4274367605a1fd81306c58d9fa4ef09ad822c3c45e8fa	\\x95cde0e7bfd4c9307af2eb28d23abc2f5162e76c8b1c24d164c1621a2ee3cd4fd1a1066e50ad9a52ce77a2d7ea0bb6a57a915c931c20b7614503b0af49aa2401
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xee835eeb0f76cfdcecf6c570d0dd139d1b261d1b16cfac6b53666129251a3550f0ce526b0fa9f268c366cdb6033ae46fcf955b5bf5654e09fbb3437780f8f2ee	\\xbcb05781d2f7fa22329457da5d2dddb33786495939732dd0d2512834117b6f545acb5bab0b537bd786a3b82b65ff6738833200f5a1b4a3e52186897f1a354f07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4e58c9d356be8982cac4d0abc893101fffd2db84dcb0484507c15ad0f954644c721341675a3b41cfd8807d35551333822107e3b853c3058bbf761dccf36a5617	\\x45e498a97fc786e917acc95c867c0b72d4290be091f0fe91c9392d0cd0abda19e848426467c9f095c4c7ccbb8ff3fed40e7a9de24881320cde8d7690ea61f60f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4a0d5e0e54feb99d038da86abd90af7c06a10e726c58e9961e13e3c0c1db6009650bb2a442577ea79520e84bf4bbb16e10f77a616e23d686f209d175d0b0c9cf	\\x03bd3aed729faf7f622dd311908333b490ec3a31c07dc3462388cf364c29ff1349fcc98bd148fcc392d66776c94f5a90288ac5941f4b42e75ed037c9d9ddbe09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3118b09b902aff3f203899466937fc0a008274f84a95fb1b7f3947a81de4b7fb56ec5a65ae8126f73abe750ef68b9a8e8de4df587daf8b5e63e0469c93ace19f	\\x167200244f34affd59da35f8b27254cb762304fa8118cd44b0c505d132314e783bb786679afea6869a137506a5da2d7db86257b24c32cddc131456cf6572150b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x602e4d40bf0cda32764af0bfc11d89a73284ce90cb82f0e453768e943627422a6857c54fe3e15e1efc7bf17cf31b5c63615f191fee8eb9ea64e22fd93f828d37	\\xd1b9fad8e044e0012a5e3c8435bf447e7bacb53b153937759c0c5e3a1a906ea721500e3e2cc409dec9e0fb7e2f19ee3baa765e9328b04de899ce1e27c2d5840f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x61d8b2fad2e49c33155e426bd2e09898ff117c785c00f91bfaac362c288a5fe79db0505252fa846273d725c4682c04301bbf626f944babc04660a7de3c93cfa0	\\x0cec9035f37cc2ddf49ed48d3bcab7e643e774f821d71266ccc5e5133fa35fcfb4c93c50fd4b3396353f25734a1aa23951cdbda5959c0d18bfba9c9cbc5b5607
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5e7005299cd36af19b54abf1e4c070e94596dd1261ee63d489b07e6a732b092046f6c8e1ce928da4f1b8a654796102fbcdaf6ceaa47d0e06cec8de77d3ac49f0	\\x2eeaee4423496391d0b2514feff18d9fa4535b307df1f3b1df6c8bac7e736852f947c703d93109672dff683ef7abd7c7795cb9b3a58e075de8ccd4425ee05d03
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x7e759b9f857687a55ed6eaf40f4138d1fd7a442e4ef9d9fa5987aebe5e4ac613a2d609b643e5bfdbe02bd7fc16d6e5f2094a439cffab05aaa3a750dbd7a8a7d1	\\xe9a88e97169c64bf29ffe320d3ccd2cafb38473dc0b0b38255306e30bd3dd92e8e839ccc63cec074bf12ab066988e0df642ee8e3c50e5823b8563e1fcecb3f0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xded30e7de71133d607a03d80ff15efdf4de9cb6fa970e4f6ba96b7891b99327390162dd2d005e8cb66f82c53a3e31eaf43f05161726a6036fda93acdb1eabf78	\\x3fb196a6cbfcd423ecfb8b986220e78c3a7d025dcab11e9a89f1f5d890fe63f90a616d366291802cfc93923d6b5dfa17b5d2b51a9513e80b97743458c744250e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcd79728187086fbc33b4aadd370b12518c227253a5e0bd945241b8b88acf8c079a0b7d160ec8b0a44d2899f2dbd85282144362560021eaf232edd6c3f39efebb	\\xca16cc4d68b4d4b3dc28b276201c6a96a37b67a2ec2e5a8bee98f0d4ba5b09b7fb191e2254ade7e9662953b8198aacde03f9d6a5b605b5a50c7657322de40f0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd3650f28444382145bae97a34b72a3bade397cfdfbd2fd1f8e6f527d0fc58e9134e913a67b3c7f9b5d808c7450850d2deaa1cfa47c27e0e63e98e58ef8482a59	\\xb041a60b012d1f328ddd2c9a799441cd6245a35631fe5f3cbff89577edeae4b5ce09416dabf00cd0942b3c96e76d6e027528c07e86e135892065b94b9055ae00
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x741e6c8ff6c56ea791005f000433707e0635426c8e78a000bcd529fb54ab031baaef39fe118514b64fc1c456b0ce8ad964c3d54803934f7ac9d2dc2c6da341a5	\\x3dcdca952664908f5336645ec7cbc27b5fc5b8b31b9663f26740ca30ddb47e224b808e8f1b10bdf7054e5c4be7aa34af4750d072d3bd9df0728284aa532e7f0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xadc51dc10a92c47992b4053e5cc40c70f3a8cd0cf0fe7f89357bef20ce9c96304d1daaed4e8b10bac2fd15dfc9d7bfe895053ed69790b4ab9014d4386f011005	\\xd5dd9e0566ab17926449b0f8c0651bfc8cdc3597839dd2e353b49d8fcaad9dd584a371f15b2c7b6933552260981389c56aa410f94bcb3b415be8d9eb873a4108
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x42636cfd91fbd79dce73a9314b3224bb0a090993b23a05a1f0fa14ea5674de046720962e9886e68c84391f7b6b900f1a5348fd5d9389fd2bee6ab42fa5634506	\\xa208fd9b7c4735e6b1d104a77f1d483d59a05eb1df180ba09fd1e1a473af80853d26a0365ab2059f6e8ca31787ccde4f10e9535794f513047bf323a69564d908
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xbd73b27d1e9a003218b4e7295f4cacfcebb57995516a1b844cd4f24ed80f1004b46a7dc4c9ef5bdeb0dcac85c5be7a5196f8beab6fca154eb02f79764471e2df	\\x5d0b33d9b2086cdcd2526ff3f422061eca1b025b808123c72dd1beb83db9723bfeeb606aee29cf9e1b859f5caef106243d6cfec4d5ce655d440ec519afbbd809
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5d2785429038f50575291f1541580b4bc84ef54955a44c60d2d275af6bbe271d5033428684e7c6e052995f23fca6d44ee180c7e4d1269fc35c842fb1a47f1fd7	\\x35ee3afb2b4d32dd1de2ef072b7ef8293f8b4a744255b3696f5b64926a387708c59656f5d289d520694c46f52281b0cac3d13a5ce0fac1aa4769e96b40daa20d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf8e3fc22807bf9f84cebf3c314ab87b7b6a3cd69972e1f95b4a18e0d3799ae83a1b0d3542e478afde9ef4c16de3504c3fb49f3302dbebd48bc501ce53b656eb6	\\x28812476f78c9212e2f5a19eadc360608b6d7171723d9a6a0cfb056f502ee0e1e2be08fdb3cb4e607ff055d81c88e654d866cf199d5657eed0b106effb24b608
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x189c92eda09600a07a500fde440bdb32fbb35a6d3ccd4daadb2991c7cd6b45b3d43ce97bf7f96be15fe88f67b1ae403084b0ae80f02595c394883eb8b911efb7	\\xd714d4ddbfe0f869f7c1d165b9f4665177ed0c04b56b7711880fc906ee35a7a93209eebb4b6d8565c44a9fcf31d010653388b5682ab6eedf3ab62b7f02c9410d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x991350191f42fd6f538388dad3512b02d90f25c488cfb8e780ea1c5f987d65c64e3a7d7515538927d3dceaf418636f7eb0064a33faedd7f5e16e6902bced9677	\\x1eeee43609270b72c8543ae08768dc9d177576821ef16a40a150dbb1e8d1d86370f6b3b7faa02cba1c5fb2de14eb1e8f6c7cc42a3cfc19b24ffd3a214937ec07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x07ee6e4881d5e278d8dae3e98b0a48588323d4bb5fdc29dd9726aec25937a685aca08fa7376276c3a03f684226214f429fd327c01c9158ce925d45e8a2f7600a	\\xabbe6b4d42425dda5b91188398a4790a4201769e74d0e101ec2d413fea813763d1c47156d32912531b39ee2331c5420a5ebbdd35f1bf3321d77f011c160bf906
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x64092929a18f13f9777f46854182359b897cc32cee307383a5b4413fff8cffb441de845b1cdfee397c8cd7e8e00f18a2e19d721ecfed474f418be881b52ce73d	\\x909fcb66e9965a8ce2c86163fbc7173833f855351194c9946fa2b940b2e8cad159cbec7e847f2684709e63082cda800a02e26714e788250b9b36d729d3a4d209
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb810b91af3da1a6e94616facf9fdacafe0d5e1fa42832cf0732a864a08e61c2e601f394965129c62be6c8e1b1d14203e05f288a4ab3f4aa27821a8f602c52427	\\xc7bdf3f44b2c1737f0cef3daa483966a2e76dbe74a86c57d677751f41a697f404204a5eb47864f8d4b65b7a8cc8575a27e6ee2e19fbda006672c9c3725d10705
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa3cba2b54c5138981a40128116798dd3ac3bd87265f9d099d4038d72224256c6dcac17f9a4c563f3abe455c5911a4d0920489be5d7f296c61abf0b4107bb9824	\\xadcec8586fc18c9f512122e602964a890fce13ded45448c4243b5a7fe6af46474ba064ed87be99af22fe629cc69531d20a8dc9878af3a14777cda7f95d3c3809
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xad2d2c1f5ce1a985f2dd5c11a2db01fc850bb6baec88bd38bb0ca52fbe546d587b899df28c9d8583e322cf48f7db47fdde8460ea608e6779280ccfc9a985ae43	\\x343bfa35616b6ad36f8346d190cb3a650a69e79b1819888ad6367f8150b2ecea0c7433b766e33172b645521ebaff69fa183f3be461df3c21ec2c8a19a880f100
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf2dda0e63216c067ed6248befeba4318466ac956c904e895de0e975d3fee6caacbf230c8b1fb4facb2c7595b303af72753c67f13a76ab619dde075bef75b9694	\\x32c92f4a9276145d7e5cbe3025c1c0a47bbb18d65e279267262ea9415e38aefa4bcc235110e354a608d1375d115d60d3124cdb15f7aab65e9c70eece876d3907
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x88b6e3fbc7b467151afb9fa02bfbddda5f6879915a44613d532f7a66185ea698ed9af893cf79d53664e10b40c572d089a9a26f54e41323698844de84aa37e4d6	\\xd0dac1b69cd1d17ce3bf11b557247fccd091b5bda0e28bf2f70aea3322c738cda0f33eaa0a4e06102ae44805b1e0903ed3444a86a38fb65506d58799ba76e502
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd12883a66074e699b9b1187a7349267996a09c5d1db4cb9b917b1c15c0c1a1dcbbaf68b6769c193b45201122e7edc4d76598c0d213934161e32675f9b29a9a7e	\\xcfe408fa80b4724236d3cbbc343fd72970f3805f4d255feec276f29a29e108dac599346e2299ea515a03ecf659e7d42da05bd170d7d75fe74c671162208bec0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x66821d1a9b4593324e2f009bbee664dac4b1146e262db4fb87f1b81d00c423574dae7f9fe6946d0d36aa7e0981e8c0d9ac551065e2171cfb2a484ba35787a2fb	\\x36e347eb766089e84c5c767617c7bcd243743e264cf229b131655facd03f3607d9b0fb0acaea2155da5f803bcf3bbe102df208093067eda66c5f476229d29a0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x56dbe84748dea08f1e2d764d15e548c451642a29e5aa674d38458ae1f94e8ae9e6b0b46f02f0e986aed31e8c31f4cef269abd3bbe6ed2724289e2f771aa6621c	\\x14b3c41c389f074fe8754ea955bf97277bf5e933495f545d04b27607422cd35475f8125ad897fa1da3b7886bb40b1fbc8de668d822aeda6276b86c8023879004
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x772dd001d91574f43bab631efc169042153c83c4a7ad998a5acac19f17c35f0a0d41e3b4fb77b949516cc1e700608182e60220e90e3b85e555cec584aec2ebc9	\\x48eacf681f3ce1a6ced97c1373793e5ca6798c33c6622b8675d318ac4982b221491c58e2f80a8802606002cce0acf99fa336351f9d9e78889b3f9ce05c976a0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2bd949102cbded0ac13af20e3e3ce0ff58f5a443b9dc30662b6a6f5bb2d765fba01de60a28440a8878a5539ce8d157adaa2b52142044f51491c88002e3ec10c1	\\xf8f9318dd5eb78a7096a56646dfedf265f0a2fa5020c0a1b1ec53f9ce9f178a825fe9b4d6baaecd466c55888f567716daaf2f8c1b32894868e98509bb4c12301
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x081ee271d99442b4b2d0510bab2a158d88c6184bddc89f34f2a160b630e0eead167d5ae0468ccc5c1f781f0b2e18e192c70a5078d948931dbe655c5bacb72ba4	\\xe0716ae203d2ae30e88b5bf39bf2487da50653e61a775e3dd51e1dc6ef04f2ea2bcf84a340b0031c667ee2b47e7e8a5eaf475ee98a1bcb2a2e31ac88b0fae10e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2942f4ecec958619bdb1213bbbad603c868b6724a6497e13aaa7c44656bf57fea5f6e66666f5872cd4486b1fbd3b2ddbda4bbd911e5adbeb1e1f964b0cc39cf7	\\xa7a73f5ea05ea173087d0b1c5f02401420725f1868c258bda1c189f5f243e84cd4258e657c506de0c67cd91575dd428ada77ab50e6ed933d6f490d6d9f1e2e0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xee7de8128209ceb85a0f1c8c66e493d1cd6496b1e4bfae00a143cb404d6bc9cf3be7b4c3e31affaafdc8bcc254444e5035b644be840cc5190d69899d9b893462	\\xd4b5aff143492c5a247490efb9b960916d6b3b9c6528dcdc3aa0e36cac889b4a7cdeaf3fbdd9f8379467418838ed84d5afa07baa6416a4e0ce7e2ea72cce2b0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9339f0fc65dc8faaf66f3c8a5d8845afbe6d3278656613059a6a817a84fd27a42fe6ff557aca6ec6015c83b491fcaf8ad76b5b76d107003aff4c67df82ee65be	\\xaa07f4c52ba5600e92f74ff1aed45cc2dcebcf2f4e34e6dc99f359fd9de4a284a0b84ef2dd8b8a6804acb634d7df4ff9bbc99e4923b34180294bcffe5f889501
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd3982bfd13af8f6a8a8251580716eb0fd8c83407fddd545bd67ac4d1153ff8bc847037d6775651842a35127ab7302e9955c57d238425f711f2dd2695304fb597	\\xcd91452f8bf23456dda89db9b6a145b583b79a1831769ddb50c3a36da06266394b435c73589f3b55f03d8db7df7418e065563a2d2c64303f01ed0be242193e07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x066f49ebb6ec213bb762b60a8216483da3cc3ba0b386db6d34538be1da01a2eda5348d80a14c89350b1e345178e5a39a1a46b5f46a5c6d90e9f43ad91d41bca5	\\x3045fb60ebd392196f951acd74fe5f7757a92e5fa41943264e58c815fa617de9f178aa83f63e1302a51d7eb6d4eb6392f648b57a738b45f08adebe439e776f0b
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x40748822c87a5f6d8c8debf25e88c6d1e6ccf4cd6051f4e933f0bd3b83f44fc17c40dbbb9306c122cacd5d8ca568336277d2a141511a4bf7a8cb7dce156a460d	\\x70549e6f51dee29b598929746224b3a7712719c89ce88d159265d89560a63d002033ba807cff3e08dd9b992a8766752db1f9334b6036c3622337cdf4ace0850e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x89b84f1825ab657540fefadcd6bbff672e30126edc857a32591e53a818fb3e5910429c3cb258071474195fd5764cc3d69314051a7cea8fb85e23d401c73813da	\\xaadf9923db0ff0dcadd58c8300bc45cbbf3d472e80647489a01f553cb8cdaddf6d707c73884aea47ecb4fb50de917c61e4153ae45a494ba96aab69e0a07c2a05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x647c6729700e44ef330dbbbd74653780f0265c4fccccaa4e866397e446cb85d93d64e5421e2590889badcf8ac23d4881b0df71bda77864f33b0c9ee897ca3859	\\x754d7f141dd3190c479ec94d5aaf026d095eb04c1ad0817c9a12d756a05d536ae6a61db707a3894f87e6723faf13d406f3ff5ac012490c29362802d2d165370e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8664a31b573d0021473e68081a2cb505cb379a230000ce6166a7850dea214300bc05a8f592c3d120bd15ccbce9e9b88a32eb68203b01f0c6c555bb049cef08c1	\\x26e4da2346af1ade626a9bb24f28ffdfc62d5b43512b8c29400aa1a298bd00c7ebee403b319e7fd2fd035135b0f03a7b0cee634896e534bd0c2faa386acbb809
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x46859c0e4a6493def54e4a34ac8535f7fa0bd1b2604cce8a133efa2bd3cac0bea9cc3a47d142722b9523c32ee0fef90e64b8e0ea009bcec07d65cc3ce7198788	\\xedbfc9e7a0e5445d6793dab52f6730917ce8b4973d79caa76243a78a60760f0e49b939afe48388ddc26d032906aec7b3d99bcd8e1c7f351bb159849d125ab305
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2ba78dd430d4900b6cecf4685393d5f8b74904e275f27017ca6d618c01b3ee99be9b6c19d19e52fff0fd3310dfb0ba208b93fcd491df1c31782129180ba72a86	\\x10f6673cf8068ec7b82f9dceeb480665c6225bbcd2303ffabaeb1ed0ecee120ca0f8a671155de23a116496ec40ca1775580a47d32f803fdac52706b6b9617f06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xcb2dd39755edcdb6358e3a89d79ea22e6dfa147abd54857676f9f393871fed1e2ec8810eaf07ecc427382f069da590a6fe4381dc6dd1174a74977c1bac51bf27	\\x9fa7da5689febfffacfde8dd1c70fb3a11c811658346333ea40be9724f2dae3b1617590b6b8d349d29222361f3e5b9ec2fb743ad21e88976f8c811e149fa0b09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xd30ddd62d8db10c2b7efecdedb607796c01c6b7ca0e1a18b8bae5a6a3a7e0d1b2815f21a98eb69eec4a6288c27ec53896887fceb8e02580a74b2a28ab2619847	\\xf9d996c5412e99f2dd7835d76f04e9fe80b8436c19e909893e392ab21d37f5ae559326cd944a5b48499ff04b2a552d0a7c72eac661951a098b89168f86fc5909
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x16877fe489ec30cd9d9969ae4967d3ec277f5a1c1b6f8c5e058f5f614016197dd78d8f5fd65b98059b91e0aa459c54da0a3f6959dd870540c4008ae25f0c162f	\\x87af76ee98a9b1ba7aae3bc18af51b7881f8437bbc4c8734b0129fe28c07b4db4a8391698b894c539c95d4c93c4e5f76e58f6b369968545710a08ae6470e0304
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe10f831b59171f53e7236eb56ccc74d7a358483265b6486275252eb73c406ae610ea81e9218034abbb9ca59182a6d04b6bfef213330226f177608359ef19eb20	\\x09912ceab385a5e462936ccb71c49fe23d821d30ff0fec81ab25dc86296a0920dce99095cf270801d3ca143d4e101ded9ca434dca10b78db4e90a2b47bba6108
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2f73dc140344c7f9c6a9447b54e0eac56a002e3bdc63fc082b692af389011b2ec8f42923d67e88c65776cb31e93c2582bbc9252f9ebf0fcf8a0001319365c0ad	\\x5262c89245d16ac2fc192589ac9bc3515d3899774638f2886d2d7509006aa5419e817e3142b0156146bac87e77c473c9ba09db4c3086ae394f870a0ca8242d07
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf5146ea8136c0622b5cd93ec03eb9a8e303ff5a8da4e398505edb6bf35c61313d7d77c6bf82c54e74378b9f9d749356520b3f1bfbbb463034ce332a2122b12e7	\\x9b9beb257404fac4fc2a5377013c50d527d255a1d1cf3efb4c3640907962539f3c2ca27f190923f6a9cc2e27940e228eb8dcf23fbe3b82a0cd7a74dbedb22602
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf3b2e07e38a58688083a282cbafb95eea11fb4883345b09b87dab2869cb068ab95cdddbe8a6c7b0b60fcaf5a10c1ed4674849fd557ebc5b83fe07090d9efd4f1	\\x414cae89f5a368b57ee335f1e208837cf4e792474be0c41f669ddde2a42c37a0ca2c84b0b010980f50940cca4f68b50d4989afb05f0aca53c11868a4d70e2a0d
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x184eba31e34651a4a1452cf3c6db4c6cf9f6f01f892ebb744f4b7e31622e6460a6915d2b086cf28020edec1f0c7020c83f2abbe40d915c3ad4fe5da7984ee9f3	\\x80a35af7ffa8cf95b75810e49d63c9d76df3acb557d356ad8cf563b97191a668c434536fb3d9640f363c9e27efba6e38597e5d042fb6da8939568c2b6908d80a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x8f439e2d606622d7a983630c230c348c6f73403ad8194cd5e7f09d2839f9163442ca1ab91da0f571b44575bd0e9ed4f03a13e190f3fe36509b1b696dc8025354	\\x2a06d55550a6d07f32122b771df9cbf84bcf00b7ba4a20413506342513455ce12373865a2550eff06ab81e49cdaeaf9e7248654c29cc969fbb2d56f8f83ff907
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0147115f935001872222df5fab8bde5c9ee87caf46bd9583ae6ac92b69ebfa2106147ec569ce199c0a8332f3aafac63cc8d90141b1495cb728769379b0239fd5	\\x2afa38934752ea2bf2030f8cd219d5d44275b09dbb29bfba50a0c4719a99bd90c9e1df1786e0b9dc5c19128a495a16c3ada418119fdf1c9094d5fc29999bdc01
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x1c3c9b0bdecb3f689a879a73f419734c844b76d9ee4a11ad848b38be93b30c47cec9185305649f101bce9cbe432bc311dc4f80d495459e212e5b3211fdfd41d3	\\x08cafe8da7b1107fe1b325178458ab21c9695915378c7622910db66be112681f7b7f6c3ed4f84e82149937b7986afbd8be2e790ed95797d24a170eab71374e05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc25c1857d23e101434671ad8024239759938f32143c8dc09146a01b86422cbe8587a357c73bc840f625d378fc8bc67869078248e76165070fa2c2b733d024c5b	\\xb80223036dede7b50745b152338ae4f06a051242943cb1c4db4c93175fdad4ad16c6a73a9d5d137cf120d8b397953b09a334e5b53d96657b85072b6a2015160c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x39bc7d6fb867902898bc5ba76302b69b36ceb86bbec23d50620cf9393a37cc9fe88c60d870f745406259d0450cb983b84d940d28e62e17412a36342a12ca811d	\\xda8edb35e18e65e714d545062f9899c90b7d18dfcd07107a71509ed363fc3837d81e206b5647223853584a0708589a71b55469a4c324dd83bc77fcc428d70100
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2092ceda385c6d8d7ace61f832d0da425b6e8834ff3a05ae2f109f3f7ab1e7875c134e1b26e0275919c3ec48effc42003d48bb9919a8fdfb445b2d6fbb9ae47b	\\x6f670ca0e9a54130d828c631ccd5ea86fca26817f94ac8101e511606455d7773629fc2b1bce11eed7d6fe3ebb27660fe30ee2f32c96af2ece8693a6efab86302
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5b09630567ee746549f0c0f0bb3ae05a5da586945d834cb74a503a873f51094ea400c72b447fc1cdb4c96d84182e3af169dad2ca3be8633a772fe7174f55c90a	\\x3ff555ac518967c44447c456698446a145bb6c0a885a29a29f8e09e1159e4341d36fad276f7e0ca15a60de4c3b89ee4cf4d4bf3b2e48dca251af0d81e9f4db02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x408165d3aab8ff1a58efb222797f54b35f2dcb72d8c673f40ae09268be2e662f934a1680d19487f2b75dcf7c60786195a9d1a0f7c109f741e1256acbcaa8ae0d	\\xc6e2bc2ee30b13e231153660e026af10cf0963541f21ded75b40b6571a1d1b969704a00e69ecd19ff097d6fe300e2310b72c0221b7241f2341dff2393aa0f106
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9993543772be8740d9ec8e99d85b97a5e0db4d0b47d89a454f5c5a29c4b623115ba31d5016f87f57a120057cdbf87949fef2998f32dc23a2a7ba50e7969b3a49	\\x4f105c0ee7940d626775ae0acb96e298e804867cd0103be15455fc13beb4b93824bee40a48e8bb429d5d10afabbce32c5282f6b6f78a404f8c19b881a2515a0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0d6e99bc240fb84923d5ee5932ca24c1b4232947432ea10a9c47d7b08608ce72d21cd2adc75514a1161325b8be6c841838f4c34c7cdc9fa083747162d0ad6047	\\x8d3b2779e6e9e42f9e7c16add591de10340fbfde33e60fab27dd8ad659242b3866a9fb01008497f3548234982d280e21a9358cd17b71497f4f9da4183ce17f09
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x09717ee9c89fc654bf9bab176270a4b5686c97bfcf717fcd7f18afc9c78c15dc06d3cf0e9dc220b7ca004ebcb7e7887bfbf2e9a029bd7e5be1686fdbc102f0b7	\\x39a380f0a34610266e4a1eab845f8a78af786361039ee0c72e5174581218e2e1cb090f741bd280dd39796bdc87feb2772ada25a9b0922d45bb577d2d31096205
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe5e825e13610c07d8e6273a87334dda2211a9383f854a465a5cfee22f40893392d9ca383585a334cef1092ef87022c4ea3ad364a3bedc2f54926c1797e04a9cc	\\xaba9fb0edc2e00d4708be9675d3d05f551e05f4b4bce1d640966e4792d1988212afd23e899c8c9538500827f8845234bc823855782dae8fffc0a93c9d9755b05
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x28e6943817a1c69c9f439511899e39594f5de9dc69deb2300e01f9048a52e5e1aa3ad19c011742415efb755df439fb3b47ebd26f4937ca09e3a0bf59ff278511	\\x3ec7b4be4e5d0a77bffc4a96718a05256da7b2eee408f95f31828c33723eccfa4432e525dc0c06b283f30280508bc4fb0bd9b044f15e8e5774aab91b55fdff0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x386c618bb5768e3fa748f0e1519b23cf41fce0207ea81244deae8381a94bf7fe8224fba80832401f1beb4ff26b58955d9bce341bfa8bc97acfcd306df2c10b3e	\\xff96e0fa7f55552915ad27b124cb4c89f1cd6c5ecb9cb9fe0b53aaf52e0f9e2fa029c718e069e7378d1c47a8e12743702e6ff5956ebb743acd4098bcfcfc6009
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x0b85c7c0200ee709d23a5e6b323ecb01e7f3ef6c56e110ac19164d15cfdf12019d045c1e11ad06037b9cb83853e44f794661a2dc6a6f55a1a03bcd8f9ac44678	\\xdb04df3800859f2a3dc4598f743cead0994271e51137c0588dbb841108b323b1b5c8a82da4c58103b35018db54fede1aebc5e23ae1507adcb3fe84a6062d660f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xb8c0ed874ad3c4dce7028925a4d6a4c8f4fc04d9edd800f96dbc234392225e150d367a10c2e5ea8b98d6d37e70088ce12f0696da678f06fc4981f2ee4b153334	\\x14b755e778abc120202463d7db7d361228f436ebd46afabace400face414c172440f85ff07f3f4e84abb6eb44f1c3c6cefc5908a9f6e48f1a978607e81779104
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe435042bfc269ee05d59d0422172770dcea6044ec8fb0549c84518e3efee61ca505881133df192b87cc81f28a41dd7ae5085d91ee0f2a386d2250bc13b633e06	\\x0d120e85f2e3a91979831092f5bcdb0dfdcedbb75c4a19e43d9c95c198c8923a7dbb8faa2ed2067f20c80577f1f1980464d12ee9528b48a54c820b3d80638205
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc52dc10352d578c5311604aa6d398b3cc3878a34afe2929bf1c8916910f0301ed5ce836825a13a14026e2d1deedaa9358f6a619c787701aff1384dacf0ff1323	\\x874eb219ff171086ca7de741a41e8934a6144bd375b7ee1ff9590d473140ad674c7902ef18b4b49f2e021c8f465aeaba5de7b0a5d0788445b5c6ff53e4e9d909
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xc107f3385913cae6a3f967a92babc80a42de6f9df20c782d7030d7f03de9667bc4c7eb9eba2c2cdebc3ceb2e79233be6d03945e42b41aea8a2ef1e6627dd6c32	\\x20cd7ab7200a296641cb2f0523bc530e2ae1b6d4abf21ab0a59bdac3afbddef7a0518b188bc2b45f744692f5a913557f736908601f7b2ae71d644b5376a76300
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x3cc623ff573efd163e229ec82149c40718b383bcb24dc3335c6be59e57718e164886a9031a62e0cc10887ffdcac78d52879153fc8520c041aa3c51d610c2fd9e	\\x968a0af60b8586be08c0617c3b7dbcd8a33df0ccfd3ad70a2f2f1526b933cbf5e3e09b731885c1dc04ed4fb89db45a9986e1bbae02ef2c6e81e541a4b03ded06
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x35f57bd5746cb1f69ccda8c8f43fa5bf09d7318170f0b72892db6cda96f77f6df3d87c526d31e030aee211bdf192ba14db92292cb6230590880733f474e7aab4	\\x3cb03c8006bd63f37fd9f0354970ed772b0380c0080fb0a31221f564d4e4f3bdd2e450fe2dc278df3d03f1ee6de4051818861a7a534e5efa974ea47564039109
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2553c62822d0e05f553b20b737876b355c1141fbe39fc9c37ec8ce93556b53590f69addd918f374a131fe701ea2b9cfd4d01981de207576afa8867c6bdc56577	\\x112d6d8f6881e97ab86e5b8a5a657186ca4c73842aea352bc0a6189e07b3b3aab9875e8b8bf521b533a38ba2dc87c2fb12e08b5dffd74c27d1172f91b2897f0c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x35362fce8a68f769a883fc511d9872807604b16014c0d933e985d94c00760402b936c15b6fb887a1a785caec9cb31202d2fc819135affb5e0bd655bf26e75c64	\\xe9420c1cfad118989902458c8ad166f6264469e17f991aa51b624bce3235cb14b6151198eaca89d32701d0a1593a23d920d9739921b50d46a85c8bb89b6a1b0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x299eb422f86f9c25a9e86459b7f798f00a6b002ba6d4e741844d4997420d3340065c8ff51836552946ca848ee6979ca6a4c593007142d85e97a7f3b03a5a95e2	\\xa9cf2676b92a0172838fac107987f0de21ddadb9c719848a43c17e6ca07187efc822a4f6b6d1fef6bd43d2c414cbda9127d7310482448f2269916af583d2d20e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9bd0d17850678a9d204afe195c35f3835de220ea01107559fff7969b38efd6d32f089830db37dba55d0127198d699e9055578b36adc57c37af6e02f41f67a86f	\\x7349e70aa5d1315686bc6661d8947c24a523d224fc341a78bc92c345e7d0ee734fd3c77ba607bcf9a565b9d59a3183c49d44eead142c81619488c878b1bdf00f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x2642acd3c4ddaff9112cc05a624b6811123396e6782b70b116acda5a0c5528ac13ae1c203a7cfcb538a3a78501aa7c1e1ef28e436f13b5044e25e256c4cb5aed	\\x67c81a6554cb2d5e9685aa8eac3e127cac43245bff431f5f32fd0be0689868fc5aab26a8cf8df86b5efeba27db7664d984450c66aa9ac3888340b56c59964308
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9d6be0ab2e176e1c2b9023908f1d8c4e9e82cae7805a5e0d7660727e796ec334e016f824b9ee19928f2090ce52bb723995b9c0b073e8c592e8f78cc6e2f41520	\\x151e5b8a3179a0e24e523fe9993270606e6bbf21761cf7e2e6b138b2d12c5bd3833fc66e5e5df65eb60b5f1b22fe08b88c07fe5a9f982aeceeaa0a5fda2a280a
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x9f191ea8a79eb3b91268da378ced532008f1d1413efa06db873f3131e5d52d9b274cf4589d6cdd544ec9aa1efcaf97e0ca9bc551910afe48a82f0d99faf36e13	\\x0eb3a63d89747f537dc3f30ef81ddff8d9c96aa5a69d3442cd43820452712ad272effd45c849cd6301fe1ed72403719e90059f542919a3cbb7f79e7169b14e02
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x5d8f1022fd9e4657fe7d941c77fad3504a288550a5fe8646894ae8b55e36226610bc534c322bd4c8c1863b0fc3f31fdbcfffcc191a2112ae6ff5ec3bf0ddc8c0	\\x5b50c0c8d32cc6161854478087fe413827d0983a8500f3f6e8feaa0a597a74760b0b1ebbcd687c9d201b5db62ee3fbb16074bd33966eccdfeff7d0e95a295905
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x6c06fc175f144908e9aa8724cc714af68089437cc9bcdc48cdfb7f119bfe34a0a979b8652a78af01e5058e5ec875795fb0ee5b2bca7156b8b362b87bc9d1a782	\\xbc4904542675c8251b8ee989eb4c454a7e1898959ffae509ee4894e70b0341b97c3e96f8e83d73a64247a3ffadb99321806a521e73471e66747ae59efef6f601
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xf6095197734a6da9164f604563635d2c6143ec60105e3a00d0808d676958cd519ce4cad96eacecd669fca591c385ac60337de4a967e51cb750c8e2609227fc0e	\\x216a2750d98dcb706fcfa333d6e3e3f6c4d1efc81c12b52100e5bd33665dee031b1b56d38fab29257393f5e0e1b0aa432e4c6a95672e802b11359b9a4f55fa08
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x254873474aedfe74739451e371cfef26bb6870c829f90aa8e8c2a1d48417fad7974ca42b4b79b2db95d55c0e7989491d71fb47c55f88d131f101ad1cdd553642	\\x3ffa3d7562a24ba2df1b6714c1d030122875be1ba017967531e4fdb5020a3db3da3aaef43debda6df04c96a9b09ee4643959af8a90e77590e7e421ec3e61c20c
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xe1e484d0398119b31d4d6d36e4ca560515edc546cfa6aaf62f56544325cb5edb31ba19adfdbc1f066d10317c94d634644d187dfca488c6e13e261f013e18cbf8	\\xba84524c2c976db23373d8ce5c24cd6426c069aadf40c2f355b30fb8ed9c0121782d3bf09de70d8ab058f2a0863b24079661af1ef6b5e310d221f5873f65160f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xae1ad05f94debf53dccd9c7ebb71f4457e39b40ce98cac09008d3ca326201e5d79de40099771932abc6116e2a245ce8dfef7b81755bbd84d43de699c8421996b	\\x655b15040603e8c794c88eba56db3cec89a6ef54631b60ac89346ec074b7377ec8a17e94e9453eb5db130290f122e66aba230f6833fafa4cb83f7c8b63443009
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\xa494cb927c16c121809c438b10772527ab934f5b5c13a1868f7dc38949255480dbb94c5f99efd18eb6a7dce033da3ba3570210c1aaef53f6b12793fa4c664053	\\x26ef24b18b63d45dec7f6a5d68c55f670fbeec4290edc507359f914fbbd83357be0489a7b8c62518501a459d699320c3114322d9e8308a9554af893bc7614300
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x617766eb95ee04b440d4550a61c41fdf1b64f8a4ba007fa635f2b55887514dce569f0d152aa4db4ab48998d028099d5656509c30e022ef7d69b8ca276c73ede7	\\xa0e9299f86599ba6226d69dec0b06fa6f58eb443fb529c0e38ffbe57e680eb56f9eb8cbbdf025d87b2f5a74bf667c85adeaaa50e8666402470168b8eb5575b0e
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x52e8fde29948056f75f35b670f4183036121fc7c6e061dd1b3f87c2af0b6f9ecfda08694434a73d3fe867ceb30d8e65378e82a017cfeb77c945f0b9f5c9e0c56	\\x948124233db23272e716713cf44609a50bc036a6976f9d83af7dd4fbcbe43cc460afaf294ad53b8f7bfabd67e122a88007f60d190c0f6e4b9cdfd418220e5609
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x4db961742e8b03b19a069d16f4eded98506cec4577454b41d98b1240d68bb6aeb2d2b563a80541f3fd6daa1b4d4ee1ea7b920fccfa74b528fe06d52a4106f4fb	\\xa027c25c549daf1fcd3594b4e6ab87642d71fc0c0d257b1656226807c3fb1a3f7cc866956205d58e85e050526acdba8b0b3b68b40518a671dcad08226882ae0f
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	\\x248cfc83253b8d98f48e5f0c5dc2c16c5231811a4ff6237b22159f25e6ad68411d6cf65731ff43d6b37133321b80da1092a27dd54d354a02ec60798092ba8e74	\\xce1acaa9a63f0a0538355d6a78e7f6f03bd857245d5380a8064792ce8a90350b7c4d73b943b615d0ea2705471e79b3a822d1ce7f0f258de3fedda86721596b0a
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
\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	1608204289000000	1615461889000000	1617881089000000	\\x833637d82665c26443015603beb980cd059020ff738d2ae3ffbb96242b797644	\\x738d8ce211bde306e71e8ad5cb15fc6cdb680160cca32edc16f616affbcb26470b4eef9d63b34abf08d76061f073b3b27cbc0c445449e602cabd4a8cb5f8fc0a
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	http://localhost:8081/
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

COPY public.auditors (auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
\\xe8207c4b5dad62ebbab091fb0eae735a43d2729441d0e11d11e604526d40939d	TESTKUDOS Auditor	http://localhost:8083/	t	1608204296000000
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
1	pbkdf2_sha256$216000$owxYaP4iuwV6$mISjypT7BH2HVeQErFROCsc48tSYZmTykSGX60K4ZeU=	\N	f	Bank				f	t	2020-12-17 12:24:50.001826+01
3	pbkdf2_sha256$216000$VA8vmUzcRk5c$9aw6yU0VReudJb+V5UydgZkBuRhAzzSDYTlrgx+NprM=	\N	f	Tor				f	t	2020-12-17 12:24:50.156801+01
4	pbkdf2_sha256$216000$837LBn5ZWBKE$zcRDgclnJe8VLlA1GU4J6aU6F62b0v0q8RmPLXIlpOI=	\N	f	GNUnet				f	t	2020-12-17 12:24:50.230899+01
5	pbkdf2_sha256$216000$FGYvEGax7xh1$PabzAieZ6av89L/ewg/C32FI8ZdvTs7H7qx7aCg0rRw=	\N	f	Taler				f	t	2020-12-17 12:24:50.310114+01
6	pbkdf2_sha256$216000$b2gdZDHywHFq$sb2fFp42A0FLLgQZrXdgUINKJ0DZBcJxpKyO53Po8d4=	\N	f	FSF				f	t	2020-12-17 12:24:50.384942+01
7	pbkdf2_sha256$216000$TFpbq3iHP5Pz$hyiHLkZIQwyzgvF4LB6WUUGATM3/yvMqGYh1r9oeNvE=	\N	f	Tutorial				f	t	2020-12-17 12:24:50.459303+01
8	pbkdf2_sha256$216000$Y70Bz869nuL6$AbJL8uJyT4RKR5uZkrT+nJqz78LkArIoBDXPXDDPJiM=	\N	f	Survey				f	t	2020-12-17 12:24:50.531849+01
9	pbkdf2_sha256$216000$wczwCZrZzduR$KuRL2/iksxW/lzB0vHfyJo60IDXVrAQR5xNxJd0Lnbc=	\N	f	42				f	t	2020-12-17 12:24:50.977897+01
10	pbkdf2_sha256$216000$EUvucHlRsspg$3IZlrkVzoWJOaf2Kj0Ad4zKNK0khbM36+XAmi6vZ83s=	\N	f	43				f	t	2020-12-17 12:24:51.440906+01
2	pbkdf2_sha256$216000$BOLeIVl2Qcxi$qd0WtRsCNRYa+QJ0E2e6uMoiCfNJPiiEb3pwDLwoYh4=	\N	f	Exchange				f	t	2020-12-17 12:24:50.083175+01
11	pbkdf2_sha256$216000$xK5J1A8R7IqB$SBzVtta/E4Qbr6Rz5PHoSpGUiIJcgYqFed+O+cbdU48=	\N	f	testuser-cJvNv0WN				f	t	2020-12-17 12:24:59.757568+01
12	pbkdf2_sha256$216000$uHPcwxn7pNfP$BoXm5pD/ZCd07OhBve8fsTzQz0A7e89E5CCuryk9nlE=	\N	f	testuser-jTzPUzRz				f	t	2020-12-17 12:25:07.640584+01
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
\\x020839f05b28d18929c53099902f9704836a3d3ff09a4caee62b1478cd4af868d5f517b3dde4d55343fe31b57a6780853abc2b03345a0e97b3c0f5cc28d1ca0c	\\x00800003c90cefbb7f3dc79d4344603fb92704df5d8db2e78b9f5779d9652730b1789bc7e332f30cedae491b3d607d8e38f571f4b1532e03556f93da4d5d2e6de95307826f0c20bbb8f82da519e5cdfe8254555a1c3cff056058555f26f8478debd1650a5760c38d8915643e6526d79b3f3dfeb4fa9970bdd6bbb44a3611dcf14a4dc4c3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x94483fba91c47ca82b019bfbdd81c455232f5a29d1d2f55daf424baf6a8dd2a215f0a969c8c4440ea5546518fe2c044e0f15526f72c8499d32e80418b4ded40e	1611226789000000	1611831589000000	1674903589000000	1769511589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x03f83e89e1209c25da730db29519c2c65e0b0f08ecd43dd05cde135be1c2be9192510f7ff80dc1aac793b35135da85328d2b803705ec1c9b4621942aef8ed835	\\x00800003c1d6c6598e9e804afe24c94440ca38c2abb24a346b63a3ae06fa22713cbcd8b23e39969276c2386ca66d075e1799e7538f9a28c1a2ebd3332b6ccfae2837bfde51e68a9b8b30fa489da9c11ec200f3269d3ffcaa9d507e9507b997df20b43b4c4ad7c138a62aa57ec1978445f474b2da0acc283c8358ca3c4949148e7eb09de3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf12a0e9d4f83b9a53623425db29ad0751716dfc7f58ef3c4004a3b59bc0cbe311a4ffc7cf24763bf06df949dba2fddb698b0be6dfa26645bbbcfdc7091612701	1637220289000000	1637825089000000	1700897089000000	1795505089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0690b296d9f0bbfc6abc9942032e8e2ee63d626c9ad6f0b56a75ce639e411b3667a9cddca63d409e84e52bcd195a384087c1c38abbe489dddadc673362ccdf68	\\x00800003b82cde070c896c4e7cbe682f05bb878f7db354484f119187adc62df56740ebe4ce078693b4aa31c6b2b93fe2cfaa575a39d32f1211d4e477bf9e9c618a5bf1ccd17d72a8a1b5dd7d88af65f6bc640ce01277158ef75b430ee4d549c528f8417f5f6cde34e153d214f8fa9ac652ee03f78948457eb4539e4203b58aadc5dbd0b1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5b9344b53ea2f675dfc3000ed408373229418501bbe66a101d73842ad64ccb10e68c633906bf67372c2ebf4d6ca97a1f2f5cbf36624672eab28e97326be5b40e	1609413289000000	1610018089000000	1673090089000000	1767698089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ff889df4e102dc6f27659f4425211ce7ef50a907646e3eed2aeb30611e2de8aac853f7d3bb9b6ec4d63492e0f3e140cc4b7cc1e0c7f6198428909fa26964af4	\\x00800003aa4fb028ab680a713f6764254d2c4b6e1538362a67b90028f174efdb49582d8684d23f09248ccdb18789fbae7ddfdc0f94d1f99f582959107cce07b66c4e2536c449bfb5e41dac6029ca7ce161ecfe6f472d28430c57c1e5895b4606c6c4ed06956e165af7a74f779941f96ee68e1626eb9e74c2dc8f9538e896902e5aebca55010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5b5fee519f9f5026ad8ec7dfda4f839f017968abe955a56970dda19d6e9a071b8874ddd32691ceb848daa7ac32e2bb7aa5ad59e76fdddd3a3c90381d9452f20e	1634197789000000	1634802589000000	1697874589000000	1792482589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fe47e353703b0804f214a85d968dccb1535f4023e525d90ea062a250f14e5b1b1a2b09bce84255bab7889cb0f466e6ff1425b8aaa89537d71a20091a4339f4f	\\x00800003d29d5ba148d68e009ea9e20a8981eea71f550e359c60b2b9d0ac10a03c87a32946bc67d35bbf0c935e83ae4c77360ca92ec47f459f8272cb9a38728d226922dfc28e428f632cae4e2398363f3c91d1e49bd24b45736d51b170c5caee6412218c7de91574c0da68596c57b4bee5f7b4aed7d421dfc6bc4cbb6b1172d2ff919ee1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd81693cbe87448e68b289a6be147d776b32db99849cee69b0b9de94da145f7f02b0866488c98c6fec73d836eb165fa06c6d60d489f19f4a3a08c4a125a845500	1623316789000000	1623921589000000	1686993589000000	1781601589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x14e4d0de211b03aa9195ae7f2d1d1d35644e908ada3a2147d38c08fd470b74b8a1cfa3a167684414303782d58ae1d6f8cd0f0598512e898415d077d3b4c4dc51	\\x00800003b794f0d83293103ee02f9ce8de13c2f31624fb6be03309bb0d08a5f1305d7597d3bb508ff6ee2b67ade8ed1775f7243cad333467c51255ddc33747213b0b73069aa53f9601e8ea21d174e773e67b0744b078ee0e641e94f99cf64e23ef9852dcd2d958b29a2869862ad49260c32c1f120a5d719fcd085be39836dd7c8ee731fb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3d62ea2510eda38d14a44e3472e58657a12484f1614a64e53965b07563008d08a5063b42e0bff49556a8b49f30e9383b59361dd6f96cce92b1c9948c99b57a02	1631779789000000	1632384589000000	1695456589000000	1790064589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x15e0ad982e2d73b161c99e019be3b62cff84b2afe8b197b6f2cdfaae97e991575c3d3f2bc65589b3275465c33fbae428b92fdfaa0996143b50b60641023865db	\\x00800003ac93126ccaf3cd75e24dca30423629333a7144c49e4a5b14ee43e1e615838166d748b775a42d36c0a3cc682f5e01f9a8b8464f5984e73cb92d1e422285a4c6cb796c9c04d813e0210ef5c84d2987d901f4284204e967a068e12c0e7dea895d4314739e0e800c46a6508db0d2c1ef05b8ab81e963b2266edaba1c56c5f4d742dd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7da5e76059e63375810a049e347e3a08420ac99d408564d78978476405b4ead23dbf3b17f423e999a9d00dbbff9564b7921cd48be65f6e83db78406a51c2cf01	1616062789000000	1616667589000000	1679739589000000	1774347589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17dc4c1defc635fa35d65fdc17f2594ebec0370cc23e671ba6bdb24408a58aa47859ffced730879145d4f057ee9ef3d7df2473aa7a6cf5282214504d6ecef1c2	\\x00800003c5b2517c7e3a18fb0df499f388c571418a1e590b271e35fea711e389ca3cff8a31d18586cc9eccfe4e2bc4214a486883d41afed7bb17e3625880ac48a31fc3df111ba57802abb02a18bfa02946e421134bd7404656b1805e22ddd478072897fd1eb715b5e0c762367b8157d048d44e68994865e5509dd92256a7aeb87a87157b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x479b6f3763a2dbfeeb914f860b4b4deff5673736ab3f1647b0522aba04cabec20119257b16a21158c87901cce026dd746a357a994231f53406eedf0457b2160e	1626339289000000	1626944089000000	1690016089000000	1784624089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x189c92eda09600a07a500fde440bdb32fbb35a6d3ccd4daadb2991c7cd6b45b3d43ce97bf7f96be15fe88f67b1ae403084b0ae80f02595c394883eb8b911efb7	\\x00800003b831de2a53806326a921faf162d81a65a466ee8ee4c05c3c12b1881510bae29e9f43c23e9668e363c422eefaa371fb50ca0e30e3da799d31193356ea599539e29fffcb958c01c18481ef047bea373abda60f8bfebb766aea8d720ea04cd7e28040006b27fb29b93a6411641d2ba3b7875c2f493941babde1e58a415b56013d15010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x675fb24d28e7083320eac07e803359541b1bd72734329a9debf5e35b7d3c6e7b63e6b6c5b26fff0cb2eb2a0c2f53373ab414f8ef5476f8977701876169874d0d	1635406789000000	1636011589000000	1699083589000000	1793691589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1904739fa21838d24b809ea216211a90db9291677e037fd51cb0814e0532b5a3d64d796de6f4132877132f732bf7ddbe703e822333a7dff64b3f8117e8e6af3b	\\x00800003b8d14bd273a7b899bd2af62454d0bd59420523dc8483f6a36a65aab96605d632cf0888252f07696781a26b88c1969abb42f043c416f50d42dd94bf5ab26f2d8624aa2251876690c838742a3db3902fb1ad295603825531e072d627d82e19556334025942d23271964b8e5e2f541baa9c5c168d3ea2ebe42971cca4493361f0dd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5629338b92bb7c187759860be5994ee14a891bb380f351bdebfc061c39a9647e44c352a4e7d1b74cb5b93c7d3d584b72269edff9e2c6b2133de1834caedf780a	1614249289000000	1614854089000000	1677926089000000	1772534089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1c3c9b0bdecb3f689a879a73f419734c844b76d9ee4a11ad848b38be93b30c47cec9185305649f101bce9cbe432bc311dc4f80d495459e212e5b3211fdfd41d3	\\x00800003a60e4be97bd6dca5d27fc9409d4edec4b80a51bddcd3b79f612b21b38c104d3b79e75d31dd24f99c9fa3c339e057f30cd82ecdc074886ed90c4c98105181963e441135cc35d3bf1e2a6196bd39078a97e94aeb610f5648600fe328ed3713502f5000f72e054ea9983689aec52497e9e59d62c104ef0647e3c0ff1cb3c219224d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x19e5a6c1bc5bb461b548622e6fc30bf5240e0f83b8ad1f6e1dcd299698c18f34fa2d19bc03552c6a7d8e095219fc4e39261915f82dc4b6c4abb7dcbf122b5a06	1627548289000000	1628153089000000	1691225089000000	1785833089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1e10b6f918b7999557ee963f722baa31b183ebf35351a5b37e9710abe47f10cbb3645c3feef37c0cdeb2cd9e924a7b2f13b2a5efe560dd6e435cc0478231e209	\\x00800003bcf663d4acf6e57d19ef51e6312e1bcaeda8870ea30289014b06f11a1f9e9c57a639c2df1c926c75b3102279699c3025362dec83a36bc7b753610c375169a89a8bd87257ee4964afe4b94be1b3c59d236becdce290fdf3b0473d276ec7e935f8a57a0fe881fb3b31a8cb31af61c939e4fd01e691234e9f8edc497e28a6abd359010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x227a93d8a9870a46ba5519a654a495c66e36386f46cefcf653f7d339d3b2ae3ccae3469a76fa3b1956eb5270f969b6262a681a0a79b69b1afa8b7d852bd80908	1632384289000000	1632989089000000	1696061089000000	1790669089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2010280b843e37e1e786f4b199ce79848ed14c823378424b3b1c0df8f2b684d8ccf313750a5e480eb81bf286138030907f7590cdd3b31872d15ebdc5d0089ff0	\\x00800003d6c282cc2b91ef2be68dab014465a5ba73c942da81dcc3c94aa982d702c29af45646ac158ece94c17d801d6ef1d62dfc6a76cef81c1216f7d2104afc0f1d59bec0455c82a85796af7fdb3e0e00ab1a90a3cac255bc67930abd7c15e3c22c856728a328767531da6fcfb0e80181c501423f9275fdaed4a1756f2469f18be39b33010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x36ae056dc35508cfcca47908c5ef7d1cff8debfe24ad2cfe2289ba5fe6359111020758aed3bc0f5ae154a11e877d03c249721b21d2920c8f8de8a13d93a6a006	1624525789000000	1625130589000000	1688202589000000	1782810589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x23a0e06e9bfedc0c5994490d25149ff694cecdcf96e80e04c5475795826e5586fa99a904fdc577c620aae0daa341ff0f1d68a64bfc4e74c6383d1e07457a1448	\\x00800003c8a40a135e26f769144dcce904550253548b71bff1f9ecdd16653bd3af88d677ceb4c10e23c1f6cc37fe27362b4d5ddac6c2b03e8fa3a27b4f3729dd7904840bd9b16f06698536d42cc6e6df3443afc4fc47a03fbd700846576f79b7b9c7794f452d88a46b8cd516cfadfbfbe6deb55ac6264bd8c55c592c747baf9659095d0f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeb27d9daf06573a10493a64e185c17ede456e61f6265724227b13ab4cfffac45da116948e4fe78e2a3efb9835c9f5c98c975f80df01271a0f87c8e32a754440a	1635406789000000	1636011589000000	1699083589000000	1793691589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x248cfc83253b8d98f48e5f0c5dc2c16c5231811a4ff6237b22159f25e6ad68411d6cf65731ff43d6b37133321b80da1092a27dd54d354a02ec60798092ba8e74	\\x00800003a75e34d6e459d0128ff3ff3eb3734c9c00cd00cf7280b1a49e591a578e597d662ae4cb19df25128c3f8696402f1c891657c3728fc2d3dfd3a09ef10fd054041bb3ffab2c9d644a13737bfdef5fc050d7cbbe2375b51763bac65aa23ffca6843c15fd7a497eb4994cf5be7d7a13555ae0abedb00bb6b5b703485c859aa076e9c5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x439171f8a1a4b824b855069f859fb1b4ef470b97262c44c813590f443b6f4c618b91c9cf7e2bf37cbf917e032a195900be31f9a483aec7dea200663e9efa7d04	1638429289000000	1639034089000000	1702106089000000	1796714089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x244cd1eda9412aacc008767b84a710e4ea9c4ec3c97011cf732b44ca041c180d29c56dbc5a4640a36cd5387aff5b6582bffdfcbab5881a120e37940bf69e9a7a	\\x00800003c909f43ad5d3a338e66dab33433433c9716c3e6c291cf506ad60c5180f76f4bc07c64e1bf00eaf5fdeb26c5e358c4b86fd345c5d73009dbabc5a486cde5a20839e75ef456034dd74821bf029dbcb2ab5e692ed5debb9ea24fde188dec5107063ac518dd9874620672c1a6f1a7b349ce62915765330b4ab07dec18b9c4bf09ecf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6690c76eae74f2646bbee40bcd4717f465a12f347db90b34ebb2751233f14249f7563e5336f3fc6e537557048621e92b0da3a7faeede3394c5e6b1b04436710c	1623921289000000	1624526089000000	1687598089000000	1782206089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x25d8ca0aab36465727ca5000d053b5eab4a36c4a8562659af53334385bb8831df7363d71767bb658cba00c654d610385b684f784168d7be1002f6942cd2b487b	\\x00800003a9bf6c48e2cdfa1851bff8ec32f24f6dc4afc8e6b22ebfa7b11b7a8b7752357f7106f30b7a434c6975b1e0f8989b9683c7f9ea725b0de5e8d7a7200ae5efd740b116c3d599f3d13a08f61d64f9f5fcefd07d2ad680fa275a3165943d9ddac78b10051fb64daf9204aa41bd99a843eb6445b711148db6055e7fecf07a291a10b3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf3a231e4d75edb61e814409797c035fa5de563ab3da0661ea984b16b0ef735e57ffff084433a4f94e847cfe6216bd898e88ba276114a82ab6e636da4ef2ae401	1632384289000000	1632989089000000	1696061089000000	1790669089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x254873474aedfe74739451e371cfef26bb6870c829f90aa8e8c2a1d48417fad7974ca42b4b79b2db95d55c0e7989491d71fb47c55f88d131f101ad1cdd553642	\\x00800003c3f96894a1132622e309f0c41a41d8caf11ee9303ca0afc350a5300f2b084ed6ddcc07c9c2bff728383b423c7b0cf3e1b35383f2146e7933e74cf61a9b7bc1cb5769cebe7333b1000622a658814772efc8f1d3b5e6b9cdbd00d17723c8604745a0240eeb0649b96cf0e0b5ad3f0632e382752ddd2cc5b45188094fd33e32ad0f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x42d0d33bd29ba896231d0c60954dfc2ff0c8c6398307955b36dd9444328a39aa5409728a4ab97d28fbd57be1c8498faaf5def7cbe7e009bcd6b51ca1b9328404	1620898789000000	1621503589000000	1684575589000000	1779183589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x28749285c1935987f17ff0a3fab6261a09a37154ee4e1d0c10c5913ac4f2332f736aa0ff243f23bce9256cab74d64cb5cad61c1434c52437b73a6abdc792734a	\\x00800003d37b3c181a1164f982dec144f0f2667683e208b6a84b5ebccd83d568236efbcc86e3159a96a4089fc0abdf0fdb109408305039e6965e3ad82d3644942356425c0cd35775165f3623b20d0f6fe9b4f142e49104bf05ab9bcaabc63ab523d733b41e00fcd49f594dd135ce91e63e3f3808f6a1c3bb31681d0747f1190ec5f7c8c7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa800b5d54e74b1e300e999ac3ce44d41b249789e81487d903432b5532f3975539f09c167e75ba29d9c3ffd3c54c98ce08aea14d415f03fd296c7fb4c23e35f06	1613644789000000	1614249589000000	1677321589000000	1771929589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fdcf8ef3790f1bf38e3140850698c0755f8b2238ade880b705c39153feaac016c8101e00f9af73a68bb51273f42bae661d26ccd8a97649d13464e9c6ea2596f	\\x00800003a1a1640cb6f405c659443dede2d14a61669df2b64d9b4e8dfacf6da75dcc96ac062c63d3316b5023ee93f5319e1a9138c89c89d1fcdafb9df918734587d86e886a62d9180b8587733d792133654d3cd6ee353e132bc9fafd3ae5ae8c6338c70f3a1a9fd668805f149bb83c05711e4c29bce19a94b8021a4c2036e30eac4e5dd3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa394a2c6397c3896f346b4d7db38eb3bf2ab22f208439313857e1af0a2ca9437d3337fdadb78eec93a90475af64edbc437399473cd51bf933d3f98af118cb40d	1636011289000000	1636616089000000	1699688089000000	1794296089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3014fb627672c8b4a2649d3077b477b2b88d250336a81d69823b6f37ad20c9dececabe59423b59a498ad5c2170388760219b970c229c2b783066352ee4cdc3af	\\x00800003d939aec8ea92c91bd15a0d5841f8a8b2f1708e0be0891765da6ca637220786f58105d4b976e66a573ce9ea83c987ae905e3bb4bd0ebe503be3a0d399587d458570e096b4a73ddd60601dde4ce4cb03b4873ecf9d1cc3833eb91a9c482e8f33d7e673a54b972a10e438403ac6a82653f83ecb874ba535841ac048e9f2bfc968a3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3b535ddcc8038e1472c20ea06db1d886c2ca95059e687be36da3d5bfe3d3688bc4419594f76f462ff0471d85406a5aeca515f52410f9c49cde29f388764ae80b	1616667289000000	1617272089000000	1680344089000000	1774952089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3118b09b902aff3f203899466937fc0a008274f84a95fb1b7f3947a81de4b7fb56ec5a65ae8126f73abe750ef68b9a8e8de4df587daf8b5e63e0469c93ace19f	\\x00800003bbc76ba478c9265fdad10ae8c2da249dad8d485a82c2639a1ef62700ffdc6cc781c062dd4fbeb61e18637ab7f39ac0133ccaccab28f14a870f7d8eddfe48e2ffdaeeb3783f958446be86d10f48aebc6c7c2e52557c24d377004ec1b1f93cac23acf7293f1abf2e4a3734e2a686dc6a56b138f0d3d96b6723770db4b3c07a58db010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6b21ee2a11607500ecce501db4ec227712ae75fafd4e84b52aee6519c922d1766e5e4af48605460a746f035bb72237eb7c8d5418258ad6837a8d9c0a6f4bcc0e	1622712289000000	1623317089000000	1686389089000000	1780997089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x32d430a569ec8e99742b305679b2fe5f68c94035dc73d5daecf0a0ef6c92df2676fcdcda5415fcacaea4274367605a1fd81306c58d9fa4ef09ad822c3c45e8fa	\\x00800003ae076503ff4e07a94c75612adaef95c260713631833b14b07fcbf0d1f3ed477623705e85a4ade586bbb9bf197b27b92a378344b566ef65bb4b1496e38e10b74c860dc7242de39f4a9d2365959f977aa6e102dc43f0a6dceb73b117a557a48f7655062e2e776643321b0e488890f5d7f84bcb518e6e3ddd4c6337ef8f172b52f7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeb048d249b8fa4a006c072c11c9489b84752b0fd8eacf59f74886be4a91f5ab9e63086145985cce2e4da3a95513d2b6a0469c8ac9e273a7b3eecab5b7d515d08	1636011289000000	1636616089000000	1699688089000000	1794296089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32e42f06a8594f8f7607525587a31f1aec454fd3bd681352ea7a0e298cfb806c414c61f814433c087b6bcf360c6be3917528f4181984c9ad738973d98c7bbc47	\\x00800003c00bb4468c5441c20922b24fc7bb0a93a575a60fc7c152db45b1c0e2f1e90299353453546dd02daf310e2e2ee3ed2ded8723600136369c400e98d8d5122b7a3cadb0aabf9e6ca8ec26bc9ca937a9efae45690074861231d5cc57cb18526344f49a656ded904f36cbbb8c0c2439df06bb2599b5caa3653fdd276a8fc8edcbb117010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf3b226099161a1c01fae2177bc0ee678be0b4f7f6e2bb63c779ebfc3b3926a49e46b015161e9222de64db10ab0af753482f090d9f3483d088b8996e3b7672505	1629966289000000	1630571089000000	1693643089000000	1788251089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x35e8581484e35928e91b5c01dd0bcfea87535c9acf9ce66b34be8854f37e5edb6a6b15e541ff71d4551c6cbf69b8d42de9145d16c66605ea12c003f04f60a8e3	\\x00800003d9e866adcfd1063a34c3fd166f0154dfb62fd2eba465c147ea90732f5ef12638ac1e766b497a3d5aef445f78ce40686d156634f4da4807d7db203f9cfb8d6e8f8ed5f504b087359f344072dcacb3e94ca2fb97738fa515ad8055505c698802ebfc309e664cbfdaa9c1d78cbbdaf24dc9c21d32819b79743ea14e0c2f64d32ab9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa5bd83f9927f50bdc71b3c31fdb87f6c8488dfa7f290e3f5e04c2689a4b3394d3e587ece25715bf724925869f843c960899bc5fb04727d8e8e6a74cce23f6003	1618480789000000	1619085589000000	1682157589000000	1776765589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x386c618bb5768e3fa748f0e1519b23cf41fce0207ea81244deae8381a94bf7fe8224fba80832401f1beb4ff26b58955d9bce341bfa8bc97acfcd306df2c10b3e	\\x00800003c7e60632a81593e108de1b8086af418051e2b4e3de81d9c59a3e0382e6e6470ed41d256442032c4aac016d88bc4f65bd5692d890d47096610222c2103308493b4535842c1324c7f905bfe4cea50d2d05ffbe1373e1185d84705d24e1e952db8c5c4ca81bb3ed24c4b5579c3423180b7cc1c2b8df2d669bcdadf0291b8aa07f0b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5beae0111406d81cdeacd80d577a25cdf9f7352fd1e2e1a663bcd48ccea04c1bfb1a4cb332ee710addb406d96ed7a9cbb7aa973636a6b79f4aba4809928c300f	1637220289000000	1637825089000000	1700897089000000	1795505089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x39bc7d6fb867902898bc5ba76302b69b36ceb86bbec23d50620cf9393a37cc9fe88c60d870f745406259d0450cb983b84d940d28e62e17412a36342a12ca811d	\\x00800003c07e61defba63185c8942591f1b9f61ebefbfd77269b7af4926563640c0cb7c1582725824c11b7b2916e68ca99b682d3b7304bebefe7b392147fa51a49a442e3546bccf7b61726b1dca0634e6e9c597ae1071cbe9a21d151f2eb1d234d2c7ac422047ba0865695d8d5b8d4620c0d51a05721f2d318479cf2b720232d3bcb8f63010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8438ef2da3c6c92e0477cdced47580e1db8cff2c308cb7ff4be535bfe42d7e9484a3733af43695ec47270322e808156015a51a36e8af3fb3c74bc4629c577c07	1639638289000000	1640243089000000	1703315089000000	1797923089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d08260c07c3b9303b5fb847db1ed224ce3655d15c6784bbbb4d97f84704940b29aeeefff2ba525032775d83aea3f17452bd2ff5d9541a7d46afb1e0a0620070	\\x00800003b173cbbc47eddfaea3a6b956f61a7f2a7f3b1661234784f576d72d05df76475b15440cf37f30275c32d9e74204289cd8f3d14fa1f157c2340bfbfd560f84a229befbd02a54df65c4af580a2600a0f07bf1dc935a50228863988b56540160de942ca14bf45d0443563b5038f340be58a0c6b0cd4022f974bf90994c13275586a1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x963d3ac68a24d91714aa9dfc0dd8b97a776833ae8fddb618a4b721799cd271dda5ee1cc3d793508e8744e5a0658b1ad4a7f868f7c10134212e4b4b579ea52106	1610017789000000	1610622589000000	1673694589000000	1768302589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3e08ede3e8121306bd4be4a49ef413e53b0a7233bffc7795d4b21a0e38d200db7131de4fd0f67feb93fe55eba3536f48face8685bc3d74af80654b306afb07ca	\\x00800003a37b22fa11bd172681ca31b9de1d2fbab52210e58327002c8702640cdf767c4924f327f56a710b49fa6aa49077b220e3757d540829fd91fbfe024acd93923d668c04f107a242d39385ac0deb51396624ca94d26140a20851dd6412838f70c65d696fd08be0843a637d7e223259b498953ff80db549a26a86609f719d0d3290cf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5ed038869b14dbe69aecf81b9ba5cf3ee4b1f0723f6a121910cd7d2b321f98fc41c2f529341ff56338a3fd52678f41b7122ada045828ee8a50ad0d6c48b46902	1634802289000000	1635407089000000	1698479089000000	1793087089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x40748822c87a5f6d8c8debf25e88c6d1e6ccf4cd6051f4e933f0bd3b83f44fc17c40dbbb9306c122cacd5d8ca568336277d2a141511a4bf7a8cb7dce156a460d	\\x00800003c7a04221e23088e8969109822e60596f4bf9f585035e7c8192c49f13acb905f947fd10683d1009461bfcd8664f513ebec892e4a16d8e0ea51b1e18e00f312b1a9996cab095d28f2476b22697597c13e86315206fc940d24156b68689a61757ac4b9fa934c4293699ed0ef5195d69a565fe30fd76d85a730b3d49bc6668d8cc8d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2c257290d4d9a7a763f32cf4950faea7baf6f69662bcf37f176703b4ba57b774b0af866b2af82e8121aa71233bf8fb005ae90db16818a2165b7d49fafee5d905	1632988789000000	1633593589000000	1696665589000000	1791273589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48a4e6ca933a046a968f551f8302a21c23d4bbcf9c98c5d4a890fd5dfa741b4e2b75e4c1fefced781d5ac46209f39465eb4f657983dd79c470140aef05e6e7ca	\\x00800003b53624b7815e0ee9f69feb54a8531c85a679a335d291b2de82bcfafce6c69a4a266311a81fa967836369a3b2cad094f6e6d564328e48816307aa3487dad1d0ff08abb2298123fd18c3a67769e378552293058e4dc7ae652e555102203a5090739182671f9d01459a3fbbbb31081f991384cefad70e1573933207586ba1c4d3db010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x72c869711f42bcc8c5e6330df551e08e7cd120a91dd057639c5838eded377b02903aa2a0c2ae31dce987410057941272a55b6436cba4cba0569f738faaf1e902	1627548289000000	1628153089000000	1691225089000000	1785833089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x493079c2e2ca2a590ff23ce43c227436dbbd5011a56a46656188fd524efef0a7d7e3e65e541d9b30945cff09eb3e5656ca51465e36ca766200318e60407189dc	\\x00800003e188687b1d7f034255c13229aa96d7b381fde33f366ec6294262fdf928786aacbb630d56a15e585893bcf7182056e4a4d6a371a8e95db05dac55c7d1c149d9590c99aaea2031ca667c81045b92b026c4a5e5dcfc21b2c479a85e1607305f4251de0a020698c7efb1b1b5841c0e5c8a99797b435cc78e01bef79ed64ebcbfb447010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xff97feab5dffe861725faa12431a86be579f11d6945543056304d0713cd7550829e66ea351b89e741abd5c954e75414a3334591e634203d85294672ed00ae501	1633593289000000	1634198089000000	1697270089000000	1791878089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4a281b11da8503b1bd560e5938cabe1bbf869c2784ae074b96cb346bd08dc46ed77ae3cd07ba2a18c41d1e13ab177e879825e4377e95b8ecd45458928be41ddf	\\x00800003d1feb8215cddcfe4336179144f2a1bf94b02755e8063eb2a9e2722e635a5694d78acc80b113bfbc4da0fe43b20e89206db24b7b7e0ed69645036cdf32e8620f30be8342608da3aae32867ae4e2bce801d5390192bb76931a6f21cc2a35d53b173d84341359034a28f2d7578dec95a7164ddafc3a9865e7cbc0d3a0e66b4655b3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5efc216882dacc479ad739c6601c9bb442e215946c64706c15173ef8ddd3ec7a43c809d6b47023ad7bad54f3e66b5c9f8c62be0b469c3437972d9acd2d51e10b	1622107789000000	1622712589000000	1685784589000000	1780392589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4edcdc7fd093249f7be12f127808151cb14ecf5db488235135076189d230a2eb27ca3d83f4af16ef4f24aa18df25e0910072e904245c2ef26f3fb3a8d0b8a051	\\x00800003bde25074f10567b9c713bbf204f44f0f5c4c5fda8298c2d4af23991cad0f67fa4c86e42403c3161ce3f8c358600fb97fe8df741e41c55b67ee9b1f0250aa736e67c9c35b418d62c24d428ed926782f5764e508c7ef11b98bd0cd8057a101280ce6604ab11233a8d2b8a042ce9b14ac940f7d0d8629061935b55d11a255b5f403010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf2ffbaf384e4444e5362c67e3a5e2981cd7f854570a88a36d96d2952d3f6ea1764d43da895486910508c512e17a7569824d1cd9cd4565dcaab12189aa7713604	1614249289000000	1614854089000000	1677926089000000	1772534089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4e58c9d356be8982cac4d0abc893101fffd2db84dcb0484507c15ad0f954644c721341675a3b41cfd8807d35551333822107e3b853c3058bbf761dccf36a5617	\\x00800003b90b5e73d577f338831a7816d532a362f64351b3a6e03d2e96eb69bbfbd4e92285ef0161be1e90297fe81db6560f1e5ad30dbdaabbe74489bc722a1edc65be8fab033eb2dba43dd7cd8b4fd1a321e87c0dc4c8c2aa9b33f4bfd63e328abc8677a7d403311cbe556cc69d76309cfc503918e7a054ebfb576959176f440ce5561d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7bf1895f9e820f00df630e56f37f682318a804d20f6891b6088644aa73b9a365b249d3d0d15fae677b27bd907d64a6a90a0593fd5c161390a81de70de403070d	1610622289000000	1611227089000000	1674299089000000	1768907089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5228900f25941bc8aec60e011078672a910d44c77544b83bd7fba9731f57b07135ae172bbd6eda3b29ed4e47329e7976da469992518c1c4667657eb99634d23f	\\x00800003acef3ddcae038ea8cdef73d55a1187a95c8af0824b016f0f7b5e5bcb45aaf1fb9543512016fd835d30c3610ae52b442a466688dd560617110f7d7ee969b95c23b6150ee994d00f5f2b7588e6f40c1c1ca8ba867728632ab760d06268db2a7f3ee1851c913def6e15c95722f7fd9700aabf2460803fa4ae1648bb81edd1340233010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x03babe4bb31ad0b432053a6da55e26417787688494d33e98f9986d609626dc724126ad7b8b8e9eb61f6fddff874367f7b66d86d5b22c66a73462a7032af1a70a	1609413289000000	1610018089000000	1673090089000000	1767698089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x52e8fde29948056f75f35b670f4183036121fc7c6e061dd1b3f87c2af0b6f9ecfda08694434a73d3fe867ceb30d8e65378e82a017cfeb77c945f0b9f5c9e0c56	\\x00800003b3fa5c6be09d785fac2173510d092ca4c66fdff4e3453cd4921166b9fd629b27789347df00e9b7739d651b6328985085881fdb3543b7e8f2975b6a9d372453d7e0a84709c8c70e0f9348d29e6963f6d69f4cb097cf12aafa7dc78d5863de8c9c4a58d13c2c7dfedfaf7c5b2b14e166c501b20386ed2e07674bceaadfe9cff357010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2c53739e50e88177968854febef75412ca9ff0e24e7e48fea127b85c1a51acacd577c0c0e057d4b4abc477f00942d30e0fd24847866d18ebc7278800583de20e	1634802289000000	1635407089000000	1698479089000000	1793087089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5318174f188fbee4e205ca4968bc7271537b04595007bce1dbd52700ffba01da2b3474cd1818a50ec05c4ac7eecae436368f50d1ae8d343332e64d2f9baa0ccd	\\x00800003e47aa3f4cdbc1a96a1061a278f419b6a562286fa5100a81978da647a4f1c480931904bd4cc3078222383dbb1438a1f6c77e77e659c1c80362e3f447b9d50d25e943db99e66940c6d46693ad1825e204f6a45aa7ccd5061d219073b95c39eeddc732cb17ade4299d4035b784306191ce23cae0480b454bd58dfa8bbff149a47d9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf20c01c095bf85eee592e431c46e1347634a3fda5c316ee24fa87610e1a41e9e9852d3ccadb3174871d117e8e7893709e062ec2d12fa598c3ef44ae334fe7109	1634197789000000	1634802589000000	1697874589000000	1792482589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x540cee979335b9fcfd3435c13f8891635c71056b257e516ff2d93195f1a74d77f079d9d4a8fbf1c1a6d456eced071eaf3bf4f5f126227ec0503153dd2d47ebdd	\\x00800003f69f7054b47344a6446887469b6298571cc64f77814e08545e815ab475496913da3da692bb3b5d8dc06c375318f41ee05e1080f7a651cdf7f6faf72ee14ad7ef215669130717699f82e7fb832046f0029c05b67a8dfa4357e6664c38d76843cc949f8262cf3040e033cea0f249ad202f271626695ed46c8781f193850f59471d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x05a26cf38c40a3df8420b00b92abfe75dbfb5460abd11d4bb04cdfdb29da7285915284e1caa30396486e0b4d41c9170728841e186100140bfd1199ab7b335c0f	1628152789000000	1628757589000000	1691829589000000	1786437589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5538058a9604e94b2f32e0af7a0c1cbef6483bfaf82e739a5594721ec694ffc361dd26c1af0f3e70db54cfc7738d1a3029fdf92e403e74af38aea6b81fdcf90d	\\x00800003afc7937ac88d1bcc4401befb9296633aab28f789477a9ebdbafb29ed84687d376d14d0c3bcc856b669ccda2068340c0596943705253c67be7d388ac8a01143bec05a28e8b7ccd9701cc51bb48cd758b13f4b4a95da4141623934ab0980c1cb4ed96400e328252ec4689db548ba21806728bd952dafbc37c01171dbfd92f89f29010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x470fc4d8e63bcf43b433258cc3974a4b39c4bb179adcd36fe7ce47e56b3ad92d68d77926cee94ac7d10e64003ba7dcf18d60c659886dad3a179aaa964b3ccc01	1616062789000000	1616667589000000	1679739589000000	1774347589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5a18fa2e015d86912555d3de84669c0e1f1e37dc6fcb6078ff37cc08c70f7f836cd703c8398f97d1d8f310f07a6da5b3e3ac7b0e6af7998c59c3c49b7259b0cc	\\x00800003b4bbf023da1b14126e81689ea624d7768a8ec0e73f99e74348a200beb569b5b948c89a658e5ede735f29e3e1d1f4ccf720548d6ebaef485b5bae8c201a99deaeda58519c2ac9a88be002fca2c270d05d05dc651ff09e4a02145b991f19e51735c79ac63044754f5a4a0e9135503ddba01b19be5ed373e1095466d4c24edda42d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6953391075cb94095884396d2f8bf6e83cabae96cd6d5ffbf287a485c1ae81e04d3bd3b1d71431594d686e4fd9e1da56131b6fbec5b14f7f57c54ac896c17e09	1636615789000000	1637220589000000	1700292589000000	1794900589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e7005299cd36af19b54abf1e4c070e94596dd1261ee63d489b07e6a732b092046f6c8e1ce928da4f1b8a654796102fbcdaf6ceaa47d0e06cec8de77d3ac49f0	\\x00800003968ca4e260dd8b5c09504b1623aed2af6d57708bae89370ff94e3856f4388774d92c9673ce009a119444fb02e995dc3390c25615d5758757d03929c7eca1b95c450eee539a24fb88a2b12c28cc7e8b2339e1bd4a2a4a92db2937ed1a86b6820002cbda2c26c3087099a1991e8ef49fa3860e09b65ca10ddf578a50e902643bdf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xadd8b3e45eea6a33b62c7919cb2efa14e4f145bab63626176068676a0602f1e506c25c6378809a3cacc2147876eb437e6dfdb0e02943bf15272676cf05741b01	1629361789000000	1629966589000000	1693038589000000	1787646589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x61d8b2fad2e49c33155e426bd2e09898ff117c785c00f91bfaac362c288a5fe79db0505252fa846273d725c4682c04301bbf626f944babc04660a7de3c93cfa0	\\x00800003b68c7e27183f5875f8f44c04cfae8f1f35bcfb5d6e32a8e49a63572f23c69dc121ae67f7c50a08de9ec4b1720521ee57c6f9f358932ae898a72f1c1fc5570b6a40c68b20ea97b59d458790133af9c0f2eda79e7bcdbbd756f8b9e5fb32566e0a9b6f9861c381536777a2c2e56728314a787ed56411c6b1979bb80a8fa0bc4791010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7975eedd8e540f88344b60ae260e25ffcae53d16d97a35ce916caa6562ce3b7e6740a4238c6058112f416fa2588df30302afd8de02b572746bef8ed5bcb4200e	1633593289000000	1634198089000000	1697270089000000	1791878089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6370c636629288842b92a798a96194e2e568955f630c0c9bdb6a1034383994cdec4e78b81deeb6da7d894528ec87a8eee01339b8822559e7bceb9465ff1d1b94	\\x00800003bd2ada9c853a74e7cffb15a0308d1a26b8d15615816dc84c0e34d68f5a60151b6b35e276955b5789faf20c03e631457b83a5eebfca94d9b3cecece1577c698c10221be2de7e0967a02e0223a6edef4ee10f6d458ad41f33edd7bb6868b989cf441ed5fdfff1b7fc1dbca326d671b631718532af2fd403714e9fd92b1531cbf2d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x473e9b226fd8f8711359c8b93d232658253503a11d23a33292f533bcc625cf7504fa285a5ab867683a6e96736f8025f06d9632ed8485705b5298c606b34ea308	1619085289000000	1619690089000000	1682762089000000	1777370089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x647c6729700e44ef330dbbbd74653780f0265c4fccccaa4e866397e446cb85d93d64e5421e2590889badcf8ac23d4881b0df71bda77864f33b0c9ee897ca3859	\\x00800003e4ffa3037f8f5dee49d6a0219544229e3758d6d9bb7861b2c10b01020622af1a9066d2fa9863915ca204b2b7302d2dc39bb2ad196d3568cb4496a85aebb6101cf49751ebd4e8dc83173f9055dac2ce32135d8afdbebfbf45c79ab1893fe5f3659960ca87abc9d9d64be010f3e41806afd16dd776297fb3ec986ecc73ce998b9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0a20fb9be2fb8f6b8086ff35674972d9ae0fd21769999cfbf0a8e7ac51b1dbef751695bcb69d1a61095a7cd78bdc8703cbcd9a12693b420c5826e9fc91a47403	1610017789000000	1610622589000000	1673694589000000	1768302589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x65f451341c049aa6bd38bf581bde523502d4ff2c8517b45f89b188b549203a4fafc92002413a6441d53110c0e3a69151d709afb5b7f0a636eb40d743d89e1059	\\x00800003c5bdd3e872629cb0649abe5a263e20cbeb35f617027eeb999a882b4857ec1408840f1d7e7888a99c1f2fbd958429750329d6141cbfd6e0fee660b54c1067773e9cb9b015601f7011cc34ab7271123dbf13d950824d47e95690de968f5b7c64fbe191e806c2d6a8d87b2f5fb429458f99c8228d65f1844b562f5d84185148e9bb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa6e6e06198436949d6cb19c98769c039a0e2e880e30bad7662a04b263304a46c06d3335a55d46c7101e58a80c9b3394a98927b78b409c61fefa53aef559fcf0e	1631779789000000	1632384589000000	1695456589000000	1790064589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6504a7dd7756faf6754df08c5a8c00ae1608d202d5f2a5fda48bcd7f45dcd661a9973e1ea4901450619b058c891de607eb50f3c24b3479c3692d1e9522da581f	\\x00800003ac2a112463265ce8514d82881a746f689e7a92137f83eb49f87e6b5aaf1ab06f92180bbf820c392d21bc27d1d7d42232b9cb5bb356e7c3933dd9576fad5790ada0f93b95f9b26b431989a7de5e6409f34eb2f3cab761500c024c06ce0f344a4e4450031941231f7f4b694e914113523bd202c48cc22d1aa0297ad5437a748c51010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x163fed23eedcd850da92b34663f53747f8cabe4d594153aa17312079e2dff6a85e88972133f05204b577b9cc40c0e12f776876e6d8ce2c75216fb0066d00140a	1616667289000000	1617272089000000	1680344089000000	1774952089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x67b0861bc2ffb36039094397f55b43f193d2d73902fc4245af66a34d8d12f5f3a49211fffe78347976b5a0e4384d0f447d5205cd3f15452683885464724e948e	\\x00800003a66d58862e856a71b18f83a92c78af81c13e0d255d7ce3e16f1a8f9d1771adb7476b72d204ed82e5b417e7c5893f1dd4789da92e7c387e799e485482f38c103f2c75b6548308528e630253f6d9ffae1d24d8c62296655cdc6011e8841ffe866cc2c721dcedcefb24a5544a8c9231d8b7b9b56e75de1d764b06ecc93e9bc7d49f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xba95592ce8b8bc93a5fc25022539b95cdf8395fab247449a5dbd9ea7011a1de155b02d2cce4e1b982d8216f7af45195949683af125ee4b945590b7eccccb1d06	1613644789000000	1614249589000000	1677321589000000	1771929589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6ab8daa2125d18b1ec1c147b89f3284dc36572b7e7adc90f37aa64ffe94b253b26f0767bcbc903a5359db69937fbd4563a75f50cb64b34b2dc2c7fc1f7892f5a	\\x00800003f081f8e7c93d4f01ab0788d842023f70ce73d880d1440ea816ddd1c2cb2bead57b28c959539a0bf4c1d35b57254761a9c7dbdb956fd94af9464d460fd64c14fea7c20c5b9cd0b8278133538f697cbb1700403db7fd7d75bc374bf1527eddb8f5c8a284ad1eec521f198d2b57d8d57f6768d5560d802782e37ae627657ab178b5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x77877fe5de6c4c445e2dd981d3d24ffdc569f1fd531d10c431a58efd75760076327ebfe1e09162967830ba792607fce4ef2418ef37f183b65b7d88c5ab510207	1617876289000000	1618481089000000	1681553089000000	1776161089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70c4b20a8dc90496c55cddabb55945e249ecf3a4fde1703f413a1e492538299da5183308e35c1cd006f8ce3cfb418b56935458b3fbbfb00a0fbfcd548fa1984b	\\x00800003e8b1e0de48b125fc6510231f0d3dcbb54abe027423175fd132c01a3f9e33a45d6037641612801e1b12c2f6d5c68d1b09e3d6f32786b6dd310fccb94b499098d78734f3b7b24f017aa7fd4026ddf2b9335c78ee50e1f7ea6ef217c619ef325b1a9caf1a6e8621974d6d95d1607a90a6d1272e4f526200c8950434f10e7523556f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x99285cfa641b8f136ed880e4df4849ae0f61a98951988f78761b80c1344fe030606875e9af967f7df96c5010ffc4676d7ffc6c82e0f65c20875811ac37580d09	1631175289000000	1631780089000000	1694852089000000	1789460089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x70984e95dc16909111af2fde2e4873890dd77b1ff485ba0144c64f84bb924e59f955b599efd3eb38281e41a03c8b8e25b4301bbee059f9d8f282b38c0625a473	\\x00800003b076a2545ac6f834f36d29356389ce548a3acb28235e6c95d4d747e45c5387e851f4c6d95ec118a013d6ef5b05d58bcf95f7a18f7df436dd321431f2021263c7236634fdadac7897d29c4868ed9a0bcd79cd557ae3366d08a9a1173afae4e41cf692671abd35241f8eccf59fe08fb8e1b93d55d6bce1cdfe674ea15552dfe523010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc7f8fe8ad112792bb5d14f6f99b9361cbd63da77a12d9b37e5d590ec8bd39d9d7a3efd0fd3048eba6c83ac2fff75592fdd49a66db821d8ac1192de35d20ba603	1626339289000000	1626944089000000	1690016089000000	1784624089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x736024538e180b54ea554ff182b5a26224b351211e86dfa019e5acd2b0cfd3f37739ab092e11e292e2accfeddf148120cf06aa595dd0a054bc3bc7d0cc9e58ce	\\x00800003b7e211b8130592c5ecd32d4f8b0baaff80075205faafaba8d1db3b649477c06e79410dadbea01a45a88cb0014a0d9d27788e6af84cb2e6f36d2a7b2465ccd0ad5a157ea171d58670362ce51f7d10a89dc9383b9c66dc5d8f0d379a73184d0bf14b65c98a9648e1423d1526dac54b30484b1229172cd8947c5327142e8022c48f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc5cf400f079204168f0d041ea6647c279c19c97e34f095d02d8b8f98c991e166777fe9b4815e3ce6e0732f56bde5481c614ca157c75906c5ce6dda877bfd8e08	1616667289000000	1617272089000000	1680344089000000	1774952089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7470248addc7120d5ed17c34a5452876e61e04f4e4bcf318c9df292215ce93184cac02ad38f982e5c1a1e8880a599c903fd9cb83c2fa15a1c9ca0dded465ecf3	\\x00800003ef79b0551bf6bbc3ccc8218f406187eda574d59ce7d2c72a87f14d0c915d8b552766b543a354ba000f7c5d9d2e9119367429b73b0568c66a1ec0b25f82c4543d288f7a8c7e836e2d9b3c459aef563c6306aefe0141d61eaf3d8bc2c18c43d80fdb0cb9ce31386d922dd50848c7243ca4ae27c31369a1f905cb388120f80528e9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeec7fbf48d2203e7926d4af14e0b8ab5ef49b463bb3a6cf7b369fa514bf89fffdf50fcc4743661860bfc87e8b55e875e1efeabf18e675fe962f3204d0ae8af0a	1620898789000000	1621503589000000	1684575589000000	1779183589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x82305662a553455fea8abbef99d8b637cf44bf759162d20681cfc8cac2f6b9ef5ee5c72d2a06ad620b1fda270a8b35a93c6e4edd4cc5c4449364def69221bc03	\\x00800003cd47fb4efc748e670e65aa20b15cc034b19bdca022d2c22c24f72c11d237b3ae812fc94900641c4f69ec4d13d151dd55828f81a181a0aa728aafc19540d938863d7401a2f601cac2f425af54b71c9487b731b270083b4c94cd2e6818350b718380d4fb845b0b92e128c67d60675413b2784e5f427d29bbc23ee1d172ea1f3745010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7b4e414f9faeec41fd7013824ae4c2abc4996c9803fe3c0dd50fb26b43e44bbf547c0d22ba7405fd866788e9d100d56d6a4665750c75704076cb5062e11e840a	1608808789000000	1609413589000000	1672485589000000	1767093589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83f015a76a88b5bb794fcca87306cf558d2fdd042135ecc885b6e528b9acc2f0a7e58518ff097a9ec5e7c846ff068889e8556f716ff08884e4ebcadf5c1e727d	\\x00800003bd449fe87f525a58952c2ccad816f8884c87ba8bfebe1eacc39e382caf31ba3b41b204c61048fc451268a925dbcf61397025a71ef47dad1f72e4d8a5b347bd207ea76b6a0cc219073e22198b17306deffa581eb383b5efc0c2d9cfda27901ae6144bd628e31d4083d2bf94166453a70b1f001e958d8c0e942d694d0837ca321d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc93d3f18e8945b3c5e47d4b942937e443f330424d8bf5900f203d877d431f5e41f70fba9a7a0a761107753b37597adad931e9c6ecfbdfe122f002b8470b9da0d	1619085289000000	1619690089000000	1682762089000000	1777370089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83a883f698a90592d04dd7171feedf1502ebac059941f8edc76bb7ae1d270b7ed803d146359ee86e1baa6bd367be63838840e735c847c91eed61263b65d8341a	\\x00800003ce9e49e3f1ebe408e6c0c18174a7058003488571ff6f5d940056a6ce06131630a08dad2dcbf1034845c28c1f6fbba3e863080223384224aa85e1782daf6bcfcf56b81446e421e71b2d19dc0c54c208d6f4a8bd67be6eed19f4509ee5cf2f064888f2d068f05d17c15b0f378d91a3a248a8093687285a0f8b4af0e656f8e8f999010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x01558922264ef7ae5f7dce48103566157c307a4db8351951365cab7d038953ec679ee819912aa7d5c8eb48879ab14828ee4c9feb5c3d9b29dea1e10abc87d408	1628757289000000	1629362089000000	1692434089000000	1787042089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x83accabb4cea70f771f83c3db7fef99e2e093a404aa2902d700342b15c621c4a3dfc7f65a7f849be2df5d859aa4f7ecb40239a1466f2ced515d8b7215b59e4bc	\\x00800003ae2eef8b5decafd380d1dcd649c189acd6326e67dfbfc2cfbcc626c19ed34ff3bdc8683b3c0284fc29fa6e304e1f09a4b6e9ec618a2ecec7a1b4abe5c4b416b1afbf95de5d04fdb1cdbd03a0de4ea1b91e424fe4a7a4219be814e13d35fcea152397128a276f7529ebc90adab052583f850c9050f09e3aa22f599709e7f92c9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xca4d3adb6d43c5f78bd0812c5677654c62f9a00956896f656918c71828004fa9926e965f32f63c5c7708fd6751fdc1e0ff6e0b39a686df48b02ca866394f880b	1612435789000000	1613040589000000	1676112589000000	1770720589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x84ec3ab54448135df4150a81074c02a6dd207f31188b0cfdf54cc2c25fb3b37b3e7c49bec83289c52a7ef36e668acfedab2076e44b737d2196fdd3c6834da689	\\x00800003dbf255b8e802e89a16750a02ed01ea0db215c07657cae358f54f2bfbd967ce39851c075fa525126ee875503f99c6c166613bcfc2984e518ed099bb03c01a1b232a97bad1e83d43a6f8b4eb072ad1f7edd738b125b1131e75a4c68e24aa7d6350a3c7052db612a8e84e082018539c7f850a01ddd56a221a72b5de60693fdc2353010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6ca875b65dbc641b3ca343062569cdbc8112e80793e6b2432deaf300f0590ba3f6d27e1c30733738090d98ccd6ba0e8069c53567c2ad3443461642553e5f550e	1639033789000000	1639638589000000	1702710589000000	1797318589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85a48b3fa44d8ff6890c019cc2d8ebebce5d4fc43273dee5842eae7345e7df099ef127cd5555d51048b534d54f04ebf13c8e37faa74600d6ad496607ac52de4a	\\x00800003d108e627355efb3b49611aaed6235e23cf97bde9e02ff5275daa494554a30187b5056edea537c2c48cbfadbeeff37476d800c26382945964c8bf2bdc256f384d1c3d2e75e08bfdb5ba320b51d58921900a59a104561565f09e590a888e2249ddcfcf3abb79944b551e824aff753496739bfbde0a2106b48bcf226ddeea68c80f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x10fec2765df86241e22273af21f7f9064a0408e8e15e40dfdab2baf082d05519aa178d300b5b0dabd6c2c799bc7ddbf62932de721552471d49dc5b705c644c06	1624525789000000	1625130589000000	1688202589000000	1782810589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8664a31b573d0021473e68081a2cb505cb379a230000ce6166a7850dea214300bc05a8f592c3d120bd15ccbce9e9b88a32eb68203b01f0c6c555bb049cef08c1	\\x00800003c42103389f4ee20dbd77566a8cac177a9ca341167072efbf331001261c9474b95d4d3671ea94e6cb584a059dd393994a4c7a163a8ea4527f4effd5927877fbd5101498363fd922e47ef0f94197ef9b71d6b50b9d07376f4970c6c04c90624e4645afdade258ae683d6c93e281e04fbdb957094c893c375985ac1e77bef01bc51010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x834a671472d2890583d747c6704ad824aa3a1a25295c5f4377c3c9d1ed3ef4c9bf962c1092094f0b0172ef3736a9fe227908bbd0386fa01d0b6da2ff6a02ed09	1623921289000000	1624526089000000	1687598089000000	1782206089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x89b84f1825ab657540fefadcd6bbff672e30126edc857a32591e53a818fb3e5910429c3cb258071474195fd5764cc3d69314051a7cea8fb85e23d401c73813da	\\x00800003c09f1a00fecb90e926b09bdc49d0abc3e139b78d2b1ae707b98f120fd2dfe0ec109fcf2344e63948936399f6e3a786bcefda1a91138fbd8b34cf7b79cbbf3ec421e64cd4d427554a780d97660ed0d8c312c2bd5ab4463ab7a05eaa3a4941c66daa27d5508bc1a9f37b86b2c6af576a0f3630ffe119f4389687f4763e8a4a4f5d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf5304454abae232d3e90330342bd306c8c4afa5a6e381b446bcf17ef25c7789a86f65010ab53fc0f96069738f83caa33988009f7063d68777326348cff329400	1639638289000000	1640243089000000	1703315089000000	1797923089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8dd87293e8eace6275e94a099101730076057205db2e10ec6cb93f71dfd46096454a90d7685ec1c0205fdef75049c38d0f922c0fbec26b32efe38fb24c43e51e	\\x00800003bab6f1f44a02b5815f17706ae3fe60a210fc48ed76395c486dcd587be3396c73227646b971440c5a840026744084c64fd1ea104790c7468a12262db1c1e81146c4370115aa9ed49fd628eb0333f9b69bbcc04388f57e9e25c1cf3b667f74a8ab40cebadaa0139ff570aa8283a529017e079f81e2398881a8121415b79dc09fb1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5ff638346aabc45a759fbe80387fac45a9eac4ca63a34ad2f9f1748f32014f895af84d4c7bfa770299e7273e9f19cc53ca3e84302dfdd2daa9e7e1d625536e09	1608204289000000	1608809089000000	1671881089000000	1766489089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x91fc378ab80b0d864d2f8d1f5ecc3497b44cf65233888a022b3b9ce803db7e71505a31ef0cc06d64b5fb16cf8617209b384aecac90dfdc4d73cd9927f671e961	\\x00800003aacc44f2f1702c8a7b607ee5ce2383b4150e1783caa4cf7405501b5f220b161c8acc12329820bbc234d30e887bdbdf6b8e8d54a50e31d7ed803300b569ba188900e27a091e63893f99afd6d14a9024402c7a5e1c3182aa1947c23ef84493c1bc783201f2fe8efabab96721b74ed2beac417d3b980fc410570df2018823ea7889010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8bd8fa7da1da0180bfd1ba4ab4d506ddf6a73b37f1079772af61eccdd68ac16186882f5f1adacc346477eb3b6649cba8a292a2dbbd6241dd2609a05efc355004	1637824789000000	1638429589000000	1701501589000000	1796109589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x929ced0450d67e4b79ac6734ca62f5618d099fb3cb327c9f841c73e40e599d277e677f7a02f8a94cc4195e2859b03c097b2c885697b0cf5045629fe8edd6b543	\\x00800003c5af60b30833ed65521056f750895fe5202193813725add8a111b9cafaf4a43dbf4e794ca5890fb8efb25fca2f6f6dda4e39d112dd6023053c977f2ee85c34445fe02627df78e5c21a3f55bfc815f18748eb3054e7c55bfa70112bb5b2287a2b1f4791a02b55f5e1a07b8bd3fae8c70f911a485e5ba025af4f745e4cbfa0c09d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x29085d67afac4df78d0b64f516bf69a010391f537471a6dab92e3b21d3bf903808b7ca8eb3c2b9c03fd03bd59603346e2168c07086865cb9db2722a715efbc0c	1618480789000000	1619085589000000	1682157589000000	1776765589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9570c99a87c622515eecb6db91865fa6f95c77e34bfd5c5ed0078865986c1e652523b10ff82241dee8543763f96b33f9cbd9d7f792e9642723979c7a0bc2a214	\\x00800003b14bed13da630b99e92ca6f13d5b092291d31a0cd645dd6938a883afdf270d24d9dc114fccf1b1cc33068229f8e26cc653d537bfc93f782ae46e89f7900794edfea21e347608eee2f7bd0dc32e961f97cbb1c2c81b066ffd89e7129f480f840ec6c88c59522b1fd1bc92897796bce7f19fe73bbffc9893ea0c7a6c3f9e2593fd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1af58168a9246c6f579157070b35361e528ec5ee07148242ae16169471ceaac6fbb18e41c98ff7adc21f374a85c82a0d8e99b5be36cbb4f4d97bbe5bce62a301	1622107789000000	1622712589000000	1685784589000000	1780392589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x99bcb76b6e8409cdc26cea7aef6998f0785061129d4388d6b0b70a9346a3d9d492d6bf5c2869d631274cab809d9178aa54e7144f7baaef4ef5c4be541ba6b094	\\x00800003b21b206a5d39c8ee2c2666533b2350d69ac5083688fb18737399b635d64e29761a643bbf86d7d1f1a5c2a720453e133ce7d092e3c861ba9ec2e5279081f48a350288d8686783629d9820926a9e471e4d5c530231773d76db5744965683e089b1a44ec8c5335f8312feb1240e82bb35a7a546b2316c032d0754cfa89f2acb7195010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3ce015f9c0306f9ff95d43e5be5797609a8dfe876a720e3f95a73fd90b26ebf522ae73057c2a38dbfefe59ae43759703df58cf4c0c3dc3d9eb10e9652323980f	1622712289000000	1623317089000000	1686389089000000	1780997089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9bd0d17850678a9d204afe195c35f3835de220ea01107559fff7969b38efd6d32f089830db37dba55d0127198d699e9055578b36adc57c37af6e02f41f67a86f	\\x00800003a1b1d1ec780280e2649f04abca3c61d2409741c4200827e9b2e452588e9a12b4b47722bb912e50d942a39715cc8cbd09cc6c4546b6feca3eb42237056a8dce83f14e55883ec4b85c00550bd279c104b914046d55b2e24b09028e1bf4dac706d4abe5211324e0bfd3ad0cf0db8e83cae694164b8bcb626ffb05401dbc7be0123f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x19eabfef30f4c8d0af7618cda0adc4c7b646d87c9dd81c7ceb6dc7dcf7446b5afb3af5f3427ba93b70809a2eb09e6fcc9cb96f053043991eb1e3fe1c82d43406	1617876289000000	1618481089000000	1681553089000000	1776161089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ddce34a891db500aa9b8dc52eee6bd02ca3b66c8a562fcc4ca5685e1a9caa250b66a17b59e468f562e02f6b2ceacf1a7d9fdcf7447e72e32cb88a55738163d8	\\x00800003b26690906549aff5e9ceda7eaa1bcbd3fe69ea2d10d602783c0a864781cf291a5a723cc680cbcf7e49ea9e2fb6976e72da036a63c1a14d3a21f18193335153a14870502cf5af670657569813518d16c33e7506af6964aa720e20f2d3e5eb63afbb78dd5872ef2c75c96a230e1cbf13001cff0edb502b6ef995d535396c757095010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x015f1d77191b51c137e600b29f96365e0047072f048acf1d4a1b03c550e2ee34d5a97119c2a1cdbd6feffdcc173eef929ee98d685181110f3f9bfeb1e62ac60e	1616062789000000	1616667589000000	1679739589000000	1774347589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9d18907fbcc474a9d15d0791f0b222dca25f9c77de85639b31adeb5396f4e1e038f1733ef0c3a60db273fa346b479ea2b7b65fd2972d7f64bb35c2358fc2a9a2	\\x00800003b30bdd90550504f32b2eff479edbf1d45578d0e430eadd1222fbae3dc3089bf5b3c2571d57301e7c068baecb7b388af9a64018c76d06ba45eb0e4215e701c5e701713cabd68524072939d14b10d276f43aec7c0247a8f8bee1c6c623d3a6a614776a9cc0ff8afc6e5a51640d1f0f314e828e8027f7e6bae6dee305557b2658e5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe0a49396eb7bab913d406b3e89dfd258889870891a9e388187342aefb4b90db4b7f941a10501b8d843513477167028a755314c78b6ab133a817c906249ff5f04	1629361789000000	1629966589000000	1693038589000000	1787646589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9f100cf317f85d4c468df9df7d742c01f5719a208468308c74413c04bde2f17ba0cdd386c624ccae2a5c873ab132c9a8864a403a2011f40c9811a1cc38c52195	\\x00800003c22be752c22690095fdabd1a85b793e9412a08592bfc3655f603aad827beb62fe0617284ce604778e6ae97639628ca1488767050051cdb58b34007e9162420df60a2e42ff0cac7a13a9ed2c54a2efce304c557d7dcfb16937283d19c4bbb7baed22f0294ce4b153127ea13c3ac632a65bc70ed97316e0559d11bcbce794166b7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa3e55ca382aed4168bc7cb4a7fbab30b2b698b4cf7f7ec69f193f09c315ea3b40ef631d4677c0738d71fcf66b33c9d34682e3dbec4dc9144fbcbc06fb8b8a809	1636615789000000	1637220589000000	1700292589000000	1794900589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa094662cc51665334d705a3548030d0770af6b0a21e720947e621273db207f64bb2d788fea339c3a14f222679a8957d3f0da36a96cdfb3929cc21573bf977fdd	\\x00800003de06863bff96141de2f89124edb480a3aaaabbf38f886e8436788dfdab011cc1602e37084ea57327bb1aec4db142596f621c336fc57ab543da401fbf6eea2181ea88709a270eebcf55a0b7d715a055ba516ae03843b910dee171f22a1c317ef9019ac899f426a18112fc4588e58ad209135650cf58ccaa6ecd21dbf624ccba0f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9e27972695da64836309f2d20a279c816415ca7b14ecda3924f814c0d36e27feba10c4b170f659c808a31c2a6568eed74776983d7cd97bf01e3eddd5c31cd60c	1615458289000000	1616063089000000	1679135089000000	1773743089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa494cb927c16c121809c438b10772527ab934f5b5c13a1868f7dc38949255480dbb94c5f99efd18eb6a7dce033da3ba3570210c1aaef53f6b12793fa4c664053	\\x00800003ae74f94863f979fd52c69fdb561ca672d6315d264ca13fe46b3f9fd38f4534678d3e16c1d86ac7e5487f8cfec55407d4c8217399b145bcac3321cc0379f5663558790c14f971b25998e0f835964667d336e0bca8f0cc2139ccd6af823aa0b9e20d0e23e144b0986ff900f6df3725b731b51bab1fa0055fbad3e5fadddb8bb0ab010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd3c7c784bf0470179e88b7bff0a05dfd1b15e1a51a36030a9bcd6bcd66440b569090b5d23659cc00528d29149b822e2fdac59dc7e8a48098f877c1e1097f2d02	1629361789000000	1629966589000000	1693038589000000	1787646589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa404de1056071832f505c36292216558221f2780967df3fb21d5350e6acab283b1dbf41b846089d91c5217508a4ab30f182459702afdaaecfb97900cf0c58935	\\x00800003abaa37795a50d8ff5ed400eb774feac220016e131f63d0b14e07b9d66d35c8c165d6d7b4af74aab7ef046d48cc60cd09d89ed270e167b84f74906c41ff9dd2111e82dacefc92179de468e9e1b3691db3525a851ebef030c49cfe0737f1198edd11029b65a72b6ca1be4a798f9611edc807ddce7067bfb0eb3da2554cb1a67c75010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2d03dce4f4a3f81de6eee5c59f0df176d966fb6abcea112cb2d4039c6d77dbfc46d685cd36161da3dcbb9b8089a276935a0cebf0f30de1577d210ca4145ab507	1608204289000000	1608809089000000	1671881089000000	1766489089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa53419859ea42599780e17c9731e846d9cda34100cb70b443e355d66ef065cc584eef4d80e8053d10061f2b1cde4c1b5980b7d4446519d37595012407ed371a0	\\x00800003a1d0e07ae850667b77127cc042cbdb90ccc0923b03e6efd85def2e488dd748ed9914e784f90565378df987b7c61e5c5841c5c9edc17578b7332159d0348dd8d50e8483de2e24d9d6e229ab35d9a2ea04d0dc668f3dcc44771766ef861a8656d13736196fc013f7bd0f0b8de62469e3ec33909b10a0f1a8abe5ea94662cd4a87b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc98fba4828c2f79f5399c7144cbebdebf35b7ec8b83fbb7eec31ad46a580d2e1b9b019b541f5175d63400264b66fba33e965f522d72bce15c75e8365729a6105	1623921289000000	1624526089000000	1687598089000000	1782206089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xacb471ea890e35814b607e3b47684b9f8b06b45b09f1535dcc45bf4709c61cbccb81dc040ec4caab0fd26d73b1ffbbc58ae2b21fee8dc94546ad9947beb8400a	\\x00800003f56ed74a344a0abc2e422b1a40ed020aec789bcb0d14ae3f92691d9f1db28275da569f501303808b3a15a0ecb592bcc615044555b1f5a12e7f57e7cc40367e2e8426fbc37554e69a085303048091e1497a890c6791919ab573ed261a81217881528a16d08fa335c11870753a205d6a2ac319e1a7a4122f4e69e0cbe71165896b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe0854da7db19ff0a5a15cf032514adbca7db702b52c32d59d86932f39e70cdba4f13f4ea5a575b6838392bc99478c92eea4d2e41d0e7e2abd7b5ce0c7767db08	1619085289000000	1619690089000000	1682762089000000	1777370089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf74992802aa635f29b8cbbf22495f1bffcba58e7eb508b4e211a43c54dd888bf468fc31bbb933b73b1fedd2c435d7986981564fff31e3b59b73dbe98d88a83d	\\x00800003e513b3a70a2d3a48d7187e019538bdd07a3602a07efe97da384747c1ff71b329985f2047c1708164626c05163c3d20c3f50ac1c3ea3ae578ebe12aa988ebfbefd57a020c517aaa80432ce993fa70a796e106fedc385315720f9d0bc42c47c774211f4d7790434f9273ac185b8658451e0881c886c7b99ac3a96bf86e220e2509010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe895a660bbdbefe4acb45c99a8639a4b33d5cccfd852d2f4795a28db4d8569a537b2c17dcf49310a2003e30b9d53e6caea80bb929980090a5189485db452530a	1626339289000000	1626944089000000	1690016089000000	1784624089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb7c42e96b37fca9abd905a5089d4c1d3a9c3e8bd9584ecf41531302a333839db91d2bcb3e36d2707716a979b709aa80b7f556763b642d811fa593bcd687ea222	\\x00800003c08a2d98ab05923f5236d17ee2508a07b841bb160cf140abd5c8cc4701a1036f858c90beedf0c69995a9f8adee346bd4e1ad7c97ec70a904239515c5e6bb9703ecf6ceb566f63428a0c59044028bc2b425e968063974632b3d88810119c87fd40c6478dcba7c84eaefedb5544dd03c9fcc7eaab730bb3fd22acbb6cc94d5baf7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5978f085a7ac08471ffac0a6d91a00eddce76d384f365d537eb9dca7c61c4e46c92b8295dcab687fe0a889a83b4673bd5f53216bae6e70ea2fe9ece72969d205	1624525789000000	1625130589000000	1688202589000000	1782810589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb8c0ed874ad3c4dce7028925a4d6a4c8f4fc04d9edd800f96dbc234392225e150d367a10c2e5ea8b98d6d37e70088ce12f0696da678f06fc4981f2ee4b153334	\\x00800003cef9cf4d1ea3e3997ec2b8ba9b1651e5c7e118f8ad783f25e9d9c003bcbc494ac4286a67c0862381cc6916abc2f4ab2ca887361f7f2a0855bb43955e992158f0d04d843e0ef0f4d7b6234ffc3c6c27bbd2b33fb6810a95cecbc298c036c1f96e6991bcfb19f21f27f3b29e89f8f742d30c028a24f26d3dfa8f5f2a6afbc2128b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9f2276305120ce59aa499f0692db2b976ffb7d332ccf589c42aee4c3db77792615deec8bdc047953dd0d85707878847f7343cf83a45c8e06dc9c634a2ab3c20c	1639033789000000	1639638589000000	1702710589000000	1797318589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb810b91af3da1a6e94616facf9fdacafe0d5e1fa42832cf0732a864a08e61c2e601f394965129c62be6c8e1b1d14203e05f288a4ab3f4aa27821a8f602c52427	\\x008000039cea845702bec0d6f76dbf8fac5a72fd363cc8e5477d804f0581343d44dff0cdeff2665b9f4de7221b803bfe1f871c60ef76abc5af854a6caf3d7e50c05d75fb058761810b4f4506c1e63ab70fcb18f0a7c2c69a8a246dbdeb391a77c8d81ae6778960a825f7bcb2ebd33e8ef47cc711c1f7b4205d62a105d19faa4c8d1184af010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9938bd31876bcb305d5d064ec938a8a79957a2abb16e9ff523f1485c53ed9ff25aeea38806084223dfe79703c9e67a700a48e1494e7cea05245faf5ac0f17c0d	1639638289000000	1640243089000000	1703315089000000	1797923089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfeca0518c2d0c91c7f26870b7e5c27536420e4f8d1dfb29a186253f493219d6a6510bb470f458f0aedcd40480e485ef0f7bef7f2b100f09dd7e33bf54dda41e	\\x00800003da95d086e155ab25bb1193e860b5da01c8dc21b84894f2b356aa559cd3db1a0b8b39ea8713cd0055c2087447d96216a7181011469877f5d34f406a0e158dd7623692b361dc8e540d60567c98e26773d55ce6b11e50b5372fc1b2c555a288d0c57b2a08041cde2a193b75fa91f427bfa8d1203747869eafb74332439b559c71af010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc19b9d8734026fbc89d4e8530c5f5906065cde051a271f050902c1747ce38ed79cbfc723d187e71872430a6ba2fc7fdb73949a939e91da06c77000949c4cdb03	1620294289000000	1620899089000000	1683971089000000	1778579089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc25c1857d23e101434671ad8024239759938f32143c8dc09146a01b86422cbe8587a357c73bc840f625d378fc8bc67869078248e76165070fa2c2b733d024c5b	\\x00800003b69f1ee4ee3d76687281fdc5ad64e9f4f047c30ad4cdfa56b8b2f4f37ad751ffb2fc05b139c416cf7bf9cff868698212c1c057cd7342b568637cf28d82b5964c1f594d05c09d9460d1b2e1b0c8562061d7ee8fa2341414b1add31e49c535511d67618932349d0108e664a07d7eefee2c6c54416daac2c48ab718a871183fdbd5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb4336cb74305d8e986a9423f95308eefa2c00136eccdb2b0a7b452552864b484cc30b545c772edea9d1a4ad1d5a8d9ba388a3b738c06e876c411c4138103430e	1633593289000000	1634198089000000	1697270089000000	1791878089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc4946f95146da8bb2df435f755a02dd0c27315e0cee9504326eeccc63139070f1f2e5e36060536cabc27a2a6df23e37031d021559a247d958c2059dd54d8c2c6	\\x00800003a7df0e8d2f6a71ad61dae6c75003b2e3ecde7bb84ec5f742ec033462b3dffcb91d0b22ced199b17abc9fdc38eca09ab368c494fccfa669b0a209b9dc88b3b2a23e6e82aa998cbc7bcfdaf468a18ad86c32cabf48dec6e6d37b3a66a244e916135b7a6c25d39e8beb595ad914db9a7b0a316cb745f340728ca9f7b012e3e4b357010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1583d3272170eab106f80c8d70b01fa856f07626e78c9bfa1dfd902ec3ae631520a0b7e87d0afebff54bc1cbd7a449d8b93ed50873a66e30c5ae65278f890108	1628757289000000	1629362089000000	1692434089000000	1787042089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc658bf966408dab5f76cf2a8129d04c7d667ef2cbf287ca4dd042ddf27519ff7338bf33157da1de54fc4bb1e2e0e0a34605cd2b1a8ac752e5ec56eb9ba8acff6	\\x00800003ea289864066028db9afcaad6777038632017a80a3adb557863119accb314d47a21d82cdc6c5b8eb082a58b84fb1c9a4e64cdb210237abf0e04523af677803d9dedc96333ab3618cde33798a83785d2a045283dd6b1e9ea0b7d5135209a88979e1aea5219ab92395ce6596dfed743ba9e0a4803eb7672080937e776e9acd1df25010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xece61edc49418c1388ed98f642cf19d969eeb8eb908efb40f7eab101b2f30acbbab39bb29c0953624963a1bf3174694f97361e7b16153ca75cb2a6f4f6994409	1636615789000000	1637220589000000	1700292589000000	1794900589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd0cca1c89b5ef7239154c33de47f223671642bc490e16db2cd445fc5e9452c6a6769127ec68b7bc8a3e51c742a5cbe84d85f43a31441756a301c578665960a5	\\x00800003ad783b17ca58570431cc0e64e48110ceddf2f7e12d2da1fd825e36d07a09053d3bd4bc8172ba6d5f93b12ec55b5fe1130680bec750f8fc8a6875ebb020aaa0c4ffe6aeee57877366c2e1d586fc1e236f61ccaea9fc0c4c94849b0be2a7acaca5a1cb5de07b86a1d1b7143477d37b0a4e99103f96640e91eaca9e7fe2c8ef112f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x57901ae26d301e84c724eac7014c21028c3b2323be9b064240412ed93d559518818dd09ed074acfb537c36db28a569e97f07d86202520de78ac778a9251a7806	1612435789000000	1613040589000000	1676112589000000	1770720589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd12883a66074e699b9b1187a7349267996a09c5d1db4cb9b917b1c15c0c1a1dcbbaf68b6769c193b45201122e7edc4d76598c0d213934161e32675f9b29a9a7e	\\x00800003cd52f7b6facc5d3e4646bf3c9b65d29bc6fda1a8b623edbbe2a28a4d8b79470c1ac992865491ce63cd7c7536c10d70a530d2ddd006b428260326f81fc91b81899ab3323b794b0cb8a6e0344dd82cde2f19e070c9560bd89d4d122d5e27778a84732bcdf18b953bd9c9936b151efe7346730a2bfa5f8f5e17824dbbd9649a10a5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9af03410eb918d89b587e2b6b5eaf1373fa5c2e34396b00da3337955a028d60a727c28a50a1c787fcfe792c07536f587f33ecdb15148b6ad80bfcb6061e79302	1632384289000000	1632989089000000	1696061089000000	1790669089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd28c93a36dfd2a11dc8a7e15eae55976d697109a50390c523b6e183c26ecf9edcb9e189c00ae6acd737f6305d3b580f7235cddf5adc67782afaaee28e775afee	\\x00800003d60fcf773c9f8b853122c2ff5da295ebbee247b646c6d35025a8fa32884b52e07692d034cd4f1f99e257ab7a3f12e22c4664f56999c4402546c704326440385d2f3c1ce0b5498d103d7524a4a7c029af6700e27e900cb2635b69b0da8c24367b9aa11e3824bde783656d74cf48fa6e840ddde0738f5f36f08f68e7afdd19c01d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x29177daeff706456067cda2e005d721aa739ad64ea251d1ee415daabc807f6d3115777278b0c468eb4cff9e8c88feee11a5f218df08403fd34cf63d4a0ce9503	1625130289000000	1625735089000000	1688807089000000	1783415089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd3982bfd13af8f6a8a8251580716eb0fd8c83407fddd545bd67ac4d1153ff8bc847037d6775651842a35127ab7302e9955c57d238425f711f2dd2695304fb597	\\x00800003bac9ef65f11fd6be25fa5385a53500c3f4b4c64b44053d01e232f260bd446b98c86cf1c6915fe619c31170323a26229f2c09772d968bee6e5ec2f548f2cf7fb7b4301cd1061dd1c47816ade6ae6b137e638b2062b5863346de06758e985585a881c7eb1c04e4cd9364f7d6b4bdc6c1d9538d6cebf289ebacfa0d517fc68cd983010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf0547233c9d0b8da6031c812185efd7b3bcfa0f07fb8c391c6b493d74c583afeaa181fce6c614d125d66b7ac00d06a2cb471c8cb0993103b3418d640ac26dd0a	1632988789000000	1633593589000000	1696665589000000	1791273589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdbb85430f93f58cbd9132cb0f28fe88d9648276b2e11087ccbc93363814b3abc69d1fd10789e8cb26a8304a86fa383fb8dae40e45048c5c0a84db40a69a9cc1c	\\x0080000391b3d18a561635444f1d45c0032aa19c2e7acbf40dba6ed9e7cad6f14d239a88ec6511f7875aa958ebf592565c22ef8c26511fc108b4c95843e40f2c45fb6547cc86862ba29548230d697ce5fc5cf2c88c8b088c562b44549ce91b78b74a5cf92638f254d6e01934a496e3d80d429f626a3472735d7e125eaa7b0b4f31ed9f07010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd447a2cf25ccb0a032c96988407977767c254d78fe15ce4bdf85d91d9528226c568e149ddb7400d47f9ff63a257e9cfa0cd56f702764bad87448f207cc94dc0e	1617271789000000	1617876589000000	1680948589000000	1775556589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf90d2b24614b0013571b7f1217efef7c9da64a9b03a9cc57e66b225d72c49244f635470f53d0f1fc1eca997829588a129d6488c62a6cc575386a0bece7e9cbc	\\x00800003aa68d53082e94357188f7aa05363dd2f36f842c925c838f279c7f316dc78b4af0358decde8c604e16a68419af74236389def12aa8ed99b934aefbab4174e611cef7c761e9eef51eced8392b42043cb475db91599e20f9412fe730db985c53059519d045799cefa10bd9f3f3a1ecc17ae0f0b2eac18875b835aacabd4e189fa45010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1f59d92a188ecdaec0f053e5a17660a68ee53ab64f6938bfe481633e8c6621a92bd26cd4bd75ed8807756cc640cd8839b2aaa9d1e03e9e86e92d100e66ed5a0a	1620294289000000	1620899089000000	1683971089000000	1778579089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdf445e913b2f28a051a27c615e2c60563e1bd209a3767365997165b999c70bd5b40585f6b952e9e328bc782c0669243d91e3cb8c3ac22179d1ae8dcc902c5463	\\x00800003a951201f79c0be7eec3f70fdb911a64ba6fd6528f65195b7b619aec556aae474c14bfd42781c8da06365be064a27cb31576d6b12860010f53d3e42f4f9c80d4df395bca4a8a782dddf050250945cd6d6b723f6d19eeac232229f6410a97c628becb1fb1b4bf440461b5335ed538754cb27f0353e15f18f72d3cbf434ff1d91b7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2f365b3f33c0a96badd773d974423dc0ec442c4d0db1b04c4c03e285ecca5f928b5b15ccfb253a7e33633e4cf6dabdea39f1343c6d96a3d4509f00a1f8698d06	1609413289000000	1610018089000000	1673090089000000	1767698089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe1e484d0398119b31d4d6d36e4ca560515edc546cfa6aaf62f56544325cb5edb31ba19adfdbc1f066d10317c94d634644d187dfca488c6e13e261f013e18cbf8	\\x00800003aa9668e38e3aa989f092439cf0258e8a0a52393b77a656a5f961b3eb96db894922b298ade3eddfe6d6f8f2bc8e360a737458cb66a9c20da23ddcb6e539c4b2f04c4327f03727b6fd97d9ec5cae21b888d7f3ac21be102abf3dd1e1f83fd2f64557e6dc908e60daec2d017f01d0c72d93b5bbf11d37342f950ea86a17632605f3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9c43e569852e17c88f9d96f6108a6f26d3e73f65c10fc21acd76188fd4118f94a82f0279f1bb7e14ecc2bbd54606b34fd01c9167094a20a1dc1714fbf9b67e01	1622712289000000	1623317089000000	1686389089000000	1780997089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe458db96d8160c115f5fc8a51465f653d54ceaf7d71c8ecff7a1787b4174bb7cf80bdcc78f589ac978d0acd7c8f90a571a54f7b08c3262d334747d510a18d691	\\x00800003c06388eeb952a1213eb257db08bf015c73fcce96b89f9b31c3568338522624c7d422c9672a6599751aa87df8cbd21bead7be1c57c3fd87df14979db1b1ed9506c610b2d6a3b81d4b0f4483f6c6d9ee6803c51d33827431c1dcf6c4b16df7a32c112a6c8fbbde1d3abafe61b8c01047dac0695ce263b73a608ba163eb2c4143d9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x93ead7c5b1a23255a889f7688efb7aa14488d5bc425955a1af13f48d12e56380445636edb7417f6c82235b4fe80bf7b87514c934a8bd6640eb8b24b5a9c6240e	1629361789000000	1629966589000000	1693038589000000	1787646589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5e825e13610c07d8e6273a87334dda2211a9383f854a465a5cfee22f40893392d9ca383585a334cef1092ef87022c4ea3ad364a3bedc2f54926c1797e04a9cc	\\x00800003b224cc60d12c0cf3fae7d1ad2a1fc37f8984ed901142db1cc3fcdf139f1ad4111a43d5c99796a2dd168ced36beb408bfda7afe1326b8025293b5d09d000c243518c1cba19c77e3cf335c48d5650913581ab3c95ecde2e56066800778b16ed59770752f3e452628d0ce98803596bcb25db47b9c280e3cb60614a096b6d638a0a1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb63c61ab1e91e4ffa2abef84575fbda3e0d53dc6f1293bd59e3b55f538b820d32ed7d5ed2579a155143f5bf6f26320f30479ec89df4eb15b724046c3bc985805	1634197789000000	1634802589000000	1697874589000000	1792482589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe5908563d736c05b2e0b324079bc6443b4ee0977cb3588b20bbed3b03efcad26080bd64c35cb03ac6396ce4057ec5ecc843953f0c7b04689f3661c6161f17fa9	\\x00800003dd96ff6ca7da6c65e35de85778b48f1c8092d23d140fc0952f96c6f4917f2bb8a56fe9f1342cc6e8813f3516cfe00e5f269f9e6f02c9be7ea23952e99d8e509e8fe6f1433226fcfef36382d6163ba994583cce2ae425745341c8561df561f7e76bf07a63edf6f7950200f17822e15fa1cf865d3dd6f222c53b5ba88bab59396f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xef4129c11f223791c6a355f8efb94c9a074f68ae3b4471cc490dca6310e97e12c14b77812beba2b156e8b3ad21536403179a7dac70e9ccbebbe3bd1a047afe04	1615458289000000	1616063089000000	1679135089000000	1773743089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xea34142a8c8e411f47565eaaa3684fae7c9f7b4efcbbe95cb975610fdbd15a248cfb6312cd3d31ffc776d6357cd0fa967113677a74bbc3a31be98e9a099588e1	\\x00800003e58edc075569bf3a67e0f4a244b7b3dce15f2631c97aec88f681717889978f59c048decef09f6d1ffab542dcba10703cc16895ffe9f21500a339b35c814f7aa8ded7eef8bd31c0c8533cfbdc90e0e06fe7dee87a2ae23a01c736970b37afc9c452cc08f836ce351841228e639182fc2df7e35910d7c8f0a3d2abde25fd957b9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x712a108c0b06f9edbf98b7e6a6617dec481226ee932e0b3dff0ed4eaabf409b8dd20f8b268fb107e28f0486182ca8d071a45b89bfc206611636afb04ecf7e809	1616667289000000	1617272089000000	1680344089000000	1774952089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf0dc36367305361a31b267a850d95d374eae84117e74a69cb8c5ad0ddb0497ee314e533fdf97305ebda0eb3b5f14c9ba97d9287563451fe22f3247ea30ee47d3	\\x00800003cb9e77d98233184993b2bfb5ff9bc452f6f0b3b1cb5d95f506cf73473f8ce3bf8414769d8c811cb861e92bba8a1c3542989de086004f003aa60f02e0d813d228657364c677bfe9339d4c35a8963f1aff467265322112b0d4616831ab6809e4488fb07652b0c5ab04c400060d9677737754a6c9ea0112e65c289be8b316f6c427010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x56788ba21b5953e501576dfe70228d2c72d89937fa7a27df2c36efdda07116a3ce3285b6e4e8ec1bbdaf7f08778fba80be01275cab7e975e2a75c7a7840c440a	1630570789000000	1631175589000000	1694247589000000	1788855589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf3b43daed009d92e3d5943f4b7c2c5d14e98b2fa17ae08a9baa39084a12bf616682bf607a2cd7c5aa0d4d55048ad4b710e8403ae36f0f72a3a6a44d02e39286b	\\x00800003e80666ba8a64e4d92185af71cd7164b29d29091bdac3ec5dd8e316e4dac69ea9bc42a4e487df2179ffe46c55044e9c501f48ca4cf6607a9eeb08aca02497c1787d1bbd178ce1006861d723de28127ca0eac43368ca63aabbefc40ac0bf2f60c03c10a791d09e65b3c77aa0463e77dd8ec16f991cd8b47a95d1ae6dc4fc22e3fd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7f9e5836ab5179fd08232454af878b29c96070197dd6e7ae4a7c52f374dc7de367bacd62ada2589a3477ab4c1609afe842e62a953c149c763464b489bb46870a	1620898789000000	1621503589000000	1684575589000000	1779183589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5e0176566d08f9b701541d0b5ceff308548b388ace64f6065211eccb1d25caf4666d86a3eb7a2b1b06c04e5f8af18f6fe1063247d74504a717de3f70720d808	\\x00800003c000945b7bbb716c08e69e31491a2c313d1babd0575d32d9c1187ff094b357302eb660ee2e31abeaa79fd2e6857adc6e4e6b6d17d41b2b420b086edeb6740bb7c38f9d77ec8711e3bb824a0df2ef6ca5e33197dd1150ba9221bf1f40c352dd430a7420e0b578e0ca99be3b7d6a576080cc9c1dc1668b512d4ecd241bc37f3007010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7d15d936d30de3200fd186e0e4a94bafb88015bf431c36a3f09b2d07b730653e04ed0fb2441afabf10b70d8a0cf9021c2a151b62021974066b8ac31ce630160c	1611226789000000	1611831589000000	1674903589000000	1769511589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf5146ea8136c0622b5cd93ec03eb9a8e303ff5a8da4e398505edb6bf35c61313d7d77c6bf82c54e74378b9f9d749356520b3f1bfbbb463034ce332a2122b12e7	\\x00800003b91c9d8f529629befbc1c183af5bce7c9a8198fb01c7ae983932e7a65bf10c6166f245297beb5a839a973f848fd6a3273f032a2eb284ad52ac2858c41543ee325a5524ca4f70f7f37e127fca7869ae77d4e2a10c81ccf91092fed29d27334bc03d3c9946a2472dd713df14c9fb7f3191a013b35c6b486dd41f0c34d3ad1eb895010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3db8e085f9aa5a7ab6651b1f20c3644e8230b121c2f02ef7499ff726db5bce1d870ecfdda312fdd0633487528ee86f2fc5a56319edb041f553bd4f81e3f5c509	1638429289000000	1639034089000000	1702106089000000	1796714089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf670aa584356d26c3fb9f75adaa967ae0dd29da90198d5945ead80311519f7e11f6b5a03f19c8ccc751c87cfd7e79dd5a72f86500d35531e1dce9417f3d80bd9	\\x00800003b74a57f73a22e159799c1399c49781318199855db35cb6819a1032b1e1c3ccdf91c9a6e4802579880b4703e19571edfea802bafd1ab05532ff10057eaf59846b3742d7b11fe691b1ef0c29c37450d2e66ac744804b07f88298576ab34ed7960b58627af5151a846dc65d95ae03266e6dbfb3a5e785df0c2ead0a92bc6e7527d7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4572036e5e7b70873365852b6e0662ed1414c6c13c42c9d409c6a898e4f6bcec00b9b1a071a7557f179cbb9eb0526fd31a69240f3e9198d7db1504d5f471190f	1615458289000000	1616063089000000	1679135089000000	1773743089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf7880ba50d13432a695f9f6160707b94df260a161baeca8c6f7c1127f33bf857fc453990ec14bac168f51786018a00f691f40f4eb7a9bebfe82a75462cf96f3a	\\x00800003ba0934df9564eba497ef568c6e180b4b59130e096236950fe4a918298e00b57dce5f042b9027f3a3c0856bb17ed4a80bdffbe3c84ec38a95b2b49114c79452a29aed7f02ae340e21c9f905a3508f46c5900ac2827ea913ab956bb084287b1d724a9ec4276016f7327d5d435163faca7f3e5b36e69dd85ab39414c12a416b4c05010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x10219723c5b9c8444865ef997250364ef7dc39cc5a00c04159a2d08d632f93ee0e61d336da259e8fd19382f09e373a464a4e0bbc6db4c4e48924f0bc39345d0f	1613040289000000	1613645089000000	1676717089000000	1771325089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf70c73a360b0a7e5dd7bb5dff5594096680a63aa9e49e83895a93f1ca56fd6d905d3d3fc8fa7acebdf975807576177f792c1b53cd1e19d5b61c1eb72d6b25404	\\x00800003add85af4f0348397c12ce667661edd02280b2b79c549116e645d37f9d74598dd9f72b77ae5cdfdaed80d312eeab7f51338a74a7db54378b0e7fb50133f5cf9c66245b92c55f8fbb8f00d407435d9b859f140dc814538984254e289e2623e3108ccb1afbeafa7448c47043ac4b9becc54e645289a2ace1140868fc27491a64e9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x48c37f22c25c0af792b148b65fb8621684f178f5b990d599d4e741ff84f026e6d697cd7d87a0c016b853f6915c09d7b86c65b98d9f661b52c614edb27f5e3c09	1628152789000000	1628757589000000	1691829589000000	1786437589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb9c1481dda403b57963fcb701c7c5a62ee2b42299cff73afefe21c7f9ce8e018a949e9f9d6b79daa562ea272153865cbfdd53b3f73665502f5695a3d4e13327	\\x00800003be2841a0da3031334ae135948a44ca7c53c8c194821081648de448006fcb33a08737acbca3b646dc16da87b3f3a6ca652f3f04c13a6d173a422c71fb30a98b38f27d0d270e87126bb59b1e095827452891a2623dbb907f6e9d22f857dc0fa3ab5aa7857aab9444b994f7acc8316ed1fd080f4423cc0e65e9c0849b7359703a75010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe44466570f96f1ca873ef859650418f4ad79126c38f62646d9cd8650b5de2d2eaad81ba3d0c81a856d2c4ac4110465950730bd59b0f0bdf17b0db628ecf7140f	1622712289000000	1623317089000000	1686389089000000	1780997089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff940722355169ea675239a1ab21821946d78914ff981be7339da8a6606911e9b721e12642afc9970e0dc23cb4d944d6cec0bc71c31fd2fd3b68822245caaddd	\\x00800003b150e4ffbb9f9e1da4feb9883ef00ce2a88afa060eced6a958b19099feb0b40ed8c8dc284ae6835700f419f52a3bc2ae23ec8ede08ef312b5bea0022cbbc608b97bd42f74b31c6f559383996397e1fc8b603c38b489e013964c30ceaba2df485e724df6959c6d22dbffa7853d581e2f04d608ba1961a84e78a7da662017de733010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x881c9667aafb5535f98626f0dc55e129c8ed7947dbc16e3d8a2d42689cbf29e2ea85710ed47205a4b95df7373fc445e4b054ba641c9a63e6079703fb27de190b	1608204289000000	1608809089000000	1671881089000000	1766489089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01a98a1b44820eef2ec96b908f626e32a0fc52d40d384a43a0f83d93507e443b11a2b0c444271999e041cf36789a753260bccf8c607a77d478729c8cfb1e801f	\\x00800003bd43e1a43d5a13ce1724dea9982c585dc85be5a58865443e16ea6e32caaf54886241a38b05cc3e847b537c375bffe1cac523e642d6b6fb72c7249d76d5b18b3af957b18b3594d320cd3d8e789bfd09b207b17bba40189a142ed015e815010cee3a09b4cce974d894ee3379fc5ba3f4e8e01ebed785ef793a73d4d21be4359a31010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xbe05e37391faf1ee8087d1065d7b4bc515bfdd28d8540faf57f77ece3ac3113630a11b0f6be0746bd5ddf5b5058deb6c501baf182a6a9084aabe9a5811d1730f	1610622289000000	1611227089000000	1674299089000000	1768907089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0401f861e6f2b67dca4fc15c5da791cff19781df3d3b347828a85fd60198f84c8780a8d178c37282f991bd121f941900b9af7e3460f293bb124f58915dd8b2cf	\\x00800003ac348e8bdf943c921f79b474498b03fee03622eaee19d913869c9411d486aa66d70c384628271aad52223c665607497987c355302d804af432f8b640e494b030e635697f7400c0e7a74d075efe46bdbc32660108c906675cf2b75e8908e39ead63714f4d05376cb40341425abc059f2a390911c767fe004ac6a556344b5812cb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x06da3a4afb122bcc01ae7cd8b081e5dd5e7f4bd8f9246ae9be59c5b2eee510e6606d0c7b973fb9069621c374c1291992c55a6c895e563ceb6e8d483fb200c40b	1620898789000000	1621503589000000	1684575589000000	1779183589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x054d937d78b7fab83b71f1778464ed6233436144d78274a2c2973b3bcb7d3247ba8aae555fac55b0e89edfe26bd0be68e80f37b6aa9f1187d335bb3c70ade98f	\\x00800003a8ba71ecb9f0745347ffec87a5122ada499d056fc502caf4ee3a2b0a8d10b4ae03ca21fd36b0c4e4407d1a9af3262bd9b75191ee3837d79d5eb830494df16215524488f9c96fc8b6cbc4240d6b98f82fd581a4b5c809121806001d375ce6717956d0ee24992e21e388f25436083697eca79ded0ef551e212c98de1b1860391eb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4aa5a0a365a25f3416a3123ad5386f4d0d1a43d71f3ef1424cedc6ce3f9672b8dd93e6c74a6a011c8fb3a5e9aae4895c65f03c0b431db033758d088cd6da8e0e	1636615789000000	1637220589000000	1700292589000000	1794900589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x09717ee9c89fc654bf9bab176270a4b5686c97bfcf717fcd7f18afc9c78c15dc06d3cf0e9dc220b7ca004ebcb7e7887bfbf2e9a029bd7e5be1686fdbc102f0b7	\\x00800003c0831f6c6ccb622c1b5832c327ebbc1a0852442ac3b5974434e7cdd4240a0343275a99ec5f6d1dab8fef602d9a1ede7e759a713cff8029695d2b6f6a060a3bbdc2e68b3217e75f4a5344438947293695ea30e0799fe1c10bdb04a9d9cdd88feb22b203a0ab0dd7616c6c34d1ce92365defb310890798841054e09f62608e77e7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x45d326b7aba44840e16e0560c36392f3345110d9e74a7cd1089c60d654c674ab2dcac4613d5f7b1ef5fcbb6d610d021629594b3afa55b53b952e38d14aa4fa02	1629966289000000	1630571089000000	1693643089000000	1788251089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0b85c7c0200ee709d23a5e6b323ecb01e7f3ef6c56e110ac19164d15cfdf12019d045c1e11ad06037b9cb83853e44f794661a2dc6a6f55a1a03bcd8f9ac44678	\\x00800003deaded4b9b0c62d7f4492ffd27205d64d53af959eabfc9e2f11f52c7a843a0943312e2af34aadf86bbc340bb982b94d835b5e3da06b67dcc92982f9863e0df69cadad599981abc1e855edff1d8f7757d9dc5c92de02c74c016bf3a9696811f44f05d03bd1ac691da12c3ad1cbbc24d8c0d5950f61211f7063f0fc33aef60cbdd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8452eb51fbeb885be4a72a99d0bc95cbcd6bb400cbe4a2061dc772941cb35cbd26a881cfbe7e24d7d5d06129c872960a9b1defeb3bc92ff63e618cae3f918e0d	1637824789000000	1638429589000000	1701501589000000	1796109589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f15ec6e3b6ac9180ab67c807aac06e5be67bf9add61e490504d36a79c165e5586c78fa6c360cc0ad1ba0c0b193f76e5c2059a85aba55c0a938f0993b21c5371	\\x00800003d3216de8c0aedd4d3b5db6f8d751482f6047770bc401172e28d30d664a70714862e9f377c21b7d888f1348e8fb35fb7ea7577279f295a271b24830759d93604002f0995d19afd7da647489327480047a02513a1be130b97ee69bf16a4d2b5a76b78c049f6a23b96eecc47bdbfad2b508249b325178e1b2a178047cb73909dbbf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x360516b0f348a8d66df4c7223ba6272aa7bfb863431b37865d5420fa170745b5e5e9851f54e7095a901b70a90fd2097bab0016b11ed44f29c36ef876edc4420b	1625130289000000	1625735089000000	1688807089000000	1783415089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1421ce34e584f5c2dea672bc8435443086ed8da87ad95e1bc77b359a15469922d94432b840ff4ef109c73b62b386c51c1c19f2d003ef5a04e5a10f55f8fe0810	\\x00800003e74703816a6d7ff51f45aba0bd2fed1dbda91f2a3edb1b01f775f1043ead6c88d265244684094f7b7b6a0ea7a7fe0700eb4417f4538d75dd11d146cd55ee25a6fed1df14591937b3942eeef2118e6c5d90432115adaf9b9b0cc744004f60175c096ac3a42d1137b527ebac42639fdfaa70a7a787f07d32c39fa01c5277462d0f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xbd296618aba1849b43ebf24c2d7e64698f6ea25589f38e6de6d339b4153de327c66764cff62dad649c3d4a12d10d3ae94919cda09b4c2d718b64113e8605570c	1637220289000000	1637825089000000	1700897089000000	1795505089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b35b1712d91f46bd2f2dadbd28d46cb904ee1ba08c7e5ae2383d0c8521a18b18beaf144d5f1d2095ebdaec74b33f18efa1896167dc4c95d7160031de5c69c2b	\\x00800003e10688a6050f01ea71f7746f148fc8134bd29be084f300b6c3a18535714ad2aa3abfe5227318a4abcb2328a1c72393863f16a920c5acc57a70f8f474d315108b92604d8841075ae7aeb05329ded06b174b79a91e69e6f6790869a3874f46c3f4b0dd0e0399d3c2f66273db798e494d410c5359b00b90061301f61b0c747679c9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x81cc452b1b9f0c225c7ecf224e169fcd9cd0aa89d68082d813cc468ded7a49ab2bedf2947f9a3ffcf0fcb641de1e5a373f0a8dfd22643927a24bfc2245496109	1625130289000000	1625735089000000	1688807089000000	1783415089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1ff10819538965ebbd006f5541cb2a19e40cf41d6f7135645492927351339963ad75ec0fa62505317417b10d0b5c8dc093102ae2ef2213b4ea45148fb025208c	\\x00800003b1253570839f17d83647f25639a75fce49b9d1893813cbfe20467a9674ed5aa777a3e5882ab99e8e98a3bab35d388e22076745077f7fa1d30a52c7e721762479526e46a06efeeaf36968bbc67475b3116ef4227a348180778c84e95f8882121e60465c7328609d5d547ef8544f264c9bd2bab6d524ba28bf21ae0637d6ae4e5b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x30d45cb8e46f5178cb8465a1fb275f0bec1aaeb506758564caf1ec16aa7d9392fb28676b901b7c002e2f64be525854fe9d916cd20f7afcae031a66c562183804	1622107789000000	1622712589000000	1685784589000000	1780392589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x20c5d8a5b20e2d2b7b44bd23c3fe740c8f8f91177eb04e10018dd4ab440465c30d9d58df423aaac425c5fd2b0182a2fc1758e2722cb16dd03949b1027776a20a	\\x00800003c15bd609a85c85e6f050060f2b1a6fac8c1bd7db6bdf0348484fe899f7b6472535fab910b3138500a7c9f6c9daffc2ad24fbd16ea7777d6cf561d77ae11c2468e03d4d622a086fdc2abde43ea8f30c3bd9667db68ef21c9f2ab7c084a9fc97c0ce75872748e18e5d8e67d5a627b0eff75900f7e91c9701fe01fbb04a5e9beb9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc9786bd511ce84da8bc21ba6fc6c9aef62249d6a304739c62b1633939ae5ef01c3c67e67b804927ec3cdc085ddb8f980572613ba6205896e83e240e219164b02	1614249289000000	1614854089000000	1677926089000000	1772534089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x257de1ebd5c056d6deb4f2cba96a85712a586192373511ae9562e9f445f58736c9d260243d5cf80b352fe522c987bb11a7ec704bdaf42a620f9f829a08a7d238	\\x00800003c29d9c556caae5857397c9749b259a2013a2b6e03dccec6ebab75cb5bdcdf7966aeda27107b5845d5d2bc0b6c0cb18fe6a7ad73cfd89c43d97842fd71296e3eb393a1024b2f85f284a584e63a9d7e64b18d2bfc8204669e907ddd8bcf2bec51b8aa1b167c20cdd9c45a741feb1a4cb2a54591c89eed299ab74edd8f26e582697010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf4e44a1e49c711d61f8df608dd42a785c1a3dccd98883dbc1cc8b47838d7a688e9c68e969e04755c42c76c793030c436c25fc34f5c972536ff99686c6551bb00	1623316789000000	1623921589000000	1686993589000000	1781601589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2649a49652fc05da1e1f51af62d91e4b4c40c6fb0b0c9a74e75be8b58bab297a92e07b4039d517d1df6363cdfaab82e3ab495c97b422c1deda287d184ac01c18	\\x00800003bc6fc507e19de40b387603717e76f88a38c014cbddcbdccca74b1f910960d3f0519596651f58649b089ca01744df7e2b953bc864a592850c66f0bdf13748147c94163d3272eee13119a969c7c21b3507a7e2e6a82d01130427c2dbc7d377ffe22fb8572b267ed836d61bd5d03cbde5f88bc20fbd386200b12b86ee555e69b5c1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3dac380500b6ee30b488b83d8685443a44126750a8be117037439d58e52071ea34299a24526fbb825bc58d9e1f45db8fe463fd272b90d760f50c5b9486a81201	1613040289000000	1613645089000000	1676717089000000	1771325089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x28ddeaaa767f4ee5ecafa7f7e9130c9877fe5192171d0383e1e9b305832cf8842e5a0bd968d200610274518657faca70b6fb6b38941038bab509818c7c896c11	\\x00800003e309e78c9556f02897f862d6300ba7205186317d10c1a807d009b97f5ef1ba24bb1e865faa9ad9fccf4eb186078f4a1e16974f84807b8b18b2e25f60077a3a72beef4dacaa29646d2478a33b0ee182039500eee50b4d57a196ff5389eed1577b863ac8819a6a026b7681d6e49f5f04347b461a801dd4426e40cd839e58fe6a59010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x06997a5336fbfd2abe95ac7c77fa06a787294078c7311a44fc1fed57fb40aa9d7f8266371a84c6116f4af8051bb1b92c75045da411022262c299e1252fa43705	1614249289000000	1614854089000000	1677926089000000	1772534089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x294d4f6026ab4b5ac39a192b2e04743556bfaa2aefc8cbe20dfa7bba0e7b878814cb3009ee5ede3524cb4cfc1d8f7e52ff8d794483137d95e2251f2ef56cee11	\\x00800003abf100a93ffddbe769757d737266f7d81eed0e43e49f2d78a08ebc87a8419c112745ff2e6c23e999572e6c14e3712efac2330b73672b634efcc87d13b9917924ccf450dd4d5abbc66dcc5577c7595586adcfe1c3997d12016e22f50399f7a70124e969d1db2a92842798a2a6d149776c5e2360c6f66fc5268c6ed959a0970a61010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0593b1d4a0b9862772715cb3566d2e4af1c7db0a49f679ebd6e738d6e0892e576b6dc7a5938597078613b5a63b5cd5b3fe76a1a9d82b8f543faebf3eff8b550f	1610017789000000	1610622589000000	1673694589000000	1768302589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2bd949102cbded0ac13af20e3e3ce0ff58f5a443b9dc30662b6a6f5bb2d765fba01de60a28440a8878a5539ce8d157adaa2b52142044f51491c88002e3ec10c1	\\x00800003d8a203bd535454f2a0f107a46ac6e207f1243e1f9e048467b09773b27f7affaa872d13cedd581cb0c35013ea9822bbd0481f8cb0b859069665bc62180b297acb8a6d5a309fb7caa8bf4c85d18b7b4c747063a6cbe46542e5ece76b2b2805e8c1acb990a931372e1793a1ca1379279e56bf6264eb1c346004aeed888f4b6fbb49010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd4899296d9f056663dbd7eb2b36a136410210a4b6bccb78f9163cd3e5b73c3028a1aa6e6f3d484cf0c32826a228d4dcf584e9d1f57ff0bae8c521d5880ae460b	1609413289000000	1610018089000000	1673090089000000	1767698089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e011951eb136c3e59c639694287ca7dc159b5c125fa015ca9f610cea02830890cc8e6cfd7b46197bde64ebe406684baeebd3b15ac17548f214854696774b934	\\x00800003c0cf1963cb34961c9b74a201531117e7065c2a1fe3d0f13391b8810946e5a122fab9795e035d06b727674d22d2d3883b6039092fc4a78c7af98f9bdc9585e31c0a06ffe01d74409ef6491e5efb41b0f22339ba5b6501a5c751b75c3ff5e49d1f6c69dcf90b767061dcf868af4648f0ea9299907bfd2c78f68f251417738c73b3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa14a6c94e2521bf85aa0de41724a8ef11e276e5d0599b48d57c58f6e9a0a84839b231dd0fb673992783b3aae85ebace7b899cad9fdbbb33ca7b912251712c40c	1613644789000000	1614249589000000	1677321589000000	1771929589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2e695fa0a4cd63f736815f1aeb8f9c367a7011e23dcb7c340a39082e8bd71110280696623c9d3eb38a13a2b20b089bdb646d225f0c63ff7afb9cb920c8a79aee	\\x00800003db4a03bd0d9ef63cc323d45c9642aa1132cd429e0a389d543f8f6b8ebcc1db15516c97e8d5903d4bd82874cde9f346d652cfb8c95077b301a7eb76017ab574838cbab6af07d00390cf24b89dcc082764601debc5858ed572e48e60f0c8d3c667ba87fd51915950a9229748ab3c44b7241f388ecc244df88f529dfe1fbdf06e9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x07277699f79a224f45d59f9d90995a4f806f3eb81cf7c4a2ec4653db0e375050286b36e5b96186579154c132c202d9abda70a77d16bca5a275f52122f706ab05	1613644789000000	1614249589000000	1677321589000000	1771929589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x30dd0a11758cb98b37b398cc880a3e0c687ed960f88efdaf21d403e116409ce530949b7c849098d8b6a400e88d642ac0a6f461af2bb2206d26f4cac90d8dea3d	\\x00800003c69efb126ccb4bd6d727c9207b5ebe5996a11ffd9b9dd73e209c5bb705db86c1edf91c8433eefb45299cc687cc66699fb9ab2a61b38e06e771f64c35566350f73e8a3f24abdcd83b12f0064392154e03b7e7c3786b34cc865e8a917b5a20ea116d07874897ccad42455e60f8681817d381afa514dcb3b032bce4fcd30a7a6167010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeffb135a10cd14a272f686e542c3aeaea9a100e05be6215eda519b34443a84a0f172fd56c01caae7f4a7ee0a53612a81c3c61985a796e26cf64f40cf13d4b30f	1630570789000000	1631175589000000	1694247589000000	1788855589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x306dab646003543b65eba2616873ec3aa9c2bb111a1374eb3ee4cb44ee9450b8d2d1ec421741a971ff6ddcde566b90f04087773505bc05c53e182466a585b82a	\\x00800003ec77ba9f94bd5550996c00f9c027a35bede891c977743309f9e0d1e5e90f4ebd457811f792871fd42f580bdec601338ec5d558d0895d4ac4251e6bfd13ab6a8cbb8473f2349036b1c23f4978b89a65a1643803ff8d4be8e85a53c3e41df80b6549a3007be1494e878716ee9389a39beb11ebc78eb8746380fe4d9a895cd7a005010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc4905ecde55cb01612b15cbd83e1e65a30d554d0a33915fb1e6fe9aa97a3601b627cb31e0ced6b79b4a13977716e59b085add063037f6005297ccd31d39c9a09	1608808789000000	1609413589000000	1672485589000000	1767093589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x30e9fc9c0dcd047783e4ef981eeef9a817ba73707cfed5d492131f60bcad05cb1034b16d8bacd71ac66d55b138add8743d08f8a2937eb19993ff442f3fbbe4e6	\\x00800003b65e8c1b1f17d47485fc3d211be5ecd6141d76472163a60562067a2cf1eb5fbc7334e9ec782dc5f0af8aaa869a75edb0413df0be974fe4917a1f4e4d9927f24a00ad87a141af0f0cdb26955bc0a0ce9fcba074c587ece8c74ce7282b3d83fa4993d5b4899e36481b970c06f7fd808eb53502cb3e68230ce3d9215939c83250ff010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xfb185747b22af9723707487d67c59d64c63b47501db21f314c693989cbc20fd696c88c1d0bb2b31afc11a6788297bce66113c5d12e36c5c786fdd87c07776d0f	1631175289000000	1631780089000000	1694852089000000	1789460089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x35f57bd5746cb1f69ccda8c8f43fa5bf09d7318170f0b72892db6cda96f77f6df3d87c526d31e030aee211bdf192ba14db92292cb6230590880733f474e7aab4	\\x008000039f084a58deb9df706baeeb39ea9fa27fbb1b3a595ea794163ea8eba19801517028e84b9dd121a934aed5c6fb4a4f3b402a40f9f4ac98cbc99b5994d1c995d4afabe979ca4a797ff0006b509351b4bd4196588f4b43a65640b672a58c6760ba01c81e4371db4078d63915a6ac18b84195da2d13b3f9d7a6f8a8b47f148c40d373010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb0e90d716c9b480f6e5a6b099b0ec9adedb44449599bd8a1bae1aa6a766ef16546731238c393d328c7af04e25b92ae091b7076aa2635830cd7cdc625bdff480e	1615458289000000	1616063089000000	1679135089000000	1773743089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a4995a368c92be5be6b77554770e2c07ae1c10c01c53fce603ebbd7e730ccfc9aaabb08516b6b03e1a2c20847f8c58f496fc9ee9e5ffd538979e69fdfc3efa9	\\x00800003b95da77fa490bf3f890263c8e56ada892cbcafc1db63f66172b43ac94c33a9419d2d8fa7e26906e247c9e0773ce9623f42537616fe6496c41a95cb18ec067d09dd177a8047a9f9fa4c33c16c700a5c45a7b1e11aa5937dcdba00e2c12bc55c2aa87ad1b38c34cee7f015391e651219134d1d48cbc2ab2e0c5af4a2b36595159b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x343d209d80aec29afaab2a8a8206e3fe0f68a9d1d0091684bb5da8236aa5576d7442bfd298c7bb11d27f4fa91dc03c61cc4a81198ba19f42b15537b269d8e805	1610017789000000	1610622589000000	1673694589000000	1768302589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3d01677ad2f3c537712b03ec5d8c008144729dcb76214d049d67e51459a3eebade7503e67484d1447be665c6566b51a9a73d441e69014c74a25d82847be0950d	\\x00800003d5753ef7b407f8d79880c8c9968bf5625191b6a9af06efa67f19b110f5236c140e744b90e201f3cc0410b911d15de041a08539fc5ee375ad05798eb904e9021342758e4723374319d26eaa8e773c138b91b8c5ce5605796692ffbf107bc46ff60ad9ce05f0ff4c827d6d428756ad58b5f3e1c1a8e8ffd426adec8468246a56c3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x307f4296abd0b20254b165ed0db84bd69c1ab8b20901bf5209f4d8eb9e0f1133dae3a61bd4aa4e1120fecf4bc8822fc47a3f9b515af75b0c56cfde0c21ed5108	1631175289000000	1631780089000000	1694852089000000	1789460089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d8df1f26f7c91d6d14bdfbbd3ee03eb2955bc40806b298e85cad31236675c8b483524ee1d42fb0b942b5807385846d6bf62b7c979b54e97a1ef6df6d1a442ae	\\x00800003ebd2636fd75fb30b2f64ce640ff4d57033bf87f6948b6813ae2e1ef4b71b6f58ab217c74e7a22c9a863ca6086682330de368898e1e7054a2d73ceb1f02766dcd17306108b00a0ca4ccd079d46d5f4cacadf6f18d0c1310ebea3be763ef202cdaacccca630683595c6a2cfbd909bb1c10e84ca8da76d15feb53e829df22fa3d0b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1de1e8ef829718251e99e84a6880a1cc4145e166d3e73c70b7d61c3d69e73e0c42d2ccfd6427edfd67178ecd30230cdd26809b1767828b2cb33dc7e9c29c2700	1629966289000000	1630571089000000	1693643089000000	1788251089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x408165d3aab8ff1a58efb222797f54b35f2dcb72d8c673f40ae09268be2e662f934a1680d19487f2b75dcf7c60786195a9d1a0f7c109f741e1256acbcaa8ae0d	\\x00800003b932595b8be59ca568714935f0fcc85199eb7482cc6c6aa824af2252308eab692b8f3be0df5e1eb623bf872655a973670523e61e6885545fd0b9febd1e4a3284a57867302bb48485df473fda79d953672edefdde9b3b2eeefe78fe9035c9a597c43908e2571b999176d8d74073ade52f2bb69990867f6308094befd3553e0389010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6bfa328a41300075382834b39a8f17df0bff3aa84561f19ffb20c22c0f735812d20aa018f36d186a96aa8b5429372736aa7c342b58526d9e6d16faab422d0f0e	1625130289000000	1625735089000000	1688807089000000	1783415089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x41f1b455f0c00d59f8567c28d234044b7fb12b2ba5a26afd7986bc314beee738842389bec8bb507cd484d33a8baf91b8b00b6b1de15261086b99719052650210	\\x00800003c03366325b624f79de7dc74cd73eb7593a8eefec1d3d7e0cfc83eef36a87c680a59057911c9121d574402cd98cd16f4706a814d3fa7a1e3a3d8194d0c87f7595a39286dc7d59c91f681f7ff859c0e30b8d831256a2e81206930d103f3d5ee09aff95fd5f22472f5119fd6fe43694edebf51493691fa64bb5167fec86a9dd7bcd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3757410bb7f2d0f80d6fb875ab4f41d387253bfb5c4bc8f9660d52a1060ce4fc6171c40b3fd230019c2e05ec59d79760ff6fd1e717d4b859e252319dbc178306	1615458289000000	1616063089000000	1679135089000000	1773743089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x415544fd619bf6d0732329b2d9f81fce2a2359d2e5ec513adaf1700b0316e0ef510d427d67bdf6a3c2d7d4b6f1f06a9452d8ce81a6b6e4c5725469d9f658f553	\\x00800003df12819d7039dcbdd58d919af857661118ae64990845cd0b2cd207611f83e74551b70b2455b04f452cb4a470239d3e5052cdd3e892e21298abedac62a31271c5aff8383af9cb29e9741d476af2d1d9f05361f7fbabd56dfdcc2f9721200ab11cfb2580e54e24bda5c115d1bed4df153f0616a63eaa2f588404a1404ee1701ec9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb74c0f143cf654b41082d01d43b65d2d4a0538578adb0b066f53fd1329ce71b1b498237a7761dc1ff6226edc53b252fa47181c752aeaa9bc47f98b624ca4d009	1613040289000000	1613645089000000	1676717089000000	1771325089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x42617517be08266b02336cfcf5d45bbba9714babd6a1023fbbfd94b8de7ad4e778ec23045cab3e802af235ff7708f16e2ec15769762e7864e97a07cdeceb33a9	\\x00800003dccf63350340becf520b64b15bd38c458ac91619a3d53b676e5a6a20e28c45a1ae445a311a17b71649498d6d9b89b734577bcbf5b41789f187a9fb27b363fba7aa64caf78c85931bc4b19fadd165ccab4721f9dbba0cf7051a12a7eddc28c4a9ca46904b950f3937a5075279850e845ee4a0630acec113dec6c2533085dbbb2b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2ed95220fdae65fca4d744fc31f63df0f40889d67ac689c2132a38760a7f424b50c7fd41af32fd2586c822afcdfb08778f58915caf4bc5a781d7c3549dd99a0d	1608808789000000	1609413589000000	1672485589000000	1767093589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4395dfa085e84a5ab61c58d76117016d95be05df550248c9ac7c5d0fef712f5596612ea15a375bce68ebd599ef6bb0ce3a865b21c0fd72e119cee1b95ddf161f	\\x00800003a83a3c9e9bc8e3190fdd96761253fd21987b98519193563d34762cd41e0e923ee49af06f4cd1a1b137bcf79b4f3fb50546edc397107b64f05f1980856e08f5f2ddd62e971d83fa03c4ced8424e64f4b8580dc7c09a3be2ba21571409754e68affa20f0769d26ede80c70d240e6aa061bb449a59e930c86c904df393b03da9b95010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4e409147f7cf8e97499663a7e9a763666c487bf1d3c68b1999dc323b5b663895b25242fb2c765fbece2b3a24f4c1cd04a6dbc717038253e8aa53ac4be99bc20b	1622107789000000	1622712589000000	1685784589000000	1780392589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x46859c0e4a6493def54e4a34ac8535f7fa0bd1b2604cce8a133efa2bd3cac0bea9cc3a47d142722b9523c32ee0fef90e64b8e0ea009bcec07d65cc3ce7198788	\\x00800003bea6430ab87734086d27a85adf1e9ad94627142530b737874f13db5137ecaaf55af2ad0b8fd651a0f35ecb69353a96c4bc6c059cfd85eb8b85e6e265a87905216fb488f96d70a5791ff28adda24fa6ac6d66a1cc5700b13e37d16527a2bde6578246816be4e1a83fc6ff4a4b25a361b5aa4488cc8189b96c263d79530268caa1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x100c82604cf4c0670318a15ba8350526d54738e70621e70b49fd458751a14b255ddf9bdf9523663aa74155467fd336d75a844a68b7f8e96862454132c7b6e205	1625130289000000	1625735089000000	1688807089000000	1783415089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4751ff657e7db68c4636ed2c0890f696dc133054333e14827b28b028e457153e1193fd4a26baff1810d92e5ab0b58a5bcdb2f355e1e57e181c53c1bda80867db	\\x00800003cbb89ed1e044a3cbb8b149a334fcf0071ed05b04b57570fdc77fe603c1dd29958c75d4df7ffbcf58dadf77e782cdac868b130a280c6c5d8ab07ef9a5948c0dd2f60055aa1374d1121767d45ce2798a79d6204a7ed519a0370339c23e8213514150b886bb7361f441820f834d0187ce76395f23b70bb4a4a6d5d20ecb1fe0e62d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xff2ea601914535484e7e5b8b9b8de2a14a60990d724d15d04e5a8e6acaf4ca6c0d079cb65a3793fd33c707bcec32d2c83c9c01e5e1fef585a08c4cf55774800e	1616062789000000	1616667589000000	1679739589000000	1774347589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a0d5e0e54feb99d038da86abd90af7c06a10e726c58e9961e13e3c0c1db6009650bb2a442577ea79520e84bf4bbb16e10f77a616e23d686f209d175d0b0c9cf	\\x00800003cfc63535dbfccf56e6c161258976bcdac962e62e7ed6261adc72d8d126fa3fe6dae6e95120102c93aa938ff24ddfc997dbb9913992d6f3fd1aa37a80e60773264f88fd499bcb167786da6edfccc53f4fdf73048dd5cbe62c6980f3a502d1d3806eb884577908c952a209612876c78c1c2622b8c4831fb8688806625a3f934f61010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xea30ab9afe6bc9f26bdf45154a429a5fd0edce1b370984481d1c16a0ef30561d0f6bf571549965bf2aaa40ac3c3988d8527d6b48c4ff02603ed33b83664f600f	1621503289000000	1622108089000000	1685180089000000	1779788089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4c39b0b882c6fd96f9cf652aec01fdab934fd5726b36b5de4af3f8f3a8dba253d2f96d74f48f9c96e1956d58df8157aadc0e9600531c172d03a4532e51e2f01d	\\x00800003afb9a764e62c77ba70b562db085d0b3a9aa15b2fa56d75865550364db5f51dff3dd9fd8d46f2e092a0ac64a9b640f796b120083cdfbc7fada4c72d740c6ea2c547d025d456904458a1c4b09daa5bb99e0fcfc49aaa3b2223c6d9f5e346753c1f9fa9348fec88ccfbf010e5142d4bfbe390784ca915ab6bbe8de6880e25938cf1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xaf759b25c24f51b6985b610ea24a4b35d3908b9f477dad52fcd313e7010a431e5f60da3d68fe9afa1c1a74acf09020417666a08f6a99ccf5e60a875789d87a02	1608204289000000	1608809089000000	1671881089000000	1766489089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4db961742e8b03b19a069d16f4eded98506cec4577454b41d98b1240d68bb6aeb2d2b563a80541f3fd6daa1b4d4ee1ea7b920fccfa74b528fe06d52a4106f4fb	\\x00800003e18ee5975818e7f1ffe80004e3ac7950f145aef8a3f6e4706a67d87ecf5f66d54e1be67880305b4f8881bdd72d2940bc26f958a0f61bb83223d10b721b3bb0b3153edcbc49d7c7ea09762e38f5ccc26ad59f817c0929f33737206b3fe38d7f055e11b149e2dd8d7ed1bc3ac20c0368b0cf4361e3cda3beeb0f095e8abd5a5d1d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xff6a6235751ebea612fc3ab9721764d61debcf2e3cf039f644436ae17eca0f244995b71c07e1c6fb22698e95b1a1b465644944d97798b68a0b870e217ed2a10a	1636011289000000	1636616089000000	1699688089000000	1794296089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f258e217e3c214a844abfddf2a862e22615b5a1770612ad34fd88c14ec128326bc49abffac0d14d246cce363ec3df2b0ad3b9a66d347e8ad1b7a55d9aa91bc5	\\x00800003ba6c46b84d54b5499bc4d373d6d9d6c88f9ba223fdea24475b638c9ac45c60c31fefe6071597e1639d485cbac271acae8793cd67c8da6fd6ca0388103ebb81b0992f1262f2500a7ddf9c0dc1e25d79a5e23ad21496a212ac5e7f0058beeb8d6353f79e5c861d06a5d0c740570089f88f4d84c7630f9dff315db4f62412db8a6f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc6b44e76b60b7996ca68ebdf48a30124ad6d73e81b09ce0a2c38b7bd27511f86c4d77fcb7ec708bf5d5ab2c566a94fc4e12eac19bda15f9c3529c1349acad10f	1635406789000000	1636011589000000	1699083589000000	1793691589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x52f1aa2a52f530611fff9be9f65dc9639ce99791bf6dd90b373d469790b732d970573e8ffa70263db8ca8542224534e35a9c6b248eabda6fc229ef67a9558133	\\x00800003b64d5ab4b9ecfb754b447a9a07afa9ac09b76e0b0205cf9f455be86e332aae14123165168409eea551acb942648e08e40b47ef8f7aff955da576e44c1bdc996f486d5e83200575f3cc3aa5f3af715602980bd868592f0a318430bccdadf0c6e3fcd14a31e2a72a01e4fc5c6807619a7ce4f68d0a9b0a6505ecc9a1c29c963755010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xef4b3aaf3ea4d6aee51e0359b084f754ca8303b1ac614265432772caeba4daa66efdf71ac2b1689e824677bb29ecdf9f25b3399b40e141eb0e2bf96686562201	1638429289000000	1639034089000000	1702106089000000	1796714089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55695195b8f915699c36878da604ad2ec1eb4504d56677406d3463b32dd32f7848c810c159a0f90b3e4fce685afcf8f5e2586dea3ab7b47ee88f4835d772a335	\\x00800003d49ce20cc18d3288eb92d3070b68799368f01b00089150c574a8d4a5d3bc026bf22efee42fe6c13f93bcc62a5adca2d4eea3150ebd1a86dce53aefc28635010660fb1d78b4503d52eda4f95f3caaab26a26d34fe247ca0eeed8aa765a382781cb26b16baf186b44d85936c9c3b8dacce69c728691f828747a5278aa6c95d5eed010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x529d5a08fad107620deed7ce3dd6f096edb54615d2bfcbe5ea3d7bba4914b09dad8e74eb23ee022ad30e38d4c817c3d10ee927b42753458c99bb8ab724f24f02	1610017789000000	1610622589000000	1673694589000000	1768302589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x55f9d8cdb345604aa33ef812c805bbcd892fdc1aed3ad09697f34ad19e6c45f474f46e103a33308a426e566cd11c16109052cbb52682b532d3d928875005ebac	\\x00800003b0114ec83cac0cea265cb32f4258759290b07bba1d90ab2e0897ec52936d7ba74bf1c1e5cc53cd5575a63c87c2ac89c69406c2e35ec96d197f276a3e8411d856bd9c7cc8b7cf5644a7e32f42dbf648d713b56ec3cc4cf946e55c5f09ec5c7779ef5e266111a9e558d72147335a65b9502d3a82d346bdf56303378da27cd2cb6f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xedceccaaaddb84fa8a9aa2456fc84afafbd67aea1c6d5ceb7ab5db409a660b18c5b5043c410ee650820ccfe66dd719da0b27636d7f0a0ffb36ba9c3722ac1c04	1618480789000000	1619085589000000	1682157589000000	1776765589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5b7589ec2c367e807e47a4033f04191de73c86956fb3f87c69846547ad6d14a8fd45503c0afb79a65b267e81a065eac8e1b6b398c0eb6fd6be246025d822a161	\\x00800003bbadb0d6a4ce00a2eee4168bccffe5751bb1bc67a0efcbfc92e6eb404ad6d135600f7f6aa4cb56a4fa11b7df787763e756106272256ed642a70494bba2516a593252ad745ef626a75ba8dcc69e049c8eb8e55b613dfe939e671660ca8c858aeae3accfcc7b1ae276ed7301582c93a58d499b464c87011b7ac39802ba9a97a65f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x66ea295fd7d5541346e250e237507bdd7a3730f5f712f6c037749034d2748eed52880b7862a85fb2e45746b2bedf68c87cc34e60b2042425dbfb65e172e5fd09	1622712289000000	1623317089000000	1686389089000000	1780997089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5b09630567ee746549f0c0f0bb3ae05a5da586945d834cb74a503a873f51094ea400c72b447fc1cdb4c96d84182e3af169dad2ca3be8633a772fe7174f55c90a	\\x00800003ad8f8eef722f53fb2d7c80dc103785a3919d2ee12882084f1ae96cca14a4824ccb01a1f14fc46091dcaf2b693756db72851024a6b41ace3d3ffdeceefa1b7aeab38dc19e9eaae8af64db5d58495229c46fb3e37b9f4c3cb57e3edcadf814b2b57a72d8da1da778c5e0e919998c77c68709596af5dc1a8bf5dd3a95ff0d1453ff010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xfeaa97d5fe4613c4cc62fb77cabedb11800373d49193aa988e260afd311e294bf624d95c357d3cde0cecbea71903e2db898e5632d1a261abfa86aa91ccb48e0d	1621503289000000	1622108089000000	1685180089000000	1779788089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5cc9581173b08f83b2d1349cb4f4915184937585fc39c981878a3baed7c93add0ed380e2a079fd07343633fd36c5dbbf92d7f3c65f489d27aa475fadb446a1e3	\\x00800003970dd20769d8e2fde767eea61d27c0d8e83d23f074faa082c401b134bbbeabbe625e42a9197fec737c8e64979bae93239e7b78f627b7f2d13fcc08a977cafe51bf8cb6a19aabd5203b37fad100f2de3c44e28b5a765f2f993363edebcf784ea0bb071bdf56b90e0919e3a0cf1fcd61ed69408c6539695d5970eed0f255ff263b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x756768bb3f46c55d87a309cecfa50e1831698f8f39c14588dcb4700ce878103870fa4675ccfe466988c2097e54ad4fe8cb61885d68470fe4c8fc3fd2bb8e5502	1612435789000000	1613040589000000	1676112589000000	1770720589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5db90105846eb74f74819f9f1002cdf8ae7170420dc37e26f944109ac95f1a78f6dc9cce8ec7df3fe164a9262ffed2447404a0bfa165782d39e38acda4714407	\\x00800003aef7554afcf1e6521928e10922c81fc73de4a83bec6f3b7474c07dc71dfe4a8e5975d73716d7994325ec1bcf12f4e7ab71b6ab5baf3c61872832587d88e8f5d4e8eef7e85e380edc442c9647f00f90dbd12c24abae79ff7b96816599c1c9fc3873ac39fe71ecf583e4948c08f4e34e20c8c236e95f4385ec6301554c41bb6053010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x577880f977c025c2e69c0bfd337905a82e9ab95214f06c0ff0473688bcd8b8af92913e68eca3ad8c6d7a7275dd0dddb9e31753e3f149644608dc7d8b09ec560c	1628757289000000	1629362089000000	1692434089000000	1787042089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5dbd25082107817b75b449bd83e36a379e4d0701c68a14c23efc93470d9576dcf6ee18f6cd4c1c3a53147aeaa8adc2aba197adb7a7dc9e8ee11a8a21f1f29d73	\\x00800003b6a2802a63dabf28428f3b32942a22a419e9f397b9351f7aef630a5cd8efd7028aef816d46b105fe8d4901161a686398a9ce20db488c5e1bbd6fde7375d764f88d3d2259854cc880973fb28692e0445e5082f4d363b2c8a81cbfe6133f6a4778005d644f1743acc2a56b5523f08542577adeee24ca1587f3e1881d81bfd90947010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6191aa0cc776c642a535b404b0ef0e04b8d17e39bcdf6a0d85a06dcc974ef90c230d73466876cd523e885aabca636649dc8c7a05fd40874b4c19c72fd2df9308	1622107789000000	1622712589000000	1685784589000000	1780392589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f291f3d163b16155c55c768af1470f3c3db6ae162f1b6a88f8c7efb56ac5680594d7437c21e4034325a1dd42080ee3083ec8193fc322e217c22d89d979f24ae	\\x00800003d3389e0064b4d18522379713c913fa5fc4db7d0b4d299f962303158bc729c02bf62a43e4344e6168b28989fef800068f04773fd3539d8b6f34213ef88428c4fb8e6d6ecefcf845e5204a2d8d3dedca53c3d36a6676e051568478f0b1a495c49ced588b858d1e6c2c7db86cd81e208f2c8ea77c248ce09081143692e548ff33dd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x975324ce23631e79273c6761375c9d36bbd44eb87cc7670e8095f2611991bb23e4ea760207578ed51a57fa069352ffc9241c36362da582ebde615d4186385600	1626339289000000	1626944089000000	1690016089000000	1784624089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x60b19f47ac96124b4261c198c0d08ab878a2175b5617320c8f66818d83e7fd3ff2e61e30bfb01d9e78c16996ac797914020916fc9fbc46ac2edfb386427e8b9c	\\x00800003b29d194c7a48d8d21e847c494231f622aeb411eabf5a28f74325c039e36b55ce1c35145c449239ed72249398bd7918c351add51603758ebab1367663ecac2e19f9e91deb51ac7d989d9b77c27ca8036ef47edaee0af43f0da7e8deb4e18b0940b88351c858e42aceb55d32cc6dd40230f06a42cdc4b81704df7417d11ac57a37010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x643613d4bdeaafcc804a67c309316ce564dd1efd5a9347416088c5f678c77c91469dc1165f8136882e28c17835d0d8df830b921ef7df6e73d977fe2b481e5104	1629966289000000	1630571089000000	1693643089000000	1788251089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6011ee56121267a0cd2334a8e973718013b00a0ac14123e600632bbd8fdc73ed4827406a062e5c7b384174f99e1ce39ff74ec9473dd5591d0e92cf007585c431	\\x00800003baee1690772a3c20eb253a658230cd37ea95bdd8fa196e23358fc41b894d059f6bafef4805f3ffcf25bb20141bd5ca02a6d31995c367afca1744b476517568422de2fbe59dcb0424565116b15925218cb9a1e4f483499b0b26917d9da146c99574dd67853d57e597f9526ed482c53d81cc701800f08550c54ed29d5797123b11010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd01beacccdd72cb48411ce836ca24ef2527490d064ddfa6bcb253228cd07ffffa504a4de47d9601b2d2774a8853d1b163388db2a7653b0cb7f38ae5c49e11806	1614249289000000	1614854089000000	1677926089000000	1772534089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x61fd9eb96f56f41fa1d0195c2b065a46e801ef87b0f09c3eeee3c7d9c11ba18f21ff3404efd364c0274537a003e2f1b7f5f28694505f9dca61544345f3c325a1	\\x00800003d5da7fbf9cf1f202a9fcb1be22511576fcee204b6580b66d12c11daa25057751a6f4f135f98849a333e7cb73a6a8a6737e875a62a2dc82d33d8cdc0aed21b07b1ef4d48d7a9c9233bf2c84dd0672ecff943efadba5a64706de0306a6b0436a601d234cfaaaee7463c53a38ce8bb0a4e236da79b9ce537197413e5d3886fd2215010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xddd0aab4eae8b55024539d8aa5a963d21b0efb03614aa1d90ff1b14caebd35a5c93393e8e42544b2efc9edd6b3329d4bebb89b593cb4ec029f345c1d5772090e	1620294289000000	1620899089000000	1683971089000000	1778579089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x61fd87dc691dbe0f4cfe40c262b2d83da7f5f21a7d04a3a0a2dfe270d1606e296664dc3567ed1c933a8e58248fcbd514308431a6f9953ebef26d28ad99749a0e	\\x00800003abf66dab415c8080730e29aa8fe4e73160656fe572f9a40761305e1ade005dfc65e67ef52dfb0b9dcc972d4ba7dd25083da3209c99df7b0822462683c05dbde7bb6588f396aa6c0d028f823ebbdd0bd0c8d213e073d05c9edda27383b9c56e1c776d847c7ee0b0c943827c36406e9437aa8a159dafb60e8b8b579b252d89cc31010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf95e78a321dbc5cb3133c262be98c0bb9c1d65e6087565b8bbb7d5a98d6ae3d9879055a363dbb0018eb76c6f59b8d86f04da16939fe4e0d6203cc353320c2a04	1619689789000000	1620294589000000	1683366589000000	1777974589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x64bd48fb2eb4e95dbcddd34e5ba2ec7582bcf929b9b484f84192a64601dd4c81180d57409891cc96cdfabda37e29b88529f708ab0914556be79c05727f8741bb	\\x00800003c59dd40fdf2a8668d7bd26240d84551013d36f41cda04e8ef967b0111272386f85ce6851a7efc60134610d5602d36a65b331a267b31d2f3fcd97dd756927b4cfdaf21627dc89b61e3d36ca4777d5804f74ae1e6ae8d87561437a959240a4b09c7237e310cfffcc7d005d91dd98b2f71f1d2549903d25cab8117adf0f88412741010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x499dc56cc6baa5e6a4e80a9db5678779e6a5d1200d2934bb772acf0a56c94d5783bb21cc6e1900402c86b4b5c297b5116bb7645cd893ec6e203482f78b2d2f04	1635406789000000	1636011589000000	1699083589000000	1793691589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x64092929a18f13f9777f46854182359b897cc32cee307383a5b4413fff8cffb441de845b1cdfee397c8cd7e8e00f18a2e19d721ecfed474f418be881b52ce73d	\\x00800003cfc33b87e3ae743479fa9f89a4199aa467b7fdd0da63df8b9c097d9cafb8b41f665d2ffef3433c8babf5a7f176ca84a6a02f0d2d32f7f18706915eaf2c6418abd94043ea40cffded6f637afc56fa43e0156eea2db60b3db8901ced741b9f7da427efd4cc457be9c473a0b4a7c5be732d1024b2dc285421e9688772b5fbe9f9bd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe1b3d20855b6c9f8024007f7800ee2cc46496f0e38779a34ed486aaf5a7c46ac76d68941132334e6b6d8866a4daa65e3e2eebe0528177888c810c20257fab30a	1637824789000000	1638429589000000	1701501589000000	1796109589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x642d19aaa52a50b545e74c188d4bbb4c470dc9e36b923e4bc6ee1b91c0ed7f2a74610a4db2152dfed2f0761b12aea6000505e85878ebe85fa95af226a9bc7102	\\x00800003c3861f3f0381f3c66f21605e5a2d9e6dacee0390e7364302c470e2b7d8a4f1dbec72995b9fbea59c561583861cd545c521fb99feb0c18bccaf69ead1ed498837c8731d3bbb10a6ac2a39e6f38c051e61cc063382901c429a829e1d3e8108438118ebe2555cb0ed1ae4c2b7d01b695a71f21d359079e1737428e0e8fc0eb8b28f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf4532e8b481755cf10bc34e810efb9cffa33ac2c2e05fd30d58dea949ffce32901b3905fd0229dbbc88dda90f7670fe672ca9de88784c2160b38b28b11d5a50b	1622107789000000	1622712589000000	1685784589000000	1780392589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x67a5cafd4bfe0d9c96db7b0a36382e39e85c38549da68002bee037fa1575ed3ab1cd045ede7b964d11d307885439951858b9f718edf6e98410e10941deac08b1	\\x00800003c16d787b7cdabaec2d94d59ce5040cf36c8c0ea9b4d64577ef53e6801896fe5fb49ab0d61bbd04e35f21de1a4917cca6ac23a0dd94cea76131488bcfc85decab733194c702ed0ed61b8c1f68bb1914176f3097623c12b38f7c5e005c76af08c1599adf06e76e75f41cefe2458a6e75c630864d7110238e399e92e6e8a89ee277010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x31c9077be800a1e023c4bb1839d29ed6c3131059d6b8d1917666203679a57c129f57130faead00d37909d7446d670e0a6aa123242a487f0f86601d52d2011a0d	1622712289000000	1623317089000000	1686389089000000	1780997089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69b14fd9ee32dc7facccd480d8ebeb5b0471e72f2119ec4f4d31e189ad4907d6403eb83c3a5bb67b62b4a51158aaab16d2512eba38926907a9c9a6d24f25214a	\\x0080000397b0c9e1a5b71882936ee47e0b3fc72e4e4db640f7d0e91283f6dde0f4e1a08dc81ab54cac556e6ce7ff7e9bc851d5d7ae8cbab04c647c09556cfbc10faae9c571b8bd6014ceb754e8b69f4917c1cf98e853e4f4f6ede1636de7a56157ec49404fa6b60170a83933e96fbf64cdff898396e3219b73fffac6276d5e2cef9979c7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb331ce6be2354b30616ffe8db886d8f2c51b021a2a33c2c7df9fce6dfdbd2313e40c125eff67dfb0c32608801d7f71eea0740f6dd44194db9ae207395c8e8405	1625130289000000	1625735089000000	1688807089000000	1783415089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x691d730589f8cd4ba9b6c060aadb8c86204c1927f01a9de42ae67241b6c584388801f60ca32a13a4799624fb96b8b18e3d7ea2e627e1e18f085e69932834e750	\\x00800003ceb5e7ad7c77d644b5ba22dc49ed952c79535010022daa4cbfd5afa25e7e43bb67f31d1d604e8a143187294ae3c19d8d00dd148beb097ba81392c09ba60b45421d9bed338551e9b9770e5aaecd63f062599e935cda4b3a52f7e3664542095afacc8e9935af827e1105ab7efa7a3b6936748703e8d7e122343c777053d60ec251010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xad7ca4e7a996a7fb4cdaaf6c5b7ab34ea686252f6dc603af1f44ea6ec2a67cf2254a88e3e30ca838ed6da026df35127ec3598bdbad0765734b81d85a09fea20c	1617271789000000	1617876589000000	1680948589000000	1775556589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6975ba574c6b1f2a18314e2938d45a6340eddb5742754f8a9dbcd867efc1a97ea2d7cc1ae8be0e59c4c0992a938ae2dd867e3bd937060d82149c089efda8c343	\\x00800003c2b64f7c5bb45eab74fd3268f2f6937e6b1caf54e0ed5f4c8495d39d8e611c16dc597b6f337d268c5e01da4f28d54448dc014cc39064e8b0db964d9aa0212b14d7eb68a4e13b3fea5d452f0be913e9174326b4f31f7e1521e4de86b146df29fea42046e0653ef7b554f24141733b9a96f251c4977a1b68a71628bce140f53d47010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf8a6f4d1607a4cf8f585c62a5ca9c63f11b39b272a4e8e63682650881c8c90b762363d83ae19198e0fc01ef64094c0c1f46bd39b7dced4c6b1f07cdbb33cc306	1634197789000000	1634802589000000	1697874589000000	1792482589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6b4100a67b282df9c611f521f2ecc1dc802dca2fcd1ad2fb9dd4b487b6d55ffebf1c7fed32e33cb4957cc8347b8d7f987ace50489219c53b1675a26821cf3199	\\x008000039e6a47b543013b00b877924fc3e7902f5643d6c34fbeccf8800abdd8f81c3af6f360927ae96ab32cefdc17598010d258e401680548673a6c83907882e82113a6efba0dbb01890d2f513e47fb17ebdbe71a2565ded7b7c6d5526f0c20056ee71290f550f533d14d06b00dd098bc778106d3e1232a8c5567a8c3cfa4ee2c304351010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x48ff64fb33f9d29e620b2778b353a3ea32f03ccf8f7cc8bfe87de43c32510fd57dee484c9f4cef56d0b4c1eb44d160115f813b59e1c352fe7b55d80aedfcf309	1609413289000000	1610018089000000	1673090089000000	1767698089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6f4102425d2402ad3e496b54aecf0bacbfe4f13e853eb2e4dfdee2807785a13593c64d098ee80b7d31377a8ebb7499f4b749fc7fa13c7a4c67c6427f386706c8	\\x00800003b414c34790b43b7df227ccd1cc65ec1a2b09f535e31d9773246e2beaf22935abd8493b2fc61b905375e3df9a3f38dd68879729904fe76d6e88be8fbeb891245606d5c88965d9c1de74f5efcbb6ab75fd6b3601b4e52d5e364efe00fdbc68d37f44059f005967df995f7d04e4b999d30a41d3a7e3b98f49ef88ee7214f7d18ca3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x035a9c17807fd4aa7f9d9a9229cd583edcc1aaa4490f6598ed83922b60e529680ff64d1c84d414ecb9245da8dce250e64ce8eb3f0e32af0c2dbcd0f9ca58d802	1629966289000000	1630571089000000	1693643089000000	1788251089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70bd2ae10e9e87d29eee420c2de276578df6b013113fada7a59f9e20dca9f4ec67ac006d518841d37b98c0e364155756d683d4771cda34d748fff70485975d5b	\\x00800003a9a459c0d031471c484d8697608ae0ecdc362148f2dfe802c032129482cfac0951fd44c67250fb1c047298917d97218fde903d908623dea1da1b4439f2bbed8b904ca6ad595cb6a65d8ec2c1178896c3ad200c8d759dc4f4e988e9f5063dde8f05ea61710cd73befceaa004e7a624aabdd050caf50f3a79be33e585c2c479931010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x194b811693081811f5d67b7f099a97db1e35a7fcd510cc68bf649f4c23574dfaa46f10f9e69cc56b638c68a5c415174ccd1364dfd22e2ca07c5d0f7f28223d04	1633593289000000	1634198089000000	1697270089000000	1791878089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70ddd37ebb7cd71fc30b1c8d9770ff87407cdfdb61b8a76bbd91870415aaad6084f9ff2cb12ef8c262d36816768221f9545baa87fb3c38a8e8f89ee05cb531ff	\\x00800003b8b985fc3616cf087de7b34bea20f2a05bf49db292bd066ea9b0d739564cd27c1cd9f2e9dd2edc62ecb864918cc904bdf15c5536bb5b83b0d157ac03df176511fb979ea9831a6b09dfa3a8bda7a756ab36f2c33f7d9982a12f80e38e5c2bd1f6cca2adb3048986dad8390c8d9900095c682f1d60b577e1b6b3607c19a3e029e1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd11f06e92b61f5176da609cbdc8ba43a601079599bbf8a50555e1bfee5f5321fecb41b656246f4f89cb4cd0c50b4518c9e61505e27ae127d1d1561d6578c870d	1611226789000000	1611831589000000	1674903589000000	1769511589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x710de21d6a0f1b65bbf31c7029cb5d86f0fd5a02c21455da61466be5b31e3fbbd0d777fec4d483dcf413771651e368e0860afc7687a670ec60c555462569699d	\\x00800003ce59a5fd5bc2395e79ae3702c1f8de7ac32dbefb4734dcfe737991140d7afbff7dcd026dfa659a5b403701456338427fbdb79d72d1a61be6d9e457d88f14aaa547d1f7326d2e1176c162b6bda9fea98a1de201d9897feeedac6b14e5094fe4f06280b9c5adc65518b31b0616c0d600cae32a524c2979ce835645e14a6c6181e7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x467fdbff2015081a5e3a061fec4f81e1b476347322065eb9b2acff06498d92a9fe1b455be73b90993de533433ae9e81b3972f4b5e3e45aa06467ee90a62d7b0e	1628152789000000	1628757589000000	1691829589000000	1786437589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x72555ca16566d63134f89bc7206f68973fb839596691105ac41bca6e7f1d66946b6bb1be05c049bba73396a9badb01c9293c647136e2c3eabcfb301f968b3d72	\\x00800003dbe137eac629f17b3e46b79bc2564436d2b4d660909e369480ab9aaf9ac6ce8c7e6f9768189d374b1b2cc0bdb08623fdfee11ebbe12396f9f38dce344e877a033b67f7ff5ce6f38bc08a9fc68975bb556930ca14aaa73b0d351f73e13e28520b782351ccc972cb18a201896f01ef358b27c209f81e621228fcafc917b76e115b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x29ebc97173c88180848d77e7d313b4e8f7be08edf221f346aba57d2d6bf4913f49ebcdb6bcf2651f3748bfddffa2e97dce53ad8d456dd7e50161ac0585525908	1630570789000000	1631175589000000	1694247589000000	1788855589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x772dd001d91574f43bab631efc169042153c83c4a7ad998a5acac19f17c35f0a0d41e3b4fb77b949516cc1e700608182e60220e90e3b85e555cec584aec2ebc9	\\x00800003d1f6e7b54437bf867b5503d9ab96205c14fcb9e328715049495f97cae48306eea052bd2f45936e28480803e2a337f4e9fa668a4f88ce897b6c854c41e07ce94bb8fb26c4ee4e114d452654e46d82fcaf14d46f19f6b406cd2dc86bef634a7b41ad53e70629f86d869842035b1f69ca0343fa11fe0579b69c28f953c98118c88d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0b50d192dae58c3a3d73e36e405508240a055745dccd83be5a0e92cdca726c3206b34de08f6e434b81e9344e3fa7b82c44ef8ddabace9f8004f6b3be226a8305	1638429289000000	1639034089000000	1702106089000000	1796714089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7e759b9f857687a55ed6eaf40f4138d1fd7a442e4ef9d9fa5987aebe5e4ac613a2d609b643e5bfdbe02bd7fc16d6e5f2094a439cffab05aaa3a750dbd7a8a7d1	\\x00800003f19be77f832353469168f2dddb923c416296c768eecb12e66ad44d537cae6d041a207c3892a7ead1d5312e1aba7dda9fd9dfd6cbf7e727ae4e09ab1506ac98f9064cc184a0843c33eff79aa0a25ee2a81cd8bd18a39bedd370d24bdbf289395eb6115c8fa24a70bdf86fae6de98fc535cf0fdc87ebdb98aae89e3e66820d689f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xae487d724604d3e881719ac3a8b24875e99b9d19f5bc1c26ad7cb4a139d93161b95baf95f7662c81877237c1e6e297833ed518675c7e58ec61b899f0fbc13203	1632988789000000	1633593589000000	1696665589000000	1791273589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x837524c067d269a71989247da9511770af3d597545a940465828d33509a829fa7f93c7fe985dcc934c7a7c2336e7bf3bebb63b687d457b300d6f380b344a3149	\\x00800003a5cec876d7332885bfd176fb9cd7f29a7301ca8c5290447c32a89b916d47467bdd720d82adb58bc8032c637825c67444b87abc3bbc9c3a376811270e620fa13875cb0f9232501893c55fbc81fcb97f23558e18ec0141228609e7cf0e1972c89940bbe818049c6806e5c77790de7a52868f517fbfba21bd9d4ab0ef47af7f4411010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x60449a77365e3126d2654b574e75c651615aeb7752482d2dabed0a87aaf8b6e78be10b47eff0a1762d65da41f21613674c27c492922350d8111a5da30b4e530b	1624525789000000	1625130589000000	1688202589000000	1782810589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x89a5163123e142c8274ad22aa0a54f04612773625005ed54a982637d04ddd7790fc5c9687d5ae34344c8c2a69efb4d6c2424a45b20f0046343f895c43c5d7042	\\x00800003a820986bd22e5dd3ddcefa7d16dff7f9f08c582d2bea06988ab77015e5d0e93a13b2204b09d92d5bc50415d033f63d1552aefeb11effd66f7a026cef5c0ce2692031d41ced116e9b6e46b6c0df8e59992de5042eb01d2924f40dd7d02df46078408bdf482ab166f46915153d7e7b64a8f369efe6f65fa9e4e717e00960bc0997010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe435cc5ad6f8a8e227297883ca7ccf335778c801aafd9d381cee61101f01d127bda64e4bec6b5b5385afdb033ecd46af4b452d6a7ed04e413abe89f51b23520a	1639033789000000	1639638589000000	1702710589000000	1797318589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ba9c29d217945f583e9c906a96353f047f500d5b503da74e3ad0e8abdb487795888675263efad35da441e2a4539592abcf73028c71eb73c14c06fc94206e1be	\\x00800003b55fa8e744586d7d2cd11e6d48edf51fc4a3e1dc1a93a016ff58eb2a4f998686656d993ef86cbab252e2a63a8c981bdec0dc9148807ab7de90b6129d82742cd9f813657f0117bbe630a3d42099770055612ca658fba22844bd61d3b1e2b525c83f7f1324734f9a6810ed1c27ce7bb96310602f3cf33f91257ee6727d0355db3b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x48d380c878c5fd3363d9bc28d3d45c387788ce87cf005756e56ff6e8e9dc57bebf4e579ad3325526852eee798bc9f56b81e39a7935943ca88daf494e24787400	1617876289000000	1618481089000000	1681553089000000	1776161089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8fa19eaeb42f2fb86f0b17746a7b4bf20b82091a75c177fa124f132c5d80fa90422f824fd073e9abe1eaa88b92aa4b4ee40bed9d1cf67b2a6696f87c586c2748	\\x00800003ca67b0b9b40a8faea405f12609d1933fcbd27b12c8f634d1a917a8b02c19ecb4757650d1edf317149a080c9891c7d414cb93b41a2c6a2e8ba31bc6ed048eada2fd40244c107f22dc0be695979ecb2fe1b493147972907e007e7833d9ff404f4d0e458b0040ce3ef9130fdb0c1fd1237144c1840647dc126631d63382128ae27f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5a9f87cde336e975823441a4845e9a56ab81ea8b34d7c932cafa912cdce71b384af1e476d2d22b9e7041c2831ae943a60714532c975d35f9201628c25114c707	1611226789000000	1611831589000000	1674903589000000	1769511589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9339f0fc65dc8faaf66f3c8a5d8845afbe6d3278656613059a6a817a84fd27a42fe6ff557aca6ec6015c83b491fcaf8ad76b5b76d107003aff4c67df82ee65be	\\x00800003e5736b103a14b3492facdbbf6857a771aaffb6f5305cbc6b60aa3f5877a91d92d499d133afdd7b0a3c82446ffbcfb2814e60732e6fb920058043fd95257e1d73da47b64b916f593a77b142057e9366c740e718421f8fef4dd4575b8c7a1018bd3fc4d7ee490732fe75f06091a31396ff087d0afad044058dec63ab9f38b58049010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4224e71fafbbc94e416f4e1253dc989532e8ca4ba3f49846cde3a146585d96ee48fd6d21e7f640c6727ea14b742391b82400b9e7b0a5286fcefc0d5c92cfee02	1627548289000000	1628153089000000	1691225089000000	1785833089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x942504a8ae7a8f9a5c57cb4ebb83b1a25d816df33116f4c53b83b8feba20ec586004122caf19d576899917108cc639864cc4902fe98f5c08c8e978cfcada0d1e	\\x00800003c62059f0682287062ece90bfcb81dcd4266f6ba3285b2c25147ef96dc0b9a41baeae7dfacbc779a48aa7f895d58f50cc141564d99161903a671536c6526a76a49f4150431bae8c8ebde3b3d90495b15859ecdf7de5a6385fbd031adbd055f765acbcd9502a35eff791ac648fd89b382f83089f4cef627a4629540be1cbd78d91010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd442c24ea529bc9291448bf013b8f879b79736ddce65d25a475bd5105168d28eb6498632c61ef1415020defbbc4404ad9957efbe31c42dd7bd1505e95ee2030e	1639638289000000	1640243089000000	1703315089000000	1797923089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x963db68e2b66899beead0bf4684c9eb901fe67531e31ef98b7b71f2a1060ee82d55c89c88fd2cb1ac7aa3e5e80668983008d9d65771b308b0b5cb2457b20ade5	\\x00800003b404adc98fd033b965c3fa82e4a727912dbb34dedfd0e677e7f505889d993331922f7f9f1d5691480ebcb0774c79abf664ddc95a3765e86d4c30f0d7fed6be1036ae631f3b950dcbb2d6fa3b43806bf7bd1391b9bb13f340306aa4559f89194020b1257c105990dcea94b14de52bd9c80fe3cfa161a4f6ee0d1be2b6657b50d1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5c76be39e99df87f800aa15c64151a65361276aad717ba035d7d9037a184dae3b4a9d4edf4703e3bf35db149cffb0b20d98bf28669e075d8345d1005fb8d8703	1616667289000000	1617272089000000	1680344089000000	1774952089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x97d9481fff5cf26e18281fc2d990682958c8496eaf468267e9e3bb7e70144cc8a12b5103b79b85e9454bc5735c9f14811150851912e907985701ead093392ce5	\\x00800003abb75e74f3cf3a3cf25e583967f1c9241b5c0e5ec9a5c7822caaed8dd46b0e6d16adab9b365870b6579c8bd70a9b09868f42d5783c3889e40ed9e0dc15dac5615677d12ee76ca442478fb3498b6a312931a1c3fd7186eba3c690f818f1691c62f779e51e26c3cd852b9fc34f3ce67a84285f368d9cba8927807150642ea2ce55010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x792449e4856f5649cfb3486747072bc22d2063c158246401f3c6b424aa40e1400e57e0aa8ee7cad649c6d1aca36930540aab31f0ddb3ba78c34e558f15e52a07	1634197789000000	1634802589000000	1697874589000000	1792482589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9951f7dbc4c032bb3a348844840eda9411a391800d1998f3dd5c81355f737ebfe28c81ff3deec3adef5b8a14857041f37cc18156e773aa6ebf937c9f3666ebf4	\\x00800003edd131d96426a7ff01d7e18f9f53a3dff2888e62d561fbcec6b07ff7cd3f230503f91b4c170a3ef527a4a449f4f586c8fe246e1504e8c424f745be2d6662977467aeca705f832dfe1f7b38fd86d6026ddf54cbd45a2a2a5eaead345a80887b281cdecb0216e540160d21449d94c1f45795ec3de52d979e3cc96242053a9e1eed010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5c2a2eed6a5d1768414ca9349e58d7eff3453895f1aefb7f974478cb9fe9d4ce97d64b425465f48bce515bf93a8afdd7de84680c6a54a0411490a0eeb60da502	1627548289000000	1628153089000000	1691225089000000	1785833089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99895433646a0cb0b655a823eeedb74b6efdc20f6a6c3ed6a3114445a35cddd9a105a51d12c54af5d456028cc034709f7d61161e9c69d78ba56fcc90046458fd	\\x00800003be38e2fdca76b010091c3f29a36a5804c377054a2c9235ce5a7e1d92a7966bfb18f04bfd57f297334761a75f9788ee4ffbd53f7026f6bac26a5a6469200d3e04bf627b98b4966e42896f518af148ad8b9ff60a7aadf16b9e2f77618c47225d3b7b47dbfd564741adbbda107637a16c2c02fe5e39ff7bd6b1a3486cdfbb504c93010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x83cff95de4021ff1486e945bde13ca7cbc7033db7037584464cc091ecfca3f3e3575517e5803789874cffaaa8c3f4f542a989815616519e483bb65529c582e05	1636011289000000	1636616089000000	1699688089000000	1794296089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9aa9354f44c53e4d3dc2c0ec6e9a0ec96290457a0185424a3ceadc34335302d9130334a29f9b412b667a40c1621fec200734c6a88d01c833910796fc906cb3e6	\\x00800003c194d2052cb5f73cf7c4ccd898266d1ffd3d2ad5284cb09b6e2536434fd23168ae6588e860cd8ac942b69e424bc656aad1b03f33ef64f4fffebcc2e6893d9a54cf022bf6b9009030d4a5bc855b2f05044a5afa00e832fdb2120d2c3661d3b7bb98930aa848fccd656a6f47414e4725f36e76e30f4b979bb2a1615d54207cfb6d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8c8b3337061314e1c2e6f105a8493bbd46d9ab114722a79f43b10554c2c3d080ef772eb1db42c9a2888b3208e47a02166db6b5d93c04ad3037727b677674b40e	1626339289000000	1626944089000000	1690016089000000	1784624089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9bd943dc08496d09485a59548b7866449f0cc11a50cafd07c81fcb19176342b2327579be8949efe885381dfc9e238c86339288cdf07265aab3edda9da4940716	\\x00800003cf24b86d54d68cf6911a030eb559f3e21ce60b8751e1dbf5a0c558b66ef704542114f1d34b17f9b58ffe54a580ef53d05f6d0a8806b517983a8b2994b138169bdeb5615d6a0fc668fa336cbfa0094fb30821ef36f0fa8b4250b7e3ad93d8353d1c8db2db29a5921653b9f05621d434e74544707434edeeffd250cd2e4e3af03f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xfb9cdc239616738b3821529495d302c4d96867e6ff290f07523b9bc4fb58f7214a3c3a97154b4ba7cd2910df3a75c55bc6d749b98596f619b8e5b1dafe1fdf00	1635406789000000	1636011589000000	1699083589000000	1793691589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f191ea8a79eb3b91268da378ced532008f1d1413efa06db873f3131e5d52d9b274cf4589d6cdd544ec9aa1efcaf97e0ca9bc551910afe48a82f0d99faf36e13	\\x00800003b1817a9d4369830915aaa6da00126f19e69bcd4d1cc53687bfaf32c3d2a19ea6e4fa887b82f6781fac971d177d1dbd3e3fe7b11315a466a83785275c98528e3002c91d37fdc44e28dcb5f97b3a476083a4b7750eaf96c8e2d07a9aab679faedb5a1e7c63aff00667922c304dfc619ed417ef6f51adfed3ac6e04ef6d2e375dfb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8841819aa5ff0710f9e33436bdb6e74939dec1496f8d4f7d3fd45ef15493a7ac36745a529f7a6a091745ff65c8b7440ad6a8c21f067091a4c06945888d3eeb07	1619085289000000	1619690089000000	1682762089000000	1777370089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaad91a04b72a743953e2e27f43c2c0a18a6cdda7427438221b2c4ea3a2f123db450df715789c857069185f604d61356b774d2fc0b02f9d276ee0b0b21afcd998	\\x00800003c721c2b902ba6ff392dd3c02766a6e1bb5e149b12ece7b935cdd194cb1331e14d390087869bca179db7cc30742fe90e9bcc8aaf1b2c0add614dcfef265c093a814b7abf543e8a4ca2e1ebd53b84bbbea3e16df16fb0fe425eee0579a5198979487ab5c6b5dfe9de1d74ff478826a8cc0067a5586deb4e46e964bc5f7c4343d93010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xfeb13fb2c4fd55caf0212ccc61ee6f8b4b7e28ba6ed0e6dccb32639f8370978a317735118ab3d5946d55444c681079aa504d08376df809f81e5fb72351d48f04	1623921289000000	1624526089000000	1687598089000000	1782206089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xadc51dc10a92c47992b4053e5cc40c70f3a8cd0cf0fe7f89357bef20ce9c96304d1daaed4e8b10bac2fd15dfc9d7bfe895053ed69790b4ab9014d4386f011005	\\x00800003d9fc585118e3fd050ac547f7a2ae13b9e57c2217082c60d724a61fe6951fa3b5d64968d2eb7aa94642e91e7e282e69df3c18edd38abf01646714d6691ebb8903a86b9a1ae8ecb748e9cfae12153c736da96f165aa891520463d347ee2f40a8bbe5faa9c1c9e3942aac2f677f1ee67ea2610c7ec8247ed20b2f12e859b1c1231d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3b483f95986395281c1d2190b36d454fdf5da4a22b85cba7d3f74994f3af6cb8e50b81ccc0216ba921e6d912adb54069dbce2f9c7cd9b9ffb35e96ce914ab50b	1628757289000000	1629362089000000	1692434089000000	1787042089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xad2d2c1f5ce1a985f2dd5c11a2db01fc850bb6baec88bd38bb0ca52fbe546d587b899df28c9d8583e322cf48f7db47fdde8460ea608e6779280ccfc9a985ae43	\\x00800003af500d1267922a4d6bb2f9a5b7e2895cd142fe82f7602967c43d2946d58c3013c302238756c0cef0574bb0d5abd6bd159ea23c2e0790f3fdc9fe733a8a68ebf6e6fc3b1a4b7e0f4d32d05200f21a32f8eb8c35e521686a1bc6878af62005f6b39919acc85a19f1b4d408f0bcd9252a7155fb2862e523ec22c30a4340f47c0e8d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1925e7585a7b2933ee09da7c9ab0095ff3e110c582341b6ffd630cd299395cd89a37807a4017b4d650d83285e79e656086a3fbd136483ab7ea8e72b26992d30f	1621503289000000	1622108089000000	1685180089000000	1779788089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb551ccfb3fba26c773a1db7f707e99b88112289407fdb0c7646c6dfd4ea195c52fb97590576ca30bab6cdd83fe63c378ea7af83aed9c1c60630539e0c04bd95a	\\x00800003ab2146a10a1e7587542d11044f325fda5888f34747572d9ad6f11698586c08338c1c89086ebeafd27dbb88e47fda44c3cb2fdd89a0683312ecfcf51abd508cedfe6116a95a7b3d9050ec0591e773b71a8eb69d0f362b31730c55b1ef10d86ba7159068001fa524ad74acc71003891d42c56c611e69a22fb655f6e5cc24054901010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2d38b3b1ac21d8decee88a7d6747acf2be2bbcc29d7f05e8ffcc806812e8ed35ee6bc839f6d06c579860b8a24d5a6889923d4bb7cd1d4d8e07811d1a34ffd305	1613644789000000	1614249589000000	1677321589000000	1771929589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbc097cc06563131f5491f22dcec00d78efb2017ffc340070cd2b29420d6b56f27cd81b31e78fb2602aa3ff312d0abbf9edf84ca5dc1df0c516bd1ce2d23b4357	\\x00800003d17633a27bb1366f71514caa596f02c42a9a3c8a2b5606177b3df0f7c12bc020d5feab74f7599d99080dd9c5434d1761d9802d68c0850a98099ce5094c340ab5f9da62ebb49c22495b1d3571e9a322bd14b24c97984b2c194784815f8e08f7c8932272a3fe97eaf27e01c3e4b113cade0838f6dad60476a1436fa5bc715150d1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9ac4cabf1029f0331d2531b5cf157a6f283ca648be34f35d40651fc84d88f2117aa81cc89160645b74caff0961bda1834f91d6e209b29672dcabe63a42651307	1618480789000000	1619085589000000	1682157589000000	1776765589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc07d6832f28af34815906f9de39f209206fbbf03b1d33aead2e16cf97ab29c75593e9b2f39b9ae58eab625bbce75a2ba929da473dbb59638eb5a68b3dfbbf2b0	\\x00800003a455b26eca86917b876f00ed1fb81c323144ec6dec89f24e0463d9c6d44d0a7a7a7ce652607651dfe8e24a5a6d2fc600dc96caa16f0d682b144fee18bb8ce06edb2f6c7cd524b0d1674c32e8592915b7c4244a3db159baab5515c60359621927dc047b9d883dbdd117f4cbc657ef28ae3d376483d5cc4729d6e503c514a827b9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xfb69fbbc694bf227351cd78185b3bdae525fad35c4a84ee64f700b0418e0fa4a3eb917236a65148ff16ea2936cf05568cdf0e6eaeb175b381d5ff5f46a82d808	1632384289000000	1632989089000000	1696061089000000	1790669089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc30dd993189c124922cac74647cadbf877bb6f4b64d00df55525fa14c66892ca02b079fa65173ced84d4969e6b8172525f0f4a5932e444af17b2c3058c18488c	\\x00800003dcee0e72f6b73f8d6874748a5d8f4e6b67c55934d8f8073372daf78cccef9f64b25fb8913706085c53cecc56e5655b4445af77bcb626d1d4b68f2accfe57de922902eaa022278b96c0ac8b8577a81da771520145a9bf971a19fe0f0d70ffa510648600e15fe9921b9cb3c64230a1ce0870e5c9d80f0f22cd6e07938e98153141010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7717c19e612f54a9679eab8a20eb5a9d4f67a84cf7598b43949bda3d010abf863d6108f4a1e4784b156e4fef2a68b7c605afc576fec4039a6ca5a9bb28e3f10f	1623921289000000	1624526089000000	1687598089000000	1782206089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc331c36a8bb2bb75df1d25029cab542ab827a38745ce211bb0a7f522a1518a744b02809f30150c008c60f483e645e176c01d1a804ab6c79d5b171abad6d2471e	\\x00800003da7a95efa30f92aeb7fe4fba21c6fd0ca3a42fc00beec60152ad59edd8b8b29aea8281222f2a82bab6557e823d3f5abc9ebbd29866aae8e1f6143606c1a85ce426410790463c4f60164e2244062d88cb21ff8f8dc8ed4d2a2443cce8d1fda9e40c3c581d07f73362304eb6bf416bcb9902d76354a33bb7608a4f27cfe7989017010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x83dbb0ce552b062272a4555a125f42e083f79cd41b6c5f4bc6313afafe6e96e05f20c3108751ea44024f8c5a8acc4306487e0eaf462c78f061035e26ff000906	1616667289000000	1617272089000000	1680344089000000	1774952089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc52dc10352d578c5311604aa6d398b3cc3878a34afe2929bf1c8916910f0301ed5ce836825a13a14026e2d1deedaa9358f6a619c787701aff1384dacf0ff1323	\\x00800003c0331fa5d8a921b8c65343610422b7b05818d02243c02fd528db00e4363ec1f6a3d83c708c39f0f034eed74a2c49e49d0f9d0b3d193bbb351da97c0c12b5a5fc69cc6b811cfe4a879691f57b195e3e53442f07b98b8f9dffa45a2873577ed4b0c3ce7918436aef302fef878bc55d397d3f57095e337b301b0a61a5a527588daf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x716c741a2915d478f5547f0c92b84ce16c84fb2691a1085fed930cf87589fd4478b52d13eb41b7b6627e42a43273ed69fbc1acfcc574ffeb4d700b4db65a230c	1613644789000000	1614249589000000	1677321589000000	1771929589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc905689ccd3ed8d5cdbaf57b40acb60dcd0dba66d898559bc9cf83255b8b1f79df94f08bd68c3dd16e33be4f1f4afdcfc72a37ec1b7d8dc1fe60f285eae1d062	\\x00800003bc81fcd6e93aca77721b9019e3599d0e172f9e391e20861f9e4a1ad02f2ab4834c1fdcaad4496c4ee240a063c9b67d1f043c86122736e14b34c6b5176f155a178849fd9b5b56fe9892661c6f1efb73ea2e4f7c635079671fe3e0e9af6aed685cdf02b1e77ad16418f48ba09f397988d563b05d0b22ff62c4da824bfbd02ca70f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb522133293f711c0402479b2764348b015c75b87d5b81cc8e80a91a4902589e7e3872ef3d3d83a52253171f10400b71428a0de9aad84ed7344eb4cd477fb1806	1636011289000000	1636616089000000	1699688089000000	1794296089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcb2dd39755edcdb6358e3a89d79ea22e6dfa147abd54857676f9f393871fed1e2ec8810eaf07ecc427382f069da590a6fe4381dc6dd1174a74977c1bac51bf27	\\x00800003cfa83208edfc047480a798e254669c6b4bdbd015974184c58991a7f78fc682df4d3a0cc50608dcf3467ed1771dda203bbb82a9ada89f1772b4da64fad5c298dc3c4aab4ce384b6f70269a8955385058ca5cad6464f6d4dadb92251915f736d42f82eae05fabe0a8d8be4ff0bbc50806a9bd6818a379d102694364e8df1c4437f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdbec607d77be63f3514cea6a8936d6f2aeeb28b1cc0443cb871816a0ec53d4f896330922d6d0d4f5d3ece46f691f7c56789615a9838e3671828aec23c427060b	1629361789000000	1629966589000000	1693038589000000	1787646589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcc59e766b6c26350458828e0c80e816b3d57338a8cd45c5c6d76ced48e12219360f9a41d485a76b0763de1592d01ecc52c67726da945d543df58f50ad92c3746	\\x00800003bbb586543ca67027c3df14fbc62d5a103691b5af237c4669abe59ef94003d992ac3cae83b018bbbc3581090c32918125083988e7968d074adcd1983cb1c499997598b57b7c894d1e136f87bba48a8d4bbfb7e28a0cb392c887749794eece4b9f77b56f78e1beb57cc36f747ce0fe43877ec58d47a4c6734706e3272fb567e96b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xad63d857f49aee95106b497b833c481ca2663fd27c24de4df52eef734e662a335cb04c99269ebd36487536f3b633d1f1cd9c7cc795aa1128a5f945cd20593d05	1619085289000000	1619690089000000	1682762089000000	1777370089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcd9908c73cc5da9da1247b853ce7fa3f636303ec4f0d51b6ca617f90cc03a1eb3e7f18fe30ccb303245ff49811b4ee91192733480998bcf71269e1c4d3bc213a	\\x00800003b8a040bf9789845324d0e25e2db6a2fcb8314834980b9c68c0799549d9a0bfa96f2cc9d865054c9e78ef5ddd1be63ee45e3574c506be26592cd2c08fba02ad0e1391e3b531f5a9807d909b09a18bf0518601c7b35283ead3f0110d23061c21674b9956713d912aa07b519f6a10dc3a71d984493a42d2f7294461f1d59c827a67010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xabf724268fa5345a62fc1ebe34182f2e5a0f9a866820012f8c512124f6dc714eb82261ff46e0e8c70a67ee0ee9cc7dd5ff23a14065cd9acf9a55687ac85e280f	1626943789000000	1627548589000000	1690620589000000	1785228589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd79728187086fbc33b4aadd370b12518c227253a5e0bd945241b8b88acf8c079a0b7d160ec8b0a44d2899f2dbd85282144362560021eaf232edd6c3f39efebb	\\x00800003e696825bbdbdd12ca618e4024e3edc17bf50ca1a3889517cad0ce7b2fac32e011fd662f65d134899c1c869e8fe349d83b1e959631c4e43d43224e6d2fa4615c8838a246a584e6296a70f2637499e2a20dd1de2163d6a98589cae406a3c855bf7362ffac0f016ba26801e5c51ce44e59b0ca159ebd62f9a668e5811f474509167010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xadc3e9279c9bd3afb99409ac20c2c209c3319de3422451d91f86e21ac0d5f385fdf1ff65764e4696e0df25755931d29dfc0fce6a57bb8ecce5360e8b3912ac08	1610017789000000	1610622589000000	1673694589000000	1768302589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1c10956d1a3f07f0a477e1e0ee7e48e9c992741a416535ff2d47cf49fb0983e079df9deee39bb96902f5dbda67caa7b1d997bc50a62def0379aca4ec18b81a5	\\x00800003ab545f071bdf348e99becd5b5b4730023eb4399a71c5cbd383f94bc36806d4e1daf6ee2c7f3bfd154feb92e4c31eff8626f41f1c13a5220590c54742d0b50803ff6f7b6a82975b7257e028ca6a0963298e2a193919ef00185697124a4a59bdf3693b8ac3dfcb6f8fc5d8fc774d2cea6fcb3c6e1ccbe7629b39757bc284ff6669010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd8e2b972687e82b9c89bdae0480ef5ca9c962aa1f25dd455a658d83e18175ed4c748d5e807a35ce20d6ffcae8abe54c2e208a96a36cc8bc5274a31058731a908	1629361789000000	1629966589000000	1693038589000000	1787646589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd30ddd62d8db10c2b7efecdedb607796c01c6b7ca0e1a18b8bae5a6a3a7e0d1b2815f21a98eb69eec4a6288c27ec53896887fceb8e02580a74b2a28ab2619847	\\x00800003d231466b970cf6ff91dde5a97334c4096bb96d7bda92bef865fa0f2fc3686f9b3b1f797d3da9225f4a458cddc6853fcce8ef56b6595f5808873e2c232195826da59df697bc5aab1b2acc867c3ec044af4a6230679f1b0cbe61442584a46ac71f6db637e611ccc52b1c58103b1d29dc2872d706e3cca259b0335829164996e02d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa66b415c9bbe4b5e70fbb740c1e5bee622c1e5d5ff1440819f4183a3701c05d3440ae239240aa8429f40ca3a372a38272b29f3c1126f36be6d57b70765201004	1629361789000000	1629966589000000	1693038589000000	1787646589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd3650f28444382145bae97a34b72a3bade397cfdfbd2fd1f8e6f527d0fc58e9134e913a67b3c7f9b5d808c7450850d2deaa1cfa47c27e0e63e98e58ef8482a59	\\x00800003ab6faeb4c193833e533c8d81b6108d41a42fdc2a47f2d1ec892d3072e4c64977ad468c5a32dfb56df139bab16c4af2ea1ccbf21d1d763a3331ae751739f350eb1dd9891ffe38f79effe5e636d66c722ad2c7dc11577bf8a0f97ba96257dc15c1f7745d21a488d7ead76e490b30fe655301626ba44d6c9972beb604abf946107b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xaafc8e5860a1e757312fed47b73d907ec4434b3ed1bbeea77ae1f9ff4cf429770009580b088dab8f5c6f5e728f544af1568ac36bb312d96e968849dd25170207	1621503289000000	1622108089000000	1685180089000000	1779788089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd429ddf539346c70f6459548df5d2d69036171b5e0a9cfae11091b29eaee8dcbcd89b1c534eb57b283960f85d298cd704716e4c4b866324c2e536a19f046e84d	\\x00800003a2fbe57880310d13706623a3258801be81b922866dd68a9de042eda8f5c32af56ae1adaccea6c0b7a1a21526cdc6dc5ba12fdd3e8c6c92bc28be617eb937b233cf66bea678ace4c61259ad721b2d11996bf230ca1b52d68fbbb5c5ec9b96680ecc746139ba395890a31e7e0cc1d06aacc7ac52601a4e389d1e9412a3a9118b25010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x54f3228f6a264f9d86d5a65ecc5df9b295a4f54c3cf3cfc5fb2f027db15ee8d5dbfe23a042f0733c9c33c60660a6ae3348dc546ee7e96affd16066ad0d95e904	1611226789000000	1611831589000000	1674903589000000	1769511589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdcc90f0744ad4889cb8e03929d0dc0d3ba431d6d64540b3b217f25c68a5621c714166fd6c3b930f05c3a1797c9fdf3f949fe3450fbe251c2c3fed6da07b682cc	\\x00800003b13bdb79c508bd08754842ee1b05c9f9bbe9bcbc0c7dff7fce31f0950cc822de01a89f5f5ef269d63e16837226113c05cf48711f362f9e1ddf70ba717d7b378547368f02f2ff1ae576965ded444fb65e70f43fe54f7e457517a50e05b5dca8a9abaa29ddfbdae5a505deab8f8f48749516bc63cc5c9eebbdbfd6a4136c508faf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7ddcf19f8b9d0a4efde10a81b6f227c5d7ecf940e3ef570e917e22238a3963e2ca537520a2539a542df21acc1b62014296d5fceb4cbf57ac2e8fea98dbeecf04	1637824789000000	1638429589000000	1701501589000000	1796109589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdcfd63125829a210abc252ea99f75ccb1bcb1dd450d0977114e23eb06b0a1b095e69bd7d403c077779920ca39de58db7cb5f7624dd44ef950de8c581109cd52a	\\x008000039b1bad0501bf290fca7e6af2119dfc4497ceb41da4bcc45c01b5fbafcf78d33938f646ea895bef72074f934b411674a4a2942dc69c41066f007d4e6e9e48efeb46ffe6e0eb7d0af954df8cc21802bc8eaaf3c00abf09ccb4e7b5f9038a2413af3304d1ddba5ea410809d5657978f873429d0885c592fd7a9036b856933341bcd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb7b760bb5b4a7bcb58de9dcb8d9afe96e31dfda66e46c6d8e77aff3a3bbe1b288beb9e08a9f22d255bd8fbbb565b20f70e4a4098b564f90704e768221d105c0f	1639638289000000	1640243089000000	1703315089000000	1797923089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe3d1367936362443bea59f482c9d05274132308d7f8d45052dcd764024202421c95fc285227d53ac4837c273a57f2ee8167a9e9c3f98ce96bfd08f2d81ca9cff	\\x00800003c2e01850a1c53c0e2b4d1c0820f90b7378742fd0403cef61d4c246007195416bb001d110642c2f595883d57f00b0a91b4ab9fabec01d0c65965b2330a23c3f136f80eb32194d3971f596a5c657517564bdad77176cfcd4db3865fcd2aa0febb516a215d4fd7fbb306351fec65ac3c495f1e94cd5a84d93dec3ffc529509463eb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf2463acd379a8a2dcbde56f144cb9ce64084af9aa5816209e51cf7a9ece63348d99a8fb445178cb888acf83a51e09adee4464ccbfaba884c3ecc824f95a1e204	1633593289000000	1634198089000000	1697270089000000	1791878089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe34dc9700705d84bf85c8077a1b72ca852db648d5b5bf649f0823bece663d47093db6bb8c173695290f59eae64fd7bdaac3921973a4ea42b5643a548a03c4bb5	\\x00800003c12c4927142ae780643ffed2a146c579ac0bca1aa5e0d29e891fd710bdde13b6506b5b7970f7a24a4e6acbc39abb266eb0ebfae6bcf3b2b9917fe373cf5f7ca8ab4174c515707310166a11063ab732fb8cc9a53da4a4392561c4ee53f52c1157a7c4b4a0b5519950ba89a5b276e836b180f3d839bc78c5aaa22a6a6377443d83010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd3b21d0b5d64c44d8f32e43040ce6e5ecfa6a56ac5409e9f02670e80ee0c20f814fa82cad1e1151204e83bf64603d13e6269b8f1feef5736681aff4162edcb05	1610622289000000	1611227089000000	1674299089000000	1768907089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe435042bfc269ee05d59d0422172770dcea6044ec8fb0549c84518e3efee61ca505881133df192b87cc81f28a41dd7ae5085d91ee0f2a386d2250bc13b633e06	\\x00800003cdb35912a036563388e3b23a0bb803b0647a81e8c97f165598ed10c2e68279ae8d28c4d79aedc726cc7f576f61f934777e90317cb77db3e0a913cee8bf94c6108806942e9015f1b4a6bbb323869b5a9fa772222e54cdb695ed6b1442091e0bdbb5ee94c98909e992dea17bfb7309241177ed1d797ddcfc68f84470664e2b7551010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xbf6f954d744984f3ee555ce0102d3b927a6a888a24e97ac2bd9ad000ba46c9af091e60774eed83c74ff3278debe0150b9e8ee99cda79eeb79edd21972325fc0a	1613040289000000	1613645089000000	1676717089000000	1771325089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe83971c83033cd73703bc6f54e154932abb52a185f38322c01d557425f11d4ee77acce580c2614d2bc9204bc2f11d1ad03913e00f6719a6e6f70b2ace7b0ab4c	\\x00800003c385f3323051ea558f0ab3e04047a5175c2b999fe1c091a786c7c4967e8f582702b73b2a93bac25e70d6d4ef73da3dfe0e5828e8f2dc96d2a07d5998f256b7d8b105ceb03eb61d35511062dbd4f53d6c30276b4dd0b9cda7dde832ef20cc80c3241b0d059b679564355bfbb72968681fc0963f1686eaafcc41e5dd90e030ac99010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeaa5d3c5f058ba51a0d404b97c888863c9d2f6c7b6403675d6f5b592c13b5b510f0b684962c5b6ba8612349a541d71b7302947e8bf6ed746b0810037be07590f	1624525789000000	1625130589000000	1688202589000000	1782810589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeafd1d71b7c852653b06df46cadb505c4b111a7956439f317c5bc4cb125b7e81e44a546336f8283fcb96237c5013bf204763378553a98b94a4e2255375e81eb4	\\x00800003d94dc9e5d236c152e21a1d651925ddf0536dde92ceff8a606ca6bc2493f18b5f02d17ae5d2867ee0359d8a6e9df2555a147ee835b1f18aeb7f1ae9bb2e56e7f092908e0fe52f8cb11a2c001952e84d965e09143f5b8304e61e4f266bb832a24f78cbd3846e00c86e9d62d0f746444ca1fa4a6d46192d050b25f89bc445457f61010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdefc4cf2863daf97930606e815634440d606a1540a71d59bcbeb12f8b620fda9898dac8701bee8ec0adfc19b4180b1dbd554289b01253ed623c20681e7e89606	1613040289000000	1613645089000000	1676717089000000	1771325089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeca972004e55e79ac45b18503cdde787ff98b7cc0deef06e07a912dcc6411619c8fc2d8567707f592f2c37a66bdd2aed1f9d8d5efedbf4cc46cba56826d91c76	\\x00800003db938f297f559ef97a1bc19bac51e7b23b1c6b0d94030d0855de6652f558a1ad7a323f30d7b5be31ab61fe1b335a14f1054a89cd0d0d0505a7445ed43beb68701807b97250d778ba4627fa17f05ce294866ef4c77522b55e735b3ff0e562129037091c47c22d43680f548d90928ea344c9914e393c5ae3b1c50595b36a977abd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5d40f17695464974d031ecdcde69d98a765f403933c91a67764265362a457f6bac6952997f9b31a0f7f92f869bd19b3445f387b5a238d5e88722116cd74d940c	1626943789000000	1627548589000000	1690620589000000	1785228589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xee7de8128209ceb85a0f1c8c66e493d1cd6496b1e4bfae00a143cb404d6bc9cf3be7b4c3e31affaafdc8bcc254444e5035b644be840cc5190d69899d9b893462	\\x00800003a0d6b7b3f96e4b90b8daf4b02508f26165caf774dd7a724cd5ecb61dd323e70dd1249233e9786f0f52b20d9dfd5b46f9d501b9986371ff709742202fa8a6467741acea2f82a4a60f8c365f3f7af654c4e3658ae2581431a5597a29ae5964ba2863f28f8272bfa41def70af1864d9cf5094eca0eb9f3f594d6d1f5877a0f42731010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5412a8c2aeffec5d0dc837eae2e0331cb0bd1453d69d363a6a3b5b5b93b925ec55626ca7a8624099f85501ca02fba3e7fe007ad0865d9040ad141af0ab8bf002	1625734789000000	1626339589000000	1689411589000000	1784019589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2dda0e63216c067ed6248befeba4318466ac956c904e895de0e975d3fee6caacbf230c8b1fb4facb2c7595b303af72753c67f13a76ab619dde075bef75b9694	\\x00800003c2d7dcfb15483f3d40571132d4bb765de14753b71f89eade5d3c91bdedb487eda095bc5c5faf0ab980835c750a80055a93ec732a223dd851a635dfadb5d5e83e6a6c0b857d4155f51e69d059880a982808ad341042bcc41cdbfcbe48765b4a7afcb711c0f6bec278319b608d4476203525aaa91a4e92ea219f1d476ef8bc18ab010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe031fddc57ff068ea28063afac5aa0168186cb984f9e9138b9afbaa116a90ce8adac9dc9df43c457983c4b3ff41181729fce9cd2923fdfacc7504e0f32887207	1623921289000000	1624526089000000	1687598089000000	1782206089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf6095197734a6da9164f604563635d2c6143ec60105e3a00d0808d676958cd519ce4cad96eacecd669fca591c385ac60337de4a967e51cb750c8e2609227fc0e	\\x00800003bb7a790aea4475d76202c7df66ba8ad6bd40c70e3aedc9fac34a6792120c294a87774bf343ac83ea944c1e534b3bf164bf7eafd5d6c84204795528a27b421bb2bc8fa62f94c1cdcca2dd7fc69e5d196e8c131a433dc84629d467ab013f0ee757a374d2abf0b6039cde4079d68093a271f5d5089563fb9a11330e9a272acfcf5d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb53621c759d294f67334fcd5272c977470c44e6048e3c9e84704f86dfa3d4f3482d9016fcb951f6fb6806229521705e2438e9211ec2cbd559b153731a3c42201	1620898789000000	1621503589000000	1684575589000000	1779183589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf79134b678ce3dadc556d4a670fa7a51be3241ef35cabfed96a6fd858af36b921b5e62c807148ef85c81e24ad7bb0463bfaa59dbdc54033e9ab46dc0ec0f1a70	\\x00800003ad6e0eeee1901fbe5d925a9fac35ad25427d25d0df02dc5239dceaf40e2c99c3c3dc7c78551b52b152d485177e65d34914b836f1297732a34dc35f49893601eb59cb58f98790a95e0292af3322be9cb5af2425184c68c3d2b3d77370252ffe0168dc5a0d90ee64d91b74de509f692e3ef40610988baf4c6359bad1d63d30158d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x43571ca7a374d5d848d0fbd6d83027e351fa14f7174872dc3c004cc6776dad745ee73c728b0a444cc1846959d8aa3861b678260d1ebbc96537a1a342433dd507	1611226789000000	1611831589000000	1674903589000000	1769511589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb1de484d0fab1b93bdab4f3ab17a8367b87b4d29c0a1b494f267b8b267ee2199048d147f6b2c6cc502171029479537c904fd5e3b6ba3f7b3641b3ffa4ec5804	\\x00800003a6560720568060eaee577dcc8c10d3b2cde5c3268fc9705cfa5446db92c55bccd233739fdd9879244c6e5cada6ecfa080585864ffd2b5de5fb752c94df8a671ca84eef59627321ca2a849f738e75ced12f605a38caa58c2311f8bc0885cde8642e39d6ecbb804c2c03dfe488cc77eb4cd8fd4f985ed6452accbd5c3270cf5a8f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x42569904f2c96e483928408648a8536f500916808328a0de90008281686f97b9139192a62378cadbd22be221a4abeea65267a5647f9a88d1b835d04687214801	1627548289000000	1628153089000000	1691225089000000	1785833089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbcd1d2a6e5bb4613821595750e4aff01917b83df82e391c36fbb2ff4e0720e71c59f064eb51deef54abce44d96d2e90e42ccd9d9d03bd62463d2b0bd7ddd3f2	\\x00800003b92cbf7e08b553a7bc4df35da980b55ba8df2991fcf52409a198e311dd16e8f54fabbfb9e4f3be6b998d6cf965163f089f3feda456b25f3fe6ceccb096b75ad419495789c5b158a1770efc2b5578d9c6d3ef9abaa64f4a6f1d2d32591b92d118d6127e692462f2c633391e392e78425f2b04f7e07158af17feff9da2193ddcaf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x28afb9bd92532ec92986ac0b34ed7ca098760e8034f2d2051380a0a5f7b194596f11a14c0e41edc82543293cd930a7cb99040514e7fcbffe2c4b76d5142fc707	1617271789000000	1617876589000000	1680948589000000	1775556589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcb12e30dc1c183d970e54f333e5560f765118466163a931d45c135cda804d2f4dad03b89aed3a4c4c2678a8b299d781f24eedaa9c06436c87e983cde35d4513	\\x00800003975b033b8e9e48bd3e5f47cef1480a95be403c988543633d74adfe14a2c68bf78c2396214cd1c3fab1d489ce0e0cceda1e893b31626e24773b3e9285aedddc678469a463b3484c34e6efd79a19adf194d422f9a25e05197d6ccb4e6285a89bacc004a56c5053a1f194c118d1bb44f647f5390a054e4333b8059db18424dd46f5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x09e90b8b73abf86a2a8dbea645a5900bed5c89fedd1b8bcf846839ea0aaddc075c4696cf9ea016c8bf32ceca09e864a39fb2dfb4b452c8045c3046b48d13c702	1616667289000000	1617272089000000	1680344089000000	1774952089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x014ed192bd0fee98c1b8dabf369e06ef58381d542cee7772e5f655beed6a3b8fd79b1d33ef902d575475190446af14ab8d1f2eb90e8a2cd393951ffa85398e63	\\x00800003c851796ae3acae7138688c934d12caad565a255fbd0e6ca7be9617ef63f522297e2be8136eabe2913ce2e08d24ecf5650faa340930eac08eeb7ff3deaee9a07f3c76c7fbd6d7a8d1fa07c40343013e549236da6fe7628b8fd67d33e92eae5c589c665baa813ee11bdca0c3d5980d90ada81843840cdde806682ff88bee390f79010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2705bf5cba7acb4a66388a020af02717dcd5cc30c1e1659550738d09f81d4e572b83b63f27da99cebc52724958c7bbc5c11141167aaa5e6690274c2f296ded0e	1632988789000000	1633593589000000	1696665589000000	1791273589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0246b8f715f01e20e548ba93a69b39e949029354c9f17b93b05ba35fc3b799fe3127d45e1907ce4d280ca2be7524296742ce730265c9bef1b394affb89b46706	\\x00800003b7f3038aa61c64a14b68aafcf2ffd68fd48fa5f6ecc149b08a2735ff5ddd1d7bc5b606715c0c2d4dff155cb6cfc5936e50cfa0e2dcdf7ca876add2f06988401a241dcb5738d21876b7331ada77d5727cf42d6ce628d6bfce5155933d503fec434dd7226b8b316d6662f824f51c253ab79251230631f96c3e7c5ffe81c2131685010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdd67a4972f96505b3c6982ecc502d5a8a12a06518ecec5df790b38b956a6582355f5cb84dea59e7400b26153eb0d4179464cadb48101f493ef2a603b0d172709	1624525789000000	1625130589000000	1688202589000000	1782810589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x02bec7929e143edd96a750b69f439c211e79d3866a36dee88ad78ff3960c80dc3d2998dbb891f598323bd2f0acc9c50e2fca33abdf8ba4d472f94f0e8cfb4978	\\x00800003f8b47af826ddd608166e9a97608ba854e15718fa81453dde2e26aeba04469c04726ed491623f6819e88e8c17f5a94bcda896201dad6a32c31e5793ae6f840c5787f893e484644998037fd5b6166e1fb80defdb37dedfa696c907b28939950b2d57f70b0423b1de3395e344df21bb597e585a9c5d34b9cb5e7451fd9767fa0095010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0ad307d63a88f326c492fc9961251046ecfaaa064cb7405b0c84076419d17062e01fd02cf853dc24650b539504a4c4f2c8d05a6f92eec374b8ed36a171bd4602	1629361789000000	1629966589000000	1693038589000000	1787646589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x055245baa3a3dfb6bf0f73e55927b2802947bcdcccacfe5f7813fa2a507d50820eac68c8ae8b234a1708e3b2238ba24f720fee3132c261c6c375ea44576267f9	\\x00800003b1becbce60bd4d0b3eac8206346a51120966b9f4145e69ba33ab775600facdef518ff828f321e59138ff29d2704cb40d6b97baa93a61b5fd7d3fc8e10e786127cc7631047c671bb6aba61d4cd4e572ea996234ddcb2cc955f4dea5c97ac36751f0b25087893ff7ec97929bc3cc301e851496719e78adcb42635e64780fa1bb67010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4e88fd96639c3d05b71a13b94d70ab07726556cc3b6da8722adaa4b5c08a05f60636ccd36eda309914775caabaec9d61e7d65642d6f4d91bbf703481ab507706	1613040289000000	1613645089000000	1676717089000000	1771325089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x05f2029ad1814297837680e4b68e37c01fd6aa1b1e101ba0ae0069122ec1863af40e5eaa0fa144f1b376ce59577f8ba2efc4bd3e5cf8807f378b71c37c302837	\\x00800003b2218f2212c6917f808db5808410e1e0a806c535380e729609d0cd85eae7d0802c480326ec4ba0e1898c5d84d610af6690b257e65c431e5f04b3bbdbe5dd6298c35dceaebdf60d2f53effae63f0292ed65ac0b93cb732d098b2dbc698f2fd14a2e33d2a501eaa105a95ddc191a2becf171fd40f2d7ed2be0cd0c49eb640bab95010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xcb5c23bd65873eab18c70db13d22e327a99dbbfcde14ba9cfeae20ad1ec1c51961c6a853a7cd8a9aefd1318d73967086acb720f11237e75af456aa16c739e70d	1614853789000000	1615458589000000	1678530589000000	1773138589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x068269274aa340aafb540a9c3c3b440a857a3801a57b8ae8f65d166a096258a2da8dbf02c439b7848b1d376fac6eb47f947f44eb700d4cafd1a73e816def4d91	\\x00800003aaf4944a9dddabefc0a72b5078e797ff337ae350474e0c19a5f458705f71a7fe9c20d894053450f113a99f0ef39ae97274f77d7b8b81633a465814f4f202dff31c9f89ebae698f6495bb250556aba415c6736b645bb757d7e92eaf590ad708de119048e48e892a13785f9d793c04e39905ef394669868b025faef801fe681079010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1b55f2004cfb23597c0e699d05ac5c2bddce63540eb8a2657497e6017c360f8d08ae3b1d8e9ad4e85389616de832e4c5b3381bcdd73bc33fa412d484ffaa0601	1617271789000000	1617876589000000	1680948589000000	1775556589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x07ee6e4881d5e278d8dae3e98b0a48588323d4bb5fdc29dd9726aec25937a685aca08fa7376276c3a03f684226214f429fd327c01c9158ce925d45e8a2f7600a	\\x00800003d8352bebd508bfa395ef6c7af7eacac24eb0fdb0d4dd8241c71299a8a0d7519759dce79f452ef5debd80c2e62649027cd697d68d0c92acca5b506c29065ff4de06aa5ad1230c7e728c9fddeedd56ca9e25ff71caa9ce492d21ae3db5b52ae09d5e5a7935a2965fd99348f4708045949865e6274165196ccf1ce539b7792635dd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9666d6218c56f507eab7fef849b507a0aaf3e44b159610027f274786f102fd4573bce2dc0a90faec68d7f983f6f6569272c3d21a64544706eb3c34a43a32600f	1637220289000000	1637825089000000	1700897089000000	1795505089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x08ae0da77f474995a37f3c2a045d9cbed0aeeaa508aa7e28dc55f495e9f07da28f93105541106052d453f0b8b23f2f8f988450140a16b875ffccd494a2fbb264	\\x00800003c375625eb63a84a9258a8e8af064f090006653d7636d66589314b9f7f7255e3a07fe1cd722c1bbddd54bfea474fd411ce0fdcedf5cf5df6bd07750580397da3dc79aa4f3838a71d2977bb2423dd7f0ab96fd2e779cf47beb4e7e2dc14c06497ee54e143d1b5f00be3fcd0df16845788d79cf0bbb1411678276353d0a56277fcf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x00508113d81bbb45ede62f75e9633187657dff2c9752986636701b5a9a900511470c7b9743e39e5a56022431b4f5991f352faaf7400ac941e347bebae60e070e	1622107789000000	1622712589000000	1685784589000000	1780392589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x081ee271d99442b4b2d0510bab2a158d88c6184bddc89f34f2a160b630e0eead167d5ae0468ccc5c1f781f0b2e18e192c70a5078d948931dbe655c5bacb72ba4	\\x00800003dbe4af12b8beaaccd122253b23a0b0ac1a8ec3d3b2453faa091e568c5092ffcf14875059708a3dec9a6600a6a67624b03d522cb8e90e5361201425b3712bd66e1e08a8fed97fe5fcf1f287d30541859feabfca9b781147d1294ca28ee6ebd7e24495a017b1c9ec3e17fb75a8e77da9ad5f985e4dabee26c7ecaa68203f05043b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x043156e997604fe218cb5a0c6aa626d626f2b3546682422c4d9ed1d127a673ea18323e5f049cf521fe25650351223016ee66d220efa1fab68c1d21346f99a306	1623316789000000	1623921589000000	1686993589000000	1781601589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a628140e5243c036eac2d1d60d9c16c5ee8dc6dffb31da3f8bf899979d55fe59c028726354052cb74ea8109944e51eb6268e09a7dca9068ba063b5f247d7b36	\\x00800003d3b16fec6988968b454ed83b34b39a0a6857f19419c9e1c82aac5132eb43112070006f7aa698237b31d8b64f8cd35eb83c3e58e2e11ea167ba68c58bc52b3387933db96a9ed96fd27e32beb7da1b77d64a985a7d50015047c2370dabf79907a78f74e226cbc7d606f5d771520d86951aa56330ee8ae19a7ece4d30525eeb93b7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc8f6e7c95ae16eade4309d3984100ea5c5bfb98a67f2ee2a262128411179a24bf449fb16df51aad827b3ed10d5e11bf727200d003e97d67dac2898cebfcf370c	1608808789000000	1609413589000000	1672485589000000	1767093589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d6e99bc240fb84923d5ee5932ca24c1b4232947432ea10a9c47d7b08608ce72d21cd2adc75514a1161325b8be6c841838f4c34c7cdc9fa083747162d0ad6047	\\x00800003bb47a92644153f8d6201d26135493378fdb6eaaaa373a89a00ef189ab6ba6d8221f2ed11b43a618410b2837152a99af04464d6c646d335f0608f5a113d8313fd4b1092f2e640d2fb7378dc44ca6e905a82e03d79b7b0c4958df3e54088c163b03157a9321a784eb073feee2487b5b498e8d553fe4676ca793f842cc36d3b717f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd4110c46329e0055a21174855074a0ade2da8beaa57556151181ab3563b60e5452fa2f77a201f55853db5b5a3bbfeb2bf479a3c5c0d4a13d0bf785166b1dc90d	1633593289000000	1634198089000000	1697270089000000	1791878089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12da20e3d09cbcb21cafc61fbe48352365d33ea8e2824027c1a975923405a799d9ecab3ac4ceee62d18dfa6271f87bc79f9abd68b26615a4e33b7659b7bbf2f5	\\x008000039f303c3616f8735365e51fc8287d53850bb331d430e635d150ace16b0e993cc76b4ba51116ae6bda62c00337fe34f0f10b5788cb70f15e72653e524044606dc0aa45843cba0e3261ed92a04aa81c6c9bcfbf8cd9a81e07de9f9cf8186ecb9a82be9d05a79e919a0f7fd4d9a12fb007b5d298251b92a1134b78067922125d752b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd4c0f25a3151ae5bd88c6c7cda989d5292aff6a6898e71f42a405d2e09de698fb5b06655ef9fa7867d309150a0a98ee601058a517ac03c2f4a8f64efea15620c	1608204289000000	1608809089000000	1671881089000000	1766489089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x138efeed6ab5116ba0cbae3488b7ee979d6acfceae9ae3cb3f7da4a45566b9936a05b1c80f73d409a8f541ca9d795dcb91412f7fdc89c7abe7d362a8d2c27754	\\x00800003b07eac9bcb798bf2a96f12db4fe2f14c8e68a48d67f07e8c9fdb3255c0a827ddb045d141beb30912fa8ea6f239e1bacbfec3368dd6875ce3f8bc1ff105d86bd244582515654075ad402555bbb914a1921f50ca3f6c24b7ef838d4fbf78bce0493ea95373387f613fa7354eddc0268eae1f76febd9b74f6c9948a5ca744524c43010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xaa65b8c51f4fd50849d784577cf118442f6876b0501e188edd3c0d09f40586d3de2d4012ff9c4f846eb55b1212a312e91ce3e4fc35ec1a45db417728a198190f	1626339289000000	1626944089000000	1690016089000000	1784624089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x141605fa18af242618518c8826f16ec1eadcc0eac9d907cffc71079ac28325e20c5a76951bfa71abcb7cadc61f0cdf4826a30b5e86579fedc2cbbd9e99ae307c	\\x00800003a5624f19de8efa283e5e53220a8b84b15b1106727ee3555ce8dd3be6ae64c9f3036d1c20645f41967d51acbd5e70013b2f8d6cada85dfca583f22813208182c76ad1d6ba59bba0668c91c64c052b3a38f9a5bb88753ed6b295633fc70ac2b3e5d9f0ccb967dc20688553d4abb5c24a6cf5270f0502af9ef4ffe2c1eab281bd5d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2739f3972f94deac33712db838b3d1fcb425db4b7dcb56c70d50903484c791315c0760c7700182bfe288b267ba9981533436ced3ffdbefe8460adcc134420809	1638429289000000	1639034089000000	1702106089000000	1796714089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15a6c3a27ced735ad465528a3765f0c726c55001e3d3bda590a1bbfa4fea422a69776272e29ba5c53fb9be8787a15966f09611f020f707e41f8ef20bfa28cebd	\\x00800003b2470dbc6942a258e38a41bfc436a91a608db9252ff56af9dfddb26827046334a64fec0dc134c7b37d89a5b75447bb957df9dbaa1fd51cf4455023b1b69d1d809948d4cc48566f4d1636ece80977912b694257f62ffeb414bd5f1d4e4f0364efcd3df6d37a190e89715ce6885192e9103f0d94a4dadb685017e408072b99080d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5586bd3f27a0dd9fd7f72dbb6b0e8bc799d1f2a2a962780767b65861e3256efd8d8754b8f77074c54065f472063d3edce4a1e995dd9f9df0d9b9024639592c0b	1628757289000000	1629362089000000	1692434089000000	1787042089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x184eba31e34651a4a1452cf3c6db4c6cf9f6f01f892ebb744f4b7e31622e6460a6915d2b086cf28020edec1f0c7020c83f2abbe40d915c3ad4fe5da7984ee9f3	\\x00800003c584ef392f518f5b804c6000686f07b073c2cca8f5c8d6d7b6a01b31fa5a6c0c6c4bef52bdd631ee5a98769d65e550da8fe4f9ac58fbb93430ea135e6c6a833bc0052a88e5c2683dac0900194a03ab203d77148a3d46a9c06de66871a7a16a4d29b788a64a42b9fbb872392b688b76c2324c1c7ac6bc596b12923adf5368b175010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdc7a9723e9036a59ee185c22a125a12e601b875fd7c9d37ba58c4a1ded30bc4cb99324da52b4506171d0662ff9371b927d40c1d1ebe745903e8e340aec18ba08	1621503289000000	1622108089000000	1685180089000000	1779788089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b1a424ebe7e55d044a5743d6827ed698a9eab01f934374273711805d94a7d41a2a1ae944a4548ac4c27a0344490a4192cd05c5f88ce6726bdfd5c5fc15a9b62	\\x00800003f193f900a4a8a5bb74dc8a3fa36eaa154c4bc2a47a0ad5947a7196dabd4ff1f2c84bd606e01d44de846528a8cc95e57e3f979db6ee44d46aeb3ea3d9987cdbce5d169e45abc8e4ebeae8cc867af6965bccf498213193dd0ef83aa9e3111b64d52c536eb2054aefb98eb7fa3f78420bc8efce287c81a4b93a2c87ab642b8dccdd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x309f6adf5164f0af76b7bf27c4f89fa1e7c962e3bec5eb2fc2389b8a08ce9dee02cacbc70579f68410b80faf838a296ee3a00b4436558d50560df17823b4d205	1632384289000000	1632989089000000	1696061089000000	1790669089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2092ceda385c6d8d7ace61f832d0da425b6e8834ff3a05ae2f109f3f7ab1e7875c134e1b26e0275919c3ec48effc42003d48bb9919a8fdfb445b2d6fbb9ae47b	\\x00800003abc89295a81309726f4931568f55142264ef2ccc5b901ebcd3a2f7cd1ce44a7c08044d309cb15b6138767a8730d12cbb80ad0f30c2d6623a131dcbbe845f01c1f23d790514fbe39a3a5a42c83bf9e736a1995da0c2ad5dd1fd31283caee9dc760a3894c2f66a83658ae04aefc44a0df991ebdc75a46fb0ecdabca1e378180f2b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x280bc991ad47833d87e2c35ed60f2842017eb1bb266440b4a0615bad8f548da3ebc9b6a96377d935b2e76ce9a0a70649d42b481ce4d1c99413145fc83f274a09	1610622289000000	1611227089000000	1674299089000000	1768907089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x22122ba7ed447f1d900b13cc0de967b44602b79c7ee80a8971855b13d0bdf2b922436bc9959792f114845916aef6a69196d0037bec5e6cadb268038b59fa83e5	\\x00800003c4c763b1e0cd3b1c001c02d62313f104d010ffdf78e45efda2c313e10b6c085ea5526622da8451d8cfbdacdee832066faa293f92bdb272d4aacad092c7310520d7adc1808e5a3a13edbd8136cfca04a3638339941730faad295194797ce76050dc749a21bf57f88b86fd8b64d13d87c28ef9d3095481bab7398f9977dd44475d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x126ea297604d7fb8c342367ca1ef1b10818b71bd973abf859d1efe8e2712fddbe5740422e19d96f2f8e591ffe55b138009108bb98be9eb870668eb0dbe70b002	1629966289000000	1630571089000000	1693643089000000	1788251089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x231eeb4a3a2416ce33a2c0ebaff6a0c0b59d5841a8e5da47ecf594f8008c9725a5d6c2870415c31ef608001633d86a072e863ad3aa21365fd84ee3926d977a54	\\x00800003cec8f4c02bfa954c65230f63b23385cacccfb61e1d089d2c8d258bffcd4a76d5a2a64d44fa249eddab9dddfd72ae7845b13b412dc4dcb3974c05ae319d8a8c077b843846c042017ae3cbb45fab0e4c4f6b8337cef1e4cc464e2879fb367d8b1c6df66c427ddf0ac3281e420b5faeb0a28d235c34ec9c0a487edd5049a50a06a1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xcd0da667a3043564a3f62d5493914cfec87465d521f72f3306f5b0fb2d45d1d0abfc386431970c3279cffc47c9eace57b493c965e6d3a88c40967fbc8b202306	1622712289000000	1623317089000000	1686389089000000	1780997089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24a6bade78943f8298c11784051c4475be98e8c5e8cbcd882a04392a83e475d3b45f411886316cc71d3b045f75fda8c2a338fe54d22eb19c823bf68a86ef747b	\\x00800003d80c7a9995a7a30fe1c9851df9fc192c565068df35f7a122c5e1437bd40bf025553b042390f91836b5850c95c8284d2a1a7044301d9ff7118c3fea4179fbce2955a3318616d6614f4457370967efb8b894311b3ffd63209b7f394e8630403d8fb3456999b601f5d26a3887320932776b0646ff8f1f2aa2b5df95b724851886a3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x440aaf46874bd751b6a43a6b60946cf3a48a58f3db97f1d9f2b1c77df4a7b9e602c09699ebb57e84d56ab5ddbaec82888057c62859b97ee64c7d8b1d3dc6c307	1631779789000000	1632384589000000	1695456589000000	1790064589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2642acd3c4ddaff9112cc05a624b6811123396e6782b70b116acda5a0c5528ac13ae1c203a7cfcb538a3a78501aa7c1e1ef28e436f13b5044e25e256c4cb5aed	\\x00800003c4b4234f0f422e66a791391b39cfb4f6d55292892bcf886d21591750570bc0bcdede0b3113a2992726365bc0aea5479ae87707fde238ff9f0c8c07125dd6103176c0e388acda91de6f17754ffe2114208bfddbd8e55feeb6d8f6331822f77c28cc4c59acd91781e589bcb36e09aa61f7974654927caa68c1dab309d8b9228169010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x23527c08729a0b495c505932f7908cd7a346cc1f3b9f89cd336f127b4a3fab503820b2d77a1cf32099cbb2c3b60112ce67c8785c6d3bd3cf1c4e787b4fd04f0d	1618480789000000	1619085589000000	1682157589000000	1776765589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x275229887ff1ba997965eb3469bb46a05c7cc111b992f988495c5d3ad985321fcf7bc4367aea295a448284c6ea2a39e7b572245898e4cc2ffd29047a6a84fc41	\\x00800003d2a021efe9ca9ada3f9424dc1748770e281853264c3c3444740b63842d6a1730ac80b942bcfa37d8e662f2309cf06696759fcc71ef5973ced7b3c85359c3d524a91cb9c907131a484a76deeb61cf0510f8f3c08617f8c9f311d1b9882fc8f1f73784a47f796d59aa1c991790697f50f30c4c6f958f0f5b2c8b0fd03e2a2957a5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xaf3121e4d46542e3b2e94a35e719a5e7eb807355b751746c5c0163f783897a73d3df320a4e06c4259cfd62868e8f9107208a8dc652533a24554883ee401d2a02	1631779789000000	1632384589000000	1695456589000000	1790064589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x28e6943817a1c69c9f439511899e39594f5de9dc69deb2300e01f9048a52e5e1aa3ad19c011742415efb755df439fb3b47ebd26f4937ca09e3a0bf59ff278511	\\x00800003c886c541e8d4517cd56e099b8114fed15c5a1e9363ba349f4deea8f42e372f2bee868f2454365cbccb591537106b67089ae5b00270b36cb5e9f9d048c20b5ce4a3f315b80a3f1f31cfa7ca5ef8aade15be3e19baa99e5d651a9e8d34b6bc231fe0c829579abbf8ae62124915f59c7e62562707b04324c523bd67ce09f90cdf4d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf0f61379927c8a0a67003ea152b72f8878e7413e3266d8a55e4009662b1a074155ea26f90b720e6a8c42574142226bb4f32145b41c9acc5974187867ef7f9703	1636011289000000	1636616089000000	1699688089000000	1794296089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x281ed1e02d31491014e7d4f7d8817f21c56f4f8a5c71f9ca6c57615adb5acbbf01caabe85b6fb88a2c284845fb2e4bfc41b416a496287ac6ac6080fbfe849e77	\\x00800003c03e1123d9f890868130d5a37fa62795acf488647dc4f7da272859f7b3b71bde47a2463ce209d04fc0bdb5f86258b682d85e937fdde598e36b9563bdd272af71e13c2dd4112deabaf151c353fea7a638636b2aa70be42da7491f7666b56b75031d1fb6a2d6f9339c608763a1e380f298122d6b8ef662d71753f374b444823469010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x10173e9d017c849d7c23ea6d2158aaeb1bf4fb6aae29cfb193c69d010ef37acfdb91d00926bfd6b1ee8c23f815de9311036a3590a824cb46e97e56b07d999701	1611831289000000	1612436089000000	1675508089000000	1770116089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x292e3f2a66223663f09851c25bbfe8c4f692da827b21baa64daeb37b77472e03d630d7ac2709e15b96ca788e96d8ba0aa1c92e9fd4ca77f345a31b1adb19c78d	\\x00800003accc2c6d86d547090113744ca0fa93a6653c8ffac5c13cf689161f6593c81880ba49ad2fe732f3080bd0e4aac70f3a1739c5d607a4f45f35281c2c922ae5fb4bddf56b03879e6859b80b4371ea9314999a9c28d3e97de12fa547d82b4a45862e02c291cd58ddc43d990bd72ca89c4f55af8d7eac4c2ed6f01429dcf118fb3739010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x23631d9544bcf330c2a66edd891a486f4224055ac3e6c4b855a69e6750e6156320704c3f41c0c378ba88f7183fa62f8ad3a680e0e1c0a3b0ba11bc045b1d7108	1620294289000000	1620899089000000	1683971089000000	1778579089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x299eb422f86f9c25a9e86459b7f798f00a6b002ba6d4e741844d4997420d3340065c8ff51836552946ca848ee6979ca6a4c593007142d85e97a7f3b03a5a95e2	\\x00800003c0d9d3de3553265f31ac296e0563d9285b9d287add1b341030760a46423e333dc3212ac1e29b11cd8efba6aa77c6463ae2320146b627901448641b0ba9b280a230025c75b9d21cda7547ea477c4a807e8ace9e3c94b39583b7cf72a42426575ab84779815901f065d4eb5d4d36d0dae8a38db46ff17247cacf0e0a778c69954f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x65f270d1fb932180095fce7e280a0706e989471ad1e79c7b9aa160112725f0eef626d6818bb58906d60cce2dcbcc7e657c3693b02768ba5ed3a0c0120c6cb80d	1617271789000000	1617876589000000	1680948589000000	1775556589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2942f4ecec958619bdb1213bbbad603c868b6724a6497e13aaa7c44656bf57fea5f6e66666f5872cd4486b1fbd3b2ddbda4bbd911e5adbeb1e1f964b0cc39cf7	\\x00800003b86745dcd9fbe600a9e9b4d524655b4917fbc437e5d41d8009943365ec172a70e692da4939f53f9fcc652a81df9f3d3d84ab3d2ad3b199bf110c7c3bd6a173669548e37fe6cde302fe0bb500acbe6767fd77260cf5dd183a039992c55142de4387f1cd98a9c7a42726d616136b33cb57538a1ffb7563805d0bfdf6b12c440367010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3e208959bea2ae805cf28de1c51bfe1ab7ad74c3468567fc103938f9e5cc916b99c1dfc744395aac803e0c15a92e0045e5e8d925a3fc22a88319b06c1dab4908	1625130289000000	1625735089000000	1688807089000000	1783415089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2a526010b01bceba38289bc35b9c0cdf0eb586bd1c730b5014a48fdac8ebe2f9f55ffbc9b19dce9a4ac242fa9c9833b27817ea88f67d6c5bc66b055622b1737d	\\x00800003a035eb6f2e53b48db4e9315680023c6835ac535fce7297689fb16a3ac46b34f4350acd77360f77ee7917ba7ed6f78786f065bf08a4cd832cf52cc33bd87d09177f25a1621d381b325cb9e24b7ce917925940005cfd163221461d455ed014903790f2711c6bc81e4b444075a640ff72f9139a38a102819b52c12676389faf3c1b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeec01f0f0f6cea2561edcce71bf82d2c4efc7b8a9a0abb7d2a8e9ee63d5f71e8c5a471565848fe3350f5017d7c7850955a987583f08eec80fade763d18bd9c00	1613040289000000	1613645089000000	1676717089000000	1771325089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x320e6d908094d7acbf538c26983490f1fdb442c6ed75ee99e40de1c0b0986b085f68563c34039aa9d5f1dd2905e1fa1ecb897b3ce7ec587bc713d4273f9458a5	\\x00800003c73f6538707ec79f94785154da4d9a436a2e9a6209646053a63ffcbce156e4398f3cd4c46bb8da458c431ac06e91f0166961956f80dcf8a7d57496f3ee688fc46654f84bdb2fa5898889954db94a661e6c7adafaeaae7f437c6a1496d9584065b341d42b54d941a1bf8092d2a43d5244b79ea5bcdfe5087c39fccbb2bca9178f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x20ce713db64004c7293b24aede3326fb68c38389e2b76af927ef5160e3a96426ed97029f2526275773c2b93704c68098d760f06a74d1e1983cff48eb7a91da03	1611831289000000	1612436089000000	1675508089000000	1770116089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x35362fce8a68f769a883fc511d9872807604b16014c0d933e985d94c00760402b936c15b6fb887a1a785caec9cb31202d2fc819135affb5e0bd655bf26e75c64	\\x00800003df35f3bfcb78477dd7fabc80b3f205d803d252633fdb6384477c2df27db3f6d2250d928e9b5466974113e44e8882a901b76990ebec2b312f444575e0c4858c2bdf174e652bf351335e5d7ecd4fb28b113aa04a3f5330d62bd735412859bf99fb5026c0b2ee0355650673e42631dc468d7dd52159d12e9a6879b77e30e9a80e43010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xffc0fb7f2a6293f28ce41fba9e439fa80ecb028a09358c1f81c289d93a3e56952f01895ed1c6d69c8ed659f88861870cf65eb969ee754eaf28e40e7969e63c0e	1616667289000000	1617272089000000	1680344089000000	1774952089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x35aa5f7194da6712689ec6497a1814fbe4736eebc17f5f1747f1616e74dae7a7fa9beb6bccf7c34d4526d4bc3db3b317b3ded94a62a127c359d175321ba78b0f	\\x00800003ca52b1618b1d8d50aef5bc88fc6c5f1165a4544c4a8fda6dc8d4566d8010cbdeaf8eb8a4c984d0fe33303396c4fbc8807d7935513f5091e1b0f77615954d4e714685c4df785c2217b3452295983fb89313f36a71f3dcbfa0f163c2d9cf94e56a18f10e912a550ef8c9f7fef99272af27e36d465bd2f1d1d2a84f22b0eda46491010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3e48ec8aea181faf767b7ae340f6563db4d19a91780d90e3aeda7c9ea6b1a530b5c2616559cd3135e6f0ce92f4c580b75f62048a93c3644542840be1ce918c04	1636615789000000	1637220589000000	1700292589000000	1794900589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3686ad9701574194e4142ada8c0a24bd975f5d5a307eae244e716a101b425c15398ec1a2e0ed4b6d3a79af0d9a2cbc9d7ac4ef6db328a863f30b0510708b911f	\\x00800003d2d574f58f5322ad9a5f878b478ee3e682a9e7ced3d2a5d99653567c9afa6c3c9b54ea002aacbc5e285799a97eeeed8eec0a51d4e8348b8a99e4b89085b8ab8d39d48e16fb377f897f5af1fad81ca45e8172b2d03479c4dc73ef6883b4afb051254af12009c9f0d349f2dbe0fcfb6b26237d771ec6d07a0440dc0776a815e5d5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd065f3efcdd98fc3fcd35962df5392702aa2e45da11171f89000a9bc3e4de4764189f34e7d8e75b66e0fa9768cd92a9df79fd93356639007567ecf3dab8d0a02	1619085289000000	1619690089000000	1682762089000000	1777370089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x372aecac2ada0c3257bdc3995cec5f0a7a9d8f2a8a5fbd20b47c2af8b3872db24d62bde4899831c704083a2170ac0a5a81831eafeef490ef2e5f95c2d1d7b9ca	\\x00800003b1b67110ed99205eafdba177100be816f3dc47f57397c94612ff6d7100111259de22c86fe8c3ff91c23f4eaf0229de1406314243055ce82894cb0fa922c3e262acd1ad7d7bf8616a86c8a2f89ffee726401cfedec3f98cae4ea2cafa34c84a667c85769d0b0aba0012925ba617f5694d3012fd1f88023481ce0ce30e6219d739010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x55b6c3c40da1e6747114c77a444a62c1a81518b8a0852b399522dcfaf8aec6704895a64a22c50ef9e55ab0c599f3692cde6f5dbafc12a4a57b78cad6d3227a0a	1628152789000000	1628757589000000	1691829589000000	1786437589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3cc623ff573efd163e229ec82149c40718b383bcb24dc3335c6be59e57718e164886a9031a62e0cc10887ffdcac78d52879153fc8520c041aa3c51d610c2fd9e	\\x00800003abf88e252eb8a3c1c1bdead1f4f7261acf6e4e735ffadd987353977a774fb4a5b07c60f37bd82a91335a443b56a37dd23d6cf6fe62ee0f317d4deee2fb9bdb8cae84934d909afbf210a510e9dcd1f5c431d601c91d815f0e46c35f641d1273783831a2b6dd3e297232b3c4d6c7aa78cbc40625eba3ace6073fd5d432e5e2cce9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0913a2c67fc9cdbf1bc866720dcf6b1c83077c5267462f8c1dbd995d76911ca70a5305f5d9acf2aab6ed186064b3728b3b626f124f886f082d2925da1a7f5d05	1614853789000000	1615458589000000	1678530589000000	1773138589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3d9612486bd8aaaec84c99190e19676cd147cf29c88e592dea6b27a7923607f479b5cfe5569aa349e8bfebf61c46b8613f9304c4c64b6906ebcae145dac4067a	\\x00800003ce5f51eb2028dae9da14accb0691bd46ceba4fac0beb178f34af864cadb11daff1aa3ad5141ae39c7bb97e99c0503ff179dce969a3852414368777aceb15179b5cd0a42ca9afcb818d2999814a84e6eb0f3a58e68209a79ed8a7dd35b3a8b21e915afedaf56be5c41e77e50f77ce1d589eea8a91eae304c3085472bca15effab010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb9e27a50ca481e613370ae17fb97a16d33bdb9c9203b4f90c420c1791d039b9bdfa10ced39bdb279e98c518d9dbabd709c952f1cb438f8d4e5f724550b81900b	1613644789000000	1614249589000000	1677321589000000	1771929589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f722fac23bb13f969b712012526a6eeb36f0ef8854ec19c55b5bbd0845a37f9df9f7b2de02d914f781465c694c0903ee46ecac2ffdb36b0fd681daffe26b5a9	\\x00800003d080e44deb0eb5c064e4ea267181ef37adba95b59af60f1022399bf885bbd0cded7998998cbc3fb16e460c88cfb9207639b1a8f7f388be83cd17f4f95e7242dadd8805d5b24f714998853f2bc125c69de3b83602ab59987ddff2d93bbffc87249610827e945f77df263fd0edfb59fd1933ce8e66f3339e10d4e811e1f264ef09010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x51f79fd2efbe95f89f14decdf4c24f81b91593dccf6c38c2772a5276b45a251609e661668e391aad6f725e73511ecdd8eb4a4c804c798256e4786eb8e5d51b0f	1618480789000000	1619085589000000	1682157589000000	1776765589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x412a7c1bf544372fb80c8e9188c0cd1c80387c0019b9a66ae8f146d7fd13c5eb35374376401b336c9d266351c4b68f50badd763915fa827b13664fe857e34806	\\x00800003d3726409de504f7a867014f21cd62af9548e62bf0815a7eb28a306a3131b47d606bfcc37add16c377fbf4f896a5efb4b243d7d4df5c6e3b17e5f24519a5776b7a70379435e94305a05d1d4f58227e35a165cf3867cf39617a9ca035295e38d44f3f411cff8e12bb8d454e7ec8f06ef283c3e9a3c88fbd451fea340047b7298c1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x03ab0fe38c049a921a39ac262548395b5f46927e4669c41e450c8a39b3a5d1914ed091ac6df7805e4ead64656573e14849f50b0527f0ec2fba1efd3f21ec170a	1614853789000000	1615458589000000	1678530589000000	1773138589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4566d165a55a4ac4b2038baa6b7d18745558f01f2a95a0aaa4dafad6792c8b4541a5de44412f427287e19e13abea99101c2c02c05d796cb4f3b0beb4ef70e159	\\x00800003e2b3992a51f28ac1f4ebec4d79cd6a21c8d0d9783eb24b3a855c5c3b0d09417bb9fa744b0fdf55e28f043eadc32242c5bdc8701b0efe2c1055b3a42a506eca8c8129aaed82e660595adb0e10f8487643874af25a77dcfc277b5c41de9d5652a427c83ab96a5edf085a368840570176926d38b99682db8d0fb31780bd4deeae2d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8de50f198714478f3171a7b2aeec325a4889d18de9de7c3d0c65852a9b71a9fcddd5b3f0f19f6d905e04ea507c14bf147abc70707952b9fd233465afebf1050f	1625734789000000	1626339589000000	1689411589000000	1784019589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x48f29fe534bdaa9ff662820d2fe2fa9b417c5d214dbfdcb94b3807b1177a7ea639529174290d9d6d71dcf3e1722b4841676cfb9bb9d58ae6a816a24bbe2ff180	\\x00800003eb3ccc5c9ad1feda93de0c447665a47b061e9cca46271ab1d1b9fd29510d8d9ca5754309893ee765139a5043d7a1560b1e664d1926521e5d2732c0d1b8abba93ce58c615318fc4fccdc8587ac0b50fe8ff1d90ce2c67c82ae75a9fa3ded00b6b1247d39db45ae2194fe4b2b9724d93b785afc818b29d9c32ab6f8dfe182fc7c1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xea9c44a128d6b61f2d286ff2fa5b28aa1532552f92a75c06af5d5d34f10b1072e0fd42427ed20a69f83627f93401c4a7e6eab2530c68d0f71dd83852fc729b0f	1620898789000000	1621503589000000	1684575589000000	1779183589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x499609f97908335bb790ac1fb46ea8d9905353c68c895a4ec48afc4e778e61821a80364fc1e5e03a55bee4ad9bcc81e1a04e7f18c492a6b990d75f9023df9d69	\\x00800003c587d5e85150cd312033418ea668b8e0ae07c69281a94367adc602249db679a70890d634dc435a35f73ca011cad8348b15b18bf1fc3b49e22bdefc86298c62cba0eccc64126604639afeddccb1f53c44d541ab3f79ffcf45a30acd261939aaf0ec13c8a8ab35f0da4e80f0a5253a74df86991264d4c3a56a37098733007dc12b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8a87e1a77a37b7e4772ddba6beb3f7a683932b2d2fa38ab87eac14eaa8babca764ca6a6a9301fbbb0f42adf9a2582b251a72dcc97d5cebd42f169cfafe956007	1625734789000000	1626339589000000	1689411589000000	1784019589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x49bab45030f3b33253c7691b2527efc9308dd53fd0b5b62db49d9cef2da1ccd5ba87b73beb6abeb54c159045651beccbe9019df542eadc191e314a7f6426c5df	\\x00800003cf80990864edd18a4fed584ab222a1774f76c52b7ba32270b1efcc1c05e20decc8bd5fae76fc90ec26aef3dac3e93c45fca29a263593220eb054ae99df19c39a23c20a06b861773c74db79115980e279d21b5da4304369b94172f4563c0df50827f483333dd7828073b118d73a078cbf3f5f6e10a57fb193021fdd4a59f28f2f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x695cd2fec792b2c3703689575527e9b468bd9cdccf9305bab98a442252e490ad2f343074052c206e0efe61503da28062c3b250368400d1af3030a54d8599b305	1638429289000000	1639034089000000	1702106089000000	1796714089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a32b888887b6581c12e21473bdad9bfffb71da6ad714241468145f7d5e51294fbbc7c29e794d7741d7d9c8f1978af1e4b4fc13cb1715b686d57163b8a761ed4	\\x00800003d97c8ceb821b8b631d0c2159beeab48d5528019daf1e21cda12cb457859bca7f50d42704eb672417ded9df2fc1f1c3a9d4210185621880d5f9b4e05f265406ee27065003fdbbc25e4d733a79912ecf626acfb9fa1c0b4545a956af6f5ae6b5c5d5abe1b5f456f13d8e4506ec7a3783da6fff775e1d06f1fd66a1956f821d0f97010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x07476f2229beae8dfaf763199cd5ae284970db39f48701a492811a2061d350118dffd8e907840a1176c897db67d82491c50086fe0970aeace956189af3566309	1623316789000000	1623921589000000	1686993589000000	1781601589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c12b20043e86f2e19bf6acb047420b1fc38d6b4e273b8517717614ed0b220dc6ed17d4e56be92cd2e7d965406f720cd846f73982db30cb6f3d94b29bfccbfc0	\\x00800003a738107f1d752655d70b3f6796fd72bd72b5d7abadb93c50a8e2014c2d3565abe9417b55df8fd5dde7dc69e76f7833ec643023592c9e176ba7d35d3af7443f698e6d8a2338d6293ee4ee9dc5d5c9482419702204d2f9bae449c9de4fb0733fa220510e722fef39ed52c494797dee05728bd2b182089eb4fdacd2b6c563aac369010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc33886229af015b6faa36d439f9064321f20a9782fa0231da2621a50a47f269baddbcf3c6688cf7aedb7eac35414a5fa82191a2f45f47d5d1a8f1b0515efba01	1637220289000000	1637825089000000	1700897089000000	1795505089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x507abfb69a675cb20ee6d421f0ad46e92198e3695a12c40c499f718613b43f92f1914e4bfdd1d4ea9b2f1884fe44fef835eeca2f07cf29d47f803c26148bbea6	\\x00800003d4cc7d68e267fd5046223b127fba377cdd5c04a355945128b74ca36e1234cb3f5e1d0c38fc782db34e099ec8d39b0ded074f1be3191417cb8dc3e5d4f1c28e6bd7c8236ef9d793ef5c7236851d22a016ff5efa4726636086ade12d16adca847ccd14db31f3f76bb99b52e6cdb02aa4479014dd673894aeede6a8eb5879e123c3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6814aac63e85753992c48b8b961a329f18aa692805b4d25d7a07d9a9a13faabfd53b7c09e750b43a7a6a35fcead544f24bd8f9b60c580a55ddff6fa0781f1902	1634197789000000	1634802589000000	1697874589000000	1792482589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50068b304d530ab111e5577aa6cf7c7d5cdea28567e13eac62d36402cab1391df0c8fe89250ae7801dcabc0c9ac9f28cd63c30df76a506434c88750a4c09bbb9	\\x00800003e96883696a7d270166e8a453b1fe40b13c8fedcdfbba16781f6e959e84d486cf0bfe769874e498154c9b9454048df0183d69bcf7da6cf74db6e7dc91e7a45dce0a9e6a3c17025f015d6391c09c235ff26fa163c91e3a524d435d419aff5425757db7ff2ec6e481fbcec93d6d0bd40be63b017352adb1dc389a90e612f949efc1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8c64e0b1c08dc007a89afbf94c077e9c47d2bd4303a422a9dbc7e8b193bd71f71122880930dcc2823dd8837f500fa46ca1b2fc64ed10e70ca8e516cb84459b04	1630570789000000	1631175589000000	1694247589000000	1788855589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x55229be21d08504e60c844173916333ee751caa095e1c59bd5f167daeaa9138bec7547eb56e7aa0f2278e0da0e9afc8f30dcc1c4df2242a7d615d92e3c2ecfcd	\\x00800003cdb8962f01c7475592bfbc67f387fc49e3e42903f6e35c056959d9929d545c5f098aa517e78db67b6359a79332b2f12c8b84d64999dbb8b5adb480415cbf59cd8affe7d7925a7c6355326d867f01ded4e4491210e97313745948a31bf74d3881d4b7c6ba36165b525cfbd9da628d7c6407da7145f2e16484e54b0ceb3d110d45010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa2d10ad3bec278c02b3bf0d91a25a6ad289b1006b6a61584dd7d9beb843a95be02d81f6dbaeae6d7def5aeb574a8c82db3c85d7b99f0be21fae0f4b25f370c06	1619689789000000	1620294589000000	1683366589000000	1777974589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x57d66a6018c298f2b82958268b700191352ad646aac899b9907272f641d32229089b6ff39c748e5af6ffe58e2e081cfd96ffe6059df13416b78a4f99a45e05c0	\\x00800003d4ef78b813e9498278ad73fafe89a9d638ae6d24524ab810ae3bb8990cc83001d839d8d08d06617ac452366e5a0c9d96f49dd02eabf8d728e5b4f43a18a448a57c49ec22690630abd8b0750911987066471ce726829a82ab948d49900f30aa0051822fa8350f4b3edaad2c60ea08d49d673f63bfed2d8a0763ed60517151b101010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x31888d1b2d0c0935795e82e4082b0b17c07281995506ad21b674a70d8f214e258ea2dee1055fced4a1950d65155a5d6b9a5725127aa9b082a92608fe56a3cc00	1631175289000000	1631780089000000	1694852089000000	1789460089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5b4e2dfbf28c5c63d96f15d0b173324c670a6d46226cdd7ae7896d34e5a438aa4047ef9110236ec0bda1fc7718c0a73cb770ab323d10f458de55528d1e2faaee	\\x00800003d00c34f4b129dcacdd2ffae358f50a0fe5ab96c7bb9dbe064324fe9df2e079b39d0d9303a8b0b0d858a5de466372882ea11074b3b12c5eec97747b9d485e2a296c9eb0af9d50501c8b26d22b7c11c6e6afc9220a29a83512a3e394897f46c6ca8fff287df143c63f4cbe3526ac637db16fc8d6a3a8102f895696b64bcfb7716d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x59bfd23e495905b6555e130b6c69010edd767be66b45e95fb2a9626c50b088ea2e2ad78ba8fb84fcf0b08166709b71898024bbd58419be6b55dcf4253b4f6a0c	1635406789000000	1636011589000000	1699083589000000	1793691589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x602e4d40bf0cda32764af0bfc11d89a73284ce90cb82f0e453768e943627422a6857c54fe3e15e1efc7bf17cf31b5c63615f191fee8eb9ea64e22fd93f828d37	\\x008000039d5b8752cb052a9c4bd7000c556d8c5beb9ee955cc092c6c69d144cd1edf8035fde5f870bad0b2044580632b0d8c311c78763da7d4c0ef0e910175960e575058a1f7480a9fb3fb9814c6fa0659e352042254f722b785247d6322ef22ef022488afa2c952110b93dc1fd7ecdfb4a7e943cdbba2f77fb47145ddb115f4a75e33e3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x69a873abfca082800b487f45757700ad7284c756c5c0bff4667e14983a4bbd24a50978b72cfb99d888e8c94e5bf7f0f1a90458a736ca4346eaa5db703295810e	1626943789000000	1627548589000000	1690620589000000	1785228589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x61d65e23c2e7adc2b8f44a4c0573a3f8f653c71380ac2412c9b5e6050506eaea2748ca4a273d883312f4547c0f3a9978baca8e3c8cc46c1f6913575505b324e5	\\x00800003c3f6e9cc66b7b329edfe6e348d86c1697cbb51ed2e8a822ca1f6470a26d19a93deb8633034053de03dfe2975feb6b71c7baaeeffc81613022a87f2e3ebe15dd5222b4bd2f954de67c7527804ac170d045c79c4ab552a07bd85091553b62ea66993f3850963701c3b4dbf8ecebe7a6be209322a6c9bc3eaa13e11cabf193138bf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf7267561cf9af75a8042ed867b5979af72066bb59475d375459d243f0eb1cd739938a17b9e73e646991fc7325112138a460bb8bba0f9f0eb348dda5d9e31c403	1639033789000000	1639638589000000	1702710589000000	1797318589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x636676a506490fb7ae5af3bfe31a17470a22aca62e984f6f88bf55b01935d839266fdabcb5c086e35240b78f22dcfc98535fa1d74b8228e4858b5ee548066c55	\\x00800003b6ef84e388b7ad7c7bec4122533d472b29602b305fcea255d20cfdec67bb65f8e22cd36e77ea8dabc050f8a010bc500e794ae491bbfa956b8c33c765140e05b317b77103213dff0c06e29cedf37cbf758387bce57a56583ff260121c3e1113b8f65f5861844743eef58de80df3d36881ee2730eef0a8d35902c0695afa8f8553010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x62ee997fc30c9532700cf29aec67ed822a16e56f209fbf6e7e716626bdccd174006364afc54645e2a39b05f2139f390ef80be49b1f3fc69e0875cbd25417ca00	1624525789000000	1625130589000000	1688202589000000	1782810589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x64e664c9ccba58a7fa5d1ad9389926e3c5d6b8243aa4c7b4b056cd8d1adcf078bd53f151343cfac6cfd91be715f32b04c4c868e631f26f4dccafb8a9e8ce6ce8	\\x00800003b61a7fd35d5195f27af6214132c979490b06203d22b12b466629f148fed5aed64a21efb7d63bf0a82e5bc7c19aa3262998513f7754d81ea60e82c4ff9347ac75c032680b7223d5592a02c668f1303d89f91614de7c6452dd699645c7d2b8edcd175511825e8040af054b4ffd999a1a680ecd07cf72df6559d3bd5410b82320f7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf060d813c606bea9c8a85a8331e7f5e717a5f056059f7339cd5f50d3d47d4d44329d4b895cf9b8476f5523e3a45d8e86fd0e1848fc59f33187dbca141d817f01	1608808789000000	1609413589000000	1672485589000000	1767093589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x644248ad54d15f7f7713036d7a29bf14ec96a678f473021f273e78d9435da4c597dd74a157bf255d612816623c978f726f2a0090393cebd6f1e2cd0eb525b453	\\x00800003bffc7d620b02b1db9d7cb92a618479ba36d6c2eddb503a1f0ccb5fabc9092fb248ea0afb019b1e1c538ed97d1f3dc10c6a36e1f4ef7a2eb328f491a37d09c4697980e78b4bdcff9216cbd6ff3a8e780793a4696e2bebb5d4cc3d51143af09a9d50023e52cfdc7cd2d5fdd1418cad85fb883a81fd22a985f8585e3e2c5d7487a1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5894756b6d949ad7a396c5054766118db8f579b7aa698af582258945ff53e3d103ac493c7c3e4db18d6710fba48ac44dae5b68cab10ee8c6507223c6d52da004	1631175289000000	1631780089000000	1694852089000000	1789460089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66821d1a9b4593324e2f009bbee664dac4b1146e262db4fb87f1b81d00c423574dae7f9fe6946d0d36aa7e0981e8c0d9ac551065e2171cfb2a484ba35787a2fb	\\x00800003b13c6c0395bc8b0c843edca38f46f64d9536729fb916636950324ef354e4bd31ff78192b47d4f0f1caa5ccd1a241a299023a9b09d0e39edb1da15e6979d2eb6ac023340fe3765ac946859dc9d8cda3dcedae9efbf9212f545d0ad82fe7b9d6cf2d1737b4ca655bb24bd25561bbdbd6b8f46700dcd5102f6628e9034c2c9e6943010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb02f67d078ea254360fc8c552b00b741beea293333a4a5e25ef8c765526ba3bda0c3e56d223561eb132766efeba19baea0ba92151eab6438890cc706a19ba604	1634802289000000	1635407089000000	1698479089000000	1793087089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6a6a35a89f12e3df1c0ef1695e73f226d50efd78375e7d707f2ec4c32936ae28e9414b38950b4deb1a78fabb714332b31dcf9daeb940a674008965d8a257d554	\\x00800003c41f264e20dcaa0027c438076a03cc884e96de70d520007f4fb6edfe9ba05efe21dc0c9ef166fbdd1f08eb145c0847467748a0a872ef1f8d11836c44ffe7711e4e0f6f0d512641fd141bdab7d3772edc8b77c8bf606d23264b18cd63ce4d7ade296a32aee9500f6dea23b06f19c584d76a5ffd04c135b1fd1af509bd59128d39010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2077053e6f3129ea8b5e1db97887d085c6770575d13b2e5c92d66a5c8ed0f3e78af584a06dc2a72371927ec760ec1c0834df37324d2161af7b0281d8ac8bf907	1639638289000000	1640243089000000	1703315089000000	1797923089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c06fc175f144908e9aa8724cc714af68089437cc9bcdc48cdfb7f119bfe34a0a979b8652a78af01e5058e5ec875795fb0ee5b2bca7156b8b362b87bc9d1a782	\\x00800003b2dd6a259522e8ae8cc2e1ada3d97af92dc6f085fe9eb1744c8408d62220fa8d012110aeb223c9c11c9a4a73f3807537665bda65a6cf1566c292ee2c48f565113e0f3466032673783aa03e6c29b60a726c17b8c73267cd3721359b2a8b6dd769670389665faf0e88a3a6766d36fa8241d6bdf4eaa4a565fc957cd482272dac29010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe262b1f3ed69179659a815224f64faff479652ffa441d06ab4e2dcedf33547c8214b84db1aeae5f2938bba7ef6b40492acbfc142f7d2a67c6cf2035e3d7c5901	1620294289000000	1620899089000000	1683971089000000	1778579089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71eefacd46a7d936e45d1e60235e6085dad624228d3d5b113394a1e609ba785fd869e2e11570673dcc5f0707c1651752daf22fa365e8966f7ccabedc0305318f	\\x00800003ba0efaf960a5f42094e7aebe6a927503bfd55974dc5f4082fd594728e4085d6ec5ad6acad2a9b0f8e60ec0e97ef8aca21c72cf5db42046675aa8d71117ef980dcdeb9f4ff6a83c33b3165146b12fc2e65767afa88e15d97875c909c038c08aad1e768b667b81f2a7ce8aca7be89824e155f626fce7f8614f7b047a44e8ae960d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xac82be2f9d458956325c4a113bdf9f1cc750c5082be30c8b1d4661a81e8785891858ba35647a44f9b6cfd3f252039293cff3661ebed299a609c711b3311e0905	1616062789000000	1616667589000000	1679739589000000	1774347589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x741e6c8ff6c56ea791005f000433707e0635426c8e78a000bcd529fb54ab031baaef39fe118514b64fc1c456b0ce8ad964c3d54803934f7ac9d2dc2c6da341a5	\\x00800003d997ae53773c3cb5bbe25f210a96f6c94e14545c5b693a8559d70264c464a8a6e0619c20dcda1168dcc98a26bebc003b1c5092c25a16d26d53634d76530f97631870518388d70518e85182bb4e731c8ba54a86335b3ad2240ca0c5501e897ce05ad7c0a1e29989c998418f41c551377bcbaf00601d180f18e5ab29b26aefd001010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd30edd298b2f6490f4ecb9e103a3a4b26aa23b6029d9c7ec0aee5d21694eed80dc24f3654ab046d53f57086b1f0a393930bf88b5b986f52a1ea1b4a4c8e7e40f	1622712289000000	1623317089000000	1686389089000000	1780997089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ef25aeb990277ca733cc120fbcbc6c8bbc0670c24a7159ad33acdfae328b8517c5ca0b1bc92b1b99e05bf29b519b81149fac984fdd7eb195847a7a667533794	\\x00800003b5c2750f763fa1208ca7b15ea34f78af691fbfa258c4235286421107c006022691b05a762c3bbb7b21aab5c2fa0c04ff5534208eaa18e2a8025f392d1560779c5cdb078144dac24bee1038fde3f961bc7a9b989af57a3bfc040bfd32aff3eb4cf8574cf080e24f05d83bd97f8b9a73ac6e866dd7fd9541e76dd84908f33d7f69010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc5c83e9076c0a445998b6cdd2a609861e5d59cbc40e8c35e437ff6822bfaee6293136f67aabc63909b93901cf286ab386cbdd507229933cd9344aab4044a6603	1620294289000000	1620899089000000	1683971089000000	1778579089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7eb68aa3a27236da516bb7ac69fb6c804f6fa4d36b5e7d6a2beafa6f938369c50ff67178015b58ff2b31cd79c35b715387272ab75e88730269a5d50c730d4048	\\x00800003a4f015d4fb60d36a63fee051546381d76ad92ac6249047e878afaa1a23c2ae8d78c65a185ae7a5b24faf79d04afbdef5274476aa0a5988aeda8d200e96ca5c540f21613955865aeed3f4d752e368c548daab15614e59c687aee59b74d081a536f4a45f5edb41a65810139cd708f1f1e7457c65b3129d89a412597509c87358b1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8745bbf8bb0d55712553122be965eceb35535df24ab639822f5e212fe99aeb88e1e9c4613b1e8d3975ad3018f906e5571af3b626f6ee2172a82b95e6fe1ef904	1608808789000000	1609413589000000	1672485589000000	1767093589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8176e9c0564aaf8fb11b1245c3cdd1c6c3cda4e44b96cb1d91e815dcee5abec29647d0121950cd1438ac2ab4e7c483b519cbcf87c72af622f17872fe79a06cae	\\x00800003ba3d197496f6cd13ef1452c913100b1a7e2028ac08e71dcab7b58145e7c4a5c88bbb7ecaf0c47d66c7777b4acb62fc61de4c9d887f34b318f6a85f5b8c70fd4d86817989534cff1e4e596d47b91f8de72b919808e0e37e53786709930fe3db3c3cf108e084f0386b8a883e20955c77fdee367c42c93ce1afdb78ded7ea4a81eb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xfd6fb645f4d0593c865f087fee3f6324f6aacbb24ebbc22a624549388c0886925b95375ca5d763bc9caa024c24eb0463d666220d2a45eb782836c785cfe97808	1614853789000000	1615458589000000	1678530589000000	1773138589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x830664e3de56976c3f8538a645635bc9b664c57d8bef573be7525f229f95ccd933d54437a728ef27c355b8c6b319cc916264dab55fc697bbd03cbce7034423cb	\\x00800003b0c7ed19a3cb96ecabb2a037d74e02b4fc05c060a0282fee91bf901ce9350e02cb7d174e2cd9a8989a894fc262dcb4261cf77d6a6120cdbc66dd63198e2afcacc1c34c163b9cadc1e27c255802497b3d8caeaf9e4cf1301cb89b48b4513b824d52c286adb68737d93b1491e18be4f37d6619d51f3ec9c8b748ed176dc57c45cf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xcc772f6996f7f23643576c04b9da5afc6731c4006418624de5285ba90e2cf5d77e9747c4ad67e11ef6178583471b14eebdf1798bd887fcdf541ebafcc036ba07	1611226789000000	1611831589000000	1674903589000000	1769511589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x859ac21ea79bc64f5977ae25915a1fcf0a90ba7a51473148d6f360b6c0326a6b88feff70874ff73e5f2ff36a9bbe844d61529683b86df8a8b9313b0632838180	\\x00800003c0552be379e54d2a5bb6ab8b465c2fafcd5071aa7c34d0a8c7bd69fd967870be7b15efcb170679398b5328ea55dae4b26f57dad12124d636f2eb49d9d1094f9ad947c9f2f950e08637bc5c0f6499b805fadf3a83027297e6c611bbad20beca1eef131e7d391edbc342a310da075f71fef39e7e10b1e235274bb66b335fabfa2f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xbd202d1e2d84949a53a69735931cc33ad2e7f98ce497ffb653fbe745b0dd981c3e893f33d4dba129817a75e8beebaa63feed9a2ff91ba35d83fa45b48ccf8c0d	1623316789000000	1623921589000000	1686993589000000	1781601589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88b6e3fbc7b467151afb9fa02bfbddda5f6879915a44613d532f7a66185ea698ed9af893cf79d53664e10b40c572d089a9a26f54e41323698844de84aa37e4d6	\\x00800003cb08a7a15c8f0138a436c94b839cd8c227b26c1cce0832c35721f389680d083ba871a112955baf43ea249abbb795d152c5525909154affef3b4131670f9613ef69001ed8ad6eb7504692c3a1e988f17f2a5758cfd0d5a75adf4ed10f869dc7c005f9050b1238ffda0a934e7e61d3cd570ca5be45cfad845942c33559b437482b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xddb0868b0614e97402cfab606d3aab00e4f5a19aa4ed259b594cc1b36b6c654163806555c7d05979face9c6a3d2eec185f7752a459da41da690eb1d6fef13d0a	1628152789000000	1628757589000000	1691829589000000	1786437589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a2aefefdd10a8e4ae694602318cc0ea72a200b6df9f8989c1b645401a08adae78c0bd4638bcc13ef2679355ce57981c7b425fb6e447145b46975f09044ce132	\\x00800003f2592db3075f6423a55547ee3289836451934559a9489e5a019c3fdbb2c8a6ba1a8d707727fedd685e1e05df19c4cc71cc38495ecf7ddd56d1cc9103c3d86a5a2690772db7526fd388a91959a51ae332ce2627966933bc8ee6d6f4b66064e628e0a446a0d81a2f84ae405007bd253bd5e1983a8ad559e66a0ddd7cb2c45022e7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x346c4ab24458ffde85b5e98985d69c532b4b0a0d985f0fcc01d1546398b7c1db14a30302a16d16854d012ad54edd886364ba2d8442889fd52426369a5c6d2e03	1619689789000000	1620294589000000	1683366589000000	1777974589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b36700d3833309b5981efb8d9970c9369ded72ad1f5fba61b042913ff9658e0969d890861b58132de1c32ea3e0459ad577b8a8a21a82c59aca0c785befa52f7	\\x00800003b20dfc4428570585ac8ab58aa3030c2b84e6b6a6c1c98df9f23ecebe316af2de804aea0674ba6e311e04561cfbf44b554269889683efb59c8a7cf67f20999731405972547e16b8598fdb76104d3bd26e8448d686ec21fef6ff4a0e57bc0b5849ef4c4d60551d1ca02c57be8db0edcaec382e7dc29743a0c4d39c141b2613b07d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd21e209f5359365e8a82b557177fafeb15bf11035900e2ed06e60344bc3cbb2ab1c23c7ab86f9cc2e7a44576faaaebb881c2a2f0e6c8709514ef9b47b4022703	1629966289000000	1630571089000000	1693643089000000	1788251089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8beea228c4e0ee0b8acfa0d8661906abfd2bb4b905a4c6b2c337869a9b7960fc5617225a4aa0e10f94380824e49d256c6fc3cd2a39de5913ed69285147df3105	\\x00800003c30994109da1d4aa57390a4b54e33b1190df985eb125c003f3d0037f1b4849dfa7ef74535a74224650d78fdbe34d9c9f5fa4bb0fdd7ae8363e267c0bb08e09371425c6765916be5707a0de3eb44f5200e8032ba92c97d1b0575bf4b7507cd5f85a402406fa855f659d5a426c36ced1e48057ce5191420c309511a379a07b3721010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xebe7cebdca65d4dbd6d0a63d410cc520d90667af3e3e160bad31795915080f495064d320c37e3f20d60baeeb186b9542c7d0fa2c09b955d341a60c8b6ffd320a	1632988789000000	1633593589000000	1696665589000000	1791273589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d9eb5630343cb79c8a6d1e597bd5a460c38597cc6f25af36760bb88a0528341c1b0ab9be0029df9d836a66485ab907800a970231b59b896ee2675d5fe6b7c6c	\\x00800003b1f43270b0e46e8d4a9029a3bcd3d86487f30352408172588ae249b9abc004df0c005c55d3d87d3bb1250bd661875a33067e56ca12c71b81aa5ccffdc9520ba798eb026273aadf8d29ace8b4ed21e9a35e09da5b25b8cbc5c47272d4a27fe09ec938b1dc532497ae3ed7d552087eac24f9f7fa1fce51e6d1023800c840210edf010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe19f242650019fa241d87c8f7e12c5acab2c57459655120a48ebbee53a4819c3b079cc7747391f450cfaadb9df3fc2d697adcf4828d12a6b666cb41034e56001	1614853789000000	1615458589000000	1678530589000000	1773138589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8d22091a5ff6f6218f74b2fd5f5e42e1ba3b7d686be5168d9abc345ffa7dbd76d08d31340e2b85b6bbb0f944e4990ef644c955f96d09785a1984fdd8aba49550	\\x00800003d211d5df9f73641446bcdbde8ddce72f799432763049dcd04e48611a64bec2c0aa11b676755609130553b85213f863d8d3b51914aab9a149d66936f6467abf007750069a91704a01f46313f9ebfc543989cec993e0a5b11ccb833699d679939511ba4e9f1485c6fbb888fb8372c27959e6331b307341a1c86bcffd0023f168b1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb95b2372c22412495dc0831fa662c4226c5dd7079c11696257797df49c0c83613eec5cac8af67a50d99086952e0d7636023b43e6046a169175365f5537bbdc07	1617876289000000	1618481089000000	1681553089000000	1776161089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8e1a03cf50a9ddde401a8ccb070361d461227a1d6aca4f34ece691f8ed5b5a49be2c45a120444471636664a1d598bf2284d06879b019eec687788e34332f270a	\\x00800003cc807fe5d78bc1bb83d0d02f97f6a72aa0688c30f3263ed3a7f06d146535cded3580c1a130489533e04e9967198f4ae1620c78bf2d48c238fc438f6e0806a52691d7129f312cf090d0963d58a88870cccb299d6b8fcd0e2c29cbacb4506b4506f86708681e2ac91323298a8f2997bdb2b47b5f4b4850698ce15b5cafbbb230ff010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4e337431eca07c9b61c9fc598f22b22d773cf0676b8264572c0d29dfb71be64cda738b11c89b4807e4912b3a0fbc2121fd3ee8233c31ebf696ab042de045c20c	1628152789000000	1628757589000000	1691829589000000	1786437589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8e7e093bc69483bd3cbddbdd401e42662288e1535e2e762c02ccaa2aaa3344dd135126a1d7f0efc708c2ff62552817db26acf8cd0f89cd178ae5926f6ea1c0e4	\\x00800003c682f53d2e2c37ab9ffd0f7dff343cc95ade4f844f4612e8dee40570cfa1ee95205fe95db916f1c26a620285c22cbc3d0e8e2697a43be29643e8d123ae35b06ac6c97c3549ac176fe5393eca27ac1972b486794975c43914aa7d651a13e1272efdc7b637739724418836011afca217496734917aa21d792ccb05a52b009e7c59010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc0248761088ef90fb9f5180d72defdfd2f970cff5ea2aa58fb9739ffe468648a33e8cae655194c1de7cd69b43c6c24de73a3dae7f3d0650b4648e3a794fbe401	1628152789000000	1628757589000000	1691829589000000	1786437589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x922a1c0d0c6ccc46ab2dbb9a0247310e1fef57567fa7179fd38f0ee9f50e0c067e3ef3cedeeff49f8df59205c609d622f6ec1e86800861977c0089c8380afd46	\\x00800003e6c786f5df957d63eb28f7248574c31cf96f5752eb879745273cf1a1a716d2f5825c3068348952c48900d4bf69783e912b0a4c13e6f198b21339a23b68a1ad97e24673d01b08f3c8d024fef9fa4129b9fb0f925e8bf6eb872f0767671cb8eabb65eb737ac1dbfa03bf96f496055e0ca447ef262cfcd07191153bc7ea075b65db010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf90a7e8046b7c624501ce7b77d2a60a800f3a3346509256c789c37e339222b8786e5d110dd4688381ceff5b9c9511c7ab1ccd77ffa0eeb8016553537f1ac9d05	1614853789000000	1615458589000000	1678530589000000	1773138589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9856e102bdb2a7f2ce040f018f54a16d54bc18998d50768dc41b52eb5a89bdbe3d9796abd7acd2662277c845db2afcc71315dbd752ba099a50dab64766b8480a	\\x00800003f06d16a22667657a13011d32243fc3c3f74ffec1672a6abd7d56b7dca2c98cb7124ef7d06a78182bb5f0d0884dc33f92eb72cf6873d519be2f25f95c8f18010e084ce18716210781f5f481420dc854a65686015b62b8da206becc84f4cf6462957c4c54efaf1ea10cd2cbbbc413c39be963fb939fb1fa2ecf55a9cd8f4eb6b7d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5444870e8037f3f852540a32ed4bf0fe7adb9b0a1c56f3881c2b661b311a482f5adaa95633100608e8a547a2e2ff660d33805fa42437a8ee59ca38e5620a0a0d	1630570789000000	1631175589000000	1694247589000000	1788855589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a2ed0da3160e257f454e4887563b0d4495fcbe603cc9cdf06cdb80eca4ceb888662e89376759beb66d9f1d69d8f24401c18c5358b11b1297ecbc784eaf8f5d6	\\x00800003c0cf2188ed703d990d9115fd3243836a010a3382b47b4dba4b30fef667b2df3b755b279ad1b3225e28585875b7011fccb484e97442e15855b68ea91bd94b68a8401016e30b1d007fffe7e559b1756d2d472896eccc5a3831bbdaa19b0f3e5da60b1ae49fb4d2406f9f43cb05e2c66ec6ad659e6d45948ad87115d5757f3da55d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x643fc2063559096c2990b7d4158818fec8744d2585025f3352136b07fb3953a92976159c7e69dcf6c0ca2246ee1cde58586f1549b1f93380eab6318494f8d10b	1630570789000000	1631175589000000	1694247589000000	1788855589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9adee060cf538520c46394dcad073bcd5c5e926b56698ef56dc81dffa8bd0cfd5c607784d6a72de04fb1346ca91cdd00d280faf86413a4b79790cb88041e8f8d	\\x00800003bafa4553970e6f8af3d9374ac150d91bf719973f84e7d8f7aedb580fd5efa668e9adfd6d111eaf58abf80db7cc613ba82e1cb383ca8d072d07dfcd2cab617288409b75745b4b0c205453a228b15c6b1facf6be85b12ba2ffdf9672b98abd515e579c377e43e3a57ebbc8bb8532789532c940ad2223ca643d295153343de94d23010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3b95579542566e6229f1b7b5b6dedb82e7cc0d7d3e07c805507c03f6a033d51a79c6bffa8ea0725f3604ba2b895c82ac53d7d22b5235a289428636e82d156a0e	1617271789000000	1617876589000000	1680948589000000	1775556589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x00800003a3980d895bd33489c3e380c0b7ad077344ea176f15bac240a40801410c0a709f7bbfa46ca93af66951b7920b2a4797ff94a4d89e45f9eae5a0a57ffe15047297d031313fb6f31f27356d2daa519514038bf145d38f90380bf03f744fb300d959216855a052083949e4f7fdcb2345366a0f580dcfa4c9a6136f5cb72f6975b31d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3d4c42132589fc50a28393155324d2d1bee7d7cd8e3ecbe5f0a41ce4e246a4eb4593fdf9e100533ef142f027ffa39a59732cb6890e2a0dd619ea73def1dd6309	1608204289000000	1608809089000000	1671881089000000	1766489089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa5fa3f86fc1b80745ab3d7234b80f7094875e4ddb1c8d76c543cc9fa32446e51dd8e1c6357a5d91073fbc76331ee377b72fbf063ed80a3a6cc7c2739e0e0d222	\\x00800003b6e07fb60ce6d7ebe5b22132cbea27a53e4a83ab23d0c7808fac674c52aedf3b9db5fd689d1bc9e387e64c7cfaedd639b805ad6e7c37c64366b8068b393918a678bbac18438238cd51c6c97a1fd3f655137617c394150b28f8dc54cc3fd2e9ea15d079aa5b293759f18e7fa44ae128c57f6ed77ac9b4c133ce4f62716bada5eb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x04be964979f99bde99213e5967d5e62dedbcb14ea8dbd40e7683f503a17bc581cb8e4a0aab87244fb378867a6cd3296d66bd2a62777b1394cca3e3bb7d04aa07	1613644789000000	1614249589000000	1677321589000000	1771929589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa7761202e74774e119ec830c302789042d9413622b8a2d1e1a3bfadb943fa8f9141787e21df23d2eeadc49a7e0f66df5e58ed2d28ee526cc9b61c23874cf762d	\\x00800003a8f2426ba809cee4b9dca8dd84e63fc968fc55232190b826b5c1cc6106eebe281a73f98c0a338b30581b133af1e391d6c6e0973030edc6ba020120e30ab772871e11cdbc03161fb523d9f9a0f4ecdbc4ecdb24a9f6c8db2236e05819e8124a045c555c8574b9e06ab1415530169a447722f924f95021354695f8249f4df206db010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x45b399d51a0729d285de3d588711dd1646a0911ab8e3bd7c62f1f4895ec89cbc09edeec92aa2b5fe17083b65de6156f82f5b3c4f05925c87092d64a372e16608	1619689789000000	1620294589000000	1683366589000000	1777974589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa80611d6dd164ddffe7cfd3cfe2a9f7563160afdc114d4dd51ba8f0ad18b6d8335e254e177e9f1a1be5faaa9678d8abcec606094787e9dccfb19f8b0fddd2326	\\x00800003bd3d12a4680d2ae429662db1b5789b6f7aac0e96fb42b888391747ff9592314e3d395c5aa534d1e498d07cf87092dff6181de8f9d912101917aa8d77d94c165058b4fc1586efbe8b0a4a54da8d34d1953ef32fd8b8180e9c8c5b3fd51a423c24b2fd5dd5e486c9a97b4234abd44807e0a045e880ca8644611cdebe0981f27f4f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x09a35ca65fa5b6106bc31d1a54a6f86b94687424a4cff977336c1dcdc17c1facb82e31c36ce386358b3259b076a09661ac0cdb8f0b0a5c5c9fe7a712a92bb50f	1626339289000000	1626944089000000	1690016089000000	1784624089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae1ad05f94debf53dccd9c7ebb71f4457e39b40ce98cac09008d3ca326201e5d79de40099771932abc6116e2a245ce8dfef7b81755bbd84d43de699c8421996b	\\x00800003c0ec5ef414c7240492f2b8ab7f09e35e2e7e42f1e7619302e3270c8c4bb919b7b5f6c231f73769958871b1320856f283a0f72f76300d01278bd0eb4f47569328b24a39a65787a4e122809051a32f1810c740ce03f2888531e9aea2c9372163f3db1f463ca180fd1976c03cdddc6e7debe303fe5d91d2ac36784ef66d3bbc3afb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4f621c7e6e28537e6c4de91ed2b7814b79cb2dff4f3b88315a223cbdbb389d3928d1b3f0195bd5c80da509ed3acb6262d52413e46702623dff8f3a8de30e410e	1626943789000000	1627548589000000	1690620589000000	1785228589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2e675a4a755da30104b357ac71c863dd36d64298013d1d6500d70a43105048924163bbaf1ff8866e0922a44bf9e6e9b565b99d7887afcd3345eb1663ca783ff	\\x00800003f583e9bc208cae53b87af4a5736f32f1f3816059a8467bb5ddfda10fe298b2affb09722d207d3aeb64e63eb13e33d1500848de06df42422c086c0e86180196a41579cf214cad1e47e29b250a71b3fcbfb54e7af3f29f927937429fba4a06595b4949898c51544498e99c414bc83bc332903362192c59a7bbc6d61eb51a74dba5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x21572ed35d96eaa2aa96cea1335339267109b61a7c7b2c0b58b2f99a245f672722292429b3ed7c65f591d35c7ab607c9a88b08b43b063dcab31e19be51ace60a	1630570789000000	1631175589000000	1694247589000000	1788855589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb6ca21bf84ddde8e225a9b6b31ee1468e7d55b5dd5ed3e8bd46f6a0b3ef42c97112723d5e4c52bd856fb7d20c2ebc6564083473d51ab785de65acb8cca2a0a57	\\x00800003a9cd2a2ec9da6409c02308aefb2cdac93887afebb0e223f67ca9e68092c81c52780ab00bdf2f34ee67a2c337168d47c6d54f451dad9de995ec0587a0d7deb2765f0d1f4d87e6a20b965ec618c4ab3a6fb1415c0d55d8047de8bfa8e3cecb66ad7c107ba1bcfa53e5fc16820dd7d6d8200517fbc7f4f1e91f48c8034e3a8d4671010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x05d6225fc167dd0cbd4b7f4604cd635f77b7a3cca782a17eedccc4df375bebe9794a678b7898a4286c6a38af6d00358a0d43cbdb7c4cc6c644bbe6e9a77c1608	1614249289000000	1614854089000000	1677926089000000	1772534089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7f6b15e095aacaf54bbd7b5db9562e2fbe0decad605dc5df1c65431be3942adeaa3210e5934b5cdd34bfbf5a2ba3d773aa24a0edb70b5e62b9fdce8a5c37166	\\x00800003f093721ce0e1d440be9cd89febb5606f7f8a1a5e4f549d2cb4a80a9c73f6dd62159d3218e5453cd714d89ff9fdbb868ce145c0e891b401392b9a52b7e684253ab05fff79f28d32594fb93c23f386ef6314b4b1f36d567c6d10eb0a5be98bf49bcafcb4d41bee4759ce3d6f6bb152892c658679a8aad935756e1b00cf18011fcb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0163a0fb6fac76fecb567a78609aece124d65f0f1ea286f97ab0ceb91334404df8ef1779b01d06dbecee125fbc74e2b20d2f69bedf261a1da17534a3e6cf3c01	1615458289000000	1616063089000000	1679135089000000	1773743089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb7864b4ea1c087eae351699d5e6b31ce169483a146f4eb039f12622f97e026086e05f71ebecc11780f7790a308d1baa3da0536221e8fcb550eb71ab0f5f37769	\\x00800003ed4ad55d261ecd6ae7fcca8959463cb48192ebc664ac6a3377ed3a9a61aae6e31f5b76cb5d2cf797b3960d6163f4abc76ed7fedfe3fc96943fe761a2af4ae128913f24763d01c6396726642a6e9973ee9436f185205249d9b2c1191aa9cdc7e163cb61bc3f619a23e53e1d2cbc7d584b558d682a00bba841f0bdf0675fa3f2fb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa347387c3e39fbddc5558147c6b6416c47974798d294c8b8e097b00b1860a012435b1afd12b736a9fde3b91b63f9df83b09437b1496e8b945e0f3af831ddd502	1616062789000000	1616667589000000	1679739589000000	1774347589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb85ed48822f4ad355bb04da7925d9d73473423604fe24dea664e713a1fa0959d4b2b82487c5ba2a03d3e043e4f3babfa34c29e94d9b0be377560e5f918717453	\\x008000039633237b209b9cca93b1179c2587458994fe2b2d047c9e4ad54b5355f2262004c046c8c2ebbde0f7a74f507062cd2d96f01c6ae8fa0b0bb1525aa2181345c33f94c86a0bbc207b010a48dab3a6f03dd2dbd923d92945b0c7c2fe118795df9ad7f4d9bdfe6546d827982e4ad7812a005120f6e3bbbd2a943f2ef27ebc755dee27010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2df70e5a18af8012ddec949e0ea8ba2839a13229f6c5cbede77c84705522bd1ac1ac864edf8383cc819d95a7cdaa991e6c8cad6db26b84ee5c5cd5272f990205	1634197789000000	1634802589000000	1697874589000000	1792482589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xba8a12f98f6edb218b49f1577fe9a410e24471fbdda9008334f4de831ace8128c6baad6416eef600759ed07e8bb9f3153aadc4952d69318d156b8b846df29c2c	\\x00800003fd0d422d92abee45e31f5862f367480b0dac49e0e4746d87a2b823df815c2808c1cf1baf46f5bde1b0d9e1f348a18700f6d2f1280fb07303cf37410f75518e015112aeb7b8ce31d5f5164c1d7f10687561305a8ccca91de371a6142e19b747733683efc17e0b84d2d1f7e2ce91a1d5d1e598590f9be471d5c04170bc9d7e1c6b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4a39317b2e09604c8a2f413d2618c9dd6a311955ed80334855bb2f765802af394007257ebd660cdc30afb8584b91108bede40ff07fbe01421ba1381c9382dd05	1617876289000000	1618481089000000	1681553089000000	1776161089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbcbae42a9d01482002871dd03c6f59fba6bb114f0d9c3627d102bdfb4eab4f040c84d62edee6f8db1d5ac0012b7aa855f39e266e68000eaa30fd4ce01ccaa8f1	\\x00800003eea8fb0082591180ebfaebb7258d9d21228fb398cdd725c168c5cb1152bd8840fc7c2393f516c333c8f2fd35e67cecfb41391bcaa9d2fd3eeea529d5714acb738bfa504f17fc67cfcd20209db5a15b2a7e472de188962f6e70e957b0797aa9117a891383fe4d07765f3ff7e37acdcc9d0877afdcbf7fe3de6ddcaf33439ddfd7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa76664f20a21dea8873795e6ac4563f316b36627f9575a3f846c6734f1309f895e120acef88ac59834a6aeb7a602e84969025786db14425b6a72abd37a91b700	1626943789000000	1627548589000000	1690620589000000	1785228589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbf321b0b9ab4ecefd20e4a984394a91495b101a0ac37b77675aec74e8730b450501a142c08d8b44bee18d6fca82a92157555a0b6c2eeb71c59e9cde1ef1a86ca	\\x00800003d4bfda172b9594b79f883bbeb0882ea1103ec2b51e5914437694abbd03ed13d443d07dfcfd087ce55a3d08ef5680b841574db75f1a3f0e252b578d26e4b1e58c3cc0d2e5c2920b15a4764f8a3b024d4af27d41286b7228dda64595cff56fa513dc5eaf79605d658d3be9b8bfd6ce6fd096a9bdaeb53e0164e3fae5813fa9ce6d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf94e65718fa738fcbe1937367455ffeb2e3f208faf9798dce2ba61ddb0d8fddfc04181a316c9eebcc2d4a9c6fc1d9971312f0ecc092d2d1ded1a777d9f08780d	1638429289000000	1639034089000000	1702106089000000	1796714089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc0568122a386ac813982640670d78f4f050c66739f67dc68c4091558238502f3276d691d9b72bad2b5a961fd5f9d50c95aa75b923939223bb33bb73010910dc8	\\x00800003df8168491df57996e22f6635d7f197da2481c4821fae99389a7e4e87ce7e67e4181aab562261ba1804d8d66b87ccf93cf0a0b5dbcb9faaacf86cdeb00e53790e163990c494ca9a384166c6eefc68686bf46991a0ada4f6e2b640b1b4516d59648d8235226da17d74f32661f4fae9ee49de8c75831aee8bcbca31b6492d4808fb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xde3ed750fb1c59ca5d078f810d3f01c5684886abd9363952d536e809684428f878e025e09feeef58a78fc22a05dafc8da93194dbb90f52d3a87c2316ae02c606	1614853789000000	1615458589000000	1678530589000000	1773138589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc582224bcc58d52b411a568721e9ed63f68284f045a66b6a0271f94f758d3c065376fe1fbd00eb5326d807749466147276776b564dff4fb379c6255e4b3cca50	\\x008000039dcff374c32c1fc9c372b1434862839fb6d9b25a3c9e3a0c1b436d853d474e8c3519b7ae582f49abc34da488403a75b401b3a86800f0d0782a43527cb627c4ac097284a043b77e308e0376a107ce18c3b5c3ec8d2659d1c36d5eaa96f41a74c6578dbf3df603c504e4e79eadea8142e69ecec2dbd2f6f5732eb304a5f172e6eb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xec8e79767ce6b388d38b38c5426d453c02a03414926b8d419549950b0d60a6abfdbbc55bf7d1734186b58300bab41fa6cd656a07fe97d960e5e0e2a0bc0e6107	1620898789000000	1621503589000000	1684575589000000	1779183589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc7da95fd04eaaed0c98a1df6eed527755a98095aa2111a8b4e848b3fe2912ba3ae08b0b7ae6e6de328635d75a3657f4a85e027b5a34fa953e87964e60eebc49b	\\x00800003e7c73ab096edbf200a3c104dc444da30140566e44bfe6fc011b40db1097f14d260d8c5436bf70e1ede5653a951f2f9612727a6c909d35f1585e69c23f87b4e219c7440421dd28e46577f3781d13774ca9a3c4984f99205c50ef3109515fe3f5b140941ec7debbc5a85f0baf1c96bf0dea97396ac7b0dbcc655aea186c72289f5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x213a261968b33553e59b6b59b8e2199f3aa89bf2ea6f43f7d74558784dcdd20bf9cce793c84d652cc9b9e8999e6735c89d8c5e09e301ad01b5745ea247a5c00c	1620294289000000	1620899089000000	1683971089000000	1778579089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcac600a4d3d71a91282b7c16cb2e05f8474e6444cf42b49acf12099a82feea651ad3aebe1dbd73ab95865f496f6a9295193234e274eb6ca18ffad6f61e74e75b	\\x00800003a0899b4fe21efffdd93d084a74ca1759ac7c3c92ff1417fdac86efb2471651d89c5ef6490a96d335c8aa731eecbecf9d95e26f40fce592aa07e8b64256856ec27bafeb629ff708e041e033cbf31c9525cf939c1d0aea9a55007c0efba2cbc32ebccd8b8d24562c97912ae1af57bd7ee416aaa3a069fedb823b1a4e1950798d3d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf51f142950b8b0891ced093ba2f723e40c6e0ba5eafda41d9b07bea749902b04167384edf945d3cb10cb6bd431f607528596cf0a466f8ba2cade7c7111a2f30e	1628757289000000	1629362089000000	1692434089000000	1787042089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xceaa6376598dd52a83d16733b55dbeab8ef0e66d12e7d5b9fc7c9b5274b514f897f7e81190b1fd87c0b51ece54830a8590e1ba270098791983dcc30f66c457ff	\\x00800003d4483709b8e908f988d1f5df824a2394074d1d791f66166fbf72cc6bfb62153424b081c69cd54f6fe90b740f9882b770362f39aa5349717e361b699a564a0d2401f1968c258bf71ba1d23f5110387fa71147f87bd4d8daf6302489102c88254c06f1d8aca0eb1d99bd60b91c7a3a95daa5172329f40be3e0f5fc799fa369907d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3d3aafe1f7dd581508cc65345ff6cb75174e02645c442dd14ef0f6c6b3ac4b92dccdf6dd45edfbedb4ff73aecec92f18b76591d7d0380a8dfa138373260e6106	1616062789000000	1616667589000000	1679739589000000	1774347589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcf3a20a036961a9116d49454cf7412eebc290b1031ecb9df960a8b491ea51ec97d6ef4a3f2d07aceb174f80e81cb31247e70350137546c39ef9b02c80a465669	\\x00800003a8ee009535dd8b6e660bdc99e0384647e337ec50f78dc622c06a093d5ae425bbfd92e21e42d93bb3d98875da8fe14b2ee083cd2eaf395362b2cad69c63732bda3a63352ae04fffbfbba9a3c8f7504455f7a25be6d23d7990387f9c497752d1572531c843a8e65092162570ba397ac95d18e9cf3ef1e1fe38910c7dd35ee04665010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6cd64fe6e8475fb8fd41e2e6fbc46f92443b07780574d504db0e58ff033be33ce0f85420377947646bad8ac7d1a2ce84885988077c441a159b9c34a6f532bb01	1608808789000000	1609413589000000	1672485589000000	1767093589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd38679763feffd035365eed23222de8c8536c7239a94f797c35eb01cb12e8fd00305a1c20ab0716ee80b8ed46c0ca2ab96c2ed1e3375a9e0f22ba1400e213054	\\x00800003b6cf0f4b4346dd842793dc5c82efe83ec130af03134a9995dd2235516ef1c13b5ca4a18b5f5ed2ca4bc82bfbc4af712df615042c84db76d7b2b6acbca97da2e2f730072a0a09c9ec9dd383549619c27a93aeef70bcaacd7f30424ac7884edb654338acf33b0d918354db164e28680d612b4c8a7ee0c525f2bc94a8c5ce033817010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5f6a6c355337ea0cfa79c1c834404bb5ddee83ff0e17fe83708cdd4af683cd6ee3dff516abca996153c3cebdf6c1dc6e91ec4a671a3b0d7265e5646c9e63e10c	1611831289000000	1612436089000000	1675508089000000	1770116089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd62e61dd80912c9b21aa7dba6d288ef52ddcb2f85f73f6e5757ee863dd224b394a999a71fe7325a04f205f2eb77ae646a1510a992e0c17e5dac5778c2b3fe13a	\\x00800003df9f28c30c0fd180f65a6c95df2ce5ac740bb61d04652c875d16ac428281b4c48b3f37f8e682b3bf14c43332064f0d32a79b6b887d6a48cbc0cc53f13ffe2f724fbfc6d242e5777d6d82de4e70f651232367c4a058a7aea56f4ebe1d173cd0cb5d65c2263bed11321d5b880ef5b73daab64e4cbae9241dbba067c14e5567896d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdb16562e2b200508723c3c478f17ae767f7f7582eb836f3ee998a75ed7cafae699346a8d5ba5974ffda2941d496cb235d38ffb92f079d70fab9b95d7c0d88201	1610622289000000	1611227089000000	1674299089000000	1768907089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8c25c0452b5a52440d037128b9a616bcd7e330ec261718c711ac439d34c117f24e47ac27eea790811e54ca793de169411d65d48de65847e5902da03e0a5bd89	\\x00800003a5a44b80d105fe40d207326b59f2fcb9a0603a669aa25ce0118d27ec2df279d8140b9666409432cb4d3d9d6274f8b4776548666ccc50e27a24f9b74eb3269e64a46fe70a95aa9c747bca5b84d09dcc942a564fd259e20f120234d9bc6b971c8279736f165175a00b121837f1e45f68505e0c5fcc51c38640eb1030458e97a717010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x99f853236d44f356ca74f8749916c2a014b3b2ce525304b8ad23b642fa2001a4b567d965f252ed0db27641419718630c04318a529b2a970854bb52cb170c7d04	1610622289000000	1611227089000000	1674299089000000	1768907089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe2620513dc45766f3b7e6658a8fc9cad984fd1fb912b352ef224edced3d231cdad7a231373f431af91f280e591a814e9f20e35a3796ae25a536fb1708085171c	\\x00800003d0cacf6cb62c9ac7362a4d6bc80e24de83389b96b896fcf3971ce4c36f154d0d27c6e4dde56f98c13e175c406a19480a5765954b786ad860cc897fd66fed2d928e5ac6c7e14360a912e81580f6709b1cd21cb4d4b26a5275ef811269b5b1be06d457dfa26107b4a41515b6be0e5fa5f4d33a52539ea7db63f99a2f6d132423f3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x25ab115e0ee23925d8d9ae28874ffe212e1fa964b7120ce5a40b9b58be5dd8fb6d9995439d22376ce3745c88f84502a72439f3b7bf04a7b2af43e52dc7a44b0c	1639033789000000	1639638589000000	1702710589000000	1797318589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe88eb2bb869b87eb81dcbbf99d1e42ee7727215148ef1fcc859ca43f2f42b3551fc25faf2179a98b8801fbc4fa7171367a6df060d868535d02fc7a51265c9a54	\\x00800003cd7177b79493b12fc9ddb209df782d69640176e27d0b973185b479b7177782332b96e1373878b8fe7ffbb977a5eb68a15759aeb95b85de88ceaba86de93f110978b2af72d33e0a273a3a1b462575e9d7f9679514b873f57a1d0fcc7e49d01164dbf880770203e8dcfca668988bd1304264f6262856606a3edda9e82d70f8d305010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4f1392c738580ef70a48f97a151146f808433a461e586c98e61b7bbdd506c0d24b6344cdcda82cfd7b899987bb5e7fc72b652d6e2a6aeaba26a0e0780fd83f01	1611831289000000	1612436089000000	1675508089000000	1770116089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xec0ee2424bc7fe188a40d30676d01649cdea2bdee3f75d7a8ddbeaa6b6254e04ab337c685ed30777b843477de261f87af4995769781e20bfe0b9cd0b759f0017	\\x0080000397a569496d47c09f4a99c29ea2921a70437bad610e8ded4d0780d9fe343dbf9f3cce0156c2f14e7e78266dcf6f9f8957f7fb45154f63ebced8f57341db1bb492cbb3fa26fce3fb266aa2bae605ff819e73bb8025ca0029032a4fc5f5719d0dc3de668f155ce66d1b024957a80e5c506e131a01f2c715c4e71316f3578032121f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7adee4453674d98222de93a3698e27228608df6b263305fd3b75e2b790b40f21fd7b4ef56742fa3673ecd93240b1c03d4dc8eea1136d9de5f295d32b9cf9bc0d	1626943789000000	1627548589000000	1690620589000000	1785228589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xedea5e395726f3fc6ec329d96efc45d52ecbb01ab0d4f480c57832b707f6ff4f16f7760afb890884f61bebf04e04420d45c473a535294097f0fc228c4d65ff1e	\\x00800003c48a820d30b8df9216477224fa0c42fc2bbe014dff0cb69fa35edd58f7cf0b6f228f7db3be251e4f803c24cd687231fd2aa9354b310d1066e4c65b2bcba77921e50e20c83ebba2c3f3fc07c0326440ac13e4b2d5fb98e9add8ec11cc8ef87793db99af5dba091fa66899fbfd9fd90d6c2dc3e26fa3cfdc6ade12c84f24d20061010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x023af8f7b327bf5bcabbe671540eaa3a6a85d86ed25ddc3a612ebe527c89026ab58449d51142bc03d7487e37983e68a41f77d6be81afc16421046aac8d3d7e01	1637220289000000	1637825089000000	1700897089000000	1795505089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef7a8fea879faae6389c9ab0087263ca98abee137379aa920c264ce2b9d9bf01d1059857b6700e05cf23b1bc785898ac378aa592c054e55e42d596c6ad1ed271	\\x00800003cf46b61bc3561a8c4e49a89ca1812f5f1349a129479f6f3f7acfe39def096ba4163822cc0ed049188da12de2e0ab3d66e71ff0cb67f3ef4d7a08f6ae204ba44ca3393366ddbe66dd4fd629ed810e1bdc55e2e1bd3bea76d80d20248b4bab4032e1458e5513832855395d4d4ff71ed72c68e773d44fedb0e96826e3941c6cb841010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8544e5db1fe5daa225ab1f5476475b7f9e0b5a6bfd25eb75f627ba1f9e8e56f426633b20e17f67065162c55cc6c6558ee3a13e87f1ba9c90e56944597ec15507	1633593289000000	1634198089000000	1697270089000000	1791878089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3b2e07e38a58688083a282cbafb95eea11fb4883345b09b87dab2869cb068ab95cdddbe8a6c7b0b60fcaf5a10c1ed4674849fd557ebc5b83fe07090d9efd4f1	\\x00800003daf3fca94191c261f079a37d5bd83a4c0b9663e9a0c198b3b5be33b8e5178aa77fa4788dae6f4d075904469728c3a78358ca27cb2dc9cd9a238c2fc6fd13636b97e25f2e98428d23d5e747d6e54cc62065eece6fc4e12e2b30f03cb4a9a005a376f434fb076e0589ff7bf42ac06e7b528ca7a05edecf93355d4498ff0e29d54b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x55765d1f5c266b01681457b17a2a1ccdfb84e9552e083514e44530773dba6e97da64f917d2ceb58ae6ab3d8b3f2be9f9b1ad30adaa0fc9ed6cab88ca14ad1104	1610622289000000	1611227089000000	1674299089000000	1768907089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3764b68b91def6a70d72cf48a5ef3c6949f53b9fec9174e303f7de0d482024b7bf147c1ffc66fb05185cdd248d4f0f536d17195c9fb7618078d3a87d7cfc431	\\x00800003c407c68660eefa5e99d543639b9f42bd61482a7cc12fe8bb514497f903226f060c40760c70e2d5a8de34843a20ea27bd894000161713fc996b3f5328222176d56452a2eb9e0e93e66338f4678c7b45251132c5059faf20c62ec0a736495d278cda5bef2c9bc8a36d36ecdda06d58c32de6b800b827f168e26da95a2a2ae6cdf3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x73b35156ac042430b89230f2c93eee7476f269174397f3720b095e23ad448a4bad8b4d9dd1b25a7a04610865fbe117324ff2801796a8f3ab33f5f7a81362ef0f	1623316789000000	1623921589000000	1686993589000000	1781601589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf57ef558c1d408ed513e52aaefbc17bfb18b70ca1d89ce535ee5c5313074bc37491515537a10c92d14c3b5d5c8969425558d550e12d46d95e0f2a45df393a2fc	\\x00800003d0ec650493669fd8976e26d88ca3c697f9966b78baa60ed940b1dab26aa1c0d32b102986377adcbb95445a97e557d6e486240d32988dc7d1fbdbe241f3c82971e79d08f2dbcf7cabd5f9b02c82f371a1816d07a8313914a5f597d7fdfbad3208a6ef1d967d6325beea719d9a9a7574095d8f6cd859039cc41e95f24bc5422633010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x29be464fbd60a0a25d9bbc81f156c71be6308b6b6af6978dcc2bbb64e9785b817548895f434ee6ded4ba316a3f04b73ce0afc05cc6810eb749a759615095b20d	1632384289000000	1632989089000000	1696061089000000	1790669089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf87ea9d9a84861875a29ed07ea0ecf687c9fb50cfb4eba61c482b77c790a0adc74e1c3c047d16e5c10e533abc56979fa51988cae39abb246bb06c7f3900c1749	\\x00800003cdb91153f013bcbdf2e86f3b9a717755f0533796f23919c787313f97a8170b02266a5d49e30646c7228bef0ab7bf96cfe6054dd5c98cc25047fdbf4efe4ae7b7c79236b4c224e3615e049e6f505d8bee32b09131d43ea9a4ba235940a20f9f1a93adb5512bbf0211f2dda162613eb7e32ac095a08fe8c61cd5e4be239cf369eb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x89070c84bb7f06c567948f5b1e27c5a2700439a78dc492b1e4061f33f0b97150179908587330552cc8798caf811293aedf75d0c8e264a42b80c32993c2413a01	1610017789000000	1610622589000000	1673694589000000	1768302589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfaee1f71c923b24349243eead6ca4ee9824dddb0e21e5b3b440cde08ec598bf07a92889fc886c9490408b1cc38915609cdcf401d089a588dc0b85478ea53f69a	\\x00800003b9a502f2bf18f0be2aaaf6db8506a4f2214585a10c2effd5d954aa1c2e5b221c5a6395bd352dc5ba356c89513acbbb13b8d0a93e5a50293322bb4e5e8fdb1338f514cd6236e93764064be6e3899de3505a2e0bee13523aa641b344e707343668b52023950719f17f3bb879125fd4bd1fb71ff4072f71bbe426fbfa0e56682a67010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6d826b9eea785ab7418e0445d66042bea2bfd3a15383986feaa0910f694ebc71c9779e7c8df3f760d72e9516ed83c5d42b1a2c400e4fc39043d52873f6de0705	1635406789000000	1636011589000000	1699083589000000	1793691589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb1e20395894a660f64470e7dd3c3d10a08857c88cab1238efc799fbe0ad8df7494a0a56a09978f1c23da624bdbc1e344beb892c6be2f090d71c4008e00de4f1	\\x00800003f35c1334851b08724d0ae4991e7c1320a3250d6cbdae79384a235785cf0b7c42aa2f9aacb8419a9120bc38e95873966f5dd8ceb8bb15b0aa37cd8f5bd4d0620d1521a822328affeed809fcada7026f7e71e41667930904a071e97c35e5087f7bd412053621ff68cef9294aabd2a82171dc568c2f9607abd081f158c3a81f77dd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x82c24d43c42d9cfe02cc0e7ed9ff96757b7549f8d345d95cc1d59c3ed780dd17460eaa339fcfee1ae794df8579bb680d337b31fa8fbc9e9d18814111cda9090d	1625734789000000	1626339589000000	1689411589000000	1784019589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfd8214abe8c08c4b8c701ecd12adaee417fbc7a1c6a240cc94a1649ee2f1c12cd00ad63ebaa73a9d1dc81b799c1d50583814b302688b12fddaa6f3beae637ef8	\\x00800003ad688f336e957196c5d4f382239c8738d7de08d3f3b71fe55e8d7d93a34894da304235da67d8a0f1bf1e9c8933a15deb3e847b2d97ddb5b4df9a9be2cae31ba1632a4ede64c8765d0d4f70a1a4e50df9ae6a8b940951f342cfdd0f9acac9572cc7f0618b5620fc67395886a37cdb63646b2c2d8736c89d4824edf3087c37cfa5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd8c46ac9dabd2db564ba04c47532b6052de52e59b0cd0ddbd36215737f55a6f4d278318d08edd451fbf47d313cbe6a23ddb821ed4245f49cdc8361029ba76106	1611831289000000	1612436089000000	1675508089000000	1770116089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0147115f935001872222df5fab8bde5c9ee87caf46bd9583ae6ac92b69ebfa2106147ec569ce199c0a8332f3aafac63cc8d90141b1495cb728769379b0239fd5	\\x00800003e48e466206e6f3daff2a0e13f093100d2e7ba8a30e4c77e9a4263963b69a7c779c94bfd2cfb3b0a70a0ea65d4d574e8a546d8139db65c68e7dddb9e2c7328e3370db400b33ef1b1bcd44730c26c51b271d1b313964575593b907a505e46e699b19e78d480562ff97e9be5bdeabc9fb139a2daec96fac577b3c29ce8aacd60139010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x409e909d4f897f6c2caa0548cecba4c12c4919da713181a99b0dbcfdf603b56dc519c3fe7c2e065f049c558f53677d53cdf11615a57f3b9ff066ad314fa7e909	1625734789000000	1626339589000000	1689411589000000	1784019589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x03efd666321e621d522d5a9456ee8a08d5c10e61d857e390329a7b5d2ac203f383228f335d21e6842e081d6c6c6f516f586a8e319296d165cb09aeb54100ab3b	\\x00800003c7dbcf9268f6e2f675757f310a959cb9b51f3e8a412673679a0777c424320021a556976fe8562dd8c8be4a2fdeec1a7d80fae4b5025fc22fe151a9740d7cd9f2229f15f655a53f3abad86f380c847ef15ca46fbb73531efffa1fc710e4f2478120741e3ae32a3e4bf12b82d14759a8819122eded751388b8eb4ccbc3dd406c5b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeef1a97239504e1c09d932214a4325b4cd3ffac02d9148d0e796ca66764f1992bb708d743d111db4bb2e42b7541a91cb0353e0e3955f4fe54d93b2de833c860f	1623316789000000	1623921589000000	1686993589000000	1781601589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x066f49ebb6ec213bb762b60a8216483da3cc3ba0b386db6d34538be1da01a2eda5348d80a14c89350b1e345178e5a39a1a46b5f46a5c6d90e9f43ad91d41bca5	\\x00800003b3ce5091b8d537ad6d31a874a98995edf7c8c51d9cbbf1ea886db47897c54f1672ed0b89d3a573280768999905b56b975a9ae5b7432550218bf2ca0ec215d9a29fe263da4a8db1463024d9674a7b80bfda1350a75d50bb2a442424b7492f8c269197d0b6063395c919aea236983038e1a735a043210e56ef7e96739579338bd7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6c899acaf768d24244850c011840c2bd009b37ecc1247230e39ac51d52602ba5283853b6f70a11078bc3896eb8dcabc7044874d8eab7b28196e1bb08b30a2502	1631175289000000	1631780089000000	1694852089000000	1789460089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08cff8c4b9f60d2572d893abd76194dee57759fecee464e9331b72dba3357d15839573133ed09f5b4e53bc46cdb3f59728abd3663780fe826eeff3777f2af936	\\x00800003aedbc231b32a0e6a0a956bf744e121b40f8df1055d65427dc8b35029f07e4d45a55b4d8abfdbb9d75b72908b9e6f3b2a5cc5bde2c351565ff566d55d3532d7d969ffc49899042e1b224c1c20bd6f47861ffe3b1c35327786b7d0cf242e277618c9f4b9a1e2b9608656039c975d2a0bf9064bd64e9c601a405092485ea7bad03d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8bd08d466fa02fc4df53a3d392b52313e59b1d7c4d1b8b9fe685e01ecee3d82c0c33689b8354511fbeaca6889df5f9a9da299c7e27c5de5b23015b812ead0603	1630570789000000	1631175589000000	1694247589000000	1788855589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x092306d2573553fb98c4e8fe1723a8e81065f8ef46b175a2f71eb632c8c0f1cbe29c9ce65e58539ec9b32c36f12287ebb1e2fc5230184faf08ae9c7201f2b742	\\x00800003cf885ed10a41719c14ea540d5f47c17b5e043a0f2252b254475f788271d0d92f3850cd0ead4e4edc06192d708b497765aab85d2db82a9d316c40649492ec4a23bb026ec74eb91018f7acade9a1fffd210d05ef8823f7ab418b97ecc64314a8e84deb557207f9735b0b1f8b44041db190902996588a6d4a77005ca7c6c024e96d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x379d036f8b9ebeb70e9fe47e19eae1ac261fbfbd7b6f6e87037b918c4734f42a4191ac8ee2b97ae96a1477676020b86c819b82b89fc01e16548e5852c0d64908	1611831289000000	1612436089000000	1675508089000000	1770116089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a33a9d80e001ca119611ae305a18b58149378fa9f28f64ed216b40835b04823cfb0f54e8e8e918ab2babdc7eedc2c9015c8c7ed1e922cb5b54b069e2c337787	\\x00800003a1c128034e5c2ca61c4ba844c61a5b3692ddb8dad031bb855e59060f1ab5a77de700bfc0fc3648ddd2786727b37957c43c3329ef5692f15b0a1e7534d23643d8f8427ce66465aa987caf48db2870c3edfffa101c611b0b981b100dd917e40d5f66a3782cad59cb7f019d26bda785eae32f31b6feecdfa8ab2de3d1fcb123a1ed010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6b7ab4cb3adfda70425e4bda83532e08e9fd49336beec135e27a7a50b00aad87e38767da42fa6f1044e44514d6cbbd4d620cb1f93c88de8db168fc0ecfeb1403	1612435789000000	1613040589000000	1676112589000000	1770720589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f37be1eb1830c084039d13aa017e81805bb5875106c1c98603ef5b314968969cf4489c8a6a00f51686a4cd1831ec3113619221d3ac7c3be49b4a1638e7f34b7	\\x00800003c83273c524f7595514f64dc51b8282c38467dd471e475578ccfedc55db99e5d044ae2e40f2a6cb75a4e254f1f2a97a394c802a055226e02d63b879b0fee81d765d40f79516c5ba19e5bcec63b943d2f7423ce1787d11fbdb991fcbdfed787dfdca7db7b6ec4fc0188357046f965c7436f5f228a1960405db36c40b0c619d0fa5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb9f7756127fb8643f335394308126ec412377555f16f6f25ca71e2f67b4509269b7b3c62e706579a58aabe7ee7e32012b986fba40e126f8a811a76b0ba16d10d	1618480789000000	1619085589000000	1682157589000000	1776765589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1077765c6afcabb507aa2424c3ec2f33f4905e452704e18fe0451febfd832acb72c95c5759b76f2401e2d941296f474855886e066ef97378cfc23bd4709162b0	\\x00800003e94235390aeda41a0763f963fc87e2e795dbdf69fb0fa42497bca461fde794cbd5fa692675d9225ef8a902ec13258cd36d4d064d2ac1472aab355b5637bdd10220f1db63e146d143419a08eb29fb009e500ac7f5df3efa9b7a96d6a9b1ea1513e2bc42e5015cc61817e958555ca380979dd4f3e4a0eac0495de71b49ba70e5a3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf771d2f865f465af29bfcf83d2c74af6b272143db92d8c197a3eb0a6afb36415ec01dc5c8353dc13143d3c7ef9e89109f6c507a04376c30f8004e4b8c414270b	1633593289000000	1634198089000000	1697270089000000	1791878089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x115ba456098910b86513c78ee5fd4ed3ee9f794638d2562bd9bc667c6516c796a66ccb74449ca014228464320cebbbff463fb17efaed3006874ba801f5c5b07f	\\x00800003bd5de85abefd47bc7a91741a3c284fb7473dd150f6d961d131a0ef3a7a78e2710414cd56f9f5b9dea4ae4a469371a874c0c0692abd20f1f403cfa43565e870a3ea2de87cfc669052bcf440a074180c7661681f0a9ef6feb888e48c1b39a3148fd72b1be913e0c781228e01fd5decb13a0f6909a5f1ddb8ccba0abce599a8618b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8bbe74cf551f6190d76f4b50395720496376f33d2c585f59e5c152974cf5d902f378fb17c07607758ba3f20bc6a6a63c0ebcb3b6e6b30006d54da9a17e57d502	1632384289000000	1632989089000000	1696061089000000	1790669089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x14cbdc313556b284b6ecfef26a908f23dc8af66b716643a29d66acd7f74ac83351d9b8d02e705b0946c149f4ce315504f5329f5b71b9de67639468b48a1fe1c7	\\x00800003e65da86b26f7e761a782fef240ab8bbea5dd966cbca6a89741bf796cbb651ccb976737c26a89990ad774fc18884dcbee718a837a42e40acf6c372986254af9c421acdbe4568eaa7cfe479f9006f12cdf9b9d3273389d894dc7b578f8c78814de66bbb48237bac5533c831563f855407f7a246e7ba7a321d1a13e0835138f2eb5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x85157080aa822289c22e25c52952984c0be1e5ae4d5b585c1d442b5f3a5214e89721616119d180aa65a1a9ad174b339fba3cd6be0ea1602d3925b413c930370d	1628757289000000	1629362089000000	1692434089000000	1787042089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x154f88772b8c5f4bca74efa22f1c6718fd26583e61e4512627f3e278da8eafaad720a49464c596673c014cf5625195598b6221eec5891cefa43a5e5f1950fede	\\x00800003bff469725fccce2f95da5fc2e62d79006c1bb2e6fa9002324d5822487ee14212ec83093756d35a748406afa9bcd1f28ef341103706c8e1915a0cddca675df5f38e901d44ab217db256dc9479426fa7afafe07520b8f5b4004a7e615ea5b359313c90c980b414fc8b97508998087aed9455f43ac5f80b747b6611385f90fb1b4b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x975bdd5d2f0821895a2163046a61731e64152975b4b3c9cd65bcabe7713a2c53cc1e7df0b6232320e4297835bc72a551aa5c2d28f6b79a812c106162d08c9807	1631779789000000	1632384589000000	1695456589000000	1790064589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1597542dd7c682ab296e5b29cdf47792ddfa2ce225182f4d036f2405a94a05953f5d6897da0e40d264a979935e0e5fa787efc629199237278356fdf520bed423	\\x00800003c32043f3b771d33013f0dd7dc4b8662ad77c2f212553dbf30649b2c676e024aa46bcc64c5c812f0c58ed51bc3adfb799d921504b749d8998c3937cee400cc0a2235bc3ccfcf760aac99991a11380027f6f9d6364abe502b7840c78d95c1400643b6594d580ea12762613743bca4680fe84c2f6d3d10e2e3e695680c4d3940e6d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x25d8e729395e131b96e4efcc4795b4f4733c6b8daff6a29f65cfd988d9c7de8a8e51da3d22ab177bcceb87d8b159ed512f7788f81ddd66593e89da3ad177480e	1639033789000000	1639638589000000	1702710589000000	1797318589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x16877fe489ec30cd9d9969ae4967d3ec277f5a1c1b6f8c5e058f5f614016197dd78d8f5fd65b98059b91e0aa459c54da0a3f6959dd870540c4008ae25f0c162f	\\x00800003bbc92640a67650b667e603e6a520e2f020f67d13ab86ef538856fc1d74031ad849d7df8d43f4818650f5c9c9e2ab3f75133b65af8e603440ade5aa45758e2aa9cd4477565a176af28eae505d8485a3cd40347a1a33e003246d2528c3a5ef0a07b43f25270a26a7b235e21fd2e5ec909e58221f583e0677712ac7ca8f9e27b863010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x3e039a677e2afee4e926c412af4f05b7e508576340bcf0c0710f40f69b4d3053395e6dcaa83411b1853f603efa2e8097e1a4eba736ff95747575516d5c92b600	1631779789000000	1632384589000000	1695456589000000	1790064589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16778a7e7e0385fe9aa87e6045211908eb5528dd81ad487d55702ba7191b04874a918c1dd545cfa1925419367be00886e15f3542f93a45c64335cfdbbcf35439	\\x00800003d60505463d7b68cfa0ab763a5108d03018a02fa0241afb7a75914c279e99ea6d1c2de2a36caf43657ac9f9deb63edf886c7dd7a6bb13eb3e661a4f5f6ced927e9562f8f1206d21f96c3359f19f55c0e7464ebb469ce3527320f648c33480d7f73ab1e4864098bd1b19e5397fee41d27496424a5e38e55850248c5700d2bde8df010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe6f60454a46a224db31917ec6d99517b23c50a9a617bf580e16423357fa967bc5d81ed47883db05350ab71a86cfea8b3ced4cf76c4481857db00fdc6b0486707	1637824789000000	1638429589000000	1701501589000000	1796109589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x162f9b3a08c27c7b7f4e4e5cd70a082e1798e9e2bfa82802c02de9aa854e03b54d51fdedc1e3250d32eaeea1b560b52565f2808ea659c9d082906215d85d1ee1	\\x00800003ca6c57a8ed921aad6f7539e3313b8595e01b1bb10e3a228d0b1dcad0c45bac0ef1a4cd1f051022760fcce07c703456b38847de5be4c3cbd6ba4f5dc04e8c28d660a8f072366bb29dc5b871c4df3a151280ebbe6a7be01d526587d919b14a8d8c2d816e3bd3e08585cc05c51cfa4f1ae870de406a8a23f6e19a0b031613905e9b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa86f1300bc1d36b7ddc9e96ab7c5aa340bbd51920bcc16fed6567e61a263b1a2239f2ade9804be0653e79f138f968539a16089c96ccbedc58efc5ee57369e207	1612435789000000	1613040589000000	1676112589000000	1770720589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f1f9a24b881f0c56c866251f96d0502fc052bcdc95dfd89feb3068299dd92123578e06ceb2e0ef0909a145bf8bb4ebbed4e2e6feedf7b73b15362cf3bfae462	\\x00800003cd6c74af49084a6209aaa9af591dde42971a256fe4f91b2049e8b2d9e4011bac3eba2106def94d6419557427cccdd1342880c96a2afd9e95b86e1bdf7538253dbcb3fb676eab1a8d4ee86599cbe225d6cfad5a5c5caae386c710bc2e0aca575de67da471ccd6b9f28f9b357dc079edf7472d1b7a485db65134d8cb2e125e32d3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa996344957d34f90f0de80f0fb70ace954cd9be1278ace4113cd4248c0a69160816e7f59590ca09e3ad32ac5ce1e74fc5fb95a33e2a4f2554736ee84ec29b00a	1619689789000000	1620294589000000	1683366589000000	1777974589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1f4fce1b97633d6ed0b7d739f62283ee49eab1acfa1b7f411bcd7d91573a34bc18cf2a2179cb063df30a088fa8700475b9e5ebf593e9e43a89ad1be2272812a4	\\x00800003be413b807e3ce163e7edf7746f023294f3a24b43bcce05eb7a6d9f7ae6b51d8603220a43cf4592517ee9ca8e0cacc1f01267e49da5e35ee3ce4a20ffc6cbccb54869894f6b897f2c8c94e0627b0f3fc84130d8eccc7c00622b92277e518ff4a6b47c1053d353ef3e2803d1aa3c8123899342f0e55c29e871854a7d5ed355c329010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5dd0985d728484b595db9ca931b037857d47b445af2424bd72dd37fcd58d41e4e52091fe89311de441bee4abbcc03a8a340b008438c13b4e77ecdf4ca03edc05	1619689789000000	1620294589000000	1683366589000000	1777974589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x00800003dca835812550bb8e386e42f2cc483fea23e2627572ae3c68e7c57688663761f5840b12091163252e84ed85a4f82eded3268a0793ab314873e6abe298d83e93e848d270040a3eeaf2850881b2536dc9167f7561ca9532a4aaf16f96545388a20ebefe9f92efd25686d17945e14d785b79f01cb05f38203f2d61c45e0c15e4c221010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8773e73265e957b86a4befd135cdaa6277ba5a60a010daa4f8327b9010454717eae3f542fc5f229f9ccf2fcc4b5a5a47352f0bd32dc5e810f72a2406965be702	1608204289000000	1608809089000000	1671881089000000	1766489089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2553c62822d0e05f553b20b737876b355c1141fbe39fc9c37ec8ce93556b53590f69addd918f374a131fe701ea2b9cfd4d01981de207576afa8867c6bdc56577	\\x00800003be50b29fd6e22eb9779e5687b6cb66bfb98bffaaf61ea4ded72d782a0cfecdd14d9ef38efe0e7ea3cd81ffd7afff35d5b129e3c00921333112d0797dba958214ba7db2eac03f5460cbc3415994dbbc09e5efd79989fae1711d702e1aa69e0ad23834daf18667545f62614b1fc2bdb17564649ae915f1a28ea736d6654d5d1509010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6884458811d7e24d330e226bf353c053cfae3645f43a51738d0afe98c74b228246b152543eb4264df92c2d97cf1429ab5e5b2085a4c1b1bf85aaa68531739f06	1616062789000000	1616667589000000	1679739589000000	1774347589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2ba78dd430d4900b6cecf4685393d5f8b74904e275f27017ca6d618c01b3ee99be9b6c19d19e52fff0fd3310dfb0ba208b93fcd491df1c31782129180ba72a86	\\x00800003d2c88c3ee1d1302b3e74aee83956dd7dda88e8f121ed76a69c0b36581a84f7a99091abeb08b1c446f121176138d3371fc7708cb7e72e4edf4f75c39807298c1ad31b6dc72b8c748071d413871b8ecf1b601262ce8ea7f20363bbb147ba131fe40046a0edc6e445e6791cb30eca5c7216a017b75c1f427f6ff68f65817ac39a79010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe56e6de40deb155b9d63e0924f6ac6c1c6a3d615afea1b17d1e05c34814e3e9913422c7bb77a4dd26f16d554d54d337fb570f9e22ac19b9a908f93f7375ef404	1626339289000000	1626944089000000	1690016089000000	1784624089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2dbfb519ba16030c5642d9970734e89cdcce360be6cf99066ff5fd2955148edaad6ef72ec6fa1dd5ac8d7ce50f2e86bc9f8c3eb138786dafbaa6f08130925088	\\x00800003bd76773485d55435aee413011de83a927b7e3958e890fda0bd63bcd0e8513dea353b1d0cc093715937b5b318bc090cef4940a1e56e392133bf1629600717b40455ad5c74b3f4415e13a5481f67932e46fd5fdc88c1fbf311394e0009fbeea76c732bde39ea730993b3cf24e14a94569ddac7f493beb75af8ab3062bb8e65978f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5d330146e3ca0a007daf9b3badc5f05297a77d26b0660c60e8b96e41ccc71789349a052bbd0eac8a214128e464c6b4f015266d02457685256c0e66175d4a5a07	1617876289000000	1618481089000000	1681553089000000	1776161089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2da765f13911b652802e9b2e14ec68492b1c4fecf6429d3ed503383e9feff493c12a10f8934ec6363c380d607eaaf6082c66df7f091cc751ee1570dc8a84a759	\\x00800003a423138ddf6a7c4dc9a08414c12eb5f28d2986d68c3305ac09ce307d4e8b6886e1cc7b5786f89a4be3d80c14ef1d43662bf1669ec3e7b1db8c55113a0af3f7ed4db62d2cfc986f1280c0b340b0affe366e7d6013423033be01f94454939fc115c06149729810a22c8b79439a596d64ce5565b7db0fd13a1c6a8ca3e5040edead010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0a67aa23a70937f76dd0fccaaece891d96eb6f692f92cce697cbea8fd36b8c8b3ff684b087b23098a5cfc44aa1709c45890f0beea045b001aa182c8392591a0a	1623921289000000	1624526089000000	1687598089000000	1782206089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f73dc140344c7f9c6a9447b54e0eac56a002e3bdc63fc082b692af389011b2ec8f42923d67e88c65776cb31e93c2582bbc9252f9ebf0fcf8a0001319365c0ad	\\x00800003c8b3cb86a1f8251cb0928a8ac28f1a25eb12eb730c09465d79f586c85eb745cdd52dc4f7a1f2b9279b4ff81eee8ebf89afa184470e2b1adfd29bbbac8e8442f58cb2a0460da5818aff3fff985260ef316eadf705226b553674a5c19fadc79dbc8389fb803a15b96e69d3b8c24ca75498ec3cc7e7b8fb32982b1a49a70cf004ed010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd3d86cdbf46dfa69ef3ce0420ae1f699dfde7fc8ef43d6b196bcd875d82d61bbc19cdcdbe7851705551f03b3ee98aaa59925e49e02a52aa51e6ae0bb01beca08	1636615789000000	1637220589000000	1700292589000000	1794900589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2f8f9066181da08b4b336f471177f4afbfcbfdb880595d21293533d61da7de2f6ae163feb8bf8ce8309f9ff59224046da774a9db5a68531261c61ac5d8dd02e9	\\x00800003beffd5a8d3b2c85e9b9762cec3af694d966c9a88cb0b55af9aeae2c9db98adfd50d38bfd9aca1f5523a7ad8c1d978cfd71024f3822e3efae487499b9efa0c2b7ebafcbda22e712938f90f170575f56ce791e567074344acfec2a23ddcb3717e4fb742866ebe9f92c173b2cd757564c99c4ebbddecc26a30227eca2a0a3a5c2d5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x14a0691d91940913e29a118cbdc45977a780b9622053f6afda608fb086276e6b7375efa8bd0d7dc73b57b90689e513a294b2c72af601354b87d962d9b3a70e0a	1636615789000000	1637220589000000	1700292589000000	1794900589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x314fde3a7f4f1fe0af9421c20de1d8956338febe68737e6a6f8b745db6aaccf470883d4841492e92779c3053c05cf6ba38db0fbb874c50c07040ca8c3803be69	\\x00800003c6bc0a581ad922483cb4c77dd703c1d3a128b33e5f6e52eb314db88cc79b9cb33d2ef4b02283e128acc026fa2e1bb7ccbba6133765aae974bc153e8ec779e2e686dd275ee790de577edfbc548543bbe7eb0fecd7b75c99661452cf44f2ce8a7b4c1ca63fe94a1bb333ac0c0e082839810f42f625b174513f0523ee1132d0cbdd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x47a323bb9eb539e3dc5537895092b2bbcee473c9835ee1652c3430c0a71a4a4ac73cbede5ff5de3600ba72bfba29f385f441d44117d49df578568004d0b41d04	1629966289000000	1630571089000000	1693643089000000	1788251089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x31df9ec13c6f316f26d908e647579bea2413439db1d04c8983a6574ba79122ea4f03e9ac46d0d107e905bf73ca4bcd46d2cb1923c704bbc87eb91559e938e612	\\x00800003c7264e567551f311c14ced2d60cf44c838a29559ff2acc7188d8b09f5dfb7e3f1db6ac2770e6a9ce884e708138f1d3bfa7e051243d6b2d39d4aac8016f82c74ec445ee1ce4daa3df2f72f95a83cf878fb6130b695bd01ef08270495945c5857759829e5472540fa3db7ddd7d6ffb465353c5cf7072399c27df31c66da77c04f7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5e3df46b60273c1ae2e0ae8cc7e1113ca743c1a5a9df6e2fb4bc226c9b1935b5e1781a5aa2b6384e3ca3a3bcfbdd3ebc0cd068cf13380609df42895fb692f70e	1626943789000000	1627548589000000	1690620589000000	1785228589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x31573b4f2fa91fa88d63c8820348f6bc8a43d5fdc1668e0506f451b94c0fd6bd1ac01a917b0ea033d1d01fdef6fd25224b736202e039fbf9689848869bf17b9e	\\x00800003dd4bb31d9bdf3747b83fd1a40ce4120951db2a3d4a3536f1fb2822de35a70aac68b55c1681096624c67c5525e8fb791e729acce85a46209d284b81939c1d394109f139d079436ebf0ee657c867821e803fc41aa79ca8832ea229be1eb516963c91c8cd2de83b3660d5ed8881ad91ca76609333b294336e246d29c9a3be06b66f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5c2bbe7fed5962ba32efca7cdbfe8c3fe5220699cbc1b3529e513351f8466cf10e4ad39ddfd87e10fc6077a9df72a7857151958f16d9cb4bb8fbbd65b390ef0a	1632988789000000	1633593589000000	1696665589000000	1791273589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x337751eada1424987f9dd88cce7e25e8aa5643788840aaa5c786396aeb44adf64d1052bfdcbfaf0484f806dadb2712aac00b60f23aed74a7fd84934e59951b81	\\x00800003b17be974bae00c5647fb1bc6bebde09f3108befde0f7c04a86f124560135110947c192d0e39306aa31b5c1066a6c4fafa7d649e5135dc066197735dcde3f60244ee492bd68f990c629761393f73dbcdb2ba8cec342842075b17b401c07c65af9512dd5e479aba90cd9a66ace40dc699b33a9cdc11efc36c23373379302eb77b7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x9ef18a4c8faa19e36d912d219ceb673ccffac94162d0e8d09cfb5f32eb1bbc446220159d19eaca51378a49a2900040bc7feb3adba477a3c34854754a722a6c02	1639033789000000	1639638589000000	1702710589000000	1797318589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x335709989d3769130dd906266b23d4977c01d1714a18337e29ddd38a9526ec00e2eae8e4b553ea0b9edc866bb199b4d1d725589eabfd01deeef945af5be0c7be	\\x00800003a7269ea78b02cb077e45feee03b226781a08ed4b98e622a0c8ab9e1e2a6a6200de07b0ccf30c8819702f925cff2f76587bb8055ab288237248191a7290bf286b0d824c696e8786151ba78040b5f4bf458b669a6b6b9ec1aef7ebf4e22a9e27692ff786038e15ccbdb2b792c19088cfc248ff1f2a587e8a42da274f163404a73f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x654da04a555a504eeb98fabd2459b6e6cb960deb2482771b17d441f0ebcab9177ce708c6322c1796465ac125751d008cc12e81a899813262521f98a996d70509	1636011289000000	1636616089000000	1699688089000000	1794296089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34b3906daf9c05b2be6b43aab9d04b7050eec8b925de40541ac91f5333f3190f956265aae4bf639044caa1d6859b485d3437d3f73013606d69e92384437d6604	\\x00800003be170364bee6475bf988e200b7225a25b29400b61724ff2aab3d8cc0d7181e99832e8ab0689e18579083604b69f6532d903650628d575bc3b1896cf2631d8426349a9607e109aae8c4ffc3d2967cb89fbf33b39062136129545c9ee51af8926902fbb19f84f37d2a36fdc726f9c86da57ed71238820ddbcef997d63cf73d220b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xed6d8049d7c6b380dc81dc3a0da5b5f1ff01e3a2ccbaf1357998f187ce65fc194f08adc3a5f16920c6e0b877711a630e11eec77e24231a392a279ecb6e16a904	1639638289000000	1640243089000000	1703315089000000	1797923089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a8be77efee027ed6b5715ee6818562d9c64b7c3858fe80b60f55d88ef239025915bc7dd461a3617366dcd0c2e9ea43903286512f3e838d8f70b0c741ef34056	\\x00800003cb9ffb9129c95f26b762ab4cd27d2ec63fd5b73272767271d95b34be22ea676c1bc5bc1fd706a849ece8c8e2cc70fa51ade7dbfae3a036be3d55c601ea7a917b842b24b5d1cf49e8dfe3a937e0e058f02f4512eaf62c54ba179950f6e23d55e9085d8a1177e6924b5167c7edd2c3dd895b16189f4b16ea5cda0cadc74e03b791010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1a6cc7734dfe501731399dd37135cc1e8fb7d4a28ca5cf9662b52a611ca9fb524ea2dd059cbb39b15b9d6c3c9d3bb23015e7f6eb93f0143a3277203399d5e10c	1617271789000000	1617876589000000	1680948589000000	1775556589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x42636cfd91fbd79dce73a9314b3224bb0a090993b23a05a1f0fa14ea5674de046720962e9886e68c84391f7b6b900f1a5348fd5d9389fd2bee6ab42fa5634506	\\x00800003d027ee6f8b68a97bf2f9ab350d1cf3bc0773db484a5fbe9918b8e19def9fef73c7cf789f17a981af9c29ecd4aff824a111c59f729732916a99147211378fdf9d85f260a9e0a3662c4d48e421ca5ec976c171436895e93aee33e138ae3bc6bd63833d9763c7afc27306c1bf11456520b7564630d95482ec591068aca5b6062c37010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe9a87b54c3d68eb3f18b52facec81d89497dab1d63c20405cf4376c8fd8d107da35144179bbd19a1286a194795d92fbdcabb59c3495226a71cabb0bbdbb31302	1632988789000000	1633593589000000	1696665589000000	1791273589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x43afe6b7f25a6d4b1884acee07dd2febeff6b9dc858a80af10df66d54a8cb9459f88b4f0252f3129e1820204a5a2344d2e9c82a7011a373564dff387613fd9fb	\\x00800003f1ab8b47db89ec814d5f1be9b84b4a7a98aa3601cd0f81b46a832ea26dfec49fa7a2e7109dfe949cf270ede22c8a0581b5eec9792413adfe6edeaad61360263401c68dbf3ff651c8a258d67dcf561b6fb96f06aaffa70520b66305538d01452e11db86b9bb31cd5be87055baa82dba7a79102c249c77f6a8264f8d5833c3cc1b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf9d540b49d5a5c004b4b2b5515099e1aa290b3047134018095948c6806acab960f786f04656eda895ccc05e16e12b039d5a117439a016ae3350fa643dd60f300	1634802289000000	1635407089000000	1698479089000000	1793087089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a8fd290dc9d67fb5d440f3c21e1a3476d0aee33c07cd1fdf567658dcf7e90de1d9081eb26efdaaf4d72825a1f80dede0dbce19f405bd85350d454623b4c29c4	\\x00800003bb836e01a7d1c42f6f13c3ab3d818f8a14425e812847ca7787b7e944e8e5fd4961c8e3b809d49d6fe23424f80fbdbe0b18f8bcba5b87fab8eb0f918d4c3edf43607876b36c37220f877b2655db567882b1a350bea4024de94c0e442ab1274ee7f1e42c0ad7ff5b954832a7c106e193379526169576e8b5985884f745f1e534d5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xeacc5d60064dd1f658e9163bcf44e55a190dd6fa1c7eac0c450902d4f906711f449cf3a338347dcf349005776426c0b7c0f14082bf77018a8120acd6d1e51703	1624525789000000	1625130589000000	1688202589000000	1782810589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4f1f08b18d4b9f7656ef7b5f21f85ce3c41985dde4242bbd586bd561ba65bd559581c13afd88706feb86133495a7e4c8e28cbf06c5f5bc735d277d39efacc35b	\\x00800003baa3b42646f37a23f941352f84491e44f0dc6fa301efd467707b9bc4bc89562a2898ca42fe4513b381f18df13cc60ab49a99314721ec2cae0bee5eb249867071a541db252a00aa54e6e4e7066deddbbb67c2d0018b82ac8af5ef6135752979569c736614deb803072689ea34d07004e19c1b1d6c1a6e47aae1f95c49bcb1ae25010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdb35a36bd7c48bece3f031115d36ee818767f536db343ffd4b60804216295062435408b817fc38efa2dcd7c03caa0fff9afc5ffbbceb5a3acf3efa7afb5b580d	1617876289000000	1618481089000000	1681553089000000	1776161089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53572c461b85ef83d826e4694791d81951765a39a84b1dcad729c52b71482d24b219ebc91419871791c459da5b786c980178b91b57a607e2baf84424ef5d2a67	\\x00800003b7f4b5875ebf965e87d3a1d04693eabaca640285122afd646b0cae12e10f012d535da0cd2dc27ed87b61c03c9e4f546ac523cbdd2c1769db5701e3c869676c5029ac43f2f8ca5ec24c037dba4f135e2f3f5cf89d1fb61382039c952d819e29e334c55e34dc497eef9943e54bd6f073499d87a26cf0c8e13f4d8aaff15ea6183f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf4474da262d3019aab4546c9a5e2353526341f360c1051890f842b6bb2b4ae9bcbbfd613909bbf94518a9af40dbe27d7f2f522444564e3226966ad8221537209	1612435789000000	1613040589000000	1676112589000000	1770720589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x56ffa6c75b172b652ead6af0a129515924e1eb7af96828827dd2ea796589ce5ad2288199ad7f060f2f5c671c2dcb1f656ef816c9a064b2da901cbea2f211a64c	\\x00800003e9455df701929056ea8662dc1b9fe6d81f15958072c79cdca92d97fd0c7ff86653ebb129ca6f178d012862c151d024d44b638e9e618ef646bd5b7ab615ed588e4d45d860d40a4c72dec958737986e1771d0d83ec95070301db59638269b576107cf9b502374b09504cda66537f286b274e0529a433143a5b2ce9bbb20881e4ab010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc155872faf8b08e9531955611c24cf7da4c3312bf9dc4ae1a1388f3b050861101f8afe36188f925d2d0d1f8dfe202709e409bc730e31ae32add7846172fb2206	1626943789000000	1627548589000000	1690620589000000	1785228589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x56dbe84748dea08f1e2d764d15e548c451642a29e5aa674d38458ae1f94e8ae9e6b0b46f02f0e986aed31e8c31f4cef269abd3bbe6ed2724289e2f771aa6621c	\\x00800003e65c4e040460e004f9a4f7a2939fce657a813bd7f3c4c5fa204ddb73c0a0d07e8c7203e4c29bd1df5dfaaa5b2eb501c406e5b6881bf75f2d460bc17b9f4f270a090f801a6642c0e22c053549195fe085329c094266b2dd472336ce32b4f126d070294ebc604e831c0b45ef29c2019a55b8303a985f58bb0986359a0462826e2b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc294720c6d6aa28d3061798249e3ddf4a5f4c496f33c98faf61835b86c25f357703f4bf647e9d56c296982461b78579e1b5cfa33685c41ce51b09510eeade605	1637824789000000	1638429589000000	1701501589000000	1796109589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d2785429038f50575291f1541580b4bc84ef54955a44c60d2d275af6bbe271d5033428684e7c6e052995f23fca6d44ee180c7e4d1269fc35c842fb1a47f1fd7	\\x00800003aaccf9c4022316643efc2a648c9547f803618c78eff8866b4c741140d6b0e50f9bc23ba22cac69a2c11aa8a229399775fd99c7427eb8d7c6b0effe6cd9cefd4c31b53baf85173c0d9dca85fe2d241ece50a458b9d8c3309691383d7fee56ec6e41090bd484b5357b9b3e02f6e76e1249bc39226735f0a941f7780aec1befd6cb010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x515d03db02668a9ab867315960b23fc62ded8f87e2f12c4227f3f69b9e3b339d9d5cb13c3f986d16fccb816f2af97d46391aa34e4732bbf16e6729063fc07f09	1631175289000000	1631780089000000	1694852089000000	1789460089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d8f1022fd9e4657fe7d941c77fad3504a288550a5fe8646894ae8b55e36226610bc534c322bd4c8c1863b0fc3f31fdbcfffcc191a2112ae6ff5ec3bf0ddc8c0	\\x008000039ec05c4957966f0a07d5c6d28c2e0f6a9aede225888cf6b2accce1ce525dd9aa691a35041495ced4b6e14e2ca431f805a59db2268b7164f5bc99601ba9bad25e9b980e494acda631d3f4c3bb7cdb8facdbcd0e461140c87f49c55beb9ab29f82c6cf433af1789e1d7e7bccff7581bb704086db2e3c71552429dbd8b817fb7189010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0edffc45cd86f7b6511a30dfd23d783c8b68439693532d56232cefcb38f6dc81c8edfa8083bb9cfc5789401f0b114b29f1b1e0256c77f4f907abe4504f66af04	1619689789000000	1620294589000000	1683366589000000	1777974589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5fd3b40c1f9b12a7c06a1e3ad3afff9a2e0457622bb1a76ada68e03ad4f59ba4ab0f4ac23c97fd774d22f98d16ddebf343d9a5af80f175563a2437a72f6a897e	\\x00800003f117440fcd041e6c0ec714cb7973d9382a070657d60223efc8ab727b42c36648bbd6bd6d0da14865414c6abaeea127e921bb6ba06e043daf2888f2b37b28ae7f6ffcfd04f04b909841ead4d727bd9894d98433122b15565a13ffd448ed81cbf9f40049d88f9e4625f1a5edfed98144e927d87b5e472a192f3f4c111fefc6255f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0b7592217d6267ebf38193ea3a2b1ceab1283c66f933a5a29e9ccd5f11baf0c50f4423da0c99e918ea72f118a095abf33d0f5c37b5f923dbe7db93d785c0f90c	1625130289000000	1625735089000000	1688807089000000	1783415089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x617766eb95ee04b440d4550a61c41fdf1b64f8a4ba007fa635f2b55887514dce569f0d152aa4db4ab48998d028099d5656509c30e022ef7d69b8ca276c73ede7	\\x00800003ce37cd5ff8784fe33ce7863a572e5d63f68430ecfc248ffbc847ef9d79df3daa962e239e407f0073ebd698d0c01e8c55267982ff708e5fa26b6707131ba2e3e22042e407dca5184ece0804e6541c818c04acd9c905724f468019079570452edd1f1fc5ef142af27e06342e4d251c5793c88f1ad0e979011eeb08e94a2ad55691010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf566181d5dceca8153e6f029ca3908cb70cd648c8a3d8d6fc1b806bb1cf7541dd891f7199cf8fb4dc261bc2bd282ee62ab63b10ef73031900e92c8373a3ff701	1628757289000000	1629362089000000	1692434089000000	1787042089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x647b8efb9748c2cfcc094bc09c5d5aaca2d05311e77d8b94c2cf492d154ab05ca6d70f09732c6d91d9b020e3c5c228e0e16728145fdc8372a62562633782bb03	\\x00800003b7da1dc20926cdc4cbd0bc792e5c29cdcfaf5d89d128db6075758396f7c682f660c3625d60aed7199833793b5331de0aabc7fe8e1fdd60649ba31020c90dd019e816e9d72482975deccdb3ea66fa5d6b601ffc5dc4c826ce72fbe7e49885201612889528996591960c1a7562a8485484b8d09c77b954e8f3e3a6170771044a27010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7192865cdcd550e6201af468e62898dec5acf1bcdc7cb86a68216480bd7c266132ea2bb3cebf0f28bf15ab275c414b39f55e0f47c03dcf7d645959fcd561ba02	1617876289000000	1618481089000000	1681553089000000	1776161089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x663f6f0ffcab8bc1953c8a62de5ce52b13f7df878fadf498d6b8cdda3c97ec6e1e25e85220ecdce1ef199da851e84e663158cc092de52bccfa541e66382c4ca8	\\x00800003d16d00490c5c284f774220d47088ff090383be82ab47867d66b4d1956c7340a5e49272feaaeeae35db7df1148ef646deb3194f519257ccfd106b202efdebe101af840cb3d67da50b8f53eba6dc12c625de8ef1c996762cfb38c17546e0a9bb878d58eecd838decbfc88191ebae591e33c0e35ec67fe5ee237b7fe9179a7f834f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x506da891e87f5f10d3aa3e7497254f82ccb5ab7d7e98309ff476f60d34e460e14737046cefdf0feac4eb28df5c01b80df836e107a88ef711fd56455a969c5e06	1634802289000000	1635407089000000	1698479089000000	1793087089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67835523e41a7f22364755ba0aeb09bec50669d9b72760c203dae9032766ab5958f2df62238e8647ef2d9e3334d83cf5cd260fabf44df3183d7df01f871e8ffa	\\x008000039be5bca4a8a1dec6ee4100bf4b03ea602e1b2de483450f30ef5246da1bec4570ec1805de317f7f059b878f8f57a37ae7c9d0d6e8dbf43eb5f63a1199663d5b574587098ea9ed68e170ce305f1ecf7592caa0910ef4d235dfd587dbcfbc6b73ea72acfce8eee7f3d772d04d1d22f697aade0abe0e902242d537fc0e98c0be2d8d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x63970bea152c6a38ab54d13d0eabafa0b0fb661da44d548a744d1ad5221671758c82196ba783dbee25dd58eb0dd39c8c345ace921b204507a11fb0aff6de1601	1625734789000000	1626339589000000	1689411589000000	1784019589000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x757fe56fc5a000e05e1bab5ab3cbbafc0a7f9f5d7eddee55498b3721848e9ba0178e031facf42d4fa1c5728ebae6d38d9df05c643888982d827e1135c59300db	\\x008000039ce239f0c0ca457cf0ae8d02ff0cc939ef523a860285222e7fb36831a8187a8c717edb9b9b2b88cb10274e568b923b741e61f9c6ea1043db54e81e6fdfeb57c5e3fb53b7ad4d10018af9aa1a88fab24f3159d5ef310ec18775cb6e65a8fcd5b2ec2ffe65feb08dfdba72e6b545d87fb7c0fd3db9014ef5d559e1a488ac7fa765010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x02ace8a7012b933c74117fcaf9838e7a2802b2702507cac0416c016562bf657c4e60dda38a73128b2195461e4236f03021972c9e63a8ae9b290c2abb4eb3e70c	1639638289000000	1640243089000000	1703315089000000	1797923089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78cb5efab5d22453175c2ce0c3682c1754df57168dadf4ad522b401e9d551b308689c139c21b75a2ba37040f9bfede97bc9ea7b001690d366c305f827e7b60f5	\\x00800003cf9dd35b7b9b3e04f1293f8825f93eac1891b135dd4556ccf811457ccaad5458eb296193a40ba1a4201e28c32c52e79d93baf3cf2908d0a508cac2fa9fc18fa563a5de20f7698d0aae92c916d8ddf8018343c2bf54a5cc453327aba769e2d6a79163424be33869b8b5e5ee26a387c23ab74f9db1fb060a3d6d95044b7d0b8c3f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xa8adfc2f7530bdfe57d0c513f3b5424e90910c32b694601ab41f9c303c01fd4d4060833939e51ba63139990323a7921ecb4184ef7e948de9b44521c5201e2b01	1611831289000000	1612436089000000	1675508089000000	1770116089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7a13dd59cb0db7f8badf1031ac56d037328e08b2fa3fe2c84a576b2da724655ebf83dda9426123320e2e02ecf349399531f5822dbb6e910fff332001ddcaee7a	\\x00800003ce696d085fb2ab5a1690cffe28cd103a5c2184bdaaa461b60a437610aeb3a0b2dde6ed2d39dcf40ee690e724ecac275a668c7356a476fbc6484a8508059455188554bfe511db67b4119bf4afb9b20407d8f980dd971b560fb0fee976fc8d03e7710349e2939de4cc0184fb41bfee02184667ce538667abc9f73226c3ab2b48c7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc810e3131d2df1a5589d1465b5b28b3069a9da98c61a1e93f001c2438d42355145276f1731bcb07daa06b864990908f87c0ec03fd8badece816155cbbde59708	1609413289000000	1610018089000000	1673090089000000	1767698089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bcba76a76d7962b0a5600992b955783c924d16f469a5589af8889db213b51eecd0c693b0d76de7de30bbe2c09135e16e8ba603e7fa9eb02002608eda8c59e15	\\x00800003ad4bac05794d46e8f6d50e17a523c7e8072a0a05fd4a208571ce56b5e0d68c56f1f3e3e740e74d97a36da0377bbb4f21ee7b1b40656dffc348f16651e94510dc4ee8149188dfee797268171fbe4653cc4db6b5c7dc704606016219e566b1fe7ce3fdcd6c2e91925192e42422a98042e9d8f1e1f5dc82f3fc9eef9026970b1907010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdcd6f3f8cbd3b70a9560d28708885e712b81a3e88d720396745f1d7614d6612041607a0d29e373d9c4be01e4443a418ddae64cf9988297420c62874ac903df07	1620898789000000	1621503589000000	1684575589000000	1779183589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d83b679eabb205ffabc2eef5c267d634ab50c01a51eb75e2192d3bbc1aaa9b0b36a7d79fb52e637fad9cec4e292ccdc3e6d3d1c1d5ba50f2456c9b326152d0f	\\x00800003c060a0db6dc18894a55af3bded2be9eeb7f1af2c9fec2a61bc78f7a3cc59ecbd1755e9222192a106aa95ae855ede638e5e3ca92e2f8a516010934faaf52c59059d417d52536bf127a1e7d2efad1b0393715b4bd06c8ba52028fa3c728461fb7696a98a0b6d5801874555198cef46e2eaf9f59b8bfe227db124891fbbb41a926b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x57569d5a959bc23bccbb4dd1a15a940231379a944ab2b320f05e38ebe164d806f94ad2141a8aad03d8edabc185c751fb69d48fb40ea2f0c8e1db86f286b61608	1634802289000000	1635407089000000	1698479089000000	1793087089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x80df7d0565fda7d5cacef25286f5674f50ea777b81e5a5477875e8ed1dbc974c1cdce226456824d8cef886140d29602f37aa787e0c0ba932d57566159546ca01	\\x00800003be579b7f215cf82d07faccb419a4b30ce9351326cb037b33ee0c2da129d49133dfe823d45fff65c6050800ca89d2d953ac56306e73dec99c88bc7ce8dd262e8f6738d406f73806d744d50ddc9100ec5f59986cbb9cc9fbf0f18e8e0321a148829a0f57b04d58921f59f3df83be3057460954cc77a3e7802b03de5c2297f9b77d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd1329de4fa9b47b3ce0dfeb7a0355a40d88302c3275f9284816ae8e9a0d860cd47093b51e9c49c5191d9d899d499e1bdc51e9589e277adde265ebf7db7eafd0d	1617271789000000	1617876589000000	1680948589000000	1775556589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x80a38087bfa533d47905c8f3f3cc421adaf473713ab041cb04b0cd9395db826d1772380ab79a00a5f50da82ff15b3d72041156e45f2e528cded563d503a425ed	\\x00800003a41b0762d0fc9574f2297a099fcffe40ac3e38dd451c790a15e2918b1a31d7501be9fb152fa90361bc89f21586dc0870ff94848131ee2ed220dfdd4251145bfb38f3ded2264bf42fafe89e51366ba92a169e72158aead36ffb9a047c2fcf3e0cb63e1f9f976199cad4cdffda29ecdba47579b1832eb17985e8def3e1765f1ec7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x876d007f58e4e898d070a2148ba2fb33568c1016c5bc0eb43b1818db4f40ceddbc619f53b00f395ab36135b458f7732b7f465428c00db831504534c684193908	1632384289000000	1632989089000000	1696061089000000	1790669089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86374e8ab9ef317bda31093e5132e96cef6a63611bef2b69d51c381071ed0fd18121c9223f46949bdb789cc38811f8c500625083b363558e8e3df2ba7613087d	\\x00800003a90452664037e4847e4b8dc1b239527b522b06a022841c32e1b566bee9e02260310157b7174e71c476409242265c40a7808b829e3383742b308dc467123cf46cf28da7bbe6353875c42fa68790205a97dd184706fd80d4b36386197a196bc1aa51e5556420e174bdda592e1ceffa127a248d74ecbf12547130fedd0d7fa1647d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1826aeea8e48f154921d390ece03444d469fef002e4c76fab0398a77330da75e70370387941eb1467bd1752dfa0445fc9003bbdd9d2a091385a380244a97600c	1611831289000000	1612436089000000	1675508089000000	1770116089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x894fbaed79760402db88e3d271282f8826e5b12bdabe2929bcd45bee0c89f76d8a7f69fe4e836b6a6c75944450be5167f9dc4e32b62ac40cf0a29a53422e795b	\\x00800003e3e776fba5c8f94382b2f598442f58219c0bb43e53fbe78e1698a352ea27fbf5b9620e979a3be49b3b23b777c32df4635d26c29eb9c8018597a85583087176e9db026a897c364fe8d213ad03ba813505342df27d24e22d2bb039559b5001c6597c00b7eeff537e3d87c41106f38023421146b550817b2484f8ddf7533d56a993010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x85a86cc3d625ab290b1cdcf1b7fb58a7ca24ab59ed15117287602a36623c4dce1ddcd64481969eb96f905745501f8add9aefdb110e44b12a955bad2b82f43506	1634197789000000	1634802589000000	1697874589000000	1792482589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8d173c8a8900d67da6c0ae8f727fda45a557f39d81f5680a89f975ed1b944bba78bcaf2df17029d1294e70e7b5f2ac5c62127197eaa837412ee223c245a63bf1	\\x00800003b9e48f4b55d565fd5f0b68e396b24edb0501b2ed3e45cc27b883bb46d058846eaca10d025b2c6dc64e9311d104d57e72daa196b8a4f21f224159ab82fb6b462795bcb289010d29732199ab3e0a083f18b1380b9c79297489d20cf9426200b4cc1cdbb9a42ec454417ecfef88bca9e71cb86d31c8a0a55a3f8c8343ba36ce473b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x6008e5eb678c24b4e89c7a9bf233eb17c1d37f5002e931426ae460b84a2e2bba7536fa55169326a10611c5e7700a7c87db042fb513f820371e93140c8b489504	1610017789000000	1610622589000000	1673694589000000	1768302589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8f439e2d606622d7a983630c230c348c6f73403ad8194cd5e7f09d2839f9163442ca1ab91da0f571b44575bd0e9ed4f03a13e190f3fe36509b1b696dc8025354	\\x00800003ebb7be1dd85ca3147c76ff1f7c6abf1c08215cdcfc82203bd01fefaa012f1dc2964fdab74f44f8633491bacd28b9f94d49747e4f2a7f77b48465c81e8632af7b82ad0e4156a80ca83be490107420c37b30a01889412e4d9fa314c121a6b95d2385f591bdd078f4225dd39c998a91c6e5df61a95c3b1f5eca0641703e374a5323010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd5ce143bd874be06392a7c0bb0e306965422c6a2f75a150436ffc507b74db05e00eb35e195e30116f5b54d860fe8ec4b8f0cd663d497201369a4ffdfe197a609	1621503289000000	1622108089000000	1685180089000000	1779788089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f337d25d1742798559c9354454dd63de0d1a2a1bfb00a443bc858df8e574dc83352915cc013142890cccc1424db340782a9553de65b5ad921532ac00e8e09e7	\\x00800003bd1e9e6a219048f6a067596a8882afe8629ba2c56295d0014cee180e555f6a7a65338e315e082f78a9766a012ddbda7d3b1cf9d3fbe5e6036f5f4529bfd2afdf517ec75ae2a95b36cdee2d7aa2d5aaecdb6ed4dfe51ea34b9c22869887423008f71f0251b8a30c48e8aa1687674b98c9e9277852f0db19cff9aaec52d09ef155010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0787d0caebb20e131b52dabc1ee3030f3f093e226b80d1e9bb84e13ca21a6380ea1b3ef98070c68459e4f9a258f2838efe91658a45c94bb708b025aa6c72f906	1608204289000000	1608809089000000	1671881089000000	1766489089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f9f0e03102b6d13f7a7e593281884a9b36e7462d3e645b934ecef011f0a1559b635a4e3abd5a79ed59f1a919de585f4e74a33f72eec5e96c4d3d8ac0aee8234	\\x00800003a0765b9d0832233cc7824913647bd4b2608b61970ff5c7e2ae696124956f5d19d3e2a3eda9d0a8b157ae95116dd6e95134ddf4d6bf0c6701e1d30fa5d838a0edd77be7cf6cb0c2f8092fa4dc3d77494012b93ec40093ed8c31ab943f13e10cf2135b8e98a3608fd76c7755734b282d8175cb4181238f8d40e1fa28c6e03842c9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x1057e720b1d57f14d77e68813383ded769a6592ad67c397f2fe3565bece8a3ef6c2be3e1a05b93e027b2d1afb86475539877c41fa93400b17443119350efd20c	1637824789000000	1638429589000000	1701501589000000	1796109589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x953f1c9a32dca73e798987ac7c3d9083d7b6b90bf20eb70b7b260610f07f5f3ae9a945d1df365ecbd91b1c93101d7eb06d5724864ac8400d794de2d86f94d18f	\\x00800003f8f3b1ad0ae9779560dd40ad0161faeefbe8bcdc67cc2d0162de7c178269ad712a70b71758a9a7059c99aa79edf382d0abe88cf370427e47a90e0df5ed2b1baddb9b9961fceebec0fff9dd449cde893874e8c9a9cd11f9727ce90647cbbefbe481c767b2093a4ae210cd4db0474556b68ef26851b91b5a5b67a21e679dbe755f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf38b301ab86ddd2cae7e6b00641def311723189d40e74df2a33e1daa793208fd4b7617bbcfc03e8779de78718673416f8d5628164f63d1e5232c12407ba02f01	1623316789000000	1623921589000000	1686993589000000	1781601589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9993543772be8740d9ec8e99d85b97a5e0db4d0b47d89a454f5c5a29c4b623115ba31d5016f87f57a120057cdbf87949fef2998f32dc23a2a7ba50e7969b3a49	\\x00800003c4a26ffd0e496094be6511f9bff6a88880630a6f79997365d2ab685e037de09bfb89ab8192188d8af3f011c81a6713cce922da203530585a2b4c3544ffd914145b62ff607fc7701247e9cb7445d629d08200cec30db077a28452158c9aeb61b2ad8204cf30292dcf067895d0f0305e8b47a78f571ec7ebc1b4c7a75182d76fb7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe2870218ac9e0ef72e4c1201f905e11a0342093aebe2854936aedad412cf710fea5acc74089d4fa688301494b262832d6047085a059b4b868b715457329c0604	1627548289000000	1628153089000000	1691225089000000	1785833089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x991350191f42fd6f538388dad3512b02d90f25c488cfb8e780ea1c5f987d65c64e3a7d7515538927d3dceaf418636f7eb0064a33faedd7f5e16e6902bced9677	\\x00800003b921cb5c785d0492d15244fdfca86c78963a8c93bccb75d25bc59a15460ce31344845fb948f4e9cc4c49590e75e39d6135da9ddc64ea362fbb45d31ec79e1e81ff799be63dccb68d892a38e34dbf3f7060c2d70833f55f74134e7b192a226fc93f5d45b5eb10154504ed5684e1ccf5cd8128cd91259af704265a78c4f6fa839b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xece53efbd79e4efd65f0856287345470d40cb1aeb54a83054c0742495ecd78c97cb1a8a957cd436a56292a4267db70a28ac87eb80d63fd39e195b12db52a9707	1636615789000000	1637220589000000	1700292589000000	1794900589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9d6be0ab2e176e1c2b9023908f1d8c4e9e82cae7805a5e0d7660727e796ec334e016f824b9ee19928f2090ce52bb723995b9c0b073e8c592e8f78cc6e2f41520	\\x00800003aaddaf5f3c628e897a592d01ae435a8fd7f01bec29eb3641b37dea6363e9235d823c1bad6eb5fb5f23bed777786d9326cf5d23dda3d8f76cabcbf27105c5300d1366454fb3a2da37b495990cd4b1ded4b7eaf01d221aad5b69542f329c84a41c3ea198ea81745fb8011f293a928ef7c80146186430c01d55f1ede41bf759b769010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7e5187238e2b3e792ee652f0ceb6e4fefd0c44e1bc40f858fec39c83ef03f7ecd169cc37f6281ab705487d0af55da353a8145c029fc39895171509723555850e	1618480789000000	1619085589000000	1682157589000000	1776765589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9eb34debc73d18401d4749384e9c633e23df10710c04ae66b980a1ed82a5a69c26727cb895ea7430e0b4a437550106f8401648977f5e5185f1850b755d2b7f84	\\x00800003a9b2b1b6336ed32e1a1d63c4c39adfb00a7166427ccde41722b879b0114c812aa75c47d1667eedb0a4460ec767a731f0baeccaa403862119015e3fa8418b06e53f60427f3368c676cbfa13009959352ce386fcb2ebfbf71daa3fd3f6446a85af89e8ca3787c38e3695a37fee55d0b588452508354ded2781f2af84860eaac2df010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x17ed58e1385867a3073207cb18d792882bac8f1ae7ede8b426ab18fbc7a56b51675cd3ed5bce4825f9ad2dd3624f15ee6e01dffff9e87fa5b143703c237a3507	1637220289000000	1637825089000000	1700897089000000	1795505089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa1bf45b28a795c0518dde8e6321dcc60852f2b888210e6f9d82e927b7c76de67ee7d81a1011322a2189f86084e894522fbf26bd93e48753cd65d86ea585f7650	\\x00800003ad9f36d87d919c2394dbab5a08c3d95ccfd7bc40aa95a869cb8af8fed0aa4776a9c5f8ad5763385989aced081409cf8000a8306b88d9e7b022a137f18669758a2a2c754977ffc7862531e7f07efb940728d4beb8b73aee09e32579d68750a25d1288b2a49ac19589b46edc4ef099a779225133478dfeb3db1f28467bf62ec6bd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x269405e13852599b52350319c868110b5e4067fe041e8f88b2baf0a4da481b287ea3e2b60b60f8f4a643a76fb841c84309863b822aee8de00ddcd25b1eee3201	1612435789000000	1613040589000000	1676112589000000	1770720589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2535c14c0895d441f221f5c98b74e8938b62550eac9974eea05be02cbd00749945261528534e8d2ff86e9eba511f1dcaf8732371099f572277e998874842762	\\x00800003f563f83607e988ec3df923fa5cae8b8693366771854d51541728db959ed78d23c3ee9a7975c6b092c30db0304512b4a81b1a4ea772aed8ecd1261fe22b6877bc6130fa918b5317d00eb79833ad36e79d8b9bb03ac03f876ac56b981d87d67a631c46d1d20aab2e1713f66427407df0ccfd2665f2fab375ea3ca7912d0794122d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x86487f2c3f6400ced16e5c1a308db32ee2bab466042590f8c3b9cf241233e7743cff9161ba3e0e2321142f4da44ff9858eb78695f70778b4b269b95ce7771b05	1622107789000000	1622712589000000	1685784589000000	1780392589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa3cba2b54c5138981a40128116798dd3ac3bd87265f9d099d4038d72224256c6dcac17f9a4c563f3abe455c5911a4d0920489be5d7f296c61abf0b4107bb9824	\\x00800003d59e2e5ee022e817f8c9804c3f8fe8051e5ec623e875da9242c94337d754732a35f96f1790b7917820964b192ebf59767b7bf3d5a2ba21fbb84e6ef0d623cf4d79f68785f8b3470a1a768e41fa209ef9a31abe801593a9574e1a14eb08353682496134d62d891a451b1d43ff2b5b9a2c9763bd4f243f0ba85b716e876165a57d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb21815b815b259cc67fa18870845fb038d07385eabb2ed017832224e05e573b95304833c1405073ea2df7f20a5a124e07e946447623533c08f0b4480f36c3d03	1609413289000000	1610018089000000	1673090089000000	1767698089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa427b89feb0f0078bc7ecd74a6952033cea853d298867dd3d187582bab1b9850ad583fa643c85c4b42e59362b0ff8a10f8944a9fece41dd674795a07e50c4152	\\x00800003b1187e5b3e47c5ab146299cb1a972deddc68f5d2173152fbf91057937047a009fc04ab0a911ba8475c2c18b3909f10fa6846c88ed9ab3b6d0a2f3453e67299a7a4c71036c17481075b988708763ff26767b48c3354830a0dda601aea7e7765235471ab026e785f6483cd31b5a1a5988822a0d2d2873b38910282d43102f4304d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x75eef37c00296cd5cb4e41791743357a9b3317a28d78d5b48a983efb3fa7db55ff9240bffc3a473452126143846a093fe2b81bd5d6b4ec3a0f55cb5b44545b01	1631779789000000	1632384589000000	1695456589000000	1790064589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa8e78226391ffafeb4a8a4c61a5dd51543ecbe564fbd2d46226749acc82c8b1fbfc7423a4063bbf86a589e7950846a89d763222a3aaa5c4621d01e2fb67de12e	\\x00800003b7c4dfde220fc6732fb948f9fe42d723fee3e533cbecd53e701cc486e25f522a55636a474abcd1901d0e80b2ecb712e732cd8a724678ef609519fd7b098adb13068ceb1c12b71379bd5ce194c6a43802cbbee2e1df01b12171b63525afdcc38a15d92372a6a8c14e3ea0d0758548cff05983b011e4519de477c55e786ea93139010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x27a15c21d4f1aec8e01ad0b1d0647ccc3d02235342bf26564b9f01c8ace004c473e2b569d14a91f90137c1a13197fc0efbea221887f18b874167e1bcfa80bc05	1613040289000000	1613645089000000	1676717089000000	1771325089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa95f9b7ddc565eeb11a3d3af37d8f7e4582c6da4ae8c32148059b9df15e10f03efa9fe73e6973dca1833e975d739d29f4024a00e4f473bc2129475a25e6d0840	\\x00800003c1520ee6b477568903b893d3f14325e77ce8c0f30aa9412a9411e2fe91549e81bcbf28eef3cb32cf745da6d8f4cd80648f7f5525b3867c7ff89c1126feec3a4f847a25a5201b965a803404fa9c02b53f15a6295e4083f63b048c042739d34e878bf1e96494dad83a0019ba302da94accc1cf5a8d122b6b0494c38dfbf05480b3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x154073b36dad13783dcccc01904a60f05e31f2946b1878ba2c685a4a3963d233fd4af3c01c12307ddf715056ac1475a348613e0155c70d003c40db90f2662703	1623921289000000	1624526089000000	1687598089000000	1782206089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0c3a96404cce6ce6902260c6ba4a80e6b61fdcda3aae1e4f64d6beb7e7b8c15fd18d28ee35ed3969fdf051a92f6df8e8673b237605c2b54211ab07fdd59748b	\\x00800003b895028bb87b745a2366cde90c446e8bb86d84350bba0edf7ee69f1e72eddc0aa1ebbc654cdd68fa97c866c87954edeaf5bbbc08d3381d9f5a227bae1d1d152b3f5cef1d306a23f9fa3d1a3d7a926e96f439b130fb302cb26ce2e751396253d2ae61c2f5d66beb3058608e2dec47f92fb1fec657ff392667d073765dc39761e1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb0866a93baf01b36251f981c244f35abc60819b97dd63f9c5c37de2d4f8bd1042eba756217aae9ed2e9b62f9b265c126c798c7957f5ec57f766684ef1c87ae05	1619085289000000	1619690089000000	1682762089000000	1777370089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb37b0efcc6a0f551f551252b83cd6ddb7d84b9e4d31d332ac6a182e70bec2859d07ba983f54466ab3cb6ebcad62b55d952b2ab23ecd95093cb0e2694222fe790	\\x00800003b3027f32c3c333f3ff9032c660cbcde5eb72f1e2f003a1a0389f758e2ba3ed8d1b2639764d1f43630ba5f447e662730cd4572c0b249d21562704a107a1af2f4b7f1a65e6d81ec297bc93379641b441bf47f083e5b812b0ccda3b66031d2d28ecd70f87a5e5bda300ad09e315700624284e2f86e882abaed20174f54df9eee0e1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc4148cac633f529369a54c9c0d613f9e3c40f34a9006fd5a93956eb64d956419d5dd9fd3af49aab2d9fdaafe12ea5b135f6532d43f38d1f819859f103bb94202	1631779789000000	1632384589000000	1695456589000000	1790064589000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5737c3d1b7e74a92e3d8b280f6b73f30dceffb242474b12f4ff7ace301fdce5471ce4fe08f9a564e694409cd34f993be5626299ff727475a02f2ddacb773403	\\x00800003b28a0938253e67e48b9d80e6c5388ac55f2d70887b1db66cc1e78ffced0d70ee9f535769d9796371ee0c157c96221815f27612f40407766a70b50960320555e7234aa63f5d3f57298b6330871d74b13cf18af3aed948cc87444a385d46b6b14d5fd6a2d0000b59c13495051d0d2efd053815c0078d8b5e6b04ddfb2e3355e549010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7063924aba4ad92143b897850460f7906aff50e48b3db2ba62007e53024b6d88f5306f2cac69448c5bb0af10589522b389d210b6c75362b56bb2530d21c54600	1610622289000000	1611227089000000	1674299089000000	1768907089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb777135e69a10cb40acac6845aaaffaac5c51ec5735e90c5f0bf64e09ec20b925cdf533ac78f25dbf37de00d9e80a75c7406fbc241e416990895ae4f69ad010c	\\x00800003cd679103ecff5d41be2ebb1c76ad333ed6d3cadce26f90fac9ef17a1ba6256f9855932faec4e15966380ae19be66d2c331aab6fbebf9232c95a8901be6b0e0c5765eea1a0572d5ab1e9c58c6335dc5b231aacffcab3a8968c78fb825c8bfc3c6ca75cb64d44c731d4df66a6bdaba442afffba4e7c5a878661ed5bd90aa3c29b7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x64763d1bbf56b13410a225f5ed5a92bd104048148253b5f21926f1ce166681a5cd52fee8d2ca98ed850d40e6bf46d4b29d325f51f43af3284e572f60668a3e04	1638429289000000	1639034089000000	1702106089000000	1796714089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xba53ad68079797374ac906274e5e78ba316151c24ed5c09e48cbbd6030f07c00f1220a63c8d926943044fb4d8c7578d14fa48cf50dcbc42124a98e71bf60c693	\\x00800003dbafc55ec12a2355d512a62e9738e6a3d5f215d536cea7699d40ff9d52ca4626b8a63530c992fdae72190bf7df193bf3d7bcca675e23318b5e7a0b9b362e276e4d34317be51cd2f772636c5cb22ea810c709b873ec4b7c49e6a07872639279b669899e32b2fddc28920904c6f0f3d00c65ce6badd851e50804ffaab11044e85d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4750506e8789571775b1c888fd8c6dc47827dba6602216f8a646c22fa55d58c6bddbc72aeeb800e36b6cc5d013a59f1818e65c38ebc088e68a4c16343903b00b	1625734789000000	1626339589000000	1689411589000000	1784019589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbcff0c46a3bdd50e7dd8b860ca4e25a668411c0a12f850c2ae2f74c118a0f591ea24f3279ca5edcf0121d5895aadf8d723904894fb578bf9789d0ac91eb4792d	\\x00800003a02aca2009389fcd7c9cdda839dc9eb17d6887bfe76e9d35729be233f379e67fdb6a42532f8908dcdfc92990030468970d4faadea8659ad546cea76f728d2e95d0247ba4f4fe322bb0e8e020dff61b0e95f0f8fc20d41d97b5ea6f1b39636cce8576b4f3e8bf923fa1503b976e564a7dcc7aac5db82937cd65a4ffe56d4f90b1010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe4b03fd72b96d6e0f994df5d2959160661b9df31224cf49e5aa9c9ed106a47ce57403ed43125810454b978f300c901213263b7de8944f33fd87df4d992c02f07	1619085289000000	1619690089000000	1682762089000000	1777370089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd73b27d1e9a003218b4e7295f4cacfcebb57995516a1b844cd4f24ed80f1004b46a7dc4c9ef5bdeb0dcac85c5be7a5196f8beab6fca154eb02f79764471e2df	\\x008000039a0512e8f936957ccc8ccf397fb7bca00542841e6d64bf4df09760301fb0699dd73cb900db480f4640c520e9e4802b3b16c81daff6d4bebac0e9adf04d98b9a85733f28ae9590b645efe0102976ba31a1491f51ccc9dbd56ae5f4c90182a4c7a3c1cb208bbf6a2d545f84cb10f512a0a601d4a6109773aa332d2199cae176ff7010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdc292cf067a1663b7b2967fed4a70e015c93b66db35ca010884b5c4d624800781b42a98a38f87f00a62b110da91ca84ade5e59bb50f758e9fc88133a869e9b0a	1628152789000000	1628757589000000	1691829589000000	1786437589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbfd79c9b2ab2eb6c276c42a116fc2a2ce9caa36f4444f85ad23b6907b70953d34bc8798f5da77af97ecf3de778a8fdf17237f8be9f2597e119e7edfd2b3381bc	\\x00800003dffc02c5160a764b9cec5eb5c3ffec82799780ff86cbf98313fc66b4dea9e2418e79f736234ef1391cc357308df38625880e619314e8fe1a9d7cf1c2f84c22f22ffaa52f238a5c6648152a785facb23f499bba2e3d7e97b4d091203e5cd95763427ed3bb83616a85d3265d387f88de0c30e9322bf9d8cd94ad74ef05b0a85737010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb7c35716e1af6fcac9956121c91e2dc7b74517ce16bc219519e5b6f92d07d226f6a052813ab56b2120cec6975548545b9f70b051a032124b6fae81bd36535005	1619689789000000	1620294589000000	1683366589000000	1777974589000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfbbfa75500b06da668b8d325ec2b4c31ba8b0d3ef2c2cfc0f09b2dacd4d2b677ca927711dfe54fec5586f0f4c850f7d5e5e3a18fc17ad73ecf83bbf5f59a41e	\\x00800003e2ec3f6c372d201cdf5bf674d094be74b5a9f0b0657e76bd68e0b4bcfd8c576f9df49cb8e211dfe449b7cb2131fc7e77c32c9560d3aecd045679da7f21cd0746fb141bb19f24732a80dcdfedf81570af938134442dcacb21c32dca63142275539ad7bbaf01607ad72357b9d7617728a466d0f88a9918935ea564f863645f300f010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8ad55d6a3e601d577d75742f54b02c2ac50210ff1c2772fcf0cd6c531476e0467fee6260df059d757ab1f3d8f05f2195b57ee5d11e9e46ef8d6b041f7296f404	1608808789000000	1609413589000000	1672485589000000	1767093589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc0a3134294b074e8cf652a49eb15458731c513e7977c9f07a33b22f08ccab9b9872df7be1341106d59f26242b19e56de01011f849979568542cbf2346cb972ee	\\x00800003d20d337618778d2316566aaa70f1ba557c825c7ecb4d60e11b82081fedbd99866f7b3bae936391c4c682b9c9bca5bd538a7c68ec68a9d3a989983945cb2c501eb601546083df8f23f37586bf72cc1e5b5a2974f6b2555ccaec2b7e74f6f292f41714a734c45588d71f1b7e48975a183932c82ce01bfa7bc64f11059ee16e103d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x423699a90ef4638c87951a4c5a1e6a02f28841309b8b0c989bc6836aed711fb695d05a85b10ab039996c69efaed671cd47a8fcfdd0362feb6145dfeed9ce9904	1612435789000000	1613040589000000	1676112589000000	1770720589000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc107f3385913cae6a3f967a92babc80a42de6f9df20c782d7030d7f03de9667bc4c7eb9eba2c2cdebc3ceb2e79233be6d03945e42b41aea8a2ef1e6627dd6c32	\\x00800003b55305cc9cf4dc559d22a9712c6f637b66fe31c9c43fb32fc92163a2f8f1b13902fc0e826cbdf8623f5973a7762e758eb675f15fad774e0f908c2eba43ecca1c33378730bf9c4dac605162121b55f732af9f5c342cbb8f1e25ed482c5b857220372ec0cc7a70ba704e940f0571558f4243e3a9c61f538d5e77c8f5c36cf79295010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdaf4c750264a2400965313f5c47f49bb96093a8e29add294db4f92d43b02f1d610649246bdf84003965691718d548064cc493f36b4cea4a260cf61f05997bb0c	1614249289000000	1614854089000000	1677926089000000	1772534089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd72b735f65c2c59537bb9a05a49d16eb1338516c1794ce87fc466ac2bcc0a5112b5ade7b267f675861cddd4dcfaa4f6aaaf5407e6e57536a3dfccc19ddf3b887	\\x00800003afb2840e8b8ce162d7dcd526016dab2f19e9759ca34928e53513954d5173d8e3f3b767ae49d90d7e0e639a7adc15b4cf533306514225ca05286c46ee2606fdea32a49e945a95d294fe5d4d23d11aaa9d830489d8986ee5974b20fe92f8e5f01d0e720ffeb4d29e8b84fd60f764c000b0b7c74cc2ad9908c5d96d3d21b32a6335010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf8da8665bc1eb2824ec76273cde068016daa18079b9d48ee2931d251bee077ced51fa76cf95bb1e15210c518fb2dea25d187d39f0040ace2bfee022245e9a20f	1615458289000000	1616063089000000	1679135089000000	1773743089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8370a30fb99f3b3123d2216c70c2351e8d101f1d742009d1a83510dfaea2ca71814ecccf7442bee55601a922e4c56d504d646c2b4fb5e3f69cd9de1926c0b49	\\x00800003ac3aee7cf0364438779b8277e0985ab97f5172b4f14c0eeb9205fb0be22f271f1e00c7ad16dd762e0460496f4721d67c65c2d72b31fd24b1216e9b30122d2e75ac6d08c2b245440e599a86b8d9707dc90bad2e0dd2cc43d8cd7ac4126ff019ee38c39f67c4d4f7427bf77fba759cb69887b5c49bddffa563c8b788e7a721abf3010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x94a2b2e329f81821f89a98e9b3909c3b972dd94239da3d933adc2a0f4796ae3a26612242ee83e6d7715e1b74330cbc734638246c2fb7abe95ece042dd315e004	1627548289000000	1628153089000000	1691225089000000	1785833089000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdeff814c153dae3a9dfd3530e0014825a6c57d3e5ead7f337f7f24e57b3bd02834760f1fa468bd50a5a2072a749376f843aa990a7215f23520f787d6512bbafb	\\x00800003b9b23f73a6dbea64542a9ba8a073f1a98823f1162c6395fa19bc02af7f5376bbed64cd093e669a0aeb5ceb3db38d1f845b30f300f35c13199c17c3dab9cbf644927ed3cf9dec261b2d47f9eaec99db1766dafd00792598cfeb65cdea69ad819ffbddbf8ba584edb80a5573e4461299af2d3a3fd08f1eaf15507fe91a1496fbfd010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc8145116452662525749f58f9b5097808592c87ea7ce843648c26ab283dc9be3cee52ef1186d333114ad5ed57fda1c1e12b23fa9d4eb0488a732d9a8423c1408	1615458289000000	1616063089000000	1679135089000000	1773743089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xded30e7de71133d607a03d80ff15efdf4de9cb6fa970e4f6ba96b7891b99327390162dd2d005e8cb66f82c53a3e31eaf43f05161726a6036fda93acdb1eabf78	\\x00800003cdcd469db53f354f36905f0ff9fb795722fa528457a3a9cf03cb1730f15eaf031642a18201350145c197839782d3e0e1685e8cb923a9c6ebf209cd54fa0a8bde998aa4169d9a4447db27fcd53ad7872a694d567202b61e1d18cb15ab34d9671d7fdba62a025e057761dd5cc7ff8238255b6f3667acb1f5d2712bcbd354ff5c79010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xe1643616da74e5b81153136c1db694017f8ae884358f4de0542596c930571050f95ebfa573d90879e52f655603ac7143622d6b09e806671ff7c92ee92e182407	1635406789000000	1636011589000000	1699083589000000	1793691589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe10f831b59171f53e7236eb56ccc74d7a358483265b6486275252eb73c406ae610ea81e9218034abbb9ca59182a6d04b6bfef213330226f177608359ef19eb20	\\x00800003c7b4c1853d20ba312382e550df25fa777ea227a7cdec588bb063db84402fcc7e1045828e7155bce01f34750687a18f4fb7482ef85d357bfe01daa9e99106884336efe3bf04102e008cf16fe10a8c09d51b91f09f51d9f60ccc1f760932bbeb073f9801aaa4946e82a21c444f1727722dff68e7d1c19d02a477b7cf1b7b32f399010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x06e58e4f668fed1a48245f50b73c3fa20867bc4179a2032d346efdf742a0c3de7b7e30b454dc4a9325606cb4288cd10bc62e4e314173c5eebe26fe7ea8e1d10f	1636011289000000	1636616089000000	1699688089000000	1794296089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe19fb987b4f3d53ef7e825c92c39ce1d110bdccd828cdfd0397079c7491517cdb6b0435b4b367c767c77229dfba2fe1eaa09f8001edfecaef3598eaee977fce9	\\x00800003dc9fb17853d14ca65df4662cca8d0305c3f8a320735996f2240a358ae4692d0bf039cc76693fa3b28a85b64b759bb57d08fb6e2873f8733bda35c93212f49b174d0db6a55c6685fc32ab053685fbc12aaf4166deff5328faa80cac02644a3d526feebb880746f2afe55f6134329c591aeb7350a947f011ee6b9c78a3f1bf513d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x0d20c867928f82b85a48e25b17f6af54f686321fcd40d3bcc4bd4df2d18a8c38fcdb0f9ee2011bce77aa040362e870b6e50fc1a95c81218932e268d8a40ed007	1639033789000000	1639638589000000	1702710589000000	1797318589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe57b45529b57fc30a067d2e201ed09c3db38f588fe71c4d11b2d74d95653286db6033104cf0ea56a5544670e2a57bd6d6741e8db1e920889a68c78811c657a81	\\x00800003b813ed2305df6fba17091e504bb7d0fd2590e23b0d1780b4053fa55c7d7e3ba0351abdf056ed6eb21c7b8a77bfbc78de524074c1810a67a5f9ec4559e2959ad398e4deb4bbeabf359cb440569acd60f95e7f1301dc6e0defc7e47b76f7422154f4d908de5b8082a1812b477d09ed5525574e143b3b84a0eeb84aa2c1d6337095010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x908dd1cbabaf856da0441a8773341f8febda0f05aa9c056091132c828e2c704a7e790a66ab9d75f7ae1895ffcafa8df7614850c03febafcc77569d7b1eb60d0b	1621503289000000	1622108089000000	1685180089000000	1779788089000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe5a706ec8a069e15a0c1c062e67c0b45ceebc9fbecc66e9c87c93e50cd72ee3c9f2610d142835b16c9d117b9d07fff158cbf498e0444cafa497cbb08a9642877	\\x00800003cb67773fc5f560332807a6dba00b77a5a5bca3101a8029e17414a639363a32634a7f9090c91b09ce6a4d40a2e9949dfe379a022fdb25bafbfc42006f26083072eb0f915ff846d534174ece2f4b788427a4152fe6e21d51c00795d45c53b7a032ff74fabd13a057a9e792589ff8c5af77fb9425955748ff5756dae7bb3673d81d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x4ad5af5ad8bd5011b473cf346bd9601c41d135a106bd0e36c491fe45cf82baaa4fd954cf5f50d8c65f4716ea2c9227b773f7ba7f83ebe98e27f4867dcc461103	1611226789000000	1611831589000000	1674903589000000	1769511589000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe567e2a7920c75b3bd387b88e5a6bf6d8c04b085fa2164a5fb4acc92d9dfbd6817b09b42f5f0bdd374f9c2c1a5ab1da4475f855680c1f5f652cbb59609951609	\\x00800003cc7a21a9c13204374091a05fc3776d0e915b4ac0dcf319d6e8917b85194d7ceec15a4c0a8efaa972a5399144ca64b27ed6bb1ae8dc7437ba5fccd8126e5194e998c53abd8bc8eb2fdd15b55b27470651399706655adca1ab6fa0f2393a39ca399f1fd606ea3b759c3cd87d398f12e95f9c6193cdb958f81ee296c7bdd6753f95010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x7f0f1679f6fe4edd284cc95d67f423854ec65235a9e7d4c247c197094e3a7f0c339bc3ae866fab2b3ac449e06faf11435f173f621cfb9ed186fd97feaf226903	1620294289000000	1620899089000000	1683971089000000	1778579089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xebefda6ea1f853d414122552b5d8930c88d397e054faa009cc4022611839a971c2db83563bdca74d49d621321ff4fcb96e532aa3fb2d9be4e69d1b40d1a8a9b7	\\x00800003bd9583c3c704702a7b983f0636bf6af32582b8e7e6ec9d25d3be3aff65647847511ea04ac3e7c8e7f020c2f4495342a755d4048459c9f176610b05b199075bc283b37fab98474b0515fcf153cb5ae8ac1e4b46317806a3fd1e64e592a598217ff9ba140294be9f21db241a4e826a61de416964b2ac610fd30e7b01db0ca2b2a5010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x71e0953f25d516726af5c619b481afee67358882ecf898481fed79159c662c63d29403da039506d38ebe988c09099f66edfea6e6cc3a04c2c6fd10819e635b01	1634802289000000	1635407089000000	1698479089000000	1793087089000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeddf4477fa1f929f70e9969233d92f08babe07d36fe4ffe484da548db9efc059fe6bcd6b687d1eaedc3a16a01d7a78e2f0a92fde4c081c9957dcb1d7ee12e37a	\\x00800003bfa1b06b9ae04cd5be5ebf71a31b3e74009b122c4b70becb364c7bc5c792b83204c7485da8f1d8574d5a6241b850c41ebfe1c5389e5546192504372f2711e0ee244be463e7d4a4d3ad1aa017ec35a899203489bb8cafb1721e4af0e325a64e04c770b7a8cb435db71c885df0e87a9e01880d63a33a4d6d015cd21308d515a237010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x78b64efb8086235088fd499169981b65f16cc32b0b8aebaa1a83f927bec52e0adbab0cc021b6f4df9bd34ca41c603786ffb77d4b20057d04ef28938aa157e507	1609413289000000	1610018089000000	1673090089000000	1767698089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xee835eeb0f76cfdcecf6c570d0dd139d1b261d1b16cfac6b53666129251a3550f0ce526b0fa9f268c366cdb6033ae46fcf955b5bf5654e09fbb3437780f8f2ee	\\x00800003ab949447088b917c1d96fa338a26a6ea1c7a33a64a2e348c2785b6d45e6b277ee2ad3039e2d861a79e6b57d938797c41287ca8cfc256a86fa95496f98193a377b8408b81343978444274cf9352d6fcda2adc6a4fdac7d93bef6ef7613e59ea9feb641ab8185887ab2ec77523d996e097200c5924923c12cb9421e501fd0810af010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x2892de43144e02d978c42d84e6325900f11cf811be911450a83a923628a47df03587ec25fc2bf42105907d94ffb00c816b5dcd09e902351da4b7e2a6e93b3405	1637220289000000	1637825089000000	1700897089000000	1795505089000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf0d72bc0f033c034fee61c4023539702a883ac2c4527c0cf632e0aa162131d90cb81d139c0db6f2e79f8ee7391cc90794c61da70a25a699717bba1a49cbd5969	\\x0080000392dcb7a65584704850af1abf746a0167d48e4d321c1f5f65764b3be1598f83ea56a24deaef09062dbd657a5cf30aff1548012df2b002c61c0fd6830290bd2f362f42a9a4f611f8ab5a70fa25278b18675a5fc30c9b9c9384af6c41db88f86f5751244ade9d5dc4faf2ac916847e2c45e252038f1b4c2f06b58a1317a4a296ff9010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x5915343e506933a941e98aa97eede34c3d193e9caa0f96733efeb1e085aeed96e41a5893a34beee5c55bc3ec762aa70a9ffab9e501851fea42d17dd94fe39505	1637824789000000	1638429589000000	1701501589000000	1796109589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf19b1a7aa29f36432bef472cbb7f635c4147b3c3dd49dfd88ebc5c03a9f361ff88867f7f6fa1e4a72ad1e4adfbaf5d8380b2a2f514fecb79b9482bdb443f47c0	\\x00800003c337288dce5d2a1b1976f412fa42fbc1b193a614302c9a1ffcdcf388814a92c935a2ab24a8daa7ec36f29ad5e0db15df958d2ff58e1f93a1950bb0e32871cdc7af141791e26e7030515d33adc01499c5cf450ec65b1e04811cafe39b4690ba96eb3d78a59baa60ed3a96284615bcd3d3de62ffb55ad4d13b4a9bde88ca410199010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8e25898a8e6e180b7f1b786e23ecb92b23544aba514537c74c158819e77a2ad8f971af6f8abf898e1537be83968548e835d135e9dbc90614c55a24d681574405	1625734789000000	1626339589000000	1689411589000000	1784019589000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf4cbed6ec7c98421b317a55f00750697274196fdefea2d5ce9ecd2b281a0223a391344e91fdca422d968cee6888c1a097c14abf7b96946872532c5d6518d9900	\\x00800003a82e936288cfb6d94d8e88432d0812e27cb499098d4bcb0dee48cb57f54b5a0e980bd8c3c19c35c1e15d54074181e439d5403055e692c750910b5e64419dbf31ec36aac36e55d740660499867d0bbf7057f09ff4f027fb7c90c5ca5451aa18a955e02d39c027a732af3cbe8034c7af5442f0a737d3a6cca6a34b56b3a0bad571010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xc758e951fbeb2890bc9baf0b84e7f9956ab35f437a329a0d192dd47a1867d996f1864c8d35c2bf9df319dc6cbca6bb1481d65ea786b8acab6091762f3e1d4409	1627548289000000	1628153089000000	1691225089000000	1785833089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5a3bcdf6913a884492d885e1563b063fc187e67fc489c235b25838dcb0faf21f3ecb07b07ab799049644f1576da2999a2dc8eb9f1b52a3b50dad8d57ba334ad	\\x008000039d51c48c4e0ab99d28abc3d72abb7a3a8efcb2bdffbc310e577b06d0975aeee881e4a0f05210253255d03e8a152968e4fe22c31e2791d714801b887f631b9879a19dfe9e97fdf49e89c60c98145cde8c2e41eb41fe52d5360ea4524265e329064dc8778ea318444835b47f887ec7818df2383280239b60043bbc280480779f01010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xea71b645c11ff3bb0a1d6741425614c555a836522ed03a389d663d2d3776d0012347ce5400daf0a824853fe6dad7e701d94e21340daa78413b12e7e20f06010d	1634802289000000	1635407089000000	1698479089000000	1793087089000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8773623f8ab5b7c900e59ce1b87b1748a0e8fdc318259b510cf67ccdfc1e097332d72d677e43a94f70fd25d0e2aa8ab02087c0365f245a453273e866c3e4aee	\\x00800003c0e00d90c452ea47492f17963dbd0cc0687fb47abc9ea2ce960d78a569ae30cbb1988045364c9155de04d9a1827689a985f49f38d1650d28f4d8a94d67a5e6b6106ee385e2e31e75c7f31fa8cbbf934a5d8911dd1c801d738b01eae24371371ca1be167678d15ae990311a971ae9eefa4b764a0db573ef37530e1f578f5a6527010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdb411da68f7d13b24d47536e3810547b71a855231f21ca2ddbdc2cc0b01ec9fc8518fad4419ce019774ac86bc9dc3d839293296261b675c518204fe6e599ba06	1614249289000000	1614854089000000	1677926089000000	1772534089000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf8e3fc22807bf9f84cebf3c314ab87b7b6a3cd69972e1f95b4a18e0d3799ae83a1b0d3542e478afde9ef4c16de3504c3fb49f3302dbebd48bc501ce53b656eb6	\\x00800003bc02608a5aad42bd7009e85e9fa8dcf6750d00b4ba26a598af4bded1ee6a1385c49019cc244867cc3e29790184bbc1d1a3486fef7684c0c43218e0d920a8da12b06b6dc54ced76d533473f93d555a23cc292edeab26d422d068bd11ae2fede9acc5ab716793aa02d6c7fd2b9ea95845f9fa878bcb6c3513e1f2bceceef07905b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x66888b105e0834fb38e9b16d0a0e5863289e614dda3bbc3f62e142089e356d08eebd8e177bdf6ceffb4aebf144dbc5faed17e773b0cefd51ebf656dc5608b406	1632988789000000	1633593589000000	1696665589000000	1791273589000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf917839b47bfcc8887908c36b0ee62cc38c1e257aaf8edc44c29c0f1045ba8b756c2bbe644f2237a60441ed17ba023f7971272deadfc18d4cf6fb7e862a10ec4	\\x00800003b5270e67a79c3303383aecf5d8a04b42c9619f49c13b8650e753433540436ff0e90ab932b76e0a1b30defd4e2b16c586a887ba2089877341ae022c1386d3ef13046dfc28faf8600461d2c431ca1b5b6e2b1edd3998e4224097cbd095ef0d503c448367963595de97dfea6e33dcf19d16fa73377b2e5dcdb66f33faf7de678ded010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8ae11b08885b6f6cd9827bab3dbf1ea161c54bd82eff1ba41527306819cd8593f66d8246e55b34886a5d6ce39a5f8d2b08c32eb96305992d0c3b14eb1cbb5a04	1621503289000000	1622108089000000	1685180089000000	1779788089000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfafb0e1896d6867593d4f8bf78c0093d2597c7463d8091783afe5bd4470d21e6b111322666dcddb922d2b01d8e5cf84329c9f646d72b5aa1e209eb97a074f0c7	\\x00800003dd81f2418af6e88f41a7e8c957166b84c28e08020fb6ef52cebb4e7899627bae9da55946f7cb255e1ee616767b520fd22c53af8e944eb0015a3dd400405cc7ea278009975589cf9440af9ee29a1bf42899f554b3ce685985df7dab48328fce404615e9978e777348759afb79f4b41ad061efa624233020545af76f8d37f3241b010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x28741e4e314841c8e35215d2e1a0485dd1c5ace817dd352ccd1b76aa38a7c8c5d775ff08298ccfdae838152433df67ec69da49271cb2238aa1fe7779fdc0e00a	1614853789000000	1615458589000000	1678530589000000	1773138589000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd136ecb9dc655062ac1bc0394d8b943130ff5c73ddd7a9bf7862fc4f79174fe9834de6ced535bef2d2dc56391150368741aee5988b4a28b90798221fa83aa8f	\\x00800003c1b44966db375922c200add3469613dcb96b55229251e1edb8c971a7f99ead301d284237ea99eba9a9914fb43e5a7f6702c8abb3c9f97a013e6189bf7a0976ba493aea301e27b0b832e18a9a50a16392f00cb4a46fbe868e5cb96bd206035c227cd2ffc6dcaf285be248b75b87b87b02552f617f2f88d2aa11a0516682b5552d010001	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xd119c1c306bd9958269f0b36f0300e5c6c65b3332360d8befe1973cae7078230af05ac83dc56b0d8d78ee44494d570f6c875839a5ba516b923bb5cc2fd57d20a	1631175289000000	1631780089000000	1694852089000000	1789460089000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	1	\\x78fe579ee9215db99e257f86888eaf6b1da2698049ce55fef3a7e1c4f8dd324984bf18667ac75f3449e4b635451ceb6fc4877395fa056b782aee173dc4ce702a	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	1608204305000000	1608205205000000	3	98000000	\\x26196d39da3445ab03bdcf1a3c9ad2c81f9b6d4f6c85ce405bec0c1d5d5cb30c	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\xbb287112ecd7b8555613aea7069a83df324f33466d3d91ffeeccb323efd6093d6cfbfc1fa8939b077494345fc8300ef294b3ed26e86f13d4b6479c90b8e79e0b	\\x833637d82665c26443015603beb980cd059020ff738d2ae3ffbb96242b797644	\\x1b8d37d801000000209fff9d6f7f0000031e973b09560000399500846f7f0000ba9400846f7f0000a09400846f7f0000a49400846f7f0000600d00846f7f0000
\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	2	\\xb060ec00caf1a798dfe4f070286e9c25b65bc6d31d5726eb9892ad5213c1b9ba95a1d353674ebf732ccd186012f9afe55143f3475d3fad5d2c925d235dd2a999	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	1608204314000000	1608205214000000	6	99000000	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\xe464c054de3aa5149a560c58d6f56bc21315a1aaa1f9ff2299faf32904338b216d8531f3638c0dea45cf590b29d37089ea36f5b25ef4c4cc481b3a3ae952db05	\\x833637d82665c26443015603beb980cd059020ff738d2ae3ffbb96242b797644	\\x1b8d37d80100000020dfb9cd6f7f0000031e973b09560000f90d00a06f7f00007a0d00a06f7f0000600d00a06f7f0000640d00a06f7f0000600b00a06f7f0000
\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	3	\\x1e6de588ae5df764791624d17ba0695535016232068da298e972f5561fcecf3987e74c520d792e88118b21a8c7f1b4159a79abb1dbce19f1c070f650485c99eb	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	1608204316000000	1608205216000000	2	99000000	\\x4bbebe1c0c6bdd5173826d6aa02dbfc9bff9367a2e0b9d1a3c89b9cfd32e1ecc	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\xc29899c17ceba973c8392a9a6224981e8da680a08b531b63c0b4fdb7de95e8e90172b8968ac72976e8ba65916974ff2c5616474d652ea33bc032f91ba276a009	\\x833637d82665c26443015603beb980cd059020ff738d2ae3ffbb96242b797644	\\x1b8d37d80100000020af7f766f7f0000031e973b09560000f90d004c6f7f00007a0d004c6f7f0000600d004c6f7f0000640d004c6f7f0000600b004c6f7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x26196d39da3445ab03bdcf1a3c9ad2c81f9b6d4f6c85ce405bec0c1d5d5cb30c	4	0	1608204305000000	1608204305000000	1608205205000000	1608205205000000	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\x78fe579ee9215db99e257f86888eaf6b1da2698049ce55fef3a7e1c4f8dd324984bf18667ac75f3449e4b635451ceb6fc4877395fa056b782aee173dc4ce702a	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	\\x62251939b61e77606a4c7cdb905ec5496f83d7b611fe8a8133da49ef5fbcec4447a72ccfbc40fb1fe5721c7eac07a06b90554fa38056885f20e32756374c5708	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"FV85ZQDGG2QM2CAV9V7STJV4K53G9KR38F2SXTRNXGGT3J0QCC05DCWEXNKRZDGG55HTBVGXG45QWD3ZRER0JWXHH09AZFBEDT8RCH0"}	f	f
2	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	7	0	1608204314000000	1608204314000000	1608205214000000	1608205214000000	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\xb060ec00caf1a798dfe4f070286e9c25b65bc6d31d5726eb9892ad5213c1b9ba95a1d353674ebf732ccd186012f9afe55143f3475d3fad5d2c925d235dd2a999	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	\\xf7c78b3f88195e7e98a6cd6faede7068c91936d2b5b06abd0460a3f438e295713bf039f97641ef8977e330174efea8acb57f824661f7ed7862099269f4f7930a	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"FV85ZQDGG2QM2CAV9V7STJV4K53G9KR38F2SXTRNXGGT3J0QCC05DCWEXNKRZDGG55HTBVGXG45QWD3ZRER0JWXHH09AZFBEDT8RCH0"}	f	f
3	\\x4bbebe1c0c6bdd5173826d6aa02dbfc9bff9367a2e0b9d1a3c89b9cfd32e1ecc	3	0	1608204316000000	1608204316000000	1608205216000000	1608205216000000	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\x1e6de588ae5df764791624d17ba0695535016232068da298e972f5561fcecf3987e74c520d792e88118b21a8c7f1b4159a79abb1dbce19f1c070f650485c99eb	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	\\x219c7897560ced7155096b49c25a45bfac65252561e7a66afdaf991223e3b109fa18be57082c4bc64148b26d2aac6085105d2f4fdd53bd7f58c781b1f09bc909	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"FV85ZQDGG2QM2CAV9V7STJV4K53G9KR38F2SXTRNXGGT3J0QCC05DCWEXNKRZDGG55HTBVGXG45QWD3ZRER0JWXHH09AZFBEDT8RCH0"}	f	f
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
1	contenttypes	0001_initial	2020-12-17 12:24:49.737933+01
2	auth	0001_initial	2020-12-17 12:24:49.76274+01
3	app	0001_initial	2020-12-17 12:24:49.818643+01
4	contenttypes	0002_remove_content_type_name	2020-12-17 12:24:49.838579+01
5	auth	0002_alter_permission_name_max_length	2020-12-17 12:24:49.84709+01
6	auth	0003_alter_user_email_max_length	2020-12-17 12:24:49.854122+01
7	auth	0004_alter_user_username_opts	2020-12-17 12:24:49.859523+01
8	auth	0005_alter_user_last_login_null	2020-12-17 12:24:49.865493+01
9	auth	0006_require_contenttypes_0002	2020-12-17 12:24:49.866988+01
10	auth	0007_alter_validators_add_error_messages	2020-12-17 12:24:49.872402+01
11	auth	0008_alter_user_username_max_length	2020-12-17 12:24:49.885651+01
12	auth	0009_alter_user_last_name_max_length	2020-12-17 12:24:49.892964+01
13	auth	0010_alter_group_name_max_length	2020-12-17 12:24:49.905095+01
14	auth	0011_update_proxy_permissions	2020-12-17 12:24:49.913292+01
15	auth	0012_alter_user_first_name_max_length	2020-12-17 12:24:49.920182+01
16	sessions	0001_initial	2020-12-17 12:24:49.924725+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_sign_keys (exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
\\x833637d82665c26443015603beb980cd059020ff738d2ae3ffbb96242b797644	\\x738d8ce211bde306e71e8ad5cb15fc6cdb680160cca32edc16f616affbcb26470b4eef9d63b34abf08d76061f073b3b27cbc0c445449e602cabd4a8cb5f8fc0a	1608204289000000	1615461889000000	1617881089000000
\\x247270384cefe266791575ebd68c44491bf8656a6003343db3241bb891125527	\\x47dbfba70f1ff337941e5583b6ce4d57a1841248ccf88068ced33ad28750eb1ee9ce972ee19b18985fb97b75fa428ced61adfd802346d9cb893442722300fc05	1629976189000000	1637233789000000	1639652989000000
\\x8b1de1af321db6649d51e84a3824888dab71b1b1a71e77a6b07764d295fbaab0	\\xe4ec8ed0e2d280854e84f39d589916be9dfc82edd601aaa5d3e27f9e80432f784906d41e98bf1e3b44c6be7611aeade7abff7814c3085e15f32ced6c8499d902	1615461589000000	1622719189000000	1625138389000000
\\xb8fab5b3140a7e7c545f0a475b9735955ab1d050a51881df4fd31533911e6264	\\x571517c18143ced20f098ba4319cedcb6162395d81b2a6903b7f3c096de4c8833260fb58d7f265d2a404bfed2d287b553d6cd8e7866d6458e0c3d48a5c81c703	1622718889000000	1629976489000000	1632395689000000
\\xdf4e8bdcb1229eb02bddea2ab5e21db3d5cb34b5406bfa8a586e910ab4b39afd	\\x61fd43ce357de1ed2b5a94ddc111cc886150a98071a843fe540a082bc54b70a028b4b99cc0bf8a6515f23cdd10990ea52680244a97ea373ca96c52346fee2709	1637233489000000	1644491089000000	1646910289000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x26196d39da3445ab03bdcf1a3c9ad2c81f9b6d4f6c85ce405bec0c1d5d5cb30c	\\x12da20e3d09cbcb21cafc61fbe48352365d33ea8e2824027c1a975923405a799d9ecab3ac4ceee62d18dfa6271f87bc79f9abd68b26615a4e33b7659b7bbf2f5	\\x152a19ffa49008d50c27e5cb937a50416036792583470f030e25694482ec3eb664f4e917420df09571b3e002798ae8a6203f7a8c68aaa0a04e6913e8ac70db213e84adb55d9fdabd1244fcfec4ee5d62cae7d09c9bfe4a2f7be8de6065cd5a86557d0b0fe44b51bc244c2bd45a92866f50f2f9de732156e9eb7789b848425d39
2	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	\\x4c39b0b882c6fd96f9cf652aec01fdab934fd5726b36b5de4af3f8f3a8dba253d2f96d74f48f9c96e1956d58df8157aadc0e9600531c172d03a4532e51e2f01d	\\x87ae87830acd25c6e099ee733f6cea7a4c645ed7ee856619a75bce68915ceca507eb047b375cc7b8ff5f994fde21e0033f30791958d570f2d6f9fcd058355d836c09e7f6021b6a1a0a446049967684427075a41cb56ef23a638e179e0ef5240c57fed04f9b64e66f3bb2599535de2c454aaf2b3e5008305775abb36afa881bc1
3	\\x4bbebe1c0c6bdd5173826d6aa02dbfc9bff9367a2e0b9d1a3c89b9cfd32e1ecc	\\xff940722355169ea675239a1ab21821946d78914ff981be7339da8a6606911e9b721e12642afc9970e0dc23cb4d944d6cec0bc71c31fd2fd3b68822245caaddd	\\x767b3aac605a01ddff9049bb58943e7b29a3982ce497132384cd1b16059831484c5a5db1b9f66c099b3fd11beaf5b47ac0ce276d1c2f4c9eaf0313195a7a03a4738d6ee678eb49061278918576cb6a8af466a2b356c5ac234b324223d1680afabd4bb6215cade5056c936bd5945cda3db3b9c7bb3f3f970a1beaa92f0dc66b96
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x1a3b4b199d5ecd69a8fe491f151c159e2951b27ab8e1a52d84f58d20472ea255bb9a974098b1e16dd0a1991a17942ca8e8f7868135ee1fae1996010e3e20c3c3	\\x7ed05fddb080af41315b4ecf9d4b64994704cf0343c59eeb15ec21a1c817630056b38eed678fb6102963a5ee1d810b7e347fc3b00973b18812afbd6e6e918644	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.352-03W70Y3HFCWBR	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383230353230353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383230353230353030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223338584d50364358425636504b413759393446484137304e4b524d4e33434b5451334754414243345950364a304853454d39415651364d513832434233524244543247534a3647514a475041485437514754304b4256475a4e5243534330384537524743374752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335322d30335737305933484643574252222c2274696d657374616d70223a7b22745f6d73223a313630383230343330353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383230373930353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252463035335930544552453957524e43345434563534353446305359413848534241363350353845415842465939425037453930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2245503838513856483146484b4d4841465434534352374359325653365054543631504e5836545942383846504650523345413330222c226e6f6e6365223a223234334d534a52484343424353474d5930435a4733485a5a44414d30303641544a4134433552303636505a474551485a59435647227d	\\x78fe579ee9215db99e257f86888eaf6b1da2698049ce55fef3a7e1c4f8dd324984bf18667ac75f3449e4b635451ceb6fc4877395fa056b782aee173dc4ce702a	1608204305000000	1608207905000000	1608205205000000	t	f	taler://fulfillment-success/thx	
2	1	2020.352-01N4EVKWPMHKE	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383230353231343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383230353231343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223338584d50364358425636504b413759393446484137304e4b524d4e33434b5451334754414243345950364a304853454d39415651364d513832434233524244543247534a3647514a475041485437514754304b4256475a4e5243534330384537524743374752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335322d30314e3445564b57504d484b45222c2274696d657374616d70223a7b22745f6d73223a313630383230343331343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383230373931343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252463035335930544552453957524e43345434563534353446305359413848534241363350353845415842465939425037453930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2245503838513856483146484b4d4841465434534352374359325653365054543631504e5836545942383846504650523345413330222c226e6f6e6365223a224759473833354736445a46474b47424a333757374653484b39563659374b4232394a4a3358444243324b4d474559574531564a30227d	\\xb060ec00caf1a798dfe4f070286e9c25b65bc6d31d5726eb9892ad5213c1b9ba95a1d353674ebf732ccd186012f9afe55143f3475d3fad5d2c925d235dd2a999	1608204314000000	1608207914000000	1608205214000000	t	f	taler://fulfillment-success/thx	
3	1	2020.352-03W61G14FCR60	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383230353231363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383230353231363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223338584d50364358425636504b413759393446484137304e4b524d4e33434b5451334754414243345950364a304853454d39415651364d513832434233524244543247534a3647514a475041485437514754304b4256475a4e5243534330384537524743374752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335322d30335736314731344643523630222c2274696d657374616d70223a7b22745f6d73223a313630383230343331363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383230373931363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252463035335930544552453957524e43345434563534353446305359413848534241363350353845415842465939425037453930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2245503838513856483146484b4d4841465434534352374359325653365054543631504e5836545942383846504650523345413330222c226e6f6e6365223a223051533851385141485859575a4147594a4258565a4637475a355659345252364d424656503044314d4250303248313446503247227d	\\x1e6de588ae5df764791624d17ba0695535016232068da298e972f5561fcecf3987e74c520d792e88118b21a8c7f1b4159a79abb1dbce19f1c070f650485c99eb	1608204316000000	1608207916000000	1608205216000000	t	f	taler://fulfillment-success/thx	
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
1	1	1608204305000000	\\x26196d39da3445ab03bdcf1a3c9ad2c81f9b6d4f6c85ce405bec0c1d5d5cb30c	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\xbb287112ecd7b8555613aea7069a83df324f33466d3d91ffeeccb323efd6093d6cfbfc1fa8939b077494345fc8300ef294b3ed26e86f13d4b6479c90b8e79e0b	1
2	2	1608204314000000	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xe464c054de3aa5149a560c58d6f56bc21315a1aaa1f9ff2299faf32904338b216d8531f3638c0dea45cf590b29d37089ea36f5b25ef4c4cc481b3a3ae952db05	1
3	3	1608204316000000	\\x4bbebe1c0c6bdd5173826d6aa02dbfc9bff9367a2e0b9d1a3c89b9cfd32e1ecc	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\xc29899c17ceba973c8392a9a6224981e8da680a08b531b63c0b4fdb7de95e8e90172b8968ac72976e8ba65916974ff2c5616474d652ea33bc032f91ba276a009	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x833637d82665c26443015603beb980cd059020ff738d2ae3ffbb96242b797644	1608204289000000	1615461889000000	1617881089000000	\\x738d8ce211bde306e71e8ad5cb15fc6cdb680160cca32edc16f616affbcb26470b4eef9d63b34abf08d76061f073b3b27cbc0c445449e602cabd4a8cb5f8fc0a
2	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x247270384cefe266791575ebd68c44491bf8656a6003343db3241bb891125527	1629976189000000	1637233789000000	1639652989000000	\\x47dbfba70f1ff337941e5583b6ce4d57a1841248ccf88068ced33ad28750eb1ee9ce972ee19b18985fb97b75fa428ced61adfd802346d9cb893442722300fc05
3	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\x8b1de1af321db6649d51e84a3824888dab71b1b1a71e77a6b07764d295fbaab0	1615461589000000	1622719189000000	1625138389000000	\\xe4ec8ed0e2d280854e84f39d589916be9dfc82edd601aaa5d3e27f9e80432f784906d41e98bf1e3b44c6be7611aeade7abff7814c3085e15f32ced6c8499d902
4	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xb8fab5b3140a7e7c545f0a475b9735955ab1d050a51881df4fd31533911e6264	1622718889000000	1629976489000000	1632395689000000	\\x571517c18143ced20f098ba4319cedcb6162395d81b2a6903b7f3c096de4c8833260fb58d7f265d2a404bfed2d287b553d6cd8e7866d6458e0c3d48a5c81c703
5	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xdf4e8bdcb1229eb02bddea2ab5e21db3d5cb34b5406bfa8a586e910ab4b39afd	1637233489000000	1644491089000000	1646910289000000	\\x61fd43ce357de1ed2b5a94ddc111cc886150a98071a843fe540a082bc54b70a028b4b99cc0bf8a6515f23cdd10990ea52680244a97ea373ca96c52346fee2709
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xc3c051f81a761c9e62ac2689b290a47833e522395a8c3b150e5756ff25763b92	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xba6abf4652c3c5a9aa6c8997037d7d250d3f5b050f88491f5716a31687f18e2b697013f6c64ceb3f096b49e9928184ad8c82d0764d83ced50eb76fe58ffa5d05
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x669f90d09057eeb2d42af32ab37329af279586c2526007cb195d2718875df4dd	1
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
1	\\x41d2b546d5f320ab8c0bdcc965b32ac56a0d45d5cb46b43de0226d76b9c594c93de424f4400c285208ce40fc765f46ac8aaf002fdfda8830073568e7d8d5ad0c	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1608204315000000	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	test refund	6	0
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
1	\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	\\x26196d39da3445ab03bdcf1a3c9ad2c81f9b6d4f6c85ce405bec0c1d5d5cb30c	\\xc605b9106ab00758a3c33c0b1a904259dd71956ed59f2e46b8747a8ecbe38c80b412537d30051f561c98b2ca13fcb8367f05381622412d2e51fbde27783e3703	4	0	0
2	\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	\\x0ce6e42bef67258f1c30ea69befef114c55c8ba0bd0b09ee8ce11409455e8b89b8af0068c9ebf30556dca19b831ba4b55fa5b7af150ea7f08651018d6669d603	3	0	0
3	\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	\\x5e428b17af8f27f7f49bd18c13607d8292c4983e4213122ab8baaa965b58c1dbd625c0854f45fd5bb3d407c2bd4a913bee3e7fb8f890c2bc0e6000f5b2475400	5	98000000	0
4	\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	\\x4bbebe1c0c6bdd5173826d6aa02dbfc9bff9367a2e0b9d1a3c89b9cfd32e1ecc	\\x3cc1c8a37e9a33a50c71089ec65589b4b02e49315c5b41eaeb749c955016c426e30ac77b06fcfc7ea9d2747ac92f697d9f8b96ba6a2bff013ea6ed47ef4e8d08	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	0	\\xc70b064fc516e98b301c2bd32b6785431f6a5191394cacc01f978c05a6ae9e1df8aba391e333998ca30fc277d545d7bdb9634da118b313daf16743c1930b3103	\\x8dd87293e8eace6275e94a099101730076057205db2e10ec6cb93f71dfd46096454a90d7685ec1c0205fdef75049c38d0f922c0fbec26b32efe38fb24c43e51e	\\x95ea181e8a4568672218da46c09577b81b33ac52ba10878816ce2cf9ababab007354ac5e5e57275abdb3df07add3b14baab6e1e05d3574de6843663b90c64a80ec2d7dcfe1b24187f82fb900a8d6546fed7912327c4d89fecb81805eac750ae2a5a76ceda53dbea52020955efe1fa67445f3ba55cf4e9c900a9b077a1bcf645c	\\x9c3d0b4ac70c9198a0a3c8830f7a1f6fa942f8da7d41656338bd0d476c5e70bb81361793c47fa6aa33696ccbc7386bc2e4538e3715bb5480c78189146b40c925	\\x7c8b5d3c93a7a7ad0cb9b7fb54837a0332b354d0b2f10e7a2716d48f77240c4c922a7814d6d68d1e4ffc6069cc30a9e8d32db11d11939f609abf44d44edb7b09789c26d92a5e481076830d9164c57923a3cc4da7177f9af7caebeecac5cb3ff0560cc1e68f6386efa24c553cbad9482c73365f9ca70c7bb2203022fed68ef46e
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	1	\\xe488f2e5494930684cd5b2ae18515fe61c31e3ba3cc73b01a8ddd1df60f44a56adb5ab307beb2a9aa8464b64606f1790169c4f7d303cfa6d73682e6010f7fa0f	\\xa404de1056071832f505c36292216558221f2780967df3fb21d5350e6acab283b1dbf41b846089d91c5217508a4ab30f182459702afdaaecfb97900cf0c58935	\\x76eb55bacc530dd38c7a06af7886eaaa3c5a121649ad42d1185c4766ff8758e1cd216f975a8bf15f8644ae164830c3353f67ad3da9930e119054f92d0f5f4a8f9ca000569195cd3be9e9c02aefe3cf9e92ceaed4d7a7ebd1322ed76a4e973126324d5f0614b27076adb32226ac4a167486854fe403e50834e0fb46d209caa0f5	\\xb9ba358d8ed12151d23af0a83ebcec3701e1fa4d80a49a34b42945d5ca232c4d602877c5221a110672c7af47d120c776b4d64439d9f6dc2b8fc86891e3097721	\\xa9bd200db51dd0cdbb7c1aeb2130efb66df4f474e9b8299c34042905e85cce7f47da09443a87fe133b8f6e18956f58b520ed43d6a540aa557344d36010529ee0686dce7fa272fe940818c670f6f87a18a2c4245e5992214820fcbaed27310c0dbe4c7af75f6bc1fa755b3ffed4f5c00c825bbb5ded233310c7bba6d33084c3b3
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	2	\\x5574b3e6f7a5bbf7b532728dac17a6fb773e3c3e15d71dfc6b429244ada89c29b917ccc0bed26b5d86deb6798cacf077c8f221727d6fc8ee3a57a3382e02c20a	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x40db563099b25900da4d83326885ee28784a153c25dab661dcc5ed21fdb8b367abfcf8ff02472da88454cc83298c554d3d9e76fa313028223f40fc7891a744edb3808021f6e3df97c8792717e5c889c86bf584567e3d49e65d59224cd79ec3b0e7ad24e033703a847ada161de9b0768e07addda9ec86c5f19c28ef975c3773d2	\\x80025a76c80100d9ef5fe8b4aefbf450714e7ee654af878e5d18be76ea154195e7bbfee6a0e1f16b7cd6862f67b70118fde341926a1a137af1286fe8b051a8bf	\\x014cb48d42bbb55462d403b4b051f1d77aa41ae32b48825373bdf651320e4c4d356094d6a59563be5843226d1e9735e275e7bf1c77b73345e4b716f4fbdca76c77df05cf4b672576d5707c87d416b0a059e79aee75ff4d580888101fbae8a64d7b1e9ba2af97d4763fa3fceeed58416fdbd8292e4ab6b72789605a0bfc7e6733
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	3	\\xf2573b114b5c5b6728ef5bbf36ef443ad20f2c110912926bba3fd5e45a94a99f9fa4821c811b11ddad9f80ae1655ee717267fee87b7861fca75f9786a6e30a09	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x5f1a04897c1e852d37d43e0896e102f29f8b6f270cc34102133451a776d373168d9a412f7cf9faf1fa0e785a613f3bb72e93f1219e88631ca2d65393b7c2315af3cfb960718537a0db3e8fbe86bbcc4655945360d4d098049542568e9f916c70f96ab78ccfaa5924de52d1ce922408c5192b6378f5110b9282af1ac0ae7f2c68	\\x7d04253f9d734a895d8b79a1430ce48d02340bbb7cde89ced705edcdc59d3f63567ceec3dccd503cd72f492d430312ffc00040b832f257275b89b28144702fe9	\\x965d2ee2ebe9147ed3350cb99c26a021aa41b6864b60ce6c65f2a7907917e58ffa8f1ad658a61ee09a5bb4fdce82dc3320a1844db504d809a78b2ecb1b5ba10e29c188e76151cec1b38c73c23bb7000fdfc84e24909c4aae2623a2438fe65661289e9a141057975959a500552e92d47cd3c9ac4e61cad1ea373b055bbbe13c51
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	4	\\x094456b63d225b12999d0379af9d3ea117ca8b7b76d14bc6e292d259c11058bf6ade277312b742e8c7dcc9cad84fa9f7ba37438e1428f5be32c39e4356c5c401	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x2273847815d8403aa5932a32ee8d192139e52bbe5844b43cc028e5f434503e7d8ed851dc2a4b3353d5b91fc9feb4729ee41bd4331b3537c247a87e1c48e7a5638cdfd2599a8ab7e6a4318712399d412718c4dd1d62ae84549d78f439a7462f6af3510e37325b7e09d747c9ae77b51b9e1ddd239e6ac0f8b9a3c85b9f8e0878d8	\\x8c3f11ff227580f6e5e832d531fe1a6d3f2dfb401161862b4adfa0a171ec0f53520557a551eb1e0e49b2f4a1fb4ff86a3e4544148ce2ce5e2cb339a93a421546	\\x09ad3a4b0de3a775e7daffff376e52d12ab942208342b283d92873933b5ffb05ae1cde7a09d07f0672122c333d9bf1c3649bf0f9510ad02818c87b0e3ef1563b5f578dc0ca7adf7fb39aa9373d7f5a6b610acd6b663c8a419fbc381cccf43a685f5ba369234fa6a73b7f3697c90e01f4138739c6201ed35a19b6a86adc1b77ed
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	5	\\xab1cf08b64e6015d1c8a5bc58eca095994550c25f2faba8d8eb9f3fc4ca3a377d3998579c41f2b6f9f3ff770a2912dee4f66c0b413648f869ac5f74fc6a20108	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x121d7f096c404d60713ced1692e87f3212a90d3fafd190c16248774196ec043668c19f23ae6fac6b829b2bf5bbb5911ffe50afffe8ebd2ab070f600656a7427648bae617cfb3259d5e75ea88d7c0329435fe6e6718d3b2ccb09b84049a021dfa1799859b95ea000cbe5d8d5437ce55c2bf48a3eef8f6d9840cc290d17d9e8b78	\\x31ab142c45a833394d395f4475bafffad96b4e550e395137134a644541b1a4386ff1ce4c103585e59c4299e86c7eab66ee2aead90eaf374cc468181862ab2421	\\x9f288945ce9bf11e8f08838032987c5446c647f5222ef2e6df54b24d6a16f930c10eefbf8148886a42d44e26b6c7690ad55927e2728d010ff0675943c9f8189d145895f78f900f3b604a72b1034dba1dffed63e780cbe9441e07810f90d7d5bb648fcc83f1e44864fd5173e9b6f01ce1b9bab33432b63782838e7ef09335be53
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	6	\\xc1e1fd5e2498e623d3941c80fdb962c304115e733d1c03fff24760de7a0182d7a2689cd40245903925b99e929c3e64d9342189d63ed76f4b53081a88298b7d0c	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x9fd4b7707bff292c82f0da5de5b7f82c2eb39c39480e43ff9cd04c09f0b965628c0b301306f646d31f669b05d9ea7224902a669cf4743a2f76a7158388b2468bf7937a7807be2ae37431b0fc28fe6a1a736ff7b8ed2d397e959d9572b1c783e625c207fc14aeae360f6966bd22d6f9f442d55d9d633fae6528680b99d62a8240	\\x463d5d829f95e332b497e6a960abedc6e3c992dfb7a85aa923bb3bcb6ec6380a97b127de49af6ffc138cedee8aef7bc994620e93fcc08c50d696b9c41a2e8f36	\\x19046ecf5cc34b026f1f971e5f5097cdfa459d3f86987037329308d2255bf595047e207dcb260760a55093ea76f880b113b4dd787401d5f129f7ee8a9b2b5bc9b1ab1da7e85b3bae1ad4bdc18257b311e3a282487a32984fc6d0cba90ee2be9f28964cc8770fbef4ee3caad65fe25b035e2831489a50c4a7b27be5167cf7963d
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	7	\\x2bd335d65363eca4ea81b4373d52fb4e5f57a574551a4c4e888a723bf3f54805a8140055931151cdc6846a05c726231be86e86c4674be9e7980b84b84c560d05	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x59e9b207191e00e7b764c19db8d120908abe4bd784bce8d27307cf52127cbe56584574a7571cd12c67dd69b6c9d895985730a1989739dff343a1da9d37bb0d0183883b52decc5abac4f2e0fdb9cd4b9e57843228087017ae58e42dfcc2136df51120ef3b166e92c064004da200f40d281acfb961a1a118949f4902302adf6e37	\\x1c845c63b7a341934e7d75e375e30b7dd8639d2610716dca4dc36e3c826d96c9bd03c4cd7005aad58532e53e5a00a4c5c9e4d03ae7aa9cecd8f8424654bc6f58	\\x2856db915bda2c7dd5f1adb8814a7cebdc194628a974d90cf303a6b1283f1e8284f4b5da98fad5909ff3d38cc3d114e7c3ae14e3cf10305764dd6837c022f3474833c8cfb50257072636778fdeeef1ef939f464d9644df4bc958c026f2d6856d9ebf38fc9e7be56436bf0af5abb2de34b1b05c3b4c5d98470fa47675a5f11ce7
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	8	\\xc0a161bd157d2b41bec2f5ccce5431342b50a05b75cb21e23e30da54aa2aec0b562736cb972e868c8a5797eaf4afada59cbf885af5c30bc88fcf49ad47a27f0f	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x7062731b257f242d7c85a7290714afb540930c6e4add2174d4be91b9c1b491bf59e80abe86c71ad1eca0bc8f4ebabf1abeb6df6a11acdd9b57d06565118e27b1a1fc5e1ffcd7609b9216284c479f16a6eb82154a4ce0a78faf9ff93caaf956a2c22eb83e1103f4e23b42d68d98baf61aa066ad6d36bb38cb024e7474d229dfe3	\\xfcc83359a879e8796e2ef010f54dd2e2189a3d19cd18fd08df46d8d361fddfb78b24732c03022c8f1ac5736f9453a7000cb892043e26b18e89348a5eb531ee1f	\\x8245a1456be9688134b1ea89073edaab4ceadba1af6c1d484fedcbffb879b63668579031dbe545d8461dc01ce4274d261846cf4382efd6628ce08939eccaa6c7963d68b85e517ed3fff4c2c98fab78950af667d14ce3f04bc4f8f4f171a85a4a22920c230a79ec99aea55c0afca54c1888345cd042437b4e10c4109d28335f9d
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	9	\\x25df0042ca1b0d381493196d6ed85b27af559e92226d251a279914e5b5a036b13631a8cbd58fa96057199bbfc3a9015edbd2a479a0482b315438f4b83632420f	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x819f365548bbf3e66b5a0b3fc7e436602eb8b2e02644767f5ad486c5cb15b59ee47d5ae2eafde20adf04788fa3f00391fe239d0d73d66a0eb2bbcaa0e237cf287e1e039fa13e4f5248445cb33faabf2aeac50c45c7da8fb1109005765f1e248ca0afb04686d5140d4d4f0891ae2c73a7ea4542b24af94a52b9c96183395c6262	\\x7235f4ac3e236c884ead7c465b8258ff5b53e2ebab089fddfafbdeb65ed9143539fe99c7f7940e8212e2246e61dba7da57eab0834f5c55bbb082bf949057f613	\\x96f88f4d516b854542c33fcc6d475a9a7b89d3a6ad18a9937d690f799247628fb6ed55e4ad4460263cad58f91a68ad9023d575d5b7d0f3cb58d4305485745eceda79dda401e74ae38404ff7bdc5ad4cbf4f2d08a64552c6f1ba208cd38fdf48df9c2ed5232e7668f052707120efa675a51edc9a430bc948b28305b07b1ae7f8a
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	10	\\x2119cb7d2bf2ba380b545ea1238481f931e282e358c9e5b30d0769f19e393349063658c96f45641eee7befe984ed0ff26ef360bd64ffa7bb0f554475def5f60c	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x7ed7b320c71ed02ff468ea4721a2803540bd2236e630bd411e3df15e411acf668893bfa8880e85c65871e9c82327775dbeade2df4d3b09e27efbab213f500a2cfb7177def79a5b05280e40f1956bfbdbe6879610c05e50051f785366dc4e8a0f5335dc6f33f1e1882b97160ccfe9f261e768f85846a68c8acf137ed80051688c	\\xf59608298948c6902018e5952778285b8cc0561107406f59ee5946ba381d3781aa6ef7aab091ad1a025a46ebd522953afef50a9e4a19b124f10c2fe0b1f023fd	\\x0e64fab6efb54485faa7ab7734c67a9e224d576f393c666d62f99c5fe9d79a4761deec6a6544d9e24156ab9b95561cc597a8949dd7a560c6e77eb3203ad3ecbcdf6f8656849f5aa1c26c1fa90c176f2fe814de44044ebff27a834f2b9e79a6a96ca727efb12e1ee9e4c42375c735ea6da121e627058a9256119c01af54878522
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	11	\\xd62803a5201ada779cfd9b3c97ac6309a9b3ab654fcdb32aca0a7de7af866ab221be64e09ea9bc7cb7f40399f87b52abf16924610b03b5599797f95feeecde00	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x5680dea187787ce03aeafd3d9856c31955ed848d7ae001993e4171157c5333b24d86539854d1c856778937d2a2369da430c846c5cf98f96fc5cd829effc1394aaf855e5dc1374732e1156d7ddb8d1e2d4014548bdcc14f882ffcb036287d6f2defd6c8dd8302dfe3b3690d0ad1581309d8253c3a1bf0f84ac99f83db22733d43	\\xb11ab00bdf486bd9facbf223a556b7eb9d2af1695bffac75f325b360b5c5cd1fa3dc5248105235f1fcad12dc152ab389116136d4dce471016fe687efba4b2c1d	\\x507dee7cf428d0e2f435ebc3b312187a5211a19f8239cf0a340254fd898ce9a0b2d6c2caf336d476b49977a0155a219ced6292b487f9cbf6d063c2e5eb464cd41ddfdfd727ba9a00b2b4f8b3feca111797e6a9c3808d4004d8289ef35d07b8d145405af4a368453273baf7f1048a6887151d68b48f528dfd04c602c6211736db
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	0	\\x5d0c601a1931e4dcd89468b20a4a69285695bd76ef7b9f115222e4d7ec65467ae9faf0a17e09e42bae5719d77fb1d92a8306b33a097820b773d13ce5f214cf01	\\x8dd87293e8eace6275e94a099101730076057205db2e10ec6cb93f71dfd46096454a90d7685ec1c0205fdef75049c38d0f922c0fbec26b32efe38fb24c43e51e	\\xb8948383c41939fc5cdf3977a1118bac2fa508654d707f99a5e68f3594ad1d9b1ad3f0a0d9e5493bac895003e8331c1e19a3618000fd59f3fcc88eb95799c0e713f0a3031e12f8e79d76a8058d3c479920e75dc7da821752c6d4a7b12cff84ced0c3e31d340fde59899c93bf9519eed556429caa3260f0ecbd7cf45d440a5535	\\x587cc381a8013b4cea30e1bac9f81689fecebf1cd05a88467604a3b7a5235235f054764b1f685d8ac9c6680c275ecad15146a6d6f154c39b6cb1f3eff84ef2b8	\\xae019877497375a84ab307d77c394d964475eba009e3c6376fea041213886c1bb3651b91e068057898504bbac1ef0e9451ed542213ad135e75f13f4679c74737b744f141bfefd014781b416988c0a7989963e296399bc8d5607b439ba91274b21163481c0c0fcf0b3eba4386e67930fdd3c3929c1e6e9219b749ce07c06d6c7a
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	1	\\x3aab56e1dc41394d5cf1917841f509eb983c8cbcb5c9940cb00df565c8cc22313bde3377bf2ef6bf37ad663fa44aa73e091442eb249578bbae118c65c19e000b	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x0dea8e337cf53d8126d1cfce93c619cf6ca9fe16c9e38159b87f88595f7506e2ca0f7b49298151b50e3c5c570e25d489d93ae03de1284335ad2561e4323b4b592b2bdc64d0cb2e23549c0f14c4f96839d560b3316c4d90bc537cce49cc124363824dd7df0699a8a97712c1ca05881fce929cb83c148e71613345f2eeb4b9dd27	\\x08ac5756105a0b4e5a9def31b18ca89f760a47db230bc65d4c9d9add5165eb1e2d6c3138a5a6c28f3d001df43895693ad00afff390092d9a066ee2ebdb782126	\\x1610ac8e7c782bcff0bf2232ac1ee6fb3404306717d542de8feee3d8cbf0990104b718c601b34933c9ca36b774c365b7058a7421cb831e4ba6c1441a391379ec4a42add9587947d9ddbcd0d81d0c57232a9531aac2745d9ec1b49fd3d7716a346d0c07bce3e99cf1bda6e9ebd0658e5aeb3c32decb1cddf3ccc9e80d93bd0e9e
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	2	\\xce2f29f2e5e1811d72a3d6410ac335cff69ebde1fcb607b5500be685d69c9e05f452faa5a6bfc5067885b2caf706d2e97865aa8ed4f8a0d3f56cf9939efc050e	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x8866db3da2d16883e27b2e0a27738da1f8919229081a4992e64f053d0f93a1fa702af8fb8404c9561588beccdff2402795e29358fc659685702d7cf19b753ced7ed8eb5a8325f1d690959d45bb625bdd480fdc3e7771274591161e0c8b88177ca6b08a426da342e64e51ca58a06514aade85c0e1136094e43eded4ec28956175	\\x9df2b410aafefd4d6281e40398faf1eb10b3081f1ac4dc3ab725cd8b810571405ebf11bde578574f7cee93a4c4e52817dde29da880ebfbc7c8aa7560171eecdb	\\x2169953bc0a60096e0e64422f228222fa60d4b1592bf9535a2d36665cb8bb30f071a3eedb9970ac1b7809c73a864dcae87eff3ef5f603b44e95342a2685f12a19eeaf364c1125f0cf3555950369ced4c561ce62a4faad3839dd37408364d359d5124828fa4a0776cc3021faa1918fe54490aed0b6fc8a146e7ec1e24a988e4e3
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	3	\\x5cac7ca611e050662789822d0167ad15938dbdd831f79f76072033f7c7f088cb47fc3b524092d0d8aec15a8574a6cb69bcaf451e0f8df67e2e86db8ece032001	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x2f971ff6f7daeef3a797436b45da852082e221342fcfe381623b919e68a9da49cfd4c4fcca493f516533dbca7ada02baa2dd3a4f121d35fb0ebbdc5be18d43d52451c28f16f099d5fe0057abc65cb1c467e18669aae73643496e1e7596419ce8569d5f524e12e239c63f2269645ad967659013f0a37363acb3ec017bb185ab0c	\\x1715e3c310006672f7a22c392670c6553b80b010949dea9f3d5bbd4f11a727b65bc0e779342a64c17055773439010693839c3f29bf28e48c1279e5d4f956cf0d	\\x95570c552ec925c98d93060e6bddccf194bbf2b49b98740636b149cf3b08df33639f446b0ad6fb34bdca974eac4348dcd5e515a5ca19eab69000185e1fb6b5168c0bd48a6829225d1c7bd122ac179899baa4d661bbfeb52f12a09cb18e11a1eed6f8866e8dd699c12e80bb2338189f44ee195941ab5e710187238dab47743deb
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	4	\\x098557dba39760636086f517d3a0afb88e53c542e98816251f93ddc8aacd1d9aba4f19f1cb647b4b0c976a5272a301f0a3ac67a994fbaac3399a9d320c389a0d	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x3b641b706f32f59109c3a307217cdc65490021fd33cd347dd4bdd2d8933ee31d50568a98cde93e99fac94d620555dfb8d12ba68406d65ff3acdace81e6bf8b5dec4f3d4d34e864799177b11be284e0b7ed629cfdb1ed3c5d326736f8e5e4ee88ee9f16440258ff85709e0db474828acdbb2a56ab52632a74efc613f64adaad5f	\\xe5970e5a3df70b7700236c6b8a254f42417f3449ad9011fb195a3ac7906271ab3200fcbeac7a00b775cd4a30ed021b8dbe4d40da8d57c8e7b5bef7440113733b	\\x4ecba0462bc853347de340e40b900220b27d685ddca8a51cc96e6069817d87e8202e9f11c5567df365c3e1aad64b1f787509a6affdd88c8e93fa50a3f91aae3945df0c44041119e9ba4dee67063a94091d49d7cac3eb6d591b12cea73a945c99703f1e417c8afc2fb3d35cbe7aa2422fb59ce979200895375c1506fe0f9b4f8c
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	5	\\xa15f0066f1ae60212b3eca49621eed651fa481ad05532e7f233da3de37eda33d9737b29a4e05647bf24a189fcfb393f30b3616ac3de99093c5c5874dea7abb00	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x3265513992a52f27b4ba1035197e23038d734810ac1a896d4a991ea0ba9e34d83638ffdabe2915ee32ebeb8c999f86e2de28624570cb8a4570559ac6cb1f97e974f7b9eaaff42c92dd24a84f2fa2ab67a0768fc81bd1279ed447e0baca4fae6e0efe3931c69b4955eb4158330a91746fcc34fb9a68aae362ac08736f178d4bf4	\\x64baf7d03bc88d3a8b053b8bb2b98d210e86946deea6b543ada03c9706a5778c2d64509396e97fae9c4452580c5f640d7e790ae6ed4139977e822907a2dfa5f8	\\xa069339cb368c8b2fc51e70cc60cac73b0ceae363a54835ec9e7cee9125a4b05bf1251865016ce124bf199911b5365785557a3b2f37d48f6d7b675cdddbff66d319fb4bef6fcdd8b94b4ffbc54c1efc6f5fd3fe60bff51451c71eaff39b08e727e3f202e9528690e2611ee5f9a5e13e21345c103a46f4cf0b913be33c3488b7b
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	6	\\x7c90b15e82f76ad0deb6f9b6aab009b70be98d15734d4ad9386e56935f80cdd6816b570394787c2c55723774ded1ec020de25344caf53632602f7fbd4f871c01	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x031dca156b651d9531982c69940699f688645b12ef2993a0b45c457fc8fa4784ad62f81b9b689e3b091c5be20ce66f4843da39490c8bed1699a53985989639830458b3ac9bf3a990d56da95d738bd8b575beb6e9bba111896a576b38d20d1a9f5247a8c00a20445522a81a2dfdbe24fc2bc3ed5933cd431e7ffb58bb91448772	\\xc919ea426fc5cbbcc03689830ad111c83834166f96aac31fca625a049a6295beb623e09c1afd2c873392e49270c98ffa92d96b97f3b5f672ce79939075bd6b93	\\x36e4fed46032198596d0209080192ad09a40642f42c46360ca415abeaf71b5fd5d9b4e7adb4e8b5660ef003e82d9fb4523ab0985ccc8ace3ff671e2af42f92bbb836be05abd1b33e9b461d6d1539c318bd7004140cfbdc511733c194fc015568efa439b00853086e92130e69e01a9182485b4b7a409f0d8c89819717dea4e1cf
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	7	\\x220254620c3d62c1fd1e18d721204c26d0091f4532227d3a4000f7b4eac3b8d9e1a0ab6c484a2827d7ad75a17e4b2314795e2417f6f69eb2f182d001ff904c07	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x3f13d2e7d5611f44ab9b3722ae42c0cb3099f11643785f9fe1f03052233ce3a6c73b89656aeaf9dc6eafe5c431ee5c5da94e6b1a9076086d3dc1122e981ca49b8e7f61ea845a347c5492d3e2e8f6cef079a02b58dae074311a55ddbd5ca47f1e78897a58860f5cf2a0fea1544784b019b1afcb38e8d080b065874f7754a63b8c	\\x5f3d1d33b75f806a2aab08d31e6a46a1c4c10559415aa6e289c9b71103f0440b908ce2ebb45176268ddfd733c8d609f7b17925991e5068f260a2a6e5f6cf661f	\\x91dea30c36bcf5bf3d771406f984c98949889eac9a8dd64c7920b6dab33a88e714dd22879e1601ca1efa0947bf62d9c1d3bd09d77449347a7c3b4ab48fa737e5a99ef66f192bf61aaff41e84dd32a467231ede25597be84fccf5c9dfbe41fb4c4759e4c96a870cc371468329135c7b76092e62a162f62c78d7f6aabf22f89be9
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	8	\\xc197a109a1d659320d5daf1cf2dcf4740aafc623076012263c937e2dfe55896cfc48ed15a88e030bd18cd0aee7391b378024276f304b7bc10cd0b8a51dcb7306	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x7c5675c1af0ba0feeb52b944e92cc179d5819d6a0393286cea0657bdf0829408e1caa1786850897f9d221747824329ffbf51fb732bfd83cb5d806bbefa129a918e39296d2b346d805357453546ebd185a9252c3bf21d03f46d060b1f093d95966ef6bdf4d9896677d83832c9c7f9a3c4e4e571670c7c9e46a92bf8e39021246a	\\x3defa4235959727a650c8925767a1adea7376f8430168760dfe94e91f7ea75caee8caaa97e1479d9b0b3a0ff1bb5ef6b8b24902324a322758bc463580b7215a8	\\x67780588ca6601114a09ff5dece95cc3ed9fb68c009a48f1be4dff837be831218f59cc5bd78d11a3d154996b78d6181a5470093ee171f2e6fe54f93fb4517ff1065230d2a83036fdbd738fd2811bfb0061cfa775eaa58b3d7dbc3e04abae711a94ac759f306949a74dded8da4651136f3d6b28b248c0f5e39dbe933aa7ec63d4
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	9	\\x5afbe857d801caa3b979eb63dccc71a7e0c625b9fa976e0b3881e6e140b6fa6710c93d5cfad9cee0b4a143539b160f1572366d3636b8fcbe5499a54e254b2601	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x1afc2fdcb3423bb8e15d6849870566bd2e1a0c1a42e0c316ad8a6c62ad6be20c0c49718856ed9715c99b5b269a779ee111a4887019aa8304b928a693ea7507aacaa5893fc1b33e4f18c1b1254aeda5175ab04e542dc558c0d8432362571afb112e6160739fd0a29d494371654e3a7325215e00a7f145dafb6bcaf58c350237ad	\\x0f029732608d79e648994ddfd5d903d8ebb7c61dcb698346cc8d859391d5a4a0c57e2d796f0e2fab76e05df763ff09b9ac56ca8bdb64c8b912d4257e51ac9b69	\\xc8d35a497e3e374128c65e0eee17bd4e0d6b8235057d61961820c91ff52e05187e959debecf96eb0a247882e20373f6840a06449f1f95ecc17f8a94d9ae3bab5acc3137d0bfe10e73bc5fd9cbce6ae9c6289923c138f938ca0435b44d23b7e9e72995a4d255c4605de49e27846c523b08bf0d53315844e2898125acb8d315598
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	10	\\x0da33b0e3b31aa0d9d3437b12c4f21d47849bee0fe686bae1353a5d2525dcab01dfe9544a0ab3d99301186ba60f82028beee6defc2282b764b2bfc5d216d9100	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x01cd3ff695d9387785222e9ecceba65ca7982ab550dc667477bf7b8da841e864c8608d7800105be56889ca55c5a382780d15bafe2323df6132e98f9feedb13c377268a1798bd028267338deb2f7fdf97dc48871601b5987848b750650cafd3d32dbe2a9f26dcfac14356b7dabc7f83efb98ab00a61a8cf91bf32ecbce9af9885	\\x2645920c01c5311109985c2d08f7195d85df52ab15668aee36829d1ba6d928f7da5169ebe78a6b25a59649d86b39a3a7e5e50e338b13fbc4497efe7dc250a51c	\\x2cb64ad413d344613f53a90c43edf0bf588d8659b26ebbcd01d210c514af432b43071da7825b52b8c9722730ca2a545e2f1f61db9d8c10ae0f05b5924a6fa31d1a2b88bcaf7bc164a8707c6d1f1650296f82138ecc44afd1a1f163d3825ea1e066dc5aea22b56f3dcf5e9d0ff5fbecd98b84dce8d57cf0511c78b7a4c8b9ab9d
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	11	\\xc008a55229214b6432f263cdac732854f557b05b145daad6125ae0b0b24a75ed2874e34b7b5367d4000533e0050cceae0aa9a34b56c40176f2840ed8f7d0cb02	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x02aa02e67f3d112a8b2584017c596abc110eeac7f6702272ffae5a2ffc6bc39d90c7506a21af89b1f139601a08f0b445888789a6a15242b501dce5c1b1303eb64d7746cca074a2d54248ae1d7bcb738b9004fb8b52c753247c64aed009022d04fa6ff37a13df6ef23bfca4c5ebe7636d7dca464baf914b61919901faa265eda3	\\x51c64d9b3f69252479894827834064aaf366873bc090657da5e36ed6cfbbfccf187eff76f45957a75b128b8799676875161e3e4e3181ebe6a7e781978d28c9cd	\\x29171cfe3fb689ac190d15815272666cbfa4e63a0008d1b6b427d06cfeae5d08ea2a30d087a4efa19754b1e344dcb8dbc8687471ebfcd8890b98f8cb2d9fe932a180b7bfbb9c914d5fa92b70a7122b6ea5d47f90c6b7b1deb47c9d75902fdcd27f43132b2ad76388a4601bd8b8d69672a797055d6d52729e37fcb7b48389a9b7
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	0	\\x1931260dd1bca2652b4bc6e4585cdb25ec9dec5d742c32fbaf4ce92f3e23a3e8ee95d3772d0adae177a8f5846d9208d58c537c39946cf6764e17fb4d1401a107	\\xff940722355169ea675239a1ab21821946d78914ff981be7339da8a6606911e9b721e12642afc9970e0dc23cb4d944d6cec0bc71c31fd2fd3b68822245caaddd	\\x443d1cf27148507b9538f769030aa33ddf393faa06bf70903614933e1acbb219eef21ecca98aee5e109f807b4fcf6b7523527aff53314d9899e1ccb982c11b0c9e97f763ffe54af1eff45ec260ca6596f0244d8494ae75d7a44c5c8e775b8dd31ffa8e71ad8a64b51d1f7b2fa56256e521aea3fba700c3c22b262e236b479bdc	\\x61ed745ec414b8fd789a83cb332886c62a95c31f9071cb7a8d20260a8417d2232ff4243734bfe01a91e3e6610744140a278975ead84a31708e64a88ee1fe23bb	\\x882ea2fb1c4dad7621f782b569ee04de8aec0c8165125dc325002b1bbbd449780d8afb8697b65ac47ed718ace843a1b32ddf22e3c66a5ebac23b6a8b9b91697fcbc6d94c73a2c77be50ad299953f3ebaebc2753a2402c3b886bc0c32dd6b2555151299e399e3fb6833352edc462625403aa103ece3e31861f38c1ba6dd08877c
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	1	\\x8d7b13950192afad26e6e890a101cbe170e3d0cf5a3fa94e28480b0e32be0aa76dc360ae669b72c905881dca59068a7a1b33c32a5700915c96d6adde787a9806	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x6acbd06537d69e6b48c019ccf6cb603234b2125824b3ea7d2e57652042301133e3cd7473f1f9e141d0b5a47a2efed29199971d7f55575ec4c50de28497e41c67df59f05fd84ba6a289c4915bcaeb52acea6e742624d3b3d147480653be6aad6bd8659ba32384f143540b7ffa3f3e3d75510aeef7f4c22180e05e210266e6144b	\\x240a650c4d472c91c41ff8dc39f48df342005074e64b42bb8cdd5ceab57513d9ba420a649a3ee15ce01270eaec5ee6981044d68eae80b34689ce28b58a922aab	\\x95b2ef58a2accb002e3195822da0af7c6e0b2d89ddca9d05dac2c29b20fa6e18f90efbab4b71582893cfcb99f41028fac0b1e2810c4c09ed75059e613aeecc529c9f56ee2749c8683c192d85992fedf380c94117e4d62459d2b7d876b51a8418d7f13989cd4388f8212061076dcda642e39ad7cc6e1b603e57a6ca3323d136c7
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	2	\\xa256a1f6dbb5fe45420e31ac394bcd03de6bd34525de96dfff46a75e260991405e8a32608e17573221acee20d5a2b189501ef334638aecfe04162b126f421a00	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x62f67befb8c5234a706a03eddbf784ab3ee09ddc71195f3079ffabc121ea891f8087221ad152b125614c612f1d6f4c50b2925accdfc6c95d5aa269d9aa8f4a303ed4889ae37fbf2c568ca67b71c9c5db4fca74e66f416c0f6405aecc8f3de2b6110cb99c1b656b76eeb13a9957cb12a4fa2a902cef5d19967d75cc7b70d88048	\\x7ebce5f6a2ae1a22dbed584815ea2f1542bba6a0ec1fcbf44698fd8a45bcdd9cffb4598d78ecb448604015f93a2b74f3b946808b2380b7e15b50d026a33b6b8f	\\x26e0a48dab88eb007cebe445b6a15c1dce3e910858200cb965aa751c2f222f689fb914456db2db1970f1c6890210c1733f999e1e3985c6f93eccf206f7cacc66b729f84f55577c920cefb4ec993c880d981735b06d835ba33eee8d7a98c3df37e44ad2e060f521ca2b4a317d55b5ff6cfb6f49517a6a44ba25d4e87a72623ec8
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	3	\\x6f4bbc29458879db64bfdc015f40eae3c86a12a1fc5b116138a36d4d1da7adbdfcb9c432b9318a66abb71da6b578435cca91a7a0069e654de5962550cbf7340e	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x99c0c64e93317301496ff9072bdbb74374b85ae0818fe22887a538eeed7e935b5b1e38b641955f7b4d80a23c828076b5ba8dd8fecd086a3438ebf283670fb6a1698a811e821fd005db09f1ca600d05740ed77aa68dd40ff12e68268b3298633d71b4ad048e78ce98ee62b030266aeef89204ce6b4477ce62f9f6396f6075206d	\\x3bdbf98a0822d273d5eab68471fdf618e92483fd50d5a12da122472b4bb870f94e94f64c44f0c34fe516cff08893e4b075247a8ab3d042e4b4ddb69b67325ba3	\\x81bcca1af06a3895cbd31438b246a85e270be4c6165f4579ca0ab88b1cf6fbf88e4c467a91039f4b6c55186ce6b4ecfea18a69bd95008e4d5538d67742bf9674c60be124a6285222cc0d40fd2db89aa98f2b6629123a469c5c51db99ae50b3071a300848663bbd763f56f9083fc6086e73630b484feba627834e271cecf904b8
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	4	\\xfe7fc06899ae60452a46888b18941dc1df33bb5919d298265ee558021ec7b8da0061d580fdd9f9f247e9a7f4ef56df4052befe7ddb58f0ea861a486773641301	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x27d1b573cb4b47a95824f550251086e35df53aecfdd99c1b0e230b4a9814589df3c89a00bdbebee2e3845cc7a96a9e82d8eefde42313df20dfe500ef4ac2615c9c468e8e0de32211eddb168f1ef36f297d539b7cdcfbebd38aac7330e084c20ebda4da87a00be3c32c5f3ba74dd4a0420298cc559cc16874e815855df1c13404	\\xb62b2619074e2ba4ca484e6a77a4688035a69da6063f915c6331ae6b3bb580849c6cc4c30599ee74797f5df73917dc835ebd71a11abd6f5353546ee9152fcfc2	\\x4f5d61d24cfed027373b24078fdf9a69721e670c6acf03c931432e9185edf6b43ba8eccfb69f9ece0559bb9b4d132e1d491daaf9ea09aef76111170a5a11afc43f83057cbd161601afad78ae95e8333f0cb682167ba0f55a1469a78f5448486f55d849f75d62e2fd662193026df706793c7d78b4cd12793ddad49da8815eb7d1
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	5	\\x9395834a94972943c8c576831d2d239b8f24bf7d573ccba76c62ca99d69e8314a2ea76ce85af451423696bcd29722666927127491eb69f94810106f7d2392f01	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x5a99102e933cebde9dd79d1ed36f8367ebf2170c1483281d0f3f242aab098f301dee5d52b2c37eccb16f6afdf6b0679cd6160f97d30129b375fb4ebcb45ddcb0aae5a1d82de08fdc549dadc0c7f9c87a9d5776b932ae341132e01834cf9d4ec5c83c9005967fc5a56c1a1598191f198aab3eb0b2c23224e60a7ec9692dd9b4fa	\\xaae060e6eba84ab1e456a831674179c3d535fd7a5420ec6101b5f5d6e0962d68955028148ff2db20f03a06604744f7f46002a2f1ac583659ab30ef2212040527	\\x47309838dd7a35574bd6b759beeaae3507a3a01b4c87e370d31663a1bf3c21d43925c3399503f98024aa671901fd789e062a5f183e08c5267362b30658cbb1e3b58ad1d82fa019d9400ed8fa73424d5f4edf1eed149651cfa727de37546e54c8fbc0243298a1255c0d1d1cfea09dd950212c0c886dffbbe688a226f394f73192
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	6	\\x3b98fe5238c9dfe22effcd462ab8ae2dc06c3508fd79e7788acc4728597e5ba8c204bec5bf842e89cd76d3e9e56e745170bcb1d0fe2abf52f018fd529f818f02	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x45d5c581efa1397500c8ab3677c657373987fc4d6a5184b0d828c0addad9e4439ee9fa61a24bb790b463ad923ac01489dbaaedd019327ebb55e471eb77a450c98c2e2c3966d452b46aefe05bcb1ca9b622219f3069a248d259ba9fd07ecb430959514ca97fccd1aad963f764543a98e4cbc878ca09d929cd11f9306fc1046a0f	\\x0dfef989d8d572ccaeb91759f89bbc026053d7027b63f4b15422dda5c5efafaa6a1d401916cd7972b9f27c1679b377fa7853a4a7efb66d7a31ce6bbfd716cd04	\\x7ff1492cf4543da245a47dffef0cf61fc934777212f719b1a5e6770543ed23df389d768dad73c8934ae1660bc02ca4e7e07096d5d2cfd3989bb7812855bf6c7b5bbb87817d50594c5778c8dcb33315083178ec8dc0b188828ee2a70446c31fd13856cbd913255aca92d58d6617d4f95cbd47c0abc3847b3852839008044be6a4
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	7	\\x08e0006662c97083ef169f57f6ad1569a822ecc057cb65a0ffc093dae318fccf05e6204085510b2275ac46852d62f8c82778d7cb57aa9ea54f87fc08f9f23202	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x5c326173ac2be232d5a3f00f817f86c6724dba481707219f94f347e0b159e3d9bee329874b968ffc8543be0339547cf17702bc7432eb69091071afc3baa44e3aab669028a6441fe92ada6a9ce139008a48be3a6a6b28905737c2c25c98605b4d224f8ce5f92658f6087a2403521a6790182bfd0e46a749d2a26cc9b19a0f8c5a	\\x6d973cdcc7be48d34cb044ace0f8f2906dbafc0a46f3ac816bddf18aae3a5c2d5587cfc6812293d7168553888397bb90358d2169520d61e90f87b05e817c2d1b	\\x8783652e87421b01f32898f13f91705f792c76af5ff43fe5e0ef46f29bf0ec05342d613fba9235ea21edb0bca1653aed53d58586b3f7625a870c9c0cb564d83db89231ddc81970d5101efa298d168cc85bf5f64e7303200323e8b0d522a9a1c37ac054040b25c86ab826cfcb8a051e5d6bc9405a8a8cb0b1156f445744c377cc
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	8	\\xcfc33ffa390471c1ec9589c884a4bb48875d3562e76d86a828e76d6ae2fcce184d7184c0aeb3712caba801a3e9551d20d54c16c9ef826b3ad6e0aaabc8f2810c	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x0c23ac752c644c88296984c81ecf6138ace9526c5190cf4d4181f1a958cab06bc1b914c544e82664b3f093b53253572c12dac99fbde8f87b75b99d77970f2abe9caba5ed6ea60cf603c6f2bb2ef4d1e4f7c398f3ce25efde75a2d581fa951f6ef9f6e61b2ebf6fa8b4b6f951f5f97a580fd41acfc295ece7b70febdafb1282b7	\\x6483b618bd6f7e39e8720120fefd73fb540bee31902a458e3a80544a5552ba6b86ef6653ac2b670058f7736f071a0c0809c4ae1fdb5d87eb16d9a7b7978bba70	\\x50c8bf4ca5b539a64f17109a0b7df3b87b7cbf8f096fd2251e7e277d73b37829b0c8936bd7fef5f8ddb860bf86dfee3a71638c422cf5490165e213eb1be791083f6debb3e9cfd061abb27a80438f917dd1c33d44307ff5706b2e7a6972f2a4089dfddeed398438f88ed6bc110f4a60412ef337786514509cd292070c732632db
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	9	\\x2d2687953ad2914a1d4420ca81912d2c91eb25d5100483893b08a8a19b864b5b48f9f3965089874ee50c3bc0f1502271ede62861bfb89a9ecf1ef8f0d864420b	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\xac068d129ca702010c7042e461c94c847eb0f7ecae97c6c326ddc9905421c26652f5a2f85fbfdcda8dcee8944c4ab93a3c0c6e47a377bb157ab20533abc4adf1482e0e49924df0c9153d336fc6496d834cd83e6567cbd69355d86fb3c434ebd36d4e43650d1e6218a2fe7575de327431d7923204476f83610923013043cb345a	\\x8cdfd225abd62acd4052e44c1048f4bc11f37226a6fbba2bae339d48a37663e57b28429000a4ff8bffc2300fe22d2298bb5aef5500946ecf2e5cc823405ea9eb	\\x4c6cde1daccc15fa5d0abfa7fcefd9b2f06fbb5f36ff31ed53eff3886576bccc4d2a5ea764cbdf7ebd7f6b41fac9129862ddd96e4294555c1cb767d690ad447b8bae0d1f82e457c9f98bb7a20a507e3fef8d0847e3770f8a08b0311e87afa2a3cbf3e74153ee9478eb82bbb055eeaa129701a441a36179c64f9e3fb2192f50d1
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	10	\\xe441cb1290bf35be8ce16eb5e16af8706212f07d63fb9fd5cc2111ea5890d1b8ad0862d7b746660e9b061adba88fd796c047c8b13c7abec9c011a53f93a65606	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\xbeb17b483663d79f565183304a45d990b280cee248f1c477cf522311f002a13a75be2eb8ba712f2b783c18bf053851c2c0cabdab3dbea74afef0ecf2736b247ab56139c608cc2ae892411de52160df650db70c4b58314be97a7a221e5faf7852a1bccc00a60886e614451ac062ca5451ae8dda245b90554bfb23d360cc8a43be	\\xeebd13ce6060c51206687c319b5e3b03bb00213b8522df43c982417d5a37c910066aca3e384d65d077466718d651b48750ff937e53c5deac941cfee306ea6c0a	\\xa71906a4c3c4035a9ce79092c6ceb9ff96484793c9a04366ec21da1d7f7cc7a4f600cd00b34b7212b257d71b03a9e12eab3d9724c2357bd9ff5e84fd38d602c585c30b9435afdca787b742ec7e98fc1c9f94477467d6899d57d0942cdeb1b263c01dd559e30a5fd6a407965511a15ec189fbfd9dbcabad699829ea5b219db8fd
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	11	\\x7a29fa30eab1f6b2a7be073edf54c704642b2c9c69370f89f4248e80363dd7596c7a7baf00d7073885bf828baeb5119175bd2086cfa7560e335f9c32369e3a0f	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x89080de843ca6bb3c69249c5e4c598715d3e3185482027a84c646d913c9acf3ea7a1d3f1aa5cf1dd2bf102e1711376dde824731f0ace6406220b1b2658ddd127ec84ede7536d4bf1f61ef101d3fdf70776f544cf98d49bf467fbe8f0b350bfc01af60481a9ef4e29d2f62bc25ebf110cadc2b7225eb6cfc29a51442664033911	\\x5c0d13da8dc52b7015390877f02a7f62c63aef6dda096b42030a18b638e9bc69cf9f036a7fc79cadf55b4a409542e0ac101c753dfa91965f8568b1f4158c085a	\\x42f0fb833c13a74db6e72c52a412d0ca838cb3ec2b0d918b901bf5160e4636aa1002c287934fdbf674489b88d8b4454a6c95287166f897eb2078901049a6677991033744043c66c6b45b23e514be3ae95ea50157ff751b87a8d1580c59303163320626aa09f3aacbc651b7d74b4da5f9c4a7bbb84417e254decb2aa8cb1ae5e4
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	0	\\x0862a58b0202b28735dcd492c484fff899abfec62381186c6a52a348c4246e3680df9a0abcfd545fcc83601fa05494833d8aa25ced3a77ec7400ad7e07fac707	\\xa404de1056071832f505c36292216558221f2780967df3fb21d5350e6acab283b1dbf41b846089d91c5217508a4ab30f182459702afdaaecfb97900cf0c58935	\\x0ddb875684fc57c778fa50b185875f975cb4b8fc33b28420f49bf4a704dacb59c27f36758e8360033ec3c959020e2a109b70296f7847463c8cd170e374ede7e5c2ca448d7d6ec7a29d78253ede6dd56afe09475781ad61aae3fecadee90dd3c062352b6f9091939748ba9563f7cce107e472abbffc5106ecd275b2ff4acb2e51	\\x9170e778d38733f0fd76ca525bc2e75c9b2846914993398148feb6ab5883e6f27a3e495db5bb2a312c750ed458a469b9e97aa28eb2023e363d86bc6e5eba1829	\\x9014210b5b263e24af1df8fe2787e2cf4b30e60acac519c2e3d4388d44e12800471b617ce9c8686cc48d828ccbf1bb44d8bb14e14d8800be12b9c6d2e9ff6487e079f8f73f6afcfb7448e8e06d5ac2313c90727e6d5de3ee37a45a9840814094a4a21a38871771f909305ccd267285ae5f63ebf7cc56bd2c5d186d428e77521c
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	1	\\x7f80cffdf9f31440d95ffd0de32dca5c48151df3e7afcb348de89823468b7ec178502fc1f81706bfac132396306aec1b7b88c9a9f8954364b59fa24c7ecbc107	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x8209e55dd33b3088c00efd339018d05b29e37e8ea7a8197c1ff2e6f957f2ff62b99ae7b4670cdc3ce29422f820a783082ef13f442c931d372bb6a615b53f953e7235451f4cc3b9a3815fc7b1e8c31cd6b1445baff487de70b71bee14653be8c88b57e17fc320f9cf05902fab1ca0416a02e50432453bc1b5497417357e26aa2c	\\x3906ad8b5a210f68c627b67590f531c767da112dd4122598e020d157552ed2c2e64caeb20528a9ba6af5fcccf4e0a093e508c6db0ad42a9d5d5d13255d0a3e60	\\x480de81276e625eaf4c8757f4c9132bb624c0605e107dfdedfd57ab0b73ac0cd2a636a8b5365dc6e34d4427735c2ebe946670b0a22b9f92cde7194626d9413ea9e5c600ce6a3ca66a199ccae830ee6aa59f9b49bef104cd28d3177302ed2799ce7f12ef73ebaf94801351b233cd0c07ac381f060d4234d8c871054d1e05c596c
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	2	\\x7d82b714fdd19f10d54eb7747adf09b9c0398681d31e0189a8e1820e6b5f6b69b4e8a703267cf4366ec06fe4ef327f0a784af779ed1effec55a7316ee3fbc009	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x2795bbf6fcd032d4e2cbe68a7bcef88bc2d28f5739c752ca87cf266388b552260a7a676ea72c9ec6746d3ccb1029e5e1d76f84c18a6dd43276275481f9eccd271f040c1837ba615e41169df246a972aaa35890d7d8612ea0a7ba29949c5acde52ee827591d5cc40c4cebdc6919ae3606c7188b06bad1a150060b3091beeb69fe	\\xbfa8c14a91f0776b5e752c5954674c8914b3656e291a175d7fb4da619d9ad3f407f009f340e93656b2e68858a6faf5e46c93138be1df3f98eb6005f710987baf	\\x69a5b97250126c2e63460f3b4f5804a06ae04f3054c7fc8aeac31ed2be69fd906f652e6a8a3a786da5fd5f3be8ceb16f039dcccd7bb1cdcdb60834f7381c3921b4aba08b88e53c217501b511f09742edeb8e82095f02fc81875afa06c297ed1eb5fd67aa2321d7eac19142b8925518e7662dd9d46b97717b5e7a4796bd9b3b00
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	3	\\x6bc64c207f832da299e7d6e31844ee69d35cf3d68c1a7e0f69231fe2cb4b98ca0a1bd3f719b1b95beadea33569dd1a1a263bef934f368657b45de7d20612520e	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x042a34c9d7496bbe0297a482ff7af3df5f1c7e83550d19046782cf96d5bf5aa5d08cd7806bcd3a316e855630ba098681626f01775e649262f2ab1baedc82d25b02cc000f604ba249633f8a742dd8b905d0154b9807cda0123b9723125d69d3c73f159b94f307b7933a04b1637b52b2c9eaae67a60bb778325d1ef55aaf55f9f4	\\x540238412295f739475b59507b87a4e657d2c56c9b08ea2c3f13d4dfa95bd6a11631e76042a6a6bd8def6713fcd30e8afc7c49ae6fe40ee0aed53d179f63d50f	\\x5112157dd5755158c595cf028a25a500bc5781e082995c7367baa4ff5b9c76c2b8bf5a978dff630a7542164e4ac719c27e11b6fc489d90bdd052ee613cbc83b75cc29a002c65aff830d33e438a73fd69f5da526bb9e1bd1891ddb4b939aceef2d409f8a24a9d69189e5167d1dace7d1fd7e71f0634070632e319e5e2fc877af8
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	4	\\x66164d29bcb6069895afa7638d1777d6cc022a2a47c03bde70e7f38baface436ae597b3c2bc8ce5b99f2428bce48b3e84cebeb020ebaaa67b014f85bb4c41608	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x9ac4e11d79fae552e82825e8ea0e9fbce7faaeb938bbe3d1b66c3d91542ca60470724fa879de65a1b4c48935acc8918c0db848896bb5dd0cda112270c96f53f9bd5f44935dc30aa4306a9c97304122683da24a920ab4a6a099fa4def27b3feab66336017752cc8fe43a6c3a3c154a38c28a1dc6a62433bda4393c44c79891482	\\x6892d8dfa5a920372a94e1b36b787bfa8dd3b8d6e34039ec244075b7890851e7d8178169423de0ef1ae86d4d77c236631ba1710678c49c14b4a428dd98bac811	\\x0a712afb49a62c59ee5b7b920efaa896f8330a66e7821bceb3416af38b187eabc102546e604d7ebb1cc65a7e7652f29d4a835c1f3b2ec90b4ec530e090dfa472d12b544313efddc746c9c29538ef38b1d50cd9c82992bc4c9ea73e22f6431e1656764408737276b410be045cc8aad8cfd24dac031c49f9ea86e3df61d8216ed9
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	5	\\x6809113d1af97301b204b8520a16496725be986325e21f392217b135054cf1cf262673701c1156e00fc9dc662a7527122b8e2fd00f4d54465186087ddcf53b03	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x1d5d49c68c4f74fca61a63f00322d0458b240b9465b06c5d3476e28657b3bf163ab0b49659382c27efacbbc16276ce883d78d17044f6befd740c478d71cbbebe56ea0eb7048f4db29c13bd6168a8182279cedae6d64bf5f4d00be37d2171e68db49097aff9467b8dde4cb95b3f96a53b7e1c4192aad54a57f85b11c6037a0096	\\x7d00856886c6a6092536fe17e6d732945407b4df557aa0a18e0a1c00d4079c3df13bcfc1ba6e57d01a96f52160921d1f0fc45f7b2a17d7a4c4aa3d828d3f3ddb	\\x1d0db1264a73a6b3bb9ded7e9de29d711054102caa4fadac606381e2a6a694a2899465bcaed5e77d9797446b4e32b74c46879f227e1e93a4cc4e5d07e80486d9d34afdd9df409c4f66889d7d37fa8b3568e9a21528bcca51438767a2bcb9246ee155318efc2bc233735f8084d4126be16222fbfe8d543210449ccf9e6bc3dc63
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	6	\\xc7ddac59a955e47c5e432a9d8ba30e8329e4b3ad96e1e8c4d51e06e88f6e1975368c0e721a9bb46a93ed4b54198a6def3d4091b326890c02141c615ca06d3f0e	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x23f8133815fae967f61a55af61e7fe4bea6101416e46ecbca9f80616bc03a83c997e805c5bdd1f25c31a445672a321a4a1dd4cfd380697d8c9dfd6a6b8648e3bbcb66562da2bbca8502ffc0261902505a6da5209a6d4ca730f6d2f9961a68310861703a753137118b91948fbcdc4de763d26e77a2dcfaed33f9650628b71dac3	\\x2763c203900c52758255684bb845a2c60bce3b870b6d21a12bcefc4541855898b543305b0084d1111013721916fc5b826da1372efc83a0d2d9252325dc97d666	\\x5b338f7a5fd704e07e32e46066eb7462d02681f5fa4a64bc1d718ccb4e7b88700f178e7ff34eb1a79dbceee501a8b74f2576b4029fff961d59e49ee2420b8f1fffcbe91d463f76dba88f209a8df33916103b39cf7a5ca363596d5b15595d1cf8f733710339ebc47a8ea44bab4e0299f589c5b2e247a6c124e248dc7b545c3dff
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	7	\\x207fe2914584c6659efffe72f85bf96ed54c7eef4c0cf9d3b46cd2f1c3181b589b5b377541932109609c4e2252d2def3ba416b2b82948a66877594446edb710e	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x43c85904ef4af460320fbd705fa2710f2cc576529bae5c69242dd6757625fa419a68c0bef43c53b7d5c431fb3e3a83b533a7be8c7298e63367e032c8ce76a68d440c7e70a81119d22acb3094c5317ba2543ea3e47fa1aee4b7ddfdbdc41a97e37fab1a0fc906f1ff6fc1b750bf4b07fb3c8bf913e50e58728a76b752657151c9	\\xa8fe7527b157e81609c129b96b54dffd575b794a7e4958c8c348a4fbd361e041aa21c2f2bf6ba99f7829ff7e21c2d04f7eee42ffcd9f84f9dd987305e1958506	\\x2af1447e7cdf5ff187c08becd15c604d1379ad587745363afde55662921bdd511e51b9de53152969f7b3327605475ee19107935b72fd3c6b7c8971eae5db61ad3befa4ba7f0c573c3fa7d145f25a2e9927f9c8e446d0cee529628faf9d8e85af2db774e74ff4f480d022e901cb68f597234c12f63f683fa4b12ae0af2a4de790
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	8	\\xe32c9eef81eae62521bb1d2b4b1a320d612cb11b37544ebae5f9b821920f4dcf7592b084c0b17b5b32ebe2433dbaf7b6bdd786453c04e1b0aebf11fdf7b82d0b	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x1d68f79e1ee88ef91e58a2739e7a882fd53de9161fd0e92357d718e190afe899f9c95e9784947fb8b315bdc6760bb5188e480cdce4646d1c0f03d208678a6a46b3df6fbf5186764d344890d7f1dffa0ade50b45cc75f20943fa5c026947d19e8d733f59c60592efe6f0164eb4f0dc471284f6c30bc91b58ae80d1afa7a633c69	\\xaed41522ffd73127c24e9479df8784f2d6c19f40027c6ef058968f5291e0cead2c3e143b7471690a04e6f57b968bc80c39a3bb2c5910be669fe7eb5857c0b58d	\\x808fc1c681ac100acca3e5a65ad18e3bad2819ae638b3c11fb48fd15b67c46d7121acf7a66c5757fe3df3189f685f2c33391533b71da7ca17966812115b9e10322b870eafde1bfa2a5b5392fdeef4f9f3dcd6fc52bc2b6742eaaa89f3c62b26c1a079f737ea0394816f093115b2f96c9d46c0e47a3704fd451c4e13b7f9fabb3
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	9	\\x0331387d75dbc5e32d7da70a0a29ac7f5cb3f55ae3dc8a57a844ac4c49fe15ec87e3f5e98afe7b2119e9fd4dca9af84955923d299ecd4485298698b029d4580a	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\xbeef78a475320217a5f3a12fe4581588841d12deb6b84a251a2995416bf8c53e31e131721ad85d39dcfead629b7972282125e5b78dfada7d45d75380302717264911ab5ff60e3e1a999452e43316e66a4ef32d421c7eb5d3b51b2edf10cee7a83e370807b425fbbe8bba989997f549f3f68cea44c8885940ba10f617ac83c9e9	\\x7bed0e00bda432fc2c7b6085dd8fe31c53e1b0939a63be164c8e1ae8fce090e1f1fcdf5fa0d84ad4755177181dd708a4ac87ff866c42bdeb2a456fdf82c5a41f	\\x016275147ec8a98ebf175f45d8c2b6c7fae4d16bdb815c5e4c4a6791b5cf9ea40e0368267f59512d5fe192cd0709e051804523fd1876c8da40378d86bcc4775b63da9032675e90e46ebd5cdb65a4bedeceb898f1ce88567b63d3069718058ec1545c452510e1797adf033cc7b6bcf2e7c60f4a49825ef509833f9dcb7884e507
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	10	\\xff03196f40472567c952cc4c4050c169a5ce9d0ab3e8438133772f0b16532c1b90b0daa76605d22a97f98d185cc01143d062a35de4277d07df35c2ec7f29750d	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x57829bd6a9054546b12a32ad2a9d3c0d62316e86b3eaa48b9f2bba1d5d535d951f8e2acc71051de478b8691a48d1e2479fd2bd2309c4fd1c905320b9b9b797627dfc8447e0ce4309fcdc394b8ed9549631ddea30766394e111a506f91fa8e9717bd9e55706a8c54757db15c059e7c973261c8d472422bf4ab7fd2cf65349b9b2	\\xa35081ea5044f561eba2f9c33429fd4df70f691a4aa2e5fd17913bd711ea15bee1fbb60aabd915c5b7169350af59f33ee9e98127b7dbada9017a33a9720779e3	\\x7d1d38655a1510d50f394e7acf71df29697b7f95891d452967a5c1da72b4a53e0aab4fb2a354c855aa18641dc8af77f82aff5489023ca08fc4bd91979bd6a441f7090368f1bd981f1cd2cd21d9a2397d067ff7be2740bbb2983e5816897009650b379fb8e56d35c24355585f33f189699713b8b8aadb5baf694535296c095497
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	11	\\xab4ea64b6451942ec9892447be397f9e3b58a8da1b244bed4dc68b9c0bb35526311fbcd1fbc35384c83ed38b264379b7d475fe7e9188fdb23ddf37224240f805	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x1e1f672cc0895b47e30886694a53a0453493f40078cfbc55f039f59d6c42792f503e5f444927a77caaabb558a94733a5f3d60ba59d71c43fa9aea7cb028b0e2c2ea7c7dd99c71689778b6aa62a076e9a58f5aade3cac49a6d3747be4ed80997d848c605e9cacd814ed400206812085bb6d0dda4998450fbd51c98c168422fcc6	\\xd3d74ab8f6fbcaf3766e672da640ca0288921b4d0cb8cd8bad38f57c1636effb96e8dda78dc13dca95a0ad4ef5b48f9bb3a530c50792b12e914b556439cff36c	\\x538818b40e677597d919b4ae8fbcc32a8f79858b426491a220e59ea2fde583ea58129b01ea0bf64bde543578cd949a596c4e1f17537af13545963b87cfc4a9d5f0b90d31cc257186377f19e5150e9b07954130b21e5e231445c821a4daad58c9937832b65bde3a3a4523cc40c9bf0358eee2938fd888345b316d95d3b392ac11
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x2cf4d30dfb7baa579b75221eb0224b081dacf27652742d5226cb80b30d5321e89ff73c3d9c8d5a5129ec78502916a53ea4cf3fe861c27d1914f1f794062b9bcb	\\x2e0f08fd417a440aa2085131aaf7a904c05d62f58baf0216c54ea5ae0ab83908	\\x558c31f8fc24f0a54e2e017eecb2689fb489db9de7f3f293aee90adf9ef07daefd03f54b28f9944a7b8bebd5dc2f813d8880656bdc8993b279384734fd8ee25c
\\x1fc7235a82f2263f05c9a8a83743fce651af6131b093dd39aedd64136ce9de373cdabfff44c320d062bb77f6d85d574db51e40aa3b34519d60fc8beb1edaff55	\\x4cb64f48814bd9f6391e5ed7e10f4ff5823c78caf8f78dba873f2406dfe1725a	\\x3924f05ee39f80b9931568defb83d31fd2d6914c6bae8fc601b4308310c5a611a9a62b4361819194ae1d48a2f3132ef7997eb29d1497c342bb23727e003b06cb
\\xc9e95d4e23f33b223bb12a8cfbcdbb9a881e4dbc4e59d59c932f3e8ef985c8445087b578e458c65c00c36eec5f0805296e451013ed7218874ef9b5790903dda5	\\x85646598722b8e19449f52ad38934ff178e3d6c8287e92b939657c4debf3db35	\\x45a47603d1e11319e5bf42b3628f12a60eafbe97cd2f424b022259c8f329598423b482d17c8caa599caf092bc4f8df854697d58d8ddeb0c85bbd3f5f8d8b244c
\\x8b07aafa19aaa92cc78656ad3d28445b750ccf436fec0fe64621b8adaaaefe53de867b4cb34b500cba0fa98adb11a6d583fcef70a39d20f16f8de6237e7e5394	\\xf987c7e40d27690a6800865eb62c568bad54a938f6fd7cb372f80efcb864ac0c	\\xb256c74e7a7bcc765f3e511735d8bc1a4384e2cbc219dd9527e949af8bc84757a2c8ee22512e403996aa04d3ab69d8eb24cf0c84c14b9df87ef6f230c9226f8e
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x6a0f867f7162c696ae939cb2f0b16640eaa68a5e142100508a04854b441f3541	\\x75908ba3710be33a454fd132cc1d9e16f26b6b460dabd36bcb421f67db037286	\\x0b701955e64c1ef0b888e0afaf5d08d2af251c010100e6014eb483ac34e713b9d68835d68744e738ec30bbf8c2c2e033bc7d018c755ea08b3b828c2f9315d50f	\\xb060ec00caf1a798dfe4f070286e9c25b65bc6d31d5726eb9892ad5213c1b9ba95a1d353674ebf732ccd186012f9afe55143f3475d3fad5d2c925d235dd2a999	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	payto://x-taler-bank/localhost/testuser-cJvNv0WN	0	1000000	1610623501000000	1828956305000000
\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	payto://x-taler-bank/localhost/testuser-jTzPUzRz	0	1000000	1610623508000000	1828956314000000
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
1	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	2	10	0	payto://x-taler-bank/localhost/testuser-cJvNv0WN	exchange-account-1	1608204301000000
2	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	4	18	0	payto://x-taler-bank/localhost/testuser-jTzPUzRz	exchange-account-1	1608204308000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x31f08a14931b992feca0a47c46299dcdd132845835b02c0f7e37f890953860c2f971d9fcff7c8e084294a6cc0c26c68574cb55abe2dd1476463983a409bd8e98	\\x12da20e3d09cbcb21cafc61fbe48352365d33ea8e2824027c1a975923405a799d9ecab3ac4ceee62d18dfa6271f87bc79f9abd68b26615a4e33b7659b7bbf2f5	\\x18dc46e58ced65c645090a6e9462cdbbe8b1fae4d286d733644a779afe48d6f16909f0d22b1c2a0da512c737742294a5b146e84de938582f40c17da3eaf57d1c43e5e41291c0d9b78d1316adf3533ae7fd3af38a35ab3b25fcbf262134657439265ebd1a5296e7b6a35db162184984ae28f91551a068bc4934a548c100e55212	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x7f21dc1682c3a27ae15964124962c8e5075310fdc1ed28615613a298d3bc748a0c6a6efbddb27f7d8b864720b8b8edea88558a431cef6d474d1f00ad14a4b200	1608204303000000	8	5000000
2	\\xd3456148404f1090f16064a4748f0f8e5d75c15583650e190023c83a22e2cfad6b5a8a0f98052b3580c9a7c582fdff6baffba2b4a2b7d967276bf9f6e6f52f96	\\xa404de1056071832f505c36292216558221f2780967df3fb21d5350e6acab283b1dbf41b846089d91c5217508a4ab30f182459702afdaaecfb97900cf0c58935	\\x08bf9feb69b0cd1035e18f32da1c2f3cad19a2f5e2d86e34e6aa7c81ae823aee3adf9c6eea93a94569d982213290fdf60e3553d01d7f0621631f9ad4442a1b22e2c67e1f99c86a44c5e66e58100093e20825ac241cc10791d93bbb61f22590fac6178cde3e83afa3a8e3ce3935d1561f0cb1e6d445749adf9c652c235073ded2	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x8ef8b08d21f79097054e0782ba7e81de9baf76c0b147cda6f059f72aeb3fa646226567c88438b2acc4e936dfdffecbc46cbd4248b416eaca03b083409c39a500	1608204303000000	1	2000000
3	\\xc3bba50b436f88da57bdfba2e9e72dbde4635b1a8e0f3e6a4121557778ba8d605d4e994a463499e4a6f9a7052b232e764da35174a5f140d288d323e19dee6419	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x425dff034ebc51844389af2e3638970e5de9300f2549761af2f2a169aa06b0d2acf11230c98f27e60f49080f9c97ded883a2338a08a919b919556bfa616c28a4c63cecb5e7cecacd36fbe29238e68ce8a5061a9d09cd2ff15cef90a3817a9b9a6155ba5ce73bc9f38b1c8d251d7314a03908c85153efeac623fbfa9cbca58b0b	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x9e10b171efaaa355585fee1d3d429e9d615cc1997148b029f4ef1c2ad994c1d5ac63276fc9f4d27b243c49d4ce5d4f672cbedb272d8bb2ea44225101046d3707	1608204304000000	0	11000000
4	\\xe375889bf52839ed72e4c789d8d1d6aa2e42d0abfc22f133c691c773bb3a91c42415a746a765f2dfcedc47253570b5f239143bb773723c5e852ea081dcbdd693	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x4bde53004e85973dbed795441839c55db3c830523b8fe6951c0b5a6bbcbdccff45e140cc9dfa315119db1ce8810aa7a5e2e573c5b2def2a9e71f3e5086e7123a8547ed9b622ea10a3579b7b822b9ab5d8726414f9d4b42ebbdc7bdfe947b667aa8e06a9dc15bd4bea027fc3a36657cf2cd1b384f748749b34d6eac5bc848baf7	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x01b63f738d90b979331bd0fde768472a25a2e1f30ad29964ba4beec17d3661015fbff977a633091c9cd787d6ebe42959364dc8ef8df51d1bbbbcf1bd1b963f0b	1608204304000000	0	11000000
5	\\xe0c2974395ece8c0a4ae541b6522555062085994be820c63b116ce96277f2671beb5fb2ecb3b6233af19cd9aa367d55dc0eb4b02ed8a2ae7704174407ae782a8	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x44404fac325c7a006340b31c153dd0f736437bebc789511430466be4830cfcdb8f22c46b3753a59b85c3aaddd6a22d7808b70801422ad4127657f92cfa5b1a55be1b3bc8a3ac75c89c6f792ef3a8bba212b93a6e1dd09daf8905c1799b01386cf82fb37297e12eda685e6c35594092b38b99471877115aa8300bc4ee7f16f370	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\xa1c445b53ffe2f09698a14be16a2b2e7dd9fdca239ba03ebb4d19f018ca67ab630713f27e50efc0cfcd59ddfd64e5d8678b939b40a77092bfe1d21978624e809	1608204304000000	0	11000000
6	\\x3bb723cef39c704c35f1d4fda455f5baa9bf22d072af41744943e73e3e3695b9d93d0d4fa6478468b9a27e5e9479e8effdc4d2f93a5c88b260adf3bd1130c66c	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x5e1bf2705e7da6e48162d94bd7c569cb3168665d5c3ef7598286cefabe594febfa56bcce6bc84963ffebcd5afd41e3704fef9116cc937ed7a257dfda9fbebcd7937ce3d7f428deb5c5bf438a52325349959bf6ff33e63a5e81ffce74d94df2268481c74320da3d80d9c6958d25eae6fcdb452878af53b88c9080977c608b3439	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x09cb0a1087026dd4b2669607a1305bf1625cb9f9f6ddc4a1574c66c8790684948a8317007edbb70e5f8ae7b801e1f66b1343b2a2711458ed31c52182264b5800	1608204305000000	0	11000000
7	\\x9ac376a9149a0150a03b61c3b2108a2181439e5d0c2b0b10151513efc1c12e3eeb573c7862aaf7cbde238c5cd3cb31bbf0fd730b77aaf285c50833127a002efe	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x9e1d50b545ce00ceb2cfa846f5c0e9ae37f752da96b83edc2676c0188e6faf891f37f5d2c7ab048926a431913ff92587c5f94a06d7be721421108ad91b212adef43c4a7f0fb3881db23bf1b6e0db614b90debb8d736d1c5dcfcf1cba749baa87d0995ced5a57e764da2355cd2fc010af1826afaa1d793d5b4e3a71e7b6cb7cd8	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x8a1cbddfea2c609cc43197444e61c7de0c62d18296831f3f9d2660af2afb4744a68117ee1a0ac146f67084380c8195e4d231bdf854791574b512367ddeb4e501	1608204305000000	0	11000000
8	\\xc2431339237456741eb8e130c89fe74041b7497d53faa48379699a45ea03ec2dbaf650dc76d91965d6eff697c343d14d4a91ba5d1583d15f9147215a69d348c1	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x9099d06bdc7ce5abfd21f3c8c5afd1baf384efad01bba54657f3ffbbd15fa3ab26b8b35b909f29f29af42d39542a13fa35274ddb5b8e6fe4de37c7d5c65c13c3d98400470fc5d36a632f24c99b9f57e3f98d5bf406c433675a4766cb5d4fe7a2aedbb24eddb64eb2ed403b9d51efece48e0ec97f0b240e960ec05681232a0a42	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x1c013fd135268955c6c0059b949a2efe772032cc13327a26759a52e8887935d2c8fabb39dd20846cd60520ab1f46bf78c81cdd4868edfd989f69d6d19bb2c004	1608204305000000	0	11000000
9	\\x903314397e86a05d86905aca9650c6b414bf95f0e9256ae85e2dd59fc45a298fa8d43ca65307c4eb0d8704847d650e5e5b5a891d99e8c48e143e34ee47909ff2	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x5eda65d7d3551d7aa11edcd3bdb5f9ecc3197106acf15f1ff85d095b1fdeb1088d6edffa41ebf66a05012fa5b6c3f56874598647990b42e4c2e654d0fc1da704792cd07164c52e9ac1d8ddcbfa6ae4605a83aecccfd7d21c18e18050972cc5d2b7ecdec2fd6481a097e949d5f61881fedfc68d6dd785b22a1f8ea298104a1392	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x98ba2d24ff41c5506894895dddce6ef497b7b932f858e7cb797363630d3f2e6cedf6a04e0a625c8a857d4066cc45805baf0955307122deebd95a39be40940c01	1608204305000000	0	11000000
10	\\x3a4173aad0c3a26ff37a0f932513a2c74e050a56779f0864e9bb4686888b750c4bc362bdd7fa6c982f4ad1b820f254e2b9ad60006c2de638201fc133ffb671d5	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x49f6af06e6e1df4efa39aacdc9cb1e3be3acbb792d2364b350689de3947091ed6318910c5496e781e926f208ce863d42ad228c6373a7823c6e6d604451dc8f057e95473af650514f65ec02a9cc7e0f48ed3dfcea04cc95aa56a902fdb2ac94a1b8225128f317e6fc6711fcabab24bbb194da9fc92c34b46ed502c8651305bfd8	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\x4514a5d8b95384f72e6775d8ab48b4fa196e0b308be44df1255793e98e6540f2f512ddd262054212eae95ed9a1816dfe875f06c9d1e5c2f4921f541cb8137b09	1608204305000000	0	11000000
11	\\x64ad5dbac44ceb882e3cecb4f476dbf2bac9c9b47979ba37e878815d83993b3110f08ad698613950f7bb11d4359d6b5bab685aaa167655c1e002132928863ad5	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x77a2f0c150cabf76d16936983380425fac5fb4073dd9bd95321a59e21be03863c442e0f538f7e7bc8b8ce27aa2093ab2d34a142d82b83a8a40316fd70ef8dc0961c34b7cf5924f3e3d779dcd3949d34eb1e026cdc55b4b2eec597261c9cedd1e9e42b5e43b8a44f39176b199668d808f5d9026ba475ae53c017aa0b3d684034c	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\xdfd3e26ec8ded1d3fc37dcbdb603c0ffc92040185211f22938c1e07551fbd1ae502e79904c18b94521e7ee49e6697b3f7a01a458107e5151ca70383ec989b903	1608204305000000	0	2000000
12	\\xea08c25543f82aeba44f3104a97624f8a37a9b531105316bf41908e3eb9be161ba6472956d2003b57b58ad59688f3148d8f9c077eaac64b3f81e51d4e7033509	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x3ba299dceeaa54c0225f0316f520e1c847df8a0b4b03d88c6b200764122f49fa051d628b631224103ab0d337317d3a246b63cf19d9412bbae63e1f50883a5584235b599045ce831b1a27dbbbf44b62ffc27033aaea739866ad4343ddafbbda69e85fca653a74632b20b15044bfe3ba191bedc22efd1f0f4d608362426af4fd34	\\xc63460eadea1f77505940f1af833b26819a6efa3fbdd5c8107e122460b7a6592	\\xbd5084ec136f314ef3089d2c87b7aeccb6165098a674152509bf3b832da9e0e5719c2386b1e309f5fc8c67f0fe7533f292b91e670f8f78fb2adbff40e9b7d50c	1608204305000000	0	2000000
13	\\x98d499687b990cdb68c84f1ec54224a9795df57dcdaf66556788c882afef668f34d7af6a5b618bff73341f6c4df4e48e233082601a57ce09a0e6d970c29506a9	\\x4c39b0b882c6fd96f9cf652aec01fdab934fd5726b36b5de4af3f8f3a8dba253d2f96d74f48f9c96e1956d58df8157aadc0e9600531c172d03a4532e51e2f01d	\\x4c8d54887b8be6ed1725ac7dcd44c5ae060c396146ff63851176de940bacf350274cd25b855ddb34ea9b625f725ae6185e18712f5e6fe996a41585af06e1abcc3cd652a89c25c069804a9afe636b02e2e11a7ff2c7b05534da38494d9e419513db40e184e0381b5b77b98283ae9adbfbb1fce03368e80d9f17cc9e66bdfb0366	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x83c35e6997f3c99303c9bbbf80e7136e251abf073a2a7c960fa4be9628db7624c899678e5dd89b7c473e29f511801e0be48812e9dd9736c423d362d4e59ab40e	1608204314000000	10	1000000
14	\\xe0135c4839e6d3ed371493ab034e2788afbe70bc9d004ac34e0de3dd35a6b5fc458e826c05ac44dd87cc78a4af3e7bbfca818b53e06f34895cec49558fdb2437	\\xff940722355169ea675239a1ab21821946d78914ff981be7339da8a6606911e9b721e12642afc9970e0dc23cb4d944d6cec0bc71c31fd2fd3b68822245caaddd	\\x05fd29ea0d52ccff837464016fd212a406708d8c859e14684458b0ac1a2c3ed5e2d5b40c486371e19b58b792c8b9b06ce5df894f471a4e5d5a64166303810902c9a946ec3ad0f67e93cb2b8b039fbdbe15c5380c68366454ad587ff21fd8846fcb0202a90ad0c1130677e217efbabb59fadaeacf56a5101d76b7209b63aba17d	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\xc989f606004a83024cf97012ccfab8625169e9ecabb19ccaeda8c055736950d49aaec87827368f0438e8ffe2990febd0ad60b68b0aaea30b0c0c3bd0a5c3520a	1608204314000000	5	1000000
15	\\xd4a4a33f0427deb1f27faba8b4c2b9c8aa7cd2fa71efaa98cc64825e8cc1e5cdd544b946b71aa9c604373f4c7b6a04bc5a69c5db68a94f083be838aa4eb0ee38	\\x8dd87293e8eace6275e94a099101730076057205db2e10ec6cb93f71dfd46096454a90d7685ec1c0205fdef75049c38d0f922c0fbec26b32efe38fb24c43e51e	\\x62c4ecb803f11dbfae7ccdcad4b84680a4e64985de0b93f1b9921dcdc44ccc3e7dce6fc96a59ea81e4cae76f50aeb32a578b8cf5ab9ad39ff37ea87c5259b5cc06633a375b30b16905abe3a18b7cd29cc70896ced6efab983776559f2fb39f60829035faea9531bfc6172d9b45b9bee45790e460a3f0590a86379e1503fc0e29	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x66b84cd7852f100b74b1419ee778b50b70048bb50caabd86c74c6b1bc21a3536e77ff9c7dfeb7d164f4dec32f988a7d0b46282a047b10a5f6d3167c556b7cf04	1608204314000000	2	3000000
16	\\x0ae3dcb3b681cd664c45c5737d0545bd9fd06b69c9b38e0ee77289221d71e7e1be05e5c79d0543027040d4c19bf8ec2ebf97b3f8c64889e24cc927fb2fbe73b0	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x91a8b1e426732bba4c3829586324423802d5ffe6a921b9aaeaa00659c36be25282a947cce40d8eff81f18528348c6000ca56870ab57196e70df9fbc6390be7607a421769534412537f6ab621a9a44a9787e1b62b58083234894fe991dd06b0a1fb34a785971cd265615811e8dc17920088835a55d9802d2a17901db4d8456ddd	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x92b371ffff5d7e74101438664303f70a23e80a2feff409e3ee23f0ae61b0b0507bf8ab3cde577c92e098bfc0fa5722b235b674bb35d446482270e7aa9035df0c	1608204314000000	0	11000000
17	\\xf42447912a591d45dfd183a6a943cb8ede43d35cf522cbbbfad1848f2b5376b7477a00a2b0e25824db79f4137a7601fa18a413ea7e7702b5a20c2d4a4bd22f4f	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x7aa0e0bdb3bd94c744f46ae2d291ef1806a88e246bcd54459bc48627f1472a463b27efa111d49cab083bc9c4f37f4dc6c9867ac68b533e829ad706530d3816de92610b94439962c47d30d460dda217b8d9b578e62e6081b4b3b0aa046ea0347a37551a4b04a1fd16ab1e0534bc86fea3bd0c5ed449535f7a1717fa23f56647c9	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x7205121110e26c9650b9ba765fb621ec0739d05fe2c2469a639553dc5a433f600a40dd99c211a9694d723182cbb42198559219513f00201a69e87c99ff8ada06	1608204314000000	0	11000000
18	\\x316f942c78f0e1381b0d7263ae6e310dd3849c3e9f899e734749f9b6ce7595ba80c609487f3d4c2e3dfeae7716800ea8cda368e71de7b769078a187e8647aa84	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x553cd92ca84b2e16cec35840a150b2910a4bede2632a96f301660a820dee2433594422fc7ef351b703a5d4d862830be4326660a50e1888b4bc502f0bf040f7597d3fbd2dc2bd3c2a9d5488fd9f781417b47c97b9eb94f11d54fa95e211443b407fe107712c3c70ad09bdb8b5bd2e48b6e9880ea85561d1d9c7731074899ab305	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x25cdc4b05be452d22e10d0e43f9563dcb3aa30d81c03620d90a53c8ae9f052f68773ebde11bede65a87725894bb76ab78e8c39bfa4ec0916f014a7a212778c03	1608204314000000	0	11000000
19	\\xe2285432ec4777789aaa4eef5408793a120db467cdc15ebdab659d68b1a6d13b3d85f6d10278ec311012c38c9aa6f0ac7246cb616d23c7d9d1c5a797f8ab7a93	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x881c335a239fdecd6e56c4a51be155578414a7392bd13d41e19406abc09ddef4f701af52fadde65ec49478d7e7917d48c757e6d8c92e342c3d6abf9cba1b7b1c8f46e28eb3deee099ed46d404462f3144f26ee28e2a7047ebe79097859558ff534453ad0035cbb995b906e34e89e8c9b0ebcffad8cea6e47d393cf98bffd8533	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x7a3279782f2c6597ca01ff885006c94be720333c050cafa84479cad07a83310d883b73afb5876868dee5c8b336e4695113eca0a12fb639685f1120ff8d600a0f	1608204314000000	0	11000000
20	\\xa37d9ea746865dc90385ebd72c78c654d26927fdbef13b2d0345ecd93b47dc6fcd8987514e8b4891b1e7db2685026fd247b7a8440cdf61b101deaf18bf935f40	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x9ddc1d892633f6691fb9bc7c5d2c7acfa7e5741e8a15db7b4cc5c840378fdc88994cab2f3d6ed6f1dc22a2ae7d2aaa5f7b305b3c8dd69253497ed0d3d5636431ffe515ca5fac39b1fcaa10e0623ac34c045641b076cf4b00c3352a5cbc04f43ca88e2759c0c818761124b010768676609902a555da454c7bedd7d5f67c40e9b0	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\xf7c524bec92524f43e50cad3eab0e4fc12abac321b760a7cc8fb19536c308554da95f53379c7089a702de6ddb733b0cd3bc9ca45f30b8f74d0729a68e5cfe202	1608204314000000	0	11000000
21	\\xedc337531a0b252d0d96dff64abd852d6f7e34f9cad9fa9feba46bede6007f93540873d31019bbcd1ab22291334edc0543711527a20349bf613489eb0670d040	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x9ca3963abf3565cc05cea34e496ca4fe982627d203d3fcdf1d856b04692b3cec448915eba783ef406677b283f2728b0d27a91c1f3b7f308ba8e0437761dbb4eb2f7410e88424de6dd43561dc6d9c1368bfdf2d159b10f3659d2039c3d4a632513b780a859d7f0010f447c1f0094720b51d95a4a9fc157838bfe106c477b6d2cd	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x0363deff1ef24794458cda303cc4ed59430b073d984d434137ddac0bb920828d6629d4c52f590aabd1894f4cb15dc934e62b8a343bedbf262e0f96521c412806	1608204314000000	0	11000000
22	\\x785818b3e8a24a3166fd16cb5a7085a35ee8221725e73a9a6de40e6f104a1fc7f0a696c084b5e1a83a51ec74d7e7f95a61dbca469566da26b1920c5fc326242d	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x1e0ad12c775b6d2018ecf00a707ff7b1238b7bab4a81edb30dc6995c6f8d4d971143734b216a204164c6888562c719f5563a01cd921741f6951a832d8981288ea9130ca8ab03dcdb27f855dcad9f9f0e996b7f9518162b2f38a4b97628fbfe1c387751e7f3476347f40f9dd2c89bb3d6624013d25e80449ffd8e5ac26f347e1d	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x32ce3fb8fc4e4b1aaea034a3161302ab500a1ad3a7cd24dfcce2b78198c4c018a3095f9bc7f13ff63fb4e2e50936705dd078838be7780aba080ce112ef807602	1608204314000000	0	11000000
23	\\x619edebee7b03b6ab9e5f1bbf77f350ae77b8e932bf94b01e684658a891314700f1a5fe453eba215ab750f6fe0ae174523501d5d7d0c910aa127dec26e195c0c	\\xa20e2f36fbd13a05b832ae07ba7da842fd60ece508db82680d9a5a700d0d12def7bdc70e5b4a1b94b90ef934529758c9c3856603d77d8110107aeac499fd9e2d	\\x19108b7e6b572308987a68fb24639031537b090e337dacd713f3f2fb408ea8cad9bcec967590bb6c07151113f4f9fb5323e1395988377b98870a6308ce0a2c8e2c9641e5621909c9de1b860e7d31f3a118fd562c4a388969bef37404984dbcaa3d90ba5a4492db8c55b62619eab420c32133de70bfd9b718c69b1f221136f041	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\xf84906b3df75de51e58dd0f942695818b71f3d42e74e3a651b96e1f595a209541d9cb0f83dfaf665ce0957880a2353b3283768bd5b4012d88705830fea198e02	1608204314000000	0	11000000
24	\\x30da88cb6d29c375af01360760bcf723699e4ed8f8e3d49c823ad3a5e6e3039c11dc580b75df5aa353c6e9740ab8e42d9570fa49e0182229ae7dfdd8222649f5	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x500c913ce66fe5e0765d8531cf03f9e58119ef64e00d6f0f84996188b2895e933a2c8e6f2acfab61789c0a8c76d77d7e302932a58a0a79cd66374bced9c8a304ca9aa841cd0d266815de0dd3d3a29beb397b51faaf9839ce2b2508d4952bf9af192d0a646a379c9860d44bac2b66fe3007ce24c09eed8c13a0bebe459d75c4a3	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x61fef6ae74fce8696336258d0d35ddbb38c00e172924e64976bfd38c79c84c6f653df6374b11c11d2c49f41c20260367949e46a039d185bf6f74ed03c6cfa208	1608204314000000	0	2000000
25	\\xf078847ab93bae2613285cb24155ba0e70d78bf7cda4a3ddd596d93e9a9d2caa688b4f280cb7aa17f7bd770000795215e0eabce1d3416a6f816f26c8b4d164a9	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\x026fad6efd6d4e6c217791a4515e65d5302e0ef0c2fe540fac2e02821d9802416982180e5b585ddf65aae8e11dca94567f9a9d4c5ea05836f44282c33eef8ec306afe529f996d232b3556f95661b7b9bd90c558d04e456920825b05c4fbc4db70c20cf8327f377326c600fc31365051650d4874c6fc65bf42dd31204bf77ae60	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\xbe2c15d3bb517fc743f03dcc3e4812c84efdad0fe5b193ce3926be5e90bac7dd55cdd00f626cd66d3ea47953cb1d5c1a383400f124c508ffc3cf2c9d51792a0e	1608204314000000	0	2000000
26	\\xc15b8a6914712ab4d999014ce20ad948baa0a5f70865f4215c631f7b7089558035d9961243564003a6c8f0399bc34b717d451eaf6adf2c774f78d58e2262d9a9	\\x203f1cf471f9a65d045fa44c14ecd5eb0b31784c17a4a5e713929a6cba532e3dd9d092873179bb61e971b0ed307cb2add22766f4c9398971cf0c4026ab999693	\\xcad6278698afaf7c78003a5d5aaa0b931096f228422500706601f95103f10a56ee8c27308162e3029b7c5c65659cb62946a7c6bd9bbd3e845164736dbfe87dc452eb6b73cd5b8b5778c43e79e9d261646f8597260f51eca40095c8d65580aeb8cd89bffaf71d5a01fe262c772ae3efc6588808924bb7da3baf4c33eb69f40d42	\\xaf912bf51deee6bd997cb931e409fb03a3971c53338767adb732f72e08240980	\\x7d196fcb49a9a83061400c20fdfd4aced31f987d27906e2305421944d31817c5cce26377fee1719717f25601c7002de9ce3465c2c365ecf15151981bff1af20e	1608204314000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xc565203aef860e9984d9ef8e128bb7ac5fdb1756b69cc062f499ece50a8a55c68482cfbc7ea2081cc687faedef5a51862385d3cfcc8d5cd41d4e50ad0838a30b	t	1608204296000000
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
x-taler-bank	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xba6abf4652c3c5a9aa6c8997037d7d250d3f5b050f88491f5716a31687f18e2b697013f6c64ceb3f096b49e9928184ad8c82d0764d83ced50eb76fe58ffa5d05
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
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denom_pub_hash, auditor_pub);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_pub_fkey FOREIGN KEY (auditor_pub) REFERENCES public.auditors(auditor_pub) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


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

