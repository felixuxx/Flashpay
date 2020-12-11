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
exchange-0001	2020-12-11 11:13:51.354272+01	grothoff	{}	{}
exchange-0002	2020-12-11 11:13:51.462329+01	grothoff	{}	{}
auditor-0001	2020-12-11 11:13:55.151148+01	grothoff	{}	{}
merchant-0001	2020-12-11 11:13:55.372383+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-11 11:13:59.063989+01	f	68b44bae-6cd5-4048-8cd8-ed61dc1be8d8	11	1
2	TESTKUDOS:10	X2RPF96J6JKXMQ29H8G5CQWFC98KGJ65FC1C01X55EWMGRYFWQ50	2020-12-11 11:14:00.405318+01	f	7f1f8606-f4c2-42b2-8c5f-3507ddd5ba6a	2	11
3	TESTKUDOS:100	Joining bonus	2020-12-11 11:14:02.361271+01	f	d8bcc15a-bcb5-450a-94f4-da4c525ffbdf	12	1
4	TESTKUDOS:18	X4FK8F7QV6KTW6SS14E4MYCEYHBGJV8CM2YH28NPRVTXEZA25W40	2020-12-11 11:14:02.748145+01	f	8e154379-b418-4ede-ba29-b99075c1c52d	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
3a8aaa5a-9851-4aed-b15b-67564196c9f2	TESTKUDOS:10	t	t	f	X2RPF96J6JKXMQ29H8G5CQWFC98KGJ65FC1C01X55EWMGRYFWQ50	2	11
aede6d87-54c4-4fc6-8bae-0991ffc2ac9f	TESTKUDOS:18	t	t	f	X4FK8F7QV6KTW6SS14E4MYCEYHBGJV8CM2YH28NPRVTXEZA25W40	2	12
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
\\x8988dcd0af23d86ae672fc2ef2fd5e3138fa0db8760cd454038dbbe0de4212b9ccd3a06de1160f91c71a785f28beba7659d089ad1b339167a5aaa62b41c438ab	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd70a7564e393c8cb78cbd1e2dd83ff52d152122e08c37c5c24c111c6c6cb9ba0c0630b370114d0fbf6697e97face8e3f1b3b1767856e6d538286a321b3532bcb	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5d343278e0bc985df9301d099b3690c7755f764ab8a88a49f693fda01ec3a206237f21d4d1fbe02c74b0fe96e7b9254000d9e964a51f926a3d6be84f22500ef	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa594b857d1cf45de98cc5aaae7e5c8c30e3a226024a3e8f0f2ec6469d5bf9d7033d7b3bfd9f020a165a24a9d529c45d37507864817c8c906c27cf63e9dfff543	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7993abaf20e151f066bfbb6a993e4bae36a11c35f778712b3d5b07bf1d5f95f6ca8ef4f6e7580cce52919e37336f57d79b1608b877ac31124b091e0a019c95f8	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb51b67477a52ff7a192f6f1e950e443b9d7eda2d9a8d9f7dd6066ff0219891016f65aa515fb155a33e05375939464e44db4d47340bc12bb617c10c1656537011	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf88e19886371a051c99687ec0dafcbec7ea743177388e96ba809e590b2cf719a0358e3b5cce151924e2531b556ed61a4bc95f7d0ff8fb832dc8feafcf3291d8e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xffad89bacdbc54015d602de2a5bb9c7c41aa15d41f70f123732c7508d8a17c213d6fe620258ba4d4bad4a59481ed42440ec4307dfcfc276d4bdebf79fd1d8e2c	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9df2231d1a78009df3a579a9c8707ec3818e7d70cd248e7cd4d1096fbe96e1e508647cab088fbfc487c82b5f2602ef69c230c1830fd8c9802973ac96f09847a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c0166270015c95b43e4e9ddc5a218f511b05fbc7dfe0a57b922ede6ece5c0c52f36d118f26b94c4f9f942a91bec1505f65dbf3766a262ee09a11999c86c9ded	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e6186d25ddca6132a2a08d21fbd4d18b2551c3d507ac9566efe286fd5fc8c54fbcc30c44e8fd2d722fd1a69a5c5578566875ef643b4218894e3d6d1ca668d0f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x20aee7ab7489c764346dd7c6207df8b6e4d463617cae6c379f1889828a68500e3fbb45031b27848b9cf2fb5badacb6fa26ac570723cb919b74230f9513a5b63f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc6ebec8b656440e4c5053c542ffe840d2e80d27a17fa66a3ff7ca30f4879d4a54842022bd21c1052d5ff02e4b1907bc200438a85b7599d0d029c8107d9ec53ef	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x392e4777408198f4c9cd3e8fc308581269f9f07c08b48e65bf729031f008bc060730b333e0851a35ee706a7225997fdb32e46a5da06c7e2402686a8cf22ec32f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x202e4b02d53f16b0b4674643b1f0c5084419f4609ff75ee70964db99e13bb6616b2670989ac030fb3153b49b2779f8b5e6d977b1ec8c293a852c90c97253d04d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3af4861296a0cbcd697344ea80eb5273f51d002f106914fac234a71d14adb2bc308e97af90deb806cbc3516950a1e7eb5b8f57618ab7456b4c82202b2f561b68	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab6a5178c4a91c518201208b2aa6156922cc9b2e653fad5d370e0f0095eb8c1b594ebd7f419329f78ca4720826204da386f301504f5098db99088c2a915533d2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5eac2db51a8c839df97357c0071825b385f75e5aafff8ece9d4b7a1657a8dafdd45f9a7cb4b909793d6ed0217bfcd491fd7b76d28402e4fe0ac15abbb948c6e4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda8921dc68f2e68290aeb5897f4354a0c6b47fbf26f8bc3fcab141ab7ca65ef054bccdc4e00f529586e4be557ed8aec5ac058db0fdd1edd5590816198e35e709	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x229e3aa915bf5ff11cc02ea6b395a51392740da35632a25fff1c9927edf7f6be75a21035a90aaee901408c24bf5fa8e3664488514bb5c296c296987e86b2c952	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x26ba8a53c91fd8001b896242ca2e94edb3a7e5e2d65ef5a35dabb5c031cb6fc494e5f39c8f6390a3e6f1be8911e34e090d79a13862b3b27db237913b070bcdce	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c832e7b7e60eb64d6ef2c232225db4c322fdbb61f4bd449d2055b31ab9f69153076c28398efc0c408776ff6aafb992822489e6d86a2146ede8b99c2101081fc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2944bed31b72ab8fc732b23eb37d2f45ae2304f80eb8c69df5c5850ee8e70a4118f4e0a32c312c1b512af83f6a4ca0dff50b477a61fc79131b2128df764a86a4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7def6d0bf6eeb809e72b35e94d0973c41cae5a69f4a3f987a463d1023fdacb594c6782edf4b52448514918d41895f26218930cb7319bdf684b2d36533588bfc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfe69481d6330452ceaa787b57ebbaf789fd38df8aee5237439dc0f8959f3df964f8b8fcd61c49f21061df23bbeb0463c2a4a1eea994441d24429a013dde39e7	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18277583b8ed490d034ce430101f184618e7b9a7709ffee035881d170f1bbccd61de9f2987e8d71c0d96aa080326681a553523d6de60a95dc08e3e41f1727888	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd804deb79bb6dec287db6a75d227bab089081c4d25944ad3d6b943f0ba87c0b9728a4f66bed3f7fec9556740db58aebcd423bf3abd38181c4421a5d9bbc74038	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ee120585845bc376a6339548bc29873a170e6a132ca17119f2f6afad6f867e438d58f2e1ee60b971029ea322b69cf98688e3e731e1394b7908ee46cfce3bcb9	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b64a1b32ac73879088afa0228326d8409754332a3ad8bc7050f56e5c547b784c7e59d43f3e421ba9777b1eda10965426336c68198fdc7bb7381debef6c1ebc1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf17e08a000e619d0d0e2258da684203c024399667c29eae9f2bc68c9cd3cc7598f714f8ea1c0c768ea513eb3aed745c71d7145ed1f24bfcdb3d69d3163e19de2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa5117b62c49b7def4a493ea6c7f2b21715599209effb1b9454378f777d06726d3d43cae4ac26783ae7402c401f47997282b218767b3ccf6bf8b77ffa8c366f97	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd192a99ed571965cb357dd442469307874f65da256dd1cc0c28b5b66aac8a0f99f2bec6ca932829d156a0fbfad0113a8dc42070e1a7d4e9f98a048d01956a77a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69ac290af922eed490946a570544b5f384357ffce6291802e3a967981c9af09a38507a4971ebda981ca682a58344bd28fac771ce0975ddb619de4f6ea86739e6	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0cfc72018b21353087cbe3a8ed082baa049de7d097881888231658cf8de7a952781c0cbeff1e918954aa5e05376b188a0d4ee2a11b33b4bbec41157a1d88ba3b	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x27a20b4c50563999976bca4514760b30b585eb6cd90390c52b1a48fc2fad607d99940c31140eab28500362db1eef056cf29234f9a52bd70cbfe845fdf7bfb6bd	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x37e9e30c57d666ecb5bc6dd30c863c9a8255085e6cbaead57915b2af89e2475371bdc94b8c00ed0b7d1ff962e5eb92fafcf052c38b633c4141173932532c7628	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3ce632ddc9ef26919e55dc8e867f3c9bbb08413be619f0baa67ef5e49e6ba5d74fce0c3336760323b17eef2b453248123bb8acd39beaa66342a46aa212d7d860	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x70c367f45e831753450dd3d54695d41df6bdc7ed1d949905f66efd312b3da5d650d02902ce0263af4b0af2e856de6f53b21850b4d773cc2c02724169a3267128	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x204f0ad070eaa6dc026b9d0b2a7736e2b7089de6ff629e77eb181b0f0558b3c13f72e2eeefdc2ff0e6ffa6999ac691f713379c539db2a5eea610fa6683e60b57	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xef40c7980067311db4ac7e904eda6b76cdfc66e63408e2f07f611e66adc9fe4a8be11d4f9087f88571d472c333d17459a646518818500500f4b853b16f42a1e3	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaad39a207a98087553524a012066ff42fe12ccad1edfa8c234a1483788acb1df9cdb72731748591d212c2a3a2533fd21d4d271898ef87183718102fd0e2cab4f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4287dd179f10001e91179fc5326a6b4052027593dbeea9fe9b16608a73d64a6f52f97db0e2f02e38313a9747bde35c2714f4e0f7d5e45c175247ba8f49326bc4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x343d8fe04fedaaed99d3743867774578f2404d2fd51ab2b8372e4697d032bbab87b9b5d4f55f90c2ae127a4147329b60e4514d3ad3ad606697e2aa00d8bfadb2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2fe6b69d0990bc1e5f5824d7c0e2e11be80da6e13c4955898e37dfe052b5e9f7ac1af356e8a9c07b8911b9f8dd98fa076add958569c34560f1ec7aeea7a0d498	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x879dd3a7f2e2162225c8232fed109f65a00c9ef7f1b2a9cb5724c6268aebf23d9f819d217169f010a21dc92579f650969f2efd49e6c2366b4c5eba5c4a7113d1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x196df2b72dc5c8b85b736df9793e1f1854f1244970bda1278bffded204b7d91e8871288fbae9d2166455f37ee637763497fbdf9bf7265912c52a6dd25bf96165	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb269c258f4fcc31ef2302417d283e641ac32d417224e67de055726e4fdd480a35db4308f7d49c655f5e1afde28b71ad33b187afcedd1359fa907a9cbd519fcfe	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfd390f7f384d32e6c5987ff06eb618a3b69bf2835738632c5797990294a6d3f0ed106249d813dba621a177152165e3bac31925e9568a0ff03d3cc71fd8f454a2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8cd324bd19789a78129c47ed971cffedf47037e593109dfee9a3218e23e0ba2e5cf48338e1876fdd72b45e101e5a994c6e9aa5a7a4291977af5a8a815e390ed9	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a5e9b4be9ed0f8992290469e3c8ee4202a36bd04101e8588fcf10a28b268fd5d496a73292cf7931f227f4b1f1d609771ab83eee9a1face7f8ab42a641f3aef3	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x48106cf5a9bedab43ce439e4722ed38e8655059b42241e8e983ec736c306d1248c75174ee1ed5036603b664a280c290b3318f3afa2b154cb6e18890b03df0b3d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x794334d8f67540c4337da73b6a1988a63477b73306167796b07506097e0b93bf4d4629e523089a9e910bda909a940b793c134e92014b657840a2ed828ca8464e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x46ca3cd9afdd1964223e9fc16a4fea0621bb7838f88e29c10f564e298756a4a69c4a853ef2dd25c3e64d82417f915a96e30699b9e0e7ae8fe5ea43e55d36e070	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xeeb2c863d4f374b188448ca42769a3609626f7dca56386b937402358f9a2c727d11741840b2564d2dad5101ff1b5166ce38dc3648f5ffe83e51b02bcfff14e62	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x715b56a6fef302fd513dc7c892dfe0b197aab4acc1fafba6e3dbcd44b8989a13512aff4f1f87ba56fd4b9ccbb2c667d1b8124e9e92eef8fa7dc0682c734abfbd	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3be894638501105a02c8dd7d79648fb076f6a4800a183818221b27ff5391d4412904dec055e20335b5f791dc5c14bbdca5b50f0081e5907445113e57147b1c91	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4d79e1df30d64c6dfe02a9353643ddea1bc4cd4c0cf35fe6ce3fd67d26db5867aa1840bd57075770af8dfb76948484f28c538a9e5c2db99b227d634e9eec1003	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x193e6f406e39d93a0b0b5f520cdc0419eb5f4fa3b3e7bedfeb280574eee59e8657b5496d91cf36d227780b58f3a970ad2bcfafc85d173b389f06f2351fd08414	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3e15d9fe844d7ae0c975c4ab2c3a122322d4dc303354860f61ac100497037595c0aa88b58fbe3d370a39385e0cff115d8731239548bcf185d65da9666b073925	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x207480d7aa64a30c2aff25d9f6a6fa6d8f6fb21aa209a8e8d3ea010a5028ccc31859235ee0cc617f101be8d06804f7d814b5fe39d93e3a6f6e748119211dbcc2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1ac50c50ee7b6733a663baf05184b057be0f380e19e53caa260c618761b957e94ae05d698776dee9b61e05ae3ffdb0f2168cc5c1eb62ecbde97a3b4155096071	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc618a809cb795ac452b8bad888577c56b63bfc551962e8b51bd60be2f1a9ccac8bc72e7af6c6c77da91b6ee58e24f272e16727e01d2df79f545bf6479e9690b6	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x858d811958c974c65b150ab4ef787d764302ed486b2da76420c12ad5852abcce50645d27e720d554611134ce5d09405313988d82074a18a2219c258cbb62f4d1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x08526dae405d9338c1c71e2e263a5e8d0f7461aa582476faf5c61cbf1a3ebf4278a428fe83af0634090d821243a24ffbe6432ac4b550a58cb788b645a56cd910	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x01ed3add7ab2095e56dbc5e59641c3b3f026d9f89736db2e8ec50b6c4ab2a9bda60b36e92e9b69a2538c5c22012b4dc2fd85eef1a38bbc32307f9223dc2467ef	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x47d8c0238da54a7789df565ca0d04b447e55a705a859d1a775d6a15c6488536c4953a6cc9a8a7b460c84f2224edaca03f9fb6a768784c6e834d15c579b559d78	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec808800c3bd0ac0a42f2a0a392a2826ae8b87ce92ea0fbb1050b71d2fd2dbf463e08ca58de04bbb781e9cebb1eded0fcbe7e1955627dce4665b8a7045751b6c	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x767e8d3facd58aef4524b99e7d751fa0a61235d72a3f40921e8df2588a3d047688bb57d33b44c83ea47cf3eb21b2e6536c216eddff48793e329a990e7effac8f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98b19bf157589325860a460dcded11bfc43641497471abc062b4c1fdaf295bdc78eb51a506b38ecea82d460d598c2e67369f5ebbcf04193cafcd77056f043a9e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf80e655a12e179f0adf49db1f6279ded961a2f633f1bfc6cdc6abb6a29460e2cf65dfb1569bbfa0393001185366715d3de6ab5d03243731ea5a1118a81958a26	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x07f9fd16f089a6c6291e48d05f001bd5fb4ce515fe8958f8b8891371916099bd669f6a67234f306394d3d904d3dd376c79e2ea1690713ec5019df4d14525623a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe95af8ace3a33a575deb21e665a27ad03ed5ab51062aa7eac67d9489dba0090954628b383ca1ef82a32bdf9898cc98b593083bd100f43027dab6d940a409aefe	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa315f4420c6829e4891e858c736f0138c8e964360787bd434620b3fe7bbffadfd181b7a588191e3799369f6a4c94a2e68b9a5fefad84572dd7fca97fcd1ca291	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1019447c2415cfcf2190c3c57ebd39be473df56ef5fe155cc89aa3e7d83d3c3a8158fd27354155863e78294afb07f90de06315f964ab60bf1dc6998f2c0f1397	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b83b2471b38daa0192cae7d7186be566e102d18be32c02de1b665ad17a13c2e57a61b5ce4756e8dc244a78e2190a379fc81d5a817a1f5506b8561d89475bb05	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c5e8afce6f0162515ad19df73a06bedaee6795773092b5e67da57ee2f4eac6665731283e6dff0909a0bb6701a863d5bccbd0c4680185fcad130717e632c8624	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfcbd453cf4b32fe87e3404d4e54579cee4e4c678ef23246d4faea54ecd738bbca328ed9989e0a77fcd20e2561a696965e601bee75afa3e4fca1909fb8fde117d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a6605e9e414130155f920c43f6208bbee28d7f99d143767dfd616639e62cf5bedc961c36650d57d974e9c60e10829ffa81561e9c15be4a5ce100d9c7c1760d3	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eade8542aef606ab70a91e37a8be060956a75b0c82d44c85325e0c82ec8bf6d9dedf5851faedf28bba47ccacdc342e13566a6a26fab341e0542b52a52817a43	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5bbf727a64d93185910af80bda9bae4be22e7e22abc38ad1c720242857b85907680a7c2fae811931aa34fe2ba941731b62e8701bce246f09e522de2fd4efbcf8	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01dea51c79e213240d488891154667a7ce8d5bb2e43fa70ab0fbbaf6a2d615d290431ed09dc6646db4906b373532de8d5019ebabd0cbaf5ea756e04933662ffb	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa512bfe8a12354bc9f71204c8b52c7a9fcb13e249c74b443e3f7b6e1237b4da3c79ca8444bf402e269cf2551955585ff349daad232a135e21084a910cf66a17c	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fcc92c8d6bd64ee71619e9642b920ff177200b1989506911913bf2d68b7927035082b18ebe174766e4b8572b26b818e8dc2e729d255c91df91f8ac29aaccd1e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3819d7c8beac993fdb3c7e068a40fa25a9523590d358a914b64c9db40ab0b475c46c57e075e7f4f7514f19503503092efbab1a13ff6408fb4e5c43d8cc85e3f0	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x78939bc8f1f5faa7726f7809f02179512a6e5d00ed7263f0e0e7ced75eb0390ddcd59ecf79ba03a2240a4b2539036b8ecc0670d3fda6465196f8a0b6cd455355	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa374d0fa6338e581c4dcc0919ebaa651cc8be6432fa6b42dc7bbb965e17e30e744f30f64963d2cafb0eb855870c5aaa3fbaf402484b425b0d9c1c15eb005143	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d74946bd0240c68f28845168acf563cfa566653240679d192ce3d9c74563581f55c60d49fe72e31c3290f2a1434cd31862464e898f9a5fa65c4dd72c965c009	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6fd27972e48ed9b0a42c2daeda9c470d987469c97c57984298820afff2a91d96e75a8e837dbe363d92eab3e7dfb22de50b1a53838f61868d1e3520c0e3a31d58	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf46e41a1f8a59867fcc75bdce6239a00e4cf8b9c6590a52e76f43e14495ad5237b1b9a2951bb5680a7e09740a2f45747e745c23e23db6fbfb84423500b30b824	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3fa67dfc15bb335b6cad849420cc7054a8129c21e4741c416d09e4fb05a6d37a27672b55611ec62b5b156f1f6976ce218dae55104bd093c3c20600555ba9f25	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6223955bb4c2ff1a724a63d2ed585ac9fc19595dc9dc6dba9ce721da1438873f8b1c4e32c20d6de48a8c6288d7a05dab8ad2052439e2a671187a659a653a41a1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x453a722fe6e5bfa748aa6028fb0895418b24547ecb0abb8a8cb05ca9cf57e6c2f5ae67d2067449743584f3f5bb23927267e3f2b225a2827426aa4cba5475422e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6743e94d54af52d0ea7e0b8f1689e2bcf312751f55c1380914f56979cb36db14f7cd98fb91b27a7d86645a8aadced94c9ad997810704d297d004d33a769e035d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe12a8d23ff0ab733767f867487d0fd3e9d9ed2339020f69a457ad996d9bf9c66d202254b3f62a48b0db24c316f1446accf217d5c127ce3f475bb8740ba21a3e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2de9751cc612f96ada0abc942ab85559bdc094161cb6bae34e995da102baedf6761a17b5a5429f70b215cc81f1d6bf684774d7f4a4f74375d3fb19b23e356d96	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x867869e0737b6d7153fec40787afcc9b12eea9802eb847d1d1118d28c3f531d10667e9d9f96f6db16ec6743b24f385085babc69c7a84891929b79570c160bc0f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x886534610c4ef4b9656da37bf96466047a1675bb41bc834d920190322acded183450b0bab1d98ce3f02219db44c296572bb6056cee4f5e49534964ac28c966fc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x670c7c27dcfb26d48042fdd844ab49f89f1790c15f64d2d4a4d1cd9c7a8592dea83ed9fdb8eae1b5be8052c8592f688a7c39845435f58d01a8cc12fab54094df	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d954b3cb8936924e860b29f18db3d8f177911612add29847085e3d790ba9fe2783a992b13e7cf98c7bc97473c8246ca5c1a71d3aa593d7f14b7d5edc9b68ff8	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf914bd87f9b081466f92f1223da370786d4a7127520b39bc67bfc10019ca0db8f6ce8e7678b200747a306ce2921cf7c5c734902418aa199a090b3874ffa0520b	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc4232412c0c8c40424cda551b819b46d7e300b8c510099d95ace2a356cde39368765c8d2c04708098317861ef2d3caefda85a5c78a47c6d64aefca53b4b3ddf	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x79ce5b598a27240e5c20bd0da36c812b4c38da8a7cff061cfb162511a9d920a88b38cfb912994f5c4cc6b54cdfafc77ef1d12e4b1aa1b9954c00f1f010622e10	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf27f8fe863e8f67bfce1abdbcc7fd3bef0128bb6886d0454a7efa7ba5d0c47a3d403c32bd73e4240bb7218703d3db37f980039eb7f70108b04d7eafe443d61d0	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37c934ad930072060e1c33e9bf43f7d6b12700c12d64514b971657bc228439c747935ff08c203b74e58fb8f778aa7896fad6f74c9412eb29396937e42b13db5f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6c8a931649159dc2fd0ff7c262e6f70073a7a8ae1ed0af6d33204b4e1ce6a428edfaab93a099ed40a735c829fdf7588cbaabc2cd534f6667044fd5d448921bc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf0fc0d3d242b551c685ac73b608455b9cdd5bc7087e9e184727c091cab102aebd867297dba49248661ba5bd8bbba7ceae976151388dd7674ec28526eef2d54a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b682043775d844dc25cc48c483a39634b7e95900c23e9d62f911d60f692ad35c4173c033e8938525e5d516da12af8cfd395c59dfda2fdf024b7dd98bae81698	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3c15f24bfab271e452f71b7c5d47c316287b83eaeef600817fb0574793d5b52b08bccacd20f4bc6edb18c0ca1f5e4d2c0c9d4e451e02546295f5fd97d6230dab	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc4094285d3570716d020297a879cd58410305a71fad5d7a93362bb03a56dcec3be253f78d1c4c87a52c3ec67d0d493b7e9d66fe6f46162e7b3e559b76b665742	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe20b3710ba4bf8579516e9b73c750d0c9e1d2e787e3031d52c34e3ec5514935fe45031a95c08f16e2ea1955599e997a85b885d067989a414358085e15e9a21c3	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfdaadb0b814afcb3a87f8bfd03296142024c6dffa76eb7ebf34a96933984bd142a14d1f498444372afbf34a00f06c7b7dd9a48bba2b3f8c9a7395c5ba9a4cfc4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e125ac790386edd1f8726f54fe259c4be3d0ae5db405bca3f6aabaabaacec09e0cc806d50ab99e158533efe33154b82fc743a64eecd20dbba4642439005da96	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x64fdebba7d97f8b08d6b096c5566c645cd8c593ecfa532153552fee0be243d7b213286b44712eaf89b7cd3df4e0d15ce88952aba9cba02af006e522b40df7166	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x184912f725e20fd007a7da540b280d3836b58c9022a9f8c402207ff91eb318abd7f09c239d98e8b0790b67b987afb8807fb99a2da40de32ccab579851a455413	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x00f5afa9323fedda03bb7ed5e5171e06f89ebed4c5da9b303ae52b750235759b03f31a4a24057520a41679f802d87abb7781323506e0430d57ae2bd955c13f81	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x74b27d8dd3458f3a93384e62e226056bf03f848661798b0c1a4f4d4a90c3282c776d5c49569468e0b97cfec80cb71b6fb82c389c0307f20ba8ae17917899b4a5	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe1c12a5e2c64253120be104af0725de57b9d449fb91ff579c0bdc2ac3d3c22bad1e5835c37de9c2a93a430800199ea8d094c72c680cf868ef90c4562a5b4fac7	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x128dcc5b29aa0ee1593b492b77c5c3241710b7256693472f529f8962b8d01d204da69223c99d9d81f9d319abce48f58fa2463d1e921d6ac9944051b55bc2fb71	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b013c466d8c2c65fc8b73b3c7e5cee2666f7e46b7f408459bf6b2f14e06878654f286a9e6d5b2ddd04beb70c033a4e8c2b2e5d80570a2a11b5b4c5bfaf07002	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x948224599acaf38904c7b0cb8ffa122851ff8cac10da350ef49e0179c7de12658839b53380e025dcbca6424a8dc1947639196748432f4f3bde2a95f7ee6c6e1d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xea2034ed0e15597f775eeae127ec4cc6d824cef55487b3c08e05f2d34b99fb0205e98caba1f9bc8f1ab6ea6ec4f29e3c4227e20af2b318597d4b048aaaddf135	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc4fe4d113a71452a8a6beb728f7f10e8bd80146aafa856abf08e336ffe582eb48de350be6d0b720492dd05123562f9ad7fcd09f8774e48d47057354be9d610a6	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc555b3d48d715a00f8231dceb948ba774267ac2daaf32a04a17a98265dcf94ad086587a37317ee01f47d6f86110ca6c2f0f2de14eceafd4a1b0b85d4fd56f194	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe8b93c0d7bf3edea2811342a8864208d4ec7964536850fb16a5e72a6498278e9045b8b2330a5515421b2906defb2da3800d3066e55284bafd25d2ede2712dd4d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd979e5c581562cbe48ad265da771f333d82ff81ceb0acb6b23eb6e07ad9ad259fb8e213c0bc103d11ddcd931a8a4c886057d72c8d26d74baa7cc9be45d6efd44	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa8b6ce1fafd82c375f46c3cdc57de3d6d51ded575adb438bd6d1af664b6d7c7e166ae1c7504cbe64f6be3fa31e96c00b54d81e33bb4db945c2a55c2281aed359	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x77ac31192d880b72f1feba78691c95d054a70e62331510e9f7bcb4628b2df0d26cb1d042aa2b28f2786bdf8862aab24a50049fc85793030e7f1e186471c50a31	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd113aa91fab56e0ea12ce409896daaa4a870eea40bf292e4ed3f6eced424d8691dbcde73afc0a37d5698358e09513cc7b5b3dfaae74d4a337d3b4c9b42b826a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc067406d75e02643fa2f4bc1bfc3c804e59e57a5d0179a0767c0d5ecd11de0e144ad9a7a60ea73442d525d253addec67d1573a9713770aeec4bcf257b43415fd	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xabb5b0b8fe7c7a8b964225ceb80d3e1ffd9cccf091263f62d5135df562b0fb50fed8431722f15065261aefb31f91172f73fdfefab16c91849afa3c044ad6de55	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4dd95f84127b06fb908cf0be5ea29addd28d4008cd0f3a01b096084b8db6558347af46c81235a67254cced0eff77de6df9d7eaf13dcf4ae782464d05255b8e9d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb44b5f4449997da5eda04a67b86acaedeeafba9beacb408fd126a622292bf3d38aca96fed069a5fa694c22921fecbc3bdb868e71c11f46ae07ea218d44a8c4b9	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1b658134b0435bcdfd6bb88389aa25ef418a5961362dccf906f447d3185fb64230bd16123c00eddab5e78f1b237ee82075755b47220594ac51654909f570092	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9634ca6c359a7384adcf391c18ac8e57416ec127f90d7023df31885ae1fe595985fb6344d5a99ee6a28e870a8c3d615592e40ad2cb719b96bb146b4b6adf193f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ab3240682324edb5ec7c995ac2fe329bcfc46c2625147f7a52820fd4dad1a2f7c982db50e04a80847242f617b5a4a2c55dbfa35294c34b9708097c786391ff8	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x73a42c48073256065d6f936a5540389080f19d815b553c5278b4b456a518a2a465707c8e3f98171518384df3abd6a5830c8b3a137a7f759d081c702928252a0d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4a94a08e8d1879c332606f380a99298ca379c9af095b7499ea98839344563be0981b6e07186cf577eebed8514acd66c5e07bd4f728d8fa1860232a5b0b83f6a4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x050adc39564fdf2cf4432938ee87932b2a9868ecde5e6573dc200c419d2eb705d5da14f3d22ac5a0b6727ba2bf9f0bba1996dbe0858247bf6f2bd528e0101589	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbbaca6d90aa54e1d2c008a1d4ddfd57796bb9748d9d987396600955090e269976a9c4fe9a964a12fe68372257e1a20c139018c6c87164b77fe20d73a8e537011	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe70137ea4e9ef7069376ce6b3bf06a8a0586bf56d20a84fff4553afa47b0b17d3cfed37da2e00bf14eaa3afd0f89baf8e842b6b5ab5e94dd3d96b1f735e1ad74	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed96c91380174cf45ee8b4875f3bcfd1947281a3ebeee195ec995cb548828fa62d09595beb93123da9a1817fac7f065299f8aa964180bd8586b8d8ab124b21a6	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e6a127930849566904337de8fdfc157e2b78f0d3f1921f4141570ecb094a6584f45ed0f21a5785ffbad774fa014b4140c26b930ea5b9a3e05dc7ec512e60afc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x48939e2cc6ddae76022d6d69bb2f3ba1df948bb0cc1e1663c66a33a2d29c2eb4c3fe197776325bb5956d63a8183e084f6bc9ee62abd821cfb0a75ae41c035e36	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43656999c1e514eeadd116f3247f82555d28ee9d9ff0abd83cb2af66a52aa7f9d2f9cebb71f367d9206a8b603113d5d610dbc6e928b68d714e9498df8e14b923	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47f56204fccb541c9a3656190daa913eb37a998097a395338025b44840bd1964a3ad9a36548ce60470663f35ca932f910fbd12cc17c6620f7e508eead08be813	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x477bfdbd6835b595af8eed59fbb0be6425c6a156651ab1ecedc80e08ae001a51c8847d1004b3810af462b55f32bfb6f4d2de17c5eb63b909388b019da3b56e55	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe1378e8e82cbbc75cf4c86a071c66d12ea4209ca8ce4aaed3ced753916ec9fe7d335f9d9bad8758d46ad5d7350b2863f27988606af19fc1bdba5c803d2a22755	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0b35ed65caa93f6b394fbf80af7a2011d6e760fccd1ea1b87dce0cb25984dfe9970c707defc6d43a6e83286dfb9b7fb46a3bc3fae3e5f201357cdf9f4669a905	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf400435fd51a432cc49c591dfec7e525a1553ce79c0b342cfb5a6a5f419b4473bf64103dee314d826af508c18e8258a24caac2fdfe2758f61a20ece9563ae89d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12192afc25ea0e27fb1d30c605784768699735338adc2870726030ef23f0415f79c388d1141ebbe6fae3e75e64b60efca01211843a168ff9701011b525f12142	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa0de64270c193bae3481109d5df6581bbe11bc947450a10d50e7e4e105ae049a74cb9634544bd347f07b43bc0083ff8f3c87363df8c9a24c52e7fcd3734e771c	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43d3a620b4eb53bf662203318ca78a75f15285f41690cd025beddcab6c382a2563339ac0eead683dae4e2eadeaa0b9c84bf3568ed1ac7422065f6a87a84d8657	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf54420caa89afec2f666f3999c8d0387054b150e032f1a70418f45a967d8acfdb85f589bcc39b3f0ae149b4f1177d874a752a76dcbc8032fe5171803f180315	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d56ea790286aa5459ea0b01c6c4a3f74727ecd2390d55d24845c5a146b61fc0faa7551415ea130c27a22421d4b3acf0692c2428c25c03928786bbc6a6a981ff	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc36747fe01951c71b5186cb28be0b117e17a31ce3c55e5025462ad60a72ece2e724f660fb333b86deffd3b61d5fad93751a7e0bbacfa340014fa80677ae29334	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe5d8faa57d4cddcc730e0c7417ac542d959d73f365d08259754de01cdaf2d4d34116048b47ac04271f3ae6502098d3247a4dcfdedfa2ea57f0fb3cd78050f67a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01ef39315d4e10063fb13d9dfd1e46608cc1c4e238de5f89bf7368c2d065d68e5ded73f78c009fe51739d46bca096a11a89dd68ecc185acf66ca631c3adc1f7d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1bbfef9f1be0c710860181eba8069c89058d8ff7df78639ad3c31767076d0720bf2cd19b18d0dcb914448fe8a19b5278e9b0a33a28f319d16343d1b30d3489d1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa502e242f20d8f027829ae23a72da67e9d456ada400f487ab6a4c0ea5dde9f2f24b19e8525dcc18df5a442a3d1612058533f8bca751e872b865593b66a240eb4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x66a6ebbe6fa03a4979313b8f9ea98978f28888e7de4c214108c04c81e1ccbd8748867ea7fd072f5793d3d4fb576ea49fd52f5797d633839d8ee5dbb6a2be56e5	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf38d96528fca3517bfcbe2be396392c3639a604883312c1eb45e1c18e9dcb28bfff038ff1d503df67fc1db8ef20babb178c76729f7e79fc151f27582cf706418	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd27184f770bfb11ac81a4302956fd1eea01203d90a8333bdd76483ef2a7bdf394306c2b10a7c53f6a3f0106a29afdaab24ebd3b79e126fbd3f59b952cf506f33	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafde70fc196cf72fe9b3c521a227ff1c07bdf36d23534ba73515b3bef3d40a05ab2d3bbf50777d09929e514503f5916870d2845dd0860f6fa0ffd0f8b1386a5a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5bd70aafd1e3a3d79a1be24de986259bba40996d81047fa9c88cbd6f00d7b86b8fbd2b8cbc9c0aabf701e70eddd9525260ae3d909e2df67ecd9c6d61e4d211cf	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4fd4f431f10de60c1595fa16bb24877e76cc82751019a7d8ba44096570132addcb8577eaa5a2b3cdae063d8ec310f6c617ef613d2781fb08cb7cfa7ea1469993	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x11a3eb19bc7a7a6843734e389a4155bc93805e7eaad70a05db28137d882f980284274ffff9ecf34b4d9940591a4b1ab909e13f720820967dccf1e85ec49bbcc9	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x35695b77e094bf112245816a8cfd53bd0bd5e27f0ecb36e184d979f8ca320679599d52114b81ee1b95fd9376fcdf53a2d9ef6e059008936502ffbd1ba8e2a682	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x59d05edfa818e501e721108f4cda7c61c1586002d03879d8ee74295350730f4e83420cbc33d4181c3a5424818ea863aaa06be36905af0173b5ebdc0212adfe9d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41254eacb5fbe99ce74a761437ad8b73f95686d1d121e84b9959e983a803e1e0c4971ed5236b783297d23fb98ee1d26fb9eef766cece44da261268dfbc2ea1a6	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2cfb8289f7a5f4e7cf645db537c8b7fef3f133e516031c91932452e1b0cdfb9b777da43651418ce9fce5fa9c7467726c1ccb8742c65347eb22ff0d4a0b896985	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5056af5f3785b2082efce5bb602cd976bfd188e73930c9d8674561f3216eafc1956db9709b9b3083fa8b8e69cceff9d0376d6c795eb5e3df7e06c50eff67b5f6	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xadf6bfab8ac4335b3bf4d90b91017f03cb4ff5638140fa4c0c316c722e34468cfa928200805f2c9bee855e42f291e4032496c02d38b67d7664a1625bd4fbe177	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd2ca24fbd266a610adb27c89709427f21a9f599ce646e23b44ecacca1679d0940c66fb4708d184a7dcbe261ffc90eaef1c7901dc11d90884373f4c794e280a2c	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x64d19bf147d71f5cb255f2537c6c21e26e90d12c6eaf23b7676abb1399f0473745d648d30012c04d322c5728f1ff77c4f941812524990dd2e233c559bb1c4eed	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1fd067ecc1135b4efe96a56a9333a89ee9653a6561d371ef1b1e350494cfcbc1dea4bb0a4a259df47f72c0fce284f631d082e07074fb20a310fa5421efbe78ba	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x95c75e5e6e3ce077d9ebeb9450b2154553897a420d456d722f5a1a21359bdbc7692ce8a740879373429917e5884b8aefeef4bbb9a054184c8e561566a437c048	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x895a5cebf84daa416eb3ed391ae31f1448d4ceea597348dc5a0099353cf77904d465f32a3d423008a8c5de78df496fae04b4947cb412fcba79fdb85a4f483a33	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc60c27581cd4f115459104f194dc347a796a025a9625650e7fcd41bdf517598b543f31c1f9f73eae795f9c8c05453fa4036edb2033c40e5016c388c0d9463a2c	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x35ff6c5b4c1a622666460abb732ed41a076e7718732ecb0bf0419e6a91855e0dfdbfc79f6ab970d5e11e52362382aaace0883013ea37cb9892233745a17da126	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x363b77a1588987b15aa6f9e54394b5378757aeb911058cf8c138032a3e750472b3a11113ac2944a9dc9a27b8697fce293ef3c2c6739d13470938c66cef9cab05	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0df2375119afef8659664098cac2d81a1a2d50343a0d7339c28648bc44f846660160079df920a884265d68b04c7393670c5fd2c77ddd61bea2ea8b9861ef4202	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa5403dc186ae8a705609a219e84c7be9bcb8fc048788179942274004e93a75a8d0ec5fad6f4477c4a6ee90fe0dce7f6be77d2443181d684687992ad3f48cb650	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x317592737eabe99857a15adcb3d7f0c727cd00d7c003d732ca20cf169388a8bbf21d5d1246487a02b0252bed14e55684ba2a79e2e443186bd71d8ed7306c3f40	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc7f1927147b45a260d604be54fcd472078b07ec9720bdfea0657393fda0eaf51cbe9f091cf6d603242a6272e9fe14c8c62a9040737d15eb806fccfb51a9f7bb8	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xce2a6d4f80b5e8023eb176fc85f0c40960809bf903312e79406ad092184ac12c9bd291a2a64b5693934748d7d1492c0c80be501f8ebde83064ec7c31c0c8e399	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x11ad52ae5bc5cbeee728a65ffae42746f413224b1e81f2977103d79f861871b82fa9ba9b49bd6591f8526717bd6310be1fa00dc7d1ec17dc9abb0098763f9204	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x10b6bb26d4c5b8ba25354a3c06443b1064e5325813a0e3cbec04dcf56204acb0f4ef2bf04f4030ea5d4b6402fce2a7f27b6653196d7efe0386bc85dfca2d4110	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x61665d8480d0fc8f06f7309c8f6434b225139713d7cb352f8c3d654a491be577329aadd825c4e344cbe9a87b4b406bccd69a64c417f58dcf11e7d9940c4c5ab7	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe63c11aff8024a786565afdbaaced8327ecf4d7f549f91cf4b46eaa480e624f77bc9c2d2953eefe3d8c2a50ddae4efdf57655a0482843b6d70b27be012a48db2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x30d49135ff14ed7dcaf3b6e3da9ec9d4a1d960063c518e795309dbfa4d470fb9cd896a56a8e98820a7562a758fa32d39d1acd9e9c3bcd6fec370b5267d444dbf	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x82ec94be1308f93bb545ac4aed4434eceedf7d466670874968cc46363294393dd4c9c9a092faebd86b108a6d002f4209c3b1b663a38c13477ec77592e48ef79a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41bc22c4d4a944e855fb1af14380d7f1295a83d3f0874af6b6d3e01b215ec3636a125050f749b75a4b527d912c4363b53f66610df8db8fbd5fd2ecc3fb5d6a27	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6cc6a16df0cafd904fe166ab48520e113081ad488d57bd7e272143137ebd1e73e8830872f941bb77dc8fb7311c9ffac799ebec3148d896d8ae621fba6525ebbc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf599bd1778798c003320b458bc627cf80eab7ecc21a0e1867472d6790bcbf06d7a8697ff682fcf600c03beb0e06b901f0ccff7672ed9a7612a28b4e01f06c0be	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5557a24294c7085274b7d023dbd9aff85f62180ffcad731677eb01819926112392d0b803680e57b2fdb4cfad2c4cf8c4ba5cff4cf6d0bb07096bb20d6ae11d00	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcc5c643dc1139dfe8b6fc2172d42ec4c36750debbb7730e5abf98975230a224202cde61c2ecd29c820d8c762e7d64a04efdfdd4b6df683920fa38d5e1717b4cf	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x48fb0cd9980af85e4a1031d031ac98978854ef6e455c739b81479b178aee6826a3a372468fbb9df8709fde6ee7f552fb7e689be545231791e4e1650c34e8024d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe44d275d581f7cb2a79d5f81b07ed0023328d377b49a2455ee67b6bf12ea5e7dd1a5397012a30071b11e13702bd191782e35782f757d5fb50b6f346a620b03bc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2aa907bc152aac2c1d4c37413714b106cfe76c27aace2c7c42ebf494876149d4b176eb7e720fe5d90430f3768bb3ce3edd0035224ee8832baf94b0a92be5559	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8e5dff5840a8a80712656143e08f21bf08ee6be24b24ad5d03879bb6dda1bb85e938fa6dc4a7f307a102baac8c6e88f447915c3786b1d453fd7fe47848e316e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x919c4f1a5fa4bed568e3d1c55a18d746666b8dbf607adccaf4ab26996188bb7982a2dd4e0ff58c2dacac534ea9bedf16ff223176102f7bb6d8b1d1217fbda057	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x49fc560569f870315cb32f7f6c4a5bb9a52404daa735101321ec9db21dca2043ac4c5eb510f2ea19435a4da7ae3e701303bb31b297a379d270fc32a3da4f1dd9	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x50e3f45e2e8f590578bbb6adfba8509ae7966cff6f547d8ce850680fcd94e64a15327d0937e4a66f90eed844d1431f42725301f41df2134bc8c817c362f3eb72	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3737e19259b85eb81acd1d64102c3200b0259f8c0e8df0ef5c19ffdd07aa3c6bffb04e8bf4bce4e71c13b640047ba916744d07ae53887c1333d0419f67d08857	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x605e5354dbcaa37780c65872b11426acae101d3867782868956c42c7109cd67e523c7ab5689bf659547012a2e26faa9b330e89be7d479e64fbd0ab9bbeac0e0b	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfffee7edafb5be716be2a5b9c33babe1cc387cff264c8046163f0dfd536f5f37ffa987fbbfcd85a0c3c0bb812a3627a90430c2865dd1e6839a93aa702e2be3da	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x09e9a37650b6ad9c53ea4eda0d767f4e3980e9cfc9f99d97357ee970c5d42e0d0018535cb54042346bb3670eda076793d8e2ead7b2b19d48eac5fca423f30630	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x154e69da7f88498338da463456e12dab19334630c259f8247fab6b2a83aa1d748f2e92d40678c79e0bd89b97cf12f9d9999ee11055c5644a4f0ccd29b8134089	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd42228a4edd5edc59fdb53ff916ce7f4dbba894ec115fb2c3dd4679502571e62486749e366184e5f65933649db9ad6ecdc233697c0a735305ba5fb856965b82	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x208eaac6643c59c887af3e3c6842c671f2c60e6c81d390d0a57e256e866420a1064a3368df78f420cc193b6eadc2845daf276b88edc5953653c32ab5361a2816	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d53d32431bdd175a32729c33a3f77798bd7bc88376936d245cbb8d801c0493b138f89e1188f9577543dc63afe6caeeab2c61fdaf2431d666f627e2275b7dfec	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe052fe3dfc5fb3278e02a35c78343797d8bdea2766ef5b0a6683cd61aa165cc48a4d50a2348223cfdf8a1a4afe024d3e3a9ffdf98bdd611edad47b47b87f7135	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xae29ed6d1690dae884e34b7caf156b29c3e1a206e3e4a8cc98bff8239c5f36ed4c7d4f1a4cd5f78fa2797b82361347c4ecc85e057833b04682eb1cf11e67f695	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x19dc032bbcbfba5c85586b0b2dea7b622bd9eb9485bb40bf7fcb04e06fd2dbce223ccdfbca539aada4d6322237ba841187e4da61f590a2bc48ca34cdfffdadad	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3f71cbd6b648ca2816304ed7124fa3bb1b79942e7512762c3f36c4c0a1f2f22fe33dd1d9fe8c46ec3e67a618612ba65cb2d962447cef2d46d4fab8937958018	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x05ae1f794f32e855c0fff2fbe4af328db5207a47910c77e7b0c4c3fdfd8b3aca5589c12e73418a95db7d3717cd4e3451692033a02b3fefa34f4e89abd73859e4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x75dae8ee8ce2f62c9e882c4f57b62b2de0300eaaa7a7d99fe106299032cce6f341ced90ff4fc550ce166e2573bb1e6c3a58a6984a814f0f76a9031fbb5f31bac	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcee19e6093e01a5f16216bca16eef72a600417c73518f385eb24a40faeab59aedc21757c5b0c1748a43629d5c3281cf13fce5557b691b33638dddaedcc8b54f4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0626e09b8e06af8067bb1888dc477d9382cf2dc823569d744768f2e7665152d1d025fc4ec3d114875d9bac8528253f1c158b7b5f186534d9a432da338aca7db9	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xab82b6c09535a090093e16ad77a397536f0d8a6f1f9e8c10267e4847c3512ffbcf245f0fd5f67b1e4f3d05b9c90ba29a3bb46f8d63d8a4ae69961d590c60915e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7a526143fffdea4c85118d3e28885c8643435976f071c2b7f5e3b7cb882b26f2ad4a700d51eb75ea4a96cd17621855da8ae17496ce6da8d7f7bf8783458036e7	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x509a2e9675233f7fc2a19fa2bd4a68bdce1e4b45fba736b3788b1df221bd6adb36b1bc5b6ced4deb5f719b52d91d0765133da69287632d07fc509e481c17dcfb	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb82966b69f736e5a0ce4c3812044f0464b768574fc844a735baca3f5e9b81dc2d97815eb2b0ca60b1a2c593e0927018ac0dcbd96dc0340e1dfd1ce9ea55ea7fc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a933bd55d5e8c69dc3e4ae5c37430c9c42e1db44f401eae087cf99060441240ead7b6424570ed17d5eb1851e659280feb5b654cf2b1d3dd61475e9f168f1225	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8cb218d5fb18c310cb3c44f6694fd8e0b552d33e9e9c1701998ae3bcd761746c6132f7cc61b7e30566e23dfd1bf771e5df03f84ae8f89d74078ec27395d400c4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeafac0f49a7bfa0af33b8882830d732eebbc5b008451fad25afc8923b87d9e0ac2b906784925c31cf24b9d229b779ea3e4db55ca25112814557d7a8df916f7ee	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe823ca32480b1daf8950dc38b5b5f81a81a91c505f23805f1c164d569ec665a2fe45e9d951ce3f72396cd083f39a2694db8152be617ba8007687b7da9679517f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a978e99b5719169ae8da5e4ea67dcfe2e81d95a9e4532c42f00cec86b72126da26be08490c2d32a23e80ddffb79d70cc6dca900f3d1c27766e5531f1477ae68	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb498d7c4302ea125edb836527fc7a93f4e0798bf6cac22ed58220d2ffcd17eb3af914960c3c3d9a8925dc34c9bc91d5683768ca36b7cfcaeaaa2386d80a2dfb	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8f61b4996a24367185f02952968924a6990a05e487567e6e400f6d69e8e064513dcc7e5cd6f842de4901c3a49fe39b0c61fc6a78a1b649913fe930e4d162164	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1608286431000000	1670753631000000	1702289631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb05fec2667665e5ccab6637736324db854b90baffb28cc71fafa11307ae6087cb9b10e2fc52e2ae1280ebc75d64319139914ae304cca745e0fda62feaff3e82e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608286131000000	1608890931000000	1671358131000000	1702894131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa406a3bae11a98d6c47957dc8f2ebcee3a339b224b9fbc4a011abd61005f7918124c7799fd8f261a2cfc57689d6ecbf9055ffdbd064965a42bd1572bfefd217f	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1608890631000000	1609495431000000	1671962631000000	1703498631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5387785fe960140df72d9f2bc1f3941f8ea45efe0c30d0f1e9387efb6b8b8160bcaf2e14a1cef96d1bb403f8d3db680c26ab0e298d51ae8787b04a1309ac0f13	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1609495131000000	1610099931000000	1672567131000000	1704103131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x883dcd1593ce8c836352d326a9411997c88ecb23437f94155ebe459d4dc16a1998b0b0fde9c1e0caeef811805674e69a55d4c21cf06c1b8318d47448314b392b	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610099631000000	1610704431000000	1673171631000000	1704707631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7652d7b44fab9b2452a5929530e6650fbc5fd0ffcfc8bad93d94a3976573e505529a05cc556335a70dd52127c6cbfea2e65d342e0ab59de5a9b803aefa2ad3fc	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1610704131000000	1611308931000000	1673776131000000	1705312131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd3bbde0f8fae8e7ebcdb8880d4b1e8091c8b0faa560c90089c682b4f796c4d3acf295ea117e342bb78f54e1198c59e5691dcc177c0e082468399f3d20f9ca8c1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611308631000000	1611913431000000	1674380631000000	1705916631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3d935fd41498834137b91632646a01a557961387590d16ee11b2fb3fcba754769de8312f0ce12fd2da96ef185430b5514b8f57004e67ba25eabb1021da2a4777	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1611913131000000	1612517931000000	1674985131000000	1706521131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf21019aec0513bbd2392048c37c2bef487810094b2ceb786b3c8fe5d9e8c9e185f4664750597f884ad1bfcdca258444ef5e3b770632952a4d70d22c9e8033a82	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1612517631000000	1613122431000000	1675589631000000	1707125631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa17d4685af9ef4b8a664e5705c005e001d405322b10fac4dd6a4eb046ab238519852e4c7d6621f5b45a27f5d67a8b7e2fb80e2123996b01a956cbaf1947eb4d5	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613122131000000	1613726931000000	1676194131000000	1707730131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x67e1cb0f86df1958ff4d129bc8472ea43e953ef99fd18f6b0f22deda51a61d6bf11ded197956122e815dad4cd494413fbe83a0ff01de69b9a0bda039198ebb4d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1613726631000000	1614331431000000	1676798631000000	1708334631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5c7e954785bcc48cfe85f252776e72a91899669a22a2cb8931a92ef506f0409837873b5e5a191c229407de30900990362407da51cd4b1935aaa78be6d3880b87	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614331131000000	1614935931000000	1677403131000000	1708939131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x43fe4d245a1757a5b287e827af4db41e251ebc9d3671fa0a36892aeed4c90fb6b9deca4fc10044dbaa4378363a33fc685bb48d259770612f97938d4a5978f483	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1614935631000000	1615540431000000	1678007631000000	1709543631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe58ed8d206a37416f1f235a4eaf5c10ccd3d17c0c815e4e9fc577c9450dd97772582dc0a718101bcf0cfbe9ef0869364836e278b8dbe8f92f7a2ee968ce7b7dd	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1615540131000000	1616144931000000	1678612131000000	1710148131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x59711ac428aa106c14bd8228c7c4555838da119125e156acf867b9059f4afcb89bd08a2f02fb6c2bc691a6b240b76ab1c4e4b7d584ba6f7581cf779200931ebe	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616144631000000	1616749431000000	1679216631000000	1710752631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5671980d05e33a746d4b520abb1b7ee11a729f95aeae01a481236e6b5e59329a27c4b4e542961eaa0c13b117f76da55c0984caeadddbcd5d2795617894b6dce7	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1616749131000000	1617353931000000	1679821131000000	1711357131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x507e680be4f2818eaaa2b342f71d5fe0b0dc484059dea8cc63ec253d9ae659d397da2c40b31a3b21adf55126ac750e2ca9e60cef825b3ab4b2d1691b854063eb	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617353631000000	1617958431000000	1680425631000000	1711961631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x55d86279d711341a01a1f26ab5a950be58a92e20027763c0b8551f0638ba755b8da95e3ac6ae87e72110fa40d1bb7cc58606a78fe50861b877b6ed8f8a8062f8	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1617958131000000	1618562931000000	1681030131000000	1712566131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1a595f439961a7a68f43a52d37d12f01b93c233edcefacb0309d861b88a27227973c61cff297370779919768d141a1108d511c54c52bd9b90887ba92060b475	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1618562631000000	1619167431000000	1681634631000000	1713170631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x64cb3594c6103b5f07ff2c414b65c9e0b1f982268da24bd71671cb74995fbddbbe83d140b02b904d8be7a658aa88cf0735d99b3c80e5b2b6c2338515ffa6563d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619167131000000	1619771931000000	1682239131000000	1713775131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x78aa7d1c1b1f389cc66945e68cba7d2ce8752f6a1debf938685cada97ce93fac0ff1f4ef921a4f24b74d1c15a5b3a437ea021f117dde738650d3a591331eeaae	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1619771631000000	1620376431000000	1682843631000000	1714379631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9288f112d99acb980d6b972a8f89069376a100fc2fa9c5597684f9def84dd2329316080c124e99971186528208567b543e8def42befe8552eb73406d6a4823d1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620376131000000	1620980931000000	1683448131000000	1714984131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x663917ba7ec1dd01e21b145fb8b1f166e1c5a831165e2d32ca72e180a9503060b5d16d7e69c500a3a267431f6c3e6df62b0f6acbf01d02b43a93cfef996547ca	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1620980631000000	1621585431000000	1684052631000000	1715588631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa748bef4de8b946151a27d6fc6aaa5dc698d72ba6835104860c9859dd5a55d4e419068a72112a7d6e1267ff84b743b2028f1407d3918814061bf40c41f7780f1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1621585131000000	1622189931000000	1684657131000000	1716193131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf8339e921c0e0754f21bb51335be8c4bc8a44d8e0b030b978b80b2dde1321d603160aed9883da07853933aea1b513e1d9ee00166fa53886f39e406b42a9a867e	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622189631000000	1622794431000000	1685261631000000	1716797631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcdbc5fa5c9a02d6d5b6f01faa49324ea23af76b79a8cbafcb025e7ce73b738a9a179146a6fdbbe1b03d44777f0625a2b3875442be5480507c070a52e3f46f140	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1622794131000000	1623398931000000	1685866131000000	1717402131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0025c83d813395116a806bf4565e9a3b1e56854b370a41caf1f4be451c58e6edae94a737eb37da0ebaf890a7e3732c5efc0f0687ac6b23731eca80cf272d947d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1623398631000000	1624003431000000	1686470631000000	1718006631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb768874c0e03f0692d48ba7bec50b4dbcac9104969635989909c99eb7281ca931718b5e186dbd2350f713a0d2f509c22da8db825b22c86a18554543aa5996d24	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624003131000000	1624607931000000	1687075131000000	1718611131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x15d6142d48cc0d2bec038818240040395578add438bb4556b0bdae752e96873c162d3cfc26046afda8922b1bcd83fce5aa8686a4d13d89598493da5596a3cc14	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1624607631000000	1625212431000000	1687679631000000	1719215631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3403e250651c4fb77e39ceb215b965c68e04ad28fbd8343e1acb98263a6d8f678a1d32682fe9b33f00935c663e61cb97b79a8bdcc908202592a354c43124c4bf	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625212131000000	1625816931000000	1688284131000000	1719820131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x831112980015ca6f16dc091335be37c76cb0f4f975b512930c5fa52990a20c4b6e52dfa07e53788f1db80bb8b882f9cf0dc8a817100b0ac6eab6efd496862ad1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1625816631000000	1626421431000000	1688888631000000	1720424631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x22465ba66c9fcf9281714f0258d6f58e2f31700d2c5c43d5cf57d40cdc1667fd873347dcca945d0099285164ba06e6c423c1ba66d294066aa4718cdf03b46a3d	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1626421131000000	1627025931000000	1689493131000000	1721029131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x048ead9f550efba2c752f832a75ac995a5fc22a1ceb2f4ffc1a000e6181e30fc783c3d8356808714a637f248eb1e88a6cae35a115b450114d250292f90b54f15	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1627025631000000	1627630431000000	1690097631000000	1721633631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1607681631000000	1610100831000000	1670753631000000	\\x4c7177250061a44a37ce1d1580306e2b67a51baeab5d73033fd4fb40657e7fb5	\\x3ef318c58ed6479a04d47eddb1ecf1c82bd9e71dc52f40e04751fb4d53c44b289059f79888be7c366f57f44f4175cac6815d185c794cd7ae7e05195c66b21602
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	http://localhost:8081/
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
1	pbkdf2_sha256$216000$LGR7sfngJR40$WABynXX2NX+Ap5zTyVFR/ZNm1Q2cL+SRdjqcVr44AzE=	\N	f	Bank				f	t	2020-12-11 11:13:55.801855+01
3	pbkdf2_sha256$216000$pM4N9PF3NfH7$FMgM1345jpA21E5ufkNmdIomqaqqTP3mFjElc8AR5b8=	\N	f	Tor				f	t	2020-12-11 11:13:55.983086+01
4	pbkdf2_sha256$216000$T1oOjpiRPCV0$OQ57MV6nhpSrpN4IyvtjRntzpavH8aE7wL6nZw1xRaA=	\N	f	GNUnet				f	t	2020-12-11 11:13:56.064035+01
5	pbkdf2_sha256$216000$nSMHRwOHibWl$sPJqjOId3NDO5Bgs048UsC+r+BnP9ab1uiIAg7z51kc=	\N	f	Taler				f	t	2020-12-11 11:13:56.140069+01
6	pbkdf2_sha256$216000$LPQgemwuVA4H$iym32Kvp2JN+42LveUQIr1Nw+giCWr7jWSVYJ2yb1rk=	\N	f	FSF				f	t	2020-12-11 11:13:56.220024+01
7	pbkdf2_sha256$216000$ZdcJDqY4Gpwv$xhhZf90Ot/iZ0DlOcoHrrwhKxnpgIvUUVYf3bY/GZhQ=	\N	f	Tutorial				f	t	2020-12-11 11:13:56.29692+01
8	pbkdf2_sha256$216000$j14yCOYHgxfb$Kp96MJLF/PIjfK1XrlzRbpGVhZn2X8x3NyweJqPi4cs=	\N	f	Survey				f	t	2020-12-11 11:13:56.375164+01
9	pbkdf2_sha256$216000$0UqjRYV6Q3Hz$mey768TZl9HrANFlTNCJIpS7pazD12vW19RQZpAfQQg=	\N	f	42				f	t	2020-12-11 11:13:56.851439+01
10	pbkdf2_sha256$216000$rwYeH2VTazuh$Dy4byhWfyaqEXokDuML2VOn12XVBVHUhKr+m0Dnk0o4=	\N	f	43				f	t	2020-12-11 11:13:57.348151+01
2	pbkdf2_sha256$216000$GhztxK7EH8uI$fiQnf2STOS8dJKhZRrK6Jc0l37ushIKaaIdZoLhsnes=	\N	f	Exchange				f	t	2020-12-11 11:13:55.897328+01
11	pbkdf2_sha256$216000$LvBrt5QTByQ5$OxkBShKvOZA1xcPKaKxY3hHi0jSMYX8yrz/YXBsSuTM=	\N	f	testuser-lqIzYy4F				f	t	2020-12-11 11:13:58.969111+01
12	pbkdf2_sha256$216000$U43o1JeqfjZW$R65wa2XDBbs/skUaIbfRA88lQRaiEEoIZ3co3iozkT0=	\N	f	testuser-EUc4dkCI				f	t	2020-12-11 11:14:02.27603+01
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
\\x07f9fd16f089a6c6291e48d05f001bd5fb4ce515fe8958f8b8891371916099bd669f6a67234f306394d3d904d3dd376c79e2ea1690713ec5019df4d14525623a	\\x00800003de9ecd7b84c6de96eca3009e718ea481f6d3cc6c8c1215bb80dd176fcbcc073d94d89a08aa482afe783bdaeea79ef361d70a15f14afb9294e7a6078fbb8d360425fbe76aab9c51c2bfedce41e63fb260da2136a1b3cf3b16ad56800468b044dc71d9a76f9c3922325b45f9f6f6469c6523b1303ffc8c687039fc033978273113010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x0f8b3ed5fb973f7243295eb2d2fc9dee8f92748951c211233508f87b2018cd3b9d99572d5db3371ade10764c0c648b93bb67d5775b8f68ae3802035dfb331c07	1610099631000000	1610704431000000	1673171631000000	1704707631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x767e8d3facd58aef4524b99e7d751fa0a61235d72a3f40921e8df2588a3d047688bb57d33b44c83ea47cf3eb21b2e6536c216eddff48793e329a990e7effac8f	\\x00800003b6662504164c13224fff56b8f5c392f31d5d09b3978043e0f6a5e7fdda93bc908cd0d317863ebf9779d125b11e40c3ab8c52a67d2d29b1635fb285a4f24191492d9125d69ebba5ee5c931d28fdc6b5c5c0e35db9b0f400b82720b4748775baff252e36d9f283588968f81f065f46dac8a90a16a80c34314c227c5c6eb971d517010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xa9d5c3b097a98e5b30a8191843e06ad8de313b184ac9695bb20e0d59241e7843e4ca689e32e03c2bd3ca0e4741c90dce1d481dbafbe2e58d753275c4ab850004	1608286131000000	1608890931000000	1671358131000000	1702894131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98b19bf157589325860a460dcded11bfc43641497471abc062b4c1fdaf295bdc78eb51a506b38ecea82d460d598c2e67369f5ebbcf04193cafcd77056f043a9e	\\x00800003ae51c82e5456413aeff73af9eed9f7bba3c0309fc3f48a4f58dac5859606fdc232becf701727f6e6cccfb17918a9338b35415153cff5048580aa170c202a48002185dcbaea8162b7f52aaad1973fd7d4885953c49a968b656662f6b74139ed416e5987231bde5790d213f9ddc45248dc8358da9f06f253e671e9802d7d24bb65010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x4e42944520b5f5fc107fbd0a1f49149e6baf7935b6493e48cc0a1bd4bdd70c013bc6d5a5a5ebedd7d33d3a6f0604f81ff651a41e727f280f7d28cfb07c7af609	1608890631000000	1609495431000000	1671962631000000	1703498631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf80e655a12e179f0adf49db1f6279ded961a2f633f1bfc6cdc6abb6a29460e2cf65dfb1569bbfa0393001185366715d3de6ab5d03243731ea5a1118a81958a26	\\x00800003abe961ecc8eb63090f013f9d7f13d57c084453438f7afab8bc01e3347ab9b0a2259ce0fa3480cdd2f9fdb253de99e28199e9a4a550568f3b9733fa26269f89c8dc927c0d9009edafb7536803908271cc65fe07cc1b8b8d84302073fa78fd1f0d59a7c323ed148484ceb5b81c02bc471b2879fe663ea9d96b5f33e0fa5e331b15010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xb3b5e7549b1f0cda119c3dd7bd163ca485013fa0b81861453b657d33fdb812237479a01ade611c6df5c26f0a71e126e901b7fcf8b96a3b65f7e9f87b95397307	1609495131000000	1610099931000000	1672567131000000	1704103131000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec808800c3bd0ac0a42f2a0a392a2826ae8b87ce92ea0fbb1050b71d2fd2dbf463e08ca58de04bbb781e9cebb1eded0fcbe7e1955627dce4665b8a7045751b6c	\\x00800003b59b11f0af2d9eb6dd8e47ec1418a216b090ff55240ae97347ff822192ae8c23740d3e4ee4c737d399f1f6f9660d316bc877834e2f65805488c79360ff07b53a7b3d2e3848b9277ae10bc31a658b2c85ff85977888dd82d9eec6903a59c258ce1fcd649ff93f397d0953806de4437f5829f0d6cf2a3cab6f8698f26ba5250579010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x1d193701c5a6a0824219451a5d42ca442a625a650789cd4003b2580930d594b17f6599fadcfa0360708632b30373d728dab71264cd113cae30dd758e05d63c04	1607681631000000	1608286431000000	1670753631000000	1702289631000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7993abaf20e151f066bfbb6a993e4bae36a11c35f778712b3d5b07bf1d5f95f6ca8ef4f6e7580cce52919e37336f57d79b1608b877ac31124b091e0a019c95f8	\\x00800003b46c7e779d9774e3b62fd6b831d6d57f7f55d45cf8ceaf3f4ebc46171704dbe33f63e6e473173e0fba1d6e8d3abcf4f2dec4c3ab924ce05939e2ae2542417ef25d5f21d02dba448a45c348c7de4d25dc257fb2d9fae5f421cc2c5b3b434fc6f236a6eff8201495a52c50ef58e9e03a13d667820bc8b4a4ea07d8539ec174141d010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x4dbc55ea8cded1636d3e78e8678bae07f372c154563c9f4c4a261ec419f1cd84b1e56a3b6279dbb007b818fdb46dafcf4ef5fa5552cee5e9730f5310e8377f0f	1610099631000000	1610704431000000	1673171631000000	1704707631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd70a7564e393c8cb78cbd1e2dd83ff52d152122e08c37c5c24c111c6c6cb9ba0c0630b370114d0fbf6697e97face8e3f1b3b1767856e6d538286a321b3532bcb	\\x00800003d82756bdc4c855bcb7c3c5642dc425211ca9418be01b5f9e9857b63e2f180c8c359ca8848badb41bbeceb2d2c49d26cc9eb56edec8918675e127aff4175689230b0574e35d870dd2e9de6195be82b3e3fe034cf3e7b0940486c4446cd5025c95f760d4fb01b448f09dcc00617fe5f892559294d771904f955864180b67d53485010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xc8863c07b12574d12ea524d42353ce761661528cffaa32d9223e36eaf47da8c2f619c763a2055cab46ae943e1f1815363d2a6d9c71a2c828c544d0acda087808	1608286131000000	1608890931000000	1671358131000000	1702894131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5d343278e0bc985df9301d099b3690c7755f764ab8a88a49f693fda01ec3a206237f21d4d1fbe02c74b0fe96e7b9254000d9e964a51f926a3d6be84f22500ef	\\x00800003bb3e898a3f7df3a29be3487f167324f678c52f63e510de3ae5128cfda2f3eb58cf95c6b1ccba3c6d2fc437a702b2520ca8d4a95c2a4c0623f6ad0c4dab1edec91796dad3f72656f42079ec1c49411e5df36bab3559138eb1a5c27cc5d23d841c498593e1ee216bb847ad6ee361bca141ff67b132fad3a95362972b5936af482b010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x3941b23ccb96b880957483410499151edeff4bd83883936fe22afd036a0ba8c27d1675974cf7de1d65c8127444984cf09b114219a4313e6eb2fb60d82d6fd60b	1608890631000000	1609495431000000	1671962631000000	1703498631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa594b857d1cf45de98cc5aaae7e5c8c30e3a226024a3e8f0f2ec6469d5bf9d7033d7b3bfd9f020a165a24a9d529c45d37507864817c8c906c27cf63e9dfff543	\\x00800003d6e61c82c7d7d8e085590cd0799c224fe3c22545b250b20eb767e0e954c838f8ee27461ee62a2d9ffe95ff85f6ff23fbdae85d0cb4e0ad0ac952f5fb6fd34a0f3446a67941b8cd52c97d6a69d4c3fe5b13556da7a845cee9b76f4244501ee2b68089aae152e506c382233cd4f0c3e4461d3b71f78e72db74a2e019fde255bb3d010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x9906f0d564af929bfd4cf2cdbf042d0e912e54dd332e2ae758e9ac40b50d281d16bd0444f7f71397567bd651c72a67a7ae3ba2e25ffaf58631870947f6ec4000	1609495131000000	1610099931000000	1672567131000000	1704103131000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8988dcd0af23d86ae672fc2ef2fd5e3138fa0db8760cd454038dbbe0de4212b9ccd3a06de1160f91c71a785f28beba7659d089ad1b339167a5aaa62b41c438ab	\\x00800003b79fd4850c4d5c08d95599774d94a1ecab3b19fbb7826eb9523b203915a929380c9c492627bd3649b3ea4a1ae27545af0c8f27e29184e74dfc70f95c287035e41e3795b9f988192337f1d43fefcd6dd1fb3dfe1e3d3df87fd0c69d74ba44af8666e61d796265be275b25f1f99eebbf90db4fb4f1290c119b18c01365f823c585010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x363c2e57b7d8d4180c2a8f92338bc38fd3a761c831e1e871d9a624bb54fe307469d2c48ccf4ab0153709bca3ad3769114f5e0940a17bf31026bb81d638860800	1607681631000000	1608286431000000	1670753631000000	1702289631000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a94a08e8d1879c332606f380a99298ca379c9af095b7499ea98839344563be0981b6e07186cf577eebed8514acd66c5e07bd4f728d8fa1860232a5b0b83f6a4	\\x00800003b4850665c2863706ce1b6adbfbe5243f24dd13341468cf1019bc881d496bd0f9919b150bb1d0b465aef0fbd5ce90e8574e28f6d4586b125f1befc0914679ab42f41f1ed6e64dc71ee1c691df545da43e72f624e76bbe5065f9a9a33b1d09d3fe8415b430b2dc35e52a7ffe061f2e527bc47096d7fda5686c6be1d8d80048084d010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xfe733a915cb7c4943ef9348b7f84645151327d985cb97cb04e9a428259151927758436f3fd796a517d6e6b6f54ad88a2150816fc657cacc303e814757d2fc008	1610099631000000	1610704431000000	1673171631000000	1704707631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9634ca6c359a7384adcf391c18ac8e57416ec127f90d7023df31885ae1fe595985fb6344d5a99ee6a28e870a8c3d615592e40ad2cb719b96bb146b4b6adf193f	\\x00800003bcae0480503b621dc5a8fcfeb20a4545a353e282383d675b9f337b1fadc785e72b22627df2044f5b45dc7830b97fbc1766f11d9e565e93c2c4133d05ea87400f21f8bdf725dd6c4eb071bc9e7ddf9e8c783fc6faeceee033dcaae46767e46f16891b9ed593c1079bd375b544269498284ef48589490d7dadfadaac1a0a309bab010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x8fa8da40fd8c8e2bb350f4c5402fb6f3bad96551198341d3da39deaac931941bdfddf2d41489cef275eadcb5728ab0fdfa84f68c47bfd56fcfd983d7bf59b50a	1608286131000000	1608890931000000	1671358131000000	1702894131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ab3240682324edb5ec7c995ac2fe329bcfc46c2625147f7a52820fd4dad1a2f7c982db50e04a80847242f617b5a4a2c55dbfa35294c34b9708097c786391ff8	\\x00800003b98af45571e3861445d52d7d0666f2202b44f1179fd6dc8668e1cb131a9b98f80e25b3933dbfe50a442d53e33add270c88bda5a7fb3b0dedc1ec6b242ca3578fd0a8cd452d149ea21f0aad985793c38fd15bd078fafde0dbcfcc0a594694a4e35978a5c2c71058c129c9e8d42845afb233825d5f1df2ae22241aa90de3999b19010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xdfe5dfa4b6f8098ed8d32027a49560906a106cde9a08326ac888f703110e496ac29b2bbef85472927dc8fe32e3e7bc0478858ad5d9e8c2dfbe0c88e801597a0d	1608890631000000	1609495431000000	1671962631000000	1703498631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x73a42c48073256065d6f936a5540389080f19d815b553c5278b4b456a518a2a465707c8e3f98171518384df3abd6a5830c8b3a137a7f759d081c702928252a0d	\\x00800003e8eae3caff915a1c0004c0debea7389129be0658bda053dad922fcf055d7a8bb8088cdebeba13dd5040170975517708f69a7ffef958823ee34ff79734c0e2de2aff6e92cdfd3b9c46e74443fdc2fcdaba63097a27233cd1a4d8d5f5d0239d2abefcb53e2c5ba28b371a77ddefb327c04924e08d842dc1a9485a3b9f1dd10e9a1010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x9acfddacb78c42f920c6fe746d49a863747931a72fad831b7c50da207ce538f75c16084cfa43d9a23d362e757366a33078985ce3291b6cb484c21a4866c1540e	1609495131000000	1610099931000000	1672567131000000	1704103131000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1b658134b0435bcdfd6bb88389aa25ef418a5961362dccf906f447d3185fb64230bd16123c00eddab5e78f1b237ee82075755b47220594ac51654909f570092	\\x00800003e4605244143409b3775335ad654f63411c6346dec95960451adb2ade8999e84d55580f98345fdf16a72180e58a1cdfed4c1eb94d0eda4aba5609982c3c246b992c6aeaaf03e3fd105cad3d12f25e43559d5e6de03f7b66bcc1ae0490c3b3a026cd9b4e7f0b7d86884e71132ee3f597782bc8fe2c25843fe20f485790380af4b3010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x84efdf445069d20be8277f9e7f4ec1abcd45b23666aa0e27a4913d9dc1ce7aa68d94a3fe4dafe6b2c66a385aa2d7f83dded7dcfcb3f76f142d427a87f3b23e0d	1607681631000000	1608286431000000	1670753631000000	1702289631000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37c934ad930072060e1c33e9bf43f7d6b12700c12d64514b971657bc228439c747935ff08c203b74e58fb8f778aa7896fad6f74c9412eb29396937e42b13db5f	\\x00800003de56159a62bd8df5b41bd637d21010a6c3044ec14f4f52bff8d827fc7afb4d72084a775205a31ab6ba3b216379f7c9da7a9a8b671e0b25990c33fba7db045adf9073d32e7d5c226c4f99af977c63e1ba1d886a643ad22ed4eb09df9232e04fe36923c20a099788b43747bdb77c5cc75ae185744b08618536fadc703b830cdec3010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x2444c916d9e41a3c7456925faabf28f5f09c2d032f8fb67044d19a88fedfee1c19e0c2837df5dc085eb3e10dcdbfc39a1729dc6d6efd5a865b5ed156f0a31e08	1610099631000000	1610704431000000	1673171631000000	1704707631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc4232412c0c8c40424cda551b819b46d7e300b8c510099d95ace2a356cde39368765c8d2c04708098317861ef2d3caefda85a5c78a47c6d64aefca53b4b3ddf	\\x00800003d3bd3fd25abd9d75b2e77e046ae386427bd3586f49f5fd1ce0016580258289888156745201ea0139e9707447eb707b57fd4825af82be17acb7e413b5b58f1f72f76c9820ea87f12124a63939019050213ea5b3363cf09d66f1f2dc3654c99530a15907e687cc470d726819f7b0ab1100440687916f83722e0416f063885bf0c3010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x5fcbbdd680db1d4d3b6478ebe1961ba03e948e08576b6f58bb8fd573e4682289a66419a550046bb81c0b6d9e0cb325a3bdd7543d99d7c301e109724998591009	1608286131000000	1608890931000000	1671358131000000	1702894131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x79ce5b598a27240e5c20bd0da36c812b4c38da8a7cff061cfb162511a9d920a88b38cfb912994f5c4cc6b54cdfafc77ef1d12e4b1aa1b9954c00f1f010622e10	\\x00800003db8d3742852d1149cecbad1f165e1663f1f160f1ea4a168c3802a04ab3fbc9f39023e1ff650956541556f52c1286d4344b3976ca43a1d846f6ee1f69bbad540ec613447e39b26af9b9b6807e1e1bd2558e0774013ad4ab0f389e070159659aa9474fea92dc93fc04d9d96cb3f667f92eafb3919bd0d893fe4043cd084ea129ed010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x01b7f28125d8ac764d9123529284068f72ee535d8d705cbaf52c7bd352dfb3703faef338850f61288f1fdad41bffc76a6d3161c2619a32f93c333dbea2f6bb0f	1608890631000000	1609495431000000	1671962631000000	1703498631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf27f8fe863e8f67bfce1abdbcc7fd3bef0128bb6886d0454a7efa7ba5d0c47a3d403c32bd73e4240bb7218703d3db37f980039eb7f70108b04d7eafe443d61d0	\\x00800003d84bc649965aede6f710420a9290fdf42500f00d4b8958e854523ea327a30c735e4e48f589487608014364ab6c9cea3549cd8f71d45f6ae3a710d11eebe9d9b3f246875c97427f3a77c781809e19a4cc0163e3cdb55de02b8427b76886245338b222f4262e2a692dc0e419f6c3987cfc232ff4f6b32631046fa6f56fb2eb0eab010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xd702e098fbc36325192bb99240d5885200089c6c50440f9e9ea2dae3c3536d35d7f48c9e28fd0b3dbb6e7dd61259f98743545db41208a5f5660e8687182b4e05	1609495131000000	1610099931000000	1672567131000000	1704103131000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf914bd87f9b081466f92f1223da370786d4a7127520b39bc67bfc10019ca0db8f6ce8e7678b200747a306ce2921cf7c5c734902418aa199a090b3874ffa0520b	\\x00800003b9d69ce97c11473d83e7ac26126c342a090941c97098691c2c199ae9111c0552065acd558add3042763bc58467b33338f85ddcd554bb2bf305267418716401d1766f3fd013e6af2f78d80b5fc0c8087c3c681c4c5dc6da9362b8baac514836c6d9c04dfa696cf94f8cb4c2e400b93f32eba51faa4c3d8c4e39be4cbfba6c8fc7010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x0553a9e6cbc79e94ab3a6bbb605e76c20d83ed36bf36da0558be92a744ae53a786fe318d07f871e0e38b347e69210784ef9f2d15c62a92d6c848e39eb8089006	1607681631000000	1608286431000000	1670753631000000	1702289631000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2cfb8289f7a5f4e7cf645db537c8b7fef3f133e516031c91932452e1b0cdfb9b777da43651418ce9fce5fa9c7467726c1ccb8742c65347eb22ff0d4a0b896985	\\x00800003e93749cdeb39422f1ce5ed4dc542e6c79098726822593ec0b388e95f895bf90ceed14280c431fa07eef073e2e39a7e07e73891f07d5cf020e8a0835fd2fd9dfdf6b7db4fc00ddc17147985ac39674feb4b941f3557ace1b801c1e8d490c1c4b1c61b8dcd1f8d74e17a6dfa4a3d8be5b1e012349bbd4c0b71abbdc6154c7cadd3010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xa2ba120b8f96c478b9d258a52c1e018b2196dca574e30bb879a7466c081c7f37ba18b737fa38c8370da9fdc429e383eb2c86497be68c8ab00e5483ad022c4207	1610099631000000	1610704431000000	1673171631000000	1704707631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x35695b77e094bf112245816a8cfd53bd0bd5e27f0ecb36e184d979f8ca320679599d52114b81ee1b95fd9376fcdf53a2d9ef6e059008936502ffbd1ba8e2a682	\\x00800003db151c96c119c195159d07b83f6e0cb60a38ee613846fddf382ff4d322106c403e0e94182557038e19d98c82a88314ad093a0b6b55f22c4a0cacad497163c9b3443a7e99c147e2598effe86996472f1062d933a35da0e8c24764188d78f3d4c771ccdff1f309b57e613c52f753206b44475b86d86c278332a88ce10ee6ee4f9d010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xac97ba0484d0140fa0d82d247d3ca90be3e5987e7105c326f26ceec7e775fb1b4b38ae08db7bc988e97caad2544af2af0e16aa3e1cf32266bb79f5c7de309e05	1608286131000000	1608890931000000	1671358131000000	1702894131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x59d05edfa818e501e721108f4cda7c61c1586002d03879d8ee74295350730f4e83420cbc33d4181c3a5424818ea863aaa06be36905af0173b5ebdc0212adfe9d	\\x00800003b9547d3d46bd63af64fff8b26dee97540252c2070a3e22ffdc43d73848d4d5d55ee77561623dcd66e3fbf34da802afe5d004b48befb2e14d21cd17c82a09043a39a4a516222ad245f0614a940c245bf97f6b823e8c200d0e696820a25076aa1713b954e5886950f08d5f8f043eef1787a408be0fe91f8631682d9ce26cfe2539010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x59e4b86fa8fb318832b77e355dc2b78aeca75bcad0fe92a35cb6a06ae314b98b5e733121f2cd3b3c2e6267c9fa970a751a771e797e2956e701fd635651e4fa00	1608890631000000	1609495431000000	1671962631000000	1703498631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41254eacb5fbe99ce74a761437ad8b73f95686d1d121e84b9959e983a803e1e0c4971ed5236b783297d23fb98ee1d26fb9eef766cece44da261268dfbc2ea1a6	\\x00800003c89592a6e74f04ee1f5476e4867bbbe886d687dac970affff98dc3d1c36ddd5480a03f9d3d860722167a15f70af892120d0bdc076c56cd73b32f0821a754ac6447287887944d632ae97b02aa1f748d97a170c830844c9e005f55a822a08fd92c9f4c9bda81503a3f36e2d453d82d2c255b51dcd4411a82b4b61b06d46d123037010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x896f0b19db404a3a4256904b172bf4ea77bd77f7e7353247dfe5aa1a97389f06e34a3ae3ccadb1e2dc1bef6433cd17dd2b5126a6bd3dba7d07841d219bed8800	1609495131000000	1610099931000000	1672567131000000	1704103131000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x11a3eb19bc7a7a6843734e389a4155bc93805e7eaad70a05db28137d882f980284274ffff9ecf34b4d9940591a4b1ab909e13f720820967dccf1e85ec49bbcc9	\\x00800003b49d180d5a5cce7dc998a0e2c83e981c38297511b615f352a41a9b828f7a1a7c2578da7d4f0e5efd8a84dc94b65daa2f8a55f0510e50a6b7e0c54b8de3131b92ca70082f29d44f7da4ca955092a2fe5a344ed74f175f13da1f9de6912242846dbeebf6b2351750ef82544956d9c4310552807fe036a56ef825ad925536a24517010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xb560a7505fdac790c8e9ff7bd8721ca5035aabb221458eb007e9b530be6a4eee365b6245e8a65966588447c79e497a9f25854e561bd334bca2cecb958510280d	1607681631000000	1608286431000000	1670753631000000	1702289631000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x883dcd1593ce8c836352d326a9411997c88ecb23437f94155ebe459d4dc16a1998b0b0fde9c1e0caeef811805674e69a55d4c21cf06c1b8318d47448314b392b	\\x00800003ac19ac9ed494e2fdbc242cedfc161fad5b5dc4078fda77d49287e2a7c824bc717e505014630dca0b5ec93f6718f18cc86256890aad3cd51995c23c9f9572e81abf63a0b125b1f312ef75606eb3a6d3fc981b7f504f497e84b696324ab249ba9af488a6b79bfef4e202903d93ee2186003207b48ead9bb2255bee43ad073d2c19010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xdac2e47244ded56489e4791d0d014ab0177c16ce45a7e5db0c2d17930da843dde2bf6f23e22a3eb9e9dd58712320f7fd391dc7f7b3af1ffb93cee2a18645070d	1610099631000000	1610704431000000	1673171631000000	1704707631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb05fec2667665e5ccab6637736324db854b90baffb28cc71fafa11307ae6087cb9b10e2fc52e2ae1280ebc75d64319139914ae304cca745e0fda62feaff3e82e	\\x00800003b9dab315f7312f9613a4e9f6ac9df8864cfa6cdf80d038ba7053bae1b747c3b85f2546f2a35991fc1939f5d48a509f1ce9975e897531ce5b31954f6d2e2bb141cfd70d644265fb814fb264409746b0d57746db598e528d643aedc37229bef9aabce2b5eed0a6369a45df778f79d5914b4f560df0bb379ae87e44710f928f0645010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x97a2131c410153c56fd2126800ba6f14eab174aed4d05886818c8b92745da564f180d7b25920596723fe75eab63233e219c527d24513e235dfb5dec8f178a50b	1608286131000000	1608890931000000	1671358131000000	1702894131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa406a3bae11a98d6c47957dc8f2ebcee3a339b224b9fbc4a011abd61005f7918124c7799fd8f261a2cfc57689d6ecbf9055ffdbd064965a42bd1572bfefd217f	\\x00800003d403349b92b0b951225492cf370a961d596a3fed5f6215eaee350bab324d5066f94b09915fe98bbea6a558a0130d4b57145145ae5207366dbba48cba20562fe9d69dc218f50b605f8982ef0e8abbda2e337dcea891f35ad6c4e9226f78466085e9ccf72999bd5e38bf9d4c371b91b00cff2fe53546db7aca35ae58e0ae72becd010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x448ccac6c09900f26fbd164dce09200d54e8969e43e27140e041632039b60dfb903f67396c5708c18deb067c88ef4d9292274978dd28c3f1f76dca954f251300	1608890631000000	1609495431000000	1671962631000000	1703498631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5387785fe960140df72d9f2bc1f3941f8ea45efe0c30d0f1e9387efb6b8b8160bcaf2e14a1cef96d1bb403f8d3db680c26ab0e298d51ae8787b04a1309ac0f13	\\x00800003b4dedf8afd133f2932cbdc0e06099d9172d84407a50e55d472799fc5081a3b3f066ffb89f3b9126c85c41a467d475a7eceed3dfbc99b9d51d709982d8e3a38bf980ce9838f8ce3477b9b7d3e5dc18c30b175ecb2bd9c5f4f33be662ce6f51d997c6a5310f47235565911f392f49ee5656fdeb91650fd31ae41f9f16e4531f2f9010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xaf1427aa8c4b7c16ad05eb381a80f20eb6a9ac2d966a1fe95d071e8aa09efc9fa4e8d6a04cf0544c92ad04c462eba0ae8737b22d8cc0f43591d131f2c5c9f406	1609495131000000	1610099931000000	1672567131000000	1704103131000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x00800003a4593ccb525262458e2d9e9ff27e2b415cae6f559611627288d2a243b08c90c79affbee6efacb6380f5b9b0471c668bf09a97d11050517da6bf46fbde0eea8326d3e60161392274884b7baba6ab331fba948746fe5b4e8267f3fb0e463100b4a96128410a8c79ed092bcd16933dd245f9aff211bc8e67699bfe92b7827a4c4d1010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xace6d95292080fc097642809f30f6fb55a46c3be05ff53baf30f6fc2ebef30c0a05b952a414a05f3ed12d506a94e73002eebef19c5e56e0576b0733fbd5f5207	1607681631000000	1608286431000000	1670753631000000	1702289631000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x49fc560569f870315cb32f7f6c4a5bb9a52404daa735101321ec9db21dca2043ac4c5eb510f2ea19435a4da7ae3e701303bb31b297a379d270fc32a3da4f1dd9	\\x00800003db725e9c4b6dee9e98e38ab0d07c7e3f52942541692929bd9661fcc6aebb96e8e0d58ac448b69210ecf1b3e23077615f40749e866b76e76fdd2f1631b3dd8275db906429f4cfa61fa07aa86c69d96a2187a29d5afd72099549648389a6bdb4ad6738e47567ce500e023dfa223415667a449c7391b59f222f805ec8feee5a8dd7010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x5d86dd0bf82efb6cfaf6c5802ec473cef1989a8c8caf9bbbe1121951b8c887d24e61889ead68b0fe5d98f1159a070c5ce0b352e31601d136e2791c528bad7c07	1610099631000000	1610704431000000	1673171631000000	1704707631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2aa907bc152aac2c1d4c37413714b106cfe76c27aace2c7c42ebf494876149d4b176eb7e720fe5d90430f3768bb3ce3edd0035224ee8832baf94b0a92be5559	\\x00800003c4a454771cbb5252025e4a33c814209adcbbaa0f714eb68764828b88d48ba5b26e637ea227abd02aa17d4e55c8d5bb32851836f0237e347d877c9261f4c0fcec93c94095c1654a12a576e68e7124a47a5f3300d0cdcb577659de9a377159c679657a804958d86069e9adfa6d1427d5ae7c4e3ee13e3768fff73dca0c586cb415010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xc8018c50ea23471d4adebaabaf073a274b0d2b94985701c8406078d336b82a5ad5144f627fd1d362562889f7d3fbf8b6646f1857050a8e2df5916a2c2f12f501	1608286131000000	1608890931000000	1671358131000000	1702894131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8e5dff5840a8a80712656143e08f21bf08ee6be24b24ad5d03879bb6dda1bb85e938fa6dc4a7f307a102baac8c6e88f447915c3786b1d453fd7fe47848e316e	\\x00800003bc9c7cbe93917abbd97c9e059ce56080da398a494ea156019feb6cef3c59d68022338e18a3b97a9b371ab2d6ea118352f25e84e7d0f1d26c1f4ae2eabf0b4a773a1711bce33cff2ab623ba05f55c5066d4c9704c85699ec8d112ae9d1a2471df9de82d895d5e3a9f2c3d720e3e64d0c25c5440fa7267aa37eba676458d330005010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xb3a9c95a29202b52147d6ef92fca540d444a46be54373a28d19c60c74f52fb01c5dde787cc86d9c4ba6708251643630ed3d25220c78dc0785ded6be32945050d	1608890631000000	1609495431000000	1671962631000000	1703498631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x919c4f1a5fa4bed568e3d1c55a18d746666b8dbf607adccaf4ab26996188bb7982a2dd4e0ff58c2dacac534ea9bedf16ff223176102f7bb6d8b1d1217fbda057	\\x00800003b0f4e33093ef2c08b9206ba3e0ba6324f475adfa18470ffb456a4bb1365019dfc6f90cb77ec9fff77f035764d807a08c346b7047bf7dfb9ff7aa858f6c4b158d2970941b6d84641e983d3da4ccba2546f4c6466ba4481790a648d7ff7070a4ce7d8cf9edb898373fd8b72a06ed8fb9e90054b3f4dda0770af789a727be5ae26f010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x017df064a783f052636d2996e547f692636510c07cf6bd66eb99139f2fac34b74ed28b59c30bbb25ead9eb09345d959213bd2eca43aa92c94625f1abb5080d09	1609495131000000	1610099931000000	1672567131000000	1704103131000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x00800003b9b80a139e54475f5ee94a0134f8e684c17e1878c45790820c78c2355f1ade619defa49057af642062bfffcd6f1e997dac2403a9e6caed5972308e9b0778ba3eeedb5655504931b884cc21b04d1746f9f3141013acc0ff6108ceb532dae614b7bdc9dd611651c5af12f524535b296fbc61655b4fc42fda2337c9288fd6f73071010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x2f4557e11016c01a9df74aa9e16b989c6a839d73082351c310b3bb28497809536bb6428920cf93a9863dcdcb97c3475805b7d19fcac5468825a6a2eb3ecb3401	1607681631000000	1608286431000000	1670753631000000	1702289631000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x70c367f45e831753450dd3d54695d41df6bdc7ed1d949905f66efd312b3da5d650d02902ce0263af4b0af2e856de6f53b21850b4d773cc2c02724169a3267128	\\x00800003af168c713cfdc10248878beacd8fba488dfedc03239b7ead2084b14a7cb6f3e86f664cc34b71e58cb45846f8f3cd3ca0cbd8afcc7ee56bdeba92997d546acabf3e6f54bc980ca5e0d57d98ddb9ca87e7afcba51f4d9d5debed75c117d3fb60c99ea0c6225176c5e8b66df7570291418b9834151b1d36182380bb28ecc5d80a05010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x00f75505992be410f9fee24a33d781c821d61cf6a7262d63765c885db7760feaacfa379cdbb265fa6d1654ff643381d5015db074abba675121913b833db9fc02	1610099631000000	1610704431000000	1673171631000000	1704707631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x27a20b4c50563999976bca4514760b30b585eb6cd90390c52b1a48fc2fad607d99940c31140eab28500362db1eef056cf29234f9a52bd70cbfe845fdf7bfb6bd	\\x00800003a519f23da25461896f1c65125b04e1595f2b7c5a643479ab973c1ff3ee9da728bd7e78bbdb89b6aa54dba632f24801f0c0b213b677484327129a0e46d7b9d3fd21d25d9f6dd6632d02555f3a99be628c525c4270b404893f6dcdd0503906edf5f2656f9b3e84d9b4c4593b6ea23ed6897acf69ac02000ca050cdd32b073947fd010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xd35543d263a01643ac44fa2d74a62181b82abd52d3053488e925f7836e9097ce6a2df8a2f1e4f5383024e85e0b911852fe1a63a756b667bf30566fd333e5bb02	1608286131000000	1608890931000000	1671358131000000	1702894131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x37e9e30c57d666ecb5bc6dd30c863c9a8255085e6cbaead57915b2af89e2475371bdc94b8c00ed0b7d1ff962e5eb92fafcf052c38b633c4141173932532c7628	\\x00800003cf90763059c72983cd5af68ff0b31b73410c43280d3c7ecfe79d78fbe0ec9f4922f1c6468223e2c16b0aba04b13621be621a1c9d6f4b4816c33739e17bacdff8721a0d5c87ac0b7c98f41a5d21a8de75bf5ff4dc467f800cb352bf8583207a2d3f95addec80722b55f78d948555b8b9c1590b21dfe68210476f332bb9a5b2033010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x1e20b61637a9afad2df3636cfaeb52b32e61cb8c4f5001c0821e782df4d3f08107e2e7c131aa56c2674546c91fc1e6043dd4de600bcd8dbc7557639b32d0d103	1608890631000000	1609495431000000	1671962631000000	1703498631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3ce632ddc9ef26919e55dc8e867f3c9bbb08413be619f0baa67ef5e49e6ba5d74fce0c3336760323b17eef2b453248123bb8acd39beaa66342a46aa212d7d860	\\x00800003e76b720807a4ffeb0d3bbf542288d3cf948556d233c25173c3486a3f67c33f802e61c3aba909d251587135ba6b3948ad7dcf6e1e283f49fb2170772b3d1e35c47cbb9b30de7d69b403e05e39c9a9bcd01d7c8c1a97e3e4b96b591df04fd3504203bbcdd0ce05d7de59340a5c54939d247f5fc4e42d06228f398907dfdc7d1099010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x95a5545be1320d06dd8fab1447ebda53e1bde36450153da2457863e300da72456cbc1e014bac8c5fdade9a3c378d942c6ca787ee6aa938be8b929ff0b9e0eb03	1609495131000000	1610099931000000	1672567131000000	1704103131000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0cfc72018b21353087cbe3a8ed082baa049de7d097881888231658cf8de7a952781c0cbeff1e918954aa5e05376b188a0d4ee2a11b33b4bbec41157a1d88ba3b	\\x00800003ca8ce26166ccd3fbc2e918b5c7bf37b73c23309a455933c6d6232d8ac9dd0280ce538c36c7a5ccfcb4ceafa5be0d392ddef6b70a8adeb3c81ce589027323df490b637c6fd8ce6a39b0939d39bb115ef4423f75838073962ebd1fb547c312cb9198d86434fe6002d0067cd9d63c2e50514aaf87928d1bd79191cbb20700a57d81010001	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x4a1573b7d865ce932691d6bdaa4975f20ff76450dcc4993098f3c289586e36ba0dad28abecfcf10aa935f0f14f6426f1b64344be3f03e0de879fe56cd5053902	1607681631000000	1608286431000000	1670753631000000	1702289631000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	1	\\x62f4fc0e155851ebc6b5ba037067837e0d586c443cd15008cd6c6570be945b8303c74da677fa2f62d93acd00040f2181f6d83fd4af704568be2f20b6e82ac892	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	1607681641000000	1607682541000000	3	98000000	\\x0948e251168bcc21c847d19d390a217b2200519b24dba58aa20d52270a11765d	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x48eacd605c34086b2f168a84c5983dcd1dc75ac39357acc1558de9d175352ef748a04c0d5ed87e943abce7ad60a25db790b478cfb7c66f34342c3a3c1f9aa703	\\x4c7177250061a44a37ce1d1580306e2b67a51baeab5d73033fd4fb40657e7fb5	\\x1bbd0f110100000020bfff92cb7f0000033e3c4ed5550000f90d0084cb7f00007a0d0084cb7f0000600d0084cb7f0000640d0084cb7f0000600b0084cb7f0000
\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	2	\\x8a2819cecf841d3ab1f164d28483a75c7dffa9333f4a1fc9f63861ebd8e834b08731e35dd38d5ccfeec246ed53ebbe68cbe91257a22a32172471011724830cde	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	1607681647000000	1607682547000000	6	99000000	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x2d233aa4a80ab00be11bb1e2731c22ee25e2013dedb8c083c72235f925f2d4c8be98548f68933d28b43178abdf51f7698114c278271e43a4a1bab978d18c6808	\\x4c7177250061a44a37ce1d1580306e2b67a51baeab5d73033fd4fb40657e7fb5	\\x1bbd0f110100000020df1110cc7f0000033e3c4ed5550000f90d0008cc7f00007a0d0008cc7f0000600d0008cc7f0000640d0008cc7f0000600b0008cc7f0000
\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	3	\\x975fb6bbd7852ec5a954c2dfd741d58f491642abafe8ab73b159827057cf2a00f64c07f683c40a032c0d5d4747d6f850139a8652d9031c2055ddfbe0162607c8	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	1607681648000000	1607682548000000	2	99000000	\\x406a33149ec914503d2b9c9cd5ddeb410eb2db53415c10654d762d5952d53139	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x397b423e65e31aa56d8caf78bc30f10a5d4dc3b2998d810969a475dbdfec02b7f928b99ac5132a7d57f89ec7a603a5522067b75164f78d9537a7bff937e66002	\\x4c7177250061a44a37ce1d1580306e2b67a51baeab5d73033fd4fb40657e7fb5	\\x1bbd0f110100000020cf910fcc7f0000033e3c4ed5550000f90d00f8cb7f00007a0d00f8cb7f0000600d00f8cb7f0000640d00f8cb7f0000600b00f8cb7f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x0948e251168bcc21c847d19d390a217b2200519b24dba58aa20d52270a11765d	4	0	1607681641000000	1607681641000000	1607682541000000	1607682541000000	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x62f4fc0e155851ebc6b5ba037067837e0d586c443cd15008cd6c6570be945b8303c74da677fa2f62d93acd00040f2181f6d83fd4af704568be2f20b6e82ac892	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	\\x5f3a7b19e1c1710ed61534ad7c808d447fb5d258dd616efdcd4f9d533866a2f570e36c8314a27ed32139806582deed23c52d35d8721586a27d4eb4cfb0db2208	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"Q7WAZGKCHM5JRYDBWQVAKDYSJ5P7HDQNK4PKERHMYNR4MJSZ4AY2ECM4SHYTCYKBFJSVXYJDNS2G596CAC61W96PJQES0PVDYG8RXGG"}	f	f
2	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	7	0	1607681647000000	1607681647000000	1607682547000000	1607682547000000	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x8a2819cecf841d3ab1f164d28483a75c7dffa9333f4a1fc9f63861ebd8e834b08731e35dd38d5ccfeec246ed53ebbe68cbe91257a22a32172471011724830cde	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	\\x9d0906c4be278678bf230c390dd4c5a63a0992dabe0c646894bec51b8881c5beba3a946a39a70db2e1e8cc6a3ef1d6eaf41c7e8cc6a372308d29be2a11e31701	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"Q7WAZGKCHM5JRYDBWQVAKDYSJ5P7HDQNK4PKERHMYNR4MJSZ4AY2ECM4SHYTCYKBFJSVXYJDNS2G596CAC61W96PJQES0PVDYG8RXGG"}	f	f
3	\\x406a33149ec914503d2b9c9cd5ddeb410eb2db53415c10654d762d5952d53139	3	0	1607681648000000	1607681648000000	1607682548000000	1607682548000000	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x975fb6bbd7852ec5a954c2dfd741d58f491642abafe8ab73b159827057cf2a00f64c07f683c40a032c0d5d4747d6f850139a8652d9031c2055ddfbe0162607c8	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	\\xbe481399a9d7a5213dde8dc36a0e6e7169d2481cd7d21ee9364129a7246fc1ac6b41ec45d87ed9a12108f1a1ef47f0dcced42c728dee971e5d044b84d44aa607	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"Q7WAZGKCHM5JRYDBWQVAKDYSJ5P7HDQNK4PKERHMYNR4MJSZ4AY2ECM4SHYTCYKBFJSVXYJDNS2G596CAC61W96PJQES0PVDYG8RXGG"}	f	f
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
1	contenttypes	0001_initial	2020-12-11 11:13:55.533103+01
2	auth	0001_initial	2020-12-11 11:13:55.56005+01
3	app	0001_initial	2020-12-11 11:13:55.61781+01
4	contenttypes	0002_remove_content_type_name	2020-12-11 11:13:55.6414+01
5	auth	0002_alter_permission_name_max_length	2020-12-11 11:13:55.648877+01
6	auth	0003_alter_user_email_max_length	2020-12-11 11:13:55.655865+01
7	auth	0004_alter_user_username_opts	2020-12-11 11:13:55.661235+01
8	auth	0005_alter_user_last_login_null	2020-12-11 11:13:55.668244+01
9	auth	0006_require_contenttypes_0002	2020-12-11 11:13:55.669996+01
10	auth	0007_alter_validators_add_error_messages	2020-12-11 11:13:55.676253+01
11	auth	0008_alter_user_username_max_length	2020-12-11 11:13:55.687056+01
12	auth	0009_alter_user_last_name_max_length	2020-12-11 11:13:55.693029+01
13	auth	0010_alter_group_name_max_length	2020-12-11 11:13:55.705824+01
14	auth	0011_update_proxy_permissions	2020-12-11 11:13:55.712227+01
15	auth	0012_alter_user_first_name_max_length	2020-12-11 11:13:55.72107+01
16	sessions	0001_initial	2020-12-11 11:13:55.725983+01
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
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x0948e251168bcc21c847d19d390a217b2200519b24dba58aa20d52270a11765d	\\x0cfc72018b21353087cbe3a8ed082baa049de7d097881888231658cf8de7a952781c0cbeff1e918954aa5e05376b188a0d4ee2a11b33b4bbec41157a1d88ba3b	\\x6a549b7fa88ab5117ab6991db8cce7ed3f7530c368f805f955a1d8481e82ac414e7c3ab50a072aa433dda69692858eac5623efc9a9e26ba84f9592113924013c06a7221ea699ce9283e2dada7700baea1b969c633b5964cc95e2be166d35f0119c03118bfd41ec58c69845b312ab66557e134bae51c6596a59c299531c49978e
2	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	\\x8988dcd0af23d86ae672fc2ef2fd5e3138fa0db8760cd454038dbbe0de4212b9ccd3a06de1160f91c71a785f28beba7659d089ad1b339167a5aaa62b41c438ab	\\x4745ef6cc4750516e5574af57dc6b6a6fc100cf48c7d78345358e78be3b6fa8a5689e4e168e70fe2a340ad0f5e1bfb386ac1adb4b014d04fdfda19e63676c5c832b60b51fbac2b6724da4195fd240cb9ac64f000146538105589ba3eec0b71c262cdc1fdf08d506e855d418dd0dd6ff0e3e6c28b03cb66826246ac09f9434c71
3	\\x406a33149ec914503d2b9c9cd5ddeb410eb2db53415c10654d762d5952d53139	\\xec808800c3bd0ac0a42f2a0a392a2826ae8b87ce92ea0fbb1050b71d2fd2dbf463e08ca58de04bbb781e9cebb1eded0fcbe7e1955627dce4665b8a7045751b6c	\\x50286cf4a78b31028ea3c54a7c42fb8f04982cdf2f1db7f29085a222e23fffab37ba45aabca6e54fe6838300a859a9f06cd484724a10ad0bf19bed5ad4a963db3dc5c834eb0d59c946a8a15c7fe8df44bce663c5b4d7fbebb26e7912d7f6c85cc632e31a052b6a3cbc3d285f4b8e70f152c575c532783cc48101db9d66bc4370
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x653f268f2af9ebf3d499329d16a29e0bd3be111c0c892f31e90710bcfbad5332dde4c79e8ca0d469ec3f94cb6b02ef72e8f39e2c74e67ea28788c002c2ba8421	\\xb9f8afc26c8d0b2c79abe5f6a9b7d9916c78b6f5992d376234f5704a4b3f22bc273284cc7da67a6b7cb3befa4dae4502a4cc530c1e24d695dd905b6df4118ec2	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.346-026XEFCTRVNHW	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630373638323534313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630373638323534313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22434d5a4a443353415a374e5a374e34533641454844384d593146395657343857314a344a59434639305738425359584441435344565336374b543641314e333958475a53394a5642304251513554374b4b52503739534b594d4133524847303252415838383838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3334362d303236584546435452564e4857222c2274696d657374616d70223a7b22745f6d73223a313630373638313634313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630373638353234313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225743414b394e465442573234455634394b575142593642334a444430504a475a5a5a435356485137365645323143585744303847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225a315650543630484b32423631514d444736475453333534514546583750384e5743385733394d4d4b4854543259375930304a47222c226e6f6e6365223a2235583938594e393739333050425447594b4a364338375a53445947525837313552464844323341484e4253474157524852325747227d	\\x62f4fc0e155851ebc6b5ba037067837e0d586c443cd15008cd6c6570be945b8303c74da677fa2f62d93acd00040f2181f6d83fd4af704568be2f20b6e82ac892	1607681641000000	1607685241000000	1607682541000000	t	f	taler://fulfillment-success/thx	
2	1	2020.346-002BFN70G9DPM	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630373638323534373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630373638323534373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22434d5a4a443353415a374e5a374e34533641454844384d593146395657343857314a344a59434639305738425359584441435344565336374b543641314e333958475a53394a5642304251513554374b4b52503739534b594d4133524847303252415838383838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3334362d30303242464e3730473944504d222c2274696d657374616d70223a7b22745f6d73223a313630373638313634373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630373638353234373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225743414b394e465442573234455634394b575142593642334a444430504a475a5a5a435356485137365645323143585744303847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225a315650543630484b32423631514d444736475453333534514546583750384e5743385733394d4d4b4854543259375930304a47222c226e6f6e6365223a22375952354833464a395645315438483241394d4e564a364b5a47594336545046314548415154365953584b415759304358344d47227d	\\x8a2819cecf841d3ab1f164d28483a75c7dffa9333f4a1fc9f63861ebd8e834b08731e35dd38d5ccfeec246ed53ebbe68cbe91257a22a32172471011724830cde	1607681647000000	1607685247000000	1607682547000000	t	f	taler://fulfillment-success/thx	
3	1	2020.346-028MTFMES0K1Y	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630373638323534383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630373638323534383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22434d5a4a443353415a374e5a374e34533641454844384d593146395657343857314a344a59434639305738425359584441435344565336374b543641314e333958475a53394a5642304251513554374b4b52503739534b594d4133524847303252415838383838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3334362d3032384d54464d4553304b3159222c2274696d657374616d70223a7b22745f6d73223a313630373638313634383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630373638353234383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a225743414b394e465442573234455634394b575142593642334a444430504a475a5a5a435356485137365645323143585744303847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225a315650543630484b32423631514d444736475453333534514546583750384e5743385733394d4d4b4854543259375930304a47222c226e6f6e6365223a22325750375439513059475442434b5a4e54394d484d3958595438563847323839414e333647364d34463054444a44504a36473347227d	\\x975fb6bbd7852ec5a954c2dfd741d58f491642abafe8ab73b159827057cf2a00f64c07f683c40a032c0d5d4747d6f850139a8652d9031c2055ddfbe0162607c8	1607681648000000	1607685248000000	1607682548000000	t	f	taler://fulfillment-success/thx	
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
1	1	1607681641000000	\\x0948e251168bcc21c847d19d390a217b2200519b24dba58aa20d52270a11765d	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	2	\\x48eacd605c34086b2f168a84c5983dcd1dc75ac39357acc1558de9d175352ef748a04c0d5ed87e943abce7ad60a25db790b478cfb7c66f34342c3a3c1f9aa703	1
2	2	1607681647000000	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	2	\\x2d233aa4a80ab00be11bb1e2731c22ee25e2013dedb8c083c72235f925f2d4c8be98548f68933d28b43178abdf51f7698114c278271e43a4a1bab978d18c6808	1
3	3	1607681648000000	\\x406a33149ec914503d2b9c9cd5ddeb410eb2db53415c10654d762d5952d53139	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	2	\\x397b423e65e31aa56d8caf78bc30f10a5d4dc3b2998d810969a475dbdfec02b7f928b99ac5132a7d57f89ec7a603a5522067b75164f78d9537a7bff937e66002	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xd5fe6dcafe9ccaf80c635c509c5c00a97fcccd3cba3f81dd10c2857a0f38b573	1610100831000000	1612520031000000	1673172831000000	\\x8180205ce0587911617c79aa673dcbe22b68386e7981077fe58a90fc6db20e941e90f6ff27ba75eecb6acc9441a345fc96a000793d0c304a699a23f61ebedc08
2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\x4c7177250061a44a37ce1d1580306e2b67a51baeab5d73033fd4fb40657e7fb5	1607681631000000	1610100831000000	1670753631000000	\\x3ef318c58ed6479a04d47eddb1ecf1c82bd9e71dc52f40e04751fb4d53c44b289059f79888be7c366f57f44f4175cac6815d185c794cd7ae7e05195c66b21602
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x2e23f6bd0b7b7f2b4ba1a4e88da679114ad4ce55f77fd41d4b5a51393cde259a635c5803d1392139d5b25d073c148a2cbb4b87e03fef85dd48b4d34f7433b90b
2	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609455600000000	1640991600000000	0	1000000	0	1000000	\\x1914c5e1582e3c3a75c6908aa8e8767b1340152a63f4b224804e24e57e6c4ca43a699680485e8eb27d04e6a6fe05bf5fa402fce2a0a5f0e844bc17d8e9eb4a04
3	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640991600000000	1672527600000000	0	1000000	0	1000000	\\xf836593e8fc650ea65212d934c4d50cdb38b4e5ec83de640e18c6d3f528041f9d9d6fc52b3fdddac7f6424b06fdeb0546e0b7885b08dbafa85094d93cab96403
4	\\xe31534d5fa5f04476c899f2ebf1963935a0b4a1fffd99dc6e736dc20b3bc6811	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1672527600000000	1704063600000000	0	1000000	0	1000000	\\xa1aa92ca7ec45340032fd669663a206aa14540163ebdd5c86573706c397e50c63087d8b65dccd0e981f4952d4d502bc4143b566cca9ae540c7cf76f530025b09
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xccd0e5bddf72e5243b0064c0628ccc632dc405ea785f8a0d0245dfeba31fa153	1
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
1	\\x99dd67ce39ae90840f538dc6ab487ce0a101919efb4e194c4223669b3669e6c5be3ec626f63d1b7f4b333bc7595c8fb6624687e075db40a050521936ea57140b	2
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1607681647000000	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	test refund	6	0
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
1	\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	\\x0948e251168bcc21c847d19d390a217b2200519b24dba58aa20d52270a11765d	\\x2656b54c59fd0a29dc3c79762ee868b8767ac42d0758de9e150340c67678dacda7cf498ef27e40759338c8b06005a4f9e7bac882e2d4ce57c61aff73c3a78d08	4	0	1
2	\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	\\x8f6d5943ba7ad42513d2c045b4a10bafed1c4cfb953ab978e405ad58defdd31e9d3a3a7f0b3a47d06deb579b0c096e51c36d75cba8630de1feff7fb91e82360e	3	0	2
3	\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	\\x34dc17c7a2bc0d523289e22365196a64d0662a9f8b24b3c4a14e29762bbcafdeadbf79fccd859c7ba8fd3496b0dd56b5738ca46525aab8952406f6b9e4d73c0d	5	98000000	0
4	\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	\\x406a33149ec914503d2b9c9cd5ddeb410eb2db53415c10654d762d5952d53139	\\xb8ed55d0f887dc156fd86dee7468d33960b4c0c16e6fa3337c51b160589894fa4c796059c7205609887ca11dd93632f1e198882bac9a76cfe47eb5c11e851b03	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	0	\\x81d758113ec86d5969b21c9b019ce10bf9f0ff1936dc99a15c597cb155ef211548f1ed723d66ec15d746fb736ccc8668a20e3f17b8bcee54e358ca2cbe15f603	\\xb1b658134b0435bcdfd6bb88389aa25ef418a5961362dccf906f447d3185fb64230bd16123c00eddab5e78f1b237ee82075755b47220594ac51654909f570092	\\x2c94c0e58450fcc1010213d6248961bfa1c202035f87cf3c208e21652516e099b6784874c5285af1d922d30c96d4f79ee6dbf1c6632be2c750e6b6a85fac36366128e6b4e66447b92ba356bdc4cbc8e08807be9d994ac9f3bf82ef2431755a195580d66b71596be7e7c81668a1c862a97419076d92db61e69bb5b40ebd0e6ce1	\\x0a58bd29d98aea5c4a13781de94951ed539c8f1bcc0569a724a71edc1fc6204b0fa0e3d11a30c1006e862d12a03f94fa11118e995fcd008d320eb5c5f3ab506b	\\x4f048d4f1eff977ff2bddf61e298f73d8d4caa1d408abcf0dfc0ef3f2a8595a99e60dc7a5cc5ba0e3a384071d18dcbbb6a4f712f1deaeabadf9786824cda1f33b237c6d33ade7fb70b0887202baf8df8dd37e56bad36efdc5d8f000a70aab60c9929bc7ff32ce655e98e40e76075bf06415c45195b7db5f225a7ba6f99cae59c
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	1	\\xfd6cd523e1afbf49e790079f791c6c04a53f50de8a798cb747bdd9dd2c4c26cd22e73e6aa088764f360fb2e9feba6b8665d067a681cbf1fe2b078a517f54f90b	\\x11a3eb19bc7a7a6843734e389a4155bc93805e7eaad70a05db28137d882f980284274ffff9ecf34b4d9940591a4b1ab909e13f720820967dccf1e85ec49bbcc9	\\xa12e7811d8a0ec08e927aad233af6a285eeb600e4c27cad6ccc2fb1980947cbd048bf7992ef99e9ef5f7f1e5a02cab1c8fcc88c471aa757357d8653399235e0bd4a358735f6f32509c43f8d9fcd6a92e66cf1a9c899d286310739d8c6f07712ff7ed0fdce198e237585dc85995b0fc97b98630e1af8dc27a1615fc1a37875d6e	\\x180a44ebd1fd9fea23b0d231f3a0d36ff605ed458318ee146f08b5140a8bb988d73a0adb27f4cc936f42435d28c05c0167750e0bf490c6ccc9c3e5b99fb189b9	\\x4315282138976e8a02d17cc81848191b5a878b944680244180888ddca9d3059d9c065ff30467b63737f8e8d636244f4fdbd253e0629b06f28f526301a9860cf4b93d952fddb2254b5645385553442a14b795b53d7f0c4baea1552a067422b8437f8ab95675ccaf04db64cad43b151546251294fe94d36ab157cc5cec4b81e753
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	2	\\x01ec16f0f394f4bbfec50d1a2ddcbb7d89a93be70b911c1e57a5a88b1cc5bd6411292f64efd182d9dfa62e0edc376609a3ed40dbebb58d796fe5004ea84fc905	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x153f65a6591d69c63dec2e6e307f2b7e3d8c0a3919635a2d85cae42a0eb388f9ea50575813a4a4537e873da9b4654704a4b20c9cc1a78feea7f6caffa57e0afd06a5afe79c552fe718a734b0edd0db1bd2104f8d15be5c9d0d0a27910eb03a6ac8cae7abcb5f893546656d33f244670d7e97007db66a5f12d6846d40b20d0112	\\x498fc77ffce69c8f45c0062e66d16ae7cc7eabc990c7d56edc855e5201da2cb29b88608474412c61b502f5dc5e7737774e6ec81b188c7ff13b0679475529b10f	\\x48f3d4275f000a1245b7b346a4ade0a5c505bf3f8db85dab89ffaa1f0ac842de95c677d7e50952e5c98e3ddbcdfd2c4122f5b7f36ba6fa0455623561b8b8ff4c7f351f7ac3d0b17e16cc45e05d5f6499a5f749bc6dfad0fdee3a5449e9e81a5e01906b73c9f34bcf51032ee0e4690dc5c89f9d91c86116b60ec05ba2e88ba387
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	3	\\x3f073da4ca78ecf18fbb0104f9bae88a3df51517c24735ecba60ab993ab3212b60a95c3af1c3161535e3fc0e89df50b3eb56531c7c0cad3fbd8f65053971ee0f	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x585c0c83e6d9ca7fa7fb2dfcdd85099189067fcfbdbc23b259d6d8a49433d2b4a9a433ad58edc0eaf55ca30a32f7de74d6dd44c231f2a3177608b6069b02e4035587bce3ce81b407067689ed2dbc843d0e7b79c9532a76a07adf90e6a9a03b3ce4ac030a1809c5a7509d19317722eca2d9b0201a10fcba30a72b67c6b9ecfc06	\\x4565e565d184800dffb26d8ee95a565d3022392f1f195c0ae069b2235137df42d9477ba121b446abfec369109f549133292738945b6e4b8437219b073391a114	\\x7177267fa8a22f4020ab1b0a934a751c2ff716fdb3703dcb1ed326bf292c160bd24d76e9f1a314b1783a04ee91177aa944e7cceeb60d3edaa3789de74cd78d6993ec3d58b84bc4006e363d27c9b33921cda4490da4f20d87fb6b63847054bdecffdea346dbcaa612a3e6c47c508c3a4af191393e657baeb995d2ad16b8ea1e2e
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	4	\\x264f14dc19814bfecbc04892aa59d67687b248b87ddd4e9e043895cdcb15aa9b20ca4968fff88a141e89ebbfc2242e227cdeb5fb1d7d7d1a199d875aed712c06	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x54d71dba733916f8d08183ea2d7bd977569e71c07e3e6edc375957b55ce690efd011a402338942f041f7144d94e08b7ea8011c54c0a68147bc39f274ca59e8306cd8ca1aa258e16d4647cf598a524a0bab1c56b456c2c9348780f4744f29525f5c266516336e30b06f7d791fd3ff90ebb7210465dbb978c3cd05eba83bf9d43f	\\xfee0a40129dd7a4418ec8067a764142580500389ffe64afcad0554f1e2c918eb9e59f304ca47a07f20b9e59da132dc55266bb6f57ce645997948f8b030916fca	\\x830bb318e1fdf59b2aa927ba47458892702e95236f1a46eb403ad2ae06828b300a97faac5f4785e82f26c312936a23c265bd0dbffb9674e86b9d071b09b51d005e1d4da4a47775ce33179bec915a759d6959dbb203f849da9efff4676fa4112c2cd55a8a2694b207367b33d64949be89fd6244701397928d0fb2950cc9e85774
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	5	\\xf5041930b84edbe243d7cfd37c3d609270e2d9db8a04291a52eff70248792427b13c9c2dfb9ca0cd3496919fc30fb50b17f1079712464c3aee231e3320028701	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x536b01d9fa25f034e3f2eee469d8ff22a482c918839e398cad68bc631f2db60363c28e15f432c9fd26b5c396b39d50c10a7bf75c857253b7c9cb5d42d07df49de98a61b58fa941cca7e47d2eba95d03f4db9e4b78fdfc7d30e98a47c6765d11bb92f15c1258030ab9bcf744d4017249b6a145e780a4adb5bc0a4aabec018a6df	\\x65396fc26a6743079ddc14daf7d3dcd9ce59f7b43d035e9e06bfc1736ea3717805852a56cc0902c746d76074173369602540b2a8e56424656174cc006431922a	\\x979496d69806cd912fdc895cce66b37224ca81cf26288b1623e2e3c019e208643fc1796ce2ecf7f62d44143d42bcf7764da4cc0696469971dc78bd2635e88db9788dfe09a79886edb619071e3f9ce680c50a0e69fb9963cbefab4490caf6c7c47988168edee24dfa4d11227df01cf04b58f4309ab9d6cce336f58978de265104
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	6	\\x62535eeaa3d84334055d2bd1456fa8b5677321a8d708e9cf096d3d92a684046373e79299a9683ca0b832d2ef836e3df7e3d7a26fe6eb7a39e1873424323a6e07	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x4fc72a65e4be08adc62e6855a86c4431efb4701cbeaa2ed244412164314e29af269f4810d9dabfe0b06a65a2eabc5da9072a1f5a3298f6a25e38b1bc405bc0762cf437ac57524c9e64842488a7ab6625ceee1df08264920ef3781710f96ddb57aebc37d528b4c10d8da0394807f3043e6d0933f32edfd99ea62d301590872f45	\\x5054b92e34929aead400ef64b398bb9a776b4be8b3816c65d7bbacdbe678fb305bb2d96082a3a77aad184c9bacc720c7d5ad9ec256f77b104e568baf25f7e267	\\x87c3713819d933341e400247c99bfe2eae8ae774dae3d6211fc996ee548ce8429998a061c933ed2c01da4f19c441be074fbfd9b0b956f88ae42847c57a47b1ec9639beb167085bc778fcdb3540d5ad9c777d0d48231eddeb93a732964dfcbdf0e4576a11d540d61c7a90580e0e1808f859685d74127974881f55ffbdc75b0d60
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	7	\\x9f7c91299683639684e323c9163e1366e1bec772614aa85a5744ffdd84610c385928e599065e852a112ae386148a9419450fe3641907f87693de2914bcb6aa0e	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x825ae20b4cab3cb0dc4a064a38a1dedcb156cd37ebd290462f377a68c14b2d39a150a16a05f172c47a1c850875e25dea21997665f22f46043cca1a199e0f6ea5a955dde2e31773891925077df6e348df0f5690b5c97aefb9aa6098c0926e3a2627b739684cda8580948aa88ef71b1622b2e2445cab3a92525ec0036c9c378435	\\x0b74abee4752685b21f59419ca03e9b2a4fd74bc920cdd1499a96926395cd3d49fda1130e03e9cd91715ddd4954643d319637ea7f2b4645ac4eaf46a7058c40d	\\x6609e2f8b3d6d01cdaa357a08499942c1436176742e466f7429b79f4d3262f7eccf16a90e305693d880724902f821f15b645a70c7e2fd47e669b23016832e016c0e64a27e793e17be8983d6acc93fa01638cf09d0af03e3079268abed3454f89c978514eca2d8d580308746989585d8222fb474cba3cecd23160c3ba7df5e2db
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	8	\\xd7e20e4c182b3b06dc823c63d876de45b185bc4ecebeb699b8996794cdb091a4614d5474690623ff0cf0096f565cbb437ce76c056792b0da064beb0297c99a07	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x07f789334a73fab5977c55a7f4ba8d2d67fa0c5cad07c39354262576ad5c2ad42484739b011487c1fbc2e58c46a408d3392de5d1fd03ab7abe5f17e47052842aa6f0c58e9272b522955c0fa5744203fd0f7d5895cb8a5dda6a5f496f111b91fa5122100bc1d00b537ea69eb73a608135c0a4f9d56fdea40a1058e4dc3afcc5e6	\\xa0bab6bda4de2db0be37a9f8b494ea1ea13750be5effe03bf3099eb155eb4a1091f7ad0abd105c83fbceebe9d3d2c17be631d89b0c1db2d7cc2ec025baa311c7	\\x71b464121aa02760c8b0952f200669a1c58e96db843b0d652438454550505b3b22cecbab6c63ba13a81dd425774e5d7eec5f45432936d086bbcdcfc698ae89cd19f0b5f235c5393e756084d4785afc7e5fd106df34f0c0c864ad0fc4018990a8c22c9abfbc5e6bd4546263e1eb12cda8438b971431c910de0fe2ead68de699f7
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	9	\\x0629a1c25a622fff898cc6f8aaf7cc4d5138ec326dd2e0e7d0176ff2cf5e5a995c4f784da425236edf3ba4c1f36d0785cf54cdf166c53e7abcaa822a31174d01	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x2cb131fac939df59587af03f6b701163aa6df85522bd0222586532a8c4ebe217bf39024dbfcfbd0b94822ed676f4eed61e4efe260393801cdd60813623471dfa6589d594abc1da7fb300c4a467bc5c224a95c024d7e5466f52a4cf7355293c8c264640cae2a368696afe5f65c9723a478b9e6ba8efc55b3fe3df6c4a50a05dbf	\\x2cc4a3d56f8557a8521346a78a87b6a76f8abdba9a050b90ed976c2b1960b94fb046f17ddebc669f1d46d9a77e13c0403058dbb5c33e3875f98940974a5c9296	\\x66898e9c05a81f090295d42220ec5d7ddb77467a8fdf877aaa59420170f197ab0bf6d8468abb9745dff31646b4c34cc11e03c035b1157bc8a87f922c41e062318d13b6fae82f09236168fd5e95d22f21c3da885fe1ee3e1623a52d7302dcd0761a3030fb0ea7ba6c47d97910772d5abc8e93d033ac9f8a7730bcb105f2dfbaa0
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	10	\\x7b8ffc7de6664a94743666d56762ffca8f23160750fece0203d61750c0d34639b85b43b0de01538fc0f99f138028eaa86d1ba549a11f639bcdb2114dc5fb5c0c	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x1233a835e06150ed1516239bd9a2e591f360fda3ac6075438c84696abbe04bd292aad47632dba765e989fd2cf4ae42b3163b6ff7d72dce5f037d933881b9a31948b639a78e19eabc1e6de565cfdf8453194faf10d6e76a7e26841d161530b7ecfe48cd5e0dc432a94ca1c74822ba854782af8d5efcbc354d1fa93d12c44eb731	\\xb06da8352fc30f1981317b5f01c19fa5f2e94322af25561b3800ef3bdeecbd51e4324f4667cdd78ecf77ac36fe346ada43c4273f03c457e904e250cd0bc583b3	\\x9fc36d43455acf97a57c1d0715e4915da3551cc9264e0a3ed1fa0391fdef6a135c9f6c8a2237f39fde1e10b6d7a18597564801e48e5c3fdab09a6064abea04b02e93d60d2534a1493da89713040582450cafb33465a68dd1f4be36535f05a84f8fe241b2a3e4c058c4b947d97304969ba9b767264a422ceb85be42b5a4c7cff7
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	11	\\xd266de1cc38c0aa6c23a05730c47059dbe0472222a6b6935282db154c33b6c4b9a3efb6796bc293d117e9fcef99d6d1eeb7a4f8d117c10b2fedb387db1519d06	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x2d84dbd40a79d1a0385df575d011062da26dd622c76ce67f8280f0fb38f663955dc7364605b58421d09c97e42236c8b34360656e55bc29a17c05ecedb1504ac11e2663d7da82989cf19f1a03f2660192a630388edecc66c86eede6274cea81ddb20075833e11709b51d2a288b484dcda36c83058033b2f0c1bf165202ae894ee	\\x90d4c821e866be2397524f5c058776e93aff63aec248804cb93c0336ac0cafdd459b92b7521c921fd067c44628e8f8f8fea6b1fe938e8da5e6dcc481c232c0ec	\\x7188b6c357b03863a111ba76c62cc176c5440828eb05b4c6cdd4049e4d27f4856f11ee53a9e90a1fe93f8fcebeba6f0da4e20fe6069d3184f60d58fcab451ade58facd35d9e9d751842e22b4bf0395ff28f7ec5a76a4901e893c50f9adddfd8ac4b780b8ab2b8f878e2bacd8dde195d27d9794de630e1c69defc6d2b3bf9937d
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	0	\\x46666fc9e18fec130b5548f9d7e947757287d267be19b6dd14eaf12e2bdae8f4b61c95136c921a920ca4e4164322073e77239ac2064ee8454dd34d50d49ff600	\\xb1b658134b0435bcdfd6bb88389aa25ef418a5961362dccf906f447d3185fb64230bd16123c00eddab5e78f1b237ee82075755b47220594ac51654909f570092	\\x9c398f03e09ad5f351b6bf0593251c686f1845be7c8142197b04c92ef14d75cd73a187d6284f2904e179ab9a3de988c666fff72c4d7af88d816a8e161a2d75392de368bba204b7fe1b1f95139b471178188d12f05fed4ece96525bd80d4bc0593fcba31bf1900ce0d5465253c5253685e998d8fafa056f0d6a6d739168a46821	\\x9e333ace86ab1b1ff30be326c4c406f697c6b463027fa6082c5023e94d365f9993cc670c150bc576e6966e9ff79223214846396a87e45fcdc5b70d00e3686633	\\xc25e5c8dadc57d767773e8de998f64e6ed35eecb2eb7ed87d33c3d70e3e95df26573b1fc9e8f6348e387e21d36c5d975eef1bfbc5775b4156a0d5f15a1cfa69e23c7edca8e33ea46d1f9781ff57daa3859ff9cdc45aa02c431588e29e71a646c95dbaf3a4cfcfe720108d21720200fce9304e9a90d945ada59c21e4779be5799
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	1	\\x7cca581e44fc4f96f1c94aca1bc2e700da760706ae56b7f523675d83eea0b1b7c5c4cd9d2caddf3f110434ffc48eaf947c6a9ab545e845d1e49414225a3eaa08	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x86411a0c14ade0d1362c8748da71140c5e304444bb1d3cddd3cfe5fc99e005e7d53bb5357df0ddf77c7015205c66afeaeb5f1a7a38a606a47b10f428073d236a9ada385f3bdf4e573e6716afd991c59d31fff738b6ed4ed5efc92c0d87d0058f124a2460d19e6fc086b1da142f56d3d81e2afe6f8d96bc5d4464618c49b2f759	\\x8dc645a82088cc72eece843d96a601057947b836b153c37da1745f977f5fff20e70eff5632f3ed511484a14842a7f12a49a03ae05e6d3efffd4fdc033146384d	\\x2207ec307150a41296e5e12d43f012ff4a24ad532e3331e149f811dd6f3525663e5635f3ce3688e94c6b5d7420ad1a7d303f2d592b1891317ece047d308f80916879d3185f1d33f6a0114dcb734be164a94348abf9bea2cc9e7ed30343e8216281d27af613d4bb07b3c53a60285b8bd04d1a6d09d443af52ca1977d6bbd71677
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	2	\\x8be8b85aaa0fe0211bfbfe04a2ab101ac424e5042ba74228a69158ff355e67e2313e88ff1b8c76486ad6c2b5aa028ec88dd36464ad5a37ac040888054a5bfc06	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x746293578e3ab3145cf8d6dc104a170c411503eddc7b04afedd28ee1c79da50f536ef133d6b33bd5055c38ae8bdc9ac9665b4522e680ccb2157efe8604b540accab7e4b7729a0f26743447c56ff85c1756b826d18aaa1586278b66f292a5f8f9b452e4f1578bad0c28dd405c5417ef3b4f9908b6dd992b335a84ecabe2797f30	\\x2c16c6039db1a435b335d4296fcd1d98be0c42fad585c4b72ee861b71cec43b6f84652f51b6ec78d52f14d891d3c9c0be575286fba4f0eb54f2e872ea2c7ae46	\\x5454fb865bcca972b725dca8e5f57893fddb89d92ef6765d2ef0870c7619d4e90c9d65030bf2225cc8eea14506132ebf3cc70e993dac718890853e5dc1155a971afb67365e66b9a9590fd53532e7d5d27b0113a715a4d3077196bcaf689c988fd37b2f1a9e03adf07a0ccc2faf490af4f8a97b75d8776e17a370422898f26630
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	3	\\xfd67b8b17239bad8a6a38e5e3f28538f39908708d49ec188223121e118f17f695c085e8ad9cb5d1811fba58c05f64ae0b65b96bcdcda26b51bc928f23d41150d	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x7614c4544c181449297bcc5fbcb236f8dc2e0adb78e1701a6d0198e9524bc78c4020c384bec4f82872e9d9ec4fbcf0a81c8dcceb1ac831a97d47aa48176b6198082b70f9f89dc6c161d172f2fb78072a94b123a9b562ff155028adf96c7e1deeca83c650a3670b1a33423952fedc90ebeeab24fff73f8a3f760563e44732db9c	\\x99dbe8a7c5a4f4f9e95bae2e7fda669560fae53cc2f22bde1532e8e0c18e4df37c24d516832a04000f7c98cf881b1ef5b44a27f50a3cd7f63e228703534b3034	\\x23cf290bbb9ae61292f35a226025d3fceab07fdea65b336e000b0c5e7e6750b4b7a29bb16c4dcb9461fb52b929545e6c38efeee6456f002ff6789092ebbbaf443de1741d5c75e0d626c6254f9d4d928195e1e5711fb634a29edb6dbef687c8238beb35d007cfd9cd043e91512943f970967e01fd9f26aa3a7ff7823a2eeb3c6a
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	4	\\x40e34deaabbfa094d18a237bd01c1f9a78974b079a7f15b278ddf84bf9b8e5b34a23c1d9125688e4bad247e66241fbe371cb277644ba042886fae5c7df1f8b04	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x1f614ebee777a0013cde7e82d1d3a1e710a77b83f3b537112a402177997565ba38e62f2ec4d62e0b4ac81f7f5c7a99f22ea0d1637aa6130336ba962d13c0132bf863f94c8bcd3e1bb740c43664b73aee747168731bb45d83187e511d7dec1a21d610cae3d8e69ec532ae55886a676e7e0fe9cc0a8c6133a3973fdda972cf7021	\\x75429b8cb046f299698d8345a8c0a50810a021646f37a793a7f69d0541687bfd3ac30d3f901f3a184d9367cfdc503bc3ed9a125ca036d2dacc139715a25517f3	\\x1a8aede282a3c373f3e69b90e8de142d26ee7b226f218e798856cae992b695f352a66d8bacec6d55db64639a9a2d8081d2f42c82cabae32167562df9faf6eecee75a1571a6ef5ce17beb7923a9633a48584abc1d3df7e9c504d37238b545b38acc896fa6d700a119914a5d1ea7032681d8b4c94fc28e914c58556cbdecd4e45a
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	5	\\x07638f07fa840ff7c65f7757a548bb1fc711452799816b48bbb64bda402c754550172ce0a537fedf7de0e4d5fb80bb22c7e1b6310b422158b268415695537d01	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x2049a44562d68d50d57db00aa0b3f7e5c870de57facdd5aac9bddcd859fc5ed8433f9adbd831f38af5d88921991366ee45f0aaeff805ae10d4d7405cc49cd65d4b723c33d9a951bc21665e9c15bbac17fad0a8f4c2c570191bd2fbfd4db4d83076591b8b8c0913a05b62e0c8ee85f8e67d4cbd4134f2129c5fcc5b438528155d	\\x69012bbc3d718259d1b1bc187db05d7c1ebbf19f470336c1d0fa6b8877e9f6d7ec36c47a8ad127507eddb77e49518a107580c13845ae19100eb60f1c7000762b	\\x02f8baac53422f039f92bca60e70a0fe08f9cf8cba9744361eb7997f99297315051edace57cc9cc197968459862d2cd9c7d401398a37e50b9090f664eab9d8d93dc5409ab2376a4d82ccde5b529488ec67dc371e57a12dec0773a0b88a0a1dc5b8071c2bcf1fabd96280dae7459cc6545d2930bb789f151c6253e0027ec24fa2
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	6	\\xaff842e918771ac112dff881b07d3528be2bec931825940381f625afdcb1b45a6777a6bd488e91600c16d9fc32ea5cc07b1e593479e5df43ce3945d3fe372305	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\xa46f29c161cc5bb85adc1589220cce623c716ef99a464f4f3c668b586223f2672685a9d7f8ef3e1377d58f7d3a9861a1ecdc235f9c5c7356b482f07799356191c4f0aede6a5242f2328d61f8d8e8280dfb062ed5d21fdee7ec30b9f8e6bf217a5dd574e2356faffc8071c5259c5bc5189ccd0fb0e1e3def7fd60690d1dcec519	\\x3298ee5317d50314ef1a691d3f892ed45663d95c53ce9cbbd1081ee36818bdd28e7239c127343060326baa91eabaca230d253c4eded450bfaa6641f19f4e912c	\\x0c31cf0d9bc3e45cf8c0c6f4e337c3bda11fe97d9e1301f61a3cfade58b81dbd6d67d7427286aba036214ac56dfa83243978b3fd59338b56e5495796b7808755c4626472fbfb66aa5c899a2e9778f8419832bba4b44f0332ef1cd8aad59042839d148b144ee4c960bce8dde754cdafcaa19f0568b5c20925141ee041084095a9
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	7	\\x3e2ff4045bf6400a8354789f6571aeecc8f8dbfbbfc6bd773e8593ac13af9622a66b063e63c2eb4b3aca5c6d25679b449727fac5dabf69781aa8a42fb0e7dd03	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x3c1744eb5c83bc8c068fbfbea98a1884846c0532bd69f59b83e63338725b919324c97758afa45a9a88391d2105062e77ece8f003b023c0f92edc3bfa0adf14b95d339598d1c205e02f416325ef131b1b01fedc028fc9cb0191b501926f12d0c6d0c70519efd77bd28b04c83d4de33f88666513e44630e2095bef2310da359ce9	\\x1a7f5983b4f7c097afb3fe8c1d89663372e56c5c3eccd55dbc1ec5dd513bc2d6ce03bdbce3ec47aade6fe959dbae561a811a9f970c7bc3f66d06b26b11d99f03	\\x72e8daa08e23a72e6c71c48ae602ddda38fe7943328f771c342a51a0021eb6c2818d911c0f7cf187f9e10c357905e1581b4158271e1067baa682436d82fc8bb187f533d2ca707e9b2a6d25f741bccd2ac15aa75e0febc639bdb1bbdbc85d4574490c52eb82b80232c3558482994869b3b99a110126fd58e5b45dbc0bd78a57e6
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	8	\\x6cb7f5d0b6a2a059bbf420bbd31e7c00384f7229870b9a3c9947c578a2f2b53839876b6bd644d3dc3ce6e55978c53a207f04dca1fde25c5289b5d6302441450a	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x53f8e02cacca4307f46b167dbc78af17c6fd6629c23b883c7f4a1913fd44ee0604376d77ea70ca6c3cd439cea4348468b45eb15280483f7194ed02d0797de2de1445e32f8b4f4efe217bb0828ca7e0bc42c92a69ccb66c6afff8d0956cc14b7e7067b14ef54507d9fc3e421d86bcee906cea8e1dd411ba2aa148d91aa0177439	\\x2cb30aec1aabc94b8254ec7f623bc0d1e15c1aaa2766f9cfdfb1e23b888628e505d09d3915252e7f7910d9f644284e8d43ab410b462131e28934bae814a85c50	\\x245748d71bcf503aca5e23f8f99fd09336082573604049bb395d85c4dfc456304b7edc9f8e83c13a7de334568bb4cf598c3e7c2b7e418b42b87c110fd4eaa706016105b39119117d1d8c90b33e98b4d962193af1ce327bbc46cf3f2c2a90552f48cc6a7391523dbeaacc9c838e3e825e362d664a565932b155cf7ffbcc16abd9
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	9	\\x2bf01c2d10965d0e743eda3c9f4c63a96d2d5323a7ad2737810938b51f8d2666ab48bd11ba203013dd0acdf68c610d47bbae3b3c3bd2dcb6d3fef56af4108308	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x6d8657d4b9a26078d07022706875c7014228acb9b067ca2e04978b6ad7ab61b8fedeeee141f5105341d5e9480bca44fe0f577fac88f1b724fa006a13225252f7fe970674571a9d595a1651a950a13e57f4ca8c9ac039e6edec0a22af209f7bd893805414f410ce26bf55c34c90656c5d2b180522e492fabedb7f6b9c4344a5c2	\\x486b7fc89c2402af6d027cb1448afe3154fb2783581039c08e75cf26df7e99cc7464c4a596b8089fae095409bad2371219481dd4aa0289dee8fe176c644316b7	\\x69ebc4257788117591683b670cf95e27e0788707f1dea05975729ebed5b45b0f11cb25c35a07ac1093f0bf8c8c03c3f7f82f32ae9b94194b220aae872de8cf5a6b13eab48df7f9033dbfee2f3be26dc9af05fd3d01d3015c0e4d9be83bea1f2e4d61efca8fbb88d53388733ad2e283bbbe333f1b833fc401fd2378c2dee07b45
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	10	\\x98dd61890ea178bdf068ff687c5a360e106bbbee670996a26c79b5943f0ad89a5cf711414494472dfabecf68ec8da2f391db2cb7d4e346bdbe46e9baef7f9003	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x6a5c06f5cd963ba9b595d16aadb6300494eaf81f06888eaedd456c669dbefd0f71fd0acffb0c10a36856a83a137b5e93b30ad52c1529d3a36740a55057ef9eaf1df56e5ed0211856667dce805659138184288282865c6ed14673378cbd6d4d32db71383dfbae80ec0441c4f0d19540dbb3792b38a7bf2191eaf903d5dd3e31f5	\\x83833553dd00138dd9a447b9bca98ec24b26959916260b18fc8d2a5d7cbe699ab8b6bf5ffd7cec9595acff3347cf85cd48bcf74f3bb227e867861224bf45b74c	\\x6d15ed3e60d64c6b50fd2e2e7b6f64833f9cb096e5b4b7c4080fabde973e3d7a492b6a0837bb4276955c1c98fb30135f35a4d6c45ce7605156b770824f1a9ebfd498e8bdf009bac5dc168485eae396eeedaeff6c0f16f762bc2dfc81e60906d17e5a8021df8182ff656ff966d0e9af384372be89205eb8f8b227a4d3d655a27b
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	11	\\x38b0ee9d4c879c1c8da35d2bd9d3667bf8388ee40e3f9aeee886ed63e303f5308adc6a6d504c537420de3e8b9f5723d092241667b12a004e98662f8e5097e208	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x9fefd4e88f22bda79bf1f2d11b836d01da5f00d14c2b816edf7903ee75d6749b5d56b38b9a8d48b72ca7af5884fa5ea5d9adcaff3a07a3d6ce16d4a4bebed3db71abca5cff40417038374a774138ab9cc43d1970a1cf9e803804c91fe6bd55baa09bf275004b58b8a82f2a74ad08cf0c4083c461353a12cef1cceb15ca5c7868	\\x2a4c04bc875860c43c954370b4f371b98d2b49942aa7614b8fe538e94db02d88508dc01ff125647fa7041acfba96b4ae50b86982c363912ee95ed89b5269fd92	\\x29cef4baef2dbcf9d84af973e27a63c8c0d71a9aeb87522c7a73e2bd349c5825df43bb6443e4bc3647be208e72d228bedbe1a8a40a4620cf0cf145b78a33df292b8a8cddd1ebaaccba17aa82a78487da4ec7d15498daf3ebacc4d8c58bebc3c269781c51acf43d7cfbe3506aa26c703511d83ea4c0137150feb19cda06c499db
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	0	\\xf96ce132f3bddc4cc5efe060318d41b8b58f77ed6b9608d4eb5f1a9770f3b45037bbd85f772f6cf111aff782806c05ce8ec77f948625a923a7526283bf47160a	\\xec808800c3bd0ac0a42f2a0a392a2826ae8b87ce92ea0fbb1050b71d2fd2dbf463e08ca58de04bbb781e9cebb1eded0fcbe7e1955627dce4665b8a7045751b6c	\\x0c0a7b61197bbae8b2edf155a50a8e684468d21194d7f22ba54f649719234b11103a0f0f69e0a435cf2f803cd73e7ef352ca923ecfa60b6356f69d0ce67c6627c62cc71e3a2a3d3832723e62a0c2aba42cffe1fa903d2329261c2617b68902f94fefe5e929a6c83ab8e6299a008e7559049f35b9f4d5dc036787ac54fd22a59b	\\xe3675b7148b6d7234102ee223177c8ce57a1c3a6a84bf527d8803b61d8634ca07d572d0cab9a1e29c82edfba7656185075474d27cee46043092b955e4a12bf9c	\\x7b7ed0beb9996637735fda7f10dbcee85465358e1c73dff17af98df5999e560f529f8bdc06e383c65d9a6e15ed5354dc963efdb0e113d4ab6062a3d0f3a1c7acf131b047b19d412a5a531352d62ba2939992d15e81ae344af6fd7018e4c4c7ab68ad4bdaf3af3b8afb4014d5aea7e00b82d65f13d2320cad5ddc5bfb875061fa
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	1	\\xee694bcdbe0bcc3d753dc817362bbb50116c617235a9b2850185fc9f2a17fc89ae39b50814a0d2c1050b72c244ec7139ed8a29f4429dd06df550de94a099c006	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x383dc4f8c76fc6c3c105fc53b1aca902ceaad024a019e87ab30df7f46fdc44c53fb97327e14d2c4a86aa3105e0b73ebd903e51f9f3a1cada826466f0dc41af98cbd93b2de384978652bf45f601f0e0404121eac6cf10756f0506babcdd47ccb5feab6ac243b1f7dc72389544e471009490062bec531266b8240f4606b75a236c	\\x82b02877af25ef6ed040e115d7238f7927871b693f3f8447cbf8ff69bae03c5acb0738f84d6baf0268ee02f36aee638d15cf999a3c65a6aae9256db999a16419	\\xa76f1d4ca5316ee4aba613404e1ab9211d46476b4ced952e2fd6eec7e21151added17ecf6d807f7605c49ade9c058ced7176dcafdd9c10a6a6434216b5361096f0ac64218e8552dedb58977e9e0063b792811f897e001c65cb78bf49179dd9a426427277cc9a5ee094ab08de6a4cf1fb5979f415c64f935b87d696922c862255
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	2	\\xc56a68610257b718c4401192f70e107a5552d2be1ef3908af9b5882029d275df68efcd63a71aa6f251e4ba9c6d2a490012f88ffe4d703c618fa485e41a79130b	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\xaf1fceb54e53b042b61c4185f1a88d1ca4a4a1971dba0af7a0ff7bb57f1b28f3cc8fe45d82bb72303a3954eafd2038926a469cc55e1f65ab8121cafc94f570d249a36561a661ef71b0a554b0e83c19f2c30ca5c0b40b06806b9dbf16b3c103eab7689935a4e98d64d11274f7c19eb4dbcd1eccb966999d05011c197a0c98287a	\\x18c2f410662042d48905caceb78e398d815412cc152bbc2c4160dbe218cda9df814d112f223de7e48020f98186ba4b177123af77dcd800d7d38c725fc758004c	\\x46c67e8dbdb7cb7a86bcb07f6969b4914324ba125bec3cf6882a6645d5f0bac372f80a50d97f9906203d969c2a10da290eee819523cb00de221708839aa7ab25309de2089226c64ee65500950182c6e185fc8110044960b32a48bd7e0f8732d33b0e7f08b90a16937bc355257b3abdcc9a9d634a6d78c0d6efee0fa8a1ddc5c1
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	3	\\x36896a92e6f30136e6d013b1173b3f3280e5846fcaa19a03b7a47922dc25983be36ec77616127a521d48e6f4d93b467788ea6ea316e3f2d0d162afa94ea30509	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x9fa8f9a832892a050211a6c013645b9e39e1eb53eef4881b86515ac471749b854068f0d9a8b6e49d5974976351a4270eff7178e53ec77e8d4cf04d9db484055c2b78f196d877b7620f9e64b581afb61f7185375b9385a1b3818a7f7bf6400a79d28a352d7a53644d5b78786d604cd445eae346e4da30e771cfb840b64803f120	\\xbd600d5f0f1bd6c69bfef41e17deb52dd2db6473e8bc59d8bad399563e3859ea6c2a119480ed52b15b8e310cb34021d1e549b17869ef47246ad227045a59aa18	\\x119fa56e7c799dc025052e2f020b42e133e870e2fe0fd8eb040c3e9b312a51ea5727e871767e2b993acbb0029a23a2654646d81cc59f7f9fdd61fc9b1b4f2649e6b7f2cf127899e58ff5d578dbd5d85975e5ec6d375d951424b07a5dacc1808abec7192d578bb81fd4155e4d2942863546ad693029f7f3cf4b02b9c3a502e54c
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	4	\\x6ed95d9610324f966148d3a2c16e9d1b009b3675ac6bb0fce970311a8fdaa3210af0cf0da7402b28b708395b48f2b2d3f43d474eb495c830c253509722647303	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x3eec37482b4d8dc4b2300391ed3e40564bace16ba7e01a0a966861ad81dae0de11d0beb6605caab04f2c544fb8b419c2076dfcc1a02fec816d01b6ffe4f352f18c979fd9d4b20027d3e059669140ad64de39464215f8a930d5d4c561162b3344872686d1e3a785c808ad78d2ec9a9349c942e0e63e342cf9583392c6983b9fa6	\\xc47a950c931ead5514653bdd894e495c0e176263f4631f55c5327ce9a7d2f7bbc75644a71f2c5f451edfc62f59e6409e74b4311654bb9289e46b3e87a60406aa	\\x7e79aa69421734757f4d406325112c47d1f7ae205f57b5d5a552c4f791e13985009b39f441aa41fe4b43539975282036d976762733f3d4c984f3e52a6170b85b766fabff9cbc695825e25e4e6147bdbc2aaf845ed790a35817d37de74b92360a2cae41dbd4a77a03e0d0c935bcac08e1fb1c0cae29edf072d21d4a8871053049
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	5	\\xc34878b21adb0afcbb4c78168f38fb92f905351ed7b0d7bbafaccc4835a0123c6d8776aecf45741104b2bad85989c5ac2c9428493a0b4d28c5eafdf760609205	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x7012e3d4ceacf4db87a36c2a232e1491cd090af8b6c0f7b36298076754c9e5decbc6069393570f66c5a44183dbe3606f94673e23875c2aa3d037b764f96a48fcb42f45d9016f5f646aa4e9cdb68bb6e39e58cf66b523613744558c7825ca9834487a19e88047a971dbb09ced400e0568e1a42f4b27b673e9b7b413c024b9465e	\\x6a61285922a5db99a9080672fd78a8768a170cde01e483ecd66a3b7edcedc0cbb3321abc6bfe00c8307ebf228dc1b93e2d2e9eeb439346dc90ca54291a73341d	\\xb171df5a612eb077d01a51042cc2725b624eba45caa1656e1a660bb37e1b3d4452abf09c637c9d4991b757a7a63e6f1d510b53fa86c12bc5e923cc348cfb3292e6a872aa2a7bd49e7446c9fc3f534e7bfae3464e96590cab4256bf05e5bbddb922d62931141ccd3bdf49e8d62b8c2a7088c0f01d4148a3110ecd1f5d941071e4
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	6	\\xad4d2c3b8bd72d848480785107d1662c13438c5c1e4c6ceed1f7320d3529ee995beb79525144cba1e5c6b70b32e6214cf1e5f3cc47538e35c7195defcf76180a	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x028d173c3f5c91936e98de00a22274b7c058f9f38c5b7106be77f7352adfcea03641b0d36c4f5efc3cb7ce71296f014d063bbc82d40c3d71c57d1274e783f7334400258fb39c7a2b0f064eb1bf47eb4c92eaa7e13bbfa50619393fdc22233f94a06cec3860d3c7c3369e6ade90fef075434b59e71aee4d57c013b9a2f9cc6377	\\x0746dfa1607a2c6a1b714272de261105a5e29f302422ad7b8ace789f10e3245a055893208b66c3243af9c40ee67270d3cdab32d68e53189d56c771f77fdd2237	\\x8f5869b364e9cc7e06832561990c90aedf818141e7de759803fbccd3fb01cbb5b86f69f93956fd826b22d49da8505a2922b2f4aa70aeb4d71c410ae4ebef5e5c18293fd66ee2a7744dabb60de4d19af1599abb3e09589a7d86bf1c6230ce41ab0762b0e1d746d559b8a6444bf332f54e5d13f7346027fcb9d67a5cef79080789
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	7	\\xe3242ec2bfbc212dcad7c074762bce6580a0ea663f9bb3ca963a7f13e22f7843fa4fda7b8184db5bab3cbe5ec8dfe013be7911c868724806b8500dda5707800e	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x40fadf1e346d4a908e07f09e7f2d25db3df87e9f6ef8950643efafc29038513fbe5c2cc1963fa3557fd23959e2d8f762128dc9807bdbaf24af542582b3678276dc33fb9e8991cfb31101b4287f3e5070515e8bd2e9c91c61741854ae0737322a3bf406610117299dbd1f4263388e6033b8437b8e75e50ea672acc3135c703103	\\x1d294b425f370eb3776e7d6616d949690825acacb01c84aeab8f637d878851273695c63d2cc43406f94e0cdd94c647ac478adf0d98b1a1a60aa40e68e2b04305	\\xb1a5b9f87d64f0124fc81bb6076499e927de0d9e796d68db9e1e353f2be77c6293f4fa52a9002b40cefd924f52910b23c34ebf334fe17583a1b81e5a15735663f3ae6bff53b698d15308be5b264d9d403653210d5477e2bd3a1e3056197c1cd6079d342e0cf3125dd16248988fab4bdac65827970506674f603c5523a3f799bc
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	8	\\x7666ecde76a37cf7ff96ac2d95b905b1a3e330c40e1c88ca0ebf95f197ea79ed72dd0fa9881f2575bb698c53431a6176774666224af7fcd86844bddae8332a01	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\xa635ccf687219be4f4297aec379dca786c7b9cf27f855ad07217982d65774953d12b24dc10af1f2a75f02ba6ab2024c3c8c6a29c771ceea854a9d92141473420b14d3400d6776d2877045ac57beb8fc8b379bd98084ef8318001e808a67aa6bb7409c0f254f343b0b895ccce087175ec9ac2dc1845b19023f95de5b3872c2838	\\xcbcbeed6c4a475f354e0d0d4f057cb6bc4308778d1154b6505d45e2dfcec0d10b2289bc453f43282833645e103c45acc879a6b5206be5b043338051dab4d9a7b	\\x3abe2c3d869edf39341dd7ff4431ce6190103f30f145dfd79249e4c296ba13040e65893a9934f5ac779aa2c635244a3da2fb0df21c5a2f60edc338a61b39d49b332a5a4fb866fcf91ecdf722b7e0b597f8728c1979516cf97b6f0c042337ff944ba16fa21a8669d85d16f4683d95137dfa1b2efcdea67a65448f05d50fd965d4
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	9	\\x0560598edf4d94e483428e3cd6254d366d5316075ce6aeecb45d88e8160923b1217d74e572271305b5b47c1da2e98551cda302fcd88fcc738902c12fc87adc01	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x917cc6a2687f461be6035bfe9a8ff46c718a5463b01723a4f67ee5257e209932e48d4e8265eeec5939cdc005170d8dfc191d8388fcedc5e95cef7a4a5231a43d6d7e7579d77bb02abe96bb35b5537287796f29510349be8f3662c447c0afeeab986fbae0ef3051bddfe154b972421ef8c0ecd29aa9c456f4df73bd0eb55b0a59	\\x941e16dc306bdc9c2eb7b787a5eb6b01db13578466557902da46f7a02d8024b91cc246a37a3106b8e2ce729e0f734baa1273c0351fd0198d24fd0863a4f4f143	\\x6bf0f12b7eaac971f3c2e0db1a2cadc1d37c51a05a58b8f8c9ae10d867e88db1d8fc1c186cfebcba46fb2e5e94239d54b6cac56ac8b20b4d3947b0e608f1c2e3c875080d2b7acebff4638da7fac5c295c6c4e581c2f9ad80419a4a8078fa5ff59c2debdfc5bf8f4759e2ab62f39e7a3107dbf156a86bdd075835e3f628fea7fc
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	10	\\xe1b4ff399e228e0abd353f3cff50918a78341ebef7a00c7a0d87a85a602a0b6b8048502b129305b94a8abfa19695d6c682b52aaec53cf7192bd4eaff33d68601	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x8c0ee4aa54a3f74255b9672548050173c692b7f71379905aa94ca2122078cde44618bd1cf40f762db471cd2253cbf876f6a925792eb50bc4b36c321745d186daf267b24f9850318676c1b15a1fcfba3f90de5af4b39f48440c69d2dbf4fd56a7fdd8be651cf170e32ad93f46fba0e2445da7670d1dad68ab9a7c3fc5995fb9ab	\\xa2bd07c6b2f94ff00d24cc99fb220ccc9610c01ccb2c7fff8911532f65d6f05ab84b250fc22d2682b9b77fe60f6e4852fc383a64a66918964dc7510f8018f404	\\x5e6122ab29256de73ce947217ecabf0c720b2c8e2fc3e2c7b22c9df037dd2a6c8c4376063c9603d1a0023fc63bd114900a17cac79d1199f03f6d30d40bf93dbbe4e96d1b75651c329210b9244131efc2531a671b9da0d4020fb53cc6d2e8422d3c349fd770f61d94357f351f3ed2a69d063a987ff17a64bacc429d7fe08026ec
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	11	\\x24e2b45df1db539f8164a5783b130403cde99bdb91a7fc62e50b172330b8ee7197e4cb46edc28d80006f46335a15e2850c0c1211da508f7b9013eb3c3f5af70d	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x0a146f65040feb18d770f7d600584d639c27fc3ba38eecd501c72d79b8cddc3b207121353accc75e17955ce39af870726c8a555eefe794a0233e6affa9d6fed7b06fe952fc2dc4ebd02538ef7a5cd8141fa3f06cc19d37b9dee454142b0c5208eea048b301aca4c9fcbd933fbbd5f59ca311cd6b858d83d30b69cb9033947859	\\xc6b68de96577f5d8631a65c55bedcd5b1edfee3c2ff8fc7a8e57ebeed289101bd6730355404ee310318fe9047f342eb143133ace3730d69c6b34a1e3bcd84ca8	\\x1a9ec379da7ed41cd68c4247ed478a804951a8473a4ebd2ece2f64d29a2d94e2ddacca4eecc61c426dc8aed193984670b2f30967afd42258425ad55a466417c16082c7a93eacfeaf91ed4ac5b9eb0c4e499120dc4cbc05b226f15d925b986a27cee7d31668bfb8a9900b51bed66b0e921c04812507b6737084ffb76af62a7acc
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	0	\\x075c36e2997a01afe05fc5a9525d1a2f6f82f5e19163642ed569cbc921a6860b71a435a19d38d8bf182617b649ac6cbbff438f217817e89f5c002115dbb69300	\\x11a3eb19bc7a7a6843734e389a4155bc93805e7eaad70a05db28137d882f980284274ffff9ecf34b4d9940591a4b1ab909e13f720820967dccf1e85ec49bbcc9	\\x12bad94701b77307b65cb692677f4630a268f487173b96e9fccc7e5f1f3bc124c196d48bed351a8a10cf43fe3b13e4436a61ae56c3e73dd0cc6043606efa5edae51bfb2b2aaa86f3d85f891bf7e9fe15644334b8d8485225b2a8b6817b1e8594544ce5a8070e672524059f2e7e74cf13ffd9acbc1f7419b10e91824e891a3e21	\\xdf54725c37a9faa7f71f4d3796e6639937877d59b808594f350e83206c02f24a9bb61f388aeea0f26068ff02500c11152053ccb2ff778859ee75802de6020e57	\\x9b4df9d85ef36e7f3330c63658fd27071a822ad16ace3583847fcb6bb9bdf6fba28ca17f5730069543638a4fa5efb296808d8bbdd6e315742dff20d372ab4d15375e1e1e7e84e5b6690efe5a28a365f96b6439f9e89ab79ddc1b0c60a46885bd272cb0c2909c61990759f184eb2ae83a73f51ac9151673dae2c39f87e478bf70
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	1	\\x587636d09479a7b127e5b0e01466033933e035e68e36b7a4e2e901029dd4480338f75c13369a3992bcbbded7f245378d4d7ae2270fdd73db3d9b66938ee51b0e	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x99a83a7ebd68f299a930581646f94608de6295617a78619d032d0e93d6e2e2103f12b07cc8f58e7eefaace46372b0b2836e622b9d74feed11fcccbcdf5f2c924cd8285a8739defd1532d332e6c76eddaa4f954a4cd368640af8a344193653ea00cb9df0b091dd89b0180b2d502d3a220ed03bfa6c837380010b6d0ef9dc731cb	\\x8c7574a1ef33ec78d6d48b2744e8891faa937deaaee26e70bb8f1ccf4e203b768dd5169a3a228ef2ee62e40d79c134aac9b3a4e17014198f546dcac3509ee08a	\\x64a7f70ee15ff81d9100bf2b5f138a2d64c6b0ef069a84eb246cd06ec607c0c51473074cf86ab413980a0e83f035f5debf0b6add313adf534cd12a50729014c36d4ba05e3681e01661c0860376508618efea284101d60bbd8603f1685df514c7971b8084099e0e001212ecba0a6591eb2b8d23ead65b20cef58fac046bea83ba
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	2	\\x6da602d939de5f84da29315a25d46aa47c100bc52eafae060ea7cc84335d03876ed59fe7764528b62eac3fcd44dcede8fa15e13c7c35e296379d96c79359a700	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x65584728f23b4741c966040ebc1f8129725912422f73bfdcae07f938c76e25576ac135e9eb0560711d05d3459edb09082679bafaa195ea1e61226ca4e71806b325884f1b38e8e91305bc27df97c39141ea86e0acc1b4fed8ae3f1355b57d15010069d76e8a0239b8c1e62463bd4f3c4090ebf6c183aeedaefbe0190ae97f40e6	\\x130be1ed603a2cd820e117ac98f680208eba265aaef4fc24fb7f47f61d71577298d50c1b4033bc00d86bb39b2d8d9cbf34e81ec4762184f60a175623cb24aabc	\\x2efd2c25c9ab8b58e56f216694afacc5c79884a1c15161ff025d69cb43c2b038bdf3e8f657445f8daffc24d4a2584c68f02e5fcf6d09ec07a1f37abde34c629d7516bdece42e2b600abcfd0b4fd6783508bff2eacb909ab092c64e13472a86524e17ec259a6b6ce495d77f778028fc3b28c8b843e5befe6b519c9a0a021e66cb
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	3	\\x52de742568014e2ed2d4d1e775394847ee66afbb8347280fca3a67769c0c83e33d6415509bf69c851a3ef2803e11e8cf3948f05913903cf24dd09148ed5fb80d	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x55732e22661aa5047318c5fa9769d801b56098a2449eeba504bc44150b646ebc2032e5b6a9c42bb1f064314e9f3c75a2b4fa7f2b5ac493fafcc14b8d2a57a00b3a213bb7593751bcee6d8a3a35e3d0e357f34501526d79470f9d83582add6efb1dd968cc6d42d2bcf1bfb2bf4150a1c71313dfb5c254c05220c722335484cd70	\\x08e077d4155d0a02965d54bf2d6c2dece9db8d127334ac97621ba50683b4e11b405859827c0a1b19c43ba68da3a5b75c5de7755f2901d72a79a49e9129732c6f	\\xb36b25a6722b566f06525b051f5508d23752634873a0d2648fb1309d49301f29fb9f33e86c793b5a46a70123496315e5f0552f3df8d6d55750f575d4a45ae8bfdad79112ede1c13520171d8569435c389c6ecc508d5f8060c6428beed2f247ace334f15e1f1b6c6bc774e86e53f59df83c6df48da1830ad401169c5078790e01
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	4	\\x04ab9e8c16aa1e7e83b6bc977b578d33b75706afe5cd6c8adb93db155db8abb57bb07787da42c723a949cdaae07b249cc216b5572e94bda8857732325c2c850e	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x30d6b25ef2f23e0bc7b9810ce68220d8a7bfa281a9221e4aa47396d2ba9bc3273be0d7521dd0533cd4fa6db727eaaa2b07e26fec2f634aa6af5fcf384ba2edf095b620bbb0f94725435e36a84ca4a204c96363ec85af35c8c78502e854886d53f6e8c449139045693912a269e511591975540983d14db824fc76603e09ff1dec	\\xfd295d607159396f60d8e624a409540ec9044815f7bfc520eba663c39bd51cb407bb4f555e471ed5ee233d3af13e030dc2191e735b96259717e92a324a645ca9	\\x86dcb45c3ae926607dde8465cf32325210e2b7865a0095ab2ae5d16bbedeee8b7b86c1f90fd5dbff93bca869bdd109f065e8c0cbdcf49ce13577d2f0eefdad45d4eca676ba5a581237028a70bbf2fd28fc6fbc88e72fa3ddc67c1e5271d51c0f8f7e1c7e8228925d40f59b468811fbc462c397ca4bf778b6ea51c3fd2feca92e
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	5	\\xd65af71587bf9f99be9bd0133807da946da325dc10f0db3c0f490aaae9224bf7052c6fc8de4ba6764515c48bee5f6fac07a704adcbd239f1670ebbe8b718f205	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x81f7bef456a10f1d08e3fba3251eb692c285facbd88dab72337d195046b4153952e916af02b1f4debb8d7cdf6bdaedaf770f9138472f37d7173b0aed76480b604c4c77a17baf846046694ae4530e23d69ac18b43e2e38a9c5ab6b21928283b40e17fcabde2639b99be77b05bdd5cc9a76d3a010bb63ec77f8c8b1c9257122650	\\x2c6a256afab8c43017f8fa4184ae9443da5acb378e2ab34a1f5c14d9b24a3f88ce8c7a1d43b0deae9e58d06434feb0f878ee94007b3978e5d9d8ea4bb4ea9ddc	\\x1873406e403cfbea6f03678f0368efd66e7daf9fe2521446c885675f18dbf2d77508bcdf294488862bd2c3779b38e64454ed873263cce17fae268ca8f2a6aacdc009a2c99274f92ba83462cd371e243830b84fb26493a981754c795773d059b48b39ec25e3b2463cfce09189f1f8f30ffb4440f077199d7a80ceeaa0b5d1ee1b
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	6	\\xc55aa185b893946f5f4ccb2c96c549249721177bf5d681a01e64790c62247374205fd2f27229ac9c8a2bccc3305f08bd48f76fe7eaaa96fa78b4951e085f920f	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x9cc8111c0a25da0b3ea5937a45c401496ee186ab109a51dd3e3b5e9955e720bece4a90f30743323c7e8ea94cb75562940a82290fd2faebfeb936926f22e1760b192f7aa8cec5140f17053c85179fd9ef8f35a964be01b74dd229b2d3435d99def48313021a5891f9277622f5ebf593f110da39287867eb5531743c25414de41b	\\x344fdd4bfc3802594ccfcdbc4b1a0c9b4ea8ff16db98a6c113bd18a00740c9b25d71308e091bf7f8b5e57fa4b9d47ce8903c001cd8bc889f63cd952818232ec8	\\x0106136019c21f353127e4fd5889f8ff89176d02fcf31532c666c5f0b366eae46013b8b73c73587f6756b3e35240b84de138372b9ecfa03fd9a6ba4cafd313cb5859567c39349affb46a3fd5998c17e093aedfe5f30b381db942e579e22b9955bed3d5cbc40f14448cfce9e78442f3ba4d756bd000f34318b4a51478ec37bfff
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	7	\\x80bbae47294596ebe41948d516aeffcf5cabac9dd5d8f7ea6f8269b3c5165e4457b8bd174a6797fcf0ddc95f6b66fe3532c90acf52138678d4e141557cd2c507	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x99a74dda0a77da5d4abe9d7d29e044411f9fab981d0878ceb39713c8a67c7909214fd9280f015367c12e1c31f2aa440828967050a8401009fb88a3904282f99385d22b45795f6386ce1c4a7b7a825a98dff19faa4f65e524cf5450d7560c7ac59e2a8c7863d11d17cbc5d751213b94feea776bf7c2788dd49e1f4f515c6e8976	\\xcdf6b5e78706d6931f78a0f1c5ab818aea15bb2f9cc33ffd792e00103b9f7738d5cc934f31151a8824b451d551136abc25d08d2570e1f1a2607c5d8c4a8c967b	\\x9f8487102d09444bd47267ae831708cd176eb985ad95f8e01165c57c664740651d3271e5382389682114ee415653037f53a3ce88bac4b2536e650d10d594ac0adbac654ec0e344512bc8c83e03424635f030ae3ed971e5edcc1e9cc551c47231c87c79bd7013e8c7a0157f5cd446b15f38dc84f5fb16cd55bf184ddd47874dc5
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	8	\\xa58a892adc118e91fadab40c16f1f89999fabfd013e3a5fad15727b1c6ffb51a5672f15ba7ca7f85ed2c68247ce1385919f3adfb0ba4812719a419e5cea86207	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x49c25cc7ed2439cee17dc8472e5edf94492d562d38e6053c857eceb331ed63b38e30794fc00be30de72558a4559b8bdbb816497e95f35e57c6122b8eb33fb8162c995a42a2e8b73bc7a32b2840965e4d817c101e6ef7ab078daaa8e78604cefc63e8317986358a5c185a97b8adc8cfa9e5fc3bceb7152b0743911faad5b8d78f	\\x073d09f244fab1516e2490d363af54ab6cb3ea94d09daced610be7649247142b2fec456bf0986c1171edefe2a867db24066c4c1807c01a3eae94b60567d48894	\\x9ee86330894b50046f26c61492a5f57dd6f4711d3f3df7761fe201fb535b9a61c6bc1adb008a774a4b731575e82ec0c2e64319a11c27e32316130d8609382bba030f12b1a03eb4fbd7e60d6dd51c3c48cbfcae9b0725721a395df2b384a2de0d1bc7b3dcab2b03b80ad2062edbe12d78eaa8654e61dd5525a3b278425e46e469
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	9	\\x886dac7eb95cf61326029f4b32f24c0e517155425e942e563958956896cbeccfddce1640463b75a3cde94041cce3291efdb9400b521e97801feb7f0c73da1f09	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x3980f782d52a4bead396c9a7095ced49b76f1661d56b5c540fb4cce644e4b891fde55d665df82bbc29f69d4e5f46fb5889004b3675d422c60e16da82cd197701de744636a6f9816cf6d988369834604f060182cc510928e1b915ece1789c960bc11bb60b38b37a89fff3ba2acd1cc08fd4c9317514e41901939d292f1aeec084	\\x5667e303cce249a3b23be6ba3f0453ce901f1cdc8a524341159540b4353dde200d51985b4a40fa4167e3b2c6c76f836f77e6173163531df4b400fd74346386c4	\\x780f6958529a38707d134da7237c454a84be2340e85bb1b5531b371416b6f9856d59f5f6980416333cfff24ca487b5bc4632cbeacedd4e58ef470fa2d6b6ec66f9540e534ebbbb1a1553561ac90f089c9131f9f49aadbe35582d25f0bf1010fee59fc43cedae02f0b77001d20cdc4df769e34e704a49d26725af6a64b07dcecf
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	10	\\x52230f7cedd138f9ba1ebd1bfd208a67994189bac96bf092e5f0fc53a4a188e058c9bf8cfccc62f6dbe0c747c31bf11366547cd754439cc5b1a61215aa395502	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x832a7cfaf08a2a77aac283614f59b369c8a6381d9c94d81bc956621ff4126c17925bb36a1da855cc7cd17067d1f33c9fab5a11ac395594a4d9a18b628e260f9c270cb86d7b9b82c9bd8a495d66849277f4f6f0051b6c36955b2e07afcb4a77f907cfa870df41c83a1c0d5ace61ce8e80bd417d7ea96ef3cf41b046db96d7e374	\\x41bfe8985081b361d3bbd79228f2288c9f7cf1d888b3e9c67ea4347c4153c0062f0a0418d819cacfdd4bfe7aca5d648c8eb9ac9fb7df8a9d4e4a6375df526412	\\x7580a831c4887194d80ce7b606cc2bc380041f2933fb7ccf7d4c33e0af9255dc49e73bd88832568f8f4b8042b16b384ec5b0b34ccb5ba97f22655b7f1de54635e77ec6d60b8e7d21ade7dd03d53a19ec6f45584fe515b2ebf246197201ba52b259b08f9fb552fec16cc625e0a24feda4cc5cc1cdd25816f57e9de36786d00077
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	11	\\xbad8a968f0c5948c1db513585f299a5b9c5f2e83a9946031112b568cf1018f60e38126058eea7b2f17b1711a4e2ae48a90034d87120b5aa520541a552060810c	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x8975de2801c49dc3cd0a7cd1b4efc192f40059c1f9c0a3c01ce8a72b693a3fd942c7fcf81fc29e864a358eb2982594f1eb022751c6bbf2d21308c9cf348c78411556a40068ab537833f9d0e776d040e1b9b0c29b4e791566e676f019c86b481c1201815c9e56641bcc0cbb5dd56273b9ced7edf7c3f95f945236463b496db552	\\xa45612b9d4b536d695d88aad852e78031583a109bc8ac0a2017c5e046687d3855b7b2a99b8952111590513cabe33a2ec5f51b0a2efdc5972193bd386c3a78789	\\x5600a7ebf815cec02f92228f5516bd7acdfeb2156246c7b10c4818b6555a03449d424c490e4e37d183f2acd6b4c75319c02315d8342f58530cf2244847fcca024d8f5a21a7868820831c70f969d5b3a2e62ab8e5c6ab4a8bf4aadd6d28a8ae2228d0e71a11a20625d3fa2f17780aa25389599e8c169466b77f5425f3b0dee07e
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x982738ca9ee4427fe30b2f85198b4fc9aa740f0dcaf7016107f67da23066335ff9418e6197fbb03fafeef7b02266a145a901b2dc5ddecb3aff0df48d4b259743	\\xaf145c857db10188317a8187c2f0066c0347146f16f1f7c128b5138c3bca7a16	\\xa5d25768fce5e6ac8357f016e0627785f4e20c4134cd4f31ec64239dbc400294e3a23735f762cce6b6ceafe445b59ee4f1d41d75853bbb248cc139eb4e0ff72e
\\x9e5e5edd8168f83883ef46eb5d60b748900adbb49810b8a143f5e1666b16f0bee036655ff6508943b55f0850ce1566725c75567a2937668f2a81ed5a452b40b5	\\x8e7928cf2fcaa145c3f7a79c3fe362645fb7df9a40ca36f355f6303c8fb3bd3c	\\x793d009ef863226c060efea33df5bd44784cf568255eef906901b3e5ea56db36046d4901cd358495c552e43ae5a2699efa6e74cb02971ee50411a3f42412b4d6
\\x9e842ce8fa7efcf7b4e283add4c0748263706bcf80e54626c39fda9d3dd7300516ae9de389b2e6cfef51dd9dad5ec9248c608436f983059855f3befd588334ac	\\x7f380a7b16b80f45dd32e6e192fdf7fc2d6f0644e17bb6bfd4d1956beb537a7b	\\x44676b9b8a1db056c4298f02c30da768f5bae553d6bc2b3239c6c282444c2db45a39437f4c4fd62c37b9d81c2e831a05749d3e48f358176fd8c584d5204ea90a
\\xcc5b9493249b7deb8afd6666033860ebd6bace337ad602d32509244d224c0f00f275dd3c30846e660b75fc63310204eb0b10df90ba0f9189de5002f6a5bf18a3	\\xc2089e60f6cb2d04f08022452d03d1e1ee359b6b04501696e3d22cc77bcf4013	\\xa497b75bdbf13e9caef31b78ad7c79e326300f149551b1fa1f9abb871b210d497033b5a48a0988e694b669bbce69734326044013600e6e5318387fefbe8de561
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd2057487bf92ecd95794ab222b21a38c35f40738cfeedd7afcd4cea4427aea4c	\\xf8776d1811989660de8d81a1ac8ca4bb9fd3d915e311c1a6949c75a178fe0025	\\x20fac3e96f4c1d3e2aed167d08ccce25319e9c169b28670c3af26436aef819fd9858f2122ae7a10b70ad3d5244cf2b3e9f5afd3ac6f2b5311a0b1419acce6a0b	\\x8a2819cecf841d3ab1f164d28483a75c7dffa9333f4a1fc9f63861ebd8e834b08731e35dd38d5ccfeec246ed53ebbe68cbe91257a22a32172471011724830cde	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	payto://x-taler-bank/localhost/testuser-lqIzYy4F	0	1000000	1610100840000000	1828433641000000
\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	payto://x-taler-bank/localhost/testuser-EUc4dkCI	0	1000000	1610100842000000	1828433647000000
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
1	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	2	10	0	payto://x-taler-bank/localhost/testuser-lqIzYy4F	exchange-account-1	1607681640000000
2	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	4	18	0	payto://x-taler-bank/localhost/testuser-EUc4dkCI	exchange-account-1	1607681642000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xf5444456c149ffd44a8f9c6d52e13d9cbcefc6bce8096b9bcb01ba6ab0040d8f19df551d213a5bda8427af397de7b76ec1cc5be08b389960e1eac5f2d5f907a9	\\x0cfc72018b21353087cbe3a8ed082baa049de7d097881888231658cf8de7a952781c0cbeff1e918954aa5e05376b188a0d4ee2a11b33b4bbec41157a1d88ba3b	\\x8066bde353e0a990485419519db8f4b3c08799e907a186e6694e93463c21af6a3d5f7b4401963f523414d6fe8be77245b9547f58532b7552bc646b113c4a226662183d05258feb546cd46108833f4faac32bc3e2721e59bf6ccf8e7bc700e5214525204a4f466bc290ca3fd1d994cea29586a484815f99fa4e2c4e261fd4073a	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xce7e9818c8c71815624a42d8f6b573e087e659979d67e42d1921f03e282f6a1a6ce2b4504ae49f44325977d16e02898fee825b49fccd279a4d736ab6988eea0b	1607681641000000	8	5000000
2	\\x160fe96f25d359e03e689f2b3aa6d2b0a3b99c776559e5eff5c33c7bf8417c9fb437321745f0ade6aba611cf9692858b33bb5f93a31f984279906f10ec50f96e	\\x11a3eb19bc7a7a6843734e389a4155bc93805e7eaad70a05db28137d882f980284274ffff9ecf34b4d9940591a4b1ab909e13f720820967dccf1e85ec49bbcc9	\\x190c7c36f66641cc203b8e276d31cec8ef5237d7db04228683f6962879e8ed4bcd65663f97b794822e883cf8660aea0fc190d3bfa5dc4f402e429bb870937ebb2521fcaefdd0fb7dbbd245e20da2d494606ace96136139ce2b108743de1a11af1f8c5e80cc0c6b76e385a90484f9378ef70e756a9e4fadbdd70f1c2849f572e8	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\x0c6ac51eb59f90d8090476989b6f82424a0be2b359285dd62a933d60506f74fd5c4fdc7b8f1faa8fa0291d4aab83f03723c9809b583c603fdf80b511096d6a05	1607681641000000	1	2000000
3	\\xc329b1b88433c6f2cf6549cdb8de030f4923c34b34127cc36b7f30a3bcf20ea049555eb9f2a3036cbfb7f733fc9fd25eb97a4aa3de86fed968117c4c313ce590	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x39ad11c1c89ddfe99d14b14a27161d3a20aa67fa0f44fb66e7a12377f56e5fe68e60986da590875f59925b718756f5faa6b391f4ee9f315996a7deeed7511b6ed285f6b4a24fd7ce211e4ed22fd9d7174466583b83afda43a4e2de3284df36968c7bc1212b1e687302af08e6aae2f66596386c54190397e46eb0b0d01830440b	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\x5a291715444d9245812461384cec9576890c7e34655c29357f4cc80302a35518fb33d49fa70a6056a3e3fd5f9daa6d038c44954bb02af15184395bdf7e7e070f	1607681641000000	0	11000000
4	\\x336650bfc7bf6fe2098511604041872cc17a1aa35c0356a225786464cbe01374fae2e7d4f394b03de4f953818b708b2e2509d9522530024c80264e3484d83990	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x3b5ab67e2246c513cd5eaa119ec6409e41dc4bcf13761817631e6a9727eaba3c2875f65a7686f6d9b5c8030a6d413b0c459f578f9693da5c98cfec420a271814dad24006a1dd24ebd66c4c526b48a4c4c8b90a0e1a3e28b17f9f86d87396e3c306c3bf98efd8a9b17592a186f0410f5fe4372bbf87bf136221156ceaef76bc25	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\x3cda75810a69250a55410beb281ae3eff06a4595df29ef601467f093532b9554e4fb2495a61febfd07452686f2f6302ea0090188b7b687e540d2fdb619927107	1607681641000000	0	11000000
5	\\x44b63f51cc2faec6c709dca7c5105fc3398d479ada147f677cd383f6c25551a87f5ddd062d09334daf653b62639ddddf9fb2e0bd002ce27976e60574554d6b07	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x8ca73ca98f7775c962d5ef84ac0b45839a33fe02f6a955d929f6546c1d21e10855f3f87f758fac7fd6b5e777e692a6d24e856c247a46a557aea4f41a151325e20e56423c99cbb44b934d3678656c38cb7265fec1d0de1127fe246a651b27838ee65a0709f111a9d1b01a60fbb02d37faf0845a92cfe68c953c256158fb276dd6	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\x7f2ea69c159ce009fa86722e75ecd973618c63688179dfe818fcdfbe9a3ff8d2ec3e8325d9d2599576ab8c9866eb68b105d7cae5d9c889347ee99453fde37b07	1607681641000000	0	11000000
6	\\x1f6a5e951157b9fc40557ce1f44d3031a806972e4d27178d2498d3e2d104582952b98fff099592abd0e30c7d7e97e5f31ecf8f99f7124001adf9c08587f80cbb	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x60d1ec370aebf364d9c0b6b3a95f9f54d84f51a1db9d1e4da03b703730196802776a62e48ec0bd602c36963dbc141a36925af5e94ca0860e53cd856b29b3f32b8634d75626943045cf14198cac9c994514b29144780eaf81ebf11bf14bddcc8aedd57543270121337de380a8424f2f8a50cd735fdf9e73daf402d34cd2073fb0	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xee6967093f10ca1d78313af42a4d005fcf4e695644c85007555f4bebba89cab8cc974360ea2f1ec2c04cd33e74d3aa5ee4a9a16996fe22ca13b3b832a1f63609	1607681641000000	0	11000000
7	\\xdc98fd59816a0dde5007001ca8163689d9f28be934ca9b5dedaaef72304e6a1c3e7a372ae6dff7e5f8cbc9b8a76bbb704f6a8698ea7abc2b8c49b0600174d8ba	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x69ded6d0150e2fc40d40ea573cf2ccb0edcc86249d6b43d605cc156a886d6c9d7199166d0744c8f01a8166c68531202e7b61c358d435037edd7f4faff9e46ecb91782ff266393316c220240e02f9c30c1c43a64f81d5e12128d6a6f7472967798d59cba18f9e219982e431649ae04708cb6688842fdfac6f980e7fc4954f37fb	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xf1e790031e9a68fa4bbbbc9264b50131d29cc1b1ba03569ecc15891190f5de94811d63c57bd70318ce89520d723e7d265744f6350c52ee3ba572066d24124304	1607681641000000	0	11000000
8	\\x69c2ff864c85c4587dbb0975bd72ebf2d9ab217cce77df3c7317a413a51d8ea7d563065ef1e4917623368a61779f2ea9316143748e5d8210af327176535ca01a	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x0c3294150f8607b430dafe27e62678027e8d83a6abecbb663efd08dc3d9994b952a9df2142e98a9a2f2d05ea9356258884fc11fab78ed50d11a9e5aa8b4a1171be67e6aafc3ab3d503d956ffd82d623deeeb0ed3c6f198bd51456e0b37e8350449916651b3c5fec95beefde8f064c802cde28fe211895f3d889a2c621e8bf4dd	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xb099bdca2c650c9219151c8abdea5e0a33980e449512e8a67c832bbbcd0690d4862e77a323ce6bfc4c976e712f9ade07a72c56c15585ae393ba47f1b0941f103	1607681641000000	0	11000000
9	\\x7ba8f0aef69e1e72edf85b722b269699dd46c7c3bdd7dd0d90bdff6e076776769a17be3a3e8350771e2f0db73c7374969f21a25bf94c0aaa1367c0e69eba1dbe	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\xa4c5b23a63b5d668919eaf68b9ac6d4a49ecd1f37e7ae53b139dfd067be86b296b14c2b96fe6f4225b345ebca89f705b0ac9a3af263b575d659e13a0c24c2ebe0be1ac3e8d56ff012805a9a1c345d9a6cbdda50f4528fdebfa3de03c35abaa4537ce7ded5f97462fde34a8440738a58dfb52d2f95dc781119086550ffe49965d	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xf91acd2aca875129d663bf5f6da7e83ffe3f5515d252827d62c8ee36654e0734e4225a0fced79bf837fb8e50f74f3d7d4c12b3e48b99f9308323f0a11544fd0e	1607681641000000	0	11000000
10	\\x498343434882917e8efa11a696a9db02ee2b7368d7871f5f7c29da057ed325be34af77a8fc56b5e92a122ec438dd7eb9a8c10c2f0bc3e9d0ffa886cc19dc8749	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x24a743a68a559b32e4009502661083addc02358537451cf7e445e1978288280bf87038edceda44a64a5c4521c56e743f878dba636b42611df12768f9ae77fe5c63abf214e12cd13e656f8a4a060bec850f676e2bc9ee87dbc800c326622ed09df201c3bfc0e01b9e47d072d591223c56721215ea3ffc4e65867f885a3b1bbe28	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xbcdbe482cc4c8941d817cfbea29e967030a3db742e3e2272fed583b10b34eb8410ad244ca2bbb31d292d5a3a662b0bfebcf429043851f7f126f864a41e9e570e	1607681641000000	0	11000000
11	\\xe9a76223d16815d7d0d5a040ad529038b1f3142136d550af93bb3be1acaee5af01d08429899b065188aaf6db018f9b2da03324e6f31a74aa1ccde87d64910e2b	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x1cd70316eab55c06d98cfd179c7c996dbcece4965d5451af79c959edb90e103e8287db0a5bce066af6797f8c6ae58c466d7edf7c51e1846b722e46abf5140de0ac67f0c722c630ab9042a63fc36472e30b3104b1a382e518d92f9e9e89ce9fd510c9c0092fbd92ed83b60dd3e0531c71a6664164b79a98cda64f9750bc552ebf	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xc81916bb5200af064bedcb167c9e3480d6f9c33fcda95a20973dd007ff2f2ce9e8cb7531b6f414522fdbdff7f0be9bac03566c68ac8d655de65889312f4e120d	1607681641000000	0	2000000
12	\\x91d1f47aa656c298e43f1530dea2ab352ba4a3682d78ccba151fba8f2221557d68931eb8f881da94fac7fd966000a87da643c7f724576322794de05f800be45c	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x8e494704df2682c4dde7dd6c47cc5bf123eee8463a69bba4b662f1888ad8ec51467d146bdeac2e859f977b29084d43b2b607d9bb3c9c1e95a1152adb608da77d7cc79af2ce670cd89291d0acb56801e83091cfcfe1ee3e08ee4773d01334225cd698322ee475f2fc636203af1d9a21c6e59216a90ca96023c2b85742c3c0e696	\\xe8b167a4d234a7da5c498a20565f8f62513848c57b02c007a52bb94863cfe5ca	\\xed411d6a55134309ad16fb104a7fcc45ac2546e9b3f9900e75ff44724ed92e54e5c267d536be9eab94eacf34dd945b56675a245a0b79045fa02a132674537c0f	1607681641000000	0	2000000
13	\\x9127e711ea7f0331510c53c413d15e1b335bd7a9a92cdb90d8800cdf5365114dcf74d678dddd699056afa4738380a4bb288b8e15408355f3ddcd566a84641331	\\x8988dcd0af23d86ae672fc2ef2fd5e3138fa0db8760cd454038dbbe0de4212b9ccd3a06de1160f91c71a785f28beba7659d089ad1b339167a5aaa62b41c438ab	\\xb50cb786577386cd642f825149c6a71ea9618e49a9116bbbb401c7921659069f4c086ca09e12e5ef01718a820a5c24e75219cfaede131e38d5240195ec3644b26d53904bd36297f55fb5417cf5bbf79b33b311a12afb02ebffd07ead1e62018aa0015f0521a9873c81e6fc6efb088573d802a4de8292c29516de8ff6ea17602f	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x300f20760591a69827475f7df585331e6526da034ea538936eea714693f5dc494acc518921e146ae54ec9d3fa21bc3439c6cdea2fa6b4dec6881a5dd15db750e	1607681647000000	10	1000000
14	\\xb30905f64417b86cd8a179de2a77354c3b417fabb8974941cbca62d086ad9c37f7df7e9c2deb3c9bb929b6d53bbcf57a72f9b5a1364a02239df8d575b01ea9db	\\xec808800c3bd0ac0a42f2a0a392a2826ae8b87ce92ea0fbb1050b71d2fd2dbf463e08ca58de04bbb781e9cebb1eded0fcbe7e1955627dce4665b8a7045751b6c	\\x4484b5ee2ca12c50f5692e1d1b988efc8ce38c5674c3e858a77ae7e66e8004b04788eb041e14ba3b7b0d4649e6ac2cf40a621962965ffab1cc1d2d9270006939115b0115a7867c172ee8e787ba8812e582ca02e0e58fca71d8be964659e87109906104fb2bdf98571e0fc04e2541a2585c157a1a0b6dc47c057d373471883b35	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xcdb65b3f5034da7bfe8e7032c2d41b84fc5723f925daa81bf1ffc1eab46d7e3ac921ea0f1fc5a8d22ef9468dcfea0c33d106ec5f17086cd0caa281e025402706	1607681647000000	5	1000000
15	\\x1f1cbdf0c7986fc537a637d455088a1b393016fd9bed883b71f4117b0d3767ccf69a5d7f7592b42627ed8028e450517625a3844dc754fb8543969517295bb5a7	\\xb1b658134b0435bcdfd6bb88389aa25ef418a5961362dccf906f447d3185fb64230bd16123c00eddab5e78f1b237ee82075755b47220594ac51654909f570092	\\x05affe6e0b603ed347f6c19e582703fa93597af7df29cad0e40aa2bb91696e301936b00c117fe7c8779a4378e505b04eb1662c1080eac30c33629dd3c82c8e2e9da2f2eb2018737030963bb6f7e67ef291a40c0fd79890d4b895a0f5b81d3ecd1becf05859ac231cffdd0ebcf87f03cf72dc365f67f872b4cfbd3e7c2ff480cb	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x74a6c34a7d4fc4b5ddaf722ab8ab4395c6c2568cf05a3d43155e4433baa682339359a8267cf6f2232e5fd9a5aaef0ab65c66aaaefd84cd6655c8de21e80e4800	1607681647000000	2	3000000
16	\\xef10473b1330b8e40dce5db7cf486941f042256c42fde3b04408903a18f0909025a7c150262aed2f890719ef18cba3303c91f41416945c1f623c4700d8a7e1d1	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\xb956d83565ba12c066174a3421b8f54dacfeeab3e258ee2694358b7d6672801404c2335ab2159a608c693f5687ee2e8456f3f3bc6197fa71d2d3408c70fcdb3b5496c685486a727589e4a1cb8caa6603cc4af5cac7cbda8c822d75ed1a59103e1f7fae2d3f3149baf3b0014cf1f201d409fb34f26826c1a2160c95a0df074714	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xc7277f786ff926c290e42abb8f85621ac2719016fbc33e1c00fb0ac48e118a98018611daeb242b3bf27be02f38b1629b9a84f38b4ba9a54e48336ef2a2d5ba0c	1607681647000000	0	11000000
17	\\xe9c474075d34dadf11a326bd7bf18d1b85cfa5683b99c8a59999cd469ba5d90c9d15df4835bce91c9c95cfcbfcd85ca43902f89d5dab147fcce5d2a698ee4a50	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x76f24866fd8589ad73b44e138b30319fbd954e712566fce19010b3330cee1e9fbac26b8e1948d636fbf223325f32fe004065df117b049f354f507d17dd86663e595f97e83c3a461d7e3719abf7838d9cd3f64f50e6b0aff7e497689034ef9cbcc89fc9e0a7d70a1b622650c6c2bf60e433c0851913bbf3176f6b5b9925d0be91	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xbe9ad0f17a8d4a613ffa3ed4720a35f871ecf9ff9e7f9a68997ceceda0d693b2fbd999fe2380a46d9b263e576d230488a14f02917bdede73b0628046073ff507	1607681647000000	0	11000000
18	\\x9caa658b1ea5aa13011cdb3afb01389119a47aa575a4d0fbbcc7109375769bbaacecf0bc9ae13c469d1dd442cba2bc9471068d8a83f19ac6e895c19e336f0f61	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x1b695f858686e49dde13bcf79db9aa825fe30e49e6e077e14b2bfd13471767ca50a7140a8914cbb976d4c96acd4617c68811ec0f99213b76b1acf0ce30fb9734bddfd40e4eb611a15273d4ca3507164ad104a4d247239396b882dc30c4782911f102cd95958d779bff2b7c2883756c6ca59086e3e45ddb60f4f25c7646d0d68e	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x045b37ca734feea53c7028414ce4dcfde94cf66bcbd5f7b5d9c2ac2a5b2a1c528ed5238da97064780e1327b4039ca822e9f5877ce125357b4656418ecbccc404	1607681647000000	0	11000000
19	\\x79a943fa6a22711cfd8368a84b820ad100be268c0a8d632ef928862baac4a9d3bfb26848d4dcf1a99c4fc9e7be0790977206b7164a6e7476e00f8822c5880ab5	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x5d6ab0566e49fd78caaef3e308f54132dca54b2943eca2b124072adc0a8cdb9776a130ecc129597620147e48b7d318bc34dae584ec37602819d2700b14b0765eeb22d896c8222bd59f8bc2d7eb5ff357ca7187ba2a41becd6f518d7c8c1ff68262306bcb9867e2a8f39ce8ebb62b310b997654f18a03d4b6768495b9210bf782	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xe0a6409b411243a248a02b9745a06031772a30366b14940763a92f7a1862c7feccae6948f8042ad86b3bcc958fd5aa479771e4b573a9f459153533a76e22320b	1607681647000000	0	11000000
20	\\x07f52a28b47eda2052a85fbd7fa220415d234255089d5e6ddd8992989c3a1eb0af73fc176c15bc548f7c851db5d424ab239dc7542b7e27336311f7e7f1b0e94a	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x1d96354d7f433322276454db889c454b55c41999c75814cc9a848c93c3c7c697a3e940bffedb5d3c1004799dcaa1c0013feca11c04748bf6546f6fccbb9167e191998d310d12e3fc36e70787a1b88780d9512b5a81cdae532d6ce65cad87ae99ee7b5a4a7bd3459ab90516a98e09386d56932e5fb9c234c74f40cc72d083d679	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x04497bee5753c1ef8917c9ebf2c1e0a202ec44e3ea77bb6f2e3e4094649b1711b5e6cc842dd2d982db5ef3104419155a8813fec4d92d1c4d7a22e4203f21ad0c	1607681647000000	0	11000000
21	\\xa207158899beb5e28e9c776b9e823c3e2f936d719cba2844063986b3f4643aff7515b890eec854ad26b1fe3295e34caf1da39310042ecf9c246f4e17e32c7692	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x551be9cf82a92a730de6f013cc1e343f3c2991da448f242c6d48ce32511db55041340f994695349b348266e3970c0ebf5668d2686a7a0e4bf835045542b5c3e8a0bcac3dec8604520ba3208f1c7916d3bcc80f084c4dbd3414a3a00fd80399c65b490073ac503f5f8584eb9b6141642045934f903a868766e492a3ac0a6c0899	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x7a47c3e4e4da056803e7e8377d3720267899e5a2892bc62fd12ce722128fbd39af4a0926448d3ee1739b4089de735a6c00f2f46c0d04209c1ea985f8be92ec0e	1607681647000000	0	11000000
22	\\x6246180c157575c2823790fab2258021324fe59c815fb79f9b41ecebff0cde67c8a12cfe302638c89f1edafe5c58f2d0258eeaf6d4ca193dd264a86e47dafbdf	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x2d128f1b6ab95a0d1e6af159d5fc356db6fa24791d90ff077835384ac87e0ca6b7efa63d83c666954b121918db338641f21a3c8e9c5ecad4d10a1e4e41add70568e0679671859efc53016c4b61f8538e9e14a6e2fcad0f8ab546b030d873cae2741b7a95bc87c4d8141e4cdb938bca9448687b8a4caf4943450011599148f7b4	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xe8f7d3e29ce03f73ce68b69b266413f51dd1680d2d5f9e745bb1dc7e1886c486d79db803e72cd796c35954ec4b4b1e51fad19e8123d164485d293fb3d466b700	1607681647000000	0	11000000
24	\\x38d066f90383ef470cfa1ceed58f3696e589216ad4289e25f50451167bfd59b42edaaf32be0fb13c03131f9b956b74ee324a481769b00387fe2d35083a1c4efc	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x103cfba9788038e35c50a5ca2f087d07ac88f5c81654831633eba0299d7df90063b4810747f3eacbb87ba1e0421dc995a7e815dfdd87354a996884b22d4a838d230df4e12936479a4f7b5eb8350e44d966a0e8ce4088cb50c5c84cc5f585a30139c5d6f0e4dd407cae72376eb9adf7435d536b990b43094480d725f2d22237c8	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x4ade1eec314294b94921b392525f81e59d01fe24609cf6c72245985dca3fedec2fcaaacdd2d3ced190effb709669dad7967bf751f7efa1a3f2e11429a15b4b05	1607681647000000	0	2000000
25	\\x49b3545890839e46a324a839c1c9d35494ca7cb75768adceb394a59bf657646054cdbc580f9d60ba22a6ad8c4483b314317ba24dfc4b491555223fbde8319159	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x234f6abda56ca776709db69afbcec604d18609e007ba1d573d8805ff1953e91f212b6e4b09bb705bcaf25684651768910517c18a115e5381105fea7533c80fd7cf04d4d1370e1bfb42a38d0ef10d6212497d7622b0f27c197d9c1a8424d14d1a330373cb295e8851aca4b35a99502df463188f1de488305c71ece96fde9dd394	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xf71393be1bf3aa51a2b2c6b2e2541efa2a859ad6056ffae64cdf5a0b26f51e0a4df5107498647e8cb75c31cec07c14939000db90d1ddabc6ef24b2e9553f5406	1607681647000000	0	2000000
23	\\x82fc10da47c7eae1d3f82e9dd18f7f387947c2aa0ebad2367f7761d053b68cdc298a22cf440b2652dbfd2f189087eee26c829311d95d036d9c941451c362ead1	\\x8ca16242ff5d051dd68b1e9eba919e61bed437b92bfbde227e6ac52a627b540d6b25def3abdf493cf2237e9bc9111effd84e5a503aaf3506f9bbb17c4da27353	\\x49bf30e33c3aa1e6e7a8d7395715440193cb54eb070a8a0a4703914e2aa05d501cd8889b7d83aeeeb7ba8353cbf5c6ad81a78325303ce6743a2bc759dcd308eb5f011da76888d93a4472eaf33b944e5d0a1e925b26e21cd55d298ab7c5fa4b828b4dd5b78b48ea0c2f5d4755742167f1c758a2e13484f01c2678c2b1faabba75	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\xd03066031565fd013ea02f52a9f765090e03aa4eee5de1bb551ca4fe862705868f8c231d9d0365f7c8824a0b7e09c99cf9d9b763342fa5d33182186527a0c401	1607681647000000	0	11000000
26	\\x2643b40bc96d6cb28778b15f7ab6fdf336f8ffdd2c59841e763b5f597aed50196700d63d71d007ed7cab1d49ea491607a175454b0786986cdb784a49c86bfd39	\\xae6e5fd6421b7c177e7c5912e1a1507c4f60639daa85c0863552ba2817f4ea471d161b3b0946bf4b2fb7ca41572533e1661b7260bedd2471fd929f76aa53463a	\\x12f827c0b8001ce304a4fb1a56af20f1b0585a09f06628e32b4f08e811adeb15f9c34943f3a517c030af4a654ad6526e51e736672d2da64cb0556270e199affd655a70bc97647bfad4430de26a19e96442b63e154c50e02f467556320e73e03cc033bec7003d1dea17d9484a7edbfa1ece72b4470e4e8cbf6fe536f83f43b6e7	\\xe91f343cf7d9a7ae1b39091c4a798ef457096d0ca0bd1122b6c6f5d77d422f08	\\x36c3aa53e33cb6dfb10589652e219185e42601551acdfea2706774177465f9ce4b35f2736afa8aa7ac07964abe277e0c5d4ca6a7cf1def917e3fcb9ec92f070e	1607681647000000	0	2000000
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

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 2, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 4, true);


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

