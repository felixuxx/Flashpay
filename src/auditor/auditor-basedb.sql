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
    rrc_serial bigint NOT NULL,
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
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    reserve_uuid bigint NOT NULL,
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
exchange-0001	2021-01-07 22:48:07.280865+01	grothoff	{}	{}
exchange-0002	2021-01-07 22:48:07.393899+01	grothoff	{}	{}
merchant-0001	2021-01-07 22:48:07.576843+01	grothoff	{}	{}
auditor-0001	2021-01-07 22:48:07.716747+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-07 22:48:15.426568+01	f	0ed240cd-f534-4892-b9f0-638eecdd003a	11	1
2	TESTKUDOS:10	69G0BVNQMDAYEYPDN57Z3EV5SAEBEEE3431E63NDVEGX7310588G	2021-01-07 22:48:29.812115+01	f	fd711d00-5ccd-4c21-9469-2453640def5f	2	11
3	TESTKUDOS:100	Joining bonus	2021-01-07 22:48:32.92431+01	f	85135799-4738-4338-865d-4103afc5fb66	12	1
4	TESTKUDOS:18	0N9KCQBQ7BGQHJHWHDCT5FSA6JJJYA840EW6MM6CTAJB6HZEVWFG	2021-01-07 22:48:33.667+01	f	0f09ebea-2712-42ac-bb8c-1114e70f5d56	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
94410621-0e81-4e8c-8140-fcf172cc19a8	TESTKUDOS:10	t	t	f	69G0BVNQMDAYEYPDN57Z3EV5SAEBEEE3431E63NDVEGX7310588G	2	11
73f677f9-16f5-4c11-84df-fb1dc1dc91b6	TESTKUDOS:18	t	t	f	0N9KCQBQ7BGQHJHWHDCT5FSA6JJJYA840EW6MM6CTAJB6HZEVWFG	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_pub, denom_pub_hash, auditor_sig) FROM stdin;
1	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4f74dbdd8370937e54a0feb69a91a28151b1b05d94a81b4008f625d71b34d63f8c9a5f907332c8381e69d504f2ecedfd83b8ec505d130ce95c90a943ee819dc5	\\x4b4db35316c04e151e7f63baf9ff706b93096ec017dfc6e42ac8e808f0b23ef919dd2cc56c3159efc4f360293e4daed897007096c929c8a86c508fdaba060001
2	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa77d38202ec21b65e2690152dd3047ecb216802650a4a60a287e44c3890ee0464ebacb132f9ac310088f5a7cbaef8a08021b003e61953c54f1e620977ad81467	\\xaab66bbaf5dafb5d31729bd0dd9cec16f3dda65bf600262b4f9d339216ea4acfd9947524918d1b445bb875976957f7e0c9af38e9fb74b5818e585349c907e508
3	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc3401fe695c51032d91b1c08816b270ed13ade219bb96dbda2093936a2d64da7604e458235896263a142bac61a1de2ab0479f58788dd834dfd9e5fb29d6f10aa	\\x3726a864eaa2f11c12636ebf3ba8e5244b1f0874d1651cd76a306c965d668a80302201add2dc3ebe1db9ffbb89887c33d58e1e7efa0086a04b62d3187167cb0e
4	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x31c37c0000281a832cac33e3a1cc975fb714d0237241ae8bb9a228276948d455beeca6acd886d6e296973f7372892614d783c1bf84f5da0f1ece838d52dd2570	\\xe9cd0b48996a5aaf8d6d696c02778c359140dd67f4f64090e6d41f6502a9eb1522fa36d26b231a232d191c3e0fe3a0e66b5fa298ac4467f482c7e41a1b9b0700
5	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x904b247f080f8bd4afe955d55d92da5387d166d815026509da421f9c4e0b459114008ab0f1e7c8976476d6f972d35493eb0d3375354258dd63cf95077c2772f3	\\x332ecfd00e3fcafa82aafbcab2fa218984d5c8f22141d34f0c420f2adfb526f25adc86593fc42386a66b2049736ddb68ca0774a2ddafdc9fcbe1a0515cbec40d
6	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa8b867cb6c44aa4423e9c3609ba66a3c674e9829d950757e10f0986d00cebc002c5a303f736f2f5b693185121e09b15cb853f4a0b556329a9c0db5200d939a1c	\\x7f9f96d273302d4d72292bd91a6b3593da4270dbd996132a43cd1a36343036103007f59b6eb720425c9c0efefe8df43564d0d9f5a934ecdec57e5311769c7c0f
7	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xaa871cbd41626140a7331ce5db6fe0b8b79c8164396da1556f88f2f75a7f4e4d507a863d80a144d4c9592b3282b976613933d8cea8a5476be738c42741807209	\\xd831c392ac019e2e76ad3b2cf835b9f814bfebb58a202060e68abec07e227e11fa2e35d0fb962c2cefc414aef2b2c5a2cc965b3c1a3360e8be3f5a6569ff8104
8	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xced06b5a40945c9f13cff3498726d20313b08a32699e366d29647b3a0c8fb3125818af0d8e7d8cab250e420b597f2c68a8243258596ce33c53746ac1c5061700	\\xfb5cf6cd4b8abaea4d3b01212f54e9eb0fb543bd8d32f3405cfe7c0cf17519d1fb67acf28f06fe6fadd8c183541635215c939e99529d005c1c289f2cbc64bf07
9	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb320c1325196910de2ab075ffdc4c6946dec875ba0c56845754f381a5112eaea7d00f79588a102ef938a5081cc0149c46b7d33ed3b2a6e6d57cca95c1a7bd795	\\x3362ddba21dfbc702d019234db3fdb4e1e2a4aa04deaddf26dd220d641ecad076b4dc52417ddfa3473b3015d9bcc58b6c71a9a36a3f73a9231b5de7ba0b52209
10	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2b83f5fc39a94a44b53faced9127314722f608c5812fd3426ba9ba1b08ef545025e469d50c09d460c41bbfc7e07c395e131e50ee4ac3a12de37e6a4ccb6e0b87	\\x8db95cd79e5e7fecdcb77d1914930922715f8774ae1f90d25198899d7989f4fb56d7154f6b57f94fa8ac3828a3b9d1d3897b82a980e98d6215b3c9155321d909
11	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6c78460d910f2398cc86ad0c33a5a39435f39c1405c1b909a5a915eef9b08219c2118315aa83f720cf61812f82d7e0fd271898f0e3db855b5aaaa21f379a3da6	\\x134fa260555f41fc3efb0b9be263d04aa4221499d7ccc40eb8d4867281adf4fa65df67eff69e6b914f4e158eee83b0e67bc7ba233a5aac0be2cea206745e6100
12	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x387e5db3268f3ac0e4624d946427a650195b07c36c839436175022fb98c1bfa4a3476720280f460e3bfabd3b0e5477e5c0dfb23b5eedb479c1d15d85e8826575	\\x4bd39b75e42cbb6d0d4b35a2306c42215dcd4d8f7fca64c18a697bc257dd3670e79a23fec722f6b33dd79922e9ecee72e89b89aea83e9359faa3780e29575308
13	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3c245ecb0b12a61c4bdf826d89a7b61ceae7346f678786b821db3f30458fb37afc630e5af01830a0f78ecb2cb547becfeb62b826bcea47a062e7222e0a0c1c37	\\x7b6fc4163681b0ff71dc4e618649d00e7e5358ed4b199a00c7104fd25185e39dfaa5b1c6de5a09bbe1f2502fa9e63ada178f015220604f476932ba1dea387e0d
14	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8fcaa4b1f1ce9e52eb4aeb8012a061bd06faba20e7783a54aa9715fed8e74b17427c6a0ad99a46cf1f86b12a508ea1c022937d116b3a0638e799fcd50e455983	\\x2b01b509265350990a4ec0b8f7c2d921af66d2be2ecda9a9e6fbd01962c1deaee2b00988ed46a2f0eb3c4ded9740d525065ab368b9e16b9798c1c0397c24590d
15	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc23884124cfce2b77a4007d673ba76dc19d8b1997483086c67afac6d15883f5fe046b059e27eba063f357565dadd985a43f7dff2922c053395a1abaf16e372cb	\\x5110b9b76c7e5e82450661c7259a89069cf218b7adfbc95f740c010ee489ef1f9d0487dd762ebbfd560c959c8d1b368688480b912bb4d3b55b0ee0408e58f80e
16	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x418e1208c0c667268e434043819d4fcae95c7901f567260531feb4c9f5d61fb1890d16d65f14bdfd09b925c05f04d910bc8e5a3e9f22ac23af813d16bb5b1a53	\\xcab499871c152f6457d3801b17bbc7019cadcc711a7a3607399922ba28bda8d2f3888d719660636a0a97df1a71b561d6d1eee32ce19a03e08b17edf7109ecd05
17	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe9b3251bba138844e60e12955e929c97b10b5297974ec5130364a637b7b67c93990dc5363769af123f923233be711db61271cbd3723f62208bfc7c0e8209d752	\\xe3dfe86aef267b6659911306acd6898c04b33f2083354c5bb56cbb6d34a871a918f0de3a724fe936f4eeef486b58e34132b25872831e379c25c6edea17c2050b
18	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5f8896d3e0d7fbc85867f68524e674951220db22eb93148b84c4ad94f5a9cb278707dffb57c8f751abd631cc55b3c4c3dd460095a4ea9bbb1c018c829379aaf2	\\x8e70c391339e390b74e078d39d8b522dc9e72ddac409027f5ddc2561f6ee1f891219267f6e8a5ae802afcbc93b31eabf63e26dcddf2db7c8eea38165b74a3306
19	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb540fb2f14e0a5db9645cc655d70cc72bbb445578ec93a25e9b2fd03050497b8997ce4ec5e429e631ead8b7dff00d6eba10e9a25a06eaf8d4e1c5b8dea302c57	\\x75078174b8219e2e96035b032b2d34ac6c897c71e47bd5006eb1bbc3505fe22421d3fcd0ae66c42da93a08f09f9738faec4141996a0ae05ce387104624bad001
20	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x51aebe3f28942e3d61980d2be678f77ff6fedc3aad43361814cac7a3d10606ef8e30d9db79146355f8285f18fea1a237be671cd4f7136d359b1006f347dbac71	\\x389a8a0efe89a3b2338106a449c406cab069efb1fba728686fd31f7dba0f35d8c3a0d9b7f7f0e7edc075535dd9ebced8f63e5c11aa8d275fb4e24c69fbed3208
21	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x72e892a8c6bbbc25c2b8699b49827ab4c3d6f854b41e2fe416cbc33b0ad7aff7b71cdb6743404cfea18eeface89207a50aec931462ce34c83bd31b100784bfbd	\\xe9116f0223ab92cda98a4fe1b47b412d615187d1d72fe7ad41318e4491d2f31e42d12203efce9b005867177c28afad630c4887ca3a08d321acf6dc376423540e
22	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x338bdd697976fe4c5cc6802f7fea59354d3c225906f622ecc3620494a18f89626690b2d25fa26b0eabee53b8d32f2ae2c2a8c77575a42966fc224b6e56d3a528	\\x9bbc5a212ce5cb0397fbd80c0505f407bf64c59c559c412ef236fd912ebd4f809ac2ea4f228b724f7f1ed2fec463441edd2b75bf1a47e2bf1527368ffc388e00
23	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfaac1e9fc7c3f543e946367865f8710ddca957ca7e495b6cf1825fd63d59a21940bfc1ed7fbd42a75f4a0d648288e1dc54efd6de8d0f1922fc0e092135abf133	\\x6fd8e372846902e0f8ad23a719b53468586dc82b4b2b2cc3d3fff00ff3c51daae0fed6f66ca9968b4f9d2c514f34ee0b38c844ff49cf709f34adeb694d525306
24	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5198466e78887e2139b813cf66d1cd6b2d60dad4ef6ada0b04ff508fd07df5e682d072ebcf1fa73cfebc017bae564d697cc709004abdb96e3b4f2517127f77cd	\\xea09541e2b7c341999ef06d470be6a582d66fd50064d08ef23ab89624e74473571b97ff1d4ac9065d518675ed28ca86ebb4f1f0a2fe335dfb99c88ca02d2c707
25	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2a1aa322de9300eecaac47caaed13703bd643cea6e0dd3b009725db0f0405832985b4ec0b4bfcd9d21d3715faac7761eb90fa24a43b4fe6504ef2035dc4205c5	\\x3116da61a986f60adfa12197f9b379afa36d515505346ee87d35cce9fb31e4ad9c26dfedaadc5c7b988ec70558850ebfd896f004768b4032fb2395eaa501060c
26	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe94921868ddfac604daaf4eb643db2dab45b2ae1c9650e13c6fd80c6db2cc8a1e66a32a4a6f3005c887ce49ba86a2aaa3535950625f530cd865d68e6c3b2a2a5	\\x003a3ef90b63196abc43dc0e51f4482b8652ee09b44edee6ece268fb70718d0323e7bbd1d7687a520111f02ff1b47d0e6d14a4d151ed9b7fc2d341dcd5667b02
27	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x204b57b821247decf46ef8a318d596e971522147128475adba5288fdd58b3d5f8ab172846e189b969d6727cdb74ef0b5d2e4b4180c43721abd9c722d936c3d3f	\\x796da8804be815d8d4b22948ddf6bacb26509b5a048be0898564459a9d71810efd102ed252d19ad2890b7de083fffb4218ca01e4acee9a003d2144992feaa405
28	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5711e1532a3fe7e9b0ab01397ac6d9e81c20055b9787e0ef8dabf7eecf9beea86b54dc53fb1ddd5970bb8e44c325c5ad7410df5894a778cf143facc4e2a4aaf3	\\x1d0bea494e67284a7113c2ec720a925c4b9d01b323d96b6ce81bb7e569ef889c6b80b4cefd877fbeecf9cac7c914c6632f6242216a32c0bde9f6f690a0da2109
29	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8075d54101bad5dd58d1fa0f6730e4cbe2bea79b9088efa980c6315db8130daf047f8beae1b4ee753493868b482cd3c26deaebe8eae8db32fdd02bf289177929	\\x05f9037aae6fa1fd906f686abe422981dea146e65e3f74c4eb7c1a64c10ec14238897571843394eb7ec9a434c182e712ac17e17d802ea854e1f940c1af7c0b0e
30	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x237d035a2d24c3fd2d3cb578da6a1ec7cd0ebab5052ef925b4bbd8feb309f936f43ab3731d2c84c422d09a2225af3661bf8c529c91ee2239af8106a7e13901bf	\\x0c6ae91497b0f7d5814944725e985cc9c9c4be0fa68ac8f1a531bc4da34e7de1188038f6eee1404434eabb3b3b424fd1966f67322f27a548e357509ebb70a404
31	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x07f6f70085c553d08205c733de1b6d01d774ace438ecc838bd5472955178aa31e247914e70d196d5fa2d26c676673e03307d0d520c7e0c99dfb1555585b14433	\\xa63f7d7db656a11822f2b02ff6c17ffb778d2324a139f921a8a6cdf4e365b617f391951bae3c20caa47c5ae415eb81922adb017a5a5337dadca327f828797207
32	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5c092916424b0f26065829745f57d1184c048e1c9679d302bdc5562ed72823ca871322bc8c03996882b7a440ff45dc6de26564b3571c05459987e5d842fe831a	\\x0ecea4ac2ac6b18586ddbc851d49c441a6c5f6fa5a773b21218555e13ee752ffc8f4e4879dea03608dcfab3243316e1676f39b9723d09e71c27354f65cfb4a04
33	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9ddc493ac7d5fa655574982d2786279d3e2bbee41655bd3302cd06c75c0d3e471b9c60584baa430b96d72504bfe42032740a0b674c741852ddb36e67a0ba205f	\\x66fc9c09eded161a4ee8f785f394469d093771c6f5d2d73dc527cce529fe87e77aacb9af175da79f27ee2799a0305b0352da0a85429ffdab545395c8517e3202
34	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5e7fa9b712eb5ffccd3243c81361230814511d0268b5ec79e9c3f2ef14fd2ef583cfa1a6873a74e88faaadabd3ed412e42d9b336ced7f227f39fa0f8f31a1eac	\\x0c7666fc996b62ac48fa798b70e965057f28d48591474ed0690f51df7357c3d381b9c6ec23eb1757b2a39efd30b1db50c158664e4477fb7cc1132bba6b6a1f08
35	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x62483718592cafe927c539809b1966256414fbf885fe79a3d337ec71391ada5fad7556bb022fad22bbfdd89f5e036652590c933064d6e2c1bb435c24ba557cdc	\\x8c6d28a27f070236d25ecd26517b82708a107a4442c61688c7d043448b48e23ca93c8e960e2dadfaf761f51f1fa08335bb04b12fec1cc7f0cad4b69b2f30db05
36	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8fbccf38b13311d1a4aeb9ab636b252b380a31c17e0801ef6a6e9e60f3a6f2d5bd034e6f636184c37463549342414b4bac8c840a72082a7a59620a790cb2e260	\\x4c2ce195427556c075875bb4c70c919ff364a7ce1b0aeda44af6874ac1f3dfd96c9bbb36c72da8df06d6ca7bebe6ee5c4d277906b88842cacdb66ade0c890e01
37	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x44ddc818356071596217443817cfdb3d081b1d9b296755e5461bde74fc4adfcf713b30b27fb5ab8ace4d505c2cbba8b53ff2252b89487a4ce68992ec903d3713	\\x8fea6cdaea7b88651daae55f8982b9a721bc621845868571a39cb55e31e8f21030e12f1a28263b3be822faf8bc734194c06aa9010ee596f2110c419132f1460f
38	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8730225baa775894748a986d2f17e9204773a5ce7c3739f9fce2d9eaef0c0c9bc12362f97c6d35f6c5060c4e5114c6c8e506317af528b072d229d9a76535a5d9	\\x724bec13e17eb41e9406790a88cc6c00c40816c836bc9a192c1022d9b78393cb5367c7f88c5e4596a939887d1a7d5bd729bfc1ddd6f9bd62a1ddd8591b072002
39	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8d26e5152de9ac1be92dcbb2ede6d23c236b42afaaaef2338a3b908dfa65532c05df2c62c79539eb94d62995e673f6cf134345e2372236a38a8c740720b5938a	\\x851f760b6a469dca3e86205a53182ad2af37a445178de6e21c558f3322bd2d9e2a9e008f0aea7cb3d56711ab0ceaef5e01d65f708bcbbba2f947ce8e1a30900f
40	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x93df7ce8f22e2b549e73ea95b5e4e369e68cdfd1fe5da941e792f4a1375d96b5c624b9b71a48be38db1069fae65c18558ca4877d4a98a622de1b62b0f9d5a668	\\x7f650d231fd3fcf75c7db1fad4e3784942028e3a5d066ebc2135252fa6568cc0396623f1a57e8623fad9536b38308f8e25d2976a9d840d15287ede4af1a61706
45	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0afc20aae1d81eaa9ea530b96c19346fc68b8797771641efb870692170d5ad0ce4452b0231d5ef891c90b728458ba2dcaf0ef4747ba286ff5a924d928a9a05d3	\\xd955bb137b6292b255b1a52e2a99fd4ef36babc0975f912d193e2521668b15b0766ef091cb2f2f87ca0428f4013e16a29883f12e9d0b961e9e69d23d4c4ef10a
49	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x61742a5272034cfbd0fd599fc4cf9ea5424b55ee78803cea4c7fc4cb88589c117307926cbc50682dbbae212fcc329d89b0b5463fbf32ae40fb20b1d5b80fc75e	\\x2587f103c1ee46a9b7d5769d6ed0077dbebcf5c8487a33619de5466506db128b0a1fc3c41e165f21c38dd39aa3008ae7c6d95253035ca189421fbbe837ab6e06
55	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9ac1906a866d1dbbb7279e2a6057e72b44e611d66d6a68e1f29007e2ac47d914f70c3dfc0379bf7b7bbf20711c75e4ae06e97e47a77f2a036cffe4a6bc2ed3cc	\\xf19639c080e24da5fa785e383c6f57b22ca7dfcb00effaa25a525d22d2ab67e35d0e42c40a16410bc6dead03440659d4aa592902afcb19d6fe00358585f5660c
59	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x21fdb92f0e1d9b18cc5ddc6e214d5d317514cb2df982834a50c82627f108fbfea0c82aaa297a80d57d0abee7d9299bc4a6524cad460ed9768faef068e0a559c9	\\x6fb8a163e1ab4113402a6ee9e5699dff33aac9e4acd31db3784b00f9d7d039640a601ac6642abd4019d9e2a66526002b39f57700caa154b20cf7d28e15e55001
64	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7b2ed905499af0ecbf6ab7e37b2fa8168939ca6f1f6670a97ac754f0e4db2e20c8d6b09349bccaf57713769b2de9e0f7c6c1208b5fa598522cc475a976338645	\\x3c32505edb680d3279bc1c627daf89c6874859c83ddb727809c642d4d34815ccabf335baf9cd8a6e129d5698a8a858bee620afa0db1e5f5037167ea0691eaf06
69	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x486160f60e2470b3ce1e9e0ea65f0924db40661176f7394a3b0a9bc0026d3efbe1198d9e7764ac1500dc3c1f933cbb6653afa0db640df17a4c989ed8933a3fec	\\x5fab8ec23b5bcbc5e834178e45b5ddfb46378f9e6e169821fa3492f57e4f02b5475388361698a01ec873570d4ae5b8c7a48ff73b7fc1cc0bf344ebdf957dfe08
74	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd08f6f1fedeb743ba0c3d61bd1d215633cea3206c10870b054c9a4742a0c16f99b1e36234791eff53ed99bf71fa338be6374c809cbf9f1b57b1599a4b05747f3	\\x01c5508979eb2681fcb32b22d4616254426b2422f299d269a1d9d913d5c84c817cea794498ab98996e15065bf73575071b59380e3149b73c89e98312411cc702
79	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa0c9b6cdec0a13492ac6c457f4e767e5ff7678c72d20dd3057b2f7bed16f65017bcd38ec05ccd767d0bd2e9ad8dca5f38c81a196b6aa0b6ff20105be7553419a	\\x0a3f2719ce6d4154775eff831a63043d980903854fe49d7296012dac1f45aaf2308d7791addbbee8e007bf7d188aac415cf5cb5d36e5d9c134dff15728392408
87	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc8239149f5e809c073056d5722dc84f7d3374e17fe714824334be2c8cbec872c4bd1641a7b12250f42bb5b35cdbc3e9257ec89457dd19403cbad2d5788ba2a55	\\xa8773f4403eaf015af5c404589093396c84c9cb0f48c71c14ff5d605c1541ad7fcc79188bae07ec44826851c29c9026a146d60fdad3d526944b26da615507900
95	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa11192d3e8e05aa7da01bafc2876110b8f9783d7422c3f785b18250d50e6503443425278bc0890baf48f0c098230c0e72a6fbb886dfbb71e634beb670d9cd158	\\x01a45e67fe70745bf178a9a0f37f82bd1045d387ad09befe0895565fc64b82bcf2f084bcb28c41f8f29c322ec8bd5bbfe732930f1d7e424ab7ede1cf9807eb0c
102	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1a8bc43c43115484137bda3d48c6bfcbc49ad6c1db71303662348845559c6ef8f7baf49504ad412480f0c19e96eee9cf4919bdcc14d182608c54f7dcba03f4aa	\\x7657dcfff79f39341d5abc11fbd2273b62b1bcedb748a7e1fb337a8da938efc69aad89e137e25297e1bca815ef25507f282e8e167496539abfc78602013a1f08
111	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8341ac867cb38e2e97fc7dae5b25aac4eb265cc603c0d4e34a954bfc9893897ebbc66b29dbc3f2bde3022b6d31d305c856bb9c854d3b4442606cf491f2975298	\\x5b8968e508bd671da74cd0784cce9b2a46c3d9c4b7963af5a81a2c8604e26621f21b53b296d6c84af4c9f002b521d737022cdc309bf48535e591a9b8652b330b
118	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe4ffb3efa7d38d1dfd9087100c867c1d48dae937179df69abdcb7f9c7a9d7f7bc8ecd5695f916dc1224a49bb6e3831725a7fe71e7dd27c6058155da6ffb20ffb	\\x3ed02e58b0d95e7b4c11aeed9f3fca3218475b1b936ccb2c8f52a1117b5b6c1871a38104b8ad3d37747c58b7e697a4a7234191227c5ddb9cd75a4f2e50619205
133	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3e00bf8ce2b098004089de607922efca77d81a6d6eee47ca8d3b0015afb3dd5e8078cc10f0af74ff0233bc05f931da5a77fbfb46984920d200f9a48a4c075f57	\\xd1fb04c04333bf77afd827071e3eb03bccf54c531b5b62c7966f2f335b1c74ad3b51cd1fbe82364266c332ad8253392e586d19f82bf1a0d868e34f6aaa251b0e
142	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb3241bd14c1f46c563a612f7c12fe1521fd3cd2a53918b2feffea73f42208cab2c001e0bc1a538b7972880e612a4dc19ffa0768e9cf476ee8301fcb0e5238ee2	\\x6da8eed0f73c0112d3000edf766111db0029bb88008b1d787e8c4eb1b1f248d84e40433111ee3199885f42707da199c7b9f163d85d8039a403328632c13c7a0e
180	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9464dd7da4d538cd2a53effa72bfa8c73d1e6409fb6549961f96a669ef680b6276375a5938b8ceaa2d24beebdce5fa9b7408257343bbbf3db8945885a0e3247d	\\x1fe3b3505ccd754d4052b61eb11da798d4bd64217d5c82f694a04f57a334b75269f8716d418d412f28a4fa8d05762d36b48f0b7cf159e66d9fb413633eb7b60f
206	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe7b178c9f9f63b46e7125104f60e81acb68747c84b8a46b3dbb0bb67eed5f7955c31763abc29cf99a70c883e4e661d5916477ab49aab17454504db5a8d7cd546	\\x6607c4f5de2381d447d1f465b23513d9b4e0a7f3454a183191a2385a7b2d4566093f34949a0f735dcd57df1a6875cd5cb1319a787182446a2d84c016b3ee4400
232	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf8c5b79d36ca255b90bcae32c1569fcc5e81df19bebeedc65369928d05f3628a9724c3ff49f4ce148a2d6e21718fe8f6345721891ee79076dde15b06c944a1dd	\\x41256674325461649b0ca109564ae666420df379466a10c0f5b697d922644db3e3a07b1a855d5e5d916bfd4cfe4282ed27d928a52cd51acd9c6859a872f9940c
243	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd7f95b9f69bce61704ae8c9e6566d249279ff04b1c0cdf548443fafe37de5ea191f0f4dae571917f046b1d70c206bb263aea5b910c93f72995ee558e8dd35a37	\\x6cef28fc0fc2ec48ee51467990357abc2daca2d64d0b0b300e9e319fd132ce7c73e5ffb876e2c464bac20779448d4b6916030724d2ada6989da4854f53572908
315	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x23906eb74cc76faabe6a567297cbe7a56f488bb5747d0b6986869f96269fc643e3e66a4d7a8ba4c921cbe04d47541cd335ef55121654b6d244ba997f138e0df7	\\x6e55460aad736201a13d5f83548f42713324543ed997da70226608ea6468c4a80cd40fd8dec23368d5ba213a79819b7aac7fb59e7f90777923b731286ff88b0d
365	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xeeafc96dd741d2e3fb70b996754318f495239f90ec69260019fa9498c5fe7ed78df8d20e4edddae689bc52b889a8d713a9e4faa2cb72cbae215b2b4b1f16c79f	\\x2db9bdbadc63ead7af657818d0372793eca44f8eb3daa79eff9b5a4d81437d98e3b67748c8d18137301d68f0d5fd215b50f4a40d3283e869f6e68005e41b8900
46	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb711fbe49c7e91bb3af74dca593d0ab39285c232512e76d332265eee83d5a7c50044374aca052f6202f4da174a88ceac47dfca33f4d5cd256fcddcc29cd2d94b	\\xd7a3841a7ffb27bb14090889085ab9ac3ea8e7686bd2fb24bcde3d0bf4178b946275c38a2ceb6905d842542f95aff9e9d1e802f00795fe3cad24a93fa8854a03
50	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8ed23eb5cd7f957288ea9b86324da52f97930303c736dc6e174791902528e8a511b032d6224bcaec15c5ac9d5098e0a7e94de3c65e999bb27e5073afd73fb044	\\xad3fa05d482f8b4dbb7b088b814cfdbb0feeb800ea2504027857f083c911cd731bb1635516f3ed720b1a67e02638819cb111a7bb1fcef6cd07651a95d62e390c
58	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x42e3f1a7936090075f54ad026032472c58f7916197e81730490d2aa80a0b9ff710cc62d443d9c415b149067f6aa76f3a94aa9ef952c7aaaaf749b20dcb713209	\\xbd4ce716a54149050768e2acb90f32d6c5652bce5eb5410437910e7e7a7299bc230c808c0d43c5cb63338438583dd446e5c6daf3212d64eb7fd5356e1f52a502
62	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf9283312555ab3d60a08b113aefe78b8fe4c6c4cc627a246a2e6e99d38d570fcc505afc549623c25fc6bd4d3b644e294363fff0fb3e87dbcb448cd7b75756ce9	\\x8253941abd14063f31391a482a54d19e5dca646c39c5d08c97c58832cdfdb94b9af3864825175765ee81ab4c479a05f5d255435c3ada3c8841134364bee2ec00
72	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x08272fe5639a9321040898026ceea3f274738d5ee91bfe866c3aeb4d4c0a0bba98a58e5b3ff003eb8b991cc3846380a6186041da1b41d4f161b12bcab30c508a	\\x445bcc307cbc6bdbcf587512695320f66a08a2f28c9278517ed3232bc189a5e091863785611931faacf64e591ff600af803cf0678af61e51b4e42852f57cbb05
86	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xae5af11c169956813b7999ac757eb7cc7cf2d8236b0f5dd72503317952d8a1c487165bb2a911bbb9ef1fab75c19d6db83b525f14b748ac90b6d9d820bc39bb1d	\\x8e9a9158226177f526b2a278e301149ce80d7f5a0bf0fed407435fed85476533550d0bfd150bf46e7b1dd17d600bb99f3d0afaecc396f49aa0106fcb0ddc2c0d
90	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7e4b693f8571995c842b44b4826766021d24b9019500be5cc49829111d7eacd5630e438c013aea34c0dfe24252faede2b60111f0fba216d8ca6dbccef651f04b	\\x88fc3930ae72792803be65c35256e4539745ed8f8cd0a0fd7f4fc3dce350a0569e182fdfec5042e60eeca6d2df5ff4a54d91c1826c26ec6e6b4a7c844ac1b803
98	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x862a07b9620c775ce4f6becb0a288b575c12b308202a8f9e1300ac5e9ecebec2963b457a92750c95aab4685cca1cdb67bace7f44072306186edf17a56c7fb726	\\x330caba42a26c7b9a51aae5055b5810ff76545a67da33f78534e243383bb0e0e7b7b13dc02639e614473d65e3c935832fa10f73b9655ec31973e0b96c9123b02
106	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x07af7e69feedcd0139f8f27d8d5dac93579488fecc298428317158a9572a9558fd9b22a0a659b5feb9ec2c04f4983087eb74c55656f70e3c4c8ccac8c731a62b	\\x9e430b9c0d1199a2473b7c2a4e67819936c7d126d4ac8cc73e3c153a653d46af1f8c39b36760763bfcdf96653f53db25cd393e53430a77394ba0fc80fa9d7501
114	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x58e4e4a3a8314987d2f880ea51ed326e542d3f9e39506c4111893dc309b6d08582c6cf47d447e6845c524a7327e9b0ea8f9d5f4baf6e9cfe1634cf184875ef50	\\x3a2f1e6b95e872d7e924f42de01149570fd61f86a6e1b1907a9c0190562148f62384a3e09faacafa418f85c939f529ed4c27f9629c89b406a4951cc2ec47b601
124	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8bf1f1cb3403a1fcf4c9c92bfea0ae9505846f748e425b1eba53644c04276a3aa365d5bb67ed997ae3ab85478ed606e588baf2deea3ff36cf2d3ace7a0960fc7	\\xdd9837ed87c683181f6c088a7207cb6aa22ba1437cf234b61f8511743a023213aaf2d1b01a14f0be132e8a2446aec9efdf3a4155f092e1b04418c90f31423f01
128	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x815c4576ede8f9768ce893db80a627511899cefbf7df5600eca95abfa98e715e41d04b8f972500300125eb778aa5b38fa535e01a18d072de0c742756c5ceabca	\\x66b3d965801ab3d757f4165d08547172d64b7f6111bed57cd79bc9c1421b6eb01ff279d7c07ef040d6c96d67ac42132dc3f77da4f6b1065ec9074feb672ce901
135	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2d5279b5a6e3eaf079c4b8a6fc5ac476e8f71a66fb41bd0097e39f017161321b08aacb41f783b679fb0962cbcc70b6f43370c46184123af82bd15767ed9938c6	\\x94367563f7f1680c674a636429409d5bf2f2be6d6a3a461e165b558e4714f7147c0011c417c388b40b9f3d0f06a63c5ff306731995fba2b134e12e851a11bd02
145	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd02a0b8d3962f142968f953056d009de3f9e83e3299e78b621553993997624719af0a13877522278c95549c69d29aefc6a2b1cfeb536e6c783567950b398e93a	\\xed6f9b8a1357d1bd5ebeb58b0fb6490caf002e28a32fcc6d7c344cf5f4e3ac8a94e5d9a9960097204edbc8667ceeae12d1d06adb27c7fb189f0d5f11351f6e0a
192	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xdb580cf05aacf8ae75c99c14b05049c34c100dd0d8fbc162987839139190a3249bcd1da9e3d7ec043bde3402f497c69cca9ecf05b650e63154f71a66d53a059e	\\x419395c72a0a65d83edfaab6eadf0cea484efb6061b708639d5ebeef8d19f232a31fde26e0dff294802408b69a8504a120a8378b4bc89f860c0eebb3c818ab03
240	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb230dc27ef3cde945ce6e2bd6719d97dde02076e6c99cb4ee2fea40f95d8e15cbe73272fe1798dbae679ad4983001fe36be9bb9ddc691129eb90c7c49578f3f0	\\xc6934b67bca9dcca68b6321c15fb5f7d860c44b86253a269062809b33567c10b08ae6452c08cd2e7b2c32688ab855d361c5d7e6143752b38a7d2da527f9d0303
279	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2740ee2cf51e05d8c0ad2489cdfb7709da247b4b01b30df6f6326b770d7c35f9fb3af98f99e42780e654c3f0c6cc1b9ba23a27fe07b3d57fe343aeb8b93f5930	\\xd52650021aa87c4c24153110a9be5d80f11b0e95e72d6addaf963ecd7d7680eaf5138772e2301bdd38178c81f5ab28f2420c6180340ce4d2e3726cc9ecb9250f
298	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8d57553c549b2aa6bdfa0afbd6b2b0a4837d4570c3ad80114005f8a5221687ed3a193f61824e427a8c39ab84c87d160021291f2bf32395a338384b096621fc92	\\x1c729d442d6f7782c81451bd19933ed99c34221e1d68404fa777570d7570bd6e28873c796bdec1be244d90e815b2147315db774c897fa99d7a897d75e13a6f07
364	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9e55c0aa50f3ffb2b7c02cb947d87716f62c64a3968040637fb9af4a05540d33e24ca37075243e60f19ca20201710f3cb27f1c4ad8245ea3185a98058113690f	\\x48ec12b6a4379297f3add5513bb683948651a30dd55c239ef4874d41e95b67ac179be2dccbb9ca9697ede4b1428459d2ed4f41a4e5d4d46021f8be5e08b2dd09
47	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7e0a50d4e5e891a8eb7a17706cc05519954872e422f4da85456de6ee63553b743cbb1a4a68a170ddc45d3b409291e3d45d3d3adf70a86557890d625f0766053b	\\x306b213aecdaf25fc616f96c68d241912fdd80410289674210a28b95594e79944b3171c3a050175f0fd53e745eb02f17a2191a7e5d3606a13831da2e9ef62a01
51	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xedd395f2d0a07f71d895d82796c97dd4b639c862d8906d35d5ac849a19c5ccf950f866b6959edc525d0e05f4b9b441b73c383b326da59aac38d58703143733fe	\\x18eb4f0ddcf3d58d2b53487436d87212f5f43be2d5448a1de3f51cfa58ec9316b8a997ab7e011c58a6d31295d698a6f7aee36b0ad1a8d88630b2a527edab270a
53	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xff3d35cbedc83df59775941516b5a3bb83ae28709cb2cd79b4aa352b8a3253e75d795570b90c7058f7eb03f073e4911501a96e276ff09c01e476a9a6c8f9e912	\\xe790487a6e8327321a036f257a565a4853b377496311291952b0155bf64c868e0a16d5f3e5b380261b671cd963b73c02e6c864330d02488b23891a4066ee4503
67	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc76e019c93c472581110f8f5d1ac7f11507c2e09c0c8c861981c2f078ca4c2ae6539f4b377fd6b3e775c799b0050b0a1201a155be7ce5a985e2c3d9703448e58	\\xb277b7af80d4941fe0bc9cd1e9bfaa5ab2e6738a0d820e61ba11cff346ed3411b1bad6261e35223978a7c352efe6c1a20049a8c8dc859008126d53618c09470a
73	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfc75436f0caa80e3cd3fd9bf69557e3879365188c68a1926b40838bd9919fa55d999380e0d966f7cc1624ef5a9c4effd120b13bf43b366f30050bd7a3f88a965	\\x1ad11e9740f909934a2b763cf2477d048ae5177df5c422beeaaaf3095809db5e64ccff8b92b35d01243d34ccb54d02b541d249ec0b989c7745b96fce9694d50f
80	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfb1d874519c8c99712d7e5c51539716395749d25d7ea99a03797a16f457f9bd529aaf3b2e8fe2aa72b834370e9052b320de269ba79bf042d62b8deab00bebb1d	\\xf89903e581402814fc85afcf78eea42a3d9612be2955a434f537507fb4e2cc6fd9baa72f19ad08daf8d135a9a8fa9d312224735bb9c63d6a6ff5be3b8bbace0c
84	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1aeb02759af7f4f4776bff994f66f883987c6053d9ed3a539c2b1aa1370bce60abe96e913bbb55946cb34a3b14632c0dbf0773d264e911509780d6b5df4594aa	\\xa6e6de23711cc867a90069c6e10739251cdc03d799cbb92ce28c7aba35a96916a347481049d1252a7bfc9de8cb58200921a304afbde15509cc4296633c25c902
91	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc9db10b020d2993bd8652fe7a902993403a81e63e3aadacd7a392ad096570a2caccb42dc7d8c2d533742d36c2dad3330df700692b26b9c601977bb243eee20e9	\\xde491bc1ddba0e1861811a21613773fa10206e1ac8a2b0054770fc9904e365c9c0be5876fdf680d018bf4f5aaa6b9a74232d44a9c9ffd0d107cacc463d84f405
99	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1d6d7aad16b90e5c811bbb9f817bff8b51d3f561eee786196c2b225cc58a961c5af8992c02b451b1f30d69dbc9cc77f17786f60d40880a7afa919b34951614d9	\\x2bc9e007bd46688c2704dd322cc7f1b43e1ca7e96d1be53edda807ba37a1c5db6b9690ee1adb855f4d46efee864003d39ab5dcbb986d3699c4b9771b6722ae0f
107	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf5a34f34d179d915a0b0eafc94e08f46fbf751df75b421e7ea0ad0f5b11caede0ef8a53e44960e25fd81c6f58a479623518a03352314539ebc4645c0e684a129	\\xe39f385c6a4f83db571dfdb7be87f61fd6af3278057e8175d9380989c14f50b54812453a7b98037c8dc7b7e2a41d80ad5b6cb1f2e215ea168585ecbc726be204
115	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x609593e90584e5107eb3801b88325a988cfcdbc6479f8ed8ecdf5c146d2c2e74830b92457769c5bae620f9d12124c970928d34aec4223b88f80a7f3fcf7a4721	\\xe49f29779c75a9233924ecf479bf63aab91298592555eb7e0d2b64e030415a3b8cf33c45cd7f93c44c3f3cb7ae1862e0136221d1c03ee75ae38aece73030fe07
123	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2c8539df22efb93cf8b0028c1a9358f68e316f9dc00096627bd9d141f51d22ab1eb05ddf8bfad6293a38ff79ec48c6ba2429aba654a5ba143a20168fae165255	\\xceb5843840914ffdc5061cbe8dc3b8648a5713de81f3b79075f5943411a0f557ae9c58274fa476ab92af931c9f8557c5876615cb08ee7c8eec0b08fb5509b407
129	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbd3a0b766b14274df17b753dac7699d6b807d2295051e93295e3a39b3779d5733d9cb01d3ba8d9c07e910caafd4ccd407a9ca7fec81d9a1a6eb491ac1fe819fb	\\x5c17995fd97394aaa53d0d3eabda7dce4ab605e468f8e7fbd7e4932e2c1a674315622603f1885fb9da548cb30400113c23b2d1a982932f5371fefe1a006a760d
139	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4d9ab359cc4c94b722757849df07307d30846ace2262f97fa09f17e9cafa59ca5111e3ae87a4f8ffa6ac27be7a323e63bdf3ea7a461b8c9024f2a11b4ac302b0	\\x91e40c1bea200c3dc0b72c3318ad5d58559268e6aea5a7123d29f6c8abb2582e83bc9693a00af24324be24ee951ac0dc14af9f245d5e6be1fd03a6942e66d002
181	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb663fa70488e5a1a7b3d0053ef49e7f14ca32a792e58e7e1a53f22c79ac9a7172950f9f87999ba0197e27b021b36d43f255b869ebcf3a3dbaa48d604ba9991d0	\\x32b13bd46cdc57f4a0cfba981bd1e3dcc8ce9c94c4a5b2e41fa3128c33f1ca50b1007bb00e86802ca7ee00ccfe9821f0ffcc8ba2ae5626027627344af00a0e09
210	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6178a14f98887dc6f60e614e86198b2d97019215b9efc52f2e8506d94e93e558d7745f359a09af71d6c20addc4c5591f505e37e046dc56305aa3ecee63560735	\\xea5c102df3c5d164a9e0cae89c9067291d702cfdfb504d9bda8a9663e11bf5cb9c7f6cc1ed494d4c768e74442cb2d044f1a08d7c9c26c4fa647cad3ff377840f
231	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa75a02b0ae2bbee9642092f2ae4877ba3ec14e87bde23d0841fb387d4c2030a8a625050779edf20d9967543045516b50ac175655b0d0dd57ae07f266695c411f	\\x3b400485e4668c4b626330f290c209374f2b593689335f6ae46948fb3e6423bd1a2aad2c6863735cc9c8070157c1a41bdd1c462db9c4baff0d63aa3e5ba0b00e
248	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9790a76eeb30f5af98152124f2780593ca929ebee27536a3ec276cba9d8ac294fc0e8abfe56b2e0f0936341cc6527a82b32f9563c96e010d819b37acbfe892b0	\\xe80785740d0e304f6cf115cd9e0be84f28a20bffd60d052c2c24c04fc44bba95330d28b4c613df2876ab44c0122da4739303e560ff5b6ffdbb69a022c0bbb90f
285	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7fd16cf92e07cb80e00e99eacb2eada3947de252fe5337305f281d9cc9e7f804763e7c1d7e6acb3c099cb2432d77f5c1e9a9fca2689bbfe1934f075599dd9e17	\\xe34a3533c55da550d46d49d82ccd4d3f22e876610ac289679d22070a1e480ef72cce48d5dd4031f47d49a141c21d24ba447275aa265d52e9422a9bd43a6a5400
341	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb2bcc4dca189973dfaeb1fd8e11f8dd3dc7907b38224a42064687b0c6e8fa9620e76d556476a6bb09faf88d018ec18df337863587d10516c121e47cf8a9ed617	\\x320f5b108da6c8c4ce3dfec160727f54f6c25c0a0d4f942725384072f7ad1b7bb031ddc0efaf55f66223ad89a1ab9f94abea34f2762524f2b43f1e3d7685c704
356	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xeaa7a4aff687149a9a3a0cbcfd40c3596eec6b3a45c106c935ed126d8ebcd54d3755d452df0c5747d88ff7e704369ab5f3b5d9f15e8dc6c30b51d77ef11983c9	\\x385fd212e4f1a47d903ab0a68dba9d4c2d49e83f816284f477efaebc34eafc76de56d8cb45b12ed015aac6648df371c438f92d5eab6684b2311093e608c0ce01
404	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbacea387664815d55df00512efbdd73479e8c00497ab5c29bddbe04f05f2df635508ba32e8705d950bc143b6b678f5e4b2ce7760c043e71e0de7c3adec33ad12	\\x4bcdfc1701ed13e8fd3729119fa3a30ee8faa92c732851f8087065771ebed78eec84fb2d2099c408bfc8676827032f2075705b06fa404a4918bda761c16f7f09
48	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xacecad800149b1b78a60a5ddae2947cf26e4d1a0c26e8fb28614799a034a6745d198a39f51266e967e9a5ed5dce504d6d613dc5bec36ac5514722b691a9725cc	\\x5372e57a8b839d734a7f9b0c1100cafa3c5e1fb4e88a04ff8b14ad14331c9bb6a77f878ae0c6e97430b684194332575fdd8da66a9d04255401a2857ffa204c08
52	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe1c140c1fed533cf18966e48bffdb9cef0fcae92d832f7e78eb8200468e8b45389df2c2dfb797f37ca1a5d71fd6af7f582dc49e2cbc1603f0a339c85817ddf0f	\\x70c4e9949a11d4a6ca0cea91d6d7788933cd4bf08bec5438c1195fcede9901aef87183d0c27f95a9f151cae44e0b015d580d6b021c087ce55ffdcec44d499106
65	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe8208c20a023c315371faabf69c8a9ce174bbcaa361e5cdbed09be5bfe836b0b262c6d1b871fad48515b56198b986531a137b65a684c33ea0a1fcd233aca2aae	\\x5b30d983c13763de9bb79b554509a86739b4b1f6d63db0c2dd3bd55c1fe8bfee2cda071d4d56fe4f773e9b936f9d1f4711b84926680adfeaa99e151e056d3508
81	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x516223fa0880fcdef4f9da0d556e74999e9bd0b3e83ae2a927245478e106a755fa00f56c58dc0e9a38a1f9fa7b9e88808d664f93246854378dda1a75a0a26425	\\xe5fe41033e682413c9177592f2074de0fa956b1d3fce689680bbe89be7e294e9399d84c0816aaee4e441e4a89a0f1ba508bcb1a53ebbfaf24188c5602939bd01
88	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0974d47dd3b4686a745c3f84166f61a7946a47f6285b04f233108360832f7f5dd7b96cef3ecb639a0da68fcfd96771bd075a15b05d042da3184c390fb71ffc8f	\\x3f97990716e658fc74ba1b75c287928a7699721dd8c7377581536fd5ba1c5a3edf65b98399ca68c08eb9a14f3d2c9ea922c8df0599cf0c446140e1df64487107
94	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0d05d1d9b2acd544294166fc370358fbbff83562c0b644e5e552f94e6f6a8c75ca1f876e3fbae4e743914ad4082b92e5a6461a969e4f2154c59bf699f7649f76	\\xd713cdb788437ad3c8a708ba7ffc0c1cb5400ea43b3894c3b42a23a2b7d99f8ebc2b990020e05243e6bc2929b8e9f99738ab1d0afb4a91d4d86f0f133476d60f
100	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9b55b05ff1e55f33e07bb963a9c59114000d2aca2531fbcdbf7411bc1ff20b6cacd14fa33bba4b4c4ff6f36d364d90eb664bcf08285c8010954de2ddccba0edb	\\x38c054e4a04164a1129d61e029c75c2a8d01daeb9d5f37ff7ff38ed63b589b45fcea6b1f908c5fdbea61bea310c723fd7b1a91aa5c3cb50eecf46bcb2325ed06
108	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1085535313399720c4cd31c9b17b81ddb9f0a735c592f1a0add28be4ba18564fe3e5b54e3cbde73530485c5b8fd7bf033cc66ea4db3d5a813d4eba2f66aa225c	\\x417b0bb2b91bbc512a20a3ef1b81039b9600ddbc1c2d4de26c67261158477c41a134135f51343b2e129b7d9644636173608a87b6959cb6d6e14628087037fe05
116	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe02eae929432ed7139aa4655d9a37be31ed4e42d42c534ddd2068e9b9c888e727a2e7177c219a42181381916419f5c69b4f60ef9c4a8329051c3a324a5d61992	\\xf5c6d4b9c7a2c0479f39d5e97f43d13a2de0c7176a7b80e8e4ed3023b1ceea0a7bbc109656ba1eea77426b0f106b24a183796efd95d8d3eae55fb58ac8e6a30a
122	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x83748ac23308cf9c07aed798e4d400f9b1a571a5b2a3b5b0d185bad482c71f06c99088173698210694f75ba629d45e610e7270cc442820b5bab9ff154c8b8e70	\\x363fa0a2faeaddeae82b15e399d017b91adebe7cb18e6e0b2eef87dcd3372a55cf2d4afe84035fa42bf933fa53f94068d98b1040b0d3f78a32c94503f78af105
127	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5b2a9cc29532b69cb43e08f532d3724600076a418e1c223215b923aa85da45e686dc88e102db7f863ca46cd439d17959559de2d596bd87aad39b91e7cd461c0f	\\xac89b992a9065ef61d42c17b70ac92fb729188afeb05efb7ed0803d7ae315f04459ecc880ad422cc216f1ad459c4761b44329e2f348ee16fd494c72f1d772508
138	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3a3bddc0b4171b5542f15cb3d5dd4bf75ecb5cee1d8dd27b157bdad845b27190d6d3e898bc27f3a5816c71a54cb60b5d164a48f241ac45567c9846056e639b4e	\\x32b3cad2b1bd2126e89e73a5b5585dba844d4ce58a3ed09528d581226c59daa812007a5bd7f91cfd1a4f31e1b9a3034a3111f0703a4949680d2346d358055909
143	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x99014dd210a109acadf3d174a66f9e45941e071dcd471ca00fde83f859a16aff32396747924a5d8ec36fad79281061b0bc1b88c691a6e6743ed83034785762b8	\\x0291f772ed3139920b338d6964bedcaad2a669d059318e0e61fa808269707114045a4ca3f8eea1c06432d32dc73bf5ebface2e15d661319012c22aa4f2072a07
201	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7425c401a22ac4507917c4567643b9342651dea7a573ce4210cc3b9a148d8a0d5d1684c1d5fd04a493df6ba118467d30f3c8d5bc2f3982f6c71516a6dd98f90f	\\xdee278b6c0725f0700a6c841d1405b000792087e394ed69fe62ec3a899a4dd4734f51c08700bca81aba4453eb0d887b11eaa42911d030783ffa0ad926cc21903
224	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa3eb2e39dda663c2a349069db2e1620c088b7516daf07b95e8c09e822811c268f017f28a51fcccaa18de6b7e79466b10b022e54c27c5b3af0bfef33af4ca64af	\\xa89235bf67691c3af7df5f2c8a4ca5efa155ccc22667ce64d563b93f4caf6d228b2aac813f8599632597b08e064414a355d6c92f41282c56eaf2f1a643414006
249	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe8c239e3ef43950d66859b9224f51b5651c6ac837bb7735b5d86d780bd7cde86150b816c24fe5de521a757ecd0f19a7bd35691ecaa05e95446b9211ee536d748	\\x18b3a935a0bf83192d443111ea0978b4260604123942b0bab6fda7974a78b98f515f33030a7b3e459432fa56e0729233a2d454d6ad63d74554813eb11ab22b0c
297	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa4ae5982f377c031c7561aab0d6a296c64380c3d9752b04f72b78512101798d0ba7942798c73cdff7b7cd8f5adb3836aed84bb0dcabd80a082d4f4e097c1ee3e	\\x16ee2626f30cb2e1ac205ce737805229f18e104af26d36c09b5f04090f0637d70e1d55b3614c9e03a879ee982d52c4b7227e8a9b298d17a3f4d0382fc608fe05
307	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc2493615b396b72cd9cd5752c2c83464f4a57463db279a3fe4682d7af0d43d60bba07444679ac608006ddfb915ccb368389fa13ac407129373e8c0ca93fafa50	\\xe61632128d27c05e310c7688fff8c05b1d6c17327750ad6764942cb583b8467aa3252a95b8ac5ab35c24a91cb5153087a1d5beec3a477b3f89dc1eaf3c55c10e
330	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5ac6b82b5edd41c6a012b94bf1ec8f6bd8e781a7ee67d623548f78234ea7737a64ce127dc307ab780a21750744049838b1508173b042cdde173f60fca89039b9	\\xa44909a3602948a363853f30ec46cf4d69f6d85ab1f4a8757776f3e8cc560704beaabf34ecb394605f26398c2d2904cf5a109c046293b886b66e57b31dd43203
349	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x430e11374920095486b2c37ea662c79b50937fe41aa446a5489f2c1f9f094911beea045b8267619440911d8f21db88ee5acf16de8d8894bd3950022cfd5e5d7b	\\x540920e1b2df5c53f6c170fd1c3c8c401f1bac944bea52db7e69149747c0b345f3fe29ed505009ea44b2089183be93857495aeb850827fd5d37a8e8ffb3b1c09
43	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x31ea5e32af946c11511ed298e0d2647d8e0deb65a92d01730c3b4ecf0370a58cf559d8442d1f2c1af5ad8e5f34a4ae926a1af3793f4567363251e6cc8df3740a	\\xaca106d32bb32776c0cfe2471f8ad4afeb857ab2c196d9ed27bde478e55ddb2ad47506dcb9dbda5a67ada52abfb3e385dfcd752612921626a9d8d297056e6602
61	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc37a8d7ba08fd30a8451b8f767653affc45a7c9c690b445f031d71240011b5f2d548ad867272c2d16b3b70e97f122b5962c9df528921a589f9f2eeda0223e7e3	\\x1c8fe32d06230b7a33cea2944a462d184bfd01738d39e51b34230c7e303e15fbafcab7aa0db57e325dc30821b131735c5e94b4351cad87468e1b711badaa500b
70	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfda05e3299f1626a1c438d1bdc384406c0a21310e49c24cd7a9c229ee625d8e5e231c31d72dbce8dadd68ba6759fc08a553620592bc6a773593cba82247437c8	\\xd96201b7ed81b31ee923ae6ea3cbf3a97670a8dcd4ce4cda8a0cf303b878ec4f28f4928ae81d94a2c4ae1037af06922bad1d1d2524bdecb95c9013184111c60e
77	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7fa81deab3a668c424ce7ed12f1a24538f0bc2c12c1c2160b0aa0b3b492e9750d4e73296b21039c4d2ff015e43ccb26ae61ad5551dd8d96e51c52775d702e4d0	\\xa044d0c1803545032c6c0bca25cb7b82ee20bffbadba5650b4805b5a9feef62c0d1cac07ea013bb1b13f72ab78c98e3d3e577634ede316396465665a9c41db00
85	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd1c94b888d439b0c0e8e19cfa05be99fd9bc8b47a61f9b55016f5e65e55dce11ca531e7e046e19c3bed0b53a1be2e27de7e5c7a603856cc93a20568fcb1c8e04	\\xdd05fc68d5ee0038471f793fc847ae5416b7ec5d842ca96b3a4236cad98f9d0a7ad4b64765532d54f75c69471d0896ff5996e4eafe697a9266e12534a166af04
96	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x934626a7c8516ef8cce7948b78564780cd00dcf217c4c190832b371815dd31f93580e49396a544fc4d6b209d6c0174142cbb946403f5f60f0f390c5b05dabb48	\\x662ec83b7b9cf52b504f9d5fd390e3e305d681997199cb3e251f2b89da92d1f50044c9c251bd1a8882e7c4debaf484a35b43f0553391f27fdb6138d327693d08
101	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe1ab920787db9493b19aa29fae2bf0d33da043e56bb85ff1bdd39bcd6e17c56d88db086dc35492e3bb6b25d686e50e037019d423c12ccf0b73103915e0a95f24	\\xcb3d136dd9b87488ea884fda2975e52cf43c49271e8e11e86538eef38d82734201360122b722e0698b736d96e2fe7af802fbedddb0c204e9418005fbbeb89e0c
110	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x773a0ae5590f37befdeac85591a9fefad878568a1abc6212f8635a81acfedefaa78d15f734d092f3e4fc0bdb5d201bf53f99757904475d4819d82a00a0887498	\\x22b539d235e8fa28a62640764543f87802e9343dca3ce360450dabdf90b57e7168c9780bc8ca3bbadb005eac273d7be2ae0cee753a5f4cfa99b0595ef9f85305
121	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe7cf90e35f8341f5a57a437c40acfbd6c974afe99d605512ba67f05d6196505d47cfe758b855653e3919745400c8fd3d5b92c8528e2fc41ca69022cf9b662bf8	\\x951d6fa552af314668691cd43aea0a36b32eb671d8059a6c320d9b33d33d359d73f79ca39083b3349df4e2501c86d29d3ce41ffa9d93fd81c71a142664c77e0e
134	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf2a42e61025cf381a65a39e574ac5a25e7984be472cb0715d0f3399b465672e150c48deadf0505a9daf4cb4c4d8a6affd6266b7d5ff6f1e33e6dc0b5e7a6d0d6	\\x29cf8d76bcdf4184bfb83e1a8cd07c001198023ee58fd51ce8b1cbb3b853277ac090410bef817598875d48b36dd2cab61dc65ffaa80cf451568e76ce84d40e09
140	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2d1e81974c68f805cb65c967ce55c3b632853cc384375efe98279166d0fbe6d3b1ed9a3409a321e991788fe3c066b0421283905957b47c34b22f72da7d58dc8c	\\xd5c9b15ac12d0ef77aeeea4ae3af0488906360da33265015b355a03871c8864c646133d0981453a955936b26f5348856707b043e3de29b23764f934e5862c708
172	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf386509dd22b994df92215b88799ab1ecbb834a48943d94ba7776cdb881707f4e43c844df31db767193778ecbd04a4111bab6182e9488c1304b1fa456d8d118a	\\x4305eab9c5a8bb8a0f177c821f403bd5f3b6cd9fb0a3b673dac93d134d842fe888b66f116676e0a09696a5f093bd0b25ec3ef9a29aea2777390f3dee43329605
218	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x60f05991d9663f86563a1bda8c64f7ca6e34c9b4a18d021e7cc399b6bd265e7b636c48389aeb88ff09dadcc329611be6bc358a1cbd6691d5bda39b24293f868f	\\x7218bee2c58cd00eb71a5ceb9822b848d10bf73bd5be303f506fd233cbb7649554860cd7c2cd9eb4dfbeae8be811f996dfba23a4f77bc26d8f002f36f93e6405
257	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcbab0717263c2a7a77bc4575559788aa32e7931be7595fc807eeb12c603c89fd87d2a2080de0e6ab42cf711bbb815fa84102a042311fdff727080b845bdb5dc1	\\xf586e4638c5562f8b97b35d6020ce4f05c13238096faf39feb29d6e4a0794530dad8b352ecbe0976b66d6e84171201f6f50f85b29c1ead56cd8f6fb97f7d5c0e
370	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x927ab7d0d30224c3e1a2645d44543b8416d046eadd8184f0054bde2283918adebb5cfb0d72d2ad33051dc9a6d287541631fafdd5d1d3cb2482b93f5d3971545e	\\x1b0bdd2d4c9361750f0b0af5b36974884816b78dd60e8a0f14213aa595da268e19ab0e04ca04aa646d8bff2b7e914ffe9435f23088e769a351208fd6b8a9b70e
393	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x700f8c2e3373a9c689b004b7faf77ee5ba173ec5a1e425d235ca64639a80e296ad5fc1d1e0013ac7c33f584a71c7e2f8be3714793384a164194fd5b2ccecdb5a	\\xe6749b4ffc4f420b63fafff84287f58e718ffa14dc214f4ba259bd846ee7bb81ee10bfc79600e10f260b95391f12868a8535213e0f0c01cad95500b0cc28b701
44	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0d54892eddb591880f7e837a6fc9413b2eeb2de49939d063bd99a6ae44b1ebc24e03c0ece36c85ed22b4b659196b17bf19500699c2c14403bd975dfd8514a684	\\x78187a96d41289f19760edf9ac99b598aa02b29551245ed3bc7cd755d0769bd048d71ab4109f57a1c849aec2af3fe9bbbba41edce64275eb29ae37aec2d5020f
57	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc225fb9ef622b21c8136208b17f7af7a10414b7da502a99971eaf158a7c429e8f36b13e27a8adce11b8c5a849cc56e1868cbbdbedf8b0e5c1a6835aadb5429fd	\\x548ad035dd4c6888eb26c4552907e9b20448ce9358779248076d31af9ed63e5ec1063ce4c20d0fb6dcc3a4967efb689704b31ce07f3187a09e3d1336ca2b530c
68	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe938fbe62588b34cb8d3738f29a9dfda181dc8936e559b6123bb5508100be0ebbd7d3eb33297b1b6d7acd0a15f56dfcfaea395aa582042cf0643ef28585e113e	\\xc9ff8909f14e828a718108ff9a150e865796acba320528434df78a761270d2630205ec030dc00fa03487c1a9eda1d56e6eabe2f0bf7973d50e5e2b55a4c46409
78	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf33532beec6c9367d34edf8869ecda19bf5e8c9499abac4285180bf52e43aac4cf9c86d87fd8cdc4b2e689fec383e678f2dfa77071019df5a63c8255a8533aac	\\x767bf557ff10454ca2a1e7c06bdb496bcd4c24d727f1a5c0528cf0e80671370b3ef60e1a4b1fa43974c081ebb7a6b0d576703adfe38cf702fedc1861a6cbc40f
83	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc08862dc54510385593fb01f55fcc7406550ad6373216f519d3d05372f826a5a2ec08231cc76e7c8fcf06aa7fe18dec7ccde4becf7d1f2edf954397a0a7d623b	\\x0c5b7a60f9d5227bf458488cb1cb7eebf86622eb9bc68587d519f565421d51e762b4677b54e56052468fe055c58032692b1c38e38c7ed31f8170455c60ecd401
93	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x942bd264117f151b24e7c18660e54f8a30fa10e418e8615219d57ec258b042d3925d132895103522d16a94393d163d8eb8d22b6363374acccc5ec60cea4e8564	\\x9699c0e689ac339cc23cace2df21a276e40138ad8b09e8b1d6f6f5df124f95b619bd12121b5fab1db404f759352b64c0d1fbe599d3873fa2aa34e652202a170c
103	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa61e2a08296cb1f6a89607ee5c32e91970e6e97783cd91332a7fac403c4e51c58931f4d502c02c7beebdd8d82c94fd12323b962b34d2cfd12c747f59ff11728d	\\xc8d9a8554718269df1f988c5d132a43e8fdecfc5e2273abc123c36b707fd9ee3d01f4342aa4f7c72c87a682d8c63d686bfaf647a05e417768e8977fe95c5880f
109	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3302c9a5a5e21b53fc786059789788caef6bd8f29ecd268ce55965c58802b4cefc578b8a235f19f01137da3e38adbb7126887a0bdf0c71d1c9d885ef12c6ee96	\\x41621738b1604c79044120290f4b2cc216085842835caa691b2124afd7ac7cc40035df64e2c2bbc2d6759bfb70713a2524c6cebc5308600b3b29d625e2333102
117	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9c44b67d90268bd3466e00bfc42d478ac2ee48e7bfdbc1a714d9fa744fb26d555174aabdfa1f41768d373c014d0ab8e4dcd346c4e12159de088f118fed22fe15	\\x5c5484758bd9d2141195ef5533da0c50350043c5e2ec62379499c66fa8044d9e444691ae7bd5c50abc8789b38450fa621df0e4015724a1192c85f2d444ce0802
126	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9ba0f8dd13d445920b568be044093daf9d05dbeed67c470f9c7a834180f639a599d92f8d0d35ef148a237f40f84b0473182ad04786161c140ae41f75141f5a27	\\x2d5b2981fe31f06b411e17750dbfc2bc8f58d43f175988fca340149306dd41f92e8364efb25e965c3cd9289ceb8a80b40707c7fd6762c0905550cc4d6395950a
132	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1f2bd56644d2c5464b3f4d9b369250d138a7e65a64c2d320ab1a91d248e998a51dbdb14063d4c5b1df3c9ff64298ab9b44cf3292f64da75699e96feedbaa7968	\\x717b4244cd89c57fbf3e715fded60ffcdf278c947a782d94f2ff6eb52db3a2303506375c9918434d91888f18e0c75949d06e4d5f08cd223d4643dba177fc4800
137	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe3910a132e2479d51ceae7ceaf03bdd8f37edabf7e91f2700717059adee0477879ea0d3bbdc2f065003d83a4b7b3ca22a7d6294c7e4ba1a34f87d48e6cc5f56d	\\xe1d9095b54f44db2c64e0e3d4f8112fa8e6124d57d3c7f32585d941133b9991166dfdd81e4fb6112cef2506bdd7d4c911b7fd11e7f0c20feadb9ce45ceff0605
170	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xace6e81785877c9da8062e5cdc9f7cdbfc76cc4df7d0021903349d0a986df395bd757ed0f6d02d3a3bd26c1e456b1014e2892061534331e3e15169fe2d5ae98e	\\x3fa681c36c8479bff5843e4c1732590ca3377c7439bb0b9cc929e3733b1bf9f14fcbd72278633b77373de1fb93237b6b6c5e678db5abb7278ea43005c9df0805
202	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe08d151d6744d983c92267ae327dd40f718e63604431c6f0789a75a8a070c9d526c6af2eafafb89206346ee97e2dd7875af68a1922e41303e0b7557254e8c799	\\xe22f9b3b6369ee978bae564f95ec72670c85540f63a467fe06b366a2d54b07f308d04bfa6e3aa870d88653f649529b2110042d54fe6fd7685385f18d3721a70a
216	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xafc9c0b99c89af5c530256b47d0c2c4ee37801a3d220dfa02c1fa51bc16b8050e706656d3ab99badcf715e727e5d8feab1df76ba2d532cdd7d84599b44aca621	\\x4ee04a232ebef3e11791ffce1614a07620dba381e067e639619416e317906b6eb4943345cae1d42caf57568d8c9b446adff64c97ce6f8b0e7cc0a8fb52832e09
275	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x76f6a004e6cdf5b8c07de0d2aea81f9ef3e6a4df1b5dd55d27a9554fcdef185169ade1bdff4633fd552dc5719866f5583a4412ba25ff4aa195f7b06a3147101f	\\x14d7710cea9986354480f791842543bd3eea32976efca2c24ce5eb8003fd1b8df71ea35df2c02c2a5e50ff1dc868c89ebefea87c89d001814a7a6cd8e1793409
292	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x07635dec4d4abd28f558331daae741cb38758be1ec2d08ce09e33e9cf993006cdb414243031a7e234066095b66ed5e0eb437cd2f8882e6a1d8bc499519269b89	\\xf82ece1c1b2df20048dc037213171bee41292affdc47356f5e353609a77b81577e38dc08df35353fcbd9b8230a7e95a4a6ca604834af15c175045fe417269c06
328	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x04b8afe12569ab87853fa8209832ad1dc40ca2a6bd7323627c9300010e9ee27c090ad63154ec2b1d43ab9a08fcaed9708a7ad6ce81544097092b56e58e5efd1f	\\xd630298ed10895c5674bc2441836c57ec82d493c73a8722079571f5309b5ebc8cf5c9c75135d14cff3db6cba1df56ca52afbefe5e529526e5176a06993327b04
383	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb559c32b1e114ddb6b863cbe7191ea8fbb4984ea7cb94d5340e27b07733f2a6344692524a303f362d248ff0a722996c430a8351e5f43a54dd34e9fdd9767351a	\\xcc8070fcf5a28ca81db67e9cd3e3f26025a33490f172ead156a60dea3a3cbefaa37f9f248af449c14d64cad945f1cbd32385966979de253b87ea707b46b5d200
398	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8a55a344eda33e07e76de911ba8c67a0fc717ec746c3f8ac72f5a6cfb3d3969daf0e73bcd00ce01581645c9428b30d39a98e7a6a94d7b7d425a7167c1aa32357	\\x8437b115a538e452bb62ae9400a7fd5d2885691971ea386c3cc611749218ce8a8b6ac529a99b3fb634560628153e196bb0d714765b0c54d75eb9c09dd6b83700
411	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe29619ca8ce6dd0b84b09a06d43094d186e508f55e1ebdca6c6848e3a902113baa89fda6c1f7a9a27c85e2ae5cb6b0277584991b03b060e42ba91b66eb063a59	\\xac0fe1d2127966c02eb2f01d0ed0b725d5a4a5f700e398476749cc1ab091e1f990102ab1e23385cfb4d66a1a29da6f72a8f11e54445193475ec9e81668dee70f
42	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x27706853f765cc0fd712d3cd0b45b42c9282d184c2a6576cbb2a5f71a970e990ad4681136ca1a8b2677796e4d6615802f9c283d975518459e5aca67fed7a2968	\\xce142f5cd43169836cf4b0554349dbb395f8f558e2c1cf730a981ccf50cf2980a44b4bb66174507ca226f562c39c53091fe8f28e9c94d1537f510a4221b14207
56	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcc5767b402bd51a537f365373f5361c71df554cf119643f0a50de1b699fef4097f091744c2f846e2999dfafe3649cea1c7497d8271911c2911832363d8aa17f7	\\xac972ac2bae036dae4facb0e47677d5f2fe65d297d14b0e8c42807ac381f75b7e76b5e850436f32f60a7951ea612d70ff9f4c4d2a01af9a019ac34bd704c2806
66	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa4dcbecb1ae0bda234e8fdd3b5732c0a7ca32f89432bd5d5a4c83b0ef8e04f65feb37b12961ac9dc771d5b430db68fef7ab1afc63a2b1bbc2442787f02c6d2d8	\\xf78cf2e11055e7b125c80c40c4a9aa39797efda8b14c24034fd54785e618cfc7556b275468652dbe1e17a5bb5f9ac628d95baadd95df0253896e6140db044a08
75	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6df597260f798aa7d0378e514159d6e96df6027adc068710105c3ab29da0ce606f6eb9abe516f791b96c31139d7eb8962953f3b92e1bbc0664e02e18601c41b5	\\x438360367797eda669c7ab0cd7d7b8f5b8384a70fd614d24ffd2bf25feb5ede754189ae229a77c33b399fa61b0750a9837a07e778dfbd1de9a528600f49fbd02
89	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x95334281d4463020ac4ee76ef45d8f18aad13119379293b6850215aadc5b4f3c1b3b54375643161f5816131e40db3f76f40bbb1121fd2335911e43459f3b9fbb	\\x5e42b546e161092252fcebad00828633e79da357e41779274c2f45df26410d0626d116c214663f4e83f5b94ae0d1151ac4b759c62eead4221a289a77e9584b0d
97	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd4ec8200717211840935df14e75e59fb1feb17811ee715d445b54fed7f08dfed34884310661c45f13d78babcfc8757e892a280c466ed1959d76cc4dcf2babd8f	\\x69fed86de44f9d1d0ccc40e954b2db58b4cbaeaf60e332edaea9b575190275b4014913c8294e1538aaea2abe4e49fdece6bd2ea47ad987fbb3a0b883b37ba404
104	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xabfa778ee65abc074b0492e2a831eaecfdf9fc1cd0df904a615407d8ec98e202fa4e69ec59b051f9d7428409b1c2305e82d22e08ee4253182eea51815fdf06c5	\\x1ea1e752a883d13977375e07e389b0c601697fe9b185da52faf0e3e7ad59b62cc4df9ac5587c15215b34c2b94be793925251d92ee1d96d77b7996be9fae53909
112	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x57940df86d177b264ab7df35bed18d7c80b1e31c39ea62cfa03f905e18107b6f07aeca4cfc146866e542414514743388536d0d6df11c70b19c950b2fc84b4d2c	\\x315f9a2f1502dff1ffba0fd34ef1ae1b7a1843be32cfb5dea2fe88224d13feef93215987b6d43f820a401607400b2824d3109f8ee3fc924af0aaa02d5121e40a
119	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2b2e512e9403daafc789747934c8f1355e72fb04d2f6ca77760abebca8b4bbb9c2bcec9701ecdbc0aac54935252cf4803c5ea3f5024ae4b12a345f70437e07ee	\\x9dccfe4266d030fbcded0938703a717585104acbb7ead67b98ba4a954416626f4cf79bf97c9ffd98848fabf42cc64be9b02bf8d7d90d0e23bb76553abf146b01
125	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4a50253989dae5372cbedf7fc3261eb14c217a5023ed3b2219e8856aa234bb2108649b297ec097aabb6f13481713f455d03e348bc4f160b2459d9de15115cc00	\\x73a8770545916542c34c9c64bb8f9a18d15eb22c4822bba6d903dfdb0c33c686e1cabec136ee4e790ecb4f247081377747e5b9eadaa92ad63d1606a72b37a109
130	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x369807becf9eafa1b882ca00b65e31ae34b20569fb0bd1315bde2c937ccc1573bedab5b9f1326d26f699c1ed8e896bd392b5a9cd32ba1e9c9ca9c0e5e5cc4988	\\xa5a7563d0384bfc343a86ca2284fe508640713a5255f05eaa83253181e60a6a35a91be02499feffc28eadb9ce3c08c4cea00c6922588729d46039264e9b5d509
136	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0d3dcc89b252859878b28233ec9ecc74e8bba5585623fada479c77a2df0903019bfb3aef5e574627ff2bc84fa8d8cf9cd10971e402220815854ba4b687e6e909	\\xe1b35b9e83ea15fdfe7470acab8d45669a66e92d976678ff4bf37226ea817ae6e9f879b1ad6cfc47b3968d5c83c00da09c18d5e17eb69836a8b1001e2d6e270a
144	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x874e2362ca04a40e3cb2102f709bd35ffe8c8e199fe07de724f678de184c843db5670cfac6164219daa6fb6e65a6663c81e266a92a9b326553a9a526f932dc77	\\x88ae9f4c1f4d269b762fda3158d50110dbfb8dc9db371a773308156b39f6d94dc9b53e18fd8d593ae5910427f946d40137a59481f6626a5a97115cac3d1c1100
179	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x85a17446af39e40a2cbaed3a389c10f37e1d0aaec9e61fabccc4b90ca91636b4b779ac210b25346346258a8afd95c8235239071b217615a324e454517a0d5be4	\\xbcb0db2a99ea275cc8fcedc3db846864c2a2c1a5b7f4c4923ae982ad48ae4f6cc82e13380e13de3d0e118289b105b4951d77cc014ed97eecca3e386a5f456302
214	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x99345ccb34432cb81610f1a31bb26fd593a6122d066e35d822ea30fb0063659171f7611189cdd8934e79b5c76947c88900351e535e9025c390eb71d9d488513c	\\xb9ec2ca90f49375467890540599aaa3b64603fef378f3085435097c37c2f246ed400a0490af90b2339544793f95f71d0fed30f8083b41d513ce40e5ec9fee604
271	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe71355cf36e396ce56dfc148fc02556fe5217efc2918eeaba2281b77c73e3a28efa682728adf02222f5fafd74bca411694a3f787cbcda9e87f19cf70c74c94d5	\\x5265747a491c7c42e5e6243c2861dcb558f0513f566cd0db3d96bc9118fbd44322e6f0721efbc72dfb506ef1bfa5f42a0ccab412cd70b0db572e1a6d8461e60b
326	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6b641a63004c7108f5f279b19ed378dff07da3d3ea76943c5cde33e09830ea16bc6bae407493c91d6d4e33541af5abd4242f94721a74b58131d378a8cc48aec6	\\xe21849f49c7fc1a6f4ca535405e636d0fcdaadfff341be4cfe8709f2b5248c03a8f30bd8e6fecfb5397ab2315e7918a2d6be21e983b3d5789cc6e4cacc1e7206
338	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb5b1548086a7387fb82e596d9b0dd84a029ce8c9481c3f802465e7ee1d32cd74e68935e9141206a1832f11d90c9066d35400255278e164e595718a85a823a991	\\xbf6fb478443de0d5ec622d6c8075c3273b9884075436148aba0e950d21219338e8c8b19974ecbf97f6015534fff8419460b1683f57145ccb33d91e0917b61e01
381	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0bf3b77db10390b285e540988ab8f1591c1117e5c9e9e6dbb6536ba1eab9dc8a711cc767d02c5d8fe3ffcdc36f759d56ac6f07faf0a12a2fc26e7f67220cc86b	\\xcd48c940bf66f2553072f323abea0a7ec20abc486f1177cfa0b71c2fe5cacdc4dc06b8dc40197760ec33b5e90ee74f2bce903a841fa00f9de6736d84c089d209
146	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x845ec326c51ca8ff9531984cc14ef90bfb26c33fc0773e0fcff8205fff71f7522d7fd841686fe36ff93a149b90b54a0d17899e140a2ac6f6bcabd4b99fd9d851	\\xae0f7bb58f61460ab290c2ed50b98964f1cd8aaa8e46e37c91d5ea122cdebbb7bab9dce2a402836abed314e7f782ef189f7c8c8c5c0de3b8cee2c0c3d502d90e
199	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x26d5d348eed0211cb00501e685249dd3869369d36bf525d0f1b16b539341bd3c697f2f352ce0608cd1bf2a6348721974c8f8879fe8b95499236f9657a855857e	\\xe1ff19055e4f330292811a63824d3b85eb6c564f83dab5d758f318c908b9cfd741d4aaa80b6ab500cbc348b04f57a499b7df888010bb5ef7d1b76c11ffb46104
215	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2778a077e5dd7fee0ada34869d476e5835804fc557cffde4c3d43b8a664a99df3f7eb0aaa20a2da17930ef051f4580acc175792619b0c94c3a46938bc7591d97	\\xcb539398375764bdfce5876c16ce6f448c2345cc6563f29d5d8056de21e843d05996bf8dd8582c03f2a061acae22e3eae850cf4fefafa23e8d2c29aa9cf48a0c
258	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcb98c81d551bb6f9e65669354a96d4a87ff9ea2258daeb6219a95da48b16a025aa673dc24a2978c511bcd93d26dd8bdb81306bd1ead169c518c0995e347d33ba	\\x8e56d219517e4476d68176696986d6f5cb1515aa89c1a591643bc01ebd03a60a603bb6ef5003fde2dc77e97fd5f55ef8547ad054411f4298ac00856f45126702
287	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbbc90a0b9f1861b0da55f333158bb3fbe691d861de4af111b8d7985e9bd2d7ef9ff02d1972eedfc754ac9d7479b88735cc34e78cf518354f7ec6d126f27e43c7	\\x0fde83c9c89f539112facf709918880ced94e1964da9fa4799db8632aff0c0012c609a7dff1883053247aa618650bcf07d81ea65513de2831dabf1b29a545c04
323	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8e7d7a7a3ec827131d1682a14d299b6e0af570d33842b6e3884e0ac68db15fe1002c33df362c6b126b26cd2c4c570986e6bc279cf28aca89e10762fd75b29015	\\x68fb4cd279a734fa6b065b65df0ed7b78b094598eb8249a61cd3f467c1cfdab4269d3c55e5e5a7de24632f23e517de87a7293a4ebc84aa489739b225c2e26708
361	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2945980032fcc35e5a1cf6133a839b4d9ec149b2de93e9493f538a691f457d042d72c831aaab79a92839e827a78e8e070250ea32e6d2006cf2e529d16e6a71e4	\\x35970b2b076e9362ceb18d84dc2ff958121a9a966cb40cf2494cfac407f99838ebc84ca8934930e6ffd40c276e747f3e8d91a48236cc752e02d0981c9f877007
378	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x59d695c3b9bb5fe4b05e1fb6716d38a956fd925b090105a8f81b80beb25cd86b0b6656e61f1ae745210ed82689d09a00389315a132cff94dffa2438d310c6ad7	\\x9b94ba67f172f936678e5cc186c513b23c756af406178c54a1f5c79b89c28e12e8466205bf9daf288a8a7d6cc9cb62b245b376d94922390e008206815daa5909
386	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3b6d97bb4c6719c8e47698faa3a1241292b93659e40010235c4f8a6515a43e1122e077766c982aa94d6898f21ad38aff150c40625063ba98f3ca7bc7f33e4f2e	\\xc4ca2d7a23cdc06710e1a756ccf396923a7b4a6a6845dfe049e8460aaa78bf45b06ab57e15a38d45b0f27627687c14601b0c3f488dab50f164a5ade0d8698c00
147	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x86aa991d57b7c95890cfce7385e960a9f80ac70a4c3b7e2bc4227f5ce751e36ccbaf63b00f0d66a5881a0a9c8748b944538e49e2f91f4ce5adf5ba513ecce618	\\xeb3bad5d097ca1679d8b2369506b60c421d7c31e8f0fa9db11baf67bb8206928bd412c6a2b089853241a42ca3c5312d7ce171a47936a0c35915ca5933fa1e702
197	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa309e596cca78046c1c45728315d1b138424334b9611811f6d264e31fd269e4729ca88fc11ff32711e5eb102b441e7cea3d4ec4d2663e13a7952d2966726337a	\\x4987a83445c54710642f1ced904914f1c2684b60a60618fa534843400d9f0c64459254001658c94e0d3fd6eab2db88b6fab66334534e5bceda110a823a069106
223	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x64169a2726dc586aad670d78d098f53f7eb772b06df838b4ccd455f940707d8012ee086e52f8bb70a4c8e801496e223bab1abd5f384f135bdfa1fbabdfd94c8f	\\x0e05d5390475fd7d03d0cbf22df6c7b1e1b9752f584f8f4938f98fd72546fffbeef5c729b6a28e16aa64187a1629f395e67dee2d5495c17448fd187975967900
245	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9d3f339b1df325c6d11db1e94db5398f01d8785bf5664e022f6ce3d29cebea5b79f0b65261acf71e923891ad1b843d572a0f405e63413fdca6edc78eaaf1b206	\\x16f21fdeffeaf4a67cc78c76f99b1fd4d5535dae8cf72cc82ef65cb771d183b12a0f6b375e50a6b6fdc2e50a565b3334ea2f584b2d4639ce7b1d11f3d00bf001
282	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x40d29d07b37728c321e14e56f6fc517968e376e9e34a6922d13d5a70d72004a1f106032f6ccfd6920424033b555f4a9f837611c403ce4edf0f47ea0541ec4e91	\\xfa257c8c0fd99c076f1a651e6dd9c3e9ae7bd26179f4184ca4d0c2bd49bf11bc6c3bd38de9d9481881c4ec6db98f31f304109055cca56847066300a6c7c89f01
295	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd6c54bdc6167fc4b4a34819cef25c74497f3f07cdc00f4222a776228a8a49a09a9d53e15322d80c19de23674decfd5f8447d50708c9ca0d5aba33a33f9931540	\\xeab992ef57f9bab989f998d2d67b54bcc860dafcdedcebe209b6d615aaeb497badf43778cf437f1d6264dca78efd55b0aa388abfcd4819c3d7a0f7235ea84901
329	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf4b13383c7d276483c0895b2aa7dffcebe64b26a7e57d40ace0e7eec795c090f355465f1182cedff775eee2f061af92d9d886be7cc16e4aad6e40bf6bd0a64b3	\\x69c007b682af7f979bd63899d7579515d32ca9d4190a2fb097a07e5ab8ae6dddaf42e3f4e8f79bdbd8c005b74f8e71f6bf46d07e97bf8ae18f9b907d44b85b03
419	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc726b8b5daa69fc80a6c1593097966cecd414697fee14d2946bfb2a0fb104a845c7108a07b25301af73e4e757fafdb5423f999b8dbfebbe8bd8db365562e1116	\\x6b8d21386c7e8a1a9ed0f9c736018eeaf44cae468101e5d2aa17d7e59ccf73ead1af95a73cb0cbcaa7b9e3472345a5f17b07913d1f043e3cf98eea4209e09d02
148	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x78cf87512e65003a3da1e8251241c4902dbef4777be1a1016dfebe63c51a4b9ed45e4b08b768aba7f7ff13e86a814939ab2528d1f7d0ef586f30a17705dce12f	\\xbc66819eaad86a9f8455f45ad8f3bd0a6966d139d5fd8ad52fb213d4e01c5bbf0a41578419a5c38f8e2d06479e966a6fc3caf6d664b3c79bb69d989b0cbe2b0a
184	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x30cbbe200c09aa2e3e3b55d5f7f18095aa0ff4899ff827c8a13ecce5b8d516b5316e610c3c2e7647962936791d9d4d7934c3d2a3ebd6cf6589dd76132d476e8e	\\x6b1b35a7b5e0d75a4f25e7a7fc7c16ef7b240e6e352df9a9fee40800c0fa35c6b474aba3114fe458cb03f222bb892c183a6284bbc839119c2a7cab28ea5b1d0a
226	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd06abac0bf185e173b2a73498e33ae540dc460eca0a24cbf04a3181222e4b6ef4387103592afdda23da78b85f367ce9e904f2edf0f23d435e1afceadfb672de3	\\xa327463000fec5ec6a4f08ca1f736e559aaca6596776321421e66cb40c60a43bc0c08cc261d343f1e95e82e924fbf44f0d021a7400dfced9497f367fddaa890e
253	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xaddcde70297363d4b436a620ef1fc1bb023a7b034e073692a3b62b101158091632a5205dafaa0b7a311ee3c0eb1adf569efccc9910a9ad32a5b9e7a7d24c2e15	\\x60d9d5196c999b1fcbbdbe26fefab6e05721b8ebd87a4d910e9455317e665127b51310823e076da7dc291a1daa31a7ecee13c5992acca003708e929807f28608
268	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x62a1d2654eabd12a328f16e2c78982361f6b68d1a000f19eea3f349c9f34f850b59f392d3b8f5b8421b6a05acc14e0d66b48c925f9f5b4b243d34455210c707c	\\x6ce06966a5d17c6f3d63f372237685d3a9c31e3ce9be74c8905c3ec5a82ce2e6835675e613404ca52156974ff2240b612302c4e2ada1ccffc9bd2230db65700a
293	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1f739187e977aad016c70fe3299abdddc595ae82293ac34e426794e4b7a6dae108dd81dcb4590b4b34bcc6145c4cb6efc17ed29018efe237b1bb2cccacd0392f	\\xda08a7efa0d8beee43bc4a671edd999f90380fd3517e2e408bb44b7af6fa96bb59c7784e84a6c1a423a283e2c044d0723cd49de14138b8c3aa6362dedf01140b
391	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc26503d03aae521e75adb695a4d8ecdedf23fd21348555c0a138ac3b5ac9773249bdbf307d2d29e9ce64c6b7733720f14dab34d7f38df003369df443de95e68e	\\x09df9e962aac560425e920a7909eebd0c7460362ffc4bd14031209e99873c8d014d5fb67957ddd703f70f3343569c0ab230311940414d80581b4d2e3d1070406
400	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3e6496a84bbdd7ecd8f1f7322b42728047ca2d48216d8e88ac0be783ff16cb290ca7dd45798f33b62f5587b54555baf2b4f866e3136216937689099979511f7c	\\xfac260b03d41cee0d4f058806babd7a7d337f44fe0c4489875e1471a7265dd801b8802bb8a475ce823e44b89fc9f27adffc2fa10133627e2472a59e2c9d5a600
418	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd1be75e0355fba4ba5dd09bae8534b4fe2bb9749bbfe524c9bda6bac638579874907bf63ff546480aa40f7f83d5a597247a2a33e2de7f765c1ec9fae5610a3e4	\\x427c45f792a53f9a81cd75bb930e8f98212083fc91689f4b23dcb8520a91337e695c8b2a0a9009c511743134956bc797bbc4c21753e97fb40ead05295bce9705
149	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x62aa17d2762f1d4c0329a0fb06dd68676d4efe8f0acaae008814259d16e64cb40138fe03d8f34ad58564af86c589acdfc7ed777dacf15e84b2f332aa19218a23	\\x86a100cb84ec05d843088e98f4632bc43c04f6f7631190fe46407f0b49edd2b957aa6bcdc95338377ce418b2f4e3117f9b08b06f7de599bc4a976fae08979607
186	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3b186af8e2846647ca08176a42eb8a7fd479227b30b5e8fae2b5bd836a3cfa9a3652291f5c0987b119f6a545950689f7ace312445825cada17911e9f4303a9ad	\\x6df13bcc4b625c9f3c277244ff5501ea4a08a325f6d79ad2253793feb1aed1bdc1f6f286080e913442de64b09930547f816c06abc142a445d243359f1c455300
237	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xec38b97404c6b4afe6ac879b165423044e6eaa3433883ce703f86a0ff1e531587107d07936b543b7ed60c66de1c335fc9e162b2c9957d09c75536e4863693110	\\x9d3ac771c60caa732dea1b174a764c32e27bdbd0f5af8c3146483f3cf8960ff05974b146b0561cfa6f1c9ddde0d5c08e12e369f686412e87af12b1af18268201
261	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x12ddef7227139342e8ef715a7ed45297ee9f92443e7fe195f32703af2d4202f7f562ac8fcee7592f575f49f251a9ffbddd96b2c93807ab377829e7fbfed5d5cd	\\x83e9603db47803d1522af4353fdb3a84935d564bddcb907554ce10ec7918d1fbc6d5f1479a3ae6727f03310bc8d07c49fe8ca0e530d8a64416d8eed8559ea900
276	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x97b7df6bef8bc5193254072c65f699b4cb85ea8287a8eef752e46af2e3ddc2abc93ad94f139f5e584e27eaadc48dc36d16aac19433418d540729b68e3da20d80	\\xdad417f70077705451af48802be23deda0f6c437fd385f674ed7ed95ac9c03da3c93aea8f894b3e2f84c2e5104a93062614c9586033c2392eecf76b02632740a
294	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd205bd7b5f8474176582664685ad3da0ba1c13c3540249f8aac4fb88406f8014502b4ae7b4ec083617cce6f638e3ccf9e1e405d252877ca1ce87c6b2f5b512c8	\\x7ffe0f39c1096d21aef7b6b212c4b2015299a920996688415ab9eecb72486309564b4c13574cbe0e46ce2283402d77f13115cf0bf4c769c008db26514561aa09
309	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x863d51b23d6134b3087bce2cfe3408a20f88d891ca86249fd7172601c1581c1848f9f7536abf4d628bdd1b6210b562a4dec4349510ce0fa950618a37af0fd402	\\x7777a04f82a8dea14b7b9354e07833a6b1ca15f79e100c8c5d6e4046abe4483cb9cbfcac3e8c30f7f7fef485229b69586d5ce918d488c15a8a97e27ccd950505
351	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbe4a5f6e9058906384d1c49f4aa591aa3f991ff3f348603996af564afede631b0e641ca7b8ad29246b65e4caf22eb6b2f521e629a159ec8899abc6b2abfd0869	\\x0de0e01615f5763e7fc63f13cff42b843ac6ca9ef689e924f2adf6d5853d00dbe230de1b0154eb1c40ad658b12bdd2bf2ef2e538e10e997d120607d497762d01
369	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1732e3ea1b05d700b3898caa3b965a148847705a5cf8c617f3ec28fcd598f9b8b299b555ff8d36b85a9d73210241ca0060b2e40485478717dcf5af418142b8cf	\\xbaad74a388c7f46d0d8dcf9a7c958e1455182321aee0f1aa9d7aa5136446e3a4d1b28f7a3a824a247e8a42156245eb41925aaaa216689f59125bec8113834207
395	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x65f7b642422ce69f8d7a9a36056a27b0d75dfd9b25270c411c71011c3cdc1a3f794b13fcd16b3398719a4c21db085cb1b1eba89705a55af03256896bf59620a3	\\x604dcfb4c7bd74b7e88ab177efb44e4ce259af00fc35cbe12d6f9336fb0bde0c0b8f02a722f6474edd747d9f5157e3107cca9b83d11a4d1a882d714d56aa7405
413	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x43e0612bf97f8431aff08f434a6a4a813e82754a676fd32bd611a128eb6a00e7989077a960ae2f9c647356eb8169daf6571ad9d7e6a5f0b2c1afc4d83b18d093	\\x4437152fa1561d5212096eec7f39f79d22dad67481a743380668d45785c11e7127abd65b16f5c420670e62c9daee77d5cf56d2647185ed4e112d37adb616d901
150	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\xae8f67c97a992665f7ca55c9af14842a629e854a9b8f11a79b226dd4441952af1233a2bf3abb94204245db82a809b18d4fe4483b2a82d173a53b2250f8ad7809
183	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfee29a7def706bc310ec6b022794a11d5954912bb429da0802672306673298dfcc1da48738b5e1c0533bbdec6224f34a5e80aa363beec9d190993bd225cff6b0	\\xbf80ac7e6c64a9f5d03fc9f145eea20f21a28c89d381173fec0591b70791aab0acb4940e1b42290552c15a76827206fe5932778f077abc4a6e85ae06a3083505
239	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5e8a8b86e0e9c9ba58678dac16ae91461dd014a12ff2871ecf80d24f9a54d46decf0182322845651c6e90b575d8c8d114ac3eb4caed5a314278a7084fa6e4d86	\\xfbae6cc760d046f3fcf54124b1e8b7d08e3717787844b96f48d4bf1a15f90b633b75d8615b60b4f601db1b186839a5f1399b1e5e3f846cc1b97b0fcf7b024a09
250	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x21e0907d79b5852e0a96c2a925bd54f480e49a3c33aace34b40c8a8c3dc12f7d09c48f307ae4d293cc85bdf65c3f1591c0e40149e9433b4b256811a9179f7ca0	\\xd9e72e5f5a4d4abd0ec33f9613864a98ed3e97fd4c544e0dac026b7ed40873b39eadb9456e53de709b8d53721be0e2cc21ef281310b3b148ac318fe359106a07
283	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x220053deaaaa4e6f5afbcb3ee3d3fe67981ad36defa45d6304edd543fd8ab9aed5484f2cafec7193b7771566e0f0882db42d1496c34f153dec75e92bf04b5b54	\\xd97b6c785248bd38edcf7597e719548f55b53a3fc4f4b4648d14eac433512b5c896d6cb49a812bf7989bb3007d8702cf411eea0c8e3610e857b492c374589b01
337	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe429ea03fa5262480b1f7356d1a26778abd4b7bf956c88ca16d3f8f9556e195153bf116b672e04b7b9daa08f61f303835b85d73bc045c45cbce38cccc5b6bebc	\\xf87e23a5366db74e1db7109d04fb27c9a036caef23ba525e57c499511517a28c1678158b6d364540dd3284a152e3495a162603e8f048224760fb89dfdc33f705
377	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfcd83e754c5ba5f2126fc8206995e1f9ac0522080415a3bb05a6742fc6f335e7207399f99c61b121ca9dc7a5fc78c407f723d291bde0bd2326f7a017a0296439	\\xf9fbeb297dd6ba710c244c3b5eb2a01d70fc297a1a12f5233255e843c1aebfe173316a3a4891a4b213012779505ff69ea1fcbc9b98619e10799ac8d8dc7fdc00
403	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x74e09dda1920b394d8cda25476c542a46d362740225fcd990b0a8c5aeb31c3045d41251e5cc3d02cb7ade6aa6808dce37ab0fe06e8445114450c9bdf736ea42b	\\x0cbf265a4b81c2ded51d5f0663c52563df7bccbd27011291308b6cf626e5aa559e46de6949dd17d2231ccc1e988fb7288972d86d7f8f749011f7b52124fb1e0a
151	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x93ad9de8a46c84a2cca4881eb0d4905bcfd737ec1ae6ba645a38aa649341869ba3f314212d34b966134f30a6807f5e81cae15ad0efe6f4f7e79559f70c627f5f	\\x7c5a358dd6764ace485ab54bb9c47aa31beb615a0b3b017b026aa11b0919e2b56620eda793fa6719d1654523fb8083fa89244846933ce96f96fab6f198a14906
196	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x01b6221e9bed0b92f73b7c7e0dcf431fcf2701f1ac9ffb0302de702924bf01ddddc39521a69132d41746d78f9c4c68d2105ec9c05c8759e65760666f21837cd7	\\x977912b9d614286f846350b46aad18eaaabaae8d777ed0c0428857f10080b37c7ae04d8c3f205555ad14e7e9049e9a4afba760fd94b79f7468cb611101ea5f01
228	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7069a935e2ab96495210811d9533e53edfc6c8be9ddfa0f29689a80536731a846dc7d04696af5361537bb4777267218a90a57293819b4546537405b01540510d	\\x0dcfad8c98722598f643636872ed471188e667bba2bb591affc835325edab01d4e64eafd01fbee28ed84d6e8f481d8414413dace21e129d333871c40b5dce102
267	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe2582df71cf325a5a947e9c3fec42f991836df3fa663f8972a4d97dfafbf8e4af30a7b33c34bbf48c5a76c64d45492cab9ebf8eb4664c3516fc6126660ee26fd	\\xd58445840ae97243266f895871bd90437d01a4bf6736170144d72e0e08e40981af999d060fd444ce2df22d07fc1ff2fd4e8acd0d504418ce4cffb85198b3000d
321	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x289ca3ccb60af17ef1fa93e5a94c427fd865f24bcf9a211bb6561507af15186401ab40e9702a2ff3e40d32d70aacfa57ad68e3752e02676dd863a178eace942a	\\x270969d1c94237eca5dd9fd083a5a4daf784b92c4a9af130ca118a834a80eb234225b0698cd66e66f818b15d56853e630266be0e2b0603c4664f003d42869d04
345	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6df497e0f8e6e60125628435972e5a81109756121e809beabdc015a3994d4c3864c89a37c20d43cdcae1a0f8db23121720a465068c41093472cb5193f8c10838	\\xef3653b9805d7387b0c50bc55d80405487fdbfa3a9f8ca5fad9af04ab462e156219b431ccdb7ddec84fbf18c99b7a9202defe99a75f3b105e77859313114c109
366	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x388378223b16aaf699aa9c770c6ba87715e1a177606a5a5164490c505c98dc53f7083c0fc5fbc5ecb1e5eccd035185c5b694a0ce51edcb13ed42aa7291523c3a	\\x8c05bcb6086b1effcab91ddc1102241da837acbaee24903f44f0aef0e1259f3b7d92a41e27c2b6fcf82d78c8de74ed9663bf2cec0027087b2bf0847c0a01190c
376	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc5c7f00a08d738e0ff5ac32ecdd353b716e134f1da686983135273102100682d2e968af278ae3fb28a472816da389ddd94fab6fca48fad3c4d471d891c3c764b	\\xcb6e635f958e2f65aec7464022650426436f0d30d61099cbaef841b8c27172bceffd8761b872804b5a92739361a6ed6bac5ab479b6b216756f3d27e0214ecb08
152	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x71e1d2bbb8615eafde7035f3569f8b9e440daf745cfada0cd28abe78f9b86c1e0c46d1b5c22af192f9cb10d9e8b13349b10bcccf9f848c6dd3f342ea74f2d6a3	\\xbbe7b0e415b0c4d6f2aa51f6d460a50969900746fe1a61927daf36460888e7dfd14eb304029bdc467cff0cb05af2428da5acd83c3ba5a3287f16af25a1636909
176	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf2b9c08b78ddc6657eab84aa4a376854e562b7f8cdd0eb9e5f630d2ee5622b56f2736469b5f441dd51a25659853c4b9a2a2c0691f5fa048f4a077f45df814707	\\xe0170f9a7647f8e365298430e0b34270962fe602cb3f42d7a7680731b499ef0caecd82378a62d646c091aca126f1a4da63c798a1595f8911869e3f00cd90de02
211	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7b1df95e082da24e8034203903564e07e1b57fe31dbae203ea3cb89fb042976478322851bc7802864d1dcac7ec8901785ef9d562f81e43d3527c27bffccd151d	\\xc265064e305ed1631f1ff90ca6df084d77f8dbe0413bf0be6af9d4c58d976651ed682dcbf23e97796d66e622c8f6fd04aa207b312028a8b8d0721f43fa318201
327	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4281dbb93bce6dc2ebb5b5ecd2d328c14dfee84bddcf9d1b8ee58439c4e3e17520c75fab4825391c73c654f32d80b0dae5889199c2327b7819ac1b7d0b675cd3	\\x2bb63f39e74cb55a98f0d51008e4ea3b678cbad2b769d5a140ab669ed89f9662bb986f5a838d9478ef78819ac4ab147628b38e99110ca51bee09cf2ee2ca840d
346	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x25c50cb19be925d86bcd9eb4fef3aab3400641c2d8b005e3f4f6866bac0b932cb37c71ac9ec3a97ff068ae127f352a7a6563605c5bfd0b9b7218143ba1387fd9	\\x1f4bafed5204ce171ab9965c798d2666cdf85eb6fe1db631d25b1774ee21071b662024c353737ebae5fbe2e8f057b831dfc60eab28a8c3b357d2d78f33eadb07
424	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2eb6a4bc0da958063937134a5a2fce52ebb95e1d517cfb8f97175e5c33344e607a306bbfc403ac4a96d05634aecbe4a2b953355f7e3236417fac99140b563334	\\x15307e90a9e032fcff6c58a7bbe52961b4d953e548d3d8dc0716d80663b3260d057ca4077a767ea2d4026788eeab1506a6622181c220da5a7338e045ad687607
153	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x421f889245c5e491dd944d52e84dce8ef5987b24be54b4fbe533a42f9fa7165288feed5b1301f33f920d008192d2c7b7f411cd5c409e618952ad4f627aa84779	\\x93c2913dcdd1f6cd712ef599bf1c84c1a72a4b10b61a6cc73fabd9316a00dbcd4801d02f23f2342a9f35308fa7a8c794b34826140ddcf359ff97775e4ef6f70e
189	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x86ec8d425da387a52a1613685c454500ee274abd2c01b00ba4002dd0ee0dca4fc9a62cb1374db04c614f509a39701fdb2f0c4b9d8eb1fc9c26503bd48ea4c904	\\x5eb6b327ae4c3e2cc5429e099e00d825eda31ceaaa8a53e7429cf8e278f06849a2ca9e2babc6d7b0447d8296da0f4daa0e2e7660919ee8610210ee4c3cee3d03
238	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x774d529b494fd10d67d1ad615a3b9828103119ea0e8e77a00cb1b6d92270d6b85d62fc9015963005696c9d7e21b778a52dec6d2c2690bbf50d9838284c1f2866	\\xa9c23f84c931751f686d4a3469f6a7393a8d3cdc748e3397e6203393e4d7bc89237c7de2913b6f8492bc45d0734528b04a857111be536ef774950bcb349fcb09
246	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbad79ae2b69c9a3d7730d10e97d728b428d76ab16c7a2b9e00a55829e8cfeaded9b1c477884e2e7cc4735d2e250f522a989e1e394fe9e68174fd039d09610290	\\xa9f2343451874a446aa8eda45c671c025879da224aae52072cbb9edb17361ddc341dd8b5fb43def8e3242c38f9fe138a7e885a7a0a4bfb5fd4e671ec7a721100
286	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xacb7fb568fd94d6836e0892b5701364fe91189c89237ec31f6f83cd388f286e42ecfc4e13302b39a648552607db68f5349dc7ba05466ed671110447c902765e5	\\x0f3ca072e9f4f6062233deaf745303402d21b7ed90243034fced1bb586c52481f86b9b731e1fabdfa79f8ed97eac3f6cf88e2410c3339b0777d82e0e0440930e
317	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x07a625f0434885c0d618e536b156db59ec7b65b153d1abd2886aaf124020d358fecbec3c9be6073e940ffd2aa76455735481c82b0e21c9f8d25d68b19640db4b	\\x37cc9b58b26f99da3adeef6f7776fb4e6e862e2130ba9733e2cbb3bf144773550884e8488fd2f02db582085d28c6580e4f5d322f021187c1d04b30ef69912b09
339	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd52327998c894f146dbaeedd9e8dc17be7a98c5a214bd0b895a635cd16408206284ccbce46555909047c9b9cef7dd694eb5c4be6701125b72dd61ac35bbac6b0	\\xe7582e63bb046fe850a70903d0a7c5ed781940546ff331d04a55935b932402ab02691db250d4fedd60a1e9d4bd5613262dc9d8194ab780e9ad67db15cbe21f08
352	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x957b25989394d7f481a6cb288e063f4064cb8979de04be169463ab88bad662647099a97c0246961ca91f4caaeafba1754c06819299cfa46cc021ee5cf24ad3c5	\\xe6a68fd092458ffab710b36b9646dcd2c89f68a94ae78a3fffa343eff77a277ced4c666a9c5638a67d4e7bc0101dc4640a2c1e67c5057c7be5b464d943ad160d
374	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x87c22ecf187cdcd4c6fb60480448dd7557465da308b1f1a029329738db8c60b6c95c04712839f8f240082f50711df97885f83b9d3767f3acd47a1c77e0b77c95	\\x0904769efb6d1562d2f2b42990ff315dd93e1a907dfa7f07806ea8000f7ff3f1d45059b6248178aae81e5f8bb2cc66ae5bc3bc86b134279729c17219c0977f0c
396	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9c94c643c3c7654cbc2d18dd6f954f5275fd4a1e86d821e565cafab0d8a0fa6f8a98558e711d6a8d15557529b4a5d355e78138f7d4bec8ad5875879c44a163b7	\\xb8ae5cbbdca96126f51a44f39f241f0db77a45792e3edf3d2ad4fd9c0860ae78b12dea8204dbeec29d077c5e1ac4613b785376c115e78ac66090c00a6b01690e
154	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb6495587d6ced77b54472b526148d85dd8557fac52165f66974397a36da63322f928813d42305aa86892d90b6659e7741efe2ff0cf2ac7f930a35c45eba6a884	\\x38c83884339d32385ad47c51c686cdb1c23081143ac6499dc5a512e390887ab18ddd5ac8c2fbba3b0b1d6c637b28ae7f0322b409f045c319fed6a8007f3d6f01
190	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa6244370268555b11f67a55a1a598c2a1bec9cc2d40d95695b4873a5864852f93c033e164dfe24c80217b44e38061066122450134a6687561a29f2f4b03f866a	\\x4cd88c9218c46aee7567a8dfee54ff77e0154bd9a990fd4097683c772098027d708e0100d5e7573a0c8060e07390ca039bf1ade78f9e43410d583515b1f16700
222	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbd74a080b6e2aa36653ade8b4c04a0c84dee37ee8a83c8a8d1c5fd2624906e43d0781150dc2ee5ff6c98b2995ff14c2281f29c0a11b7d91a6744d0116807a037	\\x5096d4086fc8dce3b645ffade3b3142237d2b55e02f8f7dc8d98ceaca27170926290b9e26cbb6fb17612ccffab75ce3f1bee973bf1391cc5979a20d6b370b104
266	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa1ce0b76cf62eaf5d239364da44a6037ae9116f1b8625ef70d188be6ad180c6d420da79d584b0abb514884d0c2d11687bc123c560caeb99fc013e69a3f25cfa3	\\xcae64aeed5661bc1b0ef6bd78525c02c57158b6de4dc64900f3ff41b987b3bc9dc675c46c159fac681c7cea5e781ebeafcd42247e308574204bb185a94383c0e
301	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xeee83f98db7e7d7b37d93b6e937fd723a4cc94321ce9f3f58517ddd790e3ae31d2307f1a6ac4ea7d5c3b9deee7279895ef1ef39c6b6375844ee0be2cde9687f8	\\xd5049932fd31d5fe881cf1175aec6de103a1ce1dc20fdd76984eb71dabdb17146a0545228aa89407bc795699be5712ebeb94b5989f3fe90c4e06bd2292fe7000
372	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x060ab809ac9fb4c21adb3ada8df74606003be3923f1ab60116fd243aaf7dd0806777ca661436a209b3dd412228275c42040dde969c2eccf0c71591e7ff013a66	\\x0f4e1149743d066faf897e7b4afbefdbeedd235ba6642b443cf15cc64d5c140bed24b154158e8f8172a95a375fa9a2ebb55c173a61ef9407aa1825ad499cc00a
399	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcca3be60b12d904fb49e7a0c5a031cb5371221299658462cc57bce2073ffff3018d5cf5f3085cd3e5067c92aa3de361299424fd0a45329c312e73054b23f6148	\\x488dea267196fc39e9ff80272b3d963a317643e96a84ccc923ecf0deca0166a2dc2ba62d8f4c05415aa0081ea21b118837c0bd88ef52c3ba2b785fdfcea7980b
409	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4c7cae07fc58863f55f24ff18b791edaeec3a7d36fd8d8e0ab0023508b8c1f05968c5ba4e1f78d103857ec8010b9cc8a57575ebb49882b557aff0c23273c3e6a	\\xb59b397da32a219ddc3e6467966fe478bf5338ac17fe8bdd2344a8ad83620e8ad5f950e468cc2febb5feab53e799850868219342c6bde1a73fa2dd7004fc1c0e
155	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8a4873b97c3a64d132cf490ea0541aa2719320e690cad74522b65a0e43f0cc5893b983b0c56290c447ffedcd6742a00224964b1ea505d2a54fa9379151dd884e	\\xab274c3ef8f50c1b0681f53d10a3264abc6d0de08eb54d3d09d050f1bac08d13ac3fa0173e083f7a8f589ab73f757c6ba9deda27b4d15f54d22902c70c896801
198	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3f87262f8a2d1039b1f3b8239167bfde66efc08dc86887b944df7544f57b1f46d00e98942bc7e1832d813d07927329e657c877bb2263b9d4f67fae15adf57a28	\\xbcb0dc8088e6d8928ba85cfe26e0c8300ce5e906fae4286d1bbfeb967b0dd33eeed159985900104becc65d2129cdd1df95cfbf984b4196b23fd823a9de3b8b00
227	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x421954d4ca03ac7ef4dfd2081d6bd1b920eb8a81d167d4ea8cd49d715101722eecc87e7a912cdba45896501ae25c195fc8cdff525125b0df73e055e8e7596c90	\\x7d3901eda81507f7cf727968c3aef835716045a034fcc0e6b607225b3690452dae093feba9d54628a43202d6832750aa5ed9e6cde6c37a8ab1b623eb6da8cb07
251	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1ed9f072c106e2fa582eda7ac61ce93461a7944b200890971e996bc8837e11b6e2ff74a45761d145a9cd3861b396331374862e3f13d1fae14f2f4dd43ea90c80	\\x333bed83171ff75b6fcceea75134d1d0fa064c5699333449eac2da4620be7341bfe8065890ef04632819f327eac1b2630a8020ef30db7f37effb82bb2f0d2606
273	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6a617312ba30ba53e963e31e57c80583dec96e639c3f11f7f9ca4961587f951c703ebaa84b88613707b26e2f9d1b67a41b7e26c90306babe391ac6f80540a213	\\xd810d048ea62cb8c523bb9c4a1b0c0b1c63311d186031cf91fb0ca18db866c9ea5b438af9d095b8d93708d3a777939f5b20ca959e9dda92f4aefa83b76993008
290	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcb9f2f84d336a958d1e98d37aa0f08dd9d255aa5b263e9bbaf58a630b63532b2f3c4606a88b4a89217168b5abbccfe20e9e632ae90e2537e72db47f29b76a887	\\x3fe3834ceef7881e8b2e47aaf721dadc9e618f93069ae1a47b1796eaaa5dcd80d090e81b35239e8934ef381908254017dd1a7edb7c1e9e83d0beb1bf7b6e4600
308	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xeb98c57dc039d6400ca919ac7b7e683cb16e7737f703c62eb594ff652c6eb6e19ba227b44205ebb3d2e5fd717b2495893472af10e7b14ff5a9e62b9c1b4059d4	\\x6b364d8d68dd219f6e8c22f86030f5fb1076de5aa182f57bc0ae353958c98b7399df29bd7fafbee1edb1230f5aa618c9a3d97a677cb20a8609ccbef58f187b0d
316	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2d32579c7213f81fe12d7af4e75f603cfd33a4546f90f3a335b90fadc4cb4bed9bc411d0f5aacf0d7c6599a024ad21fca3f96e694ff4478125efe448da126a43	\\x1a34bef6f8bc7a0dca2a9dd951090b78ec8d01b85250da13edbbfa312761882314dfc84737c1d7607f1bf5dd16f4bd30893d9f2798c8d43d62e4e6dd1372490c
355	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb212f81adc4fc67efe68f01c4fa281f836025bb97ad568f40c2d8b1f3ee377855380b405f657c7874209ee3d619d6b91f99b8b688b83ac04e59682acdcd4024b	\\x2fefe9798897d9b7a49efb71bb5b2894c7df3ede641b034ab861a95a9999aa03a416a3bf39ebedbf25865a56afefe396a81034f77963b9f6882df499a001700f
388	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe0a3dc34ae42ea111e64410a5dc0ef82bb0606769b3286cb85bb6feaf88f5390f44caf7abb040ee5cb62e44a08ba10f3bfd07bd7ed0c1faaa6556f187b1e57ab	\\x08f352767b5efff993c184c66a24a8a49d8d0434107c2a1a1296ec9cbb15cc778a7f1de15d87e27e444c27fa493aba96fea02d350dca56e1d357c604c10a5a0b
397	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfd4d1d4e55a83a3d1802ccd1f2cf39cc9c778e7b7067660ba5a7881b647a47c11877a4e0b681678deaa570103a652cf3a927a41c69a408c49bab1f8a957d26e6	\\x925fae964bbc3f7dbd092ed8ab87a588d4b72afefd04d5b18e20ed45b6972187381e17442d4038ade68d44b030e9636f2292615466ed784e6bc2dd4008ff190e
414	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5ee892f5c3b4a7b9cc15a67d119acf7c4cf8a01204fbefbed03cd9455553330d6ee4cb5bebfbd2163fdfdbf4bcb3554a0f735c1473df7621011b8627c5560c89	\\x902fc2242682ebf32eee544f7f1bcfa0001de4e4e11c0396666250c794213808c64b196b625aafd473685a7a6320d8e723f00b78664c8fc53777ae2da4be3c09
420	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd82d62970d2b4c5638c58036920550d5b354260684ec47cf7521d199e6ca09e92dc21573454e3f8c0c436af2fcf8f4f384de18f81002e2c919e6f1d2413ac72a	\\x593cf858a98b7b25f67f4530c4ba78b117a988cd8787cebbe2529cb9ab5d05aa62da009c59f9f1dc8dbd775769ad43384c160a762037ceca03dedd4b8de6760e
156	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe26488d17f09219cec85b4825589c9f7271be516772a15be85012ee05ee540bec4370aa5e95d78a96faba875d121d9c97cefc054ec6e701b49cc7c1f58f4d0d4	\\xe95adbe80a896c24a33476991ac830e4317c5f589df0d6a0749004f334a929e8c00ac811fc0b489616cfe4a207c434a3d62fbfe73e56a9a000e3c6825a85af04
177	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x080f6050d4ff6a61dd8dd50df4a1fb8d732de88346342fc09b932d269c49ab2d68c539d7f1183cde58a708719278724e9e177f3daae6600d0110d2eaff7f0b67	\\x5cfdac97b4c9628894aeebc6147844f908ba11bd3018eaff6cec18a87ad96e9e2ad4bcefb988c75f1a2a30612be6c76033c7fbbc20a51d91a8960d8ba9df2a06
204	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc246913a479e4ad45293065e4016f7d73a4d8e10c5234a6409908672d27fd3b49a5e860153ed927ec56fb23912d5b44966db5c64096deb637acf6dc535384e30	\\xe54f300d0d245b8cb0f51d4b89b8f19e9715e8770647066c89d4d030b1b47cd57a02792b577fa92f27286dd972aaaf3c67eaf2da62bf9e75f2f38331886efb06
212	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x44857cdb4e376a46e3d539523eb289503246d8f97d7c8c94137d5f9cec5a20d7e00522a98ee212ab47a3147c8b2e94e85231534c3b7ae9cdb5a9fa4409271076	\\xe0eeaefcfb1fe1320ed6fa576dbacde8d87dc308abf6b7b9a7ba01385eda22e3348d59f8122339719785fff3136aa662dae41aa71e23770a517c182be308020a
262	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc1ae4b5a9b7d64afc36bd62dac8874f2cde86de654ddbbc152b197069bac89f8d34313968cd61fa83d27166109f3dcaa575cd976d5dd52e4e2bc5a3ab2e99eb0	\\xda3722ad86563fc13bbc0880a5f3089fd2245c66d0f40d681385bfe1fae2420f5d5bd156ff8334522affdd6bdeb6daf698a0e3a6ffb9a746b9c8c4fe6b37af03
304	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc22fe494c119041f33642aaf44cf8f91047dc7169328d48a1e744191dac0961b5f030e7a2373393b1bfc9b4d57a7cf78b2c75b597cdd0d8992121d911f96bb42	\\x327e41eed53bc6139a04af5c6d1b2c38d4df9d7edc619d753cad729cd47fee85cfa651d6bce6862081c976c3984c01084a80e5d5348224f701d7e7c02f9a7b0b
157	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x281647f67e0ea767b47554fa4638c63b51f50f4454cbaaafbae471023f7e06c1cfda9ed9705226b6560c4b99d26ea1971a3a35219afead564185eff32460dc23	\\xffd13b979bc48a549a34925a964acc110c9552717dd6ad50e05c1673547c5c8ee00bf1088d09a6721c19e390ae05eeff22f66b527e2f31aec157fcd589877d09
193	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc5b83a18222119baa6a515fb6ab5426c9fb621ba4842add939e84b7a4578854e37346f2223da5796d39fda8396e137fead24cb1b41f7090f5a77c3662a081198	\\xe335f9c27d99b6d62e725b8374cb299e14a2a23fc857127aa51c5f76ec9c6cd7d5d2d901cceb046401c25f3e4c088880738585ffd95e7e0d6c9f77bccc13bc0b
220	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xae2336acba2fe048a8567c3613d30a5676b16c5ad457298124a4d17e349d2e98e5eec2200060f2bbd915a86a6a982c1dc382001657070a9d876a982a38560b21	\\xa4296588b2bfacc8c7ad9534198ed5bef1d9fe7654be226781b0974f72ff1ca925e792614dadfd0c85e0d6c71ba6f8053d2dec9c2ad879466f608e9aef6c4e0a
252	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x745b1ea2843ff2cd3ed45c40cf494a3a7d963eb4e200bbdb02004751ffabff77e7e655f95144b14dd9937eb795f1f1ba8b34d6d8f524107d0b1ff7d91a6b0075	\\x5bb08685cb264a59ca35a10678cedc5e26b1dec8c6ecb56ee5f3b823ce18ee1a411b35bf726d5a366f57e4ccf3d7f4c3cf108305d37b19c1ffcdbbf2a66ec804
299	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc7aff52849b08c73876c93538b9597da3a1e74f77035df744ac82ad60df219dfb2c544a46aee34441bcb0347cf0016ce358c670472a9e34ce36d1d08421c5691	\\xf635fb5753992545c52ab4c8be5050cbfd125a58ba9b2d4fd41bf30a38d5c4a0cefca1905e7b47ac12b000ef67ce79ffc9eea56b69266952828c1e73586d9a06
325	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x594caffcbcedbb6c2a1541c7f121bd13f0b1fad325174e3c59a5065c00543f7ba8fb77c02ea7c4351493797abd162564d7d16101d506fd79219e84ebcb5f4c9c	\\xf7ba38a64f0c792afd50ef2d9d656553b50f5d8b9cdb611dd1f99cadc988066c113f6f380aae679940588d5a353a474a3300ac32b8b2dcd550206ca07b32cb0d
367	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xac15d53ddeea8c09fc182327f0fea13dd755c6d977d9836eaa2c62d143f2cd298daef9a0ea324c2eaa65997130ffcd0aa8184ec9dc5b497e712559ca276b25d2	\\x3d4756577aa456082cd94b97ea54cc7e98753141515f4998176d5436749efe2fde8f0dd738d4a647faf7b22b1e09de848f5c111fce9e330b9e50a8b431773001
382	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x348a056c639088b85fc0fb48dea512a8404700433e42abca676e2b91449604d20e2fa51c12fe05dedb1af11e9af2aa681257bd51ef25c895f318c079d44a2cf0	\\xe9c0b2753db415f49634f319b4b5c6ec61cc57177aa5d8926d1bf27c89844c33a1c2e439661f5cb35a9b9bf20b90f77266907cd2dc6e73191aab7b0fe27fdd0d
158	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe18c74430b1fc8a250423ee654ee96f465dbd9dac15678e05cfaf6f58f329915a5f4e0d0787cc5af29f253ceda3235a68ddfa19e01a3eb06ccc0f1786ac81a9b	\\xb9e113886c0203fd5ab5e1db9ecc22b40a339e350174cab8935ee574488be849f21a65871a8366c434dd83ef0a0a2ac1051b3e86e22b0df45b9a9006e0ecdc0e
200	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4ab2d2410e2de77cc43dd1f4d09b8af4d18d04d428a26417f09ab075fe36bb73bcbab69affea2f91e7827630d7f0eb8608a82ac4b80cf244829ec843c566a70e	\\x557cc1cc26b74b808937159e003a44fa2ffa1b527670530bdf4ad28d2e8184ec85a508cdf0c05e5030f1aee4a83d561223c84fe04a4a422a95fe957e8d91fc0b
230	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbe7d05145fb2fb9ba6c981f5e5ca6391d5cba71d9735e2a786be4a5ee3432fc62cf28f09da04ecad899965e4ad6a34250a20bc3fbae4e899f14ddc1b49f5f62f	\\x60eac4541ea6eaa647dacb8c26ef422c3e4f5ac3d242280f44a9f1e11d78bba3ae066eb3d90a6c72fb8fcd19faaeb0e2a2286b689964935b665545c6f251c00e
256	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf18f48136f51ef186d949baf7a2d9fa0b17da7c73edda6ef64761e4fc4f622897c1350e881f4d74d04852df34508b2ccd17c4ce88c416a5e315227c0fd2bf0ad	\\x44cd68c6be894e96a2cb863b58049dca757909e2a7da18721c56c78ca82531bbaf294f1cd6f991bdcaae8ad41a3f8d2b940be391d8e29c9aee999c7541a6e009
270	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xacf4198fd178dc80de76e2bc7d2c8d89e6d3df28e50c2eccf58b2749c96989d79347f44de8f9dc07f8770bf008f39743619dfd9241a61b6d541e06fb32f3f944	\\x2198e574105da6227a0fc5ec48c73b280912e590876258e0cdc73c2a36ac1f2c1c0815297875427229933a285c003faa9844e59788a6d59eb7f3f63494efdf06
284	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe6479f05e5a0a7acc9d0d9c75925300dbbc3d84b3b3f79a6d0bf40b35a2b774541c9d099223a2145cb7c72c8a2e54f0cc52222ac5ed6d6923089004ea78afc22	\\x6423a14e7b450cb83dea29bcb8c34535e4b7cd1d9da25bd201ba0928b88c9853e43313001fd6076019028c7ef4f1af0367cd2d524fbe3fe16c3d3805a48e3e04
296	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x69fe5ffc98f39f00861c388447eb10fcf2fa755c8a3bc90c55a6f9b9f7e9146929dc43b745cf2a629a5b4331b3e1a1ca8f6971903d776969e1096d9d9ccbe3e8	\\x738585a1a70454c166b57f980202920be070d9ac5828313cdd785f6917ebfeed4847cdcb693306d428bc00796200c73acf41ec5537b65e3bc5cbb349b21a9501
314	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8d4ed1c090d266f39c010859acdfc9a1d9d0fc788738be21ce7bab5565c0310ab55190a59712a964a532d253a1d664e0aa8edd5a5a5266b86c1b2ee30ba24b35	\\xdada96fc42c9cb1d29df42d29cb48c0f303efbcfae209725113f54a3232af7224dd7077a6c126c8834e88932082a50de4b5a42b4002306d30d0eba4bc7876302
390	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xab993ca3c51758943ccba29d91c0b3150e95bc3947f7160c14d74a3117b6bbf982627933c51738761dfd67e25f7dd7f2d56761106801d5ae2f3e37063a1bf523	\\x99236587b90c1d8c0f80e36ae9278566e7fbc75774d1188d68c9e04f6dbfc2a19467d9951190ab8fd002dc82d2a888f5f242285e182c824600459031c3e5ba06
416	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8f6a122207a9f4d8d7d4f994ccbb93c46c1950bf738102a2f4f22c75f48e9f890600b160ec54a76ab45a4ec6d7b556c6e70435d789b925f8823ae3cad9f5c75f	\\x5ae0f9f4786ad78a0f47703316a1f9a9eb5501aeb68c43d9d2b6da854436b8a4ca4559fbca43bddc6aeb43cdb258971a109c22aa91b5b98b6237f983f3dcfb08
159	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd98de3509b8b483db3a148637b478ad147defa43cb0734001177811e91134e727f5e0d499b750773b23bc76102273ac3f473d491e745594088b1431c3d71d7d2	\\x10742f6a03347c51b5c126ecba33455e63e0f5cc5874b90c64be46a911c0ac2c5da7316d861a96fdfc88b15cde83df1a26763ecd673b454e178b4f32ef6ea307
191	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x822586eb59bcf7034cd6734847aff17dfd169fe946e95851ca97f7e1db8c1115a2d02dd99671aa7649bd6cf350cae2cee6bc839392bd0c3d99a317588370b755	\\xed49881eb6748372c265b5ba31dc262a81c36305b9ac4641bc6eba8b8a3ff85a1c12f6301942d2819a08fb4a17824dc73058ce28b7ef9c75de35a0b94bdd820f
213	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc38ab2a9f15405e2e509073a0143ee6945821eda17fec00d8a81c3db9e52b77c03b7a01c1666d39c5163663b62b28dfd6097e11de8d41d0c80aa17b94c9e75ca	\\xac73cd5ffd2c0e1507e52dc6031b3607f1070accf1b9a2fb785179dad1c74ffa333e8ad7d80c75b5904426a5ab54e5df7861dc90e17de61756ca9d1a0aa0220e
303	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa89f3412560017b0d9e22507a9fc1f4cc1ba7b1f1577a083f373933991fe9a20d5af0b72d72b9f3cdcc12dd54a84d181db60a932599354dd2205efcae7984a4b	\\x754f590c1527daf65c171928744f5cc967f6b5ea2c94a70af44e40ddb467fd8a251edeadcbb3648477abe29f9d448b29e91ce246999d8e9038fd9da1dcb88e05
324	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0096b7368d4a3a60aad26158ea04aef88837c5c9acdc272cdffb3e186e208eea3b3836502374040a8602a31c42f0f56a1b9fd010e3ee43aa67d70a2ace77a939	\\xdcc2cb6a32a70abb05aa34275502a755b3c7fcb07590ee54ee4ad541025e90aa4161df3563192e4a62276a0bdc6cbe5c97c6da960e1f87d7326a46d61af2840a
342	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9dcf2eb30928862f59c77142bc0a57c7133f14fd6b39b32b24d3bd6415c9a752e1ccd21744e7e357d3e143d03696a8bad231ca04ea730fd345ba7840d60ca500	\\x26d8d92cba94162bb35bc96d7c511411e538bb97078b32bcf4cda9cac248c1985a79094d85556e0a97e50de904a39c5c05c92dc63d58fb7a6ad1f98378e22e09
354	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x868b568dcb6af1683998ac79da24d0a159766283db56d390678ccdc344b2689c32b68f75fe71127c1353c5b98d6872d3f22efb02e256fb6b34abee185778d15f	\\x8899f26d8066d4c11d6b671ac6490cc785436efaa9574b7402b0c017a7f3cd7a15e032d7b57f26dec7c030bff6b126290f33d330768a8970add96f4aea807b0c
363	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3cf7dd6841b645e2a583ead76038edcb5a5c6becc5296817431253a44f007073bd5c8c0099d94f59dd6b8c60f81b508dba3729ab11e7f62f50e4712df2ada919	\\x026ef546d8a1bcabfb72cbe4871458d471b0faa4012422a356487afdf9e60cf140fb389e68b6cd1e01e8c8a5f99d48912b4c0900cb173bc21dc6701c8cbe4b0d
160	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xfb27987b3ffe1db9ddf0c32955d4aeb516c009dc62aa59d8d9cb052a4c6d5412cf4094f16061e9a46eaa22e7488281c3dd977377e4b23195ac3845b0478b9618	\\xbe3f2912515daf69f88de129f07cffd8773d3b21bd39ca6b4c6007d8e375bd828e13e233b5672043e4be3acea3a8477e4b6b915e08b389ab019a048dcf018b0f
175	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xddc4ccc57bb2082c7c02efb7f0a5a239bdaab47cfaeacb1bb271be6bb104b7d8253b6f6f1e2e05c09536b12bf1e65a78d6bc8d3d21a517deaec2c91df91e50f7	\\xec998147f481c143ae85ef386b03becee37fb63ad9b67acfa1b763a24673c0eb436eaa1caa1eac84296425cb28a7d791eec38abf2e5cf6f01dfa4bb7c24c9c02
241	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd515f3005711c8d53035443b3e834428c2e059f4d5ac31cc4a9dd17b0fc59499d05167bcd2c56672d576790df53b70aeb2d372644a51205a0f135d251a7dc801	\\x5f1fee27e8b52358d00a0a288bf639eee075ffec51b56d3735f1a45500620d93022e97f0f609f3bad168331ac65162362ab756b36e619d030e2789c58348d70b
242	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x998c336c799aef125b01776b6432c8af929fdb9e00ec749b9303c8c8ad72b065701e730b6041dc97a8875ecce29c37b3b4201e870623263fe59cc652c42a8d22	\\xbfdde4e60060b2111e0c0943038cd7a0865f5c6029e38ad1b81f5baf9b4e72b4cffbe60b1b2652fbb20253cfe92609d7cc14425dc9bdb38f38dae6814e2e4d02
281	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0053d82434da03b4cc8118bdcf6b4c75dfa95b74e608b134b3cb712194eef81423ef2156c4b574ec98049894d9f54cfc20ca1184635fca4ac89fca30a0cdffde	\\x2ef146366cc0176b783d3116daac3cb22368ca649faffa8b8e84c845d76bef86fe0d7615ae75b7531f15c3711cbcc3b5c0db6b51f8952e23e42dc75bb5215e0d
300	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x237aacee8789eceb18dc717608c6233fc9caf581181703d62103164d3946b78ddb7062dd47a0f2e537d6a313af628fecf50cdbb943c3d9bccacef560be5dd9f0	\\x6b7ec7a0401e1710dac3c9a7acd6dc8a8b10b6d4ba30b8a9418ad4d548b252d7015935950eff4d44b224a1c527dd4cd95e7ca218c92b16f052b645725920b700
318	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2b6c114d7cf9613afb1d2da6c644acc57f7f802583f20e179ab04221978f851ebe4b0730b664908c2a7c363c527d01e31c50e6114632ecafa8b52abb8c8869fb	\\x2b7612d1ab838111928e7a9123d580f4b2d4dee15849823dbeeb1c9974ab24aaf05daea3758eaa48aa9f21257cb8fef92fe208376cf78133d952ef8a04e97a01
334	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x18b49e6771b98835f139cb7dd6f6df1c7e87e1a1c8c103f0e6d9aa48b8418541b66b53465996d0ab2bc89e1c7cc9e3d643024ed6559f696718b380dbd54ecae4	\\x1de49b0de258916d8aff184b1978f5607ac16cb40f6744d0c40139f171a164225b043da393eaabcdbf5425b5368808d0f1de4b5db6c80a6cde54ff49eef8bd07
344	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4144cab4c4bb20f27f8c536ea3c19193e8d4ee9a7f621ab434eb72826873340913e0fa240178e7a3feba94f00be2527585fe7e147271cdda01661263bc05c19e	\\x6ee553a280a091a509ef1dc7c6de2dde42229c589f661a319dfff08f5ae0c5994d2fc8a77e5eb6419909380cc565c15980ddf32204f5c72177e68dffaa25860b
385	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xdd0818883234a5f33add8e50adeaefee4c03ce40d1d886deebb12eefe0754e6d51b71280eae826412d104d36d7c60bae261d9ed2c4eba12f8126d59207c52203	\\xa495ba17f0641a9f3d1335df8df25ca2ab8e780f580fcd9dae87fe41deb9769e7ff316fa8573a6c1125e771aee44acaa19c230472cf21c2c56f2a9f75a172101
394	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd6095907a8f6d4fd4c1eef25605727caef595eca995ed8f7b4a094efe42ba4632edf364e95fe8482109cb40f45f71b2a47e0efdd6219c52fcaa3a5126191fe2b	\\x32d38daba73c65982ef569826702030b51c5dd02b3674e00b5bcf2fbba614a37827bdef3ec04751602ad8b96ff1a23abdab6f6f4fb044d75a7d6b875305a1202
410	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x53f0a8459c0441e20e61a8f9141021a921923843423ca6288f6a15ac06443953d98894dd09e57b8a4c2150d16c6a53a55fb02a59427d12727bee09957d04f8ae	\\xc2743483bf9479e210a77be96138d77f6947a507431cff3d4fac455b0ec9d6a2bc083c3365329b77e908e242753ed745b65c2f905abfd607a590bc39bda7cb0d
422	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc5a210130656e40d7bde6cc44704cccfd4d6239157996d960dd6c81136de684e57b0b48c11902b2e21e8750dbee92553eace1f76cb87f7faeb978f632030805d	\\xabb7225611b050a2c447b09d4213b287838a7c1979a9c13d1244c8d0f9fd12fe45ff36c0588be5b7586750b076dc6e6127c393b27d103d5b267c9634f746b80f
161	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xddb27b6d8d7828b8ff31d58110c1e81a52fdce6733cd13f8945469f485934c3393a985ff33907c49429953a800c59c1e442ba1468282da9a5451b652735704a6	\\x538fe70dbbc91f7f96e0e154da0372cd3da9923a9de7ca2050b34482d578436fbdc9cdd754ec27fcbe51a5c96c183457dc4dc5936577a8d9aa7ad343152f040a
171	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc96fbcc73b97d022c41718038886f97af46e93b8e2081ae409b8df9b55dedcf5dd9ae871c547a8ae454d527a5986cd37165db05df6bcba0b879dc9abee092286	\\x7cad24af033a85331c327cf15d844d2130e6a3a5ce5cf4ef67a939b0f462739b4949600b91ca17bd0739df1ae07454ce4b601b2f17a49c6d04cfe15771446508
203	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x28992590eafceb15c05082b0ce2aaa8deb943ee97f12b5c7723811c8cc6388889bedde8c4302cc089ef6fb44a60e9662bbfa6344f71ee6a2266b7eee8ce8ce70	\\xadb4223f9ad85771dfd385e8024c39275f4f2e5d61053aba8fcd82f9f949085f8e3b406b27de8ac8eb2e28a46bc373becb53c28c7b56ce5056711cda84fd0807
225	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe390d6e05ea2c3bed4973806b723ca49e621d026485fbf7d3f6440e43235ef0e5e5c6ec2bd70d45be0a03cb63ed15a5e1fe1c5062a502e2e450f4ce18f997417	\\x097de518d3e62af307e63a42606eee6fb868211cfe8cc7bafaf952b201d29617fd09eab660bcd774483dbad46cb46390f4f79e316867e199a1f43e35db636009
269	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x33331bcccdea44dceeb3ea55b13ce9b081b3a43f0ea7e9ad059a631bf3750322d6f13eb1509d126df6884011d2a3a760a95132158b1b27342f08033236741ab0	\\xf6b8e4f70fd24270f940908e87793439b73f58181ec78ef5f2a641c1726e710f60eb6b1986e1e120d85cc1bfa8aa7aa08e372d3a4ca00e34c93140d0cb0ef70f
288	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7298b4fbb3d470df2a818ff45c4cb9ef5ed7b3c3a44890a9a3af78939d3d467a04a3123488d5dba3707b34186c207bcd231cf7bb110bc01bd1996ae13eb7a1cf	\\x52b22f28feed6dc1ab823c5cba1578e82c9d65b1662475efc1f185eb6fa4998206e6a3ef5e7af87a72f277b7e33472ca05b303dd38265f7d81d7c834e63b420f
302	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf9083c2701abfa43548ac53cfae4f7aa458c2370755ffab1b430b701f91e790aabcd987c024a7e95b0bf8b926e23d352677f19d3042ae4f127b729953bf8db3e	\\xceb3689c37c3336c74bee388e60ca885efa1a33329669317f8b20609352e1de6ad2cd274092bac93112a66b6708cf6ba973a43ad7c698a0bfada13dd3eeda603
333	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4c1a55dc751c97d0a2a17c291d9163ab7365fcf73a5f28f84bd382c04912101609db47d7c2a3cd05090ab4f9dbaf31351771c28bbfbde2b7783c82e5c5a495e7	\\xa93ffdf354ec9eaa1d4aba7a24af278a26127388c19ca1627684b01eec99f7ccbb2cc7b4f3a9f68d79f869e710381ae6407a205b9f10f548d371afab41af4c05
353	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x894356349b9325235ce15adab5a2e0413ca1b473a51850bac1171941d51de0f48dcfa616cec16a3c0eb98873c531991a2b20fdc6c3db39ce9c4af72c859b6af4	\\xe657a602dee53eac864da4cea075c830ec61558c8e4cf5b683866ebfceec249f953d099e5d63aae1f449e1d801f14546e89eea5abadfbc4f733c2176b29bc306
401	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd05847866a119ce34f5462c90ac5aa0bd86bc937696432b2d6a567912669dc678eb773bc6cca9da71de2befdf2624f9e5d963c8c54373f2230d43a56f4c73eeb	\\x0d5d2f5f5c15ba309a27d8ed2e6efca8900052ac0b762d2e100f08afa6bf17a35b9a6ff7a7d0acfd5ec1a43b856a37aa3d1a9e7817abcfb17bc23e4f3abb5e0b
162	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xef98bcdda1f188781edc3ca1d3718b4144d172c6e3cc25222e78253107f0685c738e2e4903d3a5c2f92c35a9a382fac0ba870180fd108b1d62709c794377e6de	\\xbc29707243cbad786f80afeab14baea522db6d01b3208bd30e4aa61a24d2793dc9346a0f5e080a64f357b8ee136092c575d76dff09064b087e76f339d5ddd909
174	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb29e2c650585d3885bbea25e25eb5f41d41cd08655ec59c6ef59525ede0c2891dbcbc4176cad1b3d64847253ea4d7bd2f99852869ca100b0ef76da59ee2b8774	\\x359842b783cd17512272e98fdb15c4a23a5cbb3132029c70e26010388bdcab5d1fddfd539cc6b5c237f021a2fff53f0e98b7fe87dd133530654a2c4743a8ba0d
208	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x59c0422241063ebca3e3346d222d692c31409d11f618f336c8ef67139f6e25afd1b0a77142f16cf6cb0c4f3c4cb9ffc82b30f8f39bfa658a7003a3c688554a4a	\\xcbff3070ad3825b69bce007702942f0701759bb3f710da814e41e4e3a6d48bc274f36677621e2ed08e46baf46d49015baf0b5d6b5829dd720538ed4593b8a604
236	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc511672930a7aad03707278db922ed77b5ab9bdc4eecc2ef9be3c73173efa080a4594b1a636ac33412ca4fbd017fb8a1e85a108b07599de6277069519dd42317	\\xa5c0c22a51f941148e830579d3ca91e43ff94fe8f2e3a086b0d9e439a1589c77d5ab7366d2a1b83190eb423923803a17efdb7e01c617f399413c8a3686020908
259	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x332a2b214f8e5cc96193366a815718c258155a8b6fde7d8dd19cf494da4e89a0feaa93df4093c9ad8bbc878c5c69614dde4efd11f3e736900f3fb6fca362dc09	\\x22c44023ea818a52e50954a434d3970bc7294b5be9fb26f75408b8cb2a512694187eef3125950edfbe52125523ec379b4f497e1fc0e1ebbebf7e972c42349508
278	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x140d9c4d348326bd64adbdd14bbe7f106be4ad1a5c5b61d3dfdc2129675e36e6507a9f97ffba75f64785bdfb8aca0a485d08233403cbf224013b48ccfd356bf4	\\x1bd1b72b34eea8ddc80a06f8f4fa9f7a5a1da105b633bb52d31e2e584928b20fd5c9405822c4edaad5ccba9bc6b24438ce63436ed65d50b34f8a23104175f003
306	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb5bd1c74b2f7c6d8358f176d2cc1ee73c17729827b141f7a43fe1c5a48d93667cebbac3755314ef456b96bfa2dcde3a02ea97b79cb2b72e6582c054165e953d3	\\xed0e78f5654c1b3d4fc2347fd6488fb893032ea79cb57f8b15a73c9137ebf869b3d743f96a2e69af143f0a9efffe15b05c271a113d241acd82c0ea640aa5ef0e
331	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xad55fec6f4c2b506558ea387b3583c6e45e3fc8191063583f4ea47f5380bee08ba86309d752219d81a34438ee4b27ca11dcbf17a3774b403cfc8297369d919d0	\\x4094bc5e21098fc9390475f4657a4507664f37c87a14939e81945cd11698021c176f54019bc3c36e8c6b3cc07c9ce06373d89496244fd09affa401cb06e95f0f
375	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7b5a5ecad69f0649ae50eabf4c10fb80fd4defffb0093ecca83cd361c003722180df7804034c4ffd2a66c372e6f60ddba26f4252a0b4ef4a15df24eabaffc16f	\\x127dfd272a4977f151f9e9597cd2002ae9f730a9f82b78a0c31a5a2a73efb8751f1493ebe17245bf67248442796da2439645e1f7801cb7d8e1ee3dcbce311403
387	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc829775a82dc67233fbab4e456f0581826e50291c0940250d44933c446782fd501405bc3f1a2f1abc35193af246ad6d5bb2c8919d553984bb1e155bcc1bc0296	\\x5bcf7bf30434893091a1953230116558aed829b59e4ad5fe326301fab344671f1b3d635e6d7ac531bf93087e828c6cdad62337067d7569049fe739663c0a3704
163	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xae64d7954224805a3be820f74f2ed5ce236985f39d7aeb5a377ce6ff70017ba88d833231c8af22785b4e9dbb82bde240f4f0def88abbba019af12a60a79bf770	\\x0bbe16d6f0f1cdd5baf04798a444ebcb38edc8869868d92208004a9b647cc8d26e6d71d3bd62c66a5cb40deef351d2b85a6a5e2f80009accf314c32df1000c0f
195	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5833dafc198d26bd15002e2122a331815a50a7139cad6790d6b54c44fed849427544afa604c13806cda071cba52c51c2025d298e4a529af06ce8a30f68bbaeb2	\\x1173039a10eaa85749e3d54a32046d74478d16f2149ed9200366454c135e1ffbf284e086fcc27bab923cb3752058e1dcb4f58932a8a1bbb8aad70beca286c906
235	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x305462136a1cf1f40c4234d8bf8ad59e248eadec85160a85e40f20b22e9ef643ce57626a6feaf23bb997f4a64ed6ebed01215c26883e49a33047c2317c4fc6e8	\\xd5b1d1e508492e9f55a1e6cc6e0e913276bf7d6620a5a2313daeb045b42d30e6e9f596d83fd6606e779596da2a8ae4be421d854f842250c98e3b64c8a8d7e007
260	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb652adbcd0091628ad4ffc3ee4381f3a42a6734d85e0927b5da7597c967a698388dbd257a0418f518e913ea1c9adfb3d1186975303eab82192715a4d8b7caf57	\\x51d0e2a21104f10bf252c95a783d4bad6ea1d546404e959eb88ca0b8b9be9c98ab7d8838cf7cd18bdf6102a154d073a2fc74d804feae48a139953e8e0ec48c05
277	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x33c5e5396be47745eafe26c3d9e8f5812fe970809e126699f465fbc1dda8e0e16f432bbaab9806957aaeb10ff32db2fe848e58a7bcb8e3bb0139023bbfd541a8	\\x85302b42eb16c40b9d99c6bfc5276d42cb26b5c4005695ad102d86f20768fb003be4c4cc70911c12386f5d57fdd772ec18fa84cd552d83a09f3bac2977487b0f
332	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbaabbad50b4acfa2778375fa99fb0084faf50a59cd551633376e9e268a86c9d6792cd8fa86fcefda0baf6c6f0b4728236fcf50b7c5315a09497dceb9af13ffbb	\\x372c72f65358eca24832a981f5aed575e65d6a36ff57fae82befc7c3a3473b6feb945e28c21391fd61cfa3024b2fdef302318a27205ce264ceb51c5124033402
348	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3d0e8e4207c78cf9394e020737046c4ef3d43527e0e0ebf37a3a1fcb4725a06892daa02b84dd9b6927d10efb361a15dc69d91a91b9f6c9e9427570a4b19a3d3b	\\x8a829c5220111d22fd7786296e383440e05533ab074c7935b7ae90bd081e0ea79f104ba4078c6718b132c773479cbc81ffcef1833ca670ca8a8330fd3decbb00
360	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x866faf6cee122229df8f4b2bd3a9dc23f9a9da633617e273898e76e42da59b673f8bd42f3868fdc0a89340ff49ce46024872ab8fdd16b58db9410f2419f2a993	\\x6be1c8f917ebc1e5a033fe96faf091b1e75b387f8ce2b649ee269c2069efca8a84da2267fe13e32036fb2eeb77410beb5022e69b5362e2c9f50be6d93318a806
389	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3d334f9def9da9bb6e2fe827027b167d3d940634177ecfe4f238e2ed8fbc7d86a77f19764d7afeffdd3b8cd42b286567c58ff67d39010865f2bb653abc577229	\\x3a958d5e845ab6ff709a69553dfa2bc39a640bd408ffbbfd1e9668af6d5289b20523611fc1a016a3ee7f8c39bce07f1ffaecf47820dc37613f8498236f5af700
406	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9b1093d795fd6992cf5c20f24e9c1572b5a72cd177b773f83dab208e514873694a445a9e848810400c68656620657ea26bbaa60d9f1c89531a3dc6453b7bacaa	\\x5a8f6f9a2d46a7fdad5c0e4543c4e0257e31a9790d06da1976c69785e56edf0d3d6210384f13144ade54e966b98817eff6f97d4467f1f138e0ba1d51bec13409
417	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xdd779fea2b83bcd0ae99eb864c13232f5af7d427321f8b393f090c3c8b23108918fd72e2a640e0d63ae981802bdad601540a7966def31462f025fb929468d090	\\xc2946e9fb766a4d3966740080ef1ba87b1e24b89cd9833ff1a13b4c89aa7b9112785ac4fc885bd122210dd9064cc8ceff5639b23a2e150b81a83cfcd9f4b540a
164	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x70984b6828dfabd64a3afd0b81ad83064f1d581aa87a46050a2516205b77adecf7eaf3570d32424fdabf51bf7ec8851918e28beb6a71795bd13090b25d905005
187	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x14d4ecf3474060987df8b9a887c2eb186a709ad1f03d35bf26e1dcc1d4455eb71c76c33ab868a17747ae9cdd45d011d3ec3bdaa9089c516d42960cdf202c186d	\\x4e6ff48b005ae85adafb7cfed3168f4fad37180019aa445c47602bdd17cb4533838f7a88bcaa5f4c7e9653d6c5d260900751944f763a15aa704b96ca2a9f1b03
219	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x98c98072cdc81bd70c269de6ccde2358a7e1974816c62b43f5b3e2381f33ed00a7a6f1488f9f5a1310d7287479b4ca1a4978fff3131520954d6b5ebee871c201	\\x6cd65b66a001fa31674b760afaa94b428628286395184c449f07c9df00bf50860752a3e85a9439070b64c61f34b6f0d913232800e214968b96b9f13dbaa8b10e
247	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf7235f573acfdb811d59dc3e9e1925ad46dd4aab80f387dc6af9965aefbb3fb6668780d7a2c029b5a15748123ca9b032c0e2013952d8e0a50eb59c4f24515ea1	\\xf89a9b752258852367510a32535521aa6ce0cda8ccf6e1f98e7af7f6b96e88ef4bd45b67f73bd360e34dbf281b7a38a92e5f4fa5c78f94f0b01a0f44f0c4660c
264	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa7a66e463574c7a544537aff6a6058869633ad963364666973394ddd42a70bda3e9d171352daed18a45872b2700878b65a839302af5950f6d13d6a5c0f785cdd	\\x9ff08a4d673e2a00aab15c735b97f28451646ea23d4ec4411bba6644d54edf215b93cd0b5285df5f85fb8a24c1871602a7d82c74e37fa0c7e17e383c65dc1f02
289	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa462a343bf0f991fc7e10de0f9caf2a95638675d7cb5fec32ae35cff61333dabab95a3064d5e9448eb3f397d49c0849d3f8416cc8d298516cda8f30141d7a6f2	\\x4af5eb69af2ec5ba74216d830236f8100a0a7ed5a4b3841e672a9403e3de96914ae50b73019f46dbecbfbaa8a6f7af7686b5eb6d72841a562944dd20fd73fe02
311	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x632ab6d937dadfd083da566c98bf3f7fa9a09c8cb5c45a1ef763dd4a2c8cd54e457eb9bc415c6c90ba32460a972a8b96443abe941fba3f2475914544c80e0b8f	\\x6067fb0e2078b3a07f3a86d0cf0fde96a70b9d1cee40ac65ad01d1f2dc63b61a514313cd1e8af64301de2f56556988e72889dbcedf5513f6c58376f13c94750d
373	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf2709871093a9f2734812914b942cd499eecc8ab497ebae63dcaa490877b40611e285af6d450779f8794764c506e00e0c45ab3c0215fd8faf1647d23a797eed4	\\x7f41d07556d763cabd03135cae7d3d41be5494a2a1beaa4f1cc17bbb772366e746f289c6b288bb44661a453c4774bbc9254362bb400f596f415f0ddf52d03a03
392	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x65bbbba583876a2dbd635be1d7154db5ff212dd2cc6f8e7595e7d60257731f8caad0e33ee633a8fc3bc0c5fd5c9c2f77a10c605952d3313b8add87eb0e308748	\\x7ce60c2279bb1a279d778d11aab647469172c606f5a594e4994d9a04f917ca2f3983068a9708b211998737b46d87bc7cd8488e0e9514763f9c239301b5158004
402	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x93fba42c8fdbd7e0448edc1786d7f96888d570a3ab16ca53df6e21e1020ac1645a224209faac7d7ebf1b0db781c542f1498abaafd03dd4e0d1cdb3008cfd8b95	\\x64c541db045bb87eb796f5a9527d1f6835786da72f2708e3d8c68c28a28a19725b621638fc8841d0c54620d6bcd3f263749af5aed6ddf548313c4be3a8ec6204
165	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd95b1bd6567f2911a6171d7ff3601eb0816b5f7007e25d38ed7f34361a59fae60c0619f6304343a7235b00c0deb0531c9ee0138c343637d1cd1504a8e2b3f32e	\\xf9a24deb0507730e65d12b3391d0e1c1f2b27bf01614c563d113f36a33cf68d45ce414e5e91c18a549505d8a8ef85a82e8ede645bb1edde65a8cd759b64eb003
178	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x217c1c8321a8eb04e090fb4cf8a65938c907a5e5bfa0ac4c97d4f5fbdc1c2b6e643031e9f88be9d9ab8650b7c8f45801eeb9c0e4fbc7d69d27215ff6805c4bed	\\x7cd359e3fabe10bde7f3d49c456569d456baff53fd56fb783088567ab4c0d6876b36ffa6be300d24e65e72b09d2d3d2c29901bfee314478c3e042f2b9faae604
209	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x57d746845f3b9c5671875a8022eb98c685c3140763521404622451e78d7739159dc05cc4cc5905bd245497c70560337d5e35979083bd01c46067dc1e8593d051	\\x813145d161a9342dfde2471cdee4f1e2c19d1e4d74d03c87332c3ba5c76f68731cd7a56e9636512e0de7476d06e5be53a8ebd579a4be8e2f1e20029b730db405
229	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1556793ff62a4ee5ce6692ec2dfc0db28e511156085d5b646b8f778dad398c710f8a2e609cd04db0535cf0f75a34a9b8585771bd94c776229ac602a2b656f000	\\x2d32f138004ddaac909c86f98320932dc508e075dca5993336ae55ac44061aeb1746ebc1f7ed83627194d92c233cc02bbb9deaad6c4faeb5ef5d29cacf4fb108
244	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x340e502b7442fd6a9e683c71683bf914908f18529e43b594942a77633fab0ceafd575dc2fb76bce6551181b7a4e54752bf5e324704a48ad1ded3441aeef2fafb	\\x8266c885a8914cd3b2eddc615eb6e273524df8637268325928c0c67c97d5d799a80739e5f4ac0d22de41d840851cf705704181fb54f94dab8fa316fc9dc36801
274	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x603eb0cff9c1e816479ecb2b0dffc46a2158486aa9304c78445364ec12037ba6f1fe1c9d10a538a0a3e8c4e5a9d218b2837ecefb5ec8b93e51e7b03a7a15c01f	\\x5956f52a39e9fcece13e3aec34b4a3d7ab8024270fd1c3ae464c1e71e6833a90f2cef41598394883bbea5dd9df46cf427b8c3866ba93b3e80dcea93cc145750a
312	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x9244f9b6d91bbf3e0204d1e26153a3e65cd643e81b9c4f3d11133950b6bae7cb7d3f34522c83d64778d5fb19a5fed2104ac188e6a966484f1ff4dd39f4d42bd3	\\x5ee14dd10ae8cb9f48f8433ec0a2c4469e54572efb1374eda472a297eb576c3853c874c48eed562c3b204360c9479a20d41e23f260b3567ffdd714279739f50a
350	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x4d083d0e37f3209631eda06e229fe09f47a99a4b0fff7bfab0cc6c2f719b681e57c0ba375922a63e0dbda77237fa0135ec4b7918aaf4e8eace7e04a73903145f	\\x9262de5034870f873f4ed47bd4037396da1bafd3d127312b54e9bcf6305b7656a37956acbff15fbc5ebd6b33b37393cde1dd93d36e34664afccf9b23cddc3109
359	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb6789b5548aa6f9417fbadaa925c7f6477a8a122206078b75269002f4c1b4b0e05c39298f4e34fda5054d0698b569d8720d02e563096505162bf1abdaae8ea13	\\x8ec858dd76a6456593e122b0d907f626b3e0967648801987ef320163e8d99d6ffd888dc379ec51449a78efc44bff67b652543e3a72b97fd986dbb5551406050e
368	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xa21135b984e09661827db18265e27156ec38107c721f3ed7d453b40b42b41dab1b3d399d5095adc29c4a6822785c4f588697fd1885584aa09dd6234598ae362b	\\x0e6c730a733fa3f3376424009139749c5c80eb3c354ebb712a19c0a673d1033da7cd6cef517ae308ac13d0c6f22d0f194c06a95eeafa813ebea7d11578c67104
166	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcf2bda116fa142b18588769808b19dc0a6754ac9103d78636640aa065b85b371e040ffd9a0283beebe97fe79e99b3376c5e2c31407078c37bafc9aa2f97e4a1f	\\xc3ed9ff0228db49c7b863f3d144d14beb8feb1b2f0589504043f1005db3a78b959f520db26dfb54797fcb9e7574fe709cb5c78d26076e1313efc9f193fd6f902
194	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1a4e31a44646cc9bd98cdf9d137c77bfab45bc11c710b88829193fe73d64312c9679e8b5fa2d403c01b789b54c7fc94bca8d8b4a0359d15cd74b98fe35a0215d	\\xfb2f30e4c65852d9f8e979fbf43d510da05f98ab7598811802da764e9e0de6addabac5bd200f6299d84816cd3f680eebc6b7ea7fd0eda3ef54f722d59a09b909
217	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5d2a330e673e9b7cffc1df8d7a17d212b0df9d8789975d6ad744893c168699559c3651cf496bc8d9a3e1e397a71a8b5a0484ff21a30b79154d0048a75afc89aa	\\x8ffbadc6ae13c1c672bed37caa6994cb1a14988cd5beb81fbca4187046395be5aadf882217b28f4a3b37f1f5b31126d35bec1191067a88f698dcf059277e1c0d
265	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0bbb5eab59e369ab0a09dc51fd0c893008416d11ea3e72ac4c223bd394e9145d024cda587d396c9fba7f8cdfc4c34694de329f0a5619e7b12a98b73c502491f8	\\x9b28d397aba2ab3afd83c84d1576d8dbac8b13e2a1d65f6e79efe4764deda26ac00847bcc4564fbf8d5886e5dcda2b6dc067cfcb30d2bfa8d52d38fbe2d9aa04
280	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc3c8ecce35bcd91d2623b93f122809b2c39f45f54f8c59c1ccfcf5474abadd2aa4e67a58e7e244a12f52eb5257071ff3f6b3028d1e152d5ab86a3471d2d487f8	\\x2808da78e341b88b00729d775af829f3a911e7fefd64993df085018df3304be2b234869ac0d0a984fdb3d5789052498da82c73a302f63d0f1379af46bc542c03
305	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x26f5b48fe6d3e150e0f62a16c94b86d373e09acc064de8d13bcb4898a29a381f8fd1e464c9728dfc6ba3e01573de40daf7b9651397844021627b1de22212f3be	\\x2011b1783bf015e304fe1a24f26cecec0af477b1dff0c9be55d69af22b3771a6a6a8c265859bf1aa1ecf59bb61addd1a682a231e917e73a04ae71a826e8c0c04
319	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x84362a02a7160f52cef1a32262b362c3c907916669f21048dc8ab45b9b54033f1068fe13222a852ca5721dfa55e88afeb44dd17ad1f8b372ffff331fe5b68f54	\\x75b409f70b503e332a7dfc79dd863962ff62b6254904642ba503bf3c0f3f0a6a4422747949b5c3d11116133f9a69857c400e0efe305fee03d29524597217eb08
335	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x75bffcfad61a706595c3e5ed3ae5124db93a0ecc7eec83f33edb08da8e780438990d68c197b47c6c2eba8574b4efec827f84c4cd78895b297e7142460890606f	\\x9cae66233c21bb62aad52ebbd56ff5960549019118e9c26ca63d7214e7fbfc0cf727d6647532fe28af587e0c6b2609e9a271a7666e2a7cbb0a04570c965d4b0d
358	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x051126d66b1b373a68f89500faa724ca790fa2b6761ff5257445167f80e86ce20dd38bd5b1076f4bcbcd50258f29ccbedde762fda303e998f82eca8c6cc8d441	\\xebc518c77c6f02d808b2ed18d2ede94b438b718846d1b0e022951bca79b5be02566ca42968be3732b1c94dd4a0553d87b545eb703473c9d79a10b39251519202
379	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6f111c2bf42cd21b441b579d415b41c1706657213c3b8e01a00097c2c2c96b7b4ae6575cfd28eadf6e397f125830dc2b356a50f0dcf5cfc1cac585c98c337518	\\xb400636026204e467dc194d7df52d06035f7c756900126562d35ba1690276f6e48d2245e90d47e8bc70a4ea2134af1cd0be730403499185c14627bbadc4bf409
412	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x07d7b6b6110fe27a5b0ec931a50df975b88a47b82a53b815955f9b6c138e7f99dfc32f3afdb4901fa51ea258ce9a3d286a806b3388906f5ab9678a3f51147f5e	\\x7e85b30e0dee3c1de389cc88d9d9557d5df913121464f0d38ac0fa297a87fddb41ebf38409f3557b65bcaabec0d0725ca72a7353526c9ce21176c575c0e74103
167	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb504ee900ae51fb6a8c0e3b2d8629dccf028abf1ba99bcaceba03347b13d48ce1175e3ce71245c1a9b5fd5362c15f3202d5437e84c789ea71fb260b4a6e66eba	\\x5654282eab3b5f0d71260bce39df0ea8f08682143ef830856dbbf7e64cc7204e1f32bf77d2f7a1934087307673123168e582e43206c171a7094a7dd01a914409
182	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x682c8451901fa24322082bdd76bcdd10cf1632d39620d8695486258c2c60338385f556bec3d4c9c392e0e668179e8727400c4a59089886639b0da0c15c818e19	\\xaed7b745c0043658efa47f45044f20cc56f517494d58e6232a4896857115e44fc7e09a360121a24523ba5ca891dc89b5928a63d204fe8dcbdc96655c96453c02
233	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3ef1ad159929dbe54d64024d9a2f82d182cb26cbaf86e6dc00374bfc2a39d445f4044995d6bcb005137f4c42daf470f5fadcee68835049d95a7ceed8154bd6e2	\\x9d2daa6fe0f11ff2d122031ff29c402dadb653e215db7b678e37dfbd9d753f72bfd6f16109c7cfa78457456b2119b7720860d9014ce239d0e6a715fc3182660e
254	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0a5293f855abbaba68b385499ace51584b643f14897e9fe37e50df4507cc7248bec8c733c59026deaa267e2f605ed280ae86111475443b2de6df80359f2ce141	\\xc0c58f3b343756a0a5f54046ed58e03ccd09908ff5202aa50fa4ef1e7118925b7822356e6aeee45d89274317a922879654f8b1cb318d89e9d3011447278c0003
272	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x58bd2d6d891a63e35c30e0714a1b54688a26f05aa508f52fef81fe07ee1fe58aed324927f574286f480f4498627d919c0e09bcf74ca74d398bcf07f7ab4ece4c	\\xf468426f4715aed5577c1ca37ce1e6be57e1fea418922204e5e1a7357ca2dda0da30b68dcf3cebec11c909862dee1f8e461b055f93d63f61b7727e3645a02c03
320	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xda0d3fe06a2a0195f29faf0f32155e91fe1b72d7e8668e294a7fd413e8912eb4f5f64ad6de4bb554fc6c50d56d0b40cfabf83c5bdfd9203ca054a05b5027fd05	\\x562e5dc0295578e779b74bcf4158811f016f4ecbb994d62e71f657b746c447d7a8a8f42d3cf1c6b5a490d565f480e672de0dbd19415af4dd6c04f91d076cd206
340	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x94a88046674b1290f81616eb1d677dca47a1543ef9e5c780cedcd91f75701780f24812bd41a3f435e357deffb6242e3f1071d9ba9ad92ae0ff7e43f43456cab7	\\xa0829b9b08e380ef71322dade54551c1ff78dd54d137b13d46809d3dee6e8590bb755d8e7aa635e1bd6695aecfb00a8425ef065a29403d322e0f4a21c13f8809
371	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5a1ac08a9162af50fddf8ab78f10e61e7642a4141b9a5978a84844a6b3b338e2a572fc39870b9ea77962ef736c468f439264fe102b13a8341c1ea3f6b6399b78	\\xf0786b16b7e1221482a05d54de32b64941bd26bf066a59ba9ca39c27c196c39cf0d6cf4c7270c670225f9d6422eb0946aab2316acdb90d657636fd0af39f8108
380	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7f6280be776969802d1962f2363b89d97480d4ad4d94f7a29b84c602bba72dfbbf0206e0f5d442c01a9d40262b343d144e93f18383a1c73ffa73eed095510916	\\xb2414ca6f3fa0468bd48eb4f908f82cf693bb45b6298dbac57be65cbd92ef81b1c37feaf0101eb5e047924f33a0f39fdc7ca1574783084d136f0591cfb4f840c
408	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x80da0577b0c27b4442b05061dafef45e675500205d9c9d36fb61dc0a5efe250528b335407e5f539f556d99f3a33cadccc4fb81b6e53bdc12cb55cb0511d46acb	\\xc290fd28effa47b0100b04a42eb8702282ed783cc5404f09e9eebd5fff7e3bc33d490c0418e6b81ad479e650387ec1f7780aa859dea9f556a4ad3c571b6e0c05
168	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb4c4edb12e3f2b0c9195d5447a644aa3c944e0b0154da7fa55d97ae94993789273b5b169eb4ac18fb3233cc79562c7c24187e88bdd8f7d71121db1f5bd6163d7	\\x419c914e4fe8f8af6e63e47763662bc968b59333f32b95690e00f809aa043c887ccfc06176ccfe3d835064fb7360608ca6611e089a8f08b97747ab83aca70409
185	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xeb56f374bfebc94f508eec8b9bfe4f778a87b8f393b025aabe268a3bbc9604eb9cc3d09a13ab82488ce35a71fbed94223b08321e0cf98cd44436e4e5384e8488	\\x3f9031c22f00d8909d737ba71dce1dc9852b55e24552cd7fae8002a98554a468b562c03b6944e40e5b336e51759b298473ed76dd5a3b8cc8d66b5d47cc783700
207	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x19a374f5df31dbbeabba390a1926b47fc72e0886334d17f2d6056a451b91abe72d3b5cf1c3ee5a8f78634451bf348038dbb420fa61cbe2de3933b487b0ca7d47	\\xdd6abd2599a58bc1d469fd921b02281de9d95630c8b5ce9a92562647591442e2ea86555e2470ef9b06786b27019dc351f1c961e7eb8c4c12ac9edb20075e7c0d
322	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7fab4758c0f6504f1a039858a1426a8fa810b701b6143ecd138a3223bfa4d97ad41a0314f55a7112adfac42a09643d83650f3bde9cb149456cb721e831e858d4	\\x181e021cfc3ba600792d2032786fa36d2386b525f95e3d9dc56b38a4699334b28f78e81fcd71f688ad5f23067f72a2f4de5bdd78a52e06970e99e59622d2850f
343	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbce48efe98d30a7bed05dd5d97a629c4c9485917944f2a04a5aa34ea86b0a771fab76f4b688a1f0e9d0392fa4b612b062c20b55479afabe872b5f89ff16fc275	\\xe1516e405526031bcebe49735b18bc74130aec755e5e58014b662e45fde8abcb17005dfb0a51fd614367101ee0fe40f4ec29cda45e5978150a2bc9f1af40a502
357	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2f095de591432ffbcb99485b3afa4c930765ec8531d8603f28ea7f2af61188ea6187dac961670e834eddc431dc457780f6ca9d724a337c3a8a6ab94e5bd31d36	\\xd221810dfd468ce218158b00860a1d577ac9259579310e82a62d3f69cea5ca105534384f71ed90a96464e4bd69893de847df53d46f4b18f420fa769255320d0d
405	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xdd7a1fbfad8ed04351161db8c1e76296e1ac5bb97d4ef1bf24e215b83428901b43d141ddfbf59aad8560e037c8d7c274d8de6b9eed5c2d82ee47d4667050d415	\\x3a332a1b43f7e0d461f97afc3db70452a75e5c27b8c5b5123c18ab2d077ad636f6aa2183ef0425547d3eb2a33de4eff6dcd9c315ba1094ae7c85b5baeb9f7702
415	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6ccabb94075293212e91f91cad31389af6927f2ef39c23f3a8640e6b576683c7762a34754ca92e526f998797806ff3da556a77b6767437a21af10efa945ab2df	\\x330b2f2d22b050d0dc907f9ce8ad57101c5f38bf928df5422c5b6ca5bc7fcb603b678e34024c739c8e1016cd1dbca882be1140f09b241f860af24b9d2bcf5e0b
421	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xbfd33a9dcb9be74652a310f2407b5657bdc10f62b34e83b9d0d0fe0303627704ff1cb418a6c114b0ee9002faeb48052309f884359862e01edd6f20fd45b8ad3e	\\x8f76fe5a21115011dfa7390461dbe022b18bfef1a2c131d25a4a09be55fa818950b6eb9b518cafd211e5abfa1bb82e06ee42537271875f3f1a5fb6edb1bddb05
169	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe3742381f45f96c6fed9fa8e2a8b1b37e09045a220f7e77ef614717db3c1f36987d02538ba748addd75105d659065b6136e79c674aac63057ec91ddb8af88086	\\x5eac362a02a61e8439d52b1bd52a82f80c9563b031455a90f4848cd3c4d311660d250f8a341a8b361eee47ea4f2116645869b4cdbb1779b5b7375ef6ea69be0a
188	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5b4da448a3441a604955bfc0e6d0ddefb03508c37e330ec849d019a9020ce266ec1e08af77481953ba297e1bf870c7ec5986ee4cf58df97cc45ba2fc71390331	\\xdc448d528d523de4efe6b4327c4db990004766541a22524ccbd578f452a32ba836234ff8d580f82fe89fba1bea9b1594e19bfb66ffb90d610f7e4fcb4dd74808
234	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcc6dad6c31fb521737b6febd8325563cfc366d506e3d1bac46526f2d96333d6373c437ade6c9ef6e18ab7e94c87756c990379de43f32d4e498aec5b093058963	\\x12a07e2f72cd5dcd953a0c67bfa8d03855288d081a30b2861f10a6f8c7e48e040c9c7ae8a316832097f2c27ffa446da599e8d8460fc3592c9e2baa60d824d10e
255	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5e46dcb95274785d0d86f6a1becfc070c2fdc934d57a9afab8b11abb48116c6ffb3e1d5527d3fa2f5d724a6f915ba82feb741d6a1f444d52a070410887e87c7c	\\x7075af1eddafa0854621783420a470cb76e2309b0c5f355b28e723428e0ec871b4401072bff2b5a9ff9843e3ea1d63a8690aabfa1d24cc31c94308879cc65705
291	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x2f97baf7e771b16991e754e77ffb79707e1dc458f81dd0fc4c444a5138b6aeda8722b9cd548b8220f2d8cd28d6a199825f635a013a10234509d6c5affa754c88	\\xf2df35a6d3e121094ec3d27a8174cf3c3a2b4bc8d5532c5c12c9b181283823bca5d31b45b910aa2ac8cd7ebe2ba762380e5866b68da18954f1be99b09e9c1a0c
310	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe4bcc195136fc5ec6d8e33c801af7664e5d49bc374e898e68891b7a8743750a62fa9cd7f07c6da57e3bffa119a39151ece0794f5b79cf886b3da44fd3ed93f90	\\x1b9a25f4f5e86ecec97981f0c5dd43ff3c71b6bda09492e235bd719ef7acec06c49d8e1f28476fb58269a727d247fa9e3056e0b1255fadc7d70aa5280bb0c20c
336	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x43a90ccdf6622df7e65f139f8a6f267065f2013bbce958ec239c504eb53253df2b1469ddbab609ee40c8843db5648412518725c91573d46e34cf50e486cbdc07	\\x37b402324b261869d158a0e63d60b251295a7e9c4a9b28836f31d455656914a28a79ed8e5458ffa9f953d06ca724fa10457afc081ce75d2f70817642db727c01
362	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0772098faa1da85d4f1b6f85d2ae2b3c4a5852d57cbf03c39039f59b6bee6e4efe3f57749e74a5d6fc6980b7248c52266a9d3df8fde2ae29117caae3fd89671b	\\x5cc7adb51f23e5f8fc8f5fb1cc45d30d5ff302bacd261ee9ea8fbdd5ec5f7552c0182e857fc0fdacdfb33897265bb068605a17a337daec16cbb8545a175c2d04
423	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xf4df5a1faa259dff7909e896c5023cb420f7024b93d47dcb00dbf2bbe4278c9ecb35e014f9910bdc78978a9aa61cd59593e1073fc2fae56ba08dea459f1459a0	\\xcf650044aecfe4578204a3415bfa0ded7108a6a2b46d7bcf211b0d9ba9e111e353f862128b2b79bacfc8edbed1f5ed09cdbb8975de4f50f588e0dbd39a42b403
41	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x6b6c366c982746a61613b34b11bee7176c998846dcc8e810d7ae2f882056ca894c3f72c9d867bda1372f4a76a7557913add75ffd4e8492369edf6fa6198be939	\\x585bfe6669297f29a11f979b3eeb0565b0831393bd3d1851807b4670d23ee3e468869a62995bdb4c751708616deaf16c9b72331c60afe67e8ac3ac1ea5108a09
54	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x7979afdeb115ba26188f60d119a0c226492ee1c27a18a2f2596eb33726b352c73770bfa1a9337718091da03505787c7c34d56f7ebb289fc8d16e18e3f2b089b4	\\x3c27e2d799c850dd1c8e7e7437387ed661e3ecf0323d9d99ef0ea75ac497cb42092cedbc339ad4e80e0766812e9208a4d485291cf8c0e3028e927de7a1270e03
60	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0bc270928310fc3ae05797eeb0e8021f12e5c25baea91615b24bcf2d29dd05a69619e1c5e7b4f7466c5cedba4fe397dc5cd7dd8f0f65325670a9cf19c17ada87	\\xbf9bdf4e5391e7ae2325f5497ea9f3fbdd8da86c57a1002e2935fad6986e10d19368e58943abafdc45335162b8135d89d7e71d861a0c0f9cc4929177a3eb7f0a
63	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5db8246a6fd34d45650726327d61fa10b1825b1d8c91776bf859151c843539cf94e09b2a5ec9dd00947fab464a481b8bcb73a3338a81f12aef189577b36b3062	\\xc02103b3d8803195dd24338a204706d879a2ee4e3278b095a59291dfc9ea93c09e67749288b3429f06df60f15d72c1219ce1902c0269f913e6d527bb821def07
71	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xc68a9c4af96888a663b4a6f6e3d4a4862660090b1cf55bc8050a3d40b1669fb5fef5fb8203a19ca11dc3b55683737b6bfd33b7d766f3f4eb2eebad03d48dec7a	\\x952eb776bd6bfb8cb4a6171e77c56637a1362679fe4db75f93e13e5492b4d79fde97833f741da375500eac6df75713d0af261a01b4092dd6f7be37a911a2cf0b
76	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x79739a0a2b2ba4d4467655a328906fd8f30f5f0f9f75e1ae90eb10ab15aed4b10cf234d020a15ff2b35c78ea35a0dc25f80025dc0b8a8278f740eabbc43e77a1	\\x2e456c00ed56197c173ba279fc49b7312e514179604a5536e18165b382460dc9f78b780a816c5cffc14f8c4a727ae2a565312f6f8b1c5580fcf279d4c3492b09
82	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x204f0f742e53ecf803a2cf1e1da923bb2706dbe0818f4f2cb43a26ff84436a9951943b6ce00da75e0efcd5351ad4b99fb7b89f13aca25fa242224048ee17f9ff	\\xa8f614f08b3b1dbef6a78582a50c7fd4921cc0a0f5f17c3bb84f5f7992597f5a38dcf45f3556a710538901be9db6618c8d12f93bbe8d6d9344faf2d2e755540f
92	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x5c1532935836197670f17b9a9c068484cfe353e33c214d30ba0ac543a747cad61992a8b868198366bd06cf41417b3ae75eecff495bf161a92ef3635d97549979	\\x28e13741b090279dc47edef9e14bcbf75a483387937e1ebae72141be8c674a6819532aafb915cbe4ed219f9b723b459c3178861a20fc5640daeddcf2fcd0f908
105	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x3a05f863c66c43fb0b75f997a4f6e99616c8adc2bfac8a253551ad4e48d2d048cd0d3a3a081dd7eae59255b9ec68155eecda15e36d939efe10e62c5c044b2723	\\x9e1b652a802d26ad41ce7bef03ea34dc236ba7a92e751b89dfda4ac75bcfb1b45dba921781a42e9205b5c0d9bdf2c47cf83ed6e56a280905f4f00df05901f307
113	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x16bbd70cc7e8249b2c1a0f12fab8be0c930f83a93538e8aa040cffca4e10422e774678ae49cbce79bd9bf28c1bbd105add5f31dfab19db75c711a65144d7e9e7	\\xdc4a4e62c7877092eace768a88f8220aa07777d8b539c8da300651e30096155816cb2e9cea424a103024f8814065282a47a4b5ec36251d1baaf78b9ddfe02108
120	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x0fde9d1d1702735599cf38cc495adfa8042fdaafb14fe64467826a2f222a7de27edee8d01e41b03bbc0c09f3be234fb6b5d3ec39e540a50d96fc31df706731ae	\\xfddebbbd1e8dc085bbbcab16feb773b0608ba743636b686de6bae5e120375f2d651de0b99b44b834a88f193dc59d4559686ae584124f4f72abdb69e84fa86804
131	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x36174ae8db37b694154bf300558cf678b1e1b6edc2873b7a783befd94d70edd6632d8b9d24f646d449fc29f00e7d703a65cc68759bf77b992b7821e22dcb3ed2	\\x8527f48b84b066bdff2dac7a3b339fae8fdb1e62fc2b907c2446d514e3ba366bd0d5cce864f6ab2f7de98e445821ffa8070a5f2fa954c92d39d89785d12bf70e
141	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xeeb73853768362e5870feed88046f1107b6d5e188532aad56610c4b1b0e2c340c19c3343c3e0712431e47ba54a08ad8a9a9bca2b8cf0c400cb95b4e3ade34762	\\x17ccf9d36b4a1064038d39bd6b9cc0187cfca0c950250ecfc5be3596a642b3de326f4a2284b2b6b1975addbdbcdaa17a516440dc45c324be15448a53132ceb08
173	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x1e8bb962e8200f0a5aa7758af4b7cc81f9249b8a80afc68cbd2ea92fa6a0fe423339b094bb64e7e8c76165b2dba4bc2c52596b5dd6045890676af06600c40ede	\\xe30bf31a50881eadf7c945f68b98cf6d585c99daca0bbb1337f5de35d2b083bd2b26e939d96185f92680511f05615be5d1be979341ff8bdde8b2ba85ae88df02
205	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x70444869f5745da10e0ca5108ae2dd36ee19fc8253c4d264c012a564baba6deb64bcc3632ae38fdd855730f6b2274c99573f96bd3d4f569849da0186b42f9128	\\xe104f630d5ead83e59917ff5bf49928984db44515c609fd9da7e7decb7348ae9be3e2a8267ab28ee2d4c2c4241d03b6599e24ec69e8da3df585b0d3d57036a09
221	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xd44fe91cf88a2b7d6b98e0fde24774a9294a2b84bd8d180edda876e409fd63c7b783b73f16d6b51160cd3b7f3ffb3ec819c1557acd57cba52ea4486e3e639976	\\xedbb236fdcd341b21037f0cb29df756f374687f5eaf6a457742e34ad39aa5253c7281ed640b3767ff9546c3e4584e5650463b1fce650941af7ec285aef2d9602
263	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xe7f653d947a432ed0cbbcc3a363a2aa82f45c4b15913d73d7c12c90f99fffdfb2086b050369fec7f068e622cd6d52c8e134c5bcbc27f89bb8d7343a3e57e0745	\\x045d603b53c0f552d8826a0d31a7d70e2dd2b30bbd871369aa681e602eedff42dbf810d17223e3218d83f5abc13c86d2d26893e7051073c45de9abc3c70d750a
313	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xafb76f21ca4ba1777ef5949153858182e8f4b11f09a670d645ab8b95535035ccf84827876ccbe214534ced9dd85dabbbfd113dff42a01deeebaa3e3f8a9dfeb2	\\xcf214e74fb368c65c625f54c51e0b2cefb0e13b8ba598fa929108bc5ee01450eaadd4391ed0b823cb0870b5428a0a31e2c7cbe3d9a8925c8ed10ee9fba757d07
347	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xcad8727c2aaf4264d030ae27d0183ef8aff215de16c10fe74f9633a3b766a1a595056134d70986f419bc3b7762526274ed1cade9e604cf025a16e2c961b19be0	\\xfb2c3812e94aeea2de87d15205d1f1758dac41877043f8e14e4445c86616b0ac15bcb6f4603dc829ae37c316236819ea8ecc61c080b03be362324cec14ee0e0d
384	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\xb305df2897c31f2a0b4d04f1209162c5e470cf73b4bf5cd58bdc6c83aa3cfb0e82565aed2e483ce7c2bf1823ffe3b1f7af547b1721900c1e4233d042aba93b7f	\\xad58782c832473c6770744082db579a093abac3cf2b82744886446e9df2e1a0871a15cc530ba6334077b27d13904208243e0a010d26393bcc46f12df629a8505
407	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	\\x71aa9f6945814a161060a1f70a43e0eb921495fd37c54e9e6d7adf652e4061ce42bae02bb097a8b9532098b69ae1993cb8ea15e12d1202cb9a750165b65b5e94	\\x3e431656538073f141f1e638d7b8d931d5cfe78ebf3cf22ba4606b25d6f7903615cfd6acd17426d8730f5fe21e7954547e1f6c567873867b0b75ef8e741a1e08
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
\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	1610056087000000	1617313687000000	1619732887000000	\\x1896a8766f9e6253d8a86187f37138656991db396bbf6ed11287940cab562be7	\\x16dabe0934911657af435f634e3ac2e861b06344aa8840b007dce147158db80cbf7b0f526e5d461ccdd0e3784cf0c7dc7d711398ec871684c8f2ff037826d20f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	http://localhost:8081/
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
1	\\xc108f73348bef5793d391ac6c16305399c17bac24d5ec793c4edec37cfa301dc	TESTKUDOS Auditor	http://localhost:8083/	t	1610056094000000
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
1	pbkdf2_sha256$216000$S0Q1ILg0pap5$pzRlOcjWlW5sa91M4TX8GQF+t9RnJcrP3Z8pQv7vAnA=	\N	f	Bank				f	t	2021-01-07 22:48:08.291468+01
3	pbkdf2_sha256$216000$9aQAwoTMTU3y$/93ZraKq7ylTR7v5s1342D47qq8300mUGl2f76nb6mg=	\N	f	Tor				f	t	2021-01-07 22:48:08.46521+01
4	pbkdf2_sha256$216000$ypd6a0c1W9Vb$DRjinQXKusXzNba97bgqXhqkGdEyTHJZXNmPx1Diq1g=	\N	f	GNUnet				f	t	2021-01-07 22:48:08.547765+01
5	pbkdf2_sha256$216000$FDbiq1q4cLBE$IkYmyy8yYC3SKbysKVj7XRIojlwArPkGiXp+0wOGR2g=	\N	f	Taler				f	t	2021-01-07 22:48:08.631522+01
6	pbkdf2_sha256$216000$3L5ga78v8gEp$imHL6U8bnxr+Zr75jCYMvIyAACJyZ1+qXVRsyawlcxc=	\N	f	FSF				f	t	2021-01-07 22:48:08.714572+01
7	pbkdf2_sha256$216000$A9R7uiWkB6pu$yaga0Y2gS6ifn33bj6++4QrUXhsspJZxGrEfM3fXQWQ=	\N	f	Tutorial				f	t	2021-01-07 22:48:08.79762+01
8	pbkdf2_sha256$216000$Tc8Zezu2Y9Dd$OPQtHw4TU+WOkN0tCH+lS08oQNwsCoS93/tpotFwZw0=	\N	f	Survey				f	t	2021-01-07 22:48:08.879127+01
9	pbkdf2_sha256$216000$EIORt8ElNda8$pyiVqfeCTgaCkKg9Uz/Ozv06A9jhM6hDNER699iwEcM=	\N	f	42				f	t	2021-01-07 22:48:09.348567+01
10	pbkdf2_sha256$216000$Xl0aseHT9Hg1$zKPblOOy/vawS0cCIexRk1cFIqDmiuJQj0YN2j832Dc=	\N	f	43				f	t	2021-01-07 22:48:09.816567+01
2	pbkdf2_sha256$216000$RpR4MAbG6CHN$o19ApWeHGeBhAeev8NL2BYK9fBOaKxScD+F6DdBbdFM=	\N	f	Exchange				f	t	2021-01-07 22:48:08.382705+01
11	pbkdf2_sha256$216000$ujs4uBGPSC0B$RfKaGWpHYScMPjfbA3jlWHLe7o1fO3nYUcFiKrr50Co=	\N	f	testuser-wezXieMc				f	t	2021-01-07 22:48:15.324682+01
12	pbkdf2_sha256$216000$TvAGQaAVEIay$o/f3fovKpnlqCDI4Q0ud/X/AJDca0XvFButJPGVrdBk=	\N	f	testuser-pHPzovd1				f	t	2021-01-07 22:48:32.828362+01
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

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x04b8afe12569ab87853fa8209832ad1dc40ca2a6bd7323627c9300010e9ee27c090ad63154ec2b1d43ab9a08fcaed9708a7ad6ce81544097092b56e58e5efd1f	\\x00800003cf4c25553fde75807fb11753903e3f216c9de2765100a4a4d2cba646ad80fedb8ff0a4c62f5e78034d35c7482b8f3914f180c520c898d69a1e503b46e4bc34d716384a59882b671e7e41c4c39a9254e37591784ee8bf6faf2b95f652725520be10733b048f8277b380311ef203c6c41117059f8ab6e47fe14eba6ad95d762c59010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x418e882dc9cf35057b90591e1a51e5cedb6bf235c2fa5bde6e93a9c1e1f47e6673b92f28198733ef584d0580cf3fd13074a7fb0ede913827feba09e80ae49902	1633631587000000	1634236387000000	1697308387000000	1791916387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	1
\\x0974d47dd3b4686a745c3f84166f61a7946a47f6285b04f233108360832f7f5dd7b96cef3ecb639a0da68fcfd96771bd075a15b05d042da3184c390fb71ffc8f	\\x00800003c4b45114761eed55254ba1a4e02b99ecd4959f032866bc79edc09585d1ba88bdb5f99f69e91ddc1abdd7caf76ed615d5497c415de7a5112468fdb3f8484ad3327bfea8055e76c417ee24c426d25a8751ecd8d99c54e868a0fe8a8fe851f2f80d2f0d82fa185b6918f285b004ef971858cee09f876cac820618665901402e08d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x71f6532967047b09757854dd5daa9ff492e10c6abbd1414f4bc6917b89017d0f97477e72aa695b9def14d873a8e897e008f5a5e8d0b95e15275ed5321401660f	1618519087000000	1619123887000000	1682195887000000	1776803887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	2
\\x0afc20aae1d81eaa9ea530b96c19346fc68b8797771641efb870692170d5ad0ce4452b0231d5ef891c90b728458ba2dcaf0ef4747ba286ff5a924d928a9a05d3	\\x00800003b099845276edd3cf10250003599ed34001d3ca32dd10e8e42e076e5cfefc83b9adb736b5d0266c6ac1d6524a9cbce07edeaf7d83264bbcc77cced6125626716534a93c683b00dc52bf3302d68a28920b07ed06c34fee81915d60303c81768d3a4c804c614b0a666ed488e570643f61e3d79ba5299e489bc7245777748d865a63010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x50f03206758b51bde6b15b4111584f25da9ea7399107c892ffa020aeb72222a30c5f7922079fd459ccb8185244b73d81cdca36872e548e99ce197d158669a403	1614892087000000	1615496887000000	1678568887000000	1773176887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	3
\\x0d54892eddb591880f7e837a6fc9413b2eeb2de49939d063bd99a6ae44b1ebc24e03c0ece36c85ed22b4b659196b17bf19500699c2c14403bd975dfd8514a684	\\x00800003be8d7135343894e4599a98419bc01ea0e9242d62b44da2e2160631bbdae5ee3d6aee051dcce384a7e88804df68f45339a5df243d17de42539ad01b35d8f20bab63a369d0814e01032a5d39a1575002100ef5061a939579e04a8a6c58b141be989c339d4efaffefd5528317a90c6d202c2a3bcc8f16bb5d7cfa3c4c7384ac0873010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd02df6ebbb8726782308e69b0d2afe898335ec918a2b49f0708d3a79620c99df6f3154f054017995e07c973e1f16be923b302d0707b89e4f5dbc83a6554f5c08	1614892087000000	1615496887000000	1678568887000000	1773176887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	4
\\x14d4ecf3474060987df8b9a887c2eb186a709ad1f03d35bf26e1dcc1d4455eb71c76c33ab868a17747ae9cdd45d011d3ec3bdaa9089c516d42960cdf202c186d	\\x00800003b921ecf57d213ee7f72f05152c65eb9ea26a06ae472f176a5cd3f16f8c069446a8e8ba30bf323e5f31fc62462a6e08236d31bbadeccfc1adc0f647f03904706f70eaa55886faa8a943e4d14943a62edbde46b5a232d76d49806831296441c50f2e418b61f33e8d022024dead748bb7c1049d166d4b6c84ac9f128245de767fe3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0c20a53575f8a50ec598f3e6eab27958408ffbbea5344b71043f51dd8a4b0c576dfec48949ac59413232e9ebae215566e8b0fc5675663686136d03d71c8bb908	1623355087000000	1623959887000000	1687031887000000	1781639887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	5
\\x18b49e6771b98835f139cb7dd6f6df1c7e87e1a1c8c103f0e6d9aa48b8418541b66b53465996d0ab2bc89e1c7cc9e3d643024ed6559f696718b380dbd54ecae4	\\x00800003c8d0ba20f5c5301dc4f670bb1ce4ac89230b9890e1b8f1f8930e2b9eed600bc447809f01feb20a325a05307145cb3bed57719beffad507033684490d224f09c29f8ecafa31fd4414498df6e27982e68b355c5d51d0d32512490be76d29f315e09cb6964fb3aa7b4ed53c6e8868ffb322a1a3c4d7a56168f4b32438b297408f87010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb86cc2462dc44d922a0cdf426fc17d92ac673f80573710a5325f2be7ac4bb771bbd49743d48c7c394c6d8fbd2b8b9abe4da9b47d50bf87c2da351919e3468600	1634236087000000	1634840887000000	1697912887000000	1792520887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	6
\\x21e0907d79b5852e0a96c2a925bd54f480e49a3c33aace34b40c8a8c3dc12f7d09c48f307ae4d293cc85bdf65c3f1591c0e40149e9433b4b256811a9179f7ca0	\\x00800003d24c81c8f93bd7e4445698a048f5a5f7f7cdd194b8f4a855f70a6bab3eda4c5c57271fe89674d6dc48137d4b1eb04852eb6140f11118a29ebe42c4276d124058a22bb2d302156f650105adaaeb4afcddaac5174e5a8efa8235d22b1b1b39ac9ccc089f44a27818a7540071d04519804b58f1cf8861f7a8f706f32768311db01f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0a8b85af0994528c816676b66e402e529d3a82f081112650ea8f673b0d26090ff871ec33729c33f25bd9c27c9c95af90af90ea663a114b45870276be13d1d706	1626982087000000	1627586887000000	1690658887000000	1785266887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	7
\\x217c1c8321a8eb04e090fb4cf8a65938c907a5e5bfa0ac4c97d4f5fbdc1c2b6e643031e9f88be9d9ab8650b7c8f45801eeb9c0e4fbc7d69d27215ff6805c4bed	\\x00800003c60255daaf13cb6707e4921c83ba3241b44aa886cc4fa200b789778122c55d69cb59f68ff95e12a250850ee22ab0a68a7d27f6c7aba925afc2daa2ea85c63888b6f40da9c0e28fcb01884b2f21007042faaa459504b25a65b29e86729e28f8a357243afe6a472ba5f0c3fdd0c4ce7f3060d68b55eb8020b029422c9d4e602555010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8667e44705d2bf57ea6896c670c899d10b3e790d797e72d5cbe463c664a2724da33521abef621b210d613650f113c47d06a67772dc29a59b9612e7871c877b09	1625773087000000	1626377887000000	1689449887000000	1784057887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	8
\\x220053deaaaa4e6f5afbcb3ee3d3fe67981ad36defa45d6304edd543fd8ab9aed5484f2cafec7193b7771566e0f0882db42d1496c34f153dec75e92bf04b5b54	\\x00800003e6abcefb37250ffaa94cf576136aecaeb7781e4c35d5efb6281169027f27ef49a7dbefd14ffba9ac466f512295ef716d902832e0cc0f97ddaac44e0b1e5053fa1e96069b028a1b8948790a43632a77f905a32c297d46b7b070fb0ff29cffb8ed3f19efd7eade59c862483681a294a4160f2021a09be5ca65a75d12859a80a7e7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb9af822b6c193ee0ef7c1e2ff462fbb91326b91c1e8e1ace08ba1eee63e59bc04ffc1b37e4f45d29e61be95bbe2d7bbbf7dff1fc6822174361da2de7be3ddb00	1629400087000000	1630004887000000	1693076887000000	1787684887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	9
\\x23906eb74cc76faabe6a567297cbe7a56f488bb5747d0b6986869f96269fc643e3e66a4d7a8ba4c921cbe04d47541cd335ef55121654b6d244ba997f138e0df7	\\x00800003d9b78e4911df0312582d3ad5e0b5341ee0b378cbbfe5342ef47803f57441a70da280a096785f023bf7a362c1270f120b5874f15675d45ae1e7cb02770f60120c6fcb5ca36e8f3d72708140a546136f6d3d4cd9247f7fb17d63dcff06e3e3a9f9bb38b8c43b999669628f5c46132b9665eaddbef03cc7170755ad6f41c9d3cad9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd91a8fee42d885fa763c7b6a25ab8c41414ca1d1ca42cfb948ce7791a6f9d3367cf3f43db8d89a20f2adea6f7ac281dc81b6afdd6c6e7dce05eb17dcc32c2306	1633027087000000	1633631887000000	1696703887000000	1791311887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	10
\\x27706853f765cc0fd712d3cd0b45b42c9282d184c2a6576cbb2a5f71a970e990ad4681136ca1a8b2677796e4d6615802f9c283d975518459e5aca67fed7a2968	\\x00800003d82a8a4b19766b4409c9b9a64e4a77e14de11972c4352192662e259672f00598aaf399ba009d95454817ca40ce43407c1bfa369f73a1bc17d712a5a02caab98324cf398b58b9c426a952b862b7e1c64fcc82ba2bb85fe3faf4433bf95619acd6bf16cc982584d6878972526fbba30fa255f9548f486e0d9b74f61c01db97fc49010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdb242d9d841cc0000af37ca3996bc0499a6c80a1fd83bdc5f728acb5462e6d472fa5731966ce581a15bb1e3b52a6df46148f82ae0a77e93d904a84a76f5e990a	1613683087000000	1614287887000000	1677359887000000	1771967887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	11
\\x2778a077e5dd7fee0ada34869d476e5835804fc557cffde4c3d43b8a664a99df3f7eb0aaa20a2da17930ef051f4580acc175792619b0c94c3a46938bc7591d97	\\x00800003b9384b55497166529eb913ae9364c9506a89dcbe4555b813b843df0be5d3f154b1fd499ec68a8f287b198c23db28956d0ee3bbaa9d94be5ae0cf371f9e5d7b31bddb14fc1c1af5fd24afe5d4ccf902731fc5ba94b28069ae237c8dee2c51aa7359128ddc043fbfb8e61d604daa1c03b9768477f5e50d4c7e7aeb309d8f04b87b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa717bb64f8a9ecc8bd487234f86d4e0c90cf79812d444964ddcff5f722ff8264b3fe0bc244de1423d61bbddef0ab2da0f984765d4586112c92fba0638f462e03	1629400087000000	1630004887000000	1693076887000000	1787684887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	12
\\x2740ee2cf51e05d8c0ad2489cdfb7709da247b4b01b30df6f6326b770d7c35f9fb3af98f99e42780e654c3f0c6cc1b9ba23a27fe07b3d57fe343aeb8b93f5930	\\x00800003c5e49447076642d6377646570bf7004c2f2c05f25248e9b8a2947cba868c30e701b4dc3fb1b8a9a5bc697bab4d76e33153fbcbf7979bb17ca53d999e74d18846a8d5b224cb6c10aae01eb6f14551e981609d83ee17bbb4bc550c7c2e050b62991d9b276883b746bfae98b7e7fa0694218def03398426b376937c0e05ad0224c7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xda016dd65afe7adbee74923dfa733f3f1ef1f8da05ac2d5baacd504b6401c8f3cb92747a2a3d23173f4df82e66f6e844e1879f08d9f8d0cf1601599af1af2e08	1630004587000000	1630609387000000	1693681387000000	1788289387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	13
\\x289ca3ccb60af17ef1fa93e5a94c427fd865f24bcf9a211bb6561507af15186401ab40e9702a2ff3e40d32d70aacfa57ad68e3752e02676dd863a178eace942a	\\x00800003a61b6fc3f16546bb35e5c728f96a350ace4e08692675359d6ed236ca61e7014c6b46ae797363b1322b7a90c77d90fbf13b1161e45ad0c2c126bdebbda85860004877ba8d11d999df0bad7699a43a40b2c18026d785453de44f13c5576dbe7064448ff6ee3cd7361f55c36e7fddaa034a3bd00e65bf7f6fbfddf8f22d9f1bd001010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1b08274e21a37d69ce2aa15ee9a5e2e404fd462f5e7fee4553cab6482bd83ffdf7c8fb114656d2e765b7b69993b6dd2f25e775b1c35646e33b39181004729b04	1633027087000000	1633631887000000	1696703887000000	1791311887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	14
\\x2b6c114d7cf9613afb1d2da6c644acc57f7f802583f20e179ab04221978f851ebe4b0730b664908c2a7c363c527d01e31c50e6114632ecafa8b52abb8c8869fb	\\x00800003d7533a512dec5597f850fc29d32f44ee5b61d25a522fdf5fbac4702464cc3bac567d8c272aeb712f4b6f053d745924960fae0ae8d9d48e09a26248e14a41396574d823a980105491234ebb6b386a7e95e594fac02baf9bcd5af0b4c8e002c84635a9364e40a0c3319f2d0eceb67dce4c33f083c7ce543984a48c1c6e0a4430cb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xedf6c7c1de28d3bc5f33e8505aa34fd5544ee50285b232c27b6838ce9e78929ecf5eb5f4086b4fbe2229b04dc690ac7f5bbd3fc3831cb1a2b67809648a6bd604	1633027087000000	1633631887000000	1696703887000000	1791311887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x305462136a1cf1f40c4234d8bf8ad59e248eadec85160a85e40f20b22e9ef643ce57626a6feaf23bb997f4a64ed6ebed01215c26883e49a33047c2317c4fc6e8	\\x00800003af17fb5b2a9114b546fd6f264686f020ec44422acd53b809e32e9e3429eb71fd307a75ef88e5d85e58964c184155e04f8f9b7def06d10b1630510557c5fff1f3e2802fefc1844a21b606b602a5504402b6f43f02fc03a0bccf310b0d28b4d63af44b6736c17442999868d65ff0391862edf2197ab3af377ce089735d95304ed1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5879420011b0da32128215be5e3a916b1a9131487f42f94418015b307a30e02fab85becfd6a1f9d076c7b9e1a5db2b74fe6ab9ba034a5fc26b1924b763fed50b	1625773087000000	1626377887000000	1689449887000000	1784057887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	16
\\x369807becf9eafa1b882ca00b65e31ae34b20569fb0bd1315bde2c937ccc1573bedab5b9f1326d26f699c1ed8e896bd392b5a9cd32ba1e9c9ca9c0e5e5cc4988	\\x00800003d217a88bbffb8f354a18da9b0bf8343a7de469e146e72ecab452284b72d73f97e23c448eed10035d0b056ce7d98e7b35dfccfaa08a131f4043ce9d6721f7a46a12545bf8fa40bd406e5cad994c25cb75b050a0d4d61631e0353a9cae6aaf700e600656446752061fe8503fd9a3d7888fb226e50d7e6a16a77699116ea3bed40b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb6e60ff456296b623f05fb3cf852997ee33201b92a89a8fd4d5f25b9050fcfd7471f2150066ef544c25df16068ca2e8d3e7929486b20c45bf097bd7e37f79404	1621541587000000	1622146387000000	1685218387000000	1779826387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	17
\\x3b186af8e2846647ca08176a42eb8a7fd479227b30b5e8fae2b5bd836a3cfa9a3652291f5c0987b119f6a545950689f7ace312445825cada17911e9f4303a9ad	\\x00800003fd91dc701abe9195b9e2920cdea6286417e2d1d6d2da51517cf5ff44fbaba3c9032916166e6f0adb3e336d2872273c16a35a421c191d05850cb22dda9bef890007af97d64776010121d786719eb8046e354bd1460fbbef643c9a24ee93f884d77783deba4493d9cf290de618d9a47d213d099b285e3343840e46474ac20a6aaf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x256bf7478de5450fb7bd44d3eca69e8e5fbc86ff85ef9010d91982853db00bd184fa4b33431b45de762ef31aaa688fdad6379c243e0a92420984b018ea041401	1626377587000000	1626982387000000	1690054387000000	1784662387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x3c245ecb0b12a61c4bdf826d89a7b61ceae7346f678786b821db3f30458fb37afc630e5af01830a0f78ecb2cb547becfeb62b826bcea47a062e7222e0a0c1c37	\\x00800003d7092a024e926ee63cfac642160878b93a127d4b606c26ab4f5703391a965a486557c3413c34760c0f5dec2f987ec3d6407d8475e65ffeedf3f61584c857aa0d9780217972393b1b51edddeee554984216dfcca9b48cd70af8a46a325b872478aadb4b0e267d2b579c74323bfc75a7cdfc3174a537db7fe858182002b5c6dc5f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc9cf16cc6211a89354740cd12e97b3406809e4ecb1183291dc2f175c6d3edc4477baa80190841992c2d3b313993b44d0fa3535d723474338ee017cafeeb00801	1613078587000000	1613683387000000	1676755387000000	1771363387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	19
\\x3e6496a84bbdd7ecd8f1f7322b42728047ca2d48216d8e88ac0be783ff16cb290ca7dd45798f33b62f5587b54555baf2b4f866e3136216937689099979511f7c	\\x00800003ecf0c4aeda77ae32de0160a103debe11fddb32e7a5833f5cd881cf9f0a7f722d98b54daf3e766f344649359364f113f98c88ca5b32420ce5f8c0513c1129beb2b98062f52ae09958739361df4610ff3b902ba422149fa1d77225a9e2a095377d82c8b56e0202710eb1c36ebc688b9e9d57878e47cb9b4d7ef4d77fc290e9e849010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2fd6374fc31ff7f61ab71cfe10d25c3ac9695f62c225230b1ae2b9d715272574ef0686cb9b346a0083905d98f38f644aa232e779bc51793f4b54603df271cd02	1639072087000000	1639676887000000	1702748887000000	1797356887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	20
\\x3e00bf8ce2b098004089de607922efca77d81a6d6eee47ca8d3b0015afb3dd5e8078cc10f0af74ff0233bc05f931da5a77fbfb46984920d200f9a48a4c075f57	\\x00800003aa009daeaf814ae6dee245cabf03e5471810359260c5e9f06ebbee98aa7d25f835f9918c3c3a341f082176146224ccc2af9ea36518f82bc59940b8f060734d6d7c33803bd9a1066fd13669062863443f360f354eae8e628d3e9589c12686bc254c5520f90c9a5cbe8dc082967226ce010935c97bfed1fb8b19bf12d88ca08f0b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcbfff68887e353c667b1d7b9032b6ffdb59f797b014deffb4628625cff4feb75d8c72d94147d6e5d67bcc5c9fc9acb5a3efb42bbee14520b4cddc9d849878005	1620937087000000	1621541887000000	1684613887000000	1779221887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	21
\\x4144cab4c4bb20f27f8c536ea3c19193e8d4ee9a7f621ab434eb72826873340913e0fa240178e7a3feba94f00be2527585fe7e147271cdda01661263bc05c19e	\\x00800003a751a4cf113d287f4f0b6e391d235e7da1170bb349fbbcb5ea6d87daeb0e7ec51d31cfcbe37cf24a7f97fd5830158eefcaa84b7350403ba56fea45978129c1cc2912ec506cf6b4d8c79587d29e033380b2b59853808cea89e00badde0c41250a6e6d8b03374af8ce096c455ad2f3d300128cb27ba0765808842c809d25093ef7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe1d466336d59a1848a9c4b0738a0cbe3b8493d9c577bbc1c337cbb1fbe177f3416a5a26a6eb12eda827d9abc5a4d7d5976c93f99a47ee2e1df64f416fee9d001	1635445087000000	1636049887000000	1699121887000000	1793729887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	22
\\x43e0612bf97f8431aff08f434a6a4a813e82754a676fd32bd611a128eb6a00e7989077a960ae2f9c647356eb8169daf6571ad9d7e6a5f0b2c1afc4d83b18d093	\\x00800003bb37266aeabc2a03418b900ac9f35396084e324cbcdd27743a2c1b9cc25b5482a730d420a74665258cfd273aa49f6c155d28ed8b23c70a06490c74a5e20543923a3b9a881b32f80872f16fa38b24eed7b931e7cf5fac5c4985523fd20d4fd1eca83cbe56f605ccdaebfe221dc65a46f56e139d266dceb073cfd6d087cb2195b3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd17e1ef54f9b2c5bdad55f42dc1a11115a93401c220b2cdadac1e83d8e1184b0ad7dac2e10339e6c5c9a709a5ba353a06e5c43dce762e6331f7437e0f87ff607	1640885587000000	1641490387000000	1704562387000000	1799170387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	23
\\x4a50253989dae5372cbedf7fc3261eb14c217a5023ed3b2219e8856aa234bb2108649b297ec097aabb6f13481713f455d03e348bc4f160b2459d9de15115cc00	\\x00800003b7c167a6b77108a7f8ec8376cf3abce6d9225cc76dc62fdbaf3f103a4ce8dc75d929a655b6ad955cc5d71e79c3d4fae177bfac61660f24e3c396905c2cede40ab1547bb51820f9bf4d850188a744ce9095ba148baf61f5dbbf99b9648b6f7f2f62922a667ac10fb5798e03d94569416330830ca3cf83919593fe2b56f5609201010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4949fda9d3cd2b531514f60d266c3c08b303683192b06fb4456e62e4a7886c273c8b63eced454e8d2ee56d0073cb958743ba431d1e0f65e6a02d6ab9dad94e03	1620937087000000	1621541887000000	1684613887000000	1779221887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	24
\\x4c7cae07fc58863f55f24ff18b791edaeec3a7d36fd8d8e0ab0023508b8c1f05968c5ba4e1f78d103857ec8010b9cc8a57575ebb49882b557aff0c23273c3e6a	\\x00800003cd958752b84c9ed5eb59f1d423ef79e2129fb22402682910546ac0a640a70422ee4c5cbcc533348fd180aad290ded946f458ea1cbf05084918d280b90f3ef92514e7a6a6f9566b834131f5967fae2e9d0941ebcbec48f70724afac75a583fa05cce333c83b7a3cf2cfc507fed4e52562bdaf78b54c6654485840ab111b0858d3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0417706cd9ea49d9e8e7dd11e3b818393d5d8906b88c703b06236b26cd24a23ca15c5b3076a02d34f4428475cbe638611b2507719cef17769b5b2bf5fa33760c	1640281087000000	1640885887000000	1703957887000000	1798565887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	25
\\x4d083d0e37f3209631eda06e229fe09f47a99a4b0fff7bfab0cc6c2f719b681e57c0ba375922a63e0dbda77237fa0135ec4b7918aaf4e8eace7e04a73903145f	\\x00800003c165dd4dcee8f12fcae92378bee8302bf936747911e89f9b781ace9b77a538c29acc5cb2844be745adfb33ce11be86ed3fefb5d47d64c672cc1e9a5be64fd6cfd8d9e49cf09bc4a600ec2d17559c849e725fbb4f4f4624f81e8ca7b7fb56161e811cb8237739c9e390c5348af51de62f4da2b28598c431421cdbd4f575b5b02d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb8727fb985bf77061d32f39c3195aeecd78db0dbadd11c5f30ff1d9cdb757a58880b89f1ae9f8cc437fee09fb1f6c87dd73b6f1b214a50a6371a8f2a78884a00	1635445087000000	1636049887000000	1699121887000000	1793729887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	26
\\x4f74dbdd8370937e54a0feb69a91a28151b1b05d94a81b4008f625d71b34d63f8c9a5f907332c8381e69d504f2ecedfd83b8ec505d130ce95c90a943ee819dc5	\\x00800003d694bf99c1d58d3469b5285a9abb671eae13976d2f46f04eaa7ea1cfc52391513e2ef683fee29d6a1613168aa235fb5c2a175740191000cbf7167096b631e317e03d6aaeedbc60cda6212465c609c78032d03cefd2aedb8bf4ab289091846347ed334f19697552181ccc004398ef48de0c40b6b85af61e7caf1014fc9a93e749010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf69c9f752c1e32eb5dca735ee4b16b499c6340bf7d6bf04d6f5e1478cd167dbc33cd736fe318287375ed5270363db5f9192ff84e815e2912feb16886d5776e09	1610056087000000	1610660887000000	1673732887000000	1768340887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	27
\\x5198466e78887e2139b813cf66d1cd6b2d60dad4ef6ada0b04ff508fd07df5e682d072ebcf1fa73cfebc017bae564d697cc709004abdb96e3b4f2517127f77cd	\\x00800003f98bcfdd31668ad87ce2de4f43d456eb41ebe36abc6a040255819596ab594253307dc85df0cc7d1ccbd208a85ca5fc2d8cce7c46f972c9b75c7dee549d79a0a87a59c4fd49a463ec7cbd12a9cb5750a9f069696b24aab9fc999de206b867623bcc19e9d1020045ec972937c81f6d5fd8800d2af9a411e86206433bfd88c8eb1b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa9d42b3d63d9278c323936319748fd2df1c9797943d66ed0f9fbe5edb1ac02ce57421ceb7019a620d34fc79242f90a58da017ceee17841d5d32775533553bc05	1613078587000000	1613683387000000	1676755387000000	1771363387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	28
\\x53f0a8459c0441e20e61a8f9141021a921923843423ca6288f6a15ac06443953d98894dd09e57b8a4c2150d16c6a53a55fb02a59427d12727bee09957d04f8ae	\\x00800003cf854339efb4f25f6480267623de57ead2e4f10ed8c3731d2e909496d73c564944498b995e079cfb9889b8237dd6ebc601fbd4f812dc483240da9cc057d66f3a5f70103d68a40892724981090d573befa30b40039bbbbb959ed438b02503a40a0780c9a4e63ae67300f341ebc6fde94998ae19ea24addc38cf8bf6b539b303d1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2f5d8b7afdb28c4dade59d0d0d4648deca612f4935d8de0659ef14a29db4f38fe96f36ade452d0526e96a50d57f401acb6ff6913722ff36859ee58f3174a5c0c	1640281087000000	1640885887000000	1703957887000000	1798565887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	29
\\x57940df86d177b264ab7df35bed18d7c80b1e31c39ea62cfa03f905e18107b6f07aeca4cfc146866e542414514743388536d0d6df11c70b19c950b2fc84b4d2c	\\x00800003b6cbcd4db1b234c7129670a4a07485529d965b75711ef393c7682178a93a5fe26439f9db28f94f9aad7b7668e5c4728f8fcae160a25c0867489d32bc3e0559c0b5b24d117e9e9b2bacae73678e4119b0e3344dea001a781dbcc2cd48a2b6b9a527aecdea7411313c468b2b2652a05debd8052f708c268c766492c547c8dbc76d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4e43f88ff821c1fff44b79130eb7a612bb498b4c864469b8d67c837b79dc8815e7e6a5f5513d260d66c9154054540c0933d7fec64e3f792d198350c043735802	1620332587000000	1620937387000000	1684009387000000	1778617387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	30
\\x58e4e4a3a8314987d2f880ea51ed326e542d3f9e39506c4111893dc309b6d08582c6cf47d447e6845c524a7327e9b0ea8f9d5f4baf6e9cfe1634cf184875ef50	\\x00800003ca2d426730f9af24343cc75bb6001f143f743228ac113b8af24537a5e7ba94d918fac3655fa1d79b807f221f5c25ecd9dbf9cd82e25bd85d8a5e9a0ba844d5ea10311a97a637d89ee1faf9c684cd30c17cb6cf1db2a91226f703925b87758c11d4d0c44f08be2267e9d1ebba4095fa56e4041b2b533298630914964f19a1031b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9d50e297597832ce2f2d1735c65cdb7d664b4cbd5d8735444e1d32cbaaf94618746524f9db21c53b30720295b9adf6222f2cc63dfad9b3e26f82e0d3c5c0bc01	1620332587000000	1620937387000000	1684009387000000	1778617387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	31
\\x594caffcbcedbb6c2a1541c7f121bd13f0b1fad325174e3c59a5065c00543f7ba8fb77c02ea7c4351493797abd162564d7d16101d506fd79219e84ebcb5f4c9c	\\x00800003c712d18f321028a11028af7ff7fef3c038c94270f30035773f33065be9c55f512909fcc067e871767121e4a058c526ebbc810e90404aded257612174837118a56ea3185e497b0b6488b9513e6dd9d18428814226a7415fd3b736131f6b0590a061aa1d0fed041831c5ef4683dfb934952dc68e1f285a6de053d018b358e314d7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7cca3ab7e161ddc69c4b0637b04f84725ce1afb41687a57272c50392c39fc43faa996056e591ddc29089b9c54e65bb9947f6b32b8ddd138c47088fe1a8214e05	1633631587000000	1634236387000000	1697308387000000	1791916387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	32
\\x59c0422241063ebca3e3346d222d692c31409d11f618f336c8ef67139f6e25afd1b0a77142f16cf6cb0c4f3c4cb9ffc82b30f8f39bfa658a7003a3c688554a4a	\\x00800003c3302a436d3e31c1e2064fcbb2b4ea75f9aa1df774d98282b0f914b77a3e9389acd63652b4ec8e9577a1af37ffff3d00d77fabf7aca059de9fd755d5aba1686d447c4ea9e1d6d746c788897649136821e6ef0875ca725ba8e7a0ece71d41eeade6ed8b653e976ee74d6769eeeb6eb6ba5c2a6a9debcda2e170ea3353cd6ab9f5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xef2ac6c36af2d7d8d488c82472087cb2318eb113db6bc400dd3354a5a75adb1d957685daae78d4a77c83afc2be7350113d497d991d54571e48422d7430a0630f	1624564087000000	1625168887000000	1688240887000000	1782848887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	33
\\x5db8246a6fd34d45650726327d61fa10b1825b1d8c91776bf859151c843539cf94e09b2a5ec9dd00947fab464a481b8bcb73a3338a81f12aef189577b36b3062	\\x00800003c07f41a401efb870167f21642fee42948dd5f40775c1f451f4092428dd212b2da2c2d117829ab20103e8dbce2b8da8625d070c94d863afc64462783bfc84189b6a491b952ea1ba96307900ce9413cb5d6f4d5765ae18b4ddb7128424f4913eecfe272096d32b388e148b60bb91159e6ca8386a2de4168aa79eb83964f28a8de7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4c3a83362a43882251feeb99bc73ae4bb751c0552ab31abd424775babb0e48eef01a4a1925402e2a72de2fbfbce64a926c13de469a20e4d741d2652281c8ad0d	1616705587000000	1617310387000000	1680382387000000	1774990387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x5ee892f5c3b4a7b9cc15a67d119acf7c4cf8a01204fbefbed03cd9455553330d6ee4cb5bebfbd2163fdfdbf4bcb3554a0f735c1473df7621011b8627c5560c89	\\x00800003b684cd7a0be31bf7117da321f5f80f854be83150f4c1c07721167c93fca62d607ac16ad88886e50177cb35bb26951491de9e889ad1f76fa1b6db3e2fccfbb197696ec3e6d4d36d926ebc2b2b56cbab42af3e9fcbbb6ee9ea07e8537dc190d9f00dde93855056c3d338c2d66ed7d9b2b91aab4e398e9397108892bed82c0e8fab010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8a99b8944777dda76d0add7eabeed695a418ce6ed59c9d640ef65af84c87114578c545e1f73af4a70cbbe282b4f66b9fd3f81ee258289f0607c7f0358dfd5900	1640885587000000	1641490387000000	1704562387000000	1799170387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	35
\\x5f8896d3e0d7fbc85867f68524e674951220db22eb93148b84c4ad94f5a9cb278707dffb57c8f751abd631cc55b3c4c3dd460095a4ea9bbb1c018c829379aaf2	\\x00800003dca2cecdc5fc55bcef24dc228f453df44e1c1596f328e435bb51fae16919d6c4d015bac2d9d1c7eb241fe2d68aad91fa8fcbfbb55429543fdf3ebfe285f87d48bb69ef6ae32729729cdea37877c686265b6921a445bb70a9e989edfb7b190fa2210678e1acf5fa73397c2adc7fb19268cc808b680cbb22a163a5aa02a04d7a9f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x007bbc086605cda5438bcd5b071060574f595481a0ff69d67907bd42e97de638f63d4a712fd0edc98e3f1704bc5ffdc0b1e2fdd479e42b639373c2c09163be08	1612474087000000	1613078887000000	1676150887000000	1770758887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	36
\\x60f05991d9663f86563a1bda8c64f7ca6e34c9b4a18d021e7cc399b6bd265e7b636c48389aeb88ff09dadcc329611be6bc358a1cbd6691d5bda39b24293f868f	\\x00800003c7666782c23f432cdbf6f27c7a2edc5aa9fc44e18701b464de4bd4dac4f618880ee243eca7290a7b261818ef76353ee3a866185c6daf2b5df6e86a3b7cd0c3d6f913fda6352fb58205558aa1e6132259eb77e6078d3aae8b2e410e8e5db59db730cdbf75f87b19a008e7942ed76b1b4496d89ac99597e84e84902c3bff75c087010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x63fc12a3e2bf50513437ab0fee1cb730fda25fd9cc3cf3cc0499b81bcb6636fb3aece44398f6c951cb8bade8ad35eb1991f543b5b2fe2c33222c36c6b438ad06	1625168587000000	1625773387000000	1688845387000000	1783453387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	37
\\x61742a5272034cfbd0fd599fc4cf9ea5424b55ee78803cea4c7fc4cb88589c117307926cbc50682dbbae212fcc329d89b0b5463fbf32ae40fb20b1d5b80fc75e	\\x00800003adf605dc0d7b043be08ceabf6f9159400fd324c77b8bcff59a8794dc62208526c873b4b1600de791782eba6572d1ce88f6856174aa3cae4e1d2039ebea56aa1fd49912d9ec0e803eb367af14d22d5354147f1fbe106923196355162ea3ac8cbf9748383896efbe63190cb12295ce2ed8f928cb48b2a9f590abebfea76fa4579d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7ae5bbd2deaf8d784a29960c4c63ecbc001a02fd8c9021ba9e0e1e2c3c0e20d4d960c33dd37549504556b51adb03f6f71dbdafa4d6522d17db630b93bfb75c0b	1615496587000000	1616101387000000	1679173387000000	1773781387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	38
\\x6178a14f98887dc6f60e614e86198b2d97019215b9efc52f2e8506d94e93e558d7745f359a09af71d6c20addc4c5591f505e37e046dc56305aa3ecee63560735	\\x008000039a6e2c630569f4f5914528bfa9a5d35d33fe8493e4907babadc578471fd1bfa922a1861e05cefc0f6556235828076783444e30e40a172306111554d964dbb6a756d649e2df3b78b0e68ec9a9d7b4c0592e60130b91e432d386b66b2c06e291a1bc13c7a6da2c8dc5570c483c79ca867c6c2f69cd569aa91afbe18d624ef869f5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe69ea3e826820234056116392b3d29f88378d2f52ccf2ce74336a2a5b60f09c82f15811a81f8098ecb70a1fd4cef2996a0659d54aab35bec25eb1d282972b50e	1625168587000000	1625773387000000	1688845387000000	1783453387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	39
\\x62483718592cafe927c539809b1966256414fbf885fe79a3d337ec71391ada5fad7556bb022fad22bbfdd89f5e036652590c933064d6e2c1bb435c24ba557cdc	\\x00800003989345f35a6ca6fdea78787dbe44924a50d86ddebc8cad49e4c7a1e76af3487db68b2563dd21ecd5db2476288c5079ce307a4de5da0b8b180a99e3f44f074665d52c518f96d52871e7f630c4c286169bd7c6f55f8c81109cc7716b77731a73f503d1ef45de499a074a33a55f5d1e76f43aaff6dea212956634a4485ddffa2125010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd2605c3701857bdf0f07a80cfbe62ad6be0b76c2e99cf88d39c57ab65863e40fa7b701454a5c6be8ad92bc7e7c15e3d7d51163863db1e63e9fe9ead56a0db407	1614287587000000	1614892387000000	1677964387000000	1772572387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x682c8451901fa24322082bdd76bcdd10cf1632d39620d8695486258c2c60338385f556bec3d4c9c392e0e668179e8727400c4a59089886639b0da0c15c818e19	\\x00800003d26c09c74094e58233367ae3b33d7cc1a283990140fe99d0d85680119ef7e200e1da77ad0dbc3b2e1f2cca17ee02ec1b57dbc645f1b19f9585958a1dbc3918f5f2b79abcef6f9445355cefac0ff817fab82743f1c7478b37f8549a384c6a0c06d19c3a3097dc376e21779f0a28d5a4fa45b1990a53babbcebed6732e20f31019010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdef24f5616cc6ae274c135ee64d4b87bc0532aef7bd1b57db1f55111d22eb004964f3804068e090781f2e83be255adff47fbe906e900285ce1b35f85f889090a	1623959587000000	1624564387000000	1687636387000000	1782244387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	41
\\x6b641a63004c7108f5f279b19ed378dff07da3d3ea76943c5cde33e09830ea16bc6bae407493c91d6d4e33541af5abd4242f94721a74b58131d378a8cc48aec6	\\x008000039f721bb5d51d539220047caaf01b55ed5b2cd515f0ab163336e06c42a6eab26e076b17017aafec49baaa32d221ccc0ab537c427d2fdc9e29d06c3ec4e0ec65550f3d76326e8cc849913b6d8d2299e24378ab5b7de717e013afb994ae715c331c6a7d8d728fce33ef3077f3664cc81c7fdede7e6c798ad97a3ba6c143f634ed13010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x915e6493f4139873da5738a5f965e4845d7141327b3795a514a4dbd270169ed976bf4717450a7e26eb9e634c1bd4a27f03e56603bc57fac684b3897ed769100e	1633631587000000	1634236387000000	1697308387000000	1791916387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	42
\\x6b6c366c982746a61613b34b11bee7176c998846dcc8e810d7ae2f882056ca894c3f72c9d867bda1372f4a76a7557913add75ffd4e8492369edf6fa6198be939	\\x00800003c3c107c1525747ba549240970be4c8e72d4ba047d98c2512b95b0c3518857dd70399cc0438ff2a35c2e56e840e7d82864326f89601971197a0e978c0e42ff7ef7b76b7c9cff6c09a84b44cb0663855b7b5da73c085ed61ff5bc142680bd895a3f854fdb62967984a309ffba61de54eda25222692cdd74d7cc3e36ef93b8d95dd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xad01a7004e89173317e8308a28ada2325d7ada154e5348de32737e7d96d39f0a5b71a747e98f21210eb2fe7909f893411d621ea22a45d82253b34e6a8184610d	1614892087000000	1615496887000000	1678568887000000	1773176887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	43
\\x6c78460d910f2398cc86ad0c33a5a39435f39c1405c1b909a5a915eef9b08219c2118315aa83f720cf61812f82d7e0fd271898f0e3db855b5aaaa21f379a3da6	\\x00800003c1f65cac8cc527cddc4a0a727ba0b7491f3bc76b91f8decfcece1884c5ebb19a55aba1707f8d86ab96d6f7ad1b83512d962fef2b89ae4b839230cb7042865469e0ecf6124ddcc2f18735dc9ce536d4f5e2bc934801c287a17dda39b39245461f7943154209514a59c1ea25fbd551d4e5438865347cffa2b402b67bdff2a4378f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3749b88269165f63558bcec594ba002068777f20ca18468af6d0eee512d285b1d6f2469e579ac990d87bb2c9163b3322536090e03824dc971c2f7c7d91df1f0b	1612474087000000	1613078887000000	1676150887000000	1770758887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	44
\\x6df497e0f8e6e60125628435972e5a81109756121e809beabdc015a3994d4c3864c89a37c20d43cdcae1a0f8db23121720a465068c41093472cb5193f8c10838	\\x00800003b8478213d5876e42225ba96f8db9ccd87867367d3bf0d581a43fc2ef254e08dffdc03e120c21d6dbaeb7caca35948783f6287dd64ea962cba6e673868ecd116404cfcdb7ecf0fd1913e58e5756b370dabc98ee422e0cd945a84de87901cc45fe35610ed47beabe45145383dacf3c30a13e1c1afebdbc562e808a80f0753915e1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x06dcd9780089c86936058ecf5a9d8beee53dab57ebb54db500fb8b0517b1eda7a313320999a1ee2f186a69d2f70bfb066afb42d9da85ef6e83dbcd0d53c33f08	1634840587000000	1635445387000000	1698517387000000	1793125387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	45
\\x70444869f5745da10e0ca5108ae2dd36ee19fc8253c4d264c012a564baba6deb64bcc3632ae38fdd855730f6b2274c99573f96bd3d4f569849da0186b42f9128	\\x00800003cf52e817624f1ccb020b829946b93ba9c52a745d28775ee3ac49f5bb750fbc4a319561a02b021dc671dea41066a70cc9e12cb7d80f1c6f906ae3e7ababf2e48e8b3068cf64b31a10906841e0474c976ee1381fec13a0ca45ae4545bc33a8b54898fd82b1178596d15b2bba1386466f55dfd15d5bc576393c051eddc0da5345af010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xaf02d88f63a8c42532bb05c1c24526edf3167a74a251c78c649ac5c9ed7f96576fd5c9d45c16e00da761d36f2614e3f78bd63dcd4621be64ad0cdf380a5c260a	1626982087000000	1627586887000000	1690658887000000	1785266887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	46
\\x72e892a8c6bbbc25c2b8699b49827ab4c3d6f854b41e2fe416cbc33b0ad7aff7b71cdb6743404cfea18eeface89207a50aec931462ce34c83bd31b100784bfbd	\\x00800003cc615ac209d2de40796f885b895044a5d8c55b86c0cc71391672b67ca869f67bacf79ab869a31be01056d6f23ec77902d56b863dd56b74b40876d2d28e128f1fe47527fb9ecf8c5685259a4be585af9fb7b3f109a836250c74e82a4781cc78d463959ef625a105b054976f96b4a0184103fcba3a28fc6a95ee254adc21a8cf3d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd1928709426454a233bf50af57e4b354ac625666e164d3998e2d814d77efe4b8667dba4347546b08f4a5606d8c009d522954beb061fd1caf9032a168d51a1206	1613683087000000	1614287887000000	1677359887000000	1771967887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	47
\\x7298b4fbb3d470df2a818ff45c4cb9ef5ed7b3c3a44890a9a3af78939d3d467a04a3123488d5dba3707b34186c207bcd231cf7bb110bc01bd1996ae13eb7a1cf	\\x00800003e223dea93b316cd10c2d1622f0fe5237796c872030b19b8e0e249f6f18345691699796b77021a6fa64bb62521229983404f8d31f500c3deaf4ad1f89068b9a2fb41601b311fd9739c13722abbae1088c60366914f153c9b7409e88541eff66fb167ef92d697cddbf86ff31efb9b9ec01e642574a8b63d2dba7c0f9cc1d5cdb07010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x29a25355da138a3ab532f30c9fdef9f3ec2cd73115b1fddce0257b5c42936205608984396e293f594681c734ec0f116390addba7eb2519d2464dc2ecf5491c0d	1631213587000000	1631818387000000	1694890387000000	1789498387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	48
\\x74e09dda1920b394d8cda25476c542a46d362740225fcd990b0a8c5aeb31c3045d41251e5cc3d02cb7ade6aa6808dce37ab0fe06e8445114450c9bdf736ea42b	\\x00800003b5e634811f20c2ac83bc546a937a8645c876d0320479d8a3a18afc50a14401ee0acfdfd8663b9473a8869c38daee3c8159d7e85ce178ec4bfd13fb60b67a48ee187d11a5022c918c481700f127b1d37a7a33b5db3b4798aae336a2a7ff3c4c7eae943418dc83655d8ce704c62231c17d20f471d5f0f477c9ffabcdc18e216a8f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6531446f4d0e07d16665b889991e552e5f9c2ab52b8910a8e28f37a239ebbb159edde31ef1e30613464b5ba77a70dad70d398565c2127020f7f586d7b1a26a07	1639676587000000	1640281387000000	1703353387000000	1797961387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	49
\\x7fa81deab3a668c424ce7ed12f1a24538f0bc2c12c1c2160b0aa0b3b492e9750d4e73296b21039c4d2ff015e43ccb26ae61ad5551dd8d96e51c52775d702e4d0	\\x00800003babbc19332cfd9998eaabcd399e1464e90752669b487f699fe67c2f1fccd395b59b89065ac0100bf2f267d12a25112b285d5914f44262acc8665863981f5a29becc8da6dde20110e708c5766859db896204a8c009cef9a5f5af3658484aef549e028827a7533a5f5a3a14247e3010e7e7c97a3d319eb4c683529787b35d49587010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6680dcec1c479af0f738fd37756a92c9f4281478359b8421701f615ba2b630adf3c1ac9f111629a896aa199a41a49613c98192b393e34e402790e103b5b83b03	1617310087000000	1617914887000000	1680986887000000	1775594887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	50
\\x815c4576ede8f9768ce893db80a627511899cefbf7df5600eca95abfa98e715e41d04b8f972500300125eb778aa5b38fa535e01a18d072de0c742756c5ceabca	\\x00800003b7ea530f1bede1847b60553c8576832789c84ef3686a9a5fd603239ff86d920f710f30a211d984989be7004ef03ce3ec39997690294e71b400b5274fb5787370346e68697ce6de20fa941946164ea5ef23077e82645c9f12cedfdc23579ce43fdb0606e41f140d7894fe521da21d7214639f0f050d3fbb3fddc28e58e2ec725f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x30b6d34d143bbd0371690c71fb35624e7705cbfb400f84d96de3fc8a3ebf93f20db17e4be0b471c487a6a6e3a8733e8da3f266f1580d652ad353b340dc272f06	1621541587000000	1622146387000000	1685218387000000	1779826387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	51
\\x83748ac23308cf9c07aed798e4d400f9b1a571a5b2a3b5b0d185bad482c71f06c99088173698210694f75ba629d45e610e7270cc442820b5bab9ff154c8b8e70	\\x00800003a233cec6ae3cdd4a9512d29ec1f6b64672ac328c41a4d46e7440e7fe2b9a1465489dbf1f9555cbaf030e38e3c8c2b9573f94fcb4f238ce335c22fcae286b85b35727215b2220d2514d82aac11d809aba6726371676de00a3b42ae17fda00ec5d53523229e5a9aacf5e2d7461c1fe48696af59247494c8e840f100c603a14ec83010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5e7b0ef960132c76bc90c16bb5b23bd3af43bd8083c1e56a34d99c48f541d11ffd92c1e327931a0734b65ae73f9b4e789b959fef0ce72e81684a689986663800	1620937087000000	1621541887000000	1684613887000000	1779221887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	52
\\x86ec8d425da387a52a1613685c454500ee274abd2c01b00ba4002dd0ee0dca4fc9a62cb1374db04c614f509a39701fdb2f0c4b9d8eb1fc9c26503bd48ea4c904	\\x00800003b4fdc8d6ef721f2c04fe645e332cc160f9cf6f0c399e3a70c73c321bfa348c10d101e13fea3fc6b4090763aa9995497d6aeb6fc423f735ed233cb668001c39edbd1eac7d7431b9982551624385193dd919b2fe432c8f8b7c11a82d27273f297d3426d1fb8d4400610f259f4ceabd251cfb6c89cf7a598ecc928ef87f49447dff010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf6bb061468b20acf5654776636a64f2d016603f25f5b8c1c8634bf4585f6ef5d646b7f1be388758c6947e7670b8c7ca44f3f816cf32a21418ee8b1c0bb0e580e	1625773087000000	1626377887000000	1689449887000000	1784057887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	53
\\x8730225baa775894748a986d2f17e9204773a5ce7c3739f9fce2d9eaef0c0c9bc12362f97c6d35f6c5060c4e5114c6c8e506317af528b072d229d9a76535a5d9	\\x00800003b46ed96ee01800e7a71c4dd44a71f90ebbc8243ece76cbec600db3320142fa0d9377cb4bb38d066c6f5ae0927ddbe6147ec88991f4f977e8fd0453a27df431bba62ef7d29d7315f6c6197c23b91a4786cdf8c0b47acc07cd8d5d6952245daf995f986c1874a29a0a28433bb641e982c324500d616fe73c49f4a2bea1e5ce2fc3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe7084ff17986ce2106e891418140757690efe965fe8317339254f4ee70a1e2983cc6f1a53f6abfd38a494c1bae9cb08abaecbf59de5bb9f855cba6fcb3e9bd09	1614892087000000	1615496887000000	1678568887000000	1773176887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	54
\\x8a4873b97c3a64d132cf490ea0541aa2719320e690cad74522b65a0e43f0cc5893b983b0c56290c447ffedcd6742a00224964b1ea505d2a54fa9379151dd884e	\\x00800003ad83d6ad08b3f46f433ec142633fd6b0357da1837e1666cc75162e6f728898da4026beb4a37b63f1fdf233b72a4dd2c63dcdead0dc16d1f92c90434bb4f4ad5323c909ae890c99e1d04eee0276c1a821bd106f936cca76615b9cd2589ed46e9148cfcc912e446c9f5dec2c780af0806b8cfcf7fb1efab2cc60cee9368ac69e03010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xba7bdce0c50bcee6c85b7904fe6d8eff0c867c9373521ace897a8ed47d738d00cab36908ccb23462d97c3839f88c227d83756c16bf199c71d92ada12841e120d	1610056087000000	1610660887000000	1673732887000000	1768340887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	55
\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x00800003b54d23c48e561c1427927b91caec30ba44132601b710e0727f3a9ed5000b0cdb0f72d518661c14563b96e6cb0671b6dd18ebdfced5c813ab5a852e0d01e18a738d1fc3e2f00dd00dacebb7d899fa780bd73138a6b40fc337f474354bf0f5d8e95e0e6a2b0499dfaf037145af91dd9752a4d531a44b63eca13da85bb089f68b2b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc9c0e4d551c424e534fa3bd623eac77cb99fde2ffa8642f1ab25d1264ca3edcbf52716fc63f3bf04b04f96feeea242f2f4f963ba8200f56aa3938d3acd96ac0e	1610056087000000	1610660887000000	1673732887000000	1768340887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	56
\\x8fbccf38b13311d1a4aeb9ab636b252b380a31c17e0801ef6a6e9e60f3a6f2d5bd034e6f636184c37463549342414b4bac8c840a72082a7a59620a790cb2e260	\\x00800003c12bf1e7701c226c38ffc54289e19a5cebc77663eb9593d4a9a2fd2299446a54b24c6e22795d2196eeff3d3432bbad6427fa286c81f8af2e3eff0ad5c736a3ca092f69735c547017dcc756efcf6daf185d9c0c5a8e9e426b515a8adc78901e05fbf6fd1b730d6ab4216550447ccfea0c918447b04b4e592f1fc09fa4ee56cc23010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb205afe29bbb03564262b6f8301c870ecaf7ded1dadbe7c5fa0173e61eedacfc57f336378e6bedee4819ff7f29e6790ccf4509e53c7d1bace1adff0e5d66f70a	1614287587000000	1614892387000000	1677964387000000	1772572387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	57
\\x9244f9b6d91bbf3e0204d1e26153a3e65cd643e81b9c4f3d11133950b6bae7cb7d3f34522c83d64778d5fb19a5fed2104ac188e6a966484f1ff4dd39f4d42bd3	\\x00800003b0db6c6cc6e1adc1b246aa4ef060587f07c20bd1790f990009b7032bfc0c4277faaf407b71910569cdd8ee0cb7c3e337281f4c077fd3f04d382da23e3d34a88ae0adefd4a0ed9783c9a5521a8b9b1c86a42165c35289af82369f8a502eb5bae0b8f0083a35e1376915a608d2570c18560450bbbe8fca35ee638337e601b22ce5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x61e6b3c41a6dfa092568b059a122679b8937722cdc5de11c9bba88f02b013185f5c266846a851ece80f3a080c32eabff212627090c5040aca0905b8c4c349f0b	1632422587000000	1633027387000000	1696099387000000	1790707387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	58
\\x94a88046674b1290f81616eb1d677dca47a1543ef9e5c780cedcd91f75701780f24812bd41a3f435e357deffb6242e3f1071d9ba9ad92ae0ff7e43f43456cab7	\\x00800003bf06b25a2edd9a550ef370e8fc13a74ebad7f9185fcea517911aaf8219ae31040f9d7b6c7b894dcc0c20ad3d7b1000762c929f2c55cb676b7e7de093065ad8e7e8cbe89cc76984bda8e4afeed27c14a620a975afc7b809a44b259608de9044f5f57a4dec72fa84d340b1ca172afa52e5ecd97d97c317802976a6d8da2b6a3c37010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8fa903c8bbe31b684f3c8030b956c1386266b16c2a6f8af3fa0571296d52793d4ca3f66052f94488e128d094085ade896cef36edb3f576b733ee3ed8df40350e	1634840587000000	1635445387000000	1698517387000000	1793125387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	59
\\x9464dd7da4d538cd2a53effa72bfa8c73d1e6409fb6549961f96a669ef680b6276375a5938b8ceaa2d24beebdce5fa9b7408257343bbbf3db8945885a0e3247d	\\x00800003b6fd70ebd97ebbbb116a5742f43ea1c8ddbc46454af85ec93e7206c8300ba7a0f44e385de4d1cd9c6fcebc9b3fafbc05b873ffe50a826e211c8ba8ebf97d3573ed6f2b0ad34a33e6327393509380f15f0ebdbb6cf72b19274c22802f31322c1e56c39860a7e50ca2ae60eacb5c077bdc271839603bb7deb3c2035e052679e5fd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7324718c2908cdb89dfd146f0df93ffa4ae521e475618368067dc0c81a906be284945df00a8af152e7942d5467c4dcbe9bd75f31dbc353d6205c6306ed91bc01	1622750587000000	1623355387000000	1686427387000000	1781035387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	60
\\x9790a76eeb30f5af98152124f2780593ca929ebee27536a3ec276cba9d8ac294fc0e8abfe56b2e0f0936341cc6527a82b32f9563c96e010d819b37acbfe892b0	\\x00800003c241575ae04a57c5b4ec1dcc41f34fe36cbec4c70016b9d24f0dda31ee9e054d2a296d4e7632e83e256a59b01c39eca19009c2787d8396f339230a43da31d80589749baa8fe50ca4c7c418512aeb9708c7f8f6d8f72dfb4272617ccc06bc40965cfb6896778884795e63adf669e294a077db4d6dbbbb5289012ff01a46cb7627010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x19667206c7daaa994cd076b906520eecb6eed2917697ac2da70a47d51a4e99ac7c89728134e0279d460f0e1bd35810ac9db49aa572168350c84430204273b100	1626982087000000	1627586887000000	1690658887000000	1785266887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	61
\\x998c336c799aef125b01776b6432c8af929fdb9e00ec749b9303c8c8ad72b065701e730b6041dc97a8875ecce29c37b3b4201e870623263fe59cc652c42a8d22	\\x00800003cc7c5d015765994c66a6d139de36e519140866c3aa4929d4d5a89ddac18acaa89d872d52dcb642f3e3d5013ec2b14be73fd268c81254d22a9b573626d8c072c955d89c53709df7bd9e137af137521c01c7eab2e4777799c0ea20ac075f79e15c571c4415b091c8357852c3cd6dbb62cf22f0bb668580f1eb2e6445450ab66bed010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x06e431910a6e3a93eb5732dd89aed014335774923425f5d7fb09d7778f2893bc2ecbaaee878ab82e6463a29d974facf3c4e0a08cd0740b88efbcbb8eb0a26a00	1626377587000000	1626982387000000	1690054387000000	1784662387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	62
\\x99345ccb34432cb81610f1a31bb26fd593a6122d066e35d822ea30fb0063659171f7611189cdd8934e79b5c76947c88900351e535e9025c390eb71d9d488513c	\\x00800003bbe8593f3b06d5c6389ba35deaeb3341bf31a8efce650c5a9115e37c63f20f1b86857b49666073530c0f0afcc9cfb98314bf8a3ce1847fb298d8283e9c68dcbade5c4e3083eee6939a4ff0ef8230f97c4f51b2937559c40c48da20e93dd51ffcb3d282ddf8b81b88a5a104cf2e53e90481efbbcea606fab272ceb9f399e0ecf3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x735e150aa85c9fe025a753106e910033b3f1ee7a4daaa7209c7dffc171508e83faaa4ae5c9c4d841a97ea71d2877277cc4b4d28eb001a13c35d5fc58979a420f	1625168587000000	1625773387000000	1688845387000000	1783453387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	63
\\x9ba0f8dd13d445920b568be044093daf9d05dbeed67c470f9c7a834180f639a599d92f8d0d35ef148a237f40f84b0473182ad04786161c140ae41f75141f5a27	\\x00800003b2d7037e803ec95488255ecaca884037497754570a6d91060defc1a13393ca82194dcb23f82f9ef753348c0f0967543c9db1e1d09ecbf3359ab33cc4cda18aa62c92fbe718f8e41f970c149b049f5b606af81a2d74cf880d4b09b03c838b5e4565d6f578271c6e4b969ff6c9dd3d987d9c649e31a51fe89965e44101cd1bb407010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4593e3be1e5b390942d4c3a6f1372625e5b1508feebea59e4691e8edbfee4eaf8c55054f435df91cb8ac369e06257214fd451c20094936bf860eb65d5cba8101	1620937087000000	1621541887000000	1684613887000000	1779221887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	64
\\x9b1093d795fd6992cf5c20f24e9c1572b5a72cd177b773f83dab208e514873694a445a9e848810400c68656620657ea26bbaa60d9f1c89531a3dc6453b7bacaa	\\x00800003cbd0990798a015ba127a119679291b255daf152fe5f8cd0f572c5f53db3cf1fa6c2328e664ee7c1e5a29aa1fd112592d0f4f9bfc60f2666236990780d4a3edc79e4d85d976e12cea647ad56fb2ef9852624c95d94712317cffe761357e3b644bc715db528d1afc8d7860963d3793b3e964c3649f4485a5695c8047fae993f0e9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x828e4f697d08959f7bda7747f486159783a0e90f970620863cd62e878a599a802051b88e9dd304c685dfccb93d0bb008c73b07ba67589b0436946af71600ca01	1639676587000000	1640281387000000	1703353387000000	1797961387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	65
\\x9c94c643c3c7654cbc2d18dd6f954f5275fd4a1e86d821e565cafab0d8a0fa6f8a98558e711d6a8d15557529b4a5d355e78138f7d4bec8ad5875879c44a163b7	\\x00800003b20bc21f38a9e6d012d372f1f39ba32382340f56730f45826c56b1cc5ee5bc484623107796b6a99264e9091cb4b4b1c307d6824325f1ccb55ec53a772e64802c31593be4056bb3ee0444797a65e174b7a6b9c24e31a3b823f39489d947be985747a265eb0925247ea817e2f769d6a2f0a4fc6782ec27935f6e503446970327b3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0e4be7ed77da0a80cb524abd9a8c9862cba1e47127110d8dff35ec49b6f6bfdaa4a083ecdfec6786b0ef654ba2a0686ee2ba22bf3a9b1c54429d5249391db003	1639072087000000	1639676887000000	1702748887000000	1797356887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	66
\\x9c44b67d90268bd3466e00bfc42d478ac2ee48e7bfdbc1a714d9fa744fb26d555174aabdfa1f41768d373c014d0ab8e4dcd346c4e12159de088f118fed22fe15	\\x00800003b88d4d6f004cd6a93fae078cee9b970c4ec88a42f65ad32169a1ec6de0b34214b3ddd3821f4ac539c4d8c7c08f3a001849ab1c466a962543a1bd2e56ec83cd7fc1aa2a0082e4e259921de21fcdd713750d4d224455a5c04418b35a5e41668eff4bb2db71230b5291dca62a74814ded36e037b5b69031db5bdb85ff65d8b52b47010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc39d30b171cf2bccfc0e110f2328ac38e012e72a4b668fd667af978481c5a3edc4b2fbb51c916c4b9f91203c744cce5d7174b947f96228855fa6471167847404	1620332587000000	1620937387000000	1684009387000000	1778617387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	67
\\x9ddc493ac7d5fa655574982d2786279d3e2bbee41655bd3302cd06c75c0d3e471b9c60584baa430b96d72504bfe42032740a0b674c741852ddb36e67a0ba205f	\\x00800003a7cbaa9b208a9881f06d8474d2f7864c2757dc4b4585edb90fdfd413c99f8154597bfd35a2dcff4486aba094b1a28ec7d89941f5fb64b6f09f7777c299e72327b5a68e6961867fe628f2cd5770b726b5c645e0e20e4a19f1bb27071f9465bfb4aea43a9bb4d0eb359332da0b87908905ff20e207babb4cdcad7cb063fbba509d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe599e0fbf71a6641ed9fbda5bf5ae560370a7befe6ee6927dc19e8d735088fbe32f4c7c192054dc856057f3e96aea2d396ffaf5d34075f57b009fbda729fb50a	1613078587000000	1613683387000000	1676755387000000	1771363387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\xa4dcbecb1ae0bda234e8fdd3b5732c0a7ca32f89432bd5d5a4c83b0ef8e04f65feb37b12961ac9dc771d5b430db68fef7ab1afc63a2b1bbc2442787f02c6d2d8	\\x00800003daff791dbee5d0de687d4d0aeeff57326a73e6c804fccebcac61c01e15d0896b9a9e62021f4d4418f55dbd443c6617f8f805da740b1b3464babfe7b990f5375cb50cbc9093dca787f9aff520fe4c5444abd6cf6ef272bd3ed34664ea775d7e4c024f0245050c86f926e26552c1f1c0bcd4067e020004c1448acc4c25f2774f2d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd7f87038793df565dcbb4ab57ce84cbba5bfa7254975890099e22f7e251ff5262c87a3f33cf67fb69ec99c237957d2ca4695bace062e3a42e6bc057efa058c03	1616101087000000	1616705887000000	1679777887000000	1774385887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	69
\\xa6244370268555b11f67a55a1a598c2a1bec9cc2d40d95695b4873a5864852f93c033e164dfe24c80217b44e38061066122450134a6687561a29f2f4b03f866a	\\x00800003c53bfb4b0f294ae6430610bee0339592a490763ca870e0722858604b7dea0d8e0445742c7d02fcea2c30b63a6cec39a9e824519bca55afd1549c271cc3aadd6bdc5636365829370a74c2741c679eba9c8dc51be96b2eeb6bb90bc9a07846955c25251763a069aca70aa82200ea4bdccd6ee7610f7abdf70fde6cb92d1bc44731010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf37fcf705e1f63a332cadef44b4e495157f0f0a670f5ad1307f59b78a58cacc11f819b3e3b4d599bd6d41f9d18efbcb7dfe9b6fccefb88f81ed3ad92324c260d	1624564087000000	1625168887000000	1688240887000000	1782848887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	70
\\xa8b867cb6c44aa4423e9c3609ba66a3c674e9829d950757e10f0986d00cebc002c5a303f736f2f5b693185121e09b15cb853f4a0b556329a9c0db5200d939a1c	\\x00800003e3e13e01fa28ead580dea81806653389c1d00ed61dcb76f8848a88df886dd5f7a1831efc6196b5b29ef3f26fe1ed6b34aec0356ef3945614fe53e79e14506f1a1fba4af78dd9645765ea4a5e50546d047b6bf68335871dc1405516b1b9f9177912d3559bebecb006c759d35d588890103ad59dfe46cb8016f6452879245849eb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x45202029529cd9fb69e21b7d2109b89d095de823a262449b28609fbfbc175b551d68f912173279c9ed525ac22a246fba380ea75053bb65cfd1f811412b07550c	1611265087000000	1611869887000000	1674941887000000	1769549887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	71
\\xacf4198fd178dc80de76e2bc7d2c8d89e6d3df28e50c2eccf58b2749c96989d79347f44de8f9dc07f8770bf008f39743619dfd9241a61b6d541e06fb32f3f944	\\x008000039e565894ac6f01b2c29189c0210c68e40df754048460859b9627988f34930369b85552b241b5b3fa7aadcba0f4e00bdee9d52c1d4e9d9fc85641dafc43af56f02ed430ac2dbca539d5eb62c2a1f23ab40a47c9d608872abcb102046f20e107207532aef4ccd573c2cc00f3285fe77b66abf3aa5e87887ea905da28b0c1bf1707010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xba419c5880ee42e4c2d35b780e9cd0773009eaa57a92ee14c406da8a1313973c579d73ca4e3839eafeaca80340267cda04e3006eafa3faac7bee09c84f675d0f	1628795587000000	1629400387000000	1692472387000000	1787080387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	72
\\xacecad800149b1b78a60a5ddae2947cf26e4d1a0c26e8fb28614799a034a6745d198a39f51266e967e9a5ed5dce504d6d613dc5bec36ac5514722b691a9725cc	\\x00800003d8d56aefa5c096bdfcabccf98fa098357d21d204e207085ec6d09ba2131a4a005873a9246c2e55b04486c6292f60649b34b9b8195c3fe0030cf73d8ec6e35f64b1ae7cf87acad374e1a4ac76d7d96f076d9e2e8dbd69313eb6d9ff4d25ab8e4cdd641bc49d0d45fd3ec9d6fb9621340fa3c3fe055c109db1572acdbd4672f977010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xefeef0817af3f3f3c5820372612c964bad032e4fdca4589baf947c936a78e67ba08aedbc29af20e3839f73f701449f6eacf9b829ea953fde5fcdfef03367a203	1615496587000000	1616101387000000	1679173387000000	1773781387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	73
\\xaddcde70297363d4b436a620ef1fc1bb023a7b034e073692a3b62b101158091632a5205dafaa0b7a311ee3c0eb1adf569efccc9910a9ad32a5b9e7a7d24c2e15	\\x00800003b9793ad6e38d21d9b6acd73bd0c5a4af211315b9ca5663dcb35e069d8f03cceae4212dbd79005dbf38557d0692ab3f20fc8d4f3b5c6b8af3957dbd68defedc151d33640bae8b0a73c93af9db0b2358e7b0791b85490024844755a429a590026413748df45d61b5956b1e993268f0ab937111d6b754292afbe4f9d0f4ccb0092d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe521c26b15ecd663bcbfe3d679fc77693106e97713b54594e4f4037180658a45e5f430a587ecd20af815c3ba37a550802e8a5daff2b68c21aa4249511af6b709	1626982087000000	1627586887000000	1690658887000000	1785266887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	74
\\xae64d7954224805a3be820f74f2ed5ce236985f39d7aeb5a377ce6ff70017ba88d833231c8af22785b4e9dbb82bde240f4f0def88abbba019af12a60a79bf770	\\x00800003b3d0a0208d32d97ce8d95726d0b55450c15bf6f99bb2cf3d9ff9ced895dfde91a3ad149c0c57cd096ae253bceae8a8e61278702da7e224552d4e4966f883b82f411ee755034835e1f8273cd29a8ed2be9f35e4683fe128069139f0047b3ead73629dba2949a835505b333347661996aab0e319a764c2b4a9eb0328706406b0d7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4815d7d0e262813f59bd186d3d522c1de692fe142a2564e040c59fa5ac5f58b6e89e6b52c352ca132323a966f4a6b877b1b30236350f511c30508c4440218105	1610660587000000	1611265387000000	1674337387000000	1768945387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xb2bcc4dca189973dfaeb1fd8e11f8dd3dc7907b38224a42064687b0c6e8fa9620e76d556476a6bb09faf88d018ec18df337863587d10516c121e47cf8a9ed617	\\x00800003d56db61d3a1ad5c351b2c0a3e89b4ea63f01fa465c3f3a23d4ffc79f6ed7ae77c1cbeeec2308262c8e0f75cda9ba8a013c264068ed58f260a01e63b3fc51dbd073b61b810e3a9cf0625195f180efa040ec6600de82273633ae22171eddfcc6fb9250c0d0478b72b259a3d08845f58e37d54934feaa141f7b815d24927e370325010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc139e03b2ca3d74275092df16edc7267cfd1fb40ed1bc99ead0e4f3378551acfb0374ca71f9a402366177b11b7113dbe7ed7e35991b8454c4bf96cc495359a0a	1634840587000000	1635445387000000	1698517387000000	1793125387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	76
\\xb230dc27ef3cde945ce6e2bd6719d97dde02076e6c99cb4ee2fea40f95d8e15cbe73272fe1798dbae679ad4983001fe36be9bb9ddc691129eb90c7c49578f3f0	\\x00800003ab988dcc21747739008d14970bc858e0482c0f28f9bb2d1e07b58f0a876052509d553199114635e024476b775ce931478e6cd992c934614d469b47bd6ecabe44740ba1d0acd2916e31a645ecd84213dca79df4dd1f9f77e8319db926c3f65920b83e845fb17461792df0b14217f73666246f476ed391e09e604b490dc48eaba3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9f71e900bc19fabfafecce260746801ca5eb5db8af7faa4dcb549118c40f50695a07a14d729ac1036974dd985bebe8f218130bde790ce7a8bfc8f32263b13f01	1625168587000000	1625773387000000	1688845387000000	1783453387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	77
\\xb3241bd14c1f46c563a612f7c12fe1521fd3cd2a53918b2feffea73f42208cab2c001e0bc1a538b7972880e612a4dc19ffa0768e9cf476ee8301fcb0e5238ee2	\\x00800003fa70c30d628cdc3d429c037065865684a875874718ec6c107e89a333c2523885c4a9b0e8c5c4fd9ebef92f1e5da762fcc6ed333c739109daacbc3f70e6504effc68eaf39e89e3c263323e7c8ff64f4ec8d36af0180a48b4489a4e871d98712782cc6ac5556f6bc80dbdf842fc4a509cbda083c7957b4181d5d53bddf12233281010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x52612cda12299dfb503a2eb0f1a85d6b80a7460b2acf3aa183b8b03e95511068efd9872dfa07632c9f569ccc57cb52156db7c3bf6d1090fc9daefa8cad409b04	1622146087000000	1622750887000000	1685822887000000	1780430887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	78
\\xb320c1325196910de2ab075ffdc4c6946dec875ba0c56845754f381a5112eaea7d00f79588a102ef938a5081cc0149c46b7d33ed3b2a6e6d57cca95c1a7bd795	\\x00800003b7a4751ce696255445f554bd4bae62c86811d957ebb09ac894832e25b0e479745824cffdcd0e58c7b38cd568e31c4036bde55cdbdab7be1a8e0deaedc506800c843a700e422160e81eb9b4d7f14ce3bfeeae5719c6f0830ac20ef4f160636f315ec09520834809c6e56f2a73f3cafe538fe19de193aa19b37cc135fee9441fbb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x00c5b41dab9f8ebf80b6b9767b55a306e1ee99d3d22ca29efc12a627d6e30db88b67b683a493b5564e44bd15c6c1c25308f5511b45bf254752f95c644b340600	1611869587000000	1612474387000000	1675546387000000	1770154387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	79
\\xb4c4edb12e3f2b0c9195d5447a644aa3c944e0b0154da7fa55d97ae94993789273b5b169eb4ac18fb3233cc79562c7c24187e88bdd8f7d71121db1f5bd6163d7	\\x00800003ea9175ac50e43a2a8d4ba59ded3d266edcb5f1ec039482d7ae45db4fd38305d6863d0168ee261b77fcdb3483d197bb2365b807d2377ca3121cc659baaf0c26038ba14375e2cb944b146761efd53f1ef5c111612c8899890f54799a4aa2ffe075bd9c5e7e94772936f64a71a79a5037444ecc6c1d125fbb3b3831a05a14ca8f35010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3932cda6166c16bf6211d61bcbc3c54784be6ee53ef05c80fc05024d5fbe9e53a8a18371e862a8e6b3e1b4e5b899df8edff4b8ce9c29b6558d37bf75dbf34b08	1610660587000000	1611265387000000	1674337387000000	1768945387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	80
\\xb504ee900ae51fb6a8c0e3b2d8629dccf028abf1ba99bcaceba03347b13d48ce1175e3ce71245c1a9b5fd5362c15f3202d5437e84c789ea71fb260b4a6e66eba	\\x00800003cf23a88c093248e22efa6da63d3db2df6c2c0cbc60bc8eefbc91bef87caedfa5458c725cd38f5ae50d0ceed6c920df028d46f67f8063d934bd697b75df9ddc06410a1deb9f90f4b40260eaa3d7c167f3caf3c970ce47163f7889bc0847ffd8a6899080e8a6c9fdadb842846adf4996649525160352bece30999a2f55f962ba8d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8cceebac44b98d1c01eeba1876765311dc41b97acb4acf5121e53ae8157b0bb177386c6c01e755e9046b58b2486eb7028516c3e4dc3bea0fb8e01f900b6d7901	1611265087000000	1611869887000000	1674941887000000	1769549887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	81
\\xb540fb2f14e0a5db9645cc655d70cc72bbb445578ec93a25e9b2fd03050497b8997ce4ec5e429e631ead8b7dff00d6eba10e9a25a06eaf8d4e1c5b8dea302c57	\\x00800003cd1c8370b2d505b2d43acbf4e63af9cea83f67e5670fcba8e2de2f5c27c6a69c0822220e19df33d652a9cdc792ecbf2c0321a01457661cc1a8439d7eb7db152c295858990d70050f7f9c215fb2ee13803ee96754c8d476b9ad10218f80960e513b7da1dae08e7a0b180ebe6d4b61591d623f71d117846486b4e18bbc48fffc15010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x460f677226cbccb4f8f927c3b17172fff6156e4788fedb8519ba3a07061c674f4af4dda07a7f49f04a93400b33eda27153792de7f0d4df2ece2d5dbe1636f909	1612474087000000	1613078887000000	1676150887000000	1770758887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	82
\\xb6789b5548aa6f9417fbadaa925c7f6477a8a122206078b75269002f4c1b4b0e05c39298f4e34fda5054d0698b569d8720d02e563096505162bf1abdaae8ea13	\\x00800003bdabfddefcae078ba0e91f707466dc4bbe71828cbe7336b40db586fae8fee0e24429cee909e4586b6d5d7f6cc5f7b18836ba2f13e3a5eeeb59393850b7e5826da98e9b741f687eda0f7cd264f73e5d47a866f1a504d8a5a72c86f48bdf9f8e72e3c08f111f4eddde9e884504abb346798659c8e3e3dbba567a9e24ff53577ac7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1988397c62e49b2372b9188c30f7c28d75b29b2177b5d4ffbc1b203a18f6fc294d7038165086a58499746a2017443ad2bda5e02c84fb499ad2ff9d0d630b7204	1636049587000000	1636654387000000	1699726387000000	1794334387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	83
\\xbce48efe98d30a7bed05dd5d97a629c4c9485917944f2a04a5aa34ea86b0a771fab76f4b688a1f0e9d0392fa4b612b062c20b55479afabe872b5f89ff16fc275	\\x00800003aa2600c1a4ebd4aaea283cc761b333057faf3fb20f0cdda8b096fff5075bb193a93727077e4962a38ab99cbff2ee094f6288fbaeacfa36ce1335c899bc755b0d70e7139219e24c383401f0994f3e9b02b041104a80b5b8da76e46b64f215da8fd851b8b5289f236ae203443c2e6339f198a949b7e20d5d504f79913530d0a141010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xca12fa25b5226324548949306baefc6ad4aa081cc31af13f8550c01dbd5486ea263bcbd8300026f13dd0c09c99c0f05ce764c99fdb53cbae703e8451ac848305	1634840587000000	1635445387000000	1698517387000000	1793125387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	84
\\xbd74a080b6e2aa36653ade8b4c04a0c84dee37ee8a83c8a8d1c5fd2624906e43d0781150dc2ee5ff6c98b2995ff14c2281f29c0a11b7d91a6744d0116807a037	\\x00800003a5a56f4efadd227a7085a34228de917c21db46696df48f92e2080a2b4bc95072b8a28a3b8bad076b4f276458b3f85fde684846b89a46bcf5e0c3320a1f918ffc0936c2f1fed10f016ea4bfcd8269d38eabbee1ce62be391da6332c1b775db828a659a4b1cc86eb74a4a75ee1cc421a539f4d24959cde39840ac28d51dd40a71f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5d3a6467456ad401f0ff66c8d49b6318cce9ba7710eb8168cee4ebb52794bbc46be788140e3e508dcaed48591384b3d3b287f41a6c924c2ae400c1a8586fbb0f	1625773087000000	1626377887000000	1689449887000000	1784057887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	85
\\xc08862dc54510385593fb01f55fcc7406550ad6373216f519d3d05372f826a5a2ec08231cc76e7c8fcf06aa7fe18dec7ccde4becf7d1f2edf954397a0a7d623b	\\x00800003b563350534058d127c560bd06e8aefe18e2c633f3e78d055e1712edbd54da174c670395f406caca32d6ca29ef5bf948299392ed8837cac3aea95b5a19a821e88e46ca1b6533fd27a37fb7965c5707a940ccd99fcb72fbdd3848e3b8607baa8886adbde851397d226ed8e5f34a29ec57756eff0a91d4c9d848ed52568a5d954b9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x505a1dc1e7d782f7fda8378f9070330ca408967b1a865026652e96ab36ff46a9b9726e38ba460f0e9d236ea67f5fe2eb678efbe7a28e54e5680c4a2efb189f07	1617914587000000	1618519387000000	1681591387000000	1776199387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xc23884124cfce2b77a4007d673ba76dc19d8b1997483086c67afac6d15883f5fe046b059e27eba063f357565dadd985a43f7dff2922c053395a1abaf16e372cb	\\x00800003ca93c6a183c889a9c71331dac79f1ac375a28f212a0f9dc4b8b328441b69c6f0427782055ef06ef15cfe21af73fef175a1d765e91cd3a9577a4a5998012f4f216eef2f6c2279df54e8569ebaf13fd1397748e6cc494a4a994ee4977e0a977b0193444d94b6b794fafdfd432a672ff857188d493597b4ad27715d2755c31ace3d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x585904c185f0c6a3c0195373772beeb6e985b8a533d48d98b10b3bdea6ce8bec1489a9c5513e8958972e192655c542f1bf90f4497fbf1aa210559e07ef473e0b	1612474087000000	1613078887000000	1676150887000000	1770758887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	87
\\xc3c8ecce35bcd91d2623b93f122809b2c39f45f54f8c59c1ccfcf5474abadd2aa4e67a58e7e244a12f52eb5257071ff3f6b3028d1e152d5ab86a3471d2d487f8	\\x00800003bb11a8b0184b77ac204a162c8b3af8c3768ee505f4cf452d9037f007a43e34a96b4e2ea961376530a1dd2fea94a54924f79eaf8b31a6e464109396781911ee6d26a6fb2968ad5c19517b08ff556c3b8f1ebc766abde6e1f599af686616f3ddafdc009eee237c2b9f285b68fdd89ee935d2f8de2be9e6b1fbdad25225d60dce73010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x63e7191be17f257d186a3cc0ab905d4e15f52273f936eb059211e7ab1ae6a6aa84134c9ea832f1166cd14e8a50f0c0f8d1b8cd1d643f4deb529d13ad2b06430a	1630004587000000	1630609387000000	1693681387000000	1788289387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	88
\\xc3401fe695c51032d91b1c08816b270ed13ade219bb96dbda2093936a2d64da7604e458235896263a142bac61a1de2ab0479f58788dd834dfd9e5fb29d6f10aa	\\x00800003e84692b6f50aa485a4d35b5491d1d5a1ebeeaaf514e05eeeb70b6d7fd4614c8d0a7da8b0bb35cc203b3eca530c825b445c9d7f96fc1a49018628ffe95ef84dc60f9365724d6b5785b6d10115bbde06caf97e2c89478108916aa2a6f3998828891919d5d2b7dd79357ecc13bfec4261c3d08c2998a87e7ce9a0c81cd954ff9d43010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf6234e288a4748d674bdef9c31824362106ab9155a843b00ae8074a61c2062205ac69b3ef06c91568c4b45767a3ca487a90d1a4ac08ccda9c1c844e4c359820b	1611265087000000	1611869887000000	1674941887000000	1769549887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	89
\\xc5b83a18222119baa6a515fb6ab5426c9fb621ba4842add939e84b7a4578854e37346f2223da5796d39fda8396e137fead24cb1b41f7090f5a77c3662a081198	\\x00800003e9a17085dae818f3414b8f10b00fb75f2c72753c3b2392df73ee6cd25eb5febb358d90ce398f911378206b5b2ec40110e7430af8b2a50efdca75719659b4a776fb9cfdd932dd119aa6d57b6cbd8a9e9232e373ecedfd8ce21d07e1ea54d20e144d993a475422bfde9c768bbf78c97419cd1e7c8735bf9b12c532900d9c6be34b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3ff5bf555eb36cf3bbfe95ddeabf79cc2b81415abd0ec1a77daf6ffc03896b0d2ce9b5e83ad875595c467707a97394048dac1fdea89e0b78da134bf894e05306	1625773087000000	1626377887000000	1689449887000000	1784057887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xcad8727c2aaf4264d030ae27d0183ef8aff215de16c10fe74f9633a3b766a1a595056134d70986f419bc3b7762526274ed1cade9e604cf025a16e2c961b19be0	\\x00800003e505ab505df69a37c57117fd5b5ef236d63a71c91b6a3a3e09f67cfed58d4760ebf7578c96c1a95456a9c897fb9f20336532bba091e3bea74dd6b78c653cc9f543df77551335a55665390e13f57fa94be9089ad95e5192e2fb9c17be6a0c8a441cebe2648f77313e7fe7be8da833e54689abfbe1cb10f15cfc35c5ee3b111b15010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa2db681d178a7350149d12fc7865bccf37234b4422505f28a5ed9ab2ee25dbb0aa7fc74844a6a8c6e7a0391a06971b3b5d84455b0a341b1c00d18ac78ca6ab0d	1635445087000000	1636049887000000	1699121887000000	1793729887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	91
\\xcb98c81d551bb6f9e65669354a96d4a87ff9ea2258daeb6219a95da48b16a025aa673dc24a2978c511bcd93d26dd8bdb81306bd1ead169c518c0995e347d33ba	\\x00800003eb01f71a81c691e8db293ac04af36ac922d12d3c4c2defaab30303ad784dbcaa5ac2194192725ca02b5e2de49a97042fc13b72be7206f6f009e45f505deaf5e101d03b1775849d5db336dee541492d7b18737d4781ebf6076a2ab33a22b14dee3dd16b6309412da7d8225be0efd4223b9e20593843e2f00b44ed12361028348f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6e3412b8c89008598c94994989ff4bff0d09f143bb6f4f6f4fb750ebf3fd8e481689b8e63cc3b0f20e52edb220a36668ff55f864fc9072b69c121571fa5a8301	1627586587000000	1628191387000000	1691263387000000	1785871387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xced06b5a40945c9f13cff3498726d20313b08a32699e366d29647b3a0c8fb3125818af0d8e7d8cab250e420b597f2c68a8243258596ce33c53746ac1c5061700	\\x00800003abe1d710e6dc4db9c3c86de64e3fc3e01ee17b2f67607d9905c26294f3053767a2484b925d8cf15425f999bab1b30bf9902d6d3baa9e21b7758ceece133e901c5a317c7ce34b7baf467c5ba0ccacd4828a2ac37ee743a6a961645fa3221a4996312c1d1cb5d4dbf03f97fa591da05b7b2775d1e5c12b1b83e7e33c4be6bc2d63010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcc5cb6e77a7aacdec8c87485f8b305d5f55a2c2ec38d97b130b1b67f7ba50ae434c26afe06a59effd52d85095c3a8f6eba7ab36651575230d03c0ceeee4a7a0d	1611869587000000	1612474387000000	1675546387000000	1770154387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	93
\\xd05847866a119ce34f5462c90ac5aa0bd86bc937696432b2d6a567912669dc678eb773bc6cca9da71de2befdf2624f9e5d963c8c54373f2230d43a56f4c73eeb	\\x008000039d16a8bce7ad648f2e0e699afb83f8ca0afbf812afef63c5d715ab2a71a9b8d725037bde94c2595a318121a4884c5542ede569e435916db969fa82830d3740c5621cb5645e737790cc4e5266363d75e8eab5006ed8013121dd803c9cc6a9d9f6a5e7e5d15118ad32618446f57f0809c11212ba3fa6387190152c99e248ca30dd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb43045b6a5722d0c89324d300c6f62e5ec8082c6c959a478dacb702981cfc7900733d8447ff1ae9dfa3a522433ce5f3b25db0f692346e28f1f5317dc0760010c	1639072087000000	1639676887000000	1702748887000000	1797356887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	94
\\xd4ec8200717211840935df14e75e59fb1feb17811ee715d445b54fed7f08dfed34884310661c45f13d78babcfc8757e892a280c466ed1959d76cc4dcf2babd8f	\\x00800003be8124ebb100d8fb3f9f090c38a1ec18db07ab599f942a801f31aaa328467f23d6a0ccac17641562cbdfe41734b9e15a6613f9cd6db277fab6cde1e624d68a75ea26df8375d8c48fbe0c69c6baca89eecec62f6e784d4f8e018d1e3698f4a25ae20819012461b1bcfd34584b6bea4b67e8c0286bbe0fd73c39ecbd7233869f4b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x218dc1ef131b39376a39154e49286dd838c5c888b30e7782a42881e5f86e6e7bd174801d955de50b905b8ed9be98aff0d10046a1bd13334d057dc3cc5e3f9d0b	1618519087000000	1619123887000000	1682195887000000	1776803887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xdb580cf05aacf8ae75c99c14b05049c34c100dd0d8fbc162987839139190a3249bcd1da9e3d7ec043bde3402f497c69cca9ecf05b650e63154f71a66d53a059e	\\x00800003c2647be6d39fd28bce50f9a9097ed2bb0aa13f80d21fbb5e6fb5a533c8c8bdd1f44212c92f9afcafcf93c9a87065e731e2e85b4389e7e587981404e90c1904cb2743208fb601e2681686c1153143a502bbacaee6e53bde6ebd695ee38324b4986d88fdd5fe4818a1b163bb12d4e6ad734d416cb45aa2db7b3b60bd0302654129010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3ca0becb31c857cec12d9c1be7fe7583d5b900ef0bba8bcc5d33c5c103f6a1c5b399eb5f00e65561dd02cb95ba44e995ae7bbf3792b9b0b97588b4f4a77deb08	1622750587000000	1623355387000000	1686427387000000	1781035387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	96
\\xdd0818883234a5f33add8e50adeaefee4c03ce40d1d886deebb12eefe0754e6d51b71280eae826412d104d36d7c60bae261d9ed2c4eba12f8126d59207c52203	\\x00800003bb593acb26132a1244f4b65bc5ef3816a0c9338efc1eb0f670a30173777ed60cc4dcd600df68bdac0e04f3ac343412b72290253beb61d676e860e671a3beac4f3615f71df0a3a82c5012bfe78c93d2d18e8c80ae180be467da423a3307f85a3a0b78b12930ebf8bf1f70c45a430c794e551e8b106287778915673b58195b6bdd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x02a7b791553b53af1982200f706a661b2490625661e48114edf1597c5bb1ccff74b13d8aecc58f1f9186a67f4bca59ed7dc7f29f9c47ca0bef6e8d6a0f244f09	1637863087000000	1638467887000000	1701539887000000	1796147887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	97
\\xddc4ccc57bb2082c7c02efb7f0a5a239bdaab47cfaeacb1bb271be6bb104b7d8253b6f6f1e2e05c09536b12bf1e65a78d6bc8d3d21a517deaec2c91df91e50f7	\\x00800003b6c693567043d2aa25a948f30827ac95f82610ec9382faf1bb2c00d6d58772de5c8e8ae150f069998c5562a313c74cfa77e712f2ba7c3323c08c75bb7e4c7626e62ef3b6b400dff665ce25cac520259748f3da79eccee18250d2d63932bc1a4264f462297b0e60733c19dafccb7bf35d0151ad9307b5ca86cffc276a5f6654d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x141f09478a01a3fa237a7ff8d056133aa5cb59b195d85bd13ba41addd5c5a431be0a252ae5035bb9c3e60091486f5bb75f52e4985dc624cddda5a36fa1aeaa04	1624564087000000	1625168887000000	1688240887000000	1782848887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	98
\\xe18c74430b1fc8a250423ee654ee96f465dbd9dac15678e05cfaf6f58f329915a5f4e0d0787cc5af29f253ceda3235a68ddfa19e01a3eb06ccc0f1786ac81a9b	\\x00800003c8ed0ff9fa4d4beadb4ad20e6400fc8127cee303fda061e00c82d162e452af69397ffb5baba83cb1c5a02b866bb1074065f1f2160011d78d2a42745787be90a044835d75f090f24bacb64296beed0be3d63f947cdff24188c8e8a7be137891902c4ae29ffbd533bb2a7757df6a4c917a5e6a10a53ce7f1049aee191d7f353343010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x62af9f32b2bb3043796d8be4d4b14c648044dc434e0f7e39f211a2967cba8942108bfbc7112ba6006364dcda075afb2cd1cc0cd6f68d917efaebea7172503e08	1610056087000000	1610660887000000	1673732887000000	1768340887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	99
\\xe2582df71cf325a5a947e9c3fec42f991836df3fa663f8972a4d97dfafbf8e4af30a7b33c34bbf48c5a76c64d45492cab9ebf8eb4664c3516fc6126660ee26fd	\\x00800003ef9e1436dbe6c2afb7bf15a1373d940e1e116fcc3d15006afff235d951711f82462929151c9dedbd8adc7ce93bcd6060f0487cb4441b4e409df69f98802537c71d70ab8cc72900fb53e445bf75983eca43213c0178bdd151cdb9d07e1d99c945518e5cfd91599e9a9d78e759d47bc5eb67cfcf38be6feb41154329870831c477010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x87fdf4ce93442b878eb772e52abf0d1470ea131be1fb02ae70c961cd9d00a3cf5dcbcffc7f255bc1b8bbd2786693490e291b08fd6885618e8d82adce14bcec0e	1628191087000000	1628795887000000	1691867887000000	1786475887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	100
\\xe26488d17f09219cec85b4825589c9f7271be516772a15be85012ee05ee540bec4370aa5e95d78a96faba875d121d9c97cefc054ec6e701b49cc7c1f58f4d0d4	\\x00800003d464faca43b860f8f8cbad4fc66a5159bb55115b0bb72d8874c886801afa7cb0e0205a08b205e898166cf1230dac25338d1ee91fa868ac84b39bdd4b271e04f587c5c4eb94acb9d9b39df377a8ab37f379cb424c4ff4520eb2e0f1402bbb71c4ff2b8feffef3a6b79f49292bdddb7c98288f282c53916e880df619738d80e37f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe3a4cf6dab9b0718b75e4a609d37e1b3e9b575167d9448c7ab876512257bc63597953f4b38b574d4322668ca56c81c289d6cba246e6719d46a64cb465a41730e	1611265087000000	1611869887000000	1674941887000000	1769549887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	101
\\xe3742381f45f96c6fed9fa8e2a8b1b37e09045a220f7e77ef614717db3c1f36987d02538ba748addd75105d659065b6136e79c674aac63057ec91ddb8af88086	\\x00800003b2a6590b7922827acda2ea0ea312b25432798064403d6f15707bc0aa06f0f84033a2aed22755feff8f1f55a9e4214ecb60d28546aac15ee991b40c1b0e9adab69d1f3beec0e7ff9e286a92993b310e38f0a3a819624370bb1dc258f40b198f541507455d6ebe0cfe8746f200dcc542e538c9276278249d1c68d5628bb0614b2f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa7fe7d0f140cbba0f9198c06cd9da4d3ba2856541a6a45d4d5f8007a9aa4b6f02eb62b40cb25db274178dbac045f047e48be31ebe15086ce2e6ba107c72c1306	1611869587000000	1612474387000000	1675546387000000	1770154387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	102
\\xe390d6e05ea2c3bed4973806b723ca49e621d026485fbf7d3f6440e43235ef0e5e5c6ec2bd70d45be0a03cb63ed15a5e1fe1c5062a502e2e450f4ce18f997417	\\x00800003a1acd31900987617c3d0d41a071d82a3dc2b210902ffa820ced2540deb4562192a0671c99688065d72ec26206effadbe05dd35cf5e6c8f2a5ee5a942e65aa54104db90c93b1b46a65f22a371c7d4d83c95e35d870eaa1ede3d180710c0ec4a22a9c8d92720d5e3874376742480df4868ce9c013170bae564bae98ab351881f49010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x34efc81e6a1834121378b4ad6da14e1df8dd12ec4fa160a4b991583473a37fde480c7d4228e6a3f1fa984af1f4bfb641063903c14d1d41bbb58edc83c3a52c05	1639676587000000	1640281387000000	1703353387000000	1797961387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	103
\\xe4bcc195136fc5ec6d8e33c801af7664e5d49bc374e898e68891b7a8743750a62fa9cd7f07c6da57e3bffa119a39151ece0794f5b79cf886b3da44fd3ed93f90	\\x00800003d3eb5b6e017552daccf2a88a9d1f2627cfd1e1083048bef9e4fda762eadfa25548e2213523f5158e0132a261a367e418f1ce20d04d18fe5074bfc0eefc71a093004b03cbfc2f129db1213aa330932ae6d41c15371072480ab78f1c20bbd95788962f59b45c2a80f1e5159258f5a5a432803f829f1721b1313c04de22de41978b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7a8b7fcdb6036f616fa0c5a775669562748208854dc6bc72a8cd332a49b365f47e4605faf155f23aba4fc6de9703c92770aba5cf37abc48831d93a81803de20a	1632422587000000	1633027387000000	1696099387000000	1790707387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	104
\\xe8208c20a023c315371faabf69c8a9ce174bbcaa361e5cdbed09be5bfe836b0b262c6d1b871fad48515b56198b986531a137b65a684c33ea0a1fcd233aca2aae	\\x00800003f451db673fa832e094ce5e9fba70a470dacb1b99932688029dd6fc792ae75b4bf44d8c1106568d21cd3316fba34989f57d7c3c4c4936c5623ed525a0732ba4f8a36cd4b42879c3cbd10f494b99c575ec7d60ae4b42cc65a550501e8a8b83d90042ecfca7f5c028ea76a7e58b4de37a166f727d9cd25c64345bf908c400e92571010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0c8be72e9f7663ff80c1c8bf9514bdd0739a108569ad5bad7ea571f7beae750cb7ffe256967d9cfd896cfa220ca74d530870245e2bcca48d42c3da2916c24003	1616101087000000	1616705887000000	1679777887000000	1774385887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	105
\\xe938fbe62588b34cb8d3738f29a9dfda181dc8936e559b6123bb5508100be0ebbd7d3eb33297b1b6d7acd0a15f56dfcfaea395aa582042cf0643ef28585e113e	\\x00800003b4efde80f28aca5949632fa81e85c327ab9f2789e76c080f78697272373e9daeb551025b11606c45fefb2db980d7b815191b8441308a3dad7719653f4b07950c81d0a052d6614e38cf4794445b46b9bd0713186d237a1ad1b7b2851bbc1eb0da56ce29f7f1e69a53b23e797a44511915554ef37f7c796ed947ab8ff63aa1232d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd747a8149d33685063b58c4a03a7fc974befb5214b2b1c6075571ac838f6a3621d600f3c8c62d75191443be161d010db5eecd48d3205e41ebaeb31e938cfbb0d	1616101087000000	1616705887000000	1679777887000000	1774385887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	106
\\xeb98c57dc039d6400ca919ac7b7e683cb16e7737f703c62eb594ff652c6eb6e19ba227b44205ebb3d2e5fd717b2495893472af10e7b14ff5a9e62b9c1b4059d4	\\x00800003b7864f0f842ec0ee198e36f005d6175593d6d3771719e2dc5e8457563a9b84bc32255c42b4de0f7d0905aa1a763acc4c5d2da9e8899626fdbae88264ca4b03935f0c7aaa62fd68135081a188ed5df8b550c9dfcfea3ca6d0e7fd3cc84e18b2321954f3b084baa9989eb89a365d8d9a20faa48aa5adb9633d71a0c1f40647e297010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0d5bf5129f988e2422b33e671abccebb8af050e297df89701067be0ae48910151bbf5971e758f15f383ab3e392616e96fc547d07268e08cd559329679e9bb408	1632422587000000	1633027387000000	1696099387000000	1790707387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	107
\\xec38b97404c6b4afe6ac879b165423044e6eaa3433883ce703f86a0ff1e531587107d07936b543b7ed60c66de1c335fc9e162b2c9957d09c75536e4863693110	\\x00800003bdbe03fc1bad0ad9af1bb36dc20c856c8287bcea5314f68a4f2da413357e1b9123d4d08b4d693070eb8da80816f76ebd42272c8e74fd7c47be175a3f7d0c06659a61c6926717a4fe53b1fb39196c287a345399d9bd4b2f68d2f03da34af5e8f16f1b1f72113cc19e3ebbb370cd211b6bb83adcece84f39fd2bedbb4c02a16c35010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x363f4a33643191a44030922ae71d8b9e3a9e7f21b08bbd0425a7a0183a7b0f4c9a56434a51b9e071857af55e82921ad94c3705f1e0563419a89e15c35686eb0d	1630609087000000	1631213887000000	1694285887000000	1788893887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	108
\\xeee83f98db7e7d7b37d93b6e937fd723a4cc94321ce9f3f58517ddd790e3ae31d2307f1a6ac4ea7d5c3b9deee7279895ef1ef39c6b6375844ee0be2cde9687f8	\\x00800003b866ddb5486d33f8d90c7e3c190d98f898a3e0b6ccbf16c017d5279ff5224d7d2a5f2036f634dfe9f65f012db4577f7349b51f49f44eeed8d2a707dd6261f3a5ee359549926d3896b965a72fe1bb913f166f096e1e3cc99f76acdc6ee5aa658d9f2aaa030cedd330eca182e42c90a350bbcfb2cb07a370522299b1a536f6c125010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3d697da6d317e100a247d953ecaa3d33adfc6a29d141c5a1f35cf160058d1bdfb3e87fc5d187303a3a15dc75c4e36de0e04752d5db220e1a950db52e2c85fb0d	1631818087000000	1632422887000000	1695494887000000	1790102887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	109
\\xef98bcdda1f188781edc3ca1d3718b4144d172c6e3cc25222e78253107f0685c738e2e4903d3a5c2f92c35a9a382fac0ba870180fd108b1d62709c794377e6de	\\x00800003d219a7f898d82c7d01dbcebf326bdf805e10ddea42770b33e7cdf21e23528003d6e77a055508516eff3b59184a2cc9e3ef1d6a1b2d2e5169444fb6d3ac3577aba4cf2367a53c05d34ff2cf8c910c23798ad698344e604b0bb757e4e681aeeb5cbf43410a81bb8d1f1e0d91a522e3dbc6c05331e0481ff4aeec8ec742cd9500dd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9f5fbd8f2541e0a3248c1ecc234a0bdbaa55d4d369ff96a188c547534b9ff3794bf2e128a137e7b6f63de8e445c1d0bfe505aa013f744f6a9947d1c1b34bfb02	1611265087000000	1611869887000000	1674941887000000	1769549887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	110
\\xf2a42e61025cf381a65a39e574ac5a25e7984be472cb0715d0f3399b465672e150c48deadf0505a9daf4cb4c4d8a6affd6266b7d5ff6f1e33e6dc0b5e7a6d0d6	\\x00800003b4dd6db2cac32f204304f0909bf92d1f69c70430465ee2d90eceba4dac6f33954e2b2992ba62437120e229b10e6b10cc42170462d00e06aa69a503e1666109e7db9d9bc8001d2c2ceca0309d337333fa01640a076dc891edfa296984137cee4ddde16a04740fd26d6b2d7d6fd00f2cf440e180166037dc5443e368f3d106c83b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf398fee1bd7670a02bdeede0869f67d61a3353cb2e56f8ab81fa109d458beffa9446d0c9386c6b3c3cfdb8fcb954b46b5d238c1e50dbd894f267e64e8d9f7200	1621541587000000	1622146387000000	1685218387000000	1779826387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	111
\\xf2709871093a9f2734812914b942cd499eecc8ab497ebae63dcaa490877b40611e285af6d450779f8794764c506e00e0c45ab3c0215fd8faf1647d23a797eed4	\\x00800003c33a88cb114a2d05da0b6d2760da0e32b24ebf1d488014115b2d9ab09b52b028ba8dbf7baa0a02c47f17dd02913e810f9cade22bcc9b5c77641358123e615cd4ad187fd14c024239deb044df2e42e3c25d2c7d7da5299d8f41caf3eaa082dc92a00d61916df3379b17cb3d1fccfdda6143f4b756ed755311165cfcea990124c5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7822f73d6189d9c3ecf249bad8ec5ec5b83cb90667b49d5bee2517b3111f7bf16b35c9a8f68694d24199ca6dd3b44ae7759f39fc3eb1bd16bdb4cfd35446050d	1637258587000000	1637863387000000	1700935387000000	1795543387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	112
\\xf9083c2701abfa43548ac53cfae4f7aa458c2370755ffab1b430b701f91e790aabcd987c024a7e95b0bf8b926e23d352677f19d3042ae4f127b729953bf8db3e	\\x00800003bdfcef35fb9b6ad538208d6f99b9589e30b01f58c8eb582c60811c9ae7ea4bcb7211f92ce1fccfc9b13ef21fc0affccf1c33da9465556b448897031e4a805c001dcf00dd1db6ea459ea23f5a1a621560435fa053dba703abf0d8d8f310c6eb667431d666537d951b6329c191a103930a14a6701b8db3a8a87799fd508e71798f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe0dc962917f31f8422051a688cd8aa4e29aa6ec9da883d60a8a3b0bafcbc0032dfebe40a2c641974690470a0b3ba5e835a7863773d34691ee33961eb4218b40f	1631818087000000	1632422887000000	1695494887000000	1790102887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	113
\\xf9283312555ab3d60a08b113aefe78b8fe4c6c4cc627a246a2e6e99d38d570fcc505afc549623c25fc6bd4d3b644e294363fff0fb3e87dbcb448cd7b75756ce9	\\x00800003aa8295ba877b94f92939bc475b69f58d9fdaa32b2c1fdb5d0a0901dd733715fe9f8f4870c830cd79529640db82c7de52855e59c60a3078a68b87a300917e7ef5415b525658c6d9b415ad7ae69fe3ba67511cd2a73165d3b24cda35e609cfd3d9d27eb3a47cecf05ef9fd84c50d5c240f823556a5453ab7cbac2f451f0182cf6f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x05338aae28889a55d6d5f2d436dba5a3b38398d8174687d69fb3dc4c23cb4a8d708dd016babac3bcb926a1f3a40f955fbec838e72b4f8471962bb41920a11b09	1616705587000000	1617310387000000	1680382387000000	1774990387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	114
\\xfaac1e9fc7c3f543e946367865f8710ddca957ca7e495b6cf1825fd63d59a21940bfc1ed7fbd42a75f4a0d648288e1dc54efd6de8d0f1922fc0e092135abf133	\\x00800003c0f3a3be9776b782f35353647f0bc9aee25426b9eae7a4ab3628e82429d4b28b87a9268ea985a6fb48f4e14e09b59e7c1c87effa962b745994746d5a40a8d5a97d80c62e8834f9b60db70f576af28e95bcdd9d20cb0ca0e3af9883e66d08cf49698d0ca0375e1daf273b1093b4bd5108c86d4a13948afa1141c4104d3548b495010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3cfeeeb46a72db490f40dac1a3c55e885c12b1ba96310cb55890a6fc797bc9d41c3c6d7a805afc04bad15adc1cfeb857d31a49e5cc3839b38aaa4fdb59519a09	1612474087000000	1613078887000000	1676150887000000	1770758887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	115
\\xfcd83e754c5ba5f2126fc8206995e1f9ac0522080415a3bb05a6742fc6f335e7207399f99c61b121ca9dc7a5fc78c407f723d291bde0bd2326f7a017a0296439	\\x00800003ba956ffc346f4edba1afb0b8336e743fff66c6027b73a2a03db62c5d916164d23c48f127aa0f32849cb509bce3c4f4173dbed02726ddacfabd0858c98c7b3cdee24e579bc5e09597ae30181accd0a3a7d279d94cf2803d5026556334606b8b7e709b1a2faf122b41e36379b814261db7618b98a7de9677a6b8f612b00e42f9d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf7f3b3a652ffcb0cc60439d554e2e08dc6b2e099984c1891135221c3091fd62088016e9eaaf6a3a5b5ec01d988959b93f9f3d2e38fd5783577563fc265b1cd0f	1637258587000000	1637863387000000	1700935387000000	1795543387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	116
\\xfda05e3299f1626a1c438d1bdc384406c0a21310e49c24cd7a9c229ee625d8e5e231c31d72dbce8dadd68ba6759fc08a553620592bc6a773593cba82247437c8	\\x00800003c0833332779c276bbdf9075318784ae7e244103cbc18fd77614519b843646748cb78c4b5de169cdfb4cbeb946c8b0ebe14692c2477af8487d36e4403cce9a17009ce0207c7c638fbda10be170887935ae83af4656ec1516e31ffb428cf866f0b1937d8762e128547fbf7ab9e6980e5bc3c8e1c0821ee425db5bbd10854b039df010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x99257abf8dede7eb86febf36b07f05e03fb12cb2d87fc934e829244df4ff5d000acdbfc79e5ee860b6e328d59c523ce393f458390c1668431a3c41a0de12910e	1616705587000000	1617310387000000	1680382387000000	1774990387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	117
\\x051126d66b1b373a68f89500faa724ca790fa2b6761ff5257445167f80e86ce20dd38bd5b1076f4bcbcd50258f29ccbedde762fda303e998f82eca8c6cc8d441	\\x00800003d24003b6f5287d4a4bce6bc3b95bbe26d64ade2cab794bc317529ee43b1a79ab7ca7cd7e02e731a01e2ad3629b5de886660b2eba63662b6b987ddf123caee76d47694ef801d03226b2c523860aa0e28ee1d1148565d663c71c5a19c4d5c0b7aa3d109a9466fda530856efe17706e5975024bf115c37caf46187136b30729163d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2036fac2fa703690efda85d700f694fb2f94d30f89c19ba38192bb3494da64f4fb1fad5d9cf72540762c2dd1239f47b30e94a970e9600f307aec5d566eee0308	1636049587000000	1636654387000000	1699726387000000	1794334387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	118
\\x0d05d1d9b2acd544294166fc370358fbbff83562c0b644e5e552f94e6f6a8c75ca1f876e3fbae4e743914ad4082b92e5a6461a969e4f2154c59bf699f7649f76	\\x00800003deca693243b5cfee3481322be3066b891aef20bb8279795c0cef3642fa67898578dd738177aee63ebc6069b0f273c8721d9f89e89dfc83acb69e8a601d0a2bd0d0483b7c820cf13c1e0189ed35c7649f2d2e0382f0fa62f2c48d3b715e37c6818d1ffcc6475fff43c1195ba9ab40b14eaf3d19246526955ef78a27a2e67d94d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd8a6c52b238db0234f9b75258aed1cc513fb4670e321ace401a0bbd2d1abb2758887f811d9650ac95bc8433c73e704bc0eedd8d65d5daf44ab113bba3b0b1e09	1619123587000000	1619728387000000	1682800387000000	1777408387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	119
\\x0d3dcc89b252859878b28233ec9ecc74e8bba5585623fada479c77a2df0903019bfb3aef5e574627ff2bc84fa8d8cf9cd10971e402220815854ba4b687e6e909	\\x00800003dd34d6137fd5a6b694d6079e57be468aaa8d29d059cc88a97c818169edca435ecb3b8a7dfaa3fa1154b10ad007aea5e976d0cd80313ce824d7f5fc09d0a9dbfda9b9c068754515c3ba5d3fbbd831c1e0f7d943820d42804575350e08b7eaa42b07cab7d4407c93abd40fcb7c01aced395f0c7928fe3dd809910f11275709a57f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x65cde2d5fade5c2f375e2733dead3d67396ac2dfde046a0538f8e705e735bbe3e3624ce60cac82ebad70da6b959c89141d5343134e0c18fc4b16a9d692110505	1622146087000000	1622750887000000	1685822887000000	1780430887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	120
\\x1085535313399720c4cd31c9b17b81ddb9f0a735c592f1a0add28be4ba18564fe3e5b54e3cbde73530485c5b8fd7bf033cc66ea4db3d5a813d4eba2f66aa225c	\\x00800003b599d8916502d843fcff892f87d8d1f5f1ba60a7a1285f875ca07e6eecfacb2fe5feeab663abf46db378e94c48e72ff274c1264080534a6f448c88a645adfd7f42f78291ebdf09342c186547afe4df1850c8996c3cb501bbe880dc6c5cc71fadd35f3626a0174c4cb02e6f9030025dd668c4beed47cb73d6bd2648b1089506d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb925b5d3b838c1d01ebbc34ab992c2e7bb32d6540a3354c6695d673efbb71130628d29186cc39b8ca95d8f30662048e7d7b18293d3a962ec7862ef1ee620470c	1619728087000000	1620332887000000	1683404887000000	1778012887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	121
\\x12ddef7227139342e8ef715a7ed45297ee9f92443e7fe195f32703af2d4202f7f562ac8fcee7592f575f49f251a9ffbddd96b2c93807ab377829e7fbfed5d5cd	\\x00800003bd969dbc2052151ec3c6148ea98e6b15bf91d27e989d06d31ec741e872aeda8dd0c2700971917ff22668c7816285fa9d050d9baf7ca2a5158d102b380fc77f97679083e9631ffcfc724120b676a7713a0b710af75e50ae2cc85491537c69906c2520c58b4bcf95f48fbebf2d959ee8888aa53b304d61c6d3bc4ad6502f52574b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x72802037f2220ca7aa8b05a63ea92e1253f2d565e5790a06438a0338881e4effff4f7ce51b607970d4cd7deca42c06b85a91d4c31695f08c8b0b7bdef5c5ae01	1628191087000000	1628795887000000	1691867887000000	1786475887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	122
\\x140d9c4d348326bd64adbdd14bbe7f106be4ad1a5c5b61d3dfdc2129675e36e6507a9f97ffba75f64785bdfb8aca0a485d08233403cbf224013b48ccfd356bf4	\\x00800003a373075643d3b3c7df9fcff33b421fdb4652965e625e3f09188ebb3e8f304974c9f6eb3da06de3ce8d228719ba1188e0d2217c812c8ec895cc6c2dc3860f1b6448986882ff125f678b3e4f8da0d16146f99af8c203c120acb481e87a2327b3c78452dbdbd047a9a3bcf3a73da2d2184764a8917d265c800a273f2805a7e28f45010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe14aa776aefd3be5d69df7cdb21c62cdb981566147bcd6deaa88df54d34f66a68c063d92fe52da83ce98e097a04806efa255170dfd4541d64eb7b1c2b3826f01	1629400087000000	1630004887000000	1693076887000000	1787684887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	123
\\x1d6d7aad16b90e5c811bbb9f817bff8b51d3f561eee786196c2b225cc58a961c5af8992c02b451b1f30d69dbc9cc77f17786f60d40880a7afa919b34951614d9	\\x00800003d937004870c0e859b099f08718bcc57e6fad8996f587fea00a49cff2422e81b9a0d8c278ded28852ee10d6b7fdd17d0be3620ecb8bf2602ebeac8e45ef1e1dea074f21d07c564f818bfa7bfbef31807dbd54208fa896e52faf19d6dfafad0ce7a60db96f6ff0d1fb6a57dd054f720c2c5929201cfe029c0a08c0db8c80175bad010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x432ab2d2729f317701080a3c59c686beb421252cccf93dc58c59b03c5e4f87410c73fcddbd73651f0281bf6b19c086d13eaf350fd3cbb9d5e62b47fcfbf3a509	1619123587000000	1619728387000000	1682800387000000	1777408387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	124
\\x1ed9f072c106e2fa582eda7ac61ce93461a7944b200890971e996bc8837e11b6e2ff74a45761d145a9cd3861b396331374862e3f13d1fae14f2f4dd43ea90c80	\\x00800003dbf4f982b5db4de6974cdba76b5fdee293255026d89e03e49275da22cadcdb70fc0f2363dcb8d7a9e8978dceeef6172809d76a5c1773031759f9d69e81aaed9574aea5e7c85c57ff36bc7219dc61a60b3352f5abfa51420a0e9af578d01fd7a17f841abb34a08f9e0fc56287d2be54b954c244fceb1ed3e107ad2b2f56e45e5d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7199cf230d5bfc7bf38d05ac805203bc93036e7de59097733cea8c5ea7000bcc2c751e7c588de090bb81b4ef5b7b80d926d0c6f457f2a9332cf7414f945c5e03	1626982087000000	1627586887000000	1690658887000000	1785266887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	125
\\x21fdb92f0e1d9b18cc5ddc6e214d5d317514cb2df982834a50c82627f108fbfea0c82aaa297a80d57d0abee7d9299bc4a6524cad460ed9768faef068e0a559c9	\\x00800003e3cc2607b24f0818cc7e237145bc2364697ad1f60bbc73af462776985dd1dc5204964d5e8d46f1483abe43ec73b60f2d686a04180a8cb9275e13ed84bec6534675c7992d66323ae4cca3cb0f46556858a7e345360423c1d306cc732baa44198701a0ebb4a9156270dd000a52afd2653c8d2b34cae29cd3b542fc569df1ed0095010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x718f6e603e7b059893dd1bb9420dd15f5b2f5433a078f1f0275f1cb41e30d9ac63b9f1d0eb0d028f28b4dd5b2a46a0b7ff3282cf341be731c1e9861e03ff6803	1616705587000000	1617310387000000	1680382387000000	1774990387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	126
\\x237d035a2d24c3fd2d3cb578da6a1ec7cd0ebab5052ef925b4bbd8feb309f936f43ab3731d2c84c422d09a2225af3661bf8c529c91ee2239af8106a7e13901bf	\\x00800003c52bdd0db47667fc3d05df22863b51c9f8efb3def4fd6818547b227b03197d20d6ad679b7f7a4b2ca2084023a4f9f6e246c293cd5142c0f7b0c038e6c3e73ea4a1bae988fce4c7640e89a174ac1973d225068ec868de0ead19136c369f2e77d6cfe0047ed9a0f2ef86306bf6dd65fb9f341e471084aafa0f8f7acd1967bac67d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4a91d23d777fb272636274195797b325ded36a42a4374d2df0ea148df9c03a620a6459961a82ab0a15180aae309ac3a333a8aad937240b8cb40d90b3b94eaa03	1614287587000000	1614892387000000	1677964387000000	1772572387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	127
\\x25c50cb19be925d86bcd9eb4fef3aab3400641c2d8b005e3f4f6866bac0b932cb37c71ac9ec3a97ff068ae127f352a7a6563605c5bfd0b9b7218143ba1387fd9	\\x00800003bf0a7e04ec49ac7d88f61ef9bc5e6e2f95dfbc3e896c773ee9b454059c0a69a980f1d52f42e045b2984127e8f6f5eb7c3665b3d8473d89b2a6423b042c60326d790b1bceaa733c923240be7da8ea26fb2b42ff34bfad7e8172e071c191d24a8887ddac825ae120a566399090c670e0a464f9658252519f1b5e1d454cbd18c671010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x86f60f5020c041f3bea2e83784ed2350847ce043e78804078485c22ea246833e781705be98e092ca2012c19ba2d8e9a140efe10552b2703a0860ef18415af004	1634840587000000	1635445387000000	1698517387000000	1793125387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	128
\\x26d5d348eed0211cb00501e685249dd3869369d36bf525d0f1b16b539341bd3c697f2f352ce0608cd1bf2a6348721974c8f8879fe8b95499236f9657a855857e	\\x00800003b5ba92ed72a5cf34c06fc3786ed185daf891d0398f615cbdcd99b36369c5b40e9a93ae57f227daed36cd29e742ff3e9c5583de752290531540a0b477a4a66f5e76236fe1948475c1d84c67343b1d2f4fd34c30b33300c588799139a58b8f15659424bdc281c36400f25c363ff0e714586239f7b5d5b414f5b645e8dbe5d9d8cb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd60a1171d8d3663a815063d85b80eae69022c4ea1998cc9ee530bfd03523b0df9babc05068338e783d02969699f42c7ad49d52ccc444e9a262cac8ceb427e104	1625168587000000	1625773387000000	1688845387000000	1783453387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	129
\\x26f5b48fe6d3e150e0f62a16c94b86d373e09acc064de8d13bcb4898a29a381f8fd1e464c9728dfc6ba3e01573de40daf7b9651397844021627b1de22212f3be	\\x00800003d179b0675caf81cf570a35ae4aaf6f1e481ced4ad5f55af1d197b46381ae21e837e5cbe34ec41516fecb00af08e4347af91aa6a1b12f1a7302b59e4af5f5f974e82714c88c412a111a37f991edec40fb55197683f5eced63849db2bfa69af397cf79e0b033a2af5200f0e084db6b29e23db38cbdc7321203a9e2a1a2adc6cb1d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1217b77804628aedd281fecf37a702cc91b5f309a1b65cc7c19b775306ae22ac9c267ebea55a3e9d64cbc5eec76cb5d759effb12896391611e916ccff0337d0f	1631818087000000	1632422887000000	1695494887000000	1790102887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	130
\\x28992590eafceb15c05082b0ce2aaa8deb943ee97f12b5c7723811c8cc6388889bedde8c4302cc089ef6fb44a60e9662bbfa6344f71ee6a2266b7eee8ce8ce70	\\x00800003dd3dce4ddf9a6e60636120ff2142b64990d05ec282b5555fa99600ff8ae125a7aceb13fa5e1ed09e2701d77fac1c7f2a02910212a038d75163bf8030c25c8fa816511eb655aea2dc5f4b9e2362c20b3077cf11c8492da56c4f6c198302f58a858bb8305f18a29287cab463369fa8056ccfa88a28b70789ed94a041a43780c3f5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb1b396f21758d6d2f28e0911a354aeda8e9d53fc159eb0c423bd63fc043cb82c90a496635e311799b5f8a8945018ea670860db4bd8e01ccf2c3efb774f80580a	1623959587000000	1624564387000000	1687636387000000	1782244387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	131
\\x2945980032fcc35e5a1cf6133a839b4d9ec149b2de93e9493f538a691f457d042d72c831aaab79a92839e827a78e8e070250ea32e6d2006cf2e529d16e6a71e4	\\x00800003dadda89c6fa1f8edc3da406e9e9bdbdae524573091e317e6e444f6e6fca6b62a0de1053692bd5d8a02b6885a7ea20107a2382faef83d1b3d65bcc9b8069e3a67bde86d737c96bc478986fe061c7f875ce9a809091f6b5a341394746c06aa456ba8ed3065ff9787f73b169d31a5fe5070ac9ee173aa9a5043517d828505001a91010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x39ffcfbde453684e5b053f4d4049dc42c41d28943bfb03296c2f98fd1aaa12003791dd097a65bb713a52a53fc607eb9b9e11bf99cb4c653431521db1a3a59901	1636049587000000	1636654387000000	1699726387000000	1794334387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	132
\\x2c8539df22efb93cf8b0028c1a9358f68e316f9dc00096627bd9d141f51d22ab1eb05ddf8bfad6293a38ff79ec48c6ba2429aba654a5ba143a20168fae165255	\\x00800003c608f1d92fc520749aea0ec42f3d98d6fa4a535fef1aa98e93ad03161fa9f4911e270f6e657a3bf5e3f6cc9f3ef08249f7e57636b7ed401791e2321a8c3e749ad0fc6e39e78c8a614e16fdf8ecf9e74325664abf235f6bf1415166d37f624e18a55f4818b76499a098ba2520cf9a6ff9a404a6eb5cd64e0a456302e73d043ee1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x907d62eb05a412e655a4133d9037c7f706cdee270252203aaf9c7bdee61a72b6255333213208f6a865cadf7d0093ee3663a75ffea1d75c10b13d570702e4e90c	1620937087000000	1621541887000000	1684613887000000	1779221887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	133
\\x2f095de591432ffbcb99485b3afa4c930765ec8531d8603f28ea7f2af61188ea6187dac961670e834eddc431dc457780f6ca9d724a337c3a8a6ab94e5bd31d36	\\x00800003cff3f731455c30016350f1495841b873370d8ddfb6562bce1c0a9180019195e859d946947f965688d777081135d60c55df6a3b89c5e76d2ee5046cd144a73dfdcd938a4b548e081e6b6bd871166880139b743ce34a46971ab3acb3bbc4411df78bafffc0e83826e8793d7490d774dd8573eee613816bd210fa6545f7d6f621df010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x282bbe8e207b3e5d244d437f81bb3f87bcd4f592cff647c0f8b1a11f0c6f430d1e5858c3f16ec30ac3db0ea6c376c42a52c9beaf0da01465697924f8f9f0820e	1636049587000000	1636654387000000	1699726387000000	1794334387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	134
\\x33c5e5396be47745eafe26c3d9e8f5812fe970809e126699f465fbc1dda8e0e16f432bbaab9806957aaeb10ff32db2fe848e58a7bcb8e3bb0139023bbfd541a8	\\x00800003a8c0145b69371497802efc774976a0b0af2e0f35a8619f76574f44e4d2c8edcac4919c43692b9e0172308def300dbcb147764f524567a88187bb6f711bb6bed6c29319bc51c3794b12bcd97c9e398d4cc2d9cf81e75df9541579e0bfd2f12c67dedce02e5dafa657224afc2d1bf59f0a904e6bb17c4d31dd43a7bcf6e5b82409010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbaec8749ed6fcc242ab5088f4d4ea9c262072b773f1d288cce3d3b98beb7831846ee0263845d43dbacd4318d41032c0df6c88d20e0da156ecf75bd665a8f770c	1629400087000000	1630004887000000	1693076887000000	1787684887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	135
\\x3a05f863c66c43fb0b75f997a4f6e99616c8adc2bfac8a253551ad4e48d2d048cd0d3a3a081dd7eae59255b9ec68155eecda15e36d939efe10e62c5c044b2723	\\x00800003badf651c38e892ae111c664c2437b79944f8f19638e02b0381ef84e5b3e03312141ab33f40aef4708caa256d8f23afc36e654cdabcf3d7b82ffae53b1db1309263fc7cd5fcb1adf5fd44c6cdf8f7a3f08579932f08e7117a336eee6bcd8ccb253dcaecce6f1aaab46b71ae2057d58c3da66ecd80d8a93a0acd6120161675d4bd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x52bb9981f783e8bd6f87267236aadeb0ab22c6b8bb1f7109bb260a2ec319febf433e905116b81f5c33d91061e20cb27d040b7a8388ffd38e7e80b4afa31d150c	1619123587000000	1619728387000000	1682800387000000	1777408387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	136
\\x3b6d97bb4c6719c8e47698faa3a1241292b93659e40010235c4f8a6515a43e1122e077766c982aa94d6898f21ad38aff150c40625063ba98f3ca7bc7f33e4f2e	\\x00800003c02d9b831d6ce7cacc8d942a2e6abf84111acf50fbca777a0a61cf58a733d812588a80cbba50dda4131929056930882cd037cd4beaf9b23352409e1115dca278102d2fecc5b659562ace961bdb34be63335e1012125313745ab17b7e6ab37328cc2d4aa5c2401d74bdb5e9c9fdf43fbd1cdeace05e65d24cb88399ebff866351010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe1164efe91b8d37e7bf7ef2876e1f2543780621476b2f24e809977fb42985246f6c6212e4500cb30851d05f06c566b26b24859a5a509436f8652d3ad4d83430b	1638467587000000	1639072387000000	1702144387000000	1796752387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	137
\\x3ef1ad159929dbe54d64024d9a2f82d182cb26cbaf86e6dc00374bfc2a39d445f4044995d6bcb005137f4c42daf470f5fadcee68835049d95a7ceed8154bd6e2	\\x00800003c25163af404058fd894c2b1f8c2a908b5bfa2a4d40b49cfdf89a5de7cf2fdcf7f02d712452c31030f87d11daa2050844bac18173809ddad664467dbfc74f828eee2b0601ce73878d9649c278afccd0b6d6ec2a21a9732d15c6a9a054e8d9181171b2f086f88ea7f341301890e19614cd8fd6089717ba4a2174c34fc8f52690a5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5638b59b6fed9a9b7cd05fbb9bca967218adb92cf47085b12595689a8a12d9d856f742d78f4bfd2e2246d5b601d40afe26bd6cfedbde3ca6a66543c2e398a207	1625168587000000	1625773387000000	1688845387000000	1783453387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	138
\\x4281dbb93bce6dc2ebb5b5ecd2d328c14dfee84bddcf9d1b8ee58439c4e3e17520c75fab4825391c73c654f32d80b0dae5889199c2327b7819ac1b7d0b675cd3	\\x00800003cb339412def114a8cec06b4899fffbeb858ac61a7ba1fdb72be7402f6d2b81cb276d033c56cd21ce831ff41313ccac6e7a3936c1a6b00af55994bfdd115405fcf74f7db908cba6387e3d3970a344af8c073e454a4d9185beec2ee67dac4ed15e7295f11fb031d17f84a66f1a804f9cba36332bdca36325d6524d85d91c697e21010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa080bf172d76b156c94f3f0e707ebf18c6a061d5fbd0ceacac68b027276f5355af7d529f743031b58ef18a2b884c698800bf03a152f652daf9490eb829b5400b	1633631587000000	1634236387000000	1697308387000000	1791916387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	139
\\x421954d4ca03ac7ef4dfd2081d6bd1b920eb8a81d167d4ea8cd49d715101722eecc87e7a912cdba45896501ae25c195fc8cdff525125b0df73e055e8e7596c90	\\x00800003bde7d03aab9abc8f6dc305501eca9d2ba8a2c1df93cb1945ee565a02180b06b5ef00f3c9729654da4b331c0419600d996fa03fdadc904a2180200e17e2db2643cb409ee7b27a859e85ff6ca609bf70b9de7100d4e274c3ec310fe89833277b74ca3e6db3862666f656882086f2688953126ba0eea54cf8a645a51b125b7410e5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xfa060db3e9ae4e174003259202ff7b3b9f8a56890cefe48582c04ec1b2c8996ad455317df9cfc2853cecb7855e3ca2c88567def8ac438c87c02aa66d5b227f04	1625773087000000	1626377887000000	1689449887000000	1784057887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	140
\\x43a90ccdf6622df7e65f139f8a6f267065f2013bbce958ec239c504eb53253df2b1469ddbab609ee40c8843db5648412518725c91573d46e34cf50e486cbdc07	\\x00800003d3367e37ea871c910670bcbd6e9b9ba246928866fa503cbcfdcb195158b849bf2a797dccfaa7386ba249bb32785ea666a4e3bb7fa94388d0956878db74c15e732c311d1e6b2fe80695a9580627491bb9573da547bfe4baaba4141e53283dd3260890f5bb7a837ab4641f5e0191202a3f1d96f627e417a5f4b059f4e74973eed9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe6bdfd6efdbc7db65ff39270e41b9c96f1dd052f29101745c30043697f5fd1fdb53f39a0df1d6e6795742114ffc483303ebf5e403b1aa54d8971f58754e81e01	1634840587000000	1635445387000000	1698517387000000	1793125387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	141
\\x44857cdb4e376a46e3d539523eb289503246d8f97d7c8c94137d5f9cec5a20d7e00522a98ee212ab47a3147c8b2e94e85231534c3b7ae9cdb5a9fa4409271076	\\x00800003c74a19fe1678d408863f0e98f97ab805def2008ad5406746242adc8611e00c8c40d008b44e43cd28badd17dee660e204819d4ef2345c606af4c24a8bc57d701bdaf760c4f19b96a16490d539d64fdbab820a7b091145bb294be69d9c48c7f2d7a12234c99217e3892f568cc2acb0a9f279ad554783f976eb50763c8a68619d5b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x91dec0f3c60fe25830eb299e023c60d092734ff8d3d6cbf896199c609abd749ca1a21154120f74ac813f99f7e832bfdc0cfff9a30cfc1ab44292825a32ad0e07	1640281087000000	1640885887000000	1703957887000000	1798565887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	142
\\x44ddc818356071596217443817cfdb3d081b1d9b296755e5461bde74fc4adfcf713b30b27fb5ab8ace4d505c2cbba8b53ff2252b89487a4ce68992ec903d3713	\\x00800003be8c9124d88666a768310ccaf50fb06f335992e09a2141209dd02a74520275e292c64676eb377b1886cae774647dbc01e68634818f7a550bf6c7ae74567ab24c5d0405da9adcee8a4638cd5f8ada922e9cea4acf59018cebfb22d0bfb2a047eecb2aacd49ee0d2889861d6d7b329e2be896f357fb32f1e9f9cbfb7441152c3b3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8665c7c533bb68973fe34fb4a24e204a0ad3bcd9a5e3d77bfaec2630345a93ab09f5bbf0d335810f69802af15b747f2bfc0f27561cc705b8e5c6e6862513d200	1614892087000000	1615496887000000	1678568887000000	1773176887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	143
\\x486160f60e2470b3ce1e9e0ea65f0924db40661176f7394a3b0a9bc0026d3efbe1198d9e7764ac1500dc3c1f933cbb6653afa0db640df17a4c989ed8933a3fec	\\x00800003cbbb2774a5b5d6ea1fd2f45c5b23d9717c1c0aca5fe8bdd043de56ef060f7f84b4f4742e83d4054e01485663ce2214b6f993d607f323a2cde9439baf79d97addd8720db88084355aeb9d1fbcc1153b384fe7956e43e84746bede729c68d28121db093531b34a90815767d40304bfc0e643e3a2b126242ff7d749f128c8fe13a9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdad18f0ebe954e3114be776aa46392ceee55fdf7cfc748e4a29989e465fa9e35e021ed7d9cd4ca5780c23774dca390a56025d40d5ad8235f9d8d4f57b4cad30a	1616705587000000	1617310387000000	1680382387000000	1774990387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	144
\\x5711e1532a3fe7e9b0ab01397ac6d9e81c20055b9787e0ef8dabf7eecf9beea86b54dc53fb1ddd5970bb8e44c325c5ad7410df5894a778cf143facc4e2a4aaf3	\\x00800003ad72d615e4fb5de888617ded67961fa71660159c9adb857b7f53bd12400b0fe4475bfbca885dd55bacf6a4fe9aa427357629bb8e159866468f71f68743119fb113b03d51c3d619f115a199cd56c4f7196502cbdf4aa21a0f0cf0027ccfe3627e3f5b6763c0051bfd6ead577ca64daa8e747b055068d8684ec90f097526b4932b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xedf5be8f4e6683f648dbba59dbc34006b813848d15f009c33ad860600faa7d3d868d0138a32372dcfcd240a3bb4710e75918fef28eaf0470959a97c06ee1b808	1613683087000000	1614287887000000	1677359887000000	1771967887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	145
\\x58bd2d6d891a63e35c30e0714a1b54688a26f05aa508f52fef81fe07ee1fe58aed324927f574286f480f4498627d919c0e09bcf74ca74d398bcf07f7ab4ece4c	\\x00800003b6e840d38331831c2630f43e4e1e521e59b7920b38c7fb417ffaecf27a5663c80bfaeccd5a86ee8be572338e30554a4ef2ed8964868f619eba67da991b99c3b5245cf4620a0297864ddf8a15b5a144354929c15d77eacac0234dcda2b71a61999e92960fa42f3808a42708f196a580655dd1d827f9d959a48e241eb36c92a8cf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x18090fbb85cec2debae2db782d4729d2424df5c53720c3563b6b74a82a6e6d29c0d68b576a4818d6017e9c9ffd243d66ed8cab83182885bbc095b64261330108	1628795587000000	1629400387000000	1692472387000000	1787080387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	146
\\x5b4da448a3441a604955bfc0e6d0ddefb03508c37e330ec849d019a9020ce266ec1e08af77481953ba297e1bf870c7ec5986ee4cf58df97cc45ba2fc71390331	\\x00800003cbf3438db0fe70c200dd7cd43c448f935e95613c97fb53f5efa0e5ea2d56e75be634a7ad581779758616865b31e8bc8c8575167ed20a731b03fac5d953ad9ad155404be7f2072583ecf8406d9f542b2437eb986a145c85278b6741a9d66d342caa10f719e787e927dad3de58f611ac793b6473781fbc2cfe9a89202c0ffbb56f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xacb1881efd039194340385096d38d80b5193178c59a60b0d7830d161a06a2d646db16e8d2f6cebbd558814d2f9f552a03bd167fd16a42db11210a027f82fe507	1623355087000000	1623959887000000	1687031887000000	1781639887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x5c092916424b0f26065829745f57d1184c048e1c9679d302bdc5562ed72823ca871322bc8c03996882b7a440ff45dc6de26564b3571c05459987e5d842fe831a	\\x00800003d39102971e804f6f8c8fd679791ab79275a07b4eb006eda65fec645deb680b96fd2e7b869068a31946a8c63c27461fef99ba555bfd89e861774b84892d3f94295b73371a1243d6ce52a2ff39b308ed5179943cc6bc6a05b3032db93c1b02bfae4d943352481163f676dbb6b5ca90e61eb7bcdd08083bd20a4392e4058c00fe93010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe4269ef8a620a75f6c09de21dc7bc6577c892830777e427f2eb5961ecdb54bb5cbbf838f26b6fe2d39482911bb7b595149acc7af81b5d392b4345fba9caa1806	1614287587000000	1614892387000000	1677964387000000	1772572387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	148
\\x5c1532935836197670f17b9a9c068484cfe353e33c214d30ba0ac543a747cad61992a8b868198366bd06cf41417b3ae75eecff495bf161a92ef3635d97549979	\\x00800003de37f0217ea40813ac4643899674146dedee06ec5e58e14506a0f500f2fddb4016aa1909e7fcf4481083d9fa4de6fb9260dbd5c50fa8690d0046c87555bc84b44554917d62a7cd8ad05b9225520f44e9f2ff444b5b4c9e58447c2006447fb2d6030e1eb107637a1ce8cb6f906efcb027533ceceda9fd112434d1a67c97ab3df7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x136381ab59d6553283823f9a3ea6fffd1850ca07b256c6f5fad0967d9ec3b27a9bad1c964ba8425602e1711f304f8d513cc43500c7e94fb0dc00655ed3711a0c	1618519087000000	1619123887000000	1682195887000000	1776803887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x609593e90584e5107eb3801b88325a988cfcdbc6479f8ed8ecdf5c146d2c2e74830b92457769c5bae620f9d12124c970928d34aec4223b88f80a7f3fcf7a4721	\\x00800003ca5ad1ce7c4b71c18cb89c84785daa051273a316ad29986674d4a2ba6bc65b5bd761fb775138fee5f45a12e22929abcfcf99cd379136412ca8d0e23379bd943f8f86c7a5de5995d03e1f1e1b2eb7d727d6fe137a8515cc397df20906bef627a13774a7d31117136f32a8f797165001156bc47aa9512027dc4c234785f3e5b097010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x50d64d4fbc0b9425d90fa1f4f2ebf0a25d75c26931c8446013ec14cd88e310e4adeafdd5a3802ef579c9e38246c8e788ee640b41936e906252c831abbe07a50e	1620332587000000	1620937387000000	1684009387000000	1778617387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	150
\\x62a1d2654eabd12a328f16e2c78982361f6b68d1a000f19eea3f349c9f34f850b59f392d3b8f5b8421b6a05acc14e0d66b48c925f9f5b4b243d34455210c707c	\\x00800003b576984a5e1868776b848aa45336d386ecbe84d332b18329d111d9fccde770b057f76da6fbee63e3d7dd755ef7fb3b1feb654c56d7b8a31e7cb7713e09244b54facffb8a50e68bbc926d1da43882e555076d90ba0344dad332599ad38b83f03f5dc81e4cd4a78654d47cd7fb417d41854a1e646417e3d16f4d9b25aac3bea1b7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa9cf6d380a9fa0d09fb8fcd3fae07e8a6186c9a0ac6975712058a77c340ce85dc41be670d970d32832c67383e03637f4ee4eaee9024bf9e2f20abc67ed2cea0b	1628795587000000	1629400387000000	1692472387000000	1787080387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	151
\\x6a617312ba30ba53e963e31e57c80583dec96e639c3f11f7f9ca4961587f951c703ebaa84b88613707b26e2f9d1b67a41b7e26c90306babe391ac6f80540a213	\\x00800003c4aa7aafb6fb8d45f7645c3fabf50c989592d2c11a86a2274924b59a3ae499c3c7ed0bb1fec845fda6497703d628a12c8d8202a9bd6912ea92d713f904b9c2d4c3b486746f0e98dc9113141460341d96e9509c3198c3595058c425ede6a5c27edb45bad4d904479853ab86862638d96ce242316f82b0d90432ed54c8601e219f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x20a678c09b52abc55c663e4074f6b98c160c8247ebef0378d18e445403057bc825849c5a90221e1ed2ab78fa8d61f50b94b85d867177c75b69fc9811fac7f50b	1628795587000000	1629400387000000	1692472387000000	1787080387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	152
\\x6df597260f798aa7d0378e514159d6e96df6027adc068710105c3ab29da0ce606f6eb9abe516f791b96c31139d7eb8962953f3b92e1bbc0664e02e18601c41b5	\\x00800003a4739a289e98bf6e84f0ccc448984249f2833b7a9ef6bd403d5c3fa49ceca2d8467f952e1628beac16b13b616d8e2e978b5056e1c65c1b2f5b1a67731696ad6e0aa8bad2be2b6aede840de1b5c9eb0a1ba6892847ef53ddcf6ac3a33c03ffd8fc5d88ba7e27c6f4857c3c411880225b573816c2cab3847e1affbaa276629caef010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x020e004d1b76aa6af1e8d1c849f0fc3fb5bfa8db17dfeb505f4a9b8cec990b2902a7fdd0157fef085319376c4fcbccaaf9e13438b0e6d2441d68c18623ecb50a	1617310087000000	1617914887000000	1680986887000000	1775594887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	153
\\x6f111c2bf42cd21b441b579d415b41c1706657213c3b8e01a00097c2c2c96b7b4ae6575cfd28eadf6e397f125830dc2b356a50f0dcf5cfc1cac585c98c337518	\\x00800003c11e39e61f61ab02e6d416efea1469473d096c50db17c51174ee93fb789a9517ffa870387c9d239c75784b60d022263c4c976930c11c380bc0a4f5751019f35b157130c90551595c43c84830a594c44b2df88b185f5119246f44eae50a3d27c02d15554e9cd6cd997dbf8289ad24746cfe28e3b667106c2b6d47514071ce01e3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb3207053c62d5a122d1d361c6e8fe5c72b57b16a47060df4a8c722dfa8cc55d7990e8afac188d24f9d228140e3ed97d8edd07925d9c4780106587543a4d53c03	1637863087000000	1638467887000000	1701539887000000	1796147887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	154
\\x7069a935e2ab96495210811d9533e53edfc6c8be9ddfa0f29689a80536731a846dc7d04696af5361537bb4777267218a90a57293819b4546537405b01540510d	\\x00800003be69c57123cf695b375b04834bb79033eec62bf225b54290e66b5a1629aef352338835827a8685b03a2684f158f6a7039c21421017bee0a6cc5b958a68138cb1db3247132c01f1de4b552def748527928f84ce0c6847a4ac8c87a416e3866c550e325d8ef418407bbb1efb0f45d87580babcec3496df0cd8d84c21589d9c0161010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x69029f0415cdb6f1efd02d769869afc19b560ec51cb50d6923e27091990d41e571bfdb82d014ebc7a18a9386e613e43ca2084c568769f56e9c3e8a21dbd03005	1627586587000000	1628191387000000	1691263387000000	1785871387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	155
\\x71e1d2bbb8615eafde7035f3569f8b9e440daf745cfada0cd28abe78f9b86c1e0c46d1b5c22af192f9cb10d9e8b13349b10bcccf9f848c6dd3f342ea74f2d6a3	\\x00800003bd893699ef4df413f36385902a9cccb3529a9325c23b276be7a9a1c17518e8234e3cbf519fe2c1fe67d74570d79d3334a068977ef50a7b3570bd17cd66035372d2300d6bd7c480a7dcedfc0fb16c2ecc8801783c7259909d407676aac4fb8b948339ab8e4006aef1d66bce889ab263fa1e883e2b6b310348ff6386918aeb52c7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x852e2efce6267bb57c63c312b0b87f76c61afa92e88c1fab745f955e5517328276662ef3863bfd613f5a15071716f93d1c762f932e0c5645aa32bbbc8f5cdb0b	1610660587000000	1611265387000000	1674337387000000	1768945387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	156
\\x7425c401a22ac4507917c4567643b9342651dea7a573ce4210cc3b9a148d8a0d5d1684c1d5fd04a493df6ba118467d30f3c8d5bc2f3982f6c71516a6dd98f90f	\\x00800003c8bf5c1ed9e3d502422a1b3868b12ffadd4c94b822ad6a66bcb197300f8ac463a7d853a2610317dfcc166297e0e5561f7bbff44207fb58333f2229434f252614bcf1c8abc0f7845098e87a5401a20199ae6de060d257059475be48caabc821f43edb99c57969e3e9188ff948f49665527c689664bdb76ea84daca62b9fc9d273010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6060c3cda46cc6f5d2dc012c4741655a4507fc61ac39dd2a497dfffb30c0824d92c0a85441cbd3143ff88dea7951d6fa2207c92ee8b41b40428be04ffc604005	1622750587000000	1623355387000000	1686427387000000	1781035387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x774d529b494fd10d67d1ad615a3b9828103119ea0e8e77a00cb1b6d92270d6b85d62fc9015963005696c9d7e21b778a52dec6d2c2690bbf50d9838284c1f2866	\\x00800003b8c931fc23110347bfce904060e9e3909771115000b8f85f337bfa4e00676950f4fbf7f79d7594280536e8a6db715b5a012300f664612e656b0f41220b8d2e022e5bc21fe7c121d20c2d493aa9cd9fb900c3d4c65515db916c283f61501a069def58ae7700179a5140c826f4eb9dd33590c0b22f4d91217657f5188ae8881aa5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4318c95073c6764210aee476491f27816839509f1c17785542cbf76ab5af70dc28aa8a28131f6b738ee80714a171852f857d7668ee34e4afe94b60f2b2277e09	1630004587000000	1630609387000000	1693681387000000	1788289387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	158
\\x7979afdeb115ba26188f60d119a0c226492ee1c27a18a2f2596eb33726b352c73770bfa1a9337718091da03505787c7c34d56f7ebb289fc8d16e18e3f2b089b4	\\x00800003bf4600d9c616f3533de25058bcb7a2dab90fc5b6ac2a127473d0c6df452d21d89f62123b6b901f4b08c11618538d18c133f0a2e5f8df399fad448ac5739935c7b9cc597ba5826758b2f2ced62b36cea6c73ef0b500cde55f9d3199fccae0ab7a09f43131fe52e2afb066ec0e2c49ed31fa62390814774b7a4579f6e85806edf5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd5114847b0ab2fe062cb3f6890d9d5c7ac6050b99ed838a48da87dcb7a76884278f593a2e216a6e723e5a215ef097d6ea567822eecb007d49dfe588720d6730a	1615496587000000	1616101387000000	1679173387000000	1773781387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	159
\\x7b1df95e082da24e8034203903564e07e1b57fe31dbae203ea3cb89fb042976478322851bc7802864d1dcac7ec8901785ef9d562f81e43d3527c27bffccd151d	\\x00800003da8f5e876b4fb868392b7c87152df4c7a2e660cea056f7088e51a75fee3b6cbc0e5c57961620e6c7ea7d550063196b819674d750f57f8b58207f37d7491d0ccabf8f74c7281f21359fa11ac720c0d47296b1d9e8d7e9fa21e3f908e77b9787bc34ab14505c1bc563e8d98948832f3860ed73e13fb017a39d5f0aa7643a3a65ed010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6a6ac92e793412d76de3718eacd303691a5c6eaf36cb171596ddcce8b5d610a5e70991fd4c55c3b3fb9c92abb8f0ae9223fb7e854ee53ce9ef4c0a95763fae0d	1639676587000000	1640281387000000	1703353387000000	1797961387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	160
\\x7fd16cf92e07cb80e00e99eacb2eada3947de252fe5337305f281d9cc9e7f804763e7c1d7e6acb3c099cb2432d77f5c1e9a9fca2689bbfe1934f075599dd9e17	\\x00800003b2a77956bf37ebf60be67f99c4ab8bfe6bfa7546e13ae2e1ca8549eea73ae57181e6308ae627222f09be209984dd7c8d90934f1a83672c5250d7c7e54662d8cb6dee4dcd386e94ae96d49644434a9ced694b2c42a56d6d3c1af67689a56172606067b472ff04f5983ece835ccd6d902b02a161ab88dbb1b52831ebbd9842c9db010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3077c54d5f59bfebbd256e9013ed6c3c6017a8fb835dcfd40125b369b932a6375fcb4a49daf78940f804e720229c8ccea39d3d0851e8de4bba5f0340274a6e0a	1630609087000000	1631213887000000	1694285887000000	1788893887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	161
\\x8075d54101bad5dd58d1fa0f6730e4cbe2bea79b9088efa980c6315db8130daf047f8beae1b4ee753493868b482cd3c26deaebe8eae8db32fdd02bf289177929	\\x00800003dc06dd30af0173484e94bac1143fd41713963dc5ca695c8b6b91fa367bfdcaf1d06f9c67452be7bd3ee06560142a88fcb704bbf916a56c87035305f3dd04cc2be6cf70a7a295bb30365433fa69bcf59b3c653ac8571df9955c5369bd71d72d8fc9c7ff646ec8f2e8c728feb347440d244cf51905a8c3de3e82067a71839eb641010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x333475257f4681078834301dd13acabd10ffc93d4f1fcc6c3bb82d83c68c024561ed360090576211e3ca6ce956a7263172ff44bf6b20d994bbb5d11678b72203	1613683087000000	1614287887000000	1677359887000000	1771967887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x822586eb59bcf7034cd6734847aff17dfd169fe946e95851ca97f7e1db8c1115a2d02dd99671aa7649bd6cf350cae2cee6bc839392bd0c3d99a317588370b755	\\x00800003c9463aa51d90b29425ef509200ceba1bc64975444e6bf3f4a71a96caec102752626da2b4034071fb53ea8a5198ed91089be4e0ac142377c5418b163c2280950ae106a90a8eee70520b89b87bc8ed564c88069773714fc5946aa26504c1d7f5f3d68cd730886979faa15bb838d91f37d2471742cb5f3ccd78bc66449af70a907f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x291939d079ad59a804183e4c5ce5fa5c4b79c01d952caaa888405990be2ae0355c0b6127060ba43120d3edf54e1dd9a15c6005377ff0371ae1c6f3c113628b05	1623959587000000	1624564387000000	1687636387000000	1782244387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	163
\\x8341ac867cb38e2e97fc7dae5b25aac4eb265cc603c0d4e34a954bfc9893897ebbc66b29dbc3f2bde3022b6d31d305c856bb9c854d3b4442606cf491f2975298	\\x00800003af3bc32947aa9144e867d808d04e5fb41165f7272105455c4d1fc73f1db1f017085296615f9525e97c95b100a103568dea4343d69aa752267572eac6c575ca98099071377a7ebe69c1167b44d848f0a6d63a589cbbaeb74fda4d47d54921fe416ad828c1088db170d648dffef1d917928c7e66a91880275b9e402a5464669b9d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x93aeb3a1e740dea5fd7034d91b7f2d4c7128747df574e4abf7d5f54b6e3ad567843c7eb71564a72d2982e64cbb3b37e8327ee80c8600e04b5d3b69898024ec0e	1619728087000000	1620332887000000	1683404887000000	1778012887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	164
\\x85a17446af39e40a2cbaed3a389c10f37e1d0aaec9e61fabccc4b90ca91636b4b779ac210b25346346258a8afd95c8235239071b217615a324e454517a0d5be4	\\x00800003fa015874242ade46e2ca8297c3f357550c45fb4973c306813aff6302e743c1335e2e2d9c696b3e2cf75054c69104b8e578792add930cb2081188dd805a42e4d494f8ed7847c41802bae4fc6c36188304d44df95f56398d2dac837b1e12647af2af9b687674c69c3a117ae701077bf82d0340bdbf84b476fa1faf455c7c4fb183010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7ec76203524339db28a8bc85450c282109a4e0a874ec37f3556d93eed32ca4b7108fb1133308d1ee4b880044de284de9b88ecf467af0bccb179f3f1f66f9530a	1623355087000000	1623959887000000	1687031887000000	1781639887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	165
\\x863d51b23d6134b3087bce2cfe3408a20f88d891ca86249fd7172601c1581c1848f9f7536abf4d628bdd1b6210b562a4dec4349510ce0fa950618a37af0fd402	\\x00800003f40504e27245194e78a8a1d4eb37ddfec7f2d8afba40219226ff56bb4b9f477b96323d500a049143c5c3329e2f039347c6cb06d2c112bd8ebda9a3f0e9d89043cf80985605a1a911e0a8b5307eb9c669b270f174c02e6f2233af567c63cd1df19f6a9bd4062413757db80d124f897d6ed51c9e1423e57de8845f17b6b481f569010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9b2df13d03adcf4cc5fddf8fb6578243367502b7c3d3341d24955ce21258439183704e09130424ebbedb1e1c018dc1f290d44adb4a88e22f1a54ff06278e1a07	1632422587000000	1633027387000000	1696099387000000	1790707387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	166
\\x8a55a344eda33e07e76de911ba8c67a0fc717ec746c3f8ac72f5a6cfb3d3969daf0e73bcd00ce01581645c9428b30d39a98e7a6a94d7b7d425a7167c1aa32357	\\x00800003b8a5bd9b9a53f26f69e4fbca19a7a701f3aab23ea708a88c70e5fd980647772f930a3139b2ef093464812a77fce62b34b1306c85de412cd861108ae2e7f3695d182e1fed573c660fccfcaa51dd0824148a73cc36eb18b03e4f56782a5aeb3fe298537c342d9ed27b157c1e547c610491883ea40d540601dee2ab9fb30a23fa73010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x175d4a3d31766e03ca04ed240ba02e479906a9a210c75c2527a603511f6e5ab90db05fe1f99fd97f8c2decd62aac1d25557db807991c9dbae24103ef69de4b0f	1639072087000000	1639676887000000	1702748887000000	1797356887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	167
\\x8bf1f1cb3403a1fcf4c9c92bfea0ae9505846f748e425b1eba53644c04276a3aa365d5bb67ed997ae3ab85478ed606e588baf2deea3ff36cf2d3ace7a0960fc7	\\x00800003dfdd7f04afacab3fa6b5aa7138433224e99f10fa1f48adf145bff393877004d215431403c451e1d4291364f9da2b40e0ae453c0dec72ed049c9d77a9a9731d48e18fe397ece2f4ecf277533cbd094771e98a4dea25bfcdfc97d5cae1d0a6e1cd3f09cea267054f17301c5e592d2ec204860156b52acfdbf9439ef50a3cf1137b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x38550953f95b8b6fef1281fa3562d83897100350fa78a17fee5f6a1ec053ba46d6b73b53cb7a874a43eebb2b1b81db45d48c81e8b7d35bfe902ded168faa7c00	1620937087000000	1621541887000000	1684613887000000	1779221887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	168
\\x8e7d7a7a3ec827131d1682a14d299b6e0af570d33842b6e3884e0ac68db15fe1002c33df362c6b126b26cd2c4c570986e6bc279cf28aca89e10762fd75b29015	\\x00800003f820be179d705a94b0a77c3156f3519a3f4a9020214eb1ed1a626576a4231f9d97ab9f17c66b4c1c62fc42bb4d55da6ca98466aa07734c0bdb480258144735fa245c533914cd7327f7db0ddfa0b5d383f66fec55f4509606ec35bdd1b38a8962a895854a2eef2552119c3061435e47d6a5d5a6a5f2856292369b19d37816dbdb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xfd1a85b6df2ac24d531f2661a83e4fdd89063571690b8e74dca9f78f3077b1b38a53fc43793c194af08bb5341c4055ec0f306410fb2aeba0c5cf54aa71a6370a	1633631587000000	1634236387000000	1697308387000000	1791916387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	169
\\x93ad9de8a46c84a2cca4881eb0d4905bcfd737ec1ae6ba645a38aa649341869ba3f314212d34b966134f30a6807f5e81cae15ad0efe6f4f7e79559f70c627f5f	\\x00800003a1a4ea2ef9acf6f8baf47aff6346a03479c983168d5f00498e483dfe50a97b1bed9ac81ef9695384e4c8d41308c3ba809ec89f4a015795c3c179aeaa49c4fc01989cc6195c983aba5224f0b1ca4323aedd80827f8a3ee91534cfb4b6ff1b4c9b1115ab89a4812226703acdcdd95af272227457bad5407512a472c5731fdf8a4d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6b20074ef0539c5858a178ede890e2ce2f9160f4145ce8ca9e6a9f1627bd8135d33e867fd8e9dcf94f09e5e825e57b90d34a028291195a2a365632a6cb51ae0f	1611869587000000	1612474387000000	1675546387000000	1770154387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	170
\\x98c98072cdc81bd70c269de6ccde2358a7e1974816c62b43f5b3e2381f33ed00a7a6f1488f9f5a1310d7287479b4ca1a4978fff3131520954d6b5ebee871c201	\\x00800003c7b8dbd8d8ae8c39d5cdb064e28cb11dc00f514f7b50f0d067a947daa3a320cd283333929ac990318cf49526b7300b5da43757b3d7e13cca326b2c9c567d0b98332cc11c33d2ffb4ae75819bbf699f00deb2e1b9f6b4f18b44408e6dc67b9cbf1cc0f847548dbf189bd445f87bb9ee978b9546e67626a8dd54e31e24837ed0cd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x52123007ef12f89013bfa4ddd26f83d546fe3ebc0695320a5484a9047bf5a109aa26786a53f14105f4d771699d8c16dbdaf2b692700c19305f1dee8d97d7b508	1629400087000000	1630004887000000	1693076887000000	1787684887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	171
\\x99014dd210a109acadf3d174a66f9e45941e071dcd471ca00fde83f859a16aff32396747924a5d8ec36fad79281061b0bc1b88c691a6e6743ed83034785762b8	\\x00800003cdadf617678719ff37b30883de4dc6a495662a3e5d1153d82c21234504313998f0ebba065b229e3590f4edd8a5964d3a3e7ca87336d419450ad29dd23ff0756e09058461685945fc8bdf3ee83c37fe80c46f104a4889be8d4920a92007281ceb8f6aea9580feaa1f9795006afc343e0f16f25c241c86f6cb63e9fe78044eb5ab010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xea7b60f18333a112c73fd73a375ccac91ad3b32e9329bfe96f31979c6926072aabe5dc3740b78495ff34df591306370ce847d56418b9fe98743c87d8df912f0e	1622750587000000	1623355387000000	1686427387000000	1781035387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	172
\\x9ac1906a866d1dbbb7279e2a6057e72b44e611d66d6a68e1f29007e2ac47d914f70c3dfc0379bf7b7bbf20711c75e4ae06e97e47a77f2a036cffe4a6bc2ed3cc	\\x00800003da39357c195118f4bdbec78cbeec939261b702cbf4bda210924c57a5da7ed561b38d2d5a9447d3aedb72594c85cb128d142a7db5ef0ad56d0c46b2b21d711c32bbebd4f3ed2d10008db40b28c1b4f2d4148e41c6572dea26b93d13a79215dc084b7a219c0745f61b3e22c4eb3dc4c6477a4d7404e1985763d2d9430d61dde287010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb3ecff27a257bbb9c162d03e745f8b5a22bce1afe0365e88dc136b7b98fb14b55aca21c06ef571ad6797fce7198d9ecd3b7ef8d6abd5e8b460b96dd5e011ce07	1616101087000000	1616705887000000	1679777887000000	1774385887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	173
\\x9b55b05ff1e55f33e07bb963a9c59114000d2aca2531fbcdbf7411bc1ff20b6cacd14fa33bba4b4c4ff6f36d364d90eb664bcf08285c8010954de2ddccba0edb	\\x00800003cde2cfce10bda41fdb2435bf242db2052521d3e13184d9ce647c62bf7a5babf5272a09b86624ac764c36a53082f634d3b2371edbb3d5b279c1dd3ba7ecc0e1312b11880abcd5d1962b462209a66b32519490de99f7478e915751555b4d69fbec7df5a37f15a678829c5374f6838cfe61fe19c12ec256bc3d4de585e811e19d57010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xfe3cbd973557db145e6de2b4476531ff34f004e02c41a26bb08b9d849e0d36cd72e1518ca5ae08a71c6df831123045f4d43c28526816f652d39ca7f8f09a2b03	1619123587000000	1619728387000000	1682800387000000	1777408387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	174
\\x9e55c0aa50f3ffb2b7c02cb947d87716f62c64a3968040637fb9af4a05540d33e24ca37075243e60f19ca20201710f3cb27f1c4ad8245ea3185a98058113690f	\\x00800003d5b2596f130324ccb9311f0ee14d17f718a80fe5610d1a1e5f8b051888e6db5c8013079ab1025761473f3980e225b2e39058522f1fc49a2c71d6a6fc3d5a3849d236ccb5aab708892d38a060e0b721d659795b9765c2840deff15fa1a7c92026b6fb4d580837cc891d1b2d03b6dd00368ea4aae579acc8a3c11385aabf62dc45010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb2cdd8787cf9272e1dbe13d4b36c2515210d29e94b42026eeccf74ad0da4606587dfe1a17c10fe91e1ce8e6678fa35dc49515ae52913b37d3d928e9d2035d40b	1636654087000000	1637258887000000	1700330887000000	1794938887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	175
\\xa0c9b6cdec0a13492ac6c457f4e767e5ff7678c72d20dd3057b2f7bed16f65017bcd38ec05ccd767d0bd2e9ad8dca5f38c81a196b6aa0b6ff20105be7553419a	\\x00800003ed880f89220b8616e630c2a7ab66b3a4dc849c375a7dda4594379be5ecbfef8775081c711c9bbd2cf0b2bc7492b0aec86a28c563acd2c97521bdc7cdb4a658cc22bc4b5f3b891ef473d34e25ab70dbceab5e171f111e6980d9c8a636a8d35c81541b9a78935fbae7443325591dc5b9a533e1f7509d542009c3b02507d2e07f97010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xddca19f75a16fc5793c9d0d3f623da4fceac7610983304068018e79af4824e79146e86b623527b4f217f5d55b3f230bc692b410fe8572bceb98e0aead36af007	1617914587000000	1618519387000000	1681591387000000	1776199387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	176
\\xa11192d3e8e05aa7da01bafc2876110b8f9783d7422c3f785b18250d50e6503443425278bc0890baf48f0c098230c0e72a6fbb886dfbb71e634beb670d9cd158	\\x00800003c37cf751e7069c806f8636056101192da31927655201c6950a3dfd09c29d68b8305653ccf419a8c7f5dfe69156424710bd26031e2bd12f500c8eb9d6b4c437aa10336bc5d3f2240cd8d8e37bd8cb9624181367e8dbdaa0e018005a752bdb7f15f8f162ba1138b994a7157f5e86452335d4e92fcce886b0b3e34f00901830822b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcca9a74c9fe172d844133ff632575dd57c0df92ca02d07f697cd4c8e48c08a85208b062e86a7e999c6082637185c0ffb80e7c91811fa3b147f93bfc645ada301	1618519087000000	1619123887000000	1682195887000000	1776803887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	177
\\xa21135b984e09661827db18265e27156ec38107c721f3ed7d453b40b42b41dab1b3d399d5095adc29c4a6822785c4f588697fd1885584aa09dd6234598ae362b	\\x00800003ea7e1a3d6c9396ae68ad892c4258346e77adfb16d9825e7893d648786bda834974bc68e08344b63f0ee3c8823c95cfe2040b6c44fc2294dbffa5f0f68cd60e0612dc8b43e783a7bf74e98f2372b38fe94987e048759ca477d2b93bb0782b5b84d64118802d7ae42d4b55d9e6470042125e4f93909ea760d9980fa7b4aa9dda49010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xea0bf5c85edeaaa7e059374850d91861f95f306770038285f7177bb124698e3c66f4fad4af83606cbb532d6908326e8ef50b46632109a4b7c7e55cfb8da67d0a	1636654087000000	1637258887000000	1700330887000000	1794938887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xa309e596cca78046c1c45728315d1b138424334b9611811f6d264e31fd269e4729ca88fc11ff32711e5eb102b441e7cea3d4ec4d2663e13a7952d2966726337a	\\x00800003c45e4ca34aacc68904b97b6cce5c3389e68f103c999c34619ba972fc99b492f99850e5bf2343abec2ccfd8c9498c17e1c750992cf3e643d315c251d5f55777eb26a3484908f61e3995f5c8d11f30b2aa779730d96c3ad98c935b728cdab1788d8557a7015f8f829b1655b5619e83ec5ba938a8ec20fbed65a83aafc0a7b85aff010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa48713a993f729125f35b52b3097b1608af0847e08b5c484f48bdfc2f670b10a5ca59c793f677d3ec5f19a2dd276a95bc0cf7b423cc5ff6c444b685f20190109	1625168587000000	1625773387000000	1688845387000000	1783453387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	179
\\xa77d38202ec21b65e2690152dd3047ecb216802650a4a60a287e44c3890ee0464ebacb132f9ac310088f5a7cbaef8a08021b003e61953c54f1e620977ad81467	\\x00800003c3b8060a814aa90c35d62a8a7f9ea2a0e6494f344a6afd187667802dec5f0531a2aaa93860c29772f802db7855410e39f42c268dd9bb9c8e266fbe8266bf7251e95aafc3bf16bec0f194f6178249b7307129b4747033d913c5eaba3b20c8ada220fbdf3ab23a0967fdaf4fb6c86a1b3a0eee369e2d7f64f2f98b3217b19bfa51010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x880a36ee7bd2177d20ccc2e1302d1a5caf823e15d60a8d469a35731d2cc0c09a256b2e1be3a0d50f542b1f63c0792713f8997143870d92bb8109b20e13950105	1610660587000000	1611265387000000	1674337387000000	1768945387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	180
\\xab993ca3c51758943ccba29d91c0b3150e95bc3947f7160c14d74a3117b6bbf982627933c51738761dfd67e25f7dd7f2d56761106801d5ae2f3e37063a1bf523	\\x00800003d802d0f7c8519f79261c0a3d1fe52e17cfe58f284120f19ad415ac6ddfd2acce61e46fd5787afceea3c49cc3649aa13789563935085be3b4b344dc8a2aef26c07dbb601bb78554a259939ac90923fd19f6150371503cd916e1768f0ab59a4a0373d5c04b10abc087f80839bad6e638639016c10481ea3afc62102d071f66fbbd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4a7729fb055a50c8ed6f0f9f203ecc4a8488c11d1e411b8f36a4924255042720abc6cb2ae4641cb4530c2a9e929ec7fc716a6ae325faa30220d7e6cafe970a0c	1638467587000000	1639072387000000	1702144387000000	1796752387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	181
\\xac15d53ddeea8c09fc182327f0fea13dd755c6d977d9836eaa2c62d143f2cd298daef9a0ea324c2eaa65997130ffcd0aa8184ec9dc5b497e712559ca276b25d2	\\x00800003e8dbd6d1d32496b827b31b3e9aba30c8a6471c523511c803c7b226d8427b77764d3a265b3719f899ea1f0b7602349b0c61445a1f9478b5128dc9ec9cd12c5454de94e7ceda13a7cb7670ed6b6d10c644c4afdaa941a081b154eb5f9d038e0f739605680b7515162953c319c2a5c06f20e07359271745f169667b7b4fafb63215010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x51cec7361b40729f1d1795bc61f5e93e376321de932050a501bebcc542fad850e39d3055768faf9f61dc3f89d0699555a80f163a25c4c187cacaf03ea5979704	1636654087000000	1637258887000000	1700330887000000	1794938887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	182
\\xad55fec6f4c2b506558ea387b3583c6e45e3fc8191063583f4ea47f5380bee08ba86309d752219d81a34438ee4b27ca11dcbf17a3774b403cfc8297369d919d0	\\x00800003c8d3860aa662a88e9e7f0e8fb7285d78122bf0dfaecba6eef257de2788ba76954f23610fbb971de8260e49d9aec4f5ae6c6208112921f5e4fa1d8975ef91b32bd8b581c2bc96eace7b78263c66fe071d6081b3d3e79db3580726b5eec4b1a22febb38e376ee8c62cbab681fd05232b09d14439621718e6679b8b49ea8dbefea7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1c27ffed45eb3eea78c89453f9313b41f4febfeb973949f12f5da056daf4e5cde5f2c9ffa8e73f89eaea355076ce212135a648d0f8f71079354e20e29629c50b	1634236087000000	1634840887000000	1697912887000000	1792520887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	183
\\xafc9c0b99c89af5c530256b47d0c2c4ee37801a3d220dfa02c1fa51bc16b8050e706656d3ab99badcf715e727e5d8feab1df76ba2d532cdd7d84599b44aca621	\\x00800003bfc084e9a52012a97802690511ee785757292694ff68510c16206f9ced4e936471dae1dd7588e39abcde7c78f66a3a9c950eef7f623a9f669a255502ecded223ae356d9d5673621d8d4996efdfc1e9d6dded4ccff8ec196e53dbaa5502388ad3f0b5330ca64f49647c2d73a5d92baa25557005aff3e6c16ab80ea8475a92cbdd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe56048de71d07a9b13f86d9994e9bddc04a1ffd717ae613a2cd172c79258560389fdceb2ff482c1099d3162a87aee2a8789129b11025b36db8dc29c81a12ee02	1639676587000000	1640281387000000	1703353387000000	1797961387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	184
\\xb305df2897c31f2a0b4d04f1209162c5e470cf73b4bf5cd58bdc6c83aa3cfb0e82565aed2e483ce7c2bf1823ffe3b1f7af547b1721900c1e4233d042aba93b7f	\\x00800003de41f12bf7018862b17bf6d2e1be9b05f369308033edf540bb07f8acd39c78c003619d22538dade1824eb7fa982e0c3c64c49354fd65708e675689f163aba0c26d1d929e0d5103107223abd2aba7e21a239a706b7de97e62e5963002d88e6eb5b3dcdd561f8489ed32b3bbd152564a018f793a5e22c9250e2de29398416dddc3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdef95f15ac8fa138f04be4f07374b2231f3c79554c470951e8d0a7efd25013fb654670217c635ea5ef64eca25fb0e0ee028a05a5f301649b89cf19dabf5f1607	1637863087000000	1638467887000000	1701539887000000	1796147887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	185
\\xb559c32b1e114ddb6b863cbe7191ea8fbb4984ea7cb94d5340e27b07733f2a6344692524a303f362d248ff0a722996c430a8351e5f43a54dd34e9fdd9767351a	\\x00800003ae59a9dcf9278a89a971878c140a879b6c07cef842ca1deac4543300b8853a42110a6870ce09b92f468854f34a17133c9eaedc2e0160abb888281aa385ca005c448840476373c98509721171db47d88422bf8bd23a3bc86f6bc5522afa26c6624f49b0b36d39a732ca3c14a2f8abf8134dd2fe32c3a789d8728d1b9bf006aabf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5328f718134e180171cde0cb167209b2a9961783ab67ce671c096d940d9902f319dbb99c7a1685be8b04ea62fabaa759108b95643753f55b9c540300fbb55c01	1637863087000000	1638467887000000	1701539887000000	1796147887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	186
\\xb5b1548086a7387fb82e596d9b0dd84a029ce8c9481c3f802465e7ee1d32cd74e68935e9141206a1832f11d90c9066d35400255278e164e595718a85a823a991	\\x00800003c4b95708ed1bffcf23454a72509c65770391359df7349135ac0f7cc122eff2c669a8ac94b8fa68fa001367212f4d1e519c32a011d6a2e30901faf6d901c3c02c0143ec833ff54ec4a7e9081cbd1fc452553175f4965310b95704362ee58d5bd293c7350373fc04a46faf8f5d70d1d0d9aec716ed700a43f44c083434a4dbdd23010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x204831138536c526112ecb3ba548a0fcdc9d231569d7df45f82d1df6c69e0dad79f3fde3d7222cea70de83416e4596df64e40c2aec59c22ae1b3a3633b5d630b	1634840587000000	1635445387000000	1698517387000000	1793125387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	187
\\xb5bd1c74b2f7c6d8358f176d2cc1ee73c17729827b141f7a43fe1c5a48d93667cebbac3755314ef456b96bfa2dcde3a02ea97b79cb2b72e6582c054165e953d3	\\x00800003b31dfd4bb896163d4d39d6076aff336e4911d3bdd33ece01c27f9d1ff2104994b425c32b26f679956763f22922696ed9a92b353a7276afa0dfa2cf0f6c72fd8355b379a17f3bac929aaaefebc1c8eef52d57d61d83a124c8b56e590cc5f0f2a2998dc6d5557a5740b79c628f2681cedbf9252e04ed236840e206de77508bbca9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1ca23dd1b3952ef3831911c31b2e3efb058da78adbe23cabef1a666c6397d273841e48f028ccec4895e13eb4d8ab07a1fe74c6f6560cf1952a23671c49b02a01	1632422587000000	1633027387000000	1696099387000000	1790707387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	188
\\xb6495587d6ced77b54472b526148d85dd8557fac52165f66974397a36da63322f928813d42305aa86892d90b6659e7741efe2ff0cf2ac7f930a35c45eba6a884	\\x00800003c3e9d3f46876718e856ef88d59e5716937ae5df6392af4ff1a6726acaa3327a301c2261ee21b2e16c71353c9a95fa260f88dd7242927ff4f4e237553576a7850ca93e507ae0c3949a670e06e2f8129b6a114a08f6301f11bec900af9a1016b19475d238ad34b9fe28393c216a6bdec426c0e7dc8b3cb9b8fc361e9a08405039f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa2434427fe020025a170b75dcc706fb6c6e71894f6c8e1174a3020c0360eb71b0b1207a48430b0ae4a6a831c6ac9b5cf4b0d8566d2502214287f4977d234320b	1611265087000000	1611869887000000	1674941887000000	1769549887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	189
\\xb711fbe49c7e91bb3af74dca593d0ab39285c232512e76d332265eee83d5a7c50044374aca052f6202f4da174a88ceac47dfca33f4d5cd256fcddcc29cd2d94b	\\x00800003a08bec7e8eae1c8df8f79faf06476961047e24810c4fb5b2563c89dc3d8471926e7f6242c4475a4407e8591ebd625b24d81fd4d1e83ed1222af3b909cccd463bfc1be900504362c8a9fe55151aef01756f55c354f8d78219633c4595135f59c80c23ee0c5cc13852fb8b5b7eac801de1b0e6b2d30bd66d607e4a5136d347ba81010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbc68db8478afb3566a0ba60869a80d652f65daabbee30dc3139cc75fd1bca884aff752edf034e8fb05acd0b376577fc97ff8ba5042d1543f4a7a3e2d4d5cec0b	1614892087000000	1615496887000000	1678568887000000	1773176887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	190
\\xbbc90a0b9f1861b0da55f333158bb3fbe691d861de4af111b8d7985e9bd2d7ef9ff02d1972eedfc754ac9d7479b88735cc34e78cf518354f7ec6d126f27e43c7	\\x00800003d096bfb91ccd7dc16a65ed04fc72362b659b2b29e2124918e8e62ee72e5dc4753865f50f5bdcf4215f7c631bc411f17b9858ca23da1630fc4885dad1d62397d61cf66d18aaa786ebb13b81a1f1be79fa4141fc6585c87c4cca3c8ad42d2ec9c38ee7a26f43f2328c6f2cb4d53da833f2d4db8371525a9a7acbfe12fabbe7a469010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd84e690001f29f8f0b08a11f90b7dad9b0bd5bc2fe73f4f16ae4e16cda8cd1ed2c46fb70aefa3cdc153c8c9958002acc79e78192cb9f63193f64334644b13e0f	1630609087000000	1631213887000000	1694285887000000	1788893887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	191
\\xbe7d05145fb2fb9ba6c981f5e5ca6391d5cba71d9735e2a786be4a5ee3432fc62cf28f09da04ecad899965e4ad6a34250a20bc3fbae4e899f14ddc1b49f5f62f	\\x00800003cc2a1bbf007ef9b3c008d787718dcc54641de7da5d486a944a5a480d3b83d5e971c875abe545bf26466eba81040bb2030667f8505346d73355f92a3b533578c3bdd10853d0cda662a51c4cc726fd1f99f7bd10f1edd2d983666bdee41eaf4045a1d9f3116daab0ce525232482c2d2b0f2f37f7f2684e6629338b5bc17393f36d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9c88d78f4da55fdb523884e54420c4175d4337b8773a16270bcd679f7612a49b7ca60b83be77ac4b8e122720108ae95eb3f0188e11a409929d06b0ab458be205	1624564087000000	1625168887000000	1688240887000000	1782848887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xc225fb9ef622b21c8136208b17f7af7a10414b7da502a99971eaf158a7c429e8f36b13e27a8adce11b8c5a849cc56e1868cbbdbedf8b0e5c1a6835aadb5429fd	\\x00800003a9b521eafdc4a5ba2e31239e9a1df130be66e1f5ef49209e331de7049989ee0d030f081fc2706d157e5b5d6c195ff1bbf230590376719b2bc02ced61e242680c54210bd3aab02c6c5db1bc3d0395271f17f5c5d978c38056bbc97b6d5cbd2c8bf66ac3513016d552757258652d04e580bd120d1d11bc9f249d5a10ff2af2f2bd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x158711490dc60c12554ca82119f628c6e87ab7ac88d67a653950e753e5d183479adb4b6c2b3cf3880c1506faf87192e3b144427ac3c6cd9c1594bf6badce8505	1615496587000000	1616101387000000	1679173387000000	1773781387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	193
\\xc26503d03aae521e75adb695a4d8ecdedf23fd21348555c0a138ac3b5ac9773249bdbf307d2d29e9ce64c6b7733720f14dab34d7f38df003369df443de95e68e	\\x00800003bb799f46d8ae8d8b7dca126adb8dca3769f3c2942d3d7a3e7083b999c309f8f8f21a5d004592c9740f28aebde1bed51581f8894e806f52c2f46243f4a5ae8227e59408aef4470157d66dd99c2faf126d560de65c106981b2e3339e1535566ca910abedcdce89942cac90f0b9cfe5e762253f1f7a2d1abd91bb0d440d73a13a11010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x51465a9fff47f046d37ae69455d556e605dfd69200c0cc6a0872997e5874a5833769f822f1bbd8e039301983d67e855e6b34f542de5cdeaa0272b831a2f57809	1638467587000000	1639072387000000	1702144387000000	1796752387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	194
\\xc2493615b396b72cd9cd5752c2c83464f4a57463db279a3fe4682d7af0d43d60bba07444679ac608006ddfb915ccb368389fa13ac407129373e8c0ca93fafa50	\\x00800003b3561f703796ec5d8ea67576137fb636fcda5a2e22e7b786fa1bbb1d0a4933c2ed72a695d074d9aa2588feb0031123aebb986f0a30fb9ebfba96cc0cc64b13123b41d4277aa937cba2eb2577545b039d7759077a527f052ba832a93f665e3885fb1c828ab4287846c5370fadb953c68a9f53b9a60535575632c7690d1f075d1d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x81e3bed91918f5187284a7c818a0c139d3f74065955db4b635b84fb47661d5dfee21f0b27f0913ff4820899c1bc8ebf7a34fbfdf153b326f83270af9693f940c	1632422587000000	1633027387000000	1696099387000000	1790707387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	195
\\xc511672930a7aad03707278db922ed77b5ab9bdc4eecc2ef9be3c73173efa080a4594b1a636ac33412ca4fbd017fb8a1e85a108b07599de6277069519dd42317	\\x00800003cba620e0e48e1b6d35edaa9a7c59ae3bfe7cee1b3109c5a95f2a25b751243a1300b607a3b2e00184f89b8c769e34ec62ac35a41b1dd22f121a69eb6eee2fa7b5e47a37ec4ee9b81b1bc7760900e4b2c99f243259059128ab846d36775540509042dfdc6c2270db6e15e546e234efcc0617b392d72c2bea2af9598961ee2bed25010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x09e9b74a3e83e5290e925d1951dc3d005ef7652e1086fe580731a12fa01af2c10d318b265807dca7489c70fbe0b5038a55cfc661c0aee3fd7aec7e08e86aa800	1640281087000000	1640885887000000	1703957887000000	1798565887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	196
\\xc829775a82dc67233fbab4e456f0581826e50291c0940250d44933c446782fd501405bc3f1a2f1abc35193af246ad6d5bb2c8919d553984bb1e155bcc1bc0296	\\x00800003b917c54f01fa737fef4c44528793e1c44804ba7975fc1716bb8b2c46971a3a4e29c3cf66990a823900cd9a92c8cbbb680494a2a89f352a55394ee8ff54b5c50c98d30ad4188b1569f88481bed8361be20a37d278ac1856a5eea0afd76189740584a0cfe691d56b0d5d827700b55f795058ad970e2012a95d5864dfacbd0cac25010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2e07e0518d32fe972b898debbccfdabb30db03c2c52d1f73a3b1c936534c07dd4ecec5ca4263d0fef6062338c15d1a48f1d09924e84adca135c4a77b1cd0fd0b	1638467587000000	1639072387000000	1702144387000000	1796752387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	197
\\xcc6dad6c31fb521737b6febd8325563cfc366d506e3d1bac46526f2d96333d6373c437ade6c9ef6e18ab7e94c87756c990379de43f32d4e498aec5b093058963	\\x00800003e521cd3307e208137934c75113484fe1750556f7aa43f4b2373d91a8e3525d2ff25ba2c9d90a53c73ed8b8d8b02f5857668668948c61e6c89807f24558d62d45c161b0edd0913fe44381a629bfd61230407100d22ad04f3e9db3598a8230ee64f62bd4bbd11cc1f3039cb0aba9dd5362b23b75147a4a31c4e4c8d836a6f9a2e1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x54b4fe414263d606cc53c5d185dfae253be406e177f4a7b45108c4d740f5afc0bd6011978e31e7cf50ec545119448afa931c833c7208e2188b9dc62ff016ae06	1625773087000000	1626377887000000	1689449887000000	1784057887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	198
\\xd1c94b888d439b0c0e8e19cfa05be99fd9bc8b47a61f9b55016f5e65e55dce11ca531e7e046e19c3bed0b53a1be2e27de7e5c7a603856cc93a20568fcb1c8e04	\\x00800003cc0b52a5433e968594604cdcb59df7f298e07ef9d012972c40a31106f2096d4688f1a18af1fd4670355ea7e31134a61c6655c5b299676475a6a26de3a193b430eeb9a3e65c9b1024e335944ffc568eac4be89b6f91f8293b5780f07a89975ef0fcb664e356279019898ad9e691e88307afead87c5bdecd4ff6eeb69d01670ef7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7b08520f330d3dc1e124a0a3bf0ce9bff517ab065a2fa7f0495cc6f6fec5053e64d14db03e4b2c096c84620caeea1dacf99af80804229e5e6f8befa1668cb403	1617914587000000	1618519387000000	1681591387000000	1776199387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	199
\\xd205bd7b5f8474176582664685ad3da0ba1c13c3540249f8aac4fb88406f8014502b4ae7b4ec083617cce6f638e3ccf9e1e405d252877ca1ce87c6b2f5b512c8	\\x00800003e98459eddffc9f4d57bad8cdc5eb2129b1ea782730b296fcc023d4fd8349fb349adaaa0eb3e3117c815853f9b8af5d54065fde02bcfa33a8b3d93226b6629ca964858f5bba95f25f656ed8e0ff31a61c08f886f12661c9cdb2bcceb66ef3ace34099de3ed3f4df6b01bd8ea8b7370ece219d8bf52c914a912d238ac2d815c749010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0788dd10cd379f95ef8484567e1d8e979493f04036888308c5042b967aa6b611b33adffebaf5293ab158719ca9ce261bd4d1d589303fa0312e668c5868f10b08	1631213587000000	1631818387000000	1694890387000000	1789498387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	200
\\xd515f3005711c8d53035443b3e834428c2e059f4d5ac31cc4a9dd17b0fc59499d05167bcd2c56672d576790df53b70aeb2d372644a51205a0f135d251a7dc801	\\x00800003b047e799042fb7347b9b1589c65327eba5dfedc2c635905f51f6fdf19b47c0612618def8e16eae09b809f76fba7b7bc256d86a3ef65bf200bca5c731505592b3cbc155a3f3e5aa32bde743df809dd78d1daafd0d7d3523a580e1bc6e9bbe943fdef214c59092d81081be5e53d196f212b040bdb25da57b4fe9f2f233e9751d95010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x97a05cae8ef85e3381df34deaa56cac8439eff896812ce2f35a0611de89f91b0e11ae69ae0b4b5bae3cc047c141793786db22ec0155035cbad3ca5eccd698b08	1626982087000000	1627586887000000	1690658887000000	1785266887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xd6095907a8f6d4fd4c1eef25605727caef595eca995ed8f7b4a094efe42ba4632edf364e95fe8482109cb40f45f71b2a47e0efdd6219c52fcaa3a5126191fe2b	\\x00800003d6caf549c889a24b11283d628810bde75d4530ea429c2c5d5f926b013bee2dd0f94cf6c78267f8b7762f52e1483521df8206d828b07079ad9e8a722e1ae5d38ef8ac1d8819a0d7bf8728d1e5308ceb3929d373d6d70dc1f5fce7b7ebf415be99917986a9e0232f3659ab8d2cdf4b0a6885fafa259dfcdead1c769bae4b133071010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x69df6834b45f6d91ac4e163839900262de0aa1431bf78fa5f11ba52eb610cbb2d3c66a03439cffbea5862a0b0d33c94f6b868a30a24af64903353ad9958d0e05	1639072087000000	1639676887000000	1702748887000000	1797356887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	202
\\xd6c54bdc6167fc4b4a34819cef25c74497f3f07cdc00f4222a776228a8a49a09a9d53e15322d80c19de23674decfd5f8447d50708c9ca0d5aba33a33f9931540	\\x00800003ae8b82af13b87178be63817553ea6f7ab2e58dcd4ffcf3aec3a448e0c8d2905e5dc86685bfdf5aeddb6fcbe6066e88ea102de485bbd83767d9ec9ac74566ba0f703ee7291c6454c06cbe9b461c32d9e2e2f51c660944543b9bf0ab86d3f812d14474f860c48352adb75f697d14848156b459952506696f2796369c881df00a7f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x26877a4fc6868c722e58335f125e4a454a82abe21bb66f0603bdf8b2f5a7430d82ba742bc08d415db15176f460ac948909ab7acae3d6484c72e1cb2260f0a00b	1631213587000000	1631818387000000	1694890387000000	1789498387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	203
\\xd7f95b9f69bce61704ae8c9e6566d249279ff04b1c0cdf548443fafe37de5ea191f0f4dae571917f046b1d70c206bb263aea5b910c93f72995ee558e8dd35a37	\\x00800003f71655924f859203799e63c5352c0446f629d41a7e0a6c4817cdd710bc47a6434d425b56a38ee8a722f09fddba8682834a9d6cbc57bd22c7a19dcb8da8ecf01553054238c1d421371e99f2943fc9977abdd228fc11daa361fdd74de7f46449a9138a93b6eeaf502d433a829d16534fc107e5c0aebd1d212d96e8dc75b767c521010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe9e7cb0e8d5b912297571d531b4eccdd00efa02966e7d862e2980794f9934df9607d9c265b6ac1623d4b4ba3b8fe94bdec7e290ed42f872ade55ec856c53e902	1626377587000000	1626982387000000	1690054387000000	1784662387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	204
\\xd82d62970d2b4c5638c58036920550d5b354260684ec47cf7521d199e6ca09e92dc21573454e3f8c0c436af2fcf8f4f384de18f81002e2c919e6f1d2413ac72a	\\x0080000399a4be314a6f306712839ae5c92613905db5ea9781b48c0a16ad3406cf553cf6538dd5350f2e777d953701772475bd7978a94cc8438f09615c24b219504945be3fff2633c5786d0ad2040e125be7670063f8f8422ae8511f80ab16e9137a1ab5ed6f535a311151ed06755f9260d86e1ccbebd537172c057e0788bc10d4355f8b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbb66cd189f9ae5c458a0b6330be8c3e441328bfd52770fcffcadbd48af4dececb118197368d02521a8d0644ac23948a4a16d4718e0c15ea4bf37c63d5ca2d902	1641490087000000	1642094887000000	1705166887000000	1799774887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	205
\\xd98de3509b8b483db3a148637b478ad147defa43cb0734001177811e91134e727f5e0d499b750773b23bc76102273ac3f473d491e745594088b1431c3d71d7d2	\\x00800003c477739f8ff9982500cb51fbff74d505fde1c4d820d87937f6315cace90c4a690ab9c966cf8c0758cdb251eab602dc0894efe44c30f98dc910eb63078cb7a60bcee4f694df14cbf8c31d395fcaf25ce09974dea8bcbbf5b2be1d1fdc36c075853d6bbef4fe692ad2bed302bfec1bd77f603e8a124f720bda7bd771b6993ae5df010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf5be4eaaa2501451dbf5177afc4b5a815b0b82599179a1faef3901ad111695f6a87e15a054be5ae139154a6b85e1ccba8f039648ded31c387288e9eb67a36306	1611869587000000	1612474387000000	1675546387000000	1770154387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	206
\\xda0d3fe06a2a0195f29faf0f32155e91fe1b72d7e8668e294a7fd413e8912eb4f5f64ad6de4bb554fc6c50d56d0b40cfabf83c5bdfd9203ca054a05b5027fd05	\\x00800003bfa29d2146f250f83f1f555d84006afb7e430672b8aef182c21ecf7da3ddcd6374eca643135b050d41111aabe3b9242bdef6a8707403e4469ef00af31628dd347bf80a46f18db2c1aef0751d87aca95fe76d0e7067e98bfa9b79f7c52dc28ab4bdd87ddfd5fb67ad846fbe65759757875cdaf657d5a5cbe14fb7cfb92cdbc7c3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc3bd4241834718f1609b11849fbccd289d031544e8cbface72a5e63275e5a0774390fa5a82661e42f8bfc5aa4130fa2828ef626fb6c9ca4227098d7d17cea909	1633027087000000	1633631887000000	1696703887000000	1791311887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	207
\\xe08d151d6744d983c92267ae327dd40f718e63604431c6f0789a75a8a070c9d526c6af2eafafb89206346ee97e2dd7875af68a1922e41303e0b7557254e8c799	\\x00800003d8f9056570ae9f67263c6b7fc5b14f32ea1cef840768d900a099839b12d191c74a324567cfc34609e4e4e4e684b63c9ce162735885a7be9087ff1ae816519af902f094022ec111bcb56b91b8c2a75d95771b35286ed7aeda9e215a1c5f2bf814aa2a7927ebc548eed0a9e55ef8c8a9cb52865d771c92b10ed27700785323965f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4c5d4f5193ec645622aa22edc221fb3945452afec317dc177c4c34e14b8113ba52b16c770879b48bf9d73b036323d7ebeb9d0fc25341fc3c930bfc2f1350a70d	1623355087000000	1623959887000000	1687031887000000	1781639887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	208
\\xe1c140c1fed533cf18966e48bffdb9cef0fcae92d832f7e78eb8200468e8b45389df2c2dfb797f37ca1a5d71fd6af7f582dc49e2cbc1603f0a339c85817ddf0f	\\x00800003d134bd6c33b751a05321f8863823eecf5f6ff1f99289f9cdb0f0a7ffe5173fff237d9e55e945a1e10f224c93bfca78b9076041daca50567b036c2370bc242884dbb2a8de68cb3492c897f3c866349a9bc7c7a15e4dcc0279cb7dc603b5ac146a9a8e94b02ee8da9d9049d0fa1b84a9666f827f2f5207e94d20c50d4e5cc66525010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa37d13c2d53d4eae6d4ddabefd22186dd10a992747be3a181b7b53a2dd009edb030bfcb4315e49619d3cfa8e9ecc33ea09760ed909fe529a2bde62813700cd0d	1615496587000000	1616101387000000	1679173387000000	1773781387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	209
\\xe3910a132e2479d51ceae7ceaf03bdd8f37edabf7e91f2700717059adee0477879ea0d3bbdc2f065003d83a4b7b3ca22a7d6294c7e4ba1a34f87d48e6cc5f56d	\\x00800003e5abefa3448e9474825890f714f5bae3aad2b6fe6137e3dcaebef57f33b42ea07c5bb38734b0fd82cad36a1f03d196d9088bea2ddf96bc38ad0751597b5c0d894df04371512f10e5ad1fe9ec2cb19645217be6ec3741bbed30fed72bc9afa26a86c293d01b6dea029dbc36b0dd3b443a83184040d01e112418d0911c8f7ef8b9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb74a35d304f0e02c956954649456457b9374e02f373dc279c80ab28901514cab1ec2e14b19f32c4e70ce74e09f88d5a81977426269eda876f47a8f6fb13e2604	1622146087000000	1622750887000000	1685822887000000	1780430887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	210
\\xe429ea03fa5262480b1f7356d1a26778abd4b7bf956c88ca16d3f8f9556e195153bf116b672e04b7b9daa08f61f303835b85d73bc045c45cbce38cccc5b6bebc	\\x00800003a8228dc3122dc925c85a638b5dc2a7ecc021f9426680e3ee36bb4428fc8faf528393fdcdde34b6d3e56ff6cbec92b49f3b1594578e8e6d055daf905a8bc9b1691963e1d9fd64a58cd080f8b36b9f8ff5790c587b42e5cd68b90d49546f64123d7e9351ae971989500c9d4aec6a3b8bdf74548b372ca0a53cc7af3f4390b7d1c7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x80f9cc537cc7a8be875918458abea6f2ffa07ea26fc912d018a35b8e254dcffec55300c48900e8f096fd2c451d5571b9ed2c39dd2426c114fa481b35299d0209	1634236087000000	1634840887000000	1697912887000000	1792520887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	211
\\xe7b178c9f9f63b46e7125104f60e81acb68747c84b8a46b3dbb0bb67eed5f7955c31763abc29cf99a70c883e4e661d5916477ab49aab17454504db5a8d7cd546	\\x00800003da55fe102579333e2bf22843eca1cb336d750dac4b12f83152d0b5ca09f8dacd1a3ec4b7313511ddc0db0448dece950db9c9b630bc5d176ce284fde1881189e2e99870c0156f6989239de97f2dd6e120905720a814db90b7ed5fc0d860c30ad42a540c783a6f3d2df0da1c451358820e25f29017889fac4e7dc1a66c10271bc5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x661182f4cab86b77b9f67183e699ebe38c97c5848ed3239cfd0629d315c4fcfa58ea2b55e122973a7266b462f8ad835c5e007e172b619fc68b2c0d56099afd0c	1624564087000000	1625168887000000	1688240887000000	1782848887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	212
\\xe94921868ddfac604daaf4eb643db2dab45b2ae1c9650e13c6fd80c6db2cc8a1e66a32a4a6f3005c887ce49ba86a2aaa3535950625f530cd865d68e6c3b2a2a5	\\x00800003aec2a27bb43f24183573d62ce8e53d83970cd15201746311406c12c6c7aabcaa39481fb1f35d48f60b555189309c9499335221c3cc4f1c4a66d698e6c2a5478d0ad91b6bf6789f26e0a44e2fa44fb55b25f16d5d304d92dd0735fbb4922453c1c638ca3ab3c3f60a42e974009616cec1429e59cf0f43bb5c29ceb719c743bca7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf3656cc7a6ad5b2138259f13170027a37ca20172095e5c5e93c09db8e8ae8f3af799f877fdf973c7a9dbaac3909a2361831a55f1a08dcdbfd06faa0943470003	1613683087000000	1614287887000000	1677359887000000	1771967887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	213
\\xf2b9c08b78ddc6657eab84aa4a376854e562b7f8cdd0eb9e5f630d2ee5622b56f2736469b5f441dd51a25659853c4b9a2a2c0691f5fa048f4a077f45df814707	\\x00800003ed8e540ea3ab11114325280eb4e233847e456bf6758afb9481cfc02f596a439a232cf60afc4f44c0f892c4c417b227df04b5f5f09937ee97fa3caa8088cee2339f25776766fdbbf36efdbbf45f42ab7d0557e8dba1bab4c91348bc51b618fa3930af3be3f78da93abb3056a6b46cf8edb8b895d5f8133f09d3a1ba7fc32b0a29010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe794351cd8c027868d06cb8c3abeefd82f67c850c00582c72ddf42eaefb381471b7e5f607e3308407d5f02f705cda7f80989bfc2ad28c40b03a6d793a394ee04	1626377587000000	1626982387000000	1690054387000000	1784662387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	214
\\xf33532beec6c9367d34edf8869ecda19bf5e8c9499abac4285180bf52e43aac4cf9c86d87fd8cdc4b2e689fec383e678f2dfa77071019df5a63c8255a8533aac	\\x00800003ebf3734e5dd170c194ba813b49d27a183372bd3d354fbf93b36837139f7ad508a3bb7b34b98c9efee343388fd478e5d74307c9fc6cd05c2b7048d9d55152cc7922f978a334cbad38960b4cb101264b0ee1a4d4af9092bebc2237a0ea70739f649bb4200706c7f12588a80d58cdfe98452d5463c5a3b07d7c6ce99332b1b2a853010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8d6c9075d607b3a30dc88d9f7b159de7d8414d3000ae5ab368b3ae90ebd9effc49c800f7e1e891c09e836b6f8eac7c241b3b87024a28de423b4003a5dfbc0e0f	1617310087000000	1617914887000000	1680986887000000	1775594887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	215
\\xf4b13383c7d276483c0895b2aa7dffcebe64b26a7e57d40ace0e7eec795c090f355465f1182cedff775eee2f061af92d9d886be7cc16e4aad6e40bf6bd0a64b3	\\x00800003c468f207db9d70378ed7069f0111407dff2627b418021824e67c7535523d01c58a574030dae4ae4e86339b543242eb55d168d2b9f6e53fd171eb60cb531fca9c3e48c48ee1ab4d4b63913d820c5e42b56f0ba535fa2a0c2182eb449e844b47714126ed5a079fc19c1419767c8f3591b44eb08794bef9112af47a4020a9acd5d9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbfc70045cd04146605eb8b0b20e38af455bd21949da33bad2068b775224b099e84e2a256469dd097009fb109a0668ff0466a27145fe3a89bfd8f89904e4cbd0a	1634236087000000	1634840887000000	1697912887000000	1792520887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	216
\\xf8c5b79d36ca255b90bcae32c1569fcc5e81df19bebeedc65369928d05f3628a9724c3ff49f4ce148a2d6e21718fe8f6345721891ee79076dde15b06c944a1dd	\\x00800003b294639522eecbfa9b46d4ec97c92684e93625c718da3b63a32b20a280978022249a6bee854a1433cec7903c3bd2ccaab1cbb9a22a7a4062701e726ec7d6ea00c8d9c7daab5dd9e05c9bec4f43f0c346de13ed0f5f0ff9d4c5b8bdacaf205f82cd49be6e792e4b4f1f32d1ca64fe839a14162a6a386eff482e52e649c73469df010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd64820cd339ced7f092ff5360641e262f9e10183817aea1b2d6eae8890903991057de3874ed4d5d17f3a57ab35bc6018c4f796565eb5be153d102a45bbad8a0b	1641490087000000	1642094887000000	1705166887000000	1799774887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	217
\\xfb1d874519c8c99712d7e5c51539716395749d25d7ea99a03797a16f457f9bd529aaf3b2e8fe2aa72b834370e9052b320de269ba79bf042d62b8deab00bebb1d	\\x00800003c338e15d32562cedd9d6db8188878c7d81ffaa8c7bbcf40cdddda2a63ab11cec00fd4f20df3957a0a68dbfd6ed69c48bdaebe6e6688ae89c196694b69545ea9bbd2d535fbe5abe0ff048f00c9093a25820859043ad1abbed66e2ec0226261cea09c86f9904584d02df4a6b81954db1ba98431d1a46d1ebd76d1ede2c9a3110a3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x43a1a047ac8c6f4de460605f2b231f9d87ad6e601ad31118c4f6633c835fc84968c7f279f39626ccb7f7da7ca83b60e908d7defedd6c015a3f2787e323442c01	1617914587000000	1618519387000000	1681591387000000	1776199387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	218
\\xfc75436f0caa80e3cd3fd9bf69557e3879365188c68a1926b40838bd9919fa55d999380e0d966f7cc1624ef5a9c4effd120b13bf43b366f30050bd7a3f88a965	\\x00800003bf7ba56008155b5df1435351943230800d3bb0e63dfa7c7c7c39182a5e7a692194d91eb36e46b7cc6ba3bdb0bebe194406d2734f533d13d48784ab899568530ab6ddcd8745a168e57c7540817d7366a312f24dfa560777d27754e2bfa093bcdf53b4e5092f87622c2ce5a0e3d1d4db19af0adc1142728d97cef57ef1f6cd4fa5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2fa58737351e53f2ddbfa35e5a2d75fea44b86828e200e8f6b0d1f4c1574d3c5ef90303ee82845c7ae1100a4724a6b385f7edaf97b78a2a418179b04053c3c09	1617310087000000	1617914887000000	1680986887000000	1775594887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	219
\\xfd4d1d4e55a83a3d1802ccd1f2cf39cc9c778e7b7067660ba5a7881b647a47c11877a4e0b681678deaa570103a652cf3a927a41c69a408c49bab1f8a957d26e6	\\x00800003a6ab0d8b94448d70e544ead7d9ecbacecba4c8627a813bbe98db5d0064b254cfd38d318f1030c76e012dd526e1570616c7991f9cffe8349a0460c032b56f9101fdae2499eedc1980ba29fc38ae03f08713356caf64facea0255f7b77253f2eda35753de8c2df50fe4f1d660d4f1039f89e83e5fd2b077c6cd18b9fe01a429325010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa8a9d9d03dd35bcfe67374d4fd9d5c4e8bb856d36669da12e45d3b29c65f6996d13af91b8864e6b4a2b9e84dcb12c00ac84c9c93bec8f9f2e969c850b522fd0e	1639072087000000	1639676887000000	1702748887000000	1797356887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	220
\\xff3d35cbedc83df59775941516b5a3bb83ae28709cb2cd79b4aa352b8a3253e75d795570b90c7058f7eb03f073e4911501a96e276ff09c01e476a9a6c8f9e912	\\x00800003ad45520018fd0d5e3a9792d2dd62a59fc00f7c1425ef2bdf0a4728b9457c6835c05c34f6334a1befecb4041d862b255ad67e5f47ec103529f09c5ab453a2222618ca7f99821a93c094fde6002453bdeb80f37a7d1438b63d33e779a05035895b5dd026f1f7a78d57c1286ee707360e0b75c3cba887c7c0e52fff7945fc3cff65010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x72af73faec8ac94e74d9a7f11f6dfa3886f40a3e133e49ae8e1cad1334265932afcbd4f5faaa5f1d04502e6fc02ff4b1ea87aa3e419b6e325b4258cf19ec750e	1616101087000000	1616705887000000	1679777887000000	1774385887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	221
\\x0096b7368d4a3a60aad26158ea04aef88837c5c9acdc272cdffb3e186e208eea3b3836502374040a8602a31c42f0f56a1b9fd010e3ee43aa67d70a2ace77a939	\\x00800003b9189e5ac4972db668837d57791a8a815a349dbf94074db63c2bec23b9d6f368e6a6729e2e9cde9587ce72380083a82c5b4c80240597a470493ae2d7cb80d99ccf66f2773c5171f2094e9ff318548f51dd86bf58aca806f78f3a116a677fcecd36c01d6f8d696cf5c78041892e5b2377f54949d2ff99555ddead2a63e5ffbdcf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcf9be06bc63bf9dc908a383bdb4b6bcad69baed975fdc6d5055192ca321060ca2a4a3ca20a6c35b57c74bbfe22faa4284aacd223316270740befb31b4ad3830b	1633631587000000	1634236387000000	1697308387000000	1791916387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	222
\\x01b6221e9bed0b92f73b7c7e0dcf431fcf2701f1ac9ffb0302de702924bf01ddddc39521a69132d41746d78f9c4c68d2105ec9c05c8759e65760666f21837cd7	\\x00800003de7f01a6dfcdea12d18838e206b22543cbeb183be1bd825d06250b1f135142a5911e62461a9a9650e5a12739b56f33362823328639f4d8608d1284e6e2433f1832b12b6a2f9905c912ba057102d0be38117a677c5874f7dcc27a2489d7e92246a5022f3db19d2aff325f79a3f11fb20fb7db0395236ec74395af0f516e565295010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb1243b17c9ee8cb1744ab00581a1e7f7298924375b72eddf96ec09b84e9bfadf58058d8bb36456a60df67b3ff7744b21e91da2a7219ea1a2111080a6ba92d205	1624564087000000	1625168887000000	1688240887000000	1782848887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	223
\\x060ab809ac9fb4c21adb3ada8df74606003be3923f1ab60116fd243aaf7dd0806777ca661436a209b3dd412228275c42040dde969c2eccf0c71591e7ff013a66	\\x00800003c4d54ba2e9b5c87f20f51bff69c82c7c01e0bfe401acee348b350b82356c18a269c7ed1319793463d7c95a0a01d160e67f3a4d955a71e9656ace9547ab9925483fb8e5c34aca50481d36e8c6b3cbf37e729a16803cd7423e1f218625078b249d9053db3b562ba5e64204f751b7fde5e58870dc2b7c6bfd6bfb4ecfe33afe1009010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2d712e3c8408d16ea4632a812319d01f33d51d035b69148e35fd75634d3dd174435a04cd2bd6a5b22d6e12d8553b06d504bb240248e539078fa49d6b5b91d700	1637258587000000	1637863387000000	1700935387000000	1795543387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\x07f6f70085c553d08205c733de1b6d01d774ace438ecc838bd5472955178aa31e247914e70d196d5fa2d26c676673e03307d0d520c7e0c99dfb1555585b14433	\\x00800003f801a3ed04cb94d37b5d63d261c028d289de825538a5260533e54bab6512b525bc4a5ac75e500c95a101db577c7c7b3a9ca1922de9f8440f9a2aa884835865297dc22780b2731ff4278e17bf0b786c7cfa7e6aae2d1680121c1c93aee24503b66d313b8762b9fbcce6e1ff9e14b713508644523e352fa27450be8ac40f44758b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6e19c5371d738dec7a064e22da7bd5c78a99c039e2853d09e20c0d3c000ace66ba6af35fbd5670508b48947ada8fb3bd7aaa6589e8f1368dbb371d5e8b7bf905	1613683087000000	1614287887000000	1677359887000000	1771967887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	225
\\x07a625f0434885c0d618e536b156db59ec7b65b153d1abd2886aaf124020d358fecbec3c9be6073e940ffd2aa76455735481c82b0e21c9f8d25d68b19640db4b	\\x00800003dbff43c7562cbca7bd1cd569efad83e816f3aae0e595a4a6daf9c0e4fa0676e5e4806247b64cf892d2ae4e3095a7a160eaed9e0e277f6af4969ca9f8315175b7b7cedad68989d477b868ccb6921d020fcb534c9679e43168331e6ab3086f2b8e9570067c4831192395ea9a2b1bbafed1f3d1c60c1a57236a8ef5e36cdd898b77010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf346c7bbeded06e3d11a6eb745a7ebbb4b9ec665a671e1e682828fac4108ad660ffa1466abe6ed48eb5aad893c380bc5fed95eef78a971922eca66d4ed989808	1633027087000000	1633631887000000	1696703887000000	1791311887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	226
\\x0772098faa1da85d4f1b6f85d2ae2b3c4a5852d57cbf03c39039f59b6bee6e4efe3f57749e74a5d6fc6980b7248c52266a9d3df8fde2ae29117caae3fd89671b	\\x00800003af92f9c4e16962ea0d1c3ad3f79abc531211105c14d7db834615c0e34b78fbbcf901e19246e30f8ba9bba2ed579d9aa4ab1893e49d28d4d4b50e0bdd0aa6d1296602bdd4cd5efea2a7312a9d450bc36c8ec25a07eaac0f8313ede0f096d30cad218c190e9468887f2e728d18a4a3daba3fad1c75f9fd8f4813f5215e0fb1f945010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa21fb696117df54bfb223a51c16c99968471dba4e6085b449f89d6c5b36d96040395a8af3ca27a4d7544c52ef56da8802dc6746de1afde78ab02d09ad478900e	1636654087000000	1637258887000000	1700330887000000	1794938887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	227
\\x0a5293f855abbaba68b385499ace51584b643f14897e9fe37e50df4507cc7248bec8c733c59026deaa267e2f605ed280ae86111475443b2de6df80359f2ce141	\\x00800003b37f265ae1c071272b5804dd3f48346097d8f08c9b042e5327ebe780f25c0e123c6830cf15536f049fb5ee9a5ae6b0131396d2b2883ff5015f378edc4a9d64a19bb4b129a125fcd6924ff8fe21e72c31e16564c8b7b26cea473ae6a6e8f872a1a37343c31426713ecaa0867e307650331990d0285d0ad82ebf2d2642fa685129010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x70072d87dfb7deee48b68606572cb46a993ae655d7d170944517d7d34ddee66cab3a3ce5b6f511d71fc8d65e1bdc987e2ef33703ac036c00c6feca1f416e500a	1627586587000000	1628191387000000	1691263387000000	1785871387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x0bc270928310fc3ae05797eeb0e8021f12e5c25baea91615b24bcf2d29dd05a69619e1c5e7b4f7466c5cedba4fe397dc5cd7dd8f0f65325670a9cf19c17ada87	\\x00800003c2a9bef794ef40ae98b34cf0a227ca5d0d368681c489a6883996a6ac1be6c45d295b3d9220661388a4da460978e9ff6ffd2a221bae66f2c469a238999e46fa017600ae879362efeb66d22d631f1d4247cedae82837d352849583c246743a1e6296b819bd3349b8c3fce03538f2fb464741d3887a1c425dc71e7d028482783395010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x840e1fb225935b35a082c44ea65b2b652534626d6e497ab69defa787c0fd82da62d75c6739463c3fb28053fddc7dac66d8f01c47144f91ec3b18011a656a9c03	1616101087000000	1616705887000000	1679777887000000	1774385887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	229
\\x0fde9d1d1702735599cf38cc495adfa8042fdaafb14fe64467826a2f222a7de27edee8d01e41b03bbc0c09f3be234fb6b5d3ec39e540a50d96fc31df706731ae	\\x00800003d2464f323ca66990cc91cec4d2dcdd4926f828bc33d58ce688e414be2d0ba663479c7c152426838b8fd9bda653d0760601bc59408529f21d0ef5643fa34d222847cd474fcf04f3ac5a1ca9f2f67cde3cc3d83cb204e7b1f6b4461ec7b0971cf8145db0adf2212f8b892b83ea0532ae34e7cfb3106db9946f888af69161a0a551010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1f25b74b0d012d08e352239f726622fbbf216b650e7ac21708759249547073c914e412c03003945db2c6aceea40472632ab77c30873fff16910e45f98f92ef0f	1620937087000000	1621541887000000	1684613887000000	1779221887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	230
\\x1556793ff62a4ee5ce6692ec2dfc0db28e511156085d5b646b8f778dad398c710f8a2e609cd04db0535cf0f75a34a9b8585771bd94c776229ac602a2b656f000	\\x00800003bfd7c1f6356fe2dfcf59f9a3212678bb9e596e3325a5392106c6c9307d324ff385e77c4a4d7b8d681b642bd7f2921a16a18a3d1bd3bfcdbfbba8fbdbb09ce341b0e521f18d2fbb991cc5b01b389e083b36aec13f003d47301d1464c8891d331b205c16c5cda7a66dae930c2c7867ce2fbe442e238a01e6b7e0341365e63eb90d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x036f3416f85f2e5139f54f31bc5659e418d6e0799c4045af24c3c22e52245f599b8b36e16ad741fb094f1a21a0b437f03afc43b0c5d3ef5a1804c8bcb8522e0a	1640885587000000	1641490387000000	1704562387000000	1799170387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	231
\\x1732e3ea1b05d700b3898caa3b965a148847705a5cf8c617f3ec28fcd598f9b8b299b555ff8d36b85a9d73210241ca0060b2e40485478717dcf5af418142b8cf	\\x00800003ead0a06b007653f1537ad3692381140b8af424e95abbab0e8d35c4b4d5da98885235ad4e539288d8187909b6f46a4ac1beec023248d73b8a687e82d0fa7e455adfae560fb23c956bd027a0f8f1a3f5a0104d67bd776df3b5b22f766acdffc38b0de7033d95262446366bc2d9b06e3237c01343c33794dc306ac7bb41a065a161010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x77eeca1ae2ed60016bd62bf16c69addfac26f498f695141c91582571e16f1ea1060b225f47e07e711e241fcff18495c042663a2893549ccc2928e3afc647b10a	1637258587000000	1637863387000000	1700935387000000	1795543387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	232
\\x1a4e31a44646cc9bd98cdf9d137c77bfab45bc11c710b88829193fe73d64312c9679e8b5fa2d403c01b789b54c7fc94bca8d8b4a0359d15cd74b98fe35a0215d	\\x00800003cbffcbd41ac380ad4c91d30f87660b443b9ee20d259976a585801ffdb83258a3fcce2cc7bb2f95b7a9d9e4c1bf6eea9fcef6a670eda72c5981b82df07bba6d42e1c75be629b2e6374b4072093d7e7e334097731ba9ce608f084045fce368da261e43815cba78dcaf2e28f9a86025d051e8cf39c0eff8a1405edc5336b04f4c4b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xce09633fe9b20717f1e37b000fb2911fa2aeeec40c30d696b581ef2a8a44ffda2c0169f1f01d79d0058dc6887f5ffafcd263b6e2b9a34b63680eb8278ef22a08	1623959587000000	1624564387000000	1687636387000000	1782244387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x237aacee8789eceb18dc717608c6233fc9caf581181703d62103164d3946b78ddb7062dd47a0f2e537d6a313af628fecf50cdbb943c3d9bccacef560be5dd9f0	\\x00800003c9e68203cc9daa74334fe7a212202ba29e170f3978fd1849ed9f77a0a6f06922c8849f36f355f7c32174680f275067983ae1ba98f370c40c89f5153673d616b653b0e42d8ba80c5427e66c2f7fe1bc2c6f9c3356af171d088a07a110d2a81d41308a9f113ab2da0441df57c940d063a13eb45e1ec22d84f07f4e40817e0b42d1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5bbf33c4d19511f06898fcfd07863016f9b2f63386c70bf4892fbf1f142bcbec5b3205eead5c6874eda9575ce10271f523ab9b2288f4691c40948bd8b51cbc0e	1631818087000000	1632422887000000	1695494887000000	1790102887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	234
\\x281647f67e0ea767b47554fa4638c63b51f50f4454cbaaafbae471023f7e06c1cfda9ed9705226b6560c4b99d26ea1971a3a35219afead564185eff32460dc23	\\x00800003ca2b4cdced3596c1a52c54839192ef4fd271e96d47103ca499d17389a6021eac0cadbf1e63b842682f518dc2a1214d58b4d91a06c3c22ba76d4e15d9337ce5595729b8035c7852b5165cdd01b943a6bc12708e9ecfea25c6b69191946f73479001da6db91d6ff02d50c6d0dbfcb8c6e9a526471dfb0122ad124bea166c4305bd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbdf95eb75bf20482fe344997ffcca1fa50893bbd9b3a8a9abae53a167913f939085d7b716f15b70497d9349357779de48de166acd3ac4dbcf3cc2b4e1612640f	1610660587000000	1611265387000000	1674337387000000	1768945387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	235
\\x2a1aa322de9300eecaac47caaed13703bd643cea6e0dd3b009725db0f0405832985b4ec0b4bfcd9d21d3715faac7761eb90fa24a43b4fe6504ef2035dc4205c5	\\x00800003bcb768debf432b62cb217cd1ed5b273012bedea9cf1f7e7d31e528ccb5753302347aa4b8e767c8ec2df12195bfbb4f6ac2a265dda3a707598ac732985c5a4091426e87910ccbf4d7c9978693c8d7d7252dff401debf1173db45df59b61ce76e8cb6c6f5de491943b1c1a75fb6f375151f2e6dbdb48e68ed3c726d608b385120b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa2e0a1864d5dc0edb55b0e38226b92186ebe617be21c5127b4141148ccfad8e0852b23a668b7081d386055b0727f053aeda2cf2245b22999941de9e925c49d0c	1613683087000000	1614287887000000	1677359887000000	1771967887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	236
\\x2b2e512e9403daafc789747934c8f1355e72fb04d2f6ca77760abebca8b4bbb9c2bcec9701ecdbc0aac54935252cf4803c5ea3f5024ae4b12a345f70437e07ee	\\x00800003a8ce6de2150dcba3928af66b87ade97a15816bc7719e4d36462eac53ae4a05f578b1cc8d2fb5a292174d6c6ebfd5d3ba52ebc916b2228c688077236c627c21911e7a00203bdaf452c411b2fa2304de0e8aeef669d48f986c4b4151842274de4de80b7321cbd7017b46a040d7948264c3863c926c2b21a85818b034f7f716dfd1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7a04b0047b81ca8059ca885cf0d72f2429d79ab3bf82600f5ea8aa783aba5f0358fa7b7bc0747beecbfa7bb52445e01f0dfe16310eeb060cd20df59a994b6806	1620332587000000	1620937387000000	1684009387000000	1778617387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	237
\\x2d5279b5a6e3eaf079c4b8a6fc5ac476e8f71a66fb41bd0097e39f017161321b08aacb41f783b679fb0962cbcc70b6f43370c46184123af82bd15767ed9938c6	\\x00800003ce55b5c219929223d044b4e292773899da09e6e33706616b1001217eec7ffd6cbdbba2ddc466cbd94d9fff2c0c7f47069175d91b253cf06c1a8bbb2cff35d9dd7411c2581f5c0572e7495c2ca95530289f618b06b3d87c4a2564c7b2622b33eca834f09e92da27790b1a4ad17ce13d9772c6e6679ab686392159c2b3346a2c89010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4c6acbefadcd901ce15b08017e7a27ef1e323ebb40fa4dad6b968865a00481d6a7e8f5999da19665e17bf31fc80e31b403b3a687632b82272c2f75df87b42a08	1622146087000000	1622750887000000	1685822887000000	1780430887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	238
\\x2d32579c7213f81fe12d7af4e75f603cfd33a4546f90f3a335b90fadc4cb4bed9bc411d0f5aacf0d7c6599a024ad21fca3f96e694ff4478125efe448da126a43	\\x00800003d4994c8dc35cd71d6b9188b723fc16dc3495f983e4f7af7a38e092c2e29bbc576d56d08fe76f4e65b530412b7e896cd4ac15eb71f4af071cf1f9458490a5c2314740e7a701aa6beac6a634c942360afdf9a9b5e64e76bfcbb0d2ce654a83ffe8e76a2920fa1df577aba981ce35e8c77fc35f6e18933c052c0d588b3db989f3b7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe4ec274450f2036dfdd6c9e5eeed75223c539436637050f4f6e4c8778c7e5204f9a8a12e196de5572eb84a6e4106529990f886716a6e9afc41eccc55dd99e502	1633027087000000	1633631887000000	1696703887000000	1791311887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	239
\\x2d1e81974c68f805cb65c967ce55c3b632853cc384375efe98279166d0fbe6d3b1ed9a3409a321e991788fe3c066b0421283905957b47c34b22f72da7d58dc8c	\\x00800003b3b9f97a08eabee8da8fdd459ac2b80df53158695b058afe71197cfef12d9b9610e616c30fbc85682836df8e075490746ad7a37d6fa73f11f0bd2c123d206c7d0bc47e46592c3de835a799c5869f24a261bbdf8e08b49b6c904c7d94c97c9843fc1033c0c9183d20818837223b25fd47fcb8c96fb207a724871b52e1d26c87bb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5d750538f9de3b26cf4aaa879744db1af46b573c5d8382422d3f17289065e5aa5a0246e5632cfd385b313c84dfc2f1a1923a6f281a3f2ddf00efccd65489310a	1622146087000000	1622750887000000	1685822887000000	1780430887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	240
\\x2eb6a4bc0da958063937134a5a2fce52ebb95e1d517cfb8f97175e5c33344e607a306bbfc403ac4a96d05634aecbe4a2b953355f7e3236417fac99140b563334	\\x00800003cc172e6e2e015bb86a47faa595dd3f9c6e2650f55b295702b3a34d5d53fe5b8da55c1fdfa1bf19c4ab6ba956a1f80d32156228b54348a7f85e11ea0b14c69864f760d2e70563f5744bc8ea3623fe8ddf5125c41b5ad044f7d3cc4e9ec09f092e26aa64404d540803639cb75da2d8a477cc39301ed46c87a62c8f56c842529beb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7634765a109c85612e53bb99dbc474f7330ad0b73824d4e0da6d2812c14c55ccf198b082fd444350a5b16eedee269468639d2d4cd21155aac1f68a2c5bd67a02	1641490087000000	1642094887000000	1705166887000000	1799774887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	241
\\x31ea5e32af946c11511ed298e0d2647d8e0deb65a92d01730c3b4ecf0370a58cf559d8442d1f2c1af5ad8e5f34a4ae926a1af3793f4567363251e6cc8df3740a	\\x00800003b368dbfb5a37aaebb45bb54e33570b205ebbd0941ec9f6c29a46ad7abb7bc9730c3fa63154a2c9860b8ad3f6fd758aa144305a621ebcf7da7b9e18d60e851e9fc52a66075d2d3bd217e286ec79f9b1a43e9b5a03533efde4ccfb99def15d4866b3bc16c85d0c1a159bce7d65e27a44d14c0d633b5170eff6893a10193c19dce5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb6d68c27df8d7e5930c7b4dc17f67fe8cc95a2e0931354c3d77773173a32e18a27305737100466536db826d3086efa0974f62b7c81e8ffd73af64e990efcb10c	1614892087000000	1615496887000000	1678568887000000	1773176887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	242
\\x3302c9a5a5e21b53fc786059789788caef6bd8f29ecd268ce55965c58802b4cefc578b8a235f19f01137da3e38adbb7126887a0bdf0c71d1c9d885ef12c6ee96	\\x00800003d7d1031fc3886b95b14ba6aa75745430fea051afc3926ad9393c03e71eb35f0addce5146cb0512d99790ecddccd2cba089a231565fc310b9f8db9b0d78bb52c83a8c02cb323ba93962fd240a982e7da7027746bfee347ed807eb445b04fbee69e1188cfb401a5798faa65bde0a524201a123ebeda21196c65c942bfb9117aca3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe7938f29f5ad3c0263062994a4846852ba36e460986042a51992095613925574fd228608720e1ca20dbb585f3b4d5d1f9c5afd555dd2425335d26a9f86008f0a	1619728087000000	1620332887000000	1683404887000000	1778012887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	243
\\x332a2b214f8e5cc96193366a815718c258155a8b6fde7d8dd19cf494da4e89a0feaa93df4093c9ad8bbc878c5c69614dde4efd11f3e736900f3fb6fca362dc09	\\x00800003c382e8642d5d402e490c6462aee106520dce67cc5bd014ca4b4c2d3e5e3ea057048dcca77fb8c0281b1c55e0d5eb3bfc19ef5b6e71f1d48b111d079f20cc8843c571dd1ab2cd23bee72dafebcb36dd568c2b184af1c7fd12ba6fe345b5cbfa6481a3ca1f8c941e9f1bea2359de08feceec15f6a8290f6da29107d87c0cf43bf5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9682ea3807d050250d5967e08e057fcec2b17479da1a18275d46f0018d1f1e95d904818e34d13fddda327ef9533c719148842998e08a84b096b606ae81b8670b	1627586587000000	1628191387000000	1691263387000000	1785871387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	244
\\x348a056c639088b85fc0fb48dea512a8404700433e42abca676e2b91449604d20e2fa51c12fe05dedb1af11e9af2aa681257bd51ef25c895f318c079d44a2cf0	\\x00800003a830712226a863b4fdd4a83a90d4bd40f578bbd6edb9b2f2a169d2097d0f465e920f8837aa86c562a585b4e480946f051893280025ac24c854214ea9b0ab2b86e3d3efd27eee02d67cf596e99fbc13da7562a5e7306e44e80e1679fd4b11979b2b4c21b3aa81e9d6c47593610af1cdb0fc4ab6d61cdaa4fa80856b636b790709010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf6ed4ec72934aebb3db56a0a20ca7d34f2b8208cd11e114301353aa7c282c42fcdf2e252d89fc3c08236dda57241cbc75d96d3ebc7401dffc95bec4480af9604	1637863087000000	1638467887000000	1701539887000000	1796147887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x340e502b7442fd6a9e683c71683bf914908f18529e43b594942a77633fab0ceafd575dc2fb76bce6551181b7a4e54752bf5e324704a48ad1ded3441aeef2fafb	\\x00800003ecb545af90cdee76778507483d1030697508345f4d1e4120aa9667e8978afe39f70714c84924f5806197e84c51641c9def3b9cd31c4a19756d1dc550b48cfa3889c0038fa721534c470e98359009b636360057df24d52beb11f40e8423eb61ebf00f4b2aaef277db96d491b8b4819ac0906b9365dc1bc891fdfb108099b9e523010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb488aca593c19a2954f5d018c5bd2baa141cf8cd40e12a7d0d836669426e7784704f3a193307c3a1e44ca55027f816ccec1ed20f90a80e453ce4e75c0f801809	1626377587000000	1626982387000000	1690054387000000	1784662387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x387e5db3268f3ac0e4624d946427a650195b07c36c839436175022fb98c1bfa4a3476720280f460e3bfabd3b0e5477e5c0dfb23b5eedb479c1d15d85e8826575	\\x0080000396118ef99f7856015b902a22d7b86a98fbf7555833510f0dde17f5bfe8751c515d0d07da6cb5d6ae78c65c08dca06ccd3cf8890508a3cda50df709a4bc700cbe3a432f272e2ad643e4a64657c8fcd8eb0dc82a22a82785dd681792a43023509d9a856a949de14a8409fbcf80fe057123d24dee81a0597cbf8bb315e4973313e5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc0487d2713f5177d119af9969ce961617db3dfc46ccf6962c99121df478834f6b41e425d7e061e65c3de60f9cdc95c01240df2a37f343378d96a251d25af2b00	1612474087000000	1613078887000000	1676150887000000	1770758887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	247
\\x3d0e8e4207c78cf9394e020737046c4ef3d43527e0e0ebf37a3a1fcb4725a06892daa02b84dd9b6927d10efb361a15dc69d91a91b9f6c9e9427570a4b19a3d3b	\\x00800003bae637f8bdc425ea9457134c717ccdfff0b9c5c0dad64b581f6b67aa54ed4479537288368b18a5b90033eb755ee34efaea590ce215a85dd6709044fc68dea4f2e3986924eef57925162c94df3d288efeebd19fd626284ed268985029a0a44251856f1e0a0591234b517aaead42a128f6b0b29747725d47431a4c8c26ff7f884b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2eb20390a4caad0c4ca1992ce8de7fe78ccf574123142fcc53c145c5c7a1dbd8dbce9a0b49656e98591c22e9ae5a726c7277ad278217c8f26412bf5089f33d00	1635445087000000	1636049887000000	1699121887000000	1793729887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	248
\\x40d29d07b37728c321e14e56f6fc517968e376e9e34a6922d13d5a70d72004a1f106032f6ccfd6920424033b555f4a9f837611c403ce4edf0f47ea0541ec4e91	\\x00800003c2d752b3b00a0cab75b4db0c99286dcd537c1bce13dc3f1f14150eed6c52eb17168ed6dd9bd6270566044938b73187f8a91cf71184a751f31eb28a55c32b7d953638807aa54b9c01fcaa599427e7ced856a2f6561b4995c5cc572475ff850d9de21b944c032a3b90e5dea236f54cbe5942fd615c7809bfef514aef34075c6cc1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x020f6ad69cc044dd5bcce5d838f8c39e5992ff8f33b0e46e8907ed2b102f390965a812cacacee1185de70f4a11daddaaad9a102b9f80441cd72dc4d59e8e8203	1630004587000000	1630609387000000	1693681387000000	1788289387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x418e1208c0c667268e434043819d4fcae95c7901f567260531feb4c9f5d61fb1890d16d65f14bdfd09b925c05f04d910bc8e5a3e9f22ac23af813d16bb5b1a53	\\x00800003aec2d7373b1bac48b73cd08675643e6878720cb42f138dccdad53774c25a9820cbba595de71b2e465854704e818fb09b9451cd8d270e77ac308968d0c34a096b940db172739310a9b7ce3f7f48f40c37caa462949729e77464aa41090c7b521ab3bb5bc6e14dbeff716d94619b626febf78db98e79706673c53572e16b1f7e8b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc024aacb64c6902002096e40cf4c3eafdd96443949200d1dc1c01811817e5e6b39c6f8402f6bf460a60d7dcb145362d781c9bb51e30aa5dd846d7a975e4dd701	1613078587000000	1613683387000000	1676755387000000	1771363387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	250
\\x430e11374920095486b2c37ea662c79b50937fe41aa446a5489f2c1f9f094911beea045b8267619440911d8f21db88ee5acf16de8d8894bd3950022cfd5e5d7b	\\x00800003b3e64b3859504d6ea03c5b3aeed09c1e7cb3fa566acbcd58839afa9295d209ba554a78f439ebc8136697d807a91d74c586f0f7c577b614628ecf89b0ab4a20eac3921bf3f826b99cab1629a49a7ad52f6a1c05ee22b9e382c9dfde5414bb36380a1dd90eac40529571e22b2f0a9b3845669d9a194d0a7b2692c9fceac0a01ad9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x026242b997a9d6e1735abfdd1fd1059793dee96ff66a25305d00ea43bd90f5f31b65cfaf2342b6ea64b4483b726fbd648bedc602a131309884b3ccd7da60d004	1635445087000000	1636049887000000	1699121887000000	1793729887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	251
\\x4ab2d2410e2de77cc43dd1f4d09b8af4d18d04d428a26417f09ab075fe36bb73bcbab69affea2f91e7827630d7f0eb8608a82ac4b80cf244829ec843c566a70e	\\x00800003a78652c77f8cd15ef97cb87d0891e20081835300dc7061624853a5cba9a6de8703e87fe6834bbd1fb931d655062d4433f8165de72df0e6d5449e1894dc31c3a2919dd0723b13a4e5998d1bd66b6372fcafbac974a206419ffcae8e828cab493a0b4b6f01af5d73f0133bfbbbaa4835755a04e6ca36c97d70a3f6f3196abf37eb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2bd38aee47b3115efa4cb986550d239e6a03c305baf4eee63d8bc33b5f63c12cecb87d3147503eb12a6ed80b17c708517fb7e1972db7d754faa3627ee00e7200	1623959587000000	1624564387000000	1687636387000000	1782244387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	252
\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x00800003a63141e3235c7ef4ccf5572a770f7cc11e3deb215ebacb1b2d5126e4492c6b917492bb7a64ee88ec46e64a38be0cc7f9983bf597ce949830fbb1e3b9455e55b62ef1b6bb9ece310b4559bd01a21c3332898b171c7941842843c9437b8449c6183f7b9e78a3fae84870b5e1c59ceacd6e42f8c0633417796ef63b9798569c7e5f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcea7dcc4003b2672d4cf8db715130d445dfbae87215f78c4fb45ff618cee78f7368261212486c7d13bc3111d14ae717efd9f33af805dc2af2a3480b500d3150d	1610056087000000	1610660887000000	1673732887000000	1768340887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	253
\\x4c1a55dc751c97d0a2a17c291d9163ab7365fcf73a5f28f84bd382c04912101609db47d7c2a3cd05090ab4f9dbaf31351771c28bbfbde2b7783c82e5c5a495e7	\\x00800003cf0d6efdb1a1018d85e8a9354a5068914a95ff9ddb82f1583c057a0cf1d526ed85e4f1630809235e49fdd75daf110721bff85e687252f6b73dd986d22ac1c9705ebfb495e5f9b28b9beabde6d7b470df6ff0ec5d6d09c5ebef8f4091f946995b787cf3a02ff94ed8d64403dffe30d5d4f87844a9a0d28dd15f3951ca1f310249010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf3f4c493d61bc4ae54fc373365ddf0219642dd73368b637fe3e1867636531a979a2a42b87f1a4eb397833b1a603a4b9d00e25079eb7a02716fc2fc00efda5006	1634236087000000	1634840887000000	1697912887000000	1792520887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	254
\\x4d9ab359cc4c94b722757849df07307d30846ace2262f97fa09f17e9cafa59ca5111e3ae87a4f8ffa6ac27be7a323e63bdf3ea7a461b8c9024f2a11b4ac302b0	\\x00800003d5a7903014c118abfddf03240211eccaeb2135e41e85ccc0332d7ea1763aa2c0b13f928ef229985daa4a133764532782b9e931e1aa3d0b8bab3e41b552b89b016d759a34e3c1b67450d20a9c8e00f0dc41a30e9f8ca4cfa35bbb0e6f9fae2b12d8da7c07dfef8a3f6bb288f0e90cc4d2cc963bb5e08ecf5e54e0c1ad97b67191010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe01cdb2f8d9d71a96949c07c186c7810d6a8d74a8b4138a43a96d6004d54fa1a86613097c7f9c9feab1f1a8f25987d086f234591a1cca3a0ce45824d7a487c0a	1621541587000000	1622146387000000	1685218387000000	1779826387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	255
\\x516223fa0880fcdef4f9da0d556e74999e9bd0b3e83ae2a927245478e106a755fa00f56c58dc0e9a38a1f9fa7b9e88808d664f93246854378dda1a75a0a26425	\\x00800003adf9aeb86b701877baf2437a98a1ef505d9b4ab95f0acc2984d28b9b6888151717a19b51f670ea1a6e5aae5ffb156a156615a4f8457e00dc70d6ca1cd13ef79754ff01a5fb5b8d0d9e7a242732c63738396a0dac97efbb160f5d473e1fd3f7968bf75597d7ce52213282acc946a55dc0b3a56f3e184c0cf114d5e89a268916b5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1093ce8b76d4b9baa5ed114c1f616c292b469aba1aaf4160f8fdc989b62ddc643360aa0efcf36e1d66072f4f0bd932b0e3a91ab1e1d507d6320237531d14a009	1617310087000000	1617914887000000	1680986887000000	1775594887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	256
\\x51aebe3f28942e3d61980d2be678f77ff6fedc3aad43361814cac7a3d10606ef8e30d9db79146355f8285f18fea1a237be671cd4f7136d359b1006f347dbac71	\\x00800003ccd6c57f43723ca81cefdfa84ba033e68ae9086d2c5b12469abcd14f12a8a7f2ae7d3869db9065b50bb5ad17c3a07bf1a854d9afd6901ffd2d45e86d7b67fa21b47e9c988152167a302c53e31a692b377e6922119892119918a1018e8de2e374cd562921df56d26fbf51bce6522114835df4f7a84f000113d03e42b5a0b056a7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3541eaf2add313784688a451a43f62dd1d2e713c6114c37484f4522f25352005a13bafb26c322b070c26fbc99f3e0731017ec587202c44b2d4a92964df54210d	1613078587000000	1613683387000000	1676755387000000	1771363387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	257
\\x59d695c3b9bb5fe4b05e1fb6716d38a956fd925b090105a8f81b80beb25cd86b0b6656e61f1ae745210ed82689d09a00389315a132cff94dffa2438d310c6ad7	\\x008000039b486cb889c2b4e929f296915dd873bd129ce7899730c3147b56892fd158b93d7c1c204ff12e91ed45f2d31ec541db1e6c8bae621a9b65cac0419bcbce6d4c7225367354b7619c9973664f48932d8c6ba28f3ea33471c8614be26496b7e495384050b1b756fd9397b9c75403621c116dd994287a166d16134db4267e8a8fdfbf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb6b21229488063c6226f5200acb1221879c3496d2e87d1eb22fb9788145c6befd03ae3e28427e8b0e3ddd062b432ddee27e71a592393fe33bdf06befa596bc03	1637863087000000	1638467887000000	1701539887000000	1796147887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x5a1ac08a9162af50fddf8ab78f10e61e7642a4141b9a5978a84844a6b3b338e2a572fc39870b9ea77962ef736c468f439264fe102b13a8341c1ea3f6b6399b78	\\x00800003d10ef8e0bfce7574e49006526dba176037d8554ac3e0c88ae30522def93687a07143154a71b989ee7e72346d6c6ca525bea4a53381a60f670e11d1c6c2bc047eade7c746e5b497d115b43b971f5d878e9723f161abdafd3f7d6e2bfc7a88f3d7ddd1032efb0777ad7459806e49fc043927c282891a457268f66399db7085237f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7f8de05fa8dff8b3a2a9f559e058cbcb874ce665b57a917848d2675f2fc1085040774413a09d936fccda0627e3f30ea055d6bb28581963ff6871426a3e84c001	1637258587000000	1637863387000000	1700935387000000	1795543387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	259
\\x5ac6b82b5edd41c6a012b94bf1ec8f6bd8e781a7ee67d623548f78234ea7737a64ce127dc307ab780a21750744049838b1508173b042cdde173f60fca89039b9	\\x00800003c91d03a53d709d9b2898fa6c7e5a52cb42cf2e0eeb5888999ed2362b36c549dcf61f0c576f837d907bc881455cce618211bd634dea5c729877aef67b8a60bfc5a841d58b04356dab416bc2b3790373f60b58c94633c02f6df7255ac171c216aec5a2d72f6a4e3fd63b6470e68b8fca63d45d91cf44eb96fed4346265b10c95fd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6403175b4ef5cfeca0df2730a7af5a97acfc865f3b1d5330274d857992996196a2ad738ccaa145a5473af4417bf263111fc686aa05effaefb30ed80f10e65f0d	1634236087000000	1634840887000000	1697912887000000	1792520887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x5b2a9cc29532b69cb43e08f532d3724600076a418e1c223215b923aa85da45e686dc88e102db7f863ca46cd439d17959559de2d596bd87aad39b91e7cd461c0f	\\x00800003dcc01307bf3ea4c0794a717ca53c01e8ee10a95c51ae21c17a1e0ddc9af66ed4b6b5f8763d5d6646fed370dffabc2872d8dcccbad97d4bec1b4ecd8b76dd23645d3c67c6489577f325460a3057c68f38336b822a2e4768f572eeec64d13982cb0d5183a7b222c47af9dc6b02f6b31efb858ce9f11b83972541428b24c5d41029010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x26fccf1442346fe96768958c1aaf4a449980b79351b2906f3b4ad76eefb4e57080c25bbb71470ea2bbc0008668059ad20b729a8db7f14ef2f2552ef29881150e	1621541587000000	1622146387000000	1685218387000000	1779826387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	261
\\x5d2a330e673e9b7cffc1df8d7a17d212b0df9d8789975d6ad744893c168699559c3651cf496bc8d9a3e1e397a71a8b5a0484ff21a30b79154d0048a75afc89aa	\\x008000039d29fd8cc19dc92c920a891e0f282ac21ee025dff892ef56a74038b6dfcd583ba4eae47f6a393370abc3725fb9b1b3ca2a96cd4495f2fb0e75c49fe8f0e8d72245af18fbaf060b0386234e61c357f0c539088ab95c44ef5dd378d6a3b08441e64b97214e965b9e01013a3850d230e3b908b2609c1d2d27b7de3e57023a1ea4c3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1093e6debf6f836b9f19ccef7fa4fff9b63d858dc0a186e5fdabd374d00569296be92191a651cceadd0f0d6404fdb042ffa5d20bc7f111edd63f9e90140e660a	1626377587000000	1626982387000000	1690054387000000	1784662387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x5e8a8b86e0e9c9ba58678dac16ae91461dd014a12ff2871ecf80d24f9a54d46decf0182322845651c6e90b575d8c8d114ac3eb4caed5a314278a7084fa6e4d86	\\x00800003aff5297307f29a341545163c2c44a0297add96554e2f87f8b7bc9918da43dbd6d2144d0daac21db1119e1c52280d3f5dae4d08e63a63832819991d7c08c9a1927814e530e0cde820d129aa12c99b8cf4a1ef5109f2d19e63ab668d5b43a3806630adc0e6b27ac3ab1b3f8564fd13b3241fea331351f7b446621e2baa3640c467010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd8fbf26340ead2542fb3065198a2ae12f1955ecf5fb6938df4d1761dee6f08548c45ecdc149391c7ddf0c157d99023878a0c4f3086294ffc1d21524a6033ad05	1624564087000000	1625168887000000	1688240887000000	1782848887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	263
\\x5e46dcb95274785d0d86f6a1becfc070c2fdc934d57a9afab8b11abb48116c6ffb3e1d5527d3fa2f5d724a6f915ba82feb741d6a1f444d52a070410887e87c7c	\\x00800003cb92440df83ee5aae07706ba5559263224995980c1e94999fc54ac954d470bdd56b2392c0bb533aaf06d380633036d3b6d3acd636c67eb62bbaae6d2c6bb0c5443afe174b9bca66c4d71a051e76a8c66407b76ee4748047cda129be72adb25980af429ee6e37082e8ede4c4a2642ac52eea1645995012f8594d3d8bc512e9ee1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe99839af1bd4815645b13ac1dac163ab3ad7c4886692c6681e78fe12dde4d09ae98e53dfb02fa3d1c4b7ee43c363627ceff1583c1eb992ee1c42546387a30b03	1627586587000000	1628191387000000	1691263387000000	1785871387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	264
\\x603eb0cff9c1e816479ecb2b0dffc46a2158486aa9304c78445364ec12037ba6f1fe1c9d10a538a0a3e8c4e5a9d218b2837ecefb5ec8b93e51e7b03a7a15c01f	\\x00800003ccbb99a94833fa0a9a5025efd1f6b27a22e1441dd3811fff3794311e7db4e27d14177edd7544b39c394d7d04db9db28cb7580baa00798e075b0c322a4420136e5eddb877b20beb1199f23b307ac905b8af53365bbadcc9099a5b4954709b86e29eced711343a9563c44c0f18f3823e9fe370567a073d9833132c17136e31d287010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xee4f0c581853c7ef7465f66d3eccf08bd8a74d49c3f8db9062cb2aeaa31638a0643e9abff87ce30072150bb39bbbd8f966c3305b861652f231f7396a1c566104	1628795587000000	1629400387000000	1692472387000000	1787080387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	265
\\x62aa17d2762f1d4c0329a0fb06dd68676d4efe8f0acaae008814259d16e64cb40138fe03d8f34ad58564af86c589acdfc7ed777dacf15e84b2f332aa19218a23	\\x00800003c262d2636ec83ac2ab9171e3739217b05b7854e0aa99ce22327cea96d606c4c03e15c27cb8a9f43d869cacc2e2f25af54426951382b86014b562702efbe917472fd7b9fde6134cc0c21c22c783996bb73cc28eb8aed8fa481f5b975f82589c8cc1cac7979a36b95a589be605d2b1a9a377113762171c9ac6efa4033354b6ff87010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x74a84f1324fa7bbb64d5a53d26a031006931c31fb9a6ffb0ec29862cb9f55bba5b30949e01056b911ba2b61d5fb445550e8c25f8e7535c4ad85464978e5e0901	1610056087000000	1610660887000000	1673732887000000	1768340887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	266
\\x632ab6d937dadfd083da566c98bf3f7fa9a09c8cb5c45a1ef763dd4a2c8cd54e457eb9bc415c6c90ba32460a972a8b96443abe941fba3f2475914544c80e0b8f	\\x00800003ab8912a976ab4f123e6087ed0cdc20854357ee53155d51f0f7cce0b7f0cdd9d9a29761b015a0acc3273d20da4c63817ebb66854f36c4db23c6805f821838c8a7c0fb40ff1e76a157286c9405937902326fc1c6614d5a98266cd7b053a57da97dbb304ea346deb1dbe1b34ca794c4f43451605c7a8b59154d9787e478486bb76b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x19f204daafdd87c6405ac1366cb2ff0de60cea6ea4025a9f42f1ed7afa7f3caf1dfb750625fce15d85420d18a36c7dc3415b8b875be1e42c39f84d8d54d7b90b	1632422587000000	1633027387000000	1696099387000000	1790707387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	267
\\x64169a2726dc586aad670d78d098f53f7eb772b06df838b4ccd455f940707d8012ee086e52f8bb70a4c8e801496e223bab1abd5f384f135bdfa1fbabdfd94c8f	\\x00800003cc8fcd81b202d444a1e14f1633cddfece1e57c11670f4d67e79bee3905400a1ba7e7557a7f944b19f45ec1cecfc5c087325d056c60f19048a6a5be6485d301d51788e67444160b0f3841969715655b5354a3392d32511a24cb4a3ea0255f4110e6563bca027eda20f2453a1844b976a25850477a2129cdd4875c335bf3d1c263010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x968ed8f73a74d95e14d94afccb82bc859c208c44dbdc9610dd5fe72a1a8cff04a655a972f1cfa627fa4d639b0abc55c4cfd56742fd6ecf7317085661e3fbca04	1630004587000000	1630609387000000	1693681387000000	1788289387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x69fe5ffc98f39f00861c388447eb10fcf2fa755c8a3bc90c55a6f9b9f7e9146929dc43b745cf2a629a5b4331b3e1a1ca8f6971903d776969e1096d9d9ccbe3e8	\\x00800003c47be91c3bc431d853219b35442b3b2eeec2e335bbb0ff25467656cce9ca18e231bcc3d98784a1f9ddcec6d1a95e55166b52b23b0fff50ea1be561e777650880ced7cc2cc83136f7abde0539259218a4c499437c956b2d0f0abbeec1f7c5e9722f83cdda524c839285fb070fff1ed3a8c61506cc8fd7c43547d5182797ff605d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x15c4bd3b0d80facfc37759a0ff0f0a4781959a42f663d14a5115cdd4d7da4f0551b8d7f437450bf43ab0d7632d118e4a4443347b429492a709c576d9bc5f2f0d	1631818087000000	1632422887000000	1695494887000000	1790102887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	269
\\x6ccabb94075293212e91f91cad31389af6927f2ef39c23f3a8640e6b576683c7762a34754ca92e526f998797806ff3da556a77b6767437a21af10efa945ab2df	\\x00800003cdb341a2e50e446c0877f0b70f8055fc197b1e678fc1615f19a16c99b25db3ba4a0a29f0d58244c8e9ad5a3cb81ceed3e3e472113dcf40d7d2bc92218f24cd815abe7b20b2f9cff4566443f75f8df83f6d01c8d73d345226e75765ccfdcd92d355161ef1d0b6e81c2824b31ed14a1682bcfbfa9e22f42bf10aa401b684efaf7b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x248001fcfabc911c6be7b90b7b47e86354f085c5856838e515b705fec8950b540e53382f63b9450c042e4ec2173544bb9c2d69901d8bfbe5e201b511fe9a9a08	1640885587000000	1641490387000000	1704562387000000	1799170387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	270
\\x71aa9f6945814a161060a1f70a43e0eb921495fd37c54e9e6d7adf652e4061ce42bae02bb097a8b9532098b69ae1993cb8ea15e12d1202cb9a750165b65b5e94	\\x00800003cb5e6995e940e9aeb39a37e9a93aa3871fbc36cf25218c392f90b3ee723e8fe04ec04790f8546bd50195ad3f3d56c9231dda820d3261383fce2b41924bbea82f86e1091d804027ad309c12d5e305492b04e79e800f78495c856836f80e15150b0e8fa25ee54261293dae29d55467d290a5c7d99351a953cd80312756896889a3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6d734e8c7597dc9de02ae55011d07dbbaaaf73720302ae50cb4c7d89925640af220270c643fda6c92612bce4c8e4855c8b28014cc0fdd310acf532e4d678940d	1640281087000000	1640885887000000	1703957887000000	1798565887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	271
\\x76f6a004e6cdf5b8c07de0d2aea81f9ef3e6a4df1b5dd55d27a9554fcdef185169ade1bdff4633fd552dc5719866f5583a4412ba25ff4aa195f7b06a3147101f	\\x00800003d58779c0aa929eff3c75380378733343098094f4a0a545a4c3b71488bc47386be0d356e087ec0e0454fb355888cded067936d0445134bb10eef6685002aa9e6b9084697a0e8d54620f8ac85e1c86fdd236f0c8fecb961c3abff0a83a112d0e0a2720587f0476133040830266c09cae037720bc330d7ac9680e5ab30d712b11c9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6d1956b58f08b1bbd1f125326a3e90f12c362966cbf4f341305ae7bfecbb12c96fc5acc2d2d5159be58379fa5d559466e067135a514c1990a669d0675eeda200	1629400087000000	1630004887000000	1693076887000000	1787684887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	272
\\x773a0ae5590f37befdeac85591a9fefad878568a1abc6212f8635a81acfedefaa78d15f734d092f3e4fc0bdb5d201bf53f99757904475d4819d82a00a0887498	\\x00800003d6cc67659f9c04bfbc4235bda2686f2e997654c3ed8cd2bc7340bd3b2c3e7907d238d77d423aab0e96b17db5fbfa1bb6d84008867f93a0482292f0e71cdff480809fca1760edd5f24e79dcafcec02052c2b41f7a5b28b0e1695aee9c82580e1541b123a7b6bf1cd20f468917fe605f3a98ea6c220058dec219386cb4b349cb1d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x644db0a9915eecc1ff0cd31cc428b26fa5a0b9552a6b2c2cf0617aa8e4f9dcae25d4c13c807e9b3981f5c74bde2a4f7d0ec456b36c3e3c58c5c5c49ee8852303	1619728087000000	1620332887000000	1683404887000000	1778012887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	273
\\x7b2ed905499af0ecbf6ab7e37b2fa8168939ca6f1f6670a97ac754f0e4db2e20c8d6b09349bccaf57713769b2de9e0f7c6c1208b5fa598522cc475a976338645	\\x00800003bee5a1fd4de5a0352f13dc20806b72f009625cfe9256f7dfcf6a6067f20f59812a91f02ddeb7035239df431921530f2df07883409db750bc310d48899e81f9efba7fc9f4e80d971e29e3b20211bfe681adaf91af62615ff3ba3e44441e2b89d401e2b94875a48368b1d7cab86b550257fc3f85febff0ee049367eca45f726f3b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x47a61cc13d7f0830864e74f4ee19afdd732613911e644d9428cef1fe05c8b985a0716dd74e9ee20fa42a258d53bc43dfc526e152758c9e5c3c8d8e2def797500	1616705587000000	1617310387000000	1680382387000000	1774990387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	274
\\x7b5a5ecad69f0649ae50eabf4c10fb80fd4defffb0093ecca83cd361c003722180df7804034c4ffd2a66c372e6f60ddba26f4252a0b4ef4a15df24eabaffc16f	\\x00800003bfdf9a151e47709f3c9dbc6f6c93181f7520d0d9d22e24ebd5f4fb6fdda04053ac451a4d21d90b2c78228202dc0da231ea30ae22ff551ffc2a27851360d450abc77df64d87579b6c2dea8101e93c23f38f09ee102076b8ae760b1faad1cf0aa8c3352a2211e63810e60d2b90a0aad24effc9bd5ca683686856ecce74b70a946b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4e34ab453cf8390bfa268858f4431e13b4d5c25df8321489474e09ef46ca9a8610cef07cafc26b7522757a73c7ee33605bcfd2bc6b1223b104dd09c8a8f4c80d	1637258587000000	1637863387000000	1700935387000000	1795543387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	275
\\x7e0a50d4e5e891a8eb7a17706cc05519954872e422f4da85456de6ee63553b743cbb1a4a68a170ddc45d3b409291e3d45d3d3adf70a86557890d625f0766053b	\\x00800003b36f97d89a09edd16c56b0b4527854bf3935169d8107455898cc70096ecac96e98cd9266001fb58471bcce7ed2844c5461d97ab947c4a52a0fd828694ea2566b597a49bebc9e12a602049c1e0640481ca0a2b0160159a20b2f50d58e2ee03cebd0c0d68958c3db9a1c944c433fc51975091b85e5f4ccfb886268a9479e5d5e4f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc05a86b02e1833db340e80031e9ab2de4b9b198659c2243ceea0d5e36a8c7a165508f4be9dfe6d62f6014907162c04a6c908355b51b879289e23fa2aa097bd08	1614892087000000	1615496887000000	1678568887000000	1773176887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	276
\\x7f6280be776969802d1962f2363b89d97480d4ad4d94f7a29b84c602bba72dfbbf0206e0f5d442c01a9d40262b343d144e93f18383a1c73ffa73eed095510916	\\x00800003ab631c8a50a148516d144ec3edc71e69ce6650ea2d6115d63303578561110002aabbca2994baf63349a9d9e6fc1a96dd1dc1bd998b2f5a722fb7cf2d26ee9dba18a8201b6b0d479277693bac1f0eb56dfa3c40ef0aa059e624667499b46610b1b9f002f2feaa3236e8e9877e2920684c813109e84d18fa7ee301dc2aec476d53010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa835c1eadaf25a4d37a353ca3939e922b4d7f7a6dbb59bc8ce741a96feb70c87d3850d0803bd5a0bf3ff7ec574c2df741839a5884cab8ef21fe6d3827ff47107	1637863087000000	1638467887000000	1701539887000000	1796147887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	277
\\x80da0577b0c27b4442b05061dafef45e675500205d9c9d36fb61dc0a5efe250528b335407e5f539f556d99f3a33cadccc4fb81b6e53bdc12cb55cb0511d46acb	\\x00800003c1f85a3522671f62ddd9c4c9604a8d8507e4ea8f3ef30266bd96b8db180c05d93bb5949f06770b90ee04ebe21300bb77a1320d7b9033978704bd2a8e2d3690e96d5726c55b732ac0684cc889a3dc7c9771873a0f232057fa094f46b5da6b06316b1ca816a9daf8157b15630af8a99767c9f6cb6a486f7605fccd24a78b6d3cbf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xaf3cec17d2ab4adcfe1104f63b96604f1318e28f907528df525acdd90d72e77b7edd9dd4f9493914a2df51753156a88d3f5f7effcdf3d61445bbb0512837160c	1640281087000000	1640885887000000	1703957887000000	1798565887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	278
\\x845ec326c51ca8ff9531984cc14ef90bfb26c33fc0773e0fcff8205fff71f7522d7fd841686fe36ff93a149b90b54a0d17899e140a2ac6f6bcabd4b99fd9d851	\\x00800003c1d41129254dd17e62ec5417a0828c4760bc4d1071661af7462d327efddae3eee9796e2b680377b9e8c725ec256be250c0120534e81dd6d29c46c8e2b505f7c48acb1012485dd9db03fb93bcd5c36dfc8363afa511d42d4b943843370447e92a7e241d8d5dbc23e4f668bb095f4f1b226e890eb7d462d6c153b7ba3ee20018c5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8440ce519344ee62052744c3505ac8edf60f03b56dd56249918111a9ea55cbc7f3c509b8244f6a1d783ec31c630d74cdd912a5f12790770a43cd0284bfa5e302	1610056087000000	1610660887000000	1673732887000000	1768340887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	279
\\x84362a02a7160f52cef1a32262b362c3c907916669f21048dc8ab45b9b54033f1068fe13222a852ca5721dfa55e88afeb44dd17ad1f8b372ffff331fe5b68f54	\\x00800003bfaeaf11b71dce86ae1048344a6ecdb71af1176e9c90e0236c55829e100051ee4b6e95f0b8b525ec84d46fda4bca72dd631fec464b3743dbad0571abd1fc53824c036489bcd6c76cd22bcc9dd2ec83b3ad6b7339701c60d391cc2039f5ba25fcbac4beae719ce08a201d355cc07419f4d2fac2dafad4eaaf1f0ce564ef5c9361010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x225a9356d321cd3aee647cfae56c6a9dc97326e4ec1a7c00fc31cc3910d116edd85f5a94f819fe7660c31c541ee7a5653de9724ef15f76db791b74888731a40c	1633027087000000	1633631887000000	1696703887000000	1791311887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	280
\\x86aa991d57b7c95890cfce7385e960a9f80ac70a4c3b7e2bc4227f5ce751e36ccbaf63b00f0d66a5881a0a9c8748b944538e49e2f91f4ce5adf5ba513ecce618	\\x00800003a6d816aa116f8f854da9ca3ad15d4867bfdbaf34c38834617ec199fe79be60641e7b4b110fe1fbd2036a9d13b874470eec2b93e24796f0f281b4dd75e4e6b2889bec0df61f930e279895766f402a34fd3ec01868ef197a95ad0daf9ae6b34a81e06bbfa9d90eb460881f5dda5fff60d7e647e4186aa044b210043b321175dfdd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x361ed63b063b70a26fba9c88f1dd6a2d0879524627eca344a540834ad00149de342eafe95030d20b076ab2ce2869284038b464dd267f946fd63998faaf1c0300	1610056087000000	1610660887000000	1673732887000000	1768340887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	281
\\x862a07b9620c775ce4f6becb0a288b575c12b308202a8f9e1300ac5e9ecebec2963b457a92750c95aab4685cca1cdb67bace7f44072306186edf17a56c7fb726	\\x00800003c984d39901f2f47a413717c210b5989675c9aeb1e191245689dc150f309b4f88be3cc0bc5385ae35b143000867c1aa018d802ff8f54caeacca4e574f8c1aed71393ef77000576bd8d562cf519106fa5a39f01755b2fb49a30a7529cd00b94b7f24942ffa74e9d903624a5baf5347399e67ffa16ce78589e32b506f4addcaf84f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x48c3b748634959dad32ab7164aeaaa736b7d4e9b4d702145804e9cb719f5615e1f1514797e169de14fc0b473633ec3fa9e6b55a4df386da6b30c9a2cfa16e30d	1619123587000000	1619728387000000	1682800387000000	1777408387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	282
\\x874e2362ca04a40e3cb2102f709bd35ffe8c8e199fe07de724f678de184c843db5670cfac6164219daa6fb6e65a6663c81e266a92a9b326553a9a526f932dc77	\\x00800003a7f77c550a03082370b42593b8d3151a79314d2c88ad7da834d604708e133219085f2a6b2d6037bcf4ace148c6067aceb0b7731b35d9e017886210ffd229bb27cdc7dad2303c78ba702a953ee3d7105f38909bbec6b706423a459d38160a119efb065d5da58831d6206f6dba29ea276a2f1e04d35ddee90118a8534d39fc61ab010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1e83ad11169a6bba659e8adf3690df40dd90b6e477ce3ebda4784c1634452d06bc0c11ad3d4df556eff44a7ef37baf969d8aaf141eb4ca0f458c391dad110002	1622750587000000	1623355387000000	1686427387000000	1781035387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	283
\\x87c22ecf187cdcd4c6fb60480448dd7557465da308b1f1a029329738db8c60b6c95c04712839f8f240082f50711df97885f83b9d3767f3acd47a1c77e0b77c95	\\x00800003bdf71cef773d166e157adb10c54d2cbbfc635d6b760707afae7d6abf7cbe5d7af04141d615b5be154c53b825a89b220e16fbd05df8d744809903251127558f7dffe674aae837605cf662156caefeef0497d36b7ee4edab385961c9f4378ee387ff964a63907720e43c667eb87bc6982aed166e10b62812913ebf7cdba6eed4d3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0e72b285e0398ba85f82c4d3d254bddb270b06f8e1153a42a94859b0b96e5b239e3ace080c933fd0353d205b28db817f5fa12170b4f0e0a9b529cf093ee99607	1637258587000000	1637863387000000	1700935387000000	1795543387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	284
\\x8d4ed1c090d266f39c010859acdfc9a1d9d0fc788738be21ce7bab5565c0310ab55190a59712a964a532d253a1d664e0aa8edd5a5a5266b86c1b2ee30ba24b35	\\x00800003bd19418bb31bfbd2dde32a63e89187f30dcb9b52a09eced50a7e043c857d3734b9bd195c085ee9fc644a44fc07bc31e642bee124bc575c9a620c60d2dc7ad60863b6bb85f57d429941c89bed6b95c9c973a9e456296923a4274994b0726a8c2797633f35aa627ac4f69c248ab3e00eebc601ab3d2ddaac4b9b2e9dc160264a85010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf4434d2f8616a9cd06eac11c2483d328115f3b0ee51cc7098a35494449987cbe6ae65e10ea1b3c6ac5bcad1db939779f1fb60ac649ce3c683a889d1258b4c00e	1633027087000000	1633631887000000	1696703887000000	1791311887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	285
\\x8d26e5152de9ac1be92dcbb2ede6d23c236b42afaaaef2338a3b908dfa65532c05df2c62c79539eb94d62995e673f6cf134345e2372236a38a8c740720b5938a	\\x00800003aec237b887cf38dc87344a0636c9987f03483847d0b1fecd904fd31b67adc07b131b7efe8e8d55046f0bfd9fd28da9739e92d84053c5ada69897625d1a873a0c7746c5d283a89254eacbf45ac2fef6e67a5ba9fea5bc3f29bd5439c5c5dc0e186e6012e1ee1dc6969feea530ac1d3b1c29c519884174bb907284acf1a9ecfbbd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xecabd8318fda7c51d01a19f177d5e6288a696e0d8e265852011621661d7c219915ee278b9cd997eb0a7937c5ddac2119bd459331cecb0c98b9f368d7e05aae07	1614287587000000	1614892387000000	1677964387000000	1772572387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	286
\\x8ed23eb5cd7f957288ea9b86324da52f97930303c736dc6e174791902528e8a511b032d6224bcaec15c5ac9d5098e0a7e94de3c65e999bb27e5073afd73fb044	\\x00800003ba1695a1421b65a1b0e065964d2f269ae4f0ba841f3a3dcfb20d9ec092a3fe90d1854a7c906667e8f0ca35d5a68594e1e547ec76f142a663722ee595810e3c4fb16ff9e3de32776c0b5e242af1778c0a12facb80574290af02d4547b317659990aa70f2ca09ee6b6d62531d5a557ac2623de1912c1446ca6819d61547eb89569010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xfc766e8c2d31760b33567b6beb079a148500528362c51bc76ced897473a067d8458a064bbc7c958aa67ec523fb602266b6186e5ed11e3ef82ffff296f2240409	1615496587000000	1616101387000000	1679173387000000	1773781387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	287
\\x8f6a122207a9f4d8d7d4f994ccbb93c46c1950bf738102a2f4f22c75f48e9f890600b160ec54a76ab45a4ec6d7b556c6e70435d789b925f8823ae3cad9f5c75f	\\x00800003bb0948257b3d41cd4ad4e7b071d6bcf9cc4dd93f49c7c568c52ef8a2f6e486b865e25416d684b785e73c3a59e8bdf3b9fe2eccdc3791f923104e27778531e1896ab9df4e50876aa2a8951867b8a1b5d100f90bd914e2442d49f0bb52622262fe7ed9f8f0fce8cf6d3799515d621b3edef05cec0ff800ac799e7228d39e3d16c9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5cbb272f1e97a9ad7280912313b597fa7080efb25110e9a90b8091de8e5a11769d84b70ff964a3c21e6e067138ad92f22cb7befe269bd03d0c827bddbddf3d06	1640885587000000	1641490387000000	1704562387000000	1799170387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	288
\\x8fcaa4b1f1ce9e52eb4aeb8012a061bd06faba20e7783a54aa9715fed8e74b17427c6a0ad99a46cf1f86b12a508ea1c022937d116b3a0638e799fcd50e455983	\\x00800003ab75802eacfb95efa83d42cef6710f6daea8f24b78ebe35d01ebdfcef5031074c6c8163359a7018f6a5ec7d8dec0359823bf63d079426fef7a269865d29c43b6b8d68d6d662dd3b1bb67fe1b3334127dc8e97e8d5d7dd473f8ba16c0fe799cd648b79bbda3647aa16a6259c4d1947ccaf4551afc2cc28ffc3a69368e67985c61010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf2e7216943c36f4df298c8d0a23985726976d47f0d53c23e413cf9fd72b33c0aeee805d5f55addcdd19f02dd50456f4f5cac160e2dd093977e0b1d5c70d49704	1613078587000000	1613683387000000	1676755387000000	1771363387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	289
\\x927ab7d0d30224c3e1a2645d44543b8416d046eadd8184f0054bde2283918adebb5cfb0d72d2ad33051dc9a6d287541631fafdd5d1d3cb2482b93f5d3971545e	\\x00800003ba979b05337454c0a9cfc9e7fe39feeca904c4534a6cf49c17bf8afb65e6aade0a2d89b2211beb59f4c944c15a51853ea131ba83bb3e8e1f0abead6caefa57a105b9d61337c7a01b60520c126c7819157a60195e9433b52422051833e5d0cff78e93deecba12aff2297e3187bb8cc4fa2ccbb7625d3cebb46b9ed570d77cc51b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x13de4beae1ee45057867de87101425aa1f2952f4c3476a44b6f622b705450b83fec0bc7e3681a84ef2fe5fc9f47e326c89e7764d4a2a1dd958d8eb8ebc172f05	1636654087000000	1637258887000000	1700330887000000	1794938887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	290
\\x934626a7c8516ef8cce7948b78564780cd00dcf217c4c190832b371815dd31f93580e49396a544fc4d6b209d6c0174142cbb946403f5f60f0f390c5b05dabb48	\\x00800003c43a01c51594993803345d61209b65f8dd7c661a28e3c2e4f19b37d8779052815cc6d0fb260e81d9b3c185beeb3254293b9bd8a856134b6b50fe8495462e1dcf93c11b77dceb8af7be5c7c37b2aa8545ee08c0cce31741a3e36abf4e458891504e17ee472b918be5319fa400d8c384ae78be7128049e62ca9128705260f2a665010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8c3dd439e4105c6054153082e3c087743c59cfbd5424d585854c2a063ab37c58ced359a8982138f4c9f00e653808bad53d43456fcba7ecfb6200ad596c6e1703	1618519087000000	1619123887000000	1682195887000000	1776803887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	291
\\xa1ce0b76cf62eaf5d239364da44a6037ae9116f1b8625ef70d188be6ad180c6d420da79d584b0abb514884d0c2d11687bc123c560caeb99fc013e69a3f25cfa3	\\x00800003b3bc0c832b6410dd904e5b4242feaa0f502827109de9240b68557bb07ba8fa611c89f7b71a592181254f4726fb0610a96b9307cab4a6462339e6779ecb0f03bf02d201a10806d6ef1691ead03e4e67d790af009f86365f75517ce3a8fba5e7810ae8ff9338ebc3075ab58f7e74a68ba782e68e786459cae813699abd1420cd91010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x16cb4139365696ea7311aae620cd8671831089f248dfee5018c06cb995a4bc568dbeda15feba47a6504ad25d8cdf69839e45ed93e19053ce4c3018b331710f0e	1628191087000000	1628795887000000	1691867887000000	1786475887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	292
\\xa4ae5982f377c031c7561aab0d6a296c64380c3d9752b04f72b78512101798d0ba7942798c73cdff7b7cd8f5adb3836aed84bb0dcabd80a082d4f4e097c1ee3e	\\x00800003cbd6a886646b38581ef167b21c28a22a8134507d6c005a43a6b5ebd3c55d7d8fe3d90ea11d30f54063d1adfa304021db6922edb4037561d2fc230201cecc91cc34c43252994cc7a19d906d8d05609ca0cf7f16351562f4df850a19953bccc566414e143ccf5d6463e6db154ac15253cc7d58ba54e369e7136dfe957bd98fc89d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbf1132c8c241d411201da85209b11fbbcf9745c8b909ba1deb80e68cc8392acc41ee6309fa36866cf944956efc085153c54bca209e50bf06a27017bf18d94201	1631213587000000	1631818387000000	1694890387000000	1789498387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	293
\\xa462a343bf0f991fc7e10de0f9caf2a95638675d7cb5fec32ae35cff61333dabab95a3064d5e9448eb3f397d49c0849d3f8416cc8d298516cda8f30141d7a6f2	\\x00800003b863fa422fd8647b8aed4b0386357d5673d4f0d7dfcdd5de146ab8a70544d1f31dbdb23b1631391c7fd7f38f030be4e30d9c36f10c774bb37ea1085a48e9f46d4f65dd542f0bc6b0646f8b9a40f222713bcbf33948497de86597daca281c53780ef568fc73756328272dc99844b58a1eb5c2122972f2a0fe1994e344ee91b7e3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbed04a189054c593ee6af3cda997a4b80c0b78ed1e2d160aff3b95ff0fec14c4c63308caf43af442a0d222be93483e995931361eb0bef185d911f82541ffa807	1630609087000000	1631213887000000	1694285887000000	1788893887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	294
\\xa61e2a08296cb1f6a89607ee5c32e91970e6e97783cd91332a7fac403c4e51c58931f4d502c02c7beebdd8d82c94fd12323b962b34d2cfd12c747f59ff11728d	\\x00800003d4bf3527f4430d0e3c361e64bc0693458989c99f09ab96b4b9849fbc340d84b8afae6fd9dbd80eb8f9ac73fed94bcbd5b558e757f306ae9fc3684fc6b9c731f4f08b465c4ba5cc6e2b8e02208a1ad2d47450bcab6daddf86af465cb5625dd2122895cc6b31990780066800db324c4419dfe8ed13456b134b1d3d17baf5799a77010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x186107db1054a7d5b106abc2085fd220cc8c1f8f0b0905a2e8814628e4740d7c7a90eb0b2b99305f8a89dae5e840c8f7a7269508073f343eda25ab68674a830f	1619123587000000	1619728387000000	1682800387000000	1777408387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xa7a66e463574c7a544537aff6a6058869633ad963364666973394ddd42a70bda3e9d171352daed18a45872b2700878b65a839302af5950f6d13d6a5c0f785cdd	\\x00800003d8ffe49889696850b64aa8b4e861b508e5dea46aac7e74c431f53440fa8833e41b4a3f159442c3c751c19268d2df8c4d072f03847d8e556acc294e22c231c3dbff39a925fafd50df38ba63ce1af31da20e1d53f6fed9035324f932c1441d86774e24e0bc2dceefbfe647e735e2aecdebfdf497f7f5d294ba71b54e0540b46df1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x36637026ef6a16ba2712ba7ffdab4d4782a6fd3678a48bc1e9cb8875e8e6dfbd699b28da53a6cb708aeae034de200d35e8893fd9dfc36aeb47ee20e77a52560b	1628191087000000	1628795887000000	1691867887000000	1786475887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	296
\\xa75a02b0ae2bbee9642092f2ae4877ba3ec14e87bde23d0841fb387d4c2030a8a625050779edf20d9967543045516b50ac175655b0d0dd57ae07f266695c411f	\\x00800003d3e12a15737297acdb4856b43e038b669271d71920615d37004730bf6f638d4d99731d5b23e64f170e0fd3570b45c5887d04c1943cbfbf5676ca81f0a237a5e2055a5b9d98e8fe7891f9bc141c1f45c0d5a57df0cf94607a9b231f2345a0cc95878be35ed9a573e005000499263df1e727ba6a514d787d239defaa96588e8ccb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb3dc23d6e32062be5bf4d61e369dcc16a5449b717737f75500e66b17170ba9972953d2e66282d0965878cc9a6c54116bce430cee6dcf70496cf3ee4b4e16a408	1641490087000000	1642094887000000	1705166887000000	1799774887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	297
\\xabfa778ee65abc074b0492e2a831eaecfdf9fc1cd0df904a615407d8ec98e202fa4e69ec59b051f9d7428409b1c2305e82d22e08ee4253182eea51815fdf06c5	\\x00800003a84e054ed69959fd21479cf17c58271eae3e85daa9ee59dee465bb1312eb40d4def418c30825488ce4e95a533f06c910ecd16d203f2a037b8ffcbaaa1817cef4e63a3b41922d5b684098cc93a49805c40d70ef5cdf7237e922eb038fc2c3f4ac84947ba07af1ae508cf8d77d0d57acb42e330d41d9e67f84110e4f760201ed73010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x701d4202c849eb2a053f90e4095adb3da4b632361b236959136c245ad11424445d61e08e0e8bf2eb8fe4822439b912cddac3852e295b7f81050dbaa94d685006	1619728087000000	1620332887000000	1683404887000000	1778012887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	298
\\xace6e81785877c9da8062e5cdc9f7cdbfc76cc4df7d0021903349d0a986df395bd757ed0f6d02d3a3bd26c1e456b1014e2892061534331e3e15169fe2d5ae98e	\\x00800003b80c445db5a26fc76aebfc558f2add9467e92aaa46103e4177ff7a61b1b1bedbdc4ce3633ad14e8d4c05bf3be7878ff43d0cb4b6f6e163318d9cc41df7da5c0308996fa9fd2d802445e38a479237cf7780282a4baa7afb5d4b1edc5665d48a89054fbc6eeccf2444f9e4b955c209920de2eb1e4894eb1cc908742ca9683d734f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc4b922ebcc29962e4c6cbe6e5e9c822c353576ed5b7008b83dae7cb6859218f7dfff9de1142c59388d9fe6e10259126eb1bda45fa4cda88f70f56112a8e3bd09	1622750587000000	1623355387000000	1686427387000000	1781035387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	299
\\xae5af11c169956813b7999ac757eb7cc7cf2d8236b0f5dd72503317952d8a1c487165bb2a911bbb9ef1fab75c19d6db83b525f14b748ac90b6d9d820bc39bb1d	\\x00800003c2244098cd9512dbe85caf6f3d62b12e6aca51e9fc02a47debeb0edbcb3e8169eb54aa0cdc0cbc916c63b427041a52601b50d92f505731184a2b6c59e53fbbfaafb4b61b51afa878eed130edc61fe72c2859e9a7815c7e0cb71d55fc74c6c7b4ebe297d22fa27679dba795fd5f5598fe2fd4a43a8d2ad4d499101bc7fd912dc7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2df95ef23785c03f7e7d652af2ae7cc805e291fd2afee8e33500bd62c29fb5474e2da213eeecde8c10a3fe771578f80f46f397bee83b2b39c2434ca6c983aa03	1617310087000000	1617914887000000	1680986887000000	1775594887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	300
\\xb212f81adc4fc67efe68f01c4fa281f836025bb97ad568f40c2d8b1f3ee377855380b405f657c7874209ee3d619d6b91f99b8b688b83ac04e59682acdcd4024b	\\x00800003b5793ae41015b21dfcbae9e4e210e221717e3ec54a00e543d1bb513ff789f62bd2dc4a41832b14900edf7f44b7e5aea82c79a582aae6f9bd4867be5f458ee8f8a8242885bb8455cb08937866ad6dfbae498ddf2b1b25af9a6ac842e46e2f61a8a9e7c7416cd6fe8071e1795b52ec357b868763ab433b79e55dd5207275b4b175010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1361371ae55dcb1903f1d677070333925b9090a75a1b6d7e10296d934ee2aa00918600f78a379e5d7b268150ab2bca88480bdb1f58686157bfac2e57565b3508	1636049587000000	1636654387000000	1699726387000000	1794334387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xb29e2c650585d3885bbea25e25eb5f41d41cd08655ec59c6ef59525ede0c2891dbcbc4176cad1b3d64847253ea4d7bd2f99852869ca100b0ef76da59ee2b8774	\\x00800003d254f3b92a58022766b783d8129f1b990ba799b4aca4bfcfc1bd85a5f0c803d971f3d77221ec06cf3f501a82bb271cbfd7f9634fc3318013c24969fab4c52e04d5e55e0b2f0419b04b57504f9c70a23b7e1afed8775b6cd7849e987ed37211fdf4df39e81985ea2164e61a919f188a74b8f9a9bcc60d973a31418e66b0af9ab1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2e24e4cc2477e8ce18fcbbaf8d69b843bdcbe3773bfd25b21389d936330978fbb00bea9b5270fd537e5bafe42a3a3ad158cb181fa40cbae448123c98e252fb0f	1623959587000000	1624564387000000	1687636387000000	1782244387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xb652adbcd0091628ad4ffc3ee4381f3a42a6734d85e0927b5da7597c967a698388dbd257a0418f518e913ea1c9adfb3d1186975303eab82192715a4d8b7caf57	\\x00800003b7fe8f4d181797dda78d22db2884f462c847ce0bcea6163ab242b11f0d9341dbc3de0fdd9d4a706d6d3645498bbcb1090f764ddacab938a51d0d7b15e4f02426ae31eb857fffa88628b2e9dc01f5e729781deca5de1ccbec6b122c119c9ab46b3d4431659441ab4b516ae6e11fef10e8c63c581da91268bffdb5c51860980cfb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5608e537285ccc6bdce95a549cb115b30160aec5189c7fccf558a433cdc2cb68b20a340f713a00377ad61277e432a25b9b70cb0c017798f4b8218d35fcf78b01	1628191087000000	1628795887000000	1691867887000000	1786475887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	303
\\xbacea387664815d55df00512efbdd73479e8c00497ab5c29bddbe04f05f2df635508ba32e8705d950bc143b6b678f5e4b2ce7760c043e71e0de7c3adec33ad12	\\x00800003d71dcb735ec5ec2558643a0d025b3c5b169b0ce1b8fa002b49533450236336c375acb0545fd2f6a8f73a4aa8d2d6327d903090654a98bd4b5918ae3e46cc8ebfe1ce2fdb0cfdd9064b819eb4a2c269c53e961a2e262363e2733f19136efae6375d854ee5bf99e419d7d6abcb8db6cfcbacc863ff48b4cfdf01dba62059708c13010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0a22cb655a743f39d7453d8d75ba7ba2a08398bf683f416ec814b91fb8b07c8695daaaf02c0a5889ed763f9497adb2e850fa94408f36df6d7c0f3562a4b70009	1639676587000000	1640281387000000	1703353387000000	1797961387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xbd3a0b766b14274df17b753dac7699d6b807d2295051e93295e3a39b3779d5733d9cb01d3ba8d9c07e910caafd4ccd407a9ca7fec81d9a1a6eb491ac1fe819fb	\\x00800003bce7799d3531d5c8aa8694c3a8f7e6d8c972aff9ffdb4e6a1a6f039fce77569580698d251d70c1c7003d85a72d47b72e68e1b4c369cc4caabc3cfd0c7deca8cb1da3596f28f612dc02849c4ac7f44e48f6c301f01ae9fa3e8512cb04e989d7275e600f45404d5c503a851dde82b86e6adc0423fbd7933537118fcebb93a9626d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa3646aafded86921697e6772315d82d55a05332f932f2dc230499148f92cd3a13400a63d26039bb340bedf2de8adbe86538bfdc852152a8b88d9ee4c912a6c09	1621541587000000	1622146387000000	1685218387000000	1779826387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xbe4a5f6e9058906384d1c49f4aa591aa3f991ff3f348603996af564afede631b0e641ca7b8ad29246b65e4caf22eb6b2f521e629a159ec8899abc6b2abfd0869	\\x00800003b7b17daf8fcef8d49b12249e9be8e9b8ed221852da7b0ea4708a6dc6fdb9b50e36156133a9bd8a9b9c0841b5c75d03db4ac470bcd0d03c89267a211e9c00a42cf71d5caa89674feb76620b91b9fc68ac27e2badf9809bc82596899907806ea91fecf0eb520b7ea0d37a0a2ed3bbe3a1f076b6b840284980f650027c60fbcb4db010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4a452e53c44505b8abec3eb0d4bf7f9d38dc4a012152ad3b5729b8e16ed9549ea10e0bc89b01d20f6d06b661666de7ee88f7793e20126577935c09edb2e9e003	1635445087000000	1636049887000000	1699121887000000	1793729887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	306
\\xc1ae4b5a9b7d64afc36bd62dac8874f2cde86de654ddbbc152b197069bac89f8d34313968cd61fa83d27166109f3dcaa575cd976d5dd52e4e2bc5a3ab2e99eb0	\\x00800003b2331a8270b9f6434c5649685327b41ed7190b624d0224471bf74a559797fc524fdb97c610e9399b3f57c5f97ae2e75be70a480e408f29b8207eaff9eddcd0ad9d88d0b4853bcb1a6b2c7a78d2581974a4a72551a4dd79f1351bfe2a9afaec4422559052169b2d30163117164c11c28ab0c2c9fb0472c1fd5e548b881c1aedfb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcff65bc7c05850c221d3d0a8a759acd2a815bb3f694ca33221a2350ebcb1c6e67ac72f7e5df3211143df13db05eef49c33724a368fba1cdd71e677510425da01	1628191087000000	1628795887000000	1691867887000000	1786475887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xc246913a479e4ad45293065e4016f7d73a4d8e10c5234a6409908672d27fd3b49a5e860153ed927ec56fb23912d5b44966db5c64096deb637acf6dc535384e30	\\x00800003a9e3a4d30fe9f93df46c7b0ec2eaf639cbed9810c21bccb6d12b700a7f336557187b779777908650a815c5e0453066e94d2549dba127057b61f1ef4603b4bee7d5035940e6b5a29abb87fca916ac2b4aa1042018a7da5e00850ca38f59428758449188cb7c6ca28e6628dd0d1ccf7c82ff08b321cf19185f2b94d5b24dc41017010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xaec9fe5e75e8acf1058c3329eac97b4e7c210292c6a0c8acc87e0a9b77205a508d11aedaa35401aebaf4b696c1c2bb94d89724799c39c7375112fc8f9acd9509	1630004587000000	1630609387000000	1693681387000000	1788289387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	308
\\xc38ab2a9f15405e2e509073a0143ee6945821eda17fec00d8a81c3db9e52b77c03b7a01c1666d39c5163663b62b28dfd6097e11de8d41d0c80aa17b94c9e75ca	\\x00800003b14c1ac279f39c0094c0339249bd680baa28c0872c858e347fdd1a39a6fd29702f80fd555c96c9d9dd44454ad261be6cb29a2ff15eeb34d3c92a9de58773e18412f78f5149d351c8b13d1ea216da51036fea1fd8ad6a640fc3b7692c944cbd948eaf8839b77aba9fd13c3a6ac7a4d0fd9fff81fccafd356d7645e6d2c0b921a3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9581fe34b7f4e39b228c3383075e94b1d12bac13b9ba013b55794e521e8f001694b08bf00b129c2437ca716d3a02bae94e5356a994b934fab28b9621c3cced08	1624564087000000	1625168887000000	1688240887000000	1782848887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	309
\\xc37a8d7ba08fd30a8451b8f767653affc45a7c9c690b445f031d71240011b5f2d548ad867272c2d16b3b70e97f122b5962c9df528921a589f9f2eeda0223e7e3	\\x00800003f587ed60b8172ee11ecdf47252d03d64489779ad007fe38944a77f283b204c345fc343e59b7ba6a2c988ea0cfa8fa3671244ecffb5adc5a4351d4e38f925647a461feeb80565721b859885849b52e15303f989341348654699269aaf0dea3a8a273f7a70caa160cbc8b442df9331069e2b0867da033931ccebaacf1af611c251010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x98f80ead7b8a9c03e3fe7b7e205405f26860e9480d71f180081d824f5fb79856e041fd7f3011596bab46d3a3c50a18e9e3cf71e37ae2755bb41c06b7c5b64001	1615496587000000	1616101387000000	1679173387000000	1773781387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	310
\\xc5a210130656e40d7bde6cc44704cccfd4d6239157996d960dd6c81136de684e57b0b48c11902b2e21e8750dbee92553eace1f76cb87f7faeb978f632030805d	\\x00800003f01851dc4a1c3d189556b4d9a90a047a3b7c7cbc55c912ed55ab2944179ac0069671ba830c5be93d16f05a0d406201da9fd70ab3d32203084baeabe642cd39629955d8c985dbc55271ec5d8841a84e59c31b7d5680b3d088f8bfae8b9627f75417ca6405dfa84d86784a6af7a88d07eb27319a9145bd3daba8f27d636f54b21d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc806e83acf268426f7b28d30b8e58d813478581fea8bf583cf68d407423676b4b33c54ce928753bd9bb7859bd422e1c2496c06566265b977aeb541e39ff92d06	1641490087000000	1642094887000000	1705166887000000	1799774887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	311
\\xc68a9c4af96888a663b4a6f6e3d4a4862660090b1cf55bc8050a3d40b1669fb5fef5fb8203a19ca11dc3b55683737b6bfd33b7d766f3f4eb2eebad03d48dec7a	\\x00800003c9e472485822bba6d6fdcb0b4220bba616c73739a2fa43574cffa5418aef9147925bd890aac10883ff6ee3558c6316ed0c62c99bb7df4e77755b5c64757ab307708e80bfe6ed5bf41996e73cefba8721a0f1a5f010fe5ab96f23486b78f41d6d962d6462dfbeee4e3b951aa609f31579b1595915f95b9bbdea01c5d54619037f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd335a1a302b909273731524460da9ab24906a43dc45249dd06a7b1ddb52c2674ed4fdbe5362453a6bd7fc57bcbfa14d233ec648a94059f2cdeab5d39d34f5c0f	1616705587000000	1617310387000000	1680382387000000	1774990387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	312
\\xc726b8b5daa69fc80a6c1593097966cecd414697fee14d2946bfb2a0fb104a845c7108a07b25301af73e4e757fafdb5423f999b8dbfebbe8bd8db365562e1116	\\x00800003d04f8d4a98df2cac257d7e40eef04e0476498e545e31f0cf2c72c6417400c33ef391612fbb056ea44265910aa978deb8b96bd5315e828d00e720f8b14a04737267847b626eca826203bd4b3f8dee60db6eeeeb10683092f2e5e68d2f760aaa6b75061c334ddb16c184f6ea5ae09792bf30eb38211053bfc775e1bc9ad5df1bb1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xff9ff6020f27897f5d184ec7d54e6900bf92875b23d6526e318ce3c705a2c3944f42978f2ee59c6a917002d35f66629897d5dff48aeb43f811e5aa979513b503	1641490087000000	1642094887000000	1705166887000000	1799774887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	313
\\xc76e019c93c472581110f8f5d1ac7f11507c2e09c0c8c861981c2f078ca4c2ae6539f4b377fd6b3e775c799b0050b0a1201a155be7ce5a985e2c3d9703448e58	\\x00800003c82eb2be7cdb92398a555cf7431284e4eaba5d0001129d4b7c1147addedaa6c977f7cf0445be693ae28701aa5a3d29685b2feadaa757928e2665832ae4506730b38cc74b286043f12a2ec29025710a894622b1f7345958b0ead5e1be65e823d321b735cf3c8d25e16a94cd25008cd9c101d584c00cecf3db22f41585c701f6eb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x37e3a6ff00e66d8e2bb6b694236175cea8f6e1ad6eb4d629febbe5610116ce908a7276a9204007d681c474f565d2f34913ae9c8e01f05fb7189484f3b0cfa404	1616101087000000	1616705887000000	1679777887000000	1774385887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	314
\\xd06abac0bf185e173b2a73498e33ae540dc460eca0a24cbf04a3181222e4b6ef4387103592afdda23da78b85f367ce9e904f2edf0f23d435e1afceadfb672de3	\\x00800003af68ac61bbfa0ee3dbbf3d58d525398f83f2ce1914ee7416ad1d95da070dcb0ae5d0e33cc905266f28444b6a27af7550887a9d935fcc41b0f0c5c607d4a8cdb71cf660a8db4548957dcf4ab223669553066854f581a1e8f6eec3bb10c0c15d413989d1e52fc54804f7af1e934b62e091f220ad3297308b5ff6f15dd06462602b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3bfa41e908a606317e3450b63e94c2c86ade55636ab068303e6201712c8357133f8a6ee1c410481025375fd1aea5c3d25f93d0f61ab58e207ee39504a6b3d003	1629400087000000	1630004887000000	1693076887000000	1787684887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	315
\\xd02a0b8d3962f142968f953056d009de3f9e83e3299e78b621553993997624719af0a13877522278c95549c69d29aefc6a2b1cfeb536e6c783567950b398e93a	\\x00800003c5cf9de38e2128e8ad074eb475bdbd9707ce996778753beb02e424031fa414d1020972d9a7fde07f640eae9f3dd9a22223d8b670a066547d9b922d34e8541ab0c36b1ad8ac3dea3622893d37898b6cc0f932124169561f12e89961ba780894e4dc03e353c98f23d25b792728ba301d1b99c8896e2aa2022ae6373c66df4b77f9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2204060a1ac2a598e56d16f4309ff4b9ed43b45a4327da42623d45b8fe22d6d34b583dfc1633f3c65c3a43e35ddd00952230e30ce39d5b3935d400c24568a003	1622146087000000	1622750887000000	1685822887000000	1780430887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	316
\\xd1be75e0355fba4ba5dd09bae8534b4fe2bb9749bbfe524c9bda6bac638579874907bf63ff546480aa40f7f83d5a597247a2a33e2de7f765c1ec9fae5610a3e4	\\x00800003ed6e8c5593c53d0c96e04be1eb547ec76336f547e231d622014a7d5ac91b7323ba1abd7a8814c94e0add9ff04ef7781817a409e82f1df88e354e1fd3aa2e764344e3e3d8403776cf8ed9fe51a642079de52d5fde526711a41d6fbdbd7ce4578a27f2b8be8bd47d7bf6eba3688091b0489b19fe8304688969b4044f1f58101e3d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdcbf1847c0d19c0734fc21d82d71a13f26670f72c5fae9a446af51811d01081a6fec729e7067be957e3a60d697b1a023804e75201c9100afa94fa7c818ee3e0c	1640885587000000	1641490387000000	1704562387000000	1799170387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xdd7a1fbfad8ed04351161db8c1e76296e1ac5bb97d4ef1bf24e215b83428901b43d141ddfbf59aad8560e037c8d7c274d8de6b9eed5c2d82ee47d4667050d415	\\x00800003cef44e70712a38088b9bfdfe4d59f42dad52732d773ff1cf30d2e67ad84d9d16e356ab1b9d9c331ca4cac164cfe638007ff0c904ad8a0e32a1b19d7e747757de0532f078de389fb3953d20680eb01e08c7346b5b3931e235aeeba7331df7cca945e8308d281ab97562a78e1e533732aeb5f1c26dbefdcbde7e7bb6da6097aa61010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf222f5de68e7f79aecf971cc58b782c7442cfd63b59827c92363a960bb873557b127f7aea99603530834a06bee8fac62580994f462d6cffc53664ba9f62d1d06	1639676587000000	1640281387000000	1703353387000000	1797961387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	318
\\xddb27b6d8d7828b8ff31d58110c1e81a52fdce6733cd13f8945469f485934c3393a985ff33907c49429953a800c59c1e442ba1468282da9a5451b652735704a6	\\x00800003b931af6dcbd972f3bb84fb7fd49337d003a8653181e99815eb89869c804632574c3180436891fa7c3067a54f3dbadeed7d43e899767984119814a9c3a2f1a39b4a41915f9efae0da8efec26a8dd2e7d0dc1259dcd018abaf86abbcc20026ec8c203699996980a8372932d52cfb4b59f86e947fa78fff48ba5e377c1f00dbc6cf010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2203f29a22f3f24a6d2a1f30212572ee299676ddd5755839a4669edd6cae0d494abd4b89af2a19d720c6628ad5d57507abbd9e2d5a74d31d129de6ecefed190b	1610660587000000	1611265387000000	1674337387000000	1768945387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	319
\\xe02eae929432ed7139aa4655d9a37be31ed4e42d42c534ddd2068e9b9c888e727a2e7177c219a42181381916419f5c69b4f60ef9c4a8329051c3a324a5d61992	\\x00800003c9ed25698d4395242a6990578d4145b5a69f0826387eedba653027451a7b7365cd0f2e55b26441d5f0c71e5154d2eab5c108791722c80f7eb72f773a85b2b9aa31b0368703c6f5d622e9afb93cffa72bdab4c64a314a2d7cbe4623e9dfe87e702d18cd6c4c2b231eca18ddd3c7e6c427f49581fa618779cd1124093dd4b3c70f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8393acab416995bd607d5e44ca4d5832b57c323b6aeab79c23d98a67024383eec79f7c7f04bce61293be9f3f6e3639284edc8dadbce8472b27496d5bb2c9f907	1620332587000000	1620937387000000	1684009387000000	1778617387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	320
\\xe29619ca8ce6dd0b84b09a06d43094d186e508f55e1ebdca6c6848e3a902113baa89fda6c1f7a9a27c85e2ae5cb6b0277584991b03b060e42ba91b66eb063a59	\\x00800003bc2a7881e54a63c127ad9d28f197ce83a86eaee0b587f104aa361f4a5431a6d31320c160d9b92c4779c6b86dc8f19678193965660c43a589aa0aa0044d6bcafe017af9c4a9c04fdb6c609b153db6e6b7c2e829e0c0cabbbfea34135f0f61f07a650c00361582b04ddb5491d687f03ba60bd4099b9583ac6cd559c849c940551f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9c159a21c206873daeca36a816370f9ed2f505a031d7c5c8480a0877e21c516ef68536ad04fff03006dcb5c3e9ab7a76fa04ff5b8c688f181f90edcdb2086c0d	1640281087000000	1640885887000000	1703957887000000	1798565887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	321
\\xe7f653d947a432ed0cbbcc3a363a2aa82f45c4b15913d73d7c12c90f99fffdfb2086b050369fec7f068e622cd6d52c8e134c5bcbc27f89bb8d7343a3e57e0745	\\x00800003e0eab05f1c463d6af8778a5994ee15e598a60663606b2b0e2be43010fad0c6436167ba48257c9ffc4916e7d62b627c4c9c4bb3c6df768ddd706b4f2103d0d6b353c528c6e866f87014b3398969d55afdb8e0318f87c3f9f4389142502eaf30b603eb4018588fb352ef288e181ec724a000c75acc6ef53bfa864eae2ea05f16b7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd2a6ac53a2b4e0b62312abafc823885d412bdbf91ff3bdbdb0b59da7c3a63de708eee392ea247419380b0706b705ba11cdf26954116f9e2f8dab423bcc65fc0e	1628191087000000	1628795887000000	1691867887000000	1786475887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	322
\\xe8c239e3ef43950d66859b9224f51b5651c6ac837bb7735b5d86d780bd7cde86150b816c24fe5de521a757ecd0f19a7bd35691ecaa05e95446b9211ee536d748	\\x00800003e4f9975c7b8277683f3dd013f0415701631c4842c75e9baa28ba2ab2acabb54bc5c8a906cb78a9e821036135ca9737637f9d5ca14573d4189c3fec3f3806de29144e4752c42462baf8ab3a993bb46a72bb01910f905ece6c1989f16c1a5f23958fd8577b8f60f10383a63633ed4e17d8c56b5d8e7e2c37a0c4de3a04a943b64b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x538189fd4304c9a210eb6709aece94e74becebaed5b0b01bbe968ba7a1a43288ee87f37de2ce1aac840d1906115d582957b6f6a94ed8d0ccc7adf38e0c6f4501	1626982087000000	1627586887000000	1690658887000000	1785266887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	323
\\xeb56f374bfebc94f508eec8b9bfe4f778a87b8f393b025aabe268a3bbc9604eb9cc3d09a13ab82488ce35a71fbed94223b08321e0cf98cd44436e4e5384e8488	\\x00800003c7e7fbd6df8e7f53a81f5483ed3b8ff8bab4dfa9b771926579ced23fa8ef9aa2f68e8987d58a1c29d4f96395f8ee46351c944a9614953f6bf6d5ebf8947fe5298059948b1b250a944fc22ab30f227f1c5a76e301cc8ab2ba37b39d91c1db1da884eb3040f8362d8a70d136427fef929ae93a4ecce73fc34c1976346a813e1103010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x36394db1bd60254637c27c196cd9d19e12ae6e35616b1621a4bc86dd6b365d677c0fcc6a398f80b4815f23a669b19f07d3837366c385dc829f28dcb0b68a7705	1623355087000000	1623959887000000	1687031887000000	1781639887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	324
\\xf386509dd22b994df92215b88799ab1ecbb834a48943d94ba7776cdb881707f4e43c844df31db767193778ecbd04a4111bab6182e9488c1304b1fa456d8d118a	\\x00800003cc315e9f0da584dacab502ec220340967daa12a59b0cf1e2505d473fdb9d4526e77adcc7a60b943176c684f3ce30e57d8fb3b1a55032804aeee46589b4421b6d173f2334f32a10b62f20f7796ef457e26e63e1eb30f53eeb50441de6d4c34bed33f2004016bb27c129a2e6abb586e1f1c984b80c8f84c2a25c6f145b22637c55010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8de05670e86749b630e792ae62ab170e2954a9922b521365a5d8bfd433720a3ebe468dc59f9f932ce02a590abd3a21ae19797d712e58df28db335c84ff62ec0e	1622750587000000	1623355387000000	1686427387000000	1781035387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	325
\\xfee29a7def706bc310ec6b022794a11d5954912bb429da0802672306673298dfcc1da48738b5e1c0533bbdec6224f34a5e80aa363beec9d190993bd225cff6b0	\\x00800003e1c3f0dc85dc97fc29534e87566ad238b1bb3e0622bd91ea2efae5bc44997bb68b17be3f2c5068ff5a2c4fbc6c1ee102cb33376ea075614b8128860290a411887cb04bc687182ee5859c025e764358b24f016ba0c54ed8b4a6cb0dbd5f2c87412c65d8167f4077389615324d3a79b8fda5f463a03f7a5d6d65e40b1ac80d3e3b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x509c75493d56aead4288d3e371354f8d9a3f4bc6f1fc346e44a201376271ef3680dc163c0566259c11dcfc324d72ab8beb65cec5bdbe16dcec1c46061830320f	1623355087000000	1623959887000000	1687031887000000	1781639887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	326
\\x0053d82434da03b4cc8118bdcf6b4c75dfa95b74e608b134b3cb712194eef81423ef2156c4b574ec98049894d9f54cfc20ca1184635fca4ac89fca30a0cdffde	\\x00800003bdbeb61ca8fc394fc9d0bb116f26295c9a9926931796a96eb9fc110b18e89294691483a3f24f9b2a467bd692b840dae085f5873837c03c2c3e16eadea8d85499e6fc6c7c6591075771ce781b90508bcf86546c7ed7aff827f4fd18545f6c795b6238d310ce15fc40ecf663aa60354244cb8f0cb9bf26912d7375b294744bb067010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6a259f77ebf197e93765904b11d5375902e7e8e3d4e4749a63134604c7881b37869509fefa6c0eda7009a5fb9d7cd7d6f4ca71f49136453cd39488c9da521609	1630004587000000	1630609387000000	1693681387000000	1788289387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	327
\\x07635dec4d4abd28f558331daae741cb38758be1ec2d08ce09e33e9cf993006cdb414243031a7e234066095b66ed5e0eb437cd2f8882e6a1d8bc499519269b89	\\x00800003cc35ae92e0fe0dab17740b1f94aeae00ff62d3f3b51451a8b3482d2a4692653f1c8cd20612a5fa7bc41c7d802e679076d9858c9772cd5f4db93bdcd2abccd237886cb73ffba72aaf012cb2538057219ebebfa9fba2107adca9379220ef41eeca6faf59a9b1a1159e1491b212f67140973930805157950b5574ff7c7b85bbce7f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x23abe8de3ac67f9bf4feebca79ec7833b4fab59fbe4f9ccafe3502dd6ac8cadcecd73867adfcf01c0b156f24a0ff391e38c704d8c38131490a6c0a5f99439e03	1631213587000000	1631818387000000	1694890387000000	1789498387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	328
\\x07d7b6b6110fe27a5b0ec931a50df975b88a47b82a53b815955f9b6c138e7f99dfc32f3afdb4901fa51ea258ce9a3d286a806b3388906f5ab9678a3f51147f5e	\\x00800003a31b942c04618a924f3e0b87ce7ddd46f0db5bd992b6598632043d37a8443268ce5c81aed24b1a9d8cb68260038f179e2720ec0e1789d7a560a104d7e7eca843c10e280bef4484ef3a7fe0e88a82c4efec9ca919d9d965030d2f50f1a8b0cd41357bc0f5af59cc7f1e4549a28070647787c634591f52f6f061e42c47a747979b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3e5a369946dfd1fd9e8963601fb7465159e6faf47c9ab4206696590104efbb4b43c7f1f16ac107deadb533675105c019ae6d4c6ad45171deb915a49529fb7e0f	1640885587000000	1641490387000000	1704562387000000	1799170387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	329
\\x07af7e69feedcd0139f8f27d8d5dac93579488fecc298428317158a9572a9558fd9b22a0a659b5feb9ec2c04f4983087eb74c55656f70e3c4c8ccac8c731a62b	\\x00800003f878996a89dc4d934c690e0feaad45a2ffa50cba708d699d3746b14dc721dc32b5e9d8c14a0387a96b7d2268b5728b6d226e23a867832498e94d00bd909d5a1d8e55d2f2d67bc34b589808a2dfa9e0bcb3a2e8a84ec7e68daf962c866142147ff2f99b0a2d31b56d4a2e6011f93daf1a2ce89b24fab3729529a7e483a47908e3010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3a04cc8c9eeda1567d01387905a7239c0d2003c7ba61cda28eb77c057cf0899246d73ba53a717714695f17856485c232766d58bec615aa8a6bbd4681a69e120e	1619728087000000	1620332887000000	1683404887000000	1778012887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	330
\\x080f6050d4ff6a61dd8dd50df4a1fb8d732de88346342fc09b932d269c49ab2d68c539d7f1183cde58a708719278724e9e177f3daae6600d0110d2eaff7f0b67	\\x00800003baf6853a4c8ff11315658c9dfd5e238b212c78607a19de12c106995979d53ab71b97b5f073ff5b071a9ab3b6119555896e28dd7cf0d31c60059ec257616ed0766ab9bbcd3a06bb5002382ef5a5529a6169dbade46bc326c5402e76c1bf09f56658f8bcc92c5c9b0f206680911b7a782352eb4e2c4277b1df5f05541419183a9b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xfbe28876e7d727e1e87dea377778adfbcad2e9935708d9cee153ea4c6b3b93a7ceab0c295a034800543ca94a44ab82886c5b0deb147b11cb248b320e2aff2206	1625773087000000	1626377887000000	1689449887000000	1784057887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	331
\\x08272fe5639a9321040898026ceea3f274738d5ee91bfe866c3aeb4d4c0a0bba98a58e5b3ff003eb8b991cc3846380a6186041da1b41d4f161b12bcab30c508a	\\x00800003b16f0fa106ca0eee9a5ce001c4eff5a9759422ba0a685a381f137168a4ad2a59a08a298872d0ef42135d45700f89a41c32b7f29ff00fc6af49e717f712dfbf736a73993809e8e54f6043183c0d17f6efdada2884ab662cb553272d742e5b50e2c8fae5d2ab633a21bc87e8f8f4df6bf11ef44995a67f537b139aec0ed33851bb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xabe7b64a96dc128d555e4eca0e370deef07d7ba2036a20b357f979ceaa3a7dcbd10ff0b0174413a0943b1a342bbb29c72c2f621ddcb3ff142d4d3f725d679201	1616705587000000	1617310387000000	1680382387000000	1774990387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	332
\\x0bf3b77db10390b285e540988ab8f1591c1117e5c9e9e6dbb6536ba1eab9dc8a711cc767d02c5d8fe3ffcdc36f759d56ac6f07faf0a12a2fc26e7f67220cc86b	\\x00800003add983b6324be9fd2178b926e78c6908d6cb4a031480fe4a4af9420ea08f5d56868a6b23e5c6f83e8b1224fe1a3a69d7a4f3d53e1e17daaa374c2b7b2f68c27d4265f09917da8e55a6ac3875fdf6dd20fe2143c15f749d1b5e016ce74cc7e439e7c81ea4533ea52d60e13adb5fda8073108b30b1d52bda55b4d8deb25c631617010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8e69a9500860d549f1f43819df6b79d559015a47c9855d59461341118cc6f773e02569680aea010d0be3afe905d86ae4011ec21e9336d78e593c8fea0c0f990f	1637863087000000	1638467887000000	1701539887000000	1796147887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	333
\\x0bbb5eab59e369ab0a09dc51fd0c893008416d11ea3e72ac4c223bd394e9145d024cda587d396c9fba7f8cdfc4c34694de329f0a5619e7b12a98b73c502491f8	\\x00800003a6686c7cc6afd1ac7a296713a73c38e7f779f8bbb186cf97a015de873aef12c93389d44d859090a0a49820ed0bd21ffbfc69dd6f3e554c4d69bfb735aacffc67280ef82bfe63510a64b1624fd75aaa492feeff1d2489883615a195e2123646f523ebae9a6ec8494a685d0320f8c1aadb731e4bfbb46d7461138d57c5b44a602b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x56c5abe280e08d50a8a5547f3ccaa339106ef2243b5d7976fcf44e9d1147895b08d23d3d4dc4d1303836a956099ed3b9ec972558bc36284fe686cefc523d840b	1628795587000000	1629400387000000	1692472387000000	1787080387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	334
\\x16bbd70cc7e8249b2c1a0f12fab8be0c930f83a93538e8aa040cffca4e10422e774678ae49cbce79bd9bf28c1bbd105add5f31dfab19db75c711a65144d7e9e7	\\x008000039c99ebf57ec355dc3b2dba9b1adef3daf61a5fe9c5a396d716b1151b127d7c3db2e2529c16f7c489a5d261fe023c0e6f0b9ae9bdd70a170054dc12e4fb3b99ec7e25cd9209afa28619a9feeb61c764dd70a0bb47864f1ac6fa7b50a6f0a3d6aeaf159e18a1ac28a76d8f95372fb125ef0d9bb8e722a055380fb24aad20087a75010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4be832ab847f89975c7aed6a1b92abd12660faee20b0adf84bbdef73f6380158a895e0b98df3a5f77bed358cf3656909d6e30fce09189782bc1e515fa4df5f0f	1619728087000000	1620332887000000	1683404887000000	1778012887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	335
\\x19a374f5df31dbbeabba390a1926b47fc72e0886334d17f2d6056a451b91abe72d3b5cf1c3ee5a8f78634451bf348038dbb420fa61cbe2de3933b487b0ca7d47	\\x00800003c988cbfed7cb223a6dda41dde11115532ac278a6187f070e162f26b9a95c996e0d08fdc8c69cf205a69c5729c6a4da15dfb275257a124943fd84b4559cf5b91ab25c64b1679fc3a1397baa8510911f4c1da361cc26a896ea9e314bfb1d0e7934e24bf5feab704c0964d4ac64ff0286adb6d2b22c47571c18c119d858df0c4f79010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xbe23f499c2371f9619301c6fb95ecfc7e72e7eaa3447a133b1103d9b547b6113312a034ab48ae2cae864f214a4291c587cb53a5eb6d7f5e1173f01e05a81d904	1623959587000000	1624564387000000	1687636387000000	1782244387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	336
\\x1a8bc43c43115484137bda3d48c6bfcbc49ad6c1db71303662348845559c6ef8f7baf49504ad412480f0c19e96eee9cf4919bdcc14d182608c54f7dcba03f4aa	\\x00800003c7a398d84ad15194195960f81276a0b16a3e75ce7be4b15a8dcc7b2ec72ba4760890c268423a422b17b7bca1816c79573659b141bda8c1f7d61ab6b14241d17e20ca4f9b757d95de2c4b4d90eb0da5cc036c45b040ec5b2e20581e8284f4b2d01e92086cb5396889d7a351984f38077f5d562654206eb2dcc35a6a6c6d3b65d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa208cfdef301f55acdcb41fd234dfc52d0194950dddb3adb0dfa046893fc4cc3d2b9a6194409ce52f19952ede49690a6b6d5988f5f26c38cb7443c22b11c8100	1619123587000000	1619728387000000	1682800387000000	1777408387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	337
\\x1aeb02759af7f4f4776bff994f66f883987c6053d9ed3a539c2b1aa1370bce60abe96e913bbb55946cb34a3b14632c0dbf0773d264e911509780d6b5df4594aa	\\x0080000396bab8a4bebc797d20add6b668dbaa18bb4e9b8a2357473989732f872380cb174a5daa8e0879395b05fb48d84c1b80bed8e8932338772c06766e84ebd99f07998925397d00e0fc34514834b944f68202ce7876bf1790d251e94cda2df591355965b2c7416815cfb912a6c49bb15440b79fcaed1578c9e832cc27c1cda3745bf1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0c004f01bcbd0b5cfa594c3cbec2b0b5b0184d3951c3816579e7fd6798e4c417811dcced24d11bfd08d1022181369ea5a799b4828e8da5cf25a679f0d16e5408	1617914587000000	1618519387000000	1681591387000000	1776199387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	338
\\x1e8bb962e8200f0a5aa7758af4b7cc81f9249b8a80afc68cbd2ea92fa6a0fe423339b094bb64e7e8c76165b2dba4bc2c52596b5dd6045890676af06600c40ede	\\x00800003b006a0db1cec70357b82c44333fba673bc374f7cfda5729bb1c7a2f243a30e090061a0685f384ea5278983b7e9fd1a4e571911eea615f38df9c2a1b21d4b09b87a1a6c5ccbc58afa930b35ae866a1474c718d6f5dcf852a6526303edfc92efeafb5d003ddf3b1b2cfd7120b22365a8f18dfb277d1492812e705a0e68437242a7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd453dab540bef6fc4d9a11398b5bb46187207680f72572bc31a80c19c6dfab1f2ea94724bf99faee8df43b55ef5febf0463769ddf1257d6e66f975d19e948f0a	1622750587000000	1623355387000000	1686427387000000	1781035387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	339
\\x1f2bd56644d2c5464b3f4d9b369250d138a7e65a64c2d320ab1a91d248e998a51dbdb14063d4c5b1df3c9ff64298ab9b44cf3292f64da75699e96feedbaa7968	\\x00800003b486ecfe61fa65271b46cdf3e9b70a093771ce01e2fa56c0de5bbfa028234149ed2528dde0a03aa9af4d8a1cfd0bede3b0bc1a8ce884863761bcfd6befaba91e8a5f744bafeb6d12ab7665c17e7c19cf6e5f6bef613cf3710538b29179d25c1664d466ec2b712c53f7581be1ee380cb14f578a834c7db94a07bc7d5d6782bb41010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xcb028a1c1490e0bbfd2f01d7ce01912b5b53dfef056868ce201935677426ff13e4dd07941d19f723b52d3c8dd8ec82b36dd86edd157896f0b8dc568601f1a307	1621541587000000	1622146387000000	1685218387000000	1779826387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	340
\\x1f739187e977aad016c70fe3299abdddc595ae82293ac34e426794e4b7a6dae108dd81dcb4590b4b34bcc6145c4cb6efc17ed29018efe237b1bb2cccacd0392f	\\x00800003c2f5002c1226bd293962f143bef0187d812a4ec2629b3e61a2563cc9271e8121035a30f6797a3598cc55a04df9ed8edcde75b0c176cfe4b497aac5be682b27d7761d0458295ea2e49653310a08d8c9cc1560b8dff961988308f68f1cea03b4fd45a5275c4abd71c8e32d76f32aa4494c8d26e474dcc937cac549681a4bb58b2b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4801e23508886b919fad83d419dcc0d42d2bbbd9bf787a08069093b8a8316f91bf921c96e0c4c9062cd3a42b3cb0d05b9629ccd8d50a82955009cf4e164e5a07	1631213587000000	1631818387000000	1694890387000000	1789498387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	341
\\x204f0f742e53ecf803a2cf1e1da923bb2706dbe0818f4f2cb43a26ff84436a9951943b6ce00da75e0efcd5351ad4b99fb7b89f13aca25fa242224048ee17f9ff	\\x00800003c3699beae7de2526d94c0dd74c327bda26073b29757efeba34a8796f99a7a5db49a983169533ba6668b9d4243da32b89d665ddc064f6fa5ea51ce955767579cea29cc657f4ded6fa59e29a8158190bd68dfc8f618066b1521c7b924b42732b8c9adff021e879f8cc8715630c217bb1d3fe351191493cf45d5b6221cb37a6f66f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xea6714e00759e15d6aecf4042c344577873fa6f50b4f192eb64bee39172442d8b09ed54951185a0cf87d734d021cc73cf8df617872a410a68f29f6337a2e540d	1617914587000000	1618519387000000	1681591387000000	1776199387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x204b57b821247decf46ef8a318d596e971522147128475adba5288fdd58b3d5f8ab172846e189b969d6727cdb74ef0b5d2e4b4180c43721abd9c722d936c3d3f	\\x00800003b40ba89238a62637f8c9f7d38c8fdf8d9c587ce8af8c67ad728eaee2e933364356459f12ce6dbe96077bd04c2dd9b12e642cbb2e7b92f157e4bb74b33f74aa6e7b36feef27cd6141369ecd0f24cb1dcf3dc0a8de4c29df048f6cf78cb80fc4cb59104ef225ac90afa58e85d2c90ba7647da462ae846f75c809ac4145dfa4eeeb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x54b12b55970e9657a7d30fa515e367d2a306586762c4c9947543b9a14de55a87c628a55a39b31cee6375d392cf9ec049dccc2f597a127609a37e4aa04439b60d	1613683087000000	1614287887000000	1677359887000000	1771967887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	343
\\x2b83f5fc39a94a44b53faced9127314722f608c5812fd3426ba9ba1b08ef545025e469d50c09d460c41bbfc7e07c395e131e50ee4ac3a12de37e6a4ccb6e0b87	\\x00800003c49a3a2894700f914ee00951e9e259323489011350d622074ff5893d1298a5cb42a5ccb9bb8941c403a57e52fe46dfc887d5dca74a04341955dc3bacb3e5a74aeb30f599a8e07b0eec4fe06285a043dd2349cb2f89dbe26a8a081be573692b2e0f4438a8ef141932e9238fd383251763c6180bfb4eca189f9702b4a73d91aa05010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x061b0382e60a468f482c31291c22ea5a48718807337194da11bb752354e8730bda54180388d684036e441f23abcc61efa6ada39746cc652c7860bda02723950e	1612474087000000	1613078887000000	1676150887000000	1770758887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	344
\\x2f97baf7e771b16991e754e77ffb79707e1dc458f81dd0fc4c444a5138b6aeda8722b9cd548b8220f2d8cd28d6a199825f635a013a10234509d6c5affa754c88	\\x00800003b8176e32e635692d62c28c8925ef759abbce812396bbcfb3bdcae8918303addd008111724021d36c751ec01da2dbe834941e303cde8830d57f6d4bebe31ea8ade234bf625f5449007fcf7acfc6bc5e77cc103d5197046a1aa93d698af75c2c062295bd0a00b7d64fa5e59ae82db64edffc1d8d1a372b582547d5210b98863de9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb9d1a24412c2449fe9b11d162064bb00dd5691eaef3e43d2601521676a63a0a076c901e312284a2aca1825dd558c60bc8555b82ef56283c3eb7ba32e3f1d4102	1631213587000000	1631818387000000	1694890387000000	1789498387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	345
\\x30cbbe200c09aa2e3e3b55d5f7f18095aa0ff4899ff827c8a13ecce5b8d516b5316e610c3c2e7647962936791d9d4d7934c3d2a3ebd6cf6589dd76132d476e8e	\\x00800003b1e70433e3441a5806d8ec9a047d1d5219eabe07cf7772d1c23b05acec0968e4a8a1766a375a159a2de5688b86d0e12fbb0ac063b07775fcc17a831383a95ee30dddbfdb5415f6210a2e1d86cde28f662a2e18da80b1e97b359906587f7e116cd17937bccc007200a6e4ee4acb420749cbebf13f83c0067827af197e8b514e53010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc20699f4b268de044334e920f462387ced9b6fcd8b548be51220f34970abae98443c4f4267d728ba0fd774981be8cc6c8c6824b143ca39e97cbc89c5988f6404	1625168587000000	1625773387000000	1688845387000000	1783453387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	346
\\x31c37c0000281a832cac33e3a1cc975fb714d0237241ae8bb9a228276948d455beeca6acd886d6e296973f7372892614d783c1bf84f5da0f1ece838d52dd2570	\\x00800003bcabaec33be652f4427ee3b66d26583af3d59fa2ca9422d077b3122c0c6f4bcaf263a92e1a6f263810fa6b25cb101128b135c4b218611a67ff98d8c3121f10ff3d6f850e07f64b035f5a8e83d02aef6ebd00c5dec1409e23017cfa310abf19b07c97220ede9172834fb7bac31718c04e6ec137529b4f085956d1d183692cd97d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd2526d0621cc94625408e576b6ac3bf2948a67bbbdd9b715bdcf6e3b21507750e4d9e19fa8f8c301cfb7c8fab302ff95cab5ecf337920c03889b0b2fdc81370a	1611869587000000	1612474387000000	1675546387000000	1770154387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	347
\\x338bdd697976fe4c5cc6802f7fea59354d3c225906f622ecc3620494a18f89626690b2d25fa26b0eabee53b8d32f2ae2c2a8c77575a42966fc224b6e56d3a528	\\x00800003c295c20f8501c8bc52a958c043a43e0994c7df36f2df38ec8802b35ec2d6983e09e0d37797c8d79b994780bb55b5cf817cbfe0469a4a21e6065a1920c08d98d8f9da17eee72e0300a64de87e17d77c1a2f9a49cac8bccaabbe10a1f4e4e99cd67c6f7b0f12dd314c0fc262e0a35267986d7d6ee14e07391beb9f6a79d90e1e73010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4993e2479788c36501a8694e7f426c1974e118ac25d9b257f9874152665dc2fae0b2fcb79e2912b4edfe7cc31eb7b6d23ed3fb1fbe7941732ae2294ef71b4003	1613078587000000	1613683387000000	1676755387000000	1771363387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	348
\\x33331bcccdea44dceeb3ea55b13ce9b081b3a43f0ea7e9ad059a631bf3750322d6f13eb1509d126df6884011d2a3a760a95132158b1b27342f08033236741ab0	\\x00800003cf00312f2621a3509eda8c03f5fed7999cf9edfa9414511e7ab0ab85bc1fd9c8030b6733607df3153858ca318630fa0519a5573594d7b3d30a0298e56fd924ef4ca913cd6f36116273b979486a52371c855db92671b81b84dd82c7cc1646446fc7f2b60d4756bd280f945738e2e8e3ec2d983932f839a43a3741b6a0d9161001010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdcfa906736f5670a6b7dcd81b2223f1b6917e865a713f8cfe6a1728159817308419ea39b046bd7e528519597207dcf5975d1e1ea972afc24fb5703f6e0ed720c	1628795587000000	1629400387000000	1692472387000000	1787080387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	349
\\x36174ae8db37b694154bf300558cf678b1e1b6edc2873b7a783befd94d70edd6632d8b9d24f646d449fc29f00e7d703a65cc68759bf77b992b7821e22dcb3ed2	\\x00800003d439443e3df752f4a64e8a45465249a65aa1df30f78c0ea39becf2cba068a6294e39265b4d0db54e807b45e2e66efe843f6a884ffc921677fa14ae5cb2a99a2b4e3d4c888de8738be79fc5368db769a2bf603185e235dc47a1194fd41a43cb9548a24f2a34b297ef2bbb0a177be4f3aa7f84cd1e45fb694b07e4dd8042e923b7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4cc2252733e5dddd8da033d7e602cae77216fad4233eb2a04ff2c7fd2186f620e02f027667c8adfa621e4ea62b9c2bfcb2414a4d995f9a961d74d52a68866506	1620937087000000	1621541887000000	1684613887000000	1779221887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	350
\\x388378223b16aaf699aa9c770c6ba87715e1a177606a5a5164490c505c98dc53f7083c0fc5fbc5ecb1e5eccd035185c5b694a0ce51edcb13ed42aa7291523c3a	\\x00800003ac4d9295812af27bdf8ef17136a71af5c381e7cfd973beb7c0e3f995711c18722edd123d98f7fc988befd3def189bcbb91479ac3570a18bf55cbc43fd1be82426704b19953db33db02480946da65324c109c46246acf80f123bd5584ee8ed4ea829ac8b8ae56832e77cd554a8072710ad9b7feacafde3c1f1564877d10921a05010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4437269b7109ec98997e224ccd352c6c3179c6dfbe5ab3ae29787ba7d0b9d44cf5f149ff1e1ec0aa986dbbfb37862a6f66d24d812d0a072a4ccdfb4451bb7906	1636654087000000	1637258887000000	1700330887000000	1794938887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	351
\\x3a3bddc0b4171b5542f15cb3d5dd4bf75ecb5cee1d8dd27b157bdad845b27190d6d3e898bc27f3a5816c71a54cb60b5d164a48f241ac45567c9846056e639b4e	\\x00800003d44b87f647fa8bf99160442e33454ef5a31e76d330b1b38443d56ffee29f544ee643fc0a1e159fbf27828d7d39d8a6ebb01d76e33f57fc1e7b1a98f2d57256ce9629aae7fbeb81a551eca9c1b658bb6b0bde502a5e1fe99bc8e91043eb7d0dce88bc509f97042f6c0a0fe41fc98bf5f7dd6a146bfd690378e06e49f5cc00880f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x14be7d4584b1060a1ed35452d9944ddfbb9281e6f9ee9fb7edc33f4f2266c05fc7f1de4ca94ab918481b56ff8a8afe5902ebadf8944f74be4a60f5365fa5da08	1621541587000000	1622146387000000	1685218387000000	1779826387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	352
\\x3cf7dd6841b645e2a583ead76038edcb5a5c6becc5296817431253a44f007073bd5c8c0099d94f59dd6b8c60f81b508dba3729ab11e7f62f50e4712df2ada919	\\x00800003a64c4264df5b07083e10d91a7d7d20dc46a4d1c09618a2c29e8ff6183c3ad95cfeef786bd1cf9afb20650865f529fa2c6adad18fd679154f1df2eb61d9bf8a33db8e8923dda4aa547b6f58c0085235176955aff983542fdd33280ee6b052fbf11f73f6ec5adc31ae478fe05abb13980fced97ccf7326cc998cdac0614bd6aacb010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8b4fe0b0e6fadb4e8070d7543b87c8df12ca21698af7112b1484273e5bd86116edbdc020a7bd76ac89fadd30cc12e01c85998c669c80c096c0d61d0803788d0d	1636654087000000	1637258887000000	1700330887000000	1794938887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	353
\\x3d334f9def9da9bb6e2fe827027b167d3d940634177ecfe4f238e2ed8fbc7d86a77f19764d7afeffdd3b8cd42b286567c58ff67d39010865f2bb653abc577229	\\x00800003c39d115c3d09192a295f7c9a510378e25cc9163fa59582da5c6ce55b1dccb14e3735bffd419ebdec1932539fee06afbb60e267c42211952f65fcd53236aa1d1a5eccf4d6f340cca5f38c9dd920dbbefdf03ce3933245feb553771ac497263cc0ab62fbf55682d723ec9d2d2defde7dea981ad2598c0b03fe11807af573208d69010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1af71aa6fef646f7098134c6772ec092ae6a904840b3c242675fc9821ae54b3e6ebcad0409f44f81b66f9b656f71788090d86923cb6190a71ce70aac2afb5f00	1638467587000000	1639072387000000	1702144387000000	1796752387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	354
\\x3f87262f8a2d1039b1f3b8239167bfde66efc08dc86887b944df7544f57b1f46d00e98942bc7e1832d813d07927329e657c877bb2263b9d4f67fae15adf57a28	\\x00800003b82b03c3affeb867b957864638222170116dc674a5de558e1445be328bdab6e14b6fbf7bce84f8ab11134268cb34ce7a86e9bc9cc5e1044f80054f37d92cf0829b1eead6d8cbe67cf8c0d95cb23c861da95ea57d5d01ec0473e4325d554d219cace297e509c3ece1ce7a2591b21236baeeafd07507a66795eaea9b1ea3e969d9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdddb93aa7c1c01d7e562e6340966010c684a50bf79b873da8da7cadcb1b522171f1c3864c50d16c0b1c62811ad611536412dda39f5e1604072385a0e5062ee0e	1623959587000000	1624564387000000	1687636387000000	1782244387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	355
\\x42e3f1a7936090075f54ad026032472c58f7916197e81730490d2aa80a0b9ff710cc62d443d9c415b149067f6aa76f3a94aa9ef952c7aaaaf749b20dcb713209	\\x00800003b9c9cd60815074b118015cc34ef4a9bdf44f72899d167a7360bce6fc4b38366eac57165fdbbe75d7f41f068843b6dea2735778f5aca14fa8bb54b83d5910ef62a46e1db6597b73290cfa313ca9cea61bdb2035098942173441d634796c48bab672089c209b015f4898bf41167fa13ef7609ca780f9acbf2d9b4b78c2af4f1d0f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x73f85b5b780fa2d38e7688dd97b13041142797bd28cdb85804fc24a46fec49eb2b5ba307709a85b75929e0bb8987d59dd4832c91cda828d19c72838fbcf7d507	1616101087000000	1616705887000000	1679777887000000	1774385887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	356
\\x421f889245c5e491dd944d52e84dce8ef5987b24be54b4fbe533a42f9fa7165288feed5b1301f33f920d008192d2c7b7f411cd5c409e618952ad4f627aa84779	\\x00800003d39f175274cffd7a5637eca488a922823b98e129736a75ed702f3e781229b452b84a344a16e8802b5ed00863de6f77d1283802e3085679393342fe246da12043cdc4421e7806f03383d4711a852b28cff75c5d9c436b38823d7b9667a0016599c9e775486a4d245238e7b7082014e93c57e1e6faa366feb771c7383f1033bbc7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x76e2a313992cb8f4ae994c1b28c778101c201ed7b9719673341a7592cf109393f7418e0bf4c50d724043e2adc487779307c849fac26992589e3344a9a0451205	1611265087000000	1611869887000000	1674941887000000	1769549887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	357
\\x57d746845f3b9c5671875a8022eb98c685c3140763521404622451e78d7739159dc05cc4cc5905bd245497c70560337d5e35979083bd01c46067dc1e8593d051	\\x00800003b8eb778aa79bb412e844a7a6812dbe0bd5731531028d079801ec0412fbfe374d251fb1a7756ebb0a4812c7eb890e2b698648ccc3a110ea74d98b7a4d39b50f01f0cee14107746ed7a36e106a00ce9beecfb473fe2e31095e047ae009e849fba3983eb087f893ce898968ace3c29a5062f4169d2a4cbd13422a6dd71bd9958421010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd1139ba5cb53830ae8c4a8eaefb5a9ee598083584789910bf8cdd3fa5e807dc530bdbe574e9d589a3f1860bfdfc099d108d3c1a466f339dcf0e08649be89b509	1630609087000000	1631213887000000	1694285887000000	1788893887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	358
\\x5833dafc198d26bd15002e2122a331815a50a7139cad6790d6b54c44fed849427544afa604c13806cda071cba52c51c2025d298e4a529af06ce8a30f68bbaeb2	\\x00800003a61490ddaa74bf98555ed9962d93c701cc3be5b919b0db48540f9bef54a526604fffc4792e37514f2ee0251627db0ad58f07ac6b6feccbbead0971210ce4e189075be51ab15f8a4a9595f9d9e5784e3a6cf62db62574f8e94c0b404dc7a975321de8405ff99698de708ac09d9c3a8d4b4d71ec80a25e27b7d40555c99f29d1e9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa83bc600d31db4f87bb6f77f527a54e068cb6ee9052006f1664078171dd209aacd5052d8ee1a75bd3165d78d50dde70c6f4c4dd947fb0a31e48bac3d0bef200a	1623355087000000	1623959887000000	1687031887000000	1781639887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	359
\\x5e7fa9b712eb5ffccd3243c81361230814511d0268b5ec79e9c3f2ef14fd2ef583cfa1a6873a74e88faaadabd3ed412e42d9b336ced7f227f39fa0f8f31a1eac	\\x00800003e0c582572e65207edf8250085ba90aaf91750ac17e4cec9ad999a8e190cd8f195800d6a7bb3207f964f40c168c180ca681e1dbfd366c91fcaed10b80cf73a13b7a711a33aeede4a8b933fc5ae364a32340d0ae8136cbe49db86d9796551b1710f3aa87d89f1b5785352c23fe418ce09def1c607030da593ff8309c7ec3a28dab010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2a1b21676c6bedc23dc938cd787c7e6ab496147c0c4f22862d7221c569ea4369b004c221c7038831b1e0333a6ecdf2053bd9532095ffdbf2e81f00168c7f8109	1614287587000000	1614892387000000	1677964387000000	1772572387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	360
\\x65f7b642422ce69f8d7a9a36056a27b0d75dfd9b25270c411c71011c3cdc1a3f794b13fcd16b3398719a4c21db085cb1b1eba89705a55af03256896bf59620a3	\\x00800003d4c70aaaa9ca6dd66dbb92d60972f22ce7d0c0ed302f8259fc51a1fac599fe15dee83be8bdaaf6d45c496f7619693c0b67475153eeaf1aa3d683bfaad0791ef3ffb8d97d35e277f92d23f356ed41abaed6f9d7c4bae30dacff6d0787f239f6276351d4f11dc724ea5b61d053449d117c0e4bc037e213ba09b2418a09e45f1201010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x853b21945d4d43291c0a60823d8d8b5980f1d773279fd37dbbca4e9a709a8b649266084db4f37adfd1717583d766fd67ec11f87130fa8077a69f0d0d95c4e406	1639072087000000	1639676887000000	1702748887000000	1797356887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	361
\\x65bbbba583876a2dbd635be1d7154db5ff212dd2cc6f8e7595e7d60257731f8caad0e33ee633a8fc3bc0c5fd5c9c2f77a10c605952d3313b8add87eb0e308748	\\x00800003ba3d15017889cfc62322d45ca7f685984fc3a2c59e727863ea29113286d7d37f1cc10bb7b6b8003a857edba8ec94a0dab948ca493d687791b16b20e4b41455afa0c7359ea2039eff8a986bb91327bde831debdd49186e91e048c00ae241ba0e997eb2af4c01cf492421447e8219d8ea0715e494b7c81a5a5b2e688f7184739a9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd652ab08c22585fd85d994d6d5c74eb13a534ad375a33311a87c7cf012112a1aaa16bdeaeda0d72c87047d5402ab53cf9752017eed47bafcbeb7fd6a16d2d907	1638467587000000	1639072387000000	1702144387000000	1796752387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	362
\\x700f8c2e3373a9c689b004b7faf77ee5ba173ec5a1e425d235ca64639a80e296ad5fc1d1e0013ac7c33f584a71c7e2f8be3714793384a164194fd5b2ccecdb5a	\\x00800003ce7f75a106e8edda671981bd4ff77c31a1cfaa16b5e167ec1858451491c9593819177f460d0a311e96f39bb89052d5e6705a42849e179747e2984b92fd6482088394d961037ad1f25045842d3350c95a0a4281479ac0d3d1193ce8ba6b0e45b7136a9f116da406334101b5f3ccb1947bd3299c401060b13238b3c926f11f9ff1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x07604546cf236281a4b821db372f1088fa7e073cf1b07822f9791c2c5ad3ce677cf487b70546831ce9a675a7581539e253959c096db3c585473d99ec1f9cc700	1638467587000000	1639072387000000	1702144387000000	1796752387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x745b1ea2843ff2cd3ed45c40cf494a3a7d963eb4e200bbdb02004751ffabff77e7e655f95144b14dd9937eb795f1f1ba8b34d6d8f524107d0b1ff7d91a6b0075	\\x00800003dbd5ffe728daf10de37e4b17582a29d03964a939c330256317d3bcded918fb662bb3b543a5efbfa1db711b90d5c16bcfbae059e1428a4cb1b251e6f55914e26e3a5a4a45e2fb414c243926d608640a56bef2dcf0a4a7736d7ab32f15ca71fe644a19b52a1368bdb9983b7c9baad32f4f24b74cb041dd157eba8eadfc6b571a4f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x36578571ffc161913732c7429fe0bdd0de6c97d8fe29f2a03f61df486ce713d8ef3976da2beb34688a8fe563a127fcbc8749acb3bb014ce1771268e769ce010e	1627586587000000	1628191387000000	1691263387000000	1785871387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	364
\\x75bffcfad61a706595c3e5ed3ae5124db93a0ecc7eec83f33edb08da8e780438990d68c197b47c6c2eba8574b4efec827f84c4cd78895b297e7142460890606f	\\x00800003bcc024dd0f79bc35bbb2d80c702ccc8c4d0c1c06831040b3c38b0c12e899b8ec99f98e1b23678b6b537c0f2e859fa266613e3ae4ffbfaa178a316b677b405746ba366af911a6afc5a900c27df41f06379d139aab7c9d88fdfc81738309c1f706e29e148eaf8a5bc8b11366e84f69da3e372acca0d51894365dedb0b076277655010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0de833af13df3bf28230cd4157627380237601b2d9e52b58b106e7060e0df234b39feddbc3c9bf862b3c92463fb6701b8f4c2017cf174d846ae02e7e43b1ca0f	1634236087000000	1634840887000000	1697912887000000	1792520887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	365
\\x78cf87512e65003a3da1e8251241c4902dbef4777be1a1016dfebe63c51a4b9ed45e4b08b768aba7f7ff13e86a814939ab2528d1f7d0ef586f30a17705dce12f	\\x00800003da9cb836d07615261ffe1659fe66192cdd9602211e57777d148fa1b614aeb2d0bb8331d766fa2eaabd09d8ace8ee97261844d5b8397b7333b764b77c335bae325c2a5facc512b2d115d8456ac9801d6092d861f844c71d8444895fc1c6d44aafa2b6176896c599d63d3adc204befcdf15704bd08cd3e85a38e0dd888ebf229e7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x68248d81843731caa28ab3e2ec322dedca328a6ecd2ed21562c413dda80333539697486e614cc29180e4fc219561cee6e96951e1680a1eccd4a405172defff00	1611869587000000	1612474387000000	1675546387000000	1770154387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	366
\\x79739a0a2b2ba4d4467655a328906fd8f30f5f0f9f75e1ae90eb10ab15aed4b10cf234d020a15ff2b35c78ea35a0dc25f80025dc0b8a8278f740eabbc43e77a1	\\x00800003a3b1eb3bfaaac86a4fc4711d47850d99d837c484255a6b9cbc7cd9f3c2c785a1d2c419a285b6eac10183981c0bc87bec0157ba4196cdcbf8aefeb41b801cc49400f38582e604f71a34b8c45d8689fa79d366f580d3cc767b5e0ae595b16ff93505a587ecb91f602a6d395fc7e009fc67365023de987900bf7000a3ebc4823819010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb2265242d88636177ef09de988f6cd38b8c2904e951762ab7451d98585f36da851670bbb913bf2dd19a9f8a380832634b2c4d3f6d5ce5769f0d89141fbb40b09	1617310087000000	1617914887000000	1680986887000000	1775594887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	367
\\x7e4b693f8571995c842b44b4826766021d24b9019500be5cc49829111d7eacd5630e438c013aea34c0dfe24252faede2b60111f0fba216d8ca6dbccef651f04b	\\x008000039f82f653881ce030dc7ecc02ee07cb4ce4c94d7a4111788b72077c6d0fbf627cb3bf0289d5eb92f025e80410e1436a9f3416256f90b9663c4f5a0b09cbb4d426c79a35f647f476e78a68e00b66233d8566f0271b3a969ca0c12739b99369a22f7c2c6262ccdabd63f062e6132b593fc677093f8fe8237ece5b71c85e92445f59010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1e6563ce11f2e67cbfeba8ee421205ea29c7be9f1aac8ea7e7cfb74e81fab25d66819a8e436d49d93309a5e9c4942239935e8950bcc4128a91a1bddf9f136b06	1618519087000000	1619123887000000	1682195887000000	1776803887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	368
\\x7fab4758c0f6504f1a039858a1426a8fa810b701b6143ecd138a3223bfa4d97ad41a0314f55a7112adfac42a09643d83650f3bde9cb149456cb721e831e858d4	\\x00800003b2ccd5f0b32846de9623a77b11e952fd0e1cacb9d6995a391b7a16d1930f6a3033c00edf565a30798d89de0c8e5c5d8291529c111cce2dc4eb2930e331a05e382cae5bb015d70ed1962b445ca9873397766e5a6c56c49fd8a1bb52a3ed3be7a8ae14de0cf0db115817535cd6c63ced2df601ca10bee5601c752ff2eca38d5533010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5894a309782ddb05d88021299c594e6012b171f7d90931f3b84b43db770fe6f78e6d66b8aaa8e2f14e107fbdaeb882cd4f6dd0a8f049e633f6a98e40aa44c801	1633631587000000	1634236387000000	1697308387000000	1791916387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	369
\\x866faf6cee122229df8f4b2bd3a9dc23f9a9da633617e273898e76e42da59b673f8bd42f3868fdc0a89340ff49ce46024872ab8fdd16b58db9410f2419f2a993	\\x00800003ad4c53a01f0a658fb02c60fa177d65ff998c2332828df4d5829d80e31a740fa9693ce76627d806df963899deb01edff7a65ca4691b1b6f05b1fb7aaf2bd2e74eaacd62e17e85e80bbf30ba7dfaa0e8df28b95780c582541986cecd2f06a24f5a44aa1891407037d279fb457b5b2e02a3130ef91d9b3beedbeede00587dc68453010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x4976da77763a0690f1dedd0139daef566d6aac3e5334c53135ccec7d914c5c66d9f8cd8ac97fa5e03e567212f70baea1c4efe94a7a2fd5efca978587833d9b0c	1636049587000000	1636654387000000	1699726387000000	1794334387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	370
\\x868b568dcb6af1683998ac79da24d0a159766283db56d390678ccdc344b2689c32b68f75fe71127c1353c5b98d6872d3f22efb02e256fb6b34abee185778d15f	\\x00800003c6618484f5574e5ffd820d190dec0556b0a3301d00951c6ac752d60dfae3524e620b58442979782c225ce092f816a6142db5b67b42d69411b32c46e5a280bbca1998db0d93a0c09f3d84e892499eaa3e9e9cf56b359aef72e65e9f765b8017b723f20f0f3a9dd51c7bc033a1dcbf42c26b51fd2aefa5d1372dfd781ca05e2f69010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x194dcc40d4ccefc2c7d6e3616efab260e99e75907e4106c4cc45b4c15b2588450fe68679b8bc2eabc2a567cd50e893cd887c02ef2c2a97a6eabc96990bbd500a	1636049587000000	1636654387000000	1699726387000000	1794334387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	371
\\x894356349b9325235ce15adab5a2e0413ca1b473a51850bac1171941d51de0f48dcfa616cec16a3c0eb98873c531991a2b20fdc6c3db39ce9c4af72c859b6af4	\\x00800003aeb6187b6ea0faba40f6af8c3705ba5aa53554ec6213f62a9b79f21fedccf922af5edf4389393f14679450e9c71c1f1ee8bf7653d9db479f5a042c6334e2588c3d5aa4f9bca7e65b38c4c9dcf1abbedcc8d1e1a19a19ed5ecca46038585cefd9d2c9c6049cb4dbc46bb385bb6339c80ae630ce477c32a928beedb0a37bb1563b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd5cc797349e90c8ba7ee592014823bad0e3a8402b318be68db548a5c8f75ae798f5ed3eaf23b442125c608fc3ecca2a50cbb1cff9f34a412a0f2b5f88edde007	1635445087000000	1636049887000000	1699121887000000	1793729887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	372
\\x8d57553c549b2aa6bdfa0afbd6b2b0a4837d4570c3ad80114005f8a5221687ed3a193f61824e427a8c39ab84c87d160021291f2bf32395a338384b096621fc92	\\x00800003df6c21f1c251906e4547f3ea0806421726e400d1850cdc1f428fe39c62267c7853956a55f37d0ef2a8efacd17c0513bf1ecd9a3db0bb409a510eae124ef55c5a4002a4efe3c515eb6c32ac1adc6fd420f1fb0328b9194af6709e75f3b0796e86b860d51bd9a16b6098215b7fb3f261137b20f8f6426d532dffb2b470ea1f24d7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0b5780782d0c1f69d3dc4234cf3f6ffd98a8d5547b3c7dfb0028c6ae51586caf86d032fd05493c3a210c79dcd9a8a51eca7537cbe301460cf62f71e655243205	1631213587000000	1631818387000000	1694890387000000	1789498387000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	373
\\x904b247f080f8bd4afe955d55d92da5387d166d815026509da421f9c4e0b459114008ab0f1e7c8976476d6f972d35493eb0d3375354258dd63cf95077c2772f3	\\x00800003b5e20ba866be583fc1dcb336c2779eb3a5783740878b023c959919c61ef49d4a0429b02ffcae61da2256956b68cf91f33fcbba4160c4cd1a2a95a39c32fbe99dea2c8db99c5d4055b4e9c8d0ba52c23ff8ff6b14e409335f8deb9936321c7f1d43c6f2524e8d6126639610a714e8d67c4da4a06b8b805dd119d0516336c5f339010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe6843db5771d8f0ec4b494ffbc467775aa86ba3e79ec04312a087d689ca00a73d01937198dcf7cfdd0e6719129558a7dd42283475e7207033a70ec9afd357804	1612474087000000	1613078887000000	1676150887000000	1770758887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	374
\\x93fba42c8fdbd7e0448edc1786d7f96888d570a3ab16ca53df6e21e1020ac1645a224209faac7d7ebf1b0db781c542f1498abaafd03dd4e0d1cdb3008cfd8b95	\\x00800003da614b75a7e8924d0a64745160946db80994e80f6d045da172e5d629dd8ed6cd7709737081ef1bec28dd8fece2862001d8ba618f12c0bfb0427283b16f6415c069ffd0865cd9fdb751e500f201b7724d68035b54f5eb9133675ba75d344dc074d57b4528d21bcb81e54b45689cf7791ebea2ef08bc22d164b3aae2fc7326989d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc9835ccace1a5d989c4d448410fbdc6ca3632f696eca43fefc7c601bc320438e7af9bed362790c1fcafd1f43649af07a25b96d32db6d19eba257cb706e40d40a	1639676587000000	1640281387000000	1703353387000000	1797961387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	375
\\x93df7ce8f22e2b549e73ea95b5e4e369e68cdfd1fe5da941e792f4a1375d96b5c624b9b71a48be38db1069fae65c18558ca4877d4a98a622de1b62b0f9d5a668	\\x008000039eb0b119d56a11d4ca0fb0352b5f268aac335892c0a69a1a985e242ad3231b91796f83029c04053fa1ba89579e684aea273528d2b4495bcd5a5e0e52dbde8ce90972b5199671e66b21133d13e664360026e78f9f29d26e351dffc71941fb95816585606885aa9da24d50f63976518e6faa4a9b938b58af52a2bc3c0c7d334e7b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa01960f6a8fbb6d735bf7711732476b2700747b5cface7e221650f3762f54e798e82be18f7347ea7e9ddff5e46467aa28d5a1fca39a2f44e072ead8de1b2b901	1614287587000000	1614892387000000	1677964387000000	1772572387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	376
\\x942bd264117f151b24e7c18660e54f8a30fa10e418e8615219d57ec258b042d3925d132895103522d16a94393d163d8eb8d22b6363374acccc5ec60cea4e8564	\\x00800003f8d1cbf5a8699f810fbb73e2eb3c76c27efdb2e205e18db96bc3b368cb9094c3aac18d702aaff4adc2695f77409f629d5bb0b560ee58e5c9e07331a533b0e9b37be3d0913394508eddaddbb9d270057fe814d69725d84584bd00b6e524200e39987a3ef4959ce586119edc0aeaf60f4013f7a8cfdcfbaad2151ac6089a62afad010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3da74ef2b6995a78953e0bc154fc82ce4b6dc3f548b20cd23033344b931c9443dd5c36ca2b01b48f349ce6ce879fc0b8bda445727e29025e547287938849c008	1618519087000000	1619123887000000	1682195887000000	1776803887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	377
\\x95334281d4463020ac4ee76ef45d8f18aad13119379293b6850215aadc5b4f3c1b3b54375643161f5816131e40db3f76f40bbb1121fd2335911e43459f3b9fbb	\\x00800003db84b0e00543d4a41ea1574016a120621b82abe43553355daa18492454c43debf2fd0ad8d8a91063dae32263146eef341c5566436f6b9c6dbeb8fafeb67ee5781a8f01a18157dadd9e8e3c7841ec018d86bf644f831f9deed95a27492e27e4329d9a44947972b0011cd1fe1353bf99a094dd225a026ee8e5b7fd77574a382da1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x094b17b706dd3195d854ee597a541a32b3a635b68592cc0a8de195d775d86d2311491d5f726e53a6e32c6814c08e0f9b4502d922eb2b0da374eb7a4973d3cc0d	1617914587000000	1618519387000000	1681591387000000	1776199387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	378
\\x957b25989394d7f481a6cb288e063f4064cb8979de04be169463ab88bad662647099a97c0246961ca91f4caaeafba1754c06819299cfa46cc021ee5cf24ad3c5	\\x00800003daea1390501ee75bd85b2a2d86e997735bb2f827a65f3aa7d69379d390b298852f2970f41ec72d4de55214a1120a79b43ceefb990a00f1d917e57ec95048df73c7f8328806419f98c4781ef12b4bec1174c5e937695fe73b338ca69e624cc683d4f23ef7bc41faba27891f48085620bb14d5558cd9443d2c55ea1dda8f819985010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa6a55fa17b92fc43215a4a62de6ab329b1b2e8618fe55ebf769859dabb31fe831021fe9d24b4c05bebeb7d7f05a7f763088032d4450bf633d47da9a6fe752b08	1635445087000000	1636049887000000	1699121887000000	1793729887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	379
\\x97b7df6bef8bc5193254072c65f699b4cb85ea8287a8eef752e46af2e3ddc2abc93ad94f139f5e584e27eaadc48dc36d16aac19433418d540729b68e3da20d80	\\x00800003f28f9baae5d7e940293884c792aa38174d9c52b1c2feb6b2628857956af6ddf8839448ff2e4aa4cd2d7bc238fa1dbe02a437f35bb2078fbeb449e4de1b9b97d43da8e8c8a0a8c3c0de28888c1c347b624d41ece918ff0416bf9c0a12449ca7a17d305604a750b63c064bd4f45aefcae9118dd64d9cf4401fc10c6c00aaf93a23010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf65581f37ec9bc232a3d476473c2679cb4cacd3367854457015266ec932538c7fd9db3a3ba78aebc54ac8467c04223b679ad39412692948ddfd312664ac1e505	1629400087000000	1630004887000000	1693076887000000	1787684887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	380
\\x9dcf2eb30928862f59c77142bc0a57c7133f14fd6b39b32b24d3bd6415c9a752e1ccd21744e7e357d3e143d03696a8bad231ca04ea730fd345ba7840d60ca500	\\x00800003ce321570e73ab62aa9493b07ecf01cf52828235145ec584e34819723d8962018169c80565c6bac399f731f242ecfb729ef7d1f310fa917063345707688484122de63db8326b99c1b0d82a89083bc9cbac63cc48f025806aed465b865ac3b5dc97c6e217a636b413103af0214f5bbbc644106695079696060160da87a6f3dddc9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x90503bb9189bd27e21b0b67bcde412d8b022e2adfed51544608cfda9267831910d8406df605795294ce89160863b651f89dc3ee4ecd8c15a17f1d8647171850c	1634840587000000	1635445387000000	1698517387000000	1793125387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	381
\\x9d3f339b1df325c6d11db1e94db5398f01d8785bf5664e022f6ce3d29cebea5b79f0b65261acf71e923891ad1b843d572a0f405e63413fdca6edc78eaaf1b206	\\x00800003cfb6567ee543a79d90a50fa8bbf9d08db425b69a5e936ad62742cb3f25fb3a924f06f676f2057365dfd74797777facabfa950a1320657a297d1206a48d68640fae73afc8af19a0d62782e32e19be2e27d7d2ca7e746ccadd50136547e4759b1aeab0954cf4eee13e5a7b0686985f07a5cd14ed69e19b4772eb2b64ecb7b39a0d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe820c185361c30a2b03e2b15ca1c09f979773c7cddc18f64cc16f98057eee36251c55dce9ce7077a34e0631425cccf3521e86f12311bc33a21457eaf90e41608	1626377587000000	1626982387000000	1690054387000000	1784662387000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	382
\\xa3eb2e39dda663c2a349069db2e1620c088b7516daf07b95e8c09e822811c268f017f28a51fcccaa18de6b7e79466b10b022e54c27c5b3af0bfef33af4ca64af	\\x00800003cd53580f5380be10be9f630ee5626fd84c5cc7b73c5e9ba0abd635394e41105b21cb0c031eb57a164c2b0f088e913916b11525895dc2cdbe400beda46d650fb19c6d76b84afd441927a174f8b31cd88fade6865b91eca0983b903823703067d8ab3c127bb4dafe07e2d4b4d777326a8c44350f26435a9b373c7d90711368a6c1010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x95b5faa287e9015a44c7c15a5c186f27870c0003fdd6ec0f88cbcdcf2654c364c99aa234080f2f5448e401cf6ffa5a631e9f41e2d5691c124d056f84c29edd06	1627586587000000	1628191387000000	1691263387000000	1785871387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	383
\\xa89f3412560017b0d9e22507a9fc1f4cc1ba7b1f1577a083f373933991fe9a20d5af0b72d72b9f3cdcc12dd54a84d181db60a932599354dd2205efcae7984a4b	\\x00800003b5c35a9d936a36ec1b91abf85f2b15b26b82744476a9cef98c9b9cfdbaf0db1c9f67bfe27ff1a723fbc8471d18a913469b379cb89fc632b14d4d64b6b21f7fa7aa84fe6b0a6f319dcb40a7e255b54136f7a116093c910b2d4bb291a8ba4370c537c429c1e73a516879b3be429a733356dce8dd3c676f3128a5784a81a978397d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3a339ea377923d3ef4bb4e34bb5a8c23385950c28d6caf3298decefe339ed104064665ad401a9bf91bbef1790213b8aeaf2e2a3efb8015f107c2456b764d2d08	1631818087000000	1632422887000000	1695494887000000	1790102887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	384
\\xaa871cbd41626140a7331ce5db6fe0b8b79c8164396da1556f88f2f75a7f4e4d507a863d80a144d4c9592b3282b976613933d8cea8a5476be738c42741807209	\\x00800003dc3c2669277bd7e638059a0242fe8d6cd9a6b578dd11ff695cd8b1ad435dc31c43b2e85352403e7e8a308230f47952f5642beee76c603ce1653885dc2ad174f4c8ea4a49157d59262e9e92bc1fdb3846e41be6cc5e66cd2e042ba298c0e7ac6a6a607cd043a28a3f9bc8509a8d6b1d79c683e130dc2a56027479bd73be8c6109010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf651740095fe9c6faf9010f774c97e54d2244d7c854e6b99af3cd1fe8dcb0df66c29c763d121a809f4b2069b18b8392bf784f0827a3fcbcdceada84ab3b8d506	1610660587000000	1611265387000000	1674337387000000	1768945387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	385
\\xacb7fb568fd94d6836e0892b5701364fe91189c89237ec31f6f83cd388f286e42ecfc4e13302b39a648552607db68f5349dc7ba05466ed671110447c902765e5	\\x00800003e2522184b08e18df3674f3f571063edc4940a35eee90ab729f96d151343913f0c743ec50034b7ba71dd447aa6af65868a900f33cc4000c4ca50dd6cfb309014878fb975099f25a518167762a81f2b1b45b5035e2aa936c235c515b1af2827e2de305eb0c6c00d4a2769da59bdfdef8dfdd5da364549f3d8a97af0142f35f30c7010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xaec020208d34ba0e3a05447ad6e7f23f5438eed11ff3d4ca3602741232fd5a0d890fb6c425cef39411cc3c7572e1e1ec10917405700ba3b98cc3e7991ba82a05	1630609087000000	1631213887000000	1694285887000000	1788893887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	386
\\xae2336acba2fe048a8567c3613d30a5676b16c5ad457298124a4d17e349d2e98e5eec2200060f2bbd915a86a6a982c1dc382001657070a9d876a982a38560b21	\\x00800003aa3f1ae0ade6d4aa21036765295e74d18554029225dfe1d192158b583be04d1f418aa2b6d80c451971d058bf5a80a9df6b371ee1c7bd898e8037420a167650bd88723230e87c3eb51db8845c8cdb758a0a246f437e1e4188efb5fe3e5eada694db67bb145fbbb75d1ceb2ea32b470df24b6fa892dde5918d0d72abddcf42d909010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0cc187297f198ee73442ab010e77919a76cc23534cd75af51becdf08b58e1896155d7a8046e0ade58efec345d0eb1b264a4637b48af236f4adfa2df15c700505	1630004587000000	1630609387000000	1693681387000000	1788289387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	387
\\xafb76f21ca4ba1777ef5949153858182e8f4b11f09a670d645ab8b95535035ccf84827876ccbe214534ced9dd85dabbbfd113dff42a01deeebaa3e3f8a9dfeb2	\\x00800003c2b7ab521bc6d2812edc2752a345d276a42085d3db4511dfee508f34c779ee4ad2e46231149976e676a43fc024c4265b6eebae6591eb32275f43f798e5f3e805f4b21f2fe8bbca30cdd31946d3fb246b6ef83582f8376f007e61932db50766deff9a3a858525694e4973112bc5ef3592ff1af702f7d41309e3e1685593193623010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x880850bd71f093b06a47ccf720d97375749e257dfd5462fe41c048a7f6d5c3d4594b986539995a0e5fe63dd8612635dbe6207d84fc8c8dc4bc66f7685dd4370e	1632422587000000	1633027387000000	1696099387000000	1790707387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	388
\\xb663fa70488e5a1a7b3d0053ef49e7f14ca32a792e58e7e1a53f22c79ac9a7172950f9f87999ba0197e27b021b36d43f255b869ebcf3a3dbaa48d604ba9991d0	\\x00800003f05ed9ae5c68f961072f90d18a37092280f259357dbc67b0901b0c7bf0d07422bf1a2ac32e0bf3dd4cc4bbeb64d642683e0445d0e2a707a01d9727686c71db95d0e42860a95af2863c6a6bc6241f563c787c0b1e7a2ba36bdb6fbd88f715a543bf7daa941e37e7d53e1a9ca25126ec0651482208cc4738025fbd5a7c8cc446e9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x966125cd4a2ac574e603263221c40ddf5fa05ecaf9a78cf7d8813ce8bb3dcb1b3b82c159ea312426e4bfd24f999ecba482cdbb16d0bca23291c767769bc2ae02	1622146087000000	1622750887000000	1685822887000000	1780430887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	389
\\xbaabbad50b4acfa2778375fa99fb0084faf50a59cd551633376e9e268a86c9d6792cd8fa86fcefda0baf6c6f0b4728236fcf50b7c5315a09497dceb9af13ffbb	\\x00800003aca2e8a82e0cca3b49772c3916f44ca8d4e8bba60b49e4d239087f0cb9aceb1c0dc554536957aed8e242220453edd64357d4241a9c57ac6e3ffefba2fe8c26153011737634c56c067325e284d4d2e1381eed0fa43f47bb31cd40aa53fd4b3e4a5b617d2fa06c98f0f3286b638fa0229f3eb7fd8199a44c834418b2d58416a25d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x3ed3a57a75495709f25441b2b2c14b1ed496ad7f9dbb26422c5477a52f60f4747227ad01a6c6dfcea6d26937eb2081662ffc9a8a15fb68e3d3b70024b51eb402	1633631587000000	1634236387000000	1697308387000000	1791916387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	390
\\xbad79ae2b69c9a3d7730d10e97d728b428d76ab16c7a2b9e00a55829e8cfeaded9b1c477884e2e7cc4735d2e250f522a989e1e394fe9e68174fd039d09610290	\\x00800003cbb689df502991e3b7e7bf0dd122656ed2cc194cdb42c7ea674076244df779db7b1c0f63067bb15fe647a2af4c2737329cae8e87258329e65511723bc7dc98b33de61b4049c014812241b001a5020e3698e9f34b21734a4f675e7a861f9939878def869401e77de201b004b3b8838cab28fcf48ce72a58eac79584b50bc6e4d5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2e2fa22857d6092578f1b8f75e45bf1aa229991e660aa1ee4ff6660fb1eded5950dd12d5da1f25551223d0285fdbf125ffa4ad3037c047d27097a9990db4fe04	1626982087000000	1627586887000000	1690658887000000	1785266887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	391
\\xbfd33a9dcb9be74652a310f2407b5657bdc10f62b34e83b9d0d0fe0303627704ff1cb418a6c114b0ee9002faeb48052309f884359862e01edd6f20fd45b8ad3e	\\x00800003ae63e4383846c8c25e68491077c9f9ffdcf51beb11c0a12652f125989c4f7aab14e1c1fe0b91556bd961c08c48a775f9f27306376990102a1e69c64788d326dacd8d60c38c958af63ff7f3013308071df8f0136374042c9cd663cb2c98de0563ad5c15678999da782cf9999dff45e163edeb137af9a52a1fcd85eee65d6c8d79010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x504f962c49a66da72b9b11dfa212ec713ae0af3271554b3aa95db4b202563efa3e6d77dce4e1955c0fff1b850d2ec1d0d57147f31d9a4bb13bacf153e5de9e0c	1641490087000000	1642094887000000	1705166887000000	1799774887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	392
\\xc22fe494c119041f33642aaf44cf8f91047dc7169328d48a1e744191dac0961b5f030e7a2373393b1bfc9b4d57a7cf78b2c75b597cdd0d8992121d911f96bb42	\\x00800003c4b578ae4b2b5369a34e43b2baac6ed219a4000a8cb1ed782b37559a3779cf36f13e1e3cd632d691dec2d2cf6ee44dfed295999f4f5e3f5c503c54da74f6bf9dee54250fca04bbe7dd6d316a8143088bb03001b45f15a0c1dbb400855882f92bb241802c4eb6a8ce417d2e43e260001845667823fbb10ca37cebc49a3f50a883010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa74e0c55f7a4ca138bd53599de752f89cc5b2829dc35794f9843750ba9f2e649dfdab579d26e18ea2ab6096410499779a6c799d1333dc18cf8ce1a1e385de905	1631818087000000	1632422887000000	1695494887000000	1790102887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xc5c7f00a08d738e0ff5ac32ecdd353b716e134f1da686983135273102100682d2e968af278ae3fb28a472816da389ddd94fab6fca48fad3c4d471d891c3c764b	\\x00800003b627b126b9d9abac05f409f0590a349c92aa4cc857f0ba61fa04b712e04c0db17e956d105cb22dc5d379e1da2f6781c5f40dc500eaa647bcfb10cf1c49e1c73813cdbb28371e5988ac63141b8854f2cb8646a2cdf39bb12c95aee79d2602831d9ea604bd839ca22076bf9c567aba461109d9a4a7cb265266d063be638354109d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x9d054150649f1f1ea4a12f34b965dd730d1e7be1b35ae2b573266bfac6aa50419f187ae6ed54dbbee226b4fc7752f0f7c1a27cae2894ba624e391c8d00e12b0e	1637258587000000	1637863387000000	1700935387000000	1795543387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xc7aff52849b08c73876c93538b9597da3a1e74f77035df744ac82ad60df219dfb2c544a46aee34441bcb0347cf0016ce358c670472a9e34ce36d1d08421c5691	\\x00800003c3354c14d9a9461ff4f41ea76984cd5ab0e3ed72a4ab0a0a41116c7dc0d6681f42040a51c3b73a216c9bcc80e0a1a9f5cfa2a5052b2ba21dbea4cc1fc913e872e310dae1e7c3bde7a81df55473d0f3c84f7d785fa3b61d14d234718ddc58b1e6c61b5f5c72d8741700621137a9b6ed2a0078e023e80273acfdd63ec603ccfa61010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xca4f6959d697d9fafc3e8ae48a4b6d8306397940c8013773138774f60653298eabf2f5ee384bb8aaa9deec1328b63c2bea206915ee5c303e72e7c220a552610a	1631818087000000	1632422887000000	1695494887000000	1790102887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	395
\\xc8239149f5e809c073056d5722dc84f7d3374e17fe714824334be2c8cbec872c4bd1641a7b12250f42bb5b35cdbc3e9257ec89457dd19403cbad2d5788ba2a55	\\x00800003a7126ef9eb2ae0f88d831141cc376e10c688473ccd8b1c6010a231b07f85565d1afcd84ad69a7b2f3d79d61f5624f0b912f1085dbf9f8d01873dbd613b800491633b36ad2cb9980033610a2762811c7968a84663472de02d8d4145f6412bde00fab07dd6335633effdcf1f91db4d0cf3384bf302685176b9703d8d542917022b010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x95da33370f12333fe93eb9edfd235b21192a3d725faa507335e115a1b06f9086a89449bc06662e1cdc57d88b271aef429b5a312542d9e84e4f3769ea5d1deb0e	1617914587000000	1618519387000000	1681591387000000	1776199387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	396
\\xc96fbcc73b97d022c41718038886f97af46e93b8e2081ae409b8df9b55dedcf5dd9ae871c547a8ae454d527a5986cd37165db05df6bcba0b879dc9abee092286	\\x00800003e63803c39f7ab35856dd9aff07398eeff430ec062533d8b9d47ab19e995faf81c68c807132cad053f803ec809bdb6a2a2c3f62e32cb3f44f93aaa5ae10e34800fb5256062a7c144a1ea65757c5eea8540a2d9e4bb53db2a25a2d2af852c601d85ffd119faf99fbc59df5325ef731485c8ce98d0326df3f0c7c28cabca2ffdd1d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc5875c03cdcc6dbd92b28d601d55fb40b2b2249d26cb032debcb1534e603d9f96e1a4607d6bd299fb18d71a3b86bb915c3c18a2010bfb4160cb5e1f28a7ed70b	1623355087000000	1623959887000000	1687031887000000	1781639887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xc9db10b020d2993bd8652fe7a902993403a81e63e3aadacd7a392ad096570a2caccb42dc7d8c2d533742d36c2dad3330df700692b26b9c601977bb243eee20e9	\\x008000039bc7c483ef827801c9105bd761fb11c0e4c61a91a6476bac28d8029e3571f78d56c7719a0e44737e7483abb0c5e989b2cbf159f3a999aba105f2b20dee2595f69b6a8783dfc0e01201f5769dae16c616a11544714e0ddd9857f3f73e4d01dccb08d1e8ea12d79b5a76b98127fb39e5db79d85279aad6800d446fd9567febc605010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6a65ea8aff785f9ce4266e27aba582471da4cba2e0c243dcf912c0a54df140dd09419bcedb0ad0d61886524d7dd520cdafa91709becec0f16bb506efe3a9250f	1618519087000000	1619123887000000	1682195887000000	1776803887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	398
\\xcb9f2f84d336a958d1e98d37aa0f08dd9d255aa5b263e9bbaf58a630b63532b2f3c4606a88b4a89217168b5abbccfe20e9e632ae90e2537e72db47f29b76a887	\\x00800003cfd0dabc10904eb7242c8a5cd04a91d9e0d1319041e7ac9a6b7b9bfae48a122ddde5681681d2df5a81bb73af532b3a31cba14c00f292bcd952ef61b2099216fff72c8ca2c5ef2c2351c963888930e78d50626f6f16f635abedc553211aae4c1453acc7d2e7d4ec0c94827dbd424524939183d9cce6c368ae8c9843bccd0b4fbd010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xb47814c42eec43b9e1570d75d3c96d03597b3b19497a870fe9ec1533a8c2bd39f4f2c8c91444991bb8f7fbf8be93b1653a746d67a0c2ac8c3636c590e5923500	1630609087000000	1631213887000000	1694285887000000	1788893887000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	399
\\xcbab0717263c2a7a77bc4575559788aa32e7931be7595fc807eeb12c603c89fd87d2a2080de0e6ab42cf711bbb815fa84102a042311fdff727080b845bdb5dc1	\\x00800003b94b280c83dd7eeb55a595ca02622175d17b13e1ad624672cbade740e0795424a30547f61cb8c79b299e430bf8c8858932aa86be9616b487027cbf1955494ec99ff93f6051d30170a531f875702b2b9a28e18a042d5618e8063d95cc888d4ab35a32cf39ffa3601b70bbbaacbdd81b90f7da5578c8a18903e93d29cdf54fd351010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x392359ba3b73015dae15d5a665cefda4e7a9c5dffb2eadfe28b51232c0d6d437649b9d71845815dc949fdffdcde7bf1e68663f9c1b55801513b0f1c6e9973104	1628191087000000	1628795887000000	1691867887000000	1786475887000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	400
\\xcca3be60b12d904fb49e7a0c5a031cb5371221299658462cc57bce2073ffff3018d5cf5f3085cd3e5067c92aa3de361299424fd0a45329c312e73054b23f6148	\\x00800003e05796641239fd6602c1974462fb927b23ae1ec3afccdd231dfed83bc8883cfa7dd57933f692bc661feb203dd67528387219f5f0f79351bd3044a0a4820a4f962c89bb8380a910ca3086618c14e61371035eed63e9b4144f0641f957b16acbde39f9a286b92e27e89eddcebe517c96cd62fc82879ca7cd67291ac02a788f4e27010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x93d903f78e7661bdf35f7aebec7ade8dfa72099042ec17bb9e93eec7e5c7ac0527a30a14e10e9b723a3905313e8cd8b3290959d267915b17a0c718f91e087b01	1639072087000000	1639676887000000	1702748887000000	1797356887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	401
\\xcc5767b402bd51a537f365373f5361c71df554cf119643f0a50de1b699fef4097f091744c2f846e2999dfafe3649cea1c7497d8271911c2911832363d8aa17f7	\\x00800003acc7acdf4e93b56a411c8d6c7eb7c65a2997b1c6ac5c2bf133dbe995ee222cde310897245b982ba8c6b0898340e6ae5c49d1ce80d5c84647eec925ea56d2742b9ca15597b8b1cdc83da8c885f49fcc8e3f633666997fb7c28d96ae81fd95eb87e6982b5ccfab688b0bb8777c508fa886f654a56c9c168dd27d15921543ad541d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf71b7be27296bb36eca55332daa039e017ebf83aca8c7db23a44392e1d7c97b23f763666252c09e76ea62258e764b1eb686f7ca63ce7d654bf184eb0b2889501	1614287587000000	1614892387000000	1677964387000000	1772572387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	402
\\xcf2bda116fa142b18588769808b19dc0a6754ac9103d78636640aa065b85b371e040ffd9a0283beebe97fe79e99b3376c5e2c31407078c37bafc9aa2f97e4a1f	\\x00800003cc1bdb6a39bbdb2e6844d747e1c7c86e7dd09d00fa4357f4d6fd26069471be563ffec2779944c77022f129b167cd15047b7d01f34a3d9d1259d8975029614d6349d2d0a638fce7aebddc9c0089ac1950fa1b4ad7fa667cfc25ddcb850430706c8c2cd47eb5ad8d8bd89097e6eeeb5a2797db6d5a088b12f44490b243879a1979010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x40630d087785b67e68e319a96bd1d5e4792c1047f21a958bf503d44aa558cf55ee29e93ba46ada9fb75731687570ead7c6f8e416c6fd4d1c0186fd20f4c45a05	1611869587000000	1612474387000000	1675546387000000	1770154387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xd08f6f1fedeb743ba0c3d61bd1d215633cea3206c10870b054c9a4742a0c16f99b1e36234791eff53ed99bf71fa338be6374c809cbf9f1b57b1599a4b05747f3	\\x00800003cf718627f5332c56317b7d554077a2f3752d10aaec29c9d9bd03fa07c6ed5ad40bd83f53c08fc37ec1b15eec4cc7cc2792972711d560316da458cdc9e4c54775f0b96063f63cbfa4cdb05f74be5db81046e7bc931146551c7a5b03957debf3cc9d6cadf9b3eeeda99f08d97fc523e72bef2ebf776c596068b416447a0f4b883d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xeef8a4862c9c2072c455b0b39e012542caad285f8e19628e26bae2ba1161cfb87a7a475c0764ff2d9c927a983752c546b5f340accb72e1ab360ce546c214840c	1617310087000000	1617914887000000	1680986887000000	1775594887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	404
\\xd44fe91cf88a2b7d6b98e0fde24774a9294a2b84bd8d180edda876e409fd63c7b783b73f16d6b51160cd3b7f3ffb3ec819c1557acd57cba52ea4486e3e639976	\\x00800003a17d702e51df8dec65bbb4dccc1799912e1ab9683f90a44b14aa0e71a28f7da4e856c4a65a674c1f4af5be273e6fc6a62b053a037ff933f448a3646b670eb047cffb1ea1a6d3bb8618bd3f2b4aed978ad490dface831104571c24e11442333b5a5c11bbd82db8b5abfe061e44b5e39e5d14909b0c7ae7fba9e49116d9c80fa91010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x8b9086a65f475f96c42b7dc60a33f4019092b1f1e4f60b746e67edf1ffacc029c5bfdc8c711ea7fa17b7dfee43200dfd0a9d0a6385ad851c74b6fc50596a3606	1640281087000000	1640885887000000	1703957887000000	1798565887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	405
\\xd52327998c894f146dbaeedd9e8dc17be7a98c5a214bd0b895a635cd16408206284ccbce46555909047c9b9cef7dd694eb5c4be6701125b72dd61ac35bbac6b0	\\x00800003c38bcce5123c5718209665fa97561be3ebdd9cac45f64d991dbc20d78a5ce540420bb0c3c8b9d6fbac9e70ab84fb0fec0dc62f1500821ac339108d7f7decdd78187d2476164cb23d3928c044a85bb67541824c8650d822b92b1f87d28840272b841f5000dd523d70e10d01e8923912539fadd798b8fde39596808b8aae8dc7ad010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x76721c7209adabbe9893750a81997cc6c9f4f281f85d9f7b40d40786bc034fed6e801018330ae4942532a0cc61ecedc5ca828cbdcb3a262a9c6647b077f6010e	1634236087000000	1634840887000000	1697912887000000	1792520887000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xd95b1bd6567f2911a6171d7ff3601eb0816b5f7007e25d38ed7f34361a59fae60c0619f6304343a7235b00c0deb0531c9ee0138c343637d1cd1504a8e2b3f32e	\\x00800003c47e519e9443b43fffb7ef43502457980e8d6450099df7cee66ac77db46ea19993f63b2a788f3d83ea9d70a9d4a5731da32b1baa2b7d4cc09436d61fe8f1d759b7449f818e0b7f265190fdcf54c02da420f3d8c72d0c4916a2f5d5aba28d19da19de7fd15eaa8256d6865428fa4a1357184a2c917cffd4495a3a2cd235ad9f31010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa73b37a18c1427a4edfc2b741f74f5295126c4ae95d8f9000cdfa56ef39e488c4c5c37b992370482b18127ccfdab9b28dd846a19cf3172e016e0b9a2f416df07	1610660587000000	1611265387000000	1674337387000000	1768945387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	407
\\xdd779fea2b83bcd0ae99eb864c13232f5af7d427321f8b393f090c3c8b23108918fd72e2a640e0d63ae981802bdad601540a7966def31462f025fb929468d090	\\x00800003a55d623233073aa7fbea49f2188a5d6dc1f4d6ee768e0e61a960c5ba95f613118ad5a2d3414c77616b3984c74ab78747a2f984a6e788a870b4f0659c9815f1145c22479efda0e4f9cf1de0985e775676b17806f8106172bff0d97e3299f35d97657da097ae298541126471b64ff3a3ecd799d3998bc64368189d02317b81e6c5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xebfd3523bb4081963162b575b168aad81838596b9d9e51b69a4ad5d032b0f318e7b084add6ec67acad11a751038d73b99f98741552bfd7f3d52504aed862a807	1640885587000000	1641490387000000	1704562387000000	1799170387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	408
\\xe0a3dc34ae42ea111e64410a5dc0ef82bb0606769b3286cb85bb6feaf88f5390f44caf7abb040ee5cb62e44a08ba10f3bfd07bd7ed0c1faaa6556f187b1e57ab	\\x00800003957e8bc4e531e9ddd48e6e8fdb268e47b989c2511f479776b8b5ffb6313bc10bb5ee0e9348adcdaa5a2e3ede79a871b8447c9e111d83bba918e80e9cc2adb215575cc8150d8ab5ce43a5c03e69276dc1d14a884373636b26773eebec18b3721706bda23dd30754831c82390d8a36736d139c720d05fb03c5d1799a8a0c545dd5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x7c120a17ca2b440b14b3aa1b1e9cb45f147f892c957e4001590a595b4407684653e1b35862d050f31ac7003eb7204f647380459fb9deec4b4b60b5f7bd617208	1638467587000000	1639072387000000	1702144387000000	1796752387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	409
\\xe1ab920787db9493b19aa29fae2bf0d33da043e56bb85ff1bdd39bcd6e17c56d88db086dc35492e3bb6b25d686e50e037019d423c12ccf0b73103915e0a95f24	\\x00800003cb0dd2c7b897b20ac9a7e78069535b5373c3e8f41838c80c2ec4aa7b48346b82f5ea1fa2c08d7f92d4e8a9d633d3409d958211a9bb68f3c215ece446a98f276a097d38a63ba0acdc3cd5e1a7e5ad5990c28ecb05a9ea9971cb760f3a18fce693e34b434a7053e6310348edc6411b7faf185ea1382c4b8a63cdbfc828c7c7e557010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x57e145a576ca47de6dd0b6388565b4b9ffc8b123e88588f5889733c4eaf7160ebcdea1c6da37dfa798d7bfb497034190d0d998ee1b36c4688156bae3f7c6b005	1619123587000000	1619728387000000	1682800387000000	1777408387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	410
\\xe4ffb3efa7d38d1dfd9087100c867c1d48dae937179df69abdcb7f9c7a9d7f7bc8ecd5695f916dc1224a49bb6e3831725a7fe71e7dd27c6058155da6ffb20ffb	\\x00800003a921d1e4f0f12f212c140f708dccdd2f15c4c1b7607501e82c3a78684d3bda82f0b7f511e1c4318d4e8f53cf21a010548990d6d28c35be1356d89dd8f9a27f9be1c46f6596a15702396bb468572df06caa354ca8c16c1a11f09de78e8c1287683a2026ce407dc05abbe4384f0ef7adeb36fdb70465de08cc2ff733da96c16449010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x2db42a99d7113179df332d1cfa4e1307b4b9be80e5d5e0233bf9c1d254477e54aff267158bb77210f64811ff597c566b246305c6d713fa86b0a24409340d0309	1620332587000000	1620937387000000	1684009387000000	1778617387000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	411
\\xe6479f05e5a0a7acc9d0d9c75925300dbbc3d84b3b3f79a6d0bf40b35a2b774541c9d099223a2145cb7c72c8a2e54f0cc52222ac5ed6d6923089004ea78afc22	\\x00800003a717c475ba6d9a4ee45f7eeb8c06cc3624efeda534fd8a4ac44377449c33d355a867d370d56bdeed587cb08a4d5d24346160bc8bfe97b5ad2c53e6cf341164862828fc3af262ae2bb7c53be16a35b9653d654b90b1e55ba0a313b0f4b37606fe95d5dcdf9458dee50b517970425c117570ac183826b97cb073b6ccac1c0fcf11010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x35e57582cc0a843dd4b9dd2f1e53a1722dfbc037f0dec468e4dcc77be04eefa5d7be6c4acd36a6a5aaf980b629eac944f9317f9086fc77cfdb5f761b1d93200b	1630609087000000	1631213887000000	1694285887000000	1788893887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xe71355cf36e396ce56dfc148fc02556fe5217efc2918eeaba2281b77c73e3a28efa682728adf02222f5fafd74bca411694a3f787cbcda9e87f19cf70c74c94d5	\\x00800003ba5ce67d1997f8b57583cee1f9c558bbbdf0a42e29e92aad0572c384711651b536f7afba8721275e45377bf0c6f46b53b7f9229b02807fb83f1512d398decfe5a51851c364c673ac533473ec2400ddf2d98bf394048703a5d0a5003ed9663c7dee1b616f8f19680eb7efca99e8b70ead9fd27ffe797bd32f53195ed9ddda97b9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xa0ebae3bc3a6307f3558a4a819d84a6b961fb8f30090bec07f61bf5fab77fb9a3a7bf71603bd28bb196b326edc0046156e8c9f9c6a255847b3a8a711966c520c	1628795587000000	1629400387000000	1692472387000000	1787080387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	413
\\xe7cf90e35f8341f5a57a437c40acfbd6c974afe99d605512ba67f05d6196505d47cfe758b855653e3919745400c8fd3d5b92c8528e2fc41ca69022cf9b662bf8	\\x00800003bcf18ac17d183938d7501fd0f152c324a466f87172a136853b9d6959ad9f760c57aab2d23735c28344aec257fc6b979f0070884ebb547295811e99809b9bc543d6479dc3dd07d8cf954f66ac73e815264cfc9515c21cfba977c52f17f97d0ed45b2b48a435c4219eadd7be49be0ca3ca3a53cc0689fe0f3a2aae9e6b8e7c4263010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x25994fe632f47b3756c1717e9289854cb82b24ff27aab616d771cadebda0ccbca7c2ce7b5fc09c398cf8a7c75d32e8a27dc836185d47c9ef7d4978b3917bd505	1620332587000000	1620937387000000	1684009387000000	1778617387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	414
\\xe9b3251bba138844e60e12955e929c97b10b5297974ec5130364a637b7b67c93990dc5363769af123f923233be711db61271cbd3723f62208bfc7c0e8209d752	\\x00800003b9ab0c29b4e6d765a8ed4cc0321f93f970582119551d647ed636b0032b396d6c1f160770ad0e88430101c83549b977216e90158acfffa62cc01202f5acb162924bba33b06fbc073eb1beeb63c5d907cd6e57c327f712fd2595564636be025f00b8fd4a74ef462e7f7e6cb79d2f433163de63f01c7f9b0da86a36ed20c7959491010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x25ee849c02017207693163be6f1d553f1254e63a6427e6aae6d6c16f83bed90a2864d2cd94bae5ec32a90a4e0c1e631afc78a4617b14b1acfe18e78594a9aa0b	1613078587000000	1613683387000000	1676755387000000	1771363387000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xeaa7a4aff687149a9a3a0cbcfd40c3596eec6b3a45c106c935ed126d8ebcd54d3755d452df0c5747d88ff7e704369ab5f3b5d9f15e8dc6c30b51d77ef11983c9	\\x00800003dbdb55dd7353f73c995c1355c5bf776ff84f60022d05c02fb8a68d148253ca091c3ba6032e2021cfa382f64a4095f3eeb11e0f03a88b5394132ae2c3444bdbb71fa084eaee3aab6fd41cbdfa021c0cc64bc5295ec0c5560e684338cb4b16989f70b4de35a9ca90cb38fd8898a1a3a2a3c2f61e3bff0592edc44072a9c6dd6f6f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xde077b582011a27b2f792eee20df4e4195a7ab0e94dece655e0c41758fc147c1e9ed228bda85860539ed636e58c8853d189b82c77ffbca93128da1864f446002	1636049587000000	1636654387000000	1699726387000000	1794334387000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	416
\\xedd395f2d0a07f71d895d82796c97dd4b639c862d8906d35d5ac849a19c5ccf950f866b6959edc525d0e05f4b9b441b73c383b326da59aac38d58703143733fe	\\x00800003e2308acfa490504d2e6181e9992d0d710fc2200ba5b41fc1ff0c9c0b8f6ae00eb8af4915fcda0588aa717d58ba45aa2bafdee96da92d11fa19c07210342ec154c10a8bb6bb25dc7fa0e5c60cf3a6c33807f6378519ffed199f1857c2df7fa0f02535776e9f78df13739c26b296750f2b212e4712834d0031890793e049ff7b19010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xe793805f68ab5502057599f2818842a93ec92be1ad8864a3f72cd4d57d13f47340a8400d2602301b3444e7f7fd7211341a96a6b57c8a9448b86aebdccb69f102	1615496587000000	1616101387000000	1679173387000000	1773781387000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	417
\\xeeafc96dd741d2e3fb70b996754318f495239f90ec69260019fa9498c5fe7ed78df8d20e4edddae689bc52b889a8d713a9e4faa2cb72cbae215b2b4b1f16c79f	\\x00800003e4779fe6440b0c7a280ef40e42e7ac40e4255567f9b48d79cf95144c012faf1495f7becd40c829b0d4c2090569cf791c936f78f0d7b78c6c82e0e65572613c907c2259cff0b50589908c8a2bf86f4f8d12ce205e97ba0b0c4491aa98ebe7517784f1cf582294644e0c9e215788a79228ddaad80f46cce5eb2239fe8b87599f9d010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x762c84fc3369dc833db780c2d710ed8d52ec8ad4ca80f64316120df9b3e15af29b7705681d0835d57af04e071244330cbb01bb79e0b3d68f32de73bb58cf6304	1636654087000000	1637258887000000	1700330887000000	1794938887000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	418
\\xeeb73853768362e5870feed88046f1107b6d5e188532aad56610c4b1b0e2c340c19c3343c3e0712431e47ba54a08ad8a9a9bca2b8cf0c400cb95b4e3ade34762	\\x00800003b9525e79b685bfeb1eac24f5aa33c9f570849240794b94afcb041e6b1b4c011533143695b6df14152b4321bae1f2bb190cad4172013b698e74ffc45f039abee0192166cfa38b0ee77f56ed1efd96c48b727f9711d8f8f79681df06ab2a6c01f044c1ad344183db532dc2fa7b178ba90d376c2c965b52d34840d33b58680f8ea9010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xdb9df295f5dba91ce4a0fa21bceefc8abab1a246d111947e550efa38deee1d187d3be6a3d11aebdf59be44c73d362eef3674c56b3f8bcfb9c11d882a506ab20d	1622146087000000	1622750887000000	1685822887000000	1780430887000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	419
\\xf18f48136f51ef186d949baf7a2d9fa0b17da7c73edda6ef64761e4fc4f622897c1350e881f4d74d04852df34508b2ccd17c4ce88c416a5e315227c0fd2bf0ad	\\x00800003ba7e501d2c021618f8001e24b74185fe78666afa0ba6edf629549cde05862a8ce97f6b1918d5d8a10c05c254e4de0af931be3ac7233993bbd27734dbeffda9efff7b83b77df3df461a0ae2ec4d4104a35a73c7cbf40446c7eb4d6a4f489c008298e41dc40aca1884f519d1cab039438ca39281d0de35348e0ee2d5a891fd658f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x5b9294b716e9dede7ba8324383a71e4c32c74a4124b010ebd60bc07c679d898ae751c0a2fe169a2ad721353373b785968ec7f9fe895f21c85b9e274d2a4f2204	1627586587000000	1628191387000000	1691263387000000	1785871387000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	420
\\xf4df5a1faa259dff7909e896c5023cb420f7024b93d47dcb00dbf2bbe4278c9ecb35e014f9910bdc78978a9aa61cd59593e1073fc2fae56ba08dea459f1459a0	\\x00800003c8fb4a1460ea410fd677950213217ba5836d418c61d56fe89739fc96d08407949ab9afe99c036f25eda3130ce410489c0df976b59a1743cac3b1f6650a0292ae7137d8f83a9c456a78058319437dcd04bafcb76568314487062df5241cefffdea50fb5ae7b2f23d1a0110948de162da1803efe44ef4b2dcde61bef00ef2ef03f010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x6b51c0c80c255899f1dfba2ce23541dcf46b2e0a137504da40e065e0302240dd84209e87b7edd4ec68c40024b6c182815c3772532fd7a8cd4df2f3ab7137ed0a	1641490087000000	1642094887000000	1705166887000000	1799774887000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	421
\\xf5a34f34d179d915a0b0eafc94e08f46fbf751df75b421e7ea0ad0f5b11caede0ef8a53e44960e25fd81c6f58a479623518a03352314539ebc4645c0e684a129	\\x00800003d20eb4b57085f246663361c1cc012fa1a7a3f03db4c6986727626694daecd5aba76f405ea912a7222b590a48bc29e8dbc03e2e7f5d5ca35127f8a928398a4709ef73a32d23056907bcdaf52645b51cca9fe0b059c33a0f7d15836e8e7bbfab3fef65a0ca1c99258f4b4eeefa03e81ff51cdba991226fce27dd36f24cf67bbdd5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x60687aa955528b8567d42e56cba99aa33e5ca19d2528fe068d78c03a9090abab7f4d70ac38c3a41751cc38da2db004bf1b2e6fbce129c28cee9937a07fb4610f	1619728087000000	1620332887000000	1683404887000000	1778012887000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	422
\\xf7235f573acfdb811d59dc3e9e1925ad46dd4aab80f387dc6af9965aefbb3fb6668780d7a2c029b5a15748123ca9b032c0e2013952d8e0a50eb59c4f24515ea1	\\x00800003cf988217b6a45722bbc5018cdd2e5c68adbbe83e48814605d06d1d3ee3ad060264e134e8ab23b28d5919678243aebe6e5023e7cc47fd6126c786c7861e599e13f63e6580d9bacb5f48761c705c536632f01c82f34de05f3bf32bb2c788764e4eb30402c9d55dd901c26273d20c812091ddb2a3738f8bc612e7fed5a38263e6e5010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x54360e8b00674847ae28eaafcea9ed33f133836e25178d22607a769212b6a5d6c50e3cb6b891f0e400c6b3763e00f472808697fc88dae170b53e0f1b81fded0f	1626377587000000	1626982387000000	1690054387000000	1784662387000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	423
\\xfb27987b3ffe1db9ddf0c32955d4aeb516c009dc62aa59d8d9cb052a4c6d5412cf4094f16061e9a46eaa22e7488281c3dd977377e4b23195ac3845b0478b9618	\\x00800003bb4b71c66462e46b44544e10d53212b4666408f1d4341cf4adc5a13d1d0aa3862f092b5e0e6b55ca12d89f3001d902c674f17d5cd2c2cac14551eadfadc20a98bdd8b2e35b254d6ac013e5cbd771ea188b63f50fcd31aa9038918b8b94432c43bec84b47bb146d1eea78bd1455560b0292c66baf06798e6c3673d03b91454845010001	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x636ac573bd1902235fe22ad14c267d72c24a7dfa647d244db7dd941302c7ad8d686125abda05ef63a611418f54d9e22641c357424feb9de35e4b735356348f00	1611265087000000	1611869887000000	1674941887000000	1769549887000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	1	\\x62ab79dbfde905d299d4fe7ae81eee0e2bc7ad8dc99230af94fdf22e0a1ad3d4981ba383e87f479a92bc0a5dfab3043c4b04b4c13a13be24c9128eafe8ab6399	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	1610056111000000	1610057011000000	3	98000000	\\xb898ab421250883863ea7966a19eedf2f405ab364a1fb1c5fe76604f065b6ea1	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\xb651bf6e4b708efb26c65665b84be8d0cea400d85356559e3118dc9dac6b16824466fb07e89c73db4525cdc44669be122fe236dfeb7447223ed1abf2fcc4690e	\\x1896a8766f9e6253d8a86187f37138656991db396bbf6ed11287940cab562be7	\\x296e035601000000608e7f09517f0000071ff7fbb8550000399500ec507f0000ba9400ec507f0000a09400ec507f0000a49400ec507f0000600d00ec507f0000
\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	2	\\xbbb9e252a37203c9ab994a1265753df3b3da8f1ba324c7fc5608fbd6a30946964391ca1a217b443f36f80d3db39d0bf5c24839abbd17b65212f7cd5bd10de0a5	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	1610056119000000	1610057018000000	6	99000000	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\x79ba438d991ece65273223dff4eaaa7e0e3dae062490f0507b8f8296c28f350a4baf083e7d17d113e5be684ba66630f4f57568c8c0db529fb6cadc8f0c5bc604	\\x1896a8766f9e6253d8a86187f37138656991db396bbf6ed11287940cab562be7	\\x296e035601000000607eff08517f0000071ff7fbb8550000f90d00e8507f00007a0d00e8507f0000600d00e8507f0000640d00e8507f0000600b00e8507f0000
\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	3	\\xe63d2ce384c83390825d0ecfa619f717035f67d9630f5b0649d41ff96640326a54f0591f5f8e19b777762a839f29fca28fa38036263810bbe712e76aabecf1ea	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	1610056121000000	1610057020000000	2	99000000	\\x225c45583aa97fb24cc99776e65486eaaadbf3acec07af0eb22378fd14152378	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\x9997801d61dc6cd83cdfc0a8f2979df1d8504ae7f32542f919222c13cafadcb052ca18f3548980f994fbe0f6a382d14fc8f033adb97328acb3b282d9258a350c	\\x1896a8766f9e6253d8a86187f37138656991db396bbf6ed11287940cab562be7	\\x296e035601000000608e7ff1507f0000071ff7fbb8550000f90d00c8507f00007a0d00c8507f0000600d00c8507f0000640d00c8507f0000600b00c8507f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\xb898ab421250883863ea7966a19eedf2f405ab364a1fb1c5fe76604f065b6ea1	4	0	1610056111000000	1610056111000000	1610057011000000	1610057011000000	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\x62ab79dbfde905d299d4fe7ae81eee0e2bc7ad8dc99230af94fdf22e0a1ad3d4981ba383e87f479a92bc0a5dfab3043c4b04b4c13a13be24c9128eafe8ab6399	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	\\x88d16191ffd7c7059f1db6daf2c7a0bbd3ba41b88cdd18cb3fffdba133cdfeb29bfafc9af8e34eb3c5e49c61a8a409ef7e6f017d897f8159c6eb22cb6f88fc00	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"RQ7SPT0FERPT3QPDPM039Z5NJBW08WZ2Z3VGV2JC0AQ1JSW1MTQ7XN4GH4Y09XPEHKBRAK5WPQX271C79FE3SN1T5NNP5PG32JB3WX8"}	f	f
2	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	7	0	1610056118000000	1610056119000000	1610057018000000	1610057018000000	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\xbbb9e252a37203c9ab994a1265753df3b3da8f1ba324c7fc5608fbd6a30946964391ca1a217b443f36f80d3db39d0bf5c24839abbd17b65212f7cd5bd10de0a5	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	\\x27fb137c8d2eed4543d1543e4d7e03fb83f91b8b0d5952a050d8827b6830e6c7d2be7c4fdac49eeb127e95b3f53dd1f192fa310d97510ac9d360d7d66972cc05	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"RQ7SPT0FERPT3QPDPM039Z5NJBW08WZ2Z3VGV2JC0AQ1JSW1MTQ7XN4GH4Y09XPEHKBRAK5WPQX271C79FE3SN1T5NNP5PG32JB3WX8"}	f	f
3	\\x225c45583aa97fb24cc99776e65486eaaadbf3acec07af0eb22378fd14152378	3	0	1610056120000000	1610056121000000	1610057020000000	1610057020000000	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\xe63d2ce384c83390825d0ecfa619f717035f67d9630f5b0649d41ff96640326a54f0591f5f8e19b777762a839f29fca28fa38036263810bbe712e76aabecf1ea	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	\\x20dea2c163f1d837e0e226b7f7fe1ae8a35dece460ba8a86a473b032684f4f94b46a05f9ff0f66a5cc5864e8f13bf0b2a7335a8d5958d7ffa657bdc1b119db0d	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"RQ7SPT0FERPT3QPDPM039Z5NJBW08WZ2Z3VGV2JC0AQ1JSW1MTQ7XN4GH4Y09XPEHKBRAK5WPQX271C79FE3SN1T5NNP5PG32JB3WX8"}	f	f
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
1	contenttypes	0001_initial	2021-01-07 22:48:08.012467+01
2	auth	0001_initial	2021-01-07 22:48:08.055671+01
3	app	0001_initial	2021-01-07 22:48:08.099992+01
4	contenttypes	0002_remove_content_type_name	2021-01-07 22:48:08.121435+01
5	auth	0002_alter_permission_name_max_length	2021-01-07 22:48:08.133631+01
6	auth	0003_alter_user_email_max_length	2021-01-07 22:48:08.140064+01
7	auth	0004_alter_user_username_opts	2021-01-07 22:48:08.146023+01
8	auth	0005_alter_user_last_login_null	2021-01-07 22:48:08.152207+01
9	auth	0006_require_contenttypes_0002	2021-01-07 22:48:08.153957+01
10	auth	0007_alter_validators_add_error_messages	2021-01-07 22:48:08.162127+01
11	auth	0008_alter_user_username_max_length	2021-01-07 22:48:08.175321+01
12	auth	0009_alter_user_last_name_max_length	2021-01-07 22:48:08.183041+01
13	auth	0010_alter_group_name_max_length	2021-01-07 22:48:08.19678+01
14	auth	0011_update_proxy_permissions	2021-01-07 22:48:08.206504+01
15	auth	0012_alter_user_first_name_max_length	2021-01-07 22:48:08.213574+01
16	sessions	0001_initial	2021-01-07 22:48:08.218347+01
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
1	\\xc1e7c42e9c1c5cd186c29ba2c93404d12e2ef75f1eddf6417abc43d94d419b39	\\x298aec1af1541a8e31aa47fbb5c01ae27338e7fa2088b2242589f48c6341f825c0828f2c6a4c79004cf0bdc279a11843367d44c0f196969f4bac154a06ca4c03	1624570687000000	1631828287000000	1634247487000000
2	\\x0fb4535865d165b9d6b084e44a42a6a6af090a7e85699ed637c36ad714d84bdb	\\x53b57a9bb03abeaee3bc94665026b1ecb8989bc3370aabca7831645e4475414671be609086a1539b240b387c56be21587b6a5e1e165d50f75644db15fabd0d09	1617313387000000	1624570987000000	1626990187000000
3	\\xf173672b8b37a781bd5129f4ee7303a904525a32d38535d18ab91b5477e3d2c2	\\x72c1fb1d7bf95e0ad0683c21218b96dcecd564986fd9a6e902ca8607ba07d1c53ba2bc5ed1909b47269eaf5b0732eb9bfc53bb47ec5315ab2f9668b15531140e	1639085287000000	1646342887000000	1648762087000000
4	\\xd560c506c8c0e151a1d378aac8d5b65b0a8d92c8187cc3eec0b0e473c5bead1d	\\xf3e4520ca827b01ba4f37b54c231f0cb200056d90da4df96194329ac7744cbdc6d833bc4aeb2a649924e35e21c2cf1512d841e8678abbb2473011e6a5fc40609	1631827987000000	1639085587000000	1641504787000000
5	\\x1896a8766f9e6253d8a86187f37138656991db396bbf6ed11287940cab562be7	\\x16dabe0934911657af435f634e3ac2e861b06344aa8840b007dce147158db80cbf7b0f526e5d461ccdd0e3784cf0c7dc7d711398ec871684c8f2ff037826d20f	1610056087000000	1617313687000000	1619732887000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\xb898ab421250883863ea7966a19eedf2f405ab364a1fb1c5fe76604f065b6ea1	\\x86aa991d57b7c95890cfce7385e960a9f80ac70a4c3b7e2bc4227f5ce751e36ccbaf63b00f0d66a5881a0a9c8748b944538e49e2f91f4ce5adf5ba513ecce618	\\x99872c90f368071e044c665bec5c803b8805cb53d38499b69f7d90da2a4b958f90aacd9ea733d8eb2b2e52ae59e13eeae3a4294b25d9d8dee4d1222eaff767eabffef3d6bb32afc8b819bdeaa835ed093b6e56128e72000ddd87d049441078adaa92c1c47828cb684d8db1533c081c1b013d7c9c83d5c3b82c33ebc829b8cd8d
2	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	\\x8a4873b97c3a64d132cf490ea0541aa2719320e690cad74522b65a0e43f0cc5893b983b0c56290c447ffedcd6742a00224964b1ea505d2a54fa9379151dd884e	\\x1d028de7b8c8d73febb522aae8f2d11b49ab1aa7ad6517590e1602feb2ef73a254abbeb2ac77e07cb6226b081887837f5603adcc1b44e2aef870cafa0a3535570dbc1971fd3df95cf7d6d0c55092cf4440bc4ab45b7b17195050b6eb5b8c115f6386408b1ad9fadd43c9ce06dc0432109c93fe6d706ce149f52c7b2a5fef816d
3	\\x225c45583aa97fb24cc99776e65486eaaadbf3acec07af0eb22378fd14152378	\\x4f74dbdd8370937e54a0feb69a91a28151b1b05d94a81b4008f625d71b34d63f8c9a5f907332c8381e69d504f2ecedfd83b8ec505d130ce95c90a943ee819dc5	\\x36c748a6e061a781cb9a6887c699bacddebcbdf6bf0ed5e5e9d03c9d72b7700cffc04b096a5b0c70b26a809df353c700c5365e811460bda7d999c98c2c0523f224db1f20593857999664ca362af01c816c1aa0e0f76567e327daf60d035f59c171566dea780fb5df2119ccb0b05690b9dba799f3804b33aa51f493417c131485
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x9add03d21d871adfe95d51ebecfa148f4ca4bb14c9073b24d2f469c26ffe97ff7ff1adb42a4f9561122a57a8094ec28166d3e514529f5fd7f46722e0ce79630d	\\xc5cf9b680f762da1decdb50034fcb592f80473e2f8f70d8a4c02ae196781a6ae7ed490893c04f6ce8cd7854cbcb5fa2385874bdc3cd43a2d6b62da0314963e75	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.007-01C262CBNA8R8	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303035373031313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303035373031313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224b424547374d4758475744445a54415841374e595359474d485836413945524d5334334b5039364a59484d5734565a594a5a5a515a57444450474e345a35423132384e3546413039395631383253504b574d41353537545a545a54364538513053535750363338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030372d30314332363243424e41385238222c2274696d657374616d70223a7b22745f6d73223a313631303035363131313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303035393731313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224552545a314e354a38313332594554595a314b4a3358334345355750524144354e3838393337414d30453435573643534e4d3847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22434a5837364a34594e563244395446324d3736444d323951454752414254354741393131443548413954334d3653485143585147222c226e6f6e6365223a224e325a4335444a5858524d4350524530575139373730373434585236325833544652545836355742514458333746594558585230227d	\\x62ab79dbfde905d299d4fe7ae81eee0e2bc7ad8dc99230af94fdf22e0a1ad3d4981ba383e87f479a92bc0a5dfab3043c4b04b4c13a13be24c9128eafe8ab6399	1610056111000000	1610059711000000	1610057011000000	t	f	taler://fulfillment-success/thx	
2	1	2021.007-01GDZ4Y8NZQMJ	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303035373031383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303035373031383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224b424547374d4758475744445a54415841374e595359474d485836413945524d5334334b5039364a59484d5734565a594a5a5a515a57444450474e345a35423132384e3546413039395631383253504b574d41353537545a545a54364538513053535750363338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030372d303147445a3459384e5a514d4a222c2274696d657374616d70223a7b22745f6d73223a313631303035363131383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303035393731383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224552545a314e354a38313332594554595a314b4a3358334345355750524144354e3838393337414d30453435573643534e4d3847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22434a5837364a34594e563244395446324d3736444d323951454752414254354741393131443548413954334d3653485143585147222c226e6f6e6365223a2244563845533644355731504a514b414d545353444d58433539544435515a383057545a4442324746375059383050383456395047227d	\\xbbb9e252a37203c9ab994a1265753df3b3da8f1ba324c7fc5608fbd6a30946964391ca1a217b443f36f80d3db39d0bf5c24839abbd17b65212f7cd5bd10de0a5	1610056118000000	1610059718000000	1610057018000000	t	f	taler://fulfillment-success/thx	
3	1	2021.007-02Y1NYY8BT6QT	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303035373032303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303035373032303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224b424547374d4758475744445a54415841374e595359474d485836413945524d5334334b5039364a59484d5734565a594a5a5a515a57444450474e345a35423132384e3546413039395631383253504b574d41353537545a545a54364538513053535750363338222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030372d303259314e5959384254365154222c2274696d657374616d70223a7b22745f6d73223a313631303035363132303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303035393732303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224552545a314e354a38313332594554595a314b4a3358334345355750524144354e3838393337414d30453435573643534e4d3847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22434a5837364a34594e563244395446324d3736444d323951454752414254354741393131443548413954334d3653485143585147222c226e6f6e6365223a224a344b5134524733335a5a31354e54444739524d3438354e3434565738444e424134595832575443504a56314239343447313847227d	\\xe63d2ce384c83390825d0ecfa619f717035f67d9630f5b0649d41ff96640326a54f0591f5f8e19b777762a839f29fca28fa38036263810bbe712e76aabecf1ea	1610056120000000	1610059720000000	1610057020000000	t	f	taler://fulfillment-success/thx	
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
1	1	1610056111000000	\\xb898ab421250883863ea7966a19eedf2f405ab364a1fb1c5fe76604f065b6ea1	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	5	\\xb651bf6e4b708efb26c65665b84be8d0cea400d85356559e3118dc9dac6b16824466fb07e89c73db4525cdc44669be122fe236dfeb7447223ed1abf2fcc4690e	1
2	2	1610056119000000	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	5	\\x79ba438d991ece65273223dff4eaaa7e0e3dae062490f0507b8f8296c28f350a4baf083e7d17d113e5be684ba66630f4f57568c8c0db529fb6cadc8f0c5bc604	1
3	3	1610056121000000	\\x225c45583aa97fb24cc99776e65486eaaadbf3acec07af0eb22378fd14152378	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	5	\\x9997801d61dc6cd83cdfc0a8f2979df1d8504ae7f32542f919222c13cafadcb052ca18f3548980f994fbe0f6a382d14fc8f033adb97328acb3b282d9258a350c	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xc1e7c42e9c1c5cd186c29ba2c93404d12e2ef75f1eddf6417abc43d94d419b39	1624570687000000	1631828287000000	1634247487000000	\\x298aec1af1541a8e31aa47fbb5c01ae27338e7fa2088b2242589f48c6341f825c0828f2c6a4c79004cf0bdc279a11843367d44c0f196969f4bac154a06ca4c03
2	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x0fb4535865d165b9d6b084e44a42a6a6af090a7e85699ed637c36ad714d84bdb	1617313387000000	1624570987000000	1626990187000000	\\x53b57a9bb03abeaee3bc94665026b1ecb8989bc3370aabca7831645e4475414671be609086a1539b240b387c56be21587b6a5e1e165d50f75644db15fabd0d09
3	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf173672b8b37a781bd5129f4ee7303a904525a32d38535d18ab91b5477e3d2c2	1639085287000000	1646342887000000	1648762087000000	\\x72c1fb1d7bf95e0ad0683c21218b96dcecd564986fd9a6e902ca8607ba07d1c53ba2bc5ed1909b47269eaf5b0732eb9bfc53bb47ec5315ab2f9668b15531140e
4	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xd560c506c8c0e151a1d378aac8d5b65b0a8d92c8187cc3eec0b0e473c5bead1d	1631827987000000	1639085587000000	1641504787000000	\\xf3e4520ca827b01ba4f37b54c231f0cb200056d90da4df96194329ac7744cbdc6d833bc4aeb2a649924e35e21c2cf1512d841e8678abbb2473011e6a5fc40609
5	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\x1896a8766f9e6253d8a86187f37138656991db396bbf6ed11287940cab562be7	1610056087000000	1617313687000000	1619732887000000	\\x16dabe0934911657af435f634e3ac2e861b06344aa8840b007dce147158db80cbf7b0f526e5d461ccdd0e3784cf0c7dc7d711398ec871684c8f2ff037826d20f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x7635f0d4b240462f3b5ef86721f46c71796c29a5aa10919d5403885e1999ad11	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xf922fd3323da4616d7ceffc9defb66a43f574d25a789213ea42197e0202adb4092cf23e133ed50b3e8dcf8c639ca6296dcf8345f95e471e6b9d4fa57319db408
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xafd55322074f620e8892443001891af6a78a388408737e0c056e4a685581f0fe	1
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
1	\\x5036ab0e814c4bb8182c7d4c9a24d01fb1762a60a39b244a960c9eefc56a5c50b7d41bb4a21c3bb4f2646b89aa424bd9da4874b33b61af634c86b7a44d271300	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1610056119000000	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	test refund	6	0
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
1	\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	\\xb898ab421250883863ea7966a19eedf2f405ab364a1fb1c5fe76604f065b6ea1	\\xdf6913eb986c80eba73e74bcb4e38fa7a050c4423fe6fc1b5b085e37c2dbfd01769362a41b79be590d9ae0190dc29c45155adf2125019ba78282b482f4308c0d	4	0	2
2	\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	\\xbca4b7924b246f79fdf5158f7f3a678c628d2099a1493f320d0ef08cce930a897db0d67f4178875232ef54231df4d77edbc06bbafb59088a30c91ec21eb9f00b	3	0	1
3	\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	\\x2ec9ae411a013bd739b15edb5836c1cc5ee9bdbca18120d57b3709b2e400c85dbb4d00c33105ddcb8fe32895ab54dd6090bca60b9f7b07f5b8bc605ec8a6b209	5	98000000	1
4	\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	\\x225c45583aa97fb24cc99776e65486eaaadbf3acec07af0eb22378fd14152378	\\x856ab690043aa772c115fbf0e9cca689d462f14ebb0ebdffae55d262ab94fd668277401e199fe236d9dbcb359894d54b56e8061396f4d342dbbae97f4dc3080c	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig, rrc_serial) FROM stdin;
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	0	\\x50ca3d95d8562ff58e3dc2a800ec3a33345c9706c4bba21925d378b28edf27c69ef30677b85c4899df926789f6cc8276b7f3922064f14e810b5b2eeefb822508	\\x62aa17d2762f1d4c0329a0fb06dd68676d4efe8f0acaae008814259d16e64cb40138fe03d8f34ad58564af86c589acdfc7ed777dacf15e84b2f332aa19218a23	\\x81d47b9b634ed50dc760eee13ce9a94a1d78a279a328f167d8bc52eb437b6c6a6fd5adac810e12c0db0d2445f1b49969aea38b0b65e9127881c03af2a9cbacf19fa846fa0219930dd79f2761e75e0e9ec6a06cd38582e09cf34f7b563e23b97b2f03a9fbd134594d1f001b23a9805dae3177e9683d347ef95a30daa859d5d431	\\x80e1607fcebf8d03c737d68883b48b448775362d852516ca1d1904a66e93d785a9868204efef969f90694dcf81a974911590e05f92235adc244e3d5aa4436b8c	\\x1fecb9aa6ac225eb223557d6339c021fb157b28fa9bc14f5ff163b21c5d413cda2a360113b2ae314a7a2b8c719244a93fbc9654507559d21f926714fc944cbae36bbba979615359929a4ac47f18e72fa29a1fad63bdc1d81a38fc4466373536f863787868882b9fe28211db36134afaa55eab261f8d002500231499408c59e18	1
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	1	\\xa40c672d0b1017d63841c788dce510111240ad1fb08b689a79b86f395b027c47294d6f8f0d74dc54cb97683bc4d37eaa71ee69ca690e5f6fc36b2531f9caff02	\\xe18c74430b1fc8a250423ee654ee96f465dbd9dac15678e05cfaf6f58f329915a5f4e0d0787cc5af29f253ceda3235a68ddfa19e01a3eb06ccc0f1786ac81a9b	\\x2c0bbb48f17c85c8d4184f42e5622aae4472795e19162af10b446892bc20772c3e1f2a4c9e8724f819c9f03de8d57717509d622d4b803d35f49bb5f72706837feaa791ab004edd65ac41a78ef86d5f8b14923b05b75515ab242a7a8936a2a4c3128c9239d320944ca25abf9cb09e3a924b6b630f869972073bef2b30e0d75e74	\\x91a59d6533fba191fe181bbf256c097275573cd0ae690782804b60269beec257137fbf2436806532f3b45ee2d11d3996387b82d358d665eb0fed1ef0ffc811ae	\\x70417eef982ed0c7fd1d63b76fd03fb2f8f20e8a27851f6d5e7904e473f0818bca70d6848a783fc43a6ccf0b80ff66438466263f614206f46fd8eb7dcf22ac017a0569ced4bbf745d37d11a3bfcdf39062d98c2384e39529cead6f883f73f597bd3d56e7c9f4ed076d553a74ea16e4eb7a88f8bf00bec59fd7a561be569d94f7	2
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	2	\\xec9807d560a9f4d572f59bd7a96b18df5f2817f028ef39b833ef2597daf28caf8fd9323458e9186310d8f567a329dd6d80d903110065941800ebb6dea797af0b	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x0a2791eba42a5f4ae58f43d2d1a94a04e0d6b48fe5c5ac716505619a5d9dde3f396545e4819de07223bf0993734351f9cf5ce8c075a1b7f7db336f6e1743e527ddad4d95cb3b7b5e7957f03914cfb92cb9654234e2fd096dc5193273db318df2c2986d129168f776968eac8a3b6d27f4e1c90bae7b3d0dad8f11649179a5304e	\\x337767e8867603f8143bf6653b9ce185da29383c857d116e9354e83e6d0db91d6449a291241ec7eebb68d27876588651dc8a1564d88fc2d6530ba00ea76eb72f	\\x49123cfb74252c76783093dad0dce2557e4ce1f5af8f37e738127a110c89da3739d6ceaaf61676e08c03492c51f783cf66e995ba7fa18c941cc9898d0f29483b596d412e664ea198e5da8b04ff3327860837c4ad38a48435a419f5b3f8d34f0ea799706c7bfa4c548a4bda918ac0b064e6dcb27c518fcac0d02a1f1c0030ac65	3
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	3	\\xd91c96547ea8f644bddd55bbc3fbef7718126cb6b6e1d4a0acc2a596791b1ef180ab72344db867e230736bb41d27edfac32f95ba5ce413d94b7754f7caa0a007	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x9f96b4bd25175223a6079a0a1aeb5bab44e0d07ba8e9abfaac4aff2d916ac4852f208123f910514ddf1ac5b33de6247de614d0969107f645b9089630ae6669defa1070086bcee537e9176e564261b89150ce4892555a1875ebe457cc145ff6754cef60d50fedd9686fcb1e95f343bbcf63a4ef4a390654d0681b13de0e67bc69	\\x959bf9ee177ae44ac154ad7c343997ca24c3584cc723aa0da0cf0506edfdda446b516485401d7201e92e38255d2358de5c3cd7089648edbdd8315d2793bf3663	\\x8605c7073e86088c63d81adb15021a5a7fc7a6f410941f89108a380269b00bd9d1e3c3be60492c78ecf1e31b6e9d3813574e1ff2ebdead3f143a6142a843a6fcfae3ecfe89e601f76b5f28dfcea4b95aa7d62fd2de5aac3195427c40c00ca3f12850c9590e4027835247cb38df541fd71d086b9b76865fafe6435f6eb24b524f	4
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	4	\\xf1c126dad5e0a747df4f88547de2f434fa1fe0eb6d984f02f66a834bc2cc03e70426656e8b3d045a76f49384a91f585e1164d4cd0c4af07cd2c821922b6b840c	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x779ef4bd573ce013177c0dc101d641c1f13f39e26c45e6c5a7ce82669b33b3d4421d9e7cd29430069f13c81fc58511f91cc6b9100be1ca476a99c43c1028139fc698845586682b2a7ce4c6fd3173cc30c4123643bbf6d3f4bb0bb472362db2ae66c2c968d23be6ea82f8e15d623d8e6c9d68c305c92ade7d8d8bccf5956d6fce	\\xe1c6b1e46469a285d2a21d262c7f1fd9576676c4632465b92ceb594d59ea478a36b299721a7256674fa88262ec65ced2490c8e57772202b9215b5b768c45b3cc	\\x44c412f372c46e5eb37c1aeed0691a9708c65a9b5403bfe1a9e6e65fb348b192895595c0407428162dbec91d46e6eda4d78cd4f21178aea8b90ae2c30838dacd6e5740cec00b2d0aa87fd306815f8c4d7006e99abefb578d21f8dee200664c3f77ddc949a8dc333e1e8f3df2c51084d95d5bdee93aecc78da00b87375ce18632	5
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	5	\\xcade69fa553e59fd9aaf03ce3fa1374931519d77222ec0eeb96bb1bda3da8bb1b4bab011de3e02d2b307a4a5474aa2fa3c76eaf1b22a908c59a24f41e17a0a07	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x4142037fecc0cae5ae4a3fbd9bb4afd7a3eae0c36c40d0dbd49ac969918a89f6bc3c17cce6818a442173759824adcde78dcf521ae626ffde9d19a3da9e7f3c80070cba2c0190146106c2f90b7ee08ca05e4fef798cff963df8109fe4f8b9e4638bd97336a63dd5b7761d8e63747883edf618b785dbfef2f313718b45e7b8f505	\\xebd2b13a2cc828068ed9555c2a4359bd4508c651a62c1eab0e202625d1a6b5793ba63a35ad69a2349f9e0620a0d367ee6645f5e8762e9e97886db37a9556cd03	\\x1972d5e0f5148857169f7c49e790712af920b45bc9e192b821aedd97e77fbb14da4270a8a6c712e4b4fa40489a8e616f0bab62fbe57183c5ed4b21ca8b1246ec623b210a8c53e0a5af309df2f229a9743925250f7578c9e8115c51255550105c5a5bea8657e8fd06ae13ab9b4fbd9d9cb8b589c4794bfab9377b06d6f54cd11c	6
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	6	\\x938b87abb6e3ea6d3f8fc879230789188a27a12d775daaddc39602046a01550d6d3dea6aa1067490072a7e08dead2290ac129f999cace4d2ad01e3a3c2fdcd04	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x5976b9d56194b1fa999e4d12a4e95993d133bb5b334e9507a58743e66f2f0c04ae02c00c4fee5f9ef09c0c1baa187e2139d52853cafa76ab1e24dbcfdb7e544f6a1f5106f6e506e1732779f63aad25fdc1e0e3602ff971027d885f71f95db8cbfcdf93ae92e1abb541f9b021f4ad6cde67a938dc1199ab6a449c9674b3811f5a	\\x4e440d4a049c2cac8765cfb2e324d5c26b8dcd18bca3076bd81c762d666ebd72cafb6671e03199ce8db9be004fb27cdc1ad2f9f1cec2f26b872a8ed315da02f2	\\x882db7f4863c6ecefbfb975611ea5a3d582a9d5b6b5065e9072bd48468d8d8d0d6374684cafd89cdebf0119c513b212b4838c5ac48cd176d35008eb10aa4c84bd0d5ced3f08f805b17cb2b8e72e1a6bba18d25211d23ca8cca89a69793ddb199cbc72b42b110d15e6610d930e7572c3c007a4478489c9c940861295673b99ce8	7
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	7	\\x7daa5938b1084109163789d35e60d2da4f1802f6416471153fdc99020b7490e686b41822e3c541d917a69a5c644c473845feb84730e02bd8631fd1b440b96802	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x26e3a95bbbd772065b1cbbf74de8f4ed36a7e571930a59a381b390c5919eedb289efc7462d74217e8d8a80adc990647d35cc8583f1fe9736001b99af2170e663688174fcf01446377479a79737366370cee94185f447e3c95678913a8a458ed67c7862c935b2efbbe7ad72884d5e3615703042795de3cd8157f4d7392a4694a1	\\x3aeba1539bb565953d8e7b56fd6bdc95580977666262b656d7afdc04f9bcb66a47cc53600fe0dedb21620bd417fb773c2093a8a0c4d0a5a37cfc06bee32766d4	\\x9cb7692ef8a3035433b0e2552b87f9d7aa96ea7f3e1f91c06d8a10ecd1eb7510e69206d9cea6a974c2925753c8a12c1dcd8f4b424da30b1f29ff8e2dcc3e0a5cbf9d50f415d5c0cff4f8761cfaab44de19bd017d74c79043a92633cd989b78274b57ae2f8dc73589aaa751a6d0c78e8a1c10335195f9bd5a57383777e66fb9a4	8
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	8	\\xe7e575cfa0a8eb393036d247f702d0831a0143d9abc9456ffcf25fa0623757779010a1b248d04c2a8a5b4f9e656dae40290505217bda2fb18c8543e73961e40c	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x7e708e6d045bc6c830659cb12e92d0488095d0fc0c446b4ec2c47703353ea07f95a48a2546965535fb8c4c74bfe4f22b000422c300af474907302e4b3cc1962e379d3cd19a9350cc3baf65d71d460e57c7772f8ca5d6a056dff3f14f80f0c3b4f3940539bbecf99c83302cd80078724d590a6766bc880e09d06f5775cc1f3b35	\\x46926a90adfdf0be4d33ccf177e04015e98022dc2b3a4cbda06beff9de037239292f00739708377be5ab8e077dc838404b935a698cc7b4c06bfc2c0e8e54823f	\\xa79cf281efde2a3fd05502935464bdb46187d822165150cf0278fb36296320aae513bbae6097325f960caf3582238236d57bee31f1a34f5bb0f42956084243cc1205141ebd9550715368a4d93e64e3e7de0d20701d2905726bfec302a8a3cb58908afa25f9f0110074779cb0e40080ad87562c664f30eba32e882f7cfc772ed3	9
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	9	\\x6afc3b79ac58be358e38963a7706b8d6d0be8302cb29f85006cef421935d03d009a7d1a769a031518ffb813901622b6f1f6f7581364bcbb3ea587a044af5fb04	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x8d5f673bef20bdf569668010e2f4fb4bd87c14cb1f175a860e48442e164f64231090f62fa4596d453350a1444ad343998310ba5c933907abbe87fb0e875ca16826ca4b07034bbce260804221b615abf183d0596fac646cbfe0b9e8cbde67d0b4f30b6af74aea87a1c8554db8ed3566dcc9905cf0ef4c23096a9b0e0430e6cca2	\\xbe3f97486fa61b67a990b0cacb6ffead5e60c9c92b0202fb20e5023725327ff1ba80ccd9df8b1bfe20933f38a96b65ab476064e132416b4bb9c4338f48438271	\\x507434a783eeeed7f4eeb3e7da7b0800ff998552233fd0db879d39e00e4dfc7ccfea9a35c7f83954a41097d037a8bbc2a12e3d07434d0340c15996ca7c1e1fdec433a2fea971972035aa90429774bf3358c656f9a2dbf1fb5971aba9bd5a4f1e3c6f9509f6a6eb20c484bc9c11bc9051f6b01f82aafd2622cd9a648c0cfabaa7	10
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	10	\\x270157133a2d34b3c77528976e91a77b5d6b9aae885de0aae3b11072f9250a4aa4a6f5bc6c519c91cce07050281071dcd233530622deb017a3ac1559f3ae6609	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x783be8ae24e05e1d10ab928304c0fcd6bfffe30a7c3a10cc94b934dd0b608019de519bf91b6e51aafbaf5777da98a2f192492844df14940d6aacacec5022ada67e99a77c8b0ec3fddae107dd66dc6bb862681ffc9f70a785971f117ba72df64d536c117abc10dfc402b5f470978621b51618fbdc9dafe2864c85b89b4263efc1	\\xb36702841b7fe7a443bd926faf962431d7791d427e4a7e93443e760984fe9c9584bc96af81080d3e7ca6b315a417498470fa286aee8f0b51a22bcf3bdb8e4695	\\x2a5d13234aee66581abec1737768c5200b5794b8d0a86951fe288d30c6ef5c1688ebb20d29756ac3d2419bc54d55bb85a0b51a27ab0ea99042d83c5c66b711a845706c00f8d06af2013e5bc73c0bb80142afa68d95112dc33d6159ee304b668fe18e4f5f0bfb224ee40e571282b28c5c4fa0dca14020a2fcfa0ca60bda43458b	11
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	11	\\x99d0368389aa0445308d5b7e5f0bd2a6c1b7ca6fb6befb24bf938bad9855b24e03a07145a05edd0346077c6cef944e66d545c4164f3f2327e3f6f7c55d025b0e	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x59f14e37c9e471956369bc1c9a558ee0932a754d85ec7f6edc85c7adfceed5da61c744ca537701144d3ac9c946046a5a8a85c84fcb66a21e3a559cbf992604035493392aef5ebda1fc597bba66aa88a182e7111f6fbe1bc25d09debf589b7b4e099862d845878fa1704bb4862764e0cebc55e296c15838545e990cbb247693dd	\\xf0eab845d801b90ea104487fcbe9671d00bc0ea65fc1a379a323e8a3ca1f4212e57d11ec362b4f716192b283f95a1823a1c896c64929b5347c7807bdecb67eb6	\\x287ac0a58cbdfd532d74c396b86db19811c6c4417e87c548c3f666a27d823153e047d37790b98e415e6c6a191a8496e26bda63b4d4874557cea2e5d7db018d26742ca1de131da9e4735f03e55eaa4ff662e2548b7040674ff4464aa8fcdb4b8554cd0172099bb38a8ee487ada159815fbba4858234ec1ad0fcc68affbcc7825e	12
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	0	\\x29dcc95a8f43d6d372d84a6ce88204a339ac645c4341b53e098da95d70bace5dc9b9a9c826c7a0967b8a2df2a98774b03d21c1e0c6958f62bb46081c8fce5d03	\\x62aa17d2762f1d4c0329a0fb06dd68676d4efe8f0acaae008814259d16e64cb40138fe03d8f34ad58564af86c589acdfc7ed777dacf15e84b2f332aa19218a23	\\x88cf819d5252dccd48e2eb3266c3f306c83fd6701b7f668d96dd3a9a156e39f679feac20fcfb5b8143965d382286131509dea710e6ead02afaa7e1328b6ed799ea9eeefdbe054ce8e30f00db7f5d8531ec44835f6568208ba2378ce7e052cb5889bab36831e3a85f1187b3de94014d48b4f47bf69e52e1f141059021ba3177ac	\\x18ddb969b779839608105939454cb61343f57fe28855b0498e849fe76f822c0d0134cdeabe9faade40ad3a30b2a6d9f97d0ee426b0e9ce281bcfbdd152a7e58c	\\x748b531620371b52b8854ef072b54be667300a0c47dcb2c1733c81ac04d2974001365ec79a3fabb1b39d04964dbb9476dd0571c21b392e7514a557a59e6fe47d63afd4d95971353c867a65199b2294e18cd88aadc49425f870962d57ddd2bc39b1ea35da3b6f1c9591110c0078f027918cae553a618250573843ce99aa1c3ad5	13
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	1	\\xb5a2813bf8cdd43a442cb9fc946ff08d970be7b5a3c36bcef03c1ecc90f65dbfe98e403e9f638f3647f716e654ef77cd072c3b1543e2785785c84cd036e0710f	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x0dc2c20f803b6ff403c8e862d73157919431dab2b3ed7bdb3dcfc7da490e265c0e44543218e6fad59001c312c040a5bc126a342e4a9a1221ce9b29d80171a0c6efffa5d318c3c7c0157f2dff2fc9edeaba5e8a5469f3b7850ad55775c651ce3939167df216d7a04fd8fc62e1251c2d3e3b8af2d06bfffa7b51816a763fa478f4	\\x3344bb6d43b78edd71c6594934afe4289e5680b76152d093db7dd96c99b531fe4ae62cc6d3501654f2c01128445711e72d1c180144f6d8d3b425643f01b936c0	\\x2acc169000c014e67018777bbaf0608e518cebaa747ad3e54f534d50b6783f0c183d2772cfba4c0f60e89bc2c43f6a2dfbd6a95a6989d52db33412959b66ebd6eca1059aed2b6132b150092b0fc1d71ff78d7204eb9f763f043562bd72dca9c2f5cbed7d95164aaafddd68db5383196432165eaa8ecaba4e16253c17f154191f	14
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	2	\\x1eec9fe2ae1e3c87af11c588612f15d6be816b367fcfe43cfdff3a6942aaac033aba1de4a73a912b650a39cd4f42f8594982e2e8278a5ac62ba828e3343d9608	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x4cea796765a14b210769faed022729358308cc3b5535bcea58d36981315a4db0ffc7929db14082ac0281cf30d6d85278212f3d1b1404d9adaa0dd320c075fd789903bfa531d8abc692f6bf78441d47f1e38a7e8a1527239ced2b90d75e8d744ddef5f32200bb2d46839570aa98c3be47d3ef4dd316237f61f823d0e1e4ba9b72	\\xf13f52655a6075f458006aeaa72e96fa7d0ad6b5cb4c816c5b4d3999071e3e6474dbb60d63c2ce4345604dda3a5e5c6358374857aecacaf083c48e18a70857e5	\\x8611d09ea3c065f7cd9cc2b2b67e60345f0721ee330decddacac1a93f4367ed06c1a0538690234226bd1a29cbba5326ed8ded123426d149defb3a1973ec61a7963ae1ef51d79ffcfb13a5f65ed530c4b8b10601a9374a4b9b599a49b3f088a2f206f5f94f13bbe0bc5f45bf117fd35b8c5a99d84da1e1f4aa5c1a7b414752264	15
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	3	\\xc80729bacff49897c31c41487e8c3d1d396d1b7f48eaffbae6d0e3d3250258bdc3adc300345bcddfca46ee0f337d4bbb9dcd09638b17c1e8f878d98f60c84209	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x1f3c1b3ecdd14c5e08ad4de9ed949fd85dc2a3ed5ed56b9c1db645aa253f40589504c4541d1ba8841208b1ab401cfa50fccf206f34a57f32ea95ba9ad5af61981b5f52fb00c90dc95723a82878604c44eb30316134ca9467f6f2353b8a9acb1897b829f0d82fa2932b910ca882463367187b710569c5a213635c5351bf84ddaf	\\x0f8a8e136b66bc24a1f6e875a5a3260455cd658c1e5ae95ad181b9749d43cae0e61219674224e98a8d1b130c1fa463d1572033b1d24ae9cea83d9727550defad	\\x76cec03a44350d2d68f72219862e6a1e69a472432ce22e88dd830effacbada3b664e6613758b3f7ec2f9b360a04b820b9febbd780dbc6fdbef0cd63de56628ccc0aa7b3661939569bc86c010e28fda631f4a18a7b34efc9217fe9e3322cf16c5e4f812d17ce0c11e06edde2918ea0d36ec3c81525715ed9b324165978ac1be03	16
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	4	\\x97bbf67fe38e927a05c4a09c9eb42bd6461f8aa8dd308ddac601b224f43c03b0a40cb4c48a68d3b714f52fc3aeac03466a42c894471f37a8c0e9be22e2bea901	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x8fef6b517d43cf30b5beee489f8c4c24e524d8c894015919d1895a5c282b9ed88ebcdff3fa673f4b9a91b745c91dcd9bf18c4910a8bcdbcf1273b38c01ed1d53a6a5700994438f4b0c83c51667af303ede8a12c80fda8e20e725136c43aa15016de4fca5eec78f09f815a89217e9f49e0e938e684cb806662cd3347a2645b8e2	\\x980ba8e6db3de202825773010ff8e5974e2c9865148cfff208792389ea600cd3e6a0515133f6cfcd955112bf10e2ca4bcf5e1e8989f15d8228f198bb7ddff251	\\xa5a2947104cffdc28db303009fdef042e1a5dbb21726ed314282984f79064b8a725ed76021437d4fcf2720517093ab8c42b65852956b4fd2a323d95cb9811fd13eac3a4245da415ee91986c72a3dcf2f86e3539b6bb601f5f8057145328cca85013a5a96d9af04e125470b6a15b8b71b76b0839c6dec15550a7c0d83457dddb7	17
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	5	\\x8c0270e8de10292eb136463682b87e5d2fe1d058e60eab17b0eec31df99e80d0a851b5be1d16c968a490bb769cbd74e02baca1cb2ba1b2a0723faf9671031309	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x2f2db233e272fac0b1863a4a0df8568f4a94a3c990fe46e796795b5d7185fc8a008f5330bdaad77e0956f16ebac9160be7997c87aadb08c8a70a275670fea674a43951289517b4090c9b2d454247432e0f788dda330eead430ed3620326a397eb88e674c52a279d0f2d32b45a449790994622e2c489ba4735810db23465e9b59	\\x0c6bf95f3f2fa158b7b67a041692e9707e87e9c0718a537d07b533dbb76693178c7383ab61539df621354113fc4360ae1003bc7447fd679e825cb5b7a1f08049	\\x70b3526dce4bd6f2a6caea37ec1a486fe20aea2cb531b863c43ae579b28e125e999328442cf811bd8393f2337b66f78638016ca8b4d73062abcc83e97152616af70f7067c76e30dbe7bb5f96e08e0c56f661f4c420d9ee2521a0392a4613038941d79914c90c0debf2d1b5e5bea64ab71587130014c9ee1ee55d623b68b95cc7	18
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	6	\\x4e1dbe9c019d63e458d02286d643212a712f86d1348fd935e4bd934756599692bcd23926fa377ef2ff2ba9e3b482496a33504499e7bbb078b6ceecbeca44d106	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x9a78cbf9c067e110d21149bf5a5b01bed5bf2f0c3d00f833adca952a3baa36f167b19b1cb842446250c69ace793bb872cea1d95ed33985b215be85149f90ce4cbb8d07ca3e3f2d7b22389da47b738e3f3613ffe49a593994f90771862430990a3e57e539a3ca814549c85a69ab674233a03a31f073b041425cabcf56902ec0d2	\\x6278977a5427197dc0dd5e6f723da8dae8cfee8eaabbe58dea406c605ca8ccdc60ec03098fc846018d4f318164a83cf42e3835af528f89417ee856268eea8703	\\x5c36b2b5f123f47b471d1728bcf40856f8fbd4620536ac8ffdf6126340ffd25edd82a36b823937cf9fb1ae4eedf62dc7383d2b05fc4d884d2af78f6942449ec5a5cbb56b28813349dc06debe5ce503305f3884c136331ed566984b96076aa4fadd8896da89b9e0635f18ed89776c1b261a2bdbc3888a1046a4d74c43e8cf6ab9	19
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	7	\\xc96830e63dca6ba810459331dd44ce521fc71142739ea8e405002535100af3bcb7ffcd7a654e5241344811753f9fc8dc2c708dbc6b0bd69bb09d310974f6290f	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x7d71283195a456dddfdac4ec76ed71f3a82127125ee775669f975114ba07679a91da2e1ca125bde55095ce90ca6122caac6ce87f0ef770f008dfe0a464a1c1d97a07b7e3435842955ce447cc0a57c7b8124da5de536406b5882a1675583f64afff14b4e9c132ae6b4ecfd358e439492e3850a1bf9fba2aa182db7d95c9bc10d7	\\x53df02339845237569e5eb5162e96579efe9981efeec87e1011b2217c73555b722b5477733d7da0c43e6114cb9e57b6398709bc607803882246f9475d8cca2ee	\\x4d6d72e25c3220ac548ad05a63ceb27caace4cb3947be3878d2d7be04d0483ba80d92530428045062074bf8f1b52528a354263c4ce359f970e5ee6305b13815494a8696f884481f30ceae270d594630b78c14ee74b96713141119a95f75be33df8b5d9a67deabc5bea181a4f772f3a1a84968ea9eabd61fd1f50a4b6e2f92ec3	20
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	8	\\xa2c8e8af68845acdcd0d6c27b747b58d3071fa8f91f6f65cb20344300b629201599fcceb724cc5b2b8fa705d1e7b7f7e7647abd7af7f63a8900d7ca75b580103	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x20c5ff61d54c6e48efe94074d650bcdc1e4c4150417d2a0691f6184c1e4011df39851ec285a9b9855f1cb87c731d7b59376e03e4e8eb13338bfdba30b57d5aad795f8133840848100a009a191ee10480f996d18faad3bc14b977f1d4678746df3dd2a01dc6924bb41cb7201f2ac0f35ad40cb4e7f18ce5e67604a23d429849b6	\\xa98f6db61f2969d320e3f41264274c812c9bbd49f4701c69c4ca4baea6f362b6fa171d11031778df29101624ae61a625d0965f7e8fbd48a52b0723afb1a73e30	\\xa47eb653eab705526718a37f4824f6899f008859c45a6c1e0e67ed0d214120ef68e46b1069349dc0062308e8fca66b369373571838775dd87317b4e6cc4a02bc5e13edf5270bf2701d92d12bf33b2a9dafbe3830b558428488cfabd8b3a6561d6460792faa75cf8184632a5c8f5991f85421593a2bf23659c1ea7e3322e08256	21
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	9	\\x4220ff6bcf1e04a48fe61b55c6def28a702b66161b80d0afc488f417446dc83ff944867a6c2b1f46dd353a7f597a2ff96481bee56eeab1ac0933c49626ccab05	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x7a99538b19a0cf05c85f72e4c9a99a4a9b71e876ddbf7c36bcec005c925f75236709a1e30064f7e498cfa4777ec7026d072b338e32e2f2f71df07b0108763cc5f05f136f77d4ccc31fb647cb0720186d60247a4bec2306b151a64b27954bb08dc02b3a0ca2bdf77f8e0ca080fe70d5284cac24e734bd284bbd728d620ee33455	\\x8b87f0096a0b188e4fe83dabf664971e845934bdb13c948d67eb1f4d91f2c078df5f9d5d79feac8ea82d1289755c5d5be075191d4030176847a2406c4ef55c56	\\xa60a30068b0125836bb17956163dbe61ee217d8d275d5cbb0df0e7d3e54fa18320ce53ec4221ffb4bf44163f47c65d0c2990c4bfb3c2230ec9661046e7b477facecbd3ee79658633b03b1c780079817d7efbdc3a3d057aeb491f175310c951bf100d8b740159dc930c6ff910c1dc568863a2123f98802724a604fae2e8fbf9e1	22
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	10	\\xa6c33109430082e7b1973dbec439a1b0333ae5198ec58278c232dc179e14a0e6849466de3747a07ffd100d55e02ffc6f1ef5b7367dcdd274aaf0e9606d510f06	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x9eeadc0a96f491242d1a718a704f3b89ec2d44ffed3150f3905c9ea0381becf1989e28283c1f94f5fb71b9164fb3c2b7946f4a2150cf16c2ecdfc9ca9b54267999be2b1cecaff6ee65a720d2e605427f7620e0754d1afa4dd97d6b2d5e554f36ee0a7f23e6d4ac5d9acd4c8772ac838136b3772adfdb821cc1b23588e83c98ab	\\x90bb12efd988df0169c37cdf9662ef74264b17bf09c016747839ffe08447ee3d1bbf05562cf590a9c6050e2254e00a56925334fa719ab4d16ecd02b4e6c088dc	\\x27ed4c71447c80069168cbc73d970b43fd7068f98d200177713f9f6d90abfd229babcd7cc5fb51757918bd1f6ba28e4141d396df58f8e9f923e1da2bfd62c03f46d2e6b37440eb8f21ed2eaffc8a6a5339a8b75af535d41dca5128370550f7f3028617c8bc85746a95063a786cff35172cc06f34f8498fb072fac753619fb6cd	23
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	11	\\x0578cac058ef43099427ed2fb42badfeec3f6be76e4dcc3892a74b4e99aba78299adc35eda12acc3bf535d2479fe120c9ee2bcc7cb8aead40faac123c4296109	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x20db915b80789fd985a36508241cf9cdd98a9231b35cbcb5bedb28f2f53eaaf3e40d21f946f649874fee9af984398b9f0d8069851b619d7d7d642c73b9fcfac06aac8b7fdadde62365e3073e41bb419c5f5ff5b242841daf28266cd329510bc878206c7a5b75232f6a016fbb4ddedcbbead16635ac9988d8febdf41bf2fd1f0f	\\xd53d93367a2e01842308fad6e1d38644ddcdf0c0a039cbbc9648c1d5acddb503e9796783fa5e73f223f66d464274fa1b541cdd9d8e88151bac4782d6fa83b08d	\\x36aa9e2548626149863069186e2f7ca69c9429cea29528d11a7d434e902443e5f38cf369983780ff0981db137e54d470c3a6dda57eb71cef882d458220503477c112bff3fa31b7cfc1c5274339ae9abaf2ad7bc90fa1120b0793697fae777abff85478c450bb4fb16229f11020e5ff2f0bd49b42dc25655fceb2f818405355ee	24
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	0	\\xaff7b0a628660e772010d69735beb7e45a9d570cb8c920b3b641d127d1e6a9e09d778b3fcfad44b76742125037d7cd13f73066c8fdeeadac9d80a921cf6f5d06	\\x4f74dbdd8370937e54a0feb69a91a28151b1b05d94a81b4008f625d71b34d63f8c9a5f907332c8381e69d504f2ecedfd83b8ec505d130ce95c90a943ee819dc5	\\x5f87275886a67f96e6c2e216004fc616fbe3fac24aa5643615abbab9e1c69b0c2e9750a8dee07ac0d7b0cb786464bade5434264069abf10d869bea70b9b732f9843f82dfd00a815a018f3e482b8c034c982aa445645c5a2629c97e1a4f8331e9bdd7dcb8fe9de462f04ce0008063d706db9fd7d0e30c1e7cfee508c5bc82921c	\\xfd53dcf618cbf82fd54d25ff3d7fa544f692899708ddd2fcf5e0321d67d44d6fd6adfab1edfa0b1a53380a59dddbf83852a507fda74fdb26fdf8170421e05bc8	\\x845d7152bb2b2359274d146870155f1bc00eb3958bb5e2281b05d2d6fe26ddbc5176e533dbc454e12a774a0973be29e455deee633ce2e17293d0403c03ff96acf75dec325827bd0df0a6ae4a8a0e5b0794f05df0a6ac1cb732fb53bc292ca26bec6ba8dab13c57b5f0e64bfa5572d8ea1a53807b0852b6d99c6d19410e3d4a45	25
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	1	\\x4d98c125253be679c0ffc7c6a3c4befc1843d908d4fa18e7ca2fa4673514d9d0053464fe4fce59b9773a961045e642cf00d5c8fa13a0f8875f52116741223400	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x79529108210f8c34e0ef989f01e6a037b86f3ecebf4f5553613ea0590bcb2ecd55aa708bb28ee18996d00182ee033a7a9a18415f8497b0f7a4bbc45e0ea0e196b9273e6c1ed859f3596d06e8cb140c10675386d7a1e032733242cb1f52cd80762cce7d51f5bcae51e3233228e05b3a33e5fe122f923cef21984428e80bd7f098	\\x3afae57683eb0f2ec5cd4a9039ec288e992c4f0e05f9d07227976fe05c2ed708a122283b46406029db5223c1ef74d09ac0458075ca03268ab3e85e7a019f0b20	\\x10e8c887df8d9304ab20e44acdb71d5b7b5a8b67a6774c268e414b5a4ea3fc35f53bbe0521f81ebd32986ee390a0fec4c22e1ffc6cc1a84b47b51001569de886ca185bb5dda4bd49d30b12ecf1940110dcb4fe16267ff9e4f5203f8005b61aa629930dda7a0c30a2ca2bed11af4efe9cc8767377c12d91c34d29be0db29a93c5	26
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	2	\\x8a4b6a782ed7202da9426b9d2ab7ace7d1a45355b8642d141bc42272901b4ade93b6cf2a6971310e81be6fb61110a142c18ec8fd5a2bac5ff8414824ba80ba0a	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x3b8659a16124bb8edbfdbe9aa8f544374f53fa4562fba1a7dd0f371c2cf202cde742f46de99e15f862738923e770ebdc4bfb16dd7cc9dd6758cbce161bedbb975471da39618dde79016106e3584564374fe76443aa47f2ba46681a3bf53b870f999a36a46fa74201777203f6bfeadea186f733abda3bf806299c7cd6abdf6973	\\x41469f77456ab4934dc65ba112276448392586acf8350304e618f8282288cd1d4037e334fbf4dac589f153d068056e947b25081b09fb84a7d204a23bc9c80b1e	\\x92635cc78169425f06c9f9f4fc6d7711c36c0293c77dd05a45da001511abd65906f93265ab1c7052cd962877c331a66d0713edd9dced855ad2af7f373923a7a49f5762e65ca3bee9ebf4869de925d71e095ea1d33db22e255d6618b67fb181b9f30f2afa9d7ec23735886f1e088388b5c61ff2c5341f34584ff0735cc0365a9c	27
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	3	\\x63d6b819936fb12a9e5274c6bb1e80cd3ba3e1d7095f1e44f39ac442e45c6040842b7e98f755a862e7cd11e53f7ce3e0e7f8edf2f807181bc049ab4d3f679401	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x201d17616ac566a62d3805ff0b903ada92761450cb2df1591e2cfbed00dd9608bae5fee69aa1d7046a211348a9985bc6ad3910527d20c8a4889622b34fdccebf93daf99e855208fac8eb3be908a10aecadb0242717f922bb2d6434dd90c05fd325e656aab59999f9fee625bf8ff1085dbe76f10a710f52cebe8565064ffe7fb8	\\xff251fa19548b98cf786fe257cfd5b6f8ef099b17f931008f05db15ae59e70290475b72b21d0f5ca8d2af936612f3e5e0600caf6a78ee53d9577d06e50fb7d86	\\x345c9fd7cbb88fcb951f29079442fb5d560e8bb8eeb43a921eaf404ec3705ffe0c45ee516bc8239b6c3a3d82f893b642b363378a8feb34a7de0e68169d756966cef3a95cbd54f22f13a64b482931bf5c6e44ceeaf0668497ba3ebbe23e33df58ce57c7b1b1155acd50c1167764e3a69c97ab03655a8b7728939d32b3c805727a	28
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	4	\\x2499b2344cd395c687e7572e2d8194cfd89bf61db5dc9f82a003c6ae7f043097634e4ada2de18314969f4ad65d2d2ec23564d430ec8218e225ff9afffffbb90a	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x71fd61e27b3069348ee07033eedd7cfd604a8aa14a112f80bbee94cd1d90a4f08c7d2f117cce323f280aabedc5a53e4c5e83196a6257b5e0827c17b924d8d11cf90ca9fb50ac5f2c5e3a65c03c51c1a838548595c28d3165aa65304875c4872409bbe1942bd490ed990ee4c2838b6af863abe715836020ec1eba2c54be8c6d62	\\x72ce10bfad0b22e43323cb5f02fc795d5fa2cfdbb2e1e3e195400579a2610ca97d23081a77716caba013c8f46db453ad1c8f9777ee50865d72b2672a17103f86	\\x6f0503d58c562cfa2215665d09652ed6c4e801874b7e6d75624cc51512c9de17af214c0f7fc5229aacb12ce93c5d9024686d2b4fd8f15463e97160864fb8da0de62905a23eff38b26cb91d47e9bdccdbb4557c27cdd7080a2860db446071d3f326452de430683a10442ca46fafbe7bb153a9b8ceb7409c31e82ff36e702dac07	29
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	5	\\x236dc90ba216b990ce25a658592bd04a5317a11915e0d52144dfd96b195112036746d5dada227534b91d22f64a9559ee2d165ea647af414d4b2a4136131edb0c	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x745b8f7552bb31c84c964712ff8ffada7caa498a7108f0f3b9792c8d433ad98efb7c0cd94afa7a92a7013e535428b310151c07ec213a04aef88a9fb9c22b797504102693c86c128af1ff51111248005458201981aa8dfd7ef26f9bdd53c4cfc0638ae645745f93c5003f5c6de99f4e0721296021a8949c5ee1eb6e14a42a362c	\\x79bd5756fb0a6d70f2efbf0164afb2f28bd38c4e37b3bc0081c1a27320e6983bfbebdabc70fcf75fe19ce632c9e8a6420a9dd8b98173abedc1161cf1002d639b	\\x78f83554bfc27541c44b7e4ec09f2e5fb8c8d2cfe8e56d9eb9bb1abbef00326efd06b6875e1607e66b84e00462c30d17cd975fc12a516d18959d8afe9de2ea6cb99d357066cb0a35aa19f640c293981f8d88e0c092728f22536ddc526ba9f3221aa5e4e5ee31a15fdbb4491f83b0b2ce0598886a0f76f65e785da476791ecd04	30
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	6	\\xffd4b392caf6023ebfe46881fe6bf889a3b68c7dd7c5bb42dc6224ac2cb992fc35c29d88407a903f754735ed7ce1abeb8e1607969eb12903dbf71573bd292000	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x544800ed55f9bb40c51c43dcdb59debea6b3ed36821fb66dcb0e65622c9db8f055b4615f0e78a6b6a75c659a96b35a3d6a4ab0b1cabfd62f1cdf50895cb294c6408eb0e63805ba697dd5ddd796ae66a1be08efe41e23ddf74f7eaf1ab0520a2342f6bd1badcf005b7e5bad3180420c7cae65be37d20594938f5de71101e2d480	\\xa13e7b8b182572a5852b9b8e361462d98ec3e2b5ddffc964e3082f52409f9946b1e9b5494c797afa3ab507311c419aeaaf53c93943aff28055172a941d4d1997	\\x3a31a4bcd2ad893d3468fb0affba8f92e2203084fabdf722aaf4e277ed3b071763d74523b7f55fa36c77ad540ab2b6fc6248bcaaaefcf153bc3ad687a2d93382c21618d0493b3480def44887bf3213447cb1b2bee6fc5d9cdf3660fb62b6ae441dd410eee823ab707e4bc1352a7dd3a8137120fc41fec2c46c4016171f4e658a	31
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	7	\\x00068ebedb64b0423c47f6f7fcb00bbd988ce06375ec32c37cdde33a9c2b292e5a96b05ea0ee7f50d26c251db04062a1ecde24e91c1e62cd41ac1175cf044d0b	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x8459e7d7465fb3c84f206eda511bd719153a95ec3fc4f47ac50aa2b0892312e1c3da1869e7509fe8b694d9dcdbbdbb02c9b8b93e8461ec642eaae463b390596eb18e2702ac151050f704447540c48011aec9c05b6cd429630e95d24ed321c59c39bebabdeb696a9aa2f89cc58a3fa0f359169efcff763ab0bd4ab2a3e6b8fd54	\\xb93ef32861b599f5a9468947bac9676b593eb6e391c88f75e6eaf7008f59b4eb877f6d62036c2b3d2e49edbf7be46fb2ebb37a55fe9fc2d84b6198c5688c70b6	\\x08ec43256158d88105237aaf8222e9534eab2426b34533ada44bcfa83e243320dc3ba2b53686b391047867800d88436a50ea3ca47fb2a3d3c8161639ebd609b8244804ce3ddf1af6493a48aa997e627c61927d3a1d332e9600f7a9c1794075f3ec3e6f6c1b1830aa24182e5bef7a61d0a31c866b4a3748ca7674943cb2b30d32	32
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	8	\\x22384e0c14cd4f264fa4752db691e61c7a287ea82acfccd9f6c2059a78205c666cdb04562aaf328e1ebc11e55a6eee04a8ed5aebcaba368c1d7db26065f24506	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x9fefb1694c15873e3d479af13669c8e1064b59aacbeb4815e0adade7c1b12ac3b82425fe630fc48fd2de9d66628a1619b672f12621f0e8945f9f34539fc985062fcb50eef793d47f7758be2f37e4964e710529020a48c340dd07f4e2aabdd12c055fc247f0dff245de5be56072e1f2458d3304897496ec7e26bb9f41364c88ff	\\xdb6bce2b3966a0ff2290626b8281d8fbf30c142bfb5976fdf9014ffcaf38b7daf1090f40d02475dc35069c648d6703ee595a1daa147e3ef3c55f8ee25f2d59e4	\\xb3b00edf2eb8a0a38a5e5c802829c027575ee115cae97332875ecd91b15c1dd2cd56cf6f9742b3634f7ddd4cfc0a5b9dfce89749ec25e3a1094c95ecf127f6e73f52a5c362213fe462ec46cafae62532ae8c5d2c7c62c5832bbe0221d1631b7c64749392660b6a455c953c10f451b78b9110dd7ec8a8849a36b4485a5dd7882c	33
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	9	\\xa1af59feb92707db60221bfccaae8f22dc1077fd3162eff53ffe51f0a31556079a54fbe8eb137fd301a33015b5b106b5da382144cdc8edabb94d5af89baa0e09	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x6f8cc5de53910a8130810522b3a4cce7e422627d261a3b98b8442145a2feddeb51f87b161412b2868a670a294219f753fface46f60d4b3140dd342ff2293d13201097c41b6373cfee3b7dae38817127b1e54c98edceb0fa63b052fce89aff1562590612f7422df8ce3aa190c061bd452e37c9821a55b90f5cef3968ba142dbf2	\\x695289a7c06af567e12eb19ca929b1fc9d2f0c619a5bbb6ac5c597d88e4c4f8ac053c2b6656cd76ee2a559a207141ab51eed5d9ac16d6967eff1474a1dd24c23	\\x637589b70da9780104df48e2f2da5405feac46e11f321f6d956f82949b10321a101e87f1b14bb4995d8de1a5dc29aa3a9d8f4e1a9052bbc5e81983e24d7827e6bd958926d9f40c1a4bd70482addfa53fbaa89ded123c00a62e6fbff97d88ce21fa00b2eeb80687b12f6a0dc9ea6b8a11331fc6364718cc846692e4078833016d	34
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	10	\\x28a6233ae7b995f1624fb1c063d4ed06186a5815ba7fb27c69cdb9fec9e4d7ce7c5187a20de0ea5b23e0502114e04848a5c25a440f88fd084aead8df4962ea06	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x10b992ed6f11007a30ea3cd62b7dc4c763818f76a3bfb7f5a477f782eee6c8d7dce48368301949d5f817ed7d1e4e24f3732674126c8ca7948e8e6c13719528269d84ee17d913ba8b9de31ad4b11cd7508c33d463a1b5abce76060eb4b9f3fb94ce905d9012921468e98d5c552aa78dafc991c7b169525df0c685a7d6976557e6	\\x29059aa94e34bf1ad492de0f853c5240ba7ff8db70508cfe9903bd137595f5affdf88e0693dc81c0e861e9b031814322b2042ea0e3eb042b1fb9751a2f5d0bce	\\x04849fa1d4d3c037546c06accf3c8e184fbd2a953c3515bc4b01568d5ba3c9ba86ade4532b4755e6dcd657f96cd4807823467972e6a33299cb15c88ffb37b842d76c11111b3dc5fa6390a7cd6a009131934473381cb1bc921babb521ff1ecc98092ad6c3753f7d10d70815a4bc885301db4dcb7924990681057ed94e7902c118	35
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	11	\\x90fd66775520cc76d44385c84adea86ea9b8a31a56c08e387ed84d3936b9f139e040dbb326b211e93eca3e05a12174bfe35efa8b190331a324f95d3b41a83a0b	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x7c5fc806cb3d19e9e00ff35b96c64b05196f2f1c3b1d57716a9219dd8eaf4fbe7192d3600ce02783c02e20f5d73f620894deecf0a44b2b251d1029a17e9da06036b3581ddbb0c90200ef59898caa38d135574a0b7db7bf7865dc9e12049a1f86818a3c1ee391dd245fd364de86fdc2d88dfd93279753dcd3ec4c02ca266a492b	\\x771fed5ab0d482f4017c3816997d7d6e365ff35ee1ac4a053fcf483f4c1d3b31c3a1d769beef120b8270b81fdfe2f7672e5f2813a0503a079eaad81e3882a6b3	\\x8c7670b963dadfdfe3edc737d702c4225c811d38a6aedb9ab96cb4428e749f02279f2ae123a1d34200b938c2c1f7a94c0d777b55cab5a72c62c2f0d1d3afee8248e56225bae810ec7cb133202adb65a35c597c98cd67f85630add69f6242e03dcb372aa677b2a6410fcd38033e8cca13b46851def882bacbc068181409ac3a9c	36
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	0	\\xddb195cc1eaa022429a1490ca8176b7b0bddd0ebf9afad21b75343ef114f38b68331a7af37b1dddaa54e44f4472cb80973d00dfe05e0567cf37cbb2b68051b0f	\\xe18c74430b1fc8a250423ee654ee96f465dbd9dac15678e05cfaf6f58f329915a5f4e0d0787cc5af29f253ceda3235a68ddfa19e01a3eb06ccc0f1786ac81a9b	\\x58072f8fa3b7e63d69e385072c275d899b8885c5473093b342865fd4f814ced84724df095f00542403475c2454fd42d4a9c8092b4f6d9429f6fb7c38554b85f3e056dc390e55e079861eb60e8ac14a6a367dcad5da71b429cb4caaf0370c2f07f2f63777037bfad4ee06be817ba9b29f1ca16090fa7ad7e9876b2a0fbee793b1	\\xe5cf9700763a0fbb24966f6798a60c7cc3fa53217a469c3a65a178e8fb6f41148a1f1d7169ec899551e7591f062a810f2c70aba00369744459100ce62bec358d	\\x2a147562b9e7eba61147101271e54709cac599f82418b2fd91bf2a33429d0379f4a24e0beabf1e42a23ac1b6ee7d31ce03f6b40e6a7e240e1c674057d3e862af545a69d8da568b016dc4b631b189a4b8c737682a00054afe607a9d4c7a6e7b8b7dedda507afa36f3f7d7b8fc6a823a032e75f135d5af89a9100b2de4478664fc	37
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	1	\\x3943a5c2e729476de8928e87eac0070cbef18766ab443d02d63789510d5118f89cb3d19c7c896e932d3319633173979d1e80b050f027730eb9322ceebb4da507	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x2eacf6bf9c70f0bbc3a9c48f71385e904da2834101ff327c46ed2cf4f2a8ec9ad82bb378784494c5e0a5b2562a5101c920d66df4611597515ea81965f4eaf6f2cb3cc88e58965b9032397161946063b9738df49102ef98c32911fc2ad539db360446d4207cd34e274dfff3c65bb2241b588f6eb9c0d0177a4755b55339ea53bb	\\x54abc87026250a24895579acb98a8011066792aa673926fd47ba295edd49b2ed31c116af2c7bd02289822be3aa36f5de0fdaa91b24ad68ee7f6525b71a992aa4	\\x276428f8ad11f43f16c34a6d7723fcf75cf261306205cda87cd6d71a9b8805ac6ce6e3510ed0add7c636d06c2549d4fb2d2874b6e8a962d32dd0619e0c77438f38025941bb55a35b6e9b5a8af8b8a743c529dca74d0b845b62a60230ee51903b7bc37e51c22b81de90ffc453a6834fd252c5b11674e51e626daebfbfdd235ed3	38
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	2	\\xbd017e9445229bf33e932b0e48e6f702071def224f3a2b99e74073eef7311ae63eb4313775696d22dc43c1f9eece02b7f72f56d703f29392bce5063699c55c04	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x73f29d212df74596d0ba1831f0c69a3b11f95a1a3646f358e0a13090948b5decace442c7f2f248ca89f2ba8c6e3be32b7bc3b7b4a7ed9326ba4e02ba7088905b175f45606fa6924a3d6b68177533f762db1320eec26bbadb13ee2c681bbc26ee45e54202c11a26234f6d1019fd159876968001c30d3855c7e4d5d5a858ebb90b	\\x1b55ab287b6ccd424b83e82081bc0be3ef3a0337361214b287307ded4cf8ee9c6ec993648da63fb022069e416d34591ce4f317b0c7d2fcc258961264828f8003	\\x3665ad2c285ba45c7c212f55909fb98e6c82dfdd5caf74f5b5269d7b484dec9376fb5e783150a5ac2bc1f4ee842622b6141b8100248c509bf41c9466f5214097a149f4f4e035a51067e7968a90f4cf7b2e5f548b0a3323c0b485e6ad6578cf2e52ec98e6b180d4259eb1f6b853b150b5cd58011a5890fb1ede61dd67fa242824	39
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	3	\\x3540e84a0ac4f85b5319b7337688ba0afda10598fec43bcdce3e3956370595c8595090963addc73ca0e601c2f8d8e996702a4ce9605a57752350ab0807f5ed04	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\xaec9997adc803783530f7a06ec6db627a2e3d8056e9f04e51f5d3f5222fafb14ca4e3965c2405f9a16edcec0e472b876769acf728733e96fe20fc6120ee3b4a134447e6cf6ae59f44e84dfb6e6a8bed6d2e30c09c619f0c76a356fe7d3a93bbb73503c108464ee8144842a825b8779ea5b48aa9bac5b651c54789a8371717152	\\x94eecc0e5fe4ced6f5943c8f64b72a7aac616c600e49505fdf976cc4a6129ec32f9c2b6bd1462ae64cbaebb9017fae791f614e5ec42925c9a2abfa6ef3ccb338	\\x941471c9fb16b36f957b5dd4c07a7595f03b4b9708f70144b8c65b3b85adb5f6c445713f411d50196802eac848c95eaec2da16e0145c90717a95ab4b93bb17d37fd42e6f025425dd800eda585707ba4866ac543723ef2f528af6bcc7457c2363d008e240612d1985a1eae8eab30c24b59c3c9039b5c5b61920d12c9930506d8a	40
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	4	\\x8c943434b52d4c317056643c715ac3bac26894f2508a741d9b5f70310ef3d37103bfddbb62e1fd230ba45badaac449b6c8aac549c6b8b0352d99837bb20d730d	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\xb235652a126cd5812b5c80d5376da99a473504ae518287a8a33c84fec23794bf173a49bcb4af22f8907d3c2e4b0545fa95230de72eb09b33d354ca23824943b511c7dc5834d882195aecc36d58c29bfb8d83e0ea21d2eafdef7bcd3810cef4251ba4d15bc54d325ee64a8ce8754db1883df5c27b6ca97dec5db5abad6024cd78	\\xc9f358ae4e92309eab4bfc77884e97ef9b1f8a6de4e1f3317d7716b4447a9d6c2e56217a57eeff1df5f9eaec39f95458fcbb77219fd7741641055a2b1bdca95f	\\x8785de88484c3e5f8ce1e344831ed72a6347d6b0276768b940bdabb7864f3b1b64b59aff1f62c2f5c2b9d24f46f6e4aeca3fac29d94e090d74891537e9098e9a469ef107261e451aa3395c68e20228a0372b9461b5de6f59348469a24fa33ada5aec318bd9ab9b3f7096594d170481c31ae9fa938c1ba34ef490fde9e344d40a	41
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	5	\\x83faad022d68523d458298218271b5a1480c3070daadd044f46826bee258debb4061a191167320d0adfbb7566f6ae3b6e72429f6e6fa3685bca236af3a45e509	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x7e3cc324072973feeabd3bcefb1be73d3d20aa7163f2cb052fa807ef4f57d3e46cea6ed93e82dc9e38b43da5a1d8c9ebd627fd22ce7c063fb52df73d711ae23fb755161c9b7472e55f2b2b7c3eba97c1127a03c89bc11bdbf5c402d4ce4aa5d36fa405600cbcb95ad6d910ecdde34dce996b68ef8c862051bc17a86338636bf4	\\xad4ba1fd41d77c7c14b3c0236e26a5b2a3169091b30d6707a55e9524f27e99ae4715fd63df069c6cfdb776e013771906ac0a028c49c133fea3ade975250c1283	\\x955247001be267cce0263101f6b4f27481282d884f4291bf3192eedefeb6dc7a51e57ca4db041d163250ddb9028d8a39ab621d56e60e0d0927d29abe67d1609a1db668decb5b387b6b528df2f54b57c8b7257186fecd6934c8e2602424e0e38ad2a82f21e96f5c69cbe0c3906711903f6af7c60488cc6daf824ff88af4032354	42
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	6	\\x4b917eb3e6e2fdde67a9ccfde02a4e38e3dd036c38f098f366a584e449ce803ea77658964d76cee33ab362b7ac8c9a34c8f1bb37b2775828e3d60776850f4f00	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x98575bd335b9a72687985dcd75a2b899edaa17f9c818b4ed092fde62ddd020994c00fed0970090b8057ff52f8e8f70d8397cc855c0e1e30bba58c7826a010fb324407bfa55112b4697304bb8ebe80cd3cf46a251526c4c346633ce193c22eb361ab321d7dff6edebb00ea38e4cf8bdd0d4390db2c69540fbd772990b5dc32964	\\x9f3eb974562c26d45dfdd876f95fa63c4cf7b6c02dcf8a19ede94485e6e8a8a5ebe2e777cc7c655f2c6c02b966919b772f6e6b6a09df8cf46ea4c369af256780	\\x3f629810eabd9d2a57adb09f6fe822e88c8f1944991f5fb7090c48223ab76d7b69ba74707d326e80eba69d36cb8e2d2a40d20a47f2d1e97f22087603e4db76fee28717d915218912a5f62fc2feb50fa75258566399337bb65e89f39a0d420667c51bb2c825bc3fd5bd90bfe4882dd614554445eca54f759bf92ef5712455cb4b	43
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	7	\\x21e9faaccd29993a5d9a25f0db7b90b9449be74d4c997422fce34085a10740288b3d552edd8c8ac5ad5f844f33490bb7f928165543261dace27048afea88e408	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x89f16b2d3f63868eb3ec85f62bb1879d8e4baf12ba07e9bdd0499316ab83cb21a125b65f9a9d5c00fc61839d87eaf7f242ad89692299e6a6155a7b9ed5f841c18bbe3d701c42770dba9297cac3bec4179dc94a231cbb56256e44d91c5c07995736a5d6e679e4dac61e0eb2392506cbfbc64b0692ef39490acd4fdc42de179b65	\\xc526c364ed05ba12cc130d3f5d375a626521665ec6cd63d3b29a86dc062adcaf1b3660912e126efeafd70182a16218c4a08b9928a2ddd0f01f3496e00f9e95cb	\\x755a4f03cb490ba6489a937f5d9aaaf30e70b2f668dff9bcc58288a34b37a6423ee5941e226cf33dc8738bed55048436467654ccc07f0259aaa505ca5a7bbd0c1bbde7650735311d4bd134df951bf49a8abc4f62c60c46e75cbe45588ae56b547962c42dfd96ec7e27b3c675b2789b2226f225caf3968a0ab685c00e793d3a32	44
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	8	\\x8a7ce4626b1ae7c1b69158c947cf1a93a2a5c344b12ed01e93ec61ad37e69b6beb69d8e2f9ccc3733a2a4edc71e519e600144c45670e4c32cca15d2d1bfe5501	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x01652d2192bb053374922464079996fba3da00aa9db076f7e055e1f8f308aeaf3db545b4ebc17b547f1f60516b565b8f53d0f6a699dff8ca83591872b114e88bde9e27188aa316039b69b2f5c7ebeb513b22d677dd7145e594116656408b325ca96e876565bad9ba119a14158509a31d47aca1a76d3c6793ad998464914231fd	\\x7ec9a35047ae4156aacdcc3bd04a49f7912bca6c0b1d9d702d7de1ac77a87d3e16d2173c0e75ae1caf531e510cd0869ebcf53d10bcb39427ec9af3adf59f406a	\\x38b998a06bed31c2c8908f691638814ccb3c79776cb39e2272b1362e1d3683d1e80dab303ee2b5753874d7fbed71cd9e6dbc0c871392ea116cff5c5ceafdc70ffabe792400d6d856724ce739fd56578ad95d3590496d5c0c5d90b492285f1afa60787eeb018789666cc606963caa31593260912e95ac139de421f521444989ed	45
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	9	\\xadec4c3f2c33c87880d4260b4d9563b4a2698a656c1f98e0cdbcf763939d95efc4d621cd18c9002c25cf44c6f98d9f561e7f58f3a131ac2683b795cc92dcd403	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x5fbfa0e2a924c4c8b6345dfb80e0144d230e4dbae8bf8f1e7fd1001d2de3984606a2972e742b2c30b3e080c429b4bc2a96ebe8c62326a974cd5fef637cb59e57cae3bead60f919b78466f585592ce59cb4b927de75145c9a245e5904ffd7fa1e981edc9475e7e728583061186cfcf12347fdbb1e1d1b0c9da5bcf1fd3bfd0590	\\x1fe5563170d8574f6a71031c80b3d0cf8fc4c1148fd8627c61828c9f3c6c6da8df5d5eec4ad5f19cbef3427ebb9d275242cbf906d4dd5d9d38c5f3b95130a7be	\\x6ed4e6878297941e9aa66b6a40054cd46f528c833395014323285ed2cdb2c6cdb117de636fab238dadc232fd1d3060aed1d1685cfac2c77e9036916a4e7bf78305b60f105d4bc7c56c7b5ab20c08407ac210051d9adca27fd368e36054ada96794d53e0fe1f6aa40cf5b8f4cd5941f28c9ae81d3ef9c886d0ae313517d3a8fbb	46
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	10	\\x26b661f53987bba9ca7cd0898c6a806b4f4be940207cf8b953009ab9cbd21a52f53377b9d440b5fca12575b7e940a0d7568cbca560733bdfcd088f4699d24808	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x5017d3220f41e40ef192e96a8e806bb167c4fa297f36e30eb44ec44c0ebc9fc864637a8d440868cbb0cc1dcaf7b558e645d5a0b118a70f11eb147094dceeae57ee34dd05ce10c45047607fc12ba3ab65bc79f57dc07619a74978e8050d3ef4c061f39c022997c0c2801eb20029523f22de01e4def02701b09c2e8203dfcf8e16	\\xebe8945b71c7f1b8cc3ce84b442c25de11640966ba9b9a5e02ebddcd18dedb92c598a57ecd009cfcf7d4d80e4b27791afd2aab4ad7e69be7525e72ad034fb9d7	\\x6f6cc5c856639b3997e294f15b228bfc1734284a6e2157fd49ebd8014d07fe977ff98e4eefe816472a8d3ce45903d0b2fd9b3ff87852825228481e85ac61fc8436912baf4be2475c974f71a352c3be35b0b185a151590803314e0afec9093f1dd57eeb6f1b32af8f7aecd90ff695e7e5e8486d7e2909c1dbc1ec95881dbc4744	47
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	11	\\x08aaffd9004fef8dc47bee4bb31e65992293a06c3660f5124e4e3ccb3299db52ee0d9febb497f5ed9dd0966ba9367757a1eecfec4d7f67d6ae7b4978f8fc5908	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x61117d87758f0ce8b292f47176a12ea8e3ca02e5054338d47dca208d4d0eda8a227b4f508b22368ac3bba7b961e197090b0f37bee52c05a7a8cb0b05afb835a771e0e61ceeb16a205264616375628f9ca03f09acc127cd485b9a9ef79e8be0102b128a7e381f0f7186b28626b4c0ba8fbe4cbbc46a82c65413b9d8c749c96c35	\\xf08969939e7daaaa423096ff1306db1e67dc88331a6043abf2dd962166cc06a13a90f5ad03e4909bd75b3dc1532352a685dabe0057e9873da2adc0f5a4ab3956	\\x15582bf44612a45bce00f4d0cabf9dfd21814960dede8568719f9915f6c705d1546ba643731ab45e0123e8b9f2bb9ff13fd75d49c0df601c1cd9e78f6581227af86599432ad065a0d24020a955aaa5ab59772b1da332a51c844490044792628da4ab86b6733afc45bba976159bfad202f866b418cbc116d0daaee5c46149a61e	48
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\x08a0f3148beb10c025bb2949d090e30278bc2ec954dfd06a3e440709a0ce2c003c67564fe12bf9654d2569cfe8ab24f4d64bd1c364bec54b931bf8ab09507e2e	\\xc6bac1451172703bea06a473dc6151a6cfbdd4d28a25ece0960ffcede0471677	\\x98ff522b677a46415a4855decb3136c1445a926f9a3359c0495216d3223dbd1b0ee9e896f370b97f26ace4904ca06e5575f6dc34c2e3723c948d15a0f4325237	1
\\xdb795d8ad6bbc2b43142e7b793c0c58232e105885ed1298b6f692aff095b9e834c4ba8d9a89e12a545fe797a47e51a66fca726c2cc8f5e9c14db585918d23ba3	\\x0d7de3c25f7a73adbca44000a3a2ead3b87d46c04768b4acf1a5c6aa7f990e03	\\x7cde8873ae2dc3bd52d9ff12b917346885e8b6781fe2002eed68033a18c071ae6a744c138b2f163b6e6b18e76c252f93627811cd047d86591f6082df14a23627	2
\\xa798ec47b3260f736934846c2e424f7b1ab059d38159f2f25446464e969e4baffeac5061be2617cbc83d3fd9b3034171002dc23810816279564e87b20b0b75cc	\\xd5d68de664c97e3f2653fdbd52b29c792a960c980426a6e2bdaedf3c2667802f	\\xa022ce0a95700d89b7358a871a474ebf2f73f0343c7fd2c03cd9e2b58e2304a5f93267da35b9115311caea48c62597ffccd31b2d96107e523a3c4aab6890782e	3
\\x1930c9da8184d62e5fb925177610378b6ce50a385c20fdcf94b8f6eaeb2435dadd62311aa72b9ec1d1293757f083f5e41323a5583bc24c10c223219a8c8e9b81	\\x1ba3ba3ef22831291c7f933fcb1a1c7ea1b3ec297d40ed3dd4708713a3f88616	\\xc6de6bcc793e77f13b79d65b83a3f1dec396c006df995a67ac61eb4067c2c824fa69d3cd3ac52d66c6f1c057e7dfebe33dff19b7f85d47ea91a2ad5a2fd4bf77	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xe14e22d3f4e8f5d08037acf0c43078d3a3a79e1116079869ae33f07456816aa3	\\x64ba73489eaec4d4e9e2a1ccda09377430a5e8b0524216962a4e87436637676f	\\xe5c3c2b30b425de235fa3bd75d2db90760882c09e226ee0ee0019afc36272c68d937f5ce1f6d61313e2c63b444387161bb01dc811a03ee57f2300588282aa10a	\\xbbb9e252a37203c9ab994a1265753df3b3da8f1ba324c7fc5608fbd6a30946964391ca1a217b443f36f80d3db39d0bf5c24839abbd17b65212f7cd5bd10de0a5	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x326005eeb7a355e77acda94ff1bb65ca9cb739c320c2e30eaddba1d38c202a11	payto://x-taler-bank/localhost/testuser-wezXieMc	0	1000000	1612475309000000	1830808111000000	1
\\x0553365d773ae178ca3c8b59a2bf2a34a52f290403b86a50ccd2a4b347eedf1f	payto://x-taler-bank/localhost/testuser-pHPzovd1	0	1000000	1612475313000000	1830808118000000	2
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
1	2	10	0	payto://x-taler-bank/localhost/testuser-wezXieMc	exchange-account-1	1610056109000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-pHPzovd1	exchange-account-1	1610056113000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid) FROM stdin;
1	\\x4dada3bfc4de9debab2d3995e8ec3461e983167b144d9b449887aae10b591ae4afdd54a7ad6f56cee843590e8d31d575373c93da53c1d1e557e0e9135a8a8ee3	\\x86aa991d57b7c95890cfce7385e960a9f80ac70a4c3b7e2bc4227f5ce751e36ccbaf63b00f0d66a5881a0a9c8748b944538e49e2f91f4ce5adf5ba513ecce618	\\x5929460226751706b999660200c895a806cf2b64464fe555f76cd0c5ff72a0da4dfe06f593f80844dc1bd423584c27b567eda5f71c7474e45f143703f1867dac162011f78d33a20d2ff9576218d47f5de1a6a244c4653694b6c285f08fb741dcb6e026535b3ecf5cba99a623f6da295ee086eff6b07897dae3a497264b553c41	\\x933d2dcecce5e434dd86b15b876148ea93845b505720087ebc45ebae70fa66f14607767a657c24b050ef69a5bc15b11444946b4d25406fd3f054df7dbcdb1802	1610056110000000	8	5000000	1
2	\\xb69f8f40c8f684487dfb7169758db187191db76e0e2af61d7ea57ca3b107a0dd9af82703498e8e52036d76c0d46752628d55f357c2ed4ad31c373b4919e7749a	\\xe18c74430b1fc8a250423ee654ee96f465dbd9dac15678e05cfaf6f58f329915a5f4e0d0787cc5af29f253ceda3235a68ddfa19e01a3eb06ccc0f1786ac81a9b	\\xb667c134e76f7dd8bc45500277ea2595052f247ebad433b574dfc6843351e6d7cfcafdf14332326169a9822357bdd8a1245fba91ed0869f55f62e856ac683fbd5bc5777536b0a711cde72c385add8014d7b1ddb0adcb67337678c2f7f1d40c3747e7c72b26fd7915a07745991ee1620398d08c41c4d08a13496b9db54ac568e0	\\x216d60450e6d85cb3355cb75ac54c489ed95dbce70aa1cd434e9ce603f7ceae128dffc71ef6fccd5f5e98c519e5109fbba74c1a28bdc6c0e60fc4f0b9bf02904	1610056110000000	1	2000000	1
3	\\xd24b12c7c71bae231a4ebc6bdaeb96c2e7be3d7e8fba632b585cbea1cc1ddfad5c1199c0e0f93493443084a4ca6a2a96645cc7e9b97b520cf0a24f60485460b0	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x910f99e872c968ca86b88d8237c68eca7e6fe3603b031f7ababc90a38752d8bd84ee077a4f4b96367784dff57e2ae9f88580089b88d877c2177cae215b7de7fddb66cbbcf74f7844a20bf33fc104907f31e35eb1c325326263c262871fc2346b7d4968f36504f7cf66a73f6111f8ac7fd105496e29cce29a72be8504876cec1c	\\xe3c670b8ec8d7ff584e169dd8ee921c0e9f7d3b0befeb6c034449b57521f4627e40e4be18b8b5432bc6cb745b9df4aa1388348e706b5e50c8f74e817f226f40d	1610056110000000	0	11000000	1
4	\\x2e46a4d0e70ddb3a9a585b89254c448ee3deee293cda6fd9c9df0f5515e656ebf2b5153e082363747dd29de4538be65a819b30ed0c4c7c3b5ea0e74fcd7049f2	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x18663b50fd89e4b4ae92b1355e8e08fe8ceac09e03133c0c22ff9e838be576a338423a07faafb6b589039a3c5694a3a6eb918a493510c8f402244e193e0e70e0719e07516bc1fcd04637774edaa0466484078478c03f7da7cfb580609930a8aca7a216f7883e1e74da314989374e8d78a65fae5573e5b96ef509eb462a939859	\\x41245d35f97c442fee26ed42455527639e19dd6b047727113375f7f13a5c3e2b2af04acaea93f83f3f8faaf6fb0b95dee11dcf53ee3b8a544d0509744b7e3d0e	1610056110000000	0	11000000	1
5	\\x15bcee9024361ff22146b5a9c4428de27ef8a703c4ffbc6e8f20bdb7587782bbe57ecfc65e92fa8f885ed49d5db6f79f1410a204a70668d46fb6953f65cd1df4	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x3fad478ba867c13e9f0642a3dc8f0c7b05db62f1b0ca59d8a3745236a8d7bf03c163b4c9f00daa9f1b5638040219efe347b06f4af00422dcd0348112e551af391815d3428c13f24e14b3c4a69b8b876d5f83e14d858cd6486ca7d9e913d0a335b755a9b87913319e690a83efa85080f6efde5ace72cba1e07a816b2a9b88331f	\\xe88bdff3f1f26950c311b6100c50223d4f6212e5aa36e65f47d2aac9921033d039572e53c88d53647917d37a36276a6f39ff2eba0452e0b7cb5ca8002c3b400f	1610056111000000	0	11000000	1
6	\\x9b9890d29c7605a0326544ecfca1bc7a7689c5145ccf5bdb9ca734e809b84ec3d8a439b9eb227c2af93b580c8eeeb42e2539abf44c55e2a400c7542148358c5a	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\xb42c81e5894d8dce77af9e558b500a1125dcfa7de1402a9796a8354c6e40683a32ec869884d109dad63ade5c1028f11f1e89f11164caec5c634a07aa2af14c7d6380b3b184f2d504e986967fc846ecba7d90789eed26350712f1a16a2ab874c43df74e1cb39964df2fa962acbb355d88765783b7da860da9f70b31c1efe2eaed	\\x29be7a7d6320929772889f0cfd0b7cd6d6d585407cbd19bb1e6a3d61c55d0d0929b3816790116907faf68a2491a5aa264decf8badc4aeaa860835d0183ce6d04	1610056111000000	0	11000000	1
7	\\x64d46afb21e191a6c39473c58aca8c04b3e3ffe5e62ec66144a5f502e8f9a122978061b3cb1490e0de74fb31af7c4a23a5d5915e41eb71f242180ab172079447	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\xa01b3bd41cfcc418eeedeed9e5dffdbf67d896df59fbe2164ec72b5b80eb6a9dea98d1cb8273d4f412f73859d647fc32322a2d39b9d70256c1a7c8b78f63903319e706e47aa06e17440329381dac1d991f5a2cc3565a5454ef88fbdd8de52e4c85b7be26e8941af7952e5aca92b413904f821db148344257a8a2b0f7cfcd0e7c	\\xfc6575097dc9eba35fffd6c8141aaf21557ce26f3314cf880ca913858efe82c27c9b567aaf5afced3cce5777255a796ddc64fcd2d76711fa69000227a5fb4408	1610056111000000	0	11000000	1
8	\\x546e382a516f76ad15d674ae0325348e6bbe7f6a1c24f652d6d5c117e97216a16ca7f726fa3a727033f731523182f3d47f99a78f015abd3a0dafb53681e5bf14	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x4a891e4def16fbca020a872a83d3a8d10f21f1ad79fd44966f0a98692f79f91d3a278b6d30ffd142d4c13c36d99aeb21389e898b6a655aae2fa77bb3bf9ff08cca3a969ab3ef4269253f3b88437419eea7ed2298aff7ce2e0bd847a451440d464bfacb10f6073f565eb4bfdfca018f81a60fbd528b32f41eb66a0c8f9eb68410	\\x297f55f391ac894d9258ab48f95769901cc28244f055f4a20aa9d330c1e75e1c272f77245c2b8f3505bd29cf38b11b606ab34fc4a37568d29410cb4c67a4250a	1610056111000000	0	11000000	1
9	\\xf7337443309c35bd707f0a0481c16ebd077f76dd2a6720fab31d3c3c45603030ceae637602b6fd6f13f2f4d4189141ff3e561c6eefdab8e0d3c733a4a03b7482	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x51f0da1b86a28f22ca8cf8c22c653f0138aa7b6a98af5ab8a4adfbdd172e3c97b8f50294946fe8466caf21dfb16b1daf8912175db23230991a47fadcdcee386c4d24f89861d2c2af831bb663a48a7501a8d62ea3e0c05f753bc0f1cc05a784216cd7984e1930c0af1c082b37b13438da9a7a6747c14987e8d9a81c868fa7bce5	\\x8c875cc9f1563d79db9004fa6cc01cf0f8245ba4ed1a187b1abddaf2ec3bd737ce515f173d74dc5912bb765f7bcce852cc2aff0fdcd80e98f8afc0523dd46401	1610056111000000	0	11000000	1
10	\\x5066fccdf7319988eeae11a043abd247abd38451a7a8391206e909b3b18ef16c3b8335ad85f41f8204fa83035718be4d0c82d683587410b611cc1324667225e1	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x5d36f5ed5ff7add5b4b80f738441a71e6ad31f71483d02062c871520ef0b076e61dd7d42006e23cae26d2338d8cde43cd7c4c15b0afb08118dbf79db5cdeb4725601a0d4f597bfc5a3bf8e2b19f27ddde128acf248c4677a76770d97764450660f981d889776c8737d189785f8e2533bb4b43989dca438f9a6a9715a3349d17e	\\xf6c6bd37d59f730659211efc51a20a41d8284c151cbc7c97679bce6be52c79e339afc8a084bd041cb77abb79422e1bcba2391412b208772ec3e829d717e7050e	1610056111000000	0	11000000	1
11	\\xe5732e0b8f06a691827da7d7b3372df192e44638c391eff1d868c32eb32309bfe4e882a5aa4e6c92236058161adebc65827b9c91e0fc799a667ccb295ca9d0b3	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x9e017e0cd38d6e382ce433367efd6f182906687336fced6e916c83c7751a7ef4eb6b542e6086e224af0b8c0c001a7937e0dfb0137599740a84664f309359593d78472e0b8489066489dce1a4b3fb2a8eb85295d216c05b8cd267424fbfe3fa6d61fea75ccdf2d43fbc6e53f58ec3182e22987f9c1893131122a9fc8ceafffcff	\\xcefb07e2a9332249f7198c9fb33201c122dd1a4e756d38c4cac9df6132a06af36675fb06ece5749afe266125f62837c8cd949f4e5747be272919760ac0e18f0b	1610056111000000	0	2000000	1
12	\\x88960d4d660792bbf7ddf6cd4fa70ef7424147869e85501e9c25c756c1790ccaf3de6972e049c0f8723a7ddab8d3f95b5f5496ae4c2a41d29d1e9fc1dedbc775	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x4ab8008e6898dfe853b6e8ebca7231f992c2613960f6d6bc93adda26621282b1a0d9319926b4b4cc85b83113dc050ac4a2d8fb25d7af408d9717ff55f07a37faf439c80865d9a6c93e1efda1ac8c5da21f990161245e8a0fdbebc37ee05962319efa5553c2cc3645817061f841658c8cb54e512ccfb7d1ecd6db3e27c4f96bb8	\\xd3ae799a14bcc3295e199fa27ad7e8442d51b70e20f047bb2110d9d18bccc67f16f01b27eb796f4232438b4daec07b5c6cbb1fdec433ecbca394d282fed35106	1610056111000000	0	2000000	1
13	\\x122f7bf580cb57f58aa179c7a7c6618d076785a67048cb5a00e454f0f4873aa021a99c09bd2ffa4b7a8ea188314d6b7f370bb93e27c37197516da25565c38b0d	\\x8a4873b97c3a64d132cf490ea0541aa2719320e690cad74522b65a0e43f0cc5893b983b0c56290c447ffedcd6742a00224964b1ea505d2a54fa9379151dd884e	\\x0a52618396d5a94487b399ee858d4e4d521548c356eabb3fadf71ad82022f01f7199348bdccecf28e6280b867c755ca64c5fee6d8d874384bf81a9510243afbb026461258187b3c3c34b4cfb3f1365ec6ed4c4f808820b9fa03d45074dd208bab4e24b92a71a4c5b9915694ea6e6d434f5e9c05dae2aa8239612eac159475116	\\x695197480c77bdc76cac1e77ef39caf0568aaf8c25a3a289c2ec3b22d40afeeeb39b881c4e90d660e6fa7f83ae1bcd707bbd998985848977e2ffb4c4a8cd1509	1610056118000000	10	1000000	2
14	\\xbd02daee89dc7a5f10374cd7a89dc536d631a7adaa54a9f4fef6c3f81f00cc37308fdba85cafed72c2cda57fc56303c23c9286bd3aa891ece5698af3a4c8a4a0	\\x4f74dbdd8370937e54a0feb69a91a28151b1b05d94a81b4008f625d71b34d63f8c9a5f907332c8381e69d504f2ecedfd83b8ec505d130ce95c90a943ee819dc5	\\x0803f936e62d2fb74eb2dddc4cc7d739ee59bbc427a3aac0d68a7c52f91b59f9c0ddbe04026b0f77c1855b272213466d4a815bbab70c8faab5bc50fdf6811676f78f6efcec88539f5d7fdbad22693db94d61a0d1ec5bb4e9687cb15e0bd4edd5957e57ae63b647a41c692a7980c6b6dd0f68ec311b0ea664b8ee2299226b2185	\\x2ee4ecb9f49c0372d08bd9caca7f8077dc397da17a94b5375e028fa9a7f91b1cd2b7e53b31f14e12d05f46487312a6a1f5f1b2145402496000ac6f741acc0a0c	1610056118000000	5	1000000	2
15	\\xb7c8476477cae4f3041114a983f7341f87624db351706693858cfb51be001a6977f35217ea58332c1f0a08262a58f6fda9bc4839f2aed765800f03b3de29182c	\\x62aa17d2762f1d4c0329a0fb06dd68676d4efe8f0acaae008814259d16e64cb40138fe03d8f34ad58564af86c589acdfc7ed777dacf15e84b2f332aa19218a23	\\x3fd450b9ef7937782da0fc5a9c3b24e6a75e69f667617aa1fcdfa46e08b013c650ac7e352655f093bd5913a42b91a07d2942966c1e61a1be6a6e34e9513a12236d394d3ccf2cb84e58e9efada09020fc0314c5aac3cfa007de91c14b1094895c268ef13072451e761ff9cc4b4954c948fab81a1ad3b5c1c8154dd132f09fef28	\\x57ce8730898b8591c58230c6897418e4dd7a2fbb3fdec99e77273f9e288e3febb3163d019227da87e45dd09900fe9a1c5f47fb0dba6e6b17c2b72299b67a7704	1610056118000000	2	3000000	2
16	\\x319664a83c4d81cd53fd7f11e41b5e30b5f5072368fce01fa8ac7b0c2aefc8b99a9ab1a207438b12ea434d77fd67ac931f9d3e5a29e51534a264594e27dcdcfa	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x88345969be88920f5e9815cdaaac012256a20ffbb54b0b84319fd38f9f179247a68f5088db4980e7cd3b1400bc271d633643dd17bd4a3b28f261881c7e4c43af0493aeac1801a2e59d8e85182440cfd258b234c1997b051e5eab1c305f0cf381885de115a79f27ec1a162a55f60e755e86d9f454c0dc17a57aac5f86e3f98a37	\\x4a4af73453bf51be1abdf2a3dbb6da990c5973f5850ae4bac9643c5a4dac5082545b21c11c204530b76db22880dff3b04a374f1d34e5ca56bba1377be0252604	1610056118000000	0	11000000	2
17	\\xb2cec7a669416c68653071277a7b8a44c74fa65adaa899be91111b354afea5cbe7eca1d2d4c82675572780548414c64ab19a29c230f2db46c32f0df588499081	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x3c3b82f416afd57c4d90d38880a51318fc96d367a7c40aa9ee94f8f6c71f7c63cc2bbce69d9d731e58b7af65f750ae553ff51f270c2c00c332372c0c1873431ee98e596c34dcbc555e26a890739f05dd238209f2cfe0564444d46693dda8f15a6fcbc79e23066593f0722b1744bc32defdc43d02ad807e8d37bd49ffba38bec2	\\x9231cf12978e40c807e55ca00a104f14ee33d2378e617c7da67b4285c5c390ec7c34d72e52846f30099c1126cc12bd81a628cdc94b7a2d0de732fa8fb090a80f	1610056118000000	0	11000000	2
18	\\xe1a3858eb480aa4d686c1a6bdf71a5f7a3bf3ff999043f9b5a77befc252f5a683730c64a097685c6cbec4c25b354209337352e00fd5e340df114fbbb92a8dd97	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x137e46be885c4305434546cc076fecc059934e305c4d5a761310a655ca1f6d6b9eb6f10d992666809617b9aebeb9de127ea65866382c247ca6ac3059813595a428ef2518fe3c37647b817d972ad24eb95a25fe36db6b2e2800a0106b026f2718aad1bcfc7f53120117c59e14613e42f1722aa4b2e64cbb252ef2e9b115ec03e7	\\x93d7a0df6b0541461b9ae068552f7594af1f40a449599414418fae502e403e5850ae6d591920f46b1c1a4889eb4def8a31fcf2fa4a265d9eabba1138247e1800	1610056118000000	0	11000000	2
19	\\xaab6705d9d5bf8406d13e9b97f6bd7372ba811396a85efa79abc368b7b470755679c165d169960ffb252a6e3811e150931927ebd6aa0416b684cbbfe301a790d	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x2c101234bfb1f14225b31cc3fdef78148ec5abd49da6d50f4ac013f040066188ee7f081aed9b0b104b205dd64d4cb8acfd970a64fa7795cfe57a6a22ce13eeaf8e238588129691b289e10694f7c08e96ec7996de562bd6b5ae1f1569bf9aa88d8e3ffccdddbab0a1c6343e8c69ce9c27543646a72b156c85645b1e2020a67161	\\xa1fe4277531b64edf8704db6a3ab0de2496d1266931993914239a33f2b8c96ade523e604bd7a025649ddbf5f4ef362a4ab86b9e7bad6d6ca1699628d49e66502	1610056118000000	0	11000000	2
20	\\xf4d745f0e670c499067b8be257aad8d0b7df95f56cd37b89cee37254ad70c12b9defabb33bf295e237ee4ecac9fa17d3add7806d6bbd7b29582c195f73bf0902	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\xa72fc9fa632e3bffbeb43adb97413c5c77a107a88a372b57af9f59203ebe0b243586104aa140207a9280fe5efcc150ef24c87183cfc4c8d0dae2a6d392ffde7ebb5bb7e66b3b0866ca00dbc774a200c94f447dd0d4551f04dc05887bc2f3f892e5599e02dd78f2d5e7fe6318db6ef98ec0838ce65f819ec4bbe28bfcf379f418	\\x74f62dfa4d141148fd3fbcd822ca4fc5208e3c76bdb5e15d2f06e50f6c9599a0c49e0028a738700db659437f36fb0af515c9372427d572eaa8caa321d186cc00	1610056118000000	0	11000000	2
21	\\x22f85e59fbd4a078b7dc5e9e2d463c02bdffe438d782c6c22b98ff8692c76d9126956b4709c01dd0093bb3952e456adb953b80c043a435b048dfe6df7ddc6fc0	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x306cfb50c3f5dcf96c58a4d05152f308c072f651ad61fe8f52e13e48e56c42a2ebdc2bbb5744d0d838cf644ad399e96908d89761cf6a6d0356954713bf22a626953748d7a68639835042f77f92a98cbb958f248971f3f20a19b14268f8e072f9ec78758c8a40afc20caedcde2354309d5842f3fc95332f5d51a4393fc5d755d7	\\xaf0bd6d353a862482bbf49c0fd22105cea9c27300070fcf28f8e2a4d322bc09e3df2c71fd38b35293cba903b0b6cac0291535e1099f59826c45c05bd31c97b08	1610056118000000	0	11000000	2
22	\\xfbc95d6cac16de41c1c0e13871d9df1aaca9af9de032c9b8eec09d4a1d146dbe9b7090dad709d18840d1167ec6dd12f070b8f29e8aabf0de2a5aa6147b065b20	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x58a04e23f8a5175cf73906f46424c3a835b973f43e2412c1e3a744eb16afcb592c9439e408cb3d1e9455b9de6c1389a1eeaf6d94897fba9cf91a890153722786a1c49fdb46a438345c97d7fa3a5faa4b60d74e503790c5354dd261900e0e74804a2a923328db6c43e50a96f3067abaea0a71788aca2b61e272a7de30b0f489a1	\\xeba6351788c040672ff7e713ba224934c1466d95b609eba9a83152efe7bd4e28ed0f83a1892ba6280c1635b48a0fb10e516c2094b0b419b64de18924f3f0f301	1610056118000000	0	11000000	2
23	\\xf77e195f94f15936c93fb98dcdb2e0fdc033ee040bd9b6b3957a965bd24d3a3aa8bbf8eebca6dd55046c023dcc3a21f5f9707d7cdb714363a24090bedf2d94b8	\\x8dccb874473605e28a0ab8e5928e790113e2cca0da32439e13ba4c5f29e342c0144a93e3f015d58dafd371f4b37d21ad0e739729c4d75287e0909a46fa1edbe8	\\x3960fcf3f77e54fcf94d0837512fca551c0f063b4cb7095af39e4940d0177ffacdc7b506c9a593163b488bef0eed7faded24703dfa0a14c0decb324b840cf30bcd032b873da4791dfb758e8f5687edd166cbe5d3309ddf5b9eb1c2d0cb949635074f845144f19f29fd9d322fe636dc4c00bb199b41d697e73e45ecdcd2321706	\\xe7429b067916cc76410870192768ead399f7fa19bf111f94fc6e438a491e0868b4bb79e887f917f7856ac1ef933a88ca18a809dc09ffa2aaec909304dede7403	1610056118000000	0	11000000	2
24	\\xb585a7bb86cc60487b9679b51610b1a16693ad4b26122434beabaad5ac2ec334d053c432f63cb52abc6e14c5681c6ea9ca7fb81102b0b2f11159680d7f54f937	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x7d201908684ad62cbb4ce139084d949878fbd9b90ecad225fbb228286318e73f22efe30b1ff12ec66b2c4b05ede1b414ad68fa5268440033dfe0d1434e66ee6444d7554feb66d7a10533926765a647892f7a71f5c53207a41c3e2c79afbe6ebef7da2c2f249f99384d5aadb4da68389f9c3790b2eb376363941c73016687d4f5	\\xdf30b15eddad47138740ce63cd478533bb589aa4e85a0c3da203c7df9c090459672bb79c72b7409703ed5502eb02158a8efccd103ef0e27ace506a4857d4c504	1610056118000000	0	2000000	2
25	\\x6bb00d5b7bf255942731433220c94e2e7a1d7146c7735b9df4b61d2257ddef98c8781cbe4c35fd9231654853985ac22d5b9e99aa1e7b29f4422aabd61b39b141	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x0da2803540598895de385145513803b8a012e22097a034c81b19ca4f6e4653a93f0909786585e719d020fcf2f4db3d9e118cd4d2fe1aa721124ede78144482de712ac7f9a740307ef3985b6827b453a73465593e5bdd740b9c97d6bb4e553bfb9ba7e6073e93f7f04d5870ccbc2f69b5be1a1c5e3d376fafc3d21758a2e97326	\\xe93971424a0a2023e0212d1603c3d6723bcd04cca36707a96e82cfe35caed11a669973593ca96f92ef1bf9b1e671a7aada71232a02239c22e650fa29c177b004	1610056118000000	0	2000000	2
26	\\x7f52fbe2f54f1e349952cc970a86f5fa7a7c82aa42369d3133f6698b8e63a8492e3a78d423aa3821b9fbb835ae2e7556f57aa8897287ecd614ae4096dbffcba9	\\x4a56e6145ba6c8278cdc522611dafd9a65a62a0adb0bbd82ce38aa3d0dac5ad0f808f7a7d0c4042bdfdbb4d55f084b4d980003ce52986e407fba01cc2408bc8d	\\x366cccd2f57cc90158a00cf035c22126df40a47c23cd0c02990b0af2244b29e3f3ed920b31881f267a3ee31e1c603bc1d4148ced972a93aea266ddc8f0ad3da1d7bc41093550444959213b894c708351733c96365c3107e60cfd55062f75f4ef81b3fab8306ca843b008d87860eb3137a2f69658089de55600e94b48b0b3dcf6	\\x8ba1aedf27fbf965e2fc4b24b42bd6ad1f8e161b58bde060b6b4dde0e5184bcaa0681b246a62bd5a565098b0e714dcf458bde886206df637b86a2f7a9efedf0c	1610056118000000	0	2000000	2
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
payto://x-taler-bank/localhost/Exchange	\\x197921c85728b38a68931fa22ddd35afefa15c5adc0cfd07dd217526e8b5f8d1235eeb084e4f7419692129c0164af4f473f97b21c0b5b78d9d391d636b3c5606	t	1610056094000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xf922fd3323da4616d7ceffc9defb66a43f574d25a789213ea42197e0202adb4092cf23e133ed50b3e8dcf8c639ca6296dcf8345f95e471e6b9d4fa57319db408	1
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
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


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

