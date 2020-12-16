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
exchange-0001	2020-12-16 20:00:05.848638+01	grothoff	{}	{}
exchange-0002	2020-12-16 20:00:05.974167+01	grothoff	{}	{}
auditor-0001	2020-12-16 20:00:06.065945+01	grothoff	{}	{}
merchant-0001	2020-12-16 20:00:06.168337+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-16 20:00:18.75941+01	f	bddbeddf-ec19-444e-bbb6-34df73b39f57	11	1
2	TESTKUDOS:8	F95QVPXZR9EFX6CVVB80ABW5A95ZRAG9AN93DQRWWEDY6B70FCKG	2020-12-16 20:00:20.686577+01	f	5f4bed26-e693-40ec-b34e-21d7cf85c13b	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
eb881b91-963d-4e3a-96ec-7d51738cdbf6	TESTKUDOS:8	t	t	f	F95QVPXZR9EFX6CVVB80ABW5A95ZRAG9AN93DQRWWEDY6B70FCKG	2	11
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
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
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
\\x1491570ded37a4cc5564cc98ed9e347a953b758a047f0f6916e5ff7fe4cee302	TESTKUDOS Auditor	http://localhost:8083/	t	1608145213000000
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
1	pbkdf2_sha256$216000$kYAvD1GjY1E3$FmuIhMHNUAi5YyJya0wxBK/9bgBNQGhnX+JhG+ZAIJ0=	\N	f	Bank				f	t	2020-12-16 20:00:06.597394+01
3	pbkdf2_sha256$216000$9331RiS7mVPg$sgErfn3J/G2J9y/ZsICqBqcpANJa16UbFpFBW7Idrks=	\N	f	Tor				f	t	2020-12-16 20:00:06.771252+01
4	pbkdf2_sha256$216000$Dut8wxYa7xZV$+8wfHCst/8yzs/K2OS2N3G8hhQwaqqmRJduEq0edDAQ=	\N	f	GNUnet				f	t	2020-12-16 20:00:06.852187+01
5	pbkdf2_sha256$216000$aFF7OWnxWH0J$3WoNqWmfLVNQdNanA7LdMxsLuxdK+45UuiFhG6FT2HQ=	\N	f	Taler				f	t	2020-12-16 20:00:06.941386+01
6	pbkdf2_sha256$216000$DrK8tC5wcZV2$neNzkyzog1JL8Bp59akOPhrL5OSEUV+bFU02Z1WS4Qg=	\N	f	FSF				f	t	2020-12-16 20:00:07.0239+01
7	pbkdf2_sha256$216000$qRfHKiUQVeBb$9w71Hs7VW+oF0IJai2/+qPtTqCDFWkVJYWhaBfaH+hw=	\N	f	Tutorial				f	t	2020-12-16 20:00:07.105572+01
8	pbkdf2_sha256$216000$J8YbPs3ECijr$5mam9JWOjIx0mcnNLJOPpVf87vuisxtYtAXtQwnZqVA=	\N	f	Survey				f	t	2020-12-16 20:00:07.188733+01
9	pbkdf2_sha256$216000$SMwxEyGmCwZ4$6BKCyVm/IV6ft99Lc7OvyXGrYdUjUciLj1oXtgWtRgA=	\N	f	42				f	t	2020-12-16 20:00:07.6574+01
10	pbkdf2_sha256$216000$XVHbvPxuNGoR$NxqjsMvIC+Xg9TDKusNt5exKKBmDG1B8sp20HJAiZ28=	\N	f	43				f	t	2020-12-16 20:00:08.12724+01
2	pbkdf2_sha256$216000$sgHUyjaqTZro$hEOfhmQWLcEyfVkotJW8DVsP7fC2DEEv2+nuu8pILgI=	\N	f	Exchange				f	t	2020-12-16 20:00:06.690021+01
11	pbkdf2_sha256$216000$VHp3dAczMmAn$Jf+XvVEqoSFnO+BEAI5pg+a8wt5S9v6MA1QjdyB0vP4=	\N	f	testuser-tp3jiCPi				f	t	2020-12-16 20:00:18.668532+01
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
1	\\x41545dca6a5d61f31920dc7bc487f4eeaa2e41c01d4b87c82ad58d5173ff1f720d2ce2c65e5b4d0aecace98e3334f28d8e7e82f4978d5c3256fcfd15e4f9764c	\\x299235b078c1004c798e8904d47d0d4fdfe1b30b6cd7bfe5b9b805dc7936f4dc747d7cbae63afd60672a40606fe98e97d6e3604e0725fd34618b0453d6f28505
2	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\xb29cadc5cbffd836137c006dc3198462ead316fe2eb88d49c6c28cbfea38771256e4327ee281ae66d41dee0db68cf3f39df78415e8cc7ff5a98bf2c18ee59f02
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x04f89c47f3eee1b7a54284435be71069ed500681b1565af44a397b6993cab5564603b2ae8f02671a1873f4b95d3c551de841aabde4dc3c99dd03b1fb9438493f	\\x00800003ba29aa0b39468507330b3c092b1262c34405de699074c55aff48e62869bf2e0f0eefa04754479d91ccdb35975415fb5be517b2d8d59f4e927725fa9d8a13bea4ce27d6b48ba75999bb977222202689e6e2f8edc23d39cbcf45cc19d802527deffa3bd827937d84e0a8d2347d493811e501c0d451529f67a0e4972a011db590d5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x52c669b456e31018da5cc628231e5362a78ce8db500fb01a82baf552789044a5e44d9101936eed45317beaa162f84b47a7af47af703eef62b2650c1066917e07	1616608206000000	1617213006000000	1680285006000000	1774893006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x065417cbdf3edebdbe3003e43da329a34ed94dfedeebca1e0dd346ae0a75970b7f130a561d62fe1de6d5e8326b34cf69a8ae72266a1c42d2c94227e6f353b417	\\x00800003e242cbda21c4b298c6c79ee494bf09f1e9b5bdfc496b21b40e55f05a3b828587baa14f7f12bf552dcebcdde84f6a8d5e7adc6e27f816d7ceed77c0762abdc4f1646d83208fd1370167fb0ee5a63d954cb58b400757054ebf3380acb5662a10d8ba52d97340e3c5557292246f6571d4d2152cff8545382e77fd52a15516309195010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe6bd544dd7470ea186480180ba475cd50932f2a448c28874a3820cd47af8aca81b2d5793c54101c6c926403a499b171e01680673312e4bee86897c6c1af07e0f	1625675706000000	1626280506000000	1689352506000000	1783960506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0784037aeceeda7222cf7147870f802dcac685df4ec9ffad5a1a045ca2de9ee136fb4ab43bdf45f7e90cdd45a742a162be52c6559146bba30d5e30fa42aa4c7c	\\x008000039fcf0aa0878f2005cb6f4ade26f3426fa9843a3bfa303af889847ce96311f49464989f93ad94ff41a82eef8d6453b34e3e731348ed5d08095fa3ba84e97597a6c420c1beb725193b11fc302e0a0b8c01ff99ddb83b57484d6a2d9b589f4507db498acb62781e14c5c5b4d8d59561cda2fba93ada2f2776f42879dd1b33b64923010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc92d5fc47c281707e28192286efef1687e92c0c45ee822d9e5a089852286a0f954958124b1c193ddb6077e1e1a67087a8729fb4b1695d53ad06e0ac5c2578007	1618421706000000	1619026506000000	1682098506000000	1776706506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0994040552fdcb88258bd00667b03000a1dc7a65d64774bce3ec5cfe49c62d6bc05800d582daa4e99f3cd09502a479e43cb53e1ec98172e77581fa38a1faab57	\\x00800003991baa6432bb67f6936bac0c4f6245dacb46056148d35a8cb78ca06233509e02539137a86d35f9dfcb0dfbb8345c6a3818ac29edd1a936316b1c74b9beef2af691c72b1abceb5a58f947ffee7428bdfbeb6ca0b378df784a4d2e9838c4fc86e2858f9a8f5e8f14d5dbfd6668618fbc7a0c0240f09b1cd64d8e58690f0b71daa9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4768da1d9c7e1e5618ea9f6f7c9bdb34d40577c8a3b1dd8dfa7268e9e973cbcc5d9ee636765c2ef5a553aa97e22a425a8f058d22fefb51624908d7299e796203	1633534206000000	1634139006000000	1697211006000000	1791819006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0b743ceaa1b6ca10dc5f17af35c69fe173a9d1f6fff09a12ebd404dd620af008680b852d5bbd9ff6295e51f2c9468744a9906e789e4bcaa2d64844eaeff1b6f5	\\x00800003eaf9cf02f8ee85c93f8c3c11ae4056adb7393ad7aacd5e3c39ad07a75ecfe9e09ed74199063211ed2e817e08674ee06b70f6801f7e2617860f76d99d89f7536b04f66f7c484f1b09a5b59cfb6f0522c1224a3f2c7da1016d0fe103f481d6a4f635b826c5e9dadcbd07f501d0bbe4196d9c2808a3423179edefa3afe7ff0d68b7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x902b055a49228e9b4b8ef6fe14ad90956732d4301bc3bc8b0b671837c3ff8ef62f8dc5c23039576954a482fd7b8cd069caa162abcdd95b3bb0c91cea786ecf03	1620839706000000	1621444506000000	1684516506000000	1779124506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0d44251243f20e5bf4c9934185da756c10947cd80090a899ebbced49ab5e485c526e938277c0fd0bd94aff1b1cddd811f7ff209fe6caeb622b365f36fb78bd48	\\x00800003c53ce915d08c5dd5df85fa2f8e1c79edf0540905a7cc9e7af822cdadfbc036d7d890e747e6720677f6546165dd6a9c0a4073a65bca64799c92b41a263a9f52ecad9141535c2afc613f0c9aba30ec67cc1d545fcb6a0496eaa6e15c034a75f7ccccd4ecefc28d3f090b6cf331512ad13fc0f628e030a88b9495c0d111aff77e29010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x64bb56c9e6a91aa894017a55b36da1132f2177d06cccdc64c479db10578a494a073650764afed84ba6a7f53ff078e202351d7959c0831b196c544824f27c430c	1620839706000000	1621444506000000	1684516506000000	1779124506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x10c41071ca987bb9b122e36d68e7e89dd8c6f38bde4c30e447d68c7e9c882865a6350d719d2107563565df401187db891739190ef09eee2e68901181ba6e588b	\\x00800003a112f9de0017ef0435b4387db141f7d7d86c6a76a06aa12dd6a24451e255e9da0520baf4f1e7dd0baf75bb530ef2c71d62e32842817c67909ba8d5d4063c1c105627a12f335a706159cc6f74d8f7069194976fa18399e66e31e7a9fe0f4e13d9b3179dfa8b91994880ad4b6758ef5f7a80b7156fc202af3a61ece43c0c7f3179010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6b954a292a651e7f0b77d903f09b15504ab62fa2400fcdd58334c8af5232bfb4c12bc8c60bd7c5692e4b1800e3c21319e00f53c4a9626cf982acbfaab4420106	1625071206000000	1625676006000000	1688748006000000	1783356006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x10dc3f74589496eb47531ac3df4091ddcc2c624b127cccb320deea8947aa5115b03ac7371bea4e3e16eb6791e421dcda9941bb61fc38f7d9c5b1126b61979a34	\\x00800003afab97fb821e7cb19a3b49bc13a35ccea401d43c93bfbd27ee5a31dd8f50a4a95c192dbebaccc3b423c908f3272931856b990981f678f45e9e6f0b38bebbccdb3c8e6fa40de9ca0d2d0b3366ae3a9d3f5651f2801cb36f337b0b7c5524970d816f6f65ce145c69dca4348053acd31c0d8a206d80844b482ece734b1c98c6e77b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8b517797de446e4d127c6aef60236270010b82185e8120ef21a7fb307b2e036d2f7c576e29db0fff01e0ac22a33704cc3480e0ca57c9c4e00943e013d9893206	1616003706000000	1616608506000000	1679680506000000	1774288506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x11748b286304d18c9e6ed4a18900cbaac353333b017f53e3287725da233281321b3a016c58539ea20db1d09ce2330b55e15ddbbfdb705ddeef13469c650b376a	\\x00800003cba1e6ccede5b70e59fb733245ca3e42d046a70ea211321393fadac0cd6934a93ebe76c276feac4129dcc82ca5743c3f604ae6c438455696751df556d7ec4b174d419dffaddae0100a78709ecc6aa584fe91859520977cc9cecfc5f6b3eafbee097ed9a10c16eb1ece2f86560a0fe31f5443555d75b6f561a72df380b114873d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc012eaf78227dd8236731b6eaa86bac09fb0054e77f2c7a16fe3fa46d1fe132c0e1f8d2ee2a857ef16d038ab3fa99e7fbbc519a04952a508f408c24f9484bf09	1637765706000000	1638370506000000	1701442506000000	1796050506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x121817509c187bac97c5e4f0954b35d27cbcf460f802c0ce3ac97f823b34940c2c4fad9228158a199ad4fdb308623e160213330efd56e5f8cddf74ede082796e	\\x008000039aa0f1d2a76841e6faf5be010dbc4933edc01f41137c40751c816b2e8ca7000bcb8c597a5b27c65f3b1e9113267b86070dd2b18afafb1274b838c93e47c2300e02c623e6a8a161966be1b9effa1370eacc66c741b250c04221b9cc811708a8825790426018aec89f7928767b218a03b5edddfe8fb7236bddbd6b115448ff7b31010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5424dc7b6e45c613df94e58753c872eed00ff0a158b1f7c805b927b71b46b7edb84da2b632cae0537a1dec0bd2d51b294c3e4008f740709117c41cbc314eae02	1632929706000000	1633534506000000	1696606506000000	1791214506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1614c45477393939e717b7795e785d7ac66daea61263145d727f1327b81afb5139cfa1cca91bff152fbd9358439688d8c73eed389712e7320ed6236339a3c04d	\\x00800003a9f80183ae3bf8b0601eaba4c41fe8a81d9d03f011454399716c40c2c662f23bb35d34952acd6850d09c128bff30cad1367854ad2b11a75b0b151de6f07a554eed10c39145767ebb184f4cd0eaf315afa25f78bd25e184338126b4474cd7f173c8525f0afd049572a371e9641e96b3777ad128d5cf1740c30137eea6a1dcfe11010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0a6a2fc8fa581857143500f978cedfde68d3cc2065df5c857b6867054848c002ddcc043129d332708dca92181a7ceeaf7137a4c44668a1e457fa1309e7c0280d	1611167706000000	1611772506000000	1674844506000000	1769452506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17d81c2763b66571d8300c5995a71fb1c3d9ef3e7baa21af2acf72df29337d6b971c3ef915e82ce4c2ed1c4156a3eae0610bc83c0580762ef238d0b48223acc2	\\x00800003ba24469e64afb30ad63dbe0fe9f241299bb6a9f0a49ce2997f2e4dca58c9e4ef6a26e9b9607d8d53552c8b880403dbb8bde954a0157e3f592fa426f345339bbaf3985a4e5c618d39ace536e35c3eb47740a3cfcdfc08611f8360b993337f83fadf5881f3957f61012fc01c2b68caebd7d8830246f276da2f9e8dc4b8356645f5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x310bd1b7f759aff8fdb2da892cd1ad00246bdead3db40213073d6980c733b46a2b96512558a64bdea96c9401b30c68e56adf697f2bef6f70aad6ab1ee3fb3200	1622653206000000	1623258006000000	1686330006000000	1780938006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18d0cef9b0ae59362350da71627ed352f507cc63629e87769930411807ab3c6545d8019c838bdb8cb53b3e9bc25c871c9e40df6453f41ff3b50d6bb318ce5de7	\\x008000039c2aaadbe2f95fea4fcc9d61a90780b59521b653de0f5d5522c0a8f863240c2848d1f8e963a52089ca03b423e2307fa5cab7929ee4ebc65cbae540ce4ecbc97ab4c6e65d4a1e3c4251e6e595837689cb411f1d35335a36c5b1db27b84762f31b57ec87d61a5247ccd84d433387f1c19d050e0f8e688ee5139078a8c9dd7f3211010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf49fe21dc854c79f66540cffce93375bb576e7283ba3cfb96575ccb837e54fbe6847f38aec0a5e5a1f1a5e0927b1d652b85d3633c1587ac35a65b9c83bfc2e06	1608749706000000	1609354506000000	1672426506000000	1767034506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x18442e5301281db28a2935082dc2086a06e5b264e5a6e82554d747f78d25149e935235f2481277691bca3cf411a98ef82b374af4fa9915fc75ea9141a527a540	\\x00800003beac295644acf252e36634973f9974d3d7c842fe511002731563c68e63f62bb29dfeffa250f1a19673db8f49d125e4230c84f83ce1ebf0a2e2f174a3f4653dcf542927d13dbe856eca3c2d425e9e8c554cbc7adc443d3cbe0e5b2e7cfa55aa4ef5fb395689eb0d4ce9f42df5cf0ca0c84e8f4e26316864377c8ecf5844963bf9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4df6dc8113c34f3a379d732055d5bfd778ca9a73fcf09a6a13491bb94418c450578afd8bbd2f73ec87066d3c5b7a719dc6d3585863c3ba3c658b6c35f100ca07	1613585706000000	1614190506000000	1677262506000000	1771870506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1984703f82d838a6976d997d5d929887f264bd4bb35ca7754b828595d4dc34f29e9bdb75be1875f14a1ceded7d3ce426f7e288a8a7d3c577f987f1b0a30cc334	\\x00800003ec9dceac5e68bfbe8d7517d9cf569320d6a8d9b44a6e3378b833f3d360d3cc7f65d2b3a65ce422b1710a6bb99845466c10037420147c7486147ba6cf9179734c059cf54b9c2bf60b5d352cefc6939acc61856c71ac456b2635071076a2eb09caed4dd1308253fb87e222f16cbdc3ac17c23e2aa694df423346d32a8716d8f0d9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf71419888ea95cd188e96da5bb6c3272a1f0daab13561d6cdf6ba275425dbb03c51dc13a369fb81c7c7272258aa88159da0b0b0d80f6a810ee5e36044c7bdd0e	1637765706000000	1638370506000000	1701442506000000	1796050506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ad8fc16c79c5112b4661356a9bec0e2b0f7c21d77352043b11dad39fe09bc82ff3e94bfcd4ca33de84fd17cb8e5b2dab0d416d416c4ca09349bd38a0285b069	\\x008000039a286b7e3efb8a190fb9e526be6f18c2da38d931cae501bb922019da73b49333d73651b0902f9ab2b9a84aca1b7b4b50ec46625457603692e4227b11986bc494b48834872e1527cadf67864da790e594cba4f6e6187452a3502d0f264d4f796b488727e610c07dbdf582863cf794f12fa22604ac88cdcb8aa7cf54b20c398975010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3fe7827b056fc8b5c40e7f201fed6372d08b36fe33d4dccf69ed58b54393181e3375865478dc35b9b350bf268b1e86276bb27a30a64b2a56fd154707dcaecc03	1617817206000000	1618422006000000	1681494006000000	1776102006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ca0e43f9f578eb6e5f75e91ab8d784cb77ac75889cdd0a03bdb9b70be0b1044d6a60720b77864c470964b6a1c10a6a9e87ffb2ff4b41c4ccfe3591f452808ba	\\x00800003b23c0426c93c82fac33d3041122c30b73b4036ab1b52dd3ea208851ec1a0dd764874e72250c0028bf2d9dfa62ab532b1e90a3294bdb4734349c60765f0cbb52b853e6ad8486be90e1d6cf9ed3f52e29c911d29f94ad000da8e72563b36428b860b595f189c631c5e3b6179c3fed7bace540766ff35367c1c4636cb71042f6ad1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2f9b968245b03b9916b1626e3e9e9ed4d10f2dbf60f2f5ce349cd13c7cb666020ace657f10078e3822cd33dfac63ee8c983793bd849234d642b1d288a976a809	1630511706000000	1631116506000000	1694188506000000	1788796506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f10e21c7156d48752f0aab5f67b89d91fe7aefa28ae8e616f02ed05213fa93c5665dd20410a1afe069e8b0eecdd8bb74a59b82dc99ed7e8ffb9cb4656f3065f	\\x00800003cbb51d959b7094363526252f7803e4efe917457a0170a505cfa3031544155c60d5181f933cf4b23caeb79c22b3b2ce6e1abd03f850cf3a79e4c92efa3dadf04530588320f46607851192deab102a67287b0029e03eb66db2b53fc2925f8673238544c33655d144816568bee03bba19ea59be27e3e930585dc4fd1a6182399737010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9d0a6fd46328ea605c31bb7742c9b98f4a775b06d2b5f60f8b45c763c450d9519884001a608aed2c5e541c278c3d10fa09ad76ccd5492d42ba3685d3dce67300	1627489206000000	1628094006000000	1691166006000000	1785774006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21eca517e24e88e9c532db0e963880dc6caddd88cddb4bd82964b4ff1e4b0b7e962f0db464501c1ee9116f8d2481515881d0b1a40c41a82e49c7cc5066706984	\\x00800003d82f01d3767d9c0aec820677f860c9ae206ffa3d99af08517ee6ab6a10ac653c84c8a8715f6ad9f88d4258004d09eb19ebc01c5ce4f523dded9b52b66d0977e8b61a1e515a5d02d214ae37f5ecacfda4e5bb8d444980e92d6b7b6a6b2d9698b3eac1a0d1e48d19a5295d334976afdbb3bc99c50d7050e27d00904ec208343a6f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x89d9ab7beae1caf5a69e22cd6db03a2725fd242a9774a24dbf3d9ece12c039194a77321e895e870b2cb71395788e5c0c26470cd045a88737cbc8c49a34b7810e	1628093706000000	1628698506000000	1691770506000000	1786378506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x24084ae0026e0ab2c9f635082988c91f4b9292f16c060e32e03ad957aaacca49935c3f58011df1cadb876e9f92411578d371bf70a10162398571c9ef132dc8f1	\\x00800003e4dc953e6e18d4db12d1a9a0c0c43a208a7e1cac07564ef8da2d79c87118a7d06a01fd03a837e176528a9e66d18e94e5a8d4ebc871acb13e7e06ea6ed00ff8f43911fafa1587e19b57a467b2b9138db48a018c9793889a0b2017a9ae0fc0c8400aaa2455c463a9556f066d831cb51d216a852b2a23f49666bc8a00a4e3fb3907010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x39e21a5edf3245b50af44290224edae35daf7555114d464ac99c2869dc6bf35d5898ed216bd8e058c4bde3bbccdd05691c7faa3856d2ea8881ea6662ba52800e	1609354206000000	1609959006000000	1673031006000000	1767639006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2cf8e969e191421ff82739ab5d25e726fc05a7794df5d4fe339c3f52869aed137c66066013b3d52a532c233931a1a7775578166afca27374d2186a169ac9d2f3	\\x00800003d5f378ce4db7eee4e4f2133439b1ce6efa4690b28fda0807a45684a559762e8e34bb624742cc01751ac99c67424b4c08175cd49bec6a605619d60e76cd1ae1c0767bd840565d19444fdaaaf6632553f611dc95e18b37c9fef8875cb6030c7a24f1d6b949a23d26175938ba5d82c5e380d1c6707616dff1137ea9671ed86e9a7f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6d103a41787ab4044254b44da3b81af23021aea34d2d9a6db4a7992bff9dfc4e0fa65831d3d90029116ed90e5bbf118b897f09cafec4afb1042d73a5fdd89004	1628698206000000	1629303006000000	1692375006000000	1786983006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d6cfcbaa4a0bb0f549d2a73dd250ee51d3e1a1b07a5c5559adf4d4eca73f39e323e8259dc6860aa5c2d0f619936ef34fb12599f40a1ff2a8a92e3f1ac9a39f6	\\x00800003c35e92559dd81d1b761d6a3fd016f39dfa87327e8815dd16ffebddb8641599f96559dde1810c854526899a1473d76300eb75bf99a64b28bd11508c145635bcd42ec00216140ee4cf6d489d396069d68ec63b5cfda628fbd7d04f299dbcb9d9b2e2ccdea8fbdc7cb8185e4552f2425a537a0bd9577a3bc9e9a8ecec5a63ef4285010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2f0ae4e21b25bcf837ec900142e989cad2ce0a1f5a4c4af3177f24b514f305c09e7533075fc25cbbd7dee7861608ddd07164d97b0e88eb1356420009dcfbd40a	1610563206000000	1611168006000000	1674240006000000	1768848006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e88e0b520f4deee3531e3a5348cbc5d1f341feae9f2623ac45a3202ca44577de430d3a3c7a85e1d58d5cddcb9548c6bf936ca964b0aee04ac3164c2e70c60db	\\x00800003c9057af6db41f8a4d66a7b18a6489b1e3dadfdf75121d72fb41ce3598eb850115d8aa0dca3c55b6597478def3240a171cf04e4864dcda4c98176f30070c0958d2fb1fb596d245d28e4dc66955abea27fbdfbe76a06bca0984f72141313847e9dca918f990086877e7d32f15e2e10de9782d990ed6b6d8e7070fb33551a80e8f3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x804984e69257f505b0996408875e3db5278d85bc3519f10857b7ab999c690c90d9f521e0dfaddb338c5f345d143a4cc59feac88e3f5572246f7d1857bfd88002	1619630706000000	1620235506000000	1683307506000000	1777915506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e0cb836f0be6924dce1f7714aabcf6d320a591470610035251b6930e62be0ee9fd49be9310c7a12d6bb510285b7123a89fd0a53975cd50934e4d70bf361cefe	\\x00800003ab0d5db297dd8eaf55d11858736d0a0dedc079be0acc1b192c71c8906814d832913bb43c5dab80cc34e57404e319b3121aa04b5089fe7599b4d19f1096c55fc4d8c999e86e9c46f69fa0d36cdc1931ea7f897951547e2165bb43d2b171c755c65ca99a841b5788882c862cfe452b8bec701e3a723f4f194cc57f8b9791c6bc7f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1f661212000c7dc234aa907a063d090b9a3e5def28e75dd9a75b510caaba740626ce79bf5d187bcac817a4687535629af2d2bfc9e502763d4f2960f8f37e8c0f	1610563206000000	1611168006000000	1674240006000000	1768848006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x30fcd8a6615393b03fbbd6d0671472a0e319c527b49a6836275f9715302a4d6066e1fa747b49b250546589cb6e576f48dc73c16b55ca80912bced793f7d273a1	\\x00800003b0db63ecf961dce5fa1c4d127c021cfce08bcd71fc900266bb2a7793017e527b8090324d8c6228961078684af93fd0857e167d287bf5ed73a3ae7cd49a0e08178264ca44e8ce962cfae464835eefd72ec390ddaa6ce86df139f88c539bac8507f877b36f27f2999311ee1d3a8044069091de163357abaac04e461c6712e6c7a3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3a97e95964602a10d9967e54ae49a1875c131e56aca4dc5978c2ebb75be1b4dd2c79d829f44aabee76dbdd3a25013b15afa86408a91537738348b8e047a8bc08	1629907206000000	1630512006000000	1693584006000000	1788192006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x313c0af9dac03b5c40d1dfb7c3f42a75414893535b1d9d3dad95a971a403d5666ddcd659cbbb48467def7fb59e41aaf5b6531ae1486f8810188125c44c394c3f	\\x00800003b987ff0c4a03d755525124bb798e828ff293006b3130a8b4fd3ae592e8105edfe0956fcd7de66db3e452106fa906f88c521d58c672edb16523e93fe7533756e7783fce770096d9e32d7945120cc70de0ebf277bbd74cdb05109afda4fe4c26ee068e0d00ea6de44415bd6f21f7fa02950ab449f63f2d4e5f05e9a803927c9ff1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x756b2f57ebe4f5e053eacc6cfb86de6cd8c2fdf91a267ec09f7bed836218c9edf7f0bb9cb52bf2f0b5637dc54138fa837b72156e47cd862b87bf787aedb9280b	1617212706000000	1617817506000000	1680889506000000	1775497506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x322c8755cf60899e8e58c014d677af6108d839c0658e9029bee42fe068554511b6485cb907e75b0655155d10969ea74bb5fcd87d754dd42bfff386ff5dda2239	\\x00800003abc0a0177ec112cceab535838c8acce1af363763decb83f533cd699f23574149dfe711e569fe31a6df4aadd18098011a34259a4b44f4c5f35e6f54d59ef206d7ccaab9459bbc3659d7f2c373549cea474f8496649764594604006c2cbd4df6e4de2ad79615daa8ac0f80abe7772f236dba73d199c6c8cb29c462c8f0688cfa2b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd8510a17c86e503606090b2ae6075b3e5f63bc02240bc0d6fd720f0d58781c93782246673b7b9a3a4f76e4e58a0c4ddf1df080a534f0f2fb75b36dc90958f903	1618421706000000	1619026506000000	1682098506000000	1776706506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x37ec9303982be8ac31488ac45000fe6febf26dfddc1c81ad524accf71e4cb328ca53bd2b1d9f746a54033a6b9ba1fd0be30df80d82368dde90db533fae0fe332	\\x00800003b08e6a2f90c5b56888872a6e5c403f23e002d83f04e9944da192252e784d9f015ec2a6ded9526d645e7ba60d0c85489dffac8469ff732c1843be9aefec31b50c238051742a1ad87db1cfd605d1ea26912126c7a3d6e5617c131d88643bbda308b4a56e58040ee6b50f9bd74ff948dbe00d0aecfbf9b40f5b8a1ee0680c40b913010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb811f7b904ef49887dbe9d893b543b0e750a10ada2b9e2cefa2dbfcd1796208751c82fb7dbe7dc38bbb65e424f75931705c904531423c2b4b1d76303b1ad6c05	1619026206000000	1619631006000000	1682703006000000	1777311006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3818fcf75ee32f9bbd77d2b7b6f9adf84e1d2cebb02897f24aa97393d8f461243f2ce739270f4c8c33541c45f957a8b33e8d26fb1823ee5997121fc642c1cee6	\\x008000039ca63f5e60928f594ab98ad37a92e9687bac9d2d48e0bf211e724de235b8d4947fd5800a2337108889dd399431a86bfff36fcdc3f7588ad98a5d255fde4729f7be94c9f39f3d09220c5dcd2c69dc81a0873364acaf6a960d4aaa2efad7bc74518eff27d6049c1e106915a6822e59db9090ff2ccd0f262125ee3f19b8c4c72a19010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc38b2b15b395fba753370c6660ab54273839de68b1e508ccd5860561607a717114cdb88f34b6fc1729a5b20d4f9abe073b8580790d9817789127ff78427a8c01	1616003706000000	1616608506000000	1679680506000000	1774288506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x00800003dacf1849917cf504fa1e535349f10490442339aa767d892acf46512887b5250204fce3337b346feb40a59e6135413e4946a200986af9bc729399663f69ca284e991c52faf1b487e1724df52fca2c67c5b870b6ef75622810d8b1799279bdc2ad9ab0f9a61930d2bb76c043f3cbb22c3692acf34f67f9ab679e2fd0484c9f1d03010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x05ca2164faa56c78d811e18cd37cde88f2a50ae9294a2087cfe57b1319a5a821346769a326a6fbb696ceebea806695be846147f47d5cda7d67a528c7e5870503	1608749706000000	1609354506000000	1672426506000000	1767034506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3a948021b61eab503f269be29144f6f324d404f803f9c2df2aaadaa6ffd4dc669312d98276bea3c0727605e4e90755559b1274bb51de75ef6e0aa1aacdff1b7b	\\x00800003d9863e07d0f9e1c607b7932442152c201a772dbca317bad74387c9295fd26f92d605311a4e83bd6e1ffb3f43b3eea64578e4425b0b330328008ef240fbb6b721394e3e7545bdfb2d1739a64ead1ae7f46b76928759d0e6f56d30245030f0de6f2d51bcfd5240be477c4eef65586b7b6eea022416a2b5333fd09a51d4eb027b21010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdb694ee8b589579cd6c938388ec2dec61e237a71b7d7f13c335f272bc39ee9de9f7371de99e8929dc29969685a790539052b9a9cd2f2d9e413fcefb3da30f20e	1626884706000000	1627489506000000	1690561506000000	1785169506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4080a8f82da060d32c51aabecfdb4a50f3e123823fbc5936c7600305d155658df451d783c7fb616e1661d766a7ded2593a1df92755c2ebf4b3f440254ff5e7cb	\\x00800003c505aa756aa5a642e0129168e40b953adf5d23be4a175d5d57864cfc3691bf11dfb0d6accc33427cc646c00ed0d76e8e3e294ff64d8699dc4d60221e4d4a9a65ed4af486a1f2092f9c460ea196bb954ad4c4bebf01cb3e13b0bb12f39b9a852d7f23cfb1d095bfb1e48df82d080d917623345b02bbbe3ed4d0f9994cb98ccf45010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc4cdb1002f93efc429ccf76c777e61d29962253fcae7d6ae0a71b6ef655454ee8078ed2c8201a9c99b3feaed7375a5d4f632c61755e9b7a73f0c5d3609bf4b0f	1615399206000000	1616004006000000	1679076006000000	1773684006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x40f4a8fb8aebb9d855c1d4684e4cc8b1c194658b12a2f36bf99c8a10003a6d30b5c1bda3ba91fafad5b6e0937feb25aa0e2a0a4cfaed02fffee3c8d4a3899741	\\x00800003c33df539c9abdaf6f10c16c97ba61aa453bcf0ff525abf114571d34e4e95eaba9504c70e7cae98a1c501a2b2de593cff655d438021fc3c51b4bbeeeb43a9fa321c59f53a17dd193cc6fdcb64465df2fc502f824c6184605cb2a86205b078bcc91dcd03b391d2f38655812335c3ba121d8f94f4a76b7dbc0ffdeb243a367bbf9d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x48758128eb978a85428cdfe6450d46b0623b879d2f35b08120760b5475d25e227af12cb2d13b03886a0781aaccb8d470a4289bcf8d077df6eba42a1f90e97404	1634743206000000	1635348006000000	1698420006000000	1793028006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x41545dca6a5d61f31920dc7bc487f4eeaa2e41c01d4b87c82ad58d5173ff1f720d2ce2c65e5b4d0aecace98e3334f28d8e7e82f4978d5c3256fcfd15e4f9764c	\\x00800003bdf46edb6a0ebe949bf81f640f7675327b8ef87e935a4cfc153d848939a849c55d0543614f432679e285b8bd99ea3d9005b19c2287f8b0865774122da98842576fbab0a69822c26f65cf30144a2eb7dec693f243c4482dccccd9c19603e5486668729057f5edaf0fc0cc92fd2a12cbcf48334b6931a0aef0ad06ebc681e6077f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfca721c14d8c4be60bb476ee8ce59a1dcff85f7970e0aec1385241efe89f92c6894f0c6731ea5d678a11e9101ea1cc66a4934e7d40897b8ed81afbe24dc41607	1608145206000000	1608750006000000	1671822006000000	1766430006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x41a493d2cfd322376491f8c0d2da1c8ea98792b8525cf8759a062d89be93c50d31acde5d416e3e90d81ded81e69aae36aebeba6c9509fbda4d7a98cca2e09afa	\\x00800003c1ba7a44edcc76cb2fd6e94e248037ead158cb2a0f4863a93dfe7227c4db6063838d7054a7e22cfbc81438d9ec27248da5137595ab4763cd5b95a814aa29549663228d11d8522b4f64ee5574a91919fcc4cff003cca3e37ad18956dc9f57d63e15d17adb5ee4108aa17be32d439c34982ff1ef55039117939daf3e2232d6288d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x86edea5cdfd50d8d295a21201713f3e879e64c2795cea19cc456bdea2a7a67b1a0ed414572a26d77cd5ab84ba0b2c504112986e730394b6762a48600a1295c09	1617212706000000	1617817506000000	1680889506000000	1775497506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x425487e317bd5d771645e805c2decb34f05f7d58e8f56462ba2c7cb7b1eec0ba09861f54970f7be4df010d533f29bf7f9725c317323bc450aa7f962a5812b560	\\x00800003c137e9abfcebc1297c34b876a9230ae2615dece3fe105ad34c2e832bdf29baa7583cac15fb4c9328ac5891b74546151b3c962816bb7f95a67a7bd092d595ebec9b5bff57fd9e257bd600a290f5df2f3995d1c00cb1dbeb7319d09015825db8e6289b2a3985fa068668d9e21f11c7ca25229899312c0796145562d1040d749bff010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9dc37f8858ab7436c692e79a0a2cc39e7be50951824bb8a34880e6053b8a9c99f053845c70d481fe84e9afc3c1499c62c2c27ad0c112d517d3362ffaa9c23600	1622048706000000	1622653506000000	1685725506000000	1780333506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42b88f0b663276f87eaf0818991a5700753a7e93cd4cf4ef58ea9be0d0aaef7e393d1ae336393089de5ee8a12e298c1e49385690ae4996e9288ba4580bcd53f5	\\x00800003bb5ed476d2401bb00ec0763e1ac3f52d43bef0a1e5bfcac1e105b800305288f4706bc0ce56eb1a3b127262faf0a45c2ee4aa804dda10eb8c41c06a6bc2c609657cfbba6e816fa34d50d91f8d11f5d95d20d6a09e13e1d920991c38982f4bcaf3ed5b6f5a1723a082564c0442df28b2e762f963628d559dfb219c4003c099ba0b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfa1b0e1f043241a8047e237bb393632c52ba31fa75e4706d2b03fb7a67b39b2ebbc359fa36f60e525374014ecae6e5bedb7c7d1e5748d68b5a76ba4631331c02	1611772206000000	1612377006000000	1675449006000000	1770057006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x43e405c1c0be37157e822f13c3286372d8a791da27e1ba3fe4c27c8934d1767047872318a0a49637227224ed7af300c9827132180b688b98ed697be4c074d2fd	\\x00800003d067e46ec1091fa2fd4e3b005d4d39fe58bf0c8266fb8b7c67c8348c3032fb030bde9390a8b37f46492b7521f3f3a2b80042e1dd9944c237f9a6d76798626299289fe3d232adbd7eaac41e0d413ef10d567a68b31f8fe389be539c1f7d32b572993dca7c504611a79b2800e75d2a989fd1bfd209cf58f5b25c362593e9da6ac5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2d146e6e0c68ed7dbb0923aa291a8c96a31f81f670ae04ae5fe95888023f4a871e52af24a7ed926c81cc206e2afe018739491db1288d4b957444984f52698706	1631720706000000	1632325506000000	1695397506000000	1790005506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4ae014a4066a0b6d241f047228bb67920410ccebeb27bf7c9df5d97fed5a24e650d99a820c432e08db8c311270f0ab13e651969d129971fd19b52e3e8460f103	\\x0080000398e13340a1f835366c96954af891ff654f4470908c85a3fca292a235aa72957de0ec51758aa28de27b0f6fd36756b1da085488c6269f3ef744051480fdc05287540ae8890a051c09334d16ca68d6d20a63c47385ed416d84ce6a70ffe69889602d6a56c60b475691a45fbc00026ab256535bea1dccf771d536e5202268b65803010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xee993b2ed81c96ef45d8d651460e93cd85a9cefa0a71b50414f2c48879a79ad636ab1a835f1080bcffb5bd90eef94b2f48c488f90de953dc094a4475b9fe480a	1612981206000000	1613586006000000	1676658006000000	1771266006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e38c9e473e1cf47a158a4e5bd99386706fc96757a5dcaa98f9a33d03e0e7e71c17c9d8335f2602ffdcb1e390b60eb91d1ac438e9105f0b244d905d4b10e7a61	\\x00800003d31fc79b2044b734a86304f342a61b72a6d4133077e980dff45078ea934295792fa7b1fc91b79c60d1feebf8128afb9e8285103dda218ea83c91723a1de84243add9c3fa0cd0004b99d744e50e6129226508deca3a6dd3487a11be63ba0afbac1734f1c64b66c7907ccd6a248381e1fd3973331116eddd793b025ec0ebc46fb3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa067c083c9b043b655e85332b93a81704ae0ea749ec49ac0bc4c2b26b772d6fa0f2ae638e80713b670394d0f6a6e0fca7ece570b511f397bfc0e8cd2c6541200	1626884706000000	1627489506000000	1690561506000000	1785169506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5154e2938144a44377503bbc4231547ef098f5c804277356c5b75a55965863141811bce39c88ad51cf04becba00460e0d5ecdeeb0e4e45c095105a4b8e0aecae	\\x00800003cb2fe3790367e66fca0662dbbe571ed990937d9fadc3ba3f2e2005d6b7c126661304e3d6cbede4e6097d8cc8ae7ab150684d092b9aea6023f015559e32fee0a8d573342fd29894734065fa4f5406242bf79744bffe4b13ad26e18ee399148dc0ffda2b9e32439ec759c6e7bfb197fd7f34d61c535d7850c00c4115b6f27ba849010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4e5fa6fd003357db5ba7b4ffbbf8dcf751b1b38718c730360918880e4fba29a53c7434e02563e88f4c6a0650950761e2bacdfc01ad29c35b31742d6eca809800	1617817206000000	1618422006000000	1681494006000000	1776102006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ac4bcf409651a7d96419f29601b8fa924633c56efdcf131359d26c418b54c61c28e479594173f9135902c1d6a1a68c1c607098cbb4ae206d8b325dfacddf7e5	\\x00800003c577ade9c4b4d611da334933a2b9edfd0ec1c034659a8765d6df5ab931ecb3521654fb34c6cad2974f0bd26d9cddaf7dab858dfb5ee868348c436ed85f5a61d2e858bb3e42a27897b32f22a92b9057e8e394bf915b02ff1d07db1d3aa32fbb905c1f0e80a1b91a7abdfcb545e2dc7a38e567988ced90680f09d7978f86ed490f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x10f2203b68cdd56e2630f040dabf0aa76da7aafc5b9dd6abd41c7d892c9b5fa996346c14d9b028ec6619cbf85ce6330833336c2b5f589c5c7afe7b4d4890c20d	1638370206000000	1638975006000000	1702047006000000	1796655006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5cd81c2a1ebcf507b0e0f30bc8b49195abd75913ad9b0014f156f4e7a9e43a7553e35e7a48a7b815249574947ebf1e7a764c9a116e5b1dadc7a7f3118d8c34a8	\\x00800003d91ccbe12e7a2dc3424bd9a50defb32f3b43b3e94888d5b0a23f9773146ca682faebb600c7ed10ae2c130132c9331a02bfb81dd2513f28246174c217b1f5e72cc845843e1e1d651ca94960b7efc882827f2c82c390732f8c9cedfbbbf4820532fedbc92dece9763c3c8dc0385fed7f8d90ba9dbd6d353f9bde719bccc0d43f01010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8c1e7b7499d2c35e8e4060325c8288601c1ea68647ba2593055e6e2f281f5a0e07dcf0253548162137f69608c70ba05607ebbbc31961ce7a01d109482651d40b	1632325206000000	1632930006000000	1696002006000000	1790610006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6160d163fa7b69be907406a5f7474cae200a495abc3cdfec47ae4e1f43a7ca38edb2534f32c427fae210486cef54c1d0acf0d860f110e9731b4e92c9ad227e55	\\x00800003d715c298dba56f4e0f85e60a3e2b3418ae179e1bcdb71cfede8b51b95f25d84cb09c3fb1cb412f4455aeead90b86c86e2048904a116bd8acd889b2eb48b30276f5bbec82b879752537d373aa15ceba8edeae2e35a854faf9777f5a8a7c2b62db5b8594ed97ccdf3f9fbcc627b175c021cf52d8f7c3d966ce2cfdfa51b6c58f61010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x829c0f87a497d3832efad08b5575437f2ff6784cc9d8198a63d9ef53000a782698f21fe6c1f97f9ce2ee9d211ebbd0843a37ce03f4a1ed054651452492d7a600	1630511706000000	1631116506000000	1694188506000000	1788796506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x64dc4bf0f51e0ec7d83e3af711d1e72556bf5f1db966b7d61586a4a89c1ce558360b2125772524fc9fe83c3613bf261220225a81feb78834af83390466964f03	\\x00800003af9a5605ee0e9ef091de806e59ee150c32e3be91aa6f3b1b2a5556efc8f27331e36b65c57a750d7470a5216e93cd3f2e690d488b222d5e007de87f08d3477a93b3fc03e7011e17119a47da25068fd8120bb77ee46828b2b24e53efe9a9ea014ad97ea92e937fcebab2646db2ea9b6dff4ee3bc5bae14762167703d6bf7c531a1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x02af6cdd8a53d82ca7ddd2376a51f78e079f293ae6074d703a0f150925d367f48c77e6804833ae8b639571b36471f9801026657dbc4babb116301db03d7d8204	1616608206000000	1617213006000000	1680285006000000	1774893006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x66046a79a25ede27a91c859bf8f19887bdc9cdf98758f6765a66d768abe3c07481b9ebbe332ed6069f878a7bf702cbbd87d225bac49bfd620600eaccbd8bf4c6	\\x00800003dda3b1ce4b3ca4a369c2ccfe478bce14ae1ca897dec71ed7ac1ce081e6984e43755a71a0f90dba9bf1f01930dc34ce1ba947b81fe15aa5dced3af090c1696516784a15cec28b99de95147f0518a5e3a0aed5a38164a34098d8b429192695186ebc2d078c9000a93d0bd14afb9b84a0171aab36a58700345c5419b28b434a5139010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe6e81813d9745c12ad1b05e111e7159a21d64a6395fcabea4ae55bb423a42965d07d2533ade6ba990708d54d052344da8338303f304a5123de5ba28f2055b606	1634743206000000	1635348006000000	1698420006000000	1793028006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6828c3b5667d1a3f683b30909748f7e326406743e9994f98bf87822b0134e25f40e9210c6c30fd7725016cca170b4e66eff27b635271f4259a422000385efde3	\\x00800003c91f8c4ed296669e1bf40986d0f145bba1bcfae7c7fdd4bd2f47e43d5d70bd41e6a816f11169f106d0381d1b2fa24d91216db5227b84c1897c9fad5098555457f71d434717c403af15919fce448230280d70408720ebf98febbd3d171508e55ed322b923fdffc48e87266c51378356c4702da5f45d06ab7a352a15bc72114389010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6e1fc31f5f84c5842d10a742ee09e5d52678292b2c9fa390358df787db717db518a731215fa22fb4d048bfc7ef6f206144480feab03a533aa651f9efbdec6f00	1629302706000000	1629907506000000	1692979506000000	1787587506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x69388196abc8424431f28811f80189d04e5fcdd83f187701336b30428152def041af466d76dac8857979eecc3635471e8b2cdab5e726ba8ff645daf2443bb7da	\\x00800003bee28aced6ef8ac39831e18a5f3f6acbe647fd7b701bded780a76ba0667a9a722f2b3c5ec60b11b6bdfeb15b79a9decf1636509949fc40b1d208bf175c7fa82fbabe371f8830f591427ac68047d22f034df9e6907d71a757e40d723e8c1da11838b3edabf836e7bafc94be572a3be261fa6def3e7c9b16c0893d9bc13860cc57010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xac3728af11d7e348d4b944ebb2cb96381fb5f448eab370dfb7771b44787e5ba9896457d8e2878eb2532c776ec09bf395cd2c2cbbb97627e39c62407cd9f71c0e	1632325206000000	1632930006000000	1696002006000000	1790610006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a00657a30dade67e6aa38072c82b0fe7eb5a018abd21f9a5bc06428ebea5258e0553be2b180d88ed94dc18a8aef07b004a701e8e7ab8a4e07708e6bd68aea40	\\x00800003d0939972390e5b0f4857695b47cd66a9d2bea093a5d7984445310a949dcb2aca930e649380209330ee4eef87df77e0ff876dceffd96c5cd82bc793bc8af13af7a2606390afafd84cf57eea14c04070bbdec481f5e035696175d1b804cfabcd261e40d5e1ebae8d9e1781a45e22be0b25d9b0965bd1b18c6bffe7240f9dbb2005010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1ef28efdac5cd5e773f2512a308a767231fa753cc0939feabc96c4efb897e082be9f2a4ba5ba415c9a903305d83b651638ce4a7097e40316b677c5516171190a	1639579206000000	1640184006000000	1703256006000000	1797864006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6a5065ccb021121306ab7dccdc9ddc11ec9d6dbb43e771771e3f46d21e0d9e0dbdaf03290aa88dca352dcfa862900948bf7aac977ad57a180cba67e7c9692b9f	\\x00800003c9f1a140576eb22394e9d2dba5d31ef459a830eb9755932c9c5c2f9316131ef9eb9a1dc6e0744975853cd92de359256db59214c5bca0f505426c80c3d3499d3d4e468d7f2544de41e8d04e7fe0c0986b475975c95557ae3e7e2b155fae32938bff28713695dabb8376d7dd892f4b72ff9c036ceb07342bdea432b138caf6fca7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x87ed31bc7878e219f83a986ac51cf61e3cf1b9303523439f3bb7e4425b157280771591faea4fcdb1605f3f02e08cb6278fc0f767b3579561ce601e46793f0b0c	1614794706000000	1615399506000000	1678471506000000	1773079506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6dc4697ae4960da30539a1dbb9f1f36d3bd4007ce5ead18b6ddf53573c22a4ff7e63c1d90c742ecc843c46f841af9d6e4db7e50ccf0cf6aafbf531186edc4ca6	\\x00800003b1ce10cb963c02b11699352cb70541fdd50a409378784e26803c352d8b4cf8ff4cb5d498c11afaa6d863050ccb9ca0d74cb42613a3ef4758ce5d5de25c81b1ba4700f7a041ac8d0e664d11accc19bed97095929aee1cc1a8682408db2312b71c25b53857026702097e46d5af53a13c3d9c4967b845f96e87de29b5d62e5a5401010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xade1137893a16256941d6e5df7b9bb0d82597687de7a4996c760beba77a09b98bab67021676e1a4e6755bb394bc328656677c705737b3206a4c4d8be442ed00b	1626884706000000	1627489506000000	1690561506000000	1785169506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71c8ef30b05cf5ec2d4b36a1c5210167a20b5588a260820924b65957dc80ae3b891572b1c6f714bfa8537187e8fc358cbab1161f4e5196c3fbe903434ea911ba	\\x00800003c5539b22549cbff37d269f245c908a1dbddc1b41f81d928934dbcad0ef819e2de96d9f90098c420d5788fb09ae5fc55862e8a00ea7dfa7e5bb23a7aabe40f8a62fffe32107b87c8e4bf4ce68ff00257710d5b42db2c1b36acaf590ad40caa5ae61022f61f00d71ccc442737df71b6926fa8e66b6ce001eeb2c3d2ddaa4e8b889010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd542fca16a63972f24b283d499fb0b5447c89961c53388e0e5d87e6e15825988fb78a0b3476bf1afec2c5277d9456166af1aae568ea206a6c4d188078f70fc09	1609354206000000	1609959006000000	1673031006000000	1767639006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x724c6b0846f9b5e8041301637bf1cd810379a7e2195b263dce9741599993ec3a94eb2818f52ca6e26ac0091eecaa0a43a23d979cba63a8e5d8f8487d543094aa	\\x00800003d6719a1a6e6933454062755fee510d7a5ca165b70b50f67dfc5005ab16601e353e8d85150ad86882ec4e3d3244899c5564f87d2645f38a28070c66473dfeef547437a85a57d3c23255af1e3f42e8a093426adb0a354f8b43802f414e86de8c7857f21062c760d58fb6d210bc16b2b60470bf7c15efcb6800510d5f7923c67e6d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9574c41090a5bb184cf8acb8a09486bd36dd1baeacb8a5284ff3980959ca2be5776762c072ff911bf5cfdabe2f68148c6c4f14e40e4dadf27a74ccd01cba670a	1635347706000000	1635952506000000	1699024506000000	1793632506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x72a0673121166615e422059db62cbfb2a052ae9ef962b44f17dbccea85f3fd6d0bbf3f11932db75950749f68275a7fddbce3ef50c9fa67cfe559a83f4b876d4e	\\x00800003e2f5adacbb6d3b60c1755d938c971af0dc18a9cf46e25db902d11c6bfd12ee318cefd68cda0e0eda284580868fb0627eed8fcc80450db49f1b94995780a055ea0d2075a830248b474a2fb9d5eefeced55c7fe87cb622f114f0de8cf6af3542def1b87ce6eeaa5852817bd73806c4f83ef715d7b332e65897266d3366980a18f9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x69d158897a83769998ee579366bd477ef79d235dcca08ea8d5b578f0d5e1ba26a3687211f00b24aa40259496923d582a09683eb828aec3ee015c33f2630b4e0b	1609958706000000	1610563506000000	1673635506000000	1768243506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x73f4765a1f0ddc64c647f72c2dd5ece09e88bd75cb07bc16eadd1fdb78d72c0b265b6132c6f1ce69145f4e5c21b05229f1d90ec1db98651c834fec3d6b770d3d	\\x00800003c1411ddac981dc7078c7a0007f6b4e28c18669e03a858373a7404a28bdeab99406ab3fbc0af5f6811de078d557b9209bb39d61ca2448e2d76fb4ec28d5186091f3d69bada354d09385f7f441417be2ed82d7d88e67abf5bc61f8bccd14f946a9083de2f3297a13a53fe18578f14dcb7dd3d362b867bdd0467d2e8b46d70d34c1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8a25a9058db47a261a509499a4c82e4cedfb7a3bc2757e0fa9048c59a65f4e9a25e72c5d2ca84d3b56d7daa3c33bd400e0b98d347910c9e300b30c5f8ab4bf03	1619630706000000	1620235506000000	1683307506000000	1777915506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x746c8cf3e616e64f3ddd3e1a446f670395c14ffe710e80aac6ee6e0d44458cd920255eca40f1beef3082ffdf44eece8f5f3a3bcff11ad0b413748aa41383eb34	\\x00800003c2a36918768dc843cf54594033cb0361fa17cf03eaae257a5809d5a5c9560d8ed9ef00c0905942ea241bf7052ff18a86b21a10f79bc224bd862e1cd815040c6a765f13640b2677baf5bbdb29243afe68f8d136d6f489425a36c7a0d38240edbf977acdecf124d7b94fdcd26076f8e8092d1c06dd6f4028187254d371f5a38d81010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x36ab0420f65897a76ea040ae8e6f2664e62a1f49f6136fb2d85b5210464d1668fef07756416034daead0a0d2de76483ecbfb87bace1d7bc052dfe97537a15e04	1608145206000000	1608750006000000	1671822006000000	1766430006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7c70311eb42b47dc12b9186f6870ce1319c1a238985da09d1575aec3c2abc0f37f6469cfc77af6d083df5e877cd44659f688a190da7e0b1ccd5406b95f637a99	\\x00800003c3b673a1afd7df6ef1f93be4567da29aea02cef0acd9187532f287910f92c3ece9d84d37b1c34e6f0098115e2d086f4b18e95a82ecec6b21c6064a7785fe17371ef11a7fd19edeb1f820b012e1fc47c873024e4e86eefbd3a6b2749a4e728b8ede578f29c800f07deb4f97de19127de34707d5876f8e4072aaac9ec68064b9f3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa8cd1519e00f31c3664979516f5888769d0a44aefa3b595e7bc1da287fd281f5736450c15d55d2efda1cf143660582b51c61172324ef972ac8867d4adac40905	1618421706000000	1619026506000000	1682098506000000	1776706506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ff8c708258f51242c2ae3512b6c75f3fad131f7d8778579db418448ae482632309ca565c85411d722e3927541a970fe69798a90faafb33b2634a521205d4188	\\x00800003be83fd82d1fce9fb52c8f11d0175e7d8bc18c288b4ad5f6748c8aa6f14d1f9fe831df358da4553950aa2a28b364ee591392ce827c5fd4110e3e628ca23bc60469db2c8c97c3e1da760d8ae6ba8c289bfe38e38503986e36021f15681f2ad2a1bb63513bbcbbce9a29806ddd34cb748de09b497af78634b6b4fc28ab0f23a24a1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xba92db7e7e2f28ed48c64d866d85653b3b06bb30eeda40c023e7a7d214293e47b19adafd5f059731e89d9275e4528aabb6ba2833484c707c54a0f7cd7abe0601	1631116206000000	1631721006000000	1694793006000000	1789401006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8018901f57244ffb10b682b08811aa98700f94b0517b14c3ae5b41e11dc54f9a42aaaa0ed0fe59c8d1392b0b574bf8c45d71cd6e0c302de44ee579f58d74029c	\\x00800003c005bf0fc8099ea6620ea482817ab375bd84d4c3a293a5d1b22fdf511d2cdfff5c099564f14ef015c4ae95620fc0b4784c1f2cee412e1dc3f0a5530693f090219a5631051508a23ed03967ad1ea1a32398f91dcac61cee149864ac6bf0c16f01c97284ce07d3d62b49b838c0b3b9cb625461a4a8a7df86eea2acfe9fb3b7eb95010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa5e555acf77e211e7ffd5c891400f3638c597f6d7c2880fe82c288b4ed24f0a94e843773da2fa61fa2417dcf05ef9ee1c85cb679c2603e1d7eba833fb7d25a0c	1622653206000000	1623258006000000	1686330006000000	1780938006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x80549b4de4a78fb92c2499b27b192685a83b67600f699ff35d2ead437aecfd3793860acd66ce08f970bc7f7f2b5363ca49d1e1a40bf44d8081397740c2a639da	\\x00800003a7858cdd8a848920ed97c02440c933d5707bdfd91a3d7b312da3133207fee5f738b9297cbe1b20fcfe8785c817cfb67a59b40736f8b8692efa091e21097940c931e13d5dec9a7b452eec39579d6a83d967144636723f3203d11531bea83e68765d23e5f64b8ad3db5de6fd53c85247479b7a62aff61c35826ed7fda430541cbb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0ae2e885c80360612151e28608e1c79e97e54fc3117120898a3c2824be0830a6b1d1b7802f441256dd2f1acc3f8bdf572a74fb45f0bde88ab8a4ae59e9e7cf03	1618421706000000	1619026506000000	1682098506000000	1776706506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8570fe26dc22508270eeeb06bd4f5b59bbfcac932f9c3a0cd5563512e507e93917f2216a72d4ee96480b19305bb246dc68dfa41e9a2999e324a66d42cabf1d7b	\\x00800003de4c2be12d6082fb4ec35b1ebd34ebe12974431dadbcc051325183eec9c0c1a291b928a7f146de19745420b46a87b4a6bea590fbf70ca68fc4c50a8c70c8e71f0a17498e4b9ef28ac3297e10e7653bc327630d0858181a545b60ed1aec9fd8e463bd099e9e153957e4360e17dbeb6ef5104a17414f7bf1cd20b407d93b213aad010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc145e1979167e72d0c9c1a03326e3c40f8a87b232a84bbfa889ddb1e9c19cbc4346d1262654ff3df1c5de07b05f1ef647887797b27c88ea0e4be9be3531cf402	1615399206000000	1616004006000000	1679076006000000	1773684006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8868aa7e30051934e14157bec333e8d72dc8da78acc863fbdea48844bb115de33238cf5c990f928b81ec8cc8aaa8cdeac5593a701b1bac353c08a0e3c65c2b8e	\\x00800003e90187fbc078ce3e906ea781c68bf1f9a7a1b318ae8387beeb61ba06821a0bf20f45cf91bd2136db8a7d19705063890706f2fcd800a45427ce4901371c833621ea32bce5287be7fb7b785fbe8d8b4a64a9f2256e29deaf8cf5b456b950fc611806c71536fe6e57f8ace6ed048c8b862d9ced78145f1fe37045deb1cad1543479010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x65b544797fed2de42c65d69d963c5f410c3725c771b6c433eb9a45dd43be5cfb3786fd89fc157150d3eae772fc6637cebdf7224ffffcc8d9b350e5542769130e	1638370206000000	1638975006000000	1702047006000000	1796655006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8db8888b576138dcf3ef34956fdf6bc5d0f7f6128788d93328105cf8cd344a47c9a549c14881e4367034a219d672559741820a6c025841773d55200290516a91	\\x00800003f5ec8a61fcd43ec4531a95efddf9b837340face066c53a0b19ccd5c2fc0cbf500910d676764f1407a18000fe41469dfa522114c56b9f612f1f1fa3b7ccf77ee4cbe41115a2d49e6cfb92ef66cc1def11a7b7d0a6cedc87780b4d6e24502ae32bf3ca6ca7c51ae3db8d9187b9e48ee9cc449f908072afc34dd76ccf76dfe12c57010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x410234e44bbd40f3892b63113b8dae801e23ef9ed61ee967ceccb154fa92b26a4c2a1b7c50786844ad9039e23db895fdedfb9eaec9fdf666c409be967f56b408	1609958706000000	1610563506000000	1673635506000000	1768243506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8de4f59fb9d7f1801853b29b1166ea79de641816b20ffdec36eb8e0901660ecb30ad9f8da68395501b38a8c93bf4d316e563a2c1d173863890f25aa50b0a7e57	\\x00800003aa68a2e153cdbc6193ca34879e1d310374e2841de92571438c7c5ef9334faf18b9b63cda0dfcb40c297dd3402ff3b1b419cd04cb189016059e1c4c7f4a377ee96e7a0be916dd2bd80eb28f5196e1fa59683158ed742a9cb4dbbd61dd2d0ec59f02b916c1018639423640ad1f0fd8ae1c517e4aed625d6cc01dc539d171b01a93010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x76a11f877f03e6d82f0b17b1c388b9648359d13f95e079b170d68084e903750f8334cd32147a14a30040d5593f9cbf7ba8c1b13589adba7ec312364f7237650f	1636556706000000	1637161506000000	1700233506000000	1794841506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x92e449292807b2673a2ec04e27bb070535500d06996dc55a290410418c7efe077cf8df550053104c78d0286e5513ae383014fbc68347a944836d837caad273c0	\\x008000039dae39ff47734f00101bd501ec8d03cacf6f0149073b8eda8b143c2919fa5676bb4a54c9b8666f8767e071885dec4d6e9af73fbb0bf980006e1aacdd86e24d2384f926ceaee3e02338bad0aa6c8cce54757537b63ec82d8c80e868bf70ff42cea1d6a583c77b9aa68131f8db3e59c9b8475545dab75abc4e9fc3319d0d2bc8a1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4453641646c7cbf7f50ba3cd44ec15d4bea17f6c8726b33c11f847abfa1cfc939e43c7651fab57341682f3ddc22a762a5b475889f40e703b49b32e1e5cf94d00	1618421706000000	1619026506000000	1682098506000000	1776706506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x95a8d4ee49367208cb1b1c60a5044a7e5ed46107e95bda3e0e338298880b68ec61976adfcb4f13a10121ddbe55974fbfbafa4685ade90892690162453caa2cc5	\\x00800003d55ec23d6668f0ef3de4f2150d773964896d34ac63a70de7ee6f5fe5f2545ff712759ed331a12a6b8fa84c6a9a50ab3f43792a4350bc471cc310c8e69ccd7415af8ec30ac111c467d0d06679a2e5e5ffc7de05c52c06e0b2c7485941c6fc0084337add3577c185b9eaa2052ee790f86bddd35fbbbf2f3c1bfcad70eba90e2c6f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe25fed189e00e8db44fc179208a5ba75e6199f9744db0d571d5b55171b91355b21ec8eba8080f07e51511c06f0d57daa223cda80da68bdb13d462a10f3d5730c	1623257706000000	1623862506000000	1686934506000000	1781542506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9684de9f22887b2dc490aa9272790dab1f43319145c583d2798323e28cfabfde400d2390a9112655eb8fd46da0c7dded9dec16ea369f7023b8e3844e359d1769	\\x00800003ae61f7284b5d42bfa3ad98fc4ec9d0cd20beff4ed6cd295df673c89abc4c3c5f2a381526094a8b152cd0ae878504c0c732f77e4ecb5cabb36074896b8996bcc607fe2bfe8381fcd64f6acb4885939468adf9ec355aba5d0657d2e326b25920a7b3426f80b23cdd3a827ac57baae2489b953b69200693164698a0bee50df1e9ef010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc3a146f1726b20d42cbf8542d293ba3722914d0d7e03ca044e056eec69fa0389777500847750e38387c9aae28e879282501a9037eaccd8b78abdf6f5bcfd8604	1617212706000000	1617817506000000	1680889506000000	1775497506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98c046cc10e793c0d8b17dff49998730c7fd592897309f84a36c2761f2da8c3f11b598ec91f54fd2b8f5a78dc93ada92b40430584fad31a1a40b715b0bda28f5	\\x00800003b99374b471da7a0e5ef04b64b9c925654bda3807d18bcbdf5772b5bb2f0865af90a4e08355cece48a143cd1e57825463cd9ded191862a1e67d48b15317a438721d7ced67af062346dde2ccd0690c6bff1179480f0a99a361f5ce8ba8883e50f4932358fccdf1a9553f5e54de468ba9acafecdd046f20ccbd630c2f6c1a5a1775010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9b29ab794190a680ad08bc5c7cbf267735b97f4441bf1d542588a001fdc69041e2a8e057a41a90aded89a204a5e4b8d242efa9bfbed66b1bdf79bf213eb5540b	1614794706000000	1615399506000000	1678471506000000	1773079506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a400f5a89b3a7f254a9503cbefabbe34d31cf90ad34e356288e6f322fbefaab3b734179b1de688d5ed21272d0989e1cfb4eed8a5dc90da134e889cf481b90ad	\\x00800003ac9c98f54f25e91052d5937c8bd1f369082712f19387de615c951d3367f67d87832bfdd1bdd75ecd5340c3350641df76c020a942b6e47675becbde54e459c741a254efe138ddb3b8d666814e7d1989ef5e63807102cdb02b0ee347b185e957a8684b5a5ff2fc8767c27029e2bb9ff346bf364ace0156af2f008a54d2901cb0f3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9af53c6eed04feb6d64aa04012b289e534ca422f3bd8f56347495f57c9756cfed34cf9e977c63ebf6a167b669147faa05495079b4c353e0d1c857dbca85d730f	1635952206000000	1636557006000000	1699629006000000	1794237006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9bfc4724e6eebe025a00d2e2f33f7491109e8424d8c0c4c8d51fa8db0da6b2195f2a3a4123217d83838271eba98a2b4b68ff25d6231c137f59dc6c9b66a12681	\\x00800003b53afc527f899d44a32628fd8aa49c8afc508e789240f5635cc8284cf1553c1d304de56b0b1f133b27b8480178bd6d87be365cfcec59ab34695951daded729b222efd5c34dd02bf15066a693a79d9d00dbe9d27c0637256561a308081438b574f8cb0a3621c6fd676856fdf87a073b4599b43992e97a9d6855b0b6051a2998dd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6ea7e0ac92b222989a2b845a3af4735db7259a318dc28d6c4b05fcdbb38d214ba170f45ffb719809b848121bb6c7291eb3097254710f51305cc5523007281b09	1620839706000000	1621444506000000	1684516506000000	1779124506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2b006305d3a80e8a27d15c61ec1d80bfe73f09eb8b1d635ac3db6d6e71f08347410b6dfc2e9cf5971df45fd2c4a0497d8efcff519626ef4b7717bf49c1fd8a5	\\x00800003cd4f9c8be4a7258be94e43c5ccd36b09f76b8901b5c7b082d4d870a11191f455ef737c90042d58651ac2bf6b11a431f30e7123d1bad55ab17ce257e3e4ba3e2a506a53283c505604fb9148d56b24b9a569dde64dd51e19d202b6ef79c88b8db6009d9fb7b170a2957635494f2b70383ce915045c01aa6cb737a6de4659e0d791010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x06be6862ff1c0d621203a870cfbed7f5d070fbcb13dc9f5b46f4ee30c5f898f19caa127e0739923314fb7bb55205a203eab7e59d1a61b180e5326db82244ff0b	1632929706000000	1633534506000000	1696606506000000	1791214506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab947d49b41502b6448600c2e84dd7314360c9ee1183d1d401424c81fdc24bbd83d191cf28ce18cab087b18d72a578d179ce0456e70d522a174384011cc367fa	\\x00800003a5a21e63b0ec1a2674404b4cd42efe888705b7a765d9a8b92d83bbc501e83aaa70cd4b543fcd57fe9e9c0a14bb1077172a555c9d4c08ee2568f81ad82295be5628746f1be0415cdcfa81a26b926a364b5b8b62d302a49be42d208bc8cb3be17ae92ffc1672f24a162d625c5f0a27b5dee1a7cdfc7f2f14f9e1e29821aa25d333010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x88e6db3b1dd2c4eae2e21f3683147309d623bbc484811af04fceb05289a18eb115e6e2b30a76d3ace277d7dcd1e6f21af45c5d0119512939ee535a9130b6be02	1631116206000000	1631721006000000	1694793006000000	1789401006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaec011c02766d1830ceccc83a26fcdfaa7c54e3626e92727083d5801e5557a69a7d43d15f8b2995e9e35ad3b4b035201560f50bc1b6f2d0f44c855b5449369f1	\\x00800003b70ead8f098c44b4aedff3198351fc659b900ec7e05242dc1b63dc9e7506aa4354295ab9d2a5f7d602f8088e019d69ddb276cec31cdc68b17fd05b606efe7ef50aa78c9533dedd4e77e0a83f280b1a3977261d2eab74a446261c419fe57d4bebb70c0c30f89b619010c5ee3c0243181fdbc5ea3a29a5fea30e2ee116eabf43e9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdb8fbe400a1bfc805958886c90f2c99df39e69cba2d4ff9d016000f437528adc65e4702aeb0f90659413a3af42727e6dfbc93b31e151a4b796601e72d44d7205	1633534206000000	1634139006000000	1697211006000000	1791819006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf9cabd98de19f0cc592c708d0e7c45dc44e53d0c61ef50f0f380f19f8d87872f46711efebb1a1fceed4b2edd86bc29b76bd76129f7febe34e059c8a5fa8bf54	\\x00800003d5bf3971d84d57dba0140c813b28f7da5759df30485de00822aa27ea38957cf49671788ce186a637d4a3e17e00f636a3d4e917dc6e6bda078e58d12856b4baa63a4e78626251cc5732605874c5cc56fea77445f9b49e23e54adc1353dc7c437376caffc1ca945217bb06f66f063d72c1d6e9eb4ac7f61349c0b42fc090be34f9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdecdf39910fb7615e9f49a3b98aa374bf0b4a4bd2ffdb53ee8f8bc362892d9abfcab1151df7e3ebfa47652841e71f4b79dc7564ad3977c92a50d3d1ddcaa1d0a	1624466706000000	1625071506000000	1688143506000000	1782751506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafb43f509371f12fa4b328ec2acedb170ee8739f9d7d8a615def3b9169ae70d3f4cd43b95efb3d0b85f49319be3dea9b0c2d2278ced6ead95b74f60aae8009c8	\\x00800003d63eac05960aa6699a79b505c0e709090b9ef8427e72a1dc89f132918038eb713a34e32a6da5ea14622fee3fc6c3f69c83c21109ef8ca5d519a5ceb7be27cc9e6e009474ea8e70c4b873ac58c37493c18fd3247d3d3df57aa12061b096228034363e3ca94babdf264584e1b5f117a1b3b93ff185e9f7eaf9b136ea1f8f1d8971010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd9252f1da6593b15b08756da8390083057c2da66ead4d371d58a97a2cf00eec07811783a11b1fec54e2228f0cbd319c5c8e9244c77a25b09f1612ee903e4cd0d	1616003706000000	1616608506000000	1679680506000000	1774288506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb45c346347ea985ffa18ae3c50a5bff5fde4df004e8868e806679b089cb6d78582a4183f7647710971aff1bb5912359d5f19ae264091c2c7c9c36dd3aa28b4fa	\\x00800003d7b89962e0413832915345490728d4dc076623644f1dc35fa40b8d7c125c9fbc535137cac366e7e06513a368c297724e69853d343c2ba3f403949a39d409d4f766668e104263051b3da1f19ecfee875bfa6c0a244f03e2c6ff3e7f21930ec0a85b61d5852b3abf34d6b03cc41f7bb54a5b47cc76a9b05ebd8510100aae7c5835010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd6b9f72536aa5a9585dd28c3eed002f4f5f7d482da88d05b83f771ba9b636e15c2e657307dbc001d4bed200a131bb1e196ff9d8bf9c3d702aad1c5489a6e5001	1614794706000000	1615399506000000	1678471506000000	1773079506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb64074094166c3b77e98709a62ca1c5852d9a4ee30e27723294729a46efe44fc5d629d85be958d685985ad4b3e8153486986b2deff8e461bdf2d4680c9631794	\\x00800003e8ee22e9deec7f6022b0a0d71caa0ecada3f7450a8551770cb4f81b932d3b308367ae33fefbd29bba70690957831c8c97ab892d47ce1bc1971bcbbb7d9669aaca6e15f66c68452eab1d40e516a10e071609067e70e364307001d467b99e228dc8127c9b45735fc51654217603a78028a6927dce2f2d95880416a7d399259f12b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x021d8b91a345312871aaae5fb79443950d8257370257dc010e5d29972f42acf8912b244996de015fe70d8a53ade55fd8f2dfba3af8af7e2de3eb2af3d86d5808	1616608206000000	1617213006000000	1680285006000000	1774893006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb9202ccd79f88de9ac862cf1b912d81f4818296bdef419534942bf504f5968f73cedeecdb03fd0b784a965d4dfa9d2f6d781a577021ad8b244f1cb10b3185f64	\\x00800003ac61cd0ba4580ac49d86457353600a27ec91ba6f603cf0c152d08deae387979f3b804f4a176dd8c9c9f9490528d98514e85d17855cfa9fe17a179750064eb3ed6ac594ba999a6f57e67c9a667a7469a2fb11139667dd4ac059af136222ab75182bb456c6a87c2d96707c8fd02038e83d4f26f5b9083303de822246c4a36ae695010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0d96423f03cc829598c93fc755ce439c0e978d18541af8be5fbb6ef3f18ff4f3e2c67ee24aa2b3c822a73c23aff7de94acf91b66c87479d63ed154044e6f720d	1629302706000000	1629907506000000	1692979506000000	1787587506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb90c851f01564fefb5474a7c84a1360cda6e064ff299d65cb7668a674e27cbf151148736e0cd60422540ca0c3aba04485ac8acfd5ed94d5a63b671d39f07ac5f	\\x00800003d300ca356fe3a7ed61e9ca409fa630f160502a52c436b6531bc0114b81dd4c290b2792888b6a93821fb99673aef4349c7dc6db0653dcb1852cbe899ed0c3f172be8cdd743d04bed8f6705c76b46255f4ebc6183e7fc13ea56a85151e1d889ff75889a9e28ff61e9e5b6a5e00532b07c70bf25c690d0b7f66ea89bf022b7d21e5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa5283b6c10eab4c711b43c5f46145c43f9638cb34136eebb114320db4205fb66e53c9244a7b78b15e9ca4c89127d48f698b8958d0b8eab5676294575b7e8a00d	1627489206000000	1628094006000000	1691166006000000	1785774006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbbe45941a4174bb84012e9dc5775abdd01d15806d8f6d4e726dd73a25ce0b58eb11726c1ccd529cdc1c6dd31f932f8ac161e9fd1deba97d6c0ec6fd274957d4a	\\x00800003efdd60ce295b934c871ca19035611f5c4b8a94e92ae869a4b26e37cb294c04eca03c879229dba0ebc53e4fef8339aebcfecc9f29165d10e80a039991e14c39447b3611700304ecabfd290a8290cad1379d956e6aef913cb26c51cdc30f6db96291f30bdf5343a740c94ebe1a679afdf51e4f08a68bd851f86ece1ce38527f683010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa8cac97ad99dd0c1f464c524649a1bcb15a6f28607c8d0ac2dd8350b1b90f76325a78c1b8130c107e189d8b3036ba2902ac0dec71011b81bedd58da9fa40cf0d	1617212706000000	1617817506000000	1680889506000000	1775497506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc68fbe818bd429c2b4bfecad83a507d9c64f74df3ff91345993407f00ace0aa9337ea0e25c2e0e36b90764f04c79873fcf14beeae81ab8dffd545192588f43d	\\x00800003e7066ab3da93b23c644276a7970dd9de836e4267989556437fbffd5e22b9bfc3b1c27882145278568d0f068723e449682506fe7e8361bbad6db2c5c3f2b8f3b0e7ff1232d090afe96c0862d2ab57861110525c6813a2042334e47cae3836e020afc0bd806f2ff9f41206b82fc62537969fa484d2b6524988783b1121ebf79545010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xca11ea4a1c29f223086a91203366e5013ea2e72db408c839740ea21e8fe385b78a7c0a58fe9d00267cb8b3be4fd089ebe6227b23ea6e267853721ac7e492c009	1624466706000000	1625071506000000	1688143506000000	1782751506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbec4625f9d9cbe981a161be143ae897b22a80965e38e29e19456dbb3a74d6f5438a14bbb7dce52802a2050ae3079ffb102355ce8853127b6aabc2aeede7d4ac0	\\x00800003d6def6bc243520e2ec1c018b271c46e5dc1ce91c6370df5c4150b2ce640489b20456ead1e9e916adf72e08d82fb8f3a35212bf8e2746e1f5ed072c7356cce9c006f290f21b68fb1712e4083e0e5fdc7c3d6ef16ea38ac86e5724b0edf65440b06e230fb2e77e9de3e8cd3d566ab058cd46079c20be1119416f89e2cb2542c4a7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x55ef58d62e3562d5a86b62d1ba4dd05ac89e3151755afd1822dae3a64338c8656db7bb38488ddc532852cec2b1164268454268a053486b72d910a4544829b107	1619630706000000	1620235506000000	1683307506000000	1777915506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc3040aa528254700228c19a582c03289fddf1a603e87e5973945a5aae9b6c7101c9d42e05cb6885ff5cd8ae4b07fda10f9454d87ad748f8c1692da97525e166d	\\x00800003c4c6ec2b0a8451622e6cdcebe4137dc866741633adc8d5c2b4265693c9bdeef32b1727f0017bbe8a296e2d6409bdf3b1e48112eaef82067ab8ea104c626eb34b71198e388bb674e44c08d317f811e6f760d910d3aa97ad49ab521fb8c570f4472a4aa5aafd69700cde42ebfa3380594c888261076409098479a8b529ea42ec23010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x15bab16db8a2ed624092b5f2700b4d74c06227ad9e64a04156b4be77783bdb933e0a47b5f1ce432ecacf5d169698b3f69cdb2276ca2f5ff1082fcb83084e9c01	1638974706000000	1639579506000000	1702651506000000	1797259506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc4446cfe0ae0ddb82c6f0ae728b94616e0c58ad4b20ac1f54d1373e9c795ef5e78a15cc6a81c81181ebc7c8ae3f1af99b3eda227a754b043df3c635ed8b46ba7	\\x00800003c7862b1d67c19ecab2e5a766c07941f347224c4010ae4102e58d8acd34bcdfa92fe84cb28fab9281e0bdc71f1cf962a5c9a3271829a40de02b2f3fc0121bd546af03534b5fbeaf7de5a8ae9ec75fa6d6dea2178c6a471f710917cc5c53789fd67b35116df643b6af1a75d52aa7fad8c7bd0e5b2b3fa3b940836f915f001003dd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x12f5ed62d58e4790b619ca04b5a5866f9bfe43018cdc861818a6d0e7e93dc808274c1d710453fa15fb686103019d2e6bf1c2faa6943d7ff794a5b9aa4e825909	1632929706000000	1633534506000000	1696606506000000	1791214506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc4341bab6401e066bc2aee64e72b9c475e49e5fc7fa6796322c74c715bdf1c8a0b6ab54c30f36fba720732f3a032ae9bed61f8b98f87beca0bcc5f33b9479dad	\\x00800003b6ea01846becc216612766eb7510a556f59da85fbb0285972e3f988d47917a93dac2910dcac57d6650dd78dba093743acd216ce39ff797b2b071b6dd2dfbfb8747ce69cdac4545e2e7f2086e719c4135836e003e105571cdebad2924d9150a6cf7a8273f089848c5b487f15b708dc81f629108fbbda3b364e169347aea60230f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf2e41d2257828fab555b13f6cd39dd477056d170bb9acf5ae82feb75602f76da3fa61ebec5d0f24ad6f047fd44aca6f0e4e2766c85dd6310d73f0b7eaa79d20a	1626280206000000	1626885006000000	1689957006000000	1784565006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc75cbc782a01f29614766f1a88a322adc6ce5fd3c5354735ba463c57cfe08916595b427328d39a87f735e63991c361514dca5aa2fee7066c6861cea1abf3ce4f	\\x00800003cb256b99f1c7e13e96a3eed0a4816d6fa9ae22649da7c35c8602ec167595ac94a574e1512400f059a0d301803c81a9beba361739d1cd36bec87a58279ca7df5556c5f75bc4c4a8c94fa028e3efdca2684925309ff79b7e01bf55c7c7a076537e8cdf297b3dbac9b7371e6cf5ac91023de65ce6564eb79f5d20575634f544ac7b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe698f36702f91db3653eab83d8626aa4d760243882325c878a8d24ac023adc1e57a5e93ea6bc3fd20781515c61743b09151677ea22508cd3e5a65d732f2e6001	1620235206000000	1620840006000000	1683912006000000	1778520006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc99890374d28db717d69e67668e4ec21cb56f6fcfec3eebe8453dec3d2adc5693fdd0ff5502c4a35a416df9317f93627ebe08068247881acc970c8f9fdf304fe	\\x00800003af8543a1291c345e0b82942610649e2386667eabde9f7ab2f90e28e666734503dee458721682467419b6009afca0b745a3abacd27255eb06b1307217695d086e75f15d1b8534a6499e089a3c18914814f7e3b865c645ba60fd03c948bb9bc68d7eeb9603c64f2a6e4d8b136efeaf5093f60fa02f4135c7571d73f42ea7ea0d2f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x77beda372e8bbb8ab58e2f60480d80c2df9e8384f119089dfc4db81609f8787619535713e0c4d0db2dcb3cbd65eda2375852820eb7752df72e07e75ac885850b	1612981206000000	1613586006000000	1676658006000000	1771266006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc9a82de5a28fb57d7ad9710863c1375f0ca080e5102c9500eba08fe34d74c295a7029304bfb808de8e19faceb36715019a09cd3b23231de8681ca9311b11f5e4	\\x00800003af9bdf163e4bc16889e581a27784710405896ad0cc08fc27117e994898b65c6774d56589f13663e11f449a48f890678be14447ebdb1ffb5e0bca9026c11d22dd629c2a230cd750e070231527775c47600fd0de70edd374fa6451c1d32f2d2a815e2a6a89d3c8dbed9918e030179fe030d336d4b6676f3709b38e422af13592c5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x073819aab01b5429f2d7a666245dca9338275dc64b6c6e0d74db9538e46a7e926ebb458c0161537ae7982f47c54213c9938c595cc0daccfa6097e6ae73cfef0e	1637161206000000	1637766006000000	1700838006000000	1795446006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcc1c806637ca9fad47c8a2364ba0044d715a4af806b51d21c5ab4b5424dd75903735d845ebca4b3fba1ff2f02e85a6049abe0356173e1fd4707d674af6fe132b	\\x00800003c0e5ceeb60a23bb987c90719057c21c64c21b2e92f8c1a91f10064e2d0e76c6060e3db52081104bc0a8db8ffe025669cd732ae716bb86efdf18cd92a12bda18798ea0fdcfdb6ca869433469c73f060a047ee34b992cf7b06cb790095c05b371567378193c4129267062ed8b0a452b67f70fb6fb5b6e136c3103fedeb4b31dc8b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3a0638c8820cae9f9bad1087127721e0a68ffd3dd35f6b374f796648ba654fb002e72f9bb578e1a10b39503cac5ed70a85f1fdc6218a8e18aaf8b5b904aa3a0a	1636556706000000	1637161506000000	1700233506000000	1794841506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd3b47db26f36e6d889867a6fa3a6a7229d3a8ef5bfc5a59f55e168f42b12a6e596e07bb1676ff94aafffae5279a3657fb7cc6ef62d92369062221ec15a8cd5f0	\\x00800003cab4da57dd3101c8cf28a3b158fee9ed248193a3676d06085e438b90c5dabbf62f59326ef59bba78f7e48a42bb6585af4ac9b46ea42a8c012e82f1012f233d34b40afbfe3dc288ed1de187b525f706c845714ea8039a91709132c61936b788215f28fff045e62412c85216670a52ce2253fddf73fc12918e81a819bade75469b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb106c44ca6051d5c845a5a08e3d0c326e6d2796a722b06e426c66cb8ae1cf3e104dd9213002793bd5a1eca178ca3ca05acc0b6ed6aafe47529f862ca03974401	1626884706000000	1627489506000000	1690561506000000	1785169506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6f0a6ff816c6bb8c1149f421a21ab84a054348b6ca998f588970b27a46ae9c83f2ce73fda886d0bff8b8235449500efeed6205f873e807125495a9f01eb9017	\\x00800003ce5e60e20b9b4eb2eb9234a23d327ecdee0a3b8ebd25b66536ed6b7ee652626f7d3cafee912a010636cc194a2a5d65641e098db56194b0c3bf8a133c5b54eaf87156d1bde94cf6f9293ba979bf9f6c0ae940c447e58ea2915a498a72d7910c9e66bbdf80445a05a5f22be7f3287902b86339e8a08a66d24497ffc51ebfac3df7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5acb2616479e908bb4831ee8a3ca6e46f10886a15e5b394aedeb658dbd11b1ac2200f80300f380c1f86e0422dd5dfc10f337bf2dd83acbcd90100c2b77de580b	1617817206000000	1618422006000000	1681494006000000	1776102006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd98c6d2a94f81c9209b5b5bbcae3861cd6380b5497b6493be9d7667059f8913983f75cd93712ae94e675dcbfbdee88f16c00c1a4dd8ca22ab706f57240ea3038	\\x00800003d8a502d2e049ca2ccdb2349e53b389b8a0adbec31222d720b28be78f60d5973ea9205f538b8eaa0012a51eff7e46ae0ada73c02b699852bb35b88e703754b75034e359f7ed88b8c5c554cffe57f483c162ac1419360ab75e53c07f1a00f9cdc8c734ac1d6ad23b813a0414263ee9fba153968e49c0ff8827a0430a83f1ed9749010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x19528651b57391f8c30171c38170cb871a1a25f725f4b68347cf5701a63aed899f453cf53738c2e7b24488425b323ab3d15fbdeee9600db627abcb12db10560b	1634138706000000	1634743506000000	1697815506000000	1792423506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xddf4cb6dd3952f872bfa23879bf2e1fbaa34054f2da1a242e89149229f8489f4306589f02ee3596f46038b2213f40751f4964de20d42530d7ebacc1cd3b0cb95	\\x00800003d5a7b78c214909685d19f8de95f429d618e912eec9a82ac71e8fc34030dbd5d0860993ae372818983b3f3989288f62d7e49eb46b0cc43854e6cdd69fc3dfc45d6d55dfdacb8c5af5ec39ea0bd73983d3f89f4f19e43eca7e98947ccd528ef344bf6ffad478700b9245c13e070060b9dc9c1d57921a2785f0675d525ac19f91f3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x70724cb638249131d0b41e3a3f9c9fcf8b83b5fa357cd638e800653492bd15729e1515dc58ca0cb91da88c0eea96594b40fa4e8a372e9fc556ff18161cd5e103	1612376706000000	1612981506000000	1676053506000000	1770661506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdee046aa5b6ffdf4d5c1d9f67cb84048c21ef3aa4d1e94a8c5f6d74313849eea41da34dc9a12bbbf3ba003338ead0b43a8cae34d16874529d30bb4e9f54a4cd2	\\x00800003e279ddab5d949548b22133f13f8743fe5384ecc850774c5af74fc3ea735562af7c8ee40ffe68db18ac689dc32f859adf730e93f893bab3bf2a37539d60d24fbce49abe4d81f0a1dc8e8170ee7e0a571ce3742f850da8a2d25361964e03fc17668d8580f43e715e468d7970ea6c89856cf301fba9d33e9c898565f3c1e1c4daef010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5da441b43f95046949a3e01eb5939c7a94bf9d03d29937bc86141a5e4283cb0b308280ee6e9d8ecb53a5d43d9ee2caa434016cdcb4f4983b47f2210aaec05a09	1629302706000000	1629907506000000	1692979506000000	1787587506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf141d4ec58e291d23fa75c9e21eabbee4d6a5fe570af26cc5f9966f721a158939e173a159c88c1df8463a25bd7f16c76bef1c22f9610e68217d858f2c11f6e6	\\x00800003ab2702aee2e26b9f8a4e52c4675f4e014e09065c1c321bbe2c2fc94c213f6fa558f317d1a055a5e6fb1e066f0801702c7e19ced8cb5bbe0cffb4e216b96dfef81124e3443d5e68850557f4fc9b42aa9d7e63ece173f6708e5ef8e7b465e5e84a63cdf7e33a823ecf4f1aa4b23bfa371f717604dae67339b4949db01ec97edc51010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0d6291539971fe4f0f5dd089ed96ed2f6bb613f11ea9c672f24b35e5b7bf61f0d77322787394c776ffe2189d2d331d4c655712d79f14b603c51d21ed4bf4850c	1614794706000000	1615399506000000	1678471506000000	1773079506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe910a10e10f07cb0287c340b943403173b35e1d2f1f9e924c9483d0b880f1ef44dd5255a5cc916b7951a3b13cae52b78bcb31cbdb7aa71c178e8a89fe3150105	\\x00800003c80497ddeba071d02b34d0fc1af7a0d6dbfaeed6625d206c84712f386ac585c73d490756686e03de13447b2ebb1b241d3b48700ca777c086861be8a625c60a8f86349213923aabcaf7c8c293fccbe126f29b316f9367a947574ab84806e7903961b678ca0ed3e5f19495ca6af8a39fa281b9328feb589c09e281d509a95f5f89010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1fb70138b5847d8a5de8d215112cb5c50b9e3f1c736fb52db2f5b895c14d4a95a0f31d2dca8ba9e40dc6ec150cb81ffe6cd66a78f5c7954138e724f569ea9f08	1623862206000000	1624467006000000	1687539006000000	1782147006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xebd4eb05b94f712efb7988dd7abb744c5ed86fe8f4dca38417c9ceb63fb3ad16d87cb93a6d026f8bc1fbce880931588ad54491856748b94d67a4b07959649c88	\\x00800003d2fcb1caae8a3767b6248a8ecd7a809dca674cf0ce726d76c7d8ee337967817727fdc45779243892279bcb87f756e60465704805e89bfa883fef5ff689826bd6e68d130a18273a9ef08d9709fbe1aeceb96aa57790dadc817162253c3e5c0038c0d2f36e06146a7e63d9f63468a908fca7eeceb509cdc7d5c3cb89188cfe0cdf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc8fbafc8a19177be36f07951c1126527da5128bd282104bfb413d7a89e4650dc3884aa31fe086e2c5c736795aeceeceb7e753d5d6caed324a256af639aabed04	1617817206000000	1618422006000000	1681494006000000	1776102006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xecd031cf99a8b12cb8a56071a84b7a9dff17f4f528c3ee3534c7819b570309f6459637da60da7c7ed48dde3515ffab4db725c91cc4cd0d45ba0ad2063ae3dafc	\\x00800003b6592766101b48a30cfb8d23da71a2d7cc391770c0b1b0180da161dfbc044a9952a51afad4d2ba4cf8edfb40c818ab5bd078bd49809826bc9b53cb74edc3c534e9532fa92f261736dc4b117aefa396576d69d7cf30eeae564a5f85567a570b8704c46876228cf34670bf8ed9c33b4fba99223645960a0f14332c61897b28dac5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb81863cca070d3bc8768fc6f2bb4da208e4fe7f2d682f946ea0a31f65ac00afc37cf81d810b836c5adf465fc968e048da5b1423c5e085713d45686c73b968309	1636556706000000	1637161506000000	1700233506000000	1794841506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xee7066e0fb83ba872f644998cb63b2eb70432da5e98e1b283aa86d0001cad6035556a3383eeceed9b0f03c5c0af291b50f200456b06e6b401a465d92732efccd	\\x00800003bc6749cf45851719dbc231856c609db1cd08c7bf70f3b17f584b6742b98c9597863d546ef1676161c5d5fa98cfdf1a8455f58571bcf592cbe660a84c2f465478f5d2ec8e638957beb44a9c20f3ab296b8b851d189bd3dcce2386f5033a47af5747998cd208134dbd404510582dc939dfbe7f7f1c5d1488d9c98ff24c0b0d4ee9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd7b325d2331b4686c03689473e447f80595f45985eadfa51e0d7d95d65b24a3a7b22c7ab1e59fa5adf51fd3bbf7ce30137cd2219adef60a14832bee0b5418d0d	1630511706000000	1631116506000000	1694188506000000	1788796506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf0e03f8d617c106847ac12db5c1c03ce151446da8962d841476721623e0406f2eb931e0e0b7090b25570aa4485d8bf6e780a254d1bf245b68f19cfcbb29cee51	\\x00800003a159cfff1dabfe88b80a011ff66849a9bc160bafbc97a11c948bbf67e73146c84af9e58191dfed7a6c9754cf918b137aa2d514c7e3952dbe2b3b80a8cd3aef915aa33ef60167fbe87237145c81a16c90f6b7ecd4d1068ed9c76db0c22607e502430534050bd5bd1fe1699e2914723b236579095fb198644f3a9c34a9f996a9d5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2d1445a9230f27ba71f4b913c34890b494cdd9eb24f41b7ee4d76a0b640e1626065bf78426bf7c97cbf19f8d67a278476c9d4f8f67765d3968ed3fd3283ad50d	1638974706000000	1639579506000000	1702651506000000	1797259506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf1b836884cfd1f2dcf333942193453ef362897759c696473263de7dcd1b50d3b1aacf99570f602376700cba0094076831f099906e5ebaf21ba971dfa8370e2f6	\\x00800003d8bc22c8dfff53925d37cb636cbd746dd40030b5baa03499b365c7320b2c32d1eda28be73e8b153564903b7554d59422eea09fddf8fc4b24e22721036950be25e4c9a9b96006ceb7b40ba40b3f24a66f2ab007910280f902315337a9e924ac306310e4f876da9a3182da02ad2d1f3afd290e572ec15432dd4e0b256e5677dec9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8e4558a4fe015033e41b59b2fc969db4ac0eef40d00a4e0a391136d1da09ae119f7504d841586e2bfbe7be8d8357238cdb6cfc72de6e80b6773f4abf4b69110d	1619026206000000	1619631006000000	1682703006000000	1777311006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf980336bfc27e3f2c0e4b01914f50ad1bdfd991df15ae97f9d8fd008569c0d2493d07b79868541fd43f4b7d8235bfcfc793a23e724f321a217f3b3a7da40437c	\\x00800003b2496b50b21fe57221765d7ba9fa7187a9f5d9c4006683ff6f5291305c50209c68175714d3b11626d3b4a37e9b2de95ffc4e5a3ebde0d9fcf0bb979845ba2077cfcb44a1dfd2f063b20fd7b5d5b03e471b46c2b94a6f753c94dc6ffe35ec7a7ad6c2fd0d883307168313db217951d962ab35b26a4ec39870454555b483d7b92f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xadcc8bfa6a91649d9636fc2109f832d577efcb143cb46ae8c83312ee20e979739e0ae78223fc4c46649e71420b1b33e38bdc57943be3dbf4e9dc06a523722a06	1628698206000000	1629303006000000	1692375006000000	1786983006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfed484c15657ef9d6bf1c5542a16f15b9ecc65918f3d1ea12d6d4c3e09d745efebfa53cb49d512579db61fb743129cff297bb638889649842fdfe3df44efdd00	\\x00800003cfd8dc9b505f2f314068e5602c0ccd1f2dfd6067a21f37cbe532d42dde4f27b0c6d7def93abc5128ad053404cd4e5d0aac54db64be1291daa6c428853013956e3306dcfb2a78a284d9c23c25b59da098276501d4ae97713713ef9edf3f69d892eae2f81723d602b4767f4cd345b113ce5f7a3c47e6d687125d1ad746d5f3eefb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf066ac0390c86fd0e3bc8a7d499176355ae7623a7e9039b4333da2425b2aefc8bc7b7ba3abb7ae142a603ad537826b90ecc1954588622adbe77f1388a647a90d	1615399206000000	1616004006000000	1679076006000000	1773684006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x083d04b05064f328187933ed2ccefff564be9e79d82f50b132b74681366ac339c5f205d0030a952bce803cf32e83b3a7fce073ba388302334f1ac7ddbe9a989b	\\x00800003c53f56fd25aeda112fa6e3e6b44a1b3e0822c8508ca4eebe67f5400f2acd4075c4fef936bddc7d1e158198f55e9c24acb3b11d9fd23b6f2159d86b6544e7deec3d067e637171bcab08092c1d63c25f9a70e65ac57c54c0efc8feb78ec4524611259dc82390131aafdf4a7bc5e0262199642c5a784951aaf8e39594328725e7c1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf36563fc2bedd8b83f3fc5100663b994e8b727bc05192e4500edb6585b7fd0a3efe2ba16132c983750cc66397b7d36dfee6ee6a504a655fe889b67136715b00f	1625071206000000	1625676006000000	1688748006000000	1783356006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08f190f0e50d9444e2f87eb8e5478a36a376ef9e6ddb7f92f0a086755ccdbb2e869124c664cf3d9da4fd30f506469c3deea49ed6d31cc2736707e2c4c5f046db	\\x008000039cca60425d02f5ada4b7941136a8b72ce1c13b29aa074f30d828db4f810af2db8019b63acb8615ccc3a6149bf2069d68c0196ae1b58f07a58fdda6e0b7f79275437928c848e7e77143ee1fa1148a91b24622da6757ee2bf6f7201bf021d8855beed815a6b8821302a1fd2317419c08b883b0bb259b0955cf2f6c6d3f9b028fb3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x820be1674c0b9dc7219c9de06bbc2ad3f8bdb32a81b5e7e5a473d582e9d64a4b8cfe65b65484cc85d7ba594413b4637f05bffb45082d1b06e7abe5d983907202	1611772206000000	1612377006000000	1675449006000000	1770057006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0819c756318f6c844e8b9a401583138bc0ccc0c3160acbc1aec8ecb05713e28fe293a27e023ee25d5f2f805e3c1bdc0f81813c87099516a1f46a89a326b2ae64	\\x00800003d21a78f5da4321f79d5b8cd1d3cb45559402526b45825ccefe3e56e83f5d492e32b451a79e0050d541518080fab20a9d65c0c8be1de7ad6d8e32d8f61310df2b001fb5a1d6f1ee17400c7fdfbc71b8351e732207402dfc9e353da66e164c1fd416b034b667a6252e4033425cc306d9200a607397519c328b5afcc92318a840f9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb42feb76bcd0779790a723fffce9a52f552679586b867cc234ccb091d3b09711706c9c1a8d9ab82c4d6e99fd17be6feda1d766c5ee9985a677421834a6ca6f0b	1629907206000000	1630512006000000	1693584006000000	1788192006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x00800003d65613dcac0da3777c6b713a580f2c6e467325eca3d7dd42c364384ef0c6acb821c2f3190b44eb434daba659119fe1d43dae56b2934a8dbb7efac7b29f1a1ca2e213a0bd62e9d27d6f59f9cac227b5e9788344c7f100c32d3175a4f43de17ce0ac7a6ea4f4d03986b48b7f1e07382b38bd2d8be1d821703410e7f5d6a5c09c55010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x515048e2657c64564e7409163c054dc057a7d58b23b7a5aad97d2b70df4701ea2d596a12f097f1c5391eb980bb59502329c2e4db1c29bd4d8b1a6f9f16c74d03	1608145206000000	1608750006000000	1671822006000000	1766430006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0dbd4e56467b0c7b311d238e672d83a1260a347a5a6ea133eea31bb4b6fd341dab4ef52f3adc9ec2dc63ac4a7cb461cec6f4519b938bb66a9a482a7607d15317	\\x00800003d13aa73aee5ac5c758e6e7d0ef0fa6767f962638258c36b9e919e01d02c0a3ef774979693d22958ffdbc2e7d139a779de759e446449492c54b743afec11bd90c9b1a175b929e4d9eb3be65b159d1676ea589fa1d21c5b9a17571cc33b6059ab82681681b89eda16cdae1061ec6e5aabcdef54749821d790c72b8ea6ffb325f7d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb207601ed93e69d888df3b930f9bd5b6ded0d75fcea37c45176d56f55a009783f6942d050a6b142c03171254a624638ac9950bd4509821acf90a5bcce1c01e03	1636556706000000	1637161506000000	1700233506000000	1794841506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1039df2f270584f9972abcd046bcd0808735847a6967c26ffaedc523da55fd8257906c2257506bf551945f16f1f7bbed90da5c0511b63d2ab5a08e9919535044	\\x00800003c115e1e14b5cef50f8a8bc14bbf1bf032765ea3ffa70b840f5d758edf09d8ac4d77d3a556e8146c8ee8784ccdfbfd6858a574363b2cc3913b648de4fb729d5cac320ae7dda0f11918f48e8ab09f17d4bfa3971ef23b809dca14dee13099952a9d00eed9a985408d4beaafcc330c0d96781929eb62bec709ddaecd31e79b7fa6f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0f27ef75dba32b5dc5a30acbab8f2f43b6b1c6d8f0c43e35f06adf90349b85d9c026456eddc399337412c8f0abe36de17762df10d4c388a1f0efeec56b74950c	1637161206000000	1637766006000000	1700838006000000	1795446006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x10a52ce4b6fe04184c44b06712c044526ac11389dc4fab6fe21172db57571b12f362e133208773789cf6a2196233e62b17e50a73ef41b76304bf40e6339b7c7a	\\x00800003c67b1eab3150600ccae1cd2d0fd0a1ad977ecccdc3f587d61ab247e58886a6869392767fa3289415f6178b78cb0269714e796c8294a79f596a3a6e16611aa57d779edd4060ebd5fc241c1d1b7332475cdde010d7d9e01e86a8a7880b2e86a2813af389b2476816262ccd98c9432fd03c22e6d7dfe8f95223fa8d6197b4743831010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x49dea662b7c2289c49f42fb8aeecd33244d5da52bda753a3abf2409e4912372417dfdde675cecbac8e58cf6e2689298bbcede669926af5906b96182abee24f04	1622653206000000	1623258006000000	1686330006000000	1780938006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10f92bd2863ad87bea9adfd1b3dbe6fbcaecb7b7ff8e54d40635e3b9854f0d146384e6da76651a6f276ecdfbaa6c3834df57412ae7ac3f0f5bd97d5d8e7eca54	\\x00800003c2b83f7273848472b6492be450c6ab884ec0540373de00ce300b7f7051aadd2fa04ef67f4ec08fd6dfb8d5b5bb98c8cf8bd3c644d6d617fcde7f826034465aec022bbc66237f219a685676f841928edc408f24849a04b46640acdad0b2ba56448ca34a748dc1b8d9224af54af9a29073ed1db3a0f129cc2a6023072bb2be5e91010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd3b6a3bcd5e0bf7c139c77023d07e80e3e4a5bc7c84538a16aeba143ef580c0b7d0603c3e0ad694c6da786e621f70279d06e7cf24493350a3f4bc2e2f032480f	1614190206000000	1614795006000000	1677867006000000	1772475006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18b54b77bd90fbcf6fe131044aadfd68b72de1445e12d0e55dd18e77f2c6e481aac313da763652438374a68ac23c35faa7d0062f7da9630ec907fe5855c0d890	\\x00800003e2a8f16e7f103b0fed24feb6c42d3c68ec4cd939148fafb4211babc4c5644d8685354d2aca8e14fea7a2c2d8a38eaba2062aa030b3f88f0a23fff005f0e028464b451fef01815a771a7ef7c9757d2c1cedae388ae820c1460312714e22fee59b9094168504caa15715c59b8f883a67fdfd5e5aad72b6c14c2026b32d45b36259010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8cdc38429cc17eca1e10d95bb878d4fe568eb2be11803987fc2e87e4b6fdcee37d0df6b79753bb06218d02f7581ca6dc18e01a0b21a15e096c3a3de252716c0d	1614190206000000	1614795006000000	1677867006000000	1772475006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x19bdc710bd2ebc060977b6dcb58e3b32ac80e83e2c2c678dc326a04b99ca71340af0b64a4e4841dce1e2b5600c2cdc696eaf67f2cbf0ddc575999c239672e004	\\x00800003cf1a21c7204a440ece9921e09f97589111da167490f8929c16608eea92b23629aa8e743daed25f9d991e576d5452ad58ae696f84eff2a666e24adc239f281444674f85c03ce09045254e25f036e2adbaad8c919530638c3b5663837c6a1f38ce4d9409897c6d235e99dd7c9178598d5818db42ff7b979edea32cea7236afcf9b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x77c0fbd55a8dc1fb282f66ff6bcc1ba2381baf7eb2c4fc9cc30416e38dc68e0551642b2d752a4d11801b3ce79042b76bc357e29e4d2e67a90b84a462bfaa4c0e	1619026206000000	1619631006000000	1682703006000000	1777311006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1cf1a52f313513c490d9de865fdd86275f11fa8035baf469de0e3e2a77508d173dcbe0ab77af4b629d8f8c2eeaea622a3b915bb033510ad1b34b1495bfc274fd	\\x00800003d7cf814ae15300c03f79f1a22b4da5b3622fbb700a2e4f59a5c686ac6734708e97083f7b6f40536795cc0549a3379768eedd3f5ca59b43264ef88b05177a4787e781ae7abbe4b18f5597a1c02680d3666bd582161b849d19473104793ab95f8831f6f5d283ddaeec5b021a7e84cac992335aa9abecbecb97db4ed6345dde01ed010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9e98bc8dd438c64863b132f3d94320a07845de14d93a76d9c4d9c562ea373f212fd3bde8e9bfdf809b7e3d71eaa3862900dc051398c0fd751215c3a3651b890c	1628093706000000	1628698506000000	1691770506000000	1786378506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e3d77cf2dcb6f31591cc0ddde3d89d93c70599d5b4d572500b067f931e8104ff20db85f7a2d6ba671f49100e76589ebc8a3634bf930cf09f8585371e781f23d	\\x00800003c658c957280306bdcd84db0242d1e032c7d266b62f6a70b471f86652efabdf6e24e802f54ec9eacfc96c28e7ac0ec07302a6c0e430bae73d4d99552c483ed0dc783ad66cb89a532a83dfa419983157a142e317e8112f62c92ef3771229012db2e84f2871830ee4351415684ba25e98a66201105a6bf878e454393048d4a98385010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0f18e7ebd00e797947bf0b8fd6368eb7f0b64f59bd953a322b27df25080d2e8e0ce505bfd39141a832e42c6e5c89a99d3290c28425ff86295d00aa0fe0bafe0c	1611772206000000	1612377006000000	1675449006000000	1770057006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1efda76cff3160b04208731d4c51d28106c482738443dea3ef933bd7d068ee6a691085f6216a11d40390668f0a2bd7a297f6eace9da7eca997254cd63c0585a9	\\x00800003b9a939d10407c211b2ce6805b3d47503b25a511fc007e17d4ecc132c92dcf89a7a8bd4c5ac614aba5172066e507594c5a9a795445a9379c07b888afb9067bbbaa8d5f878ca442656a35da175f054ea29dc60c77ad37cd6080d444ad20246cf546e0a2ed65f73540b69ba7dc60924a76683f3c2aa32fe271b8d6d60b8f72e5ff9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x909fee3456bebde11d48b743a1cb5422cd9667ec61ab69668ad90b85f63a609446e1c23395fb4850ff554ea9d5419bb02a45cc85a45a598968ad085d9fd8b308	1609354206000000	1609959006000000	1673031006000000	1767639006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1edd16bcef0f42e9c92b28d7d287b65d725d00dea9b8c4e6c8f8e8a2bf2dae0c6acdcd30e1f264264598c6d9f719761f21a463d40da6f7e7c6717919a594c21b	\\x00800003ac63b841f2bd44c83ad4b5971082970c199e11d110afef2120a682039176efb70907c3e04c9891f050d60ced31464bf6bc8a1a67c8077972c2a2df40ad50ead0403a78331d1764287804f4a638302d7a97a32ac611be202457d8dbc3f62249ff4554cf357f0f34a1cf586a655c341fbe39b2473f1df67d3b9cdbdfbcaf54fa5b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xff5f826b38d4dc9b3330401f0aef64ddcc9667336ef57ed2d5fb42fbffe2a43f0f8e606a666b41e91eece17a7ee9f5d7949ab8da6b792c9c99841f2dece75f0c	1626884706000000	1627489506000000	1690561506000000	1785169506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1f0100f4a6cec1c6f591525f94338b68f64ff6df5708ca3e3b9a5c52a4ac3f31a7ba3ed2db0a319277f99e0903e414e844e106e96ee0541b3068c411d3fa5f19	\\x00800003e0aa6028ccd8a241fdec013727720660b43fb4b8c699fc625c3e32b02c042996cdededb4c3b2676f471dfd32264a22449bfc6a78c2436aeb82466a472c0dfa948e4c1e1e815c04149db9f48c23aeed6fb7937de6d19002c36e1c7cf9c1775ff631c300031c97f84b42e1a4b7a4ee10cb7371c188af5902e671d5241b45b38193010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x06561fc589492843b4d74f568bd5b13a1d0081cd62b6ae5b6e84bbb3ff9a88b3603be8ad24082b699817c9d00782e33f9f4ce4c1e592c379c14645f9aa23c107	1635952206000000	1636557006000000	1699629006000000	1794237006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2131d0daf5192e326936e0eaa82e8e4d5f47f68cf3537cd7d533d5b6b33b62517dfe201bbe8adf3d2566d540f23f4006fce1f7c2a30fd80e19a90aeadcb05f22	\\x00800003a302fc5afa305596b8721f3af8b850342a67914810150105a9ecfb912f3dea1cada2b501888dbf95545c699de764e1341dee704c40e16d585be1a56ab8e04e6ed1ff58fe739a4798094a833521a9b7ec3e7cde9fc6052d00b5f09705ee0bec5c1234b6cb19b409bc1e3d9d91d8a4f25ef056cbe1e06295ca77a3671df1b74913010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc25602dc2d508c31b3a65d4a32700ccf762bd94b1df832ef566448eda434a9722a72c9ff37ff15e8cc28f4bb0cd2e9aecda2f1704ec720f68b5527a2f3f98105	1639579206000000	1640184006000000	1703256006000000	1797864006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x21ddb0e8d7199505d0818eeae7b611799c40f84129be21786cce167aa7478fe127ea5fcf65bbc6154f468f9718ca04e9fd8d5816ac1f314a7de8637be6a4a020	\\x00800003b5a3ef303151ac2a8890804374082de07bb80a5bfe828dcf98dc66abe3b2cd4d107d402ef45331ad4a095654ad35ae1ffa890ca1345ad499ab80fa8e712f8ff0bd14c35f36c672df1e42c8662e9bf1b3d67b0db4a2b538f9ce5fd0a5b3b038e8686ef2a44724fb170455281f5926d7be2b882eb350c4553025926acfb9d35667010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x661d613fae8b3b10a5542fe85d0c49b602abc3fb306629a7b97ef0cef9eac36a6e0412d2ad898fc42fb2a3c0e08cc9707d754d1a86e563e2c9554c1a9203cc05	1618421706000000	1619026506000000	1682098506000000	1776706506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2341c5d0e4b272888211f52ee1e96606b2c72b705c644911c570f765afbb5210d22ab7830fc342f496c05fa90196f59210353012771f22b20f71c1c750236e03	\\x00800003cb50bb3a7f64dd92065a1e43d876b3e9b824464f47092b56ec86fd1af653157671678a6c0ba980d61f4eb0f2bdcf7bcd93725f487b9f19db8b3d871166ec3777f322b1c3903793e3bf434397e978bab40f81329fc9921e93fb31457033d17f6bbd5aef8a30b9fbd9595a1f72e3a5eac311e532021d236f0337f4c119b6908f75010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x24be8e4eae44e022b60a2bd2d37440d15281e4bf02b9232ae82b9f1b13ebb7598339b78da5826291d03ff313243b55b4fbd8498fe5644f267f0f99aa0a013404	1637161206000000	1637766006000000	1700838006000000	1795446006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x25aded66bde17c9ed105a980deadfb888613623edaa81214cf3a98b0475aa1e646a8d7c269347f16858643eeb14ab2d5250642359a07459dd670c35318545a25	\\x00800003b149dbe08b4ede5c448a3cc10a714270e55a11a09c27997231901b49594c05d8381ec1c87c5f9c606b85a7557bdff34bbbb7ce93e6147f52c36b4d45de96b849567a9d354feb0505472f9c03510663c3b272ad6561c5272c3bfec1151c71d9164cab387f3d3646f1fe060b682d11ddab41643d75e6a94fe1ddf24a67b584aa35010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1e76c43f8ce7666c394de5ae641c2b8c50fa767ffa4dad1a104893e37dece4e96e5ba21b360f8a74b601a19507e4ded370256d03420d2ef068f30fb9ead76a0c	1614190206000000	1614795006000000	1677867006000000	1772475006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2841a3281b638a7cd0dd1a25be7a35086d7cf49658afd7b95281de1f4ea2d649cfc16bc7e9e84ad449e1b8499c571d8381f03ab867b7365160dc21ceeda0da5f	\\x0080000393faead4795e8549e39cbaf13aeb01257ff77de076f4c77cffb2cf1b93c96fe79e0f8ea4f05aa723acb2ac33a9ef6e841254e68d6162c3329a42a213140fa62cf00af9ac825c0185f6901dfb901814d3d56d649b549579b438a9dc1d453ddbed7d3531db11c35d04fc0e2df6d3214b045d3664981e56d32b2a4b6b428aaefd75010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x80a067af64b315c5056fceccd42b25be596a7b6ffe2fa98eb223bf7b2b12b15669fa974e6aaf9937394927cffbf830b79f5faa141536e8cd72ba40d4374dba0c	1635347706000000	1635952506000000	1699024506000000	1793632506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2bc947bcea4b140bef6c5450cd8c6b4526f022c7d13268639a0376297725a5997edafb1ce4e474c0febc95d87061c673a70641af6d09e9cd123de7c1e420c9be	\\x00800003affeceaaa65b23e37c868fa5d75c96680be95ae0ed86966f9958c49bb3df2311d60b16f14d009b48690427841775d57215c7c87258ac7a0cc8db6c27b338118f37852a28846d75ecce1f329f8e09c31e7531f8051387f98595f5f15a85077bf1d82eead6e62ee378da4e3455623992fc7092e00d553e766a72a60c8a46b2a991010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x763f5ef36e7df401690e5fa553c33ab8af0b980725c9be6a88dd86fff84ba281f9f9005925c2f3fd7d9b305d34a8f99fa1e004b68c26c2795f016fa2e679d701	1624466706000000	1625071506000000	1688143506000000	1782751506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2e097fc1a75f467549f2706b4a55e5e0a6e9489c63275202fd8871a44500dc43efb16fd0d22f4db0ca6289be29fc5f86f253f5fd34d36f4465842753d6d6f4e6	\\x00800003cec5f3735a688e4ccd569f7ae05cb17c0ea05fb1b5bb5df887d191dc1194204c26ee15d01174277cac7d05dc5ab6a590c8091686ce933759b95f40905f5deaddc1a7eb4b561696374ef3eb8ab4df9c7a078715d0ba05d6f29ba520c3ce8c585e72f442886dc18ad67c51b69375cfa5c2954bd86965b5b5d3eb83e3a011471903010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1d0af6b5de24db5dafdbc36b93cde5c6e25c678d4bb4dd04c3e044dcc73bb37379c5b3448d73cd6509767c940ce76e752fc7dc152e81cdadc1805d8ec1574300	1635952206000000	1636557006000000	1699629006000000	1794237006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34759c44fbbf432745f9d960e74eef3de924d79c1f28ae20d1ae5b832b94c26cea2e23d24927e1f89f8f7eafee15422a0056a4e062f7e3bcbce04851ba0a07f5	\\x00800003e3a16f256ae9b6f8171685d44ad70f7c387fdf8c9c440983b9fc2ebcec289c19fbdac0f38f6441a739e33ec142623dd513d07f07310b69821116a81279120a25aad337efb8576f005c2c8fbb7db216341258fc7ad11c49b685da8cb6ea28faf4ca78f6e7442caab89f7ff7234764ef52e09e949ea264dde385760a05552c068d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa404cbd3a04ebaad07d9e1fa54364db63559d1c823ee659b5cbeeb24c529bbb3e8a67015104d3b8160ff39e5b18d1b8c9a0e80f39ee8198680d7a76141737e01	1625071206000000	1625676006000000	1688748006000000	1783356006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x38b566ba636a542b31d4ba009980c757909115ed2b116b7538ea83600d60d84ecef21c9218211bf050879636214bacd616d04d1595ed550fd809f944982b931a	\\x00800003a8b8490059732154d72fe853295cb68270e5d3b9fe288beb9bd72e8263a3813d84efb73b2eb7bb37c47e76a9a7d7bd5fff749c7e41ea0b35d6e3fc33ba755cfa1a420929c38dcd942b7fc78972c4a3a2ea16cc3bb65af156d924f3ec2e2ba210f7f9ec7e775da749e7389be6ceaf4754d92d306872132be8e93efadf05c3b2a7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5693683568324bc7a854d40d9c207c675ba96177dcdaf446d67909ada7dea0fdfd50e59e2aaf56ae3da3226a521247b2586a8dff0eb6e747dfbbcf8d3ea92603	1616003706000000	1616608506000000	1679680506000000	1774288506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3969cc6c6483dc54b0f59c69819882f89142248ce82041ac49b1dc052c52c6101caf8ba0b93a097b11be473ea550e049660f1af926ca96335427138cacb105b3	\\x00800003aafa14bab903b1774b9fffca1bc3f68461cefa200b5e2d6e19f0889c9dd4c01a58215d644d50407c32067f971629c245f15b4edbf46c8e256039a5e90413edc25d65b56bf2514a864d87dd4746c2398322bfe0474ac61111bfc0bcd04fc3c4c187d05156548c09c7b607400a2f6abb31e20cdbeb75548da0a9733b7229ed3237010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x07162339ca2a399f6be6a38e70a4d0035b61170a64569b4bbfbca67f31e467d38e19ccf3d4835d2f98609921cb476a09789e8adfc4a72baa64878b060852c307	1623862206000000	1624467006000000	1687539006000000	1782147006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x397137e3d7e1f3c45440282fde0208d251ce9bd21bb05c33285a7785fa99b8bce230ca302c8daf230f38afec584b2067fe18dfd0ebd3ac8532e3d6819407fc5d	\\x00800003dba48c8d0b485a9aa7cd11b895df8e858e1573a07738f00d5b128432fd18fe315b8cda9e4f8398499b8eb85ce411cbe939d50ef9fff366c6aa042c97ad9a4418f6edb8d222952d04a6f4a641d95bcad3a2d1b41889476af8c622b2c97d660b2615d00c4f17fa869bc2c572ccbfe96484eec9e7a294c0a6260263c9dc88aca279010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf29ed3e847f7e83d0e7b52c72ad084291ced02cb98067439b77e142f222dab57814aaf29c183d1b816d6bc6454366d0c65b2679b51d0b0812ed9c80b37e94d06	1638370206000000	1638975006000000	1702047006000000	1796655006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3b21714c3924e3971bce9f8842fa7337b8abdf22ccff62a85f96ac454b931a22c68e83752d619df8f86c429ec5ddd043c5dd79a244aeccd1df1bfe1aa2a501f9	\\x00800003b78ad399537cde7e2248284af19202c8eb85a20c7d4c73a4c007640bb1e4056b244f58c25a3306bec0086cf51ce2ccb0b0138972ba028dc09dbf3d655f2d005ad6eb3a9a140aeb1470543bc2037419be39ef80fe52ed68a6be0791bcd146a77d81714a196780f49f2df6e692c31ad9a37cc1c53ff790a2a5a276ddaf1ae4b07f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf52d5a9c941884ec83c025c4cb431d2239c428d19df5e2d0c2680eb456fc2689b518d1a4389dd9f30edbc9d2708a8de2e001ca6781e7b4968ebbb05e2c92df00	1634138706000000	1634743506000000	1697815506000000	1792423506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3b798667be140767025e0f5b6ee106322c6cb441538f27af60f94c00f0a8a5e0d4a90fb129353175c62dc36c268f35a342f0b5729f7433c91468eb76802b549e	\\x00800003bd5783bf3d8e47580a34ce63e66a015c334427704cf4d4a6bb6d070db5658df083bec2448f8f2cc70078ca6d0897f0eb033601fbc88b6f6dd562b2d0dcaa93824abb4d93cf953d9396750bb35aa6dfe7cfcf3bf0192fd8cb9b5982be71fff67edaeb454162a215d66b4b39ade59c9d7f4a86e24736e5e7bafaebe4126339ced7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1514ea4105554b6a7ae1552a6ae1d25642526de4b01b3a6314d713883c57c172ddd275fbf6d572cec80e96482a94e1237364f7ce6c729d73c3c22987c0900503	1622048706000000	1622653506000000	1685725506000000	1780333506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3ce90ed32a18dbf8b01cab75aa272ea3f9a6efc582594f51ecf34ab0c9d0524f78a7cd43e543b8fe02c89533cbb2a26bbe68793e9101c3e5c4420ed21dbfbacc	\\x00800003c5cbd23e3dcd8bff3d20c958e776ceacd3efdaceb4b593720f2da194d30ae3d218d5dd31a4ce69d3f939de3ebf8d9eda5416cd813fafd191b98a8ff392698419c199783df03fb7f92d2169345c39c7e3d10919e45776d3ebac92c9ba4a0c5126a1164060e4e4a3e6e18694240370afc8a8eda772c81255ad1a6e28fb94c3a8e5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x79634f78f80778fef038d79c9b9f1ba2e97c1f9f3ad5921f34534bc7e3ce7096564a39b96dc664c35b4e4334c7e6ff2138afb75fee855b15050b916f04df7006	1628093706000000	1628698506000000	1691770506000000	1786378506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4309bcb98a73bf520aad6924403a1174ae6ed1947602a38c7bbac3b6c76c5b355605c557c983a154fb4640b72449655446b5a2cd7ec6c49bf2dfc747ba1040de	\\x00800003ae51c3e129c62f3a3ebd55bbc31be222f18f78a5b0852d33f9cc41ace1dfd8807e161ef3d134d328840a138cc9770697a640e446afc261a726e45219a22148005326480fe9d4a5f39fbf11069ec5f0b562fd6dd8eb6d43227680989ac348ce44a2343c41cfad7fa7962fbc16d86ab43cf598288637ef12b78649606e01636c7f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5d1bf6d3c9f3d9c8a5219d92b7efd60661a20b48faf61cf0f175df0a979815fe4933a04967ca415f1473a8d0c9ab1d7d97b462fc016e89bd1644dd92cd76fe0e	1634138706000000	1634743506000000	1697815506000000	1792423506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4359461a803207ad4a13cac19fe9059ef0e80711343a6d8e1120eeddf6409d1270538054644b6693b7c5a8c55d738773f1fbc866f546c77e3cc1afa84e07054d	\\x00800003b841a3936dad468bda46d9675698c36e92cac7cff59e7a5b4b87e16b165683d384f6c0eac10a3e5c6a72d4c926748c001145eea6549e85089c69f3e5f9a351acd8d816fe844990d3767d2ce1c5755f133d0c724ba470d883a6323a7388b3a444e88bbcbc47cfd1447539221f28ddf59759c85bb116050b0799d2c71aa0b18241010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb150059e7e5b336ffb631abee3e81eaf84c0007e4bb2f747f3296089a255ed1b5302dd488061f9f30e62cd2138340f7210841e80d856584444ede0ecf6d67403	1634138706000000	1634743506000000	1697815506000000	1792423506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44a5cfd54a590b22bec7a15ebb72025235f7a600a5b0e1bc9b512547511a0f65b5dd39233f0ec1bf93deee08af7e6f7ca5fed8612ab1355333333839609c3a6d	\\x00800003c72f485b777e7ee1ad6a0134f39bbcddd192c451c1e784ea65f0ba6e9237dc65e11b93d44d2547a64ddf415290e17b243c535950b8cd602320dfb8d42fa6794f49669ca50c80663990ad00db7c8b009672e536f2dc4a7e388c01211f54b2eb121092ed710a31cc1ba1bbfa7415d1651ff4b3970115ceeaf5a946f1117ba306e9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x93c2a8e30c62643ff86a9f75d4ff2ad07314caffe972ecfafcc844d01d9a3077da251caf1e6097221467a760af24a7e43cdfe00bb2096028d8ac2a1c1f467f00	1622653206000000	1623258006000000	1686330006000000	1780938006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x452d2b2110ed0390019794d8de4fd5930966205f20eca077820f2cb501776cd4d9c266565a078dd478600264f75337c92b0bdcd4934fbe6cd690c4ecfcceb146	\\x00800003dde38deb13b7a178c9b600c1939e869884669ef4b3b9168b2372259bdc552b3141eadcb38814bc69721a3154250f11ecfb7d73c87946cbee7c14b3b7b4183e8fa8e75cca173dee5fafb5e9ef9f0b05ffa070f09d4959028c6f508f0cde25f27053ddb2241c6decc380f26ef010a3058f7ebc372d98607ab8ff21298ddbcdc261010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xce916f4a219cfcf0174d362587ee8187add9a6c0cd5071e7776b68fd3114deec8bc617e66c7bba2f976f4e073b9e31c8ebd0d94e52e3ca18bf4a6f64a7bbc00e	1629302706000000	1629907506000000	1692979506000000	1787587506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x46b9163bdf531fe3196391ba0203d8692509cf6f824da09687a4600b84a05d5947c309fb566e70312d887b202bd3ad6fbc4901ce2d3a46899455f69454a8a7bd	\\x00800003c83b462cfdab20011993cfe79256090c4f3b576bdd6d6098637b996be357af4b2eff572f509766569307a34acf183d3e346a58a33e47c34a92f7f47e9a2cb80b328a85027b7cfa4257ee6da719e50c7b7774a8daeefb0f10913e02bc46c2c4f34f395cf2ab7e7bb4a45d1c346c73a9dcf5569485d605b96ccf0234c47c01801d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9802714d99e2969a2569547c34a0a220f8d9d3414c21a147cbb7bce833f88d78d86e5b43422027bd36c321a18ea8fb9dfbfcf1493e4ced0509d9f33374b9fd09	1631116206000000	1631721006000000	1694793006000000	1789401006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4a416cc9f79908e97012cfcbe1dc0c424c1b3168806fcab87710bfc0150b635b69b70b98bc017eaa14609d6d2d0a199b604fc12a665bd7ba33e77e674b9ae636	\\x00800003e75aec8a356e9eddf995db2b3135057188bcce5ca38acdfb6ba9f4d5d6d765e4853c513ecbb88b30742e828f2240cbc98c09ae80123d0c53a306356332e8a6cf9511063d7d312b117b4d2897dd2916a6ec7473ee815a6ec005ce07d434f5b3dc2d007fea5b27d8e356a18e904a351ef48b578576a8831fedbd8844df11566e4b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x305e67f04d9404df3e1d9dff041e7c42041111542910fb41d01fb38ac13a39ae9cf6f2359c0a4b3f19cab7bf56349847c0aff1eb91db98509c0ba928ec55c20a	1617212706000000	1617817506000000	1680889506000000	1775497506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4aed0f3b0797da71f475344eeaf0e64d98cb18947de6babde3ec8b38d3eb16e20bcfe13b273ce1ac757b1860e1d6fd97a2cfeb3732e3619bbbddd678689c55a9	\\x00800003b122f1af8cb1bf4feb46c76f74edd02f0f09e0eed163eecbf3059214ea8102b8fad8da3a6dedf0cc90c1a767dd99f004553e63f64674991ba65488de675bc728b7cf8e35c9bc00d95b81ec73d91416bfc973c896d0ee9d2bb777de99bd66305a8d7524754d583decd4a66c83059212951893df66851539f2181d6d06fa06a4eb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x787195415104ed37b7f641d366ae0a0423631014c89fe485f61e1ca18a217c70130ad4f429d2f07933547cca69cd4101fbc5ebf02ecf8f6490401ed8a1004606	1628093706000000	1628698506000000	1691770506000000	1786378506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4ed5aae9f862162d9bac545266b06323208a8573aec533d274d062c490977f2d6546380d47da7a26892f8f46ebaa62fb801b7f9b1d3a98570d475eed5f15d843	\\x00800003c888dec2ce5409972da2f784044b15cdfaa700ae1a8df668f8e574b43b309179a8eeb5bd9f3008986a7f98bc1917fc82ed75ddfbaf92009fb6e45aeafeee408284a1fdc0685ac56348f293152d42c684955886c2ab9d26e2f593781e074b2f057200a6aaf1a9a721af955af0b6cbe74c3dd8b8ef49d6a779d258a65e069a3eb9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x00e97231b45eaa53c4b03e347af294a8be7fe6ef7a0fd091c39139eda97d5ba50d50daaa8abe6cba2fc539ab78edb9dc03fd3eb225a88927cd3043fef941500c	1631720706000000	1632325506000000	1695397506000000	1790005506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x51b5cc42d531c8aabeae9ba46051b77fe89f2b60629221d6a1bef2433c06c46acbf612affbece3b827963601c2140e83e959c6051da2af4540ef9f9ee4a94f9e	\\x00800003b71b80d8ccf33b0bf69dcf796317e4290e21fcf68feee2614e09e2b890fc661aa09fe77ac57af085bb9285c207ce88a2889cc3fdbda542bcdd6a94dc8c6497aefa4b4b3cab8c52fbc816e4746f2646cd243864c9f7c1930afa4fd4174f1e476395d9264e8d2cb07c92aaad17a19a1534ce10edefda9ff1072627ae8d329c5f21010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfe8110e7bfedb7a414799f3354895cfdb0705966a8896392ceef0dcf33f34f988c54864cfa1820a1a21a1a543abfec94f3afb841d365e3ab1db81653933b3d06	1619026206000000	1619631006000000	1682703006000000	1777311006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x51a56581c381fb55b7c8458693f8d5f935f4fa52fb39910756467d831116b615921053ad9347448288c8ca2d51b4bd422357cc28ffd3fa913bcaddf5f7c38b34	\\x00800003e05ec95a1f61a01f14f9ace4bdb182a340b6f7629b969c455f187b8852889b49974317609e28534567a4b91c3c3e3fedf2096b3dcf25c3364f5c67495f3ce07d5b417397ea41bf8566ee44cd54ff515d69776718d5362e03496851ed2225e1222a5d8ef1b8082400aa6ab9c8c64c0503c22613952ccd330916b906f0b2a01bd7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x81349576256535cc784b2cccf631f2d4fd8e3198445d0589ad6f955e8c83e9e3144e95b4160302895504611fe5f5f27d6c6f047121d9341a243be31b86625501	1617817206000000	1618422006000000	1681494006000000	1776102006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x52b584c0e4bf019ddddca0c1fc4ff45ed850002aed111cca45927fdc95fb2554fb7c89d02fddab1c17048f91663edea80ae73bf9ea9ffc1a289405e0bc19e98b	\\x00800003b4b5e6edc5c24dc4d1b709e45f8ee7e5c32ace8c860754b827104b25b43976745ab2e67d25dc22d00d382c065493c2360cdffced970a9cbe460dc4d097f12e04ea9e364bfcb808df43f2b3fd84ae56f61192faaf401b324bbb9347f37484e36a144867ca15ff2377f798787e72625aa58d891d4bc2729aa5be61c9adebafca39010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x839ba6ef20e6422f3afbce6ec20d9672de7f379230d9e79ed5b5df50561d2e4e412860e0a797769c6268d894d5afea63b2548e3215384ee87aac13391f9d2407	1632929706000000	1633534506000000	1696606506000000	1791214506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5215b96c796d6f1f0f4c1763f8a9150be87162e7be28afab39749a93b957ece7e16e223dcdfba4fb2c9da0ffbfa917c790d8382dff20d0cbd6e01a793581e181	\\x00800003c5820085b9a55d3eb09b2bb98dfcca2792b2bc22f792120d501b9824127e0db40ed502a951130e8e0bfc9796e8e480e662e5b70322088deb0979bdbd7257b0d483287f76365ba450b2702c9aaba13f42ca93dd9f7b95da60fa095a49c665a18ad7203d1d61ea208b869336804e27f33fe607d92a8af52649f24c58758007eaf3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa73d7f82a03b763c44bf72d478ad00c23bd06434c5aae90d9699d499cceb88c762206970f2642b4cad28230e1a76954c3edf7808b2c2967048c774c621b77b0e	1639579206000000	1640184006000000	1703256006000000	1797864006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54d9981a1fcbc5018e5757ddab35829201873953b63125337307177735f0240611683cd2ae151fb53cb6ccefa720eab5c7c91834fb3657a6b86a5683b96acb12	\\x00800003c0aa76f68cd5e66acabe2c88ad9cc829660b2b84c785cd3dc1efc9025a1a7fd3edf496e29c37456b83acdae907efe4d0cce9ed62f598bb76bcabcd19e2777ae4add32c457519cc74dc96068e86ba43fb95489b8747ecf230964b9f7e7127aab328f501aa2108b950179f7605e5db1b96c7652066a680d95264b82c1af6d76d7f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x935306638617a1403e7e46afbcc52cc4c2851dedfb1bcacdb51f83213c233df9a0d9bbd08d0e42cec03272ff5a022f18018fc9181fa7c1f3d635f41f6f29a005	1633534206000000	1634139006000000	1697211006000000	1791819006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5755f62abb9052f398c6e20dc40319ac9b8126a533a6c30f3fab23a78be40e37de8d19e5128e470de64e4614541661643c180d773b6ebebfa3a13d55709f32bd	\\x00800003cdca0028f828af6454b82ee977746e0526ebb137df6ac0ea794eba234ff8f3f9dae36f8f1ad6a349a3903899b874b20acd9f0674122c57702ed374f440e77ef9be2317048e2c6ece33a731175f9dfa78128ffa2333f535a12110eedbb65f87e1b5126a5b4a14c3f41f05e42ba2f81eb5af4b73fb8250e810233155e8db93ac17010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8d04a4a37128bb8728525e1ac660474e0a347788e7704df2fb187f4cb054a9493a33dd222bf2a1af728d3998a47a5227f7bac8eb8fa70f73f39a5412dc614205	1628093706000000	1628698506000000	1691770506000000	1786378506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x584924f5cc231e7306e8e593b59ffc7ba6452b9c96333809968c1b187a390085c81e0d2cbbc6036cec46cb749e1910d8a46c5e1b742c8a3eee720c2e663b49d9	\\x00800003c72376f5ccd4702cbeedd191269269ea46e7a1f35fa11e8eca2ee9f880ab970de4b22d9172133ee4a40cf23a9842f1155cd03d939bd5bed3f3610ed7e3de707124500967f327ca3fe09f6ceccb52db9dc1277dbf0191558b1d1dad71d44d4f825b925803770041d26e82b70f78df0137fa1985dc2a6b2b2bc5552381c430e76b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8ba60e3743b3a9cd20a7131e8543e64a60365c4b407f204230dbc599a5c0e48361112e8fa1c9c23f933f48c61c62e20d4a810a782c957a109d1560ca517e1509	1614190206000000	1614795006000000	1677867006000000	1772475006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5979905811b0d09c1ac60c9f37c0c83f17953cfba2e7bd8f33880f2e830d6f334c5f18cf1a16715c721ce1415bba885ee52fb3fdbe46780dc47b612f1f4c4fa4	\\x00800003bc7bf2b9f563d811214ed8530288ef4dea5185095ab76bda5a6287ca6c0a2411560e97e6387a2fe72889b405501530dbbf71b0cc5685d870fa5bed565f8dc95a85080fcade9dfc296847657861a414fbc4b081d1c5a9e6bc856a07638373d5d92e1a900d31207feab41a63aedb3d47f4e44c5655c85e600a96bc43c431204167010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xde4467e92e8a0cd6c401df0deab5148a331876e295620a5c341dda36431d3eb271dfbe709ebaa38aa53b1fd6d1854874412f41bc29f1492e2f604775b0a79309	1632325206000000	1632930006000000	1696002006000000	1790610006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ca9fba200a7ebf0a2852d3fc1ee9f169cf6aa92d5ae852f6ba69b220ff48589a28354c1ac539be89cdb32accfa4a60cb53c304014f2137c446ed4e42115f370	\\x00800003d6d45ec3ee9c1789749328f1217ab912b9cdfd69287cc9f245d4d8d609b8f198b22c862c6388b17c1de1b2f43fc0e79d3385800e20ca3a27f62d7425aba09fa5152386b1d374754608b93c42bb9d8557fc04140a834ad48532b6f149c9a1d66b911f9473283a87f133079ec448b7cf444cdd48fd105bfc29c543cb1765e69ab5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xec43561c3822780625ec02815813967a6f83409e451271e1c8f752e99eeac90184ff142d0aa26361ed84d75f2cdbfe34caadaa8925fb8537d754d3616f5e3803	1613585706000000	1614190506000000	1677262506000000	1771870506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ef5621aef2f853ea0ef3b692fea4230a3dd11f1f887370aa061ccc31c874071240e72e522d2a2164bc327bfd575bac5e1cdbeb08768be85c5997e06c384b53d	\\x00800003934f8ae3d04583bfb9054a64e23d8cd26095591f098f477d35a314184aaa00264a22c962ea41652f4d5bf83939a61cd8ca14e60bd38bd96723b383250ffab9cdcb5538743c7ffc1a9e86028993b565c292ad82393b92fb597bf8c1017961af098d43af0ce1343fca4a4db6fde81e0baccc620bc1c025ad83453090a4f970c4fb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc324097609f98c4521eb1bbf38c4c7b40838a528868c188bc85c7350ab4994c32acbc538c935b096fe9b46c2802ab127c0f425f399ad553de4c381576e69220d	1636556706000000	1637161506000000	1700233506000000	1794841506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x61b10e880e1edcc39d298e33b81cd8407961a24ce4504a679edaab146206e2f5e18ccef4d230726053ca4f43b9c04c22e743a6252cb5091516857e658d34ae35	\\x00800003cada8339b59fe91cd20d4e042ca4109b5aa1fadfe8cdcd7d1d1387a88340a9b20551157c9fdb9eebf744fd79e0cf6b57c3165ddd5c6ba14db3aa6648c904ef5775a7e27530566cb2325c63446d7797ffec3e6b483644ac4d8c5873246f0969e621221ec78e789e8cb01bbe5b77ba4c3f7fb0dcff988b996189826c1a5c640f23010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x70654f20847fca7ac1f0375c30dd37af8fd10a724b79108a5d60eab022296b266ad1aac77635b2f3eacb3f16c8f25043eb6c05e3f8d83bf72782db81fb372007	1614794706000000	1615399506000000	1678471506000000	1773079506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x622586f35244cbc96d921587e7a42ded7f7f0aadab3057aa7d0ba02905a91e2f29a291cda24cee45601cf3e5fdbbdd20a144fe6408051ba9abdb6db7373169c9	\\x00800003cd89faa008927b88b4bca2989aa8813987fa56d7cc375a6af1eb8adac91e74528c0aa794438824210dd82935f44268ded390aa475d19e76e263936763fc860c146e32fc5144733a3b0c961a1c9cee221c54be72089d5253faf2dde8086bc2e0b39142fdf79aa75f4194b51f9bf58da3e6f086363d1416aeefe8a93ddb9da7871010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x074b2ae0a79bfbf0418d9f53ddeaefb7e3b3f8dc9d2579347dfb8a2e62b173a693346c9cee6773c0d6db9cb6d8d996a0383f59aabbb7ee01444abe5395bf2008	1626884706000000	1627489506000000	1690561506000000	1785169506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x63e5a9e110359ff2cf951e4703e93e78da007080c02605a892163536150fd15623394c2cd17c63311968cc6bc7ae4c41fe258be44c1324b0f01333a7cb8d885e	\\x00800003bf939ca4085326ba0ba7affb7063725ed20aaa7d349ce9df3c56b2129b7ef6b75c28f0d017d6f69e90d55e5911c1b5e4b7dc2065d2413c4c74c518233280ba174b07423d4a2dd2bdcc065762acfab6ae426aca4fa8da39bee68b941d928747158797efdcd01302c1fadc7c674c21f10903b9a20107ed4a11fa91980fe94360cb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd23edeaa8890ef3ff676aa42cc6434495bbc9d812a0ac5e7db8fabae969818f4ad411ad4369e386d74812ae72cf6b71660fc357a051ca24cfa6c46ceaadfac02	1628698206000000	1629303006000000	1692375006000000	1786983006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6461641d4bdecb9a34a4bdd96b6f87ca34e155b81b5f94fc7be7d43a7b410980dc6391aa73ac877f8944b95634512e10a9a391696f669fb0de3981e9b6566f0a	\\x00800003d325bf3bc4b6270793d797dc5fda29286805121116e18c58f04602152a9b8662bcc24f9d920173928b6e91c403270c85e2dc6546f2562ac7c4ba7376281b4fb5d8320aff1a4e6d2cd0a1cdd67e1a8f46aa9e9bce16b176f8ec494032861381520d31094c231b571bfbce8040e4e76364bf3ea733c1a9e4d186684875d5562d0f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x95ac06a485e03bd75929d396acf236fb743c2b9396533c7b54b421126708f0777afe41f4394a23f692495ee159342f22d7ffec0fe82ce5a47d6df621926d1901	1633534206000000	1634139006000000	1697211006000000	1791819006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x649d979497111a594664efc779197cc4def38882f0be5e75a50155cd57a03328d4d81f1dbed97e74bf255007ca518a1408c10be3838e516cc5bb4c7da0e9ce44	\\x00800003d5325455b114fbb800606a77602877f28cb572b2c1ef30ca06e69d80c36ecae9d10c1f9b0823dd6f5856df34e7e5c8dde765a0b4defe65bb6cda1c9d1a2312afc760d5bce225218f0665b25edabe7cd97ae2e3017d1076097674458aa4a938c5059f5c6ee1db8c464c219cb9830d8f18687a16d730c96c49b9443f6adcf11013010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x609633fbfbb64df3c1160e45cc333dad6d7be577bb66ab0dec90af081ca565900465d8620c9cd95d47acdb206179fd151c21743c3318ad816da0c11e14c70508	1612981206000000	1613586006000000	1676658006000000	1771266006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x642dfdabd8060080413697d1cf986d3605a096095a7c379603d2b972591b291a3c0a5f767cececa0501ae79e48c9a302bb7d88ad19c5174e0565201e532d612f	\\x00800003c3794b3879428d4ec954894be7f2618573c42e9c05083fd97384ca36b25435fb2f85f8b0c77f7d9f88651def9440541ced3559122f80933a8c17244cab60dcc3da1e8133f71433822972fdc1c4a70a691b10c79770c7fa71d01104163cdb43b034810deeaa356e61be7840713e9836301da5da3e8401051f657ae080bef20775010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x934b1534521c50cb1919b5801395bcdd9b77b6c3cc4551be0b5a37d50a1fd2aa8c7e883b12bb62a25ba3bdef3e4b5e68f052649669049224b7a4a607ea926003	1610563206000000	1611168006000000	1674240006000000	1768848006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x663dbe90176a805b9a657ced1a7bb5155f65bbb9ee016526da2519f2f53325ba39ab8ff8214f79afd7196e0ab6e3c8bfb8ca44bc2aea13de1a348f86a4cb0525	\\x008000039e54360cae68809caee79b313bda0b7989c3c86dd56818a9d527e33c8d657d46062b7c66044fb9b983b9cba45974018b8894f02cc63ca8f4b7680310413c4a9d69feee418162fa37ae522c3ee1352905bbd155d7e14b4ccd09e64d6c50408f2092cefabc3edcc00539edd61756c61cacf953e4c9096f8871c0c89e25f7b681f9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x72e9402938b11b538f788b5b35ac4884437987fb29444e0bb8947847a0dcb4fd4c0a94875cfcc9df03232d4abdfde5aa9d7226b5bc45136358f540b39b504407	1611167706000000	1611772506000000	1674844506000000	1769452506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6801e30a245c5e9ed4fd846716c3ae6fe4f8c1cda355000fc097c0c940f0475c2e14c8b423e542d82dad6f25f9118f281c2c3fe44fc00c0897fa7a52728e5837	\\x00800003c19621fc57d733b2dfb57177717582ac1c102cc9088ac902198cfd7ee00b1b4d7a79d66ecf0297518149f087d598f0b4b25b5ade6f801a66fbe73ab2ea50df47d48e4dfa6d576bb6e03ffcd7ea6c9894b94c0ce9a60181ccf1d3c1ff015217cbe7b0ba9e4c5efe55a7798adebbabdbb464528ab3ef6d18f06d2d7ea24c61d1d9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x38e3db0536c2ab1ee39156579b8bc6f07ef1ba5b81439a5d4b559a5b291285e64b7e9a991b4e4df22510902e26ef18fc25175f7d8fc2a93bd8800468da17780a	1634743206000000	1635348006000000	1698420006000000	1793028006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69e5640671f8f46d8ac3b4a2f483c0745fd8aaef67a15fdbc0a63488d9709d445710ea28bea59df43fafb31d74220e990a7338ae9356d21717b20fe1b1b4acac	\\x00800003ac19480e43c9b0ca46a621aa3c4c925dd4b0fadff7a4714cf4c43f0ce9012e182e0947702af39288d5e3c3cd7e962684350df11523b1a238aca7c173535674739ab3f6b913c0d9f194ee6b8d9be3a432c2772fae451a9c75cf8829dd91d0e7cf424d9d976197a824fb9dbb465c9ec6aadaa65aee0671d1f2bd2296ec9a0fb6c3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd40aafac66a558ca0f02ae05240616ebf0c07843a5820969c345fa356ef6faf3a18c20b3ce66098ec84c51f8a149bf444f4225b3f91ef12290f678cffa273300	1631720706000000	1632325506000000	1695397506000000	1790005506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x69190ce20f76d7d30cf37c95e4eb1af4bbae95fe00ba706e5a1944d614d59dab78efdbfa1bdb218c0e0d6d8c0c15d2103dffdc5e968710841f71599e633c8d94	\\x00800003e0a91f268526e226d1a19a50f3c76192377bcd9fbee72961f5aeb5a235878e47f3f148fe23a0c8f227adea9f5dea2a473e55d5e972383f1008e7e2b222de59d250ba53cc1043896d161fb1a3263eb59f2c75a05a50825475909272e60abcd537ef9c341b456ae0d9928f2f25a8617e27b30a099da28b5f79b19f387e973c8b2d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb9fff46ee4e19b65687e37b836db0a4c50a527a1473901c97f067ee46f7b7aef887c918180a4f000a0776838f5bd8a92a5d0e2b9c07ea49331e322a0174f0608	1625675706000000	1626280506000000	1689352506000000	1783960506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d811a46d8972e2d0938ac0d91d8f8891987580855f487d55077d5b24f4e50a2d955e27e436ee7245e0d12a75dfe2f431d0b129b0b60c047b021c39867822727	\\x00800003d026c3547a2a55a85f5ac877c3fb88ab729d788ead7b330fa818618e31f328d22a3dee152edc11f18596ab3d83fa25ba3d94825b0c389928f1cc9f198c5133b8cdb4bb1ee5c9821e81870f51140d4426d60d3189deaec488e11f6f9168c42411ba238adac4519daa9cd71264273520131832cfe5f4c078077f6c7e2387c7f2cd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9aa6b36fff0d83302c7877e5f5b16063e9ffdc98a2b6c76ec67a05d4f3dd4ba419a8778e3236e8e42c56b50f0da124df2580c5d65f4f9023734904497849b403	1628698206000000	1629303006000000	1692375006000000	1786983006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x70d5e9e95453583365fb2cf5b1da8b722d0dc91ae5e64553f4f65fd525eb95b1c5c46d901888c3d8e43ec3e8ca22d3f98e2b54ebbae9b6df56891b4a12258659	\\x00800003c6dc515b25c3f9f685cb23dbc4f0681c05d6a02ba6bf013043a9a2be019bea25a6667dbb13a22969082750b34f257c2cacee5f357d169cdc4424b59bae72c7d74ed55c8fcbfda8f4d7036069c72b9f48abe9d6da154e5d106043e017e607814fac052d6c5013af0a81d52cde817e2066a61aa54cc2e01818874de8341d54701b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x420d520e2f12758518b2eebc8160e0f88626041b07a797c97ca3c1c626341fd6f1e7d8c3ba8b0e35c13bf89ba1ce2859017f0996b6c4df1d7c34ab17ce88f70b	1635347706000000	1635952506000000	1699024506000000	1793632506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x72fd8bc8368b2d24936057b1270515fee407d129e43e067741fcf3de1f4a955c2cea9f0d39123a99f2ecca66a41ed691cae145c0bc981e5a4385319a7f63f80e	\\x00800003d134da6f0bc5721e58af06181bdfc7519a17c508a7d008030ecd3f64f541ae37fd2e2b2dcf21449b4178117f7b764f15d1897ced6be9d61dc089c7f11d06a027aef2f1c49dce6b531c30906ee14d1b57a6ab0cbb6f462aa0e388c6161075320ef712b0b37182e23e69eb37ffa6444df31e165ff4ead6f48467d01ce47aeda275010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x48715ff729af94fecfa6dcc45c55595166cd19c3e024414b179cceeed995cc6bc9deabbcfa3a586d6524e0bc1575adf885eb785f1bb172dd5aa8493d21c8eb06	1621444206000000	1622049006000000	1685121006000000	1779729006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x73b58b85882329f0907f90a00ea3e667814102e389e0c8b9103a73c1a1902072d47075283771be14a25c77dfb5ce8fa92f29d7978a065b2fd0908e4406613b8b	\\x00800003d287e750522a090aa35990bb44eb22b557cbb2d8c568f17489a0e21f7070796fa145b943dbcced39a1fc1ed1bc17c1f0b59a9da3950acde9f6700142bf7436f1925ad2a6c80e2d2686a2c16fab99a241511c584b42d34f9194b67919c8ed93a686d83f007a716d0959cef00e139c26cd028b9f27a17c7a6a62af270ddfeaa213010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc4c88d1616bf6a74c3f21e5cf430adea36fdc8254ea399a448f788d08bfc43cbc9abbd1617208f481967fea7f57f4ca809e1764468fcba582606d143a9344c04	1609958706000000	1610563506000000	1673635506000000	1768243506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bf961d7d03d76676354c3d7da60034982ceb9112519aa460141466bfcf6ac4481638082a1b19b50fc6cbe09f9fceb60a966518978550d367f49a87b7a6c19a4	\\x00800003b4163a935757aaeee8123f0e5f7e032d4d468d02e4d2890ed1c317c6cdfee9451d5f31314fdb941b83c4ce41943a75663ad04998bd9973c2112ecd0081ed340cf1e6c8ac78a869679b457c173e6e863daa33b81c500d134d7a8b99189fe3a69807ad0a68bf450bd4838e0ba8d12e5f9d4fb1aae610b164cf170449fd85dfaeb9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5e419a1f73dc09310d7484546ad1a2bd568b81fc564213f960b0ee096fdd2a6940e53a601f1c2fb30ba6d9d9ff4a150166a4f7844b96d148ab9fac28fb04830a	1637765706000000	1638370506000000	1701442506000000	1796050506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7d31be46d3eb0ce85a0913daf261da7340fe00ee17a0e86501aae1e99709da4f4b9a62f117170bcc5b3d3fdc052cd696ae581c8ca5b79fbb475ede20505668c1	\\x00800003adca5ba045af38179fbb1deb93f73e3e475b1ab18497ba5c03a9b2220d984bf5226997b7f37707270fd22c91e02f87593830f7c582cfef2400f969675d08125d0171de7058a78944555418e47974f7598c9da67430f34e8036f90382d926cb5ae6a9cc63bce0befac5979cfd9d7de13afce70bfb7cd44ada6c5e0cd2aa16e103010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xbbf8cbed24268c9f87636dbaa6e1f8a0f3b34be932dd2014ea386fb8069a5bca4a95c33dd4cef5dd66a8affd5f5e2f0fd5d797f862813b5bcd09d03cefbc8d00	1637765706000000	1638370506000000	1701442506000000	1796050506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7fc93780ab61ec8b1fb06923418f8326e8f4d3ca4291524dcad3c252c57bfa6e048b4a02e6d41d0ba969113877a182232252f5698feb520d9d8d7777f28b5095	\\x00800003b064418449d6717b88d7d850db302d1200376b64187b3b11b5885534d3702c6767418b508687c7448d2fd9619e0eb52074f41d903838ee49393c7605fc2aa883dcd41b80bd84904e798081c757dd19e860acad27561135dad0faeaff3115afff10d5826c98a5097fc486a3c3c62c799adf4eb8ac029b3efe157d3214bf5efc97010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1a1824b6e53de0ae20ed77d181ecf7d002eabf2652ab7dd0ada5a0f6f1fe9031edcc497530c05661f38ac243c4e010e87402cc17ece97a670c1198b198bd650d	1634743206000000	1635348006000000	1698420006000000	1793028006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x82151be4f7b4499c4de5824d8761ce8c7de92ec2f21f07b6b3287a5bdba2cb21c4e40a7f2ea180d52d8c8141d8343284d63bfd69ff632912831d35cd8d35a5ad	\\x00800003ccf3c7d9f247312c083cb921a4d14160da9e139676d8f37484f3cfe08564424b040e53a09fee79447274081c4bc58e7561e9fed9ffc7a6c4ab5f464965b91dafa450fc8f1444f0b2519e2535f8548e7c1783dbac79340a180e3afdc9f6d2f7689e06a4da8fb9918f3ea08ac57b20fc8bdd3c5a17b83f43c6503dcd78ac0c9325010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4a7bcd6c330f12d78d470d2b1facdd4580c81404a9f6a916835620e4aaaaed6829718d13b0bdc19bd8683f5c03beac85cfd5f5184ec9bfb2eb9e11f260a5c102	1623257706000000	1623862506000000	1686934506000000	1781542506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8399559761793cdd2bc286768408e032e2e17be45a0a5f28e37a3c998ee20f256e1ca01b156b0d280059b62f1840eee2d0678bf3ac238cb7893f3cef2acb154d	\\x00800003decb93d202db0424b16cfb333c61870a481efd6c3589b7a475d8159f02a16965af1aa9798401dde2883734a3ccfbec717291de75986ea02be78b75657a25ffb7099545b51f744d8f1f0264edd9a208da972bf8b17d494f506b6b2bd4c53fccf8e846b084d6f4941400a035555876126595b3525154683667573a6e4ee9b8cd17010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe2918cec3cb37f369393c42909e43fd463b950f8d54ac2f5d710faf5ba0c7fa72a850f551b3237eeb5a0b3564abae935cba0d8d8d87f83ec1f5279d8f422920d	1613585706000000	1614190506000000	1677262506000000	1771870506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x84e1a34935d639be799391b3d6a145f329157f0ced693c81a71f4b478dd3f6a15e786d08305003abbe5fdbd1026f54c9f9cc9541ad96c4fe9324ed22ee7a2ec4	\\x008000039c8ce53e2b7990e471878b1e5c73dcbd3a2727feded0dbfc31e248a7a7b09ed20e024a5bbead79d4ae0e6b2a92d3ab2d9b4e6a22cb8e65e99a6ef30eae0dac9c74c6288fca021c2793b093bbf2b16feb4c7fc894638f90e6a68ea1c5f7aaf84f96999457884e4aa3573cfb11c76a37223c651fd425c20ae4c380b2ae8a7fe80b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9335a33e8513159d8043e2c2821dfce4dce082d761fded608970e9425f7f28091ac37ff526049af1f6acdfb778a20ee3a7a69eec37df2591f834c25d639c9b09	1608749706000000	1609354506000000	1672426506000000	1767034506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x850544800dc57496bf72ba5bd5cba9b29558a72817dd6ef051ee9d589c2f259d86f3879b96c6b9f9faa503f3f8c08a3a633251316fd345bf14d2cda2042d414f	\\x00800003c9c195c23f4962734f6e722090e385cafb87bb34a56dfa56dbfd2501673bcacdcb4c7721c458257a03f01f7823a9161fd8684f38be73c9ae02a2d1f0783ca8401b24b2cf012e8985119bd97a07accfecf2133491eb6b3f44480f9325ea5ec1c335370309f8c4f202fb4207337901241913ecc8fbf69751ac68492ec427d07b73010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4ecab61a6cae2341db94de413c9d679948fc6810adc5da80075d1ad8cca43dce5b8f29c5b057fd47e241d2119cae49ffffcb1de8e5540da25727510cb1e60702	1627489206000000	1628094006000000	1691166006000000	1785774006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x86b1ae126f99bf64dd6905b3d4d0f6a2cc1a69fe794b72aa82fc31b45614211f71c0aaf521936ee45840280201df6c72383142e8fb539faf202446df888d546c	\\x00800003b2ca6a5ba8d1735741070571d21aaf27b44e53bdb886a0b7dc06c9f5aed4d8d90501d01e88e39405ccf3f9251bd8e86929601372a4790451c5fa6c5cd34562df569b4add65c0c76bd285101ce7d99f780de0bbd41d857ae2dd88a36a3b5622cc7cac1537c0d8e6632dffa72672947a28e98f7394a078c256313b419203ac51fb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4b1b09bfefc367703ef46dc1758dcfac45192f5f89edb007e0182515695bf63625921c3dfa66e1fc850eb8ea3886af26a4bf87c9eb55b7d39f89963090785401	1622048706000000	1622653506000000	1685725506000000	1780333506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8715fbaf647ff5a872d8ef324e26b4239da317d7568e969c5189729f61e1f06f8db253f6bdca1534c27a7fbbbbe15ed2f635632162b14bfd13b349e06510b4a5	\\x00800003c4e7bb9b5e0aa65dc040ed43815450c09de5f11f9b0535cfba4ad5bf461c5eaa56f5249342d0e1a80d1209db19162c2407bb0446a35460b3f9594cb28c62fab04afd2532e3be9b14315f4d54523fae315da78f914e168a2af35afd6ef47cca90669a96020b093e44349c726bc24c7e01b4b049f06570c614645d193d049b8701010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb4a8f403e606b134f6fc4083a2f9bdd79434593990353ea9ceeeba10dc09461238a527443d1901b964a063bf087546db95995d910c51a6a7dffc8d5f6e60150a	1614794706000000	1615399506000000	1678471506000000	1773079506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a11c7f90a44d3d5b05b185f1a6d4b34abe1bee88509bf838385c2e5cfd0c0c72af08d347d0cf0e7845529d74ca09138d07e92528ebaf37700e5eff3b25605d3	\\x00800003c09b06989506487bc1d0699dcf8a439182a27ce12d89d38d1a80155fe5e8f947f000f524605d48af5d4b5118aeeb8f163f85d3f2504d42bc611d7f80831cc599d26a976cc47d41b1435f0aad4d826a0e3acf12b122d945b55e310abe9a240b8550f244146dc790aba3df6854836883b91275684531c50f8dfe6f9e73593ef4e3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x84cb45f0ee9c9618e1b6c85df292ef4328e3a77811fa6467b1c2f27e0d610f5a5850b7ea47517c2afe4603a9285051302cf93ef2c475e5436f63736fa2c1060d	1608145206000000	1608750006000000	1671822006000000	1766430006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b4dd2f9dd00840ab3f366793192f2b7f6623b03c94f5baae1320839c3918b65b498d246a0b7a60127f0fdfda8d61dc4b95c4373d6be400af1a00b28da226258	\\x00800003bd0f3642aa15a511161e4bae75e8c45ed8721c0bf409c22929f1d6e9c83cd2acb05f0d511e042432fd810e0385398f8c8d9f451d0946f14690e7932cbefc12aba5c50683e2d1940172bbc3d8d7e849b5bc57a64af8c6dcd8c6db26ff9c7f8e83c735935a927a724a08722eb666e1a7be60ba6e33532aa094c95a1a3715d614bf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8cf348a2998a5f4d42dfdc857adf9ae1a0393b5f57a20a776ada57f26ebcf70ea53446fef38526ee84d80fad44a4a2d73a3226ee2e703e8ed0220a547b67420c	1622653206000000	1623258006000000	1686330006000000	1780938006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8cf1171eb6daba26b1c6cc785a1e2b3d96a458704cc6164384ef4bab345714a0c074f61550f3a417c3e4fbc771db9eee3c3bf232569dae7779c374e26f5bdfe4	\\x00800003bae86e5ccefc7b2fa9896122a8c6b05d555ff646581ac01a3e6e23145d485b1e1ca313aba319b2ab0a9e3bc4dc0ac786ceb6ecd4c9f66e033f11f59b88eb4db29a7e3091a228469e6f270ddbe0a28d8f5767d6aaba7fe7bb53b676033f74f286214a1ee7cd1b973f8f1634be86227a58fa4d0b28a1dffd3fa42670efaf8be91b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x625d3cc6017e43211ff8211ae991c9243aefe187dc06741603e097f75d81b33dfe162f2a957a4792de3f52375938689c93fa73ac9bbe4eaab7bdea2c18d04c07	1615399206000000	1616004006000000	1679076006000000	1773684006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8db9e9a50ffd86eaaf92e3c450f029a00248aad80a9f433b32247909f21c20c355808e07c907fbd007e8213ce8eaf3c5d33919d4d2ee0cad6c5c4cef8111eaf9	\\x00800003c79eec6a8a4be781836c5008b8715e9327dbf05a9ffe0d170a01fbb0dd94e73ae9cee9ea6f418a6747c03bb455442088a1eedc6ec7d915443f6b9fadaf436ed6da471b277781026ac4b4e6be9233a30ad1b048526d3ea70ec904c0afbaf0ec41fff19f208d1d8223fb63c2951438d5c5595e3e7e54cd532b59634cb3c3b0e6d5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3390fb5d1f1b8b2964717124d0c6b9225f6787281604db8a1ad72da44ccc63c8a6130dcab7b1be621e47e55cb81abaf2f78c2c5f0d90c61d5480ddce3633e607	1623862206000000	1624467006000000	1687539006000000	1782147006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8de9a532d46a7719404f4db48b9d68d28ecd0462b80f814d4dcb3da32c1838fd7ce06bdc1e6c1fbaf9af79c3f421bb8721d398e41d450634ab66cbbef19fb82d	\\x00800003abefa5d0907acfaec6f6da9a422ef738bf6cb51e47419682e6d1847bb3710c599d79ee3dff7cf95e3e18956b57d4bff86806314e4618387119dae0272a4098a03ecca62756f2e758b9978a79c57abec1d577f37db4f89bf700945646ca05cd7415f00f250113faa7c9159b6353c1f167bb3e758cb5c2264c53f7da5b3219e2cf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x88f9fcf2daeba3f92f102d52f9f463f01af6eabc428a5d4c77c134cb9a4bb3df14a8420bdb5f5a0dfa1bdb135ab74ec52d950041f1788a2e68aef8c0267fd804	1629907206000000	1630512006000000	1693584006000000	1788192006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x91e97d695d794b0c0cbc8a1687862100d3b33951319381015f52185c513f6a1173ae365328e06ddf61110edc3f33df6ce956d74599b754378c78622a745176f4	\\x00800003c0210d234974b02ee03f3229c77763a7be4ce15c4d88a5d6e127966b8225205a9f47f90bbf749b922e5043b7eb9942a510c7c81e1cf6529238fe537ed60abaa3ba33b88429ce7a5067e70f14509ed2ae405f38f34c9e3396cc119a5884738581587317c50c8cefa578406592dea8a910510a6394231acf6d37f342f467c4257f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xca8ad4b1ccf75062d9ace41361baf7c89e70bd76229253b9346f3cd9ec6cf1fc3ddf8f9ad5c5574eb5f1adb023ea61614e19e6fde35695d4b6b1cab0116cd502	1637161206000000	1637766006000000	1700838006000000	1795446006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x91b5ff90ac5e4a9a62cd8f9bf042b8b5566216e7fb133ef26969a66d0b68a0f4077e606b7fa81f4b76afd46989028c0ceb0f34e5c7e28be5dc8ab4832c7c07dc	\\x00800003b8cbfa3d2ce0e6653a9298eb9b4bf1211bbccc48e3cbee8dce74bc8c799c10a2a948266f8e5a2f44666a3185a2573c7d2d35925aac598a2f4bfd928c8d29339865eb92d4f88d48171f5dc4bf573431b41337278c5f54f49e4bfe459d872adc5135030a60f399dd26aa05c7408f39696cf0011e9c8683d57fa07928067a4c4035010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x95c69169623eed75eb1cb52a87c3181ef7a0320ab18b7a15dd5fb38fbe321bb51ae76b895e6108543f46b293da833cb9d1f124e3f9819baa9d06c68cbbdfc807	1609958706000000	1610563506000000	1673635506000000	1768243506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x93413884ef2b04124b4374da02d76027a3e5addd9f674e0b8d6fdf7198d30a673cbbe5ce17f49edd920f4477ac98693244a3170318fcb2adc5a077c4c30bfc29	\\x00800003c736e96501365abe003a1b7ba06a64108fc53dea1fbf19d8f0342b51971d3d1950a4c3943dc4e1995c6c9a57ac67e85913a9d85f25dc7971334549403e16f96a9e2030b70d66a305c56909108c023996f5e5399bb70f4ea2367966ce66cb066a2f7dc4667b29a6d7a39e5e5c09d79622ba880adb960b06c9c003fed5d0b0ad6b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2bb9ccca2d148118775545dc215e77d07b9d55082b19b780c51d7eba485a6e3eec83de48f92dc0cc30c83f5faf286f4e2faa880625ba528307088a4ce160c007	1609354206000000	1609959006000000	1673031006000000	1767639006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x952d607dd601238b173c265290d2564cb130e96c249bac191afd214a92fd1d9ee8184a11260c5e26dbada3a5b10fdb0e1c92c3006992e8368987acfe04863fdc	\\x00800003b95703dfd9fb45e7690e200d61267fdd2fcf713a70ffc2fb1ea6e8dcd3e542d0115ef339d70c46cbbbdd438953c77b3321111ae9dfd927cfff21d89ed4787fdfee4ad5f915a08de4b2cc8618fbcd6b02d85ae99ef31359d107b99c36c7dc2a68766523620c7b021e30e7c50f956c77fd5d7616a6c1c43d3f94763644abac9921010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x141de76a937b3b56bcae9e8ded8c33832649a9f4ce7b0593f9aaf84d9d60a88bac46927a521318a22e8be74c35a37aa27a12db0fdb675b093a7909f0b6e20e09	1632325206000000	1632930006000000	1696002006000000	1790610006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x967196b28eb973257bf6e2864200e8548c383d286515d0dad0dcb5842ce24039865d8478ef384a5731d7719a5daed901989ac978893da5c78b8965bc957af4db	\\x00800003a5650f72810dde0a14efd941ebbc8784c1957105d12ebb9c39144a3319f30f27de03737ed39b2c61c0b9c9599fa3a0c70661301ec887928d24fb8bcf6113b484746db037af96c2f46d51bd0cf98ff519966cd17394634af23ff063e6994879346cdfdcfa288aae0e26ef7ba40baebe418c3e8387fc079609fc23d33845c9571d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x400c52460019d52fed0fe00531d58dee120a385f9823551a6f1f633d851f0a7261b3edf6bad330d0500e2d8c1121e3a5a76dac975245ab18af0159253fe28208	1636556706000000	1637161506000000	1700233506000000	1794841506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x98f15432e9cbdd0a646ab7b9f4a03b3c81b9ca58e41c6f4fea2ef2e70eb15f07f20004fd7f452025a194e5748d4ca158e3798ced4f2b2cb6e886d331d43a29c1	\\x00800003c3c02b7795c142b86e30c96860a13296558a07c22789f1cef1c79732c68c2c38dda260a04f94d6ea56202da5c0d9c4781dce5ac135b53186551211d8b2b63de57b2b9d4349173564b8d3664820999d11a1586547a00a4580f2838a32c563132a195a94ac84fe152428a100bb4d9df81f1d1f1248a4f1cf4c7684ad17a31314f1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb95813011d1411e63b47595fd3749cacd4633b5cba60b910612b61616a790336ad9b05b482331c9dcc071f87967f744d2b76068717303f39077328bca7ead60e	1617817206000000	1618422006000000	1681494006000000	1776102006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x98e99a2ea7edede0d62e66dad14f4f5a90a9157521c464bae802b536c9d399ae277a3fd289a0dc5ca99359085bc4db639027e98f3a9e83785fcdeecc96b1598d	\\x00800003c1e0a6db938644545d2a4ba6d901d7e5d6cbf27e5f617831150298668248cf5fd893a00e924b4ab75aaef8b28cfd98d9b1e90534f1cd430a4a99a1f9b80e8143fc29b4b2f01d209546b57ed5e19c2b7b3c0bdbd9f66fb8dfcb9eb24e59a6b942f19d34dab8c421922bb1f3c76fbc97e7468df398db93566644d986b441116faf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9e06983998acb0303574b8a9f658d74587d919848c84e11d544fc1fa0d98f701c5f90179657100ec9e666915b7a9a3d5c4cfda4fe18c94b23831cec6fa37b105	1625675706000000	1626280506000000	1689352506000000	1783960506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9921a22fdca1e46c7a107956f1e2ef4aacc6dec340204c9d0fe087c3978975e0b6f2c9e0d37a493a444ecf69de7a48750833249619a7236092e77ce74d75d74f	\\x00800003ccc049793bf0d14df55983a3db2bfba80cc8eaadf2256f076e98b01aa295a24ac31e8a64e689e7a593ba92b0c26400ce466dc2107f79cf8a6ffc2e41d8016a53f13050fb8c66a0e3ffd40be7b217ac6b9aae587e6072f65296408a2fb7f20241522797bb70da92c200ad7198d06876e8a6614ecf7eadfa7f5a8fc6e8402038e7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x496e4500c7c6075306a0f0632f1f6ac4ab7d56b31c86c4da35c6795137e9a1edca9f273a7137222153654efac8427abba1a8b6fe8c806d690ac7dbb8ce8ca30a	1609354206000000	1609959006000000	1673031006000000	1767639006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cf969edc4439e93240f1232571a2e0776288f5ccba4a4a71c56e70f6217e1c681dac06b10df9e557a74a28085e68786510fff0e5d17ac33479e54366993a3a5	\\x00800003b4346e6ae896cb6c78bc9e25a8c4e7d14a00703b225a9d05149c83dab5ad727f579da7ca328aa081bc04ad7dc8d67a1971754fe85e199602ca974126994f0cc29a36bc6146a25fab8a0c576e7091bd256406185ea079d0fe6266681f99bf72eb39e0a611d1275f225e549652932ec84f84019824ac3264b51bd80024ef5180eb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0120954dfb529e80c9609fc4e615d5d59c3e18439ccd58358e670c78cfa03fd3853d89aa9ad1e42a08ada55984243812d37b39a71b5d12a5ec6b504ad9180a08	1623257706000000	1623862506000000	1686934506000000	1781542506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ddd79c30ea03d3f4731fe1bf959e2e8d52482b55242ef47c666a40da468eec2313dc8be20798edfb02592c54d7c4a7a1f60e7bc8e7cb731d91cf5a94c349061	\\x00800003b9efa7b7735efec914fa2407e2cea4ecd54608d2e99b80ec0588be5c7f2553ee3b616b04d325516d608a28b831af4b1d6890b76777959be5c4c9ce58b5a819be6ed356bb5d3adb5ba64f9f147a8ea6be601944d739e2006bb3939cc62f104153d7cfe3f54160b0e1079f239b7b51d76f7caf59fbcfc49d35df6c0d35ae5a759b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x68ff83bd37aac1ae5a3698157d24414a038d4c86304f592d472a313d84943b9d54b771b33ba2e0b5def4e4da326ebeaa4cb1213ae0e44b79b82b0de6654bf905	1615399206000000	1616004006000000	1679076006000000	1773684006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa9bd7979e114076a347b076bc4b918e1a166c256fd00795cbcd7fa6d0648a822c5394dcfd83bc194ab2f221f657987cb7e571e062eaf37e6cc238453d5e1a794	\\x00800003dd4aed97884394c138b96177732e1cf9b01ac331a588457883e1beca259e20fb7021beacc7ec202fdc79052b9f8b849e70636fd0bd61daaf09c25bfd4b0a31afcb5c1d93092d72726a0eded3d3dd1d491da1b8e25c1c0e64c9ba7bb1229f3f9187914ffb2329fe2374c792f2979f17cadca7e4ee2d2cd298ba8ee88b4625fe67010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5f0bf3cfd310b9be7370bed7193bf3e323441386301e3c01bd48fea239e1df341269fc87e603f8992f7f1e314d06f8b045bee05063e6d045dcc09a88981a3704	1609958706000000	1610563506000000	1673635506000000	1768243506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaac1458740b71eb2eacc6e9c21e4b6f1270f5a1aba15374ad995c2186cfa4dcd0eb29019659b50381b4cbdfeb2bdb82d4c232ec13368b7f6bc20fcb9c91363eb	\\x00800003a8107356518b4dbf1b848ddc01205a2cefeedf6c3bdb0124280136eac62c0c54ff13a52378f3c294ae983801210bc345d27d9e8280152b599c4302af496df4c099fcbf1d29a78e0ec129d2cf4a2b872126a415e6be2cf2624188fe7a7cd91ce4ead5e7f36d0dc8a37365cc3e44009a10a0768b88680ee4b90ac06ee4533b9a27010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfb86418cde8ca9995497a2be8fa3408034c38db96b8a421670de1e9f4ee6a9bc0d545ab34d466ab9c1b01878ddbc6e49a5eb8ebce8be60b17e548e3c1dcd2f0a	1638370206000000	1638975006000000	1702047006000000	1796655006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaca1792663ea2f9014e2574017963c935eae370c851276d03927fe9161648b95277fd85c17e977a45a7717e6ae0356c0bc7e13110c566c074fbd9f81fa75f360	\\x00800003c67abecafb419d68a976672f23c0e33796ef76cad32bbdc11f2f7d0c521ae520c30c3b718c4429b1f6b93d7e3d61fc1a20990e80ba2109c50cbd9ffa1ab13c0f84c55eb5389b71fbb4ac5e308ce31044058631b9cb16f768e9b3a4c889365e80ccff9f9c057d60d52112ec088aab61eaa8004aa669c0b73d93fd4f768249f6c1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb892a228cb6f0050485933576754bbe3d87abb37157cafe204453f9d6194818643d9ad46d3318f4453ad63c15de113d6e089a19e5a922a1f6ce317f0a4037f03	1611167706000000	1611772506000000	1674844506000000	1769452506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb499e870b735619fbf4aff04605d3c44da3dc4389bbb84c04be025b87821e27440a37578599b0c363a2b22bfedb6261da26aa1d750fb56eb42fd81f9227c4f6f	\\x00800003c963ad49ec85df5d1f9a25403ca92f4cdad917ad857a81f3c9c0c45fc98b8b085de6fab12427ecb89c545fc8b1eb57e4187ebf040be61982ce1bc3ceaf210fec6a9976c461ebd95bee06630772b1bae816f34a4d4bf54b05683fac47707de2b421424cdf6c380121d2e9a9342cf7b979bf19efad7a1d8a7cbc0dec9ce5af918f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfb24047dd414ce7f45dc22de7e75d841e42baa91ddaf05afd4cd17ea19c16fc70a633c01117e2afa91838330385302ecbee56854051c7fb6e8b9fd185fc25101	1625071206000000	1625676006000000	1688748006000000	1783356006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb659598d67d7ddc4731247dffda167b25e7e08e442707f08e3ec81a9873e6fc367e6941f6bb749cceee9885cba8f65242378470dbfc3ed0e2a65f614dc0761cf	\\x008000039da9cf4c4519b97b2d2c1d7e3e865722c8d19f28bb403b2ae9f91acb3d0f9f9105470a679ff65acf3fcedf8f7e75642985fdb10b103bca0d513d535a242518401335062425ba698a2d0214efee51e1ede689f88b17b165ffd3349232cfc00faa3e927df3c4a4d363f83957b011d30b924016abf9b699917a94cf8eed1ad932ed010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x01e223a4d0e4e5b0d86d649e69248af954e31d9b02e6830207bf8bc3fdf2b91723427dd8ad98fcb4e71de020f2275ef93e4c599192224b953d578f6f5b9b0103	1619630706000000	1620235506000000	1683307506000000	1777915506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8117bf4d1a41d4d1991c2357d370cd1843034a2c5d99cec957ab16dcecd051d59d8fe904588aeac4af89307f9acff03e666b5b9de430977c9db5b35f6691d30	\\x00800003ce6a4acbc8a674509c3772fb44ceee8996615f79252f54010a6f92bf5d0f4ac847bfb12466bfb4caf5ccd5ec42e0be9fa78fefb9d1e9b68c84f5092df55da225ce832c7699d64f648d5b7db58fc16ed5f2647c37c3fe95d54b2fdaae30c892fb943d554f64080d87f404c3de5f7d67d41251d5145047e14925c4552aa029837d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xecc0e946939c67f59eb1b66a65da31e6cad4a22be5b26108bfcab59111f4fb3a3a69e0a3e4629a96746dc1b12387079962fe078ab306b3827be38ea0448b3a0d	1632325206000000	1632930006000000	1696002006000000	1790610006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbbc1b7f414fb525c1bc0ee80039d614f7e66dede06cb6b30a460cf1aefe5a9b20eb2783cab11a5c0ab7f7b6e621bc560a826eede795ba7a6d9b701d06b6f2d64	\\x00800003db4033f012ae94ac0cb06a774b1096ff76bc1fc50c73f3201d2ca34f25347c3c773cc1a67858d7d9f46e6f75daf40fac62cd1b6064e1c4865ccb0ad348c60a96c7ab0263d0c974c1c442105bcf6c5b02759c57445bbd6d8c7667d6a63dfed88fdb7b3e1449ab664433e62a0052aaf5af083de0f7b749284b07465126a8d1eb0d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6ee16f67df22f9fe8816b0c80403cfe4e33646efcba2054cf5fce782dd080591801048b611e9835985a2b757ab84e8356ab66a72ee1ee58fa80d20576b066904	1623862206000000	1624467006000000	1687539006000000	1782147006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbed1557543612058bc3c4f81bdbe10bc3d17a373998e45cb28bf03cb841c4288f699060eaf02b66a47de5b1bb8794dcfad3361874c1a95b758b04fdb8afdedcf	\\x00800003ba38403a5716451d7e8c4ff6eea861418858bad93c7614d981779690aa650b4f1a4ab074e0e7508ad967fd24cf8c3a53b049d68b354dbe17a6ae0af2a0b56ff60a838b1095c8aabdcad800d9b320ec1695ea1b0440687ae1a13c697cd63cd4137a09f537b6d9b0a473769a4b01df8d8167a24111cc0c07c51f90eeea5f2281f1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5f67057575739a4c864d505e09b763becb447044ce0682fd0458c8588a4783cbaefa10d1a3ba4db85ca304ee9d73d589b132e5198f8ffb736204924d14c6680b	1633534206000000	1634139006000000	1697211006000000	1791819006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbf814aa5c099c9e85b2fe9299db86f3f4d5014ad51f57f583905cb2c27a3b06bc22357cff7743e717eb5a9933c1f4da33866b67e005857a3d9d13527e360deec	\\x00800003c506c9c233a7c70353271b2b5e85e9fd955afe057e4673d8a9a5245a2267311a37464e64e02b27c828fd7f86821a5c6d0fdf224dbba950f642706fcfb29527fa813876be71096df8588818186abece6a6ee4d30f92a0300397eb8487987a4edf33d30d7b634979d31f31e7d640d308f6ef42d742340afdab9bd82a8e4cc443ff010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x03eb4580359d7c717497abdb7a42022bb3aaeb6291cbfa7625c2ca623f5f84b8877b96a6f46884c28944ec752293b388f3d09d0855a209ff8f170874a0c99a0c	1625675706000000	1626280506000000	1689352506000000	1783960506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc0216cc3b3288b28edf4aed8fc46a96a3889b60f062c523c24917f854e2d76bd9f86cbcb10a2e3490696767b6c58015340721ab5aa7b632164f176a1fa46e16f	\\x00800003c82a41f3d04be5d81d1a18db3ecfa066b9ff5e8486978390e3a1916ec7d4a3960a869c13368e99f3b11ca596fb9b380c175b78223350f3127d3ab36f5f4e3ae534d1496cb63694bffdb8ed0d0a3635fe92e41be16848088acf918e66afe786827b4d4b104f124ecd4b752ab2292e7b18cf3bb9ee01c380a17e36b0c3c51e359f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1d790a1873e9495a9f11673fbeb14c35e89661895b603b50339b5faf36d037786fd11d1206e905411bec2bca3ce9f118efb4678e6eb76b3c2d5e3ffe45d8bc09	1629907206000000	1630512006000000	1693584006000000	1788192006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc8e120518aac304729ad87a926e8f49e26a4bbd8158e9dc90d971de4ae8e26fcf457d5d808407dd873df8e3bb5abefd02216aafbec0c789715fd83b6eb05c329	\\x00800003b1317411e74198c4c42052d04ff157b4540ccd36f784812e6b8ade592ac607c09b84b43d2a3959cf575acd2cebdcd8b159114070a8d28783edd58956f149c0aab2e68b3e6b0b3a1d2e4ff561821bfb6d7ab8e18aa0353c5754a6e2a8c03a6a6fc1dad1f73f0f6c2dc558a88cae3c15586b76b0e5972d6e29f45c61296d7bbfb5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x191f84a346dd4e4863500a7db0f59d887453a7d6db96a996798708472bb9a463f8dbdb5011fb958e0ffa80a7bb406f7db638cc20ea1e47baebcb6d5a52806f07	1620839706000000	1621444506000000	1684516506000000	1779124506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xced1a38f992c2cb9d857a000cacccf6eee05d7c66472dd62a5b544fa59bd38d2e037463cc32da1042ad0bb4089eb2898e9e4db3eb7008b16b7ac762c64d1fbd9	\\x00800003c90b5a855fe0a45401c3bb3ab59182ba2e80590c8c8d0426d6a0e9506c807bb66f26a12418bff31da306a35c7ab7c427fb5b56d0f8cf2fb33f2f02536147074d3d8ee15ca7e81a8867ce2d7d1c297289b7961a78d0a7608440424f58e61b2150646c599e41ce30cdef27d71a7089f6f4d94d20d6040f80d7a79ecf3cf39dfce1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa67c1e067684831ed562c2592b00764a0820da933ddfc6ac02271c2bcebe13bbbd78a698d2c2b7964b9aa1b1ded1158622d234a57b60eb23fe7d853485391e0a	1639579206000000	1640184006000000	1703256006000000	1797864006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xce0d4e4b567a444d3446f7bf6f3d74301849dd349f5f2907ff752fdfa1f320a9e6f4f749b51042c6fc13d01c1af9f2a98ea8bb5984e355b2c9efe461dbeed6d4	\\x00800003b74783a21b58afab27a96c106f5108e4a6926cb6b89325a2c9cf1be6f80a398377ab6adce75c9d09884b3b8d346e1e9ef07447e9c420f97b6c54ada013a0d11ef26837203fd9f217831d9c75f4482ffe64d75ff66290006aca681df697ef53a743c704a74639ad9e5aeb0354d6835f8aa5f473074f48cbb53b39556ff2984bdf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4eec471905c9a83a254af6e494414a00a49beddd337fe08718b24359e6c6b7a83fa9a2b1314a0a0a528884834c86f6149ff4e8a505546edf05931cdcbc5d6603	1635952206000000	1636557006000000	1699629006000000	1794237006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd76964a9419ce53e3ff87085d43fd51f737233d8d394bc7b57bc12ce7ab77c65058b2b84343db1faa548f10d4095524006d6bb157ace7b0d4f49df1dbac660c0	\\x00800003af38f0f501da8183fdcc636480f5726ade9949431c118301199ea77688d7fb50c937ec9cae05b229b838c718979b9115095e3ea3b71dba2b2952ecbcbe1a95b4307b8818bb83bc67e35817d2e4684c856fa10a9cf788220060ce2318a5db6ae0ab83692cf47416e0d1ecbbf4a493ac5dc7b93cae6e648dbe67bc168ad7a9597d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5fb0f94c36db02005f17066eb822224e0f4aa97281c3c53499d786b4fbb3fa3d298669dd859ccef0a65ed7ea0d876218849ffccfbf9d690e2f96d3f0f5cd8203	1620235206000000	1620840006000000	1683912006000000	1778520006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd8fdc3f74dfb4e21d70d75657d58d294fa0b2638ad55f53acaff4d895e45179ed901a8b9dc672ecfe44101e58aeb80adbd47e1d09858a1afe95c3569a62f9506	\\x00800003b906bea343ac90a04f25d3b2a72da596f31e75e9b8a39a17f0f3f3cbb6348d9b20000963ca2ec624e7588317f452f68e00d70cff536cd1cea13244a5fcabc5ee97301b424c683efa5e84cec118ebd51dea727e13e32f48c746678fc6f32ffa29d32f5de751691fdcd48db42d0aa6c717e131065f2ab8c1e2c9f409e9f3c66cc7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x930a4232ecb8335705036d3bd549565b5cb1027770c9fed2391cc6c2dfe1788b372652aa37ee45fa346a43d9e5a3aa76d8a422f87e6512f405111fd43ffe8f08	1638974706000000	1639579506000000	1702651506000000	1797259506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe745938ed4a71f18f90f01ca16ce32d08f0c9f884e15315c1d5c690a8c94dda2cc797992f06e939fef13e652fbce5b9cb87b084fe8b3e90c084f6b91fa928b96	\\x00800003937eb8dfa40481ac91e70a30d391f39f28ca750ba04417fe89b4390e3d71c3a81e0273e160f500a5e9820ec94b1c02f01d2599b7e2d06a52399c782ac3f701a0cebf03b3f03ad5eac118ab59d6f7d5f65bc65d9a9253fd3395244f1e17189f28b8a798e7b716ce97ca2ff1a949a6fe53232da7aaa4dee6274d34757c70aa0255010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x712768af0a8869868be2b2c2174a7cd99753a4b00f6b6342573455e68205debbb6a8e3fee7e13caf64d4dbe4feb3f1899d6f4b35b0f82389c2d611d6bb173907	1621444206000000	1622049006000000	1685121006000000	1779729006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe97d5737b07783f40bce0e609e6e09f763fa02998b55ea501e3ff2afdcb7765916206bd538d5c140c915c88415a3ab321bdc052df258d3a45bae43941e8ee878	\\x00800003a2eed709e0262c1f21e6f7680c7959b4a5d7bbdd64648fb49afd2fa1016db8087c7f755d050409201e75d0dd602af8f37a1a1678a0d445892cda60a00610a030dcabadd664653e78f7437a5806237f84a67d0bcd15a2f418dc37b44f5df0204abe3659226d33b94fa99e405725236e7868b9da40e2e1cef08b1c919f88cecb19010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9c4bb1fb4a77dc2c4e255a49453483f531b5a697c5ada71a21ae1d80cbdd255be25aaa28f975e34a256eb1fed9f013a3e96213006d83a99055194cdf2bbb4d06	1632929706000000	1633534506000000	1696606506000000	1791214506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xebf1194574ffba7331e5dcfb6e6b0313115c3059fdbb9a18977bc27f7456f3941402b922ff0b846f261ce7dba23e798c4f9a4c1889fc9800fa6b65a5f1fbcebf	\\x00800003a527029b17e51d45933b4418016cc1f37f065c74c2a14f1914ba75cc9ef696edbd8bffe07b29af06fc0fd4a1c5db793a38af5c93ae574534c8d759938bf8942ae699a5900ce2b85b12bc77fa5b81569fd6b278952a987749e7c956f86ca519b3916c64db5f31d645ad60ac2d044863d99b39a2e92e976603bd2ab3755f8f7e6f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x30a74a05ae47e92d71091e1e7e9358f40a9fb89db65a101652892f8c81cc470a959aa8cd562e3dff1e021d17e7b7e1fc04361a45ead92caf008c81a2673c5e0e	1632929706000000	1633534506000000	1696606506000000	1791214506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xeb99cc2036495bfda49aa510d55e54c8ccf84f98b41152c88ae84d1057907a4bbc87cc81d9725cb4228d610195206cdf3828f47fa59c18f348d99173f4610054	\\x00800003ba3b818b0430ef94c7a9f651dd8e85925ec9f9ff9942a3e7116e7a2142cbddcfea5758d183ad354917cf1f9fa69fb86434f9921eff24a497b940c799cd4b8265d131a53133d0e58f8cf8c10bf72bdc8b3522758e986a9ee33d3241dcdbfd59464a2904dd12830d2c4da50fffeb216544f0475abcd4b8e8f5a96d13d23ec043d7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb4da2e2df8bcb736375e0e9e5221cb50984c7099c41adee568044e6b3b8a2a8644b657c416da2c636a2ac01dc97618cacf84f02d59810919ede2f5353045010f	1633534206000000	1634139006000000	1697211006000000	1791819006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf29554549d949f83301d976a2a62df386d77bd5c34af69b7def5db8a5626bdcddee9645cdee231e196cf403946fb2b2f2f5eb0d603264b174b55f02560b1bf35	\\x00800003990ef83094064831cd6ff748e2b343a7c5ef4888c007e430f82763f5283929b51f884bb39dfe4a2eeffd610d7b7be274d3939cef76b763a091f4220da3f9a58c2e66487bcb9171dba9c634cf470f4e968aade9cf46e82639db8aeb86dd56ca68d97ef5ef6c13650b93ad10149b824a22c5ce9454e6c27f861fb32dc9dbbed361010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x277622e0888dc46045a0602d2a9263c373b6b62aaf2adee692643c968a5f0dfee1f92ed3447e29b7e6799568a5e9ae9ba0e7c36503e545474e3b92aa87ac020c	1632929706000000	1633534506000000	1696606506000000	1791214506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3c9f0b07aef8a00bfe0f2c348049e5005bd258f8357f7905530019d6004f4ae1ec04d372baef325ad144e778150f80b4d7fd1feb4b37dbabb89ec6d45ff0c43	\\x00800003ad2d4f991b1e906674ad0014002b8988caf91a223e5fd324d1bc23458ed07092654addcf14beeadf0280eb4acbbac5467ae03c42ea8c0abe60460c6bb3088fdd9707a143b9c56005786975eff21c35e00081e78d9759b1bec6c05a3fe2465f271d1370c29d7f0af55794cf98067bf241e22d03194b1c1cfe38bd1ca8dfcda595010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe85fe2df1d46c34911460876a4dea731ba795137749b815073e37056021d67def62e9d2e925ae9341ceb7fbd3830d38d6ef3b258c23e0952b8090badc66e710f	1631720706000000	1632325506000000	1695397506000000	1790005506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf371aa569b6b95f34ab8f3d41b3b368889c39733f381d70d8af00654bd052daee7d58f8a910f4ef3a8a04a8ad2d51e0adbee632262eb39240f3b04f30cf4c620	\\x00800003de3a3b84cc2102b938bf3be1e553a919d0ba5e024a936b939c80cb02df8feac7fc2036d62c00f83b8db10321bf2df3284f5dc7f1408212662d0ff10d4921505a8f06820a1ea87535d3a1a24c6857599db845be14d93f1eddb3055ed0525c7469f843ce7c26b6be725b6ccb0a8c702288ee994468461a1e111de5bbcebb4c019d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf6fa68050ad7b5d3901c8556bb1277993522b2ab5d1c3ca86e832a9df0369343170b7666b7b424fb89d30988ed03ec41de085499a67f3dde021ad0e074bd2b00	1637161206000000	1637766006000000	1700838006000000	1795446006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3b564f3163468d801d4ab623cb6c9817188e349d6da48179ace2e6be423503991a9189cdf2147b3843beb2ddd5b9169b678ef5717cc112314e239c11aac7f42	\\x00800003bb35e9e82e2fe99938ee2ee759e8c6f929a7d984fd02ce59f3c9416af5002741a4452653fe13e9c3317f23d6c120ca8da1afddadfb53fc338abaa04a6e30784fce1ada6cb057e06b603052d311e5b32466516eef8fcfb2701ed16334e105c18f8891461ee4ad5f87b78a442635ab540d1c6ca404c4730b2b70ea343e5e94c6cd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x7c2a54fd24df0c5bccdfba8f2d01fd9fcd26cd3da95862df89d5bbd93ca2d62abf894a3bb2c44edac04798e103bb3b082e2d20c2c2471525a77cdd2b2627550b	1612376706000000	1612981506000000	1676053506000000	1770661506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf53d21ef69b92d4e8b25faa4cc329b8cb1129b468df228cbf3d09223ebfcb00629bb32e46014f7a1e187e37d2d619a33a6705a6ce62ad99cc433addafeaa9ebc	\\x00800003b81f723cfe6e5ec720cfa48418d86625474dea128a7b9b8168ba26e06b543732006d67f6415446f76a9927226fca5ccab45effc091939fa7bcd7f307f1de30bfaafc7ef6266c5d2cc6a829111d6b5385260c86e721cb73a1be10ae3129eb3c7c5b7f5161c1cf5d02fe2d9847a8e20ebe10c2b201fba1c356599709ccdcdeffe5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe75119f44d8f7c2c613c22d27627477a99ad70ff7866e4258522128ffb7729355b901f25ff2a1aae036a3d96e4cb1839461b4d236494892a392bf14c8a3fbe09	1611167706000000	1611772506000000	1674844506000000	1769452506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf68d7d8f4f3aa413fabb182d5a975e16323f04222db04dd07b896bfd17c1596d1bb1cc342d86c173fde763be15069c3897be22ca431823570409b73c38a93b3e	\\x00800003a7677bc13312f7fe762f5f28bab00308cc0033a8c9411f837972072be84b4f4973d1b25943ca162ffe7c2c24947d2a5b65b315b9b5a2cf9180521b6679eac91912f0ca01e339a3325ff680aa8cca2bb18ad4a8d88e17091b83b1cdf379ec7c126280352cfe1df2f5208d386027682d50096c026e0ce0d06e0fc36fcc233ae82b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc6cf1d44f5f0100a6140143c16d8857d7aef8de1ad80c6fb06b642804af4d5f4a8a49a2ddd08a11b78a7a53378ec7f1d8d3f0b7e1be954030287b7ba0f4a8402	1616608206000000	1617213006000000	1680285006000000	1774893006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf749ac331097151c5c665874b929780fed5930cbf76d616afa924630430d928152c837d1099aff4fcc52fc857bbcd57a0a4ca4868a8d434d47a109952779b2a3	\\x00800003dd038fd1fc51c6fa08286fe0116744bf2843d46f33f285975a6fb96e1ab5c2a771aee36c1bd2532f8faba9202447285b11217303df82fc9aa89e98901061bf1a90d003a3aa121195eb37f69aeb662f71b75e2accb8c04991c023a9d56c6b735fe6e7c9eb0634662cc342ba54bba7f769b56dc828b9077d7f75b5b3b31bc262eb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x476459e5af184eddb7aef2cfe75c5b158527bfe66a9ba0b156b15159cb005d3202c612bd45b4e50b2e8dff91ee32526da89b11bbaf95e8a3e84eeb20223d2806	1635952206000000	1636557006000000	1699629006000000	1794237006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf771c952c7082ec6a0e6db11bb537c7b62daa8e105c6c4b80bdf31dfc769efcf4b3285b3eeb09ac15e6400e96b1c458c1e37ae92e6cb648a1e4e3a878013e6ef	\\x00800003cd7f7b1afa43e222b514b2f873b1f5ebddb30f8b4f34f6fd7bbbd92fc6959d9a54401ac144632563b5c2f963047b6812f1b34d0d57953babfddbd8d547df19ee7074fbb3f591bde494a7b01e5ca2cb58e82873027e187c1823dc7886ec004b764a6b141ff4a8297fb115ed654b1227c9f7250d44090a88936270756a2bc7a61b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1a0027de62783dfcc823833fcca6b7bbb8b84cad60b749e67938a5baf21251d8a091aac3d9910ae892cb5d3854c52a6bfe6582b80884b2b648f887ebf1153305	1610563206000000	1611168006000000	1674240006000000	1768848006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf741f58576d33c17a9c727e8594829b22754be898d7a4d8e1c6a3954b4d73c0d61374ad395bff07d5dc5910b170b5ae549712b65285f75bbdcca2fb162df96ed	\\x00800003b7eb542e169c06568cd482cebb6f1d213782a912ab1090d9a18013e6a85195c571f33ec829386138c2ae8608b6e1c9b380a7c7014ad2fb3b1f04fd4e480d1b52621910eaf3d3db0c3fd734d463d60921a26fe09f865d416703fcdd411a9e19b89138bd206dc8fe6b9c57fdf4bfb6825895f9e77d567ef7680c478443f5c7d761010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf6db0991848adb40dbedbdd02823c5dd3f793c10212a756c8640be4cf258d33c4694986259c571caad2fd77c3378da510788c157533be8ee2053af580526870e	1637765706000000	1638370506000000	1701442506000000	1796050506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8410dd55ef8007484055574b79bf19f74667ed2788946e8f5f3a4f39fb9eafe9c65f40d07971d8ed75df9325b68d32c3e52e7c0eec76fad59a2f2007462b929	\\x00800003b8b4f6ffdcd54b753e6d817e365a106ffd23dba2e2af09018b825f19a0496c0e57c613feea7ec69f95dabb03611526089abd4067632cfbbb64be0187e68463a1b05bd2f500845271cb99810c2d57f7f6cf9989e63e08852e1f6c2ebb83bd65105c0b93a667e42a8017474f524138eb49374b23c2e690b071ee658bc132f1bcfb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x57db7a15e7b641db473053d20a2e4be582cd488fdc2874da160f8e1869985c9306eab15261e961bb5ccc243828af2d77b3148d53d43566cf354fd399bdff390f	1624466706000000	1625071506000000	1688143506000000	1782751506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf985546db01c133266df9a77b6f08e3c88409fc2c4c671276040b966901ec8b44fd44aea57bf617643d6d627e2ef778d83b5237ca14e7a2d63e374abe29c2b85	\\x00800003f7d680404e1f7bab82279bbd2efae032a8471161bfbcfef2ab87300b7e4a009317ad60e4a4b5c78429fdd56a229a34b5827fd736cfc887e9a3b3a4bc53364d832e2f58a3335b31ef57610231c2e91ab272c3c446d89553f3a5fc332a2ad37b45b2465d089d0e768c336884145ac09be3bee06050e2c4e796fd0a30144a794c8f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xbebc4c19b0fa4fa63f834f382e25845442f12bc95a5551a4c5c2425a80946c9391c34899f075b744d60782d8a5215fda2aabca25c39c255b9a52a6d789d74608	1617212706000000	1617817506000000	1680889506000000	1775497506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfcd93ad783d268190fa68749fbe6f080b2cdd6f6e481569dcf9e20658ec819ba3a29af3777314cec4e462a970ba0590087e4b7b97c27cc004d513fe995737ae5	\\x00800003b9b27d6469abbd9a3f6ddb67f92a598fd1016b04fa4823f52b5a2a157414aa02e81fdada9e661b40aa851803eb572002ea4baa68cf4a5c9a33f1b12da8636cc45f6f9af2072c7473385d9c10720b9713c5d958e5eb83fb38f872d0d73a6796a858c34385196db6f05566dcf446131c315a5e2e9dc102bfd7d5cd8c085b1f8b37010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xaaf6b3379fa9ab69a0da9380ff3bf2317742a0a77c60af4d8727c7a25f7914625a7cc44898c4811eeedc405b0b4b658c2bad21d840c1082ec13ebec673a56d0a	1611772206000000	1612377006000000	1675449006000000	1770057006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0032c596480ef2db562151fcea1c2017780fab7840d9ef3db61106f3f21143d6b1a168826d636922da59ab8fd444bc6d920cb7b7d5f07fbfd1d85a9c60cc5508	\\x00800003ad5ada62633202ad2165ba0e3085166046ddca5741c0eda2d2dc994e799022b92615b45fd8f8a7d250e906b217d766ed8ef1af2e3f2f61f10d7833975c09244910523a5311d24e1048b9a5606d04cca6ec261d73f2266d6c511fa6afbcc33ffb5db3fed71fd233a30a2a50c863904ac803978fe2ee43da7d80a21cc781ea1d45010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe39c1632dd29a42fa0a6d7fab32be09eb171073a72c407a8b1f555bd0c8cd3a56b5c15ab6ed13cbc69282e7c32ed98e52c546bc4fd7b945e4ade3ba1ac3ae407	1623257706000000	1623862506000000	1686934506000000	1781542506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x007e1fd92507caea201a8ddcb3927b7fd57d0d55547510691fc6a305891d18311e2a7f5df8f860c7f005f240609ab7619cdaa02b0b46b90e676d4740bfc26920	\\x00800003b6d898478f7289d08f34e0e7f3afdd8ff1ca3d2a6751ef5497005a129b8f938907951a3aef32c9c0f671014cd4ca61030b2a4c5e23f16d7b010b2e5c87c9c906b743cc2a52af713f314d86c37a7beb134a13e97cecc3fcdb2fdc2ca286aa5b27714d2c0903d8d78f371894f853172f72ba8b3132937e75ebde381aaf4d2a5f07010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x39b0a419b40a401d18160fead8432107bd7d08c27a3aa7fc87b348c23cc4c1e59102b78e93f6edf1a27b4d062305062578ab8df17e17ecd8ccb676d727883003	1617817206000000	1618422006000000	1681494006000000	1776102006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x032eac880fa17f11606d6fb2ee82c08a404c42b475281640f9fbed06dae830c6ef2599edee5e528191f8da6afa57422de7a3503c48734939b88263c0ef861d1b	\\x00800003c15ee8ee5c3d5b1cbc6b5eeec8071eb3385b8c79e4d68284d417e4cfc85c289429c8c25bf768ca6ec1bc349be1cf341ccf3428254975c83c539f75522a28f7ef52e2f584fb53ff1702121addf16199377b008f222a088c38e4d8c7aa82676856144e09f3dc5be57544a2d45d82c36ea32ec6b701a91c1f23e7dafca34b1f64cf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x71f2a50a0f94908d43479907606335c710022f4d150d3982a3f61e197a9dcbbec7324682f3f7609e94ee0016aa045f35e608c6d2e957a5d4e2b22c1a81644a09	1637765706000000	1638370506000000	1701442506000000	1796050506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x04b261daa31ef5de9749d0c8524cf248ed319ec62a53858ca0ed7c900a7d2f97d98a9693870e71a3e14c6726ba603986cca7a8d23accadd715f3596e6743fb11	\\x00800003f0e521635be61839282f5f0d72ae9df98c9a2c62dabb26ceb1f9f14c028dc3a7b5f6e6b684b84cb791e5feba764e362a1dcddb06329ad0645881dbe476a597d46abe3940b20c254db504ded899d9fd2822d29386da6a26c73e39e8cf6e32ab409de6907fce5fd233c18cb4bcc7e360b4ddb9c2b5c9d51a16e68bd36fc4d42ca3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x391b6adde83ca27fc5a2f9e3e6deb50d1389c7f6ef5473670c451be827a04dc3b0af16f222a26d3dcbe9e6e77e5b87f22a8cd4bcc123ecb6c5d02983a2e1280f	1635347706000000	1635952506000000	1699024506000000	1793632506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0652118f255acd192d5284c53e8689f48f9eae8a0a3bdce16b078d1613627484289be89f90d85bc01a2b5e2242867799f14eb8903a5a796d8ce435c30caa7662	\\x00800003ce520748593df9d00a78397c8c2882d2658dd19b41474c286bba3e106d2e19c197801a5040a95e2dc928cc12af24bc9e02535dc9c49deec0f325e8b776ffd2ef72cb755d7bbf454ce91991bd5aebdcebe106f38a92b448c64da3ba0f04a949cec0ccefe47c8054ed080a0383fcd49afe556b4feccf1d0380e2573b804e36e949010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9c7421e6422f0ada7b2c62c27fc448ddbe0a064769937d5bbb624143d9a6b6a4641eff5186102298ac3ffc72cc85048e1f1d855b75f3fd188f4cd3fd9bf41109	1617817206000000	1618422006000000	1681494006000000	1776102006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0b3a581963b18f1cb6391c36f4e86783716ffd8c1cfa85ce158aeeab943ad86874b3821a9391aef4f562cfe9310cc66d4023c067204087f8d059ad106786a1f6	\\x00800003bcc870d0d9229cca4d1f9a5e79d485dde26e0cae6fa6d4eb82f5b2aa9ad842ea7d09965437067df789ff60cb68fc94764b43144214f27dc0ead3f55820e8b6f55ade8b8363b3ede3980ed926f09d4cfd567d3971d1d0fdfa0a7c895cdff7b61e742ec4e126c8910740231a81f8b2e41ce10daab7b0854c7f16e7c966fd1bbdf5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xded2c667928ae12810c0be3eb6049a08293318ab1fd63fb86dfdc78dfe9af1241eb1e7fe0d68152939d945c030e5883c89ee0d2458925f5d1b25516a72f0070a	1620839706000000	1621444506000000	1684516506000000	1779124506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d4acdb866a27bae5d14da1b070ca8ab237692be917afc855ac73c82a7f3b9d69d3fd6be9ade39f8f3fdbfbe2b3d71065f8b13919fd8018b4389c93e2e51a1cd	\\x00800003c3954f5116a23711e5c2873ed2c360615c333b1b49da85b2afd66bc12a7cdaf6ae799355e34ba740ecd6ca904203d3a732beb7b0c2b21ace72d2b218825b19120c74bbe350e17dd55107ffea6cc9e5c52c44e411a55d063cb71cfd48b17bff48d1def757f11e6a5e1525ad36b6f1245ea2d24688407b839218b11f500d627565010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd26bfdcd47653d7174c3cd133c588b32864354faad78924df1a07ccf16b4b1939bbaae79d58d46b4b77621aeb16de799a5742f8459bdb6142e4effa0d793ac04	1628093706000000	1628698506000000	1691770506000000	1786378506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x12121354a163eac6a8f2b71c2a9831e684c5df02b2f8bc462979305cc785a4ce51fe81556295f5341dc4c813e39da8d1fb423be5113ab187fcb5dfce8b7d1ad1	\\x00800003a989d8a5957a3d04a17a0b405cfe6d9757911217832d51821565565b0346aa7ac4cad224c524a0500d50b3de6e1ab2af05c2c29840b51cec6260717528690c52f54e9606250f3d215bb74a89998330882ef741307aac420a39ab114a05de00d67bd9bc594508a0ee12db37fc5591431617ab537592c78ada2476b6c93394779f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x10c49a6d87276d8eb2314456e58030fb1ef436e2d94279f4a8817fb277a6cfbfb57f66fa8984f984d61e0d595b67b7772fdbc40270e86cb3a3c7d79a4adf5f05	1608145206000000	1608750006000000	1671822006000000	1766430006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x127ef34050d829ceb17fe54b875cfdc40436dc1c1fc064c2a5826f8ccae2c2ee369ba72f86316468b68c28dd001758e432feda05624fcb8faa58a8dff4d07981	\\x00800003e59ed74b1eaaa2a0e0c603318e2b3b0fe3ad225b59df4c86987d001185aa1fc3f32bff40f7adfcf0833d36a66cf26bd762fd8080812e9dc3fb66afbacab8b4ec35615c9c2523eff4c225590fa634dfe0f430d2417e77cac97bd2f029a003aa25ecff08ba5ab73c2c9b090f4a32019a577436c7cb43a2f2c70bde6a4b6bda30d5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xcfaa273beafb54a0a861261edece161f1cb791bb6556b4ef6ab02aefc7c7b2f08d104df37159643e82a34a277d8756c3bfa072b20681065630943dcaf23c6600	1627489206000000	1628094006000000	1691166006000000	1785774006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18ba0c9f7114520efacd2a44b518c05d1a756cbf641f2fa53dc793ee2a400834a1ce975cd6cc8c150e4d9eee0786ce5c85853ea73ad9c1a1609c7b9c9e04b49f	\\x00800003ca63257ec9e31ab7d6316c446fd291dcea282add303144f2f4bcbf63c4c7c7eb0de613181b37ab1f728d30747a3a94b55ff9d7f6d75434abe39d4af4123dff84952b6e749f7ec5698cda90075168c00c3d747d11c0f37a94da697ed2f362beb6be1221bf44abbc8f7de629dee8dbd2be1ed072470e0595f0aa99c28b78b1715d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x486323d60460c183fb6d47f9abef2992b5b101a6036b985c47c8fd363c34b2b29b591a45655826e25e2aa5d0fcba15c3640745340d141bf03a50245c94bc730b	1618421706000000	1619026506000000	1682098506000000	1776706506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d1e05fd6abd8d258b48b3f939987fcaf6c4afd0e6e43b0f1b801d518ab436ebe6aae56131c7c9ce053f6f19ed4b73e9862a0d3a7ae0863866487b884775dc64	\\x00800003c3b15abba49f83f6b4030f868e1149411e0d2c69f13f73816408c999a707f66f1fb5b0599fe32aeb17eefa08eb54a350914e74252c255022bd7f81a9a66545400f3d1b1affcf13a410004ef86af5c1556e7cd176b10697a7a8351b3a90ca9fa1b9536c8b85bb888a9b2d0a01f5ce7367676eb31ce33ea4da76a660c4db275afd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3cb69422225f73712d119bae7dfbe867cb97fd09c7c336341bce0845c931aef67575f290bb6a5520bd81215e2de7f2ebc4e0f391855dad720022dd2dc23c7d05	1609958706000000	1610563506000000	1673635506000000	1768243506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x20da1e990f8b18aa8aa0cbf2a4198495ec226ae3aa776458f011bed4ce518bede78edaee73573830d92e54f70a64321d491a93b82ad40e5eed09db0003af0cfe	\\x00800003da319ef38472f1b55bc8301ad82e42e57c081bc30e48386450b8fab969f408bc01f25764aecb0336d7e85a957acdceda65589ed6da05a414c0c707e7cc24abbd10876d15d60cf09d816e4b443c2695184f8dd1dd015a3dce2ea0e5d1a0138f255be59a49715fb2c444c5296d7fc4257af0dd51747f927cf33097cb8b1005248f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x911e2663208389e4c48c4c0dcc00dade42e7e6ef41bb97327053ed6f832714381d7b513465b969a94f3bfef518f6a9a16667e178ca31b0d040e8503a3dd4c50a	1623862206000000	1624467006000000	1687539006000000	1782147006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x283e525d81c8919549e006d7b8ce7bbef892329d7a819c7487f08919e9ac2b7906daa7486f16c8102d34c8a5a573f2edf1c5502aed2de18f682dee5ea65bcb99	\\x00800003c7294bba0d9bc15a23bf01d94b0c11e86a6b900b06db3007ba9c17f0ec513d602f10e9d13d580359bd3b599dd346febde213b02e9d037e45d6520c88360f3f7c51cc3fbd84d498d6d54abeb1bd1ef3273832e6dd40801d31fb42c3c6f0b094cff03f0dfe8a4cdd4e01de82b62d516f734592b0fe40e22d75eef1223b86c8754f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3fef2d78c7f0a8f6a5c578d0fbf70e6274b107ef548538430e72f1612b3fc619571c836852c359d5e9018e8ee1c7760bd4e5fd8231db245c215565eef1d0b50b	1625675706000000	1626280506000000	1689352506000000	1783960506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2aea3442939a8876296382e0a88319ebd5b2290cfb813e24debd5e35dda4e19bfde386361341d57afba935766aa33fbc85c32cecca737bb250e16b9bbf3b4d2a	\\x00800003aba979e1e6ad0bd20318d82236bee6fd9b96add561b6a882bee9b24fdaf3a7ce4246a3e5a7d26bae7273ef53e338b7bb49c0b2df4c5e91404bf3b9cb853a63bd49ac8a48e50cafeb304e53049c1be2ac2138895b2fa2be428a07d9dde83e02df888a41eae0e66765e0ec31777d1e2bdc3b195408c53d8c0c703c782e65348cb1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2df02eb23348b14c075001feed28ba5c8096dc545c6490c6bdeab5a5cd4aec793cf1740979706010c8f13efb46f4ebf46d9972b25cd061167d0a5abe78f6650f	1620839706000000	1621444506000000	1684516506000000	1779124506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a9a359b3bb0d100e89995618a549eab82a72458a5cc13f39192316ce56fc71f52505f1dd8d1365be9bbf6e15dcc69b390b6266daeaf7ed7450c98db266aed87	\\x00800003b1340665e7ade2447a978b51649bd18f7935f32b617dadc23a0981bfe3548053d83b17ade02c2371ad576a2fec7d377eb190a79f49af49de6789f0054a0b82b0bcd3e4ac3ac427ee0ddd6f20f17443ce93a8bcf61f8f81fa21498c19f43acbbb1dfa70eda8f387694d75a85db2c7d034a56f56e58373ba07768747499c149e67010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1f84849d278a19d9d59051d5ca311e6478bafa5a51648df48c09f52e96c1510c1886a2031081e94ef43e0335d3ac523208c88105bbf7d7ad503eeda68898de07	1609354206000000	1609959006000000	1673031006000000	1767639006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d3660c9bb35ca2e28c1f86929464a441ebaea366122bebf7aff7cc9b5529ba190d63c989e18ff9619327bc879d8c8e87e1db3385f139b7f3eb9633fcc45f905	\\x00800003cd998391720f0bd719b3c95dcc682bf8a6b9721f72110a6497c6147445f9bd443b38ed18802d79d838592883e29ec80db2d3bd444aa93624f5856b8b9471825f54d266e488d274bc3e92e1e7174af2c7c3088fbfb5ecf3bb56d8b17a8c2bb46d47c55a5a328fe9395a50a58bfee022d30c667533b290953ac353b4a6f1a198f5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4db0d5b39b8408f5109d592057c10064950b527a9a4d98c4ebca5f81f7df6228c0b0db5bf3af59d1570fc80add979500572cdb9fdc6cf90afe63cd251c978c03	1634743206000000	1635348006000000	1698420006000000	1793028006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3042c264d6c4e1a1d0cac61497eb099e750f56be30f0a7ad27a4c4fa0d42fa647e6262159fd495538647b4ed0c38031b62eeaae12111b9a2eb038d9a4323ec44	\\x00800003ed713f23cc0180d3965dab5fd530f26dc586ac4c414a1a32d0cb456ed1f1e3b690536c5430d18c8c962738489e45ec41b55006617ef91e5bc698029a88fdac949ed40c5ca1e8808e8411b888c3ccd2d3813964600f76262cff7be0fcba4c1694b48474148898a911b4331d6badafa02f730ce3a55c84628f356b43de0229d4e7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1e4f4b416e71ef3ab50ac6d989fad73f77b3a105cea04b28fbadf035f30de790cd13acd0c8fa625471122b30a6aaa128ef21b2b10bf2416a62f7af528f6d0005	1610563206000000	1611168006000000	1674240006000000	1768848006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x31ca9beb387dae8f1bb4fe4b54ee91a56b69cb46645bc093ad723679da1b32aa5e40b331785f93894eafa334d53db8e4b244c00458793b0ebdffd877a39ad456	\\x00800003d68a3a911dcb685e55f493d4720a1dc1dea672133023012fae058761c2fb0e2939f4dd40000da5495fbb32cda09c88d8cef2d0fceba9e33ccab77697fee567dc934beda529fc78c30b3335ca89ce52be37a97627da8284024bd4acf566db9bba019f04cd6300906794825c9c3998ba5a3275a92648b4635f4dc3c76c2c2ca79d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe348addbc847ae5602d506c70c501d18f08b823130c805cade172306ac3dcbab9941b1847c7e85d8b5ed3d6532587a5e03145211998f3cd6c67531c5e7638007	1623862206000000	1624467006000000	1687539006000000	1782147006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x37da1051ebce87a9cd2a701606ce55d75ae18ecf6bacf6fd9dbe896891fcdfc4a7d2ccf6f8fe15e41f10695b0a7e820108526fc5a6e62a0db4b1d987a4a8d16a	\\x00800003b94161ddb88265a6613a5f2ff9c0f4ed416ceebaa4f40dfffdda7491967fd1b07f6f783ec6d3b020474ef2e757322ae182b18dcbfe8d716d52a2b5f1d93eb627097c569d3d5b667604aecdd80d935dcf518b4649da9cd4f46cf7284cb0c9b39acfc25526cb8b55de710fbc1640d220bf47f70bd6dbdc9af76fb873b61a43790d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3faf1a5f143413a0d4c83c755e5226cc659f66c214b7c214c2d7eb6c38687e31cd7f088e0d897cf23874e56c2155bf361034214368064c284e15ff82e2605b05	1630511706000000	1631116506000000	1694188506000000	1788796506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x41563acc88955a555582c848aca2989e959cc45c1deec7fccad80718e77da82681e1081cc47a891cbcb6383199abf3160f478fc6962cc73a7fcd56e3d8609cb8	\\x00800003983f05ae72a4b523c0ea40fd05e43d56ee28aaf1ea80e73a1ce6424140da5104d12f3352dd2b83fabf696045733063da2bdc0ac4a7b4d9a3ba46779d8581717056a01dac0b18091ac66ceec57a1516781a2bc56cbfebafd78bb0c46bcc4f39da42d34df4960840ca20c1aaefc8041cf659eb46725c5b1368732a53be0db5bbcf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdbecfbfb53c71650349532f19d848db87c63e3a5237f6a763ab1cb3174fc497398fbf999e881605ef12d28852986e232b1468764be29b032dfe4681acceff802	1631116206000000	1631721006000000	1694793006000000	1789401006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x421682441ce46d0a61e58848f18aa388afc583e433827c9661bc21827ba586398d0c1ff92b6bbb2bc8e4b1e72d11d922ba507fd91ec15629718a66e86980987c	\\x00800003b1c26304318879dd5645c06720c380fe56e7042bdce99ecd1adf130156048f11323b9860c48480c87708d777800436aabf337ece5a881b0157e737c7ee586a8decc472a8673477ac9404580148ae88f1ac53ade658ad7567b674fba81ed6769dbe89a7b3fd73b7ac6fb247eec399b13c9b06f1233df4b0ecb763c7f411a11ba3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x90aa4c2fb4d8880a10ecbfde5e60fc615bcbbb72ccd059ef7a33db7a9ea357ce30e6f4e05487668ed785ba896a3861a770b6c5a00f863014aa22f9def42c9d0a	1611772206000000	1612377006000000	1675449006000000	1770057006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x432ea9975bc89b6400554e6e63bb0e2d3c9e8113aeccf8bb30dbe89cf5d2d1fcb792be206ec67ed8d464231aacd37b513a02eab028759026108e2fbcc782e612	\\x008000039a088747215050a485e9efa30fbfc17c8accd8c42148306533a6449b0e483f6f6b2c8948dbd18c3ad53e33fec8837ce6199d87077cbeefa955cf03e19d0577dda92bb9d2ba2648fc524097771db040184bd4073372d79c7927171fd3425c531e6985dfe35da14dfda0d967caa4e383ea9397167eaa7e0fd9ad9f4accbad132db010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf767594472000cd4228e7e81905f17a5643956ba332ca841f13414cc90c288c417bc53d9b43574a4ac8b5e80f52dd701cebde6236a85d891a6620c14d34b5e08	1628093706000000	1628698506000000	1691770506000000	1786378506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x45a2f4c034a8194ab3a5941d6cdc25a4674a7955eb7814ccacf25c28f50739f63a6891ff0d42db7116a09ceb43de06da453212196d6ff32158ac755e9b62c9af	\\x00800003ad17472e5784333c6d092b4241b0f9322fd7bda4d262c6115540214815f12b67486c210cece4212b45c62b76ac185e719a394864c786556ae8b96232dae7df73d7564f60f502e2e09fbf965168f3d7abaa7dd5d34aac4eb613e527757c68dc7e55ddefd9e34f2353348fc90f9ca89898451436a8fd5b7de3f24f9272aa08103d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd8d27bbc511732713c23980eb1f8dce820d33972e262b74d4bd0b57b97f5ed94f3c528c8bd6786dea7c18f47c7c1bce79971d686165e11bd32eee81402d7960e	1629302706000000	1629907506000000	1692979506000000	1787587506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x483e2d61066da9d0fc99d3b284ae16bfca83b356fb53c09094e95cddb313c24b4add84427cdd435aa98e6da298d5d7b7a65565516b08a8e75b666eb98e6e073a	\\x00800003b1246b08828b25df2f45c9a191450c1fffb092d59c53af78ab69aeb495351183f0541405f2396fe02b96a75cb7d77694eb877e343eef13823e0456b1cebab315780a6182d7315e090c7037e0742ae054466c6583fff37e9464637044c105c519ad5dc8e338a5fa4b1ece1025108777cb44421bb720b4ca92f226f0cb212ec023010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0939ccd575060f25e507a5547265527b17c1610449a93fa88b1395f2a043e735018a7a6eb2e96265efa7ef9fda9661696687c8a8e3301f63e4d69cd9d86eb908	1613585706000000	1614190506000000	1677262506000000	1771870506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bc2cbe5bb3a7a042fb97e10841695812080d49d7bbec43734eb8aa068a7138551394e5b48aad170036e70c5c33c5ee214b462f4ef2ae84b42f398b6f110c431	\\x00800003c1557e0f6a0bc353973332e6bf4e80eccadca6de10775c4eab09566b0148e78679a9d8116b44448efabce2997b35d2003075df649ded33e8c4aa2494b562e6ef7b1d75d998daf547fa638da4572b48b5f669e31c82442f273713000f0b4f4917bbf0260fcb0c527ad251ecc1b41cf9acf6423425bf4184c06e257d12e4b8d41b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb8f6eea55c85dd283fdbcc036cfc0ae9b5443efb02567be16322972b2e5149aae230b54e5583e7f59317362fa75ecc497052d550d78b628f5b067709b050f00f	1632325206000000	1632930006000000	1696002006000000	1790610006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4fba098258c77268613f259c584afaf2bd4c1672a932d110643e8dc8337b8e65bef65ab1f0b56632cfaec1395f7910ad20a3aa7f653ab9b0be53ee856d649a9d	\\x00800003c41649e888c53d3776f6959495f6371d0022d4102ac94dfeb1ce3356f182634df3a0c2f7edf65353bd4d0af77112e6f6951e8e531d628bbb6ae412b02f0acf6cd261c43c8795c9c11d6eefcd1fee622983d8531729656485291fc9b05bf1a988dcd7f14d91fdef7d4cf5c593f7a79193a6d6312a3770f9109f2b147c340dec2f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3591025d4fb8bafb0eadd1c679c7165013a1719f5cc868044c5cbdfc69f1861ca9f56bbc3a3f9000987b6980566b9f79e5303770e3419e5ea7b850c5984ab800	1637161206000000	1637766006000000	1700838006000000	1795446006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x55a6cf54dace809512e10b95fe594c88ad997b7927ef2152ba4c3d91b21054e51bcceb5815c1dcefdd638737c50a337e6ae7e14273f949217872ae88beef047a	\\x00800003d847e7070311b85c7533714dbe9f3404b1609fff19733c3287e43cbf7ad7a68f34a4cc77b033475b3af99e2e1e53ca2980ebb428d60f16470cda4c4930bd260181e715abfe6f22b7a9a9e3804dd8d628ad1952705a40bacd265bc590b205cb16b6c2dde9d011200c7ee9d71f8e92d098c0b391d1cfcd6a0b1aa2da139220340f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1f63155f88d458e9460a5f4e6219ea9badef7476f219e3b76e2f135d432ad10338d8bc3a3e9dab0216e08fc6eb5785e432a4256351090e9b349d1f4333afe105	1628698206000000	1629303006000000	1692375006000000	1786983006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59f238c440625d61445d12603963ca7f5e7f3dfcc8fc4e911ae1a615dfc4a60ab163bf79d8498844504c66b74768bc7ce5dc5e96aa4b4aa30b534c729e33bf0e	\\x00800003b472e45697882ab063fe9280a5e7c84a8732bbba355fe84df708d9dc6055a58018f9a87e586e6e41012db454102f08763c26d9283d5dbc2119b66b201da98f4f6148303ef57c85a651bc046bd62f33bd5842a5eefe9c8afc0850a9eb210781ea21de910f7883b55a18f6ed26b5f3c7f5b595a6dfe106ecd6ca9470d08a213eff010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1908120a770039efd6c2a1611ef3e96870ef345fcddf621abd2ee903f61092f4cad28b52e701ea7d720078cac4547129be1cb8f07029de754a38da55810def0c	1623862206000000	1624467006000000	1687539006000000	1782147006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5c0e3c6a5bf9e593c1cc831d38999f10541152549300e5e1e2a2f1e66d4fdef37250ba50ca923d6a1424108f5616ffa689d848df16cc22ae2c1092479bf6aa3b	\\x00800003e4e1df2f2226728552034158c90fa198f9b572c39e86b4c601ce13819ffc5caa3a011648a6ccc46049696b05f1522ceb17a4a5600f3b2a06027795f5738b11487c531548bc55f5b61367f1afd54e4fca564b384249ca947312fd76ac2e4517f378198382596c49c1f4fba9fba094f904194555307f7b9884b9c22ad46a880739010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5e1334a0137d54b8d041555c57e66e1664c433526d0f2892b7ba3164b285fdd9c002b3fc4a41083444e2388fd78db0cdc191b06da2b876cffdef3820fa13f003	1619630706000000	1620235506000000	1683307506000000	1777915506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5e224a1d2edb9e910b891436a538c650798925c8e3634c62024943c44c168f0f0add452aef9c748a3df3bd98fafb9c33353ba183bdf687e116df1cd10aca2897	\\x00800003c31f8bbf8de6735e735c6ab96b5e5ef7bb619ef67203f71229abc2186da30fe7a8c41ab863ae62c5b52655027ff45cb7e97b1baab58942201a6b097bc8a6cd5bf5ca8f4a0bcd173d3c72b41628e52e4a9b5af882389de2dd1386eba4b42df92af268dc530083c601bf713122f1dc3a0887a80b801f3c4cf83002d53ef18f1013010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb3dcbaffc00ba5e98809a0d2a1fb4737faeadc9c346a5dd854f2addb5783ea2d297cd8205898472eb82eae92a2df77f511c5eb308ead8a9bd33accd6234e4b0f	1638370206000000	1638975006000000	1702047006000000	1796655006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5ea2e3cd7e1bd5b36d9e396cc8b9c07a402c4358762f27915715a183920ccd3293e4ae071e75b3e9884295239deee19c700586f86bf9b63653eb2596259c845c	\\x00800003ce4846e2bb3d1b748892b8cf17e595b42b4977ec701c79fc8dd87da8eeba52a408d868a13a24827e3a2e4106376399df74d113fe6dcf9a6ac27370efedca6de618418d246102fba6ed0fe97133b459186f3c08ee8c84ec0aa548096c0a7d9e9960116b3f49d35347dc659874e339132cc3a6821431c4233655610fbe3f1ab7ad010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x129c899e5587a836de7e263ecf578e6e6262890bb2cdc2ce5df3359b6e474247530a831cf86ea81173e0cc539a5b7747de2f2b573fa4ad200644d4b871dfcc01	1637765706000000	1638370506000000	1701442506000000	1796050506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6412b4872b155ca29a7d4dadffe4a9a51e9442b89fb316c5b0c587d33b3979b7302a1d9856cb51490f59a5d4fffc23cae3c3e9ed67fa9229b4c00eebdb9160d7	\\x00800003b481aeb5080f5c195535436a91f58c80e5244932c2f057a357f1d5ef0b83ef77e03530c5d86c1738832715cb2d08e023a4ea453c61e952797d7eecc8b7474445acac75857834f60f777e7661722409d130c564fb7bb5ef0db4665ced0de493f76a70c16def0e19198b954582879a43cc447bbb6e052db3fb13296ffbf39de855010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xab24644a81c691b1f55331346f1aaf936b4030497c0588ece893e89230b5a2cd43b9fe347765c27f0e1e311c4e24bca2945d94ead6b6b0b8cdefb0680573bc0a	1639579206000000	1640184006000000	1703256006000000	1797864006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x66aec826f698f3be07b4423987288d38170b6b91377e85af56fb12fc0721dd150b323c795d094dd49997fcbb7e82f4eacf3c861f5a659889e06b639bc2da2723	\\x00800003c3318d8eef3bae09ea00f287e576beabad6144a1dc4c0c9fd3ada210ea952d17e95e254edc3baf8c18585d1c4462ae2f06d577d8a9275eed4ebb6925f8fa8791d0893beb51287e644a6f7ed6b360ae047d3353ba3bedd9afa6f23a91cdc5b5633d9374c3546d681ce1785ab88028f3f4e05bfea4f5ce022174be97f4b7aa8cc9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1bd852be77c444fa927c46f23dd36c67234402bf8721cefc21d073e156d7f90a339bfdee53be1c10e286fd606b97106db55868e997a7d4b2f21283cd0f660904	1620839706000000	1621444506000000	1684516506000000	1779124506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6bdeefba2626409f8d1be4b519e83fd3c090481bf70e13f0696b4eea65c08ad2b844a2cd7e822b277872081d76030f983bb2be0f5427226473f51bb2a72629ad	\\x00800003e0d30d5be4c14419345e102ee40ce2b1d334be3d583008875e186d0db2489c2cbf2d266aabf47e3ca105adcdff39c74fddb898345b30ef9995fb5c914a5c78a40e8943834e35b117d40bdfe82273eb23659951ef605d565e20dae17cb515eb7bba49f5f308552e57f2b3202567cfc1aaabc9e8a0e651492a669ef8d17a2bbab5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xbf05d1056dd4dcdc502c4acd22085edc62942eebb099c2d0e62f2e0bdac4956cb660c1eee10b8f6e26ab881f73b7e8692dadc00d1fd612a8da7952b8da811902	1617212706000000	1617817506000000	1680889506000000	1775497506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6e8e6b34ee902bbf5e03a76cc2c2ef59754d0de3c40535106ec21b3eb872277e1e1c35febba48ff0024261cf4d80c262d56c218bf3cbae7f2a46105cea0ad791	\\x00800003c6ac2725f695a32eeae435906f6c9c81ba33009f180abbced0a5faacd03209a05054cff57136e9449c3470093991c6a749600c75123c586d1328991b3a237971710ee35181a458fb2e85d73aaaca27d173a61a010b400733747a221ca4a53aef48f4c4af31e3db7ba86af201ab3c630bb02be1abc924865de89504afe5ebcfcf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa1f7b3cff476c476fc4dd3f4d4a7ba13d27d4c5f112cbaddb4f8342992b57e1598204287807553ab8399f9d6f96f9e0993bdd98b708705817143264c883f5200	1624466706000000	1625071506000000	1688143506000000	1782751506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7132e0303aff7211398379991b581ca0c2210594a6ddf0d447cf24d8ab753c5306443071a67469e9dac2fd2c110f679a4a55626d7521949d680116e16b1a39b8	\\x00800003c46b7f3f2381621d5ca0e62e66963837e4fd54e48fcd9e46a9449a8cba97a23d4ebeb51a06dffdccce1e7e798b5d3f0659e81b95868034a27af2577724de4364771d3620408c1d61d79695cfe2f90309785da8d6d4f23004abc9b9295e712f9c4459ae9091badd78291c74eda40c3ef2c94cd9801fcde42c00c07d400a622e5d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x7c0c17cf208c2e7bc7cfb52b5bef6662bd41b2ff1338557d5f3893567795cd2f64c3072007293a19e69f5803a5015e43e05b1f49f7744aefdc9067292ac4fc06	1624466706000000	1625071506000000	1688143506000000	1782751506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x748a4d9b256f545dfd6f32094d8574a06e1cd28008577730caa3facf2dd8deccc524960040c896f5dc87a5a4eae509b855ae71f14bebe7ae0f6fe7c52e73a659	\\x00800003bb2c1d96e3ec4e9b7ce8c4713dec63d0210accfe964ae2199b296c3c07271b38e95d148278202c076cbe341f2a1e6ad7e85bf3a414360ad7da431803638c92be896e20fb802ca29d4bcab296aa3a826d2b211d2e29357aec26ce3c779e94a42386b16022d2a15956340e6034a1911eae6aa86ba9196d3bf51e0640e246e0fd67010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdd3f81bd2b1f44dc66ffe0a33d536cd8024c48a1ec2b498f93d9a4dac281217bc0e31fee4a36d59ad304b7f2f5d13042559c764c2297bd42ce4307d215515e0c	1611167706000000	1611772506000000	1674844506000000	1769452506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x786e26dc0f84db782198a6a37e4b73061d0e53b6b830562732426256bbe3cc52a95baeecc38508eeb16b3bd53364aaac2a36cd768e28ea324c64c013d2b365dc	\\x00800003c89785ead13de2f0966cd3c6a97aa28f32711bb1c28deb831a3b166bab36b72ec0d5693b22d5f4699d90e1b197c76e4d10102b3917f5bddb7b8517a1111776cd04eea1c2f8f5d89cc4e656b1da83b4d540b3ea36e43bb7bce0548a206eb9ba8b7ced616ba63e23fd907fff7b249c30765b2435a3448e421db5c75048cf19ba15010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9c3773dd1d0c8e0c7b71ce3e2b64ba094232ecd45f09d816aab0328d419b2113d1ef49c9289f7351dbb399eacf5b2d4ee1d0968feb60f71233a996fb9688c70f	1612376706000000	1612981506000000	1676053506000000	1770661506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7936f7017f518470adfbbfc73749179b44e76efbb8910953cb51782ca25b3c83091f5cd93938cd5599b0511b49fcec460e4abd1c3c81d8bc5bc59257c53076d7	\\x00800003a723440879ff28c1985bff5d130313e783a82a33d0dd157e139eb538bf94eb186c7d0c64c664711dd0af64bad060ca4870620cb029abfe8484c27ea09a1eae7f26cba1a728ddceb92f1c0e960a85e657bc6c72ae6d78e82af8d325436dd14634d890595346b220d06fb01371faef56eb91843834bf2f6c475fcbd25a4e0b1919010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4135b659b1a819b8c2de28176b1112a7dba454656d0460475846de4bcb4cdda887663cd24c7c08dddd280978738ec8cfcd181a48d756c5e3a94f395588d81b06	1626280206000000	1626885006000000	1689957006000000	1784565006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7dda59edb7cf64e774c1e5f106cefe6424b2fc0cd826ad2a45c72ea31b0379017cdb84f17cae977f4def1aaadcf55d0242b46c15555ef470f05581220a949805	\\x00800003d108da4c572bfc0476ee535310e3cea48451e2678b566e1afb844751456e88419f8b84ef70f6ed0984069796c9857628892b71a627aebaed98f1b17ef3f9ed14b22658a443c816958753f76543c1f99c403e021bc225b7398242607175128e62951b12aed333c39ea0ff37e97c2c76d335b1db693074aff9abcf2fba2587c38f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xef2b9e71564141d82a552e18122b53e4ce9cf53789d9635f66244026a8cf26edcdbf3134bd212516c5de46dbf3ec80225b465b204864ad2b94013ba0e27d3702	1619630706000000	1620235506000000	1683307506000000	1777915506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7dfed46e990a71e3afd45cf0975409a62512097732e42822341ea33e0e26c22af9b3d89d4dbf94787203da41e99d59e1b39b640736605b767566f9ca46024742	\\x00800003e5d8cd09ca1d1fe9bd8473d417fcd423a3076ed18e5c6e8c5de52ccbb29500d8c329cafcaacb6fe7698afe50940364ecc9268f4bc42e28ecf0548b98c3bfe992ce12da923eb96dffd85def57b5a7be7c6de7839d040dbfd8c8abd66ebd2716495bc1f3a626768a3715b4b79849eedfeb4f5070f0580d37a0faa7f34e7b2ad857010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2195fb8d443ed8b18e6bd1f281ff7e79d5868a2bd5eae896dfc806231b0c7cce4bde442a5b14d8217be7bde533cdf5a543c0840f161821fe43407c093c9ede0b	1637161206000000	1637766006000000	1700838006000000	1795446006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e1ebb8f75808d07bf2006c75b150f53a7a2d1d84dd8b5c0e902cb76eea382b996e54caa7074ed0fd11506085f59658dfd7b8a0ad594008dfa76cc5d729fc1b0	\\x00800003c2a30a1134432706023a114974538f15e55341ea96cf2ec2908bed97d6ad249c4b8091b92cdcb64b787a7637d250341b3e4538378e8076fbb992abda95d3845832a11c6d8be5b79a351f70ed121ecfba9fe697fce3fd569be034667714c922abb6a20f0afadf9e96c5f337ea3937992208a1494b3a9687e7fc01511052816faf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6dfa81ebe291301d1aa00de93ac0a6a8a18d2af75d2284a54b4f284765f4c6d9bccb72cbbc1bd852bf3aeb128a32390ee5e329fd43a00653b01d1eb4f512160c	1622048706000000	1622653506000000	1685725506000000	1780333506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x800ef6b4ad0c2e851a434627b90321e2023ac007eb6e759a7af130140934fda0de4bd4ec56015fb1ab858ffac1c2e8d93b94ae18d1da6b9a5c239b8097ad6b21	\\x00800003d668231ca5e8fadf6b8128ed27a2d8336049cddac720ac449546f1433a812ee0fbd30e94fa0faf8bfebd785e46d1d5a8ba65b646afc46531936a5b08cf31ed6895df245f2e1ff02eb590962b8efdde4a41b3be530fdb554bff23774d38a887516166bec51e6d2719b02b75dad4e8a3a23962e2aad2589342226d8c35f4876a63010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xed82b82d52c08bf53a384a59b4eceb7375a89194ad4c2057055844e3add6b4d888e80b0948f2b31da429324bbe7bb4f2a152258d590e4f77d30fb34455fe9806	1621444206000000	1622049006000000	1685121006000000	1779729006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x80b261023d29a44a70a58440378c57ab89dd81663692e677137543b08c3efeaac8fda6308a6cbe5326c3fbcd101849bf40663b5d2bb1946cca37890f6f54d89a	\\x00800003c6cc30df04c3636fc241afdfbeac58fb524e426d49e79adafc6a9f5d9489d77f1c50c9df4455bbdd00667427d26d69117ccdcb5513f999a286ddaeeba166be66016bcb32ba2d64ad265ded6134c6ee6dac982112a2d54da59c70ddae2735e46d1c11c1f18dc8439937ad9af5f2689fb3daf9ef9082ac91b410c8e1ecee24f991010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3cb0a2f557a03c04a4cd4959c4ff75d7ff85ddd4ea702c175ddd0327c4a1a22617b06e64c931a49487ed435423654e4fca8d131dedcb5dcea258f9bff161340a	1612376706000000	1612981506000000	1676053506000000	1770661506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x811682387a90244505314ae4744b821b71bcf4b17f091f047401aed2385d3df9ad9c9f26b0e0d65ba87bb4f8617cd6bd4667b65cc5f4025010046980841267c0	\\x00800003d394f7ab9c32632dd87f1e972802ac81bbeed2ebdd6e651504b01c7b0d6c742b50ad2f22b91d1b93b45a4824c9e98b54c7b218b06819fb9c4f684b6b952226f14a9495f74091ed54b8c963cbebc9291f48beee6c6cbb84cf47099e75132b42eeaf7b3765accdb3f4f0349d8ba9cb219ab40ee2aef0b7d7653ba30ae105539291010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xff734905553204ad77d900307cfda3a35fd0122420206ede2e21be087582ac4c4c0e82d28d0f71e5446562f010b6c0a06ea0fadc42d95c6ee05bd623ae240a00	1638974706000000	1639579506000000	1702651506000000	1797259506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8662e898f6ed111d98c0640892229d1e1f609ba2821e18636243f027e1415976219ae3636ebb250a8aa30557dce3a018c50d3446e022a78db2fe7fd71375b487	\\x00800003c3e3ccf37ff8a581d6166564f22e08d704f7b8b3a588d503fff8566c1fa72083374592c1a17a6f8ccd513c1c483cbaeea8117ecabf64e4a5f02faa7366fe87724a18b3782ce7f2582e227d0a9407e3c39156ac5256b90766bc72321e9fc1d2baf66d1a599af212577f7a489d0355ffacaddc663368ea8633540f1c72ae11673f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x44334b2cf16b06f71ed86c523d00978ae50b7687532f01725d3056ad16c88b33c48bcff80195d11769a47c976ab44cb052516709a5e495c0e66dbee7bc37a005	1626280206000000	1626885006000000	1689957006000000	1784565006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b1e3432b1ca8ccb093321be4dc17e5b637e62cfa6db5a611cc4af6231775e95ca045a33bed9dbcce74ac6208baad7d8755489694c6271a5a9027aa0717b61f7	\\x00800003c4ee6e538f55e4703eafbfdde019953254b373afc37ec527c6adb5fb9929c09810a5881a2781850b48e4cc54952f2313ee2aef9151f67dc6de8b88cbf5e298d9ffc8196930eb87d53ede81bd5d4e0098d0078be6e6cbb9df4f1f054491c14e8b2a69ea0fed03cb9e789a04af9bca33537ef0336814401696bd285243a00c1aa5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5484beb68eae3fbde5417d03e0d74f5d35f8bbe07c563fe09cd0f009274e39a75093dfb84769a804d2af232a641edf59d36be92266f4b88aa81afa9c84681901	1612376706000000	1612981506000000	1676053506000000	1770661506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8b2ae791a1abaedbb4e2b3aa67fa9ba52e23fc1becde9b47494bb86a986809372bc084352ddb856a033ff62e4f6d073e2dc12b210d0e358e53359a0ad1fc72fe	\\x00800003ddaea87d10efef3d3d41d51f04e46f5347a9ec07c6de19c47506d1b55416e143ebeab0709b65ee292222dafa02290676471a07aab03245be2dc1ef664ad37973b64315ba8adc61b3f7e070b7772efe3e5956e1156e3e4888db1dceff82adfb2c2e7e89b8d89cb32c175181f658998d367116d3ccce770f0e9bed341a2f3a919d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xde2be22897bafba9e2506b871026cd60e2da1e20e20abf7347f1de59f3366ccf710ea503f29a458e9eb2a480eeb4c7c6e4753a17e32601c6d23eef228733870a	1639579206000000	1640184006000000	1703256006000000	1797864006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8baa314256f35d726897b4f6ba79b1d6f3a150824b8b50e9ffff7d115e69ef55c68bbb894433e9f22a9e2801e09c94f2c3dbad1940ea83b566195c1b4dd948aa	\\x00800003c20f97181b3ce315bca3537aa342a824b0810a1fa8074a1c0b2f8ac222e02838404b5b75dd55eb8e00a5f042e66b6280e93064c53a2d0c8656c987942d2bc580d2b81d07eed4a874b0b1ba3dba4ce854184dc6426f35eefa6de7e4457e5abef178191f3f71822a9db8e3811a5a30a441f413b5bc1744c71ef850468250ce60cb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x52920cd94ef3a9bccd7c16ad3bbbf1a3442b25f099ef588294917053df0aa72ab0bc3991d6ae3117344d9b88d96635c51c30932bdd986a883244489651bda405	1616003706000000	1616608506000000	1679680506000000	1774288506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8d5a89828179b2270a141b1e77721b589fb521f22be1fa9b80b410019e74b5b76babc9713c78ecc93c42ab46ab6119bdb6cfd77138ca12a053dc06dd0933a0c6	\\x00800003b5d73fa98c4a7fcb765403a19a22646df4998037b355943955a7ff4389a2174d311901166f179e3ab886081ea8cd335eb580818e37ebf7ce1897a1625185b08833294984ffd4c35b608e79762bcab0685d2b5ed27b4aa136ffbaa21717f067bbf4578472d5103424beb0eb3e0a69e6d0e284b9a9c9e9ff6054abc1d998ef175d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x472179f6d09ec60eb143660b457e33ecbabf5acab883db89a08c7593c22c14dfcd4b3ca3c02320171c7d5aab3c0cb7ff071019663dbdd56ced72ea3f949fe502	1623257706000000	1623862506000000	1686934506000000	1781542506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f2657a6940a097c1eef1e5063d76195203e03057f10870bbfe70b877fba5c79537a7965f634c862b7be08252fb49787051690ffd60cbce80ee6843a8bbb0c8e	\\x00800003b9cabcb6c844d403c7ad873c7d7dfb5fa662ba19f5bfd6b937ae05279a86f366ac46d4a889db4b506ab3715bc84b8d774f125727cdac648f849140b4ecd9234cdc9b7429fdc5dc5b61054e3a0585fa3a3383ac0533da076239abda741fb0949f0a06c794b2dcc320bb953e181662bebf9bdb1a9e5136602b1b0f77de512a2659010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x242b390927b67da8bc1071b44676bb0cdb1e66a9fc0389dc32e10d78ab420916a99907732d53b072273448ca60b618d8913ce1a34e29e55fe1d8d9826fef1300	1634138706000000	1634743506000000	1697815506000000	1792423506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x911a77543d2a21af71be008fa1d9bb53a3a843fab5b0a4ca9864d2af11cc35246641a232598384928ee70cdd44a01d88e4e3e5d262bec091ef51a5f1d9a70a72	\\x00800003c29edc76b1523afb7f9eea7746955a89f879610170613b79b47e9fcc4e8e63e874767bd60d6a8d34ff991598df4e0665ba18316213d555bd634b8e158f9876c392ac63aba5386f23c2ed6ebe2b87d7f708ef7d2f98282e6c22fd120eb1dd8219f0271455539803454440d4c04cc1977c99e7e86cb07c12af42e801054085a4e5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5996cc2b2065b687de96457e2745d1e13454399909bdfd8f154ad6f2d82be1eeb242642d233a52a6c19fd51b84e839ae29034b51e39eb0bbc876899787aa900c	1629907206000000	1630512006000000	1693584006000000	1788192006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x95965ca4cecf9c438863d2a29f4c7913afdfff7fe1fc75503b52467e244d7be9d3ad6097a1f45cd5253c1344d1e9711ef4e2c757455b3ab8d9b74b9a8da7981f	\\x00800003dc569588e27198d3cb8ed2f0a7dec2e6bc23f162b0ab882645a5659e48bb1ee99e715285716e307b59b23e9583df3905fce0b5d95157ff00c3351e3153304db27bd3d4851d8d8962e0c3e72fa04f7b111d944632a519f8a75800d77018e94c60549876b0dc5fc1fa4753a280f9f3a3489c5e9e8a29150ef0823012a38de5770d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8ecb78438e6e84f276396b4bd92f135848cf45ca3baa41acc35a79fcf8dc2a8c403dee86a74956e781726430c65cc15765a881388253c4c024510ecbe50d4405	1616003706000000	1616608506000000	1679680506000000	1774288506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c56dce894610397c044f6d4a75ea2041372bda1b1d50c8b7e25327759f3af0773f48e614051075a5c6e0d311073f7614893122dddc9e5c55e094ec0911b924b	\\x00800003d2e147e2cfa2077e36a6a668fbb87eb3ed9662c480005586a0db0730adf542c808066b2f2d807de49aa6d5fb0f32653b11f8886ad544fe90fc3a17d255228c70cab6a758a9d93afa813d129b59153d3ff06a642c92b53a2a6ceea407b7254501b92ae2f1ddcaad5f6fde63deb0f53d20420c8b1291863553cc2ee00700d088b3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2f078940d721d7b71ae1b0c80d6848aa6bee45f0c5d44182619ab5c766f323dc78a02d855d75aa04fa387ae54e1f35a3a2db3b1907c6ccdf77364e9ff9949c0d	1608749706000000	1609354506000000	1672426506000000	1767034506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x00800003ba7be199d0d8ae25925c5204df35b2fc53558c97a8631aeb80813b3ee7b5fe1c7a55e3755b4b7c2cae859757ab4370fece84e700d0d4b3dca0383e62783e5a77a850966958747412b93228a36897f60dba5ac2ecb3a093b7f03a2f78b92c9c3570f9eeb06b6efa0ed6ec25cdf9cee8895dc297fc5a77bc498af800225d0965d9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd11415a6d6f65f63ffc4322d172a6aa32a160ed04e0130cad5f16133a7ef2d285a57ae7e190eb553e73b232914f8b7590cc160cfe3794e407e56db6f0acca70d	1608145206000000	1608750006000000	1671822006000000	1766430006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9e2eaf782877357b7d6cbe54b41c89357de6cd37ea8ea47f26b3431757e0a6bb1d597af946d844dc5433e8ae86c2f64eb5801bd5e5c8e9bbaf2f219f3a2ac0c4	\\x00800003d62e6c4e854f6a46a59d9eb4bc5ab064dcb4aabc75048fa898b366e88dfe91ac99ffd5f533b69017e993e131569618fb38dc2fd43e5ab1e9c1461682015f4f86a4371a69d4a3b1e88dab205ab5942c25a2c120eb3f3f943a285c88d0240aa2747cc10f73721cce2977a3e7af2b7709e0cf3e387e83b70252186f65bc5b2e2277010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x81b9a0e097c20bce5e42d8cd2767934dc7cb0f3e3eb0b60e1e183be0bb391e85dcc768e2e5a9985048d9269786f8c09668fc45920ee995e873c3e0f3c698ba08	1638370206000000	1638975006000000	1702047006000000	1796655006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9fe299600a3c0e46241bc7887bd3c897db177ec6d5ea5e187a54b2217071c514550ca75d6d19cb6e61134349c0dd253898b5be8921e7a26fa74d313232e9b3a6	\\x00800003abef47edb37bbe71e27fa408e4778d86130c93bf7ce15f55b608e5ccabc41b6d9b84ed8e78afed4f7b723d20ec05241d56863841f3b905761ab0745c00be552381e9e14d76f958470526802c7d98d32bde8b0d5defbabdbd4b984d3596be3202d7a5b27fd624c7c87ab45deea5f70ac3c07390ed12edef3195185930448c836f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf7b5a3de05c4d5d9186f03918f4da67ae70a6d34cfdb5a97d1ad3a36f99bde09d80bad8bbb5d3564ce8277f5acdf7ccdc793f2843ff112ebbc5312922472dd08	1634743206000000	1635348006000000	1698420006000000	1793028006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa11a38780d433491de2df8eeb073894ed953b886ac6ec52a4a8c072a846b31de9aec84f27f6b6c40a0b62982fa51bb67cd2598b9b25ba36cb39842aaf831eaf2	\\x00800003982148b27b9a32a3b4f92ef0f369b4b8047748a417f6e0e0c43835cc7ee314776b3e2d5eead3108f8c94a359b4923257903e728f5aff4e37a1d5cff00bb61c75f754d7469ae744693cc41b97a46348e69884c9fa57788b03a1686fc442e34f39847e81ce5d9927d0d574f4d335912cc7b6cbc6b64e6d8fcc243416aa7dbf9ae7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x26d169f7f30242ba638757d986604461dcd8ce59885682a27adbc000f08397f0a49e44979746a08a1be8d4686213bd2e5eddb28e9add1becf59051d2b106500d	1635952206000000	1636557006000000	1699629006000000	1794237006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa15e7869c4e86ae25f617e9b35126f970c62bd2c4485ba42eeb70d6f00e3b8bfd09c84182471606dfc5d54074b0990bf455f8d971a80fa87ecdc2ec938d2ca99	\\x00800003aaf5934a750d9a1f5e6b5548dd890fdeea4922e2099b4f3650ba74871f694bac278c80998af86b04bee26dfa1b3be9ccf92b6d1b7eb7b0119cddc73fa102f1a6c5be2911520ee8cac837765ce7de55562a20f7f425e5d070c9dffd5b5ced908b0f969bed6399d4618b326d2de98457dd9944c51e1b2cfbb936928a429ac8d773010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfdfb02f5528efe530f230fef14f029d8677bf6e1ad29ccf4d0290b63c4e39ff325c1d405b65c7aed9a5e822940e8f02019c181351c73d99f2dd9048c7391fb0c	1614190206000000	1614795006000000	1677867006000000	1772475006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa2aaf71aea4bc4954416e10a38ed21570123c919fd45c5e5d8239c60ddea31d6ab03c24bbff9d2e097bd60ebb5d446a745694b0542b0a7a7f1b1f09bb5529be6	\\x00800003bf3e33202086886a0c869e6d6ea3e765efb283faa2411c3cebbb2dbeabd236cfb8a4bf55d03151a20646617e659d9ab8128639db9b40cb703cd445fe0461941af8a65946ef7ae04788da265b2d65f99d8838a841bcdbbde041f1a56a4bccd64f61975d888df6eaba136dc2ab4ab74add06a05e3401c8fe00098c794b0d7f2083010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xeda3acde1859c781468926748f684962e1f5cce0b6b2df0d4d64149096cd2e7584891c5727956e95d11cc40ba02e90630734e9fc237cfd079220a0208ca62003	1637161206000000	1637766006000000	1700838006000000	1795446006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa432e3dccd846c68445dbe2ea57bb430b9408a8ce1661b2c75015a5d10e64542e73d85187a77595bfff10732fb5d940773705f16faa75ec9fc0b88f7f219a6cc	\\x00800003c60fea917d2cf851686d6fae556da4889422eb9060f7be1311dc767a91487818db1e9c8f43df47c0d1cbb77140fe77db1d9ecfa4ae5e724ffb6cc4efbc31b93ac8434c23fac6496807f5a27be257217dd2ae1c99a0c8a1e741022ef916a4e7cc4a8a3df63acdb3ffd289620de40cfea004c7c091eb95c92cb09f2cf6a9415221010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb384d332a336c4cead05c37a81fa15c61f2e52b81467885633fd03cf62d0ac4c8fb13ed95cb3fd7441a7917a7d9fca0b24ed81746d4fc2de651d456d3cec710d	1623257706000000	1623862506000000	1686934506000000	1781542506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa82a477d94524f4a2189a4d2d51e54b7f39c97fb352f56dfc0d164df32fa71ff8920ea32043b98df002f3b9048b7987799b7098baaa1bd0d7659fb83c874ee53	\\x00800003a90443cb1d0d820c97ccb3781dda53ee2d5a9bc1857cf9a083442845f4a563abb7a30e0aa95274eb5d2c82ece88726b43cc8f6439ba5639488c07aae7f37c19efd2a5cfa106ca481384de02f28f25a90f492840292e52a3b02740ee7d7aa21d3ff822f4e0f57c54262857079d727aa00ad7d055d1dcfbbc40e1fcf121f8023d9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3f09e861c913c73daa85dd9d94b8a76d720a7dccb642a230c7b6df657e3c10380d817877040eb7f6ac5e323ad556037da2527db9ea8cd56af5ee71c8d9a0bc0d	1632929706000000	1633534506000000	1696606506000000	1791214506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaaaa954545d502abc3d15e3c3ad9258d544a7c84bd7ea112738857d978fee8e995046c21acea9a8751030763d0d51177936272c013d8133ddca86f08d7ecf752	\\x00800003dbc6210f63102c7664757972bd03b1378f14e58959f622fef8d2eab83846f2532667fb4f552bb62cc50926adb600b4bf9cdd3beeba9a407c5d95aee114cdb2774dff98236a49d3b29b216d1c0f6ea46997ccc0b6d12cc52af97ecc40826b27c0d80ff8f828ac85970f4a4d11aa8054216ad26e6cdcba8b5c3075db9c1a81374f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa6afc92dcab3c8ff87119d1bffbfbcc323bc4869cedf9e8db84fb5e5d11356e7aa07b25bfc72529a17d12baecea00a8631489fc0ef9743b39c4ccb645864c503	1624466706000000	1625071506000000	1688143506000000	1782751506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb1e69cee4b0c8dedb93e1113b59fc641d1f6501003574a93b18fd4ce1b54adf55ffd9a28d7aeefbdf1876422d3dc2fe8c5e3a01c295444bb61673901833f4ca9	\\x00800003d2c578613b5b8376b5a6eb9151cb1e14513395a1d350580c1791aa72d7afd31607b9010db4100aadfb4755bb54e92838e5bd26d5885d4ad9a9cfa8ad6e4901d0201558efa7c7e21a74ef69d6326db3c56478b1a03812a1ffa762bf8a403581054eb04f55a65d0e8314f6181a2f1a4a9438eecbc7344792178046f257f9e1c439010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe0e75b3d5ffbfb78560deb023bfa8508423d12704220de2453bf1eff6d8305ffa1dc60cb325aafcbffa3262bf012b5136c3b7a015fe01c73d28b99b491add709	1635952206000000	1636557006000000	1699629006000000	1794237006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8b6862e3d926250aca992885178cbf6a8e6e50bf797e558306636ac418362c99b17d735a2e743154db16cbb5c97aa901b4325dae457768ed7d501b4b9a53ae0	\\x00800003972d047c3370fb1887389dfac9da977889b21d31cb073744466c55fb44f7d2dae39eeb2f5ab7ec46629b7308ac31dfca1ac2b94cd90b2e246fb1231d7cee1732b6261e1b1488a04e7efdf76a4f0a89d9ae1ddf7cedc4abd1cf72793c2d7a2672be8f5ab8e92ade6aa6397552e60db951ab93f5870ae0f1751a2a38a8b05a1c51010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfa6d5993eaf42d68e25bdd142dcbecc1e6e84ea971612efe859fbd68c3336e35e30a30e56c4e5abd222e79e39da16e817c9264c672947ae093ead5478bcbe207	1619630706000000	1620235506000000	1683307506000000	1777915506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb8a6295cb34cd9891408c75f8f075e00009d3de305537d6848b449579eebe07f14a06f6121391ed9103c400bff3d1b17dfc8463fcabde70a539a585c8f3e1bd5	\\x00800003f164e524a2826bc95399df61a5f480a75458b0b9cd6650247b9dd16032aaac691589b2dbe0245559a49c44a47e6dd53fa60e3dee6a9184eb1af0e16dca97edc21c68a9bd276347dfc67f5ae1d8610e14d78301ef731e41e91a5e91f78227170d04bd77b3160223a9cdca262aa47283b42351d52cb7591ff36eef16ebbbbfe83b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x803c5086227072635b463d89970ff91c5ec17bf2fa191d2f049bd99e5a06c849cd0ac8f75eb41f20a82a6e656964689064654b2a635c92938c231926ecbaa40e	1622653206000000	1623258006000000	1686330006000000	1780938006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9be6c5a626bb9508a1b43623eac43698f86378b57ce3035b5df522925bf826c2c1172d0427bac0a1ad6daef2fe9026ff45dad83846cbdcf4b0fc4cbec5191c6	\\x00800003ad287fe71bc3b7a5bcbdc4002851a7a75a65c9f51d6f07c1c618d8bf56c064af6b87972d2bbb15679f103a39a0c24ffe883fff9285e76c2695af6058541698a76232f178e89fe64689ef6a7037dd3851e3a9e6b4962a48d1b510c436900082ee45188579cbb9f31fcfdabe47f08ac5979741c6d6a91933065a04f63d84d5b51d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe2b2335ad5484daf074ea07696b469ee88cfc2fe3fbbf4aabdb75303d72050825bae2ac8d20dd8ca8a992a72a8b442da20e0bec92cdf9389ab2cca3b402b7005	1612981206000000	1613586006000000	1676658006000000	1771266006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbb5236f53b8a94081f2339e07e1cd52f5f7d8f1f0878a7d914732aadb2510df748ad24061c14178f56cec11d64c0a69b16b0bb9dd2598591a61b4c9e9d5d9856	\\x00800003dbf7475fb802d4676c6f1f30778a99d28b603f3a5740ab1c1fd8784a11d2129a4c41c45812eadc1f7ef6f41ea99c94120be17bf4a0633539c7de068e2052b83ff3e0841504bd594e1a80f2a9739b655677ca7477c8d7a1ba3ad3ac766bf464d83f5689b4ed45a4cb7043028ba76960653fbacf298fc0464fd5b620995d810305010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9f10400118045627b5aacd59bd775d555374d7bf725881ec8a8d6ecf169acc6ff4fc49462077c88d6fca1623d2b0eb7fa3de65a6954ec68523f6d7d967a77808	1634138706000000	1634743506000000	1697815506000000	1792423506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbb7e2502c924b26056c5d341f8c387e45bb43860266e0ec83113d567877099f14d5d6b6a93cf6d9e2231f2b4f7ef15989f872ac8f65e70ac2d2703d6eff143d9	\\x00800003df4808348329ff10aa70ddec35b9dcd2481eb8dd80d449ec530fa933fc39cab7f1087b4fe9d252d50199244a9a036bd2260031e8381504dd4f0362d19cb0a1302648a225f42d1cad1d362c4fbd1a452d8262450f4abeb049b1778ade5dadf1f11e6a72f98427b5e11e4779a31d1dd99f15121a19016387f6e7462c8493243729010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc963de6f9daefe03256138f0f98ca0806cee36ddeb47c18eb3bb5053c241d4a26e99a16e8ab0b044373a545bdd12b66347745a3eff3340d28375b83743191d07	1631720706000000	1632325506000000	1695397506000000	1790005506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc152f5c38c362efa58ec8e6deba30c727d53406417688b8e0b328cf70aef4f528730b55b36c8d1e945dee79bac17a9f6f35f7a31dd121bc415c2e6918a26d9fa	\\x00800003bd477f3abf2599d6af0fff7ec475c7b77381dae9121c00439211c49a3e090457123f3eca6f9bdf23db0bfacd1ba68b66f1fbb2150a2104dc9831f6d99984c5284b9e6285683bd60bff74e73cbb5ef42f826634aa416b9e6b5db1395b8c34cbb95c505c29cc5d43e93922210223ffb4dcb43b21cf8fb64292ef2081108867a099010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2868e1e9a75565aa037accdb86c4fe15f8f7b8864dcd594ae1d89c13ea01f5fcd90272cbeba2a7e24c637291e42bc3720bd25b4e6c338a4954774c5cb5ef1b09	1639579206000000	1640184006000000	1703256006000000	1797864006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc35ed20e6a28f49b62af734598aba6d9abd34910bba3358c1b5108903254deb9096963fea7691f7baf46b675e60c4eceb319bfeaa5b559b72476bc995c48f523	\\x00800003a4be30efefbb5bd2f7ec14924014ea9c48bc470e605484d9afb5c8c55e455b7f73ec54d7d52a259a991108fa9843880eca41feaf86a0acadb44b3040c8dd7d82dca8e44a0bb3b47210e5f59562022c2748cc6209d3491814cd44aa925c30ef00040e4094db7fa95692845ae9512075f4dd8e761360ad38e2f32da41baade60eb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2350f005ca7ecf9134237326fba74406c043fd98a064191f1dccda154f33cd13b825205667ebfdee27723cc09953190cfae8e078597b0460898fdb9e3ae0de04	1625071206000000	1625676006000000	1688748006000000	1783356006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc46e52dfff4f6b856d75d75b50fdfeee962ff12f8e32958169aee295419da059218d5ae6272dd71160c008abaaadf8c1829a0de726363d037e5ec098d2fea596	\\x00800003acf4e3d7d567fd6886f2d1d150d4ee2a4e088f952406614815040cec92976c0199bb8679a32fd06adc1c11eff3ba3a7cd61fb907718b45d8d195c86200e91ebe14e65400d3e22999e8b7a0b7d3d5958000bf40481cb6c65d9fe0182708f6651251af775df02e24f1465e02ac2b8a142b8bda7ec1f6dbe0b46b282cf297f9b92b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x117090554b0feeb5bc785fc1b5d2806bbfd79e92d22c283fe87b3774337f31ed37671f7c4b0885e1b4d5c0d500c28bd46c110f48f332534199be85abd8ac7805	1625071206000000	1625676006000000	1688748006000000	1783356006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc5b609392140f7938b537c21f5b40fef698e9a261bb82c596eae0cfc6aa052d60ad674db949e0cec37eb216f7d850bce67152d96fbf61f89ec775bf7d620227a	\\x00800003c02e49d4cefcd1d5ef7cd2898a3ce28dec113898a79372c16b713db1330ddff13dce8c24f09a90466bd7717fb6509ebbb9f611087146288491c352149e9088426356376fede951e432308a5e536133f76e45ffc38da473a39ce872724dfcea5e3bc4c45060c1da8fb7fb65364c1a0dd6f51264091ff7e0430b3923102844a7f9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x16787b76555e6467ee3ab0adda0ab5ba33bcd2fd030f3e202c4bd1f7fe424a704b5cd835a7a4a18ddc89d214d9d7c4aa7538878554da638f16df02d1fd5ea505	1631116206000000	1631721006000000	1694793006000000	1789401006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc6362a5cfcd3f0bc338c7f91f3fe88d8e781df982d84144c25a79d7f72ea7f142c3aecdcfeb1af0abb140d2d7022718931f44e97de3382e2eef04967f21089cc	\\x00800003bf5e773984333ba552414d9c4104f469c3da2e6c3535634fe34955a544de3e20e0d583aed6d71d29f8746f39a50351dd435ccc4cc0c448f3aefa37887ffd6c338696783d2f22563a5105e4caf8b4b5b8c299159ccb5907c08c5d910f6d1e6fd0448e20c52cbac3279f80c35fc950a979d5ac49cc2607bd29213b99a93502254f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1f60272f01e29c701793a39e36e5e51d80da561c8c647782b112bea8a4fe66523c6fe3502a7f8ce3bef554afc7802df2b8c988a283a9a41c81916cb360c30308	1630511706000000	1631116506000000	1694188506000000	1788796506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc86288729a9b7e1132454ff7cc088b4fca48d719b1043eaf9b207dee9dcaeed6379bef08f763a5de0f99bd71b27aade35493c3d962de0673928c70a2b2187dcf	\\x00800003c5a96c5021f512d7bdde914758a781b04aa4e4f3b3d36a0dd964dec54246a35b56ad4d43693f9898747fd7bc33fc4be448dbce22566d5e25a4c7194da597d159549410e27b721d74ce3933a3c1dddb1135dbe52414a2ad618e05bc20b29c893ad126247e8d73f03e174c5206be12c4e47c06fa3249875ce7f68465973afef3e1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xda207d0ccfaa31d89dc130ba7438482c6ad320afbc2ed39221ab3550c7d31b484bfab9531394ae32a5c537e55170c3bafb4753fe55e4136046e8e1e63ea7df01	1629907206000000	1630512006000000	1693584006000000	1788192006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc9aacde50ce0c9957dec82d430392c070d3e2c2d2f18f4764a95c6072a53dd0c4f7b67a33b8a7703af4c4799a5dd54e7208474f7c7f81b9bf80dd85f2ef50f3f	\\x00800003dc990c3d00c20f7e7d6595e84cbcd425dbec3462122f13f57a69d14a63dec04df05c6e644caaf3e9ad42b796e9dd8f31bb7e1a33aaa399d6dcf0ed256133f08710fc0f3b4d7e783accef89ee6dd8814044f3ca81f9d416d83ccf5eb69c614e6b64c3993d9c884682a75415609eaac8a9fddbd11159a068cdee5db40359db8483010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x30fb054e6be7bd83e2f24131ffe7fab928ec156a037ce70c58a103354a30c072fb76164e0bf4be1c680c0b24464bfb53852dc0d245dfb95036a85de08867880b	1622048706000000	1622653506000000	1685725506000000	1780333506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xca466974baff44a0d5e478f4923ef2eef5f06a5f417d204289c770161a13cdb2063db9de168dcaa10c256d46c394ac515064f8ba8f5f9f75ab00708cec7a60a8	\\x00800003d416e22582c8868c327a7102c300d76946b9d4c08e825430b2f674b6746db96421327e6468e6c3db99f7a7fd1ea885c8ecc9c09d60256592d60ead6cb2bfda97809de0fbcd4a9da052d256a626c67878302f1363b3256617ab41b6b6d41a841f9f4d04c7e36138dba6bb983bffc6fdb71a1f7ba65766bf95084b0b937eba9eb9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe782eefb56e487b468ee9c09f939d28fde2280ccb00a1f72be7b4ab73a8cd0571dc0857284172931128e936a94f5e9cf6c2cf5007bb8aec244284275b07a6201	1619026206000000	1619631006000000	1682703006000000	1777311006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcd2e43c38009ee2fbfe6cc7be5f71e4412ffaebd209013e62fc7978588cea593eb98ba6943876510bd81e324abb880f4830b7eda18ae3e10329760657079fd2b	\\x00800003d509267f2ade9041c42e1531b43df3b74cbeeadb15a5578801e37b5d5a68b4887744a0ca22d8e3290e700133cc1b166409f0bb5f5a43e9ecdd3d16bf4fa185443d106f46e855129a3ee5335c0fd1a4652a3162c44d39a83c9383ff1daaf4db60b49449a2cc7edd505e90d38089184e7affdd2acb32d2c3aa81c7cd8324b58631010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe5e0afa78d29fb3c353ec8e81d4ef555f1a6959b7a1c21923305aead5ea9c60b08e9111ec18188b4ce37c4e386db553af759a270ec6da3cfc6fe11443c25c002	1615399206000000	1616004006000000	1679076006000000	1773684006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xceae8d90305ddc12c679753111ef974c210dbf9b5e82fda5fe228773f36c27f326191b7b2fe1ae60a17eab278ef0017dce7270ff027a04012561b91bc5f5533a	\\x00800003d2abbc654016d7a283bf03d604207da1de08e699e0997a780c63f6583d4221fd8fe10381d238ef8a20d950d33cdbedbdd0b9a46a027a3b1517086bf083b617d5e37950759109e3551fe024a156960108f3cf6da12d225d944cb384838473faa1ef933211646a1fcf02194e0fe6f88a67c0c7c7c6d53edbbe55a9a65555f45787010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8c8577fe69ba60abab8d85c0e7581dd62919ea06fa008945109a6f8250cdef17acb87d578b38f89d54753e4ffd6abb4d7738634719bd80172191388368c5830d	1624466706000000	1625071506000000	1688143506000000	1782751506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd14e2ca2ec2932e728e29152ef19a82de7ffd84936013b549874177f848ea415f79925563640291b8e60a5b0fae34f380a32f7bb52d7af84fde7752605771a70	\\x00800003eef75457ea2a4a4ba725e9de9fa10e0ee31e4b1bc3b35061e4d79ff9d20bd238d8884df2667ac2d847387add35c57c3cc1823833d07ca050eaf4f3becfeba43efcbdf9ab87a793416e41613cb2ba9658ebcd5c3a1543fbc4902eb7dcb8672b2cefa60522dba79882d4992bd0e4aba69df7b68fc1f4454f82dd2802416d7e57af010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x268f7267b05af23bac326efb341b9dd3b17ea3f7b628f364fb95aeb81c3b2497b4c45de33d492e1e9203c479540a07a61355ebff1f941f160dda84fd349abc0f	1638974706000000	1639579506000000	1702651506000000	1797259506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1a247fd39aad89469aa477f9accca053cd96d6eecda8bb158a4df43f34e3b24eea5c0d357ed1b49b52f79f95a217818339e9d89d5a6ef0ebc67eaa4aba17f1f	\\x00800003ccf4dbb79df063738173b94fa362644044dbced1807b7044b29a42881fb602dc192a1340c5465604bc02297f4c63dbfc043f28e3b4a2da213b14d984c02a60793ab2e8a407f65cd4076a28fc8172b429a8e2182da25ec4cf9fa4c2b511436935d95d6111975a630cb176d12b238119989a334cc4e06920f54136219c459dc627010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfc882e574390ab545c578f1249043f782b7c514eb5bdab587ed40221e1c9a2599f8fcae304bb31884d187b6e4c636e373c3fea3af1829e856a121f267ec23303	1622048706000000	1622653506000000	1685725506000000	1780333506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd35a3cb4fd74b75092d64e60b0a9b794ff167230ac1ca4461cb3172f5ccc49b8e5e745af5996a91f2a66d44fbf154f1a384c8cf14d303e4f9e767dece1f634bc	\\x00800003afe2dbffeffad8a6708dea9aebf6607b143ad06e2c2372a42e8c90a6ec8de2d70a8adac59e60815749ad1c541628ac287759ac0032629bd7c837aa0fc1071b6fdd3e8057f7427a44866813f4e5ab66cc4637f900aaaa40d91fa96d08584d423f314bf7a7a9f5846e8c0f94f1641e4c52bbcfa4adbe0fb20fb1d124c15b9b0afb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x341aa4286db3a171ced8eb8493e6740386b31c93402342451036509d7907a1580d25d8d5ae9ede9fce1240403d3d6996e9f6c8860220779cecf297ab16a08b0e	1625071206000000	1625676006000000	1688748006000000	1783356006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5eec773b08b2f9540aa70bcc8a9c58336e3f295e373e5832d995d054d2598dc6e09b58c4794e2ce5f08b4f2d6461125bf2fb0dbed72510ea772daf31f0116d9	\\x00800003b6fdce0a3fd81a28befdbb196a43fc614a52765d5add8d3bc6e279c7611b412dbeba52788ead421bde6698b6d3c8e88a041fd7ee40cfd0c669ac7cd2513d0e12c6b8fa49b3e037099c8775fc846668701e7c71f911406bccb75fff1f1a39c17ccc58bb945b5619c241dbbf8edeac2e0265e5b03c2e81054e9b3d336dc6959dd1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x68d336bb59c5f532b06858d81df1bf6eeeb09722088402981cfab12706f6bf29e57cb166188c39ed03f674eea0cea9674c59efc03ac5bc8f34833821ad050f05	1631720706000000	1632325506000000	1695397506000000	1790005506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd90aea12db5ad138e19421c757cb847c792b931014057a8b887293bcc574189a9e3342a13af03f4b67c26e7883e65ed65c662326fbaef924552822db0bc743bf	\\x00800003b26047533a7882c18fbf68f101dff54dfd01ff007266163d47b6237ab0b2518b501312567336e94eebdf1f39e95101fbe4741dc8a98bf6df9b3297ebfa028b2308de5c95d86ffbef1674eb843e5c643bcad4ef2a8c445ffe59e7cd7472592f3aebce279e91549383586d94be9ee5823ba05f70d5595623061fb3950b3e7e435f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0d1a65195b9ab80e1b9779bb6e2bc871900daff15f95d7bbd7370e1f9e1323a848f64db2a75a2b7de7581e2cbb1d3bb426aba2e4b035c4eaa86fa72bde37870d	1610563206000000	1611168006000000	1674240006000000	1768848006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdd4aaa250093392410d19dea71ccd09540e038e43714ebf546af1ef04d18996b4e8432e0366f42907be296ff3914a0223cc06e7704e8a35d22e93e0b9dfd3b75	\\x00800003b393c58fa7348b78c7358a209646f79b426a46a95d65e26366cd9cbc571b0b81306e15e6ed8532d4fcf29253bdb5d0f62c747cf8aa36ce691903bca675a509fee0ca155eb6b6951c87a8c4c32b279143b0c8315dd6dfdd90e3eccdc3d157a63351a549d3267eefb1d197a417639281d7b382e37c98e7ccabe87929fc06d982eb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x80461183c241ad9e97c5150e283cf168b28872438893d1cbf51870badb5c65830bd44c3a334be3f999efb5a636a6fc96435c9fea7b38158e30631a8bb70e6c08	1627489206000000	1628094006000000	1691166006000000	1785774006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddba62fa08bf15678af364280bb01f67f95d8445432cd13c23caf163862345412e3ed8eaad6105e1e9c8ab390fa591e0633c3dcddbb329d417e5fc2cf30df050	\\x00800003d7fa133516f18646464db3ea5a89061b6d5f8fd198661dc1f8f7d955899865a8bec68607279331900a5ba951229b5cf3c7736b6cfc33a811287018194900cc2af8b7679fc07a5863903aa41d9a44de986eab91e16a1b60d21dc9c571508030d4deb0dd1a41db7a5f1e63301801825fe7b4fc3fc360694f72e9ccf70365a6bbad010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb71ee0aa9fb5a6aab11f083ff6bb058147cc205a9a995433081a4987f7c40787495002654c7ec6a268fd18618c8d9961aa58c8c15077e468d6db5caeab116b02	1617212706000000	1617817506000000	1680889506000000	1775497506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddce7a70033e1366bfe1049444a0702a1f343451fbe73bf6596ab9105e69e670931978425080a8e40b18181a8c2fe281e7cf915e907358ab898c2e4499940997	\\x00800003cde5af26de81279f4a6e9c50ab797a840fc79a4610f4bbbe39a934e18be075f1f8322643fdb79afbee08bb0b65dd3dc752ba083d425d41ae4d0048ea2a76da8f25d354c78733142bb35a10345c9b1fdbd2ca5e4c181abadf9de20369778e19716d9c8ca9fd8d2b101b2014526e36538692afe8c26d1da65b94bc7ec347e6210f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x62745feb678f7343981f042de6a2b78a3722194ccad6a0fc14dc9f1bcd02a406784a88563917b9587636640a6f1d03d160519abbee63e48ad3f06e25f33fce0b	1629302706000000	1629907506000000	1692979506000000	1787587506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3b6f8e7ade7eab159a954014e05e2872ba95a5d91ca4af8ed931aceefbdd027f46b2a9357ab005cd8beed4f4295a97f193701ecf63fa79cc00a60d41c31ecb8	\\x00800003c8e520b46d3f4aab55d3e1d6c642a814a7dc2c82b054b3735c78a7e41835644aa922450460c64ab87532363db7de6f8988e7f9646a923d30e68d55b85ee40bf78fa30fd202c413858cf89e7e208842922aee79c2204d5f02e10306334892117dc3f3d053ce789326e16016307081f94b94c8673f67176549071b89f739710bcf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x39476804c7e6375e2f264fc79ea7a0f61ae8d8ae712ea478300ac89bb6c7839384c1e2398bfbf10a392b3407c8875c27d7c03f58281a1462b908376041376f02	1629907206000000	1630512006000000	1693584006000000	1788192006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xeaf642893bf68a989db8c82afd40fdc926427ccd9757f283ad108ab1691d0006aa29ab85d86a1a4466dbab9c77ef7512a5691e6528d71bb30109c2d703981bfb	\\x00800003b3a6999f7de1ebcf9ef04b3f5cb67ea7f0d1f81fd191853ca9235bfa7df8c43d6345e83c026655e4183ed7f6a93897c571a434ed0df8ae6cc2a93a98ea98c96b91231d687c2723be4ef1a4871ab0bf4e8ec6a0f4a68dd98ac29f590d5eabe4f8da9a081db9cc3463bb3b8a73c2e32b98fe50006ab6725fc00b2674cd00440055010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x161a617255f70e0575eecb4c9c3ea1149dd0ffe20a9264b8add944b80fc394a9e758a48a68357890629433feaae6cb8b1b03d6d36bad3eda94c23092a5514a0e	1620235206000000	1620840006000000	1683912006000000	1778520006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xed562b88b17f24abb9567894467ba0b0744574f652892e957da20e9790236a9fcd1418d8c5a883ef1c01e2f696c2ff5518e34d23ba4f86e90706045bc155a064	\\x00800003a2390a40d7cb06cef2325cf8949f74136693133abb67bcc08a2d142dd88c23f35d2eaefff47e77d5a7294247a62d8d00cc7da6ff968015352bfd5043417c6112ec3821194c14f9c3d215fdbfe7bdb0e8bc0b849ebf7734aace3854f0ed020fd1fbd6b6004f07cc7c6edef47b44d6eba918a70788e9ffa79de4496501704fe7dd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x81cb99f80c99b3d158c8b8c4a40fd2f649bfdcda848c52d1dff925fb993b935fce7a3bf67585fddd50a3bb0ddb3b71bf0cb6a11f5c1f6399428daf6b4d9c1300	1612981206000000	1613586006000000	1676658006000000	1771266006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xefce81cbf7f92003248a34986f5e341f8a36e0c1df128d892277361d45134f7b045b8019d15d40133b67479381d0491f9d871dfda4982f381f17fc591c33c898	\\x00800003abbdd41efdb81067d996f988f531fd4aaf2924b3f07ee17354d9646069150060475c72828704657090c70fd52fb21a21724d3763fb5c9a1834f00359a5bf010143fbdeb50687344658b316c397b7ba91f2b246dce3339d9c1a2b28244449a3e26c7dcb3a2847db0ee9a9c49efde6d1ee5b57b6bee7c7efe3cd8b5a269963ee13010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb7fc3a78e6fb119de5fee72f0b24d6ed5429cb7dfac1dc4bfe5a9fb02f9ab68c4aeffb864fd4fa17142689f9fd66e5dc0edb3b8eb406e08ca473f7d437217106	1625675706000000	1626280506000000	1689352506000000	1783960506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef5631aad3ac67afd5aa608a9b7e57baeebe88c1921ea5b30757b350626468f1bba52c1c8f360923f41294ed2d485b6f744cb82601e87591f1b1398a291de4cb	\\x00800003be7dcf5b4039d77b6053ac4b9697cd8c62317b9360ecc01a66f4e04424eb0ac3c7fdc3b6ee94143b5ee364a7ed6ab705177c94b3221939e851188c8c5d3485e9ebe539c541b494fe6de778dc9965acf742249271742f7ed70ba22551e3445ca1cb5813232b528c2b731e8650d919c5ec3ec80b77f959c09709c1216ac48796ab010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5a188dc50f24e5019afd14640e56c8d3eb71fc508689a897ea63f1720d03159dc5495c034ee3b119b6b8a0c7d6f36bc4e8287d4a34e831b3535200c3fdffdf0e	1620235206000000	1620840006000000	1683912006000000	1778520006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf5ce9ba2a23a73bcf46cd706c2cbcbae71263046067bd2650bb4438341edaef49b554b0e26b8ddc72c7dde707b470d7f4b85b4e599cc9242a6a7c0bf25d4aba9	\\x00800003a6a5a65d3e0874fcca52e7f92255054a4bb2c65cdb9ceadd4bdb79177ab30e8b29acf5a74c270bc3a1c47a80e0863d1b248194025e1c92531f22f548c22bd445504272c6a4038ffe2c68a7c0d99b4c9ae3a927018be797382d5b3358f9fd48935321d07b2fd1dafa8971a3df171b495586a9581ba4afd581758bc84147bc23c3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6332da9b0bb99ac1138aa8f9e2956b260f80a85793e733eca2e0720c1bad477231ded811f6136f3c52529b549ded9c8393b9efc2251ce0213e6e938e1b897404	1609354206000000	1609959006000000	1673031006000000	1767639006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf82a58ab9535900b6c647b2634e18b079a02b4772a17f36355816ec109d2d6979d88f8f9817136849c675e578a61d57786bf8b6d93d0c77dc8e3502c597ace3d	\\x00800003cd4d322d4623a5380923d64faafe2e198a7da433256a2ba9bd6b3107c2e7a48ab9ec319315d7856d1dae4656f128b2e19b19eb2eb621eca44eb5834ab0db5ba9a0620dfd389f442e2ae885d7aaaa71100477046556b28237a2f2bb405a15a0297031702a0796920a038b20b819b7f69010a724a35f5cf3821dd8d4b791e0d01f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x367b6aa582e003f0c00957d21264e97ef6d8e74fff36a420c0d1b9f26670effc397143e26b4f36824593afd68f3ec8ebb890f09cb10fc82a62919d175148790b	1609958706000000	1610563506000000	1673635506000000	1768243506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf9923b84918e1837b6a9b1762319d6cb4f5776a81bea10614920c77b339b8b8ff2490b185d25be5c9d0cb17d072572be61e05ad989b8acc00370afce57a67b93	\\x00800003a596f91ad58e6a98b8e86abd5d60fe6e26c5189834ccd7efa1b120057777542e1e57a61878918de99c2acb30612b1e62cdd71f06ff709dfc71a3de83ae3c3fcdfb45b6c1b1ac920798b3970aeed1086494c5ddb4dc2c00d630d498b4a1a1a9f9f718521003f631e5c10694582ede8756ded8394219c2cbcab14b352e43ce39b7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x7ecd3e8866974e85ae9e3e5f3cf506781eba91535932c9482473c0aea99a66908624e5c61dfcf11f489f1ddac60e10f922d839f3be2846c410247b09e1ce7c06	1628698206000000	1629303006000000	1692375006000000	1786983006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb36ebf7280c57e28d2ad2aadbc37c45b0c1f2124320f50ada9ef4c5a8a328854042764a9ab0cf2c7e4097c0ae485c503eb27c505bb084866e79f9f549646cdf	\\x00800003c8e70b6dda69873bfb4b43ece43e13f7d38e9eb48cd5e6e616cb15c7ff3df0368f3120e0a1c9bb5f6c286096f994d6836ee73fd323bd95b0def4296a5b525e9fb834491606da1a175c26f3f1985e05dd886cf0abe7d3f645597a85e760da3af5b179450a78484b60dd9e2f29d132c52e6103c4c15a809593cbcec8e23fd63b9f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2e230df954e17595cab8430ff61c86e5bc3099b7ef092a028f004bc962116ba20adf8e0fb0997beb89616141045b211cb9ae90742f2eb167a7e9e8bdb65b6b04	1631720706000000	1632325506000000	1695397506000000	1790005506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x010fad2bce21dba8bd4198881abfc1a49e552a822e0855b511f7996df5715aa2d7c469c20a8fe37795a9fd97a48341814b8726c4894a9120cabf03caf5b1ca63	\\x00800003a1df7a477a309e170135e774ef6e1e346832205647aae662503237199d53c7441c2937edb2af37e36afede0851fa8de5ce4381ebbe198870eac1ba243e5f5f577249aa508c883bc9107a65379499a56f8f1599022756c212a73dfd1dac3a176b9b3bcd1c10fcebf12246ed066f2f171eb19f8259559b65517c29e632b496ac79010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x590882ef6157ea7006a6beeb997965f3a3578629dd04580f6c4fa316cb9ec5609bda0b82ed9ecd78ed0528e2faab67d44494fc0fbbb80f10ac2f6b77d916a70b	1612376706000000	1612981506000000	1676053506000000	1770661506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01d75f3302be8bd8e122a414e07e3c62421759905285d889a032b1046913fbd460586a3f317ed142a54b0a8b244e2e4dd6d363051b348e1709fa401e0d689777	\\x00800003a480b3257f44b0e601ea4c3448e4d3c6bd3104e3ebb35fa006ebb9f330c92a8e3d733e8cab10cc6f73d0cc49072c3225b899c1177e4f711e7c255bb651ca97803e2e2235ac42d752ec575d27a3eeaf9dd759f6f42e37018fa5643447c906508a82e549ae03f10c2f66ca0087b8a5f2338c067c1961d672788402fbadfe69b4a1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2df590be02ede56076b79ac7cbaeab47150988fc08ec23c41044b81450b80755892504e33578bc5ec5ccf11c0437979cc12dc88349f28389f70dabaafa16770e	1620235206000000	1620840006000000	1683912006000000	1778520006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x04bbd1f4862ff66ea3c981cf4cd618cf1b3db8a0d4b94190e97249dd158843cee87b62a5b5bd5890dd5c7afe55348bc97adb0d6069fe1929e5934213b8f3eaff	\\x00800003a4d708c3ee874d5edb453da7958589c60af98f0f9fc6f55c830f2ffc817a11c86d10746a837124feb86d26ba6440c3a5c0dea75b0d03d5ef1133eed28d981682e2e56105a77f68d9f26fde3f99381c178d7f93611c80982aef0865a63b067c42e3f174fb69f7bdd32495e8e81b1bab56c8a6d80141d00dea5b719b44368c233f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x664936a63bbf85f7fc6fc208f1515a5ccf34c1c7578600e2e316ed71756601dd56017990f737f5fc1b0a549facae4dc7fc41c0148e56c14670754fc8cb02000a	1626280206000000	1626885006000000	1689957006000000	1784565006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x04d764962e2252d31e587031c67a6de3b9b7492825dcc944baabf0b16caf69941ca1163c5a7efdab54a0d5ce2750e23637dcbe9c5089bc7a0ad490a8f6ac0d32	\\x00800003b8aed74e62eabd6e3be73488ca7b79c505ccef9e07a393bdaea49b2b4762c7ecfe138844051a3cd7a4120c544805545af96f3d03a43570f07b9487624168538a7fd59cbcad178f0a04eb7ccd9804c785abf85f040ff4245b53cce55d22d1b21420f87ed8c9f81b30563b94a1a300245651869a8e398c28953d99a39d20a61703010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6ad8230e18b5b19241b5df20a8d3c94bd7d9d504c02ba6f3520f4abc135fb4a727392c8e418064064848140351ff7afb92d7d4e6eebda6f9c6bf048cb8b0b70f	1620235206000000	1620840006000000	1683912006000000	1778520006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x04579c5e123f0bceb4e2cd023712386d282d604c07272c8658e63072e37067d936356de914b19ebb335d534e9ae53135c7d7853970240a3f2585301efd047ed8	\\x008000039f275d68e99d8d515f2d48e8c1456a13b898dc39bf0046c403f9a4bf095ede77bf8ec2a4e577888a7c81bb4199e3d3d47ee2f2b49cbab90fd6f42e223986f289861b0d57202a44d443f52a0b0519d975df62cb49e8f2cfe96c770fbcd9c6fbf35267863d1b649ecbc875925e125801c3c236f92c5c17f9bccc68457d6fcc2159010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2231cf2c54adce02f66697b4bdcfd583e91759e5eaac676071a45a36ffda3d1ab2153c4ed5d478f495d4bff7990bca964173b0a421e0a216baceb1e13568da01	1635952206000000	1636557006000000	1699629006000000	1794237006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x04d3f08dd6919c1c467e20d986701c67aa8eeff5118f241b06ed80e231e57fa07eb57fbc7ab6575f1d26cbcdf5ca7250d7f72a64c2a3b787cf2573e0ebc97b48	\\x00800003d390733d83580a8fb6a982bd5c3a1140c147095b334bb1165c692d96834959f6f3b97a55075d92c4e1d2ef926c7e939d6f4f5503602bda5d2d8797e3cdcb4636d2fa5ee58e2a3333b7b5198df3cbe374eeee60a94c21c3ea4c3b9504bb50e2511dcecd866f863bb916715dbdc56a272145c572a148422618bae2e180ce6762d7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x21547a1fceb0fc79babeb6caf642b180a73845b1f65128dbf11c85a689280dcdef04b08f0b82849fbcdf316f581b04f882054b7c17ba5c617364de5100d5b202	1611772206000000	1612377006000000	1675449006000000	1770057006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x04dba3b490f53f882a20e3a38bf49b49eb129d558db109f62a4bb50519a6a153fadb0ff560f8b2204ebd74ae40925a178e7b9f5851e7deda8ebfb5595c1aef08	\\x00800003c7d1d01458b3c76c68c21694236181e02894bd9c350bdde84cdd7ca08864b100677a155df610cb77e3349994299d217cba2f51d13b7dfb4ee10c2896c3934f661618dd73119e1a55583a46711df6d81d910cc5284ccff7383780b1bd1c690f5df6fbb40970f258e59e98237361f3c7407ffab550689172127f33f854e38ef611010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x58ce14fb516dae91c9590a47b7a38a9a000c72ff82eb12e19d78bd4be11d634f9753da1ab24fae86c0ff345514df5964440d6f2c814d62114107131ff5984204	1626280206000000	1626885006000000	1689957006000000	1784565006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0d477b8859f08daa73ce44be0ae378e67f079ad8fc940d2e9bccc1fea8f92d632a11086fcb26606f0e9c329bb53abc811e8db6f033d1f40f02865ad220a9f841	\\x00800003bddb9abe07d1738e0441136f9be106dbb716bf9eb4f78c0c20c5888e39df53e479ba029128dbfb2418402ac806bd4846e0216ddb85bcdbe8f3a60e32d679868e3e6b1d7323519f8901d27f61e64557b7bd25b0e473416439067ea2eedb5f3ad23011129fc5bbc54100363976bffc5409bb9b5eaa25336560279ad57c26450a8f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3fa1e49d15704b09b27b7c40e3391a5a3d6e7f255cae18a43287a577040f9bf25f1a2f0988029046c302a9689d7845367dbea1bb90ffdaf6b69e150c01e7ce05	1612376706000000	1612981506000000	1676053506000000	1770661506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18d3eab51d69f2a04fdea87055b4b89aa9740cd1b03f0cdd7efbb29d600f58f8df3b23e2d57758cdeb9fc532030778af60a9a663e57557236ddc35d7c04d7440	\\x00800003e4c229fbc910809e252a62a0a65c48af95d929bf1c73f9c725dda456831a2e0cfef0eb5e574e2d935c6e8a5f3de6ffcf95be97156dfe254dbc495d0e5428e0364da49f714003cc16467f0077be022625a23b92a9bc4f37abed71c65f1863c89b9629af36b36bf8a5ddb08800ae8a117e976c045836aa357e14fe43d2c4e29177010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x85198405c4da5165b916928b87ca91c11184f7e6c5f2845e3b3754b430b3a85f156df8ef93dd2d259597f03c7ca522ba713747bedab55575c9a6a8bab3bca60c	1616608206000000	1617213006000000	1680285006000000	1774893006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19631aface037f96d5dfa3dc0e4795a6441b6825ecd2ae04de7a4ab1f7b5bb5bffc1893aefc36bd7bf8e39e8603d107f381004086d3caf22e3df056e0dc35123	\\x008000039d74e68d6f2463692f159e9d3b3bca51824d77f54b5251eadcd888a2c05a30753bac9fc9df85c6b2535d061d29467c86b6ef5f1be40e246f0e01e99099892a7f8ffd89984df5d1e45b9a08458cf9c64c9cb900c14f6c47f5abc13a4bf8fddd34f809a07918651fc72520bebc7c39d71b71f37931b5c1542dbb474a3ecca11977010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8e21bf97b41cafa882fd43b518412d05876af4a0b2bbb74c36b79558b02f50147d02beafa681a12d825f8681d50d34765db506490eeb9c50f3a35ec90448e405	1610563206000000	1611168006000000	1674240006000000	1768848006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1bdbc03ede063e6d7716c384e8315309899a133a84340dbb0f96feeef3d304d39ae7e2ba7e5c43be6d31c7674a658231b97e79cfad19e13cf62aa6763ae0fb0f	\\x008000039cc5378827bbae639800f31910d3b1abd25d71ca265ecaec7194214b25fb38c6f9f7ea4f9f7b7c47c6cbd645348adafda5251613b8ce838a029bfd6333d31a7ffde535f72670245a47e27c565bf5a99384faae5c835edb71930fc6e7e80fe287cb6e1ff152ac9712429356ba080d022e46ffe94810ade20122ef1883b5c0fccd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x7709b2e3b22147e2902dd85260ab8248f729c311296954a02ecb75bfed63dedefc8511292a984819ca2abefa3639111f26bd4386e60e9188c614a40703ffdb01	1621444206000000	1622049006000000	1685121006000000	1779729006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d1f130228203dc290c48cd9d43e68383bc2a2303a028c22ca1cc7ba3cc3e262586d94d7e01f9d674c8dd307dd0a6a6546c7e59fdedc4759a580363641f2e4a9	\\x00800003e19129e2e2c62f432d7f5d380ecdaf26cd9ffc1357ff95d15de44b6b199dc67735eb11dea48187fdaf360c32f7852eb6c82e10f89a3d962a0c3733d5b64c844e981613b38a78eabfd8184cc14b2327c13023be258bdbd772210ad73c2758478a3c608c4824ca4f0d922c54c9c8b6fd31e292d39a67ff0173c2cac4efe3db4ded010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xaddea29aa8d8b2be5c5149ae099f9b9d3edb6c61e90d05b592d538be856462262db0d71c15c577dcfc05c98d2ea19897738633c2462e3f89c2d97fbaf318ca07	1626280206000000	1626885006000000	1689957006000000	1784565006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d27de68b440799aafab802dbd58867549593f32d818c8df2c49741878c9905a0d3f71c72b17e521e121ac17cd1cbc5b8a7d74c77f0907aa2fcf1c4cb192c9c7	\\x00800003b55f7e221f7b27d19da0801074045dd3b78aa25dd86420c622246a360b589795b5268b4d6d2eb217e869e96d7b1e8dc2b984c385a83039c363d42826f22fe0a60b208c75afdc43525149438524acd7bd175dd93988f0415856824df00ba95155bc3d82427371a6e85f15471678254467716ac1b58052556d57299edcb517854b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf85a540e054ad0e5a01e46971c84f33bfdac6fa91acc8342c7f238cd024461e86d2a27a15ca7dc8e029c6e2cbfacef212773599631b0d09015b564db3f79bb07	1637765706000000	1638370506000000	1701442506000000	1796050506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1eaf77bbb13d89c8bec5e87c37011536b2b50a83b6b2ffb1ea9046c3c8e921c618e8d3052cfe060f02c089a486f0f3f9dcdb25e28934003856f8d95947563e19	\\x00800003cf5d6ececb7cbce1370289f9a260f0041281386fcc14da838d8b4cf4d2f7e66f4e36a82f6578e9cdd7f8f2b515717eda395483b0708c4c427c5ed8a786aa197b14022f3dc5091b9fe80338669b7f104100b2bbd48cd68bb4b534afdb8d8202dfe9c64c40b99abbe2d28d74cc5f378a2bd955443f3d93f903c34ec33fb8c068a1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x83c6afcd59831c2acb8606c0034903053ba3aab429a1ca24217dbd07d2f11e825343e564afe3a2346c5d81933321a0546bc39be0e195db6a93192456132a5009	1629302706000000	1629907506000000	1692979506000000	1787587506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1f638a1625c756793eead22d385284ecc825dfb302837e73ca332b76392c052d9a4833b80d5351e31e5be284409930b8343a404e85ae81e986b333d603443613	\\x00800003c360390d70126e8b51cf221d38751a5d1250e4b57a3d79a1c3242fd6b41ddc281886ddde8170382b0577bf3d7fa9e80fa7ecae543cfe08bea8a8cedc142cedfa2417d3e26b2ec74f07899429512386f019588bf912cd961acc38bc517cca82e9399c486cd42f214f8052ec1f9ab25b9efdba72d917d07659c1998151810494b1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xaba0c3d7d7f991620b4795ea113ae46e02ccdd0bab80b91ed305a3ac851aa2c5ed51964022f846ab8249de00cca4be79058b0d27a389217951b73e3fdd83a300	1611167706000000	1611772506000000	1674844506000000	1769452506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x218f1df37c6315385c1532eb939e00cf8c77b397b57bd65be773c6698d568913c52eedaccc54d8a437e62c33bd74abc4a66adc4b9e9237fd44ac1b11d283f7f9	\\x00800003b0e8b03d384086f877f792974a5fe04af66f1654f1c15bcb698f3e5221b8d4c30d2414c49101ee0ab543b86ad8ab71a9fea069da4a5d3ec74723e0895898b33b871f2da76a4361a785637b9b2eb0877e37a236b05a2e2599aa3044e565e67b91903e15669222b96a67ea350cc3268c73885b8369d94ebab37d4245fbb9b45575010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x593278d7923427cd325d309596a6f535a0548a0e58fb74eb4d7451bbcc4ba54ec167cb87eec5194c7dd83831a15b82b569b04915945f7e189749ffe51e6c8c0a	1622653206000000	1623258006000000	1686330006000000	1780938006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2213807439e724166cd2dc80fe1d7dd28669aa9d4007fca246cac68cdb1f800b68b89bd13f004c163f06138e30cac70d5107952a4408978be109f3284afe6dd2	\\x00800003c5c72bb64e68b7d8e9c771d3b585d0d87fa755a3f31dc1fd0c4af9b2631e13447856de080568f93d97d7f3e5f0fd3c3dbcb0244869318e7acb6facedf771ab59f38e9146103dfd2ee39ae1b8a221bb534e32e35bc8b24f2a732c3f8552d6b49c7f26925161b3887b55ca00fc268d66a50fe70802b2a031a21cb85d5d20b62df9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf1092ccb7d8010f153c99ba0eeb966ac08e64c8c79235e3b37554239a44c54075752d4e056dd5d865dbd97c1e5f94c39813d0e92341b2e1b36581037c5a76108	1634743206000000	1635348006000000	1698420006000000	1793028006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x242f5b7dbb8c225e6f28b4117576a3add9f19640496a90423d4bac6e801533a1ff3f9e6b77b0885dcf2591d6475750815706b818cc3947d7f08df9fab372163a	\\x00800003bfe756dc219c5783bade557b077ca2b9f9ad4bc4f2cee8d7c5e437c0f5f02441daa9d903dcd31909e6586ae6f2a56bd58fa05c681076a8006bad8ac2e6b4e6b4a3296cdb7c621d0e49987f0b9816efb3340f68ad993b69a120ea6751958dd965f0c4c79702aeea51d8f5dd0db8d1c03d0a439d974e8dae59d82acea7d8eb5625010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa3b1c66b7bac367ebaa0614747d7bf3f6d732e24c456df181ea2d9b51d8a7c9e12d68fb262670cc39fb8e716188b540cf51820053c5b760e7fb57fdce6688509	1616608206000000	1617213006000000	1680285006000000	1774893006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x24bb402ff946677c5803ab31e02c1202655a8467d98b9aa18baa2f9ca1b124da2da25a6e23bace9a3b5ed0a6892ac4bf2a5c6215c6efe039f9cee19bd0c9e56d	\\x00800003c514b5b27500b76d60108de8e79e477c88a0c609fd9db70fe809bc0d41a6dcb4298aa46e5a796880d6abda9bcc1a87841e598d34a75d00a34b191fcc78e1484bd7f5d4a9005c7886e9136c6298fd40bfd5cff3bc46c0b50ec3e028aa28e68baa44a4e5c2a304a37c2cebb274b20748e3f83053637fdcb21d67d4ccc3becd050f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xbf102ef7d4887627d2aaf14cd1f1bd9cf7949149caccfccdc5e15f1d9ce0bbfbccc73b797fc3cbec24b27afb5f6905cccdc6f65fb4af6cf7ba0c2fff3459720f	1608145206000000	1608750006000000	1671822006000000	1766430006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x24170f4c71adeb3e9e9a5998529df0fc95602adff77ad3b724689c6dd39e79e51f76eb635840ba30107a7a98bf9da7f56bcb78f0259381d837c7648d8370c5ee	\\x00800003d9d554408f5795736354be26580d01e266eb9bf7967bf87a73a7d48270de4fd08456caf679f6a214dba926c6b299f85f314f48374d30494af59a70c79632511b4870e5e26d1644c60917499a3c4ba6035041c3a972ac21f17493a113ecae17a99668b9b627663722a77545b715ff58f4098fd45e4efe6f6c8043eafa931db5eb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x853904bc86e9bb7bdcc999b47ae74b2b450dbc1f3391d56ae6940214b72d6b5c926073bc32adf1b087eb264af7cf04f6ba23668e75a9e0f1dbfadd716b163605	1638370206000000	1638975006000000	1702047006000000	1796655006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2b7b2ef154582031014f6cbbf02e75aeaf2052f454b2efd269505a8b65410a30933271cd4049880ebb1d6a1fc01727ec1fa281444e081ef3cfbebd866a0df8f7	\\x00800003c2103836039a13a9d8459e252b260b8e4c14a18e4f6ca4e2a558a0d0b4fa4f656f7c778db5c4d0e3f79d4efb1be48ffcbfc8865d9043e5ba790a5de9a88f61c1c86ebd606af856dfc238d46af9ab031a1623f77f20729a4f29b6b184e1925536448dd7ca51f7ec1285866ef3351898c025fb5f1e91a14363c4e946062c7632b7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x560a6a8bf0dff4483402dc6583b1dc0ff3699e9bb660581cf2673a300ad9d2f99a0acdeb5e55665a5462bd062519de9af6852feb8abcafaa2ea29a9920049e0d	1613585706000000	1614190506000000	1677262506000000	1771870506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2b8bd58467bc70ed062003ce4d3d23564e5c251afc73f26aeefd4e0f5dea6e802b0bc9807c3e2b3d64eb041bfd55db79aaaf65fe12bba6ef31610add88a69412	\\x00800003a4082cf65a56a6aca9bbdd9990028d2cdd41ce88a3c167b85b42fb87b2098568cfc80ed1830fd7e8c4958199436fddfcbe84830fcad0d7b4faee83e939240011f808523f3ce7566270295ff3610e1b7b08c862cf561a89667edfd324686596bf503ab4df764377d0dc1a7b8eec770d36d67b6fbfb19409b30706805a029d7453010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa817ce127d4b36767ade6d0f83ca64e13835a2db17026c8ca1838bb82aff89d9fa0f0eab67b7a1ce6edf2f53aa79ff034d1165769ac9fc02956384187cf1cb0e	1625071206000000	1625676006000000	1688748006000000	1783356006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x345b4b28457ee55ca8db21a509976a9eac78a6085da424a643f8e58be6cf619b75be15a82c65c4a80ec59742e4e9676e81a86a0df39b941ab129b8a4e52f2aba	\\x00800003dc9a79aa74d4cd9499829d86efb10d025a1a81e9691cc5907a68c90f4be5442f20e0c42665f2d89100473db8b5ebc1e6b819c0f226c4ec6977f90e9c003a8ee177d56c5999913a203f61e10bc2a91b057f20a6b7e6d964300e90778de66aff008f444af8956667cd6608871ce1bcacc1edf4f2a492e5f106314a5f13c633e961010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6b38926b799940e8b216e6329c0f50af763366f90119955f5bdd4180ab128f382ff0b877ee7ece039a1245caf65eca6d2493854b05f6dc0eb5fc21ce3fff1504	1621444206000000	1622049006000000	1685121006000000	1779729006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x386360a222a07537be1b5daa89a7c04d84bd6d0801a4dd607a366b5adaec4f0feb31a9c48cab145eff4536cff498f5d722be05612ae21786dcfbd2566535b102	\\x00800003d18c3f8b4b2226ddbb3c818ad1c36836dd64d4a3a6fe3e8687aee1807019522dd574cfb7229d178b83d6c4c46e2a3a0548686a3c7d6286c52d3a686d5684b7d371dff22ab105a05fe669779a33a92aee2a644ee12dafc5a7b8cfb609de05d4c43beda6556283e68b70d8ffe1ae9bd7fd167a18ae3c2e983734af470aa07cf223010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4addff679e592e6e338a46018799fcf2d4ea37a1668fad97cc560a3325165bf360745b2f3eee21160754670a41a52cceef5fee304900a23d503b1010ba3e850f	1638974706000000	1639579506000000	1702651506000000	1797259506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x38ab827652139ddb4cf1674d3d97c5dfed5aafb1cf4236524dc788d1a68d779e6f02c9bdb81af83b9f269dd3ee4e3b12ac3e39e60f1d140ad8051e9a46a7eb42	\\x00800003be42ef2666f41a18acc73e7a05d5a655781be407f0f999796dbeb9194561a3eb9d62a7b5dd865224b2ca2896d68d23798db8dbf95ab4ac848adb64f274aa53a2cc5469e3504f184597e76d5a110de1a2bf26310ecc33246780e7fac9431632f57d70b7b6c7061ad037b7f70fa7f214a9893adc09dd3783725d504c8bb17872c7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa4881852f8632ff2395ea4ec287a2ab8118da9c7136f4ca114fa6cb5aa699c517f360e6dde9069859d2a214519d8b81f74983e833e360af360b8237739629e08	1635347706000000	1635952506000000	1699024506000000	1793632506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3ebf548be75005c067236819b9ed17fd43fd8f3833d8800bd17f01f05e7b4c8cdea6fee4f68beb96193ebd4db031c1148d366ee8b3be801e83e7ed682f691d52	\\x00800003ae849ca15f1825010cc6b2e7bb38d6a2c5c8c9acd6c39b24afe4c1c73d264bc4f84ea32efe4dd2f8f5de47eadc4886b7fd04efb3945848667ecfe187c657f6ff1d8f2e46d078ffa5f34367d12aa40de5735e5ad63ea1844470f87658534e387352e848f3e397a94885de4e76c7aed08b321e09d4979393c4de50f2c2ca99e9d7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x651a0d70b10d30f3079759f3eb284353d5cf97d544449db94f5a3375392fd4706f4c6e846cfe6b139eaf244413a1639217d28c5bae576bdf959d2b3baca46a09	1613585706000000	1614190506000000	1677262506000000	1771870506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3edb5f4eeb1f2838c30eacb8de0f68b459ab3b1c3d583b5ac3841a19253ea9b78b817c74df3e205c432312aea94af0c510039ffa76e6d2ba07ab756ce6390e19	\\x00800003d88f98017a25fb56039b76fffca54a7c76e12a5e001db8fd43860d65796905a937a8d0c79f5273b768f8673a0943eca201b4591987eed1edb8a9981a6d26f5458965d344eaa4cbc7155fb32bdfa897339ae0a8804dd92ba81e3330e9ae965ca5fbb8ba13da8fdd6002c7069ef071c04f730505ec598e2b7b23a584b941e1315f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x64867e58a4d95ea29cbc14b4e0ff0dff7b4715d7dd07fecebda8fec992b62ebcc40bbb7414b6f9f29d3837ef14d53d82068d49d557557f1e6644c00dffe4c40e	1620235206000000	1620840006000000	1683912006000000	1778520006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f0ba540c782cf3c5211db6f71f712c7a5c3f9b1203ae7eb257a44b88daf6f75c2a7ab61d293eeedc23f6f2004ed0f59500be76645d3939b87682fa1104abfbe	\\x00800003d80a83f8f37cb331246c669bad47bf30626bc3674a3ee442f88761b25f97602a72da3e018cb49714d18e34ace7bee6c5252eb5bb7c0d42fca0a62bff55411bb8ecd99db6f504224ce9749521519ad72dc822761fced330b317a772c81ac5d2dc23a18c0c68f6512dee483672c298588799a3870c4afeabfa4c0e6f993ef69b47010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x99067057cb8ec93ab76db2f5c7eba018b7718ec22fbcfd709d73eb37c23240c937ebc7b47ade81218b1fb1a9a4e967906322523efc71c66dd812cf57ee29480c	1635347706000000	1635952506000000	1699024506000000	1793632506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x406ff73cbf90fcc5b46058ec70ccb8fe0dc42b096829bc50fe2913555c1ae60ec7d9c781f4316669576b275793e468bbf0bb24cd94ecdd6fe852024b0707589d	\\x00800003ab8d82ce4a71c730b57860305a38ae1cd056a7d06343ab7bccc6476da3735dd1ded4f0f38afe9bff42b00dd2765069e5fc3989adb14159e3c96e081b8e60f3c397bc8d4fe46b897061a2cc851d9c7413a57d4a54133fa2e56e9ebad87e4311614b437548fee709d8cb726a5ebc6d96911bf59db0e1a4ee1058432799cbb92459010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xaac84985ff33674afedd8c872b2fb958c7682afe2753f6bc4fcd61bd4bd7a334ba6818a6d9b3c1b1832a56186543ca8b6316aa6bef5f86cdad9dae75cc7f180d	1619630706000000	1620235506000000	1683307506000000	1777915506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x437b9efef5c8316c42e6bd1d564df78b75c05afbfa8ec2255c6aef489ec012bdbc35e6e22bd3ab26ecc6fa4d1eed0a1aef9559ac017529878f8b79146454babd	\\x00800003b585ea4a22962ef2fa82638e2af36dbf1cc8ed77843dc100441186a2a2608c078d0db8a61388ccfe316ad48ab7856b0c6d9c27ac02eb3a8ea1b7717042e8bbb722ae860c38c4eb851a3adf195ca87414552c31e9e9da813096bd56ca5266b0007c1e1f1df275174da08565d6c428dc9bd08f28412d4aceb6f3f2efb7d8dd4e81010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb1dc1ee11e2ac5e1cf1d47c09fcf0abaffc54325fdb966895af5dacb9617e4253c110d119158fb0ba06c4c3f2d1c01155780ce524bb4220cd0eea5b75aa0250e	1631116206000000	1631721006000000	1694793006000000	1789401006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c63d9ca71ec09ba7b255bd6087b66574b3f0dcfc45d7042075e1f0e1796032eb075cbb1f75167e24b0b2de05a7d8bdb54a69a1e0e622cbf4980d4536f591d55	\\x00800003cd5f2637e51fcb8690fe69dff0475ee791f818b91e4b0ce6255b1c9a53ac96c0ccdd3f7e3b867e8252c0f2e27a306772e0b5cfc7b093a4c6f8fc838508356bc43b4f6ba42448066e137fe2f18992b4614766a7fb0d5afad0e77c5c5341278ae2908340b3c8667c58f98e91b28c84083505681b475d24f3c0d780b6168b0142e7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8168132ed2de5d795193ae9e97c964ef4e5ad201ee38b60ea6646954f1203029c153546a434ca894f1eb63243e9060430b5332b58f5565f1eb97e1ee0e974309	1622653206000000	1623258006000000	1686330006000000	1780938006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x51273772b20e4f9544b7c5e8a57825ea730ffc5218f74babdd8d04b864049167b050fef1e2c76e3753f4ae8cad0ed2aab9d837e6caa98f8159ec41ae539eb380	\\x00800003b932a969a9039545ee249434e6e824e73637d680fcb1e1873b9d1d35d8a35fdb4411fe3aaa04e50e87fae26112aa3ae27d7577f45f0f143e45da896a92c9060fb23c421c177b6fba27f860c6cba53385aed08bf5d9d633bbb5633ac9652e113909f43fe2c26ee464d573b7cc055d2df431328941161fdb766400b2ee1153ce1b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0a46193fa743082bca0ef328b39c7ca5634d1cb9324c97f6c271f7b8bb49c83f77b1502b9b5fc3162112f86a7f325774b5e6571dfc8a4e9efcf7299607d67705	1630511706000000	1631116506000000	1694188506000000	1788796506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x53a7c9aa380245d600adc70b4a38d621f391cfde6432f6d46dcd5ae8d81faf349ad8d5f39704971b3e60faf51ce7687ec0c104683992c60040345d2751834656	\\x00800003e855254b19cc789cf91d4b9d787b80536ed178dde034ac5f284c23ba9d919e20a122c492701c147846edc74781466b6d413e66aba76818290f99782a36bf9bac9d274ebed34af9800b762e7959c45e5e9638f1c87feab177cc9cd0b3190fa6fe877b3811a6e4a71e45daff805e17c7fd246f32e36d1a161671bd5ec7abef52b1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1fdb28045021e33781c721028b12c635e515f329938e4e66f2fbf83d5a806e4a05e140927c2a6e0d028dd739f24a6916c038c8fe0dd4720c97b497de532f7f0d	1611167706000000	1611772506000000	1674844506000000	1769452506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54ab1e8c9090609488bdfe08c08ad265ee810267a76282425ffac0ac2b23e57ca86908a6d8f1a65a6dd8cfa560a882bd4926cbc3f35110db6519dd997afeb297	\\x00800003c6d0ace0f2de8e5c349631536b8db95c3c6bd5567f3a3ec375252af8b6ad03f7b56b11860e18fa45b96d316fa721a25e790927ded6e21f335f076f31b540689018cf210d8f355cab117e6bb223e9ad439a07d377cc0765c87ae06bc48610a1f662d1c70c8bef4df7bd0026bd8d7825a3799e1b5730304b93ccdcf430afab002b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x0cf04f6158263fefd07c445f76403f101f8ca13a2d7f5a2fa8ac9f4ef9915cf1190381377c7a39b8da17a602f7d9b9d9e5edc1acb8d2242f4b3be9fb709e3009	1619026206000000	1619631006000000	1682703006000000	1777311006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5433780e4acbde3bcb1ca9683378a48f21e53afd6f8d0477773080cc54c2c4cc0bfdf020c012bb883bd85290c1661477821bd66cbd25c142c11f203c6f88ce9a	\\x00800003ce54fd1cd557fcda9217f2c6f6f5c094478824a86724b1c7c98a1399e6149a22c6df9445c01c2cc6a97ebd2cc652d7b786b921b9f67abc3c14a7b4dd4cda6f89581f033647d43681a747f8c44a0daa4a99514ed488d5c4f6879e6b218c10eb3e627437001506f673b1eed02a52d0133a2e49cf352e313952934e3d1e52ae672b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4892b5d6902ad39280cd7c9ba7a4a6b755edd6c5c81cbcc9e28535000975ca0646cd624ea40577fc41e1fda9ceec2dc177af132898c1ceee0b436af12ab1530f	1612376706000000	1612981506000000	1676053506000000	1770661506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x562b832d4448f37643d0599aeb06a761a835a2df7ebfd571fbbc1bb20804e2f8148277b2d82e1e9647e461bd43a1e6f4e0883addc8b3b45ad63a5f469b4ff4ee	\\x00800003c2608bc1ac22614061ad645e7be2ca76ead4bd66a4c026482e5ac06f9c49686c6a2c7c3c41f38ba1e21590d1451a59a04cdd49f18ed027d08b67b58aad3230bd0e96cd941020c845c6229d34d869dd8c8cd254bf69ee74a26e9e6ada9a8da44e1a9f20b9ceb4b904c5b2c8485f0fed64b6ba77fc367f4073bb8f5d5078d3ac8d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xac9f0dc7a08e8b0a757c7f8c4b91343ac7dac18c58e45cfd40c792c6ca1f79141bf88ce9341ad82856e717287da3fe7bfd93e61a1c477c1d8e4467fc14f3a10c	1609354206000000	1609959006000000	1673031006000000	1767639006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5737c27e68c6cb800a41f552f084a5e72f8aaabf93ffb173e3ddb8799cc313f85e6cf2df02fd886627c4892277ec93ca3166d6ffa99e28aa783db80bc2dded60	\\x00800003e3278dbadbb260dd0c971ee108dffb8f463c6be74f587c3a9456e4fe84f927e237f1ecebbc6dd1f1a7cde8d203ed2ff8235f8a0d841437f4c6446009cef97e563c4d6ac0104b7ed68df64973991f879dca9a781258719409f28401ac2fc3476ceec93a8a9d62662f3e82b00789566c22376159f68b8faa840d91642bcf4366d5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x45c8ceb22ea2bbe9002e1839e9d6fd8dcb347147565c22ed5ce0e260128bcdff1742ee538e09608f8802d3a3ff9bb76adb202bafbd0a9dea81e432bc774fa902	1608749706000000	1609354506000000	1672426506000000	1767034506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x59cbc902b6aab0bc507794f386261dae8514c78733ab651a520d95a1284ff232ff87558e654198ad0d056349920f1131872fcf1a259e67e42a2aedbc2354d882	\\x0080000399ea66c78070374ea178d0d6a3a27e447b94b87302d8e09467cb151b2bd24919d1be92b1bb597d8acc02c8e4eba1db75a7f6dfce16f1f29fc67e0b05f4abd74665d4aa07da77694be7ec03b62a8e1357547fa10041417f28db1c0bda5eb61a1ec55951c59f6818f2633dfe4475069375de479e0f9d54fe0911e14ff1c0baa9cd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xcb5795b59445d5cf44f8b818b43009dc6973395282160cba4f5a00ce5dd899d197aa8aa86ef74f3b7b49b866f5e6be85b8dea7f956cc2fff28d1721c9940580c	1611772206000000	1612377006000000	1675449006000000	1770057006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x59bb71a770739469198c127071a3786c9f94ad1eaab01d6b93526ced70be3c1ae7cc690c6630adb611ecab03fe93bfe5583763c61e36372abfcb561b694793c3	\\x00800003b78fbe903f6d44632da54581360b03993c4c86318cf57633c5c278b4fb12e42446200efe086c3e15e7a5b711b04e3ffc40669c0a456286201be0ae4868926ee32bed7ca3ac48f0936e50a12dd411a309ed40f686d4358f66d9933c40d3f23489ba0ea2950c2c2e5c42429d40cdb55ae82d65ed351522afb41f0fc2b8b7c20007010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x08774c9196bf4681ef81c118e0bf511f56ab3923a5b3ed510957bb45a1abdad4e0b362fa980aaa393075742b5830320212dce72819ea687d2e3af163c658dd00	1608749706000000	1609354506000000	1672426506000000	1767034506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5ce78e8b8746a6c9afe5b88283785cf6987b6bc9ca9269b126e594233da4cb71a5582d49bf1f1388f7bad016c9dd59a63fb6609d421ae6832defb7e1209dc6ce	\\x00800003b54f28b87be08e3248528334fb7171848c3987ef3756d8b6bd1f9d866356d73322ccd632e26ef73c3f74568112214a69f788a878b3b390813b3ab08241a11ab50eb1ed5ffc89f82ab861ea3ab19b55561999269623111281777781208d43dde7031e84ead61d6a05b823c4ea8b66cdd7913f3774a09f469b68dfae3e4c6612c5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x52ac51a96e10683753b757b078b17c9a98a428d284606fbbd7349dc34dd0e9bb4b1adf7f96ceaa4c1b9906535ccf8ddbf5a5e430d21f2cae1f3eebbced92b609	1611167706000000	1611772506000000	1674844506000000	1769452506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c6f42ac238239a78cf27537312b7c36e713c4e78481b367c36344c9690605fd61ae31376b6a3c219c1a403e7217636836d46beaa2cb18d931904aa80984151f	\\x00800003c1f65a7d8f5b1cd95253d28eb06cf64eca9fe6957d01e0ba71959b2486e1d2ed7e8af89192163f4e23f0c2d09ea9fc3b30588030ec4975b530ba4bfee5250ae32cee0c40c1059d3b0f21ed601591c49573c527bdcae9589a16c87ff1330d7783e0b20c32c34a8fcbd9a3dd03c728d175fba07b4f951b813f1d581d6b017a1bbb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xae29af3c0af47e5b468b24752e6e5b362c70097b38f5c4bf355d28e759f299aa01423161ff4a03651af47d50ab3c12ef27b651b3282a84edca504ba04557b90e	1638974706000000	1639579506000000	1702651506000000	1797259506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c9b61057d67dc355490e27d05094b78dc2ad1238104154c0286ad210faaae89e3e38e3e026ec6e3ab70b8f891b797f7610ec5a4287ea2c6d7bda334108e6b90	\\x00800003ebffb8963938de522e37ac24c7555e1fe9bc552133acc37247fed1f593ca12d47ddf19580ef67093f188202d500eebde6e4173e9d687ddb8119dd8e9934707a7ad26375c6176ebbbbfec5f33282709d895ba39bde37b654d1016e3a5bdc0b841d3c62b47ebf81fd222237d67005c13e8df2c96325cae269a13a4a780c2526ac7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe4ebae4648f46c5af495465d140823baa65d234221321a53b4c0b7179d7807b547c922fe03ae8d32a0eadc82667dce58b845b9311a3dda5c190f89f4fc7aa105	1634743206000000	1635348006000000	1698420006000000	1793028006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x655badafea0b0c278be4047184b927fb05313753f851c5e95ab14f02d8a4f7969f3433b7d6348259875f4b87d186bb9ec1c4a1eb7d150f2f503841b79f8336f6	\\x00800003aef4ca93b4d561205c99571d3fe00a26d87323d07be3458b1c1ff18ee2c6bfcab5395dce07dfc6a36f94f45bdb6ec0883f85795fee4948efbe806ec911ad1694faaba234219133f51ca0ac909f1a1f220f42b3ccc7bf583b6001d0af9e79c9bdad55831915d3817ed6994726a4d47517beb00f9cab0d36b2ee4663d1b83b4a9d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfa140fdb48908051a2d055a9984557dde4e30628ea7d0c90ae8d45388704d7b4206b927b8a09090fc07d08ace4bd864c6b491202dc28279005eeb374ec5e8a04	1628093706000000	1628698506000000	1691770506000000	1786378506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6a47df795c294d85ae65595a8427b977188341dd08b2be006a09f509d7507b3a0f26ced0dadfc2f92c8d1f460dbea256034b0ffb38e16e7bc6e20f4a2aa714aa	\\x00800003c417e7b881ae7d4420e505f63e0d2ec6fa526f4123df0b05be57a71cd3dbbca3bdff60ccceecf62eb30b2fb42967cf9768aa328e4097415babc7ee98672122b25e073aa410cf59bc3f87750b3c16f6b09edc0e421e6a352209247b25fadd794c10679f0a47953f8cc411eb752db155dc3b849a3a7162db238d92f67d1dc301df010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe48163bf78406a996e196313ea2b8986106eeb9b6dc6e60e098bf43c30ab50bba3ac6c6efc1617d7502bdd7c2742ed588a9d365418f75b676523a07c1b5ab40f	1623862206000000	1624467006000000	1687539006000000	1782147006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6e93627c94f60d66efb9da5b8b834c83d0560556aeb945d714ad2293be901cc0243f0561697ae0c7635a62cb2ee003cb4ac3c497a4802a884fbf6a8f4865cdaa	\\x00800003aa58859fcfe47d44bae7478574c93f40250fe9d257f36f0fc340b8d25395eec127d3e19e3622638218ecf8133a78dfefcd43ffb2178a7eb43856c9e59898a26c8c83c22d2feeca3bc8f1eb6687ece661cd8b976c630da4b6c5d5d6e5a45b2f7d9eaec68743a924abb2f88bc556aaed50b3d6a2ccf6e08c09888c4f903693d541010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8b7c4025093ad866881777bb39120e32534733d4295cfa8fd7141982ec9a4c886c62d1becd4db95ca3ddd0a3d77e9957d354602caf12524f620ad2d672c69b07	1613585706000000	1614190506000000	1677262506000000	1771870506000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6f2316ccba9d658e25854e90389508e0f4cada554861519f2208c2fbbb8c32f276e0f1b5ab99c6fd030d39c08fdef97c8eecf776058376f5cba0fe50a294fb05	\\x00800003e92c581e382199fc8a2a7c598a8e42b9625ff59529b3acaabe28503fb41c64ddb55d23dd16082bd7833941cd4184e93c833986d9d2e29ba6e090de6782bc7d33e831c3ff4b6e4af37d5a587aefe314f1813b9b6bd81110a4c4283d07f42579fab596ed7c9a502e4b6786c9d08f0934b2a1a4a9509d0125c41aa1ac65e37cbea5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8cfb0fd2013585463cbeb6dbf97309c2af71ed02e2c171d7c276681626a4e2601a6680d5937ab37c00b147d0cb705b1d8e86712f2d9959d2f5adf4b0ec87c90e	1626884706000000	1627489506000000	1690561506000000	1785169506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6f83e2e757576f37855a3344dfefaa22a84b5d70782dbfd28de83f7851cc23e3a8a27c108a186103d09dbaf6cd6aa6beed14610289dac8846c22325e0f54d47e	\\x00800003bbe9203b28ce6bc2f2f98a5517f23fa9b968158d6caac9531e2f30115e53a4001607f8ca780a0a919830bfddb0ea335bc4a07166272bc04ce50612776dcff6a6ea2dd344a9bad8a9a3cec4b1aeda38eaac0de4e1578fce41d9c358ea10518400f24eb438ce1d472620031aa77f9b01fddb0b02e7573fba9f5c1a70d2c5acef95010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb9e1d9d1eadfeb64ae49e8ce4a517c362ad9d1d5c21acd0fb34bd6d18e83eaa6c38a55b0ab026b7e2b41a5d6e799c8641ae607c0a334bb2751bc9a128231c90b	1632325206000000	1632930006000000	1696002006000000	1790610006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71d700c4dbfc561090365bbc3e205e4635700d668c678b27ea2d259f3aa009f990ee32d56ba3e4eb041bb0bbc1564015b77cb609fe3d47e001dcf7dd79d91d6c	\\x00800003af0b93edc530c37154c7b80f26e100043ea8daac3d3c626233e3cf862476fa9b52501568d32219fec57165b111847756481954d95ba6b12477d9c8f8ec5b5ecd48eb1b1805c1de2bec7fc4e01f0684b3006e01f1bee69a7cadb2532514943ac70c41a6402427341203bf12aee0a61f93f77e954135477dd27d4ff52793f26a6b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x20bcddb3c64fc13a97d8857026de404a51406679212d6835418d6402802c5f7558272eb6263a08e75bfde2da486daad23a6a538196df57d6fa75d2787ac58e0b	1631116206000000	1631721006000000	1694793006000000	1789401006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x714bd2eab3d885164564601caae506622df50a8532d655e2ef9137d7714f3f505d69cb704cf95b28fab01536c5712c2b4cc7a760b899ad1433e3c8ed863f871e	\\x00800003bcf242046813bd90c322910d8bc501ddf747da329df75b0ae0ae1f2e477e11bf971bbe994cee0278bf3e1316517a152f41a15f76dcb314b4423baaa4c4e5ca0561168ba8ccb433686836960c5dd4c4f36928f105744d36319ed5c7a0d18ec8877278f8e7f696664f63b3993ebdc22778ff1b8ecc8921b102c89af0c5010ca82f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdfabe33fa10a02cdea55aaec276ed7ca24812e436f212d0d561d99a1b51dae33b6e0639446789b0efa00fcaca2ecf0be914a2ad46ba503d7c9aaa70cebfc7901	1611772206000000	1612377006000000	1675449006000000	1770057006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x72affc5f6cb94ddd1e6b3dec533279d6fc631952a8739621c3b7de5c10569db80a1a2c8a962c1f5c52a25b9a5f56178bf1c9f0f98586b6e6d790cecbf47da332	\\x008000039e7e6b96fb0dc38bb7ef787154d102a182a0260b1f71d4291bd818a88e56d5b6aba6f6168794390c3bf5a536c5c1c25cd93416fd918a9a2867aec35929899e054187cf8a0d24322a8a2825505fd851c5a3dc57b98d6143ab526f1225a901c42e2b950b79d4c21031757c9fa82751a99a0450a2261bd32067c52c49a5cca42929010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x23b439ed0251b2b5aa8828c9a4ccbdff6807acceb8dc3ebf76884edf4929e667c587c8f3bbd87f3f2fe4ce8c216c7803544ae518fb9140f5f082d0fed8cb590b	1625675706000000	1626280506000000	1689352506000000	1783960506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x779f4a333aefa9f20fcf3c68d8041380215d96919ea46d060a6b42f564931b2f24e729dffa074a28da19540e138c33fdb2502bae00b40370897ba201619db21f	\\x00800003c4d56cb2df63a8f5f2cf67d2cd3c43279bd67283bed7b79dec44293ab4c197908ce22f8ccc0eff31ade6f8c8f6e0a9f048fb795cb52ebe79660b7455388d448dbea83014070bd30e645bf298f892e580a4badd677acd3863778d959fda3fd51e657db4084658cf7d3d64ab956529f009196d5cdd1234695abf82f754b508d76d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x909ccf63f96a8e60fe60373a76cd5a2903d32aef98d7845be77ea8d85967cf5a42ee66c0339cbd3fd25efc54a2872247ecdf01c21842393feaf805bdfd04cf04	1608749706000000	1609354506000000	1672426506000000	1767034506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77637160875062bd28c2119dfb8c0e0b3a7772bdfebccea872f92e31cbec7e0a32ff63517462564d28aea45d1d19f95be678edda8a63bc27d772219052626bba	\\x00800003aa2cf1ecf25bb19a81182572c7bc20e8b365f3748d62c0e596ab24da31314b2c8a3c6326672877d5569121b3b4e1966921780a13d8bde0e0e130ce0a58b7b47d73f9213017a5ed767311d21f6fba151089b66928ff1027604aec097ab66693cb38fddb518f045fd414a68cbb5a3cbb54caddd03af698a3dda9488550d1cad6bf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x4e0ddf6983367de75d4602403d5a9c5ef1495a0ac4cbaf94ed340f4ceed2959e5ffcac40029018cb3d62c6ce4870b0a9e3b00bd2ab6c2dd86093b01306646304	1635347706000000	1635952506000000	1699024506000000	1793632506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7a13ea336200fcef40ba46826dbfdc43e26b3004af912d10635f037bc6f26a6004468ee1ce35601e9c0e839d1418ceb95916cbf4d2fc3bc106872ff77424a2c4	\\x00800003d7ae9efaab6b91c20d767023563d3820a2eb82f048562c8609e97a7fa0d8e362151e9c7cb469e97cb5e36243ed7e906158bf27a25fbfaa7783c171339c77a6247adcd2e002387a65e2956b7fe1c626622687f622f4ae03bdd08dfca110f1803c780828d8c4d89f71c26644b3a10d72485f2e38e96f1632a5fb152410bf25d175010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x74f04575502f4798b7f644ee54ef4b8c19050861eb838dbec305da817d0b6f68532939d88dfd8262346695701266b80c6da3a2476d6e9eb675dc314aa165a600	1621444206000000	1622049006000000	1685121006000000	1779729006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7efb67e477daaa965bcfcfcf539786881ec0fcb0876b5a56549e72b887261f27c24538480c711c61e2c8cb70c58699e3636220e54ce45f9d1f85798d9d426bb0	\\x00800003cd34a065e5c1d0aaed1e3012bb5fc0134440b77c1a4086d40d88550e8db0bf6633e937ebc94fed5bb05d4e1d831f02b9add275dd8661a87f5297b477d65d2ad9a280b232ded434dbe4027f27e0b797ec82109a7c4de05a58051773a95f9bc41f212c183f269177ecec836ae48ff8b4dff2d141396ee1c234a840892fe5feb841010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x900213d803b572fe299b6331c4d3d172ecad16a2d5db7bbbb28f5e56df745d8cc2bdc0fa489f14856476e0ac2a1cdc697befdf43c0da98c797754984416e870e	1630511706000000	1631116506000000	1694188506000000	1788796506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x837b53092e33b9c5f266c76b6c4c6ec6f694ddba684f1d1bc19c5ec1b8055edaa277b40603e977a1b3843ff59cd406c6b7c16ede587f3300dac029512c8ebace	\\x00800003c8b42474a19912e1caef55cf9a519a176b959064c2e38a72a2fb8196e985189ca79350f2e50fe490ee6bd8ab348fbe98bcb1419a13213a1f62cf974002af720243668841136a00bdf1eb9b86a4c36a4c72f98b657e12ddf68e9558f13be9fd426fecd252c4af6661787c8ab05be3d9d828bb8a3e379d8368c82f9d6bc4d7afeb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x3b6a44b2f15cca003465556979d990e753bdbc9f314d98647486a3ae1d10bef670bdd369a2f041457bcc8dab722776b18284a1e9188bf67fdb7cd41fbcccef0c	1625675706000000	1626280506000000	1689352506000000	1783960506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x87936b5ec5a8b193926a03777f8594f9a584046a040e556432249190f569801f016d1c3ba965e49a1256f4cdee800ed14e2852c6dfd3c5190478fd9d702aad96	\\x00800003c68c406f602001967ccc4807ce23e17dfe54ceb076eda20a54741d95728e09cb14753facc0d05f716704f56faa35e31bcd7886c54ebc1a6b828de034c98188e000955ce20960052878a85a1d8339f824c4adf914b704a2addad8b56d6525353d6b20c69c9429042d61f99416b9049a15f6f958a9dda1758f90799ec41983249b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x06b60a42fe55b5497fe124681bb7d3e8fd98df2d7b58e78013f0a26e9fa3becbd3d75f5ebb1e4d5f3807802d5d06da728dd6c76ae5da79e017531763be9c440a	1636556706000000	1637161506000000	1700233506000000	1794841506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x884f69c5033e2faa689ef7626d01db508fb0d22779b7f481ac3e85d29264e8cd67113d9776604dcea69c413606d18ad455ce3f812aa463fb06d023b2047a787b	\\x00800003ba92342dc6c9dd6b04ba96ffc9cfb657e25922ebebcda2f8bd5ba988c1d52bc50dd1aac125a02f551548922a06b28d3e4fe23eabcd08472e6ede9de659f2e99c862bf37c95c90ccc5151c41a86cf7183817b493310e92cd38b0098393b09dc9e0c8ec95302b2a545c34dc45a8bcda8facc7cebf787a5d7f702fd2a686682e20f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x701b9557c0fd97bebdbfc7c02ed4424e984584abf89cb1ba4882188ea783adf3e6f9595c9743f312b64dbea2e23a8ac51f23d99a276e1313be3d6cbcb9a64d03	1616608206000000	1617213006000000	1680285006000000	1774893006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c37357f78bacd18d281daaa439294dc6493c5a5871183364d185b891dd94f48dda3bcdf3824058d9ea9c059cfc200148c0297e4357498ef77c0ca7571b76aac	\\x00800003a0b397e0ea96e89acfc45e1dd6c52b149209469285a5f3301bbbf01c8220a0dab98d5c151cf6640d00c326c0682dfe7f6a3410cd022d26f4e01f23bb8b110a4592f684aec7141240adcbbd1d14fb577b7350eb35bc3b85cca022ae32473999ee461a9a3683a302f04f55d53be1d3a2d6434956f1f7b33ba8bcf5223fb6da8e6f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xfd33ce52f8eae62372af39b2bf1d7671dde00202557131ca4f81f20e5bbb1241354c9c1fa3e8033da6632e957687ff5d042361b0ee6b3062525ce1700c1a6900	1616003706000000	1616608506000000	1679680506000000	1774288506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c3b2aef16ef8b484ec2d93d1a793bda732f146d17b31f085fe365a6a8c5c2f5ecc3cae46372beec82595b6ac189097dadfe4a5d78007f1191fcfb7879063279	\\x00800003ab388039e4abf46f38269002f933df063ebca5d82883f0ee99b0915f38941520e160bdafc4f05cf7ebb4a56b4a451b85a09af9662107b4cb09a98d1c4efa26cc3de3707e0aa76b07d11f3a77f6d36b2af3785167b476eead57e3f536dcc15d1459291b724af6fc20464c668b42a8c70fa0737c1172c15d071cd1657292cb31bb010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1cdeaf240e4ce744f3980e4c78c2fafbbbc2f9fb3a5390b8671956d22dce21dbeb7ca8fdbca4221747fa269c8556e77e9768afd2dc57dd5bbf17f7cc1f59990c	1627489206000000	1628094006000000	1691166006000000	1785774006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x944f323a2af8209834ae1c43753b049371addf842de0919e6079152ce33d73614ca5e2219d6ec3c57aea7360efea929a8680ac6f8e95f6f0b879c06fd12e4aa0	\\x00800003c76d49b73aa0b89d9e461a8b506c6679458d71a9e797e39ef6c80b470026ebe18a6b6c326363f483c38e8ab55321ca3f3c6ae0b61f94b9aec4c0d75c8d2abc61fe746edc54ab9391f3016f8ad4f5b3d356bbeb317269d44ca0048e4a42989ebe8e9c501ce66a1af6f32831d7ed4c13918a9173f0d8d727843f944161ae4b36c7010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa6d202c877052e5790949618edb7811755bb8bad50752454421adaf59bc4bd304698e5da82a8a4f6b1442179053c9274223be8ce9720fa3bfe537eaee9ea1e05	1609958706000000	1610563506000000	1673635506000000	1768243506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9cb33bafc412ded9b3455a8917c40b9fa0269482968abd5f158952f281967f26365819b93eef6ae4ca1c1c6aa20615d17fd39ee4ec77458c5dc500bb8b1b3588	\\x00800003c0a350cacc8fb73b8aa73fa6f0ac0dd29a72092657457673af2d3b7b2035adcc5bc19fffc6814f3dc588d80d03bc3a215608eb6586e22bb09ec356eadec18cc3fa0977623a6888d9807b993c04f85e3e0377313c20de5d30ee3b1810a0f8760369a1f5b4bc3e290d31067d88800f4c49cdfd42d1eee0af9537ca8e5c52bb7d87010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc75d8e9734a7aac0056c2fb1101fc58761a61725449ac2b85a855726602bd05aa64caa95b20a32551ce279b522661da71fd1fa5d6ea43cf9797361ed222f8b0c	1621444206000000	1622049006000000	1685121006000000	1779729006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9e3f21807ac4807fe85be04e9520252dd001eccf74ab364e3a150ea9f1867ddd7129f7263d3a1bee3b6bca93dadc03db645bb52d6f90fa6bdd4393ffa6e24ede	\\x0080000398715a73b350be777a78bb3e4f04a7b8d27db547235140cec9f20840936e0765bdce185750ae1877989cc78c43c7bc8c0e5d35eb3ab1ac2330b2e3f0569476bb3714694ce4acea04abeebffcffe3d068686b604054ae8c84d17e27d4bd66fcb54f5c57c0aeb2a77a369850857322101d79fc516ea0eec436866030da9ebc33e3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb5c3c4e538c268dcf62e130ae61d4cc70ec20d2df4bd4858e0590a05be2b95b04cdf741a6695fcd532e9ec6dab34f06364ae9386aa5dc06681bacea453916100	1616608206000000	1617213006000000	1680285006000000	1774893006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9fc744afbde73877a19d9c8b75da8e5145b3c30d7b5146251f5739a5c24b4d7ef3cd8bc2bacc560082e2e218be4af6702a14feaf31c6f004d9b39cf553c2ecb7	\\x00800003c097a1ba97aa39081f98ad665c6f248f9f600d906d8138be8a7bbdccda176de3becba699d8f0a8ae47f14d885c912f00dadb4c3b7428a357d25f674a7a06a9b8a96a8ad758c2883ee72e22bbf0819eec50c45f1d272209960e93636ade784dd385e79c1520c464db0874da691c19b5dffd19e75cb5a18c724941ab88f39f8199010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x5be806e0f200a13d988014773792219388e0b995414e053e2868b7381e672ecac290914320ede51dc9e900b15105da4395f0c7ae80bf5b038158fe8e62031a03	1626280206000000	1626885006000000	1689957006000000	1784565006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa5c3cd58571ebe67d3c56cc552d725daddf6a451a3b268a5fdd764940ccaa518b857e815e4113c9c9fc4cded9a1407599053a8a80ca24149937d30ba5d1103f0	\\x00800003e5b90d1d8d1e7f89b2945aae52ba9c7ad7a3c8e8c3d3338873a7db73292b86760a914ec6ea8e77fd1553e56c0f57690d5da5ac582f1db1b0d22a94ed5b450364ee8da79920127307e3bb44d5db4d114748867206d852ef3b687bcb082bdda1bb545882e2820cf85633fa6804971e32ef202b4f1a8efa7b759883f17bcb40ca9d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x637b309c6afa27dba1ffc23525b40ea39d6dfac497781394566c6e92fd2c039bf08edafe7e02b9da146242f92217532c34e5037a282868740e98c56fb4731c0a	1612981206000000	1613586006000000	1676658006000000	1771266006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa57786a4020d9b54890a949d5687561163b134da5350ded28d9e9c683193ccab90aa80c3face6189d86c82b994911363dfcae9115fdc52956856d05cc134a764	\\x00800003ca2df1340213a24006fe3952433bc7980d073b00d190244a4fb102a64baa6447db19570715dc0acf6c2ff0184d8e9924e4ebc7367f64e2d376a35b3a6165194c3916f089da7d0e61cde09f7dd6a94e9b631ad9316c611617ff6535ba3b98a5da324599d5968e78fc6885a14a9dcd337bd86418c91063b01d15da8bc41830cb0f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8642b6bc9df7ada136ff63645b12c0cd6cbe519fd4ba5f568e9e65749bddf51ca0026777c426ff81b55341452d15e45b3f62fcbd52a7580cfcb0a4e8b0d0eb09	1614794706000000	1615399506000000	1678471506000000	1773079506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa59b455d13d1f3435dfffbd9c8d503acf7c659f210f024566167ea2f3d8a767df31f24c7f491b2cb568d9917c2f3ca7026bcd5460c66e8d93ee308a4a39b8d21	\\x00800003f3a105296e1e4ee168328f15859dfd20988a62765e0bcc28e4e4f8ca8107d06d88a71a3276f06009ee201bfab19f7d175c6f9903dc98f7e847879a20ac9692c0b1b2eafefbbb167c2956488082fa88407b96304e87ae9d2a315162fd6b46db5b29c3b4c3f93ba854045ea9260c1f427b2cbdb35c5472eb86eb4f4cb53c517fb3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xbb856964e7d74309d04a0688966c1da315ab79204081d6cd64726a0c28743ed7780fcf259a06fa0782e3d0c9c7f36f2f3297c599c6dc326dd877d4ed8cc59f08	1628698206000000	1629303006000000	1692375006000000	1786983006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa6579d4e8356f67183ce40c3fe3d5788e76b57e5c54bb4da8cf9686776eb161523ccf998ce9847f66dcea94ddd854686ab36b891ca04e1e641253a69fb467f08	\\x00800003ed7e198b79cbbfd172bba7c2d0483072af7d685c3da854113618399d790e33cae11463b9d7fd81175640dfc50bf7dbae4ef5433b7b1b00808a4e4b624a1abcaf3bab12c1a28e5193b05e80484a758d44ee7b9ba96d70ab60ba416b406f1778e959e1e28947a984aed559a5710c3efa7f31ec7cb7a45bb1eaecf54bd9e38617b3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x261732c99bf668ad546394bb909d1543633581948dec93d63cab6338cbfb888b354e8bcc5aa97ed3634c240463c50f175b7fd1cbca44c5cd4dd04af465a21109	1626280206000000	1626885006000000	1689957006000000	1784565006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xaaeb34c6524e674298e8e9c75058e888737ac3e57beffa0a708f9ed1ca0af467847c00943a3324cf9ff52e307ef57ba6f03c172cd6f8aac2d3ae58d9b4030b84	\\x00800003a9c98fe0386c2cd4fd6f5c36e8d847f8eeeb57be32aa66159e506a327848b6a7d1a0de56ee20c39db423c3112fd927838ef30068a041d53eb38586d26f07591060de589bde4e314615f6fb4fb6dadf2fd9a967a6de1e424634331be978e4375c943c7b52b6bd4e7a1f706feb05008d2295d21c44b3a70305e4535685f4174d41010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6a9b62b603b3ff03cc85b285ff4777311beec738df8124ae398d58273c478f902f409e4ffd8998555f116343608d98d1f5835efd0e9721f2a0bef2aea95bdd0c	1636556706000000	1637161506000000	1700233506000000	1794841506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab77693fe6698314ae8dbf63ca33ce12ed67e4f154b5c85be57fb0156e4a02b182f63b26511781ff4c508825a594883e4eafb7ae99f4df932c93bbfc09b701e4	\\x00800003ed9beac4ef573d7f176e39ef635887a02567a0e66a02d9dedd84233da146126a2eab1d88f4a508492d011e08eef282454b9c8e0be05e1238aea1f7fc0a1222618ff74662bdff328bfbe46fcd338813d5d3c3bef3243936c288e5b5a1ca86d6ec8bcacae8d8fecfb3ab73bc760eedfc57028666391a2b8b4ecdc8d6eadc6d83cf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdc2e67747f945e64817e4b92b7d99a8486da9a19de24d385fa0131a8b835bfef02941d0a2842d84f9e7173600d1d24d43580dc10ce62c0ceeafeb733009c2b02	1634138706000000	1634743506000000	1697815506000000	1792423506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab27e6bfdaf57f2ef4e334395e3e1538050f480a94465a7fb696063f55d6c7cb326071e395843fc5b188d52a3f56c89ffec33f53ef48c086b2bb3d6ff5e27813	\\x00800003da80a680854efb637cc905fffa8002dc20b67c901416ae292c1c881f89c21a6a4ed3700d324be59b2d98887ec1a0918f331cdce8f70c0fe075fb39804c5b3d4feb61e87f7caa2421e10b5b594386920550a9ea3782a596188f5c9bf959a3af338a089b892b9c67dde9ae121d90669cd11025822dcdc535a953e0951a7440d3a5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xe36a830c33da9eb1a669b1de25b689f7fbf7d2b87359f2b6f8f5ae3d580bd29aa91d3cba271b2047630b4d70aee111b29800d864dcc4e7c6ad11a51fa4db6e01	1615399206000000	1616004006000000	1679076006000000	1773684006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xabf3270ec6ed8990a230941e8f77ec52a9cf6850017ae62a8e764ed029efcdd8ce873e8c4d89689b5fa73918c7b4379a125d1fa70f42b2d90a1175bf753904ea	\\x00800003c0406c754377aa798b5839880910ee16f1bce995879f0639ff2609e52ce8aa3717c66f2dbd7db7245d656e10a39f7269f67e36026d459ebe17ba940c577d5931d2328ad90910cafac9681c6939f813af062897a9000ab9e6b21232ed25c79c19931f7fbcc6d3cfaf631196c106dc0f8bd0eda4342e33d707c77777079a45e6f5010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x41ed22a51c272c7b0a6caf02e9d64605d28547522119997e1adcbdd86d60862131a980f6f759050a10fcdfcd2a64ee080ddadcdd4e8febb5bc69bcec33b3540a	1618421706000000	1619026506000000	1682098506000000	1776706506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xac7ffdfed53ee38321185e351f5b30dc7fb7ca875102bc13447496f816ea03a3ae8d14182360a4068c48e143e245d8edf26a6f989470b110de15d83448893350	\\x00800003c1c453046c5d92f9c4c074d4bd018d98fc27f3e8d50421f5d7c3742d98d68b1736fcd8556a79bd9a8f08b3c92539f44e80f1df0a27db672267d7653ed99de38e120025118894bb0fc71c4efcfa561d3a16cd80c7055278be9af9ca741c065d4405bddf985c554b5bd58d1f9a5d76070f6bf7e783cc2500cd192f2fb1bc59c0e3010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x02d5634f1772baaa6e93d036ebfb3b7aec4efe483474b47ed41c987c19465b002e2b5db3b290baf00d77c9b272698c662411b40d9c48e4cb1a171e9533cfff00	1615399206000000	1616004006000000	1679076006000000	1773684006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad2ba5869b2ae502cefc037ba34b5e02669997cd77ccabb58604dd84c7f626cf8f4cbd6e71edbf141abe9d6f454e62ddfa397f46554296ee4c01b3557f65e5f7	\\x00800003bcc9ccbe2f433e15be87966355513221b6a3319aa4fe315bdae13644dd2c27346fc8bc844d04b4eedd1d48fd98a1540e2e30509798a87d35bfc10c90219e277f603a9346a76fe3c11f883c2817f9fa237229402a51c2291d6cba542d7ab39b7e58a07103d649f620411559eeedb4ee5f652b1cc4a2fec780da19c122ee90aee9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x95110a0af7e2a2c884b4296aa544b77da417a8b5b1f2ee24fe8a50b3984bb22adc0b5b5f2fee2e6d2f4bed8d88bb7f7ecbc100e500a41f01183d8b1c7bb5e607	1614190206000000	1614795006000000	1677867006000000	1772475006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaeff567b280b0fb6a66eef4db1b194d53367a89a43547462d6d9b832a18054975dc1a4bdb4b4d2fd027b9be2834ee71215451fe73577a2299137b3372fa8836d	\\x00800003bd5f2dc9ceab7894665c54a7d75723166e6571a40d77f9a6bec9ab3f6eece14df448d446b3ce763bde0089e8a26ed624e9bc9841a857c7c0749681f73507f908f1b4cf008e9057131e6651acb86ffa981fc33d1da9aed7c5db4462f38e9e44a11d46ffd1760455d14ff3e56e74b18bf011e63762eff1747ed5e8d83880316205010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8efa1a808be1056d687ba008df38399204294fb50e218d8992f56eb7064f585cfd2bd1bc430ab74b9a9b5cc5a34bdb726dd9c820eee7f4ce826566cff087b900	1619026206000000	1619631006000000	1682703006000000	1777311006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb00f2250ca335bbc44cdfc2db8f362d0f42eb82416703413d728e8ee7584466ab631f482c2d1a1843a27f3130c18d66f5d79c5e870d9f878f5bd4e79c5e6accf	\\x00800003baaac1b51c8bd3b2c76c6cba99bfd344a7f47b3558197a3f090efe72198d09cd8633d2dc61e8cdf565a59edad0edd17afce5f3657f16495e0106b5b7a6f76118dd75d6ea506509b9d5045d5fa2725f8989b2d1ed3ad3ded3cf1cfb2ef351c7f13afd2f038c3d39a50f1f1a7655c0f0863517ad2ea7e21804dea6eb55580afc37010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc71d14fd5dab3ebad9e47e5b5411de91846dbcab3b8bb6ea88f81ffaebb8594a4948a9b81633b0998e0374efa6f3fc99e1d49fc4924770615f52291c5362ad04	1616003706000000	1616608506000000	1679680506000000	1774288506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb103ab716d7d2b9a448587dcf9d7bd8abf424ed83b4d71bb6bd7a4cee5a1db9e56e575c289e3fd0fe27eb69f4280fb47ee117336cec9354b2c3f19a0388402d3	\\x00800003d946e8bb9318b12574be2c9de1614d0f80e8928c7a69f0f3f6794b9223a1bbf1ba5393c83d9efb767bdbb567407cb6b4fa8ef4f223298d6b26a3ae56d79ab274e22289136aada89bc06a92d45d25cbc6d248c3c5e243c06af86aa82c04f3c924730412459f910247895076e1eacadae7b9885d920212180f08a025315bd1b821010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc8ebf567d78f0c76973bb60394261524beea14f2e869ca00494ba0ab472f758be00ecc840532727a87c52d4afd7711b6171b76e619a084c46a43d8dae77b8904	1628698206000000	1629303006000000	1692375006000000	1786983006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb44f3d02b973085b229af374fe7401fa3106f7f00e5f4297f27ab9baca8a77962746d9ceabc011aa7a6ab7786726002ee658b1f494163181019a1e72a48261fe	\\x00800003c0b9b43adb293549851dd3544b70c2304a0f02d0d0b3bae3f5fca7dfa50e1f07a4ac951e7a16fd85c05a694932409d467b8353037aa367768671e9461e0b4e47591ea9133d3194811f45df509c905ed14e60b7cee6c490d6fdffecb8d7ce8ed05948e5d0ca2d66f802b2cb71e929322d695f6ca3b654511ac4ba0389a5757771010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x66a0f628a962abb2976b3d46823ccb1bfcbd4a3dc94e7478c502c3fe3fb4f4495ed30e873223a820e4cf40d33f7c771e39d85e7fe123419c832f07d14d617b0d	1623257706000000	1623862506000000	1686934506000000	1781542506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb62faa5cacbfa8efab4f54e16c778b6c93c429ce8b5f6347564b84d3f44ba05e513c3495b383ef146456d4e4d11276a834a8a7cee745dd30e4af00160d86d9cd	\\x00800003d61f79f746677aa8d273d2850ee52bda17c97aebdd5a4edad8c4ca00fe1085841df724e8a451d47a7caa8e85ca01d36413439a576c314248c855e154ecbfbd0e29fe4156b7f98218c53beb2791b2c0360c34e71c4023b847dcbccea1ef64a5270329852f9e39ecc67d9cb72e9d9f7ca2b0f47887d8e951514cbc775c4e83c25b010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x32728cb110f422345c547162fb78d4120132a0b01d575b8e383194d46e9cfe8333c6ce8a2a435509552650136012b213f065dae8c24f107f0d46e8695f4efd08	1635347706000000	1635952506000000	1699024506000000	1793632506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7b386e28aae2f7c250e7b9ddfe9b94769faa484e22bbf14b6c0a82755d9111e80528365601a74676b3a3bfb3b9e904d4c301ebe2a4946b68520144af9cc5b6b	\\x00800003c7e2466476b45a84231b2ea535ebc293f98b7cc4af00b4cc6eb649a93d0842bd72937a27c4e899ebfb52165ee0afa124cf93bac7220090c59b4a842999fa320a64c8c240b076b71fa27f18b395e5ca1453c7e24e519291ad3fbbc41fa0fc93e201803b4c4ec8f5099a75e914d95b25442a7e98c34c86a43bae559e27889ac95f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x40a51e1030d44da0e23d3222f077aa395fd02134d0884c200dee8f86ab57fc9a6b6c91155b2de3d9fbae7306117c143c6071131835305badc2d120b0cba3c20b	1623257706000000	1623862506000000	1686934506000000	1781542506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb793155a57578d83b373ea7e35ab68b3a7250e2b748f906f8bba884634f5f13f19a5137b9d12df05235b40fe7b45911ae552462db2c166ed76cbdec701cb7a0c	\\x00800003de30453de9529fc120a71b4247bdca9d8525f22752ab72ec38fe42ef517d48f81c3b04bb15f9754fe79185d612e2fbedf8b071a6fbdf6b2a547e7e50aefdc34b23560e6ffa6f7662ee728f2b4e2bb0d8da8f9dd18749e784608f64649dd2ece738a896d28e255c38a25ba902d77371953c71f5abd827bdbca9061e9d3c800fcd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6aa3ff80b1d1828c7cd2aead86994ff00a39c607775e8f75eb68b1466eb3d86203d14ec84d879c4e72ff9c0c962e73de2b07695d39213e63d71eb196571db000	1613585706000000	1614190506000000	1677262506000000	1771870506000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb8677f1dbf7961a5d5b1e7e04eedc9403a2e6fb81d61d8be114af9775b4127b7758789ed6c5f945311d88e86a12595d6d1675111ea1b4d9bf90927de8a28e805	\\x00800003dbebee0ca4b96ac7626e5ba31f23cb876e9376ff1fb17994f007cb69c1c4687a27e95e27d50dd1515d55fae0a39eb22583e21520b2c0a4f21eddea7db6c7044c501e483e578a7b4a34282faa43cb008ac0d38bedef8bd6c2533f69d2b608a9f4a3799605a3efaa7157412d69911242eb5404748d4235da2a755db4d3d71ad5f1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xb99fe8a87d3f7c989065bb08fbee34ebe83001d6355eeec0a35a6ed3d1db15b777b543e9832a75536520b5a8b8ac9590f0ae9bfc3f0b6a361d93238dd30c850b	1629907206000000	1630512006000000	1693584006000000	1788192006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbc57dc44c5d6677fbd935d63baea393c51d2996ed8b8444040fae9e6984eb915db433d8da11ae670a2e2bf7493e50408490c214696177affff4ae6477e8bf888	\\x00800003c0bc675cb42edd36dd224d3f9d81631efa68d7049b7e73a6d2f67d03881972a03332ed4f23e12ed9129a8f32e72bc8ff6f9472743830efd039daee3ab5139795bdd4f019889624c970dd7d759776ba81fb429e966d92d1251977d3f80495604c51cd1111a685e9f6798a58be0621118a61bbaa7915570fc903225bb8735f50f9010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x35b26608330b9e94d1f043bd6bb0a31d6184c760e2536de5c37b75296720cf600585b206823064c43b931bc72aae74dceecfa28b475d863b49c2d37fc62cef02	1626884706000000	1627489506000000	1690561506000000	1785169506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc437aa7d65aac8f758443a18afc5602d39ef2ea2d9e4696768efe0e1ba79eccb80b1ac2b98375a809e3708c067df7587d1ec2857fc51a3e429bebdea05a0e25b	\\x0080000398dc036886daddfa04f75a96055f3f7c31d88a289402f8f61e3cf67370423ea8b1de9ec4fe77d8aaa454a2ac063b3920b2aac8cde0ca954c62f0ef2e46c56606860a5df10f3a76e43709d71ebe7a81004fda9fa5007fefb76ed0ba6636517493c198893d0935026177c26e37f5116936157fd812c56f380e2d477d8245bc1edd010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd14ab3f31b41b6531b0a8e292c0d08f2b9b20e70d5ad9aedf93750885b695c35d55e3b4bbb71b725591da8e8e7c37e93fe66b5cbea39aefa04441b4fb6055a0a	1638370206000000	1638975006000000	1702047006000000	1796655006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc5391c10963579b0e63ea1e988b35d5f6cd71e08a91e86ee242e2c45ec35c2647a442916b1fb2f0076cc747cfa1cc3da64a88cc6e2273d62d0f889e48a6f4c1	\\x00800003c3004c0df278b308b5ef2080c416fed0e8d7a1ac301e0eb3518b5b11df77fda531bf851b2954f3e3efc76ba261d9f78e0dace5cb3cca875bff94e1bd6082c2bd10b24ebf983d6111026d762f74cb1abb6aad6fe33a3c8b0e7fe1164ef078022c888caed3532f209f853115004c7846b7236f58b74acf20487fab66865a5cb2b1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x9dc41a3b4939117c814bafec7ed995da865ff26eb95f45499a518e0ebe8cf53ec94743795ff2724ad5f5f10325b25460de7ac6078bee409dd9fcc8aa67270101	1619026206000000	1619631006000000	1682703006000000	1777311006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd07bc1077c147b9a046a05724cd27cdd01c926cceab3c1f0d95a918128c2781abec57cce52e40878d3c6ed3f9bd9f2575a1133ab7b26559b3c9201c85513ad67	\\x00800003d1e57828d02a79edc532d24660433c95b49c606f69d5ef0031d21cfa5bef2b5b3987c8c74d38f03f3bd0f301f9cc63c0c4d47c1936bab2d410ff4083bdc8b5dbe8d404978c5555fb1723680973b076f2a72e5c3c71e7e71024db74eef549173357fdd24b52db419cce2ab2d9f9b29e8694168612320bbe0f258674697875c183010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xcc6aead9376cd205ca22487226aecad0172ab017ce0a8f06aee3d46b11514f9eb0ec0feab3622b83ef548a7cef3f43dd2ecea140803df8a3a08e229792cb1d0a	1638974706000000	1639579506000000	1702651506000000	1797259506000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2bf2d8d2e09048cb98154d3d989ae35bc67de5609b74406f4b693145c495573192d30dd2f970684215f27b164cb3c3887115636ba52c92cc9e8e2f998c572ff	\\x00800003ba62a24518ce575695b027d282a6bc2497c66b3ccda3eb0ee17649ec9bfe5df1e1f0dcea5ba9fe55d73cd8c5a8f319a1a6c0ae70c6936d8b3d59d58b8e90d9f621fbb7a66aab8a906540587c23f4b238911eb28a30e8e6ce972318d3d79ea91aaf027c5a00ba2dca330b9135f5050d520a610ec6ef58fc4b3e1343f853d126ff010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xdeeeebf888b761c55c683a5ccfe271fe0124fc9f92d231efaf2e5bf589efd1647da2d9a852a454302a128b22d863714e5eab75a387c0fbb09f87dbf1ad14a10d	1622048706000000	1622653506000000	1685725506000000	1780333506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd3ef46c83887abd96a8f961bc98e5aa621413eb389aac25975b977fb12a94fdb6a558752926e275e350db68641e71019957c1a931cf27989ff5c8207a65b0092	\\x00800003c973eda12414f479de841041ae9eb26907171ff4d9a329072678533662ee59175e7c59079fd9f406a6babb82924882ecc6dbaf6aec49145f74202076a32ddae4e2d80f51120881bc0ee20be5c520733a550ad7a5e9d1fe3f58c63e5feb528823c6d6e657244b6d444c4566e3e037f6c6ef8591a180fc1aeccd8fd20c6bd7314d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1fdffa7340366f69a0038bef4707e31b846a43822f967f664e7cef4299f2f95de89ef9895720c01a7c371342287e33daabdbdaa02a46b838573fc6437ee94e02	1627489206000000	1628094006000000	1691166006000000	1785774006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd36356b62cf8a58e8b8a682e00930817fd03753ee03b3ffb960c57c8af21647b65843658d9ea2d867e8ed725182a79b352e25066908af56f7a6808a73be1855e	\\x00800003a742340964b1694eaf1fe6e7afa0ed5e163bf8a3a1e4a0b5531ec3b21b126aae64966d4eb3a8dd9c994756ef3abb4fd1d331207bddf136125d703908a4a94b6a7b705a5877918aeb52de62c144aa2a95a2802916706a956110b16a4b377727fccc52be95c6204a853daaffe7e55028e46cc334e7302f8820c25e0870d9cb4eab010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x623677db05f73813a96f993782d0ab73398cc49bfb6b5cb38388dfab3fe8bcf4de3e7b597061684d6772eee35cb2f1c6c744f0349c05c60373adee0d37c7910a	1634138706000000	1634743506000000	1697815506000000	1792423506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd4bbb75d9b1ebd3c868f53a2b1fe51b97ae4929508f941564684720db316898b465a4b8d5b093886532fb8ae6d9f7092e1f790472f7c95ac47b582e049feb8cc	\\x00800003a1a95cc8000678a34cc21bce69e7c4d585d20379a818d7eeab64f0d0d49e09d3615df3e4bac456aa4d06c8a08650299e15408d003fc1a85ab819c1d61d4f633d7f88ad09a3fe4dc9f7207673f08eec5739967f2450dd4900adab8e13ae468e2d4e6442e730684f47329d1f8b94bfce74463ea400a657c7d8d0d56f9c83aaee15010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x863383efa1ff65255e4a767fab513c195641226b7ad8e45c8477be76427ba7525e73cae24dc53004beb23d83b7b38211cae68b7887c78629ada56c3181a4830a	1614794706000000	1615399506000000	1678471506000000	1773079506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd47767b678bdf4dc3586c3d8c7cf335c89089cbaa68d8a8f9579baf07b70743f3be457c61ab21124bde7434e92902f6b6b5a70872e9b781ad74aaf2570d1cb5b	\\x00800003b2def16ba57aea45d7307cbd56e0348d7e2e60ec5f6f76b3192ccf10f945ab8690ba15ea7017b22ca81d325e20ddc2cc2953c25ac328250c1081c2b039da522824e05e2bf737940162dee60248135769e8f2f2e8191c295773b7428f1f6d8cf6ac4a8a664d178965b39a572f9f474b001e210be1db333a9481396da8be0c75cf010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa7025fc814699ea2fc1c7179addce36870183b8015f7b16beef967892e5d9a35e837f3301e6eba282d2a21bbb02aea0d7d3675a8a9a3175f0e38fa643c345408	1627489206000000	1628094006000000	1691166006000000	1785774006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd553a34182655a9f74b72ef8af44325956fd1ae84435e6e007cc3a264770955aea1a39789640b8224d568c80f60d5d10e341dfde1c62b6f5abcdde5a5cb7206c	\\x00800003e528c7f7ec5e2f5c99cbd4506500c36daf35e3d864ab01ccaf67d42407de80875e9290151529bcc7d3a2a641c1a2cca9e325711e19679879b1dd9129573f33c9556690426068f83e8a20bee71e19c80b0a5fe58e34e65d70ff74822bc0985816d9b23f4c5958d083f46e466bc8632aa986cf312d4c6c3f652e70dfc3303bf74d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x24ce1968ac582f37168cc8bc9f674b8f41415d7edc5bb6dceb3478ca869ec42ab38d7d33ba5a212f412b76d345215edf61d8cc0444ed35ac035fa40fa70ee80b	1612981206000000	1613586006000000	1676658006000000	1771266006000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd9ef7a1b18830654938d8b16c54981571fac570130674c32eb869a0106bccb862d4dd33b15d3e7f55d5d244d6f12141dfb062c2ae5effab8b099734526e65f7d	\\x00800003dc2406e9d8618463f7bd49ce269a4b8cc347899d0f6b524549fed96627915bc3877a0e2f4207c8f429a924f68b5033ffe7e2fe2bff571f53018716796c70f6521e50b70952f7ca5ed72625606e906d427246b345fba7fa96ee4aa94b3c374fc7964b8306c1cddb193cc159a8a4a9da33d25b8a7ff003048dd1e7c97a5f9b1381010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x8abfc2530f37133058b5ff3e5f21b10618dd0615be19694b1da4ce481c167a99584f70767f69bdcb0119ea8b30adab02c9473ab495cac5f2ccacc8f40735490b	1620839706000000	1621444506000000	1684516506000000	1779124506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda531784d59f662daaee04c3b1f143ec1897d67a1d1b01b3ab2fbb8239877a1e9557393b79f8282312260dccfb5b217af03e2ace251afc6852c75509ed4da05a	\\x00800003d8fb5492f3b019d070f8da34563131cfca5c1ebe1dc91e0a9ff853acb472d24d7c0542a564573ce40fc8686436657e5d247429cc899619f3bd486964b3f5a19fb769476ec4afa329335e7207336517cf550d73407873985aaa17a08cf96137041266022529e968a2db858e1f5dc68e4adab2031aa5472fda4cdd207676d8fa35010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x7f8748f7cb5f9e2030e4e459a72f7898a2df1ae2927087c6390768b7207397d3c294204deaac5d508641a10a20e2a955491407916a9ccd76a6c2723d9a1c0d0e	1614190206000000	1614795006000000	1677867006000000	1772475006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdb537a90d00d4132564020c871d75ffec616e4f191ed566fcbac235ffc889df19c22be1793198a823e9085741aad72f2b7a6f68792bb881966ba0c40d7c27b4f	\\x00800003b13d670d02bd3ba0250ee326cc01dcfef98bbc257fd09465953f32cae538867388949ed5e1b748873775aca33c3a56f824a473d1892422a1ed85b9d3765fd2a2845054e484e18409558d6a3ab744ef07a56c6eaa25a54ceaaf95cd8688b22fb2481eda2afbaee13b8fdb5244c59e0ab1d588d935a292e3fdfa5047a74a5f0951010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x49187484321fb439468a51ab68a4eaf0725d7f4319c7e8af55b26f4919be6147187082a7efd05585b59eee8021d004609de6dcd2dede803fb848bf1c0f50c106	1608145206000000	1608750006000000	1671822006000000	1766430006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddbfc5c5798088ff1c381196886f9e39256a0fb8b8f4fed8ed8a19e390c27c74ecd93af89a8e664eb41ec2ff4faf9d6eb69154077686b13cb698d198ea4fbdd1	\\x00800003db7af257665cce70994f3da0ad68e8550af8b2634e7db149680cd62085c40d3b41c6687959ad0df7a465fecbc4ca4a54f54f8c85f91e2d72debe76eff08d97d41cfc310ac71ac595b046a1afa9786456e6fd6d2a6ce16d8b1658029466356eef7c0656935779d65321f3a6f5be36a4a95a4057712ee89de9ff0f9b8ce709b961010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x99fc62d06dda13fef52bcdb5e3b03701a4c13cc6e9d27aa9550fd898f6c1705dbc80fee0e7bf43e521d9a5c54ccd12f2dc39895c517e118b215027f821cc910f	1630511706000000	1631116506000000	1694188506000000	1788796506000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde8326dd59127b83f5c80715f8e22db75139dffa615f2a61e92be56e73ef6239137075851357b770a1ce86dab82624206258a55050ae80c32e79901ca3ffad37	\\x00800003d67239406e3e874f394b3e6bcbdc9f5fbae902f853e3d1e0d427972b66a6d62fe43abf70033f239821d2bb7f93acf791210c66b4e88bffc0e10b8d8c95fea71d72cf71ee7c6a9ff96649a5abec60b7fc39c1f3032f3d4f4865dc0a5a6716fc22c5f7cfec8f074d8ae007687f5362e14a105ab6ebdd1e0e2e3b63d18b237e6e6f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xcf9133d8e666e455e887a7973473633519fc13a5f85358d3f622baff2034bb9de54b6b2ef446b02a18149a26811efd5acd8ef00d02ee0a8821c237b287de2708	1612981206000000	1613586006000000	1676658006000000	1771266006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde4f9c83a448e44729d475a7e3e5b33ff7258f0b528bb799e2b5933bfcfd6e5745235f5bf7949fbcab3c6948e15202685be4531244ff215ea5c74c3887b23f16	\\x00800003c23e61cd2048a06d9fb57936dcdeef3f33b381ef95f34b4fb0be918fc8e90ee9f6e2294329a9b1f20af8af60bf35229905acc15b8514bdf9cbc64085c03d6ca54adde7e7dcdcdeaf51d80f8c57154ba285032a68750cdd65a4a84a8b8ba7e3469fb98a118f103407139dbd26994336f7b36f81a2671a3dcfe6747f9f84867d1f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x6414f5c0c633cb8f67adc2447a0b8e54aac5fb88e5344cbe36d5529d9efa3d42f21bf191b351f458d5b4f25a0be24b8816e7fb82633403c8c12ee293f13b7506	1632325206000000	1632930006000000	1696002006000000	1790610006000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe8e70439bef56e38cbc24248803837902e13874298255e4095e7c322c12227915194f934e32fb5be130b49a0aea6ea2bc830ccca24594283819151a8581ebee6	\\x00800003a8bd73c1e899a2bdd7051577a6abbbe871a0458065070b792aa764197c30eba3071a34ecd0cca6cf133e1aa3dc9cab3d96f1eaf15160d5655413daf98f5bbacd427f56bb3883386d1711ab01434629f289f707142b6713e51f88309754f47f287c836b5f12eb81cf165b2f862a76706e2aa7bb7b4dda666352a15637bf395a47010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xcef8dc9a8a73fd1a9f4cbe3e85ee3bc920c691323885d261138489035d8c4b321939a266fe39603b830acd9ce316b2b576bcc67b8df21e1278b5f79de95be505	1614190206000000	1614795006000000	1677867006000000	1772475006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xed0f696051b1bc1b38809a68d6cf322e7725ad794868320ed48db470dd08574401a491858fd8b5b154d6710c2732f14d18fb36ffa679f8733bab6d0b6a201e45	\\x008000039a6218d971984ac176b393d97c4564559fe17ec405e2cf223a0bc1e66c9b7943e8f3add3f3559bf14ccd7285812df1625a1e2c7b5a85f0d3b3dbccd4589ad616e71612434b3955f2cd9c71d73c45a97e08c859b0a932feafd783bca225445d1534ffd6b0cb8f25bed673a2400a1eba29995ff65b7825cae36717a87a780d998d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x802314520a310f90086a1b0d1c13c097a951c1d9e0b53bcb464889f645569a8f6623d9000583873d259598d95322868c3d26725279d3f59f2121b92c72887108	1621444206000000	1622049006000000	1685121006000000	1779729006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xee5b1cd6bdb7a25ca6c4e283722789b3d66e4d02fc9f1bfaa3d2cc4d7a5f988915c0d47640e863ae0d051613bf4f2335f38a5c496185f4f6b7b185b858c527fd	\\x008000039c082b2355ec0de8d75d66a9c3ec52f07e4c08fa861bdaf8266c84a88943250a9e14b40deced7d2706e17df43071a76cfb9cfec6f4e8b17df71d396dd4c105e6510b0f36e9a18f24544606fb99b9361278f85dc197660e012a07fc368c38103fe80c3491887f59d707bceea409627ba2e264f7ff6caff6558e42b612a735da3f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x21d077baf14c33ff413df10d81f5032b0e304137d690c9b64de58d7f46f582bd5c8deb7254c53cc0b4e997183bea4f80fa4d73c38585ab29660d6de2820ef501	1633534206000000	1634139006000000	1697211006000000	1791819006000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xee0f1547b97310be4076444f5a2cc7e4a872d665aa0e184ceb8d545d42fa49da901f11abc3a5e0806e52f5a7ed0479c7f4826871cf8800a335708220d35ec514	\\x00800003affa5c7ed7346d17bde582b528561791730ba49cc71cc7b9bfcf8aa7e7ae5781d515bf7e377df99b26dfb2f7a36dde06ca32f809a9eb99cf9b50ff59ac4a9ba3e29155de6b5a58e9a677b51ba2c49477bcd7f4a8f21cb0ab210471afdbcccb69fe15e51fe78ca37f0bfd7debaac9fe4368092e304960f8ff2e2bf005189ba54f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x711d1d1978d0d4fba782be66e23370b3100da76cd56e83c895782bfba608705e1b53ea76c7d5f204187a8c04c1b6dab24e5ea7e9396960fbfd4ad459fee72006	1639579206000000	1640184006000000	1703256006000000	1797864006000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf1a744191ba3e8f81f90892116e20cb25306b12c177a0f102209fa6e84d1e1bb4324659fb8e993e1c614a82b85aad8ad8767c915acc4d1e51acb1caa8086ac2a	\\x00800003df1d2d1b404978d6dceb2f789eca5c696e778790fec43b9b512a21486050a9939d2748f99eb4f34d49c52e9238ce1d6cc18f74a664d3d073fb429cc0156669f18a5537a63399283fded3c0f45e6762626090824f8db22c6f713f945d03c96e129aa35c8c653cb2b18b9de0523f4ad53895fccf8fd6ca3ae161313c35c634439f010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x1e115fcd411df46bdef1f8fd450a65bd2e456a234286aea8079df6d8c145b70c4897090592acb60ecc35d0df6fe7e595f6392dced48c9d4f5d4c2561547d4d0f	1629302706000000	1629907506000000	1692979506000000	1787587506000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf3dffa8bc708c2125d8ea69a677671cddc4cbe0285c6a64dba1a53388c4447c53612b35877e2ded0bb8b03e5dbf936a4c0ffe0080bdace1bf699b4edbcf7586c	\\x00800003cb041bed0aff46f4e1d1faa40c2ab89f20283c845f395b25a961ff0f76f82ba6abe0e7542bd0d9fc35855e3908ad67558fa49a6fe4de7402b4ebf87ff7a02da02023cb8a459e38f1b8d1e379c0c65bb9c175f22742dc49b6e395bfe668c377da20d7b6a35f1ef1387bf3a41bac7cede0987f38733ccdbe7b7a9fa9cc5995db7d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x39e8e4f8439c6b231412388c74ea8e1d2d8a3c7832cba02203c6de5462ddea4c4235180f5318ede1b08938dc1f47dd7a5591eaf64b38a18eb7a4764f788ac606	1610563206000000	1611168006000000	1674240006000000	1768848006000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x00800003b709855a842c7b7fb034c74b8498d0ed5256d45bf2aaec6318185790256ffb44c4cc538e65771917c3c10da2eb4b121c4ff9ed78b16861f300aefe97850c4838d92ca9a1db2ad5dfd2c47f9fface2f944cac0cf86d156686daa0552187fc56a02849c61c53cdf4a8dc40432ca0c6a96c93379751bd5ee7ae42fd62ac37a54e41010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x672bba49cff91bb51da8f418e2240113c4c3bdf7789a7a42e8eb140e165e3e4fc995d7992a12ab515209ab5c0ec1240e3d853874d0d2dd861964c26dccfdd405	1608749706000000	1609354506000000	1672426506000000	1767034506000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa075468827bcd1dabe509ad79d852db41a4451b34cbb833c0a73f7bbfabbc142dc1e137d76979a37cf1dc284c969947299c85acba00a683e88161431611fa46	\\x00800003d5fa2c2ad0253c3eb907e69a0bc07399c722bd651519c4d7f1c93b3025c62da978846b7b2ac90631a2ef478ccb7a600dde881ca5c39eff479d056779580546dc99d0bcd155351cad46cf1020c99a1bc4bec79d49032c3480019356975b53412abf07d93ad6fb0f181f01823126539cded329bf42bb4ea871f56422a80147c22d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x2e77c06d1bbea92b18147fcf851fcdb8c618e0c9a78204a3def0e96c8274e80414a9f7a25ab27e6eb665c0d314238645e042197cc9545497f7b09f3280506c06	1622048706000000	1622653506000000	1685725506000000	1780333506000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfcc7a31838f79a2faca10254aaa2433f98a5995ae3c85388963dcdf595f48db6697925d497cf46d4b201c0b4b96bd2465a06f5aa09ac2873bad9ecf5725ac863	\\x00800003bfbf73933f4436e5da93ec23dc53f362b7db86020c8bcd6d3a55d34b82c352f551cd834ddb817a38f42b565f73a9004f60d54b30307ad4d03441fec831ccfa2bf698c2ee155ad1bba4a76dc2e056c35581e7d62061599f877e01af1103fcf8ad9a05f4dad65c28c77d2014e8eb4a95b0d18dc80c01a69b6c3cc62e6a53d4375d010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x89670a8cd09369885aa0589e07eed7c629b6b29cfba00a0910af0c27ca537af11bfc503b0ac79dd0ca75aa8d7dd20337b9198ed3b10f2b8201b8aefbd666f807	1631116206000000	1631721006000000	1694793006000000	1789401006000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfc5fec6455904b5f85140ff7a7cff10fe40cc3bc7375a9758c616151cd5ce4203bdb5c540e869a916fa2ba0d95381039aa4b5d7c9cfc62de9e7172c6f2a85b77	\\x00800003d7cbe5124f615504bb2f6a7142ef6e8346e3e295bc8a6d3aec20e17e9eee4f102519c1066117406b244e7a8eaf37b26629a4ce5c88bb5ab6b6581ecc7247ad01972c633b505bbf776aacb9495eaf7f31dbe194e8a0fa5cbe42c4b2fb76a54c832a3c995c2a37d700ad690e9c3c3ba9f766d089c3598ad6d0adb175fe945848d1010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xc70592c98dff200cca2c85586c703f2da93cfffb5a3812f0a428e731aa26265c543ffaa809f084b0f9c66a9acdd9ebc5ae6de30a28d7e3fcc69cea8c69bd7702	1633534206000000	1634139006000000	1697211006000000	1791819006000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfddbafa5cfa12d20028c1a73e2830647e44af19bc7dd321fb438400c1e3c8d087c3f11aaadce6147823b638ca9ecc89204fa9ea66373502bf1b202526988fceb	\\x00800003c9eec8951d602f7475f3014b1960f8b75e61edb7805c5c944f2d7162bac77692d2ced6d7f5134d43ef59222881682af55ac94d85725b1fbc840d3e8427d3d1b3ff59bab8229f93ea641b641efaa52d4d7683d1b35fcd791c574792fc590fc598b633b8721395116b4365d9856c3d6ff0b12178ff587174e28f9b08bca3358a63010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xa4f726829f309be1bb63ca3c1e97911dcc70ba93bcc473c3d8fcfbc585dcc500ee1390293acae8408487f19689dc8a4509bca2399586cc3efb093dca6d08f609	1631720706000000	1632325506000000	1695397506000000	1790005506000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xff135fc6e1a23c8f89585fac287ab6859c8ee0974e5c1f36b4568ed50cd40e49f7ed2234e957ece33abcf26ac328f37dc5d9ccb48758ba6b1d1fd2d9fe80aaa9	\\x00800003da67ffbc9582eb8f88ef4e6bff8d84dd9a2764647c5d3300099302e097a9162ba58f08ad64b868a766e76452991747ded3b4ada2a922a62022c24a8b65f4b5e743f9251f4bdd9fee8903c432a80406fa70ca02ac47a40a0c36960416dc17e9253412769b88f321f60d53d781535a7d695effa84bb95d82583f49e3540b5b7721010001	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x482dc4ff035a0368d3fd174f4e52f76b6b68eca022c2ef9ebb16b068028ddbf574f9f15717d34b51031ae49b4ded8ed07b477c56f77e39aed775502dfaeffa00	1620235206000000	1620840006000000	1683912006000000	1778520006000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x9459cd3232fe732541244112ac303f3ed97e4f10861e1b93d74af81d4c54c36a	1	0	1608145230000000	1608145230000000	1608146130000000	1608146130000000	\\x49529f51bef8d8201d81cfe80a0c93c328318fa94343350c9f7bd1fb2e44dcf5	\\xde2ffc24baefee52934be414c7993d1147881f92557c9cc7f7c562c380f50f8a0ae425b715afc6d1652061405f07245a4dacda71c556f92b94d337f18e223da1	\\xe77c085e0c372fa8de5f970af6917f516312950a1fba558e47de379b5b4da39390fc7ac368304f9b029a9e2964f5825ab6d860b0cfc76313be95f5cdc2f842f5	\\x311e558ab15e8cedf0366a88e131f6cecab325a547836ff674c5716a90922fcf3cd2c8b1612aaa75b807aad1697b02be49641c058a3f3b1b80632a6d5a1df605	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"TE5Z9N80RT4AYNX1HAPQ8THNE0KMKV39YMK13Z6GPMDYBZAHMBHTE6C85WYB8546EY47QNJHZ3GXFKTNPMYQ6YBJCY9KHQ3H7S03VYG"}	f	f
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
1	contenttypes	0001_initial	2020-12-16 20:00:06.329621+01
2	auth	0001_initial	2020-12-16 20:00:06.353811+01
3	app	0001_initial	2020-12-16 20:00:06.41153+01
4	contenttypes	0002_remove_content_type_name	2020-12-16 20:00:06.434737+01
5	auth	0002_alter_permission_name_max_length	2020-12-16 20:00:06.442113+01
6	auth	0003_alter_user_email_max_length	2020-12-16 20:00:06.449681+01
7	auth	0004_alter_user_username_opts	2020-12-16 20:00:06.45667+01
8	auth	0005_alter_user_last_login_null	2020-12-16 20:00:06.462274+01
9	auth	0006_require_contenttypes_0002	2020-12-16 20:00:06.463643+01
10	auth	0007_alter_validators_add_error_messages	2020-12-16 20:00:06.468783+01
11	auth	0008_alter_user_username_max_length	2020-12-16 20:00:06.480589+01
12	auth	0009_alter_user_last_name_max_length	2020-12-16 20:00:06.486664+01
13	auth	0010_alter_group_name_max_length	2020-12-16 20:00:06.500179+01
14	auth	0011_update_proxy_permissions	2020-12-16 20:00:06.508185+01
15	auth	0012_alter_user_first_name_max_length	2020-12-16 20:00:06.516584+01
16	sessions	0001_initial	2020-12-16 20:00:06.52183+01
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
\\xaa33eda4e4006f9ab4bb21fd99baed995c8272b15d9d01b3a0463a89ac6064e8	\\x4c1127b7d748b346e9184cfef67ff7443906f888c4535bb92c2efa93234b2f5caf1860d02fbfd2af0802721c62c8e1b2ece5453635ef16062586844c9d19e404	1629917106000000	1637174706000000	1639593906000000
\\xf09021902f8dcf346e5170a8581c6aa3816a87ddc5beb7a10872bbeac5fce2fa	\\x04b34003dd6f8ecb31922e26a5e52d499f0be48289f2eb8be3f9a401e04577b436230128e17f37f9560df7b3e154ddd3012eaa0c8b49b470633d57b2e4441505	1622659806000000	1629917406000000	1632336606000000
\\x737a37fa35fe72de03d22c99f899b759a3fdd20b66ab51497d19536eec3874f0	\\x4fb4ea2f41e72f54ed91edaf2baa6a0bee6a9c6da03c5d6ccbe1fcf242f9bf2d21d9ae993d8a8f0744238abb2b45c83894adf22f5594727dfd1ef02683034f07	1615402506000000	1622660106000000	1625079306000000
\\xd93e6ce1f6e6b2f5a22eafedf17e8e5d68a8bec77218e2e20734824dd592b711	\\xa4e2795c603138535daf306833e77153b3ed6542fe6c7618aa94db7d0be9a78b9a4ccd63d86f1b2fd8d3a06ffe145ced805a478bebcc10b75e4a12801201a802	1608145206000000	1615402806000000	1617822006000000
\\xbb2af3383fe076d0cbff70cf438f1e1534a442ef6fce2e17598a5f0dd27fc894	\\x2ded4524cec91ad20bb8f96b6dd1377a6c6a160342283d69e8672da71c7eb6ec101a5e174f0fa7e50a450845df232196f99d9288f451a50fa6001a840921d40c	1637174406000000	1644432006000000	1646851206000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\xc6150d5f3957858bee8380198b1e6b5b05cf4da596f4fac05a94f261fa7de20d	\\x41545dca6a5d61f31920dc7bc487f4eeaa2e41c01d4b87c82ad58d5173ff1f720d2ce2c65e5b4d0aecace98e3334f28d8e7e82f4978d5c3256fcfd15e4f9764c	\\x415161bcacf4c0ec162ba1ac8430e18ea4b1c87cb20107f57ad226d52c8494d33f94aa378a1abee95e586372bbe427a5da29b2dc91285624ba89126cb79dafcd6f806ba077ddab9f4ef8edb360165957404ee5cffac9269236eef7e0a53660a07428f150a4383674e8570106bf2f62bdb2d4a8edd3cd9632af8b06f6a7dc634f
2	\\x9459cd3232fe732541244112ac303f3ed97e4f10861e1b93d74af81d4c54c36a	\\x24bb402ff946677c5803ab31e02c1202655a8467d98b9aa18baa2f9ca1b124da2da25a6e23bace9a3b5ed0a6892ac4bf2a5c6215c6efe039f9cee19bd0c9e56d	\\xa79b95474f2be7e224ce2d80539c98e3e38f76a1941ad885e239c3b590ab354a952914d32b9d766a70654fc5d9627f5aa1e65822cc82b87b6f440d78f46c42186308a53a563ea441dde14cb00dcb1d52835da6193797c9bc34021cadd86fdb09ce8f02be4a16a9b5e9001301f1ab08e20b7f76af51fe3a64a1898240f6073c1c
3	\\xca70090875bd840ac4572718a82acc7dcf4f853432ee5a0a8f217d75ab35b11d	\\x8a11c7f90a44d3d5b05b185f1a6d4b34abe1bee88509bf838385c2e5cfd0c0c72af08d347d0cf0e7845529d74ca09138d07e92528ebaf37700e5eff3b25605d3	\\x6a1c655102c74355fb393630b6ec38a0bdec27024799b86b0806864f58fa143e58dc29b3ad64ccb8a89ea887892f0e1d9d64a14da9df1dc2974641902141767060fc11342f5d005284150e95246e7a9225d15a0fd646e8b5990252191d3bb68b7050de84f9f228b2e4bc139fb34df07d869d56f8cbeede189aabf16c853b3202
4	\\xab7b3341c0ebc8955e0764fe95e0d6eb00d16ce67cc8e426d074cbf0f2d06b53	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x9cbac7ea545088511f84690b9aaab1826cc5ca19bff8cce42fbfe76683ded885ee9ceb56da729e89609da941b299882ae600916f449b3903d6aa8a27a50640121688902c3dc75de498f9c6a5d33ea551d119ce3e52ead924d0bc2feaf1c600e3c753b22f54edd3613d16bc2e0bbcac9cf253090717d355834638ac19bdbfbd5d
6	\\x06cb25e6f145d392459422ef96ab90f28bbb8335afd091caffaede1863a3d3b0	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\xa7cdb6e47e0b86865e68649065b845aba97fde80d20c6b40ab3ce8bb989f8be04dafed45ced11518794d13d56a89301910ed0fe0332a97b7d5cb47d1332e5ee8fe33062d42ca900950653353f4a92814410564e8e7ca8943b8a3cd2773d42baf12e66ae360f4d06c7732d90c70ef5ca4bf3a650c84f6e651cceae6bff8cbcc61
7	\\xe47a02074396dd54e74a4fdb449220c860983dd5b8bb91ac1117febd06e25a1b	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x08d8433b1ba837c4c3b100f1b408a3de3a8c28f97a3273a18f5bb0eec8f60fbc6949b2a7ce5ee954408bc89783b90d127f41c1dff4da867ba3df4b37e25772d6d75eb818e9dc86a1bfb91e29b0b168574a3211a1532972181e1d71f5b3d8b5edd30600a0f5b01c3e6d39616e63f2094802d29919cddaf420fc8f076e4f7813c0
8	\\x8f8f8243e9c22f0a479c2bb0eb7336ef8f40cd428683b7dc22056acf734cdf52	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x12a4e34270a9369bdd56f256d88d538ccfc9bd958c2e673bf6eacc30db8936550a8fa2c92424205651b8040798a4ebeb9afd0104f5bcfdf79572c1baf28c9fa0770f818aab5115e82ad49eadf9887dd884b435184f21ab23571f04b4647ef321fb4d67913fcf61c6e0941c8bec929a166b74d556c9511ab36c6dfaedc68db16f
9	\\x4ad809d656ee3cbfba4e955e0b3651b5b23f385beddbb05502a36e75adb2a9ff	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x85aeeef28b5fd1789251559e44d95f8b3f8e9918d4b7d4bbbd98f4e6df63999b6f370ce8cd6f674b85ea59c7032b1342facc84f81597c714e99a063b4e61190c921ccefbf28be2f9ebca6a6517affa8f4390fe54aa55ec86096759d932ea4e15d3f5a6bdc502efcaa41481b7f5cd954b3d9cc7ea79a7e193c0b1506bc4551f35
10	\\x5e5d8d639b0b0aeeb0c4d65844eeea86032757ca43e661f35bcd41df0e4a0cb4	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x30e67b6181d2ee8ea5dc5517432d22804a1a4af2ed42df6b8fe3f745f6c504c78056e36fe24f7ca0a8f5c81e200b73c5eda243f7ea0c05cc677479d66a1245a4d66b185bc15e906e7c8bbb1c4e1a77e278541c5a008afa06c9c9e290d4e564ac80ca4a64301a254cf925f1c3668a286cfb302baad55fec3abfb498e211f0f2cb
11	\\x7303b52eee703dad37ee4de511c478bc15b91684690c1ad3ed20a9eb5901ff5d	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x615d7712f95751d3ade5cca0196b87f182d1cf7f8ab7edfb7c453d7aaef881ad5356c90f692eb1225f93e878be97ad00684ee685fd63e68aff6408d50eb60d8f4551692fe370b8bd460799c1408b8e21085eb487c3e1b48281a49a9ba0ea24d97fb8bd07ad418a57aa864cae4a9b06a8d3ea8562d4ec1ca60331e8fc1f32b317
12	\\x2eab3b1b08f1dd1c57f1c5c1a91cac3200691bcd4b4cffbed3d2f296b744eb75	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\xa714df1b35c0edd94189ae1ee4ad756f49181e27211bb4ea6c824180d9fccf64b819064658f867e3dfaec6b256c51a9e9cb1623dac959f3880f034202c8bc0bc37167c6a4092249e196215918975d64430abd6b21a0a3b2531e620fc5077006df9cf37ab46685159fb6d92d33685cb30b99b707da2c54bb39f4104dfda484402
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xe77c085e0c372fa8de5f970af6917f516312950a1fba558e47de379b5b4da39390fc7ac368304f9b029a9e2964f5825ab6d860b0cfc76313be95f5cdc2f842f5	\\xd38bf4d500c688af57a18aad746a35702749ec69f52611fcd0b51be5fd51a2e3a719882f3cb4148677887bd651f8e1d7cf55b53d737972679338dc713e403dfa	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.351-03Z46JD2ZTGJ8	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383134363133303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383134363133303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2257585930475147433657515448514a5a4a5735464434425a41354848353538413359583542334a3756525653505054444d453953315a335452444d33304b57563041443957414234595031354e445052433252435a48563332455a394258454452425734355838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30335a34364a44325a54474a38222c2274696d657374616d70223a7b22745f6d73223a313630383134353233303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383134383833303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22464b525158324d5834325056345152393248464e5450514435425043415831525051444b593359305a363931454d464e424b5947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2239353939594d44595a33433230374331535a4d304d33344b52434d33333358393844314b4133345a4646385a50424a34564b5447222c226e6f6e6365223a224531474d4e354656344b48504433544e39594a4d4d365a474d345a4b4757543038533959325145585246464354504338334b5047227d	\\xde2ffc24baefee52934be414c7993d1147881f92557c9cc7f7c562c380f50f8a0ae425b715afc6d1652061405f07245a4dacda71c556f92b94d337f18e223da1	1608145230000000	1608148830000000	1608146130000000	t	f	taler://fulfillment-success/thank+you	
2	1	2020.351-00M0NK1Q2M2YC	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383134363134383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383134363134383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2257585930475147433657515448514a5a4a5735464434425a41354848353538413359583542334a3756525653505054444d453953315a335452444d33304b57563041443957414234595031354e445052433252435a48563332455a394258454452425734355838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30304d304e4b3151324d325943222c2274696d657374616d70223a7b22745f6d73223a313630383134353234383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383134383834383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22464b525158324d5834325056345152393248464e5450514435425043415831525051444b593359305a363931454d464e424b5947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2239353939594d44595a33433230374331535a4d304d33344b52434d33333358393844314b4133345a4646385a50424a34564b5447222c226e6f6e6365223a22583258534e505230524b454139564841363753414545565a4d454746434850565856345643593843483341373152353643363030227d	\\xaf65a616c4257aaa92b607b5bfab17aa7cd55f1a08a761b50a1e3b3fc18d8c14ca87711acd7df8a230b3800d8c33323343137bb4f0477346d95a8f44d7ca8947	1608145248000000	1608148848000000	1608146148000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1608145230000000	\\x9459cd3232fe732541244112ac303f3ed97e4f10861e1b93d74af81d4c54c36a	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\x477c6005b4dae45483cbb8c937baadb2a16588405f56c0918d6548f961ee48a5bcba1052902a082832163b358680d512abbf912e2020e320add15781e4f3480e	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xaa33eda4e4006f9ab4bb21fd99baed995c8272b15d9d01b3a0463a89ac6064e8	1629917106000000	1637174706000000	1639593906000000	\\x4c1127b7d748b346e9184cfef67ff7443906f888c4535bb92c2efa93234b2f5caf1860d02fbfd2af0802721c62c8e1b2ece5453635ef16062586844c9d19e404
2	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf09021902f8dcf346e5170a8581c6aa3816a87ddc5beb7a10872bbeac5fce2fa	1622659806000000	1629917406000000	1632336606000000	\\x04b34003dd6f8ecb31922e26a5e52d499f0be48289f2eb8be3f9a401e04577b436230128e17f37f9560df7b3e154ddd3012eaa0c8b49b470633d57b2e4441505
3	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\x737a37fa35fe72de03d22c99f899b759a3fdd20b66ab51497d19536eec3874f0	1615402506000000	1622660106000000	1625079306000000	\\x4fb4ea2f41e72f54ed91edaf2baa6a0bee6a9c6da03c5d6ccbe1fcf242f9bf2d21d9ae993d8a8f0744238abb2b45c83894adf22f5594727dfd1ef02683034f07
4	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xd93e6ce1f6e6b2f5a22eafedf17e8e5d68a8bec77218e2e20734824dd592b711	1608145206000000	1615402806000000	1617822006000000	\\xa4e2795c603138535daf306833e77153b3ed6542fe6c7618aa94db7d0be9a78b9a4ccd63d86f1b2fd8d3a06ffe145ced805a478bebcc10b75e4a12801201a802
5	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xbb2af3383fe076d0cbff70cf438f1e1534a442ef6fce2e17598a5f0dd27fc894	1637174406000000	1644432006000000	1646851206000000	\\x2ded4524cec91ad20bb8f96b6dd1377a6c6a160342283d69e8672da71c7eb6ec101a5e174f0fa7e50a450845df232196f99d9288f451a50fa6001a840921d40c
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x7cf17e8a9d20adb25f09145f5d5aed2aecc57438b5db3f0fc0f9921751f55cfd	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xaa94551bad1636112cb271ce96f2cf454356810bb643f435098950dece5069f2913ffc74e9bff43bf3a1ed370ca201b57632d560b004cc0760d1e957b3ee8b0a
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x49529f51bef8d8201d81cfe80a0c93c328318fa94343350c9f7bd1fb2e44dcf5	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xe6d41d956405f3a54e635deea421603f729e0bd888017c891ca35eb0a314d616	1
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
2	1	2020.351-00M0NK1Q2M2YC	\\xbebec35015ade34c8badea55fa9ef317	\\x361b34b62a4e0e1ef9c0861fdc2e2151ac83a261d6f0f3205da212863186b67f53dffc18c5a9c7235474f9a93e81cee8775069898d0b0210fdf529be0cd79a6f	1608148848000000	1608145248000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383134363134383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383134363134383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2257585930475147433657515448514a5a4a5735464434425a41354848353538413359583542334a3756525653505054444d453953315a335452444d33304b57563041443957414234595031354e445052433252435a48563332455a394258454452425734355838222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335312d30304d304e4b3151324d325943222c2274696d657374616d70223a7b22745f6d73223a313630383134353234383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383134383834383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22464b525158324d5834325056345152393248464e5450514435425043415831525051444b593359305a363931454d464e424b5947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2239353939594d44595a33433230374331535a4d304d33344b52434d33333358393844314b4133345a4646385a50424a34564b5447227d
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
1	\\xc6150d5f3957858bee8380198b1e6b5b05cf4da596f4fac05a94f261fa7de20d	\\xe83abd90d5bc41d5637f62f12746b62e6b625fc370be444485bcc11c3f56db0b9fb4e382f9e4fedf14d7d6c63e2c9a8e33da7c69aae12b37dc8bb3e2906f0d00	\\x226d8fe9037326ac12736d8bac1a593d6012c6276c76025b4bd53f4497b9de96	2	0	1608145228000000	\\xcd5c2e2f45c60e669f81b1a0681d06caf3b2f921fa0c52dbdc181ffed055fa0741165ad9a9e2b09a19758cc4b94acfbb7a9c6bfe791e28edd04eed956813ab12
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\xab7b3341c0ebc8955e0764fe95e0d6eb00d16ce67cc8e426d074cbf0f2d06b53	\\x861b7348d29ef4e8afb6aeacf8e9bb9a9f20b53ae18d27cda9a596556c4112cfe36156b34d0429cfd2bdc13bf86550f688eee80f91cdae4c0472f8b96d9e7a03	\\x819cb1486836e46c82c89bb9e8d7c9742f97b8e47dc9870ca2ccdf6a3ded9271	0	10000000	1608750042000000	\\x61f5d3f20eecbc4a96cef9219a853369683e3090e36719e75a162e68ef5214c04882eb6d698000f340187f850c6cc1279b2cc490f6a7cfcfa5320bf0884ddcc2
2	\\x06cb25e6f145d392459422ef96ab90f28bbb8335afd091caffaede1863a3d3b0	\\x297c80e9894b28e4152d7d146a6586ff06dae1e7c8a2aca22e8ea694ae545b735b55740ab378e08b8d8aae363ddfa53eb3d6b06022272fce51dd460d10a76503	\\xdec19ee573dc1dea508774e6c6dc566aeba08c7f14b92ca4635a4f8eb8ac106e	0	10000000	1608750042000000	\\x4be4b59f855940990db920ade088800c8d16e85569e360bad3cfc30388e6a37f8700581250384ef7100544ca6bf379a16f97af59d9fb9c8908d2e0de25d2fb37
3	\\xe47a02074396dd54e74a4fdb449220c860983dd5b8bb91ac1117febd06e25a1b	\\x9ee6324ffd15d33424778d0b2e8e858628129f094ab05292772017d59382b88739e5fde234463b8b769a6de289b94b7c15e24fab2794a71bd457ef029cbd3902	\\xb169064bb4f54fa32bf5ad1805436a4b252a1b3ae5d7402e51e1558b77969a0e	0	10000000	1608750042000000	\\xfbd0a92de76d580867800b3de5d5c80ca833c9457db365f25c9741fe9a7a5fb20efa2681501b9df2a2f7ded941e51e773a1ced999f7525d000577995baa06f4c
4	\\x8f8f8243e9c22f0a479c2bb0eb7336ef8f40cd428683b7dc22056acf734cdf52	\\xf7bcf3aa16a8244a70b83507214ae7c28df51a17479838dfe6f7f1c88f149fdd02480eb43ccb4a25d114377725463448ed43a5ee5d760eaa70c9abe52f801901	\\x35d6af96216e6337d234ca5bb699830b653b044c94b97ef8881e7f3292924258	0	10000000	1608750042000000	\\x44df3707623518e3ae78d0dc7ef78e8b57aa9389e0b18953879149b174eb5d64ece3bab4c734bd3d402f516e6a3c67c6526f26815e87887a73a4ab7f0d823d10
5	\\x4ad809d656ee3cbfba4e955e0b3651b5b23f385beddbb05502a36e75adb2a9ff	\\x84b25f981f431c16902121aef5322c0ebbcff42ee4e82f98a54a5d824388fa5d3b3192b4427aea01b8618584bf189fdf26ec195a26cf3e5e0debff579e776104	\\xb1198740ce2f0ff1e18e15dd577928c07b52cb6e91c8af123bd4f8cd514f7083	0	10000000	1608750043000000	\\x08221474fb75f66380825334850228b8e7aa52d8a9f530044b5c0d16c4de1edbaa371f1adb34a731699b6e5ac80a5fd1f390807b1440e95efb4f1427e81b8f76
6	\\x5e5d8d639b0b0aeeb0c4d65844eeea86032757ca43e661f35bcd41df0e4a0cb4	\\x0273cecd406e7ce800798ce0d17737502277154afe1baf7de5b996cfe7a17ee923a6c4401531b7b65b24aa4e77d252329b5cf036acce24c5a3ea589e7d69d60b	\\xbf153b54391ec3ccdc2e31ec49156fcb2e4c7b6626535b0710bf7eb81e9fc97b	0	10000000	1608750043000000	\\x254f2cf7d04d5802f5def58d149378c1f63a74c4f6fc2646e7b0fc9dc194c10518d00d5c6d0d9f428d316f96e17fd035858a0c5d44019caed38b059d2251695e
7	\\x7303b52eee703dad37ee4de511c478bc15b91684690c1ad3ed20a9eb5901ff5d	\\xa1e235798e288bb2433fc452968a9fa8b31bad5ecaaa3e8c3e2db2860608ca57d690000c22f37ec866e039ff58e75fb66543c050071c9abb7512a8d5baef630f	\\xfeb2905121c25b3ecc1578ada3c1f36143f1a530e146dd3f886d387689f81a20	0	10000000	1608750044000000	\\x15c99770634b0ad031dda35fc9d396a8e3c019760867cb4f083a6bcd5216c77291c34e991445b3e9d05d3975c979815c397d4639eab140ef53370db7c8bd823b
8	\\x2eab3b1b08f1dd1c57f1c5c1a91cac3200691bcd4b4cffbed3d2f296b744eb75	\\xcbfcd1adc6987fd181d762b6dfac762a32a58a02abdacb9aa4248c2701bf047d7339e33ddb0694756213d0da3a778e00c0000b2570658552defc9dff4c1e1b0c	\\xaefd1c96d124b92d10dcdf60044b8f2df2eeaf70e8ec0f8ee3e5938d70a52ae8	0	10000000	1608750045000000	\\x8c9f3d6ac36088d095175258f281f3767ece90925aa8d04fe9649eabfae009f9d0a957557c2a1af37a62722e0746719c23ab052a62635b5e2533e7602c9f00e4
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	\\xca70090875bd840ac4572718a82acc7dcf4f853432ee5a0a8f217d75ab35b11d	\\x99b37c372aba9fc764cb0c414b883d9c7cb7b695ab5780507f4221a4070b2d633b67fa21fc544f301d3197167a4180301a47f90d6dd3cb3869885599cf8a8a07	5	0	2
2	\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	\\xca70090875bd840ac4572718a82acc7dcf4f853432ee5a0a8f217d75ab35b11d	\\x8aea653d9ab4c5c6b19324b3a7971315fc4b881116a1a7e5598ef8a1b6e28620bd60df2794974eae9293389555fc35866b8ed26d0b4a21f8178a034fe7d98f09	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	0	\\x168a4b185d33a7fa2d3a100f3df46b7df91b8b17057165a04c04c09d3c61b6ada41216dfa8cece76e714aa456474d978f0a3601aaf9593292de68321eb2f9706	\\x9c56dce894610397c044f6d4a75ea2041372bda1b1d50c8b7e25327759f3af0773f48e614051075a5c6e0d311073f7614893122dddc9e5c55e094ec0911b924b	\\xada200172813a37df7976b5984181245051cdc7fad34e59925142851cd8588b3924758415fc759ed10f0babc0fc370598376917b8ee850f2370424a3236b58939a1cdc39d3d2377e529f7555d0a2796e5bc9792df70a52fe09d8749c9b761752c95b11bb6cc5fffaf3bad4dc96e4c86869436379b68a0efbdc58274698a16494	\\x1a09187580f707233c8eb25e1ea4e47f77e6b31c0c494e669edc1b74d8df3b58813580e7c3a3e4776c32e47c421af8f844e6d5355c56ff59e79ec26c10cdd468	\\x3e1cfed4dba1b1149c9f3b14d59e649f56f5b62c85e238697bedcbf774058ce6d69aed8658492e43776b156d544da2db29e48da06e3a67e71ef78def8f454446b911e8babf4c7f59094f3dcd350c70ac694c66a557c0f0485bb094856f0960bf7912a67271f3afd6fb4b9e4418784fb04846fc169313e0590dfa41b0c44f80d3
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	1	\\xca83eb795e8c0549cc07bf8525e84c419b6407560f31483a8f31cf63535c78c8d0cefdef0282c5695e912807e93aaf54de9a43b2ec7466cdb9953633c716660a	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x435e0092f866d004285deb8b402ba64db7967cbd902dbbe6f8a730068530023c6f4d98c3a1006b2d355c6180f0bccc12bc6f61576ae8c52406f72da613c3103fedfe39a0707d609b3aee0c21221dee21ae2d400ed091929805a9200df190ee82bd243c4d36bb44dec28c77c8cc9b558b86a369f1662d7948a0ba7d1eb58afb53	\\x254f2cf7d04d5802f5def58d149378c1f63a74c4f6fc2646e7b0fc9dc194c10518d00d5c6d0d9f428d316f96e17fd035858a0c5d44019caed38b059d2251695e	\\x4f7725f4c447787a94e578de8806881b9f29e216df30133040597ab2df5aac4ba538ffa7687e7f942c9bc27ca8ec05394929c034b8435eb7ef84c640864ad732e870a426db63a3b1fb70e7974ed5759c5b2b80de0f63d1c925f78bc5f38ff745313d1d54b1675468c9b273b2552b459606906aaf8c6d81f953fcf25e423c6c3b
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	2	\\xced56eba5e776c89443dcc872b93118806aedbb3a3ab1584b4d5940620debd89705308a7f1f042aa15e34eed42ab0a0ad47704a8282b0c417fcfec2c78f9ed01	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x276f36b7560014deb4304cf966908daa8d05236962bdd59b94ee350b06d06b9677dabfa88b277e4458dcee3bddeb227aea06d3e19ef5944dec22fb55fb2faf40e0eec30deac550f7935318b253ed0d1d5b09c7a21c55d2e900a21f969f1fb411602b31bad9a7e3e8f19165b8e4c9515e3cb3d5e076fb2b1b3bfffc0371d585ba	\\x4be4b59f855940990db920ade088800c8d16e85569e360bad3cfc30388e6a37f8700581250384ef7100544ca6bf379a16f97af59d9fb9c8908d2e0de25d2fb37	\\x93c49073408d57a34cb7acb559bec9e1966d4552d196cf151c237f2d2dfdc962c421a8ef1d8f8c19742d1f1efc3844f7404fe3eb4636daeca58e38b291b63bdf1f044a5bd7dfa2a1d4cb110663304b94aa04fd587e3146dfed25271f07e3ff6a5af5d1ebbb7579e1bf4e0e11f283a947d0f67f96fe60c4dc64fdb5838f16a7ce
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	3	\\x023d2cb65a9e1587bc353c4d695351efb74a6041c54934c58dfff97b53479f6bc1a43c2aa05efb611f459582d0902ea6418901ee02ade0be55d9943131d7600e	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\xa1eec9afb9b79f351d039bd07af6e90383082e8695a6dc015e93b19a2956eab26ee5a5661fe0db9c30f70af6119816465088246a5cf71408935edf2feffb1150a2f747e9d41437989582bf343bfb640a778c5025d95438cfcc8719991bfd9b69b932c1baaf9455a21d5dc0eda8bc477f13e3307599974895ae519c0c107a4226	\\x15c99770634b0ad031dda35fc9d396a8e3c019760867cb4f083a6bcd5216c77291c34e991445b3e9d05d3975c979815c397d4639eab140ef53370db7c8bd823b	\\x01e28d0be8d1a7c721d6c61583bbc0b03dc222f1a432ec6e3545354c9c7411c1ef249fcb6e3835ec6a921cd37b45e1df3402c6ae4cd5b959f0d8f299d04a6adcbaf13103696da971da7041de39ddb95c02d7c4772c22e4e7a612c0187499f2dbbca091734f5411e83d02d2900b7aa6a4f86afda7bffe371b5fd1fb891aa38767
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	4	\\x09cc7a9a4458afcabf0d62773a6c6d1bd340d267554967d6017bb577a3643678f23ee52157591c47223b0219167991655f1ae43be5e1b6ddd11a422bbe024203	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x67f9521e67116eafa4a6c6ebe0e37ab3435d0fc8aa2b6914925699d8bb74f7915fac18d3c051c31420d6e032323e12f700d9b145868c2f39f68304d18ffa217e1181123c6f81775e7d26c4c004824608a30073a3a0b3a53d2f8fda2dafb7107dadf50e38e1fa2dcfe67762a129e4863412a9b55eec8932895bd4ecfcd216d0c7	\\x61f5d3f20eecbc4a96cef9219a853369683e3090e36719e75a162e68ef5214c04882eb6d698000f340187f850c6cc1279b2cc490f6a7cfcfa5320bf0884ddcc2	\\xa457f52fa31e98d6efb44925e42a1453dbb1e0bb9e135275e22ff8af3d3ccb7f1caddd9ffb68c58d16008a1459fab2abb9a3489ace37f9c402c147c41cb81edb1e0e150e4917df0ea2cbf31199ef6ef705fd446c8c6583e88c9a3b00aa3f2b21f54d1ce9276d49695a21f331618ea0bced7de7ddff253cd35653115a3186cb35
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	5	\\x39020e17e8380f7c408f58bfdd05437309ec779a9b41048f30c4d7d696bb98ff5524109d45c0eaee2f94cf40088e3694f4c09fa2cffc34a3e8029ad21b3d2404	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\xab82bd60573175f7453764eb33ed5b71b4df03ed5b99db317d41738fab888259564492f1c19ab9c72f8236cc8a395922d6df6dd9cd91a48090ce3318ac83f2ca1c1edb5c71db44a1a47c01fbb20fae81ecb4ec8eb984a47d94f3a94eeec58d086008873bdf6b007fb1144e643aaa66203a1cd1bc73785d12154151034f5f83db	\\x44df3707623518e3ae78d0dc7ef78e8b57aa9389e0b18953879149b174eb5d64ece3bab4c734bd3d402f516e6a3c67c6526f26815e87887a73a4ab7f0d823d10	\\x5e744fa6a8ae04ba5abe19b4322a1fede454f799572260b044a63afd334df99786a0a528a1009117affe5297c290cb2781f91f7497f7889eeeaa3f57da491d729553a2ac935e809405f3f80a9f5c478343c3ad1dd0ba0c4a1742c862faa4dfe860c420ca8c8d916eac374de5c61f1b5c454523b016fc94c8fd20fff6e0ced19f
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	6	\\x7d3ff219058ceac56f22d8ad6d9032c83e8ad9b47c6a341987b1e08cf656fb920ce915a595692332b3f6789878de882bcce296ce505e87f7156b1b196b0b5202	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\xb4f9b21baf179458e278bf66bbdfc49ed21d287636d7de284230d92769e52384f77c4e53dbc0dda8fe98ea85735a35f4f172f37ec383be65c32cd653ab5441730a415d44be56b0e9f1b5637e5691767584cfeb58e17cff8a5e2ca4504d4b4af1521b81777ef063e80c036e027d6908d57cb27339af0cabf4569fb5e20070073a	\\x08221474fb75f66380825334850228b8e7aa52d8a9f530044b5c0d16c4de1edbaa371f1adb34a731699b6e5ac80a5fd1f390807b1440e95efb4f1427e81b8f76	\\x9be0e136b7b3a37e4183098d7f8de170888aea82afd91f63253696071e40ac2e23295e3f396892da142e0395c11bb2e8a25e2c2e829823b9273b475f062483ca7a6e5fe7c5ede78e5b76ca0d194ddc7e2608a9e8a930b090839589ff6347aece3926dd03968539c5d5a121bfed0a60de28cab6ff1cac6845c455eeeeeb0a352f
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	7	\\x9d689a4695254e07923aaebe7144b514e94ea40847462fa0c8e56d4ed521b7cebcbba61d1161b63d7a1eeee0d63fabfed3ef763bd47cfe22112bad5bf74abc06	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x2fa57c801808f9c8e11d1aade9e9c7db13197376bb45854b3698b972c84f61efa0bb8f535fecfe4723bab95e6f937e7fc74f5ac2e7dd83adfb24588b5055506bc4a20c5e8fc0c56ab9871af56789d59fdb9afcc9db24d7314984ae65bf51772b9c9f39a879832c68e819fa314ef144f980b4051c33b40cfe3920caac1aa2a40b	\\xfbd0a92de76d580867800b3de5d5c80ca833c9457db365f25c9741fe9a7a5fb20efa2681501b9df2a2f7ded941e51e773a1ced999f7525d000577995baa06f4c	\\x0821ac87e312fde6d08d943091b5514c659d089f1bd5c80e73b8b75b78ca1d5fab69a5269e679ed69058e6fd897ad963f84a8debed4d7d0fdb09e45db082cedb3ca268e3870cbbaaefb3869ed5328b96f06c7563a27ac4f631c42705abc1a1dea0fe1434f0cd0686b1c49d63f422c583efe7464bd8a24f0f4c6f0791b691a19a
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	8	\\xa0580470eb66c016d19842a273e1cb717a5731e5f51b4560bd9fdb6e7301a8d050684ba5d4ad5636aa9137547088ea4a183e99dfb3dd13a3b9d3652cd5754000	\\xf4bfdbbce3fc967dde87d06d62dac6b21458954c7ca88aa51a66b23f11545b0d974b9c362c17c453803cf4ef1b01f2af6fc6735576785e904dccd810287ba771	\\x5aa38ff05fb1608bd80cb9626965ad2dd1f2ac57b002b01bec8b3ff41bdf8da0f8129497025e6e9d32c1f13c22161389c3ed706d8ea410bb35c195df97dadeae6eecb737d7b361b8394f4d0c600b272b021d040cafcc03b801237b27b0925510d03dcdfb453af0312998d9f9a20b4614950c2b55d0267060805898cfd1e16e1c	\\x8c9f3d6ac36088d095175258f281f3767ece90925aa8d04fe9649eabfae009f9d0a957557c2a1af37a62722e0746719c23ab052a62635b5e2533e7602c9f00e4	\\x2a341434a047ac7b0ba2021ee8cc517f2d3abf468f783d890d527ec306d456df79fdbb27c2a50a5e0cba6b1358ba711afd9c80b8256d53fb24e88307d70d2f4af4c976dbfa6e49ea7fcb09bf0671001e2f60d93ec7540b78298b85e4decf764e8bfce938108703e330ba0157e685371372c726813d97fae8d0850699a3cb5715
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	9	\\x478e36c76ff4daaa14e8456447c11604ea5369e0ab6bcb02656138873ff2d96e5de14a0fe4918cbfc0bdb6425d61c439440928fb190ca06b2a4fda8bd1ef5f0a	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x73ba7dbe3bd3b8a66ac7152cdc407ee6eb89a48ac368b59f9210afa38a55121ce456c8ce03890ac2df71edaf4aa17ac976b2c31606d448fbd9d370113ea1692aa94912ae902a3c9e72d97ec814b8b3df0d900ab5a3845f8e3b05097ec84cb8ebf1fb9bbdfa3f4c7c8f0dba2a7c9916a8085c554dc3ec2b9e6c0b7f8f10fbe187	\\x07cada02ccbd12c7894aee8c25885782d5851b7a9c1ebbc5bc16df3a631808f44859b62b0cd049aee0ec23d9126ae2c5b6daea4a7bbbdf1b0854f8d65b7fdb5e	\\x40067c92bf8ab3147091dd918a920f56409f80f76c27d214d6a9204bb0e478725ff76f0344345e25a656fecc11a980139122a5d5c247de3fdec728fa8f719dd1535dacf5beefd6bad9486dd0eb3d2a311eda8e27fe14a6fe8cd6b0111540377a25248833d7731bb0ec75865f90fbddffb58c7312a70909e9ce9c724bdf4d9402
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	10	\\xd6b678ef476a8f3ce0d15e6a5f9fa6776908029269fa2fde7156cc2c189a8ef7a9df325936d2e128ea4c3c7bd916b07e9e003f80905b103bfbe4be842d329108	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x29c61ac0d7ae1e5b707dae994ad4849b6ebd0fccaf4676b9d2028e37130513aaea2eb421355abd6c1ecefc13f8ca8b459c51372b37d7fcbcc0281f5a574cbca7ad44a77afdacbafbfa69cb3509fbc5ffec07dfd11e9b6f53a9804cae6ce5817fe48b82911acbfb01168d28d8739dbabcb931d74cd19779c49bfda35c5a082059	\\xe99a12d1514fe12460ef738d95cbb70701b59255cf323ba4a0d8d25af34670fba0615994b97f4b73ea87ae7705e5c2ebac61e6860dbbd1713aa216f2de249204	\\xcd4c56701aa48b1856dd88c9b1ad91ec6200065af89a3e856cfa60353070c0a409f8bb59442943e085ffd661df6cfc439bdc23593f9d2ffe1afd71f6af81f190e6c3f5dddeca0dd059b6e9ba18dc10e638628bb5f802afe3e30a2ae023bddf68aa063bace3ffb7ab32dfe365d854f1d04b9255326a456d5d63ac6a5e652ba41b
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	11	\\x9f18cdaad5234b03b643f85a5cd27be51910901661193fcf93844b470a8c7a37e02f662df5b93f5fd68869a35d0b7a6acf476439c2b4fa931646c74fc058d50a	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x7e2a00ed1994c2bbb773b5dd0e85f5e0acd2fd551bc97ba4372707f9f23c11a5902eaabe8f642e1b2587d788bdd132b3a541935667a1a37501d8acac8945b3038aa22a9f69cb09ba81f5930ee310010acfab1ff764b9abc0b3727fbca78dae5366e2a895c33e51f57a5be6b1c8c9df7a729163f114f79829a266c16968d03965	\\xce32984108afbb7d9a0f52c4bdd1e9209c0d41289bdb96662c9d51d66ad8061399d127778613cf2993196ec0d3bf3297cd9a2d07430cafdab5c0fc9dad2a078b	\\xf046ae7225c7ed7b0ee47dd4fb59bd7b1b43c685b59c06d59d23b3652b93f2f33bdd1eb2e8f36dfb06df1d03338b37905e081a7693bd083e36cea7e62489d6b65ece0a1b184a7903719308c500144c2a4833c6b09be52da7bb90ad60225fe969155709af9779830b129a385ef79358dd21dfbf0ff43e001e883463312c9c56
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	0	\\x4b39c66e7b6fc4f5b534e4bfb32dfc15f58b7e7c78c804406b62362897207493be25efd29d5ffb328793e82d7ad55810657a3d11870e0413eb308b3a79442309	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x4cf58b4635e82381d2c24d9aadcb091643cc8ced02b9631ef8e1f0120110b3b3f2f536b36e17a8024dbe6226fadf2e177c8c14014cec92cb5a5908e6f398ceb09a57aa46e114451481546286aee5ff1016a8b876edcc97abb85d8ea80c55bf67131e95b551c234b20f0956d676444a806ffdb3497a4afb9995b0416bacc4c25e	\\x214b1ec0413a65de71de2441ec7bf13dde1ab56122670cc807bd94ed5743bdd6d5d27cd3c926641cc58ac86105b78835b075ff0dd8cf648d7c936b80e0dc5845	\\x9a2889d49a64f4aa570fa5795118e0a798f8ed67a290f419972aa1dd1355b78d95f3caab12a1b2d2792ceb80280f9ea2d77c0521de0c18e6bcc038d8bdb7f976e6563279d21bf53a50985de21ed8afc1551093a495e5dbe79adc0ca9054001a6eb82ffb0d9cdb9a8c4605c9b02b7d062d60bc21fb7a8dbc94e3da90f907fd293
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	1	\\xaac86713fe99f7d63e1163cc87ebe40f22ab41ff583b3634adfec96ff822710f46602d08d5bb44bd24377e70c8c8f83bac90dddf690fd009a7150058a6349401	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x43d90ed75a11bf899dc3b77ae04e8a1847ae2203208dae7c4d55079eb0fc76d62c5e459208f44dcb1427fe27888f0774c630e30ad946846f64a2ea4d801b6af0d503d4394a61d1ad9d320354a6f694318f00dba5a4a93ba9a972944b0cb95d86401edb2c0006b0e507c42a8b162ce300d99bb649c0e0a3341f65484b894bfd56	\\x08fdb4a5a6403fe2b41a89e5e664d935d6a220897dd395deb46bb63ac6a9b889227cb50616a5b622730cee318bab0890b6f8487b80308d26ea7f3c464ecc08bf	\\x5438b08a565816700c0361541080dcf16999337b54a93c380b1113f2e6b5c6b0bc7be10c3eb7cf3316464cca155e7d7915c97efe2c3e36e9a1ff4a3b5db1814ef7ad8c269471f8074579993a80d05134563e2fd49eac4fe8209d2233b47b6a7957ccdc27d796697fc4deab68348db498fd4b54edc0a643387d59d760e6cbecab
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	2	\\xd5f10514ef141723293c0cd6a6fd0a72e35b391fa050f2e6f9e36fe5e515b22f8d860b6d8ee4b0d87b37e7c4660f6f3b709389d0f8ba8ab675ff05d72d94cf0b	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xd5de8a83c7008b3d1fe69461617504682fa65312ccf749e6399ef56e077e034638d2b5977d58485a2c0663e689a632823738fe1613abb50aaf1696f1249dd757c88978f76224bf2efcf792c903e233cf55396906caf361a4c25b2a99b55c0ef88faec098ac62c09a2e615c48bc6465d583bd955eb4ef04a6499f543a84c32ddd	\\x8614cb385c9d0b1cf0585ddbd090c857c8d7a7ee8fdf91e1f5cafc3cb9111897735ecab4e59db73d0b41d7000e387e106f0578aa869c67d37e552e28780ec711	\\xd7da5c89491fb9cd05231c2bc0849c62e1892b9d2c846da2abab2dccbb0c83aa22e410f3029069dc988cad05f5756e9308167669cc40ad9f41bd8eda07830e624e8e31e26a5bb26c3a1cbc8c182ebde89b0035ac2d0dfb183725eaf4f6ed93db9efce1ba6f4c96ded43cf6784c0303efef592e05d8b56fad9308f51e11042b4c
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	3	\\xc7f50a0b21ab9b4d09dfd88532b178a133a6c4bc1a105bc6b3daa696c480eeb8b6c243971ab34a76e14cf9fe244d0b851bb553d9d2f3db5e63f65fcc31c9ab05	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x723d6d6ff72cb86ddde2f185f948280adb3b71a662e470e7c288d3693016fa41358baffc3966dbdd57a8bad7deb953ce19b7c29a272b8e6c3da3d7e1db0d82e9d2909b182f3b56bc3fb4e9236d6fb97112196880549d13962425c87ec4616e114f0df387c3795d07cec980ed6719f060d3365c391948c049bb66602a3ddb12d1	\\x9df42337ac2dd8ee1aae6c3dc95d00caf5d588fa795089886483fd0124e40cd51a546754eca44bcf28165c66d15fff8405fbcf0705d21e4358d168d3b665a977	\\xc71494187e1d6f971424c86486674cc86d0ffd46cc84d9e928808c139bef910b2f15c576d007653a206b47a3f319f1088728cbef03c91c0c256a165a40d24632653ce7667839809c43504d675c04faf20c53a10369458c425a3d8c0e31696a1e3633d21ff04506299effe86da34d208b80e1c5af6d8b464a621c2fa4af134c32
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	4	\\x7f3d09795d42c1dc33707386c17c729bd344f6448cf5548e23a29be120662679e59de367aa265802062038aac6993825941185892c9084a59128481d19718803	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xc156619e45f27bf6b9dc654cb4f1495ae41f7bf04f77930c4e0a53ebdabe8bcbf733de69830c2b2a3d0c22c1f8a32b3dba43783f27089efc342e223db9cccdf3ba59fc56c581aeed80e19cb3d5382abfb6b1d2966df3e3f1d9e94148bf04ebf1f395b4482876bbe31f8be288712746338b832a4bffe139ed17540f295479df95	\\x04bb63c96105d4f45b74f7806b3677f7e0feb7ab7ea0383b62645b4a55a811ed581c71a7c9fa99a7cb36ea273e51df1599c097e6df22590d9415a668e4729a1e	\\x2276c594bfbed90a6591eaec577b699a6df706afd60cff50f7e74876e44a7c91202f03dbfac8820d88fc6405644dce4bac28715f9c4bfe87b567ec54aba9ef3f77aa5309339a4af386598a602ce57e61f800306c5ea9d68a19d655dd2746e8a719ee0f56585e4f156e8d4f8e9bee50e96c41226588bbc0b41820895a767eff23
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	5	\\xa0a9438f599de2c18b92996ed74f97f7317c18985677b521ff423d9579d08d652a5d9584d7e05f5095d0f5c8372fc71e4b363bef8ac4bfe40cca98f659fda005	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x5adb1ac960d94755b94ac16e099ee9e9a4b6ec9fb8bfa28ef2079b8f0a994c737fa9d3635eb6de41fd8b53f4fc04c584ce6e1234d11a52f59c22ed3ac5ad05eb2e76217c2ebfc5cec5a21a30ef8ac8be3c689bbaf74902ce32798675a5330249cf39ca48a5ef381a1e26cd2c096f71488c6ca8de56dcb93634e912adc36696bb	\\x0230c4884428199cdb38902a78a55dc3d9448bb29656f0729584a3e43b328d63b03b5d351dc3c94dd4a68d4f09cb4cc957c5fdc359ad06b825dfa91a33e15131	\\xd5a7e2f8097f27f36a1e1d7ee416c376641bb5fa4c0fb4e037ee9feda4755c3ce5074964fcedba2a54cb269d84a791cd32baefa3829d92c456b2f3736f5f8f84d127538dc6943333d749567a4666e0559fe04186ed7c62b12a099e4dec657e011deb3c0b84e7676b5973f3e0463b0408d4edae9a77bb0cfcfe70ea29cf201387
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	6	\\x3033fbb46feaf0dfc17c3010e43c9b10f61da1eb0865acf1d1b1f60c770cff408b88de839f729dbeb6e1ff2a0230724c85cd1ecd40355ffdd368ae1e9f12890f	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x76f166895483a925e1b8a883e531f6f1f28920955ae96307c4afac6e5a2d4c605cd1f65ac0725c5956c050ae26752ef9defb4bdb6b0d301f7471cf144227b4ab069d3d2be260cf0eb176873ed58ff40028c6e562d68fb32b7c006570de172d4884754dc567d2444d175827b7d2bfb04bfd19a74aa94d25fa364338991d01d784	\\xdd14de73ad0abb6a54bbbc045b0237b132c269a0ba6391fa12687b43cbecd7566885755416f8edfcd945282d318fadbbbe2e366494285cbc91bc44e0564a1d8c	\\x8b7685ae2b244559f8dd3a7b8e0a74879b99f342de08671f3f213f79c87019e34f5478528eb67f61366f9a2c05a64e348dff027091183c8be263b54ede83b992a521a1e146ddcfdb8b66d207e7c2f7a4f9bc35e32f1d4e0d07fc0bde571da9e2f0d9ecaf1faa08ade6430101c5ef39768492a2f95b56b92ace3d6567b7c7a736
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	7	\\x471cdc44a43c96bf3ead6c75cf8602c7cb5a785df5998fad8974bf9fc14c5b043e9b09b05b7ca48c3e645e11af3707b594be64a7457c46185f9cb69b25db150b	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x1028f3bef69d527605e6d6fa82e84cac3e420fbe1de1d61945ed66f277763e0c0f843e588042be079f944e99ec06784ad31a8fb3adccd8e52ba848e9ffcf786d681ecd2e91e9c91585f0587504daaf3b4e94b0969ed57bc15f6b6addffe89a8f8848f7502e1a1dadda8065c3fee416f47c6f79fb22b34eb1211c7592ca643def	\\x134d5e61ddf5fc1655779148feb8417fd04a20c4fbca59435065f9ec20a04df09353e0fbf44e05d297e766a98e64d9a66ddbe8e34c0230b49d8f9a948c646779	\\x060cd82b15c0ab17f735e35677d02988a1aa4d24224e2b0639d189066564a5677a7a6762daebee83271f1c4282d669031603a1a7ad6c9e1e54331db9960fea26d960d13c8789154ef9fa886d8431c5413e62c84fc3aadde8d9593436eb9f57b81dc960601beec283889ad6173287be4f1f96b2cfb9f4f18559946e5ac12d05a5
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	8	\\xa54652810ffb01832a2a6be96d7a352e2890ba32037315c260e0fbc2c5d2935a6dc4eba310f28910742e089c275dc4fb4c2c33a43784093dbb6cd20e8735920e	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x4246374db3af4f825b3ddf895163229e4a3b3ab8769d20761f0192d61c0c83127631f3780d811d1d3d40eaa5c584c388c10dfd2dc527a5c125bb4a3d59337ae6451841c24736eea316922b64459130247b6fee1c08ac9106e5f860a956469f02c53f03b928543312a7078d35552b2bcd37da42b55ab96489d67f164a20635ad4	\\x8f06b32d094a3b2db57513097b01e3dd8c6f79c2eaa4b757c269d0f2fc1ada4fd8c54b95c1bb2ff462951af86c990fcf8ecb7673b11cced064e67bc49bd7876e	\\x7b0ab9643e1ab4b83fccb050bda89526e35f3ce32449ace43ffd6e27521382c8f5d5a0ad3dd2867489f8c18dded2fb5463e521471b1c28fd6a69c52aa1053e9c09a850ed5c0df251c4d00c6e8c177185fe7a2d4d7400c0c1d5297ccf09db56d7c2d0cb1f5dc9cd9a61a5b0ebda0b82e443eb625015efc10bea68622befdd34a0
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	9	\\xcdd40ff8d6de9ac05272a297b9ef00c6bd1874b534f79f6d7ac4640c973dbc3f1dfb994b4519629759bb3716184ad3d6d23f64738126d18d29613cdd5b83bb0b	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xd6bd719668bba98cc91d334628e7f9b297d0eb60b78dd32aea0d14ebc92d36a192bef2c1dbfccb08193099b3f00731b4c3dbfd55a2fc02002c19259566caeb4f2e7b60159043129a9f60ec891e146ae05e3e51a5337303d59a0712c4dca8b33403ee389b695f58421b028e6a12520c820377c11e647092462c0656c95015798f	\\xca246cb7bd72b6f0aa1291b6e9c6348e20280965581bc006c5bd2d8dd62afb66b43a74badd5668e2b84860ab8135c9b4544d2c6669b7c4ab8a624d997e4be0c6	\\x1ddaaeb375f7de4a942395795d847d6d8c1d68254bd4252b92f74573e2463b5010ff9a9ed078c8c6bd89c170738b164b6a07bf803edd4ab0b9eb0292704e45d5f58014d7d6df17264ea8466c333d3f8ef9c4b46872d0ea2672f582ea3c3d4c17c37e596b62f565995d533e09bb6f1499997b4c69553b5a6bdf5d128c5e43d6d5
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	10	\\x346d04fff45cd89b150e972ae6caa520a4547ebcc5f481013aa75296f84c18a8dd6e509f4a4360c52ae228c394e6241394d80a1dd4e01e38ec96b5bb3faad509	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x5b12ae2cf46d861d5bcecdbb8266c1932a66107ddbd09bc188e54f7a0477b5ff5f8b5525bf36087b71bf82ad846e2894cc0f64dd1ce7b4f7c790a90b7466a183461e7c9cb8e4a93f8e945f4905c3da4b38829cb9260b75f656153a6a02888df5b115574c1fc08ec89e5ff8b087f30d767f64bd3187f520bef0e98217ebb4a31a	\\xd9d1a4cd5d2bdb55dff813318540877151a862f9a37a967aba1d79216fed53447178902c9d81828cfb82794a1e8f05bb01fc346b701e6f97468120ac860925fb	\\x84a73a49ceced03c2ddfa6d64db499f2494edc92c9e55b2b01b2bacccdffc506cfd1249d4df2d6494674d02dc3b51c318b519defc2fab3c9cf5de2a5acfac860ded226b7ddc82f9eb358fd43ff3558936406bdc308d819a118e446e823e57f354f8e2f55995221417c2cb786be544734573be575d1952f8a0073b0bd799a59f7
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	11	\\x862fbd0c4c5d90611914391275b4c9288c58111042135f4dee24704d95efcb213e024d2566d517b1d5d8920c6d9f1ab3aa823daa6e0d7f04d9fb5f9a62874f00	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x8a5ef07f8e447489faffbabef911772133321fe115204ad49f912f636f44b3f7690b8222959ddbbdb977b80d122162d078d62198931d9d9beabc89ce04f583f82238be2af7205c47c6a531a5a5099f747c6de15560d7065fcefb51a1f381981a941cee167561ea0d2b3cc4d5f296c3cf4719d7d3ec624bd1c693847af9cfe91f	\\x848e20d2664ccdfb2bfe8dd9d19b55e6ac098f4327681c756af6b9b6009537543241f35a99a19b1c635e3788feabae39e21d000ed21b75681a19d983a2f508f2	\\x75e455f332e8c7e91758d7de7b3954f16199ae63856e7280a8f44c2cf89f8a6dbf4f0e9f2328a8b3712240bc2e961ee4f73d2575c8a1b26e6fd6bb9f2246baa9015868e92fea7b331271d231be96f3c344531438f2b2a51e278af47a22fcfc98f582a575979b2fc5278a142b01a67a42cbd098b9b6e7dcc0c6838aa5cd9e4c01
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	12	\\x05d852959514581a3c27fb69ddc4ff37d631311438cac490315e5257d12f425f0484a2f63a468b47e75b5065b15354c23dbf5bb297b71330cd3b4f58d1fe5c0f	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xc73f53b4e1d9c62fa308ecd551fbb93f1c58631ee6442d2dac494780c47f4ebc2b29c3e9fdc4d279203f2aa2f4cb56db4b85149580085c1d26f20ff6edd36ec09d0707b542a0f23ba4466557565ce1147b9e6ce57781848f82897abad2a0f4f1a9828d9c3c4e3856258040be4274cb796c5267602bd047bffc951c9e34285407	\\x171c799cbed0781b866efc46a3aa269ac7ee1bf048651f5d7c25bbe8c69c6af9defe593ed0f828d8779022fabd54112bc16b56f6fc19dad82ea13a3fdf083226	\\x1357f2f79ef82b444088eb3866ef869b7ef8716501822512953699be26fcce8aef68674537321b79c120860be1025b2f03dc071ea759cd05a7368b7f43851ad46176f6acfe1c561ee6e930d47e98f449ff40ca651af69d94c9f0405f97e4479591798a7eac449d4d07cb9dc23c5166dd12d4da7778ce4583cc8c851c52475143
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	13	\\x80ad232355aa1ab9f25f299fbec0a6b98a112a4e02f5c7e0a39b6aadf8efd31699b92142aaa6f364e3855b79c583d1d6cee8fe692e819931a8a9d551634ab805	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x38b2f6cd975fe721e8ae5ea77f918aa50e7f709bcfc9fa6340db5c11dea658ca13a84d037bf555eb82ade9e53c7db4c3f143b7e6966eab928cd30bb7c850cf3b939d500614466cddcb780e351d0e3e85d4077f9787da64fa3eb87138bd198f405cca0e42dfcb2b6361f04ac1369a385c024cb15d9c12c9a94bf1559de3b065a1	\\x1ef686407528ec5615b0fd76fcbdbc9c6612ae04e9e70ae0c0a7d0b324bcba77230b7ac16be32ad4c242badf67d869a392e8a466a7cb3717eae9e31986717141	\\xc5be480f86538f46e97c2a13bd252e5a27c49fae138d9b39e5de1d97eaedf02afb44aefd3ff66f8343287c88a8fbfaf67537f00b291d69fcff979140ac024d536e29d16d8a8234f2709c7e8b9f32f9f49ee01518fa1fa1c871157d6831af475fdf6a6945214e55f617e5879fdd3293e12dfc11488cabaf2d2561ec632a0fe562
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	14	\\x91364abd1d26792a1add5b47b844924072c8557cd40d7bec5e6483a8aa93d5ea93c120ded2bb2d390dbbaa0ed56200028253275426c3303818fef548b14dcb00	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x6394f5eebef96669d6c93cb04404639e101113460e441e9aaa6275667d6a6470704162b31192557306a3488a70ca4dc1ec08bdca4ff46dcf52c77a0582a3290529b4fefa04503b3b94a0832776315f3cd05f2717b4a15b7e86cf157a949411c485353c7d54229c5bf547c92db314149de8cac9b3cc5cfdf32c31309f3d221a75	\\xac0cc2d0aaceaa7cc877bb9da0ba143c0853f47d336767fc1ee2b2bf36bf2c65419822480acb799b0b02dcbedf5565b1cb13d304f7c90dadfd2f0897d7b0bb40	\\x96c44df5c7d57bb93d2dfeb34db726092724527e2ac77e8d05f2f927b4bf98bff5b2e585237a79b1312199d99085e4e73597494d673b53395dba58f1080d0cc6b37f4d385e561ff24fb6e4427922a4afbee4b952b4c9d77e15094cafb4ad2d47ab4ee69f2b6ed20d83b351f74b011b1d029e025c38b9c2bb0187c783cac76076
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	15	\\xf3a0a9e97ed2bb4d8bf24b0026826167c1c02c9bc66241cc8ab2850541354fd06840eb65f708ee6659aea76be9720ce5012feeb163b32ae0d8faa2c0c029f802	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x994061c772bcb114c1aa9ccc5d14768ef99a01d740c8d989b50a29623df5deab02c8812e36cd035b2a65d05bacc79c9d9832dc16429fe796224be98d9787746cb6ee55a818bcc050c020876283fcb51432533481f3a4eeea41e6ff278612f01a948d3d15f2af51b0643d2d416eb58660cfdd3c67488895b154d7f5b0085ba7d2	\\x74b7e8c21c86c9e94248d587e22dd1cadbf05693932e32f3712de6f7116242345aa95d748fe35605e57c98162c735ee4736f9d990ac4a5546442846f3cf1d758	\\x359fec295b4baae23015f477957b605452b98d0c1969c0e67c76dc257d111faa09dc74ce5e157696db7dbbe7720d90c272493bf6e68d52121d98dd6f9eb72a7d6149b2481537ef185516de2c47dbb4ce3b58b158efa5f95e1b22db9c47042359aa2ca8e627e182c241e94a63c7fd7b29d36e889ef3cebd089c65752536dc05c7
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	16	\\x449e534bf7786961571685e97f9fdc232cb13ddc15060a1f16ab423a3d3870153c08fcfe2d398b781739f0c0ec80c093ee7d1429f8528819d2a3a67b80a59806	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x38e35dd3f686355a7bc4365f693ea1c1cf27299021ffcdd0af5f7674f0a0c8e12d9fc1d46da8399541e3711e2d1f325cdade24aae75f46675b70561b93501cd1c742336c24c0958fdcf22448440260b60e962164b833064d0d0b759d9f0d7c141dafdfa1489089283b403ba633afd590bd49cfc6c1c80b6b9d980be95b787558	\\xb03190f48302282db477159d05b1276695943be84fd2cc298db10349c3a9e741af6ec92b419886adf4e8844ed3dcf74faec25963bcf3167e37dc6510dd41f599	\\xafdb726a894879394d4ec15c5d176e94d36c444238ae490e0d1af717dfd4fd8f1ec60f5b429e42049acf3bfc6f289dfba47a367e0f6293f6d51d13f6a6e1f647625ae685cf0a66b13c1a3bdefa670b23788707b335c2d0223bc827913e244f26e50c8be89e60895da50031ab0e5d931777ba119e4d3275e4c8e01aa5f1749289
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	17	\\xa0ba57b88f648b0a077b5984568c94c1182b466e503f3c07ab187d3c8b70771635e6b4829bcc15d07d5a29f16446ba0e7c59c38a4809096710b459cf2d9a5f0b	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xb52eb000a25f74191ab6ccca55bf6bef11ed029783540dbb39829a16a93b63784ccfaef05dee4cf32882bdb65b2313d81aa7eebaf56f6f0252ef0ab6696b219b59cf78d2c4711694d269330d6cd2b02f660dfbb6e7a268f3dae0b89323b9fd34069843eaf2adab0f14a5e44258beaaf3243ccf876e582511eca069b601f2fe0f	\\xcd328b0459ab1577f4dc7bc49ae52b36cfd419e0303038e927bbe3afe822c14c18a09db746c544be817d5f29c47f6570c6631cf5daa52179c281a745b6989a0d	\\x05f38fcf7f717987ac87ae2365058afd12cc3dacff95edbfb89966d2886303f3d2fd4c51455c7e1bd7a5d8070f2a14a3e58a927f6ef67e33971fc67e7a3daaada183e4a805c148d8125c50dce108af94a8ef391566f33e89b4299b49900ab5301362b29fae7df3a731b01eeb533eee82cbe2681fde3c76d46882ac01e70a9834
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	18	\\x12cbb90bfd1941e29a3ccd46510b5e3554d511c39a167d54a2b113066fd3b8f17af9fbadb42a627d21a6cb82d93678408c7b089336e302ec0f28fd6d9c7c0209	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xa33c59f284460fc15265cfb69ae903786903af62e7b5cbb7606c038e2d6d6a9844bf2218c3289fca8684964dcaa40079c329d8a85e99eeb4b6a635c50a3435846448344ecdd2119fa44ae7f241dc3e02208ad26b653d56f40a42e293d05c3a08047cc3fb517465b31cef08e68213263620080f9b8a187d61e4b7791ce0bb40d7	\\xe8c046f88a1d18b42bfbab81d202b576c548d874635dbb3c80028c5ecaccfaeba83a0ec35a57950613459cd0f21dacf2ed111a824729ada2cb49648462068a10	\\x1b7de25244c38f3c8933e019c7aec8869b7482ad0dc0651b44c78c59c7494e62b5e21b799b3740243b3a64dde9b71f5b3f5f481483a1d23d758591fb1c077a121c969cd0ee639c054da42382ce0a5f7c9bdc7cb7ec2c2fdf928d78b274504a8a0b1168fd49e9f516dcbcdbcee171f3362fc345ce4bf9347563c34fe98c88580d
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	19	\\x28432143f2798b75652606c09904d29dac006fc8607ab551535fd2867cc28cabc2048f08267410adb0576a94455fe45f1820295e334a27e8bd2a38ea1a80d20f	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x57e6018dae5f4b4670ef2f2124c1c47c7c665e3b1315a96211040795209d5958fe80ce34ec1bfdf07db0d5dc533e03bee7af307808d87ca49b958a5c8c37684f79bf0f7cc84aff4492ea8dc94b5e6572a087166124cd0f2640bd340b9e749e4f7ef39815d6719ad41c263d5fa9fd862c5f1778c6cebfd49b2e2a0fd39fad7c2d	\\x6d02728471f2760af51c372a15ef8fb3cef4f670f3878b7358ea5b12797d7f4c81186eb6adb40aef2f90ae47fe0c20c9e1dd7973640174cfc2cc52b8b2a947f6	\\x3a4f96ad5242d2aa5d94d5da04e3bcf564cb09582421afef62399ed1a210e3d25e578a6f410d3f4780fe0b38d89bad1c8834e7c0a116fa15315574a1d6ee21d08d1b6626d75634c682ce8332858887b2d75b1051b76890cea156f328f34b1ed9a0da78ef48b0e3415e64a1c25f738eff7414d58fe693584d14a0dacedf498f92
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	20	\\xe51ef4fad39da22c9546eaf7180607b708a70902f69c26928ca6f7cfb3f1f41b12b9578a799e467f5472e853fa6760cb44658ed0712e8406525dcb84fd64c805	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x3f632f9a3fb845b88640195c5af12d5193a1e6625717d9c15ddd83ce7a675da1169e4d1f172f9e86085a2803357937fa8deb73b0a2f6d89d2acb819b187452d439126a4550a5e89b83a9e3615d2b4a9ac04995e03ae663d493b50853b0778f55653e59e7539a1343dc18a258029b77603989b827aada8d12c5b536d38dacd905	\\x9d0600778c464fab15a8005aa70b4f09a941b1023a82690ef646bec76db722fd1e397c954f9c2c1ba69fd51c2ae4242a866fe8efab6419dfc70805373827862f	\\x5d22ea1fcc56f6fddec9fcf50ece7b35c42f2f1d0e667e2fa20e1e80cc9610100b90447bf52d7e3966a3da2326e5b350bb99e2059584039ee6dac5ebf5a6dc0d11c00044046317803bdd80b81d602d92577f5c2274f8a4222e12a0709bde8757bd382b78d666f065a157836daad3ab621f4e69212086e2f43710d0c7af525a97
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	21	\\xd225ace7455a7886c42820c820bfbcb4eb2a5a0a736af962c538c24b43e6dcb448d33e21b0afaac27fe3d9f9528ef6c4f6e63fb3f285dceade07ee7fecdbcb0c	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x3d26dffe17cac2e81f586deac4349efddb816d98d786c633dbe101812948ab69f3bbbc89fdc97c87e49378940559518259cb3821784fa00edd1d93580f093c101609942ebebcba52ae3241b4d9893e532f2e38007a5affd5f9a1c993844a55a25d49e33d99f33b02de3f6a063b5d48556751bee1137850657c0e117f5d7a170c	\\x9bdc9afe3ac0099de135740ed088b74562ef0ee51e5e1bbae591560da0e2222cc102f8b6bd9672f398ac6bbf4738d07d10ae096c952b076f8263a73db1cd4644	\\x44655533f6a34a7bc1a6e06bb4aec4b1d5da1aef0d844f3a2f8abc89a9fa276bfc836ca13bbe0ced3ed82c8b7a7fc0a480845ff50f50b20e4e44c27140f137bce4f4aabd16c40ba1ea8c0fd34a1c048ef5407656bcdd81468bd976ac16557fd1faaeea03a248861046f0477136c9657a7d3b296993f29c673b31ce6f09df328a
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	22	\\x0c5bb33bd951b5bc66f98739a6fe36fe9acb5b82b7fe81e16aeee86a005646d12951436a567dfc5199f10a76ce0b8ee5bb598dfff9bc8e787edf1d1d5ac50902	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xc2c20dd2fb9d0e7a188448d586016060fc20e56cd8ca3837e49f9310449ea93e88d32673ba8e9dbc9e612668cf57409587a4ef287385077db902accd7d177a77bc50456b641d33b11ce268c125241cd6ede936776c311345f51add90cc58f76e2799789ccd06b8d257a7dbba7b487341399f6ce95d21aa353662859e30290b37	\\x138af059d669fbdedd6b8605383393f65fe3337adf69607466c2ae36204654b4d5cd70933024d15cda6389733716d7d0d9ebdf6a0d4d52d23caa557209a1f3be	\\x2b7fda0aa3b220d1eeed24d33ea77c1a26e2440682ae01774f9349cc1be5a51b1e404fe672d57b27e64d1e10fba768ab52b4a109b49fb5a3d09bb09dc92920c40a5d8d5713b801c68e51441b94b34f764598b66c89adcae7feac7a6cfb8c886620547fda5cd8d16e44d65569874258d4ab8aab1a28f32e08e0046a7e617df345
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	23	\\x11af42b687a45288e2ccd8645bcde9ec9335064cfa6845fcbb8fe1b324b88bf271746a8523beab5fcb7fe1b6eacfac0a7b3b81766fa7744064ff4c9d992b930e	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x116df1ad09b5c1421af68dbc0b7b7355f45ced18014456057af5a29704337c6c1e5ae07ecdc464ee21257a50aab75847d909e6cc486350d01716f03dd317899be4f3378f60a2d917bec81421ffd731c0cb7c2f010932193d77b9f0c2e3647d24a7ae953ed6454f6d5dee77e5c7f4541f3bf771a1c1cf7e4bcddd2b8c3e060907	\\xe2f8355f7c0a19873c32a0600e7dc5193420bc354b5625b15f383d60eb6910c53bf9ec7785960cf28c65282d1ac821d4377bbf965c925241f0ab1618e7f849d8	\\xbd5402b79546ad6dc4b4a051f1e15875c06842b11dc9563cb62bf6fb786d631dd83355db86a2cdbfaf876bb093996a856cd2854c7b8b1a82dd564a0caf7ea9e673e25e731eedea4a13d212e2da4531f9db230feeeda20acbac381591c92b5708b616a8c7620439040debc53d4fefedc35eba1baf82bedc7893cdbc04160779e0
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	24	\\x58174dd3e67c7cb8a8d37e27d2ed3e2a5b259ff001fae56ec32c8319b73ff603dd59e1eaa7ed2886f3aefa3a2a47e10dd1e10b3f319f002ec1e1f7d213501506	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xab96e8a30762edd62a4a53e52003e3e6bd37e9e698582bfe69aaa084f22beeaaf504f8cf8a558420ac0952d4709603e318972b4ccf973f0f2587baac29bc923aa3d295b59308542b0ef04541d3e825250b2b5f723b42eb52efa5d1f504690da811ffb30d1ff2d5709208a50f86226b51211fc0c07d7155d68e016e385dd8fa13	\\xe4f7208a071285ae5a72b61661348ebc5fdd83c3b6143a23cc069db86bedd3a23919bf0458ccb498244b4ce4a80cff6df9516e16a3ec079f658d73fb076008c7	\\x23f7e3f5e4057e57596ac20e5b37ec95e5971e0e40ae5b11117d35537275b8c9b24cbbc382c325020906825b2de421c73c3844db798608accc5995ed52ad73c6b51474432b92b89a1f0f987cf42ddac5eba30f26b90d243a6894d71858e0e95cae8bab1ae57e9a98dc005b383ab8e785543d1c2d2e45e56558d0543da43334d2
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	25	\\x4f03dca3bdc90569425a7c575e5c44ce00fe7fa37c347f0d3a306599a1c00ac47730d51e1db64bb80da42c199d20a415929e875d8f5b31242c4a99bd759b6307	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x633274a0da399ebf86ee7a9b8e17f097547c9db6d89411506be77849f96637497a432a189cfccfeed604cdd294af78a8af5ffe4c56980a5f1909c176693cea4a8c1e216544491caef656ef6f8eef99a5fe97f978f6bfc663393640ee00ac6ccd4ffff3bcb7a6f385daa92b5bc2c31a2d05929208b6007e993302878de0698a71	\\x3f543f5f66afd975b2d0cdd86f10d2e63a2391d6a7e3bc640246fee46e27426f26b596845d1fc2d894bb4eda1ba36312f540b50435b3323af83fb6c4f15fc8e8	\\xbb9d27502f04503f6b2604c95d201ae5316190fc348c7d1d6a4a36709370232670ff149fa09891e9c25150a03ed127515f7cdd0507c2ec9f46c013990c2842e8e37585e1e7770f299637d7e20553bf2c652cea819ac1f50762cbcb7c680efc3b0afff303a35b40f6460af062ef06e8528ccbc1824eb2af61eb386d552279c615
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	26	\\x84f7ec24f52b21adf3264298caa3e56ebf9e6695c19c957d2d090f983ac102d0582c2f51f06090e51a68dfb05bbb7e134fdffae1205f80f1a3108d6f19166609	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xb5648865019df9c5cb7916a6ae883796be6de0edec17ea3f415c654b687c7d831e02d8ec13aa712280bb00b797514d872e5f8b47aab0e59d667072b2f33a8a0220fcbf02cfe36d4374c371443025cb19b4b4b11e5c65d7bc1446bd1eb7a17d4d0629509138fb96c306e57d825c9b33f233a66403383d56818781660cf7eca4fa	\\x2282116f4b3d3a94453b3a90f3e8637aa3824c92fe7448e5609b0878d8d601449a0bceec6468a6414146deb3da3c7e0e54eb57c589bb08b7bbbec113e3a20486	\\x6bf60db5d436e230b5e6a32470278f66f57f2b77655364e367cad848f5f27ab608956e7eb408a79bcfa6cb6835eed82f284b77be51f07d7eaf44f98eaa2d3a34a3643e61d113a1412446a6a31374c5e3fd07a67b393d8e38b97bf4fc0f0c99432416022e545d37f029dde7f6e80c59ec28654d685f7e0432640e22454fc566bc
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	27	\\x768ba5321dfddcea5e44f911cf8269801489e12ffe986b1068f9dc4315621720fe6c307459cfb6f84d2df6dc9cbd459b491e4445670b3f0c31399d71271e6004	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x1838242a335eb7283d9e65d45368da112f2687426f40fdec97b646eb7ac38b52e13698f399ecc737909e963db4c8bafce3bd8491d6f3b04a36f360e10023f5fc1d3691a8046beb0c328b4e599c721a745d70b1d03631e5bc6cdf3ff0d1a94a3dc17fda449e9c1c986987d4be39f2f4551bb901fa18244fba57b967abe0364377	\\x2aaefcf4348e01476d89e1d44ca10e437263537b9c9a72d31ff868b1e402912642b10188f4583b8c492152ce02e5645adf202b5b174f647333dfd0d796f60a2c	\\xa8e5c068562e1d9f7a6fe33e351ef6d3c9cfb1ea63090a0805cf984c333b37aa5f100a16e58e09d3d629ba96e2c866d636c5df4a29b3357c878e6f1daa2d700819b96409a8a9c4621a3877516ecbbc81555d0be11f8c2d0b1016bdc5c7ee988fc6218c13e6de4cdc36fcf74aec989bb99b54650cfe5b2cb2ffd47273cbb18d09
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	28	\\xba974fdb285510b2a37fdbb978ddcb7034b28508569b9600bc2faf4f72aff9d8494b6ceef897fbe3157844cbd40242460953a8402b3ef8283241b49f034a190f	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x6527cba00d01b05b6f0e29b2cbd878535ada1442b6a9af328d6a181a1708e37f0a3377be9416a893a6b99502e942ff11aaf1a949606e30a17dd01fdf2a4912407f182cabeef378b2f2e944fd51479a7c360fbcb1d70d78651afac6cf1b9d3950c880278d4cfc9d6c7fa8e5a04ef83152ea4d0c6a33fab96134e9cc9506238124	\\x1f09b967cfae7fd56bacb0dd0d3248e41b8f671f4a3e1cd374ee3ed4f32fb748bed42c4ab7296272d0c0c28d8a156e3a4a51fb6f6f05b9b55fa4a2dc4405aaa1	\\x36c8a328648e901b1fec57271c635105bf14eb3bd51b08d97b6baa0e3de2a984d4eee65bdc688bc4ef801e59a376ed844a844aac300725cc13a3935b67d55d8707c98e349c8f77cb6143035633793be404d9b866165516f6b7e63bff18842922a183e32c27d941d1e1e97c482ceda6c2495e045333a766e279825550187b19f3
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	29	\\x42fa870ac333400d6f477c995e0cb2c2513aeee0765f96404ed50ecd09c213940b200a11e9e1f44701485f4679310f3ce36dc1b501ea43e9318b405cd0b98506	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x3004bce509d64b01e45eb51ed931f51b8c36b5737e5a0fa3fbd8ba3bc73e09dc4d307cd7cb3e490d8f8d7ee9c453ea8a1c76c7e63ede07485c7da046fa31f0e00e034c33a8b089181e91001b605d17d2019df5fcec03f7701e95e96b1b119262931cd7c2a79661e21174477d5dc361b94ae1b251f39e2eccc4a715f066ff273f	\\x0658c66ab6395c34eaf1f973aa6fe246b2b38fc0b302dc82bce7dee9849ae2f0ff0ba1e57f286afd573be79501b08862b5cda39f4c1bbc02d945a96cda96112e	\\xc4c039e6b4279f5bb79d9ae9672ffafa942df39156f3e02f117206473bf0a391ed7d00d91619dde33dfa583d46dd9c60cc158ca43e85ee9dfc61540e670aec21c873b12910e54cee364934091a048ed9bbbafc10a835aa78aa64f90d555c6ef424d58641e233cfac3f2868022435bf1ea0022a75d6819248bfaffff3fe62fd13
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	30	\\xa999c3a4abb9d0d965db9f6c75844e15b1239212fb51045c27f94f2402de1892d3b580a54f7ea0154f1f71505f3945173efbefe1938dd5a7fa523c064a9f7709	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x1f78e83f4b270a4b7513f2a575cdb58e86a188e59d73c588995a9c3c860a1f5347421f3049b1e4f322dfb9211e7845d6d14c77408d97f46756e2fcf9f1de5873fd05a3f43118a1db366ba22caa9e93365c5a6540436c6d2a35ffe5c421a61805c57d5028bc42597beeac82df642285726ffa6003000bf3f075b73b63c0b5a59f	\\x47ba6e8c2425c86a02970c6ed8356fc9f0e32e1f1d3a0ca40dd5eb2ee7a0de44a71cbcbd8af6d6361797e62d2b2507f10b2229a8267291fb0597320b1cc70b82	\\x938cbffd205212bf28923993040a82c8082143be5676aa2e1c42ed42e0fb206fec41faf7d19bdddea6834d9302adf9b76a3b59bfc305940e523855fd8e037828b070d70c2e42a53138d9fae694c30342e75dc5942975fed095b94c9043e5fa5026a4a203300a0ae49652edd77f3b95d673009b144680b808aa8f7e02f88c5e38
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	31	\\x494488cbd13c84c6c9649310a5e1498ca66d83277a67940b56e11193f8bb09b560a1988378ed65e8aa0c40bc7536933e90277fcddd026314e406ba66c3daac04	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x62991bdb3b82ac1fc12f48c09055e1e5d53388a6d86c8b536ad0503cc075bfbdc569b5243b4cad85cfaf5f3cb956282514e7afc63a1a980659fdf15b758d6e6c618c64b93aee4704c3cc5b04aaec7ba83ff65f97a9503fe7626717632ef96c4a3c50063e1f0b3a66202c36051fcee4d5fb7264847448826095ac456028b7130b	\\xd9dd66c239258882d988c55e6fe449886359ed4d4383117cb699ae19a0cb55ce9cb927e5b15766795572d951d85df6c0f6b999b3588ba39c470c3f98a6e2f8a2	\\xccb62c097e1bc6a59df0e56c4a53257560d78ce54c15ca95f9ab83bfdabfa8e9027eb3400f0b37d0b944b3707e8e2cfc6cd0816b698b7b7bfc27bdd22dd13652de63f2980a5a9b87171ef36dcc807f3578c78dac2fa9b93a0780eb8b27d7f2ad0403e38e22716de28402445f442e5ad03ff9454963d95986c53333304669f0b6
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	32	\\x2d56bccd3d6a6634788afc3c316f713b5faa32e1af0aa63efd9d78469d9cd2d6a310783e384d9b63a75f68c8ed4eaa6ac6cd33c1032259dee10f958fd9723406	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\xb6c12747b10aac5470ce2d8a2ba47e6f726846521ada775bd14e2c37b5538d532a142fc044ada8ff6c533ace2d8cd3e77eecc0c779e2371062d2abbac942d77baa14ad885403b1c81f27ecfc3d9ea0fba0532817fe69460c2d2f692f0273d392f5da414694da014606a39b237b2349536a0539932cbd4e166c27d80e36f3d50e	\\x5b5344282209cf3bbb4ba5b64ead871a9107d639b6392014dc5f1e3093d6342edb14e8fa15bc964a2f6375aef7f1a71768a4d3139c628217e72c118d48403864	\\x05081f576dbceef6b9acc4dee276dd6bc57a83fbda24da859d0b458f73053b5f7d5342d65eaf41669ab7d02b3b664b022dc2b7d5b7785014b8af95559711c5a004351a5c7478475d7ed45ff764ccc28bc7aa94198c184fa60cf81f20e60df0c008a68e65aa93199eba1d677410eb5ee9c08ba8d4e3e3d233d1c68643ca1e8ce2
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	33	\\x848f103c3558d0a382f672665ddf6fe5102c2f522d120552a5278c7cb281b1af5e68781f9d5fb8193300c31e02f6328389c1ba5c10f97d81fa11d7e7adb6dd01	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x7624373a8a08b705122dbb03686c93ef2fbf73b15593749c81677b933fa3cf62c76ee484f71bd1a7992787866f74c666ee50920eee02892d92610992bcfce0a6d732d33f707a37959ec76d7024647da24224642993569015e982b1c818a4d4cda7480c65ecfa04b9e6e677355c3b24bdfa43a127933bf9bcef838fda146aeb86	\\xc59b10e40610a7ad0f5313bad56248c0967123d1c76f4af83de8fef634dc5335c6c9a4e5cd11aff3e258a7969a388e597f39b5690fb040d022ddac479d2e21ec	\\x071e97fd5ca67cc5b8f1871b7cbf6a5787cb1514433c76f0253b8a0cc474a8a24071e995000f7bed3c04457f0d12cf9a3e811dfed246ee2d123204a39fad5fa0c17aa73b7d640258bd3a3ce5c7b26f5b72c549e8066602d0b58f68e76b097eb343d7de67ae872dfc2d6611cb023057922bace59d0fc91c15b3f5a7b8808ef202
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	34	\\x3dee91cf1b7ecb48f5a11dbf81c5c55192f7acd25cb7684a67c2a6cc0ff129452a0538dd47370dadfa4811cd5b287d018ef15149f13a13b7c2a253b4ef4f7d03	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x90993d7cbb547456a4f3468c1547d70c3029896274ae1d1a048c929e918993580d37a6d330bc80e132e71fa0d2fb5d91e6535bf1f815c2e5c3d76cdc17a3c57bbcb178a1abe032c1902beac111a9c3495b8ad2565030f9b353cb694bad069c2740cd06efc7e9a9e8c14a6adb764b9b28a5634aa97ad0fef0bc94555a3ec2c331	\\x35c7e8c0daba7e411dd9014834348638f41e6cb4a4747ea7c5fbe08d875659c348551f22e244514311f76b50bc1b0e056a2f48752bb416d7da917e49115a3d59	\\x45f24a2a86c41429eee6ced15cb19abfd05c0ff6be10998e7a55cad8247a52e5e98e73513e9b82ac48f3fa39b4275e24defe0ebb16ba87cc117a3551d475b88f766e23aa41f60c1b7e9b87dc49b84210a2cfaa6b70b7440a788e8d5c41cd9b34c7f29dc8f90b5da78b31a611e11ba94888a5bd0d48fdd553a2180cc2c2de1490
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	35	\\xc38d0f71fb0d6b4d174221ae88d54b510ca15bdeda4bb81292cc88c629df4923b58de5e93860359d4ff6ddf6cb172631cfc91bfda8a737e0e87082e7ec063401	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x2996ff4b2e9d0c7fb2e2f141fad11a12e035760700cb5612e5e46e35598b37a7a7a0fa19dcb96d3d92aa74ce4e5fb1d31c583a685a07bcfc3c549afb8fc71caed3f757d9f5ff6f800f32230ce74a303fe67c9f7d6edefa3fbc8415f5cb375a10b99207ea92ca83885c9d3d6509b24a5c2e4e71722665dde346dc49251c285cfd	\\x7103fd67668fa18fa904152dfeebbccb2a8cdf3e24a9da01eeb68ed2dfc7a950d4cbac2c339d609b46a366fc68a80e014d9c624950a326aa4d86893abb430d4e	\\x9de3c6a463b2d8c3e651789345e37870f4dad052942d77ed3659e19947f6c263e86b5755963546ae892400963b21ed3749fe4cf9a722bf9972613a48d167ec4c469499057ebedbdb1c707bda3a4acf22c54a736cc5ec710841ff5c715386175ec8de3708557f3f9286ef769c891398290865ec9b4c307b0bdfecb8fa30c96f95
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	36	\\xd6765d6e2a635abda11df4047bc48e94aefe4e52fb91cbbb196c38b7b8250295949403c96207623f06ebdb63bfa62f56eee3cc463a14de1fbec11ce360a54c05	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x83486f74a7fd84ea99b4734d6b4102c490a47389a4bced2a48ca3ce06bac916a95ddb7b3d13c036765d820a8c2481387a273ce62d532d02d569b3d89369c8c3878da27cee04399da99c32b45a8b814c06e4aaef6582d7cc4be94691439a8de0684c0ba2178cd46706784f29f0d9f208155dfeb82ba7b7cf866d233b497659efc	\\x21b9c3c7380cd0dd3709fd6e1bb053a7c8b457dd6f213f1b87d61d8afdb991060d344e13342560e1f8d0c5a707c29befea967b4783c85ee3593da392d50ae1f2	\\x7b6bdc2708dfa3e22a9fbfb1d436017949e6eef6d58594c066544b8561bcde03bb9196982e1c855520fbf88841bc87fadac5c416d33cc9fa58ed07543323f476ab03be130f6fec6c110221c0a993a3253a60c59dd6e6108fabdee6b4f25df9854f01441fd63b8ca43ce93ee3c86e3f9cb84f38a1289ee80e9b1b7e4985ccf043
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	37	\\x82cd4254f5f47eb0c91c0e3c696f7f1c4d750ed754039743f2fa8054385de8de553c5d917cf17a0b3845d516d7c6a6f668a476b007eaaeeab6aae394dd656f01	\\x39b0f9f10a7b76627350fabdea95466ca125326bed60267ac14eef91f87fe3a4afe1bc87c326d95697ff7fb73ed15e220fcf5544c536992ef1611c681f56ceef	\\x985576c3ce033ed495c97d27d800106657be18ef1f4c600004d16cb0f76ea2dd5094dce12a3a0ca5fddd50540d77546c26130e9f8aa2450678b4d3ec19fa202f6ae887523bee4c22435c85cb2b500aa254e8760411db25af92b2cb21abe7c757ac96e4c13b9d4efb9d0dc6d56a5d62e9c340f9f14efdb7cb2df18f656f8c8003	\\x9b92db2e455d1248ec933090da9e11dab37e54177fbae4abe459f31246f14b7dac6e5535d222e526e74de33db853a18de4db14cc42a277b4e1dfe30f92dc2a41	\\x68519966198b4e74950b22c17d654683017de79a792c9944c0c5a0eb886c6a48382b14fb654f44a765bceb33b8d6b34877130ec05cfd4f587c6c806f6651a034fe6dc07219420a8c9a2d05934130f70ebbe1b7b0e65bfeee4262a3ddb2cc857c629a3f2ed8bb7dab8a03543805487931809317e9ff2b61488eed8f827453a651
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xfa72cfb34239c73b622e08af8ee46132e8f2e006af7388fa1873cf820a1eb621a67b7f48fd5515dea56627bab7635aabd95b27f26b3771a1c59eb11611898fcb	\\x101b255e78ffd512ede55996ff037e4fb8933810cb7590fbe8b8839f9b860113	\\xf78d3afac4436fe0dce967eb3ca2309ecf17ac7759f5f0c0a1b0d126e72d39ebf4417779e70869693248fc8a6faac0ee1eacbfc3c50c12fecb1c2a7f9afc69b9
\\xc857183a4d326dbb887b7b14f38eabe650aaa149ff6150884bfd976852dd71b1f1150f38f35c2ab0d1f9f018fc0cd901bd75ee4b7b014daf9bf209df06a269c3	\\xe373e15d3acb7b7090450fb631db3ff79889b45244669d1cddc26861e5bb0878	\\xb59cac764b151a7595018190e703717588108f6f5e748c0922e0d259390c26def60dd73740faf45972e28ff72253b4f3bea8e197f2d542ac7cd22166ae20307f
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
\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	payto://x-taler-bank/localhost/testuser-tp3jiCPi	0	0	1610564428000000	1828897229000000
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
1	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	2	8	0	payto://x-taler-bank/localhost/testuser-tp3jiCPi	exchange-account-1	1608145220000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd87bb75e35828a4f4b8f2749fc82b6dddc12badf4b54c46e2fc3e4772ed94c5164d27ba492b5f7d9ae0931cefcc416e7a532aceb1fadb3786e8d293e50475230	\\x8a11c7f90a44d3d5b05b185f1a6d4b34abe1bee88509bf838385c2e5cfd0c0c72af08d347d0cf0e7845529d74ca09138d07e92528ebaf37700e5eff3b25605d3	\\x0349abb7ae4d65ee1a20917e0229e41844eb4db2c7a4ff530d06c5bb04d0c8a3a79a538176f943578c073d8bfedb25f84fcff6e4c0b37f5ff93c20f96dd44680b9acb1559f826c60914b238b50cf494ee53150c0cd1fe9dad4de9bf6d9f5e7226cd22d1f4f3ba7e19823c84f53ae905ebe7ba1e42ca162955e66c8f5f5acb11e	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x061ee41813ce02d18eecfe60c7786ae591b8cae4bf2f4980d5c5ea072cb6e34a5d8479b1eeb21624dd06f0059f09027a198d77d508b6ec5b45fc40ec32946e08	1608145222000000	5	1000000
2	\\xcd5c2e2f45c60e669f81b1a0681d06caf3b2f921fa0c52dbdc181ffed055fa0741165ad9a9e2b09a19758cc4b94acfbb7a9c6bfe791e28edd04eed956813ab12	\\x41545dca6a5d61f31920dc7bc487f4eeaa2e41c01d4b87c82ad58d5173ff1f720d2ce2c65e5b4d0aecace98e3334f28d8e7e82f4978d5c3256fcfd15e4f9764c	\\x22de40a8a93dbabfbbf6e528220a049f1b0db71e0055b05b8eb3f1c771129d048118d30841e2ae7dfeac59e68f28be3a6599808b72d9e11dae7f2a085f30a00fda30ec5b81945ba70d908b4804574b0d522a26c475eef5b61868a6d2cf2c5da058ef8869d26477aea4c0572b0f029372623e5f6bc54be324c1da1bda62e24a55	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x381f8cdee3e06d08715febafb3b5baceeec400a8d5e61b56757c31d884a5ecbb77023fa2220c174450a44dbbe49f443b59e7d88da6a69cfbf0d45fac654f9e08	1608145222000000	2	3000000
3	\\x19e8fbb0b30c8fe9a4498d746e56f830b234e463e23da61dad2d0a06582e3724933fc855409666b2b6548bbc7846ae3e1120a7fe635694c740b0182589930068	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x1723fc2c2b13e02002c92b0851c2f30248dd30b2267e2cf381374621a354985773de79668eaf1b4e55a0831ddb5bc8601d75b5ba1c96f2b563cbc8511b01d136303d40ff84290c6bc89ca899a5eb37ef8c4156563a1ea07847cde04e412b3754c41bbfff3d5f85e4ab092c03ec481dfc67239bacfe4ac64b14e6e801215c1be6	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x2979548edefaa3e20e7d5179532113d85f169ddfdb8c0804e14df6cc473895092799f9e3272e1f39e1d0a3534d2f56477f23fb890c7674cca75cf581b958e003	1608145222000000	0	11000000
4	\\x6bb919e3e639248ccae51337237a8a8464d45e6a3983cefe4ac5665543a1c3ee6b6e197632b52764ac469a12b125883a3025a137bbaebe86927f0a15e0850776	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x4486d52a0a5c826f692f569c6a8fdfeb12f4e6e52150512b13017c49e9640976f2917e9e592a5749d0405775b9d1c4a8ea48ae39e3d0d5b33b0b98a5f434e73cf7651f384c8b5beb0dd8436141e91682040322a8b684d23e0807f82d7d6205cb3e6b1b3e3615066609ce331b4fc325248ed4d178d26e5c2e58116463e901067c	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xab570e998ee6c0eac1f6393ad5bb0a463e03303f966dd7e3868458a023841eff5d58708d22c84e22362383979f667ac4cbfece28b570862b9f4353b8ea4b0402	1608145223000000	0	11000000
5	\\x8dde40b2363496b8f7c46e5af6877dd7bc1a576cb87c51f9df29e22fb58a0b27c4715e2466a13f25f6b46eb6c0a6e4d31860211bd353462426fd31aa12de97d9	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x051280183eff4fc6a64f33dc6d928094056f462815372a34448b1e60f6096eaa901056a19557ad5a74ec5a416a16477a19fec3dc7f760cfae2cfd64ca9468af617df83b395a8c195861eb195f02d5f7db966b60a16ed65d1ccd574024a7c9b843968b6b0cc025e772699686a3e3325e8c1ae8b0f58acb7e2d7a6fb9863737720	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xa353a8a4197de528a5d3277779f8a3d91220cf104be9bc1837f0efd4dbd75a62df4d85e744ee6763dfc55b64bc49e75b886e4d22e868d38a978410bd2c05d301	1608145223000000	0	11000000
6	\\xaa3abc008d9f59a63d251f6c32eb02d34984b0fac42dc7c800745d7c0b5d701d30f3c789e67d0b16aea4562d069db4f2a60b4926b58a4239aa0d8295b9016992	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\xb37250496fef2b15b22e3b79161f38955f0842ed0f9274a7f5bbc800759f11bc8cbf0ee9d2eed031f5b02063178eb23b0ebe3b6e55cec8984462b288a6b1ff91d64ee0e9eec0d53ff9c1e053b1ff86dbcede9c71554a3265fadb5bd2b7db73567e081183ffe6c844939126d9f5545156eb0d03e752aa352b42e1b4a9362dfb9b	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x5c056731f2f49db4f0ce22a638fe7bf2c8436ca574778b66f5e91d647545c485fc9362f1805a0fd02c3cb89e5e16585d184a7092a4dfc72a0e927db3ea4df205	1608145223000000	0	11000000
7	\\x16bcb5f71bd3e3322f6723f5becf048de3bf31f3aba97a2a6589e4c3879ab8e1cccc6cadfe7cd061174bd866ed46c4c97deea1734fff6758bb682d73bb696744	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x5ea0600285e6df52859187dfa2c1a1213c15e6104b829e2b12598349d798ecc8699081cf456f0af491934e06289ad2a437881a9895923ae3fbff712f09be2b1dc723afae07ccb81048b89a3fd711afa9076eeb1e88e9d237c3a8982d1801d5250b3bd61d39089a95c4f89d536e5377ee8495106778c54fa316a30f29b0fbac2e	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x154733895b96e9e4961cf95a68bcb948980d61ccfe1b6e319e81545330cfc66ee35da20300111ff148c62698999f7ff1bf965415d97c4a08afa0819d413fb40d	1608145223000000	0	11000000
8	\\xd2408fda9ebc5891d93ae2ebcc6e61fcb66f10ad6ac42340429d0764848f6fe619e03b7f89e2c9394ef4f4d478c1409b8359eb40dec599df3e71e4efdef6c7a0	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x064ac517bc69ad91d82ce08f0dccff69474dd833135ccfee41d34539099ae2dbc04fd68f09aed3f751378d4f1289b272d346266ea474bc8cfb96de97490679a9cbf7dc28412d24a424112d151d13ea90b0d763403c96530dcda2337ce8cb058417deb15ef4c2fce872463b90e11f86caed01de6fe7dfcafcf7530108c438bf04	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xafbb338519883a3759e99431dbbc74820028c968fa1486e1d04e10a6519c542b2de12e2eb3e41eccb6ddfcde2844c0ecd1a97a6a7233185338d64175acfe5409	1608145223000000	0	11000000
9	\\xb609075df3a7ecb4b8633528f4dd5a33ab621c18d639f3d3a2ea6545fd95322d90567d3d5df24513424de4d05de23ee21b40fa21abb10ba862c1d55de1228385	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x0f32ef95ad7ca0f288c1598844f3121ac8a7af17c68b0036859bea3b832e54173c2019170c044ab8a4405b7570aaa34f5956a8811e83fd7a280c5e67061bebcdb9a54d2407cb9482c89cef7ec9b234539adef1f91c2d4de6c8515f10ccadbb96a65145d5874d6a4a876529c8dbb006aa62f892b67b27a3fef1c2e34c7598257a	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xeb69627c2242f7b43ec00045c1af0d1e1278f0d99c9d01e1cbb2261c489684ec4fe4e45aff0e691d9efbff30d0866fa5fed9ffd08da85626b68437e3e43e2303	1608145223000000	0	11000000
10	\\xee848e54e02ecfd9e4ffb6735db6e3367d9d0a10342a6499936579cac8778cf16c6823b8e2d1654dcf670ca0d646a4306b19ee60abb33f861805be6d3ddc9c3e	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x9c81e2cd77a44315d8ed26b3032056639798fe3119ed252c7696a24ea031ddb0bf7fc8bc973039050f823e86b4a8bfd3acbfcc54c4274be7b288f9030a01db3c3f3c634475f47a734741142c17d0cc001c64ed94c36d5d92a20cfea641faea4c1a5b16f459fed37d468262984294e0a9af43f1f35b6978b900957e7226364097	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xa855c3facc067422ef4c82f9a437ceb172fdecfd0986497494774d52a5536a392b07292815f335d6a2b5c86508d580e8018be7ed74d08a640a6a752dccc49c08	1608145223000000	0	11000000
11	\\x75476d5a3d02b05a836ae0b0492327ff6307ae176479f2ee68e84c8f8c9b858bd54b59ac22051f1d4e50d4a70b13125535f9ec4460a370377d410a95ac9fbb95	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x330ed4007f3a341d2756d7656e29e8cb504a50e9c1f6d6711a01477356235366b2b45e3313bb4c759725e6df20420148a44d19f3cc669d0e559e53c87d5dbab9d1b9cac922479ee4146f0af45a56e4325a8df67358249ed3a81954266c782a9d0fd8ff2fc85c81b51fb92717b2b7a99240c2eaaa46c3a1d918353ca9f3bfb64b	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xa852548f7ebbe897ffe58cb49cb4b6b62fc18edf719448bfca1195b8031a718810f3feb0fd9952fc7ae36351c49d36721bed0b932054663d2e6d3c22addcd20b	1608145223000000	0	2000000
12	\\x19d0c36d30aa4301337cd9601f014b795191ab995685f3835e7645d14f4114bb999dc55f87b5b73117d4e23b819ca346d2ea437b9d76eccb04e8d93bab8c04f8	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\xa5f560aab3a9f95dd5f5176ad0e6c7005d852585379ec32297c212e4dcb368277a6d10d326408acecb6a1e8c8853b9b238ad3b90770d3c8a585f3992116622ea8d83ef7efe8d337964c0ccc4af603a7c9af869fe40af40452c43cc65d6f80196d0996e8a444b2f4cf7470ee6bb0183e29800405ff29ff87df946b71c0c8e6d6a	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x1ac1bb59a4680c2721c8bd6539a325538a3a51a0b597b04d308111064c388ca774730c8af950d8b55e41211968b6acbf5dc51cd068032bb3da6a525e45ffd606	1608145223000000	0	2000000
13	\\x7f11dc8be52380d58c4a291631669fd0adf0397ce7e957ee00577e1fb27df775f6fb09b4b373d595cb174312e91ecd3a6071323371325519d980a1c1547cc0fc	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x5f6b37039111f4b7e5a995b53a7c4adb304986c7b97e63003a318460234395905343ca95ec5f3c5a9b0e2afc4f893e0a78bd12d3df9953652c3a26d3ab53f5f1c826bc7c88d710f0f12af4fa9b31ff8ac77776b7c5b2e4d3cfd524839ae0e5a86166e880b5d25a6081bd506840bfb651b29d9ff740f581df1b54a73c03e9ddbc	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x1da1e156122b6ec63579cab58cc2817886b0f6c91b3d72aa28a33fea9b90755738f6894627c9f7f00d2198f43d4127be4cc5ac0975db843229fce0d39cf0a405	1608145223000000	0	2000000
14	\\x1ee6f2e018fa4d679cbb1c073b8a9c9704077158e2b8c339a84330e2cded642837216125e40b53f511d89421044d4c3ae6829b4ddfebf990ebe7098f3661a099	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x93a3555433961879861cf4a95e86720e7d896dbf360db54fd56d304f4ae24f5b1e905513acd787d2dc61eec1cb2eaa5d98909023298861d22f07333477916ff45032167a544bc4531872b2d9b2e0df1fcbb120bd0100ef192f981cdd1dd7e3e9159e7376953120bbe068f7b4fa2efeb665412034915a5a2b7a4cb3da8b927733	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x50681bb75f17a42bc8adb495dd557c46fafbbe0d5462938a9cf35edb5464effc43b37fb55b1b68de17057739cf88f10f49a782fc9090ceeefb79f2ecd8a79f04	1608145223000000	0	2000000
15	\\x405fd129f9b719308cff07f498013f6392d9b979a06f101198624c23860d05a25e8ccc0823b723feb615462154a777ff2bb0c45e1387a4f586b9593779b751a2	\\x24bb402ff946677c5803ab31e02c1202655a8467d98b9aa18baa2f9ca1b124da2da25a6e23bace9a3b5ed0a6892ac4bf2a5c6215c6efe039f9cee19bd0c9e56d	\\x179ebeadb68a9009205f116f93f130ffbd960e1947424ba0d4eaa722560f31bf48a7ef1076eddaf41bd42bc5809a1ed1b0914ae79b0193ab1d93b0675847baaec9d007c210a7f9ef7cf4bd5b8fa53b72b01308e485e0f078bcb00c2e12486ffb48becf3dcdd14377400a74cecc00b09432b8ea75343ec417c735e15fa48e8430	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x18930f03552425e232e48354f78c89eaef700e058ed4847a23d40c14af6cbd433a658bf0c72e5a8e1fa182d781c29cd3c6f75f6af033d7e365b7bf2835813c0a	1608145229000000	1	2000000
16	\\x48be4bd025448dabc0b26bcf4228eb599cc6a2ee8b021c6b6c2e7f45eaf24d6aaa89e4360ba7558a06d2f15d9556879ea17801dcf8bb388ba8ce843e8f8e0293	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x72cccbaad6b479232ed2a42f273eae59f12afd4a78ab3b9ce5349f23368595fbdedd794442e7865badc3b5ae01df361c4bb474996f1baf9066804fa29448a7a0ae501cebbd67dbcdb21fabeaa8cdc7028fe53fa5997ad06ab6bf9c7419cb43a9cb957432cae0616920c76173db5ae60b3b9760e34338ad15895af06d6410cbbd	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x87da8a563832945a28ce75eab99e53e75e61a76b56f4e5119a5dd89d1bcd5dc664a2bdc82f74aee322f26ff48a5addc46c0e0eb7ed06e69f528cc6491d86c300	1608145229000000	0	11000000
17	\\x5f58915b8b90b4db9ed48e1f1e05f25fc28ecf20b7f97a84fcfd44993432adf181f643919ed994102ad4f914f2add92623fceb0c497881e5d78b34a730474611	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x8673a1483641f347882d77d8bae5a69ff38bd11e34039ae0d474bafe0fcd8037ab7ffe89522e944b29a6dc252e57db9defbb3974a84ef33708ba37d26ffadc2c68b289c4ececccf01d5fc04aecdd24cb283e84373f81fac814237ab16e73ca51aea27118994f864cb943bff41a2da5e4306dd1613fdad0b2b506bdea4dc59266	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x27454f4188ff708887865f88d4e307f8e826d5e200d9fe883a73a6f2cb29f1ea153d6194472cb40977d816f599cde6f0c08b7c8c39591a8e92fb68bbe9802e0b	1608145229000000	0	11000000
18	\\x17442410e1a5d5a7c61a9b69dd7cb1acd47e928e6e0ef25685caf50c0d4cc17e26085bb57ed2dcb3faafdb778bd73b35e0cae0fdc034f6c69048a3f9572eb2d6	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x98775f825b5aea0d537fbcf3ba6a4d437c8d4bed78fbbcdc3f17d8e89a900ef8567d4d241e8f23f6d27d5a78e253ac7e2b77b4d56121483337b34d224e8ff6fd65ad41b54a2fd43688c476899ace38178dc3748c780e84d42c2afbefc2eb4ee3e93e07ef5a8623bd8b7649b4bd26aaa7c8439107dc6086f43d2bed3e436ffd0f	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xce845c79d4e6a3a70a0d4ad8dce73f81c4bbad4418129487edd67d26dd015b370ccebeb0a86585701759637fc9cb40cff7e14ced6ee58f0188e19d5a4c97a407	1608145229000000	0	11000000
19	\\x9d9ed66f249a06b81038e83130bebb6191371829280108032245f239dfb590adc198288411ae69c4842f6f5c5598b963e60826ca42e09697d1b3afb1707ffab9	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x12c0b2ca35d09ea2ac595c91ab70d52017e4a38a33d38298e70ecbf372c1120ba23095515d0de98ad0f75f396eb6aac9e4827800a4ad438eea97efe3a9d2cf69543cda2040de4dc0235a412f1019e6909243553c8918e844adf24820acc08eccf797b3e40adecf263b13dc11f096daa0c9cb239cf68d872f8ce8bf1aeb457824	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x7fed5f9c119b7db927e994a30e2a9bfa3b983932848d734658c4e5a29986d1dad01cdf9d63bc1b573ea02762680fc800038049f39ffd1e268be6f36cc56c830a	1608145229000000	0	11000000
20	\\xbbe9b5e7dabb05fbdb45b0b8dca7b0196ed0d7aa7c3b987a3ad4d7f89451582aba88753a479359578883f0fc84c7e816aacb48a783454413e5c64834b546d3e4	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x0a3e2ca4134a6fd6421ae99a61c6e13cebb38d736b4a58e936b53147ea7f203fa761b7ae78aaeaa29934178df01d06b8f0f348d89cdacbb1cedccc38204ba3b020799ffb96861d11fecf8899479d46df241ef6f65d543b8b17d03f4be37849246d82b654903d6e99008874b882f09cd6daf952a1b06100a7cedc8065a8681404	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x82b15ed2b8da49c085300a0249268710bbc064c9caaac0470654f93374b1c491386ec1b0cdae91c451c9b2620b1786918c69c3fe5ef5a2caaac5dc373fc6ea0a	1608145229000000	0	11000000
21	\\x45059204943832db8b250da4d5faaebd4afa82d56204d6a02791ad8da0f4a0e82b507f1270884beac1dd36bb09afe1bd184c026245ae75548228266b4fc14e5e	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\xc746ccfb32d6812a9ab9340593f7f8688c9032c361845e483c2b4c237179a2829496afd2a642dc8b72efd564633ce965d0780f00add27bae00182cb8b25bd46d495869febfd8e776ae78b6ab0a93087693727e1f78b31bd24f6f367ce46c742a982ac06825d045be987fd15d88e94783d44a0b98040f4aa22870d2b0af6738f2	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x43895e889c11f5539001f328189338bb7ec45740c745dd47e4f2ddfb496cfd2fe2a96362e1c55a255d9b79c37da723f0d284de0de523ae7e34cca89ca433a102	1608145229000000	0	11000000
22	\\xd839a917872ee36d6a442c3df0a28d702b538d0cdffcf9e79a65acff5ea8b6355bb136c0c1b5cf49fa3f1ebf4d76b81e8b74397bdebd4934a8ae0df32ed1d001	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x46164e9714e30ecdf73eadfe0c59e552c1c406e80c36929c86cb74909407dbd1a94f8d4e2840da76b58e411760a431ae67815110ee14e9d0004031a34b403682f52339b7bbe74159e61d45b28fce666bcc8cea7f56c70437af7edb02d2e93e9a8e8bd9d2c3ecc4f818b7f415d99e064df5208bf89517824fb907f8f24122d9a5	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xa0069284576d65230988e9edcd2b007565d3167495e5bc3465398d0ae7d05e17b94513e45c2577e99e31ec05409f9aa23edd4a92793de7c4bb73ce4b6147bd06	1608145229000000	0	11000000
23	\\x7803ef59008cf46128216d262ce2f434b1dfaeb15490708364402b7059f808d6e9228b6df80748e2aaf252e12e5403d7a58fa9702a5b3b0674f9599f342008d2	\\x0a39879c24396c502ec8bc1c20734735c6a20d107e0f358cf439e57eb6903a8fefcfe7ed379860dc955bbc6c8de9d5f93a61a91d3bf8e7ffb1940b9730a8f4de	\\x2e482d8690e28a41549bde4bd0de791a504cef8f86a001ee034fd1511281ade120e40d995b4c25086fca540230b20cd84924103b27b055efd36b18275597e0a1687224beb5eb0871e02edfa29c0e85403d675d4e6b0a8d97013741487f2491cc4abece6217908c9741e4c18c1d3a6ea6b64651c68923ca0f11786857c4b6b54f	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x12cc6a9efd5e792b80dd64abf3b367c67c762e877b0bff1d98a7fd33db0b021ac046ddb94494ae8486d6491ebf9fa994e889d56efaea634098376db34cbd7b0d	1608145229000000	0	11000000
24	\\xa31dc66ab49fa11a5c61127f63b9a5d69945177f21f141d8c367f135046af56cd4be5f0221bff32c40db1b91584e3f4e581456902d560e813552516b09262b1b	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x3a13b7c817e19db438e072a47c0fad0bb23cddc2491038c25eb4c9ad6a4152612e8b7f84b7e72b93107a0c236d4ec7b5c3416c09b934fed5435a31a9454ba1e13bd805681264a321562b0a960a16c89bdc83254c5b87ab4794f01b115d2ac6cde9b1e5180ed99cda2f8fb857abbe012d9bf3a1ee4861c7ea85452dc7d32b8555	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x31946954c9bc92d7594e1b9c08cc312e20451965a1bad289b769ce30213b1ed2bbbe809ca033d87e8419598d7c903a39beabba1d8954beb06b33f8339561af0c	1608145229000000	0	2000000
25	\\x7891f1bfabcbe0f5ebbd3800c2805c446f78a847331974e2d92dce5f36a8c1cef22377411ed96030d07a34865feb9f82ca8715c09aa7c180bb91e07ccc499d43	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x44f839c50530c4102c7dfd446039905323556999fb8bd3f291b5d2d1f4d495812e8cb170b2046d5d1bac5caf4536546c2b2f2b20b58bcf59c98d99f4e51d70f50f1751916b59ec5f28ce4fb9b4edbdafe417696c77ceaf9a6c04682f67993888a183e2dfb54b3c9fcb4b0c594e1b7c0c3c72a9cfa8231b46f2c3e66943593f54	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x31e487b916708d979f6bbbadc3b3bc66c3876aba650291ee424bf2dae0469e2e1c50d09fc682c7e53e0bdaf83002d5654e8381305835447a9c379e895df5db0c	1608145229000000	0	2000000
26	\\x64d11c371627ff22302669bc92fb8895a609a6341b3b944e5266e120ee81648f7ec2e133dfb5356cee6f6f30e75b2dac6df693b6af05dd1ebdf0156ef5a36026	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x1c41d4bbe18496d6b240d9ecea532d9061e2e67c7b823b3c667adb3e8d14adb1c4b28aaf4aa938943adac6e086a6ec2c50f81ea71e76ae767abfb26a5a04a331937c212f00b9194e691c1b32d27d4b61ddd09118a24d8a71b564d930907e6f3f32f6347ba3e62bf282af885531a59e48393d15e6a34c04610a07e0da86d6296c	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x52c0b399e686c40edaf1f0309c129421c688fbc657782e80b287090b07b108a0daefdf4c22557e3f5df17031d05d7b8bf2860768aebfd8a535038e4d0ca0ea06	1608145229000000	0	2000000
27	\\xcf34272d92354aec8de174e5a3ab0fe44eeeef92a0494b37ac10faf813efb560d485bd3d9270d168e1800ce07ffed0271a9e7bdb1e01796734a7b209605067b3	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\x53989fc3ccd630e0a8f669369b023bf86f748a4fe8093e9092dd33ad65645bfbb174834963cdb234a7d6305ac54864dc873d6a6f5cd86af880ad6ed62db0822407fc5edbb0156d2889c8200b129a74ccbd2cb38b8972525d8559283587ffa172e31b98cd4c5896f1e41cfe5509a973a84cd9dbef39e0c7db1e92e1e31580e0d1	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\x2a2c6fa1feb1f976897f0deab5517f55f630cc10a789c3d5850be41d6cc20e343e4f9fe47d2f79db42231db71de4709e7272c92eb8f53edc89c042fc8edb900a	1608145229000000	0	2000000
28	\\xa44e8f315a0a31b924d0271f32275faecee9bb5344b9254fc3600d7c4d9d38c29bd1ccb9c91ef5954689fed05e9d72f3c8c88e257b4a483900b208052f73822b	\\x9de2138b4ad6a9beead7565946727d75190d2eb392ecbd28e7228557095bc8eb9b68601b55591090d0350cf9e3a5c6de68c9b23bd6d83a48cd24e09faa3d30f3	\\xa442219d4bd2ff214a978198c1cc5137c7ae04e45e5ac5857860e1e85746e55d1b45e7bcb3b0a74fafc9ff055baff5073dccdc58e66dc3a48959d49233e599b21d3ff9ee86f73faeb61017a567b0e670372572a4787709293d54580d19d34a1d0cd7a73af0d4894723001d0e5a9dd0f48d4bb58589553fab3bb889839e376670	\\x7a4b7ddbbfc25cfe999bdad0052f85524bfc2a09555236df1ce39be32ce07b27	\\xbfdd10e7c389b7ca2628554b8c84bb2b1f4f258c7581575048c6edda92235ab18c34fd1842fe8aa74734b2b48fbf2a43f2cc0afd42d41a792231e4598329ee08	1608145229000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x069337e632c4f1c3b3ebd709e5ddd8d62b070d674e8dc2661db811809fd2b8acab9d3b57ea85662ab234c806a474e15d5e944ffd3792e513eaa1c86bdcc1c10a	t	1608145213000000
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
x-taler-bank	1577833200000000	1609455600000000	0	1000000	0	1000000	\\xaa94551bad1636112cb271ce96f2cf454356810bb643f435098950dece5069f2913ffc74e9bff43bf3a1ed370ca201b57632d560b004cc0760d1e957b3ee8b0a
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


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

