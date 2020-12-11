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
exchange-0001	2020-12-11 13:13:35.800063+01	grothoff	{}	{}
exchange-0002	2020-12-11 13:13:35.902194+01	grothoff	{}	{}
auditor-0001	2020-12-11 13:13:39.798338+01	grothoff	{}	{}
merchant-0001	2020-12-11 13:13:40.025786+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-11 13:13:43.795927+01	f	48f3d8de-5791-4f8f-93bd-730304373d6d	11	1
2	TESTKUDOS:8	D46XEZ54WHM2C2JTWB2SVKST5E5SGTZARRND7K159KMH7KVD40KG	2020-12-11 13:13:45.119825+01	f	73c65545-2468-414b-9b23-49cf0c44d02a	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
a6b66daf-adaa-48f5-a10d-2391dc63ff15	TESTKUDOS:8	t	t	f	D46XEZ54WHM2C2JTWB2SVKST5E5SGTZARRND7K159KMH7KVD40KG	2	11
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
\\x7e6025b653fa19b9e4a9c092115a259b19586a527c0d97faae77cf00eedcf901d07478e288eb14eda76e2b6fcae8c0c01f5f4bc6002aa75a01058a0cbe13aded	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa9ebd4fffc23e42b677d165ee80dc8e6ea4ff24c3438fc790f89f1548fd3862eacd956f17336f1adb90cd5c6a52ed70b14fed13f2c0844051bcccaa631f40f5	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53c5df43261c179709c3a9e7cebfa8dd4c2e75198dd862bb25834eb92bce57cc8d99fd43acb53cbefeb310be3a9b71910b063e0c8d2983e368217b10c2af040a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a6c4f3a2585fc1b6a7169ee9e07743195dabfc4ec1ea38d91deaec3308632225f1af5b2c85eb132c524f62555c71ada740297d42077b35a22f36e64f929ae45	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61bec86cd9c68f2c44fe323f06b9536366eb99259e4a8f2858045389ed8731667b828a66ef7ed6c99285716bfc937a2dff93a21580a8b8341a7a9131537f466f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67e03d72294f493c4fff128006a626608e4a61495b200059c2b1ebf38852ad8f2342f4e933629a1185c333b95f95e473fc913e42f61a616f8740f06542cdcc8d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f445bb4e3dbd0a614c595921bcae55246776b6df4a14b7c5a27f29e6fecde71ab27fb99968678de910348b032554c00c8e1bab30a786045cad916b35150a0b9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e9dde1d0659805eb14c2de2738b4a37a4d216f9d1e0bbfcfe0ffbe8440e47db885f1987c46caeed67d76dc22a656495bfcba424caf2d8c2d7a6304e3ee84dc7	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5fc345bfd458d28b0f1ac35f544730958bed58e8d3bd6a3b535488b2459eafa8c69d19a98733e60d600f82fe81de3d3510e20b4e7645d0cd6831b239cf5f0258	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcbdb14071d6c17a48b231df9e8e65f848ba493ec66f60c8fc3d3b6691ecfdf975a0b041397d72735c01a2f0c8b64b277f4f55e5e5e54a1baacdf4623936ef3ab	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x875fb8d5ecca7dccb13523352b782e4e389a90c5520d97246862a02125ea0443787afcab1290757d3143e23c183a88817595d09bea3bfa49ba852ddd8b58fddb	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde2344ccb5255148423f3b944bbc7bd8135b8de628655035e3b8aad72a1fe37ba4a2cfab6f9cec0efc81ba2e0106af3ac060b8a1733bcae145f3ea2b9907a2b7	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x88a7d0f9406149d3c642842eaea6637d6910ab8fb8146960ced8b0b651ac66578077d03a33d0df3f5ab9243a5d7166d008908569f9e79602512658a1f1576e0e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x154b1eb68084eed12ecfd9746903e6b2017389545e94d60b4c63004a8f1451b2262e468a0d02186e25505a84e092cac0d15dc335a99011b239a5c4dd662ae7dd	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17f6e91ee287249d94add5657aca41de238fc21949b78942700a733883f4bb6551749971652762cbf5b2a06648ec92bacb7f14abbcb846ed15c7fb8fbab08778	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb8d8e0c83b6b4d0736d889ded75a4f8ecd916b37c0f2a47dc429bd6509df2b1a17f2ae6da40e679f92e68a564a62a9cd1f59dc7580ac81379b33bde7f41b9ac	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x357b07dfb85fa609bcda8f240056cf486f82fdd09b440f6251290eb68a4359ea16f828eda5123b7f5b5fb6884b62268aafe7a8a14fd02fac6bbc63820560398c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa225a975654d8155fed3d3246e2846e5cb129fe049b27efb5810ae9c7a81aa68ed9c3b3e10e03b41d57afc6d2525bdaa2ae16cec95546ea2035079e114ab6ff4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4fecfba2fe9d54426e159c1135ce74429470bcee3c9ab35b21f4ae61b3b2a69156791ec3f25fffce8f1f1421ce76b592db93fe341a88957f70e4ebb11e06af7f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55f919db7bb9168cc5d162aaf15b5a3a166d61db84a8642bab7ad339c2457c21ad18d3f06681e1881463882f94d323535c1e4fa230871fd03f9a0cc77c30312f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c160f7b8d67920fd666d6ddacb223921becc85c0654810363a916209673cff475fff5d534c4f2d186174ae8401bd04ab85421bd49cd1e7453d9f4e955c8c864	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe85fd209f1bcc4991e81a9f5fe0de584e18b1314814f7c5bc5dbcf2c1156cb86d57d1e7124e4136ab6356be97fd5bf0daae25a9076326fa6e6ebaf6bdb4ac5ca	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86b1cf91fed193d551ec11b8855c265b57cca4d588d900bbb56065e29acdd855f084797e7f2f47f7151e805ed9e53fdc3b48065da472c4d2521a85fe7f15c9d5	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x83ae82a90bbb5f8bfd21c2f7127edd929d31916d45cde82ac305900999804e8fbe6ddeccea9ad7ccb43ebcb77f84a28637876ddddddb08199f8a0254dc2a9047	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd6e31d92438ecd063a312105592b5a80837778bdac87121de93ff0df39876dabb54276d0b829d680820b63ccd7ab947d80dfa5ac75b194586a4b0b0c42fcf3d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f2e019c6f29aa3e62d58ef94c9674dfd6483099c42c8401d408cc19337d00fe732af5f78ffb173fc753e2310b5376b794998923204c9607629f365d97e55751	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8c06b692a25f7b6555ee8727903ce185f8a5998649b426fcc9bc6ec01acacad08e4e09aade54774ab91a10689fc40622c2e6d4afa05af6b2291e92d91a73683	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71152315946323e21a1c4e1fcfd66864e01966b5ecbe737afa2e7642a1b3da52fa5583b76971c1400891be7c92d1d879afec6ca7078a8bd10129e80d65ccb096	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4920df76829f6d570400a4589676d2e2fda0a5c889615b9eb111ce655a593021a457ec7b081480327f2bea9c8b370c71db82fd37a9ecbb449f4449456ff8ccca	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fc8030c1cf0b95d1e2828212356d944f4a2423a747b1804a41e33268c4e8349f6e0ffa9c08144903473b70670e55e348c531c90b765401f85bc3d1d8db8e801	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa01312d424e0a78442efaa3fe0e4bf3c139081d4a1a741f583d5be46d7073e98e8396f54d82d1228a5b972e553c698ba4946a7ba1c6c488c96c5f3c04f47985f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x565431b367570ede4ff861b2f9358fa7688904dd81cf0ce28c4427d47dce647182efdf0506aac7a63bb388babbd582b0c7916f9ab1024026d829e2edfa255bdb	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xecbaafd0b26469496c892e614bc3bf2e767d199bf06375cb1279d0b921ea550c354db794b0f2d282df9cc3ab93299ba9b2c2743b216bfe46788eb3c6a5222a69	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd597b75514ab2e11f038821daabd15da7b6e3f3772d6e27f86e015a0ad36557e35773e3190708644781a01240860b3b21469bf7a986daa12e3a4ba5d90620028	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdb3e02301999f4d28bbdacdccee2b2617db8d37b37b27ab965c427f88f802ffd170b1c9f366bba5b8a906bb35d15b8fcbe7dc9d5d2825ca0901e2b9704a8f4d0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3cf1e3dcabfaf56afc0dfd1b73454c0d5e120139873944d523722f290d07331e6a8557a6e076c349197415a2f573b5654353bb9a0be3026895857a013404adc9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe11baafe43ca9ec7bd7a4ead113dd228e2c59b58a409696d2272ad27b4f355733b0c2928c83d5dea62c8f77ee2152400da712777d4a4577248fd95842bd04a32	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3f19a4c39ae6dfdde35f35ac21ede06189c0d9f8d433429adce71d0518b50cf42cfb1db95a7bb5794ef97345cee58e2d3469ec0d61e6a2a0a851807dd60c7d73	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x53954117be8bc8375b972b9abb9f39471d70058d94366ef4f86a75d14dc309fd3889759b0a29dd7f8de2a466c443b22cb5027328e18e4b393d841991f7c64888	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2bfb564b35684c8e8e70e1e1fa728d02bcedcbd9551a67732e784fa38b5ac9d4f1ff3a384807da958fe2330ee5552b0c4274f8ca6e444daa8c1f7cf0043edca6	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2ff4e11aa5cf41fedb6b305eae31b85e1a109a8626402ea32f3c17877902a7175db0abfbc25094675a66473f8ef83004df3ba95967cb81ca833db2eb913fd6bc	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8f1a9ea8e3e9dfccb841d892c298f70d05d6aa1cf2950259f648ecc42828d7c8ca17153f2a1bc1fb394a9b10aca32fe5ac82c0502ba3e68b14af877710ef7746	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x10163a43ac1a158708d8d72eea9dcad0cefadff54aa10faca18fee03f0a13024d205434175cabbc87001214b529e3a199d28ea2d3ea08524a01ca260b02480ae	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf9d1c0106447808c6421896c5b46ffb56d443a00f4f6215d7b2ff00546ce848d2119cdc004a715db15f56f5a8a49da440497455d15230f96cf7ba1d75c64fa69	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf6dffdcc7df00c875cd7b23a267849eaa2d0e33979d678cc46a814a96e821e1ba6f9dd2ac9f2306e695808fa649330aaeb58a811f2e5f5828125b2b0f229de84	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x58879de879dfddff8079e35ca021dd74f69ec937bbb1b621380d019a224b2ca0baee31e82d1619af1308ba645e9a5e1f1726800186fb3b61bdae0870e6645ae8	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x706d40411bfbfd70da8588934f89abfbe07833104cf9772b511feafd3bc6ccfdcf738db39c7ffbc7ce3cd491c034d0acac1629527965c4a616a2b56c3d17a2e4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaec1cb11c8703b92efd8c9906ef51818a3811053c516cfea07ebb223cb1e5dbe78cbcdab6ec1619d7283349aa6efcd83808f897df977c51fa25a12d101b77b25	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdd20f888e0bcfdc83667dd24c92a5899d5fb2e6e9141e59bad93ddef5e4426317a5a67fb01e2de35e17d6a9be5eda3a002e81fdc0a599bb0cde148b24ba6dc96	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x73be222f80a8626e37765764281ca96502f361ca5a013bb72872f76b384bd5724e997598b7c5d3e98f9e98e8abff7ebcb29fa5a93e555c614394ee47ef1fd23b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0f7decb936139b6e0a4d5f8c5b369096671b4268541690c56fbcacdd561767fd8275c0bf3353634d81da774ad56f87185eab0df17249b62e5f0731179541563	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4d0a7289e42355396f203e27add4c885ec3774e2497c00ad0ac0bb3e7394b24d3cfc0fa1c4d2f0da00b59a063a2c0b970c647dfe102c74e203a29ed3989bc773	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8fa67bc585088dfc384567e5d19715a65763ea4abb6c6e00de0d3ee06fbe1a9d0bc46b597126db18ef68206a92fa29a952009633046543973fa309291adde191	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8ae7b528b460710e56ec79c0ef8429a711a01e32a2bd52498c62e0a2c236295ee3053a5d6dcb1f4b15954638dcacd0e692526d217680a03119f457817b6a9167	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x16213897fd97576c1b210ce2062614fad654e486c1938993ebada772bfa5cbc63f6c6ac0c946983f8615be35d3d1340f8f9a3cf3cdb443a6e870ff90c06f48ab	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb86c1394b98bb0af6cfcae087d202b62e1a66313be5e0668ddcfff2bf7b2d4ee54feb2ac4908ac7e119ff2a3f4f2827795e9227558a5f23ccf86f0c4b763547a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6d1c57178cfdb6f8c9c481915a0f09338ff2d6d533915455d22fae7cfac2fc54f5d726b5ef8943f719d25c68b86049b95e91f79456b97108a4eab8f4d044d341	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc2a6886b9667b812384cc9fcc0754effc15c8cd21e2bda47e08cdb533106c15b4357d29264224bf4c92c3953fb433f86f63932ec5fe1cc4f108842f369aacd67	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x96fd3b7dddd1139fc2c56e01b2cab372635794ab8d236ba29ab8a9c7bb9a6846763054312f717384672eceded69b0e9bee99190a14dcf6cd0694968433c42959	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x258c4bf45d08c33833acb2f0030de3d6463901514d1cceadc72a3f4de9e5f1f6e9721f997816daf731976e68a764c99fdc0cab46662f264ba2d69d0232b16e4b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x63e974d731e03df0be0d20ec511eb2858fed28aa26c2a0f244a1645bb31905c2e9f12e7a94a24954334ebe02deff5099bbe87831b653cbef8a2cfd0dcd9005ff	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb9e49989ea29aeaa6c0d6a45d586161d85647eb69a10b7e7cc5327a0336ba45055f2ac14893412595cf8a282f35666374d02ee432b76adae3984105d397f6d4f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x641b7e525e46e6d000ed861e86bfa0c40ae7651eece1edc27cdf2efaa4c5d151656f0e6e2edbef97a040c2b4a7c2b5c3ca54fa8122367eb8e26920c5ecdca21f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe131fb736c8b283bd65e9857d6ff0e96827f2c983840af02df59bd42ead7ade421108e0abb68cfbbf0e66a613a85fbd228c471d0588c2e79981ee4e8047fea82	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8e58837f2a028544e2a1bbfde45e6e0b1923a10aa5f2ecc9f31f21afcd48f7054ea893bec6c89a2522e99bdef7056a2503fd862154a7b2fede138ce2864de5a7	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x41ccb06decc9f13cd0656a75a5fcfd3062947fdd75613ade0f3335c80bac8f418136f31204d1138f34c502f905377de4b590a1ce5e57710f4d0ae75b2fcf6465	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc7b0efaf2e440c85fecb226b6c17e8b584d67b6bc8cb57396790b17c7be0d6e8e02b7531d9c406be089793917ee6782bf3c4bee95cbbe24cdd9be1232470e543	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66d54201ee38e240d8fc7cc717f0c72d3ae58fb9eaf25ebfb3873cfdcd037e8b67dbfe1ca028cdfe7f8ff59f8be8d9bcf48d713a5225371b62f68e069874bb89	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30825424d236ef83776af7455aedf9dfa65dd295a7ed2ddcb7349fbbf1b7327cffce12bb2608e6a67cb26b63692e5ad4a5073528dfd0ba3061ca28e694300c5a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c89d38a79db5e166a1ac12b8b13f841f22e8141b632df2464ebdca8b8ed050123de0b93ad3e12b6481184d7ab291dbe038b760ba0b43cd24bcdf04945b3052c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e27249469d3347ecd62d4dcc134b84534d2e91b40838384899b570ba774a0c3d15612381563b57e0187e4b34b5e73ba8c618879c85d3be83b146e84d35d73c3	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab85c7ca91e23e100a88e698cfaa1d84498cfc0db9f2532687da89274398b5e6bea6273a06461f15afeb9f78dc8dbeaef82063730210a8f0f105a7d794b0cc0d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39745b78f87fdec221bcc9c7406234d1d4534b798157a92e7ead70c70acaaa6d70878737f348430a717edff53baa2e37c3137d03d6f5568684b9e05075a888ee	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcafb04f1a06ba715b8051079b64da30249ea3d6a41067f74c5206858084ed4df4e52f13331b551b8e24e3bfa693ed93785127639fbc71d2f24f4ea8b579d83fd	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x213e081e17d80617cbbe6fa03b4b5becf09cc276871c31de24fdeceeedb5244ca1d15fff59dc158b0f66bd87b21abd5c938856750b39cd8ed39dfcc12d0eb5f1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0bdfad437f672ddc9232aa04844159023d7a2f40c3fa8d7d6e181a215d3a47dcda73bc2543660f78e255a272eb7ad603d3175173f001a0f15bb01cfdce964e1b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x36b6c17a12e613600dd8c534b39fabd0dafa9cef948cac8df32906396bc039c7bea2e27fb2872d89554f12aad1b254e281f805e6cc5b2835a68d7fa37e185502	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d1b1306ebce14e9f765a8dd9e57c18d112255d4855111a31d598ac3f3baf03a6212ebe3ec6c21bdbadc8e6b4fe2e50a1192094bdfd1241d012616739a2c1a4d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8b6350f5299f5d17f21ba0621a8e1ad26960c11911af9b5b637fe89a955ac93af7229729474d9eee5be39b9419a6e49a17622cea5e4043fa25ed90c4f8cbaa4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5d2c2b36af392f09dee0520b0ba60f8f4fba9df2906f31be14dc82ec118b32d194096a0d79fb64d051192b77a292c96aacfdf3037b83345043b62d8bfe2c060	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc23f5f997d44e996a3762d7705b2c06e24a0493245a752d823ff6dec71539d164dd67e1ecce13ba143864f8c54968b0d3b470e690b1f11e2721381b0a77beaaf	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf53b82cc44143f98dbb626e1fb3ae52992584ccaef67665eb0f7552ca438256325ffaf5539830d3190ffe2516bd2391985fba0ac774eefa3de99e342e7e12bb3	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb57819c646f35bdd9da7c0bf8627ba89ac2ae9d56439f598fc52d6e00907bb4389584e371428186f3719ed13d99f1dea26668896011b23dfc682cea9b16e2821	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8cb5413c8378de3ea6762a67f61fd53232906a54d9076e19b9fc9e22165a9c34fdffe48f32d6a2820fee715e0675d6308d6b369d5ed4b50f514682772f80af46	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa3a0ef90b8cc118159f1fd2454d46aee4ddcbdae59d7f05bc42a391ee98f424165063c883d6454bd5da9f88c42b5999d653a777687a53b66aac0962a4ea3794	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b76f36d106e106ce3d1ceaaecafd6ed75f9570c49a074c09b37ca20f7f9182f4a92bbd632273a1176aff7eaf91bb84130adce2e66df212441a05c6f408b5e8f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x809f95a6c61b57074d95e60838afb65f651db637d79e2d727f7a8d2fa6e78d435702d40f44104b68b77bcaa03fd0c72d994ea8b4840475a924f118964202a52c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf4abff575569bb4914ced61eda66b4725b2bb32e59d1df61d3c4f8d46ea24a5e37e9b58c107413cdd93e84c13014cb4adaf7b9de9534bcbf094ea064f6df24b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa7a3bef5baf5df7b3cfc51ed3b18c7c30adde66b28609debd057496c7bc1dc4bd0b1e98eaf960fd97bf0acea1fd8f1ac09fcdc4f588687c60ad916cbcd131c91	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2e8b7705a043646a4dc2b6ebff27c08287ce9101d4db9e5d1b6ef2af17bd2a1c3b74df9d2475d39cd418954a372dfe5952f5b0861ac18bef07c0fcd65d39803	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2634804908b28a2b76d93381d914acc4a06573daff9c5624d0d2b5a8740e9869fd0ca64ddff863ae0c5e14a4adc32ca5c37ff7adb28e27f48484d11facf12b2c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7c600e3f11677365f3ce29bd0efc41669d8f925e4698ab192ad99e1d44de4f462f87e6ecad5a65581e46a346d361775662faa90c60239ab14c7a8f18b9a527f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c8a727adae2b357ff34ede797dfe3c5a3d3770e4aec64f5e8fc0828d0e72420c5af7979be5f0abf63a9dfd472c7eea03a281da53b6fdad81ea5954c8ba4df8b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc17bd0e697afe2e2ab1ee384ddc60a5a158bd58ab077091293861ffe7c3dfcb94e07c3e72d1be66393d3e0f7446d921381f2ab5c48d0bd280f14f61b3666416a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55ef2e44ddafdf5671cd442f5682aee13217a98ebbc12ebddf101a944acfdeaa958c946a87142b6cfe624123fa893b8dae75e3b4d6ae6a655d7c2c6880fadd65	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb850b7581c8a258b257c0869a1579d54929a8989a3f0e120896be964790511872e943651a563538f4e8af8f87a2b7ed056e45bca2eae0035d81d4bfbbdc0994f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x244c3faaea4c2d44b81acd4a742e1986317ff02c19c3025ab9c1c244e2456a924cd6c46fd5d9711e7d3a928579bb24230229e9737ad769359c782f31337ee78d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2237663c7d5c819945a11aa1e7f793e7f32241ed4867631adcad89975dd97b61f5d511dd21f6605501e3d1598136f9aee5ebbd973559b0b11f209148bb37c7a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcabf26e297d3001c7861848630030e5b549ff7d1b3cbadc6d468de81398ed9fc6983a6e6690f3e91fecea3162b50801094aff634a2647949982dfe2ba8739640	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd603de1aa6e2e6057fa2366ffef8891e79264d4e7131833d13b3c5114dd860aacea9d375083754764c1c1ef100c97839baed9c5cc5418ca70f6b054d26e6b0b8	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb5b14b3451a36e529a06dc3b3e94907e63607d6db1f290717d6a457ad766fabda7a72574135e5a5fd6991ab3901551ab567237b33b832de04aaec478f8e6808e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf409fb626e27ce7807ce4e0b8b2223a88e985015518c1cb6f5d39a1635676baff8fa62771cf6192738a5dc3fbe4297115e497e2217d43f12362364c83e246634	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc797ba8f1652f2e1dd013393bde4c9ed8e79b8995f4bc2740fa9aa2a8057c69bd4c5e7a42666111bfa38dedb32e3f2f816096fb6ca4bcc760e8ba447885d0c80	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf5cbdd38d1267d9dda34d813c5da67a1e200dfb38e7f5471287f3a11c8e408f83e519aff1f71af7cd1bdb2747bfc8bcf0746e1f59430540fda062675b1d7307	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb088077bc1abbb8f637a4712e1d574e15235727f1ad0dda5b1a22a5761197a0a5d8251ef20a5bf3aefb58b4763b099b24056e0f7b6457e0faf9796e00197aa3a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9f1ed839923cb2e4d94a9bda844f45b53e09868f893e04d9ed64b4f92ce62d0bdf9065f1a9ca64e3a9075cc5980929f0f93b0cc4a26bb5a458565a8d763e4690	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd189b3da4c092307c4a156bb08002522d35222ea8fba72f6eeca55d388b3aa9e2de1eb3aaf5e2bff09ea0f92da1e25c5cbf75fe82cda8679a48d5b50f293350c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x707b3298037b82fe81db4e624380a6300b55e96070e678ebf980772697dd46e8a94622f8b7a30001773e80ce3acea5462072b3c998d7efa54b7deda1773861d5	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7f6186efc866b779175c77b50f6d19a8883f9ca7167c310b0f2e7a0595b05fc9b7548703b9769ff31d838dd3de1aa3a6957ca7b0d222d5d4cb7bb72cb2298100	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa8a319cde52a8e312a522aaf6c172a61cfce636951776e789fae8f76c3a0a1c712418cb449b02e9aedc603c6f0cb74053b9b1dbcf07bfb8821c968644f395ede	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae9ba2ec109b77e98b2d9a7c7d282cb887473a22a5fa4bfc9649850ebcbc09308129a5facdf59b6ed08e9091fe581248e3ac943d8dd29dd462de37763f0fb492	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4722ee787bf675f3fc78dbc9d9eae426da63e145b867fc5895c1c446415782991e422088262d39be05bf5aba29e4ee13166a6fc8baf6300de88891807582507f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x863df9a92e8f757b5787769790c6722fa68d91854c93a34c34b2a2278f956aeccf8ec130c3705bc9a2b3f822f3bade0dde03c4d03ce260c34afaeb50d3093e4e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe5a012632cd3d53abd1067cb7f1e674d663f6ce48c9a45ded4d86b51ad33b6295b2cde64ce87f59ab1f858030b7834e62d8d4c536925c68e36367842b112d931	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd24b2471297228880ef981cc9af99c260cc631d089919177d2c708cad2f4c2081f5540567e16088a09425aef970708da796fc3ae4ae482b9ee11483e91c51fa4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8fd985dac6fb8917edd4b3f7233ed0aa52ff01a8ae4d9cf8444cd344db138df0088604782433b17d10ff054bc5b0ff547c9cdd7bc0e929564a8a3420ca654282	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb85a9a06c1161033a02f252e1d0b972354096a748bc657b4e9b9825c4609b43f26902a752eb274c2cb08cb97ae1b2cce009a36f8d34ae78de676f487b3c30e4f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a5597347e3bf7ac900b2a12ddad938931ebc0ab21adecc720d694a0a812f5cbbacc1f19aa0363c29d345da9dcf16b0baa64e177c391b4f81fb5baa7a422cf03	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x421a6cdb8b552ac05ab706a876d281f8b8ebfdb7ef6322a66c05e1ccbc88736059b7e1ba67050d772afa18f1668673d9ae1ecd7804431684d3cb14b6b0a72b84	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad13d425623837209bef5b9097ea6a21c66c9173c770b6c0d20a63c351edd2826d6077514c2fd3d41bd2049c9d8736fabd5d62f4223870e25e604e4818edfbff	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa476fa3754107230967d5b2feb3da0b2b4622a350887816e373b892f21f77726f9caa04b2b860bc9d99d89f0b0fc651ee04b5b5130b7680779320ca807db874d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7de82a227ec7413be2f127f081f267ae2d5c06b0c4ad80cd9642b17a70f8ad29bd0809201dde898aea7094d6253ca9678084ace70360140d651df2904fe42ae	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf08841d9c8cfa5156d985ae186cbeab62635e72ac72dfba3f9e38f775ab506474e533fac66efdaefbc3afb04101730c27c2844217cd9508dbb1e5550bb991221	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc38c833e2407ded6addb6fced68260d569e5c31bc3b4da7fae6e5c8a45f95fc062ec14573a63dc25c533b1bf76ebb8058b6b034853a8f795bc8ccc70ae1d2c9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf93fc807a22029fe34e372f2659b706aecf583798f7244165a1b700ab558ad1b1a96ebaa36fd161f681eaec3e230a114f10bd5745c9b080b7fa4f4d391bd9610	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x628080b820d1a412422b8035dd9f105c872f1bc37c90977b7c475c5fdae7d156d2c8775fbcea55077d90ed85812cbb6ddc38d20a067f3fb92a9c2ec67dfe63f3	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ce52b4fdc4fea9d43007d32e9da6749f565695ed5d1ccaca56e9478e63c2bcbbe1471ef5b6f1ab0b4a87a91a20d6b3aaae26104e4f25cbc3fed9cbf62adab4f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa7ed5d8b7e4b5df2431ad8264f56dbc9748210e8326aa2e167268fc634488769f43c69589db607e0cded4ba4968bdffe76d8506eba69dfe2c89917eb70f0fbb4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb058491a9cab23bd20d2bce952c9f8ca7f4e649c40e6429a3e4661e499a368f126ce3d6d92d049916adb79a34b509fa44175cf5da4a39b9f4a238a8d15872e67	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3f7e19aca03a17e8971a8feaacd4cc3dd806fb9b0aec323248c87e4d29b1d98055bbf4ee81e188010698995851cd9d844ca4cace08468fdbedc09c299b5b7522	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4888881c5b330ddae5b03a71d205cd0c920982c4f5150e218d8c753b3a9f3d39a5dacf5054966df40bdbaf8b8b5c7ca5e480f44b9762650af3646dd0ffba450b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23e6f423ef9056d8c5fc5aaa046514780d9e19adc70e4410d36abd5132e54f0871f46a03fd25fb3d4cfa4899c674fefd313a48257ec4c6219ab5eaf3c1b634b0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15cd172ff9232ffc8792383d0fae13eeaaf3bc40676928bf9b566af80224fd727cdadd3cd3cb1774de2e577596a84f9819fc4e791deca825383fa2a9fd06ee26	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x767eb15f94cc5de02e37e6c76b0dcd332c0f22f23dbe61d1c49b89e1d3070884eef8c1046568312ce0d95245c0f9bd2a4e4bcc570fc147672c27a67492661a62	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3922ea2d31864408d7406878e79d7f72c7168b5ef54f7ac4bf21f51089873ea101aa010abeb72dbb89e86b21a871bcda7e16619aa1704c1ba34bb7fc53cbd101	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd17f99d10320821b1704b078d9550496464a76139743bece6d5f2ea1c23a02bd9f21c9d209fb60a041db6f758faa9cf41a5339da6435526e8b23c2fb51591420	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaacac79d5a11ea4c17f5ee9ef30e8a152ed9bcb8e1de04f15012811b29ec707f110cb24dec57b73573a661395e9b75c201ab0022b3cd9db5b4e54ae7a78da87d	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb106feee5e1d1d39bff971f338052de256c102fac5dc934b7b57dfe7ffc4f82b775a52b21dec37bb8eba36bced00d49795be0aec19b4288e92f9fcdc9065b1d0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x17c6a06c8145a408bde9329a8f2b8c5c015acd1e0250a200242383ccc4366967eb5f2fcf3b64c262d9f8b3855953e1bc3d5644c4b4037e14b8f70e82516ce6d0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7162f9c183be11b46e9b589bbf3e311956c7acf58110a4dba2c80c7732a023e55243fc4cf3ee0bf486fc552717494eb9b4872fd5aecec76d23a614c11a8b4e47	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x03bb02d50313bf74e547dd02b45a662202361475dec283e37533b392ab5e0d65f5384a291444d232c30974e08ad788cfbf9beed9d44e38bd51b33772108aee21	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2eb01378166fc2b343877a4cbc2850c889533279a5efffdb75e217a401fc116d1d60ff234091a752c1973456157603f647bb0ccfa5b779f35d8ef49d378c5ae8	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1a8df27c3fde0fd12c3cfb2d912b94255ab4aeed872823725a1dd28d462d5a9d9baf3b0f0e7f7c854ca5727880622c7a5d90f1738685b808927cd2aee7617d6e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x05699e51ddab55807f99fffab30b31482c38fa4fb2ebdb6e2ffdf2b9eea0e7d46402545c174ec68f97015c71252effc94c8f7210cbf2916fb4ebb88b0b09b20f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x175a5e53d93c6557d74c273c13fe02b329917ac6414463da34bed6643ce0f3c5d316f8c47aef621ca1ba736cdb1ad9c00b5b8232090dac8e14acccf4245c04b1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc862f92f4576eea5992f62c2d7fddba37c7a6d5e40b2d697e0bb1d8ce50032bc40762ec5fdfe63a9402883416c377455417b33a9ea2cff0cd3414c74afe908ac	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd857e8504dce7bc67c1d909caf73056b8dd016567d00e81b700591be08692e7d8e1b32d2de628873ef3868539727e6133d3d63bb38c3f06857a7eab62d117ccd	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa769d00129c4a73a923744e21edb0ff8ac18d673265fccee8a0636b4c1671e0442c030ef606b0ae78c251102543436fbc56ffaa48abc65ad3f24d7539a634c9c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9d52646e47a3eb48c37854962f974787314f0a4cc09cab92a6489e1a6af7624ea96eb7e78df80b3590c88775a21466aea13532bd99441034d3c42f039b5b4f39	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa5390e0a7dda0fc8c925dd5b87b52db2ac5832d52650a244906ab0282c46d13fd9a6c1a0127465290a40cd592ad9c94a9d612c398fa28942f31ba506524810fa	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28050e446d9c19334edbcf7be7ecadc691c8962e473bfc86f890ade5e11b7a20588c85f23f4cc45c792c6bd6435e54785dc2a9a4db08580f32c972aa59369df8	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x691a69ba44fa86e89c87bd9cc25f6d9bb552fe9b88978c6072e3c9647a0ccfa46fcac1726717a565f22f15b9d1edc9e9e60cdcfdab74f8f73c53e09b332e8555	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x84472fe88e6f3d5ae07fcf41f8f46e5bc90643fbf8974bd21ef22da672c63fce2d75154fe4248b332b931fb1594f8c168d0c031e907b450f53f2d79409f2c6bf	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde015a606a8143d1909effbcdd5903300bddae259f627847b148ee8341836a9d8c1086e8230590e5913d076d8bb3ce7efc4f3712978c8ed46729a33aee4735ad	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcdd3a2bc3d4a01b39e72b61dea6176e6544ca251740c3dd13add9e9da2009a2661cb0f38ad954681ac6e229b8e0ab0dba0bf36cfdf85126c4213e762907dc30c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7d9b83816c7eab3a23b5d17bbb0dc688cfe71d58dd2d8780c1d6a8c370d093d7607fe0294a756aaad84e3c5e1f63855cca101addd2f08e7d695f0ff99a3e37d4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6a0c2bdeb493b42edd6a18ea5513c1645858dbd395b8c7d3269ac68eef31b30d043ec9eef2ee021bad5da79bfd7316d9bf09d31ae0b4d0e4af51afc0fc80035	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x05b63e809ff1861223f242c3376458d6a6e41279a9c5f8b87fcfeb2fb960b443ee7f8ce930263378383edd2086bfa8f6aa77c8fb0379fdc52239bd8cec93b12f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x412c7b88a11985be2af63777e42e17ea896425dfba83185d88f557256d856cf27e721139d2b1c9a5c690c59b607bf01fe0134c1cb6829bcff97e0032079e518b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x22d641831ccb8eab05ac2971f724461f97f1db78fb841ebb792cba237ef8fbc9c6bda89306bb737b280dc637e72c2be2552aaced624587bd7a1eabaa2ae6e6a8	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x65f05c5968b5e9dab997444a8dbd24e12f01376fdbd8ca6f9d2667157b7cb907e06a7b47551a03e6c5f33f45b3f3fd226222402e85849262069849d6f8c316ed	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x42d1794176d248db43b4c453c78a1815bfff54cda91786c05d784f581f8cc3c2d958012d0fab5e805b82d4aa73b3bd0f821fcf299f8cf912a8c5348cd49915ff	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9100a3122ed4b5190e180c7cd0f0ba259376fc9454dacafdb7ecc80efd0d7586e29e94ef52aaed010a008ea376e12b7a0b839e59554b733b3505e8119b1a67ef	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa2e5b2183bbd269c2c3905f04f6bcc7c9214b9a4c86829f2ff9fc83d1aecb39e7e20592abe69d95ec82360f5519f7fc89908b6ed7372d781e93d27708f3e50d5	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x87ae3e87d991d0253ccc6021082db40731177802769f37420c96c9533b9cd203f9f81a3f54c2ec86e655f43bc37b89def7883c91a772446449eca71e02c591e5	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3591f89aede6cf4aaa845ace772f0f7a5ff6e837b6c64bd9a9b163e4368486ab0747c36c426ec5311cdf84dc57391c1954c903b8395330b4a64a4d16ae3bfc5b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x782c7f8d90cb5970a3f73838cc45b6c24b70eb140043c40558c052cb979eaa0d3fdc710582ebed130d0a7ca32a90ba178682370eafd9d9222c1694f56d4d4aff	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x367c7c6fd3358be16eac71f5e99aed114a56556b38dadeb13812d9eb08fcadda0de12a2d0d192fdf9a94f530c53b320df12597a54433ff4b7fc6068df32868aa	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4d9f19d5d3424cf31c60e7f0167dfe1e4bef132dfec811c88297a10eb806e2a2a1a3ef9bb121c67b26e93faa8c6dfb6459062828c5d24bca38edd2aa45e9b64f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2c22dd922738cb90cf9316764fa3da684cfeaeb2f133a01aa57c31d4cb7cca176986c3deebf401c248a32a55af0c8eb917826b0599252756628e2a442fe447cf	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfee7ef0eace0dd576d5a5e10eaa0b5e5f89eedb471f2715b066442cc5b393340ca7bb318bd04dc0c58f05b65acd4d555cf5e074a261ff9f58dc627d9518cb124	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x02baba480d5889c022e695ea803f4f917d87278d8ae1681a6b57d9b9b65a3a3af9f9ad43ae53c8162073325f4593e64697414d4dacc18c0c3a206a1d95a0751e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9124a77d94d2fcf9d151613c6ea593c36361e4520882d6812353b2824f81c273c6b0645fd0169577cca02a7de6ed8962988e9d9a82477a1fa2a66a4c19959b2a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xba0973ba4fe0884e3c60c00df20e117aec974a07c715be7bcb7d396f04029e419dfc2902401877cf61c6d961c9241c114090a83693bef71cff67de3da0df1059	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5256c5effbc013bb2eff2641b89e842e0341850ea8e1c2ff15012e98814b0fb53cd3757ad5848b098fde8f65ea1afcddb29ebc6c47621f3785cfc8b4b323a46c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6aef9e69add695948aa8bbe82830749a63b2797f5a97a402f74cd7d125db034a7f86bbff80fe1a35d72a97352be455ae0b5af57c951a6e23fba06790f336d5bf	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8d878ffd5b0c438ce82ecf1da2b089c024d3baad2e77eb4639592b5bcf5c387deca4528bff9d9d302685594d578789eb53a45839fa5853db331d352e636f38ae	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1636b70c096b503b402cc5425e3c25792afe4dd7fa4c8dcaba6500f61036ec6afbdc96fd0d1211a009eef8c49612d1fd5e78f65ffaf54fa76032432ae9fbc9a0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x943666d3ad2713264797a71464e1fa723fce048c16f05cfe9a3e45285236975a22f6cf620d234b80eab37ef58b9de27202504ac109437a290662f79f6600ae25	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf8915c5241e380737bb70bf07e0703233dea83ab9d31d1697c99cb03b6b6440d3be957fd36c2cf4f1103856a8136d09f21606f797a6fb117a3816d9979dcc395	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x60468f11c5365c52f6dd58e4108c0a11698e50d2103a6fb091f34517ed880ad6b8d400b01d119f3bef5c9af7f59f4e53182431d076b8d2a85aacc899cf20f1ce	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0c9f026c3af20383240790b39a20d335e0384ca2876cafe2cf11ad4248c745535255a6405e31b62e7aa01d41a115984d75adab8d97fd432b43941a17b685bd8f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd5f1850967909a8ad3fd3f982f63ad76a15be4fb6e1027e6d9e2cf651581095db6e49a670064244dc5b24b911dfdf20e566682bb93eead490efc3275db0502f5	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2318a1745f444ae29c7d2fa5e407b86b7697f8c1340e4d133c47a04b1fb5cfe312e2cdfbed553cbc880f58498da02072b8dca3ef5fd3169d97e6ed5db5156396	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5480bcb7f6552b383262a5fc54993bffc5f68b228f2b8c96bc0dcef312942b3575ae8fcfc18c070d01e7120fa1a09725fedc0f9842d820517e4d95fdcef8b4b1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x50715df95ae3ec5997bb81898633d8b8e527498b96844f6d36f44ee2d8da38a801372e73b0ea552a8382a2efc5045f796cf7518681bfd750661cadf08273e152	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x06123cd5f2a75ffa1e5b3627a30f52b23ec9f2b545cf63522503caeaa68b80cd6cc6ee4882a2300c5a43b44a8b0b6e90fc14f234a42fa74397a8b66470d73e3e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x411b27ddbb74eecd614f23fa21aff6e07adb9e0be2d18139b6fb3a3351e2496b59ec86ef4be364305e7ff17ce8669a83302389953e1fb7e45fd56612c5a3fa7c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1fa53d97adeb2b356a111204020109e506c528ccb7a118f0ed7b41459fec337cfc53e97cc32d6c031d8254884a1e4ffe736e3cc055dcb80eddae35d9a9fe1cd0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1cca599c762304f4132a91f6b7e8bc0b881c05f10bf1fc29fa2492eda9f1393ccb2ecc0c7954c9d1193c60414a02bc1cf27ca96c08389d5f7d0ea560307fe6b6	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5ed076d580df9758600a632c6fcd4132fbe6082555ef8f8fe5e6d4cd13448e11604c1644363304bfbe6084882d1803edb8a74ca169ff146524c9acf39db9840f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5acb8e9f6ac9fe0cb49c4098211a0666f55fbca48ab96dafe0f9c00e4d6154ee1d7897c2f7acff66d51d522a7e3a9eff295681865bd581bd2a92ad5de5f64732	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x96060c95811c4deb6b5387bc0a78279dde76f9cf151b0ed3383fd451cb5470ebc5bce3d4d8a316c0ecb83752567ae0ac5991aea1b671837926f9f4dd22509457	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x89302f98e5ce02b777f5d969e3c343d6cfbce0e0aabdc6c07717531251b8525d5b98e3ef6801989a202cd1d5e29275b3b5bc01584d42b2cffb262c49418aeecf	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7a25be54c1cece344226c2f2c90be69b9f2fc4ee9df41fa0f69a6d502d7f042e5c6137965016cb98ae84fd174deb39ecd4287fff7a5560d26292b4ac971fff6e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x85c722427736bb0394c9507383de35ef61551156cfd5b35ba83a7242a31af381d643c13bc015020473ac6b16274ce1896b1dc2bc959a93ed6f76227857e7851b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2b752cacf0f858a1501a4f0672b68b4801fd23619d5f51edf1ab1add0b3b9371432acd8231686e6294c2354305105cae02548ef49eaa32982f8d747ed9670d06	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x243c7d384b25d5559ea16c08f5da09bb05862efe7b8ee2a543ac6123a9a4fde6b51fb61cfcfac490751411905bda139fd6cabd9499e5127180b33476d69303c1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xda3c97f25e1bcd13f11e2adf58a0fbfde8b2f52e8dee2b483beb7d854eda90643bb55edaab3a803fadceed89196173eea0921a9593b0a488292c2cbe26348401	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57f4bb3dd2514a8bbb3b19a285a842ad9c9c221ee3c446d45ee9164974249335cb9ee0e7391a663e4c5915a7c20dfef30820d807d19d79cad1dac3769834d006	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1d90c180b8db5b7358f32ce69a3db1b1ef8367d7c1f47079de3813e485026e7388d45d3cc83f6b3a600c0a1a19f74a67d2485f7645adec2a4cbcdd516093ffb	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9f120a90651a6f26e8bbeb7e069147a4ad17672143f90d1c8f3e377cc77c8671373e8b7902bb3e5d1471d956eefedaeada57eb44c98e8e223b91a9831765ac96	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xad0677b6c1e61a0da37c3a1a0b48a99aa0fd72edf52e7255a94a15fe07c5ac40f3e1c8b3b774d91f6510b96dda7448763d5301b5ca8e43f722668544e43f697f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x13ebe046b1aa72521af01e5430fa169b59cf6335538dc394548c7e9adb33dd8ea0cd4c96f8f985886c33cfc4bfaed33a05aaa40aa0f023a1f7f321965ffcbb80	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb94309184abbd91b4baadec5451815e03fc17875a6a39ea28ccdcaac9dc60979baf38c43e71e237d0f634be0cfa3fee47c5e87c2837f4c39da4e4f7c09a2013e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbd0c6f6c9f89b4c651cd138398a21fa9554b8250a4d5087adf1e7fc11b2c2763533c5198f8ac69937b94da38702bb3094e638f4b8003ea6fcc511353fc81828	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b7663c04be92ed61b0e929e93a9f24d81bb006ab0546c2f21acbd00784cd1a1910bea59cd78aa96396cb12834b8e1c6d8ac64d057aad338e347094b91e7e2d2	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a29722a80d4bf8ecfe46c4714add09894e7d40c028d20a02daa46d1f575fc80bab2b5783e2086cb655447d5c7e3f52149dbf6d1d40ca8a260a756300e15d8e6	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a62d4bc1984074eb4fb4d3c4a03a3196bd3007b67f7c88aa9fbe8f480577762c73493c48034fd10e4896d292e35496637599e34792e66883adf5eb8dc622fad	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d0e3b34dd5b56c182df6bf6b2cb018825a6988d0bf2bab727c4d15d08287646a6f8801a0a0eb7e28685c3ca4b314929e8abd73a3cd576cfa3dceeba79794e5f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7673d0fe74cff6ad5deac858f31c241c4c99034b753ff4f70a60d22a89e441c2eeb7f8fa30407c2855e80800bb24c5e77d5914beb0a94482f47ab9b8c092f57b	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9097f6c55254ac31c276bfe879e0962b9c3083c07ae63c1b750831f4c42f89ceb54fe2c2dc916c2eefc85baee308f240523b4206d3dcc4e1c67f905f6bdd1af	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b828551ac90297cebf2397d855b2978d6830fbc474e52a723ea20a21a36b7963d2d723b3bef0b34cd0ed061818db4ca3557b8a220891a01d2db0cffec1bbaaf	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6017954c328167275b69a826fd177f8d92b8511f209b42a0454613a2c820958434b90a951f1fe2f77c86b830cf35619a95beb17ff69c22e9910beb99419ec9cc	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc054e1a821ba25f10c988020500d6a662d1b007af7d5f1adea622ce671e442b722a45d3bb020622659e3d6e52ddff74782893ab63c6ef2b96548db2559e70c16	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x73e269f08275894a4cdd6ac52a879f3856c2b0e83095f5513f37943f6660ee1096ff0233718ad5c839c57c8e2782a61a03d56cfc6b6cb2efc953e2fcf09faea1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e5b80c2c023e4361d960aedb939558b64fc27c922226fd6edf71e48140769f7803da82fd7e9e8603f268952767852a9abc38356baab1816deb32162de0d92b2	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x125734de9444e52ad0a8018d0148305fd38ab78eb9aeda64a18f757d224086ac7f693420159ad6ad575cfb71d9b0f95cd1aecac84a41c77d2279c70b2266072f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c327bb48688fdc627dbd140840dfc8d2cc3130b46879af3f88011a1ae9053b41dfe01edc7aa69c13f40d4c42e8fdf72ff57fcfe4bdb0b258575a8f62eb80d1c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa65b24b3366adb9badd085bfa98383a989ee92006ba5fcb8268554a10f5de177c6b675b633b60ee814a12e271ade5d1da82339caa8f3317291c92e0cd9558110	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6cc82cac4871a663a32e4a45c51c2711ca8a6a6f633ef4d8629d227ed4700e016b23358a30b997bd47d05689c426ba75c4687bf27ea3c5688b9674b2fdd0cd0f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7f5f3dd62a88549273be43a32f23c26d62353f7529bf09cd4c99fef4b993fb6dd7840cb47dc67c87f565d309daf1f232082d226afdd10354f4267c393707ddd	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xad126c119c9105a441f565ba022150fa9043367aff3202e08f09cb2352cfaeb0bb0a78f42967a8475ef21da6493c5c925cbb2d8942f759a745acfaa7aa9a2dd0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b167e3fd1747ef2d5f15fd64980090bbdd8322bd4566c6ce42679668e6d625e64fda91c8e38f6b54d5b17df853b9a8005a3b93cfd7502275628577131195f6f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3925a4c6ba91383eff528042ddc6811ddb9c232d62d0cb6f333bc5d211bc48d8f86af2b67dd998b93dfef5019d41efe2cd62fecdc21f9fcb387b80ff87218222	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8dce7dc57f02c8fc9fff19000d3d30ccebc63b1cee6133e4187d47227f146e9778d73cb8bfabc0eff93b15454fb89a392ede8f6b5c440a9cb71c2b580bf454bb	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8747c91e95309fc5fe1affcedee7023d5b6880bd0f167cafbb53c085935a60117551f3806cc89c52b9103c5fd838ba5d590944fa74ca150cc208a49602534bbb	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f3bad222151c86daf9962b2561d798763c2d831984c8c7049d527353b697017681071c7f03faa5c4ff77a7c10a22629e6477cafdc57625b9e22ab902e9544a9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x000f3830b5d4da6256267ca46d0967200e9541cedd6e22b6f27d51af7f26f56651db190f09ed91899b5ad2a601037ca90126e47ed787a98688381597ee0d93fd	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18e4cbe9a7b57c535725ff98370ec5b78fc98b1f22cc95f77faf2e3ae1f56ebc48db3b715ee614e7e1660c3c3f2ad002a72800c0f47ab6268d231a6908625564	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608897815000000	1609502615000000	1671969815000000	1703505815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe441c08222a9b8693a14a8310858c6cad224b1db893fd9115f4387cd099d8f20185d0a6758adcc54be268daa1ac06bf9b4e87df65a1b80cd27b80e3eb58b54d0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1609502315000000	1610107115000000	1672574315000000	1704110315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x13fa03fc59a26a86962bc1f6f24ea88458396ca3f28e616fcbd8525fded42ad54083cf0c76168e10d1e344614f03bed51368a2299772a397b86af3e99e571300	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610106815000000	1610711615000000	1673178815000000	1704714815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa40300a24e56339aed3e129f671f5f001b8bd5be0b5fc8c2f941c9986493a1a34e07c2e37a953e4b69186ad6a601325ac66b5b0d7d16165d089f5b8b3b030710	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1610711315000000	1611316115000000	1673783315000000	1705319315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x81723dc5c363d561f628b9a2d250db417c5f75ba0b40c7e55dc7a5523cdce1b15a32a2c00b86008bc22c02a685ca0548a2c3b6433ae8b14bd004d4ea1e6b567f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611315815000000	1611920615000000	1674387815000000	1705923815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1ce9429ee37c997262476c8f90c7ebcc3f96e01fa6bb654cc755a131b9d499614465d30e5e205f326f9c96e7d1dfab8dc908fab9457025c1d27713adf6560965	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1611920315000000	1612525115000000	1674992315000000	1706528315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe28591702c7a240eec7c6ab3f950ae6e92cc200a79333228057058293bec9427d5d406b51179f9a7a7aa2fc11633fd9fca88d5b0b65be5a1ae7fc6c8284b94b9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1612524815000000	1613129615000000	1675596815000000	1707132815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9dae4dbfc7580bd53b204b355b897b53e4a1c0e595fbe097d8bc213161acafa08c583826b2087c6270f88a0fbbcf3101c8543532c6e9f0a8d4a7dbb431fca1c7	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613129315000000	1613734115000000	1676201315000000	1707737315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x874865b76f2273219fead4d8f7085e35fb68c0771077aaf514ea1c2ddf4f4a2ab19896bf2f3839cf45bb90ab316faaf99544177ad445d3747ba11a5d44d83578	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1613733815000000	1614338615000000	1676805815000000	1708341815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18f0c8f1d935c258d68589ed313c850f06014d2e1c5359adc952a90668cfb1b06ae6379512f1465e67b58773fb03412dd569e4444f40ce26dd0e5e18b70b4d4c	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614338315000000	1614943115000000	1677410315000000	1708946315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdcf78378160cad917dc865124d19e78d3d20150565c6ff9ea2f19a7e4bf57e5dc9b3ad12a688c0b9b554d32adcdca6ea6a32ae50895d4a3233419a488345e3e7	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1614942815000000	1615547615000000	1678014815000000	1709550815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe7f451deed099d22b722736e10f2639d44ec46ebff513db824e6fe3a6e9b9064bd8dd91d3be03794ad663bec27a4aef2736c766a74fbc43b8b199ed1c8c4d781	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1615547315000000	1616152115000000	1678619315000000	1710155315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf033c181903c0863e27248d36ae427a7298acde606ca2618be81819a984ffd6922fda2e65f5c1cb0c7f231c3f742ee556348c9e50b301d5f0b484d6b569da529	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616151815000000	1616756615000000	1679223815000000	1710759815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa02e9d70daed2c2daabe2453fed4db80af0a5216fbd6668015e2211b21a9ffffaf76f228cab833ad763e0ad19098d4ec5e84af70d4c0da5a4229d47665e1b2c0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1616756315000000	1617361115000000	1679828315000000	1711364315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x21c19cef16179a9c5ee3359c02955026a1179a64be99e72ba241795e92928bcef55d1d6bac8d9614b4d1104f149085a0827059465208011fade932e588fddcbd	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617360815000000	1617965615000000	1680432815000000	1711968815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb816d72c73eb89951806d08dff23fea724dae80c3693e0a78b5a0572a3e6d25f932bf2bf3797f5235512cd8ce7367dd4dbdb096ae11ce802dfe68b25985002ed	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1617965315000000	1618570115000000	1681037315000000	1712573315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfa445cae5b92ba7c7907c98d9c8bdefea1e302e850544cbe9d61e69f403d47f42010324018f429b392ab933711ee6973a4480d01ea26a1af5d5944b6035d174a	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1618569815000000	1619174615000000	1681641815000000	1713177815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x82d35e90d866180e4f36ce4a289bb94ae2ffc9a2f6870891b0753b85f24cf522f16051502a05872bddd2cfd238e9903751fbc3ead89317edff1360c4232f9135	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619174315000000	1619779115000000	1682246315000000	1713782315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7de8b9a620d1dbb502d9c7580c8c0b8eb27ee1525823e71fbda0431edea144ea62191f6f6f105382e4e12c439f47b0997d8ceefb7864051bf0ba44c9bf8544eb	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1619778815000000	1620383615000000	1682850815000000	1714386815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x19d6dded4dac2d10ea80cf55ff4768476eedeb7e230fad121bafc218e458d5248a4bf046a7147c4c2191ec3b9227af3f8a3f073e3941a2bb4dd8325c2c761e00	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620383315000000	1620988115000000	1683455315000000	1714991315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb9a14c62ed3f866dd5ceb1dfa84084184d5f1fdab768698d6b321900b6d5a11b391286891dc96f0c2fe0d1e23a0b449c7e061978ba0bc39080676a4450d91c19	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1620987815000000	1621592615000000	1684059815000000	1715595815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7a7d8d9c90e5dd719e0456310494c090f32e17fcfa65c14b6d5f144b479c468fd4798adebe0d7eaf32aee21687cb54c13b61423b75bf7266059e80a20e4b90bc	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1621592315000000	1622197115000000	1684664315000000	1716200315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x55defb01bc238289781743f6ffad7c06f6a352fb4bdb6e73443bec406ac70f1dec48ff3670869845037d5bd84a78fc749c0221bf1263a48596898e41a6b344b0	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622196815000000	1622801615000000	1685268815000000	1716804815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3f6309eda207b7c5558414fb7c2e30d26fae9b52885f2c85756d53b24633c45425f039a58dbf557def29af6a59a0f11cf760e9e8a53afd8a97b341ab9297b4a9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1622801315000000	1623406115000000	1685873315000000	1717409315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe862fdd34847be6e0cf15445176333906f937648052d320cd0a75144d8294b529736ad9635945c7095de803d7298f48333919ca27c656069c32eff789d04b9ba	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1623405815000000	1624010615000000	1686477815000000	1718013815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0bc8c71aac3b5a5ce8bcd0406083fc3781dde4c1e542e1e2a0840583da7cba1d70bb6c2ee47c5786d380d70a3eff1623a8499834317ea85d0abf2f7503910c44	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624010315000000	1624615115000000	1687082315000000	1718618315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb6d71254679445e75063cd56287f723ba4264681f32fb53278a003a193a69a15493ab3fadd5475f6c69567bca731eabd50ae70857cacb427096d43664eeb88b3	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1624614815000000	1625219615000000	1687686815000000	1719222815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcb6a66403a06ed719b5ae6a72c5e8ef73a296fbcf59d0704b01b59d045437bd1d8fe9d3f6ee377cfffd6e5cf6e416e28e2c40f50bc79efe0aec686613cf28eee	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625219315000000	1625824115000000	1688291315000000	1719827315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x38869cfd29563ee5cd6648176a10dcc408954da8b29fd4527515b7eb387746c295c68c0b2aac6ada45d9b7a4cc83bec2f85424e636d0ddf0a2ea4fadf9212929	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1625823815000000	1626428615000000	1688895815000000	1720431815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3df4c79f90e6f13a4ef0a95d96c91b9404535fb30635aa4a772d2b5aaa0b32013fb282572316eb67f19b7d4724f43b43a1167ad06ba6c3a414b597c8e208ac2e	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1626428315000000	1627033115000000	1689500315000000	1721036315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xde49d49f238e9b857620a06151fed9e0950bfae3ec6953d65c9f7363e4b83f7fd81fcc4c0bd8eb8da3eaf6599441355a762db7e3999cf899bd07d7a4eeb170b6	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1627032815000000	1627637615000000	1690104815000000	1721640815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7469ed0edb2b9f391b76240ea4dae1c92e368339253c2ff8557a201888b093bab73c8b57b42795428087ef863b00f0ad7dd57e58fd5f2e39d3294be117a09c5f	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1608293615000000	1670760815000000	1702296815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1608293315000000	1608898115000000	1671365315000000	1702901315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1607688815000000	1610108015000000	1670760815000000	\\xc06cad01d1590fe81913b26b04e234786d30592952b070621eadd61436795747	\\x8563133cb924cab4c6ce2c9301cd3899fdb892a8e64764efd5252ed66e11e62d81f565b302278e0e2f78c585272d58d93c3f5cb5ef543b8b9390dbab7abe1a08
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	http://localhost:8081/
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
1	pbkdf2_sha256$216000$sjKIBiXhaHNM$EBVAnO1aqmXz/tWE/WUpHhr6nCp27OwUotynTPPFd/I=	\N	f	Bank				f	t	2020-12-11 13:13:40.447667+01
3	pbkdf2_sha256$216000$iLSAhyfhSZSY$i5IdbLobug+M3lcYWBonxt2MLoqukkBbLel+DXmlvMw=	\N	f	Tor				f	t	2020-12-11 13:13:40.61543+01
4	pbkdf2_sha256$216000$oRjLZ8QEbOet$eUteQNyURsHHTaG1E1iqh6pzGNRqspBLbAMIj3VdpRI=	\N	f	GNUnet				f	t	2020-12-11 13:13:40.694491+01
5	pbkdf2_sha256$216000$Q1Zxn7iq9c5m$/WNuVch896rj04PRG9q9paXthd0k9Uj9XtoT0Tu9lVM=	\N	f	Taler				f	t	2020-12-11 13:13:40.774105+01
6	pbkdf2_sha256$216000$TQ9Dfd8ZZPxz$Jh5VI2UnrasrGMfPF6Vz71PAKaGeaRVCqeRocAp9H4M=	\N	f	FSF				f	t	2020-12-11 13:13:40.857313+01
7	pbkdf2_sha256$216000$TLznruYDn5o6$8LA6KwprwXOcatmMmbqjFirrMMrCiK4vVuAUeKx9pmY=	\N	f	Tutorial				f	t	2020-12-11 13:13:40.939781+01
8	pbkdf2_sha256$216000$9ggwW0WfTBZ0$uP1d49Yrx8GuggS/0Dzb7Kib9/M9Kq5hfgscEsPn090=	\N	f	Survey				f	t	2020-12-11 13:13:41.021597+01
9	pbkdf2_sha256$216000$FLcxADXZgi7Y$b8bd0i+PvkZYnLYUb0ykac5g5lEufHrCEdWLS/Q5L3M=	\N	f	42				f	t	2020-12-11 13:13:41.514745+01
10	pbkdf2_sha256$216000$oogMskyARgba$nZTFlx91EBiOHB5vRfVCDeGqU7jJx8eysK1xUfswyZU=	\N	f	43				f	t	2020-12-11 13:13:41.979777+01
2	pbkdf2_sha256$216000$50EjLM0phF2A$wA7r0B1G3Ab5+UI7ixyKjqPb2Ns9sY3xmWcU6qGs21E=	\N	f	Exchange				f	t	2020-12-11 13:13:40.53648+01
11	pbkdf2_sha256$216000$9xywk6XxCujp$LXB0NZZmaZmU90njHE4w7BsKvuz4odUhdKu0J9K4NyU=	\N	f	testuser-VPwFnxed				f	t	2020-12-11 13:13:43.697894+01
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
1	\\x15cd172ff9232ffc8792383d0fae13eeaaf3bc40676928bf9b566af80224fd727cdadd3cd3cb1774de2e577596a84f9819fc4e791deca825383fa2a9fd06ee26	\\x81a3f987bbe753c3489545267c20ab20ee7d6a9ab0899f0f09ad8fde2b31cd34493e5fdafb39ed658245455ab9750bea39e9458c804e75c98e173f0471b9ce0e
2	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x2b929aa329dd4b8e0d92218da3ee8f1b34d4689e371cdf33f298829cf650f25a5cba63ca4ce072a79537905d585c14331cbada5542b8c5ef277d920c983c6807
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x1e27249469d3347ecd62d4dcc134b84534d2e91b40838384899b570ba774a0c3d15612381563b57e0187e4b34b5e73ba8c618879c85d3be83b146e84d35d73c3	\\x00800003dad28d85a446edf2e9283545d201423f7b807a5875915da15fb3af9df6a5fbd4214b99b31c7b1917fd93619d6f783253b4138de5c98dc14f9fd4448e52148cd525c8b6d9c7236909f65938a3270ea35f5e79f37db5f246b3fc4960c95120427c84fe4d2f560da953410a5c2682cf0e618bcf3bc2c19e316d45ab2249fd37e383010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x6b0de2e2b0f1d161d902591db53bdd1599e0a2ddad6c8e55e09ccbe3be5290a622c23425b3ec5798df832f75e5450b8e9781f477b24be65e395c05e9ea4ce807	1610106815000000	1610711615000000	1673178815000000	1704714815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66d54201ee38e240d8fc7cc717f0c72d3ae58fb9eaf25ebfb3873cfdcd037e8b67dbfe1ca028cdfe7f8ff59f8be8d9bcf48d713a5225371b62f68e069874bb89	\\x00800003ba0be2bf982776f2c8c359f608ff5881e19716238ddd5dfe57d46e5a8f9d009f4577cab278289f4df8d9aa343f2f82b179b77cd4f1015c5a119e0df7cb5e9765b6189f2569f47aa948e628e11f65206294c38f9bc54a187142c708f2b8cd02405b541fcab8acbaf30cc289285e1aaba6eaa9081f732973c2262425850046fa8b010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xe952f23aca40222d55013f23c6cc0fdd9dd443de0727fd78f0608884934f6559c728484ea2262ced489eb4ad32400438e6a5f073af459db443b6811f774aa700	1608293315000000	1608898115000000	1671365315000000	1702901315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c89d38a79db5e166a1ac12b8b13f841f22e8141b632df2464ebdca8b8ed050123de0b93ad3e12b6481184d7ab291dbe038b760ba0b43cd24bcdf04945b3052c	\\x00800003e003b6d6e9135f99b05e9f6342d3a3af2c7f301deb87d0ababaff35bc3b31576bc47bfd87f2c93037ae198800008abf68eb2aa9b428b181b75e49426d0c445a89fa07a875edb3c1ab36f384ace1b6438f8f94ce5ca419a77b63402b123e181fd3a413deffbc7f34b0f5509f7869d2e1f692f6b983b1f011c436a45990eb04143010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x26575e886bfd6af53fea1edd9a08704028f2b2330f693aed7dd4559d9608a936b0031dbeaf8bbcaca9de77ad09c69c337dafe017ec2835f1f76b6301fc9b8f0a	1609502315000000	1610107115000000	1672574315000000	1704110315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7b0efaf2e440c85fecb226b6c17e8b584d67b6bc8cb57396790b17c7be0d6e8e02b7531d9c406be089793917ee6782bf3c4bee95cbbe24cdd9be1232470e543	\\x00800003e3235a069535c37c954942223280acb106e76694261dda918a7d8af68fcc1cf959ea94e95d4e6ea7962212ad7787845ab668cdc9e332995caecaff82041e6a8e3fbfa0ff65cc1b9cd0ac511aa45870510375363b1c68e25eb3a5523cef0e600124c5f0693b7f0fe6c594623cfc914da487efc182ce4d717e76cc24e80f91e2dd010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x6319a71f43ff60bb46105a406e3b1cb4af82a74687908788d0afcb97a87cba8ba4eeab86b3784c0c54dbba042ebebf328dab8b8fa20a394c7602d375548f6205	1607688815000000	1608293615000000	1670760815000000	1702296815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30825424d236ef83776af7455aedf9dfa65dd295a7ed2ddcb7349fbbf1b7327cffce12bb2608e6a67cb26b63692e5ad4a5073528dfd0ba3061ca28e694300c5a	\\x00800003ddb81ee694c8a14da26e237d7b7f2fbe7801d49675042dbe69849bbe91ce4d2e654ff886dcd2100c208302b2fde5ad24f988d89eaff60a1e38237c9e3b667d123feb3c24ef733bd94e1b66f360c4a629feaa402551c11b94758efd98b95721f77d6dfb880d6c372959d402574836636f2846688f08c4ac2282645a6a3c06fa77010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x730b5c83c38b25a51d17211f519377ecf3820778dd57e304e6e510fdb84dd9d8b7c0a95658fc862478160a49a4fa6ace9e6c6deaafea511432905461c099aa00	1608897815000000	1609502615000000	1671969815000000	1703505815000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61bec86cd9c68f2c44fe323f06b9536366eb99259e4a8f2858045389ed8731667b828a66ef7ed6c99285716bfc937a2dff93a21580a8b8341a7a9131537f466f	\\x00800003a3b69838b0c12c9993b7accea1ae17520fe5a5ef9c48335875b6fae46914ebadfd055420e856f377ebf991e5970ee98006343d2c0c407fd8fdf917d59434631dadba4bdbc5e9b6cb196f048a6c68d05700783a3d5f3d427199793f5c5ea6fb40967d53f761ee191888ca6d8aaaffd87c233d1e417ce61b2335bbd67a77a6de17010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x2e554c1dabad3bc4647eebe7eaf5a30748220bc2328618ad62c18c5690c43e1fb7935f2d8e7f7a748587607d6757bedb9303d54844cc571ca47df24726594709	1610106815000000	1610711615000000	1673178815000000	1704714815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa9ebd4fffc23e42b677d165ee80dc8e6ea4ff24c3438fc790f89f1548fd3862eacd956f17336f1adb90cd5c6a52ed70b14fed13f2c0844051bcccaa631f40f5	\\x00800003a039b3d6e675db615a3bb3d58152719131ca43d80f1869458c415eeda8e497652306f4516610334dfba1cfef075ff1790f235b3a28bc7ed7548743ef5cb9aede35c287d646910cd8d22a70f1b842faf93b83f03b49f0b587fa040c182e9fd3b3f48405cc8eae25693e1bea372af876609860ee1fafe58e9a06f0dff859896fad010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x41708b75d5da767a8361748f3d58d487f19aaa6f9c7d7cc3d2b87ac820369cb48b6200d8310a6eea17fee79e1e1666a5d841bd3101c91cd9379b58162a9a610a	1608293315000000	1608898115000000	1671365315000000	1702901315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a6c4f3a2585fc1b6a7169ee9e07743195dabfc4ec1ea38d91deaec3308632225f1af5b2c85eb132c524f62555c71ada740297d42077b35a22f36e64f929ae45	\\x00800003c62f1e31b35eb41b495a62d1a2db6a6ebdc229aa6792be5ef6acae68b8fde17aa04a543514f2757712a4c90f513bf48ca428252039dba71fff785fc8c96e3be2dcb0b5b67e062bfef7c691a6baf7707808c7bc52713694367900b404b73c77cb77ca2cc0c447f219dcb245893688111d78b1a30ee4789c8e9824460d2c864355010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x5befb0de9c5532191dbbb7c7a48cb74727b667b1834d5a57823546869c0f16a47b08bc4a6c8b342f9171855d6fa6685090cdc2baf8625bf54692d7ef09c28b06	1609502315000000	1610107115000000	1672574315000000	1704110315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e6025b653fa19b9e4a9c092115a259b19586a527c0d97faae77cf00eedcf901d07478e288eb14eda76e2b6fcae8c0c01f5f4bc6002aa75a01058a0cbe13aded	\\x00800003b887ddf00077469f74c2202386b73a60d408c09d833d3cc12afabea9c0f20ea9af9156bbe9547b47388feb434e8ecaf4c77b0028473b29cdbd9427f0e8a74053700068d644fdf97b497b4fc95be9ddb8a9d3c8d71758cba21224af550966509979728d9b6679cf3ada604059e11f4e0397cc9c779bb9b0ecbe6ab279809d5f0b010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xaf7508011d3a9c395424302f1a7d264c94b95558f5ea36bbe1bdeccf457a8497ee434d1ffef76a23f9f331559c6294d4ed23da2f377371457aa7b1054ac4630c	1607688815000000	1608293615000000	1670760815000000	1702296815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53c5df43261c179709c3a9e7cebfa8dd4c2e75198dd862bb25834eb92bce57cc8d99fd43acb53cbefeb310be3a9b71910b063e0c8d2983e368217b10c2af040a	\\x008000039ef99a675e39f45b03df38e0d4c112256efa746bb47dfe8578b54e4df44f5c3431efbb32038ebe10c26b4bcf95fbb6580f8c31ec1914b502f1bcf8a9cdab422e13126de2bba5cc46a75d1603540718ea403d6ea7d2dabcd0b5b91b1f69ed17d56cca62b6aff1b19845ca5c24c5a3b26058d5b18fded98ba599a577aca2718a43010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x665574bf6bc170d2c41a6084ed7da46c52d6a888d5284fbc29c9c5b01f9eeeb48512edf2638c1c341753b0f11efa9e6fd56408f33f1f5e02a2b0fe7a9e5d3007	1608897815000000	1609502615000000	1671969815000000	1703505815000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaacac79d5a11ea4c17f5ee9ef30e8a152ed9bcb8e1de04f15012811b29ec707f110cb24dec57b73573a661395e9b75c201ab0022b3cd9db5b4e54ae7a78da87d	\\x00800003bfbb00a510b6e216fc457d53540878da453e19a7840ced0d19d28145a00f1823bc83648a8124e6af0c7b361d2059963c968bc70789745ce8b050982987419925eb9965e9c1c075179794e058d0836c5a1b6e814858f5c8ca9732e88744e9e34dcc4c1aa646a85849b5920b85703c8c4a288e5795da5e6b6c5e049d17c601c27f010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xf1afc4af4010694a25a9e6cced264da3097848102f0c37dce8adeca49f494737f305c36ee7a0321e9996e96a8bfc774e9022de5e04aee74c23b7680e36561702	1610106815000000	1610711615000000	1673178815000000	1704714815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x767eb15f94cc5de02e37e6c76b0dcd332c0f22f23dbe61d1c49b89e1d3070884eef8c1046568312ce0d95245c0f9bd2a4e4bcc570fc147672c27a67492661a62	\\x00800003a1da61736af44b785c9f338f373bed0fd9487befb51cb54093cd31e9ebb36254b016c590f959d64d59d2ceda172c75a4a72601e346280a389b4f027c5a42acbfb7bd276d06b72cc0a2d80ec2cdd4a4a95f5f48d18d5a02cf3c03838a83b3c014ef0214afbfbd7d303f71d13cd7648fee4fdf85fe5a906f666fcaad3e54938873010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x80ca5f684d8bdf8124d8eb294f9f8af1d82c46f97d50906b3b445955c2daacddcb4afdfe072e5c404167fbb49876c329a9ec9a58f865a9d2c06631e234b5450e	1608293315000000	1608898115000000	1671365315000000	1702901315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd17f99d10320821b1704b078d9550496464a76139743bece6d5f2ea1c23a02bd9f21c9d209fb60a041db6f758faa9cf41a5339da6435526e8b23c2fb51591420	\\x00800003f89d93ad72e59e75980a57a10da346d8db36174a6c09ccda60fd9af1db3c0c8a17f7bf61da8fe1c6fa657ddf3aa54911d2a4e33aa7f0f72f429e50aa8d9f5d4070e014c32ca66e4fd2b798b6ffb50047c60a478fe616d35a2ce8a496103f9ab0a42227388773051e2441ffad0dddfe20b2dac89f04c8b736d83bd3eaaa03b6f5010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x5a43212d62dc21ca352b2386d4cf0bb7d02debea581498f8964f599ff076d48fed8f2e9b966487ab78af0a5d4cea235bed5eb1071099d501fb45150a92f56601	1609502315000000	1610107115000000	1672574315000000	1704110315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15cd172ff9232ffc8792383d0fae13eeaaf3bc40676928bf9b566af80224fd727cdadd3cd3cb1774de2e577596a84f9819fc4e791deca825383fa2a9fd06ee26	\\x00800003c8d7ce187531c8e42d9fd786ceafb9b9fde83575853801c83fcd100c296b85be5858990b20fa38447047c05cb476757ab210fc88398c1d31e64933c8513f123f38fa7c8d996d38b57d4b1216638e1408a41720513cc2b4ec8d3eca8040f3c100f9f4802604b0b75a7e21bcc33fa742cac2c6467a18526ef74a324293c0254fed010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x9be68d5277286bddd3491a2e2bcd9ba4e66bc9eade95966be3511019a5b225e2adb121ea4d6c6a7ce8e97cf7534111cd79378014f188d29ca4a3a882a79ca902	1607688815000000	1608293615000000	1670760815000000	1702296815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3922ea2d31864408d7406878e79d7f72c7168b5ef54f7ac4bf21f51089873ea101aa010abeb72dbb89e86b21a871bcda7e16619aa1704c1ba34bb7fc53cbd101	\\x00800003f6627d415dc8ede6a1a0f85f6b721032600cf76b77068e3698d1abc564c3a79fdb41e293170ed2f3c5801fff79bda66a7735922363d123747dae947f3ad1192ae134fc43803efdc2623d076a6c9313c01760b074fd11790ac9c76c0a16b284033209028130a2bb2c03e0a83635d7e08c9b52a111c2a6b791938fc77ad6bfa9d1010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x6bfb848f206f8d709398ed58b970353de13d7abef4821e9c72a46fff93d02e932f393e3109366016b413bda9bbcaa16a7d09e4734ed499d5a631f95358418502	1608897815000000	1609502615000000	1671969815000000	1703505815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf5cbdd38d1267d9dda34d813c5da67a1e200dfb38e7f5471287f3a11c8e408f83e519aff1f71af7cd1bdb2747bfc8bcf0746e1f59430540fda062675b1d7307	\\x00800003a2a9926781484bfea9f207b76b6c593bbfcc286a91986a2442a45bbf1510f91bd645f9dae2b5b3363fccab18d1e66a5641acdb23afb8393c27eb200d79af74bebd609ca59e8ccbf48c58cdf22457b98b6d088f50ec0b12a3bc71a815f977b5394537f7ecb6635ff0eaf440fef958ded0fff91a61052a64c8b341a8ef0143b9ed010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xb654c0519b8debf0a482e11cb68675df9971399011f9b382eee9196299ff2c7618387b5280d74dfdf997d4cc697fc3dd1b485432d8f02c54be613950169cf804	1610106815000000	1610711615000000	1673178815000000	1704714815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb5b14b3451a36e529a06dc3b3e94907e63607d6db1f290717d6a457ad766fabda7a72574135e5a5fd6991ab3901551ab567237b33b832de04aaec478f8e6808e	\\x00800003c9ab553dad2183ad7de3183a9c3f77f943bc9e9f183d85cde06596af108f4d302b41c26a0cafb031b582964172993281f8ba622a0e7a6c96903a09ba8d0c8bfe0b4fc46c5bdfd0596728c9d126ba4ac301e8782c676766c163a20d4551d37f2603512e06389cd2b7f9d55a50c657b73e31111eb0097126efb4172493429b04d5010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x845c150d2eb49e24d2a26f8297d75f33ac5408a3d0a216ea5221f84aa41ea50575979428270418b4bb7d5010f16f1cdc6f77f38f0730c3c22a5183972816f609	1608293315000000	1608898115000000	1671365315000000	1702901315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc797ba8f1652f2e1dd013393bde4c9ed8e79b8995f4bc2740fa9aa2a8057c69bd4c5e7a42666111bfa38dedb32e3f2f816096fb6ca4bcc760e8ba447885d0c80	\\x00800003cd20934be044dbb69dcfd3ce1ff0d960ad75c521275b413a9981ff41171469f370d37c3bf9685c7df11661d7861c0e1130b7f6176e3483cf95fb8b820c3217a1208502d6faa67d53c436170e0fc8474bc70a33ead4a68ea4ebf3764dc7b276d1ec9bd83e56321b91163c237330269844bbe28afe111b6d814b936b87839b32db010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x81d89f7421e7b3fc0ae4dce324e1c396ce74fb772f03a30dbb4df5bda7872dfac8335ac99839dfc202b197661c8839b9e17623866ff6dd2dde7d685d58d97e0a	1609502315000000	1610107115000000	1672574315000000	1704110315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd603de1aa6e2e6057fa2366ffef8891e79264d4e7131833d13b3c5114dd860aacea9d375083754764c1c1ef100c97839baed9c5cc5418ca70f6b054d26e6b0b8	\\x00800003a835c9994e8ec9bc67e6f76f1b965736d5f05a12825709f838ea885c9fa3eef2f3ba90d39918d97694c5e337971532d26a2bf89bd0e02384440af0ef238e18017ab7ae806d418e8d65957451043796848e9eaa21214b606e31df61a02a3d01457575982221f7ecfc18dbad84cedb2cd7afd3e2f53b6beaf18c43c23316ee4931010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xe752c6a58db931ce659c1d8367f2c0d9906c004f3398430faa429792b65b9f071c8bd7c399bbea2c24696b33661688d3bb952617cdb4d849b4a01d45cc7af80c	1607688815000000	1608293615000000	1670760815000000	1702296815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf409fb626e27ce7807ce4e0b8b2223a88e985015518c1cb6f5d39a1635676baff8fa62771cf6192738a5dc3fbe4297115e497e2217d43f12362364c83e246634	\\x00800003ae1d59b7d4db39a027272d9cbed71096eb788ba1721b040b00fec85cdc6b99fbefafa7f6f82d2bd5d70eb86122968802cf838ea12bcd0256495691dea750f55ec2b15d0afaf65563974148c139bf4c3a7464c3907be4e80cc9c74c06af540865f658776069f9b947ae6e5ac00a94d9db1b531a55697006daa3ff1544abf0f0cf010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x2faf4960b55ec57f295a484ba9e2b3c2449d3c7f07af5a0ae5e6c42161ab5ad9fe402e6aa6a03e0d539e2b9c5bb8dd3fd5a849ad9e8de4ddc0fcfa7ee5ff6e0b	1608897815000000	1609502615000000	1671969815000000	1703505815000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c22dd922738cb90cf9316764fa3da684cfeaeb2f133a01aa57c31d4cb7cca176986c3deebf401c248a32a55af0c8eb917826b0599252756628e2a442fe447cf	\\x00800003a5a1d659a4bf14bef729e4c61099149b5d392f31657de194e026af46f8a8077358431aa402825d2d724d15373700e5f87fc28a73e08fb442598b77fd28e9bd3adce266e6c252d0d05929253120d56f1dcf28a281ea3928a0f3cbac53d03862ea2e24d00462e979b142f8657eaf1e2646e6585a54993038740c6d3fe5fdc6f1c3010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xec594637ed45fbe83297c25e6b899728f00057f77804a2fa08fa2e370b10c160cb91085aca05e504f303323e40cc9104ab1bbcb9273b5f3621f2e78f1fdc2b00	1610106815000000	1610711615000000	1673178815000000	1704714815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x782c7f8d90cb5970a3f73838cc45b6c24b70eb140043c40558c052cb979eaa0d3fdc710582ebed130d0a7ca32a90ba178682370eafd9d9222c1694f56d4d4aff	\\x00800003ce1456c3545437754ebb5f2febfd1da9e62c8265b9f35bcb7583d3fd7eee71044e32e828a24f3b924703e61d51b1e820a24703dd7f333e3a3550bc6ade561caa5c3eba18a5cae91aac722ec7f7b3b49de3988283fcfd014387e005f168e807dcaad61bb5885ef6d81dcb5cb77a4fe7dc99c27957712e32ddc9172bc46e2f5b99010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x7591b8dec0a97892df71533a7dee7e43ae64cdf303c9964790570f18df15391edc912b613e17f5e8436ee5fea5ea6f6ed7e05dbe25823479dd07d020a6ddaa00	1608293315000000	1608898115000000	1671365315000000	1702901315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4d9f19d5d3424cf31c60e7f0167dfe1e4bef132dfec811c88297a10eb806e2a2a1a3ef9bb121c67b26e93faa8c6dfb6459062828c5d24bca38edd2aa45e9b64f	\\x00800003ad94cf0d160442103f4ba3f203778d3d6d841f846f6bb9c07445ce686e98845cf34aa4b948642b9109d4d194a7cfbcbfa0ce737563d61fe2cf549033a9cff339658c074e8b73c6a5e46bd45e9f190d07c24f4546046b5007768fd4e64341850992e561f220e45df69faf052f07fc528669e466fa7e4515894be923a8ce163d49010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x20163b23e55116a62b307a792144c63deedf3609830474d18059703438ac0eeb1a37deb27f6c936d834440a20ccdc3663c45dad2f26dfed1a52fa198abf23601	1609502315000000	1610107115000000	1672574315000000	1704110315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3591f89aede6cf4aaa845ace772f0f7a5ff6e837b6c64bd9a9b163e4368486ab0747c36c426ec5311cdf84dc57391c1954c903b8395330b4a64a4d16ae3bfc5b	\\x00800003ba98e0c17c6b790743d4b6239d32df3cabdc00a2c78dca059d24ea5732fdf64e7b98fb1f9946783fb8527b3d59c310c0f7e275e1200cd89638e9245bc49d7e6f400bf80274187521ce7346c47afb63f3579e90119b3814783c2af18b3e75e2dff02475e20926a83b4ed8451c75289f3d9626f1b6f03e8411cd5535c2835f7c75010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xe6cc87930f3818ff2fa9037c0c1a1a376e14e0a3d550f423c75d67e1ff35b89b87ddec924ebcb3c41b314d80e296cfe73b5e74c096f41ba58d952e589c701e02	1607688815000000	1608293615000000	1670760815000000	1702296815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x367c7c6fd3358be16eac71f5e99aed114a56556b38dadeb13812d9eb08fcadda0de12a2d0d192fdf9a94f530c53b320df12597a54433ff4b7fc6068df32868aa	\\x00800003e7b46455bdd7cdc512fee38d17ca2ce82d249cfa762ae7b5df32655c214fc4f94809e2c893d42f25afdc4520b8f4b65bada3f80499cdf00b1c3ac3c1dcdbc72d980636fe5ba262dbbb133508c56f19170450a428911c2b61e9aa2258b11d007dc42507a2976f87afe62e73ba509c9fb1624e0fedb41c6de728b865129083f2e7010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x18977b1b8cdfbf73eac84c428f11549c9f14f8b82fa24de6d4215ed9e88f51cc6c71225538e2bfdd976eb7728e01f0f12d01b054cb6e12cfce4e14af27d83103	1608897815000000	1609502615000000	1671969815000000	1703505815000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x13fa03fc59a26a86962bc1f6f24ea88458396ca3f28e616fcbd8525fded42ad54083cf0c76168e10d1e344614f03bed51368a2299772a397b86af3e99e571300	\\x00800003b8934a44e441d031e03e2f11700124e73fdd4116aec3f6e171ebe0f984c9f9986ee62938d453ab20e1f5fc557a6ba45728505757cc1c961ee8dc84a800d7845281988f20204513aecb6b1eedc90f9e27f34114f8f4398c3e003415f7bba39b1118f4c9cc38166a88b275bfda7c136a4c71796a9c54d38f1ad6560e3174c360eb010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xb3ba8b9b0d2e76786e7d1be5fb01d6581b9616345836d4516c43fc88c7c4ed3cf876d4ab6bee05d8a1c7e1af18d591e8811e3e1dab15e95cc7594a378365910e	1610106815000000	1610711615000000	1673178815000000	1704714815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\x00800003e8b700966b9168cc0ca211fae3cbaf9b0b6e169ebbaabe47771f8fe71e4e6443d4f58db5b403b4d028d54a1c8f59ccd0ddcef01ae29a9726674f1dbee4a2cf100fc56bb2882eef23fd065530874376f2ab0bcc49e43a9ad7f30ee633763da0f0de34b8dd2691cb3b7ba8831fa3e146b744a2995c5d5df735c6414117307512d5010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xfb4530ccd2f376a4073691bba7b2899c80f17303a4ebd1ab7d3fe8fc3e756f653a73329fa5cb2d7809b3c076281700ec8c2ad64e77fc2308cc7513685f9b490f	1608293315000000	1608898115000000	1671365315000000	1702901315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe441c08222a9b8693a14a8310858c6cad224b1db893fd9115f4387cd099d8f20185d0a6758adcc54be268daa1ac06bf9b4e87df65a1b80cd27b80e3eb58b54d0	\\x00800003a53eb3970b76342e5bca644b58ec2a160f34f3970a9b1383957d35928bc0931a6e79f5cbbd6e8fcedee9ffeb936684fb52c4f1fc9b0e4ae7c84e8e3f2e5fa886c524974c1d86a6545c4d973356de680dc537d8af9586d7ad2b9e5cea8a52915cd63e23e849d19b3250c0cb759e8b4557565a7be3a887946f0b14b787a868a1bb010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x1e1de50d09f88f2079f18e7d4e06bbd4db43e91153f44c2cf50bf2c4e223ab0153e8ecabbc2331ee106a810d81d4f12de614777fb778c733aedb769297f8ac0d	1609502315000000	1610107115000000	1672574315000000	1704110315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x00800003dcd0751730367453bc7ac2f79fef3037052880ae517002dd75517e50daa64b582316c7cd96523138fa933f8eeef3ffd6149a58e3653b7d71e0b3334e5573bb4f32af13391bb433b72af9feef434935c82b4b2ae1eb350ce67258b35daca4d9d12a29d769a6ef7c563721294f6fe951d18304c1fc8f8424ae136ccb9ef6abc171010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x840382d9fd9cb2d643228bc8aedcf3b6ad25a3e97b0988e15cefbc92bc48a537348fa1b813b7dcaa51541a6cfd256c4e38e1755a4649495e91399691ad0cb10d	1607688815000000	1608293615000000	1670760815000000	1702296815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18e4cbe9a7b57c535725ff98370ec5b78fc98b1f22cc95f77faf2e3ae1f56ebc48db3b715ee614e7e1660c3c3f2ad002a72800c0f47ab6268d231a6908625564	\\x00800003b472524a4a75f12855a6fedb5072f03ee6e9ce2f12986da467d5623f2a4aaee05aadf8affbdf0246ab8a06028b904bd08049f32527015e6fcd2ee0b64f11a0defcf2298ed69f8f814dc4bb013fa88bd9462aabe599129b2eb63f3d6f00b1546b5fe4f4169bdc8db45ef1d193c627423a365d478544ee45cc4af49959825ffecb010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x5d071cb45bd528d84e24b6ce969bffab443301ebb4a91a4e1a218390d0f7ab04bfbec46afb305425a65c8846bb713021fb701add1eb0c387e95d3a363bb2f703	1608897815000000	1609502615000000	1671969815000000	1703505815000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1d90c180b8db5b7358f32ce69a3db1b1ef8367d7c1f47079de3813e485026e7388d45d3cc83f6b3a600c0a1a19f74a67d2485f7645adec2a4cbcdd516093ffb	\\x00800003c5c5fcb8a00f260360c24425529dd4d72ad0faa574c3f7c72b2ff01cedbd8947e9ed39759add745ec22cb5d1407e9e18d34d505c10f71e32bfee36ec626680c7f4b21a6019ca78c57208aeaa4dc22c59b54f8cf0d1f58520d51a5daa68994347ed5d150d909de3e2c5dac9c7ad781763d0d68971bb3d00ba215097cea1a5e737010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xe1425b0fbb176ad20ed102e7db6c88812b810ef53f668dadc32a2e861da900228718d420d0d23d4abef3ba957033cb78c38d6de664bf7441967927a5882dbd04	1610106815000000	1610711615000000	1673178815000000	1704714815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x00800003b78a3d9d4bbb366e9279f01bf0eac9078ce66e351a731fa4e97dcdc711e40ae986b4a48fcf3ee2363c8695001755a5553a38d27d8e2ee8e0212d5025218300668a47c93749f9453f8f98ce11197e7ba4b0e4ba237bcf6192a518d75a98f9afb62a4c4a9735704ebcf0b63c990156b92d31888e7e9c43ff45317650bd53743ee1010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xa9127247212131fbf403e0defa148b5f225ee9f155ded227498ceaae97af2b09d683062f54f51eb8e1401ff393a5b6e664a7b1d14dc4b9870734caeb9b732004	1608293315000000	1608898115000000	1671365315000000	1702901315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57f4bb3dd2514a8bbb3b19a285a842ad9c9c221ee3c446d45ee9164974249335cb9ee0e7391a663e4c5915a7c20dfef30820d807d19d79cad1dac3769834d006	\\x00800003b506fc42f37b3d615af9d41c503f9543bf689952cd7979e73e74a61c29b96c1935f684dd3bdfb087fc6c05f8911da2e29b4c890e7adf960b7418f6b16faacf7b287517fb6888a030280e3921f2fac40a13088ada2cdbb4bff004304865378374c5bbd9cbacd916d8bae6b00eeb297a882523ea355ff103469f146b875e4dfae3010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xbfc73dd1f25e7db13510404749f83f6c75350ed6e9ce80e00643039f4a11d8fc8fb5241eabf7140a66a4a687df1be5c842ed7702a1b3dbdba8dcde8995bb2204	1609502315000000	1610107115000000	1672574315000000	1704110315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x00800003d6783e596c1f18f7299877278c826a832c9116aeb0959e1b3c2da2548795f89e67075419111d0db8b6f005c13b5c4015bb79f4e72eeefb7b87dcc943dd3b73e24141defa8a0b2ffd3400bbebaa003422351326c9a6033b52555d007fea1f1d3c8c474871526023cb064dd5c0585a29ccac1ca24db99c39afcfabd70f6a600dff010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x31b435d47b06fd835fa7a05932a462b08c04cba61ef805366f777579342eeaed8f4edf8e8e106d486e0f006ff63caa8fc8ed1afff1daf89ce7d6008d7952b70b	1607688815000000	1608293615000000	1670760815000000	1702296815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xda3c97f25e1bcd13f11e2adf58a0fbfde8b2f52e8dee2b483beb7d854eda90643bb55edaab3a803fadceed89196173eea0921a9593b0a488292c2cbe26348401	\\x00800003b0373e1fe6391fc2b278490078c2d720df7ec3e15fc9d330dcf93371606986ef0601371452b44db0d337ad72062e2d68c71d516e000803e244592363d438b9c990ed7e33b3e64fcd8f6979f4f616e6087c427ed2da0306d1b912445661908c45bfa998d901915652c566f0a6a33509288eea9cbdfc77468ce0383178ee6d2a65010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x32d8bdb807006c59b23e21ad1517c3ab55da4eb00052b2142d5585d580306443ef5787c318afcf8738aaadabbb282e0716bfa29fe183a97d4d2d64c4ba043d05	1608897815000000	1609502615000000	1671969815000000	1703505815000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f19a4c39ae6dfdde35f35ac21ede06189c0d9f8d433429adce71d0518b50cf42cfb1db95a7bb5794ef97345cee58e2d3469ec0d61e6a2a0a851807dd60c7d73	\\x00800003c9df0119187a7768e1f284c48473ff6c19fc13753b9495544920e4e7f1587c93dcfc5d3d1b25a47674e07b0eba088737a1cd5bbb1f5c9fccf9829cf7583de01f77e08ef65b824d9ac5f189ab749675b5cb1bf88b4983b4d0a27449056300d65ac7da6e9743874cd2d71ffbd749c7d429d11f609fd1c51a7c200a8ad9cfa7e059010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x7e985db6cbe51acfbbb1f56e3746afaafd4c0a8ce377465c965d3709ac22e17bb23407a729e8bb951582db35931676ad55f48a8ec7c83a6eb04906eaa930880a	1610106815000000	1610711615000000	1673178815000000	1704714815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdb3e02301999f4d28bbdacdccee2b2617db8d37b37b27ab965c427f88f802ffd170b1c9f366bba5b8a906bb35d15b8fcbe7dc9d5d2825ca0901e2b9704a8f4d0	\\x00800003e9f29f14b62647b0599600226800f9210b12b31e88490e28bbc5dbd3f31f6d2114975f590b3d0e5f717cfa83858b5d233fed1a504e1f5f513312f0199dd39e90a4ecbd553c59bba5bfdea50c0d31f82e9d98bae27c66093de5af8282281a4a557139cc73f4187f35695418358877782df802f77c2e7693e11c80c770b08d8b49010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x53784b3ca7b3d5f80a22c0fcb4f0667c2eef1ffa19f60f77bcebd9fccfebaca92d84993019001c46b197f85c03542f84a7c6572adac4bafda7d6d4ac04a05707	1608293315000000	1608898115000000	1671365315000000	1702901315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe11baafe43ca9ec7bd7a4ead113dd228e2c59b58a409696d2272ad27b4f355733b0c2928c83d5dea62c8f77ee2152400da712777d4a4577248fd95842bd04a32	\\x00800003ec75207b7b80c2d27321b70df4177b870c857f14cc7ff8b79d620f6d09c67a095671040d4bdf33b10453d06a9cbd1c555ebe8df84f06ddb21822db993eb8c9725f19c4565fc51597197a5449f89429145531d4c20b826f60bf45d857acd292b8b71707abde7f66314898be1f9ab74760033b7403cce4e80cb2b78342172e7053010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x43fbd887b15af4372d20d4d41eed48a1e299d884ae4e7b3ce9cf37c6fb8d46acadedb8559a27b60e6b2956570b7b0ed5cfea9caee8638b192507006bbec77904	1609502315000000	1610107115000000	1672574315000000	1704110315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd597b75514ab2e11f038821daabd15da7b6e3f3772d6e27f86e015a0ad36557e35773e3190708644781a01240860b3b21469bf7a986daa12e3a4ba5d90620028	\\x00800003c1c8819bc7a08d9709ac48ee59de10c7f0fab4b11d263b0eefbc5ffe92f33633a73f07efb89add5e29933146f3098d69b587438bb6b2d698805b3b76c2477c0483022024928f153d91064c3904daa9eeb4e4c21d67af603742b5bcd103d966afcfbcfb767ac8501df2f42c8df6deeee4a89324c70efb7bf017eb2d3d02ba52b7010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x955ded0173ced30b791332b3810268ec92e01828617d689ad55e1e5109e00ab70a0c0ac8bdbb845f01941a56c7e92f7204e314acea489b1f7d5983510d554100	1607688815000000	1608293615000000	1670760815000000	1702296815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3cf1e3dcabfaf56afc0dfd1b73454c0d5e120139873944d523722f290d07331e6a8557a6e076c349197415a2f573b5654353bb9a0be3026895857a013404adc9	\\x00800003eac8c465d4223b5909a1c506b09928f8625dcec1fd31b2d7c1b5fbe93cc1988055285e23575df9b9db3b1ac5ecdff0cf92c51636ca00409d4b6b75687bf6c4ec76e98eb85b37966283c8513f7019f0a0624b64611c87e59df81ab3bd8f3f60363b973e01ccddcc93cad6fb51f4c4dd0eafe2ed556cffb2557494129193c81645010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x3299c04a68326630c4fd20d0cb367d99ca42170af58169c982ab64f8e4a713b03ef155a4ed88e0d82b506ad0b2a766adbe5cfde00c3328982baaec00b9432402	1608897815000000	1609502615000000	1671969815000000	1703505815000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7469ed0edb2b9f391b76240ea4dae1c92e368339253c2ff8557a201888b093bab73c8b57b42795428087ef863b00f0ad7dd57e58fd5f2e39d3294be117a09c5f	\\x01000003f0a5badd44034e47fc5853a22fb05aa240142a421b5ece970a252454cc803d303747cef6a78d314435c10f50ca284f0001fe39b37083351cc0055285ea8fa2daa0046efa66da8127884e1494bc23cbd341206ce46fbf2ac2ccf0356e35fab0043391f8464dfdbbef67308478c6f07a677be9f1a186f4a05308aeaffa0a88d666fc6195a782560f5f677bc6a18016fa35ade63ad1bd0960c5764a8966b04c58cc216dad76bfbf1ff31e138d374e544e05828accfb0a4ccaf4811ce42c0521ef5ab0b1d8e5ab2ccf8a538e8d6fbbc9391b5414ac033c01c3e56f85d085efb708c3753f382de6f6273475c0f5c1886f882c4eafce672620a8d8afb52eaf80023e9f010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x6e9965bfdda64226010971b7da2e74a7e095ada169d9a371c4188046be1c0b278b9bd6a530ef04ccd015ae1b5baf85df05fdec36a94e2a373b0999b8d59f2f06	1607688815000000	1608293615000000	1670760815000000	1702296815000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab85c7ca91e23e100a88e698cfaa1d84498cfc0db9f2532687da89274398b5e6bea6273a06461f15afeb9f78dc8dbeaef82063730210a8f0f105a7d794b0cc0d	\\x00800003a585271349eee0d8b9ccb3f0973e41ee24ed6ddf24058a3b256690a4b40cda2158c294cf331a32580a9de4666256d6953aefa30cd266625db96ecde32c99d785f69440e22d0b1d511234f3d4db1594e203825ef0d8e938d855de470e7c671c9571c8203a0544ce1f211c0d4f90ac7dd1c9879b880e772992d0ac3d7add0808dd010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x24aff80bfd2767d2fdb2212b427028bacf8d73c15284b65e84768817af8d38a9c9d8f5125c2824f154d5bd2e56bec42825b001c4d283e335c98fde410e15f807	1610711315000000	1611316115000000	1673783315000000	1705319315000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67e03d72294f493c4fff128006a626608e4a61495b200059c2b1ebf38852ad8f2342f4e933629a1185c333b95f95e473fc913e42f61a616f8740f06542cdcc8d	\\x00800003b6d1809a820386f18cd7755a7207f2affbc6b4d5d64354c78ddae680ccabe0b5feab8a5e064dc7336ede694962dce63b5adff316b935edea851d62752a3dc31b4841e97cbab60d177ba2889b610c15dbbcec1d75b1fe667ee72e851c11e8358ebc77c83a8cf1dd4a905c0ab0258061c3ba83077653b5a2296552fdb5343ba963010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xb7b27a641c152665c6da5b1bb188dcb632fd96984d8a980b3eec874420062aa479bac82d9257368d33f8d2d5fa94d757adc478b8c107d8015944c7ef27e84609	1610711315000000	1611316115000000	1673783315000000	1705319315000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb106feee5e1d1d39bff971f338052de256c102fac5dc934b7b57dfe7ffc4f82b775a52b21dec37bb8eba36bced00d49795be0aec19b4288e92f9fcdc9065b1d0	\\x00800003b2215d957f1ef4c3f5aeab54c1e41fc0fb332ac9abc896a1a17686f2358bbe1ccb31451c3d43a2be816a9cd9e0c7f0ee1a7e8a913d2febd0d90e728d39145eba7280de27396242428cb7d086b8106bf90250635da90ee445605497b45d9fc6e0e0aa81dd9a8c2c67f6d880d68dbc4182419fbd14fd07a839376c2a577e9039a5010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xd53146f778412576b932faa043165427a753a41e53b72cee93954d52c1a7ae74e755924e8ebbe32df146f699acd5778e3627406c522d8be021e14047fcb0280c	1610711315000000	1611316115000000	1673783315000000	1705319315000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb088077bc1abbb8f637a4712e1d574e15235727f1ad0dda5b1a22a5761197a0a5d8251ef20a5bf3aefb58b4763b099b24056e0f7b6457e0faf9796e00197aa3a	\\x00800003e9fa5c0483cb8358c3e116d50b165e3d685679d18a16b3540d49a839a2db287438f0c9a6dc25f2a01811e6c739c97c5f29214d94f99a4451c87312eb5945b3507c8b7ef0ed9977b5828250017be3a407c142f1246d85b00e84bf563be216e943c894814b05e7daf609b2ae635a7d98bde8a1e57c0318636e7cdda13051aa9bd5010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x862207526123e04d2e290839412bde4a9f9518e4b310605f10f13c69fd93ca7e49d702a2a4977784cbab2e95b8a6fd5602773f7fe27940ad1bba2a43cfd23708	1610711315000000	1611316115000000	1673783315000000	1705319315000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfee7ef0eace0dd576d5a5e10eaa0b5e5f89eedb471f2715b066442cc5b393340ca7bb318bd04dc0c58f05b65acd4d555cf5e074a261ff9f58dc627d9518cb124	\\x00800003ba58bac60fc2b5e28f10036028b4c1919a19300c4cb949979b3b4ed78cc0b3d90ed93fe10f655832362c1f16ebb48d5aa2f63e1512a83053cca34bf7571e792dff2dbc24826cbd153e0773a746935dc9e271269d01b067a4fce1b0cbeaff12c5896e40b3904e01b7c5666198a4754183be26429f1ac6c5d2e12df2924e6d758b010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xc7e857997a652239b259fd8e4b26b31ea706d57d62283a79f456a824b476d0e6db3265abb037c809d066425b3ae271dc53035bd764cbc5bc47a5d659cace3603	1610711315000000	1611316115000000	1673783315000000	1705319315000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa40300a24e56339aed3e129f671f5f001b8bd5be0b5fc8c2f941c9986493a1a34e07c2e37a953e4b69186ad6a601325ac66b5b0d7d16165d089f5b8b3b030710	\\x008000039d8a07490df75cb96cee7b8798d3f485fc07adf4c4d3bb57936ba80cbf61bbcdd9cb3a8c1dc1c27988a1cc8d0c237fea1b429c4efe03689631fd42a55cd092d70658e541b3837f6a22f40a563bb16a61accf7e90c2486ba080388ac984b42c0a9a9c50e127c5581df9796897e2192cff21d82d9b0033f0428d5d9fb31b34fdb3010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x438c28289d559c62954484d6e39efe7696ea605898a95160c47d50477ce2806eca4b826bac4b9ffb609fb830fbafd41eb2f25fc34e3de091e6b462d23f7ae503	1610711315000000	1611316115000000	1673783315000000	1705319315000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9f120a90651a6f26e8bbeb7e069147a4ad17672143f90d1c8f3e377cc77c8671373e8b7902bb3e5d1471d956eefedaeada57eb44c98e8e223b91a9831765ac96	\\x00800003a05901f484428bf9d313f323cf45f8985027e17fbc266a7d8f80d0b9f59ddeb3def3c4376b20bac74f2136a0cac0644207be467de44d72b6f2ac7bf74d5f6e8f6d8ca8cc2314b5fd9110811daba2459ade76a11f3693d76fd230fb2b093bea8c0149f59eaebcf59b1654c2d6511c20adcd108aed938b158519a7c6396e03c911010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x1ca0315602016c68a2727d9b4dedadc66682d33e4eda9ed23db73b3862cf26dd8b54d3761bf1cfc6eb56977408d3df5fbb9001230dc82abb299745dae022270e	1610711315000000	1611316115000000	1673783315000000	1705319315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x53954117be8bc8375b972b9abb9f39471d70058d94366ef4f86a75d14dc309fd3889759b0a29dd7f8de2a466c443b22cb5027328e18e4b393d841991f7c64888	\\x00800003ad7f7d8bf443741d92f279376cfc8620750e3479eec850809f9b1fda6b0885982da4c6300e92942ae0de8e14a8600d0f512e254a50e52375c1001fe4b6e5fb71d704e6b2feaf98a36b6fd0fc7389fe8264be54fe06e9d44db9d0c4f2cd754e2ad8c4a5398397480e33ff1bfeb22037c87aff89515c32678dacb27b6778c89a81010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x0656adde2c9f17df1f516005acd8cc739d1bc9aa138998b81565e362a34c4040f7349303b5c34bc5a8639ec6c063fb1645eda2349042eff45d43ea36b427f10d	1610711315000000	1611316115000000	1673783315000000	1705319315000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x01000003cf3bb267bcd00920c888f0b430fbc36a5c0eaf17b07e25dae932e5947c5844cefd51ebbb30d8537783dfeac3be06010ba93cd557417e242085e7d6fbb405d864a160324c8246ff0c712bd4b67078e0c1a4824cc0e269e6537d5375dfe9fa9087fef91a1f3352d008e11b44a2af16489545e4cf3743d64a6f85a35f48bf15dc37e1a3f9949cc0d3bdb90b3c022d709074b651ae47bcc23871f6b34775b78f3787b1a25d851b8693a6e20e49c21117f0da00d3d129aef2e8609fd82be73fe9f8a7765e2969f566f0b2c72e5aaffb79b42f2b0a87565ba2a173ea06cc5fe3b37bb0965a1ba1a4434fddec6aa5363a9dd11b5faf274f7329b189a9693d5bb8d9acf3010001	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xd82d9db7f16116970cef0b2129e4b98c34bc3adef2ece705542a06f21e5ede888b64d06e393dbb6716b6d5c281bec98a1bed8fb6bda0b588f37e70b1c2fc520d	1608293315000000	1608898115000000	1671365315000000	1702901315000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	1	\\x96e7be861db3bf339fbd7e2db700734235b98a0af1f0d26b17086cee7559468f569b1913c48e781ce4d7fa00224b0e59b8e90dcbadd27fd03d650bceff3bcc86	\\xcdd46a94c2af8949eb0689eb60ca4d7d4889de7390871b14571865136127e0bb734a194806ecf02b0b769cc28d5b7702fb20de5578c43655b32113855f7b3cb9	1607688831000000	1607689731000000	0	98000000	\\xdc12d20ca00b38bf589253a53f8c7a1d4f9a68970454e2694d9225dfc4ac11b0	\\x072a687ef22f4358890396d95326915e6b917f929a7c22effbf4b9959ac6d8da	\\x0e186e04344acba48df1cad3e79d83633c5234a2ad78124ce378da4c76b7a48702ec944333e28f8bebe60a09bf2a445959409809b18f4d1b2b922128e5d9db0c	\\xc06cad01d1590fe81913b26b04e234786d30592952b070621eadd61436795747	\\x1b0d84e60100000020bfffb2e77f000003ce13ef60550000998f0084e77f00001a8f0084e77f0000008f0084e77f0000048f0084e77f0000600d0084e77f0000
\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	2	\\x539eb73025d283badccd8c7e490f465b2b994648d7a0eafe346b23fd821e0ff5f0011cef4df375567dc9beaaa0aff667bce36f7ef5cd7d650d4f79215a0daba5	\\xcdd46a94c2af8949eb0689eb60ca4d7d4889de7390871b14571865136127e0bb734a194806ecf02b0b769cc28d5b7702fb20de5578c43655b32113855f7b3cb9	1608293641000000	1607689740000000	0	1000000	\\x2cfeb348a8c49ba0c0f256636ef3868945ab9385580caf69922c4b309833cefc	\\x072a687ef22f4358890396d95326915e6b917f929a7c22effbf4b9959ac6d8da	\\x55b4a32e99c739d7c6435f3287ee57e0f55f7fe832fbf8e8340ab1ce4ae023fd2eedc76a4068d277f83ee17c64ca209ee7d73329b458585da3f7c0669477ad01	\\xc06cad01d1590fe81913b26b04e234786d30592952b070621eadd61436795747	\\x1b0d84e601000000207fff78e77f000003ce13ef60550000f90d0050e77f00007a0d0050e77f0000600d0050e77f0000640d0050e77f0000600b0050e77f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\xdc12d20ca00b38bf589253a53f8c7a1d4f9a68970454e2694d9225dfc4ac11b0	1	0	1607688831000000	1607688831000000	1607689731000000	1607689731000000	\\x072a687ef22f4358890396d95326915e6b917f929a7c22effbf4b9959ac6d8da	\\x96e7be861db3bf339fbd7e2db700734235b98a0af1f0d26b17086cee7559468f569b1913c48e781ce4d7fa00224b0e59b8e90dcbadd27fd03d650bceff3bcc86	\\xcdd46a94c2af8949eb0689eb60ca4d7d4889de7390871b14571865136127e0bb734a194806ecf02b0b769cc28d5b7702fb20de5578c43655b32113855f7b3cb9	\\xe2063123a23035df8072eaf48796b111215267db0dd084f76ac9e31388044ec2b6b9cfa22fdd76cd0bc35903a9ed758a3b6dd080104159ff866e252a434bb904	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"ETBEB1NT5QKM791V9XGXMPNW6CQ0P5FDMYSFJK9G684RBD29HY26J27ZP99Y2HB9RSYSRJNH08128T8Z518GHH1EDRH5CB2QKNRFVA8"}	f	f
2	\\x2cfeb348a8c49ba0c0f256636ef3868945ab9385580caf69922c4b309833cefc	0	2000000	1607688840000000	1608293641000000	1607689740000000	1607689740000000	\\x072a687ef22f4358890396d95326915e6b917f929a7c22effbf4b9959ac6d8da	\\x539eb73025d283badccd8c7e490f465b2b994648d7a0eafe346b23fd821e0ff5f0011cef4df375567dc9beaaa0aff667bce36f7ef5cd7d650d4f79215a0daba5	\\xcdd46a94c2af8949eb0689eb60ca4d7d4889de7390871b14571865136127e0bb734a194806ecf02b0b769cc28d5b7702fb20de5578c43655b32113855f7b3cb9	\\xe9a48ab2c9a91266ea054e6fc44ec6fb8ae8f3b6645414481dde487880d2c60106c45b8d3ae823e2393e8f900d2f50f3601fb75fbfed8eeb1f5684aa9933d502	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"ETBEB1NT5QKM791V9XGXMPNW6CQ0P5FDMYSFJK9G684RBD29HY26J27ZP99Y2HB9RSYSRJNH08128T8Z518GHH1EDRH5CB2QKNRFVA8"}	f	f
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
1	contenttypes	0001_initial	2020-12-11 13:13:40.174405+01
2	auth	0001_initial	2020-12-11 13:13:40.203994+01
3	app	0001_initial	2020-12-11 13:13:40.2617+01
4	contenttypes	0002_remove_content_type_name	2020-12-11 13:13:40.283055+01
5	auth	0002_alter_permission_name_max_length	2020-12-11 13:13:40.289674+01
6	auth	0003_alter_user_email_max_length	2020-12-11 13:13:40.298194+01
7	auth	0004_alter_user_username_opts	2020-12-11 13:13:40.304219+01
8	auth	0005_alter_user_last_login_null	2020-12-11 13:13:40.309462+01
9	auth	0006_require_contenttypes_0002	2020-12-11 13:13:40.310728+01
10	auth	0007_alter_validators_add_error_messages	2020-12-11 13:13:40.316135+01
11	auth	0008_alter_user_username_max_length	2020-12-11 13:13:40.326222+01
12	auth	0009_alter_user_last_name_max_length	2020-12-11 13:13:40.335759+01
13	auth	0010_alter_group_name_max_length	2020-12-11 13:13:40.34692+01
14	auth	0011_update_proxy_permissions	2020-12-11 13:13:40.355292+01
15	auth	0012_alter_user_first_name_max_length	2020-12-11 13:13:40.361917+01
16	sessions	0001_initial	2020-12-11 13:13:40.366912+01
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
1	\\xe3d2fd0d1a9959d53ee9fa779908c13081353d4835602d836c7cd743558f368b	\\x15cd172ff9232ffc8792383d0fae13eeaaf3bc40676928bf9b566af80224fd727cdadd3cd3cb1774de2e577596a84f9819fc4e791deca825383fa2a9fd06ee26	\\x0a2085e10d4680add6eed1451de78c32fcdad85197bb8033631f0b6aa89fffd74b692c5d840dbc8c7aaec42eb9927efbe8f25d0959ff8da8536f389f09a66c4ce915f47ff3c85e2896e002763c71829a3c3b81a0fab474d9a627b5a4970a2f45a02d82757f3566d517e4561fbbddc85e158b0282617ca63b22aa5a0842285161
2	\\xdc12d20ca00b38bf589253a53f8c7a1d4f9a68970454e2694d9225dfc4ac11b0	\\x3591f89aede6cf4aaa845ace772f0f7a5ff6e837b6c64bd9a9b163e4368486ab0747c36c426ec5311cdf84dc57391c1954c903b8395330b4a64a4d16ae3bfc5b	\\x040be74b0e60c42a732364faf7c373a8f65ab574fb21221d0531b587d355e945a45ce22dda068dbc711c715fb461a56468589811046c762b789c504768f5eeb17abdb079891b9b1b879186123dd70978a287d044fb952ebf5cb377454888f2b03338dd0f10d3cfc99578d16b82d829b8f5b4185ecab39fc1c1489d9fe330c360
3	\\x18e1b86f13f36b097e594a57960df565958d4e0af41df7b80c568c939e915a7c	\\xc7b0efaf2e440c85fecb226b6c17e8b584d67b6bc8cb57396790b17c7be0d6e8e02b7531d9c406be089793917ee6782bf3c4bee95cbbe24cdd9be1232470e543	\\xdd2716302dcf9d9abeb1c52e3110285828e0447874ec3c144cf4b854a4d9e244c2f56c4ec714bbfbaf9e295cba19b0fa4f2490f50e37001111e82993e25c9a31dfb1d22e314a2052972ffaa51dc8f5b5712148ae13adb27a17abbc65cce02c551275baf87e61a32669afdb4a21ee2d7b13a6a2335189f0b6d0fbb5a0765f1ac9
4	\\x09c09e09299620e3d5174e3f1b48bb564cf690c28a33cb9de7df13cb8f8b5c2d	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x7abbbeb485616e9a84a3f97fb79c00e664ab76b9d1e2fbda552adb54f4fc19f6ab65434db72d82c47a7b2b1659c8a9bccb0508c31ffdebbf5f482749bd92507e2dfd75e997f24f6c5eac3ac91f997415d39d4b0e0f3ad3fecee139d5e43ed330fbb5ca19950f714bb88f042949a45053f2a207793780a0e4c6d27f43e333972d
5	\\x4dff149a5266b5065346e6ecdb2ef73ecc9e0fb757dc54c0cb25e034fb130fc9	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x9d4f02449fadb8c7d68a61c2cf03eff5492a34468751c44d8b9afdf2bf75a926ca331c4ad99dc6b0e5b5d284ece9a52c4e8981564d72b55379f9d949ef7fe05f2de3d4aca8fb82dc5ae8295243a885eb8ced0e425348cc0e391ad58f9f8db41766ca48960bc87526c5825ae7be18e1b2515399bce85c4ed0d2f236ffd45f2e38
6	\\xd6c5a0150950b333ec3ef9f5cd7a3d248d68c26485b33f0a8c822984b87385cc	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\xafd48faf16ed9c0c4ed66cfc236caad24d735f6352328b7c62c4f53b0aa8525aac20b1506d7573661560e27bf3346f4979e55933720c3636c07ceb01f582b5ba543f769aeedb7e8985a80fa5bb0d1e375b4c379a97857c018b9177e8c35c4e81dfdf4d2b40b2f6b0a45f198e946961339c3bf9889570058ed1b908cf8412971a
7	\\x7730c718681b95b102e5ae0a64793dda59bdd78b5af9857ba9e1134365055cf2	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x370174787ade6a0d7b5ea8b8ddc77636e5c84ed088d1f0703d44bca1d4ca8b3423a079621fa91bd2610af0d1771a71097a216f51165e406dcb399cc60ac91866d20fa55f1b70a4a54ca878036f3fed055f21c65fc3d420fefe91b0c0236eea86284809b5d9798068e0029ee6f3d62e0f329e0b6056258f3ec0031e55a18e6b1a
8	\\xea3f682231d80e184690648778c76343b82d795bdeaa0d720d594e830bbac3ab	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\xaf678b2b2e900f47b16af04300518b56a4ac3e1d3f0daaec5063f52b2899d67b910cca10f7ce49da3c1a534bcfe40c332393b4945c899a83e8879202cab76d23d8c64511973df1a1f1c1d5ca78f298c6a160c966c3569b579b0b1294ee6016b196c8f4fe71dc422250dc87d4b0ce0a5c4f455083753636079fe47306057da18f
9	\\x6142980e01773ee7739ed4b1cd255c92d7baa8d7cdfcfa9334d531be09d0bd41	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x5795e2c81d7adf82a02292264c6092687dbb5893455f876ae0088d6f1ea3ff705474db701fefc5ff3bac989808d107fe45f74a523acb7a6b4ff7d98fee911a7bc2b81fabbb420e0864c3fb26acd03ec72f92f1b8c2e5bc4fe4a79b97df1c55fae5318fa9b6830c5ee8334087c67372555b00dae190b176a1e02454a996137928
10	\\x176e250c2ac15fa3212c2b916491754e9adf42bc7d79ca4398ed78b36d9df143	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x2199ef39676e651a9c2f8bc89905ef838c7d676f5e1670540a47e9c0d72dcdb3cceca4818cf3337daa1903f3fa9f96dbf6d89db30697b8dea7d9dea72dd1fda84b1b2b89543b5938de9dffde18e4825bba298b515fc162f743370c90c0a9132b8235316915adbd20d0d156d4e53373c17918a5d04446bd2954083f255bdbf102
11	\\x6c0984b925e584cc5021e6860197718afd21749302d62c74078fb4b8bd5b16ca	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x65fd20433ab0f7158bed3e7b346efa47b154749e4be5e8232f79fca989508510af419724ed8fa99deb6138de7ceadb40ab185ff86fa4694882c2c814158e085a930e40c34f36b44724b32f73b576d6f0a74de6b717b5889528dbd55fba5168e66ef4b6c60b6786227c0a7fe05516a55d91a6a3558703e4708ac52de80eddb548
12	\\x2cfeb348a8c49ba0c0f256636ef3868945ab9385580caf69922c4b309833cefc	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\xc17a58b35b78c12bd9dd46e2ee52e20b300c37c1d048acb1c4d05bcac5b8957fd36e6d0c1d19cafa9ec23fa5549b3e8db8e2be8efdba3e382477a6a0b9512c28ae118b2d8b8383cb4aa1a4499e90b9a97363edac92021f96853492531360726a9c9ffce29c951bea70fc0e327142b44d46f4f1d5c0fccd0ba83889d5d72bd2e383d42fd64481381efd00ed0a1f7a5a383666884f9f946a7d36a17e1817d8ad9d72b2d320dafb9260f608e43408611337eb00f44c7fd9f8ad9b60636c4682c0c1b5883c355b803816e3a640113f919a6c7ee1db4e2fa3baee2ccf777437f3384907976094f3197a97dd4f3cce20e1d0f30130369913be501e75c6645b9fc97497
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xcdd46a94c2af8949eb0689eb60ca4d7d4889de7390871b14571865136127e0bb734a194806ecf02b0b769cc28d5b7702fb20de5578c43655b32113855f7b3cb9	\\x7696e586ba2de743a43b4f61da5abc332e0b15eda7b2f94d30320985b4498f846908ffb253e14569c67d9c4ab1020224691f285108c42e6e22562c579d70fda9	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.346-03M475GNYGGWP	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630373638393733313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630373638393733313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22535141364e3536324e59344d4b54523648374e50314a4a44464e34384b514b4b4a3233485035325133314a483652393757325851364a475339303345535731423144563953474d44424456473559533056534151484831504150534a323457354258584b534538222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3334362d30334d343735474e5947475750222c2274696d657374616d70223a7b22745f6d73223a313630373638383833313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630373639323433313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223757335259365830354b47504537384a584747475a575133584b413754573443564245575a51413450525648465a455730355747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2230574e36475a514a3558314e483238334a56434e36394d4842534e53325a574a4b39593235565a56594a57534236503656334430222c226e6f6e6365223a2244415a51503046485356344e57434a48484d5451573847325a593751435950394e52345a304230514e464d4451304747334b3147227d	\\x96e7be861db3bf339fbd7e2db700734235b98a0af1f0d26b17086cee7559468f569b1913c48e781ce4d7fa00224b0e59b8e90dcbadd27fd03d650bceff3bcc86	1607688831000000	1607692431000000	1607689731000000	t	f	taler://fulfillment-success/thank+you	
2	1	2020.346-014F5AY54FWXA	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630373638393734303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630373638393734303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22535141364e3536324e59344d4b54523648374e50314a4a44464e34384b514b4b4a3233485035325133314a483652393757325851364a475339303345535731423144563953474d44424456473559533056534151484831504150534a323457354258584b534538222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3334362d30313446354159353446575841222c2274696d657374616d70223a7b22745f6d73223a313630373638383834303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630373639323434303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223757335259365830354b47504537384a584747475a575133584b413754573443564245575a51413450525648465a455730355747227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2230574e36475a514a3558314e483238334a56434e36394d4842534e53325a574a4b39593235565a56594a57534236503656334430222c226e6f6e6365223a224a4d51304a30364a425247374a42475259304437575342434d51355030575a4a3733574a30564357415447573458574d35323330227d	\\x539eb73025d283badccd8c7e490f465b2b994648d7a0eafe346b23fd821e0ff5f0011cef4df375567dc9beaaa0aff667bce36f7ef5cd7d650d4f79215a0daba5	1607688840000000	1607692440000000	1607689740000000	t	f	taler://fulfillment-success/thank+you	
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
1	1	1607688831000000	\\xdc12d20ca00b38bf589253a53f8c7a1d4f9a68970454e2694d9225dfc4ac11b0	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\x0e186e04344acba48df1cad3e79d83633c5234a2ad78124ce378da4c76b7a48702ec944333e28f8bebe60a09bf2a445959409809b18f4d1b2b922128e5d9db0c	1
2	2	1608293641000000	\\x2cfeb348a8c49ba0c0f256636ef3868945ab9385580caf69922c4b309833cefc	http://localhost:8081/	0	2000000	0	1000000	0	1000000	0	1000000	2	\\x55b4a32e99c739d7c6435f3287ee57e0f55f7fe832fbf8e8340ab1ce4ae023fd2eedc76a4068d277f83ee17c64ca209ee7d73329b458585da3f7c0669477ad01	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\x76b67bd773465d03290ec4d8607d33176d6e884dc4c9555f1a9130e576b45962	1610108015000000	1612527215000000	1673180015000000	\\x160b83baf442928ad5e20a09f5d051eeff3784ada5bb2bd13f01dcbff01ffcb4d9c712a30185950efba8bdeff8ea5fd917fccf355cccb991519cbafd10206506
2	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xc06cad01d1590fe81913b26b04e234786d30592952b070621eadd61436795747	1607688815000000	1610108015000000	1670760815000000	\\x8563133cb924cab4c6ce2c9301cd3899fdb892a8e64764efd5252ed66e11e62d81f565b302278e0e2f78c585272d58d93c3f5cb5ef543b8b9390dbab7abe1a08
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x41d874b65826969a5370b093cb3d2a7944b9dc86a6f34425d5a9630623b2bc4b0aefbd5710b89a3fe7e9a46efe61f85564d5ff8f340729004689d8f16cd96c08
2	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609455600000000	1640991600000000	0	1000000	0	1000000	\\x8293c0d186ae64003a69a6a325b0e01eff44317f18ada30e8d1d491aad7efca7d32ae050301c40060007a7780ad84328f2ee286163f30fc3251371d7a3168d0c
3	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640991600000000	1672527600000000	0	1000000	0	1000000	\\xb4742fc19c817cf013277c39e145671281c62fc0ee2c1c111deac4e9c5b1eaf984c48d71c5b2868cc3a11f454e66863dac70a2a5dc2eb8518cd773d6e101ae00
4	\\x3f078f1ba02ce1671d12ec210ff2e3ecd47d708cdaddcfdd44b63717fddc0179	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1672527600000000	1704063600000000	0	1000000	0	1000000	\\x33f77f54590efba34eab80021ece951b7b0ecc41106f50be385bb8c419af7d4b0217e355d78cb051b1df3710fa931f3ac4bcb2373f1ed8c6c30453a9bed89a01
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x072a687ef22f4358890396d95326915e6b917f929a7c22effbf4b9959ac6d8da	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xa90a2a2c669a6b7e5d834c74d67d614dc992af39e88631158a1fd56261001d77	1
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
1	\\xe3d2fd0d1a9959d53ee9fa779908c13081353d4835602d836c7cd743558f368b	\\xff09292d4205511d990fa9da39b334c88eca9df3ac8410ae47ddcbfd57759bfcb54d8adcb38372266ad48296e3de6b18b4db327f612b712fb9a4e6da8a1c3504	\\xf39ca577285b58b949b83cd6dfae8fca4b716df4c692223c6f7f4f78c59ac613	2	0	1607688830000000	\\x5ced0d082d95fcd336408a025968757fd76ea8f91cf0c4b2bda35a1cb648bf4a33d2a68db5801d2543242e088681ef2d10aa1d5f938fbc0f51adf466c6f74ddd
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x09c09e09299620e3d5174e3f1b48bb564cf690c28a33cb9de7df13cb8f8b5c2d	\\x9f7fdac1dffcaac37f1c1212b1e8c12b16fbf831b95379c4dfe424c9513471017507916f7c8dac4c246f9cad9ab35b6dd0a34b35973afe78c016a9ade4ea3d03	\\x8fe85139d350e04b843f636eac247297a5ffe745574ade8e4315fd69771e5867	0	10000000	1608293639000000	\\x9d983297d40ae40f2697dd966e87abe243cbf10a44b772bbce2578aca313f48a04597ef0fba4f6e7f63179ef8017e03086348e6cb9d5ba0bffd4a8163cdb99ff
2	\\x4dff149a5266b5065346e6ecdb2ef73ecc9e0fb757dc54c0cb25e034fb130fc9	\\xf3b15d6e9293f1c482a7543de4d3c3f384cc8a462182c70b55e7db6e45bbb48996a1dd1b97db7e65e7dd592878624c9f508fe8d101c815ee6ce6b43579ecdd0a	\\xe038ff6a53bb16722136de2fc73bd0c0804b97e97a7007694340df2604171e0a	0	10000000	1608293639000000	\\x61f7c36e3cc8eadeb0123dd925a03ac05ec29d9afc55c1b7dc61cefa03541c5f0f4047a430015f998ea93537954c62c96c27336f74717940c9e8b30a2feea5ce
3	\\xd6c5a0150950b333ec3ef9f5cd7a3d248d68c26485b33f0a8c822984b87385cc	\\x9606b8a4441f6b058ef56b338372f1a498cc0be7dd8bd5787a1875d1177db5e8ee3ec1b28a740cba4b0e8f7eea71d0a77c65877b194f32b1268ce857aa8ca203	\\x60a332031ad7da3c05e920f2b8e6751a92a3e5f0f27d5d0cef43b1c0ded5f96b	0	10000000	1608293639000000	\\x177cb70dd9531d81871e32c988a46bc71ac27a6d8011bdf7cbbc8d464da37e644ca2a2d9a70e57d52d6e736cbf6e6d99225f1cddbb30dd68a69f37f48acb6c85
4	\\x7730c718681b95b102e5ae0a64793dda59bdd78b5af9857ba9e1134365055cf2	\\x7cb5b316a8171c90e73fc56215beefa70b9374eaa49ccf7db18dafc71b27b487da9aa9310b0f1363fd845ef6014add6224b4b0d0a47804c353d15784bcb76107	\\x5b08d7f07f8761f0a047d342132a3278164b1e3a2e3249b921fc697c89a69fc0	0	10000000	1608293639000000	\\xa8f69aa9c3a07fbf0bb474ebb46418f9631902b0500881ad6956b110d07d45526bde95ced2d4e034a31703565ad66dcbd4c2f18eec48e6d913f95c97335cf775
5	\\xea3f682231d80e184690648778c76343b82d795bdeaa0d720d594e830bbac3ab	\\xa30b88855e542e53f92a7ed2482c8cbd32a2f5d8dd36dc7a22fa96853364bebc4d42b9e792c93ec856a80d225e59fde9d33ade0bd17785393a95f3952046100d	\\x8991874669aee815479b44f47823aaa891a72a30598530be5946ed326d128796	0	10000000	1608293639000000	\\xdf760b9cf17ef7abe1c74a67300c578cc6b09020bb858145b4fc0aeefce7d2e75bd84844286c8e98ba9879a9f16b0f321064d6b498d07aae907cc5fd4431f6a3
6	\\x6142980e01773ee7739ed4b1cd255c92d7baa8d7cdfcfa9334d531be09d0bd41	\\x0228382f0b739f7c18d86febbbfbd1949ed8b0305da247730a846a0f0e2d81ae443e97e70f3fddc54bc07c8637c918cbb814aa0eaa8dd66bd2bc2fb0480b750a	\\x0cb842f0ce028ad59f83790f98241527bc56af9528b5d8d9558566691dd92ccb	0	10000000	1608293639000000	\\xfc7c5ce3fdb9b9711a47783997c31cf27823706d6a2290a30f174660aefe827e99c6f0ab2f3ea369b1598de34ca66a0a2042b616d990b5728964341c1ea43798
7	\\x176e250c2ac15fa3212c2b916491754e9adf42bc7d79ca4398ed78b36d9df143	\\x016ad0d2130b4529bbdeae5f070c7b24365fcbfbb60af07b2dce5d633187b0a6c2cad0817bbcea6a8af59c331a1f91311ccf1f8eee991f34daf2a3e5691a1e02	\\xaa52d39ec48b04a3e33e0ec9616974c8f10bfeeacd535ae23080b0b99099acc1	0	10000000	1608293639000000	\\xe9c3740824c1b69d7237755866a300df923b16a54ed62b882b82b1a3fdf92cc1ce2f0fefff8ae2b7a9416bd5e03cf252e605049bd9fc3742cbe9282f7385aaa0
8	\\x6c0984b925e584cc5021e6860197718afd21749302d62c74078fb4b8bd5b16ca	\\xfbc11735b8e70f2f1e7b0965d9ef5de00a71df4c83c8084f2a92cfde90924ee1a648c5fd7b9c8d5b7d1d32b2c5db282b9c57851fa284f8b241b7fd2c8d594009	\\xee05bc18ed16eb94f593782ca6729d64442881393591ba09a2657c787de9d6c6	0	10000000	1608293639000000	\\xb1b3e574bf13c00f191fe05e948a8250adecb5b80c77d3ff5880cb51455f0d138c7e0d62f81bf20e86def587feacfe6d17c905431baabc133e851656bd40f648
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	\\x18e1b86f13f36b097e594a57960df565958d4e0af41df7b80c568c939e915a7c	\\x3808bb69b8693013ac9b01a5a44650c533c9438fa2a1ddfb3d8b68b0955ba99ee3b1af9704002ec4f38e573b7b69f52475e77975bf8236e2bdc896f131229000	5	0	1
2	\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	\\x18e1b86f13f36b097e594a57960df565958d4e0af41df7b80c568c939e915a7c	\\x7ace52cb79dd984a79ab13ba2048018961bd7f88f2d73a56179db39ab4e7e4953d5f8f02931bf8e1302d9b31231f2e38c2db66bcadf63dacbb5983d54b552a0f	0	80000000	2
3	\\xa9684a84add6bd855b5d6b2c7172ee7fefa47a1b9a1ef1fe93d27cbcd4795a3f11fa4fdc3b030d220e4137b98a17c2a6a49f0289a1007e95001eee9f6cb90413	\\x2cfeb348a8c49ba0c0f256636ef3868945ab9385580caf69922c4b309833cefc	\\xfdce04244325dc92ad88722ce9e8056ee47ae422be20ca7e06dc4729c6dfa3869171d19d1e273f645dbc31e74d8faafc78899c834142f165052cfc45d8173308	0	7000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	0	\\x55a7b9f78b6a632a38ef6b89d21312d35de8d4c78d0bf68cf1def7d86619d7fd7b12de34225b65ba153651cce0e689c64e8aca4201f95e1384dd06e4d3a37c0a	\\xb5b14b3451a36e529a06dc3b3e94907e63607d6db1f290717d6a457ad766fabda7a72574135e5a5fd6991ab3901551ab567237b33b832de04aaec478f8e6808e	\\xba41eafa018a95fcfa46ec25e32f410c908027f21a500421b4d1150254b59aaa4b3219e380e89a625298dee6a8050e90b007e2da78db67d57b708092ccc9acb4fbc1b71a70e4c2b156b5d7254002a46f57b33846baf8c715fae22aa67b178e2eb6913abc20f0db41fbb45398a05eefdcc48ff4c63db76732698b7276ed155806	\\xfcff572a8d4abe0fe8cc72cf6e6b90587a22235b37f9b7e04cb2bf5572d65a981c0a663cfd4454d65609ddb59c53dfa1a2644f9540468d0bcef051b5f5fb0863	\\x1efbd6149d51749c0874fa0076ad595cb6fca0cf32348867c2da3dec2e31ddd5358a2597fa1b5b5ed85c24891b83882fcc1add5a3124fcb66d01ac2e440d230fc093ba56e10224ad52c46952d3988d4039651467ff14c5ac07074ca133920445a80f8d0239e2434e2716e24314d90d53a738a41dbc5007a0128456359c71c294
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	1	\\x84b85e1186f6252f5f78132344e12c811c8ba32a153e86e25e5b20ef5f221d4f3f1c33d28ca14d4d631934a94dae340335f645f3bdeb4db42912e21dfa48f209	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x336ebbff67ae5d0adc6d85525803f5f8893292ebf9df4d53955684800fa890c7a40af5a9d962447dfd41009f727136c5b952da20256ed0dc1e265cafd613312df0d347ecf1326c39606ff11d8be16beae0b10b3b31348e17e769050fc9bc77b2487cb35e87853c2e2734d4bf39fec5aa53dcbcc7369eca3d6d1a8153a238c52b	\\xfc7c5ce3fdb9b9711a47783997c31cf27823706d6a2290a30f174660aefe827e99c6f0ab2f3ea369b1598de34ca66a0a2042b616d990b5728964341c1ea43798	\\x77c69315c8edf54310dd8f4b5efc85a675daf6171ec6b77147c1b8f24675f95aa37458db81cb13cf3a4c695c43d5b7dceaaf92517ee3df9c78acba6d56cb05cff667746f118f70702bc52eaf86ba0acf93f3c3fa4a56c3b08a13b316a7781323e227c0fdfb82adda8c18f69f9e438defbf2444066a6a9698ee36301448b4e226
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	2	\\x1ca39edaa1adda6f06d32c229bd51c5a00ef0f783b56c9afb5402b351960e979d49fb1f839b39466100edf13ec8ec061ccbcd66ce9eeb6780397b6cb3f81fc04	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x1ea024d41434c64412c4626634b61eafc808ecb4e837f7db99f71a307aeaf20c76c6fca86d59b80163fcdc55378c3d2ec2c9698cfbcf74c65a3329e3f21288acef344451292d5421794023943e29d31a606ced0f2902c3fad5fbd9abb078f5e81e709e6fbe97a060ee5d391f2fa43b6b8b5a4e8eb6689128938f33411e4beb0b	\\xb1b3e574bf13c00f191fe05e948a8250adecb5b80c77d3ff5880cb51455f0d138c7e0d62f81bf20e86def587feacfe6d17c905431baabc133e851656bd40f648	\\x6818c89d454f7b0b3816a44ff05424bd7578106fb26366df7cd3cf0feb200c13d02c1045353d07dbe2f36f4cb87d82c8d7da5bd36584dac4ed1e9a6375d9a9336568dca5ffde7cef6460b6cbdb0cb7c1cc272b497898fad981567fbaca5a905751546f15172cc0860e0b5d83fbc6e3038fbe552a7cb912817b58da070f6c9781
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	3	\\x1b638a070bfb769e97278f0f102122843e062bcb3db0b49e6cbdf5455e5d8a1bdc69ee830e54e9c1144495424ed32492225028029f02827c09fa7fcefef3de03	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x41b6415de80c1c7bd23e336389e7322422d96f3b512accb6acf6c94f31bf66ebaca728534ef0897b5870bfa072903c69f2adc3d80981c048132d28fbb0339513f4eb3c8660a7ee1b1df7bdd2240fea12b93a6696ca28d088fcfc263c9b369a57415cfb4db887cb3138b3241784dd3d9a2093e6199f1485a0de30dd6748acd5b2	\\x177cb70dd9531d81871e32c988a46bc71ac27a6d8011bdf7cbbc8d464da37e644ca2a2d9a70e57d52d6e736cbf6e6d99225f1cddbb30dd68a69f37f48acb6c85	\\x0709c9c0b0b4f68e0d552b8b8f3bd1eb743f001fa534fe7f7da7dc695f1f900b97a84225741d6366edcf12dad9beda916daab954644f3099c9ff14f06febf5c202a2ee00b22383354bd8a11267e39956b4c6b51dd8225bb4782e355365ecba409a17898d3dd5ea0150901283e300bc1ba5d205c5e43ed8e0013c17c776a0c401
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	4	\\x3b32bf5b0e13a7137a3e359eeffea466648c0fdfb98e31dcf641fd2396a66aea35cb63ddc450d99866d5689e10ebe861c13bda42692751b182f90834edb56600	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x4d4ddc0631ae95634da70e2b9f18dd65aa63b83b435133f1cf82cecda7cdd1159f055ba1ce4449c156d50290940b6b49fbc957aa853179890a7c1e53b123b3e73be61e8391bd30bc38b4146b5c63cae88aa13e5e6df2466fd612c78f9f7aa280b43edc61be82070b954a9320af3e2192653714a744668b6c7c9924ad5055d918	\\x61f7c36e3cc8eadeb0123dd925a03ac05ec29d9afc55c1b7dc61cefa03541c5f0f4047a430015f998ea93537954c62c96c27336f74717940c9e8b30a2feea5ce	\\x6a1f61e9a437d1f88c04cf2a18a630ecde6f5389e02f500aa9d71e12ee5fb053f1873edaec560b3adef6747e4e62d54684721ddffc6786c59ee85c09cddd16968cffb99ec0d2a9612e54e3c853bcc7bd083b68d7b7fa4f6a90667b461df5dba8919ac5d94cfbfcbb939a1c81cab4bb1c2ad53646b380b1e883a49c381e116305
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	5	\\x1084ac7a6db86432b9c9e85645cc5c94f43ed89aab669bd0103e7761738edb4ee4830f0130c0bfd431bb2a817f8b86cdc323b99e541275a5e94b88cd56ca670d	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x634066e7484e85936d9b5be7ddad870660e0132343ba9abccee9031a4bbd724bd385523f64ddb81c4ca63bc740370e0ee745cbfd2c86c00e9a6a9c05d2885f5b4382ad085401a9abc97ee37b75eb6f272eb35aae3905b53112f28ad2a5417a0651e502d96262ddde5ad4653f1cfa86b7aab93208f0a179821112141f780a4ecf	\\xdf760b9cf17ef7abe1c74a67300c578cc6b09020bb858145b4fc0aeefce7d2e75bd84844286c8e98ba9879a9f16b0f321064d6b498d07aae907cc5fd4431f6a3	\\x28172e83757551c31ab6f0d3306a237908021eaabd74b16c6b57925c31369f793a299995bcdb1c6886b47bcb1d3f681088b8227df551af54be12e1d7d91a963d79903f3fcf1b0eb5733acabeb70dd0844bc4abad9affee0d2764dcf6ebc8a93379c2a07a22ca0499bf577c9970b7220bc373ac112b007b96f18446985a9047c2
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	6	\\x604a8fde7c2197df430cd6c4f3d534fdac26942e883c3ac398e2b616b28fbf047aa9ab702283ced8201458f41a131f3f18aff55da0c526ccd164f50addb2e509	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x21ab979bf9943a0eee82038788b25f3885271a21fa8092e66cfd3403e697ef1c53eeb1ab7ab0756284ec9268426384b836d402d44b46fcc6e577256e1ffd52b77ae9c283164b89489d1243029e6aa9dde9ca955968bd61ee2ad4ea11338094be404486de524c119a800c9df6b38c03fb7b5197b27815cb96491e4778781dfec5	\\xe9c3740824c1b69d7237755866a300df923b16a54ed62b882b82b1a3fdf92cc1ce2f0fefff8ae2b7a9416bd5e03cf252e605049bd9fc3742cbe9282f7385aaa0	\\x0cde40419b782b2e883b238bba02ece26505cf695dc46f4ca4b5da7fa52af5145bdeba7747fced2233e579a793ca56a01c6fb01d8886ce3335fb98ce91ba9e494c82ef514c1cc8a8028d8f2326cb5d856397fd8d5d5ff7a7aed8b1b7017440e65af7d04ae003e0296c3c662d17e200b0e5668e384e42aeb5147ff460e0baaade
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	7	\\x5a0a5448dd62436e1c2983eb43bfa27fb276b3bf97fa250db4789af76ab7f111acef2c7b598386b322d817f95fd25abfaf66e6d65337b32fc49fbb67884deb07	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x06fcab052502107cd56bb9c6e8e60a88059ebe86128bfddcc80c550735ca22df773e5b49c2159723dc5dcc4c1d30463b344d936b33d5e23329e2d2e499dcf6b7ea2dbf1062ee9cbc214492965de6fc59ad44bae4260061b580e6275f68c9687848ed400aee82c4388c399e7593371c7de61a329720ac9250f8f3c8dfcd60197e	\\xa8f69aa9c3a07fbf0bb474ebb46418f9631902b0500881ad6956b110d07d45526bde95ced2d4e034a31703565ad66dcbd4c2f18eec48e6d913f95c97335cf775	\\xa7a5ac79e057b45fa9bf8cda1742c9f2a1d170c21c3f1454bdecdef885f9df08371d61658ddae96f23298bcf2b6e243eb81f4969fd230430dde47aff336c85c337e9e572c069a1a14cc8ac2793cf7365b9e442155c0c6e5bcea841dcd786cce5ee712e67265a0f475bd93918977576b41f6b0e4d9f90d9586e5c8f1aaef5549a
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	8	\\x67f9036a455b4ddba1c44abca24cac75bf227c21e93b96cc9625a1898a800ee94c4c8eba924afca61e78c07aa7e365b3e2efd596384cce98eec67f2e33e3f605	\\xb6f78f842e39272dcab6924a840738798122967b52c9090ffa63051b5d3fd8d9ec9275d77ead5fd5fcaea508ded8b71fb4395a998f6f5d6bfa5855c0daf37fde	\\x1b802c2b2c8c2b97a371554735c0600021375d931f0c0067b125c63692a9fa5b3db98ffa2de2f7d883d0b1e97398edc74b532140a4aa3613c29bbf13a8098f3dc546bc39f2b3784a5930ce3191b682be7ee4cd9e81eab916f64b4c15b673db434d85b0111110189c53e89a0c3b2ffb7109c008f94beaffcae3147c91c3f68b55	\\x9d983297d40ae40f2697dd966e87abe243cbf10a44b772bbce2578aca313f48a04597ef0fba4f6e7f63179ef8017e03086348e6cb9d5ba0bffd4a8163cdb99ff	\\xa8cf7d7c050ab07c1d521982dedf01e34992976ad9ee1e76619c30beb8a42d3917982703cd658ccc09815ab78f780cff3a4e992f98900c1da38ed9559bb3cad4c69c48ddfbd7cb33dcb7c15410836c6ce419f554ed4997a84a871fe8093b013243ac49c6dbbefa13b217cca9485d5d9055945a3be4774c3665a9f99794503adb
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	9	\\x406dc0986d8ceb325cf2ad20c62fe47825cb6811845555d2819e9a343016f38b311b7f5b9cc959b6de110a516f7f4b217f3a7833b738c9dab5c853fd12345009	\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\x1bad4cce230c652462f65c9619933732ab9d2ed4d11437175574503c1fd82a8c3627d27e58f1f1978bae0330d89c5d3704c4d9fa3964ca5f82fad9af8b59191a0175f9c0feb4c2af5431c88267d82aab0899b8835ba45b770c5304259adaf74b8cd90a938582ae25114872e40b9f06b87466ce7a4f4653154c82da0557dfda3f	\\x67e0739cffd3cad86441a6cafd9cb4ad4bf629a24c7610ea1b19962c35b322dd25ea92a4bc5c28436e25dbb076b9dc4c6bd1b4606684504b52c83614a0b1cee0	\\xdc78ff45e3d814ad5fa509882a651acdeca5e16c1c09da1db312e85351d3c8c6597c975b90cd199b6809a4e00c7472c8b5708785f886665afbd8d426b088de428e256045ed82d6e9e140545982a6e60fb6b4e626928454ea09b16bd8bbdaef024db1747da1f41b111e419a01a4aaf12ddd485b1723520db3c2f01220b9bad498
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	10	\\x548c1525839d580962b0d84d709e2c7771a6181cbeabdba79f0d5110d41332c9e7fbde3e90419af06bf88315e3ad21367f4b23f8e55f8f3d952485cfe42af909	\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\xad5a9f831edd9e8a2eb957c2511010f0f5e366603571abfc85127a881d5e4888197f13ebf5acbb0af56b7641a69c4f09aa313f16da750431db10ad5e69787d1bfea20aa6f85ab37a5e1f6bf6cd1990d85ba694ea65edf2110716d235e3a09232c58065862c25882492ea34a73147bcf5a4e467052ff8619dc3b977dcf0c1a5cd	\\xbaf3cc04830dca18acca93e1582f70cc512e438f8a7a31c3841474068fdb05971e916efadc5cde6c2c68e9d939dd23449f9fc85a954d212115712f40e5c17f81	\\x54bed54bde92fb4511916f7a4b26b2ce493679656d7deae96e6bf0c7b0d444883a2d239ac2aed96aae28584161fe69b83f05efbc5cc2482617ba218ee749ed709c26c3179a46aa536b41fa75cee7f76d80dac141d042c7aae04b8acb93227f017ef0f24960cca0801809692d32608a3ee35863165e61ce8fffbbef6b44951efa
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	11	\\x50df37c40c16303ba226b61b8301be74eabbc5cbe06919b966b4044fb9645a6a4d7828c391e5d55e699bf4f3079f879e774aa6cb6ec25566a371a7cf22ff1f01	\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\x089745c3b4f7383178c66c1d9ef638a32416f0622c0689b9f47668b95b4202af297942a0cd30fcc5093f13bf8111d883103b0989e351ea94d9276b1ebbd7a69cfc4b02dd0a2572671581a3afbaa8de018669b269e5bc772c6b1fe5176b6e317ce826937303c7f34f09245186b48f4bc07532d452ab896aa2a72fe133306cfb80	\\x377bf1537f4f14c9fceabadc441b7e3a32d4457e56a45b5b144b9bfb67e23003825b0096303b039aec43260791bad369155529b146c1ecd8c3b18ce2457030da	\\x402fb1e880afeebc0c79f7ab79ce1d2e0dad47ab33b7adf7fff9585463409e4bf5abfcf3b783c86535998a40bb9cbf9a723bdf0164063e10c218a9d39bda69a131030f59732852519d4dacf8de8cdbdc14ee46dae105a60c84a13f92bd938e067189605f3fe145fb2654c5021f49877ab206b0e1b9d10adeb8e28b8d502ace27
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	0	\\xc3ad8b56feb24c337d28d8c88e6038db1aebec2cf145bc23db02b28dccaf925679635686011e31e639a61ccae5cb84c2bb61b546868c65033a5ec7aea8633803	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x7e296520864a046a652710602bb0178057a497c335a41801131f198f428f7524ed88f018a3dce8341f90ffccb2cee1f89e9cf7267b860de7c7681d53887bb17249b535d2c9c5e22ec7c9181a006e94b1a9cbe87b9884fcda73189a46179185ef4358ff5eec35f3c484a07bf42b21ca0afe8cc39ac48a4ba9c3b5e962a6d8a2c8a5dd75684a8ef0fd826a35c89dac6741b862e9e58418872578c81911a1ff04e9455052c827ac919cda520607449f1df49835a9a9bbc5a5bb5d408c46497ac7d25721b915887fe7ada311ded80d90bd10abe2b014e180a13b43f6f898e6746eec25c9796612654629e666b5f3818f852ae372f80587c163ccc9523372b6604d16	\\x7b9d9e45f125838914b0619d4e3f1c79a8f28fe2589fd1d2b34d128980fda924aefc2d0ee36bda420d06984059da6edaf54318d23fd6214d7ddfd0cd6ae43440	\\xc053aae38067de60cf6ccc146264addef7abc3b7cf700097c155468325b8ac8cfeba5e684f95dc1124a22b166e6d98b4952234bf2c9de991c9079d50bb2e74e3d9f4374765352bce0b9f654983d3f505a8429fae6778e15c1fa8d5ced157f6ec5cc9aa61c8256f197ba0ec9599b94d990808aa34fa19d9a1f17c2cca8cfa967ae21f0797b1e707d4a5b7b2b0c88540a822ce2b0d45f8dd059e9873cdf144a872827d7a59e62b31cce875a2b4bd64059c3d854eb1ff3dd621070892ed3f8cf0affee9d64d8226c8ffba0024b1b10bf860520497127cc4286c902a564f59a8345a437b1db8027d833c7ed322c0204a8f5d1435a146c7a07318d05de5e8f21896b6
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	1	\\xd2e7b2f95b1d5991eddfb1ac0fcd2df0f6db1c232e670f4854fef5e4c18d14ea5eff6cdc3c309dfc20aea57bc72b2f9a7c491e2ae1f9cc65653b1a86874ecc09	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x7fc6275e5a14e3c9b8e35deba4f81e852dae18b4a5af45416153eff8662184d42281ebc409fe0ecf01ab4cc94168f5a48af4b4b122ab52fac1e597ba2b6ffa18195f996b4ad817d9c6865786a6d3364f3d3d3d1844203d43cfd63c89ee41aa5c211be4e8b7a29c00a6d39d127763117f3bfc97b37f9584d001fdcd1798a185d35e1fb2383b7b01d7a005a338feadb3e5cfbd9ebf1d8420069f219c3b735ab857b7709b7713bc351228875d90574b575e3a21096d473a2c4909d809a577f97502146429e657b0ee8bb42f24cdfe8400cc3f019cb54b2b3a13fd20767d779cd47d69cc4dc2e6dcd8ef6daa1ef572ecfdc166dd14f88f3885046d48c0b8e77c9f24	\\x458214b04652b741709fec3396914852b5c11cf287c6ca48c84134b17018b451393e5b8af62f27216644f722abca5763a966aee04e44a44bddcb16e97934f766	\\x34b4255e7bac789a087ac5add3b3eacef3fdc3baca3bae83fda734b81f9809fde5a1a7643d6da956458c957f655deb45df78b054087b76c356208a4e214cd864c7bd357df0f3387dd3e535d988b213c8bd71d43bda7de58e60010918cda8830ed9df5f74f11f1c596366a278831bffa013bc7a0b45045c099648cd83af7ce08142753a18f28b7c133a7915dd00a12ea5e67b85dcb7729bef9eccc95e7a5b08a96cbb8641be5083cf1e4f9b0bd75de8ed75826b02a802669b4100165945652fe997f7f4ae587da26635c4b87070425fed63a3c3b8207e92dba5f2976af33eeec44936fb0e4a733e87ad2b3cd8581a5058fc1440c7ee4e8032cf4501558d30d992
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	2	\\x9d23b359bbc3e75b732369f56fa92e5411802053b052938624553bb117d1c80f2d772fa58115131b840035e1a03097c2dd78b1c3012d42b1d5fd512d59811c04	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x6f0c99c959a890429bef5746281112dd78b57a774ae2c4d1678e928b4b1e303e437a007fc1ffd8be72a32a04e3485aef8432d4d764742cd1b7ecd6baa7a65dd52caa0e7baf418a6c9e56fcd6865b72627448c38842d3382b5c5ceda1f7740eb7ff6a82844e2ec18b97c44ad4d289babd51b4477a6b3127eafa81749ced176bafc9569e8998c9d5f9c480e5dee9204e8461c45768b49ca7cc1897b750cbf6837565ceb33cafaa5eec43dd33ca0f793648449d83c9ba9f7db3943b8f56b595df6143f11be1e6061f12aa6a346af0d477b6418dbb8b3b5158b35ee17bba348bfbe1edbc7c2d9c81157ae5e697e066ddb7811b9ccb0e28733d7213375e61f5e178b5	\\xc8812e02bf62566e75496af7e46bbea49663ec9fa43182523170001e01a8de3199b2105fc799614c6e425c5f314cbd85ee2c3f623499b5bd06fa83d95b9448da	\\x9a1f05acafdbd4b97db1bb57c4c61ea401081019ce8caddf6cccb235915a005822b3cb42a876dc40b0293a97c7a4099548dd992f1627009404fcc415c1e1b2c247f83d64b90fef13308700f4da1bd73caa927f1a5ce0ca03abf4dbfc7b736edd02c2a5f70a37302d62aea67fc4052e50c5eb9549bbc4a5eca655dc2a0d6025efb53bb8473fb01de04685f551db9036496b45b2b0e5c22a072eb57b563bdcf26c5daef38a6e51ee63658d2787e0b1cc6f3baed5c151001d8970dedd8196ba475adafa44372bfc961de4b140b380e408ae13906b710d96e2f2f10337873a838add9a8d064078aafe2302a3ad740208657a0c9455501d517e5bedc05edb5eb7fdc9
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	3	\\x5b136bcde1a736f88b4bbe2c6b19da1efa3a0993eeb896b326f45587cfa74f89b39047464766e1c8121ba183932befe7b077b3dfd21005fcbcf81488e194860c	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x86f3a16a3e0e301f7d36b946a34fdac0499c680acda0532baa1483b0735e6b0797fdcb2659bf0df39924943defc48238170b51e06be7e3a4677044c1318f6fce55cb71af93602112df0acd01649bb115728ffd4c1be7f27c22b0b29ccc2b011fd37fc4e56ab919183b5a019d3419df50a2b4662071032aa2b8d28e1aab532195543a86485e22a692c8edde613c5e8ab982dfcc16dfd6f65092076d14993c5eea3874eebb42b5cd029c5a85aea3dc8e161942b33bc6e296af2afefdc14fd13f9e3470e5f3470e752b434477f7c59f471ff849fd3481dcd7e1a1459d05bd32e66f5d7d194f7034dea89f369fae110e9a0cd79f63f9f8f8dada284daa32d43ed491	\\x7a01535d46b90d551ca2d668c3ad37c7d4c9ec3fe8ff24af44f188dad650047bc1a91c8dcf5ec172f89b95e7736f7564e19ec9ed7a799c04d203bb422eeb220f	\\x6e49c63d03230cb587e0e6dee3ae8f6d037736ec56131e1e893c5ba8c06ebc219081fc29b800ef8df37e0cac7ccd0c1286256f17169e4240f4eeb4d889ecbfa38ba6259d5cc7cd0ef6e3b327db90a617602886bbe4c0966c0d50aecb191f8ff7f1c02b7b2365171b429a4d6c8a7b1c6c08f350dac992a2c541765fe3e9c334707a66be959994cf27b18e823d59d786d04fe05e01fb889743967f7160d18dffa359259c3d24721ff6af58d5ee58ab5792f27e68d53cbe132f7d565e5ad3b57e2e2b44d096727aacf3325ce323209676488753ccef7f5e057b879a66d26ed62d12c1c6b081102c44009855800284b0e35dc6f2b867ad2661b46e4671fc74ea053a
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	4	\\xbc64045e8dd32c1b17f792d759c615e8ecee1ced2bb3dbbfc61d0bab9790916b7e65ccbf3fe831c747f913d74723f9ec2a3584a6399d890882338bcc8424c604	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x1138ac318d08ea3d3f9e62f07023100e29f178192992acee3aeee29f58cd4f64a69531ed6496f76d6e6f56dc68d420c6a2f7ca8b190d032f53da19fbb57468e50e606d6be89d56d6e7bdfb9a756e244ce36d68fa1df3534efb57ef8729a6797f8c5d7b7c808017cedf63f3fa1bbf09ab86cdc0c3429256a563aff4879ee9252223bb3415ebb280c34a55763f6c9a00e6b1ca64b786e6b04c6e241deaeabf05604bbeeddc8b16b568a126a76c463522fb7b5b210f8e48dcb7ea0ad1eca8c9ab77ccf0c528cf0399f6f61a037fac1c33bd55e1ac0b53f1ea28a644110ab2a9849137670dc0761956bd76ff189cbbea4562284da8e249802f9b4d6dd878eba33850	\\x2c79d598233d77bb72706c8dd3939a92aa9ca954121689aa431fa0a59c168721d4d8bfbb4d517ce4b7d88094651a19dc5053dafa23469ca009539da8eea2e5d5	\\x3ca748e7c077537072a5f0148ebccc2dc71dfbf5f3ed7abb4634b5c6f714b4bc9b95c92a89ec162e8d22dd16618ff88cea34b120db0da675d60c974a05bdffa5e403c60c3610d5fc6d0c27a84fa92fb6469cc6d6c3d8d1be6277a5098847fb99be6a77d0b368897f092f6814be176587112a67b98cae84bbdaac2ee49c4a7143c571b88e2a8c4f13bf82758bebe26c790f32c978e46514cadfe3da66af0aa4fb87d77603e0abf5531bc9a06ad3fbecd2b7c54636ccb1aa6840f51deb09f821df5c9386eb08f7d333e544b3c06f905d09c8ddd9e6384b49df01f7167fafd15a1f85369a3a148046fcecb18c30ac752ef6f65727b9e18b37c5e9a2bcb79c3d179c
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	5	\\x0d273784ec78c7363c171c493d0726928751d7d1b170445b366290ddf78fef6f620697900ccf2fff87f6787ceb2629e9a1d4ad98e570cadc80d745391979e80a	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x0d2313334985f08b5405b7c6d2a2ef2c05b73856e3c2327b48d1a62ead134b264c54ab9306884f8ea1e3382a388511fe61f03e93c4f0ee7a92754992bce925a274e4ba5a1f6a8f0871ede513d6ad2c5330ef19fd749621d950b4069900491e8d6978302ea2f8b7180eeef0be6f10df93095343c96f8d4b74f23a86aa74976c06037b848e1a5739bbb48c8134d7217691025ef7b737d132a80d5e461b58c144537e5bb35de953d49e6f73bbd153043f62e19f82ca1ab44736daad9648853ffcaf10b016b12487d386d85da749e990a4414cd301988d1f422a01e7c521df0bd2bb5b5cba2dd12e9225abc80941b750018345c14bb211070623eb58bbb0a7e7550e	\\xe7e457472c09672b47a1ad4164a5271060daa7c574df698a670b42cd6b2cd177abbc2afb3ae8a9f70a0e4f6e10f2d1676c35ec3de3d962a0c9284bc2393b5e08	\\x6578cbd441576d34813e6cfd2ad9c59573b677a7bd2406eb99a150302d47a2eb1e14dbc8bc621f4868a474ae30b7743fd7a3a3530a71284362acdb1c04e1fedf3cdcdfa754a85673796e284c0dd43e3536727e4cd3b72553078f7ce9de2f1979746365358a43cb96ea710584393f2acb8e78a2f6a77615b9c8917e36d2e31259425ac3f608b98b3ead61783aaddd959f8b996afccabe134015c47775a3d3a5a54ebfd4a437ffcd9087a60498e392cbd1f8af36134f25433f723a9d5bedd41cd054cfb13fc0518b29e109221039b986b0252c20d6342f4d7d1ccd9b34b4f5437e820c79a8784c30c5a40f495ff9578b4acd838d0578f345612d841b9a90993e99
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	6	\\x5172649889aeaa057eac14e4601214889dd5685984b4b7a41d97af7afce3e37d9b29428ba1f1030b8a9c05923b68a1aaa3e7f3e8d5351fdb880ade1e3911fe06	\\x71df9d5356bb68c5b91cd1e38bcc90c84307a7c219c7c624e1df0dc9a2ae5d966919ff7cdb9a8ca7da930f292f109d2d6932111a642b9c99799d463e324512f9	\\x059fef73f2e5992ee8e26b889325330822659227dc1fc859847abddbc3543142ec85a18685bf4499b15808ccb14e0700f37f85efb40b01f90fca5d326444d7385b57ee6097d14ce96f3d7b9ea234eb897921690cea4e074aec4fe1ded59d1f12d0e99561af1eed130c04ae53d9adbb9ae3a22887bee73d955cd075514cdb138bdfe8e476acfa4743de2bab06d37f899e511d92f502aca5cabcc142699bac7d6721f72b76b4d57780b04ca7ad81d1c9d827064397fecc4dd8c5eecfa90aef3d9288512b7f2aed10398f20debb0475765d21abff2d0718165c3cdae453d5706449fb49c8f03704546c70900017f4b398eda0d01bd51af98bf94aa2f34f8b1d2db2	\\xe1d4995fe9fd1497f3da90bb1a9baa53ee25f44467f85b4c53422542607d82ebe8cefe904732e830b3ce6cfb91f55af3e3738cd68abd746d98c7b933176acb6a	\\x0bea865ce24d3ccb1b3dfca35f5a35a1b27fe06fdf7f4eab5708be976e78b3f6870a51b27ff41ab0c294f93052aec81c4ec21f1ea80bde1716ae49669e26e675e5cfbd95fb13da574735e33d6c594b5136133d9979b96dff7f124f47a52be7109ebe581607adc033e261eb0f60656c909c9e12b9eff2364f2a50e7e18215fece0e8cf950df2f3b6a6a8c934e2a4763209402d7e36d434aa3c33262f1065ca3374e045d715034cfd5584391577dbc669135749a74ac9af73053fb0a0b7d0d4df4849ee32594d1c8e820f2f8e82fb30e42ae839a35a18633f73131d06f233ffaf4c9c7d68bab05e1b0fc3e9fe200c2dc4f44821df467714b5bd3f659aff104a003
\\xa9684a84add6bd855b5d6b2c7172ee7fefa47a1b9a1ef1fe93d27cbcd4795a3f11fa4fdc3b030d220e4137b98a17c2a6a49f0289a1007e95001eee9f6cb90413	0	\\x6297c352ddc6f884935105dc3aeb0b97290f57e07e06f0ded3b875d789a0dbeb1643cd442ea14c3d6a930ad17ed8be62b6f0a8094cb5dae7af70e37dd7f94409	\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\xacb8e635715d1ddbae0ba4a91b955d8dc6f9ba4ec501cd323ceff4f24406e1ddf6363c1a75a8f85f8181607454cc06d75aa18377885052f7c92940967789aee5e6a2728430508b5f5096254dc637a1d626b62bfe3aabfd37e9a9416f80e8283922e50f66a80d1175d1d8962f7d2afd6dc4ebdd83e7f32f234dee36d333cead82	\\xfc3cace89d9e4e197dc508c307f979b18a9c33bc1ab30592c38d0d2c8663c5bde7a23e223a5ed01b9bd50c61f78325b065f266df30f1ebf0bb9820b53b78b63b	\\x28b6814b9e92279cd1414d0ed0117d58722f5fad5eade01aafdaa71c538827a126517115cffc415c9708f7cb6bbd2144a94863ad2b12794644f173f1f479a0d05ec9481dc1c188f7da87287b34dec74e8d5461dda4c3d7c1a3fc9c56e67561e138f367619ea1b2fe3f7a186069a3504f5452d3fe7ec85288986aa1c36d2547da
\\xa9684a84add6bd855b5d6b2c7172ee7fefa47a1b9a1ef1fe93d27cbcd4795a3f11fa4fdc3b030d220e4137b98a17c2a6a49f0289a1007e95001eee9f6cb90413	1	\\xef27f2a47f662c5f4e29a0a868e3c93012f91999a620d8ee6b2dae82df17cc6307cf3616479d8c59c87fdb2fd757297c075fe5b4cbe004d0a223f9a6690a3304	\\x949f6345ea1cbbe748f5361ea110eba7bc96cfad33e09cc5bf730f77b2fdbea72e0887e6e4753f41d632071bbf48ed0d43053518923ca3c5676941175c1e9ed3	\\x566c368688fd812d3bb632d0b0c5ddf4be517d80eb2e76f7dcf030a70d2859d35a79b4c76f493ed84cff42102ac6242438d3d24f5a812bb464451c868f67a370c8072b32f71ef5d95da703e8aad3285e422e8dc93aae575d6331ca4addc9c631f916d3e97f043858bec517711cf99b61b7262c8e164bf49bbe724a84bb4213fd	\\x4ea2f941b84d50cc5dfe7f205d795bbf5acdbe0cf6652e5e088444886b435a2492927b348e1c683f2eb9703afa2293d8f7313645778edc7b3a4d4281c2c400d6	\\x956d55a922174ab7a3a2667e80fc65fbba5a7239fee7fa79a2f2fc6b60566f7d10a9da98b959ba23d1bfff4a1a7fcfd5ad2811e62133a8a8e6ab8de569e61d3bbb8a84d247e0691e5a966448b49afb28807a0094ce7f13e6ba814f091c5e8ea464911a5e525302cdb699532f22a755ee101bed82460957a3a38decd3e3b17020
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x82bc8410a806fcf6d0f1d1c300a44d63c58c580c6d41ae44fcdc9b5b00a8639e954030efdabe1b0f50915b6c0043db4b973b12433f665f110e6e8edf7707ddae	\\xc9965bd6de8d18cd0ae7dfbc87ebb3d89b62579a576653b76434b59c717c4852	\\xa8b5c70d00db0c95180abd97707d1c61b487393b97b1fa50dda081220aad26819cd1f1fd73a268a7a6bfc08580316422de862e24cb267e747d52d2253a1e806c
\\xbf78a60cda958f4ae2b89e1557720988c5d392504d325eef10cfff278eea4a9398baf742bb8edaa3cdce6a1e2da510d96f88f46e73703f7ce598ebc76e6e5d3d	\\x849aedcd8da629f5bc89f9fc4a66c4f8fef816399f5fb01035e5bd76e931140b	\\x7116c066d259cf2793284754d3e6f4ebc0ca4ce5bd60251dbcd1c8fdb7dbf9bb482e8549691c6651af6b588d7cd906287470917624d9f607b622779fa9770db0
\\xa9684a84add6bd855b5d6b2c7172ee7fefa47a1b9a1ef1fe93d27cbcd4795a3f11fa4fdc3b030d220e4137b98a17c2a6a49f0289a1007e95001eee9f6cb90413	\\x2e05a5461fa38dc3740b3bf2a1fe6aa009ef87edccaea112775f24df3e088933	\\xe8587e4a7eae13f1adb96a30c6458515860903e436c6ef59529fce9d77b69ba562a8eaea24654cdc89bda41a6c397e546f36711e3f83aec9af3fbc7496347f5b
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
\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	payto://x-taler-bank/localhost/testuser-VPwFnxed	0	0	1610108030000000	1828440831000000
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
1	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	2	8	0	payto://x-taler-bank/localhost/testuser-VPwFnxed	exchange-account-1	1607688825000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x824bf29c29f53d85691e0dc41325494cd80fefb69adc8fb7c45a8e8f7a729c990d71f6cb123c667f068963ba372c1a6fc1f304ec4ce51014b6ba95b5f939a61d	\\xc7b0efaf2e440c85fecb226b6c17e8b584d67b6bc8cb57396790b17c7be0d6e8e02b7531d9c406be089793917ee6782bf3c4bee95cbbe24cdd9be1232470e543	\\x913f99f4d15cb7575df5d016528a05ab56a0a8620711992101fa24585662f6e86eac7a2207c72f238766d7c4b47614dae0f1d63362ba5eb5da9cf5995d74389cb337cd43c1da3b96316fdffbc34ab1c25d51bb71b3df01ddf03a3b254aa4a5b8e2eec643d995f82a0916939c509aa63a2da907a4d9d0322ef6cc43072207597c	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xc58def99b2da341e62db01894c72dd8b9b0b9fdffbcea7036810c520bef898445c3664f2865a1903ddd2deb7f1e86eb2e541ba8f39fda48160e2e50f71a59b0d	1607688826000000	5	1000000
2	\\x5ced0d082d95fcd336408a025968757fd76ea8f91cf0c4b2bda35a1cb648bf4a33d2a68db5801d2543242e088681ef2d10aa1d5f938fbc0f51adf466c6f74ddd	\\x15cd172ff9232ffc8792383d0fae13eeaaf3bc40676928bf9b566af80224fd727cdadd3cd3cb1774de2e577596a84f9819fc4e791deca825383fa2a9fd06ee26	\\x2b1cecdad4419221e102532fc6deca61695fe1ba187cef627e99f5f8356c2ddf58f96f6790248d8fde17dedb3a0504b280703e6b48501f03f2a8c2b72a643c20e541e287fb89f65e6f4691ed43f28642081653dd1ae6b8e2c704be196a1cfc6f4f7ed48bd4692d0eac4b77d8362bbf7500120c0f46138d3d2ecbdd8f552b8540	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xd9759308ebd10f3aff3ac8d2b5419c985da188d0e903ce3050ba7fc2f394d4be73fdb11ee1df61ca357c30b5e45c64a310a07d0939510a9423f3e0ec4dce6006	1607688826000000	2	3000000
3	\\x60a52374f3c5e5900d679908990f01f9b47f3a3ed0343553a6e6901ec1e009db975215c6ccb9d847c3dfa93530494ec18123c37f661e0c04dc76d04ca54a5fa0	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x62298e16c16897584194c081121d112c0c354ae76281fb7b82691abcb3c9312eb928aa6477c007933f22f54cd93294dbcc458b224d0c7b797cc4f830bb295503c7812ed9e0bdeda72507cef2d952d0ceab93ad98be5a83ff98bda3e42b2895bdd5017a6537a17e3a6ee9b497e7e711266343d205ced96e00e8cee74285234a39	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x89d522e41bf9277d69fa58440db720f7da47f4a80a736b5d56fcab13f7762f697275a0626ec6e5cc2fd0d6723510d7ebbdeb7f7fdabc643dbff66220deaf5c0e	1607688826000000	0	11000000
4	\\xc13c8a45cef6960cef597a57ce9fc2828cbe9feef9ea6c6d8f4f2a9dc6e9cd29e7b8f9df2cba6497eed43170e26547358f8938335c5ba16ba97f8ce4a2f38be7	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x40a17ad0a59cbf9a5f7555ee0d69208cbe4691ec47f13844bc16df787b53c47a7e9012e3dbd55baa287fe574bcfc92300fadd4ac13e599e8eaedfd903ddeb3264413314f08f3b6276b0cdb5f841498ad7517f78117dbf66d0f6396e968e3b61eb7a00199d4549b91c55d248281b86c96e45dd9f53ba0210302e368517bb80f72	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xcfe8a78be2b7cbd3bbdf905279279e65a97f3304cfd969d1050018fecb5ec880d83e3cfa943cc4165e4f7c565740137e976c30d40f558f7c7fcdd917cf19b505	1607688826000000	0	11000000
5	\\xc1232bd66ab96342ff91cc22bdad970f6d6816fda3f531ec593226fc3100d7d5903c8df76689bb2ccdd68fdc9e77c54bde8b5b1414a1255c558571d9990853d4	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x6da03cb437a99f401b6a82614227dcbfd0ffa6072b2330662fc5b53f17d699265ff11dd13e86e183629e5ae774965589273e067630045a4deccf1b62e4150d15eda1942e8a1134c434092cd6ff3f8fad7c50aa40abc3b53308ef7b9f738fe79222c55831152a4a45c2b5a486c4e52c793458281affa0baf0c06e19c80ee39c47	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x65facfc4107a046c9f455e7ce3f466316820e30fcfe16bbe80462c5f3722d7c5b2e93e7d8c8b216d3e31a505b1384620c2b2f70064dcfbd8c4d693dd60909e03	1607688826000000	0	11000000
6	\\x9404a7f2828566f51e2e77a39193216afeb9c6b426dec793d9a911aaa09135d4e1dc6ef044702bd0b5b6a06f2565c20eb58e345d5753fcea831092047f8252de	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\xa3a6dc66105a34609ac34e6d470826d973d37830ba1383cc867f218129caafa6851f132e0da761945f5bd41a0e8b0fb1d07a1ca8877bcd5cef47f16b0b8d51476b62e24458556e348f1bb44a9cbbb41c82f8fe9ccc6d7c84e9d7ce813704bfe6086c9fa8e4dd5950c6143400b3362d42974563e5b570a29886e5bb0a913d57f0	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xdd03c91c256d0d55c9f0a3d5dfb5401d22dafa022b11ee10a6c7698ebf9b09efd9fca8f4bf833fd655c1a995a9ab0b79d31caca890d7afe7ec4f66e59bdfdc07	1607688826000000	0	11000000
7	\\x7d5bd27f15bc5d5cd5705c24807ca87698d40e15d6fa65db803021c1ef25cd71be3705beb0175d8b069bf170401c545cce79d021f317b5e9a111f02703eda7e7	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x4514ad06ff8d310d5f22bf240261015becb4b00308b4c027b7b49eade96039fde6ad9c743d3fdceefd9cb6bbbeea8397626f2ebef14c525636cef1874dda147dbb3ab456773cb29012aba8982dae1f5733fc72e642e550c00fac112fef7ffe69c6960e5ba5d3cce4e519bdee9f0e02e06271e953d4c435e64cdca193a49d0093	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x492509133b8c64290180fea334138fd9809f97e392b1dae23c5e912d98d9756383951e5ef551bb5b547ba431c84f4f1f7e6a1fb7e3056ee4d4f6c99a2ff0be0c	1607688826000000	0	11000000
8	\\x51338f5efa5ca7b7969aa1009ae8f9133708aa0efa35c9d2410457ed1aa603136e5c7dd162168a06d8ed479d70b8c3c0331eed17a6fa442f1ad48f25302d1820	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\xa50c18ec3f0604b99788215b03a12b9731d9ca3a24f5c116d5657568b81dbbaab5f83c101fe03cb20b51d06a2a6cd0c5dc2f7e2ca9b0d5029850870a552f375e634daa359e41f6ad63d20cbbd2595d1d944557b809ea5253f71646dca2ae84710cca2497c9805fc2e8e27f0872f67b6ce05efcc61b65583428e646a2612bebf3	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x86c833a778a8173ca7fe1349f39f930b9204ba085030b75028af1d4885f684cf97955d9a67b13144ef8d4a4e07253ff48b79724044452d0543e0bee825932e09	1607688826000000	0	11000000
9	\\x398fc5e67b6b14f6520afc009767899adca5e37e76151519eee99009828ae1f72073e4234834e894542e6202113752fb8e346ce9ab177d382f36c1fdb0ba86e0	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x26ebc2b7f9b32a572f6e61e3c206d71eed06da32c673ad5c66b3773e0256cf45c4dbd7aaaace666f7aefb11e730a166d893ac7ca6386f05d2acdd2681ca1a75ca8690506593fe49e80cc63e005f464c84d298c976e51168f95f7d4edd318e116c8a764049fd9703958183a6032df71d530bcba16b0245674db130302ff9e80f9	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xe82f5e8ae64257458e0f869f9a4d58d5ce50f7a82a34c6911dbadadbc8caf3e561ae2cb92054fdd8fe4c3dce52e2d684ece611283d7fcfa8e04fa7cef8f65207	1607688826000000	0	11000000
10	\\xb7880bddcb6292d88379efa68da5fddc52fbdd75318dd9df6f6509c72562bb4161998dea25537648451399ab5ba34da971303de9c27ddc51e5a228fea3dada9b	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x0804f8a07be620100e19d4abd4f974e3db5fe7a56a834a4d8f3ce52ceaa22d2eb8580afff7add1eabcdd3eb7d1336f073ed1aa343afad0ce4b1bfc487c11362cea66eaa5d822b026963686a5a40f3271269eb2a8d2ab8a7eb5991381ff4d1f764809d46351af51381fd2e9ce6d0f8de48b97a0467c5857ed6b9de48b9f7fdb43	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x948de65270fd88374c557ce557ffee1f4247a6ebf3340236b6329f5d5f584a49e5b90a6b9796d13ec0b284591ecd603ace2107173a78f6ad66b141fac1e62f06	1607688826000000	0	11000000
11	\\x37fddfceecaa085f6410c5cada9901788c732a6db4097b32f5dd9c902952394b14400e06b59ae7c16fea2b3c15df7718606e72879818311a4354fb050fd1b10b	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x1d4e49441bd7ed9418c06819faa0faa51c56c0a49e3daa44c0747f3a660f92c8c2455c7aa35db21e5fa549c5f417aea5eb77469ea3c3aaca31c02c03172f03226fc664396a09584face10fc5f78c7b461abf68ddc72c0711252e945bc47dcc82f81a3e8ce363e2bf8d884a5706f96df2a4b8296a22badd91b79f348c31418927	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xf06dd47ea45f43762486e04af2dfa165ad04625ef36db76af5c99803282b23200facbef4e79c33b528ecdff33520d8746a74c36cdb4d4b27944716d514aab10c	1607688826000000	0	2000000
12	\\x9f1f52ade931e51bae4c228397abee0c42d64e28020e8976d6ac28458a65883c3c9c1a7e7843cf15b74583eac0ad0707cd53c7d44f771abede4026b182a58867	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\xdb87c835505861f41e77d456b07c189b4e8898df0d9396f451ba23159e6754ff31f73df79976aef4975e3f2b0d80a6ca6e20ddaee25c390361ed023ac1f55fb75e5be6e5f3eb8f741d54b89aa105b60073ac2894e20d13953d71d7bf32bbb9b4abff4bf8f8df7c21bdcfa0966922babc568974e48499a71fb9fd47cb14c8ea11	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x01754951766e97bb3225e3651422708f603f325bfbd5ce82df815ab0a3fec727379d4cac1e3c385fd5eb32e6b027b0c15d83bbf8303cd06cfc6e7cf8d08c5d0d	1607688826000000	0	2000000
13	\\xeb07abb78f4c87556ce99a13a3ad69a3e84b8bf6d9bc8e4c3312367bb813f4abb0e1fb2d65944284d820da574cc8fb7a615c1fd23c2856909472c1ea0c468630	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x9e31479b5fc616a4120769b5d288dc33436187aa7c9ae488d2d1baad248c77b526bf4994bf6ce74d9c9e7b909470a8aff948597bc5cce7d6c0861dc1ebfc9098bd025a22963071fb5097f9fa02ce3f564f434a2ff41ecb5fc7276fb858fb8496ec991f050f59411b559e8a37f165c4eb4055d3e7712d8eb61566807044150ec8	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xd23cc3539c7b447e646d1fcfba3cb8d6cb0802d9365b3c02c6139a51a884349e028ff654516315cf7b84dca43f4657277e088372431f4ca61c8bd8c903121508	1607688826000000	0	2000000
14	\\xf87b68f782d3c1450b5b9ec9452332420d03be23cb9eabcc981fe27b4d4f1eda4046605ef14c51caa326af868cd1add16e4c49743d6a5c12c705ae70498972ac	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x1204db69042b799ff73c9bba55b249f3bdf386cffb0510fcc234ea28ee261a265d7c80b8d057dc0fbb148cd7dfc25ae8296a6732ec02373b599b4110a77007fec4185af425fc9182454254d07f4afd0138b4641b23cab664736612c5c6dd768b81ca3c4306b6279f4b48278131bac59639ffca6477a273733e2ad9cc33e2236d	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x62cdd38449a26ba05e1407f5b1cb8b02ca129ee95a25cf5b4f0d1f7f02231b1a47042144b61fbe4ec8109ad6d2ba07c577901b7c151a5f644eb70bdbe0629b01	1607688826000000	0	2000000
15	\\xe49b55740a620bacdfcace044e3e567bb88c0f878480e569754ea9f72bc977a7c56402c14050dcd3261de4a130cd65ec9d967fc8e670c5ab844d7422939a9d94	\\x3591f89aede6cf4aaa845ace772f0f7a5ff6e837b6c64bd9a9b163e4368486ab0747c36c426ec5311cdf84dc57391c1954c903b8395330b4a64a4d16ae3bfc5b	\\x8192c034827f5825a1e4421560bce62983515d316bfd6b1dbe9665a4c348d9431eb4b88664e2686a20fca1e4897b6a601bc6295374dc367799a0720e6af575688330bf8831091de8960bc0c3187e7ff7cf39b0d5565c5f4af503f0e408bb049f26f1c3207c7559b0f9736e3a86f30c2934f853ab015c7357dfb60f04edb617b8	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x60768723142fbe8608fbfc6d5f223a0224f4b8703e4d391a63869ad5fc7384d6b4bb21b6190785f2ded8f4673a8c269558912062d16541bb89277517cb731e0e	1607688831000000	1	2000000
16	\\x0823f2bb1444a4f05d996db353513d78bc07722a04a4fee0541b0859ae7b9071613d5761b4f21c7dfe0a0af55be732cd6d7dc09d4405e2746c89df7bc775ab02	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x95083b3ce500fe0b346c57109747a52f828ebcfb01a4fe8cfe4be61d50279da6d0a1fc5335f1c543cdc8dc9c4e716dce68bc80c6c062318d96e9b7b3f9fc891c8e8454ea2896738b98c96c0de19fab59a7bb28b53720fe51229d3d05bdb670542f397a7a1f23f5efaac58f82004c59e3c42b9c80cd79fdbea5d2b014d2cd5d26	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x6b6213cd31baa27f94802c61113aba33c6e6586d3871384af7abcc1c296e0a97b56317323ec9e1e87133fc88382fc710953636aa7bab39f0ba8f46ec481c4209	1607688831000000	0	11000000
17	\\x7a750677ec793c8880b2ff6c034cf9889014bf6c03640ff0fbb79b25e4e84be1c7ba6ce32bb1c34edc292bf0161d61a18c27c57fed00203a0cd1dafdc96e3dff	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\xad601a51286a016bfe287ca4ab0249c2bb8dbaa9d244f35d62fcc29ba58a85776cd3b7819fca8c2d751d51f8ebd80942ba0443484c6134f8a4282b080848b940db6b06923c7e7b6e10fe6bda9b2ef8eed7b71650ee60b2071dbc05797f14e9f4f0eb8758def3e0452f919f2b7c140aff7b44de4779d4340da910556983fa7c5d	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x25918d14fb83a1c2413d742ed7525606787090d32b65ac2d22442970ed577e18c9933b748653acd167cbeabff9ee3811f9821208ad7c98244c53c7a6916f9205	1607688831000000	0	11000000
18	\\x3515499c9c7b21decfd67144ef5e7fd3f11ef4b20fe8bf9f16a7ff86217d12a7a11d70642f8042a4b2935ceac8eb78057bd14b4d3b81a0eb40c3857fe5558824	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\xa6b8891443f7b26552e3292a6c5367e0d14201342f443b1c189e8c59b478e75885ed57cd07273c2fea38ded4bff4134faa49e8cd89300a81970484d90d6bf37ff6f496a901e937b5cf2923b82a6549c3730134b316922d6c6414d60f5838f57e7fb1fb425f20bb33e9290e5ea00a5ccafdb25d97ae7257dde3db9a6bbf0ed0b2	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xdfa3f6c7f7502b4ba7c69e50dde2eddc683ef14f81bdccd9aaa4269e5e8d8d22a2aeae62d4d48af2e6f40b7985b6d115a32960eab6e947b9c3cfcfda5dfc0109	1607688831000000	0	11000000
19	\\x88563124363c79af4084e88bfa6b94d06372a4058fd1471e64b62c5aa923bb0d2024e60d3156548848e049f25005f205e9abf5bee3533644b09a55bffb27d0c5	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x399f5c6d21e1b6bcf7d3cd4b239bb01326341cc53ddde39de9e62ce3f641edee60c734db5caeba5b0d2b36789734a312dec1928e06c226e2597bc62ed0b6c01aab90f0a9403d8564dfd5d0193af7a5fae7b5f2df04470eab3efd5da6e21e5f097c9c8291f33ac125157ac47dd63fac55b392f0d45511ba076fcea0f5e0f6c3e4	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xfd762d1d53f81c03b1f9ec24c07b031d951ec4ccb4f8b6aa73ba7680cd57a3ea073000869e07aa3a0b651ac094cc889a4a3193a0235d88f9a88a3870f650b20f	1607688831000000	0	11000000
20	\\xa7144ca5b0cbdca748066fbd0ab7b383fb9e230512ecff0d2d0328ec2254daa4707f9e1efa5c759342addc127a2979e71c50e46d5ef6dbf7f3a11f2e146f5abd	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x0e510ee265e331d4661356bfbc8af1e3ed80196cca5f7f96b25a620dafbd8f2402fadca0bddcd5a3b77bbd6fba27a236d4e8b80640b04f56d02f9c08efae31836e7274c162f9509bebc08945bdb1fe1d7f8c104b16afda36dfe76fb1db57a7d55da85bfdb4a8d53b5f809f7133ebc2d538bc88dc8ea52ff90a8530832a4c44ff	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x93acdf391d88965658fd17c34b33c86f70708f0e8a3e5b0c1a7c977fbfae8753b615ae0c15811bc4eaa58732a953a1517c99bc41b58da0aa29e72ae4da39a80d	1607688831000000	0	11000000
21	\\x78a42d871484cff75f624afb40330348ce83fb699711488553387c3d392c37b0de8d28300f95235bb43630bd71cb58850833c8f32539ec222e688bfcdd5acac4	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\xa918234a01b6e4f21d5616b7d13f172d37f1aacc3ed539b98c7076358a32bcf51c05373eae4ff2d817fee0fee423082b96831959f3eafe6dca58ffb68e496ea468b4570ce8349f7dd5a24fc1c08db1abef9aa1efa91d7f463c21d54969ef5c718be9543f29bbaa3a1a7220be2de0bce54a28c4997ff454ac4635492376b87e00	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x28e992755f9c12a3d24d3defdb45b5de92ffba3747f6ad54dd540f0772939a0a016869186d69f197f270c3e4b2931c88c85f6f870d743397650005d38d719b09	1607688831000000	0	11000000
22	\\x46af7d249d6d8c052612330691325d6eaaed305617ba6f6e76ba0e04b5e42d9fcb84500a37138566655e2ccdcd7d5425509392001e8d0e78a7b27046165cfd93	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\x8c435f67566070b647ed3bc83929b20559a6a1839f03f5f0e389d013d6819f1258c939406cca0f3425358cbd091539f69267b96a2d19f0e72129552f3147b36942c250d0f6204da16091a7da91fb278230cef8c76ee7261aef20c33bee203aba373f299b625b3b443d7a89928e042b24e84baa0c69bc848df65761a7d2cf44c0	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x4b84874b533e24d6ef43289d26c4f4e5b044ae6db13918a11f44048e5035d2037b70405bbd5f4b204490c5607cafaee4b4d60b7f19c7c67a52338129a4a56508	1607688831000000	0	11000000
23	\\x50c85507ba189581fb0c1be5deb44cff2959cd865cd2b111d86178c48a2cb080f357eeaf12bec88b4e3081ce5dbd5ae06d46a342f77a3db0a8e2d5481ebd982e	\\xeb1d62a31620b4e981623b02f11cbdc2166884a85a9355f032f09dcae37d462cf605ac44d84bb3ea0d0b3d690c2899f950f14c51d70221417f44626bb1a2d826	\\xb05f6c54362762e08cccf308ff92859cb48e425fc41090f083e8a62daaa93e1de140c77c78aaa92dc116ccdc9583e1d7e271b26081c74119850153945775b05883bcf86b4be9c909a38b448387181901f47a3372cbe07af424bfda55ad8059c329c06587ccf609e0681900695da2f72cd5129d7d1b8f89bbe845ccd8e9872fb2	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x1782595995c5af3409ed7b37d91449ce7be895e3dde8d081690d2387487e038bb06b7a4663e30cb2ec27f0f41c89c02398fcac402d1b7c927df134e80a3ffb0c	1607688831000000	0	11000000
24	\\xc1cc95b4c5df2ddb50901dc3a26b57eba97ea016b48819347d548606a27aee9a49e515178c380bb81654f85f84974dc7734ca2eec4b38f5098b6b87633c8d024	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x07993261c12295f44b5c7f62e5c49891a91f828d22435c7acb985d0f4e30dffc9a54fd79f2438faa891a98c33e0f47af2b6c593dee1e08ff420ba5a9ce2a0b1764340f47f141aabc38959d9e2176742d1b6ed1ef7778ebdd92fa584b2da8bd7e76928b9396c49b10c69dd041ace3ac630c5222ba6e5b346b441190ef13aa563a	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xe9afab66875c99ae96bc98bbc557dfbdfa21b0137fdfe0cd0742b99a266618697c961faee5030c9ed7dd6cc196cfd2d30e93eb859fa6b46fc9db6bc0c917f704	1607688831000000	0	2000000
25	\\x37207fcd987de4c661fc8111f7ebe416ba0f8d731b33fba157fb2d4337943421fec9a452dda63c33291862db705dc747b78014af5a492ca33bddcbd81d3afeca	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\xd31c51aab225dbfe98c52a4b7160359ccad4e0e1688e424d0459e18630e559f05741d98de8047cd91457aa248b97e9aed6450a6b69089bae1f1d9e9c659f1f02106674a40eba8446677536bd495881d75d266a3c0809c332d4926c75978205e041014884e05aba50fbd51e4ef950b55fc44e1991bc0e6294581c4fd3b491c07e	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x54b64b939cee749aa400ae585c0704a6bfe17d0072a78bb913f77ccc9ff0ea772895f391ceba87ba79c72a3bef6822c14cbe3d227fb1bdb6c0ea6d9af73d3d0b	1607688831000000	0	2000000
26	\\x60d501290b0834fe6a68b33b3c7830db516ecd845c942338141c0c32505a4fe2eb78df8fa5c603b055a539581617be2d9d28e5857b9305d7bf8aec9b5ecae59d	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x4287b7bcd5d84541431c70b6723ad658cd25ef7764f44176426ef3eca214d6e5d6b7d6e00ef245d484812dedf3177934b0fd3f4fa4bdf8639e854fee1a0f76065a11e5ee99bd1be1cfbf5b2e6a848f956811131526dee77f1371a18e0cab95b75025437798a228024bc8f10462086c872bfca505d11c0706f699571c655b99a1	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\x5997c7b891bf9a3f3f16a48a5990aff476486fa101f93fadce6f16f779076c0814ff5ed8b2f88fe73d41d2383e0e4cb7ca32a386b932dbf569417b39aae7660f	1607688831000000	0	2000000
27	\\x5437c95f46a906fc2fdb0904fb344c259a7134ab4c5d7d52c5f21b81424f5f1557ccb102b134f38422721a15c8623707b8dd662c06de976c90758ebdf805306f	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x6f6b5e0b3e831cac0a325f65e96073aa1fc64aecefb3016e68ba97548492caa3338862d604d66d0c03b6c48af0671dcb80c74bdbc3e2c760b36015ba45fb0041012282beb9d2ac11507f632769526829deb7fa9f3d4c521344b91cdfec3911c5c0724444f5ce6f3a03fad5f220fd9b54e9a6b57202c69f54949573dc11f5566c	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xfb58f2fee53f625303784f7314b213eb7da6aebcf7a2995569064404f119672450abb1e604d386cac3616f8a59f8f1642124ed4cd7d68f1ee7d52ec7f66a3306	1607688831000000	0	2000000
28	\\xb85ee4b59ddcadbb40e89f3f9e733d8dc4bab774fe7082c416da0ff5afdde2de9a4368f07742e29116eaf433f0435b197e34e8f4a3ab1181805c11870a3dbf57	\\xdc5027f183ce96e42ff3feab54e69e5f76dcc40222dc735c87716d6f500ea04287c85714c2176d8759cf7155612200dee1694d3a05b1fe9736b405d7b794f4d9	\\x67b605e176ddb54bca3a5a23ad4e178bf2c9dcdcdab69b7bac60af5c36683eda4c3f4b8739de4b1f3845f6e858e02b2d5d6a50ee98ccf61644716fa54da4ce5b1289e6eccae68238d5bee9852db244a8dcf3231277810b81e30244a2d344890825e62767a41d6d4fe3c8806c1c91fb5017888551ea24d2911b1b93d8a839dd88	\\x690dd77ca4e468260a5ae2c59dcf3a2b8b986beac62ad3cc254ce913cf6d2027	\\xa3622be7ca81f4a9a75c2d77a6db397bda3a05c54b532b3fdd43aba04aa906baff8d2979f2d57cfca7b3bd685bfd35af199ad1b2e5578dbd53ddabc4c6cb3102	1607688831000000	0	2000000
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.django_migrations_id_seq', 16, true);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 12, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 2, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 4, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 8, true);


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

