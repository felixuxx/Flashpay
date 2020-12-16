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
exchange-0001	2020-12-16 19:59:31.281532+01	grothoff	{}	{}
exchange-0002	2020-12-16 19:59:31.389063+01	grothoff	{}	{}
auditor-0001	2020-12-16 19:59:31.476911+01	grothoff	{}	{}
merchant-0001	2020-12-16 19:59:31.614215+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-16 19:59:40.467723+01	f	5d2d690f-ad16-43e8-893a-e01f5c76b75e	11	1
2	TESTKUDOS:10	T33SQ7S0W0NWYBG51A88X2B9FSFV09BXQTTTATXE7KHYDX09Z6E0	2020-12-16 19:59:42.48506+01	f	51df18ed-4af8-4e9f-9867-9b504aafdd98	2	11
3	TESTKUDOS:100	Joining bonus	2020-12-16 19:59:47.448601+01	f	c5ea7768-12fe-43a4-a3aa-962d2841bbf6	12	1
4	TESTKUDOS:18	FBNMBDHF764T1CNACNHAAPT7AHCH43D84GT1HRE6BB18X8T2W1X0	2020-12-16 19:59:48.250494+01	f	3fb68215-dce3-410a-b2d8-fa5aa7715091	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
0eead591-8963-44d9-bda8-b61389d72129	TESTKUDOS:10	t	t	f	T33SQ7S0W0NWYBG51A88X2B9FSFV09BXQTTTATXE7KHYDX09Z6E0	2	11
9ebb091c-7783-4a72-a883-ef1fb6febf5e	TESTKUDOS:18	t	t	f	FBNMBDHF764T1CNACNHAAPT7AHCH43D84GT1HRE6BB18X8T2W1X0	2	12
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
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	1608145171000000	1615402771000000	1617821971000000	\\x3e0caefbc826be4c81a93be5adef6c9a02a06009da92abb0fb17feb6d0364591	\\xe045a1f5029ce53b6f7dbdb02a36c171a34c5b6101578e065320763da4ae1d9bcc9418bbe6e9066fe6c31f9f311dbd2c8146621d5bf9d1a325693afea596700b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	http://localhost:8081/
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
\\xa1b0fc69ae3ae203eeff638d6d3754c1dc0186e9464de53d85049b7bf3e356f2	TESTKUDOS Auditor	http://localhost:8083/	t	1608145178000000
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
1	pbkdf2_sha256$216000$2lJOyTKRxjLp$SMCenWQFtYmJqt+fjmOtI77lG2czj4ofL3UiOrMwYTo=	\N	f	Bank				f	t	2020-12-16 19:59:32.018847+01
3	pbkdf2_sha256$216000$9l31has8kmvc$ySc2fHk1IYTfbMjqvU6L6yf3UkydGHECFh7zVfVOEoQ=	\N	f	Tor				f	t	2020-12-16 19:59:32.21582+01
4	pbkdf2_sha256$216000$1jbl8U6JYv21$KX3VrZ/Axifq3JFKCuRm20BMixUiNSR9/xt+/XDkGv8=	\N	f	GNUnet				f	t	2020-12-16 19:59:32.301138+01
5	pbkdf2_sha256$216000$8UFNr06x7cop$OGghYcQ40JOlr3mq6zlQEb1vPJ2kiq7SY2OPAnMNlhQ=	\N	f	Taler				f	t	2020-12-16 19:59:32.383969+01
6	pbkdf2_sha256$216000$QoHYFlshXj5W$XZpaOZhuEMmiSz40gap+Gdck7nVmlGnOEFtARRXQzYc=	\N	f	FSF				f	t	2020-12-16 19:59:32.470254+01
7	pbkdf2_sha256$216000$cHle3NFnQlWb$EvfDTLgpy3aBb82hr8E8c0zMbkiCW8iXJrU73ikth24=	\N	f	Tutorial				f	t	2020-12-16 19:59:32.57304+01
8	pbkdf2_sha256$216000$ew1ClBB2A55C$NN6lQtlHtSQvtzCjo5AjKvZO0oayqh8oUhX3TPslqBI=	\N	f	Survey				f	t	2020-12-16 19:59:32.685997+01
9	pbkdf2_sha256$216000$jamaqlroyUcx$6Sfxrbpu/QwEL9jpnjjVLjlBElJRI/vAsk5qN9h9XFA=	\N	f	42				f	t	2020-12-16 19:59:33.169479+01
10	pbkdf2_sha256$216000$LMi011aUeA3p$lAGOiihSvsGtdGNXt5I+YRTXU2qE2ajb+VkcCj0BmTo=	\N	f	43				f	t	2020-12-16 19:59:33.656551+01
2	pbkdf2_sha256$216000$nrwJnpT3XsW5$dCphNujkGWRAIU5Sbm6Gh+xiQmLyEnMnnao7tz6XmCg=	\N	f	Exchange				f	t	2020-12-16 19:59:32.133538+01
11	pbkdf2_sha256$216000$9BWhGevqGOBb$QJMTif1onA5HmBrYIdnksgfisKdkcsbX5E33sIX0e9k=	\N	f	testuser-nvBJYNQ9				f	t	2020-12-16 19:59:40.362296+01
12	pbkdf2_sha256$216000$gvUdf1EuyFMM$fjo3uS+4919Y1c9GrQowf+JIZ10wbvYZYyLQtDz6SJM=	\N	f	testuser-QbgOxKEP				f	t	2020-12-16 19:59:47.353635+01
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
\\x008061ebd6e2015c0257c8cc73f494c8320633f94b0d804e6e0fbbc1c4a547c33ef9a2d8f34e5a09fdba7a2682c895c51700843b3a73b8bbb9db0d974ea9e4b0	\\x00800003c947c16eac576dc29756c2e8e29aab14d2831279bca7da213af40fe505790a61da5ec8fd8487d63c66058733eb32843d033892b681ddbcb4a98305c39993c937dd6305f54146ac877ed2916b4d8f4987bfbe79d3216f926eaf010134b5542a2569e136adbb1c8d4b6cf17924eb3ed57732223cab7dda92beaf77f9009522ff69010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x23c8dc1e84fd5ad6bf4a0aec2a297b3f93ad1cba88ded05fd15b405a3fe8680d092b4f39a0c0403c57f17d2770d9f6ed55f5ab5da6b1f812d4c244fdbc4d6c04	1615399171000000	1616003971000000	1679075971000000	1773683971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x05589b2b1b54e56fa5d7406d3f4229b143467737807a70d83f8a6a792c26241cb6d3630dc15c077a8d2c5217b946043bebfe06ab8cc086555b3e8f42a3318726	\\x00800003c41acfa7a735835e91e30d1c3b00d26e960912c16192ec205af9d9114c3411e991690e6dbf4eb47029e1416974beeebe1084d484bf0281364ef1e93f9c30026a4ff3578ffcb4d20d620616b4175ed729a5d37961704b840c52e4f01872298d5804b74794155944547c53aaf1b1c2781cce6d74865229b9166d5731da54764405010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1ddf3b07548244f99cea7fc10154659ba3874a42e29897ab02e10a0aaaae228b69a5029b03938eb29e9825b12fc26434b0a00c3f3370456b64ac3b415bb0880e	1633534171000000	1634138971000000	1697210971000000	1791818971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0820d9c212818323451b2088a6cdec626d42704140ac9e5dabcb2fa291754fde1d9462d292fce405e633e2b5f81dbb0d98ce40121321444d9eb5056fb3bfd0bf	\\x00800003ad60e3d7f9c776f41a60dd3b485e733cfa4c4c6ef2fd04bb1e462ccaf40381f41a108d75458bda0851c5044892353891f3a23459c93a3f4464350390efee2cd5e0641fff3659d35cc96be21ee1977660f75801fe6298a7feb624f4dde6ce3a8470a9ba7185f445761184d7476abda9092a0582ede374837aeca46ec1218486ef010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xeb74b73547762469c051fb99fa80a84b0890a5c2494658aa6be2818df63dfac95421abb40a90c3cf76292b4863bf72a77c1268a60e0a79869cfe1bcc6e967c00	1631116171000000	1631720971000000	1694792971000000	1789400971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x088cfe515d7ee3a8277237a2530d57ce70f2b2dd8ac9e27d2be505f256b37133a91d315fa0c6faa2edaa8b3a0a9fa8c7d83a089cda24852eb669bdd95ac7029a	\\x00800003bbae5a8bbe281049c7c040a71ea44c46bc1b9dd55a67f98c759c0d21d15626c5dbc5a365a96f8cc01c3cabf6a778bde105ef54533994361d7eb7c646867da5eb7d1568974731706ed3c89efa8831c9d36e4135893a6a1cb9d19c57339088f3428c6de2e45298d112dba61f4e666405638b38341162f1fe702e66013efa18996b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf637b0ba9ffcfc414da577f2875e88b8efee618ece27edb4bf7f7add6766a11d63c8f7f63a66ca43b45d2380b8715c21bd2419b34f3540b49e070ef80248d70e	1615399171000000	1616003971000000	1679075971000000	1773683971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0bc0859aeb110fc843ddb9e1222c74cf44adb25d17751cc892420cffbd3560c65115a26a9bc7e5fbc2d0936205530bb1308a53a0f91f255228bcb8618f1f0ab9	\\x00800003a5ffff47e381b14f3d2cb0682e0e28f5bf94f928aec65a04d3436ed62c3d66fe3d37189e9b9812f7ebc6ad0c9fd757563513b11201efbcee10630550666d1d7e7b760c0d2c76d2d6b6ec87cf1f38fda3394d08437ecbf373fea36628e1fc9620129a71b4904291f91a236ebb0bd3fef5ddbdb990208128f4ac9141f83ea313ad010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x11ff68e2acbc9f160d89bfade590c308af98077fb0557892bc352040678e0c6bcc09656fb7c57df86263cc13543f2a1b36e466a384d9731be96aa0d5271df203	1614190171000000	1614794971000000	1677866971000000	1772474971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b8851f0f592a1d83ac83020ae2f938184ef32e67e16db418820427026d417cb232779faa7c8dcf7b27277bbcd37618b485fabe616dbd9d9c3fec79592050610	\\x00800003af284ef9ee6a00a106164842f62370b2c917749b21330c5538ccbf134bcf5a4842bcd561bfb4459141dbb3d262dc34534306a6aea78d16d65750a9d94c5d585726b474ab0918190b71feaab7159129d17065d47f9a96d58afac7a1eff6140e4ee44b0581607cdba9bb6b867edfc3ac0fde1eb3b612db39b8c484ee56a3bf3307010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x696ebf07f18133b53d8a2d9310a486f059a558bfdb6f683ee742faa7f47cbffbdb2b4fb6c9f5d9c1b3f99413e67a1d25fbdb1b30418f68d2b8e7e09c29b65b02	1620839671000000	1621444471000000	1684516471000000	1779124471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0cd4cf397a82ebd7cec352afe912637f97e0459748207edd3fc463e57a533952a23fbdb00b260a62e38a09e5df5bc9ad72465fe2e4acc14ce9352f3523d25737	\\x00800003db0c071d7ec8591d6355cf20caf101def9e93e8ae697c49656c11674446cfc46c319d175e21f9b30ec78680845eb8b7674e69a61a2a62d5f4d988433537387dbf07c5fc99009a93fc681feea78016778fac5e503d0ba82dbb086e88c8948a7773f674a547bd1cf16652fa4b0575835a1cabdd8c9f282210ac461c11c74db66cd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x85be16cf4715525882aedd712e9a2851b218e3488d68411598115e316ed662bf39b087ac41dbf93be614908a8ee268f1f1dab55656ea091c55dc3a2d4cef390d	1634743171000000	1635347971000000	1698419971000000	1793027971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0c4c926909b49856092ed55113bfa099ae5f8f4151bb551f3c0d3c3f2783b9426ce180b42aec676d3d64ab7455cda6cce2054295e934f3ee2c9eb55eb3d1eb50	\\x00800003accde33cad3c2728f85f718ea70dab847a89204e84c2601847c30af997f171e1c57844de725f9f489be2204ba8fe5a44ab7d92dff348cedddef44f464eb632a10fecfbc55b563fdebef835bdc0c3a050ab546dbc6ea6ee783f0439ff5cda828277c4f47325b5cf53301f852e5cd7e0068699b5fc726397a043ee1953a023ab63010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x390ec6555fc7697a4e1cf6b4590544958a41c2d16a15370d5640dfbd6853dc6b4cf12851a1b4e17728c865d63ea1864b080b3d537b9cd64aa9edf2082b7c960a	1627489171000000	1628093971000000	1691165971000000	1785773971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0d84febe2e7124045f269ba64064c271b21e189a77196ccba5b7573f3cfad8075b5cda345928d88f781c7b4468a696a8c8d0129c3f5372df1eaa27aabb1e32f7	\\x00800003edccfa0128fac0902483d6c62a9c6ec83024d84d40e8c4621697e418f3fda01ccc7a4e4af8685e26d0c21bd163730f724d70fcfa2b23837bb62a0a15a43120d44c78670ad68c1128c15fdd5a635cd969c3715e37f7c42dbdb1f06033d212609705b29903174304af2c6333c2b17501f945b0e1d94d253582a2ac742bc9319873010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa4d66d594af99a1e9a0de296985f8d506788a4b7a724ebb175a53843ed8653be17c1a3a16dc057312b21f8ce7c0b00d74544f4837f58542672e1e1cda5cf0805	1608145171000000	1608749971000000	1671821971000000	1766429971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10a0cefc151e874eab76e2d2937816150255d6f06245e6c59d86867df9e8344b488ad865b09f6d1c3def9310c7b922270004164b871fba34410c0c0aba3c6a7d	\\x00800003ba90fbecc8df95039df8cc5080e896880ddb1b674d4b2b9ebe34ec7d0f4d4041877592db57f2e94cb0c5424863ee3b68a113ec5e3f2a9fc24be84a57ad435a97ab876895fdeed8d4dbc08de693b2732ec5782112ca0fbd5ee53e7809e05a74f407b9d87780a00dd5fcded3726dddf3c5ec1add6af7d3faa27e6842fcba8a5a81010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x473349e0fde417fe9ac06f7a472d89d366df4f3c748341575b06fd6b700b45673f4d14d7ae9fe0d6dc6b3964349969dea6ae3167e4b6ca6f0801173898074d0d	1608749671000000	1609354471000000	1672426471000000	1767034471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x123c92cd9b9675bef1eb148253940e41718564f9282ac3ae52f427c3005c11ed2ebc3537474a4fd675972d19b04502cfbb3e933a5c7a879bf931be3df9097739	\\x00800003c6f09b98886b4537bc43e31728a050c6f5796d2804d31bf1840d3b7fab700f6803459b52e0d1a3eaddad08dab2f84570a1634cd28c4ad461e0832677b77f70153141f958d4e1296c648a1fcf24e51356da51afbb12c4a3d012df1fc8fa809a5a3b8a85055b244fb1f412a3b141289c16f7c2dd5957a671b50b099c05075c64fd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x41db34e893354069ccad407aabeb8871877b91010603378d871e7951382805e99cffca21b9f247685bde5160c230fecefdf05a4f0a0645fee91cf06512514c00	1619630671000000	1620235471000000	1683307471000000	1777915471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15b01c76367103a687b4fcd540757751441a1c1d6c987a6a29e12bb6406874b1d1f478cc9831ad77c9984ecd1261f05d139921c1b61d8046df694b1a9aa7c0e3	\\x00800003bbbe1286ce6738e25ffca01675f3056a6f25fed43f61667efd09437a5c6214e3af7899eaf778157e2934f0fe60e69d7a34fc9f5ddac44dd7fbe6b60b1c652c2b598ca43ccfe0c7cd0ce61ae2c8074fcbdad07678114aeba529b045821b200293e2f6f014e161c1046178a8a79272252bcff374a1f6d7035bba6d1f110dd810f5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x200eab396d67bb6196411d02c099201626f413c690f56d5e2fe93f0d60a346124c5484394f406520f440955060fe09d526a3212fe84e73bd6c542e36eb70f40e	1637765671000000	1638370471000000	1701442471000000	1796050471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18b497e56f748e744f111eebf673ec072db1941fd35d9a38209c1ddfd1198ab90545cf82dcb9d6a9d4568d9a174e7ff5c795f0e4452877e77c3b8e1a24d3b01e	\\x00800003e962d3bc7c11d274f0c0ffc7993b4bbc1efd92ae23ab7132ff058f9ac838958a42722ceae0e7da8f249dcc39fdb920d3fb37e9faf29ec6ffeb7d56ca7d0e8ad9dda479be66f123d87c44363427906b3b859b8ac83a9e946183adf1dd48a194c551036d24da831ffa1faf2bf9de38583de3760f9273922e8831b9229f0448a4c3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa886292cd4228b3c65efb8c29de34fdca34061dcbe6420e89dfe6bce360556329721e72c5bcee0b1603f431b355e57257506d0975bb13093c63ce85fb3e1ed01	1632325171000000	1632929971000000	1696001971000000	1790609971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1924ecf2f4bc9227c654c52a7187b54680a2c77d6eaff948fa12e30c31533af91a9dc082c8657a0291fd0f29409f94890b27af40709f7aa52ef27cf8f6e06765	\\x00800003cd710c522a628339f670850503529fe7396ffbb90106cac655c2690ba25b779fa8d8589c0e259760a5a5c9ce785234c656d70efc1c33b686b90958cc49a0c6d10968fe64016bdca1278b7f3f22ebeb856758348514d1b3387dbd7e0ef07eade1167cb10c296182fc29384d68a73c2b70db0485fc045bef9056fc48ad79b8fba3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfcaa2d126efbcfc5dda93fd3cdaab1b91181f6ae323fe8aa641f300e3e045dd9814455b4ca6501d1814950c00ed233343fd700d29612375cc526c571c8e39900	1620839671000000	1621444471000000	1684516471000000	1779124471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e34b9ab9e06e2ae3fbdf47339a8b84be785a53a94103b4b72c4c98808d56ce3271aede8989a31903c4a243325b1945e2c8fe603b051d448efdef3caaa4dd6c8	\\x00800003cde5036b223aea15e8c8d838c3f388ed3a6a49b048f6eb36073e375a07db92e07b89da17a373241228c042ada7046e34d5cc76b49a731fa5ded98967a877441c667bde3a4fb7229ed166a4020720df2615f7f5244518f2d3bfdcbecda230e017c523fb6509a73c209381610c2109f604595caf411fc61218c24235d13c834f25010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xca4c53ffe091a465959c6a52a5b6996c310f96d15d4f936552a716ebe04c52bffdb9d64ede2a2eff34469b7e198a9fcc9f63172dbb0b2a41e90a837fedc23909	1636556671000000	1637161471000000	1700233471000000	1794841471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x22845e605a8a19579c592f588fd90d6b6788b00813e1d2fd64cc83b2b7a8b5fa6d2c473e6504406eae3a12f850510c2ba7bd7164001e730167c762d257c1a16b	\\x00800003e0556d5356df9cf45e1bb03ad2e96434b4c20afada05d712ede62b65edd85ca444576125842de0553496a2d87e593c0d3009cf74a53fb5c763a2ed7dda661e67f3ce2622626053712f948ed54490da3f843a63234a5bdb626fda9b5a8a22efcf16377bacd1fd68eae6f02769afa3f48c9d75c170195f9ed72b63ca22ae47347b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9ece1a9bb487b9d1bf4e12f28d1b00c0f6aa0f79a8bd0926440cba30b64fc5f688a22f11dae1f344a839c8fd6f593c4b73b64d8afa6d9767c3d4ce5427f5530c	1612376671000000	1612981471000000	1676053471000000	1770661471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x24e02278cee5003e405a87d71392bf89749790759b167dfc67da5e959fecb313578a86ed96c1ff173d88097829c44651874821fbec9e73ff8367515352dad4b8	\\x00800003ae7891ee36adcffa7036d78872545a0a4ceb2e1358276195ff2b6a239fff79313a3a3e1f67e43da31624be40f439912b67a999689a56601b00bac86a0541af6c6f7d371b3f42b21f9847bc1a5daba890e7a6089f3315c0ec56f96c946c56c9de23d03c4407938f938da6c508caac5000a27f6681aaf1b65b1b4769ced1968c8f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xebd60974925063dd647a7cfd9a7b84b472e8cbc6d1a257abbbfa17d168d0f88cfeef7a9b44817ebfd6457b0554e18c91eb48d488baebbdfc2e60c2a59f8dd501	1623862171000000	1624466971000000	1687538971000000	1782146971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x25782367d9c627b8e61a965a87b59a8995d794898b37baaa8715b2022464b21a856946fe62eed3a1807817742bbcfaea59bcce7b5fee490a8f857e9e0c5e61af	\\x00800003b7bc49a124be1cfffc2deda28fffb5386e848612b52162a33f24a2b1f36188da7e394aa810bd4d6b076eb45e41eeab7d70e5fa4416b7931d6dcf2e593212603217754c6a3140e4ccdb9ef06a678e9f6d173be61cc260a9e66799df5cb31abba66ecb2eedbced9de38ca618ba9726ae0ed13ec0c192e6d3b1f3cbd63004f41f5d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9d6b7845652e7e6d5bf2a2d6ed8ab4fb9943b530ab57cbdcdade6bd474774c17d493eb67b2d2855f0d4e6fa7711312ad864aceb02404b1084a58b60163284405	1614794671000000	1615399471000000	1678471471000000	1773079471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x25b034198755e22f4635c55b8a0b87f5a37c78aedf60c4bf898ba62b3bb3cf16c498992c708af674661487b9008c727bd770a6da429f89ba839e2bd9f6ca41b1	\\x00800003aee633ba6463fb12c3c56239b1e09adb8ea803a0568765affe2734fe79a1813cc909e067cbd7c1aa330d593b0e1d9c9de067e7f35cde010765f1a7f622b77acd52664c44df06ca4d499d0e3a20c95e95a9d87b1f574dd8af0f43e24d52644a5457fe6dc7da82cb203fac0effe451c3a131e6eb8a487d5e855000d24aa4333655010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0fe8b8facc14e0d72aaf714547040f3ff105ba47da259207022e9ee450576ed6809a11ae958ea25b47718f90007606cbf26be524091876f6b541ee6cf09ad80d	1617212671000000	1617817471000000	1680889471000000	1775497471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2750a25d0b820703b2f7d333b4b4e9927964a4acce63ac507b5950bb540bec39256e582c97d8980f92d1a2b76d61b5a44b6011d6206e4910dabd9562fa2e07ac	\\x00800003a8e577d4ff6edbc1397c839b2ef728b4d0bf06857050ddc787c85343b187e12102b79e615f365b7730d3c848bf820f81c17366cc53f2d16a4d404086d5e3f00d609975c49aee776fd2a81aa15d44c5684c3c698b868c84171efd7270d72afbc461b7491e1b970a19d126c0493352d444394e8db5be95d3b29b221836aa68eeff010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0e1dabcb701f92089e6ce427fd7cb6b6ec68b1fbd548afc8a0187080e584bf0e3a91df240eaf634ee2c980d72f74b11ce1aa28a0c120fe5235b72960f3bd770e	1635347671000000	1635952471000000	1699024471000000	1793632471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x27908d3486eaef24850aac156be5c3c1428c9898586b7c4d2a207cd6047c2051ea501c87c003af0e69f6254ae4f97ef0a78683bb461865a37398f7da8ba5a470	\\x00800003dd14387c8d56b326dfa3ce5d2a22d8606fe0ca95ff7bde05b82f19cc4d5c9bfba6fd582c5a26123795fe39129af4a6bb1d9e9772b70a6cc67d0ab19d2ce2b7dcf98c4b965e59e4c27443b02c06190899e7af3be33b0322c1c24bdc8350d74826017c97de28a9441a36f0dbd52f1a73b571b0ceb666f7095582a7836014895051010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7d100f435b2f2b4f355d91bff03702fc83521d5fcfa08b17828fffc153b1c39d2ba535ca6c900422095d14c9a6c3fcc9b5bb0adffc833acb1ab56f1d33512400	1612981171000000	1613585971000000	1676657971000000	1771265971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2760b66a4f0849dff35ac9e03cc8452a1ea77b86bd41cf7ff349e6c09b05e09eb325c4ba68683d7383dfca97c701f683dad7359e5d1db9a8690d71763c0a0f26	\\x00800003d2d003d48d61991325b49ae19c1f0a11c677f9af019b25e24174c8afc22847bfcbe3512f5a95a5356edf99bac7f6771b483968363dfd921c296b6f684796b8dd6f3c86c4df479502b84bcafaf4c85919a0142464be08db54fa37975579a5af9cedabf25b249f41ddc2b8bb2bf4b6dd72b3f46670627769cfa5c7c86b326a9e93010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x536125c34390dd36e24ec1d2d11b7c0aa6042327514d9725cdf769e2360ab2064ebf7de1500d24e259d2c0a88d6a08038a1047e78c4888572022f81a98f57606	1610563171000000	1611167971000000	1674239971000000	1768847971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x288c83ac0eeb96d19d45cef13721c4a5f9b2d30a11dd57105d31ff2c7d748f7419d8647b495c19c678724015fc7955e21506881b37d5676743847dcfd907faf9	\\x00800003c1345f380e76fb695ce895b8e0e1eca7376cd391f39a16743881cdd469e4b272322a7be7a4b3b2d69fa11f9071cfa827e1c8941966e346daf422955d1d9347abe7a957f0626dd0ef26041ebad015e33c27993e514fc0c1b1c0a5f6baa9b9cd92ed9d518903e6089e364d9d87736d44bb17e22bc875413b38f1b118529bc81165010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd8d30e8a1bf8aa74b897f54221c8d9cf9ce2662fe4880f9ee523f9192b54dff6148c23b26bd91a1d9c3ece0d5b5fb1512fe76918c5835464e43ff5963617fd0d	1638370171000000	1638974971000000	1702046971000000	1796654971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x294c5c05aafc78f3ffe76e1e5b556d4f117b426a11eeedb903f3927e2b07e65d289d687dbdb915c46e9de5f5fb841b4b5edf1e786edaa8ede2defc0b170b6e01	\\x00800003e173b01e75d290a5ab3565b1e4f864f0ecc68a33ebf7f0c0def55d742728fc28a3607160ac5f5c8561fc84c49d8dc5b1c30507b5352c3c18340985b8145c8b38a95eef19a5a7fb8fb1d2978360b9263d6999940132b5754d67e37ddaedd8f802d7f5ffe16e16ea2c57a1aa22387c14faf401701cfcf0ea4372cd1c00c5b95d2b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe165b0854920a91deb9a467bb98e8f7858aaa1a6893c465a4df5fe81d914e3a6e4be78ab5139074d27de188e6815ca9f19fe800b4caae7aa1818a18ca7e09a0d	1638974671000000	1639579471000000	1702651471000000	1797259471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2dc8c8eeedb5f8c9d9a00993a5e791c1d7d2a7f6106d498fb31aaf26a23cd885f8e9f34978b4311d71239d7206f090eccb1fb5ee96f582d95e913fa21e7dd111	\\x00800003c3863f7475162f32493d644988fab75c0b5d431eb50b98585666dfae1bab39d7e15efdabe69eb43a12962d390b2d7f82e053477f173d976c803861bfab65df51180649d09d42a5dbf01c78671255ff3765abd86fba9567f51a3475958393c9ce4a7e88b857699a3abd64e83b82415a0da217d2d4e7808b3a6f23b3fb30caa671010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x668dfc920b75f9ff2950d259d71c5558e957a7f6e4ed5893d50ac61ccedc6c409d5cf65b8aaa287f0297e6c22dcf9e8351f0eb951df7895cac1edb02e5144209	1626280171000000	1626884971000000	1689956971000000	1784564971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2dc0992f8a6778601d33b5a92d36f827d20f3aa56ffa094dba5d08043a546b44fb8ab28671a032b33175b9b6feba7aaba1eef31fc43fc1a335a80474d90882db	\\x00800003b8bc29c142ec3bb5b6ae36836d79def9bf9ea3596b653d6ae4c3ce95bf6667a41ca9f935f6d9b51509292b5aa4a10c158339de8fccddae3bffdb9a240f70200b3a9fa0722324f2cd59afa006cb58da60d4fee6fddd92a030d97eda5280bab803fb96339201a0c5707a3ad192b0c466f894b860cbb31a229cea565ae98554a381010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb0b612a6dd152fd467f491911bb581be40057c5ab2887fc8ccba59c6040a8ad032cfab37ca5f5a1d21721333c58aec76062076a0c96dca38c5a89942a8b54c09	1631116171000000	1631720971000000	1694792971000000	1789400971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2fdc0a6fe1530e416abee98034a9a3f0795f0913ecfe59ed2d27a97f8891ac18c15acc8bc551a99ee5802d371aee1a3ec9a23701d2ee3ff2cd20fe73f54c4b9c	\\x00800003e06f4f91e6446b10494d2f945d231e7677dedc317e109fa44d32e72c9ff16be64181950e15f21206f3a38c471b113e8431f09f934ca316ef3659d42ac0e822f4beda28f5f463c3751baf8c4e703b0df658ad3bbaf38074cbba07d9982acfdc215cce78f259dae2299e9428b271d25e72214467c5a76581390b0133e9b5b0b905010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xce1b0872ddcdb509687032cca74074eab3d12f0152eef100cc6a81b09297559ee5955f79e193868c2e0521ccf698a91a1590ca1686806676ebe94884f5cf9a08	1620839671000000	1621444471000000	1684516471000000	1779124471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x31b461f4aa3a7f5a4b910dc554ce7b682fa2dbc3905782b31204c5aac521d2bf947b33645cd806db4b1362f14142aab1d41f827118339cb97ad36fe281a5a3a8	\\x00800003e0d0940a48581130fa55999f79c1f490235d8c2e734237c2b91527226c4e8485b505dd86ad14a43f80da683727e4a2a70ee03ea47577dc08654002de4cb1ad84f0a0550cd813b17cb1945c584a29f09f9a585328833cb386b3bb8ee72a224107860f7ca442d84e0cf99a591f1034f14f689c1de63be40b532eeb846fef373979010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa228a46370df6a158a48210bbd16214e797b9760dce77c12d235b76ef3ef9e0b0d8869df6d36e7815bb2de55ae36ed2a42529c0b15afe02d297a804e05025000	1615399171000000	1616003971000000	1679075971000000	1773683971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x314430d4927a9fae330179ac98320bf86990d6b82ca78c2b51bb2afa38de43996edab1ed0265656757a9406001c06b75a431743c5436a6979007220497037117	\\x00800003de2a73b9f7dd8ad358cda20ecbf3de52c4dd558b7dd464b837f5d50a00bfba7771b86e14507e7284a6d17e1a00bad2b7a4463e47cf64c3d70c98e00147c616159aecb011ad0606e8c602f5068720fd360123dd8d86bdb6b51a17141e70b15a0e7c34aa2ab49717aa1d6764158a8a56a43869cbe3a67446a8c28b45800b4c0ee3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x05a97e7d857bf39822c8f7c1a6c8c0a613a89c25a473c2e7e402f17e956fa5a013a35f10da65db5d27e26a79a4a60e3b574bb254bbd1877b931829f412ed830e	1626884671000000	1627489471000000	1690561471000000	1785169471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x38f4150a2181124db7860bfaaab85786de88d434813dad8afcd7f6a91630b30ca2c5cf8a6a3f93b54cd26044aefa6f61ce7915a4da625a0e6b251f625b8f4609	\\x00800003aab85b75f5f24f5750a46dc78767ae1d19728121157695994cc0713c33604d280041896e1d2b24f433992baaff75976f98dc8f75d66df33136e86f3707fd81b2d94f68963c1548b40c20629f5d0ae7a2ba8644345a5cdd434a96f94400c2a27b26e2ac45dd9500730361206bfe55cfbd2ecd7db35101f93ec6faa5c21e9ef337010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd23a13fb2bcfd3e0fb2aa6191f12e1f2885315a3c070565be647876c3302ad284ea5ed2567f295895d3778859831de4209181d24f280f833386af324f365c50c	1632929671000000	1633534471000000	1696606471000000	1791214471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3a685b3503eac94f8931c56c3e049c1d778239445ff91471f3166b26dcc814843b719b3efee5d7a66a3d946bd2ee35cb14c6fd5d18adf9df09ad76b18db878e0	\\x008000039d13259687bea5ca8cfb7ace316010a0e7c90532a1b58d50f4780604cc583fe90fa8a24ec44de8b7a699b0b74048e0e82aef4dfca6d0fffb36ea886d5b399430f8269858dc37b70d508785a229aeac8d9b00a860318bd77efb3f324a0d6f57946d5ba3ef0086e0b6fcd80ff2e49ce216fa6d7dfdff1c5f4aaaddd6fa29741e13010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5b104381adadc8f3310a8e4aa998463a9a3f30740456967a80f9cd641ddec5cb84bed33ef0baec2efc7fb4b02eb3d72a38e32815ca06f117a1faa200a7a90d09	1631720671000000	1632325471000000	1695397471000000	1790005471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b04cf2c5294f7dcf99616cd6c1460bef904c2147d0d474f3ae2e7831317425d1ed7651fddde300732504074e188b013d04057b03e2adcc1da362e41f4818000	\\x00800003b7e911b3a843ec12e988450db81c7c0c3706bd8d0fa14f8c0436bb070f5b99b0a5cf320103cd2e03f677a43006e927247a312b4753bdf0f9d2e6bfef84ae7061b71e37c3b996f93964b54c0664793bfe5ad7d55f8e6817ce581fb91fb024aac48e8cb7f252994ad4cadb5d1f48f83f71992727e018e5132bc852804020a2dabf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2cc2324abaa79d7450d1cbe22eae13613d9d34a31986db109a009e4978aaacb3e72719898fb8dd0c8d0913cb80349ad82023edae7535c24bc4f741fac18b0d0b	1625071171000000	1625675971000000	1688747971000000	1783355971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e48bb7261b2f3e1dcb8b47a4e1739881a75b72040bff8483e456449f27c8d194ba39a1e21919035808cfea957c477bb60ec9069607d71cf6d9a00ca01177421	\\x008000039c0174148094dfb0fca9562bb88792621541c884dc5370fca52e9d10a884da6fb11ca83b346e90cf30da150aab29d8b5df5a3d5fd9da29964df1a98e5004d5ba872c1190af2fa20e7a03e52d4deaba495e5576202ee9bb87620ff0e94d48ac624c1c9e8ad0bc6695c4e610f216e64c7b7f576bf95db3f022427b4d297a9022a5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa956abe44aa80135bee6ecc248684e3b301cea227a7a4487beea22bb1e210f59b0f0c4b19d039a488b5938c073d7badf969b9946768d94a8bb58ff1b43bb3004	1620235171000000	1620839971000000	1683911971000000	1778519971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4090bc568aa5a6f0138b1ade29ec1bbf985451f3965e776b4e90adce9da48953b615c137fdd8d0aacba5b5a44b9de37074e7ec06fa4a6d97cd62ffa39e7c91dc	\\x00800003dd39861fb5714a2b4ae0a26bf4160807e3ba98f46944bd26b51966c108b55a9254477787b067b029a8cfd1d6269455f6a017206c4eed8ba8ec17f11f1e74e9560618c7e72471a22a173a3127603265f89327149c75ee4136b2711bd8d9e5965860d352f1b35ae893e944667940634761765d70df6f597c9b1608aebeebf81dbd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x92f7e6f3eaea600f7976d0aa1d57456dc40f9fe7864ff7bf1eca15240e8ccc8fad87c9d18156ea4c2137debdbddefc07099db6e1434850e78d9d80313c47f900	1628093671000000	1628698471000000	1691770471000000	1786378471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x42dc906e7b70d6a03c0d25a2b1b548003d23f330d0f01a82acbc923541c654459628c2381ab2d1e07eb1fa7a8239cee6679efbc3f055ce23f7c625102336a9a4	\\x00800003d749a2cb67502cc0dfc922e09f1dcdd579cfc7e9782151387526a8bf96fdee080895767a5d173d6095be74c75a488573117475a19a8ed23302e3fb5fe042aeb27fc398e4aa9cd4d6a0700296658df29db724adfdd7dbf8ae6237938ea40c8e9d5aec54a5223469466e214bbdd6a5e58e95bcb7a93652150cd9b0b985dd52809d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5f9e98599ee2bfccd5cd0baac97b94c3715f35e947eb53a4fea7f3665b6b851bb51052fd9e1ddebccf661c46b4123ad4db899e2e371c4aff740351c6a5edc802	1634138671000000	1634743471000000	1697815471000000	1792423471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x44a49fcd7ea47018be4ffae62eae48ea4967e8c1750c8ac39eb75e8a453997b2e51d482f233a6d7bdf4b2e97aa24c8f4f05b659e3ee26bdf8368b7c119a45d54	\\x00800003d288608d520b0aa1f4934854e568dfd17138ee12fe31ec188fa74c01bafbde37fdb45fb94b6513268f02b57e0ac6714cdd479ff5ae37e4683611e5b0def50c20f7b74c64daf6cc5175b257e31947db70eacbe89e69653cc07f206f24a58eb9050f0648977488e4dd500fdd342df0a86af4179cff3970802a76896dc639a3e4df010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0361b2684b9defcfc72613186c9b9132a6d2883cc2e25f326244b73850ba9b9cca2e570064622d0931c20b5dad71c79cdf7540f371a4721299ff6bb474d49e01	1609354171000000	1609958971000000	1673030971000000	1767638971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4bc431e082c5fd1921245a7a4a903c7594b7646db15dcef0a85326d47718f2638b7ddb32878feec81d3655b98d5068f103a190ece77fa82da2d01caab817149d	\\x00800003cd5ac6482c8546a823c625bd6d5721a5357d90e6f6a07f000a2c5bf53ecd727e8df3601f2a153685437bd0495aa72a3b40802b4ff39aa42802739e1822e03f28c26e4a4bfff73db9199f7ee0f909df72bdd50e767cbc9e04032627c1fb4b4e28d728c9c1ad59d11f086aeaa18d6b6f87ef1ffd557ccf16771d6e0eef25afb9af010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0f18cd8087292bced8b4898a383b1f0df72341342338dd514061f37259d0f56006050527f147ea01c27c4abaaa60f6a81f8fea63c3bfe174f7f4dae3cf6ede08	1619630671000000	1620235471000000	1683307471000000	1777915471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4e7c5179f064b80c14678a60b72eb2dea94d8044e4eecbfe02fa74c23e4c5ceb6e9cec252c6a293878d0dbf043975a608b985c73ba0ca26508fc3dd502c064d1	\\x00800003c7b5215a598901c679284a94a23784cc03dc9b29cb2f15acef7dc10f367e428947ddd20d9d32e36a86783fc9492060f78b67e75922473ed0faa8ed68397fc748cf569d22cdeed45fc4dd586b8a8ab6feb4a45639ecf80e1425bb370224b1bca244c8b66d23b92ac0c551ad3737f08f7a0d05ceaa5b6574d216e81b0b121c66d5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xbefce3187fb1f336cebd8df088cffb4c0529329a7958aaaf9f72ea9a002c738b353e2278884c52328edf439a8871ed4dd3a148d72d569a0b1d70b3e133183d05	1637161171000000	1637765971000000	1700837971000000	1795445971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4fbc1024856f264716a9fd8daa5c30289bcc68b01ea53a76b6fdf77f95d1a64f0c61d85af1d4070c8f81ca9bb57b799e016cc0c5f0fdfb87d7e3d1d3c9c7535f	\\x00800003bdb0cc19c6025189742dfb5040250ae9248b38434e5777e0ec7aab315fb99bd6dcdf56ce7f1045d8f238ea5851b551965e67bd6700f7124d25f5e2badc516e84c420e1edbd877f5486547fc5bc2dd393ccd0d9bc7eacf1ebef1c32f7a57e918a4758649a3c3b3d13704df2aa39b1591ef5cbc560215590a67f3c375c8fbe9af9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x931304770e51d63cc1e4740ce399b0b727f43d6d9f3ba26b1301fa5c5f100788152f3e37300130e25753c004424adf9d1aaeb90836b5a5220dd9133f73c77d0c	1635347671000000	1635952471000000	1699024471000000	1793632471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5110743d1186e0de73724c726d2d0aaad87197c79fae77aa5edf7440dd9006f66b8281ce3930c9cb3983323a7270c099fcb1336848f146673029c3bab450798f	\\x00800003d97864d99ac498cb373a459757359fc1538d8e79180bea7d9469f86e849784411b2936fc30e694ce2ccd206c7fdd6d10626de40c13686a2740f18c96286d74d0c9722f99900ed5cdc8313607e99121d65ba0b2628486fff203bb723738cb9f066a66bf2d78cc1eb59aac5de0d778a023ad1a2ec25144cbe017386a8f9e6e1b37010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7741defe7e6c5b41adf886c22ed40eb6fa94aa76ae5a1a6fae1b5fcf91b32c8f254fdf7a18b9bebf32261e678250ddd8837e4b5a9c9739a7e18adab985d7d301	1635952171000000	1636556971000000	1699628971000000	1794236971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x533498d4e5c377486e885e6c8788d24e7409a2bfbf4abac7493c70234d97a4e06f6c4f20e4dcd50f62ecc742b0083f05c79465468386ec48bc66268107c6306b	\\x00800003c67d294a5e4c96e2362bd146ff6b9bd1b252830fcda6a10b5d7392f3e2f75a578c69b4ee66d70c46fe4b00ed30d2cb5cbd04d9c4a394cb6cbc09cb7aac2ba4f6db1869279f1fcebd81761c3de54938ecd16b71422ebb4a8fd19bd9079e4bf648a5567cf050f79a628e95194c1dd8d7cd8d8fbb1f4e08f6c966b03b5a873dfc2f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5779f8d3d9c912cb3d3640f96cfbd4cb5553e5bece506f629782f3427fe63b9e049b847ac6cf038ef496b3ea6a1293f5105371dd6992cb4de26a4ad2e149710c	1609958671000000	1610563471000000	1673635471000000	1768243471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x55088b5807d381848dbb559918c313916065d9bfd6c04d27ecd133c71d5d472478446d299060f874193a196a7c66a56024706e3f7576b4016226ff4ae96a3c22	\\x00800003bf4d78f6711e80b35b3b72e30a3357af0db35575846c5ba4413cbaf3a1047448d3babc90fac2bf294ba5ca2f02c56e13484d588526684eb5b67826bcd95bc16099376ea0b98c3b2ec8e82822bd96ec6929b85e28b32d88550344148d4483151cd277bea3d8f4e5acd897d0c19850089d870ec55ab4c7364d84e7f728529cd661010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc4b2a76b26b02afb79cba30f99ca489db43a1a6d32abfe4dec03970f70b026ade2baa420c7a18f376e5bf8e14cce2fabff7b0a5a3c7cde35e0ed9c5ed7a19e03	1622048671000000	1622653471000000	1685725471000000	1780333471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5cb4b65c55ddef959c59d636439bed7429df1ab1a04fa261d7c2eae5b4cf64d2b429534c651efe1d7773b955270d200418bb178b715f0370adfd80872e542850	\\x00800003af1b03e5a48b224511030bac3394f89f3aea0327ce8914e3f787648bb25f1d1e170569cd9082728659e8125b9dfa8fbc06402f79cbae8d6d9755f537a4eddd62a262e4cbc80ad0bbcf87bd177800d63359dbd87f511858a7abe05aaa95bc526036b7d1119032ba401b34f95b182d778c8c36d760e93dc7262509cbf1044d7c29010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa0c330806fe65e20523333b55986578f11cfd3b192067dce7f1fab9f2b56f65d8de01fbc6116215df2aff4cadbe8ce19e5633ffad8f82e69321f689de04f7704	1638974671000000	1639579471000000	1702651471000000	1797259471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x617cb127213bc4b8d0ce53d139fe26b782f3458491e89ce176c82e2cde5dba5f09ad16b192532a8f056ae5355de04c20ab793c0ce828985bca4891cd821aaf5c	\\x00800003b5790eaafc8f768b313666389fe2478ef1fc599b3871e423a14a2df71506040b05af7cfaf262f2ac7e3ce5ea333080a1916c377ca79ee590c3e95d3ffac99dee4f0f2a233aa13fb5d5dda0b265fa6c422715d61a409eda39660f52594ebcc9913b76853b4bf687fc7685c45c7f25c1454e430ec5d98ed31503c519191144c577010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa710011471faeb726104bb56ebbd726148165c1a96ece9ba1dc7173cebb12fe63b696e11b9203822107a5cc0f5edd1eb6ceb1a1e979e61115ada169369fd0201	1608749671000000	1609354471000000	1672426471000000	1767034471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x644c1c4a52621dccc5c94172496c5cc0b5e761b8c2bbd04f685e3796fc4e9374d12370865f8bda9002a6c400d5dad526066bea02bf8299cee78e7bcff137ee52	\\x00800003c8dd8c6432030662c5f0b6939963929958b1a1756b66c496bc33f3d05130e22a320e5bac1508a479c89a43865b9d09259969f3756c46686dc2a4129f1d34e124e661c4225e72a313ad231700daecea70b50a293284f7fd784086ddfe599669bfece169283931390344a5d26516b8f483c8ec921beebecf0bea9e507ff1c041cf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0ed0a6a7fe09902b820812202cc6db59dfa07f539f82c53db2fb7f197dc054ed4a4992858ca8a743c8c13ec30260671ac9a8fe5f80cb2946053f36a0862acd05	1612981171000000	1613585971000000	1676657971000000	1771265971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x66c4f532ec272eb29cac7acbf0ba7bebd255ccfd22c7ccae355b3d7f735ef572de4bf8ec582291b8bbe5477c54a187f9a439bfd2938451a3e65a0a214c38633f	\\x00800003e0c523aafd6304cf9272208eb72262c5645ad67d0b39bfab966f4c1c0c0626b11b918e2d60fed3bc29685f5d61d7bf39171991d668cf92a5db59ca3ad56ca306e0b94ab9bf339c065afdefc7f5d39de4a4355057e9a78f5646ff05184ff16f34b13fa18644f2a6efad869530536ff6c148968da31e2937d8565c73246b7b25cf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa6389e570fb20fd5e7274462e20690b56d9a6c969440f0eaf3ab99c1dc8b75e6bc84a42212da5eb1f9f4eca83c31a0674422b5789666a474cf4a51f21aaa3701	1629907171000000	1630511971000000	1693583971000000	1788191971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6754a9f8b7b3bc616bb55b2ea4a74b82ecb9f90bd0b43ae45a9bec4722325626d52b0713db9c50742ff4baed901b7274626bae92676d3082f222bd24328d0848	\\x0080000399baf5755ae1fc06bb4dea938d3fab6d120d06e6c3472df813c0d9ea3b2dc268408e98b2fc9c1f4fdb7307088de462950a4d99d41112d32cfd58282ebfe4e9e3bd399cf2897bf70f74c09c0e9f9f039a5d76812777518a450df203aca77e295c02abffcc9d7c92c1189620d00786b5da21cc57e7af57d8f6991b53e73131d551010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x01969876bef6938545062d730e2fea0f98f79f292bea70a6dfb2d925d68f32afbb961006aa7731412a0ffb3bef514cbd8cfc9f71431fe049db7c30b29e732007	1625071171000000	1625675971000000	1688747971000000	1783355971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6bd8f4745e1bc5a041fe826204e29d1422740ae4a2c8cf2eff392aa55514723cb4244e7b2eaf3c203c138cc6d4f25b0fb0e1b80ecc659b7571b5cd361991058f	\\x00800003ea16e3c3beca795288e44a2038a6ba808d25fc1e79041850f19c2353d4bcbdc9141710b0ba3da9b0dcf470eed2b0561e655e72e67d302d30c4efd1278f7935d47386b01ed2acb5a7772db1ad7f599801a323298157a5cffbadb4bff457ddf1e4e0d4236916574e9472690c427662a79a7ac56e84a5f1681f8dd4cab4ae3c2c71010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xbe70d6f429f66e2689bf6aa96a3aba47beb2fd53cd4408893969f661712880787116179a98d0b32f434ca4dd7972a507ab96c6091d0448bd1aaa75d372d0920a	1608749671000000	1609354471000000	1672426471000000	1767034471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x704c8bb85e8875cfad22c68d2416e06b222a4bf4765f281b242228bb282785a6816ade892aee79f0560d0da47790c1622378e3a0b6b1d83f5877a5b0baaa3f2c	\\x00800003bbe8cec05a876fa59b8654f34ede732ab9470d3272eb2968ae0aba590e1c8015fef14bc97ca64e4927bc40ddd05b7726f52bb5e1f34563168c499315b3f03cc11f0829431b283d3b4831eed5074ba5033960865def94a02303b789f66d072f98bce005fb5dcdd238816dc18c743a4007cf92ee8dce0fa986f396aabacd161d59010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3cfdf9418ecbf57a285d7211ccc1a54d1a31fdbaba56e6e99b563c85779f357db1f4b50dda9fdffd8227168f8b57531d59136ba4fb4f5ccbac4f028835b2510d	1619630671000000	1620235471000000	1683307471000000	1777915471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x74ac2eed90eb17733924dfd89d8597b667358ef7d92a6ffeb028a4078674d5f33b312a6bc40c128ba4b3510689be94a821beb37e259e797c96c0828c8f090d51	\\x00800003bda7f1ed6ab04bce392d0acdf56835534843dba8f5ee3106d0a9b702689116594e9d0baa534122be2bc353a6e1bcddb5270041dd59f6251a3933c56cbc5399b2d96ae731cb86fb0e3b9155137e49ee5b6d6b925d16e3f3c2416766508cd0d7bdd2c21f4a03b9182a4eecad065c1cc2b318c56c1f491850b2c756767174100991010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5278facbe5a946ab71097af05a303964f75dc03e863523715e09394400dd56a217b527a81a3d45bbb3cc4566a86fd515bec48a8014cef1ccd018251755733901	1626280171000000	1626884971000000	1689956971000000	1784564971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7a987f6d74203b846b762eb2d8f693a87497197898ca2128af04e876d20e317713a69af26e87a2301b5063d58737afa4dba8d496c40ca2407a2138d720cdddc0	\\x00800003b11990dc974de6e2e8067c472543477fb6cea130c3c55a52bd490b607420a5197274cc631f58f96d4e12e43bbe4c7d302a6b22e2302ba7a4872dd6e4265d6e346e6b9073fa865f886c75360547985051b9107c967465ce68cbcabd769b710774b6fa2344b6ff39ca212f87d7423e79305f21390852b0591337a127a4c9a7e131010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6a92f4700524afc1a7527abdc8ed8b2c391bf4a0b37546b4a436d893c6aaa440d283e234d812355e0e90ee305fc6791cfa7218e30fde15e55bf22249f0083b0a	1625675671000000	1626280471000000	1689352471000000	1783960471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c707604e0d4e38e45bc0f8948fcce6d2fe88e21b96e18a2793879f649ae33a67d04c7e5b4421044821c40d5e3bbcbc911d5e899c34860acf306e6fa159bd84c	\\x00800003c446ab740e051b52dfe3148726195137b125e42a87c3387764dacb2e29f816c023b2de82136f3d760472e759b28cb9df79b09afe56194f75fc33325725282817d394f1c4e38e7acda20a1ba32961bcedcef8c78352dfd1026eaedcbba9f8249e2abe682bd92ecbce6c3c4b869be9192de6cce23a0a4c757ea98aa60e9b699d39010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1fe612b3e783290b6f6aec1bf2acac931baa769b8523b51a9758d312b20d3c06399f5ec9fd61408a55ddfaff388f964e1b0289e54d948283301191f54a3b2b0f	1611167671000000	1611772471000000	1674844471000000	1769452471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c547f6d8ae15fc45c9dd13f2797688e822069bfe357fe2688dbd698542196d6563f340fa765f04e8cc8ba4e74a3fa0fb640ca2011e80be40af2316c84111f02	\\x00800003d5966df432b4abbffd3ae234d416de7fd5a8eb66d5370e4163433733e464db2b2637c2594cc55a75b713f94edc03263eb1c2c5d45327212f6083f7439089b06b1366c5ad2256904350fa6dc8357bde77e35b33c693fe2cb585c3e3327d3f8fca182edc9857b0130435416d82634162bb0d550953a6264a5dab39c52369aabe43010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0a264a084d4e195d037db0e21703c2d493f6c50c91960464eab03738f8677fed9ca4d9df2a0cca86f15e8f662502b3df92d0fd57522380eedf5080a82020e301	1618421671000000	1619026471000000	1682098471000000	1776706471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7de4030f926ee1dfca81bc597637297321ad05001c123cac4ce06938fe7396bd1d202621c55e8034a824cf29b5bdc8bc4b3e83dd896a2d85ffa9b6853eab76b0	\\x00800003f2d21fbcceb71bb441ba4ed37684dc36f17d05d43f4e52df0c83dba1f814d9c3eb476fa4b9a316190baaf1df5003235ffe67351c894d55ae80824c0de5bddc16870c0ddb9d98764f169cde5736d76cfae100bf8df56b10c98a81b1b0ca8bf1fdbdc99471dbca7f21f16849910077a53d6b469e19102e9021e29f59954aff215d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x10a82419b98cc62dde97bef4c86d08aa7350e832bc792dc4f744a3fac63c04dfad55d799bc0c36f5d5d5b9e9a25e4676af2cbaa724b8389974e969a28aaef600	1622048671000000	1622653471000000	1685725471000000	1780333471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x803ca0bd7a1ac71185eca5a068ae9d27dc5ef80fc0be2389256daf757baa67388eac9bfcef5fd6e5ceb77e89ff1466e3cf328248fc7b9df79fd90682a53d9f3d	\\x00800003b6c880225841a94e4a729544875e346740da4cf076edd7ee144bffeadbf56700c77521fa84a739554b0aca0c827506eecfb5b4ea025ff0698e6f0b4c3614a894e0f975013432f7fa65edb70f379c47feacb0b9471519002adc2c2957b70f543be3e42bc26e09930827b69f582e406154eff5bc08d9e2793b4a0396e21381e5af010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8afa64b047d2eaf9cb7a691dc37b82b13c832d05aae6edc99001e65ae49a6f478457cb1142634c101b72383e6248acd2c7156979e5e1403ea14b29e408c4d108	1630511671000000	1631116471000000	1694188471000000	1788796471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a3821c7f5c4e69db8a02244550a2ef4c2ae65afeadcfacc17439ec42e6f2feb5eac56ed5337cb6613112c60abec508a3c1749fd1e9e9936573334b0d39044c8	\\x00800003d3030a5c19b6737393692e2419900b10410aa0e680f47fc33f8225679fdc4ab69f9ba7c038e8030cf6cc7782f6b82e2482f1164405b4d23d8ae49321f2bb3dab61e11612124e1aa5b7d93364c6e26fd33feb264293bbab6a7080aadeaabb24b80d908329b1673410b58f04012e507d33b66a0c837e21ce7a7af2c9305088d999010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0259e18637ee10434feb75c4efc48d2ba9a66691804627a21d0d18048951f1ba9d71a234cc19fd88d00fc71393fa22846696c3572f221153bc9554dc8060e209	1628093671000000	1628698471000000	1691770471000000	1786378471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8ac042344469a50f36a209b306d682670e9f18ee21bb535300b64d69cafd6a186d4b817f4df8e5ce96649ac768ee6c54d048bffcd16769f267f3fad68ce2cd84	\\x00800003a4e14a452a9c1e7a27919b9185258a72c30929140a6ab4d5a482fda73926bd5f5231851f24b3119f672c71f3bac8a22176498b4ab2ddd632edd7f7aef2c1b7e73d05a951369310792bec2984177210c448c0647ddfc7c78cc8c9990278690a20d0cbc90850865a27a6f0497064a14478d6aa62c96f746d79e9cbb0ad3b2ee7eb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfc23552fc98eee2a64f11557f22f55458753d52ab77a83a1ac72a8aa73d379df1376e2eea43f1efe806cc55916aed92ce9bd3135234782ccde758167677a0c0f	1614794671000000	1615399471000000	1678471471000000	1773079471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8cacdf4abb53d3276871a37c7ab1c27ae575e63c6f485fb217c9a864ae6070fa43484d0a328ba53260a0be8792c164da4e344f9dc232805c84acb471548ed95c	\\x008000039e3718efec61aa63cd89e966e4b51d7d22ac9d6b84b889798b0ad6495c7cae3696b41335ff0da772a4e4295183a4543af8604e32897f920f16646d216784f088d6893fcf7ed0e01b23f51e6ca1ba6233b569c159d25e62b8e596c12a438e011d8c86ebf4fbb97f90817d3f2e04f5098af833dde4cfe901f33a3f05abb8cc9d7f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x21b25ce4c35a160137dbf1086b8f1dba013409865b636cd13b91599ed8e6ba73dbb6b1af6d3b16088e1350907469cf5dc08841d966f9ec838308b7136ef3460e	1635347671000000	1635952471000000	1699024471000000	1793632471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c20b8bd498687df6d7dbc6ef3db578c5dff4e97ec7d9aa3d282de0f2094ceda1b0f744e24ea0a471001ec9a5f4156031e63cdc57e0870d1a1f3993421aede71	\\x00800003ccf5ef42c7268bdb3197ca957007eea4e36462454631540ddf53bc2d80637338e8ca4a1dfec07adb6d0f2a67dc633584c235851ef3dfe5f78a81bddf6bd77871d1945754f1464dd0104f78b43be3def73ce04edf65f1df8521dca3dcc116190c5af06f06b4a947a8d923aa2bed59ff78dd599b6fee7e1e7a23b72134dfcc7b63010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc21ee9bd44f453aacf2e4c5f5c205522aecf647c7c11c901a8bab49cef03df05bbe29fd68527ff1c9b214620534aa84b72c93772b23dff345475ce566fcebc09	1635952171000000	1636556971000000	1699628971000000	1794236971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8e747156b17229e37030ee9d151e2237250451c8af9359882e4754482a34c26427347429cf8c97062b4f3a0b322d61b379e2135e5927e221d4b03038c3cc1117	\\x00800003bbc279f4cfd70118be81bd22f4d02b663a1e9159358b97acb94ea2b8708c6b36881efa7a0878654bb2b3540f476c3a1921e6493c0a73a8db5ecdd77f8f3b3b76b5ec7c1dc6ad2b7ed47653d63b3463badf83827c03529bce4a7997f63d7572260ee848c60c824b226426517bd96f109c7d4bbb251e3ce4a61563ecb5ce5221e5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa31825395f4cccd63430e949c7fc5e4f0a0b8199450022aec25858ee711d8aeab1ef9daa2837920a8ca8a82d3f2725e37ff7b9282c693a7e5f81f51c35771909	1616608171000000	1617212971000000	1680284971000000	1774892971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x92e48bd4fcea5f954a708e13989c0d1eae05da1c575b6442cb19745cbd3d5e44bdd26a49cbb526bf053eff0f5a288a3459c2eee08c503114d8e2df82b8d9c9dd	\\x008000039dbc54195cb02d668d1a3de5634bd0f2cf7c4b32b1848196d09ef7e9c440a76bded42daae20794872eff85fc2552c5941f8d9165177ab6f38333540af6b2cacf1ce7fdd5f5e066ccb32dbf522d09a60ce3ebe0eb1b318f93f20dcd4862b626db95c81e76f27b60fd322c627edfab530f7caa180c78621a425f3f0bc44b0ff05f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc91c715e4eb71091905612567c2faf9077d0bfd420862a3fbbb7f29ed6fec4dfec921a392411eeb691c285c56bdcd150c30549cff1be6c3ace28c0a2e5683304	1629302671000000	1629907471000000	1692979471000000	1787587471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9800127280776413b2fa160d574cf5b0358364dba7d3ca49f1678562c2ce20e15480ada7d6230806c256702e672349c33eda7ec21cec5eb0fb8a7015e0c8beab	\\x00800003d78f8ea6500b53a6e3c683c2e01877148c16ff6be1564e9dce1444176bdda7416bcd0b2ca4c7bc83d7a6ea0935cd9a39d62501d299f4ee6d99e1c97be742ae59e6561ddf61fca498088f8c602e582acb360055bd814ee82c1bdc1ada9039388a03d4ee8f700dc6d9cf4aa900f9fcd1e57e9c1b7805dd3d3de327f217541e5d2d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9192a9fd5767e76f8a58afb86859780c8817c521e45588acb404d49f209850fb3c775e9d95d7d9f4da74bd4798e4440ca40d659a25ee4f448c38c9a382dca50b	1620839671000000	1621444471000000	1684516471000000	1779124471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a30ede898c38abcd279a47a8de7abffb50a312b38eee53341f5c7dd75e6c16d9020336f0b539cdd4e5c4487c8a6d96ec59e7b3e0ed5a6ccdbcd7b77bd550220	\\x00800003d7fc857371792b932dd2c4f8a9fd587469d8ccdfdc20e09175a651e9f5ec2b87f27af1b9bb6a9a6f9aa85e79eb0826d3b344fe60762f5eb5b2db384de28e7fda3205db404c04e802b032153ffb8fa23abad42746c4cd0629d1dec9c0ddec0c94b270c43a97ab5fe09c5d379e6ac87bc5ffeb8a4fdaed92d84fa60e0efc9f69bd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf2ef8ce268dc28d4abb7fe689fd83668a89e4e9a3ec208ff20ec82107397fda9dc36ef3331da91eb0e5c608c0ad72cd30037498d8014099c4d49576a99177803	1634743171000000	1635347971000000	1698419971000000	1793027971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ae81bd09eba2a41e6bcf2c7b4cfaeebd01a435f0faff49827c34ebbafa71756a0a6c9225afaf2769454255080facea21c1f3e1c93e6574f651a1ef06f752083	\\x00800003cd189b32c6fed0c89d8fa471cb17a71f0367f0b3f087bbdb84631cfbddfe540fc7b82f72a07a8b954a6641ce1b04fe29a462c4f529ba30f19b1751e8e1121bea5f6e9846d89a6298ca4fc51ce7f81ff48eda4df5a1e2065b22c846a2f07fb50c4a1f8275129c2d5101bf36fe2e27d9152f16f71e142132910911f74bfb4e7725010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x28a654aa650fab54bf82dcc53efcc0b602f65abda47ad95364cf98a8f5d093625c6bbfa065a10f3c8749576c65419d72ef6b1825c13340c9634cc0ff262c1e07	1619026171000000	1619630971000000	1682702971000000	1777310971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c4870eee9298f2aa80e389bb92478599bbc0fa9709a0eaab85d0f7ae8808f0777e99659130ca1d5be5bef05b9e386e47892ebad425dc31b7cab6206045761f2	\\x00800003eaff7f45c70574e05e2ea918c7cc9bd8cdba303eadb0823819f82c64a38efd4bca51c3338b93f1e1621153e522f015768fe12a81ead1aaf2c700d8de9f7604b7cd5c9b6342546f0de523b45ceece06a99ddd1b63533f5f85f56c078eb6cbc773aa3aa19aded966de9652d40c3cbde2b9787a5658a711a9fd63b255d59d362285010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x637d080c25fc65a209a63b10a4197c71c1496086811259ce52e0c5acf37e5ac519830523adb9a5d845342b631463072a0a856b33766734e055cc680f36bc9d09	1628093671000000	1628698471000000	1691770471000000	1786378471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9eac686bdde17a634ff5d06810c262d159723640b214c89c1c8b6161838dfec5e4d041309678c74bad5c627adbf9aed0ad3278051a96a78dabc2e1d64ab8fe17	\\x008000039fcc389579399cfc95e1fe657ab022a8c94ddb895cab17154c71e342d0a2382fce15dc501501c94b405859fece4fdc3fdbe53fa20c08adf51b9ddf8342fc2dce2f324c421c8ad8f3ae0fee74193f4c364d96b55ebd0c5ac14ad7c5909ffe6accc4830ce5a956b1dc92dbd5bbfe3c6813202d9a8187958162107b38f4a0013665010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xda7f03cd8cb6e4a7d2a12b0ef0d3094576754957f31bc6989a0e1db1aec1d65844f47cddcb1d4d7d5ab4671683be414c09afc73128b5f3252236656c8c764903	1625071171000000	1625675971000000	1688747971000000	1783355971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9fd0d3c0c9ecae498f5852bbc753834e138e37fcc5818b6346f1f663b01152dd78225488296c4269a44eedbbe879563fba86f7afa082e84cdfde293a2b1e8bab	\\x00800003a77204951b7ce66705ae40ca1622c1fe143c019911845ec6038a1ce10b6c268434de936cb553099daaaaaef22857f3a3bf5ab42f51bdeb8d02c29c87cb8befad93b503e8d6c2a149528a11d112a26a8eaa045f3a660e6b153007076fe302ee03d3a08c782ac4669a5660ec22f2e3a176e8bbdc20d2d188b15c877905006bd825010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf7ae95492ff775f4c51607678925424db76a56fdae8d4b3b73f5cc32671045f17a7378282b23d045ffa79c467c6e159196c481fe1b88b51c6b61723f8ceb7c0f	1608749671000000	1609354471000000	1672426471000000	1767034471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa02c3489529a3bba1eed20efa0d5a98105c3fc4edc4587dfdd2d1fcfbdf2bef630ca68ccdc75fab61e77222076d99394623ed8aa1afe9cc6aec5f686a0b8a7c7	\\x00800003b83bfdddd02a1795271c80f4c57ebfe82ba5e87a0b136d3b30dd701db3a1ed157de15d9cf46baded9706eb3be19587cb5c8db84cf9f1825e4019fb4f1be3c036e2445518092bbf8aaf7f86a22b72761c11495ecf61b3c924c8cfc7877244a29ba07a516b71b4260556a9eedb091882639904714929f05aea339b7aead22eb4fd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1f02ecedd226adccdee8b5956dea24f2083f4852fc7588e61d360219b77ce15d4f0dae1fd4b56d32660089961482ed5796708e311e7907864f13c2adbad5cf01	1616003671000000	1616608471000000	1679680471000000	1774288471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa0189d1b72241b31339ff8d00091bedd4c36f8bb94aab8414222ab2949290b6194c4ccb036f00b4aa6b9503ed9dbc649fd88922c533a171704e931d6fc433646	\\x00800003b1604352508412e01da08314aaa2dcaefdafdb9eb4a366ff4d70f39e3b88dc0534ab3d19a15288a01c9f2f6dbc7d34f7a15fef02bf3b81d51c201a4aa90d8198e0275c43d0db0b715e5ad7cf8e4c6109c5a7b7e3a5ff9058d0d4c8d03cd136d65b1649735103e1163fdce310d1315b01d6bb74e18f55c1442b270d14dfb1d673010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf14925cfc44df8375bbf1e55883578b83763864cdc1a738b7a5db2fd325561ecc0b8b5be871a55e8dd81acf2dee5a9015e6988538d0066d0d52d8a0b809f0c0c	1612981171000000	1613585971000000	1676657971000000	1771265971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa404251703a35acf8e9f2ab7a35df414779edf16abd2970854a3f73e4b66633124202d8a999202c191c38c321cc996bf60c4a2ffb8831898689d52c4c1d02f87	\\x00800003a6f0fa39b45e99b71b48f658d7306cdaf8b13fae3b6a968015b57e6aa2e169134404bd5fbffa705b65b19c7a394eff44681e241c3e92bc2bc705e4640281a8829e57c4c131577ccfb0951cfb338185153525ebddf842db516c3121ecce98deb0bac53e6d45f4bbdd00ded48779e6a14c15ed50029135713fc2e2f90dea6e8f8d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xeab4f4dc08caa468955df3074226bdf72e8d8394714912ecbc6b139b1dcebe4cb01183cdac8b79db767c7509d939a6d421ccfcabda83dc07446b1bb12162b40f	1615399171000000	1616003971000000	1679075971000000	1773683971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa8046a22889907ba93cca68b95892f76c03c4f07132886854ba8fe00bbd383a94ed03c230dee09e0acd41382ad91384a9ee5cc56db56d5341afc9cb26e0d3a56	\\x00800003c8f4af5aed4085e25b387036f64afc4dda8f541c7916148286ba46633010754d66d7720eab68097733ec130e0dfc05100343e9cb3a9af27dc908df412cbeec022b3099330d9fcd02e47d6fb72f1a7b123cf9ff35dd5fc2e3c0e47cafd7572d5d716abe9c37d20d62789ba5e974353da9d8187dad0422dba5eb4c41c6e4247f59010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x762f146b57e554d57f92a5a719c2445f563868913bfcf441153cf8add161faa16268eb76e94230c235bb6e568afdb7f1eb6e28d8e603fb46c957ee4a5385bb03	1634138671000000	1634743471000000	1697815471000000	1792423471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa920e312969dec3987c98311435245903011e0fbac0f14c5189fab09db1c001242f61d036d2e06be876ba2d59bb370c2fdda3edea8890cf39db1cdc056e4f882	\\x00800003b1d6e833ecbf24456e27823f883ef3230c1ee826100348b16120ac2c4484161f2fb90fbc45a04062efdf79625042c96e4383c55b3f9d0ce6dd21b58b56ec444d44558cf621ba3c887067947564f5f4b4edae5ea3e66fcee75d2d4eee8e5e96a00b8e6e7b999a1b5be2a7ee601bfd3aa4c6588d6dce30233254de8b5aeaba3ed3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2d060e3da197cf76c37e681cc8b947679d8eae621ab06bdd3819539ff8a681afe477a66e80160e88d2de721a9b7aa68b262b6f6df98dbb6cf7e55ef5ef2ab70b	1612376671000000	1612981471000000	1676053471000000	1770661471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaa7c7b64dd437218f0d79b5eadfa317e39580d3e590a855d14ac8e6b31b7e5016dd59e4f75db327323d5afc3ef8146646f33c19f845147804886c886bbcbf497	\\x00800003a511d45a8671bf5cabf36e3ccfe57ca86c0783f16e28935e5a6d8505febe14b7337c9588708f674ac6a33e4d511bf7738818c5963e981a0a5c6ed85d0130d9092463186ed99187a3e31a029a8c36eb304fbf7cb2ad0552d73b9a1ae7f7e017475a656eb39cba92de36329908ccd71ce7155c2cc3f9e4a4ced0303d8d79f44c61010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x14ddcb669f6e4b9268058a97b29ed544bdb7a9b5ae99253a7e356e0a7767ace1e9a0890285e613c614c5ff737e3559dcb6edbd1277311fe52199014458f89f0b	1611772171000000	1612376971000000	1675448971000000	1770056971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xad2cd5de05b4dd0748b0cd2b1f7818e5a54f9d4225be3a48c0d34ed6d65cb56483060a4e56b9b4e56a86ea4013054a423d629738c86e089d238ae153b29c3df6	\\x00800003d9a4e6fd6e7e263be0ab924beb1924fb3a2c87c904ee3e387839eb7cf51542347e2450290143e8150eaf120cf3290782ccea136932fa954f3e43dae09a87d4eff3a77ad300c43714500cca75620c73868b371ecb33ba7ee99b9ab2bb7a7432e2a95ad1c657676019994d16ef23910843fd035cb16af15f92aea5a035216b4aab010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x27b305ae57e3ad6bbc41092468717fc2976571fb1375f8b17c74d667d529c7c1e544e79ed7f3ca6fc4ee5af1dcf66bf370ed7d8e2ac402d965a51fb478cc760b	1611167671000000	1611772471000000	1674844471000000	1769452471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1c0a7f224dd53ed1878d787b3a2d298366b759bdc46e773030084d033b759f557dd400743fecf569e6d3ec94dea0ae36dc37601f61bfdb236d855d306656ae9	\\x00800003e3162e72a961cba4a9f8b49879f7fbd2264bd137e24333d6d880ebbbc0c5a642136533c45c0e7161e77b048ca0108d844fdfaec5661fb8bae6d23cf6a8197af8f1d44c02c633c669f4783ddd4debb4f201dc55e775baa177a4e79762e94658f0814c5d59440a58d024d677f8009bf471ac119ef7a80b2b1216754385084b410b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xad19d5a603ecf2dd4e4355f56aea960244a35c24b2586b76b70142af15c42fbd8e2674d3643adbdd7faa4710eec0f1d236f211ae449962e48c1c7aa7fba70606	1631720671000000	1632325471000000	1695397471000000	1790005471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb368f919e78c5e17a655dcdae07bfeda737c76fe13efe98e4f147fd48dee34bccd3d57dc3de8e328fec017465e56bdc6cc6193b1a7480f24884d0fbc87da6ff0	\\x00800003bf06756130e4f4708d167da6ca2145dad1630f2413dcc6740b60debcbe89c1b8a84f89ce5d60f79dc9ec0fd9acd3aa137d809578f68bb0bbd713383cfa97b7c070e5146f42de0d11526aa9ba87e2a19840992b16a09156a735cebf41a746cfc52f6f8a731fa2fe51164d6ca48c4cfa64e9ce6ff0d1c3de8507482ab1b3db3311010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1093d36f70eaec09bef85f057df1ae6539e19e8cb0e4d34ff255ac52cef1ca0cd98df0944ed44d3bf0be6c3504e2c6fbfe58ad98c4e015ea7a5419406197ff0d	1623862171000000	1624466971000000	1687538971000000	1782146971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb51073899cbd0ec612fecdcabac9d24097037ac5ba6da86722ccc5141def81822c23f0b222323408bf3039c31c85f9faa4d0d4accda72f45cda8fb76d8312eaf	\\x00800003c99582b70cedb0fb8cf7bb5abd14eef08e2763794c82d56e9cf68dd3baeef0101cb8d5ac62cd9b13010643e62d9a0176eb20555f839f8667e27addd19b1075c88a53a4491d02aceec64f7410154164d158e31599f8b478288e51bb39673cefd379eccd0bc96aff6f435814189c5b006f779dc8d6c00f13d480ae94b982789dd7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x01fa05229aeb03b3f6ff58799787cf48534b5356bd17f227ba7fdff88ca4050357dfe0031bcff2ae11c9de76f0ce4c60720480b35fbe74e906ca7b62c3a0160f	1635952171000000	1636556971000000	1699628971000000	1794236971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6b80aacb970301c7301139b25d55d9f74ff30b51622510585fa2a1b9a8920f8189837b8c4f70e280b54737d703f4c48d503ac99098285315180f6ce9cfc1b04	\\x00800003e46cd47690f485f3a269011480e6fe01c8e67e924ac4e07c4eb97f22e1cd53ab89e447f25530495f29afb1520aa4701b3e02d71f1d15a9eddb6d72f9570e3a212016dc8600cd8f3d7a4d0eca2cf5fc66c95a3d4a33182a4887fd354c1ed3532049b62ee4ae9670ee9310e06a8504220b034c021642f108ccc93ff9662344c9ff010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xcc9fb4af51f1bb89963e809e5c042cf7c74149cf23e4c13283057258c5a3336bac15d911c6e3c2c19619ef8ec8e43c933f5ac2b85a029374728c838ed60bcb00	1611167671000000	1611772471000000	1674844471000000	1769452471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb918056d418541c1217c657a326cf22d090c223e827729dc458ae29604970f89097fcd0339d48a1dc3c13c1d8ab6c7092b2648988bce7d5db8fbf53f9f8dcd46	\\x00800003c0e911a13b92d810cba0667adcb9e66a0e645a705319f83428a4b96c24fb777e93da32cd277a0cbbe5aab6eb170d0d7f15fb57c48efda0da54d3cc920dcf6b32dbe6d48c675d62b8e09f153772ffdea8324c07177037735d7fffb678747d3d70e08ca2e6a81127ac9fd1612db2e2a29d0a69ac5e3571ac83242254751b554547010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x828ebab925116f93ce9fa96a9f5c5c9444a957d3981d200091373cc9c5cce32bc35a761f7cf9ff7b6f2108d373c0b9d036f45ee08edc449e07e4826452d0730a	1628698171000000	1629302971000000	1692374971000000	1786982971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xba78ea540f10b43452395ac8abec75ceeb4596355f5216be3d4139d2624debe41f2338cae5b62e9028c66fb3403d0337b2fa8a5857f870852181fb062712f014	\\x00800003d409889b69a312379b06d252aa79c2ee962586cd074abd1c4357a3d4d8f805c582246d2e4beb6c180fcd43e9db7564133a8191dccb4e28cd9121f3f33cd1caa149d838a528a769f26c6e92418921f01c16ebea4ef5b75e4e205755ffd6763625a56d1f8b9fd1c170f0ca956d3236f86a12738290225224ea8271a1c4866aa7b1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2bed60df04614397fd1cc61c41657aa6aa964064669e500285056a0ddc8156af3a7952de560564fcccc0b735ce986bb0f843263faa23b81df626e250d46a8309	1621444171000000	1622048971000000	1685120971000000	1779728971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc21c5d0085ecf0e0ed79c290c9443acc4600d61de268c4d6cc3f933aaf91edf830fb499707bbb8f557bb4453ad4784e755cccad572e155770c903b1c648802fb	\\x00800003b1ada03389712b5ffb7592725f8d3a534964d5bcb32c1973dec5ec1d637bc367039b193b7262e06de1bda4fdb4f07c7f8a7ba6afcb00b9511f8e5117cc2c2a6593d6d6d1001b811da1082d3cf217399dde5930283df863c4e3127c8a9eaa88950dfbbb41749aaf5aa14f3d72d9ad4ee3e8bbb9721d02dd41d9771a203df2db31010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x418974b0bf81325a5b6b841e25e5762d875a81d015d07530f801879867707f72fa82d59730c3f5936daca7207ee3a64be9fcf66e797d2c57768a997bf797290e	1619026171000000	1619630971000000	1682702971000000	1777310971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc5141bff8b6c792a05d4dd731b120969d002d5bbcddb630229cbb07ddb42d8904ed245972bd4a56b08442ba6af5b514ac7950a713f7b64d749b9feda4bb622e9	\\x00800003b8af1256142239d6dfae44f23bf8d91d530e0b4e47cc3fee53bef133352a190687e32f856f89f0761b32b87a375e1dd19734afb1680fd718a02893e98c209059edd0646a582499e8349c3af014b16a1a405c7235b3c4c9217d24114ecda39b37f1b2c0a3a81a5599e34ec88cc1ed847ea304ab036357702a9241233819786b4d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa933eeb5e7075298467c9b9c11ee0a1f2430434e4c1afa0a029f147a6229ac76cca3b66d376dec2c05bcb0c6f640060aa1fd33cd310328c538414f7127b23d09	1622653171000000	1623257971000000	1686329971000000	1780937971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc538f0d09235617a4b6a1c819d28f12230e7908b177a050dae6507827a56d58c939928a1514adfd78c55663776955ec267ba101f29538f58997d66c2d8ddafdc	\\x00800003e06809562c30f60b6a23f660a1dd643eb268018a63a6f104b8b054cad91be5652c44ff838ccff6b7139e890ccbb910ae035c92a72dcdf3befee93d900673a859718ca4ea5b2a3a756798c0b0e9d5849dd6cd42b0944a02dbcf9e3d0f23447f4440a90528ceb3be5e64d859cec30a1ec877f903322e18e84d3ed694e2de8aa59d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd4d763963de425e211aa1034728e068e20f76f0bfd1536a76df049681754327764b2dd18a2115f2630391f46588deb97f1b682b10738c7ee0e88e3bf1e8a1d05	1634743171000000	1635347971000000	1698419971000000	1793027971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8547e0dfd7e1ad74ba97a4755e6b29058c1d114a7332d1cff708a05e8084c6d38e023f05170e4184482b14074b3bdae097e897f09a09a92d706701a626c66e7	\\x00800003da254cb9e505bf0514eb70cdfc3bc824687098dc2eb7f3cd1deb16b25f728744405118b9874590ee5a521b5dffc20240489d701ad3f27bc3d8e5485e06751cd15e9dec78eae8c103b4dca05b309737ac3a1708ad0d5e9a949fd21df5e7f05d68236fc6db38a0fded555530f11eebdd4e071b124ac6bf33ed43ad30a424ee0ee5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6a2e59863e4bb830acb3cf837d6819f115f453518d0ec641ffd11a692a742d0a093b8fb839c1e987c613b40436e9ee4b47ea0aee8519943914a6600aae368a08	1617212671000000	1617817471000000	1680889471000000	1775497471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xca10658f3f7d802639acc271c218b7fd97868f69cd52d4d1552d7f563fa0ea359febdbe2f441b477a93ec19c719e4f13d2f438f2990d4d53d32759790c0b7c75	\\x00800003c45ff0ccaaa9a2cdab7f924abeca5a0b1ba5f4092992ee02c05cacbc330a44a04a314b634ca0cbb01444b94d63ef78b636dda1d66dc9467164ad83a7473c3959243bb4f05ca9978d2966a857b52fcbccb8b90bb4e4ba2243d673045ee8000c2ddc34bed843ab5894908682438c94948133b5bcd292f1f75d140b2004945e1445010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe6eb5560354c392e504db88344f2551cace76d1207ec4e4ca0fb6184fe61559ccd4e31333d39c8f72fc69c4433528bb42c2e19cfaf93409b1c96a57699cfa50b	1624466671000000	1625071471000000	1688143471000000	1782751471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xccacf95a5f11f398fb6d2d54e93d7bd8383b5c941e1b1a77cafec4e8111faaea35da12f0015c2d8197f08e09513b59054ac80470803de3cd2e74fce2aef02292	\\x00800003bdf6f7470e258d4322388e04bd181d4fc63eb93c503c4d82646f4ed8dcfe7b6fb8cfb44f5ef769e3b905468a8dc6b2ae135a1b86c632c0fe29f5d8f3735024c83d02677d9db164deb32000d23b4d927c21b66791b98e3643a67b7ab203d0253b06690968e601e69c88b8980bfae2ed14308dd524f60e910143913a58b8ec3b8b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe4c7bf3250eedacbf515d643a5f4e7ee36a110b0050df0144c2eaa0917785d1306bcf9f12fa1c07f4d784ec1e3305855e3f830396b9af0e1eb7481b9a584c407	1620235171000000	1620839971000000	1683911971000000	1778519971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcc5cdc544454664f747174d1332770dbba6569d47129a01246c38519c44dc8f7d6181745e69c2e08260e90e9e551dcdec1d51bf43d7c5d30fb1d68aefd1cf1a6	\\x00800003c5770a8352463a14f765cfc142821d4ac6ad91055426db1d7857a110df35d950ee39af8730882a5fc8d8c98581b5db3c0593cf39b85cdee316150a3fa155dd40292789cbb394be7cda3a84d84e532b094407300396e9114336da1b649f7ddfbfb6e2a9efea9a4502e0de3dae82261eeaa04459d8aa9a14b1ff47c0bcb9cc40ef010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6ce8e727fe48084dabca790f7ca8c5370b672a58ed89c8f8ec3f339e7c2e58aba153ff29af662a7ffe1a8584c4f85de746ab3e3dbabf5c96fd93cb686304360e	1609354171000000	1609958971000000	1673030971000000	1767638971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcf4889f2e1ba77d13ccf6dbe075f464c1dbf160e0c6f075f248d248c3f783a41b6118a409fe51373c19b23f7bf521ea8bd7be08982fd645ce3f8fafa808c7c2a	\\x00800003c8f692896341282d8ef2240330a99c399ae1ae7686ff3baa042c92ee90c15a04589c8f9c577682c61aefa71eb058c62b2a05b8a0c701eb3e22bdc3a4efcfff345565ef756bcd3997714e6a6e0529de250179ee53200e6fb3eee38f285a7dc63df3d83fa08183097f06c3056021772b8cd7842db1e4b1f15e4432b255d77b25d1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1750154245ce1f8cbddf73ff39c89369f77b73f68613130c8cbc97f408283a8e11961c2c47d234e00f5aa9b2a35757af08b135ec0340897e5bf283de09226d05	1638370171000000	1638974971000000	1702046971000000	1796654971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd39c0d3b4857e7d7e7264b5417d362770b2e85b8808cf30d2878a48016b7bceba883c1780623136d359d233d323c14afb189d0e1d87e982c905733ef4a811f61	\\x00800003c5fd678ae7b7f1a07db6057d9556b4c45aba97f31db4cd2673f736fdb706ab665e9a6036505815200d97d64c7f01532f641deeeba720a2266d3950de1302a73b0aa89ae7dfe7794530c4767c3cfe7972c9053264f483c0d93551f29c2d9344cf03bf2e2208d7e789276ea07d926cc4e0128e568569297e4b5587b520635bb759010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x522f9c6d224dab14309c024546c7fd57214d610f21622bf6a2bb1cc8c0a72cd809c944ccfece634454dcb27be45dfcfec21ff965b6445b5d7abe5f69dc82830c	1636556671000000	1637161471000000	1700233471000000	1794841471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5082568702cb7bbe061adc74ce4dae55d08a69d430c4e293cff95dffbceb83a963045425db5bd920c91a701eee622be3930266819bdaac1e6e938f3472138fd	\\x00800003e7f78b9bdbc472e9b28efd0d5b3c4af0629c43bdc969720e1b9a0a3560951629583aea82aab5bdebfba3c649faf5c805e6cafec0a719a39e4f4f1ad7b2e3297d8d3159f1192a8804b735de1b494c9b74afcb973fe792f6ff874ff967a43f55700e21daeb78c89b4aadae87563677be4285e1a9ba9deee274cbf8bf7692070f59010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf1377da747c1e9ccc1417db096240258e0031e44ea751d92c7bbcc8ccf607f4577cf81f3dd446f17e5844f65c1ef9587cf3119861cb3c9ceab5c3579f2bf2302	1637765671000000	1638370471000000	1701442471000000	1796050471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd249961370893c8a4a8551399cc606bc4ea4d81a90ffff187fff021b8f4d73c066473047547eef5e6f51d324e7112eba708a05b693800053f68c4b195bdb3f4	\\x00800003b1f38fa7bdd3d2338c1c45e0f7be560ca6271a1630574e6cf01e47b0727dd227a9b8f25cd9ccf3f97e79e844b1709941343f91534ff6f5b9c74db5f4154f74f8d5729111664465d4cd0fe4d8f811ef19f525007cc32f6f7051bc4b650c410839968e559326a857869f5a6ea59f51df199b1cbd5a6121ef0fc1a1bf69db187c6d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xaeafc3214ece26ec880a3dab144830d2c90d4f03af57848dd50d084d7f88741ef1c6c370794cca798262d4e98a4e2d1c1287401c35d70c81ac121f5066eed701	1610563171000000	1611167971000000	1674239971000000	1768847971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfe43777b933884a7f1539d001f0ca678214de53a238ed28ac1249c9e05c2f8347dbe5eb87edc0a1f81512b92af8a7ec497f522ca33e3e2748ed26b90d48c8f1	\\x00800003bfb5a405f6071999122e44d8c819d463ea29b1896d31cfb490576a5348cdfbeacd0b46cf52c7f35e10633b8b8df7fd12866c56e7abec02aed409b6e985714e187cdf43c902b7b76b98f520af193893dc4e53989732ce30fd0257edf90941ac907bab403780a09ecbed90482f0dcf893a0778caeba2cfe82d780ea78444798c2b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x673f3e4209be64927560ae598dd295e6eb49cce03f48764ee8a2038ce26f8de21e295db114047b0165e4771347005e6e21dac9c573762829704c869eab038f01	1630511671000000	1631116471000000	1694188471000000	1788796471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe154e2b3af7260f8ddf14ba3e8e6b5be4af6cd5179a5ba721c971e9bb8928846c438239843ae42c40337329e3533b599f52958543d61a5a5cb4076a958ed742a	\\x00800003ee6bf67cbe310e8ba1615a3e5e6103252c8d1aafb89e57d532179c6e794763a9e591cfd8ba24b8af426c41500e33de195fe69838049723e4a1e8f5bbac107a10ef0326960898629a432ed4185c9e11a804efdd24a404fde793e7b0539ee802ff95c7f6d85ad912dc14598ae6429f7e916375969ef4cf4f1e90685f176d6e80f5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5f801644a8f0c3ae92bb9c3f64542dfb7b060f840f5d9fd744564c3d47ae7cd8fb0be7578e77d4bb0d11e9d37b620a7e65039b3a9e7ad592a6fb444777024d0e	1616003671000000	1616608471000000	1679680471000000	1774288471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe194c2147ffc4ce7c92e24763d6d2df1568976729e7ed0a0847bef903925e6f5aa4f32aa91a2b1e294dd6d147e8066f5c43f0b36761029522a76ec7ca2cffab7	\\x00800003bd8ae65a154cd83ee35146936c85255ebbde975f14baef78ad04138a09fcb9f9abf61cc2458479e4d1e80d44de5ab4d751fa466a46cf57c01a87fb66f924d82116a361ae632083106d3187309074876e9f066d8ee59e610e080fd0bcdf86fb089caaeaff1a47a6fba0c6b40b9df943788a4743ddb2ccaf60a0ac56aaa406d08b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc4b0736e5afc4182edadb8eb3301554941bd6ef9c7799a6f24a290fddbb3dccdf77aef141900edf383b5b2444d695b77788f5f58cfe86796fd879830cefe390c	1638974671000000	1639579471000000	1702651471000000	1797259471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe2d824c3240ddf0600ce518e790e36e4ebbba40ce9f213e512903fb18666958e2939361e737894f76b113075bd024f95976de007957bcd51661e51e8ec9a091e	\\x00800003cd0612c11cd8c754c335113a959456968d03fc96d3c1e0e4907c45ea724beda81c95c06cb6cb384344819c09334e13307d8d461ce1e32c6f1712e8b02769875e81c5fe04d3efc509cc493c799277444618d8e22a85161ac1d6c220d54b320b88807b21e2df930909d3e252e9b1984b8fd1b705b7d30f7ddc5188bc900cfe522b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x39cf4b610d67dbf6bc920abe9e83db94b2eb7e4ed0832e2a78d59e2cf90ce39645921cb1764e1fef01f6fd3c6e4938e90180a7b2eef5bff7db24c36b259c0009	1609958671000000	1610563471000000	1673635471000000	1768243471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7a8d131b35c1331cd43d132bb56ff8308d9b604b18690ef3fb12ef9982c5d97d2f5984dde25c83f30c6e3a5ba8a8e4b44aabf8bfd1f0e8563055ee781b63872	\\x00800003b21c3c383e341e14b4cb06e28c09b895eeafbbf138d96e818370555ab24ff96b669e07fb06ca8f20afdf86525fbadf4a0fd33e8c1b0ec3e9f797208bb42a1eab762f3cfc375348d764b47696d25b03e95e5420cf274a622f3bfec6dbf703764d1623b9cbaeab532de7c2967f86062d707f4adaeac30aad3b03b40fb33db35bd3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0be705f41f12e6147623b65df1f7f1fcd53e4942668089d143b468de97054485398bf7b838bf3486db3f8f4f97ae72261abea3b63b8d06010e41d62c69e04509	1622048671000000	1622653471000000	1685725471000000	1780333471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8cc23be5f529a041bf2b5b19815256d731da1ae0d0cee47835f2ca80bea1d9710dea6f77ee77545584fbc6e984649486a7b8fc3f82ab8afcdb8c48eaea9eacb	\\x00800003a02a87470a0fa8c698ff647df05f306793fa84c232130536c72424eb440349440a862cf78dbd154d865b908fbe14925281b6e18c76a207b9b21c53e2b43571fe482ce9c50a31e3914787446c607c2360b176e49bc3c8b44b676e85dc9bd9438c75ffa063c08ac51638e4fd189a7dbd0b9fd1be3dbf178868aac79400dbb3896d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5dbb143222b7aace91848cea5bda9b5cc024b1b05b6c49cb228b1f30d21287905e70c4efb3ec94f6ca6f53b3554bcccbf382906e0b2e3061ab2174bb4b33b400	1632325171000000	1632929971000000	1696001971000000	1790609971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe8c0d2d5e58af6de1884ec943795c9fe9ddc51e9745c603aa94f41b06794b4aa25060967fb165b4f7c4a916777d13d5eb297c6d2dc8b121cabe5fe562e3e5cd2	\\x00800003c36eb01ec63409330422b23c6a3ee3a462fdb0c9f145a28f028521db02d5fcd075613446d5d38824f4b6c6e195dc10aa43716028f138a29216460bf72280b1d92da7cd31b8473885c9247ed1f49191f3d609f8220729ac078d465ffbbafa24bc68897d1e4dc317549724474d2033c7956bb249c389b2bfcd8363c43e2c1f236d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc5e7d4a4ebb0151d982ca5f3d893a8daa995eb36a2178ba6a93a00b5ba0c8124f4d8029b5c31b8c9bfd3746b880c3407ebddd409693a666e591ec5947a38fe07	1608145171000000	1608749971000000	1671821971000000	1766429971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xea9c821ac0c814fec5252d4b9c9821deded6df403e330f321ccbbc92238c95065bd4f9fd6182a416a115cffe21edbce9ac36f04e72b7a3a8c5f4cc112d575118	\\x00800003b37a965980d41f3dd998dcfe0144be220eaedfe3139e4bd171a9e6b74567a5796e7292954a228ab9eaa417f35acbf35954c9a055a8f8913b9554ad483895c0a95ddc72098579d8c8bee0f8d41185a38393125300863e4eb6a7f1de27a4d01c54bed647b8dd7ab6efc71057923030cdcdb3aa70662fdbe0bb9f71ede8646b9b7b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2181c4974343ef394407543266eac285d69fd961e2c97527611f4c66ad4deafbc50c32543df0ad1ef429eaa72981d93b50ef86ecb21641e44ae0ce17b645020f	1634743171000000	1635347971000000	1698419971000000	1793027971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeda4cd322ddcf54006233e4f21c84d7c313d0827f6d9bb48b8a9a3e2b3d388da5e4fced66683e782f28f928279470062ad9c5e45f6f3be34f42bc37a5e661707	\\x00800003c0c57eacfcd276ead71cc9f87a3688fb99634953de7588b6b97a40c4ef66069ced8728e7f312261834b84f416750013f7024e55d2ffcebc837afe823ab19345c6c6b4528ed7a974ecd2aababb057e758bb6a7c8248cb327363a71bc048df6d24a21473d085bd68ffbbc99d2662d0e2da51daf665103fa00dd73183206f1eb043010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa723cf8849c70317e9966bdfbfcabf0c363f72d67ea6b3a1972916dad9b01f5f73dcc555b7b3aef66ba4b35cd973ab011d13e749f421af5c97c9dfbad8fb5205	1632929671000000	1633534471000000	1696606471000000	1791214471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xedd46de856f267a448c0c302e7307c7857c5bc6d5fdb05de7543378d6ca89aa9b07e2c1fae5e20c13f48ecca0444fb5e8474a3fe95b8e30fb6992ad9413575a2	\\x00800003d3650a8beb15b87a23fe845206286cec92a1946cf8ad46d5c78355e7b8f57095c32788db93ad9f755504230b15e97c6e8f79d612b8514aa44d648dfbf2d694f9cbd82367794a05efab906cba626ce4355cddbfb36db97853ec18b90db30480522a36c567297411d6fd89d540ad53f4f9b543625d9dd24e3d766743774dd333af010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x732d16560b972ae7da0998bdde11036a70b4964b2dfe4b98a4740b427179f58b116a574d3b9d9c40e481bd1a1fff3533508f59c3b33fd44891823f01d1ed0e01	1624466671000000	1625071471000000	1688143471000000	1782751471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf398efa206fb14d477ac4b30aeed89d23600d7d776a53e44609756f3bae129bdc63ee5ac5536cd095a8002653703500e06188cb4a1808c896efadf6c23cba494	\\x00800003dfde59506f88da26f03062ba20ea2a42108a7f84869c5008bc8fbdef01ae32f29d6dd418f411f90238d461a3e13c6b3f20ede025dd190c2c9df4f084443f4d6bd7257c1c62c8899e4e7f7d9a248ee694614d6bcd6eda6e544ea9ee9cfe0fc70fa4c48eafb1c51bfb56880f943f90448f9086796da30056c72d1b7f5cc951f219010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x46462069ad8cd6565441405f245debc852736173831cdba2966ff0384dbaba6608a7263249b7174a80d47c86946048d09e456eac3ab1f45b686784c392467103	1622653171000000	1623257971000000	1686329971000000	1780937971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf4a0e4532ca79f481c483d122ccb409b72e376d1cb977ea301f42e8a3c9bc9462fd491ac174b086a3f95f92e0eb0a18f7445c3e42b30db08e7cda74630cfca66	\\x00800003d220e1bd482c061863cac9a38f804534364683fb1e97918a48bc1b96bab1fbb723bc00097d02353f662dd9622587f5fcd7e5415aad423099386f4e65cacd2ad6f5f968ff29c3545f6690612309c56b3113f5493863fa2f34e60e26d4c9e2e7e48b1f496197d29408e725f5b88127cec75435216e0687d07c258d5ff885280261010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8dc22606cc3741566380dd65c1b6117b3e6a28fe34b782168653fd689fc45020e3f15f1ede5b44bc3c8643cacd552ee7846fa70a0eecaafbef01db62ea558900	1624466671000000	1625071471000000	1688143471000000	1782751471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5644543a59cb3d0086cf13c8ae5096536c7d4a60802a99e10464507142c75c736c3d8058c2f307eff0d59c527708edc510f5fcef2428e955fb992450e0d3c1e	\\x00800003aa8ffbb73d19aa7e98310766d570fcf243c5d58921f8e6c93d6db99285bcc34ed4f151956002840a67aadd14108b44340545b4dcaef7eac158135d0e2ae41741c198e8a1e9b74789f747120291584d5723d4ec492cb0975889a855c78af45b75669e12d3a7d2f91905094e6adfae04c790218f0a69bd32df9f15f4b032b40999010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb240ff52fed67cdbe22a7f697b4c0eb9ba5396188016803b81fb7573a38eb8c2126960a9ece734782dca72522513c758f5d3416c4dbf1e513633206e2b821409	1629907171000000	1630511971000000	1693583971000000	1788191971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf564d79af493b8010b2ab105e9eda5c39336db24645683a3abe9458be68f1e43f5f49cc9d18d7a059b7a4fcc977ba6bcb6fda25ca11c33a17314f28305736fa2	\\x00800003f3f3972771aebcbcb5c1b748ea78be64208f1b1df2a0fa6ab11a12525542be33011c12e5d8448ed68465f198925332e50026b9c1d70bcbac03ea2f8c9da7005e7486c4997822cec721e9445d293ae1cb05b71d07548b43232ab074a4279e9255dc06e687c381a582631da87994a8da02b82e75691d9e1642f44172a52a8925b5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x67dfc97cbcdbb38263c652216e5a82a74acfc5e40974a26898ae666a6b8bf2d41e2400ed8ccf4b0cd9a075c993eee704175b7c9506eb158b8300d42460dff901	1616608171000000	1617212971000000	1680284971000000	1774892971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf7a08403c404eec16d53b2229ee0e6096fa33727d4ca76534870da06ee3d0888d5dda573912b2239d706d2cdf8167c55c62c36f97f11327639fef89b3784b2c9	\\x008000039942cbcac76b5e30c3c0c63af0168a75d625acb023e06b11fc77e124fc085dedc5106d8327f8e952d0e9d5df8f1de20d7419a279329e60f2caaddae9d56169f0419a943f5c79a67ce176c6bc0a62531463f0f139c2ae56749c9b80a2236a4be7789fe858b0ab9ec8c40c5c697937ce610bae9a098a2ef957d624fbf06ba0c397010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x748a3b9f9b3017f67a22438ac6858196a6a0a0a86b47463d33a5b231019e3c9b4569e2fcaa1925140b81fe4c2056796ff8edb8c41f8d04978008387780abd902	1638974671000000	1639579471000000	1702651471000000	1797259471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf70000ae3099e42c7c2591b109f68e41f62252358021d827d118ae2ed594debab3ebd07a39b077b964bc18d7db746a65562b954e83b514fce566128ef300c9e9	\\x00800003b6455fa8c4e6945db38ac691893be339ae96d9639980a3be80b8102d8ad4df211bdf8bff6eb5cfd19597d15a36a7159039dd7e84bb2a49026ebb1d4160f5a4137890d895b430a0d210d069dcd2fa25b4e8cde6e2c4d9862a1d9d60033b5da32ce572ed6df9aa6f03a0efb972394d669aa4bfe43c30e83075c1388973a83f903d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe3142766122348a1c11e88a87860c97203ba47746cacbfd4176c372cb39b824043f863144b63b2d2c8068dbc9fc14b6af2733a0927f3d88222a77ecd713dfb04	1616608171000000	1617212971000000	1680284971000000	1774892971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf90c383cc17f03d4650fe7e7411dd437d2ce6ba407c3b17e1597e4b7d50a3ea17ca97df0ac52c1e96f84599b5f8363bfbe194b406b8922c57ec7f1585f73e7f8	\\x00800003c3fa8c40405e8b3989329080d6d18350d66e3b9c2e8d7a4785f90252a7a69d22b762c24dd10bc7947ccd0ee8afb178e63db686dfc66e992cf4136d0a98b299732c45ff39b575dcc3db26f4101ab108f55d9b6e6a314b63fd79d6b9ab26123e1d94c22c15d56c1a58fd2ebc641840d38b84ccd59ae664690569d635fc00710119010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd6340a3a23b7123fed995c449d1b3fdf22e80f5a18c9ecda2fedce07979c69e052ab2da7d5ad60be0570dc4fa55fd0e2bb1338c3eba209dcb6ec05f8db91c307	1630511671000000	1631116471000000	1694188471000000	1788796471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf9d0735d8a46ee4593eb3688ccddbabf2a1b2e72e196a14582a59cfc54d8f45adde9bc502862470c9440a3ccdfd757f4c82ac6a57063700be15aa7668901bb4a	\\x00800003f38012dd8b847991e20c9a37a5221e3273df5265f40a2d5b52428390054ec3ca58e1d2b2ca713422a7e3cfa9d9de42e4fefb6fa4aa7533a57da0aea3a9dc2967136d4a885ea114250c0e25fd2e683af72b1a2ebf0e35560b1f96a88bf4e80c33d4f1729c11a8075e396e3ebb770143abbf0b44fa4bda31f4307e35237f2c0be7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x565bf07052c7e330c35b2129edec909d476d1a45ca0cc9f4e172b2eddbcbde0c342c2983a748668e35366d2a947e8c0b86b9fd7f218c32ad78e862dbb952e808	1616608171000000	1617212971000000	1680284971000000	1774892971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbb4669549b5be5cd7e3302007ab54ee90c8a9fc220bf3273be129043ea7a12061b72105987a80154d690a6ebc6c04d1c7a6d7d58e6934fc2db49d3f1b17bfd2	\\x00800003a4e754251cd6403af8de5fbb7bee984f6a64c7a7fa8ff01783ad9875c02c1a5587c6f48d58fa3b996d8242466a1c04493d90b66297bc93c2c23cf0f2c96922f49a02b1cd58b9eefecd811fe7af507a9e9ee7c40b44c32c6a2634eae23c73e48d5b3843fe91f949e8c035fc41d2ac3146008e7abbf331322280f061c4f8322c73010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x385a9c26b184dc4f780c3b86ad048068e82bf7829371410ca4bd2c278d556e19de4153d7303093847420074ad195af383c584cbd4d034bad248d1c3f16c16e08	1626280171000000	1626884971000000	1689956971000000	1784564971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x02c163e4ad031d00796be70090fbeb14cfcb3dc4921a81463914fb4b27b0e6c085db001a6cb22278471c074fd40b5dd3f0fecef4d3e958ae950211937ae63e17	\\x00800003c7191cc55b9c7f20a5a4a2a335b834167588e7ce577d1a41e5019a32443d245a8cc0b1b90ad32edf6c30969ddede4cda137f3a0ff737be55d722909e276f536890dc2a41e23dc49f118c11a68ba69ea88342e38e955f68bfe1f50c89900899e182420a540cd5089b0f03f74fed259515017c037349fe1ac31585fba264da0b59010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x53437529d575c901c70a31c8db9e590e0fa3ad3114f1d7e93a452175a4405205a05b949dfab051c5738e18407a4da9ce95ff4daa164dea65a9b9d3a1541cae0e	1614794671000000	1615399471000000	1678471471000000	1773079471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0411a346d52917ca3dea28a8065723c2cbdb3cd251e4e03fa00efd5e6f4bbe399432f308d0ad7482a153375b2b8c31cf8fe741b4bae3cc8da5d34592dbd02769	\\x00800003a6836c97601f946ccb1eb86f543fb374ffa64464879d03e188662f29229ceb9ef4dc78ad18c564693ea176cb9203f6f492bab343d5e0be4c95fb618cdac26575f9b5cd32daf760e8b7c348ce4c2f99ffe52dc8e129f1861e0721bb373e0a8fc8cfdc2868bda64a9bc3487e04a72c04c89f4ce37960d787852609de23ee72e581010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7e8f72cb7fd3a10139aec2187ec337487eb79ced05a7da81bd18d74558961cceaa80db143ca6a75d51b43167eefad1c568275f8b16fdd680e7290efce69a1305	1633534171000000	1634138971000000	1697210971000000	1791818971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x07adedf2d0a0320d1a4efd39c9d8c1dc942bdb7cc4d0ce049eae518f114c3c48345c9d7c3b3c3cc13cafa90de41e8c322fa7ffe0b851ff4e6b9e8e54d1da58b2	\\x00800003b42657650333b44a85bc3d6af83c7c094f10a421e32988ef20ea387bcfbb8acca11304aa4300a65831d8246bdece7b519402ca39d7ae9ae4107dec2a4f373006b2d7e7784cbfbe74588c37e39aaff6070880b4f3abf58519cfd77d920b3482c70711977d27ed9c551c5dcdec0362b0c50290262e6fb6a4958b4513af991b05e3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x72ccdefad44ac422fa56e2e664d1a8df6de246ebb9c93bee25d3c3fef6eb361f829cf128c52cddcfe9b57e11c028c7b24775fdfdbd2a03e1a231d0953e12b103	1621444171000000	1622048971000000	1685120971000000	1779728971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x09e9fec2d89cad515ac1aa1dc4eec4e37f81907382992b7c5071744ea54d1f028565e96b0807f7d5db3788ae9ec77709412ed0390f0c600c88bb544c38a9fcee	\\x00800003ba4e1ac862f988a4e9bdea08737621e652a3dd5caa32827c9bc728d7e614086ddd0658c6b687f597e3d4bd123f8a942715fb74394ec7cb06d0e7c36f50820f1bcc7b9cbd70021128b86b11ed318d07d7affec2241418de9c4694320a841be004a77912ecf7ae7c0bf99bdff19e1625ef5ef641c0aaf524a294e57331f3c49301010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdbfbba57a87fcd4c196200f1e9a7918f7f76b63148de463b32702e043d8b61ef108628e9f781ee64f84144115ee42e004bd78b78293848988c47de83ee053001	1627489171000000	1628093971000000	1691165971000000	1785773971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b69f902eeaef34e8ccd7ca134f415b5d913134f9fd219984d11d07180cb004edd090424e7950f97e4df6877a3681314188cbcab5ba7ba24bbad709b9911d89d	\\x00800003b49179682f317a6b52136db659bb1273d451a035a4d277881d77aedf0b8a516da45a964e53859e2cd3c0d062f9804dccaa4491c7774e6bb355eb8de4ff66c0201d9bfb897cdd1fa50cd53f0a748cc6068b0ee5c6c6b9f25288679f072c9a99d47399ff21373f27d24cb8710b70189b845672b3c14570ce5a0562c0c907c6377b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xaa84441d8d9f22856674bd581386eabf5286753aab7de1ff1d6539ee327046cabc0e3854d375033dd50ecf11bbad46584910ee5543e0a381fe8bd2725db53502	1632929671000000	1633534471000000	1696606471000000	1791214471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0dd1b249e6408d72d32ff63d0b66651cfd975616e5a59c607cb086cc75b26900d1f3af8006bbb4157b5fa0ba4bf272758baac288645c4417cbb0d6c17cd2a388	\\x00800003c39e72dd72b7ee974296aad0b420ebabcf85535afef96ca019b786cbd6a0a812f05dc714e045bb882380988f7a588bf6747121d8928c12ce2de2cc113f439824688ac74656814cfb223c97f01c9645a2f254100ca2b1d3e5348b37ea815eeb1f5e7bc83cc75931e8874d29c47d711688f87efb74d5e54da22bfd751bda5e5c2b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x633f75bb1241381cdf278b2d01612c6eb8f5b53f7b11abcb9cc6ed1beaf507d867de123b526af51f02148dd9de629a2552e3ca63af8efa5258adf9dd9c71320a	1608749671000000	1609354471000000	1672426471000000	1767034471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1161ed12597b27f9e490902f5f31af267bb0c53d1e26ddd699a1ab8167bc3e53594423a42a761682620b9ee37cf56d97671ac07464cbda89df241e878a39a07b	\\x00800003eea44eefdb6cb693c7dc43a2d907d09d89e983a5192a1a38f625763410edbdc1189609b5da88d1353c7df5e80c3c753b113fefd87fbfbd87e0f53277133633bc706ca7d89e1381d8ff3b61e7d7140a1321d63c973375beab82934e10ac2e9b07ba88a854b0cbeb8a992b7aebb7155b282f1fa7a49053f842914da2b03c5a600b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6608fa05a2fd0f0665c2e274f24ec6f5c1a404ce5852cd21af817543b7dbcd8d5bea5898e3958c70734967ccb69fb69e7458d44dd5c930c8a9e9ce77e7e04106	1621444171000000	1622048971000000	1685120971000000	1779728971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12e5b9ffe379c543736ffd3766e4d3c66a6544ae94baeae6c6f3b32bfa224f7a0d57ccca71d32b5e61add93f7a89421794d31759c8edd585dc105930b72dd279	\\x00800003ca2883efe3277a7085585901360d0922ec0a1c102e5e2846d7a52593de0053c2655cf18b64e5e9422ceaea6e6a4b9dfca2054e12c19905cc3e6c33e66ccf5f2ccad5a009f85e0ae0a60b76b9731d9fdc430595855782e4eac46f6fc7377ba4e0cd8cc6b0a538dc564bf5226473f182dc93a4b4e9503d1c1c851a2d88f59e7c5d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xce0c5e9b330d1e4abd1ae8dff18fef2736938fc1e892047f7ec7b8c2c86d2591bd491ceac41cd5d625e983b31cb89fef837d0351cc79dc1d05d223a546d2470b	1623862171000000	1624466971000000	1687538971000000	1782146971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x14dddd66a9ccb350f0040f7370658dc4c294236176218bf831e294442f5c1dab7d83f8644c236556343fe8cc52c798d022d898920f79d6f67a1b3def3a5ec5e1	\\x00800003b77fce4f064c476de83bd053a4eed5e2a34e8ece00ee1698dcfd905a7f9734d9c15deb9475ffaed4bb2a7315664f36295631e12d9660f78eb721543f5c9c8891c855f80199cfeb5c5f22c6ff1868a40ccdcf91842d8e321bf17aaf6cb4e41db6ee64c0cc92f37064ce95f67e2ffad13f75f63ddc9fc283c2ff09eaf276c0a1a7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0193edd4bc4bad225229acfa25dc04b67c0843ad87a9b3255535d0158dcbf0f75d0f45df1964fb539c3b5e6b15ea5f581e8c86981035edd950f073dfda211406	1635952171000000	1636556971000000	1699628971000000	1794236971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1491ee1588d59f609be7b6fe77233db7966db24e17160711ee5887bf115bc9e81f4418f86b1134cbcefbc6f04557c18690a060b949367e6a039b94917074fa75	\\x00800003decda3cff923364ebdbd885d21d1bdee694152b1fb3c0e9aa4b85498b8a729711917023a6bf16f37196e2c48abfaa63bffb0e1a6049ce87e858041cad01cee8cf19bed58f329709a8de1f5a95e3890f3f72d72f36843814f9ba7defca76085dcc05e1b72acd683f7f514947389f94e27c64d4c14e1b17dd635d40ed7f85e4c91010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8b4a18db1130b3d57bc05eda109180ca38a0e278ff508f9eebca7291c322a6209c992749c1375daafe8ebdc8f8f9c4bcd6b554f5d4b651c245b3b31beb9ee001	1635347671000000	1635952471000000	1699024471000000	1793632471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1d69679cda5633525f806f2cc09e71859fb3f30b2df5758d3c03d81c15ada20ddb655e1cb87e0b07787e6322509aee7af0eb1999d4f73dcd4314e18a044de4b3	\\x00800003c374bdcc6e96539f6d2b4c9907475586c9b0979d840b9bfb49f5834c389b10343abc1e28601494214ee8af604a0f5bed9daed8052a90364314a73191ac3dcbc1db0e44b4cd25e9f723036782e5cad0bd945ff74646b6b9d94156e5575c0110b2b47c303921a9c60e23e428790b06ba6a25d9dc8aeb82b1885c8da6a57c8aa3bf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb366ddedc0618218ae1b6e3f4d5e0372aff3c555853491c0aa2a83a8e4ad0f0ba64ad74f64ad9b8c8ef41304588b94d90e73b8370451a5cbbd993e187c77fe02	1614190171000000	1614794971000000	1677866971000000	1772474971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x20611a2cf9b40a6bfbbb048548e9f5d64157550095a4e21436503c90d36de5bd81cf0ec2232a1bd301185fe135424c59363712b190a2922ae95e94d457c457d7	\\x00800003f298afa04de0d81bdcc3eea8cd3f8f4609f1bc0ff9b8812000a8af2b0e9b1a64e9379a4e64c2a48188461ccdbf2ee4127c0ee8086e0e10674b3e7bc13be6f4a4875a43c75fb13dd468d1b019b64a052912d9591519bcd3a212369daa271172a332b912a88a25451d34bec4e5e2856088fbf8a4f695031555de6e38282be36e75010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x534a6ee8d503feb387a56a1f5098b4a3e704536bb7b7f391677f7889dc690bbd72c784610e39d6c7ca9948f2a916ee8803a367d47f3395cf1662987a17046306	1613585671000000	1614190471000000	1677262471000000	1771870471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22fd1303a8a5c95766f1ce5f75ed6b47da5839c247b3298b0e91627f50d359f7c467fcbc8cc8da9111d6360a340967948920a5d4d425d2186e08b12b6e407661	\\x00800003bb0c70ae219be4458677f1c67961203981f551958a0207e66a4af715e161382d93d7dbac9a5934004b6848b861b1dd28f648398f305e52c04a0b2ebb4055a66d40be48a309711ee18063aec6e21b8f09e4d4a7472a12423888297f0279ce568e042446f046b970ce8c26b1454ac700ca0346bc9b56782bfaa748e8bef8f6ad0d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xad08a4c7c277502251c360832a2101a86a583f6c88a197552a3ad89dac5231a0906d503501f0abfc39ff5e72887824aee7ccfc5165fd54b9f99c50c52b9f950b	1627489171000000	1628093971000000	1691165971000000	1785773971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x24bd9ba4bcd7f75f547ede8efb281ca8e2cabd2ac63c2c58f221ad7edae613e0a5c3d38424ecbef38b808de2c6e6ec9c5e159da826c2ad7c0027fc24422d43c8	\\x00800003c2f40b5d794eacf9e48f9ed30f760fe078632e54536b44168489f67fc3de3b9388db5378120b2e845322b070cedaf08ce38762b1efedfb36133d05d2dc34e84dd100361058ce143574af40814885a1c9b851298059f8e122f4e578c0f8b652babdb9106c2c444680d2bc2c3a4c56773f77ea1cb5c8ddad88a281148ac1ab61a1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x05a39681ada42e0b7c2806648249a73ff38d618083cb38574da18717228f8a809944ab8d8501285c3fe17da19a63e0f7253a6df120a207766b98544360213f04	1639579171000000	1640183971000000	1703255971000000	1797863971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a0956d3f22e7361b181bd6258d93337cbfbb2b7ed8be9bc0d72cb3260ec0b774226c426c2d2707a329cba5022bbc77699667fd3bb2602bbd044e26217f657d5	\\x00800003d28b9466a8252568cbe1e3f70c590c8c6b1d9db88de8125afbe06d9d28ec99ffd1421b13d2d763a62956ecd237326d4253ec006dc6a2ac5a5d80594390ac39a960ddb492451679f4d9e59afa667d2f44086ed653be82aed499a4ffe5bb69dc6ce930e85e694f4a9249b75298a5c62455901685ed8959a0f7e8b26d704381c08b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x93c5c7a154ae333a8252051cb5d2b8f8730153f8a584ae9e6024b777b940352f490d2ff5512debfe8b164d7ff1484e8d4f562d754ab9e80da47e02f57589a302	1625071171000000	1625675971000000	1688747971000000	1783355971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2bfdd83d7093096d008858bd5f745643e291d9028351eb365091cbb61fc5933ff2e4e15674fa51a903d4b400bdd5484559f0a27f81fd8aabde1e7be1e32a598f	\\x00800003cebb71fcc1745bfa1306d405430b06760b4f063f841992c8a158de1a93d0ecf1066257cf6e262adaeb5c144a40b99163a33b1d9f15abe695bd1681f7986e9bcdcac8d31bbcf7fafc3f2fdd816f5810883a2e03de6d7a05ffb869a93f5cb6f602350ac3705ef9ac198542daac799853889a589d03bfe115748dc1de2b7c94e705010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1645959d00db35d6e49ac55467ac88bc17618c1ab0e262d9b1273d064cd7bc8a408dd6a4f0ca7c2fe2a3844b5416046b88f1f109af98688d003a62600f671408	1637765671000000	1638370471000000	1701442471000000	1796050471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2b01aba06ae6b27ecbe600410ae6d91501bf9cd15bdb99469a6763226989861fa59676e9adc8a5896949ecfa02678175301b3cf4ea3dd8f939c316a0ac5c455b	\\x00800003d7133e538c3966045b391ac0c7d6c3ec2a6da99c83f50e714bbeebdbc1a00fd8b0799cba1f4d3e74b0e641fbea8d1157b7aebaed3f8093e1bccc91555bad1136030c9a4f32dbb85d7d790740634ac701ac36eadf2ebd2d11502b2a1c9ee75529c2f92c849eb53defa41cfd5d3269c871d605f8d28de8d6ed67edec5cfc9195b9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4778b5507f2781a26976bc50f0d0b162dac1af02769ef4387bb436c7bc353744749ad2f0e2692f596b7f466e380c5fcc649b05ab34b777881d144ecc919d5b07	1628093671000000	1628698471000000	1691770471000000	1786378471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c052461e9c96f8a233c3b251c12911765dd4c058ea675146c5408255f1032366c74fde442c1f5cc815248945a182117961ee892fd56645c5a1871f193ea4f9c	\\x00800003d1115626a84d5fdc0b0d272f4c63266de4490751ed9e8b71bd5eefe535eb27a567d769ec5e6ef79a4306285fff44087882dd122a0aafe7b213d0f02e0b48292972e2de8ca42eb24b3191705232d140cd10fc81c33b72dceacbeb8ed133e927abe7265ca9ff8e5976e1802b597a8bd2cdb56dfcd614b667b74317ef82a7896975010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x280d3fa8d11fa5f806c1c43f358f14b25aa63d168eb9af0f4d754846195b948ef84894157b171bee59d9fdc1c5400d1f3be154ee6e8c34aa77131110a58de60b	1615399171000000	1616003971000000	1679075971000000	1773683971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d0d56d9fd31765ed2f210452cb7c6518c23343c0c3ff514ea43ca1368048a94e3933f77a52beb747cd1d1c79d73ea6b10f49291eec3a1db12df1258cfc1496c	\\x00800003dd7d5a82456501a80552f0c0d4a7215a0d1a3e8a53efda3a21d551510e7787338cbd7c0f50398bbe783f23dfbefb0da6bc7050decdba512ebecce5a87d4adaf363b90bb005239f482d7b4b04803ef567093193fbfd05ef344af3d7e233d85fba9e608f576be72f614bf0809acbf6a8acb45577e5e307782b702b291f64bfd7d7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3fb88b35100caf99da4ce5d94f1213aca4d6f2fc342f1808d08d6720c8ffc03c0e35f716ee9690a88f4eaf80f02492f093156e7a0f93b779e2f50fc455737607	1638974671000000	1639579471000000	1702651471000000	1797259471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2d650ace77157e5bf9ae997429a14abbf5e783a64bb5b56a656b45db0672c24ecb683bd01fc03ebaf4d449bb8284ae4fae93640ea3a1a31bdb7ae4b9857cd646	\\x00800003f02eca4bed260e9107e8dbc3f7c61dd7d5039cd2843ab361981a7e69d85d3c5de0ff3ac4ff0fff5c444c17d93935744899c6d20b8077203da577fac855fe4bafff3f695a89fd4102283d52d94171b455c0d92df577238f184914c11adaf14eaa96f9159943d28aea9442815eca56f65abd218528e43fe511370e9a6e6b514ed3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8da0be0a0365bf77e7024a2a92116fb07610857d266d335bf18ac91e2f0983df3f6c009ee5cb137713800ed3f0624dee81d0e2bb012ae617b75bdd57a9dc1106	1611167671000000	1611772471000000	1674844471000000	1769452471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2e5d5071ea0873483f63778ded937a672169890333e5d86b994fb5495a493fc0c04fa17d30461bfb6f24687377869604e49b793f821d504d7bdf02fefb3ad53f	\\x00800003b7c7a65ee7ba5afe203b185a3168764db1ded2780841e70a6d331c2f07f3596e21c9c71118723f0cd8bbc4bdaebee3ac5752ac3bacfabf662e4b2f3db88590ce08ac546c2cdd2e586f7868de1b271b35c7f0b453749e4e70187743abff0713e544a1fa2b205926bb3186f25f0f23e8d3c7c6b9170545885beff8fc3572f6e285010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd01f759b7561e6239e82e21789a50e703506fc9bed66556532f2bdb1df590e1be4c2ee1be98a7b4199f117d9f73197c976bdc37a323a6f3d49c579c3a2abf60f	1617212671000000	1617817471000000	1680889471000000	1775497471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f21d041ac2c15a86a268869b17f83fcdb9d75ec137143e07d7231e29223f81dc27075102bfa333a5e35a1246a9b930cc9cc084a52cd0d9b5f1996530dce78aa	\\x00800003b281d92528a290a1480394f4c0819a32c487033081f2bd4beb25f93acd7159272d3a05839ca1df4a4bc2bfbe261e77a6dc3f48b06c2e12bf9cb103fcb6fd2513377311c149fc2493c4f572882a67159866b867f687c8653f673844e2abf118a11b7bfdfdb0264b595a4bcf7f1457d4183556049f3a64875158c386eab7a6fd13010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc1e65d84d9e53d614324c916398db6d1c34b35861155a75bf0ea122a09839be0e413c1a9ab441ea820154a950221218edbe4c6ffe6d74637566556e8e874f403	1638370171000000	1638974971000000	1702046971000000	1796654971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32d196c52403b212a5c8c17fe815dff647a57b055141e1818d2036e8605e36036dbbbfc731287fb947488b49d661e69ff3259b2d369d848dec3b6f73c3ed7728	\\x00800003b60d08adbcc31282fb1b1748f2159c53456b8662799106a9378a86ed044e4a69bec32bafaab97b6ae12c9b50afc1fd42b5993f24a333f4e3a9d8e5c3e074c5a9b97fe0d5d8654d5a17f7f5e28a9d6e0bc63ddc809792e562b1a41eae6eb43cfdfedc462418e4eb4727d60adf834f436c129a21811a6f350d5ba1197ffe82dffb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4553cb345c5ee639c30b7659b836ccbc2e090805660b03a611cf20b50e9b0a768aa05f301f03abedd37d8a2abb516bd86f04beb0a545127cc6aecc10ff89d70e	1613585671000000	1614190471000000	1677262471000000	1771870471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x32b9b6abdfb7a4b9735db41605aab35ce9e9f685c7d6883a0bbca000b1c72614244196f1c857d02cbcd0e89c138a5f0857bfce7c280f81b9d8578a2a1553950f	\\x00800003c1a3da6e32fc53b3c7e2122d774782726e0f81b35a038a2afb7c8ab12714321ee2ebd1b0d05113d1c631549b9bc27dc608726efc86a5a1df630414854c8d3fac9c598d0e37678d0ed7ef2c81d5f2e6aa549b6a0e0d569971b58e3a715d69ccff1b91a6b6559373ea41eb0ded11732952a36a0f44bc1146a8143c28e431c4378d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x57ad36384b0e12d7f13f84c1dea9694fb778e0947add4bcc7a553624448e79796c0b4bb7a9a3ba28b593efd0d79595afa819b31db2b4f8982de3f2b09e395002	1609354171000000	1609958971000000	1673030971000000	1767638971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x32d9a56958c847e93dcbdd6de1782a2f4843aa41e1c9a8d834e4913f53463c17e0fe35acdeb48d55d7b1da3cecee29fbcfde6ce02b0b33fa3c3fb9b3fa8040f4	\\x00800003ada769408eb39293b4abc9adff253b3715ce74d814b50ea84ddff5941e88d34ee3bdcf45f9e4237a33760eeb8ec21025614c598fd6436078b12e4c03654236e3d21ec090613326697366558221edd2bab4c6de8bad606ea33b66ba1dc8d82273122551c7998ad8328da3cf3533bc721e79720999642227521dd702b606d547e3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3d5a9a850f444f028bf6b398abbdb20b868c97f213144e709c736d9ca3dbe786ad443caa5a2eebfa5fa561e8b753eb3559e638763935c1c993de1572f28b0e09	1639579171000000	1640183971000000	1703255971000000	1797863971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3379cb8c1fe9a3a83419b9ec2167fe13d192621775d9fc8e932e29f563abc8e9bec96e34941a7f2b0dfa43be7de50b1fdff479723c8c5b6251b86d2c71c41fb1	\\x00800003c2bd4dabec2769b30e87c43fff118aef70402d6d5eaba0d24a71ee1f76f96f030b98f46aaa546d854c7e422a636f5f174ab0ed09e1e1c4319bf7d777074c2559e9fb14127e02c617fbcb444fac53eca918f799bd5c5b61c5068d4ccf52e2af8370e9a88e0ff9652c0632c92036908553477254b3ac45d587ea57b6d5637aa159010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd603c5dd53cf6b4a21f4a3de87704d560226cc24418a21a795d39353e9362ab6d92170cc27869e5485b78ad120dba2f38d858218155ecdaaaa8919895033c608	1635347671000000	1635952471000000	1699024471000000	1793632471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39217871b75b204c5137b1ae315ff629ba24f221b9bea51245e966253ef9764a951f992a61d69b27b9e40e3890bd2ae6cd8c6837378a152bcea2f1e1155c0bef	\\x00800003da930fb7ca1a0742b7a1bb5fd592773116fe042fb865d12623feec8b684d9d3061f795d307e5c8a3a278f526dc3af762a25af8c0a2bf5204f9ca29f9a9a5fc510a9399cda2d96a95b1b6b2e424a272f0c9e0234c4a7e2ebe1f7a64be63c4ca5db330f06db5e8881e5a7f22718d9537be64e212d4ddac02f3681f17bbf8d71467010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x930a6d34af46408e1c1481820b418d26981096d0b5624fc8f29dfea2d0e8ef02c69a78c5ad0f17673d1af23089d9246e0b00fe436a2a0772b36b104d7f3dfe00	1636556671000000	1637161471000000	1700233471000000	1794841471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3c2dc07cbe172661300cd28dea5b2dea5f1f4a0b99f0228e38e711f4d29e7db47569b7f5d288d4fe8925ccc5d273a84beb486b0146ed1393e336bea09152d256	\\x00800003cb7013bff9b4243b65cd1524c098f4622f6e4c8b1c72e20a20c01f2b239a51a20b07973643f1638b143dabfb2ed0ca3cbd35187d29c1787577a6bed374385a8277a16c1de576c6e7687a76e0a91ae6b66db27b486d2b358f9a2d71295081aa5fbf2ba8da224f597a191cb9ffe604547b2410895b503349c9de574020a825b495010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3608c04f895dc44e21c3037dc739e4dc6dcdab7eb3bb0bcd9f2bf3b6f32e9e5030bde24652199311ad8a00b2df06b915aa614e387ca671498d895ed64cb1320d	1612376671000000	1612981471000000	1676053471000000	1770661471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41d1f01d865714dd671ef84123b2cef4c448d8c403a80ea7052becbb84458222b523f7ce1841ca458cacb7aadd370e1c5166e7b98f03888fbe3e1d23bb7f9087	\\x00800003a4ebfa4d78c90e9475ca575e14c36cf968474b225c65e83720f6a86f77193bdc7bf74c12337914cdeb1c602b9a4f0ef4a94dd04f27f30583afe8b66d65f27713c24089273d9cc95ab6b090b58fe4c3ae0f5cbd3a350925d6b55aa99376efdd8e03314a69e5fbf3a5da8f07f2b809638439e0e9020bad63d7e6f477e45d29710d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x50d8d8e2e12ba3de1a82f36b75df3ce70fc2861154bde1649c1f1109e69c34bb71c7c930db9a5e8732929830cea4a0202a4202bf6c51e5af30e54d816b664501	1609958671000000	1610563471000000	1673635471000000	1768243471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x435579144e6b1d3da16de37b2813d7f918e8b4abecfd72cda75311ed9caafda04f14c6e88d74b69b3b8ab8a8ada6c9072c1dcda49eefa1cc2dc5243a127c0bcd	\\x00800003db8e68ebf67ee6d8da89662096f2eb85ab12e2780838c007cabe7e6ff584ac821a1ec9a3db60afe4c57b12f0e4ad17f249a572e6639a0f9eb900b7f019881477401dcdcdc620164febe5308e92e1f54782829312561d0794d534a2df7b61e77c0ddb7a4e2fe16ff43e3fa55585cd1ea4a44d5dd81bc087f5ff987135d87bd1d1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3e0a28812ae1cef4c62498c14cf00fe9043a30f2ed5d28c04d677ecdbdb91847e43f228b76d44be1eedad08d1f7ee4d2b215d326d37ea99f81074001a010e801	1636556671000000	1637161471000000	1700233471000000	1794841471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43edfc6da73e4ec42a715439af06b40936b095d09ed6ab23ba1d35e14ea1bfdbfdd4e6371107383c6fda029ab81c8eba1b6e99a662666aaca6ea72780a247b7b	\\x00800003b364afffaf738dfa9041883179855b402234e105626cd0c3320db1092d065c07118bac138e2696bf62370a3b867ddb63c3066db57fcea391904bdb2f3386c5613a1e65e96530d6840c37dbcbcdba9adb5864305e0615d36fddd354dea8b2926306449d4c8e66dfad5760673c85256020b441f0944d043eb7289747584cd40055010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc03fd12e2c8c1c161c3a9abed294789b0d2866fd45e4b82b882f18395bae07f76151914cb7709a95c349689c2da86b29c6ea009bd89144edbfae3dd29694840e	1625675671000000	1626280471000000	1689352471000000	1783960471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x444d340c38c6e6597c148a0370cd0774e5802674a7beed81c0bfb66cc270e0fa3b121d235e44f08210047d0d833938b1ecb293c6d3c9a0fae339fe864922d5d7	\\x00800003b282a7dfdc0d7bbbf5eec0b57e17b249678d0a1d29500ebefafe77b301004d6cff2b6ee2ca0fa61fa18b89abcee9af8a3ecf2f661984a38e3eebaba86137c6650d4dad089d94668974a6c4fc34ec0c36175432a7febb9b852d2f205c7a212a8f26e2c22cb2de8d5d5683c7978bc1c2c28dec7a7316b480d39c503d436aedbbf9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x540cda816b37429f2f662641fafb34415a57b149f91dac04e6a9330657a7b7a330c73fd4496d739d03c13f254226553b90c46587516afa83b44633026a5dce0c	1637161171000000	1637765971000000	1700837971000000	1795445971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x48291ff5edc3a7d60929eeb090de3c6c66cd11f3a9809548adf46a2a6b2c2c14f34c68fdbd5ab001368d8d4da855a4219b9b1cd954fbc28c5f62b6899b6492c2	\\x00800003e5c430bdc84b412f17c7943a38fd4fec084f04795282f4ab922a0adbc6b22177248178c4af021ba36783d8d3a2d47a782f3b47fdc7e6928258e2004353e7e8402f140d049d36d615139734ea68329d29a07cd9b1031c7b6e09f4338f9fd893a11deaf0504dcf0aee94e255fe54493921ba6d9da712175f6f0faa7b4b83d25805010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xcc1f6efbafe0ec16e8219d0b8a0ca56a988fba67219ee3acb8ccde8684ac7941789ee420cc04760818de8fd55bb2c205a931ef7551130c2505c74f02be2be501	1631720671000000	1632325471000000	1695397471000000	1790005471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x490d4134eaa9615515ca6b0fcc72a2f5c58b529e7c6f93747080500722025b8930d0db93ca2593af66764be8c6466d21594eb7afbcab846dfa138f9cdfee24ac	\\x00800003be8dfa8dbe7eacc3573576990921580036b7f9d135690f68ec1ce7cefa4c99997cbd98a3398dad57b37180180795b514105bfaa04dd879e5cf1ca365c8b3215b4e82a3f070163b6d0b80dcd02246f84024d9c264917faa76eebe8be0a30b767a5eeafa4fb507e480eff4ad4c00df9910a5532b15c078afbabaccd3931103c38d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x50584fddb97a53d4d26788c5c2657d456b34b9fc1eadef5195f62935b6c49aaf3e02310936bd84d85ade89e6cfbfaf45bbb6e9a900e7db7d05ebbcdcab5b3a0c	1614794671000000	1615399471000000	1678471471000000	1773079471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ba1c666f9e1292052b813ceb2e847d6d9e36f23d14df4b245ee36eddbd033bc353d8b1be2b4965d3e200148a75f903d76c481a66a587e0942bdd12d02d75f06	\\x00800003d694a4d6d9c3a92f32eb7e8f20c26058c39bb5a381fde49398a38a8a27e2f204e454a9399210cecf0c9ec876bc5c2b9d1b33207dcfb3aa9db5db24e4c6d782a47db9141104da839a7b6541ff42396e8f9fa361bdb79d58c6588125cea4a96276916d8287a062acc43ac91ed0518596309c9ba51ee97d3ab4583eacefc6ce30a7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4f1b62e4b766a6d4c32b4f212948acfa8f1ea52606cadeca93a17e93e864895bc0d5b00178ea3d21dea845530aab6974add68589dab2989eb69ca383c07d3a0b	1614190171000000	1614794971000000	1677866971000000	1772474971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4ec9c5c9160d7742aa73734a12aec5fb63e49ede740679305cae507cfbc8f99fb9de63c86f4cc2980b28f59d94c3be133528047f129910955bf37b1eeba0cc08	\\x00800003ac6d450cf8ee9e3d7b9643deca7c4123dcdf43fe144aeda13ba668732dcddacfb4c0acc07d0006467f3677a49945fcc683c73f70d111c8f82450e485aff2dd64a5fa54c6c47ea01272d3b84ee96d093468eb9a888fb31febfdde653f16c2ca2cec112e80b5777a301d24a69b661acd81e70610ff4ab4164dfd70efbb0c523adf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x03a80468325bc986111a00b7268b528b4f686da7e9ad132f34a21d334de5d7b8e57663f40fef6b27af381c38aab4f5c860924814ab8f41ea2b6e4ad062da2109	1635347671000000	1635952471000000	1699024471000000	1793632471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x50add2bebea9a4fa8fc6d7282061259e9cbf8a8b30dc6cc9d6107176c77df641c344534db8d02ab5d2bf5585776c14fe2ab316b918a968cf7227a6ee88089a56	\\x00800003b978d21b64c0bfe52afb8710c8b15045bd9342724bceadcfc9a6c65bc8304e06a662a1f6bcc56634bab025bd165b1398d8022d297571f342a730a27c5bb2d426dc8fb2f0b0c1c6ae0b72819582a09b91d27980f64d4f5f155d424d34dab6bb1dbddc5dbf7b4f753a1db6621ed2965d91f83838d9c63377edc6fa70b2bec280af010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x55946de092b8973ba54844a1449904c7d38d1aa45c5d468064ecd9fcaa22e7a6f742197fe6ebb0a6747bc30004a61c8c0ccaf3134e46d79fbbbe625fd0a2ba08	1616003671000000	1616608471000000	1679680471000000	1774288471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x590dfc0c94400ac737860cea4983c20f85500c3779f21e04b4f4ea5219f84c19416adb0e6c56be55280954b4be6000da7f2fe6201ad7a13a08ad33337921166d	\\x00800003c921eeddfa1fc237761a9e27439ae210cc4a6a6aad840952983b0bba2b5563d2fceef876d72222a28d9d3991782060c29a917549afef28ee41f80a2f59ed42acb6915f9d7c3fabcc572e29b9661e1a26618a46c49b174bf62dd9bc5b955b1806a6840b9165523d29cede6526ee6774db69e876c29d59dbfd06afcde690434af1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2048692e7eced3fc70c2d18260fa0c158afa3c402bb85a2ea0b14c818af0b182ca8f8928709735b3b68e4d940bd74690b3537c86654e4893826c0bc8df5c8f07	1611772171000000	1612376971000000	1675448971000000	1770056971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c7571e56e1f3c1dfc1aeeca21d5add19f420d6e4025972dff20c7e1ae6691cf2ebc484796ae5c8c2eccefb3f7884efba3128cf112cb45f15ccd7a0a691c8115	\\x00800003dd690f74f54e44ac3c48eba6ace796f92ed0bb92ad24f0fa3dc40341808c154fd38d7b3f555f099553a299e0492f0b9c5bc02783a8a4584120607c42025b9bc2114fcb363822eb22c555cfc941bbdb331eaad2b64be2e2fdb6f0f5153ed4e19ccdfbe570567699a79d7a54a1fcccce123059c2f874644311253e34d6b1b50e3d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xaecd65b0bfa1e7f37bf593ef20c28bcd7da2f0f68a5f7edb820bcc31934805ce2732f0f56ab799ae7d266d470b3fa824ed0a4a2abc8f8599f4a9dd2cbc4ed00c	1635952171000000	1636556971000000	1699628971000000	1794236971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c19c57b5347249337c8361715061203881f3369a8b0c02de88cb60e292f992e7e7288d91fa11a0a2fb06eb928635fe572a310adccd53132591ca403f3997404	\\x00800003be42030c116ac1d202e0a1324a80909c6679b2fe1dce7ac1d27d38b8700e718a3d13f6d5eceacf438924d7319673a013893a8915e5af37c556a253ef8b4c3b997b97728d70cdb84da0e84bcda986025ae64a21b6df705121ab2b5a99a4ca13c93d0e47dc15f840bf11b74f2151b76c253ea2b95d09d77005a4a98b3eb9a73097010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1e70a072774392c6fc9a6b8f8a740ee0084bfbda71860413d1bad02c96f4958b8dc7341b3815d9e311bcb8dc179bb542d053d3f28e4c6a66d72d63c59a67920f	1611772171000000	1612376971000000	1675448971000000	1770056971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c89f74b4e82e0b198cf966f2a22e19c924e21bbff581fd3ecd80476b37d7d1eee4fc48bff7918241b597cfacc67a88fdec54b013b0056f0efb77b07bcd647a3	\\x00800003c05add91deb01a19f75afc1326d8133c1511cf5155efdc8fe2e61b7b630bbf485eb51242ce6df355a228f89424427c854c7053115b1ec37200189ad92808791ff70669e45b83b771c3680d320d56ac5a4617d10ff98991c146e38e8de5aeec61f2a5709e67380c2dc9c35770b068f923f89f1393030efca29c8f2e30a9626795010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x10adb1291d338cc78c933f37b53ed6761b9d8d93c930144dd53f48891a82b7c2d0ed26b3f35056daf664a2612876ad28b2f355e74aab2985faf284002e213d0d	1626884671000000	1627489471000000	1690561471000000	1785169471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f5d60d1649e303e3960865d95a219a13ec37af14ad37665b70fd0af7e89c5215ff47e4006c350bc93244057af88021e63fb02bf88261fac75d5a4cbf6d7ad95	\\x00800003f630c5678854e09505175906e0629e5e64972feac896c022f95788ea8b63c614009e749a0c9915925ea3570bc9cf2e05e281bd47d5870905869c3dfc52ccf3e3d129821af5fbf84e9175017751640eee0ea81bbdc0a0117f655ad00296080ebfe614a6e3fdfd4e5ab7e8da4366ad4220593dae3e935e6a98c6a6b7639f0fb283010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xcd71ca7259f0a6a5c2abe53d9b17e0997ecb71963748d3fb748e8cd55e7ed846536b2dd4aad017bdee878fc267a49ec286ebb7452bf6cc206c1f4e454386b50b	1622653171000000	1623257971000000	1686329971000000	1780937971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6031dec6beec15dcbf64df4bb8048524a82aa7d183a4e5981c0df4f8ecfb87f13aec3112fd2d772702d5dc8e5501c630d3292ea98e45354cd516a014a4223c74	\\x00800003acfa3854332e5ae0e7618e146ed8a94a2b5b56da1302d541a811b7f490238baf9fc80aa9dc40ac092e46fe52c02d586cc487c21f64511d224c4583cf6987a033a61f8520235770e539b7742706925e428afb1cc90e7bdd785245f974bda95af39eb2ded8cd116e9f210ddd0352ab42975b8bfbbda583eeb1bc107bd9ce32a4df010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf3ee67063b45aed3aafdbaac78fbd9c74d46581f3fb1839534568f543a9ac2996aded35f8b6a726a88e2dca421673a06d7aa88c7deb92d044abb8e0ddb5eca07	1637765671000000	1638370471000000	1701442471000000	1796050471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6171f953183981f26db93044e6ebee34e20ea32821fee384486dfb7ecba7c1a6c86045889089c8eec91f88c7c2fd3c407011983fe132848b14b608821db36c58	\\x00800003aff094a5c6e6645281018115c7bad020ac167c9631761bf4dba80ff1d0579989e4bf89d52d9fa66ef0029b12057b6e0cbf1c5d40195a7553ba5d1a4fbc5a391b1a59cd2794f0bab42ae84d0add5decbfec3e6e98c30f41b7b2d03cfb95f1af3b721e3def1b6df00a93a6a3dc27a91ec98c41d4940babb88ea4011d940feba28b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x27b41028d07505ba2aad37012d0b4c76b52eaeb93752b15994cc7bb6419843e58f298b427b796db7039c38dbc455b6fd7e12f1dd37434b1cdaf7aa6ee26f2905	1631720671000000	1632325471000000	1695397471000000	1790005471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x65111091fa7d5b5eecb704ea34ca2da86ed232d147be1d46fef8d615db7956ef98a138bb3a881f141b3b54ab6517290cef43f971b2de2c2fe70e4ee2b0b8e19c	\\x00800003b1c797059630770d99623d58a17d6c8725e76c3234d1210f4102e888f9e4e505ab29a0e114e87cfa7c9bf6ab05c72ca84860aa22cc54135213598801834db41805dca8c7f30e80200232d238189074b042b62cf739460783e8e3c83478e49ea395ea58afb261fe3fa5b9d7fc67346a4f8eb0af3dc06c19f60d1ebfacd0d2d78d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8baf0d0334c96060f77f4400aea7372e7757224eda9fadaa96e3100288e90777ea03a1f494ce9dcd43c923ee7237ac1318e0ecc4d06afa787f1309bba2a43008	1633534171000000	1634138971000000	1697210971000000	1791818971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66a980fe16afd9f3dce24d57564eae4d0337817bf643f89f45ec2799ffc3bf95271dc977a83279f57a42cd4ef22525f11313f891b8bd0994cad26aebba5e13e1	\\x00800003db0496dfa05533ccac67dd315f61566b97694e669d3ba418505c5c41e28530a65fcdcd3148a8900207e76402c3fae42d98cd58924ca68b8a0e2975735c2ad220a59ba3b0b2d79ed5d07e40d2581727a55512ffb4e5935e3e873b351282570c4fb100c27266a0dbc83258c0c93b252727174af89f5058bdb6dbae05d0b3af8ce3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3ef2930326621ee45740aefc08a3d390a0f14de932aebed52f6cf0b08230996b7c938ec6191f00f0b2727db131f6a1e6ab05e39e4c4ec14b56af10b12318fb0d	1623257671000000	1623862471000000	1686934471000000	1781542471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x661d44c611e70cec26e8f4c799291aa721055c0e2422da4ef542e1516f619ac8d3ff2f124a5d9f0c2e4aed8f3ece6aa7a1157a1b9ececfb1f2cc0c6878a0f888	\\x00800003d19177c106784a6b3201b56b052ccf650521730c94447f649ee7d589ce12f51456ed570a092e4443cd11a87a57394311fae0ba18ece28824aee67767d7ffab4114ca92388cc556297658f0b263b410e1aca06b11cb86d6a697cc0c4b9c8d147e0c0b29461a5853c8c1b9279e11dd310c227504824a3c1313073f78a579e7488d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3aecd3ea780d798ffc9a5d7c05a7765cd4d5b02197a47059fffcae9b2e4ee0606885bfea7733ab8b13f7b5feea802f6ae2dd38cd8bdc4313c4f51c4d326b7d03	1617817171000000	1618421971000000	1681493971000000	1776101971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b25c44302cc4f863b2537d3b8fa1dc6532fe018ed53b66ccfbb73dbff3cd764515aca84fb1c9c28e02a51345cc9f9e4d49a330913d8d3b4b4a1a9a3c7198b45	\\x00800003c55a0ffc93aabd2bbc7ca87a952bbf7169ff88fae2b55a848c990d5644ae2fe32f8f0c229b7a29aaa2043915fe82b15accea19cbe22c13a00dceb0153c76d069fd92602e802892b13c3726f81a4c37aaa4008e99dcaa880b67c4679f636dcb0681ca4774dc4d7181e52d87827ac46da20149839edaa130cf74ff36d5907ea86d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8304062e2ffc917456d8b08e4227b393fbea515c2d68938f1fce84f20541d36e2993ff82c3a5895db4d9c409ae9158bbaf02db66eb524ddc5fde5cc97e5d880b	1617817171000000	1618421971000000	1681493971000000	1776101971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6cedf3fd32b19bf77f4ac13b8190bb623586f91dcca3d78290a58e39bdd344855a6327f4f7808bedadd8af6f68e96c5839eb43b9d3164d8f9dfc440865642ded	\\x00800003c35066f2a7d2af2cde7b0e9d7920144383890cbb04b6e5e4ca240ec372573c5e7e364c1d8528ee67695dfa1296e9f3ff93a559b944c258c0b2ce17eab983bc4fc94ac71c34ec8ac0f68930113266fbd26d1551428586d344f3d7066934a22edb6fd163af6e716eab19a5cd8bc5b7b928f1d5698137a82c93218d3072b78870e3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfa9deec39d64cbfe52e34e7932076e06ca83b6200d3b2717795ee64da6ffb9172c9f1f422542de2881e5838b8accf44c7a8b04f5c57a014aa8afb820cd8acd0c	1629907171000000	1630511971000000	1693583971000000	1788191971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6dc11d4eb40f68f9a43d89af61d8697996800e88b831f4dc0217c82eb866be396d73fc10a69abec6c672d365f777fbe582a291efeca877dbac8d598f0a777795	\\x00800003cb0506259408221f75693f64d86df524d4b41179b3e7004583edc86f176f884c8cf21678ba15aa1fdccc2f336345af6ce2be47635f3725a1b0033e99ddc5dd667db2fc1832185f4f4d56a3378599b0cc2835625bf4680e3b687367ee08024b2cf38bb4ef387d278f1a445db8bd432242f0f171cd68f7b23aa61b34541e151619010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x358f8d29aeb3ae97815c386d6b5e459ddee95e598996da7ccb8a147e44e63906bc575f67e52523371f2818778b7205471d537d8493d6c8058038d086ea72c208	1617817171000000	1618421971000000	1681493971000000	1776101971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x75c59a4addfdcf318bba0bd9b6cd710becba8c83dcaa5e24e81b62dd7c31401ea2021bcbe0492b52e4280a75aeff2d0c43c3d2408a490e37c27e2efe7882d2bf	\\x00800003a10aa04f9414583254fe59e6f6bd7ae06162ded7d6beced33d25364688e3d450c37fb8656960487e9c821f9ea33f62a210959bc518ee01865473575e132d519705140d20dba1e430a50bebae37fd3dad4bb277ca3431d746f8ce18d561d6d5dcad3dd608ece88a844066275cb50c6093d767ffc190449659f3b785ebf4fce853010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x34216abeaeb5d924774505cdcdefa9ced15c4abad035e4130677aa0fc22d73caa50cc8b2ca7c02f2b82b69e2ea066cf6ccc8166f762b95235329635c0049750a	1611772171000000	1612376971000000	1675448971000000	1770056971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x769d4e2331e5e4a06eeb08773c8458aee1e4b69a92ecdcdc9d426b5016337709abace186061d3b275579be09ca7fa19f5f39d3060a388c902ca4388e99e5defd	\\x00800003c84e449b373331a4de21446ecfaebf8b071658857134186829334c84c6474478e3d2cc7453cd8538cabf7f4d1b62b74b892b64ff9f3827a7bec630526b208f47def83fe1f313ab0546947382481b55ca5ae7c5f369d47949e5b662f25275d875aa87eea42165479e2258f3af935069b440c099197dd75ebb61015e5d5d1cb013010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x22d14bc8ae370d44a6a99186f6e7cccad48222c055a9d6881279cda82dde48bb78acffb3079dd01093880723096da83bc8924268bac290e3d10e6e80f334c105	1623257671000000	1623862471000000	1686934471000000	1781542471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7b6548e9e83da7c780f7c071cc6d56ba0742d23ddee1bce53bafa022e7f24f47d780c7ad59c2684e8a0856bc148e174a810a018277b247517b64f0c1ca1d057a	\\x00800003f4e5b9d6ce8ffa552aadcdac03ba02dc2d0dcdbec4da3c9f3a2758dbed3d28989aff82baf3f368387b5b9238ce7bfdca473c89bd7133214239397d4d52183c61caa77f0f7106ae823ceee2215fc4eeb0bd9bd3bf8112b9baf93093ed6f8dbee4a583256e7d298b1955fe64cb0014d289c392dd054f475228c771038146b7064b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfd7f2006d1ac7892402438ddd1631c422eb50e5fcf46f6cb24949d8d6b58d57de7c1a1dcdd76d6dcf6a9e53a499971e1a11f2461f22400c6e2e5b1c2f7993d09	1620839671000000	1621444471000000	1684516471000000	1779124471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e650e5b11e846abe372c2ce278879d296ae2cfe9f423da23daf52e9458baeea5dc140e08408dfd6482d93200f3e08272c2a2131e031cfd01efefe4f3328633b	\\x00800003c7b6725eeb6812a6bd1fd217254c683eb763ac5e509bb1cde5f9f1b7cf078b3b03f0701edcbc1f47e1f98ac7ed9539621a99a9294c8fb38b56cabeba7dbcf878237f05b5f121eb38a7aa6711e010ff36c5f98736bbc05d8f22b43e0092ba0aa2ada5f344b52aaf8296258e00ff4845a0e4742f07de2f1d09da8ec6ad234d047f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x88638eabdd90317a9b25ab0d44085a699904aefbe0241a4d792b716f119830e06d0841209c8058d2a5a879138eb2df1f2a83879f93f6a690e883e3ba1cb67203	1612981171000000	1613585971000000	1676657971000000	1771265971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x80a1bc3f501f4a4c98f70fe72227d361b23685d351600863f94fd872a9870ed8baf1e3e18e4dd74a9a786e4e921ccdc045f9dec551c29da21776ff3f05942d90	\\x00800003d882f5ee0ff34b664a293689219bd1460852d8b6609eac4de143f9fa6b56defb816aa2f17a2e1b8f321615a6a16ba597635e70d5601f2b6c3a42658e91234590020beded9fa209985db020472742166c3ede574eaa573522f1ab15f8019d73fd57af5f1573d77325aaa8b16edcceee3a2e3107f92cecdd3aff59bb690c912b27010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x016c4f4a9d8cb424985d0077b063ba86c2a7252dee56a739e16c3c62e5c54248f9c7c1ee6ac98c8aefd25fd76414561fa72f209afbc7ebb0d983790b2016140f	1624466671000000	1625071471000000	1688143471000000	1782751471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8131223a702a992229ac32f95b88dcd7205f3199b267a194ecb86f01292c7de5923cbbfc6ab088a472dc751cf48e2431eac4847e4c7199a1e204fd55d8a31712	\\x00800003bf30eabb1b327f76f46ae7179816f63d95a5dfb9ddb8868d925d921de0eeea11ae41e10a1b7b0abd71b4723991c023b49e39d9b5f3bb534b58516c52a081e82ce61feb5aaae035f71166883137c797baefb902c2e5d772a1230417bb7173ae04ef909303d82c06523c791f453b55fad9a09e6abe1a0d6a6dcc0fd3d9953f5c85010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4f40c3440b18bd5490a03ddebeddd09b5c3624295d67b1ea737ed562898b40c68e1ffc3ed33c81d28df5204a5339e4ce10e1730694b83b53a28d0e2bcf324708	1638370171000000	1638974971000000	1702046971000000	1796654971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x86c92f107a6e61de7c6a1da290d53949fa0371e1f827c0dab7d2d33ff90ebadaab5d31e8d2aea06350e8c3b3733371ab738d4efd0a689add5da2e2e1f71dc6c3	\\x00800003baaacaf881b5af8f78909f1e882496b42ebf0d6ea9a2593c381433293c372782eff00f71bec8d9d2d2b9a81e13992774e2cb514b7e975b7c97e80e6642ecfb1dc7e1a6c3cbf75372e23cb8e900fad2d3b83fd6d9ecf8695a115dfa512d75e7a0c1b18ca8357762454831a36b906c60de1babdad9f9fc35257d7c156df9e80135010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9f5df8a4c471475fb4bc548587632e5950bf3177b74b1befec7d9a6ebf525afbac0ca71ae56d0d93be3a98e4ee3b795ac009b90795e06a06734622708b73ae01	1621444171000000	1622048971000000	1685120971000000	1779728971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8775236ece87a1c62c0b95808f20117e4f9ce15b114a3d14ee964dbb2d2d88ba6527f62f926eac75b24249ead1aec9725dade5ba42e5565f733e996934f82437	\\x00800003be8dd945f8e94b8914de604ea47a4efca1826df3ceb0237c0da89e42057f9986781604883ae5a18fa5e94705c983e6128e20c3603dd5160e5c6a0ec3f941b6806d3c3aaf35b294e65cbc68e5c39fe519f6580895c0b77ebb7d0bf10ea803ff5a4c31f83ec5831502214bc39ab88e1107de10d54e20ff9d8cafe32ed463c9914f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfd420e6e15fe1b10ad95710d79dd8e1c73bfa7ec8c0c5ccfde67bc5f34702df24e58b70858599c55adb5cba0475a5805dce271ef13e20708e45e95ee92fb3d06	1619026171000000	1619630971000000	1682702971000000	1777310971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8af112448a08bede2020cd6cdcd8d84e71892f85fae9e9341487f5b6609d6f63e5fc6438936de9046278242af5ad3422a549d311aa39e1798fa2393c05513266	\\x00800003f1032c328549413588b7a6c5576c0161d73784ee5faf5ff8acaa5d1b0718eff91b24a7499623fd705ba3d0560cfadf4ec95d606b470a2bf9e194dc716b4b8d6a12f698204c269714457928f5dfe6d7db1b5eff3becf9a1dcc39d60b3f1945dcf9091a5a78a6bcf7eb6a025239ba92cd93f60e02c676b1c61f82891326064a28b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb7646e2503657207fd0038ca7897963b652a3b053b545d078466ddb236c8f6bdb2b7f7b7385d3eaf37b51f0b6140a543cf0c61d05b0fd597160ec89f22cf8409	1612981171000000	1613585971000000	1676657971000000	1771265971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bc57768a0003c0a4bbdcae32d6be1ee8377899dead41c21be36bbd4f2ac15a844155e1fec905f947d01ea10dbe3e0f8086f582e9bac2d6b44e044661497a54c	\\x00800003e35d861b7310a677c1a9f18011a03a1af2b7389edae61770e8eac7ea99a136ef155d23c61164130f6c2d2fa9744f2c1891aa0d945a281db213b62596fad59fa792ac1f477c0f857ed417f207d0af21eeac1279db1ab71cab1480621c4b7a9ca39aad1f27470d71ba796d1ca0dc6a5a541069b4c23ba1f96aa874176dc3b51feb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x91ce6eac045238eba16ed7c456bdab1ed6722eb59339f40465062a0ce59c9214fa72e0b0c428d0cae0b14e492d87731007e303bcd0b52caf18c93a57c17f870e	1636556671000000	1637161471000000	1700233471000000	1794841471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8ee9d9ed11764f30fc81eef3514308e10ecb5f5404caece1f98c5e3decaf454a725abed44ca5ab5d1b2bf57d458bc4519d2582b62ed402f166f737fc6284bfbb	\\x00800003c7767b8cec3ca207a8149624c5f418dc5689db51c04d4b872c879918553d0b769a80afbaf305d3c9b842241102d099d6ed567e59802492e79e31b60aabdbfe3358d70b8458a8c10ad797cc9f9f635dbe8df4a6ebdc050bc69492a753cf6e3cc8efaeea6c4edb84bc0b0f92d33c4af7516855f164da118fa549a558a4b09cd86f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0310ae1983f253bb5f849db0d3535100c6575b74c502db95499d56d5beb6accc3300cf9f5a10884285efa7ac453e3de53e0dab312105a171de6dd4b4de2c5608	1629302671000000	1629907471000000	1692979471000000	1787587471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x92ed656d3e0eb859f1e7cf76e6ecde6998e261c617619f9aa4ade2e6cee3e58c1c6a68fc0886c556b138a1ed3d6ca708e234f6d3768e03f9bddcfdbaa56bb4dc	\\x00800003ebb90a2fcfcd8c546692c18b49fcdb2dc73194d081749a545cc96003f7e69677dedbf7de6e9b34903a0f99b3f506384fbd1f47a63d8d881f8f653fe23d338d681c6341075ecc09ebf598dfefb6b34346c6e9e608f1a00a75069900c9b27ba1b956123f5734784a027ec46573c33c4b17ab9e6a176c59ab9b4ee909b0dffd9f01010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x836060f1227e0810e849076779fecad26c26cee28d6552a41261ee2f5521dd481488c9648a27f0e655a20588f71d24018963dd5ee7feaf0b3bfa06e29ba14409	1630511671000000	1631116471000000	1694188471000000	1788796471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x930d5399cadb7f31bd4b7cc756d7da10d17c21e85b933734669d3c1e94049f4dce36d170a1f83e94eb5e1674dda1d300f0f8d347a467beb99339c770613f63d7	\\x00800003ad652dcda99fc38504f9e35cdb0a0468e574152adf43c887bb0ee8281d5edf65e9e78105fc56be417ef01a09621bce82cbe84a9656ebbed34b3addb084a0c1fcf582595cbf05714b4c2b1f8ac52a36d466f1d7581d8a37b42eaec59e2acd3b6a891ab35055da2f1a1bde520a6e539d4c45daf8a0e30b46a853ec8f6ea7899e7d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2ca61eeeaf8787001c43872103e1fe1553f3166c4004782380e3866cd848327ac820638a290f60d71c6ebe13033dcbefb3a4e2e3df4cf59a2c0169badc5ec00d	1627489171000000	1628093971000000	1691165971000000	1785773971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x935540b42e121cbf5d820ab8b6621ba8075e62a6721e244e9f5aa062db00790f560b8d4f34e6dd6f42e2d4b7a86ace17a015408cf1b9f40535ffeca99e3e7166	\\x00800003cc1fc225afee768fd33334eb8e2d9fbca70a526d7434d5c5c4609d2783bca2b51c45ee9ef2d8319cb272d659d74fea9c71371d273ff2568422ff83e1b9fb99533c739e5e308c229998847f124cefd7b288926c90e9ddbbc31f12c3e2dcc349d313ee0441200573e240d3383c2d5b50e60431f317cd4aad69c00a46cda673685f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdf7a2be4ece908385437757214e6cebde11bd7aac54582e9f6f7e0235fa9566d2036fefbdb5e94fe59c7a911e119b21ad3407c531fbec0f0e650004b21e30107	1633534171000000	1634138971000000	1697210971000000	1791818971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x934948b81256a972916a59f77f7f823a53117b77655240f3906fe52df22005cf143ef64ad3a04fb3edfcb1031d91e54d9cf2eb1d5c5bb043a4714658ede4e04e	\\x00800003c8fae223253d249424ec592761c32cd99362c9769f669c0acdf4986aad89a01b66cd0e4ebec4ea9e6b7e35676a9087ff4e2807413090f9fd480991bab7c911cb54eaf69e5a8692f374bde74b43d15bbf8ae379453497910e9a780a4015ad38e3e68e58522ef7ce3215202610dd8e3f258e30c01ec2647c7c2abf77793076639b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0c5144193765401e55e1571207f56ad29aadf7279d5f57e0d21f47a78913adf4c4073df91e98b5a554a811d8d3786cb67bce21bedfe3f264717b851ad8459502	1611772171000000	1612376971000000	1675448971000000	1770056971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x94f5b9773a19e2992a5409e3f38d7878d98248f1e0ca700d8e8f77189766b30671a57113c65dbca93c2f1004968baab0c686c439d12e052a6a8e9fdcbf95fee5	\\x00800003a63ada58f4208f020db96754e01de3bada999c6ac01e2574f3601b7cd7ff6c2da61e9b2d33f556599076817b2c3367d4b4253f247073425fa1fcfdf5cf37e6de98678b2bf85bd76b85bf88577bfbb4780878f045091852cd81e92e4e521373df642ad20de21b0177c4e027130a36809ec353e3de80f29ccc306a4488f6c4b53b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd85f1920ca44162bb3063d9d6d5a670660e963952550b41adc39873442178eb726204d4b67692146b2b5234872b389836335b0f414f0b04639a0822eccc66806	1609958671000000	1610563471000000	1673635471000000	1768243471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9525c969c666bfb97c81b4e51037f7194ae2650b05cd840bb3ac70e2656b29e39858aa8e7ea402f10ce3c716eef0f871c4baf4a1a044dd11e424413bca7d5205	\\x00800003c4eae90ac2f6e6097549f8e0ede33584c310f507d0dbe6b6af16f11f2c9f880d9cd8e1c112398b73ba10bf3d55c2822c5de03f60ca02df5dc52b9ac0ae693d15cd5f877d62da214351b5fea32416015534c6a336a2a09b026ea8949559ec80968d75d876cfb9c2b92a02799160ad58b2be01befdf3e067fdb3f84cf8861da09f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd6b38d11a3520d306c247c16c02d5008e9ce616795c432ab9a32730a4108731692190116bc9f57a482e96ba91a98952532409316666294ea04ff7768531bb601	1629302671000000	1629907471000000	1692979471000000	1787587471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9cf1474e6d88a56866bc8c083db482c38e0cfa2724977f044c3035a2fb8b0e6d30b4f7e83199ff2bf61281dc66536a313b90c2261aff133ab31a2ba4a2c356a6	\\x00800003d2d08a1049405fb95b7ac4abe778f077373e6489ba0587a177323bfaca5267c20df6fcfb7e28f646298abc97a58f433638c74f00c08b885d5d11d9057d9618e9d5386b150810a4b0fa35d86eedb96a40ac001bf50a262f976475033c7ff00223710e9ff8740d552926a827da793f25be4566b92f3cf3cab479797c5daa0000a5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7b1dc9064f5f939bfd2a9ddc07544cc2d6252c8f99cfc206b9b1b0a2d4d36f127ffc8a6e0eaab9ff9865c17ada66cbe29fec95a969700c9278d1e0bd9b73fd07	1626280171000000	1626884971000000	1689956971000000	1784564971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9dfd9e60091904472b36e127243cbd9d99bb3ec1d7e9461df351c50fd839c8c9b03adf7202a40f30fff161fe580e118f65fbf8bc44d9baf0a91bb3a71759af54	\\x00800003afdc21df2bf7f26a8e347c74b4684d614cb3835fe219a98bbd5300aca9d44c12878fe92924f6824d8417aaaac2bdaccfbfdc4beeafa996dc79fd1a2bc482aefa33ae8df06441cfc97149ede2f86b1b6e0a6d66eba601e6d38f2f758b02aed2035e8b6c9d01005208457416f1f258a834e7a0e6fb3ab7cb50e4a8db05058e1f3b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x33a6f10252198e88face923db391aedc3442af4307d0034678cbbc1ac403b3b5b8c227a457cc272edcbafb546fabd92e971315730742130d8c118ba84c590200	1636556671000000	1637161471000000	1700233471000000	1794841471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9fe5a3b6ed431fbf275105aec942b31d9cd34c3f9053acb27684f9045ef21510596b7fee30a29bb3d947dde1d77bd89a2c840ef6d75999eccd7260046fa14b05	\\x00800003b924cf2c1c90c76026592bffbdeb1de09c7d8daeeb29f25d2015f322486e4021d0ebcf5ef1d9400556ef04bea36cb5d6e54289b7e78f494bb3e2c25335c0295f770095802c7ba7b8ccf711a6418c9d1c03b69d2be55cab911ddf384169a4417c8bcf8ec8400bfad99ad53f30d150489339a866e6e18f6e116bf94427ee6aa33b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6ea8664ef3e8d2dfdb3ab0855372aeba1c3ef7738a19f7fd3febcd9b8e6e14bc0d535e3c40adda44990c86ce7bde0c1586096840e1cf8d1d4b6d7aeaaa9ecd00	1623257671000000	1623862471000000	1686934471000000	1781542471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa019ef2897b6e43eb0e9396f40f8c1ded93125534c8c87533a9b54ea6545c865d29d9a796b409d5d7fac104db203969c64fb9929e62e6657b601d92572c37784	\\x00800003e7b1fe542c64f89c61032926a0b530697ca1f6cf7c59080264766f437c78906bdbb6bb4ef148a984fffe162d89debc19bbf8e6f0385a10be3d31b9a734d0ed16e7ceaf7a5207d15b506d21aaf9e79c16421549847cf9742dbf5ff60871cea7ac4ef53621cc69448e5384579a9ca9b8216c8d9fc995fd4ea85ccd9583d3ec77c5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x34e79dbe296af0cd6585e050378af19a860c8cc81b658e84eb6587d317730cb9fd608cb0e0ac466a842d547b395444e9a730f299483a36574725239faa77aa02	1623257671000000	1623862471000000	1686934471000000	1781542471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2fd7bc3b1c6336f83291dffaa3282710f72c028b8503547bfe967877f24e22543d9ce917aee053b3b0c83bc9bb53cded15f57d483a728c73b96f7f5994a7475	\\x00800003ba1d8d771884a0fe880ce4ac931c4a3ec0b4d8929746bd1ceac75be513293ce50820d450856eab2179546b39829a98e2a8885913d58b00b036d4bc0ede3ba869efe898e5bbd5a024aac68ebca7d629ecb385db82b248b5e691f2e53d9321bece2753ed6093abb5e682890e3c5042b5558c4d4d398baccaa3c2b992df663c7791010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x90a2cf0bcf76a767ef19e971a3f61f45efdb07581da3b7736be56d0e31ebb4cdbf279c7e74b145898b9dcf0a212fe4f2f7af09d50d88e27afdc209a30aba120f	1620235171000000	1620839971000000	1683911971000000	1778519971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa645a568c387761bece85dfac8e6ac162c0909880c382c17a265a7044857b71eeb3b2a94de681fd48e7496708a1f50df59c09837d986a508521e1fbd19f7cdee	\\x00800003bc95ac63d8170c2c33cc034de32c4f5ba5e44d76abda0ca9c7b3f59fc844d93b52b7bcce90db899aa76b494322802a26a0a677b2bb69a943f69e1fc6d5cb257a38916394d982c8a7529946b671be96f5c887e27fc1d30605dc9973c9fcbf82f1d94678f4901ff16a6deb2546662818ba59741953f5d75ce8e53f4b0f9fe667d7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x18d7d6d0cabb8061f3518b6bf9383f5106d9f0c109246079c6781de654f20ce10043ed47dbae9928ea6e237ba7712e2368184dbe6c50c70be04316f99e9d3e0a	1621444171000000	1622048971000000	1685120971000000	1779728971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9c18f690f251a8ca632bf9fb2185139e581d0d88781bfcd80a80cea9f33bea72f82cef911f82a2ad87220eaa991985f25f6676563158bb326462505cfa724fc	\\x00800003f616bbd82aa7177bb54d8f31bcb4205d45da3336f780c8cd185c2ca55d6a2ffddbadb68aec6ccc986c69878b289ad44723e8672868ec33bc3e59b1cbd44adc5643dd35f426c936d76116be2210e75810c480f0198a3bafa207cda33221843a00bbfa3c495c9563d9016f309d835f21be3d61c0825b423fd56af80268570ce739010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x91b5f98b3ba89f540915dd4f180e74b71bc48094509efb7162c989b168b4edd0c33a9ebee8c64910c061b372f37bd3ad8f2fff8ccee1d715cfb76f3ce9a52e00	1620235171000000	1620839971000000	1683911971000000	1778519971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xad01fbbef921a77b39b91f51a5448de724fb1b5128a5c7fd42f481a0907417cfcc29da6aec5c7f723844f8d648ec7e7b3e86f103154e9e6eb031ab686a5a6dae	\\x008000039b3bc1cfca5cfa2a0bca7e2ca4fadd6dca6ef7837e0f521180acbf9ae86426062346b8616a09cecc9ed41eba9bae5ebe680e44a3270e816e3bafa64732bd79f63fd51d2a0cb65c149ddec664ba4ab68b22a2dc5bc8ae1e2930b84a008ae64bea31249313202c41fa269e7308f95638cd9bc9c333a4463a4e41f1863d77193811010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfcfca054bec99d31ac789dbc3b9dd9ddb5b4b5c57d74d927c02c8fbe34d2bf9b5243d2d77385573f22cc257d28b8b6158e77b81c03e2f65990f43fe36183f70f	1633534171000000	1634138971000000	1697210971000000	1791818971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad893f294ca42f82eeab6ae1f137d53426858f889851f6333b3f00a53f8202f6604c7fdc7162136b8cad11f0a8f49f6deebc4a66876d863c016c251ad7fef898	\\x00800003be1c881cdfcb97837ca9a696cd289ce8ad4ce515c0b3962cfaf1c8b525865e07ce59224f6480e5298c7bdc8b6c6aeff42d99be4c8fda3d66cd944a8c31700b75afc15862606d8518d6b0513bfa430a0edeed5879b48d989a79f4cb14e126493a7d0a89fb02510f2a47db85953500a05aa2f40166e39a06f427f2808e56a4ac75010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6e75b9837a4b24c18acd3065edf7b0d05f8c1a973a32287e65eaee47ee290620e3b1c96019491c504857bad82542f22e95d6c213fbb39cf3ae5324db2e19c106	1626884671000000	1627489471000000	1690561471000000	1785169471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb4e5a63153bdc4817b2628c496b5d1b160f865f48755e11e26989328c393bd56b402313828ab34dd4ee9e2735141d041db11525595ebbf98c0aa2484bc74a9f8	\\x00800003b80d48014f0c292e9788d7416a94712d3cf4a53dd8c49fc29add6b32bf2b3349a3c09878248b43adb3df72a0231ea3be16552d1a77fad381bdbaf6a869a27dc3f60ca5df8d408f1c1f199c5fcc66256202b5d40ec94a861e80aebd2ca9d32c4d93c7777bcd3062ab603e67a4be5f454e6cb0c7a9f8d7c1ab2e708df98950fd6d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa5ee7d5b70827704dd7d8229922de386233b7a82bc4ed7dd6a55c73dd0a7d76b488faf5dea183861ab0ebf871ec7827c49e66354ae4937996550ce07ab4aa704	1615399171000000	1616003971000000	1679075971000000	1773683971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb821450acd904385603afeaf2dfa3f9cbea6ec335f3812b0258131927bac5bec8f716bc931666d75e796220d0670456ad0cac345be8b07317b35238cb0ad7411	\\x00800003cb3292e496f879f5bf0f5f735caf49d5ccbe89d71e14f77f61cfbb18882a72cf7a44a4743b9b68768db0acc32cf68c1bfc035168207ae74e72c962b38ce8664bafb663e4a6b17aef3a70cc70cd66640ef29b2d8a06533099c574d7fdc3fe644ec2b9951ad8a55594bd59bac4544ef8c92453b99aa3d0ce97eb1176c06f4f06c5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xce936471495db43f648c2202369145e3783627fa6ac22dd9084696a2b357612786bd2fbeef8eb9d7ca30b53e6eafc59262665b460b71a0a5f327ea997c97660a	1638370171000000	1638974971000000	1702046971000000	1796654971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb798f4b659584416a5e17241fe2589ed7708f9198ab6bc1b6eba12e83911ce7861c5147160cdaedf68275235c04d077185ebfaef572f1c31d70be5c5aa12c83	\\x00800003b42d7612fa7ceb2f99ba281ac2953bc9b4e5dbd0cdac9f30cd13ef4b8722161335c4f75c2a1209ccd08a66b40fe9855337d67fc10ddc4f0f724378f9641653445403e8fdedb0f026f23ec885277b467e59a87f40e89ed75f656df2752eef4c1f1a12e70b5bd35032ed62aab230667bf4fcb6cf6653fb3d33bad03fa065243055010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd0b5542f836517afe5c96cf0cd99b05be2f7881dda1597fdfa353eea335b69aca7227fda9d6dbfa44ffd1de083a52a910b1c9c1e668461521bc6802e270aa90c	1639579171000000	1640183971000000	1703255971000000	1797863971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbdedd119b13d83f6a6b9533a4ff53a52f9b638bf6d7a86eeb785a154e08eb9651b0a0a5af4dd47ae3ea1a7d71921aa6ad65403f682a8888d60a253022d0775a0	\\x00800003d24e287eeda6a4b3e98fda66761863f1bf377093996d4e522529d71e47e063280661bc3dcc051c11aede53d5216d5ac20efbbec5c774c41edd2c078a89fcbe216e0a542df05a98fc8f8d4c63b469ce67b8dd0e8b87f948a74c7df4dfb1b7c6ea508c09cbecb8cf37d63ee5bf397515e1d516458947b52d270e10bfb9419e863f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x682817fa0f03e547f99993b6d92d401502ac93c3ca665409d4543d1add9df69ddae757f247e5ca42bf4193e9d9ce3fcc29d979d4d3a6b29789d0bf71ab8f470b	1617212671000000	1617817471000000	1680889471000000	1775497471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf29c954888cb93591287f0a0f3771212b6c5bfb5fe82eb15daa196a0a3d8056649120315788e35dae53aafe962f18bf4a96136bc6ba1bd295eea53b20c558bd	\\x00800003a91f7fb83e4c637a877e825fdb85f27c296377dc8c1adf8920b400ec00e1e3ed23300f3f5443b85f6b5acbc606337d6e1d1a03183908f5c12a92641caaa701bf2953ac3908696e061c0ca7cd01ed123f5a43ed1800c62f3927c6b4015bb9bc793b10efdc874a71c6b09be14680e81bb5ed6055f280bc382d3985bbc72e23b3cb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x850d989c8214e8ca8112500bc10c0bc7bae841506c7968c90362686cba7d7d36420681482f6c54589365d367c70081d43530aa8da4d753e79c22a0b279744b02	1612981171000000	1613585971000000	1676657971000000	1771265971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc36d1299f253721a34c7953a2785371312d2a33a4f1623bc7e1ce62e0bfed19d2c1641febca5b933ae973d411017f7a41ea7c53da9b0abce9f7fe0c4240c0911	\\x00800003ae6fe017a069ded43628e94c969081d306c4546f565cae25143bce410cbebd63a3a17941d4a7d4c3f8319cf8736719b6e01faaa330386f56e4137b7c685007f28d6c4a1364b1e66a5cda9a97bfd0754c2252607a284eac6d1e08b3d52393cd33c202b1a09dbb2f72a060219304d73e1f157a2a20ed5be1e7c28e2ac637d9fa65010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe574a44f368b278d9610582f40c3562992d3a96e28ed1ed69c28c5c16dc019537c26e13b658006ceb3bc13a56858086bda993bb562a1e135f058de6fcb416e02	1624466671000000	1625071471000000	1688143471000000	1782751471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc885b46fc8273847c060a5e9eb57f6b383e8708085225badf59e47791ed9dc621c71adecf447e86490851e2b3bac357d432a57fd82474dfb173d01e86272097d	\\x00800003c023f44d0f94b9dd093f7d7c60380c00589ac1d966e9fbaf3f47be13601dd57e97e838cc6fc1bb6916426a0bf0aa006bc5f4528d65a2b8cac60a55e8b404cb425e41b36fde8a5fb39750fe806cb60027d425aecc61f1379ec6d872d14251977939324dc1eb4ef1be462870d934cf0226b6b44c012e57912cf58584daf50f4c6f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5476aa7af0db18bd67bf06af0862b6c91d85223f51f9347b6f05ba738fb5fa93d82d576028297a36b8280c0b4efcf22cb96609c8f8f92cf3618d237fbfd1f20c	1612376671000000	1612981471000000	1676053471000000	1770661471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca9993aa3b67abb5540c954fd701b6fe8b5a9dd195d969267a8fe4ed13010a6ff094c4b15e6bc9fa19cb9b725f925a890c722ea7d182b0c3218a677eebe04e30	\\x008000039c3773c6634851082708810626f1d5883a08b8fa2cfaeaca93c17d53735fac24b36e2cc961f932ff89a9daee7f07c1a27a1b6f92248981f91eb23ce7de481647df96c08ffc9506ee82fee3c0d3015b3391c39657f02d4961b24b430a3032b493e593a8113fb6626b2e408165dbc49dddc821afea6d17d7d0767131018ab25b97010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf910cc22244818840e2eed4d0ace82e82a57ab590c9cb5195aeaf424eefd8faf90338a634b687e794d2992e88aa8ff65a657e54ec1fd9f75beb6d0f70dbd9601	1622653171000000	1623257971000000	1686329971000000	1780937971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcfc12d6cedfcb9bb458fd9484754daa2cb8b145712e67adbadabad2123ce07a3ce1222a1bc754fb9be9924cc154187f2c9ed636803f9c65538a10cc9981d3fdb	\\x00800003d28338f036bf15700f2e5be7533633b8e92708d831ab5ed0c7ec56cb619a0d56290ae6488c70b269e3bfaa8c7bd2b2af6aaaa57b2c31721db9c2c47a3404309514ef3b7681ad45b6585bb3395450d4a8846ec1125e575abca61359bcac4c2df0f23d7ab7e3ce2ac8988d4466cd471fa8aeced402a5e06052a8b58bca6a38827b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0edf8cf8fe1b91375e777b39b87daa427ab73cb14bfbf0cd7f6c7138f4b3e2fa2604c75a14749905847d2d385f97a4a5be31a1a9404e6d8309d2b4d93ca25701	1622048671000000	1622653471000000	1685725471000000	1780333471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8b9e0079b5ddaf0cf581685d3bc17faa84360b4700cec29b246f5adbbedb77676e11cc294313159e0200b6c923400b82ed7adfbb961db758556c5a60a123355	\\x00800003a9463b8cdcca0cfdf540166fdf8a5641003b20da1112531e57d16e6c37b8d195df39b6066c7e37f46cc2fe02b21c7f2024ef930a33fe30eaf65e07e628554897313e2803d56a3068143a3effacfc57d8392251fb0c94511adc16451271db5deee383201468e279f14d585f93389864198462a563ca7fd9717849d889283ee5b9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xffab03df9a845bf84fd09b67d274d8e8053646d3f00a6e19b1b3ec484628d75badc5f595fb65b82153acf84e429a935059a95dc69c9cbd1d370b4cd4ab9e5c00	1639579171000000	1640183971000000	1703255971000000	1797863971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdabd77a9470ae0900950218990633207d0aa536f9f9445300d7ec3fbd24a56d1eb65ec8bb41ee6005669f3d4fbd7d89fac7cebd8cd5c4a178a231e068a024322	\\x00800003a0e8db1f815af54ee90d3b7f3a3c57f94572656a0863113997b04f1f07ea077248e25b122ba3e9a48c834d5c115b18e52e8a17e5239b3f554ab43a3fc4945513b1ad5e7e32bfed4a6a615e233c66d7d25dd2c66908c78504a50a80b6d89070041d805bb3b351c301d2525af58d1fde0e49a66372e3cb571b558c324d01fe1a69010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x718f803aa50eca26afcd0f9040aa3fd7d7cc216c0f9501ace5fe4bee53448f352527be304cca3db56d47690e4f752831eea243a5c5d6bdbf1c768cd14ba9e00d	1625071171000000	1625675971000000	1688747971000000	1783355971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb712932f0e9690b639c7211b586be775351b98738948a181161adaa3cc16bbad146401da5e92b1f257f51564d091e5f61a162038399e6d88cdfa8c468d6baa0	\\x00800003a8a01e6ed694a379644163a571bfda95c794197b1d9b635f972f0abfa8115a9ab24e41ad4922d46e6e7aa907cf0c3a7f059ce4ea55158901370184658111c5cf22618bc1273fc9633873652ed03fe3f5d67c5f0ccd368c0dbf49d49fcd9d536138682add5ebc9bbe0b9df6801d3d32b03047bc3b79a1104215133bcb11932fe5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5689fa0f91daaf3e5617ab9028a2f1757c6e2c24b16061f890934e35448ace33c4ca5e8f47774a3441fd527f19762a0d8b85c822ca48ff79d55126cbdf339a0c	1625675671000000	1626280471000000	1689352471000000	1783960471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdd75315bb1199ab6534b1d09df7c535ae3a271a364822f36f90ecc27d3d51cbf599a5c0feac6ceaa5a8d3a2f51741c363c89fc6fd7304f975f2391fa5a06d157	\\x00800003dfe33a8b774a85c426d0d73c0d12ba8c702b9ee453b8bf579d652f470fb1c479cb25639ad7c1cad15f410fdd561da34c2b697131c2d183cebe3db860ad68c1b8f5b38b089701073467c397ada99caf81752c7ab6953b438eb6069b9c0c6f0b48afa995f693e1af1db9a9de633a637a8c43584646864a132be61d877c02903421010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3f2778edbf804c0a7a6fc80484a8fb27581a196fb82ed92ad4760a637202be3c9f78f857dd1235e4ab353f354676162b09139da11b35a71a35899b4fe1776b0b	1638370171000000	1638974971000000	1702046971000000	1796654971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdfe17d2a4ac4854a0d6677b618aa7afb4a1ddd2012518ed6fb96f24e03c623351138c503eaa4fabba12e1ae963eec4890c08855bfc72d455cc5aea81c579139a	\\x00800003b92531b534df911d06ff95a126e766d48da5d2e20e32f4436dadd9a51ed53e8cf7fd7fbeae198fa76947a6cf9a5b02ee317f34000213be6d4ab61c6b226145558cf76be7cc59198c1b6d1a948c163cbb54acd5362975681175a3eba397186ecfd4ff0de73b070730e98031a4ab5d7947423d78d01a6d549a978d38d5b571f7bb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdbc292c07ed8ae149afb9b7064d22af8fb8a7207a43cb3fe2a850ffa8b0264d0ca556a50b4ceb0777570abc696542f38889cd6ec113f400b0fde4351587c9d01	1617817171000000	1618421971000000	1681493971000000	1776101971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe04d08f7e9377d655609a0b55e641854d9bc88bd68537d5390ebc92937766868b65584e72a40e3a069cfae006508ed24ee1297f51f3777036beadec9df6fe9fb	\\x00800003edc39a662659d2dbbc35f8bbc6a0aca3df2d26d734f901fbb5fd8e319918425bee2589f19db190d34d488200ea382173967d745cbcc98bcf8080840e1413df8346d4984d6fd45656afb196c0e7bfe325f87bfb4c6613af32c5081ae26481d6e852add45e8734f8cfa6e0915bb7c5de02ebdb4ade22c0ea1b735d71f599254bd9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x29155f6025b24a9ea881d735c3c36857dda8be405f50fc608d517e68172575a376dc232b74ef4cae012e517af38e8ad4e19989bdb7aa8173b82b25d1ebb03c0d	1610563171000000	1611167971000000	1674239971000000	1768847971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe22142ee9170a762f8218292f610ec4190eabf21a2fc6abfb71b9942792b44ac67dcefc329d5b7c5b499fb37704ee7503531a47c22f07cf1f6f6d81f042f4646	\\x00800003b1a666fac0567e230b1d15af201ebbe8a4f6ca75ca8a12489fce09c195fcde5c91a5a97e78dee20be6ca07e32bb2eabf883757f259ecc35269fe09397f25ade6b0c62aef92cbf7d75a074e47a57ebc9f69a68df40bcb1a2de39a0f60e9b37f95e7f1cfc1c4886660fa076c3cb72c73970ee9d06c74eb6004301a212a879f1e3f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1323b217963c3f657f2660be4f02ef30bed8db69df59b2d02e991291a4601076c7ef9672c4edacbba6eaec96504cce72d1aef9a0617d4e4d22a330b37492110e	1618421671000000	1619026471000000	1682098471000000	1776706471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe3614cfe6082a5e1e60067314760abd9319a3cc549796560de94d7fb1e87e3b741d3db3bae161ad1f3d3cf66a44d9a50491819f3a887046cd69aa4b2e525b5f2	\\x00800003f3b87c95bbae49c1cfef9c26b5a142c4b08b145c0ee652ca2c5e053e139914ab58cbff8e93e0a3de11a9d68705a18702aa3b9e52a277b4a80b3457b601847b93d544db1ac877cf7ef66a1f81ae21ef7917237491c7a5d73dcf6ea4242e89c726e85d1314aadd2207425826fc6568a53605664dee3b7c748986fac541870e1585010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfe1e1986fca54e6d3ad78252d25d117b65842694e2751ea495b12d2ba65638a252e3c678fa04855c562e8653c5b61160f400e1832698aefb7137a5191ef76305	1629302671000000	1629907471000000	1692979471000000	1787587471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe591bb0325ca76699b04686870305ad989de13e7390716948bbac431da5e8c362b1370767a1e5455ad41513a434ac85b26d512fc0a2bce78380aaa6dd0f3dc0e	\\x00800003d43595196d7e7b6a9a8a7560b1caa0c54cbd7976f888d7e541715371f47fad44e8c5725780db88e595bd3771768f5dedcadf518a8ea7e3b03a4a3e118410083acda4beee905c9afcc5e8b9c8f252e939140d35e3343cd035a0d9bccbeb300e9384f2cd4de014e42b68e568801cbaef25fd0a4511fac39b7bdb5f888a63f8cd33010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf270bf87476f3557abedd0f4b9e8b8fd70a121c5883e3299dc4baf641adc294330161e737e315a7c9ffcf5601ef8bfba2bd6dbb56161162a65ab751d112c7203	1614190171000000	1614794971000000	1677866971000000	1772474971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe63dd0215048624c202121fc11438770076c46193bebf38ca20f2c1b227aa5d1ce15616daa420dae3818320c805597fcd8873d728b927ebffb260d3bd177e295	\\x00800003e891ee1ffb78fbffd027f2d3cf22b2d4ef836f4866bda185ac998dac05ccc0b947d9e304c7d433cdb8b4cb26cbdd9351c93b9515fc179bb33a2929173c4c41a4ec8b237f61ab9169cd252abeff516d79ca34a5a2712faa4d68ef2e627021cd0f9cde28314e99a896b7f2580638f8e3fdd6d7c0d6467d686231086aa343ee3403010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x930f1a5311e77f633508ecbaff47e2c91c7bfb09fa2d246444d64cf9ccf2140c09ef003aa6a2f3e639e7ce6b192b3a0ead92817b8893a5a43db872fa6d553206	1618421671000000	1619026471000000	1682098471000000	1776706471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe69d9ffe37be0a7adafa56913fa771855aeb9c7967c873d9684fbbd12eff943a5a888b1403c0df6b4dd17ebe696a241444ff9b6ae48c0a757c9de7c537d116dc	\\x00800003b82e2a3035853f7b1633e5cf2ee5ca8ebc421e6178e09db7075ee64323839be1cf53b6ae8e03624e34c0cb582dbc91e695d8e715e22779948f5c6cd70632c78cf94d4a9fc4124f0dadc924f494766e8ce57d783c937b1752ad150e9ffa57d7466d2976b64295ae0f66c444dd69eb1264d78b609f5605fc67db9701aee1b2aadb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x60bb7e63d0ef2265ae42fb054b214fe095458323dbc018e450f0477ad5f1ebac6d49498e571b23a1753481a16945cdabbebdd02f1a4bb14fd6ebedb3d97ae409	1635347671000000	1635952471000000	1699024471000000	1793632471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe70df7f2e40b37d97bb4d3421c9cd14ab6ff02073d0c76102bd82200e1ac8147ed724b10f342e44af816945e5fd972a0f6bee911ef34fbbe2da1794021099d1d	\\x00800003c9ca265f1bbfa0ecc0956214faafe84ecd14a90899f3eafec00b0cb590e7c1463acd7764770f8055cf87c77a5f89c940a9844b2a54a6d88608b8b9269f8331af0ba4a40a83f6dd6de0e48dfc8fd903166331ce13c6a8a8567e4e5b7032d62a271ef972a12fc8be1eae72e289d1244a4169560190ee18a397d5386fb22d63c117010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xebfd4fcb152c054577dfd68f54d87c1542cd67990b8cd06d8b2ea571171cdd5e724e0c8ef6c8c8ac4c52f3f7b10da6491a87b738ba5a64d37b57e5e4098ef70e	1625675671000000	1626280471000000	1689352471000000	1783960471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7a93a90bf2b55169d59a10b444421f534493be353ab8fe2d7a6470f86428f478deb394c4efadc8c6f6bcda6f75f36349d1ac0a96ae8851af3983ea4592c0c6b	\\x00800003f7eda87137410643a1ac735224e0a6f1dd9f4aaec6dd820f9785ecf02cd4a7dee94bc30a86953efcd37ffd48940bf3fc0baa7182ed331235e226b6cadb3efbeb1b4f39d2d6cb399849f3f7e4958e5de5fd48046957db1b25a4d613f849ed8cea7466c9d86d6f14e85ea2b214f0912e232549c3bfad80470095f2cf306fc32cd1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x03d9ce2b6552a97cecaaa9ac9d3fd8df9f6300b80aba95a5744b449dee9c77abd047017e994d2b2422adfbfcb2136e6cddc53c185eaa238cfc43a6f492668301	1631116171000000	1631720971000000	1694792971000000	1789400971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe84d3015b68ebbe021591aa7eacf3205f51e18c480d582bed9964e7a51ab8c03042dd64f5c8c9077cbd7af561a3ab608c89856ab8bd7ddefe54d1286a31a41fe	\\x00800003d6476c749836bb016302679767e63fd0f2e8e9664d754dedee67db0f7560bf8c9fbed11cfbec0dab0e86f6e1440a37ac09892aaa63b54de1f8ca87bdb42950016feb8ab7758502cee484a48519deed983a1648b1c68c1ce064ebac520bf8112e8a838d6f538c3d45d1766f7359a39d5f5854f292fcf7afce942d8321f934943d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd94a1131fa1498b8b1b58b4fff74da39d289d9a0df71b081c72d7d73f475ecc4d192197111207d0ed4b72241eda55a70c4fb99312ae5d78ec9114b39b384e708	1616608171000000	1617212971000000	1680284971000000	1774892971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xea9d6a09a3ad908bc97e103977e7436826c8d2942609dd3e0a9dcce638022709a04cab5a40a1c000518a4188d167ab2d56ff0e634047483661b47626d58b359b	\\x00800003b9bd9e48155c7e4325dbc4993ffcd5e4c4f7ec01b2762ba928331b92a416e5bb887abbc0504aa180357c6baca80adcfe2ba073f60fc4f8ee8fd62631fd504bf26cf5af81385842fba66b3a394c4cfcb00a6d541563dc619493ba05e1360d0214c953d67c191f350fbe9cb46bf2324e30e9471b886d4b975d32de9c99032b585f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe40f88258be3de5f55e3e6fcef7ccddd6321ce48689dfaf0a09d9a1bec4977c6026edf7a04cf158000dbee72145d0561f5ccdc381465b12ff3b2a5f06ad48405	1625071171000000	1625675971000000	1688747971000000	1783355971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeae91ef10a1c0da5346af00ab63c73d83a8bf9d6277509dc746d701a08e4eb3c9d9483c27e1b8e717b5c605c427814908fc71579f09057e7033366c3fc33d652	\\x00800003b0082d1656aef0b08609aedc8d4e35834c09239175dd650e83f60dcb7fc0724087b3197355f0a59f4943719e6072fbf9688830113037ab2c0245198bba38bca57e224e481e4281fdf0cd15043d65f77303d82c90b082d97c6e39a86dc1a131cc6553171f93c6ef5efdc6f2a34cb99dca619b3672aa00d1a38c36c213f747997d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6e8d6b73e6fd18a342b863dc0ecbf50e544ba08c12106277cdd15328c5e6e2c3e8e5a27aacf5881edc2a926d7e3a03934a751ad448734c9bf08470a737850107	1629907171000000	1630511971000000	1693583971000000	1788191971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf415f848a4c11bd204f2fdc3677078df0999869a653f40bd962a30a73125a4af8b89b6ec9d9a4c77d58a7fd352e7e29ccde5ac72ba4f1fb4c3e3f1a95b82264e	\\x00800003c6ea2a7ec26e830518e18a5d35cda4176dd613171b857c478d503efb90f3eb5d82deaa5591beb1570037d5e35153ed3e872994e59916cb4c71bd81ddf058763b8e8853ba09be95128cb720fc766676e1ebd69aff059e6c9565a83b1a6e9ff14de523fd65bb398e63694e67ffc32199f28bdd54eb1d7404aeab10bef09025e2a1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xca1c2a3306e0218a8adb7dc5307c24da6ce0e0c39f95f6531799777fe60a656a6e8f0f17dcb49f6d6f3eb0152509a1c781f362d23c47e466b24dd146bf761d08	1635952171000000	1636556971000000	1699628971000000	1794236971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf6f104e41357256b308a90af50a3e3757492487dd241c10bf05f153f92939734c6aed5851ddad0514b045489e5ac217d2149b6524f8e7988540f41bebb4ed277	\\x00800003b612ce39f8010c046a3a447aedd7e9d20151c8b966af31cbe5338d6f8d4e40f24e86f93a7a5e1df0f0fdd73bf2d1c541d25f949f873bcbcf65b68f1d95c09272436f920658e473a3201a83ef1e0047dcd9b66f410cccd91f8e59f5c5fe8df7ad242c7bd6a97867425092d7945e7dec90f78fe95a305874000b1f3b8288439b1f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x94ce4e0d62de83642a941797a45d504c49004ab7f00e42a690f889c78cf5754d94c00ffeab093713a3db43e3b620bbb4cd2c5c35b3e67cd9b9ed483d73c7a601	1631720671000000	1632325471000000	1695397471000000	1790005471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf91d0037c3779131858fb44dd6ae59650a99343bf3e70e8cf8a8572af5640b664bc2ab9161700afebd4da7af90308d92690dbbddfca68506a58907f912a31b63	\\x00800003c5a5413db491e09bf976ef4af691ebc33d5e22f21867d630a49d4f9c74fbfe3a1d4ff2e14e37f9a7d8bc9d1e2e081750551454da16ffe74cbff50c80c6e9bad6470181bfd8a983f8eb13aa8c4f13022a16138de315effc76596ccd82aaef11aac7b93cc3d2a6897b530dc45a401b9a623817025b85bd75a6c95452be53c1f2bb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x19dc8373316a54c79654f72620c3c42ce532bbcc2712515341cba1de4be84f14e6fcebff8f95b806da0070e7703484f66f586ca2b7d275ecd3d917eb9634e00c	1612376671000000	1612981471000000	1676053471000000	1770661471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb59906522895ce25ddf2a70823ac775e067db72d058c213ec33e792e22af72155886886194883f4fdcd03bfa80fd1bdf40831c722096d4edbb21549861d9c57	\\x00800003c5b5fb52ba42eeda0ce2259094658796c07ede602b2e85a1fcede6fdf01e81cd5cfa343da9652f25a9a8ad1eeb4ad22519156285ffa8a97828a7f7767aa96933a7d8c7fef0fc3eda8fb5516361219c3866f4fb5a037a870f181348c0506c8ed0d9bfdbcd2c2710440ea6a844fdbf911869dab7f32dfc2f04d2961eb08468ab4f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x66d08b9373b80e898ca8b3f2884406b9a19c09579c6465be84eb0cef7606cac5534c53e42b8d5235b477f20407578d29589194f430353255f3d359c968e85204	1637161171000000	1637765971000000	1700837971000000	1795445971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x014240033a98e08de44296e0ebecd7ffc326ba82b653f4597a834aa1074a9ea9cba3ec4f45ec76dab0f552dc23ea9d9ee5b88a37b3d2ca858eff320e15aefa0e	\\x00800003aac3ace857a38a67b8dc0f73d92b4395899ec8de27b527e17271ccc527af8e5b6de6fe2b9fad9623df6f21e8dac2d1ae150111764abddeee157d5cf7fa2871aff2a66ff0e985628c9ef5cc776e4be180d72bf3b3ca47281f36ed4e8efb988b8b7b40736dd79f7daa1a53b968e71f35de7ef54513e2e1f832eff13f8f7a6ec20d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xbfba0e2b59bc3d6898cee4989a4f0e01d529434f7cfc108e560773a4b10d8e52c538480e1b1d221513bed27bc167528ce1cf3186daaa55dc1c3ea1d70745680c	1610563171000000	1611167971000000	1674239971000000	1768847971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0d8aa39bf85dee7c8d43117887d23622c3951e34910f6d09298b2c9a62227a82b5429b9c9f7f1229d6839018c53774357d9a13dca7a34645fbb94919e1b462a7	\\x008000039c1def80e5d96f63c2047bb7c93aaf276386f41c78b0856f32205cd1d98b0326798dd1d0542d6a898eeeb57bb92c16004271f6c2675197075e28f667eac7fc9896d93df1b830045b9b973bf2d352678b86a3e19240460c4f54499523e4037bdc6f5a330652ceb8dc95b63b7c4c41f96848714cb2fc6df18deda55f23d284a0bf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2f447581b7acbda73e101cf3791780a3d3aee541f81f181d79e1c4cf86c628c51627963db310bf8f764a697785f758461d1788cfc043582819513c13ee82e307	1629907171000000	1630511971000000	1693583971000000	1788191971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x127e2090c98eeb21908481ecd5f498605b057d16dcc5bd6439eb235769ca272f20f6bddecd5c89896d2541b4d3a8a5494926abff6520f8d2a26dc95d5f17c921	\\x00800003e46fc0b61236b582a16f079805708b6447cc70624ac4e8f1a1dd7254b66fe46354c62a3765f93fa899e26464913829a04e4d880384dd626c72c9eb0f73e165a2e735a7726622841b9033227b25c6c807509a111b0308a809b9410e0a778999e32ca1e3dbda9319f453ebb4a3e72e034a41caa46baf55a1aa4c7cf335782734cd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4a43f56d8b917bc0d62e041d02e57c2641fb5e9588d5f3cbb64531ae338b73f6b90414d4f07fe701e866b728b0463f592b1430f724a300762b34950a899d7502	1619026171000000	1619630971000000	1682702971000000	1777310971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x12a6626fe87142645006cf28f6dd897b1b4c4cf05c181e4c838e81b6bb1daab92e5b434a2b1af3907a84d0609fad6ea059e1d40edd5823ed579b9f9c436933cd	\\x00800003cd0d40750841b27099920deb5f2fba594a83acd3f5b68336acbf6d5d6140974c45b87203eafe0f62c8a760f18c4ea90e3253d092421cf2dfee9984d0c60ec80e4d58bc39162aba319016c613a3bb220a1f58f77e2937a68faa55279440c7126213369045290eb3823bc138f80a3908cbea5e8c9315cbd8e008f32173e6982c93010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc4056772a486851a6d104de54d637b4a3b915e7b42d6b5c6a5e20ed2e061294c9dea25251531ec21e5091b2bdcd10f60459073ae94317bf35d3a6395027f530e	1637765671000000	1638370471000000	1701442471000000	1796050471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x13aea317fa30a2b74f1487f32e8fcecfe36c0e22bc1b9e40f3a902bbc58f77d546567fff9092932fcb41a033de30aa7c9130fbe59cf37c01c202e5e18dd1d43a	\\x008000039ba2f121d7e5c729e7c729547b5e1b8e5a39aeca72c64a9e4eaf7534b9feca99c2337a7533baacf48f9312455ce96592a82c7d0a34983113c6c9754c35db68710524f4e7176d2bf358782891dfcff2b01d7c591e8c1277a610355e0a3c5c4a706a2864928cd94f1ef9731a6e7dc2ae4a559a968bdd8352a6c2840e63da25a3f5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x35371afcbf0af2dc5333d8d22113e91f072c1dbd65b6b93d37bdc9a4f6f1a9446a1a7ad7ec7802afb8491e3b1f26251eab2d9e0166f78e18983e6614ca454206	1619026171000000	1619630971000000	1682702971000000	1777310971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x14a6132f5a0f6fb84a081c0656bc63c44953ff2ad8d1d74cec12e4985a96b86559941581019f4277d20629b09e734db3a264d491ca588f7cd7b91f6d470662c1	\\x00800003b7c1539dc2cfee18a9c595b2193d82ffdfd86dc7bd98f75fbde64ba85e0f0e0151cc7a700741b4c80f95f2c186d464a8edb7a5a7c31136d13a412fe4011aeacfad9f4b121b431adc07c975010ca2b1c951773f5fb29602443d96d918d16d3dd52a28ae3671e97e3654729548d2be307749bb7d943b08c91891bb8238e12a9b53010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x90e9117b72adb8427eec01eff9b639da2604b85fc4dd3da8ea0056c5fecce1d2dfda3ea6076b4d36fa543df86f6274d173c3c46aec9e8ce2b2df564e175b7a0a	1632325171000000	1632929971000000	1696001971000000	1790609971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2172e74941c1a656a3559ee98d8d4da6d3cbf390b870b3da32b6f62998be141e63b8bfeaae120486f1e88937c09aa5e1279e1e9c5e4b2e7f12ec73d2858fd42e	\\x00800003b64dc9ae127218b724696f0ec6b9310e2f11d1dbc2de7146daca0f83197c67a150577a2487e724017bf8c162500b0c140de0302a589aed1e5701adee49799398f7d317e285f1dd4eceeda8b253eb1a98140ec1a1cd651e9d1814258433bf856775005df42c65217e4770d91bf5fe9cf021d7f7dfec2155292ccb6a3d09f6b15f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa07b17d5d788d34f6c73d9669bdd9ed49abe703ae02e4763601242bef0afae2bd54d9aa8913423c5755a8e4544e28beb5cc18fe864194b9e7747e61fc15ee804	1615399171000000	1616003971000000	1679075971000000	1773683971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x22de473425f5e417c237908b79b738fa2a7850a449ff035c2cc47c53ad893f0e64d2a52b8e40a1396514df48fad4fa6b75a88a85f02ca289e6e1d2e32e78b496	\\x00800003c380e78d4dd0a21ea7242ffef4682761431c2559226fb55956a4cdbb52cbead67d0f945759369e287da049a362666cc7cbf28dbae5754db626bac9de5f5881e3b95660b8a02e35527e9da0d4cba3a5808a121f47c62bd42375b0354b97e69d25a86e675dcf38c78aca50105c49e9d985a0abde0d6ea1238f09081302314f08c1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2a60ecf5f370197c4bbb21394b44e0772a4a5c3d046e3a8f5a95dfb59518e3bda8d6bbc4a910a24c08ce87246a28d2f5e7dc0ff4188ed8017925cff235c7b90c	1620235171000000	1620839971000000	1683911971000000	1778519971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x232e182e089b61a0b606944ee3106c94a2396572b80586a941d170d0a51b90d4c51c4a6b5d53f1d58802962ee45b75feb369304f9c5c33c6e8a18472d2ad9363	\\x00800003b839b4515ca6ff8693f1758ccb5e41d8a073e6a5d9081be5cf707605b5e4176580c7926f07dec57a2fb05dc9d252f66c216a40195fa25f21e874d0aea9f9b1aa5e6a518476c298e61805badbb7f062b4f0adfdf1e5a83406ec64b1b4a9a5425fa0f76d1f24e796964b8b2965fe3bc87a927d6b8cbed6e8f56ce7f3f12045ec97010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc3b02552ebdc69eb5d8e0ff2d64268cba57483176085be54c589081211717db9f73df37584e9b39216457700ccd6cec721da0db25990fa4a18e04907e205640a	1622653171000000	1623257971000000	1686329971000000	1780937971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28b696f6363943176ee0cb55498d4ec4a9078733942cb6078fe55dc130b318f6326c2e07e6ee65da499023e382a997a94d553dff29e776fbfd163c69377ba437	\\x00800003b141aaa25bb2fc994c95f60f69f5d8b5bf0fbe235bdd6ef61c23321e7dcc7e7675098d6756c8bf5d40442073efb91fd90d7f82cc9ca8ffc303633a4f0a93fb8d2be015bbbd0bdab003409acb43ef700e145854acef273277fe839ab362c1a70cdf1219bef24f846e904103f91be89cf292875fdede25ffca284b5c56ba25f8ef010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5b89fd6a489bb8eb7e709a122ae05c2ae34647c1bb6afccc0154f9dd384e38710290c1a4568aeb903b6f222fbc62dfccfdd4207694157c1f3964bdcf7bb1060a	1636556671000000	1637161471000000	1700233471000000	1794841471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a2a6205ad6a2b76a2c8c547a51191c7f2bf2da36ad92674a742907b2ec47bc2498ae1777b29e2c9fafd26c2605d23ba068e4afb4d7287c8b91c94d6aa33fccc	\\x00800003f88159fbb18deea089a38099febf52077a3a023e7038213ae398345f967ed2f4f264a349414f2ba9cb4afee4d7611bcd638191720c19d4da4f8047d6377532726be9186cf17f4f580cc317b28109715cd3c7c8575f404e78ae9e6765e70e8d8477ed3357a045682ce97ba4f149b94e91019c163b2e998f425ff45c9aed342c95010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x042181f7d8fdbc2f4b30eebe9f3bda93b71789c2accf0770c9960b70a687efc447defb9491952c85abadfcd4a21f5dbc9a3d4c93e35d164e410eeece4b943107	1614794671000000	1615399471000000	1678471471000000	1773079471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2aee9623e0a36dfbaf7b27abe796b798b24b1fcf7daa761d906fdbdf48be592321a6a43c2f0d6701f208cf35696bae15c0b6d6abe50b5b32e63a03d35f64edc1	\\x00800003c6964e68956d38e28b8969cae2a9d3ddfa48735526e74e019df7b093d886f8314dc8cb975f8122eb1be97872c9680f2579e0c24899bc1b8cefdc32de8376cae47fc7075658634c1ae1dbfd1401e4d1d7b7748807b829c7ebd37b5e03753077df6736c44ee8672378d4677efeab3022e59310a939a2ff20d70c530f342a7e39f3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xab707ad76c3d4c679f45aa8e82a977c401d1cd5e86ab8486d6b4b35f7c06151fa13e8df54878a12edc1be017cf43d7c3dd81c0a7e7b6b61f04d0e914a9fb610c	1617212671000000	1617817471000000	1680889471000000	1775497471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2e7eb4025635725c8db583e1ed2c86fad35bae49d91431f4ede5999b6916da641ebf38ed89374543ac2cba58116259936f5277ce1af490bfdbd828d69d778416	\\x00800003ca20c436fa7d56bac9b07e5ed55c82f750a5d33057cd4185013da2fa54c22cd2600af3c29d6b005ceae209350fb383100be967bbe3fca91ddadff780070ca982824d728c4c4a1b31313fe338fee23c42e885c194e6317155507ffff44b156b205284ab9fdb65c72ba928ff1953ca869f4d9695a12c6d24c1c9e13d700bbdf407010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x03e427d80bec6ad6322749d1977e9f3480348fa9e2e82d01a76419e2a8bc4ce485b9711cc764ec1aba687a1705acbedae4a7f0bd7170bfac446b05bf1cae6708	1608749671000000	1609354471000000	1672426471000000	1767034471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2fea9ccf50708c1a10a262758c492ac4ab7f218389d79580bb2c879c28009cdff48f54316059a16557c348fdff07eb56e38e74ee1af3cc55f4799abc2957a95c	\\x00800003cfad7d5eb42412118fe8f2d77f9244dc4f106032388ff04bdb687bc2b304c53e0802d94f2c25aa474e6aa8abf9f1a1c12af42fb3c6316bd8fa41fed870318e93605bb5b575cddf08a058efccfb8e8e481f645d22f2ca8f2c3a640dbed71c93e339de20529714394a1019b0195050523540ce15554163383b565c0dccec1d4691010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9107015a6435daeebd61dda94a68f659093006c6c383b96ec305f46f2ba8b743a9b07a94b2cd5053d142e1638d5da7e9d7140878b5b75954c965e02481445508	1624466671000000	1625071471000000	1688143471000000	1782751471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x32beeeb9f4a60e2c4ce81bf1aa9c3ff8ca84f3801a8b94032bf81d634141c4fbc8beb4ad68fe9c9ae6030eec0afb638dd3ced2d2da3b3c3ffbf65b07b983d2af	\\x00800003e433f66c93a05417242c0febb1d467cc75891e13ad8265960c5035735eff00951e869a9d7a82447a956ce4ac267c25afda3aa3c0df60e245c4c51fb0e896b6a123962b61706cb5e7823bc0095cec3ca5e94b61749efdb17e78912b57fb6b4aa53a7569daf84e758eb3f975dd48edc600c057bcebbecb9474022eebbcdbba8a61010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5517fc6f7de48652a1dad816f35f0366acd50d25d2d8560155c1464051b7da922bc7f969064e5340c878bdb00ec85f9e07615a9f7a20b94cb4c9b89ce0369607	1611167671000000	1611772471000000	1674844471000000	1769452471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x359a1f845ce9c46c870f04b7774be493a7e90ebc96e3fd0e52e0cf1e2be77a3a201a23829ae5522f372921a6a46e82ba4f1e8de68acddcdc96d45f756181c29a	\\x00800003f3e21a9826e8c588b8b3828403d00a7ec698c361f7fa1eab511762219fdf5ad541ef1eebeb3ebfbe308b7b48cefa65d2a1029260cfe9c609ea2c21b9c8435450a90efaa15e9e368c98d4f3501853b452e24f5456243a4b722edb560f4b9d088a56e118bb81a4c0266376e85b6a778e6f818493c7892526cc9f6232abbd06b379010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x56a4cc554797980c83626719e143fa895ad68581d25c29bbdcaba5beeb92d7005dbd9173624f226252b5d7686f0eca3739b84a98706e88fd7cd1265f80498304	1634138671000000	1634743471000000	1697815471000000	1792423471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3606c699b1eb741f74abbc28e99d7921b9255a554b5cf82af38b317d4ad977f5b56681af89212a6ba1ab4c3560e384416a54605cf06ca23f10b9bcdf31d1666e	\\x00800003e6043332a5effd5ec23c59125084fcc8158817db2f8e871829889c4da8c0b5f9334b6fd332c1638a82a8f52039bc9b907d239809ebb0da482f60aa61a1152b38ed1c9ebe11314bb50bb2c73183626decb720a8b1b0aed89d4cec05bd6ef1ad8f8e94e3e34380ffd2e3789b02618ea1ccce994af94f13a16a0c79a034c531068f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xde90a2e2e3cc6833d050b304c9cbec0adfe5e4ebf035f43e53f1ffcacad073d8848561c5b50c419989d3a37c0cfbbf6d73cb671c2378f3dd1f05d5ca76ead505	1625675671000000	1626280471000000	1689352471000000	1783960471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x395a559ce42bb70f1277dcb4feebd64d8f621008d8c67212869eed476187e8e9a37a2b76082d184b219c41cc51c19b35b9cec34d3651c12ccc9025fbc866403a	\\x00800003aed8ad2ab2339bcb97738756da4760b8c48b41c5d73e8ea30904f77ea03a945622415a628e3fac3289430028a01e54cc22147c26fb3e318449fadce87e3a7a7df8574615306dc9773aac99884010e1bd1966c0456793d5b48e1b7b88511bb8cd2dcf743f76d49614f8837043dae90515068f5b258cfb22815c75b7bcb33f22e5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x34dec00bea8e19e498ab0c239effb4cd70f8e4d08e93d1d85d42f04e71046bb2bba31ab3fce3a2493fd15873afa2ed29399832f9eb6d6458d5d8bf88304b0a04	1634138671000000	1634743471000000	1697815471000000	1792423471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3cca92e38556bae4fa3e8a57a7d6e493bb83aed5212015203c6eeb7dde021eba7c20b9c2588ae6247413aa506b4e6fe2ef8904ac33f71ab8a5e3f792ed4c8960	\\x00800003dd6bb9c2ec9715f70369eb773348639225b9f69ddc97a2e9ec2f37165b6b2b815209cca2c642f9a3af2bdc37426c7e33d332b631f8e5423f6668521018759392474299b19bba75ec66a704290ef3f3bbb0b6e6927a784f1ea8ff0ea6bd15e5b56f22320618cc7ce9709699ad80d69eeba349b28b3ab7add09c8e842411ef805d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7aef34d28decfbf0d243801372fc52f503200507bd33e46d3ef6c1494de1840fd4b7a6bd5e3791035cd28cf5c9a178228f45864f5878ad6d9711141502a00501	1611167671000000	1611772471000000	1674844471000000	1769452471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3faacaf0bf824ac702c84d010d736cb680000ceeb60e9be499fe8470b5b2ed69167dbadda888018fba007cc8eeaf4c27a3f1a4d24707ea691436761b7cd2b4d2	\\x00800003c77292d02ef704463e63806c584288743161f93b327d8d1f6dbf8159c8f51245a3caedb15d311baed529fd738db6924ac2cf6bb79aaecdd269cdeb9224e85b215d66e7439c203b2187521dbec1afedd242e63b17a0b30ad5967203dd18842697b8986ecb6e20e203ac49d6229588e2638f31cea1600117b31818b906fa0a8d3d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x82218031f632edacc9d3585c4a7b7a4de9edb11c34f4775822c3cd50536303729ed46514bbb767e77d779403cc1c28cc29ef2b249a3ef566b267034ce1bd450b	1620839671000000	1621444471000000	1684516471000000	1779124471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x410e24adf20dc2dc238b6ac8204f3e306619f6ae6268a54b5e449c15d445114cf15965cc1f06febc2155bbc7383e90ca6275a4cf75f6980d92a9dbc403dbd10f	\\x00800003b2ac2bbf8d020b846f8e3a97d540d754fc3df6a6ce319ab993796a7ee2bf4aa5c2bff7707dcddfe0cd4fe863bc79a50097d3a9544e36a1cd6b97a71451a04dcde06bdb356d69bbe45c6de35874a1c87bbd7928fdb7ad36068a4af3fee69202dcdacda16cb3da24c1f3145f7efb5a838736db9c8fd3933be9f52d63953ca6ad55010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x05b07b789bdfa6b7352cf865bf18929737d7ed40112337bad2a9836b3ecf2fac986b7a237f136b6c1925787a586bec46cb78f7bff9e8ce29cacf1b107a0b5200	1632929671000000	1633534471000000	1696606471000000	1791214471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x446686cb7881794b6ac06f3c4e8c9ae6f8d769604e37566fa4a2dac46194c6ef07093c74f8b223bd7a8e5647943cec5c375bce6d366f5ef03c8faad27362e686	\\x0080000393d485a69bcef51b6144399c389ec1b1cf30a6dbef073ff6d8cda763713f11011d69593698a179ece495085a30339808751d4b6d0039a91d05602e85a664f7aef131a45c008008f80f268845ee4d042becfa1d25a74759b2f35d002560af048b5e1ecf10d0ac73a3f2571abbcd582a2c1e76c8315e7e5617bb6aba5dac87c193010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x97a2d9268a51d46eb177f84ff2429118578be973e54638d54e1f48cbc0b8bfd48d1e20c39500aa1a372c92d786ae78a44effbc1d6f01e4910801e2bbf96e730f	1633534171000000	1634138971000000	1697210971000000	1791818971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x469287ec6a4015c905f015358d389c2aa42bad4ef53d6dcba4aff1d00c7a159c94cdcf34e53a9cfec6890459e757afb3edd27b570415a506193c252133e67233	\\x00800003b6e5ca14ba70e41a28c7339f25f133b88ca2ace29c2f121d4cbe0de03130b09397af195468c4439e258612f368e33f801283ab2071a0979084f323df23f14617cdc02a59be62b0f84ebe4c7c6172a0b842c97215e4d2a4f60d195f1315778ec2f18200b2b5bfc554c25d8b8d72b44b14fde2d9cca227f8ef16c85909f4a6f74f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb274630ffba031941f5b8f434f10aa710d10d0551c4cc1df246796c43fa73565a39c6575a6dec63949b4f2081b005f3d8c3fc3b4ad60061b7c40fefdb9ef850a	1626280171000000	1626884971000000	1689956971000000	1784564971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x522e29505a2fb9b2620075c98fb29f20da0e298d9a039c5b673a15f4feec7b2f4821c05870a857af595075a1c46517adf5de6e308bdea9c6252b2dad46e3a18f	\\x00800003cf775e91f776ba3fa76eb023a56e1e9dc22e3d1995b3c90c89f5e3cfdc52f1680f4888f20fc69c97fb2cf17dcfcc9e1e0121bd6367d6a91f53618034d81bd785c7f7ca5ded2a0ecc6564d6c0716dfa1cb603617a30c9cc24be476bfd467ce889af725096987de939126d45fb3ef43dfa1edf9f716c517e6190e0db828254d8a7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6d5fafb32f01b05a8c489c6ce75a28aae1b89bb7ca9a9dcc63c96e8bccf33924db16a337e165bd57a42759e4f51c82e661ec42f3aa3e0f35fdf0189a75554e05	1619026171000000	1619630971000000	1682702971000000	1777310971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5546ca544ab992a9c141c492010c473dcf15f72d4d5be0fc55dc15161cee77e04a81762045b9d27640c48412265608c54a73239d0367dcbf9074af4d8666b746	\\x00800003ce5f3252b1ee34f087f266f751ce0ee264c97a80fd1cd5a526506d5a032b1555d3a7676dda75c1f88b9fe2dcfc30ca854efbc38a327b8230a3e0e4f9389ce06d1cf764eee88400ca0b8830d357763c1dfbbc27bff7a812a04536e3c1289b147e7064f1dac984d396c087bba3a2717ebdb2e689c1bcf6f0437354b91552c53911010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xab5acaacfc7839240d5784cfa3d4b876eba76a2bf8e4c8758db384a3473408864c603e34fc37aad044bd00a2233b1a4fa4e888287567ff8e7706d13b6215080c	1613585671000000	1614190471000000	1677262471000000	1771870471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5b7ae02d3352962f910153cd1c295447a5dc8bea5332a0a2b23edfecd7d29167c3bcb869bbb7eab2afc4a5904677e97567e84cc8fd4148114e7d5c56c4046b24	\\x00800003dd80665b0357e490a910c6bce9b1ad63711a5f7bdb07584de7634b7decbdffacaddb555ea83ea8a4a247e327b3cb01ad431796b110ec0a0c6f5e737ba73886b735ae6e65b582f5afa7ddc87f399112a17353c219d12769f731a41929cd5b971a5597123f526a63a12d5d06bc030acfa7fa6f7bd185ab96cbc974d7c611b71a0b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4c53725f590e90c8ce3219742dff859e6b00121228e4fc670428d3ac893bc95d7df3476ccc81e9263e499ece22cd6be15f7fb1c4b7b355c17f9ea15e6258a10e	1627489171000000	1628093971000000	1691165971000000	1785773971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5d0e8b97a0dcf0191df0ad32ea000d59a601aaf64baefda8862c74f590ea88f7e91ef7c7d642895f56d806e3492904740ec4726132de78f069b6397e29d8f526	\\x00800003b024b634165036a72ff985cf7fde25bb77a1ae473a6fec10151560f74ba845c59ed9e1cac13a8ba69785021f365e24a8d8801ccfbf50fe2b27595a3a4cfb9f808c5db36f2a2e49caf5feb37e31785bf2787a092363a894b2d8220de2cb5563bc3efa4581ecce47ab60efbbbe2f867935c1404ec021f13d448a5a32b67fc5df01010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe227a69625b329244dba71ce1eb3c20dcc93bf9bb310073c8a63574fc981f8bf124e662af8bd137dfa1536f0a1ce6c9f4679a2ca3dc1c03880a119cebba4b701	1627489171000000	1628093971000000	1691165971000000	1785773971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ea69c1678057c6900b2e22876c01fcbed6ae210826285be5c23161e9981682bc8bc88edd43539e8f0a00769c112304cb30ecdc66c555bb9bffe415bfd7c2d34	\\x008000039e40b09ce1bcef5382daf9a25d5edfac5152d379d0faaedff8cc61d4076d4b51f7ce097430588f1424be00b448caa9dc1c389984272adbb5a4128c4e0084ea52a36e6726c5dad811085a26f3565d8e2e7840462fbd4f0f073c3f4cf502d5a51fbf6cab3db79610fcba0d292a3d2752bba8d002d4705f6bb747f7bfababaace2b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1595424ac1b2f1cb38a6a7ceb358e4348bd5813461bb39e8af4df443101fbedb6409cb576d95d41d9202e590f828c819eb2422d741778c4e3ec1e49a9d799707	1623862171000000	1624466971000000	1687538971000000	1782146971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6026d5226306987feac0967f8b025e9ff363334460ce1b6321d0cdf56ca981415f451e8494e6b3eae3390e21640ee95d44f67cdaa378d06db23b7949e96b4f85	\\x00800003b2d53d644859b9b47af20cc2054e576a32c68a8d8a7f685d2618268e63922e854d36cedf3aed4272ddcdb5d639645311c22ab5e24afd43daeed38e53ada197224694a15b1b450f2c97372e99136b46f03ac93a8256b365b4b322dd657be55775bd57eda902ac2cf5f2ee5834d6852e465796816be3520588585a6077af3a8e2b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7368dc14ad8129c52d5ba22a7fdb151b210b5df3179dd807fd9ecfd5671ea99b59df1d3029cb20c7e78d9b97b2a0f3da18385641c3f1332d7df23d72cb065a0b	1617212671000000	1617817471000000	1680889471000000	1775497471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x64767e393a34c42a9bd30c82a8b30e896d95cc87068e451cfb409f90bcdb13d69efeb2960feae55a15d23a86d89b5782bd9d233e6a44b51f73ecf7cd620982af	\\x00800003c01ef8b2a007dc4c628d39663a6628babe9b33aa1bcdf0e762738547908f0a4eeda5cb06a6833e24be2caf62be180deef849d2e4facd55e3f36e68605737f31f7dda5885632af2c7934c5a1611fb96b5242b6349da1f77aad3f4a7115cbfe32e718d2b13648124584a78a738812e66b8974016eb12e673283eeb2261986c282d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x593bc83a1586238c9670e0a91e2c90bb19857b550517443fe9ac11041508819f830382d83ef585434a6cd87a17a332ab3b39f7266978466a975cbf24d0f60a04	1608749671000000	1609354471000000	1672426471000000	1767034471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x678ac55718e078dc3be90f82d2cc8c93bf4ea11087115e2bd84060819f1df474ced1c995d482ca82315735a0f464f568904655d8885d2b3d0d5195799579c1ad	\\x00800003b0e3e545c341d0715586b61c67f4f3868ccc499dab01ebd5dbd139de29ef0e4aed06a78fe80e9087900eb6d66417f7a0ed67cf9057a30bdfe81575b49b6d64cec142227447a28dcb95082ba0020b30f42fd31fe191a151971ae97542046d49d259329f81d81c5e4388369dc8c9f8be60db4047d8ac29aa7a79261a346077274d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf0219547e6b1613eaa425a6f8b5090adee44782cbfbbd55e16b6600172de1dff9b9ec9a454aad58f858385784e28831dd32a7bb23297febe37084421dea19106	1626884671000000	1627489471000000	1690561471000000	1785169471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6836a3b3c7ced3e82371b424d3475ced2e87eac915c40d114f396d0ec8084749e1f91d2eeb636fd4caca8979262eb3ecd0c925b5556b14d01b6f2d14dc0a0355	\\x00800003ad9dfd8294d1ea9caca12530f84c23e2ea43c7966d354dc935466f9b4fc0472f648bb0e593e9bd1b7e784856f179f1cf4243e9afef5ace437c2f337673bc91b202803b23dd318bb12c5c47025047eec077bbaa8898d66382bb57c6fa62d335f643cb76fc4d53b38ece4dec19cc59a804dfbfd01906c12c15a3946f1344f1c43f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x80978f27e6a47d8b850bbd7313455b4c63ba96967bad34d9f47be160cd0e2e27a8805e9922818f143cd2fa0325746afeabe7b689c90620d975068951895a4301	1617817171000000	1618421971000000	1681493971000000	1776101971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e826899df4c1833db3807e506fff59c6f1aeb4603403ff12c7ad775eb9f590d69049d9b1b59eb8d886f8dd6678d1db882a197068ab61baac9bbfa33d869d697	\\x00800003adeb1d38e318c653fff86e8815213e2ffe9acb4fb035b3c3925241744f8f609bf6ce658657156b0f9aaf542c92f36dbc39642ffd4ac56f1f05c43c2731161245d5b5417fb92b29ccbb35f85bf35032efbbb5f7230e841818b8af1cb5d08c6a7b62365c95a1798e020f9a1af7629faba5a4a4baa2b5cd68e9a0c6cfe6ca13bd19010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfa9a49f2257a1ee3b50146c66f0142c13901beacb9961d689682ef6161b2dea7df31fa401a26b1de52ae941e346633027789c699b52985398c297d0fefa2c601	1629302671000000	1629907471000000	1692979471000000	1787587471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x745a0619c4be8876b68e8ac17006c601116e0e8af562ae5d237b6bbadcd92b792a3c62a0aa3c60f56347e6a4f1d6804376188fb84281f230fcac22da54131c0b	\\x00800003df88619fb9a9585f0821f2d6b3c5895423d0e5ec6004a31608f2dd162c65bfb70da0cf0de8f029e8903e8c61d65503f6b26e00d043aec3d6d5fc01c0b72c2debd2e2e7e036d574f7ddfbba90c929ceadb9f920e557eae8d9a1c492c609f9cf05d1e85f592fb74e460632ffde549f9f6f6bc515be930b546c7b500b9abdd0fdd7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x964e74c2a049ee9c85b4b8ac0290bc0c6d45defc26518a0846bce6ed21d3d5b26fb4ed4d05a29dd5230d0dcba171cf0a4df692b98ee1b2956aa202c302dab40a	1634138671000000	1634743471000000	1697815471000000	1792423471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x742a99da326fd3ad78d2c6adb90dba540bfea7247d0a256452f669de25158a4e8aac787914e6e1f64e7d58bfc6b8ae045ace3d95404873e854dd0967354c9946	\\x00800003b93c3f291d397334abc1bf399c4f2c3219f66f41f18cabd485e4d65014d75b5270ffdde6f841e9948f75da644615b00e705a4bb5db4abf2907bc8d6f464000addaef4c539043b6c46346e43caeaccc34e0fecdf89c6a160f8a0947abaeea6bb37eb6a9ece11ff2bcde797d23d836f45d52de08a5a28653fae9c664b3340dcadf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe2287825ee1ead605c951be4f887a772517d8f6bfcd0fb77e9a489449a8674f76ec494d10a9125b5e80fe61446aaea56bb400a117f2f8147ad09561aa94e3702	1622048671000000	1622653471000000	1685725471000000	1780333471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x76e246faaf69fd9d02ce0d5ce44ead5d5c01555043ef04dc012043247fe0c6f8987fde8cb9b8ab6e8ec1cf45751a2b696f457af53a2b65f9528f16bae7aafba5	\\x00800003d3b5f515aa49e0fb443dd2c43155ad37dfa97f4de37f39850d749e44ebf81b182d67a15a6a825ae68551d8cb324015017a7e98562fb29c339352e3131d7502512151aa0ef508116181b69aa90e7d979a57e274e7d161ba72ee9ac70c945ceac906c14df21da2ea6614cde0017049e8f99d1c4514c085ab8fd0feb73496145945010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa66f6a48959d80b5612799910944020da643ad7aebe8820fb55f1753efb3e81fa28cce6c3148fb56113e68754a5f51e84a9a09941df78662570b376f1a051c08	1637161171000000	1637765971000000	1700837971000000	1795445971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x76d209ebad08e2e9998ff7c81a3a7fbce90571fe92b1cc497216ab2adbded7ef257d518194884747edd61bf267f1999cd520207c6799664ef7a343bd39b54b6d	\\x008000039d7051ceffa3cd2b796aec3bb79482995d349b72b4d1186a316802af30d704aa906f0201e1c085e59b1c979332c2f7ea9d95ef087ac8d33413b53bc98e60364ef925aede7e6deed26d9f50545f3a729f1ba2bbc472fa4932db544551b0d0ff33f73f48bee92e5b9749c07e7a5164023c9e5eaf9054cdad1b9ed26d352abc0eef010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8346e14d39bfb82a4807e9597b560b585313a7ffecf1047d91a7bfe1e6debbf1f97169ebf8dee4f2c793bfa69fe59f74c6c6634c28a0a8d9955f3bb2cb31d308	1619026171000000	1619630971000000	1682702971000000	1777310971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b1ea08d2bbb081f96ccbcdc901c775b0273ee551055499f8cd3018f6947e5c39c25c9e4652f5fbe32b429d85832cf2d53bb6d24cce3156e66be0bf20f26a7f1	\\x00800003e0e43a5e58aa713b80cc9f843206a269865959402bff3ef4aa58e78f56b1d0f02922731794ad4f1717a30c8315b487671e60063863fd1aa5b338c6b11a341c44b7edd770b00ea0feec3cbf932c72796e507c7d79f30789c5063e093aecffdac4fce44374f3143d6eb85c2a2d978ed97dae99f964d72947289f608df3b7374e01010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xbace94bde327948c9408e1bf3a68e6f50144406ab1259e9cb19eeda34b5d1fba77b04a55895c470d7d520234bf0e881cc0c0b74d31142b7e967adf8dc25f8007	1622653171000000	1623257971000000	1686329971000000	1780937971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b5ab1c5f541e41fb85520f1776d888892f2cc6507c435df8297c928ba1df1150bc6e50cead8d46c0da1ddd9e85a4034e8074f00edf183dacea4af187c7e2d2c	\\x00800003b391c67247274fd178315e59156e2fc4d8054a3b5478c16ec346b56802029ef0bcd8e78b7604332d050ec1b1d5adf18bb24fd30ef81185c7d82efaadca8958eda9acb791e0d4b9b813581cd0f62c901cec135868bd7f2e638b718c6e457f94fb70e22864b0a259b034747634f50064cd10df9777648c8aa44cc6a082e5f99cf7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x12e6c182583a6500cf9a8bbc6b9e81c438754f4929ab0be9e7fbe9e565b9d4be99ac69407aa5e66b9212cd856c5d09ffe38141bf836505a386b45bc4d7344a01	1620235171000000	1620839971000000	1683911971000000	1778519971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e2a335024c5f31f9bbb327d323fb19ca80aeebc15a9c5d6369d1797f48f803d7061f74af2ccc8056a209067b92a9e2e375bb32d41eb20d69dce0d83d7c630b2	\\x00800003d295ae3389fd9650b0d47b4867b9b2cbdf914bc4518b06c88147dbf77d45e01fe63ba883add3420dec3937532580029e3ea144ad6e3589356bd63c2a32f5b14a801fb1404ff8c411163293beb5690aa88ce80e6c762a5d883b180c6d3d0d6a60861a8d9b254bbff5651c36cc63868b0569e3eca03f4cf9e716b58296ca2f6d39010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xca0f24f71a1df50ed32788f8d67fbc304e9fe1f7ca0ea5086b56ec2951360da1fd5e7aaaf7de62eb2597bdba280238bc0b69e6f6b887fea7d43f699016cfb205	1612376671000000	1612981471000000	1676053471000000	1770661471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x816e83f62ea1798121d1ea90dac2756cfa095208f733ef978fc03caf61bd21fe678b5b7b68c5a82227b372a71f6b84fabfc61be69b5677d2f33d6c66a2d4fc7f	\\x00800003b639bbd6f52aeb35fcbe719974bf68fce21f9b2fb756f60273c7069c0eb824a4fa699fca1286954cb70186bf3e4ec72f8c70187e31859f9669bba304847bff53e657c5a1e73f38f1bee56906b6fd339772ad08aba62ee17c395aa71b4567c59d7274732d56e56fedf9a433f710c03186dd03aa5c9250b7e77b143f805a0116b7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1425cd44e5f889faf52593092b8862bd24bfa51a2786feaa955c3cd182af43dca36d7c700e9e00813ca8dbe1a5219cb58a7afec58c6779f621f6a6b068eaed0e	1619630671000000	1620235471000000	1683307471000000	1777915471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x819e8e9e143cce81deefaa5a216653a0ccfd543c5991e71723be118f451a1d1d87dbd2fd5b14efdb3e8fa63a8491ab2023cf2c7bc04691bbf4477d69d65a7b8e	\\x00800003abcff3f92f69f5da1264466c55401b4f1ac1396240f361f9b0874cd3de9ec7e0250c63d8ade573242c2b7cc761fbb5936929df8f3d2f72a2d1cc8919abcd56dfc0a4f8dd78816f8dc5bcf99ddc7f7f9dc2516b3d00c20c1cfc7e48f936ab74b41226eb3c2dca42671f6431057e0a6fc57add38d148f777766827909c3d952285010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x27df5e85c8e292d0a5ea699c22719e1888083a2cfecebac35fbe93e1586cb84b40499f4eac24da0b473721a23561b67b4bf7fa888a7e49f928d92fdf4d5e1d0c	1609958671000000	1610563471000000	1673635471000000	1768243471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x84be8b1fd6bc329c8ba9f5146e5656fbcec338e459d25894d6a1e696066a5a6b0679e2ac910538edc46781709ee96be7295eed6ddd89b886390e3aa3e6c84d3e	\\x00800003a1a054b809bebb461a72e4a7a57754f460574a8974f083233a82d4dca32681a96e81c965737f5d38d45a96b22e8434deca87770ba3d23815a12a85e8db4e2d9a9ca9cce583c46472eefb8cb7319ac7c8c6b3c1ef8e78b5322ec9a5ced8651d93533600b53bd0837c7b7dd94b71e0e689a2f6a91193a62c91cfff12afecfc28ed010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1f7120f45882ed06041c5d4ec3da74349a965b2c030c5d18042e7d81a8dab93872a7505f400cbb63b4c8385e2544692920e6d1d8c2e84f276f8b0918f4a01007	1639579171000000	1640183971000000	1703255971000000	1797863971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85d209d64fb14dc091ca0a4592b9935b2d5126ae6e07515614764fea801f9ec8882067cbe5a984117d9a7f91b74fe896915bdeb9351f98eff5d2bcb1d67bcf55	\\x00800003f79e84c1c12cb78ed98460f01b4886936ddc00a9757ba137cc239c384d9d9e5a72f759b174d7b512f9da1bf4cae1abc72a865f3e9458268f87a6694b5511cc2cbfcfe5f50644bfe1f0a6db248ba72d8141bef325c8e004b4429cb2e5a9a40a772152b5e57787154b73705671f4d25fc9a0ee329dc4e00ef1fc711ec717f5cf77010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2ae0db02783b336bba153804d3ff08bf04af5e7344ee63fde51fb581c6729e99dbaa977565976846ee9395d9058ad235371ed02ed1358ecbf5bd73a7620fb004	1636556671000000	1637161471000000	1700233471000000	1794841471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c52d6e0d49ce140a59a397b8f3ba9eebfd18417eea1e94967f3943491e77bbc061f6f9f55c6f67e1f366db8ea202b3102b05dbcdccbb092b1e0e4fe64f75a02	\\x00800003d51d9d9a574c7ed3c819048d2b31c8140a3d121829fad04d6f05d6cf9ec1c6c22e756882156f2f18ceac55e51e2b57aef4220f6023967b43a59ca2bd97f6babb1eba08b8c76651c95921cdc88f99abab064a5677c68d6248ff19729ba83c9971f5ae3aefca1dd9784e04bc125e956fa2d62cdbeb3239719b36e4e1107164f353010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdca2094ae7aa78044da73bf06cba50b65f13d0db7b79feb021abe2cd5dd0a58f694b373123717adbf6cba61789c37b08bf8f93b296bb43c8f849883f2641b504	1617212671000000	1617817471000000	1680889471000000	1775497471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e12fbb0f7d4e99e99862a2b3e205a63d6a6a0bc5302d6ecf8b65128dfa4934addc832566718ec85b91a939e17468055396e8ac3386bff13d60bfccf3c703902	\\x00800003c7f4ea18d9c44db32f88ef8d328769e504330966a3412ecaa503b8d55b952e70bbbefe9b16811a15042eeb0828b627611a4c6129b649b74aecc739442cae9eaf687ae3aa7565ad5ff67a3eaef116297b5f33d6611fb9cbfef216979f0b4da44fe6b3879469b8a250a1e30bec71fe0d3c8804b61c9f3198aa7304d590c2b049a7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x28e7e981fd0de6e1bf92a041ab6ff2fe1fce474c9a7e3e19761e3997f2adee20ab3830408375ca7f10abf25d79a00bbc591086f50b3395822b9f922b2b651c03	1626884671000000	1627489471000000	1690561471000000	1785169471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e72af128a39bbfbf663f84226f36456faac6da704821a580638f4efcb1ec0a4bc676180dcb4573c343ca5c19342fd6ff512ffea4297b6cbb46dd7b827cf8329	\\x00800003bbfba3296a07e9bfe0c442f3e21c6eb428bc0e9fe2424696b5f4cecb7b7064f656b8a2e308c906f127680b9d24606cdb75cb30feff77fd9f74e0fe0d8fded9e7d56c6dd5a2d65ef90c84084b0b6eb2addf865770f685d910420711d37606ef6ac3ac2ab4ad2039a18b84c26763c879db9450e5d17c4c7363c91fc17be8f2922d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc9e7b200e4af20e0309f88433bbf4b831291ebf4d47c85224c820863292192c61f986fadce0c5d0d5d007ea4a2439fb4e9254b79370567f07445dcede639df06	1621444171000000	1622048971000000	1685120971000000	1779728971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e7e6a25501ee7ec9c2881c9ab80525e980042d6266b0df295cbb8bec669e447123524de7d89561270b74052ddc4096af6ae9f42f982f4c88166e1362e8770eb	\\x00800003a0d650beca2c0277923ba46be532b30ddf1e36053dd526a9433e9fdb6fb8953fd7a8ac49c70e706befd8af921789a392fbdb13c736b278077a37e75ba3c859b7b3a8a0833cff2496e9301d9f2d795e9f23705983333bed0563c6447906f662b2981aad16b05fe553f2dfcc77553d8ca5ebbaaae0a2e6bb50ff1cd24166d20eff010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdeb5f53bc41755f5afacc8e1f7ec5736b60fbe20e29a501b8cb860554b191d7e54d8a32256dea9d249428c2f9b591ae24391d5b84cd35d960e3ca73a56ddca01	1637161171000000	1637765971000000	1700837971000000	1795445971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x99fad5f56b7a05b29d71562af421da3157f4c0165d745ba61ac97308df93a417d345dc1cc7b387eae7e15661e1743ce6beb0956ba0bc62ae04780947b20b7657	\\x00800003aca59a76a5fe082a736e087225fb40ec42aba7ca68050bb8459b21237fde94c8010e60890ca3ee948392789b185bd237be8d572d65f83f4a88598a77fa8aab0a5b06b2a5dc23b34c439faef4606cdcb6371c8bdd379f1dcc298d843626bc0e46b743ef30969ade087cd6b7cf9c525b5d8a8f884da17bda852ab7a9ec2ccb0ce9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0be24a355ace351a72a2a10262653793196d2e8f4d0fc98082406aad1fcf10b1cac689170aba15701eec35133a4f64d6ad828f3ae0e8acf20be62f0cb36c5006	1624466671000000	1625071471000000	1688143471000000	1782751471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x996ee4a81b8741a0c49dd65073b9de84b0c340187c71d3c57571b30e3f2d14b8d3c9e87123367e53ea02481b226fca42c6099ea5778c56397a7b260599864f8d	\\x00800003b870a752c44c0059d797d29fe77398ad5793be5bb32a0997845df16f9de1d42ad0efc5b33c9b4ef583fcfc7114c22d08af1bfc7a71f83291fba09938329465b556ef6937cd5cc9898353a6944945ddf7364504bd9bfd0205d1833edebd0d01fa28243a5411d077b26a4ce528aa77cef4e19f293e2503d6db6046d7b07b846e27010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0a818031eb81d5e5534e4516f2d5d25569c6117add97e1da1e379b5ac1bdbeffe85322c218687617a2305f37e65d6961d66f9abab5b4b8348120e03addbde90f	1628698171000000	1629302971000000	1692374971000000	1786982971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9b8e4f3cd76bd3ec3593a48e1352c7cb1abd631d1583a862a56e4ffb09a911a51c7fe9740a6d3189183bc5cf18ebdafe6d4d1f562e87874bc1e71582d0c0bec0	\\x00800003e4d80d5e58ae8c776e2490e3acd91cee978cf5f6653080770bb391d4434ad1972783e9b78734e29dfc988fbc0506d997065fb8a05f8cb5bb4274ee6c7a69c0acd58a8de471a92b919c69aee0b9f6bfa991ff47238fad392b95b780368ecd125e44e4b61add83ec9c7e2f79b2f1dbade34cb2ff9a38316c19eb4ec8087d5d19b3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf86526c121a29ab95b071b91fb75a2c790286351a87864d995c190ebcbb3e8c36c212582364d03e7d34be2ebc66ddd8c9403a00eb2d4ead0f8fb7d119c01aa06	1611772171000000	1612376971000000	1675448971000000	1770056971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b62259e04843c810e54ed69a2ca6c318ee3a6983ffdb28051a39285bbbc6d8024df94cc3fc8226b4c0499b137ad4f8941e912509b1e27664cdd0514678209fa	\\x00800003caa41347fc074cbed27a3218d401a0d3f9e4dea5603730796b974856277b543bf2f715caedfb5ac7769feee4702768a5e225445ac7eac783bd2c121c916a6b5facc7cfa9f195de32b8481683387b3e270b407317a472e85eb9839b0fef9f37dbc80a95063a93fce36883ed752a2d4b3134d844bb800b4f989d82afc71734ca7f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5ed5140ac7bb7a918e18ef645e90ef0c88a7ed76247e8e5e3a5e7d746ad7e2693dc3c88d7e7f61956992b5f836c85de5bd52cc4d616e0f3091af39c3af8ead07	1609354171000000	1609958971000000	1673030971000000	1767638971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9da6cb467f7480c0ac7f9566741b255edb2467b29ff939528570a7502fff37edb1686b1a27274680259f1c37bea0dc0a9c6fc5fb58d400543704aec0a7bb0de4	\\x00800003b6c271559d66ddfd8f1a6089843d47dd31301c63fc95e2b64133316ed019f689e9c486560b0297e093d6df960882b9a52528c30879ec4745070ba7845165a27c87f45225979d9bfed85d2d8c578f1727141544eeed48fd37e6eb76d69d7344ab770c392c06422834cf87eec2f08915b6437273cd3e6dfb2eaa6e652d00454d29010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe84e37a237725c9c51be9d44e405378a500ba68907989413cabffa37acaec6b61bf0df04f25e3db62861fe8ac91ed3d6a1543455b84ad28e642398eed046410c	1612981171000000	1613585971000000	1676657971000000	1771265971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x00800003c9c402df062e21041cf1afe1eb08ee983334d2225b55f3aa0454a3db4df5119a3c681234dcb47b3e630c6e8e11cae09fbe512a0fe2e460e73cfff0fc4164db25da7766842abe7b00bc5a9263be8be303b299fb2ca3bece9363025b48a5e651080c4b0de662b57b624369192f49a85532d14a5219d2a25f2675be01a53ef4362f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3f33762de53c9bf8077647607466ec450d3847b90b512f830d0759b6387019a414711f0ea864c9a0f1c79272d79e657f5a4118d1727247efb454eb103ccd970f	1608145171000000	1608749971000000	1671821971000000	1766429971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa0fa2875df3f84b8579a8bae65a3ce6cc5d8cc18cd97603dc802cd39e8c09bfcf2114ca35b2ed1dd3c10fbbbbfe9ef2fc8ee766e41661810154f107165526cb3	\\x00800003a7be7d6b8f7c523ed9e2a7330be0844d6264e08e90ecac341034d708af94d636eabd094b8d3e92a3edf341fb5b69be4c72493a1fc552b5e7b66d6554812782dafb82f27e7370f4a6d35ac6dbe7f791f3a1e974a6f302668cada549bfab2a2fd15b7ede943d38ac8e358edc799705e92c6d00c966e0643c114792a712a759efe5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe1fd58016d47610b10c24eb8736c4d58a18076ebbcbd90edcb76ecbc175935adae2b2b572e8ec5fe348f42a6a4f5f61bd13a5010c70aa45e4736d70e22b2230d	1637765671000000	1638370471000000	1701442471000000	1796050471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa18ace3221c512b4ba8ee36ee0a2bb1153b9f50bff61465db9e1310a4861ee8a261514622397362abe8b0e530f716bf23b0933e1a6bed2145928028e28ec7580	\\x00800003ac2ef0250af34d8607fd6830b0a32ba5e4fc1443f91c7ee06aa2df704936785d7e6b5e574c61019c848f37b0d561b0131fc1976f4c0fd1ad9c07e6e1d46a200b35900c8458a158799ccbcf9de29131e79f3b3277cda15a05d50057deb1f26f9e7624ab3b46bf78ee97161e51f38507bfcd4f553d9514150781615c30ee8ef4b5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x92429713d6564003b80a541a3bc1aa5c89f993b43f27b051309f1dade785a6098afa251927fde2b76405eba0b98224b239d1fd2b56393c32323050bcbbfaf309	1638974671000000	1639579471000000	1702651471000000	1797259471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad5a1b2df84704c6d0ee8734bdff228722db03c9a1d14885ae982b243ad9180b365cef2e3b753b71e9a30e7a436675f494437bdd95a8d6df93bd3278a81db445	\\x00800003c0c5051fb567f1011eb6ed53b0b869cca193a341d8ba77047c4ceb6e65b9cc76778eb2eac6b6374a8c3d7e45527e6da0ca9b0215907349bc15ff921f4282b11aa4bfaa4836004a41f280290ced214e558179e9f1c6546760ed182e3fa24d55e31a7e9ab091adc40142e680132eb4428c4c0fef2dc3ad27f1ca064920d76b2af9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x666284417810e00d941b120fe9dc6f6bde9053bc712735b0a03a3f4529641b68abb5c3efbc49b4bbea4a327a631a1d689eb5a436c147f9a721a09dc14eb90104	1623257671000000	1623862471000000	1686934471000000	1781542471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xade62e5841a7cdb60e684c3031172d36fa8a802f71e2e01408650aeb6742c8bdc43395a022d2b1d026054d1c03850f5455b4013c48845af64ac159c8f5d7708c	\\x00800003c3efe92612f7de0fccce4389cd5bd6d0d623a726f134a835edd7bfe9e58bfa7706109755ff42fa6eb33f5e93dc032a2e1f55cc6a6b27c1d0c4a9df28fb598d4f77d386ee27def52e4f185385c289b6b9d0cf9b2c6c773cb7fc1ad2af20b69042cdfe25b0ef01bbc9241c53ff1337bede4b93d36a2ee68fd696f961bb2bb06f9b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1dd5cd06f26851446cf1dc833a7143fb6c82ff36064725b29bd0768d904e419be4f70300ee38401a89a1aca0d7859e38776eb86996cb11a15c5b256e23960401	1612376671000000	1612981471000000	1676053471000000	1770661471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaed2ac5cee07a2e54cacc4fcbb371042a583df233b398c96e4e885a5ce65a49663603e081523d23a20a7b8857eb2570d36ee2ee5b79f852ab041d12175e0aca6	\\x00800003f4b523f068106b170773c99e9377d1b2e091e8422dc4afd4def1f6595bce5e84671f03f8129e0842fe1ec3109751a5b8a5ef051dd4e75118015b94059a49b990a5fa5d309e9362cd19987902cbda7d5355cee9b98115db2fd61071bce64696fd8890fc0cfbf661e77419e0ec393ff2c9414a2e511f576f0c434ab6c7a3a1731b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc4358fe96b808f486094dffebc08dd317aa7c8dd7757022327c59e16c62409004ba60303b53b1c6f8a703967736e05c266204711b3f83dcf8248449e3dac7f09	1630511671000000	1631116471000000	1694188471000000	1788796471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaf52478228ffe4a29e9b93439af2c5249a53c5181f66fbfc8b8487e9e48448a9017929002036acb894d67a141c3697a7021fb552957320703f6e8b241c50b1a4	\\x00800003d75e88e2d4f3919553dfe84c6e78d71d4d637f0d3cf79f0853fd1072f0798c4fd573b24dcc32009552a82d78c108a3e8f78d89254cdf3d3c12d8774ddd16d949a55e2f02045b0092d27b275b82a78afbc0ddf0c3621763ac7faba2b505210e90da7313f3fb98d9e2dd90d88d395ac8615a0109ee160a188616813392f8828817010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4bf8774772d2ed7bb2639a36164f07745fe7cc5060eee18b142ab3503621ab2423fd97f41985b727236de4bc3788d5a4d3907c02b0880c3087ff6180cfd98508	1632929671000000	1633534471000000	1696606471000000	1791214471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb066b22ee7825a1325d4ed0e3aad64323d741f62ebb40bfd62736f0d05d20f42afae2d5295374c5dfae4188f68da02d87de258e2a661dbb0864ebb94098479f2	\\x00800003dad68f2dc2426a41a7b03ac6dfc3c3715dec01f468480383782231332690759872b5d29e716434730c55364cf6905cda8476a57cbcb6991ce0002d3cb0be44123866668e749d21de771e58626a4a01958daa5095846cd15fc0e8a355510eda881ea11b4e4a7affd58f4e9e2a92f4c7dc8c7840379d767d02eddedcb31fbd9901010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x113efba3ba2bec566c990493f27216f6fb6abd588ad4f47f73dd61b5acaa5de4a2697aa9b0bbe2a2be273077d629038cef1f004d2fa8c3a898d62a0263b5190f	1618421671000000	1619026471000000	1682098471000000	1776706471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb816113ad5f407360aa6837762b7724c70e630d25efcec3bbcd582cb9655f8d5bcc51a3e182daa3bc3b21844c8c914849f0994075d1d31d38930d39b775de471	\\x00800003b5c0885fa5dac016208b9e2be5e99a22b30c712db3af3aed6465f7da0ce8adaff17f9adf6edf920ae71467c7390cfff6f1015c31eebdcfdff00a201952d867c9d1ecc032637b063d6d693e8000f22a4b05c2d9fdc62c62cb2c2c5bb88938d58448f9cc49752d3400b45b108b9d156ac75625898f2fa75ecf753731fb31e7382b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x389c49025f6719317e2f6cc33ecd1d9df699432122f0da8c93023e2bf7ffde3b12d27faaa44b4998e644abb4f488440e49118f1de29685a714a9229bff82cb00	1614794671000000	1615399471000000	1678471471000000	1773079471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb9327201ebb9d33598ce038d2f70fe8495e6bb833d8e47461608ec2bf8e33d335199ae965dff4b08c5ad9047c3f45d1b4699ff494347bc6f70cf404588c545af	\\x00800003d93fb5328d06213e7cacb97b305a1471e0340970024cf7dfb9548192fade46330d57dd6a9a05abec869e410f9a601ad15f94e9da75e8de9adc0d8d8a8dd702a2ee2656b7de5ba6e42cdd64e62abfbf3ac89c18fbaa6298588b117273d893165d5ea1fbfb5c239188c56b2f5a1124a12c8d45f46650725ae890536f5abc311311010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x36cca7606589e47f625c9d060b198186f42242eb98d2852a55df3f92d589a822c7b850e10b195cec36cb8408f03f445aa9bd03e0576e095eb19ecc8eeeeee30b	1631720671000000	1632325471000000	1695397471000000	1790005471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xba22080ccbc4df084e536f430dfe8640be9f0214a4cb00146dd1fc50b550aba1aa174473be3d8f68e684f04c40b34577cfa00d11d2dfb6fd41a17fc66cdde445	\\x00800003e13b3a2b33ba20c7f3fcfb6bb6a5e3492be6ebe2e198c0feba8140def3426359a726d4cadfe06d406e4fb81d9962fc920fb4278c37f8f9143ad2479dc59a292280fd2dc89ccb34a0137b7d5b841fcab2fa23c5ca13eac9abce6377d8ee140edc4fc914bee68269a6d79e8d9e06ee0586c7ee918eca081534795063ff6846204d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8b19dbbed9c3e6e17361e104fd0cfd50e6d262bc9d46a81a2cc70b91723ba89496a1f1ef5baa295127125104ab9c9d2fa1e4a4aff094c53d0658c086ecb1190f	1608145171000000	1608749971000000	1671821971000000	1766429971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbaaaae78dedc0444f3c411f9f1ffee5ac76ecdc7fac31ecda7b6a6d707b84ca38da240e16e1440d86e630fc848e6910d33feb1ce947446f37b6f00de5c187d5e	\\x00800003dc6157b5503eb23e78b6304c6e5010b8110423eac0b941ea71abc70c90f253ce0438e45f51b676c1a9a46ce107d01c01b1016c4b62c9c63289421dd4f941ffc8872d5c354e1524dfb8a4a25561c87038de21069c840984bf8f4a188ceb33945681b845f2d3ea63344e0c3deee2fd60c7fa4821d83451161bf56b917d0af5c019010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x59ab8881209e15e75e3fc67c994e8c1e64ca95d9a40108a09ddfd9f5e3c020002fa7a43d5e3c7e359d9bae5fd80f3588e27601d6f3c67d3722b62401bb217902	1620235171000000	1620839971000000	1683911971000000	1778519971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbdbe04da3db51bb388a2a2119b3e8d57456dc47b5f7d537e0902b16ee4fd143cf565c70ad0db6e695875f9bc9a4e39021318bf20a6afb3b5ef5762b8404aa465	\\x00800003d41b0d8255ab4d05ed63a894b8b810cdca185bdb07fec279da1c6e2e1b7e40c0e6ffd18ca09f177747e491920bd6cebf3701280b9817a27a35e2b91d0bb618684932b9a740a9c603dde2e29468ded2e8be1953f451068f5fe2d23a31a4362878c2997fed9b9758dd7c12d3b70b23d5e07e79b5d5fa9b7c4b4392fba836a2b1ab010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5233f9d0fc7e27a3a5df60f3f1335f5ab7b98869213bc5b91f15d76f8be4e36f727684f1324d95c1617b4508f76ebe9af8f0646b35ea89c532b845116031a108	1612376671000000	1612981471000000	1676053471000000	1770661471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc002d749ad9103860e796ba05b4f2342295b8b16e88ce6e41ac17d8ba8161c21bf4851464ea1063be4d522c78afeaeca0a979708dbd3a8e028e2c9d696400004	\\x00800003a5e341110414bf9650409306b0cf2b0215385b7292ff392a8833bb8af37443ae7163b4199ca52baaabcfaad236a80ba3582ab62dd58c64387528debee49bd1dd0216b182cea56eebaef4e524dc289af5743c830d9820b13db2f20d6354995af4bd8a593708a151f67f774c38d0fe8b5947cb28840f6dec3ee304cb05082d849f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1046ddb70ec0b756c69704e3f61d53ebcd0650b1662df8f3058b221e18b968cb91f4a311cb31f95d48896e7611807b60574e056b762ca7d4015c35f22cfeed0c	1634743171000000	1635347971000000	1698419971000000	1793027971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc3a2c2f33a0719e993a98cd6c69fc79f6d7817fd80df2c9dec9472d1bc3cadd7f81e07c9d16a1fb92edce790c44aca983e7b7e4f7479ad798d795f9940ef1b93	\\x00800003cf8985c35ea4eb75a5923b98a304ce34f3d940b437c92536071f86973608bb60476639ea3b692954546a191d0ffac1e908e6cde51332f1bde834753614751d7c96263061fc97e44a9524ed336452dcc0f6c8cedb71ef228df10d451bd1c8279a98ef9994b2f77245c15f070411076c0852f29b8fab69b7f8a6c01b03a48a22b7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x40c8c7beee0b840055bd78247705433804be19aa0fdc3f7c0eded0567ec1276807ae760ff3dd07b62443092dd7e1601566e9d5ebaf32729256ab1f3fb8e6760d	1616003671000000	1616608471000000	1679680471000000	1774288471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc31677de20d18e38e0816605b11a648aa155df791d08d8468f819d7ad705fb6d5a8f1754ea333529f6423a36b3bd1719ec29bd5e955ac7902e55c2e8f7f4c6a9	\\x00800003c73692762bef5b8cbec3e2f6d0a2569d4fa618b4a55dfe9ddeeb7d97a57529f6ecc5ad47119c65c7f7ee4fc9343e4e03ed67725c14b5a68722a501866609df2283143c0ff2ca095198551647dd8fcc32097b12fa7d767b0e3a31084e4340634ac6b744f0d5e480bbec957547b03443e61f3c7a1d727c9fda9672ea7a1628c421010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x089fb04884d87ef2c0f95c659e2c1266673bf7de2e7c2a952fe665570261a4993f6c6e2179223ac538ea4e4d5b4745751db5fa33716ba0570a2d732e30340104	1626280171000000	1626884971000000	1689956971000000	1784564971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc6125cf5d77f7558034990e0fa96ccb2cd29a8cd8233bf4ef9e8b6ee1e462cf51e6ac3d7986a2b6f08d1e3b3e8335190337a3e3b14d5fc69430569b5678abee7	\\x00800003cf8d6bf56218e3fbece03fc14c8d672ca7f5cccf6d6f4bb83b61f2208d4efccb3702bc99dabb2216ed6e8d2735c2b555b5b8230a95e3bb9f18fcfa995de594682e6f193970903194b9b77e1aeee5ac25dd888fe409046de1c5901eb6970880def6a2bb6d6968875174a7682aadf5d88db46b87d406c01b536534c5ace42eb25d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7128fe4b7e09cea48693511b9a89deedfcbff0cbae8f9c2392e6d9956984f9916c01d42eed4d634a3e07e2220c24a1f5c1efba18477d111f9ba93e47781a7d06	1631720671000000	1632325471000000	1695397471000000	1790005471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7f652bdb8a0f02cd269460c02abe5fd59b2dcd013d6ace4cc6b1a091d9f41afb0f548318c19ed771ee5fa7ac37880abb251b483d4c1a15d82e3562aeaf8a0e6	\\x00800003a120fe9039302d7fcde2a72885cdc9f2f862d9d00097dccb7133b5d7a8d2451d25091ad6655ba5dfea23af9345132bd1482fb1c8426e5d2f0c21212f138a4709190bd3120fc5bc54963c776255c1adda9bb09ebb142326277355737483766f1634e6fba42aab77c9af0932a65b663add71a31bfcd5dbad01bfe7de0cccedd3f3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa56a7dc1cdd775389447f83df79dea27863bfbe7599628d9ce33a77645a70e03823e7b3499db0073990e096cf5c67197ee0c49b020161018da132740cd90200e	1610563171000000	1611167971000000	1674239971000000	1768847971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcaaaa66a13863d51a0553de3d6f802e5a6dc5c94efdad192e43b93513a1480a9222ad7fb02464ffdabe10683f8d4d5e7e6978a95cad678f6696b44afb2b22ee2	\\x00800003c7d6751783bdb8a56c4a370ace20434e7ce34062cecf5915ea152de0beabd1759bb59ee20555f4ee2550a26237e6c83f0b1d4311cdc185637459ead09c73de05fa6eec922055b4c8d50e092609a0b2a746411041210407bfce71b24436420ceb5db64682fa0503b52ac38aaca19256017f99dbc012f8f5054046d55cf00ab059010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe749d78ea151894fa336728159a178acfa44bce79f5e0e4ea698501fd0786a86c2acb49bb7b7b98d12d51959a8159938c26fedbf09876c3c223561896c198501	1638974671000000	1639579471000000	1702651471000000	1797259471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcf2a5d7c7a7f5ac5ffaa11986b584554218527e77725c4377aa535abdb37cae4d27762a3f127c880ae8902f63200cdf2ca22a1365061a0d8b503d4800fcd91e4	\\x00800003e33c824cdc953b3c44d12a2880dcf174ab56108adfc6e110ed834c092018b7c210879b35fd44bc0270a36ea25e7e73374d758bbfa71483c73682d3c54b98c9e17eb9d99ed20d9cc5f383742b3adf9bb3d89e4fc583255ff6d553989c9be47f5f427c22220f3504a7eafede663b4e00e977b778b0109cb58fb5db0be6b330bd07010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x48658cc66fec28c71e744bb3a846b012879264dd59b23cba7d4fc8776e9091329df0751139b0108cd57a71c887b1bf43b8f388f6e9fc4247d2f33cdba368a801	1622653171000000	1623257971000000	1686329971000000	1780937971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2ae15360915ac31804893bed9b07e0afa2920bef25fe68286e301940352873ee0682e8d08d1f033ef6c1ce69cd5cd81cd9611c52e6a7569a95a00db5ffc43ff	\\x00800003d0978c0c10bf632e79f602341b26c678c52083e88efd23595376a3f31646d5dec267bc1544586f2a40d7f8c9b00f4f32cbe4dc48c2f048e63171c296026955c78a44df30f91dc32b2e2a7b4d15e5f475e1b070ba0c713a66dff0f5ad9b2aa7726ec4e4bc2fac16996a3a5e1bdeecb1b7ed72f864273e11e6f582c042cac714dd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x03847a44ae44620a6cfa0163582a26377c617f3a6e6ecfe3d1a4b9e47dae9b561d8b5844d6b5ed49041071f2ec550f3b19104bd7d298c7b35185eadaf6a7cd03	1632325171000000	1632929971000000	1696001971000000	1790609971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd78298693a84a71a3a8d8ba8139fa69a70c662793e1ced8ac9704283f6369314f713819101259606a2eb8e8aff33c661a608b5e6deab16fa27cae0c674019933	\\x00800003a06ece4dcd14c9b38771c29778fe4dec1cc19e158e8fa6ac3e4799d2c03ad8a55e241336c4649a6bac3335a7921dcb197c06ba41b062186f7a2d9c64eb6fac2b3b53f7046f5bf974454a4a9b025bd06df7cf0882aed17b6b1073239085f2db69f551a8ff840c46e19a0326e17541a374ba90b3b784a0900684b5aa44dc89865d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd39c5c99177c9a6890bd1261a6ab2d6cc306d9fb8df653ad496e8249d18283883660e000202cdd45373cea8a0d7d5f0b18b9a8122c57c6e0483ca73acc976f08	1616608171000000	1617212971000000	1680284971000000	1774892971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd77aec178c53d8927d5c035f00bafec01ef01b54844ca4130441ad38dc2e9760ec3f7e747245a36f1bb75f5897b357e1510f6e1813f9d7bf437b8fea99ccff96	\\x00800003cfd96eff0d7045b0770d11dbfae96b0dedd40bb799d7691ca00ca7a06034fa4321fe910b2c4eac20228c894714843e1f8e91f2808994b9bea514cf558eee2d744e4afc56534cd2ec2ea43bdaaa0a18626001c96f8158473b3b6e3c3fdfb18de7d8fe8ea5c5cc80e662100985eb26ef86d794499dcfdf197eee1906cd9244c225010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf21735664fa110823fa1c70f23b51e76310c76b18f6a0c816accbc129d57a0c05f961d2bad07538a6f8e101f34cc37c18b7dce44eb7872403d9356adbbf74f0e	1631720671000000	1632325471000000	1695397471000000	1790005471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8aa630aac704717a25c2aafc7235a12873c80f3d66e0778b1a5eac15e84c30cea4ca84a35422bf10bbd635435a3761b317440d0beccf28b694bcd82a5ac8144	\\x00800003a5e52783c775a89852562a72a36523510e3785e32ec4267ec3518320f99d3791ff30de3c924cef7c84110241fafe370ca47a5c70b113818de7e6fd1cb0f8aafe5e471dba5a253a360ed9e67df0fe96161dbb6dfd9c555211e72bdf9404392366881f394be9adaf253c3a693d7f46fb9d3a29b53745f77d2c288dfa524061b449010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x68b854e976e60767ab9f2ce8309866b7d0a999fd928c94c832ac1ae765f8500e47e905bc0d67c78afbd317b67a3e1dbcb04a5607a967c0b1eff6ba77a631980e	1637765671000000	1638370471000000	1701442471000000	1796050471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdb6697f294a1daab69fcfc4ea8678fbc4eec3c6e411658da8c223d42b6adb3c7e2672375d5a868a3861d6be41e02794fee4eeb643503f808fa02497e04d1f546	\\x00800003bbc55ea5f1c2eae93165aef63155f75eeb7de044f1d7a7c06b2ba100374ea58b8b52a0ae88fcb29ad6e4da47119177c1c81d2fe12df51d779ab9ba42a08eb72989ff0a2295f683e8e83dd8c25f2ff9e561ae5fe9bff56aba8f7eb21ee4eee6ecceb76bc2da913720721229c977c063dfea89db82810117b41961a869c2cb648f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfc59651c70ee2a2d7df0fdcc66f27d3dcf9c0b89741cfd58eec1200332f03241ff4ec4150a46d13fda7d5ba9c8ec4828b16b46c65a48013bea778c0b553f9d0a	1618421671000000	1619026471000000	1682098471000000	1776706471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdcfaf94a45e5937207b81e90e9d782e79b81d0f3417e161d0be8f45d4fa1dfdc3cf8680ca89a5073c08f69b0616d26b971895f21d50dfac922c609accc86941e	\\x00800003a8db0d0a26e537b4c918c91194d41c758836827dc4cf1f5834f21d23f1aa13faa25328f08c3fa63330809ebc661a36e73c48458a50c5158dfcbd6f5ae2f3f64d2c12e80cc0640575918389d81971c88904da9746d4ce1a1f5ae1984f0d82f3729f243ee83321b5c32c64a352f5c7592bf739f88ca266f85e4cbdd21001d63887010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x32cb15e6fd48f0bb8801e8bf630b0379c8ee965e40aff7f7213f5cfd281090f50741456363086650f84edc72632d40d6ba85a0738850b18cff67d4298e61a602	1618421671000000	1619026471000000	1682098471000000	1776706471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddb640683168ed4431789546cdc043b8c048893355038b4fa35ca26d0fd2565a3799824603a015204c6770f084ed39358ed9f5a7a6e644945541480557d1d01c	\\x00800003f4990f82d95451116f7b7efebb777246b41c0ed7b88873dcf573ef6fa1d5ca38488e69ee3824d7a6a1d25bda2a666b89c1a0af44670259d5ad3bd8e46d7d99a0863ea87f437e2d95895ead22d08c475d9f166b90b3fecb870b80d5fd29ad12aa0388cac2cce157373cb5b1358f1d64a3cfa25dff6e196c11df939602d8226353010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4b2af23817d8937f7eccc50e99b5ef7a7f5ff908937a2d83743c0bec2c646e40796b6b0f019d0013dd24ccc8ad6643eeb0b357ccb890294e34863f4785d6e006	1631116171000000	1631720971000000	1694792971000000	1789400971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdebac83d83b66ec80afa15458640560546865751fcade4a13f4f16dfe074ff14ddcdd1d362568bd8b1399e334274113cb131e57bd90bca048651e864fa695662	\\x00800003c0f113ef4fc0d4b8491cebd65beef98733f611a10a4360a16d0a23b2d3fb21374dd7f8b4ac2412ad1e56f49415b46fadf87ade165d78f689506587f50038da47797dba7d50e9617d83a416d435394050c40b49fc8a4d6ff8f346cec5f5d618df449f53a38ae31401595eb31bc81dcc391e593119d50694ab45d873d66b3db9f9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x426aa902c48d3598bf7ae5728b4140a474fd8fb4ca8cb5e09bf6548fed5161396abc2e1a35d2daec547dd6b1fb702f06d99fd14a4155bbf9bf433592f1564f01	1623257671000000	1623862471000000	1686934471000000	1781542471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0d28dc139aaccc2fa221303847a1033f9f1cfeac6ff9773d5adf5868d0faa6c677dc308caa3d78a709f7ae8b06e20a6d2cf8e723950fc9ee59575e27898f1c9	\\x00800003bd72a8e8b5f9513ad8ec5bfc1a75f96dc827f44026a673ddbaa082e9d2f5d251b39e49326102b0c11b6263ddbcd94fe2c524faf279eaf87e1f90255db3599099c8064ea6469c2fea77d77ee4952ff03bc2e4d5b673d34ca96bfa411f6adfb613dea27e9e0ed55838573b56a2822240c9da9c0e8b2bd3d3c751e4b399f05db52d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8bcd1010bbede2f257d7ccd378bd0594c003238f31ca75dc39a56dea5bf13cbe55ba17c07167d2ab2e289b83da790e58d94449aaffa397f2b9f07a3c1cdc8f01	1616003671000000	1616608471000000	1679680471000000	1774288471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe11632a085e69ddbc2b1e0f94efb330a960471866c52c8e5d614d8e8a80de0d84482282580a4239517a840ac732ef421ecc89aa92e3e6af3e4946b2c4dcbf49e	\\x00800003ecdd042594c853ea837bda51d3df9ccd807acbfe36cddcfd3ba5e97ad9195c19dd3e98fd0a4c420540228b039ddd06ffa04d4a7f454ce64c35cee35253d8a9c86fd185be68661a3051beee6ab956a657ae54a51fb246c63b04a421611f392f56ac1b41ca41065048a371b4d23dd37c877bb24091ea8f85c6d8d5539c445452a1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3283414d1c1722412ff509e7144a52ace8ded626b14d6953d2c11a19a7868d10c532d30e714d4315fb5946eb3d4e973c8915f7fdb4d170c6054d8e6aa637bb00	1628698171000000	1629302971000000	1692374971000000	1786982971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe39adfb5b96c88c42dfa97dc53ffa3c97d6756d081033509a86b77e8aedb95c3be80a1c108cfdd93ea9711243713073b468b0a52f1d86a1de0d50f441268f1ca	\\x00800003d9ce5fdd5c13332c481571c70c20f4f99a4784a7f3ffa91e1cb7d7ea600c2ba2914f106ea3826c28d35f7ac5608f69d87a6a5e4b2ac0fbae9b63cf3230918dbdf364f63b74b1f3d0e62f1ee248b1be4d321ea907646f5a38a8efc183254d1a86f2d7eeca22fa53281b45f965e76b15c43ec88f8d1803ed4ad32b3c001cfd4bef010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5cc4b6b6b23e6e5c024ee8951ceaebbbde03dc0e85ae654e62e8de5b853a0bf0125f35a088f7c9de73b37770dae2d37a70a0b5088dddabb22bb985f962ad3704	1632929671000000	1633534471000000	1696606471000000	1791214471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe52a4efeaa4b96a7d98cd36cc91d4e4ec51a94f9677190c8b26479cfb91c1a0046e1ec0416bbc8ed3da2287b3e7d38979bf33848b3e2999cb450b6ed00a7d0a0	\\x00800003e1cf038d581829db441e171f92390c6855e3f8586170970368be1886258dec722192d6fd588fccffc5af8bd22d2bb0c561f16f04b9e3201fb3cc1ce443756b8569d8e54b73b9c384da4156a86468f4059a31ef7ef87811fd3b41d1a84842dcfbb1c63bc2b8b8eb49249b65778abdd0181ed430652dd06a5f365c8250f7d14587010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc85e57412047c97ae583f8e6c4dde3f2d63e2320196bf6a7ef7b5a16525dd8358851070b8dd5ec68d41680d68817371ec784e16fe02171a03c08afaf26c2de0b	1619630671000000	1620235471000000	1683307471000000	1777915471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe51ebae06e62caa4562f628da79fe2fde031c35ae50233e60d2f709e4786d233703be8d0c74ba798f1dc6808e632ce98faa824f69e375298807094bf17d7a969	\\x00800003b47feef430167af2eea1eaa1d40b576f5ad4a80939c7fc336e24a1afe68041abcff19b258e0aa0461481be4fefb14597961373adc96ea0eb95c17b9162345da09ec419ac146f82872e0aed2d83b3550dc00dd8ce5310938fa175b24157df27e6ba7e2a1ae95e3eeb025d7939579d73d3efcf1a8a7087cadf16bd25001e1a9fef010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x810ac5a77b90785241c16df15e9478fb45382a401c4823f376ba0b601c122e3c22286286d910bb0797f342266cc128c9e87aa59aff146df03ac8321563249107	1614190171000000	1614794971000000	1677866971000000	1772474971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe50aef8a598d86155bb0cab29037a79b6f49616855647200a718b4429028c74d9ef3c14695ea0a5a3bd5086d3c85beee6130a376c56e285f84144f62beb1874c	\\x00800003eac44fa18d8ff696fe0161eccf8231af8f8c5b15e9ab4814ac49ee917578a69899456706f78710e0f1b3b753385e82e596a759409a5d6c1d7210b41d45fb45263668da2672ab3773f3fb875d04c9192899780d95f641c7d0389f783d0d14c2f131dbb136ed02c220f0ab41747a621ea86c9c1904629893b61e801e64a2c1cf2f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1f7f1fef4ad65b1b25f52470e254eb0e30cb353f7388b6cbce99748d973e57899a9bd4f6092f98453d9fdc4956ec61b16e0e37b0b4bce7c7a9c56d20676e9c0d	1614794671000000	1615399471000000	1678471471000000	1773079471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf3d68be4054d4986b47f04eef0b25a487e52e2fe2f8ad9715448c57b41a1e13f5703d316639221e68896ad961c9adae7bcdc006ec5f1b53965292d10a3a824ce	\\x00800003c9da2cef62a5c058d8e7917cd00b1cab5644fc5328e428ea3e00f7fafdb150ba8b9c79169adc9f9fb5bfaaef397efa7602cfebcd6e542011413d9c89094fa93ae64bd2761e7f95d9cb3a9d35e41df9e4899d034de34ebd4db78dc6b1724361f0c87aa995d74a63a6e4c09440312cd74e838c0b4b18b5700f138b9f86cbd8a02f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8fb6e465097ce02bd52fcbda84caa95c4e87a9c490912d899927e80f1af7e19873fa232915137032522f013f44dc77f57ccd7ca6bed74d1e4ad8eed91c59530f	1634138671000000	1634743471000000	1697815471000000	1792423471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf60aea428e61e93bc93602c5f8795ba029826468a1b9d53f2f4b5458ea6223106b76b693d35e3ec6f25785474f9ee6165dadbde911cf00d9b4333161330cfb42	\\x00800003bdab1df48da8664bdea699cc0b72661da6274c0e01a47d35d080c1d4dd5d585af9f7913d56188b7d325a40c2181b586e7a9a7e0b59c4369199b8f161576fb3492e1f8ee859de836767c3f458f715d13e227100ac2381386bc977369fa832920dc885d62092c69cd397cc8536dedd018aaf4e5142ca4b0d2b9e0cb15b2b1eb3cd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xcc8aefc98301eb3f5cfb1abf84b008083f7ebeb3470093a51a0298160f4d5bd830fe5991018073a82856cc851a8ceba360b6cb505d66bee28ab8c7e69efbaf07	1627489171000000	1628093971000000	1691165971000000	1785773971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf662abfb353192d897b891f19ce4d73bf95ab563e8aaa020a5178f2b2cac6a094a74038ef17e0cf4ad0ec55d79e9a6f5a779de9c897f8e9f8b1a059b33b338b3	\\x00800003c39231e2392b0fb0cdf471c572f46c50e89534d88cf7aa4c1015e1501f6a8a4853f8e739fe22264e823359949f5b5ae957b8bb0123a6f04e186ec4ebf4d74dcb0f8a37cd229616efe927987849f52e965fdb5ccef63b984c2f44f4dc9dc68c54942a02bb91f3d33a9b0477eb122feb9abbc8bf972d0bd24fea1db465301a9f2d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x49c24d87ebaf8969b0619fdc9e60b228131fa4237c764c82f6a0da48f2f03354566924518bb8950dfef32dfd244746594fdfa876b657cf853d36717ef923b801	1634138671000000	1634743471000000	1697815471000000	1792423471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf72af2fb6fb5afa380f26cddd336679bab3ddafff5f31a9cdfc2b9cb9a6732ccfc97f1d8103dd81f5f1e19bf26ce26b02f0169e0a0a5b937e8ddca8469537db3	\\x00800003dd8d0e2232eac906cc0bf0cd21c2a0328091e8bf0e15c89a0d08015e556487b97e5acbca97a11cb98a7fb6a9e8af6abb764b387b152bdd0bf4546dbbfb78f3bf17944b3620f51e3f2df6f9625707601d955713b4cfdd3df4830f3714992f07d3aa58e6611c57babbefd8c4f349bb8f55d7acc176d900af830e581610f5111873010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3f58065cc787a22a21f956ca0d2bacf3b1408d05cf58ca600b56ce090e47da1b20190e136f900cff7a47eebb606d30c145054cf3c29a63fdd4254f31c7a5df0c	1616003671000000	1616608471000000	1679680471000000	1774288471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf98e3cdb558c85de0d5eacd64b4808db8bf6514cd4e71609404d18290eed8f7e8c7dcbe8b2795dc07f49a556ce891a5116be14f31a5bde262c043d6172275165	\\x00800003fe2c90454559947d6bd593b4f4e26f897d6b0d310ca7a5da0cc8720808d09dfbfa7057f5a03cf11a836d5fcfd6a22417f46b5005f8b515985bf94474687a2b4c7d9858cfa77f05a573820c6a18a7298eb0de3de74622daf054df6f1b81852a790871ee0f02e1c43159e25318887496c051674fe713653162cb6537f07f242f47010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc5ca4412715d53ee433e9a80530f429aa11ffb9163bdf93d2356e02f1587c77d9c0df757c87493f5a0e060785cc44efa15bb0dc18aad450bc0fe1b6c77f25d02	1608145171000000	1608749971000000	1671821971000000	1766429971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfba67cb38722ee5c3b6125dda4d11e6028c826a924f6cce1b1badb7ad4381ee120308495d5a0e3c881ffbadf0316e315921fd9f1cfacf570c61d35e801a44722	\\x00800003b0fbaec00f50e971fc914b0a049d75a7a06519836f326caa0e9150cd496b32d1bd7977fdf997bed3fdd41a230581223c4cc02d60e045e9a09e0271529b6abd54a65cedc99eda092a5530690f065c68f32e86570da716f1d62db56bb50f4f4c48a05fb8cd376090d77d7139e5585d1a8a7eb0b9a176903e3fcb9f732259e83a8b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfbb4296bfbe33fe5de40a5b7266d984a6a8c65222f412406506a3957dbbce462ee8019e771507686800e629b341309bd296087c5b1b84fa620464854a67b3e0b	1628093671000000	1628698471000000	1691770471000000	1786378471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc0a91c23d4202c837a2a210530bd63bc74c0cf344899a7a9beeb4bbad8cc0f077ed91ffa8ee992ce14eb5cec695e30ba8c0f68dbb02d26ee78911900db204f3	\\x00800003dff141536bf37c9def09dfc2ba984e69cd72609a0c487c26a8c6f1a1f31074edb7cc9ad5e124b8b9aca02e0414c555b2bfe7efba705b2fb685a1b743b077c9deec449f12695d0654b2f9242a516b6efe40220e57cfec074fc855ce7e53356c6618f3272b6f830fca5b37bf00228154bd8f15019eefedc92bf923fef6d0fdbdbf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7046f5f08459000c6bba376952b24a32244f8b9b16193da49ebb4a26c8cb4e415844093ba209021a4faf82d9e8e38199cae8c015458a1e5371808fca9d01eb0b	1628698171000000	1629302971000000	1692374971000000	1786982971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfcce116ce604bd3776b89ca144f19928ef6cada90c41084e1150d1b237cac02dd29128c6630207df6203fbdc4203f435fd83e75988f34a406f99e5f38301fea2	\\x00800003cabc4c7f78aaeba416dcb08f3ae2906962ee5c01b36e9761a7b1598a014ffe7f1d1d03847085df32d621dfe4a64913ef0aedc1b6bc6c3372ed5d279b7076377a78ad6aae7f484e4a527fa19075c19cd9a7c048c2c52f5410924cfa6c2bdf79acd0fdf98f070eb094b11c2e86a4677944fb1a14df9f61aec7da6697899bef78a3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0ae10e8fcbd43d65300261b51865eb5799e5617be95b08ccd1a40fee77a226a5c1e04f246c567de9a9733f33965ce0742c787fbef22f2a88d53c035c6cba560a	1638974671000000	1639579471000000	1702651471000000	1797259471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfed6d69f6bca39eefb2366745c5cb856803c015d077e1e4af18a5c4095a6d2885668ae343f91fff4dc061131574bc5912d7c0aff7c81d60052e57a9eb9626fba	\\x00800003a7dc81db77879708909bc36a803ea665eaa3e39b13d9912f1b076c3f1126b5034ec8ec91a835bf1b5c336d95c365da39384588a0899b4ff240c1f2282f338de8c8ebbdcf7e5867d11bda4262ec04f8b234e53a9544c5feaad97784d58649e72ede83c7a09afe8012d6fa9bf0c59a7145520d578883cea8e174cc1fc8c7aeefd1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xff5165ce4c2a064e9ce3217a26307aefba5823289507e7a9d217fc53758fc5e9584947ebe9b090781f5f0fb2c5220c43fa9d6571d11f6090ca5fd96d4f9f6901	1612981171000000	1613585971000000	1676657971000000	1771265971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xff461be89a5f827c8a3583dfc198a2eb13b499925176e89fc5a2829904963995ff02665c38481379b79a28f68bd93b57a3849057a305bec902db087a783b8dc9	\\x00800003b8aacfc444d349140dd43a290707d7e940dbc73a88fa50ae7cc04a77b8f05dbdc89297904fc7fba512d96cfd894fd5a359eeaa7ad57ab60fc7ba4c9ad3c9268f96db5359eeb6aba820ca7ae5ae2a943b46fbde210280a2bebc6e3754546ae1c78875fa110ee4c01423e3bed00ad2a8d43960da9c75b8062b3619d8b2476dafa9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc65ab7deb0b26d6a0bb23856553ce940cd55ab308339e16016cabb519ee5d249aabadc3a2b8e2786540e4a7a99350ef2e81905b0a9e59a2f3be1a8ef03b5ff0d	1628093671000000	1628698471000000	1691770471000000	1786378471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01db6aaad7c61a5c35c99b1ef6519375917ea4f811ff2539a78287a2651e5e310bf807e811105c54c1c4b788c5df6aa156ed17e7030e9323cc7e3303ca4d83bb	\\x0080000391ec21e36f5c1013c49f823735ffdc14a84252a9df76512e83babff3fc2d72f2e3dc1edc25253b13bf40a6e7668aff0ad1a59a0bc56af531c55d8ed5c064d5f08dfcd3c11969dd339cc75713181c5305542a54c5a496dfc7727ae23c43788e780cdbd28c2453795773bb64e4a2bb7c3b5b55b1270be31eb91caf4443cb92b023010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe7b8e0d99e1d0bdfaeaad812627375ef0e3abdbbe68a3f23d8593ed636b30cf91eb14e2c9518e24c6c6d92e6e4e520d50d4af9d0232ad240077f3f58b003b30a	1611167671000000	1611772471000000	1674844471000000	1769452471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x074b7ebe697a5e4cd8f9f261daddfe07a47f28a291592376d8de2f59f44139879a01932c0a13a491759b5cfd481d3cd37534193e3448dc8122a9fecad042aa0a	\\x0080000398c88a1029c581b146c066a618dffb3b15a060e085424e4d70bde35fb16ee8a95af71b8bfbac051af4a3d7d2aef9f5e518f62e34509ab0858199c0c121361ae6285203e5b443f96f474d89fbacef1c9849c94e6b041351093fbf86f2b49a3d386695843e745a18dfe200d1248f034b0696e9550b4fffd68b2f963478fc9bb1e1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6b45cc6bfb430151477a3e932881d93e788844cb8a23780e6dddaca291778e705512a918de8c7518c3e4067d0400491a133ce5a042fca90e6e9282e37e45cc02	1622653171000000	1623257971000000	1686329971000000	1780937971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0717edb242b7ed2749b3a415803204b189c01a0b046079ac30a6a03a0870b6a35086fdb3643919a10b53bbc8a64c8d2b45a2f28a12a24963d08db864180b1647	\\x00800003d77c5c8e6ac5a7ac910f19acfde59913bcf41d17430078383ded9471454838af6509959aaf1213202fd553f4f60cf01a28501e18b5f96ea8d0c165e37566fc5aa024b97eaf6d9a6e98c0daa3a1c9aef29d82b8a8c0e60a87a00c6943e554581aa8f5a8461a30a694d9bc944215afcd00ef4ffbd3c663047b6ce97fb723f247e1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x349e180d40425ec120d06c0b59340316b11678afbd671b4e0f140326836179d34a4e7d9430e216734e29f1185fa39cf674a99bb08a4390ee9324b178bc03b909	1625675671000000	1626280471000000	1689352471000000	1783960471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x088f2e9dee14430e7a5fd88384dc48ecb3aa8e2f22cd698157b58098af19a3bd22b9172ccca7ebe499cbe8f7b728c17ebacb0e739dbfaa9269e1f2d1d759a960	\\x00800003f51ff53449d664591508d2175bffdfa45914be0682c731449a39e9540eff5cace20b93c526dce3f3fa3acb6539c8a97f7c8a3d465230702647a1dc6c24221ef3ed6e7487e7b2b5ce9b5e91be1015508aee67efacf471fbaf0d83f600a880240d9b1473b4c406d3b041e9896361ea8ee50c45c07d1c5dc5c78b116e76a1f92431010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2174b7e606c0f52c2c69b00c37f0afcde27ca42558fb2525ec29033122726a5e20631e9d072a902d1fbb6f6667b5eb0992e42eec58da3d53ca15852f1da2e401	1617817171000000	1618421971000000	1681493971000000	1776101971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1093ad246f7b35216f3de97519ed2b9112b06ae9bef868d36d8e1f5f7d0ea8b015b59d32f14f50bde6960dbd32dafbae42e6a7bbd3a8dea73507d33a966aff16	\\x00800003c435e073aa15cce7c17be95a4c0ac16a6e9c5ae1ee399c0d1e6f3621df0c386959d8201ff4a910f866305c4365e3ffe94c80513de77dae9cd7764b68631636af27827061606b07fb1a242e4daa31c1882ed5bad8f6dcc5023ea1e185e8133c882db937528fc3a33bf6217bc787f41b781fae170a63c6edad75a6caf63d161251010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xefbf9e177d9f947f36ea0f7f52d267e0ee72189a52d37d5937a14c92d67c539f673fbd66ff23e7db2d02b9122942c981f7304cf4db817eedf404dc7de3b3f103	1637161171000000	1637765971000000	1700837971000000	1795445971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x13cb91b9d8ced498b7c9406540802d59db87570a0d4db3008d8cc6b932bbe98b778d97e936fd67334a3170c7662d62c66d9e90341994e5946d2737d52d67eb64	\\x00800003cc37a86e1168842743f7d71a4b954492f7aedd99228bef22df532d33c338642cde84c7c88133e99c035bcf67c23922aa8b0e860a865780d42df6e3af4ca5b94b1b7e7f63d540b69dddef3c4a5f9352905f407894c2059313b85cd4114c001a3e77334154b6cb7525bf48b5f6b913a5acb543df3a183d28489cc20f481cd5c65f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe4f30a4dc4056605cc37eaca5eda5c5da15b28a9131cf982b9c31b4eb17a783cf12573aaf0f88ec09ed144a0124f61912415d224f60fddafa526bdc986b77f08	1628698171000000	1629302971000000	1692374971000000	1786982971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x133b0e0a5ccbff59e34bbce3302529f09441729c4bc359ef647f03a054e485734bd06fb3346254ecde901086c1ffe9e17176932210539bfc0769debeb3b7bc24	\\x00800003c1c5a412c90e904ac2f7dfc3652a238bbd9c1c35a040e9274a42d9264402fefd2459bbcedda819c82321d4fee503c58eb1ffdcf9a1e974e11eb64378392a08a439a8feb1d89b3233d397e34dda4ee53d067fe1e5c7ec408051ca18f2c4a6ef2f667330efca3ab7a94e14ab44e6dd55696fb10efe6c3f5e0442d9db1f579073bf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdf572f98d4909355b2e9cdda3ca00cb360d8afd5ae1d1e5d090c32e12226d9009a374b52965858403c8de9144ee1a392efbbe1ad2c12f6573572fd19e93c900f	1610563171000000	1611167971000000	1674239971000000	1768847971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1de37eb8188960b412f57d08e79e76286cd04dd41859a62900a84c1e752f9a620afc60d1347203e38e7d475f2a855e847db2e2e4e1b43d072295e2e9e63d01ca	\\x00800003bb2afc03622bbec7ef924767e05769e20b4fd1d2df72926878c3625da4ba6c2944d47c7f04dda9fa6eb0643ccebebb9380be370ae1948df1c06009fa685667ce166b8b52305c5b523c43cb31958a507646c56dcf00a95156809ed196edfe800759619ea5a25cacf23a9097e5fdf922396b316fda6fe87d8ec5e89a634096b3bf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x45007949523c081bab90a15b468869884dc121dcdfc4a04ef43e9f11ab121e58131db07ad5669f344939a9d6fb2f90f666f9e9043307adb9c33ef07818dde00e	1631116171000000	1631720971000000	1694792971000000	1789400971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x20a76c9917019f32db1e283088a3cfdfccfc8cf0c849a84702151cfe1bc5adcc71e65a5b94ad6e5bee09ef7c40641eaf9509b8f884b998b3ea978d358e0494fc	\\x00800003f96f8e0ee66736fd091c4a1d0dbef528965dccde2439888c42619295e183ab4b30d315e35ad0009daad884f4a428dbdf517c1df3c3106917b2b1ca02344decccecd051185763f2a0c339de14c187a963590c8823c16bcc1833bfef04773603fb2ac89aebbbe6e507b7ced433f4f9b871d2e54af4ee0be1dad4250aca5a054e17010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2d85cca39fe0f886fa180b5596b4ca499c722df3365c1012bb402f830d4bffd887d3018f41366f083d4697de3cf046088f945b03969c93d565fd5fad3fbdcc01	1625071171000000	1625675971000000	1688747971000000	1783355971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x237b28dcb0372c115b84c13a814a04929ad474d4760986e4d880c7a069170b41db121c36defcb670a8bf0bbcf9d66ee515777987de0d401dbf76caee3f5291b2	\\x00800003d9ae4721db7c45740df32a37e194c985bc0ba91d5a6ad6e3b731f11d2f60ca9f29bbc97ae9c72a2f31d721d1422b8e0618caf369e57cd90b84d95f4fe6f0176f926e8686f910724a915e1b81cfefc523596eeca3a43e630ea213748a955fb5168f5fc2a82c5057e31f221ef3c42ed5d62f43167e34e7cf01811cfa32ccde4297010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9f8677e2a4d543185cda33bf8b2f6b5ace5957b25089e19e5a83d09490a2b46f85c3d0df41f28b7a4403497c37817f25415ba1b94063a3ca4befe20fb1cee00f	1629302671000000	1629907471000000	1692979471000000	1787587471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2523ff90e7ed47896f5835e835a65dc4d201cebf9a10aad815891217370fbee766651d6aa19db7fbf0ae82c5706532f16d7df7f85a681dfd390c8ed026e49127	\\x00800003943a69a219012e71d3cf0a516e8529246c18d719b950c8130895fb155ae0834015db333fdb0b96e8e0a2966dd62f192ad00ff12e64c513d6041928328f1d6f9e04157576ccfb1b14c9faec9128a35ddf3941dc4ef0c95f4d393633770d028b786357559659e7ec63eefa5a1005fc6c23268ed9312860a421334f04cf08ee7683010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc50dc9fa8b8926bb41e45b4ca5d8cfa77e0ab66d597f1282c07bf044fb7f8ad375bb68461a759fd53523ec3f954807f9933ba255df8a8cb22b4e813aff2ce60c	1621444171000000	1622048971000000	1685120971000000	1779728971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27871a4844a0cbf6853a839fc2bf5c53f77a678e7259064f0e4c22137827ed8320058819f2e9b7737f72e8d3dafa0e6de165cb6b3a9d4cbc1aceda983c23ff9f	\\x00800003af2da8ffef228a03de97085d5fab31c9f661c58c0df885edc8e417d63132df3f058e70b82098ff745244770a0438938a77a88c049dc9f7afe68674cb542cfaedf024af04839d3f16b1b58bbed8f3d574c71b992f4829c9424edf8b249dccd0d69fdf19836a9ceb67ad514b05a93c02af831dcb09e0471176315d608ca5dee9e5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8f1d47590ecd14e2848d2a566423711266e10bce466e0ab6489040101b72e65c92b45fe3cdc20cbb3f22321c9295411d14744d6bf45e72577e7bbb7dd53f1705	1630511671000000	1631116471000000	1694188471000000	1788796471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28c73d6de1d555ed565a1a2fb808bc933246697c26b486646bfd8d820445b0716584debbd8d5d17258eea96873ff87d903355759d08503391a2f32e91e044b04	\\x008000039492408938e86da02dfef77ef5f9099f5199957482a1313b1acadeda312f7cd53fc07c5bbcfb4f66d93623e2f631a3eb9f49122bd25b22aa1b490fddcef375c9c38a7d665e09e2b66fbb36e784f97b889f85f807b7fc2a1667a93db9d9464410bd8f7bcd00f1d6cc7685eb9e9c9816cf71ef3ea4b3e75ed549b4dd324e36bb33010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1dafb089a30bccc8bc53dd53870dc0a7e45707935aeb12fff21883a90500d5f2ea4dc8729d19c19b4140f23c292ae75f97fbd94ca1b18d122f8d67632a52ae0f	1623257671000000	1623862471000000	1686934471000000	1781542471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2853c106e5158f0a02e562486bdac8ccd3f648d81313892172632257bfa8801a313aa52a8b47970f993be61bf414ba2bdc3fddb691d9149e6fdc6e18736ade18	\\x00800003e22d8c9b655766a5fd0aee368cf766f761ccb91a292681adce1bc9742de40e12cdd460cf08f0fb904b264fbad043d9adcce822f12dc5a077dddb7ce3d914aea39a6c8972a5de08c16243e41bf5c998750eb4d4f8b85574af7f60ab2fa5f324a26d9cba8701b440e9a034c8ba0745a9b706e4c2ceb3711dc5f641ff6af72d7283010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc542f500cda64afd18b4618cf54fca4712a38a036f0c4da2ec6b6788ec5a5c6f6aec187878bc43fe1a3a40c5adcb904ec6b4fc83bff0628c2d25f489de1f8008	1609958671000000	1610563471000000	1673635471000000	1768243471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2973f558571597cead3ca05aa0013435613af36d86b798fb87eb10bfc6fea896500e2e2192d4d9bf36f0ba214c7b2e9ed1561c7035cee1139c6cefb0dcf4fbbb	\\x00800003d233c537870f0287e6753fe57d3ede446804830eadfeb5eab22588ad8a90d8b9c18a13a9150f06bfd041ed6467a54cd877a0dbdcd608866d36860ee5a3bd737f10fca6b9a3f3f4487412d695dc1dd31b5829b5cf405baabb4a3516ca25a9389a4ba525d8feb59dd34ad0746b749a176d6dcb93e13858307a8fe3fcbdd3219847010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x56b77c91c1b7b776d2305aca51ac3ce027138551a86b6509ce63e68709b9076d4f6730464f9a65feef3ffd710e743dc19c4220dd8389f6b88ecb944a1c9bd10e	1638370171000000	1638974971000000	1702046971000000	1796654971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2d7bba63835f91f4b24207ec8fd2d1ad2f4a8492a1089be4bf000cb5942dbba9e269fa2575b51cd830b02abf1a9aa1bbf480fc08f3cfbb63da9b98f8f7f778c3	\\x00800003a2f5b2656cda7bae7e40ed623ad9fdaaaf9abffcf70abfda166168a64e8c74da2bbaa2d681d7eb09a251fa0decd5cd3286ecbea5381e9c9c0bebddcd7c906c574cab342d65a6877d2bb790fd5c9a49f5a58e95bef8de35e96193fc93858e483ef3bf075290f6c26db7122e06f2229d70ad799ece06c4f99029cf37360a15bc27010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa2c33036daee5491dbe79f81258cb147580fdb7bffda3d3872c8a33aab6cd56e79682bd85714c7f840dd906a7c631ba706095eade8a0946b69b1f874bc88380e	1625675671000000	1626280471000000	1689352471000000	1783960471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x30032463a211f9362dfe349ff36558edae53f562c8a350a935d43b10d6fae6dc88daf763c6c018b533efcd5ea8166874c76016c0e9125a85fe7024a66cf6280c	\\x00800003b4d17039beae28dac0e35e4a9d0551bbcdce335a60916d181017379c41ee205e2de788f852b66dfcff4a12672cc32a80749f1c86f44aee21fd550b7ba969dde7ba6571a271020163de9cb6ab9bd2124aea595346e0f790ea3477adc63a6cbbd7e722c30e8b8f0ee8885ccdcdd61abead7ba3f86c6adc9d113c94897f85b7083f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x88600c2d8c829947d393557fef109b6882166327996b861bb32db5a31874878a250275fbc03aeb1be19596fb2d7cb693e77e6417984c289e9b5635dfab3f180e	1611772171000000	1612376971000000	1675448971000000	1770056971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x336b72a588cbb0c68022264bb2bace8bfe0f2f5566da8c9bd4e54add7d0fd633bdcdf860e64aebf2b5e60e87fbdea90bdd063f13724066d6e4e18eedaabf8844	\\x00800003deed908c4fec32aaef601717cbbf9d18904f55dc830901bc1403c74c3bdd3c0ce540c5fd81dbb541b75639961d2cf08a2e62d79928b3cb5fcc9408814a780c36d606873dd7e46f84d235e8a0d9394c39dfbe75c09a5f04b91d2ec30d711be7de7bb39b4e247ffa0f639609fe000603ea02d2f3896e10acf76dc94ea5842aaa53010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd8152865968ffb7bf2c03177f0419a327fd919464e14197c51b150dfbad57a644053fed1767b60f9a9a515c03de0b0a8e28e9a89604652efe9fc1072119eee0b	1614190171000000	1614794971000000	1677866971000000	1772474971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x36d378e2f137cb362c7aa86f9180211d2dbdf2f40f4f488b59e100896baae31c1be9f275c23cde731e0cfba62619fe17dc325155b320bb07a8863cbdd573675a	\\x00800003f5e886699629d5b7866e08a4a66cec7ac6a6c7870be58a01770c9e062bc400ad5f76e78c6d96a712bca2b99fb4dcc47e31053727ceac8e91c20209d1bc0dedcbc15d92d38e853fef28c90d0bf94bf896e4c7150cdd347d84d44782f68f7e48420b41f6a8a4a9527f6ccc59330c432a386581e75a00f093ad9b8dfcafcf395dff010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd5f3b20581b6053456d5904671623aacec7fc17b4584e0cb24146394cb32c7e0d5fe83211b6ff8e7e6f92986ad6b83a388ac284db004793ded696fe28e5a8a05	1616003671000000	1616608471000000	1679680471000000	1774288471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39ff418d2f7cdf3ee62021c2b19d34c5795a316df5ef6960e466b921fddf3022e3a7cda2fc37babf31764402883ec6fa8702bc9856053ad04fbbe9d4343edcec	\\x00800003cb77854dd1bb0165beab36e86b4a10884288d7feae2ef4784b1bf7f465a687f4597bcf091a1f5d6b14126eb42a5c83835938df83b01d4dc8e0774aebb8a6ed6c56837b0df9f8be23c0abeb5aa07fd07cdfe9f41ff3eb15f16135171ff1fd20daca84e4b7fd899916bd53344afa2d732ec607cae7c485b154eee5c5b1b070e4cf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0e25d795ae44583570408df3a25ffe867360e6077a5785651b830de517c0de51d156d0ad2d783492469cfca8c6f75856c5ad7049b0fd2dfdf898f63e00283c08	1619026171000000	1619630971000000	1682702971000000	1777310971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3e97862a6e07a7500c0d58a0a02e54fcf3d3db0504e9dc0734f1b2e8a74e85b740ad921170675e73290bf495f908aed87c299b3403f809e88031f9864104b682	\\x00800003e34b650380a5ee93a143681cf1a7cb51c8d022ee64aa202d31a930199ac09260527669b88e3d9c263b453e510dd01c355b88b0981880da658095d90ae9d6c5f66f4804e0d8d90e967ac16cdf70854b18516f664a1045525471037d62d233abeb41eee12aa584b1575f74cef0953a7e6a41d4b0881d68723ace9d16d374fa85a3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xce7bbec1262c2b9451997cbf02d1a49e221cb5c8477fa6655dde5410a9483c5626534f59b268e8c47fc5515bd6e61eac7ca604e45b893c94846f24beca362905	1628698171000000	1629302971000000	1692374971000000	1786982971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x43e7fb35133379640fb65c49f54ef0e5d29e4f095b847072fd8937fc94b9779e33550bbc6971a05c42a6457c10a5cbce104b901f2290642b570c7a5c643385f9	\\x00800003e84be68098e058b040862fd88eebb804d6b38db57ca5cdd679f1d4431b9d83a69b16c0070ab051b07194394a87dc48ef750c9ddd33f0287fa3e3bd886d211a9d5b30b2b2bd5e252ee308ca434fb9fb2ace1dffe2c5ec39c045ba2aece23569141e75ac52d50dfd649ae805316551d891a72c1367671a6ab311a7c44c02f2fb2f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x438733ebeccfe3961e36da0dcb6e68869763f9ae1124bb194033fcf2fda4fe05e90f18a0b6101abccc162c5392541356d614d00fd666de48616be77aedd3e504	1608145171000000	1608749971000000	1671821971000000	1766429971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x44436c04122236a33dcb4d097c1f2aef1e091dbf0f64269a0ddda1da7fc1113d2e2eeca11e9504040824980c9289f05ee185e6d0e10267de4eea32f63e7ef78b	\\x00800003f4c82a4ed7bc435fef47bcabf4b2d4529d01e22b7c104b3fb0f0c35099b389a2560505b46306874498a987f22bdfb22a61877a08fb5a124fc391fbf0bbc8ff3deadac07e78924f6d9f150f445f7d91b8d23684b80bc0b2e0a7799c501292ef868eb96a1bc4c4595ac64adc8b806425eb0ff080c424341064e45f109692fa6a5d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd9ddd0fb7ed98a8f652be09f4b318f6e8d586c5ecf18be0acce8150dd20c7b2a1c80623f7fb0fea5a77a85f94a1e5b6ae7a275e096971aeb4ff7a21a59515607	1634743171000000	1635347971000000	1698419971000000	1793027971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x463f515d26b916ac7f7924cd46c4bfe28143bd9a39eb4494e0acf9c0b39cd67a98e6dfba42c6eb472d8110344ed77e349376ab306ea4d87b8f2c0253d4f314ff	\\x00800003cdd8d29bd70367e9fff510b3bc3883eb548a08b741734b8e3dc4fb9fdb6839591f2ffdfc85594a2fe8e2af9ce67d5712324d1efaafbbf3c3caf2c1f6a4ba96dba7d21d4477558a84470661095d533d16eecd36770440d8eba93982f37e9bd355a4254a44cc5ede0d02a456bb2d59f5aba2ad74ea6a00d5b5f6349ccc77bf6b37010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5f1af34ec638212346afcf79df1d8c5d9ee1a0677e6b9546f27251798a15ed51221b1e0435b8a7ee49296585b5e3386466ab4d3000631455d4f4bee1e13d8d0e	1629907171000000	1630511971000000	1693583971000000	1788191971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x495735b64d2cbff34bb15b9372ab47ab5025864192be3ebffdc9a8f5c83cc0804998a878180aeeb4276f5a5e4ee5200c6a9b32ba97c41d92944bedae4fc1a484	\\x00800003ad52608e761c53688ce2e044bde60679f52ba0c80ed76806edd4e9c846564a5bdf0b25e6f9d71314d5f75a4600580f1bef0744362da93b89a0faba958ddfecb9627a0f5ea9eba64f53ab8d8e1c1a34f8af294eb8eaee1ac6d17da27e7e40626ef0926713c4a3e011e2267da7555299221ee19b8df5e61a1342bd7c829b5ed2a9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5fdfc906e024d48a82287e07aec2b6ddd4d3d88b4c51b86f96fcc06f268a3edcfac78a92b32523313b88c7623d3a9d5cf3087816ceec704b669cf2de57c34c08	1629302671000000	1629907471000000	1692979471000000	1787587471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4a4792d1635c985c7ca84b17836621349cb0cc9d7ff3be18e2eb32d8ade9d20ee8ab5acced13237b37c31a55c2edb2c421a3d7337d9b9023e94aaf6fc0c23e76	\\x00800003ba0e88f62b0f59d517de1a2120f359d8775767aee48ae623f3651786219dbd547fd75a12b4cd388df511a9d83a03f83036accfc2caf1b162938e683a06e2b3642974c4f4ce6f97195a930d9263caa37ab90db151a725860f6e550c214087a0cd53e8bcbeee0c509f743ece193cd0b41d36d4f0bc9bf1e31e18ee926072d7a5f9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd2071753d43101e1b18357a5304d4923cde98dbff934b550a290f45221fa6eda7def85c0993b02bcd3779ee16f406b6c2bf0d92509ba16aa63bae7c9251cae02	1627489171000000	1628093971000000	1691165971000000	1785773971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b1b0bcf1884184fd010ff2634effb9239c79dc294135fecc2089b4426ba7128f42266b77d942e0b9183f246d769551dc09e6c69fec63679810f2e326daa0f7a	\\x00800003d7ea668d9cfa6a6b1685b60dd5f0bea56d5d7dada82ae9d4c835c798d7e2229fa18e2d94b0ded975a1d4b592de7ec167969594272c1be797880d395bef12d30e1757734d78037bf4268849717c650720980215d2174436eb647a95f4924a2ef85f520500ac681e3155882a3f6f68709fc92b64564e36943f84cbe4b0721f38ad010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x47b1c15aa4b3a7a452ac8aab0d7597f6a3c296b3440bc90d53d108ebe914305920934b4506d780a9defece18892c9157e97e61beae96c40d0960f04c7abead0d	1609354171000000	1609958971000000	1673030971000000	1767638971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bcb9a1a11acd9494a0c208eb8e01c9ad15ffa1134e3a8453dedf235823a9ff92aa55af0562da1f76b40ca3264c38f5e661f09f856353ad4b3dc89e5831d43b0	\\x00800003c1232e94c407a69f8eb3707e5df15f63f3799849e7954396f93a6f85bcbfe496de9fc69661c65d1913bb3e0d0525c92d7fbf09c637fed97d0e41781fdec7cafb3cb9026bac3c23af15b19c1a4cd8fda25f8e4f3b5a20ec04ac558e81ae45e29bf14e35cb8b9329362ce50b082471705d7087729136f6f5dce09b31a59ea27abf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x90f9e4408343bdecf9e79950f5d979edf43dec240a095eb13834294432f8a5a0690eea5f95b42c91b1641f4d60fff04b94d653fa1c1a1cf0bbfc464a320e4600	1634743171000000	1635347971000000	1698419971000000	1793027971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4cd31e60fa84f3f5a08dc5b4815f01c748d74865daaf8625b0f8b9afc6fbc89230d813ed4061ffc5347a747a6d99ae37bd79fccd569ad1ce17cfffa638aa95af	\\x00800003a5437121437131d63f7be466fd1146795649b5e5dd094fc1701779bdc17e5246af8d3f9643bcf03e46d878f96927bf1e7a82f345735b4bfef8dacea5bbef5b052af746546d8220bc6493bd9cf21872c110a5cd89bc6ed019ee7fc552c38f645d4a9ffac8792cf1f00e4dec3dda3f4abedef7a45e65a79e85ade3ab32ddde295f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xef48a25c96b9a7d19ad49bf43d0c3d28c085b79ba52cc47ae2066bbba77cf9c6b27cd0f47bf3263be55d8feec8a72b8659298bfef13b0a07306c7900ba29750f	1628698171000000	1629302971000000	1692374971000000	1786982971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4ed30a02be4216bdb5f7e7e026cdc74c5cf7a82c093fd9e35220cbd621a56d09eda62bea77c78919992273aa63bd6fa42a49eab181429e477b05551c837944be	\\x00800003ae7dfc7024115cb3dfa75bf52f379e18891bc1c38350a77c660dcb6f42715488221776908514b4a8a9f1720adf9ef74d09616991c73564c57474b2471f897649fe4a92ad9869caf2a210325946c5d6a92b2f4b728adb065f59ccf2a95b7be39db0172d20557a3edf492d2d3a1b65dd1f117b9f22c167f5a0963dfbdb156a2a39010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x60d616a5c5cebb91d6cb32e9cc7b7cae5046274b05b8e45bddf942b0843b9572d2e05d441211e0545230b5135794a27adf0515a8d02c8da5d0aa48a6f9b30705	1634138671000000	1634743471000000	1697815471000000	1792423471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4f53775effbfa864b010a622373ee8512428c7d4ae3e815576d459c0df174aba69b085903045f0f5a78c752d5a6c372bc87a99a60c0b1c7b225aae2d25d8a9ab	\\x00800003a6d8ed12f65e5b6020cbab579900c4cb88261bc88e8b8580fed958a69f0e8fe6e60a482bb7398753e56c9daa98ba94a1b99cd1da3057d6bb4b372509afd7cd39ea653be59164f215d01bdc3249d2e98a70f75b7a2e1d2df6e4cb03de764cdb95b0ae72b2beae72b01cc07bf7928d4d5b87fda1734c22f8ec5d8b53ebf1c446dd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd06dd22f58e639924f3a5492f992dd54cf555a3a9e74e09a4b1020c2cd66da84e27b21f57abc2fa4ef49c3e077b0a458876093cd5e34950eb6b8233cbf5f2203	1632325171000000	1632929971000000	1696001971000000	1790609971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4f27efbaf8611ab935caf7df19d28710f5416f253660853c62b29cecb3c2c2d9fa027685a3675713b06433c47117c59cf5df13d667f40ce3ebf9815e74043baf	\\x00800003c7fb31f0307d292633f4f97d52f8592faaad6b53840a51d6d1bb6664cf8e49d82d049a4a4e8d83c9e28082b47a6464ece3aff746b90c5cffc3324ffbd78cd68fe5d872555f7939e76f561d123c1073d9581793fa08c37bdee0b5a6aaf72d0e8fb63b56c07873178b4f0c60918bac2cf9e0129a77a1b1893772e590092c0a604d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6a9c66acf96502f6c53a580f9a302964612505439dfa786c3da143149781047415a28702c86b80fd3a7c5edc46937a3bd5b7a53cc457ae0499d5cdf69aa8600a	1610563171000000	1611167971000000	1674239971000000	1768847971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x536f7067822ef3c96f7f528884d23c99e25bea9786ade54c6a5e3a4771a412fd786bb7e7f2feddd2b497c656c35b7fe1979e5c4b7e92cc6594bc715393cec7fd	\\x00800003ceb7762e33ab37caec59c489be6ce9615769486b0899c5457d0242676cfc63ea889054f3234e4f488fb8f552b81c0302c2e3b9e58420710b1c8e25c9e92f6060a3de7d793cda5c34723133ffc6bf28542e5065e61eb6b745f82656a45d5e3ec7d4f743b3145869df6fb2cc92adca3022bd62278e0db756ff0ff887d811143a19010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7fe534b46658995fda7099478b3d8f9891c2318fde4a7f5e774b984dfb2fbded29e5f96b6b717e1b3fb8ea622e84e2eb712513038b865f96de427adc5a353b07	1628093671000000	1628698471000000	1691770471000000	1786378471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5833c9d7baaf6545c546753fafc0ce74ed01cc0b529bb36c33a7fc2622c2c2a589a8f0b444fe011c1296f597e0178c2757ca1af4f695b120c6c047e5dad0a9ed	\\x00800003cc5c2a52b23e089724b2ad5468d96524f43eda9c40b1a70aa396bc5f3e6153148d89c7f34a73b2c0faa7371b281bb1cfb9eba02e99c943439e8a1b71f2ffdaa9db7e620b38ffb42df6df5bd64e2535c00f6cce89c48ba0da48d44bc927c995437b5493d33dede9edfc6e8ba57b7e5cc8a0ae6f286e817b30ef1a66528e95130b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x24c86ec980ede0d8fd3a1825b1c0b70fbcd8d61054470a222b61d413dc1382dc52449ff9115d77dfa37e8cd066e7319ee9aec116188e2048eff7b14b4473a504	1632325171000000	1632929971000000	1696001971000000	1790609971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e8f706eeb2f099a4e5115450eab3b9c1818009dba9f98715ca0aa551a048760c7748b02ae6dd93de9515eaa07dc79f2d9a2f46ad9fc9ce5209e522fa2d28681	\\x00800003b30ceb456aab53b2b492c338ef38469abcb0b53443b3eb1d3fe91418e539a98502ace8d5c3b322905077ef383bcee6ad981d1f0697726d534f3e1680c3cb0c17a81107064b063e59ef1b41d96fad2730b44753787c5f5236d42ea4ff0b1c0c6447e65f97370e6c2f06ecf99f911d2f510bc4489b950f2f319004bbdcb4b662cd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa5713b9d1d39befea36c4aa62b1c599afbf0a04cdb8a1522871eae115661b737880e802a1482cda08f53d34081b6105c5d5e3db67b958f8d9f76886dc5359309	1626280171000000	1626884971000000	1689956971000000	1784564971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f3b42ba66e4d5c9d76bd80b271053625eb8ef296de7dc8e8d07a47133b049472e6b482d545ce457aeb11ddf9bf35b4aabfe1f2991b51b23af60a2b9d3fb7e7f	\\x00800003c9daa804848d6e164a59e8cc7d9a415c1539f5b5497ecf079fd7fa686f5aa650108318d9d308fb840f5d8cf32eb6c366613efc699e694df3b0c257a0ae84fb01837eeeeba4e5f28bae913ca4750662d92e26d4c227980cc21e45c6855be1fed4a1795496bcb843b2f8b9a72b805a1cd9b6260a03e3194a3bc8acb56c30fafab7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2c3ca50bcdcf6a7a84e0d39d69e4986cce4caea8647cef56d74e5403a14bb87aca136d3209d6d3b97eaed1396830af911a3cf8c3dac1f74fde0dca8a7b16130e	1626884671000000	1627489471000000	1690561471000000	1785169471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f6788a64a7a4e8048383dfbafd800eeeb3afcb2d5662d2af548f7b5e601b320988e3383d234d59d622d91f1576d0a08924bf005c650027121789722a8366569	\\x00800003b7a1414135eecab6578d9dc8c9ac45df1251d6b3e02f0f7b1aa78b4cd27d7f78306779f2ed745b16c5318a1b67b065f394a3d3c26443a4da8cb4c7a064a837bdb08708999b48a0677f43691e46594e20cf9db091da8d5ff23f62552f952b2bc9951abe26d1dc1b438402136b04dd111aaf0e6961463dad9b9412ffb797c611a7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x47a40c4fa45a4686a269c6dbc6e251715c56d212a921c4b495fa83f7dc472a1065dee423a13d88d40f8c25834baae79dc06e6fcb1c4b4a7a10f975dabfcaed0d	1611167671000000	1611772471000000	1674844471000000	1769452471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x60476a719fc82c66cd0809d43090d311e61bba7bdd66b1f14c9e9a8cd1eba4ee900245fd4adb2e46fc40d46bbc5a3b52399102beca05cc5af3b48edd74350c7e	\\x00800003e5ded75a43146b745f07fe08109013fc6fbca23ddc8251ed77c850f8a8f80d07127a53a2902c8192c6ab3da972ac8e6f66ae8dd926f8479221103b7fd589896be22a2663c6046c7c41e274c88c8bc56f257640c67465206b46aca5f546e6f8b30a27f2f1b3b31490313d53f149326a79af3261c66988262470e8ff48af1126a7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x13dfba12a1104875e83678411bec3e6b5042ed79d79e6fafb052ae6316b7646c1e462192340af6eec0f6f350fd0d3add403b6783573026b1f3d4d5e74557090d	1620235171000000	1620839971000000	1683911971000000	1778519971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x624393c5bfda3cb88e29e9292c317ccdf63a7262785177d0a7e43f2230fc2c2d520817fc528b6ed1a0ff1fcb0e0e6701b57f42349f433cd336759498b8529099	\\x00800003d5a329525a0945c3ad756dee4b6b52dfa0ac791ba2a1da0cfe4285e2c617f0c13919b39ab5573d9a645bdb4ef3e44bbd74ec60c17ba1037e437de4de4deaa24a99e6cdfbd01881816ad8a2f534d1cfd073c966826757494c6028ee9e92780a266106e2065ea3e60c8783b1571e98c16b33eab2c668d8f4c293af5de3de2c3ad5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x586b5d20a2bdb2f20d87d95788f430ab87e46244b145c0fde92c0ab621f7df1c65a1d034206bf634deaa6f2902fe44cb6152943f5f26f1ec97c3a6003163610a	1626884671000000	1627489471000000	1690561471000000	1785169471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x63ff5d9f6f6226c38d6e7944a671a4a52bca02fb9c9517273952e7ac73cbdebbc5958d094f49ae9a6b5b3d8e0c17cf606cd2586c49f0bb45ae857906937fd727	\\x00800003ccd462ab19b394f5b3329a583b00fa6a9cdee9a15475a43634e54f3bab8bf568d5647f629aa310d5ed5915e75854877c045be79e47c60d6ef00d66a16047d85e6c8b8b47df3b447a22bbc0cadb519a6cc7fd6bf969223231a0cdee7fd4a405268871ce36d7295bf1ff0ec0e4d32d473a2da0011fcb3c777b184deab1ba26fbf9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x9c3893d845746cc11c00616a96f7c3e1a597ab68e90b643bbdbe40d07ea443af70bd008cacbd94cb4f3f0f943383d40d65ebd0824eb29affa41df8db68408206	1631116171000000	1631720971000000	1694792971000000	1789400971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x00800003d9273bdc72e154d95a1277f579f2d24edb1e654b5e4c643449b3859c48ee5e83cd5d6fb006af013d508b1feccdaae1a83bfa4a6337518d84567514c8ef6f945c3ee6bed38b26385aa50a3f3c2ba934ba807b119627b4260ccc6badd07f253091d7e7f3e7679578df16ecbfbd7fb1e17d6d3b5b1e0839aa1b2a2bf933df909e39010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6e9099c5c9252f1f9bc891cf1f1668a89ea9cc8dd476d769db53169dd7854a7ad13c57113c970e3afa97002d3e03cbebc6df8802a0bc1b0f6e610ec79969cd07	1608145171000000	1608749971000000	1671821971000000	1766429971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x643397db50c3e7bcf9c6ddf4a20dd2678006d9e1628c38633a2999e67491a26bb83f3e8824eb3d94397e7f80896d9ead70ee5b5860b56fd00b3c1c2318feaf50	\\x00800003a034f67fc04ff8edae1e0e303a4d57139f59f1016288a8997c96d31770d89fea096a0d2b4bf2cfa445257ea66d1291517dfda994dd1e07aa7b36ffb6daf86c51433f40e7af7f39a62dee0739b3ca9c93950c146439034542c7c776b51cc979057433d7cfb322e84261743e3c1d4872bd2c097d0c418307044ba752265e829813010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe2820ff659708f06cf3f82b5cd6efd62e28668399adb1a825eb7db30f23b820a6129ded8c020f650151b8d7e2019153dedba911401607db6ffabc2f47cbdca03	1633534171000000	1634138971000000	1697210971000000	1791818971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ed78cdf703f5c971f4a53517b03274240d5a7fb1de6ebfd515d7518c12f5155258132d09e98bc9e715ac8458e505c719ede12abc95f3a37c9fc3a328ece6a88	\\x00800003f90e3b25e6e45707afca8e883dad4c2805c7396aaf559e70bbc46f104852faaeb52bc980688605d86b95d1501e96fae5c07dd920ea570001bfedd7e187ed511b8fbb992ca01710cf1c2431ffbafd6d692e8eaa42ca5c9dd88da1faa5aefd906d1c4da8579fa8ce64ee62f894364c8951170e68346151639c28193864a509cb89010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3e28726f67ac710a0dd117cf1ca629671085877a0b1f33d0cb601ab50590b2cfaef167890d3e4489a04ffd71d9f2442705bfa3f4c6e151bc1545a18fbbfe3d00	1632929671000000	1633534471000000	1696606471000000	1791214471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6f1fe713348c2003e8c2672703b8be268c8a2a280080f463db52775696a88ee1605e9f2cdefc99e839741f0bd84aa262c124723f5ffc43b89cc04ab2b2cbad02	\\x00800003a212c99b310a31f1d88ddc2bfcc17bb695aca9a3229944690cb77dc9f424dc4573b7655fa5f70974dee09e7b0a21cfbfcb5bb424b02301a25b16656c2e46a62954dee70c231ab8db861cd32cea32d6e7f2a9211b802d5de00ca8f8044a99ce583497f9a366549c58a76a6a692fa795aa4cb1c3a9f0f21b65350725fd132659b9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x658740e9b629e73c25cbfd170b220d6b9eae74545f33487bc911faf4f95526626837545b62e6fb9eba00352e5829d5f6895b3b82a2ec8c0bd6a6c792daa0a005	1629907171000000	1630511971000000	1693583971000000	1788191971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x72572659178468469bdf80b1efd6911f9f5f8963bcae599df5baf6bf2ffc98fc795d173961f283efbe1544465395853edc832c728a3b871f2114339fda251277	\\x00800003be07dc424073dab5fdedceb99d5da0609d9b608ac5b8bee24671ad3cbae0484d411383d7027b5b98e8200aa083d04e6c71cfd6b5710fdaa842e59df397d642499bcc6b44e4717a89e4454fdd60cd7f4bf50d82eaa0d9f3f3d6773eac5adbb3fa67a52086d677825608b79ddc04cd1b1539139655671b5e652444522ab1e3232d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x725fbd2a1f80469334ee6d0acf1d46d70e2b14347b5b22586808088a02aafe8ad9708ff62120f897c23ab035dba0c1a730b9f49f2df584cbe37501a43713bd09	1639579171000000	1640183971000000	1703255971000000	1797863971000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x75477d0ea374b3183158ab9f964db5762777e9865823d563eb6a02a335b70e1ceb4c2b940bcf8c3aed5f71e11dbc2d092851192a1c10cc8f5628c4d6e46f72b1	\\x00800003c892bb7bd585c0540012fe74979f0f747b98acfe95deb1021e868857401acb0ff97bb768d488d276ff95f5faf7f7fe87a60c1d0d326258ab626b1f2aa9ca354b574f26fdf21c10d64cecf9a91ee2c99ad8fd99f4cfb95f33a13ba1c2bda6e31300ac9416932b553189f6590fb42246aff1806b251ae4831c6fb1d57351ddb7af010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1eeb349ad622a6366ce711f5a224c8b6711633c6e9d09185d1fb6279ae6e854b4fedabf9e4064add5d71be21712935576f562c99e0aa9d3ac61e31aaa09c770f	1609354171000000	1609958971000000	1673030971000000	1767638971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x767718e2c13d16d35fd473b8b6d29f3f5033c190672b8b411527ae33c9c6df4917b91f8dc278363746cea89e96ea316b5be096d74e6e16d277fd4073b07046b3	\\x00800003eae30db49a44f187bdbc75bab12b3bda26cb22f441eba0a642330f6b857f2e48edfcc65eb9fbdbd389397144f7d1b9f1444d8e240740e4de296043807d6f826050488a98f1097e89cac1f15f0dfd62511a512ce4f8d3f28573b30eacb9ad80334f535303fbfe5e0b10e6df4edf28eb7e2bb56f9cdc6f156f32afd43b4b35f661010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb45c03b5608b3ea3acbcb3b95435f59a2875407ebd34de62825a7efa0b57057a93e0825cd458dc56e823a3f7156e91766d24c7700229f696b83c85f6922d0c04	1616608171000000	1617212971000000	1680284971000000	1774892971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x78bbb1617874ac622d1c3dc52e01960514f76264401b994f269ec3a1938751781099d92226088f0b56361fd2cac47cf1f878bbba065b978e4c9e2401dc65516d	\\x00800003e4c5923a1a52bacda49e739812d5dcdba84cddb717389d079845b29c31033d18ef763a146484cd63031c4e78fb4e264f4b27f269046b84daf4b6b57f41a2c34d9ae34e9bf40acf859bafbc1d621956c1ddb91f6019ea654ade94b4f746f3d0d28df8143f06ffb4a73b206140f204a540446153cc06a8c7b4f2f3d3d40e855beb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x976abe27f0dc4ee9f391b66fe05a96317a5fb088508c59b2974d012b48fc81e1f51a33e016d19f5d2ef121b2b8092e21d4060eaa50733bef6903e7654f45a104	1635347671000000	1635952471000000	1699024471000000	1793632471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x79e7f20baef467383e22a862519c933b07649fb9bf05f48e3ddc733333db54d876da0922d874838c2006020596e36bdf4b4f79be1223d1b576572b01c9f2dc9a	\\x00800003d60825b7b240aaee8d83892ea2abdba8cea57f610ff584a56955e7ce35b83a81aff2b859861973f961182372397d656a271498c53e76d6164b9e682b4478feaf07a97981cb0665070ec82cb01ec57ba1390015c4849a6a5195bbfbf7262ebba527a0bb6627cdc0098ca9e22722713774b7d12890d6aa94a194f8333aa86fafcb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4bd5961a82f725ecefb24bb6e5fe8a815c1f1ba977ef67eadaf40c5a55e78918f8c059001779286f56f10b173f9ac6e8b4ee72ac87dca04c3b6d50a2b6cbbd08	1637161171000000	1637765971000000	1700837971000000	1795445971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c7723c33a3bd30f8d7936b9f12bfe2757ed3bbfd93638d2badad86466850ff7d9b997a68e609d3c062a9db41d8adeabc8546f928014e883b51b6bb27dab01d8	\\x00800003cea4294ff210001eee6c595f7443fceb8cdb95abb8f48b0f8fe023127eb57d023e35e7647646cf7397f203e7405de53bd6c3593a3014bc4a860b5bf6868dd30191f2a09280fdaed8e34df6eefe60ec9def5f326051eaa78c0be567d547e5397b2c4219f97508675e3db712def11cd6783b62148f8d46187fe26deae48c15d6a5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3016828d0e3cbb130c43506695e8ebf0c71095984198736d1240ecb3fd52446d31361fc334fccc269c6dcde44bfb9fa7047d979cca11b208041b26c2a544a504	1631116171000000	1631720971000000	1694792971000000	1789400971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f7b500eebecf74affa1a68b4ce4d804368fefe105d081dc305eacb0ef523cb6010e73cfc71cda3018a5213ce8bd863d5f91f6a78fd9893c791be72e331a33ec	\\x00800003c5ca696cc4c2166ef761c8542c30fab14dc1054416b91b8d53baca3a4c2e8c329fc4325c39a94b4c5a97fad54da3b4f42f1de236ada1cd73080419a2872552961462ddbe71a987ed2c8d174c1ff73a359c45e49a246dd34cc3396ff6589268318729e104ec7150506702b2cfe4fb1892ab1c8b3e9aef06b06a342da29060d44b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x642a3f5a21076bdec7599ac2077f4c086c6d9950c15186b7a3ccc0726c5aa4509b26cf41694b6bea166e695ad5a012852f971bccf7197997b5dc445fc4fe2109	1609958671000000	1610563471000000	1673635471000000	1768243471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x81635de6f94586d4049ff68654924988852dcb2414565f27bf0f3692162244adcbcb86db6952346bbb54cf378b424d5caf810a0d4528281e452f778867a1f2e2	\\x00800003cc53728f63c912dda809b343189e41340bb79bf39332319614d547d00d0f83ada2eef50b9771fbf34205c90dc7d9eaa76e2d4482d016a87f250219d82f22865e5b7aa6107ce5167802b4f35261fc6054c5a95ea865f5ce0e7e32a340e3598a8e97b5934228e2a6a3af71b507b1c643d7da4ec8a404a4ef0f3145d92c19e56dc9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xfd87e33801bcfb52b06c3842dcee47eba5d6aaa335262ab464dfc3264142829b0473b9aa2a9d6ad12b888004cea2060b6d984893a6faf2dcbe5e482fd7699e0a	1622048671000000	1622653471000000	1685725471000000	1780333471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x83d3195304d41c755985909272ee6a97525e0db18acdd1c903af8aaed288865b0db4c20516a812b055b2f16be2f46c0724353bc9e25d103109ca490932c122cd	\\x00800003bfc183796fc7cf3cdb6b917039ed0a4be83e72415dabd41dfcebccf7649fc58cdaa846a132197393e5a1db6c8cae777d4146dafde7918f20a043caca2c35f5a1fb40afeb78378db00f5b9ddda43cf31a8ff68bc3c3d28f172e00119cb5e73dd2fe06f3a653b39f3651e08bd2b1e4df3ea114972b309a60f3353afe5923c9fa67010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xcefa8bfae938d91caf6256bf3c094eed07101e0fa21fbad92d188057c44072215f0fc354768f82c399039a2041f08598558c7f0c214a10f3464385d663d62506	1619630671000000	1620235471000000	1683307471000000	1777915471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x844f229136633eebb40b208308db695ca3cc3a7ca939759cf6ea07d5cac0eb48a51fa699a2c633ad93afc338a586f49d7c8b21cf6b17478529ee6185392734fd	\\x00800003cd260676337d786a5d660db40f4301941d16cee9692b355cc0aa4eb85238234cec5d19f11591280f1f502674b61aab1da9d452df97edb47745af3aecf4eef5e2173c091e473aab64cffd8a896311858bcc231906073868ecb0dfd826796648e078a31347582069b11935aa381fb64283eda86a4dbcac02d613bb7584f775361f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7d46b864c42e4acadbb73662fe2aaa67d68bf16bef0a493904d37496351d19750d0ffa056fff124aca76b97b7bd429bd839492af31e420d42159aeeefa904505	1637161171000000	1637765971000000	1700837971000000	1795445971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8577644bdc2fad44a44e76c850aa8100ea253139e7c9d5a11d520d2f067d64c266171967a4c566580dfafa33c3aa3ee2df078d6aaa72365a588e9a83ca7b859d	\\x00800003bd942415750429bb6c07b7fab107658670bd6e494c7d7be958083dbf8123c0f2d4dddff511c4a77e399f71ba6a1aba64c01dd7b79e3fc26273964e7fe4cb5b8c649390162c1a2f824def47329d7a94b37b33313378a94dceaf579e6f92b7e97dae9887dc5e238af739139d585b2530c81c9435b03ac4002ba199c9a2ce30e77d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x813e29f8ead15f98fe6000e3ef51a7e93525613cd396c3c34d95614dc6f4122c7060e04c928c3059ac88f55c5cca400cbcba17f55be18ce4bbdbb2a25cd4f904	1614794671000000	1615399471000000	1678471471000000	1773079471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8777e90e9045765521a4cf7fd821de5f9252238f0fcfaaadc9310045aaa12b9c0534da881f1c9f2f64d329243aae7d49a14070ea751cb8f5c60987177563ed1f	\\x008000039fc236cf3299ea5320c77f07cfc73915351218eaafb35eb313045a195daef85fe5e5f13cc82dd87cff45bd513340a5436984d15d20f1c4fe66d61e9f075bde6c6d68b0505f840a9d1e50188e83eb326f523d0e4327f683521f0750110ea125d52f8c2905b3eb577703f5f1ecb6bc6744b9b7e3a98df21c14889ac092680e8faf010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x1e3a519c0eca7b82ae9f870518ced23eb2bd8b674ca56267e217fa87cb389f39d3e42aa2380221ff786913cf1f822cec8a887cced6a9892842113936746d400b	1613585671000000	1614190471000000	1677262471000000	1771870471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x88f3b729d4b2f54b81608c0fa5b100dcbe6f1cde9583f5d6e1aacb8c37cc1d1c544d33d2405bbdfbcd734ac8d02d3027e76ccc8d9a087d5a4d6d08f2ad860c31	\\x00800003e1384f532548dbc32ee3985810a61d260459d8e455575dd3faf776168e1789cfbdc91509f4324b55fd00e02f2c496d3ecc06d75536b7e7faf9a2896168bbf1d8a4cd46d9c35744aae0e5842bc7580d23c1a4270a17f8496d4b405a4d45dd525ad50f2d91bc7907a1c378b3bd3dcef46e68f8a59398a66bb743c2f20ba98204cd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x07101c44484dc666f1bafd940505b7c3d684bf89b648309a3fd758247dd293c4c369aba039cc0b846b2205a7ea6793375e3805bf3fe43141794ed0ca4b9db206	1608749671000000	1609354471000000	1672426471000000	1767034471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8933bbc29e8e10f1b78f3fc4770fa21df3a765d94aa5e0843d4c5010fed01852869faf7015d2dfad8242a0f8a7f0f3bc133cdaff6d4f175e80e14a6f17af4acd	\\x00800003b5451e8fd16eb7093b35d8e5b517efab3aea73403dbe534c461e8dca65cb03e48b4ac852c5b0cea673f53aa99b70231f9fbe5520ae2bc754e409c2d340a8f2b5912daab998a8ad3afc1f9a217c5e06209d54f4ab8075449ec998ff6fbb213535527b04af14ce73b628539859489bbe86da1b85f1692c8bbc7cc620c4203ef529010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7b6299597b2abe6d5da08487ddd665917854cee71486cab9fabcad92b2864825daf006ce8ce0120d39384dfedd9b158604168ec632739b47a9dc1c89d45fd103	1613585671000000	1614190471000000	1677262471000000	1771870471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8d7ba9a94066e2381a8cb2ed1deb4463fd8440f489c8bcf307ce1de82b0fadf4d2efc8744951778d65f93c3310e27bcb626ec63ba4f37a2438b93ee52f0405b9	\\x00800003cabd9e1b5873b3f765744852567325111e39701ec4b9cf5b2ae974178d4db7ed010833472a55e33102255e96e6acbd5ce1791c6e025cb851c747770645094dbc5563d6d0de02da958a62dd106b1812405bde6e2de49193ad53e6afae57dc60bd4ae0fb8722e3eab3d9e5f8e431f63ec820e321bec84842253696aad13048f2d1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x73461a6bce7b072e24eb21babffbc0318d6dfbf47487c5b2194e8482a9b619fa46abd68ce17c923eaaa7b4a9464e02bd301bdc1bc3804c3ddfc1611dc86b1505	1616003671000000	1616608471000000	1679680471000000	1774288471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f73f493951367c8b0c39f4eb5cac9a467fd32cfd0fb44b51850a87fd4a4294e3c014f5d68f64d1ac548695cc9808c100758e2140c15d74e106acf802c97ef6e	\\x00800003b2525d7b7180624190a3d77042770848abff5ae6450bf41b7c98fa6ee4ec51baad737585ea5d14118028f44266aa734964187be89be440bea10031603c6e0935e7944e00b291b57bcff047cfef6a8a1b05f717f20ef03e3cc71a912492589a0793bd936122c5823b0c395bf083370ca1a50b1376a281ef89ceaae26e32547e3f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xab68065606f3fadda756bfed6704658edf1c6ab7723145442304e577902061bf169b4f6f56a54e6fab2aad9a1bdb0455ad9c5762ea4f22c5bf39b1ec353e9c09	1611772171000000	1612376971000000	1675448971000000	1770056971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9177219b00d8f898847a00dd56f9c10f20a6df9b2c800fd73402db3bb072ea0115ac8a8a70c3dc913b5ab970d4cfee59359b5f7deedee46a6a185674cced3528	\\x00800003c642c972eb2ad3d6e11fac517ba80aec14177893dc24e590dae2c141b9bbfe2ea67343a32e4e877dc0133b9196d2530c5afac39400e4453c52ef9cc892cad70426b65a2292624eb56d8c6fcb89629ad2db93e775075fcb7ee2bebbdf244e04d19be44352843226db37fb96ff268bd17d70186bb1bd1e8afd582aa7aaccb6ddab010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc40c0cb85fc81214998a2f7af0c04376f5c14b3bb005c81c95ced116c8e8379f905245a5d034dfd808bd4d3494246f1f13f9380ab73017817f7f9c558dddde03	1632325171000000	1632929971000000	1696001971000000	1790609971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x993f7427972fb5d890b0c3e236710056998e267fb7da638d1cc9f3b630870291639be961efc34e6505b3141dd2eb9b8c8eaff59b4116d2076f6fa0f4cf931aa7	\\x00800003abbdbc32d24ea55f5ca0d4ff09d5be25cc760651e0bbe8fefeb94277eb0e6d8a8496b4d67f0b251b7b8202c24cfc1a85dabfc7fb564adf6a244cb7b091b4e4b538ea920a3a9bc0779d2f12febdabca5980927a8e8cebf5364e6ef9382a706df9f58689f3f22b18bced55ed91c76f484bb0be292ed0feaf5f98abdf48f5564c01010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf2c6134b42e2f203b8b5907dcc5bc87878a36da4dd3e00f15ca5f8259c86ce683e8f62d803e36dae1b8ecfd719151a173c6cbf08d9bcfceec0fbf2e89e18070c	1609354171000000	1609958971000000	1673030971000000	1767638971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9afb73369d9a99cea57f71e80469925a665745dfa5925d5c90a19469a4422b375947e0a08a0c2d41a161b52431f8f573d40c1cf14a031014fde403d4402d7295	\\x00800003ab2475f8e8a2388756ec81ded79795fba9a9f907886d7ea97bb76c603fa8674a974cb96650571a77c9ed993a24b6e8c01adf60c90fe09e635aa07df0b95c89de0b250257347b168a4497c40ff85d5bd3555bba7cb65dcc90a267597c9cefb358e68c836d8a14977b19edc09bae73b3f6607b7133aa2e6adbfdf5010c4d55f147010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x96ee1088483638ec184f7332c35334f12b6dbaf92a3224e05420a77b390db4b85460a8f34ec60c735ad79c6f512ebfadf4e2a146e7fbc1b1dd400eb47ed1e703	1613585671000000	1614190471000000	1677262471000000	1771870471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ce398be513eda5f69b6d8c60a303946c4f5b7188b093edcf10f20280ba5d3006d0036854d3cefd1a4dd61281ae92b0c9d1c98fcf21b25498bdcf82331f02e20	\\x00800003c72e986936b93398b3bfb13355b3771bddee9a0e3b8cd5e3e853775a0bf56f17b262dbc52d22e6a354083ed0923e9fa6d48ec7e6287d7c89590f79f2aadf22ef5e2bbfd01d6e07da084db1173ca6011840b10a099a477298f752717075db2bf9362af28936cc1393afd245df68b892afc3becab0965386d8257a9fe061e8daed010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x81a23109859d6289f5a49c0e124580fca617514b45c570b08e6c40622c6c2252c241ad6e012e5554eede0bd9cb9546b9ae78738f5f6809e7da1ad9618f863103	1635952171000000	1636556971000000	1699628971000000	1794236971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9de7ecec8d93ea8b8efbb996dc3ad44e0de7a0e66d6b10bbe08a3d0b676c6b43686bba496283593700f7f15ac0e68aecb5a1bed7ce889c541663515b2a2d3511	\\x00800003ec852341325fad4b9c7325a9ada5afe062f8047655428a09f73d30dcbfb2b8eaba6bdc5dca185972081b7c44358caee895aa6e0ffce75561963ba1225e0aa027e6bd705f197b5410a2679afadfd87ec3b7e16388f86352c0e4b05ba71e9cf0e91d044d8a78ffa442d7006704a7f1aac413fa4e2b8bbc3fd85f7e6bb4a6595dad010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x19ed7c544eba3fd079a1fbd8c7debc1c5fc191a6ef6da0e82270b4344721727aa413db2da3806f620526cbaa3aadf41819520d8a7dac70a07899c68e1fe5bd07	1629302671000000	1629907471000000	1692979471000000	1787587471000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e8fdad07cc041b6d084296ffee0f4ad8bd5859d1f860b155f31a1ad72d2b9a3f113abebd88e0d2eeb5887ac751eee8efb76f87f7e3cfd091ae65c873c6437fa	\\x00800003c17ab90851d57fb3a2721cacefdf76ad99f852b0dc60edb76ac2afa5881e754b65d14058d0c8e5b2ad7cc119b17bd0e69cd76e23a5c212b3c89902db144c031a6b9cac4c9ac69f12ffeb55d2bce77406dbedd1ca22fd11f8e16b43d96226ffc017d0c4086b620b17932f47e22d2c8fee4d85092c818683e34b60374b442b1173010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2c8eb531be068c95ec59b872ceb038aca5ef14692668403f180825ea6ff39e32b32e7d8c7a94adbb5328e3a34763b6684748cc27083cc3d5ce0ea945ae9d8d0d	1615399171000000	1616003971000000	1679075971000000	1773683971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e4bb840713aa108d356f5ba4afaee17f8b059b47f5b9d69ccc27eacf24744a76a967b31ce56c60fc11a9574b2c000d7b0c7e85ca7c75fec4aa8de1b994aacab	\\x00800003b32247e7c9e255b9f5d152bd09a1774659352db813a0029a86e9e92bfdc63690f576992d480526276714ba71cf4f44d71a343af07ccc5ba3a4c2ca410c3ac45b8a92c8bb8d05108077c103eb246fc3d4e5a4e82aadd987f90bc5ff78a21e0597525f920ed8fbe6f3440ec70390d59bc5be2851b011dff931fc2309adde5281c5010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7b00ce629469b930ef736813e7c72aba4794b5b0858ee0b58b819631302498a48c6bf25cdd8feb2aec0e362f48a46f376bf9ef2f8e700c9015d167bb79239d00	1632325171000000	1632929971000000	1696001971000000	1790609971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9feb9cdc6741074799c2b518d0029980c13eddfce9443e145fc5244b6002a90cd7a9e8b1a8b6cd0e09fb8146ad4de4c10c31dfb076a08e6ada2ebadb2a06e48f	\\x00800003c69fca9e4003add60f25d462d75325db7b0001f7007e8bee9941b6edcc0bf2af8e3f927549e694570080913dee4b863c3bdcf08c5d195a7ba4d6b709f126f480a6e5e7abc0fa83d8219dbb5dc8d59fc02df4a31cfb5cf599194b30a6c5f5c495e3e7bc6cff469227318f04b8168a0b15f22d6a8deb960957c855f88f7fa3829d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xcfe89a6340257db1a05a4467ae16249f919f8dc3f9b5d2e98c9085909eafe01d69e668c983a2af0d93292543b77f9f5eadff58fe0ec594525ed9003789c0fe05	1613585671000000	1614190471000000	1677262471000000	1771870471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f6ffa86492bafeec2bc9a23ced1d78907c3cea20b6bf582df1ecad219c66365d6b3e15ae99f216c6dea6a0e59fb4167f02fbc0544b500ee74a7afe7e0e0673a	\\x00800003c9d2f738ed72975056a72bf09a44447d73e9a2bd3a8a34a827b59c0cef68ee044bf3247541d9ac115dd3245ba6fe56edddda5d62704b2de3be1b2ec0d9d35c83c738a4c851994339d4bca585c185855c567bcd002c2d9143644f805175663e4ac5b297fa6ece7ed6245df8c49a6b4a9746d49cbcfdc95d0d0c70350b2415fd21010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4ed440cf289178a5d82644117e20a06098c180c3094c1117a2962f9ea005531d1b680582a3087979489fc4e771bfc13542e79b23efca444bb02d3546b635e402	1613585671000000	1614190471000000	1677262471000000	1771870471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa2277a5cdb65ad57cd2c677b16911279f957c67be8ea541b93d3d16263f8caea41bb3572aa44c781aec252643835ecefb899fb99a817c8fdf2cb4ef5acc5ede7	\\x00800003d2e5316d49acf01ba4e7d553e706cd06a74aeb489d90e595be8f6e334b403e2c0fa657fc62c4479638c2d92f8f468a7c22b87fd57d33878a32202d706b0356804a58e76da27b6652820de7bfeabaa4ba4a39935a97a4373464ebe76d91b25a803779e2dc0d000fd7e7131453853e6756fc3b8a21c45f98b2daf5f8c83303b017010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x72c417f630629ac3418983c89e5e77605de10052fcdaf74ac97f0efe91b3ab1fa7a38658335420d9d608303efef0d835e2c7c5a1088dbcce860fbe6b56e9a60e	1621444171000000	1622048971000000	1685120971000000	1779728971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa25be61fd846611cbc2b5952962563db57c9c9d75c677c81664261213882277459fda954bd21fde98006a0adcf979997df66058a84cb3e1e6087aebaed4dc92d	\\x00800003c9f8e052a80968ddfc09488d1b5b38f03b53872537be732d5b7b620943e7ef94135e16544a97cf8ffa1d0a5ec4db2eee4381a235f8d7e6032aca39e79a62d7df4a066d7c163b90974894f3e9a26aad7176514df738d406e0542d2786e814701c29d3459ee01c14dd28f1b386ebda7f5663dc017591753b0d5710c09f0e10da7d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x591699deb2ff817947295a165eb8e3f63529697e164ef36224a601b084afd35d8ef1ca91cd7b0e630faf281ce71420990b3e9770975603dc718d725e7598c705	1608145171000000	1608749971000000	1671821971000000	1766429971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3cb5146ebb57460861f8e88dc4a2ee40d61855facc521243e08283d5c39011837a54690e7cdc710d3a6f6d3657511c958102cf8accd44401bfd8a6b282e61f8	\\x00800003b7fc36b6600561cfd633052019bd91c93a0f80cf33f0ab1d8a6a2dc06655f65f600469ce0f9e24c8f5106acc20de9701572c7b4454e2617b12902e565e9371ab09114a700b32aead1203822d8c53090cef7cc536a263468881a61dba0d6f4dbdf8041061d8e6ee4196678cdb86c05ecc57f865ea4f0122c3f1a1b5f500c88063010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x4e96ce9ce8dfc4226a8aef1dd02b1553059ab4c6576708d5043cd32fd7db455eaf9370214a5deaf964ca88f44b25da4ef0391b16bb4fe68c7a7b1e88c593de0a	1620839671000000	1621444471000000	1684516471000000	1779124471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa5571173e7283c3f12449f222d7c5e1ed99d9093f5ec64660b95057872037e89729060218ba9e64e293ac762b4c3da337a462899675e074f8f9af4c733ae4a4c	\\x00800003b19810a99b37cd411ef9389d60cb7ea0982f79a2f7ea4eb0f485a8d7c80e1cee253c68a780433e37f526f97ee5a20299001b785fdb9dd7a8a159b0e8496325e1fafa7ac9bf8e550366f4afd83fe7bd7959963d25ef94bc50ab771ee6182b886895b830b629c4084052219ad68310e4bb03ba41106b9c51990d6b9a9f3d678087010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x05b911487f65a61bbfd3f9a867b0f140150e0669f716b10495e8781bf488966cf4a143126769bdd9d9dc8fc97d824af3727a257ca9a5ccf4eb4b236669ac950b	1639579171000000	1640183971000000	1703255971000000	1797863971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa7536731db09eee1c008b24b2236cac3d609ed4337444d5bb57864151092570a9056afd83e03198048298928aa8e3b0db71c3c08383335180d6100d2db05b10e	\\x00800003f04760bb5006281339f7b798d48943f1ae21846e489c89c40c747733cd03b215855d78880544aa6dffc1fdbb38576a8780c601a784359c8e16d5ed3afd0d70d7c977106269ec2f53db85a994a142ec251404529e5db65295c0ed29e9d8c92cb5249ea0fa4c1bd41c255588d89c7b20cdb5b304c1b043725714980e4a30c3574f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd733090912f5ed92582f70f29d512809b3fa4d7b4b598e8f1781c773b8c5c5b69dfc70d566e4aaecc72a6f84796d4e19d43326fd1acbad4ef94e8ea9cda51f07	1620839671000000	1621444471000000	1684516471000000	1779124471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa86720157cb8a2a60907d4e550bf3f8db561241bc7bfcec81d3def0e5eabc2dfe26743b85901eec73d2a9bb7507c98f6ded06fe73edabdb1dece65c75a638b25	\\x00800003cda7f93744c0c50a2fef2b63614180ee4e56227243c88f22d5c6a58ca08935c72ef0a84ac27af667da23b162506807923aa6c618d2c0a7d91c8327803e6c0dadadb64163bc576e04f01a23aa90c4219edc38261431eaf29c3f389c3d52f9d445a23db75df2c90ddfb05b5982150b70a2f50316ab45f11ffbcdc8c670ed282b49010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8e0f2987dd606aa0d66b25f28a2a1a946fff8b612953f138e438e00c779c6ad5c6ef53e648bec57a883d4fdf771a96e04c9a1270eb5a5a19c9d763275994a506	1609354171000000	1609958971000000	1673030971000000	1767638971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab2f3c3cd48cfd00910411f3da65064fabf8ea33c6fd3ac4a13b148e9b459f566c03251f07e86a56297aeee2398d46e379120b43fc7455f434fda9815305e67d	\\x00800003e5a4ac39cd8c1d0622b9fc6b549fcfe08c0019d1be641c10ed0c8a8462d0d929f3b054e6d5f0f93ff3017a8300ac88d6b590b52167e346da22eb6f889e926d784da165ba76941826e7d29b42262f1da4482aaaa58cd15ba6a014197d7f09077c365e958496f5dd4609a7854118eaf0a8a2da4d2af5b4ef94dcba243058e1288b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd8996c18bca73f29a9a6521d3e0a7e628f6bff9f0d2b5b6d3bec475b6115679be7d0e5ab0b445eee6c7abe29bf53a07e4ef1a7012583f229ab6a46e3b660ae07	1623257671000000	1623862471000000	1686934471000000	1781542471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xac23b0f9ee66cff25236824982f68aff267a10278c6404acdcadd206fe41610178d8fdd4cd29df908fb57ba3a16f3e0b2cc6651cdbecf61f1ebbc941a92b3a46	\\x00800003d8d3440ebbe343ff42f2ae67c2dfec6b023c37626472542495704279b0c02796d8a83cbaf8c39123e98869cd1c85343022a72a94420dc70ba26d232dac8015f06801823f8b6210bf301596232514b74b282e9978a05ebdaf7ea3d6bf8aab43c202c5ce7fb81e86654af91a5dc582b7f9f281de41991d271c4aaea876e759e9eb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5f301198122e32feb98c9d837852922020e9551ba481dd945c9bdf061174b20cc6c68088adf9585dbf0bae141928ebef0f85933126f6c6203a4909add7d01b00	1625071171000000	1625675971000000	1688747971000000	1783355971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xac1f6733ca9262f191982256ca7fba2855d40d1af2c9283f0060ad26149f8248904415874592245a1dc6b59d2988cb6b1657abfe98ba7e7667af922cf6b8edc6	\\x00800003b34f3c0f8cbff40cffe0b84d46d4e947fbc41e869b5826988b98a919a2a67f812c05fc01304b13b051bb2f2ccd68be521cdd755ccfe7cd66a477557bd079c71b769627e05d7bcfe2bef1bf805fa9934f4d15c1532a44798d525f5425fffca0cd330dec12aa7e5f0c4677fc657b6755b0e5209cbe7263e1a9bbb49b0c5af51c53010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xe1fabf482cf055d4e84c79de8ee83edbf9d71b0b3bd0fa15e619c22f17416041b0120d83908f64fff01439124c98623f640bf07fe5892328ac8b8e41c2578803	1630511671000000	1631116471000000	1694188471000000	1788796471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xadcfcbd89c2b759c02d9d9510a3915bece90d7a76f0c1afc6f73f0c342861de2f2c083b725454f0108dd8680b1b9d4af5319b9a87a52971be696e7de8bf6927d	\\x00800003bfff0fc2c289d47b1278ecc527a20b5c0741ec6f6fa38a06eefb426034f08b3bd9070df8f4500fb0b5153e7ee40640aab83ccc701e72fbe19226b1177030f2914564ce095f5fc1aa783ed6f003608aac0b38c9d025030038ca824cd6959438ba7cfebe2bd742a0ddd00ccf83bc0adc1409c79a7305da68e85128b2794cdadf35010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa83a09298880c9d8b12a5452bc6673b928edf21b93cf0ad3c794c6818dd7c48882b515c02113ce6dbdeebd1bba6f9549a8e7f230bc5e1a72befa0779427d9a01	1622048671000000	1622653471000000	1685725471000000	1780333471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf93731378ee1208f6987997337fb58d29c10db6e7c85a24e0d8cab96a52340244ce1a888422ed526cf40508d49e7b80b7ec363fde0395fb0f0f6418e2495f12	\\x00800003efc58681858e0a378c4a891c907474da185df82ef762e13eb367fc691b0a7562901d2d9cd304f469135b9c748377b8648a5a9efe17743192c2c7b2888c7cfb6ff6fc95dd47962a00c25507d80b65ca4a9a3c030b9bce8bbfac26557e61a817bbafad0c54f041269c36734140c40e0bb0eedc747dc0f3f0f9987c46c11054ed11010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3d10ff43e6ed5cc7ed2df5141d633656ef298f684f785cf21175a5c5d6ddb76b0756b1d4381fc66142eb6e997eeb92e61f9b83d8987ce1c06494d04b502a4103	1617817171000000	1618421971000000	1681493971000000	1776101971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1377dc06135ebb2fd0d77e2c03d2535edb1dfb8bd27289b13166128b6e28b080bfc86e9727b7b5b5ab8407b0ad4447ffe20dee0251ed0432d4b28ee30ead474	\\x00800003b9692e6463582fb34cd850acd158a1f49bf7a5861bf76cc7780e745cffc06d3e05ba06480850d1ace464039b2421901152fc18f594854d96216bfa051ce464941e30d673e235ee296943fb5c29ed6a6862ef36430ab3e2c32061ef433c6efc850b9cdb8a6898203801140824de77680cc2d2a08499a00c917e3d38020fdc8043010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x29174627163d4eeeb475880f4181bfc526a30ba3809a708c2fc7dffa276282109ca63f2933c938f8161f3822792f000d5121981612b51b19548bf077b82d510f	1623862171000000	1624466971000000	1687538971000000	1782146971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb953a3abd58efc8e73829d65560ebafda26433d5141f5e4524b086ec6f14fef4216ea0816a7ed5caf620aaadd029e6f30c42fb3539811b8490a4dce07e5355f3	\\x00800003d1238af53c94edf294197baa23074721d7f3f7ee06f4d45c57159498a0cd42cbc723776e5c36b639f8e851f96cde339288bf60345e99b60bb2a7d046690d9e947891535bb876916957c467644381e1c4149783edf2781be46fbf22f1deba60996057968b55156c5e902d833b1284e9eccf046df23518c475237c16724e8544dd010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa27ba80d99ad9f6340a9aa832aeca2fc071771dae2746e9d8867e4885c9e2349c3ceac9ae25eb9364cf58fd31b0db3e14a42200bb8caed8896c411fcdc4d360c	1630511671000000	1631116471000000	1694188471000000	1788796471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbaa33c73bdabb7d81ce2fef69029516a4f6eb3ace3427e604bd38de01af79e29af33b3b4cd06479b0f67db41baa572f54213990857e7102e57b0eaf59de390f2	\\x00800003da0eb747aae895d9218423d3377ee9baa6eb293f55fe96e0076e5538909357dbe282434e9ce65bd7d44f0a4eaa2f285d2f544f7e30a1c7a34dc1cc1104ab44e89053a4be50d7b4179ea4017b19b06e17a4ee7a2c17700b459e6bd273764f15a1556333587e05850ccd2ff3298b1026993cb55107f19b355aaaffda733ef5272f010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x350751a4cd784d55d847ce6d842788ce8327f0e75fb0db0c180e30d6ec1d08d36ba2b11da6ce3efd4186a1d094b62361e9a19af60e5fa7f3dee643d8fc4d870b	1623862171000000	1624466971000000	1687538971000000	1782146971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xba1788816f6f360a7b3239bb3de287bf23ceda245a69c6f37b9b2d97755b39b6449e59e296522a75f7f095bce46268d4fc3b48a437f7a838ae01ce23127dfb1f	\\x00800003f3d67d72ae830901e05465a889f263e272f4b8dedf282ab008422cc2dae83644db57f8a8ceaaa63f176838ada541aec6db95bda72b241f4b9cce36a3500761518d51c53c66d829e02ffe235990307d8e249ace84a9799149ee2f574d88c7e7f1b974f5017873b3b6d2f9a8c388f526fbc4d106582f77498fa1246e5ad8795be1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x8c899f21166fc8bf9def366bae9d721f56eeb0c7fa5b6678763adf1f7794428cf392843debac9e31bda94babb6a5caeee6a4648d633e6f33a0b727281879600f	1623862171000000	1624466971000000	1687538971000000	1782146971000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbcd74c66b9f2f2ad5e4445f05bc815642772b23c40deaa163527e37ab36f0518b1dcfdde66f7eb00830d2000a149d0af2f2276a07c8a8c8c6e3da23d0e5d6c31	\\x00800003daed343acd4cd6bda37bc052e8eb0b5ed52b5e062184fedd136a93f88d504300f48ece71cfb93cf0bca9315a79ed01b1657d53bee5274668a8edff79cb3cddf1d392a47a8a663372936a1cb780626a55140dec3be779305cdd914c6b7b0ebdcf47788ed179d425d3e4c5a79610554d29790a3e35b5dabc4f248d70eeafa94495010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x7d0b772427f7908d4814089d29270caab9858ddc4afeadecfaf5947fad2fde774f13b37490b030721cb393fdc4ceae84274ad02348864408f21077cf03d6f50f	1635952171000000	1636556971000000	1699628971000000	1794236971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbdafbb86a878752ff51ead82538bcb694d586f0f3f48cb51248ed3d6833c423741d1a33ce507a954874d97c166eccacb0daf7ef945732213326ea04a0bec5cd3	\\x008000039bb215b8c5411e79cc1d59cb0dc2bcf46c43c88cf77dd3c3d4338b2611ea98b3d1b36e5cf592902422527f66ce165e2c6a97462d61bcb7897ba969562e731599e16a3457a2ac1469dfad7c9345e36558190973c72f7257138633e015dc013291e97d11fca198c06bcdae189dff3ed515e6c14d1ac0a2aae81552de4435e62a53010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x356f815552617cac67b805bc2d97e972ffedb9381255ca9fc249ed3c58065f74affb53dbf9a04c0608f58048e403ee4af19a5617e96a2ac5cedb930892b6ed01	1617817171000000	1618421971000000	1681493971000000	1776101971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0d7a09a506244b2387354e247d8bd01cbbbf6b92432cff873b715b5c2b4a965650641657ae78ec50edf8a91f4227c7d5171f6425316ce09d4b7aa2f690614d1	\\x00800003a8d7f8bde22154029ee1f900374c5296bab3bf942ebb7c31dc0d12da97c1d204487b41b1251244595006ddf17d8bfd013c9f910e266dea3cc9f89c59dc9100686197008d07573483c20c8fd0c7da5e1da79f643206813990cbb67c9d288184a076cf18979066c193bfea5460cebb8e218486804912399d5ba4a64912a5532e13010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x004af4a0d19a635bddc60662cfbed948b9298359e5e949354d11e4d4f471682d7917079a9d0c532138d260434b91cff47e7e3953c7a937ebcc5f5f8a27b81302	1622048671000000	1622653471000000	1685725471000000	1780333471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1575917e984284ecb3e295b1303950df742a40377dbad4d4cd25d291b79a01ec8dfb15dc3ca24f6821d5b1b0c3a62fb744abbd8f1e8717a5c2cea78c0d10771	\\x00800003d03fafab645d8e4895f546991699e10bbfee8849a7b7724aacbbe9287a880db6cad558a2eb1df9039e2176a234ea4179bfbfa931cac8430c97407e7a3e29bef14950af22b8f06251f969d27285ac678399075bb59ef967a8ffa27b6105db189c565d544f796c6300a3d85e4e376aa0eb626b8f72f9076281376a9cdab7d4ea3b010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x406f2b14e4f78587e40aa7a565d37a737c2aed1577368a1dd274d8cdcd19e68e638d2811bd436475cc8c8ca3ec0bf80e7d87ead4d8331985e045f0c9ad01b901	1629907171000000	1630511971000000	1693583971000000	1788191971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc4ff1cdab84a7ad731f3f280c21b649f8b5773014447c8e3f612aa3648320a44be49bdaefa1b40f22a4f64dcfcf94344fd631699011c76afd89c0d3f220debad	\\x00800003ba7a32538b37425dd4b40a273a8ef311a78c7d213278b2f5f83abea1b0e53f390466c23ffa4b33ac87f3cdffd10362ee619c08d5b1d272fbb73861c81264fa357ae2c8ab24c4398a7b9356be3be833d425bce017883ecd1736db63dae2d75b96be6ec6ba8d03f595f4b4da7a52dbc978d6468da8dd53dac5414009c5a1974339010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x6f5248082b6749a70451c9f0753e8b77a9d04f779138cb6e9971d1fb9be26507f65c9c909a4e7a2f914cbd0141fc6e2a91bdc608da4fe8282893acfe7213d40b	1614190171000000	1614794971000000	1677866971000000	1772474971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc41f3034bd26ec6c56ff88a41e8feae14ea88dc6f950dcf720b5c08b66d24bda0d2dab6e24e2013d451f885b45e903fabb2b922f8a95796ee5c3d062314a0a56	\\x00800003c3ca7187c7f737752a4a2fe2516cb6b1f8cffb6a741413500738fd848ba7a5965b1fc574d4db07a26f6887c9a8cc0b5d992659943b79e6f09a57bd84c2d6185896602b8fe588afc5fda3a688554572042db1bfd223528787083cbcb7beaccc48e043d5eac5c52a9014acaf03ed19f2dac607ccee5e6f9b52203d63b48353bad3010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xefc882b1e537f4814088d99db041f23f21d6cd8c9526759f588813548e2da5f6f94d58f38d6d8fc54f4c1cd4c73956cd520a70f77fb6c5a55960400cde75eb01	1632929671000000	1633534471000000	1696606471000000	1791214471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc56bd21bf0ce34d83cb73d39b6f2a2d975955f83168052d2e5bcb738cb079d6286b9463e211a37877d66328d2fe754245c483da6e7c0b9ff3d0c341a7b076ab5	\\x00800003c46cf3785d257b552b2b9029496f3ebcc3ca58e7c46951d6bc10e3d1b0feeea23f64f58e9fa24498cdc604d11771377deff728b0d5c472b79c11229c65644da426b088ec5fa61de24309c1ac5b22e9bc38b9ba985d107be63009e5a32ac9aabb9d42fdcb6dfda1a98da176df8e26167bc66100ba4ef845d406cc65a8b1e94859010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x59cd453a378aa5913f845b1298cc892b843f4a84aa1e15576806191152fb27b1562f908fd00d7319457c5021582162fd3242ff31a3995695514cd5eb359c2b0a	1633534171000000	1634138971000000	1697210971000000	1791818971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc61358b7aeaba3f4a30f69839c5589b7bb75e72aa19e31f3be35b9eb1ca3429162b8fd188855fa9341ceb49209a3b12ba3d8e530a902b040656d77040d7e0c3a	\\x00800003c4b61c5d857676c51d92701292614647ec45b6ba3fe23c677bc9ffd92ac9575f6b0a5e0f91234970acf427d3917e6274a63959294e3174d203171a99e90ad966997184c37e9af0eb9714d46b33fc8b25b2f54d489e7cd1b8f2001d0dbd2a5a850f8736bea344996a66f4cfdfbce5f21ec38030c0d30245627b6ad2f39c942f43010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x2f457da784c98dbc7b7d9e1d729370e40a54b8f6c0dde61e2f79d1b39c59cae39a414ffb91091127ece9789ddc427864dcb3c5c9d0a4db14d5ee3c5c291db600	1626884671000000	1627489471000000	1690561471000000	1785169471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc753e2e07dea1ace95d68397c8099188fd91bd26a21b244e5c7f8c44fcfafdb63e73a31f6b01d791f0a8efc3beb4dc55ba6a5e628a7b30d0135c0b3a64bd5dea	\\x00800003db8cdfa7fe4320382d90755aef6bb05aece268c63de155a7f310c1706b62d33c7fe21c823da222bc0fa4b53322095d04cf1267c882e75616c4cf2e44d01187133ad86122364a60d3063539b14e87ea151f4a854db186c4cc2a8e1ad8f84028f03a4704535f5bbdc0d6463655b8e30d7a8bdc9266059323d657c18f6f1054f787010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa84e76fc002540dc6019ecd188ec6aecb6f94718fcac31065a6375c53b1f44dad629d2eb18c4475f6f7d8930c07bee83bf8fce623d29c0d7214717fd60caa00b	1610563171000000	1611167971000000	1674239971000000	1768847971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7dbc00773567e89fcf444fca323633808684deabe57f51b5fa476cf8be35f87a38d23a2db6a77aeae85224b29945a65f98a52750860aa6cd9afa4d682251e66	\\x00800003bbf48bf9344af6aa8c488cacae0b00341352d89256476bd2b37edf6261defacfe846d51d1df33f214dcafd4694defd3ff5667f6ffe1f0b4b2d8e9ccdff27b0e2125e1773b07609f412086db9007c95e432a082d16ab85f3e30c45e01e3ee9a7f15426455aa37b1472bddb537a5de8384aefa0d30a9a4bc6b2a11fcd9ecc27263010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xafbc02348ed9501b515bfa4849b8c57f9c9dfc1f25384ae10e334525738cf99069a7d429a0596cb9c354c7779717bc2146b50a9a5f2f7af6beacb8c3e4c7de00	1619630671000000	1620235471000000	1683307471000000	1777915471000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xceafa4ac4a00fae722bd0673c6e66c0a2cffe2846956ab275827d1a1c2c81cb4ac73aa758ba64d40c5496c8b5f88ba684fb118edb26f2bc1292c48174d361970	\\x00800003a37ea4fdf74f1722d36c04e87b4ec627a980aa60f81846d61477990cf9d9a1d68a80c8ab4babeb8c090de7d28b59082d3aa2981f0a2862a7b248d9ef6e03bfce6c4ac946ba47201264f2af053fc58192437d4e4cad8f8262ea435ecd2ae59c1c718daab72517b9b1d00debcadb98f3c1a02e0da3d536449f91407b38b02b29c7010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd7eb9da75b9cb90b0b26b94e86a8ca79b173de2de4f6ce1cff95d246314966e093852343571b7d6053b61381d13e6738a44e09f2cbbd9d5ec469f1d7909ae503	1626280171000000	1626884971000000	1689956971000000	1784564971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd1335cda5df66c25efaa12b1b65d06a65a4ade8ad9ca79080a92cd77932c485ff118fa134c94afdcbcce3862dcffc62c7b4e1c57a1ffbb6ad07a75f634025534	\\x00800003982b1b6067be204945d8269dffc23f7bdea6f5310811c13c2311ef06908a9572a199ff103fce8cea0601a59806efa077b86bc75825cdb319a9d0adbec9f20330726222d43be30c9f148fc9566ce17f4ae58abe8b1aebe90815b731e3a92e647cede1cd5e98632808ec31d51c39b58cd1332c0adebfa8437fe75c9949a18b4e97010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x645fde6c41c6be1d77c555d8870d92d8a0e8521100d5db40d8f8038577cf4ae61b3b7f3b4ae1b67e4f3375bce6bda19c2142ae3681387dd680a73979dfa6040c	1618421671000000	1619026471000000	1682098471000000	1776706471000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd3072ef2dcceeb56a5b86345543f422c53bffedbff4d8feccf3ae533b29041e31c3a663cabbdd4c2a5b0cfa0fc9f545e79d598e40fd4e09537d80c9dc5c40edc	\\x00800003b492698a5fd5475c253864315812163e716843ec7a76fe79b27fa3d9d75f3af31380ea47b1df7db53f132793a23f8dfdfb7fc7fc17499b7cdf893ac006b92651ff5879bc96be9528658da2d12bcdbc30204f0a1e9bcc8a54836f34e784d6a3ad1654db6bdf41158707ccee4e64640719311142ba8ffae47dc3ec68bf4827f9c1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x43afe0f8f766d3ea20aab225135ebd0bf895a2aace7dd83b97817abe344e9b376b0257a12e7203cc13c1764d35249b481bc0ff5018e5aa3a6f70e49c5adaa707	1637765671000000	1638370471000000	1701442471000000	1796050471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd4974910754873e720cc5bbe7db79fde8dcd42651d47324f8b8b3453a5526af9a60596f744b2cfa17ff47e37e938e7f08ca244afa4f76e647902c9a7d648f961	\\x00800003bb592892bd8eefa751079a840c7d8b9e7e4f59146a616d46b727e04a3e74a9d7ed97ce078317d851a558acfa036d22dfdf4705f99be0e9e6a0fa2eb5ce95a3665d2fa4a412afcec6da4b20009006e378216ab2075e4b2dc43d5d6eea4fa072a2258624fe8fa6002be3438bbfb28f2eabc99480031d98522d4fa71b9ce7d2a62d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x5144e24386e97ee84764297048d50cb7a26c5ca4de235f46df291e087bc2943958bfc112da68fb1e153403f2a365dea6fe79ffc2cd76a084e8fd9f1e19a0f10e	1623862171000000	1624466971000000	1687538971000000	1782146971000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6bb4d9c7facb04ac8270084d068ce79c31df918726ce90fbf63d97f7108868a0a5cddb10deb303d6ea552db0655beac7c589ffd7ebb11e631fb125abf0c1829	\\x00800003c31daede1bb38c897dab960461572b048d2c0de7193ba9d7452cc3c8189d5bc285e0dda13307f9c59cb07732ea559adef44f35ad322267b7c3faaaff3969d736bd3a37347c99e8f3bb884fd5a33ba0ddc3f633613b603c8f545bbc88a8c01a3cf8bbdf1e2e06ee14940b69f666bf0f8bcd5f061514db14dc6a25cc469e423eff010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x598b1c4a3c6396e97e11ac1581b03997cb1b7a0d365c7e36a416f3e54d08d439a5cc459446f44ad91d99180a69df193eebd6c22d5060dba6dd046a274117ad05	1638370171000000	1638974971000000	1702046971000000	1796654971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xddc3f525db5404763caee9987b5e21c92714049d013e54fa223523f4a4456e0712b0762bb3cbe7b77e71bb7ce3636890361990d22b056417220919374f49e08b	\\x00800003aa42b239dcfd61bf12c7d8263573ab90083bab95fddfc4c113e87ca44ff87bb536fc739a47e06588b2d53385f5d509283ed9784ad7f84ff94c6392793c8362cf701ba67b7f17b50c3163a4532c358de20824c2d14ef94e28baad3fff7cd79919e3ee1692341a42b6606d3e29aa0c78354ae6946224141ca690a098ae1fb3fa7d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xb63e558048fd050fafc03497819650a67320494c1637f2f50004b9169e3e13c3f1b93ab036427bae56810d273664d71e25ed17d8c008a662cb913a5bf461980e	1624466671000000	1625071471000000	1688143471000000	1782751471000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe27be935a78edb160db8cb1cc359bcbfc7b515fe074e12d7071b617ccb62715c956eccdc2f85a07d351c0e1c436d229d9d1b773b4e492d397124672174639b23	\\x00800003e06d90a652564adf576187ab734c20ce3f855c880634d04064703e38f07996a05985855caa2faca7343d2c670b6c04e06599fa42a6d3eb0033443fe60b6ee23f47f12dc69821a9613ab2ff280b8cbdb947064145787613b0fac8b49718fce9ad62e8b4eb966b50f5fb6db2be94b9c696ed2e3ca9b6195f6449c67cf63e6d2dbb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x410af22f1e5e6316fb3b60f702e0fe5fe8df3f49fe2346b0fcbacebb7857be24eddf4631145ae805af1634907e7c0fc12dfa7f96cc508a8081026b41ddc3a10f	1631116171000000	1631720971000000	1694792971000000	1789400971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe53f72e05ccf6a453c7ddfff341ea29477c306bed2accfcd3f22c9e45b29fdb9a6282d2255d987d3fed27760c4b78b6dc12479aaaefd451bb81be2e8f4b865ff	\\x00800003a61d1b7db9c4a68a36ba3b95de18a23487f8c7c6ffd0f1418dd3c6d3cd159104406b3a04c19525db79f2e5380fe70e9a7aa93355a1850e80195f31bd718a66412a735641aabe2b99b1823fb0783ce168001aabaa75744631245d4746665c894e5ce1cfcf736c5405884354053156f988d4eae51496e8b2d94b557615cb9f5225010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x56c8aa843d94d28005da206983ade49c5a5fe1413b6dbc65a86b7213f24db08bdaf8be7448def4ec0b2a125b4ed80d42f0a06c0f1b0a8047ae3668899d55d009	1614190171000000	1614794971000000	1677866971000000	1772474971000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7cb242d9bb92a84317edc187c98972a50788086ec2623a58935abdd63564986a26418752fe2f7785eb1bf408442d4c94cd122b88c3bfc85a482df4f5d4b1d61	\\x00800003e298857836940acd07a24cad2b8666a7d5c2903e400ea7183ff5de4d34c7c8f5b8659727d1abea6c86b6b707b8de72454928488bda056b97a324f49f43650a6de90eae8a97b45ce2e7c5e6ec5580b01e67d9ec26ad6e7758bc8e08662901e75f3b3536599d57253b75e93e50855da346f335edbf1f7711a1dd43323503023e91010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xd43c35579cab90af3adf35a974a8f897c7c243572ee5ff046931abe2e1577b3c2a7336db3b2b8422f5f64620d4563b0862d4fc7b1fe80d260f0429080cb6b40b	1639579171000000	1640183971000000	1703255971000000	1797863971000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xecf77b5a9c420439c2696c574792a5dbd027ef2e6be23a15575778d21ff23790e49c9421e784721cc04e8866484ff7c0ae50b98275729248c61c7c6483e25b0b	\\x00800003bb4c67d72ac2ca50fbd70d2831b1d50d13371d5926cff997d79268b394ada82d3ec1929acbfd075ae2c20db09877cc6ee6da897ecbd69f4675e64d52bfdf9d4c67bb71ce8a1e04f00d5c069d5c2e1304b1dcc9a75c5a0f78cb482fe2ab8f9f05dcc57603c5d5b6f77afd9cf091dd2f2f817accabad203283efe84a768dbf5bf1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa20aa1a183575896d2561c4138a2e0c51da102704ae37e404e104404fd729c9a0a41c9e9b0b63aa90d3f7da9bd437341f45243bd0e5570887932f9b03886700a	1625675671000000	1626280471000000	1689352471000000	1783960471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeeaf4ca758ddbb096331ddeb0ca3a90486dae8d562b80370777a21e0a9418aba15eea103c06f7aad033e1b838dfc042d3872ccc3f161303e2ac6f9c24723d7d2	\\x00800003c001d4d0ba42b0aaa69399817eb51e254a69239bbdeb334375c0533d6030a953154e788651fc5c9b65d87233138c01c5cea22fa9d5e700295a1d8c95ed208705e6cc7b26a3444667dc5860ef689b20a950762942d9b0c5a9745387352c96e66bd94e62ffad98a6858f726b8aa99eb835280e5310a46f77719749b89505c558b9010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x686c90b77b596ea4e2b02b1aceee1b85a91181ac806434c4be6ef8b866889ab621f5501f8cd994a7abce23d1455bb282101a43410bf36b8ab09ac0353b628602	1616608171000000	1617212971000000	1680284971000000	1774892971000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xee5b11c5543957de9dbfcd7a030402a8f9d4d48d58b8c9825012aacf9e740b393a0bd74efdf70bbec6f9978f837840abef7bb88fb8ae2768d43c404d654e4b31	\\x00800003d360d148f84d385219d4bbd9107ac80bef50bb7dd3cd15f3176ec2a394282e9946f641d67ab5a573495ac1a08f8cb8e663d883b6a0ba25cf57f736c62ddb6f0a83ee78c5c25040b3f5c94d594c787d007d4d93818bf2ba9e6d2b630facabf9752957cce55dfb96c05c1f3639f4788866d874d9239ad3a5360a66d2884d6b9bfb010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xdb127fb24dabc9b6e06be1b2832812594093260006e5ea7537c380b882fb3d8f75d53233c23a501115098ef3c501b7bffae6c74579a4e5f917d96b3052186201	1618421671000000	1619026471000000	1682098471000000	1776706471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0b334081f0945353689882dd29ce995fa011e6dad86e18b8b1d04187320a6e2c000299b3b1dca001cf3a0aca49c969e792789c88e3caf18b21d831cb738739d	\\x00800003bc9010329315351417b4512f8ffa0bd6891ca1d3e8652c8c92142c813db5e232bfa45798488ddaf6360d73b2dafbb9fc2e453bb9cd44b794ff56332a0e03d9037ed5cdbbea52b7d88e25f43121cd684bfca775e3af1ea442db2b3bd423f9c9453bd1737bf7442d445eef041cb668bdca7b4abbf06d55272db46fe5d128ac3327010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x33c70c31dbede8d92b61d98c4fc5e8f06bf0039bedd81f8c41a01514992431fa1e51076a190c69e6d21246ca58492cc64135280a04aab71bffe3457cc4f97f09	1619630671000000	1620235471000000	1683307471000000	1777915471000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf123a0b71791960aa886efd95e97124073ea2e5f4d15f76014f5a21a91551eac4d0de12ef18f93d3e7c1b5f8b747849683c80a028600c1cabce8e10c4cc42a83	\\x00800003c91f01510f4f4e12a3ac049a3c772c54ca2dfbe58a407cd1032bfa6e3ae91ffc156f791cd23400e94e48b3db5db365a523865b87a17af9f359c660bec2155c19e36b261922c171f21b360679c619fa11029fe987a2cd3f6f946ecfd72ef257897e9f76c7bade3e1c27ad495f32f16f12cd4e927fd3f4712602f7710368e1477d010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xa66e2cacbca1f90d32a23f0a3cc1ec0bd927cfd499c14a5f2bc63620c0b786345bd8255425e32a3f3751c4a16b59457016e917d63ed279fa3ab4b80096559d04	1617212671000000	1617817471000000	1680889471000000	1775497471000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf8cf1434f692248a88b2f6efeb33c673cc01ba04ef5446a4b5755be85dba2dfc514d01bee35b681dcbdf033a0ffec6e32ba7610b9d601e3805518b4aa429e410	\\x00800003c6b9a1086357d96f56837d4b29ad40d1ee2bc2bfc0e544868346a35db0e9e02e5a13eff7f96dbb8c76cca0af6fe16db4e251fd5068218a5e6cf4b2dcac4e8c50dcdbf0df12a466d3dce0a0ae296c8c4ad802ffcaf8ebf9d92940e56bab371a617518e6c121d3295842562602fb6eca6678e5c358904013c7a3b179d016c02685010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x34b6f21f1a8e806547bb9a1c94ed5c467c60cb04307dabefdf2c4c7a53d8ef8f31c11952f60e356379f44bb78f1f0d54402549b3397cde67e9b8b12ff3d91801	1628093671000000	1628698471000000	1691770471000000	1786378471000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc975ea856f7dd3a72cf5e699ce16d2bfe5a4fb3d073bb02168cd572cae329586cc439dce42e6666f6f85c70778b4681ae0c15f8bee29140d158c3cf60660ca3	\\x00800003de414af358f1b537aa8d8f9ea5a139e1686dce512774ef121433934feecbe107d00d730c1283ad5d828995fb45be8a77bd8954dc029ac7c3e65a018db98a86f7d954fa8a76417aa8ce1de07d87fa63f543711cbbee83fbe2bb3670f9803e1e9fc98a7cb1ad6b2102d38d4f4d514481a7cd4f6cf7db95876fb9e28bc5fb5aaef1010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x641205cd13ce3bf531623b8372e3afe4ce1e0c09aec41cd7c4e900ca6a1a9905801cdf2978a2bfc79b575baba2a09e2ea0b21c1b85ac81910e059ba44cfeef03	1609958671000000	1610563471000000	1673635471000000	1768243471000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfecb4b47acb541dfdf525d99210f18e360f4539443547b596b67f63c76384622296138c662fbf2e18fccae7b60c1dacb71b5ee2d7676e2cdc4b398bb868cb3ff	\\x00800003da70c8cf7631defc29ad48c0651394839fe440deb79eade0a36c84ce5cdf2be27417cf51ca9f522ea0028828ec74aabef57ef599fdc0eb19e393143f3dcc03065485997b869ba17472722db291bd2e04a3ff9c0e187c25aa4ef06310194e45f30025b030a58d0495c4ce8f91d621e80a60f4626831bd4300e3a144d3289f8685010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf4f3aeea255ab530f9d5f5aa730f6baa6fc72fc44d2aa6c0a2f12ae37f15629373cc021f75b453bdab615b2ac517b9fc43a312f72ee00fb1e77f1fd949fa100b	1634743171000000	1635347971000000	1698419971000000	1793027971000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe074961c1749890c20a160d764fff655e3d38a3d3cab948750ed18d19aebac8780f5b32fcc80c21cef8adc234343050759533ae71e8164c82259a530fe34b3a	\\x0080000396b1b879148a190eafd6aa7a3a282ca0de6d46856b523ff7927e89855cd32c315123ede39cfbf5054bb768120afd7ad7c647baa0f1ec188e9fb22e261ae1276f5f71d7169617cb2003f2eb715cb1f823fd31ef5d4af3c4b30787084430fd286093fc6f8e0d34144b3b78777b258bd5daf47f045007af19c8dba34578107de151010001	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x94482339f4ad98175a51c6486001055901b58123c8cc2414ec5ecb0b8f554f8729ea95d594b0cd67199366f482cc2e3d29fb901d2a968d7ed22acfb40a1b4802	1628698171000000	1629302971000000	1692374971000000	1786982971000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	1	\\x66301e7fd91c79d80d65654535aa8bcf364cd9a611401f11df276bd85cfd843c5528394c09e78c1181d3bcd01319b2c42ad20e6135c8f011b48a8144d6b3a3d9	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	1608145186000000	1608146086000000	3	98000000	\\x792d847687758939e1e689068cb76577814996ec9f19f338077cb837a8e68f4c	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\xeaa9c608f3f8bbdaabf0ec9cbe46b956abe197f92bdcdb9943fcf83d5ce520503693ca235baa53154b4b4e0882d802be6b346d60e9f95cddff210a267a24280a	\\x3e0caefbc826be4c81a93be5adef6c9a02a06009da92abb0fb17feb6d0364591	\\x1b4dfc8501000000209fff1d727f0000032eae7ff3550000f90d0000727f00007a0d0000727f0000600d0000727f0000640d0000727f0000600b0000727f0000
\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	2	\\xb7e522428eca43a22242b38b645a07956cee50c968e5345d53142caea58aab8adb27eafaf10b8529e3ba1d664c548fa91f4ee112a9e243b74f4009b8b42e8259	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	1608145197000000	1608146097000000	6	99000000	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\x274e3ed6722eae4e05d46aa5c3b131940f1963537bef194a925df3b6db2eaab082ba3d93a3ed0b53036256ec42d56ef11512f71a73878ab8ab02ff86be616d06	\\x3e0caefbc826be4c81a93be5adef6c9a02a06009da92abb0fb17feb6d0364591	\\x1b4dfc850100000020cf7f3b727f0000032eae7ff35500003995002c727f0000ba94002c727f0000a094002c727f0000a494002c727f0000600d002c727f0000
\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	3	\\x739f5b0cd49646bba39cdea1f5b70b63255b45f6c99a4f5dbfe27b98ff58abd0fbf7455336a9a3a2a0b4830391a33e4df57d5d1205be3c8746ade1a9287bb451	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	1608145199000000	1608146098000000	2	99000000	\\xb3d2a217a2c716d676e33e4d94ca52a75bf81c8f1fce729d92c36682856c0e61	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\x5b76046c1d18c91ec7be6cdefd54f39ec159474289281a5be6778e2c0e0815de177de5d87e1a494f5d6a5b49d89cfd6846d9913c65229b90efe405f8d8228c04	\\x3e0caefbc826be4c81a93be5adef6c9a02a06009da92abb0fb17feb6d0364591	\\x1b4dfc8501000000207fff1c727f0000032eae7ff3550000f90d00f8717f00007a0d00f8717f0000600d00f8717f0000640d00f8717f0000600b00f8717f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x792d847687758939e1e689068cb76577814996ec9f19f338077cb837a8e68f4c	4	0	1608145186000000	1608145186000000	1608146086000000	1608146086000000	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\x66301e7fd91c79d80d65654535aa8bcf364cd9a611401f11df276bd85cfd843c5528394c09e78c1181d3bcd01319b2c42ad20e6135c8f011b48a8144d6b3a3d9	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	\\x9baf0af3cbe2586c0573d2768ac22c67efe3b7c0d9956fbf40a2b78e72caa0a110ba56f4abf8cfaaee75b5efa77b6f14c2be020d409383b32e8d7a0cad4da006	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"48CFJ3CW7QRC4W1A6V59GD8SBCQCY1QZ9THNK396QEVSXJDA1FQEFEWGNXY91HNMND0G12HVNWY5G6BYW06PPF1SCYF59331HXM79P8"}	f	f
2	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	7	0	1608145197000000	1608145197000000	1608146097000000	1608146097000000	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\xb7e522428eca43a22242b38b645a07956cee50c968e5345d53142caea58aab8adb27eafaf10b8529e3ba1d664c548fa91f4ee112a9e243b74f4009b8b42e8259	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	\\x9d9b9a8a45a5f110aa7aabf844ae548240a6c420c5f31894ee634c43574e1b6b22d07aba7e60857d0cab94a403bd914ccf14212e2291a65c9d30f721918e3907	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"48CFJ3CW7QRC4W1A6V59GD8SBCQCY1QZ9THNK396QEVSXJDA1FQEFEWGNXY91HNMND0G12HVNWY5G6BYW06PPF1SCYF59331HXM79P8"}	f	f
3	\\xb3d2a217a2c716d676e33e4d94ca52a75bf81c8f1fce729d92c36682856c0e61	3	0	1608145198000000	1608145199000000	1608146098000000	1608146098000000	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\x739f5b0cd49646bba39cdea1f5b70b63255b45f6c99a4f5dbfe27b98ff58abd0fbf7455336a9a3a2a0b4830391a33e4df57d5d1205be3c8746ade1a9287bb451	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	\\xbd3ac23cc66510b94b34bcb540a1879d6e89262963c25587a0bb7eebea57690b3067385c2ae90afc004cb1ac826129bc5c4c4171e479e547deb173658c198f01	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"48CFJ3CW7QRC4W1A6V59GD8SBCQCY1QZ9THNK396QEVSXJDA1FQEFEWGNXY91HNMND0G12HVNWY5G6BYW06PPF1SCYF59331HXM79P8"}	f	f
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
1	contenttypes	0001_initial	2020-12-16 19:59:31.769472+01
2	auth	0001_initial	2020-12-16 19:59:31.793987+01
3	app	0001_initial	2020-12-16 19:59:31.845559+01
4	contenttypes	0002_remove_content_type_name	2020-12-16 19:59:31.863714+01
5	auth	0002_alter_permission_name_max_length	2020-12-16 19:59:31.87049+01
6	auth	0003_alter_user_email_max_length	2020-12-16 19:59:31.877239+01
7	auth	0004_alter_user_username_opts	2020-12-16 19:59:31.882408+01
8	auth	0005_alter_user_last_login_null	2020-12-16 19:59:31.887668+01
9	auth	0006_require_contenttypes_0002	2020-12-16 19:59:31.888888+01
10	auth	0007_alter_validators_add_error_messages	2020-12-16 19:59:31.894783+01
11	auth	0008_alter_user_username_max_length	2020-12-16 19:59:31.90493+01
12	auth	0009_alter_user_last_name_max_length	2020-12-16 19:59:31.912677+01
13	auth	0010_alter_group_name_max_length	2020-12-16 19:59:31.925011+01
14	auth	0011_update_proxy_permissions	2020-12-16 19:59:31.931843+01
15	auth	0012_alter_user_first_name_max_length	2020-12-16 19:59:31.940778+01
16	sessions	0001_initial	2020-12-16 19:59:31.944406+01
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
\\x0121d1a9b74d9d2b9c5d3ff27f6e934945e5d0c05893b8fda4d1e71632444f62	\\xf43fbe4fcc683a1a838d6579497fe3e02896fdfc4e2cb567d16dde8a4fe07679d3e8b9fa7ef9f240ad5169a10638c53e9143a6f464e91b6f355e90c16e007100	1637174371000000	1644431971000000	1646851171000000
\\xc205d02f87abc5a55d87619dff7e320ddcf5b13545567a5fe4d96120ec14bb6c	\\x2d739d9027b5f69c1380a17bd4780d14ad6fb6340649c4306361f80bc67cec4b3b9836b07f79171f40ea7fd72f70a0d803affc61b24f529f488f3d404d2b9d00	1615402471000000	1622660071000000	1625079271000000
\\x32eaaf3256168810b572aeeec0119c98cffd8275a4651e736e44c544ebcd331a	\\x5576c0870fa583007f7d40696cb3502a13f92e160ed04f59da07bacee359c473fa17290d59ee5051ce9d143c2058a6842ce0a902313c4efd1cc8921e854f730f	1629917071000000	1637174671000000	1639593871000000
\\x3e0caefbc826be4c81a93be5adef6c9a02a06009da92abb0fb17feb6d0364591	\\xe045a1f5029ce53b6f7dbdb02a36c171a34c5b6101578e065320763da4ae1d9bcc9418bbe6e9066fe6c31f9f311dbd2c8146621d5bf9d1a325693afea596700b	1608145171000000	1615402771000000	1617821971000000
\\xbf6739c9f0aad725664f5d803ee981e063dcb74d7568cef0a89bc3de49f49f2c	\\x00841f755915712895730380cfe7cab0f356277e8fb9e6ab6ec6a3c55f6b83b6ff8f8fe13a2d6cd0ea1181cf254e91cf0f1f8106e15793aadc2d008aa4379001	1622659771000000	1629917371000000	1632336571000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x792d847687758939e1e689068cb76577814996ec9f19f338077cb837a8e68f4c	\\x43e7fb35133379640fb65c49f54ef0e5d29e4f095b847072fd8937fc94b9779e33550bbc6971a05c42a6457c10a5cbce104b901f2290642b570c7a5c643385f9	\\x9517042f7b0dcb7a34ce8fc915e62c8e6f19c54a564a752a836954671b41da3faec8cf42d3aa078abe5aacf4237b3ef66077c46fdcb7b790dfb005555597422e925ab54223020734ea45e638cc17d0388b895c4fa66e73ae52cc50304de04477a1552c9d380f292798e5fa706e6349614378a7b2a754ca4d0d77c01630f4a843
2	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	\\xa25be61fd846611cbc2b5952962563db57c9c9d75c677c81664261213882277459fda954bd21fde98006a0adcf979997df66058a84cb3e1e6087aebaed4dc92d	\\x9dda6ff3de51a795a656efb0e6fb5d957eb08b5492d14ddc9ace25b4a86a161cb8a7657772e6b0b0e3a273e69d0f0926cbc6552f29bab10fa06116629ef745608fbdfaa89413331becb4d3d2d03bcc92f0c94d2bc56b84f796915179a00eb7a7a019315515a4960d7dded8a7971d0e518a79792bdd5056754a8e4c4a0b8247b7
3	\\xb3d2a217a2c716d676e33e4d94ca52a75bf81c8f1fce729d92c36682856c0e61	\\xba22080ccbc4df084e536f430dfe8640be9f0214a4cb00146dd1fc50b550aba1aa174473be3d8f68e684f04c40b34577cfa00d11d2dfb6fd41a17fc66cdde445	\\x495fdbf0501a99f1c56b861e64ec77f8a7b31724fc50e35a39c7e3658818d08ceba219be296922f34ee05a9f22e889c297cf487e19d1006ba864d34a613e910e1e31697540804d748115f3de500b5b572ea252007b8d2abbda09d1be31956b015f7078859af25c52ae944d2968f6ca53a5bf7f7cd7adc46586ee877b24a49f59
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x8d771fa6d78dfbfd767d69148a65273bf9ee5f0b03db2eb3e24a001125618a551e63e798627cbb54b93a687895c9e33eaab585d12eee3d8d477a63687cb649a7	\\x2218f90d9c3df0c2702a36ca9835195b2ecf06ff4ea3598d26bbb79ec9aa0beee7bb90af7c90c6b4ab41008a3baf3c58197ee00d6b3c39679e548c618f6874d9	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.351-03E71JW6DTW6A	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383134363038363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383134363038363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22484e56485a3950514851585a54584b58443441384d53393737465759575152423046444a58435a3239383031323942314839414857525a374b3148375345544d513458364759344e5337484b58414e4e4751384a58564858484e33514d525638464a56344b3952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30334537314a57364454573641222c2274696d657374616d70223a7b22745f6d73223a313630383134353138363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383134383738363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225251454a4b353742314d4a463732434341304732354132515a4e465251314747394741415833425153355138514638464d595147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e56583953353631544543574847473558303645424b364e465641474735303844573151304b593942504232364d41394a464d30222c226e6f6e6365223a224d324546454b4a375336444139305a37573031474435375643374152344d41373157444d4d394a344e39395a454e474558594847227d	\\x66301e7fd91c79d80d65654535aa8bcf364cd9a611401f11df276bd85cfd843c5528394c09e78c1181d3bcd01319b2c42ad20e6135c8f011b48a8144d6b3a3d9	1608145186000000	1608148786000000	1608146086000000	t	f	taler://fulfillment-success/thx	
2	1	2020.351-01M8KMK4PH26J	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383134363039373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383134363039373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22484e56485a3950514851585a54584b58443441384d53393737465759575152423046444a58435a3239383031323942314839414857525a374b3148375345544d513458364759344e5337484b58414e4e4751384a58564858484e33514d525638464a56344b3952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30314d384b4d4b34504832364a222c2274696d657374616d70223a7b22745f6d73223a313630383134353139373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383134383739373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225251454a4b353742314d4a463732434341304732354132515a4e465251314747394741415833425153355138514638464d595147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e56583953353631544543574847473558303645424b364e465641474735303844573151304b593942504232364d41394a464d30222c226e6f6e6365223a22545a41313146383433364842484533474d3457485253593333354e524b35524336334d4d4b34484d464a304256424e5642464630227d	\\xb7e522428eca43a22242b38b645a07956cee50c968e5345d53142caea58aab8adb27eafaf10b8529e3ba1d664c548fa91f4ee112a9e243b74f4009b8b42e8259	1608145197000000	1608148797000000	1608146097000000	t	f	taler://fulfillment-success/thx	
3	1	2020.351-02W6W69NBEVRR	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383134363039383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383134363039383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22484e56485a3950514851585a54584b58443441384d53393737465759575152423046444a58435a3239383031323942314839414857525a374b3148375345544d513458364759344e5337484b58414e4e4751384a58564858484e33514d525638464a56344b3952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d303257365736394e4245565252222c2274696d657374616d70223a7b22745f6d73223a313630383134353139383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383134383739383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225251454a4b353742314d4a463732434341304732354132515a4e465251314747394741415833425153355138514638464d595147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e56583953353631544543574847473558303645424b364e465641474735303844573151304b593942504232364d41394a464d30222c226e6f6e6365223a224543315758395153544e50434d4a504e364e44343743314e345457454d38363759563330515a394d44454b595956384857315330227d	\\x739f5b0cd49646bba39cdea1f5b70b63255b45f6c99a4f5dbfe27b98ff58abd0fbf7455336a9a3a2a0b4830391a33e4df57d5d1205be3c8746ade1a9287bb451	1608145198000000	1608148798000000	1608146098000000	t	f	taler://fulfillment-success/thx	
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
1	1	1608145186000000	\\x792d847687758939e1e689068cb76577814996ec9f19f338077cb837a8e68f4c	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	4	\\xeaa9c608f3f8bbdaabf0ec9cbe46b956abe197f92bdcdb9943fcf83d5ce520503693ca235baa53154b4b4e0882d802be6b346d60e9f95cddff210a267a24280a	1
2	2	1608145197000000	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	4	\\x274e3ed6722eae4e05d46aa5c3b131940f1963537bef194a925df3b6db2eaab082ba3d93a3ed0b53036256ec42d56ef11512f71a73878ab8ab02ff86be616d06	1
3	3	1608145199000000	\\xb3d2a217a2c716d676e33e4d94ca52a75bf81c8f1fce729d92c36682856c0e61	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	4	\\x5b76046c1d18c91ec7be6cdefd54f39ec159474289281a5be6778e2c0e0815de177de5d87e1a494f5d6a5b49d89cfd6846d9913c65229b90efe405f8d8228c04	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x0121d1a9b74d9d2b9c5d3ff27f6e934945e5d0c05893b8fda4d1e71632444f62	1637174371000000	1644431971000000	1646851171000000	\\xf43fbe4fcc683a1a838d6579497fe3e02896fdfc4e2cb567d16dde8a4fe07679d3e8b9fa7ef9f240ad5169a10638c53e9143a6f464e91b6f355e90c16e007100
2	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xc205d02f87abc5a55d87619dff7e320ddcf5b13545567a5fe4d96120ec14bb6c	1615402471000000	1622660071000000	1625079271000000	\\x2d739d9027b5f69c1380a17bd4780d14ad6fb6340649c4306361f80bc67cec4b3b9836b07f79171f40ea7fd72f70a0d803affc61b24f529f488f3d404d2b9d00
3	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x32eaaf3256168810b572aeeec0119c98cffd8275a4651e736e44c544ebcd331a	1629917071000000	1637174671000000	1639593871000000	\\x5576c0870fa583007f7d40696cb3502a13f92e160ed04f59da07bacee359c473fa17290d59ee5051ce9d143c2058a6842ce0a902313c4efd1cc8921e854f730f
4	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\x3e0caefbc826be4c81a93be5adef6c9a02a06009da92abb0fb17feb6d0364591	1608145171000000	1615402771000000	1617821971000000	\\xe045a1f5029ce53b6f7dbdb02a36c171a34c5b6101578e065320763da4ae1d9bcc9418bbe6e9066fe6c31f9f311dbd2c8146621d5bf9d1a325693afea596700b
5	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xbf6739c9f0aad725664f5d803ee981e063dcb74d7568cef0a89bc3de49f49f2c	1622659771000000	1629917371000000	1632336571000000	\\x00841f755915712895730380cfe7cab0f356277e8fb9e6ab6ec6a3c55f6b83b6ff8f8fe13a2d6cd0ea1181cf254e91cf0f1f8106e15793aadc2d008aa4379001
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xc5dd2994eb0d24f3898c502022a857fd5f8b86104c14ae8d77c96e8bbd0fa7af	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xd6c38bb090c6f83fe797a0173e5dd5463823587384aa39d40e0fd322b5bdf8c48b52ffdc1713b5e3de4febf8e8aacba1ed64c675c14fddcf4e3a346cf5dd8c0d
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x26ca0fe0e32e9c132b9ff70b854a0147ef40a93c4f5497ba642a239badce1423	1
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
1	\\x18cd0ab59caabae560840c7f13cb33ee5f4b59838a50c4bdb55ea0de5a9a6fc87a62b7f1b745bdc81e306733e3069a141a58e05574f6c38cdc8eaa793109db08	4
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1608145198000000	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	test refund	6	0
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
1	\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	\\x792d847687758939e1e689068cb76577814996ec9f19f338077cb837a8e68f4c	\\xc7f06036cb47945f4dadb40cbabd279a9d1a38d3a1247c7b5491084d91fa582f3fe094fb773d960c669c73df16b2e02aec4bfb9b7cffaa7cba025d82c816570e	4	0	2
2	\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	\\x561680b91e3a1f48932daeb981eb6a7890adab449d2598ec6e14b205724634ae74d96f872b3426e6dcada964594a1c8e7a199b3f51b11fc6a9b1b0b51149f405	3	0	2
3	\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	\\xd5d59b69649429ac3cd69fe2ae256547db1d0004b38b6b59c2a646998fbf09608c180b539609c3f7743a1bc8b577e82b3701a975a4f497a3f514431fd966fc0a	5	98000000	2
4	\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	\\xb3d2a217a2c716d676e33e4d94ca52a75bf81c8f1fce729d92c36682856c0e61	\\xcae04382776ef59a28581b288312af0dd39614667ce663f1aabed66faac5268a35afa501a775c8becb2928a6ee5b912cbda5bea0628bd9d3898e2950a6d5d80d	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	0	\\xa1d08cd22b982d957156d28010523a7e99a1727112a7e3c6186db69a1ed15f55de989bd1a8ea33c2d42d05b42aafa77706f808c74ca71327d613d3a4c0966d00	\\xf98e3cdb558c85de0d5eacd64b4808db8bf6514cd4e71609404d18290eed8f7e8c7dcbe8b2795dc07f49a556ce891a5116be14f31a5bde262c043d6172275165	\\x72654a030f4964d9a774feb653d22b4ce51221d696a0379dd08a9fd7bdfc109f67bb0afd5c56b6a5460b8cf9f02351ec55fb1372213d5a58205912dce585da58a9c9c192d2c5dfa40fc70dee7fa90807820d79442099d840dff4d8dd197d54963c6992787fd366593689a891d9f9be7500285d78df742e6210b9693aebaaca1e	\\x32fd546c75011ef3e191740e4c3afaf44c2013b3e2b46a6fae13adf0780d45e3d19e049bf54f79c1457ac1f1180d6393791d2274d682c44d58d2c9bda87ffc48	\\x7419a5daee3b350bd840f57b757b32e242fc8d67b5fc8cc3808e157a7abbaa628d2cd37801fea5bb7dd7ac7d23c1f18c3f9df7d53c933fe67f117e1828f70d1435dc119e2e5f5321853d6d27401dc737a7ed88ec36f22c737056d21329286e7486b5775c827733e95d2422c9d8a08e055451485bae4bfbe26e36e2230dcc1118
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	1	\\xe369d33764aa33d55d7510392270ddff290dad066afcb0c696a6e47e5a97904dfd65546625ba8d2a8691f011cd9f2d8ce59b990df91e04d7d050f2ead5b59104	\\xe8c0d2d5e58af6de1884ec943795c9fe9ddc51e9745c603aa94f41b06794b4aa25060967fb165b4f7c4a916777d13d5eb297c6d2dc8b121cabe5fe562e3e5cd2	\\x14e20c0ce8b1dd6eb2d780e00a6fcbeddc081e0cf89b6ba55302b8fbaabc2491d9fc74e8b1d84d48c4b696c969850efe28ffde12052ad9e4598efb89b3811dcb1523f64cef8cfc35815cb17d6193e2542130ebc4bb839495037dd0c10e3ede6278553f7c065ef66fa489c9f8925ca9d5901f3193add41c1d0a4eefb958250728	\\xd7ef07b8d0463210344058703c25869ebe31c17df7fcb2c53e3f2f647db3d349f8031802dd1668fef82d6d5c21dc506a2e22f3dcb292f8c5eb78cbddbe6f15f7	\\x6d5154b19c4c77c99a18c02277f73257fa8e9f7fc50601c26f9dd0e9074836bacc00db690d28a55a8e13c46eec704dfacba17e086ac5807215f9c0bc189c2fcaae09758a4c7bfa662e9691f32de7c62cd3d2b4a233e9c558dd32dde1bd42bfd97223276b8354a4a3441d631238100e1867e9b32bcfc64e8c1d56ce5e4157b889
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	2	\\x9c88c0bde4bed96c5ac7bcde976b4049bc19bf0c76de2545320f489ff75852493929d98c07903acc8ad10a8545542004ff92aed817d38b948def72aca8210e09	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x26cf1fd9e882ab620d5f03b031f3c424ae93ca00129cf3af4c80c7e440b31e2dc24ecbdfb14f6a31b2aab94ed26c2923d54296a0300a4dfb29a0af78e60cbc523bc84e71bfe5e94136c16e36c43616beba7225903a3cb8037a3ce24f3f425f39a14643550b17354b8be4192ae2905188041497c140b165bc042710552a892d33	\\xbc4295e7f6978ad6acc9194d6cc22fd668783299e372259e3cd98c2a1816ebc04fbe6ff4657c3d55eef526521578db01b62da0aadfbbccf5b4e7836aa38f93c5	\\xa6c7393688553f0a2a6119f3ef82852041401dda059cd01ec15688d39d7cf713b712fb8cf32ab7670c2f1e37ab103ed8c6b7cc1fcaffa25d3fe83ee72303564afdb4d1f8e65370434d6063617ff3d246e902a8321931bcbe9a8405429d8a1e797e2594704d9e78dbb135265dc5b65e68bb2cdd222ba0c807444b9fc22eb530ef
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	3	\\xe3790bd4ca556a330da8d395cea97ff052de69ef13b5b6714a01c93a358afcfd825161a259f2d0452ba6fdb1fb7d5286925e103248122564f51f437657891f0e	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x77f91c7f2930d0c23b8f541a910804237b00596a9905cb7c133cd660337ca4529b8b84b6e1f8605f4f229dca55c2e0aebf7d05dd33124e70835d14a8413c7e0ff42db784178480d3d21e54e9ee38b0e3977f0f83189ebdf698e8b57d42c16c6812dbc51cd3b7c2a8187760abc7247f12f8d8e0cdab8d882ff831bb589c50011b	\\x5118f96a098048de1a8ced3e8072c786b7fbcd36940ebcb14bf2a73165c53a3ad2e4cca264d5ae6b769076c1534b44fce16a92df2adf981a11f76fb2f0b0ef15	\\x4753bb9a950c3f926865b5918a5484e092eac1c192a23169b22ba648b0883eb639f093be9a582076fe4649e921593e0b30e6a0518c8cbd434df620a02c016dbca55c2750a2d8a73ec99315fdc0da0ef27400e7d2b1602286ecbad50087679a50cb075486df6a2aa924bc15881d6026e80559fa9b3c11fbd8e31583e66deb4ff0
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	4	\\x372715a32635255d47a67d5a6d0468928426ff1a16010ff84af390f1fd099ea11072bd010eddb3f2d6d44c87ccdaf409a48b55037899964adc581ebb9a19770c	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x369da4a0a2b9e9ff5ee300ebf2698a3e84e3d26bcc76c4742b841724ab3751979b322f350cede0300e2622f1b066231791a07bbd36074eea49790c68a77464613fe9f0b915eb6f443cd4caa497878e341fdbd5cd7077cfb124dd990e01d127fcd704da1a427ce252675e6f0df742e58fa4e8b0eed73e1b81236098070d6bff76	\\xac0e8b9f434a13be35fa0f17eb4fc99297758ea389407d342172e2077b4c31723ea8783b801fe91373be8444c90b4c9a6aafebd21b7d19511c4865cf188aae5e	\\x6e7d73d24d11c0df9d1f017f105c8a2d91c6f168c004cfe6253e730f1744cbcbfbad80a110c0972384dade0de71a396b21cc9c01dd691865355c1a8f9a9dfa18cb8f01cda9d0e6e73f71a859f071fb4ffaa7d5a0d9f6786ece17ee98f430aa9b84ccd0e5a6590046f66e889cf0c39cb985793218e794779613a7a82d35b0586e
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	5	\\x2057ed080ede90ba0916e0cca432ae7845b80384a862503604e4793b2eee5ccc273aa014a37f227b739b3407bce7663ca4acbc1154ad7142d640784aebbd7f01	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x4ed91fbc4083d76ed5eb63670f77ebd97d4f1756eaf1195bd04b88d1a1a4826b8b8bf26d463b55975ee9dee287ab2b33093fa14c4c98ae7daefd69c3d2b3ac98edea44abf729ca44e92025fe7e9e1e49b90849324c5ea5cb3813ff05d6ca43dbae3579c57643f1110d98218387c7bfa0df1937a250337efa2e689966e7767a31	\\x2c42bb5e6cea4fcf81fcd1f58703904df774fc043f24ccb434036b53cc01a6398be8189a4a88d5b50a2ee9a372504172ef126a54580d75283b0433c2e974febe	\\x5a92af2804ed1b7b08617d8162f02842ddcc30bf63944cceb4c7db83ba54578f741d761f42362d0ac37945d70c4ea9e27b18eca94bc0af276d3faca65f4d482e9c62b62d9cdef3b5f9036d2a206ed14e8322dd3082c3a1e0520394b23b89446046ba2d6ccad79fa306af6a46b1fc6c8177e8e01efa38de5889a252f84300482f
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	6	\\x6fc18b62ab83d58e5d31529032ff97103f1739cd1db142ead420959051cccbaeaff73f97b5dc0199902b75a7be4b346e05797338ddee882f4d64b15bd9c3c20e	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x5924517cf3b98ef675d612cefa8b185673a1bf27641a58f39fe2d1e8e979485913297b8e93d45fe77c9873ed1dd25e88e50c677e83a8ae03b30de1a0e689262a52283180a8fcfc3e3558f2d2514ef6f79c8ed664f9a77ae3bcff59049479cddaf347f1d9e77bee67c9cd3aa22e2183278f15dbe2e88bda757177e52e965ccbcd	\\x9b91e132dd837492c0d0eb38c941419bbde1793fabdea11dbd1091f61ffab31bb23a542eb32c165346c5725a288f363edc6c04a179a64404ac81d9487cd04780	\\xb837e99fee88fb444475ec1acd00139f9285ea36b994d77774d1930d41b8dca91f960ef6eec45b513ae10e0fab062876445ebc76600521bde951a124a4c8c10d269dbc45412e84d3362b79a4ff7d7eb40379b0831fa1bcf11815816e7bad3908c904534c44514531e63e3226c8022445fda1e877e2f047eac4bd956434a60a9d
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	7	\\x22d5693b9e2e1b758453d8e2dc15e917454bac95e058a7c7de1c150dc1a730b0c99f4a19d8ab8c7bf41bc04a666fe9b8c1086e2f358d71b012b16174008b4c05	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x2e6c3d3254035e8dd3d6c843d64710efffac9ae16fb9946a1a365122f1ba416cad88d44e11032ffdac69b1e9c4a1881906c4dd688e674ea946053f781779968a7e8bbf3ccc7e6e68c9e04856310f48955df246d5bda47d21a02ad71945bb52a0c4515c0fd24efa6850820b0a3b995c732f2f4d000ee6c9a394a94aa6ea017ea9	\\xc3d3838fdf0256b91687e26783f5e67fba0181ccea77e9840e81e49c8dcda5cf2f3078982ff4ebf9d9e5d4aba91be731b738b38385c00ffc2d7f9cfa0c562953	\\x9a93ff1a2d2e92b1a6c9ca91fd32c3451bafe99d24c91928c32839d9643407b12908942607c884ec01d10aec090548228fcf7023921fc2dc89e6f829db7cd121088f3f74782d5358fbdbac40b282cccbcdb64b8d5bfef328aeb3465349aad50764e0ca58e0042435618769d0d71ee16ddfd9161ec755593a1241878e26ba3fc4
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	8	\\x540d203a5f2427cc8ced5a772e9c7b5225a4883ef7b9f0f1d1b6b0d6192d679e6c74920516c00a93680602d975d3ed14c9836e8aa9262f205155173cc8874801	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x03074d8baeaa2bbc0a2a492f7c1f658031da61ecaca190c3557fb8524280b38c51bd894be240c31325639e4103a54dcc094694cb4e78b719f688df8f99afb391056631ce1deab47e42f68778f6aacee6184012af5ab763b806b5ada2a840da4f75a903bb0af327f528ec222f92a1a8cd46b138fddc7e2143432180b2ee1eda68	\\x182c30fb6fb89f15c1d2770e921245af44a4583a6003ac4891a8dd926342af9325599a8a3b7106f26254308e79b624c375fc50c4721d4a3e031102cd075b6eb0	\\x2f406658077a7e45b5b30cc8a004b0a6f9bb4bedb386a3a6600e34ae0a463bc659f7e5b4330f0a38777b31a1c3052c92d0f91030b1329f1c715a23615911ff8407c1f18cfdaf87738f08028ff3cb0c0d46fcee66b1f3967592bf3a0dd751671a28fb17e9be7dc4f4b239c3caec6ba3d9599ab44de4849e3d5f50421722fd8a1c
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	9	\\xe86a447079528a883ab5d8f673d9018b6af0d182c01c9066eb16d248679859871214f7a9e14229f45a5d25d94edf186624185247fcc2fbb0d98d711194f44203	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x7157275d1c606551cabeadfbafe35201637304b9813d45137d216f9cf741ba9e876da2eb07314e503ef16ccceb6689dc3dbc29d799706629453e2f66ab708f8eaa7b060c8b268ac1358e3b46fc7fc946602fa1e70a808063c686df093fdd11cfcddee424ba4db07cd57cbf2fbc8ec6dd1ed91406e810c305758dab3ea5d7f289	\\x1b0dbaa2d1e4b3b8df955607bd41df55eef1e7ebe189e57e59371f2e5627d9703c6834eb3df12c2b198987fe292552c8d59d17bcf1b63a0140f343a98710ed08	\\x3fa092b5bbd40ce40665f0665fd2e33d44e702bba6eefd7030577163fcc76424013e74cd2e1c0c95d4aacf252a1e4e93b373f5ec1690033049e55af021fae8f7c71e2924f31a42ed46cd0a8e4b080bfa03f6800faa1de94481cd3efa56404611d2b00a94970777b2bcfc54a1dcb94d90daa8413b120d92e0ffe372af8f426404
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	10	\\xcc7bfc2fb35f1aa4047c525dd879d7c6c2204582c3ede79511a18619c285db97912bbbceb34e3ff7a52014d8866f38686317029493bc65ff8eb3acf2aa9fb003	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x4b4a03978a48314f5354a5b42ba8ffd07471c95e8094b66b18c8032c727f4e5ad4f6efcf2c071059b59f76af54fd926f69a51de197b29a05da7f99df36d0aa76108b2945c01ef340c3363442e61790e0bac99a47b77c13bd3d863e17cbfc33b39b9b7c8362c53a3d1219b44970506e675a37f4921abca41eff4cee7f59f14339	\\x88f205b88fd5c5d1ace6dfd046de794997ea2cb491f78cb13f22ae1c9da18834134be72f78c023c2afb1654eac7c87c2add9c3233873f491e7f95739743d3735	\\x27e31a05e6be861971839da13a4e849101a2c69c8aed11b800d85f599466292f9dfc523224dc5a9d8c71877d2be250382c4a5a59f74df42457ef35edc36510e12ecdccbfc394cb4b0ae0dc8556b9a4234332e7a55490fa20cb895a7c1d008a28d9a1cb4291fe91b16e5e4b6285e55637a263090cf29db9545ab06e150f711989
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	11	\\xabb12d06fa64e73c1638a7c6ede17ebf41685044ca6b2989e5e379d4795054113de1585ada9a930e8530b5a074b53569034ac6409e0f69acc6b68f57f5460d04	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x7df8190173f58b0fdefcd25bc1cb9186d4a11f52b547abac0fab62f6c1be654b0183560eaefa62342b18acb8c7bf36a0f6774413f3d38ccb6bea3ca993cc2d56b75b53dc9c93c0c4716c72e1e659bd2fab269fb610f2b795cb30186b9bcd3978a3e2c5f26a0645562b11869cc4166d073b3763a753bd30061a2f3f03a13b3723	\\x1902642d2009be1b7cf6234d028040192965520dd60891478b77f0e0c237b80227464fc632d9719afbf1688ce817a83e87f6eabe0e5e0043322348b5e5428419	\\x953e1e0ac6366e731dc419cd898d7070dca88889273ca240b8c1e1ae597b10bf8c0bd501b235e36464654c620a8cf263c539cd021d3cbdf4cbf6f449852c702f6d38ad8dacd06a236e96787f77c871fd5fbb0a75aba3d8de6e860426834f95f7fee15aadc9956de5b7242bab211dc83baa1968f9bedde2eba3f9c816430e578f
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	0	\\xa057472c958986f099a9a98371bbceaf8593ce0380f81668aee22033f6f637d169f58d3a4b667285b4e50dc9cb11b9bee04ac8ec3f2ad3182c0d9c5c1a65f205	\\xf98e3cdb558c85de0d5eacd64b4808db8bf6514cd4e71609404d18290eed8f7e8c7dcbe8b2795dc07f49a556ce891a5116be14f31a5bde262c043d6172275165	\\xebc2b1096ac481e2eaa21eed1edde2bb05a0a5780273832205b070dbd8db2817d2f24d80369b002fcd9ef31512cef44e86fd4eb1bd06b02f655ec47b3c3472eeb0a8cc8ac41f73dc1167becf573a8a90efdf9a1cfebb90c4d1375c80265a7656053d9abfcb72a259badf60474d6ae8da611bfdcce52faf6ccc089a187798fdad	\\x31497920d0afc34b28adc49c462a5ba98efbc09f2e7915ba6df1adde6c3008efa1ab1d8776cc62c9b17af0b0c9fa17efc8e101b97b439cfa3e1ccc89e27562db	\\x139461f3416855329f34c102079ee8f539e36ffe375ea5272baf8be463a34986bdf890c68228f9f1a9cd9cf07cff0de5729e34ec086105527e6c7bcade4de2bfbfc756f2fa1fb21a9129d695ef06ca4c77db10c94f1fdd5940d8ca7aa32652a80217c7284d513293b97de55d0d26e3086125f975ca74c1bf0bcded2dc7ac06e3
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	1	\\xa770359edb84e03b37d952ee796007d7f73abc02ad4908c1abaf6acc0a59b18f3a953e0a0acee884ee248c7ffcc1f69f3d24409a2f0346ed4c5d1adb6e453305	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x99b3623d5831e13f35c25439d4d58f3499d18a987277cc83ffd249917ca57e5d772ad667e1ed5a9153a2bc95795496d41d9180139c34424853489e296f80c536221a8c0280010c317e89f47b390ba970ef89d6dc50a9461931de721ef4f052eec38ab78eef20f13971457c80629cd8d3627cc98f630a68106221677be99ae864	\\x7f1fc779aa5912b9ad84aafeaefc6b20dac8a2f8c21a61efa3f0da6a74158f477c1c69b78cb98fb6f9b9944c31160ac201944c9101c11bdd882fab6cceeeda3f	\\xc6e85266792ed6e678a234d8ca2e4d65d29e83aba91fa48b0f4cb91cda02e3d6baee41c3a1181c4ae5471bca7c9093a2f97f73c25ee92914537d611162e3b76c42474c96b9a3c7c3221a06b20ac9c15c0c63fcdad7c646014d4c59fc1da74166f2e9efef2925df938b31d86aaf59215c42553f53b4d96e83c53347400fafaf30
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	2	\\xdd27a20b8fa23bf23061c2a54695bb9256c403f809fb950662798adbe0397d488ef5dd2c4037267b9923f84ada216ce79f7ade52d58628bb068ccd4b6c446d0f	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xb4834698cd8546cef50db1ba317ad96ec83a9e2c8df48e4ab8d014c1fb54195ec9432d43e78e49c80d3f9b9f9cd483b91d77ed460f7fc3381e129aaa2bb48d16f6ef57ca6787b9eebe92f979449050608c22e3467637edea4a89706b34582181bfb0e7b46048efa7c5a870e2ae21aedfc517cb54ec77ab599a1d067d8193a6d9	\\x586c07752f0d236ce08652f59733bb3dfe112f9f2a292c3eeb399599ea8e4b063e9535a2b0937d172e236e7e9418c67662f2ce6a25e527931da1af0eb49ce3bb	\\x85bd060feb1c05f1fdeea24008de4a1d6fd5989f5386a0d072beb1250f7a68cf6987a9a3eabbfff6e9461c5db0d292a70e88d02d1f3d231c105608ca8c6d260f1da4648a7e471dc4272774bfec4ab050efa365d7793a907aa001042f19e43b3d809c71402cbf0d0ef495f8b6c532c406a00376d2c430baa402f594d0fbd5b50b
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	3	\\x71c87160f71a99dbcd08d0d8c453dcaa246580cc9dbab0002cb0497d5cea14e46b91930bdde78b91db4422f76d5d2db350be5a29b66c3de698d74dcae1adcc03	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x935f3d02a71ae0e49a62fab7af08cc844155fd6c9072603648878ed2c4fdb51ceb97ab12e1d3c6f07fc1de8c1685d4db61dd04323e09c55d0f31669b588a62b00832d14d62bb7a245d0ff4caa67080fc5f3fd65878c6543c468800ce906e247cc669130d1b8b3a231056a9f1b1afa33b06348655a05d2ce3073c2565d320e32c	\\x0f7feca7a010b6273d33087daae01b9a8fbf659656a52625cecbd4b9e1e81239bc3f278b4556c1175a5845c197117913e39c50ab976407d339e68844dd7a915b	\\x703da625e133e62e043c9ddf1c64f444b0282419b7dddee6d592514f01bce4fb328158db3729aa56f3ebb1528c175e0be10b22cb20a0f71d1113adcddccd3845d432e66456102880647a3bfd37069c85e73194e2eebd10bd4d3d5d4368429abce21a6e0e3b84c654e99eec9c0463aea095abb2770518c86aee81acfafc37c982
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	4	\\xcf694fdbe4db469a1cbbb5db7d04210fcf29f20bc1a288e1b1c0e4d2db452387e7cb591320c0ec47acb6ae43a43a53302d7b7f7be63e4e7ca4097d385f04fa00	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x6a3adbb4d858f19206f95d470f03be225659811f7d033af25da4168559b9c81f90d392e040a3365b265852a859cb9de6548ac5b4cac4dd8c3a34d80558e315f6175c63f758bb685565aa9f596376ba8ffc8e7d3df1ea794bbfa6c5c2e95e1630eb246f2e531b0cb8a6a6c11cf76351ceb1fd3c09620ce260ec60e070948280e7	\\x957f5288ef57b27bb6137759d28bd32fad97cbdb93b8f772ca2059a4a10b1b6dd1b307f99e57856a37c212d6ca53853d61b09fa42b91048740f3e35f774df203	\\x71471e673f0bf9320aa76a6ca60ec4a787f69e6f70f16fc1d9ae6678a873fcfdb1d335c400a0e30a632f443a6b403b4c3a5fb47b6b88337d7cafe0cf78390b07338a0b15f4ddd2482d62273abc6432acdf88e46cda372663fba409df8747508da1233c4b44e9ea341563c281913efd9609ea9304738e8e74b455c2e941bc45a4
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	5	\\xee397277164a572cd1b629a5bba0cf8f18ea3c4ef9cf13dc62096cec0d39862a5e7e801aaa1275fbfeffe2a2894c0a35042a1044641ce924dff70d2ef76b6308	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x3dbd5b7113649cd93214262737283808a1e0d504031c639b9fe58d00d438bd9da8a4da4dc873a0efb20bd0208a361e9a349948062605a8e9337840899b35addf0efb11b84b07f09c6bd105c173859d3894fb9456f79a579ae2abd7014107424956fb896cd74fde002f4a3448cc67b68b8e3fae7a81955279a689918e10842456	\\xa6565f956a6265c20d50cdcfc650a636168fef98233dff028009b3173c6fb021587b2c6807cdd6dc3b4c7a8854f90e77f22f8c9a8ad80efc6168080bc27e60fe	\\x2bede3b01b4715f1bda0028d42abf9a6bddf4e6380c9a7dc9a70f7ee157082b3429b6e223bc6f89e48bf5f6ed68bf33d05644c0ba0c81d1587dde976fa1280943de2d7dcd33cc833383564a3d2efe0557a646f160ea83433ee6664158d1c21f3ecb90a36b4dea0160f61df214fb8103a82340a0d7658964db461b7bdd0eadaa5
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	6	\\x2b5d34e7d318976fccb6e1962967ab62863235f22b854fdb3ed7481c59489ff58456ee7b7371ca78ab2145f6348b58c74b63e64c870ace84cb3cd31362e35307	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xbcc3b9a06c11af2d5865cbc39d5e0ccd746c0bc2573922caaf82eea7c21de7e4013ed4494ad609a2217a2b0c541ae6d4023c9aaf07a73d58cefd8d4fe892186773911e782990d085801421b795ab62f1ec1d27e395ffa0664371c1e453df8b1094c58642e9226cb38358e10d559a87b28f7d5163b56e53d9ac6bcff47ed3c2cc	\\x5522db960a00f9f4a3c7a375d83fe70165b80bd162f87064e8e865315566cac4edc2e3fd00cfc794defb2bb3fd10104b96d05580767aa451705d0c48efa78f04	\\x2acdc09d976f3390da5d6da97d324d9b14e1c869353a195b731f386405d0c4999c1784fa801505b019d4ef60a1a1919cfca2c7725f13deb7999847026cc1ce7a7a21d6c2ab569354e4e06bb3e30ffbb2bf821947ee58a3a440fe297f95e7b75df9ecb85a98082caf38c6ee2a2a95c7acf4b54876cc6b150af107da55a1705cb2
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	7	\\x3e0064243cd1e533ab6cf37e2d974cc245e500f0f74152aa6258bd292426346b2d87e369ca1b0367e5dcffde4a67644de5f62470a6af9a7261cb31813887680d	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x1c2e8cd4dbfa804f76ebb53cd8aac4e33a13e5f1dbd075f9bb19d482d71e84aec57b0b27d7283af0f4ae857f2b7501522ce7437768734e351bc2343b9da1bc24aff1895a94944dcb8b66e2bee02befcdb5b8996b7d92c749da193a7020bfb246d5c173b032e58754c6cbb06606d96142f7333c1220201b07281fff7d9e0c912b	\\xd4aa4f7d3c36ead8c86ad6a3bc50e814562c317103c4da70ce5b4d3545310a94b19defe9aca8d29e8ba3100e5dd1e1207dba51d9477fdfa4c264387d37ffcc95	\\xa05f808435f0a8adaa78bc42461fa80946b3b9eed0c25562b90f933168ee15560c4c4f5cf9b93680873ae84f87f9c9ce149cf967752f49b5493dba546b99dbc7b6c30e9f0e2de993bfd5037c6ed4513cb0fe7e61c3eb10bc7c617874bd4fb7dfed1013fdacafe07df087dc2ba53ea931c7d87e146c1d33f8843e1760670c2153
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	8	\\x5660261ff1ea2dccb084e38c9e0c22b5f8eaee21390078c2a6f403c5b17c74777f8097d5c4c4c2a0b79af017d33f59d25e26a4e1cac469d88a3a308afb619001	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xc3f40325a8e6d4b46e8b1ebd7483bc1d957fed65ffeea245d490fd09c2372734612ae778f4d449c5f23d0056015b53751c28259cffabc05385afc31376abb517ad72595db8993431cc97611cf4334279e482dc406ea2158eab3ec28dab581825c0785bfbf67c9b257a33249adc139db82248c8adfbe46824bb9e67dd2f00a918	\\xaab017612b01864f39182e0a7392617eac237e34ea119e4d7428918fa9a00ce7672b64a0859b91a9e3b6963e8ce12c57cdeb72949a1a7642c4e83e744512d6be	\\x756ae5aa540ff8d2884b119b8e1c71ece53a715ffdf06ba7e194b765917811706ae826e39a73f839201263f37990c9b6587a378fc70e1e7b49fd6c7de2d8f405a06dc0575df842ac77739e3cd48ad4c0151efa881e1a06d6987d0dc49355a2d2630eba225e4a08d3772504f34deccda20f65b90e797d5ea819f82a4e7486367e
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	9	\\xbb2ba9b5180af9f0c29ecfc0b216d38d5622f12dc7131bceb73680a013c6d3c3536730184bf6db63685bfb922a57b3da879bde7681a4af27d72e6bbd0b50380b	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x156bf53823e86da2390d51623dcf95f0955786faa8b22327d2776969c4339c5ed9e067f919589cbc755018a20ab63a08581af38fa5c1813a0c2cb702b6e1d8704fc938357d692fe4822a15068718827da9c91e7b821c0523b5f6690a4a9f209e0c147e0d31b761e879f79af264e7c65a2d58ddd6bd7632e218812b72253f456f	\\x71de14a9bd032f05bf2f55fcb028a7cdbff25b9c3b3f864fb6463070764f5585a54e2f933eb5ebcc91d1f7483185a037d23f4f8521c3b5a2c500496872ee88f8	\\xaabdee7c9926c4224bd508f0201bf7bbc0ff4ffad6a3a78d90e49b0288576c2832019fd1f157cc7823cf78fde57c79b00a8fda2a910cdbe674150d5538a1e3534f933874125ee4a9e8420ff1cf082cdc1c011b2ee0aef3ee4ab1613148f324b5e3d69345feac28793384ca227521efecbb5e2bf309f9dc12e9b00a23ebe9a008
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	10	\\x22abc27422229ab2a86afe987ef1cb46409d3ee0fe5a3dd463fdd7389ae54a93ef66254699c56fb83998ee2e5f84ea4b8bb210a3c128b80e866c6e2cb9439600	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x2a925d97412e2d1fec641e26d095a3237a3cc917d3c92fadfcef35518f5cd7fb000752de6ff6b5b893503772e4f1a3397640b8e5970f6fec9915d796d4a45f6c89512bd69fb27d0dbc9f6cd053a662f8f9c5099073be70a68b6d1392755344025d0503c33bcca84ed271627cd63c485b31c9c4ddbf2dc85b3aed78471f932518	\\x710e38b0127e509304a3ef80c8caa1497a6f24fc77ebe7f3a83cd3ce74c3bb90bef1c8ebd4a5933d4ca0c3345c83d6fed0c7a210e37254f0ef61d814a64c6502	\\x3b562184197a2a6265e4129c119285073a400e8f95dc800f4bdd117910489b86cd68284a9cd949a20424c17a68baac701aad59e4abc4bdeeec57e5048182029440300ae421874afd6823d64530550c7bab4c98f4bfc366ec8e0012adcf70c75a2eedd843b7cd21f00fd220df26fb2f1accab197d5c715b56494ca4860e6d45d1
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	11	\\xbf69d313a560b35170c379e59a06ccfa550c1bedd425cd6aec7fb7f237e1f92c5392851b412ff9666dd45852487278d4875f95078c7a2ea0e3e3cbb59e92a70d	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x62e4e353d117c900825eb001e677d7cf5f185aad751c2d47f5ab673858cf60da4a9ae6f186430aac4c9ac908b87b6bf9a979e9379861e481c696ffb54a8fd9c518910d12d7b4f6925cde4a78efe8da4cd78fffe2cd1e215f221b23bfa8ab4a30c11d3f8c5938e3faf3ac07611ef506bd6f2dd5f2a9718fbc47d43480855d7cba	\\xa60bc6d1ed8c2095cc971dc806ce27fa8e1443b48298cf61ef1658fbbda14cb3a8b8047ba7f2edb5077ee0154249240b82d206120361aa6966165e2255fe304a	\\xc28f3f6f68ee015ba1a054f28e79f6d5e920ce25528db6175a2e09b4def5dc2df05874ae470ca35c6cb9f026a1a5b8613ebaab5fab53116c9c992dd03418ec43e34c05afe17e5f0591ec102daa1fef09f2b11f33ea94d5fa274d449f9b943a37b2d454c234ba72e8f1982b3d3da4301a97bad716703caa65057f6038077f066a
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	0	\\xe15d2e7789027410c6094c5041add060fc521b3c1efb631c97caa241907d67766141b2e42d16cabdee676b9b8361fa172f661310a1ee28dba442b69ac2abe20e	\\xba22080ccbc4df084e536f430dfe8640be9f0214a4cb00146dd1fc50b550aba1aa174473be3d8f68e684f04c40b34577cfa00d11d2dfb6fd41a17fc66cdde445	\\xa84e522895c472f5e945e675932696593b1ea532097aa8eb23763aad375b5dfd2ed31f672bce6934c8e624420bd6162c32cffb36d567b589589d94cefda79931cb40abb1147720eb531705b618d26d26901cfc6ff8373471267981da6eee501eacceab33c20c2fc4ba8264e4782ff7c2bee8ec4013d7c6c45eb08fbe0562a159	\\xf37631c3ac58e107bcbb8cba6137d2c59e5dbc46f27db7203d1aeb28d15a35a4ae00884a27e373ce5eca288c02e6d28c224d578a05c409bf65264c6d16ce2119	\\x86f8b2e7d28aef52dffe5d2c930d920a05d6ad90003a2f142dd61ba76f77c464d12289bc06fc72984606590f76e0165ed9f15fe390642a296f9b7f31840b9b6defe8bfdc4fcfb205c90d0ebfef60f4b7bfa9c26b9e4607dcec595d3c36ee179312a320b60e297a84cd134a98478fc6c14f2480ed624a78d9e8124f5629c6abbe
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	1	\\xf07c4b23126d472da20fb1e88c3ca4226ff84490b1a7a9983d3cef793a874552c4438a6e94ba187f6e00da7c348da869d5855ff14a1271ad573e8f27fc7e7709	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xbbb501b88942abc734b8b575820b11ff7ea155bdaee1379de74d5186b375ea9e471ed13e5b9551cb9a9e3c144697daa2786bf595607a691353ce5487283dafc8f31c4b460ea8d78d787828f06d3eaa45c7a602b06fa20b259baf96939db45e42823a1906e915c50aeee6fe1e1f251692508c1a2ca37d6959eb7e5be3340991bc	\\x0ddcc8c1433732d4d00c30e9c5c4881b496bf31b2674a8a022b08c735fb978c6758197fe5115f91f689604bf27b92c025587b2578a74048bb7d8354c18d1baee	\\x825aa9b9eed75da0f62fac12a5ddaa9c5ffce43d4da56097c998c8c40f6975bbd4348056a59e94a3ccf872be1e4fcfa1b8c72077e47aa6cfc582087591a8f089c1e7be5ef4cac506700eab4c2147d1ceda3bfc99347d6928cba305f4946bcdc50e901d609ca3a54d10eb06b2a2594736138dee58d7f63bf24d47b922bc779d4e
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	2	\\x0a2dc64c35b8b7d4dc79f13d80b287eba99f34457e14a6702048637c775cc83fe908fbdc6d1be973d5b4a5a88691ceb2ff798bf7e47979fcde1292d6621d6c0e	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x9e773a41b33398e8cd4a0164cb2bbff6effbd23e6e157f54530c8e74f7a5a779c8d85b4074e62193268747a8b2481db0d879566cc05f211513f55b1f3f651f5150c5aff1905c30cc6db79731845e7fbbe2a02551c4b88eb75373fdb1ae9855fb5156e16f962fd0c680b5576c7f22581d7417920214b2da5ee9f0673404ef53b2	\\xc771ccb73877e50eac735262c09924b4fd08e46c9e9e46e142408e9b0f53b9773ce4217c98de0ff9426db4e279b2a41a57c48fc0edace2859f6152fc3ec95564	\\x81d04a919b1b08e9b5655cdcaeba7cec126340a80849c0e03b382b7a1d4f4bda263f2f43a1598216b46f2be0f5e257592bff78520201d7b6f06e3fe75fe0d64db01b74dcdd8ad14ff0a719f1ca5afa66297a071781cfffb9e60aa917e7a280aca813bea1e999bfdd3fcc9f075d77cc679d5f55ed6b4430b95eea6192be8907a1
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	3	\\xc242090dd961822f95a588d0e5869056f1eca845d66648a72c07f12057ee3d511909c6d90ac49af53b19bb42cff6ae02692f32b3fe68c5db0fcea8cf1edb6c0f	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x8951ce55dd57226f04bce0343ae50f206510cef4ae9880d1255d90732069856fa05ef8436b8b68a31d4d1504e7892b60c9c4a28b3bd587d2c2308ebc192ae1601b550e0f37e2f64e5d2de68b71863c08f8947718f93761df6d089d4db79d5353067716410b02ef706a410f3c15a6232b79a448ec54ee40d2064e7aa41e2127ff	\\x1990c79b2cce3e9882ca733cb732f264041bf91b1412dc9b3d96be1f7c757ab0312d323da7738de213641ac73bf01c7c0b0c76669a8cc74a9392ed690688eee9	\\xd085e104526a58f8189fb278b1bfe127c3fb070d7f14e1bfb31934ed0b3efb92057b474f5a1282ee9ab8ab7dfe8bab6f49a59aa5947128ba9af4d64c9347016886755ce29c88dca565ccad02afa52ac6dba747d7d38dd920f7040ead0a6425c18e7c63c0e0c5cd169f718f6e8f794f7c27f62f954b54b810d81a2ea3e82bad37
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	4	\\xbe8514a333131c3ecea013dbca711cf3ea90db0b614f5d323b868c32e9b0c09a52e8b1b940217c0d46b5b8aff1b8fc3d6073b3e348d006dfa47738015f545508	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xc21e3bb50e9665d14485d6fb458d5a573edfea4cf42c7073536c505a5a3f3981ac69cb9332a6992343786e773a74a77239e44cd30977dbbb471cbff81a3753030884707be9aafea5ddafce269c15ad8c5cedfb8f89ee2a2ddb8d9a2dd7991d62781f5cb55acd2f8fb44a69332217ec25ebe2642d1d1cad1a4670fe34463a6843	\\x9b5f68b1a4b7f3277f2da140580ce6781efc9cd27cf7dfb999164c31b49ed489f589fdf9c07411c5085f88eca88ffbb73544af3d17146938c7e225a5e78dc29f	\\x74e2d0dfc5c6d1b93d8a63bc1755098282a0d5b558b2d38cb7b0d38958479ec1ad20f31ffbb7959f242a65db42f7e809ec234ce4e09700c6526d005800fbc946dfb093316d4cb409879a8764bb6a55f02f7994ddba7d1026fff5d80ec72348a014d75a5900639ec06dddcff8dd19a969b98b6ada39f5075739beb1355b4b73b6
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	5	\\xab672acb029713a2ed8f5b394af5bf5e64abe755581c3525110e6ee49836ae2418ad0ae4e61d4316f5d20689c149c7d9a75366f9ec7de8ff9218bf7b80c2ec07	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x4300b836fc834dd42ec214aa2277024676c540a795c4f5c2c9bf3716b27018e4491fbd703d99bab7def3158fa00c4e3c7be8a14e3ffd1ca4b07cda8f52319755f5ecb30753c4c65a03681c642d7c02d156285f5b07ffd8a1323bcf04b16653b92e20b4bc6591a725b08f7a8a3b142ce5abab70df7572d972826b51421dca1357	\\xd75db816f5bf956de4b2760c2baebe4e8cd0b1b2a88e1c96fa55860138257b7e4cdeae84c5fa8aa95eaf261f2a184b934ab4b9f08ad3afb18e2abc99435337d2	\\x6f923697ab8f0ad3420a74ec6c25d73e7d70416fab2f805c1ca989bacd0f40693bd1e272830bf6befb0fcae677dd43a9ea16959f1a74fff45f7b1c694217e98428a3c53d6263f729ae41dd20fcf0bb967efb9f2109b85c24a3f55a3eb69f6cd87df158b71e9ac4fdcbdf9a1f172e6a681936b95349a56c6f007bf8d277f98f8f
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	6	\\xb9d7235459cf00a9b58816dadb2e39634271eb54be2ca1603912f609b957ed1698b2516684a7463a50a74d3cc33b2721300ba27fe78f5dd0ccafa96a36867007	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x8a5058f5d558c15db36100c11cf7d1697b0a3dad09eb323822c2ab0e3da342a341893476cf0384d01c64466e00d6184eed0f0d067ae4797ff094d656849e61dad930bbd1d5fc2c04d5994695091b64b3deb3033c190b131f02ff4ffc62ed991aa7a20a9ab22defc440564c0fcba0bafb7d68bc59d063ce247b8378379d494e41	\\xaa706c52dd7d7ec7271b49671cfac1a2d7c3922fed23f763d47083aff6b7d565e78ab07ed0e51009a83232715f0b8b5333327d334cc17c983264e670a0d975d7	\\x87f6dfdc45a8d8c44e7bdb3bf916e71cfb205bcc7dd077a53c8c8594e928fd0a2cb3cc8a176da7e0e42cdfdd6f58aed480ca464fb94639cd1be21a75024cd18e2e31a16161f4cd1e67a74beba0b7799996a994413d78950187916e748ce661b47cc0bdf335faa236713a705512012fa49e8d22f37e3104988edac2ee1a6e587b
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	7	\\xa5e32d3332aa903a9967bc58f5104230ccdcb2fc07759c2051d2526e975b267fbf07b2e93d333cfaee534d463e81d7444ce7a73e7285947c8d61af9bfca0b608	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x5a3e06447fd8d9e9f9f420bdd1bc8523875fc863fc28275c3bbf302d524926b9c9675c704aa825bb706e82d54a97ca59f57ac71edc1e34d8f1c6e047f802f00458bf933f1d5d80d87870b80b54a64a34007ed318a12b8982df8bba4bb2b846292084e3075ecf8fd1899780b5cb612cc94b1461d1f0ee3bbe24a4e3607b8406c2	\\xe739207616fe9eaf84ffa4877703b9c681ff39d523e81b57bb7f0eff50bc5eabd66f2447b760ef5456b923f261a641253205c323e2dd52dc031860a2976803b9	\\x386746a07a0d89377a6f78500c69388d91a2e2da41a8f77fa1277f8933ec5b63eb436c26c42b3441620ed2a9a137b02b8a2687d3f11a43600c6b0954766450875faa56bdb9758bc5507a9a539858166e909231750db6b5aab4040341389ae848d3202abff51dd8bce06e98e0c8218afe3052a0000daacbcb44b2f209876a80ef
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	8	\\x0647f3c52eff8f80f0c6941f2b8d32c7ff62ffaa146395f1f0eff1ba8c32b6a87c5b3bcb20bfb550bebe4bdbab66d79db6033e1f18975c2c926d266b90c6a30d	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x49e07f043a8339974c6ed19949c45a7711abe889ddbdf13c16c6930e30b8d0af2956eaced0db5f144a2c743702eb2bf4cfd3ee1ace9ef57f3c1ce77353d7e0ee896ac7be9ba91f17e4a48a2e87e8dd54bfc5c4c8f85d4bcec8c24fc31d6a650e888732b08bc177f35ccf32e8eaf7cb0572045f802a301545d504985df5f7a3ef	\\x5f691545218b94765bb5b2a2a352f194fd818ede98286ebf2434d2f6485640d4aa342ce693904d4ceb71e8332df803a2c8d3d149d63c10463b2bca35d31a1c2a	\\x68088a4517ff62c274f0bf4ad42cadabbe9239adf8d3b227dede1e4db392d34b3d06da2fbce5f36b4df4792b72ebb1c6b896e5d71f6fcd5f1b9e04320ce4d0a1f3e1ebcc588076a2710b45ee06f24ec4bc17676b658bbf5aa1a6b953f39525cfa3a626332a249955f6c71f01a60a00b53b8db441a1779f042c3bca6e43044b3e
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	9	\\xceb9e4339cfff3afadb7585ed5138716d97cc842f59998c6ea4e0e5f9c5f368829948c3d10f727b7da7f298c36f08ad9b1ca05377c1a1a706da9f5ee6f2f7a01	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x87330d3e150faff7f60805befcd24558ea1ff5f7afdd84bb0e89b201e0ccff3b59bebeab694645ab044cdf21a138dd797515face3864149668782af26041045dafa68c4043fe2997b5403f62ea3dc25e403af327d1b0717d19c936699b4c3d235d00d12c232b916884955992fdbcd505f5b4d97bd4ed39522a9f0ae3496cefd5	\\x00e015c40c4930d775b255b49648f79f737f9cf65ebb6c32e263cc633882a8082b0578ad073d8bcfbca4a6053a831d50b85a0fbbbca54324bc343d515e869db3	\\xc081fda0b5e7d73217cafa42694e61cd240a665de80cc515a87b1580d27a5628dad85f686a88149f3fb5701437cf3779330a6552a21fe96c0f488dd920a1462ebfaa7e05da1806944b9857c8723ef42f22dec6ca34a90e955e0b76252c804fb5fe0f665c028528fcd02339502e9bf07e063117bb140f074b859e3a5cf18b1861
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	10	\\x7357b3aea601801c7632a538501edd1481108bb535dc0611c3927c7baf1c18d0e08c98579e7949837b153dca1686d397039a6c17d2b861f88bab7dd5b93ac408	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x1c6ebb1b85e70fe195866f4d071464f7ad6a9c5abe3b243524988b8903b09ddfa87604629668b7a04a2ce6851bd77ca4db85711c1aa309f623d9f1dacd81694d99990affb6dabcb9b4d9dd1b644ba6c5fe50523fe9ed39f65a8d61ae6adbaf047596ca11dbe06e7ac47f16a6402b98966382724f7233c8de33630ee743e4f83f	\\x381645428269c278562376ef86c50ef75de6bab0bce65f17d122448d672bcaa9321c3e7d18bc57eae4462cf22f70bb45ca9b43c0efaa4b323933532d655cbd98	\\x200775daea8cce04e963080f38a23bd0e9c3900822f4d562b47addc5797dc785be6e00c317f1a5845b9a22b5190cddebe8133158f74691938f2d501fae10bbdb33846ad63883821fa4eb04c3a4eaff820315b20a845bba01747794736e83abda65828697589fe8ee925b8b9c1fe60929a6dbfebfd844151aedd82c736df1719b
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	11	\\x481058fc3253cb14ff8398906fb6d74b8d72c62d4499dd15f3c06245753b11a9073cecc166419f9f5819686526afc679a713818e592356cb889a74d9fea9f802	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x46babbbe3e8fae449a0afd1b84eb4a7e83379768dff2877032c15c4188249b14917de9d7f361e6a800b93edee9166080f9f513db655fcce45889e936b7bd42572aa87980072a37e0ebeee03d8c78abbd0721677956b48b63ba4e6f976bbf19448c8624da80b8d7537339ee5b4b9d2ccad47affcbd690e53b7a135f0fee492b	\\x4d5fc8792b39693f52ff79c2476ebf89f05a79c468f6774f47f9d511b364c9e00ddfa1d258ef2d06452beba2b6576533142fe1c981b1ec63b8342a768cc4fa80	\\x58ac93a0137fbdefff2e019f533b578024b59ac61446bf8483d4199d5b8e4344a506c088174a4445f4881f48afc417d8c3a6cb7512139cd9fffdf89a654050a57ba3e977f520ab76970e3d40b8b722b79bac7a74a33382b6b83b2ab2e818740ff3f8de091438a35e2acf0e0f815ac80e3342f6bffd3d2a7902b9310fcebe66c4
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	0	\\x2145deed19ab82767056d8c7dae8d03e4c13968aea64eb24e8259fe129c47297f8e53b94f5e44ab0a9e18c8cc47deb6cf72f029768f8c6359116e1288ac6800e	\\xe8c0d2d5e58af6de1884ec943795c9fe9ddc51e9745c603aa94f41b06794b4aa25060967fb165b4f7c4a916777d13d5eb297c6d2dc8b121cabe5fe562e3e5cd2	\\x8377a446f4db62718dffde728c09cf7b8ff65c76bb614202b3b0257b7d1d1a9ac8d4ad1540f0a13a236e64e3e6ea0edf98cef10aaa5ecd917a6bd831afc5c2a015016894bf0432e349580c37ed49e808f7160ebbb6e5a069b83715802ab2acb00a9c969989c953cfd68ba7c791c9c0155e4e5bde511b8394acee01632e27766c	\\x9b3d7045ed955b05ce4f4cb83c1e3fa516ec61d934084245f6f16ce427fcb0b0292cb56eb5c6b89ab396d8424d968e511844b87ab507ea48b25a6fdab7739c48	\\x5d2adde973fb797a97dfcc304054eff6d670d6ac586091b76c95670aca0a5312db8b143dc2068b6cdee7fea8a74fe9851b2572a5312445b77db04746afa32516bdff12501d9caccb9b0aa6981e9ea81b862aca0f08ff12aa0a094ff5752c6b0a5a849cc5f24c86632ff755cbc780323c59e4daffa9a676ff3e3889ce0cfe5876
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	1	\\xe36978679b6b8eb139cb0696f829367349e27199d8a1882c5bfc23d0676af7367c7dda0c74e11285b36582e70b7eaba96a40bafa40761d0c8f66aa787d3ba904	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x28458fec69c4cfdcd34c67a93ff71344c25278e6017151ebb32b9b81528788ef6a75f7c37c8363d41d2278bc4f355c460112c19c177ccfbc31c616dfc5002c6c0276e9b37b74a71fad6e8602f793b9da056ec7dc330eea1685673a01f98cd173540cf78acdff4b7b5a75459509b29176bb82a5ad82eb7abe8d89e00fcc35e0f8	\\x4d926e873855ac37bc7e10ca0904caac7daa8bdafa4383d74c867b3e9bbd57013d479c049027a8f01e954d4222d1f9f41843b508ce953c10613dd46e0fbdf0e2	\\x55514e032a0c53c7e669188fbec52b78e41a1a07688c76bbf7166291a7b5c5128e54e4b3b8d882226c39846e6b51caf645bb4fb1c9252fda3827cfdd0b864695ab3880fc0a31e6cc44dfdb539c12f37a4c7ff5c6530dbb82750b454b982b74cbf06e15b11afbcbb8ef3fb36081a9a27e03c2f78650ba2d7899c23f022ff47f95
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	2	\\x2d23f84e4df57d4d6da64a6a87b44a0edb7579143c7c163c67dd4da97c9ae251e3cc4404819414faae793fe0e4791ba7efeb9c183fdcbd30bb73c6f2d1a15d02	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x815807a9b91aea2cbea8a1f3d7ec2c6ddc2ae85c007861d3fbd1811389e88980e6211c73b5d9ad8df9d43d9ede929c492e2a03cfefcbcd538b21ab8570625123c15e67fbbeca0a64a2433ea53c0e53534f28f5d3dca39c1c0f8f1ece01b0107bc8d88c059c004a90b065e0bd1e7ccc8126325c495a7cfaba0543136a16e9a156	\\xed20fc7f897d62f6610b81b6e6c5eb41ded76bdc4a1ad2000abe8e3f410495f59941c8f418ba00f19c4bfe30bf1d8e9e70720eca60d7b3d1dac1a95b6872b559	\\xaafa0a76484b8f5a665ae0ae956f246e27a7d0a0ba46caabf35d1078d5ef3e43de2f8f9f194abc6d6722001c8f1c1260709a8843bb984de5c2b6ecfcf2266f155bf2fb28c4a2de0bd04b1acdce49a3e87fec7b76f3c5e21150ce5e82714c565344f1d63509031d6b065a87b90ac505c4c88d59c7edbfcca393d2f3213feaa2e4
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	3	\\x70fefae84ecfd65db853940aa506ea2ec3bbaf4ad32a66f4f6f2b62700fe012b5898f49e573044da90e746be362df04e91688b7542165b10f69bc70a2143bd08	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x73a7d760ddfa20332373c9d8f0dbb3ba6f80795a9cc7d1757b6fd24ace633de2dbb47405f6b6cf0a3d2f6a8c9e91a1955631a6245fbee53b06001875006b6e24d79cbe45b814b25bbf8d89aace178830ab37116e0895b469e8c20a3c1b9ccb2fc646013248d476b09edf4902fd849fc93b61b7da891f97c28431ce038bb65f4f	\\x4dc6cbd5fc63797351080db876166851109b2b3ffe119e454ed2ee6da96475c1396ff6bf98ffc8de5bc0045a83c7deb3d427d24d3d454abe6d3e305394c3b770	\\x3231ceb63826b685a5f34f47eb937c87af7c8024a60ba66ecbe74397798a0e54e77643e301ca4180fbddaef0d835a639e6d76bee936b4ff6689cb6ab9ed64bc876146b33dff4a8abe2d3a6955476964c0fd13504cdd29b70bb192e73b94e1db899b33c040e9db30dea80296c062b841b499181e7d9cfcf9780470734efb24b84
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	4	\\xe9e3ce93690049ae1bc40038e9831a79d2d120cfcfc4abaa47bcadf4fbcc61927927740b3fc6a1cc07769ad9dda0f35d8b45eab10c381fa9abb3fb2306b10a09	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x58186493444922c36eb1c0a634883fc913677bc894134523cdec3ae5a917276235e66af962e6c8171d81cdc7d462cbd49f1fda2b6a59f5ed9e8703ab49793b2233ec28222574e2a0d45defc64378afe9586fcbebb8c2116850eace58dd0b3a1a8c7f77e3eaff63c98170b99855fb6486a11fccfe12eff796f1d83009152aef2a	\\x28d456fae9876781d6a18c0e251dc29fef0ab36ba3badb2cb754a6483ab45d341a6bf4fac6a116d28370c4a95b25ab6fd05fc869e12db134aefa6fec3e9cbc0d	\\x51f9dd754583c775e8facbc2605d05ea4ff26b043e91f5b72d5df2589c2ab65e2629e25031b27750a1f58a93af66b892a1854c2887a5fb6db80432dede022a334af5b274543d46ba7813497d3f1f71e11e0a0238873259abe09185ae23f74556f31b94c7448b8bfd0bebc255292ee5eb684018b9bd352005f56ee3b4728cc4fe
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	5	\\xd41d631d82e9781881b05b88a1e71863e2c8f3c05b8797a834850b3f1796a9c1ee48f0a02123958de077c22dcc864933c4480f32e993658f057ff6b3575cfa0a	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x70fcbfd87ff450ee3823f45e2fa2f2f4ae13107ed8718dc85a1f2ce11e9a04b6be9d8d6b24d09389819374aba278442bc313dcc7b3f5e6c6538e0704fc27fcf587222849997642b6eb485a505a802784de1041efdb515e3c7be10043bb9496ab0ed846f691998d6524c284c08519c6c374cdc799fe46c4bbbb7988a25f2f2550	\\xb8c0928ba44cb35205b244c0752d5f1027c3fbc27ed05ec4b8bfb5976883bea3857b1e52345597334a407383cad08804ad645542237b382d47e73c240b453547	\\xcb07a598cfde84eee1be021dfce7e2d9f6f2d7ef23a3e6bf82825c3f1671ce8ff2332230994e42d6aea35e1626507b3223d205cfaf57ea6845c75b6e0cc557d1287ce44ecc824e2da8d5e9bb1e80631bb77b857b7052cbcb128dcc541dae6b7ca6d9a8f11b69189b0081c35eb794fbb109d483c6d4d8dbf1339a9037efbac3f1
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	6	\\x7f0a5bed965532f91c2cec67eb789a59e8ffecac66520904a534aadf41dc30205880bd778d7b11f6dcccf116dadae7baab8f8bb6e67337499cde53fe86270906	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xd58e6213df13982acf232ed97855a432c53ff9d79a2684a7b18c8a5a29c379815aab8f440574e184ca29b6de9ffe0881dea20fa710fc113832d8d3261d8c0655e82ca8d3aaf09526f6568a94a63b00ad1a9dedec35658e1f7fb1a88cf06f73a2d9afb3b78b164ae5ad208539944c8a453e8ed9407ffb3b3ff3956397c23394e9	\\xfaa0df498bb7c6098a3290f99f0a9fe8549b7349a7a316bd78d39a4f166cd307030353e57386a263dbe084d4700511b3e84b22ee736982eecb62e00c7d2d9589	\\xbfdd4fc3f31cfef9be622108c06a9e830fbc2099d6b04e3750fa342371adda78c621ccfa1e289dc6fef713862c8e03ff266b351ccee15c9a05215b183b476e015ad734bacf4429dad53bc8a8bcdb6381b89299a68cc81745f3e8a6e43e7a892bb9996c8cda79bb3cd09986aadb502932e09a6f5dc521f0b374f4264494bd9763
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	7	\\x4fef368295a3bdeed0983175da2a0a65280ab21407cb2d35e55ceada30b45199b752cce4f3267b0bc55e2c7c8b37753690c75fa5c68afdc16d35cd3d1cf4dd0a	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x0c79d792e562891b39cc4c469ad11fc475d850205b66f9e4842c103e8a587eaf4310d2d0028b585cf81b8a4269548d0ab72f10a1412153a68c5ee4f4147240afbf46775d6113d5d6419cf2bd8aaad1e0860bd1dcd726060f488e9b1de4855c1dbd2d303fceda031dc98cc4085466db60e3c2e152f1f35b8cdce9fe0dcf2e6f86	\\x4df20b396df7032343a18c1516c9045cc231282160e8ebc0ea36f14dee743ecd9f43d03766f655982a297a3b61d966efe0806f6a8e6284b0548504608912a278	\\x95f0ea68f7ca010f0a1a2e14d0658bbf1bb74da664582958ae5bec2738556b91e5336ca21d93ddfa8f8c0d9b6a1ba038d45766ec077e5e194fc440a1905dd697ad1dadf574cfa795ced851b5671872d69ffd7f1bc01a4daf57c50d8b59db663a131c76a2590d6b78e3d14bfac1f55dcc2bd2ab2fde4088a7793454c451d077e8
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	8	\\x952c2fad9f9b04c481fc2c36af99f7934df8b288dca38d804335cff3183915076403435c76cd4aea01667926184c5d9eeaf9f4adb7cc04d42bdecc97e05ff80f	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x6b303032cafecc01e437943b0894c6a01b67ea500ddd65974b1e87a25b631c95eb689cf2c5e51a60aa81e90a1e77a5b4dfde618ea7a419100b8588d3014e7ff0fe94343b34c8d2551754c951d035b98bb10957fb27f73878a287be129b99d83f921b0f0f6855b0b81cc75ce4651135a0b03a432ff4f015b7eca52c18126ee8fd	\\xaec1de767d6a574e3904ffa41989ba4007761bdfae24dbe40fe167bb477ae7930a69e81c2d8d3a421cb84e0a6f5c517ad99ae9f1de57ead4024be219a13c578f	\\xb1bfb5bf05616ed05b97ab198232934c4e12b541be1bb8c2e7b2a3d3e815e266d9deb586579b8a30a57f0fce64a225a0a617d7e8b177281dc46c9bd3967bec19e26b3d89d18391871a5fa2d60a5c936e1bcc4644c7f06846fe0df90c2d43280e98bb8cc7405457e13d3b8eaae42cc42e7e2396b7d4aa5093e80500ce454d9903
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	9	\\x18702a7fc2dfddff743ce5767729119309debba0f48034d8136af831fa422563bb1000df73884f79b3c76245692a8ef2a9edc43b6802a0cf3fbe96ce37e84d0a	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x3c13249092212d90c447f09a56c4b31463c9f32a593a626fb0a6920313a760f835c776c9e5df2140c7c214b9c53e63b3952d9cce4b81ad162c4540c15f11d6a045aa954522e4a42760f9ca19cb31dc91f1cd61da8bc8716a81b1d4101147e2d0b36164c810229e907c5f2298ae8a7d5b909a12f5bbcd1c0ba8182bcea7f0e66b	\\xafe2fea4de3d5460f8799a41b1762a9001f30417b79fcf7b0e8f229b2473567aa74a33ed4d1c8a25501745efb1efbab5c28782fd83d42b2a7485a15d107c246b	\\xb9819b0638049945f515c96aa7108f1fc41ade5fe2358fb0191b877bc316cd2fb7f603ffb5f413200f3aeff78df0f32ebadf4ee945ce2e3e6b818aed7dc80ad987e8381565227cacecd4769ea481cfc80c5ed970967d67f9472381f189d08372b009cef196e9423d0f8df998cdb388a2c2fd6144e4bdb11347de8616a5fee012
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	10	\\xca77738346a9f131dd40ec1a5fa36a22f00ec3a4e7db5b033925829279f3ae9a77f5216c05cbff66df6e277ebdbfbcb2bb08326a831ed52ec0a7bfb60a9a9e06	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x3da7bcdb10f8ffb048b73263dcfc8f02ff88fa26d0e2a5940495b1260d26821cd9af0edf37c7bca9c814458af1bbe8d5b4faf24e04aed546e4a31825ba192f84c1cff3f8bf327ab5e10c48b575a2e0056415ea51d8b57f469a78a597d0322a51ad5731d85ffc832fb2bec473457ab1421ab673887fe140070ed62079ad6a0cf0	\\x093d0ea6ae944281c5631427fece2624f698b8d9020f02ddcae1b689fcf662d699f16284245c7084debb0deaa34a92be83ddf3563c687beb373f4bb2cb8f7686	\\xb49425fc75416c7749770602475d3b4f854012b0d3d566d9290b8a927c97fea7539febf9ce42e141ce1befc4db9be300ce234a1ac830e1e822d669856983d5295a59dd591a978a86a9d648c8b71e0612a676df877cec17278e0c0a906f9f11d22ba4ada84412e25b0637dbb4f2b2b9b4fbb998f30de27643c7f4aa7a68a6a1c4
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	11	\\xf5af59693fb4260c49bda562a95fd3347b36d57a9427f4a0085c8e73936b12bdd65c4dade0c28f4b4d9ec78828d1a0e0187f79dcadac52c931b45884a640310f	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x9542ced8192783083f714cc233125f27056b53ea0d2739c9198726ec4ec9ebdb6c5194e96ef473517c7abfe4e567d4bb406b8b25067edda2e57819d63e5aa63ec790afdae6be5a2dc4f6306b22ce5e0de5fe0bff0a641e2f8686e0dca0d8641652b15bacf847a4267bf59cf7fa807ba588bce396922e27ec2daa628345e8d7c6	\\x27964f9b8548e656cfbc0b6d9b658f586c7d9ca4b619e7e2c36c760caa0317d667874131d57af8c68db0fa4c2509edcdb11050cdb8446fb5399b3c1ce303f573	\\xc529a19de154edd81de80ec3b2d16c4e69b3c6e24a875ab20b8dd936c75ed79293d8b8de20598aa072bd5a444502b1a8fac375aa7ff0137866bf1b0dd3d639e23ac2f692f6ebf307e02059417b43d5550f076a29423ae754b2bc16587efed47e53f4a05e0c845496d1f1c9578b634f4224052d874bd63fe04f98b1bb0c974442
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x0f553b06877a34c4af12e41549434a3634d4134616a07e4f60002a0e95d55e195ffb4b3d092f6c80da791eb63736a70258348d23ed86806c89a94c8ba10146b0	\\x79a9e78664e2e484049fb49e150cb9021ffe991086d48c90a5ceafd94065554e	\\xcfd277f5e6fa830dd228b7c683c6d7a01bf9afaa3a4c43337adc90dfea55057cb0e58f3b539eb859fff26f296651f504c7f01790e5c48e127ef3f01cec77eba0
\\x14c09cc3cb2f504ed2aa442772f980e1bebfffa60147dac4b13b16af3387d89df35e0f9f211a11fa9da44ce73aedb2e3e5a0ea15ea3c4ad4ec92d1da3d52242b	\\x397ce228a1055a498d7e476be26cd0f901b2aa62e6cbf025117dd1e377e85267	\\x1a5e6ba883483da544e0b4f7e75cd9eba771ed4f24afe89dd12faaba7ade02fa5d47ee290a8c6c4d60fc4a9ba2012acf392ea19bbbfe49caa7f14c55727dbe87
\\x512974a8c619e2fa64e06eb54cae656d76960ed86d021556d1e0073b79b01cfba8d061c6e24b9e2ea56e2658a21d0cec7d5165cd31e993a330e73a0447ada0ed	\\xcbe02497b3b8cde0c60c6a6ee35b5b763cda03e8920ce7809b6f714705346f6d	\\x120b93c9a58798a440af58fc49347d1a976792c2a7ab8b814d6e0a8d4c64088491a537e09167d842e544e57e94cec109c9c69faeac9156c4a9dd782faa0288c3
\\x29998e28cb0748165eacfa08acf2a135445fed6566b939e32a3bb5129f7b8ebd77b6ed953f35060a5cde9c3e377f8a27553b311bb48f59238a776947a291d8bb	\\xffb1bf959068056960645d07573a08a739d4425116e41f4ed6620402da027069	\\x5916a7b58292d391d66dc5d993cea9ceae69f9843a2b140821b8dfaafe2ae07bf50170ba1e814b1ef7fcac51eb1b27e247da2a896a3a8e5419e58a9f8ec369e0
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x7ad6f71f1c75cc52b99f082bb001022cb8177db6cf5eaa63b4cba578da2a228a	\\xaefa9c94c1d399c8c205e80ce5ccd57ed50814086f03704fc95d9623514993e8	\\x61691339713f869001ca2611ba99edc61c3acd6e44e960bf4a3091f6b2ba96a6c31a96456247fb9a3727a1de04b4c3227addd7257ec36ce01909e14fff2e3e0b	\\xb7e522428eca43a22242b38b645a07956cee50c968e5345d53142caea58aab8adb27eafaf10b8529e3ba1d664c548fa91f4ee112a9e243b74f4009b8b42e8259	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	payto://x-taler-bank/localhost/testuser-nvBJYNQ9	0	1000000	1610564382000000	1828897186000000
\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	payto://x-taler-bank/localhost/testuser-QbgOxKEP	0	1000000	1610564388000000	1828897197000000
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
1	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	2	10	0	payto://x-taler-bank/localhost/testuser-nvBJYNQ9	exchange-account-1	1608145182000000
2	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	4	18	0	payto://x-taler-bank/localhost/testuser-QbgOxKEP	exchange-account-1	1608145188000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xcfb52b96feb947064f0de54c285ea24f4fdeee98c47642e7f20d7eaf331f798d094c4bf90f52898e7e4184cd38b8c90932c52f68d4c3e8e3985645aa983cc9b1	\\x43e7fb35133379640fb65c49f54ef0e5d29e4f095b847072fd8937fc94b9779e33550bbc6971a05c42a6457c10a5cbce104b901f2290642b570c7a5c643385f9	\\xd6f7f7f6d2b9d259690827dcd8656df1c39fb4b9be0583863a6fc9bd6b06a1c4866d9df92fea3ab36f691a2d84414825f2fe630455b8641afb3f30ba8d750ea06197a4ba12fe46cc8941edcc0fd9e9067165cff29b7c5f8764682dd1fefd4f10ddc3aa6214c9b028f6c914b6962e28383776e8702f912d9a39c7519c3ebfd660	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x2dcb84e91faf9f85f2de748a0e79a17cd68cc69144da09d6712beef20ad55c97311c72dd5be775e00d38bd5d8517e8c4131dedad310399b2c2f589b06ac2b001	1608145184000000	8	5000000
2	\\x2f0135db2093c797e745e3ed9debe6e04154fe97fdf88fc9c4f977cfad45048fb5f8bc8c240289f7095df996506e1b5a75082bdbd580ee1039cc6a2fc206b621	\\xe8c0d2d5e58af6de1884ec943795c9fe9ddc51e9745c603aa94f41b06794b4aa25060967fb165b4f7c4a916777d13d5eb297c6d2dc8b121cabe5fe562e3e5cd2	\\xc0aeefa8df109ea8fedf8fd12c37cd04bc5e0d32d6b081ea2c171fba466853160f7d45796319cd42bb656e8b42006fec644c859f4d9323768d193f57ec5111ff0fba7e34dd68e880cc5f78f7f7902f7618fbe3cc9c847ba6a170ec4911047c283c0ceb97d27bdf30dafa38bb1e35d96d443974e074135a7276c868d5125f7df7	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x9951c991527fdc0aa4820e1c103145dd148a809eb0eae73a346f5093cbe39218b0ff6e3dff5c8eaac77c02af374181785d91be8047a6f2c5980a04ab54deee09	1608145184000000	1	2000000
3	\\x9dbd4fffe491996e51e49f3df5ff85078048bb7b800e1383ba3ee56dca796650e4a400bcf09af36c58b6baa6f48f8d0e1a3c9e6aacc0ab0faec11e46e0d4fb51	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x46574f9870556a288c50e96d82963116558bc28220ebe4d92c979d8751122f78abcd010ff747116f34823099a708b684d57643e2624fc2371cf960d44b5b9acff18ab4236101db4514132beb4e34833b081247cea538e0c30c571df023f2b133d689713e4d9a7fd341b5b1c6740753d31745918d3b87c86f6e94ab66bd8598fc	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x0d6714161547ed0bfb172ca10e531e32d68bcf3fe19c5d67c65def94267c76f110f83d06339d844878f2e2cd2bc9328fc34a66a64ec0bcd36eb5f128cf1e6a09	1608145184000000	0	11000000
4	\\x22b75902604f580d86521afe2c8d3d73f68e622ad6925f1ba68f399f742686ce14a48c662eb18dcd4799dc9557ec20ef8da0ff1327a6f4f76e96d217680b38f1	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x4687e4c3fb2e77b6d83cfd2de829f87e0525479a8224d5514a65def0f818511bc99f8050bf56ca9d2d3c9a08a3e6f7fecc5a6c10d8e8d808ebea2a9cc92b58b15293933f19d5cb08506701d570933721f4c5b674b4b5d4bb004b443ade516ac40135a87b5d62f18e7126f07c4a3db9616ae5efdab43a33b10308dbadf212fdc7	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x721bff62366c29d079c1efc4f154c760896f07d1883ea976c385a148fdbc9215ab2801995105dfff2dbb286d996108e8edb710e9d0a685522cfb9f346d37a402	1608145184000000	0	11000000
5	\\x0419eaac3b5ffd81a537b30c6306b32c3e70ecc2b37a81216f524f84eb977d16a01cb70129f0f5438c93d6594f792ae25ebdd7dd084db211d961f0a6efb80c16	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x17a0333ee2639107660aa5563f97ae1a6d8d51c2bebc11baf37597ed98dcd3a46bbb720cf6acbcb2dc82f11da5676298e025548b095cc974f9e9597000c11f5aaced8cb86d87c472a1e1efbbbde417836eef934333f1794c709021611ee10912e400140f9fdf93b88e015239a87679d7dc7a2d547adf08dc8a6283e1049417ff	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x2a25438059d8d6d074ef97f8039c723508d15607b5e7597f07abfb1a7d99a4bb3561a40688ab1f032587a68fba221553bcf65b8e018b59be387c70303151d604	1608145184000000	0	11000000
6	\\xf0ee3c12d6d4ce7542a6fff384d2786fd13afed5298f2b786f6bc54723679cea38809d895f4491186d673babbce286e1991febfa05680133f899242d6e1033f7	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x7b339a3b79083fa860f8ebe07d548a4795653a0f6fbccc09cd5229261c03d8f529e4534c2e90ddf1c650e9c844c99f5e262a26eba1a9548e2c6920735cd59e3ba23edb6823934447c6d75017533d9483d79e3f22757260ad50297ddc966800412f5572d8d2365ff8b7bda7cd5ad3ab79724f46d21d272b7bf10cf8f870c44456	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\xef438790f4fd6de81c83a1473a9d0bd88d1f8c1998b692012c6c04b93972a0173d0da25052aaa1120c9693c49953f4a00327cee085a6153ca34d11972b5b2806	1608145184000000	0	11000000
7	\\xcbc29b1e0ebd5f5b2112916f8e539864c2aa072be90e78704f50675b4f12f69da73e6db010e6b143c96453b8ab7ee34c3fd2512a24d7467fb5457bc15d08f6be	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x7bbf2f777aaa524072b279a0031b0b0b2dfa65eb542c4f8379df27d40993f3014a82e38cec8f5ba697dd91fc72adeb279c6f46f4e5f9458cdaf728a55e0877a8e441f013450c1299782b7dc634b5c2d2c657b566e48e3c2c8ca7a8bae06b496bfa19e436eac2a386249575a6f0b647918100637e09070c3238574e23391215e1	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x8a69778a8c1fef03be7c9d3369a02315409da9565265fdd518c037c81acc38b7b3b328d5d220bfc948039ae4ceb280b8a1bb9705211cee927cd9253437afb900	1608145184000000	0	11000000
8	\\xcb93cb9d25011f337779d1df0d5f066e892157959d8d20326e1922ccc995321543e323c3d0a876bd2a880bc5489381e43012a509b3ad148c8ea5e9275a466560	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x54b8f123edf15b4873db8516990648317b87459990414c916607fad793f397b59230b4281442016a3b99a4a7436272f34ed2e8e7f8e4378a6bac45ab1e3d0374fd48228e59725e998110c2bda2eae3afa1153b8fc6f60634459e0f636f525f6e92e43d6dfa7a2e24942ddb8364db0b70e9517a97041c29a3585ae42ca0480f57	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x6b9339a72da8ea79bdc4f8ba3a815fa32ddfdfc21d85a63ff6a5882e35e1105cf055d9a9b6c97aea8114add17740ac8c59a602b1b14e35c843c68621d42a3e09	1608145184000000	0	11000000
9	\\x93253b46b1afe020bd33faac5e2e9697e2c2d43896eae5c8b0cd78e4a866e71faf108038bca5e1360c9010982ef5920c9c7e5f60e46fffd24d32dc0e73ba3624	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x46991032531185700c3fb192809d5623db0bebf5600f646100402b27ecd44da4f777333829aaaf20e4f71340bcff59b3e43abf94f32cefe63a014d0fe793cdd90d28c3a0c66982f6e76ec545c513ca5a58d3fe0b9f207a8bc431bf579af8fb51bf73c78c1fe0311f3405f83aa9b91621a88904981ba736877052b87b34da61d6	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\xe70bccbe2257f72612170e5ff069f57393fffa66620f0ecfb47a980a9737a55e5a8cf551105f414e459a4e1548a45da756464283d551c7f9548fc281caf2440d	1608145185000000	0	11000000
10	\\xd3585d1fc1ac60002894d506166aae693c7765c864178f02fe45d27bbb96de67e5b88729bc7d0266f2439651ab64b6b915d07cd5e51b6d792cdaa223cea6d8f2	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x67eef088507294b281d2c74b001ff1c822fd93a852a073cb702af5d2457ff5c8761681a492acba8dae81aafcfe8d063cebc73d3497f37067392955f066f2aae8e6c0eb219f3d5958633294aa51b3cc3218e1a05d9e07086722f85b6fca3dad0dd8efa79649712ad28b3af8dd92354e0420ac712424f140b18636d7a6d9f79c7c	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x334b86cd73864c934a80f6c2883bb0a9496d18f8253d49736373fd73d2dd4f4da2a60fbbbd50b82901fa9c7c698000d0ffec3cd55bc375fabed917257f97eb0a	1608145186000000	0	11000000
11	\\x12a04af118dc12884b024fadb57f06c053efb999daaee2f0b85f2e3ae6bc190ab7adf9cb3aceec65091112822a5b8ea86eb0fb85e44e7fa699addf8d93cf8fe1	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x0c0398bcb3945514d06293e9e5f938af237bf43a271112c528ad0826651c303fdaa1708e86136aed1c096860464ab97fb31ace23b8c2d663e000959fbce4dbaf591a142dd630fc396cf377b133d82125b237aa6e6d90ac3ed938cb7f32099d26bb3365243ddc214d3ef506edcbcc07c001c4f56d914078f96d067df3a7c5355e	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x10e4ad59645c0708ecaa683651a3d7aea1119f142edad7796b08de980628191d8d7b2232d4230461da93947f406e1f3742f0145cd7d1043d299faab9f267b90c	1608145186000000	0	2000000
12	\\x68c61c97e51e147f5e13b09dc287cac871d9a2f37d4dee960585db3bc756512a3a01921b9c20884d6ce1cf7ee3964de007f3b0f1375ff1ef763658a575e97455	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x2514974fa06fc5682c5a09404273e585408adaf913ff8db8ed249c13078babc1a759f7ca93d27d8fe582f9dc2c55202978c6252d968eecdc40c088b929c9d5fab3efcb13ce3ec75533f8e96b245c67a675f49ddc3d039b763a458d3b7dfb38b9c7d1fe00661219f85b5c480d0cedddebeb0ac7bf5879fa41079322f5ddc2f560	\\xd0c79b9f20e02bcf2e050a908e89697e5fb0257dbeb5a56bae3ce3e6f409f99c	\\x686d3e91faf56d2f2a46ba33da5d8a66409675afa0c33d30859a1867160708c29a4e5daf466d2d65e86c714f7f80484a3db696e12e3610d5234bb5a151424e0d	1608145186000000	0	2000000
13	\\x9b5145a50b883bbad8f5141dad012e2450c17476604ec83f3b77fb1d4cf7258980dc128dc8414829a083a47b8fad2b1df261fe7008812721b58b36b315869281	\\xa25be61fd846611cbc2b5952962563db57c9c9d75c677c81664261213882277459fda954bd21fde98006a0adcf979997df66058a84cb3e1e6087aebaed4dc92d	\\x04a85994b38bdde162c563634b454a4a76bd0a23cdf20f6ed9f6352f206cbbc431974f6d85309d6e352c734772e7155139d9ad3f44a969cc645da0c0a09773f510203c636522c592efd0ebaf596cc98ae08db604ac1b2e56a99c8f2d971e99d976c0997cf229697d8fb218ea17bf34f1602aa1121443c06957befe6e0c3199a7	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x3fe14d961c2bb253af0f8f749304f6578d5c8388651c34818c7c0e762b3270bdd434e83453590be3abccda31271348c5dab689863cf6accbafca1357887c8007	1608145193000000	10	1000000
14	\\x2520bbd2aa2734004835e8630428fb3d312f79c3db25011a727fcfaea10e7426493c9dde02d4138ca35ead8acbf26704a9818a21825ff852b7c1f3e3bb4d9bd7	\\xba22080ccbc4df084e536f430dfe8640be9f0214a4cb00146dd1fc50b550aba1aa174473be3d8f68e684f04c40b34577cfa00d11d2dfb6fd41a17fc66cdde445	\\x7bca0e702d4051d0162c1cd822010005b450c900851841a19f71de145b0fda85379d7c6eb9041031f3aaa0de1863724cf648157092b14a4b24464d18b8f46b73ca89d4337e160073f88b42ec15734efe87c773d1027892fc0228e0f9f8d9ded5f8c8dc400ed60a6ed39f26abf804ba2955fad01ec27c9ae37c75d0bc8ee182d4	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x4a9ac60ba7974acb189580676e74cfb90eb7dcc23969a516c37ac8ceec8cd6130eb88d4170f47abfc94fbf6c5eadb7c3679d3617927822c6bbb764fb8ada6703	1608145193000000	5	1000000
15	\\xd9e12ab9b0652ea65f36f3373569e17290635c3e0ef4f780598c8dc8d3e7dd8d937c0cd7e563f9b1a36ae81138b78e436b4cd797a218237924423963d14db391	\\xf98e3cdb558c85de0d5eacd64b4808db8bf6514cd4e71609404d18290eed8f7e8c7dcbe8b2795dc07f49a556ce891a5116be14f31a5bde262c043d6172275165	\\x8aa356843518e1990badef05320c04e9e276e0091af5c378a3d3b649676ac5c7f1aa838a179d395d652fac676e97c4e5215571002284bf524ab5ed02adb49ee9e2a5ea5a8dd9b1c5dd72fcdb4e14163631089ed8b4f64ba5470b1bd4aa80308734f7422722e3f60f2b24cdda8410acccde2d64a85b40af8218125ba8374ec3ea	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xcb4fbeebade742c77d579d1675b98b05f8989c2cdcb543a385ffaab0a5769c9357d106fcfc733d9c4a32bf8bb55228a3a3e7ae40bf93c58778ccb930da10c90b	1608145193000000	2	3000000
16	\\xa8add9510c64636809601fea74cf8e674f31580b90ce8298dba7c4a0ea15968b3e2f3f81b7bcc26f3f7723efd9f339d50f1e2aadbc81fd22287eb80dca0b0f95	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xd03b750cd0cb8b21d163b56ccaa6271af202850cff3f3be304a0b1d6db50daf2c2302d1aa42d22452d97e621b3246e9b1b8deab074d2aa71a84defdb686f533c138acf2dbd65bec54e1cf1a016e95d475d8cd0c42c3ad66a44f1340ac669e1b26b1236f288c576830a9267a108a01ec3c70c35c871d2a481be8d274a42eff4df	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xdbdb202c2e69976e868aaed3510cbe0d7b508d7c46d2858610b2cbe3f07ecebe1862a1ff41fdbc969952bd2f585a9d494266d78b2c2fe4631a658d366fd63d05	1608145193000000	0	11000000
17	\\x0d74b5e2fa977d2d3e72c9896556970839a36ae1ceaf05690f993f46b5e105030a0d9042aee246fc61e174d046cd471390690cb44038c835927a10628d876bf9	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xc1e1433a7698104ee9f2b9dae81fac9eb67683d0e2bbf41bdac0d3180454caa6b6e0f3e0ccaed862ca01fcd1621160e0e2292c4da3680925c07b827c878470e606b547f7e9eeed88862fcf54820a7c0d32741314eca2789f294a384f809c94ca3bfd8951eae32acb9df1705a93aa139b0a7dd32d16ba2eda37a6b29213a09fb9	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xbd6d225ec0db20dcc06f67537e085f510204f948a06ef7d79fa40847e3f252905bf5a4d9410eca7aa32d2af8295f1eaeeadf4348449b8fc2f7fc6beafcc36704	1608145194000000	0	11000000
18	\\x636e902f074a9a0e45ca921b12c0ff640d4c2be8f4797cd3283403a90d29262d9be19856bc880db866d79bcd8e7fb8b4d498d41ee89a9f917f0c05f9f190c70d	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x6a276723f8b691e3dcbd6d3d2b26768ee76a4893d1f71047f7bda75176bdf04254a9fdd28113cb668d37dfbbf7d39a1b96322a64c0ceec5ec52cf75657b3877bcdf34da87e5e5b907371b06ac6ca413f9a90c64e3db467698f35736ff79a4702393374ebf3f2f354f0992073fb4902f6e8d62bf9444905208107cae3af03bd76	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x92f5442490d8eb9a689c61d773a4f918081a1dfb2c4e94c48e694b2745bd15b2b45d9f967a40dfd840e533f167d89d48e1ae5d2a610ef39980356a935bec8f0b	1608145194000000	0	11000000
19	\\x35a119b8466faeae60ff99407a8a2bb5f64aec9021931972bf58260dd02b35b95a0c474f64141c0f02ea6cdbfb72437e074b26d79d071de83e2d14552169a6d4	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x44edc5c4d7029e1e601f05c22899d80b8b2b82d7e3cf0811f02175bfff08f00303eee4f89f9ae783c19d0206c1ef4a1a16cec739f781f01171567f40bcc8d2b83bd25a51776b39e934008b6be00f3637abdd1cd03c0dce271b576283a14452c21ba1a38fb9a2a9bd043eb5404def788c35ff8454b47be9fcf7116c2034e82fe6	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x121e023ec0cbbd19f6f393803e47a3c5116e41eb0ea59b04c6eaa3d27c501cb88817d78f428e0b646ed03b6c5f6ace7f4c8dadd7bfe18a75290aef4b9c272a09	1608145194000000	0	11000000
20	\\x422775c759f669a04386de43ab80ec2ecacb6bd2b84224413ac1f701bddcfda5aed479632ea337bbabdf3a046683dedee7700eb50f8c53401b28a619d7c5dd21	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xd83cd5e78842a8a9eddfe314589261f65f4fc9d0ba49cff2c1bdadbcc8939d133e342a730724d9625be1f1a8213d9eae50bf122eb8d8ac1db6dd655082cacb8c341acc38ef4d306bae4b4cc66e2052087aa67e684996847075defcbdc3b0bcca698988ee92549b31a2479533414fb1dd33abc97016bdcd86702bfba5a3e8c308	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x15229fe0b58e58c9d177fa1f24ef7cf1e124489e6de5b4ae721cf2e41b4ebdfa2b75629a2422685325718b82de14a944b620431e28032920db2b86237299c80a	1608145194000000	0	11000000
21	\\x625526511070d4010b8f79043ec16b105d2019c45f8f52bff77985228daec1e38209f3e26d1b311777933030c772795c8fdf8dad8009988b9bf4084d38395111	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x9c5b4cc56d1ed9a1c33e19f171f96038cc7b9cb72a9706708d48f152c7b3e2542275e305fbbaa7d585f3e403aa22bd5c40d97cc218685241aa01d0c99c8499e71dd67488ae0c0d95d25dcf120a1506fda708b9581b0ba59c0fb60660573116b71e4f261b8e6e7c8c193c26f488e9dd628991a5e30e714ab75f78a9485278253f	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xfb523472556e6c9d7a7436c8de9b62f1b12d1261a6161ab7485997811410b980012a55083552a2868caf64d2315af4fd448972cb6973ac412338e0965bf7930f	1608145194000000	0	11000000
22	\\xc27537e1184e3708e7aecd29a0c8a09987c15d943cc1a4c706857c79463d4ddc2db5cb04f94101711103f9df3ce77d3fd86af7ff250e828b5d2798913125a99a	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\xaf727ae5c63bde0922448dd4847469d8d91662b5a9501656f4f3e982336e10df0757e5d321b31a4ac85d28346c7e4b5e69047e663c624f36a6da1dbac4a3093f10a643635361943196b3e94c378f4c31fac342228bc303ca4a3afe97f8cb3afd37027bd76bf56b8f83c9d5613bc791663aa1aa17614b22494ebd6a88fd67180b	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x87923fb9a1acb3a98ff68e1f5add00fc9ee38c86def4002964b12d1618a63655716cd6d7ec6c96c9b896341fc1c3525ecf255fc7cd92f6aecbe3109af650c801	1608145194000000	0	11000000
23	\\x40272a68ade1393bc5d2cbf8cfef5cc13a546257581e3e8c1e5adadaa81d62e09912cece35fe0b5c79c98ad4215c27a235dd3338d3f6ac8e32f99cbe06a57b6a	\\x6347a2184be03f5953f95283ccc651dc2d387cd2209304486da77e019ee9d4610fc8ab30b491d7e0173bbce7ae90cd60576e68bc64fee40ea848c3d31c4814db	\\x48b5d2dfa688665a74d959bb300a7a6b0f45d113d213bc4507607c533e9ca6fe80ca03fda0ee4662aea9399de152d91371a4047932dfb77545dfd8e32251c03dc0c46df341aaa7983c8f75f1a0d0ff1ac4810b6a66f29074d30b1df8e66eb632c62c1a1185f74768231c80edd141a45cd83c918918276b916b5e1568f90560d8	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\x82f5de4e93e48ae8047042cd238f2a467444650f6a547f6b335095200e49b68376b1ecafdd7c096fc9bccb728df530a4e7007879993beec0b622636918c4d107	1608145194000000	0	11000000
24	\\xd91763caf62ce2b3b0785ed2d9d747f6555f12a82a32d5018f49509e670e561f9711cd8ba9941cb5b51cc2f2a136d9885f7996e96d5973dde694456423a33e13	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x18f6571c8616c29d5e3af7e48026816e62077ed51dc2cf69832eb8a53a43a198f7a7146c679f61a1384dc1e03ae19c1ee33550cb0a178bf97471d717b8d08254f6bcf27b1f5dc28c43bc1d642af64b1405fdbf726033a1aed5b1bad89219838a952d8efe27192a8eebe75301b71a696351a4dcd714c0f528a75c9dc83e66d93c	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xffb8623b88b40e97adf1c26f7799d670fec80c7f3d7f9ce945ba80f6cc878c3c6d1aa1eea3a661d938f0b7b11c87dbe30e5bc4fb9ed6dd327ccf1321a257dd05	1608145194000000	0	2000000
25	\\x18e52dd08e2588e892cd79f43c8ff486f3ee2b1c7b4b28724944a5a9a85cb8f8de0b52dcb136825521fda6f7143053cdd05b5093d04101cdfe0655baa0aa4624	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x11eebfc6ff83be70cba830a50dfe36f266f99e083c822ee9ef3a8b923b71b28c2cd2b995ca0a3e3c1abea758e4f6d72672c10281b856f62f0bec144edbaef2ff141a845d83bc3b316d3e15f6f6fe2363f840282fd52cac1731b73ef9b2db73d161e33b5116e61e2e175b914cab52edd2190de6e3ac2bc373a3ea10f48bf39e75	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xea982e8b79c94d3b0ba6f529e9f93ea2a6d07fca1a7fa759863cdcd6e984feccf7c3cf4c48cc0c009a196d882e4fa50d4a4bbf6e6608107ca072cab3f76f750b	1608145194000000	0	2000000
26	\\x68377ad630d5ecd4d1d3612c64ce6cf62e927bf32f938fb1bcca6849a7fc19f5a1e38347ea2f493a0c0950b70bff79c2a3e358cecbbfb308b555c015c4180c8a	\\x9fee408e6248ad621b61bfc4e0c812a5631ee2777cbfca8f009738cda4a986fc45b400b5d06a28b709cbc31c5f204f547bde1c3dc95eb38402488d638b0908d4	\\x8d43f8a981ce5b198b4fa1f6efb40ef91aae1ca4e59308e7c27def49f78c91e4472b8970722dbd6fd50961eec8c34707a83ebe410fd6ac93eb4ca7a4267d424eb94d37f84b0125dfd833867529c1105c51dc52d28ec6edc0327e6571b45097c2bdf18b206b446d0c6dc97587757d66003913d1c9d13a9852d3ff63cf928ede54	\\x7aeb45b62f3989a0b2aa6562a55b475459120da8243418e1c65ac28ea342e07a	\\xdcf2d1f4173b3a61a55aa9f49af0a40e88c7d06a2cf1501dadf5e94362641d8a1e6db139d969d537bf1b66f09a2e4ae7f18dfcb009e7d239856f8a574570ca0d	1608145197000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x6c5383fa9ec4dd8de1e4c6077116fd145abe9ec8d199b023414a532411603b4d7b66fe6b092158226e16b76480e383cf2170c09073c9ecc7a40fffe41c0ab406	t	1608145178000000
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
x-taler-bank	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xd6c38bb090c6f83fe797a0173e5dd5463823587384aa39d40e0fd322b5bdf8c48b52ffdc1713b5e3de4febf8e8aacba1ed64c675c14fddcf4e3a346cf5dd8c0d
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

