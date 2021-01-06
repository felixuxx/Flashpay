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
exchange-0001	2021-01-06 11:35:02.516537+01	grothoff	{}	{}
exchange-0002	2021-01-06 11:35:02.628244+01	grothoff	{}	{}
merchant-0001	2021-01-06 11:35:02.800771+01	grothoff	{}	{}
auditor-0001	2021-01-06 11:35:02.941151+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-06 11:35:10.842018+01	f	fb069ac2-caf3-4b27-a2e5-f98285b6bdd5	11	1
2	TESTKUDOS:8	7BS455F359BF0BNPD9MBETGB62231JCMSH9774KC4ZMBQFVDA2KG	2021-01-06 11:35:26.10331+01	f	08c5336e-b17c-41fe-9905-84585eeaa1a2	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
f175fce9-5b53-409c-ab06-ca0d7497e22c	TESTKUDOS:8	t	t	f	7BS455F359BF0BNPD9MBETGB62231JCMSH9774KC4ZMBQFVDA2KG	2	11
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
1	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x76ad44ad39c94061b6669563450457c4cf521ddc0e20ce5aa133e707fecc894737d40f388e761f1ada509d7cb6ef13f308d332bb7487b907899a1e5ed9b0c0d6	\\xd789d518f9f77a599d172823f96c7fdc0875defc711ae41f5c1734e80cfed3fe2ab9f59518016177ef356d37616c128a561e900bf4942615975690a0b0f10a0f
2	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\xb14e70a573eb731a7fd0b5a3aefb582bf35ea2d2054e4e11810ab30972b8a82c68197cea93fda1f654262e8d63d0c62d806efe1bd2f9a39f76c8c1fb72ce2b0a
3	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x715bb6f58ec200a6b3726180021ed01592a608bb732e907f0806c055a517d49b945bbf13e9a6bcc592809a2502371b26e307f61380c7007b2475786971dd49a2	\\x69f2f7db23c8508f64fd8dac5f22177b08a91eba0c5af528c69f3da25444b12f0beeef126c6964e28d80341035c2d3195c9489156ddf7d0baba8e739cfa64d0a
4	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x14c93f12e50e1e0adb52fd4e7c11169425546d3bd7f84b5a471b398ae3a575cf4031b82877f241224843fe00fa74576d3499dbe11b2b94bc71bf342d51fd2695	\\xed7abd1fdffa5c16d9633bdec65da045256d31dc47cb7196fadaaa3767e9616df86348c3718ff88f652a09e768ed82d4b61bd25687ed3970d4d9b03f6a6dae0d
5	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x81b082d1428f02b549d1f359f33da8ee027d5914a78c36d77f1314b60afc10589f362c48fa57bc06e7e9872ffea4f6c153bddc319264540c8241f6ae28b93e9d	\\xb8422567df0d9935b68544bc02ab2dcb534bb730c819752d25bd0f519a43498baae90d3b0d14012dc059a7e6a45512446122379d88831c3352f56ca9bb793b0b
7	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc4e76ffc5797d6dc5b74118295c15072422bc4ce0b4c422a2098bf27f1b31d3731438cc33cf9ac1bbe53718a705a66865fc23e90b43189b39ac3772ca9a0060c	\\x41dbde0a6dcf4abe4274e2be7de7c5478c07a655bd712d20967ab86cc061ac254a6cf472c17d6cc12bf8f74ee80176592703399ee78b43d733b3dd64bbcebf09
6	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x96253af14484c2f2bbae0ee0cff58e5a7c60883efb46e6d956bdd2183475c808c99e2da73931c44f38026e8485d870dae9ab08de3bc733718b16a9cc1acc01b0	\\x5ebcfb46ac1f43374ca4609fd358af85927739f8906c16a458fd15e45e56dd7be7318f15c1ece6ab8bf9383dab4b703aac8d68043f93fe4da48884f764cbda01
8	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x17a3c1cd0d6e65f95c4e3bd27a4503387962f6c99d930972d655aa1ef9f0400d2bc36b314f449476ff9216225ee2634d518d5ea9168928ee1a2481531a6a55b9	\\x24396a42fadb43c60f0dccc53c68048fe2b3adfb0cb7fb82ac8610e9905e781ef60b7073b9ae22d541ccb70c40cafb9a4fe00b8de65519dcb5a252d509206204
9	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb8f1f54ff8512f3aaaf5d5242fdfcc2f0d3dd45ef11e6ca889d4fc78e9399f8e79e7369b9f49411a4359136da5c7d78d28341bb75df5dec029f5dc37300776b3	\\x6f95b2a10ade9f13853d43ff1740be870a6e35f465ba988534d75de5626a5bba7c8282be221a0140659ccfe7ed88b4e8a5d3b19bdbe7b9003d02ee305b3fc301
10	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x076fd16511ee7a17bbe1209a97da11c657c1df5ed42fc315da15474a495ae9e9f9351ab7defc1d07a7a5ff086cb680989f44b8e0af16d39eec60e263a45ed413	\\x73a04a3a44f1e676ff7143813edf7dcc91d9cb3c69f6b0c7ad346f8d4a081bd26a1e5fff68b6a804443edafb902c770dc3ef6b25faecd12c243db61bcb274d0c
11	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6248cee81b5ba5256327e8ddab9de5a335598e89579e725f72bb1a29354eff10f65f1e12e69c4946a2940aaf66e68c2bf9157c099e8aa290f08e91ea40b15e8c	\\xf5ba7e568493ac62335cad15f640058d5156f89394d7c3b74fba01c735669d8fef7cedc0cc8847bea599d2cf6a215f9a3ef05a63ca2b92e469ab08638dd6ce08
12	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4fb56778ab0dd3a6b48d034eb89d8d6a1aeabfebde587fb59c4cec7f50b0ff11aec2a063b355fe2b2db2f04b8bd6f9d73e3b7ef830d6716491902c7b56cd484c	\\x8f6382bef86fcae83279aece2db3e3c7e08c086d515899a0354d1c0438dd3e87c611d610640438d75dc4b894356fbd6590c52a582a1b9ed21b903de02ee69b00
13	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa54e764f3f5b4abcf2eb84f2447f331d1209449c336b8c5f7e311ce32aa2480937f5677973939061205e38db1aa263053e41c11cfd11bf1cb0e4d1f0ea3cb97e	\\xb660d94f472a2dfd9f2e04f3227c6a2060b19c0ec9ed299a4cfd3794d16dd3b553251988f74a2b5014a0b0aeb3a8fc4fee8e3ab8a70f9fc2e23421b2c7916f0d
14	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5abe9bbb2bb0dc3ab7f5186da9b8c25fa795953304cf28f52dc74883961fe342cc4bc40d01422dcf271fdbb80f48c048a829eb36566b182fe3f3884044dbe941	\\xf7ae0280fd1d5bcbcbf613cbc63d93f1da465fca3f9f86d5a6f7e5350d49515db959bdac51cd69c297900d06ddd67b021ce638da50de95e7e198c49170c0ad03
15	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x600ab39ddc5fa886efc1259dfceb9578e8c6b4e2a32c16d5cc2966a94b34acd2f317d09ec924e414fc1982805ea3f2ee4dc17dec3b6ac9cbf331fbcb8a2abd8f	\\x757ca1f16cb7c18bbdf2b4cd3a23242f1bc76487f3db29bbdae9e0fc73c0c1b318fec07f06d83ebe97d481c8e0d8fbb33337708529dc43772f06e3a7aa7d1c0a
16	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xca2f989108fbb2b71a1b56d14f71fb7832ae73e4f368c6a84d83c9b4f2ccf8664837a49750da623526aa2f4e5ea7e4f60bdbcc991a746f6add08b442ceeb7e5e	\\x654bda075a103f321925f689c435e0560838f82e5888763ca21cfdc966d0c42727ad37e1ffda9e670d75d9ce3bcbdfe810d8f2e70cc9640be219e5c6e2094800
17	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1b90effb36a6706497484e25fef7384ad8074a801bed4c30aa8a722d1aa773dbb6d0b16160d24feedf89a11dc5b5a7bc446c1f79eb4a7976994492bb14be20dd	\\x0eff6126d204bfd34295eb8b086b642d5805be9ad337febe6f7b6acb5e49f0ac53b341843de628b45877831ba97ddcfa84b8b5dad00005c8559ce516d5f09a04
18	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfef2bccea093755bd4e8e970026301a901ed7a49183cf609f2c186235b72bb365f4382ba30d99ba4cb13148e98a2f49e7bdabc2351b5e4bc8c6d0f1834d7924d	\\xbe208ff221883eaea8fa5658a5ad20fdcc08dd2c0893586c7c501153e6a7cb7dca860726ce6165076ac5bde67250cee548fa0bf42e824d2c238099e514e33d02
19	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8739c2fa31ae76171fecc8197dca022313dae8c495cfc655014edac4f48de2300ce86c797574d22e74cea0446ca9083ce0a1d145f133d2b70ad7fda7e5d4e8e1	\\x52b4c86df35a7fcb3637b2f4a657d9f41a0a54cec8f7e27d2b0de5d88401b2f5e69b92fdb2ecb59ddfc1cd04a3e6334fb06bd32298ca56d0049db016ca0be305
20	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x15099fe7925f2e544de2d2c5fceee529eb10d77c419e39ef80cef6504c601d2d68ba0d360ff576cf85dfff1878505247b82033e0db2831a27425da28e8b5c9fc	\\x08bacf67684e0a837b9d0f328883db824ab897bc444ba0e27ba2961f910872d0aeb506da3ad1e525a36d5c6bdfa918da21a6860ee3cb021a3cfe39ed1263cc0f
21	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x02df65c725b36d1bad3485b0f2dc61e377ae17d7f3ea51cb6db398b2c24d9e660aab36ad50484bff24c4c02767035554835041fb9ba535e0b6ff4ee38327cebe	\\xcde494d5ed59d8856b164c5bd2b255500f1dc26d036cd085fed23a9121152c5a87b99c57a34adfc79f0ac6fcb0d70c51e90bd5c8b4e5f21df8a5ef0023dd0d00
22	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x619cfcaa0540abbc50ca162e1fc7a6a8c90d71d7fc7c14103e999e086d00bcaa93bb731a6dcadd06eabf8ffc11423773ff19ddfcf34cc1c785a21669b431c979	\\x926e8cbf3fe0651ed82003eb5a9bcbbb460da323c659945e19736e862b65fe63a358008c0086452e128ccedf1d75de54a9fcbcc298cd8d008360aa5eeec67106
23	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x13ad008564e1f9b5b60b9a3518d98c41944cac071d461586026eee6883d7302018a6b459e0e8071b89e9689ed7892e9d8ba44646f9533441b5dce9539803a977	\\xe3ca1f84853c932dd028dc1c2cd3c5243f54e7fd1fbd4d087b79bee90fc2eb39d72a0a5f9f9418081e2c68365fea09b254732ce8edc9e22dca448b12347c4601
24	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xddf8090f4098920d078c7a8b56f8f7673f5633dbffb10ddd13d29c38f3fc10ae17e7908f6a25b07fb1d52e327614eea465ea2f0fd7866ddc9492a15d9a72893e	\\x17a940c4027f2a368f0eaaeaef016ea3deb542727ade5753f68390a7df75cee54337c86e0afc4c5ed1399c0f4bf8c0f38a419ff2f54767af6be8d54bad633a09
25	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7a48195b94fcf19e7183685789a4a23bfedb23cda9baa404118c15399967d84e32d349562305dd1b48f7852214ada4445561921d198b8e019ae09a88bc976146	\\xfe926c4e0918849c1ab0bb02d9726736477d2ae7a08c1e0e616629b31ec1702d51f8fd6f46d3086f92cd16b0deaa8704361229febecfee20629f497ebc52f703
26	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x415ba01636385e44a1208cfaf904e4394db5f6f634481412612136fe55b6f7844b4bf028732f032725f84faec8f85202ff43eef543edb30424d6743cbda5d075	\\x3fcca799156121bade656be2a9912e074dd0b21f16cc766afabce6671516000f09c30d954defd1025d3582250d6648c35c7c681c280e4d2f774b779dd313c408
27	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcf31298cab7a1cd2786bc788d16248d2c0424fdcebc0da4af0bd8188a941173c2f713411a633bb10ef746cdd9e84e9e246c3c113b531ac6ecad11046baf69b6c	\\xc3bbebf70a7c08e43a9624c869d3d7aac7293ab2d4e17ac61290393e5aaf92ebf2aa61d236722adf1c3465e35d8594597ef13aadc50536cfae7cd228af9c0209
28	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x891ac1101bdf89b406b4d6166c6948673cfbb8ed4687bf90f95c006aeb1e9ab8af004b9190ee2e5adc26d5d9b48d349fb316437052b6b2a3e767fbece8f2360a	\\xe1e385feda39017f1cda9464c64681df96382ce128e1bc7070e6ba6d0afe447ba8612ab98d4579ef83428de877946f75717cf5dab4ba60240af268ebf5e80f08
29	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x53099f8f3c047f15ad7808e292a5b39a8e6eaa08c94af19ac7b21025d9ab02d307b7084f051e7ab684830d8287535e3c056e51f4ba26ec10305ec14316842692	\\x3dec17c4bfa414f0e6c04d893e48b9608c2974b6d710c0c07599249b6d917402939453000db86fe9092b119a2aa58ce6b28fe7ebac95a9685fd51eefce6c8808
31	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xda35b5fbb78a42f6954f2e9e8223aae8122e88117dd91e9e85d1daea567bacb3b54d632620071bfb636a39c0d9da67baf03f4dfd8f52546228ce2b2ac353b14d	\\x62ed42934ee7c42cba0b1e16d996333d7e6214f2115e63ab1cbc754ecaad370a73b11614b14b33a3d65fb6480fb604f53abcd0057a820014ff0f2de9a571ad07
30	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe2f2ce2d12b61e2863d8b5489b8eaf4b941b01cec531181ea56ac399b4fb4883e6ff7793dd621e3ce921ddbe2d77eeb5433602702d8df794f9e9a43220e65d6b	\\x5a2935fb03a24f4ea55e7446d5d44c27b63711a24899f8ad2f496b6587ecc8ab7d156fb7463e73523d7bc7a69929e6d420f05b598c6a112fd84ab793aa02a40e
32	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x70dbfe2b4404a9049568e5c3b1ee04b314982d83f4c18f8ea464ba297b1e6bb4654d57fbed3c396044aef501dd1b9da5127c5fe865029eeab1ab38b737021207	\\x8fd8022286476d45453c702da7d2d1cfc9eaa87d654de833defd2cd15d1b81c79cf27909d54bfcdfe99b8fe2366359cd87ff694acd70da86d709b926a96e8502
33	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xeb0cf4c0195ac21df830ef28197f669503503bbfe1fa48d28ff5cfe9d4cfa67d96906253d0b783a6832ddf0976c45a91eb9fd97436534a2defa5601aebf7bfb9	\\xb676f329b7d1ee02a12926e42f6012c954f6fc320c179785a2efa36a324c78082bb9818d7e87ce59c4c0daa719254de359188b7a8bce04ec01d83ba938607e09
34	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe184730381242aeaa92b859c08d2e55ad697bc5d0fd5775c872518b56f6a5d59ee4c24156f2401060fe1ffbc31c091df03f6ebd5c1ada073fe05cf2e1ec1cae1	\\xa96acf95842f472d7ecf9899013289a1d72ce167467ddd5d05061670da22a9a3be6362a797e342ba11f27439cffd98e3ce5c5d6f8831e66d62aa1f7dae734b0c
35	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6a7b334c15ecceeac0c73e0911aadf2ecd99190563842c8eebd36da6e65eb1a2628944600f944cf89a1db6d6da5271f078263c23db80dbb708c4f848a0d31855	\\xae6b4f7492cc1e0bc9f0f08486abc7427f36a4de43ede3c8b8905e1893b7e3396e3ab3d999ded9d172a2f940d89c40ca1f84ac85afafbecd39beadb064bad607
36	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa3ccd1df4a54ff26ddc99963a6ae9c2aa9a25659f20a0390150e511b222d24a2440ff0621014b74c0183aca73263535ca53d3d91f77fef39975c0ef203a6b0cf	\\xbdaccbe8e2056a0c5d749ef1d85087c04131dd61cdd5944d5412b135cfb75c75d547ea378ccd6110d1eab8724105bf67cea97ffe38aab8619758ac789d600f08
37	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6e1a5be575620e5cb7eb64d92290ac0bf9e571c4408fc576a7ebe1083c88d39630c1ad850af06000c956d1afa4daa91c18f4a4202e246f969ef72462d5c27800	\\x99cc6e66791731e8ad4168825a5e75bf8a4f909a3c959845d9b6d3d01883925c802aa5e6ba2b21cdd9302b614521cc2edacb841b131857ea48f2c6e68a2dbb0d
38	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3a31f32073f3e926d13973ff93fab9208509ef59f97fe0b082765480c79376c293d4edef45695c7087d8987215c405eea38535830a75a0b2086a12fb4b517c95	\\xe3d5478d55f7cd7c9cd857a20c26c7577574837ba7d3d3627d68af63900f7525d53280340dfbb2b51964e2db3f4cc534baa0630cedea2dbb26ca0dd9f671c405
39	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdb14acc0abf708bcda0312634089b422b579e71eb99364293c0921045a04b437d5b606c2c7ea56448a7a47ae0ec7b58ba08d67fb309f9557ea9b2f32534e7e4d	\\xe715914b43f8478a4427e7a04af8799e71630216f0fbd4ce35a2cedb91eec90fb5f753ecd7713842e963d0ef52587ee279771c8ceafbe1a411ceecb02fc49f0c
40	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1100379ed14de8d20762884b560836b03cbc9b0b2f45b9a939f6d6012fffcc6061d1fab4ccb1d0b7d552e1528cc8e7ddd3a7f092aab970f3c1a4ea565ca875be	\\xce5074b481ee5865cefe819a89f34ee3b97dd8e70099e2bf3a615eb97c57b1ca989ce306ff4e6612b416dad50f447d6c0d7a52356456b2a3976207a9c0a73a0a
43	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdbf10473f3838b62814fffda2d93b4cbd09fc9629351e20cec79e5f34b8c441a44e86389af675dfe46363d17201635b9634f865bc79c6c656ac8dc196b7791b9	\\x8ef11e85618e34083793c80c5ca695456e79e247b738075c0f3c20e04911ca0975874209d35b08570a115de282019c5ffa3c8d1260bd3baf218c4fc205646301
51	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa7e31f55c416b331b33200c35190a944bd68085d974c0744121b7df0f1f7ae02a044dcb693f35e97b46e6ede6feaa3158214f95f0b3ded7e0dfc912d0a4f27f8	\\xe259ed4f5de6ef9e2135f6acc119cb0afd18f0952d9c2132434a0b14c8d8a2d6730c88eb99c617ead63bd30767d76ce3b3ea6aaf0f8357462db57b495c53080c
59	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6bcc8292d799dfbea62e7d65a3bb45ec4fca50d21fcf69be644be3774100f66545c626b53dc0e1c504603957b01f6e23553ba5f65d41d434d3ada712af128458	\\x19d71de5ef61e29f36f24021fe1b7776b51b45d5016e7e67426ee308485d2c2e6933dcf3c22380785e03a809b36b23d2445e4b0e10edab44aa020a21fe00b001
65	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x48efd8445cb1c696072554f248eec3640bae4c25468d60f6d43c8c17ae4accbe492fafaac0840abb6f6d18dd5deab692146ab706c2d79d12e904e62d8e1f9607	\\x987b88bd52149df32d30608718b2a9282761d93f5601e0793fbf98f516efcd99cb11b2765a4985f11639fcb5695dd74d0c2f8c8084db9e36e6356b48cfd5ba06
73	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4b0e6158db04c7fcf750f4ced62fa9ac3f8248436b360a35376ff0572418004ab567203e41c93af4d916293d7bc2df376937a5b2ab9a2b92416d5400eb3a670a	\\xda26edec5ee083f5d3ea3a321206f9a892dc48456e58890472d120388e2fe78010ac88138cb36a36282e15e2de45fc18c3e5755e4c924a8fc5eb756c65780704
81	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x34a82c9cc6513aa420c95bd105b2fc55b5421ced2b5d6eed345a6091456efd22898ddd26130c1d9399fd3272d319819ef9328d7547a8458bedbf9fd1ca69f19d	\\xab601723b89a884ef4370d8a30a6499e0dd4675536cdf9571693d0564fa517dd07e501743b0225de659eff4d88cb129499940e0b66eaef5c2156bb866fd29b01
93	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3686834173cbc49a39123e42bb89fa268f110d37e2280c3cd830d0dcb8ae96d187c47d7973e246f7efa7cfe259a1503da89a768452f79a9a4bca40be22f521a3	\\x84cc074b4bf306dd0f4e5430eb1d4960b86b46ad163da99622fb2214d57e5af2eea9d03ebdfc651b8080b1c6aa44b9ade490c0c31795944535f4a04a5bbc4506
102	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa1840368ed810c314ce324c0c8719822f5c7550c58fbf14381b9f6ca8abc791144728ad5225a95d8e7dd40507f13ac9483ed2436c749b546321e8bacee48c896	\\x425a5d0ab9239d7714a49732447c8962264ace9d0babff5f7ff63ed7b249b9018b4e3d75dee8b4cdc0fc74855055557b5edd26d22085ff7b2a06536caf8a0d05
109	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2d1db99722d08ebb48d6a72547760043ae831bd8b8d22a3dc5a55c30a32f5e2504917aa3840f040b990b319c211dcfd01d94237d59e1869e69095b47a54e21fd	\\x26bb82789c766f4d57295e196fe798297b01ab24dbfc85085d7ec3c1192bec8ee80a5f78b642be6e98b35c8ba75c3d0f87b9ebd877b0ebd30cbe7eb8c5e7a30d
115	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd7fe7bf426bdbff29cef6479bbc2d796e9e35ae3351f1fff563ae43b0d40317e7ae2b072df9d1d6bc928ee16397ca90f5011ea9f6dcefb62c81865fe3e3bc649	\\x580455119862df1430583b0edc9b63557dda075103b1ac3ca822afd95cea5669dabefe7e1a60e23c34822ec38d5b0abcad95470b0416f5f53e1f0eeff59b6f0e
127	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4aaa00c7ee6dc8e2e55c079c85fe466d54174daf0fbfed50344388bda16217c18ac8d85c847fbf82fb08155e82a38f0b023bea4c0a79745956206a103c219336	\\xfeb615b1399dfcfccb3cad9b39060e07cab4929b59c20b2260320991aff6e541adba2dce7260bbc3f006ff82763ba74c3351d76d72f42ae4c38622dad115b807
131	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc7b5ae1676e728635ab889740dde11a047964c5ea37a94566e9d742758391f6a5f0ae4f570fcfd1254e6fb4373e79b3ae75c5bf2bb6f1929118f3d1f93f13653	\\x1050f6907c78bf1303b5283369fa456e9bd293ffc0bc211f4eea5d6fa656ba03a7b16fc605682968b7aafa0a62f705b87cbf743840bc5742a7e53f0bbf043a0d
142	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x62c03429fdfcc4ed2a8f5faf02292240afbb987ba7d6c9743a939c3d3c8073a0bbc2c4b0745ba74be4d4d358e69c20966c3f9df29d37294a08397be2a870bc58	\\x5d7d25a5d2078ef201e11583f01c6e3fcf417e46a968928b11fc1d99e1402c63094f28e50889f9546c2b7ef15db3ab7e36ca457d758ebda4f40911f10a63dc0b
201	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfd3831352ea8822b52e5baaafac1754d56508375b9c004957c743ce336cd9a1d1e2ea8c6fc450253059d35c4537d61afbec6520b95518a0d8a80ae917a4ebdc2	\\xf0029897da29c95cd88c11672ef62fb3ea9b8c90e6fcf226344aad7b5a2b01b7aeb5f03125b3f4b0bb02083b1c167a339cc725b3560e57d742313d52fa72430c
230	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x756b6abd1a6c6134b7ef9e2c4d014d0206bc1a0937d1ebc0d12f804c11d7a14c67a715c4a342f012709e2eb6c0eb877d5a96a8665b82861261b96b0964bbb0f6	\\xbe36025c2b5035820fe17d0fc487049f57eaee9a83d08aa44d71213d720a24c042d6d5ad50b040dfe6c874b1427a7c294cfcf006ae546cbb594bc24abdc56f09
255	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbafd4d430c18f5e550f79bce87984da3c3d593970af19ea215425f8a0240b38f57d9d2f31d709059bf8acc244fc46f8d07399d52a46d3f96d8ccdf4f786bd18a	\\x21ff7704be46cd274028bdb11c91c1a6ff8c8b1dcb307a572f7bab566fe616fa0495c57efc2c095ac58e1390876e629b8f739e46ff68bbe5f29e478491e14c04
286	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6bfd29236bec87074a673cc41832906672346463104c94ee6e99ffabb80e403d5dda689e50424c4125b1540eca616e348d90adac91504065f598c5851b2ea26b	\\x8e84c70f22ce7c44dc8641a748905f66800b5bef054bf453462a4a59ec7f17e0090455ce9cf68c60ca039a7b986f12cfdea2ce5fa0652c052a92189c5841b80d
322	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4bc70b00385c626da5a35b9b10004cecd43c94efc123bcc7a3b4ade1297c01e94a66636b5646170a462cc06d079f0abe65be33bf9c6e17b0d4f2e16dcba8e07e	\\xe5187063832dc30edfc516a94a1118a88833118a4106cf0b95a7aed17c1fef20d18b96fdbd5deac900e1264c8ce9adb5b78903430564d1bbe7c39694ce252008
44	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x188b23e6ae825fae55939560ece0dcee5112bd54e6d9ace08316b5bb34f2bc1951f5b7b2609171c3883b47e5fa4619bbea572008d83f95e6a36a98258b211fca	\\xba67b6f427497e2af248c1d703d7ec631c5b4c99ba29f79ba85f937556ce54f0c542db887963249697168a1816030f6d20417d695af7e6e4ba1beec59957d105
48	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7c23914786bd160822b6c7133845d8e9914c143b7302484f8644e8d7827f748b5b4a3fd7772ebc184c145bd5e6cd3e1bb4cdb823a0c9313efbff1c1f317d402e	\\x5d33677a6a4b5b5d5efcae9a4200b72aa98841cd4269e7f203b88c4ea397a252f33c6c3500c2fc78002c39d9de06f7bc41fff2d6ee2b06165902598a1a804006
58	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x43ed490136ab390fa63611cb7336dc23e7ba74c4cbcebe813484a7000af82b002e48ba2b27dd4f2fec6b3fee8effc1c834315bff2730a9d1b79b140859b5975e	\\x4c11baefba8efbaa4a89b3f29a98e4339fc75d6d0f580fd80536b832c81ab322cfdc77e3d9c0a78b87408d57e26648353e3e1afbd36ee1fb6c9e6b7fbc383102
63	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfb78d86c3e8f3d4a31f69898025976704597928a77e58a40ea3f19c4333f28b9d2c7bd933e9c586d2f72d128cd0529090af3218ce7094c3eb5ecbfd0098bf6f0	\\x6e43143c9b0f11873e947beb53f1f79def45d4f7f4e6becc100348da3a9b8206fb798f60deeaadec644ef60c48b512429bc9491a91265cc27fff21e60bddf702
71	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa4674ab3fd010ad5362d37cf149303facc5f01616ef3b1cfd0a2e57e35ea433a88e6c6ba7234f510cb951a2b0eabf7fba26ca77ff422c31606d63e7c284aafef	\\xce6cadda7fea18a07d4bc77a1ecfa226444ecae5b8b26019ad31e717dcba89f25501a6064a663452f31d09741e6cee3775f75f51d6d445d3ce3c5b53fe13cb05
85	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3ddc13dce5c238f968b3113a5d679fde9348fdd412c3bc2d033643cf0d208d1c3360944892d62d627bacbd3a538c277eadf1c3a3a722526eac582f4dd8a42147	\\x0bd80b2ea6177b558397b8aa9920fccf00f2284b574e83e5a525b0faa099a3c424774e55dc80ac4288f3fefa583995a132e16ef466295aca7f0b0bd35ca55a04
92	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x00c711b6156b20920fb2052012d986821df6fe62f1381c2cdba534a83ee2fd25cdc30d83e22b775b7031d448c6aafb4696307b154d45f6adb148865b6b831f2d	\\x4989b90ac34e55e09b3df43029457215924bac5cc0b506ba460b58b7ac67d970476c659446d60a58a13772e48d5e9e08e433c61f52324b5eb71c9b7aac1b300c
96	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd2d2c968192c5d797fbea1b84de39059a26bae600de92c80ac3c2294d6975a9fee75611ab8c3587b16321ed3bd1f81bd38790a6157de95ee4624e5524ce6db15	\\xa01906b75bc93a4bcec8dedd64f4bfe00790168e31671ed99934d39aaf94f018e00c14edf09e4fff2e01f5eb1cb9853baf94ea48821ec00dcd22144ac63a5909
107	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8f0e7925892b94cada4353da23024f5c0961e669259564558e4d54202b98df355069e7f73bf221548cc6aea5888763035a4124811913b1c1ffa61833d35e8b9b	\\xd88a07319e02cc11bfde5fc4a11704861473c8eaf4d1df5a59da42e3941a74f054d9116480997e161942760be674b0835e05f6eb36612403ecf69d2045a81809
114	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc8afc74ddae254453e37d052e9c5f777ce73a556dca7afc08701438446878db3627970883c4cd7df02c4a71b59b111ecf1b3956ab70df7fb397a14ed04d225dc	\\x0d7e1abfaacd97cab80dfe9048ad189a3862029af084e0e49a4fc36e3472d5e1c3655dd48a6809c1b5b04d382db827860783db8fd958dc5a82911ec57f4bfe00
124	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xce99c1aaf5564c0a067e5f8a3fbdfb4ed3dfb607e40a6ad34fe99b5d33bbe5ecf96ecd951f968233487123b7cc1b8073c5f3b24914e3e16d5bfa0804faf8b601	\\x7668518c68a015e393f0241622ecaf0e176487a76c8e037f7977ea4166df82188ea3ab8cc7a3f182e8af4ff92613f83e575086cff65d4f00768ff130a1afc101
135	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xaa5bd61df94ee1311c4ddfb43440ce6a65c4189f20ffeb1c0c0efed9af649468b4790ee22c7e89d93245ce1e2c5f4a70564bc132bbd4aaa86709c42c4271f496	\\x2dcde1bc7bcee1e11866f0d100d71b4be41123114509792cd81c55f5769483f09d82781780d0c601632fc9206b3ec1db7e080c60bdfb1a3382afd80dba1d3a0e
140	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd22edfbebdb114019955ff72f201909e62952f98578423278ee0f6dee5f185f43c137b3f3ac0d8d39d1cc11b1dcd6d40fe632eeb697f192c582451f3f09dd317	\\x2823fef2bcb71a194d8ab7d9405aef7160626498f4fa063ab9068b7b619a3d2067ad8bcf884f7d4f5fe54dc88d8d6eef38ac00f449f8e109125ad2b7dfcbdb03
169	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x31b5add97f25a67bc7293ba5518cdd285360a4d1571293f6dd8056feb22868cf1303f4bebf174dba01068b6f0514c4e1335061f301b318021297bfc76aa09cbb	\\x7538328315e4354aa1f9b6dbb5b26623f2d574ef0643de9ea8d4f1419e8eec607cedba75db8ed699d886cd6ec30fa2b109c862ad6d4e220894e5b52666b4490e
213	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3c54107f632915ace0bd17f1b58d6ba495d16f93f7d9a51ea57ffb2ef4979deb50c1ea7303db53972a552226c09a66bc2a36fa73564701e13037d36cca710dd9	\\xfadd1b05f263984397be5f9e43f30b6a39a7e95fab8fd0c193774d8ea3663ea7b38ff87309a119c0f2c466de66fa32ed77b5e1463ace603a00896fdab4a7aa0a
245	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb9203a5ab08833dc5b915a11dd0b2886e3403066f742c6744f82b73148946facee540f05454b6322452a9261595e87adf97a21479aafeb2eee19df5ca6bc2f64	\\x0db57b392a0dfe81d0d6c48f5d41751557edf9a1d458beb474f904ce82c88a23ceaa06417cd09fc288e108a7d1cee91bba31adfd7aec815fd8403187e5df8705
270	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x821f1ab2152a3f7ded72752fd7091282819166aae23e7e0961c0d79da2de621bbff47203ce88639fe533aa6706c321db7c0655e8af3670b1af8023514a882490	\\xe8ccabab7f03c6cedb5c942ece86a8b5139c05985237d0a43d488928623d1e0efe11b6a0a8552cac2a4c75be1c6013d436a23217cde78eb9069faac440d1b50d
332	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd150f2f0befeb26e781ffd2bb4c7bc42a4cc0cbb5cc61724a935124200e3778e7d46037056af52f5d6fdf28da4146470c21f29ccad0de7324071b1e09698dbcd	\\x1efd6f4a78e99a926601c5dbfd23d692a33306734a56364397d023c3a5ef76b8baf43beb96dc7684f25ce4453b83be21a5b553fb07bc341da5b76b2c70266005
344	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x51180136f8364c98c9121165264204ff06dd3771e6dbe5ff161205a798ec4984c394c98cbfbb4a586f269c3f13c1e5185c8edbf58cdf985db609d1f42583f49f	\\xf65356cd4a082e4387bffaed0350e227678a3174fb091e9995a7c7fb5aa64b0e76e2edfa96cb90c47f22d37128b7d46b146c8cc345f3c3e85849c1a9a490da04
377	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x98f9279532aa96799e788c0e5966ccc9e297afb34cfe212ba6845eff844cc5e3662c4e0f107e262937c677c2fa6fd12c8159079bb38c3262497ebedc2a019176	\\xfbb13b7177e8d8a8a47e129c108aa3598c4369accecda141cd5ad20c44c7f3f2baee9cd9ee90cf7c7d5c224f6056655b3b1042201f4a3478e3e0c3917fe8cc0d
419	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb4fae41316fbdd2d879e764d67b5fe52aab25f83a621a5d187ce009e1b17c6d36caa2f9b7491cf328c527f9d3a21c1579ef60414078b2c2e7d3440284ae2585e	\\xc4d6cbdacc35174a6b67e5811b62bbcd65e98fb7b98fb0bcf9dbffef884dce1b8769a195262e76f4e886342e5b509ca6ca31a0e638314b7726037f71dd35b005
42	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9c845d6c8a2dddc4a731d5444821afff6bce690368f4280eef9def273a45aba10a7ccbb42bb02a3fb448110905fd379de293e34d563e1ad7db770684818b63b0	\\xbc4e417240396cf4dbe68d8a428a4f70fd7377b6503544a8c7bf5816c10cbf8e220a33217c77b61122fb4fe18f9005acf3fcf608f54112a9d6734bdfe2347307
52	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4d75c4726dc560606ac4c8dc9fcb12327f091c1933c53519c00b88158c08d147bbc7d398b513b4933c7c757b16a463b8eead46f379437acf3a31e0be0d6a623b	\\xe5d5d8f8d7db6c5b8ac0724d2ca97cd03ef69a9016587b72a98691dd9c41aea4bb9f1460d15b6fb0918cb7f31809a64f1766a74b98cd9456a569e9c8d47cb20f
61	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa60f8a6a547b763d0b6e9a4e09868b6a2df4d416888c792e7aeb68843f1c799cea0c9cd474fd99bc7d00d728e9f915d176d2e374201883b61a2d832715781d04	\\x7b440a12a9c38120e0501061d9f12cd442e5ed6c9f716c81a5e067ff101c90a50f39ad2c12fc6232cf2734584b8c86b6acd39145267ed9ea2a1a573bb8a3d802
66	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x44da2f6a1c3d86043cc47fa2fc7ace473ec5b4348b9add0856838d4bc37c329860fbaed349503f54c214686e2b92ec84f2373bd62f3975575817c8272aab8516	\\x5b378715d9e4e9b523540e91dc70d3055da72257fe8ccfc1e86b64170ca6e8a4f3621f19ae6e4e8a6876677b88d310c4677bd02d4d7d0f91071b62617d389b06
75	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1caf8ddc4db9340fc610c3bd429b49ddca48a81b89e1327b6e5962861156415d7491713be513fa33a0ee5d79ba6e16c1e2815b46c1282c1b12f8b1c8c419e77e	\\xfbe5ee057d42a79c6a55461f1602d0f1fc31deac0b6f2e3ecbb39a3300066e5776faf687bba1737d3f89f79322eb32cd08f64d40a171e2259f9e2f7bd8e29e0c
83	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x13cad62bcfa4b06acaa24282f4a0ce134c655697ca18426128cc5c84a7c0c1ac2b373f8aa1e0661a34279e210ff65cade3457da5d120fafc07cb2bf293885049	\\xd949b7715e4ecf0315c589568daa294662bde6d32590529c2feeac6d2e201298ba6068094c4dd43b2d4e07b1d076e9ec93c4cccf47541f1155480dcac05c1f02
89	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x46fedec035de5172d38c2d6bdc5cff737f51af41b7194c15088ac92df7d794050f573a6ce1ca50878681251259d38ffa4b293327b7650cf1b4163a8ae99fc442	\\x76ad4a861866121d607eb81a5076b5948d7df01f2f7cc7cf951b789e32092a2baa8b0f7878f09758987c9b8b192a892bb6ce2d943c94305f9ebd94989b834503
94	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xad7d0e9953c38159c78694c83b61a8bfab7d95917af0b180b0504b1c5c154f3c8e56194af3facd9fdb0613e1bc4b802deed0db0e78cc1f1b179e5809e175e72d	\\x94ecb2b736dde91593ff68f74e4c3393090d59ce5fb33b17df499f956065c8fea1d3f405a21a6b16210f61d8d504cff2c4ee1b610d8ec7e8e9015b1fdeeec307
101	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x88d13523a81cc7226c849af2a345c8fb9272865f0d4e6558b48e7817a535992851cba22c0759a392046e0f4fba1d0a3d2d646b9baf81eaf562cc435f7594eaeb	\\xf88480e3fa8469e5f94f66712b13a5665310b32bace4657a2d5a684406cb991b94cf64eb050cd3015ad2c2632701caec0911e12a3bc32b8c56afba8f2c4bd50f
108	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdb3c3671d7a5c67303583dca8a746fa73515b9aaa159b88c5ae362703337d5eadbc46ed6d37130e3d1aee35094315582d07c7513bf0ddd8890c93224b99163fd	\\x22e57354d2c1149ee9ecc3bde1c3d29b5e7a788a2d39ff92a852353a71272f86ef90c4d73c5732b7979f4a3a8b55e19e7765898c144081a5d69123add46f5d0a
112	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbb5fb96ef14fbfab6334d75b6d8e22596e41c7b1a97ee20ca39b4093d10240dda04f21bbd70d83e83c28b25935cf643fab7b7f17f1c11a5d3954afa5fd75498a	\\x3720a505bd9de29a1b5bf0ab02be34e0cfcb0414b1d0d7d855b134be2b6adebedaa74c45731c5c79ef13272e6341c11013fdf48006af1619b92f197a3028220d
120	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x62518aae65389e97daa99d9135de0468e1ee04a9fdbc117d0d5499b95de2fbc70c57b11359f31a1cd3ca536e2a5c2b441f8481b9d16e49f63ecaca400bd08d3f	\\x0937739fc1cba1371a5469be366c2e3005e66cb5eaa715ad456f09e0afaa98bd897400f4c6967b211780aa35e00f1dee9bddb32691beef7bd85eb09af76c430f
128	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4564637e89a81505c6e8f0db22dd1341b85f1a8a06826f27dfe6f8f556b15a8450fe8d4b04df9ee2cee3d4012583e92507a1e2cd972314479d1e4eabe8ce3183	\\x7a6bf9b60f31a5f7220af828b5fd225a5b64582b1d91c3673a0335bb65f459fdbfb277c5e9c1c885e89a0cde38d94d11feec0fc2e69f7bb8d61a094904596208
132	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5179291e2b74fa0eb0c2405f2553b0a34a609ac13e426b5f64b531f443f6eb9ba6560a77ca7003ff2d3ac3ec7253e048173ce2d2f7391daaf192700b207b3722	\\xd639ae19fefac2d65515bb119ac907093b8985e128abfac60a2ff6bf16c6359673a4d1e9d7e09bdd62eae52ac700ea34880e6aebda0f4d41e5129f9e55cba406
168	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcf7091b5f2414049ac31e6f05d1c0f9e097e97135f9d7f0f85643f8ad54e8afdaa9552847dc860418c0ff92608330d949bdd859b1ae57a3aa402c20a0e3cfa2c	\\x93030ec6b2e3cd530c61aab8de2a66fca791aa0adace841698e1e8de03828edc0282979d5d7954f825d04e28be7c3be99f56f152b7c76ff8c1490f1ab2d15b0e
188	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5796c64cc2135abc9a70e23c93b443e224ac1cf72e0ce674634eab16bcbb5cba4326d7eaee6afeef6b1ff7eb43b13d9d38956f46f33ba9cb59eedff870204178	\\xbcbcc58dcc7673678f136f3b0b42693d93c1a6346a65c0bf411acb35499f68b901c0825f5a08b177fdfebcc9a103f3e13369849f55f03026ac4b6cc7ce655b0b
216	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd0dbe347608f3ba04db511c885699ffdb5db96fde796e2b3f7c9c59e1d67e3ceab89e95e75750678b6b9e4f4299cfa6988f159ec268bcc21e55059bd0a79c950	\\xda5a52d6f41fb52062d3a63e249462133166e5ffb7ef3f4663ade2024859cd3f935fe65bfe1169b29e63016319ad16ba0c43035fbc89c3ea037738e01f041c0c
256	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2cce0cafc90f14013751a1c3e067fcf2a760c8a437b098245dfc2486a7ae27d6d6d041c483b384d13ce2f02c2840130029bfd842a5450445fbfbbb8d6f5564d1	\\xffb03c5aadf20c21f7652c68f024442d82f90dd8e43720880cb90fddc31bca6b183723d157a001c177f5dd56ddade1c84f6157429f74841d3e9beab01b80c601
283	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x44836a8e94741e5fbf83c0f64cc4dd706571b4a7ad30505104ab0ed4c2354b140dda5abc3b582d855d97149a5fe21472e6874ac576e40454bdffcbf93dae220c	\\xfb7e2be555ae4a860a1824f2f820a2546615f8f5a31cc3f7092f8cb578095f4345c3050e127e14af6d4490469010bd39cfcad1141384bbfc464dd03234698a0c
304	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa2dce11cee88116255365f82d122caa94e4b125f57a695e003ff0b8b7921059b8acb6c6476e66c11598924e35c8793a47a4d591aa7c83ac1dcbf1964a4077a5d	\\x9614b28d767f70a14f6579884c05fd004b4e4bf43a7b47a07253a4a11ce1c316a1e7f7452efb7c85580df85d7ca9fb49f0d0554c4ede2507081fe569d1544704
366	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0cec2f25767f6b7be8cad16129e8a112ef6a22d1199d952f40b63df03e5ad210bda6024f3fb4d23477efb3cdbce53d31fc465c88de36c6e1ee6542c90cd10e21	\\x4cc7a103380c91f5c3d304d8c058557abaca17ecc01d3aa03e205d91751bb67e1257be4bde49287ac3c67dbe84ab872dedd6a66119abd96ac558344b2fdeb503
408	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4b34b1830fe4b9b7e98cc008d10717290b7976f1296890b78dd3bc5739124d78f5a02dbc68ade1157aac0578e48d34b0928247d90480e210a570474c947d91de	\\x358d525c42c331ede1b51f8de414e91691eedb6427e1ab5d06e054c8e788c0cfd86abe03255f485850f7444df12f454ae0cd08bedac5aa8e885640c7a549dd03
45	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x70c7960fd6791f02159daf42d96e14aaf12cd6dd693eea39dc4343fa397bba5f75b3b6bbb8a5776885e869185444e22e3864ac9f0d0f3214c1cdeb1da29429d5	\\xa5065334b96f866417660fd260d8bfeae74ff255d21d74e88fea4880640f4a47e3b6a4c6f7510489afcfa2347563763dc78aa1a9c7860cd885576ed504c2d40f
53	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2097fe9e48ca3063abc7dedf7a1ddbc8385b874ab018c9579e7cad2bf93d4027ce32bd29061aca5451841625d2238a285f7fe03b7865a77293a1bef3ddbce6d0	\\xda5fe629b7f2a21639fe57bd3f5bd1e868fc98ae423eb7274f36307318acd802efd89f345f43aa6325dc225d229497beed47a910146c3d1865c1c3ddf009720b
60	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x33ec95fba7bae19aaec2dca25eabddbdf7d2a992435d810d4c338b29e52861dec2c5dfb17923f196ee19d2f83bf4fbee0aa5fd0b7583e0c79fa84e6c672875ef	\\x4b4f25027a114dabfa4c53a138c4a587ce8ad4e07e92f98d2181b5f7e5d340d47cbdb074784639a6c351f94360e70b3d63509a459e753821f9717fb3244cc20f
70	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6461bb94a258adf123424c0e1a86c6f5776f3afaba687f796f54bc4d79bcb258891c8d56ca60a7cbfbf92b8c4ec7a6ef68953e9b7e8ff0e196fb84d55958a933	\\xc3b2b2ab9d61cd5ab66a3ac75e336f9ffbb01c83e9bcdb5ddb02084801091e9826c65dd8f9cbe2fa843327dd5fb0c7e2aaff4e7b2c74e22eec85c44e15e6dc09
77	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1e5d801d15f44840bde97bf42f1966e3c44940718d9d9241cc48e4209f797edad8b2578ac7963099a207bb7fb88da293881f07d9cd58e06dc2a753aba3608957	\\x60c09d8e2d4800144e844f2888f1484eb7c442270289ad6c29777e021d07163f2c9f7855af8786ef842de05e685e45621db562a70f86fdf650de61960ffc5c0d
82	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6071b886ce9ac1cb715805dc299bfa8ed7a2762a538076e67a7e8e5de50b2f5476adefa68121aea2a76da74c4f79e6171f4a1d931da7d3274f5a409e16aa4bed	\\xe85fd34c1ad1da12b28c2ae79c39d212430f294409029d65d2d4b77cb6ee410aab474ce9697b4cfdeafa336c761d38f1703190252554cd8307d3a6962a15e10e
88	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x55615682d5f272b10d0d0fb374ba5168be62ea8b5f3e269fba7e136944202142b5b816e06f89f3120717fa4542fe6f42c2a26f9686283d702b4e37e41d366c5f	\\x2aaa40436a37342e7febadc47a6c079bde1fa16fbf79d2e936e8c2c118541c863e512d97d77252d323174ff7131ed16ec6f3c1403acc9b493a82784918445604
99	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe73cf7328ab2de9a14a46eef614abca67dde06ce9c28d1be0a0b4dbcdf887e9338b36158ab026db4c8d66a01fdfc0dcd5e079675780f8d978b5b95b808efa1f2	\\x8a50a4e02f0dbed8a86b8ba428d5ed71fd3ccb1cd709e1b90ec75eb3c925435c35b524b339b71ce0b8ad81ba2b3b54c2137af224da8bf8da70ebf44a9553470a
105	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc7df01e2457feb25a28acbcf0bd9d143937fead4707e73e094e06c0dde644b9328bc1effa5e88d1fa4f0c272518315e39336e611171cf0f10802acbb466b0eba	\\x287813044d6ba22fde4771b3bd5c0d1d426ea16e43298c915799e4e71c4d1e95258a779ee2774910f90f713d0404f04dab0a0b2826c040f8f8371354deeb5003
119	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x23f42ff9325a392611ff73eac50d6bc00bc63bd96bf78660d7e73a661deaf979247c5a9ccd5288b9140e73a63560fcd5ca9063a930d069a86387b3d4a3a73778	\\x9f0027ce651eca06d7e6927ce3babbd2b43e4540cbf9fb3597847d6f33ea332800f7e25a818834a1485cc4385c046e8640726a283614bb4a4a6b667131f80108
125	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x498fe5da0206948889f388e9ef74f4df0baa04f70f4beb5d4bab57a0c812564afbe69889f70e59fa51f1cadeeb1842f3a4d9f045cf8392a4a4c56eaf6195118c	\\x34f0ee4fad7148b0b66f9c1f3ab991261c6483b9ef26c617f7979afda1fa5d049cbc132d8394df07fa0f6d94f2647a80906839980c39f10a9983fac821ef4d09
134	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa119df890c7540c9054e573e9b73756d0e955415a739ed8a12c6d4e5f2f09d210b6c66a2aa2e1e6ad47ffda94242909e749a9b90bea4686cd90dc664388b8ffc	\\xad712bd3181304e2958ec1fbc4f49ec9f4c54551bfa84861ad1fd5f3e872a57c7216a385ba6f728160fff180554b1aacba822f27286c9d7a1a59c8e43f650607
139	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xae1cd13a4111f7205fbfc780d938f8d803684811ff7c00b3164f8bf2180caf08af6bbab094cd3389c1ea668faa13609c9c13c3a237b96d1e59274fba4e5321fb	\\x9dfbdfd308910173403e8a0cee50f28dab070af387b94a588e97a835e727d6376ae190a1f8530d03ca17d3c221304deb1ed7e9c67ab5d18b4d99b8292da0e000
204	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1496f3bf7d8dca4ef7a87ad0e39b05f6cdae31a4606c35a65f4cf4b26e0056d2239ad3e761ba97de6657534077798351d964fe97e9bd93250a06ccb55762f0d7	\\x1d2ff7491d4b267c2ce1bf06c581f5fc61dc24c69fd76761fae84d0c7e7d21851d4586cecfccd0015316cc767fe08efed12be4847d12f1eb633e43fee6685300
235	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x03967d0bb0dce7960ffce38aa632a3dfb9dd4b178cb4b10664b58587e45db0579ec2d8946c66ee9ea825db2771d29f72262a960dc8f3f8b2c590032a035c3875	\\xb670d226a964602390a199dd4d1402555a69536b0b5b78c253cedf15533495e2d61a29ee41257b1ed95e0ce075fc9b29437ecf2746e36afb362361136d493c01
258	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1556b8aefffc6299582f1cc5160f2e5fb5db9e1eaa52eeb84fecbbb123020e22b7a50eb21bb7843ba71cabedec6c72ed1f08d0b2f2a6fdc78d8019e31bac9e44	\\x1e4a891afddc7fc410d79ac1440b8ab7f0cc971b1df9f4781c2d5a41a37e3ecee8dc373b1ff0fea4bd66f60edaa4cb71fa6cceeaade6284278d7f010f17e0a02
281	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x351a641d8f5a3397addbfc4fe573ada93853cc79766eae5bbe31d9ed99f5e2f481ef67dfb32413e69eae1a417a97f0b3e0030c4e2a014696ab08fb859961514f	\\x38086b75c04ec82bca9419c86bbd4701fb8221a142fea03231d35556a9a7cabecea530bc23928b65b54ff95170a23bd2d7ccc38eeccfbed15a5d68f82e8f1009
381	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x09fd6ed596e7deb6805bfbf5aeaa8263fc9c628e033ff04598f128dc356a75540511a3cef96e2277b75533134aad4cdde5c2e8ccbe587eb54caa05e5bcd09223	\\x20fdc018ed5e214b245cc0f26e5a7708f87f0d6dfae652dcb4a47cb58314b420e0addef8d7f939ea60454fc84f3a267bd246fbfae0e5f8d3089b96f97ac19101
403	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x290df8a7accdf8514c093ac97d806754cd517e785f7249ad2a9aaf59730001745556be995d7643c347de37be82ab59deef08370dd2f1872f23256e3160589ad8	\\xc29b5b04d80d66a51d4b6afcd9aedf66368e251cbe3fef3f2a12b13a770bd96137ae7dab6a829e3b97ee1c3a2a57339a8774fd27bd329ad92ef9178e95912302
414	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa63a5ac342ebebe0298a2146458f3d4f43372c7ce246cb6cc3524f5e1ffd41950ce83ec0ddc06c06b6e36fdb98c19b3e7ea77715a3c6db8e5a0105d0fa34da39	\\x6581f7ca5bd3849697d18e1b323318f1e2b0d0d1b70dfd6cf37e10b3da8e2115941341761ded568b4eb0d2e2bb2725e49656ecfe84637949cebda20ff3d0b501
46	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x98dea645e8a3b2f643413a619707d4712b166ffa5cd24d81962602fc5fc113268868600d3de5e79c1b2422df626d23b6a89c9523ab8049404d5906dadd5d01f6	\\x9f5e258ad40f295fa9959c17b480cdcb015c60d5fb4a22068121ca6cf071d70e97fab09d8a7b45970fcb25dc0fdd019a4797f4c5b0db99cb882fd50e10a1ab09
49	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd446c7fc79834d1534fcf31ac8ec9fc05f5a8341ff2c22c7b027a06182eb67926daa4e3df4737f4088c06e16fde365c7c2d37accf522a295d904b162add55664	\\xb1a14601a13a1d0669f8b2b38a4375a376ee5164a6b78fd48c9e2c9f5033969a1dd93a1b8649cdbe63c37bd7515c2db52700ed1a4b0ba0a0173bab38e4b95a0b
57	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe07b2344c5a811c65d64c9b643446008d9c8543649122bbf6bcb84a14cf91304d12e040c8c0cfc33e290b3e0c00d8ba17084378e7ab444fd2dbccc52119b11ea	\\x67559dc3890f4a91cb5e8cdaba14838423af6ceaf1d50a42428f07b2f34d501b7f95d8dc28f19750a3ef82d7dc56cf6832dc22e73b9b26aa05cc3af493fba40f
64	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc1852fd7c859fc9f09345a1ba2b17e0183068e5e0c4ab9e99ddf7b667aa02b5eb26fb080b640b7fa6bb62db921373f297ababf6b663c6434d6906b2b43e55aef	\\x4e3c769aef47f7d581e54c5ad21315256035e56c9e5c6085a769ca533e30b135b3d1f9740241bb255c041d3831f41ab44bda802bb97a23d543eaabc735b22001
74	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x550be4b8d7027bfaa1b05fb8dfb1e7604fb19fc1155030689d3a84ffbae4ed12b8c7182199e24f758ff6bd29fe500c98cafbb3058a18447a3349eec96e3efac2	\\x938fb0e948f9782bb1bab8dcd007c303f158ddb97ec0e3a8f37e55c64d8bda6edc4f68ac06c253c5f0cf7e339210a84f67366f65b8d65bd9b347198728905a02
80	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf76fbd57fbf6fd63bdefb34706ec968f30222e0dd3bf3bb03d81a4c9c5aec9574344b1b2a4d120d0b39e33649e0648638410fe13b723ad1ce483488d05eb71d0	\\x526feb7766d49a5478f524d73ceaf4c7aabeca6b3b9db99adf94207d5cfec95d4e6ea6e5dbca071c417fd0d9e70363b74a773f4d025d6919035e183f05ac6a06
86	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf4f0b9a7dd0d65e8e0cf40ae547cef4773c4bad12f1fb550c1c1d93a37ef1a6d09747adb502fe063d295211ced9f26eae160f8f3349aea85a938297b77a1a0a7	\\xb23332ed64969ddc9de7f96ba35e7708fff7f71a3f51c6b40c1fe799dee27b55aa8fca2fdf661f8588e56f8f31c60dfa6a85ca2d18991742fb5129c56c61430f
98	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x95f230534ce36e86b74583d4f2197baae337aac72c2090f78f85a2bebeb4de4b7d9d13229a33b328be95aba130a5a96e6ec011e7bb8c248fad511b49d863e652	\\xd46da9c3e57ca343ebcdfd33f6c30201fe15898a61d517cd4953240a7811f2195e76429313215211a6bcbdda4a1aadc8a9cd770a0d90932a9da971346d9c470b
110	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x992c1322f519f663a72aef5ec9893f065e7e9f1553e4e7c0de79aada7906ec334fcfb892d3b46abdb41cbb078c2ecc21f4569f2febba4341b636597d7b217fcd	\\x124f8c20623fb7ca9c4c7c75d6a70b7488b111bb6d33e70c78f90fd947fea4a52154979292e991ad81c29aafe33b6e106240fdeadc1317338f1c96ba6c10df0c
117	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x19fd75b125ac5f33d8a4f02f37f217119be5c0f039f78d55a61d86f5062e9c62e2eb81d14ee733e4c38201d8b4b494e59b56f158f4518db820f363080de772aa	\\x46e4072127bd6777ae79ea8ba9ccc4944438ec1c9dd4076fd698820db44fe52237674e2ea943dab5af26019f2ad2cea83dddc37ef1071ab80d1380c7784b3c03
123	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa37f70a65b86e64328eef648b7f8a4c691065a76d6e04b0f16c862911709f6fdbfac94211caf42c4bcf3c004a3d7a0e19a6210c1caa2d8f133d6bda788ada1b8	\\xd41a5c654a8d8b609a730eb2b12aeaa149f6f7c5f91c190cd32f39a3a29fd1e2d35530e48c9e482cda524072f59f51cefd227f30ff88490a328c09381d958a0d
137	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8db975e8e28b00ca76dea0c46826c307d9116bdd1cea4c504a7de873747e2a7b3e11401ebe48d45f54a03115b7a834175b3aee52e75861928fc67626af6a0acb	\\x6e9492d2eeecbe1b04e8985bbf797dad0dba2a489ef5ac86dbafb272e9f55b4194b5df503584666c2dcc5e32d69913c9a89f7001fdcd54b489c4f90f154aad06
141	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe39fcfa87078441d842ce3cdfe5e4e8f284bf8bd5dd2f9621d7b2250ad845cf6516a18fdc31a0d4d0b8cc42feef7d91935a9e985501d8f066771eee6ebc3d92a	\\xa01d5c69a2fade281e14cf845712e0a29f8514290b34b93cb465ce62475df4bb72669e1b2ff47e1f505ab70f5753339fefd8e2b5f9b4e8284212cac27cf2e90d
170	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc9ff3ef77041f2d78cbb8bfa60426500b6cc5d4de49bd3ded5d689ce4eefa8a00a5a016eb353b8dbf98d64184a7a0dc2f19f9bb4fa273bd62be6926df3769a4d	\\x51060afdff2f4d2e14a97d6cf2587fa9f87e8e7b2815a16ce7f7b98c40484b1d6b38bb26f6677b56107af7646224f845044532ab40b064246c5e8fee63be0d0a
194	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe7f38110801215a429d30e5c86ec967352b132c1e9d10b04d5733a0673b1d013d0210d73cf99b4a597927171cc458ea96103caf5f3ea0e683302e53fb3343fb4	\\x2269789065f5c7e9b11bd906e7c2022a1df5c629521d74f2b0810d31632a70cd60e9de5381e05e5a1ab38311ad04e7d107cad0fa6ea1ef49dcd83f4469bbde0c
223	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x895b3aa41b26bfa9d878272d0803ee5eaeab1f9222c50cc974e1144a332df626c2ee59d465fa09593570e6f02f067675733ec3f0524698e6c38499200e2e0b61	\\xf92cda1d6793426d8560ccaa42313cf4ab91695b34709dbe8548c011d68562a1ef82675a30a60144bb73399e63d187f2d59a032c1e2eec5d6c02bcd5119a7209
246	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfbf82e9fef32fde24426c59170057879eab8c940f50dcac52f6f322a048919453e5fa3a855737eac931f57cf6401a044ef53d78b891b3913d67debd6b6b1eed2	\\xa2fb330cd79284af8177735911dd8cfcd767e39a47bdfdab5f9f16d6569692e6e7ea644ebb9f8a0a45c88804186a702b9eed316da4a8b0c8f765a688d8201d0a
284	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x99f6287ca43eac0c6cda473dc4829479f2b2fc46c173778ab9702e84b8a35dc0efe0c2604bac964100b3281ec178d9aaacc95a8256d5d04bc1dd2fa092ae60b9	\\x41c9d95bde740023f19abcfb4b9a8872cf7259a6398f190d9e8464c0ba7190fbb20b2098fc650fbc7c9f6177b2d971d53cb98d9b295a43227d6b0265abc8c803
356	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2f707d6cea7bd4671a095a8af431c7276db88c4ab1af7d6ff3ccfdab8aa65816a2c30a240d3e959c6280c1f392675fb6644caaa97ba7bbb773e31f7b9831270e	\\xbe4897e5d5291e3f43f3876d281994b4ff4508ebb5fa652ac2d4d57d595100be6a08a000321c506088a900709b8769ebc8ccc86d200a31c1528f10de4bdfa80a
378	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa5abea366132e6e4862d40cf5f6755b5dfb8cf53798900dd1a13170f1f955c1e9b9ca5f7582e95454c23098162b3e7240183ca262b4c7b4954878b577c6b6614	\\x739c7f48cd720b8c29f09f4d65d3e262106de52b8dcdd3e4b801951809b5f1234acd080f604643fd5df502df49c724b81d1e1a6d82cb9102cc9305f920e5b20e
412	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe8c58c7d35e4a5c5d18074283900825d24cbbab31b94f90bacf5fdf34b6d6c9cb6bb4bc1f871050f0276dbdbbe1599696b47c7a5ccba1c44fa1692afb1f7cb81	\\xcdaeb959f007b4ce0c0cd8d594cf8fa106742cfbd2ed2bdb578f54bd049f2e4c7df58177df6ef2294f6414745c5130ac36b2accc0b54027d8b5ca66fb52d530e
47	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7129b3ed37dfa90046cd9e7297689537d9623cc487678d78d881b47865fd795bcf2a94c23de384ee3062e65bda3238eec8e3c1bd1b7efeb24ea1eb7f0497f7d6	\\x7eaea8df95dcafe3e11c395dad2bfa5b027a660c2a7c5f76c7632405caaf7b8adcb5fb3829a849c0902e7a1c5355a530886a447f31dbb822ad3aac0558190305
56	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x554915d950c879015457d6bcc322c624700b94d893967fda0059286735cc5f334e0df72ec62ea11b6a299e373f120c4c1ca6d55aa6f661de65ea7853ccbdc9a6	\\xd8316e8e9a14aff72605f2bf8ed0dd9154fda439ca833f0905f67d954ac9e20a19203193dfb1da02d58b20ca3022dae20f824be7e7c88aa59eb0f6528e0d3d00
69	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb17f17ec3a8375cc5d387c874417406735112de1bf620274784fbe0ec36d69fffbb66f79760d3739ba3e85bf20cdba1d3bda913e3276d4687babdc2366fb5721	\\xb172308eb70b438b66c35a9eb81887fab489791e2c46cc0c3ef13469120b6f93b68efa61aa803d7e8fd012aff66eb8f532ffdbff5dc115c8f4712e54deb43f07
78	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x975363fc653874f6199ca859bb4280cc2b094bbba29eefa594ab510b7d1d213f86ef2becf2733524727d6c594561cd16afcf2d1a77265dbd06b52f2de3eb5263	\\x671d3db6a74c368531729aa91256073867022ec18e0e777641d6802a069cad2f7629eda6a2f30c428e8a043650aa9d12d15955a84a058e86775dbbb404059000
79	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x168ad22ba8b6e3a9d823f7d6d56d8f3d560f43083d0de6b485138721ebb73a10b93d6e48003d6063c06dbf991581d9b4a4c5cd29df4dd828a2651c5bf8f0ea11	\\x949c9a63c4d3b6e86b2fe599388ab79848e51cb0906f151e73c1ffab85c2e87fd0cfbe7a13c2cf74c782606688824ae5381fa8e4295e11349f18f760af79d80e
90	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9737c6f41baf3f6670c660839824cda97fa7f898108bc165dbaef39e604bed48db17569861afc0585d1bb47fe6af1f790df8531be863c256d36ba0b55ce40dad	\\x638e202836e5fa02ba1ce55f092ea052423fbe3160fd547ef7b4212f475c7c6dc104decf3eeb0e6ac255a6743bb3a9847cf678c43703a88f64d2c63ebbf77f03
95	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2a9b64aeb21bf066c250486789758f8370906134104d76405e962d5f5d86b484cd24ef78ce77a91e598c2d1bf9b07d828b860e25e2e820377c65b7221d154276	\\x3da309ba91a3a033fd195cf03b7f6dbe4a4253de02a44bda30239e3b690e1fe8f8974207bb39b68f9e15a15998af176b3ce87b304ae90c0bcd18db1649e7d607
103	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x26504af7ed5cfc049bc1fda0de48e38c0e0017f8cc4eb7267cb9abfbb320f5e037cdc5ef9b0a74648e27a560f02f9ced4e3074372d687884b588566af0fb2e4a	\\xef30d596c93ec53eea149e3642fbd783a638a1114ae25ac03eed28f16369c31c82af4fc1ed5f2b088acc739893aa7746aa8c78024463e4ce49e540a17a67120a
113	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2e69ff8f9c4931c8387ac7868c952fc40885e865007518a394297b27bf8b109363af91f123dd9524559dae60f3b5e452476da4f35909e3396019da8ad64e4e9a	\\x3d614616c67be0b108415bc2a63b67d9fa80b9e7ee0bb2670d6789ebbef980edce86e215a385a2f25f25e22398c036b2bafb3ecb2ca2b160e4aeea790ae0230e
121	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x99a2557d17a23ff7ed20bf5964db4f9dbf2cfdc4aee16bcfad0754e80410f5b70a7b4c0220002f410d5c3415163e95289be21957f6f9d80ae1ce325bd417f13e	\\x9d0797829e32aadd7d391a222d3af636c37e1a19fb2c1efcdc37fde5788ed437b6be278b5993efea59bb8809328710cc3709eb72f5b22733de0c5edd412fdd09
136	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6cae26917c0ebc1f10561ed6227eaa546e4942446b584e4406c46ffe0500992f6c43ba27448e55a1690d5bc3364d99167716176f499bac7ed399da9ef1e097d7	\\xb0f752f577f3d633290a73c273449e7068f7730d93405b6ebebdf3084b9e88a777edb40a39bc4f0a03696574000526d8b126961d13171b148a0b55d21213b408
143	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb8f950e8b3456ebf35bc1bbedd42b88b088e3c34535561d1a31198bdce458a16ab08bcaf4f46096da5c4ba1dcc4d738fcfb402c72f87b5b1da411d464a2ee01d	\\x6084d62952bc2b4f9cb5b8df3a40c8095e6ced84bf66f288d311319e51b3b0744f1ce940a79410501f82dff769ff015226d750dc68f32a2d675acc2f38a9c40b
176	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9d3a9c4453d25cade57dab32f4eb4226b0cec983a5c3615feb1a593087d27a62c4b22d57411d8fb0c895c22c5d5f15e700c6be15def0a4d64b33b4492ad7f49e	\\x78d1cf7d9d77b73f0b726ca41dfb765fcf24c1dcba090f11bbebf89d04e9da0212ada06603c599a7c038b62f7c56b66141e8df77454b9a023aa2c17f8d57fd06
203	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3fbe905033b0e5d93753c43a74fa50d658f4d97fd16e043dee7aa697de3f96775e2560e5b0dae0a340825cbef91b396fc2f36c0194d723a3b484b74b87e8f2d8	\\x0f94f799d4dd9e0b47887be70a107a2d8d0eef561a7eacbdcbb20ac6108fa3165e54f94baaa46b49348e34f7ac626efa4c974b713fa6a7419c25aea2445b0b07
227	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8dcb851c8e1a7636f97300760c5a7652a09d1c452c6f11a9a11738104033e283e6151dff7f85b501adb3f6adb2be0e728ffa2d8f54ba6052a780833709e4a710	\\x2b6ac900a72b53bc1ca460562b50c54fc8089f37b8215be65cb8ce5606eae6f0c1c6c4f302f52977d97a9a8ea35d9e44f40ae412b854e440a7a28cba3cf6380d
244	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6343b0097b5924b4445fd80c3f559e70085a99b2adb3f68de6d29b1e8cc7f8f75d95fc118a43799503df8a3bf0ba553379873d1bbf36ab67d7df3a78858dee34	\\x4ca51824c7d095ab2b147317cd2e60ac8e00deccb75ce9b8fb2b38b806d9ed0cb40126a208ae5255bf407dc529def3503ba9dd26de6e0da3828348ea6ed7a401
273	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x35d2fcc7c6bef3af69b1b095fd37aafa9b423920c3e3a7a789c69ad1e3ebac027b604b73131adee5cc029ef0e9997da6070031ada1e68a22dda1d45068713ac8	\\xc56abd40f611a4767c9128d89ed87d1906a099da6605d420dfc6535e20a4f718fe4040627baa89cd72958b8f23d2e4b0aac263ea6b3f16c97ea7b037550f420c
352	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcaef73f56a419c03091600bcab1acf7f36b0d2a825c7de1102397bb880fc5b36a23c4836be6358e3d9bf2a4f060f6d49a2bc6052795872a9c7def819078ef477	\\xf625e9b2a00e75ac1df1fe14616e0563105ccf8e439f357ca153e6800f13b497d6f579198d59bc822db3ee884c6d54adc0389d9db0fe99ccebf2a838651e3f0f
375	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x58938b22e9308d3be588fec43fb82fa8b4f67c94c0456b9384c7deace2db1c6113886182f1855dca662ecf7d4cfd66ab7c4e212e239f1cbf97f92510b667a4f7	\\x00b90431db695db0538e0b7deefdedf5cafa48ddca46e86380485a6c1c3f600fbf9067cc23a2442fa8d874e04c00d6e9986f46dfa53c371cd539241b1724250e
389	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc493c67889f06c2c0142cf6c4af1c9e68a1b2abefc61270622f017a0e1a37cbcbd0cabca082b30af6cf4c17ba80380a0a589f83c1bc47a405dd9d720d474bf6b	\\x7c4d731e570d4438f0998f2183504958c45050e030f743702a0cda34cfd9ab76eea697373b0cb30b76a8bff5cebe7f2fd013268fa280408e378cd65c4bdb1d04
406	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9d8c45b8e7c6247e751a463bee35786b0ca481b448d0b61b87a0bd9bdc934736e738be4ad43bd683499989d915213750c838a9518bca1406b42c3472229f4c9f	\\xcecf29c9e1a600921b729a5bd4074a006c8eb4a7da0bc54fea023d90ba55b67902e0d90ddc6ef3a577a47b5c2ffdd544ed96564967d5e8e818e2d0c9e192620e
50	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x030c28b289ff6a85ef15a69a352275c05220a01eda397907c23c482cd76416236071c73495f604b21a144b86f06817e99a74e924ed581a957bd43df1aab22b72	\\xe50800aa24b59fd7e816bfe7d9e553a80e0e16b1ca6a6b9673d45847d9018f89409d795bfb9c7adfa141309b788842af64431f4b3f7ef2a3ea29f504a845bb0b
55	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7f16a4b04368f10dcd777e6548497cb9d3f7e6ce40a0883507522d9478cb8672c75c77c0fb94c78a0743c74c3fc97e9273a418d40abf14fdbb7ca65bcd82f094	\\xf38c564fdf57d7cc4023765c1cc705486fb625f50e37b80e3ba958f0a3c02607dbeaa2d8ec4f330c59f25502af4942c473212df26b9ccb45d7ef742544764b0f
62	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc4a008dcda26faa028e9dcb9d4f65a0bcacc682a3599aae0731411f2a89ab208d2139fcd2c6ee3ef34d1b854c589b6eb4afe51a73d5bdd2c8f2dc989f7bf39e4	\\xec61cd2377444e6d1ddc40b478fb5aebbf4cdcc94a613c7fb2e4bb75531f555f162f1baffeee976f3e5ee6657dac10fe859a8d6d0a310410009bab29399a940a
68	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x96e10946b399966ea3bb773edc5365763a81febb9c8ad37086e2ff6eb911b48ef8b1034256c7bcf3db6833db776bac7687d1d1bf0e882834dc72e7718a3aeb67	\\xa4b414d830844e44b06c5eca58d4f1c8e3ce1f64d12634e5fcf446fc1239ded880a2e7fcc8eb4b53a7cfff6575587577cb0d8d2b648bb9e7c1d44071e8cff70c
72	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdd005a18e75150a66d271580b8c18cc099582752f1347c32632ff1287ba503a5ee7b6d39f4da6dac147e57dacbfe7772a6ebb0c7f2024d205721b35f2a555e10	\\x035206abae64da723a09a9469c8384df345aabc0d828017896feffaa0bc3182a00ea3a6b608efbcb21938652f523506570b889b0e583cb52cba46f166a7a700f
84	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x283ab76df5cab09dfc1f6eeeb5629eff5ef144b4b04237884b11fa62b1f2e133b9b8a91185f4b1560c5f1560f7883deb69b0596ffb8f379c1206a5a000dfdf98	\\x7650a2d23754eec063caf03acbfeab1586bad81f8451dbad1832225e60267e8540fb3f1463ddb75e8208dd6d642a34c80f6918aae3c30135b15a2185744a3e07
91	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x10efd20a152ad2e0d6f2ddf971206070b07d8fe7b8cd9edb20a6d80024e49f9d71060b12964e6e07ec83a8f0528d05aedaed8d3b63f8394e091178d39de380a7	\\x7afd7d7d0f2a282ce3639a6fd5af7a5b40ddca01d9bba75fc73d2e5e1bfe504932aca3d5c252fff23069580a5990ee18ecd119b61d4bcdb77dcaf0b4ad3a1f06
97	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfe844257df2cd1f4684b07b4a1d340c5083679757af096aaf3d9facc359ffd7a26d2e4d0c36107b5e7aa4f6d462c30c71aa26d37357ce19bca07af932dda4401	\\xb635603be623d463375d79ea91c5a283d28a564eba9e4239ee6c1fd92d5bd005d48ef2b0c7f385dbd8cc2553bccbfdf5d6518ea00be5fabdf23c7a38026b2304
106	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8cd3d7bf8b8a7e093984850fa6e539e46fddf5faaf81b51af97953d395992ba130dba85dd234b6475f5d7f8035fb4707d82233d368112a1f0e5cfe9bd9c8100c	\\xe6ff4a0b34ced873078849da7fd524b40429b73781908e7968277a830d18e01b71a9184d0868e7e60de3ffc6426801cd22cf5e6245da0cdda584810afe46cb04
118	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc5efe340f067a286d752508f12a5e834c4ad033735cef28a62a7f1b1241e913927997374a8b9927b99c1b2eed43b78394ee186f899365be2d73eb2e4ec276f3a	\\xcdfa69313b24baa7c96bfb8daa2f9df54f8c0a353eec4c520baa96606036ca751f83558f1bf19aaa94299b76d99cbf8c670f0bf63598e3e93762c4e4d89c2703
126	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7714741af34c46162de30ce5639ca13a1a7521b6153790452b27929d9101cd86f1b6291261c15d30ce39fcf9d42fbe2ac6c99bd4989f8dff16996075ae4410c8	\\x62b64319d0670168526a9023e25647c7f4c56e1f25ff8d4ce653cdab4418200b7f5a496bf0bab0cf315d74520d37afcb1f39a33bbba20fb4b2a182c425deb101
133	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfc09d93157a55a97aa0fdbc03b43cd2f6d474fbd6ab2d70c0f255c186b41ac095849e85ef2b1730bc328e47542646338635dc12605da440b7e4f827e35ab699e	\\x93b98a5ece72b08818d975fc307339c34dc6fd05163de72ba69257ed41087d0d4fcb12f16dc4a33e1a6c6c676e3b16d7b6cb5d4ba5192a52e32d2d76184a8801
197	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdbcb4565914f939c7cb87da4733464e53907097b3e448921e7e1df7640d71dc96a8cb7a7202078583ea339353addb16a59c1f5fab38427349baa2581f16af85c	\\xcf2823ec72ccd7bda95aaf256ef37c3b0066cfed4698db80250ecb88b843c3a82509a76db8c9b70b62d85af720872af893059b39a1e22caf425f37fc16807a04
233	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd0e24b02944762bbcf7e70b7e9d3462f40ddfe1a90826f042e96314f8e0adaafcb89d19867ea4f9fb41f7052ce878d26551e385203230d9eb4eee37e115356dd	\\x5edc240dc57c647d16f5007b6d63224339e524265af990337a2ddda674301eeb05f25ac6356fa2741068f00653bd6a13222f087cc352f3966296220cd454cb08
262	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd692cac572934bcadfb12e86e903cb7396e9e8836ae7250763433397677ce2c701cfd279134d8f2db7769e45480696eb3abd87d3acd7b13f41c3ea6d8bec51ff	\\xb85ba2cdfcbf3303d53e512ee3857248a5469528ddbf92ceafeb8aa29e71c926e8ba9f4ac15e648b3a54f0d108a49b218464cfb0cab25842c2fdeb58152b7a0f
294	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcbcc50603cc963d623588cda3253a47cd1e7f99c274fc2c7b90c66f66c7bff73fc567be9c214d68dcfcedb0db85439253683ef50a4dc6458d840c36cc85005c3	\\xf62c264fc82e35ac461ceed9769b1e9886aa07027c82df5576a7d25bf6fa41dde23c2021aa9c7d7ee2393d77f2487646e6f7bed4093f8b101db7b9d7829b0700
362	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa11c149d2c06b4475e2adbe916ba5f44daad8129239563922d7721aa5863fa5e352ad849d11234a8823f1c4be0beac18b6ba9b49268ea6eef003545f5e8fa2bd	\\x9d76868dde45ceb13bfed1cf66cc743a114fb8096e6fa55bbaa501dcef1da53457813fbfcb30c6f67e87881f221890946c902c9dc70baf35ad98b98a91ff290d
144	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9f2c7912e584a7b329964a0bd82ac008234446f605065f3abacc81f1db86923233385e8d23883ed2ecb3bc5b4d9d83cff7509f636ccede02f7912dc927e392e3	\\xe82b48a977773163a6d1dbe34d55bfd124a32c93f8d0ae63ae70e62d85b1f9ac58cc6abba60845dc439d5083a99134357f7bc0e15d03dbe14da4e5aab75de70d
192	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x20bbfe4879fefc97c6ef39c0ada9531acc950bede0b8ba517a4b4dbcf6dee77b3a8a50d60b49c7e1bc2bb890226bcafe13a6f75e3879b9225fa7e3c2b2a7e3f7	\\x07babbd6d2c1694be971ce1357e898d5c2f1773d1181e7428da73796a035dbf92393d5cc9e6b2fc7fce7772d9ea3c40492a444178266bf2f6960be3356d37f02
222	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcf5f9275b4f4bb2c00f8757fc552fc5a92d273f94f9720d0a36b17bf8f1b0adfad13a9910c7baedeedaa9b8795e7a0e66951bca9d1d4f1e0d27ffeb1f95691ef	\\x712cd1d7e8c2776d051e8b1bd8e5410a1f07f3e7bd8ea7d6a6749be4927d43a18ab6c7f71ff7effe6b22c3b7070e5449175b8c2d75f7fc57fdf98376f39f9d0d
239	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd51c149bba589285802064e1d371f821012ea0e2b1aa42d7d738ee96fa43534e74ef7c75dd19cc24867168e4f95f7a2f6b070af3ad79c7713f63a56591f464d8	\\x4845ebcd3a68e0f488bd4c022461bb599f4b73dd853c41184347340ee0ead1aafaa6239c5ff38040f6b62a2f3c13a2abc4fec4e900834d5c4124ab0f2eebb206
275	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x99d440b4dde8e87a7bcdd3327e67200717941e061617a3fb6e1ae42feb6d5ad30e01654d54b83222b47aafcffc26da2f62ea3c6f219b4ac0b01be8212044bd6c	\\x20a12f183098d5ef60d5bdf32a6e9495895a72d9d989f7471bd4c105f30af644af6e2ed53d5c7543018bbc9124245d2c47de0507878fa38faf9842909ff31b03
312	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1ccb142e91b47cf563e07a9542cc637ac1fe55f448e162da1cbee3f8c619352d79284beab48239a7c013a141828f002028099d5c84121a90360c28ae9ee0f97f	\\x15d016eb12417042ea0e5f3cd9c7c5325c823af748c9db35e797033569dcb64b8ef490d8c5365e97a710e7c78750fd9cef8eee5dc0e7d8d33ee22040fc76f90f
364	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe7eaff11b70a457793fa28e20747927e85ac3de0422158dcd7816f77458f1807798ccdaa5869a1009b1bed7a45cad6cb286bd3dffd9c66928a1a1ed09caee11b	\\x3fe529fee1ddf9e0fd39e9357f5beddf1ed88a5bb8c393077a0f3f2b585bf0a1ceb7040e35220cb6852c28aeb71807b5b7f28e4a0d9d03c89d31061ee1563d02
376	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x36403f931b3ff0dae6939df990d7bf0a1bf62de49a3a1b48d53c22554aff3c508940d46166a8e53751f864960d00c789cfeee8b73999a4d6fee650fffa889450	\\xe132a7d9b4733070cdd1a8dc38a0153f5021d0a4dcce28d62e7b8738138b2286c48fadde4d2492f7f8882ec46347aa9bb4c67bc575492dcb45aa701e1d63490f
417	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc6244536dac871e8570efc4cf29ebeafe406543791c75b1d9cbfaaa489c61704927b8728c060cb5a1deebff0f0ad36cb0a4adf8ca3cb9835fc2e92448d34653b	\\x4acff08675e006e6a56f456476681802788113f31d5dc07657649a8f3d9a2298dcce54445cfb6a371c7109154c69a882a639649b03a809c10d76c14abbf08300
145	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb845153707e8eaa598f55786ded8cbe4c0bff1920299c232ef60399d3013a05ad246fb13f7450df826f4f6573bb6f762c564cc81f4dfac13cb3486b3c990daf0	\\x548b1026cd7765f65f3ff5dd93a9a5c16b3f21f28ed9750945b8adfe068eb2552de2470bc45371e33c32c82d8858507d3c5d72bfcf809ca5a58013bb7e239f0c
198	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbacea71def0b1dbb3c2186ab8f246adc159c4e24c4651626dc95b90a9e42147cdf8065255f1664a5bf2443b2a767f5c3d5b22e69b4b6728a5b2b5141f05d9106	\\x9259f1e5625db17172f30436c94aa210187ac0025360e95e497351ec1fd9825fe3a8068d1f70b98222193f7fdd4999d51bbd3ef3892f0ed9ec72545eb2e64501
231	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x953abcdbe64536cc0f9089e6d2b1782cfd75340ae5da633b3356990749bfd215b2a0b8399a9473612c88d0b1f2dec85d21311494b0ec923472a77b5161ce11aa	\\x8da26f4ed7c303feeb6aa72967bbf10f233bca110877a7ccd26d3f01a47cbb84f37b8c28f13e645606bb8478d66c15b052886ea8382fc6eaf7416449ef11ff05
269	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x23d21eb09403efcfe8dce1074e25a3cdf8a0b2bc7612b8de20f1a8b17e05139517706ad6bc7c8f2ed19c5ed6f0e852aea4fd93568b651d7cf84480f9e033408d	\\x81ee8880cf91274af7bccd8d3b9c9b7815c39553dd2b9307ffb5844216c147dccabf08f3b345ae54cbc39064f86b32df741963149bdb9be0c7005b892bff380e
291	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x58e7d429505486ac76994245b7b69ff918bce71dd0a828a3df04257425f067e44658848c6aa17345782dbcd1efe47e46327f2be11500a99d067911ddcffa7c0c	\\x4ca77c69a31f97409c370a958d7383db493f063845cf0540b65fa18e212072942e430f45a2ddc07392e12d2cc5bb7e121a1d0b234c6721162d0dfd6cece47e0f
307	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x67a3d6dd3b2109d36da432c7ba6ec1c1a65dde189f42ec87d05ff32481d2528b188bd9e5609a130bc5d7a9c68a35ec7d5abbcba2d20c6f2d91a8c5c4609c323c	\\x53a885dbb0c557bfc8a3a92eeb355fd2f115663b9d670ee482822291b5a2dde3fa261412ab440ca1b59f34ec349caa83d1ecfdb57f368ea712799ea14fd2a906
327	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1b7a8f9b4ea500623769df1d18f93e355025dbc8b76aeda260708fb22e3a5e05d73ecd04032a8d168ec449167e1d184d462497d2b6744937efc6786f8750340d	\\xf06f83281a85529fdacdf7ec23ec14a0a76202ee112f107ec6a8cbc80fbedd45c74a45fcfb64a1ecd9331afae5676a9e06f53604f282d5af14741a1c80a3c808
372	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x33f44628497a9f5ce0b0c8ccac6c1b1ae9344294f162ee943ca7821818c0fbb719f3c68b0135987caab047c405e6ed318f2de18e7f358aa7b4ff4f0acf13ca81	\\x6c9c66d52ed42424846dffc4250e12013d6e4a6758ff641286e620019c64705dd9f84e1c7bdaeb3f0356bf861811c2d473cb16f858599a5c901c1942a401c003
400	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x487254b902f13325f8fc5c801356451a5081fe9a43127aea9079532824a2a7dd8b110336c49360c17165103b8039c7e48eb443b1f9b7ba3dc3b37eb506984bb4	\\x387d78446f9344d5a93c04743c136165646b7148e6ce1841f08230500483b4cc44ce624b4471f4e9fe9e204ea9acce7a5d5bb560bd6ab979fdbea2eeffb6d003
146	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8991b5307b4e4537d8c49aaed05c2f12dabe2947aa8806aec8ce8d0d383651a49e86552f3dd738778721abf3e07b0ad3ba6938aa2061ad66260a785f4f4f7d2c	\\x0523107ce2a562761a96464c8fde3301364251fe839428a3a3106a2a64610923e5a8d075efe9e9f79ef977e9af31a2e1091c0c66f25971a67e458e71d98c510b
193	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xab70f46261d9936093dcc7da21302070a5b5e38a5e19b38f9f2143f1e4f58d67ffe5a242f66a7fe00da7d0c7a67931e6a37691a3ba95885f05efd3fbbd5e5e0c	\\xb420f1b409354fe1c477dc4af4a2573a6e537f4d55ac8f52d2c7300462583da92e1d13b06120e2e6ab40b4f2df435b9df111dac4573cb42f29ee1c5219986905
224	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x56c301a8a572eb8a0cd6337bafe84213731c3d0f9ce32d1afb246d403c7ba4ff9a80442e3076be19ac8bfa04eb20ba95b1d6cac3bae58134cce4f190284d49d3	\\x7cd8878683e9d88ce89c293b5040e4e1c84d526c9aa5f3198699df59748e240cfdd86aa193fe38488eadbd0edadf08f2d73a2ba21848e35ce195b4911419600e
261	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1d87a8e51218b7516c1bfd0698bb58709b847e9c7eb033667c5ead0bb7cf55a2e495e1fe95b979f6413afe01cca207a29aee6847fd8327636cae05f9aa85fb78	\\xb44c482216a7781fe0a5e260fc6c7a713c18f8073697b58c20aefba4e5324fd95d4c6e347013f290ecc612c11ecb1fde914db1fdc1e2b7eefb9625102737fc00
290	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x383b4e46535ceb9d4ea332438634e7b84b570fc03b47d3d68083e8dbe95e4c0ecf61f4f8044cdf787468e8bcd31cdf4419c07790fc457378ba8dcc7ce4236e93	\\xa594fd6bdad604cde51a052d840091d2703480818431f25719130d8bbd4f37f95ebe935e40936b559fab72b2033c979da69be7cecf72c62c5741738fda736008
351	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x400f130331262d7835007ae42fc20d651e2f9ba2a348d3f1df74f78ee2fedcecbb13e5fb1032ad753fccf079417dfbced160d196ae778b61ee312fb5c031bacb	\\xfb2d9427825dec8ee7c02ee710e4fa83a9f8df32298a0c2ae20da5e2bf535ea55e0d97661c8e869bc21574d7bcc84594bd607e9687bb9441bd3e835e2553d10c
388	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf2463fa5ea697bd47338d2fb4ae96556f03b458d38054e21d7871ee21866e2d4a686eb319797438e4fa502394f6e8940cde3a3dfe2e6d04c684ace882d1f22fb	\\xe4a490c92e922d91ff8216804fa7f4bb2ad5bb0ebe77b9b0deb114f7d386391c7d24376170c3154caf1083388566335f478d45d3a5d3da8a4fbbc374060b8d0d
147	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0d38a964c90917a5b21ff62fd314c1385054864c4f74f096a345ce8c096a3b0456048e975200b6637f9b9e3d6a822beb23bb4fc4eaa45a607ff9eb1638a576ee	\\x1c15d781f79088a8c81be6005e2b81d99eaec094fd543710ade9b11e651e00d513732edfb0930962e1e31a2b531f39eb9500113a880d30cfbc72b090c211bf00
186	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2537eb2b0e18263d61fbea1c9ea10ec50d84ca50a7ede8102128b6ab5d36a81664ef338a2d901d9b7506f40dd54806731120c6a43e5d135da0d6250b25b6f597	\\x9cb488269f67e3db6a8afd0c10949aab1883b455ed09caa932712d434ea7b87c3d06dd1bd45aeef5fb9290cb9d097dc5e136c883ad58b4d11fd0da96f7b17e06
226	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x25a9d3054585bfb214c15a039bb93ae125f9f32feafb0a462a7822d173612af53915084b0466e2146ab4ebafc98618bf30be708c549917ee52b28780147de04e	\\xcd8bbf7066a94c10e6d2e17e6ee9b3425f0e95d025d5d79b8a6cf9ecfa07286f3d7c40dd2a51cae3c8048fc66ef731fd948c64fe5482c87aeb8c8f375990060c
264	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6db120641f528313f02e76a6776dd9d56634cf3e6dbe0aea714fb2d29bd6af917fc1a2ad0aa30ec63b28b8056829379471f150ab16f4d204637f9be60334aa37	\\x0f968cf4cddd643d7c088a6bc2d71958e007163d9510cdcbf7b47bf6bebe1cdcde1945cdf7d145d9fb60a1b0e08f1aa0655c88f4d5e6baee0e78b12e286c6e08
293	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xeb180a362dddf07935622cdfb987d6be604ea4644a6cab9903c4760d1ae2ec96cd4c5015fca4019e7ab79880580ee024c64693f81c1d05cc14c57b20823cb891	\\x48b02df67fae65b3be61127b746c5c831aadf7c2cc5a4fffee891917bee2d21d7fc83410af05a223c7e6185322d08df7523019c7aaf91044826c97ea56608e0b
397	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8eccf2683b1f0b7953cd4b99a78860b6d9793d95622d07f62db76f4cec3e3ea02ed75cae2a32a7a6bba0af2f3f915e99b88eb11cbac6b9278c07181c8d2ee723	\\x9d197b70febe9f5144f56784d9b1658ab35f48f3f756bee7fb5db49ca81c40435f87fbe2c0139cff10b32ee958c4f96902baa8a30e268d70423e73e9e78a600e
413	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfb0d017a40cca834961a583919eaf78132e6a9e3395ab28bf604c3470eb937d67d01d07ebecce04f967a640035841a43548b3e9ad8e715be5a0718fe239c7dc6	\\x9d85e32730bd0dff990bd2623ee7c447807c08ba9b532dc18784b32c48af2a05c6178e8082a5fd1686ba965dfa59e1c1bfebe86123128cb3787c993da88c1003
148	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\xd82a70839a57c5aea05dbc6026a32403754ef026fa748bfb598786cd0411be293c6f7ef383849374da373ee9ebd4128d6e49f912e25f781e3dfac5fc9bfb3407
173	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb248181d85867f83bee7685f93b06269a5aba5d0949e950bd603b4df506ec061f5730ed0db2c17e754ebc5da23e061993d71d79253931fa47ec0451d88dc9b9c	\\x995d59956b48e4659a8e15ee8b142a18e65f5449a1c8e7eccc58a5f5a0ed5074b5160ae54717b0e1795918e2658e88eb3525d6221854a34862de250dde36b80f
207	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe88a41a72512d792e9b2c36c8b41f8084fcca331b4592860c62a8668c550176b452980fe87c63cd0f5f58109d954e6a6c86f633265ff1392686842aeb0a4db5a	\\xb72f8745863678340fff8fa9c79da31e8b61936ce0bda8eddbaadb0d6352fd19f9dc6ac54f8eceac0e8844d03a0ccf7add280d04914da951c280dd995a95f10e
241	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe48fa79afe786ed44e8144bc3790d7135fa1e9f618dfc6589c28352004bb1ab544bcb1004e4c1816e925666bc17912926dc55bfb4b0a7784effbc7a3dc414548	\\x5dcdd4885db887cf75159a287a0f6c7f155ef9da18d22f9b3755ce333402019a748c14be8512bc69e36a215c85cb56fb569c1e40e2a3e34c1314325bb8558a01
272	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x95b047232569f10691fe85c5dd3faf8fd331717e4ca847319f18e02b40a09c8dfb9d6d931f6c18887b9166bebd6c1f511dc461ee08302f38c265a1c8b121b0d4	\\xac8f30c7675d13982489e4c8192cb095067eda0ce78d80d25005c9b947b9a052268bf0502367cfdf6dc7aaa0d305e207daa3eaec7e88d53cedaa806fe7656c03
306	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6ac047fee05827c5c1bfd6e5b64468b9506660b3f3e9dba76527c35f12ac8d0c237d445519cade98cf32be4be9ed7301af9bf255fbc0c99f829126dfc1beed44	\\x75c8b9eff6982220f5d4b6608a187bf22b1208b27a3c49ff18c11c2169d007df279783e801b1ad5968ca97d2f6d497b7284932754b942f81f11fd3d5c5945009
342	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4a656730b15bb65b82b6f7d27e56fd8bd81e28c8fedcc764f3db189a5fdafd0e95583b5178591cd160ecb1e79ad2229e84e10f589a45fb98016fd33c8c675191	\\x5bdacc9121239235b09596a64dd4eebc017c78ce4bb56072a7111261177a76cc722eb8dc5249cd10f2a49226d1872dcc0d95ba0e4d6db50aeb977784d9faf003
368	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1db7cb83ed35fd52cc29a383e5f796cf1c5541345cdee992b682aa3c30c12f66f7b43965c08fb0a89e44d7f4671d18c625e7cc7e591f49893c8230bde66c243d	\\xd257d8a66be87e0155ec66f05ecf2cc5ad728119a4774ef2c380c9c9ee1bee1cdba50530058c050a3e5477ca5c4f366c9e6acf88b3efb0f30f7114558afef708
149	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x9076a747ba39f2c916bcf02280e6c261ede7882b21bcbf7a887b9b7d0ff4d7329cc3e07449fb5ef4d8b56293ea22afcf974961b5b87b3d1c69b4eff9050d1802
183	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x96b763cf415ee2d0e7c578263d703a46678c6528569a9a2b41460e3e3ec7439a3b8feaef180603c2bca840b8cd6a5f77b736452f70a40cb89dfe72ed919e3489	\\x7ffa921538fc331f77648d7925de024ced5864ccb7255f481a54ad05da6019c3f3726458e740871711a20c83c2a5f3dc9d6c1f61e2d45c1a1191d1ef24545305
219	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8f5794bcb636896eb2c2a82439554eb3e88f0800f88bf27e68edab5e54dda2ca562471ee094860d0aff28efd776a83052e29d95257f90163c1cbe84177d4c99f	\\xdde84ba44562b0aa7054e26c20b77b3bcfeca594149cec57777206123bcd1b8e9a57cf6e30d0bd3f9056eef3c51db75ed49cc27444fb3e3d5f1d3291b7102902
253	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x12880ce135de2983b1b998b2b17385208bd3dec39a704c177f9de7caf3749990a13f0fdd9e1ec59f36bd77a1ce74be1adfa4a4502debd067885e946bccad8183	\\x645cebb80d3e86d211e74ad88bdf05c46863e9d95d922b80a186fe75eada02312f1165c885c6a4598933d97630195f5981383cdd44ffa9a9edba41d6a6430607
285	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3321971397dd9d212e57fc58c90c7efb21e4c63154eb6b2f3efc7a393094bd07d9bb227233b88508b3a49e5e68b31938a44ad4f95352d843f00a2d2b6bd612ad	\\xd28abd3a15c7bf9b5d3a45e8d07d0c05f9e6ec54626fa580cfe5c830b5c5a041d72ccc1607dabbea3f751ce49240012b9eb6c46cb6a890930ec8ce2007340c0b
310	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc2b96922175be8ab94cfd03e90345907e622bea595bb34252de00e4e784aa248f73ff31f904f84de23dfdf748b811a342547a08731506ebc4255534f8586f197	\\x1c838acc4d108b151b03aebf0fbfd9c242a694527cb51d781d92d3072668455ab98cde1748629ef2911ed00a566ffe2f3fa02c804ae7a0b33cdf4c201246bf00
320	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x109487a3f26a6e0910862927b0e5f2e4f721689d7f41d5b05a2610406134c3650709ef2f35f49c39ef5bade7d6041b05f629ad97973c0e79a6759b68c1adc75f	\\xf454ed4659ebfda9486c9a9d7cd3ee8065ee7b73acdcba1bbc06fed0e0913fa3b50c0b03c59d3a14b06d72a6b2f7614deab6aa9666f886dc253bca5814a7390c
347	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd4f0eb3c3026c4530a4887fc1ac4aaa298d43c092bb9a1ecb4249b5729bf57edef84446f33ad271a672cdcc3ca352a7af435dd0c4b4248847c486cb78a6ac796	\\x9e1eeb6d6243f54042fce107fa6be031ebffca899376354fcca19acfb0218a2a38676565e4a2452304084aafb79b2f0cdc45df7639d5d17eee34b6b30e658306
392	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5b0e5adbdaf386f522e4e56198a5565a53db5549af09d351591e41e3abc437781c66b61c5c51d36ab43ebb56ef52c15f50bf2c3a352156885d421f869f965f52	\\x3fefdeaa77cc65b7152b65cddf485a93af16b3df291869fdecd0c02772c8e502e0d4d6964ab2dd41849c466ade5751c9de4089bb4f46a13bfc28d5b6c9bfc70a
411	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x880cf478428499c5dfb16ad5d81923339b53a3a228da367b44589d2a2ede5849b171a598595da7b369a6a38896ce9ad329f6d5c6eab9a87b57b2f595301a58e2	\\x11acc4e5e8d003476ab53e9a2cfd58e638aaeb1df4b1cad266c7eb32b080a52467f7492053658a950608f97563d897ed3f9a1c85f4b5c9adfcfa1e0b1590f80b
422	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x096d7aac90848da65f317fb51517f7a83eb3c4aad3db69ec61d05d1443bd312e9255a5607270b832fb0e902dcdbfb8caad30fd7a11e3e8fcb3e35cdb7814a587	\\xbce27c8888ffc476f9344397d51cd9a59c7934cdb10ae8a3e39afc3e8776882b1df2ab4e8df124d3d7604a8e64be04c5d1f65530261232d846dc284a296a7c00
150	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe88595e7a264eeccdfe8a5fcb8190a0e69d856817d3dceeacdb55aa81b37dfc65154ee453254e7a8d505d981ada409cd0640205d84ebe182d0f9286a9bb35c31	\\xf521f1c5bd442fb08eb3bfa968c95f7a796b70e3a1ff4e34e7a7d4864f7879611a053ba95f7adc325bd72ca928565e120998bb266c971a92bfe8a1bba1fff70a
184	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcd88c056326e4c9a27613ee7938da2ba07cc14a84e925917dce60d66f205375149a992fba10d48935eb3df575f27fab20af32889d7d6a3cf383e06a9c9a75eb9	\\x335e9ed881f259b15ae3df727d11e08a8633d656a2d60a8fb2eaeab3f4a4782c3a827c6eb4558eede5e513c64289750748b32316f383a6543be161e2ff4f5702
229	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa22421fff2da4c4709b6358c0a773336ff0d04afca3f2b3ae772aba8c076753908375573503a31014a140382314b8bb5d4c56060652ef2625a65b81d99f1c1b1	\\x2a9c8593a3ff7ebe91f039421e27effe0248db396a57051cf3c797d5d867c802c01de73de5959c25da465925d3e4df810ce08dfec089a82f1af83a7362c2090a
240	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1cc8f1d0157243a59e98e983883977f979fdd6ebc92702455f2eeba011e24894bbde274f9724a3e5497c5566dd01aff1b491471714bd26d2acf1604d39f70578	\\x248abc9245ffae4fe5a9358147089960129b224b45424b918a8e0dcba36f87fcaea03c4ef97fa8a967286c9113fb6c7b3419cc65d1c0e38a8cf05d31c6fe5f0a
274	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9bc893091fc7ff594858510b35b601de4cfd140ff90515aed89c4a21be26eb3b3a82ecd286d89e959eaf1df0ac4aa9fe4c31fd9bd00d15a633d1fc500192c806	\\x5e10b15b10b6a337c7bd10d266456639bf755bda622680f6bdb64a39a45d36d4cf892ae0adf15234a94de135ee361ea7cdb72c35d9b8a71e5ae48697dc18e004
323	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xaacdb4a9e6f5447f88a94a4a88cc9b73a9d086429c49118060b9acf06be34a40dfd4d1293357196c2b66ab5bdc065df0c7d456fe9d2576bdb3fb38b04e19ce54	\\x21f15d5cb9630c0559c2071d9ccbac0083ed5a235dab7328a1ccc2052d1f0de5b88e878912a4626c20af452d262abf3b2bc58163d3a9d56d96bcd4bd0c9afa06
386	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x56aa156d13056346b49ba478c458c47c9d9e61570b551cc41349b534f15dee09ff5babc24bfa614e69fa148f71497a605142b0336de76c683e6e05d925471c5c	\\xbada7d26766d0de15b17ad703f492517c4d467e172316187938252f721aeb304fbf6a051bb4fb816f13e82e84925deebc80bc8cc019c8bcdbb4f2c7c0856d808
151	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5b5eb2056e67cc7922152843534f708802fe3df705070f7147f24f6c768e2d8da86c36251e912ed277feda78dfd35792f85e8244fc68c48a47c9304fad3abbad	\\x080842ebe4cbe8825bba08284dfe7793007de708bda69755897993c73e41753bcca3ad824401fe7bb363abdf953e96b160e4d3c01b5700b4c204648857b50502
171	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x800b78c13637218250c461f0778860c58ff2c3311334e7dfcbc2fe89f1654a02480495e5663b3cca0ddc6086354024c76495c82df301a822cfda7472db97f54f	\\xff9762f2ea9fc74fcd4d8ec547bcec452beb615efe8164e8b10bfbc4e83a6bf5c1c7fc88bdbdc7abba07842de84ad5bd1361fb5b0b1ecd3f43a5db7da34bb309
200	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x44e469bfda88aa79a961972054d1b5b59e8c1dff7faee789ad8f1eddea4d98173a14d920b64356f17aa8652e3c371dfee99c20fed23d0532e6943b609d28736b	\\x74fe2a4be406f0950e1c49b09f0b2ca7eab8e0cdeca5e219853d97168bfb2b03f3f03a6cbd8632ab9cad0b3f8a8c447994f893f0ab36e40b4a923a68f3d7dc04
228	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2d3438b9cf167073f4c01e4363d5250cd2da6e9c730648e1800c9a6eb6723c26f2553ba31f72c2840e01c510fb5edc54f6173e0d7268464d48cd02c381bb6000	\\xd7a7a8531ed85b0e2bc7e0dfec9a122dcca5736c63d77387251532f1b1702fc5ca6bf747c0159070f138145ae59557a9e409ba9905237726c3e1620095cb7107
266	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc202fcbe35fd9b14dd7bf2d45db804257d0073ef637cc9ddc93440c86e9aabdad83cc69547465747ff058fb105f6e889bbff6121ac4fe96beb533ba20976da3d	\\xf4babc6b2458c79c8e9c71578e4f35060446f5bec22593960e3bb1089d36c81db97e720e8afabbb821b20ca1cd25dbdfc2df30c33f26bc8d6acc7a33a0a53d06
296	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdef5ace0e06d8b453528cbb6e101e0b90ee48c35afce676b8be6a77ec5fb9c248345a0d0ac5ddece3641334272a61c02f6ab1e9e935d88bca452c3f5cf88cd65	\\x8144c2bafeb8450a53a92fca0df8aab2f2aa2671ff4425c945471634250f951842208d3a49e6c5662d297a1e1005ac52ca0236dad81c0d2f9a72482001553908
308	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3e3df1d440aa77073824ef99ebfaeac42dd9c94d6e96ed13c9c9f8795842154c3d72eca07737beffdc12d0f161e1f1bea8577e01cc735543dcdbe6d9e4a43695	\\xbaba7363f1b8a76482693d3d2bdd65d63aad13095ee3d59d19e558c936ce2b95d91ae1d8b094945f976ac8c5a882b2ca4d1dda09ed73d31ae4d4c0c338e15408
313	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9520c24971fac0cfdf58dd985170667709f13237aba987089e05053d6da3159793ad2026ba5f245b81a8ac519b996a441c340af6148c9cc53a210c933b7480ec	\\x51e5150084eee2623f2c885e14688cd17215fefebdcdf68c7cb5b8d8da9cddf9ded8836ad2c60bd824f799c03becf355f3f69f82808cef916203a126dbaac800
333	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbc4e5c9e2870dba2b5a8d872a66985147a034fd3cb82715af85931eeaa2761c56db0ff2691026225029232e59fc84b035665b218e086f1f8a1a347a23d51618c	\\xf61305b4e8ce468434d526605301e9c0592fba4e5059a53f01c5710cff039cbd34f85f6924ecd0876fe4d52853fbe2949fb9f36d939a53eac6df8d6c6097c006
346	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3a18bfd05830fa47163f42302c776c12bf66cbd354846e5e8420271f58ad8e1390539cc25209bf2d550d2af78135445bcc48844d88759465c145d5f8924bc1c8	\\xf260977427980a2be214e39e820eb4f2e89d2bd47659667924d147ce2a3c426792cc6a5a7290bb01f5de20ae7aab2d2627003f896780ad81bd58a73da6b20b0a
358	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1afc9c9a581424587b7cd9062b22309e8a11b2a119ccd41068f7f984d44d465191606c799fa65befd4376a4a49d6df567844c27683718694f311c2a1a1ecff2f	\\x804bce43d188d586cc5253e2bbb169418d46e3f416d1ce7c47492caf13c6c3a5d71710a22f0e762c1e45927029025aa9772ed1e38358cf378973203cbce05c05
371	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0b7d77bccee502256496a6c258ee5b9b575d505977d53eb15102610ca663085230510b8c2e748f81642d5fc06ef9d2ac1ad1e3525139ba74cbf5ea2d19950db4	\\x8e116fd2362bcd496bc8b49d1d9953ad8317663955a81fc0b3eea20ca9ec504cb76c25fd4d1feb0e37f16ad0de52d74bb8af3fa2134d8ed11c83017e6b597d0a
387	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8d27307e422640884f05f6a2a1a4d8b78beffbc26e14c4152a31a0e7dd8b29d3269b467dde718b2fcb15a16b207db31b9888cfe5db04887b0eed6fb1a42be2ec	\\xa0465147eba6167b5ea3cf85b685308bebbbe9d8648371072167575bbb86bfc025a20dc06f05a2b13b2d57cb7c81cc5c32aea3c6fb1aa2ad575c9806fd336a07
410	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0309375a7313e2dba97a38ec3def46e038adf72451da098b41da485352f7ba3dbdcd4d1859b63e222f77639836db4c3e489d088395b64ef238cc338989520f8d	\\xc6f5fc39465ae0ce313bc0eafa19d1dcf69f6ef9f6d20376e6f57d870fa8f4224a249d2b52c32a5e7171ea245f82db03323e166a306c06e96c555e42316c4200
152	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3af1422befa117527661150f5bb9682d002a50a0ab312846d6ba73672ee866650375219276998c52230cdfa3b751400dffc3adb6cb3a4df2a4ec81aca25fea1e	\\xbb17befbce8e7e90ad6c2abffc65028065d79ef5a9b94a11d73d66cc9bef067213967f7f8c76aacbe0c2366ae65ed004be426591ab691e35c96516feee4bf50a
177	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3204d891c7586a18b08ad502999219f47a72a7b7f6ad5a729c27d126c2387489c156828df03d2ad0097746d2029c60ca00c4b9037064c696f48b2521c1495b66	\\x8c5bff9f31ce47e40a48e986f83bbc7de677fe21c5a10f4bd6f7ddc84bc4a5e68d503f58d3471c19a9b120379d65224d9ec9441277e3d5c0b980197e8ba51d00
210	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8ff530fc43a70354062d23351cbd948dfb98fa0386c84944bd6aaedba6aa07e258b8d928fcd61558856043031afdbc5fca59da3e87d8058c911e1a4140c02391	\\x7cceb5d0dd202d833ef1fde6ff99722d318d357dfe2f85f59be579fc8eef230301c8ba5e6d3ee472931f0b1a1aa073365091bf57fa615ee3d19a6c6e9449490a
242	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdc819a2ee8fd84336a73e913f46664f27e3d9fc682dd6385863d6a17d0cc2d9a38151718205e67d021276b6a654a3db01bdfc4eecde483ce02fc0ce2b059da47	\\x5eac157ae8346a9f9ae60138ceb3ecf1b25ec0d90e5e626a52cba1a9ee534932a162d155fcbc2903befbb71b49fea396ffcf246aff5049362d9db5e706e9da0e
278	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x357505ae132a970e1e0c4a094369ee13d8a8599715f8a3160e59c7488218feed71bad974e57ac0396bf7539931ad76d2d809d361268a8e62282277344e78a30c	\\xdb2b2210b2b3773b2c5e0477e6b07a98930a169ff69316567057336778992dc5608b01f763d7baae021719cc746ad66194dc5f6539c6c75a16faa627c9699c04
314	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x959f840b83bbd00aa6a298b907affa037972023da9ad994bd408c00d9f50fe51f24820c560bd1b32633eab37c185b2ebd96e47b2a131a8f7422cef24adfaf71c	\\x2d61876d787f410b1fdfc9e1a2a7a67c101200de99e0dadfb73aec68f49be156e3c8b430af35c77f9cfdca13a3ea12c4bd37bd099095c4321c9497526ec8b601
337	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcfe2d6bda1b8a6536a144bc78108bec1cf9f9cb54ab3906e8c78c050a8c7ecaf1ab5a0ac1219cd67b27ff0bc872d19f4082bca2c56acc42cec17dd6f984339ed	\\x72b2130423a0036b24589af7f11826dfbf7cdf5ebdbb4b81d0be043fef347f0325a4e162e617420080f6fc143446a752c8b01a5019d7c9e75cb79a1576702c04
361	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x80c1eefe496d39133296ca5212fb43c560686c0d9602ef82ef50aaf1d5120d2b944654f553baa51ba83cec14dda2eecfba57ac0ba705a9599e0a26cf6ba57edb	\\x291d571c6552091972b7a4a063ab5e4919e0b824d980988af4faa932d9c6b5211a563c212a6f110e88d8806ce878e2ed0458a14660cbbe9c22a4b2cd540f8504
380	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfc22965f7960efd4907b59bf31492058b3031850b6f37ec6620422a67fc0b1bc1d26e377fa735502982e63e394b564d51681cbbb1482baca2dba8c62e188b9f5	\\x6ab2ef6fff721097e1efced775c7dbf821d8a64266a306022c4984981197a49e979f1d9af96bbc1e7093a311d92e4d6e58243b941510cb3e2a1d48b56d2e5e0e
401	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdef095970102e109026cb37c0cd9c7c76bd3aec0df13c9849de81c68eaf9b37e7a1c45175658e6e94305f722c34bd11fb9c0269930d65daff2922ca010473050	\\x19825af595ed85469a0db4f4b023fee713ceacdf3964ca14c7fa7a8b46ed3955861cb18f4eef8479f386e46fbcf6d2ceb80a7dffcd13f582e8abbecc0f39c409
418	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x603c2b5a45c28ffec99ea5266a46a9a1daaf7a4afc48a932cd3af1f2d4624ed89f94f63b6d6f4362b0db4a2974c7f81d6fd2eaeca088f6e1ca77f4ef37b4e1e6	\\x3c436d292c97af0042a8919d142eb0b93211e001b1c4657884b8b933d70392838491113608d4df08cfc5af90e0f68b2da961a75fb85eb16f91a1952d29a0b704
153	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x778d39fc4a1a7202f5212a3e8b336d70c1532b0c730aa778064ed2def124ef8e3d346513fa8d4b40df906c86371db52fe33aaabe969d5088afd3c3381cfe1d0c	\\x34efa3ceac9c7818d9ba8da3ff7d2fa78737a34e9a0517d6f431fff2c4ae3051ab6fc570f87dc858e40f7416db8e37c8a125bbf9cf5e466334637aaa2ec9fe00
199	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x486b2b34508ef8f26abf46f7da63ada111292330f3ee91a9464d8f521cfa2a32448cdf63c1f5100607fd292a27248b51a3c4e66d019b7c7363287fa209d2658d	\\xc557455e734e2416f2f13717859628842ca5fe1053b019dc6dfc2b2f6c59cff5a5dc5281fd40381379f546d9271e6619b175ab7af12cd2cb0f588c7d6e645f0b
221	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x75bc468eb06f9dd15007a68566a039b8a11f4ce6326fde2f236034cafc97d8799a49a2ff605bf90de476fab40577b20f94509e1357825435bd794525cef35626	\\xf6449b0d38238ff3191b1bdaea6e3649ea9e7876a75de382afa7140ca6b305814fe96f65dc79b737ca5e6db9da252fa2d9850d8288f452e3f36d2a5baa011a0f
243	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1884b440e596b03594f60191c5b23fb18fd3b3eb1827840e052f638b696b1ff1c511451ffd3482b1d7e86b725923d3ca90fc1c5e592128e43f25050496830a45	\\x569024469ca58a8ea3c5ee2617571682aa1b8876e6e273245716bb75a56aab95a1b5fd1f190841933973cf6955dccf0b846390c63bcaaf247423c25a29f15904
276	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3be10ad71ab1aa4a2902aea03fab725b38c9787ea858b7b0cdf3678a3f4ed282d41545f230a03cd13c47c82f9a86216fcddce93bfe833fe3f3d3e6ce977f9e2c	\\xf19b35af91f49f3b811845f207490f7b0f995ebc88cb5a8169fed4e677e62efcc7c9e1ec9c6e08fd7d55267fdc2bf6f51897efb13c821f22356774e2a42a5804
318	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x49e2f2a5d10e0486bc74158874db4c8f90054ad92d4b9023b77aa1dd1f4bbd0331f39193f92bf1c6374c6c90c1fde763c5b88391c53883d5a5b2cc01b1d73105	\\xd5f279baf9063fafed576bfc0ee0483c0cb269d443c5d7bb5ee848a1dc25188779d929a8b5472f4eec496c3347a28f9576633ea02804b6485dd5105e3da1c005
343	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6a9b27f2dee989d6bdf43514e3dec454d13053c60424814890f18b92bcd6d4141ff5895fa3585a39df7aa182dcf58f966d8ad66d9e33997db438102c2a4e7092	\\x1ab77992bfb3b0fe6484f1ff45052ab18f1eb4e11cd1cfd09dbaf7313eb277995ff8ca67302197b99e3aa116f24c7b83e4233aee9f69e661fce266ca92404a04
357	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8ff2bd17a51cf3dc28aada5d24279a0f7f3e8e1273ff226fbb5e58914b55a4e9d0062fd2904583b814fed35108c3352295a7103f7712d5c43452ac1ea4f41e04	\\xcc6e52aa58f99331541361a42e446aff23a4b98d8a88ffa2bba563c08dfed3d9284ee0e458a57fdb5292d57c2809e9e0893259d23cc2f50fd76284a89b5fd108
394	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9f8b399c5ba1e514c5b0e2799ce3898fd6a7349e7dd16ca8b60f47c233650285c056893b1ce5187c5f5c331f26bca53d90a8435d488c05b6e72bb8fd923c75ee	\\xa5d85d028cdac5271816427391ea9ae65ef6c3e440bf6abb75e745cc7b85243878cc8cd128683fd5561f17ca1c18beffcd89a5743d5fc5a196e390442289c200
416	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa0b9c0b3f3eb7e0e8895a1d3a39d7de300182a640f964a240e55d3ef18074daf11cd68fbf110cd7f40edb259da8fbc04fbb8e7c34d73cecc3c1b504006c8c230	\\xf3713e107dc85bbfc39b079725df252beab6586402b3e1cfd55e6d8136590a0810116aab30299acdf955c8b28e3096e0056d8382f13e367b8ba0033327051a03
154	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x43922b3a8d472e56d4e3f82e0913bb2542c9a6562f138309abec176f763ca2352447f6f4859141080d78138bb1c5d115bf86a029a796b0c4bd7671fc36fa7e06
175	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6397ecdc14ee1478abfc768270d271de9ac7468e5c307b6df7c605cb482d3f070ca1934d88853b6316a238be096dd12b5264bfa5cefd0b22c655b232b2b69507	\\xc1128bc183e85c892c9b5bc6be3aca217c0bb07840736032ba777c24370522bcc69708158c00db5beda35d42882a5f1402eeec4f05b40c4fcb73e3d05ef04107
205	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xca8ec01717e916871a244aad5c1f9f732a6bc46459e2316fe3c586c6903a73841dd62341c629a587424c49dc7cf4e033f6d5bb2564932f56c024374dff711429	\\xa2f58afed1399bc6c84bb3b8ef3948cf26d952d931e3b8734d452a37bc499bca1d88ce9bcfcb096f5eb9d7c648854b90cb71c51f27b9897b52a98fcb9dcb5006
237	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5a41b611c377c1424fae72c4c981052079c9b1e8dcf31784b51b08136c1a815a0e4b0b81b62cb26eff43482addfef8ea463630fa5684ba63b6db2bba7b1ef0b2	\\x02d59a3c15f3b2fa9b663f129f436f081fcb28cddaebb630f05048e6ff94edb433abe0f3b5c5444299765a6ce411ef4b667e84bf1dd5aee5d9703827bc261c07
267	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8bd0ce44ff7c116cb59223c42e2ebe31e587614bebd7d652aa9a966565215a34e937a0a9b4438407c3164d2c76bacf33d7b7b9b3e6a3ab1bc566a1d38af4c302	\\xf690bf0803fa70d7ce24ba42f54e735f9475237c90c5441a70dfeaf7b5827d034f8493056c6dc15ea5e3c9e23a4a12e58cd8ea04a49588199e1e49dc1acf350b
331	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4b19a92c6043bfbde8c5323c0d241311854a70fdc68382d65ccee869c9bffe2e5935a6a2ecbd85347828d55f53c16fde863219f875709a55b31ea6674a925c8f	\\x595be53d43730a78d18bb029007bccf3b082d106b1235f36bc1ee9d57cc68646e63e24b3bd6a3f73a55a5a4ca6cadf8ea98744cbb7f9640bd05a2b546104c500
360	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe29267fee66431595d85ec2f2dc6203abeb8682fe9932c185bb33fb1937f65cf0d47c84b425a85c86208215c81eb491ff3c64adc9f15634ab4650ab5dee86aff	\\x67f20254c9f82efa3b254c5b01ae90bd206f6a93852b72ae27614e74d4df3371d6714af343e50599717945573cf5236099110d3b26fdab6f5cd9803cf830060f
374	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x30088023011cab513f1f96895d4c5f461b6014f3f9f3fcb4cf1fde7377ef9e29377e8677a963c38fd367b50fa9e62558deb472ec8100e97cd3fb51cee7f5b654	\\x70f32eb256301c68bd47747a1ff7baf90f73f63bd93402af99f0abfd50f45157a3e82ede6e6d6ee461118981f4b09b0f9c0af832e21da8838c5da777a314f701
407	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf8ec6ef603c9466b38d3b10e8bb61c20d66b561841035dca2382cbbc9b1ab1cb7b0fbcd7b74fda23042c52e5eab2f80540371c828addb800a03e6d757f751d69	\\x9387afff10f3fe1d242a78158866c0a84626df43211e6226f10bf59547ede6529d92dffc1d81e5fef03debdc2cbbfa7e95f16ed80cc44586a74b65ea5a13f101
155	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8609d0fd766d357a1acc40d267bbeacb021c8825862002e7a6fc4a0aa98a5918c0e2d374f8b50a00ecb53a1ed2b8760a0a2924b427a5b69eb6963d733e1039a8	\\xc94909bcbe84cd2323e3fbd6cce24a05da09fa64b690407434f2e179178139e0036079783e93a92f9d46be77fe0c2fd0c26fd3e0a7ff82fa35834d4db96f4a05
196	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd775218536a4c443ff1fc4b2d30461999ba4f88abdaa3c3a8d5f3c6a92e62819312e48bb24c649b028c6e322783de2ceb45bef236acf567d98a676f418b728b6	\\xda9582944d1ca97b3b0135a583d8fb421fc7950d5e4c1ee5a9927546b9b159ad3e791cb3eb76c340e66945fc283680a154c8c2b5ef44eda3aa7970c07d061204
220	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5eeaf32567789a9ca9310cc77534ae555d1566689d837f9eaebc0186dc8ec894b967c74740b73d5e7548ce66b35c10b4271aefae83cca7cf4a3984d6772d86c3	\\xbb475237a2cd11168417de8c23a03e5e42baa5b033ce1ff88d9ef64bcd367f8887a330e8c7be5388973a7ccaafc4487422518ca582bfc7782df937adb24c3708
252	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6d60278c44e1a8d1348938e62e0a5044b759d81ccff8e25e205b61a9fd8d5a07cbcee0c3605b94f1dfec958b42c464bc3c4c3be52f726ba958b5131e310c4d31	\\x1a5e81fb07ab2c8ba8ff258bc83a3f784b0946faf0bdcd51cc3262297277966cdbf18a888a68bb44786c186ef9f666feb9231af3663ef375a13eacf7866d8602
280	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa44c253e77be5870e275829a69875e291178d54b5ba8584fe094bc97ebb81274ae2d44d8a30646f3fc07111a1c7430606844d59d3c4372c32f54d483d59f61ae	\\x3273a61d5d2296fc9595290a693841929a9d30523f138c49e7080162726948df3f3ae95f848b9a83f9793a230dc4a7156453c4c6756541f40017ac5af7e8d208
301	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcc773ada08e85e52f58bb4ce44a69977d3eec17b2aeb52aa8dfbc2e81b7ad1491315e142750bc713b86177ce20e1cb5b3ed52fbd5bc77ad0ed66aa49f29ec2f8	\\xe828848796fa13b1712a5432df8a6ee830ac9c922d5b3a7e1ac91bc8b12e0721f44e3ec1d0de13e0bf58b90074ef3f86438fc4e90a914126586799a522299f0f
309	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb5aa0b2998a1c94dedfada5cbbaf26f1ce27b8939b90fda9bc4b1da08e4c7d256a0a5346bc49933a2c171f7eebb055d7ad2df708d795e8c360d0af719bcbb659	\\x906c7705f1563c122e72cd854ddc8dd411ebfea81fb00588c5d94b0d0141420b4c6f8a91d9d28bff382eeed8d549bfd9c3a0e477ac0a73555b36339cb4f31e07
324	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb4203dea9ffea8681d60fa2a03be5c32c1da6abf1943f4877593cf254deb518b6205df18a6b26aecbf0becc33749167a4b269d85b9715283eebcb65e59aca3bb	\\x2ba051e3c0a2c210f84ceea84c5d094f55f2bc9335aae6506ace452f7bd2e5c01f03b9bfb583dec19166bab55f025ad65479b45c14987154a79a64c34e280a0e
340	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd01dc37f14e772af9d6344a6974425c85f075f8e632279a6e845365aa88a68d3b181c31eedc6078261f1749752160cb680d24b07d5515b1105b8785e77b51801	\\xc154411e3dd5ab066ede64f35b8d78d4be61229400f5425d9e9113e6167f65568ebffdb85ddbbcf5159f24cf448039b84d9cc52a81dd271b78fe37a6ce78ff0c
355	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc8f76846b08c3780725813b35f0db622e6a053d25c3ba67253d979f03428447458df691be478b54f1d90aef4445fb8ccc842447e8a69ad3e2fdcf57807787de6	\\x9a39ba4f9763da43939d41a2bb3e901ba20256e6caa410237f5786dd36973256d0539bee4b672d52b3430c0263ba5b7636ba125059cc12a6993adea4f53df707
399	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcdfd93818b8e6b641f42fe0781646eac15d95cb892ab772c41ed344bca430ac156db2703459e21d5eac3569bf7b8e2c88a300924d5bf152ad3a856788369a2fd	\\x42fbb33e9b0f1bff65c5f1c494cb664a9a98e5d58b1e17e498581ee66f7ec7ab49f271586d9f997ef48c51dd63a72cbf43cd408a2ce2609bc3e835bafe8c5106
156	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa634c870a6c2443a6b5fb02dfd510a3d364935d851f77fba0d7ea0c7d4c2cc8d23677f00e14e119a9ee1b85aef77961a4628800726c6012ce23e26c04c9232cd	\\x01a8f6515d04e584a2862ee8419d38914c2955b81418c23df911d37e148bc3b4324c5b42f9f2baa0e738264b4fb02d3b6434d3522cd2b32e8ac251e575d9fb0f
172	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7b72129c4449b7030cfd6c3343113f7d6406948af330ea79560d07439ad04893a85280208bf1b335409f345725013cf8c09b99c8f8dd7da23eddc79633c28830	\\xcfd92b9288008df018a9b159b4fffc2725e6afe7e40c59cda35fe4e949e73d1f6f87cf5d9130371baef8fae5dfb1dc4e12877f0382dca8d59a6ff19d7ae25105
202	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0a0d2dbcb3ac2be6c23873883a5c32b275a08c72274372a0cac0c8c733309a6c947173471e4e8d3efac4597cdbe76d5a526c091d61750192214051ca7f2c86bd	\\x2b09d73d1fdf196f2ae6d0e7178f529e80e291aa66354989eeaf483e03f9c88145f9a52ef7c4127def4c73411c5296bdced011986fa27163c17962ec158a4d0a
236	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc8c680bdc5907f639710d565e74a53f613a0c7b12b96b1e4508f2696dda8c03d8b372e36003f3728c71bbfbed37b705124e81d4f54a55f9918f011127b1626f7	\\x353104e029e808cfbffe16ba1d07e7d66d61a19d7e8ca2357af7bb282eb0782d8de43e27aaa97b44527a648d9c624ff7e762eed6c2926c0da13a97789467a10e
268	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd2a9b723c4e251ad2a0513a03f8c3b8e286ebed740dda9e3b4e1ca66f53530f87cf152e0d5dd5ae6f8fcb4cd4e146e05caf4bc3fd19ec88d828cdd91162abdc2	\\x1e5d42284ddf0d3a9345bd9fb08d5bfc6ea6a58d882e977eda7b0f33b1a42d3777ea33f5be4eda3ec2ab0b34fefd588e408331c471fe489b98390a2c43a2a20d
303	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x99e3d3c99c94832e6cbbcc888743894dc4c6bc9894919398600404f4241c653d2d89450751ae669d4b2590905a6eef1207eb7b4b584509878d767742bf8f3fed	\\xbfbd70f04e0a20af0b6e6c756740a358a353e121c6169d70655fd36f3546b3ca520269ee1f6b1e73646b559d2d73ca123575a1b00e0c337b74e3d5082f100e06
321	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x538274994345493fda374523c24280b8b6a0bb4d7656a0a27c78b43e2e592e68ff6c95a8a6927896b5a3efb532c2b891b5bd4c1448468b20a129840cf3374a72	\\xe11151b8310bd4db97d0adf345303885d6b811f8c8a45d7abfe4cb3ff10530568908f6e1538b2d11ea7033f2571bac5fc81f6da48ee370522377afe329729101
354	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x788c58efb66ca98f6fae6e9855e56fa18ff609866cc60f8d4a7ba051a5a77d07cc76411d879b53b225b7f57c74e277e91cca7ff4b73eab77319a92c5add173b3	\\x0a3511506b3496ca17e5ef2292f0c8716d196c732f8273030d1399d04a18427d5b3fe2f7a9cee2bf92c59cf911911108c5f42ff3c924ddfe721f843622166d05
398	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2b7b7fe46fa508bf656188f3885a15064a59867dd45a57f69724ed6e50cfc0f5f2ddb06f32f9b0921bae09db7e04ef333ab5dfb7ee66eb44a0a1bffa83ecb777	\\x1891fb5a4bea546539527ce6141438b8a19c3642f51b50d805296ebefcf432d94af35a15fd633bd939262836625093c6ef38af65830c5192b46487573bc20d0d
420	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x891483f5da7a23a242e4b85582b1a4187f3ca2f6999fd6ef9f4cd2596ff611d2f63d47dc215b5578869b4b44a5fcb1049bfd88567714388da5a072ea05fbdf47	\\xdc4513a23fb89b342952a526416dcf617dbefe7c558f8091657429b9c84766d07d617869de1958ebe04e986d9d31471eabf9a4a2d48c32d926e324cb28e4e70d
157	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3d6297d19bcae0e710418aa4dda5a38b6e552d3878f130eee25ea9ba3eb12ad09fce3de453aa6874144cbd35ec95e4529bed4c5fe54e3a65c34da9ed3b0eb6fb	\\x248f1f72002595f93c9afb9b3c8d2e0e46215b7db15b3a12e149ce4e962cafb7ce0b040bffdb9c8c972598408c935a4bc4583bca4cc6d13b1dcac85c75d7810e
185	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3c73d5ac9079e0a53019b02c97db14205863cae093b505574c68ba9dcb9423483adf82206e80cea0c7bb0473526c791eefb2b9d58091823adbf2aa66813ad25c	\\x3acb4a6de58e2380b704fdb94dd37bb1f1fdd05dbe411513140142de55f4fc8971887a2b10710b531738423538d5e9451e4f3c2cf063cbc778277ab2ca7f9805
212	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7d4ab868fc734b65f836a884f1d830fa076cca0f2490c3e93d668154afdbe085cc42e6121725968c7583c4661b1006acf234e436caf0f7bdf9dde19c23842228	\\xf62f75ab9ed941e1031850bde2cde06513f41f1f1c097fa8fa08acbcea936b2ac5250c976127a570e87c8dcb4002440eeaabc4cd9b46e84171ff50c4accd8109
247	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf5ff97d61a0cee7c71c4479f533141461008793743dd3b5f8615e8df131df288b075fb1d8d6ed8562f22787d924eb3e501bb8b936041af2b0e76f9cff7004184	\\x6dab7ac2c5e559d5399f0a8f01b5fcb1cff254c65fa47f27aac2ead0cc2f2adec639d13442d7f0671ed8bdac1f3a2ee4b25c00332850b9fc3abc2649aa7f3d06
287	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcfe89cd9e712e9320afb95a984f10d36e8bc817ee0ad3061d55d9cd16a466475384d322fb2a9ed88aaa5cf956189af37c692b3f8a1906ee7edf27b5ccfd54177	\\x4dc6bd25f67c469ca098ab77c3ffca968995f975df01d70ea851e01f1e6eba87f3a3bb3e0f00c9d56347bb1d5b13b4ec98008d63ef655e06bd2f2a48dd9b2f09
338	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xeb5e0a5e6e4a707f8d449ed903e0cf6c1ae78fe24ad9f14932302937209035353957c7e331c9fb872c0dd8096e4e84aa3649597af8e5c8c274e41c6180f38ea6	\\x60d8a5d1bf96305a3aff472f1ea70845500c9b993da8abfd4acae85061ba30b69fad82728cf09f4df836bd5912437114745fde37c57bd16b8d0972b1ecc0bd08
350	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5698084d85b082a326a8ffe71405d05b1b6c4dcafba7e84f0db997cddc6e0dc20105c8f9eefb1d8fc095a7aa22171aad362c9063173973335dd7cac6a878fa53	\\x6a7d5b281536b8ddfb410d6f6a638710452ff87718f7edbdbf3d1f9e65f48567e42113fbbca6f57363be124eac3bb97c63d4c232e7228ac98baa09a6020ccf02
402	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0bce0d335c72380467d13f759a8ba632befca7df841f6e92915b7e9ea26a66b8ff2d3500d0b39b92b067d5467950bd324f97af4540b38e15661455007c051a77	\\x23a79475838973d61233337c7cd1a8e77a45090fe02539d94987d34aff3cf5591ac0f4b5d69b45fab68a8b201d35d0c434ed6df47dc22c1501e2d32ee6b9650b
158	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1f7c100c6696ced06347e3ed21fc694f33151315daa79530cc8a88eaf4768af1f85f92f004051ced196e3d11e930f7d3528431545dd594fee92c6617f084fcca	\\xf272e1208791fe45c5b40cfb51e954afc05e1dc511c2baa3749a9e0e16fdcc68c511cc5ca6ef98ac470a04559186971b23c18114ab3977be43e731c47e3da405
179	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0f1165c4f644882c55f0642cd8d4e8052b771b3ea592b5eac0135d17aa1c3e74cc9c67a697b1c94777712686dc22b81829b8c86db9dc19f3ac68956583654aaa	\\x233148b1136c1018b903a7106fc09ac201457c1588484a3545d1e8f95c5e2cc42e55474fa1ebbba7c01d8a40ef51bd46570c1ec95df8d7bf417bd62fa102670b
206	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x20d04a955110d5e3def1ea74438b17cfbbcc98af373858534b0b3a7e1e290879a7340fd91155dd1519d625e7a27314f05503f7af190d1bd3c5e6689236a047a5	\\xf241fc48f31abe7564978cb37dc68e43860e17bd3f96bf07d1cb8df075f105f3ec03b11ed30e4c5f116c009a1329b562fd02ef48eca5eafbde51681446565606
259	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x332a18246e9b56d8470ebf35dca9a7097ae1213a14726fcec4462aa67dee71d1f2597654df3515ef4c791ba1a1ab691527b671486e8f7611b3d93479f3c17939	\\xd4b353b62c1d49e663f8e443ba0e8949d58fa8490abf65a7b942c4ec15b926db34809332f34ccbca7f9160a60510357c7101136a3f31a7d05913178fe9ca8f0d
292	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe9c0e0f8bc3b8531f5f706938f53c470d20ff61e9aac1da173cb8a6a5b5dc985045e84f8e3b5c99fb42c30bef368dcce37f76c0b45d8de1bd069cc2f7a82dc0f	\\xbe830c0359d94b11b40756e6c94091b92a06768fa8de4c7f0c8a15674bada194f971298a87602b276732494dc928c31d1b3dd2f1eb74a795b75950cd7dd3aa01
311	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x606089c1ec9ee5ea5cd8c2dee10c638cbbc010852c72b5b08c154a4c4403ae5d84c1a211f0b6b23c639fc7e8d34bc384fd0252d5e717b7f105986db032faaf8c	\\x9a24ff194bc71cec094431fb22e1baeb6140be217411f3174441d062b37b92c1a4445e0e26d62f66225af3bec268e1aaccaf42049f8967434034e9fbff519c0b
325	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7341ae3401748704ddb25a3adb7e80b62b08c3e74599243f728b121405c0f714b377130a026f2ed3f21edcc72b8103e17ec8c06d278c54df8d154549c691f43e	\\xd32cd83ce42eb3835496a73401a8213c44331aea7b769b75b6cb714e653c67ef067f4244290d5755a95d010b5d574676502f3c6b6fc1b6697eada577797cd90e
339	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5664917b8269f985caf41d2c451693cc9cf7436d3662d4ad909be5c8d7500e18ada389deb5de21630e7e63fc2ee75b222d81b4d2a3a096ee098f045bd8d53da1	\\x87ae98f81f22cf45e021b94492efcbf3718801c9028e6df786bcdc6fa955405dfa145a38c11b49a9fa4ae658076b8dce5892cc03568d72522ef1efa25e009703
348	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6824eafde373af556d8627fba8b269d07238d1ccc42efc7d1de4562365921119e38c58f2a7b3d8abc6829cad9a04b205428bd858341055c76d741113498ef358	\\x9bc80597b0b54d693d5dd9ef2672a367e6d0fda9f372705256577aeb76fe0da94e3bf9c5a90e6749cfdb36b57279f48b49093a5334f887d26616b78f37c1480d
367	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x12cd61a3d9246d6032bb8cb608318eaf69f100a9559a5a98f7ee42d7e449b8e149314516c6ee52f4d614a8cefd6b98936ee3da4324f78cdf5b0b2e0875e6864e	\\x05cb7af95c0ecac964f8b9e48ae3df540abc04b67418c5750f448eabd6b1602370c26f06f117b80fb1006433afca2756730ac78ac39e21bd5d4be3be741c0f08
382	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x55adc5cf6361cc14d872512ffee922aa8b727c2820648744096d6bbdac91c3be2ab8794f5c7376899da9453ea6e1d241cd6f66bf1d5ba9929f450232451007eb	\\x73113d04059f70b303bb471ce401e878e6d5f4d40230672cc2c89aeba19a0fe8865f4814febaec613650f76b16bc633ffb6ab7cd90edb6bf66e310bd5b6f3506
159	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xac8a7ab78b097e0eb265a7bd36d4ffda271fa26b50a233b25064c8ee0b5fc6b7ebed56a18cd28769cd8aa2706507a8d1be5c4805ebbb920ce8547c49eedafae3	\\x0ba2c39b4f0d5c119e441facf3b72f19111c01c58fe3ac80407d7c16699eeeb9e50681330f3c0e441093f4ca5452c030af94da4cebd649e426c03fc9e87ea204
190	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd63212e94bf24fa3409be36cc809fea4640a967a749eb821a139fa13468d06b3dcb728dde799d6686ed044492eb345973621b709b6567ea9d8bfc36fee822646	\\xa4d19468aff8f71e7c16f1dfddf5e5c2d6ad313568e063b4e5d0bd4721bb6e49c717738e948a7bb6fb310e32a9a3b2b573693163c3f9d5324484fdc9581c090b
218	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xab0f71fffa7bf0d799d84934c5c9cc3ad15ae3a1651c7823191c8e40ece45f325cf5d8b5031771e69114e6110452cc89a2ae27199a9354cc59417e1070b9651b	\\x877922e12598513718d87cf35fe514281e92b545eca28d0d3a3f1aed863f1d10a73febf5e3b98e3d85e9c4c7f2bd85b545105a244921713549402f9a64019003
250	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x43216c92205cb2b6d7bae2b8649bde5c59378e518d93079d1f2d2b0c6803019c7e2c37c034fef891d5eaf8fbb1de32cce7a3fde468408d82c083d97a6cd1addc	\\xd031cc3c63f2ccd54f355154cc4effaf6d3e020ffdd17809a50715a5a6a5b12b5c5501c1238156b77bcf57d7c6ee93583b5a010ccd4914fce8305b2128f66409
289	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xee6e9f4bb8577465dd2f0856e8eef5543300b52daf64611dbec1833487e516ad4348caffaba25b80f77e24c9b29a6d212c129bdbb83b618b302c340b37a32e9e	\\x603042848333f41843868abf663570321fe6fc4015379debdba65e6adc2759041e7b420f2f655a744ef5cd03c84318d648aec364eb9e01ce3b66a1a336889b0f
334	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7129660ae587a2bf398c9d99df3fe0e4b7781cea6585e5a2064e7e5187ca7f8ecc9290d32356d2ea2572f1a6eff28c96d552a7ac635ca83e2934a6e137dd0f39	\\xd2c570acbd442f5f7c377259ae626d7e67c142d0712961a5354af5fb503fcc70ab2d7ebd8121384bf3049c8c2ea19cc4acede30f2d0aae85f9007cde5e401601
359	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x23c6254ddfff9c2bc43c0f707fc4d7d8359366506b74c4531f438ff3f7df05fa2924391ed60b28e98e31e71814ffaab2eb09caceb82bb109b527c0b392ff9156	\\x2fb31090ef644df8508445ad78a0fe50989a9bdd6b7850d98a45dc3b1c2ce09420043cd95127b87e1eb1649ca4b4abe35760a2963c223221d6401ffe0952e506
421	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2f86bb7479757c36bbfbc51791185077fa7f9884be193a41db2fab250aac0ed3ad9a55cc859e0d20c72a3cc0611d60526b4ce3e487ddb90ecf5f493355bfb1d5	\\xabe178b5d99d78dd3e3aecc0652fdb41d3d4472417ee99f540a463f39d6844aa04e75f640f7894c984d75c099da36b2a4975a2839dafe120a6a3a84cf8d1dd00
160	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd9d0567f296ff0b52174977b76c61219b58f943c31796efd60ac0b9ab8b2b8fe6cd96644b4dc66a5a589ecfab223b76bc535bf4ff386b5734d7b71b16c354f00	\\xe63b67a2e686688a8643867e5018d93c94e6ac4ca48fd46fac831e29a8db470eb86c0e69579043a6c6ecdc57f5416516652ee9490587e0b72c5d203468dda90f
178	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5aef3066cd1c1af749f4c685de40b30898ecb7dce703ba7a9264ca819a81efcb0b9e0db3be7fbdefba89e60646e64ff9f51c52e2b10e22b72b0e13fbb9babf01	\\x18f273a8774fbe6eb15123aaf4fff7c129b15165e2a7e32fd579c2bf501947a794213079a6d54c233d7aca12aa74f5790f185e14c680f16bf1c63cdc7bb45308
215	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xec160726442e57b4161f789f32a324c5d97aeb166b8adaa93f0ff81e32189b0156397540ae808dccd3c5b0e1c538b34ad2cb6478d7199896637cc098a73a58b1	\\x03aa79d80f7d13aeacae7e4a4462d3880946f66abaf5eab5d7c42fbb7aecec70fbb7bc33c1808707d14ccfe97eec506fa87441da0d276644a118e440ba599a02
263	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x916d735c94966037c4e48acd2ebb2f6b119bb70ad9f41f6f444a705bdd359facb999d0dfd4af16c64e09b4a2231c11c6d372b59f360785b77bc2754a89870f7c	\\x48de4297025b03d4620f5e1f8e846407efab52b427e6e174a52005fea17868eacc1ff1229680ac3600d9b0748939ddc349ffcf9de0aa1003236992cee467440f
288	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf2108a9acd0da7335c75fe4427f6f07e3a78b1d2b44def4fe573ad682ded7455ca0e58d9a717d92e008300249dfb366a3738b9b6a12bbd7acd6830d97998a2e9	\\x5c4ea4a2b9b07ca643b5c82ba8d757f9a63612cd4ecb5ead44aa11be14b6b8ec3de9a8667044331ca35f9097788af2c8ba3a206a04d191171e0b1d00daafd50d
302	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe1f0437052f8faa98a6a1c5bc9f77d73b42112adc6d3a9551404773edaef3442616e586407246cf1499112d93c7d0007dccd4be2b2910ded60e343a0562d32d8	\\xea6e0223f69ecd3cd4c7e0c98e4bd0df16536b14cd97473eb1c22ae139fb7a75281782b9a7a3c74586d9b0417442637892a4904d2ac515202351395f30ed8a07
317	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7497d4cd292acf351c5d66f1a506fd977f7a2668ba8cf060f58a16871de37b75f0d53aac6b52a51f1b77d9d0fa5e5ceb86266b31e2c7fdcab7944c7e16589127	\\xf6eabfb9a49aee81ac9376a818db6bcc93b60415d78354e97f43ff97aa5e80659193a7692b025be16290c34017cc480cadbe1901b3cfe2c4c7cc74e2a1f78e08
328	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe86224469a50adbd513797bfb0b3a16a85e26b2bbd052e4c4734e351efcb8d0766fa740c74c3a120f84c066905644625bb53c26bfe79d60b6e710d0961e916da	\\xc01a99b3a4efef1e7499434682eeb8d4ff86d975e10d3f3e9186ccca3f280443805d218c57231fc1bd496db2398d349e02609bb94b6bfbfc213a194ac7f1db04
393	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x772a6ea770d34d04ff4af50530a2266bcbd72a3e2756b42188a708e5421022a78d9a11983c4ed423fca06d93d5ba45379724b080e4b826b5210e5b8fd35bde72	\\x1913df94fcc9fdc1977437318f1dd01316fa8e62c6aefebcb2457ae5672eaba8d3593cf9241321e360d7acedc96ff307fc26d8b0e08dd66f98f680299a7c0b0c
161	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x512cfe865d3b9ef0eea643483617512dc377bbfb5497e970778e7876c55ab7b3d10207b6e0231e23e1ebc026b9048bc3865b8391a723c46a1a57879a8f117d68	\\x7815fce49a8e35b074deb9e3ddc69c4f5b8050c013059bfe0b6e6d4506391c264d15edb40cb3b3d2ff63b30911361c270a822e7d629950dc272137594bf1d70c
181	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x569b6e9f7710d360879ca726d4c8f07123ed6cf5d200b37b4d7eded15b52a7970c93ddfbad28b337048a1b4b9e3d83569a9f9b6d75126df5fd666386c5625bee	\\x7c8c31b98d5729b3865dd9c16731ba70fe18a8828a8b4aa170c779d63eade8081d80ed95ec1bc25cfc15e76f92cbc05e3e9d32c8c7c8a2ed7baa8ff5ea40750f
234	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc5fcdb72f1565718b9e0046fdf634076d857a0979f4626f495324aa5c6d3e5ef9ef9a4581c6b006d8eb402471d612c17740f5c45fd598772bab0f2419aee85c7	\\xde89643e2ca14a86c28821a5870d38503a1bbc1a7d202be4269b11ab3a1442b1c564234d26058f126729a7a107edfbaa225adda6894f6d6226695d2e739d9a0c
257	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1d5d6a28dcafd622d1f95feaaee26ed524db44cc266703fe74aca2d521e71a00a687eb7b8cbb78898720ebdb5232b37cf8539ef4cb8443aff56e1f87aff0a64e	\\xcc79911ae15aa483aee3ad8483d9a02c73758a86bdcb165cf43591e0be95105d0664c1106dbbee1ca9b299f30ab4efb592151beadeba5ae341fcecc9b912da02
295	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x41b1eeba24f35203f4f0b500a46069badf8f9dea0f2de4f0bcff745aa2d5d325a24457c2bbb9d3b4e26630542dd77473527e08533deed155c190cfb4397878be	\\x65c4dfd23625d02db0f3f97e69cddca76651e808f0753978e1bb0a416b62ab2753622b0737ce79714da15b09a6e49fd758f03ed87d944b92e71eb12305501f0c
326	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2263fbab7b7103670e576ef61def46185a6a3f858a2d6266d22cff42f5a18cf05065149bb9bd026d8c260491656a68980aa1f28ae321a25dcca205b9a1afd413	\\x101d107f8e969df0fef63d5efb17d5c6d71140348233fdbd8262783490730c819b7ace0284971f25b45c38273e6e78e86962b09c042ffee020874debfd5abd0c
373	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xac29703a2dc0a0746df509ce5b836c053ae977899b0c9f0f1b0df061bf3471b4a54520850d5c3680e46e6ed5e33a3168043d9995f223759a7adab796da0fde69	\\xe01506b0f4746bb3b3dac72962df9d7b6104fe5a3cf0916c291e6316cb90e9ffee8e56050d3768cd993644cc0fd19eb03baec6df5073ffc11a6f86f34170000b
385	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9d794bc6eabe0c879a2e878f6d69d54677ad9b48692ec886eda0d037092a1b85c34002e6e365aca0048edbe724f86300d4cd41d5634456f8b466e24458f65b81	\\x1e7c70ace486bb79ae6a1bf99e8fc8eff0cdffa926d4a92085206afd12a5caba65aa49bfd9f9c9faa278b5099fec05f18fdb9a5a017a9ce530fa7c4d292fc80f
162	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4549e5346143b92152a57d683060c4a4df03b26f6f239b3a5f244cf0dffca2d9c201fa5c10cc2e9e0c51dd6bfbe0a8ee903532d27b05ba0ac373233f091d7150	\\x3b29f584bf375b229882da3bd6595a816a780b6f6254e6fa451fd7e36d2c7cbaada69b09be3f04acdfc9ce891b74b78af6fbcb01a69d6a16242d25ef7a468702
191	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x15e4bb8f1f1eb5bab58254f765b10b76073807500ccad110eac92a98b2bee96a36c45e750b2975bdc2b4ee63bc83a1a722954a4d23b7a7b515647220b3de6b7b	\\x7c0c59fbc1d1b651f2f5f09de02a5651db3456975610a959faf8e46592d37a4fe3ab0719e06ecb948d22197018e7d6b60858b10137c1319eb41bf03107e7fb0e
217	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcca5e4d8722c79b7223b46a02bc7009de54cf0ea0226fb90b3a6f49fcf358f3b3f77a8b5ce245a77a01429a1af9f61eb2201d8e7a853dcafa83db3e12747c160	\\x143217f4c304ec2ea7e169108becc631519fec3a99cc94113dc24aabe0e904efe6df5bd3be9ed83582362db6861d2d77ea7308567fe40c7efe2c0607cbce5b03
248	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x02098ffab1d3a36e0a363c2c7a37fe296e35593211a99ce6a92b097c67ac9ae80035d9b0aa69c696b7eec2bc048dd26727b175d915f023bbeee8b3e199c534e3	\\xe6d695ae3f61d8e60fc93e0ee1320f9760b7c168458f6a4d23319c951fd84dde3eb3c9986f56e8c7f50f7e7eed3424ff64d7a185c4ff18dd6237992715709c03
277	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x063d8038a3391ff615a16df43680c8125cca2ea3cd8a77073cdc4a0d2c2ff322a827257cf097ae9de2dc059e89afcbfc273e7cf210f867c0db4694b33db66a91	\\xd27cc4f64bc80c44eb73c008bc1ed6776c0c44dad9c600de0b74316c4417b0aa1433cfd91c190ccb07722961aba58bb175f2881c1d8645e967b963d9cdf9d80a
305	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x01d31560ea14a6fcf2288739080682d0886564fc10044509c3b7ca36789f5735e8ec482665467e26c9356a3f4090ea67d9b3d7b5ecb4eb4d660d30eb2b6f160f	\\x044e6dfd55a46b773d11506a5a7560a8f11388afc29b9b817c447e4e94fc06bb22b6874fa33cd59d2839006118a7e63b6a65b70ccf43391697ce36201d904209
329	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcf031f489b7c9cfcded2de9bf4a821002c70e1e94f26c75b5897f5ba7786c6b671225db7ae2e1c71c96cfce1cbab37211d96976c18684aa337ed6f46e7ad133b	\\xd1462866ac296ef4a8a3b754edc3a726bbcf0919e8be8c96e0add8b5be762c980c00071b460f12b4cea6387b18e21ecfb64640f9a754a02d0598fd3c00dd3f04
345	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfe22706014a42c2a85f0964bd92fc0262692b8a36467fedd9fe4149eea61c7517976930a628bcaa904a5b565e734c5ce8c154aeeaf93dca7144c134bb01c955d	\\x13c879a84471c73414c568fb4833c5c965bee9424074ae881702ad5afed5acbe5d2006b4968fc5ecaf42db03429fae4613e7cb58823ac56e59ac5f7ecb84d609
363	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6e698d91184c9342e94cf49143314e7c8007ab1ec6bc4d10369acc27f409726e81deb1ed5eb175cd8d21cc6aec7f46c9a59a867c3bb389797839a9525390230a	\\xdb6f8ec74b07ebd0ce6816db68cf11fc9e45a8d366c1574fd8d02bdc0be4b18b06efd4622ae9b4701187f8d327fe20fbfd554b09232248776f3f23c78de5070e
391	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3254055e5462bddae25570034c5a12d3a8b5529c4747a406600e2df42f9aef648eeeb4228a3fa5f6fb26a4c378d586b8847601ef1b256bc16e4828c4a4fff368	\\xe80e4065340bcb41205b4b26b997eb369183011f31391aef4ed67284edd386b44b167b768774b88e3a5dbb3aa144da1594d0b68916a4f891659c34263dbd9b0b
163	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x636ba5f83124b62878d95cc4fe7db13f4054561f6c28209a8298c33f0ec8e280be7c26cf96aa7f2d28635eb705e589fc100d395da1ef205682094b1e4e622c4a	\\x1983c5d5e4fa15a9a422df15358f1d936535e1683d89afaf52331caf62e189dc3b90a06e67ab448165e1693294056f8264192978853f889710098ffecfba3d01
189	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x83d55e5f24e0eb8293be532bf100bd83c9dffa1c3a5df37c159c72a9bbe142a5d9a132cb97d88773e8ed5b1477dbb71e942f4ec817447902c1b3bccf1c3919a5	\\xbdf16b6841dd7b9b4390449b966267a35a29cb343c350af8696d729ae2b72ffab2064f872933e0ae4a041c28ddd24efddcc0b4704e1efae4ba63075a6a0b4b0d
211	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xa31a1576f5d7720d5bf4c121ce69980c364f62f02536f85662185aca1eebe6963c6ed520d829b3e656a1400d3c5f02b2543290339054ca14b0a363eaf34f3112	\\xee462630ba0de3db7846ee58126d4119a6d41b87d1ad9eb2bc82bc46b8a3900abb9bbe1f725cf0a2ca09b6e6d013ded712ba860606179bf59244b8d70718f200
271	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1ef385230ba5d389ef7c69bcb228db2c7b23f71bc0fdc99d059e1f9349bc947f5847147a9ee16de76cb770383e49de80e36770e2ad6e531c04b5aee5bb3a6dbc	\\x8b0fe4b3a8908671b1d18a7ad762c0c063c93064d07ecd23fced7a9600407184d945dc28fba6f11a0a906ba47d2173ccc9fa72ef82b1b1c1eaf80e7f7d09690f
298	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xabc5455a89c620324956a94839961ced20728d9565964d41cc6828050c5cde947e0486ad9f09bdb2347df8e3a75311ebf0b784963478a6928c6d83bfa8f98c4f	\\x8da21342a25c3c5bccf073f922996e3f0b690a2d533eba1e1c423fd423e6b07112c53d0ef4057db3705b77a2e2dd66ba2f4d8433ca6a53c6be4f15055e224b0f
300	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x69be477ff4990fc3e8dc6879aed99c86542d941c91f346fcabc3be542562adbd6ec5875fc2dc0a264b4184b053ec22e20243850baaf6c356a80eb3a12bc80e62	\\xe2c61f117368fda633a574b30ae7cded554ba0f1f2cdd38cf1058ddbffeaa43704d4b2adb2ec98e3aa8415601ebd8155d4b4b70de6e2cd897e8aefc4a1e44806
335	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x303464dfce8932942124821d95512fc74a7be73b85eb2b6a1c0de408f1a31a43efe01f90bdd9e8a013b378de77a1d9c0dd421e66b1a5068e0924fa17774405c7	\\xbbdea00e144f945f5d88be05d7940ac1331d00a14a578fa7330c52922bd2bffa31e2036b12ebcbcf292522b1b3db440849741940312e7268f12c774b2a49830a
365	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xe8c5832efe0f8ec9c1498e056eb9e2ebc023b6d31aa75339bb55964c847f4ec8562a7d56b9ea8a21eb603778fc4e8f556c92e002ec57c57d9c4b8189b90568bd	\\xf1748c268a18fbd88701e84b9ca70089e970cbd26abe36428e46d18873044a95ef9d971209bcf5deab9c292baab8205ddd63b9fc154b9c58e3b202093a3ae904
424	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xaf09e86decaaf4dea9be7d3a5e246dbac416b352715109c302298d927d7d5bf98175284e8cc772458c651da181a56034a47d11cfa04d444b5bdfffea3bfcde8b	\\x4ccbde44945a58c28c25e3f2d76caa198b65104ed6bcc8f17aff21d29d1431a492908a539bff739328cb9c830c6c50003a05f7e8e3e167a5877e401e793bca07
164	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2f85f286187072eda66423d0ade91f617860db0e3f3d682a823b3669dd9e3aefd949248bfa73e4a5fa650d62b45f66f944eb156b56c796a7db7f638ea305634e	\\xe8cdfc4bba91416be536e0b411f98d81fcfa8570488de0297334f84e5977e36f563f233343296489bbd98d0c81f2a8fb95f3d8af198135b3b87a1ef62a25230a
182	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5a21f3b22da9d83d74d848a9a7aa24d9a472697cc207430fc6cf04a01938b33d4c75bc6e84cce764abb469dfa7956a5708c0e3530b3f5aa83d1b8c2bf4411022	\\x86a1e6f4565d486e429fb2ef1cb12d3bf371018ff5533f3326a72b54f593cd15981fee3115fefda16219473f5f6e95371d25f38111544f9cf48757f94c399e04
209	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6606cd68e9162e5c7d5774ce342cbfe122bf2fa61c6bd04cdfbeef19398069d1a84156afd1f36bed8336c7a2b150e091e0361aaab0357f7046f626820a6360de	\\x5359e8c034a16dbc03db5d47de8e9fa71517161b7b54204b2191886fe3d429212a25b1fac9d5c9b2e02a5fcccfb190f090c99d0e749d7620e2f2d42b925df40c
251	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x21e8954efe07a71c814501a583d7c41192a98dfe1c99989d42712616b94078ea67ef398593da723c107d8c2104b52da6b6a87f7d912ff4362fde6f996279091f	\\x976de5b83cbe76eb83e2a2857772c61154a6002145b63e49d0eabb6436ca68d2a1d3a11e35eb17ae85c0df949e12ecdb600f46bc8f1f0aa6cdd811c60b946c0a
282	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd445443f816cf8e0aab489e8da73d8696d5160c651e3113605fa43e90105030a1ef68e4436e00230d956f5d481e4da7e70aea2fb6337cc206a9d05e95744f76a	\\x2de67c36aede1b561e2211b2e221749e2bd6bae91a5f28e7ba253ca31f985b82be6cc36c05fbbe149cf020931eb80e1c062112af408fdbb3038557995ae3a70f
316	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x58a2b3aa66d2bb33e230c20a64a3444523b3f6dfb86806316aa7ed66ffab6f7a12f9819f87c9773fecccf24fd955c574ba9492bcb4a27ad9024a91c82790e3d5	\\xfdeca71718556596fe432ce1e4dcfe9fe729a0e3e8e46b5f36323bb8cc496d366810cb2a5535e285a4b958a759b3e17d7e53059716166d163c1053dec65bb302
341	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x7b42da2d280fa170c9450fdd2f3db25112d531644819282aa36067bc1ba62661ccfed82f64b1cad0082ce6a06c0dcd55b67dbfeb0dcefd41385ff7507406dada	\\xe5f1bd2136d3f9671c91b7eb632e0cdd657a3e40c3ced6a5ab1232597407fda14b2fb837c2a42c9cbb2510c0d88136130b5933922e4d1c522d74648182fcd103
390	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd41e4b2a5d07933ec51cabb2f80c2245741c88fc515e3ebc990cadd550da92ab67a04004ec6eccce00d6ea766e9880856e8ecca67cf64996680b23cfae43ed22	\\x75e1ef76ff16178c5d486e63a2c30b15c427805a9b0df00a938d09f55914a42f7458553245792ee18529ac0b1b7a8b126c30365289de1f589578940fd43a4208
415	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbb0366612bf1374b54a256e5762c69f537bd4ccd59173abe7966291ecc93911070b0b5346d07d938ddc274fe94f18db357556d73d770f7f5187f4016b3aae996	\\x4db9268fecdf8223c921e67dca64ee56ff33bd0a3068eae87ba2aedd7f6ddd372f5e05897974fbf67d285f72b09a978c964e604851845c52c1399e9ff6162800
423	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd3edb87f100e01597efb8fe4b2528b1de769efe0e69a3263bdd50512ef6ab522a3c3d8e4a1f53183ef887d2968eaa7398034554a088d40c3a8ccb047c44e386e	\\xca93cfb7fd057b2cb2945bda93d159a368ff18be08f4feb1a82d96c902cac1cbc8656ed00166ff4f2215866f689df3b1282b12fd8ede44b77da084ba13620905
165	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1525e167625c9ee071012db5e74a7c112c995df2f74ec176b6ad2cdf3f39ee997436e406d48b03bfb95ede31466e74f4f3ea33fe434bc3bc9e5144d0a16f03b0	\\xad62eac82a27c171c64827edfeaad870ed8d7a56ab50845170107d0e7ef83165473a94b803709f702fad3fce5ba189d45dc4c9eeb57508d8ec691eb8dcacbb06
195	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x371e5b464bb14d1753c8f21dddcc4aa740a55fb24e7fc345f4d7157dacbcbe519ec994ab22829c5c4e19e1d8f865eb1a01bbe201c53b97d3bb50b934f2631edc	\\x3010a3f5c7d28c46ee1b6fd6338fc0603add1ec58f689051a81326a833a49df49c9f9d638eca2e6c4a2ea6474941ff4f868f5c424db23f46bf861bed6a916e0a
225	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8722ebc3927da3cdbe6a5c3d054f7d446fe2b3534db2cee19c18a36d9a6f94071c5b1772f29f31364db55b16d4a5bc3eab6bfbfb6e16c862040387774f8e9104	\\xd368e1e254bc7b7ca2f5c3f31f9dd15c19ac9a3d789e2d08853944aac25da38f4b24574e280a2002a8578aaf5201e4d594372e9000bdb3b9a00491ba2846a705
254	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x01ccf890d7002d3fbe3687a95527938dc95dad320363da351e7a08495c8397e34e2cde0c26c7c46d85c682da15f6eeea1bfc425332498d0d858035010418e643	\\x7f3962d6808eec9f1a323bd6fbf6d6fe156e434d3611d523871c0141c5d5b4011b5af8a670b9880f911204a93267b1908d763d8429f45a437e7348e4547f4202
299	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x848b3cb0e586023d4df7531a156699ff02f57918c4e0df70c9e85fa1a47f75d8d0b8a97b081a99564093de4753d077b20d812e5d5a433bc1f11593659bf01ede	\\x22cf9deb65196ec2d82474ea189805cdddcacb18246729bf7e44828f145a7620147c80bee8a5741669e6b51d30fefe324c3f7b8f3a98946c30f579321ffd640c
315	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9ff8c5ba768b5d0d7c08ec9e901e07fde538f53f7cdc4921027e173a65ce02c3f6f0d4e62d98fc16d9fb44a686fa9ad0495cc0b9db33fb58e27cf3c534bff247	\\xc409cd50938e8875da33a66a01566bbb0e762ada341c0d09715fd3a6099e3b0aec2e409abdb2c50e26e36b03cbef6a320205c9fee82935124cbf1d7012fa9901
336	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1f2757ef6637bf2d35e55fcd7546df96c1ef94450f3f9b97c9c6d8c81d5bc550cc53708fc10f0e242375d55a6ae5802f45e401c7a216d95f6cf83ec672ca2712	\\x8fc513585d3ace04e948881ba6c2ca239e1dd20286cb7e5333f76c966f8c9a29495ebc252d50b83b3b9f7fd2f0bfb83428b3931bfd428cb5cab30a0dd99cf602
369	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x986e73adb179ef153cebdcfd8b417cf13770fee0b67f4304ee8c5736621d466705b6a623117cbc024c0422e0836ca710c3ef2e27b6a792499eca6b85a5d4d9b7	\\xf1c61bce705690389a1eb2f581e23afeb733dad375cd3d1690690b35e504bb6b5581d59f24363bc95bbe80a1c6cdb55fdf79861a0f280d5b3a71683124e9500d
395	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x533dff9bc3cdebf1ad65afde43fff33433ed561e2cbcc604c12f8c344427c4821daef0f6c5abacf9c5a70bbd6c8877540d204523754dc378872789c4874f0b56	\\xe4cbf7b4953bbf7ad237870040dd8c3f1a1498074a7f8591d10b402edba5861672ff94e40882935673c7c01e930777520e79a91b00923212f9ac218f53af6b01
405	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4535cf37865664e58a886184bab3ff1f8b369c7bfc6f4d86ce415c002bd2b9cf6307df115c32165c479558c3841e6619772704dc91342049189bed4437d09d65	\\x8f3330723dc1b324aee3f50caea5c4161e040f995c8c10727b701f63b7a8ce006f4058d0bb2c1803a1d9c79964047f44a770ea26fbe24842499912a8100bdb0e
166	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x76bc3b7fa053429b94a9ad25d838622c7650d20a2d91d2a4b9fc5f83da4613f22186647acd31bbb5d126e84ee0ea179c3e662105d23a3cd608dea4bb9a887915	\\x774e38dcbf70604e7acbb726ad718dc37a464276d48740a16de42014307e8b9e28a35b984a33d8d6c55a0a75fa39643b7d918589789613bf6f131320208dd106
187	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x37ac02f233a12aa5a7cf45661df246054c4cc4a9443beaed0ff8ac013e1b118e4d506ef6528b8b65a72bafdeba091a6fb8286705517a54e2f2e471aa925e3969	\\x21760844873a92429abda8a6903418642c00d7ad0dbcaba591fb00e63044cd3bf2e25c608832c02ca8f2048bc403b625cb54910e7f4afb05539aeae3d9351409
232	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc8680859733f3ef40903b2f965e3d384e16865819c847602430928c921803ed4c5d5c9fcf2b7ceaa1d47e22b48402f40876ee0e0865cfc089877dbabd0d3db1c	\\x010fdcb6fe3d8ad9a65b66a96ac3e949a867248245c4c8cc2a894d0ef28c5f1837103d8547515dc5911bcd63600b69943cde75cbead51b6ab30fbe7115a39f0f
260	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x48e9dcc0fcad0c686171cd14cc28150fd39c7003805a700ed7a58b8f37e0311bf61a315a1466c0c36e40cbf14f5964050e46101068de473dacaaac35aa1f9d69	\\x6aee00a39c0081caa10bdb3cbb8b1230b75c87c49388312e2021f0259ed5581ad58c424c91d42bf1f530204385bc86523630686efc1c72f090ff046ebe7c8d05
297	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x0e28f66fb36b3fa264344444aebe5a1db41d9f58efe4247dc09618f19a12c88946b13903c8d9d1f867e8b9dc09fefd8f936e92dd4512060da68499906e3e4f11	\\x93705a76abc753126d4766317304b29469c526b930b3cc80f14b070f244768ebceebb2c7e17b16a030224ae870b6bd75b3c68d164b0745689545e5a625175a01
319	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1c0f00b8623128bded20efb1af26389d9b9e7d61df7663d385a1360ed735f921827b52fb36f595efe9d527d6b03eb4a908b6a423113fa2f14b0e2e283996011b	\\x14634252298b55a0e7b1756a87ba85716569a8d7b7b46aa6f3513655fa331a8256ba1dce3aee70d3cb13232d55d3bb93df5f9e452c61c9587232d83a1934a007
330	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x2df5b6fc61b48ee143991b70a16ee72ead1c74c520b289be3fe854fe04ebe58b294fa34f72a26458ab8fed05b2891e642c1613cb8d472e896d1d361f8537717e	\\x87be219c4abe3c2a4fa66a7400359858260c189caa8540bb9e39a2c84d5ada9ab4e8b5993188f3b09771962da6a54e984f3d88b86a7b5bc54456d39fc112d408
379	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd036f95764113469010d37a24cc725615da51161ed81cab45df2cbc7f4c2b367454c442bcc74e26ad6e82aa8c2ff7a7bcef0b9c7daca921134cb0322dd092965	\\xa144aebf181bf14e8f4fc475e38ccfdd29f3778d3a7c60949ad310340234d1a10f8bb0318ee6ce0cff2c6ac6c4af280e52629b643beadcf7eb079530e2b81c03
404	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x624899d4ccac932bf4a5d87858e447e21aeadcaa2208194cd93191ea8adb40a0e729c36acfc7375852c2012eff5ceee6f051fd09e99656a9a20c56110b949c81	\\xea3a0e77bf8d71478888046d80e295f78c427a291a440917ac57555ac110233a157668781f4e40b85d4c7cd9d1c8cda103758e6d85218a6d97f201e9e9ef3b00
167	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc98c80ae5df8403b185fb94120d00f362ef09a7aae9105d06d7ffab46beb62ede747b2b0af4b87f5f21b4b3ace7822a2c44d05df74ac7eaf860a8ea92ba47770	\\xa0865cbc7b6d0a9cecec1d1df70e2462bde7a4b5b8335b91fbe354d3e3e388c1de83303137bbd00276467a33ebc96656ee7657f997b7d778ee1ff4509f3f4e0a
180	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xdb818c7716a39a1be99fbd9dd566b5b6dd9101ec2530ae8a9585a8d88ae336b23309140fad6dba2ffc592afd6fc1a1c2f670c489d1f6bc389eddda3f408e2f01	\\x934001efa410c0205e5a72957aed205034dbdda2446746334f272dfcd5284a484ef6e5af3a0f08b803e14605d081e484f6fbb1d321477f9da2261093fe862e03
214	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4ee0334536093cf570e024da68b225a08ce80adc507b019dd697e79f8f4788db22442f031094dcb4aefea07df86adbb92c912cbaca15f4c5011b8cba2774efc4	\\x75ff90e81a23ab236a97e64aec34eb6d836dec7824f8041ca302d4bb8211b21516d2d5d6cd574bd721c84c15d1c304ac0dd4871fa043e422e49d71ac18de8e05
238	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xda6807709398f4e5471a40d02b7899e88bd3e708ae4c65fa182cc6c2fef8cc0f27298722f169d24f0e983bb67b421335e7de1235c4360ecffa1fc0d5dd1e85cf	\\xa113349ac09d813658a66864a9e1cdf3dee9ee5e5da4501efe8b6126f571a84b364f05d7ffc9ec97acf1ff9892925750ed6648803e8bd5328091b296682def0e
265	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3e59eea342d5b4b3330a7d1fc6db3b7266949640f01956e87c06d5e6528aa81a0d678d492997ab10426345bc7a3a7b7347bb4350bf715582e73e4b4b20ed5106	\\xaa3b4ab6e053904002248f2e53d64760d54c038ae1cb5e460f0638a6eaa5f50613d30304a9cdc095e5d9bf7ea052be3233d0e16851a547c36439393630e46e07
353	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xb9f0f644a9142c4006be5ac7c4c7911570e5e99454adca0a3807878b0615db5516e1dcda90de162bc0d5261184d6dfebdc5505479b1850050b4a11d3d688d018	\\xcb6ac2f8f88aecd78e16cc747d6eb48dc03e9c3ea424fdc7c1582b7ec310a87f26949751282eb1f14713baeb49913853c4843d7c1f2eb1b816a6ac91a2b7630f
384	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xcb312a3fac064d15df408cca22bdfe11e7bfefd569df85f8738fa641d34c0e7c68577dac752de7f7713d6057cfc8dac4f1da7a0d977501a8a4a1f5ff3550325b	\\x83ba8932be3c10f2cf8ae1b55a1203b2cbf3a536080b7df8a2035752cdf7f00899d63007426a0ca1e05a1d1d8e6fde3586e26f005aa7f2ffe178bfe8f92bc30f
396	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x1348a26bbcc1bafc18952b7474dd1545b3b5488a64290c945b8e24bb4671994a8a99fc0d15ca98388576692365fc4aa66d25f2bb26b87489b371c941eeec58a2	\\xed7a809808cc166958fca73e50ac1634367d92484b4f1a4520be842ce98705c641c2f864fcdf0eb2ce0bfc11132fe52303187f1a4b13781e6f706a523a5a6b09
409	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xf36aab7b47467c3620c68bb9fb3695630a6a8589ee1e4820665c0c80e48751793f1c4b7496c8ae075c39202ed7796700d371c1495d03a2f474c77bf8b9a0cbfa	\\x7491a1d7d681c867f7f466760a31ab449bcccc8d1b50ed918af504bfbe92dc4c5361504d39933175270eaccebd36625ff5963f9fb55c1b9fbc5fcd48e11f3c0a
41	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x3c4238e59a1058cea64375a7daf02b8c021fa7188fe5d8c6ce61d19b2e28130b6b8e736a8f6e1c5dc8ec2afa15809870d47fe95b3481677826c2e7a9d1b068e2	\\xe0bc4aebb9a2cc5b4410c7158291116357802ae5931f6d85076e3567b7adec470bb72e36ecd09bc7a44ab6731817c320442ac9d18b6467e6ce12790b6c1e480f
54	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xd8c9cfc92ad74d51822b1428b8090b52617bb78ca965ccf76b1c660479a4b1c11324e3cd0a0f23e81edc1a399c1918c869e1b054cb7e2ce074ac14ca61395c8f	\\x3cd057f8b9805870e91594dad3bef747a86ba1790336e3d9fc5d2c921179a706dd8a9e66e3949e6478bb00f51855443b52cf99296bea40c05d4e37a53facf302
67	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x5647679313951a0c68816c5b6950b18e8c95d535a5c2adbf0c0d633213d70c834d943d44e9dc6ae99226b1275cce78afa9e95a897dbc0818df2394340667b397	\\x4d9a411c9dd87faa58bb5e88ec9b1bd85241e1675943f030c8f420e429ce9d2dba35afb952b0b790aa19e4a492e27e21f1d7a548d768aa06ae934f4c8e5f4905
76	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc928f11347f2258538bae7f7fa1a7f592afa107665d64d43dd28a32ac4857b6b4e047b91263e08e10f4d93275b53b7d0c6a968f4aff0acae184df4edcf915ac3	\\xf21bca4f5ea890a2388b7452a0777e94dfbc590c5323df2b46f2228d447af21028c38be79711b91ebbe73ee2d7f4e7b406aa2ff967241f2325cb03399fcae80f
87	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x993d3fc102f3cb6483753b70e9227ff0ae72daa3cacd6586b505b7762239f9a3f2538140a7e562e2355bee38b63b40dcc9c0de0e4cc37e23fe97bfea14b9e5b4	\\xfdbf07e1ddd85557c81825ea0ce24d5623f0d293058896e8beb49cebd180f3e4ed6990309ee6fb85fc4d54da6209e218153b448480721524488f7bde903da007
100	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x620b83d47e5b3e08f69e74b3685f32901368d8eafe8c0bb5b53def66957581dd290eee77bfa002461565caa393c9ecd60a54135c0ed6a5f7bd8776ca81cc8db5	\\x08b76059958b9d6789b3980339594d5fda24a771b6364a43a491d6855760ee52726447ea5913b252db86ab673e7ef1a7071c7d5fcda10bac1dcb269caacdcd05
104	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x9d9151910f94757393cf27f19824b01c279cbecbc4f8c523f7235bc2a157b007edeec6d5d67926a19b131e8ffc77c2a820e844a48531736c1538e9c6ce89a76b	\\xe3752d3114241f84c90aadedcf5156cc3a4e229ae63e66425de494feefe7d628774ffe8200e71bf64c8373af5eba72c2396e7538fa6c077df372812d9441970b
111	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x8c8f729bea854a0338c6687625869f675f07d8a4c0f1294495a117d52c9e288a37e399fa2fd6c54e66122252c04ffdc5522ca8013efd6ddc4e32bb511e85c0ff	\\x3d2c4c1475854d5e4ff0802af2f389ccfdd4ebeeaab72158dc70e108193133e977b2ccf6c11e07e3cd97bbe23c6fb440b6b8500482d4e84cf98ad4424b343607
116	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x4a73a8d94a7a0e72677f398f61a052f00886b4f999cdbc1f594ed3e47abadb61fbbc6bddc6d8830c1b424032652dd558a503d10cacb6f6c23d16d08202d820fc	\\x849647a29620ecb68768a97c5f35531b6b662d9d8ffe5ec947ea47d6e0dbbf0bb6bbcda0f4da5ec93fa139a1a0c418f9e27c3b276868b9a1a0c3456f86ae8904
122	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x03eeb6874b51d9be77a2684666528ed6a56354d3fddc90f593476c4828f389d76fc73325569882d52b7e501d60cc8a164eace60a1ee9dd40eb71638fca6c1f73	\\x5a4812cce4cc00c550d3f8ede01325129a82532ce5c6fd1353a0c2a077ae053d68fdfed24e12849a3e5112e9b9b277509986154ab2afac7150d5f547c6ffb105
129	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xfcd3e05f9ef4765cb2ceacc476eae1e301e099594898e022e807493afba74216bee4112365aca60dafc033a0db503612bdd9ab8ef08c733d11fcc0690de99a49	\\x2f6b08d083285e93a8cf5269d63366f8899a580ec561d5807b486ba02ed3b73091b59720fcad6b834b09c5608fd1a98370c19e74f0f7176fae13441e19298c00
130	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x174b4d28ec32e81c404bb5663df9ae5627695235e600f54504ea10a4a143c3029494f704ee24ec8ab8c831c55d7172fd2bad27bd1897b9217fe1e3565aa40c25	\\x21bab42ae677e20629506c03fdf244a6506ca4b7537e967ace2358c59560aee407d5d882c31b99431ca9da9bae61151a0e609c4620acd58826d213b49bfce305
138	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x05e54c3af0731067f07958be769689ce73cee90a6d46e8a5c3bb11dee4e23c5434be1bb6767b8b7a53b2371eb39c4c68ffba710586efb2eddf320674c08f9d7e	\\x355d4a42299d39589a6c6767135b1d4d357c5b0ed840bdb903468035953c6e60d075cc5e23b43075e00812eea32bf54b00dc8607468cc2f88d3b1c6d9cf87b0b
174	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbf75919664798d75bb1c05ffcae3589d95aaf5390a90a8a34aa716b96d8db402c9b96e45d929ec470e3cdbfc54c5c3d94a88032c29e2f9b26515effc843e3f2e	\\xa7283c7f3caaace870f59fc80cbe4411e553c391ec0480c69c564d1d67398af5626c30c256f961037fb75e4513f00ca9a8d97f93af2bba4cbdb652c50ef9e508
208	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x67a572616c63ed8bb37f68d2e9d2f7532c90678c60e16f183123deb71b8ce2d897a77732c858e66843e6d5352bc65602d3ceb951354e5c5bab5a71ec8892ab27	\\x0f2bd5e962666e0956b403c33b5f6c71f0d225e8270c1310b70f935474a60e8f7c3e5948c1de7bcb49ecb508bd5a1f32dccb662374550d92ddf685615d203d0a
249	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xc318d5c64faba6594c8138890ed202aa66baae3a6885ce912f8601a36f170c757813c48f17d8459e26ff44838cdc0f72975198b0795d383d2233819d81ca504f	\\x50c3419e3fa82fd658722c27732982ef3e7de3862e4c0809f8d5e4637ae02b531ab4166dcd5f49c2a8692082a1a3fd7c086018e9bd5d0f6d79fd1d7b210e6d08
279	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\xbaa2f3d6654ac8527e510b8d983e58436584ee61b5da5433aeea2ed69d32d02e7442884975886902b9be4efdeb7683e7c73b14c1f59b87b33345fd3b2fc37107	\\xbd134fb23bbc9fddea0a791db24ca56556fc0b74827f5707b09a7e0184314818e4b8d49e1bb46a81040153461ec130a3ef6fff97941b8ac2d08486c39a4e180e
349	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x87dee77aa239db383b0852115bfd0011fa1b910c4e3aae8946ebbfaae509c5f4916197375f4e582439c79725b79f4293e2dd187bf2018755776b130499fdab67	\\xac0eae9e04dd98f39fb974312d1fe301ac10d5cdff3e5df496ac869e76961ba5af45ff7d9d63dee87b2861da11a65d6cd6b2977184164d2bf0c7eb3e7a9d850b
370	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x26dbee9722624563fabe8f70b3fac591de608e4be6e44e3aaeea8b2a9eaa5999ddcc9a93f6920df52f152a77cd902e3d19ac7e279365ce18fe5524d732ee1427	\\xb61c96d63bb2d250be0a9afb36ec331eecb4d91512b3afb72a533e1cf061be98593e441ea9f26b69258b2850b585f6f9806e4733d961e14b71d14c8b90831803
383	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	\\x6f34167d4df2b47a3713b73bc1c8de1def137b67897a8db6da1c72f3cdf1a844aa46ae58b0f7deaa15065d711931c47e0a435372ca15179dd1d4d6431a6adbcd	\\x143a360683e5efda9acac8225c9b21cbafc94a114274cd8ca74b83e40eb876e188ae0fa87a72c6a78f70b4a3aaaddce48e8b962b9b48bb882d782922822efc00
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
\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	1609929303000000	1617186903000000	1619606103000000	\\xb3233a3f9dd681a778ebcf207aced3cfec31bc93582db027c5222c8473f99f31	\\xfb7b4de10c0e939d26b9529469bafec16b2c4f90d0e5a0c1b55243952a8b417d7b0305b81a3a42cf564e6b71e6a35e383d1ee891700701665052288cea165204
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	http://localhost:8081/
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
1	\\xe279f654de59c745be0577be8d0e801d90771876faa202d135b80c13ad909482	TESTKUDOS Auditor	http://localhost:8083/	t	1609929309000000
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
1	pbkdf2_sha256$216000$zJYzKq8dr1KX$LVIb6GLJ0Oyr0384X3siWVwBYC17kFic402kS9MfrXY=	\N	f	Bank				f	t	2021-01-06 11:35:03.488622+01
3	pbkdf2_sha256$216000$xtX3u2ofEzoj$6bjgs108BoiCUslIzkq/qL9vxwiwgt2cKTdwnDS47HQ=	\N	f	Tor				f	t	2021-01-06 11:35:03.671165+01
4	pbkdf2_sha256$216000$optG8TBGiGM7$xrs5GHRm7RBW8/Upucp+Jrct4Q24ubRie+c7SRuV6IA=	\N	f	GNUnet				f	t	2021-01-06 11:35:03.757069+01
5	pbkdf2_sha256$216000$EbKMbCPRqVdo$4Aa8/oqx04H47bz8MIEcR6NptBLKeXiupuwwXnlVpV4=	\N	f	Taler				f	t	2021-01-06 11:35:03.840867+01
6	pbkdf2_sha256$216000$42tLZHsfgrqa$OHPETnhFgZ1yrFoRd6RwEG44hvTPDThWbR4gGRKOOUM=	\N	f	FSF				f	t	2021-01-06 11:35:03.925191+01
7	pbkdf2_sha256$216000$zCn2WjlPo5sH$cEAjq+9bOr7eJOSdXXDdAZlHk3gi9d2NtNuRKJkF2Cg=	\N	f	Tutorial				f	t	2021-01-06 11:35:04.008949+01
8	pbkdf2_sha256$216000$bXZqPaH5km9C$BQ7fRKLbWz9ePh+Iij/tXjplOxRhgJpA2zEDhjyMp8Q=	\N	f	Survey				f	t	2021-01-06 11:35:04.091307+01
9	pbkdf2_sha256$216000$oOeEfxc5aA86$ziJKRVzvQ/ixsTN4yojn135OVWhy6gIqpTN8UDty2PE=	\N	f	42				f	t	2021-01-06 11:35:04.545266+01
10	pbkdf2_sha256$216000$rMaUv0xWgJsQ$UOBpHyaOU8CGUACjKrcL2qGbs7xZIKdldbrsoJoF6vM=	\N	f	43				f	t	2021-01-06 11:35:04.996798+01
2	pbkdf2_sha256$216000$qrTnnBwdM4zu$IEx6Dtfx/LlXMMTs48ueR/nW3+8n+k3Z9bcGxVhvXCA=	\N	f	Exchange				f	t	2021-01-06 11:35:03.584623+01
11	pbkdf2_sha256$216000$JuVhkbcnUjU5$aDPkiAyWMQDzcVxYfcAa0VUuRWM5VjtnpKT+PGJ8AUw=	\N	f	testuser-Ym4ja1xv				f	t	2021-01-06 11:35:10.743794+01
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
1	\\x0d38a964c90917a5b21ff62fd314c1385054864c4f74f096a345ce8c096a3b0456048e975200b6637f9b9e3d6a822beb23bb4fc4eaa45a607ff9eb1638a576ee	\\x406e682415db48132e1588125469ca7e70ed5191a79145ec99f35364074fbd19cf50d616886513b416cab3591993279e37abd5db0b8240413ed43513f2190e0a
2	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x97c407dabaf4923a77c78c18201fb8ea7f7ed0fa97681b82aba155079dc718df040f11b12350c21a41597c2db7e4bd775cea2199dc475568a3b3fdb93e823e01
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x01ccf890d7002d3fbe3687a95527938dc95dad320363da351e7a08495c8397e34e2cde0c26c7c46d85c682da15f6eeea1bfc425332498d0d858035010418e643	\\x00800003e1c4e3887fc0cb8dbcea1dc086dfbe51c7ab3b0fd4bd354e31a618df639d5492a79cb0aad943abee62e58144c78e74fa15de7b097471250522eeab4d45b3cd092ea2a6dabf9c05703794b181a586f444132304eedaf5cf85d12f8aae476eb2c3178d3b8557d84d240c45a02cce782b9fb65d62e2e3b1e8e3cf3a87a0be12ebc7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x07c01b23ee37d9e54141cc83f3a630a9998d0bc8d11bb3ab154a2e7b4c62290dac0dfb3625b5e0a64e9a6873e1738e76750ffa2bca4f6080fcaf5343f1463d0b	1631691303000000	1632296103000000	1695368103000000	1789976103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	1
\\x030c28b289ff6a85ef15a69a352275c05220a01eda397907c23c482cd76416236071c73495f604b21a144b86f06817e99a74e924ed581a957bd43df1aab22b72	\\x008000039c437a965e1eabcfa0da1998b431e6e1bdc44843376c95cb1ca4b9488a215b63584e6989ec448daf4119c5e43b556bbb9ad84f573b299b8e25d1f8af63ba6294f3e5331146a5bcd40acdf7126e157a00df5911e60effc1d08e911c5113d0a0e9c39c5ae4182e7ef333f9373b1a7a77527af9c878abd0e1bf034a956768098ba9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa846749b6334a73fcb3a9855feb62953ceeabe0b9d86141ffb43acfec2295d5d3b556423227dabafb6a64ab52383ebaff4603ce76eab72981f857c7499b7150f	1614765303000000	1615370103000000	1678442103000000	1773050103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	2
\\x0cec2f25767f6b7be8cad16129e8a112ef6a22d1199d952f40b63df03e5ad210bda6024f3fb4d23477efb3cdbce53d31fc465c88de36c6e1ee6542c90cd10e21	\\x00800003b11ee0db836d4d52e8034f91799d51620a3e1e12df76d5c73ffca5685ae5bc805af3da2129de4cffbc3454f06837a8ab34415034906bb206f2e52d9219b5869d3e4131349612918f6f5f7ad2128dc54a2700d2e6e0998cc90204576173af8258e6f5e140fde6a4aa5c8a22e6c37479867c4cba1d71268a645a6e1b9066d9391d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x84c194952b8a93b94c2276ffa203989e262242dcec744fd16a3e8cac349edbc31b1703f26f2680920a16ae14c2123e9b5c3a4bf465879eec5737a69eedecf308	1635318303000000	1635923103000000	1698995103000000	1793603103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	3
\\x0d38a964c90917a5b21ff62fd314c1385054864c4f74f096a345ce8c096a3b0456048e975200b6637f9b9e3d6a822beb23bb4fc4eaa45a607ff9eb1638a576ee	\\x00800003a05f892aa9e7c41b35a2e7636ad9be8a5eff00a1156e0e707c39659d4c67dddcb6ebf6a074a9d6dd29f76a54749a6f10610ee07ca104eae1a230fe7bdc5c196fc00085c0d8c27a3faacaa8c00ba5d39e2e49a40af66ff4aaeb1667f01d2dfbb4187a432d56c0cbe3dc9b93f2f565e5f83a4c3254f6f14e0dbff2b45b2392ecf3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf8e7111a68f5fcb0116b3c3985779036c1d9df79feb514db1009618f34cba4c5aa4b59ff13ca82cb265d06aed72e92000fc18dc2a69d88b7073e0df5babc3705	1609929303000000	1610534103000000	1673606103000000	1768214103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	4
\\x0e28f66fb36b3fa264344444aebe5a1db41d9f58efe4247dc09618f19a12c88946b13903c8d9d1f867e8b9dc09fefd8f936e92dd4512060da68499906e3e4f11	\\x00800003d3217c68c224ee364dca3c676ef07677ae68ee02c240a467ab1b0b937c54e93e4c7435d5acbe773894dcee47a0eff0b7b4253db9c018c9171177833e65a2876749c6cc292f0eeb6fbb661f3f2ed678f35c961aa9d681f6ecaa0997555c39f2e766ee3de3627df988fcfa919edd64b20f20c9fb63cf4773bd06cba4a36822f9db010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2867622803585518249b907f78cd1d85eab30c21446cf34a30cca67b4756655fbd457cfc6bb46d0452ad400637b74dabb1fb38230b2d3bec8d648da24167200c	1637736303000000	1638341103000000	1701413103000000	1796021103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	5
\\x109487a3f26a6e0910862927b0e5f2e4f721689d7f41d5b05a2610406134c3650709ef2f35f49c39ef5bade7d6041b05f629ad97973c0e79a6759b68c1adc75f	\\x008000039edbf5c8277f395077f26e7ce6a25ea23883558ccabf324cfb9825d7ee92d511d28e2728e71f7d864c5349ed4df327df9e98ee1e5d1717b3bd7b296d781964d12369b6a385672170d0b57a297d0c1bce6e0bcc1a788f31a45e48e2332938ac1364962fdad508bb7468158371566fe6f0fa58710329df0b18300986c460562579010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x086960f0d441d4140e30afe8944cccd16aa60eadf794d6bd1042975c4adb08acc41f0a6b3a40039d6e69609d429cd4b42961ee5684586c06d24f5a8ec759f70d	1630482303000000	1631087103000000	1694159103000000	1788767103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	6
\\x1100379ed14de8d20762884b560836b03cbc9b0b2f45b9a939f6d6012fffcc6061d1fab4ccb1d0b7d552e1528cc8e7ddd3a7f092aab970f3c1a4ea565ca875be	\\x00800003e5df71b28eda2ff6cf41013023406b1e2e622fee1c56b0964ae802bdd5479a469c191278bd920ddc9ed21cb25207674067574d91ec2fe2f10abc7a2496561ee09628771beaa8ea18210730743d66707e8d016ba665f5208746fc3f7bf01738257cf52579a5172f5b97445592490a4840dbe67e77d25e482a852f6cc799cad379010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6423896a038c1754df5362ce03784b874c9476c150e9591bb458afdb7eac0888ecb8a6083ee06ffa927cf6b859294fbcbdc4cb9ed84adabb0ff6722b40f4670e	1614160803000000	1614765603000000	1677837603000000	1772445603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	7
\\x12880ce135de2983b1b998b2b17385208bd3dec39a704c177f9de7caf3749990a13f0fdd9e1ec59f36bd77a1ce74be1adfa4a4502debd067885e946bccad8183	\\x00800003cc745b469e414e3c6c8132b3bbb8a8a5f35447089d60c86fef2870bc6770482fd0af6500349322d6f3063ed1beca7f029a83aa0229e6cd7f5637ca4feb2ba939e17aa4e3c3bc8bfa472f59a45365f91a9397a53122cd65c6c1ae7f8a5f43f8d38cd3c3caf1e33d9d01c32199ec26fa370875d8ab4044e985188c28e26f40c389010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbcdfedf77d31bdfda0fc5bb23bd405641092ed427568c78ec0c83803428db1bc3c7b7f95cd0c657e455f8cabdd24dfb8aaa22e859a243c70e5d87ad7c424960f	1629877803000000	1630482603000000	1693554603000000	1788162603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	8
\\x1348a26bbcc1bafc18952b7474dd1545b3b5488a64290c945b8e24bb4671994a8a99fc0d15ca98388576692365fc4aa66d25f2bb26b87489b371c941eeec58a2	\\x00800003e7cb0587634016ba090e20580a0e5ca9806646f6e3f92aaa26640cf9541d95ecc7effef094438ddea24f36f54d1ea628671b27bbe599a0337924658ece01af7534726bb9a310de864ec78b7fda63ff4efc5bd607689e86973dd51268ef5ed1846b1a08ff7224c1316b530aeb59b7fea578408d19b377e5ea1c26810df3e1f871010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5acc705ba55b94a59b5435b6307b67d82ce4870736541a16e2b3d02e3b7cf4957b4173e70e767a4660efcbfc71a8e07b6758a542df36869689828f43d7ca1e0b	1638945303000000	1639550103000000	1702622103000000	1797230103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	9
\\x15e4bb8f1f1eb5bab58254f765b10b76073807500ccad110eac92a98b2bee96a36c45e750b2975bdc2b4ee63bc83a1a722954a4d23b7a7b515647220b3de6b7b	\\x00800003b79b4d8927a0294a3f39b78dd0c84d1b98e54f09330371878feefb7a2642d67922a4e78a4790a852110b670a50cbf21fa36b577a058e15afe1359c0ebba8af5c608a404094990863eb8a4fe9c31624728056761392192e2293853166769a82013321d302ba0a654f353c36a2b41c1c245bdc5f91a03884116f3bf83c1554870f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4b580e6ff9fa15c69e98e85b4a47596f0fc07f992d96e39f42bd9aea1c301e31de60f585882ce191ca8fe7383d559678d3440c749a3e71ab3ea37693e9e34d0d	1623228303000000	1623833103000000	1686905103000000	1781513103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x1884b440e596b03594f60191c5b23fb18fd3b3eb1827840e052f638b696b1ff1c511451ffd3482b1d7e86b725923d3ca90fc1c5e592128e43f25050496830a45	\\x00800003b9b5061b8e181ac40899c9d4e4e695ab2ecae8f274975e64b6b9bac34a0d43ff37b9e5d26d798a538fc2f2377e8576cccdea3fc2b2028a489828ca24f73947ff9fd93b3cd929d9a7e70ce42cdb7cb63af8949c1590639397160e246da0599123fed1facda0c8e44fa54eef0616157eb92ce8af48cafdf60fb246da3ddda54ccf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5ae8a32ca4cfa1cd9128a564db41978fe14514a3d2b705c26437670866b3456818893adf52e843de7bd8f9a7f0171df82ec49f93ef3b606b649096e2102b0606	1631086803000000	1631691603000000	1694763603000000	1789371603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	11
\\x1afc9c9a581424587b7cd9062b22309e8a11b2a119ccd41068f7f984d44d465191606c799fa65befd4376a4a49d6df567844c27683718694f311c2a1a1ecff2f	\\x00800003a8826332b45ac1253e5791656d666b8fcf3d5cada79ca4f20d86897c81200cf4e7cee89263eacf7f29746e6d886387129c60b16865e90e5c5eaeadd82425840b8ed9448f4dda976d1425e217b125f29327e002b96a155edc498101ad621222f9245991a1f3f4c00798176b95ca5f669916dc46498daa86349606ffa0c80d09a9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xba49dd686842fddb6d991d9a56e7eb92c3c955c0a6b85b3d6cd4e315777751398e42e537d2a007279d0db3cbb4964e27148c85bf7ccded44027a423511dd810a	1634713803000000	1635318603000000	1698390603000000	1792998603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	12
\\x1b90effb36a6706497484e25fef7384ad8074a801bed4c30aa8a722d1aa773dbb6d0b16160d24feedf89a11dc5b5a7bc446c1f79eb4a7976994492bb14be20dd	\\x00800003c65c3c94606b90a466c0aff8301bb4f946a4344a52e1a3054768c67b8572196e7f4b1d885613ec7be80220e34db951e6909f1c4c16c6ebc082545f6d7aada88ce791330e9fc9bc39f479ba7a860afee8d7db407341f5f75c81fd71f8d616016e54d2d82e6d7ce65493cc869d2681677f67ec69ce2a4f0c85c3f5c1b6ec0cedad010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x36999bcc1111b8cdf3064279d9b497882940e2aaa7789f1e54cabbd18f0ead7cd652507bb4bb2ca1d55ef84af0dad61e5e1eb9a9832ba6ec05491433e1010d0c	1612951803000000	1613556603000000	1676628603000000	1771236603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	13
\\x1cc8f1d0157243a59e98e983883977f979fdd6ebc92702455f2eeba011e24894bbde274f9724a3e5497c5566dd01aff1b491471714bd26d2acf1604d39f70578	\\x00800003cbfd6531b71e1ad88a7e29f58ee0100e19bfb2ee5f807ec0d46fb7a396e2df0de0dec6200a3122359c91a7862f64e96430b5fbb284257538801e192f295ee8392b198fdb16899aec42d431afdfcc9ac6f58b9f7b9288303aa43563ef56a3203ca0f28e66483ab851810cb0f3d400b741f45a169a9ef992a38b5d1f74eb891857010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x629c69f4e1983fd45f016d68444dbc4d81a1ff35b25eb2562c63da33eb6417538360096ac25fbcadab46a767b33b99e23e91bdef6282fe3fa87c9e93446b1308	1631086803000000	1631691603000000	1694763603000000	1789371603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	14
\\x1f7c100c6696ced06347e3ed21fc694f33151315daa79530cc8a88eaf4768af1f85f92f004051ced196e3d11e930f7d3528431545dd594fee92c6617f084fcca	\\x00800003da20649c3959ba8599840bcad4346d1276413aece3b63ec315fc8c30017b94735ce1ad85176ce4218a8ea002d5d19dfae951d038c3f9e8e0ecf003ec8416b3b050379f04235fcc486e66511958e84dd449ac9897fef54e36ab490eca417f83a89fb1f9f4b1db07cde3d93d0e30a8becbd1a7bd4870de4096f0c84d337a548e0f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf43d2c50e285e499f6fb9847b9e8f4f0713ed5be4ba7ab475affc16d9f19bd08358510467c78e6a8a56a271df1e2cce2c9d45e48c40fdfe08db24e69b00a7804	1611138303000000	1611743103000000	1674815103000000	1769423103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x20d04a955110d5e3def1ea74438b17cfbbcc98af373858534b0b3a7e1e290879a7340fd91155dd1519d625e7a27314f05503f7af190d1bd3c5e6689236a047a5	\\x00800003a24e312cbb099e917d7d3bc1aa1f3f7ce7f8d6e890fec003261c77ac9d59bf11021891fc8de200a4e2ed3c04f4ed3e11e0d56fc36b4a93d87602bdf8cc3c428523ca886dab4768547103086409b8ebeef75530b737fea8b83cf91013f3e63245d15035792dabb3fb5e44a9d608826c9fa8ec9407c717e8f9e13cde19352c6b99010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb2f3e60d13313db83913e11ce0194d1da5646ca94dd39bdb5b047435e14751fa480740533b6980ac719051b773545087b29b0389cbf0161f93d7bdf625d2b605	1624437303000000	1625042103000000	1688114103000000	1782722103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	16
\\x21e8954efe07a71c814501a583d7c41192a98dfe1c99989d42712616b94078ea67ef398593da723c107d8c2104b52da6b6a87f7d912ff4362fde6f996279091f	\\x00800003b1120522146f2b0ec82705206f49d93b9f887255fd4ff1728c48548ed182ea1ecfb750f5300ce2f4a97d24fa4d9762577415f41159b6b04a3f21c6c34cf8f2f6c4c127bf601c28c98439c2746f005403d2ac2541e74194241e79e918ed51f5fc41dbd65ee978cad028fd9f553b3abc987eabd1c972abf6b984ee0267a99fd705010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0c689c3faf9ac218c4d35d52a9e17ad647e3b6fa62e789b2413fafb415f9b708ac982bd8dd4a3cca157f6fbfc3d78f0af7625330acab5c343758bd346986f605	1628668803000000	1629273603000000	1692345603000000	1786953603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	17
\\x23f42ff9325a392611ff73eac50d6bc00bc63bd96bf78660d7e73a661deaf979247c5a9ccd5288b9140e73a63560fcd5ca9063a930d069a86387b3d4a3a73778	\\x00800003aa2160a5c781187cd01c9870bb5b0891c3ce6afda3712761a7b7c6a2ab6579a86e8536ba59a475b32019d826c64ea688d89be75aa0c591bb6656d733eb7e013e8d33dd0092df2c1be32ea43a18afc568745a1742eae917b3047ce4258ed4dc3d2804494bd3f073975c604d77c7ece5acd5e6b227d8dcd7aac7005d64dc776b4f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x023f1fb33256cc3607dd520b8c275f081a0a23784aa2f3dc460babf24b4e498ef1a42a9f546dddade60322b8e336d215bc82fab2a0b4d473a4079c523de3d202	1619601303000000	1620206103000000	1683278103000000	1777886103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x26504af7ed5cfc049bc1fda0de48e38c0e0017f8cc4eb7267cb9abfbb320f5e037cdc5ef9b0a74648e27a560f02f9ced4e3074372d687884b588566af0fb2e4a	\\x00800003e44fc6313ead7454633c9df95953028fe2e895fa760bee4c7324ddff8547a44bbad6eb4b7e6d6ee9c6d142653046b5686585eb2d853d06ec5b9a1fb4a7f277ea8fdaa77df53e6c19201d101ad2bfca322eecca3cb763407e5c6c5576ca5260b005680626cd3e99fd41099ec9aa83b44972ebb1f2c211dc74701ca7c18a85fa41010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x906335edf37e374e8b6d33587b9f8afaf533e181c0f088eac2ef7f2f0681d11c9a91c726dfeebc57ee92a8c094848c5e092b5c1843a253f9ec78b1c82ed3500a	1618996803000000	1619601603000000	1682673603000000	1777281603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	19
\\x2d3438b9cf167073f4c01e4363d5250cd2da6e9c730648e1800c9a6eb6723c26f2553ba31f72c2840e01c510fb5edc54f6173e0d7268464d48cd02c381bb6000	\\x00800003eb20bfb6e0b9289c5a799f06737b7b41ac77a87a139bd9622995e521112654bbd26cfedec5dc1ae1519c82ea6fad30054bc9e80ef69ae790f13259f488136c88cafb4a9810e3e4467cdb4480fd18414eac454da626e0a09525572abf79a37b89d2250d4d8cbf25229d2c8ad3b75428ee454fb7870c07904c0e3be015ef43ea27010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x21b3cc654b16b1919e91804922a58999d0d2a51f509f5dbaba40bc42b43bd27990cf2923c98f2e9394b6ddf4339f1f1e962ebb0b04deb7a32f063970786e0d0c	1627459803000000	1628064603000000	1691136603000000	1785744603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	20
\\x2f707d6cea7bd4671a095a8af431c7276db88c4ab1af7d6ff3ccfdab8aa65816a2c30a240d3e959c6280c1f392675fb6644caaa97ba7bbb773e31f7b9831270e	\\x00800003d17b8c7f4cf1a72180283c202262f9274245ea2baad8886dd5166f248d398cd9d52762ed62d379568a117eb34390945374ed55062a0ec2fd7b44241a1835a8e19d852e32a2f10af5517f0abee96de69e2a481a56b3109c0a0825924713d237e0e9f7e3ff3800ee4955ed45387e77c15bae8346180e055761f951215e244d6a0b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9b1cdb0d6bf538af4d48b84cba79568373e9fcef59c79272923d29275b36bb263c1e9c894e3f22bf4317fc391824b86338ffc57a5dde02e32f5370af005d620b	1633504803000000	1634109603000000	1697181603000000	1791789603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	21
\\x30088023011cab513f1f96895d4c5f461b6014f3f9f3fcb4cf1fde7377ef9e29377e8677a963c38fd367b50fa9e62558deb472ec8100e97cd3fb51cee7f5b654	\\x00800003bc30d2d48c5a23c9333650340d2d3f4dc64fd1f51d9e3679a85a0ff2ff555e7e024b95db0e4a0cd19be90043415a3451d0833ad4990cf5fab532362cd835e987c8133802dbb33f4c1543d22f89c6bf3fbfbf84343840155f8dac11c9cc6705e9ca11ef1c778bdb8a7dee49db45a1f540e5ae3b412f680698445b297b803a16e3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9c596fa4d3a853c4a010642531805e3b1d8d6874299fb69e2f23312a0f4d9eef2fab5dddabbaf60ab238ca8a352c03ed69538e9bfd5560608bc0855e2ce0460c	1635922803000000	1636527603000000	1699599603000000	1794207603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	22
\\x303464dfce8932942124821d95512fc74a7be73b85eb2b6a1c0de408f1a31a43efe01f90bdd9e8a013b378de77a1d9c0dd421e66b1a5068e0924fa17774405c7	\\x00800003f89f74b72fb70af09a05ba338eb88968b228b5b2c03e248d4f3c2dabbf14c75c9b293cebd9429622e7e6356a6212229490972283c0816e12a4ec12c20a0fbabafa8003796ce2a116332b9b40b1658fb9da30005efe8244e9532754a75ab5df149af75714a73ba4e32824d0ab5a5be2f7b1daf5d0096adda8e48f6762f1e49739010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x067df4443ddabf4a2e25fb866383857af402ac176c99779b2857366f061dd21f48a8a6aca1ffd5de88f4602afb844b16b95128cf27ddb2c56eac32ce509a2702	1632295803000000	1632900603000000	1695972603000000	1790580603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	23
\\x3204d891c7586a18b08ad502999219f47a72a7b7f6ad5a729c27d126c2387489c156828df03d2ad0097746d2029c60ca00c4b9037064c696f48b2521c1495b66	\\x00800003eabb44705bb85270668154c7e544313f97cf80f5d0c1fc6cda1fb3c7521d190feff7cf09cbd5305e4f6d91a5bf2747a654e3199667659764f25d8d80fc3bdd039e31aa96b5c9febb14d0ea2721c8cea3fd10cb5823df210eb40a3e5814f5b8c97ccc34e6b9e2fa4b5de42550c264a933ae321082b22e2698da4bd07144c606ef010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x22ee87cbb903a2ebfaa2ad0acc960ae2569a060a7bbe383798cbae2fa4193bb8838523aad7aceba3e0610c24b1d754ca685fffcb63e610ecdf0fac75de613a0b	1625041803000000	1625646603000000	1688718603000000	1783326603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	24
\\x3254055e5462bddae25570034c5a12d3a8b5529c4747a406600e2df42f9aef648eeeb4228a3fa5f6fb26a4c378d586b8847601ef1b256bc16e4828c4a4fff368	\\x00800003f430b4188cf00fc1a2e6d08ea56838144b8eaf09747c9a9e887cf87591734f29a735d9290be945f016694c16af2e52cb8cc9883f9852720cb5163327636a686ad829c5a14602fb7172245088f9c5612a5451ae34137dbd8d5358a70ee343bbe79afd487f25c7054b47a2095effd8785f3d8da64a8f7995abc047c82fccbe36d3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x823749585a85842aa561ba0a2aa4e34ee5348e093be6aec987d52bf013df8bd9c7eb3e1e5d676f153e830577e2414ca82a56870f1a7b8348c61adc63a9d17001	1638340803000000	1638945603000000	1702017603000000	1796625603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	25
\\x33f44628497a9f5ce0b0c8ccac6c1b1ae9344294f162ee943ca7821818c0fbb719f3c68b0135987caab047c405e6ed318f2de18e7f358aa7b4ff4f0acf13ca81	\\x00800003c45797247b325a0d895e8f7b488ed8e393b200d0cd21b2ed884f479424f59e7fcb5b05cfd48b32d76d389cb497956e908c31e0fb62c42e0dfed5e48943862076a7f868fe27ec2b7ead78a105a95bf5e3807663c18eb0d4bc75e8ea33ae85603c23180b63299d7cff2268fa10d5bdf2f7d33287d4409e7ff2c170c6111f39578f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x675cc2dcf6725b93aa7365530e1988328bbe0b3f276e0464578e32960820cf022567c74f4d602caf32fdd738402e892dc4364d11addfbbf673eed9e1decae602	1635922803000000	1636527603000000	1699599603000000	1794207603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	26
\\x33ec95fba7bae19aaec2dca25eabddbdf7d2a992435d810d4c338b29e52861dec2c5dfb17923f196ee19d2f83bf4fbee0aa5fd0b7583e0c79fa84e6c672875ef	\\x00800003d5cf2341d9b0fc4787d56f28ca90a6eda32405f14571e09da665f5766c188a45697cf44330db64cf3f91fb4c6ebaf7d51e90d369d116c19a6b86b7d40d2d4e37fe6b387ceb67b247d539e95ed53839be952bc6ca5e0a490d438bd578d4f8ec9434192d1c332328405d49e9e0db677b80545e17ba2c0325b4d57c60ec39c44827010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe3024d4d3cb02a4393f56efbcb21feb8334b6fa334c68c7487e4d13b00231e29f3e1961b909770942b586883ed083428d1efebd641b331731f2f754eaa11f808	1615974303000000	1616579103000000	1679651103000000	1774259103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	27
\\x34a82c9cc6513aa420c95bd105b2fc55b5421ced2b5d6eed345a6091456efd22898ddd26130c1d9399fd3272d319819ef9328d7547a8458bedbf9fd1ca69f19d	\\x008000039cfb15c35918b4a5bc00d42764225efe7ae1bcecbc16ba09e492eea0ef342b47c5428f2230792187cfed25d849cd4a43c80c97a6c7695ccdd93a18b4bf1abc017030e56fd11282fd638fc286b2d61dc77d23bbe23e8afc97e91d43ba2adeead387656a489c2fda5672f9ed6b8ba94dd068dbff4c2a4d065479a5162c73b2ec9f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x00339276b072366f2acb05e47c1fee4ff96310827a9ff8ba26c0f001a08395fe1838e07c632f26b0231109d44696edd138578cb5bc17c57ba526cde22e6bdb0e	1617787803000000	1618392603000000	1681464603000000	1776072603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	28
\\x36403f931b3ff0dae6939df990d7bf0a1bf62de49a3a1b48d53c22554aff3c508940d46166a8e53751f864960d00c789cfeee8b73999a4d6fee650fffa889450	\\x00800003daca29bca741fa546990b0e82b5746dbd7b95fccfeb4f80759d7d7cfd366f28d7452054009cff47f8e4b7bf09fb029681771c11b7767becb3392fc09b75b25c8e47ecb558acbe2713d2090f4207c5e18f4ba9ead1ac4c4b2b97023271e5fd440d71886418e3eb3ab7dddebd3eaa65b985c4a789806b59c8d6b91ed540a194513010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x27c468c4f1d4d85cf930d74e47f04c50c8029a784c0d17c574da2b3f14bcd329d705d086a8077895e973cd8b236ab0a5be0c5040a5e5922212b1596a5adaef09	1635922803000000	1636527603000000	1699599603000000	1794207603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	29
\\x37ac02f233a12aa5a7cf45661df246054c4cc4a9443beaed0ff8ac013e1b118e4d506ef6528b8b65a72bafdeba091a6fb8286705517a54e2f2e471aa925e3969	\\x00800003d9f8f6b1dfb6b7152bec9714d4f8b53c0a2b98aca91ecfd70a44ccde589d543ddcc3cf17b8688226337888ec9f24f04bbeb66c182389ea6f3ba8b2d11c072c475fdf71dcfc503ed588038a09e67df676879b5ef3cc048cc166f52e1d962c310071c27da1e19b00b606f4c963ac7a6b5d9008622cb04669c713987d50714bc301010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcca3909e0ee969847247c8fd09ce86aecb9596b223e6c9b052d8e261c03fa03727020f4b28f7f2180732419678365960c295d04e71506f54cb1d9e904eca230e	1623228303000000	1623833103000000	1686905103000000	1781513103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	30
\\x3a18bfd05830fa47163f42302c776c12bf66cbd354846e5e8420271f58ad8e1390539cc25209bf2d550d2af78135445bcc48844d88759465c145d5f8924bc1c8	\\x00800003c5e3b12d36035593e19942152c4c172d1ea6d0f5f323a6f5ac35eb17126a6defe1aa1124484fb2a5ff1144e7a037d99dac657d3fbe2b56f35975f67accb5789826aa53fd9195f8a348f108099e3a015c0e33f20492374fa140c34c4f1fe8c99967c1d5e934629ed52d6b87d25f71a065ed85b2c906767053a1b395460e11dd9b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x10c832eb39734a887c95f739bbac7826e5308ae8417e2092b699048c0a7f2f87e371e14e18ed56782d0f6638b29304b8928117a6d9b62d09098b88a3aed18905	1632900303000000	1633505103000000	1696577103000000	1791185103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	31
\\x3c54107f632915ace0bd17f1b58d6ba495d16f93f7d9a51ea57ffb2ef4979deb50c1ea7303db53972a552226c09a66bc2a36fa73564701e13037d36cca710dd9	\\x00800003a59f440665ad6bd47583d320b2a075e466b0644765e4a04c91d2b97e7a29df874e9395a66b5ccb8234374aacff362c62c2ca36d2e2ce0af231e3b6303027fb5c2fd367b8ca08a5de4e62ea54f0c413b9a8c8c0e9372f22c204aa51ca2a5e07f640b51f5f871e55768a47c450516d204e2335faec68ce95307021081cd1a19993010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2af7b6a03c009cf94d68318ac9f7ce453691635028928a6ec0a7e210df95a6ece01996f556bbb3a71cad0a9bc69fc0f38710b2e784746679d300c00e3355b501	1623228303000000	1623833103000000	1686905103000000	1781513103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	32
\\x3ddc13dce5c238f968b3113a5d679fde9348fdd412c3bc2d033643cf0d208d1c3360944892d62d627bacbd3a538c277eadf1c3a3a722526eac582f4dd8a42147	\\x00800003def243d59265f260247803204c54acd4000397fa66e62d2460e93e2a11e8f1e37499a3891319cf319e69b60c935342b677df42535f3397479df52c3c72471c639b7a8e49a008e818af65c1f3e07424aef9296c962c61c18d79601da50c2d76f5da7e5000643e59df2747dabda95b5a35c5964bc3d769d7b5d41fc942f1b0c643010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x70e15e1ddca9e1f35ee7cf21356e89dd6171778f1a4259163c292444e9cd151dc6fbc54dc88cb82ba1fd4298db7cad3e78bdce4b3fed6e5ecbced9c7dbf9be08	1617183303000000	1617788103000000	1680860103000000	1775468103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	33
\\x44e469bfda88aa79a961972054d1b5b59e8c1dff7faee789ad8f1eddea4d98173a14d920b64356f17aa8652e3c371dfee99c20fed23d0532e6943b609d28736b	\\x00800003c14e53a6499d4a01318ce862dcfee7f392b756e83b77b1bbf291b1769a73cab8841672dd1fbe901fe06ca1e6b011c354cdef09b99ceae26e374206e583c085574da5552a1f8346e7a2d6b08643db03449c94551193fa3565ee3bdc53e60811bcc472c2ea3c155e6de262fd95dd35d55a30a97e00b0a66562f6dd781e1ef1dcc7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2bfca4e759d371ad5ebedcb94e075f627b919d84ed316c1050e95978a11a7eba9a7b08825c9e057911cf319b92c51aa018352b2a7cde48923c322f925b4a540d	1624437303000000	1625042103000000	1688114103000000	1782722103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x4564637e89a81505c6e8f0db22dd1341b85f1a8a06826f27dfe6f8f556b15a8450fe8d4b04df9ee2cee3d4012583e92507a1e2cd972314479d1e4eabe8ce3183	\\x00800003a080dc3a44830f24e00a991299f92ca608a43368e0f74e694dc684b45863b1a2dbc76fe37b8db9a42596b5d892c395b0c5eaeb844e7ec025d10b811d7d70c56e88bda99424ff8ee1880887d6adf4f466395f43992041f21538fd5f04f30696a5c82331c84ac73fcc41672f73f6f86e0ae00ae0cf35f94eb07028ab1364fcc707010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb8243a11d774db95aaf993f07b77883134a72c974c8e253600011c4b14c10011efac169d11700d34c0958f7531bd2d087b210da23310306b793542e57d75160f	1620810303000000	1621415103000000	1684487103000000	1779095103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	35
\\x4b34b1830fe4b9b7e98cc008d10717290b7976f1296890b78dd3bc5739124d78f5a02dbc68ade1157aac0578e48d34b0928247d90480e210a570474c947d91de	\\x008000039a56787b4c3c5f7b6e69188c02600d0a9ed75b4dbfb3a12f732e25fe5b561575c5d03a5740193092b918959ec91609870096f0b5d7ee596f7257d6fa1fae8a5c4e8288861774a84013be5fd1b4a0643974c1cbe40e10236c660015bdb1d5ce31eddc4b0026c1c1212c43191541578cb2af401138dac33a5bd3d75febbe093a5d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x49adc1fdec695650447aa03fdcd2bd07258a2a9c1ea2c52b3e82b09b9d1d81280676f7f39f8b386307efb9d13f5cbdb46491a82808943540c807ecef00b7ce07	1639549803000000	1640154603000000	1703226603000000	1797834603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	36
\\x4ee0334536093cf570e024da68b225a08ce80adc507b019dd697e79f8f4788db22442f031094dcb4aefea07df86adbb92c912cbaca15f4c5011b8cba2774efc4	\\x008000039e401ef9e46838cabfe7f336ce5ab5e13db282c3cdb55085e586bf65f12100168a2cfb64638e59126f10112695df9e6bef2430be25993257a20c212c9191c2873589c3a84c4e7574f94c637c2d5ffb47280ec127060b69c3a51a53bd18382d6e9112b6df8e6c66977714108fd507cbf68fc95a612e7c4a473889fee5e3592cd7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x91374ef00c483825e9153e83a297731f0b08cba5be763e9176faebc62d684d772f8fdac5b00c36b660d855fae7405ae3fb90b43c959de490c5a3318183ff1e0a	1626250803000000	1626855603000000	1689927603000000	1784535603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	37
\\x51180136f8364c98c9121165264204ff06dd3771e6dbe5ff161205a798ec4984c394c98cbfbb4a586f269c3f13c1e5185c8edbf58cdf985db609d1f42583f49f	\\x00800003c4f25453ac7fde525653d6a49486724e4b49a8fcb85e249733b3c377470697feb425cf16b01530aaa6bab66e67f1582f4167559912b9ca796b3640bddc33822e99fe2bbc2a5bae7f8cd48935c2927e1ad2864f40d2c58e68d235518be684a71638b34cf4c4b69f36b8d70fd21c0eea3d6f9f328889b7b87990a14e767ea974ed010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x20e68fd2a275ec188b9583074c3105833fff3725c235f0940b9dbd40ef6b83d2eb76ede7d5e896c651e72c167d66d357834592ab32c9496ef6193c060e47f20a	1632900303000000	1633505103000000	1696577103000000	1791185103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	38
\\x512cfe865d3b9ef0eea643483617512dc377bbfb5497e970778e7876c55ab7b3d10207b6e0231e23e1ebc026b9048bc3865b8391a723c46a1a57879a8f117d68	\\x00800003e59814f40be72445e194f4600d36c5faa5f0dd5a303138ed7d15bf73827c1697b069a58b9c51f52f96453e8ac9c889f5dc016e6bdc2c516b7db823a9ba59fef7106ebf4be4baaaa03c01a8ca847a6c5dfa6d3222a7b63dc0bf7d1d9e7345f7b4cbdf3a52fadd814e45964e9683b970fcd29f9e30483a0c3009989febab1bd385010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb72cad24e31c7db2f588bbdd39ffab78151fe739c9f211fe3d54592577c0ce844ce19438146ee0c1bbaaab444545111c20f20973a5822c97ddb96724d1abdf0a	1611742803000000	1612347603000000	1675419603000000	1770027603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	39
\\x5698084d85b082a326a8ffe71405d05b1b6c4dcafba7e84f0db997cddc6e0dc20105c8f9eefb1d8fc095a7aa22171aad362c9063173973335dd7cac6a878fa53	\\x00800003e1e237e9ce91ee3138399d08196cf929d76be48c05fab0ad66b3523e5293673e1d7b9df1774962830533cc382e163edcb6028ad5bc062bea13b948666d150b3f8c9c58e4787f396740ab07f092f06f080ecea3eadedd33edcdfaa64061737e4016f414eb580dcbc81936b39063c03f394a610b08f0073d03bff3a61cf82eb5ed010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc1d5742bbb8fe8d3dcbe3c120665577a29bb934a00368ecaef52644ac2ce239d2bd6195e1dd1f0bd26106b8a3f9dd4626ec646f97bc206c107242acf24ca070a	1634109303000000	1634714103000000	1697786103000000	1792394103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x5664917b8269f985caf41d2c451693cc9cf7436d3662d4ad909be5c8d7500e18ada389deb5de21630e7e63fc2ee75b222d81b4d2a3a096ee098f045bd8d53da1	\\x00800003dd1698ec3b429136fb7d75049eb2814e4a54c5867058b70bd298209ae0cddbf04af9f57896286bbbe8a7916d000e59f66b50e498fbe513cabbe7f76b6bb634a2785e7eb08d744d65d0fdfc4eba41d194eb0b406278eb2eaff17acf5483868e33649e90d2f8eea5b51c383aeb4f9b85773d868a31ee2a4284e51ff6c03318eb7d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8958e2950ffcd5ce4d66b2b7e6bac4af1f785d4e4ccf48124dfe2709b8da41b091d37f231d90093b0a103721667ee65299679e0a06be5f963c41c9095f62e70e	1632295803000000	1632900603000000	1695972603000000	1790580603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	41
\\x603c2b5a45c28ffec99ea5266a46a9a1daaf7a4afc48a932cd3af1f2d4624ed89f94f63b6d6f4362b0db4a2974c7f81d6fd2eaeca088f6e1ca77f4ef37b4e1e6	\\x00800003ea347a8c0271feecc026db050139af8264ad272addbebdb928789b700e3c301398895bceb99e54717e78bf5e2f4912f7357f5595cbbc4d180a4363b8d694061140a16f4899241ef70bc7b0a7f1a0d0cb2773237dd3b879d3e9df4a5fecad304f01bf28a02828558997c686bf09f746a9a4ace5792f87b323b2d1ba100f7e6551010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x79cea3f5e52fe57738e75c19747c3551b340c6e3012b7fc90eee1fa98333f5cebb9f597fbd5de7e31e0a2372359e466afb85151219ba37aba83c63c240eb330e	1640758803000000	1641363603000000	1704435603000000	1799043603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x606089c1ec9ee5ea5cd8c2dee10c638cbbc010852c72b5b08c154a4c4403ae5d84c1a211f0b6b23c639fc7e8d34bc384fd0252d5e717b7f105986db032faaf8c	\\x00800003caa2d4978182d10e3a1745e6a323e75e8a77cb907cfb9035da5fdba7b93d1d3270d98942a6e78f1e31bd98a3fe85491733c122e57fa559cdf54bd3127f8439ce2cc3072c3494b2a715b6674823f270a0c559842814c0b7097451eb7a99e4da32554eddd5234fe10c6d7f9148b5298cbfbbfcbddcab1169129669c7e9e97ac27b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x429da0329a93e1720b104da2001a92499e9d51263b468a7727f0e58da24e7143bb3bd5d1c078b6db683e03d091e3d0c9e3a22a1b19ed794328edd3627ca5e30c	1629273303000000	1629878103000000	1692950103000000	1787558103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	43
\\x619cfcaa0540abbc50ca162e1fc7a6a8c90d71d7fc7c14103e999e086d00bcaa93bb731a6dcadd06eabf8ffc11423773ff19ddfcf34cc1c785a21669b431c979	\\x00800003d98121e767eebf360b8e0d7d11a9ec0264bd0b79055bccd0a2f60ab69544f187e502766cda880a438fbd3fb8a6cc747c56aec27f20d1f5f3d41f9448dc8a83a1822810fd1f6cf21e3f269c0654f69a0e6cec8b184e533f81fadb3d9fb465671d51a0aebc232cd7dbbdd1ca1146a5225a22fc70dcdfbe971a1dbef4a7ef717a39010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb0e78e8fa21d97fbfeaa29ead1d954ac35b1e69612759129c3d9bf2fb15dbf6e2e84a87438e60ed88a8cd9da541f2997aab0fc9dc370df49c63568c9a11d8809	1612951803000000	1613556603000000	1676628603000000	1771236603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	44
\\x6248cee81b5ba5256327e8ddab9de5a335598e89579e725f72bb1a29354eff10f65f1e12e69c4946a2940aaf66e68c2bf9157c099e8aa290f08e91ea40b15e8c	\\x00800003a1b79c175e8a0b60b09cfbf880cdd2a30a04295f852763946e0c609078a40dfd5050974543ff66c34418c7e30b24c7da91fad9a81cab0ab16c5c85db36f4a973eea7c3a4beca395a9a3d54c4af81dbc8d306d1c6a065cc96115e2ccb900ef4b89e1772d293ad42c73de6d4cbd8e10bd33d57fd253a23accd51694277ec8d4af3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe3338c29883cab42e5e22c398671a3370e3f30a2bcdde058479cb5e0eaae1922d98fea67221bcac851c34e65a3e16ecee94abecd48428e3036abe5494131d609	1612347303000000	1612952103000000	1676024103000000	1770632103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	45
\\x624899d4ccac932bf4a5d87858e447e21aeadcaa2208194cd93191ea8adb40a0e729c36acfc7375852c2012eff5ceee6f051fd09e99656a9a20c56110b949c81	\\x00800003b14be30c4c6bfe28bd8bdccff4862df961c08b8ace2bb8afc05ef8da097514e0c6e2a474bd53d46ed8021476ddd8470dbc40c6d1d699b8677f46d3f2b303744e2ff8edf36dc57febbadd12c8569e540fabec32b55757e504330c697a9c49c972f35c200e7353ca295bd3fec2b62124a3079480cd38eac742feada8cb06d68b39010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0481f2aa82097c4daee1c009e4580cf9807119bd2fa9090b22585fb06e08b6055875c6babacb055b061272bc9e7573eacb3b162dc75422d88ea55f1194518905	1638945303000000	1639550103000000	1702622103000000	1797230103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	46
\\x62c03429fdfcc4ed2a8f5faf02292240afbb987ba7d6c9743a939c3d3c8073a0bbc2c4b0745ba74be4d4d358e69c20966c3f9df29d37294a08397be2a870bc58	\\x00800003a1b98dde2a1ece7477d0f52a16179417005266ea63a5c993efbc2be7d045742f927892f2fb73c41bdee18c5bf3390188e93592e4887fcf39b5e5c663ff86c81484ad126617dfee5ecc1be61b742265d818a374fb3e03725ea71a0bf175cd002c394a7ed149e5349f14f6f2f8c03a95d0fa8afd647395f0f9cefdec323f61f44b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x990256dc4a837f7158825246778488a62b7a25af3d81d69f61bef6d778ad41ac3f977f9336ab5076277f5a180831ca1804eb315a51709edb8ba85c3c3798d006	1622019303000000	1622624103000000	1685696103000000	1780304103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	47
\\x6824eafde373af556d8627fba8b269d07238d1ccc42efc7d1de4562365921119e38c58f2a7b3d8abc6829cad9a04b205428bd858341055c76d741113498ef358	\\x00800003a61dd6d7ae2986af80d08e822ca755b2f252419be4aa75b0e6c3425eeb44055fa4b26a08b03bb898fd5c883875fe7e60cb24b2bd5bf1eae9614c39f35a10a4cf31aec63f53d7d2b515eecfe4dead07032342dae7b94100bd7732e05bf4c2a7c3ade42104ae312e34467d11182e36bf5b00af5ebca943d91161183b750882c46b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x47e816e9ac2a0217f74dcee8f1f96cba8090fb4aa9bcb52f2a3e467616454fb3c7470150e50f525a5a97fcfd02b54665c6108b317bc2f5975fab65c919354008	1634109303000000	1634714103000000	1697786103000000	1792394103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	48
\\x6ac047fee05827c5c1bfd6e5b64468b9506660b3f3e9dba76527c35f12ac8d0c237d445519cade98cf32be4be9ed7301af9bf255fbc0c99f829126dfc1beed44	\\x00800003cc125bd10f9e7056be66fa02b9d5a892dd8cd78736cb09d2dcab41a07275bda6ed763fc7770f5ae37571f19fd8a00223feba1c58c4a0036e036ab18eb6d44cdcd57205079a81866f4d3327c4740df8b9f1eb381b792a03726ad77985148d0caf1635428a001bcd83c7406c62dffbc77d34b9de8b96228f684e9286110b785ad5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc7dd21171ce88cbc7c22c02904ac03e77e75b6ba5ec324223c6f27d731f1c01297ab48ce283f228ea5753cbaf8eeeb24a284ad0d205e7ee232fb2f03d08af603	1628064303000000	1628669103000000	1691741103000000	1786349103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	49
\\x6bcc8292d799dfbea62e7d65a3bb45ec4fca50d21fcf69be644be3774100f66545c626b53dc0e1c504603957b01f6e23553ba5f65d41d434d3ada712af128458	\\x00800003c9deeaba53e9efa96ab382f896ed8ee35e3c1c68def65495157c09cb0c5718c43c6b996201ecbd6195754798261b41c9f597f563df9a35e7da9c6b98e0acbe29cd4a8799bb87e691425439b282ec4174d920b31ca8a3e17e12b6d5d6c362e7e39ba9a8e84692ef19cf606b60c30f16977f78e12e4ce8483f145358edf6cfea1f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2d9029f0ffc126bd7fe343414f77d49c3828322bcde47c223f9dc35aa657a8fa6d71df6bab77edebe3843ec939da5e053866656dc327c5f89be490f67bfa140d	1615974303000000	1616579103000000	1679651103000000	1774259103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	50
\\x6d60278c44e1a8d1348938e62e0a5044b759d81ccff8e25e205b61a9fd8d5a07cbcee0c3605b94f1dfec958b42c464bc3c4c3be52f726ba958b5131e310c4d31	\\x00800003a8186a4f506097a7341d8b75ccfbbe706d1490ea5fefc1f9e633e2af7faa0ded49d31810119205cf23f12a97eaeb036ee997d4223ab02a1a81b00a284fe9ed76da2b619a0675bc0149c7dd3b7ad2a3e8a392a544191a8221501278be0f67285d6096e433285d17f22fa8960997d7491b423ebd8a702e32c0bc91b66de6245f95010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xaa83faf801b2b359ad1d48b9cf2d4c772de7d8c89be6c8a374524c66c03ce5710e38f7f6b7b036271eafacf38053a5b79cd0a4675055270301acb3e2399cfd07	1631086803000000	1631691603000000	1694763603000000	1789371603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	51
\\x6f34167d4df2b47a3713b73bc1c8de1def137b67897a8db6da1c72f3cdf1a844aa46ae58b0f7deaa15065d711931c47e0a435372ca15179dd1d4d6431a6adbcd	\\x00800003bf9142dbcb23ed537e2d963134ce3d6d29720cc5f102b07cd3851463a3fb533bffb2bad4bab3b48280df0be048a7836fc2a4ddb3f49c1bef6424961228148ca18aa586b067eda0d09221bf90a97b51318292278ccc7f9093f6bd929fe26da81e5f72280ffc74233804974ed67197aa89c17b5535e995ecf572827fb6c64a6c79010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x100834303bad3e6ab1596065a054190d69a30acaae9f8f13c1127b8d7f903ad2078ae23cd34088a023e93fed51aaf714eeb36a8eafb6080d24831e01840cc805	1637131803000000	1637736603000000	1700808603000000	1795416603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	52
\\x75bc468eb06f9dd15007a68566a039b8a11f4ce6326fde2f236034cafc97d8799a49a2ff605bf90de476fab40577b20f94509e1357825435bd794525cef35626	\\x00800003d2a73b6eeaddcf99922e03ef0e9a8124292c9b17946ad823a80f77831b4851507cdebdbab8cee01a8090e30514c57415209dbcf5f2f82e0a696b34f840e5fa5f5bd3e31347cdd2752562dd2f09f47076e336f51729641f013e4cffc67c2fec201ab2e86b5fbb4dfce4d1cdcf1e164485455f18f2b0a8bde9b8ec0cc310f475f1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2e45f5a0a4afd1ee2a02b08b125f71498bf66455b5e69d8db7404ff6e28e6bd1ca9e6c42715f5bc7c7f6ca930d49bd189e83e820683a8d3d8f4cff29e49afe03	1624437303000000	1625042103000000	1688114103000000	1782722103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	53
\\x76bc3b7fa053429b94a9ad25d838622c7650d20a2d91d2a4b9fc5f83da4613f22186647acd31bbb5d126e84ee0ea179c3e662105d23a3cd608dea4bb9a887915	\\x00800003a8e4b34ddb0419cbac1d958a5c9535d66a354cac044c0482bc96d87f47fd88bb0bef2815adea06fe7f17022934a0754d323bd0b2fa3b3688dc4f9900140aa47af4b11e157cc63e9b19a50b8c84f1cf5050e3c8a7f24f73624ef386c7c1455aadda0347465146bbf24ac386cc2a8441bae148b6f70b23c5e1fa264a3a914c2e0b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf18c189366f2e0980308e936a4caf325fcbf43a10bd139878efa9cf5c9730689b829846939782edc6b780973180962a0b4a93ef0ff32c512756bb481238b730b	1611742803000000	1612347603000000	1675419603000000	1770027603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	54
\\x7714741af34c46162de30ce5639ca13a1a7521b6153790452b27929d9101cd86f1b6291261c15d30ce39fcf9d42fbe2ac6c99bd4989f8dff16996075ae4410c8	\\x00800003df2399bb1ca95b509e272dfcadf81ea2045a36756d6dba12cca58eaf6215aded042a9497a4be7de6038da37c3f13c4987a4a468e926d7f267194e818ab9af70b7b15d3c02d387ef3b0a5a20598301097eadad2a52aee937d9eb9a3eca7bbdcc5d37786444ffd443fbd926d45f9f27d1d929fe70e3332e1fdadf98c22f48ae5d9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6091c73cf099d7d58d7b45e65620b3df87f857d0f82f9db326087b1b124993dd9d49823e5d533b89f6ad97b00dd8a15835398a8846152f4659e7c28443408702	1620810303000000	1621415103000000	1684487103000000	1779095103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	55
\\x788c58efb66ca98f6fae6e9855e56fa18ff609866cc60f8d4a7ba051a5a77d07cc76411d879b53b225b7f57c74e277e91cca7ff4b73eab77319a92c5add173b3	\\x008000039c0370c536522899e880730130b3f39c6bd9523bfd542de74b5931fae6e48a3791924db9f4e82827a8249f71f616830312d91aa9e97dccf493b2f4ca8ab4dcbcbf738d5cbf007e6379aa170fbea6c126cc2c65546cd3e3460a91eae895df4d3a8f339dfc1f95bc989ed6c1003dba7a9b5d1c5e9d14aad4340f6123d0d70c7535010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x33722078ea2fa9b0fecd00caac433bf5968c4b54fea6eb2191e5596f309a14f6562daa9f94968f28fbcc9d4baf55e4ce812a538597e651e61d503acf64bfb40f	1634109303000000	1634714103000000	1697786103000000	1792394103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	56
\\x7a48195b94fcf19e7183685789a4a23bfedb23cda9baa404118c15399967d84e32d349562305dd1b48f7852214ada4445561921d198b8e019ae09a88bc976146	\\x00800003c18701f035847e5547dbd03730b72952b5b23ed72f4b681aa2d6dd4ed6bebe210ef769eeea3cec19d54ba93fbea91988037ac5f4472ad6a692fd24cbfd199412b1cfd3fa3cb9322dfb23c5d11708566edaa9b33f8763654e1237980956c6f3f851f1f90e89565d29eaec00ba7081793055a38d0cce49b9895c98f6e063812609010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xde0fbd52b89bceabb1402db2b270ef323e1a5bc7882dfbac6840e187a80e8d6e679bbf6b0a56660d1b9453ded0deb7e65f80087bf03c3d2e21491c73ee437506	1612951803000000	1613556603000000	1676628603000000	1771236603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	57
\\x81b082d1428f02b549d1f359f33da8ee027d5914a78c36d77f1314b60afc10589f362c48fa57bc06e7e9872ffea4f6c153bddc319264540c8241f6ae28b93e9d	\\x00800003a43d04fc447ff7b20142c758e23a33865a4663313161b6b3c2a50b32aeff48fd1c783d1ecc05623e5042d98256df29c8daf60ae2c38358cd5225a90d31cd3180d647a88a7ceb2ea5c3268f5d34e87e19030d11c679da3bfcc7399d9ede1a72dbc2634e357781788a356f8a6a5e0d60115c53abbdb58a6ede041bdd23121e3821010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2d969c46e8be1cf1cca74465d0e8bbb428412f21b839206a1cbcffe192ec3c020ed0f44e5658068060d4c5ad8d03c32760a7a99a5d194cb3c92390c3eb2f2f09	1611138303000000	1611743103000000	1674815103000000	1769423103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	58
\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x00800003ce4d96aa098aa1dc1c1cbd542bd65813fbd1f1834cfef9f319885cd34899081de6ca86862405e1ecbe13d54a278ce1946a4dcd464f8f2857efdd634807cdae6cbda6c8b631475dddf057953c822e1b7a3a5605237c7f58845097244dd0f31fc25103f3b75409223c3d444bf7fafc4b4cbf70499ceed67596ba99d6b026c5b26b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc488100438a969d30f0b4ee109f6cb44a9a56c77d14806855f1950aea450f609db79f132480a00bb00661775136e08c4c98712c677268cca3fff55a609b1ac06	1610533803000000	1611138603000000	1674210603000000	1768818603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	59
\\x880cf478428499c5dfb16ad5d81923339b53a3a228da367b44589d2a2ede5849b171a598595da7b369a6a38896ce9ad329f6d5c6eab9a87b57b2f595301a58e2	\\x00800003e7211e929103278291ca51897c9f9d018f87919d2a68bca367cf5372f3b08b2a9355337c617eceab8559570dcd3bbde9e2d065b7542bd016a756cf9e67a7e6ab13d4cb94d60e42248c6f3aa89182d536088317c28a5c5ccdee45af773d5820a089d2db8e028b5d0d34b33b61ef65b55dbcf39e0ba4b9de9f31cac5a7c499545f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7de36bf66885f907c2afe6aeaf206e50c313ebc71b6b03493619ad2a4e2b328db7b933031033f1dd7982559c5d4853039529c41d2f834dae33108247bd389300	1640154303000000	1640759103000000	1703831103000000	1798439103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	60
\\x891483f5da7a23a242e4b85582b1a4187f3ca2f6999fd6ef9f4cd2596ff611d2f63d47dc215b5578869b4b44a5fcb1049bfd88567714388da5a072ea05fbdf47	\\x00800003bc574b427378d75de722f4f39237fb01e32cc896e70f9cd49cc378012a62950fb4475a3919c1e1180fee7ae32251104ee1b13015e65b21a073c9491edf41ad7fa1eba4fe33f97d6838e23bc95cb4aabcda4d773b41b26a5e0d7b1abc7ccde98a758199f8387d23ac663f1330933e30aa0c3905f8aca4c5543a87fc794022d423010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xeed8a21cd8b41f656afebf142d8c6e4bcde9c1ba06f5052a2949d7a16c0201b6cd9d161c02c617c6abac826bdbe71862c3a0e5812b4a46a0048270f2a87faf0d	1641363303000000	1641968103000000	1705040103000000	1799648103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	61
\\x8bd0ce44ff7c116cb59223c42e2ebe31e587614bebd7d652aa9a966565215a34e937a0a9b4438407c3164d2c76bacf33d7b7b9b3e6a3ab1bc566a1d38af4c302	\\x00800003a8e775578c67448b4c12978f230fc8ce40d32983c6c37002a1a820b7cdbb7f4aeea05a98b38501b5bb34aa2d2815960e26651f3a24243b3a35c6f09f052bb050fbc222eae74994e072e7993b0facd5a81c5923945c0d0e2ab10864d81a0c495aac63bea7be96d365db7b9f6a8ab189a249622063449d6f015101b29faa711fe1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x70f7a4b2e42238f166abdacdd0b2256c1386ce15fc60d6aa8fd3581e0f5237f5f135b548aeb622f4493d0cc5f787b7183aee2453fb17ad9f62b1917d5a850b0b	1634109303000000	1634714103000000	1697786103000000	1792394103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	62
\\x8eccf2683b1f0b7953cd4b99a78860b6d9793d95622d07f62db76f4cec3e3ea02ed75cae2a32a7a6bba0af2f3f915e99b88eb11cbac6b9278c07181c8d2ee723	\\x00800003d02a36742f514718d756848a039c1675f0e4441ee5a74b73cf17668c5898de1dc684d6cce47dc6ea6ccf570348218351840088006aedd77c48c85edbe0a9459b4f82d87984f290837b5aff2cf1f5b0aeaadc32846d2afc10a2266b99ab3b48f93582c5bc64744ce98929778d251c5cf98d0111a1ba850c7d3364059d246bc229010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5f5d53df9422033f5b76a42eac3f21760afbaf844437f99dbf0d339c663a6a3bc847dfe800d1a515b31f8b58af87f155fa2e6dac42db68d8e548365388acb604	1638945303000000	1639550103000000	1702622103000000	1797230103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x95b047232569f10691fe85c5dd3faf8fd331717e4ca847319f18e02b40a09c8dfb9d6d931f6c18887b9166bebd6c1f511dc461ee08302f38c265a1c8b121b0d4	\\x00800003ab769d70b358dec8aba7f08cc0690aef69db7bc38122049bbdbfa4088b2f77e1b2218d62371f29232738add490905226bc3f752dbea02b6489ab1c0ca6d18b33e50d390eaa8edd69557450b385fca99056ada3eef6db37027c5c8ea7c11e874851330c279db0e987990ec598ede594626be5ec92976a0679baedb3e0d3c2bf0d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3209366ce686e40b4b50f184db3f3ba210e87cca977ddc858ecc4c3c7079e129a35da6c73e1bbcf572dadb4dd69e1a32459a708c9122e09ae0e9825e51f80308	1636527303000000	1637132103000000	1700204103000000	1794812103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	64
\\x9520c24971fac0cfdf58dd985170667709f13237aba987089e05053d6da3159793ad2026ba5f245b81a8ac519b996a441c340af6148c9cc53a210c933b7480ec	\\x00800003c88fc029c0314285267d5836eb0fc48f49863261ddbb2980351f3379c37bf7b9f603c69df5a1ad782cfd866d41ab2004869c2167cc6e45f97841ebeae468a00b5c0777c3902a46dc1ebf9a8865cd4f3ac655569cde246c1104219081e65b1945ad8b44d6056fc13440223e53645534f5155206700f27e664a5fe419d59a9c9e9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x39e81e7b208241ade943c52b5c10712fe33bde64e1a2a52c8e07ee2e7d092bc4dc427f0e9c22e83ee8aea78d31529ec983b6f553af01ddfff0bd05a0c5d18000	1629877803000000	1630482603000000	1693554603000000	1788162603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	65
\\x992c1322f519f663a72aef5ec9893f065e7e9f1553e4e7c0de79aada7906ec334fcfb892d3b46abdb41cbb078c2ecc21f4569f2febba4341b636597d7b217fcd	\\x00800003a97e8cdf1e0b586f5d70eb07f1a1573ba92d255a9db4240e64f701ea285766107c966f428cbe8fdb0d9cd377972b0e27c64e6f443d5b30c3d3ffb98654033a4c4373f0353b766bd09c433a474ee0fd6e3a85fe520cda7281c23bedf6666aee86f32d46e2dfa07b8b22ee20dae7e7fc8731d6c3ec9f477328a680eb9e7c05e9fb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0be82fff4626815b6f8cafa8e933dbd05b4adcae76e260dbc98dc7c8ef25aad74125d947088a33f4bb34844e27ff3734e7db23bb0f8da2ab28bc53cd8111ad0d	1619601303000000	1620206103000000	1683278103000000	1777886103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	66
\\x99d440b4dde8e87a7bcdd3327e67200717941e061617a3fb6e1ae42feb6d5ad30e01654d54b83222b47aafcffc26da2f62ea3c6f219b4ac0b01be8212044bd6c	\\x008000039876c277714cd55b01fc0bfbfe76ae0abc70c5e2dc1fdf22cf75cc682729e185a6b349e26f120deb226fe13e5d78e1e4f8b840418ff811e9cca661a690e65f343e414d79e9b8dad3947eec93ba733022beabc442d4c5a008afbca1ee34dc43082f4e305a095b7b91487a733f7082d58ff1288b098495bcbc298dea8c94dfefaf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x95e3104b9e6e3d44dd0d669d719802d7c1ba2a79a02badd37408cc69d3d2ad156dbdcf346002408a5b9e3baf4ae9d811c9a4980c923761e1b2c4511ac0b1de0a	1634713803000000	1635318603000000	1698390603000000	1792998603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	67
\\x9bc893091fc7ff594858510b35b601de4cfd140ff90515aed89c4a21be26eb3b3a82ecd286d89e959eaf1df0ac4aa9fe4c31fd9bd00d15a633d1fc500192c806	\\x00800003ebc95dff44891f93d3022cf910c386986ff474a8652a156309341100133cc1a0fa43907d6c003e629d8e9c4ececc3117e4c203b47ec0156f68481e104a09a7492014b788c76b72937100b67fe88e2a56e199dc0f70176955707600d941d0c707a9640b7662326c6721f177777f24707fdb6224bd4b20b4fe07d276fbaf2e0bdf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc98e31d61cade92158d61908acb692633260f2410853e2c725a747ba8891e7fbf1c1cca48ad045725c233f45576bbb9813d3aa2cfe5eff2dc62531dd30fd8e02	1636527303000000	1637132103000000	1700204103000000	1794812103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\x9c845d6c8a2dddc4a731d5444821afff6bce690368f4280eef9def273a45aba10a7ccbb42bb02a3fb448110905fd379de293e34d563e1ad7db770684818b63b0	\\x00800003d33734426ab734fa144445801bc574bf24e1a3d83a786247e880ab41bcbcfda59a54f195f0aef0a70a373a627beac25ef3fd28726aac103747f5d377a75ce7e2669b0f0f83b723bfca1fcd8b83b6ffc5715f0949e9824f670e7e01fd105882c9b6df7e8e97807becb2747806445ed939af34b1fab1b3dde114958686ae54e039010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf5404aa0e7ee5e108834b7cec65b20c003148b04ba03d811a29e1fb0404735de65a15e350f93f7474e3d909f3ed6f58dcdb740212f1efdf38fb6544d4b7c5e06	1614765303000000	1615370103000000	1678442103000000	1773050103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	69
\\x9d8c45b8e7c6247e751a463bee35786b0ca481b448d0b61b87a0bd9bdc934736e738be4ad43bd683499989d915213750c838a9518bca1406b42c3472229f4c9f	\\x008000039b1ef84b566bafbf601042c833a399ff1bf28ca979b7f35a60346369500f69355a1c68fc791060ac3fb41defac869ffaf03ee2dce0b6f4e1cb8befb4730a851b48ab6e28794c0517a634010dcdd912602d2f9e52936a0e5ec5b76ab9256adb3946fe32c2d0dc0ea9dc393d6945f9a15bb84142ce58576cebe70dbda2cd432595010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x31ab6c8ed676b548d65efa30633d486affbe70203a650343b493d6ad9702a85be9eeeb53c51f010a77671a1a1c9efdc94fd04c7bd976c3f5f43b0d965bb81d03	1639549803000000	1640154603000000	1703226603000000	1797834603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	70
\\x9f2c7912e584a7b329964a0bd82ac008234446f605065f3abacc81f1db86923233385e8d23883ed2ecb3bc5b4d9d83cff7509f636ccede02f7912dc927e392e3	\\x00800003c7d33c8e310ef04d994bb85780fd9a28c1c53e7add85aa196d9e029b0a7f01ccf02a4e87838414a99a4b2abfb51f0c00bc2df8004aaae95a0ea6e716ca9985f1c6f1fd804419554adff6c4f40b83259fa294fb6250f4d1a0870c7d808ec458be74334955858e9d1ec060b43ec6ac17cfa5a795db43c21822181b9793da5b71a5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbb87fd3cab6087ea60de08e7d440e1492f255d8e8454cb8db967fcb072b78288b4e80a097bdc70c8e083a4d9c91e5b29a0c9a36978ba7b41f7010524b823f507	1609929303000000	1610534103000000	1673606103000000	1768214103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	71
\\x9ff8c5ba768b5d0d7c08ec9e901e07fde538f53f7cdc4921027e173a65ce02c3f6f0d4e62d98fc16d9fb44a686fa9ad0495cc0b9db33fb58e27cf3c534bff247	\\x00800003b45b2d74829a6f5a5b110f52db34e355b1e12a3ddcf729c74777f4571a50b6cbb440b77d1f646850a624e340ad684a97725badddcdce22039888787c43f1ef09093a4e3d5fecd6066361e13fd32b2e0789665762f3c687e4337b4f87e378147807d11d809042b36b6331d16b0cbbc4964d0494bd53468d54e320ba86a26b855b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd4379541a9493faab6a71122750f083116f7a1523ab0c46fcd599782e20b82f632ab886e4d933ee6636c61b96c9bc0301d959f9afb61b8d9a5c06c431c1ec60a	1629877803000000	1630482603000000	1693554603000000	1788162603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	72
\\xa11c149d2c06b4475e2adbe916ba5f44daad8129239563922d7721aa5863fa5e352ad849d11234a8823f1c4be0beac18b6ba9b49268ea6eef003545f5e8fa2bd	\\x008000039f9a8f5e98c8d515cc1b4ff43238eaa2c9f086b362c08197d07568456df23d8f3cea12df98237d7fcd29d95adb2e39fe93f2fe49db9acbe531bdb91217bcba41a11704af7c8fa77d7187bc0dc749c402418a05c9607a7f2c33ffceb8b9817bbf62e3c4dc9f28df0971977f7f8275c2987b71634cd4c8fe1b6a03c937d902b433010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xedaa734b9908f08e89013edb814f897b23632ea8f9a85c5a7106493f19c75d2ecde3a73ef593a809a2a3bf9bbee594dd5d710fa7c511246351d44fcfdcb0f30b	1634713803000000	1635318603000000	1698390603000000	1792998603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	73
\\xa1840368ed810c314ce324c0c8719822f5c7550c58fbf14381b9f6ca8abc791144728ad5225a95d8e7dd40507f13ac9483ed2436c749b546321e8bacee48c896	\\x00800003b6b163cfd41e69de9ac55b9287e59abe89ccddd35c6398cd64fe5e73172a87e48827e0accab19eba848b5aa24d5fb33cd5b1b0060a7cfc2ea39bd0747b5e49179900eb3b53ef0a39551fa55424e6e23000898a5de26fa643d853f7fe39ca2a4f5e0452a15a81bd8fb2a2411a027c9e9cc5bd588fc133f95d7638fbaf349698f5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0ad39d946b3e9ff9290846a1740612ad47932366b62c1d04b696063197b4591f980cbc57303a9722b26f8314a6a29b0b07becad455f3b4a8390aad9b4b24380a	1618996803000000	1619601603000000	1682673603000000	1777281603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	74
\\xa22421fff2da4c4709b6358c0a773336ff0d04afca3f2b3ae772aba8c076753908375573503a31014a140382314b8bb5d4c56060652ef2625a65b81d99f1c1b1	\\x008000039b7e046c7229540211649d4640a033beee3cd54aa695f089ec84d869aa81cbe7a07f7627d98b89f1126795773da39cb74fb407bc215bd42ade7c29afb263f3c6d7271185aee30394039972b506153a93b6e7ec1cdbc1468f29cc3e66cda2c648a84a12649dd93dfd18e1eed309c63a651ad3ad8fe1c48773b9989b1754c81d6b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6f4d6fd6a606f25c21c6d44b9a785c22f08a964ea8ab17c6af5d70087257970955af9a6c601bed02a623a7927d78e6259dcc739d97f7874ab8447a904370f502	1626855303000000	1627460103000000	1690532103000000	1785140103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	75
\\xa2dce11cee88116255365f82d122caa94e4b125f57a695e003ff0b8b7921059b8acb6c6476e66c11598924e35c8793a47a4d591aa7c83ac1dcbf1964a4077a5d	\\x00800003a9009995bceb6fe6379f8d0a8d35ee3e23132f589c6898ab09c78441fa4aa07a1af203c048ab136a5d8e61500e189f67099f5f1043b7c4c3f80f65366459e07833bc192c7a905e1467396054806f9c950b9b23ebdd2ab670bb8ce9b663f2b94ebc4f59282d16b5aad58e190bacc25e663e8a2cf1137722dd2a6934cca7d1fdc3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb1a2370e3a88f7b437e5879f644d0f8369b761a9b9cd08335e5512e12bb2e83ee662dc7f2e80d207c81e1260cf569ff80a748bc7cddb37905332928802e40a01	1628064303000000	1628669103000000	1691741103000000	1786349103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	76
\\xa3ccd1df4a54ff26ddc99963a6ae9c2aa9a25659f20a0390150e511b222d24a2440ff0621014b74c0183aca73263535ca53d3d91f77fef39975c0ef203a6b0cf	\\x00800003c27d9762c451d9cdbe52fe9091ca18ef1852116aaa3984babe0bf01efbc2c5b57361900bcb52ae69f058c24229eb73557e7fbd98516c8ca76553ddefe14d1046a702a30572fedb631ca06ac346580c4c1473d8c8470495cc10a272f7ec09128efd5419899a55b964ad520b3dd6c0fd0674dfafe2477054ae582157b5ad866c35010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3db1fba613555fecf4f1145b6fa681370f7b9484fbc4724277a8bc7f95cea9ba0322d9858ca1c2a53b66a76573795369641babc4082ee9f598126d31498de303	1614160803000000	1614765603000000	1677837603000000	1772445603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	77
\\xa44c253e77be5870e275829a69875e291178d54b5ba8584fe094bc97ebb81274ae2d44d8a30646f3fc07111a1c7430606844d59d3c4372c32f54d483d59f61ae	\\x00800003cb64a029f021d5d273531bbd5a09b648ff346972e61438830a57bde77ab5d471bf321b7cba1e9a4d9bf118445efd44ffe1a69bd335e418f656492c26b32ae93afe90402581bfa78088ae7c901578d2e5d9ae37e55716ea3c84764938c35d6e37773fcda7f6a372c671ae466f168030b6b2d450a184b3a946e094b05b25287fa9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf60527c79c1c7d34677b05e086263870ba17de3f2a88dd8d093f01342023c7aab51253375c16ce6e783d1ac31c5f2df9d37d19701eda133aba293732d6f11d0b	1637131803000000	1637736603000000	1700808603000000	1795416603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	78
\\xa634c870a6c2443a6b5fb02dfd510a3d364935d851f77fba0d7ea0c7d4c2cc8d23677f00e14e119a9ee1b85aef77961a4628800726c6012ce23e26c04c9232cd	\\x00800003bb4e1a970f0194fb12e6db1918a6bb474648966d64243a9493444dc14446a0cf9a10b62cf3344fe427a9fd9960fd8ec4572f1c578e18a116e7383ff2fe06d7de46e0f06da0b66d65f4e0d9ab2514f021b571dfc12e778d9cf40706b69116fa3bc19f261d683952bfebb83cf0bc7afb74654d0f6c06b993e6e7315971f98d5523010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8088363e27be44369f97b10883241e352024735a5f2433f5fbebc26093c1b8f5ce2a72bb7e306d8e894952b107e4a932b5eb34f8480f665dff274d7380da660b	1610533803000000	1611138603000000	1674210603000000	1768818603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xab70f46261d9936093dcc7da21302070a5b5e38a5e19b38f9f2143f1e4f58d67ffe5a242f66a7fe00da7d0c7a67931e6a37691a3ba95885f05efd3fbbd5e5e0c	\\x00800003b1ca6c876024ac6dbb4b7b98fb0a39996c24020b8c0f8fc5020cd041e4b05c8bb0515a39ea44afd2c29469d4aa115526554a0a00d11430febe2333e2cc432fec88a5a438fbabcd43326862f629fadf0c96dc39fc68584dcc50b4be16384039f897c92817485b8f6209114770b433cb14259d765d6bd970ec231c36a855dbb13f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb111d6915f9049e775b40a0cbdeabbc9487d55b913ff45250b1c2766d3e804e1f839aa11c014686c44f59173238088a29f9a204f6019fb55f618beeafe886f0d	1624437303000000	1625042103000000	1688114103000000	1782722103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	80
\\xae1cd13a4111f7205fbfc780d938f8d803684811ff7c00b3164f8bf2180caf08af6bbab094cd3389c1ea668faa13609c9c13c3a237b96d1e59274fba4e5321fb	\\x00800003c487d2c32423162f37bc997b0a1fdc0a3fb24a2e72197b118e30c4a90e5f42a19ae9377435a2f81b683611acd59f5e31b7858db033bd5528dc728477aada10fd1af873b4ec4d0dbe48746a8fe277a13da712be5055e4cb00c84ae139d1498c5438802b17be365f4806a42685dae6af970c84ead9bc2569f8d6c4c1a70ef05ccd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2ec03120ee70ddcaee05329b4e9483ac9a904d49c680725842645531076088e20580e44d19dad95edefc70382d7947187476b18a395ab0b54c4dddfb1519d503	1622019303000000	1622624103000000	1685696103000000	1780304103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	81
\\xb248181d85867f83bee7685f93b06269a5aba5d0949e950bd603b4df506ec061f5730ed0db2c17e754ebc5da23e061993d71d79253931fa47ec0451d88dc9b9c	\\x00800003b4773553fdca50878b98ea1a0c5490ac001f186838a0f21c1610eff7a21393672ac0b6599b0d89ad46199685bcc69d0edf6197d2683a6ca0f3f7c3e31a0619fa05a3685c6474248093fda20c4d9d844e1459028bcfcfec4f12ec42ce4325d9872d84f5d72408769aa940d1d82894e36e532061d600c708f16ef0fda5ed8607dd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7eeb2fc21fe93c75e49425520a0e3c02c095ff63faeee187b4f19f214fc6100bb2da2dd591f7f0c379e59dff2de8fbea4e032b7c9277d4b246689587cf0eb309	1624437303000000	1625042103000000	1688114103000000	1782722103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	82
\\xb4203dea9ffea8681d60fa2a03be5c32c1da6abf1943f4877593cf254deb518b6205df18a6b26aecbf0becc33749167a4b269d85b9715283eebcb65e59aca3bb	\\x00800003c561775c715e2b9a1de5c314994012fe18f411b6cf419ad0669ea29117cad755800ebc7e85732a780e2dcd6e1521fc044f4b641b5b8a7d2b624b616fdaa51e1aba8015e43ee2146c40a976a08c011354eb0cc6974e760930f3ecb34ccd7ec6c70a9d0d44dd99e15a282344dd00f0707bb7e891b0842d3b4179f75f303a53e339010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe2db3362bbc6fc52981ba7ebe05dc3a122e64ffc7922c92226e8611fdea911479f72dfc912e5df83942e02980218375cb51415f477b1011d63defcae774ab404	1630482303000000	1631087103000000	1694159103000000	1788767103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	83
\\xb9f0f644a9142c4006be5ac7c4c7911570e5e99454adca0a3807878b0615db5516e1dcda90de162bc0d5261184d6dfebdc5505479b1850050b4a11d3d688d018	\\x00800003d23d78ff303b867f743508573d748c3a5dae9cb1f7400b166c8b0ad75c1beadb4557dcd54f32f510eff674e1fc01ebd3f355754806503374a1077e0dba42fe4f3329c935e11d37ae51c5486d0790ae8c97d4df36f43ca1f43569fece5ac3b22dc2d2ddca329f7ef64faf0c95311de655bddda92a6695abb8f4c07d351a41dfa1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe0eecc13f8cac852ad27cc69f0ebc811cc5cf2e527adc4bb1533c2ae8341a81429fe5f3528835b54c01aaaef1c4bfedcf76a38b304952cb139c9ad83fb04eb0e	1634109303000000	1634714103000000	1697786103000000	1792394103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	84
\\xb9203a5ab08833dc5b915a11dd0b2886e3403066f742c6744f82b73148946facee540f05454b6322452a9261595e87adf97a21479aafeb2eee19df5ca6bc2f64	\\x00800003ab0ca65b3f7cde3ac5b5999a428bce3d4201d9df81c68768aa30637a2afd12e14183e8b4c3419b79ad22cc72eddd9c436e24e94a35cafbb0412d56ae29917b0b2c564b3cbeffe8077b5e2458b724667aa18e555f62266daa99d655d82694cf441419b3b5077901584f24b59f37efe0da271e73e2259bb64e2ef5232803e64889010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x57eb8b59067ee94be04da9c97427fa87f3dc2fd24ac395ad01f2c5249e5ab1abdf359a3ab5b07fed7859b0244524988402fce552d6c2a5fb1393f6734dde4504	1627459803000000	1628064603000000	1691136603000000	1785744603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	85
\\xc318d5c64faba6594c8138890ed202aa66baae3a6885ce912f8601a36f170c757813c48f17d8459e26ff44838cdc0f72975198b0795d383d2233819d81ca504f	\\x008000039d46cdf209fed03fc920774aa66858dd97ccef9cc00e1e91e7bb3a1a572446ee1227924ac096b7911acd5e5b2ef67491f7b654332a6d452e25084c1fd2ecc3d590916db990c4175e9cad46084c5cc9a6d9c5b2372d07ba2a33dcd3bb9fb41ee86084a1820a6a6f7952ffd606be07368cda1e8d497137d28ebc81bffdb023428f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6459dd1f20b0121ff7b97340d3d0634c0133cfcffcc696b1089a2504c5090ddf0e3cd6092a51d06832d39eb381d23768fc3cd0590fca4164d634c5b03388d00f	1627459803000000	1628064603000000	1691136603000000	1785744603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xc4a008dcda26faa028e9dcb9d4f65a0bcacc682a3599aae0731411f2a89ab208d2139fcd2c6ee3ef34d1b854c589b6eb4afe51a73d5bdd2c8f2dc989f7bf39e4	\\x00800003c6c9a7f80d463c43f1d3d4fcd50fa35030fc51f0c229ed642b731c5820720d580c0b33469aa176e166cb1e11fe2b5f38c6c070c8744f19159e210624644c3133aa71d8310db5e2c883e560c4ce77a5439a42ae3c08ebcee6e89a9899d64761332c9f0044b272bdae0576c45fffe192f662f0cf9c91763c82a5ce0c0d86c11173010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe1324c5c84b026af1ac270d7315a9d5d862aeac9ca7551b5f4ee114299b432413251ebe922357940b42aa29559096d7edf7ea7d4214b471dc6327307d7d54d0a	1616578803000000	1617183603000000	1680255603000000	1774863603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	87
\\xc5fcdb72f1565718b9e0046fdf634076d857a0979f4626f495324aa5c6d3e5ef9ef9a4581c6b006d8eb402471d612c17740f5c45fd598772bab0f2419aee85c7	\\x00800003db8722c23b0b5e7c817062beda41120fa682dd5f0d274dac9125dc400ca5b0c8473cf81f24402153c7ee4c5560d7bdaa499f3314322dad4afbd08e9bf13a3bf3a66743edcab52849a80fcf040e2ad540f7f2eb8c38c878c4edc02ee96d2d2d62da1f9e29d35fe4b03be960cb3b7eee5c9b1680baa7eb30180c34a4866520702d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbae6b6ecefc7649a5e5990ef65d0d5d50ac7057857ecaa372ca536a9e8e3d1e4a564053079b4f95d0b6514200febc06171992b477c218a8d95b9328e1cc5e20e	1626855303000000	1627460103000000	1690532103000000	1785140103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xc6244536dac871e8570efc4cf29ebeafe406543791c75b1d9cbfaaa489c61704927b8728c060cb5a1deebff0f0ad36cb0a4adf8ca3cb9835fc2e92448d34653b	\\x00800003c5ac80e7e0db314e57bde31e8b0d96c5f1f3802fee6e98bd53fccc636c4503c6aa89f9f41f8dc1727cea6adb53dc4aa42738d8d3368547991cf534b1a1e6c1c018f7d77b6e5468c4e5d1b7f14263892b1140ca9bc8fd47fc9eb6ce6023d9537232061a1f498fe0059982f20d98bd90917a55870899d6a10da778bf495ac7e76b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa03c8826af75e8e561c61ae96f30aa0e98c287a94138c9756f8fac53b8870fd0d17933501edd00c4e5a4b9329eee53956313c732eec0daae4928da08abf1dc04	1641363303000000	1641968103000000	1705040103000000	1799648103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	89
\\xc8680859733f3ef40903b2f965e3d384e16865819c847602430928c921803ed4c5d5c9fcf2b7ceaa1d47e22b48402f40876ee0e0865cfc089877dbabd0d3db1c	\\x00800003e2437320a034240c14615a2cdf9b015c7e3e75b5074df972ca42a643ec8951abcef9e18356df6f9bd99fa475ce3382f48a4bfcb8e67fc3e6527ab0fcf44aec21dd2242856b9d8113c4052a694d1db530800366f72c8addf61b79e0debaf66aa04b134ee7b4b820fd905dfa39591715bf3c8c3edf0c7017e2f1f391a29240458f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7d1bbe3145dfe2973449273073104516e5063dfe65c7bd7d4b2f3fa79e3c4df85cfbab244516c67f03b40d93cf13830acc45234d58c5a61d3b705fb5f2223d0b	1625041803000000	1625646603000000	1688718603000000	1783326603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xc928f11347f2258538bae7f7fa1a7f592afa107665d64d43dd28a32ac4857b6b4e047b91263e08e10f4d93275b53b7d0c6a968f4aff0acae184df4edcf915ac3	\\x00800003a13360f152022ef60fc03ac3a6bfa62403dcba7681e636e9379e4535376926e252c3b3c0b5f40fecf7678d36944f86a1e63128f3943936a7a4bd5c9785aee7b10c0f1401ad5a5422c3e194c3244026d11e5321b6ebd44e4551a20893601e23316c59cb1156f3e71c04f92c216f9839004f4fd6661dbe1e2610af53ae86ee47dd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x057bbc1ea699b163eaa7faf0f526dd99228818d78dd71a615db362e81e49ada740ba4df948d79cd15b48afe5780b724b6e36d3839e4eb9e8788364ed8fc6ee07	1617183303000000	1617788103000000	1680860103000000	1775468103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	91
\\xc98c80ae5df8403b185fb94120d00f362ef09a7aae9105d06d7ffab46beb62ede747b2b0af4b87f5f21b4b3ace7822a2c44d05df74ac7eaf860a8ea92ba47770	\\x00800003b3aa889c65d5112648bafbcc023090fb0b425d35c4c732faa2250f7b5724c9e09271a561bee674083d721e37ad0524766ea471c2b944545f479c905287dfb9f0d9b767c0b961f28f3bf748d0da1df28281db84801c1634cfc7238e2905195237383318f482f5793e7ab433d92f40d6299d176c85e7a8f3b46c22696b468abf85010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x16cdfc8954aa573b7eb09dbff0bfbbbc5c141374a221dd5d75459a80847734419d4ac28555d71fb1ae4722e98041b771725cf4dd1a548dbc70a9422353d5a90a	1611742803000000	1612347603000000	1675419603000000	1770027603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xcbcc50603cc963d623588cda3253a47cd1e7f99c274fc2c7b90c66f66c7bff73fc567be9c214d68dcfcedb0db85439253683ef50a4dc6458d840c36cc85005c3	\\x00800003de5016f9876d9f0833d7ab11febce6aeb6b810e3c69ea69d38cb26186dfb5b57fb530dc09ed6065eb9e781591199d650581174464b0e2b2493b5d893391d07fd56df4e365337fefb6bfd29e7a24d0b15d0d00e64c4b872842706ae32556a64dc7bd702abdcfb49b8274175d5c291353ce99f5a3752a16c22867610eec74cc7f5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7ec7ca96d2225679f4837c9df1ecada95925d7d75f65789b56fd31502790695632e5cc19a13db533bdb1d3cbfc394d04c99369cdd6424db8bc23aee5ff148e08	1638340803000000	1638945603000000	1702017603000000	1796625603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	93
\\xcd88c056326e4c9a27613ee7938da2ba07cc14a84e925917dce60d66f205375149a992fba10d48935eb3df575f27fab20af32889d7d6a3cf383e06a9c9a75eb9	\\x00800003d0afc68c05a3a41dcf9426a1a6c687ae79600a252f6e27b68a0e716998db8b892a2320ce872d5cd74542599ae55b568ed42bf72ca39843cb0f6f9fda948fdc0ef3de18de17bde865bd5a7c5cea27c47b12a8fcc81e71c2499ef0e51d2f792643e8f19fbe9fe7a0c3d8d0d32da95a6d1eda0d5d68982c1fc2cc00db9e33fbd4eb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x56b2a376c9ad164c54f2c791d60253a90cd3411de2081d17d3ed4a897e58faea3f0b28fd4fe66833371b3329ca66698e37c7521a8aff2deb8b4c106e8e7f170b	1625646303000000	1626251103000000	1689323103000000	1783931103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	94
\\xcfe89cd9e712e9320afb95a984f10d36e8bc817ee0ad3061d55d9cd16a466475384d322fb2a9ed88aaa5cf956189af37c692b3f8a1906ee7edf27b5ccfd54177	\\x00800003d6af487bac5458a92d9835564d6379c6f9e059d7fde77ef1dbf74b7f048064821b19a9e9995cce26c75a1a308b5bc2274a2be7de9e9cd7e9e7f69e9c434fea55e332811c2627369e5653a38ff6966012d2131e898ac76f9c06836fa80e62be8058887557eaf1d3ff2147214f1651dadec8f4a48c4fc311dd3430f3360df67df3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3a8a98548307b2e3479a51ee00c37bdc8ce8b512108809c4bee5676dcd29ef192225ee85f0b7be13ea1f16c7bad76a53f107539afc6d1fa21a3bdb6c0862dd04	1640154303000000	1640759103000000	1703831103000000	1798439103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	95
\\xcf7091b5f2414049ac31e6f05d1c0f9e097e97135f9d7f0f85643f8ad54e8afdaa9552847dc860418c0ff92608330d949bdd859b1ae57a3aa402c20a0e3cfa2c	\\x00800003cc5e52bf18af080c6171dd283644081c016bf051c9a4412f0c070a295e531bc2cbef2a3df97b5643debebf7c3c3f83f1f6c51dadcbcbfac650993556001898e11d41120c18bc5ee2d0fd4903486e9b5360c33bb2eafa1762393683d8b8e6faa608f6a37b6325076f6a02a747e264a56320ebf2181fd9420d595b8f45b4a8e099010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbef8559397f9965af2bd978fed2ccddbfbf9250ef4d86a6ebc4479e43d18983ba40ae9573327dc4d09d7c8b9ccec3c907fdb4c887a4891b737e9162d4f7a7908	1622019303000000	1622624103000000	1685696103000000	1780304103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	96
\\xd150f2f0befeb26e781ffd2bb4c7bc42a4cc0cbb5cc61724a935124200e3778e7d46037056af52f5d6fdf28da4146470c21f29ccad0de7324071b1e09698dbcd	\\x00800003b5dc969d25c18cc80bc00922e390470c9b664a4304e53c344a05d5123078c403eaadecf1111b695b61534d67af5f039bd9cf352928b88b3956be09e6a63c8a4ed3ba951afa9ae5f9c556b3e614a623af4ef336bfe3670f650cedfa8987775f44922dd350093862d17435f59eb3d51432a89995ece6e0efadb1403480a848517f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfb79ac654dd862a7bb27df6ed961f97c4ecc79323764419be021eaffaefb82e597d62151c2d895eb8ec6de313902fbba33bd5274a384d7f2141fdc5ec05ed602	1631691303000000	1632296103000000	1695368103000000	1789976103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	97
\\xd4f0eb3c3026c4530a4887fc1ac4aaa298d43c092bb9a1ecb4249b5729bf57edef84446f33ad271a672cdcc3ca352a7af435dd0c4b4248847c486cb78a6ac796	\\x00800003aceb9e3aa2a2c31d0e6288eb0c92cc64790335e47697aacbea55740c17d2e7c1f15c9b66909bd85569546cc0fd88d8e7070dd2c75fc9f30e2416767c8a102414df7083e85cd9c3c8d38719df955aea710db2df437b111336f33fd5c97872c1ca05bdbfc61b42d88727c7354ccae7a0ec051c0b5f23630223b4e3f233f6759d33010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd7fefc31a847d4f753badc8a3efb0c48c9142ba56d5ef37210ba117fd1b0198bc8018e03033a5e2cf591dac800daac161c780691f277397c5fef24305e272705	1633504803000000	1634109603000000	1697181603000000	1791789603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	98
\\xd51c149bba589285802064e1d371f821012ea0e2b1aa42d7d738ee96fa43534e74ef7c75dd19cc24867168e4f95f7a2f6b070af3ad79c7713f63a56591f464d8	\\x00800003e58596f7229013a6a605fdd5c122d66a30549a7cdf288c33571af8cc90fe36e04bbd6e53d65ecdb548815ae5007655dcad3fb08dc2d59ca0ca9dc828a78e67e92f34fdd07ea4a687bae696a5b3b992bc9c0d5a9e15a8e9fd12ec7527f2dabe37e58f0b972ac525e3fe646b75d42c2e17e665ecd39ee1702fe37d52c012e33c1f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x284e0c2ad881b12943845631c55af887a3241bc40163c3c61b34ce8c5b9ca2d368ca418984ef0ae900258ba0d2caf13585392a32dc9283692781f4f945daff0d	1629877803000000	1630482603000000	1693554603000000	1788162603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	99
\\xd9d0567f296ff0b52174977b76c61219b58f943c31796efd60ac0b9ab8b2b8fe6cd96644b4dc66a5a589ecfab223b76bc535bf4ff386b5734d7b71b16c354f00	\\x00800003b0de750fd03a3a0439cb8e6ddec3289483d5250e75415f504b4a43e95b7ff2091647332f484e0aab0a037ef88d9730d809492de2198f5dedd7a82aef7ed9443822ac9ae68375af51a4877ed83150f684b7c00db5ad941cf62bfe12db161b4289afda71c1415ee604a3a2878dc22e12355fedc1a931c9dc7184bc371df69acec3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x736138c75b73684870a908a3fcc2a77954d2803b050de0bf397465d0d80ff762322fd1f69565fd46e7c07a822c780e6f1d0dc33637a9bea365cd71633483bf02	1611138303000000	1611743103000000	1674815103000000	1769423103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	100
\\xda6807709398f4e5471a40d02b7899e88bd3e708ae4c65fa182cc6c2fef8cc0f27298722f169d24f0e983bb67b421335e7de1235c4360ecffa1fc0d5dd1e85cf	\\x00800003af447468b42c8a3668465d2991fbc5d21380d75d29abfd357f13131e65836dfd5e7036d729691c7bc17e8444f2ff3229f200d229d0ef60ebcba6bbf572e8706abcf89a2ce5484329182a459ab0135941ec3d461b9da9c7e993861425cd1fd3706509515b50e223ae425960ffdc8a12a2afd28ed92202f07d1a3eea5e750d99c9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x20922872f42f8253735c23b0b1aa4d6f7caabc67f890cf7506f6d8977a64abc356547e0c664b8d156ce66e285bf2cc83c2b76df4ab08d0369808981672386f02	1628668803000000	1629273603000000	1692345603000000	1786953603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	101
\\xdb14acc0abf708bcda0312634089b422b579e71eb99364293c0921045a04b437d5b606c2c7ea56448a7a47ae0ec7b58ba08d67fb309f9557ea9b2f32534e7e4d	\\x008000039db178bc72341366e0bd0bb01f35cd25f359b9e0e48e64461f9e9cb77c10af92682aecb2108bd3329354b3f447f704741f4c298f4c0c02816827ca170820065c388ea5c18a616d70d41bab55f0de51fe50597e1bc08c0350f7e6d43347261a3e9a4e9ad959de3ad2bb48111c4eaf15d4df67ebc0c1cfecb0e4e904a2640cb7cf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xaac6b8b3ea5ce588ebb3cebfed8eee15daee304dce5199462d86a9a656eb147829d87d9a94b31464d73e6dfa7535756a91396bc5633907c87ac55dd0a6a27003	1614765303000000	1615370103000000	1678442103000000	1773050103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	102
\\xdb3c3671d7a5c67303583dca8a746fa73515b9aaa159b88c5ae362703337d5eadbc46ed6d37130e3d1aee35094315582d07c7513bf0ddd8890c93224b99163fd	\\x00800003b52ea8f335a571014240f063d77f627e294e38096750188c769d2e0d0e4d6dabae4c65982d8160c992ce14624d876b65201596efd7d92d65e599121d73460fbbbcb00cf3bb7ed44c778f88ed64224621dc9f97b7cf3d17a7a8e80db62a491a9b24945dc44c4433301efd4a00dfc563511404be24c93eb23dc11ae063a47af569010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf179392ef9c99863b4860a8bc42857a3314293be745ebfb839f2b00169095599d6e4fa9217669dca1f4629f3bd9bf9094b1b404b695ff7ce77f01d4549640503	1619601303000000	1620206103000000	1683278103000000	1777886103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	103
\\xdd005a18e75150a66d271580b8c18cc099582752f1347c32632ff1287ba503a5ee7b6d39f4da6dac147e57dacbfe7772a6ebb0c7f2024d205721b35f2a555e10	\\x00800003c28bdb544861d4b81553b6ce8dd7ed6504194f09d23a5bb8041334ec5c9d66b65e0fb847a25419f74c0e115e8c366fe1aa4ec4422488f2bd07eb8232f8f13c84d077b3feac206fced4448d7d0c883260e9ce0fdc280968cbfb324a23468c93690a30575a3800e197ebc83870e9a0ad63af4e29cbf17239d0ac6505fcc08dcdcb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x60fa3e60eddb7c1e03f5b58f9aba11c0ec1207abd8f378d69e339dd1e8fb09a3521f3555ba8a6ecca6b87c28fe814174a461a3230fe1133099399792a0446701	1617183303000000	1617788103000000	1680860103000000	1775468103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	104
\\xddf8090f4098920d078c7a8b56f8f7673f5633dbffb10ddd13d29c38f3fc10ae17e7908f6a25b07fb1d52e327614eea465ea2f0fd7866ddc9492a15d9a72893e	\\x00800003b4696f83e9d6e19448c1e1ac20675acec3d181e4bf70d877bfc73a9652dad1070dcf7b380f215dd097ee8f74b21cad53179425886f2529cc8d4790d281922510acc0485c80997e8071fd21016919c1c1b9d87d0e374f210d82cb4b9d5410a6a1c7d99d6d6e7ae41e0ef372baf4a8acbb5b6f40d20b8cfda888450d31d3994b63010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x18daf5696f7d498d66b78dd14c1d2acbe283e1390b10bd7cf5b442491fd6ec8a2ea8c0f2114f0b2344fc0be6f70dbd0d586c0f8b0eaf3cca736a44d21fa54b05	1612951803000000	1613556603000000	1676628603000000	1771236603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	105
\\xdef095970102e109026cb37c0cd9c7c76bd3aec0df13c9849de81c68eaf9b37e7a1c45175658e6e94305f722c34bd11fb9c0269930d65daff2922ca010473050	\\x00800003dee8349b57c6ee2b1657b99897073ecfe659253bbcbbb0f47dc62170e613a2f0cc89bbfd9c8c1104046daadcf1ce29e780964dc1f094b26ead4f000356ecb1a20d1fd592ec776f39662d466a0c01eae1f10e5dc8a518ae0096d06de808230b763fa48c4c1ce4ea108f6ecb0f50f042af51a2a08ccc941677a9e5b0f3f2cb5885010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x775ddd71899f8e39b6295348e17cd5ee483cdb0d6298e43b14821fe5aa0ef3d5ab259b45d681a9ca75239cd98035507b122eabf82fcde90b378becc5cd99f70e	1639549803000000	1640154603000000	1703226603000000	1797834603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	106
\\xe1f0437052f8faa98a6a1c5bc9f77d73b42112adc6d3a9551404773edaef3442616e586407246cf1499112d93c7d0007dccd4be2b2910ded60e343a0562d32d8	\\x00800003e8dfd35ef35d294bde1fcb671c901632f6622644508010093fd1d84c44600f2a6b3922ca2974ae33cc6160efcaef29acdad7d16a5ff7c00650250b20bbb17ed2a46f8ba59c006e5142bbd502bcd89162673c12576a5e6e5a50f81acd636e94a45af6a85bd8042161734ef0f51d8ba08194ef3dbb4ffd04755a7d40893f331b51010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd29ca887ea613d9be716db2e8c6e2e1986d3278c7ecda6d4f8c4bf790b1ce406254ee02634c20743eef84aa5ab5677fe41b02b1b1e98be0808d002e7b692010e	1628064303000000	1628669103000000	1691741103000000	1786349103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	107
\\xe184730381242aeaa92b859c08d2e55ad697bc5d0fd5775c872518b56f6a5d59ee4c24156f2401060fe1ffbc31c091df03f6ebd5c1ada073fe05cf2e1ec1cae1	\\x00800003eaf6649e69fe2325408237ddf4b9e464ab050d52528ce54afebe19f80348c3bbc6bf0aee1a2b9e756af1ea4fd221c3d9ace07e3614d61992eb91508c794f7be8d06f32402e771fbafb4dcd5db5c89fb84d0fe20335993608eb32e175f0850944be31e3086973d91ad64c1a314103ca096669d311488b03f732d5cb487e909189010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x463a92bc2702f80155b72e1332a00f6106a01f1895c4e3a6c4b0596715eff3d1322f67838651e23a408b92c11ca1fc1a7742fd20cfefd685fd196ad201e0750f	1614160803000000	1614765603000000	1677837603000000	1772445603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	108
\\xe73cf7328ab2de9a14a46eef614abca67dde06ce9c28d1be0a0b4dbcdf887e9338b36158ab026db4c8d66a01fdfc0dcd5e079675780f8d978b5b95b808efa1f2	\\x00800003f84121e48be5b43467207a05b16d5e0318ef26f6287d6bf81a96e5b45aed564d874b192fe50b1955e1758fd8ac69d764f087228f3bc1535543319b69fa1f7a8066a40a37123f1800fc55c1ff9a8b31b8e1adb1e9d49b807ac72eaf90565d22de56dba010ed45b896d4e0ac9310c7ce6895271c3c4535dad53fa48881f0e9c77f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf39cbe6baad0f70cf8a89d1918cb46e17b4c29b7aaae03745e47c588af3885728266d56413a2f86ef961a46482006b0cefc37968bd4bdb2954a2c28d520e3807	1618996803000000	1619601603000000	1682673603000000	1777281603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	109
\\xe9c0e0f8bc3b8531f5f706938f53c470d20ff61e9aac1da173cb8a6a5b5dc985045e84f8e3b5c99fb42c30bef368dcce37f76c0b45d8de1bd069cc2f7a82dc0f	\\x00800003b8b863a0eba9c4dbcc11a4028d25cfc0ba8a8f906df0b17f60189c5968b810a794945520c1d3cce885aad07e066b5b1bc78ba91da28de285488c3fbedbef9eeadaf829529cf8ec0aaf9e4336e3553d2478e799c4425d85821a182ad620de401a5d48f2765df46c7575398fc18afa2257a1abaa093f08ec5b61c41f5a68d79819010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x276a9e1903c66b0af4fdc8db7407bc77487c9d252ff6b1d27cfc6ebe5f6daecf5da9e651da5a60f72855e51b15412b12189ea79f29b9e4c87fe992ff40de4600	1640154303000000	1640759103000000	1703831103000000	1798439103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	110
\\xeb0cf4c0195ac21df830ef28197f669503503bbfe1fa48d28ff5cfe9d4cfa67d96906253d0b783a6832ddf0976c45a91eb9fd97436534a2defa5601aebf7bfb9	\\x00800003cf18edf6ad24529e03a16de5bfc52203f69e5177f12603b96e82450b393b9e3885c6724e09a846654b0161fdaf28e743143e51e59e23c78208228866c7e0792da457e211a8d1a5700b55779564b17c931f23c3e60e2cacfdb6a5095e93f106b6ab53c69a4a4a088dd1055b6597df9171021f46047be5b452700e169330652de7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa8c21aaef25264c2b467a745d96c092217124d3a736eab7885cd31e0453becfa1ee5d1ce8aaaf4d3d1c5b1199176ff0d55605bfcaf70a348932af1cd977de809	1614160803000000	1614765603000000	1677837603000000	1772445603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	111
\\xeb180a362dddf07935622cdfb987d6be604ea4644a6cab9903c4760d1ae2ec96cd4c5015fca4019e7ab79880580ee024c64693f81c1d05cc14c57b20823cb891	\\x00800003bbe83d1f5d92c2dcf56ac167b7ee4f3d625e522a9a764ba40b5bb51ae17567095988a01f9f4d617b46dcef892efcdd5fbdc6a215ed1a03ac114904e663840d7e0a6c0bbe45af3659d07c6f03ae11bd418dd6a16e66ab6809e41fd6bc059fa446ddf0c4fb5e044f66102c86bc38327d83dd78b7d388d338442c1c636ef840dc9f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x612cec869941f34e33f03f4d35d5367a936b04164bd044bc257cb6c4e262eb8589117d81a5281298790e55639c772509c2c3c512f741dcec7a6b0eb0e785fc05	1638340803000000	1638945603000000	1702017603000000	1796625603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	112
\\xf2108a9acd0da7335c75fe4427f6f07e3a78b1d2b44def4fe573ad682ded7455ca0e58d9a717d92e008300249dfb366a3738b9b6a12bbd7acd6830d97998a2e9	\\x00800003e5019d3d0100f73f09e14bf20b7151d2960c4b5b58edfc571c31888ad6499d0d8bb1829ebda059273d3986870f1dfe0271cefdda0e116ca6e8d1d2fe0590f2685140a5d63aeb8ea7f50452fa3d3dea6c91147062be86b2248935ca030554c50be58a675b607494334f03a12407d9429a4a5c03672c7129f6898a7ae509dc4d6d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6e00bb100706e3b6d0a5d0df2a4a80edd9461b087715bc059a8f7e41d47512476ab9cb9d14624288ffec3864872128c9941486403fc2a560332a577859b19105	1640758803000000	1641363603000000	1704435603000000	1799043603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	113
\\xf4f0b9a7dd0d65e8e0cf40ae547cef4773c4bad12f1fb550c1c1d93a37ef1a6d09747adb502fe063d295211ced9f26eae160f8f3349aea85a938297b77a1a0a7	\\x00800003ac8bd81d207ee4ee57f60d17bf51c092e2d095913fab63207a547c112935212f96915e2aef8bf4a85db3c22e0fe957b8436425b9f2de481d87538c42e3c32b8f83c56f26ab71ec98aab8440bd9b5f830b1fbb778ff915c630cbd8b7bfd7d05b3ff5e9401c629e355bfd95c4ee104e55ddd95d8f01ade72f18f1fe9f20ea87d3d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcfd34a2fc3964a8952a25ae6c09b443494250072ae5300dff4af9e43c7b9dd700106c015205aee8bbd606130efe06ede13cf08ab5567f6b2d78c1a0d6f2cc20e	1618392303000000	1618997103000000	1682069103000000	1776677103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	114
\\xf8ec6ef603c9466b38d3b10e8bb61c20d66b561841035dca2382cbbc9b1ab1cb7b0fbcd7b74fda23042c52e5eab2f80540371c828addb800a03e6d757f751d69	\\x00800003a75db09fbce59a3b358972a993c8d22836a958f7a6535322f4a8628a05411b8b17135aece30ec886b03b103d50b12a734e770cad2413da82b76053550ee9567dafeb0f273aa1256399a35cdbba1b6131f078f654545ed8cb6d2ed42be5c0e756766529a438e2184df5814624b3bf5f5312bc250dd4017189de5c4699a212c0a1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x95cc99de17212ca1cb7fce7099db8f6973d44686a32cd1a5e8e20c9c037a464bd05ab0497ee2f06b69d1777c6804cacbff6db82d027f9a3fb27683edc4317b02	1639549803000000	1640154603000000	1703226603000000	1797834603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	115
\\xfb78d86c3e8f3d4a31f69898025976704597928a77e58a40ea3f19c4333f28b9d2c7bd933e9c586d2f72d128cd0529090af3218ce7094c3eb5ecbfd0098bf6f0	\\x00800003e9fc52a722c457cec9d7ac0be313565ff1e45ab04cbc8cfdf8d2b62148c472ecf9545377eb2d0714acfd1d903c5aff03793785949453a0be9467f434a940f701aeb0a44e56763d08daef51239658c174542dcc45140fd80ebfa6f9f90774be2787814a7512125d53666fcfdf9187a30edc06496a74391f4be04ba074351140b3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x11db49dce6e13fb55048106ab7bcd21bf0a227ff0f52941aef92fbeacb99a1af5ed4b51b73d6b68c0b211606786aa0de955d1d5327cdac4fe38f02680f46310d	1615974303000000	1616579103000000	1679651103000000	1774259103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	116
\\xfbf82e9fef32fde24426c59170057879eab8c940f50dcac52f6f322a048919453e5fa3a855737eac931f57cf6401a044ef53d78b891b3913d67debd6b6b1eed2	\\x00800003d01dba5991313c6b08020c437cee9c16ebfeddea952ede4503684875f080e581992d90001982d1a7072ce39e1d46827a664e3b20a0aff68747f51b952082b42a7b2ef3efea6ea44e04653236a23774de79700ae3726e68db7a4ec0e92d193ba39f68b469556be4a586b16d72cb349e877395657a2e0d8736120aeb5169a84619010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd448e120a4f89103104d3a813af3a56e7802a9c9da4f7466369d5495f90bb1a31edf48af8a70609f7a6150f94ff05b6ab6377c202596794db73b1c579206ea0e	1632295803000000	1632900603000000	1695972603000000	1790580603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	117
\\xfd3831352ea8822b52e5baaafac1754d56508375b9c004957c743ce336cd9a1d1e2ea8c6fc450253059d35c4537d61afbec6520b95518a0d8a80ae917a4ebdc2	\\x00800003d00b05e55c1672627c4f97c7a7a35b0561454c400bb2b8ae83640c99ed3c771e73fc1991656f673174fdde77dce90f0bf7231b6a699a4f2de2d2769e1c6acfc47eb96aec568363647119e86abe24926f1e457df0b4222d652f2f3c0e0d65eadb230da41a9cd9cc9c0b322deb8106557c1551e321386bab7202fe7ec653434799010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8db3d365cb542e018babe0d17c01bfebf75466ca3cd8f0c31e37fb710f91eed99967134cefbf8c86b3f11266994a02a71c40e414bf01f9a5ac65c1fc2110880b	1622623803000000	1623228603000000	1686300603000000	1780908603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	118
\\xfe844257df2cd1f4684b07b4a1d340c5083679757af096aaf3d9facc359ffd7a26d2e4d0c36107b5e7aa4f6d462c30c71aa26d37357ce19bca07af932dda4401	\\x00800003d8bf9817462e16e8086e720d0e2af6cb05baf0f1f061814b9b377bd490052868cd36b5c82c681b0a497eb16bc0f45926f5f95bdf7ab7468cab60b47e791ee90f0ef44ffa73277d4d4f50ee950ee836458d9159b4a6a6d68e8e7c919f5a682535e3c608003d9667139ba37e103b2f72d28dfa7ba1d9168b68c1c1c29a72dcf05d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x032174b2256d0fc213e19d4514058024c482de568044fda52ffd5d2780a74e292400bef91915ace39ee202018d71542634703828b9f812e22063ef1c2d70ee00	1618996803000000	1619601603000000	1682673603000000	1777281603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	119
\\x02098ffab1d3a36e0a363c2c7a37fe296e35593211a99ce6a92b097c67ac9ae80035d9b0aa69c696b7eec2bc048dd26727b175d915f023bbeee8b3e199c534e3	\\x00800003bb35cf6fd52aa46bf3a9ca6386de53797246442f2976aadc2be48ec7800d7b3e559b148a761ad6be0c5cd03d1fc85210c9d2bca1ce7b583ee2d484049e8c01ee222f4f789cdd9511b0201e545e36ece74ad2e20b785531b20557255741639fed2ca1932ee21fbc4c2797c66560ad9a9476374eadb8805d0347e8fdc0613890fb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x89d8b55b8582ff5a73ec613529a017e9c686d685ce8477c75276261606ba4a75a99112f2aad3d77e2d6afab865da98b780460c4cd2965b9d6dee306f9b4b0a0d	1629273303000000	1629878103000000	1692950103000000	1787558103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	120
\\x0309375a7313e2dba97a38ec3def46e038adf72451da098b41da485352f7ba3dbdcd4d1859b63e222f77639836db4c3e489d088395b64ef238cc338989520f8d	\\x00800003e4da4ee62f3fb1e02923c3ed56d0bec068da16793be79e6fe682f5e28352b4285beebbc2c7e08a0383d74fd0b64041e194c1ca6cddf2ff93e2f0adf3a541e3aa1fe71d5aea496f0752804f45a8ba198442f12ff94e4ed64ba6b0573846565e208e0ebabba5766b9b39b5946ef37c0afadbed615dc14916e41af79b0eb2df26db010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xeb28ee365d2bfff5f84ec1808027c95a24d1c658e7ba052d1057b27058c240b092f9901d71f0ecd3d0f839b6d700170cc1a2b965df11f7be7b8b80a75be69d0f	1640154303000000	1640759103000000	1703831103000000	1798439103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	121
\\x05e54c3af0731067f07958be769689ce73cee90a6d46e8a5c3bb11dee4e23c5434be1bb6767b8b7a53b2371eb39c4c68ffba710586efb2eddf320674c08f9d7e	\\x00800003af90cbc32921226e92683ddc93be7883d871f96361984818b2fc700a1c2a88c179eae6b0e8e27f15de5395e2957f9937007ade89edaed182125425333df7204cd652fa6d96dc726ac91f63204821a8ca14fbe72804e57c4b37e305a00331b71ced3fd80c02a347bca5f5c93029c9eab373c047242ea7ad4e35feb9daa5699c2f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa0ca4d1d272e68b4ea00135dfb3b91f50ba2df1f4e931e0d0a32766013de8fe2cfeb9589e5db2e550a52c8dd55450ec11201731f3a96b37a3b3a98710093f208	1622019303000000	1622624103000000	1685696103000000	1780304103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	122
\\x063d8038a3391ff615a16df43680c8125cca2ea3cd8a77073cdc4a0d2c2ff322a827257cf097ae9de2dc059e89afcbfc273e7cf210f867c0db4694b33db66a91	\\x00800003bab13ddaaad102cd42307e3c813a7e1674b8cee816c0e40056bd0ea532d9b996c1486a1bd3a8bc70b16bf47754d4ae6c7351fcdc705f61514e6019d0f646a38dcd0d34c7e8e1e5b6b212ce664b742bbe4319e47b6a29f6a0294de2957efa67977e64b0309d3b5db9492cc7b73e98e6df206345b233cf1796214c3d5651e694bd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x975ef737d3c26f19b718aefbffb41b42fefaf51d7628d36d32b8723681944fca3d8f19a9ccc0c4968f8b76b3011645e8450097164b12278f23878b80ae510807	1634109303000000	1634714103000000	1697786103000000	1792394103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x09fd6ed596e7deb6805bfbf5aeaa8263fc9c628e033ff04598f128dc356a75540511a3cef96e2277b75533134aad4cdde5c2e8ccbe587eb54caa05e5bcd09223	\\x00800003de40346a758b63092365dae3a19f026c25eb7d9f704aa388a28831054da0f461ad28c98de5f8cbc10798623209acccc6d8c487a111850336907a90dc5fbc72362f71069005a0d174cdbe753286fa9c68126a3e5d29eaa51e89ded0b8923b719f2a11b177b403ff9f8174af984ac33eccd7cac8a2db8106a3a9b10f096518554b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xff25f21ebf66b5074175ac80291c73bc664e725bb24c79bb58bc5a79a80fa47b9ed29632a6454a00a24e5077adb5ecb39c6d334446c321cc6db7457427b32b09	1637131803000000	1637736603000000	1700808603000000	1795416603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	124
\\x096d7aac90848da65f317fb51517f7a83eb3c4aad3db69ec61d05d1443bd312e9255a5607270b832fb0e902dcdbfb8caad30fd7a11e3e8fcb3e35cdb7814a587	\\x00800003d546c8a709f3fc0c28bd080333556c794015bec3ce6edc99b59341e6133262649f3544f1202cfd5181de6ca0d94b99a316e31e56702f347a6f749a3298950bcab6feadc6df39e65b7fe83ae3e885142dc03d44905934e4c01248536849718a6494ab9da37393c3ca45c2d83f9dc63e96c80cccbdc6c6cfc9c6982c1f21361f07010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5ebb083ea3c73ae495545ddf6fae75b28d21039ea810ad9dc0de6cafa195cec694452b9f55242c4755fb7317b7d6e49ff13e1b46d3543c9a6f38e462f9cdd403	1641363303000000	1641968103000000	1705040103000000	1799648103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	125
\\x0a0d2dbcb3ac2be6c23873883a5c32b275a08c72274372a0cac0c8c733309a6c947173471e4e8d3efac4597cdbe76d5a526c091d61750192214051ca7f2c86bd	\\x00800003b8ec79dbb19e6866c601a285a9f0ab901ad1552daf92c292f39ee6808b8de51677006668ac68945e0ff0b9112caa48356beeaaf651c519fb8112d3101e94b85077f583124879cac868a20aba9d5472875b5bc72d3be407f402934285f5ea1c97751c6ebb58d97a67c6630e618c1bb0e31d6b059856b56f16d056415ca924e0b5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x73672eeb259e9d5088e3704364a3a76c85766e9858d832106118b6fc9a34aaf6a359d3fc9b6cbb514aca482ea4a4e1c4e58f6b138475a60ab80c67f101f28109	1623832803000000	1624437603000000	1687509603000000	1782117603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	126
\\x0b7d77bccee502256496a6c258ee5b9b575d505977d53eb15102610ca663085230510b8c2e748f81642d5fc06ef9d2ac1ad1e3525139ba74cbf5ea2d19950db4	\\x00800003b69f26c32fff623a4d325559f6cd65117b5f1e71ee42f55ee5fcf6aad0902dfe1c1174d33c5429d7c775f46df0fca0c144dc71aa0fc0e5217868ca4752d8cffd2a26d04d11415871c450b6a7851e6a74eb1656043f34bb4bc10567373fb9c3f185e040870c5e04a7e90b1921b1ac16e42dbb05c4873dc0e399a394884d1385c1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x58d798df4d079fee14ca42c042c9bddb1fa2cefc138a48b94c73213ef90e33424de34562d6c50848983789c473869f3be7592b93a2ebe620bfa8473aaecc2007	1635922803000000	1636527603000000	1699599603000000	1794207603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	127
\\x0f1165c4f644882c55f0642cd8d4e8052b771b3ea592b5eac0135d17aa1c3e74cc9c67a697b1c94777712686dc22b81829b8c86db9dc19f3ac68956583654aaa	\\x00800003eff3ad4c287863c6117455fdc3fa912458d062cc83afca805c9288c3dc1f942e5f2a3f1052823dbe7a2e060f38924c762ca9d6cda6d1c8c2e3e78cd6204e20c18673f5897d600b5356b9aa584fb4fb2a5094739637650fd52b668ac4e5c2371a611910c237d9fdb963e46745905e8052cdeb1713bde9d5ddea2bafab88930f07010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x97cafea9d7b662b64c6df37679941a2bd051091bb0e7dadd5a05815ebeb6ff376204720828a8a80d7db95776e4695e12879d1fbf1bda7d1b8416c3bf9b322400	1623832803000000	1624437603000000	1687509603000000	1782117603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	128
\\x12cd61a3d9246d6032bb8cb608318eaf69f100a9559a5a98f7ee42d7e449b8e149314516c6ee52f4d614a8cefd6b98936ee3da4324f78cdf5b0b2e0875e6864e	\\x00800003af06e2bb587c86d5b6508bbd1bd8765728ee7a2d499196ffc9cdae7c3fe2c4d657fb715f78fe555b0cf236774343c93edd4d5945f3ef06e577469c67d4a139db934842ce146f1b16fd688754d5fc4edfadc962b847dd43eb5bc1e2ac8e32740c8a9ab8298515687296f5d649091763fedee5fca6cd1848f1e4db76d5d741c081010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5e8ce8c0bf9a4677e90e5883ca1b8cfc79c28a1bd780c25a68509046040b1a1aa74419786edcedbd7cc29998b451700fdf81ab5d2b8e9c1902c86b8701f53b07	1635318303000000	1635923103000000	1698995103000000	1793603103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	129
\\x13ad008564e1f9b5b60b9a3518d98c41944cac071d461586026eee6883d7302018a6b459e0e8071b89e9689ed7892e9d8ba44646f9533441b5dce9539803a977	\\x00800003e517983d6a684018e244613e295e0af2610d26d36742796d3d54a78eef4c8b6cb9ddb0323d6ffb5d6b82e7bcab17ac62cc299be4462a9b7a32778b81d6fa28e4a75412a54d2ae7fc0955ff080a18c03bde22b1808affd0b42e565771a52fbd4db9d1af7f90c9f9d42d38388a1bbb33519d0ed0082d44c3a8d12af34420e3fab3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2da75728a302102535f5371a1161b8bd6712a22f425a487ec6c53c0feff90592968a27301470e46ebccdf3757d739b222b749e91981f693290c97d72993a2407	1612951803000000	1613556603000000	1676628603000000	1771236603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	130
\\x14c93f12e50e1e0adb52fd4e7c11169425546d3bd7f84b5a471b398ae3a575cf4031b82877f241224843fe00fa74576d3499dbe11b2b94bc71bf342d51fd2695	\\x00800003ba57c7c52963bedabf2f22b7c01ca7f3e1136b6b9e5f1c9466ffdeae929f6af7cd6d0a470579318dee5777c960760d7d61fb7f16ea37de9002a7641eab340a270fbf849bc5751f7f0c621b4515ea41bb2403a7f3f644ac2786f53ff47595b7ce0971ecc012a755ecee16561aef490aa8c160c3cd1e985013195704a5e24f9dfd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x15ca56aff185c04d7d054acac1175615e06c8cc6911733ea3f914b78194f8e469a20d9442480534ee44b0b5ccb2b5f60a2e67db8264c87b630d954451be1c402	1611138303000000	1611743103000000	1674815103000000	1769423103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	131
\\x15099fe7925f2e544de2d2c5fceee529eb10d77c419e39ef80cef6504c601d2d68ba0d360ff576cf85dfff1878505247b82033e0db2831a27425da28e8b5c9fc	\\x00800003c6990a04401fab7c6baf8e08131d5ac08d19ed02b30a00b54230d2f7d2db863f725d81e10db3d6cef35616a39921e0dbfad1041ae6d046f83790e40f73b4c623edb1f129a10ab750b382b97f6db9a24550036785101bbe11f29fec0467d524d08b30718e811fad7398d04306e0f1b2a18563b21e0d1a0c61d4820a416954100d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9526c44b1e4a2e65cff9c2000f056a9ad3d85372c461ef6d65624f8ad30cf53fc383ccfa869dc9b44ae693302c290f84ed6084d33ecde0c0f72d065d36d51002	1612951803000000	1613556603000000	1676628603000000	1771236603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	132
\\x1525e167625c9ee071012db5e74a7c112c995df2f74ec176b6ad2cdf3f39ee997436e406d48b03bfb95ede31466e74f4f3ea33fe434bc3bc9e5144d0a16f03b0	\\x00800003c898761d178abbe8fcf8420716da901ca4a083190580346a6d0119bb0b1348e0402e1daba0d44e131dc97ebd8fba1eac09a9fffe87976f2abe06b356661042c42d5b3dbc9d19b3415240db95712ddea67ca57935416b3090b43e17df09b04d9fbc89df3d947879526a78af96f14cb9f8155ab6264632543653bdafa96ef732a9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4cf5530083718889572909bd9fff765abe4194ca2072d8608080145659ba303100c29d98256b3c3163d81437cc34cfe5f292577f3eebde5b038eb3f8f94f140b	1611742803000000	1612347603000000	1675419603000000	1770027603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	133
\\x19fd75b125ac5f33d8a4f02f37f217119be5c0f039f78d55a61d86f5062e9c62e2eb81d14ee733e4c38201d8b4b494e59b56f158f4518db820f363080de772aa	\\x00800003bfef4084372bdcc246cabf1febbac94b9e5d96e2c7c063fdaa910f8758386a4a0e602249fc4818f81b9f26fa56fed8cfd8ea6de8bb0c5d23df907fe268b6771bb773f6a290253b42ebe4d400d4057ee226816f90a789312ac13e3edd8d3a961b906db4690e35a349264b615c6b5f3aed8d30d706474edfbeaddaf79f1f27903f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x16007911d3925504dbdb75832e757732b3ccf76c6cd57771b418539332073ceee67b2eeaa49bbcecefb9387f2ba318d81d7a2cb33d630a5174e288a6ae463b0f	1620205803000000	1620810603000000	1683882603000000	1778490603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	134
\\x1d5d6a28dcafd622d1f95feaaee26ed524db44cc266703fe74aca2d521e71a00a687eb7b8cbb78898720ebdb5232b37cf8539ef4cb8443aff56e1f87aff0a64e	\\x00800003d2560e8925c41c0270e488ff01ffa15070362ea269bce99d8e4e4862837db997e2c79ccd7df8ffcdd6f5d220e3af1f4ce99231dd09af0f7b8a242fa7661bba7dc4a8a9de4fa7f44b8c098faf9c17bf94e050d73267f8d6b1c3557fcc7dc0a53cd08a68d1c57d5f6e22a1d62b712d6daffbdda3cb57bf0ba7528b898e98355939010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0578600e26df39a778340a3e435f4d5d0a8242733fd701c6898c57d6ab609d14651f753851c23c6165c09cc160be285a5ba583ba5a23851673c79cd56d97be08	1629273303000000	1629878103000000	1692950103000000	1787558103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	135
\\x1e5d801d15f44840bde97bf42f1966e3c44940718d9d9241cc48e4209f797edad8b2578ac7963099a207bb7fb88da293881f07d9cd58e06dc2a753aba3608957	\\x00800003a7515651a63575319c2152d7d545ae4e8b3fbb08c98d51718fbd05120a3e9d27980565b9e75ece12b9c15560301462c4bdcd1c319bd1c0255eb6fbd0e592553ab12963818a0aa394c09003d19283080172f9665825d9287063adf31d6425b47246acdef7211ecfd121f8fede77daffc471f6787d40022d242bfde5be8a372461010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3d6005cdadb4be19c5dfe6ca1a2407897ce0bbc55c40dae37e04cd80a1cf084eec46496f64b41e16d7b4b9a20595f6371520e3771487324457683d51b9e9ad03	1617183303000000	1617788103000000	1680860103000000	1775468103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	136
\\x25a9d3054585bfb214c15a039bb93ae125f9f32feafb0a462a7822d173612af53915084b0466e2146ab4ebafc98618bf30be708c549917ee52b28780147de04e	\\x00800003bf62f021baa191bd95d84b9e3cac9d14fa7bdc99245a82d549f458ace74380db1b49fb707c9a1389e567fc896335239ad621ad3ab431484f7ef32d8fc214301e20173e6a726ce239a2a66ecec818cf9b2fea06677c233caadbd01c2ef12630bcfc3dcb8b1e01aa7b5b22e3c66d473460243d8ce5103078a82e1d1d5996946f8f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd1abb811634f7be9c1321c345408cafa4713a0781499f79ada9306da8199d132e681538de83f7b703d4a3bd204ad122031af9eac5f2954b839d19f2d6a2e2804	1626855303000000	1627460103000000	1690532103000000	1785140103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	137
\\x290df8a7accdf8514c093ac97d806754cd517e785f7249ad2a9aaf59730001745556be995d7643c347de37be82ab59deef08370dd2f1872f23256e3160589ad8	\\x00800003e4c30dd6328e24aae6f7c7b753c9db44f3b4d392ecc4140cec776365405665c8edf2b4e36aacf36582fc9a7d84f8aba374aa3cd69d9f17ff11403c549e3f17dc99f5702d3069fe309c57c74b4954d1ee480b5c6dd9d76a02b95ad04a01b510b7ac8ab272569f1989f6f0b32b10042430a943ef932b326ebd6a806e92c4903869010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa0461d6ea320de6e46bd50290f3d9e20e22775ad5c9aabe4515d1b0a8810496645389120d9bdcda3922c0556b32dc60eba8e3ffb3b68f2a027be325b9a3bb902	1639549803000000	1640154603000000	1703226603000000	1797834603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	138
\\x2df5b6fc61b48ee143991b70a16ee72ead1c74c520b289be3fe854fe04ebe58b294fa34f72a26458ab8fed05b2891e642c1613cb8d472e896d1d361f8537717e	\\x00800003bdc106fe3bcd24654b80cb1b00d42ec4395e1f6f15c3b9b7d8ea08cbb1365e57f389fddcdb257420244d04d63cd0f566ecf14ef47f5f9bfff4e26ad955a9f8be1f838f40e284786af180e9153f60d265b7e4117709d16ecb0312ceecb73c0951aeff64a7733b757dab36c154d38aaaeb7e7f89cee5b00d8c1c6ea0bcdb690825010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfd31419a1f6456316e452f5cf403e98e82ac981a0e04f5f5a092ce83e75da9604cb2a8db535d9f76882807059736e1f75b149364f3adeff8cdfabef12b8ef602	1631691303000000	1632296103000000	1695368103000000	1789976103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	139
\\x2d1db99722d08ebb48d6a72547760043ae831bd8b8d22a3dc5a55c30a32f5e2504917aa3840f040b990b319c211dcfd01d94237d59e1869e69095b47a54e21fd	\\x00800003ee363fa22ab6dceb61ad01557f09e03119d136fe271a6d1094e71f7f0949b4d498fc4542cbd9a6182ed733ad1a7937cbb72083df1255977ab039381a00c0089c2e1ce6476f979335990cf6272ed3009d5883f3927167aa0aa0dcdac40ac572ec953f814c920fbe34c85c925b744f629f2ffb26c9d6c48ccba1a9e9a7ddc89b3b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcda38ca4ab903c8d27ce228febc6a2020021e4f87ab31dbf4805578afdea15b19e100f147200896e04a740399eda57aad1f749759ab3ff1ad5e42b1e273a1606	1619601303000000	1620206103000000	1683278103000000	1777886103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	140
\\x2e69ff8f9c4931c8387ac7868c952fc40885e865007518a394297b27bf8b109363af91f123dd9524559dae60f3b5e452476da4f35909e3396019da8ad64e4e9a	\\x00800003e7ad91e129ff17076e89524ef4f30ca7b32b2a33e00ab658bbedbf2ec8fdbd0dc17382d1e5ce2eba44adb9a6db31addcc1ede70998ecfab611ff60f5b3218b3a61d1a02849b53cde17bc36131fdf3632e33f6c625ab9e0c0a5f3a3f7c4340cd82131c86aea517f31f0e0465608e9fc634b90505939d2b7fcb1881f5ec19c4f9d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe774094f065af85b4653f5f4636c6b1235e37ce07d4338db44d732639a7e773eafed0572599a87fe8a67699da2d00b720c1f6865fc2b142e962da01c43134300	1619601303000000	1620206103000000	1683278103000000	1777886103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	141
\\x2f85f286187072eda66423d0ade91f617860db0e3f3d682a823b3669dd9e3aefd949248bfa73e4a5fa650d62b45f66f944eb156b56c796a7db7f638ea305634e	\\x00800003c7d7b7416f85880eac9fd62ff0d352ad97881c0161eb59ba2d638c2a4accf4adb5ec8c94066aa48cfda0f155001ecb9641a07dcb19664ed7aed3a1abcac408bd24a94518623cfca7177d317ae683fa0b1b4f4d1f72eac3d853f4ef52d06120405a18cfc633067c955fb04dea72fd1fb42f973605f26d6aa022e1c9fe9642d4c1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x73122a9cc4d2d80a07a0f8955301471f31753fcdc8a305d9bdc1f92ce988d54eea2e487be5f9e73a5d25f004b2b8ab461de7ad7dc7c5dd997348052da1176607	1611742803000000	1612347603000000	1675419603000000	1770027603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	142
\\x31b5add97f25a67bc7293ba5518cdd285360a4d1571293f6dd8056feb22868cf1303f4bebf174dba01068b6f0514c4e1335061f301b318021297bfc76aa09cbb	\\x00800003b9a7761f7e91f147f5d7b7cf49a410e75c317644414611a503a0b2f1c072e3af58476cbe36ba2775cf77981976cec2816d9c78d3dba41065a522ab2367457e7c8a43c6b4585ecf05f1b17bd13fc1a77cea3ed8dfa28d5ecc46ee3135ecf14e8c826024399b6c0a6a3f17dac71e4a5d0d4b405cd8af6c118105034d57ae37745f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc99a3e1316df45ab0eb27d0b80ad8493b40a776d6e65f508e5ff43a1b4cf6db5aa4000f17e8cfb650c9066c2f3dd0e07119d8d6d4db59b2cc7717e894453b100	1622623803000000	1623228603000000	1686300603000000	1780908603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x3321971397dd9d212e57fc58c90c7efb21e4c63154eb6b2f3efc7a393094bd07d9bb227233b88508b3a49e5e68b31938a44ad4f95352d843f00a2d2b6bd612ad	\\x00800003d7c048354b12963635ff60a82a5c9ca3dbed4a79a60a9dc15d1aa15972854b77fa49b61c46e25b28adc863c083cbed2e7322c4b69c8bc40aade6b63c1d940d9f442d64cde724bb945040b089ac263bf9f8e40556fd13777531a36b1c88dec1db3646b170c43e123714eeba9b2fc2ae696e32aae045ff359f28323b9130bdc55b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xefb58bde4ce1b3c2f989e41fa3b1ba31e9bfa992001aa6a1fc788f9551903962ea194e3ef68531607b7511ac5406371297b7e77557673bf56ca79216128b9a04	1637736303000000	1638341103000000	1701413103000000	1796021103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	144
\\x357505ae132a970e1e0c4a094369ee13d8a8599715f8a3160e59c7488218feed71bad974e57ac0396bf7539931ad76d2d809d361268a8e62282277344e78a30c	\\x00800003b21fb58d821586c3a57441ba252de1916b13b5f27985352a05f76b900a13d981fee106acacfd531eca0dce92acab5cf72831d2fd433401f65194745499e224ad13f7f0ae37f168141105144b20399347aabe63e5b860e668e36b11d6c7decdcccf1dd95dc0b592a4c7bb0fa0c55962bda035e512454b7666ff2c8bcce0fde8f7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7e82597cfb563848dd7007b808524006029baf5345c43d4e0ac3a6d4bdc7cbbb092c1cff849b57c74ef29bd5ee436df6eea16735be63617372757b73e3607200	1637736303000000	1638341103000000	1701413103000000	1796021103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x3af1422befa117527661150f5bb9682d002a50a0ab312846d6ba73672ee866650375219276998c52230cdfa3b751400dffc3adb6cb3a4df2a4ec81aca25fea1e	\\x00800003d7bb18c961721c6ee737634a6dab09774d5d310afd3a29423f49956d14391d3b3fbf9d946273380b568b8d490d44b7cc09847be3b8c7474e2e8c0d9675781b6616418d588a65f5540f43b7c9f5a94d901bbb50be9456ae0c0bbfc0709f98f6708a39f5c554acd865f13d7eca641f5e049e385b92f30ff5b61bea39ab5023f359010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4a3380dea53396476a719ae225ec21c5030de1ab92368c7d8abf08b14eef46417a4c673b2616e622917004ca081a4bfcbc4e32961bde857b30618722e312ae0b	1610533803000000	1611138603000000	1674210603000000	1768818603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	146
\\x3a31f32073f3e926d13973ff93fab9208509ef59f97fe0b082765480c79376c293d4edef45695c7087d8987215c405eea38535830a75a0b2086a12fb4b517c95	\\x00800003c43eef5b872543083e891b585c451f5e984107941ec30bf5d7cfba2b4fb1799e1aafe0fc9ed67fb98ab1f2bbe0aa597c34d0ed4bcd4a117e53c748847db38aceff8ca682924a0624e60ed8ac565ee3c4bad6a2c3634d74f85f36638d24f9719f3aa3bcdc318ef4ebd7a56836d8687ef404e8d5de9c05ee8946000e6ff2b19f4b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfdcc2c025ded9ab19eab9f805cff86aa4b2f7a9af79686ee129c2139bb04f0ec882aa70cef67535bce55b79e3bdf8e9ca96c15734621972b4b69fc8e5ec95d0e	1614160803000000	1614765603000000	1677837603000000	1772445603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	147
\\x3be10ad71ab1aa4a2902aea03fab725b38c9787ea858b7b0cdf3678a3f4ed282d41545f230a03cd13c47c82f9a86216fcddce93bfe833fe3f3d3e6ce977f9e2c	\\x00800003d699179ea5ffa3bd59b189746c040d5a02881bdc6776e3eda078642169c6d1bf67357c53351faad51e445f0d0a5230594f7a37ecdb60e10a74449f8a71b0ef1d1b4208e21ff1664e3f390affbfcc812198323abd290ea66f29f362e3fe381be64c33058b17f7d22b57359c154c468467c1d0329c123c2d879b68129e62294275010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x254e6998c6a2bfd2065326d3cc3ed63c3256e967c31432d0a47639dfc2f2d738ae575a53bf7f05750f8f527e6c196e826eab6c13e1a15833695ce26ea3468b0f	1635318303000000	1635923103000000	1698995103000000	1793603103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	148
\\x3e59eea342d5b4b3330a7d1fc6db3b7266949640f01956e87c06d5e6528aa81a0d678d492997ab10426345bc7a3a7b7347bb4350bf715582e73e4b4b20ed5106	\\x00800003c01835c3848285a1fea90280b78616943a2828227378f4c0794eb7597aafdc1da3e781946c2c079019633686610e86ded49d18f5b13e6e5777ad80e52115cd4cab16481c632425ad3cb9eefac2a944d8b98f986d0b5d03d1f66a6a655d0c287caf4239aed1df9c3e489bb882b76975e75d4a2ae97f4b51b609871191057dff0d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x17f3a591cb5047685c144b5ea6a6698f87aaa083670161471f2ca86a5b9b8a3f7afae4037be6094b2640ed0f113e52074041cc6e42222de34430a0f9adf83b04	1633504803000000	1634109603000000	1697181603000000	1791789603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x3e3df1d440aa77073824ef99ebfaeac42dd9c94d6e96ed13c9c9f8795842154c3d72eca07737beffdc12d0f161e1f1bea8577e01cc735543dcdbe6d9e4a43695	\\x00800003bf9a773de1e059a5d58217b40707ddfcb46a3941326755e64fc4a1d07b626f2985f367cc141a57135c092177de4c46cc26c95e891ea3fcd2bdbc069351065999c8e942aeedb4e0f151b2782bc1fac55a7419c6e10ba2aec3106c0df3c1b6d24dee6fa0e54ad7b5175e4044880ce66aea42cacb47452e795c4e04554f96b42c31010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9e491657c9033850a259e74c0a336f3d2519dcee95100b7aad9e129e382eef50a107c83d2ce2474c3d71dd25fb91d9b9c78f4604657913d01498e91cffaad808	1628668803000000	1629273603000000	1692345603000000	1786953603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x41b1eeba24f35203f4f0b500a46069badf8f9dea0f2de4f0bcff745aa2d5d325a24457c2bbb9d3b4e26630542dd77473527e08533deed155c190cfb4397878be	\\x00800003da5a075ae68b6160f47aa35f3222a649279a2e969635e14fc6f1033565752ac8ecaa902f855f6d13f2421ca687d3535275f325c11397d271a7d021389ec5f323d9bb4919bb491c985ad39af50831747ba7086366b4fb70fdc2e578a3d83f0b443f3606f9d7c68a8e763d91e6ad0c4260f84ef9daf90278b13ca31b5500a3031d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc6fa711e971d618c9490b9c6eb918442ea7d06f7732ed42ac48eef0de53fc7f0213eb9ba8e70b95bca385afa843c32496303822904336f6d00c3760ba4948b0a	1638340803000000	1638945603000000	1702017603000000	1796625603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x43216c92205cb2b6d7bae2b8649bde5c59378e518d93079d1f2d2b0c6803019c7e2c37c034fef891d5eaf8fbb1de32cce7a3fde468408d82c083d97a6cd1addc	\\x00800003bbce980f6d8d9af74e596281170cd51b8843158d62d8a756c305d3c733cb84ca40408801e5b7e9f331db393325f0c00ca5f4646726129e793a8f2ec2e4d55b601b98cbd6cbe628f5291d37bcdca748ece227214003d3fa3931856b9a83df6b107eea85c04c2080c8edde756c10cb87c7aebdbf2eec9f11990dfcac1724fcd329010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf3252dd6d735719c5e13cf40bdc6d22444b33a1e4388ca7ac6c8238fbb8414be03b13d6805ab72585f12a794c2eb2abcdcd494f83f9b8f2038db1301ffe1f701	1629877803000000	1630482603000000	1693554603000000	1788162603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	152
\\x43ed490136ab390fa63611cb7336dc23e7ba74c4cbcebe813484a7000af82b002e48ba2b27dd4f2fec6b3fee8effc1c834315bff2730a9d1b79b140859b5975e	\\x0080000399e61cbbeed019439b7e4b50b8f08cc25ab4300aa177495fcda32d120ea914ce0ab7de27f2e893376eb3219dce7efd0454968b16b03534c4a834281c78f96a4b4bc0e384cb1da88e62c4c828b97a3abb219f826ff2dd392e50868cde2c00d00d52f3d9536e25651e5b210644221f1d0c705044f958e23e4cce092a84c9e50247010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe251e1302d145b47d37c784e6fcbff2cee09c5bcc25afaa11c21228d16b9ced778b0fc565c4bc471f4e9964137182e1adbc574f610b4bc6d684df1d9c847a70e	1615974303000000	1616579103000000	1679651103000000	1774259103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	153
\\x4549e5346143b92152a57d683060c4a4df03b26f6f239b3a5f244cf0dffca2d9c201fa5c10cc2e9e0c51dd6bfbe0a8ee903532d27b05ba0ac373233f091d7150	\\x00800003c4dacb7f382d63d89ee2401a59981c5f7794eee2beba2710e59104214d0467267457f35b4d307e6c755da400cc6b379db9794a4ff62a41694491a8949d2779418baeb26881c6e54b65927c465c40eaf3e3861583f525f5842962e74ead51edb5675b979f75dd41d078523b59c35f05839e726a8a905c7c663a73bc596f6c19ef010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x08f6746dd4ae73da011f1d2f21ba2420d830da4824e8289357cbf4858a7a67c01e70401f691a0104154e4c00c8d0ac0d3df452deec5f40fd2e87407e36b1fb00	1611138303000000	1611743103000000	1674815103000000	1769423103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	154
\\x4535cf37865664e58a886184bab3ff1f8b369c7bfc6f4d86ce415c002bd2b9cf6307df115c32165c479558c3841e6619772704dc91342049189bed4437d09d65	\\x00800003dbd2395dadaf2f7c79a1d49b56109bd473f0ae41fc7532365a6f6181327f6d7035e8f716b26f2c5a8a8dc3d99c8b501b8fdcaa3e2b86d7258cfbde4c365ae466046893a19c91d51a72031f648e578f2e6db631792d796634c599e6a9f5bf02c464b0b59b03ecf71cd5fe9f4ae2610bf29ec193cd355a50db63f8848062f8492f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x80cac303d1b75e10d27dbd35b093ed6897f8b62f65c8367e89b8afe270732134e9372d0ee62bef8e882e5cd0339b1b804336e7500bceca720e7126f10375c302	1639549803000000	1640154603000000	1703226603000000	1797834603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	155
\\x48e9dcc0fcad0c686171cd14cc28150fd39c7003805a700ed7a58b8f37e0311bf61a315a1466c0c36e40cbf14f5964050e46101068de473dacaaac35aa1f9d69	\\x00800003b6d2f3c8d9814f926d59293c9102b8195f1ca067e96ce7718cb45f29369ebc183c3dfea5d9f1f1d87c223142f5231aa4a416ca1121b7c5ce6844aabb04449cbc498503eda0497887cc871458a877244edcabc0e79b9a7f81edfa0012e37dd30ec6bb00fd641f97b0ca1af1fbd8ee53b4b409afb2d90bffa503f30cd116d313f3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x58dffd823e5f131a0cebebce0e694e3ebb5291a12286a7e187a33222495c47398bc48f7c63238e0513af9577d9ed0888367a304bb52ab8b0d8e59d73b7631d0a	1628668803000000	1629273603000000	1692345603000000	1786953603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	156
\\x4a656730b15bb65b82b6f7d27e56fd8bd81e28c8fedcc764f3db189a5fdafd0e95583b5178591cd160ecb1e79ad2229e84e10f589a45fb98016fd33c8c675191	\\x00800003baa3fc2a5e74ca9ceab25fa02c48696aabca1e9e645c0dc3140df4456dda85ef2c4f240211f425b1de6f3f6590462346d0627343979b162ee0fdc0be4fc3248d0858a9e7e2c0e6934edfbd2775d881ddca5be58e2626772420cb8f8804efe8dd146a7dcc5a02d62330251b5cfd41b2c056d3d0bd65384ee562891006d936a269010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe87d93490c523c197f691c93d9fd5143e4013088f0334081a7d734995e668a1c6276a715bffec7e4a17c315afb781f54876b46f7871fc6f8dd1d5da676541509	1632295803000000	1632900603000000	1695972603000000	1790580603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x4b19a92c6043bfbde8c5323c0d241311854a70fdc68382d65ccee869c9bffe2e5935a6a2ecbd85347828d55f53c16fde863219f875709a55b31ea6674a925c8f	\\x00800003ac1ff89da857359e690bae739e88ec76f13a5b77674312746d01e64c2b9d75ed04b259186c3d81269c93c8e74d9b76565feb033bb091f515c4dcfee1492d4df01c359ac01625bf9e349ce8d3cc8e33fc23c10ced24764c44d6cc9bb98986248126ea9e2eeff332201ade6b3d6e4616e7eeac5ab2e4ddae6b9f15076a561531a7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x97e8d6fe57af1dce02540d2c119ae54d8a6fc658f4736217f83adfd2fdfe70e1246039c9a15e1453d6a61acff27e780d27dde52219707212008b03619b8b2f03	1631086803000000	1631691603000000	1694763603000000	1789371603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	158
\\x4d75c4726dc560606ac4c8dc9fcb12327f091c1933c53519c00b88158c08d147bbc7d398b513b4933c7c757b16a463b8eead46f379437acf3a31e0be0d6a623b	\\x00800003cb88edbc5d9403c17415477b93f7107144c61ec5ccbd060630ea8e397f7084a7819b7b0c4e9585eb93ddfe3a091e195f96ea22f88ce3d0fd8b7058eaa20e1e0317cabbe3c5aaa1a59d5ad404cdbeff9c5a424100ae01a68fdf22f7892b6acd0e28b4df653da9aced31643ddef8eff9a525dcc6981ef3590a270b80998fdb2e07010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xee9b669ef6941545546511de4800c29fc3a23e22270b9063e5f0edb77c2c91e7bf01d4269868d010f58c1af6d100632fb3911428c7a622ee6f26cd0e8eabde03	1615369803000000	1615974603000000	1679046603000000	1773654603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	159
\\x4fb56778ab0dd3a6b48d034eb89d8d6a1aeabfebde587fb59c4cec7f50b0ff11aec2a063b355fe2b2db2f04b8bd6f9d73e3b7ef830d6716491902c7b56cd484c	\\x00800003e3b5b7ec71029efead882090996453fce9ccc8b471f8aeff51852ff7716461b68d6ad6bc882a07179244c10c7ad8960fde14da8e2be3b71f604a189d2f04987cf2a05d991ef3f74927ee9f9d00b3be7e54ec6a53f5bb52f9c78089aa2a0df97084157266f42e3e953ffccb12b3a27a4b54411dd68feac5d0d976d947ad9c51eb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf0c8c2ef594b482646b5a20c8f55ae2c65276d2520776f630331bdfff96cf675aa7538c7f78f3d986b9ebc7cc97a2a14802874609f5de99e4e13faa1ff82800c	1612347303000000	1612952103000000	1676024103000000	1770632103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	160
\\x5179291e2b74fa0eb0c2405f2553b0a34a609ac13e426b5f64b531f443f6eb9ba6560a77ca7003ff2d3ac3ec7253e048173ce2d2f7391daaf192700b207b3722	\\x00800003adab29f887d918cdf95e223165c0890007a36e07ef924d718cf6fda6992a5b84aa88f3a93dabfe3d4513162086798a0f03fa76efdf1ef0a24966732e7d7f00c3a436c2409509fb6ad27309ec2219bf1495c3a54e778c4df488425f57edc61669298c7c4c14740ee2c40df45808fc933ee23bcd2e58f336834929eeeea3207979010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbc7a1d9a2dfcf207b5790baefa7711402f5285c448709816741fd8e1afc6877f61aae672ecb6f9a924ec820962d97144750548aa1dd7dd48d3b2e01696028e06	1621414803000000	1622019603000000	1685091603000000	1779699603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	161
\\x533dff9bc3cdebf1ad65afde43fff33433ed561e2cbcc604c12f8c344427c4821daef0f6c5abacf9c5a70bbd6c8877540d204523754dc378872789c4874f0b56	\\x00800003d405e60ccf29c1f5e468832810888b9ef90da9182ab2fa375131d3773ce0d93fd40c8b582d21e6ff335d72a5164bd2816adc382ba26f52f0ea8a360562686ff5141bbc65090a45fea63c5b9b79982c7fe42437ecfe92b27c0ff3d6545aaa0cba988116d77121be8eebe45d53269059613c0df195f9a548d33d63fceb37f9fa97010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf2c16a60479be14b7ea70e9edbfb0dbdf353bccd0a94e6752a78a516f66c9de0a0338873c9c0121fec48700ef3a0866848d01fb7f327ea35b43673256e0e8703	1638945303000000	1639550103000000	1702622103000000	1797230103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	162
\\x53099f8f3c047f15ad7808e292a5b39a8e6eaa08c94af19ac7b21025d9ab02d307b7084f051e7ab684830d8287535e3c056e51f4ba26ec10305ec14316842692	\\x00800003aa22595adbfed20fd0f3b25c0fd938497c0f07ff48b56c6e52fd01902ee3b4add3a12b93534ce62dda81f7bccbf32e07958bc3481c0348c7eb2cc799a4e69ddd4d6939e3244bcd1e458a2f9fe6b8f2d2346c5fddde22403cf0d992f181cc036b34eef85b9f12b1ad2abce3ff691f401408ff691bfe28da3050c8d4f6b425f015010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x639ed4020f3c5557d056f81de319f68e2dd1f1c0bde8e3a07b8bb082d542d25ac81647537e35bf4a38ed659bb4ea7130ecca2e59ce26c94d0b1b761b8517d50d	1613556303000000	1614161103000000	1677233103000000	1771841103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	163
\\x554915d950c879015457d6bcc322c624700b94d893967fda0059286735cc5f334e0df72ec62ea11b6a299e373f120c4c1ca6d55aa6f661de65ea7853ccbdc9a6	\\x00800003c5bac643885b028e935f27e6fbc26e3a5046bb0dd1800b824742bbc3466eb4a5225a71fa960720547cf710311a536361e1b822f49c43c39c655d907ebd60c12d8d4bfafbacb064b5da771751d38a0b6c43d07423367e36888dcce67a62a66f2594e00c04c7295e58aa25cea8d5f41f24985bae0c0189fadfb2c281ddde831a7b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf0a95ead5a095c75c2f3dbb546a244f18a5d6cfe35246b730a7d218141136ca883afe39d17f451c365baeaf2491f5f99757e82ca3ff98be5696653e1e214cb0e	1615369803000000	1615974603000000	1679046603000000	1773654603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	164
\\x55615682d5f272b10d0d0fb374ba5168be62ea8b5f3e269fba7e136944202142b5b816e06f89f3120717fa4542fe6f42c2a26f9686283d702b4e37e41d366c5f	\\x00800003f33bfb614c6abd44665ca186bd0e1f24adb23f69b89f1aa5272e9e15e61dde1448e6275c50afbdae20651b2ddf53cec34c21da73cea0ad0b4c4820a3aad9f83122e0e1791c12ce11143547e98d73f992cb1958ab298a74d64f4b3d36f53aaa9146792eecc32112222359769443217cc093a33b8668f1bbe97f63a844997eb05d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe0ac1e81898972fc7d989297c16ca2b8a695402d650d7c4588dd28ba13058f1c078167fb83d548b2add8e4ab8af407058145ced1ab5ed84f0813ea1ef2a94207	1618392303000000	1618997103000000	1682069103000000	1776677103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	165
\\x55adc5cf6361cc14d872512ffee922aa8b727c2820648744096d6bbdac91c3be2ab8794f5c7376899da9453ea6e1d241cd6f66bf1d5ba9929f450232451007eb	\\x00800003f26ca92d5676a8c8005cf4839026dd9ad91696f11cfbdf22616aab6b672c94583496eebefbe8855c09032c15ff5feae78f9a073e85ed705e449f87560876373b00cd0d12ed0229c62b2bc6b7c51821abb2975ccd3fbbd6bc7ec8bed972dd3ece2115716f468e22d1d507b65db688ed94c6fe9b12237ab1afd30c8b1b23bc6605010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6a11b55e55be707470d1d1e6798b2d9076e8b2c1c8b1a09134855ca1e1d89dff81467c0f81573040c5dafb4d6f04f5c3cf2e24517f6903ef12a2387705b2df08	1637131803000000	1637736603000000	1700808603000000	1795416603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	166
\\x5a41b611c377c1424fae72c4c981052079c9b1e8dcf31784b51b08136c1a815a0e4b0b81b62cb26eff43482addfef8ea463630fa5684ba63b6db2bba7b1ef0b2	\\x00800003cbe0eb96721a27d72a142b4e835388e2069c2a837238eb779d6d08bd0f2859d2346ffbcbfd2a07b1f569f7f4c55e1e391269b46d821b29f59ec883d2a6e1ed616ec08bb0e2aa88ffd450cf26a7566408b2126c792246897252ce340e002e0eb16627a43dc483419f494a736d71896543ee784b0f0c3d31921b46f18ca4607d87010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4cb25a4543b11116e5163686e3347a9a4f050b62bda6719808c6a5e05d6b99b47bc6bd70839bbbf2ba5d2da1c6fde6270da06323d455f534523aefb5fc48290b	1627459803000000	1628064603000000	1691136603000000	1785744603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	167
\\x5a21f3b22da9d83d74d848a9a7aa24d9a472697cc207430fc6cf04a01938b33d4c75bc6e84cce764abb469dfa7956a5708c0e3530b3f5aa83d1b8c2bf4411022	\\x00800003d383fec2eba967c013e211a56555754b573cde7f16f04055552c3801028577fcfc5db4173a2751434e1b676cbd37b4a39fae06f759b6da3cd1eff7e5c129186da1968e8aea6e8b537ff021f5d55478d7e5d578ab18e47c3de2564985edf116a9cf7d466ee674fa986e9d03e76e83defbd62b81ff10a50f117a051e76059caa19010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcd9244c39bf177c4bd8bbeb4464b50d8d9f39d7319d06e2cd2583524b6410105fc46a0d237e4d94b0591e8f5703c1f9210648d5dc9d271de4f7a435477fd6408	1623228303000000	1623833103000000	1686905103000000	1781513103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	168
\\x6071b886ce9ac1cb715805dc299bfa8ed7a2762a538076e67a7e8e5de50b2f5476adefa68121aea2a76da74c4f79e6171f4a1d931da7d3274f5a409e16aa4bed	\\x008000039bc2e2919fc0589352f2564d3c018a24a3981067f47689bf1c96fe0d612a8c7e0bc6cfcee6051ecf169f63d8946f026677cc54713739e7b3875bfe00f16a430271d0b6d2b859c77d00b58ed4f5747b40867658f53e372f6b26b0830dcc4808700847b68a25e7d0d9b926f03f16e237323a47d61e7526eb06f32e606e87d430f7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd0e073884930100aca4e45714963451edfe7bb158d3d7c95f785b0bf83ba24a0c114495045fe731221837c5be31386447c3f500592273b637165f64cfcc7650f	1617787803000000	1618392603000000	1681464603000000	1776072603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	169
\\x62518aae65389e97daa99d9135de0468e1ee04a9fdbc117d0d5499b95de2fbc70c57b11359f31a1cd3ca536e2a5c2b441f8481b9d16e49f63ecaca400bd08d3f	\\x008000039acdc782da0f73c90d3eef9afbbd427c4bf7780c2dfb8f8fbead09961b7a8fffcd1551c4f396675f385f4dae54fa6b3075b331912c2dd6b90c29b0d9a0da35cc24efce175ff2cd3a0471133b2aedf26c9c67ec4ebb819872f8b9135fa83108afeec2389644cee6bb0f6a62d9dd70b96478afd5f72274c1fac8fa008d1afe2a73010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xff8082d9acc0710275682d67f84d3e8a70d93ae22fef9d55ef5918e5492b50fb4c395f6c5ec1d1ae63288e7ff40097f4909160a72f30d6f69a47f3a96be3300d	1620205803000000	1620810603000000	1683882603000000	1778490603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	170
\\x6461bb94a258adf123424c0e1a86c6f5776f3afaba687f796f54bc4d79bcb258891c8d56ca60a7cbfbf92b8c4ec7a6ef68953e9b7e8ff0e196fb84d55958a933	\\x00800003beac88c79988c4b2b173e66240254cc2a99e31cfb11e8803c8a99d19dec19ba15be8b66710f54b223d78cadc9e36d0ef0d0073f200e560cc059daacec9dd9b6dc1227fef2e90400924e552e20efcd80d6e0d8a40b43f7d5fe8567badb811016897e1b4f2f8f03e3ab51b84955f868a43eaa4ebaecebd461b39529f4bb4ce9451010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x59b7d29fcc5d40bbf88798f3a6c6927318c03a780961927cff53ba8536385193fa32f7bebbc385979ca64b17da554c77e4a0a2fd54398b017479ad6de075b102	1616578803000000	1617183603000000	1680255603000000	1774863603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	171
\\x67a572616c63ed8bb37f68d2e9d2f7532c90678c60e16f183123deb71b8ce2d897a77732c858e66843e6d5352bc65602d3ceb951354e5c5bab5a71ec8892ab27	\\x00800003c53b1959f3fe0a14774d9e9dbf4e2ba15210bd20f490394a94cae66de12d7a2b83e41c1e23ecc9ff21b306f4c4be41c6704b60db3529eb4a8a42690ee869eee4abc52a96b1ff2e8dc353389344ef3a946b8e828164341b733fc55bc301bd2670577c8892d3c126d58f49212706a75494c9e70edfa97e7b25bc287ee0b1f26015010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x659b116babbee94cf133e2447439addd8bcbefe3177b1394000c83ce3574f6faac50892b3e1f993202cde1f0b15122e6e52d7023372c3dd92cbb49647d4d2b07	1625041803000000	1625646603000000	1688718603000000	1783326603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	172
\\x6bfd29236bec87074a673cc41832906672346463104c94ee6e99ffabb80e403d5dda689e50424c4125b1540eca616e348d90adac91504065f598c5851b2ea26b	\\x00800003c8e9a63ff5d86ec98b0f519a015077689d7e9d5f85e5cad67589cec4fb2be2113e9de0cde52370c8da88dba0857d8eb088363b76c2d78c9789aac99bb77656bbd687810949e58d12c82966ac44518be66057759e90442732ce7d858106a57972aca4e85aea8c2617c2fa76c052cad308046dc470b529c5cbe4e9856ebefc55d3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x70cae0f925dd8c7218505ebbdd6c557295d3152ee3bed1bdff5e862833bf2d9f88123fa1248d84c0290b00d98c846f09cbaadfaf8120f6d87ba058e1d1403500	1636527303000000	1637132103000000	1700204103000000	1794812103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	173
\\x6db120641f528313f02e76a6776dd9d56634cf3e6dbe0aea714fb2d29bd6af917fc1a2ad0aa30ec63b28b8056829379471f150ab16f4d204637f9be60334aa37	\\x00800003c652fa199ec9ef14b65ebc2284b0aa8b9817b091a63ba78806a78057ef928edf105869f9701476449419d4fb3e148627574511234d27acc2199034b1d3873ce06ce0fe161224810e44cdfad30d626bb760ff02eee57170a553c29f1f0486453dddded9fca40f33c02c2cd592817312b6f32c8f149d74fac94bbcc5ab0bbfb157010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa7554aee033294b48662a8a4dee6acfa8cae2320ee8482b24c16c2cd4d3e377be60b05aa50d04c86feea93e3f54cd0a1a414bb96d08d637e7c410111fdc2640f	1631086803000000	1631691603000000	1694763603000000	1789371603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	174
\\x6e698d91184c9342e94cf49143314e7c8007ab1ec6bc4d10369acc27f409726e81deb1ed5eb175cd8d21cc6aec7f46c9a59a867c3bb389797839a9525390230a	\\x00800003bc7dc14605c1d50bbcc82280561ae98fab5480363793194574b9794ae8ab059b68ef9bb62d5c7ff0b0889daaf1388d966a66882cd953859439c1824b08b73cd0a6bfa20774167422e6b811b5c61c71a1086ab40f2eb2457dfcaf8205d13f45f232cdb5146ded5a1e227e76e0c6ad0a7864f18b77112bfcf3d90ec797aa18619d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcffce0ec481d52cff426f236cc3fd3fdebb7e71e346244f7b58a01db5106efb35c42f50384e49022845e12d2d72bae7438c597527fd6f21aaef596b51a2c4c06	1634713803000000	1635318603000000	1698390603000000	1792998603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	175
\\x7129b3ed37dfa90046cd9e7297689537d9623cc487678d78d881b47865fd795bcf2a94c23de384ee3062e65bda3238eec8e3c1bd1b7efeb24ea1eb7f0497f7d6	\\x00800003d7d7f3532dfda8856ba15170cf25931fb7232bff55288b9c6e8c605e738df8876ffc7b478866c8f011b78a6fe36a3cc97b9f9017cbb4442c9e7d07473c8b390a33aec58056d36d0bf72f95e3510297ee8bd64f45a264629d26c1c16f5ae4668b77c7e6f504c807618c186265d1091fe7e8707b9812bdcb4c2ef4236582db1f15010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x422b629665185f6cb1a8d40be73740535c26f9eec6425f31d70b3c565b22f3145e17d747bec17b763bb28ffabe6b35790ef866c3c28ed974b5c59a28026d580a	1614765303000000	1615370103000000	1678442103000000	1773050103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	176
\\x7129660ae587a2bf398c9d99df3fe0e4b7781cea6585e5a2064e7e5187ca7f8ecc9290d32356d2ea2572f1a6eff28c96d552a7ac635ca83e2934a6e137dd0f39	\\x00800003af1027e72e8fadefd8a7a342ca01612db8724d66871156d76fa8c7af79a2397241c1eb5c47866b267065575b9038db266decb5f273177afdb651bbff48eaa4203cba807ff17e72ad1ad6b2d167cf8804d680288ffceecde65345596535bf72909242063c52c3d31219d333caf95a9aa5ea3fe3856e3ed3c06990c27887dffb2b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5efdf7ccf8feb32130953295dc2d695af1790ddc5721189aa754ced739ce9def08f047f5ee8f82182797240547c1c2c885c37edbad92296f3b5864918b57360c	1631691303000000	1632296103000000	1695368103000000	1789976103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	177
\\x7341ae3401748704ddb25a3adb7e80b62b08c3e74599243f728b121405c0f714b377130a026f2ed3f21edcc72b8103e17ec8c06d278c54df8d154549c691f43e	\\x00800003de199516db24996a7554e80952f50010fe8cac962d87c1a3d0a976dee02419cf93afd40191d3b398bd9e85afc7a862478e5a3288eae795b15e6571da079580c5c61ebc13ecd5f0336a878bd78bfac965f8ffab3a0819244d614105a563d1515b1e8e4a3e93854333176d6ee0c053112a9372dbb0d49131ebd23e1c1618e27d5f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8161664af51355c720c02ed11abca978e05b175b239ba36c793dd7533e34f052cf9b2352da2214aa0ebf78d61e142bf14e97ea72557a2127044bb78aafbc9009	1631086803000000	1631691603000000	1694763603000000	1789371603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	178
\\x76ad44ad39c94061b6669563450457c4cf521ddc0e20ce5aa133e707fecc894737d40f388e761f1ada509d7cb6ef13f308d332bb7487b907899a1e5ed9b0c0d6	\\x00800003d15ae82c50b1887142acd437d48383f8fe1e628263cbe079c2976b8184a2591e6e8ee3c83123fe705df50eab3b7ddcc7140754e2ed978f24832d86b8deb5861bfaf51f6423602e6553841f7929e09aa0177e3f2caec0e4cb4cfb7cb3f4a8cd3b0b0f3b39427834f231a40e98efa9bf680f3f57973f4c58cf103771bc9c13882b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2f1c0d74dae4116452aa30bff915776d9e65cf9207b9fd653a247f1b92aa8a66bf7e1fd1f0e0344c0c89d98a5b2b41d31268d1c7e8254acbadea6758c9fc3701	1609929303000000	1610534103000000	1673606103000000	1768214103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	179
\\x778d39fc4a1a7202f5212a3e8b336d70c1532b0c730aa778064ed2def124ef8e3d346513fa8d4b40df906c86371db52fe33aaabe969d5088afd3c3381cfe1d0c	\\x00800003a3ec174de80ccadbdacc69b8cfebce503075c3e0f4097be12435c4f508386a78e0d8f58d42b0bdc7cf8fbcdfecb0fa58364c728bc988237e2d5283e11af8eec81fab50081acc95823ab15c802a572c6e54628748dc65e07ee17ea894021bd50cd3342552c5818f99a407ab9c689a0a97fd622d8a30b6278d9f8829154a950665010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xdcc92628588a044fa249d2485fc9201abe1ace25e991279808e6d94f78480cb4cadd7df423e7d4b6d62b52a2952e505bd028886ac75decbc05c294851f10d30b	1610533803000000	1611138603000000	1674210603000000	1768818603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	180
\\x80c1eefe496d39133296ca5212fb43c560686c0d9602ef82ef50aaf1d5120d2b944654f553baa51ba83cec14dda2eecfba57ac0ba705a9599e0a26cf6ba57edb	\\x00800003abe5cc8e5b4fccc7646ad651f5245d49ca8f07cca287f81af6894bb0c8f39f8de569540817da54736b96296bc502379ae095cbb23c5441e0a7c5b1e4648e73f89a54e88d56365155e181997bbca4ec0ad85280d419a22a065ea775f1e9b5b7f666064c4b209458c2816143d791053994fa6401cc3a677f3b19ccef08debf9281010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb0964b830291f4c0a832ae53a518f3df28d225e908540b3302a93f7dc97fb4539c30ab46844bc3360297b93e526b1083487c8b8a44880452f80b3292ab76360b	1634713803000000	1635318603000000	1698390603000000	1792998603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	181
\\x83d55e5f24e0eb8293be532bf100bd83c9dffa1c3a5df37c159c72a9bbe142a5d9a132cb97d88773e8ed5b1477dbb71e942f4ec817447902c1b3bccf1c3919a5	\\x00800003d03496c2131b15d46e8435e90e8d80846b29352172ae652bd8568ca2da6e5447a38c7832d4852c5749d1382b87048b62522952ac2323bb059ccd59792d5543d71ac5fd601d4139315349e1bd7cceec8633d3cff14f540c13c53c0e37d20d0778d7ab84326d7f64d10725143c9085bf1042810331db3d4730ba8bb21fe5a87efd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf304e89ff6db43186a81dd6a4c85b0d92e74617784c459b50594f5d80f5afb6e6517029165c2fa043dc75511f27736a37af84d7b3670a182d9560e2e56ab7c02	1625646303000000	1626251103000000	1689323103000000	1783931103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	182
\\x8609d0fd766d357a1acc40d267bbeacb021c8825862002e7a6fc4a0aa98a5918c0e2d374f8b50a00ecb53a1ed2b8760a0a2924b427a5b69eb6963d733e1039a8	\\x00800003c5b742905d9211a427fc8aced75b597e4c509137ec55cbbf8c0e74eb14f540283f938241e8bc4fce4f5116199668cccfc29d4497d9d05714858d3441a47a46a590d49960ef44db1143c80b93b9c1f3e6451e774bf769d9f6ee0e9918d2ac5cc3bb4b3984e67cc8bebff229697b02ba0c78e30593a3d21e86517eb4f37be750f9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x10690e9e29324dabcffe07afc5f7f469b0d858518c1fc77beef55cdda37480d74c0d81e00fffee71c99fed352ab0655b0c3625b0260874c8ae8e107cc4dd7907	1610533803000000	1611138603000000	1674210603000000	1768818603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	183
\\x8739c2fa31ae76171fecc8197dca022313dae8c495cfc655014edac4f48de2300ce86c797574d22e74cea0446ca9083ce0a1d145f133d2b70ad7fda7e5d4e8e1	\\x00800003d3fba10fcf8b60a88f60c7ac3e446b96f4c2bd51ab330b460b368b879870552a0cd6689514d2b11256710b1b8f0c184b78b732852b9c1a1a4165f6331cda8dcf114e59aaeb34229d6f3bd750541e21752e87ed74c4c66a1b623c16c62a5809a9364f7fb4e5ebf3b023682e8d59fdf5403ae3aaa1f324ced710f335802ed470d1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x99d18df9a92614b6f993712a2867460719501d62c3853d0047453a8b3f1095345c10225e19aaab42671ed7e959fe63e93bd7f8fc114cc8dc615bdd12ba9cba06	1613556303000000	1614161103000000	1677233103000000	1771841103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	184
\\x88d13523a81cc7226c849af2a345c8fb9272865f0d4e6558b48e7817a535992851cba22c0759a392046e0f4fba1d0a3d2d646b9baf81eaf562cc435f7594eaeb	\\x00800003bd4d403933ed61e5eb72ae1add47ef5c4adc3d6f440df68ab20c9efe94bd083b0ede36903183959e37ecb028fd3ee96b89bcbda835064333edb24749f1bd7030d90304a90e1de7bfde0ba63c8e2cc16a32e3cb3d3985001d5a7c5f438e86e6fdbf0eef3d6ee82bda22600f9979030e1007246b1a96dd45c13297c46a9f3c9ff3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe79971b5a7abf80ab15d7c8fa7294407875a42a580d07165572b0fbaf00e28bedf4538a88887f6fa72eb809582ec4503de4e62e40d49e07178fcd64e59b47603	1618996803000000	1619601603000000	1682673603000000	1777281603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	185
\\x8991b5307b4e4537d8c49aaed05c2f12dabe2947aa8806aec8ce8d0d383651a49e86552f3dd738778721abf3e07b0ad3ba6938aa2061ad66260a785f4f4f7d2c	\\x00800003aa732b3f052d5d23de75c950b6b125d0bfc362c4e83fb4d66e0dacb9c9b690e526ee75df34deda2f0ba0146d9c4e349805e911ebbbb8c5b536e00dc91397678b0f7b72ada96b838eb80252b50540e242da4648dafa0b100d0a3951feddbc9f9359e91f1a4079fdee92bfd3a0b40346fe4dd5cc0b99621c512ec923dcf5cebb8f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9aff39457ca7a1a7f9c0c9a40fe39db895def81a00390ed1981352e75854e8bcda24a11384f64ccdeb7e2f4f7f914e5f4eacc55626269803cf699c4cdfa6e204	1609929303000000	1610534103000000	1673606103000000	1768214103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	186
\\x8db975e8e28b00ca76dea0c46826c307d9116bdd1cea4c504a7de873747e2a7b3e11401ebe48d45f54a03115b7a834175b3aee52e75861928fc67626af6a0acb	\\x00800003c3bc54c731f257a0c542d8dd104dcd093105465d5443c8bfef6dc5412763c369ba3a15db0089b0baef0f5c99a83a11e4c18724db2e1ca42848eafbf2f5ea81318100a9ad38378509d77279726858a4b094e6474ca40d8f9b0fd1f14a2e3420a39b5d8cfb809338e146c867500f27c0906b571600f5af001f954eb9457526c401010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfd661316d1e9c8c9386f997c15b72c689ba11ab906d9b968c0078e2b4f457608e1fb2b4438fec4151879e8e461b8512dd47b536a7ee897c4f5f46227512ae704	1621414803000000	1622019603000000	1685091603000000	1779699603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	187
\\x8ff530fc43a70354062d23351cbd948dfb98fa0386c84944bd6aaedba6aa07e258b8d928fcd61558856043031afdbc5fca59da3e87d8058c911e1a4140c02391	\\x00800003d420569e9610ff08c7cd96f20ba8334f8f4b3f4fd2313fc3b6825a366e0a4576ba7d3fa9154b4f8fa67ef559bd868e74fbfaaaa3f5b6ae9797cb78f800389407831caa39bc88289eed433208d401c7b7cca6b1ae39a76ad0e23fb191c5dadc113f5c119440acc98bed68b9086ed0ed6da56bcee050283e8415f0378400d3cd03010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x1b2124b227b6ea1bfe5abee39d330d9bdcac07dc60e72f48ac2620d045bee08f237508a53ad851ec9a7b335f58fa6e2f4abc5b8e55cfac3b8853d8bc20ade50f	1626250803000000	1626855603000000	1689927603000000	1784535603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	188
\\x916d735c94966037c4e48acd2ebb2f6b119bb70ad9f41f6f444a705bdd359facb999d0dfd4af16c64e09b4a2231c11c6d372b59f360785b77bc2754a89870f7c	\\x00800003de34f7284b0bba063ca5025e2a5c28ce6844b1aefa15b2b57a3d8c9c3917f28c0b905676d76c965459e9cb545af24b188b821c3e6f12e6c5cd986210d917c30da0b9b8514eec1b57366e57d4d5edd6bf8c96d1ba026b201a2c1b7a9d7daa10e57bbea25fe090743272246136c89bdb1b93001c781e5f7e34708be38e811102f9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x704303ea300fe8c06ca16c4c2826674d0a69f89cacdc388f5b5bd939e4b1d76547945670c354c61471a5c930866d89c18bb8801fc83d4b32772feab4b5e2220c	1629877803000000	1630482603000000	1693554603000000	1788162603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	189
\\x96e10946b399966ea3bb773edc5365763a81febb9c8ad37086e2ff6eb911b48ef8b1034256c7bcf3db6833db776bac7687d1d1bf0e882834dc72e7718a3aeb67	\\x00800003a4926929b3001bbade9d2d9a771b8a1d98cf65024ffa17f4465746a2ce12a9d8c078548dc5839981b039140d9bb269cd3dcd83128316e63947615571d7b0d027290c9af2b9a9835a1cee15037ef05b7d261147b1b1e8f502a275f2f593ff4a5702421420f647aeae61ddcc46138bcb81cbf806eeacdae24c4a405c6d0885765d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x1d18470282df385c698012948ab19b6f4906800045102d415a52c035509b9d7fa18f936717f817e072daa7e7f8a7133af615054c69f9d8d943a2c0145fcd2108	1616578803000000	1617183603000000	1680255603000000	1774863603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	190
\\x96253af14484c2f2bbae0ee0cff58e5a7c60883efb46e6d956bdd2183475c808c99e2da73931c44f38026e8485d870dae9ab08de3bc733718b16a9cc1acc01b0	\\x00800003cacf96006d666f1a95e1b1003a0ba34696c6e932439f2b8cebc0661ab2ccfbfea02f8a4a087852eb3564ebfe3580be4556593b0b06f8782987aeb6c318578d9658df545fffacb5611a04b162a42ac9d14955d1ce7689f1bb73f87c7bc9c4c1b5dd9be9479a100062880314456a5e15678b2aaa4a3d9277792520a21f2c7cf91b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0589c97c425f75a8ef72edb3b61902da80b13793b5aef50f8de6b024205ddc85ee858a4873a5c9d416f89f81284357a0c28329286ec0be2b006e7a71f5e46901	1611742803000000	1612347603000000	1675419603000000	1770027603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	191
\\x98f9279532aa96799e788c0e5966ccc9e297afb34cfe212ba6845eff844cc5e3662c4e0f107e262937c677c2fa6fd12c8159079bb38c3262497ebedc2a019176	\\x00800003aedd94d177937fe7f3b679fa5c8996382b04dd889d8c15bc8375f2a67e5cf7f480688e88c1b004162f6ee56418cd47cc8fe5dd82f52d4f78ea8bb4ea63ec71b774b73525cefffc4ebd2ffb14b27b02ad8a293eff17db2b25e640430645daa2d080f43f4222e13bc35e25a15f8d5060163c240047b82823d7c455d2b7497bc6f7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa83bfe1f4e90b3d7997423883901d959fd502191e0b2cd560d3d8a51bc4dd7292ae54521d87d5327102a664a818523fac6c7050748ffd6a1ad67a17e48b23d08	1636527303000000	1637132103000000	1700204103000000	1794812103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	192
\\x993d3fc102f3cb6483753b70e9227ff0ae72daa3cacd6586b505b7762239f9a3f2538140a7e562e2355bee38b63b40dcc9c0de0e4cc37e23fe97bfea14b9e5b4	\\x00800003d93a0a9f16a21a67a03954d440d7c0e4b21c5fc87c5f8efd5533579a80f4586dd725cb502616d2458dfee89dd8c3afe96ab7ac173ba084471608cfe9ea9d03ed21ebf491b2c1706155ef0713dfadafbda34c1140f5f7c6de38d3f687bf6f338ddd562f31feb268386ab4a53086d308008de435c540ca59f95914f8932a6fb401010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x921ab95538346aa55cfe1d663bb5516a3e1a2c172b87d05450a048b60424421ec516f246ef5142354b1e94aa68909db99b223bd31e29a7226c5141061a1b550b	1617787803000000	1618392603000000	1681464603000000	1776072603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	193
\\x9d9151910f94757393cf27f19824b01c279cbecbc4f8c523f7235bc2a157b007edeec6d5d67926a19b131e8ffc77c2a820e844a48531736c1538e9c6ce89a76b	\\x00800003ab607a0dafb93560656f7ba72d213e8503ac275ca89ed52bbd110f1e9f62b8a4e1cd4c93e40547ac813e602f2d366a49d2b3264eb2995c4e0ca936a41820c5f3d1254ff2da12c641cac4a78fbbeee814c9e98220a2e534dd67d8a1738c87d8a5f7a71b45dff9b96d35e8cd26a023d53c55136edef66110f01e1a2cd211ad27f9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2f9b73af6b8455e3ac0a9e8d09027ec7fa1a45bdbcee84b3bee623bc42571bb30d543b59d29939c5da011301f6b3f5de0abd630f77d5918b9a99d7604ce11209	1619601303000000	1620206103000000	1683278103000000	1777886103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	194
\\x9d794bc6eabe0c879a2e878f6d69d54677ad9b48692ec886eda0d037092a1b85c34002e6e365aca0048edbe724f86300d4cd41d5634456f8b466e24458f65b81	\\x00800003c6348e05e622d9c7608257dcf9d2b4a8119257153ef7ba4e3ecd75823f67e4c22a462df147f76093ef17a38d3b9dfe5cdbb4b1101213081d49c8baa4e76eca86ea857fe23fd80ee5a77be3cdd9e711be27d313d485879b699b18adb2055849dcdd66bbcc4e8d6548448105d094e254649e6b15ddba89b3082e1ac0fc8023b75f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb3564afe0a0bf4dc36e0f7554f4da70053432651224121c9a76181b2bf3d7a01a3cf8f396bdd6251f43ed9f88bc546dfc563ed98963d70669e593c8a7e9b7305	1637736303000000	1638341103000000	1701413103000000	1796021103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	195
\\xa0b9c0b3f3eb7e0e8895a1d3a39d7de300182a640f964a240e55d3ef18074daf11cd68fbf110cd7f40edb259da8fbc04fbb8e7c34d73cecc3c1b504006c8c230	\\x00800003cb51566811bc3367917c30e88c59cde4104a54e6cbcc252ff54163110581c26831f492ed538e49cc8017e96a50b628fb068d9ff3722cd1e303aeff26afa9ef7b05b1f04ee2dc88775ba4daf04c1eb8a4cdac63c3f89a8c09b5798946af20dfd9f42276bf12db5ddf21a37fa9cdaa909d109116ca425e20f1930a344b1335f189010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x982e01ccec5e6b2870df02b6fbd76b6430f477de1d1f2a1c7334092cae22c5e4eeb54cf68dcea2cd77a9d221a2e51022c45f31a3280b76422be9414f90304c03	1640758803000000	1641363603000000	1704435603000000	1799043603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	196
\\xa119df890c7540c9054e573e9b73756d0e955415a739ed8a12c6d4e5f2f09d210b6c66a2aa2e1e6ad47ffda94242909e749a9b90bea4686cd90dc664388b8ffc	\\x00800003b66c1280ba74f2b495844ede860e913045756cbb42d1a60487245d5c65ca8d7eb0eeaec2b1af166c2a81228f1891b0bc8268453e98697517aa82fc767345526d79272574635aa53c8b8fed1a9e9d5b17741d14879fb548c70396fa414c314ac1b4c18cf6a0b518c179934570e1327a7ee13025eec0b98985bb828a6d4aaa6771010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8a9b7b2bb5ea07d89d1537e69d01a08d425184a44d54d052643f050120ad2d7e2cbacad8d8ec9c26082a62ad5347ee46df0abc9e2ce55f6d9ddced699af3cd08	1621414803000000	1622019603000000	1685091603000000	1779699603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	197
\\xaacdb4a9e6f5447f88a94a4a88cc9b73a9d086429c49118060b9acf06be34a40dfd4d1293357196c2b66ab5bdc065df0c7d456fe9d2576bdb3fb38b04e19ce54	\\x00800003bb50e3ce92cf6bcf3edebfadd9a8ec301cf6b94e8d48994324e45752128f8055e417248404cabb22c4ad574d160514c0fc5d51974c15a0f508053173751467ef10f3efb607581bae7d1d4396c81c02b0b9c7b2c200eb60264de228f3cb4229d6ceb84a408dad4c8dd21829bffb81c45ddbf1c64189849df23f48b8de46f06657010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7718ca70d80bd39045117becb3509b896e3bed7158ee544be38112f55f04736478139c84c4f922e9a3d8aed600352d2f6e5fe0dcd6e93d5d3c885e5b1c86b40d	1630482303000000	1631087103000000	1694159103000000	1788767103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	198
\\xabc5455a89c620324956a94839961ced20728d9565964d41cc6828050c5cde947e0486ad9f09bdb2347df8e3a75311ebf0b784963478a6928c6d83bfa8f98c4f	\\x008000039ef76ba4d6fb3cd023ec4b57bcbda5c05aafe4df5ed8a3b585dd26764daea08e29c389ac8f7dc8b647b959963d6fc492f745e2fd1a239fb9338a7861b77bd60e7a67ff221b7fb221e60c3144cf0602f2a1c6d53beed51184aaafa9fa7ae28ef42429c9d5bf7a9888bc18aa5ddf8fd1f070c228297dcc0605978c45bfb6dc9945010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd56b0df7c0cabb31c7ac6709aeae32a3aa434e88a8d6da249b8a0088b86ba67f4b947423cd6fcacfa6d9a7976d0f12857df66597054b5ee351f37e0d59951d03	1637736303000000	1638341103000000	1701413103000000	1796021103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	199
\\xac29703a2dc0a0746df509ce5b836c053ae977899b0c9f0f1b0df061bf3471b4a54520850d5c3680e46e6ed5e33a3168043d9995f223759a7adab796da0fde69	\\x00800003cec30d4d8e9a0aac965554244b73b3ad2212424842599e805556dbaafb4576ea82e679c30a33db8e7a04827fbb21486f2b6427c0797daa98a8bca5d7f04a4263290a16cf3e7191d84038497d877f72e1cef3f66ad12fd712555a58ff0b7bc6380a054210e071670f95c16b2aee8356b818abae0a1b67560e79ae078194868c1f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcf0f51704ad698347058baf3c191731bcad8b2f6742dcb7f09ba84ca3709202b2c7a48eeb9079ab8834156a7d8055161ab9c040060e5a47cf5284753b0762b09	1635922803000000	1636527603000000	1699599603000000	1794207603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	200
\\xad7d0e9953c38159c78694c83b61a8bfab7d95917af0b180b0504b1c5c154f3c8e56194af3facd9fdb0613e1bc4b802deed0db0e78cc1f1b179e5809e175e72d	\\x00800003caf1a689eae9ce1105a34c05c389d56878bee547018ee3e08582d939e1ce0bf1f42798af1818205889846b9b6f5ab87051c191fa450e88eef0925ea89bc26d665051899d65894013c79f062541170e37f3444d648c88ccbb7048a3b6a1e86747d7b7e5333b0e063faa2f63ed362dac14191076c436c4c4d2221267065d421347010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb62a2c5bd85798e7310cfd8ccb46f33f0137ee1e67aa46f521389d03d37f4f1595805f356c83770d1a258dddbf7edfc1c90bcf6a69b86b42477c089dfc6c4703	1618996803000000	1619601603000000	1682673603000000	1777281603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xaf09e86decaaf4dea9be7d3a5e246dbac416b352715109c302298d927d7d5bf98175284e8cc772458c651da181a56034a47d11cfa04d444b5bdfffea3bfcde8b	\\x00800003bf897e335726a534b6ecfc33695a30269fa1baeab6cf608acb44da418ab97cf7846db8326a401ab2a5c12b18e313bb4647f12cab022edb9b5f59f7eee8b7cc37cd7d06b30b537e3dcd78cd94cf9b22f335e9ee3e3677e988f1254420cd9beb8411887b286e201b7da292828597f27394e87843dc00d9f223869da8152b6e6c6f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc028581d68dfbf5552a74c339c2158e97eff4d14a9e6f466014252865ef79a5224a3cc8d24155ccd05393ba6ab7ad8368a90a21b13eb0aaf03dfb75e60385101	1641363303000000	1641968103000000	1705040103000000	1799648103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	202
\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x00800003b3df93af5f96dc33eebcbe55d1dc6b01a0f763e05278afcc3306d422556de0b6faa1de9ebce840263d43c10427121a66b7a75870f3f2339d1675523b78ae6d7a6a018be0ad50e85e8e11eb302b2af6ea9c9e24d1c7f2d20649c5ca942651cda25133692eaec1e7672a1b20e08fdeb85c71068800a90dd71959fab12d73267581010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xefcac42d7c485a865f6311d931bf9417f2b67c124d18138bf20147fab9b94f028f566d3b3b78e97bfa1385661e4d05ad77a777d03cdc1002b6b4ae46512cde02	1609929303000000	1610534103000000	1673606103000000	1768214103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	203
\\xb8f950e8b3456ebf35bc1bbedd42b88b088e3c34535561d1a31198bdce458a16ab08bcaf4f46096da5c4ba1dcc4d738fcfb402c72f87b5b1da411d464a2ee01d	\\x00800003dcc7b012a8bdecda248e0ba091eb0b57ee86e7463c9a3e3e90ba7e11e00f61e6cf00da3ab45713556d0bea04334686a696f93e7c1baea78fbfd57fbd1ecb876b037805578695c9a81932d5521166bffa46d1e9aacb33de154fad4fd43e1db91aea3ae9d37c604eb5f4dd92ca19f2ac64702fafbf3d7835661e9309a0bf3131ef010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xec2ac69f5669dda0c50eb82ea5fbe1044b02771f2851da3e1026d779eb247f4bda032c30018df6fd6b5645c3470a3ea74355508a8cdbeda2017ecb7ec748480a	1622019303000000	1622624103000000	1685696103000000	1780304103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	204
\\xb845153707e8eaa598f55786ded8cbe4c0bff1920299c232ef60399d3013a05ad246fb13f7450df826f4f6573bb6f762c564cc81f4dfac13cb3486b3c990daf0	\\x00800003cfe6aae24dfdcbb931582c3bdf6330d02279c2e9229cb4004857fedcfd17095613a5de8fb3edaa274c7d5ea7de01ce605f40855035eaebebaf898a16cf3311adcb69ca3da641a3c14c510c4da566be63374bb6775745cf7049cecd1b558a6326a8cd6a511014b34cc4f39865ae9b52a1e69dbc5cfb33ade187e69f1924357f25010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3bfe24778a72a8c8a0a94a2b1fbf85ea470b6fc66332ea93c4f2b1e71f5be7baa289838c7f8a79e0a727bb436d43a24e21fb89a2277711b54d750a41f0741c01	1609929303000000	1610534103000000	1673606103000000	1768214103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	205
\\xb8f1f54ff8512f3aaaf5d5242fdfcc2f0d3dd45ef11e6ca889d4fc78e9399f8e79e7369b9f49411a4359136da5c7d78d28341bb75df5dec029f5dc37300776b3	\\x00800003be1b151a67015fdc584707adf08c740bb331ec647d8f1cc1b38a8075370a938b17d54fdd06daceb58a41410c2d348f5cec5923f5e4cefd6582ea0b854d1ebdf82bc0042c68f81b7eeb60badc365b9a245b93d638878873a34a79caf65fd75779b0e51953db6cd2d3fa489c4d96cf952fc4b0bcce19fcbc244f0c95060dc7de8d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfe700f2fd85b99148c8c01825053f9dcb6bbb46ae7ca4fce5967739344c1a94309f40a4af6e898fad229e9d114b4d685a09405c283e84a866812fc8e3bd13b00	1611742803000000	1612347603000000	1675419603000000	1770027603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	206
\\xbafd4d430c18f5e550f79bce87984da3c3d593970af19ea215425f8a0240b38f57d9d2f31d709059bf8acc244fc46f8d07399d52a46d3f96d8ccdf4f786bd18a	\\x00800003cbafbf255c01fc93fbd63d490495f01fac6057895eb7bca45eee6e5a5d0b5ab13792193245e90acb4c57728049de9dc6226028b263f52c2be0f5d20348b95f33b08168e1ab6c7e73e599d51655a9927222f86e0ca3d73cbbd16c968a0498cdd6c58f4d2351b1d44f2da479cf90db95a96677a6a542d914fe22ff9cd559be190d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xef43d814d4d1d193239d91c950562cd4cb325ff9ad23357ffc8f3507ddc472550f299926789a01f24e9a451b6818db0ee6e3f48603358d67fd598395b8ec8e08	1633504803000000	1634109603000000	1697181603000000	1791789603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	207
\\xbf75919664798d75bb1c05ffcae3589d95aaf5390a90a8a34aa716b96d8db402c9b96e45d929ec470e3cdbfc54c5c3d94a88032c29e2f9b26515effc843e3f2e	\\x00800003a145ba6bc63eb4b0cb89f7d68bb981f234724b6b742e6a72afbb9ae50c00042ee74f2fa1ffd37049f5d8c0119a2d94da1833d8dd493afbfc6745c4ac79025cbb14817a15087984614f8e71816e08d2cfc8a464614eb647f462c9772b7fd4c3896dfbdc01bb459fb8816923c49be1f23282b5f7a92e4d37c61b9dc4d53ed6aec7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x489e68c14553ac3e0e197c742263a08811723eb586ffa21a587968a09d8ae13bb94f0a44e39f75f8c02a183a10d0ad85624a8442b774913c58c3abe6557c3502	1622623803000000	1623228603000000	1686300603000000	1780908603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	208
\\xc1852fd7c859fc9f09345a1ba2b17e0183068e5e0c4ab9e99ddf7b667aa02b5eb26fb080b640b7fa6bb62db921373f297ababf6b663c6434d6906b2b43e55aef	\\x00800003ef8128e4a1bd3d043bbe07774b2359cb55500524a31d7c65c4eacebf3964b4f2f218f2d2788c128238a54d3efec2369ccd9762026a7863ca4906ea061c95c715765ab1f4988d8ca4c22dfc052035cef97be210296f699e305bd7b6869d85a226c357984cacfbc3a16012f1427ce5d3e78255d6c7f576c244bec5d6127e9992af010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x812e1d00b7fa7d50435499b2edcff8800e0536b5fe5be69c81fabd7a36c894426a53bdb5eaddaae8af0f010934b0c475f2f415f95eab3b289c79ff4a333ae10b	1616578803000000	1617183603000000	1680255603000000	1774863603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	209
\\xc2b96922175be8ab94cfd03e90345907e622bea595bb34252de00e4e784aa248f73ff31f904f84de23dfdf748b811a342547a08731506ebc4255534f8586f197	\\x00800003ed45c8fa65aa78e749a5e18a44330bffc241a8c31fc44d5154481bbdb9ca904ed2b75ca242aca16e43b6a49572471e30cd4a7ab94401c4092b80a929d0104f4f58dc18bcd3c2d20facf61170311462ddfb777a2140a15f42d2ee77adcdfa89029c749f453c8a5e15060d3f1a1f55e8ca2622731842b40bf1045b468152dbeff1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xce82b0b78b376dff044764e59f92e01288df2265590bbc18547112dfc74a59c7b6b13448d7e44b605e751fd372f817a231c48e428d7cb888509ae3f1aa02270e	1629273303000000	1629878103000000	1692950103000000	1787558103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	210
\\xc7b5ae1676e728635ab889740dde11a047964c5ea37a94566e9d742758391f6a5f0ae4f570fcfd1254e6fb4373e79b3ae75c5bf2bb6f1929118f3d1f93f13653	\\x00800003cb6a89beb28c03bcdb934f5a8e3c6060244d4020b2001ebcd4b0b8218018e9cef7a842f15fcf7c98ac0f34bb330ad98e7451bebd4fb0e8a6b7f843e7ea847c4bc518884eb52e0b089b4a1298c13728d5d3bb33227ec399977ce1a6097b1d47412f1d7b20a4a6179fdc497a03e8499114bda023e414fa282985cf4132fbf58333010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x40b22bad0486c3ccaf0606e39f568ae14184a5a16a2815a283837c26289a515b27f8641904333e9d301935c2078041da8c6854fa0f98798679b369422942fa02	1621414803000000	1622019603000000	1685091603000000	1779699603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	211
\\xcb312a3fac064d15df408cca22bdfe11e7bfefd569df85f8738fa641d34c0e7c68577dac752de7f7713d6057cfc8dac4f1da7a0d977501a8a4a1f5ff3550325b	\\x00800003bddeebbc74a5e9f9dc18aa889489b14b49c87e1b96370af882773d1b65c6c595d450fc8f2875132c7697eb2bdc849a12780639a3e45fec0c7362580f03eadb8a0c6140c54f367c5dc2a6709f7a0c7c43375e3d77d3355b99330a3af727384382b70b72e3947b1c2b03be5b4ab70ae3f9b5828b53b9fb501068358e82d6d6f06b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x1f0705b9414d56a3ae04900c7ad8f195f527215139f1421042d1986c442123e84fe126d9ece21188889aad90d7af12abb8cc62a6d600bed23e2fc34e2c81d40d	1637131803000000	1637736603000000	1700808603000000	1795416603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	212
\\xcca5e4d8722c79b7223b46a02bc7009de54cf0ea0226fb90b3a6f49fcf358f3b3f77a8b5ce245a77a01429a1af9f61eb2201d8e7a853dcafa83db3e12747c160	\\x00800003bee5efb1dd4eab71b945673e3798775b4025e4fdaac340197c10f5dd2fd2e2e356f60a50552944943e3ee1d66d5af977fa147b3698f558d6e96fc47f5b02733d4e6654b98747896a357d8a1de2573d2c381e267d324fc1951c3e04f1536b389900b5ea53bfe96d6d12507cfc022b225cbaa86616cfe966b35bd568f4911ca8b7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd13d4d20cfc93225692aaf6608a0976c3e5eb89d5bcfda3750b09bb9e2f3d8b2ac3ccf7cfc1964089300b5b1b8a82add9823931db256092ff8b4e61b17626b0a	1625041803000000	1625646603000000	1688718603000000	1783326603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	213
\\xcdfd93818b8e6b641f42fe0781646eac15d95cb892ab772c41ed344bca430ac156db2703459e21d5eac3569bf7b8e2c88a300924d5bf152ad3a856788369a2fd	\\x00800003a2216e920003269d25d963ba99a265279c2baa090ace954e12def692762363a30104c255a9b284f4934cb229dd371bc153440c75fd59efb8b4680a6826e883b94ad729a7959740fe2f108e6a06afbba110eefa99fa234a166f83d6d923b8533ba6ee36d0519ffd9ea5bb94acfbdb3f8e3ef181403f6cef40d2a9d008a3f2a2b5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0e25fe20509fa1cebd962b39b6145c5879c8ac6e1a41b1798feac17efe3cc564963ee00ca793837d65156e5ee6aa39d6c34dad3ae4e80aaf5e1657c093165301	1638945303000000	1639550103000000	1702622103000000	1797230103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	214
\\xce99c1aaf5564c0a067e5f8a3fbdfb4ed3dfb607e40a6ad34fe99b5d33bbe5ecf96ecd951f968233487123b7cc1b8073c5f3b24914e3e16d5bfa0804faf8b601	\\x00800003bbceade32f9e04cf37b03d5d12291f59b5ba36f9b26d4a5a59a27f71d093b6b0b09c9239cfc92953b48df68adc40329aa86f5a5bb6ad2152c07535c5ad73d1961e5bc74333401b13c7fc36df7c7ab9c0352079fdde1c54105e8b57544fd7693bbb1a2d8b859b5be4ceaf64decd2ef5cf815e9082f31c35bf3a27d9cfade36137010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x193b0236ae864a3abb81c35860291efbd94d4411582a9eff2b3be5e3179bcb27b3585caebd897250138cf8da88a9b13ebfddc2af8ea5b6ae016008c0a033070e	1620810303000000	1621415103000000	1684487103000000	1779095103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	215
\\xcf31298cab7a1cd2786bc788d16248d2c0424fdcebc0da4af0bd8188a941173c2f713411a633bb10ef746cdd9e84e9e246c3c113b531ac6ecad11046baf69b6c	\\x0080000399db10ed5a35d864272d930709fc392937b8fa925d920a6fecaede40e918de317aefcb71c536949f40a4a9e491cba36943cabb42dff05b20d8dd5b821dc6b327ae9c310310cbda837161da547b6d0ca23c50c4089243f511c25e9c83fae8a7013da25cfc58fc08a2dacef47a422f70954f974377a68ccbe8fb7793ea9fa98d83010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3f078223c08555106ab17b4f612859d26ee239153c53b1e2d68b6bb838cac7b5aa92d6272c9596dce7bab8f8a68460646a49936c789fc63592b591d7cad2a308	1613556303000000	1614161103000000	1677233103000000	1771841103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	216
\\xd01dc37f14e772af9d6344a6974425c85f075f8e632279a6e845365aa88a68d3b181c31eedc6078261f1749752160cb680d24b07d5515b1105b8785e77b51801	\\x00800003ac4879d3cc35b5fc9bf5bfb72ba0d5430e4939913250c4ba9b0a18a1166f9f5fbbc53a0e1bd5c7fcfe6204d71304a287ee129faff14c21106cf91ccb145a3d9650994af4480e6d1d711d2e13a036b4831f981cff3a5d903527c2ad164215156b23a0bfea1e97bda8bd14c6e290a9daf7bfea683498a688a41fc8240eb429ffad010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf955839b4d02731c360b36df266ed4066a5e94a8185471600c3c61f04072c8dfe309a4a03fcebe20faef4c66bdf7b51f0489c4d6b0aab66daad235310298dd0d	1632900303000000	1633505103000000	1696577103000000	1791185103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	217
\\xd2a9b723c4e251ad2a0513a03f8c3b8e286ebed740dda9e3b4e1ca66f53530f87cf152e0d5dd5ae6f8fcb4cd4e146e05caf4bc3fd19ec88d828cdd91162abdc2	\\x00800003ba087b4f10fc03d420ee88e1989c16910b97f4e2c61fc0c4aff260e9d51c2c8fda78d667c1a8a3463e33fd0c50f465a4133bf511836f594bd6dce8b37ec277f4ed949b1c721d96a3d82cac2cb39f03c4896c06637bcd5933d8c286e42b583a7e6552e47c3cbf1a3a5d8f2610272acac61b04d4be4264130895c2ce03858b3841010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd85d3b8baa25e7f90cbd9b11f34c64a42a8b6a96bbf9b717649c65a447a8bc1b54088e4a42a6f271afbfa6ead96bc48b503ad408b7cb0e748a8574ff8f346c02	1633504803000000	1634109603000000	1697181603000000	1791789603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	218
\\xd3edb87f100e01597efb8fe4b2528b1de769efe0e69a3263bdd50512ef6ab522a3c3d8e4a1f53183ef887d2968eaa7398034554a088d40c3a8ccb047c44e386e	\\x00800003cc1beb7b0d3f44529bd54a86477203ea4ea1efd9b9f5da6fc49d758e6c219cd1dba1187b0070e0182a81810a1f494c08a812df803885aef154269ab6b3af2e11f6763ba891aba821f8288e599f6c3bb95e4e831b24042e91535293095e95b0398383dace567836ce46c9c3d4cd2ce1e600814dfba51a8770952949b3977c0e69010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x82618e198e4a7860cf4e74c527b73d7153cc99d998963fc5ae61c0f87942b3b62210cd8ae974bd1d64ddbc7d3aa4ae43413be0771bc4391a66b728351f11790c	1641363303000000	1641968103000000	1705040103000000	1799648103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	219
\\xd445443f816cf8e0aab489e8da73d8696d5160c651e3113605fa43e90105030a1ef68e4436e00230d956f5d481e4da7e70aea2fb6337cc206a9d05e95744f76a	\\x00800003d2e29275eb6c9aa13bef6ebb590e72cbf661f524a8af36e989b154f8e4589dc2a74f6433a658460f9f0846bb42a56774bead452e3cf54ca0b440eceb36bd23450f97a26cfa9b751ecfe7a7acdb14362df09e547c76b3bb9ee334f395cf19451908de52fb7cb2ce61bf6cb2f6bfb549b38e038e64dafe021a993a0b385a66fdbf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x49bb044fe13f5a1eb62663e5e535c406bc5e7245022540f4a230d2e5ffd83c28a29b9383a271617932af9caf93c70794071a35370673f63ece8613a5c192510d	1636527303000000	1637132103000000	1700204103000000	1794812103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	220
\\xd775218536a4c443ff1fc4b2d30461999ba4f88abdaa3c3a8d5f3c6a92e62819312e48bb24c649b028c6e322783de2ceb45bef236acf567d98a676f418b728b6	\\x00800003e76e08343af5777aa511947345e0cde6b791573c7096607910e08d811f34c2fe2798afcb2c720f2986579d50a4d2c57d8568e0ca67226e3b76155346789e15d518044c35ab10d5a8874fb03ade47aca6bb33d6687f573b55d04cb6c371482a368363c10eadef1044a2d0cf53a510e1e79354312b22f31a07b6be127f6e14c20f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x79efad54594f94bfedce3180f604573939dc5ebcab186a5c3933328c2e484f0afaf82ce58dda8dd614423c39689fefb0517a273c43fbe3b6f230f74a3253110e	1623832803000000	1624437603000000	1687509603000000	1782117603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	221
\\xd8c9cfc92ad74d51822b1428b8090b52617bb78ca965ccf76b1c660479a4b1c11324e3cd0a0f23e81edc1a399c1918c869e1b054cb7e2ce074ac14ca61395c8f	\\x00800003d20c1a21a487fb012d0a8bc5abf31f9a11c3663e34a7195c89f9aa849d33fbce89fb06c9ee02d09ca9eaf275e27286b6aef5971e5cc4d6c0ccb427d62f0dab82937575fb78a21f59329675b72722be5f7bb879f618bf10887abd924df07c8a7d41548f1d9b9623725426a5052241bd5c0406e5262ef37614efaef31482cc095d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x170ad73f0b791aa5c0f195ef2a9bda3fda07bbc682530c4a549a8e81e1771aa5238f7fd09d92d55694416e9ef949be04266bf3ed76ebc1d9a52143aac52b5907	1615369803000000	1615974603000000	1679046603000000	1773654603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	222
\\xda35b5fbb78a42f6954f2e9e8223aae8122e88117dd91e9e85d1daea567bacb3b54d632620071bfb636a39c0d9da67baf03f4dfd8f52546228ce2b2ac353b14d	\\x00800003bdc21fbdde769263132b2710994e0be00e8ac794d843af32853776e7a50473225548142e6213d814360f868502c7a2a907ac4298be5880a270c3f50a54e5f300cf4c4782acfee0a4cd2ab95938fdb2399097299482df9f166a9ce23ed6aff351db3aa5604784ff7cf05bb8782dea3385c197e3963e8997cb262f4c430cb3c685010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8b2f11800b43565f863cc7df5d0044b37ed9bc8755a8fc0eb57b47e7e049a9c77971fe67d746338e52fa1ec37e62309fa943cc3e02aecce97dbb7e9b8f6bc701	1613556303000000	1614161103000000	1677233103000000	1771841103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	223
\\xdb818c7716a39a1be99fbd9dd566b5b6dd9101ec2530ae8a9585a8d88ae336b23309140fad6dba2ffc592afd6fc1a1c2f670c489d1f6bc389eddda3f408e2f01	\\x008000039e46ce892ec16e0c3e846a37e316c313f71954ed54b75977b3f47865938466c1f8aa9191f87f5496b6459e061555f869815ac1479fc094dd7a9d6cd80f3a8a8e1e8956d5bfb19b5df2569d4bed27305e62ca3cecb532297a0dfc1c5e83e8f404fa3d1ac7df89caab8970333753eefab7cf61691e7456f337811969a23bf109d7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa75bec48e6bb295a0345e6c7cc613923ee4a56d361d947a7d3d043e84d14a4cb063538b29e293587aeb1387fa6565ed6a2290177743c4473a8fa392855ae3a02	1623832803000000	1624437603000000	1687509603000000	1782117603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	224
\\xdbf10473f3838b62814fffda2d93b4cbd09fc9629351e20cec79e5f34b8c441a44e86389af675dfe46363d17201635b9634f865bc79c6c656ac8dc196b7791b9	\\x00800003ce61067b18ab249c48a6c6da963fdc14e8029582d1a48fe902e796c9e4534d0fad1d5dd0023007afa3c71ee5838d095d251e2af16f99b7e2484aa6e8091cd9c0963db4c077002ebd1873ec6ec9d8bd78a40ffdc5a5eca7963fe34ca9986a7b1ea71eb0066fed68dfd76d261c7dff736d42888783545a26a8e443836cd6dd80fb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x58c20d68d0c44eb47718ed08a4324fc895221c7145aecab4de6291f9e09b6b07b98ed05150624ee674db4cc3a6cfe0d4a89cbea36dbcb59bc7029ab0e7303f05	1614765303000000	1615370103000000	1678442103000000	1773050103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	225
\\xdc819a2ee8fd84336a73e913f46664f27e3d9fc682dd6385863d6a17d0cc2d9a38151718205e67d021276b6a654a3db01bdfc4eecde483ce02fc0ce2b059da47	\\x00800003e2278a82e8504760baea4e555ca4e819dfedb1f19c8ed72182ce1c8eb89e06ff5020843985e3e633c177407f7a610420b2aa6b20af5a8fb5e18426565b73baf586f5e38a19229bba49e9385db82b086eb2fa38372c9920585d779665fc777b5ac569e64f1d5488f438724dba59a13e82e8cc2d2fbe059e571eb92cde5a31154f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x84f63f189a46edf75614c78d8284d3cee0b234c71858487808d38d0e2f4b2dbef7b2a471d4d102474619cfa09d7b0b6361250808364cc25a7c9e5cb1d291bf0d	1628668803000000	1629273603000000	1692345603000000	1786953603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	226
\\xdef5ace0e06d8b453528cbb6e101e0b90ee48c35afce676b8be6a77ec5fb9c248345a0d0ac5ddece3641334272a61c02f6ab1e9e935d88bca452c3f5cf88cd65	\\x00800003f10dd1770692f3a0d90213f077f66b50c2ad6b83ea84f74385cc842b19004fba21f6c0a8c83a89a6cc5d0f4083054e10640f6e9521e962c624d38fd61a0fab1826cb4ea2c56b7029b1d06d630292e8335b3b81a560a804907b8cf41e706aafe8117f766281af36ac512b21d8b5083ce48d4b5304577ca45008b223c2811686b7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3a69d5e0786d0c0770df349de0b77367c7e484d074306ee8d2e2b18165072ad328b1b2025087804f841468a11244836f60a7b133c57ae1a852d135ca393baa0d	1640758803000000	1641363603000000	1704435603000000	1799043603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	227
\\xe88595e7a264eeccdfe8a5fcb8190a0e69d856817d3dceeacdb55aa81b37dfc65154ee453254e7a8d505d981ada409cd0640205d84ebe182d0f9286a9bb35c31	\\x00800003bb913f97de134001e71149aef5b233159a666b160f5a18ca47404a2ed050fc8fcecf39ed5dfeec05832fc7edf3dc75c36e962f778d6f730605ded716388596087434b969d54dd587d9c24fd86bc8a20ade8f22fba2264bc1e31acfb297557ad33af1454cdc479da5407f834c238b4230212f8b3115435c1552501d1a958ce7a1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5f0fa86c11d6adb50e1072805e9255b6c1a6884d4ef2f8efae6ce57bb2f92cee365962a2cc0a3327363cf2fc6d680a47cfefc378f3bf3cf76c76d13c1ef87102	1610533803000000	1611138603000000	1674210603000000	1768818603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	228
\\xe8c5832efe0f8ec9c1498e056eb9e2ebc023b6d31aa75339bb55964c847f4ec8562a7d56b9ea8a21eb603778fc4e8f556c92e002ec57c57d9c4b8189b90568bd	\\x00800003e5343109012c96907786db0f31dc9f1c80a4123a4f600c2fc0258a4a4b540f5fff112aa991e567164a225f7211833338958865fbc95e74b87f69ff5c2bd6ecd41b009bca67612ba196fce18b0c931b6f3889d43adf3e000cab7be11dbd8287fdd4fb93b37336861f99a2ec9973d40899ffef11a8f40d56c2150418b06309dbef010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe4f55027c008178cf430be3b13eaa7a29421e09ae4e040536b25525a11eb54b3919a0f319128f60380bcd36db48edf2ee0cfc61f9fa537085cd38f0f1dc43c03	1635318303000000	1635923103000000	1698995103000000	1793603103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	229
\\xe8c58c7d35e4a5c5d18074283900825d24cbbab31b94f90bacf5fdf34b6d6c9cb6bb4bc1f871050f0276dbdbbe1599696b47c7a5ccba1c44fa1692afb1f7cb81	\\x00800003e2e39e46f3fce0c520d27f6a000fdc686a6905f1cde3636a95f8f3a66bb565ba3ce3538d32616f57e23719118bd6adef420ca5584b1f977ed9725d7d3ab7c1074fe14b7a338304edfdfec3f4f5a725a79ea4740f1df0469290e965c78d5396425a01620b5efa32eab53db68cfa9921cead0d666c9ec82bbc43f3ff41b25afca3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2bcb7329cc62401776441ae007db05883117dc0cd0337ba71b35e05706177d1a5c162a40a5461dbc726367149b3ce22941fe365220eb34b025ba4d961705bb0e	1640758803000000	1641363603000000	1704435603000000	1799043603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	230
\\xfb0d017a40cca834961a583919eaf78132e6a9e3395ab28bf604c3470eb937d67d01d07ebecce04f967a640035841a43548b3e9ad8e715be5a0718fe239c7dc6	\\x00800003b829ba760bcb0c97a7df71710419dc7f740dfcc759a2560f91a8f5f47e8a50bb867ddcb9c2fae4e843ffd249e8204f8dda1c9cc8faaef124fb1d71dd7502afbff112135c4ad82f980d2965c928af310efbbf2ed88237650bd9d62e2f58c498bd9fe5a77d44fa0a6cde61c7b6321308d32b3b71a5756cdd75af75011739aae897010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x09a7d91ace92cfcfcbc78bd234ed3e79aaf7fb7617270d18126d136cca6ee4cfc82cca00f9997e54d02a87bb32adc1364d4c617625fe083d7e206883dd7f3d01	1640154303000000	1640759103000000	1703831103000000	1798439103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	231
\\xfc09d93157a55a97aa0fdbc03b43cd2f6d474fbd6ab2d70c0f255c186b41ac095849e85ef2b1730bc328e47542646338635dc12605da440b7e4f827e35ab699e	\\x00800003ca6a47f57a16701142e4f81f357f2b77d6b89e7975caeed2eb6082afb3f90940a052cda9e05c778ec2a068c860389353b2f4d6a438956bde7690a84dd9c6d9a311e531af2e3b1d0c26ff2094856db934be169788144fb108fc11752e912b3f63d58395c8852b3b81d55a47e8561d57a4ddaad6ec4f51f641be121857cde04d6f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x757a647e674c01fff7b856907254a1b5a6c433c0dd1fcb18f59ad695a3bb17d5c2411028d5366ed4a1be59972f2fb9dfe8f065c423fecb0ddef21d548781e00a	1621414803000000	1622019603000000	1685091603000000	1779699603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	232
\\x03967d0bb0dce7960ffce38aa632a3dfb9dd4b178cb4b10664b58587e45db0579ec2d8946c66ee9ea825db2771d29f72262a960dc8f3f8b2c590032a035c3875	\\x00800003d629d866680178625d6d271238229ee54b8d058772ef31aa3f345a693944746217082b988c896b0f3b738cf27da7a65efc7c377141bc47680ba664f025fe990d7cfcae3d0e73d2e5ee7d9112203f6431aa533b8df1e4be1fc4a536383ffe9acc37707d5a8f6719ac8b67d3a932318731386ef48a6bfad0868f6b4caa217c5681010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe428041f90d7dff1e39c35da5fab395dedecbb4ea5c8238e2e77d68627299209e6adcdd0ee78b7033c9759bcd309ccd1e348c3ea80aabc589f2e23e67d792209	1626250803000000	1626855603000000	1689927603000000	1784535603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	233
\\x03eeb6874b51d9be77a2684666528ed6a56354d3fddc90f593476c4828f389d76fc73325569882d52b7e501d60cc8a164eace60a1ee9dd40eb71638fca6c1f73	\\x00800003a883f3858dcb327c5f00e7536df1d77532655f3dd5eb3814e9a19fdf9eb88f9f963576ebd1f9eaded168b5e08f7f6c33329df6aca21fce96e18aefdd5ede58cffc81690cdebe2e20f5786494996f570bff6b287b04d5eff52f08941a49b76a46585388af922ebf832eaab06de91faa87c430b623c91450df5e5dd7b7bab6a49b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3594392ab638aa5060a5b4f25578f1791eaa1215f6eea52382fccfbf58192c92a33f40d0a412ff405842c2d275c10691a014160be13d30dd96151fb4a3f47906	1620810303000000	1621415103000000	1684487103000000	1779095103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	234
\\x0bce0d335c72380467d13f759a8ba632befca7df841f6e92915b7e9ea26a66b8ff2d3500d0b39b92b067d5467950bd324f97af4540b38e15661455007c051a77	\\x00800003ca3e08c65122287974b27462b09c4143bf5856474a5b0a7650486fced53cddd0a1b8c6576eee0d84ab5913a3b0d6151ee77f2bbdaaef064c9a015f15da092c86616831e861a926489c332b920786588b530ad0760b2995e61708286b62a5019c3e6c7d9c65b964fbffd1be757c086a5bc8a96680cf78c4773b71424b031c8109010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2ea75dee1fa0eaf3c2fbc4eeaf6f57204af47c14d4da0cc85e91762f415ae6064cfd6d66235890817322ef94050da974498d6eb9dccbce36a4a676037ad0d609	1639549803000000	1640154603000000	1703226603000000	1797834603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	235
\\x13cad62bcfa4b06acaa24282f4a0ce134c655697ca18426128cc5c84a7c0c1ac2b373f8aa1e0661a34279e210ff65cade3457da5d120fafc07cb2bf293885049	\\x00800003f7692c96967b880ae19681924b9787affdf4c617dee843d7fc449dc21ae4e27d910e12ce1be1470f7c8f174b312851bc23ef79dfdd1b6aeaf8a3b8faf63a59efbda72e0c27c263f95bc827aac51b2574fe8d446fb4bc43f8eb16869b7d5413385eb28e6dc9093217545b6f7f38317a96a72d1bfaf4072cf0109b142c50e6dc6b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa638660f7856340d4d86fb09729b8580ec74aa9ee5665e360fcea8091051a41f2b642b0f8f82f0eccb343cfa1ea279c08ec5d120fee61fa6682c1aa285cd3a00	1617787803000000	1618392603000000	1681464603000000	1776072603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	236
\\x1496f3bf7d8dca4ef7a87ad0e39b05f6cdae31a4606c35a65f4cf4b26e0056d2239ad3e761ba97de6657534077798351d964fe97e9bd93250a06ccb55762f0d7	\\x00800003bb2afbb0ae68942eeb1caac19d04dd822630d80038404422b81cdd1a615242f73c60351f84617b03dd6624e5399a5163375f40387fb0da9bdd4d386ed4e73c37ed0c73d5d91d16b6653d960fe309f9359247fb14114cddda4a04f4cfae416ac4d0a668d0bab21c35f046c3c2284bf905b809fe48ba3cfb3e36518c4d7e2e3c3d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4b3f42947295528c4f53f8f45bb4e72ddf4b82d801d4f36bcee8cc1fbea1a11fc53a1ac5c76c44c33dfd7ddda88f2503f26e1d916cbfe98e37f8c0913c311c02	1622623803000000	1623228603000000	1686300603000000	1780908603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	237
\\x1556b8aefffc6299582f1cc5160f2e5fb5db9e1eaa52eeb84fecbbb123020e22b7a50eb21bb7843ba71cabedec6c72ed1f08d0b2f2a6fdc78d8019e31bac9e44	\\x00800003aa51fd208a0e6c77d5526e0b1886c2bd5f99586024080101dc0b07ab5e9f2a6d05edd371ad5cf82d75040bdddc29fe360d2882e4863086e739f691f80d6a28ecfbe1740231f0a41316a73d9b9498cc0beb1c237e2188208b8dcf01197a2e550c4bf9bd7554bea7428a361387d3a6995633a1807de4c5fb1420b85b1bbafe79e3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x68dcfcd1c5b8de3ab3250d3e5a721a8f27dbe31f0992c081fec6a0564ec04bfbc1c9f0bc31564c9dfb4033bd14f061fc3542786dd4c2a5c9c168574b7f916903	1633504803000000	1634109603000000	1697181603000000	1791789603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	238
\\x168ad22ba8b6e3a9d823f7d6d56d8f3d560f43083d0de6b485138721ebb73a10b93d6e48003d6063c06dbf991581d9b4a4c5cd29df4dd828a2651c5bf8f0ea11	\\x00800003a2551043eed7afc44a19bd3fafff5d26223bdd51f3e94b06af1890b166156061c1353890dd324ed8a7ef8f746b153e0cbd66209f028d608135025c7900028f8b4c72b08551e322ed87e8e61c52e874b3287ce3ee75c44cea18ce42479f831818637af3c38237ca61768f3b55c46f4339128c23082849745f4e256324a60c203d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb1c0433145be56d6b63923015fe746e851158380085969541ebbf7beefe3fabbf399654b37ed45fa197fc9942367a1c06b119f7401164a0e9081f8bfa35a5809	1617787803000000	1618392603000000	1681464603000000	1776072603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	239
\\x1b7a8f9b4ea500623769df1d18f93e355025dbc8b76aeda260708fb22e3a5e05d73ecd04032a8d168ec449167e1d184d462497d2b6744937efc6786f8750340d	\\x00800003d4eaad442fbdc276727f25a29b527ddd5fd8f99031699f96aac9d8d23bfbc6da471993bb93d2a062ed8014988bbbe012f413d6e642b5e66741a1d1cd7341de7c571e87ae29e42e836d4d4e0dd75023066287f03be3f1d37205ced53cbef1c1b58c0a1e4be861282ac7768394ea3a559f95afea206f587a096d9c169a85c7c3a1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7559c3591570da5f75cadeadd89a8e179c1a5b03dd659dc855651e0e2b9c380cc684566f76c2968b83d173134bced3eb5fa26b78b269270ca7da9895570f2f02	1631086803000000	1631691603000000	1694763603000000	1789371603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	240
\\x23d21eb09403efcfe8dce1074e25a3cdf8a0b2bc7612b8de20f1a8b17e05139517706ad6bc7c8f2ed19c5ed6f0e852aea4fd93568b651d7cf84480f9e033408d	\\x00800003e4173431c47941d13532125e79af16196e1becee20633a7a9bd89a85ee6e4924f9ea30ee564904d44122d4eefc66513438c728a5b629b4cef38e31dc84f5acf2acbd136a07bc03de821fa3ca0e18b72bd38ac241c16cf41f7672b64087be97f1ca4843025d893bfefecd8305077179d9b2b97214ece39c93bf019e38eca8473f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe8674b8e175f5d739cbf9534a5c1bd7b9c9dcb9ed81b824b2e470d9e2a55e491e0949a171659c7dd41e118630aaba397f3f5b3f71f29510f0b601cef3d42700f	1632295803000000	1632900603000000	1695972603000000	1790580603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	241
\\x23c6254ddfff9c2bc43c0f707fc4d7d8359366506b74c4531f438ff3f7df05fa2924391ed60b28e98e31e71814ffaab2eb09caceb82bb109b527c0b392ff9156	\\x00800003f767d4bb4c79f19790893597e03b0b959d640ed983fa9c721a9325b692a2f77e406ed50a8372af1689ea7492e3ac1fd05a8d23ed782082d7bf861ee669ca76b068be78b11239a8bea2b5691660ad62d611775a89839523781fb1fa404ecebb0ece7a7d8c591d521570089222f4b63a15f35c4c78800c66862bafa379327614bf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe6d64d403da1e4028c7a295365d49f3d509ad205a8183668f8b4df7e654d298b73d1f5e59ffc5ec4dc33a67c2ac22800cb5e1392e1919987b296fe9247a07a05	1634713803000000	1635318603000000	1698390603000000	1792998603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	242
\\x283ab76df5cab09dfc1f6eeeb5629eff5ef144b4b04237884b11fa62b1f2e133b9b8a91185f4b1560c5f1560f7883deb69b0596ffb8f379c1206a5a000dfdf98	\\x00800003bc6a6ad8cf75311dd692b81cff31a5f07369297d874af176059a54eda5924e9c9eec8dbd229beca5865851a43c8ea4f48579e4d0cfd2a697cc6325b32078b78b417d00e342d9cacd4e587afb9512dc32bdc5ead84a6c53b22838931e96f39d64754c0e0a2eb896d60cab6e8f20d376bc6df955459c3dd7f0699b8da6322bbefb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe03754e9c73a609dfec2f42c5a76ced833ae8991382c046062a16a2da8142152b58fb9da249c59e5c910b4abc7fe0542bfebde71b53be6e627748850e0e1f80e	1617183303000000	1617788103000000	1680860103000000	1775468103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	243
\\x2cce0cafc90f14013751a1c3e067fcf2a760c8a437b098245dfc2486a7ae27d6d6d041c483b384d13ce2f02c2840130029bfd842a5450445fbfbbb8d6f5564d1	\\x00800003a8b97748d079e2ab82caf52f4bcb69f05d55f63359cc3ad3798e049d38a97d7c847cab52407564ea9efbb6c030db2f602e3cda152d3df0d2db4ccff31ac4f182056956136e2bcd9e794f6bd344274c9f189d5a51b3ac38e626dddfab9ca88ba9a61446d5dd0787b4fe6662d7be26d5d11db89185efb7c2dc28d6ea33b2515dd3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0d1ea0731f13ba0f4bcaf6e999730c14d210b85a0830a4bdafcc31ed83969214f2255469719a8d64cd595e1ca6b46b267e61f2c4d56640dbb3a8211ba4f3b40d	1629877803000000	1630482603000000	1693554603000000	1788162603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	244
\\x2f86bb7479757c36bbfbc51791185077fa7f9884be193a41db2fab250aac0ed3ad9a55cc859e0d20c72a3cc0611d60526b4ce3e487ddb90ecf5f493355bfb1d5	\\x00800003aa020411c8baea55b036670c9d99b467dff42b7c695075ae1daf6960d096697c5504c106326879f27a6b5151079a3a7400f81b1caef10e7c892317f4660a38767801e8db7b8e11c99276ba234da462dc57029901daa4b8c8b05939dbe80928acc95187b38ad7453f2d0d9c97f8b578ec3bc48b543a76e741710ea2e599485a03010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xceb67f994e1e7e4b2949d31dfc2f4c47c43328765e5f98dc59cda77855fdd10682335eb6ee9d7330e15a784417771fcf30fde41c809582075f6ac5c2fdf1ef07	1641363303000000	1641968103000000	1705040103000000	1799648103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	245
\\x332a18246e9b56d8470ebf35dca9a7097ae1213a14726fcec4462aa67dee71d1f2597654df3515ef4c791ba1a1ab691527b671486e8f7611b3d93479f3c17939	\\x00800003de953ef0acfc65b95d926caa59d7aab2fae207b4fdb864c832cab3d3c9eae0c349d8a5dd6a1bf38d456fa47ee68495101c6b55c8d508b19170abfa91add89003db61e497a3eef8f9931b9536489860ac99c29410eea673892f457b190c5b404fae4aac8f9f612445681474f1a3e59123f54ca13660da163a19a47e0de0c658f1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x401c63225e3bb00770699db66919f47f6fe8eb8ac4eab77e30d71cb409fe4ddd1a7fecdff5f1142d597f3ecbfed0076ff2fafa0d297f79922bb660738f9d7008	1628064303000000	1628669103000000	1691741103000000	1786349103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	246
\\x35d2fcc7c6bef3af69b1b095fd37aafa9b423920c3e3a7a789c69ad1e3ebac027b604b73131adee5cc029ef0e9997da6070031ada1e68a22dda1d45068713ac8	\\x00800003d31bd18f9807b19779414174e3ee73ebd332ac8dc7d4b7c19f1cdb28021b6dac9da6cf1cb759065c16a70016ed2a3e4e0255b360065a01e436df5cf400155c0eae05483d170014e477250eb27daf69b74ac3468eb69c740be966125a7dcb4b0a17566e7c81eab60cbf955498e02d143fc5f76f36faa3c91686fc9f12941c9339010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2e1ef0f5d8f09afa96aea941be3b52a90c7cf9b2a79ce5b82a0a274977c51127676e57b6023998811a8545d1254e3c3492167be7a46605473b489245c95f9c02	1635318303000000	1635923103000000	1698995103000000	1793603103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	247
\\x351a641d8f5a3397addbfc4fe573ada93853cc79766eae5bbe31d9ed99f5e2f481ef67dfb32413e69eae1a417a97f0b3e0030c4e2a014696ab08fb859961514f	\\x00800003af172dee9686550be7b212b9f2b09c715a03af4ba1500145abc6aaaf6dda3b1de8e414f0e0eefc53c913aaa3e118235b08234d0f98eb489161912991ec7a1ca8986949650e4ffc04862503322c248aeb3a26534ce94b284fa1d424764b04aaa1c25c1b32aaa6747564be055af641066129a1c779089467e8969fc3b070d71d27010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf073a670da79e72fcb6f911a90e7863b40b809810d75909b9beea5deecaa0422ea897e7509cf57e3e79ea202b6dc9323ee15aae1f0796c5f83bcaa703c304b0c	1640154303000000	1640759103000000	1703831103000000	1798439103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	248
\\x3686834173cbc49a39123e42bb89fa268f110d37e2280c3cd830d0dcb8ae96d187c47d7973e246f7efa7cfe259a1503da89a768452f79a9a4bca40be22f521a3	\\x00800003b5f5b56f8c266fa61abf8bc0eec6cf2bff2f9906b213006d28bacba46f0c4ea1add76645651d2a633523b04ca9a53081b7e8ae5a9d28199194257bfc386de583998610b951cac99d232a25c4f7bf786cec2928c3efd92cd9471aa91261be327a525a9bf368d1322b34bba7462c4779639588f2751ebed3b104ad9dcca572552f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa039f92ce56b042257b4dba068679548107454cffe2a9915b870628674f47c2bb28771f63e326ed6c998f52a701bef442d9a901200156424ff8c95e088ba7d0a	1617787803000000	1618392603000000	1681464603000000	1776072603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x371e5b464bb14d1753c8f21dddcc4aa740a55fb24e7fc345f4d7157dacbcbe519ec994ab22829c5c4e19e1d8f865eb1a01bbe201c53b97d3bb50b934f2631edc	\\x00800003adcccdb2e426827e1f16de0350c10e5f28f1e068a3f7de8d1d1da91adbdd619516798fc636f288f2131f14ccfc2010da502d66cbc3a9f8a2652230be0fe32cca9fdb93e48b107a7d7307861f292d8b08033504ff1ca3d39f6f35bba651dd33af935b09058c54316842bd5290c656a761aa08da8e6d8224ab24eeca9ebe1d1409010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0b7b86a8a0b278cc0c4d04317b1f769f342328422e162b6fcf5a216952a42063cd95266a8ddacd0422c7301522d775d1e6bef8b68945abb5f973d0a82d1b4b0a	1623228303000000	1623833103000000	1686905103000000	1781513103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	250
\\x3c4238e59a1058cea64375a7daf02b8c021fa7188fe5d8c6ce61d19b2e28130b6b8e736a8f6e1c5dc8ec2afa15809870d47fe95b3481677826c2e7a9d1b068e2	\\x00800003c32a4dc34135b22c9dcb20b33bf539edfce8d10c0d1fabb12c148e507a63a5ef8b7fc8bac96586651e223d62f8005e83baea7d423ac751de68cf0db85e71ba8d8bea248badefa97ed5b58a24d7f1f79c477eaaa5af10d113c758a1c1c729dd7ac6952792584939d6f04c8187987f460ee3f9044d11b165bff503ed76e48e58c5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcf37112868d9a6e0a5d08b07d1b0fd82147b1c08d6e319eb321eb14dbb1c0d663f3350e3a79f75f304e3209fad9889038a93b536c0beb9ccf24edbbb8078750f	1614160803000000	1614765603000000	1677837603000000	1772445603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	251
\\x3d6297d19bcae0e710418aa4dda5a38b6e552d3878f130eee25ea9ba3eb12ad09fce3de453aa6874144cbd35ec95e4529bed4c5fe54e3a65c34da9ed3b0eb6fb	\\x00800003d37212502021c2dfa9af21eff67efe377cc713d10ca2ed95bac1b5d9e8a92032270afb57cf724aa38707110883adf69ab2efec781a163d107028bd7989f801968b69255d0d50e77c95eaa3f309bb3990f714d614efed3ce95e4971e960757f9f77d9f578a09e7626a33375fdc3221b54d9a0a3933af92597d4ddd6d9a083f3c7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x761bb2ef620ffbff74f366fb066adb6be806163852b291f1a2820aa94a0828975439aad0b3676e2f0c74b4ca2a52cc0e0f29a4bd035427b829f8b1f8b602eb0f	1610533803000000	1611138603000000	1674210603000000	1768818603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	252
\\x3fbe905033b0e5d93753c43a74fa50d658f4d97fd16e043dee7aa697de3f96775e2560e5b0dae0a340825cbef91b396fc2f36c0194d723a3b484b74b87e8f2d8	\\x008000039bb05e3b936bc2d338ed23582c427b652931aea47ad845029b92942edcf67ac89a24697bce360996bf1cb4fce302852cea09c76349da75515ae2c58dc2baf963c61b3a24b0b06f302c9bf4fddb81bab2dc84ba906eb264585e31bf70e8f4a41e3ec5e7f323b35823b2859373698f48435a76640a66eb5c57bf34935d11f405cf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4b46c37d8ef4ddb2ed4868c7172318d8013e28777f93ec668e79feada18eb7b696ff7f4c57483ac4c062fe0f1862390b0219098eabd991098967d4077ec5b700	1624437303000000	1625042103000000	1688114103000000	1782722103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	253
\\x44da2f6a1c3d86043cc47fa2fc7ace473ec5b4348b9add0856838d4bc37c329860fbaed349503f54c214686e2b92ec84f2373bd62f3975575817c8272aab8516	\\x00800003d535ca4bec37f0f3d06872c4cf666badbb4e2fb0952ca19b3f0eeb71b6550074f753429f7700a5e2ffdda26a4257c4aeb12c65cbde465ea1effc51c096bd092b8e932deb78b99154a942cb152134d69473675c71f49a0b0caf341d2655147de7a8fc4af54e9f6574153ea4d7ca2375e4c41d161f68cc309f496f31a01fa0a61b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3afdb78907fe00b2e5377923d9fb6e38597d4ca98c12a1875f66f8e6f7ea3f8c7ff9e99054129f453f9ccbcd2c73b07ba9fd7268a5bd04ac1c88ec2ad0b46708	1616578803000000	1617183603000000	1680255603000000	1774863603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	254
\\x46fedec035de5172d38c2d6bdc5cff737f51af41b7194c15088ac92df7d794050f573a6ce1ca50878681251259d38ffa4b293327b7650cf1b4163a8ae99fc442	\\x00800003ce26ecd05f83ebb9640181435401430e4c0a04f409e3e98227ae1fa4cbecd3214319c20aba9feea102afcf1d2f8253d4d64d449fbb3e4df620671f1b1c4ee35d14e3bd7b2a2acf4d8df593fedbd6499154e67a755e90474642ae6ee8626801e29936d6cd8819f2acb9df77ed4c6dcfa92071dc9742843b3e1f7f1bf53bf492ab010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbb704adf63db097f73c2b762c2f35e3fc44704c5a70eb61c4393c332278ae079640385d541794c1fabbeb8912eef7541bf30eab58a3c700e1342a4d5fae1a802	1617787803000000	1618392603000000	1681464603000000	1776072603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	255
\\x487254b902f13325f8fc5c801356451a5081fe9a43127aea9079532824a2a7dd8b110336c49360c17165103b8039c7e48eb443b1f9b7ba3dc3b37eb506984bb4	\\x00800003b9599b19b3d57ba447afee42f06fa13a330ba279147e574ca5aa29fbadeaed9d16c6f7153d4714c8be371088d84326ce8d8b2a5e4e1d3aef6256922911a3d2318275c1b05af69e65687ad700941af620c4bf26ce799d4c9debebc70cc74fb30df62535cfb39de3c3f861941c01746d932ff21f307207b748f17c4e7397fc3743010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x95c688b00341933d2a7acbfffbd295aaa94f3f280352ba6d0d6a1feeed561fddfd640234e6ab58f3f59607b682d51a997de5ca102c5883a192f6535acdab6f0a	1638945303000000	1639550103000000	1702622103000000	1797230103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	256
\\x49e2f2a5d10e0486bc74158874db4c8f90054ad92d4b9023b77aa1dd1f4bbd0331f39193f92bf1c6374c6c90c1fde763c5b88391c53883d5a5b2cc01b1d73105	\\x00800003acff90abdde33230579da1021fe7a2ab99260b707a4e95f04510caa91684847e6640cd44342b74bca2604d94716efb4019e5eccb032aed050c28452b9cf58074b4bc71836cc4fee8b32fd93fd38b22cb589fb0c85d311cc09c3d1938193ff72891aaee9469be28466e802b64a282a5c888906be5f3abc4b2084512d46e679cd3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x79beeebf00379e44fcaf68471825003da335293b462c0211091ca3d87a377110177b8a3a28e96ef7c8b4e37c3917453c5d905b67705ce968ddb2a9dc7d89b608	1629877803000000	1630482603000000	1693554603000000	1788162603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	257
\\x4aaa00c7ee6dc8e2e55c079c85fe466d54174daf0fbfed50344388bda16217c18ac8d85c847fbf82fb08155e82a38f0b023bea4c0a79745956206a103c219336	\\x00800003cadb4ce35439ede639fba28c8dde1678994f24f3d6ac6abc62100c1f0c9cd7b0a62519acb5d3b562da08aa5773cd009702759219f10e266990695933366087ba7e5a9ac8485d5cc3ac04eabcf64c33204f5f51fda9699b2c386f1fec2fd8ced3e4b201bd35a9202769c970f6f3bea2a10d34fb84d1069a6d6bd4a27195f2f813010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x073821af588c39c6e39607596f440720d52f949890a9b180737aa56514ea4c526b99dfeeb737626d3571150e727855559e333468e08e64f4f1a5f1b06502e00a	1620810303000000	1621415103000000	1684487103000000	1779095103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	258
\\x4b0e6158db04c7fcf750f4ced62fa9ac3f8248436b360a35376ff0572418004ab567203e41c93af4d916293d7bc2df376937a5b2ab9a2b92416d5400eb3a670a	\\x00800003ae3833b2c18543f55516d3a5b12c1f2b8d7cf417338f3cc3cd19ce7758027c832d28cb482addfa1c51022e46597f84d85fff7d8b2c9ab523eded77904456f2e3fce188d26c04d67f8325fdaa5a45cc1225e1af80457f555be41412164408fd5682d1b4be43101b220c0521f10d7fc11996cf05e7c829fcf41210bb449b9dafbd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xea1b9b79a278c3729b0f97420d498e9db3303967a579dcb0fbcd93a7935a090be751cb2b4065f08412d2e24c93aa48151a8aaaccb42a2cb0f300035eed5db801	1617183303000000	1617788103000000	1680860103000000	1775468103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x538274994345493fda374523c24280b8b6a0bb4d7656a0a27c78b43e2e592e68ff6c95a8a6927896b5a3efb532c2b891b5bd4c1448468b20a129840cf3374a72	\\x00800003c7ab46791e918f726bb3000eac4e940ce8ecfe24baf543f3c3d6259a77e7db24414156b4ae29c52c6d55901169ce193f738e650261d3f1cab9d85174a5df9afc85af948f2775a15fe07f361407de086cf9d36a04090b5ce37b89c34bf8f3618cc3a5ae88a052895c79f15f238410700c13d29bb510ec4442fc969a1d5ec5c94d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9b1304c1aa3c8deb0e885111625b32abfb077ba155f6db9c4ce4a47ddeea1b0b5673c23d4545893c2fd3df9d05d3ebcb6b0be5ba7702396f2113447e3b094f01	1630482303000000	1631087103000000	1694159103000000	1788767103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	260
\\x56aa156d13056346b49ba478c458c47c9d9e61570b551cc41349b534f15dee09ff5babc24bfa614e69fa148f71497a605142b0336de76c683e6e05d925471c5c	\\x00800003cc683718c2a9a0142f621442e1b63021f48ee8196ba3296f4274843508b4b033dafd56c61e7e41e87d1981f326c571d68f08e9615fae3124dfa05cf1a207cfafa515f2134b4f7aad95da4ec33209448428c8dfd8211a5c380f0b93e55d63398546228aab510969ff462f3ddb6e54cab385c3a130232033e32ace7f1a763dce27010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x88a04b9c521f7ab2db29f5f15d7c82b4a4255fc3b27dc66efb057047fe8813b26badae0df339736c763745b7792b7d2343bcfbd244ebc73d405abb9e55899d0f	1637131803000000	1637736603000000	1700808603000000	1795416603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	261
\\x5796c64cc2135abc9a70e23c93b443e224ac1cf72e0ce674634eab16bcbb5cba4326d7eaee6afeef6b1ff7eb43b13d9d38956f46f33ba9cb59eedff870204178	\\x00800003ed7e829b8bf4e65f7fe4780ec3627233fac28ceeb2495b60f8697ef9e93900dc2e9dbc5e65def698842885601cbba0bf633a3234e7166c5f1eead6fbac4ea17eb6883592bde08fb768555d73305d8a542d9770e643cbf37813fcf64c038198dc729b40a8b0b5e20115a4028028d471fc1f5e0a06fdb1a70afe4d4cd4f2566d6f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8159a55b85b4634f1018c23c7c6fcf1ad361d02d553f48db56e6d01597cb08cbc6b447eade1438cac1ada30fc9b88132de8d0cb3e5007dbe08f60968a2c37e01	1622623803000000	1623228603000000	1686300603000000	1780908603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x58a2b3aa66d2bb33e230c20a64a3444523b3f6dfb86806316aa7ed66ffab6f7a12f9819f87c9773fecccf24fd955c574ba9492bcb4a27ad9024a91c82790e3d5	\\x00800003e4c48366b56bca14c013713549e2fb2d8ff2651182e42fca9744e38f8190d2469d5dc487471044ca0b16579b4646419352f14a3430156d2eae9c70beeaded91c7d0e07b16026ce21e98adb5341a512a5aa46eb0743ab8e20ec0f3efe274a99dcdc20a17e2e58b2a2b9207e8c84d82f6af373974d5b6465af87c21d344c58822b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0f0ed31c0ed476dcf177406c02209c2868472adaf20b75b1a88c57861cad74c570531fb8848e213a2a0332ac3d84ee7a847fe8ddb77c863943be4bf3fb39b208	1629273303000000	1629878103000000	1692950103000000	1787558103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	263
\\x5abe9bbb2bb0dc3ab7f5186da9b8c25fa795953304cf28f52dc74883961fe342cc4bc40d01422dcf271fdbb80f48c048a829eb36566b182fe3f3884044dbe941	\\x00800003c45d72f2f761ba09b300127c2c719f39170dbe57c69a1ae209c19ea807e11f843f472b2cd5233db65393867fcdb479311c1a84af65692abbc13ee77808ce51f6cfca8f7f3cb0c51b72fc995be26e860c8aedb381048136e01392a5fe6932b06e661e38d3eca00c713506f97fbd4f2f96166d8c26f223049c0532de48c0235bd7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd3b3768b14d84361d8cf06123c987c870dddc6531d5ae13fb5c3e779cf8ffada61d85c1b8095579fa782311e7060d93aee342d3a3d75556bd7ff5dcfed1cc507	1612951803000000	1613556603000000	1676628603000000	1771236603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	264
\\x5b5eb2056e67cc7922152843534f708802fe3df705070f7147f24f6c768e2d8da86c36251e912ed277feda78dfd35792f85e8244fc68c48a47c9304fad3abbad	\\x00800003ed243d9ddc44b464ddf4af7cffb58b6e459892fc35b8f36b720105bce04525b03865854b3a6f1265c7ad2d9df561e038fe7ff1d0ac5dd9c07679349c140dfe70f2c32f9070c1c298c93d290bf657c49c80616d1cd59b7b555c24c9b74f5e03812835f41f766309b19b85aaa5470fb395e3123d491c37f1e140a91b25dfd4a77f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x36f744401d3e21a2120a17f25e45248f1ab43d7525071093b86b2a7978d715e23aefec4c6fb397aa7a1c58fbdd314de7920c7ae25347b003d78b9a99cf130400	1609929303000000	1610534103000000	1673606103000000	1768214103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	265
\\x5b0e5adbdaf386f522e4e56198a5565a53db5549af09d351591e41e3abc437781c66b61c5c51d36ab43ebb56ef52c15f50bf2c3a352156885d421f869f965f52	\\x00800003b6761dca44daec47d324fdf88722cb1b2cdc72b37eb743b04f08ab43b898909d13bf995f10e572a767bb71f21b8d49baef9a0508f3e87007edd6ef1c63d46ced28bdd863a3b3e205d01912a302a59a79838ce3560b038508a506db6a3ab58919c4cc6a5fd1b06d82c5dbaeb9b7b1ecfc2ea1c78b317e078990a650327f3a7f49010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x32a0f41d1e921676122b9f31521fc7d999f22564f9e36cab94b3710b6fa442983a72b6141af48249a4e7b67d3c28de7505b7588a94bd6a0cd6acc21d9db3a30d	1638340803000000	1638945603000000	1702017603000000	1796625603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	266
\\x5eeaf32567789a9ca9310cc77534ae555d1566689d837f9eaebc0186dc8ec894b967c74740b73d5e7548ce66b35c10b4271aefae83cca7cf4a3984d6772d86c3	\\x00800003c8cbd0662abfc27ebc1904840cc6861710ced785e3e6fa4a21328e44d1d57f032ee78d2a82d7a8586ab47d74e3dbc731d13b5c2e6ae79a2407ce723eafc7b7bd8d7440622e0b79802c05728feb8667eaa18f45112c1a919df2604d2aba2cf7e59dea3e54d952d4877c490b3f30c348f21f385540b02fdb4469facb5f9d5275ff010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2d9b3b0b004de3f67e4d0279b5f29a381780cb8474b3a81bb4467d42558b4c67e55b8e8cceaf025ba08fb49da6ca7f532d7cf9b16217b70648042760b51ed305	1625646303000000	1626251103000000	1689323103000000	1783931103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	267
\\x600ab39ddc5fa886efc1259dfceb9578e8c6b4e2a32c16d5cc2966a94b34acd2f317d09ec924e414fc1982805ea3f2ee4dc17dec3b6ac9cbf331fbcb8a2abd8f	\\x00800003cbc29e9c84664a32021ddae065dccfd66af62f36af7323e9a337472e917809d07a154fed8cc40e26ea2a06143edfd051dbf0dcdbd68adb31c7b351a947df7387634d0f8c6de8e6b35ceffed43fa05b4f3969b5696e515bfad0867e89663311af9e34dd3fc7d738972907515447fe7cb6cf48c854ad6cae00cc98d4ae9ed60eab010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x468f780807136ab7b7d409b6c6a3ab8f7ce9df35c1fcb1b7e88ef3f8fc6cbe9e2659d533cbfa441f644ae3cf43b209d5a6f9fe3ac87fa4def03a36df8bc57d0b	1612347303000000	1612952103000000	1676024103000000	1770632103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	268
\\x6606cd68e9162e5c7d5774ce342cbfe122bf2fa61c6bd04cdfbeef19398069d1a84156afd1f36bed8336c7a2b150e091e0361aaab0357f7046f626820a6360de	\\x00800003cd88269949a238f7bdb80c6e8fe8ef4fc1c55e2db1224ba480714fb70405f5fadd2f6ebd5f9f2c8001225492e0cc45771f8b23c404fd56c352c7f83c49328cb843122bf967752dc63e4c3d9f03b3ad726f0e6a68e22e9325f4d316860f3085c22c2f58f3bcfd332030a87812e9edc5d615d5be64f70700b9449dfcf50092b6dd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6a4f98efc9fc166d6d20864efe33527779d002ddc6f41f2b07d8e0fc506804681586fe21ea493e52ad58a55424f23811ae4a904cd217a8de8b939cef6b24ed0b	1625646303000000	1626251103000000	1689323103000000	1783931103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	269
\\x69be477ff4990fc3e8dc6879aed99c86542d941c91f346fcabc3be542562adbd6ec5875fc2dc0a264b4184b053ec22e20243850baaf6c356a80eb3a12bc80e62	\\x00800003b9ac60d6ce0b9abe32f36af1a2c68cfee53f80209b35d1cddf4656fd72a766e9aae8ee9f759dbb9e3e250ed5abf758382b54c6b87935c155ecd44fc05be7581356896709742ab8418c9059b503544559c3d24e818bcb3b0b4d77c6af1fa46f518f921d805b5d94d284bd3c5b74a634cd9ebb9c9fa4f0d16c66fe9da5c6a45d77010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcc42fe30f4f40e88a738e7cd0f8bc22597ae88e388fd1702449c9bcf496faf213bce35dc1e73488a7e2c6a90a1540ffa1e1a651318f17d4403f6d7d1984e8309	1627459803000000	1628064603000000	1691136603000000	1785744603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	270
\\x6cae26917c0ebc1f10561ed6227eaa546e4942446b584e4406c46ffe0500992f6c43ba27448e55a1690d5bc3364d99167716176f499bac7ed399da9ef1e097d7	\\x00800003ed1cf573bd9209b6233df8980325d69db73cdf0f4d1088a45acde9b9e3e9fa269051a5c936342a111fd50a6530e1a89f341064270bc51acc84d9eccbe4c4e4903301906f4b8deaa70a1f6fd51dcfed247d91c12ce3ce0404280a7a4f9bab680fa76ec3ef6085a607edea6d0c649499eb54539810795ce6c0a19d176f7bac8403010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf3d4289f23dacca2665a5b916062326a884969dc95bcc08fcd6e9a169c1d5206799f0545ba39e4dcffc373e2f7df3a5e8f826b6c891b07e4a0d74324caf7b803	1621414803000000	1622019603000000	1685091603000000	1779699603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	271
\\x6e1a5be575620e5cb7eb64d92290ac0bf9e571c4408fc576a7ebe1083c88d39630c1ad850af06000c956d1afa4daa91c18f4a4202e246f969ef72462d5c27800	\\x00800003c0f75df90924a1a7244ec3dbc8a8abba91cf9fc572ae0853d8b7d65e65625c3cf61afdcdced7e0256bf756b3a1e4a55dc7bb65dd1275a9f27841c82944d40875a5c665755745ee995c83bb7fa18d5df524b0ae8fe78204aeb6f052c4d4b74c6ddc064dd5727f8861c76615d5405e14548688d20e2107e3abb719beb52de3ba77010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfd3bb503d8af85bafc48f91b9cf29f4f9acd83481a77afbae00bc185c56e66e43794c900f453b87fbe46411a15ef87015c5581b25cfd373aae1cca2fb7c33a09	1614160803000000	1614765603000000	1677837603000000	1772445603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	272
\\x772a6ea770d34d04ff4af50530a2266bcbd72a3e2756b42188a708e5421022a78d9a11983c4ed423fca06d93d5ba45379724b080e4b826b5210e5b8fd35bde72	\\x00800003e1265cf9144a557e2062572ea3ab3d6e8dbda41fec1d1af1f258bf3f05508cd8f6ecd42e0553c728a4a60e1ac73f83f8964fc4651d3b3e8d3b3536ac39b5b9e4a390907b7bf0e9d2db0f1b1fee3d66e76ac9c77eee63bee62aca5849dd90d960c4468e2dce17a03df42adf7699659179350908b206b9a931ece0254d1f5762c9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xbdc1478397890bc08d87c22e3b4a55cfbfcdd647664d57dff42b2924f6fc4b4ef59c33f70553686974091abb6b7e7a9dbfe7997b24855a3d8df786d1045ab701	1638340803000000	1638945603000000	1702017603000000	1796625603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	273
\\x7b42da2d280fa170c9450fdd2f3db25112d531644819282aa36067bc1ba62661ccfed82f64b1cad0082ce6a06c0dcd55b67dbfeb0dcefd41385ff7507406dada	\\x00800003c4cbdbdb2493b315ad180f02f9ca32dffb8406c14ecd78cb797f5c066c01e4f4a0d9b5225af475865177dbd4946ee792d7d025cf9a3616f20ee4f5dd4869e710dd17971f48ec5d041ec4cae955b5d779ce330b271e1579ae2f3b84b8d8cb11005d1aed826a97ef4027f5f05038416025346aa638110e2f7e7eb0081189c3168d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5813a633cd8e49ef3d6a1d80b779a0b996e1d0d3ecacdff4ce33240b1bea2921e33cf6aa465ec8261d6a04e6167294e92eb65f06757004df6c03a467ea218c01	1632900303000000	1633505103000000	1696577103000000	1791185103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	274
\\x7b72129c4449b7030cfd6c3343113f7d6406948af330ea79560d07439ad04893a85280208bf1b335409f345725013cf8c09b99c8f8dd7da23eddc79633c28830	\\x00800003e82c33ab7aed69ada5493f9c5a54dbc8f9097fe2b259e8f9a4adf31b3ed3b0ef52a031c357c35a2b21009e6eef0e2f5dbc4910be583406941b0a63306ab54e3b8701ce7edadc080c77afebafc6ecc9055d068dd0e609ab9bfe413a8da80b3ba1ef5f5b110fd54ba41ac5d3cc702105cd04cb8b0f712d9cb34d402c6f1e21e565010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0bd95d2556acab07a7db59bc61cc087defe9f80f934a3bd49041975a99d716c4d818d84ec6032414425f7019593b3c1096787fecda5b2fe9ca7ce5de91b5060c	1623228303000000	1623833103000000	1686905103000000	1781513103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	275
\\x7d4ab868fc734b65f836a884f1d830fa076cca0f2490c3e93d668154afdbe085cc42e6121725968c7583c4661b1006acf234e436caf0f7bdf9dde19c23842228	\\x00800003e22e56d33d5478d4b2ef387acfb3f9fa6d060ae33505edbe4eb5b4491f55586027328c3bf34279c0c3491c28b87b17d92d82dac5df39e1bba88649bee7f0a5e3939c993947a156009dc0c6f4f16212b7d33e7af05e1493a63ac1829f04afb28216035ee4db5d5d232f6534ed6f1d9e996d9d8a231f65e638d0b6ad0107f75a99010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa3b35c9e41b446403105c20c2549a33d7e49663e0f80d53a54f05d3cbb7cd6c72974a4f40cb7ed8d60fb429da04f8ecd3b993ac781a16d7dbeae452710901b05	1626250803000000	1626855603000000	1689927603000000	1784535603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	276
\\x7f16a4b04368f10dcd777e6548497cb9d3f7e6ce40a0883507522d9478cb8672c75c77c0fb94c78a0743c74c3fc97e9273a418d40abf14fdbb7ca65bcd82f094	\\x00800003ac2f1b035e4dc619204ccea58d7177468fdea1ccd2c2bc90bac2163f0af085985f7110cfcc7c77e88d753caee2bd0fe8346b06292814c8d0a75958cf3acd35cf5732e4483167ec31ec0c807c1d3f6040375fb03a88a1c8adcbdbcd8d27e104569b8b83975a124d9345ab312531892fb45676c4ca03ad973e8d17db9d91b5244f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x0acddbf3d2ddd0dedefda40ff0c98695b19f0161ad200a61999cdc246203dbd0eed86aa6b45a3505d0eb99cf182ec28f494fbfffcdb24a37352d702cc6acf706	1615369803000000	1615974603000000	1679046603000000	1773654603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	277
\\x8722ebc3927da3cdbe6a5c3d054f7d446fe2b3534db2cee19c18a36d9a6f94071c5b1772f29f31364db55b16d4a5bc3eab6bfbfb6e16c862040387774f8e9104	\\x00800003d8e0a54986c20e7a5f62dbf245cbb5e36009cbc058abac73520f3be0b56e52acb0fc0b87f5b3415880ffb022d9dc985da1d0b892cd9ca87d00a1cce47c0fb295fd39b0108a2e6c7c4c5b087fdf8e6a9c74e08f753284f08d56e2a10957787bc002d330b9a66fa2f1cb4c65673cfa7c3ecb310f9e25c2087611daeaf4c42ae035010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x81ee45b8981d4fdbacae1067cb3244fd932acf14b91ded991672c9977fe0552e4d4b2bda34b4e2404081f20855dea54fa5e7f90f0a9453d076c0efda2bc89208	1625646303000000	1626251103000000	1689323103000000	1783931103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	278
\\x87dee77aa239db383b0852115bfd0011fa1b910c4e3aae8946ebbfaae509c5f4916197375f4e582439c79725b79f4293e2dd187bf2018755776b130499fdab67	\\x00800003b1082b8aad921c41afabbb41784f3cc76772fb358c12ae3994cfc836dfd282582cb3ee19bc2589eeb6ee5884ad8e8433f5d35bb8d4f3cab2f78e62188f47647d05955bb227a7613dff38f6205bbc3710fed6fd2f050e8ddc8a9fbd09291c8e8441cfc3161edd852c8a6d20466ea8606ba2a2600b07e078a82ef6c10d75a30e11010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8dd505632b44a456265b93903a01b6c92f618de357641d00f0bf26e1a48cf0ae083b6854d0f82667e22cfd72a1742694abeecb4cdfb238d34f38f22ad4b21205	1632900303000000	1633505103000000	1696577103000000	1791185103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	279
\\x891ac1101bdf89b406b4d6166c6948673cfbb8ed4687bf90f95c006aeb1e9ab8af004b9190ee2e5adc26d5d9b48d349fb316437052b6b2a3e767fbece8f2360a	\\x00800003f40cc5e8e1ed29177d0997391c2e5f5f5ba47b91e15458400773af53341cccfd3fd7563525994a5ffc4f9489bd2eaf8264f9fd158893f597bbfc942274ed77c99d8df004e781458f8537a8681d1d5bd59816bf3637dc8449963e470181893d1d156c256b4bb460428856e0f19d3aeb997e5409455be9e151da045f7d91db35ab010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd32214b5e2684390b128f1941188ab5d264ec15752f7a50b201572f6e2b0b2cd99c28f780ee023cff861fe7e59351dd478f127fe3a6dc3345a75a818968a1003	1613556303000000	1614161103000000	1677233103000000	1771841103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	280
\\x8ff2bd17a51cf3dc28aada5d24279a0f7f3e8e1273ff226fbb5e58914b55a4e9d0062fd2904583b814fed35108c3352295a7103f7712d5c43452ac1ea4f41e04	\\x00800003bd10e0722a11227c7b042885d9dcfaeb98dbc4453f6f416204738ee097df423b3abe8905000104077f4d6369905f28d832d1af54e7a978169ab4d96f08846f64ac2e86047db7ce0f9a4c3eece0bd8adac9161ce336b99cfe7570cd998cd0df3d727ac36f4fceba15252b82ef8de9f68ec5e4f1fb6b4e77a5cd1d7ee6e7cdf255010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4dc015e79772638458cc18f54f0386d4e2e3f63aad67393494425b1347eb1672a384520cdc1f2aa4b0c6ca3bb06eac071f285a84c93fcb90c20bb19d51cc120e	1634713803000000	1635318603000000	1698390603000000	1792998603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	281
\\x8f0e7925892b94cada4353da23024f5c0961e669259564558e4d54202b98df355069e7f73bf221548cc6aea5888763035a4124811913b1c1ffa61833d35e8b9b	\\x00800003e48a2b4a4db5435a0efc2c30214cb55c5f2a8c07c77223d058ff604e861cecf2766185452acec64db3e7770248218276ead8eefc1e8caf04ee0f56bba60de83781df95f48c3995e865e40f8341b0b9263fce4fcd844f1ef3526778ca54c041c906966f7d0df977113ca869260df0fb01fdea959de88eab43c1179c5fc555003b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x52edf589f69ecb28d2af60a9d83843175830f378c1e87b91c1685a4f81ebde5bb5c9618ab715a2228cfbd116eed18d5a3d1df6937af73587902b9e6ec4a56306	1619601303000000	1620206103000000	1683278103000000	1777886103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	282
\\x953abcdbe64536cc0f9089e6d2b1782cfd75340ae5da633b3356990749bfd215b2a0b8399a9473612c88d0b1f2dec85d21311494b0ec923472a77b5161ce11aa	\\x00800003d12165d5dc20da35d5e3607ed306e6af28df5ac99a90e0407a4c60af544b30c03c75d95c83bb9eea67fab898674e25b30d1997dd2c5f3306f4a823dd8a9c1fa85ebff297704263ff73fdc8415539b75ecd709939f1b88abd2adeddb3f232981aba4ac962b95349614751270d1eb98c7eaf5e0542ce304b1d40674fd64c9a78a3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3e6c5ee501101cadf92892abb16232a1d871db90efab715ae0d48a111b3feb0a19bb13b5f32438ac4ee6458421066bd74ca93043c0daebb7c876f3489c8ee00f	1626855303000000	1627460103000000	1690532103000000	1785140103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	283
\\x95f230534ce36e86b74583d4f2197baae337aac72c2090f78f85a2bebeb4de4b7d9d13229a33b328be95aba130a5a96e6ec011e7bb8c248fad511b49d863e652	\\x00800003e04de09a63a0d1603fff268943f293baf143dfa0ead2c953b6c6f5a0f34b40aa5a97333473933d90c6edd562931fd9dc788468e65006f43db86e79b496c4252c0dc49d799f3a3ac23689aecc603f17982b874bbc282a445d6a15e385f486f621fe70d0774e0f8f2dbf8f104aa0e75f71674b66939fc2e1fce28a53112eb6ad5f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc7de258eb7aeca47175befefb71a57cad7f7372d60f779117b71e0e6af337c854863e5ed0e7ed67dededc4e4ec52559d5ceeca222281f008bfe5cb74da60bb0f	1618392303000000	1618997103000000	1682069103000000	1776677103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	284
\\x98dea645e8a3b2f643413a619707d4712b166ffa5cd24d81962602fc5fc113268868600d3de5e79c1b2422df626d23b6a89c9523ab8049404d5906dadd5d01f6	\\x00800003be2be4e611ce71094d60d406edf365f71d917c9764352f846c06a3a884d9f2e83f215469a509892482250531d22f21728f14c40909d2b9fd01c479ab30e181573a728f49c25dbfd190648d8671a0bf5923e9ceceb0c4ee24935b943cf84786e9109de7e9dd09f376ffd96457e8dc80e56b5c38d1c63f3bd50552d1b22c87c145010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd745331bbc77867a5476862cf4bcb47b412f8c767392aef9f1e088aa197dc196204455397e1fdd7cbf263799d0e6044a26c83f621d4383f5f2f25864eca45b0a	1614765303000000	1615370103000000	1678442103000000	1773050103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	285
\\x986e73adb179ef153cebdcfd8b417cf13770fee0b67f4304ee8c5736621d466705b6a623117cbc024c0422e0836ca710c3ef2e27b6a792499eca6b85a5d4d9b7	\\x00800003b702e80129df8494877a3eac0d5762451eb9198faa079e9157c662751092f5138c88b2d54de3ab456c99fcf0574ed5f44150e09c87c1baa87a41769c79c43673cf5135e7738c27e896cb04a88f900ad934866cfa984df40c7afd048e0421ba08123940870675d1abe1075f22d7f1c39d2710808ae02836ade3e07eff0e478c81010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd9d0933b58fcf969f1b813345036dfdb9df2477c2ee687543848c35b4f90b9a32313294b1d0dd736998fd1b1b135f28e75d81773c62bbacd42c889a0b01ad50c	1635318303000000	1635923103000000	1698995103000000	1793603103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	286
\\x99a2557d17a23ff7ed20bf5964db4f9dbf2cfdc4aee16bcfad0754e80410f5b70a7b4c0220002f410d5c3415163e95289be21957f6f9d80ae1ce325bd417f13e	\\x00800003b284e2b463e818b7a9e23a42492d8e527a76795e5504c67112e72e46704b9dec8acac8fd7fe62160670dd347e88f51f27589064caafa149473cfc08d6159f7785086943d3e2e459e2e1902866278875a0a5cbb5f9bb3d9ac768605ff85066451d03274457b6bae8b42bf17a579ed40e3f5cd57eb244c530813af0c065059ae61010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4920124a2db3c4685dfe28e594560dac47b12a406d556662d98c5e168322b8e3518d6cb423788eaf116bc6d21b084b135d3b3909919bd922164bf9c6f1736f0a	1620205803000000	1620810603000000	1683882603000000	1778490603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	287
\\x99f6287ca43eac0c6cda473dc4829479f2b2fc46c173778ab9702e84b8a35dc0efe0c2604bac964100b3281ec178d9aaacc95a8256d5d04bc1dd2fa092ae60b9	\\x00800003be593d8b9adbbff3733dddbfc84c4b83af47d4492f987b9ad4600aeb08d0d011c423d4a89b7e08578fc25542d328d368563182dd08f11e23718cce5edcbb22e75ef32b96c554ea7b556df9378fa685a26f2a1234be3e2170b180633d61f83aa99f1976cf025dff2442f363335718211fd4d8c8678a40be8c296d195768a2277f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfb4359684a96f04870f19e23eea40371f7b54fb7cdd6af1fc050d0e938947d8a3072d2e2e592ef1605c1b603e2b64a86678306d2b6ce289e60b059075b7ed10f	1636527303000000	1637132103000000	1700204103000000	1794812103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	288
\\x9d3a9c4453d25cade57dab32f4eb4226b0cec983a5c3615feb1a593087d27a62c4b22d57411d8fb0c895c22c5d5f15e700c6be15def0a4d64b33b4492ad7f49e	\\x00800003b8f0ff80b4166892fe578bd0f196726bce7febf945026e1a7a3b91c31e7d1274cfc776002c3a082a9df903fef156959822451592bbe128e31f81bf1d8dc531e62aed036d406142e7e729e13753019854aa7805db22f856763b1c54a086d81fed590ca6f677af182abf125446eb7f67402e054e4fa99a9bb299413f2fe5e19109010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x91ea3e3742c41ea4ad5d108793989a2aa33743bc415a2d9c7df217459b3dd0f9698c35da8fe5ab165bafcfa9012c1a2f1a9f27665b6614b8f775c33307037702	1622623803000000	1623228603000000	1686300603000000	1780908603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	289
\\xa31a1576f5d7720d5bf4c121ce69980c364f62f02536f85662185aca1eebe6963c6ed520d829b3e656a1400d3c5f02b2543290339054ca14b0a363eaf34f3112	\\x00800003bcf6720d4e6ee4cdb41888c268b38539acacbb5e007d54275bdc7e0f38e64cd6b6c7a5b316d2303a614f32d5cfedf6c00044b01cb7f630895aa5b8bae028560a4e31fa70958c84de9d76d8395bb7417f32c67b01d7915d8da5858aaf8e38c0327d5b646418f89cc6f630f19efb69d4c0b6ba27d5a0da39ee03f58fc9112f2d2d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x33b4cb3197026d665a740bdc83adf4eae2e9de0458a411aa3540276828439cd4ac1fe4d6d49fb0117b06c1d1ea4d0d181113c8974a00026a0e2d9087f024aa0e	1626855303000000	1627460103000000	1690532103000000	1785140103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xa54e764f3f5b4abcf2eb84f2447f331d1209449c336b8c5f7e311ce32aa2480937f5677973939061205e38db1aa263053e41c11cfd11bf1cb0e4d1f0ea3cb97e	\\x00800003b61d4dcddf4efda92a29295dcdfb94c150c74c0387c6e8f0d8bbd96f03bcd62bd2c927f37bde0315f750f725fdeb8a3b7d90b294b4f5d5eb51751a53b7ebc7930d90eafe161b4db2eb05dcf91239c47629c55be0820c58756d9ce9af9417fa224e1142a4cf9ee44b4fde4792bf38f9a1cdea848c78ab2690143a75189cea9301010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x58c4d19e951b60dac643a643d2ffd8bec66deaaa1d629440492ef883e31ea7af3802951587439b7f482cfe488219066fdfeb015f08f75e67869c0128b61b0906	1612951803000000	1613556603000000	1676628603000000	1771236603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	291
\\xa63a5ac342ebebe0298a2146458f3d4f43372c7ce246cb6cc3524f5e1ffd41950ce83ec0ddc06c06b6e36fdb98c19b3e7ea77715a3c6db8e5a0105d0fa34da39	\\x00800003c3210770db853cb3013bf7a50695ab7663736a3cb4c941a25bfa6aa63bc96094096c266a3681261504aa5280173c4fe466fa3734ac056ca31eadbe7de52d00a366a2c04e04314ddc7e9c9a9c03343271d6bebacdb92f73820ad8e9e2dbe6ce6994a89bfac0116cfeb8afc331fee2ff81d8f698a7d0ef0f04ddb818f001d53961010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7bc44e657e50ba8d7292da3c8a56f3321df01f24b756c5b16b53858279309de14619d9571ea48b25e7c0c1eaf2568586aaab2abcddf10bed7c3f2262a82a5607	1640758803000000	1641363603000000	1704435603000000	1799043603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	292
\\xac8a7ab78b097e0eb265a7bd36d4ffda271fa26b50a233b25064c8ee0b5fc6b7ebed56a18cd28769cd8aa2706507a8d1be5c4805ebbb920ce8547c49eedafae3	\\x00800003f135a6c336da859445fd957dc421e064850101239ae6446fe1e2d0a9e134eda9344e34242bad9a168dd79899bbe8cb19a21445a9a99505a05117b46f244dcf4676db52fa765848174f7489813c9f0ad37fd43eaa615ac14b5674b1251f7293a272dde6cfc435d4eeebfe37eff1a1f4194745335655383836e7765e04dd139d6f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x36f6a6ebb6b5385f593f48082293d85caaab6df8d446840f3afca34d98e6522c17e9db793ba96b9e762a6ef51ad15a0d79e4e33eacc9091ec3fede485ca2f50f	1611138303000000	1611743103000000	1674815103000000	1769423103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	293
\\xb4fae41316fbdd2d879e764d67b5fe52aab25f83a621a5d187ce009e1b17c6d36caa2f9b7491cf328c527f9d3a21c1579ef60414078b2c2e7d3440284ae2585e	\\x00800003ade36cac5311bc64c2d293892cd7a17b2ace1a225fd74db5340968a2e60d105102658b134b0ae8d3a4604eb1147af0b80ff178ea4a318ac43087463b9c9e600db5e060cebd45efeea7da7112082c91dc059370abd07f52a022d21293ceb9eee96568ed8302256a5216534741681a7089365ca2138b621a767b819400f2a4c5cb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb23ffd73687db600424cca58868d4bc9ca09afdafd70c1f55cf726ba642456f7382d51ac450a591743d857ae330411b883d3dfa69f703de5dc4373b631e72201	1641363303000000	1641968103000000	1705040103000000	1799648103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xb5aa0b2998a1c94dedfada5cbbaf26f1ce27b8939b90fda9bc4b1da08e4c7d256a0a5346bc49933a2c171f7eebb055d7ad2df708d795e8c360d0af719bcbb659	\\x00800003d4760c3fd893c12aca2db4f95206720748a08708f941b2d27a8a6764003fbfaa9339c20cf1461d87b6457d95e4fa45de1fb1d9a328878dde623ccde8ed6b9333ed616cb828b50e8ba5ef42c263425433b2e79473b4a9609163f76f10796fcd87303b3c3fb5ffd7c233572187d8d53dfdab6a7f285be32556914fb0d3c777494b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3462f1f032faa24c8b81a012822e1d369a39123babf384a8706648edec0008d370898d688e404b0c9bfcea26ac791051362dd0d5c8e610b0ca52638f2ec60607	1629273303000000	1629878103000000	1692950103000000	1787558103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	295
\\xbacea71def0b1dbb3c2186ab8f246adc159c4e24c4651626dc95b90a9e42147cdf8065255f1664a5bf2443b2a767f5c3d5b22e69b4b6728a5b2b5141f05d9106	\\x00800003c1d1ba8500e3b2f37340851cac7237af21adb93b5c392d6d19c1294d2bcd8fb9bb205ff0a3360505bc9b514dbcfb6e48c43d76b2d5834d516fe251a35db1d45c3bc0a793aaced38d0055982995f08ada5933c9bd9b0cd776671a495a1bc9cb65ac13e25de93b042f33bbf79e96dd4daa990b00ffe2590d9dc3aab04478c8f9e1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4b0891f5ac352f2f6ca23a81c998e03ba2e7e95751b37d5a165fdaebc3b46c0258b9f6031232998c292fd4d2f8f418170ee77d8d7fd08d7f4d1f0c5c7ae1640c	1625646303000000	1626251103000000	1689323103000000	1783931103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	296
\\xbaa2f3d6654ac8527e510b8d983e58436584ee61b5da5433aeea2ed69d32d02e7442884975886902b9be4efdeb7683e7c73b14c1f59b87b33345fd3b2fc37107	\\x00800003c7efd67cb17a3c0b386cb3c6c991f2a9a0e3813f530dd0cbfa1c4e4e8c478732823d9c40b9f620219758842d206c105d5459f4667c8af1386b2bcdb5e38aa212f006b981807f1f1206f41df1eb9ff394b6d93d693ab249a2244f519170465fe98896e0741445fb9af539e193de129917ea94b2b805dd675c28957f9ccbcfce7b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd962e9e8861c926fba3fc942eb64dc61d78e70f7f46d9f6010c3b091fd09819fd039ba230a65ed96a5cc52573bcc5983e0a44f5b472f7a8f1813da167abbb409	1636527303000000	1637132103000000	1700204103000000	1794812103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	297
\\xbc4e5c9e2870dba2b5a8d872a66985147a034fd3cb82715af85931eeaa2761c56db0ff2691026225029232e59fc84b035665b218e086f1f8a1a347a23d51618c	\\x00800003cc09472257f5839bceeb7f902766de922eeafb1662a3ad0882e6605441fa163253a94237eea7001d11ccd04a6bd7c05f7df1193f6d06f6bca637f710da48b3923ad6d2eec5216271cdbb2961b8f5252fab602372655ce6888ba74f5d693485f70587e73479e3e2c7edcebf1f719575c929ea8662f9f73caa767a160c584fd9bf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xaf731b5b79fe0f4d255c6936c09a1aec322477ac04b5050a0b974c8105056961013c2995bb035889da0fe5d3897ea44fb9ca5ad0a37051a003f1e8a96887460f	1631691303000000	1632296103000000	1695368103000000	1789976103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	298
\\xc202fcbe35fd9b14dd7bf2d45db804257d0073ef637cc9ddc93440c86e9aabdad83cc69547465747ff058fb105f6e889bbff6121ac4fe96beb533ba20976da3d	\\x00800003de2c3f930e779c432b6bf0f6090b00cd09a3a6d9a0bee4a00e4fe8f28e9dca6e899224fef43ffc606aa70366e81c62338db8464b8939ef78df0e2ab6ea900c1458805603a5809bde9340eed3742fdbcc160bbd863416fc6f76f1c6251db6f5d60a47b81cb087a5aed47ef7a723c712f809d9acf1fdca119062c671deb9c9a637010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfa57401a1f4fcb66ca7a4a9ec662e1bae9b109246ea44a012f48264c304e834754cd0a8119053d73633c21094061ed8101d374bb5593ee12a87611dde9810b0b	1632900303000000	1633505103000000	1696577103000000	1791185103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	299
\\xc8c680bdc5907f639710d565e74a53f613a0c7b12b96b1e4508f2696dda8c03d8b372e36003f3728c71bbfbed37b705124e81d4f54a55f9918f011127b1626f7	\\x00800003b0169c4e7b8d22a330eb3ad854c705e0fc16e6a2ed9f8fbae6f6acb8cf1e93ae90d63f4134882755b2c3fd11af7f769b8397a463ca896567ba4418878d2dba1977ec2cb2857725d44e9ec7b7012569c1ace69656bc7368c55b1e5c306dda2815dad90c4e5b56e82ce070b15ea1b7b5c5214961983745ba536976780ce38d6a4f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4598098d9bbe7297777120616b6f449f80d17886aac0aeeeb686719c3140987316ea149ab8d44c44e3b02113b363a592f1d64d8bb05e51d7b196e673d7669104	1627459803000000	1628064603000000	1691136603000000	1785744603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	300
\\xca8ec01717e916871a244aad5c1f9f732a6bc46459e2316fe3c586c6903a73841dd62341c629a587424c49dc7cf4e033f6d5bb2564932f56c024374dff711429	\\x00800003b9b6cf369c757e01480f22abfd2b074e258f237d861b52941eb00c80b3a801b9cc90d928fddd4a8f13ba566d8722619c9282d3b9458d5964d0f5f8142159e6bb2f370f9a8d1a0b63d39e0d3ddb500b6001386a3d35ce8bf78e0fd5329ff86a71eb7bd9c44bbbe0e068ed57db48388e6286dd0fd7110f22707ed1a646af330d0b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xafaba8f4c20493a0120ac0f3e3590bd3b9ca720b774a92c85db271c2a45c0b2ac9c17ff9a265a498703cd8ca8320a64cfd5841487933a5edde332e15e33fc209	1625646303000000	1626251103000000	1689323103000000	1783931103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xcfe2d6bda1b8a6536a144bc78108bec1cf9f9cb54ab3906e8c78c050a8c7ecaf1ab5a0ac1219cd67b27ff0bc872d19f4082bca2c56acc42cec17dd6f984339ed	\\x00800003aaf598b37d675b500e3a990bb6569dadf5b07dc58c6b5546a99675e89d65b129c1deca5fdcd9acb4c6ffae328788df704a4c796e59a6ed85e5445ee00e5126b21cd9b6ea4e1f48bc29927f3c7214e2d46274d08913e61e607a545f978da2ce364eba94baec983a75b32c059e95016d8460cc3161056596b697edeba954ad7b4f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfcd203840cf41f1261f26a8b83fccc1e885050769dc2114c3853212dd4900ad9472207c268f406c1bfcb7fa91d747edbb60e6d3932fb7edf4928aab6f3b6e905	1632295803000000	1632900603000000	1695972603000000	1790580603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xd0e24b02944762bbcf7e70b7e9d3462f40ddfe1a90826f042e96314f8e0adaafcb89d19867ea4f9fb41f7052ce878d26551e385203230d9eb4eee37e115356dd	\\x00800003cbbaec392c96943999835e2ee9e6fea9f041b4b0ea06f05b5485610f340885b70240656d745a0d515ed07b5fbaf23c77c88cecb3a0f89ddc740ae023b4c15f27bf446bcf783dac4f3c5b047596328c3d7ca21f0941d55ac770c01093ce1a6143c5d73121a8bf33942042632198ba28cfe90f2c51b2a071e2dd8515bb37bdde2d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x514646358407b839c518723dfaff93c7fa68403f27b809baf94456d496e1615a63be15d76b6edd4d5985906fcd97087d2cfd31d0bc85153d2542fbfb1ab86f09	1623228303000000	1623833103000000	1686905103000000	1781513103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	303
\\xd036f95764113469010d37a24cc725615da51161ed81cab45df2cbc7f4c2b367454c442bcc74e26ad6e82aa8c2ff7a7bcef0b9c7daca921134cb0322dd092965	\\x0080000399967a7cbde7fa98396af0cac47845eba55ab2280a55538a9ff99ad8e37899e4c4e1abb81f93b91a6c496732113415ee5ae6093efde9096872c0f35ab4e592eabd7a8644c84308232f2ec1f61efef7777aa3a083930155d73d00cab032ae96a0063aaab70b1345820516ade9470d44497e0eddc0a2f4028a62a92b36c6fa744b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb1ddce0a03af41dccef6199299ab20b13bca91984135a5551ebcfb8a79ce82ef295fecb7ec0bbacaeac770d8ebc5dc4cb567e4f05186ab28fc6589313816700e	1637131803000000	1637736603000000	1700808603000000	1795416603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xd2d2c968192c5d797fbea1b84de39059a26bae600de92c80ac3c2294d6975a9fee75611ab8c3587b16321ed3bd1f81bd38790a6157de95ee4624e5524ce6db15	\\x00800003ed78b4f73fd18ef4fdf1e61511f9c97fe7eb211077376651f2ee4133c914db66e74149e6b19fb59d49a180035ebac8bec5dafc5479f53fb3c7c5c0da5b3e8171295b0558218cefdb29ae90079fb97d468d9cdb6616b12db621023d79cfd0690b718c3f198f1d8e6684876a6fed96f3cd7b628a303c56c7a8f40b834c5a6b300d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2291f698d74bebe73ce23afcd04526090055fbb0a40d0dccbfbbe2f129fed4257a7cdc26264a3e1e6f58f58607f9b72f748b76b4cf8889f7e408d7614f287e05	1618996803000000	1619601603000000	1682673603000000	1777281603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xd22edfbebdb114019955ff72f201909e62952f98578423278ee0f6dee5f185f43c137b3f3ac0d8d39d1cc11b1dcd6d40fe632eeb697f192c582451f3f09dd317	\\x00800003c30929df7252b46f6412d6d396c7d7605a16fc86c1fb662cdfc5dcedd2ac392552662b5e75f833eba62eac488d2872f02f9ac033a689d5219012c6f11de9f13872f5896adb75f26d58750377d0c4797884146e80bd3cef3a8c448867ee824c062ea72ff06809f40ceef4835cbc6ebc18de6eaca358299ff8b8a748630e4f35ad010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8036d70dec8809be7d197b59ef24a242585d82fd2896f2dbe07a9250d01b126b89feb574d02d4ec4f594254c1d9d381ccd593c6f31c5ed9d0c122b951983c70f	1622019303000000	1622624103000000	1685696103000000	1780304103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	306
\\xd41e4b2a5d07933ec51cabb2f80c2245741c88fc515e3ebc990cadd550da92ab67a04004ec6eccce00d6ea766e9880856e8ecca67cf64996680b23cfae43ed22	\\x00800003acef212aa75f0f34f0c56e26bd55fd1583a85388b74ce40683911558bac5c4376ba8f6a18503a5c48960b3609b3c5d66c7b245e69c7a723030a18c277743b41c7b3f8fd8e0dcb6baec61eff1279eaac23b4b2c3e9be09ea620eb641bd9a8e0c7ba0e4b999e4ac8a46541e53debef2d66e9273669db0341cb56eefb6d7ca61951010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc1245e16962851dbcac6c06ed0c19ce87aae7adfd423dcd99807a021df1303aa986e57b7aee88dd223c994f2908ebb84709582c1406aeb1398c741d955322b0a	1638340803000000	1638945603000000	1702017603000000	1796625603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xd446c7fc79834d1534fcf31ac8ec9fc05f5a8341ff2c22c7b027a06182eb67926daa4e3df4737f4088c06e16fde365c7c2d37accf522a295d904b162add55664	\\x00800003ab6b60f91ac4ee7c50534cbe09aee1c9ac460a28efd1a6c6242e0cdd7e95394d68fa8dccd7007f0b973f5411fd902770a2ce161284aff3f4dcb9215ac399a5ed9ee47c9b78949cbfff5dd58d9654df83cae57c8c62ca9cceb6abd1b9274aff38fe3994689d297aa74ba3b7ae393d322b97b697fffdff626b8be4f96bacbff963010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6d98c33aaf51e84f1627f2239b7a4552530902db640e9b78fb4708f070ab446fbcf6f7aa7d4df6eeb46266df9fa47c48cfdac55d0267313329e6a1198f58a40c	1615369803000000	1615974603000000	1679046603000000	1773654603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	308
\\xd63212e94bf24fa3409be36cc809fea4640a967a749eb821a139fa13468d06b3dcb728dde799d6686ed044492eb345973621b709b6567ea9d8bfc36fee822646	\\x00800003aa20851918fad81f53ff425baf87d68ccaaf36aa7ae75f2bfc947aea56be491d30402cfec00242014277da3ddc33a9c11b00f5d82e9ec8bd0e704cdcedc90d5fb1ff2035d7f64180032cfa0a0bbeee7b8dd555b4d8d148766388a249716a85970c2012c0ed6b146c2f732c0d13f5fea613d4a17f8448a124337db79fdc9bdc29010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5b3a942937307841bf72fafb29e7ce4248659f11fb83f9246c331ddc442c9fdd0642d7f29702a12a1bbed9929be4f546ab6b5844629b95a2f45083f529c7a70d	1626250803000000	1626855603000000	1689927603000000	1784535603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	309
\\xd692cac572934bcadfb12e86e903cb7396e9e8836ae7250763433397677ce2c701cfd279134d8f2db7769e45480696eb3abd87d3acd7b13f41c3ea6d8bec51ff	\\x00800003f45b7201681f1ebe2c793bb1d4a40fe1330ae6c3ee9f1ba25a6235bcf7fe18b828f37c09cf8a79b2d8be9db4b08d087993cc24780bf1a6db0942e75fc316589919c632e08e4167d6f02226f9a2db48a5ae6d25534fd649737a295605b75f923ef21eeb47919bb95eac70334901280b138573186c4dec6cf73408aa29d37a3cf7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x83aac9a0e4d9cd4c55a0054d3eb499adddd74a77dc184b5842bff58c6ff73f65c00b7775bbfb40fdb41d77477925301150b0fdf84c9cc8dc578a5d33048da703	1633504803000000	1634109603000000	1697181603000000	1791789603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	310
\\xd7fe7bf426bdbff29cef6479bbc2d796e9e35ae3351f1fff563ae43b0d40317e7ae2b072df9d1d6bc928ee16397ca90f5011ea9f6dcefb62c81865fe3e3bc649	\\x00800003c1fb2918e52ea5215171d13ee5aa7f3b6a7c6d19f4143bbce5a17a99413d2d184fc379d515f1a37510bc4da54dbb4fab7788367b1dfd06d9c1b4b4f70ac024601293045f1011e3984fddc52a75999dae65fbb20b5bf374bf2bcc500ec503d85dc447a05b8294ce79e7b0a7f1846cc615ae3fb8450b2504a987aec21719f2dd2b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x472c44353ce66842a4d45b5529893fd66e46f2f613265de0a75ee0e7394f630ae1a454e7eb2a33897ec6df33f33fdfc3d5890da389e45785479e81f8a3c67e05	1620205803000000	1620810603000000	1683882603000000	1778490603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	311
\\xe29267fee66431595d85ec2f2dc6203abeb8682fe9932c185bb33fb1937f65cf0d47c84b425a85c86208215c81eb491ff3c64adc9f15634ab4650ab5dee86aff	\\x00800003d48e747efb2258700bd43747138a7bf367209f3d5d6061be882cd077197224a49ee88e7d262014150788c576a1d01ad3581a4cc3374aab721185cf238cd5d9acc01154f8641cca27b662482a5b9f3de8ec7b578985c9e1eb61526abc9eb8cef4f5526c9db1dbdde594cf5ad5a36aae291630a26aebbe46d8e2c5b779cc1920e7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa2b07af3601481fa8b2c262de0839a3b954e7202630da28566bbe0d62ff2bd93d79d54fe9e839bca8d290ebc998f8465df0db51b7498c23585f23f9da19bb80a	1634713803000000	1635318603000000	1698390603000000	1792998603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	312
\\xe2f2ce2d12b61e2863d8b5489b8eaf4b941b01cec531181ea56ac399b4fb4883e6ff7793dd621e3ce921ddbe2d77eeb5433602702d8df794f9e9a43220e65d6b	\\x00800003eae3bc94e62369aa3ddeeee1252287eb41888230a2dcc0fb8ce1068893c0edba0b7329d84e626954795d3e62eb23a65306ec67ae7dbd30a53e378e32dbcb5ef209bb27e3e751a585e69f4b970f14ecff07031363dc9c40b1fbeff1e55a0b54f661dad47406f0b6af20f486f1d1f14c7764b68752441d19bb32d4c715aaf55eb7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4a3921f19faf5e5e1779c31f98cf5a2739c904734ebfca984b3707734742ab9e105883c1c89023acf8ce447b51d5c25068ea93c9551888af5b10d9dba536fe02	1613556303000000	1614161103000000	1677233103000000	1771841103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	313
\\xe7eaff11b70a457793fa28e20747927e85ac3de0422158dcd7816f77458f1807798ccdaa5869a1009b1bed7a45cad6cb286bd3dffd9c66928a1a1ed09caee11b	\\x00800003df7f092632d8b74ad964c8785110cff368634b0c38597d5965c7a41f4cfa5d6cd9fe15eb5f524fc366906fa6101de7a02e93ee1de33c77e313fe44bf56d2b04aadebf4201842b2bf9eb8e15c690b86c7b5fc66f39e02b977f0d6b2df4d1a57e8b6271009b43f91afed79d75506de2e55ab40c28ed6f27db445c674760fbdd1ed010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x848812587be21fe20d36454be7fe53576ecc2bbdd9149fde50a4305883fe5f8ec59123f8611c51271a423dfc50bb9ec010d37141432589925c4b176f5446e10c	1635318303000000	1635923103000000	1698995103000000	1793603103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	314
\\xe86224469a50adbd513797bfb0b3a16a85e26b2bbd052e4c4734e351efcb8d0766fa740c74c3a120f84c066905644625bb53c26bfe79d60b6e710d0961e916da	\\x00800003a06dc94da17518b21c35ceb11a999fbdd9e0d57aef8df9af39cc725bf3bea3d9588735c6375fbdf39a3ad4620500890c446ff170e9ca14f83e66e80d3d221654b888154211ebb112ada9223e962c4c7a4bb095469e899880912cbaaa6b80ce4f5ccd96efa1d02fe95cd50ea9708e28008d421ab0ad1379e12fd1de26780a104d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6a32b672e8139c75341973a71b216cf94e7a1f6b8b74a59453c36429fae7c47c46ab8970f220337a365d66c290b893e99becb09e3839a4ae07350c76b583b10d	1631691303000000	1632296103000000	1695368103000000	1789976103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	315
\\xe88a41a72512d792e9b2c36c8b41f8084fcca331b4592860c62a8668c550176b452980fe87c63cd0f5f58109d954e6a6c86f633265ff1392686842aeb0a4db5a	\\x00800003d7beb9a5bafb1ca2b53bbb1345eefa33108ece3c6abb370b6036e632a3106a112e1046a4781998c9e29baa8da90635b28ecdef70b1f2b91330d6f2355a3554d2b3d66bbad9b831ea26e1970a846ea2e9936aaeecb1ebbafa6f09b97fe9a2220804804853c2e6ff08c882697d80f7491335b0bb29344ae7b9d6b088ee7332e91f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd66a8fd4d71ff8884406bf71d3fe0168f0cda9ac1cc00ca7ade945ccda4a1d56395b7a416c6e4c42dbf6d12799dbc75df5271dbab10ad73f0172cb10c3fc9f00	1625041803000000	1625646603000000	1688718603000000	1783326603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	316
\\xeb5e0a5e6e4a707f8d449ed903e0cf6c1ae78fe24ad9f14932302937209035353957c7e331c9fb872c0dd8096e4e84aa3649597af8e5c8c274e41c6180f38ea6	\\x00800003c8b80fd347a9d9d99029de3fe0a1ef9b1af40697352ec34963987aac0c20e79fc392be76727dea52e328a8cac5856857d06da570a20f6478f2287779d1827c556a92ca4778bba5f31a8565a76ef26343ae614415145b33ea1fdc62e089518cf38da9f3162536ab5ceed10465c76c51cc0e8abbdf45c776945cb9ee7c6e51d2ff010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3e5cc914ad4d015f815369b146d48e8c885ec726fb02828c9899dff56ac016d1ac4e4fb91a78b2b5f228babe2c3e701e255d6390f65936c42a078ffe5052d40d	1632295803000000	1632900603000000	1695972603000000	1790580603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	317
\\xec160726442e57b4161f789f32a324c5d97aeb166b8adaa93f0ff81e32189b0156397540ae808dccd3c5b0e1c538b34ad2cb6478d7199896637cc098a73a58b1	\\x00800003ca0ffec619aab17567469859d0e59d12ee004ecef1ff4438586175a68b20f1fabdedc36e0039c34c1798a35be1ace26b3d9233ca550ed368a615fcdb68c946969b153dba18d873918f5253208d50aea3a2017b432a5f5628d8332998120f7be776c97298c8c7a9f3827fade1bafd61db11e7d382e596ddbdc065669659f9a019010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x609f4fb2632ac0d3ff0f480ec823e56d554046dfb4aad4f0055729d2e96149b518c5835cce229c30160a9daffb168ff1b3aa73563c6f7edfbf2feac44c4bab0c	1624437303000000	1625042103000000	1688114103000000	1782722103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	318
\\xee6e9f4bb8577465dd2f0856e8eef5543300b52daf64611dbec1833487e516ad4348caffaba25b80f77e24c9b29a6d212c129bdbb83b618b302c340b37a32e9e	\\x00800003c6442f722ab6de30efe8ce16ec5afb14129ba87c551b04162183c4ff486ebd40d110d3e046578df2a57a3663d5bc0cecfecfc5719ad52162de3bb8ec5ace1d4bea96b344a3cc09287ac8bff3358e50356d86d4f24af1e98b935b0fec14e295e4e806da4fa227195af010b7bcc589715e058443a6494804769d13ca42efd00681010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9e2e6e109a6dbd607abf5ae86edb3061ef7dd2cad620b548f8d3c8e8e6d003c9820fe709c75201637289f8fc698166ecd03ac7f4a46c4422e399eb0598901e0b	1636527303000000	1637132103000000	1700204103000000	1794812103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	319
\\xf2463fa5ea697bd47338d2fb4ae96556f03b458d38054e21d7871ee21866e2d4a686eb319797438e4fa502394f6e8940cde3a3dfe2e6d04c684ace882d1f22fb	\\x00800003c07be1d91f999691844da1e9d4cf68b8c561a4c563d709fdb6aa5f527c1088144fd5c92b7b2ee20583509fd7fece686df6eb09174f52c3ce09932d97bce552e69b39739e843fe7c614c98fb212e0877f286099003b8e6cecef982cb01dfdca377a0bc76e650fbf889f38c85279e783dd88723471c2ce5c9ac31c6948f70c81fd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc07991e674ed817d3095512528c1113dc117c7163fffaf2086f154e8aa6c8f4d9929835dd128c546ba6948ce647080143aab8012c98789aad752ca8057e23201	1637736303000000	1638341103000000	1701413103000000	1796021103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	320
\\xf36aab7b47467c3620c68bb9fb3695630a6a8589ee1e4820665c0c80e48751793f1c4b7496c8ae075c39202ed7796700d371c1495d03a2f474c77bf8b9a0cbfa	\\x00800003bb968200692cfcd03a2a1c648bca5167ca59e00c50aa3b272f0832520b59e6d4c10892d7f0cde3bd2cde80a92b9a2c8a23ffde9b85efb51124b2316688a93eb780b87ea1c5d38afaac44508969e75df753083814d24be302175c792856481ad5137151b13319048120fd5663acef7cfdc4fed1696e890c96d4cbecd3ac1f6247010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x010524d09bc2c202d451833713a805093306107b20bd0b4745bb8670f4e4eb8f008a85914765b3132615628acb36e5d167d5ef88464c4fb63b525b0d5bc1bc0d	1639549803000000	1640154603000000	1703226603000000	1797834603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	321
\\xfc22965f7960efd4907b59bf31492058b3031850b6f37ec6620422a67fc0b1bc1d26e377fa735502982e63e394b564d51681cbbb1482baca2dba8c62e188b9f5	\\x00800003c33003cc70b9c5cd0d55451e190e23e7cb29ea24a8471c01290a5b6b13f23fcfece3cb2beb5618a6b628f61d6f99bd0f11cae479bf3b73759e714f951035cdf1dd116da997a968f7f23209bff2fd055b4f4fafd1a5a9627dc0986466977ca571f6209065e8e77449430d4182ac57ad16c451a5fd8e90d3793ee5d245c181083b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9f186b3c9e01201b1a8d253ec29315e2f3563f57d0b0e747ff281fad616cff95e6b3c7957b4b3029e0b5fb1606adc384a45680f281d4a2a284ce0a4081d54d06	1637131803000000	1637736603000000	1700808603000000	1795416603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	322
\\xfef2bccea093755bd4e8e970026301a901ed7a49183cf609f2c186235b72bb365f4382ba30d99ba4cb13148e98a2f49e7bdabc2351b5e4bc8c6d0f1834d7924d	\\x00800003b39782462a5ebf247e098dcdfdb4f658b328afb02d447138b19c7c4a61cf09db802a3c93ac98c665fbe9c5364ac1c6868b06cf9f00e8070e0be9175e82f5b078465e243871b642cf4f297a3932c353890e02ed7083b21935aefa66d55aaf51d4395227c2c801cb38f5c91f0e9515fdd6ae58d1c923a8e17a78756d1cccc3f027010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x590dd72c04363cf692379b93ce824adb5871407c4793408e199c99066eea255873af80164e9e08e8da5c0df9250c510a61dc1c9980680c31bf40e4165f31040c	1612347303000000	1612952103000000	1676024103000000	1770632103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	323
\\xfe22706014a42c2a85f0964bd92fc0262692b8a36467fedd9fe4149eea61c7517976930a628bcaa904a5b565e734c5ce8c154aeeaf93dca7144c134bb01c955d	\\x00800003c479d220e368c6e06ef0fda6383b1b287ae7f364ae87e00564c2180ef2f52f5e8486ee760a79ec1e507ee82e34f9ed8ded0340ad2601e2cf3c349128054e47cb41e45e6e9071c43272c0b0f3f5867b752d48129ff849ae76e7aae1a501ea696a0e2699fae68b476ccc492555e2a08dae9886a98edd32b084586be8c42ca90e69010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3de455e3fa9ed54d22e09229125f3895cfe26bdefa86c4f426ff0b249c5592d05ac72dfca68214eda8b207b0084b70808a1cdb1a56f491ab2026a3ef0bf81e02	1632900303000000	1633505103000000	1696577103000000	1791185103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	324
\\x00c711b6156b20920fb2052012d986821df6fe62f1381c2cdba534a83ee2fd25cdc30d83e22b775b7031d448c6aafb4696307b154d45f6adb148865b6b831f2d	\\x00800003c93d6ae46329993adcc0d1a7bd79880d08431f5c522e77d8e09b407b70374735944f729ad4c051c853107bd57f276315df24e656ccb7b065de6461085fc0b48442458024e17bf5dd7cd881258ed17fbf2bcade2e40db974e8859b1d0157cb4f83c858dea884c0df00daf39d12547783d0202b09a1bb031fa6b428edfb6c6911b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd64e9a2f7567b9780fa7eea2e21a76e6db6f1f3c08bd38539def4c937972ad4e1880d8124951d6f3c0719361e2845f22e182f96e2bebe4008308f7d7e8e1aa03	1618392303000000	1618997103000000	1682069103000000	1776677103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	325
\\x01d31560ea14a6fcf2288739080682d0886564fc10044509c3b7ca36789f5735e8ec482665467e26c9356a3f4090ea67d9b3d7b5ecb4eb4d660d30eb2b6f160f	\\x00800003960530f724d33aa28c06604fb7c1fd4c34265c96b867576f71f4a77718f06e597d9234732f102f66d97155203db8f3a18713a79256f1c43df3ce4f2756c7d7e851babdfe35b30f4d564971a4bbd07e002c68093be37c63a5fe6c1b92fbbc1677f22bfdeb0e06f81f1e7c22146a7f1d2a9b0d034a9573b9a8ed64ea29690a9ef9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3fa84b7b6fac1018191dcf93d2c52cdee4e901c642cdcdd841e38f4514b4f93e0b626e5a95b0e33c4a5650ebb82cb24565274da44de9c089ae81fb33dfb7da03	1628064303000000	1628669103000000	1691741103000000	1786349103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	326
\\x02df65c725b36d1bad3485b0f2dc61e377ae17d7f3ea51cb6db398b2c24d9e660aab36ad50484bff24c4c02767035554835041fb9ba535e0b6ff4ee38327cebe	\\x00800003d9900c405776a6ae22e9b92b0974b5bc59173e2fe8807ec8843183db13416e24242e82494d61f395f2e4a07c53c0456e81ce9d3d2a5d08a5006d3032db96f0d941df85e062b5745749de50c465e5d304062d062dc76e30f844427d65e8b97473241caf70447d9177f1c15304ed129280966e7ac9dae9f955b7988881e428e1e3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2aced84768e0077e8ec81d5bb65674b3bb267a2639febad6ebff4c7c0b50c1d83777e8ced23fad9a640ef0b1b7c4c149dcee2d952f35f09171f1b5b00d91f405	1612347303000000	1612952103000000	1676024103000000	1770632103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	327
\\x076fd16511ee7a17bbe1209a97da11c657c1df5ed42fc315da15474a495ae9e9f9351ab7defc1d07a7a5ff086cb680989f44b8e0af16d39eec60e263a45ed413	\\x00800003c727b536a520fee4ef54074da642758cf6848a5849fc42677ac1bcb99138d8053584eded7141c9a74413283deeaf4065453ef779104aa04252d3e0d68044f94f458ab75f9d115a33a82f0442767ff46f49fa73231f76d0786df9b499946882dcf8974dfc763b8f6eb044e43c3d20545eaedc80907917c0335dfba567170f5751010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8051565fd6494bf9b3476a00b77d59ab3ea487d58f79bec11e0c1550c37256000dbacf4d1618ea4e550d330df35702a92b5e4dd4f464be6286b4ca0f197be005	1612347303000000	1612952103000000	1676024103000000	1770632103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	328
\\x10efd20a152ad2e0d6f2ddf971206070b07d8fe7b8cd9edb20a6d80024e49f9d71060b12964e6e07ec83a8f0528d05aedaed8d3b63f8394e091178d39de380a7	\\x00800003c098cfd28cdbaee6e1b752385b2e9872a9ecebf7c58384a158831687618975adce2c56927060b401dcd23f9c8897a86e7d5450a8542ed4a404f56fb573dbe389dd6e8c31de2b3339d9ada44b0212fa59160f8755a46e432da3a4e292c5d9455562a5265ebfd775ec76ab302d45b2c43369d3483b87a30c816c5f2e9247c6abad010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xba0638390fb0a2e961013ba9613d031bb35cfc7495d130d46954b4fb20d41cd2567a1caefd794ec393fedc8e31c63edc89ebe3de0f7bf6e747144887b37e490d	1618392303000000	1618997103000000	1682069103000000	1776677103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	329
\\x174b4d28ec32e81c404bb5663df9ae5627695235e600f54504ea10a4a143c3029494f704ee24ec8ab8c831c55d7172fd2bad27bd1897b9217fe1e3565aa40c25	\\x00800003bef64beea4e72edffb4d9113dfba5aeff8c1a8edf7f02ab50335f7e539554bd2d2928606bfb253f523d3eb98118c95906bb13b8fc5f987d7b89599508e747200d9e85bc585777b5d6f6e7fbfe97ea90e49c5b68e2b27350ebf56981b55735de3cfa0b576fb66d907b39282801f7422fdefbf320bae1c937f996090a3fb02dced010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xef4a1a605542de10562f525d15a32f2a21e66ba08d3bf47c793d6073a8fce9349cc4e0206c28e1f33372fdb5bcde57dd2aceb0a053b2039215d4ab0eeb71ee07	1622019303000000	1622624103000000	1685696103000000	1780304103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x17a3c1cd0d6e65f95c4e3bd27a4503387962f6c99d930972d655aa1ef9f0400d2bc36b314f449476ff9216225ee2634d518d5ea9168928ee1a2481531a6a55b9	\\x00800003babfcc6c2dd0bb89360acd483458a820e41741e407ec074b4e23672854f5cd67ecb2488494477d2be988e6c835605171f77638ed0fcba22545b99541cb57e4206a434384510af572ac7fe06b51267483c91ae30a6755cd7f781106f143004a654cfd19c62a5de13d1b937c8cd365977ff62dc664f37f921f57a9b21c9cc23531010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcd4009582cba44abb49ced6c8cfad5264e408b558aa1607487e9652577b499332a74562304fdefdbc8fa76a6c99d7f790ac425cf249ece1abd49bd00982fb907	1611138303000000	1611743103000000	1674815103000000	1769423103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	331
\\x188b23e6ae825fae55939560ece0dcee5112bd54e6d9ace08316b5bb34f2bc1951f5b7b2609171c3883b47e5fa4619bbea572008d83f95e6a36a98258b211fca	\\x00800003a302b400e4fee2a0759c4d8541f0dd8997304e54b76ccb7602d0cb59851b1b75f500659c583fde6786246e2eccb684b4227beb087b25437959b6128b8be3fb2fcced150c4c06218e6c07f3d8d5814fe54c35c1461372e22ca249f50e35b1ada0dbe26f105708fd0b4af939627d4f7da13db1e5aaa05b4a515ef0426df6f8072b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2b865153e878c9abf2920cf9f4e37daba4b41de388c3f21d492896a9c096cdcc00ae7e3867f29576b66cf7e94540ca04ace2f5022ce8d4bed808f782e422be0f	1614765303000000	1615370103000000	1678442103000000	1773050103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x1ccb142e91b47cf563e07a9542cc637ac1fe55f448e162da1cbee3f8c619352d79284beab48239a7c013a141828f002028099d5c84121a90360c28ae9ee0f97f	\\x00800003c1e1ecfb9a37b2344b99c19d92fca9a7304bc48968bd6098c1b91448e1abd0453190374ab4d07673de392fafca01fd1e5f264bc789c9537a5dff3ea60c42fcf41c3ad769d54bd8e75053c1b4d22ae852f5858fd0cb1607d61dd6f3b07f00b7c4bffaa0ea05d81aa7fd1d9010337a22c90b80ccf0ddf535423f52b77958b04a91010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x983470e486990243d1a361209764e11bc2e6127aafdca7e98652456d4adae2add26895c1edb37ca525eeaeef73c31a9ef208000d2dadea8f10f0ec9f5c3a8409	1629273303000000	1629878103000000	1692950103000000	1787558103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	333
\\x1c0f00b8623128bded20efb1af26389d9b9e7d61df7663d385a1360ed735f921827b52fb36f595efe9d527d6b03eb4a908b6a423113fa2f14b0e2e283996011b	\\x00800003c09fe2979b84ecb277c16f5ff2a4cff8cc53c0e55857588afbf6af337989329f8228bccf38586840c0d13958af3a990db14e6913e37f928b1b6e1e13018186f67f2e434e03c656ede47859390b82a78421daeb6bd3b400b1b487db2c2bd7153340bbb24ae37b66a7f27b740916edcbd0d1dcada1e30acbcd762c3e860b9bea1f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6fa2fdaf80db4288b28af421e450a67ab829cfc35cd4537bacbe429b7d53f566b82f91a28ff0dfea6710532d101508a5ae0af6390934569bbac9d1f64aa3b608	1630482303000000	1631087103000000	1694159103000000	1788767103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	334
\\x1caf8ddc4db9340fc610c3bd429b49ddca48a81b89e1327b6e5962861156415d7491713be513fa33a0ee5d79ba6e16c1e2815b46c1282c1b12f8b1c8c419e77e	\\x00800003cb24935677399509b8323928a08ac38afaa7fd1f4252715c8c3fb5eaef734afd5027562e8128acbaed714b463dd2ab94dad48e60dec7bc3860b894f673daec3f02e3be64b5de93e141bc64a00c9698ecc9ab11d529b5908efa724143d3159967a0af0f5de9ce40f3b67966bf4e0eeb091581f231e4715038a4d4ba0700543081010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x77ef2c403ebc65c83b79537c686f017c4f15d450274b8b5eb3467aa12b3ab23705c028d5f3698f4d98ea009e04556ecbed1364284f76f0ffc27aafdff5cbd005	1617183303000000	1617788103000000	1680860103000000	1775468103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	335
\\x1d87a8e51218b7516c1bfd0698bb58709b847e9c7eb033667c5ead0bb7cf55a2e495e1fe95b979f6413afe01cca207a29aee6847fd8327636cae05f9aa85fb78	\\x00800003b16e817b4718a760049e44a016e7e99cae00ee257e69a9a80de225d99b246e9f373db62948e27567ea45202f78356e6282467aeed25c1184b91e97b61469c09e5994410e4b2102f7269742c27d53f0a3ccdf52b97b67495c05aa9a2b602dfff369705894607bd233c3d5b21dc2c5e9b2c4d05f1e7885b70190ad53be8b1c07c5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6966b570a8e663fe1fd6d8802d3f98e8a27724a946bc825f27eb409e2e07bda94f19e6d4473a21e5b899dea226aec9527c2d0596214f8b08710152e5e92e7e08	1631086803000000	1631691603000000	1694763603000000	1789371603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	336
\\x1db7cb83ed35fd52cc29a383e5f796cf1c5541345cdee992b682aa3c30c12f66f7b43965c08fb0a89e44d7f4671d18c625e7cc7e591f49893c8230bde66c243d	\\x00800003adfb6230993fd78551812034782c0a32688e4fc95a69531ffb39be6d5449ce1b7eb7a51c6b56acea7802c75434d3b014f38fc3d0ee59f7601bee1033766f394a38adb9f624a47302533fe890da77f7124f6f4c900aa357d768640efa894358d28f39bb199fbdef95a905cf511b333ee0d5c382bd06953137a019397777a4dc57010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x23edb17c44669a48a7aefee26fdc3a0ae200e93c93e3ae18ccc32f773c29f4da248dd4607efe1b9facab4522c0c7d7c1a7399b1ca2d336f07e7a1d1019159d0a	1635318303000000	1635923103000000	1698995103000000	1793603103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	337
\\x1ef385230ba5d389ef7c69bcb228db2c7b23f71bc0fdc99d059e1f9349bc947f5847147a9ee16de76cb770383e49de80e36770e2ad6e531c04b5aee5bb3a6dbc	\\x00800003c5b2dac5b90226889bfc12a01ef444cf26d2bca22b6153556eaa775b58df1b6cdebd9cefb1d98ae9438b2ed563a832e4083d9528bb5f3d343d39592b271189c862b427a8f8fad85b7fc73d9825de5ed4684e8c37d0c439011e5688295a78511342d5df51622d541cd2df962531f5ae547d2b2054d229e91358b1121ac5ec7e49010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x98f5b56ce12b1524cbea64ddd54a2c08b7cf49793911546db6cd0eb0c48778477091bc6bff98e2afeca8cba3b3f13e19de63d13da40aae98549b1fd9ace3190c	1628668803000000	1629273603000000	1692345603000000	1786953603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	338
\\x1f2757ef6637bf2d35e55fcd7546df96c1ef94450f3f9b97c9c6d8c81d5bc550cc53708fc10f0e242375d55a6ae5802f45e401c7a216d95f6cf83ec672ca2712	\\x00800003ac191aece2824aae329017562447691dd9726ff00c555d495a0a8345ef566fb79c2b1673ec70e47cfdf9c4f138aa5f0a953b0099e6997bb930ee19287345d5ed4618331f8ccdf8dda6f8f7fb0f48bb706e3a75f41d824a07dc304e6275a2b22c26e7da68331b98374645c80453bc52f1eae9732ea1732450929aeda23cb85b7d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc222e24962cc47893d13a9ec10d52b75527885fcb568db9e0d637f4835d36d05597ae621cc3aeef779d9e8cdd4ddfbc61fd7353b2e23b440aefdc0b8cf4d4c02	1631691303000000	1632296103000000	1695368103000000	1789976103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	339
\\x2097fe9e48ca3063abc7dedf7a1ddbc8385b874ab018c9579e7cad2bf93d4027ce32bd29061aca5451841625d2238a285f7fe03b7865a77293a1bef3ddbce6d0	\\x00800003aeb9daff67c213b16a4612f7032c5d0d61e1b95db2fc6d068344eeacef2d09adbf69c39b133611f778a65c8fb48ba211a4cb4ab17b1061a5f7f87fce777891d4b3c154d96cf57473636a4152fb23e938f008504da743d4716ae31a40d85d4ec8d1ece230431ded289e1aad579e3abd12107a6b992314a8c21898115796335bdb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x039724d46ad250349de7dde452c3a9f979cbbc2e25b69d94e207d7bea8196ed41238bc844855315523931db59c7bff54789a8eba22758ae20905b124bc2fe205	1615369803000000	1615974603000000	1679046603000000	1773654603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	340
\\x20bbfe4879fefc97c6ef39c0ada9531acc950bede0b8ba517a4b4dbcf6dee77b3a8a50d60b49c7e1bc2bb890226bcafe13a6f75e3879b9225fa7e3c2b2a7e3f7	\\x00800003a78d59a3a443f9d7d93a316094069f0d7b85410c93ef35828a191f22b945c3ccd2e9118cf570d9dae297e466a124ec894bdc7be314366312c4166e280fed19af082abcd0a9c5a075fa276441cc8b3763ca0eb7d55cf6b2e407d8d6bb3ade8b1cf72707d77f34dea5f632a84a5c406346d6fdb35628aa8a2581db97f9f3358569010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7cf624e8f37052ef93a009cbf068cdcd9ad89e0a27bec9decaaa8a0bc612f914056555da85da0c14e41a2e0f2b8a8d6b949f0412b625f58ef41dd1db729b3904	1624437303000000	1625042103000000	1688114103000000	1782722103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	341
\\x2263fbab7b7103670e576ef61def46185a6a3f858a2d6266d22cff42f5a18cf05065149bb9bd026d8c260491656a68980aa1f28ae321a25dcca205b9a1afd413	\\x00800003c843924c83026315020b270f9563c6bdfe09dc4a28da87a5263a7e0da20d4e07d350c9ee2835881537c4a4b6acc15250eb027a63c2acbaf5d6be6361e02e54e748c52437c4aa7decce483b3d0ad44a402963ef8a9563f73c3469a73e4841bfad96f22d73265685ca16fe4c8856e8c165999aedc182bf8c5b43a52ebe83e10873010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa96ba6dcf2c26b8a9126f02329c1a413ce3f6daa627b8818af43ba46dc6b6536a7a108e13ceddd48288872b453124c22e71113d52a595a01550b5bce56ecee0c	1630482303000000	1631087103000000	1694159103000000	1788767103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x2537eb2b0e18263d61fbea1c9ea10ec50d84ca50a7ede8102128b6ab5d36a81664ef338a2d901d9b7506f40dd54806731120c6a43e5d135da0d6250b25b6f597	\\x00800003e481f62bf80b035c2a6bea3188f0d7bbad2c606cdff94cae18c07f30b02cda948ab50a482c5ac04b9a5ee77d6a22a970acc90062bbbbf04325305dfde4e4f4e1ce1fcf30dcfcc2bba4da92b0bda2c25d9bc42ebe981538e57415b3440c17c2249c8a79569882811d119c5021011ceca26e3a8c97e52a0fdaded77a1445cfd39f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x13cdf1abde84dff99fd5cd0fa61b8bb2a3acdad9c89b01ef44c2f2930dfafc18cd20704300eb19a59fc0b8bb78a1567b89b66fd8591298820d8ac83678f62907	1625041803000000	1625646603000000	1688718603000000	1783326603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	343
\\x26dbee9722624563fabe8f70b3fac591de608e4be6e44e3aaeea8b2a9eaa5999ddcc9a93f6920df52f152a77cd902e3d19ac7e279365ce18fe5524d732ee1427	\\x00800003c73670694966e70dc44e23fb9d9c3f769a69fff7c7105f836e8822c024f3a4af1287ead9c299a61efd373bb3a66ce1b698188c9b59ee2e1e10064bf6c3e2e8325689436545ff018d58236462514226c2a5490f88e44d71bd3fa0cd82fb3e5af70e3af64fb7e0dcb9b2ddf6f92bd25286ce5a6097d2cbe3a39b55e8eb3bf2fe79010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x53db41441006720d86b4f4858dc03fbff7c7b4946e6353df646f42e0a458450badf0c1c29ebf7d5a45dc4a8b91ad4e186e4c0b84c0e563e9252c7959a266ec09	1635922803000000	1636527603000000	1699599603000000	1794207603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	344
\\x2a9b64aeb21bf066c250486789758f8370906134104d76405e962d5f5d86b484cd24ef78ce77a91e598c2d1bf9b07d828b860e25e2e820377c65b7221d154276	\\x00800003bf46b3fcde536942d163930a6f44830474663b360cca0f13add8cb0b352560a50c8f4044cf3508fe3de05096d2293235373429c3cb0d472d89e477b333d656284bb0549f11d7240caf15b79c729f10bd04909f85f08e17638e703ebbaefc01c34c23138361bed0114c1a9befb55d1ddaed7b775f77e8788dead5cc16fd73a58b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x668f6bf73acfe85474d05ea9f0fd9091da5b78ae2d15c421f36c11806a39e7e816c81ad85c26eb42f6b86ba2e2055f0ed097511c7a36bb10cc1a32649efc9c05	1618392303000000	1618997103000000	1682069103000000	1776677103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	345
\\x2b7b7fe46fa508bf656188f3885a15064a59867dd45a57f69724ed6e50cfc0f5f2ddb06f32f9b0921bae09db7e04ef333ab5dfb7ee66eb44a0a1bffa83ecb777	\\x00800003c344eef49356dd638e85c4fbc556359bd133bc6ecd6b4f46995585c4bfeec32a5c0dc4f04588f254151430bc3adfd5a77338c2d731d804831b3b418b76a3f1e2002fd381dc2c348d954827ef885a1f1958bf4e32ede55ebee1a17362f9dad7450f0eb4d6383337f277b4462dd2e82009bb8c0b16940ceb3d19545e75f4bb1691010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf9ecadc04536e3741b2c90cee8db1c7e4313d49f059a144893918af79c1e8e02642921ef1ec3a8adb8aa81e9f1733b7868e8235a5fde2da7d1cc085dcbd7bc0e	1638945303000000	1639550103000000	1702622103000000	1797230103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	346
\\x383b4e46535ceb9d4ea332438634e7b84b570fc03b47d3d68083e8dbe95e4c0ecf61f4f8044cdf787468e8bcd31cdf4419c07790fc457378ba8dcc7ce4236e93	\\x00800003e9366315f46d266f6957becbe9059c69f7c13e27a5a27e5d9b7477e76e440157faf2b076e22530c690ce8fbf29a75f3ea394191e006688170a28920eb196451d02625c877914efe82920ed656a9461acb25a78dc142aff123934a4f769c29a9488553f78a9d3e314accf366377338f30ec6f0e3585aa68c1bb3de7fd2b629d13010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xdbec74ab2d1fe3acaca35b4eab45f4f748a969f032e179bcab0a448ff7509a956c1484916292041aea3d6b2f7e26f9e59b70c065f6bedcd4e0f301fc6266b604	1637736303000000	1638341103000000	1701413103000000	1796021103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	347
\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x00800003c6c7ec7e5a2aa3ee9bc7cbbc0f6cc743ee95009a011ea80d9af2ea7f2ce3b4fe50fc8818abaabe673f52349dfd9f48c767e61d4db1ab09057b2bb9e179f8c5c4c4037f903e6aa065d7e644cf84e165fcf0878faa9c7599ecf3830a0595c8dd6a151f6de4f53cda6f06221af369b7e334480235d77b5497b6369df1b50cb867ad010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5b7c6f9ce5316bf80b4924a64604d9767a6d4b12db056eec5082d5f77e4ea057fc206536d8956846e3edd06cefb0c559e25e530effbd37d4421f9036d3e43b00	1610533803000000	1611138603000000	1674210603000000	1768818603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	348
\\x3c73d5ac9079e0a53019b02c97db14205863cae093b505574c68ba9dcb9423483adf82206e80cea0c7bb0473526c791eefb2b9d58091823adbf2aa66813ad25c	\\x00800003a267fbf5c5e51edf88952db3f1bce6ab493fc9cb15a2fee71667dc43d5ebdf5223ab52458a3c6b5f3c401d3c099f2fd746b8803dffc7b468a011ab78d1d65ddb4203d98749cfc6a1770363577cf7524176aeddec694b9a2abf15d0b7d463ff0e2686280c5f5efd554afce5d30584c3cef6a52bb9a1857bd494981eaabc559265010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa685aeb6ca113e81303bfdfa842b53e6e477853315e2f7bdb0ee369b997ba33bbacd7155df0ad7feb1d64ab749291ebe72966ec46d95d7353b34d1e95cc31c09	1623832803000000	1624437603000000	1687509603000000	1782117603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	349
\\x400f130331262d7835007ae42fc20d651e2f9ba2a348d3f1df74f78ee2fedcecbb13e5fb1032ad753fccf079417dfbced160d196ae778b61ee312fb5c031bacb	\\x00800003f323ab97dcca53a4c0b470492e7524856b5c2810d04da3e0745e80d31ecc1dcb8548ecd5e165924f4d04e95d339d4f3e3b4d9f604894be948113d191759c71bd44702bbeb10c79849996c7e9c56be6fff0c7258a9240a7212b3ffcd3168ada6c46490b17b21a95672ac3a4c9c4b722ce9314808cecacb418e446edce593c0a9b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x16a823c968d81d6fc2d27f78f1f20e53dad86bf238e4785846e404e47e8c2670a097444d726858bbc5ebbe5bc674cb54e33055e2101fec03b88ea0e4558b6d0f	1632900303000000	1633505103000000	1696577103000000	1791185103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	350
\\x415ba01636385e44a1208cfaf904e4394db5f6f634481412612136fe55b6f7844b4bf028732f032725f84faec8f85202ff43eef543edb30424d6743cbda5d075	\\x00800003e9e6f925109b5a7790462c6469bb03643849bc0827087c3670144d5da8abd34ce0bc195641faabde658df87bcda26811ef309453dfb50c45dff1b4f241381351cc7bc98e13646ad8e9899dbca69b43ff652ea05629239ef9e1f8280a6b4dc1ff54f8302e15e846ef4ed180b12c7dffd0129a20af53c71595e3eadb7c2993bb8b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa6b6b1afa703b92a6fa7eeb37a4e3313ee96bf9a714e3b9dfa1f12a48e8bc4a78603cbef992537bb28d306a787d92a4342c469f5136bed17da58e686e2182b0f	1613556303000000	1614161103000000	1677233103000000	1771841103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	351
\\x44836a8e94741e5fbf83c0f64cc4dd706571b4a7ad30505104ab0ed4c2354b140dda5abc3b582d855d97149a5fe21472e6874ac576e40454bdffcbf93dae220c	\\x00800003ac84485e4bd103abbc7b1156944587fa987000c63ca8ab00d1e291b8854dba2547fc3d0a52b9302962a2abeee86e8f49a0dc515347f38622bc87ca16b6a474a928c1363dda2b244411692e248cd06819a7e079e06fe22969cc8708c46f73f23bc8cb5260dc5cf67ef4306c146e3e588009592d8fa26287d42ff44ed742708e37010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe5826ab1f58cfa65e98a32a2e11fe9ea7398b013d145695f918effeea3c224c65f1553b508c53112747fd231791a06947853a557e6d81578e24eeaaa402adc02	1640758803000000	1641363603000000	1704435603000000	1799043603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	352
\\x48efd8445cb1c696072554f248eec3640bae4c25468d60f6d43c8c17ae4accbe492fafaac0840abb6f6d18dd5deab692146ab706c2d79d12e904e62d8e1f9607	\\x008000039d046c28da2ebe548a57da283055ba8426639a0187ff60e1c6518853de4a4699dbec1287ee0c1dbb8a40e2b3aba2cf0d6f89797992c22a39f172485030acca1cad17712104c1e8ae8e4eff51ae09109ccd9d676d1dc2e637991f4c6ca71049aee79a254151576d05be687c3d64b9597904184f90160ac8ad5a55c84e67c4efa1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb923d1ab70810d537c397fa009db3bbba0a1663d6b70b454e4ab1808c8a319d9f27d0e004f3ef09e940c3833d2002a9812024cf274bc3249af4890709c86bb0b	1616578803000000	1617183603000000	1680255603000000	1774863603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	353
\\x486b2b34508ef8f26abf46f7da63ada111292330f3ee91a9464d8f521cfa2a32448cdf63c1f5100607fd292a27248b51a3c4e66d019b7c7363287fa209d2658d	\\x00800003ebadfbecb2aff3563e98ec60c1aeeee8703123f071ed1de1be099b7ecaa85a1e1a3b8c0572b6d5d0f52b20aef0c322436e07847bee6f6ea626eb4aa6c613e55a31d77476379fc345d456ed43a515e13c97c57217250d9b3278197451ddba668972077f9ed0e3e23023840929cf42e13a35418712ba95198e1481fd7aca494067010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7de1f0f7b392c5d9d2c6b426bf6a1cb9c443b3b8f12b2c5c6920b04d4ae9857ba60a842714dbdc771b4ca5bde7cb085a3a172d542c9e3e94299c91a95c3b8c00	1623832803000000	1624437603000000	1687509603000000	1782117603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	354
\\x498fe5da0206948889f388e9ef74f4df0baa04f70f4beb5d4bab57a0c812564afbe69889f70e59fa51f1cadeeb1842f3a4d9f045cf8392a4a4c56eaf6195118c	\\x00800003be196c271bcdc71e24a5128525dc97d1798385bead2835ab446184d8aaa7a2dead57f3edbd4b2db6e2176222b55c386d00a36ef6a714ed4228501285b3a84d826d4a75c5f3300c731beb1b1259e565f3e7b35779122c788363788945006b9a75f758fe53e866ed63c8a0d8df8f4ddc268b8248d42e3b718c807dc950aefa72bf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x028b56f2c1fbd1ec398c481193ef2491c4b0f1f1ed10ef18070b83ba639cacbcc14888cd7390d9d3198ff4d721d9460fb1b2ef8d8b3dba29e9c6d8ed3b72110c	1620810303000000	1621415103000000	1684487103000000	1779095103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	355
\\x4a73a8d94a7a0e72677f398f61a052f00886b4f999cdbc1f594ed3e47abadb61fbbc6bddc6d8830c1b424032652dd558a503d10cacb6f6c23d16d08202d820fc	\\x00800003e428051c5c80e0eca80402be9400335017661c49bcf2e3a175d496b425c7f727670097fbccfd8fd708a45a62c6f387fdb8182bd3e696f86d932912a6d0e8a414a0a4c3d9be999443d845ea3750bf182a0027af2ca888fcb7dce290cee02bccbc3c8126deae9fa2eae7bacc30d8ba1f1c70b5a7244501dab1ed4d942589c8392d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x053a32889281acb107bf7fb9d9b49ae83a20fbb141113a304ce53ccfedfd3e2bba966a62d2b5dc742ce2f10c48dc19d7f9de3d39705ec74c42470fdc460fe009	1620810303000000	1621415103000000	1684487103000000	1779095103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	356
\\x4bc70b00385c626da5a35b9b10004cecd43c94efc123bcc7a3b4ade1297c01e94a66636b5646170a462cc06d079f0abe65be33bf9c6e17b0d4f2e16dcba8e07e	\\x00800003d04b5a5f9011c72b2903b0842e651348e48d7dbb19e92c23eef4aeae2213507187f03371288bfb1f079b2cb7bc2dbd0f5dbb75135527f2151a5ecf96e2cb4aa1edef5d7b2a74b5eba37c593f9dbac2f31acfb7c9a06e36cee49d7b586c91f0b68bb276f241175929f152b77b2e409c87393bdc348e5559619b5c168665767ced010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8b89b406078d1efcfcdb2b97934c448a7fdcc2cac5b50f739b957c5d886b3c7a6615dd85ce4c12948aa4ec7c5dbf169021b2e1b151ab04d84a671d238f665504	1630482303000000	1631087103000000	1694159103000000	1788767103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	357
\\x550be4b8d7027bfaa1b05fb8dfb1e7604fb19fc1155030689d3a84ffbae4ed12b8c7182199e24f758ff6bd29fe500c98cafbb3058a18447a3349eec96e3efac2	\\x00800003b239f7706adcc64076b517a54650f313ff563d856348ee57de48c522a0117561c1962c041dd38624b9e30a682465e8944353186777a8200ef66591e7675a77260ee467dfc0651b96f509c6d386c8dd50d64cae05dad5f2c151b491bd55fcd9ed780fe8f06708a532e1871f76cd0b26797fd1290ecd0c2b1e82866d4509d41b57010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe360fce4d2d3e284ef95b478b8be5d415c5252e0371407eb43c6fc9fbae727caaf2bc4e41f2a3a2586fafc29c090148c32e524d37f292bf1df08bd8083944b06	1616578803000000	1617183603000000	1680255603000000	1774863603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	358
\\x569b6e9f7710d360879ca726d4c8f07123ed6cf5d200b37b4d7eded15b52a7970c93ddfbad28b337048a1b4b9e3d83569a9f9b6d75126df5fd666386c5625bee	\\x00800003bad015826fe9854d55b3dfd2300dd655404fe06b3b249b51864bcda50058ecd9b7b46a2e406d5f3fdfed45a10d2cb7580a969ea1c184f60e46caf8c8efb553a1c88ad049cf65f4bd1e9239987f6b66d654c33c607d6f4960f3bf46942e4bbdc86fc2a6f4386c072e30685c2240561e4774af3e0c99049ceeb04c32ca3d0fc147010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb4681fb9a3370d6b1de99dbe42c0781fa946125e1fe7501877be64c14e5b1dab8690e43fa00a49cf43efc012a5130e31d1753e447325d750d4b2a5a4fdb89503	1625646303000000	1626251103000000	1689323103000000	1783931103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	359
\\x5647679313951a0c68816c5b6950b18e8c95d535a5c2adbf0c0d633213d70c834d943d44e9dc6ae99226b1275cce78afa9e95a897dbc0818df2394340667b397	\\x008000039770f3a4e94e4e55dfef8be159a02ecb743aa999e0ec89d391b3572a0cd59b8bc29f61d2840af370a720abfab28246c843a5aa5c1a8e996e2fa142dd3aa7838cb7f63c1ca74d45ea0f9e1f4d530934a2618324398ad25b3bcb279769d17479033a0f443e8fbb631f9ca42c61e8bdf4ffce9139281537b04dd2a685bcf39dd88f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x61ecefce94b9b46dcffa2e40523caa805208b682f9a70aef018418d605f88e02d819c79b6298fe050af42660f2dbf3ebf0948974e4171ccff65489ba12f5be0a	1615974303000000	1616579103000000	1679651103000000	1774259103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x56c301a8a572eb8a0cd6337bafe84213731c3d0f9ce32d1afb246d403c7ba4ff9a80442e3076be19ac8bfa04eb20ba95b1d6cac3bae58134cce4f190284d49d3	\\x00800003dd24defc1e91ad14d7a74ae9c7320c3cd12d528e3a7016723f70cc66d0fd0b848cc66de1bf469fe3e8d9f931a352e0806bef61e2f758e9650138c714d158d3f562a068ebf11764240a062d85393e65c6ce05f8ac7d006d3aeaf549483f7e1631ec418402683561775e2d3d36f4b7f82ad71ba4a566f7666d16cadaa81716a775010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x16ae503970df45a5678af26072ad87fc471358fbadd3a98d1098063217e08b9a8b4e1ff03b55a88be14f650d001c7fc96b05dcdd8ea2c512f4e85fe5816c3e0b	1626250803000000	1626855603000000	1689927603000000	1784535603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	361
\\x58e7d429505486ac76994245b7b69ff918bce71dd0a828a3df04257425f067e44658848c6aa17345782dbcd1efe47e46327f2be11500a99d067911ddcffa7c0c	\\x00800003bc668d9abfbeab4225333b0039e0a1f89a5ba71000b119121b0a588a5874d560ff97c15891e1b72b13b21882ea3de5ed5de81eaf77dcc9f116e5144097a785cf79db882a83dff7719d6d5b37f57a6d058f41fb3566d24e713b0cbadfa600a20339d98a652a7744cf478ebaaa378902ddd2d26e802035addca2152379cfc711bb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x191b5f6ebc9cfd9b6f8dd6da84054e91ed915e127ba98d3d46e3fd45cc56f6fcb8700e9ea43d71b5f58c4421d8108c9ac6371b6d7aa2605c532198251f223c01	1641363303000000	1641968103000000	1705040103000000	1799648103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	362
\\x58938b22e9308d3be588fec43fb82fa8b4f67c94c0456b9384c7deace2db1c6113886182f1855dca662ecf7d4cfd66ab7c4e212e239f1cbf97f92510b667a4f7	\\x008000039eb9d16a4b0603779613d2f309cf9bde3b597f93d7e1511c0dd69a8d8ad2f76a3838e177a838a9c1a867ebd3a5ebf83df532630a0a7fc89dd67ab7d74ceb9fc95a08ffa60743c1db90f73537e00b58f253830a1f65db55a3eccf05db51f47872e94643b59efecf621820f747d1a5151707425dbcea6b2a36fc39f465d14d49c9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa0836d8069f33fa7a2a81c716c9d9e042921337f32e67a79495b73df52f25ab1103adb8f1e37b259c5c8ab4d616477c2b41ce7c524fac87507221eb92f7fb506	1635922803000000	1636527603000000	1699599603000000	1794207603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	363
\\x5aef3066cd1c1af749f4c685de40b30898ecb7dce703ba7a9264ca819a81efcb0b9e0db3be7fbdefba89e60646e64ff9f51c52e2b10e22b72b0e13fbb9babf01	\\x00800003dff4a824ac7d205f8e9138cab24a0a754d8b4444c31fed0f5fec2f873cd6ba7473e9142120ca3856dfdea5b48d63a82c155ecd3404533747433976b44a07366abb3f243922ff8df507a48533e9d56a5e17f5769b3776eb21cf4b0ae319eaa1f1c1276388beeb60e1ff5641e3e2e212ab1272c93a0a890e565046c17e924eefc9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x182691f050a94910ab58cff972706b532079639b08b2e66fc9ed289f52f3cfe4288da096a69f44c5da116b11841ce49e59b70af272d7c89c9afc949fca17ba05	1623832803000000	1624437603000000	1687509603000000	1782117603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	364
\\x620b83d47e5b3e08f69e74b3685f32901368d8eafe8c0bb5b53def66957581dd290eee77bfa002461565caa393c9ecd60a54135c0ed6a5f7bd8776ca81cc8db5	\\x00800003b4188d3a901f9670e383aeae105212f8561043db97dcf6bbee88c85b9e09d1bb6afe67ede66396e8b87ebd649390b74f098217ad71c15f9413febfb973b87b4084b3e6e3b5f23475ab289cc73b5fc1f5c329e01b658c349be479b83c956a789df126d509ecc89f84f9dad61b47791def257d62479f45dfb2a166495a8c88c009010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x746c643effa8c915ae5b08dbb354748b4931425c41ac87553e6638fa9228167c884c3e3ee185508da8832a6a40d07a37a12360c24925d545fc6b347cc2893a08	1618392303000000	1618997103000000	1682069103000000	1776677103000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	365
\\x636ba5f83124b62878d95cc4fe7db13f4054561f6c28209a8298c33f0ec8e280be7c26cf96aa7f2d28635eb705e589fc100d395da1ef205682094b1e4e622c4a	\\x00800003b3c44613c29bac6b477b9fa594561e053860c8906d7f364b73ce881d1ed362a5790179d61ec305fbe2c40a38720eff1afb5f7c814aae7b2d69b47883b7740d283a9ccdb1709c92e9e6ce73b6a3dccc2116d1d5163c84628453d99dfcc81465d738635dd8522aa71c904e9e2c864ef10ca1db20e3dd4d106f00ec51f44fc9dda7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd4ec4c53c8db356b5cd4d318738c70319fd367a08e9fe4c9c7b68519882232b3269d8fd150c068f4e35d96b9f85ac60d7400a6e7af85cad5a70e8f5107aeb80e	1612347303000000	1612952103000000	1676024103000000	1770632103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	366
\\x6397ecdc14ee1478abfc768270d271de9ac7468e5c307b6df7c605cb482d3f070ca1934d88853b6316a238be096dd12b5264bfa5cefd0b22c655b232b2b69507	\\x00800003af35cdf4fc46743721db18b11005d79cf805bd57e9c218794e7959436bda3c1b53acf2e75d7830a97b7294de3771c6a3ce3089694a3959bf1ea5100ca11ec970ac68983060cc449e434d2d7f210eceb01edc3b71e291db5fe86d4c9c99671808de26a816c437a0b9d23ee78a86f5028a4567b1f5088e4810c20608247f6b1e55010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4642bdc8cfe2b61cc25943317285b9815ed1c70cde7cf3d547e8cf920af019aaf4edc253dfd98929dcc6b52f5bdbff917724b3255011f824718edfe19185480b	1623832803000000	1624437603000000	1687509603000000	1782117603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	367
\\x6343b0097b5924b4445fd80c3f559e70085a99b2adb3f68de6d29b1e8cc7f8f75d95fc118a43799503df8a3bf0ba553379873d1bbf36ab67d7df3a78858dee34	\\x00800003def3a94b5b78cf5d0e25b912658822d6e4c9ca2157e6f6f133be7efc1dd28fa47e070bada742882c18b8f2fafd09bb45dda2cd7a5c2b37f21b3a66e90bc770b4a63b9512d1a8d57370a98c15df7f597b4111957ca00eb4e93aeac81b2c3a2297df84ae89145ba947191a88f5d55fc50d53c6ceb46b42e4e543e6cdd057ba139b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xcb5428bd12b669957a4a2a4704d2b8f97247a4e706a988d9e02fa24796288ef70c0e01b32a047f8930a1106aeaee6cf3488a4b61966063f8a076c30a7dd7d207	1633504803000000	1634109603000000	1697181603000000	1791789603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x67a3d6dd3b2109d36da432c7ba6ec1c1a65dde189f42ec87d05ff32481d2528b188bd9e5609a130bc5d7a9c68a35ec7d5abbcba2d20c6f2d91a8c5c4609c323c	\\x00800003b40d16e80f01c07ebe9b872f02ac94407de6cc2818fdbc9ff3b3c18d532584ba3687ba0b14334b1cda05f01bae01601d9adb7966f1972248c3e0886efe95be8b6b3cda6e3ff0ebe3c9699fd332332bc314de003146ac775ed836a0b771beade552771ee62004387815b524facd183db7266a20ef2aed38fd46eacae2adb6f80d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x11e1c1cfb29e845f36dde45d3f5325524445f73be24a02d4f98fde704139325def082ebc821263a68ebec5d4afcf0a230e277c6843f875482ff86628e0f9010e	1628064303000000	1628669103000000	1691741103000000	1786349103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	369
\\x6a9b27f2dee989d6bdf43514e3dec454d13053c60424814890f18b92bcd6d4141ff5895fa3585a39df7aa182dcf58f966d8ad66d9e33997db438102c2a4e7092	\\x00800003b0dab75d89c8e3f2aea9046644cd75b8bb8d4e79ef12f8626c275fabe1d5b3bab70a3349006c47ff6a10401a3ec11a2cb0ba93e7810994cab3fd9b6f2a85d2201a4f54adabe62f0a8ed35f0da65ac88a22e40169ca5a9f10a16b185a836deeb124c7b5693eacbc5cc50a9b527ea4ed3091593ead50bf5ef95c04365260a733f5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xd13a1b8a3fb5fbda319bd7ff857932289f2dddb7d50ebf7a021130930d335d9ff26dbca85bb169f18045c072499de2334850805f9c5402211aaef9bd50693a0d	1632295803000000	1632900603000000	1695972603000000	1790580603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	370
\\x6a7b334c15ecceeac0c73e0911aadf2ecd99190563842c8eebd36da6e65eb1a2628944600f944cf89a1db6d6da5271f078263c23db80dbb708c4f848a0d31855	\\x00800003d894cd8b1d56e907d4100f5ff3b6022f08566363f06c3bacb66f47f75a3ca15419b04c27d8eb82d8986bbeded40fab4c588d8f9a9778282cbf1f7dcecfa35027fe05fd3761862c61905bf1ff54bb3762e16522c6446946751f2cb8b2badbfb8177c1748324643793e9a7697e3ca1393499af937518cd1476200986eff79157a5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x71fae6f31a871c4657b56a622fc98f3b22923470d7018b9ed1983434f9431d6a5cc522c83e1eecd6c7783b6a71b391135a40382729076728a34a97643d926802	1614160803000000	1614765603000000	1677837603000000	1772445603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	371
\\x70c7960fd6791f02159daf42d96e14aaf12cd6dd693eea39dc4343fa397bba5f75b3b6bbb8a5776885e869185444e22e3864ac9f0d0f3214c1cdeb1da29429d5	\\x00800003a2cef272abaee28ab0f593d41d375cd59c0cd23aa01b4de54f6e6b969cf82bfcd329a223b194e5d3fa8c7a1b86d8d648f5033c6aaac9a7316d02532ab283081b32ceb275f1b819f0ff81d6eb14e3ec6b018c18a8009d5dbcfd1ed168b7af64e01ab7ca14577dc180617bba4032089e4fa1727b2065496e9d61c4bc8159949275010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc85991dbb4893ea099ec3cd91101cac089e2a2d71ce9ade338580efd8af5e15b6c7e85ad4c69d7bd66b5a078d9fee41a0c1098d5379200f77a7cba698d009603	1614765303000000	1615370103000000	1678442103000000	1773050103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	372
\\x70dbfe2b4404a9049568e5c3b1ee04b314982d83f4c18f8ea464ba297b1e6bb4654d57fbed3c396044aef501dd1b9da5127c5fe865029eeab1ab38b737021207	\\x00800003ca5dbc8b6e5d1e7821f13cdadc7326cf1434ce0a4f3b0877023cec443f65de0c34e62a15f8ccaf153990686b74add062ca429436decde27ae76b03ae60588c4383822831543fe83ad1e5f7d44e4d35c846c0828995b6a8e0c6ccc3b6d23dacf021c5dbac9daf9c77964cd53aef4b6522b7311c456117136d2f19dfe3460294df010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe511d6773bdd53135064f443bac40dc36c0e900792a613da8fa90aa2db023419ff32cb67bae522d535ce2cc8e3a771dc9f54a6a28ce543170bbeeb601b454e04	1613556303000000	1614161103000000	1677233103000000	1771841103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	373
\\x715bb6f58ec200a6b3726180021ed01592a608bb732e907f0806c055a517d49b945bbf13e9a6bcc592809a2502371b26e307f61380c7007b2475786971dd49a2	\\x00800003cb00ad75dfefe3d7b43976a00a25a009b87a22332d205ff24d87a70e77be797bd2d6e95ec951dd72e1dbac95aa5c906ecbe394e802912334c19844ff4d42c1e89d0a9f07a97e95b9a6cae19ed48aea704097222319aa0488612aec4f93bafd5b0974477f3548f1e54fbaf109baeccd6e86aef4caf0fb83b074e5ba0daa27b7ef010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x003d2ae6bb23bc4373f7e72aeea03355807c9f7722f7e23c0309e5bf97e6e9abf622a3f3cca5e37ce79b14aaee4ac2fef26b3d465b0db0c6ff6808ec34da4a07	1611138303000000	1611743103000000	1674815103000000	1769423103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x7497d4cd292acf351c5d66f1a506fd977f7a2668ba8cf060f58a16871de37b75f0d53aac6b52a51f1b77d9d0fa5e5ceb86266b31e2c7fdcab7944c7e16589127	\\x00800003985400dd0d2bd64a70f7cc88a70f613eeea6df042a80e199ad4064b9b6f9f523353a8eab42f70277038dfb35fda88a537a146c2f6371ace862ee8c60dd28c3b5f4850372258ded440bc2b15511a884e9ac603d646fa873adcd0ec7f1a6422596cfaad296a3e6d12cfef268e2039d98db93e5cb78f8af216bdde914feadec6175010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9e74ebcdd23569093a804cb0e385827a7b0a8aa27124b35b04d8736a3c40b56b62bbcbdd56827f76bd3525579f9ffa3d89f939d85e4c311901092283ece59d0a	1630482303000000	1631087103000000	1694159103000000	1788767103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	375
\\x756b6abd1a6c6134b7ef9e2c4d014d0206bc1a0937d1ebc0d12f804c11d7a14c67a715c4a342f012709e2eb6c0eb877d5a96a8665b82861261b96b0964bbb0f6	\\x00800003aa89d16e16fe3fb7590e64c96db33a670861997a03c3659b07b271d108b5106fa173bb4a7576fb88d2032d9bca3ac010a531842b1ce2a8924a69fcb41f4e4335a52fdce1e8eed0bc87808febf2aaab271112dc8eb76680ed417d04cdca2a2ab68cd8a7c74140ea1f904dfafb4a50fee1942a08688f893e9aecfd3b455419f60f010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x023dc6a118768ca791d7196ef75ded1a77d1fb56d7bc0e37c05e9f79cdf5fb2095ae741c8832d61181daabae8917d36b7e7d2f7dbb7a229895dfb2701c265c0d	1625041803000000	1625646603000000	1688718603000000	1783326603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	376
\\x7c23914786bd160822b6c7133845d8e9914c143b7302484f8644e8d7827f748b5b4a3fd7772ebc184c145bd5e6cd3e1bb4cdb823a0c9313efbff1c1f317d402e	\\x00800003fcfd03a6c82e81c0d4c92f58a52f2e77fbb1fa27e533a86ff420a4f435424e9887fa4e0647d40dcd474fc3dbc6ff13c0a65a56bd4412a5ea4d4c4d1cdd47a67b51e8e3019df4b047c5bb11558dcc7097c40c751a13e3e00a0caae193aa3ad002d6291eeb2be554cbe7b066117535c68006db96f981b84bea30b5a02c8b4101b7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x4e079c86dd727b075a3da78d4c3b73c10cea094fa7d83ce7d0295388c1c059f092fbecc4421daad5c11329f93c1394182796cc392d0fdc272bb9187dd22fa009	1615369803000000	1615974603000000	1679046603000000	1773654603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	377
\\x800b78c13637218250c461f0778860c58ff2c3311334e7dfcbc2fe89f1654a02480495e5663b3cca0ddc6086354024c76495c82df301a822cfda7472db97f54f	\\x00800003b1843630541bae958971f2049c80bc367be988ae9e96c94d085bdf70cfee13beec07b5c533d3183ccb0a9918c803a796fdaede9c91711b591ff081e1bf0b6e100c3e327f1e75e86118a372603c54b6fa428e81363d3003e1effc7a0424932cf1f902930364e61fe239727c43b8073b82edbe7ac012049d60207d5edd10949ec3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7146abc5c8b83aeb2811b74bfd39f22e8a739f57d9363f3b123791096e6471b7b8ca321898f61ae89c79699e1a62e531f689c73e93c5ddac55549039b6b1530e	1623228303000000	1623833103000000	1686905103000000	1781513103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	378
\\x821f1ab2152a3f7ded72752fd7091282819166aae23e7e0961c0d79da2de621bbff47203ce88639fe533aa6706c321db7c0655e8af3670b1af8023514a882490	\\x00800003a855cab23013e9afd3bbc47601938bf0daa0580f72e066aae5d355de636138e9ebea58d80a7a4e132ed6e0dc46045e63a62521b36b46712c1c80145343be858fa4974a2adf6233b234707d9bad22a3313f9df6584c48720ac22ab596566625104292282d40b3843a8737e643a8a4cb8a36a6269cd07b0b7538b0dc264800d5e9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe2c2541421783676b5167cb60ee222b6558f447f7bea908b9c332e501a014906f425ad315462486dafdf9d448923600747524bb9977d6359a026c512ff7c5f09	1640154303000000	1640759103000000	1703831103000000	1798439103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	379
\\x848b3cb0e586023d4df7531a156699ff02f57918c4e0df70c9e85fa1a47f75d8d0b8a97b081a99564093de4753d077b20d812e5d5a433bc1f11593659bf01ede	\\x00800003cd050f6eb165d717eaa2e44830f769f7e26618806b3d11c1e08fb2f341a63f4cbc4da81cc488b63501218307f3c6ae6c93764e0ec1e9500462ae27fbe88f75e565c00024796be444457eb4bc52e03f04d545db3194287c380149e09dd973277a7e1d6928c566eab9940f462d64a5b67d81d4e5ad58cd4e00c55c44477cb6bc87010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3edb9ef37baa574215bef858c07cc84910ccf36676a5ac9c1974e0c2f8b11f7b0687b82d8ebd26ead4b338130d8b19a0b192c0e0f00cf3f4c41ecb3c98fc8903	1640154303000000	1640759103000000	1703831103000000	1798439103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	380
\\x895b3aa41b26bfa9d878272d0803ee5eaeab1f9222c50cc974e1144a332df626c2ee59d465fa09593570e6f02f067675733ec3f0524698e6c38499200e2e0b61	\\x00800003f716166b5fd0374b0d06e0670cf4657c0b1ae84d1bdfb1f1640591dcf83257aed03f429124a1e41dace3763b01bd3890fb266a7cc98f839bca73af6ac73662e95403317b52866b489f2f9c29961724026844bfa668ffd39d176e0da87545b677ef332d9a915c187e92e79155889e2b3036a342fe1998fff4d9f69129df346cc7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5d2a2ba440f5900892e93b0e119668d7dbf1004b55184e3dd1b1f134bff1a067ebfc997cd9272888662a7e356a0a213dd0b70d81c7401cb3a466d5b34dd2cc07	1627459803000000	1628064603000000	1691136603000000	1785744603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	381
\\x8c8f729bea854a0338c6687625869f675f07d8a4c0f1294495a117d52c9e288a37e399fa2fd6c54e66122252c04ffdc5522ca8013efd6ddc4e32bb511e85c0ff	\\x00800003c0cdb4d7032c83de0038241fd66c13e38ef0a5710fa183b09196a87cfbff47762f863dfab1dd43eaeb1617a5ed6a826deb0c2efc42ac0aa5f6c30b174f8bfc4698802cc83e50a2464d0095a0022a8ea185e6115d413a531b0731675a6235d8924fb82ad0f2e551213e783fe359cf426714770c8e771a5d7342eff324329e78a5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe9541f58f39f474dd503c2d9bdfd14db2178da4acc73914716835daf35c5aebd9120d2ab1b0dc1c9d15db663ff1c9a7efa7dde78370d0e9fc82ac4e9c310f70b	1620205803000000	1620810603000000	1683882603000000	1778490603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	382
\\x8cd3d7bf8b8a7e093984850fa6e539e46fddf5faaf81b51af97953d395992ba130dba85dd234b6475f5d7f8035fb4707d82233d368112a1f0e5cfe9bd9c8100c	\\x00800003acd7d8584317f0e2ae9e4647f1f4ec444e311ceab2b233547619bf0ce204e29454c2d8e0535a9f8011ea81bd657b924e33c4191b2375a0516de2c57b75ebf779e3c752a63665867654ad7118166efbb444c1ff6110bbb0a1cec242aa7f71507abecdf2cfd6ccea916da6fd1a619e31e32221e517bc9d23ed5a7e14da5c6d6625010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc545899f70a5824d7cbfd7d463a103a5c63e98688ec2fcd88ffbab8779d75162b27b6ed17163f0800b08700fb4b3c95c10970d03ddec806a90de063b9662790b	1618996803000000	1619601603000000	1682673603000000	1777281603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	383
\\x8dcb851c8e1a7636f97300760c5a7652a09d1c452c6f11a9a11738104033e283e6151dff7f85b501adb3f6adb2be0e728ffa2d8f54ba6052a780833709e4a710	\\x00800003cd12948377a39047d056e52013d0eac009a9d162708eb61acb965493285e312b40432e0d36db426590b5f7b324b604583056e19bea641f15487a4a3197ac981a5abe0d0ac1717b385a11cedcff25d3ac2f32b8eb5cbe5acfc7b0d69a6384945e03b47b856de52c3e76af9de4a02cd732ca729547bb51bc0d995d4a5086640307010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x5883d6336f09338cb103557df33b56eed9a2147a7bd3e494295d3512b30f7416282d73d96256f56c18bfb424d5b3ecd270ea5f48e132321dda8bed10a7476104	1628668803000000	1629273603000000	1692345603000000	1786953603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	384
\\x8d27307e422640884f05f6a2a1a4d8b78beffbc26e14c4152a31a0e7dd8b29d3269b467dde718b2fcb15a16b207db31b9888cfe5db04887b0eed6fb1a42be2ec	\\x00800003d7f86d1c3ee8b698268d8fd89e5b0ec3d941a14d9e6d0ed84629742b25c18de290052f2b8b5410a975764283caeefa9120f407d2cf86107c9d284c2262da155ed1e865cfede497053de77948f4b8acaf9e9667250381c5fac8b0415be7d7e017b50c61c42c3afbd0aa410e0096102d58ab9bab8b087c9cbd84b296ccb7caa1fd010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3e5dcc23def4c3beb947a794a0a36e924938a46ba5db6d77b97951446d230b1b1346cf0e62e9bff2bec94fec80f7f5fb03380a5f97bc8c36dea8da1993693902	1637736303000000	1638341103000000	1701413103000000	1796021103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	385
\\x8f5794bcb636896eb2c2a82439554eb3e88f0800f88bf27e68edab5e54dda2ca562471ee094860d0aff28efd776a83052e29d95257f90163c1cbe84177d4c99f	\\x00800003986a6411f29288ba328e05321e3794324bd7dd1679bded8caa049599a240f8e71eb96e0f314a3d9f9be67c37774465338ffc3baf8922f7f414e4b78ac4a903c470c9d38f0e2a6fd2dc6b4358da1cb682cb6ce34d1055c60b683e9d8996e0ffda268a1d9f54761e44757e6232c19253acee2b81cf410b218db9372232964365b7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xfed459e5a18ed8391f34dc9f4634d803d13f83962993b2318f28b1612390e2324bf4b973d990b82022d861a85add11d04f7a51a4b97335336510b796b7f32f01	1626855303000000	1627460103000000	1690532103000000	1785140103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	386
\\x959f840b83bbd00aa6a298b907affa037972023da9ad994bd408c00d9f50fe51f24820c560bd1b32633eab37c185b2ebd96e47b2a131a8f7422cef24adfaf71c	\\x00800003bf4f91ed66eb20c189b3ca6e191d3ac863a095b0c3894eaca35fa44461d8597968d74ba9e8a4b55e3d445d2d81ddc11f5436a8b96bdb2c2b1873ff9cdcef2441aa47e837e28c1164c3e9f09d9297155a4ebe6e586573d3054aceceb30ff79cbdd7656c3a03340ba849feac4642746bdd4372bbfcdbbfd5b15a0c4eeab4e7f55b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3e1b19d7816a725616ed743824cddb1da683aca58906f0e204b66685178bac78a7adf93adf61d3ca3d22c25c4c64bb03c88cbed94eb5f058bf3e21881c605d00	1629273303000000	1629878103000000	1692950103000000	1787558103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	387
\\x96b763cf415ee2d0e7c578263d703a46678c6528569a9a2b41460e3e3ec7439a3b8feaef180603c2bca840b8cd6a5f77b736452f70a40cb89dfe72ed919e3489	\\x00800003ad5a44cd0a693fa855ffa8f84b9bd39638ff40341dd3f2d77e9ebdfa038394849e948c3eeab7a160736ceb05da1bb446d76084550ae610fcc404fb2ebf3b6af872e557ec7b8fd9a1393355af1fa8b9d516c14a511d653deac55c803f0b1178a494f0d92ed0792df3c13ffdd7c68feb68950d602f81295a2be4b91e255aff3b8d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3b7c03ee80f85cd1d234bf9ca23d5cc62ee6a749072acd20fe6d1b0a5eb44afc61e6843bf194bb682002d367a92fe47621986c62307024948e9d0a0249e4f001	1626250803000000	1626855603000000	1689927603000000	1784535603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	388
\\x975363fc653874f6199ca859bb4280cc2b094bbba29eefa594ab510b7d1d213f86ef2becf2733524727d6c594561cd16afcf2d1a77265dbd06b52f2de3eb5263	\\x00800003a9ff54992e2f5424202c13515d1db86ec295fd5bd7bfbd7047b4526c86f5698eda2611e233b74186c7720dd5a5370c8b08eb1d49f083653fd9d35a79c91c258b77b329e59b3d1ddc917297ab5214b6540bd47b36e32e7b3583e405ab774d049c82152dc7b1e284463d530ae2554727c2a502240b138730162162d3242e10a82b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x41930c4e8a8abd4982a68ea4c93b89ef4f2929a3719e758b57f85c5971c9269c48633575887846875700662d98758b3a911f3efe0378d318b473089226705c06	1616578803000000	1617183603000000	1680255603000000	1774863603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	389
\\x9737c6f41baf3f6670c660839824cda97fa7f898108bc165dbaef39e604bed48db17569861afc0585d1bb47fe6af1f790df8531be863c256d36ba0b55ce40dad	\\x00800003c6cf8d98b35d4b8f28320a8ea98401ffec4e43823a6b6b98a10f9033fcc4107ee53b05abe9cb2079112ba0543757e089cd36fb4146306aad2ede4aaa727131434f5a511a2f96ec34e0df87c205fa8517a349bb7e5fca01737a9cfefe618f1e4c9634c8f123ac7cd767a939b82083905188faa2e276b80e44ac0d2e7bc2d0b2a7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb55d89026511c6e8e41c792625ed3c1ea1e302b0cdaefde6e213aeaf63a8bbfcb7158f3f79d8684ef15d4735ade188c3c9374516dbf14a56e1bd305c6d673b08	1618392303000000	1618997103000000	1682069103000000	1776677103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	390
\\x99e3d3c99c94832e6cbbcc888743894dc4c6bc9894919398600404f4241c653d2d89450751ae669d4b2590905a6eef1207eb7b4b584509878d767742bf8f3fed	\\x00800003c88bc81e3e62a48b81b21a0059a25fefd9b1a0596fac518309d8cb27496e5a14dc18cee72d27bd426c22e626aac5a804adb24ee3b9b049605c37551d680f1fdecad258e9802e8645b783caf840b6f34bcaa4946058e7f54a1b0c12fb88178f3e7ee131719f824fd998bb0d78091a079eb2246e26ab9dc0883876f82bd60d25bb010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa078207bb90e8e7ce248c554b3b8ebff3d6ecd44565e3e2d619e9abbc76d838c6e067257a294bb4a8dd8c3ff06b267ef372aa1576d3546e9fbffe581a73b800d	1628064303000000	1628669103000000	1691741103000000	1786349103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	391
\\x9f8b399c5ba1e514c5b0e2799ce3898fd6a7349e7dd16ca8b60f47c233650285c056893b1ce5187c5f5c331f26bca53d90a8435d488c05b6e72bb8fd923c75ee	\\x008000039fecbeb886945334338455534cb784bea729c68f5d4f6cb713854346c5778e110c77f17ce52abb2875785a73fd28394c2c1fe723f62a0ec0d756c98197ae4cc9257360400b12d62bf59184fbc6337267d21f82324e05ddd63e5e907ef4b261f9e8e22be4e212f02112673d88ddddb8767b742dbad4293a445d43d61dc310fd29010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb4f5059a01e9feb2267032eaaba8392d36b6efb033b9436f268ddb16b7b3d6656ff7aac01ad35fb5e369ccf760cbb4c2b3d66342527424027289a207f2821805	1638945303000000	1639550103000000	1702622103000000	1797230103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	392
\\xa37f70a65b86e64328eef648b7f8a4c691065a76d6e04b0f16c862911709f6fdbfac94211caf42c4bcf3c004a3d7a0e19a6210c1caa2d8f133d6bda788ada1b8	\\x00800003a61dc745b387cd03c8c756587c172a2d127ace3e5b6fdd93e10b3ebe6102c9b4568c8970d1f4bcb9dd3a8b40deecebc697fcf7565f365cf3995a398a83b58b31548ba7ea2ae78df0d653484e85114e120bea471eb8af0e7211f57d08eb4502fd5650cd6e3a803ae40ee4e0002820a4a3967c3c2b72cccf4ed43284e625ad9bbf010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7a7c6b49e908b669c78663491560e728c441df95ce22dbc9a1da6820455f4cf80b0162f4d306b3fa3f871edc191afc06649c59c3d0a36b63abb54362b4540a04	1620810303000000	1621415103000000	1684487103000000	1779095103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	393
\\xa4674ab3fd010ad5362d37cf149303facc5f01616ef3b1cfd0a2e57e35ea433a88e6c6ba7234f510cb951a2b0eabf7fba26ca77ff422c31606d63e7c284aafef	\\x008000039c889a45951bd6463c0c0a93d9104bf1a2bb4cf4d4602ecb01e9c2b8c2f091f2af1206c0d6c90be80635faa404178778d90b807c7a105728698befb86eeb93bef4a8891644eb8b47c9eecd8f0113b8a2138417eaab22fe0be9651c24399e194ee6b91666be1fe2e4b42a69552f299aae37929eeca0146aef38578f93cc7d7ae3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x787b203e9f70ff167b2603eddf5a32093b8f4f807ec0c3693d67e0073472cec2927d8fd033bd5858cf9e0ea5eb9de07fe6aa49b1bfa70ceb38ad8b6331f49d0f	1617183303000000	1617788103000000	1680860103000000	1775468103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	394
\\xa5abea366132e6e4862d40cf5f6755b5dfb8cf53798900dd1a13170f1f955c1e9b9ca5f7582e95454c23098162b3e7240183ca262b4c7b4954878b577c6b6614	\\x00800003e44cbab3c78d6bee5da9c90a5207e99845bb9c87ddc0c2c9b3994dbd9b4a2338536bc5e2861eaaaf6814e4be96f79355aee3d29d581e10046e6825891e8407c712ac726459d1df28ae0a66bbe509a94c81340abcdeec1edd093a3e749b92a858ac9e62f954553b223b759066ce92ddf2e535503dc3db4da55893145b3cdc4ef5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x42254714623106af1e08993b004b8a2292a976799d72d00f7a78921aefd51b1f4d7daa85c0c9127cf3c26bb264a487607ce05810c51227c0ed0d505794ac7f02	1635922803000000	1636527603000000	1699599603000000	1794207603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	395
\\xa60f8a6a547b763d0b6e9a4e09868b6a2df4d416888c792e7aeb68843f1c799cea0c9cd474fd99bc7d00d728e9f915d176d2e374201883b61a2d832715781d04	\\x00800003ea66d6078eb25c52e6a5d8dcd57992413fbdf34e91e53cf0772087780af9f2e9434bebef1f4677929db87435999171b9333c1a728078baac74bc735858992a71f1ddbe51d7c00a8ce553dcca468f1db0f925695b08790da39a6be240c19e770c853850b637e6b445c785de00141dec00d0d9d6fade13f64b701d7b336b808825010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8d94ced5cf1b2c8241219f346d764f3f196191d5933b93fff5a4589932b296e3214dec9be469a97957851c4aeb187dcf45832bcd772e37151224b8c3fe67b60a	1615974303000000	1616579103000000	1679651103000000	1774259103000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xa7e31f55c416b331b33200c35190a944bd68085d974c0744121b7df0f1f7ae02a044dcb693f35e97b46e6ede6feaa3158214f95f0b3ded7e0dfc912d0a4f27f8	\\x00800003b5d9caecb4ec7b6129d06665d1df2edfba4cadac1d3c4df4994a4ba7ea8d0c843dbecdd2b225072e019ce0d17866cbdab44968c57df999a200b4661c912ec142dc38b799f99c22559a03fd200eed1e6e0bd72ecd89949104dc2b3688ce67a034c09172e0487979b4464f4b12c22cac009f80e1167af830f6d3aa1b3a257631b3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xc3ba84610423139dc1de29513894ff84ba7fe201da477ad6624d3c1390ce930b6df9cee6fd15a401b37e8bea6fe529378c5d02fb88b3adaefcd671cc892b7d02	1615369803000000	1615974603000000	1679046603000000	1773654603000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xaa5bd61df94ee1311c4ddfb43440ce6a65c4189f20ffeb1c0c0efed9af649468b4790ee22c7e89d93245ce1e2c5f4a70564bc132bbd4aaa86709c42c4271f496	\\x00800003cc4c74aded541b8fd83c22a48752ca489b2a164e5d5b7d6b79a56bedd0fde3fde3caee15eb393e2a997b35bb7f7fce643a21790c4f41d367105ca38c7c9627b16a28d9fe4b19f48643c77d1c8e22d70524b228af12f5ee429cf114edf21566b7440e9ed2b35b30878edf86206755970c0edc1e012e4b2b9a74d2664e1825e7e3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xaf399010150dc7b4ddbb97c016028be6d1e0cbec1c81f5f6a0b5172b9c3ae691158da5c86f9c8cc6cada979070fd03dac5b53c764d9222740f0a6862f93d440c	1621414803000000	1622019603000000	1685091603000000	1779699603000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	398
\\xab0f71fffa7bf0d799d84934c5c9cc3ad15ae3a1651c7823191c8e40ece45f325cf5d8b5031771e69114e6110452cc89a2ae27199a9354cc59417e1070b9651b	\\x00800003c105dfd70f93848a34d10963a1d10d2e5ac6914bb74fabd20bbbde6f716866375a65373960aeb255ef3511deee85cf1e0d364b7e62676b57fb75453522a59965df23d05645aa2e0db12c16e441f97ed804dc4f094d3b60a89a8015ac4fc616e6d80f4513699f165bcceefb3006cc730329c5ec9703877281418dcb75bd94c4c9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x47804db21a37ce8bc52bf7a617f3b6b859a970066ece25aa8e3cf9a828673924e2368746d03a4aa2d06458c5dcff7327350efdfa161dc8a17fd32593f71c100f	1626855303000000	1627460103000000	1690532103000000	1785140103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	399
\\xb17f17ec3a8375cc5d387c874417406735112de1bf620274784fbe0ec36d69fffbb66f79760d3739ba3e85bf20cdba1d3bda913e3276d4687babdc2366fb5721	\\x00800003de59000b6e0e7b03453df54dbda4cc64a5357cc61071d193c5ac9e24caa386eb902df6ce531fcc63ba72434129202b595ddb774e25a2e94e67d0a1d5944be14714fad3490e0f0f19d377a6644a6d9cf78b71632369005ce693bc4bed57033c1a3d9f637b9cd549724d27938160b1a0b76b03095953bfb18ae6278eb1a67e7999010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x9ddbaef309b5b30e2b2bc5acec035f2d0f241ecc4caf07fa4c522580f9b7d1c3869157bc35eec904acc2fb5e0535f0aff532f0ea8a68857f36b626b8c29cfc0f	1615974303000000	1616579103000000	1679651103000000	1774259103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	400
\\xbb0366612bf1374b54a256e5762c69f537bd4ccd59173abe7966291ecc93911070b0b5346d07d938ddc274fe94f18db357556d73d770f7f5187f4016b3aae996	\\x00800003f0963bccbcd7b3352267739818967ae8a93eae28d3a1d6253437decf24d085d944615f806202ebbea9bf65e935ab9b8069922083ced5e3ed4c81b8d93febaddeab442b4842874467fc555f637a02dbca3fc8c3b8701b37ea2836fca2aa7911aad5554532a77e261a39dfba9291a0e73c96efc58280873207859d4706f4475417010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x976211c57eef72ec44ab718a53647ed4f93caf7817d766684f67069c4c54c3ddab5cefdf4937aa3afcade44cf8d3067e65903efd88df9d46bee0ed27c4914202	1640758803000000	1641363603000000	1704435603000000	1799043603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	401
\\xbb5fb96ef14fbfab6334d75b6d8e22596e41c7b1a97ee20ca39b4093d10240dda04f21bbd70d83e83c28b25935cf643fab7b7f17f1c11a5d3954afa5fd75498a	\\x00800003a00fd2d75f9c93488e48d8d1ea54978b58682fcee29252c7a38d6b906618f1d6adda2116654755468e093fdf75a25fe2ac3cf5d10112ba83c42c2d5230cc1f76ca88e9139d399fce350573541870b547d8b8d82da55f3105098b8e6de58dd90d3e493053c01d2f1fa4bfd4d75fd02fee9aed05baee0ee2ea302ec07268c22cab010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x524e77c502be4660f80827eef3f2fab588d40df82bef1811fa04807ac467f234aba38aee0c3f6b415fcd9559f90d5d2dbe23e16e74e0b303da2ee97848643c05	1620205803000000	1620810603000000	1683882603000000	1778490603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	402
\\xc493c67889f06c2c0142cf6c4af1c9e68a1b2abefc61270622f017a0e1a37cbcbd0cabca082b30af6cf4c17ba80380a0a589f83c1bc47a405dd9d720d474bf6b	\\x00800003e16fc414b8de7537355a9d86ed8835c7d75612682403785e9160376022488f2cbb93efd801b5d0635e1ce4206f046be1b3df2053cc5d650ea5b7e0dd546604dac1984388d11e02d501020f39ad7b9d0aa19bcec77f5b9e001a1177386132e899845ced5ba4f3c2a18315728f3b19bad259cfe5faccd15d9e73aeda55e8555c07010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x58d917472ac55f372217f07d67e94203c6e94700d5753e0edb2971d293411040c43e8a0454fe16a50d53de433cbd6dde3023b033911561bb6196923bc636560a	1638340803000000	1638945603000000	1702017603000000	1796625603000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	403
\\xc4e76ffc5797d6dc5b74118295c15072422bc4ce0b4c422a2098bf27f1b31d3731438cc33cf9ac1bbe53718a705a66865fc23e90b43189b39ac3772ca9a0060c	\\x00800003c569309f56dcfe705960a30299611eb9e2c14b3569ac48cfaa6df3ca63bd468285b214c3729b0dfe4e77891eef948c0c5a19de65db66cb73d338220e61814e3b24deefcd3c22aa1ccfde895a3e932e305e603259fd0070bba597c81d9bdf962560df360853084bceebd9e456ccf47442befb61b6dcdd27ee37396a10351136a1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8ab61ff047e122cdcbc444aa0c487d19a79050d064b10a4605ca333764380b130ba69442951556834df857d982e211ab9f43b94179ff05c375e74f6a4742f409	1611742803000000	1612347603000000	1675419603000000	1770027603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	404
\\xc5efe340f067a286d752508f12a5e834c4ad033735cef28a62a7f1b1241e913927997374a8b9927b99c1b2eed43b78394ee186f899365be2d73eb2e4ec276f3a	\\x00800003bbd6d51cde01ab99ae322bd0a5d38fd16decd5daf20214e87056c0cabb9ac53e6f419245a8f0dbf0cc24acbb20533f83bdf7cd6122dcee03e65f0e7b210497b06285f17f8edfc3d0c05cf1ed1dd27ae8ab5c7addff4a4531d07a1ba85df20ff8f189bb933e6908f4e12400fe1bf072aca5fcaacc0912080f117f61ab1508a111010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xa07718bef1cc43000bd22dc41f2694f5e0eb60440fc68a8b28a3527d1be6d7ddf2c890a2343a4bccb9404c6c346a42f3445c6e41a74ebd578ae30512e6c5270d	1620205803000000	1620810603000000	1683882603000000	1778490603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	405
\\xc7df01e2457feb25a28acbcf0bd9d143937fead4707e73e094e06c0dde644b9328bc1effa5e88d1fa4f0c272518315e39336e611171cf0f10802acbb466b0eba	\\x00800003d2ad224222ede90032a7e808c5f7a458801cbe68f441827e12fcb60ede52b1284e2b46f4294e0665598b584c6ebb35152aafd931263b22bde58bfd34418ee0c43b873757a935f4471dbe9579f35bda5c926f2e48a494fb12d8714c12434d014c50bebe59351f1b88e5c137f423fc3449a8c01f71b629e44ad76a095e0344869d010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x034b8e8bef0c965584bba6e00473b7a32029186ee07f2da9f736a00eabbf6f630e1197fa4158183a50f861e8a09b321b2c449e9d56391bae3070e4944f83cb0a	1619601303000000	1620206103000000	1683278103000000	1777886103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xc8afc74ddae254453e37d052e9c5f777ce73a556dca7afc08701438446878db3627970883c4cd7df02c4a71b59b111ecf1b3956ab70df7fb397a14ed04d225dc	\\x00800003e4f4d0c433b779adca8b6c35bdf0eb15e9f560dac3f453aa0ce33db425dcf75e5500f9aee7aa90a3ab43250c44b093500ac683a30680cece467f901433d0f476b1f50dfdadd1c9f33e812e2cafbadd3aed93a608c5f3d96bb6c38e5efe247013af6b6ac9bd1731534b48efae29320b4befbc29be2c4f0d65e2d1bc262341332b010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x23be626cfbe9e2af15280e19cec0eaa494a6c86eec090c13e48d2e7a6651a76ee2c8026b356a0b796b8029d3e2e85014b792ebcfbc82fd3ce44b7775cc415a0f	1620205803000000	1620810603000000	1683882603000000	1778490603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	407
\\xc8f76846b08c3780725813b35f0db622e6a053d25c3ba67253d979f03428447458df691be478b54f1d90aef4445fb8ccc842447e8a69ad3e2fdcf57807787de6	\\x00800003b8b9c927a1c237d74dace6eb6fe8561575985e534d36b9252aba15e35460a1723edbd191fd9660b71a8710f6e8f896a7ecb43a351397e26b24df45aca8560dd281456a976369225bc62bdb6634ea7b1594d2260d99f72f4abe25d3d79f68849c3812c3828041f41b7c78eea349b5d3519e7e88cdde83afd2c66796c32c6dad79010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb5a57889fc682ddc9289f677dbe87836d93df0980fbc30c173ed1cea179b6d2b71c66a054527c154d054c000f1379885369ca0a811c09b1d5f626a685c9d380b	1634109303000000	1634714103000000	1697786103000000	1792394103000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	408
\\xc9ff3ef77041f2d78cbb8bfa60426500b6cc5d4de49bd3ded5d689ce4eefa8a00a5a016eb353b8dbf98d64184a7a0dc2f19f9bb4fa273bd62be6926df3769a4d	\\x00800003dcb57c41b73b4679b576ea2a7a68360c50488445e0369b7cc26b27049e6335c7ab653dbd80630a47b0bd8dbd12bf991bf1aaeab0e41130b390ceb0d4a7c2f7d973c1916852dda422abfaf18d56082b042242a150cc8afa1b3d367c540064a28efc8743db13d35beecc7e4f11d9943e58e4fbb816221d8180937f82fbe5c1c5d9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb2a495a2af79c74e2875dbc6d67acf80ecbc101880362572bb6c387f3248ba743496f1a2114d2da898d70e53ca54d4599d7a0dbe23a77391a95035b488727704	1622623803000000	1623228603000000	1686300603000000	1780908603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	409
\\xcaef73f56a419c03091600bcab1acf7f36b0d2a825c7de1102397bb880fc5b36a23c4836be6358e3d9bf2a4f060f6d49a2bc6052795872a9c7def819078ef477	\\x00800003df1440d762e94c3a74d9752091e1bae12bd307f55bce0c46c0b08dd98ffdbf8294f930c6f60382229ba198ffa556b113f433a9cbe6fe62a7e39abcfc2d524ee3b71bd4a0788b9126751864f4bd7a2bf27c7473a67a14779d0463736c0e4468354c064a441c50d99aaec2794872460ed1bc27f6b35934d7ac36e2e79af1acbd85010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3dc77bbf5fe68ea77412c31df5bbade3d29e36f32275872ce277e364a7ca0f9d70377aa29f3eee959ca72eb4c3125cbe6369b8c9072e776971c312624b8d8608	1634109303000000	1634714103000000	1697786103000000	1792394103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	410
\\xca2f989108fbb2b71a1b56d14f71fb7832ae73e4f368c6a84d83c9b4f2ccf8664837a49750da623526aa2f4e5ea7e4f60bdbcc991a746f6add08b442ceeb7e5e	\\x00800003eb8fbb8dcd8ce45b2d647f0af67b3e9392267fb825759634f89736d87e5f02d56cfbe3ac75c25157e7cfc82e03c2261cfaf3045cb0003e5cb1871e7ec9ac7eebfb1c740b403e8e654a5be50f6ee11e67dfc3c07dcdc234e91b59c666f32c11fe1878bae64c62d426028c425c92b06da4236b01c332f69c1ff7f928653f464dc7010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7842e61d8f7fe8220f4860bb92058d763e4bb83c4a866b31107d351b151c9176edafcfe9d87a053e894922960d0a2c5ed4a05c73979f42a081259e8af7afbd04	1612347303000000	1612952103000000	1676024103000000	1770632103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	411
\\xcc773ada08e85e52f58bb4ce44a69977d3eec17b2aeb52aa8dfbc2e81b7ad1491315e142750bc713b86177ce20e1cb5b3ed52fbd5bc77ad0ed66aa49f29ec2f8	\\x00800003bf5c9833fc88d9b66da99ba4fc49e6c2aa9c1806421106662668f8615fc640e3873c7a81351d7a4530a3914aca9f6ce74783f27560bb88890b6616a8b7af79dcff8522b69020fa6212a8cb801d562d4780d120e96e4b6336514baa29e92d3a9afb109bdea8b584f4e0a568df25f4881cbd021181aa8ca15d868624f0edaf9aa3010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xe6ac46ab5c565f80ffbc1d11934039369e77097dc0c1c6f703a878a513a0e81cacadab9ee37d38a0fe59a4c7b62524ab51bd2dc4e614ae6a1c72562a6adb4d09	1628064303000000	1628669103000000	1691741103000000	1786349103000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	412
\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x00800003beb860ae2d43d163ec1fd5fcd3cf57471e380eb5f03bd9a86311e0096a739027a8a731ebc5ce064cc2c8eed114b4c074ddc33d58b9e68bea69c7480aba3992e00264f094e5a4104beedd63a36d6c6254728a75637558ea072455c47dd69e81247394e5306bb2db982617f9ce25aec33d49e88a5194b0b8bc21e8ddc6f2bb47d1010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf7d3ac1e01b5dd3fd9d676bdb4248744fd31a9b25996856c6ed93178216ee0e0fa3b67f7b0c9a6bbb138a800cf309c3593497c108db31abe518f7728c21dcd06	1609929303000000	1610534103000000	1673606103000000	1768214103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	413
\\xcf031f489b7c9cfcded2de9bf4a821002c70e1e94f26c75b5897f5ba7786c6b671225db7ae2e1c71c96cfce1cbab37211d96976c18684aa337ed6f46e7ad133b	\\x00800003a4f3ef783a872c7b816a85b7be5247566e028cc33d839cea5b4eecfb576eae62b6c342816517e27e18b5d321982f64c6052a8016a9dafdc140dfce94739c816dfa1811d85c49dbaade3fe3d78cb4650103436608b72ec331106b3399dd9f12f7dc4a1b3656d18b9f478f6daa2cd67458ed55370f232427a71799e694adcfee85010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x00bd9d08344da26d7ab997ad2fd3ce2c256e8bccbc669995803a90b80045a6dcc005c44326085accc81befbb379f30f7e06afee29e49499053cb37b5d35abd06	1631691303000000	1632296103000000	1695368103000000	1789976103000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	414
\\xcf5f9275b4f4bb2c00f8757fc552fc5a92d273f94f9720d0a36b17bf8f1b0adfad13a9910c7baedeedaa9b8795e7a0e66951bca9d1d4f1e0d27ffeb1f95691ef	\\x00800003d5b397bb7b5235be3007a5e18cf9cc3d1d701d4266de044e95f4814ec959931ff1ec437b6c3f22015f84642a03c221f6cc7c0899ead18c48f73bafc7f9a0a1a8fa008246d627a06e402519867eb6e71f808d356ffb2d91b1313b5627a285a5dc9208db14d308bf090d398e72680b8a2bc0a70260d619560f89ca8d0a7841bbd9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7edea4714a26ad07034ddb6e21eb2c1a39d851595bef72114888ef062b7bb64ccaf1f4438935d9d0e0b3820dc333de7f22b698022f8344bccd05a6a091e36b01	1626250803000000	1626855603000000	1689927603000000	1784535603000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xd0dbe347608f3ba04db511c885699ffdb5db96fde796e2b3f7c9c59e1d67e3ceab89e95e75750678b6b9e4f4299cfa6988f159ec268bcc21e55059bd0a79c950	\\x00800003d74128accf4bb2e9f729622ffce19c038a946b6d024c40eb34f9bc46c57855e0778050b7bcd22e23fc901633b9dfe6a024bf23d1d9c25232f31ca17af318e8c53171d069b892c21bcbf5696c46c91a9c25a2022f2c861844537ef0a30c867b751f2fe365cedd723cc60fab47ae562e020eb7080b7534afbad9d07958d47a39c5010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x838e4b2561f6a9919c54fbb1b681ef701f7f3210cf57de13253257555bcade92a47d438994b51b51149c2abe5305a7e210355d2e2fcae1ab3cf11cb52cbee90b	1626855303000000	1627460103000000	1690532103000000	1785140103000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	416
\\xdbcb4565914f939c7cb87da4733464e53907097b3e448921e7e1df7640d71dc96a8cb7a7202078583ea339353addb16a59c1f5fab38427349baa2581f16af85c	\\x00800003e046583f193316d8e69fd6e10423dc892a311cfde5c7e0f49be22311b6f78b1ea9621d16a315007625046df467ea22f18e24356153302c5495e7f44c9c302b88e6a594217c9cceeba75a60c2a19623179866700803c26c1253f0bece345f7ae20da7fb36efa045fa7c6b4a741a7116fe5f1710f3334e55a85962ea7ae813ea71010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x81721f100aeaf7516758aee6ed690d1e188ddbbba90adcd29d4e870bd612fc414f10748f9177db2cffe20d3d639f70f54eac040eb6f3943250772578f04f000a	1622019303000000	1622624103000000	1685696103000000	1780304103000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	417
\\xe07b2344c5a811c65d64c9b643446008d9c8543649122bbf6bcb84a14cf91304d12e040c8c0cfc33e290b3e0c00d8ba17084378e7ab444fd2dbccc52119b11ea	\\x00800003cc2e2100e6aca75975174c57fa556c56d302e1f0bf8be0e26b683603a488d80839bce015711feb14becbd02be7066b392a2fa46e64d11782b6c47d721eb962f514fb5a670c73f6a5580d3f16291d5985cb1a4031c832973a62ab946056fcc9f11687611668ca808b23d591fedf657d3370abe19dff553e7a477b9ff048ec2eb9010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x353b4b1b3a70c5545ba7307395889a4a66beb47cf48f62c93cd1d0e8a5b43696fe8f97829755e86d24316ddef8633e44640caa4d682eed9311787a884f5af50f	1615974303000000	1616579103000000	1679651103000000	1774259103000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	418
\\xe39fcfa87078441d842ce3cdfe5e4e8f284bf8bd5dd2f9621d7b2250ad845cf6516a18fdc31a0d4d0b8cc42feef7d91935a9e985501d8f066771eee6ebc3d92a	\\x00800003c248681e756e402c1de79e5523dc3175a255a03d767922ef2383c6fd9028424234d0f1fc51bf0279ef1434dee1d255874a51a39bf4d6d361e95a08bce873a8313a08b5f1e19652ae71b25e409f5795bc8efda763c1787f83473f4544f2312f5e058158600608318120e752df06b538dafd05910029ee51e855ee519626012007010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x6cec4996b37140528c37b4dd42f3e9f05df9fb6e63e64934f7ade2d737f82a28c1e22c66a5e83ecdeaf0c826c61ba6aeafef31e9785a12e21c5ec4a4be222904	1622623803000000	1623228603000000	1686300603000000	1780908603000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	419
\\xe48fa79afe786ed44e8144bc3790d7135fa1e9f618dfc6589c28352004bb1ab544bcb1004e4c1816e925666bc17912926dc55bfb4b0a7784effbc7a3dc414548	\\x00800003b2b6d7d98e656a7d2c2005f47bd24a21b19e2a3f5d9ac66a019c68b00e5c3ae5f6e6fd45ab985eaecd12f530ba1243df887659e99ca65dcef40ebb5fe8cfda928d3f0a7c03b84fc87bf2ea47a14d747ef5857a8295050c5950cac431e4bc39eb40ae6124c2d4aaf15a5a2824a3c5b2a5ac19c28b1994fb93ae436e6e35567903010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xdcfec06c2fe92214b5b72b4ac9a06c568858a392397dfda8148cc4b6dee1c47574df3e1823bf2815553ed2ae999adeb56bb2f5ad93c27ee32b895e3ddf19100e	1627459803000000	1628064603000000	1691136603000000	1785744603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	420
\\xe7f38110801215a429d30e5c86ec967352b132c1e9d10b04d5733a0673b1d013d0210d73cf99b4a597927171cc458ea96103caf5f3ea0e683302e53fb3343fb4	\\x00800003f112cf161b793a46c2c56d50f868d3947598c71f5ba10350c03736896a6400e5c08b93b1e300b33754c6fdad1afe05899699ccde8ae89cdd93dc6c2c965d3f8059a2b174bf283a25f93d7d61b47f584b6367a4f26594c2a33b2cc39f94352d1bb7832465941adde9cc090120a09da92fda1ac5af678f3b66006b1ba49df24e71010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2aeb33cc53466404ff32b9ede37a554493ba51d431199c9534919ba039a74aae52d1439506bf2627000e9970d60bff85a3add8339d8eab8f43e4d1b66ed5a009	1625041803000000	1625646603000000	1688718603000000	1783326603000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	421
\\xf5ff97d61a0cee7c71c4479f533141461008793743dd3b5f8615e8df131df288b075fb1d8d6ed8562f22787d924eb3e501bb8b936041af2b0e76f9cff7004184	\\x00800003b89bfc2ef31493ce550cdc2cd707f2df70cf3a9982f03d48662ce9853aa5b76cef9865413b84da655dd5f02b8a1b546668d73779413bb89ecc6108f52644c52501d58a3b8334725add53404f5b0f4416f484fe29bb824ac9ecc73623ef6aecc2ae6cec51560b17bf085d057a8980be715a99c5a9a34e3c07a2429d50779cafff010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x7609cf2c656b2a2ef1e596de9324bf41b6b1c29a2c6f0dcb09bac0bab2b45cab2d4ac3020d3b38a5485117d661a9b7b27579dd733c49652d8e9604f581fad806	1628668803000000	1629273603000000	1692345603000000	1786953603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	422
\\xf76fbd57fbf6fd63bdefb34706ec968f30222e0dd3bf3bb03d81a4c9c5aec9574344b1b2a4d120d0b39e33649e0648638410fe13b723ad1ce483488d05eb71d0	\\x00800003b57a100e4fb0edd41296d1d234e7cb3af5a131545bc96c27a4912611763233dbc2855372b7c7eb3b84e6dd77fead45b58ac4ee78720b8c922b8d9d2bb75ac18dba6855bf5eae7af1aa00bbe81f85a8d88c16835a92d0ca9d01cefb710a586d4dc56c92cbdefe120cdabe9f116b0377c89a6d38a07d8496fbd5516b33d4b4d293010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf0758a690e20fb5bb8e9f2158182e5af1741299c0819c8c793e502ee54370ce8e50bfd5d38c2569d50dd293bc7885e1f8c37441c972bd4592a1aaa5b58329602	1617787803000000	1618392603000000	1681464603000000	1776072603000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xfcd3e05f9ef4765cb2ceacc476eae1e301e099594898e022e807493afba74216bee4112365aca60dafc033a0db503612bdd9ab8ef08c733d11fcc0690de99a49	\\x008000039a63cb4cea40175a2e37d1749fa3c044c04c10001891ff1da478327762a4ccd4cec38170bb7ee6880e21a45e5b9eb9506ef1eb19963c3d6c8428b152a49dba8f4da920e006052e344f744aecc5e6856b0389c7ef251c55ec5c84b46692d5e14a528f67a4ccd2cf2759fdb1d879ac45f9033a092d3770d857f644e71ed15c1075010001	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x2f9b943616789f007f97089d9f13ec7c1c59ba331aa2d93986393ad4a062592c5ca48b88e0bb5a756dc6cfa5c5d29e00e63e7029d89352100afa08ba8903850c	1621414803000000	1622019603000000	1685091603000000	1779699603000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	1	\\x3bdcd0e749af9c0a9f863c889bd24929cd9bfc5ba44af2bb6740533f8ecfef5073996642e8d3b1c1e74e37c43e14b4b0099a5afe846bcfab616539e495473f55	\\x0e767dcfac09b5268edf08896a7d338f5e9a1a7c17ad6f720f32e72ea33a63f8b692b99ca49f119e08cf8b2646b1b50475913c231913c78b5f9fec73a7e50830	1609929336000000	1609930235000000	0	98000000	\\x59e58d691e348b6a11de83e9125a6becef3c5e8270983745b25be67a3b8eba62	\\xad1eaf6b3ec0f1a2392ca34dbbfaa74fdd560199eb361cdcb7a20e4e4137ec75	\\xf5b3b0fd3afc471f6993b4cf45763e1c505caf559a64e34307d5095dc49f2f1add2cfdda989fc557e23b9b1d830967dc9693ea192d2cf09e3ac9a2af4b6dff07	\\xb3233a3f9dd681a778ebcf207aced3cfec31bc93582db027c5222c8473f99f31	\\x43cdde610100000060ce7f1b287f000007bf407a51560000998f00e4277f00001a8f00e4277f0000008f00e4277f0000048f00e4277f0000600d00e4277f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x59e58d691e348b6a11de83e9125a6becef3c5e8270983745b25be67a3b8eba62	1	0	1609929335000000	1609929336000000	1609930235000000	1609930235000000	\\xad1eaf6b3ec0f1a2392ca34dbbfaa74fdd560199eb361cdcb7a20e4e4137ec75	\\x3bdcd0e749af9c0a9f863c889bd24929cd9bfc5ba44af2bb6740533f8ecfef5073996642e8d3b1c1e74e37c43e14b4b0099a5afe846bcfab616539e495473f55	\\x0e767dcfac09b5268edf08896a7d338f5e9a1a7c17ad6f720f32e72ea33a63f8b692b99ca49f119e08cf8b2646b1b50475913c231913c78b5f9fec73a7e50830	\\xe8b551a53820be99bab242c71e66aef17e24f9efc23d04bc13edda0c0a97766bd50eee669cf0c774b22761e66c28e3eb66e725480606ced44ff940feb2c13106	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"K0J0RASFJ19HGCSK2RMHV1F3Y9H0BVT999DNPNW5ET87EKAS8HZFVRVF1WRHM4M1PKXB4S7900F2KZ1GE7716Y5FYTCKQAXMM5TZAE0"}	f	f
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
1	contenttypes	0001_initial	2021-01-06 11:35:03.209144+01
2	auth	0001_initial	2021-01-06 11:35:03.249616+01
3	app	0001_initial	2021-01-06 11:35:03.296048+01
4	contenttypes	0002_remove_content_type_name	2021-01-06 11:35:03.322288+01
5	auth	0002_alter_permission_name_max_length	2021-01-06 11:35:03.330461+01
6	auth	0003_alter_user_email_max_length	2021-01-06 11:35:03.337096+01
7	auth	0004_alter_user_username_opts	2021-01-06 11:35:03.343822+01
8	auth	0005_alter_user_last_login_null	2021-01-06 11:35:03.350974+01
9	auth	0006_require_contenttypes_0002	2021-01-06 11:35:03.352595+01
10	auth	0007_alter_validators_add_error_messages	2021-01-06 11:35:03.358024+01
11	auth	0008_alter_user_username_max_length	2021-01-06 11:35:03.371257+01
12	auth	0009_alter_user_last_name_max_length	2021-01-06 11:35:03.378535+01
13	auth	0010_alter_group_name_max_length	2021-01-06 11:35:03.392254+01
14	auth	0011_update_proxy_permissions	2021-01-06 11:35:03.401959+01
15	auth	0012_alter_user_first_name_max_length	2021-01-06 11:35:03.409173+01
16	sessions	0001_initial	2021-01-06 11:35:03.414179+01
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
1	\\xecb40ca2afcd8b3268d7e02f107f0a6ff26608b92c058a82946afdce4fb9286e	\\xd94f68cc3186dc4836b9f85c02719d23aeab55367b1d3a9b133c065c74ba28f254e0f09a878a14c1d1c81cf8fe75bdbea7741024cf7a27a3614def1e3acb6b04	1624443903000000	1631701503000000	1634120703000000
2	\\x8efd8e2f0b0a6e2e6156654861cb23fa26a9fac96b0c8f0f3c0a674ca988c832	\\x0fe25d5e1514362f2b76a11648e55b5011eeedfd8968f1e200d7e0d891d6b773a27fa519d0470cee6d8170487dc8b432bbc803ddddf04c99e2ddce25ac276109	1631701203000000	1638958803000000	1641378003000000
3	\\xb3233a3f9dd681a778ebcf207aced3cfec31bc93582db027c5222c8473f99f31	\\xfb7b4de10c0e939d26b9529469bafec16b2c4f90d0e5a0c1b55243952a8b417d7b0305b81a3a42cf564e6b71e6a35e383d1ee891700701665052288cea165204	1609929303000000	1617186903000000	1619606103000000
4	\\x3446e4a46f7992c2c468b52e424b06632f1f7e6a954b24f842da62bfb7bedd7a	\\xfd3e1c8f89107b3640afb654b79b96fcd82a2b13f56766010018cea5f8fbae953ff717d49ea003d7d70f43a4368f7583f650b78198ce91142d38f2e9ad18ef06	1617186603000000	1624444203000000	1626863403000000
5	\\xba6359624344c210d3ec096a907e66cc0215e566425f2f46bc6766b5d7b6fcc8	\\x15b49c3248456841e0b8837cbc190a9bce737e5547d7b9f1f4b90ac225b38c1a7ee54b4a2e25444772cdc05c66d4d59533d33df78ac8ae5d5592f23c45aa7d03	1638958503000000	1646216103000000	1648635303000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x1e5048774b56e4c575273681f80ae90f3e5e6258ee20c34bbaa9737c9668922a	\\x0d38a964c90917a5b21ff62fd314c1385054864c4f74f096a345ce8c096a3b0456048e975200b6637f9b9e3d6a822beb23bb4fc4eaa45a607ff9eb1638a576ee	\\x40e2062d9a0a0506a0f5f4113f148494b4a6928174254c19ad3fed63c1f54254b66f46daffd145f307cb1839cc7d5883997b5bf07e705305055833b378b3e4da1a13e7dc4a4d85995d64079095c420c61f14bb45376a72f867a41b75e1c9778734b14a3ee966b0718666fec0c346bb56de75723b4a40a7eaccebe7ad87e29f69
2	\\x59e58d691e348b6a11de83e9125a6becef3c5e8270983745b25be67a3b8eba62	\\x8991b5307b4e4537d8c49aaed05c2f12dabe2947aa8806aec8ce8d0d383651a49e86552f3dd738778721abf3e07b0ad3ba6938aa2061ad66260a785f4f4f7d2c	\\xa76833aebc3b49722af4bf8be9822331da863875a87779e298775ffd39aeb14c2f4400799d7b6fd84d7c0fc85e1f1cd60ea868e292eacf2b45b4a5e8736967ad4bcf6faa0779dd64576b317f03c6b5836600eb0d6d5a69767ee15538e12a89417673123ca447e8e11afe399134b3e819096d93284160eec72fc7eb9da7cda573
3	\\x32f41d7026b4a1c8b2f778699655ad6403db9a3dedde6c33505a19439e07036f	\\x76ad44ad39c94061b6669563450457c4cf521ddc0e20ce5aa133e707fecc894737d40f388e761f1ada509d7cb6ef13f308d332bb7487b907899a1e5ed9b0c0d6	\\x42a36902301ca373637e61b55988a7d10a46bbaa1bf9ad245e21b0e51a7241e294c1d0a7b341b586d9dda2be3698b30fba0590114b2550cfef7206944e82de0603d0995c4532c1edaf7780f494416b25846fcef9d4b0630bc5cb86fe035973ca958f655736cb1d12bdff0f5762358e6f47d3815783f13ad6bec388019bf5ae54
4	\\x1d94cd96b9a0e19d89a78568279fab2f187e820baf2b02a45d70bd3eacb8ac86	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x5d801d8493ecf85484d6d8b72b5571588df82194000a03c985230031142092648bc69681614eeb06e637a9ef3c7d299afde37f0bfb98bb35f8d38d2efc915187ddbc39a250180d876d9875f4f5e2155fe5e21d923b70bdaab2601055a57f1640914c422bb17a0e8d81bbe8c4723f84af42525304990b30c196aa514c3872fb55
5	\\x76df0038c2d850f55a766637b794323f05d63d32a3139f41632668465acdd874	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x1c7cdc4d2d912c5eb58e59fbfd47f45b10c762fb0b9875f8658b7f440af11cca98216f23602a10724339045a20f158d3e6ce694da3bd9ec93b6271f099aff0319920966927c86d97133326cc6ca51d07e12c4e38317adf7e40ad59f09cb5a061d0589d9ff5b9e1bde73b5ad173d8b79bbd5054a56e581723e0567c70d2d50fa5
6	\\x8f2727c5fcf60d52c3cf086756f3c737ff578727b386677a91829dd802b7f0ab	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x758a282f4c63dba08c1e50059aa6e6f56987cea75405794b25d7b4134555c562e2b7066f8916c337399189fdc14922a972762ee517f6cae3b6e297a363fde719c87443a0f8060670f9b6206defed288219766ab11a610b27be61dcbf79200b957a462d8a57956e85e0a4b90e1eda0b3982f949a16db1377bcb53cc29cc856463
7	\\x428687f34278b8ded57eb3a7ee7d1cddb241edc86c2a2b59bd3704b5e61ec5f6	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x6aa675b45e059c570bf3574e58d67a630a5e04cd85c09c5d238acfd4fb9a5c30e15eeea23cf45e97feb3878970b4f62311279ccc1c7b1a2d0513a6bfe219daf69743a2ae75f3ec5f3e48b68ca81e755dda84925b82bc8ed7669d5468f30aff8752e92817b26f828a2015e1bb383e6f72e9bfb5c8e93ff2ebb12200d2ad32df9b
8	\\xea2e6741ca715201cc70608afb8debce736451653ae3e530d7cbc58fc203364a	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x194e51e4c266a12a2c68c4f1e96581c970b1b20cabab8b1ec0b19fafe0a88315e6ea38941659487893fc7b5ab325253bf2e7d50a6f3f3de9ecdffab3c6dc2be6e2129bffaa82c377a06a93629f06e15ed00a5329797731c4ab8d9f144210f93e863970443e85eb2c9713b9a9f57ff772eb0c18366dce6c78434e3b7e4b7bec5c
9	\\x8a507dea9821dd64edcdedd7f58905fc5843178a186e044f2cab7a32a6c28a0f	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x3c99428765e93e2761423199e2d6202164ae8f5cdfaf5fb04a08c1aebcf62ad6868c34e62c60c8cdf0b89e2ae720ef449a8052aa6fd88c9bc6c2b5ce9be0ba703983b1f8ea8f4e503cde4d4f7efee9a59ccdded3525f3768e45d15dea7e44a04d056cbc110b97dc3db76507e7f3de857aedc85f369b1c57e6ba53fff4222cee9
10	\\x799790aeecc3ca25e9f9c3317da7dc656dbcdf4a99616d426cdb37a15523626c	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x0f029adb92dcc19050e1a88eca762a61f0db531fab23ba20a849610e6900098351a6d4db9571fa1f7e87bae7dcc371e140021b6f8afdc2c9ce04b5895e9ba877a2fddb4810fda19c25b595628c889ebbe2611daedee7a6932641d8b00181fffadb9f2938944451beccee0f34e0d190124da4975f989684bba6f9ab93813b0120
11	\\xb9703fd4637e393bec6b1876a200d27b8a81b929b55419cd4a4da4dbb48244b3	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\xad1453611ecf30671e7b3d1d206df7690d0bb2d747ff66eb5c059ee2584bf140bf11e07568f2ae7dde2cc1315b0eed91a87ce7a56fb9cfcb44cdf17a017152568c0d8ce8793aed344398939df7405c7eb8869453e488a7002ade4a1a0a28bc09e5a812047d205a2cf03e7bc4c832cf0be3f91cc1408de645d0dac564e6d9d8b0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x0e767dcfac09b5268edf08896a7d338f5e9a1a7c17ad6f720f32e72ea33a63f8b692b99ca49f119e08cf8b2646b1b50475913c231913c78b5f9fec73a7e50830	\\x98240c2b2f905318333316291d85e3f26205ef494a5b5b57857690774d59447efde36f0f311a1281b4fab264e9001e29fc3071ce1378aff6993babb4a175f538	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.006-00WB4DQK39CSP	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630393933303233353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630393933303233353030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2231535637564b58433136544a4433505a313234504d5a394b485846394d364b57325950505957474636424b4a583853544346574244344e534b4a4a39593443593133375250394a365036544738584348374748484a345937484446535a56334b4d5a4a47474330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030362d303057423444514b3339435350222c2274696d657374616d70223a7b22745f6d73223a313630393932393333353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630393933323933353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245454a4e3336303937505648325148544e54423237544b4d36545259415831343842565a4d48415259315948524734575a335447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e4d46415954535952335254344539434d44365651594e37395a454e4330435358435631535135514d3837345747395158485447222c226e6f6e6365223a224d474d41465242393938473641305a5058563131395a5a394d4a56474358364d54334d32453833354b4743533738323039503747227d	\\x3bdcd0e749af9c0a9f863c889bd24929cd9bfc5ba44af2bb6740533f8ecfef5073996642e8d3b1c1e74e37c43e14b4b0099a5afe846bcfab616539e495473f55	1609929335000000	1609932935000000	1609930235000000	t	f	taler://fulfillment-success/thank+you	
2	1	2021.006-027EW77E8SVGW	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630393933303235313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630393933303235313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2231535637564b58433136544a4433505a313234504d5a394b485846394d364b57325950505957474636424b4a583853544346574244344e534b4a4a39593443593133375250394a365036544738584348374748484a345937484446535a56334b4d5a4a47474330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030362d30323745573737453853564757222c2274696d657374616d70223a7b22745f6d73223a313630393932393335313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630393933323935313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245454a4e3336303937505648325148544e54423237544b4d36545259415831343842565a4d48415259315948524734575a335447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e4d46415954535952335254344539434d44365651594e37395a454e4330435358435631535135514d3837345747395158485447222c226e6f6e6365223a224536445357314d52483552544b42324359504a345654373032544239365037325a4845444730305a4e365038535250444a594230227d	\\x3abed86095bc32769b501938ea02533a42605cacb43208ed124623936969a276f22f35a1a3072b4b4f4b6e571f21eb0f47b30086f3c86ed58eb31016e160da9c	1609929351000000	1609932951000000	1609930251000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1609929336000000	\\x59e58d691e348b6a11de83e9125a6becef3c5e8270983745b25be67a3b8eba62	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	3	\\xf5b3b0fd3afc471f6993b4cf45763e1c505caf559a64e34307d5095dc49f2f1add2cfdda989fc557e23b9b1d830967dc9693ea192d2cf09e3ac9a2af4b6dff07	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xecb40ca2afcd8b3268d7e02f107f0a6ff26608b92c058a82946afdce4fb9286e	1624443903000000	1631701503000000	1634120703000000	\\xd94f68cc3186dc4836b9f85c02719d23aeab55367b1d3a9b133c065c74ba28f254e0f09a878a14c1d1c81cf8fe75bdbea7741024cf7a27a3614def1e3acb6b04
2	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x8efd8e2f0b0a6e2e6156654861cb23fa26a9fac96b0c8f0f3c0a674ca988c832	1631701203000000	1638958803000000	1641378003000000	\\x0fe25d5e1514362f2b76a11648e55b5011eeedfd8968f1e200d7e0d891d6b773a27fa519d0470cee6d8170487dc8b432bbc803ddddf04c99e2ddce25ac276109
3	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xb3233a3f9dd681a778ebcf207aced3cfec31bc93582db027c5222c8473f99f31	1609929303000000	1617186903000000	1619606103000000	\\xfb7b4de10c0e939d26b9529469bafec16b2c4f90d0e5a0c1b55243952a8b417d7b0305b81a3a42cf564e6b71e6a35e383d1ee891700701665052288cea165204
4	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\x3446e4a46f7992c2c468b52e424b06632f1f7e6a954b24f842da62bfb7bedd7a	1617186603000000	1624444203000000	1626863403000000	\\xfd3e1c8f89107b3640afb654b79b96fcd82a2b13f56766010018cea5f8fbae953ff717d49ea003d7d70f43a4368f7583f650b78198ce91142d38f2e9ad18ef06
5	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xba6359624344c210d3ec096a907e66cc0215e566425f2f46bc6766b5d7b6fcc8	1638958503000000	1646216103000000	1648635303000000	\\x15b49c3248456841e0b8837cbc190a9bce737e5547d7b9f1f4b90ac225b38c1a7ee54b4a2e25444772cdc05c66d4d59533d33df78ac8ae5d5592f23c45aa7d03
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x73a55198093db7115e3aae9623ea7436b1e5742442f7fa4558f07d1c409cf8f5	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609455600000000	1640991600000000	0	1000000	0	1000000	\\xc0918c6acffff8c5760ee8ed5a4a457339742a951d10519120287bc2db5bd9468589d2da6af00d536f35d2f2f4d5f96ce5fc9f0e4d7d1c3bc0a2c0513f277207
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xad1eaf6b3ec0f1a2392ca34dbbfaa74fdd560199eb361cdcb7a20e4e4137ec75	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x24eb4810c75569064d2597a906902e403a753cb7dbe45a36450508d47d9b6d44	1
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
2	1	2021.006-027EW77E8SVGW	\\x5871e1115bbb5ff41c59a1d06a2bcff9	\\x72a6dfff1f8171b6802280264b06ac2288f33695517e4fee62aa29768372b0b34f9fc24ebe414216172b4347218de8751eb0aba1dccd7d98b615181006ee2b57	1609932951000000	1609929351000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630393933303235313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630393933303235313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2231535637564b58433136544a4433505a313234504d5a394b485846394d364b57325950505957474636424b4a583853544346574244344e534b4a4a39593443593133375250394a365036544738584348374748484a345937484446535a56334b4d5a4a47474330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030362d30323745573737453853564757222c2274696d657374616d70223a7b22745f6d73223a313630393932393335313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630393933323935313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2245454a4e3336303937505648325148544e54423237544b4d36545259415831343842565a4d48415259315948524734575a335447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e4d46415954535952335254344539434d44365651594e37395a454e4330435358435631535135514d3837345747395158485447227d
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
1	\\x1e5048774b56e4c575273681f80ae90f3e5e6258ee20c34bbaa9737c9668922a	\\xb58249fef2aac1cf0eddb7055fadebb35335cead20cd55fb44f29e913a30574b8a05cd0af7eb0cb0434fd2591cfff857e9498223a66c4cb4cff0353d4d6d800b	\\x693f470f39f8a3f4fb51c591e04bbf2a6b7c1c71e330c0b6818c6b0e1d25e951	2	0	1609929334000000	\\x009a9011c33dd2abaebaca777b2b187c784038d66f98cea211379aa36479a34ca9f29efdb16a6bab430ceb7dc78e7e6f53cc540c6c417093f90ca9d55bcef3f8
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x1d94cd96b9a0e19d89a78568279fab2f187e820baf2b02a45d70bd3eacb8ac86	\\x5f790e7a80a4f28f097cb462d4c12a0479d0cc211cedceb2602fc050e52cb36a8fe0036a99e2790478713ff2ae1e3be0017fa5dd2691f53f010d0a8ec4541303	\\x33ff88a71240fd3c3f6ed048e178a4f155ba9564a143d9e788a8b3031b3e44ec	0	10000000	1610534147000000	\\x7511d0296520cbf892e987a7a171770a525b9aedbb656885d954ce2d94247d0ccce3e69db037ad9215a5eea0f78b47c09df1eae481ad6e685ded3ec7f6940f58
2	\\x76df0038c2d850f55a766637b794323f05d63d32a3139f41632668465acdd874	\\x0aed55a509408eeb6018a84da71dbb4c1701cc0173fd1787d5aecc162a2fbab591a2d38a11ac0cfd2cf047b5ee51f111825b8e6c17b168711a947be3521a2f09	\\x355a8bfd51b3b6eafb87bd9038eac37134bbf4fc0f97660770f04b1d2058d3cc	0	10000000	1610534147000000	\\xf5432015f008723c06975f262e94ba65162f0ab3866a17b5a22fa594b01f52f6f393ad7a4c3b12930a9595a174dd213d1b0902789a72376434a6fffc0fe6d650
3	\\x8f2727c5fcf60d52c3cf086756f3c737ff578727b386677a91829dd802b7f0ab	\\x8de520101895684988b54fb56a5ffb372e6873a9f8afc796d95b02219836c94455ce8e0c53894401b8b989a446dd504bed5ac752ae57d90ddcfca74baa25eb09	\\x4d5770a7e74420b093adfeabdb5f44572b4a20dd9331fdc28c2680d796b1b735	0	10000000	1610534147000000	\\x2608773963b17464d81a0a4bd2e2c8ab566b29dab4632768232785da16e6ffc7aa26642d3f9fc84ff745f25b88b8c22a4a5cb0f3c5205df34e9c62010d66f99b
4	\\x428687f34278b8ded57eb3a7ee7d1cddb241edc86c2a2b59bd3704b5e61ec5f6	\\x4e1b5429c61ecea1ffd0df5241218ffc6b06ecf243519068c22413833b4c4ebdd57c04e8af867fdad72bf8768bb861bc3bd4e9d396c271eadf86fc5859a20901	\\x3649352677dacdcf3636693855da4c9d2c8036b55396d474213fe8ae770e9f2f	0	10000000	1610534147000000	\\x6ac0d894af9bef3d474d76f5a1e1bca47d0215275203bf5ad962bb62815f55ee74964bb131d3db8f96cda7aff5e53b0115bd267cd1099ee4f41a3d4f6324f9a5
5	\\xea2e6741ca715201cc70608afb8debce736451653ae3e530d7cbc58fc203364a	\\x550dd06fddda9cb4e8fbd6d9da61920c5580fb3938efbc882754600bfa01875cdd0cbbd485ddc3cc45a8ecf859260809fb136caafe542efbedc6b1c03423650c	\\x8e73f47fdc561684174ca18fdd867b60126b76a5e26aacc6f17ca87b4456942a	0	10000000	1610534147000000	\\xe0a1c6f72309f00696efb9b73573b31cdb944bbb3689cf874bee5e990c927feeb3e37fa3a614ea059b9bbdd5f90df851f2fee13cfe2aee7d11f4d60842b8e1b0
6	\\x8a507dea9821dd64edcdedd7f58905fc5843178a186e044f2cab7a32a6c28a0f	\\xaa1c798657858842351ad0900b7ae078fd4fc312ff955718507f81e9d853956e3c404c5a35569fb054f92bff37677e896316edfefed7d51bbf83f10be5eb1b0a	\\xdde99206efee56f1feb4577b77b5242defc13156f8f4c34b4a08aeacbee55ed0	0	10000000	1610534147000000	\\x08aa95b3451065e6704fb0722ad13663a53c8b74b1afd8778064f2ceda36d4eb60f0a01a7ad63b17c155700eac09f7538e597785839461425ea72340d11fc4fa
7	\\x799790aeecc3ca25e9f9c3317da7dc656dbcdf4a99616d426cdb37a15523626c	\\xbff353a4b6106b004bd7f47d682be4d33b3f4563d56f12f1adbcab6508cf6b627bedb2d41d41c30a06cd7181599e618073d68da6f90aa4fa1ee3512966ea2e01	\\x16b71e7fadb895b22442b124387bc0ac9554c139683b14b6668c520123252181	0	10000000	1610534147000000	\\x70e3e8ce03ababb3001c8191b58fce302afe01fce788a3a959806bf704a242d470cf04a4d2145aaedcff8e57c73c7a636285b19c43370126ca0eeb2b6779f218
8	\\xb9703fd4637e393bec6b1876a200d27b8a81b929b55419cd4a4da4dbb48244b3	\\x1285633c7d78f68be36818988b2e39aae249f1d0b0b84332f22184e8971a2d5913fc4d17cc3d8c856b4faac470fd5f4b4ecda8f55a984cd6647cd510d94bfb0d	\\xcf5f043595bd624dbccfd2209dc3692862b1ed6af95b87ac6d5460e81cc65a32	0	10000000	1610534147000000	\\xd2c8d7e3cfec4c6c0e8a3018340286624edaa5cac413df065797752d26eb7e696d9267ab58335376a3256c6efa336cfe0fb9d2918814c34d2373b0d646f5782e
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	\\x32f41d7026b4a1c8b2f778699655ad6403db9a3dedde6c33505a19439e07036f	\\x7f42a03a780a3437a9eff6e291dec118ade460ed8f933e0126b515484ac5f74141f539fc5f070636e63132a09c2c049115b3f56514ab3441262ef076869fd50f	5	0	2
2	\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	\\x32f41d7026b4a1c8b2f778699655ad6403db9a3dedde6c33505a19439e07036f	\\x59d949cdef1140a1df301afdd68c62e1ab1cf6c21d6284310530721fdb241b24036f1a775eb2694467dbd265263a1f74014e737423a702c939b30fba01ab880b	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig, rrc_serial) FROM stdin;
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	0	\\xd94622d3e9133570086339b22c6bc64e5af8907b096e594bd727d773c55d90382cae2f7a544d5f4ba41d3cc4cd8e98520865d81d017d2c6b65993e0a6f5e5607	\\x778d39fc4a1a7202f5212a3e8b336d70c1532b0c730aa778064ed2def124ef8e3d346513fa8d4b40df906c86371db52fe33aaabe969d5088afd3c3381cfe1d0c	\\x059d74c6d3ec94e91cdeff72a61b4b7b31b72fdbbf21b50100896deb197c898c1bf444f5fe898c2c2958b16090f9a0763cd8c8eb229c721f6987c80719d6b374fae33639f6fae2bedb4aae85ca9cce57fb9cca08cfe434a1d93f63948b7e05b66c555b41fdfbe0fb52d6870cf5d1cf01a1cf1200b5526d4e473156e5c6925db3	\\x567c993af2a9f0333281b4a58ec39f4861ebf65e69c08f9b65bf759f69a8c46931a051d604f9e94c03573316d9a3067d21fff6c05fc6b0470e36652c2051cc50	\\x41672e51f8ff27aeccd4527da86106abaf96ce916559ea3df1089184156dce6ea3091cd4c6b4eb40cc81b846c2365ffda96f5aa02bdae6aaf56c4817bf7e4820d4606203ac5c302777f91d60d19923112c334abb7f6302a850447d3f7df78ce0ed88044f0ba01e1d2c9591cfa566c60726e49c29d117538a7701e05778c3e6a8	1
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	1	\\x52bfb4f3ee8ec9a1e56c7b6ff32b7021dae8961cc4ad24f3f3f5a62d60e7a243b0c3a71d440639e7b9a9d484e83f793a2591e2fcc5e4ee899756decdc6a1f609	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x86baa7740b24c8185a1f22334e6a9010e431143b56906c249dda17fbf720e7b03515402c680628cdd94dc5f3ac66521eb0ecef87d314abe25d43205048b97477d6d949eca291f483fe443a99547dc2ef6fb6d6d333b3e95244c0164ac322abb080f52ccbbcd26835630caa3c280c4dde4ed9f3c9294a79fbd105ed6684c38670	\\xf5432015f008723c06975f262e94ba65162f0ab3866a17b5a22fa594b01f52f6f393ad7a4c3b12930a9595a174dd213d1b0902789a72376434a6fffc0fe6d650	\\x011e935a1f4ab9b227390793966ed72fa6c4743ac04bd73ccc3b66a7ac788f7e551bdae4a4c2dffa2ec03d0ad051ea51caa9ce7e3b4555072ff7b3f2886a6bb8dba1a234fc5902d614886aaf0314c7a43b1c01b0c62c8c4284b2f1b3eb036f87bf289bc06f0b3e323fd279bec1a63274a8c43df7c7ae7dad6050c54a1a29b2f9	2
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	2	\\x54e2ba036a15a27f3be7b8867fc144276c6c21efb4d39aec53aab2278f67392702d74a51d957daa5cbcce6174d94c081fd754d42d667f1a52137af623c5dc601	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\xa55e3a90c5aa6fdfce8115b504cfdfc2810aee43f49529a9ba8ad6165508284b98e068ca2b44cf714909dba07a36a808adc9dfe5589c1d939be68d5e7ca4b1ca9dc45801a99e3e7b7abe6e51d54d06c17fffb6d412506302a74bd6100f2245c2517200ba562f49f5c3ae607fddb6e3f47af251092fe7ad94e5964fb3fff506f7	\\xe0a1c6f72309f00696efb9b73573b31cdb944bbb3689cf874bee5e990c927feeb3e37fa3a614ea059b9bbdd5f90df851f2fee13cfe2aee7d11f4d60842b8e1b0	\\x23242e7b1e16f766e4f5c9029f1752870768d6fdc0670358e070a78346ed45ea1a365c6b7ad529077a309e324ca095620a30a8aeae6d6b22e20d69e948391ea795321af1eb54c805d70ca949e5bcfa735d7fb9dbc7e4608011a7e935bca231f30a4c8389f9973c8b0aa700b0c7ec74b934b7541960da1ee934afffb68427f3e9	3
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	3	\\xdbe85cb0b09c3f6d0e25724bcfd81134eafe97da47b8d5edc96d3911d4d50088ab4c172bd6e1e6e4203dd24ef24b5a431df831d0bef76059012b3e618853a406	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\xb8fe8b71de4a654def3a94d10656413e641b05eb00265ed86f42f2439b46a695274bda3d8c54592120ab6114a948bd1aca5509432deab5e299ca767e92c4b7116a082a5c391b65d8ef31f72436aa2960dd5ae29a71d8f3c1d8bfb2390f03cca405b83b17c8c372714db3008c92ce8fb3e9d56140f923a545c5e0865dc3213ef2	\\x2608773963b17464d81a0a4bd2e2c8ab566b29dab4632768232785da16e6ffc7aa26642d3f9fc84ff745f25b88b8c22a4a5cb0f3c5205df34e9c62010d66f99b	\\x08f5cac10f40e8829e10023f5fe3268af0b20e8bc49983cac5c787ed4f139c47ad3e9e0b98f715d36ace6431d7a28d4a83a52b73e634cfe6f3a7e993232bc414698f16df17811afc1f94aabe91fb80e97fc99cdc8cb10d958b02bd8fdefaa60926158ce48f88372dcd1537d0abe695c4579c6d2c445390b8f704225c4cfffa61	4
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	4	\\xdd9fb7072750bb4dee6faeadb8dd5d0e3dc120c6b7a785ad6511c6b9b23e35d0b955182d59a93bf7a2177bd7d9cb132f4d2e8afa59666295ad14ef3eab2f8d0b	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x2b95fea98228d88a73fb907d664a4b47ef67cde23fb3d57db534c478420b52baae2de6587af6c8166ccc50be4f8c89ad87dbb8ca9437fb6bd0bad21fc12525d124124b2446a72bdce1e9ab8532238456cd62c29faf0442783bd62f704523eba95083b27c2898704ad7528660d7a09b8c8eddaa7d5c175cd77dc132af7e9ce67e	\\x08aa95b3451065e6704fb0722ad13663a53c8b74b1afd8778064f2ceda36d4eb60f0a01a7ad63b17c155700eac09f7538e597785839461425ea72340d11fc4fa	\\x679997be260abcf7eb2ec241bc3c7877128205bf190b0ca77c3274e4322a7268949511570f340d0439f143160fddfb98195565b7a196aedb7f1ffa5c871ddf63835978044f778aa2261c5f29b8ee1da3b1c93c7b37478d2b8fd016aefa77a6bf12096333c1fd6c92f185c8d494e4b9e121e5e0f0b041004ebb763807040d0aaf	5
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	5	\\x1937c74bced43e6a394011da82d9caf41b1e3d72b09f548891c03def0c5788bdcd472df07e65d25c7a701ec5632cce54fcbfd3dc5498dac7c0267b68db493a07	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x39258549208f533ccb5fc9c35f42bb7f3d4deb7b00a0a97272060c79faa34d1a0d892ca746a1513faa024ec911506af2e44a309f76db707816416d033e524d9bb239e5ea17afc29a4bd0f837fd39053a51371a47aa640254b6322844e8340b1b4fb84e1ca3a3133621c3041ec5dbb7f6ce041f6aff087a883fca26935aab0426	\\x70e3e8ce03ababb3001c8191b58fce302afe01fce788a3a959806bf704a242d470cf04a4d2145aaedcff8e57c73c7a636285b19c43370126ca0eeb2b6779f218	\\x03645284ad08b927ea53f2655cea586e639b0bfbaf3abb86e02d2719f9986413c34754aa0a1cd7b68c4f0835c973f48d27b5e0f3218c0b62708a03e44e6cfeb853d6c169cb9b0d1d9c610ea85d069b77086bc79b9a713b7f0f7e87555921c90b29910a665979017eb42bf58afab4b7adce3350f17266990b5549ff163ac8bfe9	6
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	6	\\x6f42993a1e2e66c66402956574d834f8d70e75e1bbedf088e8ae409da00864f4bb825be140b3b9f82b981f46599055b12b748a5f87163d7950213bc041c46100	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x9550b6f8f95b47892324932831bd2956b0c2de9d1c44090a93ff1f1eac03db7440a50e44f1a1f08279843fb8d69e0c86f286af8dd420ae33545f41235367bf1fdea376579d39149cb0f6c8c8f90f579e01248ddc571793579a429e331c43ab70d15195ccc7a6422cd3ae644d3b46d19b0c61ff58d08b35fdc8b7a2a03362a799	\\x6ac0d894af9bef3d474d76f5a1e1bca47d0215275203bf5ad962bb62815f55ee74964bb131d3db8f96cda7aff5e53b0115bd267cd1099ee4f41a3d4f6324f9a5	\\x6cd5261e4ca2fdda5c5f1c841490a2129f8452fd19494a0f570862ae99ad08005521e573e0a006e993271d7e9918671fbbf1917f938dcf120d285557567d9fc2ed0ef50ae1607261b09ea4898a228b123e096d439506138e98137e57eeb1fcd02ec0b952cdf5826b9dc57b4b057ea5b4491edd4353919f98f1c5aaf5aad6a09d	7
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	7	\\x752a12354cd43fcede3ba76d1652480d05031241059f943986f88850a2e1d15b41d07f8fe7e25ff72209ad1891133be5d1b942f3f4293594c221e83d9dd79901	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x70cb3ca0bf4f57fb385c14ae4ad631660f200ed5413144d507e99b5d76513357a35d12c6e509947c2bcfae3361ade9294f264fab65877bbf7c2f31b4b9246dc46a7842ebed7c0566c6e3997bee17f03935af5fdeb96804e2f25188c4522b02ad3fda0f99e65c04754d7d9ce6778a265cb5fc6632973056c12f10b4428bdb5258	\\x7511d0296520cbf892e987a7a171770a525b9aedbb656885d954ce2d94247d0ccce3e69db037ad9215a5eea0f78b47c09df1eae481ad6e685ded3ec7f6940f58	\\x099d35f0bd94d58303f1f6b7e393f04fdaf067abd0505af653a0ba53f897048bc6cb69eae2c9a3ac4a383729860c93858d20c77ddad9f7bf4477d9dc2ad8e06e2cb9485759dd02de4f436eaed56c5a6bd2a71fffdd6b540dd280bbbd4e2f5ff128a365da29a1533e4364c19f769ceaee04e4ac582c182a7142ead0d71852b8b9	8
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	8	\\x28d7b8a822e81fd90f6bced08ed8856526efe5b7eda3e69c61719510bdb248c3abbf52af226171729ce3e4d5bfc1b67f352322aa851ec9d42412eb4cf4c83609	\\x393f695255a87e483767d5278d5a92865ad8e23fc47da92e808ccafe17a0b2d30438e07baf164e1bf5f4b0b8f7903d2a00024ef305e18a5c064ae7eb9fd5526e	\\x25cacb74afad485309c3162a1bd49ae943f5b240c376f9809e192c6428b80705fc8d6aec01a825e73818307466e20e9f700ab9911ab7ac152c8055314e6fa2aab495631ddab948d81a88750f2a4f30481a2721f79d5ce2dd339bfbd751633fc067cd5b426aa9567b8c6194920ec64d482f3c814c038b26a67aee92067e8aeb59	\\xd2c8d7e3cfec4c6c0e8a3018340286624edaa5cac413df065797752d26eb7e696d9267ab58335376a3256c6efa336cfe0fb9d2918814c34d2373b0d646f5782e	\\xb1a8abe4292baa17c0df8868f091e10a872183d8c7edcfa9112ed06fbacf1d5ba3e6c92a44aa99a2df368cce739fde860ba9422a21de445f11f50313f1e72dcc42da34e6e14173ffaa2f0a95ee5a8e550708b6c0e4e382311371d6e1aa1dabac3d1eff474819f56f9ecd4bf0159d80d36eaf75e532995660737ed40d2484ec62	9
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	9	\\x7145a87a540ca79370bd4eeac072fd7590389a010ab6e1f13f7c562eadf50973666cd3b61dbce82244e003c34adfce26de566365d4dcb09d28869cbde7fe900c	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x618ce1900a142ce3fd98ab894719b195dffb2b64be77fb60e11ee1effd31e797026e7cecbc18501c2e7bf875e130e81b1488a28cbf92e8251bdd236d19172b2950e8b922e9505f8fbdd68771ebe88e9805015c49ac0a3caff621c0b8419fae9103953cdaebc07b4b4ceb15bfde4c99d1c10ab6ca1877f9e44ecbb6f1883c6e0d	\\xf693105c025cfda5a8f9e65995582ce3b477435d698522d63ef3b085ed3d1dc32ce1a9b90e873449348afa82d11994f184bae46fa134d1b00e11c96a6042eefd	\\x6e3799700bf5d29cfb9094ffb70fe7e867f8985859ecc061f02b3add9be3c0a04973ecc3a1b91946a92a6912d3364a9f9c02997f1f814f962894d2f474b4ca99f96c9c9c3292ff8268dc379adcd323dac278124b18117d17357ba8497c6e00773067568dfac0e70fba017ffd6785cac0fb836c834ff295f5a8b2c4dd96e40838	10
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	10	\\x907256d352035f12c0b55a6ce42748a8b5dd5014a8e1af8706eba0d09cb43ec10cd63b00afcbe83db89edbbd84cdb2076bf4f2916b5bf5da142b5da582321207	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xb506b3ac6a0a2004b6b0ec7a394c1abbcd4ffac86982c924d3ace89b2bf7b9e8c564c1ef950d19e43eb36756ac8da3668178f86bf0e467a6d73d627d543baec49a027e2cbb64833bbeccfd9241e53fc5bbd1ca80104de3957221c17849bb399292b3f0995f10d0ef8caa01d375c1cce281fb7ab45faed3a845eeec65a51bb8d7	\\x9d36f710c8a8c32dc7e52ce4093e02beed4f36f3d10a5fda716b2e841544f0b8e3dcbda0480a51c8a97a7fbafed47f25de083e0066272db4a007decb9c0757c4	\\x27fa43194aefb4523a499b4206d8bda540f72d9ca4dedd993b335dfd195c8d3f21e48122c700676628e33edde73f5eb58415e618d8522cdb02acce07b50790cd7776c0560db6b366eab5b6ccccc149d2a91bd9dda3fa90616507ee59a5096ad8b6172ea21910b6bd1c4153225968c7abc053781cfd27158d7e3b95321cec31a5	11
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	11	\\xc623abd3f48a93a2e7e760753c2f9138f6e253ea9f27989110de6f26015ac2e63db79074eb9cd083985d6d3801eeef1d8d825484a9cafa195fc0a76069a21b0f	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x44d200ac4d5d15d74f32b7bec9ef4a494539fc16638d174c35b1c62e5a9b0da8b5ec8a4b7f49f3d3dcd7e6f799d60de77ac5db3d3e3b73faa3f00667db3db2b8b80b15ff44e4816096fa33bb4728942154b52eaf09c117ded12e1c44378389fbced6553aa2173dad290c9b8f3fa45ad1dda43e542b2e8bdd06f9da6be98a5dc3	\\xa3d20e6c7f8a70f999acd5da659920b62e8758b28dec14d90d1e52d737f53b4e716deb48e1abc2f37f90435436e72448f716a1c8fba7456104e7f75f26a4e187	\\x7c1898f8f11e9aefd223275395b17c529d605f4a3dd03392cd357099653906feefccbc0c196675036cc72b93713b0fe281e53f370fb0e149a490ba743b9eaa25d0780867b335488c451c1d5a3db317f63a87082dc0a1ed141361b5ab690668595147bf727e9ae5d27a6d6cbf420b7e980ffec4586ae87b48931f1fa00f9457f1	12
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	0	\\x5fb6333a60aa35c601ee5c706944878312b35c8482600b8d17204823f43372f27f8162a245f86ab15fc611a71b77d8620f4d686b75edd62dcc2160ebacb46608	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x11425c07fb6364cbe12cbbab43c2d51259c7b8d95a84df0876581546d7dfad16e5f3d394994948651da771caa4c84af64706f8916164711d208cc3f0e5fbe1b1c6fe5fc0fa6c80c65bc7efd26a43e38b1da46eb1a69df1e6f32d2249388cc65f8628e2502a2203cf09f0d4606a4a1abdec1a2afaa586dc08f05c2937290802e1	\\x353a15ce80711a2b5aa6227246fa6a57dfaabff6152c8943fb05e9536710bda27d96d5acde5b9752aaaff1ae304b8a2b58604b22388358b7c18fe90d9c029517	\\xc96bd0b4b7bfbd10166d3c678fb15fb4b0347d6a216cbb75d580de34e9b982f13245aae7ce0617f24bf5b90cd607d4f0d802e881d981a697191736d54e8eaf8992b07029cc52177f3e48b33a10efb9c6e1946bc92510ac9a4089169c525526db118afd8b3c1eb85cbedcd9b2887238f0281bd1f76a54d93b8e71b97de8d30f57	13
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	1	\\x7375f7af32685f77c4c39ccc117ee92562dd68aba0c8c2d4b9d48fe5d367976b08ad049987453f9f01ee7371936df28f0fc412728f09e5d4a31528059378e20f	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x3c130150cff030c014a81bb9558c8c2d1f5a94c3fad3b6a7c18a3ee0ad1af3a86503249177a8bbf4817f2ca7917af0e1bbca6bff1dffdfbf2c501a6d6ea9211d3827f32650b123b747bd9abc64675fff2348dc4b8370c371b337becbb24d6fee943a31a4b984852baca4f39725ffdc817dc5ef629716d5df461ac57d4378c0fc	\\x49d6aabdb0f75c9cbf938a7239872871fe3c3a3879ac4212bd568821d8748170e3f7416b81670badc9ed7eca2baf704fb5e1e02dce8a27fbe317071103313ecf	\\x9bf14279056b4e375efa64f2ecdb2b11d37010a0fcaa3daffa04bf686ec42919bd4b43f086b69385824ae07539165fb727febc31a7c9163995a928d0da9cd43df07f9c197ed415bdfedc00339fb6c4c632070ac2f57ac68f10dcc34a1a74d61c12bc332b841d46a1f59f7edd7518025b89e169e03c688290a6db19ff847470e0	14
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	2	\\xccb2f3cd59a8cfcc6ccf20d52cdcad4ee108f6ab7b5e4f1bc8a7717291400b628bcbfffcecfe081ff62fe42ce06669a1e70a34813c069106eb738c1d380e090a	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xa82e5aec3e30f4f273a604cc0bb7d99e80dfdb6abb9f7069eaffa29792dbdbf61da5fe217b1194a776a5a89314af285019ac59269dd6cfa098636d247447c5d3d31fc7eb858c58db9733f0b58d36479a63800f775fe333ee9f08c46b10d8c1b53ab0097c62d53a0f83491950b2ed078ba82c902b8e27622fc84367642e8cd2ad	\\x6771b3e794c0c50502203008dafe83e1451fae971209890a2e6f29e7c67c10fc78efc02e768cf324bd461746437e38a8aff0f54504f27fbd7844b32dab6d9a66	\\x2bd75783bdff5718d2da41bedd1cb25859f34c488095dd93870a58df3b1730e9f4846f8cda2967fd8f0df358b3798d8a03e403bcf6a78fb8f4e5ecfcdb2f7af95187864a1ed9e2417b7d9fd1b1716a17f15c005baff9f83dee7d9ee7c3d206431518adb0e4c95cb749f09dc1039c067b9f0200b16f1add2bc815474e79c78708	15
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	3	\\xc2b77155edb5f24af8dcf4dc4649c1c6334d2fa3f9e88aa8f54f52f0373a8df068cc29ae8d5fc32386c62171bd004f65985b9ae38fa73d221cd5bf93263c5504	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xcbbaa40f98d98aacca78253e2649e4867d20eb08ebc800c78464410dac9c678a76e3de0fa17fc73f0263e515b8d46df80741a402002e59e88064ff63f70ee33f4361241ba7a5384fcfa3d7811a2823c3b802aad624ab84d83203f6c5dfd6a89e11f239d15f445101d7106e563ee036c7b66a43ffb8140d67852e85979fe0c8b4	\\xaa12e753edad6aac7313128450f1123ea4bcf756e8dc73ee399a061ac41a59eebf0e8901e30c23bd67ee91c2dab27e8026f4a5affe4572186ad69753065ad53d	\\x61905fc02f46b95b717dd3c4d7970ce1389bf04a26dd6be9213a5bf0350642ce2735fd86d718ac8b35dc7b17e11aed65195f14bbcca5910dab118ab6e1dbc0dd0c49253b9397ff764851355f31fa1e74b94ca48340f4e50d42e1f404ada7f7d889862f4548559ef9acd64d5919b29cd8d4b042f24b4441f75ba1752325da382f	16
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	4	\\xdf2a0c8ba3899c45ceda7b6e75b8d14b87a317689aa26b38ea0848c53ac62f7cf52ea7a4c2e0e846b034103494e9670e9e594cdc1dbe0ba5b7475eae62111c04	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xc4df4b3fbc1c9ecfc4aa7653933c8e40d6968c6ad27a3380838ea799b8cc1456c76d2f92ad5b24003493f3a2a211db58be21f8225160decc1fd220e3e5290a56b9046f4945a69a19bf786543f5f2b2f5a3373d2346007e8bb280bdc477cb4cce3e629140b715580ccc16dc92ccefab6fec630f1869086af0eac3e29049f78c76	\\xa30f9f6750ab419002f08768c4cb2820204c2a15c49d07d66833e76f479f0b9e1f2c14bf21c134846e901db5b021323afaceecf0709cae12c5c0c3eeece9980a	\\x84b304211eb51feeca67036a6fc84e50123c3b9e78cc7ad54374d89abdcb619bdad1ddc25e5d2ef1f3f16ed5587235c4dd1a9e9348338c9226feb82aa3595843f437b1823cce38509060c43970c2db6cd6ba7b10dee69cd3451e0ac42825afd409a341f3f134918f2578d2ec770921f9bb8880836d1ed2e704bf45f6834361b1	17
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	5	\\x1de1b5272f2e8cec6a5b971418a183a21b03f2fa1da511b6ed2b5bc8f200508fa70208ffa939499af0e070e771ce32438de6e8a1f620433a2315627642a48603	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x1d7463d83622da4c6655d9f84b6d61bb2446393ea5376b652de2840cc16429a998da8e7c33ae386f09590e20b38eed012d14c3075bf66e235ae066e2900cf5850d14e69f65db863a919c4043578a3b7edf4d9f47d29d1130d72e1427024f428873d8c79bd9dda9c341848f39d1391baff5d1b44383887d36607524c2e6a9276a	\\x6a4e39119f5230695e7aa90ecd4696c2479f66265a7f66987bd5939d5804e924ad342935080bf433a9d3b7c380c86834792aee1a27189709baba94448cbe91a0	\\xaa86064d95410352f316e082d9367a141b6ad12b8ca48e811937f3262a0332bcf31008b2a42a1fbf55d7f9f78cbfc540dfe3e7e4898d3b71d860f2292f5206132dd6ff558a105b8a5fa2a334d37627803337b09a05f6a15f121f8d9112163e586a621a8221e5f8886ca778f2dc1123ce84e23f017165ef972b9ad44af86bce55	18
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	6	\\x91b7996209fe329717e5f1467d5dde7fccca6705a2326aff0b01a4976b84f9119ec49b0ed7e5b2aa55f0a09dd1e1c901c3814fe0c31174edf2dde0d42933b700	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x7819e98a500f730bb658f7bc9ae353fd37d3ac8856e058152e44c978aa6118c970c7bc33b8f4753daffdb1942edb7426a71379c02db2896718b6519393c3ee6d489c58d972399e3e77d70e086ba6a9fa1209232793467a7191d4b035cac01fcdaf0fc439062db8c718b6c7843e5e3af398583e96974cef4655652a1c332e5166	\\x02ad7523035e1b4008a094f0a85613288fbea305b2907afe86c8b0ea54ad8407b6e0493e67f1fbb98005e7ac84af43c2b07dea92b9a40709cc424199e31cd2f7	\\xa3bdea62458970529af058bffcd90e2e3d39b1241c97a0b338f185b79381ec85857d768bb692541f9d8dd751525fed348ea00de5531ef687cfa030ac93be01096ef76e411a0b83ef53c74bf3fd935ed9814b879656747111e92e49b5811bb301f4ad6f5cc4e0224a6685545cbb63dc9cd8613906f4a66058f28aff1b50d4a7f2	19
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	7	\\x9314b29ff6933ddb70dd31e3b842295da83916c977472520fb03f4ce932e2464761c8ac165e011d73c884361ad5226b5efab46693396043efeb3bb0d56c9ff08	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x294f06a03021db57695de79901d035227dda2d7e31aae49be8c373b503bc82111089241332f1ab67369383b4d14a151ab986678f029b24e7d47a3b64dbbbe88ac1df55548a77c2a84baf820a7b4b14bf4976bc70aa8d187235918120fcda936f9ec409c5b17c927e2ba25c393af035df7d4914a0b1bd34b91ebdf635b0bd6094	\\x5aa2abcd1da561c23d0582df6a782d1b8363012f18d9f4c879d088270f489685f8751d34c0b3cf1a28da94f41d220b549de6ab07c1ad09df4946852e02231be0	\\x6bf9f04447c58ef7847f16e7baf9f9e17da2196726d80773f9bdfdfae1f0d7562c4272cf47562ec1acf1e75cb4d33dc19a08046f3d300b714f1512fd8b5fa8f78501a69085eebe7924b816aa92ba58ed56ab5624908b65b9903b4d50743474517bc511115b2b664f404df577beb667a4b6e5b6301f3687ed6ff31628045b830f	20
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	8	\\x08cf9346e0bb7be929efaf5f676cde583c7d1acb602ce92c2c3c04e697653620ae7f0e7ccadcb8668c08af07b1762bdf41bb3dd08e925f93e1c552293dccae06	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x5f655f24912a6b08cb1c9412fa683f4bd2360af77ddde997fe824e21ba9729ae58c08c57f82114915c06b1dfb8861d77a0ac86f249229bdff513bdfdf742dbbc667c5407f7cac4c52602a98b5bdb6cea0fcbe060da0f16ca169c5848abf5f827d917c7e4a1ed6956510e1ad523300f6a31b4ce0f7935939638e446d062c542dd	\\x5c053def96d6822139439133f71b91db3196392ca62b530939d8d1b9b7a889a9e9b035ebabcbbd51b29587890bdb9bd735798fe79b1d64ac3acb2105d7b6a0c1	\\x06542e15ea7e7ac0213bff4f3a617b091ee4b5648317d435ca4623743680a98be939e49749eace5aa9fbd98a8a5fe9145a19b302b8427aae3a843b51206264c9c047a2b51d72ae482a6fa6418996266632189cb3d092898124585e1ad8e83e95bc291dd0c143cc1fdc360ea30b89fc843371371470ea5b79af74fd9c2eaa533b	21
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	9	\\x575e2b3a448fa72841c15cb22b903de058199f48920d2774a42a4ac4a8e55695b560241c8619c246fd8c811224a0717229ff2ed9f2773f4a2bafc9f9c9e60f02	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x7472dca5f2c7b81c349cffdf7618fc42359b800a1c552b3c97eeed4732c466dd03e2e1fc7f35c49d0ecb4f01ba3180a58a414131726671fae8ed92de7467d34f5756f52709b6be0a4a93cdc358b10563e4563f6cf01d866a5f1b82df39e52190a00967d275598f6a5b458765fe41c6b18d84dfa39a67ea46c6586eede9d7d38d	\\x477b39ad3b6e90962b49440b9962fc94e25bdcf0352444c1169ec63a902bb68d627dfed403423bd167e04524cbf59038972b41516a225ab54f5d42a1133004cf	\\x3f1e938249724b7b7aed9a9d670d2ec8f5358907c11117eb1b5171254b4fec33e0457f49199a173ed04e7acb53fbc08ec0987276a8fd6316a85293840ed3d01dc6dc27bdcaa0d60b9bdfdf5db41733cc1681b67afc2078762fd3e1a5a111d12f5516596b8c35ba94e3e789c0f8c8477d3478c23a73d72c837755d709c3c6b296	22
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	10	\\xe8ad2cf091c3e8b6cd25d65433e07345d4400d07089bd1ac3749d1bae0a88d952830e43b9cf1a75a0bd664a01c38b31984c5ec6770d74aa154680e5a3883a509	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xc87ca75127f589116ef033554908e6b78de88a14fe145df3ecb0037c73f50d9b0af08386377dbdeb0afc64dfde8e099c73dcb623117e263e9f5d97fc53bbdb1d5c6f6d5f4051f1e59bf1cfba4f3912925e753ce26fbc0ba94f19a169858a411fb6f01d9b32f46aed93558ef0cc78e85487af496bc5d247d6f84a3cd189a6dea6	\\x8a6bb08cfc90937e88ada0dc0eabd211b26b5d13ec475ee0223ac58e34dabc86666805c848123c9e7f05f04ce2fd1606df07fecdd43b1d700e740055acf00309	\\xcdd109f523ba60fd2a7b9bc3bd24684b2586ee463f113c956e3daec86e6ebfddf51a6437f071ad337a9355ea9870e02472d69256ac0bde4e046c2ef15020b9213c8fb2b22ff7c4291f7592683dacd022afc7c3a3116893f3bdb32687ec5399d3dc3581e5544ecc8df67410f86120686603203ed90f74c2245d4d74e86c92b2b6	23
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	11	\\xb4dd07780c69d2ac054d2b326c7d6597d6a8ee3f0e0800bf531faebdc64dcc292fb6a6394513880ae2e2c8f0994a875c32195b4572bd4622d2b32826363b030b	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x3e5b084a68bb96f49b4abe05c765fea5f0cf5bdb58083b054f5c3f31fc4c6702778597a9cbd9bb1213d390185de8709074e61b65b050f0fec4a29f070a392a4dd27ce21f34c54a1355d941ef78c11a2d2563b472666bfeb326439c11e0a6cf5c49507c28674320cd34afbabba0a7c62768b3bab40c7c7ada056b00bbeb4ed295	\\x31e672b687057eaea80b186e06b8c922bb29501e5ce9eef6e97d4ace7451fd90fd0a6ce49ed3337f4c59b707fd9e93410ab5672332d7c398a6c3970e524300f6	\\x459974742484d2f0733cab37bb70bcbeef81cd2a73b04ded60d0b4f32afe6430c37293bd8f354c996e2cbe3731829fef11c6f922767d7a1864485875a56ef4f21d0f9c5a53e45a195d4ebfec482e21397c79f2ef6e60f1f73d0266bdeb2fe441f54c3e3ea8e7755bbf831af79e2e13f7dd50c8b6de6d914ee2ef6001baecef1c	24
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	12	\\xc13018456b4c5ec781a7aeea88277abaa3f30cc4dd732f9c3c6e7729935ff1154ca9090b64357ac89894959550c2e5993fb677031b4cbcb6f61205d322c0490c	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x5552be7f7ff2b5b75b46d0fcbd5dfbee885f0c98a353e04ebb872039afe97fee1a0a39ddefdefeb2a11d14607aacf531a6a043987ec6ad842865995218cabe847ed9575e93b9e42b8ff7460d93d7329d3039374a65cf21ae5e649ab155535af3135f1ed150daa3e193d9c74df71ada136770384aa87ed1ce4fa961f986ce3950	\\xf0a432825ca59c9288163d0396cd21e54b780278a1f93a7fb1dc93bd5e8170ed30af889299e1320ce03f20809dc9d9685d6080524630a2107223910a864728b8	\\xcdb321993cccc88d8110e1f3436431825b8587dc080b16c69d5f0fe1491fa5babb3f1553482cbd857906e51400d9587190e70f775bd6026e0a96019aef8be1e060a72cbb091e85fd064640dee09c84b0c40928e06fcfa1254deb0606db25366141a64ce671599c768c34069636d6810c443f1803d3595d01658c497f8e7b5b5d	25
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	13	\\xa7118f96b6ec645819392231eaa3dd69dcc11084dcbe79627887650ce284cdd9db07e076c0f2df8ec6fbc2e1f4bb96693ac9f88c8761cf7991d43c4a4458930f	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x328f2729f9cc28a8a7f68203212c1c10cf13220767568d3c0a84a2f6407fdfc30bcb6f2bfe6791db1a6f34aba9526b287ae8286791496ed02648505a0e5c5f0d4410836619ae651451ec1f1e527bfe0e17874d85e10169958964b36cc421e2938ba0bf6766d97af0debd9e5f92b7e15629a0914bb7bd1dd3301c9ed733933182	\\x6116b10b19bb28c91c4858a7bdaeed3504156a89084fb1c240b089d84d977022e72ad78199d012eda2948414f665c996a57ccabebbfa1cde7f8f7a163e4d8773	\\x9b18f09249fb3cb193763c01be091b8c17b396377d531c6e06aaa38749942efdeffcaed9ba3b4347f00acf594dc490f774256f28681e15700668032abe14b43259e6c82cda1aeac475289984820d082585bbf6c34f32bbc7a594b21749f2dcc43303e8e2bc0555fea858abdc3d55f820c1a6e4fb3a8772cd54c7aae5fba5c7a8	26
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	14	\\x49872e5e77cb79af133603f9c6be02db25648eb141ef554b56c8b5468fd07582da8c2695c99c33a33b8064cc9604dfd20bf972f79ddbc3fc4b9e24b2c0e66505	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x55a1b6bb9bf60bf626cb4bf9aa58fd20efde35357fcd76d04cac4e0f54eacc3ed79fbc030d83ece898190841247e1cfe5f346d9cb2cd48253bd42e291726fc8e3a510ff82519efc8575384867f8a4360f0a8d6d0d0c3e6556dd373d612beb1ad3e429bd4f8592374caad2ab9d9d6876b0d9f5789bd011a881124c7d6525b7ed4	\\xfc75745ff7db0de3b11200e14d6e4ba0fffad3d73e0b8b570a689a06315c3e033d60d4bc1ceaf62880922a8e8310e8c0a7586b6f299824791bb2e3e38d92e04b	\\x9e1a4138c251a513ffc3d03e4df25898b13adb3064936b607e8f2ee19fd518e7a19e4386ceab9477c978f062a911bee17dddb128c808362856aa457062a9892e04582725528651b8f0661c9a662863c524720b371b82bb854ae04b90f5af410c51ec75d68ef88ac19f0ab15e0ab50afd0f0ec5c4c68ad930df3618caad16c990	27
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	15	\\xaea6f06399bd1602a768163d903116213def428569ffaf3e1c4c443b622ed4073c64844905dc2411e9a135b40c752ec24f45c8f6d37af5085344b6d7fa6c8800	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x195f4753334939e4ef2988fadba7e81fca75d8898b9e35b52c0752b2325c8ebdf9ffd4bf7ac2068be1e82561d7db14c673d4f65cf94b7a38e098ab08a0ee92e3d52aa96b9c5effb8fcdbeb83654e5bfade61a5aed7c8925f6c8e087c60838022f464f91c6f7509e5dc1c28a85c3e76f513374a966cb8bf93fc2e47a839863c5a	\\xad56f40b42c92f9799a33dea84ecaad2418b4a33386974c8f05233f60ab51a699f41b3458cb91cba6c684e8be9021e60c1fcd22c0efc7162f612141091e361e6	\\x6379dd4704b9100d6ae37ac92641d53e0efcdcaa52fa723e642609d24242ee7225b9fc68a0bcba2da7924b5d1a13987c1cbd4789896603d3712a70cd453637bb74248f252334fd52697cc57f0e37dcf5fd5e0c3b066bb367083ed16c43e1fb9b877c39763a546012cdf565fe0903e524b328cde6bb00bc17239ccf75b59b6aeb	28
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	16	\\xe4736b35f6f91f6f54626f1e7ec116bdfbebd42e957575ce6f8f0fb1ba2eeb56a4fab261555cd24e64816c537985d8c02c670ea394ee9a3354b03ad38ee42402	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x19dca0783105d999a44a90a42aacab9c3f67eb0695b55a0a58d2975b5940d90ccad9ecfc9f0717d15e71422e4d5bc1ad686f3c052ddce389e38182c3d019515f546a832937ab59a0d8a7ec615eb877b2ae7f1aca8920339f6111a7f47a3c2edf1497e82e1e53406e737e6194df770ed03a2db02f8f24890e0675de1145444fba	\\x565609cb8a13500af2c07964f36794f41726528b334f186e1aca7da65bb48b3e87c9c53c10716932e030f77270c5a03c60aa3d4b5eece62f0a9f9137e1f5d1e7	\\x40f884f7a27cd5a23497abcfc27a2588fb53d4b8425f7e52b1c527b0e71770e034084207a04c9303dd4fc82e42131b0cfe0fc926843d34923fc8d7018f587ea4ff8e9a1de5b76587b2058f387e82a466f91f98348db0115cfa6f6c905311e9c189ddb8e001fd2c740c58068686655fd686099017d76f63727d9b03311a32af9b	29
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	17	\\xa30f8034b6d1cece846b26907f4e7a582c7104f13e2a037228812241007fadc54dfcaa52e9d54c61458d95913e334a5b263cef3d76054a29570bbe6f789ca207	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x7c0531c39aeae80e7151017d0eb0d3eb917c3f2a8c646499aea2ec7ceb613aa54346ea937bb20c08a564f0c1a87d6cf5d496f86d0da3b0b0f3156f5418df0c3c88d08867629d650e6b303440c8a05b583f8f3b1226ce625c661b287c25c93a430445cc99f937652ea3f35950ca1fcf5b52196a3d18ad369d2c1cc2a9feb01a45	\\xf913cb89f1ac505aa6c8efba7ac9fba675c2e60b2a58f132ff2bb2ddf517ef975e7ae68968c3b47c9f33d517e3d5cc89d824847288cf7b4199d9d30b01bcda9a	\\x474bcc8e348274ce8599878ab5915e8e111c2b219cc3196c34e4574a5cd9d6e45e4c3ad1d13de21268279adfa17752a6b71d0259e8b2871d5d4f3dde2e9e064be8e5532241e28de3bf2954ff627e424b3b83b2e33b2d374d0aa59ed64729381a04e001d134a81cfbb39136bd62d788fbcae2aaae074420b574c6ccda3fdaf03d	30
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	18	\\x5d55e210f0317cff85b73adc15370c966f6d04c28f174142df6d50a9926ef0bfe8ea66046a35f577f0930d3a8f2b0d4d8b896103fd5af40dd05949ff7e34870a	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x9a47cabf44772b0c839855b83e43fd41d1b66be2265a52831903b3b7784c177854349708a43363bf29157d7c9bd0138b3a5bc4942c9d3b86ee5087823bb489cb9060abacf2bdd4ff515ce92146f98f9596db8aa445b101cdb86a37b1233c55461f85b8e638379341b7e3a5d8ce84af75f925d0cc1d1397089256f91f4d7a2940	\\x72246de9f751cb193c9161ce63ae5e36dbef72706caf7faca1606f932724b1a85751d0762d1441c04c7e12657b18766968f4eca96c31d4156cdc3d1f6318fd1c	\\x165d1e48366ac88edd2b2518174cf8cc3e0f506e5a92afdafa216cbd637e4aeff66668202974136df8c003e09dc8c278a5ce8575595a6ced5857f77b72dc7a6d8a1dd697314ac56024e38c32f1c9cb9257d8cd6a3d7bec7c4f8ad4b7564d2a45f22071063bd68d9492e746958dd59e3cc470c24f0ba479e730c30739ed20312e	31
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	19	\\xb86a159f74be7c4d8876a4b42f42a533b98ca44965950d6806baefaee1f9608795be073463dd37af55f0aeeab7f4740e1334fc047bdbe301eec2ad657d4bb80b	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x48b2d5b83fe076569805649ceb4056c2258e6c56a870135b53995a25a83542310d3550e9e4e70f21bc35b83313029a06b5692900785603c37e30a0ebcc375b19f7ca22315385078af6f0387e807e26e35d893f6385e5dc00d680d7642f3c33bcca77f6a241cf4ec6e4c66af8877f5537ebead9dde045cd527302e948cd872cfa	\\x37c5ad7c4f442d4d8d369e60f1e7f3d94e5a5a7ef836a02c29423d6f0220394d1a7145424fb9b50a5682a8709a550dca38b8a89a6e657df243d97e8fa4c4bddf	\\x284f5c484a253c76624a082a51f218d8314565373560ddb58b2da586f9f4500cd23c2da80236bda5e0b5f566d18d0a0d57c64cd189af46639cf13d692583ec894211a698a1e6b57ead6dbd555eda4d300829ec87c733f38785ac677139cfdfbbe7832bd1c340942e6e7d77e93372037730bdf0c08c1ddec5e44edebb90066759	32
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	20	\\x27811f5c1f1da401fcef0444810deb069f64bc2b190ddb34cbfb44a3e6c56789f24abf5b9220c8d0378fdaa47fa8633cb3641ef36b7a26f6f67523cd2044f103	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x71fdc04db00ef1abe3d49b01b3a1d73b57a37b7a018a8d560ea6eb7dc67a87e74f7b17fd6b84478a1fe66784441b98ea7b587855173247c660d1e562c6257ce6f5e8c8e438b1698daea58be91d30b0500884ce5be06b69f3953b38fbea94320625afddc442245e69134a34d2de8e8272ce765da6a569d593cddb06b444d90d25	\\xaaa92790935b5654bd62b372c128ddc1a026d041296a0ae9164773269da6f32dcd19348bb2963b8882a9d0b55e2286806f5b89d08ddbd62e7bcd47e0e8e84a16	\\x4986b75fadbcf76110a461a6756521c1d68f898d5c3472fe844ed66114ec0d440118438b4dee79c6474cb77964048ada949cd65f1e8e8210842f6d27e7738d2d8722440a13bc5967815c3c7d68d66b3c08f6469e051ce032600f75e1c356d5ca9666386421359d21284b4b2560a6502fdb6e72370834f1fd6ec57ca9d82d6352	33
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	21	\\xb7da3a22036c5135144f18bf5fb74c20956b62d81732298d37004872f5373e6d2690b2f2f86b7caba1fd496092c537a5888c2d27484f6ba24a2d7f453b298d06	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x6c9c69c2df1fbc18d76290753f022ee29441f5fc463825e75f0edba5a37a949b2a730a6ae57182a451bdc26bfd06f121bad8e0a4695ac62872a0578aef418f4bcdadf0acab5df7d7b38e14108a518c1b5fa9543fba75701b92e49939c29fb6c5b4b778ddfb738e213d2ce8d71ee4f60de196a5ff39f673743cd67ac7d6f23d4a	\\xa15eae6a28c8ce7ab5c80e4d7c5796ca570ebd1766277ecb01fe3f5e41eed9b6abc67fbc4743a2870d023e56c0b72dc23abd003ff601c88d201a546fa514afd3	\\x068a8122967421e659eea18ffaec408bd99083bfd446ae7e2717d391c38c96141e97305a2864bdd2c532885368fc26a29f29feb834ce60ac3a364fcad62019f950ffed8fc184e4b5d33e7e1feae9121596699df85b7476b0693f06eb8a9c219bc2fe25ed3ada870deadec4e47739ba2b2d0815d7160f9760462ccfc52958b64b	34
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	22	\\x29555b421efa95c2187401689f6698a7ccdf09ed78105dc2b6c93af6c13bebdfc2928881b0fa5f74a55e85371291bd1c88e5f1b5d6526b054417b41d39a82306	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xacb744fdb65a7310bb48cfbf47d3d56417a7d797be67664d99936685eba78de4174463408da6d923c24101e360cb6990c27720dc64dda4ec93254b68b2cf7abfab30bed20e3ede2e2ef82c4a5ce220f7c4b5d3e5727c000faca465535b3698c42b4bae1a1c7681154cb9753ac14e8a349b10b48fe7b358a619f0bf25b60e263c	\\xcf426b415bfa84beb42d225f844946526e4c78ccb8f1ad6036ca9ab2eeea5243166ced43079866319e184d9d0b029ce37db1a1b8b53802c28c7fb213d34816e8	\\x0c76ac12a22f3611dd35609f5f8facee1a51b83318f9102bee699784f55830cda549471dd282c1daa3d7f1a9e52263fc83e193ce520e4df807fdf9b2b9dfcb70438cea9bfec6830dc8af89858c484c747899fcdcded2aa42fa6c5d6e6ffefeb8c1593ca67b51ff4290bfaeba36a0ccc56223eb216299115387e439605fad08ff	35
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	23	\\xb7a6ce039ef9e0245b4a6d9bf94e89ddbdcf9391ef23f181f10fd7f603e05bc13c2729a830d87b8d47633d11c31438ef4e63a6a19ab84c997d316f6e10fab908	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x580b2c3068995aed20cce2cdc63d6c621156eb36062655b5a0e616942642b650572316a9a582ca88540e171e36c1931ddcd3f8a1c9342ef59b91055306f9b515bf9a14cea6302bc7da5e457cc15ea5e932373b97a283db6ee7271bedbb68a2e8f1d63f4fa904dcc7a168d380c9d7f3b4c14617b72c0ecf7ad0bb2b88e80ddfb6	\\x3a16e62391d75feb025c9ed0abeeef0388b1df45b5ddf71b7559a6110165168138c31817282e5b836d9f5b0a5e0f418248d1c21d28923da20d08f764de8febd0	\\x6ecf860b6c2f9956203129693f6ed9548b4a610e6b7754e0ea72319df8e63bd81b6603090f87e3e1004a2bf2c07227ef371345671d46e1be0028262cc3584b8982bf232dc9a7c3535608acda0a721ef91c4b4d9bb1d69ee11e7f3a9b817959205817da2631a418e6d6a83f74f328e8db4256ad2f7e4a61aca6aace34d6dc4563	36
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	24	\\x7fe460dd36203df2c22fe5d1cb797941aff72774da8b567633bf69edc2c51d4aaeb36b1a29db28de240f369b4eaa46af794f7ab38f00cbc6a04ccf5bfbbbbf01	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x564a039f1f77e3ae07b99c2a00bc54970a79a11039b701efdbc2d345081c965c6ad188736dee86e6b92999e7fa381eb3ab4620d405bdc5f16b03a6183e6e2211606242b0276b2bad7e2978a1dceedaa7563510c538d3042cc791f7c11f5871d12c6c60f4c1a1243b805e341f8ca9ddd97a1606a4e1404423b1e813a8a74c923e	\\x5fe5068ab1536af5c990ca2209e7c4ef68e50f7d6dc63c5492a1da35a5b9139f0ede951833fea6577c01086bcfde6d1bfc037c5c4a13c4f73785754399be7d77	\\xc556424378af6530108dd3a6d4e1fe03b6c376f8165b5492d16fecf7739bb6614db4297ce3f550484726fc548b03bf2725a92bafbcbe0c2c1b17df4b8d441a9cfdf4d7ecf660806239982d0d8ac224c8f6ee614430a501aa17897514a8d269770e4edd95e486dd80fcc190184a4f68836edd46a33935f8ffa00755654d283c4d	37
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	25	\\x87ed9e9fdbb579f586ca85f86ae200be2b827cd34507bf532968c545f3966883f80144beb48930484158f21310c2c5354c1e2cfc73b646ea339c690b383aef08	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x377c8cc2039a4562d26fc764232b55f31ea4b28a2f7781c950a53b8bfea96ce107a85613858e6a9ba58d12896ccb537add2a2eb42de68ea92dcdbf2bd12baccac30fcf84be74893acb34bed395f437315c6b4ce1ae88e0b1759a054c1c983cf362544f62488688e3c5aba458360f2306584bad7700b59f9e7ba40223fe874137	\\x421304b302eee430196a6aef0239d44a05ee6010ccf9e731d19511bd900c1529469eb3e961ef62671932682312bc23c66d98dec89eaeaab6a3fe8200d6e45ae3	\\x54782a41b719a77130a911998f96d252481c05d460dda4447745842566dcb5c57f55f8a04707b2fc35b709057ecb42ef315249841602ebd95d887d2680e7ffc7dba3e16fe7869157883fa2640db2cb6d038a7de40fd836a8a140ea665b0119de39a6dafa3212c09fc429a01b81d9d087202ef45ae8443504f55749d9bb515b09	38
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	26	\\x9b70bbafeb0f40c0db60505478576253644d81d23987e2b6c3e0509ce66c2d7eb3c7b770291be07fcb34bef448b8524dd64535acf65d55160b464c0f5b479a0f	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x6fa0c1b1c7f39a4ce700b12441bfbf4d75c7f534ec4d77b564f27a9c6a5efcba283d913e39d8e891b2df0579fe9b09209785d327e6d9b2bea5845454f38abad991d20c0d6597cef74bfea67730e580a0d86adfe43751c0cd7b126f141c37530b17b73d9063adf620613565947262750fb4bedd145c42cd97de32c0f6b3d4bd5e	\\x28c10763e16139cdac9bcaa7012f6d4f2f0d3e76d88918f6c53817b9239ae30ece83e7713061ca225eebefc764eab2beddaae84ecb735a3c8962b81e912f461b	\\x291309744de15a0ecf2ff7a558b5e66fc7958ba3a729bc975718f302dc73f107efa101a9603247ce592b01334153caa0c61a4cb8a04c6a6de7a464b03b7e69e17db9ecd392f76f9f1a2be7098bf1f20da63b736dae33928245917f4c4914a98a5eac86bb8cfd0f8a1a534f7060ff388c867ee4cd8501ff741c9e1bb4a02e8044	39
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	27	\\x98913dc0c4c509374eebe82a56801c0418d3c1a6a07c2b3a3396ecaf5dadb60cdf93dbff6719c3321599a69b502317a82265f946c09a750c940f391527a71b00	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x7227bc39906a02be3f2a0ea5865c404580e98616e6694aa38c084522a1257ff97db7a153ade92c14a4b855e3e092e9a187e16e6e5ff2fdd3d2cf9554c7937cf9f32b287280535bb208f69f7190ad90b1b9993138be69432fd55bf3283a92023c37c279d1015e4e6c8572e4c61ad58d021377b7b1998a589e4ba7ad05696f1c5a	\\x231850d9b46b8ef74d45866c42477cba424d4243fb774cee5487ca81612210c298d0ed4e597af466c7105dafe7409716c1cb46998591fb7410ed8b58fb67b610	\\x250f9609976c5847176cf868c181245fb3ba33a8d33596d17eb9d62c2ea7c2b24e2142f725bc0e93fd344234904809ca7d2bf72769cdc655a5842dc5f8e54c4677fba8a5d3793717bc729f5c2ca3bd6fe7da35a1e46e6bf619b12e0b9040fe0955ca6cfe83b8b3706e5939d9ac0bb1d787cd04fdff70a6f0c83b9d3259062397	40
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	28	\\xc685e3988bbbc320c0dba73e6263113b172ebd130a9562fdeddeb3642a589486e6d2e7da6cc0be58d2eaa4f8b62266cfc6d678d85f6c6fe868dcbd3391d0280a	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x2d3cca5844aa6390d8dfae4af1969b9f507eb77d2bbd64cde0d3586fda97161fb561aa9e81a702220ba8e96fdde53ec65a7b8be8c830beb1797129f04ae78262193b8489345730360dde321586bf68f277f0b5b0727dd381d8ce50a85a2a5ef9eb2d3b67383b898b93255dbbe12174b4b0a1f40698a91ae4374a7fd4a8dce145	\\xeb32a323b39a06b8a8fde04151dcb10058fe3141c6cb5832a5f211ab0a6076edfed35ed4a8a0cefcd020984837848e352c6907cac99e9db9fe792f0a5187ebfd	\\x76212af58505253e7d44da8d89b907f92452a8b065898fee0fa75881badfaf8a84e1c6559841d3bb6f442c01d136e415d342de22e012354cb0af71fb89f47dc83c2f5fdf9ad1a92817a975b7d744999b83e80b4ce51677ad7f92d06e0b276ea96c692f05d0ac2f2a1d3918764d8adeb8ef384f19a7db9c2abd8dbbcd21d98123	41
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	29	\\x813a77e2125b6ce37ab83f2f3626bc0555561294e9fcc5d3d51b46c4e949be61fa546032740f3574e146350f9625e210186d0f5e9bc6dfa8cce8171a9ac34102	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xaba09dd192767170d96347188caa0f671ce2a928726021f3e9da27787e987c132f1cd9a64a8efa1c21e5a63d85e4ff883968d32c974853e977627bf656894dacf693b793b8c0ec3ba28a2becf51be62cb39fc31bfbdef5bf63505d59556fef78db0ae808fb2b0637c9f53bc4102a41059bd3a23b07347769efa048fb7fb717a5	\\xc5a7a586f14898a6ad0c68612cd7a35478b4a792d9c60f357ddec6de092cce36aba1e231d23e1d3878965928cd1ab350e8414ba2893b63d4c6e419e198db6965	\\xcc25aaa819290a5d7ca8c375af995536537438d4162feb3a2600172d03852da5a1611e393b2c620d6b8ae917c37efb9fd643a5259ad65e019e92f79ca22d2547146fc796387b14deeaae21cbeb246c4b42c317a14a53dd85a34cb6b7683159ac2b059e22fedfd301588508e3fa38ef3cd76eba740e337028ce6ed26450cab495	42
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	30	\\x6cd84a838ef603fb4def43019896c7253c52f67fada3ee1568d70c56df1d01e60fd4b85c1a677f6eb1721dc8e6cbad04247e6951f21741edcb316fcaeb924d09	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x5e60f38f5b2b9060a55a318da18c4b59728724aa5b6c5fbe0f9a6624eabc140a168ceea50a4bb63ba558d76996f13165b10c16a020393217934e5bbffba8195b3391a0d6e6ced0fb1c65155a1e55f50b668c329d16c2761a5a07d24b1293d776152ac774eb86398d70b8475e20602c2c9846f50a47f38048eb650e148fbcf52f	\\xd50ea18636d0ff4f6e386ff25944f3719fddb67d4a69f167fc71d2bc426728c73160c37f83e4f175ef8b2a45d16b5a08e035fc9dc167e6a90cfca73cda21707a	\\x182ab2d2a24799d0e017de9e809fe6d17f988380b4f78d3d429a287dfe710499eb080fb3d8c48fed26c457a8a16800bfe77967766fdc55f3d0ae997b09f5dd4b7c019e7008a41e00de0d679c21837377b773264f6c07975b313e86853f8d05edef35a221fa8ce42604a6e43c00ef2a8a8d5c201290dda093dce274258a36e971	43
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	31	\\xb236f8d76d38deb1684b4829828efaecea38351cdc6bc29537ae02488ad8accfdf135f50aa9cd5e384dc66cc57d396626a1e768c126963d3f05de6de15489c05	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x849c028bcfdb06af981a4d92b21b08168abef28ec9793e42657ef8c84ebac7c95d77536fef3f50c6e4bc65734fa32042679101b7f2228145ebbb49a9ad6f7cf6e4a0a487f66475742decc0fec012ffcf175f617b664ce51b669ac6bf3349e4f757916a956fbb37e858dffe7fe29761723572f8e9299dd14a59886dc8a18af8d5	\\xf7deac20acf2f67b66a79c66f20822c5954e5ed441e58de80047e9074da89ce056a6500cd18aebf5de519106f91d31a9dbc3056dd292dfd1dc50fa43e421074c	\\x768b249b4ded7ad8d5205588bf0bac9219d48ab89b797236ccd455a18ff3c1731abd68c7f5911ec644b2e7eaa0cc17d83ff9fc24d02fa3474d02bf9d2a91859ef3a833731cdbcc36bd1b6c65c79174fa050e2a773d4c643c74fc7c3d54c8e4fdcb546af4ee46ade15f9b8e9e2189dea7fbdc3c99bfbea07134f760627290563a	44
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	32	\\x006424a0835086107781984c23f627477b42631bd7353befa442aff642099d187c8cb9ef664879fe24e96e18d8db40b07deea277c4a12d542fdb4e0d606ab900	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x971dd7b353c11ff7ef66e3de85fe8107b8dd760bb1dc364c32b83a97304ce520ed81a800279f62e192468045f0b1b493d402d31f6771cb0220456c6f10f607e30f9c49fc397c9dc957f99939e180888fc9fe8f33fd3d56fb09d453f0b43fb42cbfaaa10c5d11c96c14d84859ff0e46dc66fcc76c41d99c2401613892ce4d65a4	\\xe34886f3f83fdbf313780901b3e65d43ef6ead6acc932f674c31a653a4641be4c1aa5866553192566bd468ea2ae1fa92ea7cf3688b056885c10a71caafb2e624	\\x4d0a263bb2c6debd6be0ff75e594d3134d8d386fae36b0d95446184cefa7def7b815577da7eacaddddaed71a8c599f2e6017a38190e1c884d744b02d9095f3e51cfa1b2a1c82b59f9e6b405f8dc456ce9250ade67cdbb79db6e4d3506f162334a4376fcde00ff0024abee9edf32c00a946fc450c476cf4e99ed866a3cf78cf34	45
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	33	\\x75b4b428e31a865e697a343bae91820a7201293f66ed6dc58769fa8b792bf5db29f0820944ab868982498d0e50caa1dff257bb4ee9bfcee8c9ce77fdffd92c02	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xbe1bed654894ab3d7fe789b4cf2490f55f61fbfc51f934ca1b678a56a0868c4d9d1597172bec97a5a6f56442fd0bd2b566137eeea8f0d191bc0f64eea690921fc4b42d8c19f583bb903846d40e143c3b411c75e822338ea74827b8271452d79e82ac8130b45acfcdf6fc97a6925e0e7a7435d2919b13a3cd31668b6d34931d45	\\xa1b79d9df74423f4d045870b99791a8b76dce544a481a1dc8afd3a034bac6eb2938dca54f9bf5a9d970d555825a724544b6b8f8be3f261df9c61b17a1f3fd8e6	\\x266e78bfa58c577c1c751bf4f22136bbfe56fb0e5bf0b95f677fd37498b6846a1322c36fe2364aab2db73a973f4b2691702602332e18e908f6d389391095fb8a6e1c518fe5dd065db9b82900765230c1abcdaec43111d15fe7c2028bd6287b308f8dc27b7c995adc8d9b4c73953290e89709f2400e001412f717e24a48a823c2	46
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	34	\\x83683b1c2095dff6c7a2a0b9ce3a743ce97e82d2de3ffb14dfbe3ac4182999a5000f91350fbd91f1802e5221d8fe6eec77a09632fdffb2e87f196f6c32e8d50b	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x9acbed8c5611be055bfa55756c1fb5da25228d1952f30b2e5eb6ceb0571941a9545018b2d5e15275907eba9d4eff694274b59e22484e0ae2b6464eb276665beb28ea10bbf9a68bc5bf8dfea456546acd58b15a99ee31d9d84cdf05d4cac1d298064d0f0282c031f4260b52115ec8cf203a31f1ac8a9ef1fe06a9900a24955b5a	\\x79f21a0df35a7a37fbb4cb9034fdae4edc6b6a9ff546abd3fb5e36ee2cd765f82f189771a82c78d28df5d778a9d0c707b67de5735fd5c1436f828d19cc2a51a1	\\x87885c82bf0af4e9ad9a0b758edc9498e16a4aefc441fdfb29c581b1a101040628b58f2306c655b5c7761d0cec909136b2abd7ccd5419699606aa0ec7d78e08b9738325203366f4951040a795fbe082498cffc4a2b116fc95728fc7399207a3e25546ce7258db7f9479f7f834942ace3679bf869b43c1f95d65eb7a19137082a	47
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	35	\\xf758c2725db70c2c463e6851c0cec6db2e0507a4efba3b6ffb89089cfbe2637bd39528d5a41a8a42e0d40ad66a966c98a69f447327ffe9d1a7a1b003405dd905	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x945b05728096b9dd92ac7b223b99a82b62c690d791b43516e895ee0c471ede8541c402586dbed940d93ed106da32bb511ea1d7b3fbb65c3bbe58e75fbade00e0509e9fcbc48d05f8d7db6b171c7aae9e6b514ad90e415aa8a8430812d330b343f3f3252474248f9506f8fb7f625142a493971181551fe7b83e55fe01409d7157	\\x37453d5aeab11cc517963092b6c20619b53dd1b219d3b0355ad6b7036eab4791f8481cde6b6b99c1aac70311c093770538460d2d085beea26668efd28ee40d63	\\x4595889edb087ad03cb11f81ad075b3ed806e9d79dec9a7aab05ed727e1660f5d75c6bd4017ecdfa2ab137710827080b401483907727aa62c368c72126e6dff2bfb541be5c0f32e1d0f407104b895219d68280fb736671e054f15299f6b5f86875ae7a6de1d57b96f5d5c429cd64e6018e396ffe539560927fedd4bf53cb108e	48
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	36	\\x7cfe67fe1d613f0989355a6b29e951979b2c9e2dbf1ea4294c79521414dae494b4389389b92e1255809373a499b291e7ae29ce196287ee91b6f29e953798c402	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\xb2014e0d237ec6dedb985a052600161b2048eb8a0d0d232262910125fb58c5bcfc6480c45bf2a7960db4272a96515984e250cbcc66dd9b46163f82207ece6a834aad58dfa529cf2ece7010b55c9bc5c7c462face4a7100dabb4fe87100dd13ef135ccbdc56159dd7e217237264ac31daac9682bdaab54926959fb69709dea138	\\xf93c44464a2c173efab4d63d73f44b61ab2c9d7b178813134eb453b4fe1bdbb1cf65a21603bfa8311cee64ab405bf8a311e0e9574dc2e1d768072f63cbe70db9	\\xa2de302037a58e29139fe624f3053f841e5ef5e5f0f5512b20bd956e71cd7a8917025db71d0a4cefb363b8152956fefc6f2bbb15426d05faff52c84882a8151bf8cb79c5c735d5e83653cc1657fb573b0917f535a4e17d77e99395a22c5ddc99118c644883e599f6300d103239a1d20567c839f2eaae916f4b1f67ff6b86f7f7	49
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	37	\\x82203f77236d7725bf662b15efa04002b60c17b2b43892b34116c058549f5256092ea270901d5f2ae463dd16d576845f2fa6b0c701fca67758031e8383dba608	\\x8414b732c4c9e21585961963cae9fc680283cdb3926888aabac9708410e0f843e1987ce591323b14448e39845b05bd0a072b30b8a55e425a0cada2d8ef88fa59	\\x06cfe459a55b2e0ae7da41d0db39af0d75ac715bfe1b809f1f3c10940e7e2be20f2342b0fae72a54867193c3f03cd29de02be751408aebe416224e24d1066a97c81bf3067e8833709ec596c175e81ce8d31de11582212080c94f9130b5dd3033b3da988671f401fb35dfbceb02dac6e3f67261fe856957431128f866f958c0f4	\\x2532780a08588b000c325765e6b27c6be9da5eca2b2d91f78208481a8a0c41b86834c28ff879307c169c3ef625659bccebb60d00b9e3fb9af6030df3cb246fd7	\\x190d782698d38bba2e19f7e6a49e5f883c4029635ee79b75f5b63ce8f548dc98cd2aff2f512ff919162d4962adb6430ae75d6c87b2842b3cbe85cf51857621a391f137e71d0ae0eb1dbe15823994bffad6325848cfab93163d406a77744eafe5a20bfadd7891726a5babe8f4b98e61888161409b4f230003cc249869f77dd673	50
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\xf4a2c57a3426d4e1bd7db49f2a50d849ab8c36babccf90d38d3d03425724d0e9b80eed3e0360fa9bc4e5bd501ef8c62f1d42d5c413f4814d241c0e7787dfd760	\\x3fd4e562fd2cb872f7d88d5ae11c7f6ab7982225d0f763b99995dd208da70773	\\x5c124c0bfc18b0a83107cf26b8d700d696c7a6f2e389cb9cbf432b16794655d10842109bba78da563ca567f8fa824f5bd84b6b77bcce666c22dd66ab39a52bc6	1
\\xda7adefb7b699dffdde2ad34c3ead525212ce942296fd58b6f3349c0caef3f59d29ae23e374541d313967068c2af354e102708be0e271d50f3c3fa7da106808d	\\x96420ab617ef3520177d2936a9f54383a014c13fce17b3f771cf5a3400552605	\\x2486d2524853ca1ad222202e4c4d78cbecdc88472961e494f1003cddb6c06e20df5d1c0fc386e8b74c918b3c5b8a9a30bb505230ebfb1b4e167f3830824c9d8b	2
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
\\x3af24295e32a56f02eb66a68b76a0b308430c994cc5273926c27e8bbbf6d50a7	payto://x-taler-bank/localhost/testuser-Ym4ja1xv	0	0	1612348534000000	1830681335000000	1
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
1	2	8	0	payto://x-taler-bank/localhost/testuser-Ym4ja1xv	exchange-account-1	1609929326000000	1
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid) FROM stdin;
1	\\xad8d9861c795e33305d6c2fee25e4fe41eb5314bf62f126fa155ae7b9acbd5d4da636dac703764eb0c860102a0240033034f3e396645f9da037aa3f5f02390cb	\\x76ad44ad39c94061b6669563450457c4cf521ddc0e20ce5aa133e707fecc894737d40f388e761f1ada509d7cb6ef13f308d332bb7487b907899a1e5ed9b0c0d6	\\x46bfc9a14739bc1e8a742e9290f490243934522f0c0ee95825368cc1e773e51b9aa482a1d90a7533df44d71909e8f157907abac7eb335971c9eea4c772032090486671fba4fb4cee71c9631397d0e1cd2091b21e97658375f2073088910e597a25d7b917cbaa65bf1c8e55ee7829bacc9165355a4867fae416910d9de968aab4	\\x1d03266997933114fcbf996e36f06da1821e3221b693ffb67222084f305cd3932db5d8ac8bf6c2fd48266bfc5e05db0defbf622607f68b6f888ffa0ca0969209	1609929328000000	5	1000000	1
2	\\x009a9011c33dd2abaebaca777b2b187c784038d66f98cea211379aa36479a34ca9f29efdb16a6bab430ceb7dc78e7e6f53cc540c6c417093f90ca9d55bcef3f8	\\x0d38a964c90917a5b21ff62fd314c1385054864c4f74f096a345ce8c096a3b0456048e975200b6637f9b9e3d6a822beb23bb4fc4eaa45a607ff9eb1638a576ee	\\x27dca2747f41c39a20906ddb205f7f5970fc8f47e853b0671c266d63b78ed4d620bb852fa655d895dbbd5604173d417fe13c2708d53a971223e683f162f915efb60960619bd1f3207439386b63b230d57cdd8b0cf29eef791804a34244a13b4a37103e8e9931ddf24ca1e00044d83a7466c24048c79cf49a3a7ddc88f88015ee	\\x4e2e42b303075790a6591cb9db16e538916ed1ac9a2ab781a9ad16fd079f1e9abc3c2513217f0252de1c9dcf3d96e10f191135bdda1ebdf78a7c4f030d496000	1609929328000000	2	3000000	1
3	\\x33ffdd6a5ff0daaccd4e3e9379f35550405539f7bca4fec73b60c3d95a2b4a6d45b8be096dd26874d350503b56d9fc974877b079ea22b0d63c0643a152ff97f7	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x1449a78624d5db2cbee04bb6357df80a642fd5d3ad90ef75affa9046260278ce8e8fda7b16146df8c396f75b41c35f9ddf9ee10debf35b0d512ee5cae0b1c1a69a7aaecb6bbb328e5e0873e8de61bc1cc8fa23655a8427db87428129da017e35f7d9669474b6667ad239998a2078f6eeae43b9aa09591bb7c1410b37d1c7d348	\\x115e0c39bbbd8c98ea8a4cb22ecd36bf013361ef3902eb5b214a722944101efa18c3c2620f061103c3b72c2133c17b5c9663c5599c3c05006924345bb9646505	1609929328000000	0	11000000	1
4	\\x553bfcbe5f58846926a00273a5fe4b880e432fd5a966b92fd9c69d63dc891a35a9df5e76ae7dcf54ba2ac260aaa3ccbd775d91bd625e4ab07c5094b27a013f51	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x60de5fe4df4ca5ee70d228fd4a7ce1df67f6b8c3009df21419aab88d8c4bad6714be75c8b9ce39cad363acfa25a8502db43fadac8e0cc515e3944ab6281fa70a379f0511536c8dd44f77298db37445b43b85545d8d71dcb01934a4176d9ba7f45bd5654656541248c64d5d07c25010725118982db4456b292242fdd90aff2b3c	\\x81ed40ec6b3510ac0712e8b227d08215367540a14e58f093f99c2e39a6bae24ab02a8b0c494eb7a8227262ce2d067e78ccf50061a6ece09160ca5aa4bd4edb0d	1609929328000000	0	11000000	1
5	\\xe01e5df7d64a3f383e9380b2819bb66a899cbb1f39ada66b6ade1eb64ca3697b416b35b43fb92d30580d81c64929ad680c6311fb6dfd85fe3f900617f5fd7a95	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x3c6ed2040b190b1e3c2bef5112ed3cb4ccd474ae772f8318dd11d5995aa50b12362c0fcb490bf34ed858a793d8c125fd284a69ea80e6dd27ed78aadea0543a72fa851e48c5ee117beb3faffa587881d9960d22ccb63f74fe6686d9d678c85a09f13c000b2918c0e9a4b5598720c2930ceb197764481df77f1796f7657af640d3	\\xeff95cdb146b5657240a38b8fb67b857e34d65121df060161866629c9baf661b794153afd334a044a17e8e8c4b7e570f3c8f14256f6e015204c8455ef3884009	1609929328000000	0	11000000	1
6	\\x5e4e6b1b53c7a07101a968eda0956f43cfe626000f0c1c8f166bd18b80a0ad94f8f02fcd1e45fb2ab00a35a8e3a43426689fa0b1b7a43bfaf0cfb7530b76ddf5	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x23793a8accddc23faa4686c3e371a5c450b6bc8367f36653868a4a057b27aaa7dfc44e57431b13932dafdb1056804803554d974ac167fb571f417b5dd13c5864855e55ee9f33f224f967b6df35318d332acec359387dd77658b0720952be4b355b01c3fda64d00007aab870aa19bc93859b3cee32d2534dead85a9bfede92cc5	\\x1c3301d5edf6bee1790a860918af4a72cc1b2238b3fc7d45295950761f5a92481d16473133275218732b02a9fa98ec67de82cd8ed1e0981f9755b96ce2bf2a01	1609929328000000	0	11000000	1
7	\\x73d5436a81c183776828659233aed64708d197e7a92de660c8a030143580b65df3e13a48191169eeec95516b828eeb4552fe563b4a14ce60f92c17fd181d9e62	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\xb419a2d41a784fe1729a714ea798bb0f69ea1d53520ae15b27f9f5ec28f80521bb49e11df53e3668ce53e1ba4a2a09f5c6b871c7ba7ef8257284df7c21961dc712a45ef9e004715b8606e349f687088e544346a4800959548e6cd0088360a067bad741155fb46feb675dc9d96f83ec450a7325d174a122e053d7d4edf3e05431	\\xd6e11f91f8fbdbac805a18ff7110909169d803898d4fe398a0d7c1a17b2fd8953884f426b72b0e37c2ccc8b7815e5b4fcf6c80a42eae88337fec4740f249a900	1609929328000000	0	11000000	1
8	\\x59cf0010622f3ed4ec51f651ebd1372678bd25f29d7c4e9b94bf51f3a2d5a204f721554fb9d9095660e9deabaef1574f82fe1606d1f3bd4c056ed75df2e1e336	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\xaf28124011941c53daf9e890e445f252ca69a62136b3f166dc3c737e0d3a84e96434dc88e3707f9e82e844db5d9bf26a8b97f06b0888b671fc557da943fdb8a48cacd990c7fce5314688c9972516c09bfd7f8d243cdc03edc9c22dba721c0521f9ac82a4f49c5e25099857901b73314cb15630cba9382048dd5468e7ccbbecf4	\\xc3418718bafe69bcc6eef1cf70ce43f37a849b1b75c7040e9d2d689497ccdf7a65736e43aa8a0e3caa9a845a8d9a24190a9888d9d6ff12d153eb3cbad532bf01	1609929328000000	0	11000000	1
9	\\xb3557a2673484d66439a4308743e0580346bfc4d593ba84c458263c1573673985a794b52d750baac7a5f71dcd4b883fcbf5178cff39b608bcad8ad992d3ebb35	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x6d63dd0a2ff2c2632aecb2c31324ecd9659dfbe67f2bb86aaf285fdb92614f1625b3f222121b292b11fb59208d0139abd8746a505f524985b04b6f52874442942dd347e6577eb9e14088ae68652cd6f5e7f880830dc6ddcd2d49df288af1a13e189e7d2b896f2963c61d59996693ade486dfff748877afca8ce21d258eefd820	\\x979424b95474ee27fc93008cccc91aa0f42b5a57f66031faa1e4fd73462ef9a3a56c56355d86f2b001ea4083a2868a90a82a694cdf8ffeaf67d16130cc7cbe00	1609929328000000	0	11000000	1
10	\\x5c0949273b9e7038780b1dba4f4c2932d1c4b81881185a2037c7d995b7dc981c73c615d8d24ecc4aa6975064a0ddcbbc2c2e1eaba8876e26bfc15872df0bc498	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x1d4858e027fd104eb52df7118f6ebe4c92d709dad1392f81c578a219c62998b48e0c34bfaa823c14ad9d3764938be32de8f65aedaf3eb6e5e309af840c4d7f7ba3bc18a5cc9e73df22d791b7331cabd9b64828edc0fd1004dacae14b320ac991e51a899f0ffaf0771df4d607c7f170662a81a2460f57aed5981bb0cb4604a1d3	\\x63de384d40cb5c2fc5ff686074c994331fa50129302aedd9eb6cb4df9d39807dd01c731373efa0b2aa907b77adbfdb77851bedf2fa56853f689b491ee5c61d09	1609929328000000	0	11000000	1
11	\\x6cf68f5bf9c3087df75b02d29086d304d408853300c0fc3c5b5971483e75d8f4855a59bd69577fd63bacad946825e52ba5d9aafbe74a04f861cb8c45343ed320	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x5991eb826828a277d6ee0c33c0aef1ba6732e5f1241b3c529c2147b26264c8bb6a899cb627338f0645fb2e7b3211ed088d35390356ee87909c5a5e4d69a9201c093f80b9f352fd1bbd8fbf66a3324778ea9a0cf1d66abe258258e53b1644968d4e90b889cc07e3a488fd8e18706711df82fbb87cc8673b8014f07d3846f89d0a	\\xdecfaa5ce4200577644ed5515283fb092a9867dfc0a3ff18f404cae4112f70fa374ab1a3cb870675b493c138daeca0adac17847fccedc38a701da5364ef2b40c	1609929328000000	0	2000000	1
12	\\x459007041ce0281a18489d3fb29c3f4bd31e70efb241842770189f0a4bf21f71027a78f3ea02d8779273dba7e1c4cd81895c8573312e826fa49c30f84534c71a	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x37bb7b17ba640b932257c1100be4c384ce43cb9d92fee5ad7b42fd86a2b43404758a4d39cbd843df249fa88269e798da85fe34280a44750e9532713edca1964c676959772bdabe0bd3bca98aa16d0040d2e9facd9e7691374eca8e2aaa5dba62c8953a9d3458c672b7ac1b83074a7bf6d337b8cb20afa01309a08ea88515fe07	\\x7b7a6d8bef589d93726263126647f3764350755475874bfb9762668d972b0fe6cc8e1fd9ea8bc03117ec6b3ff30a1a0d631871acae2bbaf7408f8ebb9bb5400a	1609929328000000	0	2000000	1
13	\\xcded5fcdb1e19fab72c8717660b3106e64f8272bc4b12afba51b5d95f9c9bca48fa595d3ed08f3be15fdb4563bc6ccf0c511b564a53da34882b29854b4751ba0	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x72bc1bc319752418707f09fc83029d2bb2a7e2c34109a22bda11b985adfdc028dc69652145c9069ff5acad01a09e0d95f3aa607c593d78f7d7efe0aa37c7c51f2fcbbb79d235f025594b9627409117e8ee23b8b1a3dfc35d26f010e2ea9c364a90e282f1b3064dfbee436fa46d268e3d6744bd07b206f33655d7f778485cbede	\\x0a31a52940ac8091b2faffcaf22675b000096b170bf51518672c87109601b618db2500cb3efffdbaf6a070e96221388a4aa1dd70475fdc6fb60a25e673737f08	1609929328000000	0	2000000	1
14	\\xc0bceb2855896cdb271088b967e73930f24f9585f6383587376f21d14bfbda95ca483d7ff09b743b0f1d56032c38c05e017e2de98e61d0c3e75dc452d0b3a1e8	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x1e9188e28ace5035a688cd9ce1bb8a7e124ab0628dc821789e953d213a88e719a8d7845e06abb15fae89041583c9a3065ab2a65f3cffbadbe0e635d2a9c76868a29d2685ca07e8ca9579a548508f38b470c126a5b0741a0c93296fd71ffd2d546b33855fd97e063ff05c7b80b9d48bf12e66082c2503fa585633e2d19175b439	\\x2571fdac71425533733a31459b24d334dfde7b12bdcb866705505813a2180791d1df8de21bf1494f2069aa8fa249f84ad33b81f6886813b995d5affc37825f07	1609929328000000	0	2000000	1
15	\\x73683450627b89a79a3e66e2ca35cf6c3ff9fc5592761036ec6d6fa9d2d74da0eab47641e976e142bd9aa34152e1282ac820828cceb23f2b84030a58ee10ce9f	\\x8991b5307b4e4537d8c49aaed05c2f12dabe2947aa8806aec8ce8d0d383651a49e86552f3dd738778721abf3e07b0ad3ba6938aa2061ad66260a785f4f4f7d2c	\\x83841576e3411bb264b7f5ce1c5c25e3cfed3b7635d5485486aa515d6b9a1b22b6dc4c30a3239785d8940156550bb16c57239ba67aeb7b8c2de3a8cc638f08188d648a3524f57acc0296b4d5e9911b288ee74fa22f8f6189b30affee2802fbbf0591668ad9b4410cf54deb34ad5472d1391eeb09aa1ac118d568c8cf11cafc53	\\x360f93e3fe1ab6e6699beb8bbab7b48ce6d6d54663ac889e1685770051848467d7fedb769836774b89ec69611a15e95f4ad3c6571f8e9f24453ea8d67bedcb08	1609929334000000	1	2000000	1
16	\\x6eddb3fbcc7350acf7a7e814d18b27ca2a130980a18c7a8488ebc2206ba6bdc29e52210b801aa735431d63f02a3e6cbc29954d2608cd78d93f0f29eb322da038	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\xa90192477243522f0377cd73f478c4d126f0a10f98310deb48290a6ddea8bc74a6172536aa0e4971a31482d13cb16e06b07d7f38fa8ea06cb485148409bed370e640bdc42bf59d7bf4ae9247afaafacf914f728fe0966d36ce0e3f0094d303dd25488471a635ef093f462e32483091822cdd2232a6a9c98f62fe04f2a29f1015	\\xa398aa0a3022dcd6de36d21962079c5dac8c90b7e46ee5957ed2e828d8d29bca0e44b6d5ea390fe2f324ca3f3aa90b37ccd5943cad7894a9b719810b4b2d590e	1609929334000000	0	11000000	1
17	\\x5581de02bac1e738fbbf583ecf566405ecbe0e3b59dcfe7fd3630a821efa577c4b787c2eda59c44cec3cd69ac7addf66124868ce9e6bff7a46847a0d6e492117	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x2edcc07175ed0c5a741a1678b0cf4a885d7f7d49c2a1efa4fd374c5dc3d3d975ffd2d666014e3856f96965311b31c8e8cf51c45f32080bb6ebd9ac54f27a83ad51f4eb0aedad2c2ece8c77efceaf65a51833853281856b60423ed1468589cc36c183fe6119641c624e413432105bc695d0859cc7037601c5fda0258c48015e83	\\xc80c264dffa72491a749617e4ef54906afde6f8b1e419d2d05208d4b226e8a1f0425f7f8744103575f447041cf6910fe785266b95f466fd6d42e60eb2d27a20b	1609929334000000	0	11000000	1
18	\\x27f83671fdf365a837b922b5401b83f1db63193988004849d0b2798f9da1a9e16ed4ee51a3f57de461c5aabe32d94e78c8ecee82eb76cfdf8a63369b8629d16e	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\xac69ac04aca57c45990842ba1aa736e8fd480688fdaaad1229464dcde59e9048b3a6c72fe0749bdef9db66f387941e685cc05efeb9417a9fa0b9c44993ca3e2a06405f7818e0a7b4acc8f19990c2fa60e90179ed48ed953ec54d2b64c82523c95c1f246b9ced013176ed86bfc31bfae8591038fc3fc581b35b7d2cfc4120b803	\\xad319f41e90c3c36c24559f4b5ae55b35e238b36a8d5fb4511ff698f5abe4b905fee24ff7731322c2526d0fcde8333d4b5a42b003e88111e33b592b19dcad901	1609929334000000	0	11000000	1
19	\\xeada240327b996c8e31e2fd8109e64c1466bd28895da416c00c9d3a98aafd28d373104d9a9c520eeed489dcba70aaff1dfb56261cfe268fefe5e1c68e12fae3f	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x69491decd55af62716bce7bb221f2c0270fbacfc9e23b00d5582cd9c4951a1f209455f0e6e7a98aa5f685f73d487e396605219a00de14fb27352a94b09b7ae8e982e1822b4f12867c8e9c2721a32c611cc5ca2d104a73f0a56eab683fa74e279251163a0068553dc87a0bc28898071aa146c5607350a3826b42d084b53da9109	\\x4e6b5c52e6be72ca8d266026ec94ba1d9b2c89b6bd68a82e2b59c8237b59c257c514ce96b37b10fa0a2c1011aa35ab02ff8d013e5fada9ffc04c4e7408766001	1609929334000000	0	11000000	1
20	\\x7bd652876017b95e42f72e4b29cca4dccc1e861334fe762e72d39e898b90f78f2a020640ea1328352f1244e0eebc883c745d0def2a09c1e545f2f5e756f20e70	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x0300f985283adeb5c9a1e16b52f6fc4c0ee28a56dd9996e2effcf86c6b6b30fb97ed84d80621bf9f831240f790190cb1bd851bfc3ffcf02d0a51f3d27b180cfc86872bc3fbf6a21664211f63ef24427240f33f179d53530ce01d983b0ac89e61e598471fed2f03475b35d4953a111fae118b403c310c441e49186ea4b75ff427	\\xd8beb655b4300fc5583c84b75cf968427de1cc927f8d9506c43f5b32e7e09e05e36f45428566473205fac2443992fc1c68e419471e416873afa131b96b990509	1609929334000000	0	11000000	1
21	\\xe237a68308052a3bbf817a19eee590a206a4c116506bf57e1354b28ff5488832c0bd04f941b7de5cf2cf26f7b1f30dc36fe739adc3c2ed6a2d5b74c5abfe4d7a	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x434ec73ba7511292f6a77c15a2aee977e6888149d169e34237f6f71c816cb3cc7a91c1d12a6904bef0abdcc6ab8c31b2455fabb562e35f91755e33eb17a558cf8d526b9aefedb5fea5f6dc4bd0a6b366d058be711291533eb6d71c49335c913892bf4f146557ae2b67535b020926c9953840a9cfccbefc320291404ed58380d4	\\xb8b96cf15708820ace22f2ef8b8bcfd142f16fa384ac8e3df0fa011f8decf352dd92988418b1d80ca65988d64cc275ba2a435ccaba9350aa20fb9b70d4696301	1609929334000000	0	11000000	1
22	\\x1857189608cf0f4d81fd146824edc98f4a556f58797ff78131828590683e8c8b2214c61ef87c12deee742f2992295bd45a4c81451fa9fdab0bf604193de40b05	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x290489cc7440151d6323a659298cb73b95a88b8d09e16ed8bd1d4eef0d46aac742851c16f11e2e2a8c1b87ccdee748004265343a22e8e036d020750050e2407d317dae11c631b2cb109f320360aae04f31d579a942776f9e632aa91cdb8f5422b6977a9fbac7d2642e2f8e5fddcea69e26f72830ca5b7096f4e045011d636dd5	\\x7c8fee6dc7198097dd10567d57cdbab406251ae77ce818b26722345f3bcb8802a2e691ea2b92945ca71163b029a6ab220484ebc940ae45410f73f7dc36290c0b	1609929335000000	0	11000000	1
23	\\xfb42366272e8f0379680eb5ad1ceee161cc8a18babc50ca7cee8f11fc1e7893487ac1d8a0f48bd7aca036c1dd392c2fb861e1d14dd7fb67a45cdaf2f46e366b3	\\xcd33331d85fd8f03f38a0534f07dfe9eb4ed984e8f1b038ec3b20c425ca601be18eb19b85e35714fffa978bd951d3a488b1fd0d347a52ba7fe12510e42b62c4e	\\x17c73e7219bfcbb4c6c32aaafcb62ad040e29c8c306df75273a343a12a465a4cd98361769675e352cf3a71fb5e509ee99fb50fdb1a7a07f6815ccfaac9a8d68962342bac335fdd98ad49318cafaaeb418ad2eb843b0685a16c645391eb630476a2431f108581ffc1a18b2e33e3d9665c962faabf565a87474df356beb68d7ec7	\\x0ae8ec086c1c759c3244b450eb3de614a27e13ce8479663a928e75331a2608bfa0d106f4b121924bf3d6b65e0ef71e422e3183cdc95572465231c39576a46204	1609929335000000	0	11000000	1
24	\\x81bfa02adf7361243a61039999b03dd5600cff4669b5ca706329e2bfaba3ffa5a2a9a5c8bdf1a2120a52a608c88836ed99d430f0d1168ad54b44e7faf2ffc36c	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x65a5b173537e95f99238c21298354cdce7c87b51fcfe9b12687c0702997c581b4ad6f4c118827fedf6ca1b5999333e7bbef354fca1f120967bf6186c287cc9815d56b47f858fe4ad3a6c122ae28acbbf5e1a26e4e4e727cb5a0701b28e6488132496fd139e0d8d11ca6b08fee9015bab460e1a773fc72c6cef0778ef1f0a6f23	\\xd20c52de9ec7fea1d234b13a8b627515fa6c47c28a6d205d5c284777368b1a9f020d56c46e75683dfa093efb9ac48adafebc2fff8d7a66680177f84610375c03	1609929335000000	0	2000000	1
25	\\xe1ac3247c06e34480a04b78d29365c95a9e66790fff49bb91c68e958e17f9abd1f47bc7f0e0d9a1c1dba444543b56e8e422a9c3316b95b5baf3febb5881217bb	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x83613d01e9e4b90c3e1888366f950697f2ad98ecfc95cf3cc2c9a6121fc5952c6e45411381ceca0f2bc1df99a03ef608f93ef6adfbf70cd3762ff0104fd140e22c00e581c797fc041b32e0d2d961244fba56b4e7c35bb31fe2a014926cc97781062efdb4d10420373ea7d2132c5898b6261a1f58ff3dd886ec65aa0c0e4ec2f7	\\xb4653ca6bbdd0617a9d71f43070f2b68f0ed9cdb8ca2fa4d8544acb921d8080e508a1656421a43f7c066ffae2922cb22d0738f0044c56b214bd43d61de3f2206	1609929335000000	0	2000000	1
26	\\x6dac2596c50f9d733e91335495f6d10da03c559dd78badac9be822fb481e04cc0580fc63df6d2bc646ddd616df7531784e404952965ed11038b7ca203ae150d2	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x86dbb5829a2f49dcd68e9ad4d28842ce9dedad901e1bd80ba72cff77862cbeed3be02bed05c6c02c6674a09129e1da36d2de635aa29509509af90b5a500501fd220934555986ac2338aaaebb0d0c0995f1a76e77c1c5fe0eb2e98c23c700377924ddf54b082b79f674ac76e2f722b5da9752281309b51d83b6acd3e8789145c0	\\x24a6b924f1cf49314db88ec5991ff7ef16e6d884f80f3f827779c8e69279362219e5eceeb827ec8f91ae4c842c3bd8abb32ca1e5524ec54f87b4a13e5eafa701	1609929335000000	0	2000000	1
27	\\x19b40eab7d1e200d059f9380d861c28434bbb7c7e9cd13276588b64fd3aefb3b86b8a83800be870239542d2743c6175736b1cb575ef728976d8fbd13e52e5baa	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x0e3c68ca888c698e3de2c91f33a81262b3eaef7a55805244db01784bc8f76c83a7d04877a13e59ee5a9328f3a3d8501c2b524db9081251fa52e77f408d09664222bb6fce2c1dee18694621cfd25d7e3b59dd1430c5070d5320800defc5cf0ce24df6f25585d29119b517de053ea81d53a75dceb2689b3c6ee4ca175b4fba0548	\\x99b0de2e1955ae6d4c5a8e12c3c3d992368846a6a6d36831ef5522bd2b574531dae87c3c98ccc7a49c3119f05afcd6cb9fb228fa95429af9227ea70684fecd02	1609929335000000	0	2000000	1
28	\\x48a72dcb641d49f1fabd2b61e193f8fccffa41a250318c89f6cbe5f4069b23b2ed5862efd5b36cf3577ba8b6acdd5281dced801e6e2939de10ef4432908a3a2c	\\xb6fded2b8e440cc1f20584b6f46b754f9fb3a8d678627bdeb37904c5a2cb8c64b59beacedfc41428f1a927935534b7eac3931e156ea7d20b6b4193e99d48e3ba	\\x0a02a214bedd12159be34000522573a26e6046027ad8e1531de8d7d8b4fa2b4c2161bd98d3cbab221a5f307dc67933e761d491ebba81dfc8a19f08b658f70bec88034ad8197ee98dec918509994c1645e89c50f35277e2f7f08158a97b6bb72854d02f531a72bb485817e34899e7ad00cb583fc7bfa9291301ade86652b08676	\\xd9ecc2c530c7e664ee91802528d909854990b917113662fb33bd2b71a4fee5ead4f50537a020e7e54fd307c4f39df67fef74b09c1eb7bb9381d9111623111904	1609929335000000	0	2000000	1
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
payto://x-taler-bank/localhost/Exchange	\\xf9e67fb2503daf007e070dd2d3bdeb27fc7ac1265a322ae44cd6cfa5fe58820138fc1e2b93b8e65f344722a6290c0fa7abf03bd9e60f17c2e648bd3d32f1f304	t	1609929309000000
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
x-taler-bank	1609455600000000	1640991600000000	0	1000000	0	1000000	\\xc0918c6acffff8c5760ee8ed5a4a457339742a951d10519120287bc2db5bd9468589d2da6af00d536f35d2f2f4d5f96ce5fc9f0e4d7d1c3bc0a2c0513f277207	1
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

